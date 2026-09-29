using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// Tồn kho theo chi nhánh.
///  • Chi nhánh thường: lưu trong PosBranchStocks.
///  • Trụ sở: tổng tồn sản phẩm − Σ chi nhánh khác − hàng đang chuyển (phiếu «Đã gửi»).
/// Nhờ vậy dữ liệu trước khi dùng chi nhánh tự thuộc trụ sở và tổng luôn khớp.
/// </summary>
public static class BranchStockService
{
    /// <summary>
    /// Quyền Thêm / Sửa / Xóa tại chi nhánh: quản lý chi nhánh (hoặc chi nhánh cha) → được;
    /// có dòng phân quyền chi nhánh phủ chi nhánh này → theo cờ; không có dòng nào → được (quyền đến từ vai trò / phòng ban).
    /// </summary>
    public static async Task<bool> CanActOnBranchAsync(
        ZKTecoDbContext db, Guid userId, Guid storeId, Guid? branchId,
        ZKTecoADMS.Application.Interfaces.BranchAction action, CancellationToken ct = default)
    {
        if (branchId == null) return true;
        var parents = await db.Branches.AsNoTracking()
            .Where(b => b.StoreId == storeId && b.Deleted == null)
            .Select(b => new { b.Id, b.ParentBranchId, b.ManagerId })
            .ToDictionaryAsync(b => b.Id, ct);
        var chain = new List<Guid>();
        for (Guid? cur = branchId; cur != null && parents.ContainsKey(cur.Value) && !chain.Contains(cur.Value);
             cur = parents[cur.Value].ParentBranchId)
            chain.Add(cur.Value);

        var employeeId = await db.Employees.AsNoTracking()
            .Where(e => e.ApplicationUserId == userId && e.StoreId == storeId)
            .Select(e => e.Id)
            .FirstOrDefaultAsync(ct);
        if (employeeId != Guid.Empty && chain.Any(id => parents[id].ManagerId == employeeId)) return true;

        var perms = await db.BranchPermissions.AsNoTracking()
            .Where(bp => bp.UserId == userId && bp.IsActive && (bp.StoreId == storeId || bp.StoreId == null))
            .Select(bp => new { bp.BranchId, bp.IncludeChildren, bp.CanCreate, bp.CanEdit, bp.CanDelete })
            .ToListAsync(ct);
        var covering = perms.Where(p =>
                p.BranchId == null ||
                p.BranchId == branchId ||
                (p.IncludeChildren && chain.Contains(p.BranchId.Value)))
            .ToList();
        if (covering.Count == 0) return true;
        return covering.Any(p => action switch
        {
            ZKTecoADMS.Application.Interfaces.BranchAction.Create => p.CanCreate,
            ZKTecoADMS.Application.Interfaces.BranchAction.Edit => p.CanEdit,
            _ => p.CanDelete,
        });
    }

    public sealed record BranchInfo(
        Guid Id, string Code, string Name, Guid? ParentBranchId, bool IsHeadquarter, bool IsActive, int SortOrder);

    public static async Task<List<BranchInfo>> GetStoreBranchesAsync(
        ZKTecoDbContext db, Guid storeId, CancellationToken ct = default)
    {
        return await db.Branches.AsNoTracking()
            .Where(b => b.StoreId == storeId && b.Deleted == null)
            .OrderByDescending(b => b.IsHeadquarter).ThenBy(b => b.SortOrder).ThenBy(b => b.CreatedAt)
            .Select(b => new BranchInfo(b.Id, b.Code, b.Name, b.ParentBranchId, b.IsHeadquarter, b.IsActive, b.SortOrder))
            .ToListAsync(ct);
    }

    /// <summary>Trụ sở = chi nhánh đánh dấu trụ sở; không có thì chi nhánh gốc đầu tiên.</summary>
    public static Guid? ResolveHeadquarter(IReadOnlyList<BranchInfo> branches)
    {
        if (branches.Count == 0) return null;
        return (branches.FirstOrDefault(b => b.IsHeadquarter && b.IsActive)
                ?? branches.FirstOrDefault(b => b.IsHeadquarter)
                ?? branches.FirstOrDefault(b => b.ParentBranchId == null && b.IsActive)
                ?? branches[0]).Id;
    }

    /// <summary>Số lượng đang trên đường theo (sản phẩm, biến thể).</summary>
    public static async Task<Dictionary<(Guid, Guid?), decimal>> GetInTransitAsync(
        ZKTecoDbContext db, Guid storeId, IReadOnlyCollection<Guid>? productIds = null, CancellationToken ct = default)
    {
        var q = db.PosStockTransferLines.AsNoTracking()
            .Where(l => l.Transfer!.StoreId == storeId && l.Transfer.Status == PosStockTransferStatus.Sent);
        if (productIds != null) q = q.Where(l => productIds.Contains(l.ProductId));
        var rows = await q.GroupBy(l => new { l.ProductId, l.VariantId })
            .Select(g => new { g.Key.ProductId, g.Key.VariantId, Qty = g.Sum(x => x.Qty) })
            .ToListAsync(ct);
        return rows.ToDictionary(r => (r.ProductId, r.VariantId), r => r.Qty);
    }

