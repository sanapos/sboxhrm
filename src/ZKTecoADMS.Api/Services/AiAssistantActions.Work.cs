using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Enums;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Việc hằng ngày còn thiếu: công tác phí (tạo hồ sơ + xin tạm ứng), kiến nghị, đăng ký suất ăn, sửa hồ sơ nhân viên,
/// trả nợ nhà cung cấp, xuất hóa đơn điện tử cho đơn đã bán, tiếp nhận bảo hành. Như mọi thao tác khác: chỉ dựng thẻ chờ
/// xác nhận, bấm «Xác nhận» mới gọi API thật của app bằng phiên người dùng (API tự kiểm quyền + phạm vi lần nữa).
/// </summary>
public sealed partial class AiAssistantActions
{
    static readonly Def[] WorkDefs =
    [
        new("propose_business_trip", "BusinessTripExpense", 'C', false,
            "Tạo HỒ SƠ CÔNG TÁC (đi công tác) và xin TẠM ỨNG công tác phí nếu có số tiền. Không có employee_id = cho chính người hỏi.",
            new()
            {
                ["employee_id"] = ("STRING", "Id nhân viên đi công tác (find_employees) — chỉ khi quản lý tạo cho người khác"),
                ["title"] = ("STRING", "Nội dung chuyến đi (VD «Gặp khách hàng Đà Nẵng»)"),
                ["destination"] = ("STRING", "Nơi đến"),
                ["from"] = ("STRING", "Đi từ ngày yyyy-MM-dd"),
                ["to"] = ("STRING", "Về ngày yyyy-MM-dd (bỏ trống = đi trong ngày)"),
                ["advance_amount"] = ("NUMBER", "Số tiền xin tạm ứng trước (bỏ trống = không ứng)"),
                ["note"] = ("STRING", "Ghi chú"),
            }, ["title", "from"]),
        new("propose_feedback", "Feedback", 'C', false,
            "Gửi KIẾN NGHỊ / GÓP Ý / KHIẾU NẠI tới quản lý (ẩn danh được).",
            new()
            {
                ["title"] = ("STRING", "Tiêu đề ngắn"),
                ["content"] = ("STRING", "Nội dung"),
                ["category"] = ("STRING", "suggestion (góp ý, mặc định) | complaint (khiếu nại) | general (chung) | other"),
                ["anonymous"] = ("BOOLEAN", "true = gửi ẩn danh"),
                ["recipient_id"] = ("STRING", "Gửi riêng cho một người (find_employees) — bỏ trống = gửi quản lý chung"),
            }, ["title", "content"]),
        new("propose_meal", "Meal", 'C', false,
            "ĐĂNG KÝ hoặc HỦY ĐĂNG KÝ SUẤT ĂN cho chính người hỏi. Lấy buổi ăn bằng find_meal_sessions.",
            new()
            {
                ["session_id"] = ("STRING", "Id buổi ăn (find_meal_sessions)"),
                ["dates"] = ("STRING", "Các ngày yyyy-MM-dd, cách nhau dấu phẩy (mặc định ngày mai)"),
                ["cancel"] = ("BOOLEAN", "true = hủy đăng ký"),
                ["note"] = ("STRING", "Ghi chú (VD ăn chay)"),
            }, ["session_id"]),
        new("propose_update_employee", "Employee", 'E', true,
            "SỬA HỒ SƠ NHÂN VIÊN: phòng ban, chức vụ, cấp bậc, SĐT, người quản lý trực tiếp, tài khoản ngân hàng, cho NGHỈ VIỆC. "
            + "Chỉ truyền trường cần đổi.",
            new()
            {
                ["employee_id"] = ("STRING", "Id nhân viên (find_employees)"),
                ["department"] = ("STRING", "Phòng ban mới"),
                ["position"] = ("STRING", "Chức vụ mới"),
                ["level"] = ("STRING", "Cấp bậc mới"),
                ["phone"] = ("STRING", "SĐT mới"),
                ["manager_id"] = ("STRING", "Id người quản lý trực tiếp mới (find_employees)"),
                ["bank_name"] = ("STRING", "Ngân hàng nhận lương"),
                ["bank_account"] = ("STRING", "Số tài khoản"),
                ["bank_account_name"] = ("STRING", "Tên chủ tài khoản"),
                ["resign_date"] = ("STRING", "Ngày nghỉ việc yyyy-MM-dd (cho nghỉ việc)"),
                ["resign_reason"] = ("STRING", "Lý do nghỉ việc"),
            }, ["employee_id"]),
        new("propose_supplier_payment", "PosPurchaseReceipts", 'E', false,
            "TRẢ NỢ NHÀ CUNG CẤP: trả dần các phiếu nhập còn nợ, phiếu cũ trước (ghi phiếu chi sổ quỹ). find_suppliers lấy id + số nợ.",
            new()
            {
                ["supplier_id"] = ("STRING", "Id nhà cung cấp (find_suppliers)"),
                ["amount"] = ("STRING", "Số tiền trả, hoặc «all» = trả hết nợ"),
                ["method"] = ("STRING", "cash (tiền mặt) | bank (chuyển khoản)"),
                ["note"] = ("STRING", "Ghi chú"),
            }, ["supplier_id", "amount"]),
        new("propose_einvoice", "PosEInvoice", 'A', false,
            "XUẤT HÓA ĐƠN ĐIỆN TỬ cho hóa đơn bán đã thanh toán (gửi lên hãng HĐĐT, không hủy ngang được). Lấy order_id bằng find_orders. "
            + "Khách công ty: truyền mã số thuế + tên công ty.",
            new()
            {
                ["order_id"] = ("STRING", "Id hóa đơn bán (find_orders)"),
                ["buyer_name"] = ("STRING", "Tên người mua"),
                ["tax_code"] = ("STRING", "Mã số thuế (khách công ty)"),
                ["company_name"] = ("STRING", "Tên công ty"),
                ["address"] = ("STRING", "Địa chỉ"),
                ["email"] = ("STRING", "Email nhận hóa đơn"),
            }, ["order_id"]),
        new("propose_warranty_claim", "PosWarranty", 'E', false,
            "TIẾP NHẬN BẢO HÀNH / SỬA CHỮA máy khách mang tới. Tìm máy bằng find_warranty (seri / IMEI / SĐT khách).",
            new()
            {
                ["warranty_id"] = ("STRING", "Id máy (find_warranty)"),
                ["description"] = ("STRING", "Mô tả lỗi khách báo"),
                ["condition"] = ("STRING", "Tình trạng máy lúc nhận (trầy, móp…)"),
                ["accessories"] = ("STRING", "Phụ kiện kèm theo"),
                ["return_date"] = ("STRING", "Hẹn trả yyyy-MM-dd"),
                ["note_only"] = ("BOOLEAN", "true = chỉ ghi chú vào máy, không lập phiếu sửa"),
            }, ["warranty_id", "description"]),
    ];

