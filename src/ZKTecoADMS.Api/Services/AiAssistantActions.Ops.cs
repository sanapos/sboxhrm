using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.EntityFrameworkCore;
using ZKTecoADMS.Api.Controllers;
using ZKTecoADMS.Api.Controllers.Base;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Entities;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure.Services;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Việc vận hành hằng ngày thay người dùng: xếp ca / đổi ca, chuyển kho giữa chi nhánh, thu nợ khách, gửi thông báo nội bộ,
/// giao việc, chốt ca thu ngân, phạt hàng loạt theo chấm công, gợi ý nhập hàng. Như các thao tác khác: trợ lý chỉ dựng thẻ
/// chờ xác nhận, bấm «Xác nhận» mới gọi API thật của app bằng phiên người dùng. Mỗi công cụ kiểm quyền chức năng + gói dịch vụ
/// và phạm vi nhân sự (chỉ nhân viên trong phạm vi quản lý).
/// </summary>
public sealed partial class AiAssistantActions
{
    const string ShiftSwapModule = "@shift_swap";

    /// <summary>Đổi ca: gửi yêu cầu (người hỏi là một bên) hoặc quản lý sửa thẳng lịch hai người cùng ngày.</summary>
    static readonly Dictionary<string, KindRule> ShiftSwapKinds = new()
    {
        ["request"] = new("Yêu cầu đổi ca với đồng nghiệp", "ShiftSwap", 'C'),
        ["direct"] = new("Đổi ca trực tiếp trên lịch làm việc", "WorkSchedule", 'E'),
    };

    /// <summary>Loại của các công cụ nhiều loại khai báo ở tệp này (móc từ <c>KindsOf</c>).</summary>
    static Dictionary<string, KindRule> OpsKindsOf(string module) => module == ShiftSwapModule ? ShiftSwapKinds : [];

    static readonly Def[] OpsDefs =
    [
        new("propose_assign_shift", "WorkSchedule", 'C', true,
            "XẾP CA (lịch làm việc) cho một hay nhiều nhân viên vào một hay nhiều ngày. Lấy shift_id bằng find_shift_templates.",
            new()
            {
                ["employee_ids"] = ("STRING", "Id nhân viên (find_employees), cách nhau dấu phẩy"),
                ["shift_id"] = ("STRING", "Id ca (find_shift_templates) — bỏ trống khi day_off"),
                ["dates"] = ("STRING", "Các ngày yyyy-MM-dd, cách nhau dấu phẩy"),
                ["from"] = ("STRING", "Hoặc từ ngày yyyy-MM-dd"),
                ["to"] = ("STRING", "Đến ngày yyyy-MM-dd"),
                ["weekdays"] = ("STRING", "Với from/to: chỉ các thứ, VD \"2,3,4,5,6\" (8 = Chủ nhật)"),
                ["day_off"] = ("BOOLEAN", "true = xếp NGÀY NGHỈ thay vì ca"),
                ["note"] = ("STRING", "Ghi chú"),
            }, ["employee_ids"]),
        new("propose_shift_swap", ShiftSwapModule, 'C', true,
            "ĐỔI CA giữa hai nhân viên đã được xếp ca. Người hỏi là một bên → gửi yêu cầu đổi ca (đồng nghiệp nhận, quản lý duyệt); "
            + "hai người khác cùng ngày → đổi thẳng trên lịch.",
            new()
            {
                ["employee_a"] = ("STRING", "Id nhân viên thứ nhất (bỏ trống = chính người hỏi)"),
                ["date_a"] = ("STRING", "Ngày ca của người thứ nhất yyyy-MM-dd"),
                ["employee_b"] = ("STRING", "Id nhân viên thứ hai"),
                ["date_b"] = ("STRING", "Ngày ca của người thứ hai (bỏ trống = cùng ngày)"),
                ["reason"] = ("STRING", "Lý do"),
            }, ["employee_b", "date_a"]),
        new("propose_stock_transfer", "PosProducts", 'C', false,
            "CHUYỂN KHO giữa hai chi nhánh: tạo phiếu và gửi hàng đi (trừ kho đi). receive=true: xác nhận nhận luôn ở kho đến.",
            new()
            {
                ["from_branch"] = ("STRING", "Tên chi nhánh đi (bỏ trống = chi nhánh đang chọn)"),
                ["to_branch"] = ("STRING", "Tên chi nhánh đến"),
                ["items"] = ("ARRAY", "Hàng chuyển {product_id, qty}"),
                ["receive"] = ("BOOLEAN", "true = nhận luôn ở kho đến"),
                ["note"] = ("STRING", "Ghi chú"),
            }, ["to_branch", "items"]),
        new("propose_collect_debt", "PosCustomers", 'E', false,
            "THU NỢ KHÁCH HÀNG: ghi phiếu thu nợ, giảm công nợ, vào sổ quỹ. Tìm khách bằng find_customers.",
            new()
            {
                ["customer_id"] = ("STRING", "Id khách (find_customers)"),
                ["amount"] = ("STRING", "Số tiền thu, hoặc \"all\" = thu hết nợ"),
                ["method"] = ("STRING", "cash | bank"),
                ["note"] = ("STRING", "Ghi chú"),
            }, ["customer_id", "amount"]),
        new("propose_announcement", "Notification", 'C', true,
            "GỬI THÔNG BÁO NỘI BỘ tới nhân viên (chọn người, phòng ban, hoặc mọi người trong phạm vi quản lý).",
            new()
            {
                ["title"] = ("STRING", "Tiêu đề (≤ 200 ký tự)"),
                ["body"] = ("STRING", "Nội dung (≤ 2000 ký tự)"),
                ["employee_ids"] = ("STRING", "Id nhân viên nhận, cách nhau dấu phẩy"),
                ["departments"] = ("STRING", "Tên phòng ban nhận, cách nhau dấu phẩy"),
                ["everyone"] = ("BOOLEAN", "true = mọi nhân viên trong phạm vi"),
            }, ["title", "body"]),
        new("propose_task", "Task", 'C', true,
            "GIAO VIỆC: tạo công việc giao cho một hay nhiều nhân viên, có hạn hoàn thành.",
            new()
            {
                ["title"] = ("STRING", "Tên công việc"),
                ["description"] = ("STRING", "Mô tả"),
                ["employee_ids"] = ("STRING", "Id người nhận việc, cách nhau dấu phẩy"),
                ["due_date"] = ("STRING", "Hạn yyyy-MM-dd"),
                ["due_time"] = ("STRING", "Giờ hạn HH:mm (mặc định 17:00)"),
                ["priority"] = ("STRING", "low | medium | high | urgent"),
            }, ["title"]),
        new("propose_close_cashier_shift", "PosCashierShift", 'C', false,
            "CHỐT CA THU NGÂN (đóng ca đang mở): so tiền mặt đếm thực tế trong két với số dự kiến.",
            new()
            {
                ["counted_cash"] = ("NUMBER", "Tiền mặt ĐẾM THỰC TẾ trong két"),
                ["note"] = ("STRING", "Ghi chú (lý do chênh lệch)"),
                ["employee_id"] = ("STRING", "Chốt ca của thu ngân khác (quản lý) — bỏ trống = ca của mình"),
            }, ["counted_cash"]),
        new("propose_penalties_for_late", "PenaltyTickets", 'C', true,
            "PHẠT HÀNG LOẠT theo chấm công một ngày (đi trễ / về sớm / vắng không phép): một phiếu mỗi người, "
            + "tự bỏ qua người đã có phiếu cùng loại ngày đó.",
            new()
            {
                ["date"] = ("STRING", "Ngày yyyy-MM-dd (mặc định hôm nay)"),
                ["type"] = ("STRING", "Late (đi trễ) | EarlyLeave (về sớm) | UnauthorizedLeave (vắng không phép)"),
                ["amount"] = ("NUMBER", "Tiền phạt mỗi người. Bỏ trống = theo Thiết lập phạt; mức ghi trong nội quy → PHẢI truyền"),
                ["employee_ids"] = ("STRING", "Chỉ xét các nhân viên này (bỏ trống = mọi người trong phạm vi)"),
                ["description"] = ("STRING", "Nội dung / căn cứ nội quy"),
            }, []),
    ];

