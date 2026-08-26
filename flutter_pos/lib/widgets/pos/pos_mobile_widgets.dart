import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../utils/media_query_safe_padding.dart';
import '../../utils/navigation_notifier.dart';
import '../../utils/responsive_helper.dart';
import '../hrm_page_chrome.dart';
import 'pos_hub_scope.dart';
import 'pos_theme.dart';
import '../safe_layout_widgets.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Xác nhận và đăng xuất khỏi POS / cửa hàng.
Future<void> showPosLogoutDialog(BuildContext context) async {
  final l = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr(l.logout)),
      content: Text(tr(l.logoutConfirm)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(tr(l.cancel)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: Text(tr(l.logout)),
        ),
      ],
    ),
  );
  if (ok == true && context.mounted) {
    await Provider.of<AuthProvider>(context, listen: false).logout();
  }
}

/// Thẻ tài khoản POS — đồng bộ Tổng quan & Nhiều hơn.
class PosMobileProfileCard extends StatelessWidget {
  const PosMobileProfileCard({
    super.key,
    required this.name,
    required this.subtitle,
  });

  final String name;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: PosTheme.mobileCardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: PosTheme.kiotBlueLight,
            child: Text(
              tr(name.isNotEmpty ? name[0].toUpperCase() : 'S'),
              style: const TextStyle(
                color: PosTheme.kiotBlue,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(name),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  tr(subtitle),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: PosTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: tr('Cài đặt'),
            onPressed: () => NavigationNotifier.goToModule('SettingsHub'),
            icon: const Icon(Icons.settings_outlined, color: PosTheme.kiotBlue),
          ),
          IconButton(
            tooltip: tr('Đăng xuất'),
            onPressed: () => showPosLogoutDialog(context),
            icon: Icon(Icons.logout, color: Colors.red.shade600),
          ),
        ],
      ),
    );
  }
}

