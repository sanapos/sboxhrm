using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Controller for file uploads and OCR processing
/// </summary>
[ApiController]
[Route("api/[controller]")]
public class UploadController : AuthenticatedControllerBase
{
    private readonly IFileStorageService _fileStorageService;
    private readonly CccdOcrService _ocrService;
    private readonly ZKTecoDbContext _dbContext;
    private readonly ILogger<UploadController> _logger;

    public UploadController(
        IFileStorageService fileStorageService,
        CccdOcrService ocrService,
        ZKTecoDbContext dbContext,
        ILogger<UploadController> logger)
    {
        _fileStorageService = fileStorageService;
        _ocrService = ocrService;
        _dbContext = dbContext;
        _logger = logger;
    }

    /// <summary>
    /// Lấy folder prefix theo store: stores/{storeCode}/
    /// </summary>
    private async Task<string> GetStoreFolderAsync(string subfolder)
    {
        var storeId = CurrentStoreId;
        if (storeId.HasValue)
        {
            var storeCode = await _dbContext.Stores
                .Where(s => s.Id == storeId.Value)
                .Select(s => s.Code)
                .FirstOrDefaultAsync();

            if (!string.IsNullOrEmpty(storeCode))
            {
                return $"stores/{storeCode}/{subfolder}";
            }
        }
        return subfolder;
    }

    // Allowed MIME types mapped to extensions
    private static readonly Dictionary<string, string[]> AllowedMimeTypes = new(StringComparer.OrdinalIgnoreCase)
    {
        { "image/jpeg", new[] { ".jpg", ".jpeg", ".jfif" } },
        { "image/png", new[] { ".png" } },
        { "image/gif", new[] { ".gif" } },
        { "image/webp", new[] { ".webp" } },
        { "image/bmp", new[] { ".bmp" } },
        { "image/tiff", new[] { ".tiff", ".tif" } },
        { "image/heic", new[] { ".heic" } },
        { "image/heif", new[] { ".heif" } },
        { "image/svg+xml", new[] { ".svg" } },
        { "image/avif", new[] { ".avif" } },
        { "image/x-icon", new[] { ".ico" } },
        { "application/pdf", new[] { ".pdf" } },
    };

    /// <summary>
    /// Validate file magic bytes match declared extension
    /// </summary>
    private static bool ValidateMagicBytes(Stream stream, string extension)
    {
        if (stream.Length < 4) return false;

        var header = new byte[12];
        var originalPosition = stream.Position;
        stream.Position = 0;
        var bytesRead = stream.Read(header, 0, header.Length);
        stream.Position = originalPosition;

        if (bytesRead < 4) return false;

        return extension.ToLowerInvariant() switch
        {
            ".jpg" or ".jpeg" or ".jfif" => header[0] == 0xFF && header[1] == 0xD8 && header[2] == 0xFF,
            ".png" => header[0] == 0x89 && header[1] == 0x50 && header[2] == 0x4E && header[3] == 0x47,
            ".gif" => header[0] == 0x47 && header[1] == 0x49 && header[2] == 0x46,
            ".bmp" => header[0] == 0x42 && header[1] == 0x4D,
            ".webp" => bytesRead >= 12 && header[0] == 0x52 && header[1] == 0x49 && header[2] == 0x46 && header[3] == 0x46
                        && header[8] == 0x57 && header[9] == 0x45 && header[10] == 0x42 && header[11] == 0x50,
            ".tiff" or ".tif" => (header[0] == 0x49 && header[1] == 0x49 && header[2] == 0x2A && header[3] == 0x00)
                                 || (header[0] == 0x4D && header[1] == 0x4D && header[2] == 0x00 && header[3] == 0x2A),
            ".pdf" => header[0] == 0x25 && header[1] == 0x50 && header[2] == 0x44 && header[3] == 0x46,
            ".ico" => header[0] == 0x00 && header[1] == 0x00 && header[2] == 0x01 && header[3] == 0x00,
            ".avif" => bytesRead >= 12 && header[4] == 0x66 && header[5] == 0x74 && header[6] == 0x79 && header[7] == 0x70,
            // SVG, HEIC, HEIF - skip magic bytes check (text-based or complex container)
            ".svg" or ".heic" or ".heif" => true,
            _ => false,
        };
    }

