using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Interfaces;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Thiết bị chấm công Mobile (quản lý): một hộp «Cần duyệt» gộp đăng ký mới + đổi máy,
/// danh sách máy đã cấp quyền (chỉnh hàng loạt), nhân viên chưa đăng ký (gửi nhắc).
/// Duyệt / từ chối dùng lại API cũ: mobile-attendance/approve-device, approve-device-change.
/// Lọc theo chi nhánh đang xem (bộ chọn chi nhánh trên đầu app).
/// </summary>
[ApiController]
[Route("api/mobile-devices")]
[Authorize]
public class MobileDeviceHubController(ZKTecoDbContext db, ISystemNotificationService notifications)
    : AuthenticatedControllerBase
{
    sealed record Emp(Guid Id, Guid? UserId, string Code, string Name, string? Dept, string? Photo, Guid? BranchId, string? BranchName);

    /// <summary>Nhân viên đang làm của cửa hàng + tra cứu theo id / mã / user id (thiết bị lưu 1 trong 3).</summary>
    async Task<(List<Emp> list, Dictionary<string, Emp> byKey)> EmployeesAsync(Guid storeId)
    {
        var branchNames = await db.Branches.AsNoTracking().Where(b => b.StoreId == storeId)
            .Select(b => new { b.Id, b.Name }).ToDictionaryAsync(b => b.Id, b => b.Name);
        var rows = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.WorkStatus != EmployeeWorkStatus.Resigned)
            .Select(e => new { e.Id, e.ApplicationUserId, e.EmployeeCode, e.LastName, e.FirstName, e.Department, e.PhotoUrl, e.BranchId })
            .ToListAsync();
        var list = rows.Select(e => new Emp(e.Id, e.ApplicationUserId, e.EmployeeCode, $"{e.LastName} {e.FirstName}".Trim(),
            e.Department, e.PhotoUrl, e.BranchId, e.BranchId is Guid b ? branchNames.GetValueOrDefault(b) : null)).ToList();
        var byKey = new Dictionary<string, Emp>(StringComparer.OrdinalIgnoreCase);
        foreach (var e in list)
        {
            byKey.TryAdd(e.Id.ToString(), e);
            if (e.UserId is Guid u) byKey.TryAdd(u.ToString(), e);
            if (!string.IsNullOrWhiteSpace(e.Code)) byKey.TryAdd(e.Code, e);
        }
        return (list, byKey);
    }

    async Task<Func<Emp?, bool>> ViewFilterAsync(Guid storeId)
    {
        var view = await BranchViewHelper.ViewBranchIdsAsync(HttpContext, db, storeId);
        var hq = HttpContext.BranchContext()?.HeadquarterBranchId;
        return e => view == null || (e != null && BranchViewHelper.InView(view, e.BranchId, hq));
    }

    static List<string> JsonList(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return [];
        try
        {
            return JsonSerializer.Deserialize<List<JsonElement>>(json)?
                .Select(x => x.ValueKind == JsonValueKind.String ? x.GetString() ?? "" : x.ToString())
                .Where(x => !string.IsNullOrWhiteSpace(x)).ToList() ?? [];
        }
        catch
        {
            return [];
        }
    }

    /// <summary>Đường dẫn ảnh tương đối (/uploads/...) — app tự ghép địa chỉ máy chủ.</summary>
    public static string NormalizeImagePath(string path)
    {
        if (string.IsNullOrEmpty(path)) return path;
        path = path.Trim().Replace('\\', '/');
        if (path.StartsWith("wwwroot/", StringComparison.OrdinalIgnoreCase)) path = path["wwwroot/".Length..];
        if (path.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || path.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
        {
            if (Uri.TryCreate(path, UriKind.Absolute, out var u)) return u.AbsolutePath;
            return path;
        }
        return path.StartsWith('/') ? path : "/" + path;
    }

    static object EmpDto(Emp? e, string? fallbackId, string? fallbackName) => new
    {
        employeeId = e?.Id.ToString() ?? fallbackId,
        employeeName = e?.Name ?? fallbackName ?? "",
        employeeCode = e?.Code,
        department = e?.Dept,
        branchName = e?.BranchName,
        photoUrl = e?.Photo,
    };

    // ─── Cần duyệt ───────────────────────────────────────────────

    [HttpGet("inbox")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Approve, "AttendanceApproval", "MobileAttendanceApproval")]
    public async Task<ActionResult<AppResponse<object>>> Inbox()
    {
        var storeId = RequiredStoreId;
        var (_, byKey) = await EmployeesAsync(storeId);
        var inView = await ViewFilterAsync(storeId);
        Emp? Find(string? key) => key != null && byKey.TryGetValue(key, out var e) ? e : null;

        var regs = await db.AuthorizedMobileDevices.AsNoTracking()
            .Where(d => d.StoreId == storeId && !d.IsAuthorized)
            .OrderBy(d => d.CreatedAt)
            .ToListAsync();
        var changes = await db.DeviceChangeRequests.AsNoTracking()
            .Where(r => r.StoreId == storeId && r.Status == 0)
            .OrderBy(r => r.RequestedAt)
            .ToListAsync();

        // Ảnh khuôn mặt đăng ký + tên địa điểm đã chọn
        var faces = await db.MobileFaceRegistrations.AsNoTracking()
            .Where(f => f.StoreId == storeId)
            .Select(f => new { f.OdooEmployeeId, f.FaceImagesJson })
            .ToListAsync();
        var faceByEmp = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        foreach (var f in faces)
            faceByEmp.TryAdd(f.OdooEmployeeId, JsonList(f.FaceImagesJson).Select(NormalizeImagePath).ToList());
        var locNames = await db.MobileWorkLocations.AsNoTracking().Where(l => l.StoreId == storeId)
            .Select(l => new { l.Id, l.Name }).ToDictionaryAsync(l => l.Id.ToString(), l => l.Name, StringComparer.OrdinalIgnoreCase);
        List<string> Locs(string? json) => JsonList(json).Select(id => locNames.GetValueOrDefault(id)).OfType<string>().ToList();
        List<string> FacesOf(Emp? e, string? raw)
        {
            foreach (var k in new[] { raw, e?.Id.ToString(), e?.UserId?.ToString(), e?.Code })
                if (k != null && faceByEmp.TryGetValue(k, out var list) && list.Count > 0) return list;
            return [];
        }

        var items = new List<object>();
        foreach (var d in regs)
        {
            var e = Find(d.EmployeeId);
            if (!inView(e)) continue;
            items.Add(new
            {
                id = d.Id,
                kind = "register",
                requestedAt = d.CreatedAt,
                employee = EmpDto(e, d.EmployeeId, d.EmployeeName),
                deviceName = d.DeviceName,
                deviceModel = d.DeviceModel,
                osVersion = d.OsVersion,
                wifiBssid = d.WifiBssid,
                oldDeviceName = (string?)null,
                reason = (string?)null,
                faceImages = FacesOf(e, d.EmployeeId),
                locations = Locs(d.SelectedLocationIdsJson),
            });
        }
        foreach (var r in changes)
        {
            var e = Find(r.EmployeeId);
            if (!inView(e)) continue;
            var newFaces = JsonList(r.NewFaceImagesJson).Select(NormalizeImagePath).ToList();
            items.Add(new
            {
                id = r.Id,
                kind = "change",
                requestedAt = r.RequestedAt,
                employee = EmpDto(e, r.EmployeeId, r.EmployeeName),
                deviceName = r.NewDeviceName,
                deviceModel = r.NewDeviceModel,
                osVersion = r.NewOsVersion,
                wifiBssid = r.NewWifiBssid,
                oldDeviceName = r.OldDeviceName,
                reason = r.Reason,
                faceImages = newFaces.Count > 0 ? newFaces : FacesOf(e, r.EmployeeId),
                locations = Locs(r.SelectedLocationIdsJson),
            });
        }
        return Ok(AppResponse<object>.Success(new
        {
            items,
            counts = new
            {
                total = items.Count,
                register = regs.Count(d => inView(Find(d.EmployeeId))),
                change = changes.Count(r => inView(Find(r.EmployeeId))),
            },
        }));
    }

    // ─── Thiết bị đã cấp quyền ───────────────────────────────────

    [HttpGet("devices")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "MobileDeviceRegistration", "MobileAttendanceApproval", "AttendanceApproval")]
    public async Task<ActionResult<AppResponse<object>>> Devices()
    {
        var storeId = RequiredStoreId;
        var (_, byKey) = await EmployeesAsync(storeId);
        var inView = await ViewFilterAsync(storeId);
        var devices = await db.AuthorizedMobileDevices.AsNoTracking()
            .Where(d => d.StoreId == storeId && d.IsAuthorized)
            .OrderBy(d => d.EmployeeName)
            .ToListAsync();
        var list = new List<object>();
        foreach (var d in devices)
        {
            var e = d.EmployeeId != null && byKey.TryGetValue(d.EmployeeId, out var x) ? x : null;
            if (!inView(e)) continue;
            list.Add(new
            {
                id = d.Id,
                employee = EmpDto(e, d.EmployeeId, d.EmployeeName),
                deviceName = d.DeviceName,
                deviceModel = d.DeviceModel,
                osVersion = d.OsVersion,
                authorizedAt = d.AuthorizedAt,
                lastUsedAt = d.LastUsedAt,
                canUseFaceId = d.CanUseFaceId,
                canUseGps = d.CanUseGps,
                allowOutsideCheckIn = d.AllowOutsideCheckIn,
                allowTravelCheckIn = d.AllowTravelCheckIn,
                requirePhotoProof = d.RequirePhotoProof,
                requireOutsideReason = d.RequireOutsideReason,
                resigned = e == null && d.EmployeeId != null,
            });
        }
        return Ok(AppResponse<object>.Success(list));
    }

    public sealed class BulkDeviceRequest
    {
        public List<Guid> Ids { get; set; } = [];
        public bool? CanUseFaceId { get; set; }
        public bool? CanUseGps { get; set; }
        public bool? AllowOutsideCheckIn { get; set; }
        public bool? AllowTravelCheckIn { get; set; }
        public bool? RequirePhotoProof { get; set; }
        public bool? RequireOutsideReason { get; set; }
    }

    /// <summary>Đổi quyền nhiều máy cùng lúc (trường null = giữ nguyên).</summary>
    [HttpPost("devices/bulk")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.Edit, "MobileDeviceRegistration", "MobileAttendanceApproval", "AttendanceApproval")]
    public async Task<ActionResult<AppResponse<object>>> Bulk([FromBody] BulkDeviceRequest req)
    {
        var storeId = RequiredStoreId;
        if (req.Ids.Count == 0) return Ok(AppResponse<object>.Error("Chưa chọn thiết bị"));
        var devices = await db.AuthorizedMobileDevices.AsTracking()
            .Where(d => d.StoreId == storeId && req.Ids.Contains(d.Id))
            .ToListAsync();
        foreach (var d in devices)
        {
            if (req.CanUseFaceId is bool f) d.CanUseFaceId = f;
            if (req.CanUseGps is bool g) d.CanUseGps = g;
            if (req.AllowOutsideCheckIn is bool o) d.AllowOutsideCheckIn = o;
            if (req.AllowTravelCheckIn is bool t) d.AllowTravelCheckIn = t;
            if (req.RequirePhotoProof is bool p) d.RequirePhotoProof = p;
            if (req.RequireOutsideReason is bool r) d.RequireOutsideReason = r;
            d.UpdatedAt = DateTime.UtcNow;
            d.UpdatedBy = CurrentUserEmail;
        }
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { updated = devices.Count }));
    }

    // ─── Chưa đăng ký ────────────────────────────────────────────

    [HttpGet("unregistered")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "MobileDeviceRegistration", "MobileAttendanceApproval", "AttendanceApproval")]
    public async Task<ActionResult<AppResponse<object>>> Unregistered()
    {
        var storeId = RequiredStoreId;
        var (list, byKey) = await EmployeesAsync(storeId);
        var inView = await ViewFilterAsync(storeId);
        var keys = await db.AuthorizedMobileDevices.AsNoTracking()
            .Where(d => d.StoreId == storeId && d.EmployeeId != null)
            .Select(d => new { d.EmployeeId, d.IsAuthorized })
            .ToListAsync();
        var registered = new HashSet<Guid>();
        var pending = new HashSet<Guid>();
        foreach (var k in keys)
            if (byKey.TryGetValue(k.EmployeeId!, out var e))
                (k.IsAuthorized ? registered : pending).Add(e.Id);
        var rows = list
            .Where(e => !registered.Contains(e.Id) && inView(e))
            .OrderBy(e => e.Name)
            .Select(e => new
            {
                employeeId = e.Id,
                employeeName = e.Name,
                employeeCode = e.Code,
                department = e.Dept,
                branchName = e.BranchName,
                photoUrl = e.Photo,
                hasAccount = e.UserId != null,
                pending = pending.Contains(e.Id),
            }).ToList();
        return Ok(AppResponse<object>.Success(rows));
    }

    public sealed class RemindRequest
    {
        public List<Guid> EmployeeIds { get; set; } = [];
    }

    /// <summary>Nhắc nhân viên đăng ký điện thoại chấm công (gửi thông báo trong app).</summary>
    [HttpPost("remind")]
    [Authorize(Policy = PolicyNames.AtLeastManager)]
    [RequireAnyModulePermission(ModulePermissionAction.View, "MobileDeviceRegistration", "MobileAttendanceApproval", "AttendanceApproval")]
    public async Task<ActionResult<AppResponse<object>>> Remind([FromBody] RemindRequest req)
    {
        var storeId = RequiredStoreId;
        var userIds = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && req.EmployeeIds.Contains(e.Id) && e.ApplicationUserId != null)
            .Select(e => e.ApplicationUserId!.Value)
            .Distinct()
            .ToListAsync();
        foreach (var u in userIds)
        {
            try
            {
                await notifications.CreateAndSendAsync(u, NotificationType.Info, "Đăng ký điện thoại chấm công",
                    "Quản lý nhắc bạn đăng ký điện thoại để chấm công trên app: mở «Đăng ký chấm công Mobile», chụp khuôn mặt và gửi.",
                    relatedEntityType: "AuthorizedMobileDevice", fromUserId: CurrentUserId,
                    categoryCode: "mobile_attendance", storeId: storeId);
            }
            catch
            {
                // Bỏ qua người không gửi được, vẫn nhắc những người còn lại.
            }
        }
        return Ok(AppResponse<object>.Success(new { sent = userIds.Count, skipped = req.EmployeeIds.Count - userIds.Count }));
    }

    // ─── Nhân viên: hủy yêu cầu đang chờ ─────────────────────────

    public sealed class CancelMyRequest
    {
        public string? EmployeeId { get; set; }
    }

    /// <summary>Nhân viên tự hủy đăng ký / đổi máy đang chờ duyệt để gửi lại.</summary>
    [HttpPost("my-request/cancel")]
    public async Task<ActionResult<AppResponse<object>>> CancelMine([FromBody] CancelMyRequest req)
    {
        var storeId = RequiredStoreId;
        var me = CurrentUserId;
        var emp = await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == storeId && e.ApplicationUserId == me)
            .Select(e => new { e.Id, e.EmployeeCode })
            .FirstOrDefaultAsync();
        var keys = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { me.ToString() };
        if (emp != null)
        {
            keys.Add(emp.Id.ToString());
            if (!string.IsNullOrWhiteSpace(emp.EmployeeCode)) keys.Add(emp.EmployeeCode);
        }
        // Chỉ chấp nhận mã NV gửi lên nếu đúng là của chính mình.
        if (!string.IsNullOrWhiteSpace(req.EmployeeId) && !keys.Contains(req.EmployeeId))
            return Ok(AppResponse<object>.Error("Không hủy được yêu cầu của người khác"));

        var pendingDevices = await db.AuthorizedMobileDevices.AsTracking()
            .Where(d => d.StoreId == storeId && !d.IsAuthorized && d.EmployeeId != null && keys.Contains(d.EmployeeId))
            .ToListAsync();
        foreach (var d in pendingDevices)
        {
            d.Deleted = DateTime.UtcNow;
            d.DeletedBy = CurrentUserEmail;
        }
        var pendingChanges = await db.DeviceChangeRequests.AsTracking()
            .Where(r => r.StoreId == storeId && r.Status == 0 && keys.Contains(r.EmployeeId))
            .ToListAsync();
        foreach (var r in pendingChanges)
        {
            r.Deleted = DateTime.UtcNow;
            r.DeletedBy = CurrentUserEmail;
        }
        // Ảnh khuôn mặt chưa duyệt của đăng ký bị hủy cũng bỏ (đăng ký lại sẽ chụp mới).
        if (pendingDevices.Count > 0)
        {
            var faces = await db.MobileFaceRegistrations.AsTracking()
                .Where(f => f.StoreId == storeId && !f.IsVerified && keys.Contains(f.OdooEmployeeId))
                .ToListAsync();
            foreach (var f in faces)
            {
                f.Deleted = DateTime.UtcNow;
                f.DeletedBy = CurrentUserEmail;
            }
        }
        await db.SaveChangesAsync();
        return Ok(AppResponse<object>.Success(new { cancelled = pendingDevices.Count + pendingChanges.Count }));
    }
}