/// Một ô trong lưới section POS hub.
class PosMobileHubGridItem {
  const PosMobileHubGridItem({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

/// Khối section POS — tiêu đề + nội dung tùy ý (list, metric…).
class PosMobileHubSection extends StatelessWidget {
  const PosMobileHubSection({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: PosTheme.mobileCardDecoration(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(title),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// Lưới kiểu KiotViet — tự tăng cột theo bề rộng (mobile 3 → desktop 6).
class PosMobileHubSectionGrid extends StatelessWidget {
  const PosMobileHubSectionGrid({
    super.key,
    required this.title,
    required this.items,
    this.crossAxisCount,
  });

  final String title;
  final List<PosMobileHubGridItem> items;
  final int? crossAxisCount;

  static int columnsForWidth(double width) {
    if (width >= 1100) return 6;
    if (width >= 860) return 5;
    if (width >= 560) return 4;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols =
            crossAxisCount ?? columnsForWidth(constraints.maxWidth);
        final roomy = cols >= 4;
        return PosMobileHubSection(
          title: title,
          child: SafeFixedGrid(
            crossAxisCount: cols,
            spacing: roomy ? 8 : 4,
            runSpacing: roomy ? 8 : 4,
            childAspectRatio: roomy ? 1.05 : 0.92,
            itemCount: items.length,
            itemBuilder: (context, index) => _PosMobileHubGridTile(
              item: items[index],
              large: roomy,
            ),
          ),
        );
      },
    );
  }
}

class _PosMobileHubGridTile extends StatelessWidget {
  const _PosMobileHubGridTile({
    required this.item,
    this.large = false,
  });

  final PosMobileHubGridItem item;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: item.onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          vertical: large ? 10 : 8,
          horizontal: large ? 6 : 4,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              item.icon,
              color: PosTheme.kiotBlue,
              size: large ? 28 : 26,
            ),
            SizedBox(height: large ? 8 : 6),
            Text(
              tr(item.label),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: large ? 12.5 : 11,
                height: 1.2,
                fontWeight: large ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ô số liệu compact trong section Tổng quan.
class PosMobileMetricTile extends StatelessWidget {
  const PosMobileMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    this.icon,
    this.valueColor,
  });

  final String label;
  final String value;
  final String? subtitle;
  final IconData? icon;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: PosTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: PosTheme.kiotBlue),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  tr(label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: PosTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            tr(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: valueColor ?? PosTheme.textPrimary,
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              tr(subtitle!),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                color: PosTheme.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// POS dùng layout mobile (thẻ + cuộn dọc) thay vì bảng ngang.
bool posUseMobileList(BuildContext context) =>
    !Responsive.preferTableListLayout(context);

/// SafeArea trên cùng — hub / AppBar ngoài đã xử lý thì bỏ qua.
/// Trang push từ «Nhiều hơn» (báo cáo, kho, sổ sách…) luôn cần chừa status bar.
bool posNeedsTopSafeArea(BuildContext context) {
  if (!posUseMobileList(context)) return false;
  if (PosHubScope.pushedSubPageOf(context)) return true;
  if (PosHubScope.of(context)) return false;
  if (HrmPageChrome.usesMainLayoutAppBar) return false;
  return true;
}

/// Bọc nội dung mobile POS (giống màn Bán hàng: SafeArea top, full width).
Widget posMobileSafeBody(BuildContext context, Widget child) {
  if (!posNeedsTopSafeArea(context)) return child;
  return withFallbackTopInset(
    context,
    SafeArea(bottom: false, child: child),
  );
}

/// Thanh thu/gọn bộ lọc — mặc định đóng để đọc danh sách.
class PosFilterCollapse extends StatelessWidget {
  const PosFilterCollapse({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.child,
    this.title = 'Bộ lọc',
    this.subtitle,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    const accent = PosTheme.kiotBlue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: accent.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.tune, size: 16, color: accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(title),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: accent,
                          ),
                        ),
                        if (!expanded &&
                            subtitle != null &&
                            subtitle!.trim().isNotEmpty)
                          Text(
                            tr(subtitle!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: PosTheme.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: accent,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (expanded) ...[
          const SizedBox(height: 8),
          child,
        ],
      ],
    );
  }
}

/// Mở bottom sheet bộ lọc trên mobile (có Đặt lại / Áp dụng).
Future<void> showPosMobileFilterSheet(
  BuildContext context, {
  required Widget child,
  String title = 'Bộ lọc',
  VoidCallback? onReset,
  VoidCallback? onApply,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Text(tr(title),
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
          if (onReset != null || onApply != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    if (onReset != null)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            onReset();
                            Navigator.pop(ctx);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: PosTheme.kiotBlue,
                            side: const BorderSide(color: PosTheme.kiotBlue),
                            minimumSize: const Size(0, 44),
                          ),
                          child: Text(tr('Đặt lại')),
                        ),
                      ),
                    if (onReset != null && onApply != null)
                      const SizedBox(width: 10),
                    if (onApply != null)
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            onApply();
                            Navigator.pop(ctx);
                          },
                          style: PosTheme.mobilePrimaryButton,
                          child: Text(tr('Áp dụng')),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Desktop: sidebar lọc + nội dung. Mobile: chỉ nội dung + nút lọc trên header.
class PosResponsiveFilterLayout extends StatelessWidget {
  const PosResponsiveFilterLayout({
    super.key,
    required this.filterPanel,
    required this.child,
    this.onOpenFilters,
    this.activeFilterCount = 0,
  });

  final Widget filterPanel;
  final Widget child;
  final VoidCallback? onOpenFilters;
  final int activeFilterCount;

  @override
  Widget build(BuildContext context) {
    if (posUseMobileList(context)) {
      return child;
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        filterPanel,
        Expanded(child: child),
      ],
    );
  }
}

/// Header trang danh sách POS (mobile gọn).
class PosMobileListHeader extends StatelessWidget {
  const PosMobileListHeader({
    super.key,
    required this.icon,
    required this.title,
    this.onCreate,
    this.createLabel = 'Tạo mới',
    this.onRefresh,
    this.onOpenFilters,
    this.activeFilterCount = 0,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onCreate;
  final String createLabel;
  final VoidCallback? onRefresh;
  final VoidCallback? onOpenFilters;
  final int activeFilterCount;
  final List<Widget>? trailing;

  @override
  Widget build(BuildContext context) {
    final mobile = posUseMobileList(context);
    return ListenableBuilder(
      listenable: NavigationNotifier.mobileDrawerModuleActive,
      builder: (context, _) {
        final usesMainAppBar = HrmPageChrome.usesMainLayoutAppBar;
        final pushed = PosHubScope.pushedSubPageOf(context);
        final hideTitle = mobile && usesMainAppBar && !pushed;

        Widget actionButtons() => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onOpenFilters != null)
                  IconButton(
                    tooltip: tr('Bộ lọc'),
                    onPressed: onOpenFilters,
                    icon: Badge(
                      isLabelVisible: activeFilterCount > 0,
                      label: Text(tr('$activeFilterCount')),
                      child: const Icon(Icons.filter_list),
                    ),
                  ),
                if (onRefresh != null)
                  IconButton(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh),
                    tooltip: tr('Tải lại'),
                  ),
                if (trailing != null) ...trailing!,
              ],
            );

        return Container(
          color: Colors.white,
          padding:
              EdgeInsets.fromLTRB(mobile ? 12 : 16, 10, mobile ? 8 : 16, 10),
          child: mobile
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!hideTitle)
                      Row(
                        children: [
                          if (pushed)
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.arrow_back),
                              onPressed: () => Navigator.maybePop(context),
                            ),
                          if (!pushed) ...[
                            Icon(icon,
                                color: PosTheme.kiotBlue, size: 22),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              tr(title),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          actionButtons(),
                        ],
                      )
                    else if (onOpenFilters != null ||
                        onRefresh != null ||
                        (trailing != null && trailing!.isNotEmpty))
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [actionButtons()],
                      ),
                    if (onCreate != null) ...[
                      if (!hideTitle || onOpenFilters != null || onRefresh != null)
                        const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: onCreate,
                          icon: const Icon(Icons.add, size: 18),
                          label: Text(tr(createLabel)),
                          style: FilledButton.styleFrom(
                            backgroundColor: PosTheme.kiotBlue,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ],
                )
              : Row(
                  children: [
                    Icon(icon, color: PosTheme.kiotBlue),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(tr(title),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    if (onCreate != null)
                      FilledButton.icon(
                        onPressed: onCreate,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(tr(createLabel)),
                        style: FilledButton.styleFrom(
                            backgroundColor: PosTheme.kiotBlue),
                      ),
                    if (trailing != null) ...trailing!,
                    if (onRefresh != null) ...[
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: onRefresh,
                        icon: const Icon(Icons.refresh),
                        tooltip: tr('Tải lại'),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class PosMobileField {
  const PosMobileField(this.label, this.value);
  final String label;
  final String value;
}

/// Thẻ phiếu/chứng từ có thể mở rộng — dùng cho danh sách POS trên mobile.
class PosMobileExpandableDocCard extends StatelessWidget {
  const PosMobileExpandableDocCard({
    super.key,
    required this.expanded,
    required this.onTap,
    required this.code,
    required this.status,
    required this.fields,
    this.detail,
    this.accentColor = PosTheme.kiotBlue,
  });

  final bool expanded;
  final VoidCallback onTap;
  final String code;
  final Widget status;
  final List<PosMobileField> fields;
  final Widget? detail;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: PosTheme.mobileCardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        expanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right,
                        size: 22,
                        color: PosTheme.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          tr(code),
                          style: TextStyle(
                            color: accentColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      status,
                    ],
                  ),
                  if (!expanded && fields.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...fields.take(3).map(_kv),
                  ],
                ],
              ),
            ),
          ),
          if (expanded && detail != null)
            Container(
              width: double.infinity,
              color: const Color(0xFFF8FAFC),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: detail,
            ),
        ],
      ),
    );
  }

  Widget _kv(PosMobileField f) {
    return Padding(
      padding: const EdgeInsets.only(left: 26, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(tr(f.label),
                style: const TextStyle(
                    fontSize: 12, color: PosTheme.textSecondary)),
          ),
          Expanded(
            child: Text(tr(f.value),
                style: const TextStyle(fontSize: 13),
                textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

/// Phân trang gọn cho mobile.
class PosMobilePager extends StatelessWidget {
  const PosMobilePager({
    super.key,
    required this.total,
    required this.page,
    required this.pageSize,
    required this.onPageChanged,
    this.label = 'phiếu',
  });

  final int total;
  final int page;
  final int pageSize;
  final ValueChanged<int> onPageChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (total <= pageSize) return const SizedBox.shrink();
    final pages = (total / pageSize).ceil();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(tr('Tổng $total $label · Trang $page/$pages'),
              style: const TextStyle(
                  fontSize: 12, color: PosTheme.textSecondary),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left),
            onPressed: page > 1 ? () => onPageChanged(page - 1) : null,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right),
            onPressed: page < pages ? () => onPageChanged(page + 1) : null,
          ),
        ],
      ),
    );
  }
}

