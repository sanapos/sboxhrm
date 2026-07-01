/// Vai trò cửa hàng — dùng chung cho kiểm tra quản lý / admin.
class StoreRoleHelper {
  StoreRoleHelper._();

  static String _norm(String? role) => (role ?? '').trim().toLowerCase();

  /// Chỉ SuperAdmin / Agent bỏ qua giới hạn gói dịch vụ trên UI.
  static bool bypassesPackageFilter(String? role) {
    switch (_norm(role)) {
      case 'superadmin':
      case 'agent':
        return true;
      default:
        return false;
    }
  }

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
}
