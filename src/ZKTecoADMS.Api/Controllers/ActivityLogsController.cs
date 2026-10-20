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
        string? IpAddress, string? Device, int ChangeCount, int FieldCount);

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
                && a.Details != null && a.Details.Contains(marker)
                // Nhật ký cũ của telemetry mạng / log QR (nay không ghi nữa) — ẩn khỏi danh sách.
                && !a.Details.Contains("\"type\":\"PosNetworkSample\"")
                && !a.Details.Contains("\"type\":\"PosQrRequestLog\""));
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
        return Ok(AppResponse<object>.Success(new { row = ToRow(a), details = LocalizedDetails(a.Details), userAgent = a.UserAgent }));
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
    [RequireModulePermission("ActivityLog", ModulePermissionAction.Export)]
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
                    ws.Cell(r, 4).Value = row.UserRole ?? "";
                    ws.Cell(r, 5).Value = row.ModuleName;
                    ws.Cell(r, 6).Value = ActionLabel(a.Action);
                    ws.Cell(r, 7).Value = row.EntityName ?? "";
                    ws.Cell(r, 8).Value = ChangeText(a.Details);
                    ws.Cell(r, 9).Value = a.IpAddress ?? "";
                    r++;
                }
            },
            $"lich-su-thao-tac-{DateTime.UtcNow.AddHours(7):yyyyMMdd-HHmm}.xlsx", user: User);
    }

    internal static string ActionLabel(string action) => action switch
    {
        "Create" => "Thêm",
        "Update" => "Sửa",
        "Delete" => "Xóa",
        _ => action,
    };

    /// <summary>«Tên trường: cũ → mới; …» cho file Excel.</summary>
    internal static string ChangeText(string? details)
    {
        try
        {
            using var doc = JsonDocument.Parse(details ?? "{}");
            if (!doc.RootElement.TryGetProperty("changes", out var changes)) return "";
            var parts = new List<string>();
            foreach (var c in changes.EnumerateArray())
            {
                var type = Str(c, "type") ?? Str(c, "typeName") ?? "";
                var label = Str(c, "label");
                var head = $"{ActivityLabels.Entity(type)}{(string.IsNullOrWhiteSpace(label) || ActivityLabels.IsGuid(label) ? "" : " «" + label + "»")}";
                var fields = c.GetProperty("fields").EnumerateArray()
                    .Select(f => $"{ActivityLabels.Field(Str(f, "field"))}: {Val(f, "old")} → {Val(f, "new")}")
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
        f.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? ActivityLabels.Value(v.GetString())! : "—";

    static string? Str(JsonElement e, string name) =>
        e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    /// <summary>Loại bản ghi con (dòng / biến động / snapshot) — không nên là bản ghi chính của dòng nhật ký.</summary>
    static readonly HashSet<string> DetailTypes = new(StringComparer.Ordinal)
    {
        "PosStockTransaction", "StockTransaction", "PosSaleCommissionLine", "PosCustomerPointTransaction",
        "PosCustomerSessionTransaction", "PayslipAttendanceSnapshot", "PosShipmentEvent", "PosQuoteActivity",
        "TaskHistory", "PosResourceSession", "PosStockLot", "ApprovalRecord", "ApprovalStep",
    };

    static bool IsDetailType(string? t) =>
        t != null && (t.EndsWith("Line", StringComparison.Ordinal) || DetailTypes.Contains(t));

    /// <summary>Trường nhiễu (bộ đếm phiên bản / concurrency) — ẩn khỏi nhật ký cũ lúc đọc.</summary>
    static readonly HashSet<string> NoiseFields = new(StringComparer.OrdinalIgnoreCase)
    {
        "LockVersion", "VersionLock", "Version", "xmin", "ConcurrencyToken", "ConcurrencyStamp", "RowVersion", "Revision",
        "ReservedQty",
    };

    static bool IsNoiseField(string? f) => f != null && NoiseFields.Contains(f);

    /// <summary>Chọn bản ghi chính để đặt tên dòng: ưu tiên chứng từ gốc (không phải dòng con) khớp thao tác.</summary>
    static JsonElement PickMain(List<JsonElement> list, string action)
    {
        // Có hóa đơn trong lần lưu → hóa đơn là bản ghi chính (kho, phiếu thu… chỉ là phát sinh kèm theo).
        // Một lần lưu có thể có vài bản thay đổi hóa đơn: ưu tiên bản chuyển Hoàn tất, rồi bản nhiều trường nhất.
        var orders = list.Where(c => Str(c, "type") == "PosSaleOrder").ToList();
        if (orders.Count > 0)
            return orders.FirstOrDefault(c => FieldNew(c, "Status") == "Completed") is { ValueKind: JsonValueKind.Object } done
                ? done
                : orders.OrderByDescending(c => c.TryGetProperty("fields", out var f) && f.ValueKind == JsonValueKind.Array
                    ? f.GetArrayLength() : 0).First();
        JsonElement? headAction = null, anyAction = null, head = null;
        foreach (var c in list)
        {
            var op = Str(c, "op");
            var ty = Str(c, "type");
            if (op == action && !IsDetailType(ty)) headAction ??= c;
            if (op == action) anyAction ??= c;
            if (!IsDetailType(ty)) head ??= c;
        }
        return headAction ?? anyAction ?? head ?? list[0];
    }

    static readonly System.Globalization.CultureInfo Vi = System.Globalization.CultureInfo.GetCultureInfo("vi-VN");
    static readonly System.Globalization.CultureInfo Inv = System.Globalization.CultureInfo.InvariantCulture;

    /// <summary>Bản ghi phát sinh kèm khi bán (kho, phiếu thu, điểm, hoa hồng…) — trong nhật ký bán hàng chỉ hiện tiêu đề.</summary>
    static readonly HashSet<string> SaleSideTypes = new(StringComparer.Ordinal)
    {
        "PosStockTransaction", "StockTransaction", "CashTransaction", "PosCustomerPointTransaction",
        "PosSaleCommissionLine", "PosStockLot", "PosCustomerSessionTransaction", "PosResourceSession",
    };

    /// <summary>Nhật ký bán hàng: chỉ giữ các trường người dùng quan tâm của hóa đơn / dòng hàng.</summary>
    static readonly Dictionary<string, HashSet<string>> SaleKeepFields = new(StringComparer.Ordinal)
    {
        ["PosSaleOrder"] = new(StringComparer.OrdinalIgnoreCase)
        {
            "Total", "SubTotal", "PaidAmount", "DiscountAmount", "Status", "PaymentMethod", "CustomerName", "Note",
            "VatAmount", "ShippingFee",
        },
        ["PosSaleOrderLine"] = new(StringComparer.OrdinalIgnoreCase)
        {
            "ProductName", "Qty", "Quantity", "UnitPrice", "LineTotal", "DiscountAmount", "LineNote",
        },
    };

    /// <summary>Trường tồn kho hệ thống tự cập nhật khi bán.</summary>
    static readonly HashSet<string> StockFields = new(StringComparer.OrdinalIgnoreCase)
    {
        "OnHandQty", "OnHand", "StockQuantity", "ReservedQty", "QtyOnHand",
    };

    /// <summary>Trường số tiền — hiển thị tách nghìn (15000 → 15.000).</summary>
    static readonly HashSet<string> MoneyFields = new(StringComparer.OrdinalIgnoreCase)
    {
        "Total", "SubTotal", "PaidAmount", "Amount", "UnitPrice", "LineTotal", "LineAmount", "DiscountAmount",
        "BasePrice", "SalePrice", "CostPrice", "UnitCost", "VatAmount", "ShippingFee", "BalanceDue", "Deposit",
        "DepositAmount", "OpeningFee", "Salary", "BaseSalary", "GrossSalary", "NetSalary", "Price",
    };

    /// <summary>Giá trị hiển thị: tiền tách nghìn, còn lại theo ActivityLabels.Value.</summary>
    static string? Disp(string? field, string? raw) =>
        field != null && MoneyFields.Contains(field)
        && decimal.TryParse(raw, System.Globalization.NumberStyles.Number, Inv, out var m)
            ? m.ToString("#,##0.##", Vi)
            : ActivityLabels.Value(raw);

    static string? FieldNew(JsonElement c, string field)
    {
        if (!c.TryGetProperty("fields", out var fs) || fs.ValueKind != JsonValueKind.Array) return null;
        foreach (var f in fs.EnumerateArray())
            if (string.Equals(Str(f, "field"), field, StringComparison.OrdinalIgnoreCase)) return Str(f, "new");
        return null;
    }

    static bool IsSaleCompletion(JsonElement main, string action) =>
        Str(main, "type") == "PosSaleOrder" && (action == "Create" || FieldNew(main, "Status") == "Completed");

    static string Qty(string? raw) =>
        decimal.TryParse(raw, System.Globalization.NumberStyles.Number, Inv, out var q)
            ? Math.Abs(q).ToString("0.##", Inv) : "";

    /// <summary>«Hóa đơn «HD..» · 15.000đ · coca cola ×1» — một dòng đọc là hiểu đơn bán gì.</summary>
    static string SaleSummary(JsonElement main, List<JsonElement> list)
    {
        var parts = new List<string> { ActivityLabels.Summary("PosSaleOrder", Str(main, "label"), 1) };
        var total = FieldNew(main, "Total") ?? FieldNew(main, "PaidAmount");
        if (decimal.TryParse(total, System.Globalization.NumberStyles.Number, Inv, out var t) && t > 0)
            parts.Add($"{t.ToString("#,##0", Vi)}đ");

        // Món: dòng hóa đơn → biến động kho (tên lấy từ hàng hóa cùng lần lưu) → tên hàng hóa.
        var names = list.Where(c => Str(c, "type") == "PosProduct")
            .Select(c => (id: Str(c, "id"), label: Str(c, "label")))
            .Where(x => x.id != null && !string.IsNullOrWhiteSpace(x.label))
            .GroupBy(x => x.id!).ToDictionary(g => g.Key, g => g.First().label!);
        var items = new List<string>();
        // Bỏ dòng bị xóa (lúc thanh toán dòng được xóa rồi tạo lại) để không lặp tên món.
        foreach (var c in list.Where(c => Str(c, "type") == "PosSaleOrderLine" && Str(c, "op") != "Delete"))
        {
            var n = Str(c, "label");
            if (string.IsNullOrWhiteSpace(n) || ActivityLabels.IsGuid(n)) continue;
            var q = Qty(FieldNew(c, "Quantity") ?? FieldNew(c, "Qty"));
            items.Add(q.Length > 0 ? $"{n} ×{q}" : n);
        }
        if (items.Count == 0)
            foreach (var c in list.Where(c => Str(c, "type") == "PosStockTransaction"))
            {
                var pid = FieldNew(c, "ProductId");
                if (pid == null || !names.TryGetValue(pid, out var n)) continue;
                var q = Qty(FieldNew(c, "QtyChange") ?? FieldNew(c, "Quantity"));
                items.Add(q.Length > 0 ? $"{n} ×{q}" : n);
            }
        if (items.Count == 0) items.AddRange(names.Values.Distinct());
        if (items.Count > 0)
            parts.Add(items.Count > 3 ? $"{string.Join(", ", items.Take(3))} +{items.Count - 3} món" : string.Join(", ", items));
        var s = string.Join(" · ", parts);
        return s.Length > 300 ? s[..300] : s;
    }

    /// <summary>Tên dòng nhật ký: «Loại «nhãn»» + với thao tác Sửa thì ghèm 1–2 trường đổi (cũ → mới) để biết «sửa gì».</summary>
    static string BuildEntityName(JsonElement main, string type, string action, int count, List<JsonElement> list)
    {
        if (IsSaleCompletion(main, action)) return SaleSummary(main, list);
        var baseName = ActivityLabels.Summary(type, Str(main, "label"), count);
        if (action != "Update" || !main.TryGetProperty("fields", out var fs) || fs.ValueKind != JsonValueKind.Array)
            return baseName;
        var parts = new List<string>();
        foreach (var f in fs.EnumerateArray())
        {
            if (parts.Count >= 2) break;
            if (IsNoiseField(Str(f, "field"))) continue;
            var fn = ActivityLabels.Field(Str(f, "field"));
            if (string.IsNullOrWhiteSpace(fn)) continue;
            var ov = Disp(Str(f, "field"), Str(f, "old")) ?? "—";
            var nv = Disp(Str(f, "field"), Str(f, "new")) ?? "—";
            if (ov == nv) continue; // vd giờ chỉ lệch vài giây
            parts.Add($"{fn}: {ov} → {nv}");
        }
        if (parts.Count == 0) return baseName;
        var s = $"{baseName} · {string.Join("; ", parts)}";
        return s.Length > 300 ? s[..300] : s;
    }

    /// <summary>Chi tiết đã Việt hóa: tên loại, tên trường, giá trị (áp dụng cả nhật ký cũ).</summary>
    internal static object LocalizedDetails(string? json)
    {
        try
        {
            using var doc = JsonDocument.Parse(json ?? "{}");
            var root = doc.RootElement;
            var changes = new List<object>();
            if (root.TryGetProperty("changes", out var arr) && arr.ValueKind == JsonValueKind.Array)
            {
                // Nhật ký bán hàng: hóa đơn lên đầu; kho / phiếu thu / tồn hàng hóa chỉ hiện tiêu đề (bớt «một tràn»).
                var all = arr.EnumerateArray().ToList();
                var isSale = all.Any(c => Str(c, "type") == "PosSaleOrder");
                var ordered = isSale ? all.OrderBy(c => Str(c, "type") == "PosSaleOrder" ? 0 : 1).ToList() : all;
                foreach (var c in ordered)
                {
                    var type = Str(c, "type") ?? "";
                    var label = Str(c, "label");
                    // Lúc thanh toán dòng hàng bị xóa rồi tạo lại — bỏ bản xóa để không lặp món.
                    if (isSale && type == "PosSaleOrderLine" && Str(c, "op") == "Delete") continue;
                    SaleKeepFields.TryGetValue(type, out var keep);
                    if (!isSale) keep = null;
                    var collapse = isSale && (SaleSideTypes.Contains(type)
                        || (type == "PosProduct" && c.TryGetProperty("fields", out var pf) && pf.ValueKind == JsonValueKind.Array
                            && pf.EnumerateArray().All(f => StockFields.Contains(Str(f, "field") ?? "") || IsNoiseField(Str(f, "field")))));
                    var fields = !collapse && c.TryGetProperty("fields", out var fs) && fs.ValueKind == JsonValueKind.Array
                        ? fs.EnumerateArray().Select(f =>
                        {
                            var field = Str(f, "field") ?? "";
                            var oldV = Str(f, "old");
                            var newV = Str(f, "new");
                            return new
                            {
                                field,
                                fieldName = ActivityLabels.Field(field),
                                old = Disp(field, oldV),
                                @new = Disp(field, newV),
                            };
                        })
                        // Thêm mới: bỏ các trường chỉ là mã nội bộ (vô nghĩa với người xem).
                        .Where(f => !(f.old == null && f.@new != null && f.@new.StartsWith('#') && f.field.EndsWith("Id")))
                        // Bỏ trường nhiễu (bộ đếm phiên bản / concurrency) và «đổi» mà hiển thị như nhau.
                        .Where(f => !IsNoiseField(f.field))
                        .Where(f => !(f.old != null && f.old == f.@new))
                        // Đơn bán: chỉ trường chính của hóa đơn / dòng hàng; giảm giá 0 thì bỏ.
                        .Where(f => keep == null || keep.Contains(f.field))
                        .Where(f => !(keep != null && f.field.Contains("Discount", StringComparison.OrdinalIgnoreCase) && f.@new == "0"))
                        .ToList<object>()
                        : [];
                    // Bản thay đổi hóa đơn phụ không còn trường nào (vd chỉ gỡ phiên phòng) — bỏ hẳn.
                    if (isSale && type == "PosSaleOrder" && fields.Count == 0) continue;
                    changes.Add(new
                    {
                        type,
                        typeName = ActivityLabels.Entity(type),
                        id = Str(c, "id"),
                        op = Str(c, "op"),
                        label = ActivityLabels.IsGuid(label) ? null : label,
                        fields,
                    });
                }
            }
            return new { source = Str(root, "source"), endpoint = Str(root, "endpoint"), changes };
        }
        catch (Exception)
        {
            return new { changes = Array.Empty<object>() };
        }
    }

    internal static LogRow ToRow(AuditLog a)
    {
        string? endpoint = null;
        var count = 0;
        var fieldCount = 0;
        var entityName = a.EntityName;
        try
        {
            using var doc = JsonDocument.Parse(a.Details ?? "{}");
            if (doc.RootElement.TryGetProperty("endpoint", out var e)) endpoint = e.GetString();
            if (doc.RootElement.TryGetProperty("changes", out var c) && c.ValueKind == JsonValueKind.Array)
            {
                count = c.GetArrayLength();
                // Tổng số trường thực sự đổi (bỏ field nhiễu) — để danh sách cho biết «sửa gì» ở mức liếc nhìn.
                foreach (var ch in c.EnumerateArray())
                    if (ch.TryGetProperty("fields", out var fs) && fs.ValueKind == JsonValueKind.Array)
                        fieldCount += fs.EnumerateArray().Count(f => !IsNoiseField(Str(f, "field")));
                // Dựng lại tóm tắt bằng tiếng Việt (nhật ký cũ lưu tên kỹ thuật).
                var list = c.EnumerateArray().ToList();
                if (list.Count > 0)
                {
                    var main = PickMain(list, a.Action);
                    if (main.ValueKind == JsonValueKind.Object && Str(main, "type") is { } type)
                    {
                        entityName = BuildEntityName(main, type, a.Action, count, list);
                        // Đơn bán đã tóm tắt đủ (số HĐ · tiền · món) — không đếm hàng chục trường phát sinh.
                        if (IsSaleCompletion(main, a.Action)) fieldCount = 0;
                    }
                }
            }
        }
        catch (JsonException) { }
        // Giờ VN (cột lưu UTC, không Kind) — app hiển thị thẳng; trước đây lệch 7 tiếng.
        return new LogRow(a.Id, ReportHelpers.ToVn(a.Timestamp), a.UserId, a.UserName, a.UserEmail, ActivityLabels.Role(a.UserRole),
            a.EntityType, ActivityAuditFilter.ModuleLabel(a.EntityType), a.Action, entityName, endpoint,
            a.IpAddress, DeviceOf(a.UserAgent), count, fieldCount);
    }

    /// <summary>Thiết bị ngắn gọn từ User-Agent: App Android / iOS / Trình duyệt Windows…</summary>
    internal static string? DeviceOf(string? ua)
    {
        if (string.IsNullOrWhiteSpace(ua)) return null;
        var u = ua.ToLowerInvariant();
        var os = u.Contains("android") ? "Android" : u.Contains("iphone") || u.Contains("ipad") || u.Contains("ios") ? "iOS"
            : u.Contains("windows") ? "Windows" : u.Contains("mac os") ? "macOS" : u.Contains("linux") ? "Linux" : "";
        var kind = u.Contains("dart") ? "App" : "Trình duyệt";
        return os.Length == 0 ? kind : $"{kind} {os}";
    }
}
