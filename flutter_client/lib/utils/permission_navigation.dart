import 'package:flutter/material.dart';
import '../providers/permission_provider.dart';
import 'permission_modules.dart';
import 'store_role_helper.dart';

/// Điều hướng an toàn theo quyền — dùng chung nav, thông báo, dashboard CTA.
class PermissionNavigation {
  PermissionNavigation._();

  static const Map<String, List<String>> _viewAliases = {
    'PosSaleReturns': ['PosSell', 'PosProducts'],
  };

  static bool canNavigate(PermissionProvider perm, String? moduleCode) {
    if (moduleCode == null || moduleCode.isEmpty) return true;
    if (PermissionModules.selfServiceModules.contains(moduleCode)) {
      return true;
    }
    if (perm.canViewNav(moduleCode)) return true;
    for (final alt in _viewAliases[moduleCode] ?? const []) {
      if (perm.canViewNav(alt)) return true;
    }
    return false;
  }

  /// Chỉ hiện menu khi module nằm trong gói dịch vụ (hoặc self-service).
  static bool isAllowedByPackageOrRole(
    String? moduleCode, {
    required List<String>? allowedModules,
    required PermissionProvider perm,
    required bool bypassPackageFilter,
  }) {
    if (bypassPackageFilter) return true;
    if (moduleCode == null || moduleCode.isEmpty) return true;
    if (PermissionModules.selfServiceModules.contains(moduleCode)) {
      return true;
    }
    if (allowedModules == null || allowedModules.isEmpty) {
      return false;
    }
    final code = moduleCode.toLowerCase();
    return allowedModules.any((m) => m.toLowerCase() == code);
  }

  /// Thông báo từ middleware gói dịch vụ — không cần hiện toast khi module đã ẩn.
  static bool isPackageRestrictionMessage(String? message) {
    if (message == null || message.isEmpty) return false;
    final m = message.toLowerCase();
    return m.contains('gói dịch vụ') && m.contains('không bao gồm');
  }

  /// Gói dịch vụ + quyền role — dùng trước khi gọi API / mount màn hình.
  static bool canAccessModule(
    String? moduleCode, {
    required List<String>? allowedModules,
    required PermissionProvider perm,
    String? role,
  }) {
    if (moduleCode == null || moduleCode.isEmpty) return true;
    final bypass = StoreRoleHelper.bypassesPackageFilter(role);
    if (!isAllowedByPackageOrRole(
      moduleCode,
      allowedModules: allowedModules,
      perm: perm,
      bypassPackageFilter: bypass,
    )) {
      return false;
    }
    return canNavigate(perm, moduleCode);
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
      case 'PosProducts':
        return 'Hàng hóa';
      case 'PosSell':
        return 'Bán hàng';
      case 'PosPrintTemplates':
        return 'Mẫu in';
      case 'PosSaleOrders':
        return 'Đơn hàng';
      case 'PosSaleReturns':
        return 'Trả hàng bán';
      case 'PosPurchaseReceipts':
        return 'Nhập hàng NCC';
      case 'PosPurchaseReturns':
        return 'Trả hàng nhập';
      case 'PosStockCounts':
        return 'Kiểm kho';
      case 'PosDamageIssues':
        return 'Xuất hủy';
      case 'PosInternalUseIssues':
        return 'Xuất dùng nội bộ';
      case 'PosSalesReport':
        return 'Báo cáo POS';
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
