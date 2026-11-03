using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using ZKTecoADMS.Application.Helpers;

namespace ZKTecoADMS.Api.Services;

/// <summary>Một bước hướng dẫn sử dụng — đúng nội dung màn Hướng dẫn trong app.</summary>
public sealed record HelpChunk(
    string Mode,
    string StepId,
    string Title,
    string Summary,
    string[] Bullets,
    string Tip,
    string Keywords,
    string[] ActionTags,
    string[] ScreenNotes,
    string Area = "",
    string Group = "",
    string Trail = "");

/// <summary>
/// Kiến thức «làm thế nào» của trợ lý AI. Nội dung lấy từ HelpCorpus/landing-guide.json — file do
/// flutter_client/test/guide_shots/guide_corpus_test.dart xuất từ landing_usage_guide.dart /
/// landing_industry_guide.dart (sửa hướng dẫn trong app rồi xuất lại, không sửa tay JSON).
/// Ở đây chỉ giữ phần riêng của AI theo mã bước: từ khóa tìm kiếm thêm và nút điều hướng.
/// </summary>
public static class AiAssistantHelpCorpus
{
    public const string ResourceName = "Sbox.HelpCorpus.landing-guide.json";

    /// <summary>Mục hướng dẫn app mở được qua [[GUIDE:mục/bước]].</summary>
    public static readonly string[] Modes = ["basic", "advanced", "pos", "industry"];

    internal sealed record Overlay(string Keywords, string[] ActionTags);

