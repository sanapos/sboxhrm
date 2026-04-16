using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Commands.Communications.AddComment;

public class AddCommentHandler(
    IRepository<CommunicationComment> commentRepository,
    IRepository<InternalCommunication> communicationRepository
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

            return AppResponse<Guid>.Success(comment.Id);
        }
        catch (Exception ex)
        {
            return AppResponse<Guid>.Error($"Lỗi khi thêm bình luận: {ex.Message}");
        }
    }
}