    // ─── Khai báo + xử lý công cụ tra cứu ──────────────────────────

    static readonly string[] OpsFinders = ["find_shift_templates", "find_branches", "find_reorder_suggestions"];

    /// <summary>Quyền Xem một chức năng (kèm gói dịch vụ) — cho công cụ chỉ đọc.</summary>
    static bool CanView(Ctx c, string module) =>
        (c.Package is not { Count: > 0 } pkg || pkg.Contains(module, StringComparer.OrdinalIgnoreCase))
        && (c.IsSuper || (c.Perms.TryGetValue(module, out var p) && p.CanView));

    static bool Declared(List<object> decls, string name) =>
        decls.Any(d => d.GetType().GetProperty("name")?.GetValue(d) as string == name);

    void AddOpsFinders(Ctx c, List<Def> allowed, List<object> decls)
    {
        bool Has(params string[] names) => allowed.Any(d => names.Contains(d.Name));
        void Add(string name, string desc, Dictionary<string, (string Type, string Desc)> ps, string[] req)
        {
            if (!Declared(decls, name)) decls.Add(Fn(name, desc, ps, req));
        }
        if (IsManager(c) && Has("propose_assign_shift", "propose_shift_swap", "propose_announcement", "propose_task",
                "propose_penalties_for_late", "propose_close_cashier_shift"))
            Add("find_employees", "Tìm nhân viên theo tên / mã (không dấu cũng được) → id dùng cho các công cụ đề xuất.",
                new() { ["query"] = ("STRING", "Tên hoặc mã nhân viên") }, ["query"]);
        if (Has("propose_assign_shift", "propose_shift_swap"))
            Add("find_shift_templates", "Danh sách ca làm việc của cửa hàng → shift_id, giờ vào–ra.", new(), []);
        if (Has("propose_stock_transfer"))
        {
            Add("find_products", "Tìm hàng hóa / dịch vụ theo tên / mã / mã vạch → id, giá bán, giá vốn, đơn vị, tồn.",
                new() { ["query"] = ("STRING", "Tên / mã hàng") }, ["query"]);
            Add("find_branches", "Chi nhánh của cửa hàng bạn được thao tác (tên dùng cho chuyển kho).", new(), []);
        }
        if (Has("propose_collect_debt"))
            Add("find_customers", "Tìm khách hàng theo tên / SĐT.", new() { ["query"] = ("STRING", "Tên / SĐT") }, ["query"]);
        if (Has("propose_purchase_receipt") && CanView(c, "PosReportStock"))
            Add("find_reorder_suggestions",
                "Hàng sắp hết cần nhập (tồn ≤ tối thiểu): tồn, bán TB/ngày, SL gợi ý, NCC + giá nhập lần cuối — gom theo NCC để lập propose_purchase_receipt.",
                new() { ["supplier"] = ("STRING", "Lọc theo tên NCC") }, []);
    }

    async Task<object> OpsFindAsync(string tool, Dictionary<string, object?> a, Ctx c, CancellationToken ct)
    {
        switch (tool)
        {
            case "find_shift_templates":
            {
                if (!AllowedDefs(c).Any(d => d.Name is "propose_assign_shift" or "propose_shift_swap"))
                    return new { error = "Tài khoản không có quyền xếp ca." };
                var rows = await db.ShiftTemplates.AsNoTracking().Where(s => s.StoreId == c.StoreId && s.IsActive)
                    .OrderBy(s => s.StartTime).Select(s => new { s.Id, s.Name, s.Code, s.StartTime, s.EndTime }).Take(60).ToListAsync(ct);
                if (rows.Count == 0) return new { ket_qua = "Cửa hàng chưa tạo ca làm việc — tạo ở Thiết lập SBOX › Ca làm việc." };
                return new { ket_qua = rows.Select(s => new { id = s.Id, ten = s.Name, ma = s.Code, gio = $"{s.StartTime:hh\\:mm}–{s.EndTime:hh\\:mm}" }) };
            }
            case "find_branches":
            {
                if (!Can(c, "PosProducts", 'C')) return new { error = "Tài khoản không có quyền chuyển kho." };
                var (all, hq, allowed, current) = await BranchCtxAsync(c, ct);
                if (all.Count < 2) return new { ket_qua = "Cửa hàng chưa có từ 2 chi nhánh — không có chuyển kho." };
                return new
                {
                    ket_qua = all.Select(b => new
                    {
                        ten = b.Name, ma = b.Code, tru_so = b.IsHeadquarter ? true : (bool?)null,
                        dang_chon = b.Id == current ? true : (bool?)null,
                        duoc_chuyen_di = allowed == null || allowed.Contains(b.Id),
                    }),
                };
            }
            default:
                return await ReorderSuggestionsAsync(c, S(a, "supplier"), ct);
        }
    }

    // ─── Gợi ý nhập hàng ───────────────────────────────────────────

    async Task<object> ReorderSuggestionsAsync(Ctx c, string? supplier, CancellationToken ct)
    {
        if (!CanView(c, "PosReportStock")) return new { error = "Tài khoản không có quyền xem báo cáo kho." };
        // Cùng truy vấn với báo cáo «Gợi ý nhập hàng» (pos/reports/stock/reorder-suggestions).
        var rows = await PosReorderSuggestionHelper.LoadAsync(db, c.StoreId, ct);
        var q = VnSearch.FoldText(supplier);
        if (q.Length > 0) rows = rows.Where(r => VnSearch.Has(r.SupplierName ?? "", q)).ToList();
        if (rows.Count == 0) return new { ket_qua = "Không có hàng nào dưới tồn tối thiểu (hoặc hàng chưa đặt tồn tối thiểu)." };
        rows = rows.Take(80).ToList();
        var ids = rows.Select(r => r.ProductId).ToList();

        // Bán trung bình / ngày trong 30 ngày.
        const int days = 30;
        var since = DateTime.UtcNow.AddDays(-days);
        var sold = await db.PosSaleOrderLines.AsNoTracking()
            .Where(l => l.StoreId == c.StoreId && ids.Contains(l.ProductId) && l.SaleOrder != null
                        && l.SaleOrder.Deleted == null && l.SaleOrder.Status == PosSaleOrderStatus.Completed
                        && (l.SaleOrder.SaleDate ?? l.SaleOrder.CreatedAt) >= since)
            .GroupBy(l => l.ProductId)
            .Select(g => new { g.Key, Qty = g.Sum(x => x.Qty) })
            .ToDictionaryAsync(x => x.Key, x => x.Qty, ct);

        // Lần nhập gần nhất: NCC + giá nhập.
        var lastIn = (await db.PosStockReceiptLines.AsNoTracking()
                .Where(l => l.StoreId == c.StoreId && ids.Contains(l.ProductId) && l.Receipt != null
                            && l.Receipt.Deleted == null && l.Receipt.Status == PosPurchaseReceiptStatus.Completed)
                .Select(l => new
                {
                    l.ProductId, l.CostPrice, l.Receipt!.CreatedAt, l.Receipt.SupplierId,
                    Supplier = l.Receipt.Supplier != null ? l.Receipt.Supplier.Name : null,
                })
                .ToListAsync(ct))
            .GroupBy(x => x.ProductId)
            .ToDictionary(g => g.Key, g => g.OrderByDescending(x => x.CreatedAt).First());

        var seeCost = CanSeeCost(c);
        var items = rows.Select(r =>
        {
            var avg = Math.Round(sold.GetValueOrDefault(r.ProductId) / days, 2);
            lastIn.TryGetValue(r.ProductId, out var li);
            var supId = r.SupplierId ?? li?.SupplierId;
            var supName = r.SupplierName ?? li?.Supplier;
            return new
            {
                SupId = supId, SupName = supName,
                Row = new
                {
                    product_id = r.ProductId, ten = r.Name, don_vi = r.UnitName, ton = r.OnHand, ton_toi_thieu = r.MinStock,
                    ban_tb_ngay = avg, het_sau_ngay = avg > 0 ? Math.Round(Math.Max(r.OnHand, 0) / avg, 1) : (decimal?)null,
                    sl_goi_y = r.SuggestQty,
                    gia_nhap = seeCost ? (li?.CostPrice ?? r.CostPrice) : (decimal?)null,
                    nhap_lan_cuoi = li == null ? null : AiAssistantVnTime.ToVn(li.CreatedAt).ToString("dd/MM/yyyy"),
                },
            };
        }).ToList();
        return new
        {
            so_mat_hang = items.Count,
            het_hang = rows.Count(r => r.OutOfStock),
            theo_ncc = items.GroupBy(x => (x.SupId, x.SupName)).Select(g => new
            {
                supplier_id = g.Key.SupId, ncc = g.Key.SupName ?? "(chưa rõ NCC)", hang = g.Select(x => x.Row),
            }),
            luu_y = "Đưa danh sách cho người dùng chốt số lượng; mỗi NCC một propose_purchase_receipt (price = gia_nhap).",
        };
    }

