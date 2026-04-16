using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Communications.CreateCommunication;

public record CreateCommunicationCommand(
    Guid StoreId,
    Guid CurrentUserId,
    string CurrentUserName,
    string Title,
    string Content,
    string? Summary,
    string? ThumbnailUrl,
    List<string>? AttachedImages,
    CommunicationType Type,
    CommunicationPriority Priority,
    Guid? TargetDepartmentId,
    DateTime? PublishedAt,
    DateTime? ExpiresAt,
    bool IsPinned,
    string? Tags,
    bool PublishImmediately,
    bool IsAiGenerated,
    string? AiPrompt
) : ICommand<AppResponse<Guid>>;
