/// Bridge thật tới [sunmi_printer_plus] 2.x (AIDL woyou) — giữ API kiểu 4.x
/// mà POS đang gọi. Shim cũ là no-op nên T1 «nhận máy in» nhưng không in.
// ignore_for_file: constant_identifier_names
library;

import 'package:flutter/foundation.dart';
import 'package:sunmi_printer_plus/column_maker.dart';
import 'package:sunmi_printer_plus/enums.dart' as sp;
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart' as sp;
import 'package:sunmi_printer_plus/sunmi_style.dart' as sp_style;

class SunmiPrintAlign {
  static const LEFT = sp.SunmiPrintAlign.LEFT;
  static const CENTER = sp.SunmiPrintAlign.CENTER;
  static const RIGHT = sp.SunmiPrintAlign.RIGHT;
}

class SunmiBarcodeType {
  static const CODE128 = sp.SunmiBarcodeType.CODE128;
  static const EAN13 = sp.SunmiBarcodeType.JAN13;
  static const EAN8 = sp.SunmiBarcodeType.JAN8;
  static const CODE39 = sp.SunmiBarcodeType.CODE39;
}

class SunmiBarcodeTextPos {
  static const NO_TEXT = sp.SunmiBarcodeTextPos.NO_TEXT;
  static const TEXT_UNDER = sp.SunmiBarcodeTextPos.TEXT_UNDER;
  static const TEXT_ABOVE = sp.SunmiBarcodeTextPos.TEXT_ABOVE;
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
  final SunmiTextStyle? style;
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

sp.SunmiPrintAlign _align(dynamic a) {
  if (a == null) return sp.SunmiPrintAlign.LEFT;
  if (a is sp.SunmiPrintAlign) return a;
  final s = a.toString().toUpperCase();
  if (s.contains('CENTER')) return sp.SunmiPrintAlign.CENTER;
  if (s.contains('RIGHT')) return sp.SunmiPrintAlign.RIGHT;
  return sp.SunmiPrintAlign.LEFT;
}

sp.SunmiFontSize _fontSize(int? px) {
  if (px == null) return sp.SunmiFontSize.MD;
  if (px <= 18) return sp.SunmiFontSize.XS;
  if (px <= 22) return sp.SunmiFontSize.SM;
  if (px <= 28) return sp.SunmiFontSize.MD;
  if (px <= 34) return sp.SunmiFontSize.LG;
  return sp.SunmiFontSize.XL;
}

sp.SunmiBarcodeType _barcodeType(dynamic t) {
  if (t is sp.SunmiBarcodeType) return t;
  final s = '$t'.toUpperCase();
  if (s.contains('EAN13') || s.contains('JAN13')) return sp.SunmiBarcodeType.JAN13;
  if (s.contains('EAN8') || s.contains('JAN8')) return sp.SunmiBarcodeType.JAN8;
  if (s.contains('CODE39')) return sp.SunmiBarcodeType.CODE39;
  return sp.SunmiBarcodeType.CODE128;
}

sp.SunmiBarcodeTextPos _barcodeTextPos(dynamic t) {
  if (t is sp.SunmiBarcodeTextPos) return t;
  final s = '$t'.toUpperCase();
  if (s.contains('NO')) return sp.SunmiBarcodeTextPos.NO_TEXT;
  if (s.contains('ABOVE')) return sp.SunmiBarcodeTextPos.TEXT_ABOVE;
  return sp.SunmiBarcodeTextPos.TEXT_UNDER;
}

class SunmiPrinter {
  static Future<bool> initPrinter() async {
    try {
      final ok = await sp.SunmiPrinter.initPrinter();
      return ok == true;
    } catch (e) {
      debugPrint('Sunmi initPrinter: $e');
      return false;
    }
  }

  static Future<void> printText(String text, {dynamic style}) async {
    SunmiTextStyle? st;
    if (style is SunmiTextStyle) st = style;
    await sp.SunmiPrinter.printText(
      text,
      style: sp_style.SunmiStyle(
        bold: st?.bold,
        fontSize: _fontSize(st?.fontSize),
        align: _align(st?.align),
      ),
    );
  }

