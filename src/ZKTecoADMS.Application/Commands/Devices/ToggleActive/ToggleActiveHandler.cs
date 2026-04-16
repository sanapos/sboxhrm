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
                var status = device.IsActive ? "kích hoạt" : "vô hiệu hóa";
                await notificationService.CreateAndSendAsync(
                    targetUserId: null,
                    type: device.IsActive ? NotificationType.Success : NotificationType.Warning,
                    title: $"Thiết bị {status}",
                    message: $"Thiết bị \"{device.DeviceName}\" đã được {status}",
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