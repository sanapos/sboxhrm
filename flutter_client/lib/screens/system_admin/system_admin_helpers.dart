import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/hrm_page_chrome.dart';

/// Quyền thao tác trên màn Quản trị hệ thống (module `SystemAdmin`).
extension SystemAdminPermissionContext on BuildContext {
  bool get isAgentPortalMode =>
      Provider.of<AuthProvider>(this, listen: false).userRole == 'Agent';

  bool get systemAdminCanCreate =>
      !isAgentPortalMode &&
      Provider.of<PermissionProvider>(this, listen: false)
          .canCreate('SystemAdmin');

  bool get systemAdminCanEdit =>
      isAgentPortalMode ||
      Provider.of<PermissionProvider>(this, listen: false)
          .canEdit('SystemAdmin');

  /// Tạo / thu hồi / cấp key — chỉ SuperAdmin, không áp dụng đại lý.
  bool get systemAdminCanManageLicenses =>
      !isAgentPortalMode &&
      Provider.of<PermissionProvider>(this, listen: false)
          .canEdit('SystemAdmin');

  bool get systemAdminCanDelete =>
      !isAgentPortalMode &&
      Provider.of<PermissionProvider>(this, listen: false)
          .canDelete('SystemAdmin');

  /// SuperAdmin sanapos.vn@gmail.com — gia hạn không giới hạn 3 lần.
  bool get canBypassStoreRenewalLimit {
    final email =
        Provider.of<AuthProvider>(this, listen: false).user?.email ?? '';
    return email.toLowerCase() == AdminHelpers.storeRenewalBypassEmail;
  }
}

/// Gợi ý số ngày gia hạn nhanh.
const List<int> kStoreExtendDayPresets = [7, 14, 21, 30];

/// Shared helper widgets used across all System Admin tabs
class AdminHelpers {
  static const String storeRenewalBypassEmail = 'sanapos.vn@gmail.com';
  static const int maxStoreRenewals = 3;

  static String storeRenewalLabel(BuildContext context, int renewalCount) {
    if (context.canBypassStoreRenewalLimit && renewalCount >= maxStoreRenewals) {
      return 'Gia hạn: $renewalCount lần (Super Admin)';
    }
    return 'Gia hạn: $renewalCount/$maxStoreRenewals lần';
  }

  static const Color primary = HrmPageChrome.primaryNavy;
  static const Color primaryDark = HrmPageChrome.primaryNavy;
  static const Color success = Color(0xFF059669);
  static const Color danger = Color(0xFFDC2626);
  static const Color warning = Color(0xFFEA580C);
  static const Color info = Color(0xFF0891B2);
  static const Color bgLight = Color(0xFFF0F4F8);
  static const Color cardBg = Colors.white;
  static const Color surfaceBg = Color(0xFFF8FAFC);

  // ===== Enum parsers (backend uses JsonStringEnumConverter ⇒ may return enum name or int) =====

  static const Map<String, int> announcementKindMap = {
    'News': 0,
    'Maintenance': 1,
    'Upgrade': 2,
    'Renewal': 3,
    'Marketing': 4,
  };
  static const Map<String, int> announcementSeverityMap = {
    'Info': 0,
    'Success': 1,
    'Warning': 2,
    'Critical': 3,
  };
  static const Map<String, int> announcementStatusMap = {
    'Draft': 0,
    'Scheduled': 1,
    'Sending': 2,
    'Sent': 3,
    'Cancelled': 4,
    'Failed': 5,
  };
  static const Map<String, int> campaignStatusMap = {
    'Draft': 0,
    'Scheduled': 1,
    'Running': 2,
    'Completed': 3,
    'Cancelled': 4,
    'Failed': 5,
  };
  static const Map<String, int> notificationChannelMap = {
    'None': 0,
    'InApp': 1,
    'Banner': 2,
    'Email': 4,
    'Sms': 8,
    'Push': 16,
  };

