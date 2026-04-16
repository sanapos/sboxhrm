using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using System.Text.Json;
using System.Text.Json.Serialization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

[ApiController]
[Route("api/field-checkin")]
[Authorize]
public class FieldCheckInController : AuthenticatedControllerBase
{
    private readonly ZKTecoDbContext _dbContext;
    private readonly ILogger<FieldCheckInController> _logger;
    private readonly IFileStorageService _fileStorageService;
    private readonly IMemoryCache _cache;

    public FieldCheckInController(
        ZKTecoDbContext dbContext,
        ILogger<FieldCheckInController> logger,
        IFileStorageService fileStorageService,
        IMemoryCache cache)
    {
        _dbContext = dbContext;
        _logger = logger;
        _fileStorageService = fileStorageService;
        _cache = cache;
    }

    private async Task<string> GetStoreFolderAsync(string subfolder)
    {
        var store = await _dbContext.Stores.FindAsync(RequiredStoreId);
        var slug = store?.Code ?? RequiredStoreId.ToString();
        return $"{slug}/{subfolder}";
    }

    // ==================== FIELD LOCATIONS (ÄIá»‚M BÃN KHÃCH HÃ€NG) ====================

    /// <summary>
    /// Láº¥y danh sÃ¡ch táº¥t cáº£ Ä‘iá»ƒm bÃ¡n (nhÃ¢n viÃªn + manager Ä‘á»u xem Ä‘Æ°á»£c)
    /// </summary>
    [HttpGet("locations")]
    public async Task<ActionResult> GetLocations([FromQuery] string? search, [FromQuery] string? category)
    {
        var storeId = RequiredStoreId;
        var query = _dbContext.FieldLocations
            .AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null);

        if (!string.IsNullOrEmpty(search))
            query = query.Where(l => l.Name.Contains(search) || (l.Address != null && l.Address.Contains(search))
                || (l.ContactName != null && l.ContactName.Contains(search)));

        if (!string.IsNullOrEmpty(category))
            query = query.Where(l => l.Category == category);

        var locations = await query
            .OrderByDescending(l => l.CreatedAt)
            .Take(500)
            .Select(l => new
            {
                id = l.Id.ToString(),
                name = l.Name,
                address = l.Address,
                contactName = l.ContactName,
                contactPhone = l.ContactPhone,
                contactEmail = l.ContactEmail,
                note = l.Note,
                latitude = l.Latitude,
                longitude = l.Longitude,
                radius = l.Radius,
                photos = l.PhotoUrlsJson,
                category = l.Category,
                registeredBy = l.RegisteredByEmployeeName,
                isApproved = l.IsApproved,
                isActive = l.IsActive,
                createdAt = l.CreatedAt,
            })
            .ToListAsync();

        var result = locations.Select(l => new
        {
            l.id, l.name, l.address, l.contactName, l.contactPhone, l.contactEmail,
            l.note, l.latitude, l.longitude, l.radius,
            photos = SafeDeserializePhotos(l.photos),
            l.category, l.registeredBy, l.isApproved, l.isActive, l.createdAt,
        }).ToList();

