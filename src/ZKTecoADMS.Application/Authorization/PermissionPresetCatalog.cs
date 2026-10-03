namespace ZKTecoADMS.Application.Authorization;

/// <summary>Loại gói của cửa hàng — quyết định bộ mẫu phân quyền.</summary>
public enum PermissionPresetPackage
{
    /// <summary>Chỉ nhân sự / chấm công / lương.</summary>
    Hrm,
    /// <summary>Chỉ bán hàng / kho.</summary>
    Pos,
    /// <summary>Nhân sự + bán hàng.</summary>
    Full,
}

/// <summary>Một mẫu quyền cho một vai trò có sẵn (tài khoản chỉ gán được các vai trò hệ thống).</summary>
public sealed record PermissionPreset(
    string Id,
    string RoleName,
    string Title,
    string Description,
    PermissionPresetPackage[] Packages,
    string[]? ExtraRoles = null)
{
    /// <summary>Vai trò được phép áp mẫu này (mẫu tự phục vụ dùng chung cho Nhân viên / Thu ngân / Phục vụ).</summary>
    public bool FitsRole(string role) =>
        RoleName.Equals(role, StringComparison.OrdinalIgnoreCase) ||
        (ExtraRoles?.Contains(role, StringComparer.OrdinalIgnoreCase) ?? false);
}

/// <summary>
/// Mẫu phân quyền dựng sẵn cho gói HRM, POS và HRM + POS.
/// Mỗi mẫu gắn với một vai trò hệ thống (Giám đốc, Quản lý, Trưởng phòng, Kế toán, Thu ngân, Phục vụ, Nhân viên, Người dùng);
/// «chức danh» (Thủ kho, Nhân viên kinh doanh…) là cách dùng vai trò đó trong từng loại cửa hàng.
/// </summary>
public static class PermissionPresetCatalog
{
    // ── Mức quyền ─────────────────────────────────────────────────────────
    public readonly record struct Flags(bool V, bool C, bool E, bool D, bool X, bool A)
    {
        public static Flags operator |(Flags a, Flags b) =>
            new(a.V || b.V, a.C || b.C, a.E || b.E, a.D || b.D, a.X || b.X, a.A || b.A);
        public bool Any => V || C || E || D || X || A;
    }

    static readonly Flags N = new(false, false, false, false, false, false);
    /// <summary>Xem.</summary>
    static readonly Flags V = new(true, false, false, false, false, false);
    /// <summary>Xem + xuất.</summary>
    static readonly Flags VX = new(true, false, false, false, true, false);
    /// <summary>Gửi yêu cầu của mình (xem + thêm).</summary>
    static readonly Flags Req = new(true, true, false, false, false, false);
    /// <summary>Xem + sửa (vd công việc được giao, thiết lập).</summary>
    static readonly Flags VE = new(true, false, true, false, false, false);
    /// <summary>Duyệt (xem + duyệt + xuất).</summary>
    static readonly Flags Appr = new(true, false, false, false, true, true);
    /// <summary>Thao tác: xem, thêm, sửa, xuất.</summary>
    static readonly Flags Op = new(true, true, true, false, true, false);
    /// <summary>Quản lý: thao tác + duyệt (không xóa).</summary>
    static readonly Flags Mg = new(true, true, true, false, true, true);
    /// <summary>Toàn quyền.</summary>
    static readonly Flags F = new(true, true, true, true, true, true);

