using System.Text;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Embedded Vietnamese help chunks aligned with flutter_client/lib/utils/landing_usage_guide.dart.
/// </summary>
public sealed record HelpChunk(
    string Mode,
    string StepId,
    string Title,
    string Summary,
    string[] Bullets,
    string Tip,
    string Keywords,
    string? ModuleCode,
    string[] ActionTags);

public static class AiAssistantHelpCorpus
{
    private const string DeviceMenuPath = "Thiết lập liên kết → Máy chủ đám mây";
    private const string DeviceServerHost = "103.133.224.176";
    private const string DeviceServerPort = "7070";

    private static readonly IReadOnlyList<HelpChunk> AllChunks = BuildAll();

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

        var parsedMode = parts[0].ToLowerInvariant();
        if (parsedMode is not ("basic" or "advanced" or "pos"))
            return false;

        var parsedStepId = parts[1];
        if (string.IsNullOrWhiteSpace(parsedStepId))
            return false;

        var exists = AllChunks.Any(c =>
            string.Equals(c.Mode, parsedMode, StringComparison.OrdinalIgnoreCase) &&
            string.Equals(c.StepId, parsedStepId, StringComparison.OrdinalIgnoreCase));
        if (!exists)
            return false;

        mode = parsedMode;
        stepId = parsedStepId;
        return true;
    }

    private static IReadOnlyList<HelpChunk> BuildAll() =>
    [
        // --- Basic ---
        new(
            Mode: "basic",
            StepId: "register",
            Title: "Đăng ký phần mềm",
            Summary:
            "Truy cập sboxhrm.com, chọn Đăng ký doanh nghiệp. Điền tên cửa hàng, mã đăng nhập (chỉ chữ và số liền, không dấu), email, số điện thoại và mật khẩu. Chọn gói dịch vụ để kích hoạt tài khoản quản trị.",
            Bullets:
            [
                "Đường dẫn: sboxhrm.com → Đăng ký",
                "Mã đăng nhập cửa hàng: tối đa 20 ký tự, viết thường a–z và 0–9",
                "Nhận mã cửa hàng (Store ID) sau khi đăng ký thành công",
                "Đăng nhập web/app bằng mã cửa hàng + tài khoản admin",
            ],
            Tip: "Dùng email và số điện thoại thật để nhận hỗ trợ kích hoạt nhanh.",
            Keywords: "đăng ký phần mềm sbox sana doanh nghiệp cửa hàng store id mã đăng nhập kích hoạt tài khoản admin",
            ModuleCode: null,
            ActionTags: []),

        new(
            Mode: "basic",
            StepId: "employees",
            Title: "Thêm nhân viên",
            Summary:
            "Vào Hồ sơ nhân sự để tạo danh sách nhân viên: thêm từng người hoặc import Excel. Gán phòng ban, chức vụ, mã nhân viên trước khi phân ca và đồng bộ máy chấm công.",
            Bullets:
            [
                "Menu: Hồ sơ nhân sự",
                "Thêm thủ công hoặc import Excel (tải mẫu trong màn hình)",
                "Gán phòng ban, chức vụ, mã nhân viên",
                "Cập nhật lương cơ bản tại Thiết lập lương (bước sau)",
            ],
            Tip: "Import Excel giúp thêm hàng loạt nhân viên nhanh hơn nhập tay.",
            Keywords: "thêm nhân viên hồ sơ nhân sự import excel phòng ban chức vụ mã nhân viên hr",
            ModuleCode: "Employee",
            ActionTags: ["nav_employees"]),

        new(
            Mode: "basic",
            StepId: "shifts",
            Title: "Cấu hình ca",
            Summary:
            "Tạo ca làm việc tại Cài đặt → Thiết lập ca. Sau đó vào Lịch làm việc để phân ca cho từng nhân viên hoặc cả phòng ban.",
            Bullets:
            [
                "Cài đặt → Thiết lập ca: tạo ca sáng/chiều/đêm, ca xoay",
                "Menu Lịch làm việc: phân ca theo ngày/tuần/tháng",
                "Hỗ trợ ca qua đêm và lịch xoay tuần",
                "Duyệt lịch tại Duyệt lịch làm việc (nếu bật quy trình duyệt)",
            ],
            Tip: "Dùng \"Nhân bản ca\" để tạo nhanh ca tương tự mà không nhập lại.",
            Keywords: "cấu hình ca thiết lập ca phân ca lịch làm việc ca sáng ca đêm ca xoay duyệt lịch",
            ModuleCode: "WorkSchedule",
            ActionTags: ["nav_work_schedule"]),

        new(
            Mode: "basic",
            StepId: "salary",
            Title: "Thiết lập lương",
            Summary:
            "Cấu hình lương cho từng nhân viên và chính sách tính lương: phụ cấp, phạt, bảo hiểm, thuế TNCN. Cuối kỳ xem Tổng hợp lương và Phiếu lương.",
            Bullets:
            [
                "Hồ sơ nhân sự → Thiết lập lương: lương cơ bản từng NV",
                "Cài đặt → Phụ cấp, Phạt, Bảo hiểm, Thuế TNCN",
                "Báo cáo → Tổng hợp lương: bảng lương theo kỳ",
                "Nhân viên xem Phiếu lương trên app",
            ],
            Tip: "Thiết lập chính sách phạt đi trễ/về sớm trước khi vận hành chấm công.",
            Keywords: "thiết lập lương lương cơ bản phụ cấp bảo hiểm thuế tncn tổng hợp lương phiếu lương bảng lương",
            ModuleCode: "Payslip",
            ActionTags: ["nav_payslip", "nav_payroll"]),

        new(
            Mode: "basic",
            StepId: "device_connect",
            Title: "Kết nối máy chấm công",
            Summary:
            "Cấu hình hai phía: trên máy ZKTeco nhập máy chủ ADMS cloud; trên phần mềm thêm serial máy và theo dõi trạng thái online.",
            Bullets:
            [
                $"Trên máy: {DeviceMenuPath}",
                $"Địa chỉ máy chủ: {DeviceServerHost} · Port: {DeviceServerPort}",
                "Trên phần mềm: Cài đặt → Máy chấm công → Thêm máy (SN hoặc quét mã)",
                "Máy online sẽ tự xuất hiện, dữ liệu chấm công đồng bộ real-time",
            ],
            Tip: "Chưa kết nối được? Gọi hotline 0973 024 042 — hỗ trợ từ xa qua Zalo.",
            Keywords: "kết nối máy chấm công zkteco adms cloud serial máy chủ đám mây online đồng bộ",
            ModuleCode: "Attendance",
            ActionTags: ["nav_attendance"]),

        new(
            Mode: "basic",
            StepId: "device_users",
            Title: "Nhân viên chấm công & vân tay",
            Summary:
            "Đồng bộ nhân viên từ hồ sơ xuống máy chấm công, sau đó đăng ký vân tay hoặc khuôn mặt trên thiết bị ZKTeco.",
            Bullets:
            [
                "Menu: Nhân sự chấm công",
                "Đồng bộ danh sách NV từ Hồ sơ nhân sự xuống máy",
                "Đăng ký vân tay / khuôn mặt trên máy ZKTeco",
                "Kiểm tra Chấm công thô để xác nhận log vào/ra",
            ],
            Tip: "Mã nhân viên trên máy phải trùng mã trong hồ sơ để đồng bộ chính xác.",
            Keywords: "nhân viên chấm công vân tay khuôn mặt đồng bộ máy zkteco nhân sự chấm công chấm công thô",
            ModuleCode: "Attendance",
            ActionTags: ["nav_attendance", "nav_attendance_history"]),

        new(
            Mode: "basic",
            StepId: "mobile_attendance",
            Title: "Chấm công Mobile & duyệt",
            Summary:
            "Bật chấm công bằng điện thoại (GPS, WiFi, Face ID). Nhân viên đăng ký thiết bị; quản lý duyệt tại Duyệt chấm công.",
            Bullets:
            [
                "Cài đặt → Chấm công mobile: GPS, WiFi, vùng chấm công",
                "Menu: Đăng ký chấm công Mobile",
                "NV chấm công tại menu Chấm công Mobile",
                "Quản lý duyệt tại Duyệt chấm công",
            ],
            Tip: "Nên bật WiFi/GPS cửa hàng để chống chấm công ngoài vùng.",
            Keywords: "chấm công mobile gps wifi face id đăng ký thiết bị duyệt chấm công vùng chấm công",
            ModuleCode: "Attendance",
            ActionTags: ["nav_attendance", "nav_attendance_correction"]),

        new(
            Mode: "basic",
            StepId: "penalty_ticket",
            Title: "Tạo phiếu phạt",
            Summary:
            "Hệ thống tự sinh phiếu phạt từ chấm công hoặc tạo thủ công tại Tài chính → Phiếu phạt.",
            Bullets:
            [
                "Cài đặt → Phạt: mức phạt đi trễ, về sớm, tái phạm",
                "Tài chính → Phiếu phạt",
                "Duyệt / hủy / từ chối phiếu theo quy trình",
                "Báo cáo → Báo cáo phạt",
            ],
            Tip: "Phiếu đã hủy hoặc từ chối không tính vào báo cáo.",
            Keywords: "tạo phiếu phạt đi trễ về sớm tái phạm tài chính duyệt phạt báo cáo phạt",
            ModuleCode: "PenaltyTickets",
            ActionTags: ["nav_penalty"]),

        new(
            Mode: "basic",
            StepId: "advance",
            Title: "Tạo phiếu ứng lương",
            Summary:
            "Nhân viên gửi yêu cầu ứng lương trên app; quản lý duyệt tại Tài chính → Ứng lương.",
            Bullets:
            [
                "Tài chính → Ứng lương: tạo & duyệt phiếu",
                "NV tạo yêu cầu trên app mobile",
                "Theo dõi số tiền đã ứng, còn nợ",
                "Báo cáo → Báo cáo ứng lương",
            ],
            Tip: "Khi chi ứng lương qua Thu chi, hệ thống tự cập nhật trạng thái phiếu.",
            Keywords: "ứng lương phiếu ứng tạm ứng tài chính duyệt ứng lương báo cáo ứng lương",
            ModuleCode: "AdvanceRequests",
            ActionTags: ["nav_advance", "nav_advance_create"]),

        new(
            Mode: "basic",
            StepId: "bonus_ticket",
            Title: "Tạo phiếu thưởng",
            Summary:
            "Ghi nhận thưởng tại Tài chính → Phiếu thưởng. Số tiền thưởng được tính vào bảng lương kỳ tương ứng.",
            Bullets:
            [
                "Tài chính → Phiếu thưởng",
                "Tạo phiếu thưởng theo nhân viên, kỳ, lý do",
                "Duyệt phiếu trước khi tính lương",
                "Hiển thị trong Tổng hợp lương",
            ],
            Tip: "Tạo phiếu thưởng trước khi chốt bảng lương tháng.",
            Keywords: "phiếu thưởng tạo thưởng tài chính duyệt thưởng bảng lương tổng hợp lương",
            ModuleCode: "BonusPenalty",
            ActionTags: ["nav_bonus_penalty"]),

        new(
            Mode: "basic",
            StepId: "cash",
            Title: "Thu chi",
            Summary:
            "Ghi sổ thu chi quỹ tiền mặt tại Tài chính → Thu chi. Liên kết phiếu ứng lương và phiếu phạt khi thu/chi thực tế.",
            Bullets:
            [
                "Tài chính → Thu chi: ghi thu, ghi chi theo ngày",
                "Liên kết phiếu ứng lương khi chi ứng",
                "Liên kết phiếu phạt khi thu phạt",
                "Báo cáo → Báo cáo thu chi",
            ],
            Tip: "Ghi thu chi đúng ngày giúp đối soát quỹ và báo cáo chính xác.",
            Keywords: "thu chi quỹ tiền mặt ghi thu ghi chi tài chính đối soát báo cáo thu chi",
            ModuleCode: "CashTransaction",
            ActionTags: ["nav_cash"]),

        new(
            Mode: "basic",
            StepId: "reports",
            Title: "Cách xem báo cáo HRM",
            Summary:
            "Mở nhóm menu Báo cáo, chọn khoảng ngày, lọc phòng ban/NV. Xuất Excel khi gửi kế toán. Phiếu hủy/từ chối không tính vào số liệu.",
            Bullets:
            [
                "Tổng hợp chấm công · Tổng hợp theo ca · Đi trễ / Về sớm",
                "Tính lương / Tổng hợp lương · Phiếu lương",
                "Báo cáo phạt · Ứng lương · Thu chi · Nghỉ phép · Công tác phí · Tài sản",
                "Bán hàng: tab POS → Báo cáo POS (doanh thu, tồn, cuối ngày…)",
            ],
            Tip: "Số liệu lệch: kiểm tra kiểu chấm công + lịch ca + ân hạn trước khi sửa tay.",
            Keywords: "báo cáo xem báo cáo tổng hợp chấm công tổng hợp lương báo cáo phạt ứng lương thu chi nghỉ phép tài sản dashboard xuất excel",
            ModuleCode: "Dashboard",
            ActionTags: ["nav_dashboard", "nav_attendance_summary", "nav_leave_report", "nav_cash_report"]),

        // --- Advanced ---
        new(
            Mode: "advanced",
            StepId: "work_schedule",
            Title: "Lịch làm việc",
            Summary:
            "Phân ca, đổi ca và theo dõi lịch làm việc theo tuần/tháng cho từng nhân viên hoặc phòng ban.",
            Bullets:
            [
                "Menu: Lịch làm việc",
                "Phân ca theo ngày, tuần, tháng",
                "NV gửi yêu cầu đổi ca tại Đổi ca làm việc",
                "Quản lý duyệt tại Duyệt lịch làm việc",
            ],
            Tip: "Nên phân ca trước đầu kỳ để chấm công và tính lương chính xác.",
            Keywords: "lịch làm việc phân ca đổi ca duyệt lịch làm việc ca tuần tháng",
            ModuleCode: "WorkSchedule",
            ActionTags: ["nav_work_schedule", "nav_shift_change"]),

        new(
            Mode: "advanced",
            StepId: "kpi",
            Title: "KPI",
            Summary:
            "Thiết lập chỉ tiêu KPI, giao việc đánh giá và theo dõi kết quả theo kỳ cho từng nhân viên/phòng ban.",
            Bullets:
            [
                "Menu: KPI (Quản lý Vận hành)",
                "Tạo chỉ tiêu, mức đạt và trọng số",
                "Ghi nhận kết quả thực tế theo kỳ",
                "Dùng trong đánh giá hiệu suất và thưởng",
            ],
            Tip: "Gắn KPI với phiếu thưởng để tự động hóa ghi nhận thành tích.",
            Keywords: "kpi chỉ tiêu đánh giá hiệu suất trọng số quản lý vận hành thưởng",
            ModuleCode: "KPI",
            ActionTags: ["nav_kpi"]),

        new(
            Mode: "advanced",
            StepId: "bonus",
            Title: "Thưởng",
            Summary:
            "Quản lý thưởng định kỳ, thưởng nóng và thưởng theo KPI — tích hợp vào bảng lương.",
            Bullets:
            [
                "Tài chính → Phiếu thưởng",
                "Tạo theo nhân viên, kỳ, loại thưởng",
                "Duyệt trước khi chốt Tổng hợp lương",
                "Xem lại tại Tổng hợp lương",
            ],
            Tip: "Thưởng đã duyệt mới được cộng vào phiếu lương.",
            Keywords: "thưởng phiếu thưởng thưởng nóng thưởng kpi tổng hợp lương duyệt thưởng",
            ModuleCode: "BonusPenalty",
            ActionTags: ["nav_bonus_penalty"]),

        new(
            Mode: "advanced",
            StepId: "leave",
            Title: "Nghỉ phép",
            Summary:
            "NV tạo đơn nghỉ phép trên app; quản lý duyệt/từ chối. Hệ thống trừ phép năm và tính vào chấm công.",
            Bullets:
            [
                "Menu: Nghỉ phép",
                "NV tạo đơn, đính kèm lý do và ngày nghỉ",
                "Quản lý duyệt / từ chối / hủy phiếu",
                "Báo cáo → Báo cáo nghỉ phép",
            ],
            Tip: "Phiếu từ chối hoặc hủy không tính vào báo cáo nghỉ phép.",
            Keywords: "nghỉ phép đơn nghỉ phép năm duyệt nghỉ phép báo cáo nghỉ phép tạo đơn",
            ModuleCode: "Leave",
            ActionTags: ["nav_leave", "nav_leave_create"]),

        new(
            Mode: "advanced",
            StepId: "penalty",
            Title: "Phạt",
            Summary:
            "Cấu hình mức phạt đi trễ, về sớm, tái phạm và quản lý phiếu phạt tự động từ chấm công.",
            Bullets:
            [
                "Cài đặt → Phạt: quy tắc và mức phạt",
                "Tài chính → Phiếu phạt: tự động & thủ công",
                "Thu phạt qua Thu chi (liên kết phiếu)",
                "Báo cáo → Báo cáo phạt",
            ],
            Tip: "Thiết lập ngưỡng phút đi trễ trước khi vận hành thực tế.",
            Keywords: "phạt mức phạt đi trễ về sớm tái phạm phiếu phạt cài đặt phạt báo cáo phạt",
            ModuleCode: "PenaltyTickets",
            ActionTags: ["nav_penalty"]),

        new(
            Mode: "advanced",
            StepId: "production",
            Title: "Sản lượng",
            Summary:
            "Nhập sản lượng theo nhóm sản phẩm, ca hoặc nhân viên để tính lương khoán/sản phẩm.",
            Bullets:
            [
                "Menu: Sản lượng (Quản lý Vận hành)",
                "Cài đặt → Lương sản phẩm: nhóm SP, đơn giá",
                "Nhập sản lượng theo ngày/ca",
                "Tổng hợp lương tự cộng phần lương SP",
            ],
            Tip: "Khai báo đơn giá bậc thang trước khi nhập sản lượng hàng loạt.",
            Keywords: "sản lượng lương sản phẩm khoán nhóm sản phẩm đơn giá nhập sản lượng quản lý vận hành",
            ModuleCode: "Production",
            ActionTags: []),

        new(
            Mode: "advanced",
            StepId: "asset",
            Title: "Tài sản",
            Summary:
            "Quản lý tài sản, thiết bị công ty: cấp phát, thu hồi, bảo hành và theo dõi người giữ.",
            Bullets:
            [
                "Menu: Tài sản (Quản lý Vận hành)",
                "Thêm tài sản, mã, ngày mua, bảo hành",
                "Gán tài sản cho nhân viên/phòng ban",
                "Báo cáo → Báo cáo tài sản",
            ],
            Tip: "Ghi nhận ngày hết bảo hành để nhận nhắc trước hạn.",
            Keywords: "tài sản thiết bị cấp phát thu hồi bảo hành báo cáo tài sản quản lý vận hành",
            ModuleCode: "Asset",
            ActionTags: ["nav_assets"]),

        new(
            Mode: "advanced",
            StepId: "communication",
            Title: "Truyền thông",
            Summary:
            "Đăng tin nội bộ, thông báo, nội quy và bản tin tới toàn bộ hoặc từng nhóm nhân viên.",
            Bullets:
            [
                "Menu: Truyền thông",
                "Tạo bài viết, ghim tin quan trọng",
                "Gửi thông báo push tới app NV",
                "NV xem trên Tổng quan và mục Truyền thông",
            ],
            Tip: "Dùng truyền thông để thông báo chính sách chấm công và lương mới.",
            Keywords: "truyền thông thông báo nội bộ bản tin push tin tức nội quy",
            ModuleCode: "Communication",
            ActionTags: ["nav_communication"]),

        new(
            Mode: "advanced",
            StepId: "feedback",
            Title: "Kiến nghị / Khiếu nại",
            Summary:
            "Nhân viên gửi khiếu nại / kiến nghị / góp ý (có thể ẩn danh); người xử lý tiếp nhận, giao việc, trao đổi, giải quyết theo hạn; người gửi đánh giá hài lòng.",
            Bullets:
            [
                "Gửi: loại phiếu, chủ đề, mức độ, ảnh; tới hòm thư chung hoặc 1 quản lý; có mã phiếu KN-yyMM-xxxx",
                "Ẩn danh: không ai (kể cả quản trị) thấy người gửi; lọc theo người gửi không trả phiếu ẩn danh",
                "Hạn xử lý: Khẩn 1 ngày, Cao 2 ngày, Bình thường 3 ngày, Thấp 7 ngày",
                "Người xử lý: Tiếp nhận, giao người xử lý, ghi chú nội bộ, Đã giải quyết / Đóng",
                "Người gửi: đánh giá 1–5 sao, mở lại trong 30 ngày, thu hồi khi chưa tiếp nhận",
                "Tab Báo cáo: tỷ lệ đúng hạn, thời gian phản hồi / giải quyết, mức hài lòng, chủ đề, người xử lý",
            ],
            Tip: "Nhân viên chỉ thấy phiếu của mình; quản lý thấy hòm thư chung và phiếu gửi / giao cho mình.",
            Keywords: "góp ý khiếu nại kiến nghị phản ánh ý kiến ẩn danh phản hồi xử lý hạn xử lý đánh giá hài lòng báo cáo",
            ModuleCode: "Feedback",
            ActionTags: ["nav_feedback", "nav_feedback_create"]),

        new(
            Mode: "advanced",
            StepId: "meal",
            Title: "Chấm cơm",
            Summary:
            "Máy chấm công đặt ở căn tin ghi suất ăn; mỗi lượt chấm in 1 phiếu ăn; tổng hợp số người ăn trong ngày, báo cáo suất và tiền ăn từng người để thu công nợ.",
            Bullets:
            [
                "Menu: Chấm cơm → Quản lý buổi ăn: giờ Sáng/Trưa/Tối + giá suất (chấm sớm/trễ tối đa 30 phút, ngoài khung giờ không tính)",
                "Máy chấm công loại «Chấm cơm» đặt tại căn tin; mở «Trạm in phiếu ăn» trên máy tính/POS cạnh đó để tự in phiếu",
                "Căn tin (quyền Sửa module Chấm cơm) nhập thực đơn ở tab Hôm nay hoặc Căn tin; nhân viên xem thực đơn hôm nay",
                "Tab Căn tin: số suất theo buổi, đăng ký chưa ăn, ăn không đăng ký; tab Báo cáo: suất + tiền từng người, xuất Excel",
                "Tab Công nợ: Tính tiền cơm theo tháng, ghi nhận nhân viên trả tiền",
            ],
            Tip: "Giá suất chốt tại thời điểm chấm, đổi giá sau không làm sai tiền các ngày trước.",
            Keywords: "chấm cơm suất ăn cơm trưa cơm ca phiếu ăn in phiếu căn tin thực đơn menu hôm nay tiền ăn công nợ",
            ModuleCode: "Meal",
            ActionTags: ["nav_meal", "nav_meal_register"]),

        new(
            Mode: "advanced",
            StepId: "employee_account",
            Title: "Tạo tài khoản nhân viên",
            Summary:
            "Tạo tài khoản đăng nhập app/web cho nhân viên, gán quyền và liên kết với hồ sơ nhân sự.",
            Bullets:
            [
                "Cài đặt → Tài khoản",
                "Thêm tài khoản, chọn nhân viên HR tương ứng",
                "Gán vai trò tại Cài đặt → Phân quyền",
                "NV đăng nhập bằng mã cửa hàng + tài khoản được cấp",
            ],
            Tip: "Mỗi nhân viên nên có một tài khoản riêng, không dùng chung mật khẩu.",
            Keywords: "tài khoản nhân viên đăng nhập phân quyền vai trò cài đặt tài khoản",
            ModuleCode: "Employee",
            ActionTags: ["nav_employees"]),

        new(
            Mode: "basic",
            StepId: "daily_ops",
            Title: "Quy trình hàng ngày & cuối tháng",
            Summary:
            "Sáng duyệt phép/đổi ca; trong ngày theo dõi chấm công; cuối tháng duyệt hết phiếu rồi chốt Tổng hợp lương.",
            Bullets:
            [
                "Sáng: Dashboard / chuông thông báo — duyệt phép, đổi ca, chấm mobile",
                "Trong ngày: Chấm công thô nếu thiếu log; tạo thưởng/phạt/ứng khi phát sinh",
                "Trước chốt 2–3 ngày: duyệt hết phép, OT, thưởng, phạt, ứng",
                "Ngày chốt: Tổng hợp theo ca → Tính lương → gửi phiếu lương trên app",
            ],
            Tip: "Nên có 1 người duyệt hàng ngày và 1 người chốt kỳ — tránh dồn cuối tháng.",
            Keywords: "hàng ngày cuối tháng quy trình ngày duyệt đơn vận hành hrm chốt lương",
            ModuleCode: "Dashboard",
            ActionTags: ["nav_dashboard", "nav_attendance_summary"]),

        new(
            Mode: "basic",
            StepId: "common_hrm",
            Title: "Tình huống HRM thường gặp",
            Summary:
            "Đi trễ phạt oan → tăng ân hạn ca. Thiếu chấm → sai kiểu chấm công. Quên chấm → phiếu sửa giờ. Máy Offline → mạng + serial.",
            Bullets:
            [
                "Phạt dù vào sớm vài phút: ân hạn trên Thiết lập ca",
                "Chỉ chấm 1 lần/ngày: chọn Chấm vào (đủ ca) trong Thiết lập lương",
                "Quên chấm: Sửa giờ / Báo quên — quản lý duyệt, không xóa log máy",
                "Máy ZK Offline: mạng máy + SN tại Cài đặt → Máy chấm công; hotline 0973 024 042",
                "Quên mật khẩu: màn đăng nhập → Quên mật khẩu (email đã đăng ký)",
            ],
            Tip: "Sửa gốc (ca, mode, ân hạn) trước khi xóa hàng loạt phiếu phạt.",
            Keywords: "đi trễ quên chấm thiếu chấm quên mật khẩu máy offline tình huống phạt oan",
            ModuleCode: "Attendance",
            ActionTags: ["nav_attendance", "nav_attendance_correction"]),

        new(
            Mode: "advanced",
            StepId: "attendance_modes",
            Title: "Kiểu chấm công",
            Summary:
            "Chấm vào & ra cần đủ cặp. Chỉ chấm vào (đủ ca): 1 lần = đủ ca, tính đi trễ, không phạt quên chấm ra. Đổi mode xong mở lại Tổng hợp theo ca.",
            Bullets:
            [
                "Cấu hình tại Thiết lập lương → ô Chấm công",
                "Quán chỉ chấm 1 lần trên máy: chọn Chấm vào (đủ ca)",
                "Chấm 2 lần bất kỳ trong ngày: ≥2 log = 1 công, không tính trễ/sớm theo ca",
            ],
            Tip: "Sai mode là nguyên nhân hay gặp của «Thiếu chấm» và phạt quên chấm oan.",
            Keywords: "kiểu chấm công checkin chỉ chấm vào thiếu chấm mode đủ ca",
            ModuleCode: "Attendance",
            ActionTags: ["nav_attendance_summary"]),

        new(
            Mode: "pos",
            StepId: "pos_devices",
            Title: "Máy thu ngân A6 / A7",
            Summary:
            "A6 Sunmi T1 chạy app POS. A7/web/iOS bán hàng trong app HRM → menu Bán hàng. Cùng mã cửa hàng và quyền PosSell.",
            Bullets:
            [
                "A6: app POS (sbox.sana.vn.pos.flutter) — in USB + màn phụ khách",
                "A7: app HRM (sbox.sana.vn) → Bán hàng",
                "Rút USB/ADB trước khi kiểm tra màn hình phụ khách trên A6",
            ],
            Tip: "Mẫu in theo từng cửa hàng — A6 và A7 cùng store dùng chung catalog.",
            Keywords: "a6 a7 sunmi flutter_pos hrm pos thiết bị thu ngân c20lite",
            ModuleCode: "PosSell",
            ActionTags: ["nav_pos_sell"]),

        new(
            Mode: "pos",
            StepId: "pos_setup",
            Title: "Thiết lập POS lần đầu",
            Summary:
            "Thứ tự: ngành hàng → thiết lập cửa hàng → hàng hóa → bàn (F&B) → máy in → bán thử.",
            Bullets:
            [
                "Cài đặt → Ngành hàng & bán hàng, Thiết lập cửa hàng (VAT, VietQR)",
                "Menu Hàng hóa: danh mục + món/SP",
                "F&B: Quản lý bàn / phòng trước khi mở order",
                "Phân quyền thu ngân / quản kho rồi tạo 1 đơn test",
            ],
            Tip: "Sai ngành hàng thì không thấy sơ đồ bàn / gửi bếp.",
            Keywords: "pos bán hàng thiết lập pos ngành hàng cửa hàng",
            ModuleCode: "PosSell",
            ActionTags: ["nav_pos_sell", "nav_pos_products"]),

        new(
            Mode: "pos",
            StepId: "pos_products",
            Title: "Hàng hóa, giá & combo",
            Summary:
            "Menu Hàng hóa: mã, tên, giá, đơn vị, nhóm. Tắt bán thay vì xóa để giữ lịch sử hóa đơn.",
            Bullets:
            [
                "Thêm sản phẩm / món, gắn ảnh để chọn nhanh",
                "Combo trừ kho: khai báo thành phần nguyên liệu",
                "Đơn đang mở giữ giá lúc thêm món",
            ],
            Tip: "Mã hàng ngắn, không dấu — dễ gõ và in tem.",
            Keywords: "hàng hóa sản phẩm giá bán danh mục món combo",
            ModuleCode: "PosProducts",
            ActionTags: ["nav_pos_products"]),

        new(
            Mode: "pos",
            StepId: "pos_tables",
            Title: "Bàn / phòng & đặt lịch",
            Summary:
            "Nhà hàng: Cài đặt bàn/phòng rồi bán theo sơ đồ. Salon: menu Đặt lịch. Retail bỏ qua.",
            Bullets:
            [
                "Tạo khu vực rồi thêm bàn; chọn bàn trống → order → thanh toán",
                "Ghép / tách / chuyển bàn theo quyền",
                "Đặt lịch: ngày–giờ–dịch vụ–khách",
            ],
            Tip: "Bàn đang dùng phải thanh toán hoặc trả bàn trước khi gán khách mới.",
            Keywords: "bàn phòng sơ đồ bàn đặt bàn đặt lịch f&b",
            ModuleCode: "PosSell",
            ActionTags: ["nav_pos_sell"]),

        new(
            Mode: "pos",
            StepId: "pos_printers",
            Title: "Máy in & mẫu in",
            Summary:
            "Cài đặt → Máy in và Mẫu in. Hóa đơn K80, tem nhỏ, phiếu bếp riêng. Mặc định theo cửa hàng.",
            Bullets:
            [
                "A6: USB/TSPL qua Print Agent; A7: Bluetooth/LAN/cloud",
                "Đặt mẫu mặc định đúng loại (hóa đơn / bếp / tem)",
                "In thử từ Mẫu in hoặc đơn test",
            ],
            Tip: "A6 và A7 cùng store phải cùng mẫu mặc định — chọn lại ở Mẫu in, không copy tay.",
            Keywords: "máy in mẫu in k80 k58 print agent usb bluetooth",
            ModuleCode: "PosPrinters",
            ActionTags: ["nav_pos_printers"]),

        new(
            Mode: "pos",
            StepId: "pos_kitchen",
            Title: "Gửi bếp & phiếu chế biến",
            Summary:
            "F&B: thêm món → Gửi bếp. Phiếu bếp in giờ gọi ở đầu phiếu. Máy in bếp có thể khác máy hóa đơn.",
            Bullets:
            [
                "Gửi phần món mới sau khi gọi thêm",
                "Gán mẫu phiếu bếp / tem ly là mặc định",
                "Không gửi được: kiểm tra ngành F&B + máy + mẫu bếp",
            ],
            Tip: "In hóa đơn lúc thanh toán; in bếp lúc gọi món.",
            Keywords: "bếp gửi bếp phiếu bếp tem ly kds",
            ModuleCode: "PosSell",
            ActionTags: ["nav_pos_sell", "nav_pos_printers"]),

        new(
            Mode: "pos",
            StepId: "pos_sales",
            Title: "Quy trình bán hàng",
            Summary:
            "Bán hàng → chọn SP/bàn → SL, giảm giá → chọn khách (điểm, công nợ, HĐĐT có MST) → thanh toán → in HĐ. Kho chỉ trừ lúc thanh toán. Cần quyền Duyệt PosSell; bật Ca thu ngân thì phải mở ca.",
            Bullets:
            [
                "A7/HRM/web: menu Bán hàng; A6: app POS",
                "Ca thu ngân: Menu ⋮ → Ca thu ngân → Mở ca trước khi thu tiền",
                "Chiết khấu / đổi giá cần quyền duyệt PosSell",
                "Chip «Xuất HĐĐT» trên màn thanh toán; sau thanh toán báo Đã xuất / Chưa xuất được / Chờ ký",
                "Mất mạng: bấm Thanh toán lại an toàn — không tạo đơn / trừ kho hai lần",
                "Đơn hàng: in lại, hủy; menu Trả hàng bán gắn đơn gốc",
            ],
            Tip: "Tài khoản chỉ có quyền tạo đơn thì order / gửi bếp được nhưng không thanh toán — cần Approve PosSell.",
            Keywords: "bán hàng thu ngân thanh toán hóa đơn order pos ca thu ngân mở ca",
            ModuleCode: "PosSell",
            ActionTags: ["nav_pos_sell"]),

        new(
            Mode: "pos",
            StepId: "pos_customers",
            Title: "Khách hàng POS",
            Summary:
            "Menu Khách hàng POS. Chọn khách trên đơn để tích điểm hoặc ghi công nợ.",
            Bullets:
            [
                "Thêm khách bằng SĐT",
                "Thu nợ sau tại khách hoặc Báo cáo công nợ",
            ],
            Tip: "Không gắn khách thì đơn vẫn bán được nhưng không tích điểm.",
            Keywords: "khách hàng điểm công nợ khách crm pos",
            ModuleCode: "PosSell",
            ActionTags: ["nav_pos_sell"]),

        new(
            Mode: "pos",
            StepId: "pos_inventory",
            Title: "Kho: nhập, xuất, kiểm kê",
            Summary:
            "Tồn tăng: nhập NCC hoàn thành, trả hàng bán, hủy đơn. Tồn giảm: thanh toán đơn, xuất hủy, xuất dùng nội bộ, trả hàng nhập. Mọi biến động ghi Thẻ kho.",
            Bullets:
            [
                "Nhập hàng NCC → Hoàn thành (phiếu tạm chưa cộng tồn); giá vốn bình quân gia quyền",
                "Hủy phiếu nhập: trừ lại tồn, trả giá vốn về như trước (cần đủ tồn)",
                "Xuất hủy / Xuất dùng nội bộ: Hoàn thành mới trừ tồn",
                "Kiểm kho: nhập số đếm ngay khi đếm → Hoàn thành; chỉ cộng/trừ chênh lệch nên hàng bán sau lúc đếm vẫn đúng",
                "Hàng hóa → chọn hàng → Thẻ kho: xem ai, chứng từ nào, tồn sau giao dịch",
            ],
            Tip: "Chỉnh tồn cho đúng thực tế bằng Kiểm kho, không sửa tay ô tồn trong form hàng hóa.",
            Keywords: "kho nhập hàng tồn kho kiểm kho kiểm kê ncc xuất hủy xuất nội bộ thẻ kho giá vốn",
            ModuleCode: "PosProducts",
            ActionTags: ["nav_pos_products", "nav_pos_reports"]),

        new(
            Mode: "pos",
            StepId: "pos_stock_rules",
            Title: "Nguyên tắc tồn kho (giữ chỗ, bán âm)",
            Summary:
            "Tồn khả dụng = tồn kho − phần giữ chỗ cho bàn / đơn tạm / đơn online chưa thanh toán. Đơn mở chỉ giữ chỗ; thanh toán (hoặc xác nhận COD / nhận CK Tingee) mới trừ kho.",
            Bullets:
            [
                "Combo trừ thành phần (+ combo nếu bật «Quản lý tồn kho combo»); món định lượng trừ nguyên liệu; topping trừ theo SL",
                "ĐVT lớn quy về ĐVT cơ bản; dịch vụ không trừ kho; hàng lô/HSD xuất lô hết hạn sớm nhất trước",
                "Bán âm: Cài đặt → Ngành hàng & bán hàng → «Cho phép bán khi hết hàng / tồn âm»",
                "Phiếu xuất hủy/nội bộ không vượt tồn thực và không lấy phần đang giữ chỗ (khi tắt bán âm)",
                "Phiếu xuất kho / báo kho in từ màn bán chỉ là phiếu soạn hàng — không trừ kho lần hai",
                "Hai người cùng sửa một mặt hàng: một bên báo «Tồn kho vừa được thay đổi… thao tác lại» — không ghi đè sai",
                "Giữ chỗ tự đối soát lại mỗi đêm 3 giờ sáng",
            ],
            Tip: "Tồn âm do bán trước khi nhập, khai sai combo / định lượng, hoặc đang bật bán âm → nhập bù / kiểm kho.",
            Keywords: "tồn khả dụng giữ chỗ bán âm tồn âm hết hàng không đủ tồn kho combo định lượng lô hsd fefo",
            ModuleCode: "PosProducts",
            ActionTags: ["nav_pos_products", "nav_pos_sell"]),

        new(
            Mode: "pos",
            StepId: "pos_einvoice",
            Title: "Hóa đơn điện tử: kết nối & xuất",
            Summary:
            "Cài đặt → Hóa đơn điện tử: Viettel SInvoice / Easy Invoice / MISA meInvoice / VNPT Invoice. Lưu → Kiểm tra kết nối. Xuất bằng chip «Xuất HĐĐT» khi thanh toán hoặc từ Đơn hàng.",
            Bullets:
            [
                "Viettel: tài khoản API, MST, mẫu 1/001, ký hiệu; Easy: Pattern đúng portal, Serial thường trống",
                "MISA: AppID + tài khoản meInvoice + ký hiệu đầy đủ (1C25TAA), ký HSM hoặc máy tính tiền",
                "VNPT: địa chỉ web service riêng, Account/ACpass, tài khoản phát hành, mẫu số, ký hiệu",
                "«Mặc định xuất» + tắt hỏi thu ngân: mọi đơn tự xuất, kể cả đơn online / Tingee",
                "Khách công ty: chọn khách có MST, địa chỉ, email trước khi thanh toán",
                "Bill in thêm ký hiệu, số, mã CQT, mã tra cứu + QR tra cứu (tắt được trong cấu hình)",
            ],
            Tip: "HĐĐT lỗi không làm hỏng đơn — màn bán báo lỗi, xuất lại trong Quản lý HĐĐT.",
            Keywords: "hóa đơn điện tử viettel easy misa vnpt einvoice kết nối cấu hình xuất hđđt qr tra cứu",
            ModuleCode: "PosEInvoice",
            ActionTags: ["nav_pos_sell"]),

        new(
            Mode: "pos",
            StepId: "pos_einvoice_manage",
            Title: "Quản lý HĐĐT",
            Summary:
            "Báo cáo POS → Hóa đơn điện tử (hoặc Cài đặt → Hóa đơn điện tử → Quản lý): xem PDF, gửi qua Zalo/email, gửi bản nháp, thay thế, hủy, đồng bộ, tải danh sách từ hãng, mở portal hãng, báo cáo.",
            Bullets:
            [
                "Gửi qua ứng dụng khác: đính kèm PDF + số, mã tra cứu, link tra cứu",
                "Bản nháp gửi khách kiểm tra trước khi phát hành (Viettel, Easy, MISA)",
                "Thay thế: sửa tên / MST / địa chỉ / email người mua; lỗi thì HĐ gốc giữ nguyên",
                "Hủy: NĐ 70/2025 — HĐ đã gửi CQT thường phải thay thế, hãng có thể từ chối hủy",
                "Đồng bộ hàng loạt tối đa 100 đơn; Tải danh sách từ hãng (Viettel, Easy) để đối chiếu",
            ],
            Tip: "Lỗi thường: sai MST / mẫu / ký hiệu, MISA sai AppID, VNPT ERR:20, Easy lỗi 117 (mẫu MTT chưa mở API).",
            Keywords: "quản lý hóa đơn điện tử thay thế hủy đồng bộ gửi zalo email bản nháp tải danh sách portal",
            ModuleCode: "PosEInvoice",
            ActionTags: ["nav_pos_reports"]),

        new(
            Mode: "pos",
            StepId: "pos_reports",
            Title: "Cách xem báo cáo POS",
            Summary:
            "Menu Báo cáo → Báo cáo POS: chọn khoảng ngày rồi mở từng loại (doanh thu, hàng bán, tồn, PTTT, công nợ, lợi nhuận, cuối ngày…).",
            Bullets:
            [
                "Doanh thu · Hàng hóa bán ra · Doanh thu theo thu ngân",
                "Tồn kho · Nhập hàng · Hàng sắp hết hạn",
                "PTTT · Công nợ · Sổ quỹ · Lợi nhuận · P&L · Voucher",
                "Báo cáo hủy/trả (menu riêng) · Thuế hộ kinh doanh",
            ],
            Tip: "Không thấy một thẻ: thiếu quyền PosReport… trong Phân quyền / gói dịch vụ.",
            Keywords: "báo cáo pos doanh thu tồn kho lợi nhuận 14 báo cáo cuối ngày",
            ModuleCode: "PosSalesReport",
            ActionTags: ["nav_pos_reports"]),

        new(
            Mode: "pos",
            StepId: "pos_eod",
            Title: "Ca thu ngân & tổng kết cuối ngày",
            Summary:
            "Bật «Ca thu ngân (mở ca / đóng két)» thì mỗi thu ngân mở / đóng ca riêng. Cuối ngày: Báo cáo POS → Tổng kết cuối ngày, đối chiếu tiền mặt, QR, công nợ.",
            Bullets:
            [
                "Menu ⋮ màn bán → Ca thu ngân → Mở ca / Đóng ca, đếm két",
                "Đóng bàn / đơn đang mở trước khi chốt",
                "Đối soát ngăn kéo với cột tiền mặt; QR với sao kê",
                "Xem hủy/trả và PTTT nếu lệch tiền",
            ],
            Tip: "Đừng bù tay vào quỹ trước khi rà Đơn hàng trong ca.",
            Keywords: "cuối ngày chốt ca tổng kết end of day tiền mặt ca thu ngân mở ca đóng két",
            ModuleCode: "PosSalesReport",
            ActionTags: ["nav_pos_reports"]),

        new(
            Mode: "pos",
            StepId: "pos_common",
            Title: "Tình huống POS thường gặp",
            Summary:
            "Không in: máy + mẫu mặc định store. Không thanh toán: thiếu Approve PosSell hoặc chưa mở ca. «Không đủ tồn kho»: bàn / đơn khác đang giữ chỗ.",
            Bullets:
            [
                "HĐ in được / bếp không: gán máy + mẫu phiếu bếp riêng",
                "«Tồn kho vừa được thay đổi… thao tác lại»: người khác vừa bán / nhập cùng hàng — bấm lại",
                "Tồn âm: bán trước khi nhập, khai sai combo / định lượng, hoặc đang bật bán âm",
                "Ai bán / trừ kho: Thẻ kho; ai sửa / xóa đơn: Lịch sử thao tác",
                "HĐĐT lỗi sau thanh toán: đơn vẫn hợp lệ — xuất lại trong Quản lý HĐĐT",
                "Màn phụ A6 trắng: rút USB debug rồi mở lại POS",
            ],
            Tip: "Hotline 0973 024 042 khi Agent USB không nhận job in.",
            Keywords: "không in in sai lệch tiền hủy đơn trả hàng tình huống pos không đủ tồn tồn âm thao tác lại",
            ModuleCode: "PosSell",
            ActionTags: ["nav_pos_sell", "nav_pos_printers", "nav_pos_reports"]),

        new(
            Mode: "pos",
            StepId: "pos_rules",
            Title: "Nguyên tắc chung của phần mềm",
            Summary:
            "Chứng từ Tạm chưa ảnh hưởng kho / quỹ; Hoàn thành mới ghi sổ; muốn đảo ngược thì Hủy. Không xóa dữ liệu đã phát sinh — tắt bán, hủy, trả hàng.",
            Bullets:
            [
                "Mọi thay đổi tồn có dòng Thẻ kho; mọi sửa / xóa đơn có Lịch sử thao tác",
                "Hủy đơn: gỡ doanh thu, hoàn kho, hoàn điểm / voucher / công nợ",
                "Giá trên đơn là giá lúc thêm món",
                "Quyền Xem / Tạo / Sửa / Duyệt theo module; thanh toán, đổi giá, hủy cần Duyệt",
                "Dữ liệu, mẫu in, máy in, cấu hình HĐĐT riêng từng cửa hàng",
            ],
            Tip: "Cuối tháng: kiểm kho hàng chính, đồng bộ HĐĐT hàng loạt, xem tỷ lệ xuất HĐĐT và lợi nhuận.",
            Keywords: "nguyên tắc quy tắc chứng từ tạm hoàn thành hủy xóa thẻ kho phân quyền",
            ModuleCode: "PosSell",
            ActionTags: ["nav_pos_sell"]),
    ];

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
