using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using System.Text.Json;
using System.Text.Json.Serialization;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Processing;
using SixLabors.ImageSharp.Formats.Jpeg;
using ZKTecoADMS.Api.Authorization;
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

    /// <summary>
    /// Vietnam is UTC+7, but all timestamps are stored as UTC. A naive
    /// <c>DateTime.UtcNow.Date</c> comparison drops an entire day for users
    /// acting between 00:00 and 07:00 local time (their VisitDate/PunchTime
    /// rows stamped with yesterday UTC won't match "today UTC"). This helper
    /// returns the VN calendar date together with the UTC range that covers
    /// that VN day, so callers can filter time-stamped columns correctly:
    ///   <c>v.VisitDate &gt;= vnStart &amp;&amp; v.VisitDate &lt; vnEnd</c>.
    /// For date-only columns (e.g. JourneyDate) compare against <c>today</c>.
    /// </summary>
    private static (DateTime today, DateTime vnStart, DateTime vnEnd) VnTodayRange()
    {
        var today = DateTime.UtcNow.AddHours(7).Date;
        var vnStart = today.AddHours(-7); // UTC instant of VN 00:00
        var vnEnd = vnStart.AddDays(1);   // UTC instant of next VN 00:00
        return (today, vnStart, vnEnd);
    }

    /// <summary>Mon=1 .. Sun=7 in Vietnam local calendar (UTC+7).</summary>
    private static int GetVnDayOfWeek()
    {
        var vnDow = (int)DateTime.UtcNow.AddHours(7).DayOfWeek;
        return vnDow == 0 ? 7 : vnDow;
    }

    /// <summary>
    /// NÃ©n áº£nh: resize max 1024px, JPEG quality 65%
    /// </summary>
    private static MemoryStream CompressImage(byte[] imageBytes, int maxWidth = 1024, int quality = 65)
    {
        using var image = SixLabors.ImageSharp.Image.Load(imageBytes);
        if (image.Width > maxWidth || image.Height > maxWidth)
        {
            var ratio = Math.Min((double)maxWidth / image.Width, (double)maxWidth / image.Height);
            image.Mutate(x => x.Resize((int)(image.Width * ratio), (int)(image.Height * ratio)));
        }
        var output = new MemoryStream();
        image.Save(output, new JpegEncoder { Quality = quality });
        output.Position = 0;
        return output;
    }

    // ==================== FIELD LOCATIONS (Ã„ÂIÃ¡Â»â€šM BÃƒÂN KHÃƒÂCH HÃƒâ‚¬NG) ====================

    /// <summary>
    /// LÃ¡ÂºÂ¥y danh sÃƒÂ¡ch tÃ¡ÂºÂ¥t cÃ¡ÂºÂ£ Ã„â€˜iÃ¡Â»Æ’m bÃƒÂ¡n (nhÃƒÂ¢n viÃƒÂªn + manager Ã„â€˜Ã¡Â»Âu xem Ã„â€˜Ã†Â°Ã¡Â»Â£c)
    /// </summary>
    [HttpGet("locations")]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.View)]
    public async Task<ActionResult> GetLocations([FromQuery] string? search, [FromQuery] string? category)
    {
        var storeId = RequiredStoreId;
        var query = _dbContext.FieldLocations
            .AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null);

        if (!string.IsNullOrEmpty(search))
            query = query.Where(l => l.Name.Contains(search) || (l.Address != null && l.Address.Contains(search))
                || (l.ContactName != null && l.ContactName.Contains(search))
                || (l.ContactPhone != null && l.ContactPhone.Contains(search)));

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
    /// NhÃƒÂ¢n viÃƒÂªn Ã„â€˜Ã„Æ’ng kÃƒÂ½ Ã„â€˜iÃ¡Â»Æ’m bÃƒÂ¡n mÃ¡Â»â€ºi (tÃ¡Â»Â± chÃ¡Â»Â¥p Ã¡ÂºÂ£nh, nhÃ¡ÂºÂ­p thÃƒÂ´ng tin liÃƒÂªn hÃ¡Â»â€¡)
    /// </summary>
    [HttpPost("locations")]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.Create)]
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
                    using var compressed = CompressImage(imageBytes);
                    var storedPath = await _fileStorageService.UploadAsync(compressed, fileName, uploadFolder);
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
    /// CÃ¡ÂºÂ­p nhÃ¡ÂºÂ­t thÃƒÂ´ng tin Ã„â€˜iÃ¡Â»Æ’m bÃƒÂ¡n
    /// </summary>
    [HttpPut("locations/{id}")]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.Edit)]
    [RequestSizeLimit(20_000_000)]
    public async Task<ActionResult> UpdateLocation(Guid id, [FromBody] UpdateFieldLocationRequest request)
    {
        var storeId = RequiredStoreId;
        var location = await _dbContext.FieldLocations
            .AsTracking()
            .FirstOrDefaultAsync(l => l.Id == id && l.StoreId == storeId && l.Deleted == null);

        if (location == null)
            return NotFound(AppResponse<object>.Fail("KhÃƒÂ´ng tÃƒÂ¬m thÃ¡ÂºÂ¥y Ã„â€˜iÃ¡Â»Æ’m bÃƒÂ¡n"));

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
    /// XÃƒÂ³a Ã„â€˜iÃ¡Â»Æ’m bÃƒÂ¡n (Manager)
    /// </summary>
    [HttpDelete("locations/{id}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.Delete)]
    public async Task<ActionResult> DeleteLocation(Guid id)
    {
        var storeId = RequiredStoreId;
        var location = await _dbContext.FieldLocations
            .AsTracking()
            .FirstOrDefaultAsync(l => l.Id == id && l.StoreId == storeId && l.Deleted == null);

        if (location == null)
            return NotFound(AppResponse<object>.Fail("KhÃƒÂ´ng tÃƒÂ¬m thÃ¡ÂºÂ¥y Ã„â€˜iÃ¡Â»Æ’m bÃƒÂ¡n"));

        location.Deleted = DateTime.UtcNow;
        location.DeletedBy = CurrentUserEmail;
        await _dbContext.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(new { deleted = true }));
    }

    // ==================== ASSIGNMENT (GIAO Ã„ÂIÃ¡Â»â€šM) ====================

    /// <summary>
    /// LÃ¡ÂºÂ¥y danh sÃƒÂ¡ch giao Ã„â€˜iÃ¡Â»Æ’m cho nhÃƒÂ¢n viÃƒÂªn (Manager)
    /// </summary>
    [HttpGet("assignments")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.View)]
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
    /// NhÃƒÂ¢n viÃƒÂªn xem danh sÃƒÂ¡ch Ã„â€˜iÃ¡Â»Æ’m Ã„â€˜Ã†Â°Ã¡Â»Â£c giao cho mÃƒÂ¬nh (hÃƒÂ´m nay hoÃ¡ÂºÂ·c theo thÃ¡Â»Â©)
    /// </summary>
    [HttpGet("my-assignments")]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.View)]
    public async Task<ActionResult> GetMyAssignments([FromQuery] int? dayOfWeek)
    {
        var storeId = RequiredStoreId;
        var employeeId = CurrentUserId.ToString();
        var dow = dayOfWeek ?? GetVnDayOfWeek();

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
    /// Giao Ã„â€˜iÃ¡Â»Æ’m cho nhÃƒÂ¢n viÃƒÂªn (Manager)
    /// </summary>
    [HttpPost("assignments")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.Create)]
    public async Task<ActionResult> CreateAssignment([FromBody] CreateAssignmentRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.EmployeeId))
            return BadRequest(AppResponse<object>.Fail("ThiÃ¡ÂºÂ¿u thÃƒÂ´ng tin nhÃƒÂ¢n viÃƒÂªn"));

        var storeId = RequiredStoreId;

        // Verify location exists
        var location = await _dbContext.FieldLocations
            .AsNoTracking()
            .FirstOrDefaultAsync(l => l.Id == request.LocationId && l.StoreId == storeId && l.Deleted == null);
        if (location == null)
            return NotFound(AppResponse<object>.Fail("KhÃƒÂ´ng tÃƒÂ¬m thÃ¡ÂºÂ¥y Ã„â€˜iÃ¡Â»Æ’m bÃƒÂ¡n"));

        // Check duplicate
        var exists = await _dbContext.FieldLocationAssignments
            .AnyAsync(a => a.StoreId == storeId
                && a.EmployeeId == request.EmployeeId
                && a.LocationId == request.LocationId
                && a.DayOfWeek == request.DayOfWeek
                && a.Deleted == null);
        if (exists)
            return BadRequest(AppResponse<object>.Fail("NhÃƒÂ¢n viÃƒÂªn Ã„â€˜ÃƒÂ£ Ã„â€˜Ã†Â°Ã¡Â»Â£c giao Ã„â€˜iÃ¡Â»Æ’m nÃƒÂ y vÃƒÂ o thÃ¡Â»Â© Ã„â€˜ÃƒÂ£ chÃ¡Â»Ân"));

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
    /// Giao Ã„â€˜iÃ¡Â»Æ’m hÃƒÂ ng loÃ¡ÂºÂ¡t (Manager)
    /// </summary>
    [HttpPost("assignments/bulk")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.Create)]
    public async Task<ActionResult> BulkAssign([FromBody] BulkAssignRequest request)
    {
        if (request.Items == null || request.Items.Count == 0)
            return BadRequest(AppResponse<object>.Fail("Danh sÃƒÂ¡ch giao Ã„â€˜iÃ¡Â»Æ’m trÃ¡Â»â€˜ng"));

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
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.Edit)]
    public async Task<ActionResult> UpdateAssignment(Guid id, [FromBody] UpdateAssignmentRequest request)
    {
        var storeId = RequiredStoreId;
        var assignment = await _dbContext.FieldLocationAssignments
            .AsTracking()
            .FirstOrDefaultAsync(a => a.Id == id && a.StoreId == storeId && a.Deleted == null);

        if (assignment == null)
            return NotFound(AppResponse<object>.Fail("KhÃƒÂ´ng tÃƒÂ¬m thÃ¡ÂºÂ¥y giao Ã„â€˜iÃ¡Â»Æ’m"));

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
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.Delete)]
    public async Task<ActionResult> DeleteAssignment(Guid id)
    {
        var storeId = RequiredStoreId;
        var assignment = await _dbContext.FieldLocationAssignments
            .AsTracking()
            .FirstOrDefaultAsync(a => a.Id == id && a.StoreId == storeId && a.Deleted == null);

        if (assignment == null)
            return NotFound(AppResponse<object>.Fail("KhÃƒÂ´ng tÃƒÂ¬m thÃ¡ÂºÂ¥y giao Ã„â€˜iÃ¡Â»Æ’m"));

        assignment.Deleted = DateTime.UtcNow;
        assignment.DeletedBy = CurrentUserEmail;
        await _dbContext.SaveChangesAsync();

        return Ok(AppResponse<object>.Success(new { deleted = true }));
    }

    // ==================== VISIT REPORTS (CHECK-IN / CHECK-OUT) ====================

    /// <summary>
    /// NhÃƒÂ¢n viÃƒÂªn check-in tÃ¡ÂºÂ¡i Ã„â€˜iÃ¡Â»Æ’m bÃƒÂ¡n
    /// </summary>
    [HttpPost("checkin")]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.Create)]
    public async Task<ActionResult> CheckIn([FromBody] CheckInRequest request)
    {
        var storeId = RequiredStoreId;
        var employeeId = CurrentUserId.ToString();

        // Verify location
        var location = await _dbContext.FieldLocations
            .AsNoTracking()
            .FirstOrDefaultAsync(l => l.Id == request.LocationId && l.StoreId == storeId && l.Deleted == null);
        if (location == null)
            return NotFound(AppResponse<object>.Fail("KhÃƒÂ´ng tÃƒÂ¬m thÃ¡ÂºÂ¥y Ã„â€˜iÃ¡Â»Æ’m bÃƒÂ¡n"));

        // Check if already checked in at this location today (not yet checked out)
        var (today, vnStart, vnEnd) = VnTodayRange();
        var existing = await _dbContext.VisitReports
            .FirstOrDefaultAsync(v => v.StoreId == storeId
                && v.EmployeeId == employeeId
                && v.LocationId == request.LocationId
                && v.VisitDate >= vnStart && v.VisitDate < vnEnd
                && v.Status == "checked_in"
                && v.Deleted == null);

        if (existing != null)
            return BadRequest(AppResponse<object>.Fail($"BÃ¡ÂºÂ¡n Ã„â€˜ÃƒÂ£ check-in tÃ¡ÂºÂ¡i '{location.Name}' lÃƒÂºc {existing.CheckInTime:HH:mm} vÃƒÂ  chÃ†Â°a check-out. Vui lÃƒÂ²ng check-out trÃ†Â°Ã¡Â»â€ºc."));

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
                return BadRequest(AppResponse<object>.Fail($"BÃ¡ÂºÂ¡n Ã¡Â»Å¸ quÃƒÂ¡ xa Ã„â€˜iÃ¡Â»Æ’m bÃƒÂ¡n ({distance:F0}m > {maxRadius}m). Vui lÃƒÂ²ng di chuyÃ¡Â»Æ’n Ã„â€˜Ã¡ÂºÂ¿n gÃ¡ÂºÂ§n hÃ†Â¡n."));
            outsideRadius = distance > (location.Radius > 0 ? location.Radius : 200);
        }

        // Link to today's active journey
        Guid? journeyId = null;
        var activeJourney = await _dbContext.JourneyTrackings
            .AsNoTracking()
            .FirstOrDefaultAsync(j => j.StoreId == storeId
                && j.EmployeeId == employeeId
                && j.JourneyDate == today
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
    /// NhÃƒÂ¢n viÃƒÂªn check-out khÃ¡Â»Âi Ã„â€˜iÃ¡Â»Æ’m bÃƒÂ¡n + upload Ã¡ÂºÂ£nh + ghi chÃƒÂº
    /// </summary>
    [HttpPost("checkout/{visitId}")]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.Create)]
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
            return NotFound(AppResponse<object>.Fail("KhÃƒÂ´ng tÃƒÂ¬m thÃ¡ÂºÂ¥y bÃ¡ÂºÂ£n ghi check-in"));

        if (report.Status != "checked_in")
            return BadRequest(AppResponse<object>.Fail("BÃ¡ÂºÂ£n ghi nÃƒÂ y Ã„â€˜ÃƒÂ£ check-out hoÃ¡ÂºÂ·c khÃƒÂ´ng Ã¡Â»Å¸ trÃ¡ÂºÂ¡ng thÃƒÂ¡i check-in"));

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

        // Upload photos (compressed)
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
                var fileName = $"visit_{visitId}_{Guid.NewGuid():N}.jpg";

                try
                {
                    using var compressed = CompressImage(imageBytes);
                    var storedPath = await _fileStorageService.UploadAsync(compressed, fileName, uploadFolder);
                    photoUrls.Add(_fileStorageService.GetFileUrl(storedPath));
                }
                catch
                {
                    // Fallback: save original if compression fails
                    using var stream = new MemoryStream(imageBytes);
                    var storedPath = await _fileStorageService.UploadAsync(stream, fileName, uploadFolder);
                    photoUrls.Add(_fileStorageService.GetFileUrl(storedPath));
                }
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
    /// NhÃƒÂ¢n viÃƒÂªn xem lÃ¡Â»â€¹ch sÃ¡Â»Â­ check-in cÃ¡Â»Â§a mÃƒÂ¬nh
    /// </summary>
    [HttpGet("my-visits")]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.View)]
    public async Task<ActionResult> GetMyVisits(
        [FromQuery] DateTime? fromDate,
        [FromQuery] DateTime? toDate,
        [FromQuery] string? status,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        var employeeId = CurrentUserId.ToString();

        var query = _dbContext.VisitReports
            .AsNoTracking()
            .Include(v => v.Location)
            .Where(v => v.StoreId == storeId && v.EmployeeId == employeeId && v.Deleted == null);

        if (fromDate.HasValue)
            query = query.Where(v => v.VisitDate >= fromDate.Value);
        if (toDate.HasValue)
            query = query.Where(v => v.VisitDate <= toDate.Value.AddDays(1));
        if (!string.IsNullOrEmpty(status))
            query = query.Where(v => v.Status == status);

        pageSize = Math.Clamp(pageSize, 10, 200);
        var totalCount = await query.CountAsync();

        var visits = await query
            .OrderByDescending(v => v.VisitDate)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(v => new
            {
                id = v.Id.ToString(),
                employeeId = v.EmployeeId,
                employeeName = v.EmployeeName,
                locationId = v.LocationId.ToString(),
                locationName = v.LocationName,
                locationAddress = v.Location != null ? v.Location.Address : null,
                contactName = v.Location != null ? v.Location.ContactName : null,
                contactPhone = v.Location != null ? v.Location.ContactPhone : null,
                contactEmail = v.Location != null ? v.Location.ContactEmail : null,
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
                reviewNote = v.ReviewNote,
                outsideRadius = v.OutsideRadius,
            })
            .ToListAsync();

        // Parse photos JSON
        var result = visits.Select(v => new
        {
            v.id,
            v.employeeId,
            v.employeeName,
            v.locationId,
            v.locationName,
            v.locationAddress,
            v.contactName,
            v.contactPhone,
            v.contactEmail,
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
            v.reviewNote,
            v.outsideRadius,
        }).ToList();

        return Ok(AppResponse<object>.Success(new { items = result, totalCount, page, pageSize }));
    }

    /// <summary>
    /// NhÃƒÂ¢n viÃƒÂªn xem trÃ¡ÂºÂ¡ng thÃƒÂ¡i check-in hÃƒÂ´m nay
    /// </summary>
    [HttpGet("today")]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.View)]
    public async Task<ActionResult> GetTodayVisits()
    {
        var storeId = RequiredStoreId;
        var employeeId = CurrentUserId.ToString();
        var (_, vnStart, vnEnd) = VnTodayRange();

        var visits = await _dbContext.VisitReports
            .AsNoTracking()
            .Where(v => v.StoreId == storeId
                && v.EmployeeId == employeeId
                && v.VisitDate >= vnStart && v.VisitDate < vnEnd
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
    /// Manager xem tÃ¡ÂºÂ¥t cÃ¡ÂºÂ£ bÃƒÂ¡o cÃƒÂ¡o check-in  
    /// </summary>
    [HttpGet("reports")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.View)]
    public async Task<ActionResult> GetReports(
        [FromQuery] string? employeeId,
        [FromQuery] Guid? locationId,
        [FromQuery] DateTime? fromDate,
        [FromQuery] DateTime? toDate,
        [FromQuery] string? status,
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 50)
    {
        var storeId = RequiredStoreId;
        var query = _dbContext.VisitReports
            .AsNoTracking()
            .Include(v => v.Location)
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

        pageSize = Math.Clamp(pageSize, 10, 200);
        var totalCount = await query.CountAsync();

        var visits = await query
            .OrderByDescending(v => v.VisitDate)
            .Skip((page - 1) * pageSize)
            .Take(pageSize)
            .Select(v => new
            {
                id = v.Id.ToString(),
                employeeId = v.EmployeeId,
                employeeName = v.EmployeeName,
                locationId = v.LocationId.ToString(),
                locationName = v.LocationName,
                locationAddress = v.Location != null ? v.Location.Address : null,
                contactName = v.Location != null ? v.Location.ContactName : null,
                contactPhone = v.Location != null ? v.Location.ContactPhone : null,
                contactEmail = v.Location != null ? v.Location.ContactEmail : null,
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
                outsideRadius = v.OutsideRadius,
            })
            .ToListAsync();

        var result = visits.Select(v => new
        {
            v.id,
            v.employeeId,
            v.employeeName,
            v.locationId,
            v.locationName,
            v.locationAddress,
            v.contactName,
            v.contactPhone,
            v.contactEmail,
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
            v.outsideRadius,
        }).ToList();

        return Ok(AppResponse<object>.Success(new { items = result, totalCount, page, pageSize }));
    }

    /// <summary>
    /// Manager review bÃƒÂ¡o cÃƒÂ¡o check-in
    /// </summary>
    [HttpPost("review/{visitId}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.Approve)]
    public async Task<ActionResult> ReviewVisit(Guid visitId, [FromBody] ReviewVisitRequest request)
    {
        var storeId = RequiredStoreId;
        var report = await _dbContext.VisitReports
            .AsTracking()
            .FirstOrDefaultAsync(v => v.Id == visitId && v.StoreId == storeId && v.Deleted == null);

        if (report == null)
            return NotFound(AppResponse<object>.Fail("KhÃƒÂ´ng tÃƒÂ¬m thÃ¡ÂºÂ¥y bÃ¡ÂºÂ£n ghi"));

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
    /// Manager xem thÃ¡Â»â€˜ng kÃƒÂª check-in theo thÃ¡Â»Âi gian
    /// </summary>
    [HttpGet("summary")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.View)]
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
    /// NhÃƒÂ¢n viÃƒÂªn bÃ¡ÂºÂ¯t Ã„â€˜Ã¡ÂºÂ§u hÃƒÂ nh trÃƒÂ¬nh trong ngÃƒÂ y
    /// </summary>
    [HttpPost("journey/start")]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.Create)]
    public async Task<ActionResult> StartJourney()
    {
        var storeId = RequiredStoreId;
        var employeeId = CurrentUserId.ToString();
        var (today, _, _) = VnTodayRange();

        // Check if journey already exists for today
        var existing = await _dbContext.JourneyTrackings
            .FirstOrDefaultAsync(j => j.StoreId == storeId
                && j.EmployeeId == employeeId
                && j.JourneyDate == today
                && j.Deleted == null);

        if (existing != null && existing.Status == "in_progress")
            return BadRequest(AppResponse<object>.Fail("HÃƒÂ nh trÃƒÂ¬nh hÃƒÂ´m nay Ã„â€˜ang diÃ¡Â»â€¦n ra"));

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
    /// NhÃƒÂ¢n viÃƒÂªn gÃ¡Â»Â­i batch GPS points (gÃ¡Â»Âi mÃ¡Â»â€”i 30s-60s tÃ¡Â»Â« client)
    /// </summary>
    [HttpPost("journey/track")]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.Create)]
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
            return NotFound(AppResponse<object>.Fail("KhÃƒÂ´ng tÃƒÂ¬m thÃ¡ÂºÂ¥y hÃƒÂ nh trÃƒÂ¬nh Ã„â€˜ang hoÃ¡ÂºÂ¡t Ã„â€˜Ã¡Â»â„¢ng"));

        if (request.Points == null || request.Points.Count == 0)
            return Ok(AppResponse<object>.Success(new { saved = 0 }));

        // Append new points to existing route (dedup: skip if within 50m of last point)
        var existingPoints = JsonSerializer.Deserialize<List<RoutePoint>>(journey.RoutePointsJson ?? "[]") ?? new();
        
        var addedCount = 0;
        foreach (var pt in request.Points)
        {
            var lastPt = existingPoints.LastOrDefault();
            if (lastPt != null)
            {
                var distFromLast = CalculateDistance(lastPt.Lat, lastPt.Lng, pt.Latitude, pt.Longitude);
                if (distFromLast < 50) continue; // Skip GPS point within 50m radius
            }
            existingPoints.Add(new RoutePoint
            {
                Lat = pt.Latitude,
                Lng = pt.Longitude,
                Time = pt.Timestamp ?? DateTime.UtcNow,
                Speed = pt.Speed,
            });
            addedCount++;
        }

        // Recalculate total distance from points
        double totalDistanceM = 0;
        for (int i = 1; i < existingPoints.Count; i++)
        {
            totalDistanceM += CalculateDistance(
                existingPoints[i - 1].Lat, existingPoints[i - 1].Lng,
                existingPoints[i].Lat, existingPoints[i].Lng);
        }

        // Detect dwell zones: consecutive points within 50m radius Ã¢â€ â€™ mark dwell time
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

        // Update checked-in count from today's visits (VisitDate is stored in
        // UTC, but JourneyDate is the VN calendar date â€” convert that to a UTC
        // window so the filter matches).
        var journeyDayStart = journey.JourneyDate.AddHours(-7);
        var journeyDayEnd = journeyDayStart.AddDays(1);
        journey.CheckedInCount = await _dbContext.VisitReports
            .CountAsync(v => v.StoreId == storeId
                && v.EmployeeId == employeeId
                && v.VisitDate >= journeyDayStart && v.VisitDate < journeyDayEnd
                && v.Status != "draft"
                && v.Deleted == null);

        // Update on-site minutes
        journey.TotalOnSiteMinutes = await _dbContext.VisitReports
            .Where(v => v.StoreId == storeId
                && v.EmployeeId == employeeId
                && v.VisitDate >= journeyDayStart && v.VisitDate < journeyDayEnd
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
            saved = addedCount,
            totalDistanceKm = journey.TotalDistanceKm,
            totalTravelMinutes = journey.TotalTravelMinutes,
            totalOnSiteMinutes = journey.TotalOnSiteMinutes,
            checkedInCount = journey.CheckedInCount,
            // Return the updated polyline so the client can redraw the route
            // without a second round-trip to /journey/today.
            routePoints = journey.RoutePointsJson,
        }));
    }

    /// <summary>
    /// NhÃƒÂ¢n viÃƒÂªn kÃ¡ÂºÂ¿t thÃƒÂºc hÃƒÂ nh trÃƒÂ¬nh  
    /// </summary>
    [HttpPost("journey/end")]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.Create)]
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
            return NotFound(AppResponse<object>.Fail("KhÃƒÂ´ng tÃƒÂ¬m thÃ¡ÂºÂ¥y hÃƒÂ nh trÃƒÂ¬nh Ã„â€˜ang hoÃ¡ÂºÂ¡t Ã„â€˜Ã¡Â»â„¢ng"));

        var now = DateTime.UtcNow;
        journey.EndTime = now;
        journey.Status = "completed";
        journey.Note = request?.Note;
        journey.UpdatedAt = now;
        journey.UpdatedBy = CurrentUserEmail;

        // Final recalc
        var journeyDayStart = journey.JourneyDate.AddHours(-7);
        var journeyDayEnd = journeyDayStart.AddDays(1);
        journey.CheckedInCount = await _dbContext.VisitReports
            .CountAsync(v => v.StoreId == storeId
                && v.EmployeeId == employeeId
                && v.VisitDate >= journeyDayStart && v.VisitDate < journeyDayEnd
                && v.Status != "draft"
                && v.Deleted == null);

        journey.TotalOnSiteMinutes = await _dbContext.VisitReports
            .Where(v => v.StoreId == storeId
                && v.EmployeeId == employeeId
                && v.VisitDate >= journeyDayStart && v.VisitDate < journeyDayEnd
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
    /// NhÃƒÂ¢n viÃƒÂªn xem hÃƒÂ nh trÃƒÂ¬nh hÃƒÂ´m nay
    /// </summary>
    [HttpGet("journey/today")]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.View)]
    public async Task<ActionResult> GetTodayJourney()
    {
        var storeId = RequiredStoreId;
        var employeeId = CurrentUserId.ToString();
        var (today, _, _) = VnTodayRange();

        var journey = await _dbContext.JourneyTrackings
            .AsNoTracking()
            .FirstOrDefaultAsync(j => j.StoreId == storeId
                && j.EmployeeId == employeeId
                && j.JourneyDate == today
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
    /// Nhân viên xem lịch sử hành trình của chính mình
    /// </summary>
    [HttpGet("journey/my-history")]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.View)]
    public async Task<ActionResult> GetMyJourneyHistory(
        [FromQuery] DateTime? fromDate,
        [FromQuery] DateTime? toDate)
    {
        var storeId = RequiredStoreId;
        var employeeId = CurrentUserId.ToString();
        var from = fromDate ?? DateTime.UtcNow.Date.AddDays(-7);
        var to = toDate ?? DateTime.UtcNow.Date.AddDays(1);

        var journeys = await _dbContext.JourneyTrackings
            .AsNoTracking()
            .Where(j => j.StoreId == storeId
                && j.EmployeeId == employeeId
                && j.Deleted == null
                && j.JourneyDate >= from && j.JourneyDate <= to)
            .OrderByDescending(j => j.JourneyDate)
            .Take(100)
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
    /// Manager xem tÃ¡ÂºÂ¥t cÃ¡ÂºÂ£ hÃƒÂ nh trÃƒÂ¬nh Ã„â€˜ang hoÃ¡ÂºÂ¡t Ã„â€˜Ã¡Â»â„¢ng hÃƒÂ´m nay (live map)
    /// </summary>
    [HttpGet("journey/active")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.View)]
    public async Task<ActionResult> GetActiveJourneys()
    {
        var storeId = RequiredStoreId;
        var (today, vnStart, vnEnd) = VnTodayRange();

        var journeys = await _dbContext.JourneyTrackings
            .AsNoTracking()
            .Where(j => j.StoreId == storeId
                && j.JourneyDate == today
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
                && v.VisitDate >= vnStart && v.VisitDate < vnEnd
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
    /// Nhân viên gửi vị trí GPS hiện tại (gọi định kỳ khi mở app).
    /// Ghi nhận khi: (1) trong ca làm đã duyệt, hoặc (2) thiết bị mobile được bật chấm ngoài CT.
    /// </summary>
    [HttpPost("report-location")]
    [Authorize]
    public async Task<ActionResult> ReportLocation([FromBody] ReportLocationRequest request)
    {
        try
        {
            var storeId = RequiredStoreId;
            var userId = CurrentUserId.ToString();
            if (string.IsNullOrEmpty(userId))
                return BadRequest(AppResponse<object>.Error("Không xác định được nhân viên"));

            if (request.Latitude == 0 && request.Longitude == 0)
                return BadRequest(AppResponse<object>.Error("Tọa độ không hợp lệ"));

            var empRecord = await _dbContext.Employees
                .AsNoTracking()
                .FirstOrDefaultAsync(e => e.StoreId == storeId && e.ApplicationUserId == CurrentUserId && e.Deleted == null);

            var empIdStr = empRecord?.Id.ToString();
            var empCode = empRecord?.EmployeeCode;
            var employeeIdClaim = EmployeeId?.ToString();

            // IgnoreQueryFilters: tránh tenant filter chặn nhầm; so khớp in-memory.
            var outsideDeviceIds = await _dbContext.AuthorizedMobileDevices
                .IgnoreQueryFilters()
                .AsNoTracking()
                .Where(d => d.StoreId == storeId && d.Deleted == null && d.IsAuthorized && d.AllowOutsideCheckIn)
                .Select(d => d.EmployeeId)
                .ToListAsync();

            bool MatchesEmployee(string? deviceEmpId)
            {
                if (string.IsNullOrWhiteSpace(deviceEmpId)) return false;
                return string.Equals(deviceEmpId, userId, StringComparison.OrdinalIgnoreCase)
                    || (empIdStr != null && string.Equals(deviceEmpId, empIdStr, StringComparison.OrdinalIgnoreCase))
                    || (empCode != null && string.Equals(deviceEmpId, empCode, StringComparison.OrdinalIgnoreCase))
                    || (employeeIdClaim != null && string.Equals(deviceEmpId, employeeIdClaim, StringComparison.OrdinalIgnoreCase));
            }

            var allowOutsideCheckIn = outsideDeviceIds.Any(MatchesEmployee);

            if (!allowOutsideCheckIn)
            {
                var nowLocal = DateTime.Now;
                var onShift = await _dbContext.Shifts
                    .AsNoTracking()
                    .AnyAsync(s => s.StoreId == storeId
                        && s.EmployeeUserId == CurrentUserId
                        && s.Status == Domain.Enums.ShiftStatus.Approved
                        && s.StartTime.AddMinutes(-30) <= nowLocal
                        && s.EndTime.AddMinutes(15) >= nowLocal);

                if (!onShift)
                {
                    _logger.LogWarning(
                        "ReportLocation skipped for {UserId} store {StoreId}: not-eligible (allowOutside={AllowOutside}, outsideDevices={DeviceCount})",
                        userId, storeId, allowOutsideCheckIn, outsideDeviceIds.Count);
                    return Ok(AppResponse<object>.Success(new { stored = false, reason = "not-eligible" }));
                }
            }

            var locationKey = empIdStr ?? userId;
            var matchIds = new List<string> { userId };
            if (!string.IsNullOrEmpty(empIdStr)) matchIds.Add(empIdStr);
            if (!string.IsNullOrEmpty(empCode)) matchIds.Add(empCode);

            var updatedRows = await _dbContext.EmployeeLiveLocations
                .IgnoreQueryFilters()
                .Where(l => l.StoreId == storeId && matchIds.Contains(l.EmployeeId))
                .ExecuteUpdateAsync(setters => setters
                    .SetProperty(l => l.EmployeeId, locationKey)
                    .SetProperty(l => l.Latitude, request.Latitude)
                    .SetProperty(l => l.Longitude, request.Longitude)
                    .SetProperty(l => l.Accuracy, request.Accuracy)
                    .SetProperty(l => l.UpdatedAt, DateTime.UtcNow));

            if (updatedRows == 0)
            {
                _dbContext.EmployeeLiveLocations.Add(new EmployeeLiveLocation
                {
                    Id = Guid.NewGuid(),
                    StoreId = storeId,
                    EmployeeId = locationKey,
                    Latitude = request.Latitude,
                    Longitude = request.Longitude,
                    Accuracy = request.Accuracy,
                    UpdatedAt = DateTime.UtcNow,
                });
                await _dbContext.SaveChangesAsync();
            }

            _logger.LogInformation(
                "ReportLocation stored for employee {LocationKey} store {StoreId} lat={Lat} lng={Lng}",
                locationKey, storeId, request.Latitude, request.Longitude);

            return Ok(AppResponse<object>.Success(new { stored = true }));
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "ReportLocation failed for user {UserId}", CurrentUserId);
            // Best-effort: do not break login/app when GPS storage fails (e.g. missing migration).
            return Ok(AppResponse<object>.Success(new { stored = false, reason = "error" }));
        }
    }

    public class ReportLocationRequest
    {
        public double Latitude { get; set; }
        public double Longitude { get; set; }
        public double? Accuracy { get; set; }
    }

    /// <summary>
    /// Manager xem vi tri tat ca nhan vien theo phong ban + lich su check-in hom nay
    /// </summary>
    [HttpGet("employee-locations")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.View)]
    public async Task<ActionResult> GetEmployeeLocations([FromQuery] bool fieldStaffOnly = false)
    {
        var storeId = RequiredStoreId;
        var (today, vnStart, vnEnd) = VnTodayRange();

        // Auto-link Employees.ApplicationUserId where missing
        var unlinkedEmps = await _dbContext.Employees
            .Where(e => e.StoreId == storeId && e.Deleted == null && e.ApplicationUserId == null)
            .ToListAsync();
        if (unlinkedEmps.Count > 0)
        {
            var empCodes = unlinkedEmps.Select(e => e.EmployeeCode).ToList();
            var matchingUsers = await _dbContext.Users
                .Where(u => u.StoreId == storeId && empCodes.Contains(u.UserName!))
                .Select(u => new { u.Id, u.UserName })
                .ToListAsync();
            var userMap = matchingUsers.ToDictionary(u => u.UserName!, u => u.Id);
            foreach (var emp in unlinkedEmps)
            {
                if (userMap.TryGetValue(emp.EmployeeCode, out var userId))
                    emp.ApplicationUserId = userId;
            }
            await _dbContext.SaveChangesAsync();
        }

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
                e.ApplicationUserId,
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
            .Where(j => j.StoreId == storeId && j.JourneyDate == today && j.Deleted == null)
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
            .Where(v => v.StoreId == storeId && v.VisitDate >= vnStart && v.VisitDate < vnEnd && v.Deleted == null)
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
            .Where(m => m.StoreId == storeId && m.PunchTime >= vnStart && m.PunchTime < vnEnd && m.Deleted == null
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

        // 5b. Get live GPS locations reported by devices (last 24h, most recent first)
        var liveCutoff = DateTime.UtcNow.AddHours(-24);
        var liveLocations = await _dbContext.EmployeeLiveLocations
            .AsNoTracking()
            .Where(l => l.StoreId == storeId && l.UpdatedAt >= liveCutoff)
            .OrderByDescending(l => l.UpdatedAt)
            .ToListAsync();

        var outsideDeviceEmpIds = await _dbContext.AuthorizedMobileDevices
            .AsNoTracking()
            .Where(d => d.StoreId == storeId && d.Deleted == null && d.IsAuthorized && d.AllowOutsideCheckIn)
            .Select(d => d.EmployeeId)
            .ToListAsync();

        var outsideCheckInKeys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var id in outsideDeviceEmpIds)
        {
            if (!string.IsNullOrWhiteSpace(id))
                outsideCheckInKeys.Add(id);
        }

        if (outsideCheckInKeys.Count > 0)
        {
            var storeEmployees = await _dbContext.Employees
                .AsNoTracking()
                .Where(e => e.StoreId == storeId && e.Deleted == null)
                .Select(e => new { e.Id, e.EmployeeCode, e.ApplicationUserId })
                .ToListAsync();

            foreach (var emp in storeEmployees)
            {
                var empId = emp.Id.ToString();
                var matchesDevice = outsideCheckInKeys.Contains(empId)
                    || (!string.IsNullOrEmpty(emp.EmployeeCode) && outsideCheckInKeys.Contains(emp.EmployeeCode))
                    || (emp.ApplicationUserId.HasValue && outsideCheckInKeys.Contains(emp.ApplicationUserId.Value.ToString()));
                if (!matchesDevice) continue;

                outsideCheckInKeys.Add(empId);
                if (!string.IsNullOrEmpty(emp.EmployeeCode))
                    outsideCheckInKeys.Add(emp.EmployeeCode);
                if (emp.ApplicationUserId.HasValue)
                    outsideCheckInKeys.Add(emp.ApplicationUserId.Value.ToString());
            }
        }

        // 6. Build result per employee
        // Pre-compute department -> color index so the legend is STABLE across
        // refresh cycles (previously the index was assigned inside the Select,
        // which re-ordered colours whenever the employee list changed order â€”
        // managers saw departments swap colours every 60 seconds).
        var deptColorMap = employees
            .Select(e => e.Department ?? "ChÆ°a phÃ¢n bá»•")
            .Distinct()
            .OrderBy(d => d, StringComparer.OrdinalIgnoreCase)
            .Select((name, idx) => new { name, idx })
            .ToDictionary(x => x.name, x => x.idx);

        var result = employees.Select(emp =>
        {
            var empIdStr = emp.Id.ToString();
            var empCode = emp.EmployeeCode;
            var appUserIdStr = emp.ApplicationUserId?.ToString();
            var deptName = emp.Department ?? "ChÆ°a phÃ¢n bá»•";

            // Colour index was assigned up-front above; safe fallback if a new
            // department name slipped through.
            if (!deptColorMap.ContainsKey(deptName))
                deptColorMap[deptName] = deptColorMap.Count;

            // Find current working location. Each source exposes its own timestamp;
            // we pick the FRESHEST one instead of a fixed hierarchy so a stale
            // morning journey point cannot override a live GPS heartbeat sent
            // 60 seconds ago (this caused the "Quáº£n lÃ½ tab shows yesterday's
            // street" bug). Punch/check-in GPS are used only as last resort.
            double? lat = null, lng = null;
            DateTime? lastUpdate = null;
            string? source = null;

            void consider(double candLat, double candLng, DateTime candTime, string candSource)
            {
                if (candLat == 0 && candLng == 0) return;
                if (lastUpdate == null || candTime > lastUpdate)
                {
                    lat = candLat;
                    lng = candLng;
                    lastUpdate = candTime;
                    source = candSource;
                }
            }

            var journey = todayJourneys.FirstOrDefault(j => j.EmployeeId == empCode || j.EmployeeId == empIdStr || (appUserIdStr != null && j.EmployeeId == appUserIdStr));
            if (journey != null)
            {
                try
                {
                    var points = JsonSerializer.Deserialize<List<RoutePoint>>(journey.RoutePointsJson ?? "[]") ?? new();
                    if (points.Count > 0)
                    {
                        var last = points.Last();
                        if (last.Lat != 0 || last.Lng != 0)
                        {
                            var pointTime = last.Time.Kind == DateTimeKind.Unspecified
                                ? DateTime.SpecifyKind(last.Time, DateTimeKind.Utc)
                                : last.Time.ToUniversalTime();
                            consider(last.Lat, last.Lng, pointTime, "journey");
                        }
                    }
                }
                catch { }
            }

            // Live GPS from device heartbeat (posted every 60s regardless of movement)
            var live = liveLocations.FirstOrDefault(l => l.EmployeeId == empCode || l.EmployeeId == empIdStr || (appUserIdStr != null && l.EmployeeId == appUserIdStr));
            if (live != null && (live.Latitude != 0 || live.Longitude != 0))
            {
                consider(live.Latitude, live.Longitude, live.UpdatedAt, "live");
            }

            // Mobile punch GPS — compete by timestamp (not only when journey/live missing).
            var lastPunch = todayPunches.FirstOrDefault(p => p.OdooEmployeeId == empCode || p.OdooEmployeeId == empIdStr || (appUserIdStr != null && p.OdooEmployeeId == appUserIdStr));
            if (lastPunch?.Latitude != null && lastPunch.Latitude != 0 && lastPunch.Longitude.HasValue)
            {
                var punchTime = lastPunch.PunchTime.Kind == DateTimeKind.Unspecified
                    ? DateTime.SpecifyKind(lastPunch.PunchTime, DateTimeKind.Utc)
                    : lastPunch.PunchTime.ToUniversalTime();
                consider(lastPunch.Latitude.Value, lastPunch.Longitude.Value, punchTime, "punch");
            }

            // Field check-in GPS — lowest priority among timed sources.
            var lastVisit = todayVisits.LastOrDefault(v => v.EmployeeId == empCode || v.EmployeeId == empIdStr || (appUserIdStr != null && v.EmployeeId == appUserIdStr));
            if (lastVisit?.CheckInLatitude != null && lastVisit.CheckInLatitude != 0 && lastVisit.CheckInLongitude.HasValue)
            {
                var visitTime = lastVisit.CheckOutTime ?? lastVisit.CheckInTime ?? vnStart;
                var visitUtc = visitTime.Kind == DateTimeKind.Unspecified
                    ? DateTime.SpecifyKind(visitTime, DateTimeKind.Utc)
                    : visitTime.ToUniversalTime();
                consider(lastVisit.CheckInLatitude.Value, lastVisit.CheckInLongitude.Value, visitUtc, "checkin");
            }

            // Employee's today visits
            var empVisits = todayVisits
                .Where(v => v.EmployeeId == empCode || v.EmployeeId == empIdStr || (appUserIdStr != null && v.EmployeeId == appUserIdStr))
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

            var allowOutsideCheckIn = HasOutsideCheckIn(empIdStr, empCode, appUserIdStr, outsideCheckInKeys);
            var isFieldTracking = fieldStaffOnly
                ? allowOutsideCheckIn
                : IsFieldTrackable(journey, empVisits.Count, source, allowOutsideCheckIn);
            var hasActiveCheckin = empVisits.Any(v => v.Status == "checked_in");
            var isOnline = IsOnlineFieldStaff(
                journey?.Status, source, lastUpdate, hasActiveCheckin, isFieldTracking,
                allowOutsideCheckIn, live?.UpdatedAt);

            if (fieldStaffOnly && allowOutsideCheckIn && !isOnline)
            {
                lat = null;
                lng = null;
            }

            return new
            {
                employeeId = empIdStr,
                employeeCode = empCode,
                applicationUserId = appUserIdStr,
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
                isFieldTracking,
                isOnline,
                allowOutsideCheckIn,
            };
        })
        .OrderBy(e => e.isOnline ? 0 : 1)
        .ThenBy(e => e.departmentColorIndex)
        .ThenBy(e => e.employeeName)
        .ToList();

        if (fieldStaffOnly)
            result = result.Where(e => e.allowOutsideCheckIn).ToList();

        // Include store users who have location data but no Employee record
        var allMatchedIds = new HashSet<string>();
        foreach (var emp in employees)
        {
            allMatchedIds.Add(emp.Id.ToString());
            if (!string.IsNullOrEmpty(emp.EmployeeCode)) allMatchedIds.Add(emp.EmployeeCode);
            if (emp.ApplicationUserId.HasValue) allMatchedIds.Add(emp.ApplicationUserId.Value.ToString());
        }

        var locationUserIds = new HashSet<string>();
        foreach (var j in todayJourneys) if (!string.IsNullOrEmpty(j.EmployeeId)) locationUserIds.Add(j.EmployeeId);
        foreach (var p in todayPunches) if (!string.IsNullOrEmpty(p.OdooEmployeeId)) locationUserIds.Add(p.OdooEmployeeId);
        foreach (var l in liveLocations) if (!string.IsNullOrEmpty(l.EmployeeId)) locationUserIds.Add(l.EmployeeId);

        var unmatchedIds = locationUserIds
            .Where(id => !allMatchedIds.Contains(id) && Guid.TryParse(id, out _))
            .Select(id => Guid.Parse(id))
            .ToList();

        var finalResult = new List<object>(result.Cast<object>());

        if (unmatchedIds.Count > 0)
        {
            var unmatchedUsers = await _dbContext.Users
                .AsNoTracking()
                .Where(u => unmatchedIds.Contains(u.Id) && u.StoreId == storeId)
                .Select(u => new { u.Id, u.UserName, u.FirstName, u.LastName })
                .ToListAsync();

            var unmatchedDept = "ChÆ°a phÃ¢n bá»•";
            if (!deptColorMap.ContainsKey(unmatchedDept))
                deptColorMap[unmatchedDept] = deptColorMap.Count;

            foreach (var user in unmatchedUsers)
            {
                var userIdStr = user.Id.ToString();

                double? uLat = null, uLng = null;
                DateTime? uLastUpdate = null;
                string? uSource = null;

                var uJourney = todayJourneys.FirstOrDefault(j => j.EmployeeId == userIdStr);
                if (uJourney != null)
                {
                    try
                    {
                        var points = JsonSerializer.Deserialize<List<RoutePoint>>(uJourney.RoutePointsJson ?? "[]") ?? new();
                        if (points.Count > 0)
                        {
                            var last = points.Last();
                            if (last.Lat != 0 && last.Lng != 0)
                            { uLat = last.Lat; uLng = last.Lng; uLastUpdate = last.Time; uSource = "journey"; }
                        }
                    }
                    catch { }
                }

                if (uLat == null)
                {
                    var live = liveLocations.FirstOrDefault(l => l.EmployeeId == userIdStr);
                    if (live != null && live.Latitude != 0)
                    { uLat = live.Latitude; uLng = live.Longitude; uLastUpdate = live.UpdatedAt; uSource = "live"; }
                }

                if (uLat == null)
                {
                    var lastPunch = todayPunches.FirstOrDefault(p => p.OdooEmployeeId == userIdStr);
                    if (lastPunch?.Latitude != null && lastPunch.Latitude != 0)
                    { uLat = lastPunch.Latitude; uLng = lastPunch.Longitude; uLastUpdate = lastPunch.PunchTime; uSource = "punch"; }
                }

                if (uLat == null)
                {
                    var lastVisit = todayVisits.LastOrDefault(v => v.EmployeeId == userIdStr);
                    if (lastVisit?.CheckInLatitude != null && lastVisit.CheckInLatitude != 0)
                    { uLat = lastVisit.CheckInLatitude; uLng = lastVisit.CheckInLongitude; uLastUpdate = lastVisit.CheckOutTime ?? lastVisit.CheckInTime; uSource = "checkin"; }
                }

                var uVisits = todayVisits
                    .Where(v => v.EmployeeId == userIdStr)
                    .Select(v => new { v.LocationName, v.CheckInTime, v.CheckOutTime, v.TimeSpentMinutes, v.Status, v.CheckInLatitude, v.CheckInLongitude })
                    .ToList();

                var uAllowOutside = HasOutsideCheckIn(userIdStr, null, userIdStr, outsideCheckInKeys);
                if (fieldStaffOnly && !uAllowOutside) continue;

                var uIsFieldTracking = fieldStaffOnly
                    ? uAllowOutside
                    : IsFieldTrackable(uJourney, uVisits.Count, uSource, uAllowOutside);
                var uHasActiveCheckin = uVisits.Any(v => v.Status == "checked_in");
                var uLive = liveLocations.FirstOrDefault(l => l.EmployeeId == userIdStr);
                var uIsOnline = IsOnlineFieldStaff(
                    uJourney?.Status, uSource, uLastUpdate, uHasActiveCheckin, uIsFieldTracking,
                    uAllowOutside, uLive?.UpdatedAt);

                if (fieldStaffOnly && uAllowOutside && !uIsOnline)
                {
                    uLat = null;
                    uLng = null;
                }

                finalResult.Add(new
                {
                    employeeId = userIdStr,
                    employeeCode = user.UserName ?? "",
                    employeeName = $"{user.LastName} {user.FirstName}".Trim(),
                    department = unmatchedDept,
                    departmentColorIndex = deptColorMap[unmatchedDept],
                    position = "",
                    photoUrl = "",
                    latitude = uLat,
                    longitude = uLng,
                    lastUpdateTime = uLastUpdate,
                    locationSource = uSource,
                    journeyStatus = uJourney?.Status,
                    todayCheckins = uVisits,
                    checkinCount = uVisits.Count,
                    isFieldTracking = uIsFieldTracking,
                    isOnline = uIsOnline,
                    allowOutsideCheckIn = uAllowOutside,
                });
            }
        }

        return Ok(AppResponse<object>.Success(finalResult));
    }

    /// <summary>
    /// Manager xem hÃƒÂ nh trÃƒÂ¬nh cÃ¡Â»Â§a nhÃƒÂ¢n viÃƒÂªn (bÃ¡ÂºÂ£n Ã„â€˜Ã¡Â»â€œ + timeline)
    /// </summary>
    [HttpGet("journey/reports")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.View)]
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
    /// Manager xem chi tiÃ¡ÂºÂ¿t hÃƒÂ nh trÃƒÂ¬nh + visits trong ngÃƒÂ y
    /// </summary>
    [HttpGet("journey/{journeyId}")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.View)]
    public async Task<ActionResult> GetJourneyDetail(Guid journeyId)
    {
        var storeId = RequiredStoreId;

        var journey = await _dbContext.JourneyTrackings
            .AsNoTracking()
            .FirstOrDefaultAsync(j => j.Id == journeyId && j.StoreId == storeId && j.Deleted == null);

        if (journey == null)
            return NotFound(AppResponse<object>.Fail("KhÃƒÂ´ng tÃƒÂ¬m thÃ¡ÂºÂ¥y hÃƒÂ nh trÃƒÂ¬nh"));

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
    /// Manager review hÃƒÂ nh trÃƒÂ¬nh
    /// </summary>
    [HttpPost("journey/{journeyId}/review")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("FieldCheckIn", ModulePermissionAction.Approve)]
    public async Task<ActionResult> ReviewJourney(Guid journeyId, [FromBody] ReviewVisitRequest request)
    {
        var storeId = RequiredStoreId;
        var journey = await _dbContext.JourneyTrackings
            .AsTracking()
            .FirstOrDefaultAsync(j => j.Id == journeyId && j.StoreId == storeId && j.Deleted == null);

        if (journey == null)
            return NotFound(AppResponse<object>.Fail("KhÃƒÂ´ng tÃƒÂ¬m thÃ¡ÂºÂ¥y hÃƒÂ nh trÃƒÂ¬nh"));

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

    private static bool HasOutsideCheckIn(string? empId, string? empCode, string? appUserId, HashSet<string> keys)
    {
        if (keys.Count == 0) return false;
        if (!string.IsNullOrEmpty(empId) && keys.Contains(empId)) return true;
        if (!string.IsNullOrEmpty(empCode) && keys.Contains(empCode)) return true;
        if (!string.IsNullOrEmpty(appUserId) && keys.Contains(appUserId)) return true;
        return false;
    }

    /// <summary>NV thị trường / chấm ngoài CT / có hoạt động check-in hôm nay.</summary>
    private static bool IsFieldTrackable(object? journey, int visitCount, string? source, bool allowOutsideCheckIn = false) =>
        allowOutsideCheckIn || journey != null || visitCount > 0 || source is "journey" or "live" or "checkin";

    private static bool IsOnlineFieldStaff(
        string? journeyStatus, string? source, DateTime? lastUpdate,
        bool hasActiveCheckin, bool isFieldTrackable, bool allowOutsideCheckIn = false,
        DateTime? liveGpsAt = null)
    {
        if (!isFieldTrackable) return false;

        // NV chấm ngoài CT: online theo heartbeat GPS live (≤10 phút), không phụ thuộc
        // nguồn vị trí hiển thị (punch/checkin có thể mới hơn live vài phút).
        if (allowOutsideCheckIn)
            return IsRecentUtc(liveGpsAt, 10);

        if (lastUpdate == null) return false;
        if (!IsRecentUtc(lastUpdate, 10)) return false;

        if (hasActiveCheckin) return true;
        if (journeyStatus == "in_progress") return true;
        return source is "journey" or "live";
    }

    private static bool IsRecentUtc(DateTime? value, int maxMinutes)
    {
        if (value == null) return false;
        var utc = value.Value.Kind == DateTimeKind.Unspecified
            ? DateTime.SpecifyKind(value.Value, DateTimeKind.Utc)
            : value.Value.ToUniversalTime();
        return (DateTime.UtcNow - utc).TotalMinutes <= maxMinutes;
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

