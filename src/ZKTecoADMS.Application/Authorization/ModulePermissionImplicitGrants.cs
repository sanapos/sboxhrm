using ZKTecoADMS.Application.Constants;
using ZKTecoADMS.Application.DTOs.Permissions;

namespace ZKTecoADMS.Application.Authorization;

/// <summary>
/// Cross-module permission aliases (UI module codes vs API module codes).
/// Evaluated when direct module permission is missing.
/// </summary>
public static class ModulePermissionImplicitGrants
{
    private static readonly HashSet<string> PayrollReadModules = new(StringComparer.Ordinal)
    {
        "Employee", "Attendance", "AttendanceSummary", "AttendanceByShift", "Leave",
        "SalarySettings", "Insurance", "Tax", "PenaltySetup", "Allowance", "Holiday",
        "AdvanceRequests", "Transaction", "PenaltyTickets", "KPI", "Production",
        "ShiftSalaryLevel", "WorkSchedule", "ShiftSetup", "Benefit", "BonusPenalty",
        "SystemSettings"
    };

    private static readonly HashSet<string> AttendanceReadModules = new(StringComparer.Ordinal)
    {
        "Attendance", "AttendanceSummary", "AttendanceByShift"
    };

    private static readonly HashSet<string> ApprovalAttendanceModules = new(StringComparer.Ordinal)
    {
        "AttendanceCorrection", "AttendanceApproval"
    };

    private static readonly HashSet<string> ApprovalScheduleModules = new(StringComparer.Ordinal)
    {
        "WorkSchedule", "ScheduleApproval"
    };

    private static readonly HashSet<string> FinancialTransactionModules = new(StringComparer.Ordinal)
    {
        "Transaction", "CashTransaction", "BonusPenalty"
    };

    private static readonly HashSet<string> ShiftSetupModules = new(StringComparer.Ordinal)
    {
        "ShiftSetup", "ShiftTemplate", "Shift"
    };

    private static readonly HashSet<string> LegacyReportModules = new(StringComparer.Ordinal)
    {
        "Report"
    };

    private static readonly string[] ModernReportModules =
    [
        "HrReport", "AttendanceReport", "PayrollReport", "LeaveReport",
        "CashReport", "PenaltyReport", "AdvanceReport", "AssetReport"
    ];

    private static readonly string[] DashboardWidgetModules =
    [
        "DashboardAttendanceOverview", "DashboardHrInsights", "DashboardTodaySchedule",
        "DashboardRealtimeAttendance", "DashboardAbsent", "DashboardLateEarly",
        "DashboardKpiPanel", "DashboardInternalNews"
    ];

