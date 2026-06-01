using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.IClock.DeviceCmdCommand.Strategies;

[DeviceCommandStrategy(DeviceCommandTypes.ClearAttendances)]
public class ClearAttendancesStrategy(
    IRepository<Attendance> attendancesRepository,
    IRepository<Notification> notificationRepository) : IDeviceCommandStrategy
{
    public async Task ExecuteAsync(Device device, Guid objectRefId, ClockCommandResponse response, CancellationToken cancellationToken)
    {
        if (!response.IsSuccess)
        {
            return;
        }

        var attendanceIds = (await attendancesRepository.GetAllAsync(
                a => a.DeviceId == device.Id,
                cancellationToken: cancellationToken))
            .Select(a => a.Id)
            .ToList();

        if (attendanceIds.Count > 0)
        {
            await notificationRepository.DeleteAsync(
                n => n.RelatedEntityType == "Attendance"
                     && n.RelatedEntityId != null
                     && attendanceIds.Contains(n.RelatedEntityId.Value),
                cancellationToken);
        }

        await attendancesRepository.DeleteAsync(u => u.DeviceId == device.Id, cancellationToken);
    }
}
