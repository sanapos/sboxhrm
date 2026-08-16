namespace ZKTecoADMS.Application.Authorization;

/// <summary>Default module permissions when seeding role permissions (aligned with Flutter UI).</summary>
public static class ModulePermissionDefaults
{
    public static bool IsSuperRole(string role) =>
        role is "SuperAdmin" or "Agent" or "Admin" or "Director";

    private static readonly HashSet<string> DashboardWidgetModules = new(StringComparer.OrdinalIgnoreCase)
    {
        "DashboardAttendanceOverview", "DashboardHrInsights", "DashboardTodaySchedule",
        "DashboardRealtimeAttendance", "DashboardAbsent", "DashboardLateEarly",
        "DashboardKpiPanel", "DashboardInternalNews"
    };

    private static bool IsDashboardFamily(string normalizedModule) =>
        normalizedModule == "dashboard" ||
        DashboardWidgetModules.Contains(normalizedModule);

    public static (bool canView, bool canCreate, bool canEdit, bool canDelete, bool canExport, bool canApprove)
        Get(string roleName, string module)
    {
        var m = NormalizeModule(module);
        if (DashboardWidgetModules.Contains(module))
            m = "dashboard";
        return roleName.ToLowerInvariant() switch
        {
            "admin" => (true, true, true, true, true, true),
            "director" => DirectorDefaults(m),
            "accountant" => AccountantDefaults(m),
            "departmenthead" => DepartmentHeadDefaults(m),
            "manager" => ManagerDefaults(m),
            "employee" => EmployeeDefaults(m),
            "cashier" => CashierDefaults(m),
            "waiter" => WaiterDefaults(m),
            "user" => UserDefaults(m),
            _ => (false, false, false, false, false, false)
        };
    }

    private static string NormalizeModule(string module)
    {
        return module.ToLowerInvariant() switch
        {
            "salary" => "salarysettings",
            "report" => "hrreport",
            "advance" => "advancerequests",
            "benefit" => "bonuspenalty",
            "workshedule" => "workschedule",
            "attendancecorrection" => "attendanceapproval",
            _ => module.ToLowerInvariant()
        };
    }

    private static (bool, bool, bool, bool, bool, bool) DirectorDefaults(string m) => m switch
    {
        "settings" or "device" or "geofence" or "deviceuser" or "systemsettings" or "notificationsettings"
            or "aigemini" => (true, false, false, false, false, false),
        "store" or "role" or "usermanagement" or "departmentpermission" or "settingshub"
            => (true, false, false, false, true, false),
        _ => (true, true, true, true, true, true)
    };

    private static (bool, bool, bool, bool, bool, bool) AccountantDefaults(string m) => m switch
    {
        "salarysettings" or "payslip" or "payroll" or "allowance" or "insurance" or "tax"
            or "transaction" or "cashtransaction" or "bonuspenalty" or "bankaccount"
            or "advancerequests" or "penaltysetup" or "productsalary" or "shiftsalarylevel"
            => (true, true, true, true, true, false),
        "businesstripexpense"
            => (true, true, true, true, true, true),
        "hrreport" or "attendancereport" or "payrollreport" or "leavereport" or "cashreport"
            or "penaltyreport" or "advancereport" or "businesstripreport"
            => (true, false, false, false, true, false),
        "employee" or "attendance" or "attendancesummary" or "attendancebyshift"
            => (true, false, false, false, true, false),
        "notification" => (true, false, false, true, false, false),
        _ when IsDashboardFamily(m) || m is "leave" or "shift" or "workschedule"
            or "holiday" or "overtime" or "settingshub"
            => (true, false, false, false, false, false),
        _ => (false, false, false, false, false, false)
    };

    private static (bool, bool, bool, bool, bool, bool) DepartmentHeadDefaults(string m) => m switch
    {
        "employee" or "attendance" or "attendancesummary" or "attendancebyshift" or "leave"
            or "shift" or "workschedule" or "overtime" or "attendanceapproval" or "scheduleapproval"
            or "shiftswap" or "task" or "kpi" or "hrdocument" or "penaltytickets"
            => (true, true, true, true, true, true),
        "notification" or "communication" => (true, true, false, true, false, false),
        "hrreport" or "attendancereport" or "payrollreport" or "salarysettings" or "payslip" or "payroll"
            => (true, false, false, false, true, false),
        "businesstripexpense"
            => (true, true, true, false, false, true),
        _ when IsDashboardFamily(m) || m is "allowance" or "holiday" or "insurance"
            or "advance" or "advancerequests"
            or "shifttemplate" or "shiftsalarylevel" or "bonuspenalty" or "asset" or "orgchart"
            or "department" or "meal" or "fieldcheckin" or "feedback" or "settingshub"
            => (true, false, false, false, false, false),
        _ => (false, false, false, false, false, false)
    };