/// Thanh hành động cố định dưới màn editor mobile.
class PosMobileEditorActionBar extends StatelessWidget {
  const PosMobileEditorActionBar({
    super.key,
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// Thẻ dòng hàng trong editor mobile.
class PosMobileLineItemCard extends StatelessWidget {
  const PosMobileLineItemCard({
    super.key,
    required this.index,
    required this.code,
    required this.name,
    required this.fields,
    this.trailing,
    this.onRemove,
  });

  final int index;
  final String code;
  final String name;
  final List<Widget> fields;
  final Widget? trailing;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: PosTheme.mobileCardDecoration(),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: PosTheme.kiotBlueLight,
                child: Text(
                  tr('$index'),
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: PosTheme.kiotBlue),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(name),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    Text(tr(code),
                        style: const TextStyle(
                            fontSize: 12, color: PosTheme.textSecondary)),
                  ],
                ),
              ),
              if (onRemove != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: onRemove,
                  icon: Icon(Icons.delete_outline,
                      size: 20, color: Colors.red.shade400),
                ),
            ],
          ),
          if (fields.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...fields,
          ],
          if (trailing != null) ...[
            const SizedBox(height: 8),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Layout editor mobile: cuộn dọc (tìm hàng + dòng + thông tin phiếu).
Widget posMobileEditorScrollBody({
  required Widget searchBar,
  required Widget lines,
  required Widget metaPanel,
  Widget? actionBar,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              searchBar,
              lines,
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: DecoratedBox(
                  decoration: PosTheme.mobileCardDecoration(),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: metaPanel,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      if (actionBar != null) actionBar,
    ],
  );
}

/// Layout editor: desktop Row, mobile Column + panel meta có thể cuộn.
class PosMobileEditorShell extends StatelessWidget {
  const PosMobileEditorShell({
    super.key,
    required this.main,
    required this.sidePanel,
    this.sidePanelWidth = 320,
    this.mobileActionBar,
  });

  final Widget main;
  final Widget sidePanel;
  final double sidePanelWidth;
  final Widget? mobileActionBar;

  @override
  Widget build(BuildContext context) {
    if (!posUseMobileList(context)) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 3, child: main),
          SizedBox(width: sidePanelWidth, child: sidePanel),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: main),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: DecoratedBox(
                    decoration: PosTheme.mobileCardDecoration(),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: sidePanel,
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        ),
        if (mobileActionBar != null) mobileActionBar!,
      ],
    );
  }
}