    static readonly string[] WorkFinders = ["find_meal_sessions", "find_warranty"];

    void AddWorkFinders(Ctx c, List<Def> allowed, List<object> decls)
    {
        bool Has(params string[] names) => allowed.Any(d => names.Contains(d.Name));
        void Add(string name, string desc, Dictionary<string, (string Type, string Desc)> ps, string[] req)
        {
            if (!Declared(decls, name)) decls.Add(Fn(name, desc, ps, req));
        }
        if (Has("propose_meal"))
            Add("find_meal_sessions", "Các buổi ăn của căn tin (tên, giờ, giá suất) → session_id.", new(), []);
        if (Has("propose_sale_order"))
            Add("find_resources", "Bàn / phòng / ghế của cửa hàng (tên, khu vực, sức chứa) → resource_id cho đơn tạm.",
                new() { ["query"] = ("STRING", "Tên bàn / phòng / khu vực (bỏ trống = tất cả)") }, []);
        if (Has("propose_warranty_claim"))
            Add("find_warranty", "Tìm máy đang bảo hành theo số seri / IMEI / tên / SĐT khách → id, hạn bảo hành, trạng thái.",
                new() { ["query"] = ("STRING", "Seri / IMEI / SĐT / tên khách") }, ["query"]);
        if (Has("propose_einvoice"))
            Add("find_orders", "Tìm hóa đơn bán theo mã HĐ / tên / SĐT khách, trong 60 ngày.",
                new() { ["query"] = ("STRING", "Mã hóa đơn / khách") }, ["query"]);
        if (Has("propose_supplier_payment"))
            Add("find_suppliers", "Tìm nhà cung cấp theo tên / SĐT (kèm số nợ hiện tại).",
                new() { ["query"] = ("STRING", "Tên / SĐT nhà cung cấp") }, ["query"]);
        if (Has("propose_business_trip", "propose_feedback", "propose_update_employee") && IsManager(c))
            Add("find_employees", "Tìm nhân viên theo tên / mã (không dấu cũng được) → id dùng cho các công cụ đề xuất.",
                new() { ["query"] = ("STRING", "Tên hoặc mã nhân viên") }, ["query"]);
    }

