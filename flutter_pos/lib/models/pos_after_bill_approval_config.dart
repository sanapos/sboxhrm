import 'dart:convert';

import 'pos_sell_industry.dart';

/// «Sau tạm tính cần quản lý duyệt» — lưu trong ExtraJson thiết lập bán hàng: `afterBillApproval.enabled`.
/// Chỉ có tác dụng khi cửa hàng đang «Cho phép tạm tính» (máy chủ cũng kiểm như vậy).
class PosAfterBillApprovalConfig {
  PosAfterBillApprovalConfig._();

  static const _key = 'afterBillApproval';

  /// Chủ / quản lý làm trực tiếp, không cần duyệt (khớp danh sách vai trò phía máy chủ).
  static const managerRoles = {'storeowner', 'admin', 'director', 'superadmin', 'manager', 'departmenthead', 'agent'};

  static bool isManagerRole(String? role) => managerRoles.contains((role ?? '').trim().toLowerCase());

  static bool enabledIn(String? extraJson) {
    final m = _decode(extraJson);
    final o = m[_key];
    return o is Map && o['enabled'] == true;
  }

  static bool isActive(PosStoreSellSettingsDto s) => s.allowProvisionalBill && enabledIn(s.extraJson);

  static String merge(String? extraJson, bool enabled) {
    final m = _decode(extraJson);
    m[_key] = {'enabled': enabled};
    return jsonEncode(m);
  }

  static Map<String, dynamic> _decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final v = jsonDecode(raw);
      return v is Map ? Map<String, dynamic>.from(v) : {};
    } catch (_) {
      return {};
    }
  }
}
