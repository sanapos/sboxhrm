using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Devices;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Devices.AddDevice;

public class AddDeviceHandler(
    IRepository<DeviceCommand> deviceCommandRepository,
    IRepository<Device> deviceRepository,
    IDeviceService deviceService,
    ISystemNotificationService notificationService,
    IStoreLicenseLimitService storeLicenseLimitService
    ) : ICommandHandler<AddDeviceCommand, AppResponse<DeviceDto>>
{
    public async Task<AppResponse<DeviceDto>> Handle(AddDeviceCommand request, CancellationToken cancellationToken)
    {
        var existingDevice = await deviceService.GetDeviceBySerialNumberAsync(request.SerialNumber);
        if (existingDevice != null)
        {
            // Nếu thiết bị đã được claim bởi người khác → báo lỗi
            if (existingDevice.IsClaimed && existingDevice.StoreId != request.StoreId)
            {
                return AppResponse<DeviceDto>.Error($"Thiết bị với Serial Number: {request.SerialNumber} đã được đăng ký bởi cửa hàng khác.");
            }

            // Nếu thiết bị đang Pending hoặc chưa claimed → cập nhật lại thông tin và kích hoạt
            existingDevice.DeviceName = request.DeviceName;
            existingDevice.Location = request.Location;
            existingDevice.Description = request.Description;
            existingDevice.ManagerId = request.ManagerId;
            existingDevice.StoreId = request.StoreId;
            existingDevice.DeviceStatus =
                DeviceConnectivity.IsOnline(existingDevice.LastOnline) ? "Online" : "Offline";
            existingDevice.IsActive = true;
            existingDevice.IsClaimed = true;
            existingDevice.OwnerId = request.ManagerId;
            existingDevice.ClaimedAt = DateTime.Now;
            existingDevice.UpdatedAt = DateTime.Now;

            await deviceRepository.UpdateAsync(existingDevice, cancellationToken);

            var syncCmd = new DeviceCommand
            {
                DeviceId = existingDevice.Id,
                CommandType = DeviceCommandTypes.SyncDeviceUsers,
                Priority = 10,
                Command = ClockCommandBuilder.BuildGetAllUsersCommand()
            };
            await deviceCommandRepository.AddAsync(syncCmd, cancellationToken);

            try
            {
                await notificationService.CreateAndSendAsync(
                    targetUserId: null,
                    type: NotificationType.Info,
                    // Formatter không còn thêm «Thiết bị · » → tiêu đề tự đủ nghĩa.
                    // «Đã kích hoạt lại máy chấm công» / «Máy cổng · SN …0123»
                    title: "Đã kích hoạt lại máy chấm công",
                    message: DeviceLabel(existingDevice.DeviceName, request.SerialNumber),
                    relatedEntityId: existingDevice.Id,
                    relatedEntityType: "Device",
                    categoryCode: "device",
                    storeId: request.StoreId);
            }
            catch { }

            return AppResponse<DeviceDto>.Success(existingDevice.Adapt<DeviceDto>());
        }

        if (!request.StoreId.HasValue)
        {
            return AppResponse<DeviceDto>.Error("StoreId is required.");
        }

        var limitCheck = await storeLicenseLimitService.CanAddDeviceAsync(
            request.StoreId.Value, cancellationToken);
        if (!limitCheck.Ok)
        {
            return AppResponse<DeviceDto>.Error(limitCheck.Error!);
        }
        
        var deviceEntity = request.Adapt<Device>();
        deviceEntity.Id = Guid.NewGuid();
        deviceEntity.DeviceStatus = "Offline";
        deviceEntity.IsActive = true;
        deviceEntity.IsClaimed = true;
        deviceEntity.OwnerId = request.ManagerId;
        deviceEntity.ClaimedAt = DateTime.Now;
        deviceEntity.CreatedAt = DateTime.Now;
        deviceEntity.UpdatedAt = DateTime.Now;

        // Sử dụng DeviceService để tạo Device + DeviceInfo trong cùng 1 SaveChanges
        // (tránh lỗi circular FK giữa Device.DeviceInfoId và DeviceInfo.DeviceId)
        var device = await deviceService.CreateDeviceAsync(deviceEntity);
        
        var syncUsersCommand = new DeviceCommand
        {
            DeviceId = device.Id,
            CommandType = DeviceCommandTypes.SyncDeviceUsers,
            Priority = 10,
            Command = ClockCommandBuilder.BuildGetAllUsersCommand()
        };

        await deviceCommandRepository.AddAsync(syncUsersCommand, cancellationToken);

        try
        {
            await notificationService.CreateAndSendAsync(
                targetUserId: null,
                type: NotificationType.Success,
                // «Đã thêm máy chấm công» / «Máy cổng · SN …0123»
                title: "Đã thêm máy chấm công",
                message: DeviceLabel(request.DeviceName, request.SerialNumber),
                relatedEntityId: device.Id,
                relatedEntityType: "Device",
                categoryCode: "device",
                storeId: request.StoreId);
        }
        catch { }

        return AppResponse<DeviceDto>.Success(device.Adapt<DeviceDto>());
    }

    /// <summary>«Máy cổng · SN …0123» — 4 số cuối đủ phân biệt máy, khỏi in cả dãy SN.</summary>
    internal static string DeviceLabel(string? deviceName, string? serialNumber)
    {
        var name = deviceName?.Trim();
        var sn = serialNumber?.Trim() ?? string.Empty;
        var shortSn = sn.Length > 4 ? $"…{sn[^4..]}" : sn;
        if (string.IsNullOrEmpty(name)) return string.IsNullOrEmpty(shortSn) ? "Máy chấm công" : $"SN {shortSn}";
        return string.IsNullOrEmpty(shortSn) ? name : $"{name} · SN {shortSn}";
    }
}