    public static bool TryGrant(
        string module,
        ModulePermissionAction action,
        IReadOnlyDictionary<string, ModulePermissionDto> map)
    {
        if (string.IsNullOrWhiteSpace(module) || map.Count == 0)
            return false;

        if (PayrollReadModules.Contains(module) &&
            (action is ModulePermissionAction.View or ModulePermissionAction.Export))
        {
            if (HasAction(map, "Payroll", action))
                return true;
        }

        if (AttendanceReadModules.Contains(module) &&
            action is ModulePermissionAction.View or ModulePermissionAction.Export)
        {
            foreach (var alt in AttendanceReadModules)
            {
                if (HasAction(map, alt, action))
                    return true;
            }
        }

        if (module.Equals("AttendanceReport", StringComparison.Ordinal) &&
            action is ModulePermissionAction.View or ModulePermissionAction.Export)
        {
            foreach (var alt in AttendanceReadModules.Append("AttendanceReport"))
            {
                if (HasAction(map, alt, action))
                    return true;
            }
        }

        if (ApprovalAttendanceModules.Contains(module))
        {
            if (HasAction(map, "AttendanceApproval", action) ||
                HasAction(map, "AttendanceCorrection", action))
                return true;
        }

        if (ApprovalScheduleModules.Contains(module))
        {
            if (HasAction(map, "ScheduleApproval", action) ||
                HasAction(map, "WorkSchedule", action))
                return true;
        }

        if (FinancialTransactionModules.Contains(module))
        {
            foreach (var alt in FinancialTransactionModules)
            {
                if (alt != module && HasAction(map, alt, action))
                    return true;
            }
        }

        // Thu chi: danh mục + tài khoản NH dùng chung quyền CashTransaction / BankAccount.
        if (module.Equals("BankAccount", StringComparison.Ordinal) &&
            HasAction(map, "CashTransaction", action))
            return true;

        if (module.Equals("CashTransaction", StringComparison.Ordinal) &&
            HasAction(map, "BankAccount", action))
            return true;

        if (ShiftSetupModules.Contains(module))
        {
            foreach (var alt in ShiftSetupModules)
            {
                if (alt != module && HasAction(map, alt, action))
                    return true;
            }
        }

        if (LegacyReportModules.Contains(module) && action == ModulePermissionAction.View)
        {
            foreach (var report in ModernReportModules)
            {
                if (HasAction(map, report, ModulePermissionAction.View))
                    return true;
            }
        }

        if (module.Equals("Benefit", StringComparison.Ordinal) &&
            HasAction(map, "BonusPenalty", action))
            return true;

        if (module.Equals("Salary", StringComparison.Ordinal) &&
            HasAction(map, "SalarySettings", action))
            return true;

        if (module.Equals("AssetReport", StringComparison.Ordinal) &&
            action is ModulePermissionAction.View or ModulePermissionAction.Export)
        {
            if (HasAction(map, "Asset", action))
                return true;
        }

        if (DashboardWidgetModules.Contains(module) &&
            action == ModulePermissionAction.View &&
            HasAction(map, "Dashboard", action))
            return true;

        if (module.Equals("Dashboard", StringComparison.Ordinal) &&
            action == ModulePermissionAction.View)
        {
            foreach (var w in DashboardWidgetModules)
            {
                if (HasAction(map, w, action))
                    return true;
            }
        }

        // Employee self-service: đăng ký thiết bị mobile → được chấm công (punch, lịch sử, vị trí).
        if (module.Equals("MobileAttendance", StringComparison.Ordinal))
        {
            if (HasAction(map, "MobileDeviceRegistration", ModulePermissionAction.View))
            {
                if (action is ModulePermissionAction.View or ModulePermissionAction.Create)
                    return true;
            }

            if (action is ModulePermissionAction.View or ModulePermissionAction.Approve &&
                HasAction(map, "MobileAttendanceApproval", action))
                return true;
        }

        // Cài đặt CC mobile: quản lý thường chỉ được gán «Chấm công mobile», không tách module đăng ký thiết bị.
        if (module.Equals("MobileDeviceRegistration", StringComparison.Ordinal))
        {
            if (action == ModulePermissionAction.View &&
                HasAction(map, "MobileAttendance", ModulePermissionAction.View))
                return true;

            if (action is ModulePermissionAction.Create or ModulePermissionAction.Edit
                    or ModulePermissionAction.Delete or ModulePermissionAction.Approve &&
                HasAction(map, "MobileAttendance", ModulePermissionAction.Edit))
                return true;
        }

        return false;
    }

    private static bool HasAction(
        IReadOnlyDictionary<string, ModulePermissionDto> map,
        string module,
        ModulePermissionAction action)
    {
        if (!map.TryGetValue(module, out var perm))
            return false;

        return action switch
        {
            ModulePermissionAction.View => perm.CanView,
            ModulePermissionAction.Create => perm.CanCreate,
            ModulePermissionAction.Edit => perm.CanEdit,
            ModulePermissionAction.Delete => perm.CanDelete,
            ModulePermissionAction.Export => perm.CanExport,
            ModulePermissionAction.Approve => perm.CanApprove,
            _ => false
        };
    }
}