    // ── Nhóm chức năng ────────────────────────────────────────────────────
    static readonly string[] Dashboard =
    [
        "Home", "Notification", "Dashboard", "DashboardAttendanceOverview", "DashboardHrInsights",
        "DashboardTodaySchedule", "DashboardRealtimeAttendance", "DashboardAbsent", "DashboardLateEarly",
        "DashboardKpiPanel", "DashboardInternalNews",
    ];
    static readonly string[] HrProfile = ["Employee", "Department", "SalarySettings", "HrDocument", "OrgChart"];
    static readonly string[] Attendance =
    [
        "DeviceUser", "Leave", "Attendance", "WorkSchedule", "AttendanceCorrection", "AttendanceApproval",
        "MobileAttendanceApproval", "ScheduleApproval", "Overtime", "ShiftSwap", "MobileDeviceRegistration",
        "MobileAttendance",
    ];
    static readonly string[] HrReports =
    [
        "AttendanceSummary", "AttendanceByShift", "LateEarlyReport", "TravelHoursReport", "Payslip", "Payroll",
        "AttendanceReport", "HrAnalyticsReport", "LeaveReport", "CashReport", "PenaltyReport", "AdvanceReport",
        "BusinessTripReport", "AssetReport",
    ];
    static readonly string[] Finance =
        ["BonusPenalty", "PenaltyTickets", "AdvanceRequests", "BusinessTripExpense", "CashTransaction", "BankAccount"];
    static readonly string[] Operations =
        ["Meal", "Asset", "Task", "Communication", "KPI", "Production", "Feedback", "FieldCheckIn"];
    static readonly string[] HrSettings =
    [
        "ShiftSetup", "Holiday", "Device", "Allowance", "PenaltySetup", "Insurance", "Tax", "ProductSalary",
        "Geofence", "Shift", "ShiftTemplate", "ShiftSalaryLevel", "Benefit", "Transaction",
    ];
    static readonly string[] SystemSettings =
        ["Branch", "SystemSettings", "NotificationSettings", "AIGemini", "GoogleDrive", "SettingsHub"];
    static readonly string[] Admin = ["UserManagement", "Role", "DepartmentPermission", "ActivityLog"];

    static readonly string[] PosSell =
    [
        "PosSell", "PosSellPriceEdit", "PosSellDiscount", "PosSellCancelPaid", "PosSaleOrders", "PosSaleReturns",
        "PosCustomers", "PosWarranty", "PosBooking", "PosKds", "PosQrOrder", "PosCashierShift", "PosQuotes", "PosContracts",
    ];
    static readonly string[] PosStock =
    [
        "PosProducts", "PosViewCost", "PosPurchaseReceipts", "PosPurchaseReturns", "PosStockCounts",
        "PosDamageIssues", "PosInternalUseIssues",
    ];
    static readonly string[] PosReports =
    [
        "PosSalesReport", "PosReportRevenue", "PosReportSoldGoods", "PosReportStock", "PosReportPurchases",
        "PosReportPayment", "PosReportDebt", "PosReportExpiry", "PosReportProfit", "PosReportExpense",
        "PosReportEndOfDay", "PosReportStaffRevenue", "PosReportStaffCommission", "PosReportCashbook",
        "PosReportPnl", "PosReportVoucher", "HkdBooks", "PosReportStayGuests", "PosReportSessionExpiry",
    ];
    static readonly string[] PosSettings =
        ["PosPrintTemplates", "PosPrinters", "PosStorePrinters", "PosEInvoice", "PosShipping", "PosCustomerDisplay"];

    /// <summary>Chức năng thuộc nhóm HRM (dùng nhận diện gói của cửa hàng).</summary>
    public static readonly IReadOnlySet<string> HrmModules = new HashSet<string>(
        HrProfile.Concat(Attendance).Concat(HrReports).Concat(Operations).Concat(HrSettings)
            .Concat(["BonusPenalty", "PenaltyTickets", "AdvanceRequests", "BusinessTripExpense"])
            .Where(m => m is not ("Payslip")), StringComparer.OrdinalIgnoreCase);

    /// <summary>Chức năng thuộc nhóm POS.</summary>
    public static readonly IReadOnlySet<string> PosModules = new HashSet<string>(
        PosSell.Concat(PosStock).Concat(PosReports).Concat(PosSettings), StringComparer.OrdinalIgnoreCase);

