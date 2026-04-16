using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Communications.UpdateCommunication;

public record UpdateCommunicationCommand(
    Guid Id,
    Guid StoreId,
    Guid CurrentUserId,
    string? Title,
    string? Content,
    string? Summary,
    string? ThumbnailUrl,
    List<string>? AttachedImages,
    CommunicationType? Type,
    CommunicationPriority? Priority,
    CommunicationStatus? Status,
    Guid? TargetDepartmentId,
    DateTime? PublishedAt,
    DateTime? ExpiresAt,
    bool? IsPinned,
    string? Tags
) : ICommand<AppResponse<bool>>;
