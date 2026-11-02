using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Thêm các việc hay nói bằng lời: xin nghỉ phép (cho mình / nhân viên), lập báo giá, đặt bàn / phòng / lịch hẹn, thêm nhân viên
/// mới. Như mọi thao tác khác: trợ lý chỉ dựng thẻ chờ xác nhận, bấm «Xác nhận» mới gọi API thật của app bằng phiên người dùng.
/// </summary>
public sealed partial class AiAssistantActions
{
    static readonly Def[] MoreDefs =
    [
        new("propose_leave", "Leave", 'C', false,
            "Gửi ĐƠN NGHỈ PHÉP (chờ duyệt). Không có employee_id = xin nghỉ cho chính người hỏi. "
            + "Ca nghỉ tự lấy theo lịch làm việc; cửa hàng nhiều ca mà chưa xếp lịch → hỏi ca rồi truyền shift_id (find_shift_templates).",
            new()
            {
                ["employee_id"] = ("STRING", "Id nhân viên (find_employees) — chỉ khi quản lý tạo đơn cho người khác"),
                ["from"] = ("STRING", "Nghỉ từ ngày yyyy-MM-dd"),
                ["to"] = ("STRING", "Đến ngày yyyy-MM-dd (bỏ trống = nghỉ 1 ngày)"),
                ["type"] = ("STRING", "annual (phép năm, mặc định) | personal_paid (việc riêng có lương) | personal_unpaid (không lương) | sick (ốm) | compensatory (nghỉ bù) | maternity (thai sản)"),
                ["half"] = ("BOOLEAN", "true = nghỉ nửa ca"),
                ["shift_id"] = ("STRING", "Id ca nghỉ (find_shift_templates) — bỏ trống = theo lịch làm việc"),
                ["reason"] = ("STRING", "Lý do"),
            }, ["from"]),
        new("propose_quote", "PosQuotes", 'C', false,
            "Lập BÁO GIÁ cho khách (bản nháp, chưa trừ kho). Tìm hàng bằng find_products, khách bằng find_customers.",
            new()
            {
                ["items"] = ("ARRAY", "Hàng báo giá {product_id, qty, price (bỏ trống = giá bán)}"),
                ["customer_id"] = ("STRING", "Id khách (find_customers) — bỏ trống nếu khách mới"),
                ["customer_name"] = ("STRING", "Tên khách / công ty (khách chưa có trong danh bạ)"),
                ["phone"] = ("STRING", "SĐT khách"),
                ["address"] = ("STRING", "Địa chỉ khách"),
                ["valid_days"] = ("INTEGER", "Hiệu lực bao nhiêu ngày (mặc định 7)"),
                ["discount"] = ("NUMBER", "Chiết khấu cả báo giá VNĐ"),
                ["note"] = ("STRING", "Ghi chú"),
            }, ["items"]),
        new("propose_reservation", "PosBooking", 'C', false,
            "ĐẶT BÀN / ĐẶT PHÒNG / ĐẶT LỊCH HẸN cho khách. Lấy resource_id bằng find_resources; dịch vụ (salon, spa) bằng find_products.",
            new()
            {
                ["resource_id"] = ("STRING", "Id bàn / phòng / ghế (find_resources)"),
                ["customer_name"] = ("STRING", "Tên khách"),
                ["phone"] = ("STRING", "SĐT khách"),
                ["customer_id"] = ("STRING", "Id khách (find_customers) nếu có trong danh bạ"),
                ["date"] = ("STRING", "Ngày đến yyyy-MM-dd (mặc định hôm nay)"),
                ["time"] = ("STRING", "Giờ đến HH:mm"),
                ["guests"] = ("INTEGER", "Số khách"),
                ["duration_minutes"] = ("INTEGER", "Thời lượng hẹn (phút) — salon / phòng giờ"),
                ["nights"] = ("INTEGER", "Số đêm (khách sạn)"),
                ["service_id"] = ("STRING", "Id dịch vụ hẹn làm (find_products) — salon / spa"),
                ["note"] = ("STRING", "Ghi chú / yêu cầu đặc biệt"),
            }, ["resource_id", "time"]),
        new("propose_employee", "Employee", 'C', true,
            "THÊM NHÂN VIÊN MỚI vào hồ sơ nhân sự (mã nhân viên tự sinh nếu không nói).",
            new()
            {
                ["full_name"] = ("STRING", "Họ và tên"),
                ["phone"] = ("STRING", "Số điện thoại"),
                ["department"] = ("STRING", "Phòng ban"),
                ["position"] = ("STRING", "Chức vụ"),
                ["join_date"] = ("STRING", "Ngày vào làm yyyy-MM-dd (mặc định hôm nay)"),
                ["employment"] = ("STRING", "monthly (lương tháng, mặc định) | hourly (lương giờ)"),
                ["gender"] = ("STRING", "Nam | Nữ"),
                ["birth_date"] = ("STRING", "Ngày sinh yyyy-MM-dd"),
                ["code"] = ("STRING", "Mã nhân viên (bỏ trống = tự sinh)"),
                ["probation"] = ("BOOLEAN", "true = đang thử việc"),
            }, ["full_name"]),
    ];