    // ── Bộ dựng ───────────────────────────────────────────────────────────
    sealed class Builder
    {
        readonly Dictionary<string, Flags> _map = new(StringComparer.OrdinalIgnoreCase);
        public Builder Set(Flags f, params string[] modules)
        {
            foreach (var m in modules) _map[m] = f;
            return this;
        }
        public Builder Set(Flags f, IEnumerable<string> modules) => Set(f, modules.ToArray());
        public Builder Merge(IReadOnlyDictionary<string, Flags> other)
        {
            foreach (var (k, v) in other) _map[k] = _map.TryGetValue(k, out var cur) ? cur | v : v;
            return this;
        }
        public IReadOnlyDictionary<string, Flags> Build() => _map;
    }

    // ── Mẫu HRM ───────────────────────────────────────────────────────────
    static IReadOnlyDictionary<string, Flags> HrmDirector() => new Builder()
        .Set(V, Dashboard)
        .Set(F, HrProfile).Set(F, Attendance).Set(VX, HrReports).Set(F, Finance).Set(F, Operations)
        .Set(F, HrSettings).Set(VE, SystemSettings).Set(VX, Admin)
        .Build();

    static IReadOnlyDictionary<string, Flags> HrmManager() => new Builder()
        .Set(V, Dashboard)
        .Set(Mg, HrProfile).Set(Mg, Attendance).Set(VX, HrReports).Set(Mg, Finance).Set(Mg, Operations)
        .Set(Op, HrSettings).Set(V, SystemSettings).Set(V, "UserManagement", "ActivityLog")
        .Set(F, "Leave", "WorkSchedule", "Task")
        .Build();

    static IReadOnlyDictionary<string, Flags> HrmDepartmentHead() => new Builder()
        .Set(V, Dashboard)
        .Set(VX, "Employee").Set(V, "Department", "OrgChart", "HrDocument")
        // Duyệt cho nhân viên phòng mình (API tự giới hạn theo phòng ban)
        .Set(Appr, "Leave", "AttendanceCorrection", "AttendanceApproval", "MobileAttendanceApproval",
            "ScheduleApproval", "Overtime", "ShiftSwap")
        .Set(new Flags(true, false, false, false, false, true), "MobileDeviceRegistration")
        .Set(VX, "Attendance").Set(Mg, "WorkSchedule").Set(V, "DeviceUser").Set(Req, "MobileAttendance")
        .Set(VX, "AttendanceSummary", "AttendanceByShift", "LateEarlyReport", "TravelHoursReport", "AttendanceReport",
            "HrAnalyticsReport", "LeaveReport", "PenaltyReport")
        .Set(V, "Payslip")
        .Set(new Flags(true, true, true, false, true, true), "PenaltyTickets")
        .Set(V, "BonusPenalty").Set(Appr, "AdvanceRequests")
        .Set(new Flags(true, true, true, false, true, true), "BusinessTripExpense")
        .Set(Mg, "Task", "KPI").Set(Req, "Communication").Set(new Flags(true, true, false, false, false, true), "Feedback")
        .Set(V, "Meal", "Asset", "FieldCheckIn", "Holiday", "ShiftSetup")
        .Build();

    static IReadOnlyDictionary<string, Flags> HrmAccountant() => new Builder()
        .Set(V, Dashboard)
        .Set(VX, "Employee").Set(V, "Department").Set(Op, "SalarySettings")
        .Set(VX, "Attendance").Set(V, "Leave", "Overtime", "WorkSchedule", "ShiftSwap")
        .Set(VX, HrReports)
        .Set(Mg, "BonusPenalty", "AdvanceRequests").Set(Op, "PenaltyTickets")
        .Set(F, "BusinessTripExpense", "CashTransaction", "BankAccount")
        .Set(Op, "Allowance", "Insurance", "Tax", "PenaltySetup", "ProductSalary", "ShiftSalaryLevel", "Benefit", "Transaction")
        .Set(V, "Holiday", "ShiftSetup")
        .Set(VX, "Production", "KPI", "Meal").Set(Req, "Communication")
        .Build();

