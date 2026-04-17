using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using System.Text.Json;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;
using ZKTecoADMS.Api.Services;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/mobile-attendance")]
[EnableRateLimiting("device")]
public class MobileAttendanceController : AuthenticatedControllerBase
{
    private readonly IFileStorageService _fileStorageService;
    private readonly ZKTecoDbContext _dbContext;
    private readonly ILogger<MobileAttendanceController> _logger;
    private readonly IMemoryCache _cache;
    private readonly FaceComparisonService _faceComparisonService;
    private readonly IAttendanceNotificationService _attendanceNotificationService;
    private readonly ISystemNotificationService _systemNotificationService;

    // Normalize BSSID to hex-only lowercase string for comparison
    // Handles: "AA:BB:CC:DD:EE:FF", "aa-bb-cc-dd-ee-ff", "aabbccddeeff", " AA:BB:CC:DD:EE:FF "
    private static string NormalizeBssidHex(string bssid) =>
        new string(bssid.Where(c => char.IsAsciiHexDigit(c)).ToArray()).ToLowerInvariant();

    public MobileAttendanceController(
        IFileStorageService fileStorageService,
        ZKTecoDbContext dbContext,
        ILogger<MobileAttendanceController> logger,
        IMemoryCache cache,
        FaceComparisonService faceComparisonService,
        IAttendanceNotificationService attendanceNotificationService,
        ISystemNotificationService systemNotificationService)
    {
        _fileStorageService = fileStorageService;
        _dbContext = dbContext;
        _logger = logger;
        _cache = cache;
        _faceComparisonService = faceComparisonService;
        _attendanceNotificationService = attendanceNotificationService;
        _systemNotificationService = systemNotificationService;
    }

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
                return $"stores/{storeCode}/{subfolder}";
        }
        return subfolder;
    }

    // ==================== SETTINGS ====================

    [HttpGet("settings")]
    [Authorize]
    public async Task<ActionResult> GetSettings()
    {
        var storeId = RequiredStoreId;
        var settings = await _dbContext.MobileAttendanceSettings
            .AsNoTracking()
            .FirstOrDefaultAsync(s => s.StoreId == storeId && s.Deleted == null);

        if (settings == null)
        {
            return Ok(AppResponse<object>.Success(new
            {
                enableFaceId = true,
                enableGps = true,
                enableWifi = false,
                verificationMode = "all",
                enableLivenessDetection = true,
                gpsRadiusMeters = 100,
                minFaceMatchScore = 55.0,
                autoApproveInRange = true,
                allowManualApproval = true,
                maxPhotosPerRegistration = 5,
                maxPunchesPerDay = 4,
                requirePhotoProof = false,
                minPunchIntervalMinutes = 5,
            }));
        }

        return Ok(AppResponse<object>.Success(new
        {
            enableFaceId = settings.EnableFaceId,
            enableGps = settings.EnableGps,
            enableWifi = settings.EnableWifi,
            verificationMode = settings.VerificationMode ?? "all",
            enableLivenessDetection = settings.EnableLivenessDetection,
            gpsRadiusMeters = settings.GpsRadiusMeters,
            minFaceMatchScore = settings.MinFaceMatchScore,
            autoApproveInRange = settings.AutoApproveInRange,
            allowManualApproval = settings.AllowManualApproval,
            maxPhotosPerRegistration = settings.MaxPhotosPerRegistration,
            maxPunchesPerDay = settings.MaxPunchesPerDay,
            requirePhotoProof = settings.RequirePhotoProof,
            minPunchIntervalMinutes = settings.MinPunchIntervalMinutes,
        }));
    }

    /// <summary>
    /// Employee-accessible endpoint to get mobile attendance verification requirements.
    /// </summary>
    [HttpGet("my-settings")]
    [Authorize]
    public async Task<ActionResult> GetMySettings()
    {
        var storeId = RequiredStoreId;
        var settings = await _cache.GetOrCreateAsync($"mobile_settings_{storeId}", async entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(5);
            entry.Size = 1;
            return await _dbContext.MobileAttendanceSettings
                .AsNoTracking()
                .FirstOrDefaultAsync(s => s.StoreId == storeId && s.Deleted == null);
        });

        return Ok(AppResponse<object>.Success(new
        {
            enableFaceId = settings?.EnableFaceId ?? true,
            enableGps = settings?.EnableGps ?? true,
            enableWifi = settings?.EnableWifi ?? false,
            verificationMode = settings?.VerificationMode ?? "all",
            minFaceMatchScore = settings?.MinFaceMatchScore ?? 55.0,
            autoApproveInRange = settings?.AutoApproveInRange ?? true,
            gpsRadiusMeters = settings?.GpsRadiusMeters ?? 100,
        }));
    }

    [HttpPut("settings")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> UpdateSettings([FromBody] UpdateMobileSettingsRequest request)
    {
        var storeId = RequiredStoreId;
        var settings = await _dbContext.MobileAttendanceSettings
            .AsTracking()
            .FirstOrDefaultAsync(s => s.StoreId == storeId && s.Deleted == null);

        if (settings == null)
        {
            settings = new MobileAttendanceSetting
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            };
            _dbContext.MobileAttendanceSettings.Add(settings);
        }

        if (request.EnableFaceId.HasValue) settings.EnableFaceId = request.EnableFaceId.Value;
        if (request.EnableGps.HasValue) settings.EnableGps = request.EnableGps.Value;
        if (request.EnableWifi.HasValue) settings.EnableWifi = request.EnableWifi.Value;
        if (!string.IsNullOrEmpty(request.VerificationMode)) settings.VerificationMode = request.VerificationMode;
        if (request.EnableLivenessDetection.HasValue) settings.EnableLivenessDetection = request.EnableLivenessDetection.Value;
        if (request.GpsRadiusMeters.HasValue) settings.GpsRadiusMeters = (int)request.GpsRadiusMeters.Value;
        if (request.MinFaceMatchScore.HasValue) settings.MinFaceMatchScore = request.MinFaceMatchScore.Value;
        if (request.AutoApproveInRange.HasValue) settings.AutoApproveInRange = request.AutoApproveInRange.Value;
        if (request.AllowManualApproval.HasValue) settings.AllowManualApproval = request.AllowManualApproval.Value;
        if (request.MaxPunchesPerDay.HasValue) settings.MaxPunchesPerDay = request.MaxPunchesPerDay.Value;
        if (request.RequirePhotoProof.HasValue) settings.RequirePhotoProof = request.RequirePhotoProof.Value;
        if (request.MaxPhotosPerRegistration.HasValue) settings.MaxPhotosPerRegistration = request.MaxPhotosPerRegistration.Value;
        if (request.MinPunchIntervalMinutes.HasValue) settings.MinPunchIntervalMinutes = request.MinPunchIntervalMinutes.Value;

        settings.UpdatedAt = DateTime.UtcNow;
        settings.UpdatedBy = CurrentUserEmail;
        await _dbContext.SaveChangesAsync();
        _cache.Remove($"mobile_settings_{storeId}");

        _logger.LogInformation("Mobile attendance settings updated for store {StoreId}", storeId);
        return Ok(AppResponse<object>.Success(new { updated = true }));
    }

    // ==================== WORK LOCATIONS ====================

    [HttpGet("locations")]
    [Authorize]
    public async Task<ActionResult> GetLocations()
    {
        var storeId = RequiredStoreId;
        var locations = await _dbContext.MobileWorkLocations
            .AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null)
            .OrderByDescending(l => l.CreatedAt)
            .Select(l => new
            {
                id = l.Id.ToString(),
                name = l.Name,
                address = l.Address,
                latitude = l.Latitude,
                longitude = l.Longitude,
                radius = l.Radius,
                isActive = l.IsActive,
                autoApproveInRange = l.AutoApproveInRange,
                wifiSsid = l.WifiSsid,
                wifiBssid = l.WifiBssid,
                allowedIpRange = l.AllowedIpRange,
                createdAt = l.CreatedAt,
                updatedAt = l.UpdatedAt,
            })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(locations));
    }

    [HttpPost("locations")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> AddLocation([FromBody] WorkLocationRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Name))
            return BadRequest(AppResponse<object>.Fail("Tên vị trí không được để trống"));

        var storeId = RequiredStoreId;
        var location = new MobileWorkLocation
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Name = request.Name,
            Address = request.Address ?? string.Empty,
            Latitude = request.Latitude,
            Longitude = request.Longitude,
            Radius = (int)(request.Radius > 0 ? request.Radius : 100),
            AutoApproveInRange = request.AutoApproveInRange,
            WifiSsid = request.WifiSsid,
            WifiBssid = request.WifiBssid,
            AllowedIpRange = request.AllowedIpRange,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };

        _dbContext.MobileWorkLocations.Add(location);
        await _dbContext.SaveChangesAsync();
        _cache.Remove($"work_locations_{storeId}");
        _cache.Remove("wifi_locations_all");

        _logger.LogInformation("Work location {Name} added for store {StoreId}", request.Name, storeId);
        return Ok(AppResponse<object>.Success(new
        {
            id = location.Id.ToString(),
            name = location.Name,
            address = location.Address,
            latitude = location.Latitude,
            longitude = location.Longitude,
            radius = location.Radius,
            isActive = location.IsActive,
            autoApproveInRange = location.AutoApproveInRange,
            wifiSsid = location.WifiSsid,
            wifiBssid = location.WifiBssid,
            allowedIpRange = location.AllowedIpRange,
            createdAt = location.CreatedAt,
        }));
    }

    [HttpPut("locations/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> UpdateLocation(Guid id, [FromBody] WorkLocationRequest request)
    {
        var storeId = RequiredStoreId;
        var location = await _dbContext.MobileWorkLocations
            .AsTracking()
            .FirstOrDefaultAsync(l => l.Id == id && l.StoreId == storeId && l.Deleted == null);

        if (location == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy vị trí"));

        if (!string.IsNullOrWhiteSpace(request.Name)) location.Name = request.Name;
        if (request.Address != null) location.Address = request.Address;
        location.Latitude = request.Latitude;
        location.Longitude = request.Longitude;
        if (request.Radius > 0) location.Radius = (int)request.Radius;
        location.AutoApproveInRange = request.AutoApproveInRange;
        location.WifiSsid = request.WifiSsid;
        location.WifiBssid = request.WifiBssid;
        location.AllowedIpRange = request.AllowedIpRange;
        location.UpdatedAt = DateTime.UtcNow;
        location.UpdatedBy = CurrentUserEmail;

        await _dbContext.SaveChangesAsync();
        _cache.Remove($"work_locations_{storeId}");
        _cache.Remove("wifi_locations_all");

        _logger.LogInformation("Work location {Id} updated", id);
        return Ok(AppResponse<object>.Success(new
        {
            id = location.Id.ToString(),
            name = location.Name,
            address = location.Address,
            latitude = location.Latitude,
            longitude = location.Longitude,
            radius = location.Radius,
            isActive = location.IsActive,
            autoApproveInRange = location.AutoApproveInRange,
            wifiSsid = location.WifiSsid,
            wifiBssid = location.WifiBssid,
            allowedIpRange = location.AllowedIpRange,
            createdAt = location.CreatedAt,
            updatedAt = location.UpdatedAt,
        }));
    }

    [HttpDelete("locations/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> DeleteLocation(Guid id)
    {
        var storeId = RequiredStoreId;
        var location = await _dbContext.MobileWorkLocations
            .AsTracking()
            .FirstOrDefaultAsync(l => l.Id == id && l.StoreId == storeId && l.Deleted == null);

        if (location == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy vị trí"));

        location.Deleted = DateTime.UtcNow;
        location.DeletedBy = CurrentUserEmail;
        await _dbContext.SaveChangesAsync();
        _cache.Remove($"work_locations_{storeId}");
        _cache.Remove("wifi_locations_all");

        _logger.LogInformation("Work location {Id} deleted", id);
        return Ok(AppResponse<object>.Success(new { deleted = true }));
    }

    // ==================== FACE REGISTRATIONS ====================

    [HttpGet("face-registrations")]
    [Authorize]
    public async Task<ActionResult> GetFaceRegistrations()
    {
        var storeId = RequiredStoreId;
        var registrations = await _dbContext.MobileFaceRegistrations
            .AsNoTracking()
            .Where(f => f.StoreId == storeId && f.Deleted == null)
            .OrderByDescending(f => f.RegisteredAt)
            .Select(f => new
            {
                id = f.Id.ToString(),
                odooEmployeeId = f.OdooEmployeeId,
                employeeName = f.EmployeeName,
                employeeCode = f.EmployeeCode,
                department = f.Department,
                faceImages = f.FaceImagesJson,
                isVerified = f.IsVerified,
                registeredAt = f.RegisteredAt,
                lastVerifiedAt = f.LastVerifiedAt,
            })
            .ToListAsync();

        // Parse JSON arrays for faceImages, normalize absolute URLs to relative paths
        var result = registrations.Select(r => new
        {
            r.id,
            r.odooEmployeeId,
            r.employeeName,
            r.employeeCode,
            r.department,
            faceImages = (JsonSerializer.Deserialize<List<string>>(r.faceImages ?? "[]") ?? new List<string>())
                .Select(NormalizeImagePath).ToList(),
            r.isVerified,
            r.registeredAt,
            r.lastVerifiedAt,
        }).ToList();

        return Ok(AppResponse<object>.Success(result));
    }

    [HttpPost("face-registrations")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequestSizeLimit(20_000_000)]
    public async Task<IActionResult> RegisterFace([FromBody] FaceRegistrationRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.EmployeeId) || string.IsNullOrWhiteSpace(request.EmployeeName))
            return BadRequest(AppResponse<object>.Fail("Vui lòng cung cấp thông tin nhân viên"));

        if (request.FaceImages == null || request.FaceImages.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Vui lòng cung cấp ít nhất 1 ảnh khuôn mặt"));

        if (request.FaceImages.Count > 5)
            return BadRequest(AppResponse<object>.Fail("Tối đa 5 ảnh khuôn mặt"));

        try
        {
            var storeId = RequiredStoreId;
            var uploadFolder = await GetStoreFolderAsync("uploads/face-registrations");
            var storedImageUrls = new List<string>();

            foreach (var base64Image in request.FaceImages)
            {
                if (string.IsNullOrWhiteSpace(base64Image)) continue;

                var base64Data = base64Image;
                if (base64Data.Contains(","))
                    base64Data = base64Data.Substring(base64Data.IndexOf(",") + 1);

                var estimatedSize = (long)(base64Data.Length * 3.0 / 4.0);
                if (estimatedSize > 5 * 1024 * 1024)
                    return BadRequest(AppResponse<object>.Fail("Mỗi ảnh khuôn mặt tối đa 5MB"));

                byte[] imageBytes;
                try { imageBytes = Convert.FromBase64String(base64Data); }
                catch { return BadRequest(AppResponse<object>.Fail("Dữ liệu ảnh không hợp lệ")); }

                if (imageBytes.Length < 4 ||
                    !(imageBytes[0] == 0xFF && imageBytes[1] == 0xD8 && imageBytes[2] == 0xFF) &&
                    !(imageBytes[0] == 0x89 && imageBytes[1] == 0x50 && imageBytes[2] == 0x4E && imageBytes[3] == 0x47))
                    return BadRequest(AppResponse<object>.Fail("Ảnh khuôn mặt chỉ hỗ trợ định dạng JPEG hoặc PNG"));

                var ext = (imageBytes[0] == 0xFF) ? ".jpg" : ".png";
                var fileName = $"face_{request.EmployeeId}_{Guid.NewGuid():N}{ext}";

                using var stream = new MemoryStream(imageBytes);
                var storedPath = await _fileStorageService.UploadAsync(stream, fileName, uploadFolder);
                // Store relative path (not absolute URL) so it works from any client
                storedImageUrls.Add(storedPath);
            }

            // Check for existing registration
            var existing = await _dbContext.MobileFaceRegistrations
                .AsTracking()
                .FirstOrDefaultAsync(f => f.OdooEmployeeId == request.EmployeeId && f.StoreId == storeId && f.Deleted == null);

            if (existing != null)
            {
                // Append new images to existing
                var existingImages = JsonSerializer.Deserialize<List<string>>(existing.FaceImagesJson ?? "[]") ?? new List<string>();
                existingImages.AddRange(storedImageUrls);
                existing.FaceImagesJson = JsonSerializer.Serialize(existingImages);
                existing.UpdatedAt = DateTime.UtcNow;
                existing.UpdatedBy = CurrentUserEmail;
            }
            else
            {
                existing = new MobileFaceRegistration
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    OdooEmployeeId = request.EmployeeId,
                    EmployeeName = request.EmployeeName,
                    FaceImagesJson = JsonSerializer.Serialize(storedImageUrls),
                    IsVerified = false,
                    RegisteredAt = DateTime.UtcNow,
                    IsActive = true,
                    CreatedBy = CurrentUserEmail,
                };
                _dbContext.MobileFaceRegistrations.Add(existing);
            }

            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("Face registered for employee {EmployeeId} ({EmployeeName}), {Count} images",
                request.EmployeeId, request.EmployeeName, storedImageUrls.Count);

            return Ok(AppResponse<object>.Success(new
            {
                id = existing.Id.ToString(),
                odooEmployeeId = existing.OdooEmployeeId,
                employeeName = existing.EmployeeName,
                faceImages = JsonSerializer.Deserialize<List<string>>(existing.FaceImagesJson ?? "[]"),
                isVerified = existing.IsVerified,
                registeredAt = existing.RegisteredAt,
            }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error registering face for employee {EmployeeId}", request.EmployeeId);
            return StatusCode(500, AppResponse<object>.Fail("Lỗi khi đăng ký khuôn mặt"));
        }
    }

    [HttpDelete("face-registrations/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> DeleteFaceRegistration(Guid id)
    {
        var storeId = RequiredStoreId;
        var reg = await _dbContext.MobileFaceRegistrations
            .AsTracking()
            .FirstOrDefaultAsync(f => f.Id == id && f.StoreId == storeId && f.Deleted == null);

        if (reg == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy đăng ký khuôn mặt"));

        reg.Deleted = DateTime.UtcNow;
        reg.DeletedBy = CurrentUserEmail;
        await _dbContext.SaveChangesAsync();

        _logger.LogInformation("Face registration {Id} deleted", id);
        return Ok(AppResponse<object>.Success(new { deleted = true }));
    }

    // ==================== AUTHORIZED DEVICES ====================

    [HttpGet("devices")]
    [Authorize]
    public async Task<ActionResult> GetDevices()
    {
        var storeId = RequiredStoreId;
        var devices = await _dbContext.AuthorizedMobileDevices
            .AsNoTracking()
            .Where(d => d.StoreId == storeId && d.Deleted == null)
            .OrderByDescending(d => d.AuthorizedAt)
            .ToListAsync();

        // Get all face registrations for this store to link with devices
        var faceRegs = await _dbContext.MobileFaceRegistrations
            .AsNoTracking()
            .Where(f => f.StoreId == storeId && f.Deleted == null)
            .ToListAsync();

        var faceRegMap = faceRegs.ToDictionary(f => f.OdooEmployeeId, f => f);

        var result = devices.Select(d =>
        {
            FaceRegistrationInfo? faceInfo = null;
            if (!string.IsNullOrEmpty(d.EmployeeId) && faceRegMap.TryGetValue(d.EmployeeId, out var faceReg))
            {
                faceInfo = new FaceRegistrationInfo
                {
                    FaceImages = JsonSerializer.Deserialize<List<string>>(faceReg.FaceImagesJson ?? "[]") ?? new List<string>(),
                    IsVerified = faceReg.IsVerified,
                    RegisteredAt = faceReg.RegisteredAt,
                };
            }

            return new
            {
                id = d.Id.ToString(),
                deviceId = d.DeviceId,
                deviceName = d.DeviceName,
                deviceModel = d.DeviceModel,
                osVersion = d.OsVersion,
                employeeId = d.EmployeeId,
                employeeName = d.EmployeeName,
                isAuthorized = d.IsAuthorized,
                canUseFaceId = d.CanUseFaceId,
                canUseGps = d.CanUseGps,
                allowOutsideCheckIn = d.AllowOutsideCheckIn,
                wifiBssid = d.WifiBssid,
                authorizedAt = d.AuthorizedAt,
                lastUsedAt = d.LastUsedAt,
                faceImages = faceInfo?.FaceImages ?? new List<string>(),
                faceVerified = faceInfo?.IsVerified ?? false,
                faceRegisteredAt = faceInfo?.RegisteredAt,
            };
        }).ToList();

        return Ok(AppResponse<object>.Success(result));
    }

    [HttpPost("devices")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> AuthorizeDevice([FromBody] AuthorizeDeviceRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.DeviceId) || string.IsNullOrWhiteSpace(request.DeviceName))
            return BadRequest(AppResponse<object>.Fail("Thông tin thiết bị không hợp lệ"));

        var storeId = RequiredStoreId;

        // Check if device already exists
        var existing = await _dbContext.AuthorizedMobileDevices
            .AsTracking()
            .FirstOrDefaultAsync(d => d.DeviceId == request.DeviceId && d.StoreId == storeId && d.Deleted == null);

        if (existing != null)
        {
            existing.IsAuthorized = true;
            existing.DeviceName = request.DeviceName;
            existing.DeviceModel = request.DeviceModel ?? existing.DeviceModel;
            existing.EmployeeId = request.EmployeeId;
            existing.EmployeeName = request.EmployeeName;
            existing.CanUseFaceId = request.CanUseFaceId;
            existing.CanUseGps = request.CanUseGps;
            existing.AllowOutsideCheckIn = request.AllowOutsideCheckIn;
            existing.UpdatedAt = DateTime.UtcNow;
            existing.UpdatedBy = CurrentUserEmail;
        }
        else
        {
            existing = new AuthorizedMobileDevice
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                DeviceId = request.DeviceId,
                DeviceName = request.DeviceName,
                DeviceModel = request.DeviceModel ?? "Unknown",
                OsVersion = request.OsVersion,
                EmployeeId = request.EmployeeId,
                EmployeeName = request.EmployeeName,
                IsAuthorized = true,
                CanUseFaceId = request.CanUseFaceId,
                CanUseGps = request.CanUseGps,
                AllowOutsideCheckIn = request.AllowOutsideCheckIn,
                AuthorizedAt = DateTime.UtcNow,
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            };
            _dbContext.AuthorizedMobileDevices.Add(existing);
        }

        await _dbContext.SaveChangesAsync();

        _logger.LogInformation("Device {DeviceId} authorized for store {StoreId}", request.DeviceId, storeId);
        return Ok(AppResponse<object>.Success(new
        {
            id = existing.Id.ToString(),
            deviceId = existing.DeviceId,
            deviceName = existing.DeviceName,
            deviceModel = existing.DeviceModel,
            employeeId = existing.EmployeeId,
            employeeName = existing.EmployeeName,
            isAuthorized = existing.IsAuthorized,
            canUseFaceId = existing.CanUseFaceId,
            canUseGps = existing.CanUseGps,
            allowOutsideCheckIn = existing.AllowOutsideCheckIn,
            authorizedAt = existing.AuthorizedAt,
        }));
    }

    [HttpDelete("devices/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> RevokeDevice(Guid id)
    {
        var storeId = RequiredStoreId;
        var device = await _dbContext.AuthorizedMobileDevices
            .AsTracking()
            .FirstOrDefaultAsync(d => d.Id == id && d.StoreId == storeId && d.Deleted == null);

        if (device == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy thiết bị"));

        device.IsAuthorized = false;
        device.Deleted = DateTime.UtcNow;
        device.DeletedBy = CurrentUserEmail;
        await _dbContext.SaveChangesAsync();

        _logger.LogInformation("Device {Id} revoked", id);
        return Ok(AppResponse<object>.Success(new { deleted = true }));
    }

    // ==================== EMPLOYEE SELF-SERVICE DEVICE REGISTRATION ====================

    /// <summary>
    /// Employee registers their mobile device + face for mobile attendance.
    /// One employee can only register ONE device.
    /// </summary>
    [HttpPost("register-device")]
    [Authorize]
    [RequestSizeLimit(20_000_000)]
    public async Task<ActionResult> RegisterDeviceWithFace([FromBody] RegisterDeviceWithFaceRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.DeviceId) || string.IsNullOrWhiteSpace(request.DeviceName))
            return BadRequest(AppResponse<object>.Fail("Thông tin thiết bị không hợp lệ"));

        if (request.FaceImages == null || request.FaceImages.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Vui lòng chụp ảnh khuôn mặt"));

        if (request.FaceImages.Count > 5)
            return BadRequest(AppResponse<object>.Fail("Tối đa 5 ảnh khuôn mặt"));

        var storeId = RequiredStoreId;
        var employeeId = request.EmployeeId;
        var employeeName = request.EmployeeName;

        if (string.IsNullOrWhiteSpace(employeeId) || string.IsNullOrWhiteSpace(employeeName))
            return BadRequest(AppResponse<object>.Fail("Không xác định được nhân viên"));

        // Check if employee already has a registered device (not deleted)
        var existingDevice = await _dbContext.AuthorizedMobileDevices
            .AsNoTracking()
            .FirstOrDefaultAsync(d => d.EmployeeId == employeeId && d.StoreId == storeId && d.Deleted == null);

        if (existingDevice != null)
        {
            // Check if there's already a pending device change request
            var pendingChangeRequest = await _dbContext.DeviceChangeRequests
                .AsNoTracking()
                .FirstOrDefaultAsync(r => r.EmployeeId == employeeId && r.StoreId == storeId && r.Status == 0 && r.Deleted == null);

            return Conflict(AppResponse<object>.Success(new
            {
                alreadyRegistered = true,
                message = "Tài khoản đã đăng ký thiết bị. Mỗi tài khoản chỉ được đăng ký 1 thiết bị.",
                existingDeviceName = existingDevice.DeviceName,
                existingDeviceModel = existingDevice.DeviceModel,
                existingDeviceId = existingDevice.DeviceId,
                isAuthorized = existingDevice.IsAuthorized,
                registeredAt = existingDevice.AuthorizedAt,
                hasPendingChangeRequest = pendingChangeRequest != null,
                pendingChangeRequestId = pendingChangeRequest?.Id.ToString(),
            }));
        }

        // Check if this device is already registered by another employee
        var deviceUsed = await _dbContext.AuthorizedMobileDevices
            .AsNoTracking()
            .FirstOrDefaultAsync(d => d.DeviceId == request.DeviceId && d.StoreId == storeId && d.Deleted == null);

        if (deviceUsed != null)
            return BadRequest(AppResponse<object>.Fail($"Thiết bị này đã được đăng ký bởi nhân viên khác ({deviceUsed.EmployeeName})."));

        try
        {
            // Upload face images
            var uploadFolder = await GetStoreFolderAsync("uploads/face-registrations");
            var storedImageUrls = new List<string>();

            foreach (var base64Image in request.FaceImages)
            {
                if (string.IsNullOrWhiteSpace(base64Image)) continue;

                var base64Data = base64Image;
                if (base64Data.Contains(","))
                    base64Data = base64Data.Substring(base64Data.IndexOf(",") + 1);

                byte[] imageBytes;
                try { imageBytes = Convert.FromBase64String(base64Data); }
                catch { return BadRequest(AppResponse<object>.Fail("Dữ liệu ảnh không hợp lệ")); }

                if (imageBytes.Length < 4 ||
                    !(imageBytes[0] == 0xFF && imageBytes[1] == 0xD8 && imageBytes[2] == 0xFF) &&
                    !(imageBytes[0] == 0x89 && imageBytes[1] == 0x50 && imageBytes[2] == 0x4E && imageBytes[3] == 0x47))
                    return BadRequest(AppResponse<object>.Fail("Ảnh chỉ hỗ trợ JPEG hoặc PNG"));

                var ext = (imageBytes[0] == 0xFF) ? ".jpg" : ".png";
                var fileName = $"face_{employeeId}_{Guid.NewGuid():N}{ext}";

                using var stream = new MemoryStream(imageBytes);
                var storedPath = await _fileStorageService.UploadAsync(stream, fileName, uploadFolder);
                // Store relative path (not absolute URL) so it works from any client
                storedImageUrls.Add(storedPath);
            }

            // Create face registration (pending)
            var existingFace = await _dbContext.MobileFaceRegistrations
                .AsTracking()
                .FirstOrDefaultAsync(f => f.OdooEmployeeId == employeeId && f.StoreId == storeId && f.Deleted == null);

            if (existingFace != null)
            {
                existingFace.FaceImagesJson = JsonSerializer.Serialize(storedImageUrls);
                existingFace.IsVerified = false;
                existingFace.UpdatedAt = DateTime.UtcNow;
                existingFace.UpdatedBy = CurrentUserEmail;
            }
            else
            {
                existingFace = new MobileFaceRegistration
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    OdooEmployeeId = employeeId,
                    EmployeeName = employeeName,
                    FaceImagesJson = JsonSerializer.Serialize(storedImageUrls),
                    IsVerified = false,
                    RegisteredAt = DateTime.UtcNow,
                    IsActive = true,
                    CreatedBy = CurrentUserEmail,
                };
                _dbContext.MobileFaceRegistrations.Add(existingFace);
            }

            // Create device (pending approval - IsAuthorized = false)
            var newDevice = new AuthorizedMobileDevice
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                DeviceId = request.DeviceId,
                DeviceName = request.DeviceName,
                DeviceModel = request.DeviceModel ?? "Unknown",
                OsVersion = request.OsVersion,
                EmployeeId = employeeId,
                EmployeeName = employeeName,
                IsAuthorized = false,
                CanUseFaceId = true,
                CanUseGps = true,
                WifiBssid = request.WifiBssid,
                AuthorizedAt = DateTime.UtcNow,
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            };
            _dbContext.AuthorizedMobileDevices.Add(newDevice);

            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("Device registration submitted: {DeviceId} for employee {EmployeeId} ({EmployeeName}), BSSID: {WifiBssid}",
                request.DeviceId, employeeId, employeeName, request.WifiBssid ?? "N/A");

            return Ok(AppResponse<object>.Success(new
            {
                deviceId = newDevice.Id.ToString(),
                faceRegistrationId = existingFace.Id.ToString(),
                status = "pending",
                message = "Đăng ký thành công! Chờ quản lý duyệt.",
                wifiBssid = request.WifiBssid,
            }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error registering device for employee {EmployeeId}", employeeId);
            return StatusCode(500, AppResponse<object>.Fail("Lỗi khi đăng ký thiết bị"));
        }
    }

    /// <summary>
    /// Employee checks their own device registration status.
    /// </summary>
    [HttpGet("my-device")]
    [Authorize]
    public async Task<ActionResult> GetMyDevice([FromQuery] string? employeeId)
    {
        var storeId = RequiredStoreId;
        var empId = employeeId ?? CurrentUserId.ToString();

        var device = await _dbContext.AuthorizedMobileDevices
            .AsNoTracking()
            .Where(d => d.EmployeeId == empId && d.StoreId == storeId && d.Deleted == null)
            .OrderByDescending(d => d.AuthorizedAt)
            .FirstOrDefaultAsync();

        if (device == null)
        {
            return Ok(AppResponse<object>.Success(new
            {
                registered = false,
                approved = false,
            }));
        }

        // Also get face registration
        var faceReg = await _dbContext.MobileFaceRegistrations
            .AsNoTracking()
            .Where(f => f.OdooEmployeeId == empId && f.StoreId == storeId && f.Deleted == null)
            .FirstOrDefaultAsync();

        // Parse face image paths for client-side caching & on-device comparison
        var faceImagePaths = new List<string>();
        if (faceReg != null)
        {
            var rawPaths = JsonSerializer.Deserialize<List<string>>(faceReg.FaceImagesJson ?? "[]") ?? new List<string>();
            faceImagePaths = rawPaths.Select(NormalizeImagePath).ToList();
        }

        return Ok(AppResponse<object>.Success(new
        {
            registered = true,
            approved = device.IsAuthorized,
            deviceId = device.DeviceId,
            deviceName = device.DeviceName,
            deviceModel = device.DeviceModel,
            allowOutsideCheckIn = device.AllowOutsideCheckIn,
            wifiBssid = device.WifiBssid,
            hasFaceRegistration = faceReg != null,
            faceVerified = faceReg?.IsVerified ?? false,
            faceImages = faceImagePaths,
            registeredAt = device.AuthorizedAt,
        }));
    }

    /// <summary>
    /// Manager approves/rejects a device registration (also approves linked face registration).
    /// </summary>
    [HttpPost("approve-device/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> ApproveDevice(Guid id, [FromBody] ApproveRequest request)
    {
        var storeId = RequiredStoreId;
        var device = await _dbContext.AuthorizedMobileDevices
            .AsTracking()
            .FirstOrDefaultAsync(d => d.Id == id && d.StoreId == storeId && d.Deleted == null);

        if (device == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy thiết bị"));

        device.IsAuthorized = request.Approved;
        device.UpdatedAt = DateTime.UtcNow;
        device.UpdatedBy = CurrentUserEmail;

        // Also approve/reject linked face registration
        if (!string.IsNullOrEmpty(device.EmployeeId))
        {
            var faceReg = await _dbContext.MobileFaceRegistrations
                .AsTracking()
                .FirstOrDefaultAsync(f => f.OdooEmployeeId == device.EmployeeId && f.StoreId == storeId && f.Deleted == null);

            if (faceReg != null)
            {
                faceReg.IsVerified = request.Approved;
                faceReg.UpdatedAt = DateTime.UtcNow;
                faceReg.UpdatedBy = CurrentUserEmail;
                if (request.Approved)
                    faceReg.LastVerifiedAt = DateTime.UtcNow;
            }
        }

        // If rejected, soft-delete the device so employee can re-register
        if (!request.Approved)
        {
            device.Deleted = DateTime.UtcNow;
            device.DeletedBy = CurrentUserEmail;
        }

        await _dbContext.SaveChangesAsync();

        _logger.LogInformation("Device {Id} {Action} by {User}",
            id, request.Approved ? "approved" : "rejected", CurrentUserEmail);

        return Ok(AppResponse<object>.Success(new
        {
            id = device.Id.ToString(),
            isAuthorized = device.IsAuthorized,
            action = request.Approved ? "approved" : "rejected",
        }));
    }

    // ==================== DEVICE CHANGE REQUEST ====================

    /// <summary>
    /// Employee requests to change their registered mobile device.
    /// </summary>
    [HttpPost("request-device-change")]
    [Authorize]
    [RequestSizeLimit(20_000_000)]
    public async Task<ActionResult> RequestDeviceChange([FromBody] DeviceChangeRequestDto request)
    {
        if (string.IsNullOrWhiteSpace(request.NewDeviceId) || string.IsNullOrWhiteSpace(request.NewDeviceName))
            return BadRequest(AppResponse<object>.Fail("Thông tin thiết bị mới không hợp lệ"));

        if (request.FaceImages == null || request.FaceImages.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Vui lòng chụp ảnh khuôn mặt"));

        if (request.FaceImages.Count > 5)
            return BadRequest(AppResponse<object>.Fail("Tối đa 5 ảnh khuôn mặt"));

        var storeId = RequiredStoreId;
        var employeeId = request.EmployeeId;
        var employeeName = request.EmployeeName;

        if (string.IsNullOrWhiteSpace(employeeId) || string.IsNullOrWhiteSpace(employeeName))
            return BadRequest(AppResponse<object>.Fail("Không xác định được nhân viên"));

        // Must have an existing device
        var existingDevice = await _dbContext.AuthorizedMobileDevices
            .AsNoTracking()
            .FirstOrDefaultAsync(d => d.EmployeeId == employeeId && d.StoreId == storeId && d.Deleted == null);

        if (existingDevice == null)
            return BadRequest(AppResponse<object>.Fail("Chưa có thiết bị đăng ký. Vui lòng đăng ký thiết bị mới."));

        // Check for existing pending request
        var pendingRequest = await _dbContext.DeviceChangeRequests
            .FirstOrDefaultAsync(r => r.EmployeeId == employeeId && r.StoreId == storeId && r.Status == 0 && r.Deleted == null);

        if (pendingRequest != null)
            return BadRequest(AppResponse<object>.Fail("Đã có yêu cầu đổi máy đang chờ duyệt."));

        // Check if new device is used by another employee
        var deviceUsed = await _dbContext.AuthorizedMobileDevices
            .AsNoTracking()
            .FirstOrDefaultAsync(d => d.DeviceId == request.NewDeviceId && d.StoreId == storeId && d.Deleted == null);

        if (deviceUsed != null && deviceUsed.EmployeeId != employeeId)
            return BadRequest(AppResponse<object>.Fail($"Thiết bị mới đã được đăng ký bởi nhân viên khác ({deviceUsed.EmployeeName})."));

        try
        {
            var changeRequest = new DeviceChangeRequest
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                EmployeeId = employeeId,
                EmployeeName = employeeName,
                OldDeviceRecordId = existingDevice.Id,
                OldDeviceName = existingDevice.DeviceName,
                OldDeviceModel = existingDevice.DeviceModel,
                NewDeviceId = request.NewDeviceId,
                NewDeviceName = request.NewDeviceName,
                NewDeviceModel = request.NewDeviceModel ?? "Unknown",
                NewOsVersion = request.NewOsVersion,
                NewWifiBssid = request.NewWifiBssid,
                NewFaceImagesJson = JsonSerializer.Serialize(request.FaceImages),
                Status = 0,
                Reason = request.Reason,
                RequestedAt = DateTime.UtcNow,
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            };

            _dbContext.DeviceChangeRequests.Add(changeRequest);
            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("Device change request {Id} created by employee {EmployeeId} ({EmployeeName}): {OldDevice} -> {NewDevice}",
                changeRequest.Id, employeeId, employeeName, existingDevice.DeviceName, request.NewDeviceName);

            // Notify managers
            try
            {
                var managerIds = await _dbContext.Users
                    .Where(u => u.StoreId == storeId && u.IsActive
                        && (u.Role == "Manager" || u.Role == "Admin"))
                    .Select(u => u.Id)
                    .ToListAsync();

                foreach (var managerId in managerIds)
                {
                    await _systemNotificationService.CreateAndSendAsync(
                        managerId,
                        NotificationType.ApprovalRequired,
                        "Yêu cầu đổi thiết bị chấm công",
                        $"{employeeName} yêu cầu đổi thiết bị từ \"{existingDevice.DeviceName}\" sang \"{request.NewDeviceName}\"",
                        relatedEntityType: "DeviceChangeRequest",
                        relatedEntityId: changeRequest.Id,
                        fromUserId: CurrentUserId,
                        categoryCode: "mobile_attendance",
                        storeId: storeId);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to send device change notification");
            }

            return Ok(AppResponse<object>.Success(new
            {
                requestId = changeRequest.Id.ToString(),
                status = "pending",
                message = "Yêu cầu đổi máy đã được gửi. Chờ quản lý duyệt.",
            }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating device change request for employee {EmployeeId}", employeeId);
            return StatusCode(500, AppResponse<object>.Fail("Lỗi khi gửi yêu cầu đổi máy"));
        }
    }

    /// <summary>
    /// Employee checks their device change request status.
    /// </summary>
    [HttpGet("my-device-change-request")]
    [Authorize]
    public async Task<ActionResult> GetMyDeviceChangeRequest([FromQuery] string? employeeId)
    {
        var storeId = RequiredStoreId;
        var empId = employeeId ?? CurrentUserId.ToString();

        var request = await _dbContext.DeviceChangeRequests
            .AsNoTracking()
            .Where(r => r.EmployeeId == empId && r.StoreId == storeId && r.Status == 0 && r.Deleted == null)
            .OrderByDescending(r => r.RequestedAt)
            .FirstOrDefaultAsync();

        if (request == null)
            return Ok(AppResponse<object>.Success(new { hasPendingRequest = false }));

        return Ok(AppResponse<object>.Success(new
        {
            hasPendingRequest = true,
            requestId = request.Id.ToString(),
            oldDeviceName = request.OldDeviceName,
            oldDeviceModel = request.OldDeviceModel,
            newDeviceName = request.NewDeviceName,
            newDeviceModel = request.NewDeviceModel,
            reason = request.Reason,
            requestedAt = request.RequestedAt,
        }));
    }

    /// <summary>
    /// Manager gets list of device change requests.
    /// </summary>
    [HttpGet("device-change-requests")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> GetDeviceChangeRequests([FromQuery] int? status)
    {
        var storeId = RequiredStoreId;
        var query = _dbContext.DeviceChangeRequests
            .AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null);

        if (status.HasValue)
            query = query.Where(r => r.Status == status.Value);

        var requests = await query
            .OrderByDescending(r => r.RequestedAt)
            .Select(r => new
            {
                id = r.Id,
                employeeId = r.EmployeeId,
                employeeName = r.EmployeeName,
                oldDeviceName = r.OldDeviceName,
                oldDeviceModel = r.OldDeviceModel,
                newDeviceName = r.NewDeviceName,
                newDeviceModel = r.NewDeviceModel,
                newOsVersion = r.NewOsVersion,
                reason = r.Reason,
                status = r.Status,
                requestedAt = r.RequestedAt,
                approvedAt = r.ApprovedAt,
                rejectReason = r.RejectReason,
            })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(requests));
    }

    /// <summary>
    /// Manager approves or rejects a device change request.
    /// On approval: deletes old device + face data, registers new device + face.
    /// </summary>
    [HttpPost("approve-device-change/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequestSizeLimit(20_000_000)]
    public async Task<ActionResult> ApproveDeviceChange(Guid id, [FromBody] ApproveRequest request)
    {
        var storeId = RequiredStoreId;
        var changeReq = await _dbContext.DeviceChangeRequests
            .AsTracking()
            .FirstOrDefaultAsync(r => r.Id == id && r.StoreId == storeId && r.Deleted == null);

        if (changeReq == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy yêu cầu đổi máy"));

        if (changeReq.Status != 0)
            return BadRequest(AppResponse<object>.Fail("Yêu cầu này đã được xử lý"));

        changeReq.UpdatedAt = DateTime.UtcNow;
        changeReq.UpdatedBy = CurrentUserEmail;

        if (!request.Approved)
        {
            // Reject
            changeReq.Status = 2;
            changeReq.RejectReason = request.RejectionReason;
            changeReq.ApprovedBy = CurrentUserId;
            changeReq.ApprovedAt = DateTime.UtcNow;
            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("Device change request {Id} rejected by {User}", id, CurrentUserEmail);

            // Notify employee
            try
            {
                var empUserId = Guid.TryParse(changeReq.EmployeeId, out var eid) ? eid : (Guid?)null;
                if (empUserId.HasValue)
                {
                    await _systemNotificationService.CreateAndSendAsync(
                        empUserId.Value,
                        NotificationType.Warning,
                        "Yêu cầu đổi máy bị từ chối",
                        $"Yêu cầu đổi thiết bị sang \"{changeReq.NewDeviceName}\" đã bị từ chối.{(string.IsNullOrEmpty(request.RejectionReason) ? "" : $" Lý do: {request.RejectionReason}")}",
                        relatedEntityType: "DeviceChangeRequest",
                        relatedEntityId: changeReq.Id,
                        fromUserId: CurrentUserId,
                        categoryCode: "mobile_attendance",
                        storeId: storeId);
                }
            }
            catch (Exception ex) { _logger.LogWarning(ex, "Failed to send rejection notification"); }

            return Ok(AppResponse<object>.Success(new { action = "rejected" }));
        }

        // Approve - delete old device + face, create new ones
        try
        {
            // 1. Soft-delete old device
            var oldDevice = await _dbContext.AuthorizedMobileDevices
                .AsTracking()
                .FirstOrDefaultAsync(d => d.Id == changeReq.OldDeviceRecordId && d.Deleted == null);

            if (oldDevice != null)
            {
                oldDevice.Deleted = DateTime.UtcNow;
                oldDevice.DeletedBy = CurrentUserEmail;
            }

            // 2. Soft-delete old face registration
            var oldFace = await _dbContext.MobileFaceRegistrations
                .AsTracking()
                .FirstOrDefaultAsync(f => f.OdooEmployeeId == changeReq.EmployeeId && f.StoreId == storeId && f.Deleted == null);

            if (oldFace != null)
            {
                oldFace.Deleted = DateTime.UtcNow;
                oldFace.DeletedBy = CurrentUserEmail;
            }

            // 3. Upload new face images
            var faceImages = JsonSerializer.Deserialize<List<string>>(changeReq.NewFaceImagesJson) ?? new List<string>();
            var uploadFolder = await GetStoreFolderAsync("uploads/face-registrations");
            var storedImageUrls = new List<string>();

            foreach (var base64Image in faceImages)
            {
                if (string.IsNullOrWhiteSpace(base64Image)) continue;

                var base64Data = base64Image;
                if (base64Data.Contains(","))
                    base64Data = base64Data.Substring(base64Data.IndexOf(",") + 1);

                byte[] imageBytes;
                try { imageBytes = Convert.FromBase64String(base64Data); }
                catch { continue; }

                var ext = (imageBytes.Length >= 2 && imageBytes[0] == 0xFF && imageBytes[1] == 0xD8) ? ".jpg" : ".png";
                var fileName = $"face_{changeReq.EmployeeId}_{Guid.NewGuid():N}{ext}";

                using var stream = new MemoryStream(imageBytes);
                var storedPath = await _fileStorageService.UploadAsync(stream, fileName, uploadFolder);
                storedImageUrls.Add(storedPath);
            }

            // 4. Create new face registration
            var newFace = new MobileFaceRegistration
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                OdooEmployeeId = changeReq.EmployeeId,
                EmployeeName = changeReq.EmployeeName,
                FaceImagesJson = JsonSerializer.Serialize(storedImageUrls),
                IsVerified = true,
                RegisteredAt = DateTime.UtcNow,
                LastVerifiedAt = DateTime.UtcNow,
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            };
            _dbContext.MobileFaceRegistrations.Add(newFace);

            // 5. Create new device (already approved)
            var newDevice = new AuthorizedMobileDevice
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                DeviceId = changeReq.NewDeviceId,
                DeviceName = changeReq.NewDeviceName,
                DeviceModel = changeReq.NewDeviceModel,
                OsVersion = changeReq.NewOsVersion,
                EmployeeId = changeReq.EmployeeId,
                EmployeeName = changeReq.EmployeeName,
                IsAuthorized = true,
                CanUseFaceId = true,
                CanUseGps = true,
                WifiBssid = changeReq.NewWifiBssid,
                AuthorizedAt = DateTime.UtcNow,
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            };
            _dbContext.AuthorizedMobileDevices.Add(newDevice);

            // 6. Update request status
            changeReq.Status = 1;
            changeReq.ApprovedBy = CurrentUserId;
            changeReq.ApprovedAt = DateTime.UtcNow;

            await _dbContext.SaveChangesAsync();

            _logger.LogInformation("Device change request {Id} approved by {User}: old={OldDevice} -> new={NewDevice}",
                id, CurrentUserEmail, changeReq.OldDeviceName, changeReq.NewDeviceName);

            // Notify employee
            try
            {
                var empUserId2 = Guid.TryParse(changeReq.EmployeeId, out var eid2) ? eid2 : (Guid?)null;
                if (empUserId2.HasValue)
                {
                    await _systemNotificationService.CreateAndSendAsync(
                        empUserId2.Value,
                        NotificationType.Success,
                        "Yêu cầu đổi máy được duyệt",
                        $"Thiết bị chấm công đã được chuyển sang \"{changeReq.NewDeviceName}\". Bạn có thể sử dụng ngay.",
                        relatedEntityType: "DeviceChangeRequest",
                        relatedEntityId: changeReq.Id,
                        fromUserId: CurrentUserId,
                        categoryCode: "mobile_attendance",
                        storeId: storeId);
                }
            }
            catch (Exception ex) { _logger.LogWarning(ex, "Failed to send approval notification"); }

            return Ok(AppResponse<object>.Success(new
            {
                action = "approved",
                newDeviceId = newDevice.Id.ToString(),
            }));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error approving device change request {Id}", id);
            return StatusCode(500, AppResponse<object>.Fail("Lỗi khi duyệt yêu cầu đổi máy"));
        }
    }

    // ==================== WIFI CHECK ====================

    [HttpGet("check-wifi")]
    [Authorize]
    public async Task<ActionResult> CheckWifi([FromQuery] string? bssid)
    {
        var storeId = RequiredStoreId;
        var clientIp = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "";
        var forwardedFor = HttpContext.Request.Headers["X-Forwarded-For"].FirstOrDefault();
        if (!string.IsNullOrEmpty(forwardedFor))
            clientIp = forwardedFor.Split(',')[0].Trim();

        // First try with user's StoreId, then fallback to ALL active locations
        // BSSID is a hardware MAC address (globally unique), safe to match across stores
        var locations = await _cache.GetOrCreateAsync("wifi_locations_all", async entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(5);
            entry.Size = 1;
            return await _dbContext.MobileWorkLocations
                .AsNoTracking()
                .Where(l => l.Deleted == null && l.IsActive
                    && (l.WifiSsid != null || l.WifiBssid != null || l.AllowedIpRange != null))
                .ToListAsync();
        }) ?? new List<MobileWorkLocation>();

        _logger.LogInformation("WiFi check: BSSID={Bssid}, ClientIP={ClientIp}, StoreId={StoreId}, Locations={Count}",
            bssid ?? "null", clientIp, storeId, locations.Count);

        // Priority 1: BSSID match (most secure - router MAC address)
        if (!string.IsNullOrEmpty(bssid))
        {
            var normalizedBssid = NormalizeBssidHex(bssid);
            foreach (var loc in locations)
            {
                if (!string.IsNullOrEmpty(loc.WifiBssid))
                {
                    var locBssid = NormalizeBssidHex(loc.WifiBssid);
                    _logger.LogInformation("WiFi BSSID compare: device={DeviceBssid} vs location={LocBssid} ({LocName})",
                        normalizedBssid, locBssid, loc.Name);
                    if (locBssid == normalizedBssid)
                    {
                        return Ok(AppResponse<object>.Success(new
                        {
                            isWifiVerified = true,
                            verifyType = "bssid",
                            locationName = loc.Name,
                            wifiSsid = loc.WifiSsid,
                            wifiBssid = loc.WifiBssid,
                            clientIp = clientIp,
                        }));
                    }
                }
            }
        }

        // Priority 2: IP-based match (fallback for web where BSSID unavailable)
        foreach (var loc in locations)
        {
            if (string.IsNullOrEmpty(loc.AllowedIpRange)) continue;

            var allowedIps = loc.AllowedIpRange.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (allowedIps.Any(ip => ip.Equals(clientIp, StringComparison.OrdinalIgnoreCase)))
            {
                return Ok(AppResponse<object>.Success(new
                {
                    isWifiVerified = true,
                    verifyType = "ip",
                    locationName = loc.Name,
                    wifiSsid = loc.WifiSsid,
                    clientIp = clientIp,
                }));
            }
        }

        return Ok(AppResponse<object>.Success(new
        {
            isWifiVerified = false,
            clientIp = clientIp,
            receivedBssid = bssid,
            locationsChecked = locations.Count,
            userStoreId = storeId.ToString(),
            message = "Không tìm thấy WiFi văn phòng phù hợp. Hãy kết nối WiFi công ty để chấm công.",
        }));
    }

    // ==================== PUNCH / ATTENDANCE ====================

    [HttpPost("punch")]
    [Authorize]
    [RequestSizeLimit(10_000_000)]
    public async Task<ActionResult> SubmitPunch([FromBody] MobilePunchRequest request)
    {
        _logger.LogWarning("📌 PUNCH START: EmpId={EmpId}, DeviceId={DeviceId}, PunchType={PunchType}, PunchTime={PunchTime}, FaceScore={FaceScore}, Lat={Lat}, Lng={Lng}",
            request.EmployeeId, request.DeviceId, request.PunchType, request.PunchTime, request.FaceMatchScore, request.Latitude, request.Longitude);

        try
        {
        if (string.IsNullOrWhiteSpace(request.EmployeeId))
        {
            _logger.LogWarning("❌ PUNCH REJECT: empty EmployeeId");
            return BadRequest(AppResponse<object>.Fail("Thiếu thông tin nhân viên"));
        }

        var storeId = RequiredStoreId;
        _logger.LogWarning("📌 PUNCH STEP 1: StoreId={StoreId}", storeId);

        // Check device is registered and authorized
        if (string.IsNullOrWhiteSpace(request.DeviceId))
        {
            _logger.LogWarning("❌ PUNCH REJECT: empty DeviceId");
            return BadRequest(AppResponse<object>.Fail("Thiếu thông tin thiết bị. Vui lòng đăng ký thiết bị trước."));
        }

        var registeredDevice = await _dbContext.AuthorizedMobileDevices
            .AsNoTracking()
            .FirstOrDefaultAsync(d => d.DeviceId == request.DeviceId && d.StoreId == storeId && d.Deleted == null);

        if (registeredDevice == null)
        {
            _logger.LogWarning("❌ PUNCH REJECT: device not found DeviceId={DeviceId}", request.DeviceId);
            return BadRequest(AppResponse<object>.Fail("Thiết bị chưa được đăng ký. Vui lòng đăng ký thiết bị trước khi chấm công."));
        }

        _logger.LogWarning("📌 PUNCH STEP 2: Device found, IsAuthorized={IsAuth}, AllowOutside={AllowOutside}", registeredDevice.IsAuthorized, registeredDevice.AllowOutsideCheckIn);

        if (!registeredDevice.IsAuthorized)
        {
            _logger.LogWarning("❌ PUNCH REJECT: device not authorized");
            return BadRequest(AppResponse<object>.Fail("Thiết bị chưa được duyệt hoặc đã bị thu hồi. Vui lòng liên hệ quản lý."));
        }

        // Load settings to check rules (cached)
        var settings = await _cache.GetOrCreateAsync($"mobile_settings_{storeId}", async entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(5);
            entry.Size = 1;
            return await _dbContext.MobileAttendanceSettings
                .AsNoTracking()
                .FirstOrDefaultAsync(s => s.StoreId == storeId && s.Deleted == null);
        });

        var maxPunches = settings?.MaxPunchesPerDay ?? 4;

        // Check max punches per day - FIX: use local time since DB stores local time
        var today = DateTime.Now.Date;
        var todayCount = await _dbContext.MobileAttendanceRecords
            .CountAsync(r => r.OdooEmployeeId == request.EmployeeId
                && r.StoreId == storeId
                && r.PunchTime.Date == today
                && r.Deleted == null);

        _logger.LogWarning("📌 PUNCH STEP 3: maxPunches={Max}, todayCount={Count}, today={Today}", maxPunches, todayCount, today);

        if (todayCount >= maxPunches)
        {
            _logger.LogWarning("❌ PUNCH REJECT: max punches reached {Count}/{Max}", todayCount, maxPunches);
            return BadRequest(AppResponse<object>.Fail($"Đã đạt tối đa {maxPunches} lần chấm công trong ngày"));
        }

        // Check minimum interval between punches (duplicate detection)
        var minInterval = settings?.MinPunchIntervalMinutes ?? 5;
        if (minInterval > 0)
        {
            var lastPunch = await _dbContext.MobileAttendanceRecords
                .Where(r => r.OdooEmployeeId == request.EmployeeId
                    && r.StoreId == storeId
                    && r.Deleted == null)
                .OrderByDescending(r => r.PunchTime)
                .Select(r => r.PunchTime)
                .FirstOrDefaultAsync();

            _logger.LogWarning("📌 PUNCH STEP 4: lastPunch={LastPunch}, minInterval={Min}", lastPunch, minInterval);

            if (lastPunch != default)
            {
                var elapsed = DateTime.Now - lastPunch;
                _logger.LogWarning("📌 PUNCH STEP 4b: elapsed={Elapsed}min", elapsed.TotalMinutes);
                if (elapsed.TotalMinutes < minInterval)
                {
                    var remaining = minInterval - (int)elapsed.TotalMinutes;
                    _logger.LogWarning("❌ PUNCH REJECT: min interval not met elapsed={Elapsed}min < {Min}min", elapsed.TotalMinutes, minInterval);
                    return BadRequest(AppResponse<object>.Fail(
                        $"Chấm công trùng! Khoảng cách tối thiểu giữa 2 lần chấm là {minInterval} phút. Vui lòng chờ thêm {remaining} phút."));
                }
            }
        }

        // Find nearest work location
        string? locationName = null;
        double? distance = null;
        bool isInRange = false;
        bool isWifiVerified = false;
        string? matchedWifiSsid = null;

        var locations = await _cache.GetOrCreateAsync($"work_locations_{storeId}", async entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(5);
            entry.Size = 1;
            return await _dbContext.MobileWorkLocations
                .AsNoTracking()
                .Where(l => l.StoreId == storeId && l.Deleted == null && l.IsActive)
                .ToListAsync();
        }) ?? new List<MobileWorkLocation>();

        if (request.Latitude.HasValue && request.Longitude.HasValue)
        {
            foreach (var loc in locations)
            {
                var d = CalculateDistance(request.Latitude.Value, request.Longitude.Value, loc.Latitude, loc.Longitude);
                if (distance == null || d < distance)
                {
                    distance = d;
                    locationName = loc.Name;
                    isInRange = d <= loc.Radius;
                }
            }
        }

        // WiFi verification: check BSSID match or IP match (server-side only, never trust client claims)
        {
            var clientIp = HttpContext.Connection.RemoteIpAddress?.ToString() ?? "";
            var forwardedFor = HttpContext.Request.Headers["X-Forwarded-For"].FirstOrDefault();
            if (!string.IsNullOrEmpty(forwardedFor))
                clientIp = forwardedFor.Split(',')[0].Trim();

            var normalizedReqBssid = !string.IsNullOrEmpty(request.WifiBssid) ? NormalizeBssidHex(request.WifiBssid) : null;
            foreach (var loc in locations)
            {
                // Priority 1: BSSID match (most secure - router MAC address)
                if (!string.IsNullOrEmpty(normalizedReqBssid) && !string.IsNullOrEmpty(loc.WifiBssid))
                {
                    var locBssid = NormalizeBssidHex(loc.WifiBssid);
                    if (locBssid == normalizedReqBssid)
                    {
                        isWifiVerified = true;
                        matchedWifiSsid = loc.WifiSsid ?? loc.Name;
                        if (locationName == null) locationName = loc.Name;
                        break;
                    }
                }
                
                // Priority 2: IP match (fallback for web where BSSID unavailable)
                if (!string.IsNullOrEmpty(loc.AllowedIpRange))
                {
                    var allowedIps = loc.AllowedIpRange.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
                    if (allowedIps.Any(ip => ip.Equals(clientIp, StringComparison.OrdinalIgnoreCase)))
                    {
                        isWifiVerified = true;
                        matchedWifiSsid = loc.WifiSsid ?? loc.Name;
                        if (locationName == null) locationName = loc.Name;
                        break;
                    }
                }
            }
        }

        // Check if device is allowed to check in outside company (reuse registeredDevice from above)
        bool allowOutside = registeredDevice.AllowOutsideCheckIn;

        // Server-side verification mode enforcement
        var enableFace = settings?.EnableFaceId ?? true;
        var enableGps = settings?.EnableGps ?? true;
        var enableWifi = settings?.EnableWifi ?? false;
        var verificationMode = settings?.VerificationMode ?? "all";

        // Server-side face verification: check employee has registration + face image was submitted
        bool isFaceVerified = false;
        double? serverFaceScore = null;
        string? faceImageStoredPath = null;

        if (enableFace)
        {
            // Verify employee has face registration
            var faceReg = await _dbContext.MobileFaceRegistrations
                .AsNoTracking()
                .FirstOrDefaultAsync(f => f.OdooEmployeeId == request.EmployeeId && f.StoreId == storeId && f.Deleted == null);

            var hasRegistration = faceReg != null;
            if (hasRegistration)
            {
                var regImages = JsonSerializer.Deserialize<List<string>>(faceReg!.FaceImagesJson ?? "[]") ?? new List<string>();
                hasRegistration = regImages.Count > 0;
            }

            // Try to save submitted face image for audit
            if (!string.IsNullOrWhiteSpace(request.FaceImageUrl) && request.FaceImageUrl.Length > 100)
            {
                // FaceImageUrl contains base64 image data from client
                try
                {
                    var base64Data = request.FaceImageUrl;
                    if (base64Data.Contains(","))
                        base64Data = base64Data.Substring(base64Data.IndexOf(",") + 1);

                    var imageBytes = Convert.FromBase64String(base64Data);
                    if (imageBytes.Length >= 4 &&
                        ((imageBytes[0] == 0xFF && imageBytes[1] == 0xD8 && imageBytes[2] == 0xFF) ||
                         (imageBytes[0] == 0x89 && imageBytes[1] == 0x50 && imageBytes[2] == 0x4E && imageBytes[3] == 0x47)))
                    {
                        var ext = (imageBytes[0] == 0xFF) ? ".jpg" : ".png";
                        var fileName = $"punch_{request.EmployeeId}_{DateTime.UtcNow:yyyyMMdd_HHmmss}_{Guid.NewGuid():N}{ext}";
                        var uploadFolder = await GetStoreFolderAsync("uploads/face-verifications");
                        using var ms = new MemoryStream(imageBytes);
                        faceImageStoredPath = await _fileStorageService.UploadAsync(ms, fileName, uploadFolder);
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to save punch face image for {EmployeeId}", request.EmployeeId);
                }
            }

            // Server-side scoring: has registration + submitted photo → face comparison
            // If client already did on-device comparison (like a face attendance machine),
            // trust the client score to reduce server load. Otherwise, do server-side comparison.
            var clientDidLocalComparison = request.FaceMatchScore.HasValue && request.FaceMatchScore.Value > 0;

            if (hasRegistration && faceImageStoredPath != null && !clientDidLocalComparison)
            {
                // Client did NOT do local comparison → server must verify
                var regImages = JsonSerializer.Deserialize<List<string>>(faceReg!.FaceImagesJson ?? "[]") ?? new List<string>();
                var (compScore, compDetails) = await _faceComparisonService.CompareAsync(faceImageStoredPath, regImages);
                serverFaceScore = compScore;
                isFaceVerified = serverFaceScore >= (settings?.MinFaceMatchScore ?? 55.0);
                _logger.LogInformation(
                    "Server face comparison for employee {EmpId}: score={Score}, verified={Verified}, details={Details}",
                    request.EmployeeId, serverFaceScore, isFaceVerified, compDetails);
            }
            else if (hasRegistration && clientDidLocalComparison)
            {
                // Client did on-device comparison (like face attendance machine) → trust client score
                serverFaceScore = request.FaceMatchScore!.Value;
                isFaceVerified = serverFaceScore >= (settings?.MinFaceMatchScore ?? 55.0);
                _logger.LogInformation(
                    "On-device face comparison for employee {EmpId}: clientScore={Score}, verified={Verified} (trusted from device)",
                    request.EmployeeId, serverFaceScore, isFaceVerified);
            }
            else if (hasRegistration)
            {
                // Has registration but no photo submitted
                serverFaceScore = 0.0;
                isFaceVerified = false;
                _logger.LogWarning("Face verification failed for employee {EmpId}: has registration but no photo submitted", request.EmployeeId);
            }
            else
            {
                // No face registration → face verification fails
                serverFaceScore = 0.0;
                isFaceVerified = false;
                _logger.LogWarning("Face verification failed for employee {EmpId}: no face registration found", request.EmployeeId);
            }
        }

        // BLOCK: If Face ID is enabled and employee has no face registration, reject the punch
        if (enableFace && !isFaceVerified && serverFaceScore == null)
        {
            _logger.LogWarning("❌ PUNCH REJECT: no face registration");
            return BadRequest(AppResponse<object>.Fail("Nhân viên chưa đăng ký khuôn mặt. Vui lòng đăng ký Face ID trước khi chấm công."));
        }

        _logger.LogWarning("📌 PUNCH STEP 5: enableFace={Face}, enableGps={Gps}, enableWifi={Wifi}, mode={Mode}, isFaceVerified={FV}, isInRange={IR}, isWifiVerified={WV}, allowOutside={AO}",
            enableFace, enableGps, enableWifi, verificationMode, isFaceVerified, isInRange, isWifiVerified, allowOutside);

        if (!allowOutside)
        {
            // Count which enabled methods passed
            var enabledMethods = new List<string>();
            var passedMethods = new List<string>();

            if (enableFace) { enabledMethods.Add("face"); if (isFaceVerified) passedMethods.Add("face"); }
            if (enableGps) { enabledMethods.Add("gps"); if (isInRange) passedMethods.Add("gps"); }
            if (enableWifi) { enabledMethods.Add("wifi"); if (isWifiVerified) passedMethods.Add("wifi"); }

            _logger.LogWarning("📌 PUNCH STEP 5b: enabled=[{Enabled}], passed=[{Passed}]", string.Join(",", enabledMethods), string.Join(",", passedMethods));

            if (enabledMethods.Count > 0)
            {
                if (verificationMode == "all" && passedMethods.Count < enabledMethods.Count)
                {
                    var failedMethods = enabledMethods.Except(passedMethods).Select(m => m switch
                    {
                        "face" => "Khuôn mặt",
                        "gps" => "GPS",
                        "wifi" => "WiFi",
                        _ => m
                    });
                    _logger.LogWarning("❌ PUNCH REJECT: verification mode=all, failed: {Failed}", string.Join(", ", failedMethods));
                    return BadRequest(AppResponse<object>.Fail($"Chưa đạt tất cả điều kiện xác thực: {string.Join(", ", failedMethods)}"));
                }
                else if (verificationMode == "any" && passedMethods.Count == 0)
                {
                    _logger.LogWarning("❌ PUNCH REJECT: verification mode=any, all failed");
                    return BadRequest(AppResponse<object>.Fail("Cần ít nhất 1 phương thức xác thực (Khuôn mặt / GPS / WiFi) đạt yêu cầu"));
                }
            }
        }

        // Determine status
        var autoApprove = settings?.AutoApproveInRange ?? true;

        var status = ((isInRange || isWifiVerified || allowOutside) && autoApprove) ? "auto_approved" : "pending";

        // Resolve employee name from device registration if not provided
        var employeeName = request.EmployeeName;
        if (string.IsNullOrWhiteSpace(employeeName))
        {
            employeeName = registeredDevice.EmployeeName;
        }

        var record = new MobileAttendanceRecord
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            OdooEmployeeId = request.EmployeeId,
            EmployeeName = employeeName ?? "",
            PunchTime = request.PunchTime ?? DateTime.Now,
            PunchType = request.PunchType,
            Latitude = request.Latitude,
            Longitude = request.Longitude,
            LocationName = locationName,
            DistanceFromLocation = distance,
            FaceImageUrl = faceImageStoredPath ?? request.FaceImageUrl,
            FaceMatchScore = serverFaceScore ?? request.FaceMatchScore,
            WifiSsid = matchedWifiSsid ?? request.WifiSsid,
            WifiBssid = isWifiVerified ? request.WifiBssid : null,
            WifiIpAddress = isWifiVerified ? (HttpContext.Connection.RemoteIpAddress?.ToString()) : null,
            VerifyMethod = DetermineVerifyMethod(request),
            Status = status,
            DeviceId = request.DeviceId,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };

        _logger.LogWarning("📌 PUNCH STEP 6: About to save record Id={Id}, PunchTime={PT}, Status={Status}", record.Id, record.PunchTime, record.Status);

        _dbContext.MobileAttendanceRecords.Add(record);
        await _dbContext.SaveChangesAsync();

        _logger.LogWarning("✅ PUNCH SAVED: Id={Id}", record.Id);

        // Đồng bộ vào bảng chấm công chính nếu auto_approved
        if (status == "auto_approved")
        {
            await SyncMobileRecordToAttendanceLog(record);
            _logger.LogWarning("✅ PUNCH SYNCED to AttendanceLog");
        }

        _logger.LogWarning("✅ PUNCH SUCCESS: {EmployeeId}, type={PunchType}, status={Status}",
            request.EmployeeId, request.PunchType, status);

        // Gửi thông báo cho quản lý nếu bản ghi cần duyệt
        if (status == "pending")
        {
            try
            {
                var managerIds = await _dbContext.Users
                    .Where(u => u.StoreId == storeId && u.IsActive
                        && (u.Role == "Manager" || u.Role == "Admin"))
                    .Select(u => u.Id)
                    .ToListAsync();

                var punchLabel = record.PunchType == 0 ? "vào" : "ra";
                foreach (var managerId in managerIds)
                {
                    await _systemNotificationService.CreateAndSendAsync(
                        managerId,
                        NotificationType.ApprovalRequired,
                        "Chấm công Mobile chờ duyệt",
                        $"{employeeName ?? record.OdooEmployeeId} chấm công {punchLabel} lúc {record.PunchTime:HH:mm dd/MM/yyyy} - cần duyệt",
                        relatedEntityType: "MobileAttendance",
                        relatedEntityId: record.Id,
                        fromUserId: CurrentUserId,
                        categoryCode: "mobile_attendance",
                        storeId: storeId);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to send notification for mobile attendance {RecordId}", record.Id);
            }
        }

        return Ok(AppResponse<object>.Success(new
        {
            id = record.Id.ToString(),
            odooEmployeeId = record.OdooEmployeeId,
            punchTime = record.PunchTime,
            punchType = record.PunchType,
            locationName = record.LocationName,
            distanceFromLocation = record.DistanceFromLocation,
            faceMatchScore = record.FaceMatchScore,
            verifyMethod = record.VerifyMethod,
            status = record.Status,
        }));
    }
    catch (Exception ex)
    {
        _logger.LogError(ex, "❌ PUNCH ERROR: EmpId={EmpId}", request.EmployeeId);
        return StatusCode(500, AppResponse<object>.Fail($"Lỗi server: {ex.Message}"));
    }
    }

    [HttpGet("history")]
    [Authorize]
    public async Task<ActionResult> GetHistory(
        [FromQuery] string? employeeId,
        [FromQuery] DateTime? fromDate,
        [FromQuery] DateTime? toDate,
        [FromQuery] string? status)
    {
        _logger.LogWarning("📋 HISTORY: empId={EmpId}, from={From}, to={To}, status={Status}",
            employeeId, fromDate, toDate, status);
        var storeId = RequiredStoreId;
        var query = _dbContext.MobileAttendanceRecords
            .AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null);

        if (!string.IsNullOrEmpty(employeeId))
            query = query.Where(r => r.OdooEmployeeId == employeeId);
        if (fromDate.HasValue)
            query = query.Where(r => r.PunchTime >= fromDate.Value);
        if (toDate.HasValue)
            query = query.Where(r => r.PunchTime <= toDate.Value);
        if (!string.IsNullOrEmpty(status))
            query = query.Where(r => r.Status == status);

        var records = await query
            .OrderByDescending(r => r.PunchTime)
            .Take(200)
            .Select(r => new
            {
                id = r.Id.ToString(),
                odooEmployeeId = r.OdooEmployeeId,
                employeeName = r.EmployeeName,
                punchTime = r.PunchTime,
                punchType = r.PunchType,
                latitude = r.Latitude,
                longitude = r.Longitude,
                locationName = r.LocationName,
                distanceFromLocation = r.DistanceFromLocation,
                faceImageUrl = r.FaceImageUrl,
                faceMatchScore = r.FaceMatchScore,
                verifyMethod = r.VerifyMethod,
                status = r.Status,
                approvedBy = r.ApprovedBy,
                approvedAt = r.ApprovedAt,
                rejectReason = r.RejectReason,
                deviceId = r.DeviceId,
                deviceName = r.DeviceName,
                note = r.Note,
            })
            .ToListAsync();

        _logger.LogWarning("📋 HISTORY RESULT: {Count} records found", records.Count);

        return Ok(AppResponse<object>.Success(records));
    }

    [HttpGet("pending")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> GetPending()
    {
        var storeId = RequiredStoreId;
        var records = await _dbContext.MobileAttendanceRecords
            .AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Status == "pending" && r.Deleted == null)
            .OrderByDescending(r => r.PunchTime)
            .Select(r => new
            {
                id = r.Id.ToString(),
                odooEmployeeId = r.OdooEmployeeId,
                employeeName = r.EmployeeName,
                punchTime = r.PunchTime,
                punchType = r.PunchType,
                latitude = r.Latitude,
                longitude = r.Longitude,
                locationName = r.LocationName,
                distanceFromLocation = r.DistanceFromLocation,
                faceMatchScore = r.FaceMatchScore,
                verifyMethod = r.VerifyMethod,
                status = r.Status,
            })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(records));
    }

    [HttpPost("approve/{recordId}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> ApproveRecord(Guid recordId, [FromBody] ApproveRequest request)
    {
        var storeId = RequiredStoreId;
        var record = await _dbContext.MobileAttendanceRecords
            .AsTracking()
            .FirstOrDefaultAsync(r => r.Id == recordId && r.StoreId == storeId && r.Deleted == null);

        if (record == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy bản ghi"));

        if (record.Status != "pending")
            return BadRequest(AppResponse<object>.Fail("Bản ghi này đã được xử lý"));

        record.Status = request.Approved ? "approved" : "rejected";
        record.ApprovedBy = CurrentUserEmail;
        record.ApprovedAt = DateTime.UtcNow;
        record.RejectReason = request.RejectionReason;
        record.UpdatedAt = DateTime.UtcNow;
        record.UpdatedBy = CurrentUserEmail;

        await _dbContext.SaveChangesAsync();

        // Đồng bộ vào bảng chấm công chính khi được duyệt
        if (request.Approved)
        {
            await SyncMobileRecordToAttendanceLog(record);
        }

        // Gửi thông báo cho nhân viên về kết quả duyệt
        try
        {
            if (Guid.TryParse(record.OdooEmployeeId, out var empUserId))
            {
                var punchLabel = record.PunchType == 0 ? "vào" : "ra";
                var timeStr = record.PunchTime.ToString("HH:mm dd/MM/yyyy");
                if (request.Approved)
                {
                    await _systemNotificationService.CreateAndSendAsync(
                        empUserId,
                        NotificationType.Success,
                        "Chấm công Mobile đã được duyệt",
                        $"Chấm công {punchLabel} lúc {timeStr} đã được duyệt bởi {CurrentUserEmail}",
                        relatedEntityType: "MobileAttendance",
                        relatedEntityId: record.Id,
                        fromUserId: CurrentUserId,
                        categoryCode: "mobile_attendance",
                        storeId: storeId);
                }
                else
                {
                    var reason = !string.IsNullOrEmpty(request.RejectionReason)
                        ? $". Lý do: {request.RejectionReason}" : "";
                    await _systemNotificationService.CreateAndSendAsync(
                        empUserId,
                        NotificationType.Warning,
                        "Chấm công Mobile bị từ chối",
                        $"Chấm công {punchLabel} lúc {timeStr} đã bị từ chối bởi {CurrentUserEmail}{reason}",
                        relatedEntityType: "MobileAttendance",
                        relatedEntityId: record.Id,
                        fromUserId: CurrentUserId,
                        categoryCode: "mobile_attendance",
                        storeId: storeId);
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to send approval notification for mobile attendance {RecordId}", recordId);
        }

        _logger.LogInformation("Mobile attendance record {RecordId} {Action}", recordId, record.Status);
        return Ok(AppResponse<object>.Success(new { status = record.Status }));
    }

    // ==================== FACE VERIFY ====================

    [HttpPost("verify-face")]
    [Authorize]
    [RequestSizeLimit(10_000_000)]
    public async Task<ActionResult> VerifyFace([FromBody] VerifyFaceRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.EmployeeId))
            return BadRequest(AppResponse<object>.Fail("Thiếu thông tin nhân viên"));

        var storeId = RequiredStoreId;
        var reg = await _dbContext.MobileFaceRegistrations
            .AsTracking()
            .FirstOrDefaultAsync(f => f.OdooEmployeeId == request.EmployeeId && f.StoreId == storeId && f.Deleted == null);

        if (reg == null)
            return BadRequest(AppResponse<object>.Fail("Nhân viên chưa đăng ký khuôn mặt"));

        var images = JsonSerializer.Deserialize<List<string>>(reg.FaceImagesJson ?? "[]") ?? new List<string>();
        if (images.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Nhân viên chưa có ảnh khuôn mặt đăng ký"));

        // Validate submitted face image
        string? verifyImagePath = null;
        if (!string.IsNullOrWhiteSpace(request.FaceImage))
        {
            try
            {
                var base64Data = request.FaceImage;
                if (base64Data.Contains(","))
                    base64Data = base64Data.Substring(base64Data.IndexOf(",") + 1);

                var imageBytes = Convert.FromBase64String(base64Data);
                if (imageBytes.Length >= 4 &&
                    ((imageBytes[0] == 0xFF && imageBytes[1] == 0xD8 && imageBytes[2] == 0xFF) ||
                     (imageBytes[0] == 0x89 && imageBytes[1] == 0x50 && imageBytes[2] == 0x4E && imageBytes[3] == 0x47)))
                {
                    var ext = (imageBytes[0] == 0xFF) ? ".jpg" : ".png";
                    var fileName = $"verify_{request.EmployeeId}_{Guid.NewGuid():N}{ext}";
                    var uploadFolder = await GetStoreFolderAsync("uploads/face-verifications");
                    using var stream = new MemoryStream(imageBytes);
                    verifyImagePath = await _fileStorageService.UploadAsync(stream, fileName, uploadFolder);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to process verify face image for {EmployeeId}", request.EmployeeId);
            }
        }

        // Server-side scoring: real face comparison
        var hasRegisteredImages = images.Count > 0;
        var hasSubmittedPhoto = verifyImagePath != null;
        double matchScore;
        bool verified;

        if (hasRegisteredImages && hasSubmittedPhoto)
        {
            // Real face comparison
            var (compScore, compDetails) = await _faceComparisonService.CompareAsync(verifyImagePath!, images);
            matchScore = compScore;
            verified = matchScore >= 80.0;
            _logger.LogInformation("Face verify for {EmpId}: score={Score}, verified={Verified}, details={Details}",
                request.EmployeeId, matchScore, verified, compDetails);
        }
        else if (hasRegisteredImages && !hasSubmittedPhoto)
        {
            // Has registered but no photo submitted - lower score
            matchScore = 50.0;
            verified = false;
        }
        else
        {
            matchScore = 0.0;
            verified = false;
        }

        reg.LastVerifiedAt = DateTime.UtcNow;
        await _dbContext.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(new
        {
            verified,
            matchScore,
            registeredImages = images.Count,
            verifyImageUrl = verifyImagePath,
            message = verified ? "Đã xác thực khuôn mặt" : "Không thể xác thực khuôn mặt",
        }));
    }

    // ==================== HELPERS ====================

    /// <summary>
    /// Normalize image paths: strip absolute URL prefix, keep only relative path.
    /// Handles legacy data stored as http://localhost:7070/uploads/... or similar.
    /// </summary>
    private static string NormalizeImagePath(string path)
    {
        if (string.IsNullOrEmpty(path)) return path;

        // Already relative
        if (path.StartsWith("/")) return path;

        // Strip absolute URL prefix (e.g., http://localhost:7070/uploads/... → /uploads/...)
        if (path.StartsWith("http://") || path.StartsWith("https://"))
        {
            try
            {
                var uri = new Uri(path);
                return uri.AbsolutePath; // e.g., /uploads/face-registrations/store_X/guid.jpg
            }
            catch
            {
                return path;
            }
        }

        return path;
    }

    private static double CalculateDistance(double lat1, double lon1, double lat2, double lon2)
    {
        const double R = 6371000; // Earth radius in meters
        var dLat = (lat2 - lat1) * Math.PI / 180;
        var dLon = (lon2 - lon1) * Math.PI / 180;
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(lat1 * Math.PI / 180) * Math.Cos(lat2 * Math.PI / 180) *
                Math.Sin(dLon / 2) * Math.Sin(dLon / 2);
        var c = 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
        return R * c;
    }

    private static string DetermineVerifyMethod(MobilePunchRequest request)
    {
        var hasFace = request.FaceMatchScore.HasValue && request.FaceMatchScore > 0;
        var hasGps = request.Latitude.HasValue && request.Longitude.HasValue;
        var hasWifi = !string.IsNullOrEmpty(request.WifiSsid);

        var parts = new List<string>();
        if (hasFace) parts.Add("face");
        if (hasGps) parts.Add("gps");
        if (hasWifi) parts.Add("wifi");

        return parts.Count > 0 ? string.Join("_", parts) : "manual";
    }

    /// <summary>
    /// Đồng bộ bản ghi chấm công mobile đã duyệt vào bảng AttendanceLogs chính
    /// để hiển thị trong báo cáo chấm công tổng hợp.
    /// </summary>
    private async Task SyncMobileRecordToAttendanceLog(MobileAttendanceRecord record)
    {
        try
        {
            // Kiểm tra đã sync chưa
            var alreadySynced = await _dbContext.AttendanceLogs
                .AnyAsync(a => a.MobileAttendanceRecordId == record.Id);
            if (alreadySynced) return;

            // Tìm hoặc tạo virtual device "MOBILE" cho store
            var mobileDevice = await _dbContext.Devices
                .FirstOrDefaultAsync(d => d.SerialNumber == "MOBILE" && d.StoreId == record.StoreId);

            if (mobileDevice == null)
            {
                var deviceInfo = new DeviceInfo
                {
                    Id = Guid.NewGuid(),
                    DeviceId = Guid.NewGuid(),
                    FirmwareVersion = "virtual",
                };

                mobileDevice = new Device
                {
                    Id = deviceInfo.DeviceId,
                    SerialNumber = "MOBILE",
                    DeviceName = "Chấm công Mobile",
                    DeviceType = DeviceType.Attendance,
                    DeviceStatus = "Online",
                    ManagerId = CurrentUserId,
                    StoreId = record.StoreId,
                    IsClaimed = true,
                    ClaimedAt = DateTime.UtcNow,
                    DeviceInfoId = deviceInfo.Id,
                    IsActive = true,
                    CreatedBy = "system",
                };

                deviceInfo.DeviceId = mobileDevice.Id;
                _dbContext.DeviceInfos.Add(deviceInfo);
                _dbContext.Devices.Add(mobileDevice);
                await _dbContext.SaveChangesAsync();
            }

            // Tìm DeviceUser qua Employee.ApplicationUserId == OdooEmployeeId
            Guid? deviceUserId = null;
            string pin = record.OdooEmployeeId;

            if (Guid.TryParse(record.OdooEmployeeId, out var appUserId))
            {
                var employee = await _dbContext.Employees
                    .Include(e => e.DeviceUsers)
                    .FirstOrDefaultAsync(e => e.ApplicationUserId == appUserId && e.StoreId == record.StoreId);

                if (employee != null)
                {
                    pin = employee.EmployeeCode ?? record.OdooEmployeeId;

                    // Tìm DeviceUser liên kết với employee trên device MOBILE
                    var deviceUser = employee.DeviceUsers
                        .FirstOrDefault(du => du.DeviceId == mobileDevice.Id);

                    if (deviceUser == null)
                    {
                        // Tìm DeviceUser bất kỳ của employee
                        deviceUser = employee.DeviceUsers.FirstOrDefault();
                    }

                    if (deviceUser == null)
                    {
                        // Tạo DeviceUser mới trên device MOBILE
                        deviceUser = new DeviceUser
                        {
                            Id = Guid.NewGuid(),
                            Pin = pin.Length > 20 ? pin[..20] : pin,
                            Name = record.EmployeeName,
                            DeviceId = mobileDevice.Id,
                            EmployeeId = employee.Id,
                            IsActive = true,
                            CreatedBy = "system",
                        };
                        _dbContext.DeviceUsers.Add(deviceUser);
                        await _dbContext.SaveChangesAsync();
                    }

                    deviceUserId = deviceUser.Id;
                    pin = deviceUser.Pin;
                }
            }

            // Truncate pin to fit varchar(20) constraint
            if (pin.Length > 20) pin = pin[..20];

            // Map VerifyMethod → VerifyModes
            var verifyMode = record.VerifyMethod switch
            {
                "face" or "face_gps" or "face_wifi" or "face_gps_wifi" => VerifyModes.Face,
                _ => VerifyModes.Manual,
            };

            var attendance = new Attendance
            {
                Id = Guid.NewGuid(),
                DeviceId = mobileDevice.Id,
                EmployeeId = deviceUserId,
                PIN = pin,
                VerifyMode = verifyMode,
                AttendanceState = record.PunchType == 0 ? AttendanceStates.CheckIn : AttendanceStates.CheckOut,
                AttendanceTime = record.PunchTime,
                Note = $"Mobile: {record.VerifyMethod}",
                MobileAttendanceRecordId = record.Id,
            };

            _dbContext.AttendanceLogs.Add(attendance);
            await _dbContext.SaveChangesAsync();

            // Send real-time notification for mobile attendance
            try
            {
                var deviceUser = deviceUserId.HasValue
                    ? await _dbContext.DeviceUsers
                        .Include(du => du.Employee)
                        .FirstOrDefaultAsync(du => du.Id == deviceUserId.Value)
                    : null;
                await _attendanceNotificationService.NotifyNewAttendanceAsync(attendance, mobileDevice, deviceUser, record.EmployeeName);
            }
            catch (Exception notifEx)
            {
                _logger.LogError(notifEx, "Failed to send mobile attendance notification for {AttendanceId}", attendance.Id);
            }

            _logger.LogInformation("Synced mobile record {MobileRecordId} → AttendanceLog {AttendanceId}",
                record.Id, attendance.Id);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to sync mobile record {MobileRecordId} to AttendanceLogs", record.Id);
        }
    }
}

// ==================== REQUEST DTOs ====================

public class FaceRegistrationRequest
{
    public string EmployeeId { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public List<string> FaceImages { get; set; } = new();
}

public class UpdateMobileSettingsRequest
{
    public bool? EnableFaceId { get; set; }
    public bool? EnableGps { get; set; }
    public bool? EnableWifi { get; set; }
    public string? VerificationMode { get; set; }
    public bool? EnableLivenessDetection { get; set; }
    public double? GpsRadiusMeters { get; set; }
    public double? MinFaceMatchScore { get; set; }
    public bool? AutoApproveInRange { get; set; }
    public bool? AllowManualApproval { get; set; }
    public int? MaxPunchesPerDay { get; set; }
    public bool? RequirePhotoProof { get; set; }
    public int? MaxPhotosPerRegistration { get; set; }
    public int? MinPunchIntervalMinutes { get; set; }
}

public class WorkLocationRequest
{
    public string Name { get; set; } = string.Empty;
    public string? Address { get; set; }
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public double Radius { get; set; } = 100;
    public bool AutoApproveInRange { get; set; } = true;
    public string? WifiSsid { get; set; }
    public string? WifiBssid { get; set; }
    public string? AllowedIpRange { get; set; }
}

public class AuthorizeDeviceRequest
{
    public string DeviceId { get; set; } = string.Empty;
    public string DeviceName { get; set; } = string.Empty;
    public string? DeviceModel { get; set; }
    public string? OsVersion { get; set; }
    public string? EmployeeId { get; set; }
    public string? EmployeeName { get; set; }
    public bool CanUseFaceId { get; set; } = true;
    public bool CanUseGps { get; set; } = true;
    public bool AllowOutsideCheckIn { get; set; } = false;
}

public class MobilePunchRequest
{
    public string EmployeeId { get; set; } = string.Empty;
    public string? EmployeeName { get; set; }
    public int PunchType { get; set; }
    public double? Latitude { get; set; }
    public double? Longitude { get; set; }
    public string? FaceImageUrl { get; set; }
    public double? FaceMatchScore { get; set; }
    public string? DeviceId { get; set; }
    public DateTime? PunchTime { get; set; }
    public string? WifiSsid { get; set; }
    public string? WifiBssid { get; set; }
}

public class ApproveRequest
{
    public bool Approved { get; set; }
    public string? RejectionReason { get; set; }
}

public class VerifyFaceRequest
{
    public string EmployeeId { get; set; } = string.Empty;
    public string FaceImage { get; set; } = string.Empty;
}

public class RegisterDeviceWithFaceRequest
{
    public string DeviceId { get; set; } = string.Empty;
    public string DeviceName { get; set; } = string.Empty;
    public string? DeviceModel { get; set; }
    public string? OsVersion { get; set; }
    public string EmployeeId { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public List<string> FaceImages { get; set; } = new();
    public string? WifiBssid { get; set; }
}

public class DeviceChangeRequestDto
{
    public string EmployeeId { get; set; } = string.Empty;
    public string EmployeeName { get; set; } = string.Empty;
    public string NewDeviceId { get; set; } = string.Empty;
    public string NewDeviceName { get; set; } = string.Empty;
    public string? NewDeviceModel { get; set; }
    public string? NewOsVersion { get; set; }
    public string? NewWifiBssid { get; set; }
    public List<string> FaceImages { get; set; } = new();
    public string? Reason { get; set; }
}

internal class FaceRegistrationInfo
{
    public List<string> FaceImages { get; set; } = new();
    public bool IsVerified { get; set; }
    public DateTime? RegisteredAt { get; set; }
}