    static readonly string[] MoreFinders = ["find_resources"];

    void AddMoreFinders(Ctx c, List<Def> allowed, List<object> decls)
    {
        bool Has(params string[] names) => allowed.Any(d => names.Contains(d.Name));
        void Add(string name, string desc, Dictionary<string, (string Type, string Desc)> ps, string[] req)
        {
            if (!Declared(decls, name)) decls.Add(Fn(name, desc, ps, req));
        }
        if (Has("propose_leave"))
        {
            Add("find_shift_templates", "Danh sách ca làm việc của cửa hàng → shift_id, giờ vào–ra.", new(), []);
            if (IsManager(c))
                Add("find_employees", "Tìm nhân viên theo tên / mã (không dấu cũng được) → id dùng cho các công cụ đề xuất.",
                    new() { ["query"] = ("STRING", "Tên hoặc mã nhân viên") }, ["query"]);
        }
        if (Has("propose_quote", "propose_reservation"))
        {
            Add("find_products", "Tìm hàng hóa / dịch vụ theo tên / mã / mã vạch → id, giá bán, giá vốn, đơn vị, tồn.",
                new() { ["query"] = ("STRING", "Tên / mã hàng") }, ["query"]);
            Add("find_customers", "Tìm khách hàng theo tên / SĐT.", new() { ["query"] = ("STRING", "Tên / SĐT") }, ["query"]);
        }
        if (Has("propose_reservation"))
            Add("find_resources", "Bàn / phòng / ghế của cửa hàng (tên, khu vực, sức chứa) → resource_id để đặt chỗ.",
                new() { ["query"] = ("STRING", "Tên bàn / phòng / khu vực (bỏ trống = tất cả)") }, []);
    }

    async Task<object> MoreFindAsync(string tool, Dictionary<string, object?> a, Ctx c, CancellationToken ct)
    {
        if (!AllowedDefs(c).Any(d => d.Name == "propose_reservation"))
            return new { error = "Tài khoản không có quyền đặt bàn / đặt lịch." };
        var rows = await db.PosServiceResources.AsNoTracking()
            .Where(r => r.StoreId == c.StoreId && r.Deleted == null && r.IsActive)
            .OrderBy(r => r.SortOrder).ThenBy(r => r.Name)
            .Select(r => new { r.Id, r.Name, r.Code, r.ResourceKind, r.Capacity, Area = r.Area != null ? r.Area.Name : null })
            .Take(300).ToListAsync(ct);
        if (rows.Count == 0) return new { ket_qua = "Cửa hàng chưa tạo bàn / phòng — tạo ở Thiết lập SBOX › Bàn / phòng." };
        var q = VnSearch.FoldText(S(a, "query"));
        var hits = q.Length == 0 ? rows : rows.Where(r => VnSearch.Has($"{r.Name} {r.Code} {r.Area}", q)).ToList();
        if (hits.Count == 0) return new { ket_qua = "Không có bàn / phòng khớp", tat_ca = rows.Take(40).Select(r => r.Name) };
        return new
        {
            ket_qua = hits.Take(60).Select(r => new
            {
                id = r.Id, ten = r.Name, khu = r.Area,
                loai = r.ResourceKind switch
                {
                    PosResourceKind.Table => "bàn", PosResourceKind.Room => "phòng", PosResourceKind.Chair => "ghế", _ => "khác",
                },
                suc_chua = r.Capacity,
            }),
        };
    }

    Task<Pending?> MoreProposalAsync(string tool, Ctx c, Dictionary<string, object?> a, CancellationToken ct) => tool switch
    {
        "propose_leave" => Wrap(LeaveAsync(c, a, ct)),
        "propose_quote" => Wrap(QuoteAsync(c, a, ct)),
        "propose_reservation" => Wrap(ReservationAsync(c, a, ct)),
        "propose_employee" => Wrap(EmployeeAsync(c, a, ct)),
        _ => Task.FromResult<Pending?>(null),
    };

