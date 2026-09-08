/// Vai trò lấy từ màn Phân quyền (`GET /api/permission-management/all`).
class PermissionRoleOption {
  final String name;
  final String displayName;

  const PermissionRoleOption({
    required this.name,
    required this.displayName,
  });
}

class PermissionRoleOptions {
  static const fallback = [
    PermissionRoleOption(name: 'Admin', displayName: 'Quản trị viên'),
    PermissionRoleOption(name: 'Director', displayName: 'Giám đốc'),
    PermissionRoleOption(name: 'Accountant', displayName: 'Kế toán'),
    PermissionRoleOption(
        name: 'DepartmentHead', displayName: 'Trưởng phòng'),
    PermissionRoleOption(name: 'Manager', displayName: 'Quản lý'),
    PermissionRoleOption(name: 'Cashier', displayName: 'Thu ngân'),
    PermissionRoleOption(name: 'Waiter', displayName: 'Order'),
    PermissionRoleOption(name: 'Employee', displayName: 'Nhân viên'),
    PermissionRoleOption(name: 'User', displayName: 'Người dùng'),
  ];

  static String displayNameOf(String name) {
    final n = name.trim();
    for (final r in fallback) {
      if (r.name.toLowerCase() == n.toLowerCase()) return r.displayName;
    }
    return n;
  }

  static List<PermissionRoleOption> parse(List<dynamic> raw) {
    final out = <PermissionRoleOption>[];
    final seen = <String>{};
    for (final e in raw) {
      var name = '';
      var display = '';
      if (e is String) {
        name = e.trim();
      } else if (e is Map) {
        name = '${e['roleName'] ?? e['RoleName'] ?? e['name'] ?? e['Name'] ?? ''}'
            .trim();
        display =
            '${e['roleDisplayName'] ?? e['RoleDisplayName'] ?? ''}'.trim();
      }
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      if (seen.contains(key)) continue;
      seen.add(key);
      if (display.isEmpty || display.toLowerCase() == key) {
        display = displayNameOf(name);
      }
      out.add(PermissionRoleOption(name: name, displayName: display));
    }
    return out;
  }
}
