using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Mỗi sáng (sau 08:00 giờ VN) gửi quản lý cửa hàng 1 thông báo tổng hợp: lô hết hạn / sắp hết hạn
/// (theo «số ngày cảnh báo» từng hàng) và hàng dưới tồn tối thiểu. Trước đây tồn thấp chỉ báo lúc bán,
/// HSD không có thông báo. Chống gửi trùng: đã có thông báo cùng tiêu đề cho cửa hàng từ 00:00 hôm nay.
/// </summary>
public class PosStockAlertBackgroundService(IServiceProvider sp, ILogger<PosStockAlertBackgroundService> logger)
    : BackgroundService
{
    internal const string ExpiryTitle = "Cảnh báo hạn sử dụng";
    internal const string LowStockTitle = "Hàng cần nhập thêm";
    static readonly TimeSpan VnOffset = TimeSpan.FromHours(7);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await Task.Delay(TimeSpan.FromMinutes(2), stoppingToken);
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                if ((DateTime.UtcNow + VnOffset).Hour >= 8) await RunOnceAsync(stoppingToken);
            }
            catch (Exception ex) { logger.LogError(ex, "PosStockAlert run failed"); }
            await Task.Delay(TimeSpan.FromMinutes(30), stoppingToken);
        }
    }

    internal async Task RunOnceAsync(CancellationToken ct)
    {
        using var scope = sp.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
        var notifications = scope.ServiceProvider.GetRequiredService<ISystemNotificationService>();
        var dayStartUtc = (DateTime.UtcNow + VnOffset).Date - VnOffset;
        var horizon = PosStockLotHelper.ExpiryCutoffUtc().AddDays(365);
        var tracked = new[] { PosProductType.Goods, PosProductType.Material };

        var storeIds = await db.PosStockLots.AsNoTracking()
            .Where(l => l.Deleted == null && l.IsActive && l.Status == PosStockLotStatus.Active &&
                        l.QtyOnHand > 0 && l.ExpiryDate != null && l.ExpiryDate <= horizon)
            .Select(l => l.StoreId)
            .Union(db.PosProducts.AsNoTracking()
                .Where(p => p.Deleted == null && p.IsActive && tracked.Contains(p.ProductType) &&
                            p.MinStockQty > 0 && p.OnHandQty <= p.MinStockQty)
                .Select(p => p.StoreId))
            .Distinct()
            .ToListAsync(ct);

        foreach (var storeId in storeIds)
        {
            if (ct.IsCancellationRequested) break;
            try { await NotifyStoreAsync(db, notifications, storeId, dayStartUtc, ct); }
            catch (Exception ex) { logger.LogWarning(ex, "PosStockAlert store {StoreId} failed", storeId); }
        }
    }

    internal static async Task NotifyStoreAsync(ZKTecoDbContext db, ISystemNotificationService notifications,
        Guid storeId, DateTime dayStartUtc, CancellationToken ct)
    {
        var sentToday = await db.Notifications.AsNoTracking()
            .Where(n => n.StoreId == storeId && n.Timestamp >= dayStartUtc &&
                        (n.Title == ExpiryTitle || n.Title == LowStockTitle))
            .Select(n => n.Title)
            .Distinct()
            .ToListAsync(ct);
        var userIds = await PosNotificationHelper.GetPosManagerUserIdsAsync(db, storeId, ct);
        if (userIds.Count == 0) return;

        if (!sentToday.Contains(ExpiryTitle))
        {
            var lots = await PosStockAlertHelper.ExpiryLotsAsync(db, storeId, ct);
            if (lots.Count > 0)
            {
                var expired = lots.Where(l => l.Expired).ToList();
                var soon = lots.Where(l => !l.Expired).ToList();
                var parts = new List<string>();
                if (expired.Count > 0)
                    parts.Add($"{expired.Count} lô đã hết hạn ({Names(expired.Select(l => l.ProductName))}) — cần xuất hủy");
                if (soon.Count > 0)
                    parts.Add($"{soon.Count} lô sắp hết hạn ({Names(soon.Select(l => $"{l.ProductName} còn {l.DaysLeft} ngày"))})");
                await notifications.CreateAndSendToUsersAsync(userIds,
                    expired.Count > 0 ? NotificationType.Error : NotificationType.Warning,
                    ExpiryTitle, string.Join(". ", parts),
                    relatedEntityType: "PosReportExpiry", categoryCode: "pos", storeId: storeId);
            }
        }

        if (!sentToday.Contains(LowStockTitle))
        {
            var tracked = new[] { PosProductType.Goods, PosProductType.Material };
            var low = await db.PosProducts.AsNoTracking()
                .Where(p => p.StoreId == storeId && p.Deleted == null && p.IsActive &&
                            tracked.Contains(p.ProductType) && p.MinStockQty > 0 && p.OnHandQty <= p.MinStockQty)
                .OrderBy(p => p.OnHandQty)
                .Select(p => new { p.Name, p.OnHandQty, p.MinStockQty })
                .ToListAsync(ct);
            if (low.Count > 0)
            {
                var outCount = low.Count(p => p.OnHandQty <= 0);
                var msg = $"{low.Count} mặt hàng dưới tồn tối thiểu" +
                          (outCount > 0 ? $" ({outCount} đã hết)" : "") + ": " +
                          Names(low.Select(p => $"{p.Name} {p.OnHandQty:0.##}/{p.MinStockQty:0.##}"));
                await notifications.CreateAndSendToUsersAsync(userIds, NotificationType.Warning,
                    LowStockTitle, msg, relatedEntityType: "PosProduct", categoryCode: "pos", storeId: storeId);
            }
        }
    }

    static string Names(IEnumerable<string> names)
    {
        var list = names.ToList();
        return string.Join(", ", list.Take(4)) + (list.Count > 4 ? $"… (+{list.Count - 4})" : "");
    }
}
