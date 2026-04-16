using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Models.Responses;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/content-categories")]
public class ContentCategoriesController(
    ZKTecoDbContext dbContext,
    ILogger<ContentCategoriesController> logger
) : AuthenticatedControllerBase
{
    /// <summary>
    /// Lấy danh sách thư mục theo loại nội dung
    /// </summary>
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<IActionResult> GetCategories([FromQuery] CommunicationType? contentType)
    {
        try
        {
            var storeId = RequiredStoreId;
            var query = dbContext.ContentCategories
                .Where(c => c.StoreId == storeId && c.IsActive);

            if (contentType.HasValue)
                query = query.Where(c => c.ContentType == contentType.Value);

            var categories = await query
                .OrderBy(c => c.ContentType)
                .ThenBy(c => c.DisplayOrder)
                .ThenBy(c => c.Name)
                .Select(c => new
                {
                    c.Id,
                    c.Name,
                    c.Description,
                    c.ContentType,
                    ContentTypeName = c.ContentType.ToString(),
                    c.IconName,
                    c.Color,
                    c.DisplayOrder,
                    c.ParentCategoryId,
                    c.IsActive,
                    c.CreatedAt,
                    ArticleCount = dbContext.InternalCommunications
                        .Count(ic => ic.CategoryId == c.Id && ic.StoreId == storeId)
                })
                .ToListAsync();

            return Ok(AppResponse<object>.Success(categories));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error getting content categories");
            return StatusCode(500, AppResponse<object>.Fail("Lỗi khi lấy danh sách thư mục"));
        }
    }

    /// <summary>
    /// Tạo thư mục mới
    /// </summary>
    [HttpPost]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<IActionResult> CreateCategory([FromBody] CreateCategoryDto dto)
    {
        try
        {
            var category = new ContentCategory
            {
                Id = Guid.NewGuid(),
                StoreId = RequiredStoreId,
                Name = dto.Name,
                Description = dto.Description,
                ContentType = dto.ContentType,
                IconName = dto.IconName,
                Color = dto.Color,
                DisplayOrder = dto.DisplayOrder,
                ParentCategoryId = dto.ParentCategoryId,
                IsActive = true,
                CreatedAt = DateTime.UtcNow,
                CreatedBy = CurrentUserId.ToString()
            };

            dbContext.ContentCategories.Add(category);
            await dbContext.SaveChangesAsync();

            return Ok(AppResponse<Guid>.Success(category.Id));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error creating content category");
            return StatusCode(500, AppResponse<Guid>.Fail("Lỗi khi tạo thư mục"));
        }
    }

    /// <summary>
    /// Cập nhật thư mục
    /// </summary>
    [HttpPut("{id:guid}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<IActionResult> UpdateCategory(Guid id, [FromBody] CreateCategoryDto dto)
    {
        try
        {
            var category = await dbContext.ContentCategories
                .AsTracking()
                .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == RequiredStoreId);

            if (category == null)
                return NotFound(AppResponse<bool>.Fail("Không tìm thấy thư mục"));

            category.Name = dto.Name;
            category.Description = dto.Description;
            category.IconName = dto.IconName;
            category.Color = dto.Color;
            category.DisplayOrder = dto.DisplayOrder;
            category.ParentCategoryId = dto.ParentCategoryId;
            category.UpdatedAt = DateTime.UtcNow;
            category.UpdatedBy = CurrentUserId.ToString();

            await dbContext.SaveChangesAsync();
            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error updating content category {Id}", id);
            return StatusCode(500, AppResponse<bool>.Fail("Lỗi khi cập nhật thư mục"));
        }
    }

    /// <summary>
    /// Xóa thư mục
    /// </summary>
    [HttpDelete("{id:guid}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<IActionResult> DeleteCategory(Guid id)
    {
        try
        {
            var category = await dbContext.ContentCategories
                .AsTracking()
                .FirstOrDefaultAsync(c => c.Id == id && c.StoreId == RequiredStoreId);

            if (category == null)
                return NotFound(AppResponse<bool>.Fail("Không tìm thấy thư mục"));

            // Soft delete
            category.IsActive = false;
            category.UpdatedAt = DateTime.UtcNow;
            category.UpdatedBy = CurrentUserId.ToString();

            await dbContext.SaveChangesAsync();
            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Error deleting content category {Id}", id);
            return StatusCode(500, AppResponse<bool>.Fail("Lỗi khi xóa thư mục"));
        }
    }
}

public record CreateCategoryDto
{
    public string Name { get; init; } = string.Empty;
    public string? Description { get; init; }
    public CommunicationType ContentType { get; init; }
    public string? IconName { get; init; }
    public string? Color { get; init; }
    public int DisplayOrder { get; init; }
    public Guid? ParentCategoryId { get; init; }
}
