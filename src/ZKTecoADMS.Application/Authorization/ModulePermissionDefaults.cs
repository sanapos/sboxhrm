namespace ZKTecoADMS.Application.Authorization;

/// <summary>Default module permissions when seeding role permissions (aligned with Flutter UI).</summary>
public static class ModulePermissionDefaults
{
    public static bool IsSuperRole(string role) =>
        role is "SuperAdmin" or "Agent" or "Admin";

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
        "hrreport" or "attendancereport" or "payrollreport" or "leavereport" or "cashreport"
            or "penaltyreport" or "advancereport"
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
            => (true, true, true, false, true, true),
        "notification" or "communication" => (true, true, false, true, false, false),
        "hrreport" or "attendancereport" or "payrollreport" or "salarysettings" or "payslip" or "payroll"
            => (true, false, false, false, true, false),
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
        _ => (true, true, true, false, true, true)
    };

    private static (bool, bool, bool, bool, bool, bool) EmployeeDefaults(string m) => m switch
    {
        "notification" => (true, false, false, true, false, false),
        _ when IsDashboardFamily(m) || m is "attendance" or "attendancesummary" or "attendancebyshift"
            or "workschedule" or "payslip" or "shift" or "home"
            => (true, false, false, false, false, false),
        "leave" or "shiftswap" or "attendanceapproval" or "attendancecorrection" or "overtime"
            => (true, true, false, false, false, false),
        "task" => (true, false, true, false, false, false),
        "fieldcheckin" or "feedback" => (true, true, true, false, false, false),
        _ => (false, false, false, false, false, false)
    };

    private static (bool, bool, bool, bool, bool, bool) UserDefaults(string m) => m switch
    {
        _ when IsDashboardFamily(m) || m is "home"
            => (true, false, false, false, false, false),
        _ => (false, false, false, false, false, false)
    };
}