        return Ok(AppResponse<object>.Success(result));
    }

    /// <summary>
    /// NhÃ¢n viÃªn Ä‘Äƒng kÃ½ Ä‘iá»ƒm bÃ¡n má»›i (tá»± chá»¥p áº£nh, nháº­p thÃ´ng tin liÃªn há»‡)
    /// </summary>
    [HttpPost("locations")]
    [RequestSizeLimit(20_000_000)]
    public async Task<ActionResult> RegisterLocation([FromBody] RegisterFieldLocationRequest request)
    {
        var storeId = RequiredStoreId;

        // Upload photos
        var photoUrls = new List<string>();
        if (request.Photos != null && request.Photos.Count > 0)
        {
            var uploadFolder = await GetStoreFolderAsync("uploads/field-locations");
            foreach (var base64Image in request.Photos.Take(5))
            {
                if (string.IsNullOrWhiteSpace(base64Image)) continue;
                var base64Data = base64Image;
                if (base64Data.Contains(","))
                    base64Data = base64Data.Substring(base64Data.IndexOf(",") + 1);
                try
                {
                    var imageBytes = Convert.FromBase64String(base64Data);
                    var fileName = $"fl_{DateTime.UtcNow:yyyyMMdd_HHmmss}_{Guid.NewGuid():N}.jpg";
                    using var stream = new MemoryStream(imageBytes);
                    var storedPath = await _fileStorageService.UploadAsync(stream, fileName, uploadFolder);
                    photoUrls.Add(_fileStorageService.GetFileUrl(storedPath));
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to upload field location photo");
                }
            }
        }

        var location = new FieldLocation
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            Name = request.Name,
            Address = request.Address,
            ContactName = request.ContactName,
            ContactPhone = request.ContactPhone,
            ContactEmail = request.ContactEmail,
            Note = request.Note,
            Latitude = request.Latitude,
            Longitude = request.Longitude,
            Radius = request.Radius > 0 ? (int)request.Radius : 200,
            PhotoUrlsJson = JsonSerializer.Serialize(photoUrls),
            Category = request.Category,
            RegisteredByEmployeeId = CurrentUserId.ToString(),
            RegisteredByEmployeeName = CurrentUserEmail ?? "",
            IsApproved = true,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };

        _dbContext.FieldLocations.Add(location);
        await _dbContext.SaveChangesAsync();

        _logger.LogInformation("Field location registered: {Name} by {User}", location.Name, CurrentUserEmail);

        return Ok(AppResponse<object>.Success(new
        {
            id = location.Id.ToString(),
            name = location.Name,
            address = location.Address,
            latitude = location.Latitude,
            longitude = location.Longitude,
            radius = location.Radius,
            photos = photoUrls,
        }));
    }

    /// <summary>
    /// Cáº­p nháº­t thÃ´ng tin Ä‘iá»ƒm bÃ¡n
    /// </summary>
    [HttpPut("locations/{id}")]
    [RequestSizeLimit(20_000_000)]
    public async Task<ActionResult> UpdateLocation(Guid id, [FromBody] UpdateFieldLocationRequest request)
    {
        var storeId = RequiredStoreId;
        var location = await _dbContext.FieldLocations
            .AsTracking()
            .FirstOrDefaultAsync(l => l.Id == id && l.StoreId == storeId && l.Deleted == null);

        if (location == null)
            return NotFound(AppResponse<object>.Fail("KhÃ´ng tÃ¬m tháº¥y Ä‘iá»ƒm bÃ¡n"));

        if (!string.IsNullOrEmpty(request.Name)) location.Name = request.Name;
        if (request.Address != null) location.Address = request.Address;
        if (request.ContactName != null) location.ContactName = request.ContactName;
        if (request.ContactPhone != null) location.ContactPhone = request.ContactPhone;
        if (request.ContactEmail != null) location.ContactEmail = request.ContactEmail;
        if (request.Note != null) location.Note = request.Note;
        if (request.Latitude.HasValue) location.Latitude = request.Latitude.Value;
        if (request.Longitude.HasValue) location.Longitude = request.Longitude.Value;
        if (request.Radius.HasValue) location.Radius = (int)request.Radius.Value;
        if (request.Category != null) location.Category = request.Category;

        // Handle new photos
        if (request.Photos != null && request.Photos.Count > 0)
        {
            var existingPhotos = SafeDeserializePhotos(location.PhotoUrlsJson);
            var uploadFolder = await GetStoreFolderAsync("uploads/field-locations");
            foreach (var base64Image in request.Photos.Take(5))
            {
                if (string.IsNullOrWhiteSpace(base64Image)) continue;
                if (base64Image.StartsWith("http")) { existingPhotos.Add(base64Image); continue; }
                var base64Data = base64Image;
                if (base64Data.Contains(","))
                    base64Data = base64Data.Substring(base64Data.IndexOf(",") + 1);
                try
                {
                    var imageBytes = Convert.FromBase64String(base64Data);
                    var fileName = $"fl_{DateTime.UtcNow:yyyyMMdd_HHmmss}_{Guid.NewGuid():N}.jpg";
                    using var stream2 = new MemoryStream(imageBytes);
                    var storedPath2 = await _fileStorageService.UploadAsync(stream2, fileName, uploadFolder);
                    existingPhotos.Add(_fileStorageService.GetFileUrl(storedPath2));
                }
                catch { }
            }
            location.PhotoUrlsJson = JsonSerializer.Serialize(existingPhotos);
        }

        location.UpdatedAt = DateTime.UtcNow;
        location.UpdatedBy = CurrentUserEmail;
        await _dbContext.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(new { updated = true }));
    }

    /// <summary>
    /// XÃ³a Ä‘iá»ƒm bÃ¡n (Manager)
    /// </summary>
    [HttpDelete("locations/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> DeleteLocation(Guid id)
    {
        var storeId = RequiredStoreId;
        var location = await _dbContext.FieldLocations
            .AsTracking()
            .FirstOrDefaultAsync(l => l.Id == id && l.StoreId == storeId && l.Deleted == null);

        if (location == null)
            return NotFound(AppResponse<object>.Fail("KhÃ´ng tÃ¬m tháº¥y Ä‘iá»ƒm bÃ¡n"));

        location.Deleted = DateTime.UtcNow;
        location.DeletedBy = CurrentUserEmail;
        await _dbContext.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(new { deleted = true }));
    }

    // ==================== ASSIGNMENT (GIAO ÄIá»‚M) ====================

    /// <summary>
    /// Láº¥y danh sÃ¡ch giao Ä‘iá»ƒm cho nhÃ¢n viÃªn (Manager)
    /// </summary>
    [HttpGet("assignments")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> GetAssignments([FromQuery] string? employeeId)
    {
        var storeId = RequiredStoreId;
        var query = _dbContext.FieldLocationAssignments
            .AsNoTracking()
            .Where(a => a.StoreId == storeId && a.Deleted == null);

        if (!string.IsNullOrEmpty(employeeId))
            query = query.Where(a => a.EmployeeId == employeeId);

        var assignments = await query
            .OrderBy(a => a.EmployeeId)
            .ThenBy(a => a.DayOfWeek)
            .ThenBy(a => a.SortOrder)
            .Select(a => new
            {
                id = a.Id.ToString(),
                employeeId = a.EmployeeId,
                employeeName = a.EmployeeName,
                locationId = a.LocationId.ToString(),
                location = a.Location == null ? null : new
                {
                    name = a.Location.Name,
                    address = a.Location.Address,
                    latitude = a.Location.Latitude,
                    longitude = a.Location.Longitude,
                    radius = a.Location.Radius,
                },
                dayOfWeek = a.DayOfWeek,
                sortOrder = a.SortOrder,
                note = a.Note,
                isActive = a.IsActive,
            })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(assignments));
    }

    /// <summary>
    /// NhÃ¢n viÃªn xem danh sÃ¡ch Ä‘iá»ƒm Ä‘Æ°á»£c giao cho mÃ¬nh (hÃ´m nay hoáº·c theo thá»©)
    /// </summary>
    [HttpGet("my-assignments")]
    public async Task<ActionResult> GetMyAssignments([FromQuery] int? dayOfWeek)
    {
        var storeId = RequiredStoreId;
        var employeeId = CurrentUserId.ToString();
        var dow = dayOfWeek ?? (int)DateTime.UtcNow.DayOfWeek;
        // .NET: Sunday=0, need Mon=1..Sun=7
        if (dow == 0) dow = 7;

        var assignments = await _dbContext.FieldLocationAssignments
            .AsNoTracking()
            .Where(a => a.StoreId == storeId
                && a.EmployeeId == employeeId
                && a.Deleted == null
                && a.IsActive
                && (a.DayOfWeek == null || a.DayOfWeek == dow))
            .OrderBy(a => a.SortOrder)
            .Select(a => new
            {
                id = a.Id.ToString(),
                locationId = a.LocationId.ToString(),
                location = a.Location == null ? null : new
                {
                    name = a.Location.Name,
                    address = a.Location.Address,
                    latitude = a.Location.Latitude,
                    longitude = a.Location.Longitude,
                    radius = a.Location.Radius,
                },
                dayOfWeek = a.DayOfWeek,
                sortOrder = a.SortOrder,
                note = a.Note,
            })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(assignments));
    }

    /// <summary>
    /// Giao Ä‘iá»ƒm cho nhÃ¢n viÃªn (Manager)
    /// </summary>
    [HttpPost("assignments")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> CreateAssignment([FromBody] CreateAssignmentRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.EmployeeId))
            return BadRequest(AppResponse<object>.Fail("Thiáº¿u thÃ´ng tin nhÃ¢n viÃªn"));

        var storeId = RequiredStoreId;

        // Verify location exists
        var location = await _dbContext.FieldLocations
            .AsNoTracking()
            .FirstOrDefaultAsync(l => l.Id == request.LocationId && l.StoreId == storeId && l.Deleted == null);
        if (location == null)
            return NotFound(AppResponse<object>.Fail("KhÃ´ng tÃ¬m tháº¥y Ä‘iá»ƒm bÃ¡n"));

        // Check duplicate
        var exists = await _dbContext.FieldLocationAssignments
            .AnyAsync(a => a.StoreId == storeId
                && a.EmployeeId == request.EmployeeId
                && a.LocationId == request.LocationId
                && a.DayOfWeek == request.DayOfWeek
                && a.Deleted == null);
        if (exists)
            return BadRequest(AppResponse<object>.Fail("NhÃ¢n viÃªn Ä‘Ã£ Ä‘Æ°á»£c giao Ä‘iá»ƒm nÃ y vÃ o thá»© Ä‘Ã£ chá»n"));

        var assignment = new FieldLocationAssignment
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            EmployeeId = request.EmployeeId,
            EmployeeName = request.EmployeeName ?? "",
            LocationId = request.LocationId,
            DayOfWeek = request.DayOfWeek,
            SortOrder = request.SortOrder > 0 ? request.SortOrder : 1,
            Note = request.Note,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };

        _dbContext.FieldLocationAssignments.Add(assignment);
        await _dbContext.SaveChangesAsync();

        _logger.LogInformation("Field location assigned: Employee {EmployeeId} -> Location {LocationId}", request.EmployeeId, request.LocationId);
        return Ok(AppResponse<object>.Success(new
        {
            id = assignment.Id.ToString(),
            employeeId = assignment.EmployeeId,
            employeeName = assignment.EmployeeName,
            locationId = assignment.LocationId.ToString(),
            locationName = location.Name,
            dayOfWeek = assignment.DayOfWeek,
            sortOrder = assignment.SortOrder,
        }));
    }

    /// <summary>
    /// Giao Ä‘iá»ƒm hÃ ng loáº¡t (Manager)
    /// </summary>
    [HttpPost("assignments/bulk")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> BulkAssign([FromBody] BulkAssignRequest request)
    {
        if (request.Items == null || request.Items.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Danh sÃ¡ch giao Ä‘iá»ƒm trá»‘ng"));

        var storeId = RequiredStoreId;
        var created = 0;

        foreach (var item in request.Items)
        {
            var exists = await _dbContext.FieldLocationAssignments
                .AnyAsync(a => a.StoreId == storeId
                    && a.EmployeeId == item.EmployeeId
                    && a.LocationId == item.LocationId
                    && a.DayOfWeek == item.DayOfWeek
                    && a.Deleted == null);
            if (exists) continue;

            _dbContext.FieldLocationAssignments.Add(new FieldLocationAssignment
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                EmployeeId = item.EmployeeId,
                EmployeeName = item.EmployeeName ?? "",
                LocationId = item.LocationId,
                DayOfWeek = item.DayOfWeek,
                SortOrder = item.SortOrder > 0 ? item.SortOrder : 1,
                Note = item.Note,
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            });
            created++;
        }

        await _dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { created }));
    }

    [HttpPut("assignments/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> UpdateAssignment(Guid id, [FromBody] UpdateAssignmentRequest request)
    {
        var storeId = RequiredStoreId;
        var assignment = await _dbContext.FieldLocationAssignments
            .AsTracking()
            .FirstOrDefaultAsync(a => a.Id == id && a.StoreId == storeId && a.Deleted == null);

        if (assignment == null)
            return NotFound(AppResponse<object>.Fail("KhÃ´ng tÃ¬m tháº¥y giao Ä‘iá»ƒm"));

        if (request.DayOfWeek.HasValue) assignment.DayOfWeek = request.DayOfWeek;
        if (request.SortOrder.HasValue) assignment.SortOrder = request.SortOrder.Value;
        if (request.Note != null) assignment.Note = request.Note;
        if (request.IsActive.HasValue) assignment.IsActive = request.IsActive.Value;

        assignment.UpdatedAt = DateTime.UtcNow;
        assignment.UpdatedBy = CurrentUserEmail;
        await _dbContext.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(new { updated = true }));
    }

    [HttpDelete("assignments/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> DeleteAssignment(Guid id)
    {
        var storeId = RequiredStoreId;
        var assignment = await _dbContext.FieldLocationAssignments
            .AsTracking()
            .FirstOrDefaultAsync(a => a.Id == id && a.StoreId == storeId && a.Deleted == null);

        if (assignment == null)
            return NotFound(AppResponse<object>.Fail("KhÃ´ng tÃ¬m tháº¥y giao Ä‘iá»ƒm"));

        assignment.Deleted = DateTime.UtcNow;
        assignment.DeletedBy = CurrentUserEmail;
        await _dbContext.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(new { deleted = true }));
    }

    // ==================== VISIT REPORTS (CHECK-IN / CHECK-OUT) ====================

    /// <summary>
    /// NhÃ¢n viÃªn check-in táº¡i Ä‘iá»ƒm bÃ¡n
    /// </summary>
    [HttpPost("checkin")]
    public async Task<ActionResult> CheckIn([FromBody] CheckInRequest request)
    {
        var storeId = RequiredStoreId;
        var employeeId = CurrentUserId.ToString();

        // Verify location
        var location = await _dbContext.FieldLocations
            .AsNoTracking()
            .FirstOrDefaultAsync(l => l.Id == request.LocationId && l.StoreId == storeId && l.Deleted == null);
        if (location == null)
            return NotFound(AppResponse<object>.Fail("KhÃ´ng tÃ¬m tháº¥y Ä‘iá»ƒm bÃ¡n"));

        // Check if already checked in at this location today (not yet checked out)
        var today = DateTime.UtcNow.Date;
        var existing = await _dbContext.VisitReports
            .FirstOrDefaultAsync(v => v.StoreId == storeId
                && v.EmployeeId == employeeId
                && v.LocationId == request.LocationId
                && v.VisitDate.Date == today
                && v.Status == "checked_in"
                && v.Deleted == null);

        if (existing != null)
            return BadRequest(AppResponse<object>.Fail($"Báº¡n Ä‘Ã£ check-in táº¡i '{location.Name}' lÃºc {existing.CheckInTime:HH:mm} vÃ  chÆ°a check-out. Vui lÃ²ng check-out trÆ°á»›c."));

        // Calculate distance from location & enforce radius
        double? distance = null;
        bool outsideRadius = false;
        if (request.Latitude.HasValue && request.Longitude.HasValue)
        {
            distance = CalculateDistance(
                request.Latitude.Value, request.Longitude.Value,
                location.Latitude, location.Longitude);
            var maxRadius = location.Radius > 0 ? location.Radius * 3 : 600; // 3x radius = hard limit
            if (distance > maxRadius)
                return BadRequest(AppResponse<object>.Fail($"Báº¡n á»Ÿ quÃ¡ xa Ä‘iá»ƒm bÃ¡n ({distance:F0}m > {maxRadius}m). Vui lÃ²ng di chuyá»ƒn Ä‘áº¿n gáº§n hÆ¡n."));
            outsideRadius = distance > (location.Radius > 0 ? location.Radius : 200);
        }

        // Link to today's active journey
        Guid? journeyId = null;
        var activeJourney = await _dbContext.JourneyTrackings
            .AsNoTracking()
            .FirstOrDefaultAsync(j => j.StoreId == storeId
                && j.EmployeeId == employeeId
                && j.JourneyDate.Date == today
                && j.Status == "in_progress"
                && j.Deleted == null);
        if (activeJourney != null) journeyId = activeJourney.Id;

        var now = DateTime.UtcNow;
        var report = new VisitReport
        {
            Id = Guid.NewGuid(),
            StoreId = storeId,
            EmployeeId = employeeId,
            EmployeeName = request.EmployeeName ?? "",
            LocationId = request.LocationId,
            LocationName = location.Name,
            VisitDate = now,
            CheckInTime = now,
            CheckInLatitude = request.Latitude,
            CheckInLongitude = request.Longitude,
            CheckInDistance = distance,
            ReportNote = request.Note,
            Status = "checked_in",
            JourneyId = journeyId,
            OutsideRadius = outsideRadius,
            IsActive = true,
            CreatedBy = CurrentUserEmail,
        };

        _dbContext.VisitReports.Add(report);
        await _dbContext.SaveChangesAsync();

        _logger.LogInformation("Field check-in: Employee {EmployeeId} at {LocationName}, distance={Distance}m",
            employeeId, location.Name, distance);

        return Ok(AppResponse<object>.Success(new
        {
            id = report.Id.ToString(),
            locationName = report.LocationName,
            checkInTime = report.CheckInTime,
            checkInDistance = report.CheckInDistance,
            outsideRadius = report.OutsideRadius,
            journeyId = journeyId?.ToString(),
            status = report.Status,
        }));
    }

    /// <summary>
    /// NhÃ¢n viÃªn check-out khá»i Ä‘iá»ƒm bÃ¡n + upload áº£nh + ghi chÃº
    /// </summary>
    [HttpPost("checkout/{visitId}")]
    [RequestSizeLimit(20_000_000)]
    public async Task<ActionResult> CheckOut(Guid visitId, [FromBody] CheckOutRequest request)
    {
        var storeId = RequiredStoreId;
        var employeeId = CurrentUserId.ToString();

        var report = await _dbContext.VisitReports
            .AsTracking()
            .FirstOrDefaultAsync(v => v.Id == visitId
                && v.StoreId == storeId
                && v.EmployeeId == employeeId
                && v.Deleted == null);

        if (report == null)
            return NotFound(AppResponse<object>.Fail("KhÃ´ng tÃ¬m tháº¥y báº£n ghi check-in"));

        if (report.Status != "checked_in")
            return BadRequest(AppResponse<object>.Fail("Báº£n ghi nÃ y Ä‘Ã£ check-out hoáº·c khÃ´ng á»Ÿ tráº¡ng thÃ¡i check-in"));

        // Calculate distance
        double? distance = null;
        if (request.Latitude.HasValue && request.Longitude.HasValue && report.LocationId != Guid.Empty)
        {
            var location = await _dbContext.FieldLocations
                .AsNoTracking()
                .FirstOrDefaultAsync(l => l.Id == report.LocationId);
            if (location != null)
            {
                distance = CalculateDistance(
                    request.Latitude.Value, request.Longitude.Value,
                    location.Latitude, location.Longitude);
            }
        }

        // Upload photos
        var photoUrls = new List<string>();
        if (request.Photos != null && request.Photos.Count > 0)
        {
            var uploadFolder = await GetStoreFolderAsync("uploads/visit-reports");
            foreach (var base64Image in request.Photos.Take(5))
            {
                if (string.IsNullOrWhiteSpace(base64Image)) continue;
                var base64Data = base64Image;
                if (base64Data.Contains(","))
                    base64Data = base64Data.Substring(base64Data.IndexOf(",") + 1);

                byte[] imageBytes;
                try { imageBytes = Convert.FromBase64String(base64Data); }
                catch { continue; }

                if (imageBytes.Length < 4) continue;
                var ext = (imageBytes[0] == 0xFF) ? ".jpg" : ".png";
                var fileName = $"visit_{visitId}_{Guid.NewGuid():N}{ext}";

                using var stream = new MemoryStream(imageBytes);
                var storedPath = await _fileStorageService.UploadAsync(stream, fileName, uploadFolder);
                photoUrls.Add(_fileStorageService.GetFileUrl(storedPath));
            }
        }

        // Merge with existing photos
        var existingPhotos = SafeDeserializePhotos(report.PhotoUrlsJson);
        existingPhotos.AddRange(photoUrls);

        var now = DateTime.UtcNow;
        report.CheckOutTime = now;
        report.CheckOutLatitude = request.Latitude;
        report.CheckOutLongitude = request.Longitude;
        report.CheckOutDistance = distance;
        report.PhotoUrlsJson = JsonSerializer.Serialize(existingPhotos);
        report.ReportNote = request.Note ?? report.ReportNote;
        report.ReportDataJson = request.ReportDataJson;
        report.Status = "checked_out";
        report.UpdatedAt = now;
        report.UpdatedBy = CurrentUserEmail;

        // Calculate time spent
        if (report.CheckInTime.HasValue)
        {
            report.TimeSpentMinutes = (int)(now - report.CheckInTime.Value).TotalMinutes;
        }

        await _dbContext.SaveChangesAsync();

        _logger.LogInformation("Field check-out: Employee {EmployeeId} at {LocationName}, spent {Minutes}min",
            employeeId, report.LocationName, report.TimeSpentMinutes);

        return Ok(AppResponse<object>.Success(new
        {
            id = report.Id.ToString(),
            locationName = report.LocationName,
            checkInTime = report.CheckInTime,
            checkOutTime = report.CheckOutTime,
            timeSpentMinutes = report.TimeSpentMinutes,
            photos = existingPhotos,
            status = report.Status,
        }));
    }

    /// <summary>
    /// NhÃ¢n viÃªn xem lá»‹ch sá»­ check-in cá»§a mÃ¬nh
    /// </summary>
    [HttpGet("my-visits")]
    public async Task<ActionResult> GetMyVisits(
        [FromQuery] DateTime? fromDate,
        [FromQuery] DateTime? toDate,
        [FromQuery] string? status)
    {
        var storeId = RequiredStoreId;
        var employeeId = CurrentUserId.ToString();

        var query = _dbContext.VisitReports
            .AsNoTracking()
            .Where(v => v.StoreId == storeId && v.EmployeeId == employeeId && v.Deleted == null);

        if (fromDate.HasValue)
            query = query.Where(v => v.VisitDate >= fromDate.Value);
        if (toDate.HasValue)
            query = query.Where(v => v.VisitDate <= toDate.Value.AddDays(1));
        if (!string.IsNullOrEmpty(status))
            query = query.Where(v => v.Status == status);

        var visits = await query
            .OrderByDescending(v => v.VisitDate)
            .Take(100)
            .Select(v => new
            {
                id = v.Id.ToString(),
                locationId = v.LocationId.ToString(),
                locationName = v.LocationName,
                visitDate = v.VisitDate,
                checkInTime = v.CheckInTime,
                checkOutTime = v.CheckOutTime,
                timeSpentMinutes = v.TimeSpentMinutes,
                checkInDistance = v.CheckInDistance,
                checkOutDistance = v.CheckOutDistance,
                photos = v.PhotoUrlsJson,
                reportNote = v.ReportNote,
                status = v.Status,
                reviewedBy = v.ReviewedBy,
                reviewNote = v.ReviewNote,
            })
            .ToListAsync();

        // Parse photos JSON
        var result = visits.Select(v => new
        {
            v.id,
            v.locationId,
            v.locationName,
            v.visitDate,
            v.checkInTime,
            v.checkOutTime,
            v.timeSpentMinutes,
            v.checkInDistance,
            v.checkOutDistance,
            photos = SafeDeserializePhotos(v.photos),
            v.reportNote,
            v.status,
            v.reviewedBy,
            v.reviewNote,
        }).ToList();

        return Ok(AppResponse<object>.Success(result));
    }

    /// <summary>
    /// NhÃ¢n viÃªn xem tráº¡ng thÃ¡i check-in hÃ´m nay
    /// </summary>
    [HttpGet("today")]
    public async Task<ActionResult> GetTodayVisits()
    {
        var storeId = RequiredStoreId;
        var employeeId = CurrentUserId.ToString();
        var today = DateTime.UtcNow.Date;

        var visits = await _dbContext.VisitReports
            .AsNoTracking()
            .Where(v => v.StoreId == storeId
                && v.EmployeeId == employeeId
                && v.VisitDate.Date == today
                && v.Deleted == null)
            .OrderBy(v => v.CheckInTime)
            .Select(v => new
            {
                id = v.Id.ToString(),
                locationId = v.LocationId.ToString(),
                locationName = v.LocationName,
                checkInTime = v.CheckInTime,
                checkOutTime = v.CheckOutTime,
                timeSpentMinutes = v.TimeSpentMinutes,
                checkInDistance = v.CheckInDistance,
                status = v.Status,
                reportNote = v.ReportNote,
                photos = v.PhotoUrlsJson,
            })
            .ToListAsync();

        var result = visits.Select(v => new
        {
            v.id,
            v.locationId,
            v.locationName,
            v.checkInTime,
            v.checkOutTime,
            v.timeSpentMinutes,
            v.checkInDistance,
            v.status,
            v.reportNote,
            photos = SafeDeserializePhotos(v.photos),
        }).ToList();

        return Ok(AppResponse<object>.Success(result));
    }

    // ==================== MANAGER ENDPOINTS ====================

    /// <summary>
    /// Manager xem táº¥t cáº£ bÃ¡o cÃ¡o check-in  
    /// </summary>
    [HttpGet("reports")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> GetReports(
        [FromQuery] string? employeeId,
        [FromQuery] Guid? locationId,
        [FromQuery] DateTime? fromDate,
        [FromQuery] DateTime? toDate,
        [FromQuery] string? status)
    {
        var storeId = RequiredStoreId;
        var query = _dbContext.VisitReports
            .AsNoTracking()
            .Where(v => v.StoreId == storeId && v.Deleted == null);

        if (!string.IsNullOrEmpty(employeeId))
            query = query.Where(v => v.EmployeeId == employeeId);
        if (locationId.HasValue)
            query = query.Where(v => v.LocationId == locationId.Value);
        if (fromDate.HasValue)
            query = query.Where(v => v.VisitDate >= fromDate.Value);
        if (toDate.HasValue)
            query = query.Where(v => v.VisitDate <= toDate.Value.AddDays(1));
        if (!string.IsNullOrEmpty(status))
            query = query.Where(v => v.Status == status);

        var visits = await query
            .OrderByDescending(v => v.VisitDate)
            .Take(200)
            .Select(v => new
            {
                id = v.Id.ToString(),
                employeeId = v.EmployeeId,
                employeeName = v.EmployeeName,
                locationId = v.LocationId.ToString(),
                locationName = v.LocationName,
                visitDate = v.VisitDate,
                checkInTime = v.CheckInTime,
                checkOutTime = v.CheckOutTime,
                timeSpentMinutes = v.TimeSpentMinutes,
                checkInDistance = v.CheckInDistance,
                checkOutDistance = v.CheckOutDistance,
                checkInLatitude = v.CheckInLatitude,
                checkInLongitude = v.CheckInLongitude,
                photos = v.PhotoUrlsJson,
                reportNote = v.ReportNote,
                reportData = v.ReportDataJson,
                status = v.Status,
                reviewedBy = v.ReviewedBy,
                reviewedAt = v.ReviewedAt,
                reviewNote = v.ReviewNote,
            })
            .ToListAsync();

        var result = visits.Select(v => new
        {
            v.id,
            v.employeeId,
            v.employeeName,
            v.locationId,
            v.locationName,
            v.visitDate,
            v.checkInTime,
            v.checkOutTime,
            v.timeSpentMinutes,
            v.checkInDistance,
            v.checkOutDistance,
            v.checkInLatitude,
            v.checkInLongitude,
            photos = SafeDeserializePhotos(v.photos),
            v.reportNote,
            reportData = v.reportData != null ? JsonSerializer.Deserialize<object>(v.reportData) : null,
            v.status,
            v.reviewedBy,
            v.reviewedAt,
            v.reviewNote,
        }).ToList();

        return Ok(AppResponse<object>.Success(result));
    }

    /// <summary>
    /// Manager review bÃ¡o cÃ¡o check-in
    /// </summary>
    [HttpPost("review/{visitId}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> ReviewVisit(Guid visitId, [FromBody] ReviewVisitRequest request)
    {
        var storeId = RequiredStoreId;
        var report = await _dbContext.VisitReports
            .AsTracking()
            .FirstOrDefaultAsync(v => v.Id == visitId && v.StoreId == storeId && v.Deleted == null);

        if (report == null)
            return NotFound(AppResponse<object>.Fail("KhÃ´ng tÃ¬m tháº¥y báº£n ghi"));

        report.Status = "reviewed";
        report.ReviewedBy = CurrentUserEmail;
        report.ReviewedAt = DateTime.UtcNow;
        report.ReviewNote = request.ReviewNote;
        report.UpdatedAt = DateTime.UtcNow;
        report.UpdatedBy = CurrentUserEmail;

        await _dbContext.SaveChangesAsync();

        _logger.LogInformation("Visit report {VisitId} reviewed by {User}", visitId, CurrentUserEmail);
        return Ok(AppResponse<object>.Success(new { status = report.Status }));
    }

    /// <summary>
    /// Manager xem thá»‘ng kÃª check-in theo thá»i gian
    /// </summary>
    [HttpGet("summary")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> GetSummary(
        [FromQuery] DateTime? fromDate,
        [FromQuery] DateTime? toDate)
    {
        var storeId = RequiredStoreId;
        var from = fromDate ?? DateTime.UtcNow.Date.AddDays(-30);
        var to = toDate ?? DateTime.UtcNow.Date.AddDays(1);

        var visits = await _dbContext.VisitReports
            .AsNoTracking()
            .Where(v => v.StoreId == storeId
                && v.VisitDate >= from
                && v.VisitDate <= to
                && v.Deleted == null)
            .ToListAsync();

        // Group by employee
        var byEmployee = visits
            .GroupBy(v => new { v.EmployeeId, v.EmployeeName })
            .Select(g => new
            {
                employeeId = g.Key.EmployeeId,
                employeeName = g.Key.EmployeeName,
                totalVisits = g.Count(),
                checkedOutVisits = g.Count(v => v.CheckOutTime.HasValue),
                totalMinutes = g.Where(v => v.TimeSpentMinutes.HasValue).Sum(v => v.TimeSpentMinutes!.Value),
                avgMinutesPerVisit = g.Where(v => v.TimeSpentMinutes.HasValue).Any()
                    ? (int)g.Where(v => v.TimeSpentMinutes.HasValue).Average(v => v.TimeSpentMinutes!.Value)
                    : 0,
                uniqueLocations = g.Select(v => v.LocationId).Distinct().Count(),
            })
            .OrderByDescending(e => e.totalVisits)
            .ToList();

        // Group by location
        var byLocation = visits
            .GroupBy(v => new { v.LocationId, v.LocationName })
            .Select(g => new
            {
                locationId = g.Key.LocationId.ToString(),
                locationName = g.Key.LocationName,
                totalVisits = g.Count(),
                uniqueEmployees = g.Select(v => v.EmployeeId).Distinct().Count(),
                avgMinutesPerVisit = g.Where(v => v.TimeSpentMinutes.HasValue).Any()
                    ? (int)g.Where(v => v.TimeSpentMinutes.HasValue).Average(v => v.TimeSpentMinutes!.Value)
                    : 0,
            })
            .OrderByDescending(l => l.totalVisits)
            .ToList();

        return Ok(AppResponse<object>.Success(new
        {
            period = new { from, to },
            totalVisits = visits.Count,
            totalCheckedOut = visits.Count(v => v.CheckOutTime.HasValue),
            byEmployee,
            byLocation,
        }));
    }

    // ==================== JOURNEY TRACKING ====================

    /// <summary>
    /// NhÃ¢n viÃªn báº¯t Ä‘áº§u hÃ nh trÃ¬nh trong ngÃ y
    /// </summary>
    [HttpPost("journey/start")]
    public async Task<ActionResult> StartJourney()
    {
        var storeId = RequiredStoreId;
        var employeeId = CurrentUserId.ToString();
        var today = DateTime.UtcNow.Date;

        // Check if journey already exists for today
        var existing = await _dbContext.JourneyTrackings
            .FirstOrDefaultAsync(j => j.StoreId == storeId
                && j.EmployeeId == employeeId
                && j.JourneyDate.Date == today
                && j.Deleted == null);

        if (existing != null && existing.Status == "in_progress")
            return BadRequest(AppResponse<object>.Fail("HÃ nh trÃ¬nh hÃ´m nay Ä‘ang diá»…n ra"));

        // Count assigned locations for today
        var dow = (int)DateTime.UtcNow.DayOfWeek;
        if (dow == 0) dow = 7;
        var assignedCount = await _dbContext.FieldLocationAssignments
            .CountAsync(a => a.StoreId == storeId
                && a.EmployeeId == employeeId
                && a.Deleted == null
                && a.IsActive
                && (a.DayOfWeek == null || a.DayOfWeek == dow));

        // Also count field locations registered by employee
        var fieldLocationCount = await _dbContext.FieldLocations
            .CountAsync(l => l.StoreId == storeId
                && l.RegisteredByEmployeeId == employeeId
                && l.Deleted == null
                && l.IsActive);
        var totalLocations = assignedCount + fieldLocationCount;

        var now = DateTime.UtcNow;
        JourneyTracking journey;

        if (existing != null)
        {
            // Resume/restart journey (including completed)
            existing.Status = "in_progress";
            existing.StartTime = now;
            existing.EndTime = null;
            existing.AssignedCount = totalLocations;
            existing.UpdatedAt = now;
            existing.UpdatedBy = CurrentUserEmail;
            journey = existing;
        }
        else
        {
            journey = new JourneyTracking
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                EmployeeId = employeeId,
                EmployeeName = CurrentUserEmail ?? "",
                JourneyDate = today,
                StartTime = now,
                Status = "in_progress",
                AssignedCount = totalLocations,
                RoutePointsJson = "[]",
                IsActive = true,
                CreatedBy = CurrentUserEmail,
            };
            _dbContext.JourneyTrackings.Add(journey);
        }

        await _dbContext.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(new
        {
            id = journey.Id.ToString(),
            journeyDate = journey.JourneyDate,
            startTime = journey.StartTime,
            status = journey.Status,
            assignedCount = journey.AssignedCount,
            checkedInCount = journey.CheckedInCount,
        }));
    }

    /// <summary>
    /// NhÃ¢n viÃªn gá»­i batch GPS points (gá»i má»—i 30s-60s tá»« client)
    /// </summary>
    [HttpPost("journey/track")]
    public async Task<ActionResult> TrackPoints([FromBody] TrackPointsRequest request)
    {
        var storeId = RequiredStoreId;
        var employeeId = CurrentUserId.ToString();

        var journey = await _dbContext.JourneyTrackings
            .AsTracking()
            .FirstOrDefaultAsync(j => j.StoreId == storeId
                && j.EmployeeId == employeeId
                && j.Status == "in_progress"
                && j.Deleted == null);

        if (journey == null)
            return NotFound(AppResponse<object>.Fail("KhÃ´ng tÃ¬m tháº¥y hÃ nh trÃ¬nh Ä‘ang hoáº¡t Ä‘á»™ng"));

        if (request.Points == null || request.Points.Count == 0)
            return Ok(AppResponse<object>.Success(new { saved = 0 }));

        // Append new points to existing route
        var existingPoints = JsonSerializer.Deserialize<List<RoutePoint>>(journey.RoutePointsJson ?? "[]") ?? new();
        
        foreach (var pt in request.Points)
        {
            existingPoints.Add(new RoutePoint
            {
                Lat = pt.Latitude,
                Lng = pt.Longitude,
                Time = pt.Timestamp ?? DateTime.UtcNow,
                Speed = pt.Speed,
            });
        }

        // Recalculate total distance from points
        double totalDistanceM = 0;
        for (int i = 1; i < existingPoints.Count; i++)
        {
            totalDistanceM += CalculateDistance(
                existingPoints[i - 1].Lat, existingPoints[i - 1].Lng,
                existingPoints[i].Lat, existingPoints[i].Lng);
        }

        // Detect dwell zones: consecutive points within 50m radius â†’ mark dwell time
        var fieldLocations = await _dbContext.FieldLocations
            .AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null && l.IsActive)
            .Select(l => new { l.Latitude, l.Longitude, l.Name, l.Radius })
            .ToListAsync();

        const double dwellRadiusM = 50.0;
        for (int i = 0; i < existingPoints.Count; i++)
        {
            // Find consecutive points within dwellRadius of point i
            int dwellEnd = i;
            for (int j = i + 1; j < existingPoints.Count; j++)
            {
                double dist = CalculateDistance(existingPoints[i].Lat, existingPoints[i].Lng,
                    existingPoints[j].Lat, existingPoints[j].Lng);
                if (dist <= dwellRadiusM)
                    dwellEnd = j;
                else
                    break;
            }
            if (dwellEnd > i)
            {
                var dwellMinutes = (int)(existingPoints[dwellEnd].Time - existingPoints[i].Time).TotalMinutes;
                if (dwellMinutes >= 2) // At least 2 minutes to count as dwell
                {
                    existingPoints[i].DwellMinutes = dwellMinutes;
                    // Check if near a known location
                    foreach (var loc in fieldLocations)
                    {
                        double distToLoc = CalculateDistance(existingPoints[i].Lat, existingPoints[i].Lng,
                            loc.Latitude, loc.Longitude);
                        if (distToLoc <= (loc.Radius > 0 ? loc.Radius : 200))
                        {
                            existingPoints[i].NearLocationName = loc.Name;
                            break;
                        }
                    }
                }
                i = dwellEnd; // skip dwell points
            }
        }

        journey.RoutePointsJson = JsonSerializer.Serialize(existingPoints);
        journey.TotalDistanceKm = Math.Round(totalDistanceM / 1000.0, 2);
        journey.UpdatedAt = DateTime.UtcNow;

        // Update checked-in count from today's visits
        var today = journey.JourneyDate.Date;
        journey.CheckedInCount = await _dbContext.VisitReports
            .CountAsync(v => v.StoreId == storeId
                && v.EmployeeId == employeeId
                && v.VisitDate.Date == today
                && v.Status != "draft"
                && v.Deleted == null);

        // Update on-site minutes
        journey.TotalOnSiteMinutes = await _dbContext.VisitReports
            .Where(v => v.StoreId == storeId
                && v.EmployeeId == employeeId
                && v.VisitDate.Date == today
                && v.TimeSpentMinutes.HasValue
                && v.Deleted == null)
            .SumAsync(v => v.TimeSpentMinutes!.Value);

        if (journey.StartTime.HasValue)
        {
            var totalMinutes = (int)(DateTime.UtcNow - journey.StartTime.Value).TotalMinutes;
            journey.TotalTravelMinutes = Math.Max(0, totalMinutes - journey.TotalOnSiteMinutes);
        }

        await _dbContext.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(new
        {
            saved = request.Points.Count,
            totalDistanceKm = journey.TotalDistanceKm,
            totalTravelMinutes = journey.TotalTravelMinutes,
            totalOnSiteMinutes = journey.TotalOnSiteMinutes,
            checkedInCount = journey.CheckedInCount,
        }));
    }

    /// <summary>
    /// NhÃ¢n viÃªn káº¿t thÃºc hÃ nh trÃ¬nh  
    /// </summary>
    [HttpPost("journey/end")]
    public async Task<ActionResult> EndJourney([FromBody] EndJourneyRequest? request)
    {
        var storeId = RequiredStoreId;
        var employeeId = CurrentUserId.ToString();

        var journey = await _dbContext.JourneyTrackings
            .AsTracking()
            .FirstOrDefaultAsync(j => j.StoreId == storeId
                && j.EmployeeId == employeeId
                && j.Status == "in_progress"
                && j.Deleted == null);

        if (journey == null)
            return NotFound(AppResponse<object>.Fail("KhÃ´ng tÃ¬m tháº¥y hÃ nh trÃ¬nh Ä‘ang hoáº¡t Ä‘á»™ng"));

        var now = DateTime.UtcNow;
        journey.EndTime = now;
        journey.Status = "completed";
        journey.Note = request?.Note;
        journey.UpdatedAt = now;
        journey.UpdatedBy = CurrentUserEmail;

        // Final recalc
        var today = journey.JourneyDate.Date;
        journey.CheckedInCount = await _dbContext.VisitReports
            .CountAsync(v => v.StoreId == storeId
                && v.EmployeeId == employeeId
                && v.VisitDate.Date == today
                && v.Status != "draft"
                && v.Deleted == null);

        journey.TotalOnSiteMinutes = await _dbContext.VisitReports
            .Where(v => v.StoreId == storeId
                && v.EmployeeId == employeeId
                && v.VisitDate.Date == today
                && v.TimeSpentMinutes.HasValue
                && v.Deleted == null)
            .SumAsync(v => v.TimeSpentMinutes!.Value);

        if (journey.StartTime.HasValue)
        {
            var totalMinutes = (int)(now - journey.StartTime.Value).TotalMinutes;
            journey.TotalTravelMinutes = Math.Max(0, totalMinutes - journey.TotalOnSiteMinutes);
        }

        await _dbContext.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(new
        {
            id = journey.Id.ToString(),
            startTime = journey.StartTime,
            endTime = journey.EndTime,
            status = journey.Status,
            totalDistanceKm = journey.TotalDistanceKm,
            totalTravelMinutes = journey.TotalTravelMinutes,
            totalOnSiteMinutes = journey.TotalOnSiteMinutes,
            checkedInCount = journey.CheckedInCount,
            assignedCount = journey.AssignedCount,
        }));
    }

    /// <summary>
    /// NhÃ¢n viÃªn xem hÃ nh trÃ¬nh hÃ´m nay
    /// </summary>
    [HttpGet("journey/today")]
    public async Task<ActionResult> GetTodayJourney()
    {
        var storeId = RequiredStoreId;
        var employeeId = CurrentUserId.ToString();
        var today = DateTime.UtcNow.Date;

        var journey = await _dbContext.JourneyTrackings
            .AsNoTracking()
            .FirstOrDefaultAsync(j => j.StoreId == storeId
                && j.EmployeeId == employeeId
                && j.JourneyDate.Date == today
                && j.Deleted == null);

        if (journey == null)
            return Ok(AppResponse<object>.Success((object?)null));

        return Ok(AppResponse<object>.Success(new
        {
            id = journey.Id.ToString(),
            journeyDate = journey.JourneyDate,
            startTime = journey.StartTime,
            endTime = journey.EndTime,
            status = journey.Status,
            totalDistanceKm = journey.TotalDistanceKm,
            totalTravelMinutes = journey.TotalTravelMinutes,
            totalOnSiteMinutes = journey.TotalOnSiteMinutes,
            checkedInCount = journey.CheckedInCount,
            assignedCount = journey.AssignedCount,
            routePoints = journey.RoutePointsJson,
            note = journey.Note,
        }));
    }

    /// <summary>
    /// Manager xem táº¥t cáº£ hÃ nh trÃ¬nh Ä‘ang hoáº¡t Ä‘á»™ng hÃ´m nay (live map)
    /// </summary>
    [HttpGet("journey/active")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> GetActiveJourneys()
    {
        var storeId = RequiredStoreId;
        var today = DateTime.UtcNow.Date;

        var journeys = await _dbContext.JourneyTrackings
            .AsNoTracking()
            .Where(j => j.StoreId == storeId
                && j.JourneyDate.Date == today
                && j.Deleted == null)
            .OrderByDescending(j => j.StartTime)
            .Select(j => new
            {
                id = j.Id.ToString(),
                employeeId = j.EmployeeId,
                employeeName = j.EmployeeName,
                startTime = j.StartTime,
                endTime = j.EndTime,
                status = j.Status,
                totalDistanceKm = j.TotalDistanceKm,
                checkedInCount = j.CheckedInCount,
                assignedCount = j.AssignedCount,
                routePoints = j.RoutePointsJson,
                totalTravelMinutes = j.TotalTravelMinutes,
                totalOnSiteMinutes = j.TotalOnSiteMinutes,
            })
            .ToListAsync();

        // Get today's visits by employee
        var todayVisits = await _dbContext.VisitReports
            .AsNoTracking()
            .Where(v => v.StoreId == storeId
                && v.VisitDate.Date == today
                && v.Deleted == null)
            .OrderBy(v => v.CheckInTime)
            .Select(v => new
            {
                employeeId = v.EmployeeId,
                locationName = v.LocationName,
                checkInTime = v.CheckInTime,
                checkOutTime = v.CheckOutTime,
                timeSpentMinutes = v.TimeSpentMinutes,
                status = v.Status,
                checkInLatitude = v.CheckInLatitude,
                checkInLongitude = v.CheckInLongitude,
            })
            .ToListAsync();

        var result = journeys.Select(j =>
        {
            var empVisits = todayVisits.Where(v => v.employeeId == j.employeeId).ToList();
            // Parse last point from route
            double? lastLat = null, lastLng = null;
            DateTime? lastTime = null;
            try
            {
                var points = JsonSerializer.Deserialize<List<RoutePoint>>(j.routePoints ?? "[]") ?? new();
                if (points.Count > 0)
                {
                    var last = points.Last();
                    lastLat = last.Lat;
                    lastLng = last.Lng;
                    lastTime = last.Time;
                }
            }
            catch { }

            return new
            {
                j.id,
                j.employeeId,
                j.employeeName,
                j.startTime,
                j.endTime,
                j.status,
                j.totalDistanceKm,
                j.checkedInCount,
                j.assignedCount,
                j.totalTravelMinutes,
                j.totalOnSiteMinutes,
                routePoints = j.routePoints,
                lastLatitude = lastLat,
                lastLongitude = lastLng,
                lastUpdateTime = lastTime,
                visits = empVisits,
            };
        }).ToList();

        return Ok(AppResponse<object>.Success(result));
    }
    /// <summary>
    /// Manager xem vi tri tat ca nhan vien theo phong ban + lich su check-in hom nay
    /// </summary>
    [HttpGet("employee-locations")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> GetEmployeeLocations()
    {
        var storeId = RequiredStoreId;
        var today = DateTime.UtcNow.Date;

        // 1. Get all active employees in this store
        var employees = await _dbContext.Employees
            .AsNoTracking()
            .Where(e => e.StoreId == storeId && e.Deleted == null
                && e.WorkStatus == Domain.Enums.EmployeeWorkStatus.Active)
            .Select(e => new
            {
                e.Id,
                e.EmployeeCode,
                e.FirstName,
                e.LastName,
                e.Department,
                e.DepartmentId,
                e.Position,
                e.PhotoUrl,
            })
            .ToListAsync();

        // 2. Get department info for grouping
        var deptIds = employees.Where(e => e.DepartmentId.HasValue).Select(e => e.DepartmentId!.Value).Distinct().ToList();
        var departments = await _dbContext.Departments
            .AsNoTracking()
            .Where(d => deptIds.Contains(d.Id))
            .Select(d => new { d.Id, d.Name, d.SortOrder })
            .ToListAsync();

        // 3. Get today's active journeys (for live GPS from route points)
        var todayJourneys = await _dbContext.JourneyTrackings
            .AsNoTracking()
            .Where(j => j.StoreId == storeId && j.JourneyDate.Date == today && j.Deleted == null)
            .Select(j => new
            {
                j.EmployeeId,
                j.RoutePointsJson,
                j.Status,
                j.StartTime,
                j.TotalDistanceKm,
            })
            .ToListAsync();

        // 4. Get today's check-in visits
        var todayVisits = await _dbContext.VisitReports
            .AsNoTracking()
            .Where(v => v.StoreId == storeId && v.VisitDate.Date == today && v.Deleted == null)
            .OrderBy(v => v.CheckInTime)
            .Select(v => new
            {
                v.EmployeeId,
                v.LocationName,
                v.CheckInTime,
                v.CheckOutTime,
                v.TimeSpentMinutes,
                v.Status,
                v.CheckInLatitude,
                v.CheckInLongitude,
            })
            .ToListAsync();

        // 5. Get today's mobile attendance punches with GPS
        var todayPunches = await _dbContext.MobileAttendanceRecords
            .AsNoTracking()
            .Where(m => m.StoreId == storeId && m.PunchTime.Date == today && m.Deleted == null
                && m.Latitude.HasValue && m.Longitude.HasValue)
            .OrderByDescending(m => m.PunchTime)
            .Select(m => new
            {
                m.OdooEmployeeId,
                m.Latitude,
                m.Longitude,
                m.PunchTime,
                m.LocationName,
            })
            .ToListAsync();

        // 6. Build result per employee
        var deptColorIndex = 0;
        var deptColorMap = new Dictionary<string, int>();

        var result = employees.Select(emp =>
        {
            var empIdStr = emp.Id.ToString();
            var empCode = emp.EmployeeCode;
            var deptName = emp.Department ?? "Chua phan phong";

            // Assign consistent color index per department
            if (!deptColorMap.ContainsKey(deptName))
                deptColorMap[deptName] = deptColorIndex++;

            // Find last GPS: priority journey > checkin > punch
            double? lat = null, lng = null;
            DateTime? lastUpdate = null;
            string? source = null;

            var journey = todayJourneys.FirstOrDefault(j => j.EmployeeId == empCode || j.EmployeeId == empIdStr);
            if (journey != null)
            {
                try
                {
                    var points = JsonSerializer.Deserialize<List<RoutePoint>>(journey.RoutePointsJson ?? "[]") ?? new();
                    if (points.Count > 0)
                    {
                        var last = points.Last();
                        if (last.Lat != 0 && last.Lng != 0)
                        {
                            lat = last.Lat;
                            lng = last.Lng;
                            lastUpdate = last.Time;
                            source = "journey";
                        }
                    }
                }
                catch { }
            }

            // Fallback: last check-in GPS
            if (lat == null)
            {
                var lastVisit = todayVisits.LastOrDefault(v => v.EmployeeId == empCode || v.EmployeeId == empIdStr);
                if (lastVisit?.CheckInLatitude != null && lastVisit.CheckInLatitude != 0)
                {
                    lat = lastVisit.CheckInLatitude;
                    lng = lastVisit.CheckInLongitude;
                    lastUpdate = lastVisit.CheckOutTime ?? lastVisit.CheckInTime;
                    source = "checkin";
                }
            }

            // Fallback: last mobile punch GPS
            if (lat == null)
            {
                var lastPunch = todayPunches.FirstOrDefault(p => p.OdooEmployeeId == empCode || p.OdooEmployeeId == empIdStr);
                if (lastPunch?.Latitude != null && lastPunch.Latitude != 0)
                {
                    lat = lastPunch.Latitude;
                    lng = lastPunch.Longitude;
                    lastUpdate = lastPunch.PunchTime;
                    source = "punch";
                }
            }

            // Employee's today visits
            var empVisits = todayVisits
                .Where(v => v.EmployeeId == empCode || v.EmployeeId == empIdStr)
                .Select(v => new
                {
                    v.LocationName,
                    v.CheckInTime,
                    v.CheckOutTime,
                    v.TimeSpentMinutes,
                    v.Status,
                    v.CheckInLatitude,
                    v.CheckInLongitude,
                })
                .ToList();

            return new
            {
                employeeId = empIdStr,
                employeeCode = empCode,
                employeeName = $"{emp.LastName} {emp.FirstName}".Trim(),
                department = deptName,
                departmentColorIndex = deptColorMap[deptName],
                position = emp.Position ?? "",
                photoUrl = emp.PhotoUrl ?? "",
                latitude = lat,
                longitude = lng,
                lastUpdateTime = lastUpdate,
                locationSource = source,
                journeyStatus = journey?.Status,
                todayCheckins = empVisits,
                checkinCount = empVisits.Count,
            };
        })
        .OrderBy(e => e.departmentColorIndex)
        .ThenBy(e => e.employeeName)
        .ToList();

        return Ok(AppResponse<object>.Success(result));
    }

    /// <summary>
    /// Manager xem hÃ nh trÃ¬nh cá»§a nhÃ¢n viÃªn (báº£n Ä‘á»“ + timeline)
    /// </summary>
    [HttpGet("journey/reports")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> GetJourneyReports(
        [FromQuery] string? employeeId,
        [FromQuery] DateTime? fromDate,
        [FromQuery] DateTime? toDate)
    {
        var storeId = RequiredStoreId;
        var from = fromDate ?? DateTime.UtcNow.Date.AddDays(-7);
        var to = toDate ?? DateTime.UtcNow.Date.AddDays(1);

        var query = _dbContext.JourneyTrackings
            .AsNoTracking()
            .Where(j => j.StoreId == storeId && j.Deleted == null
                && j.JourneyDate >= from && j.JourneyDate <= to);

        if (!string.IsNullOrEmpty(employeeId))
            query = query.Where(j => j.EmployeeId == employeeId);

        var journeys = await query
            .OrderByDescending(j => j.JourneyDate)
            .Take(200)
            .Select(j => new
            {
                id = j.Id.ToString(),
                employeeId = j.EmployeeId,
                employeeName = j.EmployeeName,
                journeyDate = j.JourneyDate,
                startTime = j.StartTime,
                endTime = j.EndTime,
                status = j.Status,
                totalDistanceKm = j.TotalDistanceKm,
                totalTravelMinutes = j.TotalTravelMinutes,
                totalOnSiteMinutes = j.TotalOnSiteMinutes,
                checkedInCount = j.CheckedInCount,
                assignedCount = j.AssignedCount,
                routePoints = j.RoutePointsJson,
                note = j.Note,
                reviewedBy = j.ReviewedBy,
                reviewedAt = j.ReviewedAt,
                reviewNote = j.ReviewNote,
            })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(journeys));
    }

    /// <summary>
    /// Manager xem chi tiáº¿t hÃ nh trÃ¬nh + visits trong ngÃ y
    /// </summary>
    [HttpGet("journey/{journeyId}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> GetJourneyDetail(Guid journeyId)
    {
        var storeId = RequiredStoreId;

        var journey = await _dbContext.JourneyTrackings
            .AsNoTracking()
            .FirstOrDefaultAsync(j => j.Id == journeyId && j.StoreId == storeId && j.Deleted == null);

        if (journey == null)
            return NotFound(AppResponse<object>.Fail("KhÃ´ng tÃ¬m tháº¥y hÃ nh trÃ¬nh"));

        // Get visits for that day by that employee
        var visits = await _dbContext.VisitReports
            .AsNoTracking()
            .Where(v => v.StoreId == storeId
                && v.EmployeeId == journey.EmployeeId
                && v.VisitDate.Date == journey.JourneyDate.Date
                && v.Deleted == null)
            .OrderBy(v => v.CheckInTime)
            .Select(v => new
            {
                id = v.Id.ToString(),
                locationId = v.LocationId.ToString(),
                locationName = v.LocationName,
                checkInTime = v.CheckInTime,
                checkOutTime = v.CheckOutTime,
                timeSpentMinutes = v.TimeSpentMinutes,
                checkInDistance = v.CheckInDistance,
                checkInLatitude = v.CheckInLatitude,
                checkInLongitude = v.CheckInLongitude,
                status = v.Status,
                reportNote = v.ReportNote,
                photos = v.PhotoUrlsJson,
            })
            .ToListAsync();

        // Get assigned locations
        var dow = (int)journey.JourneyDate.DayOfWeek;
        if (dow == 0) dow = 7;
        var assignments = await _dbContext.FieldLocationAssignments
            .AsNoTracking()
            .Where(a => a.StoreId == storeId
                && a.EmployeeId == journey.EmployeeId
                && a.Deleted == null
                && a.IsActive
                && (a.DayOfWeek == null || a.DayOfWeek == dow))
            .OrderBy(a => a.SortOrder)
            .Select(a => new
            {
                id = a.Id.ToString(),
                locationId = a.LocationId.ToString(),
                locationName = a.Location != null ? a.Location.Name : "",
                latitude = a.Location != null ? a.Location.Latitude : 0,
                longitude = a.Location != null ? a.Location.Longitude : 0,
                sortOrder = a.SortOrder,
            })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(new
        {
            journey = new
            {
                id = journey.Id.ToString(),
                employeeId = journey.EmployeeId,
                employeeName = journey.EmployeeName,
                journeyDate = journey.JourneyDate,
                startTime = journey.StartTime,
                endTime = journey.EndTime,
                status = journey.Status,
                totalDistanceKm = journey.TotalDistanceKm,
                totalTravelMinutes = journey.TotalTravelMinutes,
                totalOnSiteMinutes = journey.TotalOnSiteMinutes,
                checkedInCount = journey.CheckedInCount,
                assignedCount = journey.AssignedCount,
                routePoints = journey.RoutePointsJson,
                note = journey.Note,
            },
            visits = visits.Select(v => new
            {
                v.id,
                v.locationId,
                v.locationName,
                v.checkInTime,
                v.checkOutTime,
                v.timeSpentMinutes,
                v.checkInDistance,
                v.checkInLatitude,
                v.checkInLongitude,
                v.status,
                v.reportNote,
                photos = SafeDeserializePhotos(v.photos),
            }),
            assignments,
        }));
    }

    /// <summary>
    /// Manager review hÃ nh trÃ¬nh
    /// </summary>
    [HttpPost("journey/{journeyId}/review")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    public async Task<ActionResult> ReviewJourney(Guid journeyId, [FromBody] ReviewVisitRequest request)
    {
        var storeId = RequiredStoreId;
        var journey = await _dbContext.JourneyTrackings
            .AsTracking()
            .FirstOrDefaultAsync(j => j.Id == journeyId && j.StoreId == storeId && j.Deleted == null);

        if (journey == null)
            return NotFound(AppResponse<object>.Fail("KhÃ´ng tÃ¬m tháº¥y hÃ nh trÃ¬nh"));

        journey.Status = "reviewed";
        journey.ReviewedBy = CurrentUserEmail;
        journey.ReviewedAt = DateTime.UtcNow;
        journey.ReviewNote = request.ReviewNote;
        journey.UpdatedAt = DateTime.UtcNow;
        journey.UpdatedBy = CurrentUserEmail;

        await _dbContext.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(new { status = journey.Status }));
    }

    // ==================== HELPERS ====================

    private static List<string> SafeDeserializePhotos(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return new List<string>();
        try { return JsonSerializer.Deserialize<List<string>>(json) ?? new List<string>(); }
        catch { return new List<string>(); }
    }

    private static double CalculateDistance(double lat1, double lon1, double lat2, double lon2)
    {
        const double R = 6371000;
        var dLat = (lat2 - lat1) * Math.PI / 180;
        var dLon = (lon2 - lon1) * Math.PI / 180;
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2) +
                Math.Cos(lat1 * Math.PI / 180) * Math.Cos(lat2 * Math.PI / 180) *
                Math.Sin(dLon / 2) * Math.Sin(dLon / 2);
        var c = 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
        return R * c;
    }
}

// ==================== INTERNAL DTOs ====================

public class RoutePoint
{
    [JsonPropertyName("lat")]
    public double Lat { get; set; }
    [JsonPropertyName("lng")]
    public double Lng { get; set; }
    [JsonPropertyName("time")]
    public DateTime Time { get; set; }
    [JsonPropertyName("speed")]
    public double? Speed { get; set; }
    [JsonPropertyName("dwellMinutes")]
    public int? DwellMinutes { get; set; }
    [JsonPropertyName("nearLocationName")]
    public string? NearLocationName { get; set; }
}

public class TrackPointsRequest
{
    public List<TrackPoint> Points { get; set; } = new();
}

public class TrackPoint
{
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public DateTime? Timestamp { get; set; }
    public double? Speed { get; set; }
}

public class EndJourneyRequest
{
    public string? Note { get; set; }
}

// ==================== REQUEST DTOs ====================

public class CreateAssignmentRequest
{
    public string EmployeeId { get; set; } = string.Empty;
    public string? EmployeeName { get; set; }
    public Guid LocationId { get; set; }
    public int? DayOfWeek { get; set; }
    public int SortOrder { get; set; } = 1;
    public string? Note { get; set; }
}

public class BulkAssignRequest
{
    public List<CreateAssignmentRequest> Items { get; set; } = new();
}

public class UpdateAssignmentRequest
{
    public int? DayOfWeek { get; set; }
    public int? SortOrder { get; set; }
    public string? Note { get; set; }
    public bool? IsActive { get; set; }
}

public class CheckInRequest
{
    public Guid LocationId { get; set; }
    public string? EmployeeName { get; set; }
    public double? Latitude { get; set; }
    public double? Longitude { get; set; }
    public string? Note { get; set; }
}

public class CheckOutRequest
{
    public double? Latitude { get; set; }
    public double? Longitude { get; set; }
    public string? Note { get; set; }
    public List<string>? Photos { get; set; }
    public string? ReportDataJson { get; set; }
}

public class ReviewVisitRequest
{
    public string? ReviewNote { get; set; }
}

public class RegisterFieldLocationRequest
{
    public string Name { get; set; } = string.Empty;
    public string? Address { get; set; }
    public string? ContactName { get; set; }
    public string? ContactPhone { get; set; }
    public string? ContactEmail { get; set; }
    public string? Note { get; set; }
    public double Latitude { get; set; }
    public double Longitude { get; set; }
    public double Radius { get; set; } = 200;
    public string? Category { get; set; }
    public List<string>? Photos { get; set; }
}

public class UpdateFieldLocationRequest
{
    public string? Name { get; set; }
    public string? Address { get; set; }
    public string? ContactName { get; set; }
    public string? ContactPhone { get; set; }
    public string? ContactEmail { get; set; }
    public string? Note { get; set; }
    public double? Latitude { get; set; }
    public double? Longitude { get; set; }
    public double? Radius { get; set; }
    public string? Category { get; set; }
    public List<string>? Photos { get; set; }
}

