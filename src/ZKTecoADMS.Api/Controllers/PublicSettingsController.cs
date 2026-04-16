using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.DTOs.SystemAdmin;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Public endpoints for app settings (no authentication required)
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class PublicSettingsController : ControllerBase
{
    private readonly ZKTecoDbContext _dbContext;
    private readonly ILogger<PublicSettingsController> _logger;
    private readonly ICacheService _cache;

    public PublicSettingsController(
        ZKTecoDbContext dbContext,
        ILogger<PublicSettingsController> logger,
        ICacheService cache)
    {
        _dbContext = dbContext;
        _logger = logger;
        _cache = cache;
    }

    /// <summary>
    /// Lấy tất cả public settings
    /// </summary>
    [HttpGet]
    public async Task<ActionResult<AppResponse<PublicAppSettingsResponse>>> GetPublicSettings()
    {
        try
        {
            var settings = await _cache.GetOrCreateAsync("public_settings", async () =>
                await _dbContext.AppSettings
                    .Where(s => s.IsPublic)
                    .ToDictionaryAsync(s => s.Key, s => s.Value),
                TimeSpan.FromMinutes(10)) ?? new Dictionary<string, string?>();

            var response = new PublicAppSettingsResponse(
                // General
                settings.GetValueOrDefault(AppSettingKeys.CompanyLogo),
                settings.GetValueOrDefault(AppSettingKeys.CompanyName),
                settings.GetValueOrDefault(AppSettingKeys.CompanyAddress),
                settings.GetValueOrDefault(AppSettingKeys.CompanyDescription),
                
                // Contact
                settings.GetValueOrDefault(AppSettingKeys.FeedbackEmail),
                settings.GetValueOrDefault(AppSettingKeys.TechnicalSupportPhone),
                settings.GetValueOrDefault(AppSettingKeys.TechnicalSupportEmail),
                settings.GetValueOrDefault(AppSettingKeys.SalesPhone),
                settings.GetValueOrDefault(AppSettingKeys.SalesEmail),
                
                // Social
                settings.GetValueOrDefault(AppSettingKeys.FacebookUrl),
                settings.GetValueOrDefault(AppSettingKeys.YoutubeUrl),
                settings.GetValueOrDefault(AppSettingKeys.ZaloUrl),
                settings.GetValueOrDefault(AppSettingKeys.WebsiteUrl),
                
                // Legal
                settings.GetValueOrDefault(AppSettingKeys.TermsOfService),
                settings.GetValueOrDefault(AppSettingKeys.PrivacyPolicy)
            );

            return Ok(AppResponse<PublicAppSettingsResponse>.Success(response));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting public settings");
            return StatusCode(500, AppResponse<PublicAppSettingsResponse>.Fail("Error getting public settings"));
        }
    }

    /// <summary>
    /// Lấy setting theo key (chỉ public settings)
    /// </summary>
    [HttpGet("{key}")]
    public async Task<ActionResult<AppResponse<string>>> GetSetting(string key)
    {
        try
        {
            var setting = await _cache.GetOrCreateAsync($"public_setting:{key}", async () =>
                await _dbContext.AppSettings
                    .FirstOrDefaultAsync(s => s.Key == key && s.IsPublic),
                TimeSpan.FromMinutes(10));

            if (setting == null)
            {
                return NotFound(AppResponse<string>.Fail("Setting không tồn tại hoặc không được phép truy cập"));
            }

            return Ok(AppResponse<string>.Success(setting.Value ?? ""));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting public setting {Key}", key);
            return StatusCode(500, AppResponse<string>.Fail("Error getting public setting"));
        }
    }
}