    /// <summary>Từ khóa thêm (cách khách hay hỏi) + nút điều hướng cho từng bước.</summary>
    internal static readonly IReadOnlyDictionary<string, Overlay> Overlays = new Dictionary<string, Overlay>(StringComparer.Ordinal)
    {
        ["hr_analytics"] = new("báo cáo phân tích tỷ lệ chuyên cần vắng không phép chấm công bất thường phép còn lại độ phủ ca báo cáo điều hành tháng báo cáo đi đường giờ di chuyển", ["nav_attendance_summary", "nav_dashboard"]),
        ["employee_self_service"] = new("nhân viên dùng app xem phiếu lương của tôi lịch ca của tôi gửi đơn nghỉ phép tăng ca sửa công chấm công điện thoại đăng nhập app", ["nav_payslip", "nav_work_schedule", "nav_leave"]),
        ["branches"] = new("chi nhánh nhiều điểm bán nhiều cửa hàng trụ sở chính chi nhánh cha quản lý chi nhánh sơ đồ chi nhánh", ["nav_departments"]),
        ["raw_attendance"] = new("chấm công thô log máy chấm công duyệt chấm công chấm ngoài vị trí chấm mobile chấm công thủ công chưa gắn nhân viên vân tay khuôn mặt", ["nav_attendance", "nav_attendance_correction"]),
        ["allowance"] = new("phụ cấp ăn trưa xăng xe điện thoại chuyên cần ca đêm phụ cấp theo ca theo ngày công miễn thuế đóng bảo hiểm", ["nav_payroll"]),
        ["pos_stock_count"] = new("kiểm kho kiểm kê cân bằng kho lệch kho số thực tế khớp tồn quét hàng loạt đếm hàng", ["nav_pos_products"]),
        ["pos_stock_card"] = new("tồn kho thẻ kho định mức tồn dưới định mức hết hàng sắp hết có thể bán khách đặt giữ chỗ dự kiến hết biến động kho ai trừ kho", ["nav_pos_products", "nav_pos_reports"]),
        ["pos_stock_docs"] = new("trả hàng nhập trả ncc xuất hủy hàng hỏng hết hạn đổ vỡ xuất dùng nội bộ phiếu kho hủy phiếu hoàn kho", ["nav_pos_products"]),
        ["pos_suppliers"] = new("nhà cung cấp ncc nhập hàng phiếu nhập công nợ ncc trả nợ ncc đối chiếu công nợ nợ đầu kỳ giá vốn hóa đơn đầu vào", ["nav_pos_products", "nav_pos_reports"]),
        ["pos_bank_account"] = new("tài khoản nhận tiền số tài khoản stk ngân hàng vietqr qr chuyển khoản mã qr thanh toán tingee tự báo có tiền báo có", ["nav_pos_sell"]),
        ["pos_warranty"] = new("bảo hành tiếp nhận bảo hành phiếu bảo hành seri imei đổi máy trả máy khách lấy máy phí sửa chữa hết hạn bảo hành nhắc bảo hành", ["nav_pos_sell", "nav_pos_reports"]),
        ["pos_kds"] = new("kds màn hình bếp bếp bar ra món đang làm món trễ đọc món màn hình nhà bếp phiếu bếp điện tử", ["nav_pos_sell"]),
        ["pos_qr_order"] = new("qr order menu qr gọi món tại bàn quét qr đặt hàng online link đặt hàng đơn online xác nhận đơn in qr bàn tem qr khách tự order", ["nav_pos_sell"]),
        ["advance"] = new("ứng lương phiếu ứng tạm ứng tài chính duyệt ứng lương báo cáo ứng lương", ["nav_advance", "nav_advance_create"]),
        ["asset"] = new("tài sản thiết bị cấp phát thu hồi bảo hành báo cáo tài sản quản lý vận hành", ["nav_assets"]),
        ["attendance_correction"] = new("sửa công bổ sung công quên chấm công chấm công bù duyệt chấm công duyệt phạt quên chấm", ["nav_attendance_correction", "nav_attendance_correction_create"]),
        ["attendance_modes"] = new("kiểu chấm công checkin chỉ chấm vào thiếu chấm mode đủ ca", ["nav_attendance_summary"]),
        ["bonus"] = new("thưởng phiếu thưởng thưởng nóng thưởng kpi tổng hợp lương duyệt thưởng", ["nav_bonus_penalty"]),
        ["bonus_ticket"] = new("phiếu thưởng tạo thưởng tài chính duyệt thưởng bảng lương tổng hợp lương", ["nav_bonus_penalty"]),
        ["business_trip"] = new("công tác phí tạm ứng công tác hồ sơ công tác chi phí đi lại", ["nav_business_trip", "nav_business_trip_create"]),
        ["cash"] = new("thu chi quỹ tiền mặt ghi thu ghi chi tài chính đối soát báo cáo thu chi", ["nav_cash"]),
        ["common_hrm"] = new("đi trễ quên chấm thiếu chấm quên mật khẩu máy offline tình huống phạt oan", ["nav_attendance", "nav_attendance_correction"]),
        ["communication"] = new("truyền thông thông báo nội bộ bản tin push tin tức nội quy", ["nav_communication"]),
        ["daily_ops"] = new("hàng ngày cuối tháng quy trình ngày duyệt đơn vận hành hrm chốt lương", ["nav_dashboard", "nav_attendance_summary"]),
        ["device_connect"] = new("kết nối máy chấm công zkteco adms cloud serial máy chủ đám mây online đồng bộ", ["nav_attendance"]),
        ["gateway_wifi"] = new("gateway wifi esp32 máy chấm công cũ tcp 4370 không có máy chủ đám mây", []),
        ["device_users"] = new("nhân viên chấm công vân tay khuôn mặt đồng bộ máy zkteco nhân sự chấm công chấm công thô", ["nav_attendance", "nav_attendance_history"]),
        ["employee_account"] = new("tài khoản nhân viên đăng nhập phân quyền vai trò cài đặt tài khoản", ["nav_employees"]),
        ["employees"] = new("thêm nhân viên hồ sơ nhân sự import excel phòng ban chức vụ mã nhân viên hr", ["nav_employees"]),
        ["feedback"] = new("góp ý khiếu nại kiến nghị phản ánh ý kiến ẩn danh phản hồi xử lý hạn xử lý đánh giá hài lòng báo cáo", ["nav_feedback", "nav_feedback_create"]),
        ["field_checkin"] = new("bản đồ nhân sự vị trí lộ trình chấm ngoài hiện trường gps", ["nav_field_checkin"]),
        ["first_payroll"] = new("chốt lương bảng lương tháng đầu kỳ lương tổng hợp lương phiếu lương", ["nav_payroll", "nav_payslip"]),
        ["getting_started"] = new("bắt đầu checklist 7 ngày triển khai lộ trình người mới", ["nav_dashboard"]),
        ["holidays"] = new("ngày lễ tết âm lịch ngày nghỉ đặc biệt hệ số lương lễ", []),
        ["ind_choose"] = new("ngành hàng chọn ngành đổi ngành chế độ bán", ["nav_pos_sell"]),
        ["ind_commission"] = new("hoa hồng nhân viên commission theo buổi khi bán", ["nav_pos_reports"]),
        ["ind_docs_log"] = new("mẫu word hợp đồng lịch sử thao tác nhật ký ai sửa xóa", []),
        ["ind_gym"] = new("gym yoga thẻ tập hội viên check-in gia hạn", ["nav_pos_sell"]),
        ["ind_hotel"] = new("khách sạn nhà nghỉ lưu trú tiền phòng theo đêm nhận phòng trả phòng", ["nav_pos_sell"]),
        ["ind_restaurant"] = new("nhà hàng cafe quán ăn bàn gọi món bếp", ["nav_pos_sell"]),
        ["ind_retail"] = new("bán lẻ siêu thị tạp hóa mã vạch cân điện tử bán nhanh", ["nav_pos_sell", "nav_pos_products"]),
        ["ind_room_hourly"] = new("karaoke bi-a bida phòng giờ tính giờ block chốt tiền giờ", ["nav_pos_sell"]),
        ["ind_salon"] = new("salon spa nail ghế giường liệu trình gói buổi trừ buổi", ["nav_pos_sell"]),
        ["insurance_tax"] = new("bảo hiểm bhxh bhyt bhtn thuế tncn giảm trừ gia cảnh người phụ thuộc", ["nav_payroll"]),
        ["kpi"] = new("kpi chỉ tiêu đánh giá hiệu suất trọng số quản lý vận hành thưởng", ["nav_kpi"]),
        ["leave"] = new("nghỉ phép đơn nghỉ phép năm duyệt nghỉ phép báo cáo nghỉ phép tạo đơn", ["nav_leave", "nav_leave_create"]),
        ["meal"] = new("chấm cơm suất ăn cơm trưa cơm ca phiếu ăn in phiếu căn tin thực đơn menu hôm nay tiền ăn công nợ", ["nav_meal", "nav_meal_register"]),
        ["mobile_attendance"] = new("chấm công mobile chấm công điện thoại chấm công trên app gps wifi face id đăng ký thiết bị duyệt chấm công vùng chấm công", ["nav_attendance", "nav_attendance_correction"]),
        ["notifications"] = new("thông báo nhắc việc chuông bật tắt thông báo", []),
        ["org_structure"] = new("phòng ban chức vụ chi nhánh cơ cấu tổ chức bộ phận", ["nav_departments"]),
        ["overtime"] = new("tăng ca đăng ký tăng ca duyệt tăng ca làm thêm giờ ot tiền tăng ca", ["nav_overtime", "nav_overtime_create"]),
        ["penalty"] = new("phạt mức phạt đi trễ về sớm tái phạm phiếu phạt cài đặt phạt báo cáo phạt", ["nav_penalty"]),
        ["penalty_ticket"] = new("tạo phiếu phạt đi trễ về sớm tái phạm tài chính duyệt phạt báo cáo phạt", ["nav_penalty"]),
        ["pos_common"] = new("không in in sai lệch tiền hủy đơn trả hàng tình huống pos không đủ tồn tồn âm thao tác lại", ["nav_pos_sell", "nav_pos_printers", "nav_pos_reports"]),
        ["pos_customers"] = new("khách hàng điểm công nợ khách crm pos", ["nav_pos_sell"]),
        ["pos_devices"] = new("a6 a7 sunmi flutter_pos hrm pos thiết bị thu ngân c20lite", ["nav_pos_sell"]),
        ["pos_einvoice"] = new("hóa đơn điện tử viettel easy misa vnpt einvoice kết nối cấu hình xuất hđđt qr tra cứu", ["nav_pos_sell"]),
        ["pos_einvoice_manage"] = new("quản lý hóa đơn điện tử thay thế hủy đồng bộ gửi zalo email bản nháp tải danh sách portal", ["nav_pos_reports"]),
        ["pos_eod"] = new("cuối ngày chốt ca đóng ca kết ca đếm két tổng kết end of day tiền mặt ca thu ngân mở ca đóng két", ["nav_pos_reports"]),
        ["pos_inventory"] = new("kho kho hàng nhập xuất tồn chứng từ kho giá vốn bình quân phiếu tạm hoàn thành", ["nav_pos_products", "nav_pos_reports"]),
        ["pos_kitchen"] = new("bếp gửi bếp phiếu bếp tem ly kds", ["nav_pos_sell", "nav_pos_printers"]),
        ["pos_printers"] = new("máy in mẫu in k80 k58 print agent usb bluetooth lan wifi ip kết nối máy in máy in hóa đơn máy in bếp in thử",["nav_pos_printers"]),
        ["pos_products"] = new("thêm hàng tạo hàng hóa sản phẩm giá bán danh mục món mã vạch barcode tồn đầu kỳ định mức tồn ngừng kinh doanh ẩn pos nhà cung cấp", ["nav_pos_products"]),
        ["pos_units"] = new("đơn vị tính đvt quy đổi lon lốc thùng hộp mã vạch thùng bảng giá giá sỉ giá vip khuyến mãi chiết khấu", ["nav_pos_products", "nav_pos_sell"]),
        ["pos_lots"] = new("lô hạn sử dụng hsd nsx fefo bảo hành seri imei hàng gia công nhôm kính m2 vị trí kho trọng lượng tùy chọn form", ["nav_pos_products"]),
        ["pos_services"] = new("dịch vụ tính giờ block phí mở phòng giờ đầu khung giờ đặc biệt gói buổi liệu trình gói giờ đếm ngược thời lượng", ["nav_pos_products"]),
        ["pos_combo"] = new("combo đóng gói set gói quà thành phần tồn kho combo giá combo hiện thành phần", ["nav_pos_products"]),
        ["pos_bom"] = new("nguyên vật liệu nvl định lượng công thức pha chế trừ nguyên liệu báo cáo nguyên vật liệu sắp hết", ["nav_pos_products", "nav_pos_reports"]),
        ["pos_toppings"] = new("topping trân châu thạch tùy chọn thêm nhóm topping món thêm phụ thu báo cáo topping", ["nav_pos_products", "nav_pos_sell"]),
        ["pos_sale_edit"] = new("sửa giá chiết khấu dòng giảm giá món ghi chú topping hoa hồng nhân viên tách dòng xóa món đổi số lượng", ["nav_pos_sell"]),
        ["pos_sale_pay"] = new("thanh toán khách hàng tích điểm công nợ ghi nợ voucher tiền thối tiền trả khách chuyển khoản qr in hóa đơn xuất hđđt", ["nav_pos_sell"]),
        ["pos_after_sale"] = new("đơn hàng hóa đơn in lại hủy đơn trả hàng hoàn tiền lịch sử hủy trả tra cứu đơn", ["nav_pos_sell", "nav_pos_reports"]),
        ["pos_reports"] = new("báo cáo pos doanh thu tồn kho lợi nhuận 14 báo cáo cuối ngày", ["nav_pos_reports"]),
        ["pos_rules"] = new("nguyên tắc quy tắc chứng từ tạm hoàn thành hủy xóa thẻ kho phân quyền", ["nav_pos_sell"]),
        ["pos_sales"] = new("bán hàng thu ngân chọn hàng quét mã nhiều hóa đơn order pos ca thu ngân mở ca", ["nav_pos_sell"]),
        ["pos_setup"] = new("pos bán hàng thiết lập pos ngành hàng cửa hàng", ["nav_pos_sell", "nav_pos_products"]),
        ["pos_stock_rules"] = new("tồn khả dụng giữ chỗ bán âm tồn âm hết hàng không đủ tồn kho combo định lượng lô hsd fefo", ["nav_pos_products", "nav_pos_sell"]),
        ["pos_tables"] = new("bàn phòng sơ đồ bàn đặt bàn đặt lịch f&b", ["nav_pos_sell"]),
        ["production"] = new("sản lượng lương sản phẩm khoán nhóm sản phẩm đơn giá nhập sản lượng quản lý vận hành", []),
        ["register"] = new("đăng ký phần mềm sbox sana doanh nghiệp cửa hàng store id mã đăng nhập kích hoạt tài khoản admin", []),
        ["reports"] = new("báo cáo xem báo cáo tổng hợp chấm công tổng hợp lương báo cáo phạt ứng lương thu chi nghỉ phép tài sản dashboard xuất excel", ["nav_dashboard", "nav_attendance_summary", "nav_leave_report", "nav_cash_report"]),
        ["salary"] = new("thiết lập lương lương cơ bản phụ cấp bảo hiểm thuế tncn tổng hợp lương phiếu lương bảng lương", ["nav_payslip", "nav_payroll"]),
        ["shift_swap"] = new("đổi ca đổi ca làm việc đồng nghiệp duyệt đổi ca", ["nav_shift_change"]),
        ["shifts"] = new("cấu hình ca thiết lập ca phân ca lịch làm việc ca sáng ca đêm ca xoay duyệt lịch", ["nav_work_schedule"]),
        ["tasks"] = new("công việc giao việc kanban hạn hoàn thành ưu tiên", ["nav_tasks"]),
        ["work_schedule"] = new("lịch làm việc phân ca đổi ca duyệt lịch làm việc ca tuần tháng", ["nav_work_schedule", "nav_shift_change"]),
        ["work_schedule_basic"] = new("phân lịch xếp ca lịch làm việc tuần tháng sao chép lịch", ["nav_work_schedule"]),
        ["pos_quotes"] = new("báo giá hợp đồng gửi báo giá pdf zalo khách chốt nghiệm thu đề nghị thanh toán cọc vat đánh số báo giá", []),
        ["pos_booking"] = new("đặt bàn đặt phòng đặt lịch hẹn đặt chỗ giữ bàn cọc nhận bàn khách không đến tự xếp thợ salon", ["nav_pos_sell"]),
        ["pos_customer_display"] = new("màn hình phụ màn hình khách màn thứ hai qr chuyển khoản cho khách quét quảng cáo video sunmi t1", ["nav_pos_sell"]),
        ["pos_shipping"] = new("giao hàng vận đơn ghn ghtk viettel post ahamove spx cod thu hộ in tem cước giao hàng đối soát cod", ["nav_pos_sell"]),
        ["ai_assistant"] =new("trợ lý ảo ai gemini giọng nói micro nói ra lệnh rảnh tay xác nhận thẻ hoàn tác đọc to nhật ký thao tác ai bản tin sáng khóa ai", []),
        ["zalo_bot"] =new("zalo bot liên kết zalo tin nhắn zalo thông báo qua zalo token bot webhook", []),
    };

