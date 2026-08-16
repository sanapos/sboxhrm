import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Font chính (pubspec assets). Không fallback Arial/sans — Android 6 (T1)
/// hay nhảy sang font CJK hệ thống, dấu tiếng Việt bị lỗi cả app.
const String kVietnameseFontFamily = 'BeVietnamPro';
const List<String> kVietnameseFontFallback = [
  'Be Vietnam Pro',
];

bool _mobileFontsLoaded = false;

/// Preload fonts. Mobile: fonts đã khai báo trong pubspec.yaml.
Future<void> preloadVietnameseFonts() async {
  if (!kIsWeb) {
    if (_mobileFontsLoaded) return;
    _mobileFontsLoaded = true;
  }
}

TextTheme vietnameseTextTheme(TextTheme base) => base.apply(
      fontFamily: kVietnameseFontFamily,
      fontFamilyFallback: kVietnameseFontFallback,
    );

TextStyle vietnameseTextStyle([TextStyle? base]) {
  final b = base ?? const TextStyle();
  return b.copyWith(
    fontFamily: kVietnameseFontFamily,
    fontFamilyFallback: kVietnameseFontFallback,
  );
}

TextStyle get kDefaultVietnameseTextStyle => vietnameseTextStyle(
      const TextStyle(
        fontSize: 14,
        color: Color(0xFF18181B),
      ),
    );

ThemeData applyVietnameseFonts(ThemeData base) {
  return base.copyWith(
    textTheme: vietnameseTextTheme(base.textTheme),
    primaryTextTheme: vietnameseTextTheme(base.primaryTextTheme),
    tabBarTheme: base.tabBarTheme.copyWith(
      labelStyle: vietnameseTextStyle(
        base.tabBarTheme.labelStyle?.copyWith(fontWeight: FontWeight.w600),
      ),
      unselectedLabelStyle: vietnameseTextStyle(
        base.tabBarTheme.unselectedLabelStyle,
      ),
    ),
  );
}

ThemeData vietnameseThemeOverlay(BuildContext context) {
  final base = Theme.of(context);
  return applyVietnameseFonts(base).copyWith(
    dataTableTheme: DataTableThemeData(
      headingTextStyle: vietnameseTextStyle(const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 12,
      )),
      dataTextStyle: vietnameseTextStyle(const TextStyle(fontSize: 12)),
    ),
  );
}
