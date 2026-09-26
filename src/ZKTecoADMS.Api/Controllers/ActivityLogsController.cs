using System.Text.Json;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Authorization;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Api.Controllers.Filters;
using ZKTecoADMS.Api.Controllers.Reports;
using ZKTecoADMS.Api.Services;
using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.Models;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Controllers;

/// <summary>
/// Lịch sử thao tác của cửa hàng (30 ngày): ai thêm / sửa / xóa gì, lúc nào, ở chức năng nào,
/// trường nào đổi từ gì sang gì. Lọc theo ngày, người, chức năng, loại thao tác, từ khóa.
/// </summary>
[ApiController]
[Authorize]
[Route("api/activity-logs")]
public class ActivityLogsController(ZKTecoDbContext db) : AuthenticatedControllerBase
{
    public record LogRow(
        Guid Id, DateTime Timestamp, Guid? UserId, string? UserName, string? UserEmail, string? UserRole,
        string Module, string ModuleName, string Action, string? EntityName, string? Endpoint,
        string? IpAddress, string? Device, int ChangeCount);

    static readonly JsonSerializerOptions JsonOpts = new(JsonSerializerDefaults.Web);
    static string Marker => $"\"source\":\"{ActivityAuditFilter.Source}\"";

    IQueryable<AuditLog> Base(DateTime? from, DateTime? to)
    {
        var storeId = RequiredStoreId;
        var todayVn = DateTime.UtcNow.AddHours(7).Date;
        var minVn = todayVn.AddDays(-ActivityLogCleanupService.RetentionDays);
        var f = (from ?? todayVn).Date;
        var t = (to ?? todayVn).Date;
        if (t < f) (f, t) = (t, f);
        if (f < minVn) f = minVn;
        var fromUtc = f.AddHours(-7);
        var toUtc = t.AddDays(1).AddHours(-7);
        var marker = Marker;
        return db.AuditLogs.AsNoTracking()
            .Where(a => a.StoreId == storeId && a.Timestamp >= fromUtc && a.Timestamp < toUtc
                && a.Details != null && a.Details.Contains(marker));
    }

    IQueryable<AuditLog> Filtered(DateTime? from, DateTime? to, Guid? userId, string? module, string? action, string? search)
    {
        var q = Base(from, to);
        if (userId.HasValue) q = q.Where(a => a.UserId == userId);
        if (!string.IsNullOrWhiteSpace(module)) q = q.Where(a => a.EntityType == module);
        if (!string.IsNullOrWhiteSpace(action)) q = q.Where(a => a.Action == action);
        if (!string.IsNullOrWhiteSpace(search))
        {
            var s = search.Trim().ToLower();
            q = q.Where(a => (a.EntityName != null && a.EntityName.ToLower().Contains(s))
                || (a.UserName != null && a.UserName.ToLower().Contains(s))
                || a.Details!.ToLower().Contains(s));
        }
        return q;
    }

