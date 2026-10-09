using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Hội viên vừa quét ở máy → báo màn «Check-in hội viên» của cửa hàng ngay (PosFloorChanged, reason=gym_scan).
/// Màn quầy hiện cảnh báo + âm báo khi thẻ hết hạn / hết buổi.
/// </summary>
public class GymRealtimeNotifier(IHubContext<AttendanceHub> hub) : IGymRealtimeNotifier
{
    public void GymScan(Guid storeId, GymScanEvent e)
    {
        _ = hub.Clients.Group(PosFloorRealtimeHelper.StoreGroup(storeId)).SendAsync("PosFloorChanged", new
        {
            storeId,
            reason = "gym_scan",
            message = e.Note,
            gym = new
            {
                visitId = e.VisitId,
                customerId = e.CustomerId,
                customerName = e.CustomerName,
                deviceName = e.DeviceName,
                action = e.Action,
                status = e.Status,
                note = e.Note,
                doorOpened = e.DoorOpened,
            },
            at = DateTime.UtcNow,
        });
    }
}

/// <summary>
/// Mỗi 10 phút: thẻ vừa hết hạn → đẩy thông báo «hết hạn» lên máy ở cửa; khách vừa mua / gia hạn gói → gỡ.
/// Chỉ cửa hàng có máy bật «máy chủ mở cửa».
/// </summary>
public class GymAccessSyncBackgroundService(IServiceProvider sp, ILogger<GymAccessSyncBackgroundService> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        await Task.Delay(TimeSpan.FromMinutes(3), stoppingToken);
        while (!stoppingToken.IsCancellationRequested)
        {
            try { await RunOnceAsync(stoppingToken); }
            catch (Exception ex) { logger.LogError(ex, "Gym access sync failed"); }
            await Task.Delay(TimeSpan.FromMinutes(10), stoppingToken);
        }
    }

    internal async Task RunOnceAsync(CancellationToken ct)
    {
        using var scope = sp.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
        var gym = scope.ServiceProvider.GetRequiredService<IGymCheckInService>();
        var doorDevices = db.DeviceSettings.IgnoreQueryFilters()
            .Where(s => s.SettingKey == GymCheckInService.DoorModeKey && s.SettingValue == GymCheckInService.DoorModeServer)
            .Select(s => s.DeviceId);
        var storeIds = await db.Devices.IgnoreQueryFilters().AsNoTracking()
            .Where(d => d.Deleted == null && d.StoreId != null && doorDevices.Contains(d.Id))
            .Select(d => d.StoreId!.Value).Distinct().ToListAsync(ct);
        foreach (var storeId in storeIds)
        {
            if (ct.IsCancellationRequested) break;
            try
            {
                var n = await gym.SyncDeviceAccessAsync(storeId);
                if (n > 0) logger.LogInformation("Gym access sync store {StoreId}: {Count} member(s) changed", storeId, n);
            }
            catch (Exception ex) { logger.LogWarning(ex, "Gym access sync store {StoreId} failed", storeId); }
        }
    }
}
