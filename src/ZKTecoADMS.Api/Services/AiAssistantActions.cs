using System.Globalization;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using ZKTecoADMS.Application.DTOs.Permissions;
using ZKTecoADMS.Application.Helpers;
using ZKTecoADMS.Domain.Enums;
using ZKTecoADMS.Infrastructure;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Trợ lý ảo thêm / sửa chứng từ bằng lời nói: Gemini gọi công cụ «đề xuất» → server tra đúng nhân viên / hàng hóa /
/// danh mục của cửa hàng, dựng sẵn yêu cầu tới API thật của app và giữ ở dạng CHỜ XÁC NHẬN. Người dùng bấm
/// «Xác nhận» trên thẻ thì server mới gọi API đó bằng chính phiên đăng nhập của họ (cùng quyền, gói, chi nhánh,
/// cùng kiểm tra nghiệp vụ như thao tác tay) — AI không tự ghi dữ liệu.
/// </summary>
public sealed class AiAssistantActions(
    ZKTecoDbContext db,
    IMemoryCache cache,
    IHttpContextAccessor http,
    ILogger<AiAssistantActions> logger)
{
    static readonly HttpClient Loopback = new(new SocketsHttpHandler { PooledConnectionLifetime = TimeSpan.FromMinutes(5) })
    { Timeout = TimeSpan.FromSeconds(60) };

    static readonly JsonSerializerOptions Json = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull,
    };

    static readonly CultureInfo Vi = new("vi-VN");

    public sealed record Line(string Label, string Value);

    /// <summary>Thao tác đã dựng xong, chờ người dùng xác nhận (giữ 30 phút trong bộ nhớ).</summary>
    public sealed record Pending(
        string Id, Guid UserId, Guid StoreId, string Kind, string Title, List<Line> Lines,
        string Method, string Path, string? Body, string? OpenModule, List<string> Warnings)
    {
        /// <summary>Phiếu kho nhiều bước (tạo → thêm dòng → số lượng → hoàn tất). Null = một lời gọi.</summary>
        public List<Step>? Steps { get; init; }
        /// <summary>Số lượng theo hàng cho bước điền dòng (LinesFrom).</summary>
        public Dictionary<Guid, decimal>? LineQty { get; init; }
    }

    /// <summary>
    /// Một bước gọi API. Path có «{id}» = id phiếu tạo ở bước đầu. LinesFrom = "qty" | "counted": thân dựng từ
    /// danh sách dòng bước trước trả về (lineId theo hàng) + <see cref="Pending.LineQty"/>.
    /// </summary>
    public sealed record Step(string Method, string Path, string? Body, string? LinesFrom = null);

    public sealed record Ctx(
        Guid StoreId, Guid UserId, string Role,
        IReadOnlyDictionary<string, ModulePermissionDto> Perms, bool IsSuper, IReadOnlyCollection<string>? Package);

    sealed record Def(string Name, string Module, char Need, bool ManagerOnly, string Description,
        Dictionary<string, (string Type, string Desc)> Params, string[] Required);

    static readonly string[] ManagerRoles = ["Admin", "Director", "SuperAdmin", "Manager", "DepartmentHead", "Accountant", "Agent"];

    // ─── Danh mục thao tác ─────────────────────────────────────────

    static readonly Def[] Defs =
    [
        new("propose_advance", "AdvanceRequests", 'C', false,
            "Lập YÊU CẦU ỨNG LƯƠNG (chờ duyệt). Không có employee_id = ứng cho chính người hỏi.",
            new()
            {
                ["employee_id"] = ("STRING", "Id nhân viên (từ find_employees) — chỉ khi ứng cho người khác"),
                ["amount"] = ("NUMBER", "Số tiền VNĐ"),
                ["reason"] = ("STRING", "Lý do"),
                ["month"] = ("INTEGER", "Trừ vào lương tháng (1-12), bỏ trống = tháng này"),
                ["installments"] = ("INTEGER", "Trừ dần trong bao nhiêu kỳ lương (mặc định 1)"),
            }, ["amount"]),
        new("propose_penalty", "PenaltyTickets", 'C', true,
            "Lập PHIẾU PHẠT cho nhân viên (chờ duyệt).",
            new()
            {
                ["employee_id"] = ("STRING", "Id nhân viên (từ find_employees)"),
                ["amount"] = ("NUMBER", "Số tiền phạt VNĐ"),
                ["date"] = ("STRING", "Ngày vi phạm yyyy-MM-dd (mặc định hôm nay)"),
                ["type"] = ("STRING", "Late (đi trễ) | EarlyLeave (về sớm) | ForgotCheck (quên chấm công) | UnauthorizedLeave (nghỉ không phép) | Violation (vi phạm khác) | Repeat (tái phạm)"),
                ["minutes"] = ("INTEGER", "Số phút trễ / về sớm (nếu có)"),
                ["description"] = ("STRING", "Nội dung vi phạm"),
            }, ["employee_id", "amount"]),
        new("propose_update_penalty", "PenaltyTickets", 'E', true,
            "SỬA phiếu phạt đang chờ duyệt (số tiền / loại / nội dung). Tìm phiếu bằng find_records kind=penalty.",
            new()
            {
                ["record_id"] = ("STRING", "Id phiếu phạt (từ find_records)"),
                ["amount"] = ("NUMBER", "Số tiền mới"),
                ["type"] = ("STRING", "Loại mới (như propose_penalty)"),
                ["description"] = ("STRING", "Nội dung mới"),
            }, ["record_id"]),
        new("propose_reward", "BonusPenalty", 'C', true,
            "Lập PHIẾU THƯỞNG cho nhân viên (cộng vào lương).",
            new()
            {
                ["employee_id"] = ("STRING", "Id nhân viên (từ find_employees)"),
                ["amount"] = ("NUMBER", "Số tiền thưởng VNĐ"),
                ["date"] = ("STRING", "Ngày yyyy-MM-dd (mặc định hôm nay)"),
                ["description"] = ("STRING", "Lý do thưởng"),
                ["month"] = ("INTEGER", "Tính vào lương tháng (1-12), bỏ trống = tháng của ngày"),
            }, ["employee_id", "amount"]),
        new("propose_update_reward", "BonusPenalty", 'E', true,
            "SỬA phiếu thưởng (số tiền / lý do / ngày). Tìm phiếu bằng find_records kind=reward.",
            new()
            {
                ["record_id"] = ("STRING", "Id phiếu thưởng (từ find_records)"),
                ["amount"] = ("NUMBER", "Số tiền mới"),
                ["description"] = ("STRING", "Lý do mới"),
                ["date"] = ("STRING", "Ngày mới yyyy-MM-dd"),
            }, ["record_id"]),
        new("propose_cash_voucher", "CashTransaction", 'C', false,
            "Lập PHIẾU THU hoặc PHIẾU CHI sổ quỹ (tiền điện, mua đồ, thu khác…).",
            new()
            {
                ["direction"] = ("STRING", "income (phiếu thu) | expense (phiếu chi)"),
                ["amount"] = ("NUMBER", "Số tiền VNĐ"),
                ["description"] = ("STRING", "Nội dung"),
                ["category"] = ("STRING", "Tên danh mục (xem find_cash_categories); bỏ trống = tự chọn"),
                ["method"] = ("STRING", "cash (tiền mặt) | bank (chuyển khoản)"),
                ["contact"] = ("STRING", "Người nộp / người nhận"),
                ["date"] = ("STRING", "Ngày yyyy-MM-dd (mặc định hôm nay)"),
            }, ["direction", "amount", "description"]),
        new("propose_update_cash_voucher", "CashTransaction", 'E', false,
            "SỬA phiếu thu / chi lập tay (số tiền, nội dung, danh mục, ngày). Phiếu tự sinh từ bán hàng / lương không sửa được.",
            new()
            {
                ["record_id"] = ("STRING", "Id phiếu (từ find_records kind=cash)"),
                ["amount"] = ("NUMBER", "Số tiền mới"),
                ["description"] = ("STRING", "Nội dung mới"),
                ["category"] = ("STRING", "Danh mục mới"),
                ["date"] = ("STRING", "Ngày mới yyyy-MM-dd"),
            }, ["record_id"]),
        new("propose_overtime", "Overtime", 'C', false,
            "Đăng ký TĂNG CA. Không có employee_id = cho chính người hỏi.",
            new()
            {
                ["employee_id"] = ("STRING", "Id nhân viên — chỉ khi đăng ký cho người khác"),
                ["date"] = ("STRING", "Ngày yyyy-MM-dd"),
                ["start"] = ("STRING", "Giờ bắt đầu HH:mm"),
                ["end"] = ("STRING", "Giờ kết thúc HH:mm"),
                ["type"] = ("STRING", "Weekday | Weekend | Holiday | Night (mặc định tự theo ngày)"),
                ["reason"] = ("STRING", "Lý do / công việc"),
            }, ["date", "start", "end"]),
        new("propose_attendance_fix", "AttendanceCorrection", 'C', false,
            "Gửi phiếu BỔ SUNG / SỬA CHẤM CÔNG (quên chấm, chấm sai giờ). Không có employee_id = cho chính người hỏi.",
            new()
            {
                ["employee_id"] = ("STRING", "Id nhân viên — chỉ khi làm cho người khác"),
                ["date"] = ("STRING", "Ngày yyyy-MM-dd"),
                ["time"] = ("STRING", "Giờ chấm đúng HH:mm"),
                ["punch"] = ("STRING", "in (giờ vào) | out (giờ ra) | bỏ trống"),
                ["reason"] = ("STRING", "Lý do"),
            }, ["date", "time"]),
        new("propose_sale_order", "PosSell", 'C', false,
            "Lập HÓA ĐƠN BÁN HÀNG (đơn hoàn thành, trừ kho, ghi sổ quỹ). Tìm hàng bằng find_products trước.",
            new()
            {
                ["items"] = ("ARRAY", "Danh sách {product_id, qty, price (bỏ trống = giá bán)}"),
                ["customer_id"] = ("STRING", "Id khách (từ find_customers) — bỏ trống = khách lẻ"),
                ["customer_name"] = ("STRING", "Tên khách lẻ (khi không có trong danh bạ)"),
                ["paid"] = ("STRING", "full (khách trả đủ) | none (ghi nợ — cần khách có trong danh bạ) | số tiền đã trả"),
                ["method"] = ("STRING", "cash (tiền mặt) | bank (chuyển khoản) | card"),
                ["discount"] = ("NUMBER", "Giảm giá cả đơn VNĐ"),
                ["note"] = ("STRING", "Ghi chú"),
            }, ["items"]),

        // ── Hàng hóa / kho / khuyến mãi ──
        new("propose_product", "PosProducts", 'C', false,
            "Thêm HÀNG HÓA / DỊCH VỤ mới vào danh mục.",
            new()
            {
                ["name"] = ("STRING", "Tên hàng"),
                ["price"] = ("NUMBER", "Giá bán VNĐ"),
                ["cost"] = ("NUMBER", "Giá vốn VNĐ"),
                ["unit"] = ("STRING", "Đơn vị tính (Cái, Lon, Kg, Ly…)"),
                ["category"] = ("STRING", "Tên nhóm hàng (chưa có thì tạo mới)"),
                ["type"] = ("STRING", "goods (hàng hóa, có tồn kho) | service (dịch vụ)"),
                ["stock"] = ("NUMBER", "Tồn kho ban đầu"),
                ["barcode"] = ("STRING", "Mã vạch"),
            }, ["name", "price"]),
        new("propose_purchase_receipt", "PosPurchaseReceipts", 'E', false,
            "Lập PHIẾU NHẬP KHO (nhập hàng từ nhà cung cấp) và hoàn thành — cộng tồn kho, ghi công nợ / chi tiền.",
            new()
            {
                ["supplier_id"] = ("STRING", "Id nhà cung cấp (find_suppliers) — bỏ trống nếu không rõ"),
                ["items"] = ("ARRAY", "Hàng nhập {product_id, qty, price = giá nhập (bỏ trống = giá vốn hiện tại)}"),
                ["paid"] = ("STRING", "full (trả đủ) | none (ghi nợ NCC) | số tiền đã trả"),
                ["method"] = ("STRING", "cash | bank"),
                ["note"] = ("STRING", "Ghi chú"),
            }, ["items"]),
        new("propose_stock_count", "PosStockCounts", 'E', false,
            "Lập PHIẾU KIỂM KHO với số đếm thực tế và hoàn thành — chênh lệch được cân bằng vào tồn kho.",
            new()
            {
                ["items"] = ("ARRAY", "Hàng đã đếm {product_id, qty = số lượng ĐẾM THỰC TẾ}"),
                ["note"] = ("STRING", "Ghi chú"),
            }, ["items"]),
        new("propose_damage_issue", "PosDamageIssues", 'E', false,
            "Lập PHIẾU XUẤT HỦY (hàng hỏng, vỡ, hết hạn) và hoàn thành — trừ tồn kho.",
            new()
            {
                ["items"] = ("ARRAY", "Hàng hủy {product_id, qty}"),
                ["reason"] = ("STRING", "Lý do hủy"),
            }, ["items"]),
        new("propose_internal_use", "PosInternalUseIssues", 'E', false,
            "Lập PHIẾU XUẤT DÙNG NỘI BỘ (dùng cho cửa hàng, nhân viên) và hoàn thành — trừ tồn kho.",
            new()
            {
                ["items"] = ("ARRAY", "Hàng xuất dùng {product_id, qty}"),
                ["recipient"] = ("STRING", "Người / bộ phận nhận"),
                ["reason"] = ("STRING", "Mục đích sử dụng"),
            }, ["items"]),
        new("propose_customer_return", "PosSaleReturns", 'A', false,
            "KHÁCH TRẢ HÀNG theo hóa đơn: nhập lại kho + hoàn tiền. Tìm hóa đơn bằng find_orders.",
            new()
            {
                ["order_id"] = ("STRING", "Id hóa đơn (find_orders)"),
                ["items"] = ("ARRAY", "Hàng trả {product_id, qty} — bỏ trống = trả cả hóa đơn"),
                ["refund_method"] = ("STRING", "cash | bank"),
                ["reason"] = ("STRING", "Lý do trả"),
            }, ["order_id"]),
        new("propose_purchase_return", "PosPurchaseReturns", 'E', false,
            "TRẢ HÀNG NHÀ CUNG CẤP và hoàn thành — trừ tồn kho, giảm công nợ / thu tiền NCC hoàn.",
            new()
            {
                ["supplier_id"] = ("STRING", "Id nhà cung cấp (find_suppliers)"),
                ["items"] = ("ARRAY", "Hàng trả {product_id, qty, price = giá trả (bỏ trống = giá vốn)}"),
                ["refund"] = ("NUMBER", "Tiền NCC hoàn lại ngay (0 = trừ công nợ)"),
                ["note"] = ("STRING", "Lý do / ghi chú"),
            }, ["items"]),
        new("propose_voucher", "PosProducts", 'C', false,
            "Tạo MÃ GIẢM GIÁ (voucher) dùng ở màn bán.",
            new()
            {
                ["code"] = ("STRING", "Mã voucher (viết liền, VD: TET2027) — bỏ trống = tự sinh"),
                ["name"] = ("STRING", "Tên chương trình"),
                ["kind"] = ("STRING", "percent (giảm %) | fixed (giảm tiền)"),
                ["value"] = ("NUMBER", "Số % hoặc số tiền giảm"),
                ["min_order"] = ("NUMBER", "Đơn tối thiểu VNĐ"),
                ["max_discount"] = ("NUMBER", "Giảm tối đa VNĐ (với giảm %)"),
                ["from"] = ("STRING", "Từ ngày yyyy-MM-dd"),
                ["to"] = ("STRING", "Đến ngày yyyy-MM-dd"),
                ["max_uses"] = ("INTEGER", "Số lượt dùng tối đa"),
            }, ["kind", "value"]),
        new("propose_promotion", "PosPromotions", 'C', false,
            "Tạo CHƯƠNG TRÌNH KHUYẾN MÃI tự áp ở màn bán.",
            new()
            {
                ["name"] = ("STRING", "Tên chương trình"),
                ["type"] = ("STRING", "bill_discount (giảm theo tổng hóa đơn) | time_discount (giảm % / giảm tiền mỗi món, có thể theo khung giờ) | qty_discount (mua nhiều giảm %) | buy_x_get_y (mua X tặng Y) | combo_price (đồng giá combo N món)"),
                ["percent"] = ("NUMBER", "% giảm (bill_discount / time_discount / qty_discount)"),
                ["amount"] = ("NUMBER", "Số tiền giảm (bill_discount: giảm cả hóa đơn; time_discount: giảm mỗi món)"),
                ["min_bill"] = ("NUMBER", "Hóa đơn tối thiểu (bill_discount)"),
                ["max_discount"] = ("NUMBER", "Giảm tối đa (bill_discount)"),
                ["min_qty"] = ("NUMBER", "Mua từ bao nhiêu (qty_discount)"),
                ["buy_qty"] = ("INTEGER", "Mua X (buy_x_get_y)"),
                ["get_qty"] = ("INTEGER", "Tặng Y (buy_x_get_y)"),
                ["gift_product_id"] = ("STRING", "Hàng tặng (buy_x_get_y) — bỏ trống = tặng chính hàng đó"),
                ["combo_qty"] = ("INTEGER", "Số món combo (combo_price)"),
                ["combo_price"] = ("NUMBER", "Giá đồng giá combo (combo_price)"),
                ["product_ids"] = ("STRING", "Id hàng áp dụng, cách nhau dấu phẩy (find_products) — bỏ trống = mọi hàng"),
                ["category"] = ("STRING", "Hoặc tên nhóm hàng áp dụng"),
                ["from"] = ("STRING", "Từ ngày yyyy-MM-dd"),
                ["to"] = ("STRING", "Đến ngày yyyy-MM-dd"),
                ["time_from"] = ("STRING", "Khung giờ từ HH:mm (giờ vàng)"),
                ["time_to"] = ("STRING", "Khung giờ đến HH:mm"),
                ["weekdays"] = ("STRING", "Thứ áp dụng, VD \"2,3,4\" (2 = Thứ Hai … 8 = Chủ nhật) — bỏ trống = mọi ngày"),
                ["members_only"] = ("BOOLEAN", "Chỉ khách thành viên"),
            }, ["name", "type"]),
    ];

    bool Can(Ctx c, string module, char need)
    {
        // Gói dịch vụ của cửa hàng phải có chức năng (kể cả Super Admin) — như middleware chặn API theo gói.
        if (c.Package is { Count: > 0 } pkg && !pkg.Contains(module, StringComparer.OrdinalIgnoreCase)) return false;
        if (c.IsSuper) return true;
        if (!c.Perms.TryGetValue(module, out var p)) return false;
        return need switch { 'E' => p.CanEdit, 'A' => p.CanApprove, _ => p.CanCreate };
    }

    bool IsManager(Ctx c) => c.IsSuper || ManagerRoles.Contains(c.Role, StringComparer.OrdinalIgnoreCase);

    IEnumerable<Def> AllowedDefs(Ctx c) => Defs.Where(d => Can(c, d.Module, d.Need) && (!d.ManagerOnly || IsManager(c)));

    // ─── Khai báo công cụ cho Gemini ───────────────────────────────

    public List<object> ToolDeclarations(Ctx c)
    {
        var allowed = AllowedDefs(c).ToList();
        if (allowed.Count == 0) return [];
        var decls = new List<object>();
        if (IsManager(c))
            decls.Add(Fn("find_employees", "Tìm nhân viên theo tên / mã (không dấu cũng được) → id dùng cho các công cụ đề xuất.",
                new() { ["query"] = ("STRING", "Tên hoặc mã nhân viên") }, ["query"]));
        if (allowed.Any(d => d.Name == "propose_sale_order"))
        {
            decls.Add(Fn("find_products", "Tìm hàng hóa / dịch vụ theo tên / mã / mã vạch → id, giá bán, đơn vị, tồn.",
                new() { ["query"] = ("STRING", "Tên / mã hàng") }, ["query"]));
            decls.Add(Fn("find_customers", "Tìm khách hàng theo tên / SĐT.",
                new() { ["query"] = ("STRING", "Tên / SĐT") }, ["query"]));
        }
        if (allowed.Any(d => d.Name is "propose_product" or "propose_purchase_receipt" or "propose_stock_count"
                or "propose_damage_issue" or "propose_internal_use" or "propose_purchase_return" or "propose_promotion"
                or "propose_customer_return")
            && !decls.Any(x => x.GetType().GetProperty("name")?.GetValue(x) as string == "find_products"))
            decls.Add(Fn("find_products", "Tìm hàng hóa / dịch vụ theo tên / mã / mã vạch → id, giá bán, giá vốn, đơn vị, tồn.",
                new() { ["query"] = ("STRING", "Tên / mã hàng") }, ["query"]));
        if (allowed.Any(d => d.Name is "propose_promotion" or "propose_product"))
            decls.Add(Fn("find_categories", "Danh sách nhóm hàng của cửa hàng (tên chính xác để áp khuyến mãi / xếp hàng mới).",
                new(), []));
        if (allowed.Any(d => d.Name is "propose_purchase_receipt" or "propose_purchase_return"))
            decls.Add(Fn("find_suppliers", "Tìm nhà cung cấp theo tên / SĐT.",
                new() { ["query"] = ("STRING", "Tên / SĐT nhà cung cấp") }, ["query"]));
        if (allowed.Any(d => d.Name == "propose_customer_return"))
            decls.Add(Fn("find_orders", "Tìm hóa đơn bán (để trả hàng) theo mã HĐ / tên / SĐT khách, trong 60 ngày.",
                new() { ["query"] = ("STRING", "Mã hóa đơn / khách") }, ["query"]));
        if (allowed.Any(d => d.Module == "CashTransaction"))
            decls.Add(Fn("find_cash_categories", "Danh mục thu / chi của cửa hàng.",
                new() { ["direction"] = ("STRING", "income | expense") }, []));
        if (allowed.Any(d => d.Need == 'E'))
            decls.Add(Fn("find_records", "Tìm phiếu đã có để sửa: penalty (phiếu phạt) | reward (phiếu thưởng) | cash (phiếu thu chi).",
                new()
                {
                    ["kind"] = ("STRING", "penalty | reward | cash"),
                    ["employee_id"] = ("STRING", "Lọc theo nhân viên (penalty / reward)"),
                    ["query"] = ("STRING", "Mã phiếu / nội dung"),
                    ["days"] = ("INTEGER", "Trong bao nhiêu ngày gần đây (mặc định 45)"),
                }, ["kind"]));
        foreach (var d in allowed)
            decls.Add(Fn(d.Name, d.Description + " CHỈ tạo bản nháp — người dùng bấm Xác nhận mới ghi.", d.Params, d.Required));
        return decls;
    }

    static object Fn(string name, string desc, Dictionary<string, (string Type, string Desc)> ps, string[] required)
    {
        var props = new Dictionary<string, object>();
        foreach (var (k, (t, ds)) in ps)
        {
            props[k] = t == "ARRAY"
                ? new
                {
                    type = "ARRAY",
                    description = ds,
                    items = new
                    {
                        type = "OBJECT",
                        properties = new Dictionary<string, object>
                        {
                            ["product_id"] = new { type = "STRING" },
                            ["qty"] = new { type = "NUMBER" },
                            ["price"] = new { type = "NUMBER" },
                        },
                        required = new[] { "product_id", "qty" },
                    },
                }
                : new { type = t, description = ds };
        }
        return ps.Count == 0
            ? new { name, description = desc }
            : new { name, description = desc, parameters = new { type = "OBJECT", properties = props, required } };
    }

    public static string Instructions(bool any) => !any ? "" : """
        === THÊM / SỬA CHỨNG TỪ ===
        - Người dùng muốn tạo / sửa phiếu (ứng lương, phạt, thưởng, thu chi, tăng ca, bổ sung chấm công, hóa đơn bán,
          hàng hóa mới, nhập kho, kiểm kho, xuất hủy, dùng nội bộ, khách trả hàng, trả hàng NCC, voucher, khuyến mãi…):
          dùng công cụ propose_* tương ứng (KHÔNG dùng thẻ [[CREATE:...]] cho các loại này).
        - Nhắc tên người / hàng / khách → gọi find_employees / find_products / find_customers trước để lấy id.
          Nhiều kết quả trùng tên → hỏi lại người dùng chọn ai, KHÔNG tự chọn.
        - Thiếu thông tin bắt buộc (số tiền, ngày, giờ, người…) → hỏi lại ngắn gọn, chưa gọi propose_*.
        - Có thể đề xuất nhiều phiếu một lượt (vd phạt 3 người) — mỗi phiếu một lời gọi propose_*.
        - Sau khi đề xuất: tóm tắt 1–2 câu và nhắc người dùng bấm «Xác nhận» trên thẻ. TUYỆT ĐỐI không nói "đã tạo".
        - Phiếu kho có nhiều mặt hàng: tra find_products cho TỪNG hàng rồi gọi propose_* MỘT lần với đủ danh sách items.
        - Khuyến mãi nhắc nhóm hàng («đồ uống», «món nướng»…) → gọi find_categories rồi truyền category đúng tên;
          nhắc từng món → find_products rồi truyền product_ids. Chỉ để trống khi người dùng nói áp cho MỌI hàng.
        - Kiểm kho: qty là số ĐẾM THỰC TẾ (không phải số chênh lệch). Khách trả hàng: tra find_orders để lấy order_id.
        - Quy đổi lời nói: "năm trăm nghìn / năm trăm k / 500k" = 500000; "1 triệu rưỡi" = 1500000; "chiều nay 5 giờ" = 17:00.
        """;

    // ─── Xử lý lời gọi công cụ ─────────────────────────────────────

    public bool Handles(string tool) => tool is "find_employees" or "find_products" or "find_customers"
        or "find_cash_categories" or "find_records" or "find_suppliers" or "find_orders" or "find_categories"
        || tool.StartsWith("propose_", StringComparison.Ordinal);

    public async Task<object> HandleAsync(string tool, JsonElement args, Ctx c, List<Pending> proposed, CancellationToken ct)
    {
        var a = Args(args);
        switch (tool)
        {
            case "find_employees": return await FindEmployeesAsync(c, S(a, "query"), ct);
            case "find_products": return await FindProductsAsync(c, S(a, "query"), ct);
            case "find_customers": return await FindCustomersAsync(c, S(a, "query"), ct);
            case "find_cash_categories": return await CashCategoriesAsync(c, S(a, "direction"), ct);
            case "find_records": return await FindRecordsAsync(c, a, ct);
            case "find_suppliers": return await FindSuppliersAsync(c, S(a, "query"), ct);
            case "find_orders": return await FindOrdersAsync(c, S(a, "query"), ct);
            case "find_categories":
                return new
                {
                    nhom_hang = await db.PosProductCategories.AsNoTracking().Where(x => x.StoreId == c.StoreId)
                        .OrderBy(x => x.Name).Select(x => x.Name).Take(200).ToListAsync(ct),
                };
        }

        var def = AllowedDefs(c).FirstOrDefault(d => d.Name == tool);
        if (def == null) return new { error = "Tài khoản không có quyền thực hiện thao tác này." };
        var missing = def.Required.Where(r => !a.ContainsKey(r) || string.IsNullOrWhiteSpace(a[r]?.ToString())).ToList();
        if (missing.Count > 0) return new { error = "Thiếu thông tin: " + string.Join(", ", missing) + " — hỏi lại người dùng." };

        Pending? p;
        try
        {
            p = tool switch
            {
                "propose_advance" => await AdvanceAsync(c, a, ct),
                "propose_penalty" => await PenaltyAsync(c, a, ct),
                "propose_update_penalty" => await UpdatePenaltyAsync(c, a, ct),
                "propose_reward" => await RewardAsync(c, a, ct),
                "propose_update_reward" => await UpdateRewardAsync(c, a, ct),
                "propose_cash_voucher" => await CashAsync(c, a, ct),
                "propose_update_cash_voucher" => await UpdateCashAsync(c, a, ct),
                "propose_overtime" => await OvertimeAsync(c, a, ct),
                "propose_attendance_fix" => await AttendanceFixAsync(c, a, ct),
                "propose_sale_order" => await SaleAsync(c, a, ct),
                "propose_product" => ProductProposal(c, a),
                "propose_purchase_receipt" => await PurchaseReceiptAsync(c, a, ct),
                "propose_stock_count" => await StockCountAsync(c, a, ct),
                "propose_damage_issue" => await StockIssueAsync(c, a, "damage", ct),
                "propose_internal_use" => await StockIssueAsync(c, a, "internal-use", ct),
                "propose_customer_return" => await CustomerReturnAsync(c, a, ct),
                "propose_purchase_return" => await PurchaseReturnAsync(c, a, ct),
                "propose_voucher" => VoucherProposal(c, a),
                "propose_promotion" => await PromotionAsync(c, a, ct),
                _ => null,
            };
        }
        catch (ActionError e)
        {
            return new { error = e.Message };
        }
        if (p == null) return new { error = "Không dựng được phiếu." };

        cache.Set(Key(p.Id), p, new MemoryCacheEntryOptions { AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(30), Size = 1 });
        proposed.Add(p);
        return new
        {
            status = "cho_xac_nhan",
            tom_tat = p.Title + ": " + string.Join("; ", p.Lines.Select(l => $"{l.Label} {l.Value}")),
            canh_bao = p.Warnings,
            luu_y = "Đã hiện thẻ cho người dùng bấm Xác nhận. Chưa ghi dữ liệu — không nói đã tạo.",
        };
    }

    sealed class ActionError(string message) : Exception(message);

    // ─── Tra cứu ────────────────────────────────────────────────────

    sealed record Emp(Guid Id, Guid? UserId, string Code, string Name, string? Dept);

    async Task<List<Emp>> EmployeesAsync(Ctx c, CancellationToken ct) =>
        (await db.Employees.AsNoTracking()
            .Where(e => e.StoreId == c.StoreId && e.Deleted == null && e.WorkStatus != EmployeeWorkStatus.Resigned)
            .Select(e => new { e.Id, e.ApplicationUserId, e.EmployeeCode, e.FirstName, e.LastName, Dept = e.Department })
            .ToListAsync(ct))
        .Select(e => new Emp(e.Id, e.ApplicationUserId, e.EmployeeCode, $"{e.FirstName} {e.LastName}".Trim(), e.Dept))
        .ToList();

    static int Score(string fold, string q)
    {
        if (fold == q) return 100;
        if (fold.EndsWith(" " + q) || fold.StartsWith(q + " ")) return 80;
        if (fold.Contains(q)) return 60;
        var words = q.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return words.Length > 0 && words.All(fold.Contains) ? 40 : 0;
    }

    async Task<object> FindEmployeesAsync(Ctx c, string? query, CancellationToken ct)
    {
        var q = VnSearch.FoldText(query);
        if (q.Length == 0) return new { error = "Thiếu tên" };
        var list = (await EmployeesAsync(c, ct))
            .Select(e => (e, s: Math.Max(Score(VnSearch.Fold(e.Name), q), VnSearch.Fold(e.Code) == q ? 100 : 0)))
            .Where(x => x.s > 0)
            .OrderByDescending(x => x.s).ThenBy(x => x.e.Name)
            .Take(8)
            .Select(x => new { id = x.e.Id, ma = x.e.Code, ten = x.e.Name, phong_ban = x.e.Dept })
            .ToList();
        return list.Count == 0 ? new { ket_qua = "Không tìm thấy nhân viên khớp" } : new { ket_qua = list };
    }

    async Task<object> FindProductsAsync(Ctx c, string? query, CancellationToken ct)
    {
        var q = VnSearch.FoldText(query);
        if (q.Length == 0) return new { error = "Thiếu tên hàng" };
        var raw = query!.Trim();
        var rows = await db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == c.StoreId && p.Deleted == null && p.IsActive)
            .Select(p => new { p.Id, p.ProductCode, p.Barcode, p.Name, p.BasePrice, p.CostPrice, p.BaseUnitName, p.OnHandQty, p.ProductType })
            .ToListAsync(ct);
        var list = rows
            .Select(p => (p, s: p.ProductCode.Equals(raw, StringComparison.OrdinalIgnoreCase) || p.Barcode == raw
                ? 100 : Score(VnSearch.Fold(p.Name), q)))
            .Where(x => x.s > 0)
            .OrderByDescending(x => x.s).ThenBy(x => x.p.Name.Length)
            .Take(8)
            .Select(x => new
            {
                id = x.p.Id, ma = x.p.ProductCode, ten = x.p.Name, gia_ban = x.p.BasePrice, gia_von = x.p.CostPrice,
                don_vi = x.p.BaseUnitName,
                ton = x.p.ProductType == PosProductType.Goods ? x.p.OnHandQty : (decimal?)null,
            })
            .ToList();
        return list.Count == 0 ? new { ket_qua = "Không tìm thấy hàng khớp" } : new { ket_qua = list };
    }

    async Task<object> FindCustomersAsync(Ctx c, string? query, CancellationToken ct)
    {
        var q = VnSearch.FoldText(query);
        if (q.Length == 0) return new { error = "Thiếu tên / SĐT" };
        var digits = new string((query ?? "").Where(char.IsDigit).ToArray());
        var rows = await db.PosCustomers.AsNoTracking()
            .Where(x => x.StoreId == c.StoreId && x.Deleted == null)
            .Select(x => new { x.Id, x.Name, x.Phone })
            .ToListAsync(ct);
        var list = rows
            .Select(x => (x, s: digits.Length >= 6 && (x.Phone ?? "").Contains(digits) ? 100 : Score(VnSearch.Fold(x.Name), q)))
            .Where(t => t.s > 0)
            .OrderByDescending(t => t.s)
            .Take(8)
            .Select(t => new { id = t.x.Id, ten = t.x.Name, sdt = t.x.Phone })
            .ToList();
        return list.Count == 0 ? new { ket_qua = "Không có khách khớp — có thể dùng customer_name (khách lẻ)" } : new { ket_qua = list };
    }

    async Task<List<(Guid Id, string Name, CashTransactionType Type)>> CategoriesAsync(Ctx c, CancellationToken ct) =>
        (await db.TransactionCategories.AsNoTracking()
            .Where(x => (x.StoreId == c.StoreId || x.StoreId == null) && x.Deleted == null && x.IsActive)
            .OrderBy(x => x.SortOrder)
            .Select(x => new { x.Id, x.Name, x.Type })
            .ToListAsync(ct))
        .Select(x => (x.Id, x.Name, x.Type)).ToList();

    async Task<object> CashCategoriesAsync(Ctx c, string? direction, CancellationToken ct)
    {
        var all = await CategoriesAsync(c, ct);
        var t = Direction(direction);
        return new
        {
            danh_muc = all.Where(x => t == null || x.Type == t)
                .Select(x => new { ten = x.Name, loai = x.Type == CashTransactionType.Income ? "thu" : "chi" })
                .DistinctBy(x => x.ten + x.loai).ToList(),
        };
    }

    async Task<object> FindRecordsAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var kind = (S(a, "kind") ?? "").ToLowerInvariant();
        var days = Math.Clamp(I(a, "days") ?? 45, 1, 400);
        var since = DateTime.UtcNow.AddDays(-days);
        var q = VnSearch.FoldText(S(a, "query"));
        Guid? emp = G(a, "employee_id");
        var names = (await EmployeesAsync(c, ct)).ToDictionary(e => e.Id, e => e.Name);
        string N(Guid? id) => id is Guid g && names.TryGetValue(g, out var n) ? n : "";

        switch (kind)
        {
            case "penalty":
            {
                var rows = await db.PenaltyTickets.AsNoTracking()
                    .Where(t => t.StoreId == c.StoreId && t.CreatedAt >= since && (emp == null || t.EmployeeId == emp))
                    .OrderByDescending(t => t.CreatedAt).Take(60)
                    .Select(t => new { t.Id, t.TicketCode, t.EmployeeId, t.Amount, t.Type, t.Status, t.ViolationDate, t.Description })
                    .ToListAsync(ct);
                return new
                {
                    ket_qua = rows.Where(r => q.Length == 0 || VnSearch.Fold(r.TicketCode + " " + r.Description + " " + N(r.EmployeeId)).Contains(q))
                        .Take(10)
                        .Select(r => new { id = r.Id, ma = r.TicketCode, nhan_vien = N(r.EmployeeId), so_tien = r.Amount, loai = r.Type.ToString(), trang_thai = r.Status.ToString(), ngay = r.ViolationDate.ToString("yyyy-MM-dd"), noi_dung = r.Description }),
                };
            }
            case "reward":
            {
                // Phiếu thưởng không có StoreId — giới hạn theo nhân viên của cửa hàng.
                var storeEmp = await db.Employees.AsNoTracking().Where(e => e.StoreId == c.StoreId).Select(e => e.Id).ToListAsync(ct);
                var rows = await db.PaymentTransactions.AsNoTracking()
                    .Where(t => t.EmployeeId != null && storeEmp.Contains(t.EmployeeId.Value)
                                && t.Type == "Bonus" && t.CreatedAt >= since && (emp == null || t.EmployeeId == emp))
                    .OrderByDescending(t => t.CreatedAt).Take(60)
                    .Select(t => new { t.Id, t.EmployeeId, t.Amount, t.TransactionDate, t.Description, t.Status })
                    .ToListAsync(ct);
                return new
                {
                    ket_qua = rows.Where(r => q.Length == 0 || VnSearch.Fold(r.Description + " " + N(r.EmployeeId)).Contains(q))
                        .Take(10)
                        .Select(r => new { id = r.Id, nhan_vien = N(r.EmployeeId), so_tien = r.Amount, ngay = r.TransactionDate.ToString("yyyy-MM-dd"), ly_do = r.Description, trang_thai = r.Status.ToString() }),
                };
            }
            case "cash":
            {
                var rows = await db.CashTransactions.AsNoTracking()
                    .Where(t => t.StoreId == c.StoreId && t.Deleted == null && t.IsActive && t.TransactionDate >= since)
                    .OrderByDescending(t => t.TransactionDate).Take(150)
                    .Select(t => new { t.Id, t.TransactionCode, t.Type, t.Amount, t.TransactionDate, t.Description, t.SourceType })
                    .ToListAsync(ct);
                return new
                {
                    ket_qua = rows.Where(r => q.Length == 0 || VnSearch.Fold(r.TransactionCode + " " + r.Description).Contains(q))
                        .Take(10)
                        .Select(r => new
                        {
                            id = r.Id, ma = r.TransactionCode, loai = r.Type == CashTransactionType.Income ? "thu" : "chi", so_tien = r.Amount,
                            ngay = r.TransactionDate.AddHours(7).ToString("yyyy-MM-dd"), noi_dung = r.Description,
                            sua_duoc = !ZKTecoADMS.Application.Services.CashSources.IsLinked(r.SourceType),
                        }),
                };
            }
            default:
                return new { error = "kind phải là penalty | reward | cash" };
        }
    }

    async Task<Emp> ResolveEmployeeAsync(Ctx c, Guid? id, bool allowSelf, CancellationToken ct)
    {
        var all = await EmployeesAsync(c, ct);
        if (id is Guid g)
        {
            var e = all.FirstOrDefault(x => x.Id == g) ?? throw new ActionError("Không tìm thấy nhân viên — dùng find_employees để lấy đúng id.");
            if (!IsManager(c) && e.UserId != c.UserId) throw new ActionError("Chỉ quản lý mới tạo phiếu cho người khác.");
            return e;
        }
        if (!allowSelf) throw new ActionError("Thiếu nhân viên — hỏi người dùng là ai.");
        return all.FirstOrDefault(x => x.UserId == c.UserId) ?? throw new ActionError("Tài khoản chưa gắn hồ sơ nhân viên.");
    }

    // ─── Dựng từng loại phiếu ──────────────────────────────────────

    Pending New(Ctx c, string kind, string title, List<Line> lines, string method, string path, object? body, string? open,
        List<string>? warnings = null) =>
        new(Guid.NewGuid().ToString("N"), c.UserId, c.StoreId, kind, title, lines, method, path,
            body == null ? null : JsonSerializer.Serialize(body, Json), open, warnings ?? []);

    async Task<Pending> AdvanceAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var e = await ResolveEmployeeAsync(c, G(a, "employee_id"), true, ct);
        var amount = Money(a, "amount");
        var now = AiAssistantVnTime.NowVn();
        var month = I(a, "month");
        var year = month is int m && m < now.Month - 6 ? now.Year + 1 : now.Year;
        var inst = Math.Clamp(I(a, "installments") ?? 1, 1, 24);
        var self = e.UserId == c.UserId;
        return New(c, "advance", "Yêu cầu ứng lương",
        [
            new("Nhân viên", e.Name), new("Số tiền", Vnd(amount)),
            new("Lý do", S(a, "reason") ?? "—"),
            new("Trừ lương", (month is int mm ? $"tháng {mm}/{year}" : "tháng này") + (inst > 1 ? $", trừ dần {inst} kỳ" : "")),
        ], "POST", "/api/AdvanceRequests", new
        {
            employeeId = self ? (Guid?)null : e.Id,
            amount, reason = S(a, "reason"),
            forMonth = month, forYear = month == null ? (int?)null : year,
            installmentCount = inst > 1 ? inst : (int?)null,
        }, "AdvanceRequests");
    }

    static readonly Dictionary<string, string> PenaltyLabels = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Late"] = "Đi trễ", ["EarlyLeave"] = "Về sớm", ["ForgotCheck"] = "Quên chấm công",
        ["UnauthorizedLeave"] = "Nghỉ không phép", ["Violation"] = "Vi phạm", ["Repeat"] = "Tái phạm",
    };

    static string PenaltyType(string? t) => t != null && PenaltyLabels.ContainsKey(t) ? PenaltyLabels.Keys.First(k => k.Equals(t, StringComparison.OrdinalIgnoreCase)) : "Violation";

    async Task<Pending> PenaltyAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var e = await ResolveEmployeeAsync(c, G(a, "employee_id"), false, ct);
        var amount = Money(a, "amount");
        var date = D(a, "date") ?? AiAssistantVnTime.NowVn().Date;
        var type = PenaltyType(S(a, "type"));
        return New(c, "penalty", "Phiếu phạt",
        [
            new("Nhân viên", e.Name), new("Số tiền", Vnd(amount)), new("Loại", PenaltyLabels[type]),
            new("Ngày vi phạm", date.ToString("dd/MM/yyyy")), new("Nội dung", S(a, "description") ?? "—"),
        ], "POST", "/api/PenaltyTickets", new
        {
            employeeId = e.Id, type, amount, violationDate = date.ToString("yyyy-MM-dd"),
            minutesLateOrEarly = I(a, "minutes"), description = S(a, "description"),
        }, "PenaltyTickets");
    }

    async Task<Pending> UpdatePenaltyAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var id = G(a, "record_id") ?? throw new ActionError("Thiếu id phiếu — dùng find_records kind=penalty.");
        var t = await db.PenaltyTickets.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id && x.StoreId == c.StoreId, ct)
                ?? throw new ActionError("Không tìm thấy phiếu phạt.");
        var amount = a.ContainsKey("amount") ? Money(a, "amount") : (decimal?)null;
        var type = S(a, "type") is { } ty ? PenaltyType(ty) : null;
        var desc = S(a, "description");
        var lines = new List<Line> { new("Phiếu", t.TicketCode) };
        if (amount != null) lines.Add(new("Số tiền", $"{Vnd(t.Amount)} → {Vnd(amount.Value)}"));
        if (type != null) lines.Add(new("Loại", PenaltyLabels[type]));
        if (desc != null) lines.Add(new("Nội dung", desc));
        if (lines.Count == 1) throw new ActionError("Chưa có nội dung cần sửa.");
        return New(c, "update_penalty", "Sửa phiếu phạt", lines, "PUT", $"/api/PenaltyTickets/{id}",
            new { type, amount, description = desc }, "PenaltyTickets");
    }

    async Task<Pending> RewardAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var e = await ResolveEmployeeAsync(c, G(a, "employee_id"), false, ct);
        var amount = Money(a, "amount");
        var date = D(a, "date") ?? AiAssistantVnTime.NowVn().Date;
        var month = I(a, "month") ?? date.Month;
        return New(c, "reward", "Phiếu thưởng",
        [
            new("Nhân viên", e.Name), new("Số tiền", Vnd(amount)), new("Lý do", S(a, "description") ?? "—"),
            new("Ngày", date.ToString("dd/MM/yyyy")), new("Tính vào lương", $"tháng {month}/{date.Year}"),
        ], "POST", "/api/Transactions", new
        {
            employeeId = e.Id, type = "Bonus", amount, transactionDate = date.ToString("yyyy-MM-dd"),
            description = S(a, "description") ?? "Thưởng", forMonth = month, forYear = date.Year,
        }, "BonusPenalty");
    }

    async Task<Pending> UpdateRewardAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var id = G(a, "record_id") ?? throw new ActionError("Thiếu id phiếu — dùng find_records kind=reward.");
        var t = await db.PaymentTransactions.AsNoTracking().FirstOrDefaultAsync(x => x.Id == id && x.Type == "Bonus", ct)
                ?? throw new ActionError("Không tìm thấy phiếu thưởng.");
        if (t.EmployeeId is not Guid te || !await db.Employees.AnyAsync(e => e.Id == te && e.StoreId == c.StoreId, ct))
            throw new ActionError("Không tìm thấy phiếu thưởng.");
        var amount = a.ContainsKey("amount") ? Money(a, "amount") : (decimal?)null;
        var desc = S(a, "description");
        var date = D(a, "date");
        var lines = new List<Line> { new("Phiếu thưởng", $"{Vnd(t.Amount)} · {t.TransactionDate:dd/MM/yyyy}") };
        if (amount != null) lines.Add(new("Số tiền mới", Vnd(amount.Value)));
        if (desc != null) lines.Add(new("Lý do mới", desc));
        if (date != null) lines.Add(new("Ngày mới", date.Value.ToString("dd/MM/yyyy")));
        if (lines.Count == 1) throw new ActionError("Chưa có nội dung cần sửa.");
        return New(c, "update_reward", "Sửa phiếu thưởng", lines, "PUT", $"/api/Transactions/{id}",
            new { amount, description = desc, transactionDate = date?.ToString("yyyy-MM-dd") }, "BonusPenalty");
    }

    static CashTransactionType? Direction(string? d) => (d ?? "").Trim().ToLowerInvariant() switch
    {
        "income" or "thu" or "in" => CashTransactionType.Income,
        "expense" or "chi" or "out" => CashTransactionType.Expense,
        _ => null,
    };

    static PaymentMethodType Method(string? m) => (m ?? "").Trim().ToLowerInvariant() switch
    {
        "bank" or "transfer" or "chuyển khoản" or "ck" => PaymentMethodType.BankTransfer,
        "card" or "thẻ" => PaymentMethodType.Card,
        _ => PaymentMethodType.Cash,
    };

    async Task<(Guid Id, string Name)> PickCategoryAsync(Ctx c, CashTransactionType type, string? name, CancellationToken ct)
    {
        var cats = (await CategoriesAsync(c, ct)).Where(x => x.Type == type).ToList();
        var q = VnSearch.FoldText(name);
        if (q.Length > 0)
        {
            var hit = cats.Select(x => (x, s: Score(VnSearch.Fold(x.Name), q))).Where(x => x.s > 0).OrderByDescending(x => x.s).FirstOrDefault();
            if (hit.s > 0) return (hit.x.Id, hit.x.Name);
        }
        // Danh mục hệ thống tự sinh (bán hàng, trả hàng, nhập hàng, cọc, thu nợ, lương…) không dùng cho phiếu lập tay.
        string[] system = ["ban hang", "tra hang", "nhap hang", "coc", "thu no", "tra ncc", "luong", "hop dong", "cong tac"];
        var general = cats.Where(x => !system.Any(VnSearch.Fold(x.Name).Contains)).ToList();
        var other = general.FirstOrDefault(x => VnSearch.Fold(x.Name).Contains("khac"));
        if (other.Id != Guid.Empty) return (other.Id, other.Name);
        if (general.Count > 0) return (general[0].Id, general[0].Name);
        // Chưa có danh mục chung → tạo «Thu khác» / «Chi khác» khi người dùng xác nhận.
        return (Guid.Empty, type == CashTransactionType.Income ? "Thu khác" : "Chi khác");
    }

    static DateTime VnDateToUtc(DateTime vnDate) =>
        vnDate.Date == AiAssistantVnTime.NowVn().Date ? DateTime.UtcNow : DateTime.SpecifyKind(vnDate.Date.AddHours(5), DateTimeKind.Utc);

    async Task<Pending> CashAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var type = Direction(S(a, "direction")) ?? throw new ActionError("direction phải là income hoặc expense.");
        var amount = Money(a, "amount");
        var cat = await PickCategoryAsync(c, type, S(a, "category"), ct);
        var method = Method(S(a, "method"));
        var date = D(a, "date") ?? AiAssistantVnTime.NowVn().Date;
        var desc = S(a, "description") ?? "";
        return New(c, "cash", type == CashTransactionType.Income ? "Phiếu thu" : "Phiếu chi",
        [
            new("Số tiền", Vnd(amount)), new("Nội dung", desc), new("Danh mục", cat.Name),
            new("Hình thức", method == PaymentMethodType.BankTransfer ? "Chuyển khoản" : method == PaymentMethodType.Card ? "Thẻ" : "Tiền mặt"),
            new("Ngày", date.ToString("dd/MM/yyyy")),
            .. S(a, "contact") is { } who ? new[] { new Line(type == CashTransactionType.Income ? "Người nộp" : "Người nhận", who) } : [],
        ], "POST", "/api/CashTransactions", new
        {
            type = (int)type, categoryId = cat.Id, amount, transactionDate = VnDateToUtc(date), description = desc,
            paymentMethod = (int)method, contactName = S(a, "contact"), isPaid = true,
        }, "CashTransaction");
    }

    async Task<Pending> UpdateCashAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var id = G(a, "record_id") ?? throw new ActionError("Thiếu id phiếu — dùng find_records kind=cash.");
        var t = await db.CashTransactions.AsNoTracking()
                    .FirstOrDefaultAsync(x => x.Id == id && x.StoreId == c.StoreId && x.Deleted == null, ct)
                ?? throw new ActionError("Không tìm thấy phiếu thu / chi.");
        if (ZKTecoADMS.Application.Services.CashSources.IsLinked(t.SourceType))
            throw new ActionError("Phiếu này tự sinh từ chứng từ gốc (bán hàng / lương…) — sửa ở chứng từ gốc, không sửa phiếu.");
        var amount = a.ContainsKey("amount") ? Money(a, "amount") : t.Amount;
        var desc = S(a, "description") ?? t.Description;
        var catId = t.CategoryId;
        string? catName = null;
        if (S(a, "category") is { } cn) (catId, catName) = await PickCategoryAsync(c, t.Type, cn, ct);
        var date = D(a, "date");
        var lines = new List<Line> { new("Phiếu", t.TransactionCode) };
        if (amount != t.Amount) lines.Add(new("Số tiền", $"{Vnd(t.Amount)} → {Vnd(amount)}"));
        if (desc != t.Description) lines.Add(new("Nội dung", desc));
        if (catName != null) lines.Add(new("Danh mục", catName));
        if (date != null) lines.Add(new("Ngày", date.Value.ToString("dd/MM/yyyy")));
        if (lines.Count == 1) throw new ActionError("Chưa có nội dung cần sửa.");
        return New(c, "update_cash", t.Type == CashTransactionType.Income ? "Sửa phiếu thu" : "Sửa phiếu chi", lines,
            "PUT", $"/api/CashTransactions/{id}", new
            {
                type = (int)t.Type, categoryId = catId, amount,
                transactionDate = date is DateTime d ? VnDateToUtc(d) : t.TransactionDate,
                description = desc, paymentMethod = (int)t.PaymentMethod, bankAccountId = t.BankAccountId,
                contactName = t.ContactName, contactPhone = t.ContactPhone, paymentReference = t.PaymentReference,
                receiptImageUrl = t.ReceiptImageUrl, isPaid = t.IsPaid, internalNote = t.InternalNote, tags = t.Tags,
            }, "CashTransaction");
    }

    async Task<Pending> OvertimeAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var e = await ResolveEmployeeAsync(c, G(a, "employee_id"), true, ct);
        var date = D(a, "date") ?? throw new ActionError("Thiếu ngày.");
        var start = T(a, "start") ?? throw new ActionError("Giờ bắt đầu không hợp lệ (HH:mm).");
        var end = T(a, "end") ?? throw new ActionError("Giờ kết thúc không hợp lệ (HH:mm).");
        var type = S(a, "type") is { } ty && Enum.TryParse<OvertimeType>(ty, true, out var ot)
            ? ot
            : date.DayOfWeek is DayOfWeek.Saturday or DayOfWeek.Sunday ? OvertimeType.Weekend : OvertimeType.Weekday;
        var hours = (end - start).TotalHours;
        if (hours <= 0) hours += 24;
        var self = e.UserId == c.UserId;
        if (!self && e.UserId == null) throw new ActionError($"{e.Name} chưa có tài khoản đăng nhập — đăng ký tăng ca trên màn Tăng ca.");
        return New(c, "overtime", "Đăng ký tăng ca",
        [
            new("Nhân viên", e.Name), new("Ngày", date.ToString("dd/MM/yyyy")),
            new("Giờ", $"{start:hh\\:mm} – {end:hh\\:mm} ({hours:0.#} giờ)"),
            new("Loại", type switch { OvertimeType.Weekend => "Cuối tuần", OvertimeType.Holiday => "Ngày lễ", OvertimeType.Night => "Ban đêm", _ => "Ngày thường" }),
            new("Lý do", S(a, "reason") ?? "—"),
        ], "POST", "/api/Overtimes", new
        {
            employeeUserId = self ? null : e.UserId, type = (int)type, date = date.ToString("yyyy-MM-dd"),
            startTime = start.ToString(@"hh\:mm\:ss"), endTime = end.ToString(@"hh\:mm\:ss"),
            reason = S(a, "reason") ?? "Tăng ca",
        }, "Overtime");
    }

    async Task<Pending> AttendanceFixAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var e = await ResolveEmployeeAsync(c, G(a, "employee_id"), true, ct);
        var date = D(a, "date") ?? throw new ActionError("Thiếu ngày.");
        var time = T(a, "time") ?? throw new ActionError("Giờ không hợp lệ (HH:mm).");
        var punch = (S(a, "punch") ?? "").ToLowerInvariant() switch { "in" => "CheckIn", "out" => "CheckOut", _ => null };
        var self = e.UserId == c.UserId;
        return New(c, "attendance_fix", "Bổ sung chấm công",
        [
            new("Nhân viên", e.Name), new("Ngày", date.ToString("dd/MM/yyyy")), new("Giờ", time.ToString(@"hh\:mm")),
            .. punch != null ? new[] { new Line("Loại", punch == "CheckIn" ? "Giờ vào" : "Giờ ra") } : [],
            new("Lý do", S(a, "reason") ?? "Quên chấm công"),
        ], "POST", "/api/AttendanceCorrections", new
        {
            employeeUserId = self ? null : e.UserId, employeeCode = self ? null : e.Code, employeeName = self ? null : e.Name,
            action = (int)CorrectionAction.Add, newDate = date.ToString("yyyy-MM-dd"), newTime = time.ToString(@"hh\:mm\:ss"),
            newType = punch, reason = S(a, "reason") ?? "Quên chấm công",
        }, "AttendanceCorrection");
    }

    async Task<Pending> SaleAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        if (a.GetValueOrDefault("items") is not JsonElement items || items.ValueKind != JsonValueKind.Array || items.GetArrayLength() == 0)
            throw new ActionError("Chưa có mặt hàng.");
        var req = items.EnumerateArray().Select(i => new
        {
            Id = i.TryGetProperty("product_id", out var p) && Guid.TryParse(p.GetString(), out var g) ? g : Guid.Empty,
            Qty = i.TryGetProperty("qty", out var q) && q.TryGetDecimal(out var qd) ? qd : 1m,
            Price = i.TryGetProperty("price", out var pr) && pr.TryGetDecimal(out var pd) ? pd : (decimal?)null,
        }).ToList();
        var ids = req.Select(r => r.Id).ToList();
        var products = await db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == c.StoreId && p.Deleted == null && ids.Contains(p.Id))
            .Select(p => new { p.Id, p.Name, p.BasePrice, p.BaseUnitName, p.OnHandQty, p.ProductType })
            .ToDictionaryAsync(p => p.Id, ct);
        var lines = new List<Line>();
        var warnings = new List<string>();
        var body = new List<object>();
        decimal subtotal = 0;
        foreach (var r in req)
        {
            if (!products.TryGetValue(r.Id, out var p)) throw new ActionError("Có mặt hàng không tìm thấy — dùng find_products lấy đúng id.");
            if (r.Qty <= 0) throw new ActionError($"Số lượng {p.Name} không hợp lệ.");
            var price = r.Price ?? p.BasePrice;
            subtotal += price * r.Qty;
            lines.Add(new($"{r.Qty:0.##} {p.BaseUnitName} {p.Name}", Vnd(price * r.Qty)));
            if (p.ProductType == PosProductType.Goods && p.OnHandQty < r.Qty) warnings.Add($"{p.Name}: tồn {p.OnHandQty:0.##}, bán {r.Qty:0.##}");
            body.Add(new { productId = p.Id, qty = r.Qty, unitPrice = r.Price });
        }
        var discount = a.ContainsKey("discount") ? Money(a, "discount") : 0m;
        var total = Math.Max(0, subtotal - discount);

        Guid? customerId = G(a, "customer_id");
        string? customerName = S(a, "customer_name");
        if (customerId is Guid cid)
        {
            customerName = await db.PosCustomers.AsNoTracking().Where(x => x.Id == cid && x.StoreId == c.StoreId)
                .Select(x => x.Name).FirstOrDefaultAsync(ct) ?? throw new ActionError("Không tìm thấy khách — dùng find_customers.");
        }
        var paidRaw = (S(a, "paid") ?? "full").Trim().ToLowerInvariant();
        var paid = paidRaw is "full" or "đủ" or "" ? total : paidRaw is "none" or "nợ" or "0" ? 0m : ParseMoney(paidRaw) ?? total;
        paid = Math.Min(paid, total);
        if (paid < total && customerId == null) throw new ActionError("Đơn ghi nợ cần khách có trong danh bạ (find_customers).");
        var method = Method(S(a, "method"));
        var methodLabel = method == PaymentMethodType.BankTransfer ? "Chuyển khoản" : method == PaymentMethodType.Card ? "Thẻ" : "Tiền mặt";

        if (discount > 0) lines.Add(new("Giảm giá", "-" + Vnd(discount)));
        lines.Add(new("Tổng cộng", Vnd(total)));
        lines.Add(new("Khách", customerName ?? "Khách lẻ"));
        lines.Add(new("Thanh toán", paid >= total ? $"{methodLabel} — trả đủ" : $"{Vnd(paid)} ({methodLabel}), nợ {Vnd(total - paid)}"));
        return New(c, "sale", "Hóa đơn bán hàng", lines, "POST", "/api/pos/sales", new
        {
            lines = body, discount, paidAmount = paid, paymentMethod = methodLabel,
            customerName, customerId, note = S(a, "note") ?? "Tạo bằng Trợ lý ảo", complete = true,
            clientRequestId = "ai-" + Guid.NewGuid().ToString("N"),
        }, "PosSaleOrders", warnings);
    }

    // ─── Hàng hóa / kho / khuyến mãi ───────────────────────────────

    async Task<object> FindSuppliersAsync(Ctx c, string? query, CancellationToken ct)
    {
        var q = VnSearch.FoldText(query);
        if (q.Length == 0) return new { error = "Thiếu tên nhà cung cấp" };
        var rows = await db.PosSuppliers.AsNoTracking()
            .Where(x => x.StoreId == c.StoreId && x.Deleted == null)
            .Select(x => new { x.Id, x.Name, x.Phone })
            .ToListAsync(ct);
        var list = rows.Select(x => (x, s: Score(VnSearch.Fold(x.Name), q))).Where(t => t.s > 0)
            .OrderByDescending(t => t.s).Take(8)
            .Select(t => new { id = t.x.Id, ten = t.x.Name, sdt = t.x.Phone }).ToList();
        return list.Count == 0 ? new { ket_qua = "Không có nhà cung cấp khớp — có thể bỏ trống supplier_id" } : new { ket_qua = list };
    }

    async Task<object> FindOrdersAsync(Ctx c, string? query, CancellationToken ct)
    {
        var raw = (query ?? "").Trim();
        var q = VnSearch.FoldText(raw);
        var since = DateTime.UtcNow.AddDays(-60);
        var rows = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.StoreId == c.StoreId && o.Deleted == null && o.Status == PosSaleOrderStatus.Completed
                        && (o.SaleDate ?? o.CreatedAt) >= since)
            .OrderByDescending(o => o.SaleDate ?? o.CreatedAt).Take(400)
            .Select(o => new { o.Id, o.OrderNo, o.CustomerName, o.Total, At = o.SaleDate ?? o.CreatedAt,
                Lines = o.Lines.Select(l => new { l.ProductId, l.ProductName, l.Qty }).ToList() })
            .ToListAsync(ct);
        var list = rows
            .Where(o => q.Length == 0 || o.OrderNo.Contains(raw, StringComparison.OrdinalIgnoreCase)
                        || VnSearch.Fold(o.CustomerName ?? "").Contains(q))
            .Take(6)
            .Select(o => new
            {
                id = o.Id, ma = o.OrderNo, khach = o.CustomerName ?? "Khách lẻ", tong = o.Total,
                ngay = o.At.AddHours(7).ToString("dd/MM HH:mm"),
                hang = o.Lines.Select(l => new { product_id = l.ProductId, ten = l.ProductName, sl = l.Qty }),
            }).ToList();
        return list.Count == 0 ? new { ket_qua = "Không tìm thấy hóa đơn hoàn thành khớp trong 60 ngày" } : new { ket_qua = list };
    }

    sealed record ItemReq(Guid Id, decimal Qty, decimal? Price);

    static List<ItemReq> Items(Dictionary<string, object?> a, bool required = true)
    {
        if (a.GetValueOrDefault("items") is not JsonElement items || items.ValueKind != JsonValueKind.Array || items.GetArrayLength() == 0)
            return required ? throw new ActionError("Chưa có mặt hàng.") : [];
        return items.EnumerateArray().Select(i => new ItemReq(
            i.TryGetProperty("product_id", out var p) && Guid.TryParse(p.GetString(), out var g) ? g : Guid.Empty,
            i.TryGetProperty("qty", out var q) && q.TryGetDecimal(out var qd) ? qd : 1m,
            i.TryGetProperty("price", out var pr) && pr.TryGetDecimal(out var pd) ? pd : null)).ToList();
    }

    sealed record Prod(Guid Id, string Name, string Unit, decimal Price, decimal Cost, decimal OnHand, bool Goods);

    async Task<Dictionary<Guid, Prod>> ProductsAsync(Ctx c, IEnumerable<Guid> ids, CancellationToken ct)
    {
        var list = ids.Distinct().ToList();
        var map = await db.PosProducts.AsNoTracking()
            .Where(p => p.StoreId == c.StoreId && p.Deleted == null && list.Contains(p.Id))
            .Select(p => new Prod(p.Id, p.Name, p.BaseUnitName, p.BasePrice, p.CostPrice, p.OnHandQty, p.ProductType == PosProductType.Goods))
            .ToDictionaryAsync(p => p.Id, ct);
        if (list.Any(id => !map.ContainsKey(id)))
            throw new ActionError("Có mặt hàng không tìm thấy — dùng find_products lấy đúng id.");
        return map;
    }

    Pending ProductProposal(Ctx c, Dictionary<string, object?> a)
    {
        var name = S(a, "name") ?? throw new ActionError("Thiếu tên hàng.");
        var price = ParseMoney(S(a, "price")) ?? throw new ActionError("Giá bán không hợp lệ.");
        var cost = ParseMoney(S(a, "cost")) ?? 0;
        var service = (S(a, "type") ?? "").ToLowerInvariant().StartsWith("serv") || (S(a, "type") ?? "").Contains("dịch vụ");
        var stock = service ? 0 : ParseMoney(S(a, "stock")) ?? 0;
        var unit = S(a, "unit") ?? (service ? "Lần" : "Cái");
        return New(c, "product", service ? "Dịch vụ mới" : "Hàng hóa mới",
        [
            new("Tên", name), new("Giá bán", Vnd(price)),
            .. cost > 0 ? new[] { new Line("Giá vốn", Vnd(cost)) } : [],
            new("Đơn vị", unit),
            .. S(a, "category") is { } cat ? new[] { new Line("Nhóm hàng", cat) } : [],
            .. stock > 0 ? new[] { new Line("Tồn ban đầu", $"{stock:0.##} {unit}") } : [],
            .. S(a, "barcode") is { } bc ? new[] { new Line("Mã vạch", bc) } : [],
        ], "POST", "/api/pos/products/quick", new
        {
            name, basePrice = price, costPrice = cost, onHandQty = stock, baseUnitName = unit,
            categoryName = S(a, "category"), barcode = S(a, "barcode"),
            productType = service ? (int)PosProductType.Service : (int)PosProductType.Goods,
        }, "PosProducts");
    }

    (decimal paid, string label) PaidOf(Dictionary<string, object?> a, decimal total)
    {
        var raw = (S(a, "paid") ?? "full").Trim().ToLowerInvariant();
        var paid = raw is "full" or "đủ" or "" ? total : raw is "none" or "nợ" or "0" ? 0m : ParseMoney(raw) ?? total;
        paid = Math.Min(paid, total);
        var m = Method(S(a, "method"));
        var ml = m == PaymentMethodType.BankTransfer ? "Chuyển khoản" : "Tiền mặt";
        return (paid, paid >= total ? $"Trả đủ — {ml}" : paid <= 0 ? "Ghi nợ nhà cung cấp" : $"Trả {Vnd(paid)} ({ml}), nợ {Vnd(total - paid)}");
    }

    async Task<string?> SupplierNameAsync(Ctx c, Guid? id, CancellationToken ct) => id is Guid sid
        ? await db.PosSuppliers.AsNoTracking().Where(x => x.Id == sid && x.StoreId == c.StoreId).Select(x => x.Name).FirstOrDefaultAsync(ct)
          ?? throw new ActionError("Không tìm thấy nhà cung cấp — dùng find_suppliers.")
        : null;

    async Task<Pending> PurchaseReceiptAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var items = Items(a);
        var prods = await ProductsAsync(c, items.Select(i => i.Id), ct);
        var supplierId = G(a, "supplier_id");
        var supplier = await SupplierNameAsync(c, supplierId, ct);
        var lines = new List<Line>();
        var body = new List<object>();
        decimal total = 0;
        foreach (var i in items)
        {
            var pr = prods[i.Id];
            if (i.Qty <= 0) throw new ActionError($"Số lượng {pr.Name} không hợp lệ.");
            var cost = i.Price ?? pr.Cost;
            total += cost * i.Qty;
            lines.Add(new($"{i.Qty:0.##} {pr.Unit} {pr.Name}", $"{Vnd(cost)} × {i.Qty:0.##} = {Vnd(cost * i.Qty)}"));
            body.Add(new { productId = pr.Id, qty = i.Qty, costPrice = cost, discountAmount = 0, vatRate = 0, vatIncluded = true, vatExempt = false, unitName = pr.Unit });
        }
        var (paid, paidLabel) = PaidOf(a, total);
        lines.Add(new("Tổng tiền nhập", Vnd(total)));
        lines.Add(new("Nhà cung cấp", supplier ?? "—"));
        lines.Add(new("Thanh toán", paidLabel));
        var warnings = new List<string>();
        if (paid < total && supplierId == null) warnings.Add("Ghi nợ nhưng chưa chọn nhà cung cấp.");
        return New(c, "purchase_receipt", "Phiếu nhập kho", lines, "POST", "/api/pos/purchase/receipts", new
        {
            supplierId, note = S(a, "note") ?? "Tạo bằng Trợ lý ảo", discountAmount = 0, discountIsPercent = false, discountInput = 0,
            paidAmount = paid, complete = true,
            paymentMethod = Method(S(a, "method")) == PaymentMethodType.BankTransfer ? "Chuyển khoản" : "Tiền mặt",
            lines = body,
        }, "PosPurchaseReceipts", warnings);
    }

    async Task<Pending> StockCountAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var items = Items(a);
        var prods = await ProductsAsync(c, items.Select(i => i.Id), ct);
        var lines = new List<Line>();
        var qty = new Dictionary<Guid, decimal>();
        foreach (var i in items)
        {
            var pr = prods[i.Id];
            if (i.Qty < 0) throw new ActionError($"Số đếm {pr.Name} không hợp lệ.");
            qty[pr.Id] = i.Qty;
            var diff = i.Qty - pr.OnHand;
            lines.Add(new(pr.Name, $"máy {pr.OnHand:0.##} → đếm {i.Qty:0.##} ({(diff >= 0 ? "+" : "")}{diff:0.##})"));
        }
        var note = S(a, "note") ?? "Kiểm kho bằng Trợ lý ảo";
        return New(c, "stock_count", "Phiếu kiểm kho", lines, "POST", "/api/pos/stock/counts", null, "PosStockCounts")
            with
            {
                Steps =
                [
                    new("POST", "/api/pos/stock/counts", JsonSerializer.Serialize(new { name = note, note, seedAllProducts = false }, Json)),
                    new("POST", "/api/pos/stock/counts/{id}/lines/add", JsonSerializer.Serialize(qty.Keys.Select(id => new { productId = id }), Json)),
                    new("PUT", "/api/pos/stock/counts/{id}/lines", null, "counted"),
                    new("POST", "/api/pos/stock/counts/{id}/complete", null),
                ],
                LineQty = qty,
            };
    }

    async Task<Pending> StockIssueAsync(Ctx c, Dictionary<string, object?> a, string kind, CancellationToken ct)
    {
        var items = Items(a);
        var prods = await ProductsAsync(c, items.Select(i => i.Id), ct);
        var damage = kind == "damage";
        var lines = new List<Line>();
        var warnings = new List<string>();
        var qty = new Dictionary<Guid, decimal>();
        decimal value = 0;
        foreach (var i in items)
        {
            var pr = prods[i.Id];
            if (i.Qty <= 0) throw new ActionError($"Số lượng {pr.Name} không hợp lệ.");
            qty[pr.Id] = qty.GetValueOrDefault(pr.Id) + i.Qty;
            value += pr.Cost * i.Qty;
            lines.Add(new($"{i.Qty:0.##} {pr.Unit} {pr.Name}", Vnd(pr.Cost * i.Qty)));
            if (pr.Goods && pr.OnHand < i.Qty) warnings.Add($"{pr.Name}: tồn {pr.OnHand:0.##}, xuất {i.Qty:0.##}");
        }
        lines.Add(new("Giá trị (giá vốn)", Vnd(value)));
        var reason = S(a, "reason") ?? (damage ? "Hàng hỏng" : "Dùng nội bộ");
        lines.Add(new(damage ? "Lý do" : "Mục đích", reason));
        if (!damage && S(a, "recipient") is { } who) lines.Add(new("Người nhận", who));
        var basePath = $"/api/pos/stock/{kind}";
        return New(c, damage ? "damage_issue" : "internal_use", damage ? "Phiếu xuất hủy" : "Phiếu xuất dùng nội bộ",
                lines, "POST", basePath, null, damage ? "PosDamageIssues" : "PosInternalUseIssues", warnings)
            with
            {
                Steps =
                [
                    new("POST", basePath, null),
                    new("POST", basePath + "/{id}/lines/add", JsonSerializer.Serialize(qty.Keys.Select(id => new { productId = id }), Json)),
                    new("PUT", basePath + "/{id}/lines", null, "qty"),
                    new("PUT", basePath + "/{id}", JsonSerializer.Serialize(new { note = reason, recipientName = S(a, "recipient") }, Json)),
                    new("POST", basePath + "/{id}/complete", null),
                ],
                LineQty = qty,
            };
    }

    async Task<Pending> CustomerReturnAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var orderId = G(a, "order_id") ?? throw new ActionError("Thiếu hóa đơn — dùng find_orders.");
        var order = await db.PosSaleOrders.AsNoTracking()
            .Where(o => o.Id == orderId && o.StoreId == c.StoreId && o.Deleted == null)
            .Select(o => new { o.OrderNo, o.Status, o.CustomerName, Lines = o.Lines.Select(l => new { l.ProductId, l.ProductName, l.Qty, l.UnitPrice, l.LineTotal }).ToList() })
            .FirstOrDefaultAsync(ct) ?? throw new ActionError("Không tìm thấy hóa đơn.");
        if (order.Status != PosSaleOrderStatus.Completed) throw new ActionError("Chỉ trả hàng hóa đơn đã hoàn thành.");
        var items = Items(a, required: false);
        var picks = items.Count == 0
            ? order.Lines.GroupBy(l => l.ProductId).Select(g => new ItemReq(g.Key, g.Sum(x => x.Qty), null)).ToList()
            : items;
        var lines = new List<Line> { new("Hóa đơn", $"{order.OrderNo} · {order.CustomerName ?? "Khách lẻ"}") };
        decimal refund = 0;
        foreach (var i in picks)
        {
            var ol = order.Lines.Where(l => l.ProductId == i.Id).ToList();
            if (ol.Count == 0) throw new ActionError("Có mặt hàng không thuộc hóa đơn này.");
            var sold = ol.Sum(x => x.Qty);
            if (i.Qty <= 0 || i.Qty > sold) throw new ActionError($"{ol[0].ProductName}: trả tối đa {sold:0.##}.");
            var unit = sold > 0 ? ol.Sum(x => x.LineTotal) / sold : ol[0].UnitPrice;
            refund += unit * i.Qty;
            lines.Add(new($"Trả {i.Qty:0.##} {ol[0].ProductName}", Vnd(unit * i.Qty)));
        }
        var method = Method(S(a, "refund_method")) == PaymentMethodType.BankTransfer ? "Chuyển khoản" : "Tiền mặt";
        lines.Add(new("Hoàn tiền (ước tính)", $"{Vnd(refund)} — {method}"));
        return New(c, "customer_return", "Phiếu khách trả hàng", lines, "POST", $"/api/pos/sales/{orderId}/return", new
        {
            lines = picks.Select(i => new { productId = i.Id, qty = i.Qty }),
            note = S(a, "reason") ?? "Trả hàng (Trợ lý ảo)", refundPaymentMethod = method, reason = S(a, "reason"),
        }, "PosSaleReturns");
    }

    async Task<Pending> PurchaseReturnAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var items = Items(a);
        var prods = await ProductsAsync(c, items.Select(i => i.Id), ct);
        var supplierId = G(a, "supplier_id");
        var supplier = await SupplierNameAsync(c, supplierId, ct);
        var lines = new List<Line>();
        var body = new List<object>();
        decimal total = 0;
        foreach (var i in items)
        {
            var pr = prods[i.Id];
            if (i.Qty <= 0) throw new ActionError($"Số lượng {pr.Name} không hợp lệ.");
            var cost = i.Price ?? pr.Cost;
            total += cost * i.Qty;
            lines.Add(new($"Trả {i.Qty:0.##} {pr.Unit} {pr.Name}", Vnd(cost * i.Qty)));
            body.Add(new { productId = pr.Id, qty = i.Qty, costPrice = cost, discountAmount = 0, unitName = pr.Unit });
        }
        var refund = Math.Min(ParseMoney(S(a, "refund")) ?? 0, total);
        lines.Add(new("Giá trị trả", Vnd(total)));
        lines.Add(new("Nhà cung cấp", supplier ?? "—"));
        lines.Add(new("NCC hoàn tiền", refund > 0 ? Vnd(refund) : "Trừ vào công nợ"));
        return New(c, "purchase_return", "Trả hàng nhà cung cấp", lines, "POST", "/api/pos/purchase/returns", new
        {
            supplierId, note = S(a, "note") ?? "Trả hàng NCC (Trợ lý ảo)", discountAmount = 0, refundReceived = refund,
            complete = true, lines = body,
        }, "PosPurchaseReturns");
    }

    Pending VoucherProposal(Ctx c, Dictionary<string, object?> a)
    {
        var percent = (S(a, "kind") ?? "percent").ToLowerInvariant().StartsWith("p");
        var value = ParseMoney(S(a, "value")) ?? throw new ActionError("Thiếu mức giảm.");
        if (percent && (value <= 0 || value > 100)) throw new ActionError("Giảm % phải từ 1 đến 100.");
        var code = (S(a, "code") ?? "").ToUpperInvariant().Replace(" ", "");
        if (code.Length == 0) code = "SB" + Guid.NewGuid().ToString("N")[..6].ToUpperInvariant();
        var from = D(a, "from");
        var to = D(a, "to");
        var minOrder = ParseMoney(S(a, "min_order")) ?? 0;
        var maxDiscount = ParseMoney(S(a, "max_discount"));
        return New(c, "voucher", "Mã giảm giá", [
            new("Mã", code), new("Tên", S(a, "name") ?? code),
            new("Mức giảm", percent ? $"{value:0.##}%" + (maxDiscount is decimal md ? $" (tối đa {Vnd(md)})" : "") : Vnd(value)),
            .. minOrder > 0 ? new[] { new Line("Đơn từ", Vnd(minOrder)) } : [],
            new("Hiệu lực", (from is DateTime f ? f.ToString("dd/MM/yyyy") : "ngay") + " → " + (to is DateTime t ? t.ToString("dd/MM/yyyy") : "không giới hạn")),
            .. I(a, "max_uses") is int mu ? new[] { new Line("Số lượt", $"{mu}") } : [],
        ], "POST", "/api/pos/vouchers", new
        {
            code, name = S(a, "name") ?? code, discountType = percent ? (int)PosVoucherDiscountType.Percent : (int)PosVoucherDiscountType.Fixed,
            discountValue = value, minOrderAmount = minOrder, maxDiscountAmount = maxDiscount,
            validFrom = from?.ToString("yyyy-MM-dd"), validTo = to?.ToString("yyyy-MM-dd"), maxUses = I(a, "max_uses"), isActive = true,
        }, "PosVouchers");
    }

    async Task<Pending> PromotionAsync(Ctx c, Dictionary<string, object?> a, CancellationToken ct)
    {
        var type = (S(a, "type") ?? "").Trim().ToLowerInvariant();
        string[] supported = ["bill_discount", "time_discount", "qty_discount", "buy_x_get_y", "combo_price"];
        if (!supported.Contains(type)) throw new ActionError("type phải là: " + string.Join(", ", supported));
        var name = S(a, "name") ?? throw new ActionError("Thiếu tên chương trình.");
        var cfg = new JsonObject();
        var lines = new List<Line> { new("Tên", name) };
        var percent = ParseMoney(S(a, "percent"));
        var amount = ParseMoney(S(a, "amount"));
        switch (type)
        {
            case "bill_discount":
                if (percent == null && amount == null) throw new ActionError("Thiếu % hoặc số tiền giảm.");
                var minBill = ParseMoney(S(a, "min_bill")) ?? 0;
                cfg["minBill"] = minBill;
                if (percent != null) cfg["billPercent"] = percent; else cfg["billAmount"] = amount;
                if (ParseMoney(S(a, "max_discount")) is decimal mx) cfg["maxDiscount"] = mx;
                lines.Add(new("Ưu đãi", (percent != null ? $"Giảm {percent:0.##}% hóa đơn" : $"Giảm {Vnd(amount!.Value)} hóa đơn")
                                       + (minBill > 0 ? $" từ {Vnd(minBill)}" : "")));
                break;
            case "time_discount":
                if (percent == null && amount == null) throw new ActionError("Thiếu % hoặc số tiền giảm mỗi món.");
                if (percent != null) cfg["percent"] = percent; else cfg["amountPerUnit"] = amount;
                lines.Add(new("Ưu đãi", percent != null ? $"Giảm {percent:0.##}% mỗi món" : $"Giảm {Vnd(amount!.Value)} mỗi món"));
                break;
            case "qty_discount":
                var minQty = ParseMoney(S(a, "min_qty")) ?? throw new ActionError("Thiếu số lượng tối thiểu.");
                if (percent == null) throw new ActionError("Thiếu % giảm.");
                cfg["tiers"] = new JsonArray(new JsonObject { ["minQty"] = minQty, ["percent"] = percent });
                lines.Add(new("Ưu đãi", $"Mua từ {minQty:0.##} giảm {percent:0.##}%"));
                break;
            case "buy_x_get_y":
                var buy = I(a, "buy_qty") ?? 1;
                var get = I(a, "get_qty") ?? 1;
                cfg["buyQty"] = buy;
                cfg["getQty"] = get;
                cfg["giftPercent"] = 100;
                var gift = "cùng loại";
                if (G(a, "gift_product_id") is Guid gid)
                {
                    var gp = (await ProductsAsync(c, [gid], ct))[gid];
                    cfg["giftProductId"] = gid.ToString();
                    cfg["giftProductName"] = gp.Name;
                    gift = gp.Name;
                }
                lines.Add(new("Ưu đãi", $"Mua {buy} tặng {get} ({gift})"));
                break;
            case "combo_price":
                var n = I(a, "combo_qty") ?? throw new ActionError("Thiếu số món combo.");
                var price = ParseMoney(S(a, "combo_price")) ?? throw new ActionError("Thiếu giá combo.");
                cfg["comboQty"] = n;
                cfg["comboPrice"] = price;
                lines.Add(new("Ưu đãi", $"Combo {n} món đồng giá {Vnd(price)}"));
                break;
        }

        // Phạm vi áp dụng.
        var target = new JsonObject { ["scope"] = "all" };
        var scopeLabel = "Mọi hàng";
        var ids = (S(a, "product_ids") ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(x => Guid.TryParse(x, out var g) ? g : Guid.Empty).Where(g => g != Guid.Empty).ToList();
        if (ids.Count > 0)
        {
            var prods = await ProductsAsync(c, ids, ct);
            target["scope"] = "products";
            target["products"] = new JsonArray(prods.Values.Select(pr => (JsonNode)new JsonObject { ["id"] = pr.Id.ToString(), ["name"] = pr.Name }).ToArray());
            scopeLabel = string.Join(", ", prods.Values.Select(pr => pr.Name));
        }
        else if (S(a, "category") is { } catName)
        {
            var cats = await db.PosProductCategories.AsNoTracking().Where(x => x.StoreId == c.StoreId)
                .Select(x => new { x.Id, x.Name }).ToListAsync(ct);
            var qf = VnSearch.FoldText(catName);
            var hit = cats.Select(x => (x, s: Score(VnSearch.Fold(x.Name), qf))).Where(x => x.s > 0).OrderByDescending(x => x.s).FirstOrDefault();
            if (hit.s == 0) throw new ActionError($"Không có nhóm hàng «{catName}».");
            target["scope"] = "categories";
            target["categoryIds"] = new JsonArray(JsonValue.Create(hit.x.Id.ToString()));
            scopeLabel = "Nhóm " + hit.x.Name;
        }
        if (type != "bill_discount") cfg["target"] = target;
        if (type != "bill_discount") lines.Add(new("Áp dụng", scopeLabel));

        int? Minutes(string k) => T(a, k) is TimeSpan ts ? (int)ts.TotalMinutes : null;
        var tf = Minutes("time_from");
        var tt = Minutes("time_to");
        var mask = 0;
        foreach (var d in (S(a, "weekdays") ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            if (int.TryParse(d, out var wd) && wd is >= 2 and <= 8) mask |= 1 << (wd - 2);
        var from = D(a, "from");
        var to = D(a, "to");
        if (tf != null && tt != null) lines.Add(new("Khung giờ", $"{tf / 60:00}:{tf % 60:00} – {tt / 60:00}:{tt % 60:00}"));
        if (mask != 0)
            lines.Add(new("Ngày trong tuần", string.Join(", ", Enumerable.Range(0, 7).Where(i => (mask & (1 << i)) != 0).Select(i => i == 6 ? "CN" : $"T{i + 2}"))));
        lines.Add(new("Thời gian", (from is DateTime f ? f.ToString("dd/MM/yyyy") : "ngay") + " → " + (to is DateTime t2 ? t2.ToString("dd/MM/yyyy") : "không giới hạn")));
        var members = S(a, "members_only") is { } mo && (mo == "true" || mo == "1");
        if (members) lines.Add(new("Đối tượng", "Chỉ khách thành viên"));
        return New(c, "promotion", "Chương trình khuyến mãi", lines, "POST", "/api/pos/promotions", new
        {
            name, type, priority = 0, stackable = false,
            validFrom = from?.ToString("yyyy-MM-dd"), validTo = to?.ToString("yyyy-MM-dd"),
            daysOfWeekMask = mask, timeFromMinutes = tf, timeToMinutes = tt, membersOnly = members,
            configJson = cfg.ToJsonString(), note = "Tạo bằng Trợ lý ảo", isActive = true,
        }, "PosPromotions");
    }

    /// <summary>Phiếu kho nhiều bước: id phiếu từ bước đầu; bước điền dòng ghép lineId theo hàng.</summary>
    async Task<ExecResult> ExecuteStepsAsync(Pending p, HttpContext ctx, CancellationToken ct)
    {
        string? docId = null;
        JsonNode? lastData = null;
        string? docNo = null;
        foreach (var step in p.Steps!)
        {
            var path = step.Path.Replace("{id}", docId ?? "");
            var body = step.Body;
            if (step.LinesFrom != null)
            {
                var lineList = new JsonArray();
                foreach (var l in lastData?["lines"]?.AsArray() ?? [])
                {
                    if (l?["productId"]?.ToString() is not { } pid || !Guid.TryParse(pid, out var g)
                        || p.LineQty?.TryGetValue(g, out var q) != true) continue;
                    var o = new JsonObject { ["lineId"] = l["id"]?.ToString() };
                    if (step.LinesFrom == "counted") { o["countedQty"] = q; o["isChecked"] = true; }
                    else o["qty"] = q;
                    lineList.Add(o);
                }
                body = new JsonObject { ["lines"] = lineList }.ToJsonString();
            }
            using var req = new HttpRequestMessage(new HttpMethod(step.Method), $"http://127.0.0.1:{ctx.Connection.LocalPort}{path}");
            if (body != null) req.Content = new StringContent(body, Encoding.UTF8, "application/json");
            else if (step.Method is "POST" or "PUT") req.Content = new StringContent("{}", Encoding.UTF8, "application/json");
            if (AuthenticationHeaderValue.TryParse(ctx.Request.Headers.Authorization.ToString(), out var auth))
                req.Headers.Authorization = auth;
            var branch = ctx.Request.Headers["X-Branch-Id"].ToString();
            if (!string.IsNullOrWhiteSpace(branch)) req.Headers.TryAddWithoutValidation("X-Branch-Id", branch);
            req.Headers.TryAddWithoutValidation("X-Sbox-Ai-Assistant", "1");
            using var resp = await Loopback.SendAsync(req, ct);
            var text = await resp.Content.ReadAsStringAsync(ct);
            logger.LogInformation("AI action {Kind} step {Method} {Path} → {Status}", p.Kind, step.Method, path, (int)resp.StatusCode);
            JsonNode? node = null;
            try { node = JsonNode.Parse(text); } catch (JsonException) { }
            var ok = resp.IsSuccessStatusCode && (node?["isSuccess"] is not JsonValue v || !v.TryGetValue<bool>(out var s2) || s2);
            if (!ok)
            {
                var msg = (int)resp.StatusCode is 401 or 403
                    ? "Tài khoản không có quyền thực hiện thao tác này."
                    : node?["message"]?.ToString() is { Length: > 0 } m ? m : $"Không thực hiện được ({(int)resp.StatusCode}).";
                // Phiếu đã tạo dở (nháp) vẫn nằm ở màn tương ứng — báo để người dùng xử lý tiếp.
                return new(false, docId == null ? msg : $"{msg} Phiếu nháp đã tạo — mở màn {p.Title.ToLower(Vi)} để hoàn tất.", null, p.OpenModule);
            }
            lastData = node?["data"];
            docId ??= lastData?["id"]?.ToString();
            foreach (var k in new[] { "issueNo", "countNo", "code", "documentNo" })
                if (lastData?[k] is JsonValue dv && dv.ToString() is { Length: > 0 } dn) { docNo = dn; break; }
        }
        return new(true, $"Đã tạo và hoàn thành {p.Title.ToLower(Vi)}{(docNo != null ? " " + docNo : "")}.", docNo, p.OpenModule);
    }

    // ─── Xác nhận / thực thi ───────────────────────────────────────

    static string Key(string id) => "ai-action:" + id;

    public Pending? Get(string id, Guid userId, Guid storeId) =>
        cache.TryGetValue(Key(id), out Pending? p) && p != null && p.UserId == userId && p.StoreId == storeId ? p : null;

    public sealed record ExecResult(bool Ok, string Message, string? DocNo, string? OpenModule);

    public async Task<ExecResult> ExecuteAsync(string id, Guid userId, Guid storeId, CancellationToken ct)
    {
        var p = Get(id, userId, storeId);
        if (p == null) return new(false, "Phiếu đề xuất đã hết hạn hoặc đã xử lý — hỏi lại trợ lý.", null, null);
        // Mỗi đề xuất chỉ ghi một lần (bấm hai lần không tạo trùng).
        cache.Remove(Key(id));

        var ctx = http.HttpContext ?? throw new InvalidOperationException("Không có phiên làm việc");
        if (p.Steps is { Count: > 0 })
            return await ExecuteStepsAsync(p, ctx, ct);
        var url = $"http://127.0.0.1:{ctx.Connection.LocalPort}{p.Path}";
        using var req = new HttpRequestMessage(new HttpMethod(p.Method), url);
        var payload = p.Body;
        if (payload != null && p.Kind is "cash" or "update_cash" && JsonNode.Parse(payload) is JsonObject bo
            && bo["categoryId"]?.ToString() == Guid.Empty.ToString())
        {
            bo["categoryId"] = (await EnsureGeneralCategoryAsync(storeId,
                (CashTransactionType)(int)bo["type"]!, ct)).ToString();
            payload = bo.ToJsonString();
        }
        if (payload != null) req.Content = new StringContent(payload, Encoding.UTF8, "application/json");
        if (AuthenticationHeaderValue.TryParse(ctx.Request.Headers.Authorization.ToString(), out var auth))
            req.Headers.Authorization = auth;
        var branch = ctx.Request.Headers["X-Branch-Id"].ToString();
        if (!string.IsNullOrWhiteSpace(branch)) req.Headers.TryAddWithoutValidation("X-Branch-Id", branch);
        req.Headers.TryAddWithoutValidation("X-Sbox-Ai-Assistant", "1");

        using var resp = await Loopback.SendAsync(req, ct);
        var text = await resp.Content.ReadAsStringAsync(ct);
        logger.LogInformation("AI action {Kind} {Method} {Path} → {Status}", p.Kind, p.Method, p.Path, (int)resp.StatusCode);
        JsonNode? node = null;
        try { node = JsonNode.Parse(text); } catch (JsonException) { }
        var message = node?["message"]?.ToString();
        var success = resp.IsSuccessStatusCode && (node?["isSuccess"] is not JsonValue v || !v.TryGetValue<bool>(out var s) || s);
        if (!success)
        {
            if ((int)resp.StatusCode is 401 or 403)
                return new(false, "Tài khoản không có quyền thực hiện thao tác này.", null, null);
            // Lỗi thì giữ lại đề xuất để người dùng sửa thông tin rồi thử lại.
            cache.Set(Key(id), p, new MemoryCacheEntryOptions { AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(30), Size = 1 });
            return new(false, string.IsNullOrWhiteSpace(message) ? $"Không thực hiện được ({(int)resp.StatusCode})." : message!, null, null);
        }
        var data = node?["data"];
        string? docNo = null;
        foreach (var k in new[] { "returnNo", "receiptNo", "ticketCode", "transactionCode", "requestCode", "orderNo", "code", "documentNo" })
            if (data?[k] is JsonValue dv && dv.ToString() is { Length: > 0 } dn) { docNo = dn; break; }
        var done = p.Title.StartsWith("Sửa ", StringComparison.Ordinal)
            ? "Đã " + p.Title.ToLower(Vi)
            : "Đã tạo " + p.Title.ToLower(Vi);
        return new(true, $"{done}{(docNo != null ? " " + docNo : "")}.", docNo, p.OpenModule);
    }

    async Task<Guid> EnsureGeneralCategoryAsync(Guid storeId, CashTransactionType type, CancellationToken ct)
    {
        var name = type == CashTransactionType.Income ? "Thu khác" : "Chi khác";
        var existing = await db.TransactionCategories
            .Where(x => x.StoreId == storeId && x.Deleted == null && x.Type == type && x.Name == name)
            .Select(x => (Guid?)x.Id).FirstOrDefaultAsync(ct);
        if (existing is Guid g) return g;
        var cat = new ZKTecoADMS.Domain.Entities.TransactionCategory
        {
            Id = Guid.NewGuid(), StoreId = storeId, Name = name, Type = type, IsActive = true, SortOrder = 99,
        };
        db.TransactionCategories.Add(cat);
        await db.SaveChangesAsync(ct);
        return cat.Id;
    }

    public void Discard(string id, Guid userId, Guid storeId)
    {
        if (Get(id, userId, storeId) != null) cache.Remove(Key(id));
    }

    // ─── Đọc tham số ───────────────────────────────────────────────

    static Dictionary<string, object?> Args(JsonElement args)
    {
        var m = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
        if (args.ValueKind != JsonValueKind.Object) return m;
        foreach (var p in args.EnumerateObject())
            m[p.Name] = p.Value.ValueKind switch
            {
                JsonValueKind.String => p.Value.GetString(),
                JsonValueKind.Number => p.Value.TryGetDecimal(out var num)
                    ? num.ToString("0.####", CultureInfo.InvariantCulture)
                    : p.Value.GetRawText(),
                JsonValueKind.Null => null,
                JsonValueKind.Array or JsonValueKind.Object => p.Value.Clone(),
                _ => p.Value.GetRawText(),
            };
        return m;
    }

    static string? S(Dictionary<string, object?> a, string k) =>
        a.TryGetValue(k, out var v) && v is string s && !string.IsNullOrWhiteSpace(s) ? s.Trim() : null;

    static int? I(Dictionary<string, object?> a, string k) =>
        S(a, k) is { } s && decimal.TryParse(s, NumberStyles.Any, CultureInfo.InvariantCulture, out var d) ? (int)d : null;

    static Guid? G(Dictionary<string, object?> a, string k) => S(a, k) is { } s && Guid.TryParse(s, out var g) ? g : null;

    static DateTime? D(Dictionary<string, object?> a, string k) =>
        S(a, k) is { } s && DateTime.TryParseExact(s, ["yyyy-MM-dd", "dd/MM/yyyy", "d/M/yyyy"], CultureInfo.InvariantCulture, DateTimeStyles.None, out var d)
            ? d.Date : null;

    static TimeSpan? T(Dictionary<string, object?> a, string k)
    {
        var s = S(a, k);
        if (s == null) return null;
        s = s.Replace('h', ':').Replace('g', ':').TrimEnd(':');
        if (!s.Contains(':')) s += ":00";
        return TimeSpan.TryParseExact(s, ["h\\:mm", "hh\\:mm", "h\\:m"], CultureInfo.InvariantCulture, out var t) && t < TimeSpan.FromDays(1) ? t : null;
    }

    static decimal Money(Dictionary<string, object?> a, string k)
    {
        var v = ParseMoney(S(a, k)) ?? throw new ActionError($"Số tiền «{S(a, k)}» không hợp lệ.");
        if (v <= 0) throw new ActionError("Số tiền phải lớn hơn 0.");
        return Math.Round(v, 0);
    }

    /// <summary>"500000" / "500k" / "1,5 triệu" / "1tr2" → VNĐ.</summary>
    public static decimal? ParseMoney(string? raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;
        var s = raw.Trim().ToLowerInvariant().Replace(" ", "").Replace("đ", "").Replace("vnd", "");
        // Số máy («500000», «1500000.5») — đọc thẳng; «500.000» / «1.500.000» = phân cách nghìn kiểu Việt.
        if (System.Text.RegularExpressions.Regex.IsMatch(s, @"^\d{1,3}(\.\d{3})+$")) return decimal.Parse(s.Replace(".", ""), CultureInfo.InvariantCulture);
        if (System.Text.RegularExpressions.Regex.IsMatch(s, @"^\d+(\.\d+)?$")) return decimal.Parse(s, CultureInfo.InvariantCulture);
        decimal mult = 1;
        string[] million = ["triệu", "trieu", "tr"];
        foreach (var m in million)
        {
            var i = s.IndexOf(m, StringComparison.Ordinal);
            if (i < 0) continue;
            var head = s[..i];
            var tail = s[(i + m.Length)..];
            if (!decimal.TryParse(head.Replace(',', '.'), NumberStyles.Any, CultureInfo.InvariantCulture, out var h)) return null;
            decimal frac = 0;
            if (tail.Length > 0 && decimal.TryParse(tail, NumberStyles.Any, CultureInfo.InvariantCulture, out var t))
                frac = t * (decimal)Math.Pow(10, 6 - tail.Length);
            return h * 1_000_000 + frac;
        }
        if (s.EndsWith("k") || s.EndsWith("nghìn") || s.EndsWith("ngàn"))
        {
            mult = 1000;
            s = s.TrimEnd('k').Replace("nghìn", "").Replace("ngàn", "");
        }
        s = s.Contains(',') && !s.Contains('.') && s.Split(',')[^1].Length == 3 ? s.Replace(",", "") : s.Replace(".", "").Replace(',', '.');
        return decimal.TryParse(s, NumberStyles.Any, CultureInfo.InvariantCulture, out var v) ? v * mult : null;
    }

    static string Vnd(decimal v) => v.ToString("#,##0", Vi) + "đ";
}
