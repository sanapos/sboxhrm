using Google.Apis.Auth.OAuth2;
using Google.Apis.Drive.v3;
using Google.Apis.Services;
using Google.Apis.Upload;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Application.Interfaces;

namespace ZKTecoADMS.Infrastructure.Services;

/// <summary>
/// Google Drive file storage - lưu file lên Google Drive thay vì local
/// </summary>
public class GoogleDriveStorageService : IFileStorageService
{
    private readonly ILogger<GoogleDriveStorageService> _logger;
    private DriveService? _driveService;
    private string? _rootFolderId;
    private bool _isInitialized;

    public GoogleDriveStorageService(ILogger<GoogleDriveStorageService> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Khởi tạo Google Drive service từ credentials JSON và folder ID
    /// </summary>
    public async Task<bool> InitializeAsync(string credentialsJson, string? folderId = null)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(credentialsJson))
            {
                _logger.LogWarning("Google Drive credentials JSON is empty");
                return false;
            }

            GoogleCredential credential;
            
            // Parse credentials JSON (Service Account)
            credential = GoogleCredential.FromJson(credentialsJson)
                .CreateScoped(DriveService.Scope.DriveFile);

            _driveService = new DriveService(new BaseClientService.Initializer
            {
                HttpClientInitializer = credential,
                ApplicationName = "ZKTeco ADMS File Storage"
            });

            // Nếu có folder ID, verify nó tồn tại
            if (!string.IsNullOrEmpty(folderId))
            {
                try
                {
                    var folder = await _driveService.Files.Get(folderId).ExecuteAsync();
                    _rootFolderId = folderId;
                    _logger.LogInformation("Google Drive initialized with folder: {FolderName} ({FolderId})", 
                        folder.Name, folderId);
                }
                catch
                {
                    _logger.LogWarning("Folder ID {FolderId} not found, will create folders at root", folderId);
                    _rootFolderId = null;
                }
            }

