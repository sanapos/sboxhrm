using ZKTecoADMS.Application.DTOs.DeviceUsers;

namespace ZKTecoADMS.Application.Commands.DeviceUsers.Update;

public record UpdateDeviceUserCommand(
    Guid EmployeeId,
    string PIN, 
    string Name, 
    string? CardNumber, 
    string? Password, 
    int Privilege, 
    string? Email, 
    string? PhoneNumber, 
    string? Department,
    Guid DeviceId) : ICommand<AppResponse<DeviceUserDto>>;