    /// <summary>Nhân viên: tự phục vụ — xem công / lương của mình, gửi đơn, chấm công mobile.</summary>
    static IReadOnlyDictionary<string, Flags> HrmEmployee() => new Builder()
        .Set(V, "Home", "Notification", "DashboardTodaySchedule", "DashboardInternalNews")
        .Set(V, "Employee", "Attendance", "Payslip", "PenaltyTickets", "BonusPenalty",
            "MobileDeviceRegistration", "OrgChart")
        .Set(Req, "Communication")
        .Set(Req, "Leave", "Overtime", "ShiftSwap", "AttendanceCorrection", "AttendanceApproval", "AdvanceRequests",
            "BusinessTripExpense", "MobileAttendance", "WorkSchedule", "Feedback", "Meal")
        .Set(VE, "Task")
        .Build();

    static IReadOnlyDictionary<string, Flags> UserOnly() => new Builder()
        .Set(V, "Home", "Notification")
        .Build();

    // ── Mẫu POS ───────────────────────────────────────────────────────────
    static IReadOnlyDictionary<string, Flags> PosDirector() => new Builder()
        .Set(V, "Home", "Notification", "Dashboard")
        .Set(F, PosSell).Set(F, PosStock).Set(VX, PosReports).Set(F, PosSettings)
        .Set(F, "CashTransaction", "BankAccount").Set(VE, SystemSettings).Set(VX, Admin)
        .Set(new Flags(true, false, true, false, true, false), "HkdBooks")
        .Build();

    static IReadOnlyDictionary<string, Flags> PosManager() => new Builder()
        .Set(V, "Home", "Notification", "Dashboard")
        .Set(Mg, PosSell).Set(F, "PosSellPriceEdit", "PosSellDiscount", "PosSellCancelPaid", "PosSaleOrders")
        .Set(Mg, PosStock).Set(V, "PosViewCost")
        .Set(VX, PosReports).Set(Op, PosSettings)
        .Set(Mg, "CashTransaction").Set(V, "BankAccount")
        .Set(VE, "SettingsHub").Set(V, "Branch", "UserManagement")
        .Build();

    static IReadOnlyDictionary<string, Flags> PosAccountant() => new Builder()
        .Set(V, "Home", "Notification", "Dashboard")
        .Set(VX, PosReports).Set(new Flags(true, false, true, false, true, false), "HkdBooks")
        .Set(VX, "PosSaleOrders").Set(V, "PosSaleReturns", "PosQuotes", "PosContracts", "PosProducts", "PosViewCost")
        .Set(Op, "PosCustomers", "PosPurchaseReceipts", "PosPurchaseReturns")
        .Set(new Flags(true, false, true, false, true, true), "PosEInvoice")
        .Set(F, "CashTransaction", "BankAccount")
        .Build();

    /// <summary>Thủ kho (vai trò Trưởng phòng ở cửa hàng bán hàng).</summary>
    static IReadOnlyDictionary<string, Flags> PosWarehouse() => new Builder()
        .Set(V, "Home", "Notification")
        .Set(Op, "PosProducts").Set(V, "PosViewCost")
        .Set(Mg, "PosPurchaseReceipts", "PosPurchaseReturns", "PosStockCounts", "PosDamageIssues", "PosInternalUseIssues")
        .Set(VX, "PosReportStock", "PosReportExpiry", "PosReportPurchases")
        .Set(V, "PosSaleOrders", "PosPrintTemplates", "PosPrinters")
        .Build();

