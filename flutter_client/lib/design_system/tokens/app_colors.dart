import 'package:flutter/material.dart';

/// Brand palette chuẩn **KiotViet** (xanh lá + xanh dương + xám).
///
/// Không dùng pink/violet/orange làm brand — chỉ semantic status.
abstract final class AppColors {
  // --- Brand KiotViet ---
  /// Xanh lá chủ đạo (nút chính, sidebar selected, CTA).
  static const Color primary = Color(0xFF00B63E);
  static const Color primaryLight = Color(0xFF2DD15C);
  static const Color primaryDark = Color(0xFF009632);
  static const Color primaryMuted = Color(0xFFE8F8ED);

  /// Xanh dương hành động / link / highlight (Kiot blue).
  static const Color secondary = Color(0xFF0070F4);
  static const Color secondaryMuted = Color(0xFFE8F4FD);

  /// Alias marketing / legacy.
  static const Color marketingBlue = secondary;
  static const Color kiotGreen = primary;
  static const Color kiotBlue = secondary;

  // --- Semantic (status only — không dùng làm brand module) ---
  static const Color accent = secondary; // không còn pink
  static const Color success = Color(0xFF00B63E);
  static const Color warning = Color(0xFFF5A623);
  static const Color danger = Color(0xFFE53935);

  /// Info = Kiot blue shade ladder.
  static const MaterialColor info = MaterialColor(
    0xFF0070F4,
    <int, Color>{
      50: Color(0xFFE8F4FD),
      100: Color(0xFFCCE4FC),
      200: Color(0xFF99C9F9),
      300: Color(0xFF66AEF6),
      400: Color(0xFF3393F5),
      500: Color(0xFF0070F4),
      600: Color(0xFF005CC9),
      700: Color(0xFF00479E),
      800: Color(0xFF003372),
      900: Color(0xFF001E47),
    },
  );

  // --- Surfaces (Kiot gray) ---
  static const Color scaffold = Color(0xFFF4F6F8);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFEEF1F4);
  static const Color border = Color(0xFFE0E4E8);
  static const Color borderSubtle = Color(0xFFE8ECF0);
  static const Color textPrimary = Color(0xFF1A1D21);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);

  // --- Dark ---
  static const Color scaffoldDark = Color(0xFF12151A);
  static const Color surfaceDark = Color(0xFF1A1F26);
  static const Color surfaceMutedDark = Color(0xFF242A33);
  static const Color borderDark = Color(0xFF2E3540);
  static const Color textPrimaryDark = Color(0xFFE8EAED);
  static const Color textSecondaryDark = Color(0xFF9CA3AF);

  /// Biểu đồ / nhóm module — chỉ xanh lá + xanh dương + xám.
  static const List<Color> chart = [
    primary,
    secondary,
    primaryDark,
    Color(0xFF4DA3FF),
    Color(0xFF34C759),
    Color(0xFF6B7280),
    Color(0xFF009632),
    Color(0xFF005CC9),
  ];

  /// Màu icon nhóm Home/Settings — xoay trong palette Kiot (không cầu vồng).
  static Color moduleTone(int index) => chart[index % chart.length];

  static ColorScheme lightScheme() => const ColorScheme.light(
        primary: primary,
        onPrimary: Colors.white,
        primaryContainer: primaryMuted,
        onPrimaryContainer: primaryDark,
        secondary: secondary,
        onSecondary: Colors.white,
        secondaryContainer: secondaryMuted,
        onSecondaryContainer: Color(0xFF003372),
        tertiary: primaryDark,
        onTertiary: Colors.white,
        error: danger,
        onError: Colors.white,
        surface: surface,
        onSurface: textPrimary,
        onSurfaceVariant: textSecondary,
        outline: border,
        outlineVariant: borderSubtle,
        surfaceTint: Colors.transparent,
      );

  static ColorScheme darkScheme() => const ColorScheme.dark(
        primary: primaryLight,
        onPrimary: Colors.white,
        primaryContainer: primaryDark,
        onPrimaryContainer: primaryMuted,
        secondary: secondary,
        onSecondary: Colors.white,
        tertiary: primaryLight,
        onTertiary: Colors.white,
        error: danger,
        onError: Colors.white,
        surface: surfaceDark,
        onSurface: textPrimaryDark,
        onSurfaceVariant: textSecondaryDark,
        outline: borderDark,
        outlineVariant: Color(0xFF3F4652),
        surfaceTint: Colors.transparent,
      );

  static ColorScheme of(BuildContext context) =>
      Theme.of(context).colorScheme;
}
