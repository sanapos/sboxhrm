import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Hệ thống typography chuẩn cho tiếng Việt
/// Sử dụng Inter (hỗ trợ tốt dấu tiếng Việt, dễ đọc trên web/mobile)
/// Line-height tối ưu cho ký tự có dấu
class AppTypography {
  AppTypography._();

  static TextTheme _buildTextTheme(Color textColor, Color subtextColor) {
    final base = GoogleFonts.interTextTheme();
    return base.copyWith(
      // === DISPLAY: Tiêu đề lớn, dashboard header ===
      displayLarge: base.displayLarge!.copyWith(fontSize: 28, fontWeight: FontWeight.w700, height: 1.35, color: textColor, letterSpacing: -0.5),
      displayMedium: base.displayMedium!.copyWith(fontSize: 24, fontWeight: FontWeight.w700, height: 1.35, color: textColor, letterSpacing: -0.3),
      displaySmall: base.displaySmall!.copyWith(fontSize: 22, fontWeight: FontWeight.w600, height: 1.35, color: textColor),

      // === HEADLINE: Tiêu đề section, card header ===
      headlineLarge: base.headlineLarge!.copyWith(fontSize: 20, fontWeight: FontWeight.w700, height: 1.4, color: textColor),
      headlineMedium: base.headlineMedium!.copyWith(fontSize: 18, fontWeight: FontWeight.w600, height: 1.4, color: textColor),
      headlineSmall: base.headlineSmall!.copyWith(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4, color: textColor),

      // === TITLE: Tiêu đề item, AppBar, dialog title ===
      titleLarge: base.titleLarge!.copyWith(fontSize: 18, fontWeight: FontWeight.w600, height: 1.4, color: textColor),
      titleMedium: base.titleMedium!.copyWith(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4, color: textColor),
      titleSmall: base.titleSmall!.copyWith(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4, color: textColor),

      // === BODY: Nội dung chính ===
      bodyLarge: base.bodyLarge!.copyWith(fontSize: 15, fontWeight: FontWeight.w400, height: 1.5, color: textColor),
      bodyMedium: base.bodyMedium!.copyWith(fontSize: 14, fontWeight: FontWeight.w400, height: 1.5, color: textColor),
      bodySmall: base.bodySmall!.copyWith(fontSize: 13, fontWeight: FontWeight.w400, height: 1.5, color: subtextColor),

      // === LABEL: Nút, badge, form label, caption ===
      labelLarge: base.labelLarge!.copyWith(fontSize: 14, fontWeight: FontWeight.w500, height: 1.4, color: textColor),
      labelMedium: base.labelMedium!.copyWith(fontSize: 12, fontWeight: FontWeight.w500, height: 1.4, color: subtextColor),
      labelSmall: base.labelSmall!.copyWith(fontSize: 11, fontWeight: FontWeight.w500, height: 1.4, color: subtextColor, letterSpacing: 0.3),
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

  ThemeProvider() {
    _loadPreferences();
  }

  bool get isDarkMode => _isDarkMode;
  Locale get locale => _locale;
  String get languageLabel => _locale.languageCode == 'vi' ? 'Tiếng Việt' : 'English';

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('isDarkMode') ?? false;
    final langCode = prefs.getString('languageCode') ?? 'vi';
    _locale = Locale(langCode);
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', _isDarkMode);
  }

  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('languageCode', locale.languageCode);
  }

  // Màu chính của ứng dụng - Navy Dashboard palette
  static const Color primaryColor = Color(0xFF1E3A5F); // Navy (màu nền Tổng quan hệ thống)
  static const Color primaryColorLight = Color(0xFF2D5F8B); // Navy Light
  static const Color primaryColorDark = Color(0xFF0F2340); // Navy Dark
  static const Color accentColor = Color(0xFFEC4899); // Pink 500 (accent)

