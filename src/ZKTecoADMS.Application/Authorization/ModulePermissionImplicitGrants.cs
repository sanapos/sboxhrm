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
        "Attendance", "AttendanceSummary", "AttendanceByShift", "LateEarlyReport", "TravelHoursReport"
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
        "AttendanceReport", "LateEarlyReport", "LeaveReport",
        "CashReport", "PenaltyReport", "AdvanceReport", "BusinessTripReport", "AssetReport"
    ];

    private static readonly string[] DashboardWidgetModules =
    [
        "DashboardAttendanceOverview", "DashboardHrInsights", "DashboardTodaySchedule",
        "DashboardRealtimeAttendance", "DashboardAbsent", "DashboardLateEarly",
        "DashboardKpiPanel", "DashboardInternalNews"
    ];

    /// <summary>Submodule POS — quyền gộp từ PosProducts (cùng action).</summary>
    private static readonly string[] PosSubmoduleCodes =
    [
        "PosSell", "PosSaleOrders", "PosSaleReturns", "PosPurchaseReceipts", "PosPurchaseReturns",
        "PosStockCounts", "PosDamageIssues", "PosInternalUseIssues", "PosPrintTemplates",
        "PosBooking", "PosCustomers", "PosWarranty", "PosCustomerDisplay", "PosEInvoice",
        "PosKds", "PosQrOrder", "PosCashierShift", "PosShipping",
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

        // Thông báo cá nhân: xem được thì được xóa thông báo của chính mình (API kiểm tra TargetUserId).
        if (module.Equals("Notification", StringComparison.Ordinal) &&
            action == ModulePermissionAction.Delete &&
            HasAction(map, "Notification", ModulePermissionAction.View))
            return true;

        // POS: thu ngân / order (PosSell) được xem hàng hóa phục vụ bán — không mirror Create/Edit.
        if (module.Equals("PosProducts", StringComparison.Ordinal) &&
            action is ModulePermissionAction.View or ModulePermissionAction.Export)
        {
            if (HasAction(map, "PosSell", ModulePermissionAction.View))
                return true;
            foreach (var sub in PosSubmoduleCodes)
            {
                if (HasAction(map, sub, ModulePermissionAction.View))
                    return true;
            }
        }

        // POS: thu ngân được xem mẫu in hóa đơn khi bán.
        if (module.Equals("PosPrintTemplates", StringComparison.Ordinal) &&
            action == ModulePermissionAction.View &&
            (HasAction(map, "PosSell", ModulePermissionAction.View) ||
             HasAction(map, "PosProducts", ModulePermissionAction.View)))
            return true;

        // POS: trả hàng — có PosSell cùng action (thu ngân) vẫn trả được; hoặc gán riêng PosSaleReturns.
        if (module.Equals("PosSaleReturns", StringComparison.Ordinal) &&
            HasAction(map, "PosSell", action))
            return true;

        // Addon vận hành khi bán: chỉ kế thừa Xem từ PosSell — không kế thừa Sửa
        // (thiết lập máy in / KDS / QR / ca do tick riêng, tránh thu ngân sửa hệ thống).
        if ((module is "PosCustomers" or "PosBooking" or "PosWarranty" or "PosCustomerDisplay"
                or "PosEInvoice" or "PosKds" or "PosQrOrder" or "PosCashierShift" or "PosShipping") &&
            action == ModulePermissionAction.View &&
            HasAction(map, "PosSell", ModulePermissionAction.View))
            return true;

        // Máy in cloud: xem thiết lập khi đã có SettingsHub / máy in thiết bị (gói vẫn tick riêng).
        if (module.Equals("PosStorePrinters", StringComparison.Ordinal) &&
            action == ModulePermissionAction.View &&
            (HasAction(map, "SettingsHub", ModulePermissionAction.View) ||
             HasAction(map, "PosPrinters", ModulePermissionAction.View)))
            return true;

        // API /api/pos/printers vẫn Require PosPrinters; Super Admin tick PosStorePrinters.
        // Không alias thì tick Hóa đơn / Cuối ngày → 403 «Không lưu được vai trò».
        if (module.Equals("PosPrinters", StringComparison.Ordinal) &&
            HasAction(map, "PosStorePrinters", action))
            return true;
        if (module.Equals("PosStorePrinters", StringComparison.Ordinal) &&
            HasAction(map, "PosPrinters", action))
            return true;

        // ĐVVC: thu ngân tạo/so sánh vận đơn từ PosSell; sửa cấu hình cần Edit riêng.
        if (module.Equals("PosShipping", StringComparison.Ordinal) &&
            action == ModulePermissionAction.Create &&
            HasAction(map, "PosSell", ModulePermissionAction.Create))
            return true;
        if (module.Equals("PosShipping", StringComparison.Ordinal) &&
            action == ModulePermissionAction.Edit &&
            (HasAction(map, "PosSell", ModulePermissionAction.Edit) ||
             HasAction(map, "SettingsHub", ModulePermissionAction.Edit)))
            return true;

        // POS: có quyền trên PosProducts (kho/SP) → submodule cùng action (QL hàng được bán/nhập…).
        // Không ngược lại: PosSell Create không còn cấp PosProducts Create.
        if (PosSubmoduleCodes.Contains(module) && HasAction(map, "PosProducts", action))
            return true;

        // Báo cáo POS: hub cũ, hoặc từng báo cáo tách, hoặc PosProducts (kho).
        if (module.Equals("PosSalesReport", StringComparison.Ordinal) &&
            action is ModulePermissionAction.View or ModulePermissionAction.Export)
        {
            if (HasAction(map, "PosSalesReport", action) || HasAction(map, "PosProducts", action))
                return true;
            if (HasAction(map, "PosReportRevenue", action)
                || HasAction(map, "PosReportPayment", action)
                || HasAction(map, "PosReportStaffRevenue", action)
                || HasAction(map, "PosReportProfit", action))
                return true;
        }

        if (PosPackageDefaults.IsReportModule(module) &&
            action is ModulePermissionAction.View or ModulePermissionAction.Export)
        {
            if (HasAction(map, module, action) || HasAction(map, "PosSalesReport", action))
                return true;
            if (module is "PosReportStock" or "PosReportExpiry" or "PosReportEndOfDay" or "PosReportSoldGoods"
                && HasAction(map, "PosProducts", action))
                return true;
        }

        // Sổ sách HKD: quyền riêng, hoặc kế thừa từ báo cáo POS / thu chi.
        if (module.Equals("HkdBooks", StringComparison.Ordinal) &&
            action is ModulePermissionAction.View or ModulePermissionAction.Export or ModulePermissionAction.Edit)
        {
            if (HasAction(map, "HkdBooks", action)
                || (action != ModulePermissionAction.Edit && HasAction(map, "PosSalesReport", action))
                || (action != ModulePermissionAction.Edit && HasAction(map, "CashReport", action)))
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
