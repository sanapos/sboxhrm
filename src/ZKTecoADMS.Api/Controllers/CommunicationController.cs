using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using System.Linq.Expressions;
using System.Text.Json;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Hubs;
using ZKTecoADMS.Api.Models.Responses;
using ZKTecoADMS.Application.Commands.Communications.AddComment;
using ZKTecoADMS.Application.Commands.Communications.CreateCommunication;
using ZKTecoADMS.Application.Commands.Communications.DeleteCommunication;
using ZKTecoADMS.Application.Commands.Communications.ToggleReaction;
using ZKTecoADMS.Application.Commands.Communications.UpdateCommunication;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Application.DTOs.Communications;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/communications")]
public class CommunicationController(
    IMediator mediator,
    ZKTecoDbContext dbContext,
    IHubContext<AttendanceHub> hubContext,
    IGeminiAiService geminiAiService,
    IDeepSeekAiService deepSeekAiService,
    IFileStorageService fileStorageService,
    ISystemNotificationService notificationService,
    IModulePermissionService modulePermissionService,
    IConfiguration configuration,
    ILogger<CommunicationController> logger
) : AuthenticatedControllerBase
{
    /// <summary>
    /// Get list of communications with filtering and pagination
    /// </summary>
    [HttpGet]
    [Authorize]
    [ProducesResponseType(typeof(AppResponse<object>), StatusCodes.Status200OK)]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<IActionResult> GetCommunications([FromQuery] CommunicationFilterDto filter)
    {
        try
        {
            var storeId = CurrentStoreId;
            var query = storeId.HasValue
                ? dbContext.InternalCommunications.Where(c => c.StoreId == storeId.Value)
                : dbContext.InternalCommunications.AsQueryable();

            // Apply filters
            if (filter.Type.HasValue)
                query = query.Where(c => c.Type == filter.Type.Value);
            
            if (filter.Status.HasValue)
                query = query.Where(c => c.Status == filter.Status.Value);
            else if (!IsManager)
            {
                var now = DateTime.UtcNow;
                query = query.Where(c =>
                    c.AuthorId == CurrentUserId
                    || (c.Status == CommunicationStatus.Published
                        && (c.ExpiresAt == null || c.ExpiresAt > now)));
            }
            
            if (filter.Priority.HasValue)
                query = query.Where(c => c.Priority == filter.Priority.Value);
            
            if (filter.AuthorId.HasValue)
                query = query.Where(c => c.AuthorId == filter.AuthorId.Value);
            
            if (filter.DepartmentId.HasValue)
                query = query.Where(c => c.TargetDepartmentId == filter.DepartmentId.Value || c.TargetDepartmentId == null);
            
            if (filter.FromDate.HasValue)
                query = query.Where(c => c.CreatedAt >= filter.FromDate.Value);
            
            if (filter.ToDate.HasValue)
                query = query.Where(c => c.CreatedAt <= filter.ToDate.Value);
            
            if (!string.IsNullOrEmpty(filter.SearchTerm))
            {
                var term = filter.SearchTerm;
                query = query.Where(c =>
                    c.Title.Contains(term)
                    || c.Content.Contains(term)
                    || (c.Summary != null && c.Summary.Contains(term))
                    || (c.Tags != null && c.Tags.Contains(term))
                    || (c.AuthorName != null && c.AuthorName.Contains(term)));
            }
            
            if (filter.IsPinned.HasValue)
                query = query.Where(c => c.IsPinned == filter.IsPinned.Value);
            
            if (filter.IsAiGenerated.HasValue)
                query = query.Where(c => c.IsAiGenerated == filter.IsAiGenerated.Value);

            // Get total count
            var totalCount = await query.CountAsync();

            // Sort - pinned items always appear first regardless of sort field
            query = filter.SortBy?.ToLower() switch
            {
                "title" => filter.SortDescending 
                    ? query.OrderByDescending(c => c.IsPinned).ThenByDescending(c => c.Title) 
                    : query.OrderByDescending(c => c.IsPinned).ThenBy(c => c.Title),
                "publishedat" => filter.SortDescending 
                    ? query.OrderByDescending(c => c.IsPinned).ThenByDescending(c => c.PublishedAt) 
                    : query.OrderByDescending(c => c.IsPinned).ThenBy(c => c.PublishedAt),
                "viewcount" => filter.SortDescending 
                    ? query.OrderByDescending(c => c.IsPinned).ThenByDescending(c => c.ViewCount) 
                    : query.OrderByDescending(c => c.IsPinned).ThenBy(c => c.ViewCount),
                "likecount" => filter.SortDescending 
                    ? query.OrderByDescending(c => c.IsPinned).ThenByDescending(c => c.LikeCount) 
                    : query.OrderByDescending(c => c.IsPinned).ThenBy(c => c.LikeCount),
                "createdat" => filter.SortDescending 
                    ? query.OrderByDescending(c => c.IsPinned).ThenByDescending(c => c.CreatedAt) 
                    : query.OrderByDescending(c => c.IsPinned).ThenBy(c => c.CreatedAt),
                _ => query.OrderByDescending(c => c.IsPinned).ThenByDescending(c => c.CreatedAt)
            };

            // Paginate
            var entities = await query
                .Skip((filter.Page - 1) * filter.PageSize)
                .Take(filter.PageSize)
                .Select(c => new 
                {
                    c.Id,
                    c.StoreId,
                    c.Title,
                    c.Content,
                    c.Summary,
                    c.ThumbnailUrl,
                    c.AttachedImages,
                    c.Type,
                    c.Priority,
                    c.Status,
                    c.AuthorId,
                    c.AuthorName,
                    c.TargetDepartmentId,
                    c.PublishedAt,
                    c.ExpiresAt,
                    c.ViewCount,
                    c.LikeCount,
                    CommentCount = c.Comments.Count,
                    c.IsPinned,
                    c.IsAiGenerated,
                    c.Tags,
                    c.CreatedAt,
                    c.UpdatedAt,
                    c.IsPublicShareEnabled,
                    c.PublicShareToken,
                    HasUserReacted = c.Reactions.Any(r => r.UserId == CurrentUserId),
                    UserReactionType = c.Reactions.Where(r => r.UserId == CurrentUserId).Select(r => (ReactionType?)r.ReactionType).FirstOrDefault()
                })
                .ToListAsync();

            var items = entities.Select(c => new InternalCommunicationDto
            {
                Id = c.Id,
                StoreId = c.StoreId,
                Title = c.Title,
                Content = c.Content,
                Summary = c.Summary,
                ThumbnailUrl = c.ThumbnailUrl,
                AttachedImages = string.IsNullOrEmpty(c.AttachedImages)
                    ? new List<string>()
                    : JsonSerializer.Deserialize<List<string>>(c.AttachedImages) ?? new List<string>(),
                Type = c.Type,
                Priority = c.Priority,
                Status = c.Status,
                AuthorId = c.AuthorId,
                AuthorName = c.AuthorName,
                TargetDepartmentId = c.TargetDepartmentId,
                PublishedAt = c.PublishedAt,
                ExpiresAt = c.ExpiresAt,
                ViewCount = c.ViewCount,
                LikeCount = c.LikeCount,
                CommentCount = c.CommentCount,
                IsPinned = c.IsPinned,
                IsAiGenerated = c.IsAiGenerated,
                Tags = c.Tags,
                CreatedAt = c.CreatedAt,
                UpdatedAt = c.UpdatedAt,
                HasUserReacted = c.HasUserReacted,
                UserReactionType = c.UserReactionType,
                IsPublicShareEnabled = c.IsPublicShareEnabled,
                PublicShareToken = c.PublicShareToken,
                PublicShareUrl = BuildPublicShareUrl(c.PublicShareToken)
            }).ToList();

            var result = new
            {
                items,
                totalCount,
                totalPages = (int)Math.Ceiling((double)totalCount / filter.PageSize),
                currentPage = filter.Page,
                pageSize = filter.PageSize
            };

            return Ok(AppResponse<object>.Success(result));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error getting communications");
            return StatusCode(500, AppResponse<object>.Fail("Lá»—i khi láº¥y danh sÃ¡ch bÃ i truyá»n thÃ´ng"));
        }
    }

    /// <summary>
    /// Get a single communication by ID
    /// </summary>
    [HttpGet("{id:guid}")]
    [Authorize]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<IActionResult> GetCommunication(Guid id, [FromQuery] bool countView = false)
    {
        try
        {
            var storeId = CurrentStoreId;
            var baseQuery = storeId.HasValue
                ? dbContext.InternalCommunications.Where(c => c.Id == id && c.StoreId == storeId.Value)
                : dbContext.InternalCommunications.Where(c => c.Id == id);
            var entity = await baseQuery
                .Select(c => new
                {
                    c.Id,
                    c.StoreId,
                    c.Title,
                    c.Content,
                    c.Summary,
                    c.ThumbnailUrl,
                    c.AttachedImages,
                    c.Type,
                    c.Priority,
                    c.Status,
                    c.AuthorId,
                    c.AuthorName,
                    c.TargetDepartmentId,
                    TargetDepartmentName = c.TargetDepartment != null ? c.TargetDepartment.Name : null,
                    c.PublishedAt,
                    c.ExpiresAt,
                    c.ViewCount,
                    c.LikeCount,
                    CommentCount = c.Comments.Count,
                    c.IsPinned,
                    c.IsAiGenerated,
                    c.Tags,
                    c.CreatedAt,
                    c.UpdatedAt,
                    c.IsPublicShareEnabled,
                    c.PublicShareToken,
                    HasUserReacted = c.Reactions.Any(r => r.UserId == CurrentUserId),
                    UserReactionType = c.Reactions.Where(r => r.UserId == CurrentUserId).Select(r => (ReactionType?)r.ReactionType).FirstOrDefault()
                })
                .FirstOrDefaultAsync();

            if (entity == null)
            {
                return NotFound(AppResponse<object>.Fail("Không tìm thấy bài truyền thông"));
            }

            if (!CanAccessCommunication(entity.Status, entity.AuthorId, entity.ExpiresAt))
            {
                return StatusCode(403, AppResponse<object>.Fail("Bạn không có quyền xem bài viết này"));
            }

            var communication = new InternalCommunicationDto
            {
                Id = entity.Id,
                StoreId = entity.StoreId,
                Title = entity.Title,
                Content = entity.Content,
                Summary = entity.Summary,
                ThumbnailUrl = entity.ThumbnailUrl,
                AttachedImages = string.IsNullOrEmpty(entity.AttachedImages)
                    ? new List<string>()
                    : JsonSerializer.Deserialize<List<string>>(entity.AttachedImages) ?? new List<string>(),
                Type = entity.Type,
                Priority = entity.Priority,
                Status = entity.Status,
                AuthorId = entity.AuthorId,
                AuthorName = entity.AuthorName,
                TargetDepartmentId = entity.TargetDepartmentId,
                TargetDepartmentName = entity.TargetDepartmentName,
                PublishedAt = entity.PublishedAt,
                ExpiresAt = entity.ExpiresAt,
                ViewCount = entity.ViewCount,
                LikeCount = entity.LikeCount,
                CommentCount = entity.CommentCount,
                IsPinned = entity.IsPinned,
                IsAiGenerated = entity.IsAiGenerated,
                Tags = entity.Tags,
                CreatedAt = entity.CreatedAt,
                UpdatedAt = entity.UpdatedAt,
                HasUserReacted = entity.HasUserReacted,
                UserReactionType = entity.UserReactionType,
                IsPublicShareEnabled = entity.IsPublicShareEnabled,
                PublicShareToken = entity.PublicShareToken,
                PublicShareUrl = BuildPublicShareUrl(entity.PublicShareToken)
            };

            if (countView)
            {
                await dbContext.InternalCommunications
                    .Where(c => c.Id == id)
                    .ExecuteUpdateAsync(s => s.SetProperty(c => c.ViewCount, c => c.ViewCount + 1));
                communication.ViewCount += 1;
            }

            return Ok(AppResponse<InternalCommunicationDto>.Success(communication));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error getting communication {Id}", id);
            return StatusCode(500, AppResponse<object>.Fail("Lá»—i khi láº¥y bÃ i truyá»n thÃ´ng"));
        }
    }

    /// <summary>
    /// Create a new communication
    /// </summary>
    [HttpPost]
    [Authorize]
    [RequireModulePermission("Communication", ModulePermissionAction.Create)]
    public async Task<IActionResult> CreateCommunication([FromBody] CreateCommunicationDto dto)
    {
        try
        {
            var canApprove = await HasCommunicationApproveAsync();
            var submitForApproval = dto.SubmitForApproval
                || (!dto.PublishImmediately && !canApprove && !IsManager);

            var command = new CreateCommunicationCommand(
                RequiredStoreId,
                CurrentUserId,
                User.FindFirst(System.Security.Claims.ClaimTypes.Name)?.Value ?? "Unknown",
                dto.Title,
                dto.Content,
                dto.Summary,
                dto.ThumbnailUrl,
                dto.AttachedImages,
                dto.Type,
                dto.Priority,
                dto.TargetDepartmentId,
                dto.PublishedAt,
                dto.ExpiresAt,
                dto.IsPinned,
                dto.Tags,
                dto.PublishImmediately,
                submitForApproval,
                dto.IsPublicShareEnabled,
                dto.IsAiGenerated,
                dto.AiPrompt
            );

            var result = await mediator.Send(command);

            // Broadcast new communication via SignalR
            if (result.IsSuccess)
            {
                _ = hubContext.Clients.Group($"store_{RequiredStoreId}")
                    .SendAsync("CommunicationCreated", new { id = result.Data, title = dto.Title, type = dto.Type });

                // Notify employees if published immediately
                if (dto.PublishImmediately)
                {
                    try
                    {
                        var empQuery = dbContext.Employees
                            .Where(e => e.StoreId == RequiredStoreId && e.ApplicationUserId != null && e.Deleted == null);
                        if (dto.TargetDepartmentId.HasValue)
                            empQuery = empQuery.Where(e => e.DepartmentId == dto.TargetDepartmentId.Value);
                        var empUserIds = await empQuery.Select(e => e.ApplicationUserId!.Value).Distinct().ToListAsync();
                        foreach (var uid in empUserIds)
                        {
                            if (uid != CurrentUserId)
                                await notificationService.CreateAndSendAsync(
                                    uid, NotificationType.Info,
                                    "BÃ i truyá»n thÃ´ng má»›i",
                                    $"BÃ i viáº¿t \"{dto.Title}\" Ä‘Ã£ Ä‘Æ°á»£c Ä‘Äƒng",
                                    relatedEntityType: "Communication", relatedEntityId: result.Data,
                                    fromUserId: CurrentUserId, categoryCode: "communication", storeId: RequiredStoreId);
                        }
                    }
                    catch { /* Notification failure should not affect main operation */ }
                }
            }

            return Ok(result);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error creating communication");
            return StatusCode(500, AppResponse<Guid>.Fail("Lá»—i khi táº¡o bÃ i truyá»n thÃ´ng"));
        }
    }

    /// <summary>
    /// Update a communication
    /// </summary>
    [HttpPut("{id:guid}")]
    [Authorize]
    [RequireModulePermission("Communication", ModulePermissionAction.Edit)]
    public async Task<IActionResult> UpdateCommunication(Guid id, [FromBody] UpdateCommunicationDto dto)
    {
        try
        {
            dto.Id = id;

            var access = await dbContext.InternalCommunications.AsNoTracking()
                .Where(c => c.Id == id)
                .Select(c => new { c.StoreId, c.AuthorId })
                .FirstOrDefaultAsync();
            if (access == null)
                return NotFound(AppResponse<bool>.Fail("Không tìm thấy bài truyền thông"));
            if (access.StoreId != RequiredStoreId)
                return StatusCode(403, AppResponse<bool>.Fail("Bạn không có quyền chỉnh sửa bài viết này"));
            if (!IsManager && access.AuthorId != CurrentUserId)
                return StatusCode(403, AppResponse<bool>.Fail("Bạn chỉ có thể sửa bài viết của mình"));

            if (dto.Status == CommunicationStatus.Published)
            {
                var canApprovePublish = await HasCommunicationApproveAsync();
                if (!canApprovePublish && !IsManager && access.AuthorId != CurrentUserId)
                    return StatusCode(403, AppResponse<bool>.Fail("Bạn không có quyền xuất bản bài viết này"));
            }

            // Check if this update is publishing a draft
            var oldEntity = await dbContext.InternalCommunications.AsNoTracking()
                .Where(c => c.Id == id).Select(c => new { c.Status, c.StoreId, c.TargetDepartmentId }).FirstOrDefaultAsync();
            var isPublishing = oldEntity != null && oldEntity.Status != CommunicationStatus.Published
                && dto.Status == CommunicationStatus.Published;

            var command = new UpdateCommunicationCommand(
                id,
                RequiredStoreId,
                CurrentUserId,
                dto.Title,
                dto.Content,
                dto.Summary,
                dto.ThumbnailUrl,
                dto.AttachedImages,
                dto.Type,
                dto.Priority,
                dto.Status,
                dto.TargetDepartmentId,
                dto.PublishedAt,
                dto.ExpiresAt,
                dto.IsPinned,
                dto.Tags,
                dto.IsPublicShareEnabled
            );

            var result = await mediator.Send(command);

            // Notify employees if status changed to Published
            if (result.IsSuccess && isPublishing && oldEntity != null)
            {
                try
                {
                    _ = hubContext.Clients.Group($"store_{oldEntity.StoreId}")
                        .SendAsync("CommunicationPublished", new { id, title = dto.Title, type = dto.Type });

                    var empQuery = dbContext.Employees
                        .Where(e => e.StoreId == oldEntity.StoreId && e.ApplicationUserId != null && e.Deleted == null);
                    var deptId = dto.TargetDepartmentId ?? oldEntity.TargetDepartmentId;
                    if (deptId.HasValue)
                        empQuery = empQuery.Where(e => e.DepartmentId == deptId.Value);
                    var empUserIds = await empQuery.Select(e => e.ApplicationUserId!.Value).Distinct().ToListAsync();
                    foreach (var uid in empUserIds)
                    {
                        if (uid != CurrentUserId)
                            await notificationService.CreateAndSendAsync(
                                uid, NotificationType.Info,
                                "BÃ i truyá»n thÃ´ng má»›i",
                                $"BÃ i viáº¿t \"{dto.Title}\" Ä‘Ã£ Ä‘Æ°á»£c Ä‘Äƒng",
                                relatedEntityType: "Communication", relatedEntityId: id,
                                fromUserId: CurrentUserId, categoryCode: "communication", storeId: oldEntity.StoreId);
                    }
                }
                catch { /* Notification failure should not affect main operation */ }
            }

            return Ok(result);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error updating communication {Id}", id);
            return StatusCode(500, AppResponse<bool>.Fail("Lá»—i khi cáº­p nháº­t bÃ i truyá»n thÃ´ng"));
        }
    }

    /// <summary>
    /// Bật/tắt link chia sẻ công khai (không cần đăng nhập).
    /// </summary>
    [HttpPut("{id:guid}/public-share")]
    [Authorize]
    [RequireModulePermission("Communication", ModulePermissionAction.Edit)]
    public async Task<IActionResult> SetPublicShare(Guid id, [FromBody] CommunicationPublicShareDto dto)
    {
        try
        {
            var entity = await dbContext.InternalCommunications
                .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == RequiredStoreId);
            if (entity == null)
                return NotFound(AppResponse<object>.Fail("Không tìm thấy bài truyền thông"));
            if (!IsManager && entity.AuthorId != CurrentUserId)
                return StatusCode(403, AppResponse<object>.Fail("Bạn chỉ có thể cấu hình chia sẻ bài viết của mình"));

            entity.IsPublicShareEnabled = dto.Enabled;
            if (dto.Enabled)
            {
                if (dto.RegenerateToken || string.IsNullOrEmpty(entity.PublicShareToken))
                    entity.PublicShareToken = CommunicationShareTokenHelper.Generate();
            }
            else
            {
                entity.PublicShareToken = null;
            }

            entity.UpdatedAt = DateTime.UtcNow;
            await dbContext.SaveChangesAsync();

            return Ok(AppResponse<object>.Success(new
            {
                isPublicShareEnabled = entity.IsPublicShareEnabled,
                publicShareToken = entity.PublicShareToken,
                publicShareUrl = BuildPublicShareUrl(entity.PublicShareToken)
            }));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error setting public share for communication {Id}", id);
            return StatusCode(500, AppResponse<object>.Fail("Lỗi khi cấu hình chia sẻ link"));
        }
    }

    /// <summary>
    /// Delete a communication
    /// </summary>
    [HttpDelete("{id:guid}")]
    [Authorize]
    [RequireModulePermission("Communication", ModulePermissionAction.Delete)]
    public async Task<IActionResult> DeleteCommunication(Guid id)
    {
        try
        {
            var access = await dbContext.InternalCommunications.AsNoTracking()
                .Where(c => c.Id == id)
                .Select(c => new { c.StoreId, c.AuthorId })
                .FirstOrDefaultAsync();
            if (access == null)
                return NotFound(AppResponse<bool>.Fail("Không tìm thấy bài truyền thông"));
            if (access.StoreId != RequiredStoreId)
                return StatusCode(403, AppResponse<bool>.Fail("Bạn không có quyền xóa bài viết này"));
            if (!IsManager && access.AuthorId != CurrentUserId)
                return StatusCode(403, AppResponse<bool>.Fail("Bạn chỉ có thể xóa bài viết của mình"));

            var command = new DeleteCommunicationCommand(id, RequiredStoreId, CurrentUserId);
            var result = await mediator.Send(command);
            return Ok(result);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error deleting communication {Id}", id);
            return StatusCode(500, AppResponse<bool>.Fail("Lá»—i khi xÃ³a bÃ i truyá»n thÃ´ng"));
        }
    }

    /// <summary>
    /// Publish a draft communication
    /// </summary>
    [HttpPost("{id:guid}/publish")]
    [Authorize]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<IActionResult> PublishCommunication(Guid id)
    {
        try
        {
            // Load without tracking to check authorization
            var entity = await dbContext.InternalCommunications
                .AsNoTracking()
                .FirstOrDefaultAsync(c => c.Id == id);
            if (entity == null)
                return NotFound(AppResponse<bool>.Fail("Không tìm thấy bài truyền thông"));

            if (CurrentStoreId.HasValue && entity.StoreId != CurrentStoreId.Value)
                return StatusCode(403, AppResponse<bool>.Fail("Bạn không có quyền xuất bản bài viết này"));

            var canApprove = await HasCommunicationApproveAsync();
            if (entity.Status == CommunicationStatus.PendingApproval)
            {
                if (!canApprove && !IsManager)
                    return StatusCode(403, AppResponse<bool>.Fail("Bài đang chờ duyệt — cần quyền duyệt truyền thông"));
            }
            else if (!canApprove && !IsManager && entity.AuthorId != CurrentUserId)
            {
                return StatusCode(403, AppResponse<bool>.Fail("Bạn chỉ có thể xuất bản bài viết của mình"));
            }

            var now = DateTime.UtcNow;
            var publishedAt = entity.PublishedAt ?? now;

            // Use ExecuteUpdateAsync for direct SQL UPDATE â€“ bypasses all EF change tracking
            var affected = await dbContext.InternalCommunications
                .Where(c => c.Id == id)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(c => c.Status, CommunicationStatus.Published)
                    .SetProperty(c => c.PublishedAt, publishedAt)
                    .SetProperty(c => c.UpdatedAt, now));

            logger.LogInformation("PublishCommunication: id={Id} affected={Affected}", id, affected);

            if (affected == 0)
                return StatusCode(500, AppResponse<bool>.Fail("KhÃ´ng thá»ƒ cáº­p nháº­t tráº¡ng thÃ¡i bÃ i viáº¿t"));

            // Broadcast published communication via SignalR
            _ = hubContext.Clients.Group($"store_{entity.StoreId}")
                .SendAsync("CommunicationPublished", new { id = entity.Id, title = entity.Title, type = entity.Type });

            // Notify all target employees about the published communication
            try
            {
                var empQuery = dbContext.Employees
                    .Where(e => e.StoreId == entity.StoreId && e.ApplicationUserId != null && e.Deleted == null);
                if (entity.TargetDepartmentId.HasValue)
                    empQuery = empQuery.Where(e => e.DepartmentId == entity.TargetDepartmentId.Value);
                var empUserIds = await empQuery.Select(e => e.ApplicationUserId!.Value).Distinct().ToListAsync();
                foreach (var uid in empUserIds)
                {
                    if (uid != CurrentUserId)
                        await notificationService.CreateAndSendAsync(
                            uid, NotificationType.Info,
                            "BÃ i truyá»n thÃ´ng má»›i",
                            $"BÃ i viáº¿t \"{entity.Title}\" Ä‘Ã£ Ä‘Æ°á»£c Ä‘Äƒng",
                            relatedEntityType: "Communication", relatedEntityId: entity.Id,
                            fromUserId: CurrentUserId, categoryCode: "communication", storeId: entity.StoreId);
                }
            }
            catch { /* Notification failure should not affect main operation */ }

            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error publishing communication {Id}", id);
            return StatusCode(500, AppResponse<bool>.Fail("Lá»—i khi xuáº¥t báº£n bÃ i truyá»n thÃ´ng"));
        }
    }

    /// <summary>
    /// Get comments for a communication
    /// </summary>
    [HttpGet("{id:guid}/comments")]
    [Authorize]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<IActionResult> GetComments(Guid id, [FromQuery] int page = 1, [FromQuery] int pageSize = 50)
    {
        try
        {
            var accessDenied = await DenyCommunicationInteractionIfForbiddenAsync(id);
            if (accessDenied != null) return accessDenied;

            // Clamp pageSize to prevent abuse
            pageSize = Math.Clamp(pageSize, 1, 100);

            var totalCount = await dbContext.CommunicationComments
                .Where(c => c.CommunicationId == id && c.ParentCommentId == null)
                .CountAsync();

            var comments = await dbContext.CommunicationComments
                .Where(c => c.CommunicationId == id && c.ParentCommentId == null)
                .OrderByDescending(c => c.CreatedAt)
                .Skip((page - 1) * pageSize)
                .Take(pageSize)
                .Select(c => new CommunicationCommentDto
                {
                    Id = c.Id,
                    CommunicationId = c.CommunicationId,
                    UserId = c.UserId,
                    UserName = c.UserName,
                    Content = c.Content,
                    ParentCommentId = c.ParentCommentId,
                    LikeCount = c.LikeCount,
                    CreatedAt = c.CreatedAt,
                    Replies = c.Replies
                        .OrderBy(r => r.CreatedAt)
                        .Select(r => new CommunicationCommentDto
                        {
                            Id = r.Id,
                            CommunicationId = r.CommunicationId,
                            UserId = r.UserId,
                            UserName = r.UserName,
                            Content = r.Content,
                            ParentCommentId = r.ParentCommentId,
                            LikeCount = r.LikeCount,
                            CreatedAt = r.CreatedAt
                        }).ToList()
                })
                .ToListAsync();

            var result = new
            {
                items = comments,
                totalCount,
                totalPages = (int)Math.Ceiling((double)totalCount / pageSize),
                currentPage = page,
                pageSize
            };

            return Ok(AppResponse<object>.Success(result));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error getting comments for communication {Id}", id);
            return StatusCode(500, AppResponse<object>.Fail("Lá»—i khi láº¥y bÃ¬nh luáº­n"));
        }
    }

    /// <summary>
    /// Add a comment to a communication (requires View — same as reading the post).
    /// </summary>
    [HttpPost("{id:guid}/comments")]
    [Authorize]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<IActionResult> AddComment(Guid id, [FromBody] AddCommentDto dto)
    {
        try
        {
            var accessDenied = await DenyCommunicationInteractionIfForbiddenAsync(id);
            if (accessDenied != null) return accessDenied;

            var command = new AddCommentCommand(
                id,
                CurrentUserId,
                User.FindFirst(System.Security.Claims.ClaimTypes.Name)?.Value ?? "Unknown",
                dto.Content,
                dto.ParentCommentId
            );

            var result = await mediator.Send(command);

            // Broadcast new comment via SignalR
            if (result.IsSuccess)
            {
                var comm = await dbContext.InternalCommunications
                    .Where(c => c.Id == id)
                    .Select(c => new { c.StoreId, c.AuthorId, c.Title })
                    .FirstOrDefaultAsync();
                if (comm != null)
                {
                    _ = hubContext.Clients.Group($"store_{comm.StoreId}")
                        .SendAsync("CommunicationCommentAdded", new
                        {
                            communicationId = id,
                            commentId = result.Data,
                            userName = User.FindFirst(System.Security.Claims.ClaimTypes.Name)?.Value
                        });

                    // Notify the post author about the new comment
                    try
                    {
                        if (comm.AuthorId != CurrentUserId)
                        {
                            var authorUserId = await dbContext.Employees
                                .Where(e => e.Id == comm.AuthorId && e.ApplicationUserId != null)
                                .Select(e => e.ApplicationUserId!.Value)
                                .FirstOrDefaultAsync();
                            if (authorUserId != Guid.Empty && authorUserId != CurrentUserId)
                            {
                                var commenterName = User.FindFirst(System.Security.Claims.ClaimTypes.Name)?.Value ?? "Ai Ä‘Ã³";
                                await notificationService.CreateAndSendAsync(
                                    authorUserId, NotificationType.Info,
                                    "BÃ¬nh luáº­n má»›i",
                                    $"{commenterName} Ä‘Ã£ bÃ¬nh luáº­n bÃ i viáº¿t \"{comm.Title}\"",
                                    relatedEntityType: "Communication", relatedEntityId: id,
                                    fromUserId: CurrentUserId, categoryCode: "communication", storeId: comm.StoreId);
                            }
                        }
                    }
                    catch { /* Notification failure should not affect main operation */ }
                }
            }

            return Ok(result);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error adding comment");
            return StatusCode(500, AppResponse<Guid>.Fail("Lá»—i khi thÃªm bÃ¬nh luáº­n"));
        }
    }

    /// <summary>
    /// Toggle a reaction on a communication (requires View — same as reading the post).
    /// </summary>
    [HttpPost("{id:guid}/reactions")]
    [Authorize]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<IActionResult> ToggleReaction(Guid id, [FromBody] CommunicationReactionDto dto)
    {
        try
        {
            var accessDenied = await DenyCommunicationInteractionIfForbiddenAsync(id);
            if (accessDenied != null) return accessDenied;

            var command = new ToggleReactionCommand(id, CurrentUserId, dto.ReactionType);
            var result = await mediator.Send(command);

            // Broadcast reaction update via SignalR
            if (result.IsSuccess)
            {
                var comm = await dbContext.InternalCommunications
                    .Where(c => c.Id == id)
                    .Select(c => new { c.StoreId, c.LikeCount })
                    .FirstOrDefaultAsync();
                if (comm != null)
                {
                    _ = hubContext.Clients.Group($"store_{comm.StoreId}")
                        .SendAsync("CommunicationReactionUpdated", new
                        {
                            communicationId = id,
                            likeCount = comm.LikeCount,
                            reactionType = dto.ReactionType
                        });
                }
            }

            return Ok(result);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error toggling reaction");
            return StatusCode(500, AppResponse<bool>.Fail("Lá»—i khi cáº­p nháº­t reaction"));
        }
    }

    /// <summary>
    /// Stream AI content generation via Server-Sent Events
    /// </summary>
    [HttpPost("ai/generate-stream")]
    [Authorize]
    [RequireModulePermission("Communication", ModulePermissionAction.Create)]
    public async Task StreamAiContent([FromBody] AiContentGenerationDto dto, CancellationToken cancellationToken)
    {
        Response.Headers.Append("Content-Type", "text/event-stream");
        Response.Headers.Append("Cache-Control", "no-cache");
        Response.Headers.Append("Connection", "keep-alive");

        try
        {
            var useDeepSeek = string.Equals(dto.Provider, "deepseek", StringComparison.OrdinalIgnoreCase);
            var useGemini = string.Equals(dto.Provider, "gemini", StringComparison.OrdinalIgnoreCase);

            // Auto-select: chỉ Gemini (DeepSeek đã ngừng hỗ trợ)
            if (string.IsNullOrEmpty(dto.Provider) || useDeepSeek)
                useGemini = geminiAiService.IsConfigured && geminiAiService.IsEnabled;

            if (!useGemini || !geminiAiService.IsConfigured || !geminiAiService.IsEnabled)
            {
                await WriteSseEvent("error", "Gemini AI chưa được bật hoặc chưa cấu hình API key");
                return;
            }

            var typeLabel = dto.Type switch
            {
                CommunicationType.News => "tin tá»©c ná»™i bá»™",
                CommunicationType.Announcement => "thÃ´ng bÃ¡o",
                CommunicationType.Event => "sá»± kiá»‡n",
                CommunicationType.Policy => "chÃ­nh sÃ¡ch",
                CommunicationType.Training => "Ä‘Ã o táº¡o",
                CommunicationType.Culture => "vÄƒn hÃ³a cÃ´ng ty",
                CommunicationType.Recruitment => "tuyá»ƒn dá»¥ng",
                CommunicationType.Regulation => "ná»™i quy cÃ´ng ty",
                _ => "bÃ i viáº¿t"
            };

            var toneLabel = dto.Tone?.ToLower() switch
            {
                "formal" => "trang trá»ng, chuyÃªn nghiá»‡p",
                "friendly" => "thÃ¢n thiá»‡n, gáº§n gÅ©i",
                "creative" => "sÃ¡ng táº¡o, háº¥p dáº«n",
                "inspirational" => "truyá»n cáº£m há»©ng, Ä‘á»™ng lá»±c",
                _ => "chuyÃªn nghiá»‡p"
            };

            var stream = geminiAiService.StreamGenerateCommunicationContentAsync(
                dto.Prompt, typeLabel, toneLabel, dto.Context, dto.MaxLength, cancellationToken);

            await foreach (var chunk in stream)
            {
                if (cancellationToken.IsCancellationRequested) break;
                await WriteSseEvent("chunk", chunk);
                await Response.Body.FlushAsync(cancellationToken);
            }

            await WriteSseEvent("done", "");
        }
        catch (AiApiException ex)
        {
            logger.LogError(ex, "AI API error during streaming");
            await WriteSseEvent("error", ex.Message);
        }
        catch (OperationCanceledException)
        {
            // Client disconnected, that's fine
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error streaming AI content");
            await WriteSseEvent("error", $"Lá»—i khi táº¡o ná»™i dung AI: {ex.Message}");
        }
    }

    private async Task WriteSseEvent(string eventType, string data)
    {
        var escaped = data.Replace("\n", "\\n").Replace("\r", "");
        await Response.WriteAsync($"event: {eventType}\ndata: {escaped}\n\n");
        await Response.Body.FlushAsync();
    }

    /// <summary>
    /// Generate AI content for communication
    /// </summary>
    [HttpPost("ai/generate")]
    [Authorize]
    [RequireModulePermission("Communication", ModulePermissionAction.Create)]
    public async Task<IActionResult> GenerateAiContent([FromBody] AiContentGenerationDto dto)
    {
        try
        {
            var typeLabel = dto.Type switch
            {
                CommunicationType.News => "tin tá»©c ná»™i bá»™",
                CommunicationType.Announcement => "thÃ´ng bÃ¡o",
                CommunicationType.Event => "sá»± kiá»‡n",
                CommunicationType.Policy => "chÃ­nh sÃ¡ch",
                CommunicationType.Training => "Ä‘Ã o táº¡o",
                CommunicationType.Culture => "vÄƒn hÃ³a cÃ´ng ty",
                CommunicationType.Recruitment => "tuyá»ƒn dá»¥ng",
                CommunicationType.Regulation => "ná»™i quy cÃ´ng ty",
                _ => "bÃ i viáº¿t"
            };

            var toneLabel = dto.Tone?.ToLower() switch
            {
                "formal" => "trang trá»ng, chuyÃªn nghiá»‡p",
                "friendly" => "thÃ¢n thiá»‡n, gáº§n gÅ©i",
                "creative" => "sÃ¡ng táº¡o, háº¥p dáº«n",
                "inspirational" => "truyá»n cáº£m há»©ng, Ä‘á»™ng lá»±c",
                _ => "chuyÃªn nghiá»‡p"
            };

            AiGeneratedContentDto result;

            var useDeepSeek = string.Equals(dto.Provider, "deepseek", StringComparison.OrdinalIgnoreCase);
            var useGemini = string.Equals(dto.Provider, "gemini", StringComparison.OrdinalIgnoreCase);

            if (string.IsNullOrEmpty(dto.Provider) || useDeepSeek)
                useGemini = geminiAiService.IsConfigured && geminiAiService.IsEnabled;

            if (useGemini && geminiAiService.IsConfigured && geminiAiService.IsEnabled)
            {
                var generated = await geminiAiService.GenerateCommunicationContentAsync(
                    dto.Prompt, typeLabel, toneLabel, dto.Context, dto.MaxLength);

                result = new AiGeneratedContentDto
                {
                    Title = generated.Title,
                    Content = generated.Content,
                    Summary = generated.Summary,
                    SuggestedTags = generated.Tags,
                    Prompt = dto.Prompt
                };
            }
            else
            {
                // Fallback to template
                var generated = GenerateContentFromPrompt(dto.Prompt, typeLabel, toneLabel, dto.Context, dto.MaxLength);
                result = new AiGeneratedContentDto
                {
                    Title = generated.Title,
                    Content = generated.Content,
                    Summary = generated.Summary,
                    SuggestedTags = generated.Tags,
                    Prompt = dto.Prompt
                };
            }

            return Ok(AppResponse<AiGeneratedContentDto>.Success(result));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error generating AI content");
            return StatusCode(500, AppResponse<AiGeneratedContentDto>.Fail($"Lá»—i khi táº¡o ná»™i dung AI: {ex.Message}"));
        }
    }

    /// <summary>
    /// Upload image for communication
    /// </summary>
    [HttpPost("upload-image")]
    [Authorize]
    [RequestSizeLimit(10 * 1024 * 1024)] // 10MB
    [RequireModulePermission("Communication", ModulePermissionAction.Create)]
    public async Task<IActionResult> UploadImage(IFormFile file)
    {
        try
        {
            if (file == null || file.Length == 0)
            {
                return BadRequest(AppResponse<string>.Fail("Vui lÃ²ng chá»n file áº£nh"));
            }

            var allowedTypes = new[] { "image/jpeg", "image/png", "image/gif", "image/webp" };
            if (!allowedTypes.Contains(file.ContentType.ToLower()))
            {
                return BadRequest(AppResponse<string>.Fail("Chá»‰ há»— trá»£ Ä‘á»‹nh dáº¡ng JPEG, PNG, GIF, WebP"));
            }

            using var stream = file.OpenReadStream();

            // Validate magic bytes
            var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
            if (!ValidateImageMagicBytes(stream, ext))
            {
                return BadRequest(AppResponse<string>.Fail("Ná»™i dung file khÃ´ng khá»›p vá»›i Ä‘á»‹nh dáº¡ng khai bÃ¡o"));
            }
            stream.Position = 0;

            var uploadFolder = await GetStoreFolderAsync("uploads/communications");
            var storedPath = await fileStorageService.UploadAsync(stream, file.FileName, uploadFolder);
            var imageUrl = fileStorageService.GetFileUrl(storedPath);

            return Ok(AppResponse<string>.Success(imageUrl));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error uploading image");
            return StatusCode(500, AppResponse<string>.Fail("Lá»—i khi upload áº£nh"));
        }
    }

    /// <summary>
    /// Upload image for communication (base64 - for web compatibility)
    /// </summary>
    [HttpPost("upload-image-base64")]
    [Authorize]
    [RequestSizeLimit(15_000_000)] // 15MB limit for base64 overhead
    [RequireModulePermission("Communication", ModulePermissionAction.Create)]
    public async Task<IActionResult> UploadImageBase64([FromBody] ImageBase64UploadDto dto)
    {
        try
        {
            if (string.IsNullOrEmpty(dto.Base64Data) || string.IsNullOrEmpty(dto.FileName))
            {
                return BadRequest(AppResponse<string>.Fail("Vui lÃ²ng chá»n file áº£nh"));
            }

            var extension = Path.GetExtension(dto.FileName).ToLower();
            var allowedExtensions = new[] { ".jpg", ".jpeg", ".png", ".gif", ".webp" };
            if (!allowedExtensions.Contains(extension))
            {
                return BadRequest(AppResponse<string>.Fail("Chá»‰ há»— trá»£ Ä‘á»‹nh dáº¡ng JPEG, PNG, GIF, WebP"));
            }

            // Remove data URI prefix if present (e.g., "data:image/png;base64,")
            var base64 = dto.Base64Data;
            if (base64.Contains(","))
            {
                base64 = base64.Substring(base64.IndexOf(",") + 1);
            }

            // Pre-validate size from base64 length BEFORE decoding to prevent memory exhaustion
            var estimatedSize = (long)(base64.Length * 3.0 / 4.0);
            if (estimatedSize > 10 * 1024 * 1024)
            {
                return BadRequest(AppResponse<string>.Fail("KÃ­ch thÆ°á»›c áº£nh tá»‘i Ä‘a 10MB"));
            }

            byte[] fileBytes;
            try
            {
                fileBytes = Convert.FromBase64String(base64);
            }
            catch
            {
                return BadRequest(AppResponse<string>.Fail("Dá»¯ liá»‡u áº£nh khÃ´ng há»£p lá»‡"));
            }

            if (fileBytes.Length > 10 * 1024 * 1024)
            {
                return BadRequest(AppResponse<string>.Fail("KÃ­ch thÆ°á»›c áº£nh tá»‘i Ä‘a 10MB"));
            }

            // Validate magic bytes
            using var checkStream = new MemoryStream(fileBytes);
            if (!ValidateImageMagicBytes(checkStream, extension))
            {
                return BadRequest(AppResponse<string>.Fail("Ná»™i dung file khÃ´ng khá»›p vá»›i Ä‘á»‹nh dáº¡ng khai bÃ¡o"));
            }

            using var stream = new MemoryStream(fileBytes);
            var uploadFolder = await GetStoreFolderAsync("uploads/communications");
            var storedPath = await fileStorageService.UploadAsync(stream, dto.FileName, uploadFolder);
            var imageUrl = fileStorageService.GetFileUrl(storedPath);

            return Ok(AppResponse<string>.Success(imageUrl));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error uploading base64 image");
            return StatusCode(500, AppResponse<string>.Fail("Lá»—i khi upload áº£nh"));
        }
    }

    /// <summary>
    /// Get communication statistics
    /// </summary>
    [HttpGet("stats")]
    [Authorize]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<IActionResult> GetStats()
    {
        try
        {
            var storeId = CurrentStoreId;
            var baseQuery = storeId.HasValue
                ? dbContext.InternalCommunications.Where(c => c.StoreId == storeId.Value)
                : dbContext.InternalCommunications.AsQueryable();
            if (!IsManager)
            {
                var now = DateTime.UtcNow;
                baseQuery = baseQuery.Where(c =>
                    c.AuthorId == CurrentUserId
                    || (c.Status == CommunicationStatus.Published
                        && (c.ExpiresAt == null || c.ExpiresAt > now)));
            }
            var stats = new
            {
                totalPosts = await baseQuery.CountAsync(),
                publishedPosts = await baseQuery.CountAsync(c => c.Status == CommunicationStatus.Published),
                draftPosts = await baseQuery.CountAsync(c => c.Status == CommunicationStatus.Draft),
                pendingPosts = await baseQuery.CountAsync(c => c.Status == CommunicationStatus.PendingApproval),
                aiGeneratedPosts = await baseQuery.CountAsync(c => c.IsAiGenerated),
                totalViews = await baseQuery.SumAsync(c => c.ViewCount),
                totalLikes = await baseQuery.SumAsync(c => c.LikeCount),
                totalComments = await dbContext.CommunicationComments
                    .CountAsync(c => baseQuery.Any(ic => ic.Id == c.CommunicationId)),
                typeDistribution = await baseQuery
                    .GroupBy(c => c.Type)
                    .Select(g => new { type = g.Key.ToString(), count = g.Count() })
                    .ToListAsync()
            };

            return Ok(AppResponse<object>.Success(stats));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error getting communication stats");
            return StatusCode(500, AppResponse<object>.Fail("Lá»—i khi láº¥y thá»‘ng kÃª"));
        }
    }

    #region Private Helpers

    private async Task<bool> HasCommunicationApproveAsync(CancellationToken cancellationToken = default)
    {
        if (IsManager) return true;
        return await modulePermissionService.HasPermissionAsync(
            CurrentUserId,
            CurrentUserRole,
            CurrentStoreId,
            "Communication",
            ModulePermissionAction.Approve,
            cancellationToken);
    }

    private bool CanAccessCommunication(
        CommunicationStatus status,
        Guid authorId,
        DateTime? expiresAt)
    {
        if (IsManager) return true;
        if (authorId == CurrentUserId) return true;
        if (status != CommunicationStatus.Published) return false;
        if (expiresAt.HasValue && expiresAt.Value < DateTime.UtcNow) return false;
        return true;
    }

    private async Task<IActionResult?> DenyCommunicationInteractionIfForbiddenAsync(Guid id)
    {
        var storeId = CurrentStoreId;
        var baseQuery = storeId.HasValue
            ? dbContext.InternalCommunications.Where(c => c.Id == id && c.StoreId == storeId.Value)
            : dbContext.InternalCommunications.Where(c => c.Id == id);
        var access = await baseQuery
            .Select(c => new { c.Status, c.AuthorId, c.ExpiresAt })
            .FirstOrDefaultAsync();
        if (access == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy bài truyền thông"));
        if (!CanAccessCommunication(access.Status, access.AuthorId, access.ExpiresAt))
            return StatusCode(403, AppResponse<object>.Fail("Bạn không có quyền tương tác với bài viết này"));
        return null;
    }

    private string? BuildPublicShareUrl(string? token)
    {
        if (string.IsNullOrWhiteSpace(token)) return null;
        var webBase = configuration["App:PublicWebBaseUrl"];
        if (string.IsNullOrWhiteSpace(webBase))
            webBase = $"{Request.Scheme}://{Request.Host}";
        return $"{webBase.TrimEnd('/')}/share/{token}";
    }

    private static bool ValidateImageMagicBytes(Stream stream, string extension)
    {
        if (stream.Length < 4) return false;
        var header = new byte[12];
        var pos = stream.Position;
        stream.Position = 0;
        var read = stream.Read(header, 0, header.Length);
        stream.Position = pos;
        if (read < 4) return false;

        return extension switch
        {
            ".jpg" or ".jpeg" => header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF,
            ".png" => header[0] == 0x89 && header[1] == 0x50 && header[2] == 0x4E && header[3] == 0x47,
            ".gif" => header[0] == 0x47 && header[1] == 0x49 && header[2] == 0x46,
            ".webp" => read >= 12 && header[0] == 0x52 && header[1] == 0x49 && header[2] == 0x46 && header[3] == 0x46
                       && header[8] == 0x57 && header[9] == 0x45 && header[10] == 0x42 && header[11] == 0x50,
            _ => true,
        };
    }


    private (string Title, string Content, string Summary, List<string> Tags) GenerateContentFromPrompt(
        string prompt, string typeLabel, string tone, string? context, int maxLength)
    {
        // AI content template generation based on prompt analysis
        var now = DateTime.Now;
        var dateStr = now.ToString("dd/MM/yyyy");

        // Parse prompt to extract key topics
        var promptLower = prompt.ToLower();
        
        string title;
        string content;
        string summary;
        var tags = new List<string>();

        if (promptLower.Contains("sá»± kiá»‡n") || promptLower.Contains("event"))
        {
            title = $"ðŸ“¢ {prompt}";
            summary = $"ThÃ´ng tin chi tiáº¿t vá» sá»± kiá»‡n {prompt} táº¡i cÃ´ng ty.";
            content = $@"<h2>ðŸŽ‰ {prompt}</h2>
<p><strong>KÃ­nh gá»­i toÃ n thá»ƒ nhÃ¢n viÃªn,</strong></p>
<p>Ban lÃ£nh Ä‘áº¡o cÃ´ng ty trÃ¢n trá»ng thÃ´ng bÃ¡o vá» sá»± kiá»‡n <strong>{prompt}</strong> sáº¯p Ä‘Æ°á»£c tá»• chá»©c.</p>
<h3>ðŸ“‹ Chi tiáº¿t sá»± kiá»‡n:</h3>
<ul>
<li><strong>Thá»i gian:</strong> [Cáº­p nháº­t thá»i gian cá»¥ thá»ƒ]</li>
<li><strong>Äá»‹a Ä‘iá»ƒm:</strong> [Cáº­p nháº­t Ä‘á»‹a Ä‘iá»ƒm]</li>
<li><strong>Äá»‘i tÆ°á»£ng tham gia:</strong> ToÃ n thá»ƒ nhÃ¢n viÃªn</li>
</ul>
{(context != null ? $"<p><em>Bá»‘i cáº£nh:</em> {context}</p>" : "")}
<h3>ðŸŽ¯ Má»¥c Ä‘Ã­ch:</h3>
<p>Sá»± kiá»‡n nháº±m táº¡o cÆ¡ há»™i giao lÆ°u, káº¿t ná»‘i giá»¯a cÃ¡c phÃ²ng ban vÃ  nÃ¢ng cao tinh tháº§n Ä‘oÃ n káº¿t trong táº­p thá»ƒ.</p>
<p><em>NgÃ y táº¡o: {dateStr}</em></p>
<p>TrÃ¢n trá»ng,<br/><strong>Ban Truyá»n thÃ´ng Ná»™i bá»™</strong></p>";
            tags.AddRange(new[] { "sá»± kiá»‡n", "team-building", typeLabel });
        }
        else if (promptLower.Contains("thÃ´ng bÃ¡o") || promptLower.Contains("announcement"))
        {
            title = $"ðŸ“‹ ThÃ´ng bÃ¡o: {prompt}";
            summary = $"ThÃ´ng bÃ¡o quan trá»ng vá» {prompt}.";
            content = $@"<h2>ðŸ“‹ THÃ”NG BÃO</h2>
<p><strong>KÃ­nh gá»­i toÃ n thá»ƒ CBNV,</strong></p>
<p>Ban lÃ£nh Ä‘áº¡o cÃ´ng ty xin thÃ´ng bÃ¡o vá» ná»™i dung: <strong>{prompt}</strong></p>
<h3>ðŸ“Œ Ná»™i dung chÃ­nh:</h3>
<p>{prompt}</p>
{(context != null ? $"<p><strong>Chi tiáº¿t bá»• sung:</strong> {context}</p>" : "")}
<h3>â° Thá»i gian Ã¡p dá»¥ng:</h3>
<p>CÃ³ hiá»‡u lá»±c tá»« ngÃ y {dateStr}</p>
<p>Má»i tháº¯c máº¯c vui lÃ²ng liÃªn há»‡ PhÃ²ng NhÃ¢n sá»± hoáº·c quáº£n lÃ½ trá»±c tiáº¿p.</p>
<p>TrÃ¢n trá»ng,<br/><strong>Ban GiÃ¡m Ä‘á»‘c</strong></p>";
            tags.AddRange(new[] { "thÃ´ng bÃ¡o", "quan trá»ng", typeLabel });
        }
        else if (promptLower.Contains("chÃ­nh sÃ¡ch") || promptLower.Contains("policy"))
        {
            title = $"ðŸ“œ ChÃ­nh sÃ¡ch: {prompt}";
            summary = $"Cáº­p nháº­t chÃ­nh sÃ¡ch má»›i vá» {prompt}.";
            content = $@"<h2>ðŸ“œ Cáº¬P NHáº¬T CHÃNH SÃCH</h2>
<p><strong>KÃ­nh gá»­i toÃ n thá»ƒ CBNV,</strong></p>
<p>Nháº±m hoÃ n thiá»‡n há»‡ thá»‘ng quáº£n lÃ½ vÃ  nÃ¢ng cao hiá»‡u quáº£ lÃ m viá»‡c, cÃ´ng ty ban hÃ nh chÃ­nh sÃ¡ch má»›i vá»: <strong>{prompt}</strong></p>
<h3>ðŸ“‹ Ná»™i dung chÃ­nh sÃ¡ch:</h3>
<ol>
<li>Pháº¡m vi Ã¡p dá»¥ng: ToÃ n thá»ƒ CBNV</li>
<li>Ná»™i dung: {prompt}</li>
<li>Thá»i gian Ã¡p dá»¥ng: Tá»« ngÃ y {dateStr}</li>
</ol>
{(context != null ? $"<h3>ðŸ’¡ LÆ°u Ã½:</h3><p>{context}</p>" : "")}
<p>Äá» nghá»‹ cÃ¡c phÃ²ng ban phá»• biáº¿n Ä‘áº¿n tá»«ng nhÃ¢n viÃªn Ä‘á»ƒ Ä‘áº£m báº£o thá»±c hiá»‡n Ä‘Ãºng quy Ä‘á»‹nh.</p>
<p>TrÃ¢n trá»ng,<br/><strong>PhÃ²ng NhÃ¢n sá»±</strong></p>";
            tags.AddRange(new[] { "chÃ­nh sÃ¡ch", "quy Ä‘á»‹nh", typeLabel });
        }
        else if (promptLower.Contains("tuyá»ƒn dá»¥ng") || promptLower.Contains("recruit"))
        {
            title = $"ðŸ” Tuyá»ƒn dá»¥ng: {prompt}";
            summary = $"ThÃ´ng tin tuyá»ƒn dá»¥ng {prompt}.";
            content = $@"<h2>ðŸ” THÃ”NG BÃO TUYá»‚N Dá»¤NG</h2>
<p><strong>CÃ´ng ty Ä‘ang tÃ¬m kiáº¿m á»©ng viÃªn cho vá»‹ trÃ­:</strong></p>
<h3>ðŸ’¼ {prompt}</h3>
<h3>ðŸ“‹ YÃªu cáº§u:</h3>
<ul>
<li>Kinh nghiá»‡m: [Cáº­p nháº­t yÃªu cáº§u]</li>
<li>TrÃ¬nh Ä‘á»™: [Cáº­p nháº­t trÃ¬nh Ä‘á»™]</li>
<li>Ká»¹ nÄƒng: [Cáº­p nháº­t ká»¹ nÄƒng]</li>
</ul>
<h3>ðŸŽ Quyá»n lá»£i:</h3>
<ul>
<li>Má»©c lÆ°Æ¡ng cáº¡nh tranh</li>
<li>MÃ´i trÆ°á»ng lÃ m viá»‡c chuyÃªn nghiá»‡p</li>
<li>CÆ¡ há»™i phÃ¡t triá»ƒn nghá» nghiá»‡p</li>
</ul>
{(context != null ? $"<p><strong>ThÃ´ng tin thÃªm:</strong> {context}</p>" : "")}
<p>á»¨ng viÃªn quan tÃ¢m vui lÃ²ng gá»­i CV vá» PhÃ²ng NhÃ¢n sá»± hoáº·c giá»›i thiá»‡u á»©ng viÃªn phÃ¹ há»£p.</p>
<p><em>Háº¡n ná»™p há»“ sÆ¡: [Cáº­p nháº­t deadline]</em></p>";
            tags.AddRange(new[] { "tuyá»ƒn dá»¥ng", "viá»‡c lÃ m", typeLabel });
        }
        else
        {
            title = $"ðŸ“° {prompt}";
            summary = $"BÃ i viáº¿t truyá»n thÃ´ng ná»™i bá»™ vá» {prompt}.";
            content = $@"<h2>ðŸ“° {prompt}</h2>
<p><strong>KÃ­nh gá»­i toÃ n thá»ƒ CBNV,</strong></p>
<p>{prompt}</p>
{(context != null ? $"<p>{context}</p>" : "")}
<h3>ðŸ“‹ Chi tiáº¿t:</h3>
<p>Ná»™i dung bÃ i viáº¿t vá» chá»§ Ä‘á» trÃªn sáº½ Ä‘Æ°á»£c cáº­p nháº­t chi tiáº¿t táº¡i Ä‘Ã¢y. BÃ i viáº¿t nháº±m má»¥c Ä‘Ã­ch chia sáº» thÃ´ng tin, káº¿t ná»‘i vÃ  xÃ¢y dá»±ng vÄƒn hÃ³a doanh nghiá»‡p.</p>
<h3>ðŸ’¡ Káº¿t luáº­n:</h3>
<p>Cáº£m Æ¡n sá»± quan tÃ¢m vÃ  Ä‘á»“ng hÃ nh cá»§a toÃ n thá»ƒ CBNV. Má»i gÃ³p Ã½ xin gá»­i vá» PhÃ²ng Truyá»n thÃ´ng.</p>
<p><em>NgÃ y Ä‘Äƒng: {dateStr}</em></p>
<p>TrÃ¢n trá»ng,<br/><strong>Ban Truyá»n thÃ´ng Ná»™i bá»™</strong></p>";
            tags.AddRange(new[] { "truyá»n thÃ´ng", "ná»™i bá»™", typeLabel });
        }

        return (title, content, summary, tags);
    }

    #endregion

    #region AI Config (Multi-provider)

    /// <summary>
    /// Láº¥y danh sÃ¡ch táº¥t cáº£ AI providers vá»›i tráº¡ng thÃ¡i
    /// </summary>
    [HttpGet("ai/providers")]
    [Authorize]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<IActionResult> GetAiProviders()
    {
        try
        {
            var storeId = RequiredStoreId;
            var allKeys = new[] { "gemini_api_key", "gemini_enabled", "deepseek_api_key", "deepseek_enabled" };
            var settings = await dbContext.AppSettings
                .Where(s => s.StoreId == storeId && allKeys.Contains(s.Key))
                .ToDictionaryAsync(s => s.Key, s => s.Value);

            var geminiConfig = geminiAiService.GetCurrentConfig();

            var providers = new[]
            {
                new
                {
                    id = "gemini",
                    name = "Google Gemini",
                    icon = "auto_awesome",
                    enabled = geminiConfig.Enabled,
                    isConfigured = geminiConfig.IsConfigured,
                    model = geminiConfig.Model
                }
            };

            var anyEnabled = providers.Any(p => p.enabled && p.isConfigured);

            return Ok(AppResponse<object>.Success(new { providers, anyEnabled }));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error getting AI providers");
            return StatusCode(500, AppResponse<object>.Fail("Lá»—i khi láº¥y danh sÃ¡ch AI"));
        }
    }

    /// <summary>
    /// Láº¥y cáº¥u hÃ¬nh Gemini AI hiá»‡n táº¡i
    /// </summary>
    [HttpGet("ai/config")]
    [Authorize]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<IActionResult> GetGeminiConfig()
    {
        try
        {
            // Äá»c config tá»« DB trÆ°á»›c (batch load), náº¿u khÃ´ng cÃ³ thÃ¬ láº¥y tá»« service
            var storeId = RequiredStoreId;
            var geminiKeys = new[] { "gemini_api_key", "gemini_model", "gemini_max_tokens", "gemini_temperature", "gemini_enabled" };
            var geminiSettings = await dbContext.AppSettings
                .Where(s => s.StoreId == storeId && geminiKeys.Contains(s.Key))
                .ToDictionaryAsync(s => s.Key, s => s.Value);

            var dbConfig = await GeminiStoreConfigLoader.LoadFromDbAsync(dbContext, storeId);
            var runtime = geminiAiService.GetCurrentConfig();

            var apiKeyRaw = geminiSettings.GetValueOrDefault("gemini_api_key")
                ?? dbConfig?.ApiKey
                ?? runtime.ApiKey;
            var enabledRaw = geminiSettings.GetValueOrDefault("gemini_enabled");
            var enabled = dbConfig?.Enabled
                ?? (bool.TryParse(enabledRaw, out var e) ? e : runtime.Enabled);

            var config = new
            {
                apiKey = MaskApiKey(apiKeyRaw),
                model = geminiSettings.GetValueOrDefault("gemini_model") ?? dbConfig?.Model ?? runtime.Model,
                maxOutputTokens = int.TryParse(geminiSettings.GetValueOrDefault("gemini_max_tokens"), out var t)
                    ? t
                    : dbConfig?.MaxOutputTokens ?? runtime.MaxOutputTokens,
                temperature = double.TryParse(
                    geminiSettings.GetValueOrDefault("gemini_temperature"),
                    System.Globalization.NumberStyles.Any,
                    System.Globalization.CultureInfo.InvariantCulture,
                    out var temp)
                    ? temp
                    : dbConfig?.Temperature ?? runtime.Temperature,
                isConfigured = !string.IsNullOrWhiteSpace(apiKeyRaw),
                enabled
            };

            return Ok(AppResponse<object>.Success(config));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error getting Gemini config");
            return StatusCode(500, AppResponse<object>.Fail("Lá»—i khi láº¥y cáº¥u hÃ¬nh AI"));
        }
    }

    /// <summary>
    /// Cáº­p nháº­t cáº¥u hÃ¬nh Gemini AI
    /// </summary>
    [HttpPost("ai/config")]
    [Authorize]
    [RequireModulePermission("Communication", ModulePermissionAction.Edit)]
    public async Task<IActionResult> UpdateGeminiConfig([FromBody] UpdateGeminiConfigDto dto)
    {
        try
        {
            // LÆ°u vÃ o DB - pre-load existing settings to avoid N+1
            var storeId = RequiredStoreId;
            var settings = new Dictionary<string, string?>
            {
                { "gemini_api_key", dto.ApiKey },
                { "gemini_model", dto.Model },
                { "gemini_max_tokens", dto.MaxOutputTokens?.ToString() },
                { "gemini_temperature", dto.Temperature?.ToString(System.Globalization.CultureInfo.InvariantCulture) },
                { "gemini_enabled", dto.Enabled?.ToString() }
            };

            var settingKeys = settings.Keys.ToList();
            var existingSettingsMap = await dbContext.AppSettings
                .AsTracking()
                .Where(s => s.StoreId == storeId && settingKeys.Contains(s.Key))
                .ToDictionaryAsync(s => s.Key);

            foreach (var (key, value) in settings)
            {
                if (value == null) continue;

                if (existingSettingsMap.TryGetValue(key, out var existing))
                {
                    existing.Value = value;
                    existing.LastModified = DateTime.UtcNow;
                    existing.LastModifiedBy = CurrentUserId.ToString();
                }
                else
                {
                    dbContext.AppSettings.Add(new AppSettings
                    {
                        Id = Guid.NewGuid(),
                        Key = key,
                        Value = value,
                        Description = key switch
                        {
                            "gemini_api_key" => "Google Gemini API Key",
                            "gemini_model" => "Gemini Model Name",
                            "gemini_max_tokens" => "Max Output Tokens",
                            "gemini_temperature" => "Temperature",
                            "gemini_enabled" => "Gemini Enabled",
                            _ => key
                        },
                        Group = "AI",
                        DataType = "text",
                        IsPublic = false,
                        StoreId = storeId,
                        CreatedAt = DateTime.UtcNow,
                        CreatedBy = CurrentUserId.ToString()
                    });
                }
            }

            await dbContext.SaveChangesAsync();

            var reloaded = await GeminiStoreConfigLoader.LoadFromDbAsync(dbContext, storeId);
            if (reloaded != null)
                GeminiStoreConfigLoader.Apply(geminiAiService, reloaded);
            else
            {
                geminiAiService.UpdateConfig(
                    dto.ApiKey,
                    dto.Model,
                    dto.MaxOutputTokens,
                    dto.Temperature,
                    dto.Enabled);
            }

            logger.LogInformation(
                "User {UserId} updated Gemini AI config for store {StoreId}",
                CurrentUserId,
                storeId);

            return Ok(AppResponse<object>.Success(new
            {
                isConfigured = geminiAiService.IsConfigured,
                enabled = geminiAiService.IsEnabled,
                message = "Cập nhật cấu hình AI thành công"
            }));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error updating Gemini config");
            return StatusCode(500, AppResponse<object>.Fail($"Lá»—i khi cáº­p nháº­t cáº¥u hÃ¬nh AI: {ex.Message}"));
        }
    }

    /// <summary>
    /// Kiá»ƒm tra káº¿t ná»‘i Gemini AI
    /// </summary>
    [HttpPost("ai/test")]
    [Authorize]
    [RequireModulePermission("Communication", ModulePermissionAction.Create)]
    public async Task<IActionResult> TestGeminiConnection()
    {
        try
        {
            if (!geminiAiService.IsConfigured || !geminiAiService.IsEnabled)
            {
                return Ok(AppResponse<object>.Fail("Gemini AI chÆ°a Ä‘Æ°á»£c báº­t hoáº·c chÆ°a cáº¥u hÃ¬nh API Key"));
            }

            var result = await geminiAiService.GenerateCommunicationContentAsync(
                "Viáº¿t má»™t cÃ¢u chÃ o ngáº¯n gá»n", "tin tá»©c", "thÃ¢n thiá»‡n", null, 200);

            return Ok(AppResponse<object>.Success(new
            {
                success = true,
                message = "Káº¿t ná»‘i Gemini AI thÃ nh cÃ´ng!",
                sampleTitle = result.Title,
                sampleContent = result.Content.Length > 200 ? result.Content[..200] + "..." : result.Content
            }));
        }
        catch (AiApiException ex) when (ex.IsQuotaError)
        {
            logger.LogWarning("Gemini AI test - quota exceeded");
            return Ok(AppResponse<object>.Success(new
            {
                success = true,
                isQuotaError = true,
                message = "âœ… API Key há»£p lá»‡! Tuy nhiÃªn quota miá»…n phÃ­ Ä‘Ã£ táº¡m háº¿t.",
                detail = ex.Message
            }));
        }
        catch (AiApiException ex) when (ex.IsAuthError)
        {
            logger.LogWarning("Gemini AI test - auth error");
            return Ok(AppResponse<object>.Fail($"âŒ API Key khÃ´ng há»£p lá»‡: {ex.Message}"));
        }
        catch (AiApiException ex)
        {
            logger.LogError(ex, "Gemini AI test failed with API error");
            return Ok(AppResponse<object>.Fail($"Lá»—i API: {ex.Message}"));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Gemini AI test failed");
            return Ok(AppResponse<object>.Fail($"Káº¿t ná»‘i tháº¥t báº¡i: {ex.Message}"));
        }
    }

    /// <summary>
    /// Láº¥y cáº¥u hÃ¬nh DeepSeek AI hiá»‡n táº¡i
    /// </summary>
    [HttpGet("ai/deepseek/config")]
    [Authorize]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<IActionResult> GetDeepSeekConfig()
    {
        try
        {
            var storeId = RequiredStoreId;
            var deepseekKeys = new[] { "deepseek_api_key", "deepseek_model", "deepseek_max_tokens", "deepseek_temperature", "deepseek_enabled" };
            var deepseekSettings = await dbContext.AppSettings
                .Where(s => s.StoreId == storeId && deepseekKeys.Contains(s.Key))
                .ToDictionaryAsync(s => s.Key, s => s.Value);

            var currentConfig = deepSeekAiService.GetCurrentConfig();

            var config = new
            {
                apiKey = MaskApiKey(deepseekSettings.GetValueOrDefault("deepseek_api_key") ?? currentConfig.ApiKey),
                model = deepseekSettings.GetValueOrDefault("deepseek_model") ?? currentConfig.Model,
                maxOutputTokens = int.TryParse(deepseekSettings.GetValueOrDefault("deepseek_max_tokens"), out var t) ? t : currentConfig.MaxOutputTokens,
                temperature = double.TryParse(deepseekSettings.GetValueOrDefault("deepseek_temperature"), System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out var temp) ? temp : currentConfig.Temperature,
                isConfigured = deepSeekAiService.IsConfigured,
                enabled = currentConfig.Enabled
            };

            return Ok(AppResponse<object>.Success(config));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error getting DeepSeek config");
            return StatusCode(500, AppResponse<object>.Fail("Lá»—i khi láº¥y cáº¥u hÃ¬nh DeepSeek"));
        }
    }

    /// <summary>
    /// Cáº­p nháº­t cáº¥u hÃ¬nh DeepSeek AI
    /// </summary>
    [HttpPost("ai/deepseek/config")]
    [Authorize]
    [RequireModulePermission("Communication", ModulePermissionAction.Edit)]
    public async Task<IActionResult> UpdateDeepSeekConfig([FromBody] UpdateDeepSeekConfigDto dto)
    {
        try
        {
            var storeId = RequiredStoreId;
            var settings = new Dictionary<string, string?>
            {
                { "deepseek_api_key", dto.ApiKey },
                { "deepseek_model", dto.Model },
                { "deepseek_max_tokens", dto.MaxOutputTokens?.ToString() },
                { "deepseek_temperature", dto.Temperature?.ToString(System.Globalization.CultureInfo.InvariantCulture) },
                { "deepseek_enabled", dto.Enabled?.ToString() }
            };

            var settingKeys = settings.Keys.ToList();
            var existingSettingsMap = await dbContext.AppSettings
                .AsTracking()
                .Where(s => s.StoreId == storeId && settingKeys.Contains(s.Key))
                .ToDictionaryAsync(s => s.Key);

            foreach (var (key, value) in settings)
            {
                if (value == null) continue;

                if (existingSettingsMap.TryGetValue(key, out var existing))
                {
                    existing.Value = value;
                    existing.LastModified = DateTime.UtcNow;
                    existing.LastModifiedBy = CurrentUserId.ToString();
                }
                else
                {
                    dbContext.AppSettings.Add(new AppSettings
                    {
                        Id = Guid.NewGuid(),
                        Key = key,
                        Value = value,
                        Description = key switch
                        {
                            "deepseek_api_key" => "DeepSeek API Key",
                            "deepseek_model" => "DeepSeek Model Name",
                            "deepseek_max_tokens" => "Max Output Tokens",
                            "deepseek_temperature" => "Temperature",
                            "deepseek_enabled" => "DeepSeek Enabled",
                            _ => key
                        },
                        Group = "AI",
                        DataType = "text",
                        IsPublic = false,
                        StoreId = storeId,
                        CreatedAt = DateTime.UtcNow,
                        CreatedBy = CurrentUserId.ToString()
                    });
                }
            }

            await dbContext.SaveChangesAsync();

            deepSeekAiService.UpdateConfig(
                dto.ApiKey,
                dto.Model,
                dto.MaxOutputTokens,
                dto.Temperature,
                dto.Enabled
            );

            logger.LogInformation("User {UserId} updated DeepSeek AI config", CurrentUserId);

            return Ok(AppResponse<object>.Success(new
            {
                isConfigured = deepSeekAiService.IsConfigured,
                message = "Cáº­p nháº­t cáº¥u hÃ¬nh DeepSeek thÃ nh cÃ´ng"
            }));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error updating DeepSeek config");
            return StatusCode(500, AppResponse<object>.Fail($"Lá»—i khi cáº­p nháº­t cáº¥u hÃ¬nh DeepSeek: {ex.Message}"));
        }
    }

    /// <summary>
    /// Kiá»ƒm tra káº¿t ná»‘i DeepSeek AI
    /// </summary>
    [HttpPost("ai/deepseek/test")]
    [Authorize]
    [RequireModulePermission("Communication", ModulePermissionAction.Edit)]
    public async Task<IActionResult> TestDeepSeekConnection()
    {
        try
        {
            if (!deepSeekAiService.IsConfigured || !deepSeekAiService.IsEnabled)
            {
                return Ok(AppResponse<object>.Fail("DeepSeek AI chÆ°a Ä‘Æ°á»£c báº­t hoáº·c chÆ°a cáº¥u hÃ¬nh API Key"));
            }

            var result = await deepSeekAiService.GenerateCommunicationContentAsync(
                "Viáº¿t má»™t cÃ¢u chÃ o ngáº¯n gá»n", "tin tá»©c", "thÃ¢n thiá»‡n", null, 200);

            return Ok(AppResponse<object>.Success(new
            {
                success = true,
                message = "Káº¿t ná»‘i DeepSeek AI thÃ nh cÃ´ng!",
                sampleTitle = result.Title,
                sampleContent = result.Content.Length > 200 ? result.Content[..200] + "..." : result.Content
            }));
        }
        catch (AiApiException ex) when (ex.IsQuotaError)
        {
            logger.LogWarning("DeepSeek AI test - quota exceeded");
            return Ok(AppResponse<object>.Success(new
            {
                success = true,
                isQuotaError = true,
                message = "âœ… API Key há»£p lá»‡! Tuy nhiÃªn quota Ä‘Ã£ táº¡m háº¿t.",
                detail = ex.Message
            }));
        }
        catch (AiApiException ex) when (ex.IsAuthError)
        {
            logger.LogWarning("DeepSeek AI test - auth error");
            return Ok(AppResponse<object>.Fail($"âŒ API Key khÃ´ng há»£p lá»‡: {ex.Message}"));
        }
        catch (AiApiException ex)
        {
            logger.LogError(ex, "DeepSeek AI test failed with API error");
            return Ok(AppResponse<object>.Fail($"Lá»—i API: {ex.Message}"));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "DeepSeek AI test failed");
            return Ok(AppResponse<object>.Fail($"Káº¿t ná»‘i tháº¥t báº¡i: {ex.Message}"));
        }
    }

    #endregion

    private static string MaskApiKey(string apiKey)
    {
        if (string.IsNullOrWhiteSpace(apiKey) || apiKey.Length < 8) return string.Empty;
        return apiKey[..4] + new string('*', apiKey.Length - 8) + apiKey[^4..];
    }

    private async Task<string> GetStoreFolderAsync(string subfolder)
    {
        var storeId = CurrentStoreId;
        if (storeId.HasValue)
        {
            var storeCode = await dbContext.Stores
                .Where(s => s.Id == storeId.Value)
                .Select(s => s.Code)
                .FirstOrDefaultAsync();
            if (!string.IsNullOrEmpty(storeCode))
            {
                return $"stores/{storeCode}/{subfolder}";
            }
        }
        return subfolder;
    }
}

