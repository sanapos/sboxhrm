import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

pw.Font? _cachedRegular;
pw.Font? _cachedBold;

/// Font PDF hỗ trợ tiếng Việt — ưu tiên BeVietnamPro bundled, fallback Noto Sans.
Future<({pw.Font regular, pw.Font bold})> loadPosPdfFonts() async {
  if (_cachedRegular != null && _cachedBold != null) {
    return (regular: _cachedRegular!, bold: _cachedBold!);
  }

  try {
    final regData = await rootBundle.load('assets/fonts/BeVietnamPro-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/BeVietnamPro-Bold.ttf');
    _cachedRegular = pw.Font.ttf(regData);
    _cachedBold = pw.Font.ttf(boldData);
    return (regular: _cachedRegular!, bold: _cachedBold!);
  } catch (_) {
    final regular = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    _cachedRegular = regular;
    _cachedBold = bold;
    return (regular: regular, bold: bold);
  }
}
