namespace ZKTecoADMS.Application.DTOs.Devices;

public record AddDeviceRequest(
    string SerialNumber,
    string DeviceName,
    string? Location,
    string? Description);