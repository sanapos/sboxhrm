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