    /// <summary>
    /// Upload a single file (image, document, etc.)
    /// </summary>
    [HttpPost("file")]
    [RequestSizeLimit(10_000_000)] // 10MB limit
    public async Task<IActionResult> UploadFile(
        IFormFile file,
        [FromQuery] string? folder = "uploads")
    {
        if (file == null || file.Length == 0)
        {
            return BadRequest(new { isSuccess = false, message = "No file provided" });
        }

        // Validate file extension
        var allowedExtensions = AllowedMimeTypes.Values.SelectMany(e => e).ToHashSet(StringComparer.OrdinalIgnoreCase);
        var extension = Path.GetExtension(file.FileName).ToLowerInvariant();
        if (!allowedExtensions.Contains(extension))
        {
            return BadRequest(new { isSuccess = false, message = $"Định dạng {extension} không được hỗ trợ. Vui lòng chọn ảnh JPG, PNG, GIF, WEBP, BMP, TIFF, HEIC, SVG hoặc AVIF." });
        }

        // Validate MIME type matches extension
        if (!string.IsNullOrEmpty(file.ContentType) && AllowedMimeTypes.TryGetValue(file.ContentType, out var mimeExts))
        {
            if (!mimeExts.Contains(extension, StringComparer.OrdinalIgnoreCase))
            {
                return BadRequest(new { isSuccess = false, message = "Content-Type không khớp với định dạng file." });
            }
        }

        try
        {
            var storeFolder = await GetStoreFolderAsync(folder ?? "uploads");
            using var stream = file.OpenReadStream();

            // Validate magic bytes
            if (!ValidateMagicBytes(stream, extension))
            {
                return BadRequest(new { isSuccess = false, message = "Nội dung file không khớp với định dạng khai báo." });
            }

            stream.Position = 0;
            var filePath = await _fileStorageService.UploadAsync(stream, file.FileName, storeFolder);
            var fileUrl = _fileStorageService.GetFileUrl(filePath);

            return Ok(new 
            { 
                isSuccess = true, 
                data = new 
                { 
                    filePath,
                    fileUrl,
                    fileName = file.FileName,
                    fileSize = file.Length,
                    contentType = file.ContentType
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to upload file: {FileName}", file.FileName);
            return StatusCode(500, new { isSuccess = false, message = "Failed to upload file" });
        }
    }

    /// <summary>
    /// Upload employee profile photo
    /// </summary>
    [HttpPost("employee-photo")]
    [RequestSizeLimit(5_000_000)] // 5MB limit
    public async Task<IActionResult> UploadEmployeePhoto(IFormFile file)
    {
        return await UploadFile(file, "employees/photos");
    }

    /// <summary>
    /// Upload employee CCCD front image
    /// </summary>
    [HttpPost("cccd-front")]
    [RequestSizeLimit(5_000_000)] // 5MB limit
    public async Task<IActionResult> UploadCccdFront(IFormFile file)
    {
        return await UploadFile(file, "employees/cccd/front");
    }

    /// <summary>
    /// Upload employee CCCD back image
    /// </summary>
    [HttpPost("cccd-back")]
    [RequestSizeLimit(5_000_000)] // 5MB limit
    public async Task<IActionResult> UploadCccdBack(IFormFile file)
    {
        return await UploadFile(file, "employees/cccd/back");
    }

    /// <summary>
    /// Parse CCCD OCR text extracted from client-side
    /// Use this with mobile OCR (Google ML Kit, etc.)
    /// </summary>
    [HttpPost("parse-cccd-text")]
    public IActionResult ParseCccdText([FromBody] ParseCccdTextRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.OcrText))
        {
            return BadRequest(new { isSuccess = false, message = "OCR text is required" });
        }

        try
        {
            var result = _ocrService.ParseCccdText(request.OcrText);
            
            return Ok(new
            {
                isSuccess = result.IsSuccess,
                message = result.ErrorMessage,
                data = new
                {
                    idNumber = result.IdNumber,
                    fullName = result.FullName,
                    dateOfBirth = result.DateOfBirth,
                    gender = result.Gender,
                    nationality = result.Nationality,
                    placeOfOrigin = result.PlaceOfOrigin,
                    placeOfResidence = result.PlaceOfResidence,
                    issueDate = result.IssueDate,
                    expiryDate = result.ExpiryDate,
                    issuePlace = result.IssuePlace
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to parse CCCD text");
            return StatusCode(500, new { isSuccess = false, message = "Failed to parse CCCD" });
        }
    }

    /// <summary>
    /// Upload multiple files at once
    /// </summary>
    [HttpPost("files")]
    [RequestSizeLimit(50_000_000)] // 50MB total limit
    public async Task<IActionResult> UploadFiles(
        List<IFormFile> files,
        [FromQuery] string? folder = "uploads")
    {
        if (files == null || files.Count == 0)
        {
            return BadRequest(new { isSuccess = false, message = "No files provided" });
        }

        var results = new List<object>();
        var errors = new List<string>();

        var allowedExts = AllowedMimeTypes.Values.SelectMany(e => e).ToHashSet(StringComparer.OrdinalIgnoreCase);

        foreach (var file in files)
        {
            try
            {
                var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
                if (!allowedExts.Contains(ext))
                {
                    errors.Add($"{file.FileName}: Định dạng {ext} không được hỗ trợ.");
                    continue;
                }

                var storeFolder = await GetStoreFolderAsync(folder ?? "uploads");
                using var stream = file.OpenReadStream();

                if (!ValidateMagicBytes(stream, ext))
                {
                    errors.Add($"{file.FileName}: Nội dung file không khớp với định dạng khai báo.");
                    continue;
                }

                stream.Position = 0;
                var filePath = await _fileStorageService.UploadAsync(stream, file.FileName, storeFolder);
                var fileUrl = _fileStorageService.GetFileUrl(filePath);

                results.Add(new
                {
                    filePath,
                    fileUrl,
                    fileName = file.FileName,
                    fileSize = file.Length
                });
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to upload file: {FileName}", file.FileName);
                errors.Add($"Failed to upload {file.FileName}: {ex.Message}");
            }
        }

        return Ok(new
        {
            isSuccess = errors.Count == 0,
            data = results,
            errors = errors.Count > 0 ? errors : null
        });
    }

    /// <summary>
    /// Delete a file by path
    /// </summary>
    [HttpDelete("file")]
    public async Task<IActionResult> DeleteFile([FromQuery] string filePath)
    {
        if (string.IsNullOrWhiteSpace(filePath))
        {
            return BadRequest(new { isSuccess = false, message = "File path is required" });
        }

        try
        {
            var success = await _fileStorageService.DeleteAsync(filePath);
            return Ok(new { isSuccess = success });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to delete file: {FilePath}", filePath);
            return StatusCode(500, new { isSuccess = false, message = "Failed to delete file" });
        }
    }
}

public class ParseCccdTextRequest
{
    public string OcrText { get; set; } = string.Empty;
}