            _isInitialized = true;
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to initialize Google Drive service");
            _isInitialized = false;
            return false;
        }
    }

    public bool IsInitialized => _isInitialized;

    public async Task<string> UploadAsync(Stream fileStream, string fileName, string folder = "uploads")
    {
        if (!_isInitialized || _driveService == null)
        {
            throw new InvalidOperationException("Google Drive service is not initialized");
        }

        try
        {
            // Tạo hoặc tìm subfolder
            var parentFolderId = await GetOrCreateFolderAsync(folder);

            // Tạo unique filename
            var extension = Path.GetExtension(fileName);
            var uniqueFileName = $"{Guid.NewGuid()}{extension}";

            // Upload file
            var fileMetadata = new Google.Apis.Drive.v3.Data.File
            {
                Name = uniqueFileName,
                Parents = new List<string> { parentFolderId },
                Description = $"Original: {fileName}, Uploaded: {DateTime.UtcNow:yyyy-MM-dd HH:mm:ss}"
            };

            var mimeType = GetMimeType(extension);
            var request = _driveService.Files.Create(fileMetadata, fileStream, mimeType);
            request.Fields = "id, name, webViewLink, webContentLink";

            var result = await request.UploadAsync();
            if (result.Status == UploadStatus.Failed)
            {
                throw new Exception($"Upload failed: {result.Exception?.Message}");
            }

            var uploadedFile = request.ResponseBody;

            // Đặt permission cho ai có link đều xem được
            await SetFilePublicReadAsync(uploadedFile.Id);

            // Trả về URL trực tiếp xem file
            var directUrl = $"https://drive.google.com/uc?export=view&id={uploadedFile.Id}";
            
            _logger.LogInformation("File uploaded to Google Drive: {FileName} -> {FileId}", 
                uniqueFileName, uploadedFile.Id);

            // Return đường dẫn dạng gdrive://{fileId}
            return $"gdrive://{uploadedFile.Id}";
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to upload file to Google Drive: {FileName}", fileName);
            throw;
        }
    }

    public async Task<bool> DeleteAsync(string filePath)
    {
        if (!_isInitialized || _driveService == null)
            return false;

        try
        {
            var fileId = ExtractFileId(filePath);
            if (string.IsNullOrEmpty(fileId))
                return false;

            await _driveService.Files.Delete(fileId).ExecuteAsync();
            _logger.LogInformation("File deleted from Google Drive: {FileId}", fileId);
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to delete file from Google Drive: {FilePath}", filePath);
            return false;
        }
    }

    public string GetFileUrl(string filePath)
    {
        if (string.IsNullOrEmpty(filePath))
            return string.Empty;

        // Nếu đã là URL đầy đủ
        if (filePath.StartsWith("http"))
            return filePath;

        // Nếu là gdrive:// protocol  
        var fileId = ExtractFileId(filePath);
        if (!string.IsNullOrEmpty(fileId))
        {
            return $"https://drive.google.com/uc?export=view&id={fileId}";
        }

        return filePath;
    }

    /// <summary>
    /// Test kết nối Google Drive
    /// </summary>
    public async Task<(bool Success, string Message)> TestConnectionAsync()
    {
        if (!_isInitialized || _driveService == null)
            return (false, "Google Drive chưa được khởi tạo");

        try
        {
            var aboutReq = _driveService.About.Get();
            aboutReq.Fields = "storageQuota, user";
            var about = await aboutReq.ExecuteAsync();
            var storageQuota = about.StorageQuota;

            var usedGB = (storageQuota?.Usage ?? 0) / 1024.0 / 1024.0 / 1024.0;
            var limitGB = (storageQuota?.Limit ?? 0) / 1024.0 / 1024.0 / 1024.0;

            return (true, $"Kết nối thành công! Đã dùng: {usedGB:F2}GB / {limitGB:F2}GB");
        }
        catch (Exception ex)
        {
            return (false, $"Lỗi kết nối: {ex.Message}");
        }
    }

    /// <summary>
    /// Lấy thông tin dung lượng
    /// </summary>
    public async Task<(long Used, long Limit, int FileCount)> GetStorageInfoAsync()
    {
        if (!_isInitialized || _driveService == null)
            return (0, 0, 0);

        try
        {
            var aboutReq = _driveService.About.Get();
            aboutReq.Fields = "storageQuota";
            var about = await aboutReq.ExecuteAsync();

            // Count files in our folder
            var fileCount = 0;
            if (!string.IsNullOrEmpty(_rootFolderId))
            {
                var listReq = _driveService.Files.List();
                listReq.Q = $"'{_rootFolderId}' in parents and trashed = false";
                listReq.Fields = "nextPageToken, files(id)";
                listReq.PageSize = 1000;
                var files = await listReq.ExecuteAsync();
                fileCount = files.Files?.Count ?? 0;
            }

            return (
                about.StorageQuota?.Usage ?? 0,
                about.StorageQuota?.Limit ?? 0,
                fileCount
            );
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to get Google Drive storage info");
            return (0, 0, 0);
        }
    }

    #region Private Methods

    private async Task<string> GetOrCreateFolderAsync(string folderPath)
    {
        var parentId = _rootFolderId ?? "root";
        var folderParts = folderPath.Split('/', StringSplitOptions.RemoveEmptyEntries);

        foreach (var part in folderParts)
        {
            var existingFolder = await FindFolderAsync(part, parentId);
            if (existingFolder != null)
            {
                parentId = existingFolder;
            }
            else
            {
                parentId = await CreateFolderAsync(part, parentId);
            }
        }

        return parentId;
    }

    private async Task<string?> FindFolderAsync(string name, string parentId)
    {
        var request = _driveService!.Files.List();
        request.Q = $"name = '{name}' and '{parentId}' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false";
        request.Fields = "files(id, name)";
        
        var result = await request.ExecuteAsync();
        return result.Files?.FirstOrDefault()?.Id;
    }

    private async Task<string> CreateFolderAsync(string name, string parentId)
    {
        var folderMetadata = new Google.Apis.Drive.v3.Data.File
        {
            Name = name,
            MimeType = "application/vnd.google-apps.folder",
            Parents = new List<string> { parentId }
        };

        var request = _driveService!.Files.Create(folderMetadata);
        request.Fields = "id";
        var folder = await request.ExecuteAsync();

        _logger.LogInformation("Created Google Drive folder: {Name} ({Id})", name, folder.Id);
        return folder.Id;
    }

    private async Task SetFilePublicReadAsync(string fileId)
    {
        try
        {
            var permission = new Google.Apis.Drive.v3.Data.Permission
            {
                Role = "reader",
                Type = "anyone"
            };
            await _driveService!.Permissions.Create(permission, fileId).ExecuteAsync();
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to set public read permission for file: {FileId}", fileId);
        }
    }

    private static string ExtractFileId(string path)
    {
        if (string.IsNullOrEmpty(path))
            return string.Empty;

        // gdrive://{fileId}
        if (path.StartsWith("gdrive://"))
            return path.Substring("gdrive://".Length);

        // https://drive.google.com/uc?export=view&id={fileId}
        if (path.Contains("id="))
        {
            var uri = new Uri(path);
            var query = System.Web.HttpUtility.ParseQueryString(uri.Query);
            return query["id"] ?? string.Empty;
        }

        // https://drive.google.com/file/d/{fileId}/view
        if (path.Contains("/file/d/"))
        {
            var parts = path.Split("/file/d/");
            if (parts.Length > 1)
            {
                return parts[1].Split('/')[0];
            }
        }

        return path;
    }

    private static string GetMimeType(string extension)
    {
        return extension.ToLowerInvariant() switch
        {
            ".jpg" or ".jpeg" => "image/jpeg",
            ".png" => "image/png",
            ".gif" => "image/gif",
            ".webp" => "image/webp",
            ".pdf" => "application/pdf",
            ".doc" => "application/msword",
            ".docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            ".xls" => "application/vnd.ms-excel",
            ".xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            _ => "application/octet-stream"
        };
    }

    #endregion
}