    [HttpGet]
    [RequireModulePermission("ActivityLog", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> List(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] Guid? userId,
        [FromQuery] string? module, [FromQuery] string? action, [FromQuery] string? search,
        [FromQuery] int page = 1, [FromQuery] int pageSize = 50, CancellationToken ct = default)
    {
        pageSize = Math.Clamp(pageSize, 10, 200);
        page = Math.Max(1, page);
        var q = Filtered(from, to, userId, module, action, search);
        var total = await q.CountAsync(ct);
        var rows = await q.OrderByDescending(a => a.Timestamp)
            .Skip((page - 1) * pageSize).Take(pageSize)
            .ToListAsync(ct);
        var counts = await q.GroupBy(a => a.Action).Select(g => new { g.Key, C = g.Count() }).ToListAsync(ct);
        return Ok(AppResponse<object>.Success(new
        {
            total,
            page,
            pageSize,
            creates = counts.FirstOrDefault(c => c.Key == "Create")?.C ?? 0,
            updates = counts.FirstOrDefault(c => c.Key == "Update")?.C ?? 0,
            deletes = counts.FirstOrDefault(c => c.Key == "Delete")?.C ?? 0,
            items = rows.Select(ToRow),
        }));
    }

    /// <summary>Chi tiết một thao tác: từng bản ghi + trường đổi (cũ → mới).</summary>
    [HttpGet("{id:guid}")]
    [RequireModulePermission("ActivityLog", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Detail(Guid id, CancellationToken ct)
    {
        var storeId = RequiredStoreId;
        var a = await db.AuditLogs.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == storeId, ct);
        if (a == null) return NotFound(AppResponse<object>.Fail("Không tìm thấy thao tác"));
        object? details = null;
        try { details = JsonSerializer.Deserialize<JsonElement>(a.Details ?? "{}"); } catch (JsonException) { }
        return Ok(AppResponse<object>.Success(new { row = ToRow(a), details, userAgent = a.UserAgent }));
    }

    /// <summary>Danh sách người thao tác + chức năng có trong kỳ (cho ô lọc).</summary>
    [HttpGet("filters")]
    [RequireModulePermission("ActivityLog", ModulePermissionAction.View)]
    public async Task<ActionResult<AppResponse<object>>> Filters([FromQuery] DateTime? from, [FromQuery] DateTime? to, CancellationToken ct)
    {
        var q = Base(from, to);
        var users = await q.Where(a => a.UserId != null)
            .GroupBy(a => new { a.UserId, a.UserName, a.UserEmail })
            .Select(g => new { g.Key.UserId, g.Key.UserName, g.Key.UserEmail, Count = g.Count() })
            .ToListAsync(ct);
        var modules = await q.GroupBy(a => a.EntityType).Select(g => new { Code = g.Key, Count = g.Count() }).ToListAsync(ct);
        return Ok(AppResponse<object>.Success(new
        {
            retentionDays = ActivityLogCleanupService.RetentionDays,
            users = users.GroupBy(u => u.UserId).Select(g => new
            {
                userId = g.Key,
                name = g.Select(x => x.UserName).FirstOrDefault(n => !string.IsNullOrWhiteSpace(n)) ?? g.First().UserEmail,
                email = g.First().UserEmail,
                count = g.Sum(x => x.Count),
            }).OrderByDescending(x => x.count),
            modules = modules.Select(m => new { code = m.Code, name = ActivityAuditFilter.ModuleLabel(m.Code), count = m.Count })
                .OrderBy(m => m.name),
        }));
    }

    [HttpGet("export")]
    [RequireModulePermission("ActivityLog", ModulePermissionAction.View)]
    public async Task<IActionResult> Export(
        [FromQuery] DateTime? from, [FromQuery] DateTime? to, [FromQuery] Guid? userId,
        [FromQuery] string? module, [FromQuery] string? action, [FromQuery] string? search, CancellationToken ct)
    {
        var rows = await Filtered(from, to, userId, module, action, search)
            .OrderByDescending(a => a.Timestamp).Take(20000).ToListAsync(ct);
        return ReportHelpers.ExcelFile("Lich su thao tac",
            new[] { "Thời gian", "Người thao tác", "Email", "Vai trò", "Chức năng", "Thao tác", "Đối tượng", "Chi tiết thay đổi", "IP" },
            (ws, start) =>
            {
                var r = start;
                foreach (var a in rows)
                {
                    var row = ToRow(a);
                    ws.Cell(r, 1).Value = ReportHelpers.ToVn(a.Timestamp).ToString("dd/MM/yyyy HH:mm:ss");
                    ws.Cell(r, 2).Value = a.UserName ?? "";
                    ws.Cell(r, 3).Value = a.UserEmail ?? "";
                    ws.Cell(r, 4).Value = a.UserRole ?? "";
                    ws.Cell(r, 5).Value = row.ModuleName;
                    ws.Cell(r, 6).Value = ActionLabel(a.Action);
                    ws.Cell(r, 7).Value = a.EntityName ?? "";
                    ws.Cell(r, 8).Value = ChangeText(a.Details);
                    ws.Cell(r, 9).Value = a.IpAddress ?? "";
                    r++;
                }
            },
            $"lich-su-thao-tac-{DateTime.UtcNow.AddHours(7):yyyyMMdd-HHmm}.xlsx", user: User);
    }

    static string ActionLabel(string action) => action switch
    {
        "Create" => "Thêm",
        "Update" => "Sửa",
        "Delete" => "Xóa",
        _ => action,
    };

    /// <summary>«Tên trường: cũ → mới; …» cho file Excel.</summary>
    static string ChangeText(string? details)
    {
        try
        {
            using var doc = JsonDocument.Parse(details ?? "{}");
            if (!doc.RootElement.TryGetProperty("changes", out var changes)) return "";
            var parts = new List<string>();
            foreach (var c in changes.EnumerateArray())
            {
                var head = $"{c.GetProperty("typeName").GetString()}{(c.TryGetProperty("label", out var l) && l.ValueKind == JsonValueKind.String ? " «" + l.GetString() + "»" : "")}";
                var fields = c.GetProperty("fields").EnumerateArray()
                    .Select(f => $"{f.GetProperty("field").GetString()}: {Val(f, "old")} → {Val(f, "new")}")
                    .ToList();
                parts.Add(fields.Count == 0 ? head : $"{head} [{string.Join("; ", fields)}]");
            }
            var s = string.Join(" | ", parts);
            return s.Length > 32000 ? s[..32000] : s;
        }
        catch (Exception)
        {
            return "";
        }
    }

    static string Val(JsonElement f, string name) =>
        f.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString()! : "—";

    static LogRow ToRow(AuditLog a)
    {
        string? endpoint = null;
        var count = 0;
        try
        {
            using var doc = JsonDocument.Parse(a.Details ?? "{}");
            if (doc.RootElement.TryGetProperty("endpoint", out var e)) endpoint = e.GetString();
            if (doc.RootElement.TryGetProperty("changes", out var c)) count = c.GetArrayLength();
        }
        catch (JsonException) { }
        return new LogRow(a.Id, a.Timestamp, a.UserId, a.UserName, a.UserEmail, a.UserRole,
            a.EntityType, ActivityAuditFilter.ModuleLabel(a.EntityType), a.Action, a.EntityName, endpoint,
            a.IpAddress, DeviceOf(a.UserAgent), count);
    }

    /// <summary>Thiết bị ngắn gọn từ User-Agent: App Android / iOS / Trình duyệt Windows…</summary>
    static string? DeviceOf(string? ua)
    {
        if (string.IsNullOrWhiteSpace(ua)) return null;
        var u = ua.ToLowerInvariant();
        var os = u.Contains("android") ? "Android" : u.Contains("iphone") || u.Contains("ipad") || u.Contains("ios") ? "iOS"
            : u.Contains("windows") ? "Windows" : u.Contains("mac os") ? "macOS" : u.Contains("linux") ? "Linux" : "";
        var kind = u.Contains("dart") ? "App" : "Trình duyệt";
        return os.Length == 0 ? kind : $"{kind} {os}";
    }
}
