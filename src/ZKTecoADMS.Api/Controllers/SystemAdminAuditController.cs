using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Controllers.Filters;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Nhật ký hệ thống cho Super Admin: lọc tại server theo cửa hàng, tài khoản, loại thao tác, chức năng, kết quả,
/// khoảng ngày, từ khóa. Nội dung Việt hóa (dùng chung bộ dịch với Lịch sử thao tác của cửa hàng).
/// </summary>
[ApiController]
[Authorize(Roles = nameof(Roles.SuperAdmin))]
[Route("api/system-admin/audit")]
public class SystemAdminAuditController(ZKTecoDbContext db) : AuthenticatedControllerBase
{
    public record AuditRow(
        Guid Id, DateTime Timestamp,
        string Action, string ActionName, string Kind,
        string Module, string ModuleName, string? Summary, int ChangeCount,
        Guid? UserId, string? UserName, string? UserEmail, string? UserRole,
        Guid? StoreId, string? StoreName,
        string? IpAddress, string? Device, string Status, string? ErrorMessage);

    /// <summary>Nhóm thao tác cho ô lọc: data (thêm/sửa/xóa) · auth (đăng nhập) · admin (quản trị hệ thống).</summary>
    internal static string KindOf(string action) => action switch
    {
        "Create" or "Update" or "Delete" => "data",
        "Login" or "LoginFailed" or "Logout" or "Impersonate" or "PasswordChanged" or "CredentialsUpdated" => "auth",
        _ => "admin",
    };

    internal static string ActionName(string action) => action switch
    {
        "Create" => "Thêm",
        "Update" => "Sửa",
        "Delete" => "Xóa",
        "Login" => "Đăng nhập",
        "LoginFailed" => "Đăng nhập sai",
        "Logout" => "Đăng xuất",
        "Impersonate" => "Đăng nhập thay",
        "PasswordChanged" => "Đổi mật khẩu",
        "CredentialsUpdated" => "Đặt lại thông tin đăng nhập",
        "StoreLocked" => "Khóa cửa hàng",
        "StoreUnlocked" => "Mở khóa cửa hàng",
        "StoreDataDeleted" => "Xóa dữ liệu cửa hàng",
        "LicenseGenerated" => "Tạo key",
        "LicenseActivated" => "Kích hoạt key",
        "LicenseRevoked" => "Thu hồi key",
        "SubscriptionExtended" => "Gia hạn",
        "DeviceClaimed" => "Nhận thiết bị",
        "DeviceReleased" => "Gỡ thiết bị",
        "DeviceCommandSent" => "Gửi lệnh thiết bị",
        "SuperAdminCreated" => "Tạo Super Admin",
        "AgentCreated" => "Tạo đại lý",
        "AgentLicenseAssigned" => "Giao key cho đại lý",
        "SettingsUpdated" => "Đổi cài đặt",
        _ => action,
    };

    static bool IsStoreActivity(AuditLog a) =>
        a.Details != null && a.Details.Contains($"\"source\":\"{ActivityAuditFilter.Source}\"");

    internal static AuditRow ToRow(AuditLog a)
    {
        string module = a.EntityType, moduleName, summary;
        var count = 0;
        string? device;
        if (IsStoreActivity(a))
        {
            var r = ActivityLogsController.ToRow(a);
            moduleName = r.ModuleName;
            summary = r.EntityName ?? "";
            count = r.ChangeCount;
            device = r.Device;
        }
        else
        {
            moduleName = ActivityAuditFilter.ModuleLabel(a.EntityType);
            // Nhật ký quản trị / đăng nhập: Details là câu chữ — ghép với tên đối tượng.
            var name = string.IsNullOrWhiteSpace(a.EntityName) || ActivityLabels.IsGuid(a.EntityName) ? null : a.EntityName;
            var details = a.Details?.Trim();
            summary = (name, details) switch
            {
                (null, null or "") => ActionName(a.Action),
                (null, _) => details!,
                (_, null or "") => name!,
                _ => details!.Contains(name!, StringComparison.OrdinalIgnoreCase) ? details! : $"{name} — {details}",
            };
            device = ActivityLogsController.DeviceOf(a.UserAgent);
        }

        return new AuditRow(a.Id, a.Timestamp, a.Action, ActionName(a.Action), KindOf(a.Action),
            module, moduleName, summary.Length > 300 ? summary[..300] + "…" : summary, count,
            a.UserId, a.UserName, a.UserEmail, ActivityLabels.Role(a.UserRole) ?? a.UserRole,
            a.StoreId, a.StoreName, a.IpAddress, device, a.Status, a.ErrorMessage);
    }

