using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Interfaces;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// File storage: local wwwroot only (Google Drive removed from product).
/// </summary>
public class FileStorageResolver : IFileStorageService
{
    private readonly IServiceProvider _serviceProvider;
    private readonly ILogger<FileStorageResolver> _logger;

    public FileStorageResolver(
        IServiceProvider serviceProvider,
        ILogger<FileStorageResolver> logger)
    {
        _serviceProvider = serviceProvider;
        _logger = logger;
        _logger.LogInformation("File storage: local wwwroot only");
    }

    private LocalFileStorageService Local =>
        _serviceProvider.GetRequiredService<LocalFileStorageService>();

    public Task<string> UploadAsync(Stream fileStream, string fileName, string folder = "uploads")
        => Local.UploadAsync(fileStream, fileName, folder);

    public Task<bool> DeleteAsync(string filePath) => Local.DeleteAsync(filePath);

    public string GetFileUrl(string filePath)
    {
        if (string.IsNullOrEmpty(filePath))
            return string.Empty;

        // Legacy gdrive:// paths: serve via API/static fallback if file was migrated
        if (filePath.StartsWith("gdrive://", StringComparison.OrdinalIgnoreCase)
            || filePath.Contains("drive.google.com", StringComparison.OrdinalIgnoreCase))
        {
            _logger.LogDebug("Legacy Google Drive path requested: {Path}", filePath);
            return filePath;
        }

        if (filePath.StartsWith("http", StringComparison.OrdinalIgnoreCase))
            return filePath;

        return Local.GetFileUrl(filePath);
    }

    public void InvalidateCache() { }
}
