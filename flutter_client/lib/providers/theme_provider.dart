import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../design_system/design_system.dart';
import '../l10n/app_locale.dart';
import '../l10n/app_tr.dart';
import '../utils/vietnamese_font.dart';

/// Hệ thống typography chuẩn cho tiếng Việt
/// Sử dụng Be Vietnam Pro – font được thiết kế riêng cho tiếng Việt
/// (Google Fonts + Lâm Bảo), dấu thanh đẹp, được dùng phổ biến trên
/// các app/website tại Việt Nam.
class AppTypography {
  AppTypography._();

  static TextTheme _buildTextTheme(Color textColor, Color subtextColor) {
    const f = kVietnameseFontFamily;
    const fb = kVietnameseFontFallback;
    TextStyle s(TextStyle style) => style.copyWith(
          fontFamily: f,
          fontFamilyFallback: fb,
        );
    return TextTheme(
      // === DISPLAY: Tiêu đề lớn, dashboard header ===
      displayLarge: s(TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          height: 1.35,
          color: textColor,
          letterSpacing: -0.5)),
      displayMedium: s(TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          height: 1.35,
          color: textColor,
          letterSpacing: -0.3)),
      displaySmall: s(TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          height: 1.35,
          color: textColor)),

      // === HEADLINE: Tiêu đề section, card header ===
      headlineLarge: s(TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          height: 1.4,
          color: textColor)),
      headlineMedium: s(TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: 1.4,
          color: textColor)),
      headlineSmall: s(TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.4,
          color: textColor)),

      // === TITLE: Tiêu đề item, AppBar, dialog title ===
      titleLarge: s(TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          height: 1.4,
          color: textColor)),
      titleMedium: s(TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          height: 1.4,
          color: textColor)),
      titleSmall: s(TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.4,
          color: textColor)),

      // === BODY: Nội dung chính ===
      bodyLarge: s(TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          height: 1.5,
          color: textColor)),
      bodyMedium: s(TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.5,
          color: textColor)),
      bodySmall: s(TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          height: 1.5,
          color: subtextColor)),

      // === LABEL: Nút, badge, form label, caption ===
      labelLarge: s(TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.4,
          color: textColor)),
      labelMedium: s(TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 1.4,
          color: subtextColor)),
      labelSmall: s(TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          height: 1.4,
          color: subtextColor,
          letterSpacing: 0.3)),
    );
  }

  static TextTheme get lightTextTheme => _buildTextTheme(
        const Color(0xFF18181B),
        const Color(0xFF71717A),
      );

  static TextTheme get darkTextTheme => _buildTextTheme(
        const Color(0xFFE4E4E7),
        const Color(0xFF9CA3AF),
      );
}