    // ─── Định tuyến đề xuất ────────────────────────────────────────

    Task<Pending?> OpsProposalAsync(string tool, Ctx c, Dictionary<string, object?> a, CancellationToken ct) => tool switch
    {
        "propose_assign_shift" => Wrap(AssignShiftAsync(c, a, ct)),
        "propose_shift_swap" => Wrap(ShiftSwapAsync(c, a, ct)),
        "propose_stock_transfer" => Wrap(StockTransferAsync(c, a, ct)),
        "propose_collect_debt" => Wrap(CollectDebtAsync(c, a, ct)),
        "propose_announcement" => Wrap(AnnouncementAsync(c, a, ct)),
        "propose_task" => Wrap(TaskAsync(c, a, ct)),
        "propose_close_cashier_shift" => Wrap(CloseCashierShiftAsync(c, a, ct)),
        "propose_penalties_for_late" => Wrap(PenaltiesForLateAsync(c, a, ct)),
        _ => Task.FromResult<Pending?>(null),
    };

    /// <summary>Hoàn tác các thẻ vận hành (null = không có / để phần chung xử lý).</summary>
    static List<Step>? OpsUndoSteps(Pending p, string? docId, System.Text.Json.Nodes.JsonNode? data)
    {
        if (p.Batch) return null;
        if (p.Kind == "announcement")
            return data?["batchId"]?.ToString() is { Length: > 0 } batch
                ? [new("POST", $"/api/notification-center/sent/{batch}/recall", null)]
                : null;
        if (string.IsNullOrEmpty(docId)) return null;
        Step? s = p.Kind switch
        {
            "assign_shift" => new("DELETE", $"/api/WorkSchedules/{docId}", null),
            "shift_swap_request" => new("DELETE", $"/api/ShiftSwaps/{docId}", null),
            // Đã nhận ở kho đến thì API không cho hủy.
            "stock_transfer" when p.Steps is not { Count: > 1 } => new("POST", $"/api/branch-ops/transfers/{docId}/cancel", null),
            "task" => new("DELETE", $"/api/Tasks/{docId}", null),
            _ => null,
        };
        return s == null ? null : [s];
    }

    // ─── Tiện ích ──────────────────────────────────────────────────

    static string J(object o) => JsonSerializer.Serialize(o, Json);

    static bool Bool(Dictionary<string, object?> a, string k) => S(a, k)?.ToLowerInvariant() is "true" or "1" or "yes" or "có";

