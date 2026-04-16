import 'package:flutter/material.dart';

/// Semantic button variants for consistent UI
enum AppButtonVariant { primary, danger, success, warning, cancel, outlined }

/// Standardized button widget for the entire application.
///
/// Usage:
/// ```dart
/// AppButton.primary(onPressed: _save, label: 'Lưu', icon: Icons.save)
/// AppButton.danger(onPressed: _delete, label: 'Xóa', icon: Icons.delete)
/// AppButton.success(onPressed: _approve, label: 'Duyệt', icon: Icons.check)
/// AppButton.warning(onPressed: _remind, label: 'Nhắc nhở', icon: Icons.notifications)
/// AppButton.cancel(onPressed: () => Navigator.pop(context))
/// AppButton.outlined(onPressed: _export, label: 'Xuất Excel', icon: Icons.download)
/// ```
class AppButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  final AppButtonVariant variant;
  final bool isLoading;
  final bool expand;
  final EdgeInsetsGeometry? padding;

  const AppButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
    this.expand = false,
    this.padding,
  });

  /// Primary action: Save, Create, Submit (Navy)
  const AppButton.primary({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.isLoading = false,
    this.expand = false,
    this.padding,
  }) : variant = AppButtonVariant.primary;

  /// Danger action: Delete, Remove (Red)
  const AppButton.danger({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.isLoading = false,
    this.expand = false,
    this.padding,
  }) : variant = AppButtonVariant.danger;

  /// Success action: Approve, Confirm (Green)
  const AppButton.success({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.isLoading = false,
    this.expand = false,
    this.padding,
  }) : variant = AppButtonVariant.success;

  /// Warning action: Remind, Alert (Amber)
  const AppButton.warning({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.isLoading = false,
    this.expand = false,
    this.padding,
  }) : variant = AppButtonVariant.warning;

  /// Cancel/Dismiss action (Text only, subtle)
  const AppButton.cancel({
    super.key,
    required this.onPressed,
    this.label = 'Hủy',
    this.icon,
    this.isLoading = false,
    this.expand = false,
    this.padding,
  }) : variant = AppButtonVariant.cancel;

  /// Outlined/Secondary action: Export, Filter, etc.
  const AppButton.outlined({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.isLoading = false,
    this.expand = false,
    this.padding,
  }) : variant = AppButtonVariant.outlined;

  // -- Color palette --
  static const _primaryColor = Color(0xFF1E3A5F);
  static const _dangerColor = Color(0xFFEF4444);
  static const _successColor = Color(0xFF16A34A);
  static const _warningColor = Color(0xFFF59E0B);
  static const _cancelTextColor = Color(0xFF71717A);

  Color get _bgColor {
    switch (variant) {
      case AppButtonVariant.primary:
        return _primaryColor;
      case AppButtonVariant.danger:
        return _dangerColor;
      case AppButtonVariant.success:
        return _successColor;
      case AppButtonVariant.warning:
        return _warningColor;
      case AppButtonVariant.cancel:
      case AppButtonVariant.outlined:
        return Colors.transparent;
    }
  }

  Color get _fgColor {
    switch (variant) {
      case AppButtonVariant.primary:
      case AppButtonVariant.danger:
      case AppButtonVariant.success:
      case AppButtonVariant.warning:
        return Colors.white;
      case AppButtonVariant.cancel:
        return _cancelTextColor;
      case AppButtonVariant.outlined:
        return _primaryColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveOnPressed = isLoading ? null : onPressed;
    final btnPadding = padding ?? const EdgeInsets.symmetric(horizontal: 20, vertical: 12);

    final Widget child;
    if (isLoading) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _fgColor,
            ),
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      );
    } else if (icon != null) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text(label),
        ],
      );
    } else {
      child = Text(label);
    }

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
    );

    Widget button;
    switch (variant) {
      case AppButtonVariant.cancel:
        button = TextButton(
          onPressed: effectiveOnPressed,
          style: TextButton.styleFrom(
            foregroundColor: _cancelTextColor,
            padding: btnPadding,
            shape: shape,
            textStyle: const TextStyle(fontWeight: FontWeight.w500),
          ),
          child: child,
        );
        break;
      case AppButtonVariant.outlined:
        button = OutlinedButton(
          onPressed: effectiveOnPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: _fgColor,
            side: BorderSide(color: _primaryColor.withValues(alpha: 0.5)),
            padding: btnPadding,
            shape: shape,
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
          child: child,
        );
        break;
      default:
        button = FilledButton(
          onPressed: effectiveOnPressed,
          style: FilledButton.styleFrom(
            backgroundColor: _bgColor,
            foregroundColor: _fgColor,
            padding: btnPadding,
            shape: shape,
            elevation: 0,
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
          child: child,
        );
    }

    if (expand) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}

