using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Interfaces;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// Local file storage service that saves files to wwwroot/uploads
/// </summary>
public class LocalFileStorageService : IFileStorageService
{
    private readonly IWebHostEnvironment _environment;
    private readonly ILogger<LocalFileStorageService> _logger;
    private readonly string _baseUrl;

    public LocalFileStorageService(
        IWebHostEnvironment environment,
        ILogger<LocalFileStorageService> logger,
        Microsoft.AspNetCore.Http.IHttpContextAccessor httpContextAccessor)
    {
        _environment = environment;
        _logger = logger;
        
        var request = httpContextAccessor.HttpContext?.Request;
        _baseUrl = request != null 
            ? $"{request.Scheme}://{request.Host}" 
            : "http://localhost:7070";
    }

    public async Task<string> UploadAsync(Stream fileStream, string fileName, string folder = "uploads")
    {
        try
        {
            // Create uploads directory if not exists
            var uploadsPath = Path.Combine(_environment.ContentRootPath, "wwwroot", folder);
            if (!Directory.Exists(uploadsPath))
            {
                Directory.CreateDirectory(uploadsPath);
            }

            // Generate unique filename
            var extension = Path.GetExtension(fileName);
            var uniqueFileName = $"{Guid.NewGuid()}{extension}";
            var filePath = Path.Combine(uploadsPath, uniqueFileName);

            // Save file
            using (var fileStreamOutput = new FileStream(filePath, FileMode.Create))
            {
                await fileStream.CopyToAsync(fileStreamOutput);
            }

            // Return relative path
            var relativePath = $"/{folder}/{uniqueFileName}";
            _logger.LogInformation("File uploaded successfully: {FilePath}", relativePath);
            
            return relativePath;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to upload file: {FileName}", fileName);
            throw;
        }
    }

    public async Task<bool> DeleteAsync(string filePath)
    {
        try
        {
            if (string.IsNullOrEmpty(filePath))
                return false;

            // Remove leading slash
            var relativePath = filePath.TrimStart('/');
            var fullPath = Path.Combine(_environment.ContentRootPath, "wwwroot", relativePath);

            if (File.Exists(fullPath))
            {
                File.Delete(fullPath);
                _logger.LogInformation("File deleted: {FilePath}", filePath);
                return true;
            }

            return false;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to delete file: {FilePath}", filePath);
            return false;
        }
    }

    public string GetFileUrl(string filePath)
    {
        if (string.IsNullOrEmpty(filePath))
            return string.Empty;

        return $"{_baseUrl}{filePath}";
    }
}