  /// Parse a value that may be int (numeric enum) or String (enum name or flags CSV).
  static int parseEnumInt(dynamic v, [Map<String, int>? names]) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      if (v.isEmpty) return 0;
      final asInt = int.tryParse(v);
      if (asInt != null) return asInt;
      // [Flags] enum serialized as "InApp, Banner"
      if (names != null) {
        int acc = 0;
        for (final part in v.split(',')) {
          final key = part.trim();
          if (key.isEmpty) continue;
          acc |= names[key] ?? 0;
        }
        return acc;
      }
    }
    return 0;
  }

  static Widget emptyState(IconData icon, String msg) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 80, color: Colors.grey[300]),
        const SizedBox(height: 16),
        Text(msg, style: TextStyle(color: Colors.grey[500], fontSize: 16)),
      ]),
    );
  }

  static Widget statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  static Widget infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Icon(icon, size: 14, color: Colors.grey[500]),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12, color: Colors.grey[700]))),
      ]),
    );
  }

  static Widget dialogField(TextEditingController ctrl, String label,
      IconData icon,
      {bool obscureText = false, bool readOnly = false}) {
    if (obscureText) {
      // Trường mật khẩu: có nút con mắt để xem/ẩn nội dung đang nhập.
      return _PasswordDialogField(controller: ctrl, label: label, icon: icon);
    }
    return TextField(
      controller: ctrl,
      readOnly: readOnly,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  /// Dialog nhập mật khẩu có nút con mắt xem nội dung. Trả về mật khẩu hoặc null.
  static Future<String?> showPasswordInputDialog(
      BuildContext context, String title, String label) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: _PasswordDialogField(controller: ctrl, label: label,
              icon: Icons.lock),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('OK')),
        ],
      ),
    );
  }

  /// Parse chuỗi thời gian từ API. Các field CreatedAt/UpdatedAt/ExpiryDate...
  /// lưu bằng DateTime.UtcNow nhưng Npgsql trả về không kèm hậu tố 'Z',
  /// nên phải coi là UTC trước khi đổi sang giờ máy (tránh lệch múi giờ).
  static DateTime? parseServerDate(dynamic date) {
    if (date == null) return null;
    final raw = date.toString();
    if (raw.isEmpty) return null;
    var parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    final hasTimezone = raw.endsWith('Z') ||
        RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(raw);
    if (!hasTimezone && !parsed.isUtc) {
      parsed = DateTime.utc(
        parsed.year,
        parsed.month,
        parsed.day,
        parsed.hour,
        parsed.minute,
        parsed.second,
        parsed.millisecond,
      );
    }
    return parsed.toLocal();
  }

  static int _calendarDaysUntil(DateTime target) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    final targetDate = DateTime(target.year, target.month, target.day);
    return targetDate.difference(todayDate).inDays;
  }

  /// Số ngày còn lại của cửa hàng — khớp backend (ExpiryDate hoặc trial).
  static int? getStoreRemainingDays(Map<String, dynamic> store) {
    final expiry = parseServerDate(store['expiryDate']);
    if (expiry != null) {
      return _calendarDaysUntil(expiry);
    }

    final trialDays = parseInt(store['trialDays'], 0);
    if (trialDays > 0) {
      final start = parseServerDate(store['trialStartDate'] ?? store['createdAt']);
      if (start != null) {
        final endDate = DateTime(start.year, start.month, start.day)
            .add(Duration(days: trialDays));
        return _calendarDaysUntil(endDate);
      }
    }
    return null;
  }

  static DateTime? _parseServerDate(dynamic date) => parseServerDate(date);

  static String formatDate(dynamic date) {
    final d = _parseServerDate(date);
    if (d == null) return date?.toString() ?? '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  /// Safely convert dynamic value (int / num / numeric string) to int with default.
  static int parseInt(dynamic v, [int defaultValue = 0]) {
    if (v == null) return defaultValue;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? defaultValue;
    return defaultValue;
  }

  /// Tổng cửa hàng thuộc đại lý (AgentDto: currentStoresCount).
  static int agentTotalStores(Map<String, dynamic> agent) => parseInt(
        agent['currentStoresCount'] ??
            agent['storeCount'] ??
            agent['totalStores'],
      );

  static int agentActiveStores(Map<String, dynamic> agent) =>
      parseInt(agent['activeStoresCount']);

  static int agentLockedStores(Map<String, dynamic> agent) =>
      parseInt(agent['lockedStoresCount']);

  static int agentMaxStores(Map<String, dynamic> agent) =>
      parseInt(agent['maxStores']);

  static int agentActivatedStores(Map<String, dynamic> agent) => parseInt(
        agent['activatedStoresCount'],
      );

  static int agentTrialStores(Map<String, dynamic> agent) => parseInt(
        agent['trialStoresCount'],
      );

  static int agentTotalKeys(Map<String, dynamic> agent) => parseInt(
        agent['totalLicenseKeys'] ?? agent['totalKeys'],
      );

  static int agentUsedKeys(Map<String, dynamic> agent) => parseInt(
        agent['usedLicenseKeys'] ?? agent['usedKeys'],
      );

  static int agentAvailableKeys(Map<String, dynamic> agent) => parseInt(
        agent['availableLicenseKeys'] ?? agent['availableKeys'],
      );

  static int agentRenewalBalance(Map<String, dynamic> agent) =>
      parseInt(agent['renewalDayBalance']);

  static String formatDateTime(dynamic date) {
    final d = _parseServerDate(date);
    if (d == null) return date?.toString() ?? '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static Future<String?> showInputDialog(
      BuildContext context, String title, String label) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: TextField(
            controller: ctrl,
            decoration: InputDecoration(
                labelText: label,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10))),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Hủy')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('OK')),
        ],
      ),
    );
  }

  static Future<bool?> showConfirmDialog(
      BuildContext context, String title, String content) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
  }

  static void showApiError(BuildContext context, Map<String, dynamic> res) {
    final msg = res['message']?.toString() ?? 'Lỗi không xác định';
    NotificationOverlayManager().showError(title: 'Lỗi API', message: msg);
  }

  static void showSuccess(BuildContext context, String msg) {
    NotificationOverlayManager().showSuccess(title: 'Thành công', message: msg);
  }

  static void showError(BuildContext context, String msg) {
    NotificationOverlayManager().showError(title: 'Lỗi', message: msg);
  }

  /// Nhãn tiếng Việt cho loại license (Basic/Advanced/Professional) — khác gói dịch vụ.
  static String licenseTypeLabel(String? type) {
    switch (type) {
      case 'Basic':
        return 'Cơ bản';
      case 'Advanced':
        return 'Nâng cao';
      case 'Professional':
        return 'Chuyên nghiệp';
      default:
        return type ?? '';
    }
  }

  /// Chip hiển thị loại license trên danh sách cửa hàng.
  static String licenseTypeChipLabel(String? type) {
    final label = licenseTypeLabel(type);
    if (label.isEmpty) return '';
    return 'License $label';
  }

  /// Tên hiển thị vai trò tiếng Việt.
  static String roleDisplayNameVn(String roleName) {
    switch (roleName.toLowerCase()) {
      case 'superadmin':
        return 'SuperAdmin';
      case 'admin':
        return 'Quản trị viên';
      case 'director':
        return 'Giám đốc';
      case 'accountant':
        return 'Kế toán';
      case 'departmenthead':
        return 'Trưởng phòng';
      case 'manager':
        return 'Quản lý';
      case 'employee':
        return 'Nhân viên';
      case 'cashier':
        return 'Thu ngân';
      case 'user':
        return 'Người dùng';
      case 'agent':
        return 'Đại lý';
      default:
        return roleName;
    }
  }

  /// Mô tả ngắn vai trò (tiếng Việt).
  static String roleDescriptionVn(String roleName) {
    switch (roleName) {
      case 'SuperAdmin':
        return 'Quản trị toàn hệ thống';
      case 'Admin':
        return 'Quản trị cửa hàng';
      case 'Director':
        return 'Giám đốc điều hành';
      case 'Accountant':
        return 'Kế toán, tài chính';
      case 'DepartmentHead':
        return 'Trưởng phòng ban';
      case 'Manager':
        return 'Quản lý nhân viên, chấm công';
      case 'Employee':
        return 'Nhân viên — xem thông tin cá nhân';
      case 'Cashier':
        return 'Thu ngân POS';
      case 'User':
        return 'Người dùng cơ bản';
      case 'Agent':
        return 'Đại lý quản lý nhiều cửa hàng';
      default:
        return '';
    }
  }

  /// Safely extracts list data from API response that may be List or Map with 'items'
  static List<Map<String, dynamic>> extractList(dynamic rawData) {
    if (rawData is List) {
      return List<Map<String, dynamic>>.from(rawData);
    }
    if (rawData is Map) {
      return List<Map<String, dynamic>>.from(rawData['items'] ?? []);
    }
    return [];
  }

  /// Search bar widget with consistent styling
  static Widget searchBar({
    required TextEditingController controller,
    required String hint,
    required VoidCallback onChanged,
    VoidCallback? onClear,
  }) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: TextField(
        controller: controller,
        onChanged: (_) => onChanged(),
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
          prefixIcon:
              Icon(Icons.search, size: 18, color: Colors.grey[400]),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, size: 16, color: Colors.grey[400]),
                  onPressed: () {
                    controller.clear();
                    onClear?.call();
                    onChanged();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }

  /// Card wrapper with consistent styling
  static BoxDecoration cardDecoration({Color? borderColor}) {
    return BoxDecoration(
      color: cardBg,
      borderRadius: BorderRadius.circular(14),
      border: borderColor != null
          ? Border(left: BorderSide(color: borderColor, width: 4))
          : null,
      boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)
      ],
    );
  }

  /// Stat counter badge
  static Widget countBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text('$count',
            style: TextStyle(
                color: color, fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 12)),
      ]),
    );
  }
}

/// Ô nhập mật khẩu có nút con mắt bật/tắt hiển thị.
class _PasswordDialogField extends StatefulWidget {
  const _PasswordDialogField({
    required this.controller,
    required this.label,
    required this.icon,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;

  @override
  State<_PasswordDialogField> createState() => _PasswordDialogFieldState();
}

class _PasswordDialogFieldState extends State<_PasswordDialogField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscure,
      decoration: InputDecoration(
        labelText: widget.label,
        prefixIcon: Icon(widget.icon, size: 20),
        suffixIcon: IconButton(
          icon: Icon(
            _obscure ? Icons.visibility_off : Icons.visibility,
            size: 20,
          ),
          tooltip: _obscure ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}