    static IReadOnlyDictionary<string, Flags> PosCashier() => new Builder()
        .Set(V, "Home", "Notification")
        .Set(new Flags(true, true, true, false, false, true), "PosSell")
        .Set(VE, "PosSellDiscount")
        .Set(V, "PosSaleOrders", "PosWarranty", "PosProducts", "PosPrintTemplates", "PosPrinters", "PosSalesReport")
        .Set(new Flags(true, false, false, false, false, true), "PosSaleReturns")
        .Set(Op, "PosCustomers").Set(new Flags(true, true, true, false, false, false), "PosBooking")
        .Set(Req, "PosKds", "PosCashierShift", "PosCustomerDisplay")
        .Set(new Flags(true, false, true, false, false, true), "PosQrOrder")
        .Set(new Flags(true, false, false, false, false, true), "PosEInvoice")
        .Set(VX, "PosReportEndOfDay")
        .Set(Req, "CashTransaction")
        .Build();

    static IReadOnlyDictionary<string, Flags> PosWaiter() => new Builder()
        .Set(V, "Home", "Notification")
        .Set(new Flags(true, true, true, false, false, false), "PosSell", "PosBooking")
        .Set(Req, "PosKds")
        .Set(V, "PosQrOrder", "PosCustomers", "PosProducts", "PosPrinters", "PosPrintTemplates")
        .Build();

    /// <summary>Nhân viên kinh doanh (vai trò Nhân viên ở cửa hàng bán hàng): báo giá, khách hàng, tra hàng.</summary>
    static IReadOnlyDictionary<string, Flags> PosSales() => new Builder()
        .Set(V, "Home", "Notification")
        .Set(Op, "PosQuotes", "PosContracts", "PosCustomers")
        .Set(V, "PosProducts", "PosWarranty", "PosSell")
        .Set(new Flags(true, true, true, false, false, false), "PosBooking")
        .Build();

    static IReadOnlyDictionary<string, Flags> Merge(params IReadOnlyDictionary<string, Flags>[] parts)
    {
        var b = new Builder();
        foreach (var p in parts) b.Merge(p);
        return b.Build();
    }

    // ── Danh mục ──────────────────────────────────────────────────────────
    static readonly PermissionPresetPackage[] H = [PermissionPresetPackage.Hrm];
    static readonly PermissionPresetPackage[] P = [PermissionPresetPackage.Pos];
    static readonly PermissionPresetPackage[] B = [PermissionPresetPackage.Full];
    static readonly PermissionPresetPackage[] All =
        [PermissionPresetPackage.Hrm, PermissionPresetPackage.Pos, PermissionPresetPackage.Full];

