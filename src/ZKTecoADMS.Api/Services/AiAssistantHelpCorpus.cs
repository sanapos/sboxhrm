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
        if (parsedMode is not ("basic" or "advanced"))
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
            Title: "Các báo cáo",
            Summary:
            "Toàn bộ báo cáo tại menu Báo cáo: chấm công, phạt, ứng lương, thu chi, nghỉ phép, tài sản.",
            Bullets:
            [
                "Tổng hợp chấm công · Tổng hợp theo ca",
                "Tổng hợp lương (menu Tính lương)",
                "Báo cáo phạt · Ứng lương · Thu chi · Nghỉ phép · Tài sản",
            ],
            Tip: "Phiếu hủy/từ chối không tính vào báo cáo ứng lương, phạt và nghỉ phép.",
            Keywords: "báo cáo tổng hợp chấm công tổng hợp lương báo cáo phạt ứng lương thu chi nghỉ phép tài sản dashboard",
            ModuleCode: "Dashboard",
            ActionTags: ["nav_dashboard"]),

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
            Title: "Góp ý / Khiếu nại",
            Summary:
            "Tiếp nhận phản ánh, góp ý ẩn danh hoặc công khai từ nhân viên; quản lý phản hồi và theo dõi xử lý.",
            Bullets:
            [
                "Menu: Phản ánh / Ý kiến",
                "NV gửi góp ý từ app (ẩn danh hoặc có tên)",
                "Quản lý xem, trả lời và đóng phiếu",
                "Theo dõi trạng thái đã xử lý / chờ xử lý",
            ],
            Tip: "Khuyến khích góp ý ẩn danh để nhận phản hồi trung thực từ tập thể.",
            Keywords: "góp ý khiếu nại phản ánh ý kiến ẩn danh phản hồi xử lý",
            ModuleCode: "Feedback",
            ActionTags: ["nav_feedback", "nav_feedback_create"]),

        new(
            Mode: "advanced",
            StepId: "meal",
            Title: "Chấm cơm",
            Summary:
            "Ghi nhận suất ăn / chấm cơm theo ca hoặc theo ngày, phục vụ kiểm soát chi phí suất ăn.",
            Bullets:
            [
                "Menu: Chấm cơm",
                "Cấu hình suất ăn theo ca (nếu có)",
                "NV hoặc quản lý ghi nhận suất ăn",
                "Đối soát theo tháng với báo cáo nhân sự",
            ],
            Tip: "Liên kết chấm cơm với ca làm việc để tránh ghi nhận trùng.",
            Keywords: "chấm cơm suất ăn cơm trưa cơm ca đối soát suất ăn",
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