class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = false;
  Locale _locale = const Locale('vi');
  bool _compactDensity = false;

  ThemeProvider() {
    _loadPreferences();
  }

  bool get isDarkMode => _isDarkMode;
  bool get compactDensity => _compactDensity;
  Locale get locale => _locale;
  String get languageLabel =>
      _locale.languageCode == 'vi' ? 'Tiếng Việt' : 'English';

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    _compactDensity = prefs.getBool('compactDensity') ?? false;
    final langCode = prefs.getString('languageCode') ?? 'vi';
    _locale = Locale(langCode);
    AppLocale.setLanguageCode(langCode);
    trResetCache();
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', _isDarkMode);
  }

  Future<void> setCompactDensity(bool value) async {
    if (_compactDensity == value) return;
    _compactDensity = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('compactDensity', value);
  }

  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    AppLocale.setLanguageCode(locale.languageCode);
    trResetCache();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('languageCode', locale.languageCode);
  }

  // Alias → design system tokens (backward compatible).
  static const Color primaryColor = AppColors.primary;
  static const Color primaryColorLight = AppColors.primaryLight;
  static const Color primaryColorDark = AppColors.primaryDark;
  static const Color accentColor = AppColors.accent;

  AppDesignTokens get _tokens =>
      _compactDensity ? AppDesignTokens.compact : AppDesignTokens.comfortable;

  ThemeData get lightTheme {
    final baseTheme = ThemeData(
      useMaterial3: true,
      fontFamily: kVietnameseFontFamily,
      fontFamilyFallback: kVietnameseFontFallback,
      colorScheme: AppColors.lightScheme(),
      visualDensity: _tokens.density,
    );
    var textTheme = AppTypography.lightTextTheme;
    if (kIsWeb) {
      textTheme = vietnameseTextTheme(textTheme);
    }
    return baseTheme.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: AppColors.scaffold,
      primaryColor: primaryColor,
      extensions: <ThemeExtension<dynamic>>[_tokens],
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineLarge,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shadowColor: const Color(0x0A000000),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.card,
          side: const BorderSide(color: AppColors.borderSubtle),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.control),
          elevation: 1,
          shadowColor: primaryColor.withValues(alpha: 0.3),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.control),
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColor,
          side: const BorderSide(color: primaryColor),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.control),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.control),
          textStyle: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.scaffold,
        border: OutlineInputBorder(
          borderRadius: AppRadius.control,
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.control,
          borderSide: const BorderSide(color: AppColors.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.control,
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.control,
          borderSide: const BorderSide(color: AppColors.danger, width: 1),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle:
            textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        hintStyle:
            textTheme.bodyMedium?.copyWith(color: AppColors.textTertiary),
        errorStyle: textTheme.labelSmall?.copyWith(color: AppColors.danger),
        floatingLabelStyle:
            textTheme.labelMedium?.copyWith(color: primaryColor),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.surface,
        selectedIconTheme: const IconThemeData(color: primaryColor),
        unselectedIconTheme:
            const IconThemeData(color: AppColors.textSecondary),
        selectedLabelTextStyle: textTheme.labelLarge
            ?.copyWith(color: primaryColor, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle:
            textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryColor.withValues(alpha: 0.12),
        elevation: 1,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: primaryColor,
        unselectedItemColor: AppColors.textSecondary,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primaryColor,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: primaryColor,
        labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: textTheme.labelLarge,
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
        dataTextStyle: textTheme.bodySmall,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: primaryColor.withValues(alpha: 0.1),
        labelStyle:
            textTheme.labelMedium?.copyWith(color: AppColors.textPrimary),
        secondaryLabelStyle:
            textTheme.labelMedium?.copyWith(color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.control),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.dialog),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xxl)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryColor,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primaryColor;
          }
          return AppColors.textTertiary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primaryColor.withValues(alpha: 0.5);
          }
          return AppColors.border;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primaryColor;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primaryColor;
          }
          return AppColors.textSecondary;
        }),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
      focusColor: primaryColor.withValues(alpha: 0.18),
    );
  }

  ThemeData get darkTheme {
    final baseDarkTheme = ThemeData(
      useMaterial3: true,
      fontFamily: kVietnameseFontFamily,
      fontFamilyFallback: kVietnameseFontFallback,
      brightness: Brightness.dark,
      colorScheme: AppColors.darkScheme(),
      visualDensity: _tokens.density,
    );
    var textTheme = AppTypography.darkTextTheme;
    if (kIsWeb) {
      textTheme = vietnameseTextTheme(textTheme);
    }
    const darkBg = AppColors.scaffoldDark;
    const darkSurface = AppColors.surfaceDark;
    const darkCard = AppColors.surfaceMutedDark;
    const darkBorder = AppColors.borderDark;
    const darkText = AppColors.textPrimaryDark;
    const darkSubtext = AppColors.textSecondaryDark;

    return baseDarkTheme.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: darkBg,
      primaryColor: primaryColor,
      extensions: <ThemeExtension<dynamic>>[_tokens],
      colorScheme: AppColors.darkScheme(),
      appBarTheme: AppBarTheme(
        backgroundColor: darkSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineLarge,
        iconTheme: const IconThemeData(color: darkText),
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shadowColor: Colors.black26,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: darkBorder),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 1,
          shadowColor: primaryColor.withValues(alpha: 0.3),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryColorLight,
          side: const BorderSide(color: primaryColorLight),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: darkSubtext,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: darkBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: textTheme.bodyMedium?.copyWith(color: darkSubtext),
        hintStyle: textTheme.bodyMedium?.copyWith(color: darkSubtext),
        errorStyle:
            textTheme.labelSmall?.copyWith(color: const Color(0xFFEF4444)),
        floatingLabelStyle:
            textTheme.labelMedium?.copyWith(color: primaryColorLight),
      ),
      dividerTheme: const DividerThemeData(
        color: darkBorder,
        thickness: 1,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: darkSurface,
        selectedIconTheme: const IconThemeData(color: primaryColorLight),
        unselectedIconTheme: const IconThemeData(color: darkSubtext),
        selectedLabelTextStyle: textTheme.labelLarge
            ?.copyWith(color: primaryColorLight, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle:
            textTheme.labelMedium?.copyWith(color: darkSubtext),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: darkSurface,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkSurface,
        selectedItemColor: primaryColorLight,
        unselectedItemColor: darkSubtext,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primaryColorLight,
        unselectedLabelColor: darkSubtext,
        indicatorColor: primaryColor,
        labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: textTheme.labelLarge,
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
        dataTextStyle: textTheme.bodySmall,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: darkCard,
        selectedColor: primaryColor.withValues(alpha: 0.2),
        labelStyle: textTheme.labelMedium?.copyWith(color: darkText),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(color: darkText),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: darkBorder),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: darkCard,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: darkText),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primaryColor,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primaryColor;
          }
          return darkSubtext;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primaryColor.withValues(alpha: 0.5);
          }
          return darkBorder;
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primaryColor;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primaryColor;
          }
          return darkSubtext;
        }),
      ),
    );
  }
}
