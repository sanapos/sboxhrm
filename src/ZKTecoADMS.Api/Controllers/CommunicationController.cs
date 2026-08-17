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
            return StatusCode(500, AppResponse<object>.Fail("Lỗi khi lấy danh sách bài truyền thông"));
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
            return StatusCode(500, AppResponse<object>.Fail("Lỗi khi lấy bài truyền thông"));
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
                                    "Bài truyền thông mới",
                                    $"Bài viết \"{dto.Title}\" đã được đăng",
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
            return StatusCode(500, AppResponse<Guid>.Fail("Lỗi khi tạo bài truyền thông"));
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
                                "Bài truyền thông mới",
                                $"Bài viết \"{dto.Title}\" đã được đăng",
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
            return StatusCode(500, AppResponse<bool>.Fail("Lỗi khi cập nhật bài truyền thông"));
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
            return StatusCode(500, AppResponse<bool>.Fail("Lỗi khi xóa bài truyền thông"));
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

            // Use ExecuteUpdateAsync for direct SQL UPDATE – bypasses all EF change tracking
            var affected = await dbContext.InternalCommunications
                .Where(c => c.Id == id)
                .ExecuteUpdateAsync(s => s
                    .SetProperty(c => c.Status, CommunicationStatus.Published)
                    .SetProperty(c => c.PublishedAt, publishedAt)
                    .SetProperty(c => c.UpdatedAt, now));

            logger.LogInformation("PublishCommunication: id={Id} affected={Affected}", id, affected);

            if (affected == 0)
                return StatusCode(500, AppResponse<bool>.Fail("Không thể cập nhật trạng thái bài viết"));

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
                            "Bài truyền thông mới",
                            $"Bài viết \"{entity.Title}\" đã được đăng",
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
            return StatusCode(500, AppResponse<bool>.Fail("Lỗi khi xuất bản bài truyền thông"));
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
            return StatusCode(500, AppResponse<object>.Fail("Lỗi khi lấy bình luận"));
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
                                var commenterName = User.FindFirst(System.Security.Claims.ClaimTypes.Name)?.Value ?? "Ai đó";
                                await notificationService.CreateAndSendAsync(
                                    authorUserId, NotificationType.Info,
                                    "Bình luận mới",
                                    $"{commenterName} đã bình luận bài viết \"{comm.Title}\"",
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
            return StatusCode(500, AppResponse<Guid>.Fail("Lỗi khi thêm bình luận"));
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
            return StatusCode(500, AppResponse<bool>.Fail("Lỗi khi cập nhật reaction"));
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
                CommunicationType.News => "tin tức nội bộ",
                CommunicationType.Announcement => "thông báo",
                CommunicationType.Event => "sự kiện",
                CommunicationType.Policy => "chính sách",
                CommunicationType.Training => "đào tạo",
                CommunicationType.Culture => "văn hóa công ty",
                CommunicationType.Recruitment => "tuyển dụng",
                CommunicationType.Regulation => "nội quy công ty",
                _ => "bài viết"
            };

            var toneLabel = dto.Tone?.ToLower() switch
            {
                "formal" => "trang trọng, chuyên nghiệp",
                "friendly" => "thân thiện, gần gũi",
                "creative" => "sáng tạo, hấp dẫn",
                "inspirational" => "truyền cảm hứng, động lực",
                _ => "chuyên nghiệp"
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
            await WriteSseEvent("error", $"Lỗi khi tạo nội dung AI: {ex.Message}");
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
                CommunicationType.News => "tin tức nội bộ",
                CommunicationType.Announcement => "thông báo",
                CommunicationType.Event => "sự kiện",
                CommunicationType.Policy => "chính sách",
                CommunicationType.Training => "đào tạo",
                CommunicationType.Culture => "văn hóa công ty",
                CommunicationType.Recruitment => "tuyển dụng",
                CommunicationType.Regulation => "nội quy công ty",
                _ => "bài viết"
            };

            var toneLabel = dto.Tone?.ToLower() switch
            {
                "formal" => "trang trọng, chuyên nghiệp",
                "friendly" => "thân thiện, gần gũi",
                "creative" => "sáng tạo, hấp dẫn",
                "inspirational" => "truyền cảm hứng, động lực",
                _ => "chuyên nghiệp"
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
            return StatusCode(500, AppResponse<AiGeneratedContentDto>.Fail($"Lỗi khi tạo nội dung AI: {ex.Message}"));
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
                return BadRequest(AppResponse<string>.Fail("Vui lòng chọn file ảnh"));
            }

            var allowedTypes = new[] { "image/jpeg", "image/png", "image/gif", "image/webp" };
            if (!allowedTypes.Contains(file.ContentType.ToLower()))
            {
                return BadRequest(AppResponse<string>.Fail("Chỉ hỗ trợ định dạng JPEG, PNG, GIF, WebP"));
            }

            using var stream = file.OpenReadStream();

            // Validate magic bytes
            var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
            if (!ValidateImageMagicBytes(stream, ext))
            {
                return BadRequest(AppResponse<string>.Fail("Nội dung file không khớp với định dạng khai báo"));
            }
            stream.Position = 0;

            var (optimized, uploadName, _) = await ImageOptimizeHelper.OptimizeAsync(
                stream,
                file.FileName,
                ImageOptimizeHelper.PhotoMaxEdge,
                ImageOptimizeHelper.PhotoJpegQuality);
            await using (optimized)
            {
                var uploadFolder = await GetStoreFolderAsync("uploads/communications");
                var storedPath = await fileStorageService.UploadAsync(optimized, uploadName, uploadFolder);
                var imageUrl = fileStorageService.GetFileUrl(storedPath);
                return Ok(AppResponse<string>.Success(imageUrl));
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error uploading image");
            return StatusCode(500, AppResponse<string>.Fail("Lỗi khi upload ảnh"));
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
                return BadRequest(AppResponse<string>.Fail("Vui lòng chọn file ảnh"));
            }

            var extension = Path.GetExtension(dto.FileName).ToLower();
            var allowedExtensions = new[] { ".jpg", ".jpeg", ".png", ".gif", ".webp" };
            if (!allowedExtensions.Contains(extension))
            {
                return BadRequest(AppResponse<string>.Fail("Chỉ hỗ trợ định dạng JPEG, PNG, GIF, WebP"));
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
                return BadRequest(AppResponse<string>.Fail("Kích thước ảnh tối đa 10MB"));
            }

            byte[] fileBytes;
            try
            {
                fileBytes = Convert.FromBase64String(base64);
            }
            catch
            {
                return BadRequest(AppResponse<string>.Fail("Dữ liệu ảnh không hợp lệ"));
            }

            if (fileBytes.Length > 10 * 1024 * 1024)
            {
                return BadRequest(AppResponse<string>.Fail("Kích thước ảnh tối đa 10MB"));
            }

            // Validate magic bytes
            using var checkStream = new MemoryStream(fileBytes);
            if (!ValidateImageMagicBytes(checkStream, extension))
            {
                return BadRequest(AppResponse<string>.Fail("Nội dung file không khớp với định dạng khai báo"));
            }

            var (optimized, uploadName, _) = ImageOptimizeHelper.Optimize(
                fileBytes,
                dto.FileName,
                ImageOptimizeHelper.PhotoMaxEdge,
                ImageOptimizeHelper.PhotoJpegQuality);
            await using (optimized)
            {
                var uploadFolder = await GetStoreFolderAsync("uploads/communications");
                var storedPath = await fileStorageService.UploadAsync(optimized, uploadName, uploadFolder);
                var imageUrl = fileStorageService.GetFileUrl(storedPath);
                return Ok(AppResponse<string>.Success(imageUrl));
            }
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error uploading base64 image");
            return StatusCode(500, AppResponse<string>.Fail("Lỗi khi upload ảnh"));
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
            return StatusCode(500, AppResponse<object>.Fail("Lỗi khi lấy thống kê"));
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

        if (promptLower.Contains("sự kiện") || promptLower.Contains("event"))
        {
            title = $"ðŸ“¢ {prompt}";
            summary = $"Thông tin chi tiết về sự kiện {prompt} tại công ty.";
            content = $@"<h2>ðŸŽ‰ {prompt}</h2>
<p><strong>Kính gửi toàn thể nhân viên,</strong></p>
<p>Ban lãnh đạo công ty trân trọng thông báo về sự kiện <strong>{prompt}</strong> sắp được tổ chức.</p>
<h3>ðŸ“‹ Chi tiết sự kiện:</h3>
<ul>
<li><strong>Thời gian:</strong> [Cập nhật thời gian cụ thể]</li>
<li><strong>Địa điểm:</strong> [Cập nhật địa điểm]</li>
<li><strong>Đối tượng tham gia:</strong> Toàn thể nhân viên</li>
</ul>
{(context != null ? $"<p><em>Bối cảnh:</em> {context}</p>" : "")}
<h3>ðŸŽ¯ Mục đích:</h3>
<p>Sự kiện nhằm tạo cơ hội giao lưu, kết nối giữa các phòng ban và nâng cao tinh thần đoàn kết trong tập thể.</p>
<p><em>Ngày tạo: {dateStr}</em></p>
<p>Trân trọng,<br/><strong>Ban Truyền thông Nội bộ</strong></p>";
            tags.AddRange(new[] { "sự kiện", "team-building", typeLabel });
        }
        else if (promptLower.Contains("thông báo") || promptLower.Contains("announcement"))
        {
            title = $"ðŸ“‹ Thông báo: {prompt}";
            summary = $"Thông báo quan trọng về {prompt}.";
            content = $@"<h2>ðŸ“‹ THÔNG BÁO</h2>
<p><strong>Kính gửi toàn thể CBNV,</strong></p>
<p>Ban lãnh đạo công ty xin thông báo về nội dung: <strong>{prompt}</strong></p>
<h3>ðŸ“Œ Nội dung chính:</h3>
<p>{prompt}</p>
{(context != null ? $"<p><strong>Chi tiết bổ sung:</strong> {context}</p>" : "")}
<h3>â° Thời gian áp dụng:</h3>
<p>Có hiệu lực từ ngày {dateStr}</p>
<p>Mọi thắc mắc vui lòng liên hệ Phòng Nhân sự hoặc quản lý trực tiếp.</p>
<p>Trân trọng,<br/><strong>Ban Giám đốc</strong></p>";
            tags.AddRange(new[] { "thông báo", "quan trọng", typeLabel });
        }
        else if (promptLower.Contains("chính sách") || promptLower.Contains("policy"))
        {
            title = $"ðŸ“œ Chính sách: {prompt}";
            summary = $"Cập nhật chính sách mới về {prompt}.";
            content = $@"<h2>ðŸ“œ CẬP NHẬT CHÍNH SÁCH</h2>
<p><strong>Kính gửi toàn thể CBNV,</strong></p>
<p>Nhằm hoàn thiện hệ thống quản lý và nâng cao hiệu quả làm việc, công ty ban hành chính sách mới về: <strong>{prompt}</strong></p>
<h3>ðŸ“‹ Nội dung chính sách:</h3>
<ol>
<li>Phạm vi áp dụng: Toàn thể CBNV</li>
<li>Nội dung: {prompt}</li>
<li>Thời gian áp dụng: Từ ngày {dateStr}</li>
</ol>
{(context != null ? $"<h3>ðŸ’¡ Lưu ý:</h3><p>{context}</p>" : "")}
<p>Đề nghị các phòng ban phổ biến đến từng nhân viên để đảm bảo thực hiện đúng quy định.</p>
<p>Trân trọng,<br/><strong>Phòng Nhân sự</strong></p>";
            tags.AddRange(new[] { "chính sách", "quy định", typeLabel });
        }
        else if (promptLower.Contains("tuyển dụng") || promptLower.Contains("recruit"))
        {
            title = $"ðŸ” Tuyển dụng: {prompt}";
            summary = $"Thông tin tuyển dụng {prompt}.";
            content = $@"<h2>ðŸ” THÔNG BÁO TUYỂN DỤNG</h2>
<p><strong>Công ty đang tìm kiếm ứng viên cho vị trí:</strong></p>
<h3>ðŸ’¼ {prompt}</h3>
<h3>ðŸ“‹ Yêu cầu:</h3>
<ul>
<li>Kinh nghiệm: [Cập nhật yêu cầu]</li>
<li>Trình độ: [Cập nhật trình độ]</li>
<li>Kỹ năng: [Cập nhật kỹ năng]</li>
</ul>
<h3>ðŸŽ Quyền lợi:</h3>
<ul>
<li>Mức lương cạnh tranh</li>
<li>Môi trường làm việc chuyên nghiệp</li>
<li>Cơ hội phát triển nghề nghiệp</li>
</ul>
{(context != null ? $"<p><strong>Thông tin thêm:</strong> {context}</p>" : "")}
<p>Ứng viên quan tâm vui lòng gửi CV về Phòng Nhân sự hoặc giới thiệu ứng viên phù hợp.</p>
<p><em>Hạn nộp hồ sơ: [Cập nhật deadline]</em></p>";
            tags.AddRange(new[] { "tuyển dụng", "việc làm", typeLabel });
        }
        else
        {
            title = $"ðŸ“° {prompt}";
            summary = $"Bài viết truyền thông nội bộ về {prompt}.";
            content = $@"<h2>ðŸ“° {prompt}</h2>
<p><strong>Kính gửi toàn thể CBNV,</strong></p>
<p>{prompt}</p>
{(context != null ? $"<p>{context}</p>" : "")}
<h3>ðŸ“‹ Chi tiết:</h3>
<p>Nội dung bài viết về chủ đề trên sẽ được cập nhật chi tiết tại đây. Bài viết nhằm mục đích chia sẻ thông tin, kết nối và xây dựng văn hóa doanh nghiệp.</p>
<h3>ðŸ’¡ Kết luận:</h3>
<p>Cảm ơn sự quan tâm và đồng hành của toàn thể CBNV. Mọi góp ý xin gửi về Phòng Truyền thông.</p>
<p><em>Ngày đăng: {dateStr}</em></p>
<p>Trân trọng,<br/><strong>Ban Truyền thông Nội bộ</strong></p>";
            tags.AddRange(new[] { "truyền thông", "nội bộ", typeLabel });
        }

        return (title, content, summary, tags);
    }

    #endregion

    #region AI Config (Multi-provider)

    /// <summary>
    /// Lấy danh sách tất cả AI providers với trạng thái
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
            return StatusCode(500, AppResponse<object>.Fail("Lỗi khi lấy danh sách AI"));
        }
    }

    /// <summary>
    /// Lấy cấu hình Gemini AI hiện tại
    /// </summary>
    [HttpGet("ai/config")]
    [Authorize]
    [RequireModulePermission("Communication", ModulePermissionAction.View)]
    public async Task<IActionResult> GetGeminiConfig()
    {
        try
        {
            // Đọc config từ DB trước (batch load), nếu không có thì lấy từ service
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
            return StatusCode(500, AppResponse<object>.Fail("Lỗi khi lấy cấu hình AI"));
        }
    }

    /// <summary>
    /// Cập nhật cấu hình Gemini AI
    /// </summary>
    [HttpPost("ai/config")]
    [Authorize]
    [RequireModulePermission("Communication", ModulePermissionAction.Edit)]
    public async Task<IActionResult> UpdateGeminiConfig([FromBody] UpdateGeminiConfigDto dto)
    {
        try
        {
            // Lưu vào DB - pre-load existing settings to avoid N+1
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
            return StatusCode(500, AppResponse<object>.Fail($"Lỗi khi cập nhật cấu hình AI: {ex.Message}"));
        }
    }

    /// <summary>
    /// Kiểm tra kết nối Gemini AI
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
                return Ok(AppResponse<object>.Fail("Gemini AI chưa được bật hoặc chưa cấu hình API Key"));
            }

            var result = await geminiAiService.GenerateCommunicationContentAsync(
                "Viết một câu chào ngắn gọn", "tin tức", "thân thiện", null, 200);

            return Ok(AppResponse<object>.Success(new
            {
                success = true,
                message = "Kết nối Gemini AI thành công!",
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
                message = "✅ API Key hợp lệ! Tuy nhiên quota miễn phí đã tạm hết.",
                detail = ex.Message
            }));
        }
        catch (AiApiException ex) when (ex.IsAuthError)
        {
            logger.LogWarning("Gemini AI test - auth error");
            return Ok(AppResponse<object>.Fail($"âŒ API Key không hợp lệ: {ex.Message}"));
        }
        catch (AiApiException ex)
        {
            logger.LogError(ex, "Gemini AI test failed with API error");
            return Ok(AppResponse<object>.Fail($"Lỗi API: {ex.Message}"));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Gemini AI test failed");
            return Ok(AppResponse<object>.Fail($"Kết nối thất bại: {ex.Message}"));
        }
    }

    /// <summary>
    /// Lấy cấu hình DeepSeek AI hiện tại
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
            return StatusCode(500, AppResponse<object>.Fail("Lỗi khi lấy cấu hình DeepSeek"));
        }
    }

    /// <summary>
    /// Cập nhật cấu hình DeepSeek AI
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
                message = "Cập nhật cấu hình DeepSeek thành công"
            }));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error updating DeepSeek config");
            return StatusCode(500, AppResponse<object>.Fail($"Lỗi khi cập nhật cấu hình DeepSeek: {ex.Message}"));
        }
    }

    /// <summary>
    /// Kiểm tra kết nối DeepSeek AI
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
                return Ok(AppResponse<object>.Fail("DeepSeek AI chưa được bật hoặc chưa cấu hình API Key"));
            }

            var result = await deepSeekAiService.GenerateCommunicationContentAsync(
                "Viết một câu chào ngắn gọn", "tin tức", "thân thiện", null, 200);

            return Ok(AppResponse<object>.Success(new
            {
                success = true,
                message = "Kết nối DeepSeek AI thành công!",
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
                message = "✅ API Key hợp lệ! Tuy nhiên quota đã tạm hết.",
                detail = ex.Message
            }));
        }
        catch (AiApiException ex) when (ex.IsAuthError)
        {
            logger.LogWarning("DeepSeek AI test - auth error");
            return Ok(AppResponse<object>.Fail($"âŒ API Key không hợp lệ: {ex.Message}"));
        }
        catch (AiApiException ex)
        {
            logger.LogError(ex, "DeepSeek AI test failed with API error");
            return Ok(AppResponse<object>.Fail($"Lỗi API: {ex.Message}"));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "DeepSeek AI test failed");
            return Ok(AppResponse<object>.Fail($"Kết nối thất bại: {ex.Message}"));
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

