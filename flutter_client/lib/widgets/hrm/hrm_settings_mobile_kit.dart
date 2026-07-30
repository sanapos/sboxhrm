import 'package:flutter/material.dart';

import '../hrm_page_chrome.dart';
import '../pos/pos_theme.dart';
import '../safe_layout_widgets.dart';
import '../../l10n/app_tr.dart';

/// Giao diện màn con Thiết lập HRM (kiểu KiotViet / trang chủ hub).
class HrmSettingsMobileKit {
  HrmSettingsMobileKit._();

  /// Active khi mở từ hub — cả mobile lẫn web/desktop (đồng bộ trang chủ).
  static bool active(BuildContext _) => HrmPageChrome.isEmbedded;

  static Color scaffoldBackground(BuildContext context) =>
      PosTheme.background;

  static EdgeInsets pagePadding(BuildContext context) {
    if (!active(context)) return const EdgeInsets.all(24);
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 900) return const EdgeInsets.fromLTRB(20, 12, 20, 24);
    return const EdgeInsets.fromLTRB(12, 8, 12, 20);
  }

  static int gridColumns(BuildContext context, {int mobile = 2}) {
    if (!active(context)) return 1;
    final w = MediaQuery.sizeOf(context).width;
    if (w >= 900) return 3;
    if (w >= 600) return 2;
    return mobile;
  }
}

/// Nút Thêm gọn trong section — thay IconButton (+) đứng một mình.
class HrmSettingsAddButton extends StatelessWidget {
  const HrmSettingsAddButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.add,
    this.compact = false,
  });

  final String label;
  final VoidCallback onPressed;
  final IconData icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton.filledTonal(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        style: IconButton.styleFrom(
          backgroundColor: PosTheme.kiotBlueLight,
          foregroundColor: PosTheme.kiotBlue,
          minimumSize: const Size(40, 40),
          padding: EdgeInsets.zero,
        ),
        tooltip: tr(label),
      );
    }
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: PosTheme.kiotBlue),
      label: Text(
        tr(label),
        style: const TextStyle(
          color: PosTheme.kiotBlue,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

/// Khối section có tiêu đề + trailing (Thêm, Lưu…).
class HrmSettingsSection extends StatelessWidget {
  const HrmSettingsSection({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(12, 12, 12, 10),
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: PosTheme.mobileCardDecoration(),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(title),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: PosTheme.textPrimary,
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

/// Hàng tìm kiếm + action (Thêm) trên cùng một dòng.
class HrmSettingsSearchToolbar extends StatelessWidget {
  const HrmSettingsSearchToolbar({
    super.key,
    this.search,
    this.actions = const [],
  });

  final Widget? search;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    if (search == null && actions.isEmpty) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (search != null) Expanded(child: search!),
        if (search != null && actions.isNotEmpty) const SizedBox(width: 8),
        ...actions,
      ],
    );
  }
}

/// Chip lọc ngang — thay dropdown xếp dọc trên mobile.
class HrmSettingsFilterChipOption {
  const HrmSettingsFilterChipOption({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;
}

class HrmSettingsFilterChips extends StatelessWidget {
  const HrmSettingsFilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.onClear,
    this.clearLabel = 'Xóa lọc',
  });

  final List<HrmSettingsFilterChipOption> options;
  final String selected;
  final ValueChanged<String> onSelected;
  final VoidCallback? onClear;
  final String clearLabel;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final opt in options)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(tr(opt.label), style: const TextStyle(fontSize: 12)),
                selected: selected == opt.value,
                onSelected: (_) => onSelected(opt.value),
                selectedColor: PosTheme.kiotBlueLight,
                checkmarkColor: PosTheme.kiotBlue,
                labelStyle: TextStyle(
                  color: selected == opt.value
                      ? PosTheme.kiotBlue
                      : PosTheme.textSecondary,
                  fontWeight: selected == opt.value
                      ? FontWeight.w600
                      : FontWeight.w500,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                visualDensity: VisualDensity.compact,
              ),
            ),
          if (onClear != null)
            ActionChip(
              label: Text(tr(clearLabel), style: const TextStyle(fontSize: 12)),
              avatar: const Icon(Icons.filter_alt_off, size: 16),
              onPressed: onClear,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}

/// Lưới 2–3 cột cho danh sách entity trên mobile embedded.
class HrmSettingsEntityGrid extends StatelessWidget {
  const HrmSettingsEntityGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.columns = 2,
    this.spacing = 8,
    this.childAspectRatio = 0.92,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final int columns;
  final double spacing;
  final double childAspectRatio;

  @override
  Widget build(BuildContext context) {
    final cols = HrmSettingsMobileKit.active(context) ? columns : 1;
    if (cols <= 1) {
      return Column(
        children: [
          for (var i = 0; i < itemCount; i++) ...[
            if (i > 0) SizedBox(height: spacing),
            itemBuilder(context, i),
          ],
        ],
      );
    }
    return SafeFixedGrid(
      crossAxisCount: cols,
      spacing: spacing,
      runSpacing: spacing,
      childAspectRatio: childAspectRatio,
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}

/// Tile compact trong lưới HRM settings.
class HrmSettingsEntityTile extends StatelessWidget {
  const HrmSettingsEntityTile({
    super.key,
    required this.title,
    this.subtitle,
    this.meta,
    this.icon,
    this.iconColor,
    this.badge,
    this.badgeColor,
    this.onTap,
    this.onLongPress,
    this.menuItems,
    this.onMenuSelected,
  });

  final String title;
  final String? subtitle;
  final String? meta;
  final IconData? icon;
  final Color? iconColor;
  final String? badge;
  final Color? badgeColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final List<PopupMenuEntry<String>>? menuItems;
  final ValueChanged<String>? onMenuSelected;

  @override
  Widget build(BuildContext context) {
    final ic = iconColor ?? PosTheme.kiotBlue;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: PosTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (icon != null)
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: ic.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, size: 18, color: ic),
                    ),
                  if (icon != null) const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(title),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: PosTheme.textPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            tr(subtitle!),
                            style: const TextStyle(
                              fontSize: 11,
                              color: PosTheme.textSecondary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (menuItems != null && menuItems!.isNotEmpty)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert,
                          size: 18, color: PosTheme.textSecondary),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      itemBuilder: (_) => menuItems!,
                      onSelected: onMenuSelected ??
                          (v) {
                            if (v == 'delete') onLongPress?.call();
                          },
                    )
                  else if (badge != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (badgeColor ?? const Color(0xFF16A34A))
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        tr(badge!),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: badgeColor ?? const Color(0xFF16A34A),
                        ),
                      ),
                    ),
                ],
              ),
              if (meta != null) ...[
                const Spacer(),
                Text(
                  tr(meta!),
                  style: const TextStyle(
                    fontSize: 10,
                    color: PosTheme.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Hàng danh sách dày — avatar + 2 dòng + badge.
class HrmSettingsDenseTile extends StatelessWidget {
  const HrmSettingsDenseTile({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: PosTheme.border),
          ),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(title),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: PosTheme.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        tr(subtitle!),
                        style: const TextStyle(
                          fontSize: 12,
                          color: PosTheme.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
