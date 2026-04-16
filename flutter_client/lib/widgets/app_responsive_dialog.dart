import 'package:flutter/material.dart';
import 'app_button.dart';

/// Helper mở dialog responsive: full-screen trên mobile, dialog trên desktop.
///
/// Usage:
/// ```dart
/// AppResponsiveDialog.show(
///   context: context,
///   title: 'Thêm nhân viên',
///   icon: Icons.person_add,
///   child: MyFormWidget(),
///   actions: AppDialogActions(
///     onConfirm: _save,
///     confirmLabel: 'Lưu',
///   ),
/// );
/// ```
class AppResponsiveDialog {
  AppResponsiveDialog._();

  /// Ngưỡng mobile breakpoint
  static const double mobileBreakpoint = 768;

  /// Mở dialog responsive tự động
  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required Widget child,
    IconData? icon,
    Widget? actions,
    double maxWidth = 560,
    bool scrollable = true,
    bool barrierDismissible = true,
    Color? iconColor,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < mobileBreakpoint;

    if (isMobile) {
      return _showMobileFullScreen<T>(
        context: context,
        title: title,
        icon: icon,
        iconColor: iconColor,
        child: child,
        actions: actions,
        scrollable: scrollable,
      );
    } else {
      return _showDesktopDialog<T>(
        context: context,
        title: title,
        icon: icon,
        iconColor: iconColor,
        child: child,
        actions: actions,
        maxWidth: maxWidth,
        scrollable: scrollable,
        barrierDismissible: barrierDismissible,
      );
    }
  }

  /// Mobile: Full-screen dialog với Scaffold
  static Future<T?> _showMobileFullScreen<T>({
    required BuildContext context,
    required String title,
    required Widget child,
    IconData? icon,
    Color? iconColor,
    Widget? actions,
    bool scrollable = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        insetPadding: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(),
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
                tooltip: 'Đóng',
              ),
              title: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20, color: iconColor ?? Theme.of(ctx).primaryColor),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              elevation: 0.5,
            ),
            body: scrollable
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: child,
                  )
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: child,
                  ),
            bottomNavigationBar: actions != null
                ? Container(
                    padding: EdgeInsets.fromLTRB(
                      16, 12, 16,
                      12 + MediaQuery.of(ctx).padding.bottom,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.surface,
                      border: Border(
                        top: BorderSide(
                          color: Theme.of(ctx).dividerColor,
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: actions,
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  /// Desktop: AlertDialog chuẩn
  static Future<T?> _showDesktopDialog<T>({
    required BuildContext context,
    required String title,
    required Widget child,
    IconData? icon,
    Color? iconColor,
    Widget? actions,
    double maxWidth = 560,
    bool scrollable = true,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 22, color: iconColor ?? Theme.of(ctx).primaryColor),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(title, overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.pop(ctx),
              tooltip: 'Đóng',
              splashRadius: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
        content: SizedBox(
          width: maxWidth.clamp(
            0,
            MediaQuery.of(ctx).size.width - 64,
          ),
          child: scrollable
              ? SingleChildScrollView(child: child)
              : child,
        ),
        actions: actions != null ? [actions] : null,
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  /// Mở dialog xác nhận xóa
  static Future<bool?> confirmDelete({
    required BuildContext context,
    required String itemName,
    String? message,
    VoidCallback? onConfirm,
  }) {
    return show<bool>(
      context: context,
      title: 'Xác nhận xóa',
      icon: Icons.warning_amber_rounded,
      iconColor: const Color(0xFFEF4444),
      maxWidth: 420,
      scrollable: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message ?? 'Bạn có chắc chắn muốn xóa "$itemName"?',
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: Color(0xFFEF4444)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hành động này không thể hoàn tác.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: AppDialogActions.delete(
        onCancel: () => Navigator.pop(context, false),
        onConfirm: () {
          Navigator.pop(context, true);
          onConfirm?.call();
        },
      ),
    );
  }
}
