using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.IClock.CDataPost.Strategy;

/// <summary>
/// Handles attendance log data uploads from device to server.
/// Format: [PIN]\t[Punch date/time]\t[Attendance State]\t[Verify Mode]\t[Workcode]\t[Reserved 1]\t[Reserved 2]
/// </summary>
public class PostAttendancesStrategy(IServiceProvider serviceProvider) : IPostStrategy
{
    private readonly IAttendanceOperationService _attendanceOperationService = serviceProvider.GetRequiredService<IAttendanceOperationService>();
    private readonly IAttendanceService _attendanceService = serviceProvider.GetRequiredService<IAttendanceService>();
    private readonly ILogger<PostAttendancesStrategy> _logger = serviceProvider.GetRequiredService<ILogger<PostAttendancesStrategy>>();
    private readonly IShiftService _shiftService = serviceProvider.GetRequiredService<IShiftService>();
    private readonly IGoogleSheetService? _googleSheetService = serviceProvider.GetService<IGoogleSheetService>();
    private readonly IAttendanceNotificationService? _notificationService = serviceProvider.GetService<IAttendanceNotificationService>();
    private readonly IMealRecordService? _mealRecordService = serviceProvider.GetService<IMealRecordService>();

    public async Task<string> ProcessDataAsync(Device device, string body)
    {
        // Step 1: Parse and process attendances from device data
        var attendances = await _attendanceOperationService.ProcessAttendancesFromDeviceAsync(device, body);

        if (attendances.Count == 0)
        {
            _logger.LogWarning("Device-SN-{SN}: no valid attendance records to save from device {DeviceId}", device.SerialNumber, device.Id);
            return ClockResponses.Fail;
        }

        // Step 2: Persist attendances to database
        await _attendanceService.CreateAttendancesAsync(attendances);

        _logger.LogInformation("Device-SN-{SN}: successfully saved {Count} attendance records from device {DeviceId}", device.SerialNumber, attendances.Count, device.Id);

        await _attendanceService.UpdateShiftAttendancesAsync(attendances, device);

        // Step 3: Push realtime to Google Sheets
        if (_googleSheetService != null)
        {
            try
            {
                await _googleSheetService.PushAttendancesAsync(attendances, device);
                _logger.LogInformation("Device-SN-{SN}: pushed {Count} attendance records to Google Sheet", device.SerialNumber, attendances.Count);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Device-SN-{SN}: failed to push attendance to Google Sheet", device.SerialNumber);
            }
        }
        
        // Step 4: Send real-time notification to clients via SignalR
        _logger.LogInformation("Device-SN-{SN}: 🔍 NotificationService is {Status}", device.SerialNumber, _notificationService != null ? "AVAILABLE" : "NULL");
        if (_notificationService != null)
        {
            try
            {
                _logger.LogInformation("Device-SN-{SN}: 📤 Calling NotifyNewAttendancesAsync for {Count} attendances...", device.SerialNumber, attendances.Count);
                await _notificationService.NotifyNewAttendancesAsync(attendances, device);
                _logger.LogInformation("Device-SN-{SN}: ✅ sent real-time notification for {Count} attendance records", device.SerialNumber, attendances.Count);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Device-SN-{SN}: ❌ failed to send real-time notification", device.SerialNumber);
            }
        }
        else
        {
            _logger.LogWarning("Device-SN-{SN}: ⚠️ NotificationService is NULL - notifications will NOT be sent!", device.SerialNumber);
        }

        // Step 5: Process meal records if device is a meal tracking device
        if (device.DeviceType == DeviceType.Meal && _mealRecordService != null)
        {
            try
            {
                _logger.LogInformation("Device-SN-{SN}: 🍽️ Processing meal records for {Count} attendances...", device.SerialNumber, attendances.Count);
                await _mealRecordService.ProcessMealAttendancesAsync(attendances, device);
                _logger.LogInformation("Device-SN-{SN}: ✅ Meal records processed successfully", device.SerialNumber);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Device-SN-{SN}: ❌ Failed to process meal records", device.SerialNumber);
            }
        }
        
        return ClockResponses.Ok; 
    }
}