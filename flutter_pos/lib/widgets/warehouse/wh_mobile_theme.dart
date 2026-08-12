import 'package:flutter/material.dart';
import '../../l10n/app_tr.dart';

/// Design tokens — Material 3 + iOS (glass nhẹ, bo góc lớn, nhiều khoảng trắng).
abstract final class WhMobileTheme {
  // ── Palette (tối giản, ít màu) ──────────────────────────────────────────
  static const bg = Color(0xFFF2F2F7);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceGlass = Color(0xEFFFFFFF);
  static const primary = Color(0xFF007AFF);
  static const primaryMuted = Color(0x1A007AFF);
  static const accent = Color(0xFF34C759);
  static const danger = Color(0xFFFF3B30);
  static const warning = Color(0xFFFF9500);
  static const textPrimary = Color(0xFF1C1C1E);
  static const textSecondary = Color(0xFF8E8E93);
  static const textTertiary = Color(0xFFC7C7CC);
  static const divider = Color(0xFFE5E5EA);

  // ── Geometry ─────────────────────────────────────────────────────────────
  static const radiusSm = 12.0;
  static const radiusMd = 16.0;
  static const radiusLg = 20.0;
  static const radiusXl = 24.0;

  static const padH = 16.0;
  static const padV = 12.0;
  static const gap = 12.0;
  static const gapLg = 20.0;

  // ── Typography ───────────────────────────────────────────────────────────
  static const titleLarge = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: textPrimary,
    height: 1.2,
  );

  static const titleMedium = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    color: textPrimary,
  );

  static const body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: textPrimary,
    height: 1.35,
  );

  static const caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textSecondary,
    height: 1.3,
  );

  static const label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: textSecondary,
    letterSpacing: 0.2,
  );

  static const money = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    color: textPrimary,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // ── Decorations ──────────────────────────────────────────────────────────
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.black.withOpacity(0.03),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ];

  static BoxDecoration card({Color? color, double radius = radiusLg}) =>
      BoxDecoration(
        color: color ?? surface,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: softShadow,
      );

  static BoxDecoration glassCard({double radius = radiusLg}) => BoxDecoration(
        color: surfaceGlass,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Colors.white.withOpacity(0.6)),
        boxShadow: softShadow,
      );

  static InputDecoration fieldDecoration({
    String? label,
    String? hint,
    Widget? suffix,
    Widget? prefix,
  }) =>
      InputDecoration(
        labelText: trN(label),
        hintText: trN(hint),
        hintStyle: caption.copyWith(color: textTertiary),
        labelStyle: WhMobileTheme.label,
        filled: true,
        fillColor: bg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        suffixIcon: suffix,
        prefixIcon: prefix,
        isDense: true,
      );

  static ButtonStyle primaryButton({bool compact = false}) =>
      FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shadowColor: Colors.transparent,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 16 : 20,
          vertical: compact ? 12 : 16,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      );

  static ButtonStyle secondaryButton({bool compact = false}) =>
      OutlinedButton.styleFrom(
        foregroundColor: primary,
        backgroundColor: primaryMuted,
        side: BorderSide.none,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 16 : 20,
          vertical: compact ? 12 : 16,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      );

  static Color statusColor(String status) => switch (status) {
        'Completed' => accent,
        'Cancelled' => textTertiary,
        _ => warning,
      };

  static String statusLabel(String status, {String draftLabel = 'Nháp'}) =>
      switch (status) {
        'Completed' => 'Hoàn thành',
        'Cancelled' => 'Đã hủy',
        'InProgress' => draftLabel,
        _ => draftLabel,
      };
}
