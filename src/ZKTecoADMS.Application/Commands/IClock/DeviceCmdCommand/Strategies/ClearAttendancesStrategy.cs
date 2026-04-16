using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.IClock.DeviceCmdCommand.Strategies;

[DeviceCommandStrategy(DeviceCommandTypes.ClearAttendances)]
public class ClearAttendancesStrategy(IRepository<Attendance> attendancesRepository) : IDeviceCommandStrategy
{
    public async Task ExecuteAsync(Device device, Guid objectRefId, ClockCommandResponse response, CancellationToken cancellationToken)
    {
        if (response.IsSuccess)
        {
            await attendancesRepository.DeleteAsync(u => u.DeviceId == device.Id, cancellationToken);
        }
    }
}