    static List<Step>? MoreUndoSteps(Pending p, string? docId, JsonNode? data)
    {
        // Thêm nhân viên trả về id trần (không phải đối tượng).
        if (p.Kind == "employee" && docId == null && data is JsonValue v && Guid.TryParse(v.ToString(), out var eid))
            docId = eid.ToString();
        if (string.IsNullOrEmpty(docId)) return null;
        Step? s = p.Kind switch
        {
            "leave" => new("DELETE", $"/api/Leaves/{docId}", null),
            "quote" => new("DELETE", $"/api/pos/quotes/{docId}", null),
            "reservation" => new("POST", $"/api/pos/resource-reservations/{docId}/cancel", null),
            "employee" => new("DELETE", $"/api/Employees/{docId}", null),
            _ => null,
        };
        return s == null ? null : [s];
    }

    // ─── 1. Nghỉ phép ──────────────────────────────────────────────

    static readonly Dictionary<string, (LeaveType Type, string Label)> LeaveTypes = new()
    {
        ["annual"] = (LeaveType.AnnualLeave, "Phép năm"),
        ["personal_paid"] = (LeaveType.PersonalPaid, "Việc riêng có lương"),
        ["personal_unpaid"] = (LeaveType.PersonalUnpaid, "Nghỉ không lương"),
        ["sick"] = (LeaveType.SickLeave, "Nghỉ ốm"),
        ["compensatory"] = (LeaveType.CompensatoryLeave, "Nghỉ bù"),
        ["maternity"] = (LeaveType.MaternityLeave, "Thai sản"),
    };

    async Task<Pending> LeaveAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var e = await ResolveEmployeeAsync(c, G(a, "employee_id"), true, ct);
        var self = e.UserId == c.UserId;
        var userId = e.UserId ?? throw new ActionError($"{e.Name} chưa có tài khoản đăng nhập — tạo đơn nghỉ ở màn Nghỉ phép.");
        var from = D(a, "from") ?? throw new ActionError("Ngày nghỉ không hợp lệ (yyyy-MM-dd).");
        var to = D(a, "to") ?? from;
        if (to < from) throw new ActionError("Ngày kết thúc trước ngày bắt đầu.");
        if ((to - from).TotalDays > 60) throw new ActionError("Đơn nghỉ quá 60 ngày — tạo ở màn Nghỉ phép.");
        var key = (S(a, "type") ?? "annual").ToLowerInvariant();
        var (type, typeLabel) = LeaveTypes.TryGetValue(key, out var lt) ? lt : LeaveTypes["annual"];
        var half = Bool(a, "half");

