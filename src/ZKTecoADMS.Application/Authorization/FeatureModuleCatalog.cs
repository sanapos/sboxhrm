using ZKTecoADMS.Application.DTOs.SystemAdmin;

namespace ZKTecoADMS.Application.Authorization;

/// <summary>
/// Single source of truth for HRM/POS module codes used in permission seed,
/// service package picker, and package enforcement.
/// Mã module giữ nguyên (đã lưu trong gói / phân quyền) — chỉ tên, nhóm, thứ tự được chuẩn hóa.
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

    /// <summary>Modules always available regardless of package (self-service).
    /// Chấm công Mobile đã chuyển thành module chọn theo gói.</summary>
    public static readonly IReadOnlyList<string> SelfServiceModuleCodes =
    [
        "Home",
        "Notification",
        "Settings",
        "Payslip",
    ];

    // ── Nhóm (theo thứ tự hiển thị) ──
    public const string CatOverview = "Tổng quan";
    public const string CatHrProfile = "Hồ sơ nhân sự";
    public const string CatAttendance = "Chấm công";
    public const string CatPayroll = "Lương & báo cáo nhân sự";
    public const string CatHrFinance = "Tài chính nhân sự";
    public const string CatOperations = "Vận hành";
    public const string CatAi = "Trí tuệ nhân tạo";
    public const string CatSell = "Bán hàng";
    public const string CatWarehouse = "Kho hàng";
    public const string CatSellReport = "Báo cáo bán hàng";
    public const string CatSellSetup = "Thiết lập bán hàng";
    public const string CatHrSetup = "Thiết lập nhân sự";
    public const string CatAdmin = "Quản trị";
    public const string CatApi = "API";

    public static readonly IReadOnlyList<string> CategoryOrder =
    [
        CatOverview, CatHrProfile, CatAttendance, CatPayroll, CatHrFinance, CatOperations, CatAi,
        CatSell, CatWarehouse, CatSellReport, CatSellSetup, CatHrSetup, CatAdmin,
    ];

    /// <summary>Dòng sản phẩm của nhóm: pos / hrm / common.</summary>
    public static string ProductLineOf(string category) => category switch
    {
        CatSell or CatWarehouse or CatSellReport or CatSellSetup => "pos",
        CatOverview or CatAi or CatAdmin => "common",
        _ => "hrm",
    };

    public static readonly IReadOnlyList<ModuleEntry> All =
    [
        // ══════════ TỔNG QUAN ══════════
        new("Home", "Trang chủ", "Màn hình menu chính", CatOverview, 1),
        new("Notification", "Thông báo", "Trung tâm thông báo", CatOverview, 2),
        new("Dashboard", "Tổng quan doanh nghiệp", "Trang tổng quan HRM / bán hàng: chỉ số, biểu đồ, việc cần làm", CatOverview, 3),
        new("DashboardAttendanceOverview", "Tổng quan · chấm công", "Khối KPI chấm công trên trang tổng quan", CatOverview, 4),
        new("DashboardHrInsights", "Tổng quan · chỉ số nhân sự", "Chip chỉ số nhân sự & vận hành", CatOverview, 5),
        new("DashboardTodaySchedule", "Tổng quan · lịch hôm nay", "Lịch ca làm hôm nay", CatOverview, 6),
        new("DashboardRealtimeAttendance", "Tổng quan · chấm công trực tiếp", "Danh sách chấm công thời gian thực", CatOverview, 7),
        new("DashboardAbsent", "Tổng quan · vắng mặt", "Nhân viên vắng hôm nay", CatOverview, 8),
        new("DashboardLateEarly", "Tổng quan · đi trễ / về sớm", "Khối trễ sớm hôm nay", CatOverview, 9),
        new("DashboardKpiPanel", "Tổng quan · KPI", "Khối KPI trên trang tổng quan", CatOverview, 10),
        new("DashboardInternalNews", "Tổng quan · bản tin", "Tin truyền thông nội bộ trên trang tổng quan", CatOverview, 11),

        // ══════════ HỒ SƠ NHÂN SỰ ══════════
        new("Employee", "Hồ sơ nhân sự", "Thông tin nhân viên, hợp đồng, chức vụ", CatHrProfile, 20),
        new("Department", "Phòng ban", "Cây phòng ban, trưởng phòng", CatHrProfile, 21),
        new("OrgChart", "Sơ đồ tổ chức", "Sơ đồ tổ chức công ty", CatHrProfile, 22),
        new("HrDocument", "Tài liệu nhân sự", "Lưu trữ giấy tờ, hồ sơ", CatHrProfile, 23),

        // ══════════ CHẤM CÔNG ══════════
        new("Attendance", "Chấm công thô", "Dữ liệu chấm từ máy và điện thoại", CatAttendance, 30),
        new("DeviceUser", "Nhân sự trên máy chấm công", "Đồng bộ người dùng máy chấm công", CatAttendance, 31),
        new("MobileAttendance", "Chấm công Mobile", "Chấm công bằng điện thoại: khuôn mặt, GPS, WiFi, ảnh hiện trường", CatAttendance, 32),
        new("MobileDeviceRegistration", "Đăng ký điện thoại chấm công", "Duyệt thiết bị, cho phép chấm ngoài / đi đường", CatAttendance, 33),
        new("WorkSchedule", "Lịch làm việc", "Phân ca, đăng ký ca, định mức nhân sự", CatAttendance, 34),
        new("ScheduleApproval", "Duyệt lịch làm việc", "Duyệt ca nhân viên đăng ký", CatAttendance, 35),
        new("ShiftSwap", "Đổi ca", "Xin đổi ca giữa nhân viên", CatAttendance, 36),
        new("Leave", "Nghỉ phép", "Xin nghỉ, duyệt nghỉ, quỹ phép", CatAttendance, 37),
        new("Overtime", "Tăng ca", "Đăng ký và duyệt tăng ca", CatAttendance, 38),
        new("AttendanceCorrection", "Xin sửa / bổ sung công", "Nhân viên gửi yêu cầu sửa giờ chấm", CatAttendance, 39),
        new("AttendanceApproval", "Duyệt chấm công", "Hộp duyệt sửa công + chấm ngoài vị trí, chấm điểm rủi ro", CatAttendance, 40),
        new("MobileAttendanceApproval", "Duyệt chấm công Mobile", "Duyệt riêng các bản chấm điện thoại", CatAttendance, 41),

        // ══════════ LƯƠNG & BÁO CÁO NHÂN SỰ ══════════
        new("AttendanceSummary", "Tổng hợp chấm công", "Bảng công tháng", CatPayroll, 50),
        new("AttendanceByShift", "Tổng hợp công theo ca", "Giờ công theo ca làm", CatPayroll, 51),
        new("Payroll", "Bảng lương", "Tính lương, thuế, bảo hiểm, chốt kỳ", CatPayroll, 52),
        new("Payslip", "Phiếu lương", "Phiếu lương cá nhân", CatPayroll, 53),
        new("LateEarlyReport", "Báo cáo đi trễ / về sớm", "Phút trễ sớm theo ca", CatPayroll, 54),
        new("TravelHoursReport", "Báo cáo đi đường", "Giờ đi đường mobile", CatPayroll, 55),
        new("AttendanceReport", "Báo cáo chấm công", "Theo ngày, tháng, phòng ban", CatPayroll, 56),
        new("LeaveReport", "Báo cáo nghỉ phép", "Thống kê ngày nghỉ", CatPayroll, 57),
        new("PenaltyReport", "Báo cáo phạt", "Thống kê phiếu phạt", CatPayroll, 58),
        new("AdvanceReport", "Báo cáo ứng lương", "Thống kê tạm ứng", CatPayroll, 59),
        new("BusinessTripReport", "Báo cáo công tác phí", "Ứng và quyết toán công tác", CatPayroll, 60),
        new("CashReport", "Báo cáo thu chi", "Thống kê thu chi", CatPayroll, 61),
        new("AssetReport", "Báo cáo tài sản", "Cấp phát, chuyển giao tài sản", CatPayroll, 62),

        // ══════════ TÀI CHÍNH NHÂN SỰ ══════════
        new("AdvanceRequests", "Ứng lương", "Xin ứng, hạn mức, trả góp, chi ứng — trong Tài chính nhân sự", CatHrFinance, 70),
        new("BonusPenalty", "Thưởng / phạt", "Phiếu thưởng, phạt thủ công, khiếu nại — trong Tài chính nhân sự", CatHrFinance, 71),
        new("PenaltyTickets", "Phiếu phạt chấm công", "Phiếu phạt tự động đi trễ / về sớm / quên chấm", CatHrFinance, 72),
        new("CashTransaction", "Thu chi", "Sổ quỹ thu chi — trong Tài chính nhân sự", CatHrFinance, 73),
        new("BankAccount", "Tài khoản ngân hàng", "Tài khoản nhận / chi tiền", CatHrFinance, 74),
        new("BusinessTripExpense", "Công tác phí", "Hồ sơ công tác, ứng, quyết toán", CatHrFinance, 75),

        // ══════════ VẬN HÀNH ══════════
        new("Task", "Công việc & dự án", "Giao việc, dự án, checklist, việc lặp, gói ngành", CatOperations, 80),
        new("Communication", "Truyền thông nội bộ", "Bảng tin, văn bản bắt buộc đọc, bình chọn, AI viết bài", CatOperations, 81),
        new("Feedback", "Phản ánh / kiến nghị", "Góp ý ẩn danh hoặc công khai, hạn xử lý", CatOperations, 82),
        new("Meal", "Suất ăn / căn tin", "Đăng ký, chấm cơm, phiếu ăn, công nợ tiền ăn", CatOperations, 83),
        new("Asset", "Tài sản", "Danh mục, cấp phát, QR tài sản", CatOperations, 84),
        new("KPI", "KPI", "Đánh giá hiệu suất", CatOperations, 85),
        new("Production", "Sản lượng", "Nhập sản lượng, lương sản phẩm", CatOperations, 86),
        new("FieldCheckIn", "Bản đồ nhân sự", "Vị trí lúc chấm công / check-in và lộ trình trong ca trên bản đồ", CatOperations, 87),

        // ══════════ TRÍ TUỆ NHÂN TẠO ══════════
        new("AIAssistant", "Trợ lý AI", "Hỏi đáp doanh thu, tồn kho, nhân sự — gõ hoặc nói bằng giọng", CatAi, 90),
        new("AIGemini", "Thiết lập AI", "Model, tham số AI của cửa hàng", CatAi, 91),

        // ══════════ BÁN HÀNG ══════════
        new("PosSell", "Bán hàng", "Order, tạm tính, thanh toán", CatSell, 100),
        new("PosProducts", "Hàng hóa", "Danh mục, giá bán, bảng giá, combo", CatSell, 101),
        new("PosSaleOrders", "Đơn hàng", "Danh sách hóa đơn bán", CatSell, 102),
        new("PosSaleReturns", "Trả hàng bán", "Khách trả hàng, hoàn tiền", CatSell, 103),
        new("PosCustomers", "Khách hàng", "CRM, công nợ, điểm thưởng", CatSell, 104),
        new("PosCashierShift", "Ca thu ngân", "Mở / đóng ca, đối soát tiền", CatSell, 105),
        new("PosBooking", "Đặt bàn / lịch hẹn", "Đặt trước bàn, lịch hẹn, cọc", CatSell, 106),
        new("PosQrOrder", "Gọi món QR tại bàn", "QR menu, đơn online", CatSell, 107),
        new("PosKds", "Màn hình bếp (KDS)", "Phiếu chế biến, báo món xong", CatSell, 108),
        new("PosWarranty", "Bảo hành", "Tra cứu, phiếu bảo hành", CatSell, 109),
        new("PosQuotes", "Báo giá", "Báo giá thương mại, không trừ kho", CatSell, 110),
        // Quyền con — đi theo Bán hàng / Hàng hóa, không chọn theo gói.
        new("PosSellPriceEdit", "Sửa giá khi bán", "Đổi đơn giá tay trên màn bán", CatSell, 120, false),
        new("PosSellDiscount", "Giảm giá khi bán", "Chiết khấu dòng / cả đơn", CatSell, 121, false),
        new("PosSellCancelPaid", "Hủy hóa đơn đã thu", "Hủy đơn đã thanh toán", CatSell, 122, false),
        new("PosViewCost", "Xem giá vốn & lợi nhuận", "Thấy giá vốn, lãi trên hàng hóa / kho", CatSell, 123, false),

        // ══════════ KHO HÀNG ══════════
        new("PosPurchaseReceipts", "Nhập hàng", "Phiếu nhập nhà cung cấp", CatWarehouse, 130),
        new("PosPurchaseReturns", "Trả hàng nhập", "Trả hàng nhà cung cấp", CatWarehouse, 131),
        new("PosStockCounts", "Kiểm kho", "Kiểm kê tồn kho", CatWarehouse, 132),
        new("PosDamageIssues", "Xuất hủy", "Xuất hủy hàng hỏng", CatWarehouse, 133),
        new("PosInternalUseIssues", "Xuất dùng nội bộ", "Xuất hàng dùng nội bộ", CatWarehouse, 134),

        // ══════════ BÁO CÁO BÁN HÀNG ══════════
        new("PosSalesReport", "Trung tâm báo cáo bán hàng", "Mở danh sách báo cáo bán hàng", CatSellReport, 140),
        new("PosReportRevenue", "Doanh thu", "Doanh thu theo thời gian", CatSellReport, 141),
        new("PosReportSoldGoods", "Hàng bán chạy", "Top hàng theo doanh thu", CatSellReport, 142),
        new("PosReportProfit", "Lợi nhuận", "Lợi nhuận gộp, giá vốn", CatSellReport, 143),
        new("PosReportPnl", "Kết quả kinh doanh", "Doanh thu, chi phí, lãi ròng", CatSellReport, 144),
        new("PosReportCashbook", "Sổ quỹ bán hàng", "Thu / chi / tồn quỹ", CatSellReport, 145),
        new("PosReportPayment", "Phương thức thanh toán", "Cơ cấu tiền mặt / chuyển khoản / thẻ", CatSellReport, 146),
        new("PosReportEndOfDay", "Tổng kết cuối ngày", "Báo cáo chốt ngày", CatSellReport, 147),
        new("PosReportStaffRevenue", "Doanh thu theo nhân viên", "Doanh thu theo người bán", CatSellReport, 148),
        new("PosReportStaffCommission", "Hoa hồng nhân viên", "Hoa hồng theo hàng / dịch vụ", CatSellReport, 149),
        new("PosReportStock", "Tồn kho", "Tồn kho hiện tại, sức khỏe tồn", CatSellReport, 150),
        new("PosReportPurchases", "Báo cáo nhập hàng", "Nhập / trả nhà cung cấp", CatSellReport, 151),
        new("PosReportExpiry", "Hàng sắp hết hạn", "Lô, hạn sử dụng", CatSellReport, 152),
        new("PosReportDebt", "Công nợ", "Công nợ khách và nhà cung cấp", CatSellReport, 153),
        new("PosReportExpense", "Chi phí", "Phiếu chi theo nhóm", CatSellReport, 154),
        new("PosReportVoucher", "Mã giảm giá", "Voucher đã dùng", CatSellReport, 155),
        new("HkdBooks", "Sổ thuế hộ kinh doanh", "Sổ sách thuế HKD (TT 152/2025)", CatSellReport, 156),

        // ══════════ THIẾT LẬP BÁN HÀNG ══════════
        new("SettingsHub", "Thiết lập SBOX", "Mở Thiết lập SBOX; thông tin cửa hàng, ngành hàng & cách bán, bàn / phòng, tích điểm, kiểm soát hủy / trả", CatSellSetup, 160),
        new("PosPrintTemplates", "Mẫu in", "Mẫu hóa đơn, phiếu bếp, tem", CatSellSetup, 161),
        new("PosPrinters", "Máy in thiết bị", "Bluetooth / LAN / USB trên máy này", CatSellSetup, 162),
        new("PosStorePrinters", "Máy in cloud", "Print Agent dùng chung cửa hàng", CatSellSetup, 163),
        new("PosCustomerDisplay", "Màn hình phụ", "Màn hình khách, quảng cáo", CatSellSetup, 164),
        new("PosEInvoice", "Hóa đơn điện tử", "Viettel, Easy Invoice, MISA, VNPT", CatSellSetup, 165),
        new("PosShipping", "Đơn vị giao hàng", "GHN, GHTK, Viettel Post, J&T, VNPost, AhaMove", CatSellSetup, 166),

        // ══════════ THIẾT LẬP NHÂN SỰ ══════════
        new("ShiftSetup", "Thiết lập ca", "Ca làm, vào sớm, trễ, tăng ca", CatHrSetup, 170),
        new("Holiday", "Ngày lễ", "Ngày nghỉ lễ, hệ số công", CatHrSetup, 171),
        new("Device", "Máy chấm công", "Kết nối, điều khiển máy chấm công", CatHrSetup, 172),
        new("Geofence", "Vùng chấm công", "Vị trí, bán kính, WiFi chấm công mobile", CatHrSetup, 173),
        new("SalarySettings", "Thiết lập lương", "Công thức, chế độ lương", CatHrSetup, 174),
        new("Allowance", "Phụ cấp", "Phụ cấp cố định / theo ngày / theo ca", CatHrSetup, 175),
        new("PenaltySetup", "Mức phạt", "Đi trễ, về sớm, tái phạm, quên chấm", CatHrSetup, 176),
        new("Insurance", "Bảo hiểm", "BHXH, BHYT, BHTN, lương cơ sở", CatHrSetup, 177),
        new("Tax", "Thuế TNCN", "Bậc thuế, giảm trừ gia cảnh", CatHrSetup, 178),
        new("ProductSalary", "Lương sản phẩm", "Đơn giá sản phẩm theo bậc", CatHrSetup, 179),
        new("NotificationSettings", "Thiết lập thông báo", "Nhóm thông báo, giờ yên lặng, mẫu", CatHrSetup, 180),
        new("GoogleDrive", "Google Drive", "Lưu ảnh qua service account", CatHrSetup, 181),

        // ══════════ QUẢN TRỊ ══════════
        new("UserManagement", "Tài khoản", "Người dùng, kích hoạt, vai trò", CatAdmin, 190),
        new("Role", "Phân quyền", "Vai trò, ma trận quyền, mẫu phân quyền", CatAdmin, 191),
        new("DepartmentPermission", "Phân quyền theo phòng ban", "Giới hạn dữ liệu theo cây phòng ban", CatAdmin, 192),
        new("Branch", "Chi nhánh", "Chi nhánh, tồn kho theo chi nhánh, chuyển kho", CatAdmin, 193),
        new("SystemSettings", "Tham số hệ thống", "Giờ chốt ngày, tham số vận hành", CatAdmin, 194),
        // Có ở mọi gói (không chọn theo gói); chủ / giám đốc luôn xem được, cấp thêm cho vai trò khác tại Phân quyền.
        new("ActivityLog", "Lịch sử thao tác", "Ai thêm / sửa / xóa gì, lúc nào (lưu 30 ngày)", CatAdmin, 195, false),

        // API / legacy aliases — seed only, not selectable in package UI
        new("Shift", "Ca làm việc (API)", "Đăng ký ca nhân viên", CatApi, 901, false),
        new("ShiftTemplate", "Mẫu ca (API)", "Mẫu ca làm việc", CatApi, 902, false),
        new("ShiftSalaryLevel", "Bậc lương ca (API)", "Bậc lương theo ca", CatApi, 903, false),
        new("Benefit", "Phúc lợi (API)", "Alias Thưởng/Phạt", CatApi, 904, false),
        new("Transaction", "Giao dịch (API)", "Alias Thu chi", CatApi, 905, false),
        new("Report", "Báo cáo (cũ)", "Alias báo cáo hiện đại", CatApi, 907, false),
        new("PosHub", "Trung tâm POS (API)", "Alias màn POS", CatApi, 908, false),
        new("PosReport", "Báo cáo POS (API)", "Alias báo cáo POS", CatApi, 909, false),
    ];

    /// <summary>Chức năng cần có trước (mã → các mã phụ thuộc).</summary>
    public static readonly IReadOnlyDictionary<string, string[]> Requires =
        new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase)
        {
            // Bán hàng / kho
            ["PosSell"] = ["PosProducts"],
            ["PosSaleOrders"] = ["PosSell"],
            ["PosSaleReturns"] = ["PosSell"],
            ["PosCashierShift"] = ["PosSell"],
            ["PosQrOrder"] = ["PosSell"],
            ["PosKds"] = ["PosSell"],
            ["PosBooking"] = ["PosSell"],
            ["PosWarranty"] = ["PosSell"],
            ["PosQuotes"] = ["PosProducts"],
            ["PosCustomerDisplay"] = ["PosSell"],
            ["PosEInvoice"] = ["PosSell"],
            ["PosShipping"] = ["PosSell"],
            ["PosPrinters"] = ["PosSell"],
            ["PosStorePrinters"] = ["PosSell"],
            ["PosPrintTemplates"] = ["PosSell"],
            ["PosPurchaseReceipts"] = ["PosProducts"],
            ["PosPurchaseReturns"] = ["PosPurchaseReceipts"],
            ["PosStockCounts"] = ["PosProducts"],
            ["PosDamageIssues"] = ["PosProducts"],
            ["PosInternalUseIssues"] = ["PosProducts"],
            ["PosSalesReport"] = ["PosSell"],
            ["PosReportRevenue"] = ["PosSalesReport"],
            ["PosReportSoldGoods"] = ["PosSalesReport"],
            ["PosReportProfit"] = ["PosSalesReport"],
            ["PosReportPnl"] = ["PosSalesReport"],
            ["PosReportCashbook"] = ["PosSalesReport"],
            ["PosReportPayment"] = ["PosSalesReport"],
            ["PosReportEndOfDay"] = ["PosSalesReport"],
            ["PosReportStaffRevenue"] = ["PosSalesReport"],
            ["PosReportStaffCommission"] = ["PosSalesReport"],
            ["PosReportStock"] = ["PosSalesReport"],
            ["PosReportPurchases"] = ["PosSalesReport", "PosPurchaseReceipts"],
            ["PosReportExpiry"] = ["PosSalesReport"],
            ["PosReportDebt"] = ["PosSalesReport", "PosCustomers"],
            ["PosReportExpense"] = ["PosSalesReport"],
            ["PosReportVoucher"] = ["PosSalesReport"],
            ["HkdBooks"] = ["PosSell"],
            // Nhân sự
            ["DeviceUser"] = ["Device"],
            ["Attendance"] = ["Employee"],
            ["MobileAttendance"] = ["Employee"],
            ["MobileDeviceRegistration"] = ["MobileAttendance"],
            ["MobileAttendanceApproval"] = ["MobileAttendance"],
            ["Geofence"] = ["MobileAttendance"],
            ["TravelHoursReport"] = ["MobileAttendance"],
            ["FieldCheckIn"] = ["MobileAttendance"],
            ["WorkSchedule"] = ["Employee"],
            ["ScheduleApproval"] = ["WorkSchedule"],
            ["ShiftSwap"] = ["WorkSchedule"],
            ["Leave"] = ["Employee"],
            ["LeaveReport"] = ["Leave"],
            ["Overtime"] = ["Employee"],
            ["AttendanceCorrection"] = ["Attendance"],
            ["AttendanceApproval"] = ["Attendance"],
            ["AttendanceSummary"] = ["Attendance"],
            ["AttendanceByShift"] = ["Attendance"],
            ["LateEarlyReport"] = ["Attendance"],
            ["AttendanceReport"] = ["Attendance"],
            ["Payroll"] = ["AttendanceSummary"],
            ["PenaltyTickets"] = ["Attendance"],
            ["PenaltyReport"] = ["PenaltyTickets"],
            ["AdvanceReport"] = ["AdvanceRequests"],
            ["BusinessTripReport"] = ["BusinessTripExpense"],
            ["CashReport"] = ["CashTransaction"],
            ["BankAccount"] = ["CashTransaction"],
            ["AssetReport"] = ["Asset"],
            ["ProductSalary"] = ["Production"],
            ["Department"] = ["Employee"],
            ["OrgChart"] = ["Department"],
            ["DepartmentPermission"] = ["Role", "Department"],
            ["DashboardAttendanceOverview"] = ["Dashboard", "Attendance"],
            ["DashboardHrInsights"] = ["Dashboard"],
            ["DashboardTodaySchedule"] = ["Dashboard", "WorkSchedule"],
            ["DashboardRealtimeAttendance"] = ["Dashboard", "Attendance"],
            ["DashboardAbsent"] = ["Dashboard", "Attendance"],
            ["DashboardLateEarly"] = ["Dashboard", "Attendance"],
            ["DashboardKpiPanel"] = ["Dashboard", "KPI"],
            ["DashboardInternalNews"] = ["Dashboard", "Communication"],
        };

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

    /// <summary>Các chức năng đã chọn nhưng thiếu chức năng cần có: (mã, mã còn thiếu).</summary>
    public static List<(string Code, string Missing)> MissingDependencies(IEnumerable<string> modules)
    {
        var set = new HashSet<string>(modules, StringComparer.OrdinalIgnoreCase);
        var result = new List<(string, string)>();
        foreach (var code in set)
        {
            if (!Requires.TryGetValue(code, out var reqs)) continue;
            foreach (var r in reqs)
                if (!set.Contains(r)) result.Add((code, r));
        }
        return result.OrderBy(x => x.Item1).ToList();
    }

    /// <summary>Thêm đệ quy mọi chức năng cần có.</summary>
    public static List<string> WithDependencies(IEnumerable<string> modules)
    {
        var set = new HashSet<string>(modules, StringComparer.OrdinalIgnoreCase);
        var queue = new Queue<string>(set);
        while (queue.Count > 0)
        {
            var c = queue.Dequeue();
            if (!Requires.TryGetValue(c, out var reqs)) continue;
            foreach (var r in reqs)
                if (set.Add(r)) queue.Enqueue(r);
        }
        return All.Where(m => set.Contains(m.Code)).Select(m => m.Code).ToList();
    }

    // ── Mẫu gói (nguồn duy nhất cho app quản trị) ──

    public sealed record PackagePreset(string Key, string Name, string Description, string ProductLine, IReadOnlyList<string> Modules);

    private static readonly string[] PosSellCore =
    [
        "Home", "Notification", "Dashboard", "PosSell", "PosProducts", "PosSaleOrders", "PosSaleReturns", "PosCustomers",
        "PosCashierShift", "PosBooking", "PosQrOrder", "PosWarranty", "PosSalesReport", "PosReportRevenue",
        "PosReportSoldGoods", "PosReportProfit", "PosReportPnl", "PosReportCashbook", "PosReportPayment",
        "PosReportEndOfDay", "PosReportStaffRevenue", "PosReportStaffCommission", "PosReportStock", "PosReportDebt",
        "PosReportExpense", "PosReportVoucher", "PosReportExpiry", "PosReportPurchases", "SettingsHub", "PosPrintTemplates",
        "PosPrinters", "PosCustomerDisplay", "PosEInvoice", "PosShipping", "UserManagement", "Role",
    ];

    private static readonly string[] PosWarehouse =
        ["PosPurchaseReceipts", "PosPurchaseReturns", "PosStockCounts", "PosDamageIssues", "PosInternalUseIssues"];

    private static readonly string[] HrmCore =
    [
        "Home", "Notification", "Dashboard", "DashboardAttendanceOverview", "DashboardHrInsights", "DashboardTodaySchedule",
        "DashboardRealtimeAttendance", "DashboardAbsent", "DashboardLateEarly", "Employee", "Department", "Attendance",
        "DeviceUser", "Device", "MobileAttendance", "MobileDeviceRegistration", "Geofence", "WorkSchedule", "ScheduleApproval",
        "ShiftSwap", "Leave", "Overtime", "AttendanceCorrection", "AttendanceApproval", "MobileAttendanceApproval",
        "AttendanceSummary", "AttendanceByShift", "Payroll", "Payslip", "LateEarlyReport", "AttendanceReport", "LeaveReport",
        "ShiftSetup", "Holiday", "SalarySettings", "Allowance", "PenaltySetup", "PenaltyTickets", "Insurance", "Tax",
        "NotificationSettings", "UserManagement", "Role",
    ];

    public static IReadOnlyList<PackagePreset> Presets
    {
        get
        {
            var all = PackageSelectable.Select(m => m.Code).ToList();
            var hrmAll = PackageSelectable.Where(m => ProductLineOf(m.Category) != "pos").Select(m => m.Code).ToList();
            return
            [
                new("pos_basic", "POS bán hàng", "Bán hàng, khách hàng, báo cáo, in ấn, hóa đơn điện tử, giao hàng", "pos", WithDependencies(PosSellCore)),
                new("pos_warehouse", "POS bán hàng + kho", "Thêm nhập hàng, kiểm kho, xuất hủy", "pos", WithDependencies(PosSellCore.Concat(PosWarehouse))),
                new("pos_full", "POS đầy đủ", "Thêm bếp KDS, báo giá, máy in cloud, sổ thuế HKD, chi nhánh, Trợ lý AI",
                    "pos", WithDependencies(PosSellCore.Concat(PosWarehouse).Concat(["PosKds", "PosQuotes", "PosStorePrinters", "HkdBooks", "Branch", "AIAssistant", "AIGemini", "SystemSettings"]))),
                new("hrm_basic", "HRM chấm công & lương", "Hồ sơ, chấm công máy + mobile, lịch ca, nghỉ phép, bảng lương", "hrm", WithDependencies(HrmCore)),
                new("hrm_full", "HRM đầy đủ", "Thêm tài chính nhân sự, công việc, truyền thông, suất ăn, tài sản, KPI, AI", "hrm", WithDependencies(hrmAll)),
                new("all", "Trọn bộ POS + HRM", "Tất cả chức năng", "both", all),
            ];
        }
    }

    // ── Loại thông báo đẩy (nguồn duy nhất) ──
    public static readonly IReadOnlyList<(string Code, string Name)> FcmCategories =
    [
        ("attendance", "Chấm công"), ("mobile_attendance", "Chấm công Mobile"), ("travel_attendance", "Chấm đi đường"),
        ("leave", "Nghỉ phép"), ("overtime", "Tăng ca"), ("shift", "Ca làm việc"), ("payroll", "Lương"),
        ("penalty", "Phiếu phạt"), ("transaction", "Thu chi"), ("business_trip", "Công tác"), ("approval", "Phê duyệt"),
        ("task", "Công việc"), ("internal_comm", "Truyền thông"), ("communication", "Truyền thông v2"), ("feedback", "Phản ánh"),
        ("meal", "Suất ăn"), ("kpi", "KPI"), ("hr", "Nhân sự"), ("device", "Thiết bị"), ("pos", "Bán hàng"),
        ("license", "Gia hạn / license"), ("system", "Hệ thống"),
    ];

    /// <summary>
    /// Customer-facing package detail: every ticked module plus always-on
    /// self-service screens, with Vietnamese names (no raw module codes).
    /// </summary>
    public static IReadOnlyList<PublicModuleLabel> DescribePublicModules(IEnumerable<string>? allowedCodes)
    {
        var set = new HashSet<string>(allowedCodes ?? [], StringComparer.OrdinalIgnoreCase);
        foreach (var self in SelfServiceModuleCodes)
            set.Add(self);

        return All
            .Where(m => m.SelectableForPackage && set.Contains(m.Code) && !m.Code.StartsWith("Dashboard", StringComparison.Ordinal)
                || m.Code == "Dashboard" && set.Contains(m.Code))
            .OrderBy(m => m.Order)
            .ThenBy(m => m.DisplayName, StringComparer.Ordinal)
            .Select(m => new PublicModuleLabel(m.Code, PublicDisplayName(m), PublicCategory(m.Category)))
            .ToList();
    }

    public static string PublicCategory(string category) => category;

    public static string PublicDisplayName(ModuleEntry m) => m.Code switch
    {
        "Dashboard" => "Tổng quan",
        "AIGemini" => "Thiết lập trí tuệ nhân tạo",
        "SettingsHub" => "Thiết lập SBOX",
        _ => m.DisplayName,
    };

    public sealed record PublicModuleLabel(string Code, string DisplayName, string Category);
}