    IQueryable<AuditLog> Filtered(
        Guid? storeId, Guid? userId, string? action, string? kind, string? module, string? status,
        DateTime? from, DateTime? to, string? search)
    {
        var q = db.AuditLogs.AsNoTracking().AsQueryable();
        if (storeId.HasValue)
            q = storeId.Value == Guid.Empty ? q.Where(a => a.StoreId == null) : q.Where(a => a.StoreId == storeId);
        if (userId.HasValue) q = q.Where(a => a.UserId == userId);
        if (!string.IsNullOrWhiteSpace(action)) q = q.Where(a => a.Action == action);
        switch (kind)
        {
            case "data": q = q.Where(a => a.Action == "Create" || a.Action == "Update" || a.Action == "Delete"); break;
            case "auth":
                q = q.Where(a => a.Action == "Login" || a.Action == "LoginFailed" || a.Action == "Logout"
                    || a.Action == "Impersonate" || a.Action == "PasswordChanged" || a.Action == "CredentialsUpdated");
                break;
            case "admin":
                q = q.Where(a => a.Action != "Create" && a.Action != "Update" && a.Action != "Delete"
                    && a.Action != "Login" && a.Action != "LoginFailed" && a.Action != "Logout"
                    && a.Action != "Impersonate" && a.Action != "PasswordChanged" && a.Action != "CredentialsUpdated");
                break;
        }
        if (!string.IsNullOrWhiteSpace(module)) q = q.Where(a => a.EntityType == module);
        if (!string.IsNullOrWhiteSpace(status)) q = q.Where(a => a.Status == status);
        // Ngày theo giờ Việt Nam
        if (from.HasValue) q = q.Where(a => a.Timestamp >= from.Value.Date.AddHours(-7));
        if (to.HasValue) q = q.Where(a => a.Timestamp < to.Value.Date.AddDays(1).AddHours(-7));
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            q = q.Where(a =>
                (a.UserEmail != null && a.UserEmail.ToLower().Contains(s)) ||
                (a.UserName != null && a.UserName.ToLower().Contains(s)) ||
                (a.StoreName != null && a.StoreName.ToLower().Contains(s)) ||
                (a.EntityName != null && a.EntityName.ToLower().Contains(s)) ||
                (a.IpAddress != null && a.IpAddress.Contains(s)) ||
                (a.Details != null && a.Details.ToLower().Contains(s)));
        }
        return q;
    }

    [HttpGet]
    public async Task<ActionResult<AppResponse<object>>> List(
        [FromQuery] Guid? storeId, [FromQuery] Guid? userId, [FromQuery] string? action, [FromQuery] string? kind,
        [FromQuery] string? module, [FromQuery] string? status, [FromQuery] DateTime? from, [FromQuery] DateTime? to,
        [FromQuery] string? search, [FromQuery] int page = 1, [FromQuery] int pageSize = 50, CancellationToken ct = default)
    {
        page = Math.Max(1, page);
        pageSize = Math.Clamp(pageSize, 10, 200);
        var q = Filtered(storeId, userId, action, kind, module, status, from, to, search);
        var total = await q.CountAsync(ct);
        var rows = await q.OrderByDescending(a => a.Timestamp)
            .Skip((page - 1) * pageSize).Take(pageSize).ToListAsync(ct);
        var byAction = await q.GroupBy(a => a.Action).Select(g => new { g.Key, C = g.Count() }).ToListAsync(ct);
        return Ok(AppResponse<object>.Success(new
        {
            total,
            page,
            pageSize,
            totalPages = (int)Math.Ceiling(total / (double)pageSize),
            failed = await q.CountAsync(a => a.Status == "Failed", ct),
            kinds = byAction.GroupBy(x => KindOf(x.Key)).ToDictionary(g => g.Key, g => g.Sum(x => x.C)),
            items = rows.Select(ToRow),
        }));
    }

    /// <summary>Giá trị cho các ô lọc. Tài khoản / chức năng thu hẹp theo cửa hàng đang chọn.</summary>
    [HttpGet("filters")]
    public async Task<ActionResult<AppResponse<object>>> Filters(
        [FromQuery] Guid? storeId, [FromQuery] DateTime? from, [FromQuery] DateTime? to, CancellationToken ct = default)
    {
        var range = Filtered(null, null, null, null, null, null, from, to, null);
        var stores = await range.Where(a => a.StoreId != null)
            .GroupBy(a => a.StoreId)
            .Select(g => new { StoreId = g.Key, Count = g.Count(), Name = g.Max(x => x.StoreName) })
            .ToListAsync(ct);
        var storeIds = stores.Select(s => s.StoreId!.Value).ToList();
        var storeInfo = await db.Stores.AsNoTracking().IgnoreQueryFilters()
            .Where(s => storeIds.Contains(s.Id))
            .Select(s => new { s.Id, s.Name, s.Code })
            .ToDictionaryAsync(s => s.Id, ct);
        var noStore = await range.CountAsync(a => a.StoreId == null, ct);

        var scoped = storeId.HasValue
            ? (storeId.Value == Guid.Empty ? range.Where(a => a.StoreId == null) : range.Where(a => a.StoreId == storeId))
            : range;
        var users = await scoped.Where(a => a.UserId != null)
            .GroupBy(a => a.UserId)
            .Select(g => new { UserId = g.Key, Count = g.Count(), Name = g.Max(x => x.UserName), Email = g.Max(x => x.UserEmail) })
            .OrderByDescending(x => x.Count).Take(500)
            .ToListAsync(ct);
        var actions = await scoped.GroupBy(a => a.Action).Select(g => new { Code = g.Key, Count = g.Count() }).ToListAsync(ct);
        var modules = await scoped.GroupBy(a => a.EntityType).Select(g => new { Code = g.Key, Count = g.Count() }).ToListAsync(ct);

        return Ok(AppResponse<object>.Success(new
        {
            stores = stores
                .Select(s =>
                {
                    storeInfo.TryGetValue(s.StoreId!.Value, out var info);
                    return new { id = s.StoreId, name = info?.Name ?? s.Name ?? "(đã xóa)", code = info?.Code, count = s.Count };
                })
                .OrderByDescending(s => s.count),
            noStoreCount = noStore,
            users = users.Select(u => new
            {
                id = u.UserId,
                name = string.IsNullOrWhiteSpace(u.Name) ? u.Email : u.Name,
                email = u.Email,
                count = u.Count,
            }),
            actions = actions.Select(a => new { code = a.Code, name = ActionName(a.Code), kind = KindOf(a.Code), count = a.Count })
                .OrderByDescending(a => a.count),
            modules = modules.Select(m => new { code = m.Code, name = ActivityAuditFilter.ModuleLabel(m.Code), count = m.Count })
                .OrderBy(m => m.name),
        }));
    }

    [HttpGet("{id:guid}")]
    public async Task<ActionResult<AppResponse<object>>> Detail(Guid id, CancellationToken ct = default)
    {
        var a = await db.AuditLogs.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id, ct);
        if (a == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy nhật ký"));
        return Ok(AppResponse<object>.Success(new
        {
            row = ToRow(a),
            details = IsStoreActivity(a) ? ActivityLogsController.LocalizedDetails(a.Details) : null,
            text = IsStoreActivity(a) ? null : a.Details,
            entityId = a.EntityId,
            userAgent = a.UserAgent,
        }));
    }

    [HttpGet("export")]
    public async Task<IActionResult> Export(
        [FromQuery] Guid? storeId, [FromQuery] Guid? userId, [FromQuery] string? action, [FromQuery] string? kind,
        [FromQuery] string? module, [FromQuery] string? status, [FromQuery] DateTime? from, [FromQuery] DateTime? to,
        [FromQuery] string? search, CancellationToken ct = default)
    {
        var rows = await Filtered(storeId, userId, action, kind, module, status, from, to, search)
            .OrderByDescending(a => a.Timestamp).Take(20000).ToListAsync(ct);
        return ReportHelpers.ExcelFile("Nhat ky he thong",
            new[] { "Thời gian", "Cửa hàng", "Người thao tác", "Email", "Vai trò", "Thao tác", "Chức năng", "Nội dung", "Chi tiết thay đổi", "Kết quả", "IP", "Thiết bị" },
            (ws, start) =>
            {
                var r = start;
                foreach (var a in rows)
                {
                    var row = ToRow(a);
                    ws.Cell(r, 1).Value = ReportHelpers.ToVn(a.Timestamp).ToString("dd/MM/yyyy HH:mm:ss");
                    ws.Cell(r, 2).Value = a.StoreName ?? "";
                    ws.Cell(r, 3).Value = a.UserName ?? "";
                    ws.Cell(r, 4).Value = a.UserEmail ?? "";
                    ws.Cell(r, 5).Value = row.UserRole ?? "";
                    ws.Cell(r, 6).Value = row.ActionName;
                    ws.Cell(r, 7).Value = row.ModuleName;
                    ws.Cell(r, 8).Value = row.Summary ?? "";
                    ws.Cell(r, 9).Value = IsStoreActivity(a) ? ActivityLogsController.ChangeText(a.Details) : "";
                    ws.Cell(r, 10).Value = a.Status == "Failed" ? $"Lỗi: {a.ErrorMessage}" : "Thành công";
                    ws.Cell(r, 11).Value = a.IpAddress ?? "";
                    ws.Cell(r, 12).Value = row.Device ?? "";
                    r++;
                }
            },
            $"nhat-ky-he-thong-{DateTime.UtcNow.AddHours(7):yyyyMMdd-HHmm}.xlsx", user: User);
    }
}