    private static readonly IReadOnlyList<HelpChunk> AllChunks = Load();

    public static IReadOnlyList<HelpChunk> All => AllChunks;

    public static IReadOnlyList<HelpChunk> Search(string query, int topK = 4) =>
        SearchScored(query, topK).Select(x => x.Chunk).ToList();

    /// <summary>
    /// Điểm khớp đủ chắc để nạp hướng dẫn kể cả khi câu không có chữ «cách / hướng dẫn» (vd «sao máy in không in»):
    /// khoảng 3 từ khóa trúng tiêu đề / từ khóa của bước.
    /// </summary>
    public const int ConfidentScore = 45;

    /// <summary>Tìm bước hướng dẫn kèm điểm — so không dấu (gõ / nói không dấu vẫn trúng).</summary>
    public static IReadOnlyList<(HelpChunk Chunk, int Score)> SearchScored(string query, int topK = 4)
    {
        if (string.IsNullOrWhiteSpace(query))
            return [];

        var terms = SplitTerms(query);
        if (terms.Count == 0)
            return [];

        var raw = VnSearch.FoldText(query);
        var ranked = Folded
            .Select(f => (f.Chunk, Score: ScoreChunk(f, terms, raw)))
            .Where(x => x.Score > 0)
            .OrderByDescending(x => x.Score)
            .ThenBy(x => x.Chunk.Mode, StringComparer.Ordinal)
            .ThenBy(x => x.Chunk.StepId, StringComparer.Ordinal)
            .Take(Math.Max(1, topK))
            .ToList();
        // Bài kém hơn một nửa bài đứng đầu chỉ trùng vài từ lẻ — bỏ, khỏi trả kèm bài lạc đề.
        return ranked.Count == 0 ? ranked : ranked.Where(x => x.Score * 2 >= ranked[0].Score).ToList();
    }

