using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.IClock.DeviceCmdCommand.Strategies;

/// <summary>
/// Strategy for handling AddUser command responses
/// </summary>
[DeviceCommandStrategy(DeviceCommandTypes.AddDeviceUser)]
public class AddEmployeeStrategy(IRepository<DeviceUser> employeeRepository) : IDeviceCommandStrategy
{
    public async Task ExecuteAsync(Device device, Guid objectRefId, ClockCommandResponse response, CancellationToken cancellationToken)
    {
        var employee = await employeeRepository.GetByIdAsync(objectRefId, cancellationToken: cancellationToken);
        if (employee != null)
        {
            employee.IsActive = response.IsSuccess;
            await employeeRepository.UpdateAsync(employee, cancellationToken);
        }
    }
}
