import 'package:flutter/material.dart';

/// Single source of brand + semantic colors for SBOX (HRM + shared chrome).
///
/// POS domain accents live in [PosTheme] but should reuse these neutrals /
/// radii via [AppSpace] / [AppRadius]. Prefer `Theme.of(context).colorScheme`
/// or `AppColors.of(context)` in widgets.
abstract final class AppColors {
  // --- Brand (HRM enterprise navy) ---
  static const Color primary = Color(0xFF1E3A5F);
  static const Color primaryLight = Color(0xFF2D5F8B);
  static const Color primaryDark = Color(0xFF0F2340);

  /// Legacy marketing blue — aliased to [primary] for brand unification.
  static const Color marketingBlue = primary;

  // --- Semantic ---
  static const Color secondary = Color(0xFF0EA5E9); // Sky — actions / links
  static const Color accent = Color(0xFFEC4899); // Decorative only
  static const Color success = Color(0xFF059669);
  static const Color warning = Color(0xFFD97706);
  static const Color danger = Color(0xFFEF4444);

  /// Info blue with Material shade ladder (replaces Colors.blue.*).
  static const MaterialColor info = MaterialColor(
    0xFF2563EB,
    <int, Color>{
      50: Color(0xFFEFF6FF),
      100: Color(0xFFDBEAFE),
      200: Color(0xFFBFDBFE),
      300: Color(0xFF93C5FD),
      400: Color(0xFF60A5FA),
      500: Color(0xFF3B82F6),
      600: Color(0xFF2563EB),
      700: Color(0xFF1D4ED8),
      800: Color(0xFF1E40AF),
      900: Color(0xFF1E3A8A),
    },
  );

  // --- Surfaces (light) ---
  static const Color scaffold = Color(0xFFFAFAFA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF4F4F5);
  static const Color border = Color(0xFFE4E4E7);
  static const Color borderSubtle = Color(0xFFEEEEF0);
  static const Color textPrimary = Color(0xFF18181B);
  static const Color textSecondary = Color(0xFF71717A);
  static const Color textTertiary = Color(0xFFA1A1AA);

  // --- Surfaces (dark) ---
  static const Color scaffoldDark = Color(0xFF0F1419);
  static const Color surfaceDark = Color(0xFF1A1F26);
  static const Color surfaceMutedDark = Color(0xFF242A33);
  static const Color borderDark = Color(0xFF2E3540);
  static const Color textPrimaryDark = Color(0xFFE4E4E7);
  static const Color textSecondaryDark = Color(0xFF9CA3AF);

  // --- Chart palette (dashboard) ---
  static const List<Color> chart = [
    primary,
    info,
    success,
    Color(0xFF7C3AED),
    warning,
    secondary,
    accent,
    Color(0xFF64748B),
  ];

  static ColorScheme lightScheme() => const ColorScheme.light(
        primary: primary,
        onPrimary: Colors.white,
        primaryContainer: Color(0xFFD6E4F5),
        onPrimaryContainer: primaryDark,
        secondary: secondary,
        onSecondary: Colors.white,
        secondaryContainer: Color(0xFFE0F2FE),
        onSecondaryContainer: Color(0xFF0C4A6E),
        tertiary: accent,
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
        onPrimaryContainer: Color(0xFFD6E4F5),
        secondary: secondary,
        onSecondary: Colors.white,
        tertiary: accent,
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