    /// <summary>
    /// Bài dùng cho câu trả lời hướng dẫn (không qua AI): bài đứng đầu, kèm bài thứ hai chỉ khi điểm gần bằng (≥ 90%) —
    /// câu hỏi «kết nối máy in hóa đơn qua LAN» không cần kèm bài hóa đơn điện tử.
    /// </summary>
    public static IReadOnlyList<HelpChunk> GuideAnswerHits(string query)
    {
        var hits = SearchScored(query, topK: 2);
        return hits.Where(x => x.Score * 10 >= hits[0].Score * 9).Select(x => x.Chunk).ToList();
    }

    public static string FormatForPrompt(IEnumerable<HelpChunk> chunks)
    {
        var list = chunks?.ToList() ?? [];
        if (list.Count == 0)
            return string.Empty;

        var sb = new StringBuilder();
        foreach (var chunk in list)
        {
            sb.AppendLine("=== HƯỚNG DẪN SỬ DỤNG ===");
            sb.AppendLine($"[[GUIDE:{chunk.Mode}/{chunk.StepId}]]");
            // Vị trí trong hướng dẫn (khu › nhóm) để AI chỉ đường: «Hướng dẫn POS › Kho hàng».
            if (!string.IsNullOrWhiteSpace(chunk.Trail))
                sb.AppendLine($"Mục hướng dẫn: {chunk.Trail} › {chunk.Title}");
            sb.AppendLine(chunk.Title);
            sb.AppendLine(chunk.Summary);
            foreach (var bullet in chunk.Bullets)
                sb.AppendLine($"- {bullet}");
            if (!string.IsNullOrWhiteSpace(chunk.Tip))
                sb.AppendLine($"Mẹo: {chunk.Tip}");
            // Chú thích ảnh hướng dẫn: tên nút / ô đúng như trên màn hình.
            foreach (var note in chunk.ScreenNotes)
                sb.AppendLine($"Trên màn hình: {note}");
            if (chunk.ActionTags.Length > 0)
                sb.AppendLine("Gợi ý điều hướng: " + string.Join(", ", chunk.ActionTags.Select(t => $"[[ACTION:{t}]]")));
            sb.AppendLine();
        }

        return sb.ToString().TrimEnd();
    }