    static List<Guid> IdList(Dictionary<string, object?> a, string k) =>
        (S(a, k) ?? "").Split([',', ';', ' '], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(x => Guid.TryParse(x, out var g) ? g : Guid.Empty).Where(g => g != Guid.Empty).Distinct().ToList();

    /// <summary>Nhân viên theo id — tất cả phải trong phạm vi quản lý của người hỏi.</summary>
    async Task<List<Emp>> ScopedEmployeesAsync(Ctx c, List<Guid> ids, CancellationToken ct)
    {
        if (ids.Count == 0) throw new ActionError("Thiếu nhân viên — dùng find_employees lấy id.");
        var all = (await EmployeesAsync(c, ct)).ToDictionary(e => e.Id);
        var miss = ids.Count(id => !all.ContainsKey(id));
        if (miss > 0)
            throw new ActionError($"{miss} nhân viên không thuộc phạm vi bạn quản lý (hoặc đã nghỉ việc) — dùng find_employees lấy đúng id.");
        return ids.Select(id => all[id]).ToList();
    }

    static string Names(IEnumerable<string> names, int max = 6)
    {
        var l = names.ToList();
        return l.Count <= max ? string.Join(", ", l) : string.Join(", ", l.Take(max)) + $" và {l.Count - max} người khác";
    }

    static string DateSummary(List<DateTime> dates) => dates.Count <= 7
        ? string.Join(", ", dates.Select(d => d.ToString("dd/MM")))
        : $"{dates[0]:dd/MM/yyyy} → {dates[^1]:dd/MM/yyyy} ({dates.Count} ngày)";

    /// <summary>Danh sách ngày (dates) hoặc khoảng from–to lọc theo thứ trong tuần (2 = Thứ Hai … 8 = Chủ nhật).</summary>
    static List<DateTime> DateList(Dictionary<string, object?> a)
    {
        var list = new List<DateTime>();
        foreach (var s in (S(a, "dates") ?? "").Split([',', ';'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            if (!DateTime.TryParseExact(s, ["yyyy-MM-dd", "dd/MM/yyyy", "d/M/yyyy"], CultureInfo.InvariantCulture, DateTimeStyles.None, out var d))
                throw new ActionError($"Ngày «{s}» không hợp lệ (yyyy-MM-dd).");
            list.Add(d.Date);
        }
        if (D(a, "from") is DateTime from)
        {
            var to = D(a, "to") ?? from;
            if (to < from) throw new ActionError("Đến ngày phải sau từ ngày.");
            if ((to - from).TotalDays > 62) throw new ActionError("Xếp tối đa 62 ngày một lần.");
            var days = new HashSet<DayOfWeek>();
            foreach (var w in (S(a, "weekdays") ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                if (w.Equals("cn", StringComparison.OrdinalIgnoreCase)) days.Add(DayOfWeek.Sunday);
                else if (int.TryParse(w, out var n) && n is >= 2 and <= 8) days.Add((DayOfWeek)((n - 1) % 7));
            }
            for (var d = from; d <= to; d = d.AddDays(1))
                if (days.Count == 0 || days.Contains(d.DayOfWeek)) list.Add(d);
        }
        return list.Distinct().OrderBy(x => x).ToList();
    }

    // ─── 1. Xếp ca / đổi ca ────────────────────────────────────────

    async Task<Pending> AssignShiftAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var emps = await ScopedEmployeesAsync(c, IdList(a, "employee_ids").Concat(IdList(a, "employee_id")).Distinct().ToList(), ct);
        var dates = DateList(a);
        if (dates.Count == 0) throw new ActionError("Thiếu ngày xếp ca — hỏi người dùng ngày nào.");
        var dayOff = Bool(a, "day_off");
        Guid? shiftId = null;
        var shiftLabel = "Ngày nghỉ";
        if (!dayOff)
        {
            var sid = G(a, "shift_id") ?? throw new ActionError("Thiếu ca — gọi find_shift_templates rồi truyền shift_id.");
            var st = await db.ShiftTemplates.AsNoTracking().Where(s => s.Id == sid && s.StoreId == c.StoreId)
                         .Select(s => new { s.Name, s.StartTime, s.EndTime, s.IsActive }).FirstOrDefaultAsync(ct)
                     ?? throw new ActionError("Không tìm thấy ca — dùng find_shift_templates lấy đúng id.");
            if (!st.IsActive) throw new ActionError($"Ca «{st.Name}» đang tắt — bật lại ở Thiết lập ca làm việc.");
            shiftId = sid;
            shiftLabel = $"{st.Name} ({st.StartTime:hh\\:mm}–{st.EndTime:hh\\:mm})";
        }

        // Bỏ trước các lượt API sẽ từ chối (trùng ca / đang nghỉ) — cùng quy tắc WorkScheduleDuplicateHelper.
        var keys = emps.Select(e => e.Id).Concat(emps.Where(e => e.UserId != null).Select(e => e.UserId!.Value)).Distinct().ToList();
        var from = dates[0];
        var to = dates[^1].AddDays(1);
        var existing = await db.WorkSchedules.AsNoTracking()
            .Where(w => w.StoreId == c.StoreId && keys.Contains(w.EmployeeUserId) && w.Date >= from && w.Date < to)
            .Select(w => new { w.EmployeeUserId, w.Date, w.ShiftId, w.IsDayOff })
            .ToListAsync(ct);
        var note = S(a, "note");
        var steps = new List<Step>();
        var skipped = new List<string>();
        foreach (var e in emps)
        foreach (var d in dates)
        {
            var same = existing.Where(w => (w.EmployeeUserId == e.Id || w.EmployeeUserId == e.UserId) && w.Date.Date == d).ToList();
            var conflict = dayOff
                ? same.Any(o => o.IsDayOff) ? "đã là ngày nghỉ" : same.Any(o => o.ShiftId != null) ? "đang có ca" : null
                : same.Any(o => o.IsDayOff) ? "đang nghỉ" : same.Any(o => o.ShiftId == shiftId) ? "đã có ca này" : null;
            if (conflict != null)
            {
                skipped.Add($"{e.Name} {d:dd/MM}: {conflict}");
                continue;
            }
            steps.Add(new("POST", "/api/WorkSchedules",
                J(new { employeeUserId = e.Id, shiftId, date = d.ToString("yyyy-MM-dd"), isDayOff = dayOff, note }),
                Label: $"{e.Name} {d:dd/MM}"));
        }
        if (steps.Count == 0) throw new ActionError("Không có lượt nào cần xếp: " + string.Join("; ", skipped.Take(5)));
        if (steps.Count > 300) throw new ActionError($"{steps.Count} lượt xếp — tối đa 300 một lần, chia nhỏ khoảng ngày.");

        var warnings = new List<string>();
        if (skipped.Count > 0) warnings.Add($"Bỏ qua {skipped.Count} lượt: " + string.Join("; ", skipped.Take(4)) + (skipped.Count > 4 ? "…" : ""));
        if (dates[0] < AiAssistantVnTime.NowVn().Date) warnings.Add("Có ngày đã qua.");
        List<Line> lines =
        [
            new(dayOff ? "Loại" : "Ca", shiftLabel), new("Nhân viên", Names(emps.Select(e => e.Name))),
            new("Ngày", DateSummary(dates)), new("Số lượt", $"{steps.Count}"),
            .. note != null ? new[] { new Line("Ghi chú", note) } : [],
        ];
        if (steps.Count == 1)
            return New(c, "assign_shift", dayOff ? "Ngày nghỉ trên lịch" : "Lịch làm việc", lines, "POST", "/api/WorkSchedules", null,
                "WorkSchedule", warnings) with { Body = steps[0].Body };
        return New(c, "assign_shift", dayOff ? "Xếp ngày nghỉ" : "Xếp ca", lines, "POST", steps[0].Path, null, "WorkSchedule", warnings)
            with
            {
                Steps = steps, Batch = true, BatchUndo = steps.Select(_ => (Step?)null).ToList(),
                Risk = steps.Count > 20 ? "high" : "normal",
            };
    }

    sealed record Sched(Guid Id, Guid ShiftId, string ShiftName, TimeSpan? Start, TimeSpan? End, string? Note);

    /// <summary>Ca đã xếp (không phải ngày nghỉ) của nhân viên trong ngày.</summary>
    async Task<Sched?> ScheduleOnAsync(Ctx c, Emp e, DateTime date, CancellationToken ct)
    {
        var next = date.AddDays(1);
        var row = await db.WorkSchedules.AsNoTracking()
            .Where(w => w.StoreId == c.StoreId && (w.EmployeeUserId == e.Id || (e.UserId != null && w.EmployeeUserId == e.UserId))
                        && w.Date >= date && w.Date < next && !w.IsDayOff && w.ShiftId != null)
            .Select(w => new { w.Id, w.ShiftId, w.StartTime, w.EndTime, w.Note })
            .FirstOrDefaultAsync(ct);
        if (row == null) return null;
        var st = await db.ShiftTemplates.AsNoTracking().Where(s => s.Id == row.ShiftId)
            .Select(s => new { s.Name, s.StartTime, s.EndTime }).FirstOrDefaultAsync(ct);
        var label = st == null ? "ca" : $"{st.Name} ({st.StartTime:hh\\:mm}–{st.EndTime:hh\\:mm})";
        return new Sched(row.Id, row.ShiftId!.Value, label, row.StartTime, row.EndTime, row.Note);
    }

    async Task<Pending> ShiftSwapAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        const string outOfScope = "Không tìm thấy nhân viên trong phạm vi bạn quản lý — dùng find_employees để lấy đúng id.";
        var all = await EmployeesAsync(c, ct);
        var ea = G(a, "employee_a") is Guid ga
            ? all.FirstOrDefault(x => x.Id == ga) ?? throw new ActionError(outOfScope)
            : all.FirstOrDefault(x => x.UserId == c.UserId) ?? throw new ActionError("Tài khoản chưa gắn hồ sơ nhân viên — truyền employee_a.");
        var eb = (G(a, "employee_b") is Guid gb ? all.FirstOrDefault(x => x.Id == gb) : null) ?? throw new ActionError(outOfScope);
        if (ea.Id == eb.Id) throw new ActionError("Hai người đổi ca phải khác nhau.");
        var dateA = D(a, "date_a") ?? throw new ActionError("Thiếu ngày ca.");
        var dateB = D(a, "date_b") ?? dateA;
        if (dateA < AiAssistantVnTime.NowVn().Date || dateB < AiAssistantVnTime.NowVn().Date)
            throw new ActionError("Không đổi ca của ngày đã qua.");
        var sa = await ScheduleOnAsync(c, ea, dateA, ct) ?? throw new ActionError($"{ea.Name} chưa được xếp ca ngày {dateA:dd/MM}.");
        var sb = await ScheduleOnAsync(c, eb, dateB, ct) ?? throw new ActionError($"{eb.Name} chưa được xếp ca ngày {dateB:dd/MM}.");
        if (sa.ShiftId == sb.ShiftId && dateA == dateB) throw new ActionError("Hai người đang cùng ca — không cần đổi.");
        var reason = S(a, "reason");
        var kinds = AllowedKinds(c, ShiftSwapModule);

        // Người hỏi là một bên → yêu cầu đổi ca theo đúng quy trình app (đồng nghiệp nhận → quản lý duyệt).
        var self = ea.UserId == c.UserId ? ea : eb.UserId == c.UserId ? eb : null;
        if (self != null && kinds.Contains("request"))
        {
            var other = self == ea ? eb : ea;
            var (mine, theirs, myDate, theirDate) = self == ea ? (sa, sb, dateA, dateB) : (sb, sa, dateB, dateA);
            if (other.UserId == null) throw new ActionError($"{other.Name} chưa có tài khoản đăng nhập — không gửi được yêu cầu đổi ca.");
            return New(c, "shift_swap_request", "Yêu cầu đổi ca",
            [
                new("Ca của bạn", $"{mine.ShiftName} · {myDate:dd/MM/yyyy}"),
                new("Đổi với", $"{other.Name}: {theirs.ShiftName} · {theirDate:dd/MM/yyyy}"),
                new("Lý do", reason ?? "—"),
            ], "POST", "/api/ShiftSwaps", new
            {
                targetUserId = other.UserId, requesterDate = myDate.ToString("yyyy-MM-dd"), requesterShiftId = mine.ShiftId,
                targetDate = theirDate.ToString("yyyy-MM-dd"), targetShiftId = theirs.ShiftId, reason,
            }, "ShiftSwap", ["Đồng nghiệp xác nhận rồi quản lý duyệt thì lịch mới đổi."]);
        }

        if (!kinds.Contains("direct") || !IsManager(c))
            throw new ActionError("Tài khoản không có quyền sửa lịch làm việc của người khác.");
        if (dateA != dateB)
            throw new ActionError("Đổi thẳng trên lịch chỉ áp dụng cho hai ca cùng ngày — khác ngày thì sửa ở màn Lịch làm việc.");
        Step Put(Sched target, Sched from) => new("PUT", $"/api/WorkSchedules/{target.Id}",
            J(new { shiftId = from.ShiftId, startTime = from.Start, endTime = from.End, isDayOff = false, note = target.Note }));
        var steps = new List<Step> { Put(sa, sb) with { Label = ea.Name }, Put(sb, sa) with { Label = eb.Name } };
        var undo = new List<Step?> { Put(sa, sa), Put(sb, sb) };
        return New(c, "shift_swap", "Đổi ca",
            [
                new("Ngày", dateA.ToString("dd/MM/yyyy")),
                new(ea.Name, $"{sa.ShiftName} → {sb.ShiftName}"),
                new(eb.Name, $"{sb.ShiftName} → {sa.ShiftName}"),
                .. reason != null ? new[] { new Line("Lý do", reason) } : [],
            ], "PUT", steps[0].Path, null, "WorkSchedule")
            with { Steps = steps, Batch = true, BatchUndo = undo };
    }

    // ─── 2. Chuyển kho giữa chi nhánh ──────────────────────────────

    async Task<(List<BranchStockService.BranchInfo> All, Guid? Hq, IReadOnlyCollection<Guid>? Allowed, Guid? Current)> BranchCtxAsync(
        Ctx c, CancellationToken ct)
    {
        var all = await BranchStockService.GetStoreBranchesAsync(db, c.StoreId, ct);
        var bctx = http?.HttpContext.BranchContext();
        var hq = bctx?.HeadquarterBranchId ?? BranchStockService.ResolveHeadquarter(all);
        return (all.Where(b => b.IsActive).ToList(), hq, bctx?.AllowedBranchIds, bctx?.CurrentBranchId);
    }

    static BranchStockService.BranchInfo PickBranch(List<BranchStockService.BranchInfo> all, string name, string role)
    {
        var q = VnSearch.FoldText(name);
        var hits = all.Select(b => (b, s: Math.Max(Score(VnSearch.Fold(b.Name), q), VnSearch.Fold(b.Code) == q ? 100 : 0)))
            .Where(x => x.s > 0).OrderByDescending(x => x.s).ToList();
        if (hits.Count == 0)
            throw new ActionError($"Không có chi nhánh {role} «{name}». Các chi nhánh: {string.Join(", ", all.Select(b => b.Name))}.");
        if (hits.Count > 1 && hits[1].s == hits[0].s)
            throw new ActionError($"«{name}» khớp nhiều chi nhánh ({string.Join(", ", hits.Where(h => h.s == hits[0].s).Select(h => h.b.Name))}) — hỏi lại người dùng.");
        return hits[0].b;
    }

    async Task<Pending> StockTransferAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var (all, hq, allowed, current) = await BranchCtxAsync(c, ct);
        if (all.Count < 2) throw new ActionError("Cửa hàng chưa có từ 2 chi nhánh — không chuyển kho được.");
        var to = PickBranch(all, S(a, "to_branch") ?? "", "đến");
        var from = S(a, "from_branch") is { } fn
            ? PickBranch(all, fn, "đi")
            : all.FirstOrDefault(b => b.Id == (current ?? hq)) ?? throw new ActionError("Thiếu chi nhánh đi — hỏi người dùng.");
        if (from.Id == to.Id) throw new ActionError("Kho đi và kho đến phải khác nhau.");
        if (allowed != null && !allowed.Contains(from.Id))
            throw new ActionError($"Bạn chỉ được chuyển hàng từ chi nhánh mình quản lý (không có quyền ở «{from.Name}»).");
        if (!await BranchStockService.CanActOnBranchAsync(db, c.UserId, c.StoreId, from.Id,
                ZKTecoADMS.Application.Interfaces.BranchAction.Create, ct))
            throw new ActionError($"Tài khoản không có quyền tạo phiếu ở chi nhánh «{from.Name}».");

        var items = Items(a);
        var prods = await ProductsAsync(c, items.Select(i => i.Id), ct);
        var qty = new Dictionary<Guid, decimal>();
        foreach (var i in items)
        {
            var pr = prods[i.Id];
            if (!pr.Goods) throw new ActionError($"«{pr.Name}» không phải hàng hóa có tồn kho.");
            if (i.Qty <= 0) throw new ActionError($"Số lượng {pr.Name} không hợp lệ.");
            qty[pr.Id] = qty.GetValueOrDefault(pr.Id) + i.Qty;
        }
        var have = await BranchStockService.GetBranchQtyAsync(db, c.StoreId, from.Id, hq, qty.Keys.ToList(), ct);
        var lines = new List<Line> { new("Từ", from.Name), new("Đến", to.Name) };
        foreach (var (id, q) in qty)
        {
            var pr = prods[id];
            var h = have.GetValueOrDefault((id, (Guid?)null));
            if (q > h) throw new ActionError($"«{pr.Name}» chỉ còn {h:0.##} {pr.Unit} ở {from.Name} (cần {q:0.##}).");
            lines.Add(new($"{q:0.##} {pr.Unit} {pr.Name}", $"tồn {from.Name}: {h:0.##}"));
        }
        var note = S(a, "note") ?? "Chuyển kho bằng Trợ lý ảo";
        var warnings = new List<string>();
        var receive = Bool(a, "receive");
        if (receive && (!Can(c, "PosProducts", 'E') || (allowed != null && !allowed.Contains(to.Id))))
        {
            receive = false;
            warnings.Add($"Bạn không có quyền nhận hàng ở «{to.Name}» — phiếu ở trạng thái Đang chuyển, kho đến bấm «Nhận».");
        }
        lines.Add(new("Trạng thái sau khi xác nhận", receive ? "Đã nhận ở kho đến" : "Đang chuyển (kho đến bấm «Nhận»)"));
        var body = new
        {
            fromBranchId = from.Id, toBranchId = to.Id, note,
            lines = qty.Select(kv => new { productId = kv.Key, qty = kv.Value }), sendNow = true,
        };
        var p = New(c, "stock_transfer", "Phiếu chuyển kho", lines, "POST", "/api/branch-ops/transfers", body, "PosStockTransfer", warnings);
        return !receive ? p : p with
        {
            Steps =
            [
                new("POST", "/api/branch-ops/transfers", p.Body),
                new("POST", "/api/branch-ops/transfers/{id}/receive", null),
            ],
        };
    }

    // ─── 3. Thu nợ khách ───────────────────────────────────────────

    async Task<Pending> CollectDebtAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var id = G(a, "customer_id") ?? throw new ActionError("Thiếu khách — dùng find_customers.");
        var k = await db.PosCustomers.AsNoTracking().Where(x => x.Id == id && x.StoreId == c.StoreId && x.Deleted == null)
                    .Select(x => new { x.Name, x.Phone, x.CurrentDebt }).FirstOrDefaultAsync(ct)
                ?? throw new ActionError("Không tìm thấy khách — dùng find_customers.");
        if (k.CurrentDebt <= 0) throw new ActionError($"{k.Name} hiện không còn nợ.");
        var raw = (S(a, "amount") ?? "").Trim().ToLowerInvariant();
        var amount = raw is "all" or "hết" or "het" or "full" or "toàn bộ" ? k.CurrentDebt : Money(a, "amount");
        if (amount > k.CurrentDebt)
            throw new ActionError($"Số thu {Vnd(amount)} vượt công nợ hiện tại {Vnd(k.CurrentDebt)} — hỏi lại người dùng.");
        var method = Method(S(a, "method")) == PaymentMethodType.BankTransfer ? "Chuyển khoản" : "Tiền mặt";
        var note = S(a, "note") ?? "Thu nợ (Trợ lý ảo)";
        return New(c, "collect_debt", "Phiếu thu nợ khách",
        [
            new("Khách", k.Name + (string.IsNullOrWhiteSpace(k.Phone) ? "" : $" · {k.Phone}")),
            new("Nợ hiện tại", Vnd(k.CurrentDebt)), new("Thu", $"{Vnd(amount)} — {method}"),
            new("Còn nợ sau thu", Vnd(k.CurrentDebt - amount)), new("Ghi chú", note),
        ], "POST", $"/api/pos/customers/{id}/payments", new { amount, paymentMethod = method, note }, "PosCustomers");
    }

