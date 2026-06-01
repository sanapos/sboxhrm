using ZKTecoADMS.Application.Authorization;
using ZKTecoADMS.Application.DTOs.Permissions;

namespace ZKTecoADMS.Api.Services;

/// <summary>
/// Maps AI ACTION/CREATE tags to module permissions (aligned with Flutter PermissionProvider).
/// </summary>
public static class AiAssistantPermissionRules
{
    private sealed record Rule(string Module, bool RequiresCreate);

    private static readonly Dictionary<string, Rule> ActionRules = new(StringComparer.Ordinal)
    {
        ["nav_dashboard"] = new("Dashboard", false),
        ["nav_attendance"] = new("Attendance", false),
        ["nav_attendance_history"] = new("Attendance", false),
        ["nav_leave"] = new("Leave", false),
        ["nav_leave_create"] = new("Leave", true),
        ["nav_payroll"] = new("Payslip", false),
        ["nav_payslip"] = new("Payslip", false),
        ["nav_kpi"] = new("KPI", false),
        ["nav_communication"] = new("Communication", false),
        ["nav_meal"] = new("Meal", false),
        ["nav_meal_register"] = new("Meal", true),
        ["nav_tasks"] = new("Task", false),
        ["nav_assets"] = new("Asset", false),
        ["nav_cash"] = new("CashTransaction", false),
        ["nav_bonus_penalty"] = new("BonusPenalty", false),
        ["nav_advance"] = new("AdvanceRequests", false),
        ["nav_advance_create"] = new("AdvanceRequests", true),
        ["nav_overtime"] = new("Overtime", false),
        ["nav_overtime_create"] = new("Overtime", true),
        ["nav_field_checkin"] = new("FieldCheckIn", false),
        ["nav_field_checkin_create"] = new("FieldCheckIn", true),
        ["nav_attendance_correction"] = new("AttendanceCorrection", false),
        ["nav_attendance_correction_create"] = new("AttendanceCorrection", true),
        ["nav_work_schedule"] = new("WorkSchedule", false),
        ["nav_shift_change"] = new("ShiftSwap", true),
        ["nav_feedback"] = new("Feedback", false),
        ["nav_feedback_create"] = new("Feedback", true),
        ["nav_employees"] = new("Employee", false),
        ["nav_departments"] = new("Department", false),
    };

    private static readonly Dictionary<string, Rule> CreateRules = new(StringComparer.Ordinal)
    {
        ["attendance_correction"] = new("AttendanceCorrection", true),
        ["leave"] = new("Leave", true),
        ["advance"] = new("AdvanceRequests", true),
        ["feedback"] = new("Feedback", true),
        ["meal"] = new("Meal", true),
        ["field_assignment"] = new("FieldCheckIn", true),
        ["shift_swap"] = new("ShiftSwap", true),
        ["overtime"] = new("Overtime", true),
    };

    public static bool IsSuperRole(string role) => ModulePermissionDefaults.IsSuperRole(role);

    public static bool CanAction(string action, IReadOnlyDictionary<string, ModulePermissionDto> perms, bool isSuperUser)
    {
        if (isSuperUser) return true;
        if (!ActionRules.TryGetValue(action, out var rule)) return false;
        return Check(perms, rule);
    }

    public static bool CanCreate(string createTag, IReadOnlyDictionary<string, ModulePermissionDto> perms, bool isSuperUser)
    {
        if (isSuperUser) return true;
        var type = createTag.Split(',', 2)[0].Trim();
        if (!CreateRules.TryGetValue(type, out var rule)) return false;
        return Check(perms, rule);
    }

    private static bool Check(IReadOnlyDictionary<string, ModulePermissionDto> perms, Rule rule)
    {
        if (!perms.TryGetValue(rule.Module, out var p)) return false;
        return rule.RequiresCreate ? p.CanCreate : p.CanView;
    }

    public static List<string> AllowedActionTags(IReadOnlyDictionary<string, ModulePermissionDto> perms, bool isSuperUser)
    {
        if (isSuperUser) return ActionRules.Keys.OrderBy(k => k).ToList();
        return ActionRules
            .Where(kv => Check(perms, kv.Value))
            .Select(kv => kv.Key)
            .OrderBy(k => k)
            .ToList();
    }

    public static List<string> AllowedCreateExamples(IReadOnlyDictionary<string, ModulePermissionDto> perms, bool isSuperUser)
    {
        if (isSuperUser) return CreateRules.Keys.OrderBy(k => k).ToList();
        return CreateRules
            .Where(kv => Check(perms, kv.Value))
            .Select(kv => kv.Key)
            .OrderBy(k => k)
            .ToList();
    }

    public static string BuildPermissionsSummary(
        IReadOnlyDictionary<string, ModulePermissionDto> perms,
        bool isSuperUser,
        string role)
    {
        if (isSuperUser)
            return $"Vai trò {role}: toàn quyền (Admin/SuperAdmin/Agent).";

        var viewable = perms.Values.Where(p => p.CanView).Select(p => p.ModuleDisplayName ?? p.Module).Take(20).ToList();
        var creatable = perms.Values.Where(p => p.CanCreate).Select(p => p.ModuleDisplayName ?? p.Module).Take(15).ToList();
        var lines = new List<string> { $"Vai trò: {role}" };
        if (viewable.Count > 0)
            lines.Add("Được xem: " + string.Join(", ", viewable));
        if (creatable.Count > 0)
            lines.Add("Được tạo mới: " + string.Join(", ", creatable));
        return string.Join("\n", lines);
    }
}
