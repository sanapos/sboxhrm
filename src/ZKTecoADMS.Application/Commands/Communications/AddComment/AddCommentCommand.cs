namespace ZKTecoADMS.Application.Commands.Communications.AddComment;

public record AddCommentCommand(
    Guid CommunicationId,
    Guid UserId,
    string UserName,
    string Content,
    Guid? ParentCommentId
) : ICommand<AppResponse<Guid>>;
