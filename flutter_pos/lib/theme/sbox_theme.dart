import 'package:flutter/material.dart';

import '../utils/vietnamese_font.dart';
import 'sbox_tokens.dart';

/// Theme SBOX cho app POS (Flutter 3.22) — cùng quy chuẩn với app HRM.
abstract final class SboxTheme {
  static ThemeData light() {
    final tt = SboxType.textTheme(SboxColors.text, SboxColors.textSecondary, SboxColors.textMuted);
    const btnShape = RoundedRectangleBorder(borderRadius: SboxRadius.mdAll);
    const btnPad = EdgeInsets.symmetric(horizontal: 18, vertical: 10);
    const btnText = TextStyle(
      fontFamily: kVietnameseFontFamily,
      fontSize: SboxType.body,
      fontWeight: SboxType.semibold,
    );
    OutlineInputBorder inBorder(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: SboxRadius.mdAll,
          borderSide: BorderSide(color: c, width: w),
        );
    return ThemeData(
      useMaterial3: true,
      fontFamily: kVietnameseFontFamily,
      fontFamilyFallback: kVietnameseFontFallback,
      textTheme: tt,
      scaffoldBackgroundColor: SboxColors.page,
      primaryColor: SboxColors.primary,
      dividerColor: SboxColors.border,
      colorScheme: const ColorScheme.light(
        primary: SboxColors.primary,
        onPrimary: Colors.white,
        primaryContainer: SboxColors.brand50,
        onPrimaryContainer: SboxColors.brand900,
        secondary: SboxColors.brand500,
        onSecondary: Colors.white,
        secondaryContainer: SboxColors.brand50,
        onSecondaryContainer: SboxColors.brand900,
        tertiary: SboxColors.brand700,
        surface: SboxColors.surface,
        onSurface: SboxColors.text,
        onSurfaceVariant: SboxColors.textSecondary,
        surfaceTint: Colors.transparent,
        outline: SboxColors.border,
        outlineVariant: SboxColors.divider,
        error: SboxColors.danger,
        onError: Colors.white,
      ),
      // Thanh trên POS giữ nền xanh thương hiệu (nhận diện máy thu ngân).
      appBarTheme: AppBarTheme(
        backgroundColor: SboxColors.primary,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: tt.titleLarge?.copyWith(color: Colors.white),
      ),
      cardTheme: const CardTheme(
        color: SboxColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: SboxRadius.lgAll,
          side: BorderSide(color: SboxColors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SboxColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, SboxSize.control),
          padding: btnPad,
          shape: btnShape,
          textStyle: btnText,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SboxColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, SboxSize.control),
          padding: btnPad,
          shape: btnShape,
          elevation: 0,
          textStyle: btnText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SboxColors.slate700,
          backgroundColor: SboxColors.surface,
          side: const BorderSide(color: SboxColors.borderStrong),
          minimumSize: const Size(0, SboxSize.control),
          padding: btnPad,
          shape: btnShape,
          textStyle: btnText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: SboxColors.primary,
          shape: btnShape,
          textStyle: btnText,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SboxColors.white,
        isDense: true,
        border: inBorder(SboxColors.border),
        enabledBorder: inBorder(SboxColors.border),
        focusedBorder: inBorder(SboxColors.primary, 1.5),
        errorBorder: inBorder(SboxColors.danger),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        labelStyle: tt.bodyMedium?.copyWith(color: SboxColors.textSecondary),
        hintStyle: tt.bodyMedium?.copyWith(color: SboxColors.textMuted),
        floatingLabelStyle: tt.labelMedium?.copyWith(color: SboxColors.primary),
      ),
      dividerTheme: const DividerThemeData(color: SboxColors.divider, thickness: 1, space: 1),
      tabBarTheme: TabBarTheme(
        labelColor: SboxColors.primary,
        unselectedLabelColor: SboxColors.textSecondary,
        indicatorColor: SboxColors.primary,
        labelStyle: tt.labelLarge?.copyWith(fontWeight: SboxType.semibold),
        unselectedLabelStyle: tt.labelLarge,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: SboxColors.surface,
        selectedColor: SboxColors.brand50,
        side: const BorderSide(color: SboxColors.border),
        labelStyle: tt.labelMedium?.copyWith(color: SboxColors.text),
        shape: const RoundedRectangleBorder(borderRadius: SboxRadius.smAll),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: SboxColors.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: tt.titleLarge,
        shape: const RoundedRectangleBorder(borderRadius: SboxRadius.lgAll),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: SboxColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(SboxRadius.lg + 4)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: SboxColors.slate900,
        contentTextStyle: tt.bodyMedium?.copyWith(color: Colors.white),
        shape: const RoundedRectangleBorder(borderRadius: SboxRadius.mdAll),
        behavior: SnackBarBehavior.floating,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : SboxColors.white),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? SboxColors.primary : SboxColors.slate300),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? SboxColors.primary : Colors.transparent),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: const BorderSide(color: SboxColors.slate400, width: 1.5),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: SboxColors.primary,
        linearTrackColor: SboxColors.brand50,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: const BoxDecoration(color: SboxColors.slate800, borderRadius: SboxRadius.smAll),
        textStyle: tt.labelSmall?.copyWith(color: Colors.white),
      ),
    );
  }
}