    static readonly (PermissionPreset Meta, Func<IReadOnlyDictionary<string, Flags>> Build)[] Items =
    [
        // HRM
        (new("hrm.director", "Director", "Giám đốc", "Toàn quyền nhân sự, chấm công, lương, tài chính; xem thiết lập hệ thống.", H), HrmDirector),
        (new("hrm.manager", "Manager", "Quản lý nhân sự", "Hồ sơ, chấm công, lịch, duyệt đơn, thưởng phạt, ứng lương; sửa thiết lập ca / phụ cấp.", H), HrmManager),
        (new("hrm.depthead", "DepartmentHead", "Trưởng phòng", "Xem nhân viên phòng mình, duyệt nghỉ / tăng ca / sửa công / lịch, giao việc, KPI.", H), HrmDepartmentHead),
        (new("hrm.accountant", "Accountant", "Kế toán lương", "Bảng lương, phiếu lương, phụ cấp, thuế, bảo hiểm, thưởng phạt, ứng lương, thu chi.", H), HrmAccountant),
        (new("hrm.employee", "Employee", "Nhân viên", "Tự phục vụ: chấm công mobile, xem công / phiếu lương, gửi đơn nghỉ / tăng ca / ứng lương.", All,
            ["Cashier", "Waiter"]), HrmEmployee),
        // POS
        (new("pos.director", "Director", "Chủ cửa hàng", "Toàn quyền bán hàng, kho, báo cáo, thu chi, thiết lập cửa hàng.", P), PosDirector),
        (new("pos.manager", "Manager", "Quản lý cửa hàng", "Bán hàng, sửa giá / giảm giá / hủy hóa đơn, hàng hóa, kho, báo cáo, thu chi.", P), PosManager),
        (new("pos.accountant", "Accountant", "Kế toán bán hàng", "Báo cáo doanh thu / lợi nhuận / sổ quỹ, công nợ, nhập hàng, HĐĐT, thu chi, sổ thuế.", P), PosAccountant),
        (new("pos.warehouse", "DepartmentHead", "Thủ kho", "Hàng hóa, nhập / trả hàng NCC, kiểm kho, xuất hủy, báo cáo tồn kho.", [PermissionPresetPackage.Pos, PermissionPresetPackage.Full]), PosWarehouse),
        (new("pos.cashier", "Cashier", "Thu ngân", "Bán hàng, thanh toán, giảm giá, trả hàng, khách hàng, ca thu ngân, tổng kết cuối ngày.", P), PosCashier),
        (new("pos.waiter", "Waiter", "Phục vụ / Order", "Gọi món, tạm tính, màn hình bếp, đặt bàn — không thanh toán.", P), PosWaiter),
        (new("pos.sales", "Employee", "Nhân viên kinh doanh", "Báo giá, khách hàng, tra hàng / giá — không bán tại quầy.", P), PosSales),
        // HRM + POS
        (new("full.director", "Director", "Giám đốc", "Toàn quyền nhân sự và bán hàng.", B), () => Merge(HrmDirector(), PosDirector())),
        (new("full.manager", "Manager", "Quản lý (nhân sự + cửa hàng)", "Quản lý nhân sự và vận hành cửa hàng: bán hàng, kho, báo cáo, duyệt đơn.", B), () => Merge(HrmManager(), PosManager())),
        (new("full.depthead", "DepartmentHead", "Trưởng phòng / Trưởng ca", "Duyệt công, nghỉ, lịch cho nhân viên phòng mình; xem báo cáo bán hàng.", B),
            () => Merge(HrmDepartmentHead(), new Builder().Set(V, "PosSalesReport", "PosReportEndOfDay", "PosReportStaffRevenue", "PosSaleOrders").Build())),
        (new("full.accountant", "Accountant", "Kế toán tổng hợp", "Lương, thu chi, công nợ, báo cáo bán hàng, nhập hàng, HĐĐT.", B), () => Merge(HrmAccountant(), PosAccountant())),
        (new("full.cashier", "Cashier", "Thu ngân", "Bán hàng, thanh toán + tự phục vụ nhân sự (chấm công, phiếu lương, đơn nghỉ).", B), () => Merge(PosCashier(), HrmEmployee())),
        (new("full.waiter", "Waiter", "Phục vụ / Order", "Gọi món, bếp, đặt bàn + tự phục vụ nhân sự.", B), () => Merge(PosWaiter(), HrmEmployee())),
        (new("full.warehouse", "DepartmentHead", "Thủ kho", "Kho hàng + tự phục vụ nhân sự.", B), () => Merge(PosWarehouse(), HrmEmployee())),
        (new("full.sales", "Employee", "Nhân viên kinh doanh", "Báo giá, khách hàng + tự phục vụ nhân sự.", B), () => Merge(PosSales(), HrmEmployee())),
        // Chung
        (new("any.user", "User", "Người dùng", "Chỉ trang chủ và thông báo.", All), UserOnly),
    ];