  ThemeData get lightTheme {
    final baseTheme = ThemeData.light();
    final textTheme = AppTypography.lightTextTheme;
    return baseTheme.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: const Color(0xFFFAFAFA),
      primaryColor: primaryColor,
      colorScheme: const ColorScheme.light(
        primary: primaryColor,
        secondary: Color(0xFFEC4899),
        tertiary: primaryColorDark,
        surface: Colors.white,
        surfaceTint: Colors.transparent,
        error: Color(0xFFEF4444),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onTertiary: Colors.white,
        onSurface: Color(0xFF18181B),
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.headlineLarge,
        iconTheme: const IconThemeData(color: Color(0xFF18181B)),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shadowColor: const Color(0x0A000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFEEEEF0)),
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
          foregroundColor: primaryColor,
          side: const BorderSide(color: primaryColor),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF71717A),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE4E4E7), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: textTheme.bodyMedium?.copyWith(color: const Color(0xFF71717A)),
        hintStyle: textTheme.bodyMedium?.copyWith(color: const Color(0xFFA1A1AA)),
        errorStyle: textTheme.labelSmall?.copyWith(color: const Color(0xFFEF4444)),
        floatingLabelStyle: textTheme.labelMedium?.copyWith(color: primaryColor),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE4E4E7),
        thickness: 1,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.white,
        selectedIconTheme: const IconThemeData(color: primaryColor),
        unselectedIconTheme: const IconThemeData(color: Color(0xFF71717A)),
        selectedLabelTextStyle: textTheme.labelLarge?.copyWith(color: primaryColor, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(color: const Color(0xFF71717A)),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Color(0xFFE0E7FF),
        elevation: 1,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: primaryColor,
        unselectedItemColor: Color(0xFF71717A),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primaryColor,
        unselectedLabelColor: const Color(0xFF71717A),
        indicatorColor: primaryColor,
        labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        unselectedLabelStyle: textTheme.labelLarge,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: primaryColor.withValues(alpha: 0.1),
        labelStyle: textTheme.labelMedium?.copyWith(color: const Color(0xFF18181B)),
        secondaryLabelStyle: textTheme.labelMedium?.copyWith(color: const Color(0xFF18181B)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: Color(0xFFE4E4E7)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF18181B),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
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
          return const Color(0xFFA1A1AA);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primaryColor.withValues(alpha: 0.5);
          }
          return const Color(0xFFE4E4E7);
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
          return const Color(0xFF71717A);
        }),
      ),
    );
  }

  ThemeData get darkTheme {
    const darkBg = Color(0xFF121212);
    const darkSurface = Color(0xFF1E1E1E);
    const darkCard = Color(0xFF2A2A2A);
    const darkBorder = Color(0xFF3A3A3A);
    const darkText = Color(0xFFE4E4E7);
    const darkSubtext = Color(0xFF9CA3AF);

    final baseDarkTheme = ThemeData.dark();
    final textTheme = AppTypography.darkTextTheme;
    return baseDarkTheme.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: darkBg,
      primaryColor: primaryColor,
      colorScheme: const ColorScheme.dark(
        primary: primaryColor,
        secondary: Color(0xFFEC4899),
        tertiary: Color(0xFF2D5F8B),
        surface: darkSurface,
        error: Color(0xFFEF4444),
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onTertiary: Colors.white,
        onSurface: darkText,
        onError: Colors.white,
      ),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: textTheme.bodyMedium?.copyWith(color: darkSubtext),
        hintStyle: textTheme.bodyMedium?.copyWith(color: darkSubtext),
        errorStyle: textTheme.labelSmall?.copyWith(color: const Color(0xFFEF4444)),
        floatingLabelStyle: textTheme.labelMedium?.copyWith(color: primaryColorLight),
      ),
      dividerTheme: const DividerThemeData(
        color: darkBorder,
        thickness: 1,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: darkSurface,
        selectedIconTheme: const IconThemeData(color: primaryColorLight),
        unselectedIconTheme: const IconThemeData(color: darkSubtext),
        selectedLabelTextStyle: textTheme.labelLarge?.copyWith(color: primaryColorLight, fontWeight: FontWeight.w600),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(color: darkSubtext),
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
