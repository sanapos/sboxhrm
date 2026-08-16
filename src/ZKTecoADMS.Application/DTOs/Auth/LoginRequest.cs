namespace ZKTecoADMS.Application.DTOs.Auth;

public record LoginRequest(
    string StoreCode,
    string UserName,
    string Password,
    string? ClientPlatform = null,
    string? DeviceKey = null,
    string? DeviceName = null);

