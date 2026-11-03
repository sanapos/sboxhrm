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
        ["cash"] = new("thu chi quỹ tiền mặt ghi thu ghi chi tài chính đối soát báo cáo thu chi lập phiếu chi lập phiếu thu tạo phiếu chi tạo phiếu thu phiếu chi phiếu thu sổ quỹ", ["nav_cash"]),
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
        ["kpi"] = new("kpi chỉ tiêu đánh giá hiệu suất trọng số quản lý vận hành thưởng thiết lập kpi tạo kpi giao kpi", ["nav_kpi"]),
        ["leave"] = new("nghỉ phép đơn nghỉ phép năm duyệt nghỉ phép báo cáo nghỉ phép tạo đơn", ["nav_leave", "nav_leave_create"]),
        ["meal"] = new("chấm cơm suất ăn cơm trưa cơm ca phiếu ăn in phiếu căn tin thực đơn menu hôm nay tiền ăn công nợ", ["nav_meal", "nav_meal_register"]),
        ["mobile_attendance"] = new("chấm công mobile chấm công điện thoại chấm công trên app gps wifi face id đăng ký thiết bị duyệt chấm công vùng chấm công", ["nav_attendance", "nav_attendance_correction"]),
        ["notifications"] = new("thông báo nhắc việc chuông bật tắt thông báo", []),
        ["org_structure"] = new("phòng ban chức vụ chi nhánh cơ cấu tổ chức bộ phận tạo phòng ban thêm phòng ban phòng ban mới sửa phòng ban trưởng phòng", ["nav_departments"]),
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
        ["pos_sale_pay"] = new("thanh toán khách hàng tích điểm công nợ ghi nợ voucher tiền thối tiền trả khách chuyển khoản qr in hóa đơn xuất hđđt tính tiền cho khách thu tiền khách tính tiền", ["nav_pos_sell"]),
        ["pos_after_sale"] = new("đơn hàng hóa đơn in lại hủy đơn trả hàng hoàn tiền lịch sử hủy trả tra cứu đơn", ["nav_pos_sell", "nav_pos_reports"]),
        ["pos_reports"] = new("báo cáo pos doanh thu tồn kho lợi nhuận 14 báo cáo cuối ngày", ["nav_pos_reports"]),
        ["pos_rules"] = new("nguyên tắc quy tắc chứng từ tạm hoàn thành hủy xóa thẻ kho phân quyền", ["nav_pos_sell"]),
        ["pos_sales"] = new("bán hàng thu ngân chọn hàng quét mã nhiều hóa đơn order pos ca thu ngân mở ca hướng dẫn bán hàng cách bán hàng lên đơn tạo đơn bán", ["nav_pos_sell"]),
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

    private static readonly IReadOnlyList<HelpChunk> AllChunks = [.. Load(), .. ServerChunks()];

    public static IReadOnlyList<HelpChunk> All => AllChunks;

    /// <summary>Mode của bài chỉ có ở máy chủ (app không có bước tương ứng) — không gắn thẻ [[GUIDE:…]].</summary>
    public const string ServerMode = "sbox";

    /// <summary>Bài mở được trong màn Hướng dẫn của app.</summary>
    public static bool HasAppGuide(HelpChunk c) => Modes.Contains(c.Mode, StringComparer.Ordinal);

    /// <summary>
    /// Chức năng chưa có bước trong hướng dẫn của app nhưng hay được hỏi (trước đây «tạo khuyến mãi giờ vàng» ra bài
    /// karaoke, «gia hạn gói» ra bài gym). Tên nút / ô lấy đúng theo màn hình flutter_client (03/11/2026) — đổi màn thì sửa
    /// ở đây; thêm bước vào hướng dẫn của app thì xóa bài tương ứng.
    /// </summary>
    static HelpChunk[] ServerChunks() =>
    [
        new(ServerMode, "pos_promotions", "Tạo chương trình khuyến mãi (giờ vàng, đồng giá, mua X tặng Y…)",
            "Khuyến mãi tự áp vào hóa đơn ở màn bán khi đúng mặt hàng, khung giờ và điều kiện — thu ngân không phải nhập mã.",
            [
                "Mở POS › Khuyến mãi (hoặc Nhiều hơn › Khách hàng › Khuyến mãi; Hàng hóa › menu ⋮ › «Khuyến mãi (giờ vàng, mua X tặng Y…)»)",
                "Bấm «Tạo chương trình», nhập «Tên chương trình», chọn «Loại khuyến mãi»: «Giảm giá theo giờ / mặt hàng», «Mua nhiều giảm giá», «Mua X tặng Y», «Đồng giá combo», «Giảm theo tổng hóa đơn», «Mua kèm giá ưu đãi», «Hàng cận hạn tự giảm»",
                "Nhập mức giảm theo loại: «Giảm» % hoặc «Hoặc bán đồng giá»; «Mua» / «Tặng»; «Số món» + «Giá cả combo»; «Hóa đơn từ» + «Giảm tối đa»",
                "«Áp dụng cho»: «Tất cả hàng», «Theo nhóm hàng», «Mặt hàng cụ thể» hoặc «Hàng có mã vạch»",
                "«Thời gian áp dụng»: «Từ ngày» / «Đến ngày», giờ bắt đầu – kết thúc, chọn thứ trong tuần (không chọn = mọi ngày; giờ kết thúc nhỏ hơn giờ bắt đầu = chạy qua đêm)",
                "«Tùy chọn»: «Đang bật», «Cộng dồn với khuyến mãi khác», «Chỉ khách thành viên», «Áp dụng tại chi nhánh», «Ưu tiên (khi giảm bằng nhau)» → «Lưu»",
                "Danh sách có «Sửa», «Nhân bản», «Xoá»; nút «Hiệu quả» xem tiền đã giảm theo ngày / chương trình",
            ],
            "Tắt «Cộng dồn…» thì mỗi món chỉ lấy chương trình giảm nhiều nhất. Có thể nhờ Trợ lý ảo: «tạo giờ vàng 18h–21h giảm 30% trà sữa».",
            "khuyến mãi giờ vàng happy hour đồng giá mua x tặng y mua 2 tặng 1 giảm giá theo giờ giảm theo hóa đơn mua nhiều giảm giá mua kèm hàng cận hạn chương trình giảm giá tự động giảm giá hiệu quả khuyến mãi sale",
            ["nav_pos_sell"], [], "pos"),
        new(ServerMode, "pos_vouchers", "Tạo và áp mã giảm giá (voucher)",
            "Tạo mã voucher giảm tiền hoặc giảm %; khách đọc mã, thu ngân nhập vào ô «Mã voucher» lúc thanh toán.",
            [
                "Mở Nhiều hơn › Khách hàng › Voucher (hoặc gõ «voucher» vào ô Tìm chức năng)",
                "Bấm «Thêm voucher», nhập «Mã voucher *» và «Tên chương trình»",
                "Chọn «Giảm tiền» hoặc «Giảm %», nhập «Số tiền giảm *» / «Phần trăm giảm *» (giảm % có thêm «Giảm tối đa»)",
                "Nhập «Đơn tối thiểu», «Số lượt tối đa», «Thời gian hiệu lực», bật «Đang hoạt động» → «Lưu»",
                "Danh sách hiện trạng thái «Đang chạy», «Hết hạn», «Hết lượt», «Chưa tới ngày», «Đã tắt» và «Lượt đã dùng»",
                "Khi thanh toán: nhập mã vào ô «Mã voucher» → «Áp dụng» (mã sai báo «Voucher không hợp lệ»)",
            ],
            "Màn Voucher không gửi mã cho khách — tự thông báo mã. Có thể nhờ Trợ lý ảo: «tạo voucher TET2027 giảm 10%».",
            "voucher mã giảm giá coupon phiếu giảm giá tạo mã giảm giá nhập mã giảm giá áp voucher mã khuyến mãi giảm giá khi thanh toán lượt dùng voucher voucher hết hạn code giảm giá",
            ["nav_pos_sell"], [], "pos"),
        new(ServerMode, "pos_stock_transfer", "Chuyển kho giữa các chi nhánh",
            "Lập phiếu chuyển hàng từ chi nhánh dư sang chi nhánh thiếu: kho đi bị trừ khi gửi, kho đến được cộng khi xác nhận nhận.",
            [
                "Gõ «Chuyển kho» vào ô Tìm chức năng (chỉ có khi cửa hàng có từ 2 chi nhánh), hoặc Kho chi nhánh › «Chuyển kho», hoặc tab «Chuyển kho» trong chi tiết chi nhánh",
                "Bấm «Tạo phiếu chuyển», chọn «Kho đi» và «Kho đến»",
                "«Thêm hàng từ kho đi»: tìm hoặc quét mã vạch; dòng «Kho đi còn …» giúp không chuyển quá tồn",
                "Nhập «Ghi chú (tùy chọn)» → «Gửi hàng ngay» hoặc «Lưu nháp» (phiếu nháp mở lại bấm «Gửi hàng»)",
                "Chi nhánh đến nhập «Thực nhận» → «Xác nhận đã nhận»; nhận thiếu thì phần thiếu tự trả về kho đi",
                "Khác: «Hủy & trả hàng về kho đi», «In phiếu chuyển»",
            ],
            "Trong Kho chi nhánh bấm một mặt hàng → «Chuyển hàng về chi nhánh này» để điền sẵn phiếu. Trợ lý ảo cũng lập được phiếu chuyển.",
            "chuyển kho chuyển hàng giữa chi nhánh điều chuyển hàng phiếu chuyển kho luân chuyển hàng kho đi kho đến gửi hàng chi nhánh nhận hàng chuyển kho xác nhận đã nhận chuyển tồn kho chi nhánh thiếu hàng",
            [], [], "pos"),
        new(ServerMode, "pos_reorder_purchase", "Gợi ý nhập hàng và lập phiếu nhập từ nhà cung cấp",
            "SBOX liệt kê hàng có tồn dưới «Tồn tối thiểu», gợi ý số lượng cần nhập và tạo phiếu nhập nháp gom theo từng nhà cung cấp.",
            [
                "Đặt «Tồn tối thiểu» trong thông tin từng hàng hóa để hệ thống biết khi nào cần nhắc",
                "Mở Hàng hóa › menu ⋮ › «Hàng cần nhập thêm» (cần quyền xem báo cáo kho), hoặc báo cáo «Sức khỏe kho» › «Gợi ý nhập hàng»",
                "Mỗi dòng hiện «Tồn … / tối thiểu …»; sửa số ở ô «Nhập», tích chọn mặt hàng muốn nhập",
                "Bấm «Tạo phiếu nhập nháp» — mỗi nhà cung cấp một phiếu",
                "Vào Nhiều hơn › Nhập hàng kiểm tra rồi hoàn thành phiếu — chỉ khi hoàn thành tồn kho mới được cộng",
                "SBOX không có chứng từ «đơn đặt hàng nhà cung cấp» riêng: gửi danh sách cho nhà cung cấp ngoài app, hoặc dùng phiếu nhập nháp",
            ],
            "Hỏi Trợ lý ảo «hàng nào sắp hết cần nhập?» — có thể lập luôn phiếu nhập theo từng nhà cung cấp.",
            "gợi ý nhập hàng hàng cần nhập thêm đặt hàng nhà cung cấp đặt hàng ncc hàng sắp hết tồn tối thiểu phiếu nhập nháp sắp hết hàng cháy hàng reorder lên đơn nhập bổ sung hàng sức khỏe kho",
            ["nav_pos_products"], [], "pos"),
        new(ServerMode, "sys_service_package", "Gói dịch vụ SBOX, hạn sử dụng và gia hạn",
            "Trong app của cửa hàng không có màn xem gói, hạn dùng hay tự gia hạn — gia hạn / đổi gói do SBOX hoặc đại lý thực hiện.",
            [
                "Không có màn «Gói», «Gia hạn» hay nhập mã kích hoạt trong app cửa hàng; gói và license do SBOX / đại lý quản lý",
                "Hệ thống tự nhắc (banner / thông báo) trước hạn 30, 15, 7, 3, 1 và 0 ngày, kèm ngày hết hạn và lời nhắn liên hệ đại lý / nhà cung cấp để gia hạn",
                "Hết hạn: app đăng xuất và báo «Cửa hàng đã hết hạn sử dụng. Vui lòng liên hệ quản trị viên để gia hạn.»",
                "Gia hạn xong có thông báo «Gia hạn license thành công» kèm ngày hiệu lực mới",
                "Chức năng chưa có trong gói: app báo «Gói dịch vụ chưa bao gồm…» — liên hệ SBOX / đại lý để nâng gói",
            ],
            "Trợ lý ảo không xem hay gia hạn gói được, cũng không báo giá phần mềm.",
            "gói dịch vụ gia hạn hết hạn sử dụng license bản quyền nâng cấp gói đổi gói ngày hết hạn còn bao nhiêu ngày kích hoạt mã kích hoạt gói sbox phí sử dụng giá phần mềm bảng giá sbox chức năng chưa có trong gói cửa hàng bị khóa",
            [], [], "sbox"),
        new(ServerMode, "pos_table_transfer_merge_split", "Chuyển bàn, gộp bàn, tách bàn, tách hóa đơn",
            "Khách đổi chỗ, gộp nhóm hay trả riêng: chạm giữ bàn đang dùng trên sơ đồ bàn để chuyển, gộp, tách bàn hoặc tách hóa đơn.",
            [
                "Bán hàng → sơ đồ bàn → chạm giữ bàn đang dùng để mở menu thao tác",
                "«Chuyển bàn»: chọn bàn trống trong «Chuyển sang bàn…» (hết bàn trống thì báo «Không có bàn trống»)",
                "«Tách bàn» (chọn món chuyển sang bàn trống): đánh dấu món trong «Chọn món tách bàn» → chọn bàn ở «Tách sang bàn…» (bàn cần ít nhất 2 dòng món)",
                "«Gộp bàn vào đây»: chạm giữ bàn đích (đang có khách) → chọn bàn nguồn trong «Gộp bàn nào vào đây?»",
                "«Tách hóa đơn» (khách trả một phần — bàn giữ món còn lại): tick món, chỉnh số lượng +/- → «Tách … phần để thanh toán» (không tách hết bàn)",
                "Đang ở trong bàn: menu màn bán có «Tách hóa đơn» và «Xóa hóa đơn tách»",
            ],
            "Dòng món chưa lưu chưa tách được («Chưa lưu dòng — đóng sheet, đợi 1 giây rồi tách lại»). Cần quyền tạo / sửa đơn bán.",
            "chuyển khách sang bàn khác chuyển bàn khách đổi bàn cho khách chuyển bàn đổi bàn gộp bàn ghép bàn gộp hóa đơn tách bàn tách hóa đơn tách bill chia hóa đơn chia bill trả riêng khách trả một phần sơ đồ bàn chạm giữ bàn",
            ["nav_pos_sell"], [], "pos"),
        new(ServerMode, "pos_sell_vat", "Thiết lập thuế VAT khi bán hàng",
            "Chọn cách tính VAT (giá đã gồm thuế, theo từng mặt hàng, hoặc trên tổng đơn) và thuế suất mặc định cho mọi máy bán.",
            [
                "Mở Thiết lập SBOX → «Thanh toán & hóa đơn» → «Hóa đơn điện tử» → mục «Thuế VAT khi bán» (hoặc lối tắt «Thuế VAT khi bán» ở trang thông tin cửa hàng)",
                "Chọn cách tính: «Giá bán đã bao gồm thuế», «Thuế theo từng mặt hàng» hoặc «Thuế trên tổng đơn hàng»; chọn «Thuế suất mặc định» 0 / 5 / 8 / 10%",
                "«Thuế theo từng mặt hàng»: trong form hàng hóa bật mục «Thuế VAT», chọn «Thuế VAT (%)» (KCT, 0%…)",
                "«Thuế trên tổng đơn hàng»: lúc thanh toán có dòng «Thuế VAT» chọn KCT / 0 / 5 / 8 / 10%, hiện «Tiền hàng» và «VAT (x%)» (KCT = «Không chịu thuế GTGT»)",
                "«Giá bán đã bao gồm thuế»: màn thanh toán không hiện dòng thuế",
                "Thuế khi xuất HĐĐT là phần riêng «Thuế khi xuất hóa đơn» — bấm «Lấy theo thuế khi bán» để hai bên khớp",
            ],
            "",
            "thuế vat vat thuế gtgt thuế giá trị gia tăng thuế suất giá đã gồm vat giá chưa vat cộng thuế tách thuế không chịu thuế kct vat theo mặt hàng hiện vat trên hóa đơn cài đặt thuế",
            [], [], "pos"),
        new(ServerMode, "pos_scale", "Kết nối cân điện tử và đọc mã vạch cân",
            "Hai cách: nối cân trực tiếp vào máy (COM / USB) để lấy khối lượng, hoặc quét tem mã vạch do cân in ra.",
            [
                "Mở Thiết lập SBOX → «Ngành hàng & cách bán» (thẻ cân chỉ hiện với ngành bán lẻ / nhà hàng); màn bán còn có mục «Cân điện tử nối máy»",
                "Tem cân: bật «Đọc mã vạch cân điện tử», chọn «Cân in» «Trọng lượng (gram)» hoặc «Thành tiền (đ)», «Số chữ số mã hàng (PLU)», nhập «Đầu mã của cân» (vd 20, 21)",
                "Nối cân vào máy: «Cân điện tử nối máy này» → «Cổng COM» / «Cáp cân USB» (web: «Chọn cổng cân») → «Tốc độ (baud)», «Khung dữ liệu», «Cách lấy số»",
                "Bật «Màn bán: chọn hàng cân thì lấy luôn khối lượng»; phím F7 lấy lại khối lượng",
                "Từng hàng hóa: bật chip «Bán số lẻ», nhập «Mã PLU» và «Dùng trong (ngày)»",
            ],
            "Đọc cân trên web cần Chrome / Edge; Android hỗ trợ chip CH340, PL2303, CP210x, FTDI. Cấu hình nối cân lưu riêng trên từng máy.",
            "cân điện tử kết nối cân nối cân mã vạch cân tem cân hàng cân bán theo kg cân ký plu đầu mã cổng com rs232 usb baud khối lượng thịt rau cá",
            [], [], "pos"),
        new(ServerMode, "pos_barcode_labels", "In tem mã vạch hàng hóa",
            "Mục «In tem nhãn» gom mọi loại tem: tem hàng hóa, tem cân, tem thông số, mẫu tem và máy in tem.",
            [
                "Mở Trang chủ → nhóm POS → «In tem nhãn»; hoặc «Hàng hóa» → tick chọn nhiều hàng → «In tem mã vạch»",
                "«Tem hàng hóa» (mã vạch, tên, giá): chọn hàng và số tem",
                "Hộp in: chọn «Mẫu tem», «Xem bản in (PDF)» rồi «IN TEM» (có nút «Excel»)",
                "«Cân & in tem cân» cho hàng tươi; «Tem thông số / tự soạn»",
                "«Mẫu tem (trình soạn tem)»: chọn khổ, kéo thả chữ, mã vạch, QR",
                "«Máy in tem»: kết nối máy, khổ cuộn tem; trong hộp in có «Giao thức», «Khe giấy (mm)», «IP máy in tem», «In thử tem mẫu»",
            ],
            "Máy tem phải nạp đúng cuộn tem theo khổ của mẫu.",
            "in tem in mã vạch tem mã vạch tem nhãn in barcode tem hàng hóa in tem giá khổ tem máy in tem mẫu tem tem thông số in tem nhãn dán tem sản phẩm",
            ["nav_pos_products"], [], "pos"),
        new(ServerMode, "pos_offline_sale", "Bán hàng khi mất mạng (offline)",
            "Khi đã bật bán offline, máy POS Android vẫn thu tiền mặt với số hóa đơn OFF-… cấp sẵn và tự gửi đơn lên máy chủ khi có mạng lại.",
            [
                "Bật ở Thiết lập SBOX → «Ngành hàng & cách bán» → «Cho bán offline khi mất mạng» (mặc định TẮT), chọn «Bán offline tối đa sau khi mất mạng» 2 / 4 / 8 / 12 / 24 giờ",
                "Máy cần có mạng ít nhất 1 lần sau khi bật để nhận dải số hóa đơn offline",
                "Mất mạng: thanh đỏ «Bán offline: BẬT (tiền mặt, còn … số HĐ)»; chưa bật thì «Chưa bật bán offline — chỉ giữ giỏ hàng»",
                "Thanh toán: máy hỏi «Thanh toán offline?» → «Thanh toán offline»; hóa đơn in ghi «HÓA ĐƠN OFFLINE (mất mạng) — chưa đồng bộ máy chủ»",
                "Có mạng lại: «Có mạng lại — đang gửi … đơn offline»; đơn lỗi thì bấm thanh báo để xem và gửi lại",
                "Chủ quán xem Báo cáo → «Bán offline & kiểm soát» (có «Giả lập mất mạng (tập bán offline)»)",
            ],
            "Offline chỉ thu tiền mặt (không chuyển khoản, nợ, voucher, điểm); trình duyệt web không bán offline được; bàn đang có đơn trên máy chủ cần mạng mới mở.",
            "bán offline mất mạng mất kết nối không có mạng rớt mạng mất internet đồng bộ đơn hóa đơn offline đơn chờ gửi giả lập mất mạng bán offline kiểm soát thu tiền mặt khi mất mạng",
            ["nav_pos_sell"], [], "pos"),
        new(ServerMode, "sys_dashboard_overview", "Trang chủ và Tổng quan",
            "«Trang chủ» là lưới chức năng; «Tổng quan» là màn số liệu quản lý tự đổi theo gói (bán hàng / nhân sự / cả hai).",
            [
                "Tổng quan › «Trang chủ»: khối «Truy cập nhanh» và các chip nhóm — bấm chip để cuộn tới nhóm chức năng",
                "Tổng quan › «Tổng quan»: «Tổng quan bán hàng» / «Tổng quan nhân sự» / «Tổng quan kinh doanh & nhân sự» theo quyền (nhân viên thường thấy màn cá nhân)",
                "Thẻ bán hàng: «Doanh thu», «Đã thu», «Lợi nhuận gộp», «Số đơn», «Giá trị TB/đơn» — có so sánh kỳ trước",
                "Thẻ nhân sự: «Có mặt hôm nay», «Đi trễ hôm nay», «Vắng hôm nay», «Nghỉ phép hôm nay» (bản gộp có «Doanh thu / NV có mặt»)",
                "Khối: «Doanh thu & lợi nhuận», «Chuyên cần theo ngày», «Việc cần xử lý», «Top hàng bán chạy», «Cơ cấu thanh toán», «Doanh thu theo nhân viên bán» / «Nhân viên hôm nay»",
                "Chọn kỳ: «Hôm nay», «Hôm qua», «7 ngày», «Tháng này», «Tháng trước» (vd «Tháng này» so với cùng kỳ tháng trước)",
            ],
            "Bấm một dòng trong «Việc cần xử lý» để mở đúng màn cần duyệt. Bản chỉ có nhân sự không có thanh chọn kỳ.",
            "trang chủ tổng quan dashboard màn hình chính doanh thu hôm nay số đơn lợi nhuận gộp đã thu việc cần xử lý hàng bán chạy cơ cấu thanh toán có mặt hôm nay truy cập nhanh chọn kỳ",
            ["nav_dashboard"], [], "sbox"),
        new(ServerMode, "pos_branch_report", "Xem báo cáo chi nhánh: so sánh doanh thu, lãi",
            "So sánh các chi nhánh về doanh thu, lãi gộp, chi phí, lương và lãi ròng trong một kỳ — chỉ hiện khi cửa hàng có nhiều chi nhánh.",
            [
                "Mở Báo cáo kinh doanh › «Báo cáo chi nhánh» (cần quyền «Lãi lỗ»)",
                "Chọn kỳ: «7 ngày», «Tháng này» (mặc định), «30 ngày», «Tháng trước» hoặc nút ngày để chọn khoảng tùy ý",
                "Thẻ tổng: «Doanh thu», «Lãi gộp», «Chi phí + lương», «Lãi ròng» («Có lãi» / «Đang lỗ»), «Giá trị tồn kho», «Nhân sự»",
                "Biểu đồ «Doanh thu và lãi ròng theo chi nhánh», «Tỷ trọng doanh thu», «Doanh thu theo ngày»",
                "Bảng «So sánh chi nhánh» (bấm một dòng để xem chi tiết; trụ sở có nhãn «Trụ sở»): doanh thu, đơn, TB / đơn, lãi gộp, % LG, chi phí, lương, phụ thu + phí GH, cước hãng, khấu hao, cọc khách bỏ, lãi ròng, tồn kho",
                "«Xuất Excel» / «Xuất ảnh PNG» (cần quyền xuất)",
            ],
            "Lãi ròng = lãi gộp + phụ thu, phí GH − cước hãng − khấu hao + cọc khách bỏ + thu khác − chi phí − lương; chi phí không gồm chi lương / ứng lương.",
            "xem báo cáo chi nhánh báo cáo chi nhánh so sánh chi nhánh doanh thu chi nhánh lãi ròng lãi gộp chi phí lương chi nhánh khấu hao tồn kho chi nhánh trụ sở nhiều chi nhánh lãi lỗ",
            ["nav_pos_reports"], [], "pos"),
        new(ServerMode, "pos_gym_trainer_checkin", "Gym: PT · Khách của tôi và Check-in hội viên",
            "PT xem hội viên mình phụ trách và xếp lịch tập; lễ tân dùng «Check-in hội viên» ghi lượt tập qua máy chấm công hoặc tại quầy (chỉ ngành gym).",
            [
                "POS › «PT · Khách của tôi»: tab «Khách của tôi» (lễ tân / quản lý thấy «Hội viên có PT», lọc ô «Tất cả PT») và «Lịch tập»",
                "Tìm bằng «Tìm tên / số điện thoại», lọc «Chưa có lịch hẹn»; mỗi khách có «Lịch sử tập», «Thể trạng & phác đồ», «Đặt lịch»",
                "«Đặt lịch tập PT»: «Hội viên», «Thời lượng» (45–120 phút), «Lặp hàng tuần» («Chỉ buổi này» / 4 / 8 / 12 tuần), «Nội dung buổi», «Ghi chú»",
                "Tab «Lịch tập»: mỗi buổi có «Đã tập · đánh giá», «Khách vắng», «Hủy», menu «Dời giờ» / «Xóa lịch»; chuyển «Tuần trước» / «Tuần sau» / «Tuần này»",
                "POS › «Check-in hội viên»: tab «Lượt tập», «Hội viên trên máy», «Báo cáo buổi tập»; nút «Check-in tại quầy», «Mở cửa tay», «Bán / gia hạn gói»",
                "«Hội viên trên máy»: «Thêm hội viên lên máy», «Lấy vân tay», «Lấy khuôn mặt», «Gỡ khỏi máy», «Cần nhắc gia hạn»; báo cáo có «Excel»",
            ],
            "PIN hội viên trên máy là số điện thoại bỏ số 0 đầu; mỗi ngày trừ 1 buổi.",
            "pt huấn luyện viên khách của tôi lịch tập đặt lịch pt hội viên gym check-in hội viên lượt tập vân tay hội viên khuôn mặt mở cửa gia hạn gói tập thể trạng phác đồ",
            [], [], "pos"),
        new(ServerMode, "sys_excel_import_export", "Nhập hàng hóa từ Excel và xuất Excel",
            "Nhập Excel hàng hóa nằm trong menu thao tác của màn «Hàng hóa»; các màn báo cáo và danh sách có nút «Xuất Excel».",
            [
                "POS › «Hàng hóa» → menu thao tác: điện thoại có nhóm «Thêm / nhập hàng» («Nhập Excel theo loại», «Import hỗn hợp (cột Loại hàng)», «Thêm từ catalog mẫu», «Quét ảnh menu bằng AI»); máy tính có «Nhập / tải mẫu theo loại», «Import hỗn hợp (cột Loại hàng)», «Xuất file»",
                "Tải mẫu: chọn loại hàng → «Tải mẫu Excel» → điền → «Nhập Excel» trên cùng dòng",
                "Chỉ nhận .xlsx / .csv (file .xls báo «Chưa đọc được file .xls» — lưu lại thành .xlsx)",
                "Xuất danh sách hàng: «Xuất file Excel» (điện thoại) / «Xuất file» (máy tính), cần quyền xuất",
                "«Xuất Excel» có ở: báo cáo bán hàng / tồn kho, danh sách đơn, Báo cáo chi nhánh, Thu chi, công nợ khách, lịch sử hủy / trả, cuối ngày",
                "Nhập Excel còn có ở Nhân viên («Tải file mẫu»), KPI, chấm công; khách hàng và nhà cung cấp chưa có nhập Excel",
            ],
            "",
            "nhập excel import excel tải mẫu excel file mẫu nhập hàng hóa hàng loạt xuất excel xuất file danh sách hàng hóa import hỗn hợp nhập theo loại catalog mẫu quét ảnh menu file xlsx báo cáo excel xuất dữ liệu",
            ["nav_pos_products"], [], "sbox"),
        new(ServerMode, "pos_cash_book", "Thu chi, sổ quỹ: lập phiếu thu / lập phiếu chi",
            "Ghi phiếu thu / phiếu chi, quản lý danh mục và tài khoản, xem số dư quỹ — phiếu từ bán hàng, nhập hàng được ghi tự động.",
            [
                "Mở Tài chính › «Thu chi» (tab «Sổ quỹ»); báo cáo ở Báo cáo kinh doanh › «Báo cáo thu chi»",
                "Bấm «Thu/Chi» để tạo phiếu thu hoặc phiếu chi; «Chuyển quỹ» để chuyển giữa các quỹ",
                "Thanh công cụ: «Danh mục» (danh mục thu chi), «Tài khoản» (tài khoản ngân hàng), «Đối soát» (sổ quỹ ↔ chứng từ), «Xuất Excel»",
                "Lọc «Thời gian», «Loại», «Trạng thái», «Danh mục»; thẻ tổng «Thu», «Chi», «Số dư», «Chờ thu»",
                "Phiếu tự động từ đơn bán, phiếu nhập, trả tiền nhà cung cấp, khách trả nợ, khách trả hàng, cọc đặt chỗ, COD, phí sửa chữa bảo hành — không xóa được ở Thu chi, phải hủy ở chứng từ gốc",
            ],
            "Phiếu chi (trừ lương / ứng lương và danh mục «Mua tài sản») được tính vào «Chi phí» của Lãi lỗ và Báo cáo chi nhánh. Trợ lý ảo lập được phiếu thu / chi bằng lời.",
            "thu chi sổ quỹ phiếu thu phiếu chi lập phiếu chi lập phiếu thu tiền mặt số dư quỹ chuyển quỹ danh mục thu chi tài khoản ngân hàng đối soát quỹ chi phí cửa hàng báo cáo thu chi tồn quỹ",
            ["nav_cash"], [], "pos"),
        new(ServerMode, "sys_change_forgot_password", "Đổi mật khẩu / quên mật khẩu",
            "Còn nhớ mật khẩu cũ thì đổi trong «Cài đặt»; quên thì nhận mã OTP qua email hoặc nhờ quản lý đặt lại.",
            [
                "Đổi: bấm ảnh đại diện góc trên › «Cài đặt» › «Đổi mật khẩu» → «Mật khẩu hiện tại», «Mật khẩu mới», «Xác nhận mật khẩu mới» (ít nhất 6 ký tự, khác mật khẩu cũ)",
                "Quên: màn đăng nhập bấm «Quên mật khẩu?» → «Mã cửa hàng *», «Email *» → «Gửi mã OTP» (mã hiệu lực 5 phút)",
                "Bước «Xác nhận OTP»: «Mã OTP *» (6 số), «Mật khẩu mới *», «Xác nhận mật khẩu *»; chờ 60 giây mới gửi lại mã được",
                "Tài khoản chỉ có số điện thoại không nhận được OTP — nhờ quản trị đặt lại",
                "Quản lý đặt lại cho nhân viên: Thiết lập SBOX › «Tài khoản nhân viên» › «Thao tác» › «Đặt lại mật khẩu» (nhân viên bị đăng xuất khỏi mọi máy)",
            ],
            "Không thấy mã OTP thì kiểm tra cả mục Spam.",
            "đổi mật khẩu quên mật khẩu mật khẩu mới mã otp lấy lại mật khẩu đặt lại mật khẩu không đăng nhập được mã cửa hàng email nhân viên quên mật khẩu khôi phục mật khẩu",
            [], [], "sbox"),
        new(ServerMode, "sys_change_language", "Đổi ngôn ngữ giao diện",
            "Chọn một trong 5 ngôn ngữ (Tiếng Việt, English, 한국어, 日本語, 中文) ở màn đăng nhập hoặc trong «Cài đặt».",
            [
                "Màn đăng nhập: bấm nút quả địa cầu (VI / EN / 한 / 日 / 中) rồi chọn ngôn ngữ",
                "Đã đăng nhập: ảnh đại diện › «Cài đặt» › nhóm «Ứng dụng» › «Ngôn ngữ» › «Chọn ngôn ngữ»",
                "Danh sách: «Tiếng Việt», «English», «한국어», «日本語», «中文（简体）»",
                "Ngôn ngữ lưu riêng trên từng máy",
            ],
            "Tên ngôn ngữ luôn viết bằng chính ngôn ngữ đó — chọn nhầm vẫn tìm lại được «Tiếng Việt».",
            "đổi ngôn ngữ ngôn ngữ tiếng anh tiếng hàn tiếng nhật tiếng trung tiếng việt chuyển ngôn ngữ giao diện tiếng anh chọn ngôn ngữ english đa ngôn ngữ",
            [], [], "sbox"),
        new(ServerMode, "sys_roles_accounts", "Phân quyền và tài khoản thu ngân / nhân viên bán hàng",
            "Tạo tài khoản đăng nhập và gán vai trò ở «Tài khoản nhân viên», chỉnh quyền chi tiết của từng vai trò ở «Phân quyền».",
            [
                "Mở Thiết lập SBOX › «Người dùng & bảo mật» › «Tài khoản nhân viên» và «Phân quyền»",
                "Tạo: «Thêm tài khoản» hoặc «Tạo từ hồ sơ nhân viên» → «Họ và tên *», «Email *», «Mật khẩu *» (nút «Tạo ngẫu nhiên»)",
                "«Vai trò»: «Thu ngân» (bán hàng, thu tiền, chốt ca), «Order» (gọi món, tạm tính — không thu tiền), «Nhân viên» (chấm công, xem lương, gửi đơn của mình)…",
                "Thu ngân / Order / Nhân viên giới hạn được «Khu vực bán hàng được xem» (mặc định «Tất cả khu»); đổi vai trò sẽ đăng xuất tài khoản khỏi mọi máy",
                "«Phân quyền»: chọn «Chức danh», đặt mức «Tắt», «Chỉ xem», «Vận hành» hoặc «Toàn quyền» cho từng nhóm, hoặc tick «Xem danh sách», «Thêm mới», «Chỉnh sửa», «Xóa», «Xuất Excel», «Phê duyệt» → «Lưu thay đổi»",
                "Vai trò riêng: «Thêm chức danh» → «Mã chức danh», «Tên hiển thị»; «Nạp mẫu cho vai trò này» lấy bộ quyền mẫu",
            ],
            "Chỉ quản lý được tài khoản có vai trò thấp hơn mình. Khóa bằng «Khóa tài khoản».",
            "phân quyền vai trò chức danh tài khoản thu ngân tài khoản nhân viên chỉ bán hàng tạo tài khoản quyền xem quyền xóa khóa tài khoản order phục vụ giới hạn quyền khu vực bán hàng ẩn giá vốn",
            ["nav_employees"], [], "sbox"),
        new(ServerMode, "sys_system_params", "Tham số hệ thống",
            "Chỉnh giờ chốt ngày, cách tính công, chấm công bù, số cấp duyệt, phụ thu & phí giao hàng và dữ liệu mẫu.",
            [
                "Mở Thiết lập SBOX › «Cửa hàng» › «Tham số hệ thống» (cần quyền sửa)",
                "«Ngày làm việc kết thúc lúc» › «Giờ kết thúc ngày» (mặc định 00:00) — cho cửa hàng có ca đêm",
                "«Cách tính công trong ngày»: «Theo ngưỡng (1 / 0,5)» hoặc «Thập phân (0,1 – 1)»; «Đủ 1 công khi làm từ», «Không tính công nếu làm dưới»",
                "«Chấm công bù & quy trình duyệt»: «Cho phép xin sửa / bổ sung công»; «1 cấp» / «2 cấp» / «3 cấp» cho «Duyệt yêu cầu sửa công» và «Duyệt đơn nghỉ phép»",
                "«Phụ thu & phí giao hàng»: bật «Phụ thu», «Phí giao hàng» để ô nhập hiện ở màn thanh toán",
                "«Dữ liệu mẫu»: «Cài dữ liệu mẫu» / «Xóa dữ liệu mẫu»; xong bấm «Lưu» (hoặc «Khôi phục mặc định»)",
            ],
            "",
            "tham số hệ thống giờ chốt ngày ca đêm tính công nửa công công thập phân chấm công bù sửa công cấp duyệt duyệt nghỉ phép phụ thu phí giao hàng phí dịch vụ dữ liệu mẫu",
            [], [], "sbox"),
        new(ServerMode, "sys_reset_trial_data", "Xóa dữ liệu bán thử / làm lại từ đầu",
            "SBOX không có nút xóa toàn bộ dữ liệu bán hàng cho chủ cửa hàng — chỉ xóa được dữ liệu mẫu, đơn bán thử thì hủy từng đơn.",
            [
                "Dữ liệu mẫu: Thiết lập SBOX › «Tham số hệ thống» › «Dữ liệu mẫu» › «Xóa dữ liệu mẫu» → «Xóa» (xóa nhân viên demo, chấm công, phép, hàng / bàn POS mẫu; hàng / bàn đã bán thật không xóa được; không hoàn tác)",
                "Đơn bán thử: menu «Đơn hàng» → chọn đơn → «Hủy đơn» (hoàn kho, hoàn công nợ / điểm / voucher; đơn chuyển «Đã hủy» nhưng vẫn hiện trong danh sách)",
                "Hàng nhập thử: «Hàng hóa» → «Xóa hàng hóa», hoặc «Ngừng kinh doanh»",
                "Muốn xóa sạch toàn bộ cửa hàng: liên hệ SBOX hoặc đại lý",
            ],
            "Nên làm quen bằng «Cài dữ liệu mẫu» rồi xóa trước khi bán thật.",
            "xóa dữ liệu bán thử làm lại từ đầu reset xóa đơn thử dữ liệu mẫu xóa dữ liệu mẫu hủy đơn xóa hàng hóa khôi phục cài đặt gốc dọn dữ liệu bắt đầu lại",
            [], [], "sbox"),
        new(ServerMode, "sys_multi_device_login", "Một tài khoản dùng nhiều máy / giới hạn thiết bị",
            "Một tài khoản đăng nhập được trên nhiều máy, nhưng cả cửa hàng chỉ có số chỗ máy theo gói dịch vụ.",
            [
                "Mỗi điện thoại, trình duyệt hoặc máy POS đã đăng nhập chiếm 1 chỗ — tính theo máy, không theo tài khoản",
                "Xem / gỡ máy: Thiết lập SBOX › «Người dùng & bảo mật» › «Thiết bị truy cập» → «Gỡ» hoặc «Gỡ tất cả» (trả chỗ ngay)",
                "Hết chỗ: màn báo «Đã đầy», máy mới bị chặn đăng nhập («đạt giới hạn … thiết bị truy cập»)",
                "Gói dịch vụ có thể không cho đăng nhập bằng web hoặc bằng mobile / POS",
                "Mỗi tài khoản giữ tối đa 10 phiên; phiên cũ nhất tự hết khi vượt",
            ],
            "Máy ghi «Lâu không dùng» nên gỡ để lấy lại chỗ.",
            "nhiều thiết bị nhiều máy đăng nhập nhiều máy giới hạn thiết bị thiết bị truy cập gỡ thiết bị đăng xuất từ xa đã đầy máy pos dùng chung tài khoản đăng nhập trên nhiều thiết bị",
            [], [], "sbox"),
    ];

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
            if (HasAppGuide(chunk))
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
    static bool Has(string text, string term) => term.Length > 3 ? text.Contains(term) : HasWord(text, term);

    /// <summary>Trùng nguyên từ / nguyên cụm («chuyen kho» không khớp «chuyen khoan»).</summary>
    static bool HasWord(string text, string term) =>
        text.Contains(term) && Regex.IsMatch(text, $@"(?<![\p{{L}}\p{{N}}]){Regex.Escape(term)}(?![\p{{L}}\p{{N}}])");

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
            if (HasWord(c.StepId, pair)) score += 15;
            if (HasWord(c.Title, pair)) score += 15;
            if (HasWord(c.Keywords, pair)) score += 10;
            if (HasWord(c.Summary, pair)) score += 5;
            score += 3 * c.Bullets.Count(b => HasWord(b, pair));
        }

        return score;
    }
}