    public static bool TryParseGuideTag(string tag, out string mode, out string stepId)
    {
        mode = string.Empty;
        stepId = string.Empty;
        if (string.IsNullOrWhiteSpace(tag))
            return false;

        var parts = tag.Trim().Split('/', 2, StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length != 2)
            return false;

        var parsedStepId = parts[1];
        // Mã bước là duy nhất trong mọi mục: AI ghi nhầm mục vẫn mở đúng bước.
        var chunk = AllChunks.FirstOrDefault(c => string.Equals(c.StepId, parsedStepId, StringComparison.OrdinalIgnoreCase));
        if (chunk == null)
            return false;

        mode = chunk.Mode;
        stepId = chunk.StepId;
        return true;
    }

    private sealed record GuideDocJson(GuideAreaJson[] Areas, GuideStepJson[] Steps);

    private sealed record GuideAreaJson(string Id, string Title, GuideGroupJson[] Groups);

    private sealed record GuideGroupJson(string Id, string Title);

    private sealed record GuideStepJson(
        string Mode,
        string Area,
        string Group,
        string StepId,
        string Title,
        string Desc,
        string[] Bullets,
        string Tip,
        string[] Keywords,
        GuideShotJson[] Shots);

    private sealed record GuideShotJson(int AfterBullet, string Caption);

