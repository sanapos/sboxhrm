namespace ZKTecoADMS.Application.DTOs.DeviceUsers;

public record UpdateDeviceUserRequest(
    string PIN, 
    string Name,
    string? CardNumber,
    string? Password,
    int Privilege,
    string? Email,
    string? PhoneNumber,
    string? Department,
    Guid DeviceId);