    async Task<object> WorkFindAsync(string tool, Dictionary<string, object?> a, Ctx c, CancellationToken ct)
    {
        if (tool == "find_meal_sessions")
        {
            if (!AllowedDefs(c).Any(d => d.Name == "propose_meal")) return new { error = "Tài khoản không có quyền đăng ký suất ăn." };
            var rows = await db.MealSessions.AsNoTracking()
                .Where(s => s.StoreId == c.StoreId && s.IsActive && s.Deleted == null)
                .OrderBy(s => s.StartTime)
                .Select(s => new { s.Id, s.Name, s.StartTime, s.EndTime, s.PricePerMeal }).ToListAsync(ct);
            if (rows.Count == 0) return new { ket_qua = "Cửa hàng chưa tạo buổi ăn — tạo ở màn Suất ăn." };
            return new
            {
                ket_qua = rows.Select(s => new
                {
                    id = s.Id, ten = s.Name, gio = $"{s.StartTime:hh\\:mm}–{s.EndTime:hh\\:mm}", gia = s.PricePerMeal,
                }),
            };
        }

        if (!AllowedDefs(c).Any(d => d.Name == "propose_warranty_claim")) return new { error = "Tài khoản không có quyền tiếp nhận bảo hành." };
        var raw = (S(a, "query") ?? "").Trim();
        if (raw.Length < 2) return new { error = "Thiếu số seri / IMEI / SĐT khách" };
        var q = VnSearch.FoldText(raw);
        var digits = new string(raw.Where(char.IsDigit).ToArray());
        var regs = await db.PosProductWarrantyRegistrations.AsNoTracking()
            .Where(r => r.StoreId == c.StoreId && r.Deleted == null)
            .Where(r => r.SerialNumber.Contains(raw) || (r.Imei != null && r.Imei.Contains(raw))
                        || (digits.Length >= 6 && r.Customer != null && r.Customer.Phone != null && r.Customer.Phone.Contains(digits))
                        || (r.Customer != null && r.Customer.Name.Contains(raw)))
            .OrderByDescending(r => r.SaleDate).Take(12)
            .Select(r => new
            {
                r.Id, r.SerialNumber, r.Imei, r.WarrantyExpiry, r.Status,
                Product = r.Product != null ? r.Product.Name : null,
                Customer = r.Customer != null ? r.Customer.Name : null,
            }).ToListAsync(ct);
        if (regs.Count == 0)
        {
            // Tên khách gõ không dấu: lọc lại trong máy bán gần đây.
            regs = (await db.PosProductWarrantyRegistrations.AsNoTracking()
                    .Where(r => r.StoreId == c.StoreId && r.Deleted == null && r.Customer != null)
                    .OrderByDescending(r => r.SaleDate).Take(500)
                    .Select(r => new
                    {
                        r.Id, r.SerialNumber, r.Imei, r.WarrantyExpiry, r.Status,
                        Product = r.Product != null ? r.Product.Name : null,
                        Customer = r.Customer != null ? r.Customer.Name : null,
                    }).ToListAsync(ct))
                .Where(r => VnSearch.Has(r.Customer ?? "", q)).Take(12).ToList();
        }
        if (regs.Count == 0) return new { ket_qua = "Không tìm thấy máy — kiểm tra lại seri / IMEI, hoặc máy bán chưa ghi seri." };
        var today = DateTime.UtcNow;
        return new
        {
            ket_qua = regs.Select(r => new
            {
                id = r.Id, may = r.Product, seri = r.SerialNumber, imei = r.Imei, khach = r.Customer,
                han_bao_hanh = r.WarrantyExpiry.AddHours(7).ToString("dd/MM/yyyy"),
                trang_thai = r.Status switch
                {
                    PosWarrantyStatus.Active => r.WarrantyExpiry < today ? "hết hạn (nhận sửa có tính phí)" : "còn bảo hành",
                    PosWarrantyStatus.Returned => "đã trả", PosWarrantyStatus.Replaced => "đã đổi máy", _ => "đã hủy",
                },
            }),
        };
    }

