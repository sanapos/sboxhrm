using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Đối soát kho: so tồn tổng với tổng các lô, số seri trong kho, tồn các chi nhánh và số giữ chỗ của đơn nháp.
/// Chỉ đọc (trừ «sửa giữ chỗ») — giúp thấy dữ liệu lệch trước khi xử lý bằng kiểm kê / phiếu.
/// </summary>
[ApiController]
[Route("api/pos/stock/reconcile")]
[Authorize]
public class PosStockReconcileController(ZKTecoDbContext db) : AuthenticatedControllerBase
{
    private const decimal Eps = 0.0001m;

    public record Row(Guid ProductId, string ProductCode, string ProductName, string Kind,
        decimal OnHand, decimal Compared, decimal Diff, string Hint);

    /// <summary>Số giữ chỗ lẽ ra của từng hàng = tổng nhu cầu của các đơn nháp còn mở.</summary>
    private async Task<(Dictionary<Guid, decimal> needs, string? error)> ExpectedReservedAsync(Guid storeId)
    {
        var drafts = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == storeId && o.Deleted == null && o.Status == PosSaleOrderStatus.Draft)
            .Select(o => o.Id).ToListAsync();
        if (drafts.Count == 0) return ([], null);
        var lines = await db.PosSaleOrderLines.AsNoTracking()
            .Where(l => drafts.Contains(l.SaleOrderId) && l.Deleted == null)
            .Select(l => new { l.ProductId, l.Qty, l.VariantId, l.UnitId, l.ToppingsJson })
            .ToListAsync();
        var inputs = PosSaleStockHelper.ExpandStockInputsWithToppings(
            lines.Select(l => (l.ProductId, l.Qty, l.VariantId, l.UnitId, l.ToppingsJson)).ToList());
        return await PosSaleStockHelper.ComputeDraftReserveNeedsAsync(db, storeId, inputs);
    }

    [HttpGet]
    [RequireModulePermission("PosStockCounts", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Report()
    {
        var storeId = RequiredStoreId;
        var products = await db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && p.ProductType == PosProductType.Goods)
            .Select(p => new { p.Id, p.ProductCode, p.Name, p.OnHandQty, p.ReservedQty, p.TrackExpiry, p.RequiresSerial })
            .ToListAsync();
        var variantProducts = (await db.PosProductVariants.AsNoTracking()
            .Where(v => v.StoreId == storeId && v.Deleted == null && v.IsActive)
            .Select(v => v.ProductId).Distinct().ToListAsync()).ToHashSet();
        var rows = new List<Row>();

        // 1) Tồn tổng ↔ tổng các lô (hàng theo dõi hạn dùng, không biến thể)
        var lotSums = await db.PosStockLots.AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null && l.IsActive &&
                        l.Status == PosStockLotStatus.Active && l.VariantId == null)
            .GroupBy(l => l.ProductId).Select(g => new { g.Key, Qty = g.Sum(x => x.QtyOnHand) })
            .ToDictionaryAsync(x => x.Key, x => x.Qty);
        foreach (var p in products.Where(p => p.TrackExpiry && !variantProducts.Contains(p.Id)))
        {
            var lots = lotSums.GetValueOrDefault(p.Id);
            if (Math.Abs(p.OnHandQty - lots) > Eps)
                rows.Add(new Row(p.Id, p.ProductCode, p.Name, "lot", p.OnHandQty, lots, p.OnHandQty - lots,
                    "Tồn tổng khác tổng các lô — kiểm kê để cân bằng lô"));
        }

        // 1b) Từng chi nhánh: tồn chi nhánh ↔ tổng lô của chi nhánh (hàng theo dõi hạn dùng)
        var branchList = await BranchStockService.GetStoreBranchesAsync(db, storeId);
        var hqId = BranchStockService.ResolveHeadquarter(branchList);
        var trackIds = products.Where(p => p.TrackExpiry && !variantProducts.Contains(p.Id)).Select(p => p.Id).ToList();
        if (branchList.Count > 1 && trackIds.Count > 0)
        {
            var lotRows = await db.PosStockLots.AsNoTracking()
                .Where(l => l.StoreId == storeId && l.Deleted == null && l.IsActive &&
                            l.Status == PosStockLotStatus.Active && l.VariantId == null && trackIds.Contains(l.ProductId))
                .Select(l => new { l.ProductId, l.BranchId, l.QtyOnHand }).ToListAsync();
            var byProdBranch = lotRows
                .GroupBy(l => (l.ProductId, Branch: l.BranchId ?? hqId))
                .ToDictionary(g => g.Key, g => g.Sum(x => x.QtyOnHand));
            foreach (var b in branchList)
            {
                var bq = await BranchStockService.GetBranchQtyAsync(db, storeId, b.Id, hqId, trackIds);
                foreach (var p in products.Where(p => trackIds.Contains(p.Id)))
                {
                    var have = bq.GetValueOrDefault((p.Id, (Guid?)null));
                    var lots = byProdBranch.GetValueOrDefault((p.Id, (Guid?)b.Id));
                    if (Math.Abs(have - lots) > Eps)
                        rows.Add(new Row(p.Id, p.ProductCode, p.Name, "lotbranch", have, lots, have - lots,
                            $"Chi nhánh «{b.Name}»: tồn khác tổng lô — kiểm kê tại chi nhánh để cân bằng lô"));
                }
            }
        }

        // 2) Tồn tổng ↔ số seri trong kho (hàng bắt buộc seri đã quản lý trong sổ)
        var serialCounts = await db.PosProductSerials.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.Status == PosSerialStatus.InStock)
            .GroupBy(x => x.ProductId).Select(g => new { g.Key, N = g.Count() })
            .ToDictionaryAsync(x => x.Key, x => (decimal)x.N);
        var trackedIds = (await db.PosProductSerials.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null).Select(x => x.ProductId).Distinct().ToListAsync()).ToHashSet();
        foreach (var p in products.Where(p => p.RequiresSerial && trackedIds.Contains(p.Id) && !variantProducts.Contains(p.Id)))
        {
            var n = serialCounts.GetValueOrDefault(p.Id);
            if (Math.Abs(p.OnHandQty - n) > Eps)
                rows.Add(new Row(p.Id, p.ProductCode, p.Name, "serial", p.OnHandQty, n, p.OnHandQty - n,
                    "Tồn khác số seri trong kho — dùng «Kiểm kho theo mã»"));
        }

        // 3) Chi nhánh: tồn trụ sở tính ngược không được âm
        var branchRows = await db.PosBranchStocks.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.VariantId == null)
            .GroupBy(s => s.ProductId).Select(g => new { g.Key, Sum = g.Sum(x => x.Qty) })
            .ToDictionaryAsync(x => x.Key, x => x.Sum);
        if (branchRows.Count > 0)
        {
            var transit = await BranchStockService.GetInTransitAsync(db, storeId, null);
            foreach (var p in products.Where(p => branchRows.ContainsKey(p.Id)))
            {
                var inTransit = transit.Where(kv => kv.Key.Item1 == p.Id).Sum(kv => kv.Value);
                var hq = p.OnHandQty - branchRows[p.Id] - inTransit;
                if (hq < -Eps)
                    rows.Add(new Row(p.Id, p.ProductCode, p.Name, "branch", p.OnHandQty, branchRows[p.Id] + inTransit, hq,
                        "Tồn các chi nhánh + hàng đang chuyển vượt tồn tổng — trụ sở bị âm"));
            }
        }

        // 4) Giữ chỗ ↔ đơn nháp
        string? reservedNote = null;
        var (needs, err) = await ExpectedReservedAsync(storeId);
        if (err != null) reservedNote = err;
        else
        {
            foreach (var p in products)
            {
                var want = needs.GetValueOrDefault(p.Id);
                if (Math.Abs(p.ReservedQty - want) > Eps)
                    rows.Add(new Row(p.Id, p.ProductCode, p.Name, "reserved", p.ReservedQty, want, p.ReservedQty - want,
                        p.ReservedQty > want ? "Đang giữ chỗ nhiều hơn nhu cầu đơn nháp (kẹt tồn khả dụng)" : "Giữ chỗ thiếu so với đơn nháp"));
            }
        }

        var items = rows.OrderBy(r => r.Kind).ThenBy(r => r.ProductName).Take(1000).ToList();
        return Ok(AppResponse<object>.Success(new
        {
            items,
            counts = new
            {
                lot = rows.Count(r => r.Kind == "lot"),
                lotbranch = rows.Count(r => r.Kind == "lotbranch"),
                serial = rows.Count(r => r.Kind == "serial"),
                branch = rows.Count(r => r.Kind == "branch"),
                reserved = rows.Count(r => r.Kind == "reserved"),
            },
            reservedNote,
            checkedProducts = products.Count,
        }));
    }

    /// <summary>Đặt lại số giữ chỗ về đúng nhu cầu của các đơn nháp còn mở (xả giữ chỗ bị kẹt).</summary>
    [HttpPost("fix-reserved")]
    [RequireModulePermission("PosStockCounts", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<object>>> FixReserved()
    {
        var storeId = RequiredStoreId;
        var (needs, err) = await ExpectedReservedAsync(storeId);
        if (err != null) return BadRequest(AppResponse<object>.Fail("Không tính được nhu cầu đơn nháp: " + err));
        db.ChangeTracker.Clear();
        var needIds = needs.Keys.ToList();
        var products = await db.PosProducts.AsTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null && (p.ReservedQty != 0 || needIds.Contains(p.Id)))
            .ToListAsync();
        var fixedCount = 0;
        foreach (var p in products)
        {
            var want = needs.GetValueOrDefault(p.Id);
            if (Math.Abs(p.ReservedQty - want) <= Eps) continue;
            p.ReservedQty = want;
            p.UpdatedAt = DateTime.UtcNow;
            p.UpdatedBy = CurrentUserEmail;
            fixedCount++;
        }
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { fixedCount }));
    }
}
