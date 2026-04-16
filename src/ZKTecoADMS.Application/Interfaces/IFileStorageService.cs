namespace ZKTecoADMS.Application.Interfaces;

/// <summary>
/// Interface for file storage operations
/// </summary>
public interface IFileStorageService
{
    /// <summary>
    /// Upload a file and return the stored path/URL
    /// </summary>
    Task<string> UploadAsync(Stream fileStream, string fileName, string folder = "uploads");
    
    /// <summary>
    /// Delete a file by path
    /// </summary>
    Task<bool> DeleteAsync(string filePath);
    
    /// <summary>
    /// Get file URL from stored path
    /// </summary>
    string GetFileUrl(string filePath);
}
