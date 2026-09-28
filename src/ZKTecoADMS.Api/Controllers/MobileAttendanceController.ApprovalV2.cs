using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Text.Json;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Controllers;

public class MobileBulkApproveRequest
{
    public List<Guid> Ids { get; set; } = [];
    public bool Approved { get; set; } = true;
    public string? Reason { get; set; }
}

public class MobileApprovalSettingsDto
{
    public bool AutoApproveTrusted { get; set; } = true;
    public int TrustedMaxDistanceMeters { get; set; } = 300;
    public double TrustedMinFaceScore { get; set; } = 85;
    public int EvidenceRetentionDays { get; set; } = 30;
}

public class MobileOutsideReasonFlagRequest
{
    public List<Guid> DeviceIds { get; set; } = [];
    public bool Value { get; set; }
}

/// <summary>Duyệt chấm công v2: chấm điểm rủi ro, duyệt hàng loạt, ngữ cảnh ngày công, cài đặt tự duyệt / lý do.</summary>
public partial class MobileAttendanceController
{
    // ─── Hỗ trợ chấm công ────────────────────────────────────────────

    private async Task<Employee?> ResolvePunchEmployeeAsync(Guid storeId, string odooEmployeeId)
    {
        if (string.IsNullOrWhiteSpace(odooEmployeeId)) return null;
        if (Guid.TryParse(odooEmployeeId, out var gid))
        {
            var byId = await _dbContext.Employees.AsNoTracking()
                .FirstOrDefaultAsync(e => e.StoreId == storeId && (e.ApplicationUserId == gid || e.Id == gid));
            if (byId != null) return byId;
        }
        return await _dbContext.Employees.AsNoTracking()
            .FirstOrDefaultAsync(e => e.StoreId == storeId && e.EmployeeCode == odooEmployeeId);
    }

    /// <summary>Lịch làm việc (giờ bắt đầu/kết thúc) của nhân viên trong ngày.</summary>
    private async Task<(TimeSpan start, TimeSpan end, string? name)?> ResolveDayShiftAsync(Guid employeeId, DateTime localDate)
    {
        var d = localDate.Date;
        var ws = await _dbContext.WorkSchedules.AsNoTracking()
            .Include(w => w.Shift)
            .Where(w => w.EmployeeUserId == employeeId && w.Date >= d && w.Date < d.AddDays(1) && !w.IsDayOff)
            .OrderBy(w => w.StartTime)
            .FirstOrDefaultAsync();
        if (ws == null) return null;
        var start = ws.StartTime ?? ws.Shift?.StartTime;
        var end = ws.EndTime ?? ws.Shift?.EndTime;
        if (start == null || end == null) return null;
        return (start.Value, end.Value, ws.Shift?.Name);
    }

    private static int? MinutesFromShift((TimeSpan start, TimeSpan end, string? name)? shift, DateTime punchLocal, int punchType)
    {
        if (shift == null) return null;
        var t = punchLocal.TimeOfDay;
        var target = punchType is 1 or 5 ? shift.Value.end : punchType is 0 or 4 ? shift.Value.start : (TimeSpan?)null;
        if (target == null)
        {
            // Chấm đi đường: chỉ tính lệch nếu nằm ngoài khung ca
            if (t >= shift.Value.start && t <= shift.Value.end) return 0;
            return (int)Math.Min(Math.Abs((t - shift.Value.start).TotalMinutes), Math.Abs((t - shift.Value.end).TotalMinutes));
        }
        return (int)Math.Abs((t - target.Value).TotalMinutes);
    }

