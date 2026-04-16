using System.Linq.Expressions;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Application.Commands.Communications.ToggleReaction;

public class ToggleReactionHandler(
    IRepository<CommunicationReaction> reactionRepository,
    IRepository<InternalCommunication> communicationRepository
) : ICommandHandler<ToggleReactionCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(
        ToggleReactionCommand request,
        CancellationToken cancellationToken)
    {
        try
        {
            // Check if reaction already exists
            var existingReaction = await reactionRepository.GetSingleAsync(
                r => r.CommunicationId == request.CommunicationId && r.UserId == request.UserId,
                cancellationToken: cancellationToken);

            var communication = await communicationRepository.GetByIdAsync(request.CommunicationId, cancellationToken: cancellationToken);
            if (communication == null)
            {
                return AppResponse<bool>.Error("Không tìm thấy bài truyền thông");
            }

            if (existingReaction != null)
            {
                if (existingReaction.ReactionType == request.ReactionType)
                {
                    // Remove reaction (toggle off)
                    await reactionRepository.DeleteAsync(existingReaction, cancellationToken);
                    communication.LikeCount = Math.Max(0, communication.LikeCount - 1);
                }
                else
                {
                    // Change reaction type
                    existingReaction.ReactionType = request.ReactionType;
                    existingReaction.UpdatedAt = DateTime.UtcNow;
                    await reactionRepository.UpdateAsync(existingReaction, cancellationToken);
                }
            }
            else
            {
                // Add new reaction
                var reaction = new CommunicationReaction
                {
                    Id = Guid.NewGuid(),
                    CommunicationId = request.CommunicationId,
                    UserId = request.UserId,
                    ReactionType = request.ReactionType,
                    CreatedAt = DateTime.UtcNow
                };
                await reactionRepository.AddAsync(reaction, cancellationToken);
                communication.LikeCount += 1;
            }

            await communicationRepository.UpdateAsync(communication, cancellationToken);

            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error($"Lỗi khi cập nhật reaction: {ex.Message}");
        }
    }
}