    private static (bool, bool, bool, bool, bool, bool) ManagerDefaults(string m) => m switch
    {
        "settings" or "store" or "role" or "usermanagement" or "systemsettings" or "departmentpermission"
            => (true, false, false, false, false, false),
        "notification" => (true, false, false, true, false, false),
        _ => (true, true, true, true, true, true)
    };

    private static (bool, bool, bool, bool, bool, bool) CashierDefaults(string m) => m switch
    {
        "notification" => (true, false, false, false, false, false),
        _ when IsDashboardFamily(m) || m is "home"
            => (true, false, false, false, false, false),
        // View + Create (order) + Approve (thanh toán)
        "possell" => (true, true, false, false, false, true),
        "posproducts" => (true, false, false, false, false, false),
        "posprinttemplates" => (true, false, false, false, false, false),
        "possaleorders" => (true, false, false, false, false, false),
        "poscustomers" => (true, true, true, false, false, false),
        "posbooking" => (true, true, false, false, false, false),
        "poswarranty" => (true, false, false, false, false, false),
        "poscustomerdisplay" => (true, true, false, false, false, false),
        "poseinvoice" => (true, false, false, false, false, true),
        "poskds" => (true, true, false, false, false, false),
        "posqrorder" => (true, false, true, false, false, false),
        "poscashiershift" => (true, true, false, false, false, false),
        "posprinters" => (true, false, false, false, false, false),
        "possalesreport" => (true, false, false, false, true, false),
        _ when m.StartsWith("posreport", StringComparison.Ordinal) =>
            (true, false, false, false, true, false),
        _ => (false, false, false, false, false, false)
    };

    /// <summary>Order: gọi món / tạm tính — không thanh toán (CanApprove = false).</summary>
    private static (bool, bool, bool, bool, bool, bool) WaiterDefaults(string m) => m switch
    {
        "notification" => (true, false, false, false, false, false),
        _ when IsDashboardFamily(m) || m is "home"
            => (true, false, false, false, false, false),
        "possell" => (true, true, false, false, false, false),
        "posproducts" => (true, false, false, false, false, false),
        "posprinttemplates" => (true, false, false, false, false, false),
        "possaleorders" => (true, false, false, false, false, false),
        "poscustomers" => (true, false, false, false, false, false),
        "posbooking" => (true, true, false, false, false, false),
        "poswarranty" => (true, false, false, false, false, false),
        "poscustomerdisplay" => (true, false, false, false, false, false),
        "poseinvoice" => (false, false, false, false, false, false),
        "poskds" => (true, true, false, false, false, false),
        "posqrorder" => (true, false, false, false, false, false),
        "poscashiershift" => (false, false, false, false, false, false),
        "posprinters" => (true, false, false, false, false, false),
        _ => (false, false, false, false, false, false)
    };

    /// <summary>
    /// Nhân viên — chỉ self-service cá nhân.
    /// Không Payroll (tránh implicit grant mở rộng), không báo cáo quản trị, không thiết bị/cài đặt hệ thống.
    /// </summary>
    private static (bool, bool, bool, bool, bool, bool) EmployeeDefaults(string m) => m switch
    {
        "notification" => (true, false, false, false, false, false),
        _ when IsDashboardFamily(m) || m is "home" or "settings"
            => (true, false, false, false, false, false),

        // Hồ sơ / chấm công / lương phiếu / phạt của mình (API vẫn scope theo EmployeeId)
        "employee" or "attendance" or "attendancesummary" or "attendancebyshift"
            or "payslip" or "penaltytickets" or "bonuspenalty" or "mobiledeviceregistration"
            or "communication"
            => (true, false, false, false, false, false),

        // Đăng ký / yêu cầu
        "leave" or "overtime" or "shiftswap" or "advancerequests" or "businesstripexpense"
            or "attendanceapproval" or "feedback" or "mobileattendance" or "workschedule"
            => (true, true, false, false, false, false),

        // Công việc được giao
        "task" => (true, false, true, false, false, false),

        // Suất ăn cá nhân (nếu module có trong gói)
        "meal" => (true, true, false, false, false, false),

        _ => (false, false, false, false, false, false)
    };

    private static (bool, bool, bool, bool, bool, bool) UserDefaults(string m) => m switch
    {
        _ when IsDashboardFamily(m) || m is "home"
            => (true, false, false, false, false, false),
        _ => (false, false, false, false, false, false)
    };
}