    private async Task<MobilePunchRisk> ScoreOutsidePunchAsync(
        Guid storeId, MobilePunchRequest request, MobileAttendanceSetting? settings, double? distance, double nearestRadius,
        double? faceScore, bool hasSitePhoto, DateTime punchLocal, bool isTravel)
    {
        var monthStart = new DateTime(punchLocal.Year, punchLocal.Month, 1);
        var outsideCount = await _dbContext.MobileAttendanceRecords.AsNoTracking()
            .CountAsync(r => r.StoreId == storeId && r.OdooEmployeeId == request.EmployeeId && r.IsOutside
                && r.PunchTime >= monthStart && r.Deleted == null);
        int? minutesFromShift = null;
        try
        {
            var emp = await ResolvePunchEmployeeAsync(storeId, request.EmployeeId);
            if (emp != null)
                minutesFromShift = MinutesFromShift(await ResolveDayShiftAsync(emp.Id, punchLocal), punchLocal, request.PunchType);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Risk: cannot resolve shift for {Emp}", request.EmployeeId);
        }
        return MobilePunchRiskScorer.Score(new MobilePunchRiskInput
        {
            Distance = distance,
            Radius = nearestRadius,
            GpsAccuracy = request.GpsAccuracy,
            FaceScore = faceScore,
            LivenessPassed = request.LivenessPassed || faceScore == null,
            HasSitePhoto = hasSitePhoto,
            HasReason = !string.IsNullOrWhiteSpace(request.OutsideReason),
            OutsideCountThisMonth = outsideCount,
            MinutesFromShift = minutesFromShift,
            IsTravel = isTravel,
        }, settings?.TrustedMaxDistanceMeters ?? 300, settings?.TrustedMinFaceScore ?? 85);
    }

    /// <summary>Người nhận thông báo chờ duyệt: quản lý trực tiếp; không có thì toàn bộ quản lý cửa hàng.</summary>
    private async Task<List<Guid>> ResolvePunchApproversAsync(Guid storeId, string odooEmployeeId)
    {
        try
        {
            var emp = await ResolvePunchEmployeeAsync(storeId, odooEmployeeId);
            if (emp?.DirectManagerEmployeeId != null)
            {
                var mgrUser = await _dbContext.Employees.AsNoTracking()
                    .Where(e => e.Id == emp.DirectManagerEmployeeId && e.ApplicationUserId != null)
                    .Select(e => e.ApplicationUserId)
                    .FirstOrDefaultAsync();
                if (mgrUser.HasValue && await _dbContext.Users.AnyAsync(u => u.Id == mgrUser.Value && u.IsActive))
                    return [mgrUser.Value];
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Resolve direct manager failed for {Emp}", odooEmployeeId);
        }
        return await _dbContext.Users
            .Where(u => u.StoreId == storeId && u.IsActive
                && (u.Role == "Manager" || u.Role == "Admin" || u.Role == "StoreOwner"))
            .Select(u => u.Id)
            .ToListAsync();
    }

    // ─── Duyệt hàng loạt ──────────────────────────────────────────────

    private async Task<(bool ok, string? error)> DecideMobileRecordAsync(MobileAttendanceRecord record, bool approved, string? reason)
    {
        record.Status = approved ? "approved" : "rejected";
        record.ApprovedBy = CurrentUserEmail;
        record.ApprovedAt = DateTime.UtcNow;
        record.RejectReason = approved ? null : reason;
        record.UpdatedAt = DateTime.UtcNow;
        record.UpdatedBy = CurrentUserEmail;
        await _dbContext.SaveChangesAsync();
        if (approved && !await SyncMobileRecordToAttendanceLog(record))
            return (false, $"{record.EmployeeName}: đã duyệt nhưng chưa ghi được vào dữ liệu chấm công");
        await NotifyMobileDecisionAsync(record, approved, reason);
        return (true, null);
    }

    private async Task NotifyMobileDecisionAsync(MobileAttendanceRecord record, bool approved, string? reason)
    {
        try
        {
            if (!Guid.TryParse(record.OdooEmployeeId, out var empUserId)) return;
            var label = record.PunchType switch { 0 => "vào", 1 => "ra", 2 => "bắt đầu đi", 3 => "đến điểm làm", _ => "chấm" };
            var time = record.PunchTime.ToString("HH:mm dd/MM/yyyy");
            await _systemNotificationService.CreateAndSendAsync(
                empUserId,
                approved ? NotificationType.Success : NotificationType.Warning,
                approved ? "Chấm công Mobile đã được duyệt" : "Chấm công Mobile bị từ chối",
                approved
                    ? $"Chấm công {label} lúc {time} đã được duyệt"
                    : $"Chấm công {label} lúc {time} bị từ chối" + (string.IsNullOrWhiteSpace(reason) ? "" : $". Lý do: {reason}")
                      + ". Bạn có thể gửi giải trình / xin bổ sung công.",
                relatedEntityType: "MobileAttendance",
                relatedEntityId: record.Id,
                fromUserId: CurrentUserId,
                categoryCode: "mobile_attendance",
                storeId: record.StoreId);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Notify mobile decision failed {Id}", record.Id);
        }
    }

    [HttpPost("approve-bulk")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Approve, "AttendanceApproval", "MobileAttendanceApproval")]
    public async Task<ActionResult> ApproveBulk([FromBody] MobileBulkApproveRequest request)
    {
        if (!request.Approved && string.IsNullOrWhiteSpace(request.Reason))
            return Ok(AppResponse<object>.Fail("Vui lòng nhập lý do từ chối"));
        var storeId = RequiredStoreId;
        var ids = request.Ids.Distinct().Take(500).ToList();
        var records = await _dbContext.MobileAttendanceRecords.AsTracking()
            .Where(r => ids.Contains(r.Id) && r.StoreId == storeId && r.Deleted == null && r.Status == "pending")
            .OrderBy(r => r.PunchTime)
            .ToListAsync();
        return Ok(AppResponse<object>.Success(await DecideManyAsync(records, request.Approved, request.Reason, ids.Count)));
    }

