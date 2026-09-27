import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_locale.dart';
import '../l10n/app_tr.dart';
import '../theme/sbox_tokens.dart';
import '../utils/vietnamese_font.dart';

import '../utils/play_system_ui.dart';

/// Typography chuẩn tiếng Việt (Be Vietnam Pro) — lấy thang cỡ chữ từ [SboxType].
class AppTypography {
  AppTypography._();

  static TextTheme get lightTextTheme =>
      SboxType.textTheme(SboxColors.text, SboxColors.textSecondary, SboxColors.textMuted);

  static TextTheme get darkTextTheme =>
      SboxType.textTheme(SboxColors.darkText, SboxColors.darkTextSecondary, SboxColors.darkTextSecondary);
}

class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = false;
  Locale _locale = const Locale('vi');

  ThemeProvider() {
    _loadPreferences();
  }

  /// Chế độ tối chưa sẵn sàng: nhiều màn còn màu sáng cố định (SboxColors const).
  /// Bật lại khi các màn đã chuyển sang màu theo Theme.
  static const bool darkModeAvailable = false;

  bool get isDarkMode => darkModeAvailable && _isDarkMode;
  Locale get locale => _locale;
  String get languageLabel =>
      _locale.languageCode == 'vi' ? 'Tiếng Việt' : 'English';

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('isDarkMode') ?? false;
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

  Future<void> setLocale(Locale locale) async {
    _locale = locale;
    AppLocale.setLanguageCode(locale.languageCode);
    trResetCache();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('languageCode', locale.languageCode);
  }

  /// Màu chính (nút, liên kết, tab chọn) — xanh thương hiệu tông đậm đủ tương phản.
  static const Color primaryColor = SboxColors.primary;
  /// Màu thương hiệu gốc #158DC0 (logo, điểm nhấn).
  static const Color primaryColorLight = SboxColors.brand500;
  static const Color primaryColorDark = SboxColors.brand700;
  static const Color accentColor = primaryColorLight;

  ThemeData get lightTheme => _build(
        brightness: Brightness.light,
        page: SboxColors.page,
        surface: SboxColors.surface,
        surfaceMuted: SboxColors.surfaceMuted,
        border: SboxColors.border,
        text: SboxColors.text,
        textSecondary: SboxColors.textSecondary,
        textMuted: SboxColors.textMuted,
        primary: SboxColors.primary,
        primarySoft: SboxColors.primarySoft,
        textTheme: AppTypography.lightTextTheme,
      );

  ThemeData get darkTheme => _build(
        brightness: Brightness.dark,
        page: SboxColors.darkPage,
        surface: SboxColors.darkSurface,
        surfaceMuted: SboxColors.darkSurfaceRaised,
        border: SboxColors.darkBorder,
        text: SboxColors.darkText,
        textSecondary: SboxColors.darkTextSecondary,
        textMuted: SboxColors.darkTextSecondary,
        primary: SboxColors.brand400,
        primarySoft: const Color(0xFF0E3448),
        textTheme: AppTypography.darkTextTheme,
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color page,
    required Color surface,
    required Color surfaceMuted,
    required Color border,
    required Color text,
    required Color textSecondary,
    required Color textMuted,
    required Color primary,
    required Color primarySoft,
    required TextTheme textTheme,
  }) {
    final dark = brightness == Brightness.dark;
    var tt = textTheme;
    if (kIsWeb) tt = vietnameseTextTheme(tt);
    final base = ThemeData(
      fontFamily: kVietnameseFontFamily,
      fontFamilyFallback: kVietnameseFontFallback,
      brightness: brightness,
      useMaterial3: true,
    );
    const btnShape = RoundedRectangleBorder(borderRadius: SboxRadius.mdAll);
    const btnPad = EdgeInsets.symmetric(horizontal: 18, vertical: 10);
    final btnText = TextStyle(
      fontFamily: kVietnameseFontFamily,
      fontSize: SboxType.body,
      fontWeight: SboxType.semibold,
    );
    OutlineInputBorder inBorder(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: SboxRadius.mdAll,
          borderSide: BorderSide(color: c, width: w),
        );

    return base.copyWith(
      textTheme: tt,
      scaffoldBackgroundColor: page,
      canvasColor: surface,
      primaryColor: primary,
      dividerColor: border,
      colorScheme: (dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(
        primary: primary,
        onPrimary: Colors.white,
        primaryContainer: primarySoft,
        onPrimaryContainer: dark ? SboxColors.brand100 : SboxColors.brand900,
        secondary: SboxColors.brand500,
        onSecondary: Colors.white,
        secondaryContainer: primarySoft,
        onSecondaryContainer: dark ? SboxColors.brand100 : SboxColors.brand900,
        tertiary: SboxColors.brand700,
        onTertiary: Colors.white,
        surface: surface,
        onSurface: text,
        onSurfaceVariant: textSecondary,
        surfaceContainerLowest: surface,
        surfaceContainerLow: surfaceMuted,
        surfaceContainer: surfaceMuted,
        surfaceContainerHigh: surfaceMuted,
        surfaceContainerHighest: dark ? SboxColors.darkSurfaceRaised : SboxColors.slate100,
        surfaceTint: Colors.transparent,
        outline: border,
        outlineVariant: dark ? SboxColors.darkBorder : SboxColors.divider,
        error: SboxColors.danger,
        onError: Colors.white,
        errorContainer: SboxColors.dangerSoft,
        onErrorContainer: SboxColors.dangerText,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: text,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: tt.titleLarge,
        iconTheme: IconThemeData(color: text),
        shape: Border(bottom: BorderSide(color: border)),
        systemOverlayStyle: kPlayOverlayOnDarkBg,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: SboxRadius.lgAll,
          side: BorderSide(color: border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, SboxSize.control),
          padding: btnPad,
          shape: btnShape,
          elevation: 0,
          textStyle: btnText,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
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
          foregroundColor: dark ? text : SboxColors.slate700,
          backgroundColor: surface,
          side: BorderSide(color: dark ? border : SboxColors.borderStrong),
          minimumSize: const Size(0, SboxSize.control),
          padding: btnPad,
          shape: btnShape,
          textStyle: btnText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(0, SboxSize.control),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: btnShape,
          textStyle: btnText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: textSecondary,
          shape: btnShape,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? SboxColors.darkSurfaceRaised : SboxColors.white,
        isDense: true,
        border: inBorder(border),
        enabledBorder: inBorder(border),
        focusedBorder: inBorder(primary, 1.5),
        errorBorder: inBorder(SboxColors.danger),
        focusedErrorBorder: inBorder(SboxColors.danger, 1.5),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        labelStyle: tt.bodyMedium?.copyWith(color: textSecondary),
        hintStyle: tt.bodyMedium?.copyWith(color: textMuted),
        errorStyle: tt.labelSmall?.copyWith(color: SboxColors.danger),
        floatingLabelStyle: tt.labelMedium?.copyWith(color: primary),
        prefixIconColor: textMuted,
        suffixIconColor: textMuted,
      ),
      dividerTheme: DividerThemeData(
        color: dark ? SboxColors.darkBorder : SboxColors.divider,
        thickness: 1,
        space: 1,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: primarySoft,
        selectedIconTheme: IconThemeData(color: primary),
        unselectedIconTheme: IconThemeData(color: textMuted),
        selectedLabelTextStyle: tt.labelMedium?.copyWith(color: primary, fontWeight: SboxType.semibold),
        unselectedLabelTextStyle: tt.labelMedium?.copyWith(color: textMuted),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primarySoft,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => tt.labelSmall?.copyWith(
              color: s.contains(WidgetState.selected) ? primary : textMuted,
              fontWeight: s.contains(WidgetState.selected) ? SboxType.semibold : SboxType.medium,
            )),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected) ? primary : textMuted,
            )),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primary,
        unselectedItemColor: textMuted,
        selectedLabelStyle: const TextStyle(fontFamily: kVietnameseFontFamily, fontSize: SboxType.caption, fontWeight: SboxType.semibold),
        unselectedLabelStyle: const TextStyle(fontFamily: kVietnameseFontFamily, fontSize: SboxType.caption, fontWeight: SboxType.medium),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: textSecondary,
        indicatorColor: primary,
        dividerColor: border,
        labelStyle: tt.labelLarge?.copyWith(fontWeight: SboxType.semibold),
        unselectedLabelStyle: tt.labelLarge,
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(dark ? SboxColors.darkSurfaceRaised : SboxColors.slate50),
        headingRowHeight: SboxSize.tableHeader,
        dataRowMinHeight: SboxSize.tableRowDense,
        dataRowMaxHeight: SboxSize.tableRow + 8,
        headingTextStyle: tt.labelMedium?.copyWith(color: textSecondary, fontWeight: SboxType.semibold),
        dataTextStyle: tt.bodyMedium?.copyWith(fontSize: SboxType.small),
        dividerThickness: 1,
        horizontalMargin: SboxSpace.lg,
        columnSpacing: SboxSpace.xl,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: primarySoft,
        checkmarkColor: primary,
        labelStyle: tt.labelMedium?.copyWith(color: text),
        secondaryLabelStyle: tt.labelMedium?.copyWith(color: primary),
        side: BorderSide(color: border),
        shape: const RoundedRectangleBorder(borderRadius: SboxRadius.smAll),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? primarySoft : surface),
          foregroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? (dark ? SboxColors.brand100 : SboxColors.brand800) : textSecondary),
          side: WidgetStatePropertyAll(BorderSide(color: border)),
          shape: const WidgetStatePropertyAll(btnShape),
          textStyle: WidgetStatePropertyAll(btnText.copyWith(fontSize: SboxType.small)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: SboxColors.slate900,
        contentTextStyle: tt.bodyMedium?.copyWith(color: Colors.white),
        shape: const RoundedRectangleBorder(borderRadius: SboxRadius.mdAll),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: tt.titleLarge,
        contentTextStyle: tt.bodyMedium,
        shape: const RoundedRectangleBorder(borderRadius: SboxRadius.lgAll),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(SboxRadius.lg + 4)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        textStyle: tt.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: SboxRadius.mdAll, side: BorderSide(color: border)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: const BoxDecoration(color: SboxColors.slate800, borderRadius: SboxRadius.smAll),
        textStyle: tt.labelSmall?.copyWith(color: Colors.white),
        waitDuration: const Duration(milliseconds: 400),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textSecondary,
        titleTextStyle: tt.bodyMedium?.copyWith(fontWeight: SboxType.medium),
        subtitleTextStyle: tt.bodySmall,
        shape: const RoundedRectangleBorder(borderRadius: SboxRadius.mdAll),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: const RoundedRectangleBorder(borderRadius: SboxRadius.lgAll),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: primarySoft,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : (dark ? textSecondary : SboxColors.white)),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primary : (dark ? border : SboxColors.slate300)),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primary : Colors.transparent),
        checkColor: const WidgetStatePropertyAll(Colors.white),
        side: BorderSide(color: dark ? textSecondary : SboxColors.slate400, width: 1.5),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(4))),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? primary : textMuted),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll((dark ? SboxColors.slate500 : SboxColors.slate400).withValues(alpha: 0.6)),
        radius: const Radius.circular(8),
        thickness: const WidgetStatePropertyAll(6),
      ),
    );
  }
}
