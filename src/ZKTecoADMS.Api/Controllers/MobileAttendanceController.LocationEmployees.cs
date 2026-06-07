using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Text.Json;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;

namespace ZKTecoADMS.Api.Controllers;

public partial class MobileAttendanceController
{
    /// <summary>Vị trí/chi nhánh NV được phép dùng khi chấm (app).</summary>
    [HttpGet("punch-locations")]
    [Authorize]
    [RequireModulePermission("MobileAttendance", ModulePermissionAction.View)]
    public async Task<ActionResult> GetPunchLocations([FromQuery] string? employeeId)
    {
        var storeId = RequiredStoreId;
        var empId = !string.IsNullOrWhiteSpace(employeeId)
            ? employeeId.Trim()
            : CurrentUserId.ToString();
        if (string.IsNullOrWhiteSpace(empId) || empId == Guid.Empty.ToString())
            return BadRequest(AppResponse<object>.Fail("Không xác định được nhân viên"));

        var locations = await GetPunchWorkLocationsForEmployeeAsync(storeId, empId);
        var hasAssignments = await HasEmployeeLocationAssignmentsAsync(storeId, empId);
        var payload = locations.Select(l => new
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
        }).ToList();

        return Ok(AppResponse<object>.Success(new
        {
            employeeId = empId,
            hasEmployeeAssignments = hasAssignments,
            locations = payload,
        }));
    }

    [HttpGet("locations/{locationId:guid}/employees")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("MobileAttendance", ModulePermissionAction.View)]
    public async Task<ActionResult> GetLocationEmployees(Guid locationId)
    {
        var storeId = RequiredStoreId;
        var locExists = await _dbContext.MobileWorkLocations
            .AnyAsync(l => l.Id == locationId && l.StoreId == storeId && l.Deleted == null);
        if (!locExists)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy vị trí"));

        var rows = await _dbContext.MobileLocationEmployees
            .AsNoTracking()
            .Where(x => x.StoreId == storeId && x.WorkLocationId == locationId && x.Deleted == null)
            .OrderBy(x => x.EmployeeName)
            .Select(x => new
            {
                employeeId = x.EmployeeId,
                employeeName = x.EmployeeName,
                assignedAt = x.CreatedAt,
            })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(rows));
    }

    [HttpPut("locations/{locationId:guid}/employees")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireModulePermission("MobileAttendance", ModulePermissionAction.Edit)]
    public async Task<ActionResult> SetLocationEmployees(
        Guid locationId,
        [FromBody] SetLocationEmployeesRequest request)
    {
        var storeId = RequiredStoreId;
        var location = await _dbContext.MobileWorkLocations
            .FirstOrDefaultAsync(l => l.Id == locationId && l.StoreId == storeId && l.Deleted == null);
        if (location == null)
            return NotFound(AppResponse<object>.Fail("Không tìm thấy vị trí"));

        var incoming = (request.Employees ?? new List<LocationEmployeeItem>())
            .Where(e => !string.IsNullOrWhiteSpace(e.EmployeeId))
            .GroupBy(e => e.EmployeeId.Trim(), StringComparer.OrdinalIgnoreCase)
            .Select(g => g.First())
            .ToList();

        var existing = await _dbContext.MobileLocationEmployees
            .Where(x => x.StoreId == storeId && x.WorkLocationId == locationId && x.Deleted == null)
            .ToListAsync();

        var incomingIds = incoming.Select(e => e.EmployeeId.Trim()).ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var row in existing)
        {
            if (!incomingIds.Contains(row.EmployeeId))
            {
                row.Deleted = DateTime.UtcNow;
                row.DeletedBy = CurrentUserEmail;
                row.UpdatedAt = DateTime.UtcNow;
                row.UpdatedBy = CurrentUserEmail;
            }
        }

        var existingIds = existing
            .Where(x => x.Deleted == null)
            .Select(x => x.EmployeeId)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        foreach (var emp in incoming)
        {
            var id = emp.EmployeeId.Trim();
            if (existingIds.Contains(id))
                continue;

            _dbContext.MobileLocationEmployees.Add(new MobileLocationEmployee
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                WorkLocationId = locationId,
                EmployeeId = id,
                EmployeeName = emp.EmployeeName?.Trim() ?? "",
                IsActive = true,
                CreatedAt = DateTime.UtcNow,
                CreatedBy = CurrentUserEmail,
            });
        }

        await _dbContext.SaveChangesAsync();
        _cache.Remove($"work_locations_{storeId}");

        return Ok(AppResponse<object>.Success(new { count = incoming.Count }));
    }

    [HttpGet("locations/active-for-registration")]
    [Authorize]
    [RequireAnyModulePermission(ModulePermissionAction.View, "MobileAttendance", "MobileDeviceRegistration")]
    public async Task<ActionResult> GetLocationsForRegistration()
    {
        var storeId = RequiredStoreId;
        var locations = await _dbContext.MobileWorkLocations
            .AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null && l.IsActive)
            .OrderBy(l => l.Name)
            .Select(l => new
            {
                id = l.Id.ToString(),
                name = l.Name,
                address = l.Address,
                latitude = l.Latitude,
                longitude = l.Longitude,
                radius = l.Radius,
            })
            .ToListAsync();

        return Ok(AppResponse<object>.Success(locations));
    }

    private static List<Guid> ParseLocationIdList(IEnumerable<string>? ids)
    {
        var result = new List<Guid>();
        if (ids == null) return result;
        foreach (var raw in ids)
        {
            if (Guid.TryParse(raw?.Trim(), out var g) && g != Guid.Empty)
                result.Add(g);
        }
        return result.Distinct().ToList();
    }

    private static string SerializeLocationIdList(IEnumerable<Guid> ids) =>
        JsonSerializer.Serialize(ids.Select(x => x.ToString()).ToList());

    private async Task<bool> HasEmployeeLocationAssignmentsAsync(Guid storeId, string employeeId) =>
        await _dbContext.MobileLocationEmployees
            .AnyAsync(x => x.StoreId == storeId
                && x.EmployeeId == employeeId
                && x.Deleted == null);

    private async Task<List<MobileWorkLocation>> GetPunchWorkLocationsForEmployeeAsync(
        Guid storeId,
        string employeeId)
    {
        var assignedIds = await _dbContext.MobileLocationEmployees
            .AsNoTracking()
            .Where(x => x.StoreId == storeId && x.EmployeeId == employeeId && x.Deleted == null)
            .Select(x => x.WorkLocationId)
            .ToListAsync();

        var query = _dbContext.MobileWorkLocations
            .AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null && l.IsActive);

        if (assignedIds.Count > 0)
            query = query.Where(l => assignedIds.Contains(l.Id));

        return await query.ToListAsync();
    }

    private async Task<(bool ok, string? error, List<Guid> ids)> ValidateSelectedWorkLocationIdsAsync(
        Guid storeId,
        IEnumerable<string>? selectedIds)
    {
        var ids = ParseLocationIdList(selectedIds);
        if (ids.Count == 0)
            return (false, "Chọn ít nhất một chi nhánh/vị trí chấm công", ids);

        var valid = await _dbContext.MobileWorkLocations
            .AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null && l.IsActive && ids.Contains(l.Id))
            .Select(l => l.Id)
            .ToListAsync();

        if (valid.Count != ids.Count)
            return (false, "Một hoặc nhiều vị trí chấm công không hợp lệ hoặc đã tắt", ids);

        return (true, null, valid);
    }

    private async Task SyncEmployeeLocationsFromDeviceAsync(
        Guid storeId,
        AuthorizedMobileDevice device,
        bool approved)
    {
        if (!approved || string.IsNullOrWhiteSpace(device.EmployeeId))
            return;

        var ids = ParseLocationIdList(
            string.IsNullOrWhiteSpace(device.SelectedLocationIdsJson)
                ? null
                : JsonSerializer.Deserialize<List<string>>(device.SelectedLocationIdsJson));

        if (ids.Count == 0)
            return;

        var validIds = await _dbContext.MobileWorkLocations
            .AsNoTracking()
            .Where(l => l.StoreId == storeId && l.Deleted == null && ids.Contains(l.Id))
            .Select(l => l.Id)
            .ToListAsync();

        foreach (var locId in validIds)
        {
            var exists = await _dbContext.MobileLocationEmployees
                .FirstOrDefaultAsync(x => x.StoreId == storeId
                    && x.WorkLocationId == locId
                    && x.EmployeeId == device.EmployeeId
                    && x.Deleted == null);

            if (exists != null)
                continue;

            _dbContext.MobileLocationEmployees.Add(new MobileLocationEmployee
            {
                Id = Guid.NewGuid(),
                StoreId = storeId,
                WorkLocationId = locId,
                EmployeeId = device.EmployeeId,
                EmployeeName = device.EmployeeName,
                IsActive = true,
                CreatedAt = DateTime.UtcNow,
                CreatedBy = CurrentUserEmail,
            });
        }

        await _dbContext.SaveChangesAsync();
        _cache.Remove($"work_locations_{storeId}");
    }

    private async Task<object?> BuildSelectedLocationsDtoAsync(
        Guid storeId,
        string? selectedLocationIdsJson)
    {
        var ids = ParseLocationIdList(
            string.IsNullOrWhiteSpace(selectedLocationIdsJson)
                ? null
                : JsonSerializer.Deserialize<List<string>>(selectedLocationIdsJson));

        if (ids.Count == 0)
            return new { ids = Array.Empty<string>(), locations = Array.Empty<object>() };

        var locs = await _dbContext.MobileWorkLocations
            .AsNoTracking()
            .Where(l => l.StoreId == storeId && ids.Contains(l.Id))
            .Select(l => new { id = l.Id.ToString(), name = l.Name, address = l.Address })
            .ToListAsync();

        return new
        {
            ids = ids.Select(x => x.ToString()).ToList(),
            locations = locs,
        };
    }
}

public class SetLocationEmployeesRequest
{
    public List<LocationEmployeeItem> Employees { get; set; } = new();
}

public class LocationEmployeeItem
{
    public string EmployeeId { get; set; } = string.Empty;
    public string? EmployeeName { get; set; }
}
