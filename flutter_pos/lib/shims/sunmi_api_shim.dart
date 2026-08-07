/// Shim API giống sunmi_printer_plus 4.x để compile trên Flutter 3.22.

class SunmiPrinter {
  static Future<bool> initPrinter() async => true;
  static Future<void> printText(String text, {dynamic style}) async {}
  static Future<void> printRow({required List<dynamic> cols}) async {}
  static Future<void> lineWrap(int n) async {}
  static Future<void> cutPaper() async {}
  static Future<String?> printEscPos(List<int> bytes) async => 'ok';
  static Future<void> printBarCode(
    String data, {
    dynamic style,
    int? size,
    dynamic textPos,
  }) async {}
  static Future<void> printBarcode(String data, {dynamic style}) async {}
  static Future<void> printQRCode(String data, {dynamic style, dynamic align}) async {}
  static Future<void> printImage(dynamic img, {dynamic align}) async {}
  static Future<void> setAlignment(dynamic align) async {}
  static Future<void> bold(bool v) async {}
}

class SunmiPrinterPlus {
  Future<bool> rebindPrinter() async => true;
  static Future<void> bindPrinterService() async {}
  static Future<void> unbindPrinterService() async {}
}

class SunmiConfig {
  static Future<String?> getPrinterSerial() async => null;
  static Future<dynamic> getPrinterVersion() async => null;
  static Future<dynamic> getStatus() async => null;
}

class SunmiDrawer {
  static Future<void> openDrawer() async {}
}

class SunmiTextStyle {
  const SunmiTextStyle({this.fontSize, this.bold, this.align});
  final int? fontSize;
  final bool? bold;
  final dynamic align;
}

class SunmiColumn {
  const SunmiColumn({required this.text, this.width, this.style});
  final String text;
  final int? width;
  final dynamic style;
}

class SunmiPrintAlign {
  static const LEFT = 'LEFT';
  static const CENTER = 'CENTER';
  static const RIGHT = 'RIGHT';
}

class SunmiBarcodeStyle {
  const SunmiBarcodeStyle({
    this.type,
    this.height,
    this.width,
    this.size,
    this.textPos,
    this.textPosition,
    this.align,
  });
  final dynamic type;
  final int? height;
  final int? width;
  final int? size;
  final dynamic textPos;
  final dynamic textPosition;
  final dynamic align;
}

class SunmiBarcodeType {
  static const CODE128 = 'CODE128';
  static const EAN13 = 'EAN13';
  static const EAN8 = 'EAN8';
  static const CODE39 = 'CODE39';
}

class SunmiBarcodeTextPos {
  static const NO_TEXT = 'NO_TEXT';
  static const TEXT_UNDER = 'TEXT_UNDER';
  static const TEXT_ABOVE = 'TEXT_ABOVE';
}
