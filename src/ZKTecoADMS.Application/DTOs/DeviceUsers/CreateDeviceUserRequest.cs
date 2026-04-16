namespace ZKTecoADMS.Application.DTOs.DeviceUsers;

public record CreateDeviceUserRequest(
    string? Pin, 
    string Name,
    string? CardNumber,
    string? Password,
    int Privilege,
    Guid DeviceId,
    Guid? EmployeeId = null
);