    // ─── 4. Thông báo nội bộ ───────────────────────────────────────

    async Task<Pending> AnnouncementAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var title = S(a, "title") ?? throw new ActionError("Thiếu tiêu đề.");
        var body = S(a, "body") ?? throw new ActionError("Thiếu nội dung.");
        if (title.Length > 200 || body.Length > 2000) throw new ActionError("Tiêu đề tối đa 200 ký tự, nội dung tối đa 2000 ký tự.");
        if (Regex.IsMatch(title + body, @"\[[^\]\{\}]{1,40}\]"))
            throw new ActionError("Nội dung còn chỗ trống [...] — hỏi người dùng nội dung thật để điền.");

        // Người nhận chỉ trong phạm vi quản lý (API gửi thông báo không tự lọc phạm vi — trợ lý chặn ở đây).
        var scoped = await EmployeesAsync(c, ct);
        var picked = new Dictionary<Guid, Emp>();
        var ids = IdList(a, "employee_ids");
        if (ids.Count > 0)
            foreach (var e in await ScopedEmployeesAsync(c, ids, ct)) picked[e.Id] = e;
        var depts = (S(a, "departments") ?? "").Split([',', ';'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        if (depts.Length > 0)
        {
            var scopedIds = scoped.Select(e => e.Id).ToList();
            var deptOf = await db.Employees.AsNoTracking().Where(e => scopedIds.Contains(e.Id))
                .Select(e => new { e.Id, e.Department, DeptName = e.DepartmentId != null
                    ? db.Departments.Where(d => d.Id == e.DepartmentId).Select(d => d.Name).FirstOrDefault() : null })
                .ToListAsync(ct);
            foreach (var dn in depts)
            {
                var q = VnSearch.FoldText(dn);
                var hit = deptOf.Where(x => Score(VnSearch.Fold(x.DeptName ?? x.Department ?? ""), q) > 0).Select(x => x.Id).ToHashSet();
                if (hit.Count == 0) throw new ActionError($"Không có nhân viên thuộc phòng ban «{dn}» trong phạm vi bạn quản lý.");
                foreach (var e in scoped.Where(e => hit.Contains(e.Id))) picked[e.Id] = e;
            }
        }
        if (Bool(a, "everyone")) foreach (var e in scoped) picked[e.Id] = e;
        if (picked.Count == 0) throw new ActionError("Chưa rõ gửi cho ai — hỏi người dùng (người cụ thể, phòng ban hay mọi người).");
        var withApp = picked.Values.Where(e => e.UserId != null && e.UserId != c.UserId).ToList();
        if (withApp.Count == 0) throw new ActionError("Những người này chưa có tài khoản đăng nhập app nên không nhận được thông báo.");
        if (withApp.Count > 2000) throw new ActionError("Tối đa 2.000 người nhận mỗi lần gửi.");

        var warnings = new List<string>();
        var noApp = picked.Values.Count(e => e.UserId == null);
        if (noApp > 0) warnings.Add($"{noApp} người chưa có tài khoản app — không nhận được.");
        return New(c, "announcement", "Thông báo nội bộ",
        [
            new("Tiêu đề", title), new("Nội dung", body.Length > 300 ? body[..300] + "…" : body),
            new("Người nhận", $"{withApp.Count} người: {Names(withApp.Select(e => e.Name), 5)}"),
        ], "POST", "/api/notification-center/send", new
        {
            title, body, categoryCode = "internal_comm", type = (int)NotificationType.Info, audience = "users",
            userIds = withApp.Select(e => e.UserId!.Value).ToList(),
        }, "Notification", warnings);
    }

    // ─── 5. Giao việc ──────────────────────────────────────────────

    async Task<Pending> TaskAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var title = S(a, "title") ?? throw new ActionError("Thiếu tên công việc.");
        var ids = IdList(a, "employee_ids").Concat(IdList(a, "employee_id")).Distinct().ToList();
        var emps = ids.Count > 0 ? await ScopedEmployeesAsync(c, ids, ct) : [];
        var priority = (S(a, "priority") ?? "").ToLowerInvariant() switch
        {
            "low" or "thấp" => TaskPriority.Low,
            "high" or "cao" => TaskPriority.High,
            "urgent" or "gấp" or "khẩn" => TaskPriority.Urgent,
            _ => TaskPriority.Medium,
        };
        var dueDate = D(a, "due_date");
        var dueTime = T(a, "due_time") ?? new TimeSpan(17, 0, 0);
        DateTime? due = dueDate?.Add(dueTime);
        var warnings = new List<string>();
        if (emps.Count == 0) warnings.Add("Chưa giao cho ai — việc nằm ở danh sách chờ giao.");
        if (due != null && due < AiAssistantVnTime.NowVn()) warnings.Add("Hạn hoàn thành đã qua.");
        string PriorityLabel() => priority switch
        {
            TaskPriority.Low => "Thấp", TaskPriority.High => "Cao", TaskPriority.Urgent => "Khẩn cấp", _ => "Trung bình",
        };
        return New(c, "task", "Công việc",
        [
            new("Công việc", title),
            .. S(a, "description") is { } desc ? new[] { new Line("Mô tả", desc.Length > 300 ? desc[..300] + "…" : desc) } : [],
            new("Giao cho", emps.Count == 0 ? "—" : Names(emps.Select(e => e.Name))),
            new("Hạn", due?.ToString("HH:mm dd/MM/yyyy") ?? "Không đặt hạn"), new("Ưu tiên", PriorityLabel()),
        ], "POST", "/api/Tasks", new
        {
            title, description = S(a, "description"), taskType = (int)TaskType.Task, priority = (int)priority,
            assigneeId = emps.Count > 0 ? emps[0].Id : (Guid?)null,
            assigneeIds = emps.Count > 0 ? emps.Select(e => e.Id).ToList() : null,
            // Giờ VN không múi giờ — như app gửi (DateTime.toIso8601String của giờ máy).
            dueDate = due?.ToString("yyyy-MM-dd'T'HH:mm:ss"), requireAcceptance = true,
        }, "Task", warnings);
    }

