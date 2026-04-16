using System.Collections.Concurrent;
using MediatR;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;

namespace ZKTecoADMS.Application.Behaviours;

/// <summary>
/// Pipeline behavior to check if a device with the given SN exists and handle new devices.
/// This behavior intercepts requests that implement IIClockRequest and validates device status.
/// New devices are automatically registered with "Pending" status for admin approval.
/// </summary>
public class DeviceActiveCheckBehaviour<TRequest, TResponse>(
    IDeviceService deviceService,
    IDeviceStatusNotificationService deviceStatusNotificationService,
    ILogger<DeviceActiveCheckBehaviour<TRequest, TResponse>> logger)
    : IPipelineBehavior<TRequest, TResponse>
    where TRequest : IRequest<TResponse>, IIClockRequest
{
    // Prevent duplicate online notifications when multiple requests arrive simultaneously
    private static readonly ConcurrentDictionary<string, DateTime> _recentOnlineNotifications = new();
    
    public async Task<TResponse> Handle(
        TRequest request,
        RequestHandlerDelegate<TResponse> next,
        CancellationToken cancellationToken)
    {
        var serialNumber = request.SN;

        logger.LogInformation(
            "[Device Active Check] Validating device with SN: {SerialNumber} for request: {RequestType}",
            serialNumber,
            typeof(TRequest).Name);

        // Check if device exists
        var device = await deviceService.GetDeviceBySerialNumberAsync(serialNumber);
        
        // Capture previous status before heartbeat update
        var wasOffline = device == null || device.DeviceStatus != "Online";
        
        if (device == null)
        {
            // Thiết bị mới - tự động tạo record để theo dõi
            logger.LogInformation(
                "[Device Active Check] Device with SN: {SerialNumber} not found. Creating device record...",
                serialNumber);
            
            device = await deviceService.CreatePendingDeviceAsync(serialNumber);
            
            logger.LogInformation(
                "[Device Active Check] Created device record with SN: {SerialNumber}, ID: {DeviceId}. Chưa liên kết cửa hàng.",
                serialNumber, device.Id);
        }

        // Luôn cập nhật heartbeat để biết thiết bị đang online
        await deviceService.UpdateDeviceHeartbeatAsync(serialNumber);

        // Gửi thông báo online ngay lập tức khi thiết bị chuyển từ offline → online
        // Dùng ConcurrentDictionary để tránh gửi trùng khi nhiều request đến cùng lúc
        if (wasOffline && device != null && device.IsActive && device.StoreId.HasValue)
        {
            var now = DateTime.UtcNow;
            // TryAdd returns false if key already exists → only first thread wins
            // For existing keys, check cooldown then update atomically
            bool shouldNotify;
            if (_recentOnlineNotifications.TryGetValue(serialNumber, out var lastTime))
            {
                shouldNotify = (now - lastTime).TotalSeconds > 120
                    && _recentOnlineNotifications.TryUpdate(serialNumber, now, lastTime);
            }
            else
            {
                shouldNotify = _recentOnlineNotifications.TryAdd(serialNumber, now);
            }

            if (shouldNotify)
            {
                logger.LogInformation(
                    "📡 Device came ONLINE (immediate): {DeviceName} (SN: {SN})",
                    device.DeviceName, serialNumber);
                var updatedDevice = await deviceService.GetDeviceBySerialNumberAsync(serialNumber);
                if (updatedDevice != null)
                {
                    await deviceStatusNotificationService.NotifyDeviceOnlineAsync(updatedDevice);
                }
            }
        }

        // Nếu thiết bị đã được cửa hàng claim nhưng chưa active → tự động kích hoạt
        if (!device.IsActive && device.IsClaimed && device.StoreId.HasValue)
        {
            logger.LogInformation(
                "[Device Active Check] Device with SN: {SerialNumber} (ID: {DeviceId}) was claimed by store {StoreId}. Auto-activating...",
                serialNumber, device.Id, device.StoreId);
            
            await deviceService.AutoActivateDeviceAsync(serialNumber);
        }

        logger.LogInformation(
            "[Device Active Check] Device with SN: {SerialNumber} (ID: {DeviceId}) - StoreId: {StoreId}, IsActive: {IsActive}. Proceeding to handler.",
            serialNumber, device.Id, device.StoreId, device.IsActive);

        // Luôn cho phép request đi qua handler - handler sẽ quyết định có lưu data hay không
        return await next();
    }

    /// <summary>
    /// Creates a pending response for devices waiting for approval.
    /// Returns OK to keep device connected.
    /// </summary>
    private static TResponse CreatePendingResponse()
    {
        var responseType = typeof(TResponse);

        if (responseType == typeof(string))
        {
            // Trả về OK để thiết bị duy trì kết nối
            return (TResponse)(object)ClockResponses.Ok;
        }

        return default!;
    }

    /// <summary>
    /// Creates a rejection response based on the response type.
    /// For string responses (typical for iClock protocol), returns ClockResponses.Ok
    /// to prevent device from retrying indefinitely while blocking the request.
    /// </summary>
    private static TResponse CreateRejectionResponse()
    {
        var responseType = typeof(TResponse);

        // For string responses (typical iClock protocol responses)
        if (responseType == typeof(string))
        {
            // Return OK to prevent device from retrying, but the actual request is not processed
            return (TResponse)(object)ClockResponses.Fail;
        }

        // For other response types, return default
        return default!;
    }
}

/// <summary>
/// Marker interface for iClock requests that require device active check.
/// Implement this interface on commands/queries that need device validation.
/// </summary>
public interface IIClockRequest
{
    /// <summary>
    /// The device Serial Number (SN) to validate
    /// </summary>
    string SN { get; }
}
