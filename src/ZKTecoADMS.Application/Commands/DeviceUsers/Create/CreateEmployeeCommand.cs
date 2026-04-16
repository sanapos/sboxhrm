using ZKTecoADMS.Application.DTOs.DeviceUsers;

namespace ZKTecoADMS.Application.Commands.DeviceUsers.Create;

public record CreateDeviceUserCommand(
    string? Pin, 
    string Name, 
    string? CardNumber, 
    string? Password, 
    int Privilege, 
    Guid DeviceId,
    Guid? EmployeeId = null) : ICommand<AppResponse<DeviceUserDto>>;