    // ─── 6. Chốt ca thu ngân ───────────────────────────────────────

    async Task<Pending> CloseCashierShiftAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var counted = ParseMoney(S(a, "counted_cash")) ?? throw new ActionError("Thiếu số tiền đếm thực tế trong két — hỏi người dùng.");
        if (counted < 0) throw new ActionError("Số tiền đếm không hợp lệ.");
        counted = Math.Round(counted, 0);
        var userId = c.UserId;
        var who = "bạn";
        if (G(a, "employee_id") is Guid eid)
        {
            var e = (await EmployeesAsync(c, ct)).FirstOrDefault(x => x.Id == eid)
                    ?? throw new ActionError("Không tìm thấy nhân viên trong phạm vi bạn quản lý.");
            if (e.UserId != c.UserId)
            {
                if (!IsManager(c)) throw new ActionError("Chỉ quản lý mới chốt ca của người khác.");
                userId = e.UserId ?? throw new ActionError($"{e.Name} chưa có tài khoản — không có ca thu ngân.");
                who = e.Name;
            }
        }
        var shift = await db.PosCashierShifts.AsNoTracking()
                        .Where(s => s.StoreId == c.StoreId && s.Deleted == null && s.Status == "Open" && s.OpenedByUserId == userId)
                        .OrderByDescending(s => s.OpenedAt).FirstOrDefaultAsync(ct)
                    ?? throw new ActionError($"Không có ca thu ngân đang mở của {who}.");

