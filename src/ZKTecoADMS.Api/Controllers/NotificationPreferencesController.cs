using Microsoft.AspNetCore.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Notifications;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/notification-preferences")]
public class NotificationPreferencesController(
    IRepository<NotificationCategory> categoryRepository,
    IRepository<NotificationPreference> preferenceRepository
) : AuthenticatedControllerBase
{
    /// <summary>
    /// Lấy danh sách nhóm thông báo
    /// </summary>
    [HttpGet("categories")]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<List<NotificationCategoryDto>>>> GetCategories()
    {
        var categories = await categoryRepository.GetAllAsync(
            filter: c => c.StoreId == null || c.StoreId == CurrentStoreId,
            orderBy: q => q.OrderBy(c => c.DisplayOrder));

        var dtos = categories.Select(c => new NotificationCategoryDto
        {
            Id = c.Id,
            Code = c.Code,
            DisplayName = c.DisplayName,
            Description = c.Description,
            Icon = c.Icon,
            DisplayOrder = c.DisplayOrder,
            IsSystem = c.IsSystem,
            DefaultEnabled = c.DefaultEnabled
        }).ToList();

        return Ok(AppResponse<List<NotificationCategoryDto>>.Success(dtos));
    }

    /// <summary>
    /// Lấy thiết lập nhận thông báo của user hiện tại
    /// </summary>
    [HttpGet]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<List<NotificationPreferenceDto>>>> GetPreferences()
    {
        var categories = await categoryRepository.GetAllAsync(
            filter: c => c.StoreId == null || c.StoreId == CurrentStoreId,
            orderBy: q => q.OrderBy(c => c.DisplayOrder));

        var preferences = await preferenceRepository.GetAllAsync(
            filter: p => p.UserId == CurrentUserId && (p.StoreId == null || p.StoreId == CurrentStoreId));

        var prefDict = preferences.ToDictionary(p => p.CategoryCode, p => p.IsEnabled);

        var dtos = categories.Select(c => new NotificationPreferenceDto
        {
            CategoryCode = c.Code,
            CategoryDisplayName = c.DisplayName,
            CategoryDescription = c.Description,
            CategoryIcon = c.Icon,
            DisplayOrder = c.DisplayOrder,
            IsEnabled = prefDict.TryGetValue(c.Code, out var enabled) ? enabled : c.DefaultEnabled
        }).ToList();

        return Ok(AppResponse<List<NotificationPreferenceDto>>.Success(dtos));
    }

    /// <summary>
    /// Cập nhật thiết lập nhận thông báo
    /// </summary>
    [HttpPut]
    [Authorize(Policy = PolicyNames.AtLeastEmployee)]
    public async Task<ActionResult<AppResponse<List<NotificationPreferenceDto>>>> UpdatePreferences(
        [FromBody] UpdateNotificationPreferencesRequest request)
    {
        var storeId = CurrentStoreId;

        // Pre-load all existing preferences to avoid N+1
        var existingPrefs = await preferenceRepository.GetAllAsync(
            p => p.UserId == CurrentUserId && (p.StoreId == null || p.StoreId == storeId));
        var existingMap = existingPrefs.ToDictionary(p => p.CategoryCode);

        foreach (var item in request.Preferences)
        {
            if (existingMap.TryGetValue(item.CategoryCode, out var existing))
            {
                existing.IsEnabled = item.IsEnabled;
                await preferenceRepository.UpdateAsync(existing);
            }
            else
            {
                await preferenceRepository.AddAsync(new NotificationPreference
                {
                    Id = Guid.NewGuid(),
                    UserId = CurrentUserId,
                    CategoryCode = item.CategoryCode,
                    IsEnabled = item.IsEnabled,
                    StoreId = storeId
                });
            }
        }

        return await GetPreferences();
    }
}
