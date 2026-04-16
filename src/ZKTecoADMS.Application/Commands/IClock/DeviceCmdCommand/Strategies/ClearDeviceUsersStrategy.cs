using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.IClock.DeviceCmdCommand.Strategies;

[DeviceCommandStrategy(DeviceCommandTypes.ClearDeviceUsers)]
public class ClearEmployeesStrategy(IRepository<DeviceUser> employeeRepository) : IDeviceCommandStrategy
{
    public async Task ExecuteAsync(Device device, Guid objectRefId, ClockCommandResponse response, CancellationToken cancellationToken)
    {
        if (response.IsSuccess)
        {
            await employeeRepository.DeleteAsync(u => u.DeviceId == device.Id, cancellationToken);
        }
    }
}