    /// <summary>
    /// Tồn của 1 chi nhánh cho các sản phẩm (null = mọi sản phẩm của cửa hàng).
    /// Khóa (productId, variantId) — variantId null là tồn cấp sản phẩm.
    /// </summary>
    public static async Task<Dictionary<(Guid, Guid?), decimal>> GetBranchQtyAsync(
        ZKTecoDbContext db, Guid storeId, Guid branchId, Guid? headquarterId,
        IReadOnlyCollection<Guid>? productIds = null, CancellationToken ct = default)
    {
        if (branchId != headquarterId)
        {
            var q = db.PosBranchStocks.AsNoTracking().Where(s => s.StoreId == storeId && s.BranchId == branchId);
            if (productIds != null) q = q.Where(s => productIds.Contains(s.ProductId));
            var rows = await q.Select(s => new { s.ProductId, s.VariantId, s.Qty }).ToListAsync(ct);
            var d = new Dictionary<(Guid, Guid?), decimal>();
            foreach (var r in rows) d[(r.ProductId, r.VariantId)] = (d.TryGetValue((r.ProductId, r.VariantId), out var v) ? v : 0) + r.Qty;
            return d;
        }

        // Trụ sở: tổng − chi nhánh khác − đang chuyển.
        var pq = db.PosProducts.AsNoTracking().Where(p => p.StoreId == storeId && p.Deleted == null);
        if (productIds != null) pq = pq.Where(p => productIds.Contains(p.Id));
        var totals = await pq.Select(p => new { p.Id, p.OnHandQty }).ToListAsync(ct);
        var vq = db.PosProductVariants.AsNoTracking().Where(v => v.StoreId == storeId && v.Deleted == null);
        if (productIds != null) vq = vq.Where(v => productIds.Contains(v.ProductId));
        var vtotals = await vq.Select(v => new { v.ProductId, v.Id, v.OnHandQty }).ToListAsync(ct);

        var oq = db.PosBranchStocks.AsNoTracking().Where(s => s.StoreId == storeId && s.BranchId != branchId);
        if (productIds != null) oq = oq.Where(s => productIds.Contains(s.ProductId));
        var others = await oq.GroupBy(s => new { s.ProductId, s.VariantId })
            .Select(g => new { g.Key.ProductId, g.Key.VariantId, Qty = g.Sum(x => x.Qty) })
            .ToDictionaryAsync(x => (x.ProductId, x.VariantId), x => x.Qty, ct);
        var transit = await GetInTransitAsync(db, storeId, productIds, ct);

        var result = new Dictionary<(Guid, Guid?), decimal>();
        foreach (var p in totals)
        {
            var key = (p.Id, (Guid?)null);
            result[key] = p.OnHandQty - others.GetValueOrDefault(key) - ProductLevelTransit(transit, p.Id);
        }
        foreach (var v in vtotals)
        {
            var key = (v.ProductId, (Guid?)v.Id);
            result[key] = v.OnHandQty - others.GetValueOrDefault(key) - transit.GetValueOrDefault(key);
        }
        return result;
    }

    /// <summary>
    /// Hàng đang chuyển tính vào dòng cấp sản phẩm: dòng phiếu có biến thể cũng làm giảm tồn cấp sản phẩm
    /// (tồn sản phẩm quản lý biến thể = tổng biến thể).
    /// </summary>
    private static decimal ProductLevelTransit(Dictionary<(Guid, Guid?), decimal> transit, Guid productId)
        => transit.Where(kv => kv.Key.Item1 == productId).Sum(kv => kv.Value);

    /// <summary>Tồn 1 sản phẩm (hoặc biến thể) ở mọi chi nhánh.</summary>
    public static async Task<Dictionary<Guid, decimal>> GetProductMatrixAsync(
        ZKTecoDbContext db, Guid storeId, Guid productId, Guid? variantId, CancellationToken ct = default)
    {
        var branches = await GetStoreBranchesAsync(db, storeId, ct);
        var hq = ResolveHeadquarter(branches);
        var result = new Dictionary<Guid, decimal>();
        if (hq == null) return result;
        var rows = await db.PosBranchStocks.AsNoTracking()
            .Where(s => s.StoreId == storeId && s.ProductId == productId && s.VariantId == variantId)
            .GroupBy(s => s.BranchId)
            .Select(g => new { BranchId = g.Key, Qty = g.Sum(x => x.Qty) })
            .ToDictionaryAsync(x => x.BranchId, x => x.Qty, ct);
        decimal total = variantId == null
            ? await db.PosProducts.AsNoTracking().Where(p => p.Id == productId).Select(p => p.OnHandQty).FirstOrDefaultAsync(ct)
            : await db.PosProductVariants.AsNoTracking().Where(v => v.Id == variantId).Select(v => v.OnHandQty).FirstOrDefaultAsync(ct);
        var transit = await GetInTransitAsync(db, storeId, [productId], ct);
        var inTransit = variantId == null ? ProductLevelTransit(transit, productId) : transit.GetValueOrDefault((productId, variantId));
        foreach (var b in branches)
        {
            result[b.Id] = b.Id == hq ? 0 : rows.GetValueOrDefault(b.Id);
        }
        result[hq.Value] = total - rows.Where(kv => kv.Key != hq).Sum(kv => kv.Value) - inTransit;
        return result;
    }