    Task<Pending?> WorkProposalAsync(string tool, Ctx c, Dictionary<string, object?> a, CancellationToken ct) => tool switch
    {
        "propose_business_trip" => Wrap(BusinessTripAsync(c, a, ct)),
        "propose_feedback" => Wrap(FeedbackAsync(c, a, ct)),
        "propose_meal" => Wrap(MealAsync(c, a, ct)),
        "propose_update_employee" => Wrap(UpdateEmployeeAsync(c, a, ct)),
        "propose_supplier_payment" => Wrap(SupplierPaymentAsync(c, a, ct)),
        "propose_einvoice" => Wrap(EInvoiceAsync(c, a, ct)),
        "propose_warranty_claim" => Wrap(WarrantyClaimAsync(c, a, ct)),
        _ => Task.FromResult<Pending?>(null),
    };

    static List<Step>? WorkUndoSteps(Pending p, string? docId)
    {
        if (string.IsNullOrEmpty(docId)) return null;
        Step? s = p.Kind switch
        {
            // Hồ sơ còn nháp / chờ duyệt ứng thì xóa được (API chặn hồ sơ đã chi).
            "business_trip" => new("DELETE", $"/api/BusinessTripCases/{docId}", null),
            "sale_draft" => new("POST", $"/api/pos/sales/{docId}/cancel-draft", null),
            _ => null,
        };
        return s == null ? null : [s];
    }

    // ─── 1. Công tác phí ───────────────────────────────────────────

