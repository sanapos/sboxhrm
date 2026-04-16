using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.DTOs.Devices;

public record DeviceCmdDto(
    Guid Id, 
    DateTime CreatedAt,
    DateTime? UpdatedAt,
    string? UpdatedBy,
    string? CreatedBy,
    Guid DeviceId,
    string Command,
    CommandStatus Status,
    DeviceCommandTypes CommandType,
    string? ResponseData,
    string? ErrorMessage,
    DateTime? SentAt,
    DateTime? CompletedAt
);