    /// <summary>Duyệt toàn bộ bản chờ duyệt được chấm «tin cậy» (không gồm chấm đi đường).</summary>
    [HttpPost("approve-trusted")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Approve, "AttendanceApproval", "MobileAttendanceApproval")]
    public async Task<ActionResult> ApproveTrusted()
    {
        var storeId = RequiredStoreId;
        var records = await _dbContext.MobileAttendanceRecords.AsTracking()
            .Where(r => r.StoreId == storeId && r.Deleted == null && r.Status == "pending"
                && r.RiskLevel == MobilePunchRiskScorer.Trusted && r.PunchType != 2 && r.PunchType != 3)
            .OrderBy(r => r.PunchTime)
            .Take(500)
            .ToListAsync();
        return Ok(AppResponse<object>.Success(await DecideManyAsync(records, true, null, records.Count)));
    }

    private async Task<object> DecideManyAsync(List<MobileAttendanceRecord> records, bool approved, string? reason, int requested)
    {
        var ok = 0;
        var errors = new List<string>();
        foreach (var r in records)
        {
            try
            {
                var (done, err) = await DecideMobileRecordAsync(r, approved, reason);
                if (done) ok++;
                else if (err != null) errors.Add(err);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Bulk decide failed {Id}", r.Id);
                errors.Add($"{r.EmployeeName}: lỗi xử lý");
            }
        }
        return new { success = ok, failed = requested - ok, errors };
    }

    // ─── Ngữ cảnh ngày công để quyết định ─────────────────────────────

    [HttpGet("records/{recordId:guid}/context")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "MobileAttendance", "MobileAttendanceApproval", "AttendanceApproval")]
    public async Task<ActionResult> GetRecordContext(Guid recordId)
    {
        var storeId = RequiredStoreId;
        var r = await _dbContext.MobileAttendanceRecords.AsNoTracking()
            .FirstOrDefaultAsync(x => x.Id == recordId && x.StoreId == storeId && x.Deleted == null);
        if (r == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy bản ghi"));

        var day = r.PunchTime.Date;
        var sameDay = await _dbContext.MobileAttendanceRecords.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.OdooEmployeeId == r.OdooEmployeeId && x.Deleted == null
                && x.PunchTime >= day && x.PunchTime < day.AddDays(1))
            .OrderBy(x => x.PunchTime)
            .Select(x => new { id = x.Id, x.PunchTime, x.PunchType, x.Status, x.LocationName, x.DistanceFromLocation, x.IsOutside })
            .ToListAsync();

        var emp = await ResolvePunchEmployeeAsync(storeId, r.OdooEmployeeId);
        object? shift = null;
        var logs = new List<object>();
        var outsideMonth = 0;
        var history = new List<object>();
        if (emp != null)
        {
            var s = await ResolveDayShiftAsync(emp.Id, day);
            if (s != null) shift = new { name = s.Value.name, start = s.Value.start.ToString(@"hh\:mm"), end = s.Value.end.ToString(@"hh\:mm") };
            var pins = await _dbContext.DeviceUsers.AsNoTracking()
                .Where(u => u.EmployeeId == emp.Id).Select(u => u.Id).ToListAsync();
            if (pins.Count > 0)
            {
                logs.AddRange(await _dbContext.AttendanceLogs.AsNoTracking()
                    .Where(a => a.EmployeeId != null && pins.Contains(a.EmployeeId.Value)
                        && a.AttendanceTime >= day && a.AttendanceTime < day.AddDays(1))
                    .OrderBy(a => a.AttendanceTime)
                    .Select(a => (object)new { a.AttendanceTime, a.Note, fromMobile = a.MobileAttendanceRecordId != null })
                    .ToListAsync());
            }
        }
        var monthStart = new DateTime(day.Year, day.Month, 1);
        outsideMonth = await _dbContext.MobileAttendanceRecords.AsNoTracking()
            .CountAsync(x => x.StoreId == storeId && x.OdooEmployeeId == r.OdooEmployeeId && x.IsOutside
                && x.PunchTime >= monthStart && x.PunchTime < monthStart.AddMonths(1) && x.Deleted == null);
        history.AddRange(await _dbContext.MobileAttendanceRecords.AsNoTracking()
            .Where(x => x.StoreId == storeId && x.OdooEmployeeId == r.OdooEmployeeId && x.IsOutside && x.Id != r.Id
                && x.Deleted == null && x.Status != "pending")
            .OrderByDescending(x => x.PunchTime)
            .Take(6)
            .Select(x => (object)new { x.PunchTime, x.Status, x.LocationName, x.DistanceFromLocation, x.RejectReason })
            .ToListAsync());

        var locations = await GetPunchWorkLocationsForEmployeeAsync(storeId, r.OdooEmployeeId);
        var device = r.DeviceId == null ? null : await _dbContext.AuthorizedMobileDevices.AsNoTracking()
            .Where(d => d.StoreId == storeId && d.DeviceId == r.DeviceId)
            .Select(d => new { d.DeviceName, d.DeviceModel, d.Deleted })
            .FirstOrDefaultAsync();

        return Ok(AppResponse<object>.Success(new
        {
            record = new
            {
                id = r.Id, r.OdooEmployeeId, r.EmployeeName, r.PunchTime, r.PunchType, r.Status, r.Latitude, r.Longitude,
                r.LocationName, r.DistanceFromLocation, r.GpsAccuracy, r.FaceMatchScore, r.VerifyMethod, r.WifiSsid,
                sitePhotoUrl = SitePhotoUrlForApi(r.Status, r.SitePhotoUrl), r.OutsideReason, r.Note, r.RiskScore, r.RiskLevel,
                riskFlags = ParseFlags(r.RiskFlags), r.ApprovedBy, r.ApprovedAt, r.RejectReason, r.EvidencePurgedAt,
            },
            employee = emp == null ? null : new { id = emp.Id, name = (emp.LastName + " " + emp.FirstName).Trim(), emp.EmployeeCode, emp.Department, emp.PhotoUrl },
            device = device == null ? null : new { name = device.DeviceName, model = device.DeviceModel, removed = device.Deleted != null },
            shift,
            sameDay,
            logs,
            outsideThisMonth = outsideMonth,
            history,
            locations = locations.Select(l => new { l.Name, l.Latitude, l.Longitude, l.Radius }),
        }));
    }

    private static List<string> ParseFlags(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return [];
        try { return JsonSerializer.Deserialize<List<string>>(json) ?? []; } catch { return []; }
    }

    // ─── Cài đặt duyệt ────────────────────────────────────────────────

    [HttpGet("approval-settings")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "MobileAttendance", "MobileAttendanceApproval", "AttendanceApproval")]
    public async Task<ActionResult> GetApprovalSettings()
    {
        var storeId = RequiredStoreId;
        var s = await _dbContext.MobileAttendanceSettings.AsNoTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null);
        return Ok(AppResponse<MobileApprovalSettingsDto>.Success(new MobileApprovalSettingsDto
        {
            AutoApproveTrusted = s?.AutoApproveTrusted ?? true,
            TrustedMaxDistanceMeters = s?.TrustedMaxDistanceMeters ?? 300,
            TrustedMinFaceScore = s?.TrustedMinFaceScore ?? 85,
            EvidenceRetentionDays = s?.EvidenceRetentionDays ?? 30,
        }));
    }

    [HttpPut("approval-settings")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "MobileAttendance", "MobileAttendanceApproval", "AttendanceApproval")]
    public async Task<ActionResult> SaveApprovalSettings([FromBody] MobileApprovalSettingsDto dto)
    {
        var storeId = RequiredStoreId;
        var s = await _dbContext.MobileAttendanceSettings.AsTracking()
            .FirstOrDefaultAsync(x => x.StoreId == storeId && x.Deleted == null);
        if (s == null)
        {
            s = new MobileAttendanceSetting { Id = Guid.NewGuid(), StoreId = storeId, IsActive = true, CreatedAt = DateTime.UtcNow };
            _dbContext.MobileAttendanceSettings.Add(s);
        }
        s.AutoApproveTrusted = dto.AutoApproveTrusted;
        s.TrustedMaxDistanceMeters = Math.Clamp(dto.TrustedMaxDistanceMeters, 50, 5000);
        s.TrustedMinFaceScore = Math.Clamp(dto.TrustedMinFaceScore, 50, 100);
        s.EvidenceRetentionDays = Math.Clamp(dto.EvidenceRetentionDays, 1, 365);
        s.UpdatedAt = DateTime.UtcNow;
        await _dbContext.SaveChangesAsync();
        _cache.Remove($"mobile_settings_{storeId}");
        return Ok(AppResponse<bool>.Success(true));
    }

    /// <summary>Danh sách máy chấm công của nhân viên + cờ «bắt buộc lý do ngoài vị trí».</summary>
    [HttpGet("outside-reason-devices")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "MobileAttendance", "MobileAttendanceApproval", "AttendanceApproval")]
    public async Task<ActionResult> GetOutsideReasonDevices()
    {
        var storeId = RequiredStoreId;
        var list = await _dbContext.AuthorizedMobileDevices.AsNoTracking()
            .Where(d => d.StoreId == storeId && d.Deleted == null && d.IsAuthorized)
            .OrderBy(d => d.EmployeeName)
            .Select(d => new
            {
                id = d.Id, d.EmployeeId, d.EmployeeName, d.DeviceName, d.DeviceModel,
                d.AllowOutsideCheckIn, d.AllowTravelCheckIn, d.RequirePhotoProof, d.RequireOutsideReason,
            })
            .ToListAsync();
        return Ok(AppResponse<object>.Success(list));
    }

    [HttpPost("outside-reason-devices")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "MobileAttendance", "MobileAttendanceApproval", "AttendanceApproval")]
    public async Task<ActionResult> SetOutsideReasonDevices([FromBody] MobileOutsideReasonFlagRequest request)
    {
        var storeId = RequiredStoreId;
        var ids = request.DeviceIds.Distinct().ToList();
        var devices = await _dbContext.AuthorizedMobileDevices.AsTracking()
            .Where(d => d.StoreId == storeId && d.Deleted == null && ids.Contains(d.Id))
            .ToListAsync();
        foreach (var d in devices)
        {
            d.RequireOutsideReason = request.Value;
            d.UpdatedAt = DateTime.UtcNow;
        }
        await _dbContext.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { updated = devices.Count }));
    }
}
