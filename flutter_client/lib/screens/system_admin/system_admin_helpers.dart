import 'package:flutter/material.dart';
import '../../widgets/notification_overlay.dart';

/// Shared helper widgets used across all System Admin tabs
class AdminHelpers {
  static const Color primary = Color(0xFF1E3A5F);
  static const Color primaryDark = Color(0xFF0F2340);
  static const Color success = Color(0xFF059669);
  static const Color danger = Color(0xFFDC2626);
  static const Color warning = Color(0xFFEA580C);
  static const Color info = Color(0xFF0891B2);
  static const Color bgLight = Color(0xFFF0F4F8);
  static const Color cardBg = Colors.white;
  static const Color surfaceBg = Color(0xFFF8FAFC);

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
      {bool obscureText = false}) {
    return TextField(
      controller: ctrl,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  static String formatDate(dynamic date) {
    if (date == null) return '';
    try {
      final d = DateTime.parse(date.toString());
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return date.toString();
    }
  }

  static String formatDateTime(dynamic date) {
    if (date == null) return '';
    try {
      final d = DateTime.parse(date.toString()).toLocal();
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return date.toString();
    }
  }

  static Future<String?> showInputDialog(
      BuildContext context, String title, String label) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
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
          ElevatedButton(
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
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          ElevatedButton(
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

  /// Map license type enum name to Vietnamese display label
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