        // Ca nghỉ: ca chỉ định → ca trong lịch làm việc các ngày nghỉ → cửa hàng chỉ có một ca.
        var shifts = await db.ShiftTemplates.AsNoTracking().Where(s => s.StoreId == c.StoreId && s.IsActive)
            .Select(s => new { s.Id, s.Name, s.StartTime, s.EndTime }).ToListAsync(ct);
        var shiftIds = new List<Guid>();
        if (G(a, "shift_id") is Guid sid)
        {
            if (shifts.All(s => s.Id != sid)) throw new ActionError("Ca không hợp lệ — dùng find_shift_templates lấy đúng shift_id.");
            shiftIds.Add(sid);
        }
        else
        {
            var toEnd = to.AddDays(1);
            shiftIds = await db.WorkSchedules.AsNoTracking()
                .Where(w => w.EmployeeUserId == userId && w.Deleted == null && !w.IsDayOff && w.ShiftId != null
                            && w.Date >= from && w.Date < toEnd)
                .Select(w => w.ShiftId!.Value).Distinct().ToListAsync(ct);
            shiftIds = shiftIds.Where(id => shifts.Any(s => s.Id == id)).ToList();
            if (shiftIds.Count == 0 && shifts.Count == 1) shiftIds.Add(shifts[0].Id);
            if (shiftIds.Count == 0)
                throw new ActionError(shifts.Count == 0
                    ? "Cửa hàng chưa tạo ca làm việc — tạo ở Thiết lập SBOX › Ca làm việc rồi xin nghỉ."
                    : "Chưa có lịch làm việc những ngày này — hỏi người dùng nghỉ ca nào (find_shift_templates) rồi truyền shift_id.");
        }
        var shiftLabel = string.Join(", ", shifts.Where(s => shiftIds.Contains(s.Id))
            .Select(s => $"{s.Name} ({s.StartTime:hh\\:mm}–{s.EndTime:hh\\:mm})"));
        var days = (to - from).Days + 1;
        var warnings = new List<string>();
        if (from < AiAssistantVnTime.NowVn().Date) warnings.Add("Ngày nghỉ đã qua — đơn bổ sung.");
        return New(c, "leave", "Đơn nghỉ phép",
        [
            new("Nhân viên", e.Name),
            new("Ngày nghỉ", days == 1 ? from.ToString("dd/MM/yyyy") : $"{from:dd/MM/yyyy} → {to:dd/MM/yyyy} ({days} ngày)"),
            new("Ca", shiftLabel + (half ? " — nửa ca" : "")),
            new("Loại", typeLabel),
            new("Lý do", S(a, "reason") ?? "—"),
        ], "POST", "/api/Leaves", new
        {
            employeeUserId = self ? (Guid?)null : userId,
            employeeId = self ? (Guid?)null : e.Id,
            type = type.ToString(),
            shiftId = shiftIds[0], shiftIds,
            startDate = from.ToString("yyyy-MM-dd'T'00:00:00"), endDate = to.ToString("yyyy-MM-dd'T'00:00:00"),
            isHalfShift = half, reason = S(a, "reason") ?? "",
        }, "Leave", warnings);
    }

    // ─── 2. Báo giá ────────────────────────────────────────────────

    async Task<Pending> QuoteAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        if (a.GetValueOrDefault("items") is not JsonElement items || items.ValueKind != JsonValueKind.Array || items.GetArrayLength() == 0)
            throw new ActionError("Chưa có mặt hàng.");
        var req = items.EnumerateArray().Select(i => (
            Id: i.TryGetProperty("product_id", out var p) && Guid.TryParse(p.GetString(), out var g) ? g : Guid.Empty,
            Qty: i.TryGetProperty("qty", out var q) && q.TryGetDecimal(out var qd) ? qd : 1m,
            Price: i.TryGetProperty("price", out var pr) && pr.TryGetDecimal(out var pd) ? pd : (decimal?)null)).ToList();
        var ids = req.Select(r => r.Id).ToList();
        var products = await db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == c.StoreId && p.Deleted == null && ids.Contains(p.Id))
            .Select(p => new { p.Id, p.ProductCode, p.Name, p.BasePrice, p.BaseUnitName })
            .ToDictionaryAsync(p => p.Id, ct);
        var lines = new List<Line>();
        var body = new List<object>();
        decimal subtotal = 0;
        foreach (var r in req)
        {
            if (!products.TryGetValue(r.Id, out var p)) throw new ActionError("Có mặt hàng không tìm thấy — dùng find_products lấy đúng id.");
            if (r.Qty <= 0) throw new ActionError($"Số lượng {p.Name} không hợp lệ.");
            var price = r.Price ?? p.BasePrice;
            subtotal += price * r.Qty;
            lines.Add(new($"{r.Qty:0.##} {p.BaseUnitName} {p.Name}", Vnd(price * r.Qty)));
            body.Add(new
            {
                productId = p.Id.ToString(), productCode = p.ProductCode, productName = p.Name, unitName = p.BaseUnitName,
                qty = r.Qty, unitPrice = price,
            });
        }
        var discount = a.ContainsKey("discount") ? Money(a, "discount") : 0m;

        string? name = S(a, "customer_name"), phone = S(a, "phone"), address = S(a, "address");
        if (G(a, "customer_id") is Guid cid)
        {
            var cu = await db.PosCustomers.AsNoTracking().Where(x => x.Id == cid && x.StoreId == c.StoreId)
                         .Select(x => new { x.Name, x.Phone, x.Address }).FirstOrDefaultAsync(ct)
                     ?? throw new ActionError("Không tìm thấy khách — dùng find_customers.");
            name = cu.Name; phone ??= cu.Phone; address ??= cu.Address;
        }
        var validDays = Math.Clamp(I(a, "valid_days") ?? 7, 1, 365);
        var validUntil = AiAssistantVnTime.NowVn().Date.AddDays(validDays);
        if (discount > 0) lines.Add(new("Chiết khấu", "-" + Vnd(discount)));
        lines.Add(new("Tổng (chưa VAT)", Vnd(Math.Max(0, subtotal - discount))));
        lines.Add(new("Khách", name ?? "Chưa ghi tên"));
        lines.Add(new("Hiệu lực đến", validUntil.ToString("dd/MM/yyyy")));
        var warnings = new List<string>();
        if (name == null) warnings.Add("Báo giá chưa có tên khách — có thể bổ sung sau ở màn Báo giá.");
        return New(c, "quote", "Báo giá", lines, "POST", "/api/pos/quotes", new
        {
            customerId = G(a, "customer_id")?.ToString(), customerName = name, customerPhone = phone, customerAddress = address,
            validUntil = validUntil.ToString("yyyy-MM-dd'T'00:00:00"), note = S(a, "note"),
            lines = body, discount,
        }, "PosQuotes", warnings);
    }

    // ─── 3. Đặt bàn / phòng / lịch hẹn ─────────────────────────────

    async Task<Pending> ReservationAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var rid = G(a, "resource_id") ?? throw new ActionError("Thiếu bàn / phòng — dùng find_resources lấy id.");
        var res = await db.PosServiceResources.AsNoTracking()
                      .Where(r => r.Id == rid && r.StoreId == c.StoreId && r.Deleted == null && r.IsActive)
                      .Select(r => new { r.Name, r.Capacity, Area = r.Area != null ? r.Area.Name : null }).FirstOrDefaultAsync(ct)
                  ?? throw new ActionError("Bàn / phòng không hợp lệ — dùng find_resources lấy đúng id.");
        var date = D(a, "date") ?? AiAssistantVnTime.NowVn().Date;
        var time = T(a, "time") ?? throw new ActionError("Giờ đến không hợp lệ (HH:mm).");
        var arriveVn = date.Add(time);
        var warnings = new List<string>();
        if (arriveVn < AiAssistantVnTime.NowVn().AddMinutes(-5)) throw new ActionError("Giờ đến đã qua — hỏi lại người dùng ngày giờ.");

        string? name = S(a, "customer_name"), phone = S(a, "phone");
        var customerId = G(a, "customer_id");
        if (customerId is Guid cid)
        {
            var cu = await db.PosCustomers.AsNoTracking().Where(x => x.Id == cid && x.StoreId == c.StoreId)
                         .Select(x => new { x.Name, x.Phone }).FirstOrDefaultAsync(ct)
                     ?? throw new ActionError("Không tìm thấy khách — dùng find_customers.");
            name = cu.Name; phone ??= cu.Phone;
        }
        if (name == null) throw new ActionError("Thiếu tên khách đặt — hỏi người dùng.");

        string? serviceName = null;
        if (G(a, "service_id") is Guid svc)
            serviceName = await db.PosProducts.AsNoTracking()
                              .Where(p => p.Id == svc && p.StoreId == c.StoreId && p.Deleted == null && p.ProductType == PosProductType.Service)
                              .Select(p => p.Name).FirstOrDefaultAsync(ct)
                          ?? throw new ActionError("Dịch vụ không hợp lệ — dùng find_products lấy id dịch vụ.");
        var guests = Math.Max(1, I(a, "guests") ?? 1);
        if (res.Capacity > 0 && guests > res.Capacity) warnings.Add($"{res.Name} chứa {res.Capacity} khách, đặt {guests}.");
        var duration = I(a, "duration_minutes") is int dm && dm > 0 ? dm : (int?)null;
        var nights = I(a, "nights") is int n && n > 0 ? n : (int?)null;
        // API nhận giờ UTC.
        var arriveUtc = DateTime.SpecifyKind(arriveVn.AddHours(-AiAssistantVnTime.OffsetHours), DateTimeKind.Utc);
        var timed = duration != null || nights != null || serviceName != null;
        return New(c, "reservation", "Đặt chỗ",
        [
            new("Chỗ", res.Area is { Length: > 0 } ar ? $"{res.Name} — {ar}" : res.Name),
            new("Khách", phone != null ? $"{name} — {phone}" : name),
            new("Giờ đến", arriveVn.ToString("HH:mm dd/MM/yyyy")),
            new("Số khách", guests.ToString()),
            .. serviceName != null ? new[] { new Line("Dịch vụ", serviceName) } : [],
            .. nights != null ? new[] { new Line("Số đêm", nights.ToString()!) }
                : duration != null ? new[] { new Line("Thời lượng", $"{duration} phút") } : [],
            .. S(a, "note") is { } note ? new[] { new Line("Ghi chú", note) } : [],
        ], "POST", "/api/pos/resource-reservations", new
        {
            resourceId = rid, customerName = name, phone, guestCount = guests, customerId,
            reservedUntil = arriveUtc.ToString("o"), slotStart = timed ? arriveUtc.ToString("o") : null,
            durationMinutes = duration, stayNights = nights, serviceProductId = G(a, "service_id"),
            note = S(a, "note"), autoAssignStaff = serviceName != null,
        }, "PosBooking", warnings);
    }

    // ─── 4. Thêm nhân viên ─────────────────────────────────────────

    async Task<Pending> EmployeeAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var full = Regex.Replace(S(a, "full_name") ?? "", @"\s+", " ").Trim();
        if (full.Length < 2) throw new ActionError("Thiếu họ tên nhân viên.");
        var codes = await db.Employees.AsNoTracking().Where(e => e.StoreId == c.StoreId && e.Deleted == null)
            .Select(e => e.EmployeeCode).ToListAsync(ct);
        var code = S(a, "code") ?? NextEmployeeCode(codes);
        if (codes.Contains(code, StringComparer.OrdinalIgnoreCase)) throw new ActionError($"Mã nhân viên {code} đã có — chọn mã khác.");
        var phone = S(a, "phone");
        var warnings = new List<string>();
        if (phone != null)
        {
            var digits = Regex.Replace(phone, @"\D", "");
            var dup = await db.Employees.AsNoTracking()
                .Where(e => e.StoreId == c.StoreId && e.Deleted == null && e.PhoneNumber != null && e.PhoneNumber.Contains(digits))
                .Select(e => e.FirstName + " " + e.LastName).FirstOrDefaultAsync(ct);
            if (dup != null) warnings.Add($"SĐT trùng với nhân viên {dup.Trim()}.");
        }
        // Tách tên như màn Nhân sự: từ cuối là tên, phần trước là họ đệm.
        var parts = full.Split(' ');
        var first = parts[^1];
        var last = parts.Length > 1 ? string.Join(' ', parts[..^1]) : "";
        var join = D(a, "join_date") ?? AiAssistantVnTime.NowVn().Date;
        var hourly = (S(a, "employment") ?? "").ToLowerInvariant() is "hourly" or "giờ" or "theo giờ";
        var probation = Bool(a, "probation");
        var gender = S(a, "gender") is { } g ? (VnSearch.Fold(g).StartsWith("nu") ? "Nữ" : "Nam") : null;
        return New(c, "employee", "Nhân viên mới",
        [
            new("Họ tên", full), new("Mã nhân viên", code),
            new("SĐT", phone ?? "—"),
            new("Phòng ban / chức vụ", string.Join(" / ", new[] { S(a, "department"), S(a, "position") }.Where(x => x != null)) is { Length: > 0 } dp ? dp : "—"),
            new("Vào làm", join.ToString("dd/MM/yyyy") + (probation ? " (thử việc)" : "")),
            new("Hình thức lương", hourly ? "Theo giờ" : "Theo tháng"),
        ], "POST", "/api/Employees", new
        {
            employeeCode = code, firstName = first, lastName = last, phoneNumber = phone,
            companyEmail = $"{code}@company.com", gender,
            dateOfBirth = D(a, "birth_date")?.ToString("yyyy-MM-dd'T'00:00:00"),
            department = S(a, "department"), position = S(a, "position"),
            employmentType = hourly ? EmploymentType.Hourly.ToString() : EmploymentType.Monthly.ToString(),
            joinDate = join.ToString("yyyy-MM-dd'T'00:00:00"),
            workStatus = (probation ? EmployeeWorkStatus.Probation : EmployeeWorkStatus.Active).ToString(),
        }, "Employee", warnings);
    }

    /// <summary>Mã kế tiếp theo kiểu mã đang dùng nhiều nhất (NV007 → NV008); chưa có ai → NV001.</summary>
    internal static string NextEmployeeCode(IEnumerable<string> existing)
    {
        var parsed = existing.Select(x => Regex.Match(x ?? "", @"^(.*?)(\d+)$")).Where(m => m.Success)
            .Select(m => (Prefix: m.Groups[1].Value, Digits: m.Groups[2].Value)).ToList();
        if (parsed.Count == 0) return "NV001";
        var prefix = parsed.GroupBy(p => p.Prefix).OrderByDescending(g => g.Count()).First();
        var width = prefix.Max(p => p.Digits.Length);
        var next = prefix.Max(p => long.Parse(p.Digits)) + 1;
        return prefix.Key + next.ToString().PadLeft(width, '0');
    }
}
