using System.Text.Json;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Communications.CreateCommunication;

public class CreateCommunicationHandler(
    IRepository<InternalCommunication> communicationRepository
) : ICommandHandler<CreateCommunicationCommand, AppResponse<Guid>>
{
    public async Task<AppResponse<Guid>> Handle(
        CreateCommunicationCommand request,
        CancellationToken cancellationToken)
    {
        try
        {
            var communication = new InternalCommunication
            {
                Id = Guid.NewGuid(),
                StoreId = request.StoreId,
                Title = request.Title,
                Content = request.Content,
                Summary = request.Summary,
                ThumbnailUrl = request.ThumbnailUrl,
                AttachedImages = request.AttachedImages != null && request.AttachedImages.Any() 
                    ? JsonSerializer.Serialize(request.AttachedImages) 
                    : null,
                Type = request.Type,
                Priority = request.Priority,
                Status = request.PublishImmediately 
                    ? CommunicationStatus.Published 
                    : CommunicationStatus.Draft,
                AuthorId = request.CurrentUserId,
                AuthorName = request.CurrentUserName,
                TargetDepartmentId = request.TargetDepartmentId,
                PublishedAt = request.PublishImmediately ? DateTime.UtcNow : request.PublishedAt,
                ExpiresAt = request.ExpiresAt,
                IsPinned = request.IsPinned,
                Tags = request.Tags,
                IsAiGenerated = request.IsAiGenerated,
                AiPrompt = request.AiPrompt,
                ViewCount = 0,
                LikeCount = 0,
                CreatedAt = DateTime.UtcNow
            };

            await communicationRepository.AddAsync(communication, cancellationToken);

            return AppResponse<Guid>.Success(communication.Id);
        }
        catch (Exception ex)
        {
            return AppResponse<Guid>.Error($"Lỗi khi tạo bài truyền thông: {ex.Message}");
        }
    }
}