    private static IReadOnlyList<HelpChunk> Load()
    {
        using var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(ResourceName)
            ?? throw new InvalidOperationException($"Thiếu tài nguyên {ResourceName}");
        var doc = JsonSerializer.Deserialize<GuideDocJson>(stream,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        var trails = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var a in doc?.Areas ?? [])
            foreach (var g in a.Groups ?? [])
                trails[$"{a.Id}/{g.Id}"] = $"Hướng dẫn {a.Title} › {g.Title}";
        return (doc?.Steps ?? []).Select(s =>
        {
            var extra = Overlays.GetValueOrDefault(s.StepId);
            var trail = trails.GetValueOrDefault($"{s.Area}/{s.Group}") ?? string.Empty;
            // Tên nhóm cũng là từ khóa: «kho hàng», «khởi tạo», «đơn từ»… trúng cả nhóm.
            var groupTitle = trail.Split('›').LastOrDefault()?.Trim() ?? string.Empty;
            var keywords = string.Join(' ', (s.Keywords ?? []).Append(extra?.Keywords ?? string.Empty).Append(groupTitle)).Trim();
            return new HelpChunk(
                s.Mode,
                s.StepId,
                s.Title,
                s.Desc,
                s.Bullets ?? [],
                s.Tip ?? string.Empty,
                keywords,
                extra?.ActionTags ?? [],
                (s.Shots ?? []).Select(x => x.Caption).ToArray(),
                s.Area ?? string.Empty,
                s.Group ?? string.Empty,
                trail);
        }).ToList();
    }

