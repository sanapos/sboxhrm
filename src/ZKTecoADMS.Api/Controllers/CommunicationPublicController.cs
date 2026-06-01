using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.Communications;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Xem bài truyền thông qua link chia sẻ — không cần đăng nhập.
/// </summary>
[ApiController]
[Route("api/communications/public")]
[AllowAnonymous]
public class CommunicationPublicController(
    ZKTecoDbContext dbContext,
    ILogger<CommunicationPublicController> logger
) : ControllerBase
{
    [HttpGet("{token}")]
    [ProducesResponseType(typeof(AppResponse<PublicCommunicationViewDto>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetByShareToken(string token, [FromQuery] bool countView = true)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(token) || token.Length > 64)
                return NotFound(AppResponse<object>.Fail("Không tìm thấy bài viết"));

            var now = DateTime.UtcNow;
            var entity = await dbContext.InternalCommunications
                .AsNoTracking()
                .Where(c =>
                    c.IsPublicShareEnabled
                    && c.PublicShareToken == token
                    && c.Status == CommunicationStatus.Published
                    && (c.ExpiresAt == null || c.ExpiresAt > now))
                .Select(c => new
                {
                    c.Id,
                    c.Title,
                    c.Content,
                    c.Summary,
                    c.ThumbnailUrl,
                    c.AttachedImages,
                    c.Type,
                    c.AuthorName,
                    StoreName = c.Store != null ? c.Store.Name : null,
                    c.PublishedAt,
                    c.ExpiresAt,
                    c.ViewCount,
                    c.Tags
                })
                .FirstOrDefaultAsync();

            if (entity == null)
                return NotFound(AppResponse<object>.Fail("Link không hợp lệ hoặc bài đã hết hạn"));

            if (countView)
            {
                await dbContext.InternalCommunications
                    .Where(c => c.Id == entity.Id)
                    .ExecuteUpdateAsync(s => s.SetProperty(c => c.ViewCount, c => c.ViewCount + 1));
            }

            var dto = new PublicCommunicationViewDto
            {
                Title = entity.Title,
                Content = entity.Content,
                Summary = entity.Summary,
                ThumbnailUrl = entity.ThumbnailUrl,
                AttachedImages = string.IsNullOrEmpty(entity.AttachedImages)
                    ? new List<string>()
                    : JsonSerializer.Deserialize<List<string>>(entity.AttachedImages) ?? new List<string>(),
                Type = entity.Type,
                TypeName = entity.Type.ToString(),
                AuthorName = entity.AuthorName,
                StoreName = entity.StoreName,
                PublishedAt = entity.PublishedAt,
                ExpiresAt = entity.ExpiresAt,
                ViewCount = countView ? entity.ViewCount + 1 : entity.ViewCount,
                Tags = entity.Tags
            };

            return Ok(AppResponse<PublicCommunicationViewDto>.Success(dto));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error loading public communication share {Token}", token);
            return StatusCode(500, AppResponse<object>.Fail("Lỗi khi tải bài viết"));
        }
    }
}
