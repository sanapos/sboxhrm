using ZKTecoADMS.Application.DTOs.SystemAdmin;

namespace ZKTecoADMS.Application.Authorization;

/// <summary>
/// Single source of truth for HRM/POS module codes used in permission seed,
/// service package picker, and package enforcement.
/// </summary>
public static class FeatureModuleCatalog
{
    public record ModuleEntry(
        string Code,
        string DisplayName,
        string Description,
        string Category,
        int Order,
        bool SelectableForPackage = true);

    /// <summary>Modules always available regardless of package (self-service).</summary>
    public static readonly IReadOnlyList<string> SelfServiceModuleCodes =
    [
        "Home",
        "Notification",
        "Settings",
        "Payslip",
        "MobileAttendance",
    ];

    public static readonly IReadOnlyList<ModuleEntry> All =
    [
        // ══════════ TỔNG QUAN ══════════
        new("Home", "Trang chủ", "Màn hình tổng quan menu", "Tổng quan", 1),
        new("Notification", "Thông báo", "Hệ thống thông báo", "Tổng quan", 2),
        new("Dashboard", "Tổng quan (cũ)", "Bảng điều khiển — dùng các quyền widget bên dưới", "Tổng quan", 3),
        new("DashboardAttendanceOverview", "Tổng quan chấm công", "KPI chấm công trên Dashboard", "Tổng quan", 4),
        new("DashboardHrInsights", "Chỉ số nhân sự & vận hành", "Chip chỉ số HR trên Dashboard", "Tổng quan", 5),
        new("DashboardTodaySchedule", "Lịch làm việc hôm nay", "Lịch ca hôm nay trên Dashboard", "Tổng quan", 6),
        new("DashboardRealtimeAttendance", "Chấm công thời gian thực", "Danh sách chấm công realtime", "Tổng quan", 7),
        new("DashboardAbsent", "Nhân viên vắng mặt", "Khối vắng mặt trên Dashboard", "Tổng quan", 8),
        new("DashboardLateEarly", "Đi trễ / về sớm", "Khối trễ sớm trên Dashboard", "Tổng quan", 9),
        new("DashboardKpiPanel", "KPI (Dashboard)", "Khối KPI trên Dashboard", "Tổng quan", 10),
        new("DashboardInternalNews", "Bản tin nội bộ", "Tin truyền thông trên Dashboard", "Tổng quan", 11),

        // ══════════ HỒ SƠ NHÂN SỰ ══════════
        new("Employee", "Hồ sơ nhân sự", "Thông tin nhân viên, chức vụ", "Hồ sơ nhân sự", 12),
        new("Department", "Phòng ban", "Quản lý phòng ban", "Hồ sơ nhân sự", 13),
        new("SalarySettings", "Thiết lập lương", "Cấu hình bảng lương", "Hồ sơ nhân sự", 14),
        new("HrDocument", "Tài liệu HR", "Quản lý tài liệu nhân sự", "Hồ sơ nhân sự", 15),
        new("OrgChart", "Sơ đồ tổ chức", "Sơ đồ tổ chức công ty", "Hồ sơ nhân sự", 16),

        // ══════════ CHẤM CÔNG ══════════
        new("DeviceUser", "Nhân sự chấm công", "Nhân sự trên máy chấm công", "Chấm công", 17),
        new("Leave", "Nghỉ phép", "Quản lý nghỉ phép", "Chấm công", 18),
        new("Attendance", "Chấm công thô", "Dữ liệu chấm công thô", "Chấm công", 19),
        new("WorkSchedule", "Lịch làm việc", "Phân lịch làm việc", "Chấm công", 20),
        new("AttendanceCorrection", "Chỉnh sửa chấm công", "Yêu cầu chỉnh sửa log chấm công", "Chấm công", 21),
        new("AttendanceApproval", "Duyệt chấm công", "Duyệt điều chỉnh chấm công", "Chấm công", 22),
        new("MobileAttendanceApproval", "Duyệt chấm công Mobile", "Duyệt yêu cầu chấm công mobile", "Chấm công", 23),
        new("ScheduleApproval", "Duyệt lịch làm việc", "Duyệt lịch làm việc đăng ký", "Chấm công", 24),
        new("Overtime", "Tăng ca", "Đăng ký và duyệt tăng ca", "Chấm công", 25),
        new("ShiftSwap", "Đổi ca", "Đổi / đăng ký đổi ca", "Chấm công", 26),
        new("MobileDeviceRegistration", "Đăng ký chấm công Mobile", "Quản lý đăng ký thiết bị chấm công mobile", "Chấm công", 27),
        new("MobileAttendance", "Chấm công Mobile", "Chấm công bằng điện thoại", "Chấm công", 28),

        // ══════════ BÁO CÁO & LƯƠNG ══════════
        new("AttendanceSummary", "Tổng hợp chấm công", "Bảng tổng hợp công theo tháng", "Báo cáo & Lương", 29),
        new("AttendanceByShift", "Tổng hợp chấm công theo ca", "Thống kê giờ công theo ca làm", "Báo cáo & Lương", 30),
        new("LateEarlyReport", "Đi trễ / Về sớm", "Tổng hợp phút đi trễ và về sớm theo ca", "Báo cáo & Lương", 30),
        new("TravelHoursReport", "Báo cáo đi đường", "Chi tiết giờ đi đường mobile, bổ sung thủ công", "Báo cáo & Lương", 30),
        new("Payslip", "Phiếu lương", "Phiếu lương cá nhân", "Báo cáo & Lương", 31),
        new("Payroll", "Tổng hợp lương", "Bảng lương nhân viên", "Báo cáo & Lương", 32),
        new("AttendanceReport", "Báo cáo chấm công", "Ngày, tháng, đi muộn, phòng ban", "Báo cáo", 33),
        new("LeaveReport", "Báo cáo nghỉ phép", "Thống kê nghỉ phép, ngày nghỉ", "Báo cáo", 34),
        new("CashReport", "Báo cáo thu chi", "Thống kê thu chi tiền mặt", "Báo cáo", 35),
        new("PenaltyReport", "Báo cáo phạt", "Thống kê phiếu phạt, kỷ luật", "Báo cáo", 36),
        new("AdvanceReport", "Báo cáo ứng lương", "Thống kê ứng lương, tạm ứng", "Báo cáo", 37),
        new("BusinessTripReport", "Báo cáo công tác phí", "Tổng hợp ứng công tác, hoạch toán chi phí", "Báo cáo", 38),
        new("AssetReport", "Báo cáo tài sản", "Danh mục, cấp phát, lịch sử chuyển giao", "Báo cáo", 39),

        // ══════════ TÀI CHÍNH ══════════
        new("BonusPenalty", "Phiếu thưởng", "Quản lý phiếu thưởng nhân viên", "Tài chính", 39),
        new("PenaltyTickets", "Phiếu phạt", "Phiếu phạt tự động từ chấm công", "Tài chính", 40),
        new("AdvanceRequests", "Ứng lương", "Quản lý ứng lương", "Tài chính", 41),
        new("BusinessTripExpense", "Công tác phí", "Ứng công tác, hoạch toán chi phí", "Tài chính", 41),
        new("CashTransaction", "Thu chi", "Quản lý thu chi", "Tài chính", 42),
        new("BankAccount", "Tài khoản ngân hàng", "Tài khoản ngân hàng thu chi", "Tài chính", 43),

        // ══════════ QUẢN LÝ VẬN HÀNH ══════════
        new("Meal", "Chấm cơm", "Quản lý suất ăn ca", "Quản lý Vận hành", 44),
        new("Asset", "Tài sản", "Quản lý tài sản", "Quản lý Vận hành", 45),
        new("Task", "Công việc", "Quản lý công việc", "Quản lý Vận hành", 46),
        new("Communication", "Truyền thông", "Truyền thông nội bộ", "Quản lý Vận hành", 47),
        new("KPI", "KPI", "Đánh giá KPI", "Quản lý Vận hành", 48),
        new("Production", "Sản lượng", "Nhập sản lượng, tính lương sản phẩm", "Quản lý Vận hành", 49),
        new("Feedback", "Phản ánh / Ý kiến", "Phản ánh, góp ý ẩn danh hoặc công khai", "Quản lý Vận hành", 50),
        new("FieldCheckIn", "Bản đồ nhân sự", "Vị trí trực tuyến NV chấm ngoài CT trên bản đồ", "Quản lý Vận hành", 51),

        // ══════════ POS / BÁN HÀNG ══════════
        new("PosProducts", "Hàng hóa POS", "Danh mục hàng hóa, tồn kho, giá bán", "POS / Bán hàng", 52),
        new("PosSell", "Bán hàng POS", "Order / tạm tính (Tạo) · Thanh toán (Duyệt)", "POS / Bán hàng", 53),
        new("PosPrintTemplates", "Mẫu in POS", "Mẫu in hóa đơn, phiếu", "POS / Bán hàng", 54),
        new("PosSaleOrders", "Đơn hàng POS", "Danh sách đơn bán hàng", "POS / Bán hàng", 55),
        new("PosSaleReturns", "Trả hàng bán", "Trả hàng khách, hủy phiếu trả", "POS / Bán hàng", 56),
        new("PosPurchaseReceipts", "Nhập hàng NCC", "Phiếu nhập hàng nhà cung cấp", "POS / Bán hàng", 57),
        new("PosPurchaseReturns", "Trả hàng nhập", "Trả hàng cho nhà cung cấp", "POS / Bán hàng", 58),
        new("PosStockCounts", "Kiểm kho POS", "Kiểm kê tồn kho", "POS / Bán hàng", 59),
        new("PosDamageIssues", "Xuất hủy POS", "Xuất hủy hàng hóa", "POS / Bán hàng", 60),
        new("PosInternalUseIssues", "Xuất dùng nội bộ", "Xuất dùng nội bộ hàng hóa", "POS / Bán hàng", 61),
        new("PosSalesReport", "Báo cáo POS (tổng hợp)", "Hub báo cáo POS / màn gộp cũ", "POS / Bán hàng", 62),
        new("PosReportRevenue", "Doanh thu", "Báo cáo doanh thu bán hàng", "POS / Báo cáo", 73),
        new("PosReportSoldGoods", "Hàng hóa bán ra", "Top hàng theo doanh thu", "POS / Báo cáo", 74),
        new("PosReportStock", "Tồn kho", "Báo cáo tồn kho hiện tại", "POS / Báo cáo", 75),
        new("PosReportPurchases", "Báo cáo nhập hàng", "Phiếu nhập / trả NCC", "POS / Báo cáo", 76),
        new("PosReportPayment", "Phương thức thanh toán", "Cơ cấu đã thu theo PTTT", "POS / Báo cáo", 77),
        new("PosReportDebt", "Công nợ", "Công nợ khách hàng và nhà cung cấp", "POS / Báo cáo", 78),
        new("PosReportExpiry", "Hàng sắp hết hạn", "Lô / hạn sử dụng", "POS / Báo cáo", 79),
        new("PosReportProfit", "Lợi nhuận", "Lợi nhuận gộp, giá vốn, biên LN", "POS / Báo cáo", 80),
        new("PosReportExpense", "Chi phí", "Phiếu chi theo nhóm", "POS / Báo cáo", 81),
        new("PosReportEndOfDay", "Tổng kết cuối ngày", "Báo cáo cuối ngày theo nhân viên", "POS / Báo cáo", 82),
        new("PosReportStaffRevenue", "Doanh thu theo nhân viên", "Doanh thu theo người bán", "POS / Báo cáo", 83),
        new("PosReportCashbook", "Sổ quỹ", "Thu / chi / chênh lệch quỹ", "POS / Báo cáo", 84),
        new("PosReportPnl", "Kết quả kinh doanh", "P&L: DT, giá vốn, chi phí, LN ròng", "POS / Báo cáo", 85),
        new("PosReportVoucher", "Báo cáo voucher", "Voucher đã dùng trên hóa đơn", "POS / Báo cáo", 86),
        new("PosBooking", "Đặt bàn / lịch hẹn", "Đặt trước bàn/ghế, lịch hẹn salon, cọc, nhận khách", "POS / Bán hàng", 63),
        new("PosCustomers", "Khách hàng POS", "CRM khách bán hàng, công nợ, điểm", "POS / Bán hàng", 64),
        new("PosWarranty", "Bảo hành POS", "Tra cứu / danh sách bảo hành sản phẩm", "POS / Bán hàng", 65),
        new("PosCustomerDisplay", "Màn hình phụ POS", "Customer display, media quảng cáo khi bán", "POS / Bán hàng", 66),
        new("PosEInvoice", "Hóa đơn điện tử POS", "Viettel SInvoice, Easy Invoice, MISA — cấu hình, xuất, báo cáo", "POS / Bán hàng", 67),
        new("PosKds", "Màn hình bếp (KDS)", "Phiếu chế biến, bump món, đọc món, in khi xong", "POS / Bán hàng", 68),
        new("PosQrOrder", "QR order bàn", "In/sao QR gọi món tại bàn, menu online, đơn online", "POS / Bán hàng", 69),
        new("PosCashierShift", "Ca thu ngân", "Mở/đóng ca, đối soát tiền mặt", "POS / Bán hàng", 70),
        new("PosPrinters", "Máy in thiết bị", "Máy in trên máy này: Bluetooth / LAN / USB, tem ly", "POS / Bán hàng", 71),
        new("PosStorePrinters", "Máy in cửa hàng", "Máy in Cloud / Print Agent dùng chung cửa hàng — bật theo gói dịch vụ", "POS / Bán hàng", 87),
        new("PosShipping", "Đơn vị giao hàng", "GHN / GHTK / Viettel Post / AhaMove — cấu hình, so sánh cước, tạo vận đơn", "POS / Bán hàng", 72),
        new("HkdBooks", "Thuế hộ kinh doanh", "Sổ thuế HKD dưới 1 tỷ / 1–3 tỷ / trên 3 tỷ (TT 152/2025)", "Báo cáo", 73),

        // ══════════ THIẾT LẬP HRM ══════════
        new("SettingsHub", "Thiết lập HRM / POS", "Hub cài đặt HRM và thiết lập POS (cửa hàng, ngành hàng, cổng CK). Xem = mở; Sửa = lưu.", "Cài đặt", 70),
        new("ShiftSetup", "Thiết lập ca", "Ca làm việc, vào sớm, đi trễ, về sớm, tăng ca", "Cài đặt", 71),
        new("Holiday", "Ngày lễ", "Ngày nghỉ lễ, hệ số công", "Cài đặt", 72),
        new("Device", "Máy chấm công", "Kết nối, quản lý, điều khiển máy chấm công", "Cài đặt", 73),
        new("Allowance", "Phụ cấp", "Phụ cấp cố định, phụ cấp ngày công", "Cài đặt", 74),
        new("PenaltySetup", "Phạt", "Đi trễ, về sớm, tái phạm, kỷ luật", "Cài đặt", 75),
        new("Insurance", "Bảo hiểm", "BHXH, BHYT, BHTN, lương cơ sở", "Cài đặt", 76),
        new("Tax", "Thuế TNCN", "Bậc thuế, giảm trừ gia cảnh", "Cài đặt", 77),
        new("ProductSalary", "Lương sản phẩm", "Nhóm sản phẩm, sản phẩm, đơn giá theo bậc", "Cài đặt", 78),
        new("Branch", "Chi nhánh", "Quản lý chi nhánh", "Cài đặt", 79),
        new("Geofence", "Vùng chấm công", "Geofence chấm công mobile", "Cài đặt", 80),
        new("SystemSettings", "Hệ thống", "Giờ kết thúc ngày, tham số vận hành", "Cài đặt", 81),
        new("NotificationSettings", "Thiết lập thông báo", "Nhóm thông báo, bật/tắt nhận thông báo", "Cài đặt", 82),
        new("AIGemini", "Thiết lập AI", "API key, model, tham số AI", "Cài đặt", 83),
        new("GoogleDrive", "Google Drive", "Lưu trữ ảnh, service account", "Cài đặt", 84),

        // ══════════ QUẢN TRỊ ══════════
        new("UserManagement", "Tài khoản", "Người dùng, kích hoạt, vai trò", "Quản trị", 90),
        new("Role", "Phân quyền", "Ma trận quyền, vai trò, module", "Quản trị", 91),
        new("DepartmentPermission", "PQ Phòng ban", "Phân quyền theo sơ đồ cây phòng ban", "Quản trị", 92),

        // API / legacy aliases — seed only, not selectable in package UI
        new("Shift", "Ca làm việc (API)", "Đăng ký ca nhân viên", "API", 901, false),
        new("ShiftTemplate", "Mẫu ca (API)", "Mẫu ca làm việc", "API", 902, false),
        new("ShiftSalaryLevel", "Bậc lương ca (API)", "Bậc lương theo ca", "API", 903, false),
        new("Benefit", "Phúc lợi (API)", "Alias Thưởng/Phạt", "API", 904, false),
        new("Transaction", "Giao dịch (API)", "Alias Thu chi", "API", 905, false),
        new("Report", "Báo cáo (cũ)", "Alias báo cáo hiện đại", "API", 907, false),
    ];

    public static IReadOnlyList<ModuleEntry> PackageSelectable =>
        All.Where(m => m.SelectableForPackage).OrderBy(m => m.Order).ToList();

    public static List<FeatureModuleDto> ToFeatureModuleDtos() =>
        PackageSelectable
            .Select(m => new FeatureModuleDto(m.Code, m.DisplayName, m.Description, m.Category))
            .ToList();

    public static HashSet<string> AllCodes =>
        All.Select(m => m.Code).ToHashSet(StringComparer.OrdinalIgnoreCase);

    public static bool IsSelfService(string? moduleCode) =>
        !string.IsNullOrEmpty(moduleCode) &&
        SelfServiceModuleCodes.Contains(moduleCode, StringComparer.OrdinalIgnoreCase);
}
