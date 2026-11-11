using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Devices.DeleteDevice;

public class DeleteDeviceHandler(
    IRepository<Device> deviceRepository,
    IRepository<DeviceCommand> deviceCommandRepository,
    IRepository<Attendance> attendanceRepository,
    IRepository<DeviceUser> deviceUserRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<DeleteDeviceCommand, AppResponse<Guid>>
{
    public async Task<AppResponse<Guid>> Handle(DeleteDeviceCommand request, CancellationToken cancellationToken)
    {
        var device = await deviceRepository.GetByIdAsync(request.Id, cancellationToken: cancellationToken);
        if (device == null)
            return AppResponse<Guid>.Error("Không tìm thấy thiết bị.");

        var deviceName = device.DeviceName;
        var serialNumber = device.SerialNumber;
        var storeId = device.StoreId;

        // Xóa các dữ liệu liên quan trước khi xóa thiết bị
        await deviceCommandRepository.DeleteAsync(c => c.DeviceId == request.Id, cancellationToken);
        await attendanceRepository.DeleteAsync(a => a.DeviceId == request.Id, cancellationToken);
        await deviceUserRepository.DeleteAsync(u => u.DeviceId == request.Id, cancellationToken);

        var result = await deviceRepository.DeleteByIdAsync(request.Id, cancellationToken);

        if (result)
        {
            try
            {
                await notificationService.CreateAndSendAsync(
                    targetUserId: null,
                    type: NotificationType.Warning,
                    // Handler xóa luôn dữ liệu chấm công của máy (attendanceRepository ở trên) → nói rõ.
                    // «Đã xóa máy chấm công» / «Máy cổng · SN …0123 · Đã xóa kèm dữ liệu chấm công của máy»
                    title: "Đã xóa máy chấm công",
                    message: global::ZKTecoADMS.Application.Commands.Devices.AddDevice.AddDeviceHandler.DeviceLabel(deviceName, serialNumber)
                        + " · Đã xóa kèm dữ liệu chấm công của máy",
                    relatedEntityType: "Device",
                    categoryCode: "device",
                    storeId: storeId);
            }
            catch { }
        }
        
        return result ? AppResponse<Guid>.Success(request.Id) : AppResponse<Guid>.Error("Có lỗi xảy ra khi xóa thiết bị.");
    }
}