    /// <summary>
    /// Đổi trụ sở: tồn trụ sở cũ (đang tính ngầm) được ghi thành số lưu; dòng lưu của trụ sở mới bị bỏ
    /// (từ giờ tính ngầm). Gọi TRƯỚC khi đổi cờ IsHeadquarter trong cùng lượt SaveChanges.
    /// </summary>
    public static async Task RebaseHeadquarterAsync(
        ZKTecoDbContext db, Guid storeId, Guid oldHq, Guid newHq, CancellationToken ct = default)
    {
        if (oldHq == newHq) return;
        var oldQty = await GetBranchQtyAsync(db, storeId, oldHq, oldHq, null, ct);
        foreach (var kv in oldQty.Where(kv => kv.Value != 0))
            await AddAsync(db, storeId, oldHq, kv.Key.Item1, kv.Key.Item2, kv.Value, ct);
        var newRows = await db.PosBranchStocks.AsTracking()
            .Where(s => s.StoreId == storeId && s.BranchId == newHq)
            .ToListAsync(ct);
        db.PosBranchStocks.RemoveRange(newRows);
    }

    /// <summary>Xóa chi nhánh: bỏ dòng tồn lưu của nó → số hàng tự quay về trụ sở.</summary>
    public static async Task ReleaseBranchStockAsync(ZKTecoDbContext db, Guid storeId, Guid branchId, CancellationToken ct = default)
    {
        var rows = await db.PosBranchStocks.AsTracking()
            .Where(s => s.StoreId == storeId && s.BranchId == branchId)
            .ToListAsync(ct);
        db.PosBranchStocks.RemoveRange(rows);
    }

    /// <summary>Chứng từ chưa gắn chi nhánh của cửa hàng → gán về trụ sở (khi vừa tạo chi nhánh đầu tiên / đổi trụ sở).</summary>
    public static async Task BackfillStoreAsync(ZKTecoDbContext db, Guid storeId, CancellationToken ct = default)
    {
        var hq = ResolveHeadquarter(await GetStoreBranchesAsync(db, storeId, ct));
        if (hq == null) return;
        await db.PosSaleOrders.Where(x => x.StoreId == storeId && x.BranchId == null).ExecuteUpdateAsync(s => s.SetProperty(x => x.BranchId, hq), ct);
        await db.PosStockReceipts.Where(x => x.StoreId == storeId && x.BranchId == null).ExecuteUpdateAsync(s => s.SetProperty(x => x.BranchId, hq), ct);
        await db.PosStockIssues.Where(x => x.StoreId == storeId && x.BranchId == null).ExecuteUpdateAsync(s => s.SetProperty(x => x.BranchId, hq), ct);
        await db.PosStockCounts.Where(x => x.StoreId == storeId && x.BranchId == null).ExecuteUpdateAsync(s => s.SetProperty(x => x.BranchId, hq), ct);
        await db.PosPurchaseReturns.Where(x => x.StoreId == storeId && x.BranchId == null).ExecuteUpdateAsync(s => s.SetProperty(x => x.BranchId, hq), ct);
        await db.CashTransactions.Where(x => x.StoreId == storeId && x.BranchId == null).ExecuteUpdateAsync(s => s.SetProperty(x => x.BranchId, hq), ct);
        await db.PosCashierShifts.Where(x => x.StoreId == storeId && x.BranchId == null).ExecuteUpdateAsync(s => s.SetProperty(x => x.BranchId, hq), ct);
        await db.PosStockTransactions.Where(x => x.StoreId == storeId && x.BranchId == null).ExecuteUpdateAsync(s => s.SetProperty(x => x.BranchId, hq), ct);
    }

    /// <summary>
    /// Cộng / trừ tồn chi nhánh (không dùng cho trụ sở — trụ sở tự tính).
    /// Dùng trong interceptor và phiếu chuyển kho; gọi trước SaveChanges.
    /// </summary>
    public static async Task AddAsync(
        ZKTecoDbContext db, Guid storeId, Guid branchId, Guid productId, Guid? variantId, decimal delta,
        CancellationToken ct = default)
    {
        if (delta == 0) return;
        var tracked = db.ChangeTracker.Entries<PosBranchStock>()
            .Select(e => e.Entity)
            .FirstOrDefault(s => s.BranchId == branchId && s.ProductId == productId && s.VariantId == variantId);
        var row = tracked ?? await db.PosBranchStocks.AsTracking()
            .FirstOrDefaultAsync(s => s.BranchId == branchId && s.ProductId == productId && s.VariantId == variantId, ct);
        if (row == null)
        {
            row = new PosBranchStock
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                BranchId = branchId,
                ProductId = productId,
                VariantId = variantId,
                Qty = 0,
            };
            db.PosBranchStocks.Add(row);
        }
        row.Qty += delta;
        row.UpdatedAt = DateTime.UtcNow;
    }
}
