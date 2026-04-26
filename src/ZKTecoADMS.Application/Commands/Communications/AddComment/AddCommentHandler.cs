using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Communications.AddComment;

public class AddCommentHandler(
    IRepository<CommunicationComment> commentRepository,
    IRepository<InternalCommunication> communicationRepository,
    ISystemNotificationService notificationService
) : ICommandHandler<AddCommentCommand, AppResponse<Guid>>
{
    public async Task<AppResponse<Guid>> Handle(
        AddCommentCommand request,
        CancellationToken cancellationToken)
    {
        try
        {
            // Verify communication exists
            var communication = await communicationRepository.GetByIdAsync(request.CommunicationId, cancellationToken: cancellationToken);
            if (communication == null)
            {
                return AppResponse<Guid>.Error("Không tìm thấy bài truyền thông");
            }

            // Validate comment content
            if (string.IsNullOrWhiteSpace(request.Content))
            {
                return AppResponse<Guid>.Error("Nội dung bình luận không được để trống");
            }

            var trimmedContent = request.Content.Trim();
            if (trimmedContent.Length > 2000)
            {
                return AppResponse<Guid>.Error("Nội dung bình luận không được vượt quá 2000 ký tự");
            }

            var comment = new CommunicationComment
            {
                Id = Guid.NewGuid(),
                CommunicationId = request.CommunicationId,
                UserId = request.UserId,
                UserName = request.UserName,
                Content = trimmedContent,
                ParentCommentId = request.ParentCommentId,
                LikeCount = 0,
                CreatedAt = DateTime.UtcNow
            };

            await commentRepository.AddAsync(comment, cancellationToken);

            // Notify the post author about the new comment (skip self-comments).
            try
            {
                if (communication.AuthorId != Guid.Empty && communication.AuthorId != request.UserId)
                {
                    var preview = trimmedContent.Length > 120 ? trimmedContent.Substring(0, 120) + "…" : trimmedContent;
                    await notificationService.CreateAndSendAsync(
                        communication.AuthorId, NotificationType.Info,
                        $"{request.UserName} đã bình luận bài của bạn",
                        $"\"{communication.Title}\": {preview}",
                        relatedEntityId: communication.Id, relatedEntityType: "Communication",
                        fromUserId: request.UserId,
                        categoryCode: "communication", storeId: communication.StoreId);
                }

                // If this is a reply, also notify the parent comment's author.
                if (request.ParentCommentId.HasValue)
                {
                    var parent = await commentRepository.GetByIdAsync(request.ParentCommentId.Value, cancellationToken: cancellationToken);
                    if (parent != null && parent.UserId != Guid.Empty
                        && parent.UserId != request.UserId
                        && parent.UserId != communication.AuthorId) // already notified above
                    {
                        var preview = trimmedContent.Length > 120 ? trimmedContent.Substring(0, 120) + "…" : trimmedContent;
                        await notificationService.CreateAndSendAsync(
                            parent.UserId, NotificationType.Info,
                            $"{request.UserName} đã trả lời bình luận của bạn",
                            preview,
                            relatedEntityId: communication.Id, relatedEntityType: "Communication",
                            fromUserId: request.UserId,
                            categoryCode: "communication", storeId: communication.StoreId);
                    }
                }
            }
            catch { /* best-effort */ }

            return AppResponse<Guid>.Success(comment.Id);
        }
        catch (Exception ex)
        {
            return AppResponse<Guid>.Error($"Lỗi khi thêm bình luận: {ex.Message}");
        }
    }
}
