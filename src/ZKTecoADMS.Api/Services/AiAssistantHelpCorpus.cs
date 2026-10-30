using System.Reflection;
using System.Text;
using System.Text.Json;

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
    string[] ScreenNotes);

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
        ["advance"] = new("ứng lương phiếu ứng tạm ứng tài chính duyệt ứng lương báo cáo ứng lương", ["nav_advance", "nav_advance_create"]),
        ["asset"] = new("tài sản thiết bị cấp phát thu hồi bảo hành báo cáo tài sản quản lý vận hành", ["nav_assets"]),
        ["attendance_modes"] = new("kiểu chấm công checkin chỉ chấm vào thiếu chấm mode đủ ca", ["nav_attendance_summary"]),
        ["bonus"] = new("thưởng phiếu thưởng thưởng nóng thưởng kpi tổng hợp lương duyệt thưởng", ["nav_bonus_penalty"]),
        ["bonus_ticket"] = new("phiếu thưởng tạo thưởng tài chính duyệt thưởng bảng lương tổng hợp lương", ["nav_bonus_penalty"]),
        ["business_trip"] = new("công tác phí tạm ứng công tác hồ sơ công tác chi phí đi lại", ["nav_business_trip", "nav_business_trip_create"]),
        ["cash"] = new("thu chi quỹ tiền mặt ghi thu ghi chi tài chính đối soát báo cáo thu chi", ["nav_cash"]),
        ["common_hrm"] = new("đi trễ quên chấm thiếu chấm quên mật khẩu máy offline tình huống phạt oan", ["nav_attendance", "nav_attendance_correction"]),
        ["communication"] = new("truyền thông thông báo nội bộ bản tin push tin tức nội quy", ["nav_communication"]),
        ["daily_ops"] = new("hàng ngày cuối tháng quy trình ngày duyệt đơn vận hành hrm chốt lương", ["nav_dashboard", "nav_attendance_summary"]),
        ["device_connect"] = new("kết nối máy chấm công zkteco adms cloud serial máy chủ đám mây online đồng bộ", ["nav_attendance"]),
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
        ["mobile_attendance"] = new("chấm công mobile gps wifi face id đăng ký thiết bị duyệt chấm công vùng chấm công", ["nav_attendance", "nav_attendance_correction"]),
        ["notifications"] = new("thông báo nhắc việc chuông bật tắt thông báo", []),
        ["org_structure"] = new("phòng ban chức vụ chi nhánh cơ cấu tổ chức bộ phận", ["nav_departments"]),
        ["penalty"] = new("phạt mức phạt đi trễ về sớm tái phạm phiếu phạt cài đặt phạt báo cáo phạt", ["nav_penalty"]),
        ["penalty_ticket"] = new("tạo phiếu phạt đi trễ về sớm tái phạm tài chính duyệt phạt báo cáo phạt", ["nav_penalty"]),
        ["pos_common"] = new("không in in sai lệch tiền hủy đơn trả hàng tình huống pos không đủ tồn tồn âm thao tác lại", ["nav_pos_sell", "nav_pos_printers", "nav_pos_reports"]),
        ["pos_customers"] = new("khách hàng điểm công nợ khách crm pos", ["nav_pos_sell"]),
        ["pos_devices"] = new("a6 a7 sunmi flutter_pos hrm pos thiết bị thu ngân c20lite", ["nav_pos_sell"]),
        ["pos_einvoice"] = new("hóa đơn điện tử viettel easy misa vnpt einvoice kết nối cấu hình xuất hđđt qr tra cứu", ["nav_pos_sell"]),
        ["pos_einvoice_manage"] = new("quản lý hóa đơn điện tử thay thế hủy đồng bộ gửi zalo email bản nháp tải danh sách portal", ["nav_pos_reports"]),
        ["pos_eod"] = new("cuối ngày chốt ca tổng kết end of day tiền mặt ca thu ngân mở ca đóng két", ["nav_pos_reports"]),
        ["pos_inventory"] = new("kho nhập hàng tồn kho kiểm kho kiểm kê ncc xuất hủy xuất nội bộ thẻ kho giá vốn", ["nav_pos_products", "nav_pos_reports"]),
        ["pos_kitchen"] = new("bếp gửi bếp phiếu bếp tem ly kds", ["nav_pos_sell", "nav_pos_printers"]),
        ["pos_printers"] = new("máy in mẫu in k80 k58 print agent usb bluetooth", ["nav_pos_printers"]),
        ["pos_products"] = new("hàng hóa sản phẩm giá bán danh mục món combo", ["nav_pos_products"]),
        ["pos_reports"] = new("báo cáo pos doanh thu tồn kho lợi nhuận 14 báo cáo cuối ngày", ["nav_pos_reports"]),
        ["pos_rules"] = new("nguyên tắc quy tắc chứng từ tạm hoàn thành hủy xóa thẻ kho phân quyền", ["nav_pos_sell"]),
        ["pos_sales"] = new("bán hàng thu ngân thanh toán hóa đơn order pos ca thu ngân mở ca", ["nav_pos_sell"]),
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
    };

    private static readonly IReadOnlyList<HelpChunk> AllChunks = Load();

    public static IReadOnlyList<HelpChunk> All => AllChunks;

    public static IReadOnlyList<HelpChunk> Search(string query, int topK = 4)
    {
        if (string.IsNullOrWhiteSpace(query))
            return [];

        var terms = SplitTerms(query);
        if (terms.Count == 0)
            return [];

        var scored = new List<(HelpChunk Chunk, int Score)>();
        foreach (var chunk in AllChunks)
        {
            var score = ScoreChunk(chunk, terms, query);
            if (score > 0)
                scored.Add((chunk, score));
        }

        return scored
            .OrderByDescending(x => x.Score)
            .ThenBy(x => x.Chunk.Mode, StringComparer.Ordinal)
            .ThenBy(x => x.Chunk.StepId, StringComparer.Ordinal)
            .Take(Math.Max(1, topK))
            .Select(x => x.Chunk)
            .ToList();
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

    private sealed record GuideStepJson(
        string Mode,
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
        var steps = JsonSerializer.Deserialize<GuideStepJson[]>(stream,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? [];
        return steps.Select(s =>
        {
            var extra = Overlays.GetValueOrDefault(s.StepId);
            var keywords = string.Join(' ', (s.Keywords ?? []).Append(extra?.Keywords ?? string.Empty)).Trim();
            return new HelpChunk(
                s.Mode,
                s.StepId,
                s.Title,
                s.Desc,
                s.Bullets ?? [],
                s.Tip ?? string.Empty,
                keywords,
                extra?.ActionTags ?? [],
                (s.Shots ?? []).Select(x => x.Caption).ToArray());
        }).ToList();
    }

    private static List<string> SplitTerms(string query)
    {
        return query
            .Split([' ', '\t', '\r', '\n', ',', ';', '.', '?', '!'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(t => t.Trim().ToLowerInvariant())
            .Where(t => t.Length >= 2)
            .Distinct()
            .ToList();
    }

    private static int ScoreChunk(HelpChunk chunk, IReadOnlyList<string> terms, string rawQuery)
    {
        var score = 0;
        var title = chunk.Title.ToLowerInvariant();
        var summary = chunk.Summary.ToLowerInvariant();
        var keywords = chunk.Keywords.ToLowerInvariant();
        var stepId = chunk.StepId.ToLowerInvariant();
        var raw = rawQuery.Trim().ToLowerInvariant();

        if (raw.Length >= 2)
        {
            if (stepId.Contains(raw))
                score += 30;
            if (title.Contains(raw))
                score += 20;
            if (keywords.Contains(raw))
                score += 15;
            if (summary.Contains(raw))
                score += 8;
            foreach (var bullet in chunk.Bullets)
            {
                if (bullet.ToLowerInvariant().Contains(raw))
                    score += 4;
            }
        }

        foreach (var term in terms)
        {
            if (stepId.Contains(term))
                score += 12;
            if (title.Contains(term))
                score += 10;
            if (keywords.Contains(term))
                score += 8;
            if (summary.Contains(term))
                score += 5;
            foreach (var bullet in chunk.Bullets)
            {
                if (bullet.ToLowerInvariant().Contains(term))
                    score += 3;
            }
        }

        return score;
    }
}
