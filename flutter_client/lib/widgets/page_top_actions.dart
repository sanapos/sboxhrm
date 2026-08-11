import 'package:flutter/material.dart';

import 'pos/pos_theme.dart';
import '../l10n/app_tr.dart';
import '../utils/responsive_helper.dart';
import '../utils/vietnamese_font.dart';

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

/// Nút action gọn cho top bar (desktop) / sheet FAB (mobile).
///
/// Mặc định **chỉ icon + tooltip** (tránh che title/search).
/// [primary] + [showLabel] mới hiện chữ ngắn cho CTA chính.
///
/// Mobile: toàn bộ action gom vào [PageTopActionsFab] góc dưới phải.
class HrmTopBarAction extends StatelessWidget {
  const HrmTopBarAction({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.primary = false,
    this.iconOnly = true,
    this.showLabel = false,
    this.pinOnMobile,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  /// Giữ tương thích call-site cũ; mặc định true.
  final bool iconOnly;

  /// Chỉ dùng với [primary] khi muốn chữ (vd. "Tạo đơn").
  final bool showLabel;

  /// `true` = luôn giữ trên thanh mobile; `false` = ưu tiên ẩn vào 「Thêm」;
  /// `null` = tự đoán (Tải lại / Xuất Excel / primary / Thêm mới).
  final bool? pinOnMobile;

  bool get prefersVisibleOnMobile {
    if (pinOnMobile != null) return pinOnMobile!;
    if (primary) return true;
    final l = label.toLowerCase();
    if (icon == Icons.refresh ||
        l.contains('tải lại') ||
        l.contains('làm mới') ||
        l.contains('refresh')) {
      return true;
    }
    if (l.contains('xuất excel') ||
        icon == Icons.file_download_outlined ||
        icon == Icons.table_chart_outlined ||
        icon == Icons.file_download) {
      return true;
    }
    if (icon == Icons.add ||
        icon == Icons.add_circle_outline ||
        icon == Icons.add_rounded ||
        l.startsWith('thêm') ||
        l.startsWith('tạo')) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final tip = tr(label);
    final wideEnough = MediaQuery.sizeOf(context).width >= 1100;
    final compact = Responsive.isMobile(context);
    final minTap = compact ? 44.0 : 36.0;
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
              minimumSize: Size(minTap, minTap),
              maximumSize: Size(minTap, minTap),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Icon(icon, size: compact ? 20 : 18),
          ),
        );
      }
      return IconButton(
        onPressed: onPressed,
        tooltip: tip,
        icon: Icon(icon, size: compact ? 22 : 20),
        color: PosTheme.textPrimary,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.all(compact ? 10 : 8),
        constraints: BoxConstraints(minWidth: minTap, minHeight: minTap),
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
        minimumSize: Size(0, minTap),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

/// Mở sheet danh sách thao tác trang (dùng bởi FAB mobile / overflow desktop).
Future<void> showPageTopActionsSheet(
  BuildContext context,
  List<HrmTopBarAction> items,
) async {
  if (items.isEmpty) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4D4D8),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  tr('Thao tác'),
                  style: vietnameseTextStyle(const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  )),
                ),
              ),
              ...items.map((a) {
                final enabled = a.onPressed != null;
                return ListTile(
                  enabled: enabled,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  minVerticalPadding: 12,
                  leading: CircleAvatar(
                    radius: 22,
                    backgroundColor: a.primary
                        ? PosTheme.kiotBlue.withValues(alpha: 0.12)
                        : const Color(0xFFF4F4F5),
                    child: Icon(
                      a.icon,
                      color: enabled
                          ? (a.primary
                              ? PosTheme.kiotBlue
                              : PosTheme.textPrimary)
                          : const Color(0xFFA1A1AA),
                      size: 22,
                    ),
                  ),
                  title: Text(
                    tr(a.label),
                    style: vietnameseTextStyle(TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: enabled
                          ? const Color(0xFF18181B)
                          : const Color(0xFFA1A1AA),
                    )),
                  ),
                  onTap: !enabled
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          a.onPressed?.call();
                        },
                );
              }),
            ],
          ),
        ),
      );
    },
  );
}

/// FAB góc dưới phải — gom toàn bộ action trang trên mobile (không chèn AppBar).
class PageTopActionsFab extends StatelessWidget {
  const PageTopActionsFab({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Responsive.isMobile(context)) return const SizedBox.shrink();

    return ListenableBuilder(
      listenable: PageTopActions.instance,
      builder: (context, _) {
        final acts = PageTopActions.instance.actions;
        final hrm = acts.whereType<HrmTopBarAction>().toList(growable: false);
        if (hrm.isEmpty) return const SizedBox.shrink();

        // 1 action primary → FAB chạy thẳng; nhiều action → mở danh sách.
        if (hrm.length == 1) {
          final only = hrm.first;
          return FloatingActionButton(
            heroTag: 'page_top_actions_fab',
            tooltip: tr(only.label),
            backgroundColor: PosTheme.kiotBlue,
            foregroundColor: Colors.white,
            onPressed: only.onPressed,
            child: Icon(only.icon, size: 26),
          );
        }

        return FloatingActionButton(
          heroTag: 'page_top_actions_fab',
          tooltip: tr('Thao tác'),
          backgroundColor: PosTheme.kiotBlue,
          foregroundColor: Colors.white,
          onPressed: () => showPageTopActionsSheet(context, hrm),
          child: const Icon(Icons.apps_rounded, size: 26),
        );
      },
    );
  }
}

/// Thanh action trang — desktop/tablet. Mobile dùng [PageTopActionsFab].
class PageTopActionsBar extends StatelessWidget {
  const PageTopActionsBar({
    super.key,
    required this.actions,
    this.maxWidth,
    this.reverse = false,
    this.maxVisibleOnMobile = 3,
  });

  final List<Widget> actions;
  final double? maxWidth;
  final bool reverse;

  /// Legacy: mobile AppBar không còn dùng bar này (đã chuyển FAB).
  final int maxVisibleOnMobile;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    // Mobile: action nằm ở FAB — không render trên thanh trên.
    if (Responsive.isMobile(context)) return const SizedBox.shrink();

    final children = [
      for (var i = 0; i < actions.length; i++) ...[
        if (i > 0) SizedBox(width: reverse ? 4 : 6),
        actions[i],
      ],
    ];

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: children,
    );

    final scroll = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: reverse,
      child: row,
    );

    if (maxWidth != null) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth!),
        child: scroll,
      );
    }
    return scroll;
  }
}