/// Header mobile POS — đồng bộ với màn Bán hàng (SafeArea + nút Home trong hub).
class PosMobileKiotHeader extends StatelessWidget {
  const PosMobileKiotHeader({
    super.key,
    required this.title,
    this.onSearch,
    this.onFilter,
    this.onSort,
    this.onMore,
    this.onRefresh,
    this.onHome,
    this.activeFilterCount = 0,
    this.filterChips,
    this.trailing,
  });

  final String title;
  final VoidCallback? onSearch;
  final VoidCallback? onFilter;
  final VoidCallback? onSort;
  final VoidCallback? onMore;
  final VoidCallback? onRefresh;
  final VoidCallback? onHome;
  final int activeFilterCount;
  final Widget? filterChips;
  final List<Widget>? trailing;

  @override
  Widget build(BuildContext context) {
    final inHub = PosHubScope.of(context);
    final pushed = PosHubScope.pushedSubPageOf(context);
    final compactHeader = inHub;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              inHub ? 4 : (pushed ? 0 : 12), 4, 4, 0),
          child: Row(
            children: [
              if (pushed)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.maybePop(context),
                ),
              if (inHub)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: tr(NavigationNotifier.mainLayoutReady.value
                      ? 'Về SBOX HRM'
                      : 'Về trang chủ'),
                  icon: Icon(
                    NavigationNotifier.mainLayoutReady.value
                        ? Icons.apps_outlined
                        : Icons.home_outlined,
                    color: PosTheme.textPrimary,
                  ),
                  onPressed: onHome ??
                      NavigationNotifier.leavePosHubToAppHome,
                ),
              Expanded(
                child: Text(
                  tr(title),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: PosTheme.textPrimary,
                  ),
                ),
              ),
              if (trailing != null) ...trailing!,
              if (compactHeader)
                _buildCompactActions(context)
              else ...[
              if (filterChips != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: filterChips!,
                ),
              if (onRefresh != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                  tooltip: tr('Làm mới'),
                ),
              if (onSearch != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onSearch,
                  icon: const Icon(Icons.search),
                  tooltip: tr('Tìm kiếm'),
                ),
              if (onFilter != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onFilter,
                  icon: Badge(
                    isLabelVisible: activeFilterCount > 0,
                    label: Text(tr('$activeFilterCount')),
                    child: const Icon(Icons.filter_list, size: 22),
                  ),
                ),
              if (onSort != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onSort,
                  icon: const Icon(Icons.import_export),
                  tooltip: tr('Sắp xếp'),
                ),
              if (onMore != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onMore,
                  icon: const Icon(Icons.more_horiz),
                  tooltip: tr('Thêm'),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1, color: PosTheme.border),
      ],
    );
    return Material(
      color: Colors.white,
      child: posNeedsTopSafeArea(context)
          ? withFallbackTopInset(
              context,
              SafeArea(bottom: false, child: content),
            )
          : withFallbackTopInset(context, content),
    );
  }

  Widget _buildCompactActions(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (filterChips != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: filterChips!,
          ),
        if (onRefresh != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onRefresh,
            icon: const Icon(Icons.sync),
            tooltip: tr('Đồng bộ'),
          ),
        if (onSearch != null)
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onSearch,
            icon: const Icon(Icons.search),
            tooltip: tr('Tìm kiếm'),
          ),
        PopupMenuButton<String>(
          icon: Badge(
            isLabelVisible: activeFilterCount > 0,
            label: Text(tr('$activeFilterCount')),
            child: const Icon(Icons.more_horiz),
          ),
          onSelected: (v) {
            switch (v) {
              case 'filter':
                onFilter?.call();
              case 'sort':
                onSort?.call();
              case 'refresh':
                onRefresh?.call();
              case 'more':
                onMore?.call();
            }
          },
          itemBuilder: (ctx) => [
            if (onFilter != null)
              PopupMenuItem(
                value: 'filter',
                child: Text(
                  tr(activeFilterCount > 0
                      ? 'Bộ lọc ($activeFilterCount)'
                      : 'Bộ lọc'),
                ),
              ),
            if (onSort != null)
              PopupMenuItem(value: 'sort', child: Text(tr('Sắp xếp'))),
            if (onRefresh != null)
              PopupMenuItem(value: 'refresh', child: Text(tr('Đồng bộ'))),
            if (onMore != null)
              PopupMenuItem(value: 'more', child: Text(tr('Thêm chức năng'))),
          ],
        ),
      ],
    );
  }
}

