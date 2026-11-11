using ZKTecoADMS.Application.DTOs.Devices;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Devices.ToggleActive;

public class ToggleActiveHandler(
    IRepository<Device> deviceRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<ToggleActiveCommand, AppResponse<DeviceDto>>
{
    public async Task<AppResponse<DeviceDto>> Handle(ToggleActiveCommand request, CancellationToken cancellationToken)
    {
        var device = await deviceRepository.GetByIdAsync(request.DeviceId, cancellationToken: cancellationToken);
        if (device == null)
        {
            return  AppResponse<DeviceDto>.Error("Device not found");
        }
        
        device.IsActive = !device.IsActive;
        var result = await deviceRepository.UpdateAsync(device, cancellationToken);

        if (result)
        {
            try
            {
                // «Đã tắt máy chấm công» / «Máy cổng · SN …0123»
                await notificationService.CreateAndSendAsync(
                    targetUserId: null,
                    type: device.IsActive ? NotificationType.Success : NotificationType.Warning,
                    title: device.IsActive ? "Đã bật lại máy chấm công" : "Đã tắt máy chấm công",
                    message: global::ZKTecoADMS.Application.Commands.Devices.AddDevice.AddDeviceHandler.DeviceLabel(device.DeviceName, device.SerialNumber),
                    relatedEntityId: device.Id,
                    relatedEntityType: "Device",
                    categoryCode: "device",
                    storeId: device.StoreId);
            }
            catch { }
        }

        return result ? AppResponse<DeviceDto>.Success(device.Adapt<DeviceDto>()) : AppResponse<DeviceDto>.Error("Something went wrong");
    }
}