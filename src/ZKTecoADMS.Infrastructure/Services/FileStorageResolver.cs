using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// Factory giải quyết IFileStorageService: Google Drive nếu đã cấu hình, ngược lại dùng Local
/// </summary>
public class FileStorageResolver : IFileStorageService
{
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<FileStorageResolver> _logger;
    private IFileStorageService? _resolvedService;
    private bool _resolved;

    public FileStorageResolver(
        IServiceProvider serviceProvider,
        ILogger<FileStorageResolver> logger)
    {
        _serviceProvider = serviceProvider;
        _logger = logger;
    }

    private async Task<IFileStorageService> ResolveAsync()
    {
        if (_resolved && _resolvedService != null)
            return _resolvedService;

        try
        {
            using var scope = _serviceProvider.CreateScope();
            var dbContext = scope.ServiceProvider.GetRequiredService<ZKTecoDbContext>();
            
            // Check if Google Drive is enabled
            // IgnoreQueryFilters: Google Drive settings may have NULL StoreId (global config)
            // and multi-tenant query filters would exclude them
            var gdEnabled = await dbContext.Set<AppSettings>()
                .IgnoreQueryFilters()
                .AsNoTracking()
                .FirstOrDefaultAsync(s => s.Key == AppSettingKeys.GoogleDriveEnabled);

            if (gdEnabled?.Value?.ToLower() == "true")
            {
                var gdCredentials = await dbContext.Set<AppSettings>()
                    .IgnoreQueryFilters()
                    .AsNoTracking()
                    .FirstOrDefaultAsync(s => s.Key == AppSettingKeys.GoogleDriveCredentialsJson);
                
                var gdFolderId = await dbContext.Set<AppSettings>()
                    .IgnoreQueryFilters()
                    .AsNoTracking()
                    .FirstOrDefaultAsync(s => s.Key == AppSettingKeys.GoogleDriveFolderId);

                var gdImpersonateEmail = await dbContext.Set<AppSettings>()
                    .IgnoreQueryFilters()
                    .AsNoTracking()
                    .FirstOrDefaultAsync(s => s.Key == AppSettingKeys.GoogleDriveImpersonateEmail);

                if (!string.IsNullOrWhiteSpace(gdCredentials?.Value))
                {
                    var gdService = scope.ServiceProvider.GetRequiredService<GoogleDriveStorageService>();
                    var initialized = await gdService.InitializeAsync(
                        gdCredentials.Value, gdFolderId?.Value, gdImpersonateEmail?.Value);
                    
                    if (initialized)
                    {
                        _resolvedService = gdService;
                        _resolved = true;
                        _logger.LogInformation("File storage resolved to Google Drive");
                        return _resolvedService;
                    }
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to resolve Google Drive storage, falling back to local");
        }

        // Fallback to local storage
        _resolvedService = _serviceProvider.GetRequiredService<LocalFileStorageService>();
        _resolved = true;
        _logger.LogInformation("File storage resolved to Local storage");
        return _resolvedService;
    }

    /// <summary>
    /// Clear cache khi user thay đổi cấu hình storage
    /// </summary>
    public void InvalidateCache()
    {
        _resolved = false;
        _resolvedService = null;
    }

    public async Task<string> UploadAsync(Stream fileStream, string fileName, string folder = "uploads")
    {
        var service = await ResolveAsync();
        try
        {
            return await service.UploadAsync(fileStream, fileName, folder);
        }
        catch (Exception ex) when (service is GoogleDriveStorageService)
        {
            // Google Drive upload failed (e.g. quota issue), fallback to local
            _logger.LogWarning(ex, "Google Drive upload failed, falling back to local storage for: {FileName}", fileName);
            
            // Reset stream position before retry
            if (fileStream.CanSeek)
                fileStream.Position = 0;
                
            var localService = _serviceProvider.GetRequiredService<LocalFileStorageService>();
            return await localService.UploadAsync(fileStream, fileName, folder);
        }
    }

    public async Task<bool> DeleteAsync(string filePath)
    {
        var service = await ResolveAsync();
        return await service.DeleteAsync(filePath);
    }

    public string GetFileUrl(string filePath)
    {
        if (string.IsNullOrEmpty(filePath))
            return string.Empty;

        // Google Drive URLs
        if (filePath.StartsWith("gdrive://") || filePath.Contains("drive.google.com"))
        {
            var gdService = new GoogleDriveStorageService(_serviceProvider.GetRequiredService<ILogger<GoogleDriveStorageService>>());
            return gdService.GetFileUrl(filePath);
        }

        // Local file URLs
        if (filePath.StartsWith("http"))
            return filePath;

        var localService = _serviceProvider.GetRequiredService<LocalFileStorageService>();
        return localService.GetFileUrl(filePath);
    }
}
