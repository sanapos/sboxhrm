import 'package:flutter/material.dart';

import '../screens/settings_hub_screen.dart';
import '../utils/navigation_notifier.dart';
import '../utils/responsive_helper.dart';
import 'hrm/hrm_settings_mobile_kit.dart';
import 'pos/pos_theme.dart';
import '../l10n/app_tr.dart';

/// Shared layout tokens and helpers for HRM settings sub-pages.
class HrmPageChrome {
  HrmPageChrome._();

  /// Đồng bộ nền với trang chủ / hub (PosTheme).
  static const Color background = PosTheme.background;

  /// Brand accent = icon trang chủ (kiotBlue). Giữ tên [primaryNavy] để
  /// không phải rename hàng trăm call-site.
  static const Color primaryNavy = PosTheme.kiotBlue;

  static const Color textDark = PosTheme.textPrimary;
  static const Color textMuted = PosTheme.textSecondary;

  /// Hub sub-page is open — [main_layout] already shows back + title.
  static bool get isEmbedded => SettingsHubScreen.isEmbeddedSubPage;

  /// Mobile drawer module: AppBar ngoài đã hiển thị tiêu đề trang.
  static bool get usesMainLayoutAppBar =>
      NavigationNotifier.mobileDrawerModuleActive.value;

  /// AppBar for standalone entry only; returns null when embedded in hub.
  static PreferredSizeWidget? appBar({
    required String title,
    List<Widget>? actions,
    PreferredSizeWidget? bottom,
  }) {
    if (isEmbedded) return null;
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      leading: null,
      title: Text(
        tr(title),
        style: const TextStyle(
          color: textDark,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
      actions: actions,
      bottom: bottom,
    );
  }

  /// Toolbar shown under hub AppBar — ẩn trên mobile (action gắn section).
  static Widget embeddedActionBar({
    required List<Widget> actions,
    BuildContext? context,
  }) {
    if (!isEmbedded || actions.isEmpty) return const SizedBox.shrink();
    if (context != null && Responsive.isMobile(context)) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: PosTheme.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: actions,
      ),
    );
  }

  /// Stat cards: lưới đều khi hub kit active; row / scroll trên màn khác.
  static Widget horizontalStatCards({
    required List<Widget> cards,
    double minCardWidth = 132,
    double gap = 8,
  }) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (HrmSettingsMobileKit.active(context)) {
          final cols = cards.length <= 2
              ? cards.length
              : (constraints.maxWidth >= 720 ? 3 : 2);
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (var i = 0; i < cards.length; i++)
                SizedBox(
                  width: cols == 1
                      ? constraints.maxWidth
                      : (constraints.maxWidth - gap * (cols - 1)) / cols,
                  child: cards[i],
                ),
            ],
          );
        }
        if (constraints.maxWidth < 560) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: Responsive.horizontalScrollPadding,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  SizedBox(width: minCardWidth, child: cards[i]),
                ],
              ],
            ),
          );
        }
        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) SizedBox(width: gap + 4),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }

  /// Nền scaffold thống nhất cho màn con HRM.
  static Color scaffoldBackground(BuildContext context) =>
      HrmSettingsMobileKit.scaffoldBackground(context);

  /// Trên mobile luôn hiển thị bộ lọc (không ẩn sau nút filter).
  static bool inlineFiltersOnMobile(bool legacyToggle) => true;
}

/// Header flat kiểu hub (không gradient navy).
/// [gradientColors] legacy: lấy màu đầu làm accent icon nếu có.
class HrmPageHero extends StatelessWidget {
  const HrmPageHero({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.gradientColors,
    this.actions = const [],
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Color>? gradientColors;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: NavigationNotifier.mobileDrawerModuleActive,
      builder: (context, _) {
        final isMobile = MediaQuery.sizeOf(context).width < 768;
        final hideDuplicateTitle = isMobile &&
            (HrmPageChrome.usesMainLayoutAppBar || HrmPageChrome.isEmbedded);
        final accent = (gradientColors != null && gradientColors!.isNotEmpty)
            ? gradientColors!.first
            : HrmPageChrome.primaryNavy;

        if (hideDuplicateTitle &&
            actions.isEmpty &&
            bottom == null &&
            subtitle == null &&
            icon == null) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
          margin: EdgeInsets.fromLTRB(
            isMobile ? 12 : 16,
            isMobile ? 8 : 12,
            isMobile ? 12 : 16,
            0,
          ),
          padding: EdgeInsets.fromLTRB(
            isMobile ? 14 : 16,
            isMobile ? (hideDuplicateTitle ? 10 : 14) : 16,
            isMobile ? 14 : 16,
            isMobile ? (hideDuplicateTitle ? 10 : 14) : 16,
          ),
          decoration: PosTheme.mobileCardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (icon != null && !hideDuplicateTitle) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: PosTheme.kiotBlueLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (!hideDuplicateTitle)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tr(title),
                            style: TextStyle(
                              color: HrmPageChrome.textDark,
                              fontSize: isMobile ? 17 : 18,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              tr(subtitle!),
                              style: const TextStyle(
                                color: HrmPageChrome.textMuted,
                                fontSize: 13,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    )
                  else if (subtitle != null)
                    Expanded(
                      child: Text(
                        tr(subtitle!),
                        style: const TextStyle(
                          color: HrmPageChrome.textMuted,
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    const Spacer(),
                  ...actions,
                ],
              ),
              if (bottom != null) ...[
                const SizedBox(height: 12),
                bottom!,
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Ô tìm kiếm THỐNG NHẤT (cao 44, bo 10, nền trắng).
class HrmSearchField extends StatelessWidget {
  const HrmSearchField({
    super.key,
    this.controller,
    this.hintText = 'Tìm kiếm...',
    this.onChanged,
    this.onClear,
  });

  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final hasText = controller != null && controller!.text.isNotEmpty;
    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: tr(hintText),
          isDense: true,
          prefixIcon: const Icon(Icons.search,
              size: 20, color: HrmPageChrome.textMuted),
          suffixIcon: hasText
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: onClear,
                )
              : null,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
          filled: true,
          fillColor: Colors.white,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: PosTheme.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(
                color: HrmPageChrome.primaryNavy, width: 1.4),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }
}

/// Hộp bộ lọc THỐNG NHẤT: nền trắng, viền nhạt, bo 12, padding đều.
class HrmFilterBar extends StatelessWidget {
  const HrmFilterBar({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.all(12),
    this.margin = const EdgeInsets.fromLTRB(16, 8, 16, 8),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: margin,
      padding: padding,
      decoration: PosTheme.mobileCardDecoration(borderColor: const Color(0xFFEEEEF0)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  /// Mobile: xếp filter full-width (tránh cắt chữ trong 2 cột hẹp).
  static List<Widget> mobileStack(
    List<Widget> fields, {
    double gap = 8,
  }) {
    return [
      for (var i = 0; i < fields.length; i++) ...[
        if (i > 0) SizedBox(height: gap),
        fields[i],
      ],
    ];
  }
}
