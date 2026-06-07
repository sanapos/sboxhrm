import 'package:flutter/material.dart';

import '../screens/settings_hub_screen.dart';

/// Shared layout tokens and helpers for HRM settings sub-pages.
class HrmPageChrome {
  HrmPageChrome._();

  static const Color background = Color(0xFFFAFAFA);
  static const Color primaryNavy = Color(0xFF1E3A5F);
  static const Color textDark = Color(0xFF18181B);
  static const Color textMuted = Color(0xFF71717A);

  /// Hub sub-page is open — [main_layout] already shows back + title.
  static bool get isEmbedded => SettingsHubScreen.isEmbeddedSubPage;

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
        title,
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

  /// Toolbar shown under hub AppBar (actions only).
  static Widget embeddedActionBar({required List<Widget> actions}) {
    if (!isEmbedded || actions.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: actions,
      ),
    );
  }

  /// Stat cards: row on wide screens, horizontal scroll on narrow.
  static Widget horizontalStatCards({
    required List<Widget> cards,
    double minCardWidth = 132,
    double gap = 8,
  }) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
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

  /// Trên mobile luôn hiển thị bộ lọc (không ẩn sau nút filter).
  static bool inlineFiltersOnMobile(bool legacyToggle) => true;
}

/// Tiêu đề trang THỐNG NHẤT (hero gradient): title 20 đậm (mobile 18),
/// subtitle 13, icon badge, padding đều. Giữ màu nhấn qua [gradientColors].
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
    final isMobile = MediaQuery.sizeOf(context).width < 768;
    final colors = gradientColors ??
        const [HrmPageChrome.primaryNavy, Color(0xFF2A5298)];
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        isMobile ? 16 : 20,
        isMobile ? 14 : 16,
        isMobile ? 16 : 20,
        isMobile ? 14 : 16,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: isMobile ? 18 : 20,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
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
          hintText: hintText,
          isDense: true,
          prefixIcon: const Icon(Icons.search,
              size: 20, color: Color(0xFF71717A)),
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
            borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: HrmPageChrome.primaryNavy, width: 1.4),
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
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEF0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}
