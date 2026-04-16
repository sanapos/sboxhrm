using System.Text.Json;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Communications.UpdateCommunication;

public class UpdateCommunicationHandler(
    IRepository<InternalCommunication> communicationRepository
) : ICommandHandler<UpdateCommunicationCommand, AppResponse<bool>>
{
    public async Task<AppResponse<bool>> Handle(
        UpdateCommunicationCommand request,
        CancellationToken cancellationToken)
    {
        try
        {
            var communication = await communicationRepository.GetByIdAsync(request.Id, cancellationToken: cancellationToken);
            
            if (communication == null)
            {
                return AppResponse<bool>.Error("Không tìm thấy bài truyền thông");
            }

            if (communication.StoreId != request.StoreId)
            {
                return AppResponse<bool>.Error("Bạn không có quyền chỉnh sửa bài viết này");
            }

            // Update fields if provided
            if (!string.IsNullOrEmpty(request.Title))
                communication.Title = request.Title;
            
            if (!string.IsNullOrEmpty(request.Content))
                communication.Content = request.Content;
            
            if (request.Summary != null)
                communication.Summary = request.Summary;
            
            if (request.ThumbnailUrl != null)
                communication.ThumbnailUrl = request.ThumbnailUrl;
            
            if (request.AttachedImages != null)
                communication.AttachedImages = request.AttachedImages.Any() 
                    ? JsonSerializer.Serialize(request.AttachedImages) 
                    : null;
            
            if (request.Type.HasValue)
                communication.Type = request.Type.Value;
            
            if (request.Priority.HasValue)
                communication.Priority = request.Priority.Value;
            
            if (request.Status.HasValue)
            {
                communication.Status = request.Status.Value;
                if (request.Status.Value == CommunicationStatus.Published && !communication.PublishedAt.HasValue)
                {
                    communication.PublishedAt = DateTime.UtcNow;
                }
            }
            
            if (request.TargetDepartmentId.HasValue)
                communication.TargetDepartmentId = request.TargetDepartmentId;
            
            if (request.PublishedAt.HasValue)
                communication.PublishedAt = request.PublishedAt;
            
            if (request.ExpiresAt.HasValue)
                communication.ExpiresAt = request.ExpiresAt;
            
            if (request.IsPinned.HasValue)
                communication.IsPinned = request.IsPinned.Value;
            
            if (request.Tags != null)
                communication.Tags = request.Tags;

            communication.UpdatedAt = DateTime.UtcNow;

            await communicationRepository.UpdateAsync(communication, cancellationToken);

            return AppResponse<bool>.Success(true);
        }
        catch (Exception ex)
        {
            return AppResponse<bool>.Error($"Lỗi khi cập nhật bài truyền thông: {ex.Message}");
        }
    }
}
