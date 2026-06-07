using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Application.Commands.IClock.CDataPost.Strategy;

/// <summary>
/// Handles attendance log data uploads from device to server.
/// Format: [PIN]\t[Punch date/time]\t[Attendance State]\t[Verify Mode]\t[Workcode]\t[Reserved 1]\t[Reserved 2]
/// </summary>
public class PostAttendancesStrategy(IServiceProvider serviceProvider) : IPostStrategy
{
    /// <summary>Chỉ push thông báo cho lần chấm trong cửa sổ này (tránh nổ khi máy upload log cũ).</summary>
    private static readonly TimeSpan RealtimeNotifyWindow = TimeSpan.FromMinutes(15);

    /// <summary>Máy chấm gửi giờ VN (Unspecified); so sánh theo giờ VN, không dùng UTC server.</summary>
    private static DateTime VietnamNow => DateTime.UtcNow.AddHours(7);

    private readonly IAttendanceOperationService _attendanceOperationService = serviceProvider.GetRequiredService<IAttendanceOperationService>();
    private readonly IAttendanceService _attendanceService = serviceProvider.GetRequiredService<IAttendanceService>();
    private readonly ILogger<PostAttendancesStrategy> _logger = serviceProvider.GetRequiredService<ILogger<PostAttendancesStrategy>>();
    private readonly IShiftService _shiftService = serviceProvider.GetRequiredService<IShiftService>();
    private readonly IGoogleSheetService? _googleSheetService = serviceProvider.GetService<IGoogleSheetService>();
    private readonly IAttendanceNotificationService? _notificationService = serviceProvider.GetService<IAttendanceNotificationService>();
    private readonly IMealRecordService? _mealRecordService = serviceProvider.GetService<IMealRecordService>();
    private readonly IDeviceCmdService _deviceCmdService = serviceProvider.GetRequiredService<IDeviceCmdService>();
    private readonly IRepository<Attendance> _attendanceRepository =
        serviceProvider.GetRequiredService<IRepository<Attendance>>();
    private readonly IRepository<DeviceInfo> _deviceInfoRepository =
        serviceProvider.GetRequiredService<IRepository<DeviceInfo>>();

    public async Task<string> ProcessDataAsync(Device device, string body)
    {
        if (string.IsNullOrWhiteSpace(body))
        {
            AttendanceBulkSyncTracker.RecordAttlogUpload(device.Id);

            var serverCount = await _attendanceRepository.CountAsync(a => a.DeviceId == device.Id);
            var deviceInfo = await _deviceInfoRepository.GetSingleAsync(di => di.DeviceId == device.Id);
            var localCount = deviceInfo?.AttendanceCount ?? 0;

            if (!AttendanceBulkSyncTracker.IsServerCountSufficient(localCount, serverCount))
            {
                _logger.LogWarning(
                    "Device-SN-{SN}: empty ATTLOG but server {Server} < machine {Machine} — keep SyncAttendances open",
                    device.SerialNumber, serverCount, localCount);
                return ClockResponses.Ok;
            }

            _logger.LogInformation(
                "Device-SN-{SN}: empty ATTLOG — end of attendance sync for device {DeviceId} (server={Server}, machine={Machine})",
                device.SerialNumber, device.Id, serverCount, localCount);
            await CompleteSyncAttendanceCommandsAsync(device.Id);
            return ClockResponses.Ok;
        }

        AttendanceBulkSyncTracker.RecordAttlogUpload(device.Id);

        var bulkSyncInProgress = await IsAttendanceBulkSyncInProgressAsync(device.Id);
        var attendances = await _attendanceOperationService.ProcessAttendancesFromDeviceAsync(device, body);

        if (attendances.Count == 0)
        {
            _logger.LogWarning(
                "Device-SN-{SN}: no new attendance rows saved from device {DeviceId} (duplicates or parse skip; bulk={Bulk})",
                device.SerialNumber, device.Id, bulkSyncInProgress);
            // Chỉ kết thúc sync khi máy gửi ATTLOG rỗng (end marker) — không đóng khi batch toàn bản ghi trùng.
            return bulkSyncInProgress ? ClockResponses.Ok : ClockResponses.Fail;
        }

        await _attendanceService.CreateAttendancesAsync(attendances);
        _logger.LogInformation("Device-SN-{SN}: successfully saved {Count} attendance records from device {DeviceId}", device.SerialNumber, attendances.Count, device.Id);

        // Luôn tạo phiếu phạt (đi trễ / về sớm / tái phạm) — kể cả khi đồng bộ log hàng loạt.
        try
        {
            await _attendanceService.UpdateShiftAttendancesAsync(attendances, device);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Device-SN-{SN}: failed to process penalty tickets for {Count} attendance rows",
                device.SerialNumber, attendances.Count);
        }

        var cutoff = VietnamNow.Subtract(RealtimeNotifyWindow);
        var recentOnly = attendances
            .Where(a => a.AttendanceTime >= cutoff)
            .OrderByDescending(a => a.AttendanceTime)
            .Take(5)
            .ToList();

        if (!bulkSyncInProgress)
        {
            if (_googleSheetService != null)
            {
                try
                {
                    await _googleSheetService.PushAttendancesAsync(attendances, device);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Device-SN-{SN}: failed to push attendance to Google Sheet", device.SerialNumber);
                }
            }

            if (device.DeviceType == DeviceType.Meal && _mealRecordService != null)
            {
                try
                {
                    await _mealRecordService.ProcessMealAttendancesAsync(attendances, device);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Device-SN-{SN}: failed to process meal records", device.SerialNumber);
                }
            }
        }
        else
        {
            _logger.LogInformation(
                "Device-SN-{SN}: bulk sync — skipped sheets/shift for {Count} records (recent notify still allowed)",
                device.SerialNumber, attendances.Count);
        }

        // Luôn thông báo lần chấm gần đây — kể cả khi SyncAttendances kẹt ở Sent (tránh mất push khi đồng bộ log).
        if (_notificationService != null)
        {
            if (recentOnly.Count > 0)
            {
                try
                {
                    await _notificationService.NotifyNewAttendancesAsync(recentOnly, device);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Device-SN-{SN}: failed to send real-time notification", device.SerialNumber);
                }
            }
            else if (attendances.Count > 0)
            {
                _logger.LogInformation(
                    "Device-SN-{SN}: skipped notifications for {Count} historical attendance rows (older than {Minutes} min)",
                    device.SerialNumber, attendances.Count, RealtimeNotifyWindow.TotalMinutes);
            }
        }

        return ClockResponses.Ok;
    }

    private async Task<bool> IsAttendanceBulkSyncInProgressAsync(Guid deviceId)
    {
        var pending = await _deviceCmdService.GetPendingCommandsAsync(deviceId);
        return pending.Any(c => c.CommandType == DeviceCommandTypes.SyncAttendances);
    }

    private async Task CompleteSyncAttendanceCommandsAsync(Guid deviceId)
    {
        try
        {
            var pending = await _deviceCmdService.GetPendingCommandsAsync(deviceId);
            foreach (var cmd in pending.Where(c => c.CommandType == DeviceCommandTypes.SyncAttendances))
            {
                await _deviceCmdService.UpdateCommandStatusAsync(cmd.Id, CommandStatus.Success);
                _logger.LogInformation("Completed SyncAttendances command {CommandId} for device {DeviceId}", cmd.Id, deviceId);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error completing SyncAttendances commands for device {DeviceId}", deviceId);
        }
    }
}
