using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>Sổ seri máy: gợi ý seri đang trong kho khi bán, tra cứu tồn kho theo seri.</summary>
[ApiController]
[Route("api/pos/serials")]
[Authorize]
public class PosSerialsController(ZKTecoDbContext dbContext) : AuthenticatedControllerBase
{
    /// <summary>Seri đang trong kho của một mặt hàng — gợi ý khi bán.</summary>
    [HttpGet("available")]
    [RequireAnyModulePermission(ModulePermissionAction.View, "PosSell", "PosSaleOrders")]
    public async Task<ActionResult<AppResponse<object>>> Available(
        [FromQuery] Guid productId, [FromQuery] string? q)
    {
        var storeId = RequiredStoreId;
        var query = dbContext.PosProductSerials.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.ProductId == productId && x.Deleted == null &&
                        x.Status == PosSerialStatus.InStock && x.TransferId == null);
        var bctx = ZKTecoADMS.Api.Controllers.Base.BranchScopeExtensions.BranchContext(HttpContext);
        if (bctx is { StoreUsesBranches: true })
            query = query.InBranch(bctx.CurrentBranchId ?? bctx.HeadquarterBranchId, bctx.HeadquarterBranchId);
        if (!string.IsNullOrWhiteSpace(q))
        {
            var s = PosSerialRegistry.Normalize(q);
            query = query.Where(x => x.SerialNumber.Contains(s));
        }
        var items = await query.OrderBy(x => x.ReceivedDate).ThenBy(x => x.SerialNumber)
            .Select(x => x.SerialNumber).Take(30).ToListAsync();
        var inStock = await dbContext.PosProductSerials.AsNoTracking().CountAsync(x =>
            x.StoreId == storeId && x.ProductId == productId && x.Deleted == null &&
            x.Status == PosSerialStatus.InStock);
        return Ok(AppResponse<object>.Success(new { items, inStock }));
    }

    /// <summary>Sổ seri: tìm theo seri / mã thẻ / IMEI / tên hàng, lọc theo trạng thái; kèm đếm theo trạng thái.</summary>
    [HttpGet]
    [RequireAnyModulePermission(ModulePermissionAction.View, "PosPurchaseReceipts", "PosProducts", "PosWarranty")]
    public async Task<ActionResult<AppResponse<object>>> List(
        [FromQuery] string? search, [FromQuery] string? status, [FromQuery] Guid? productId,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 10, 200);
        var baseQ = dbContext.PosProductSerials.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.Deleted == null);
        if (productId.HasValue) baseQ = baseQ.Where(x => x.ProductId == productId);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = PosSerialRegistry.Normalize(search);
            var fold = ZKTecoADMS.Application.Helpers.VnSearch.FoldText(search);
            var nameIds = await dbContext.PosProducts.AsNoTracking()
                .Where(p => p.StoreId == storeId &&
                            (ZKTecoADMS.Application.Helpers.VnSearch.Has(p.Name, fold) ||
                             ZKTecoADMS.Application.Helpers.VnSearch.Has(p.ProductCode, fold)))
                .Select(p => p.Id).Take(200).ToListAsync();
            baseQ = baseQ.Where(x => x.SerialNumber.Contains(s) ||
                                     (x.TagCode != null && x.TagCode.Contains(s)) ||
                                     (x.Imei != null && x.Imei.Contains(s)) ||
                                     nameIds.Contains(x.ProductId));
        }
        var counts = await baseQ.GroupBy(x => x.Status).Select(g => new { g.Key, N = g.Count() }).ToListAsync();

        var q = baseQ;
        if (!string.IsNullOrWhiteSpace(status) && Enum.TryParse<PosSerialStatus>(status, true, out var st))
            q = q.Where(x => x.Status == st);
        var total = await q.CountAsync();
        var rows = await q.OrderByDescending(x => x.UpdatedAt ?? x.ReceivedDate).Skip((page - 1) * pageSize).Take(pageSize)
            .ToListAsync();

        var pids = rows.Select(r => r.ProductId).Distinct().ToList();
        var rids = rows.Where(r => r.ReceiptId.HasValue).Select(r => r.ReceiptId!.Value).Distinct().ToList();
        var oids = rows.Where(r => r.SaleOrderId.HasValue).Select(r => r.SaleOrderId!.Value).Distinct().ToList();
        var products = await dbContext.PosProducts.AsNoTracking().Where(p => pids.Contains(p.Id))
            .ToDictionaryAsync(p => p.Id, p => p.Name);
        var receipts = await dbContext.PosStockReceipts.AsNoTracking().Where(r => rids.Contains(r.Id))
            .ToDictionaryAsync(r => r.Id, r => r.ReceiptNo);
        var orders = await dbContext.PosSaleOrders.AsNoTracking().Where(o => oids.Contains(o.Id))
            .ToDictionaryAsync(o => o.Id, o => new { o.OrderNo, o.CustomerName });

        var branchNames = (await ZKTecoADMS.Infrastructure.Services.BranchStockService.GetStoreBranchesAsync(dbContext, storeId))
            .ToDictionary(b => b.Id, b => b.Name);
        var items = rows.Select(x => new
        {
            x.Id, x.SerialNumber, x.Imei, x.TagCode, Status = x.Status.ToString(), x.ProductId,
            ProductName = products.GetValueOrDefault(x.ProductId),
            InTransit = x.TransferId != null,
            BranchName = x.BranchId.HasValue ? branchNames.GetValueOrDefault(x.BranchId.Value) : null,
            ReceiptNo = x.ReceiptId.HasValue ? receipts.GetValueOrDefault(x.ReceiptId.Value) : null,
            OrderNo = x.SaleOrderId.HasValue ? orders.GetValueOrDefault(x.SaleOrderId.Value)?.OrderNo : null,
            CustomerName = x.SaleOrderId.HasValue ? orders.GetValueOrDefault(x.SaleOrderId.Value)?.CustomerName : null,
            x.ReceivedDate, x.SoldDate, x.CostPrice, x.Note,
        }).ToList();
        return Ok(AppResponse<object>.Success(new
        {
            items, total, page, pageSize,
            counts = new
            {
                inStock = counts.Where(c => c.Key == PosSerialStatus.InStock).Sum(c => c.N),
                sold = counts.Where(c => c.Key == PosSerialStatus.Sold).Sum(c => c.N),
                removed = counts.Where(c => c.Key == PosSerialStatus.Removed).Sum(c => c.N),
                missing = counts.Where(c => c.Key == PosSerialStatus.Missing).Sum(c => c.N),
            },
        }));
    }

    /// <summary>Vòng đời một máy: nhập kho → bán → bảo hành.</summary>
    [HttpGet("{id:guid}")]
    [RequireAnyModulePermission(ModulePermissionAction.View, "PosPurchaseReceipts", "PosProducts", "PosWarranty")]
    public async Task<ActionResult<AppResponse<object>>> Detail(Guid id)
    {
        var storeId = RequiredStoreId;
        var x = await dbContext.PosProductSerials.AsNoTracking()
            .FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);
        if (x == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy seri"));
        var product = await dbContext.PosProducts.AsNoTracking().Where(p => p.Id == x.ProductId)
            .Select(p => new { p.Name, p.ProductCode }).FirstOrDefaultAsync();
        var receipt = x.ReceiptId.HasValue
            ? await dbContext.PosStockReceipts.AsNoTracking().Where(r => r.Id == x.ReceiptId)
                .Select(r => new { r.ReceiptNo, r.ImportDate, SupplierName = r.Supplier != null ? r.Supplier.Name : null })
                .FirstOrDefaultAsync()
            : null;
        var order = x.SaleOrderId.HasValue
            ? await dbContext.PosSaleOrders.AsNoTracking().Where(o => o.Id == x.SaleOrderId)
                .Select(o => new { o.OrderNo, o.CustomerName, o.SaleDate }).FirstOrDefaultAsync()
            : null;
        var warranties = await dbContext.PosProductWarrantyRegistrations.AsNoTracking()
            .Where(w => w.StoreId == storeId && w.Deleted == null && w.SerialNumber.ToUpper() == x.SerialNumber)
            .OrderByDescending(w => w.SaleDate)
            .Select(w => new { w.Id, Status = w.Status.ToString(), w.SaleDate, w.WarrantyExpiry, w.WarrantyMonths, w.Note })
            .Take(10).ToListAsync();
        return Ok(AppResponse<object>.Success(new
        {
            x.Id, x.SerialNumber, x.Imei, x.TagCode, Status = x.Status.ToString(), x.CostPrice, x.Note,
            x.ReceivedDate, x.SoldDate, product, receipt, order, warranties,
        }));
    }
}
