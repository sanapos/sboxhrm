using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Đối soát «giữ chỗ tồn» (PosProduct.ReservedQty) với các đơn tạm / bàn / QR đang mở.
/// ReservedQty là số cộng dồn (delta) nên một lỗi cũ (vd. đơn online hoàn tất không nhả giữ chỗ)
/// làm tồn khả dụng bị treo mãi. Chạy lúc khởi động + mỗi đêm để tự lành.
/// </summary>
public static class PosReservedStockReconciler
{
    /// <returns>Số hàng hóa được chỉnh ReservedQty.</returns>
    public static async Task<int> RecomputeStoreAsync(ZKTecoDbContext db, Guid storeId, CancellationToken ct = default)
    {
        var draftLines = await db.PosSaleOrderLines.IgnoreQueryFilters().AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null &&
                        l.SaleOrder != null && l.SaleOrder.Deleted == null &&
                        l.SaleOrder.Status == PosSaleOrderStatus.Draft)
            .Select(l => new { l.SaleOrderId, l.ProductId, l.Qty, l.VariantId, l.UnitId, l.ToppingsJson })
            .ToListAsync(ct);

        // Tính theo từng đơn — một đơn hỏng (hàng đã xóa…) không làm sai cả cửa hàng.
        var needs = new Dictionary<Guid, decimal>();
        foreach (var order in draftLines.GroupBy(l => l.SaleOrderId))
        {
            var inputs = PosSaleStockHelper.ExpandStockInputsWithToppings(order
                .Select(l => (l.ProductId, l.Qty, l.VariantId, l.UnitId, l.ToppingsJson))
                .ToList());
            var (orderNeeds, err) = await PosSaleStockHelper.ComputeDraftReserveNeedsAsync(db, storeId, inputs);
            if (err != null) continue;
            foreach (var (pid, q) in orderNeeds)
                needs[pid] = needs.GetValueOrDefault(pid) + q;
        }
        db.ChangeTracker.Clear();
        return await ApplyNeedsAsync(db, storeId, needs, ct);
    }

    /// <summary>Ghi ReservedQty = nhu cầu giữ chỗ đã tính; hàng không còn đơn mở → 0.</summary>
    internal static async Task<int> ApplyNeedsAsync(
        ZKTecoDbContext db, Guid storeId, Dictionary<Guid, decimal> needs, CancellationToken ct = default)
    {
        var products = await db.PosProducts.IgnoreQueryFilters().AsTracking()
            .Where(p => p.StoreId == storeId && p.Deleted == null &&
                        (p.ReservedQty != 0 || needs.Keys.Contains(p.Id)))
            .ToListAsync(ct);
        var changed = 0;
        foreach (var p in products)
        {
            var want = p.ProductType == PosProductType.Service ? 0m : Math.Max(0m, needs.GetValueOrDefault(p.Id));
            if (Math.Abs(p.ReservedQty - want) < 0.0001m) continue;
            p.ReservedQty = want;
            p.UpdatedAt = DateTime.UtcNow;
            changed++;
        }
        if (changed > 0)
            await db.SaveChangesAsync(ct);
        return changed;
    }
}

/// <summary>Chạy đối soát giữ chỗ tồn cho mọi cửa hàng: 3 phút sau khởi động, sau đó 3h sáng mỗi ngày.</summary>
public sealed class PosReservedStockReconcileBackgroundService(
    IServiceScopeFactory scopes, ILogger<PosReservedStockReconcileBackgroundService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try
        {
            await Task.Delay(TimeSpan.FromMinutes(3), stoppingToken);
        }
        catch (TaskCanceledException) { return; }

        while (!stoppingToken.IsCancellationRequested)
        {
            await RunAllStoresAsync(stoppingToken);
            // Lần kế: 3:00 giờ VN (ít đơn mở nhất).
            var nowVn = DateTime.UtcNow.AddHours(7);
            var next = nowVn.Date.AddHours(3);
            if (next <= nowVn) next = next.AddDays(1);
            try
            {
                await Task.Delay(next - nowVn, stoppingToken);
            }
            catch (TaskCanceledException) { return; }
        }
    }

    async Task RunAllStoresAsync(CancellationToken ct)
    {
        List<Guid> storeIds;
        using (var scope = scopes.CreateScope())
        {
            var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
            storeIds = await db.PosProducts.IgnoreQueryFilters().AsNoTracking()
                .Where(p => p.Deleted == null && p.ReservedQty != 0)
                .Select(p => p.StoreId)
                .Union(db.PosSaleOrders.IgnoreQueryFilters().AsNoTracking()
                    .Where(o => o.Deleted == null && o.Status == PosSaleOrderStatus.Draft)
                    .Select(o => o.StoreId))
                .Distinct()
                .ToListAsync(ct);
        }

        foreach (var storeId in storeIds)
        {
            try
            {
                using var scope = scopes.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
                var changed = await PosReservedStockReconciler.RecomputeStoreAsync(db, storeId, ct);
                if (changed > 0)
                    logger.LogInformation("ReservedQty reconciled store={StoreId} products={Count}", storeId, changed);
            }
            catch (Exception ex)
            {
                // Xung đột với thao tác thu ngân đang diễn ra → bỏ qua, lần sau đối soát tiếp.
                logger.LogWarning(ex, "ReservedQty reconcile skipped store={StoreId}", storeId);
            }
        }
    }
}
