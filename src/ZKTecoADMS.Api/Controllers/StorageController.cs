using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Quản lý cấu hình lưu trữ file (Google Drive)
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize]
public class StorageController : AuthenticatedControllerBase
{
    private readonly ZKTecoDbContext _dbContext;
    private readonly GoogleDriveStorageService _googleDriveService;
    private readonly FileStorageResolver _storageResolver;
    private readonly ILogger<StorageController> _logger;

    public StorageController(
        ZKTecoDbContext dbContext,
        GoogleDriveStorageService googleDriveService,
        FileStorageResolver storageResolver,
        ILogger<StorageController> logger)
    {
        _dbContext = dbContext;
        _googleDriveService = googleDriveService;
        _storageResolver = storageResolver;
        _logger = logger;
    }

    /// <summary>
    /// Lấy cấu hình Google Drive hiện tại
    /// </summary>
    [HttpGet("google-drive/config")]
    public async Task<ActionResult<AppResponse<GoogleDriveConfigDto>>> GetGoogleDriveConfig()
    {
        try
        {
            var storeId = RequiredStoreId;
            var settings = await _dbContext.Set<AppSettings>()
                .Where(s => s.StoreId == storeId && s.Key.StartsWith("google_drive_"))
                .ToListAsync();

            var enabled = settings.FirstOrDefault(s => s.Key == AppSettingKeys.GoogleDriveEnabled)?.Value == "true";
            var credJson = settings.FirstOrDefault(s => s.Key == AppSettingKeys.GoogleDriveCredentialsJson)?.Value;
            var folderId = settings.FirstOrDefault(s => s.Key == AppSettingKeys.GoogleDriveFolderId)?.Value;
            var folderName = settings.FirstOrDefault(s => s.Key == AppSettingKeys.GoogleDriveFolderName)?.Value;

            var config = new GoogleDriveConfigDto
            {
                IsEnabled = enabled,
                HasCredentials = !string.IsNullOrWhiteSpace(credJson),
                FolderId = folderId ?? "",
                FolderName = folderName ?? "",
                // Mask credentials
                CredentialsSummary = !string.IsNullOrWhiteSpace(credJson) 
                    ? MaskCredentials(credJson) 
                    : ""
            };

            return Ok(AppResponse<GoogleDriveConfigDto>.Success(config));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting Google Drive config");
            return StatusCode(500, AppResponse<GoogleDriveConfigDto>.Fail("Lỗi lấy cấu hình Google Drive"));
        }
    }