        var lines = new List<Line>
        {
            new("Ca mở lúc", $"{AiAssistantVnTime.ToVn(shift.OpenedAt):HH:mm dd/MM/yyyy} · {shift.OpenedByName ?? who}"),
            new("Tiền đầu ca", Vnd(shift.OpeningCash)),
        };
        var warnings = new List<string>();
        decimal? expected = null;
        try
        {
            var hq = http?.HttpContext.BranchContext()?.HeadquarterBranchId;
            var b = await PosShiftCashHelper.ComputeAsync(db, shift, hq);
            expected = b.ExpectedCash;
            lines.Add(new("Thu tiền mặt bán hàng", Vnd(b.SaleCash)));
            if (b.DebtCash + b.DepositCash + b.OtherCashIn != 0)
                lines.Add(new("Thu nợ / cọc / thu khác", Vnd(b.DebtCash + b.DepositCash + b.OtherCashIn)));
            if (b.RefundCash + b.DepositRefundCash + b.OtherCashOut != 0)
                lines.Add(new("Hoàn tiền / chi", "-" + Vnd(b.RefundCash + b.DepositRefundCash + b.OtherCashOut)));
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            logger.LogWarning(ex, "AI close shift: expected cash failed");
        }
        lines.Add(new("Dự kiến trong két", expected is decimal ex2 ? Vnd(ex2) : "(tính khi chốt)"));
        lines.Add(new("Đếm thực tế", Vnd(counted)));
        if (expected is decimal exp)
        {
            var diff = counted - exp;
            lines.Add(new("Chênh lệch", diff == 0 ? "Khớp" : (diff > 0 ? "+" : "-") + Vnd(Math.Abs(diff)) + (diff > 0 ? " (thừa)" : " (thiếu)")));
            if (diff != 0) warnings.Add($"Két {(diff > 0 ? "thừa" : "thiếu")} {Vnd(Math.Abs(diff))} so với dự kiến — ghi lý do vào ghi chú.");
        }
        var note = S(a, "note");
        if (note != null) lines.Add(new("Ghi chú", note));
        var step = new Step("POST", $"/api/pos/cashier-shifts/{shift.Id}/close", J(new { countedCash = counted, note }), Label: "Chốt ca");
        // Một bước dạng lô để thẻ báo «Đã chốt ca thu ngân» (không hoàn tác — ca đã đóng không mở lại được).
        return New(c, "close_cashier_shift", "Chốt ca thu ngân", lines, "POST", step.Path, null, "PosCashierShift", warnings)
            with { Steps = [step], Batch = true, BatchUndo = [null], Risk = "high" };
    }

    // ─── 7. Phạt hàng loạt theo chấm công ──────────────────────────

    sealed record Violation(Emp E, int Minutes, string Detail);

    /// <summary>
    /// Người vi phạm trong ngày theo LỊCH LÀM VIỆC + GIỜ CHẤM (cùng cách «AI ĐI TRỄ HÔM NAY»): máy chấm công (DeviceUser /
    /// mã NV = PIN trên máy của cửa hàng) và chấm công điện thoại. Chỉ nhân viên trong danh sách (đã lọc phạm vi).
    /// </summary>
    async Task<List<Violation>> ViolationsAsync(Ctx c, DateTime date, string type, List<Emp> emps, CancellationToken ct)
    {
        if (emps.Count == 0) return [];
        var next = date.AddDays(1);
        var keys = emps.Select(e => e.Id).Concat(emps.Where(e => e.UserId != null).Select(e => e.UserId!.Value)).Distinct().ToList();
        var schedules = await db.WorkSchedules.AsNoTracking()
            .Where(w => w.StoreId == c.StoreId && w.Date >= date && w.Date < next && !w.IsDayOff && keys.Contains(w.EmployeeUserId))
            .Select(w => new { w.EmployeeUserId, w.ShiftId, w.StartTime, w.EndTime })
            .ToListAsync(ct);
        if (schedules.Count == 0) return [];
        var shiftIds = schedules.Where(s => s.ShiftId != null).Select(s => s.ShiftId!.Value).Distinct().ToList();
        var shifts = await db.ShiftTemplates.AsNoTracking().Where(s => shiftIds.Contains(s.Id))
            .Select(s => new { s.Id, s.StartTime, s.EndTime, s.LateGraceMinutes, s.EarlyLeaveGraceMinutes })
            .ToDictionaryAsync(s => s.Id, ct);

        var empIds = emps.Select(e => e.Id).ToList();
        var devMap = (await db.DeviceUsers.AsNoTracking()
                .Where(d => d.EmployeeId != null && empIds.Contains(d.EmployeeId.Value))
                .Select(d => new { d.Id, Emp = d.EmployeeId!.Value }).ToListAsync(ct))
            .ToDictionary(d => d.Id, d => d.Emp);
        var devIds = devMap.Keys.ToList();
        var byCode = emps.Where(e => !string.IsNullOrEmpty(e.Code)).GroupBy(e => e.Code).ToDictionary(g => g.Key, g => g.First().Id);
        var codes = byCode.Keys.ToList();
        var storeDevices = await db.Devices.AsNoTracking().Where(d => d.StoreId == c.StoreId).Select(d => d.Id).ToListAsync(ct);
        var logs = await db.AttendanceLogs.AsNoTracking()
            .Where(l => l.AttendanceTime >= date && l.AttendanceTime < next
                        && ((l.EmployeeId != null && devIds.Contains(l.EmployeeId.Value))
                            || (codes.Contains(l.PIN) && storeDevices.Contains(l.DeviceId))))
            .Select(l => new { l.EmployeeId, l.PIN, l.AttendanceTime, l.AttendanceState })
            .ToListAsync(ct);
        var punches = new Dictionary<Guid, List<(DateTime At, bool? In)>>();
        void Add(Guid emp, DateTime at, bool? isIn)
        {
            if (!punches.TryGetValue(emp, out var l)) punches[emp] = l = [];
            l.Add((at, isIn));
        }
        foreach (var l in logs)
        {
            Guid? emp = l.EmployeeId is Guid du && devMap.TryGetValue(du, out var m) ? m
                : byCode.TryGetValue(l.PIN, out var m2) ? m2 : null;
            if (emp is Guid g)
                Add(g, AiAssistantVnTime.AttendanceToVn(l.AttendanceTime),
                    l.AttendanceState == AttendanceStates.CheckIn ? true : l.AttendanceState == AttendanceStates.CheckOut ? false : null);
        }
        var mobileKey = emps.Where(e => e.UserId != null).ToDictionary(e => e.UserId!.Value.ToString(), e => e.Id);
        foreach (var (code, id) in byCode) mobileKey.TryAdd(code, id);
        var mobileKeys = mobileKey.Keys.ToList();
        var mobile = await db.MobileAttendanceRecords.AsNoTracking()
            .Where(m => m.StoreId == c.StoreId && m.IsActive && m.PunchTime >= date && m.PunchTime < next
                        && mobileKeys.Contains(m.OdooEmployeeId) && m.Status != "rejected")
            .Select(m => new { m.OdooEmployeeId, m.PunchTime, m.PunchType })
            .ToListAsync(ct);
        foreach (var m in mobile)
            Add(mobileKey[m.OdooEmployeeId], AiAssistantVnTime.AttendanceToVn(m.PunchTime), m.PunchType == 0);

        var leaves = type == "UnauthorizedLeave"
            ? await db.Leaves.AsNoTracking()
                .Where(l => l.StoreId == c.StoreId && l.Status == LeaveStatus.Approved && l.StartDate < next && l.EndDate >= date)
                .Select(l => new { l.EmployeeUserId, l.EmployeeId }).ToListAsync(ct)
            : [];
        var now = AiAssistantVnTime.NowVn();
        var result = new List<Violation>();
        foreach (var e in emps)
        {
            var sch = schedules.FirstOrDefault(s => s.EmployeeUserId == e.Id || (e.UserId != null && s.EmployeeUserId == e.UserId));
            if (sch == null) continue;
            var st = sch.ShiftId is Guid sid && shifts.TryGetValue(sid, out var t) ? t : null;
            var start = sch.StartTime ?? st?.StartTime;
            var end = sch.EndTime ?? st?.EndTime;
            if (start == null) continue;
            var p = punches.GetValueOrDefault(e.Id) ?? [];
            switch (type)
            {
                case "Late":
                {
                    if (p.Count == 0) continue;
                    var first = p.Where(x => x.In == true).Select(x => (DateTime?)x.At).Min() ?? p.Min(x => x.At);
                    var grace = TimeSpan.FromMinutes(Math.Max(st?.LateGraceMinutes ?? 5, 0));
                    if (first.TimeOfDay <= start.Value + grace) continue;
                    var min = (int)(first.TimeOfDay - start.Value).TotalMinutes;
                    result.Add(new(e, min, $"vào {first:HH:mm}, ca {start.Value:hh\\:mm} — trễ {min} phút"));
                    break;
                }
                case "EarlyLeave":
                {
                    if (end == null || end <= start) continue; // ca qua đêm: để màn chấm công tính
                    var outs = p.Where(x => x.In == false).Select(x => x.At).ToList();
                    if (outs.Count == 0 && p.Count >= 2) outs = [p.Max(x => x.At)];
                    if (outs.Count == 0) continue;
                    var last = outs.Max();
                    var grace = TimeSpan.FromMinutes(Math.Max(st?.EarlyLeaveGraceMinutes ?? 5, 0));
                    if (last.TimeOfDay >= end.Value - grace) continue;
                    var min = (int)(end.Value - last.TimeOfDay).TotalMinutes;
                    result.Add(new(e, min, $"ra {last:HH:mm}, ca đến {end.Value:hh\\:mm} — về sớm {min} phút"));
                    break;
                }
                default: // UnauthorizedLeave
                {
                    if (p.Count > 0) continue;
                    if (date > now.Date || (date == now.Date && now.TimeOfDay < start.Value + TimeSpan.FromHours(2))) continue;
                    if (leaves.Any(l => l.EmployeeId == e.Id || (e.UserId != null && l.EmployeeUserId == e.UserId))) continue;
                    result.Add(new(e, 0, $"có ca {start.Value:hh\\:mm} nhưng không chấm công, không có đơn nghỉ được duyệt"));
                    break;
                }
            }
        }
        return result;
    }

    /// <summary>Mức phạt theo Thiết lập phạt (như phiếu phạt tự động từ chấm công). 0 = dưới mức phạt.</summary>
    static decimal SettingAmount(PenaltySetting s, string type, int minutes) => type switch
    {
        "Late" => minutes >= s.LateMinutes3 ? s.LatePenalty3 : minutes >= s.LateMinutes2 ? s.LatePenalty2
            : minutes >= s.LateMinutes1 ? s.LatePenalty1 : 0,
        "EarlyLeave" => minutes >= s.EarlyMinutes3 ? s.EarlyPenalty3 : minutes >= s.EarlyMinutes2 ? s.EarlyPenalty2
            : minutes >= s.EarlyMinutes1 ? s.EarlyPenalty1 : 0,
        _ => s.UnauthorizedLeavePenalty,
    };

    async Task<Pending> PenaltiesForLateAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var today = AiAssistantVnTime.NowVn().Date;
        var date = D(a, "date") ?? today;
        if (date > today) throw new ActionError("Chưa tới ngày này — chưa có chấm công để phạt.");
        var type = PenaltyType(S(a, "type") ?? "Late");
        if (type is not ("Late" or "EarlyLeave" or "UnauthorizedLeave"))
            throw new ActionError("type phải là Late | EarlyLeave | UnauthorizedLeave (vi phạm khác dùng propose_penalty từng người).");
        var only = IdList(a, "employee_ids");
        var emps = only.Count > 0 ? await ScopedEmployeesAsync(c, only, ct) : await EmployeesAsync(c, ct);
        decimal? flat = S(a, "amount") != null ? Money(a, "amount") : null;
        PenaltySetting? settings = null;
        if (flat == null)
            settings = await db.PenaltySettings.AsNoTracking().FirstOrDefaultAsync(s => s.StoreId == c.StoreId && s.Deleted == null, ct)
                       ?? throw new ActionError("Cửa hàng chưa có Thiết lập phạt — hỏi người dùng số tiền phạt mỗi người "
                                                + "(hoặc lấy đúng mức trong nội quy cửa hàng) rồi truyền amount.");

        var label = PenaltyLabels[type];
        var violations = await ViolationsAsync(c, date, type, emps, ct);
        if (violations.Count == 0)
            throw new ActionError($"Không có ai {label.ToLower(Vi)} ngày {date:dd/MM/yyyy} (theo lịch làm việc và giờ chấm công"
                                  + (c.Scope.WholeStore ? "" : ", trong phạm vi bạn quản lý") + ").");

        // Không lập trùng: đã có phiếu cùng loại cùng ngày (chưa hủy) — kể cả phiếu tự động từ chấm công.
        var ptype = Enum.Parse<PenaltyTicketType>(type);
        var vIds = violations.Select(v => v.E.Id).ToList();
        var next = date.AddDays(1);
        var already = (await db.PenaltyTickets.AsNoTracking()
                .Where(t => vIds.Contains(t.EmployeeId) && t.Deleted == null && t.Type == ptype
                            && t.Status != PenaltyTicketStatus.Cancelled && t.ViolationDate >= date && t.ViolationDate < next)
                .Select(t => t.EmployeeId).ToListAsync(ct))
            .ToHashSet();

        var steps = new List<Step>();
        var rows = new List<Line>();
        var skipped = new List<string>();
        decimal total = 0;
        foreach (var v in violations)
        {
            if (already.Contains(v.E.Id))
            {
                skipped.Add($"{v.E.Name} (đã có phiếu)");
                continue;
            }
            var amount = flat ?? SettingAmount(settings!, type, v.Minutes);
            if (amount <= 0)
            {
                skipped.Add($"{v.E.Name} ({v.Minutes} phút — dưới mức phạt)");
                continue;
            }
            var desc = S(a, "description") is { } d ? $"{d} — {v.Detail}" : $"{label} ngày {date:dd/MM/yyyy}: {v.Detail}";
            steps.Add(new("POST", "/api/PenaltyTickets", J(new
            {
                employeeId = v.E.Id, type, amount, violationDate = date.ToString("yyyy-MM-dd"),
                minutesLateOrEarly = type == "UnauthorizedLeave" ? (int?)null : v.Minutes, description = desc,
            }), Label: v.E.Name));
            rows.Add(new(v.E.Name, $"{v.Detail} · {Vnd(amount)}"));
            total += amount;
        }
        if (steps.Count == 0)
            throw new ActionError($"Không cần lập thêm phiếu: {string.Join(", ", skipped.Take(8))}.");

        var lines = new List<Line>
        {
            new("Ngày", date.ToString("dd/MM/yyyy")), new("Loại", label),
            new("Mức phạt", flat is decimal f ? $"{Vnd(f)} / người" : "Theo Thiết lập phạt của cửa hàng"),
        };
        lines.AddRange(rows);
        lines.Add(new("Tổng", $"{steps.Count} phiếu · {Vnd(total)}"));
        var warnings = new List<string>();
        if (skipped.Count > 0)
            warnings.Add($"Bỏ qua {skipped.Count} người: " + string.Join(", ", skipped.Take(6)) + (skipped.Count > 6 ? "…" : ""));
        warnings.Add("Phiếu ở trạng thái chờ duyệt — nhân viên được khiếu nại trước khi trừ lương.");
        return New(c, "penalty_batch", $"Phạt {label.ToLower(Vi)} {steps.Count} người", lines, "POST", "/api/PenaltyTickets", null,
                "PenaltyTickets", warnings)
            with
            {
                Steps = steps, Batch = true, BatchUndo = steps.Select(_ => (Step?)null).ToList(),
                Risk = steps.Count > 5 ? "high" : "normal",
            };
    }
}
