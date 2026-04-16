using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.DeviceUsers;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.DeviceUsers.Update;

public class UpdateDeviceUserHandler(
    IRepository<DeviceUser> employeeRepository,
    IRepository<DeviceCommand> deviceCmdRepository
    ) : ICommandHandler<UpdateDeviceUserCommand, AppResponse<DeviceUserDto>>
{
    public async Task<AppResponse<DeviceUserDto>> Handle(UpdateDeviceUserCommand request, CancellationToken cancellationToken)
    {
        var employee = await employeeRepository.GetByIdAsync(request.EmployeeId, cancellationToken: cancellationToken);
        if (employee == null)
        {
            return  AppResponse<DeviceUserDto>.Fail("Employee not found");
        }
        employee.Pin = request.PIN;
        employee.Name = request.Name;
        employee.CardNumber = request.CardNumber;
        employee.Password = request.Password;
        employee.Privilege = request.Privilege;
        employee.IsActive = false;
        
        await employeeRepository.UpdateAsync(employee, cancellationToken);
        
        var cmd = new DeviceCommand
        {
            DeviceId = employee.DeviceId,
            Command = ClockCommandBuilder.BuildAddOrUpdateEmployeeCommand(employee),
            Priority = 10,
            Status = CommandStatus.Created,
            CommandType = DeviceCommandTypes.UpdateDeviceUser,
            ObjectReferenceId = employee.Id,
        };
        await deviceCmdRepository.AddAsync(cmd, cancellationToken);
        
        return AppResponse<DeviceUserDto>.Success(employee.Adapt<DeviceUserDto>());
    }
}