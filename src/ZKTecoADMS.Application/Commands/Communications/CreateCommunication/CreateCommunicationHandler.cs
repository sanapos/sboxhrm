using System.Text.Json;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Application.Commands.Communications.CreateCommunication;

public class CreateCommunicationHandler(
    IRepository<InternalCommunication> communicationRepository,
    IRepository<Employee> employeeRepository,
    ISystemNotificationService notificationService
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

            // Fan out a notification only when the post is published immediately. Drafts are silent.
            if (communication.Status == CommunicationStatus.Published)
            {
                try
                {
                    System.Linq.Expressions.Expression<Func<Employee, bool>> filter = e =>
                        e.StoreId == request.StoreId
                        && e.ApplicationUserId.HasValue
                        && e.ApplicationUserId != Guid.Empty
                        && e.ApplicationUserId != request.CurrentUserId
                        && (request.TargetDepartmentId == null || e.DepartmentId == request.TargetDepartmentId);

                    var employees = await employeeRepository.GetAllAsync(
                        filter: filter, cancellationToken: cancellationToken);
                    var userIds = employees
                        .Where(e => e.ApplicationUserId.HasValue)
                        .Select(e => e.ApplicationUserId!.Value)
                        .Distinct()
                        .ToList();

                    if (userIds.Count > 0)
                    {
                        var notifType = communication.Priority == CommunicationPriority.High
                            ? NotificationType.Warning
                            : NotificationType.Info;
                        await notificationService.CreateAndSendToUsersAsync(
                            userIds, notifType,
                            communication.Title,
                            communication.Summary ?? StripHtml(communication.Content, 200),
                            relatedEntityId: communication.Id, relatedEntityType: "Communication",
                            fromUserId: request.CurrentUserId,
                            categoryCode: "communication", storeId: request.StoreId);
                    }
                }
                catch { /* best-effort */ }
            }

            return AppResponse<Guid>.Success(communication.Id);
        }
        catch (Exception ex)
        {
            return AppResponse<Guid>.Error($"Lỗi khi tạo bài truyền thông: {ex.Message}");
        }
    }

    private static string StripHtml(string html, int max)
    {
        if (string.IsNullOrEmpty(html)) return string.Empty;
        var text = System.Text.RegularExpressions.Regex.Replace(html, "<[^>]+>", " ").Trim();
        return text.Length > max ? text.Substring(0, max) + "…" : text;
    }
}
