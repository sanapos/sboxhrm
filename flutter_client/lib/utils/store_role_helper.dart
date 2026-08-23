/// Vai trò cửa hàng — dùng chung cho kiểm tra quản lý / admin.
class StoreRoleHelper {
  StoreRoleHelper._();

  static String _norm(String? role) => (role ?? '').trim().toLowerCase();

  /// SuperAdmin / Agent — cổng quản trị hệ thống (không dùng MainLayout cửa hàng).
  static bool isSystemPortalRole(String? role) {
    switch (_norm(role)) {
      case 'superadmin':
      case 'agent':
        return true;
      default:
        return false;
    }
  }

  /// Chỉ SuperAdmin / Agent bỏ qua giới hạn gói dịch vụ trên UI.
  static bool bypassesPackageFilter(String? role) => isSystemPortalRole(role);

  /// Admin cửa hàng / giám đốc — toàn quyền module (khớp backend IsSuperRole mở rộng).
  static bool isFullAccess(String? role) {
    switch (_norm(role)) {
      case 'admin':
      case 'superadmin':
      case 'agent':
      case 'director':
        return true;
      default:
        return false;
    }
  }

  /// Quản lý trở lên — tab duyệt, xóa bản ghi người khác khi có quyền module.
  static bool isManagerOrAbove(String? role) {
    if (isFullAccess(role)) return true;
    switch (_norm(role)) {
      case 'manager':
      case 'departmenthead':
      case 'storeowner':
        return true;
      default:
        return false;
    }
  }

  /// Tài khoản thu ngân / phục vụ — ưu tiên vào màn Bán hàng sau đăng nhập.
  static bool isPosCashierRole(String? role) {
    final r = _norm(role);
    if (r.isEmpty) return false;
    if (r == 'pos' || r == 'cashier' || r == 'waiter') return true;
    if (r.contains('cashier') || r.contains('waiter')) return true;
    if (r.contains('thu ngân') || r.contains('thu ngan')) return true;
    if (r.contains('phục vụ') || r.contains('phuc vu')) return true;
    if (r.contains('bán hàng') || r.contains('ban hang')) return true;
    return false;
  }

  /// Gói/module nghiêng POS (không có HRM lõi) — dùng khi role không rõ.
  static bool isPosHeavyModules(Iterable<String>? modules) {
    final mods = modules?.map((m) => m.trim()).where((m) => m.isNotEmpty).toList() ?? const [];
    if (mods.isEmpty) return false;
    final hasPos = mods.any((m) =>
        m == 'PosSell' ||
        m.startsWith('Pos') ||
        m == 'HkdBooks');
    if (!hasPos) return false;
    const hrmCore = {
      'Employees',
      'Employee',
      'Attendance',
      'Payroll',
      'Leaves',
      'Leave',
      'Task',
      'Payslip',
      'Overtime',
      'ShiftSwap',
    };
    return !mods.any(hrmCore.contains);
  }
}