/// Dòng hàng hoá mobile: ảnh | tên+mã | giá+tồn.
class PosMobileProductRow extends StatelessWidget {
  const PosMobileProductRow({
    super.key,
    required this.name,
    required this.code,
    required this.priceText,
    required this.stockText,
    this.image,
    this.onTap,
    this.onLongPress,
    this.kiotSellStyle = false,
    this.orderReservedText,
    this.onScanCode,
    this.isSelected = false,
    this.selectedQty,
    this.onIncrement,
    this.onDecrement,
    this.onQtyTap,
    this.typeBadge,
  });

  final String name;
  final String code;
  final String priceText;
  final String stockText;
  final Widget? typeBadge;
  final Widget? image;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  /// Kiểu KiotViet bán hàng: badge tồn dưới mã, giá bên phải.
  final bool kiotSellStyle;
  final String? orderReservedText;
  final VoidCallback? onScanCode;
  final bool isSelected;
  final double? selectedQty;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;
  final VoidCallback? onQtyTap;

  @override
  Widget build(BuildContext context) {
    final showStepper = (selectedQty ?? 0) > 0 &&
        (onIncrement != null || onDecrement != null);
    return Material(
      color: isSelected ? const Color(0xFFE8F0FE) : Colors.white,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: image ??
                      ColoredBox(
                        color: PosTheme.kiotBlueLight,
                        child: Icon(Icons.inventory_2_outlined,
                            color: PosTheme.kiotBlue.withOpacity(0.5)),
                      ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w600,
                        height: 1.2,
                        color: isSelected
                            ? PosTheme.kiotBlue
                            : PosTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            tr(code),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: PosTheme.textSecondary,
                            ),
                          ),
                        ),
                        if (typeBadge != null) ...[
                          const SizedBox(width: 6),
                          typeBadge!,
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: 84,
                  maxWidth: showStepper ? 120 : 104,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (showStepper) ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: _qtyStepper(
                          qty: selectedQty!,
                          onMinus: onDecrement,
                          onPlus: onIncrement ?? onTap,
                          onQtyTap: onQtyTap,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      tr(priceText),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: PosTheme.kiotBlue,
                      ),
                    ),
                    if (stockText.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        tr(stockText),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: kiotSellStyle
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: stockText.contains('Hết')
                              ? const Color(0xFFB42318)
                              : PosTheme.textSecondary,
                        ),
                      ),
                    ],
                    if (orderReservedText != null) ...[
                      const SizedBox(height: 2),
                      _sellMetaChip(orderReservedText!),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _qtyStepper({
    required double qty,
    VoidCallback? onMinus,
    VoidCallback? onPlus,
    VoidCallback? onQtyTap,
  }) {
    final qtyText = qty <= 0
        ? '0'
        : (qty == qty.roundToDouble()
            ? qty.toStringAsFixed(0)
            : qty.toStringAsFixed(1));
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: PosTheme.kiotBlue.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _stepBtn(
              icon: Icons.remove,
              enabled: qty > 0 && onMinus != null,
              onTap: qty > 0 ? onMinus : null,
            ),
            InkWell(
              onTap: onQtyTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Center(
                    child: Text(
                      tr(qtyText),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: PosTheme.kiotBlue,
                        decoration: TextDecoration.underline,
                        decorationColor: Color(0x662563EB),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _stepBtn(
              icon: Icons.add,
              enabled: onPlus != null,
              onTap: onPlus,
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBtn({
    required IconData icon,
    required bool enabled,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 32,
        height: 32,
        child: Icon(
          icon,
          size: 18,
          color: enabled ? PosTheme.kiotBlue : PosTheme.textSecondary.withOpacity(0.35),
        ),
      ),
    );
  }

  Widget _sellMetaChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tr(text),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: PosTheme.textSecondary,
        ),
      ),
    );
  }
}

/// FAB tròn kiểu KiotViet.
class PosMobileFab extends StatelessWidget {
  const PosMobileFab({
    super.key,
    required this.onPressed,
    this.tooltip = 'Tạo mới',
  });

  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: onPressed,
      tooltip: tr(tooltip),
      backgroundColor: PosTheme.kiotBlue,
      foregroundColor: Colors.white,
      elevation: 4,
      child: const Icon(Icons.add, size: 28),
    );
  }
}
