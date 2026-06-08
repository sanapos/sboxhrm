import 'package:flutter/material.dart';
import '../providers/permission_provider.dart';
import 'permission_modules.dart';

/// Điều hướng an toàn theo quyền — dùng chung nav, thông báo, dashboard CTA.
class PermissionNavigation {
  PermissionNavigation._();

  static bool canNavigate(PermissionProvider perm, String? moduleCode) {
    if (moduleCode == null || moduleCode.isEmpty) return true;
    if (PermissionModules.selfServiceModules.contains(moduleCode)) {
      return true;
    }
    return perm.canViewNav(moduleCode);
  }

  /// Gói dịch vụ có thể thiếu module mới (Phiếu thưởng, Ứng lương…).
  /// Nếu role đã cấp quyền trực tiếp thì vẫn hiện menu.
  static bool isAllowedByPackageOrRole(
    String? moduleCode, {
    required List<String>? allowedModules,
    required PermissionProvider perm,
    required bool bypassPackageFilter,
  }) {
    if (bypassPackageFilter) return true;
    if (allowedModules == null || allowedModules.isEmpty) return true;
    if (moduleCode == null || moduleCode.isEmpty) return true;
    if (allowedModules.contains(moduleCode)) return true;
    return perm.isLoaded && perm.canView(moduleCode);
  }

  static String label(String moduleCode) {
    switch (moduleCode) {
      case 'Home':
        return 'Trang chủ';
      case 'Dashboard':
        return 'Tổng quan';
      case 'MobileAttendance':
        return 'Chấm công Mobile';
      case 'Task':
        return 'Công việc';
      case 'Payroll':
        return 'Tổng hợp lương';
      case 'Payslip':
        return 'Phiếu lương';
      case 'ShiftSwap':
        return 'Đổi ca';
      case 'ScheduleApproval':
        return 'Duyệt lịch làm việc';
      case 'AttendanceApproval':
        return 'Duyệt chấm công';
      case 'MobileAttendanceApproval':
        return 'Duyệt chấm công Mobile';
      case 'BonusPenalty':
        return 'Phiếu thưởng';
      case 'AdvanceRequests':
        return 'Ứng lương';
      case 'CashTransaction':
        return 'Thu chi';
      case 'Production':
        return 'Sản lượng';
      case 'HrReport':
        return 'Báo cáo nhân sự';
      case 'PayrollReport':
        return 'Báo cáo lương';
      case 'PenaltyReport':
        return 'Báo cáo phạt';
      case 'CashReport':
        return 'Báo cáo thu chi';
      case 'AdvanceReport':
        return 'Báo cáo ứng lương';
      case 'LeaveReport':
        return 'Báo cáo nghỉ phép';
      case 'AssetReport':
        return 'Báo cáo tài sản';
      case 'Settings':
        return 'Cài đặt';
      case 'SettingsHub':
        return 'Thiết lập HRM';
      default:
        return moduleCode;
    }
  }

  static void showDenied(BuildContext context, String moduleCode) {
    final name = label(moduleCode);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Bạn không có quyền truy cập $name')),
    );
  }
}