  static Future<void> printRow({required List<dynamic> cols}) async {
    // printColumnsText dùng FONT A cố định — nếu vừa in chữ LG/XL thì cột
    // wrap loạn (xuống dòng, ký tự rơi rụng). Luôn reset cỡ trước row.
    try {
      await sp.SunmiPrinter.resetFontSize();
    } catch (_) {
      try {
        await sp.SunmiPrinter.setFontSize(sp.SunmiFontSize.SM);
      } catch (_) {}
    }
    final makers = <ColumnMaker>[];
    for (final c in cols) {
      if (c is SunmiColumn) {
        makers.add(ColumnMaker(
          text: c.text,
          width: (c.width ?? 12).clamp(1, 48),
          align: _align(c.style?.align),
        ));
      } else if (c is ColumnMaker) {
        makers.add(c);
      }
    }
    if (makers.isEmpty) return;
    await sp.SunmiPrinter.printRow(cols: makers);
  }

  static Future<void> lineWrap(int n) async {
    await sp.SunmiPrinter.lineWrap(n.clamp(0, 20));
  }

  static Future<void> cutPaper() async {
    await sp.SunmiPrinter.cut();
  }

  static Future<String?> printEscPos(List<int> bytes) async {
    try {
      await sp.SunmiPrinter.printRawData(Uint8List.fromList(bytes));
      return 'ok';
    } catch (e) {
      debugPrint('Sunmi printEscPos/raw: $e');
      return 'fail:$e';
    }
  }

  static Future<void> printBarCode(
    String data, {
    dynamic style,
    int? size,
    dynamic textPos,
  }) async {
    SunmiBarcodeStyle? st;
    if (style is SunmiBarcodeStyle) st = style;
    await sp.SunmiPrinter.printBarCode(
      data,
      barcodeType: _barcodeType(st?.type),
      height: st?.height ?? 80,
      width: (st?.width ?? st?.size ?? size ?? 2).clamp(1, 6),
      textPosition: _barcodeTextPos(st?.textPos ?? st?.textPosition ?? textPos),
    );
  }

  static Future<void> printBarcode(String data, {dynamic style}) async {
    await printBarCode(data, style: style);
  }

  static Future<void> printQRCode(String data,
      {dynamic style, dynamic align}) async {
    await sp.SunmiPrinter.printQRCode(data);
  }

  static Future<void> printImage(dynamic img, {dynamic align}) async {
    Uint8List bytes;
    if (img is Uint8List) {
      bytes = img;
    } else if (img is List<int>) {
      bytes = Uint8List.fromList(img);
    } else {
      debugPrint('Sunmi printImage: unsupported type ${img.runtimeType}');
      return;
    }
    if (align != null) {
      await sp.SunmiPrinter.setAlignment(_align(align));
    }
    await sp.SunmiPrinter.printImage(bytes);
  }

  static Future<void> setAlignment(dynamic align) async {
    await sp.SunmiPrinter.setAlignment(_align(align));
  }

  static Future<void> bold(bool v) async {
    if (v) {
      await sp.SunmiPrinter.bold();
    } else {
      await sp.SunmiPrinter.resetBold();
    }
  }
}

class SunmiPrinterPlus {
  Future<bool> rebindPrinter() async {
    try {
      final bound = await sp.SunmiPrinter.bindingPrinter();
      if (bound != true) {
        debugPrint('Sunmi bindingPrinter => $bound');
        return false;
      }
      await sp.SunmiPrinter.initPrinter();
      return true;
    } catch (e) {
      debugPrint('Sunmi rebindPrinter: $e');
      return false;
    }
  }

  static Future<void> bindPrinterService() async {
    await sp.SunmiPrinter.bindingPrinter();
  }

  static Future<void> unbindPrinterService() async {
    await sp.SunmiPrinter.unbindingPrinter();
  }
}

class SunmiConfig {
  static Future<String?> getPrinterSerial() async {
    try {
      return await sp.SunmiPrinter.serialNumber();
    } catch (_) {
      return null;
    }
  }

  static Future<dynamic> getPrinterVersion() async {
    try {
      return await sp.SunmiPrinter.printerVersion();
    } catch (_) {
      return null;
    }
  }

  static Future<dynamic> getStatus() async {
    try {
      // Trả tên enum (NORMAL / OUT_OF_PAPER / …) — transport check theo keyword.
      final st = await sp.SunmiPrinter.getPrinterStatus();
      return st.name;
    } catch (e) {
      debugPrint('Sunmi getStatus: $e');
      return null;
    }
  }
}

class SunmiDrawer {
  static Future<void> openDrawer() async {
    await sp.SunmiPrinter.openDrawer();
  }
}