    /// <summary>
    /// Cập nhật cấu hình Google Drive
    /// </summary>
    [HttpPost("google-drive/config")]
    public async Task<ActionResult<AppResponse<object>>> UpdateGoogleDriveConfig([FromBody] UpdateGoogleDriveConfigRequest request)
    {
        try
        {
            // Upsert settings
            if (request.IsEnabled.HasValue)
            {
                await UpsertSettingAsync(AppSettingKeys.GoogleDriveEnabled, request.IsEnabled.Value.ToString().ToLower(), 
                    "Bật/tắt Google Drive storage", "Storage");
            }

            if (!string.IsNullOrWhiteSpace(request.CredentialsJson))
            {
                await UpsertSettingAsync(AppSettingKeys.GoogleDriveCredentialsJson, request.CredentialsJson,
                    "Google Drive Service Account credentials JSON", "Storage");
            }

            if (request.FolderId != null)
            {
                await UpsertSettingAsync(AppSettingKeys.GoogleDriveFolderId, request.FolderId,
                    "Google Drive root folder ID", "Storage");
            }

            if (request.FolderName != null)
            {
                await UpsertSettingAsync(AppSettingKeys.GoogleDriveFolderName, request.FolderName,
                    "Google Drive root folder name", "Storage");
            }

            await _dbContext.SaveChangesAsync();

            // Invalidate resolver cache
            _storageResolver.InvalidateCache();

            _logger.LogInformation("Google Drive config updated by user {UserId}", CurrentUserId);

            return Ok(AppResponse<object>.Success(new { message = "Cập nhật cấu hình Google Drive thành công" }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating Google Drive config");
            return StatusCode(500, AppResponse<object>.Fail("Lỗi cập nhật cấu hình Google Drive"));
        }
    }

    /// <summary>
    /// Test kết nối Google Drive
    /// </summary>
    [HttpPost("google-drive/test")]
    public async Task<ActionResult<AppResponse<object>>> TestGoogleDriveConnection()
    {
        try
        {
            // Load hiện tại từ DB
            var storeId = RequiredStoreId;
            var credJson = await _dbContext.Set<AppSettings>()
                .Where(s => s.StoreId == storeId && s.Key == AppSettingKeys.GoogleDriveCredentialsJson)
                .Select(s => s.Value)
                .FirstOrDefaultAsync();

            var folderId = await _dbContext.Set<AppSettings>()
                .Where(s => s.StoreId == storeId && s.Key == AppSettingKeys.GoogleDriveFolderId)
                .Select(s => s.Value)
                .FirstOrDefaultAsync();

            if (string.IsNullOrWhiteSpace(credJson))
            {
                return Ok(AppResponse<object>.Fail("Chưa cấu hình credentials JSON"));
            }

            var initialized = await _googleDriveService.InitializeAsync(credJson, folderId);
            if (!initialized)
            {
                return Ok(AppResponse<object>.Fail("Không thể khởi tạo Google Drive service"));
            }

            var (success, message) = await _googleDriveService.TestConnectionAsync();

            if (success)
            {
                var (used, limit, fileCount) = await _googleDriveService.GetStorageInfoAsync();
                return Ok(AppResponse<object>.Success(new
                {
                    message,
                    usedBytes = used,
                    limitBytes = limit,
                    usedGB = Math.Round(used / 1024.0 / 1024.0 / 1024.0, 2),
                    limitGB = Math.Round(limit / 1024.0 / 1024.0 / 1024.0, 2),
                    fileCount
                }));
            }

            return Ok(AppResponse<object>.Fail(message));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error testing Google Drive connection");
            return StatusCode(500, AppResponse<object>.Fail($"Lỗi kiểm tra kết nối: {ex.Message}"));
        }
    }

    /// <summary>
    /// Lấy thông tin storage hiện tại
    /// </summary>
    [HttpGet("info")]
    public async Task<ActionResult<AppResponse<object>>> GetStorageInfo()
    {
        try
        {
            var storeId = RequiredStoreId;
            var gdEnabled = await _dbContext.Set<AppSettings>()
                .Where(s => s.StoreId == storeId && s.Key == AppSettingKeys.GoogleDriveEnabled)
                .Select(s => s.Value)
                .FirstOrDefaultAsync();

            var storageType = gdEnabled == "true" ? "google_drive" : "local";

            if (storageType == "google_drive")
            {
                var credJson = await _dbContext.Set<AppSettings>()
                    .Where(s => s.StoreId == storeId && s.Key == AppSettingKeys.GoogleDriveCredentialsJson)
                    .Select(s => s.Value)
                    .FirstOrDefaultAsync();

                var folderId = await _dbContext.Set<AppSettings>()
                    .Where(s => s.StoreId == storeId && s.Key == AppSettingKeys.GoogleDriveFolderId)
                    .Select(s => s.Value)
                    .FirstOrDefaultAsync();

                if (!string.IsNullOrWhiteSpace(credJson))
                {
                    await _googleDriveService.InitializeAsync(credJson, folderId);
                    var (used, limit, fileCount) = await _googleDriveService.GetStorageInfoAsync();
                    
                    return Ok(AppResponse<object>.Success(new
                    {
                        storageType,
                        usedBytes = used,
                        limitBytes = limit,
                        usedGB = Math.Round(used / 1024.0 / 1024.0 / 1024.0, 2),
                        limitGB = Math.Round(limit / 1024.0 / 1024.0 / 1024.0, 2),
                        fileCount
                    }));
                }
            }

            return Ok(AppResponse<object>.Success(new
            {
                storageType,
                message = storageType == "local" ? "Đang dùng lưu trữ cục bộ (wwwroot)" : "Google Drive chưa cấu hình"
            }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting storage info");
            return StatusCode(500, AppResponse<object>.Fail("Lỗi lấy thông tin storage"));
        }
    }

    #region Private Methods

    private async Task UpsertSettingAsync(string key, string value, string description, string group)
    {
        var storeId = RequiredStoreId;
        var existing = await _dbContext.Set<AppSettings>()
            .FirstOrDefaultAsync(s => s.StoreId == storeId && s.Key == key);

        if (existing != null)
        {
            existing.Value = value;
            existing.Description = description;
        }
        else
        {
            _dbContext.Set<AppSettings>().Add(new AppSettings
            {
                Id = Guid.NewGuid(),
                Key = key,
                Value = value,
                Description = description,
                Group = group,
                DataType = key.Contains("json") ? "textarea" : "text",
                IsPublic = false,
                DisplayOrder = 100,
                StoreId = storeId
            });
        }
    }

    private static string MaskCredentials(string json)
    {
        try
        {
            // Extract service account email from JSON
            if (json.Contains("client_email"))
            {
                var startIdx = json.IndexOf("\"client_email\"");
                var colonIdx = json.IndexOf(':', startIdx);
                var quoteStart = json.IndexOf('"', colonIdx + 1);
                var quoteEnd = json.IndexOf('"', quoteStart + 1);
                if (quoteStart >= 0 && quoteEnd > quoteStart)
                {
                    var email = json.Substring(quoteStart + 1, quoteEnd - quoteStart - 1);
                    return $"Service Account: {email}";
                }
            }
            return "Credentials đã cấu hình";
        }
        catch
        {
            return "Credentials đã cấu hình";
        }
    }

    #endregion
}

// ---- DTOs ----

public class GoogleDriveConfigDto
{
    public bool IsEnabled { get; set; }
    public bool HasCredentials { get; set; }
    public string CredentialsSummary { get; set; } = "";
    public string FolderId { get; set; } = "";
    public string FolderName { get; set; } = "";
}

public class UpdateGoogleDriveConfigRequest
{
    public bool? IsEnabled { get; set; }
    public string? CredentialsJson { get; set; }
    public string? FolderId { get; set; }
    public string? FolderName { get; set; }
}
