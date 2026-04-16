using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Domain.Enums;
using Microsoft.AspNetCore.Identity;

namespace ZKTecoADMS.Application.Commands.DeviceUsers.Delete;

public class DeleteDeviceUserHandler(
    IRepository<DeviceUser> employeeRepository,
    IRepository<DeviceCommand> deviceCmdRepository) : ICommandHandler<DeleteDeviceUserCommand, AppResponse<Guid>>
{
    public async Task<AppResponse<Guid>> Handle(DeleteDeviceUserCommand request, CancellationToken cancellationToken)
    {
        var employee = await employeeRepository.GetByIdAsync(request.EmployeeId, cancellationToken: cancellationToken);
        
        if (employee == null)
        {
            return AppResponse<Guid>.Fail("Employee not found");
        }

        employee.IsActive = false;
        await employeeRepository.UpdateAsync(employee, cancellationToken);
        
        var cmd = new DeviceCommand
        {
            DeviceId = employee.DeviceId,
            Command = ClockCommandBuilder.BuildDeleteEmployeeCommand(employee.Pin),
            Status = CommandStatus.Created,
            CommandType = DeviceCommandTypes.DeleteDeviceUser,
            ObjectReferenceId = employee.Id
        };
        
        await deviceCmdRepository.AddAsync(cmd, cancellationToken);
        
        return AppResponse<Guid>.Success(employee.Id);
    }
}