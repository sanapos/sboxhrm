import 'package:flutter/material.dart';

import 'pos/pos_theme.dart';
import '../l10n/app_tr.dart';

/// Host đăng ký action của trang hiện tại lên top bar (main_layout).
class PageTopActions extends ChangeNotifier {
  PageTopActions._();
  static final PageTopActions instance = PageTopActions._();

  List<Widget> _actions = const [];
  List<Widget> get actions => _actions;

  void setActions(List<Widget> actions) {
    _actions = List<Widget>.unmodifiable(actions);
    notifyListeners();
  }

  void clear() {
    if (_actions.isEmpty) return;
    _actions = const [];
    notifyListeners();
  }
}

/// Đăng ký [actions] vào top bar khi widget còn mounted.
class RegisterPageTopActions extends StatefulWidget {
  const RegisterPageTopActions({
    super.key,
    required this.actions,
    required this.child,
  });

  final List<Widget> actions;
  final Widget child;

  @override
  State<RegisterPageTopActions> createState() => _RegisterPageTopActionsState();
}

class _RegisterPageTopActionsState extends State<RegisterPageTopActions> {
  @override
  void initState() {
    super.initState();
    PageTopActions.instance.setActions(widget.actions);
  }

  @override
  void didUpdateWidget(covariant RegisterPageTopActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    PageTopActions.instance.setActions(widget.actions);
  }

  @override
  void dispose() {
    PageTopActions.instance.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Nút action gọn cho top bar trắng.
///
/// Mặc định **chỉ icon + tooltip** (tránh che title/search).
/// [primary] + [showLabel] mới hiện chữ ngắn cho CTA chính.
class HrmTopBarAction extends StatelessWidget {
  const HrmTopBarAction({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.primary = false,
    this.iconOnly = true,
    this.showLabel = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  /// Giữ tương thích call-site cũ; mặc định true.
  final bool iconOnly;

  /// Chỉ dùng với [primary] khi muốn chữ (vd. "Tạo đơn").
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final tip = tr(label);
    final wideEnough = MediaQuery.sizeOf(context).width >= 1100;
    final asIcon = iconOnly || !showLabel || !primary || !wideEnough;

    if (asIcon) {
      if (primary) {
        return Tooltip(
          message: tip,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: PosTheme.kiotBlue,
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  PosTheme.kiotBlue.withValues(alpha: 0.35),
              padding: EdgeInsets.zero,
              minimumSize: const Size(36, 36),
              maximumSize: const Size(36, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Icon(icon, size: 18),
          ),
        );
      }
      return IconButton(
        onPressed: onPressed,
        tooltip: tip,
        icon: Icon(icon, size: 20),
        color: PosTheme.textPrimary,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      );
    }

    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(tr(label), style: const TextStyle(fontSize: 12.5)),
      style: FilledButton.styleFrom(
        backgroundColor: PosTheme.kiotBlue,
        foregroundColor: Colors.white,
        disabledBackgroundColor: PosTheme.kiotBlue.withValues(alpha: 0.35),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(0, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
