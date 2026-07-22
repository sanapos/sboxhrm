namespace ZKTecoADMS.Application.DTOs.Devices;

public record DeviceCmdRequest(
    int CommandType,
    int Priority = 1,
    string? Command = null,
    string? Pin = null,
    int? FingerIndex = null);