/// Standard dialog/bottomSheet action bar.
///
/// Provides consistent layout for Cancel + Primary actions at dialog bottoms.
///
/// Usage:
/// ```dart
/// AppDialogActions(
///   onCancel: () => Navigator.pop(context),
///   onConfirm: _save,
///   confirmLabel: 'Lưu',
///   confirmIcon: Icons.save,
/// )
/// ```
class AppDialogActions extends StatelessWidget {
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;
  final String cancelLabel;
  final String confirmLabel;
  final IconData? confirmIcon;
  final AppButtonVariant confirmVariant;
  final bool isLoading;
  final Widget? extraAction;

  const AppDialogActions({
    super.key,
    this.onCancel,
    this.onConfirm,
    this.cancelLabel = 'Hủy',
    this.confirmLabel = 'Lưu',
    this.confirmIcon,
    this.confirmVariant = AppButtonVariant.primary,
    this.isLoading = false,
    this.extraAction,
  });

  /// Shorthand for delete confirmation dialogs
  const AppDialogActions.delete({
    super.key,
    this.onCancel,
    this.onConfirm,
    this.cancelLabel = 'Hủy',
    this.confirmLabel = 'Xóa',
    this.confirmIcon = Icons.delete_outline,
    this.isLoading = false,
    this.extraAction,
  }) : confirmVariant = AppButtonVariant.danger;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    if (isMobile) {
      // Mobile: nút full-width, lưu trên / hủy dưới, dễ bấm
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (extraAction != null) ...[
              extraAction!,
              const SizedBox(height: 8),
            ],
            AppButton(
              onPressed: onConfirm,
              label: confirmLabel,
              icon: confirmIcon,
              variant: confirmVariant,
              isLoading: isLoading,
              expand: true,
            ),
            const SizedBox(height: 8),
            AppButton.cancel(
              onPressed: onCancel ?? () => Navigator.pop(context),
              label: cancelLabel,
              expand: true,
            ),
          ],
        ),
      );
    }

    // Desktop: layout ngang, hủy trái + lưu phải
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          if (extraAction != null) ...[
            extraAction!,
            const Spacer(),
          ] else
            const Spacer(),
          AppButton.cancel(
            onPressed: onCancel ?? () => Navigator.pop(context),
            label: cancelLabel,
          ),
          const SizedBox(width: 12),
          AppButton(
            onPressed: onConfirm,
            label: confirmLabel,
            icon: confirmIcon,
            variant: confirmVariant,
            isLoading: isLoading,
          ),
        ],
      ),
    );
  }
}

/// Inline action icon buttons for table rows (Edit, Delete, View, etc.)
///
/// Usage:
/// ```dart
/// AppActionIcon.edit(onPressed: () => _edit(item))
/// AppActionIcon.delete(onPressed: () => _delete(item))
/// AppActionIcon.view(onPressed: () => _view(item))
/// ```
class AppActionIcon extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final Color color;
  final String? tooltip;
  final double size;

  const AppActionIcon({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.color,
    this.tooltip,
    this.size = 20,
  });

  const AppActionIcon.edit({
    super.key,
    required this.onPressed,
    this.tooltip = 'Sửa',
    this.size = 20,
  })  : icon = Icons.edit_outlined,
        color = const Color(0xFF1E3A5F);

  const AppActionIcon.delete({
    super.key,
    required this.onPressed,
    this.tooltip = 'Xóa',
    this.size = 20,
  })  : icon = Icons.delete_outline,
        color = const Color(0xFFEF4444);

  const AppActionIcon.view({
    super.key,
    required this.onPressed,
    this.tooltip = 'Xem',
    this.size = 20,
  })  : icon = Icons.visibility_outlined,
        color = const Color(0xFF1E3A5F);

  const AppActionIcon.approve({
    super.key,
    required this.onPressed,
    this.tooltip = 'Duyệt',
    this.size = 20,
  })  : icon = Icons.check_circle_outline,
        color = const Color(0xFF16A34A);

  const AppActionIcon.reject({
    super.key,
    required this.onPressed,
    this.tooltip = 'Từ chối',
    this.size = 20,
  })  : icon = Icons.cancel_outlined,
        color = const Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: size, color: color),
          ),
        ),
      ),
    );
  }
}
