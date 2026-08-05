using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Commands.DeviceCommands.CreateDeviceCmd;
using ZKTecoADMS.Application.Queries.Attendances.GetAttendancesByDevices;
using ZKTecoADMS.Application.Queries.Attendances.GetMonthlyAttendanceSummary;
using ZKTecoADMS.Application.DTOs.Attendances;
using ZKTecoADMS.Application.DTOs.Devices;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Repositories;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Helpers;
using Microsoft.AspNetCore.Authorization;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.API.Controllers;


[ApiController]
[Route("api/[controller]")]
[Authorize]
public class AttendancesController(
    IMediator bus,
    ZKTecoDbContext dbContext,
    IRepository<Attendance> attendanceRepository,
    IRepository<Employee> employeeRepository,
    IRepository<DeviceUser> deviceUserRepository,
    IRepository<Device> deviceRepository,
    IAttendanceDeletePreparer attendanceDeletePreparer,
    IDataScopeService dataScopeService,
    ILogger<AttendancesController> logger
    )
    : AuthenticatedControllerBase
{
    [HttpPost("devices")]
    [RequireAnyModulePermission(ModulePermissionAction.View, "Attendance", "AttendanceSummary", "AttendanceByShift", "AttendanceReport")]
    public async Task<ActionResult<AppResponse<PagedResult<AttendanceDto>>>> GetAttendanceByDevice(
        [FromQuery] PaginationRequest paginationRequest, [FromBody] GetAttendancesByDeviceRequest filter)
    {
        logger.LogWarning($"[AttendancesController] GetAttendanceByDevice: DeviceIds={string.Join(",", filter.DeviceIds)}, From={filter.FromDate}, To={filter.ToDate}, PageNumber={paginationRequest.PageNumber}, PageSize={paginationRequest.PageSize}");
        
        // Validate DeviceIds belong to user's store (Admin can query any)
        if (!IsAdmin && filter.DeviceIds.Any())
        {
            var storeId = GetCurrentStoreId();
            logger.LogWarning($"[AttendancesController] User StoreId={storeId}, IsAdmin={IsAdmin}");
            var devices = await deviceRepository.GetAllAsync(d => filter.DeviceIds.Contains(d.Id));
            if (devices.Any(d => d.StoreId != storeId))
            {
                logger.LogWarning("[AttendancesController] BLOCKED: Device StoreId mismatch");
                return Ok(AppResponse<PagedResult<AttendanceDto>>.Error("Bạn không có quyền xem dữ liệu chấm công của thiết bị này"));
            }
        }

        // Employee: chỉ xem chấm công của chính mình
        // Manager: xem chấm công của NV thuộc phạm vi quản lý
        if (!IsAdmin)
        {
            var allowedPins = await GetAllowedPinsAsync();
            if (allowedPins != null)
            {
                filter.AllowedPins = allowedPins;
                logger.LogInformation("[AttendancesController] PIN filter applied: {Count} PINs for role {Role}", 
                    allowedPins.Count, CurrentUserRole);
            }
        }

        // Khi client không gửi deviceIds — lấy tất cả máy thuộc cửa hàng (tránh query rỗng).
        if (filter.DeviceIds.Count == 0)
        {
            var storeId = GetCurrentStoreId();
            var deviceQuery = dbContext.Devices.AsQueryable();
            if (!IsAdmin && storeId.HasValue)
                deviceQuery = deviceQuery.Where(d => d.StoreId == storeId);
            filter.DeviceIds = await deviceQuery.Select(d => d.Id).ToListAsync();
        }

        var command = new GetAttsByDevicesQuery(paginationRequest, filter);

        var result = await bus.Send(command);
        if (result.IsSuccess && result.Data?.Items != null)
            result = await EnrichMobileSitePhotosFromDbAsync(result, RequiredStoreId);

        logger.LogWarning(
            "[AttendancesController] Result: IsSuccess={IsSuccess}, ItemCount={ItemCount}, Total={Total}",
            result.IsSuccess,
            result.Data?.Items?.Count() ?? 0,
            result.Data?.TotalCount ?? 0);
        return Ok(result);
    }

    /// <summary>Bổ sung GPS/ảnh hiện trường từ MobileAttendanceRecords (ảnh thường upload sau khi chấm).</summary>
    private async Task<AppResponse<PagedResult<AttendanceDto>>> EnrichMobileSitePhotosFromDbAsync(
        AppResponse<PagedResult<AttendanceDto>> result,
        Guid storeId)
    {
        var list = result.Data!.Items.ToList();
        var mobileIds = list
            .Where(d => d.MobileAttendanceRecordId.HasValue)
            .Select(d => d.MobileAttendanceRecordId!.Value)
            .Distinct()
            .ToList();
        if (mobileIds.Count == 0)
            return result;

        var rows = await dbContext.MobileAttendanceRecords
            .AsNoTracking()
            .Where(r => mobileIds.Contains(r.Id) && r.StoreId == storeId && r.Deleted == null)
            .Select(r => new { r.Id, r.Latitude, r.Longitude, r.LocationName, r.SitePhotoUrl, r.Status })
            .ToListAsync();
        var byId = rows.ToDictionary(r => r.Id);

        for (var i = 0; i < list.Count; i++)
        {
            var dto = list[i];
            if (!dto.MobileAttendanceRecordId.HasValue
                || !byId.TryGetValue(dto.MobileAttendanceRecordId.Value, out var mob))
                continue;

            list[i] = dto with
            {
                Latitude = mob.Latitude ?? dto.Latitude,
                Longitude = mob.Longitude ?? dto.Longitude,
                LocationName = dto.LocationName ?? mob.LocationName,
                SitePhotoUrl = string.Equals(mob.Status, "pending", StringComparison.OrdinalIgnoreCase)
                    ? NormalizeSitePhotoPath(mob.SitePhotoUrl) ?? dto.SitePhotoUrl
                    : null,
            };
        }

        return AppResponse<PagedResult<AttendanceDto>>.Success(
            new PagedResult<AttendanceDto>(list, result.Data));
    }

    private static string? NormalizeSitePhotoPath(string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) return null;
        var p = path.Trim();
        if (p.StartsWith('/')) return p;
        if (p.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
            || p.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            try { return new Uri(p).AbsolutePath; }
            catch { return p; }
        }
        return "/" + p.TrimStart('/');
    }

    /// <summary>Đếm nhanh log chấm công trên server (không tải danh sách) — dùng khi theo dõi đồng bộ.</summary>
    [HttpGet("devices/{deviceId}/count")]
    [RequireModulePermission("Attendance", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<int>>> GetDeviceAttendanceCount(
        Guid deviceId,
        [FromQuery] DateTime? fromDate,
        [FromQuery] DateTime? toDate,
        CancellationToken cancellationToken)
    {
        var device = await deviceRepository.GetByIdAsync(deviceId);
        if (device == null)
        {
            return Ok(AppResponse<int>.Fail("Không tìm thấy thiết bị"));
        }

        if (!IsAdmin && device.StoreId != GetCurrentStoreId())
        {
            return Ok(AppResponse<int>.Fail("Bạn không có quyền xem thiết bị này"));
        }

        var fromInclusive = fromDate?.Date ?? DateTime.UtcNow.AddHours(7).AddYears(-5).Date;
        var toExclusive = (toDate?.Date ?? DateTime.UtcNow.AddHours(7).Date).AddDays(1);

        var count = await dbContext.AttendanceLogs
            .AsNoTracking()
            .CountAsync(
                a => a.DeviceId == deviceId
                     && a.AttendanceTime >= fromInclusive
                     && a.AttendanceTime < toExclusive,
                cancellationToken);

        return Ok(AppResponse<int>.Success(count));
    }

    [HttpGet("devices/{deviceId}/users/{CurrentUserId}")]
    [RequireModulePermission("Attendance", ModulePermissionAction.View)]
    public async Task<ActionResult<IEnumerable<Attendance>>> GetAttendanceByUser(
        Guid deviceId,
        Guid CurrentUserId, 
        [FromQuery] DateTime? startDate, 
        [FromQuery] DateTime? endDate)
    {
        return Ok(null);
    }

    [HttpPost("monthly-summary")]
    [RequireModulePermission("Attendance", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<MonthlyAttendanceSummaryDto>>> GetMonthlyAttendanceSummary(
        [FromQuery] int year,
        [FromQuery] int month,
        [FromBody] GetMonthlyAttendanceSummaryRequest request)
    {
        // Employee: chỉ xem bảng tổng hợp của chính mình
        if (IsEmployee)
        {
            var employeeId = EmployeeId;
            if (!employeeId.HasValue)
            {
                return Ok(AppResponse<MonthlyAttendanceSummaryDto>.Error("Tài khoản chưa liên kết với nhân viên"));
            }
            // Override: chỉ cho xem data của chính mình
            request.EmployeeIds = [employeeId.Value];
        }
        
        // Validate EmployeeIds belong to user's store (Admin can query any)
        if (!IsAdmin && request.EmployeeIds.Any())
        {
            var storeId = GetCurrentStoreId();
            var employees = await employeeRepository.GetAllAsync(e => request.EmployeeIds.Contains(e.Id));
            if (employees.Any(e => e.StoreId != storeId))
            {
                return Ok(AppResponse<MonthlyAttendanceSummaryDto>.Error("Bạn không có quyền xem dữ liệu của nhân viên này"));
            }

            // Manager chỉ được xem NV thuộc phạm vi quản lý
            if (IsManager && storeId.HasValue)
            {
                var subordinateIds = await dataScopeService.GetSubordinateEmployeeIdsAsync(CurrentUserId, storeId.Value);
                var unauthorizedIds = request.EmployeeIds.Except(subordinateIds).ToList();
                if (unauthorizedIds.Any())
                {
                    return Ok(AppResponse<MonthlyAttendanceSummaryDto>.Error("Bạn không có quyền xem dữ liệu của nhân viên ngoài phạm vi quản lý"));
                }
            }
        }

        var query = new GetMonthlyAttendanceSummaryQuery(request.EmployeeIds, year, month);
        return Ok(await bus.Send(query));
    }

    /// <summary>
    /// Xóa chấm công thô theo điều kiện (cửa hàng hiện tại).
    /// </summary>
    [HttpPost("bulk-delete")]
    [RequireModulePermission("Attendance", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<BulkDeleteAttendancesResult>>> BulkDeleteAttendances(
        [FromBody] BulkDeleteAttendancesRequest request,
        CancellationToken cancellationToken)
    {
        try
        {
            var deleted = await ExecuteBulkDeleteAsync(request, cancellationToken);
            return Ok(AppResponse<BulkDeleteAttendancesResult>.Success(
                new BulkDeleteAttendancesResult(deleted)));
        }
        catch (UnauthorizedAccessException ex)
        {
            return Ok(AppResponse<BulkDeleteAttendancesResult>.Fail(ex.Message));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Bulk delete attendances failed");
            return Ok(AppResponse<BulkDeleteAttendancesResult>.Fail(ex.Message));
        }
    }

    /// <summary>
    /// Xóa chấm công thô của một máy (tùy chọn khoảng ngày).
    /// </summary>
    [HttpDelete("devices/{deviceId}")]
    [RequireModulePermission("Attendance", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<BulkDeleteAttendancesResult>>> DeleteAttendancesByDevice(
        Guid deviceId,
        [FromQuery] DateTime? fromDate,
        [FromQuery] DateTime? toDate,
        CancellationToken cancellationToken)
    {
        try
        {
            var deleted = await ExecuteBulkDeleteAsync(
                new BulkDeleteAttendancesRequest
                {
                    DeviceIds = [deviceId],
                    FromDate = fromDate,
                    ToDate = toDate,
                    DeleteAll = fromDate == null && toDate == null,
                },
                cancellationToken);
            return Ok(AppResponse<BulkDeleteAttendancesResult>.Success(
                new BulkDeleteAttendancesResult(deleted)));
        }
        catch (UnauthorizedAccessException ex)
        {
            return Ok(AppResponse<BulkDeleteAttendancesResult>.Fail(ex.Message));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Delete attendances by device failed for {DeviceId}", deviceId);
            return Ok(AppResponse<BulkDeleteAttendancesResult>.Fail(ex.Message));
        }
    }

    private async Task<int> ExecuteBulkDeleteAsync(
        BulkDeleteAttendancesRequest request,
        CancellationToken cancellationToken)
    {
        var storeId = GetCurrentStoreId();
        if (!IsAdmin && !storeId.HasValue)
        {
            throw new UnauthorizedAccessException("Không xác định được cửa hàng");
        }

        var deviceQuery = dbContext.Devices.AsQueryable();
        if (!IsAdmin && storeId.HasValue)
        {
            deviceQuery = deviceQuery.Where(d => d.StoreId == storeId);
        }

        if (request.DeviceIds is { Count: > 0 })
        {
            deviceQuery = deviceQuery.Where(d => request.DeviceIds.Contains(d.Id));
        }

        var allowedDeviceIds = await deviceQuery.Select(d => d.Id).ToListAsync(cancellationToken);
        if (allowedDeviceIds.Count == 0)
        {
            return 0;
        }

        var attendanceQuery = dbContext.AttendanceLogs
            .Where(a => allowedDeviceIds.Contains(a.DeviceId));

        // Cùng quy ước ngày với GetAttendancesByDevices (theo ngày lịch, không lệch giờ).
        if (request.FromDate.HasValue)
        {
            var fromInclusive = request.FromDate.Value.Date;
            attendanceQuery = attendanceQuery.Where(a => a.AttendanceTime >= fromInclusive);
        }

        if (request.ToDate.HasValue)
        {
            var toExclusive = request.ToDate.Value.Date.AddDays(1);
            attendanceQuery = attendanceQuery.Where(a => a.AttendanceTime < toExclusive);
        }

        List<Guid> attendanceIds;

        if (!request.DeleteAll && request.DeviceUserIds is { Count: > 0 })
        {
            var devicePins = await dbContext.DeviceUsers
                .Where(du => request.DeviceUserIds.Contains(du.Id)
                             && allowedDeviceIds.Contains(du.DeviceId))
                .Select(du => new { du.DeviceId, du.Pin })
                .Distinct()
                .ToListAsync(cancellationToken);

            if (devicePins.Count == 0)
            {
                return 0;
            }

            var pinKeys = devicePins
                .Select(dp => $"{dp.DeviceId}|{dp.Pin.Trim().ToUpperInvariant()}")
                .ToHashSet(StringComparer.Ordinal);

            var candidates = await attendanceQuery
                .Select(a => new { a.Id, a.DeviceId, a.PIN })
                .ToListAsync(cancellationToken);

            attendanceIds = candidates
                .Where(a => pinKeys.Contains($"{a.DeviceId}|{(a.PIN ?? "").Trim().ToUpperInvariant()}"))
                .Select(a => a.Id)
                .ToList();
        }
        else
        {
        if (!request.DeleteAll)
        {
            var pins = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            if (request.EmployeeIds is { Count: > 0 })
            {
                var employeePins = await dbContext.DeviceUsers
                    .Where(du => du.EmployeeId != null
                                 && request.EmployeeIds.Contains(du.EmployeeId.Value)
                                 && allowedDeviceIds.Contains(du.DeviceId))
                    .Select(du => du.Pin)
                    .ToListAsync(cancellationToken);

                foreach (var p in employeePins)
                {
                    pins.Add(p);
                }

                var codes = await dbContext.Employees
                    .Where(e => request.EmployeeIds.Contains(e.Id)
                                && (!storeId.HasValue || e.StoreId == storeId))
                    .Select(e => e.EmployeeCode)
                    .ToListAsync(cancellationToken);

                foreach (var code in codes.Where(c => !string.IsNullOrWhiteSpace(c)))
                {
                    pins.Add(code!);
                }
            }

            if (request.BranchIds is { Count: > 0 })
            {
                var branchEmployeeIds = await dbContext.Employees
                    .Where(e => e.BranchId != null
                                && request.BranchIds.Contains(e.BranchId.Value)
                                && (!storeId.HasValue || e.StoreId == storeId))
                    .Select(e => e.Id)
                    .ToListAsync(cancellationToken);

                if (branchEmployeeIds.Count > 0)
                {
                    var branchPins = await dbContext.DeviceUsers
                        .Where(du => du.EmployeeId != null
                                     && branchEmployeeIds.Contains(du.EmployeeId.Value)
                                     && allowedDeviceIds.Contains(du.DeviceId))
                        .Select(du => du.Pin)
                        .ToListAsync(cancellationToken);

                    foreach (var p in branchPins)
                    {
                        pins.Add(p);
                    }

                    var branchCodes = await dbContext.Employees
                        .Where(e => branchEmployeeIds.Contains(e.Id))
                        .Select(e => e.EmployeeCode)
                        .ToListAsync(cancellationToken);

                    foreach (var code in branchCodes.Where(c => !string.IsNullOrWhiteSpace(c)))
                    {
                        pins.Add(code!);
                    }
                }
            }

            if (request.EmployeeIds is { Count: > 0 } || request.BranchIds is { Count: > 0 })
            {
                if (pins.Count == 0)
                {
                    return 0;
                }

                var pinUpper = pins.Select(p => p.Trim().ToUpperInvariant()).ToList();
                attendanceQuery = attendanceQuery.Where(a => pinUpper.Contains(a.PIN.ToUpper()));
            }
        }

            attendanceIds = await attendanceQuery.Select(a => a.Id).ToListAsync(cancellationToken);
        }

        if (attendanceIds.Count == 0)
        {
            return 0;
        }

        var deletedDeviceIds = await dbContext.AttendanceLogs
            .Where(a => attendanceIds.Contains(a.Id))
            .Select(a => a.DeviceId)
            .Distinct()
            .ToListAsync(cancellationToken);
        if (deletedDeviceIds.Count > 0)
        {
            AttendanceBulkDeleteGuard.SuppressAutoSync(deletedDeviceIds, TimeSpan.FromMinutes(20));
        }

        var notifDeleted = await dbContext.Notifications
            .Where(n => n.RelatedEntityType == "Attendance"
                        && n.RelatedEntityId != null
                        && attendanceIds.Contains(n.RelatedEntityId.Value))
            .ExecuteDeleteAsync(cancellationToken);

        if (notifDeleted > 0)
        {
            logger.LogInformation(
                "Removed {NotifCount} attendance notifications for {AttCount} deleted attendance rows",
                notifDeleted, attendanceIds.Count);
        }

        foreach (var attId in attendanceIds)
        {
            await attendanceDeletePreparer.PrepareForDeleteAsync(attId, cancellationToken);
        }

        return await dbContext.AttendanceLogs
            .Where(a => attendanceIds.Contains(a.Id))
            .ExecuteDeleteAsync(cancellationToken);
    }

    /// <summary>
    /// Queue SyncAttendances command for a device (optional date range).
    /// Returns created command id for status polling via GET /api/devicecommands/{id}.
    /// </summary>
    [HttpPost("sync/{deviceId}")]
    [RequireModulePermission("Attendance", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<DeviceCmdDto>>> SyncAttendancesFromDevice(
        Guid deviceId,
        [FromBody] SyncAttendancesFromDeviceRequest? request)
    {
        var device = await deviceRepository.GetByIdAsync(deviceId);
        if (device == null)
        {
            return Ok(AppResponse<DeviceCmdDto>.Fail("Không tìm thấy thiết bị"));
        }

        if (!device.StoreId.HasValue)
        {
            return Ok(AppResponse<DeviceCmdDto>.Fail("Thiết bị chưa được gán cửa hàng — không thể đồng bộ"));
        }

        if (!IsAdmin && device.StoreId != GetCurrentStoreId())
        {
            return Ok(AppResponse<DeviceCmdDto>.Fail("Bạn không có quyền đồng bộ thiết bị này"));
        }

        var start = request?.FromTime ?? DateTime.UtcNow.AddHours(7).AddYears(-5);
        var end = request?.ToTime ?? ClockCommandBuilder.VietnamEndOfToday();
        if (end < start)
        {
            (start, end) = (end, start);
        }

        AttendanceBulkDeleteGuard.ClearAutoSyncSuppress(deviceId);
        AttendanceBulkSyncTracker.ClearUploadActivity(deviceId);

        var commandText = ClockCommandBuilder.BuildGetAttendanceCommand(start, end);
        var cmd = new CreateDeviceCmdCommand(
            deviceId,
            (int)DeviceCommandTypes.SyncAttendances,
            10,
            commandText);

        var result = await bus.Send(cmd);
        logger.LogInformation(
            "[AttendancesController] SyncAttendances queued for device {DeviceId}: {From} — {To}, Success={Success}",
            deviceId, start, end, result.IsSuccess);

        return Ok(result);
    }

    /// <summary>
    /// Create a manual attendance record
    /// </summary>
    [HttpPost("manual")]
    [RequireModulePermission("Attendance", ModulePermissionAction.Create)]
    public async Task<ActionResult<AppResponse<object>>> CreateManualAttendance(
        [FromBody] CreateManualAttendanceRequest request)
    {
        try
        {
            // Validate EmployeeId
            if (request.EmployeeId == Guid.Empty)
            {
                return Ok(AppResponse<object>.Fail("EmployeeId is required"));
            }
            
            var employeeId = request.EmployeeId;
            Guid deviceId;
            if (request.DeviceId.HasValue && request.DeviceId != Guid.Empty)
            {
                deviceId = request.DeviceId.Value;
            }
            else
            {
                var storeId = GetCurrentStoreId();
                var fallbackDevice = storeId.HasValue
                    ? await deviceRepository.GetSingleAsync(d => d.StoreId == storeId.Value)
                    : await deviceRepository.GetSingleAsync(d => true);
                if (fallbackDevice == null)
                    return Ok(AppResponse<object>.Fail("Không tìm thấy thiết bị chấm công. Vui lòng cấu hình máy hoặc chọn thiết bị."));
                deviceId = fallbackDevice.Id;
            }
            
            // Validate device belongs to user's store
            if (!IsAdmin)
            {
                var device = await deviceRepository.GetByIdAsync(deviceId);
                if (device == null || device.StoreId != GetCurrentStoreId())
                {
                    return Ok(AppResponse<object>.Fail("Bạn không có quyền tạo chấm công cho thiết bị này"));
                }
            }

            // Get employee to get PIN
            var employee = await employeeRepository.GetByIdAsync(employeeId);
            if (employee == null)
            {
                return Ok(AppResponse<object>.Fail("Employee not found"));
            }

            // Validate manager can only create attendance for subordinates
            if (!IsAdmin && IsManager && GetCurrentStoreId().HasValue)
            {
                var subordinateIds = await dataScopeService.GetSubordinateEmployeeIdsAsync(CurrentUserId, GetCurrentStoreId()!.Value);
                if (!subordinateIds.Contains(employeeId))
                {
                    return Ok(AppResponse<object>.Fail("Bạn không có quyền tạo chấm công cho nhân viên này"));
                }
            }

            // DeviceUser phải thuộc đúng máy ghi chấm — không lấy DU máy khác (FK lẫn DeviceId).
            var deviceUser = await deviceUserRepository.GetSingleAsync(
                du => du.EmployeeId == employeeId && du.DeviceId == deviceId);

            var employeeName = $"{employee.LastName} {employee.FirstName}".Trim();
            if (string.IsNullOrWhiteSpace(employeeName))
                employeeName = employee.EmployeeCode ?? "NV";

            if (deviceUser == null)
            {
                var preferredPin = (employee.EmployeeCode ?? string.Empty).Trim();
                if (preferredPin.Length > 20)
                    preferredPin = preferredPin[..20];
                if (string.IsNullOrWhiteSpace(preferredPin))
                    preferredPin = employeeId.ToString("N")[..8];

                // PIN đã có trên máy: gắn Employee nếu trống, hoặc cấp PIN mới nếu đang thuộc NV khác.
                var pinOwner = await deviceUserRepository.GetSingleAsync(
                    du => du.DeviceId == deviceId && du.Pin == preferredPin);
                if (pinOwner != null && pinOwner.EmployeeId == null)
                {
                    pinOwner.EmployeeId = employeeId;
                    if (string.IsNullOrWhiteSpace(pinOwner.Name))
                        pinOwner.Name = employeeName;
                    await deviceUserRepository.UpdateAsync(pinOwner);
                    deviceUser = pinOwner;
                }
                else if (pinOwner == null)
                {
                    deviceUser = new DeviceUser
                    {
                        Id = Guid.NewGuid(),
                        Pin = preferredPin,
                        Name = employeeName.Length > 200 ? employeeName[..200] : employeeName,
                        DeviceId = deviceId,
                        EmployeeId = employeeId,
                        IsActive = true,
                        GroupId = 1,
                        Privilege = 0,
                        VerifyMode = 0,
                        CreatedAt = DateTime.UtcNow
                    };
                    await deviceUserRepository.AddAsync(deviceUser);
                }
                else
                {
                    // preferredPin đã thuộc NV khác — tạo DU với PIN tuần tự ngắn.
                    var onDevice = await deviceUserRepository.GetAllAsync(du => du.DeviceId == deviceId);
                    var used = onDevice.Select(u => u.Pin).ToHashSet(StringComparer.Ordinal);
                    var allocated = DeviceUserPinAllocator.AllocateSequential(used);
                    deviceUser = new DeviceUser
                    {
                        Id = Guid.NewGuid(),
                        Pin = allocated,
                        Name = employeeName.Length > 200 ? employeeName[..200] : employeeName,
                        DeviceId = deviceId,
                        EmployeeId = employeeId,
                        IsActive = true,
                        GroupId = 1,
                        Privilege = 0,
                        VerifyMode = 0,
                        CreatedAt = DateTime.UtcNow
                    };
                    await deviceUserRepository.AddAsync(deviceUser);
                }
            }

            // Auto-calculate AttendanceState based on the order of attendances in the day
            // Odd = Check-in (0), Even = Check-out (1)
            var dateOnly = request.PunchTime.Date;
            var pin = deviceUser.Pin;
            var dailyAttendances = await attendanceRepository
                .GetAllAsync(a => a.DeviceId == deviceId
                               && a.PIN == pin
                               && a.AttendanceTime.Date == dateOnly);

            var sortedAttendances = dailyAttendances
                .OrderBy(a => a.AttendanceTime)
                .ToList();

            // Find the position of this new attendance in the timeline
            int position = sortedAttendances.Count(a => a.AttendanceTime < request.PunchTime) + 1;

            // Odd position = Check-in (0), Even position = Check-out (1)
            var attendanceState = (position % 2 == 1) ? AttendanceStates.CheckIn : AttendanceStates.CheckOut;

            // WorkCode: Store employee name for manual attendance display (max 10 chars as per DB constraint)
            var workCode = employeeName.Length > 10
                ? employeeName.Substring(0, 10)
                : employeeName;

            if (await attendanceRepository.ExistsAsync(a =>
                    a.DeviceId == deviceId
                    && a.PIN == pin
                    && a.AttendanceTime == request.PunchTime))
            {
                return Ok(AppResponse<object>.Fail(
                    "Bản ghi chấm công đã tồn tại (trùng máy, mã PIN và thời gian)"));
            }

            var attendance = new Attendance
            {
                Id = Guid.NewGuid(),
                EmployeeId = deviceUser.Id, // FK DeviceUser trên đúng máy
                DeviceId = deviceId,
                PIN = pin,
                AttendanceTime = request.PunchTime,
                VerifyMode = VerifyModes.Manual, // Manual attendance = 100
                AttendanceState = attendanceState,
                WorkCode = workCode,
                Note = request.Note, // Full note
                CreatedAt = DateTime.UtcNow
            };

            await attendanceRepository.AddAsync(attendance);

            return Ok(AppResponse<object>.Success(new
            {
                Id = attendance.Id,
                EmployeeId = attendance.EmployeeId,
                DeviceId = attendance.DeviceId,
                AttendanceTime = attendance.AttendanceTime,
                VerifyMode = (int)attendance.VerifyMode,
                AttendanceState = (int)attendance.AttendanceState,
                WorkCode = attendance.WorkCode,
                EmployeeName = employeeName, // Return full name
                EmployeeCode = employee.EmployeeCode,
                Note = request.Note, // Return original note
                CreatedAt = attendance.CreatedAt
            }));
        }
        catch (Exception ex)
        {
            // Log detailed error
            var innerMessage = ex.InnerException?.Message ?? ex.Message;
            Console.WriteLine($"[CreateManualAttendance] Error: {ex.Message}");
            Console.WriteLine($"[CreateManualAttendance] Inner: {innerMessage}");
            Console.WriteLine($"[CreateManualAttendance] Stack: {ex.StackTrace}");
            return Ok(AppResponse<object>.Fail(innerMessage));
        }
    }

    /// <summary>
    /// Update an attendance record
    /// </summary>
    [HttpPut("{id}")]
    [RequireModulePermission("Attendance", ModulePermissionAction.Edit)]
    public async Task<ActionResult<AppResponse<bool>>> UpdateAttendance(
        Guid id, [FromBody] UpdateAttendanceRequest request)
    {
        try
        {
            var attendance = await attendanceRepository.GetByIdAsync(id);
            if (attendance == null)
            {
                return Ok(AppResponse<bool>.Fail("Không tìm thấy bản ghi chấm công"));
            }

            attendance.AttendanceTime = request.AttendanceTime;
            
            // Auto-calculate AttendanceState based on the order of attendances in the day
            // Odd = Check-in (0), Even = Check-out (1)
            var dateOnly = request.AttendanceTime.Date;
            var employeeId = attendance.EmployeeId;
            
            // Get all attendances for this employee on this date, sorted by time
            var dailyAttendances = await attendanceRepository
                .GetAllAsync(a => a.EmployeeId == employeeId && 
                               a.AttendanceTime.Date == dateOnly &&
                               a.Id != id);
            
            var sortedAttendances = dailyAttendances
                .OrderBy(a => a.AttendanceTime)
                .ToList();
            
            // Find the position of this attendance in the timeline
            int position = sortedAttendances.Count(a => a.AttendanceTime < request.AttendanceTime) + 1;
            
            // Odd position = Check-in (0), Even position = Check-out (1)
            attendance.AttendanceState = (position % 2 == 1) ? AttendanceStates.CheckIn : AttendanceStates.CheckOut;

            await attendanceRepository.UpdateAsync(attendance);

            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<bool>.Fail(ex.Message));
        }
    }

    /// <summary>
    /// Delete an attendance record
    /// </summary>
    [HttpDelete("{id}")]
    [RequireModulePermission("Attendance", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<bool>>> DeleteAttendance(Guid id)
    {
        try
        {
            var attendance = await attendanceRepository.GetByIdAsync(id);
            if (attendance == null)
            {
                return Ok(AppResponse<bool>.Fail("Không tìm thấy bản ghi chấm công"));
            }

            await attendanceDeletePreparer.PrepareForDeleteAsync(id);
            await attendanceRepository.DeleteAsync(attendance);
            AttendanceBulkDeleteGuard.SuppressAutoSync(
                new[] { attendance.DeviceId },
                TimeSpan.FromMinutes(20));

            return Ok(AppResponse<bool>.Success(true));
        }
        catch (Exception ex)
        {
            return Ok(AppResponse<bool>.Fail(DbExceptionMessageHelper.ToUserMessage(ex)));
        }
    }

    /// <summary>
    /// Get PINs the current user is allowed to see.
    /// Employee: only their own PINs. Manager: subordinate employee PINs.
    /// Returns null for Admin (no filter needed).
    /// </summary>
    private async Task<List<string>?> GetAllowedPinsAsync()
    {
        if (IsAdmin) return null;

        var storeId = GetCurrentStoreId();
        
        // Employee role: chỉ xem PIN của chính mình
        if (IsEmployee)
        {
            var employeeId = EmployeeId;
            if (!employeeId.HasValue)
            {
                return []; // No employee linked → no data
            }
            var myDeviceUsers = await deviceUserRepository.GetAllAsync(du => du.EmployeeId == employeeId.Value);
            var pins = myDeviceUsers.Select(du => du.Pin).Distinct().ToList();
            if (pins.Count > 0)
                return pins;

            // NV chỉ chấm mobile — có thể chưa có DeviceUser cho đến khi sync log đầu tiên.
            var emp = await employeeRepository.GetByIdAsync(employeeId.Value, cancellationToken: default);
            if (!string.IsNullOrWhiteSpace(emp?.EmployeeCode))
                return [emp.EmployeeCode.Trim()];
            return [];
        }

        // Manager role: xem PIN của NV thuộc phạm vi quản lý
        if (IsManager && storeId.HasValue)
        {
            var subordinateIds = await dataScopeService.GetSubordinateEmployeeIdsAsync(CurrentUserId, storeId.Value);
            if (subordinateIds.Count == 0) return [];
            
            var deviceUsers = await deviceUserRepository.GetAllAsync(
                du => du.EmployeeId.HasValue && subordinateIds.Contains(du.EmployeeId.Value));
            return deviceUsers.Select(du => du.Pin).Distinct().ToList();
        }

        return null; // Fallback: no filter
    }

    /// <summary>
    /// Dọn bản ghi chấm công trùng (cùng DeviceId + PIN + AttendanceTime), giữ bản CreatedAt sớm nhất.
    /// </summary>
    [HttpPost("dedupe-duplicates")]
    [RequireModulePermission("Attendance", ModulePermissionAction.Delete)]
    public async Task<ActionResult<AppResponse<DedupeAttendancesResult>>> DedupeDuplicateAttendances(
        CancellationToken cancellationToken)
    {
        try
        {
            const string sql = """
                DELETE FROM "AttendanceLogs" a
                WHERE a."Id" IN (
                    SELECT al."Id"
                    FROM (
                        SELECT "Id",
                               ROW_NUMBER() OVER (
                                   PARTITION BY "DeviceId", "PIN", "AttendanceTime"
                                   ORDER BY "CreatedAt" ASC, "Id" ASC
                               ) AS rn
                        FROM "AttendanceLogs"
                    ) al
                    WHERE al.rn > 1
                );
                """;

            var deleted = await dbContext.Database.ExecuteSqlRawAsync(sql, cancellationToken);
            logger.LogWarning(
                "DedupeDuplicateAttendances by user {UserId}: removed {Count} duplicate rows",
                CurrentUserId, deleted);

            return Ok(AppResponse<DedupeAttendancesResult>.Success(new DedupeAttendancesResult(deleted)));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Dedupe duplicate attendances failed");
            return Ok(AppResponse<DedupeAttendancesResult>.Fail(ex.Message));
        }
    }
}

public record DedupeAttendancesResult(int DeletedCount);

public class CreateManualAttendanceRequest
{
    public Guid EmployeeId { get; set; }
    public Guid? DeviceId { get; set; }
    public DateTime PunchTime { get; set; }
    public int VerifyType { get; set; } = 100;
    public string? Note { get; set; }
    public bool IsManual { get; set; } = true;
}

public class UpdateAttendanceRequest
{
    public DateTime AttendanceTime { get; set; }
    // AttendanceState is auto-calculated based on order of attendances in the day
    // Odd position = Check-in (0), Even position = Check-out (1)
}

public class GetMonthlyAttendanceSummaryRequest
{
    public List<Guid> EmployeeIds { get; set; } = [];
}

public class SyncAttendancesFromDeviceRequest
{
    public DateTime? FromTime { get; set; }
    public DateTime? ToTime { get; set; }
}

public class BulkDeleteAttendancesRequest
{
    public DateTime? FromDate { get; set; }
    public DateTime? ToDate { get; set; }
    public bool DeleteAll { get; set; }
    public List<Guid>? EmployeeIds { get; set; }
    public List<Guid>? BranchIds { get; set; }
    public List<Guid>? DeviceIds { get; set; }
    /// <summary>Nhân viên đã đăng ký trên máy chấm công (DeviceUser) — xóa đúng theo máy + PIN.</summary>
    public List<Guid>? DeviceUserIds { get; set; }
}

public record BulkDeleteAttendancesResult(int DeletedCount);