    /// <summary>Từ hay gặp trong mọi câu (đại từ, hư từ) — không mang nghĩa chức năng, chỉ làm nhiễu điểm.</summary>
    static readonly HashSet<string> StopWords =
    [
        "toi", "em", "anh", "chi", "ban", "minh", "co", "khong", "la", "va", "cua", "cho", "thi", "ma", "nay", "do", "di",
        "nhe", "a", "oi", "the", "nao", "sao", "lam", "duoc", "can", "muon", "phai", "voi", "trong", "tren", "o", "de",
        "cach", "huong", "dan", "giup", "hay", "roi", "chua", "bi", "mot", "nhung", "cac", "khi", "neu", "vay", "gi",
    ];

    private static List<string> SplitTerms(string query)
    {
        return VnSearch.FoldText(query)
            .Split([' ', '\t', '\r', '\n', ',', ';', '.', '?', '!', '«', '»', '"', '(', ')'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Where(t => t.Length >= 2 && !StopWords.Contains(t))
            .Distinct()
            .ToList();
    }

    sealed record FoldedChunk(HelpChunk Chunk, string StepId, string Title, string Summary, string Keywords, string[] Bullets);

    static readonly IReadOnlyList<FoldedChunk> Folded = AllChunks
        .Select(c => new FoldedChunk(c, c.StepId.ToLowerInvariant().Replace('_', ' '), VnSearch.Fold(c.Title), VnSearch.Fold(c.Summary),
            VnSearch.Fold(c.Keywords), c.Bullets.Select(VnSearch.Fold).ToArray()))
        .ToList();

    /// <summary>
    /// Từ ngắn («in», «lan», «don») phải trùng nguyên từ — so chuỗi con thì «in» khớp «invoice», «lan» khớp «lanh»… làm
    /// bài không liên quan lên đầu.
    /// </summary>
    static bool Has(string text, string term) =>
        term.Length > 3 ? text.Contains(term) : Regex.IsMatch(text, $@"(?<![\p{{L}}\p{{N}}]){Regex.Escape(term)}(?![\p{{L}}\p{{N}}])");

    private static int ScoreChunk(FoldedChunk c, IReadOnlyList<string> terms, string raw)
    {
        var score = 0;
        if (raw.Length >= 2)
        {
            if (c.StepId.Contains(raw)) score += 30;
            if (c.Title.Contains(raw)) score += 20;
            if (c.Keywords.Contains(raw)) score += 15;
            if (c.Summary.Contains(raw)) score += 8;
            score += 4 * c.Bullets.Count(b => b.Contains(raw));
        }

        foreach (var term in terms)
        {
            if (Has(c.StepId, term)) score += 12;
            if (Has(c.Title, term)) score += 10;
            if (Has(c.Keywords, term)) score += 8;
            if (Has(c.Summary, term)) score += 5;
            score += 3 * c.Bullets.Count(b => Has(b, term));
        }

        // Cụm hai từ liền nhau («may in», «hoa don») — tách từng từ thì «máy in hóa đơn» ngang điểm với bài hóa đơn điện tử.
        for (var i = 0; i + 1 < terms.Count; i++)
        {
            var pair = terms[i] + " " + terms[i + 1];
            if (c.StepId.Contains(pair)) score += 15;
            if (c.Title.Contains(pair)) score += 15;
            if (c.Keywords.Contains(pair)) score += 10;
            if (c.Summary.Contains(pair)) score += 5;
            score += 3 * c.Bullets.Count(b => b.Contains(pair));
        }

        return score;
    }
}