    async Task<Pending> BusinessTripAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var e = await ResolveEmployeeAsync(c, G(a, "employee_id"), true, ct);
        var self = e.UserId == c.UserId;
        var title = S(a, "title") ?? throw new ActionError("Thiếu nội dung chuyến công tác.");
        var from = D(a, "from") ?? throw new ActionError("Ngày đi không hợp lệ (yyyy-MM-dd).");
        var to = D(a, "to") ?? from;
        if (to < from) throw new ActionError("Ngày về trước ngày đi.");
        decimal? advance = S(a, "advance_amount") is null ? null : Money(a, "advance_amount");
        var days = (to - from).Days + 1;
        var create = new
        {
            employeeUserId = self ? null : e.UserId, employeeId = self ? (Guid?)null : e.Id,
            title, destination = S(a, "destination"),
            tripFromDate = from.ToString("yyyy-MM-dd'T'00:00:00"), tripToDate = to.ToString("yyyy-MM-dd'T'00:00:00"),
            note = S(a, "note"),
        };
        var lines = new List<Line>
        {
            new("Nhân viên", e.Name), new("Nội dung", title),
            new("Nơi đến", S(a, "destination") ?? "—"),
            new("Thời gian", days == 1 ? from.ToString("dd/MM/yyyy") : $"{from:dd/MM/yyyy} → {to:dd/MM/yyyy} ({days} ngày)"),
            new("Tạm ứng", advance is decimal adv ? Vnd(adv) + " (chờ duyệt)" : "Không"),
        };
        var p = New(c, "business_trip", "Hồ sơ công tác", lines, "POST", "/api/BusinessTripCases", create, "BusinessTripExpense");
        if (advance is not decimal amount) return p;
        return p with
        {
            Steps =
            [
                new("POST", "/api/BusinessTripCases", p.Body),
                new("POST", "/api/BusinessTripCases/{id}/advance",
                    System.Text.Json.JsonSerializer.Serialize(new { amount, reason = title, note = S(a, "note") }, Json)),
            ],
        };
    }

    // ─── 2. Kiến nghị ──────────────────────────────────────────────

    async Task<Pending> FeedbackAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var title = S(a, "title") ?? throw new ActionError("Thiếu tiêu đề.");
        var content = S(a, "content") ?? throw new ActionError("Thiếu nội dung.");
        if (title.Length > 300) title = title[..300];
        var category = (S(a, "category") ?? "suggestion").ToLowerInvariant() switch
        {
            "complaint" => "Complaint", "general" => "General", "other" => "Other", _ => "Suggestion",
        };
        var anonymous = Bool(a, "anonymous");
        string? to = null;
        if (G(a, "recipient_id") is Guid rid)
            to = await db.Employees.AsNoTracking().Where(x => x.Id == rid && x.StoreId == c.StoreId && x.Deleted == null)
                     .Select(x => (x.FirstName + " " + x.LastName).Trim()).FirstOrDefaultAsync(ct)
                 ?? throw new ActionError("Người nhận không hợp lệ — dùng find_employees.");
        return New(c, "feedback", "Kiến nghị",
        [
            new("Tiêu đề", title),
            new("Loại", category switch { "Complaint" => "Khiếu nại", "General" => "Chung", "Other" => "Khác", _ => "Góp ý" }),
            new("Nội dung", content.Length > 300 ? content[..300] + "…" : content),
            new("Gửi tới", to ?? "Quản lý"),
            new("Ẩn danh", anonymous ? "Có" : "Không"),
        ], "POST", "/api/Feedback", new
        {
            title, content, category, isAnonymous = anonymous, recipientEmployeeId = G(a, "recipient_id"),
        }, "Feedback");
    }

    // ─── 3. Suất ăn ────────────────────────────────────────────────

    async Task<Pending> MealAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var sid = G(a, "session_id") ?? throw new ActionError("Thiếu buổi ăn — dùng find_meal_sessions.");
        var session = await db.MealSessions.AsNoTracking()
                          .Where(s => s.Id == sid && s.StoreId == c.StoreId && s.IsActive && s.Deleted == null)
                          .Select(s => new { s.Name, s.StartTime }).FirstOrDefaultAsync(ct)
                      ?? throw new ActionError("Buổi ăn không hợp lệ — dùng find_meal_sessions.");
        var now = AiAssistantVnTime.NowVn();
        var dates = (S(a, "dates") ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(x => D(new() { ["d"] = x }, "d") ?? throw new ActionError($"Ngày «{x}» không hợp lệ (yyyy-MM-dd)."))
            .Distinct().OrderBy(x => x).ToList();
        if (dates.Count == 0) dates.Add(now.Date.AddDays(1));
        if (dates.Count > 31) throw new ActionError("Tối đa 31 ngày một lần.");
        var late = dates.Where(d => d < now.Date || (d == now.Date && now.TimeOfDay >= session.StartTime)).ToList();
        if (late.Count == dates.Count) throw new ActionError($"Đã quá hạn đăng ký {session.Name} các ngày này.");
        var warnings = new List<string>();
        if (late.Count > 0)
        {
            warnings.Add("Bỏ ngày đã quá hạn: " + string.Join(", ", late.Select(d => d.ToString("dd/MM"))));
            dates = dates.Except(late).ToList();
        }
        var cancel = Bool(a, "cancel");
        var note = S(a, "note");
        return New(c, "meal", cancel ? "Hủy đăng ký suất ăn" : "Đăng ký suất ăn",
        [
            new("Buổi", session.Name),
            new("Ngày", string.Join(", ", dates.Select(d => d.ToString("dd/MM")))),
            .. note != null ? new[] { new Line("Ghi chú", note) } : [],
        ], "POST", "/api/Meals/register/batch", new
        {
            registrations = dates.Select(d => new
            {
                mealSessionId = sid, date = d.ToString("yyyy-MM-dd'T'00:00:00"), isRegistered = !cancel, note,
            }),
        }, "Meal", warnings);
    }

    // ─── 4. Sửa hồ sơ nhân viên ────────────────────────────────────

    async Task<Pending> UpdateEmployeeAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var e = await ResolveEmployeeAsync(c, G(a, "employee_id"), false, ct);
        var cur = await db.Employees.AsNoTracking().Where(x => x.Id == e.Id)
            .Select(x => new
            {
                x.Department, x.Position, x.Level, x.PhoneNumber, x.DirectManagerEmployeeId,
                x.BankName, x.BankAccountNumber, x.BankAccountName,
            }).FirstAsync(ct);
        var patch = new JsonObject();
        var lines = new List<Line> { new("Nhân viên", $"{e.Name} ({e.Code})") };
        void Set(string arg, string field, string label, string? old)
        {
            if (S(a, arg) is not { } v || v == old) return;
            patch[field] = v;
            lines.Add(new(label, $"{old ?? "—"} → {v}"));
        }
        Set("department", "department", "Phòng ban", cur.Department);
        Set("position", "position", "Chức vụ", cur.Position);
        Set("level", "level", "Cấp bậc", cur.Level);
        Set("phone", "phoneNumber", "SĐT", cur.PhoneNumber);
        Set("bank_name", "bankName", "Ngân hàng", cur.BankName);
        Set("bank_account", "bankAccountNumber", "Số tài khoản", cur.BankAccountNumber);
        Set("bank_account_name", "bankAccountName", "Chủ tài khoản", cur.BankAccountName);
        if (G(a, "manager_id") is Guid mid && mid != cur.DirectManagerEmployeeId)
        {
            if (mid == e.Id) throw new ActionError("Nhân viên không thể tự quản lý chính mình.");
            var mgr = await db.Employees.AsNoTracking().Where(x => x.Id == mid && x.StoreId == c.StoreId && x.Deleted == null)
                          .Select(x => (x.FirstName + " " + x.LastName).Trim()).FirstOrDefaultAsync(ct)
                      ?? throw new ActionError("Người quản lý không hợp lệ — dùng find_employees.");
            patch["directManagerEmployeeId"] = mid.ToString();
            lines.Add(new("Quản lý trực tiếp", mgr));
        }
        var risk = "normal";
        if (D(a, "resign_date") is DateTime rd)
        {
            patch["resignationDate"] = rd.ToString("yyyy-MM-dd'T'00:00:00");
            patch["resignationReason"] = S(a, "resign_reason");
            lines.Add(new("Nghỉ việc từ", rd.ToString("dd/MM/yyyy") + (S(a, "resign_reason") is { } why ? $" — {why}" : "")));
            risk = "high";
        }
        if (patch.Count == 0) throw new ActionError("Không có thông tin nào thay đổi — hỏi người dùng cần sửa gì.");
        var path = $"/api/Employees/{e.Id}";
        return New(c, "update_employee", "Sửa hồ sơ " + e.Name, lines, "PUT", path, patch, "Employee",
                risk == "high" ? ["Cho nghỉ việc: nhân viên không còn trong lịch / bảng lương các kỳ sau ngày nghỉ."] : null)
            with { MergeFrom = path, Risk = risk };
    }

    // ─── 5. Trả nợ nhà cung cấp ────────────────────────────────────

    async Task<Pending> SupplierPaymentAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var sid = G(a, "supplier_id") ?? throw new ActionError("Thiếu nhà cung cấp — dùng find_suppliers.");
        var s = await db.PosSuppliers.AsNoTracking().Where(x => x.Id == sid && x.StoreId == c.StoreId && x.Deleted == null)
                    .Select(x => new { x.Name, x.CurrentDebt }).FirstOrDefaultAsync(ct)
                ?? throw new ActionError("Không tìm thấy nhà cung cấp — dùng find_suppliers.");
        var openDue = await db.PosStockReceipts.AsNoTracking()
            .Where(r => r.StoreId == c.StoreId && r.SupplierId == sid && r.Deleted == null
                        && r.Status == PosPurchaseReceiptStatus.Completed
                        && r.TotalCost + r.TotalVat - r.DiscountAmount > r.PaidAmount)
            .SumAsync(r => r.TotalCost + r.TotalVat - r.DiscountAmount - r.PaidAmount, ct); // GrandTotal không map cột
        var due = Math.Max(openDue, s.CurrentDebt);
        if (due <= 0) throw new ActionError($"{s.Name} hiện không còn nợ.");
        var amount = (S(a, "amount") ?? "").Trim().ToLowerInvariant() is "all" or "hết" or "het" or "tất cả" ? due : Money(a, "amount");
        if (amount > due) throw new ActionError($"Số tiền vượt tổng nợ {Vnd(due)}.");
        var bank = Method(S(a, "method")) == PaymentMethodType.BankTransfer;
        return New(c, "supplier_payment", "Trả nợ nhà cung cấp",
        [
            new("Nhà cung cấp", s.Name), new("Đang nợ", Vnd(due)), new("Trả", Vnd(amount)),
            new("Còn nợ", Vnd(due - amount)), new("Hình thức", bank ? "Chuyển khoản" : "Tiền mặt"),
        ], "POST", $"/api/pos/purchase/suppliers/{sid}/pay", new
        {
            amount, paymentMethod = bank ? "Chuyển khoản" : "Tiền mặt", note = S(a, "note"),
        }, "PosPurchaseReceipts");
    }

    // ─── 6. Hóa đơn điện tử ────────────────────────────────────────

    async Task<Pending> EInvoiceAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var oid = G(a, "order_id") ?? throw new ActionError("Thiếu hóa đơn — dùng find_orders.");
        var o = await db.PosSaleOrders.AsNoTracking().Where(x => x.Id == oid && x.StoreId == c.StoreId && x.Deleted == null)
                    .Select(x => new { x.OrderNo, x.Status, x.Total, x.CustomerName, x.EInvoiceStatus, x.EInvoiceNo })
                    .FirstOrDefaultAsync(ct)
                ?? throw new ActionError("Không tìm thấy hóa đơn — dùng find_orders.");
        if (o.Status != PosSaleOrderStatus.Completed) throw new ActionError("Chỉ xuất hóa đơn điện tử cho đơn đã thanh toán.");
        if (o.EInvoiceStatus is "Issued" or "Pending")
            throw new ActionError($"Hóa đơn {o.OrderNo} đã xuất HĐĐT{(o.EInvoiceNo != null ? " số " + o.EInvoiceNo : "")} — không xuất lại.");
        string? buyer = S(a, "buyer_name"), tax = S(a, "tax_code"), company = S(a, "company_name");
        var warnings = new List<string> { "Hóa đơn điện tử gửi lên hãng ngay khi xác nhận — sai thông tin phải lập hóa đơn thay thế." };
        if (tax != null && company == null) warnings.Add("Có mã số thuế nhưng thiếu tên công ty.");
        return New(c, "einvoice", "Xuất hóa đơn điện tử",
        [
            new("Hóa đơn", $"{o.OrderNo} — {Vnd(o.Total)}"),
            new("Người mua", company ?? buyer ?? o.CustomerName ?? "Khách lẻ"),
            .. tax != null ? new[] { new Line("Mã số thuế", tax) } : [],
            .. S(a, "email") is { } em ? new[] { new Line("Email", em) } : [],
        ], "POST", $"/api/pos/einvoice/issue/{oid}", new
        {
            name = buyer ?? o.CustomerName, taxCode = tax, companyName = company, address = S(a, "address"), email = S(a, "email"),
        }, "PosEInvoice", warnings) with { Risk = "high" };
    }

    // ─── 7. Bảo hành ───────────────────────────────────────────────

    async Task<Pending> WarrantyClaimAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var wid = G(a, "warranty_id") ?? throw new ActionError("Thiếu máy — dùng find_warranty.");
        var r = await db.PosProductWarrantyRegistrations.AsNoTracking()
                    .Where(x => x.Id == wid && x.StoreId == c.StoreId && x.Deleted == null)
                    .Select(x => new
                    {
                        x.SerialNumber, x.Status, x.WarrantyExpiry,
                        Product = x.Product != null ? x.Product.Name : "",
                        Customer = x.Customer != null ? x.Customer.Name : null,
                    }).FirstOrDefaultAsync(ct)
                ?? throw new ActionError("Không tìm thấy máy — dùng find_warranty.");
        var noteOnly = Bool(a, "note_only");
        if (!noteOnly && r.Status != PosWarrantyStatus.Active)
            throw new ActionError("Máy đã trả / đổi / hủy bảo hành — chỉ ghi chú được (note_only).");
        var warnings = new List<string>();
        if (!noteOnly && r.WarrantyExpiry < DateTime.UtcNow) warnings.Add("Máy đã hết hạn bảo hành — phiếu sửa sẽ tính phí.");
        var ret = D(a, "return_date");
        return New(c, "warranty_claim", noteOnly ? "Ghi chú bảo hành" : "Phiếu tiếp nhận bảo hành",
        [
            new("Máy", $"{r.Product} — seri {r.SerialNumber}"),
            new("Khách", r.Customer ?? "—"),
            new("Lỗi / nội dung", S(a, "description")!),
            .. S(a, "condition") is { } cd ? new[] { new Line("Tình trạng", cd) } : [],
            .. S(a, "accessories") is { } ac ? new[] { new Line("Phụ kiện", ac) } : [],
            .. ret is DateTime rd ? new[] { new Line("Hẹn trả", rd.ToString("dd/MM/yyyy")) } : [],
        ], "POST", $"/api/pos/warranty/{wid}/claims", new
        {
            claimType = noteOnly ? "Note" : "Repair", description = S(a, "description"),
            contactName = r.Customer, deviceCondition = S(a, "condition"), accessories = S(a, "accessories"),
            expectedReturnDate = ret?.ToString("yyyy-MM-dd'T'00:00:00"),
        }, "PosWarranty", warnings);
    }
}
