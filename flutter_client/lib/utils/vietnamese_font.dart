import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:google_fonts/google_fonts.dart';

/// Font chính (pubspec) + fallback. Trên web dùng [GoogleFonts.beVietnamPro] vì
/// CanvasKit đôi khi không ghép đúng family "BeVietnamPro" với TTF (gây chữ ?).
const String kVietnameseFontFamily = 'BeVietnamPro';
const List<String> kVietnameseFontFallback = [
  'Be Vietnam Pro',
  'Noto Sans',
  'Arial',
  'Segoe UI',
  'sans-serif',
];

bool _mobileFontsLoaded = false;

/// Preload Be Vietnam Pro trước khi [runApp] (web + mobile in ảnh).
Future<void> preloadVietnameseFonts() async {
  if (kIsWeb) {
    GoogleFonts.config.allowRuntimeFetching = true;
    await GoogleFonts.pendingFonts([
      GoogleFonts.beVietnamPro(),
      GoogleFonts.beVietnamPro(fontWeight: FontWeight.w500),
      GoogleFonts.beVietnamPro(fontWeight: FontWeight.w600),
      GoogleFonts.beVietnamPro(fontWeight: FontWeight.w700),
    ]);
    return;
  }
  if (_mobileFontsLoaded) return;
  final loader = FontLoader(kVietnameseFontFamily)
    ..addFont(rootBundle.load('assets/fonts/BeVietnamPro-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/BeVietnamPro-Bold.ttf'));
  await loader.load();
  _mobileFontsLoaded = true;
}

TextTheme vietnameseTextTheme(TextTheme base) {
  if (!kIsWeb) return base;
  return GoogleFonts.beVietnamProTextTheme(base);
}

TextStyle vietnameseTextStyle([TextStyle? base]) {
  final b = base ?? const TextStyle();
  if (kIsWeb) {
    return GoogleFonts.beVietnamPro(textStyle: b);
  }
  return b.copyWith(
    fontFamily: kVietnameseFontFamily,
    fontFamilyFallback: kVietnameseFontFallback,
  );
}

/// Style mặc định cho toàn app (dùng trong [MaterialApp.builder]).
TextStyle get kDefaultVietnameseTextStyle => vietnameseTextStyle(
      const TextStyle(
        fontSize: 14,
        color: Color(0xFF18181B),
      ),
    );

/// Theme scoped to screens that must render Vietnamese reliably on web (TabBar, DataTable).
ThemeData vietnameseThemeOverlay(BuildContext context) {
  final base = Theme.of(context);
  final textTheme = vietnameseTextTheme(base.textTheme);
  return base.copyWith(
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    tabBarTheme: base.tabBarTheme.copyWith(
      labelStyle: vietnameseTextStyle(
        base.tabBarTheme.labelStyle?.copyWith(fontWeight: FontWeight.w600),
      ),
      unselectedLabelStyle: vietnameseTextStyle(
        base.tabBarTheme.unselectedLabelStyle,
      ),
    ),
    dataTableTheme: DataTableThemeData(
      headingTextStyle: vietnameseTextStyle(const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 12,
      )),
      dataTextStyle: vietnameseTextStyle(const TextStyle(fontSize: 12)),
    ),
  );
}