    /// <summary>Mẫu mặc định cho từng vai trò theo gói — dùng khi tạo cửa hàng và «Áp dụng bộ mẫu».</summary>
    public static IReadOnlyDictionary<string, string> Defaults(PermissionPresetPackage package) => package switch
    {
        PermissionPresetPackage.Hrm => new Dictionary<string, string>
        {
            ["Director"] = "hrm.director", ["Manager"] = "hrm.manager", ["DepartmentHead"] = "hrm.depthead",
            ["Accountant"] = "hrm.accountant", ["Employee"] = "hrm.employee", ["Cashier"] = "hrm.employee",
            ["Waiter"] = "hrm.employee", ["User"] = "any.user",
        },
        PermissionPresetPackage.Pos => new Dictionary<string, string>
        {
            ["Director"] = "pos.director", ["Manager"] = "pos.manager", ["DepartmentHead"] = "pos.warehouse",
            ["Accountant"] = "pos.accountant", ["Cashier"] = "pos.cashier", ["Waiter"] = "pos.waiter",
            ["Employee"] = "pos.sales", ["User"] = "any.user",
        },
        _ => new Dictionary<string, string>
        {
            ["Director"] = "full.director", ["Manager"] = "full.manager", ["DepartmentHead"] = "full.depthead",
            ["Accountant"] = "full.accountant", ["Cashier"] = "full.cashier", ["Waiter"] = "full.waiter",
            ["Employee"] = "hrm.employee", ["User"] = "any.user",
        },
    };

    public static IReadOnlyList<PermissionPreset> List(PermissionPresetPackage? package = null) =>
        Items.Select(i => i.Meta)
            .Where(m => package == null || m.Packages.Contains(package.Value))
            .ToList();

    public static PermissionPreset? Find(string id) =>
        Items.FirstOrDefault(i => i.Meta.Id.Equals(id, StringComparison.OrdinalIgnoreCase)).Meta;

    /// <summary>Quyền của mẫu cho từng chức năng (chức năng không có trong mẫu = không có quyền).</summary>
    public static IReadOnlyDictionary<string, Flags> Build(string id)
    {
        var item = Items.FirstOrDefault(i => i.Meta.Id.Equals(id, StringComparison.OrdinalIgnoreCase));
        return item.Meta == null ? new Dictionary<string, Flags>() : item.Build();
    }

    /// <summary>
    /// Quyền của mẫu cho một chức năng, đã lọc theo gói của cửa hàng
    /// (chức năng ngoài gói → không cấp, trừ chức năng tự phục vụ luôn có).
    /// </summary>
    public static Flags FlagsFor(IReadOnlyDictionary<string, Flags> preset, string module, ISet<string>? allowedModules)
    {
        if (!preset.TryGetValue(module, out var f)) return N;
        if (allowedModules != null && allowedModules.Count > 0 && !FeatureModuleCatalog.IsSelfService(module)
            && !allowedModules.Contains(module) && !IsSubModuleAllowed(module, allowedModules))
            return N;
        return f;
    }

    /// <summary>Quyền con không chọn theo gói — đi theo chức năng cha.</summary>
    static bool IsSubModuleAllowed(string module, ISet<string> allowed) => module switch
    {
        "PosSellPriceEdit" or "PosSellDiscount" or "PosSellCancelPaid" => allowed.Contains("PosSell"),
        "PosViewCost" => allowed.Contains("PosProducts"),
        "ActivityLog" or "Dashboard" => true,
        _ => false,
    };

    /// <summary>Nhận diện gói từ danh sách chức năng được phép của cửa hàng.</summary>
    public static PermissionPresetPackage Detect(IEnumerable<string>? allowedModules)
    {
        var list = allowedModules?.ToList() ?? [];
        if (list.Count == 0) return PermissionPresetPackage.Full;
        var hasPos = list.Any(m => PosModules.Contains(m));
        var hasHrm = list.Any(m => HrmModules.Contains(m));
        return (hasHrm, hasPos) switch
        {
            (true, false) => PermissionPresetPackage.Hrm,
            (false, true) => PermissionPresetPackage.Pos,
            _ => PermissionPresetPackage.Full,
        };
    }

    public static string PackageLabel(PermissionPresetPackage p) => p switch
    {
        PermissionPresetPackage.Hrm => "Nhân sự (HRM)",
        PermissionPresetPackage.Pos => "Bán hàng (POS)",
        _ => "Nhân sự + Bán hàng",
    };
}
