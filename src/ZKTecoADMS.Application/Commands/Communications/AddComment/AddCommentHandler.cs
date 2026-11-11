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
            // Tên người bình luận ở tiêu đề → formatter không chèn lại vào body (trước đây tên hiện 2 lần).
            // «Nguyễn Văn An bình luận bài của bạn» / «"Em đăng ký nghỉ…" · Lịch nghỉ Tết 2027»
            var commenter = request.UserName?.Trim();
            var preview = Preview(trimmedContent);
            var postTitle = Preview(communication.Title ?? string.Empty, 40);
            try
            {
                if (communication.AuthorId != Guid.Empty && communication.AuthorId != request.UserId)
                {
                    await notificationService.CreateAndSendAsync(
                        communication.AuthorId, NotificationType.Info,
                        string.IsNullOrEmpty(commenter) ? "Bình luận mới về bài của bạn" : $"{commenter} bình luận bài của bạn",
                        string.IsNullOrEmpty(postTitle) ? $"\"{preview}\"" : $"\"{preview}\" · {postTitle}",
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
                        // «Nguyễn Văn An trả lời bạn» / «"Đồng ý ạ" · Lịch nghỉ Tết 2027»
                        await notificationService.CreateAndSendAsync(
                            parent.UserId, NotificationType.Info,
                            string.IsNullOrEmpty(commenter) ? "Có người trả lời bình luận của bạn" : $"{commenter} trả lời bạn",
                            string.IsNullOrEmpty(postTitle) ? $"\"{preview}\"" : $"\"{preview}\" · {postTitle}",
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

    /// <summary>Gom về một dòng, cắt ở <paramref name="max"/> ký tự (banner chỉ hiện ~2 dòng).</summary>
    private static string Preview(string text, int max = 60)
    {
        var oneLine = System.Text.RegularExpressions.Regex.Replace(text, @"\s+", " ").Trim();
        return oneLine.Length > max ? oneLine[..max].TrimEnd() + "…" : oneLine;
    }
}
