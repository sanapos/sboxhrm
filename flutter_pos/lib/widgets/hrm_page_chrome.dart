import 'package:flutter/material.dart';

import '../screens/settings_hub_screen.dart';
import '../utils/navigation_notifier.dart';
import '../utils/responsive_helper.dart';
import 'hrm/hrm_settings_mobile_kit.dart';
import 'pos/pos_hub_scope.dart';
import 'pos/pos_theme.dart';
import '../l10n/app_tr.dart';

/// MainLayout publishes this on the same route as its title/back bar.
/// [Navigator.push] overlays are not descendants — they must draw their own chrome.
class HrmShellChrome extends InheritedWidget {
  const HrmShellChrome({
    super.key,
    required this.visible,
    required super.child,
  });

  final bool visible;

  static bool isVisible(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HrmShellChrome>()?.visible ??
      false;

  @override
  bool updateShouldNotify(HrmShellChrome oldWidget) =>
      visible != oldWidget.visible;
}

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

  /// Chip / badge brand — cùng xanh, độ đậm nhạt khác (không dùng hồng/cam/tím).
  static const Color chipDark = Color(0xFF003B80);
  static const Color chip = primaryNavy; // #0056B3
  static const Color chipMid = Color(0xFF1A6FD4);
  static const Color chipLight = Color(0xFF3B8CFF);
  static const Color chipSoft = Color(0xFF6BA3E8);
  static const Color chipMuted = Color(0xFF8BB4E8);
  static const Color chipBg = PosTheme.kiotBlueLight;

  static const List<Color> chipShades = [
    chipDark,
    chip,
    chipMid,
    chipLight,
    chipSoft,
    chipMuted,
    Color(0xFF004A9F),
    Color(0xFF2B7DE9),
  ];

  static Color chipShade(int index) =>
      chipShades[index.abs() % chipShades.length];

  /// Hub sub-page is open — [main_layout] already shows back + title.
  static bool get isEmbedded => SettingsHubScreen.isEmbeddedSubPage;

  /// True when this widget is the inner body of [SettingsHubScreen].
  /// Overlay [Navigator.push] (Máy in cloud…) không có ancestor hub.
  static bool isHubBody(BuildContext context) =>
      context.findAncestorWidgetOfExactType<SettingsHubScreen>() != null;

  /// Ẩn AppBar in-page vì hub / MainLayout đã có chrome.
  static bool hideOuterChrome(BuildContext context) => isHubBody(context);

  /// Hiện AppBar in-page khi không có thanh tiêu đề trên CÙNG route.
  static bool showInPageAppBar(BuildContext context) {
    final hubBody = isHubBody(context);
    if (PosHubScope.pushedSubPageOf(context) && !hubBody) return true;
    if (HrmShellChrome.isVisible(context)) return false;
    if (hubBody) return false;
    if (PosHubScope.of(context)) return false;
    return true;
  }

  /// Mobile drawer module: AppBar ngoài đã hiển thị tiêu đề trang.
  static bool get usesMainLayoutAppBar =>
      NavigationNotifier.mobileDrawerModuleActive.value;

  static bool shellHasVisibleChrome(BuildContext context) =>
      HrmShellChrome.isVisible(context);

  /// Route được push đè lên shell — phải tự vẽ tiêu đề + back.
  static bool isPushedOverShell(BuildContext context) =>
      Navigator.of(context).canPop() && !isHubBody(context);

  /// Ẩn tiêu đề in-page vì AppBar MainLayout / hub đã hiện.
  static bool hideInPageTitle(BuildContext context) =>
      !showInPageAppBar(context);

  /// AppBar for standalone / overlay; null when this widget is hub body.
  static PreferredSizeWidget? appBar({
    required String title,
    List<Widget>? actions,
    PreferredSizeWidget? bottom,
    BuildContext? context,
  }) {
    if (context != null && !showInPageAppBar(context)) return null;
    final canPop = context != null && Navigator.of(context).canPop();
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      leading: canPop
          ? IconButton(
              icon: const Icon(Icons.arrow_back, color: textDark),
              onPressed: () => Navigator.maybePop(context),
              tooltip: tr('Quay lại'),
            )
          : null,
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
    final inHub = context != null ? isHubBody(context) : isEmbedded;
    if (!inHub || actions.isEmpty) return const SizedBox.shrink();
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
        final n = cards.length;
        // Đủ chỗ → luôn 1 hàng chia đều (tránh 3+1 / 2+2 xuống dòng vô lý).
        final minRowWidth = n * 96.0 + gap * (n - 1);
        final oneRow = n <= 1 ||
            constraints.maxWidth >= minRowWidth ||
            constraints.maxWidth >= 520;
        if (oneRow) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < n; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  Expanded(child: cards[i]),
                ],
              ],
            ),
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: Responsive.horizontalScrollPadding,
          clipBehavior: Clip.none,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < n; i++) ...[
                  if (i > 0) SizedBox(width: gap),
                  SizedBox(width: minCardWidth, child: cards[i]),
                ],
              ],
            ),
          ),
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
            HrmPageChrome.hideInPageTitle(context);
        final showEscape = isMobile &&
            hideDuplicateTitle &&
            HrmPageChrome.isPushedOverShell(context);
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
                  if (showEscape)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.arrow_back, size: 22),
                      tooltip: tr('Quay lại'),
                      onPressed: () => Navigator.maybePop(context),
                    ),
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

  /// Mobile: 2 cột gọn, không xếp 4 dropdown dọc.
  static List<Widget> mobileGrid(
    List<Widget> fields, {
    double gap = 8,
  }) {
    final rows = <Widget>[];
    for (var i = 0; i < fields.length; i += 2) {
      if (i > 0) rows.add(SizedBox(height: gap));
      if (i + 1 < fields.length) {
        rows.add(Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: fields[i]),
            SizedBox(width: gap),
            Expanded(child: fields[i + 1]),
          ],
        ));
      } else {
        rows.add(fields[i]);
      }
    }
    return rows;
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
