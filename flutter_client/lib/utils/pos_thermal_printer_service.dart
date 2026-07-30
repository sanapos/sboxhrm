import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'package:intl/intl.dart';

import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';



import '../models/pos_sale_order.dart';

import 'pos_esc_pos_text_codec.dart';

import 'pos_print_template_compiler.dart';

import 'pos_thermal_bitmap.dart';

import 'pos_printer_transport.dart';

import 'pos_receipt_layout.dart';

import 'pos_table_label.dart';

import 'pos_sunmi_native_print.dart';
import 'pos_thermal_printer_settings.dart';
import 'pos_printer_peripheral.dart';
import '../l10n/app_tr.dart';



/// In hóa đơn ra máy in nhiệt (LAN / Sunmi / Bluetooth).

class PosThermalPrinterService {

  static final _money = NumberFormat('#,##0', 'vi_VN');

  static final _qty = NumberFormat('#,##0.##', 'vi_VN');

  static final _date = DateFormat('dd/MM/yyyy HH:mm');
  static final _dateOnly = DateFormat('dd/MM/yyyy');



  static Future<bool> isSunmiDevice() async {
    return PosPrinterTransport.isSunmiDevice();
  }



  static Future<List<Map<String, String>>> listBluetoothDevices() async {

    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return [];

    try {

      final paired = await PrintBluetoothThermal.pairedBluetooths

          .timeout(const Duration(seconds: 4), onTimeout: () => []);

      return paired

          .map((d) => {'name': d.name, 'address': d.macAdress})

          .toList();

    } catch (e) {

      debugPrint('listBluetoothDevices: $e');

      return [];

    }

  }



  static Future<bool> printSaleOrder(

    PosSaleOrder order, {

    required PosThermalPrinterSettings settings,

    String? storeName,

    String? storeAddress,

    String? storePhone,

    bool mergeSameItems = true,

    int copies = 1,

    String? vietQrImageUrl,

  }) async {

    if (!settings.enabled || kIsWeb) return false;

    final bytes = await _buildEscPosReceipt(

      order: order,

      settings: settings,

      storeName: storeName,

      storeAddress: storeAddress,

      storePhone: storePhone,

      mergeSameItems: mergeSameItems,

      vietQrImageUrl: vietQrImageUrl,

    );



    for (var c = 0; c < copies.clamp(1, 10); c++) {

      final ok = await _sendBytes(settings, bytes);

      if (!ok) return false;

    }

    return true;

  }



  static Future<bool> testPrint(PosThermalPrinterSettings settings) async {

    if (!settings.enabled || kIsWeb) return false;

    if (settings.connectionType == PosThermalConnectionType.sunmi ||
        await PosPrinterTransport.isSunmiDevice()) {
      final nativeOk = await PosSunmiNativePrint.printTest(
        storeLabel: 'SBOX POS',
        feedLines: settings.resolvedFeedBeforeCut,
        paperWidthMm: settings.paperWidthMm,
      );
      if (nativeOk) return true;
    }

    final bytes = await buildTestEscPosBytes(settings);

    return _sendBytes(settings, bytes);

  }



  /// Tạo byte ESC/POS hóa đơn bán (dùng cho cloud print / agent).

  static Future<List<int>> buildSaleOrderEscPosBytes(

    PosSaleOrder order, {

    required PosThermalPrinterSettings settings,

    String? storeName,

    String? storeAddress,

    String? storePhone,

    bool mergeSameItems = true,

    String? vietQrImageUrl,

    List<PosSaleOrderLine>? linesOverride,

    bool warehouseSlip = false,
    @Deprecated('Use warehouseSlip') bool kitchenSlip = false,
    String? slipTitle,

    double vatAmount = 0,

    double surchargeAmount = 0,

  }) =>

      _buildEscPosReceipt(

        order: order,

        settings: settings,

        storeName: storeName,

        storeAddress: storeAddress,

        storePhone: storePhone,

        mergeSameItems: mergeSameItems,

        vietQrImageUrl: (warehouseSlip || kitchenSlip) ? null : vietQrImageUrl,

        linesOverride: linesOverride,

        warehouseSlip: warehouseSlip || kitchenSlip,
        slipTitle: slipTitle,

        vatAmount: vatAmount,

        surchargeAmount: surchargeAmount,

      );



  static Future<List<int>> buildTestEscPosBytes(

    PosThermalPrinterSettings settings,

  ) =>

      _buildTestReceipt(settings);



  /// In từ mẫu V2 đã biên dịch (bitmap Zywell / ESC/POS).
  static Future<List<int>> buildCompiledEscPosBytes(
    PosPrintCompiledOutput output, {
    required PosThermalPrinterSettings settings,
  }) async {
    final b = await _EscPosBuilder.create(settings);
    for (final step in output.steps) {
      if (step is PosPrintCompiledLine) {
        final line = step;
        if (line.isDivider) {
          b.left();
          await b.boldLine(line.text, size: 14);
          continue;
        }
        if (line.center) {
          b.center();
        } else {
          b.left();
        }
        if (line.text.trim().isEmpty) {
          b.feed(1);
          continue;
        }
        await b.boldLine(line.text, size: line.fontSize);
      } else if (step is PosPrintCompiledPair) {
        b.left();
        await b.boldLine('${step.left}  ${step.right}', size: step.fontSize);
      } else if (step is PosPrintCompiledQr) {
        b.center();
        if (step.title != null && step.title!.trim().isNotEmpty) {
          await b.line(step.title!.trim());
        }
        final raster = await PosThermalBitmapEncoder.networkPngToEscPos(
          step.imageUrl,
          maxWidth: step.size,
        );
        if (raster != null) {
          b.appendRaw(raster);
        }
        if (step.caption.trim().isNotEmpty) {
          await b.line(step.caption.trim());
        }
        if (step.amountText != null && step.amountText!.trim().isNotEmpty) {
          await b.line('${step.amountText!.trim()} đ');
        }
      }
    }
    await b.finishAsync();
    return b.bytes;
  }



  /// Phiếu text đơn giản (cuối ngày, phiếu kho…).

  static Future<List<int>> buildTextEscPosBytes({

    required PosThermalPrinterSettings settings,

    String? title,

    required List<String> lines,

    String? footer,

  }) async {

    final b = await _EscPosBuilder.create(settings);

    if (title != null && title.trim().isNotEmpty) {

      b.center();

      await b.boldLine(title.trim(), size: 26);

      b.feed(1);

    }

    for (final line in lines) {

      if (line.trim().isEmpty) {

        b.feed(1);

      } else {

        await b.line(line);

      }

    }

    if (footer != null && footer.trim().isNotEmpty) {

      b.feed(1);

      await b.line(footer.trim());

    }

    await b.finishAsync();

    return b.bytes;

  }



  static Future<bool> _sendBytes(

    PosThermalPrinterSettings settings,

    List<int> bytes,

  ) async {

    switch (settings.connectionType) {

      case PosThermalConnectionType.lan:

        return _sendLan(settings, bytes);

      case PosThermalConnectionType.sunmi:

        return _sendSunmi(settings, bytes);

      case PosThermalConnectionType.bluetooth:

        return _sendBluetooth(settings, bytes);

      case PosThermalConnectionType.usb:

        if (await isSunmiDevice()) return _sendSunmi(settings, bytes);

        return _sendLan(settings, bytes);

    }

  }



  static Future<bool> _sendLan(
    PosThermalPrinterSettings settings,
    List<int> bytes,
  ) async {
    return PosPrinterTransport.send(
      connectionType: PosThermalConnectionType.lan,
      lanHost: settings.lanHost,
      lanPort: settings.lanPort,
      bytes: bytes,
    );
  }

  static Future<bool> _sendSunmi(
    PosThermalPrinterSettings settings,
    List<int> bytes,
  ) async {
    return PosPrinterTransport.send(
      connectionType: PosThermalConnectionType.sunmi,
      bytes: bytes,
      sunmiFeedLines: settings.resolvedFeedBeforeCut,
    );
  }

  static Future<bool> _sendBluetooth(
    PosThermalPrinterSettings settings,
    List<int> bytes,
  ) async {
    return PosPrinterTransport.send(
      connectionType: PosThermalConnectionType.bluetooth,
      bluetoothAddress: settings.bluetoothAddress,
      bytes: bytes,
    );
  }


  static Future<List<int>> _buildTestReceipt(

    PosThermalPrinterSettings settings,

  ) async {

    final b = await _EscPosBuilder.create(settings);

    b.center();

    await b.boldLine('SBOX POS', size: 26);

    await b.line('Kiểm tra máy in');

    await b.line('Hãng: ${settings.printerBrand.label}');

    await b.line('Chế độ chữ: ${settings.resolvedTextMode.label}');

    await b.line('Khổ giấy: ${settings.paperWidthMm}mm');

    await b.line('Tiếng Việt: Đậu phộng da cá — 35.000 đ');

    await b.line(_date.format(DateTime.now()));

    b.feed(1);

    await b.line('Cảm ơn quý khách!');

    await b.finishAsync();

    return b.bytes;

  }



  static Future<List<int>> _buildEscPosReceipt({

    required PosSaleOrder order,

    required PosThermalPrinterSettings settings,

    String? storeName,

    String? storeAddress,

    String? storePhone,

    bool mergeSameItems = true,

    String? vietQrImageUrl,

    List<PosSaleOrderLine>? linesOverride,

    bool warehouseSlip = false,
    @Deprecated('Use warehouseSlip') bool kitchenSlip = false,
    String? slipTitle,

    double vatAmount = 0,

    double surchargeAmount = 0,

  }) async {

    final isWarehouseSlip = warehouseSlip || kitchenSlip;
    final b = await _EscPosBuilder.create(settings);

    final saleDate =

        order.saleDate?.toLocal() ?? order.createdAt?.toLocal() ?? DateTime.now();

    final rawLines = linesOverride ?? order.lines;

    final lines = mergeSameItems ? _mergeLines(rawLines) : rawLines;

    final isSubset = linesOverride != null;

    final lineDiscount = lines.fold<double>(0, (s, l) => s + l.discountAmount);

    final linesTotal = lines.fold<double>(0, (s, l) => s + l.lineTotal);

    final receiptTotal = isSubset ? linesTotal : order.total;

    final orderDiscount = isSubset ? 0.0 : order.discount;



    b.center();

    await b.boldLine(

      storeName?.trim().isNotEmpty == true ? storeName!.trim() : 'CỬA HÀNG',

      size: 26,

    );

    if (storeAddress != null && storeAddress.trim().isNotEmpty) {

      await b.line('DC: ${storeAddress.trim()}');

    }

    if (storePhone != null && storePhone.trim().isNotEmpty) {

      await b.line('SDT: ${storePhone.trim()}');

    }

    b.center();

    await b.boldLine(
      isWarehouseSlip
          ? (slipTitle?.trim().isNotEmpty == true
              ? slipTitle!.trim()
              : 'PHIẾU BÁO XUẤT KHO')
          : (slipTitle?.trim().isNotEmpty == true
              ? slipTitle!.trim()
              : (order.printCount > 1
                  ? 'HÓA ĐƠN BÁN HÀNG — IN LẠI'
                  : 'HÓA ĐƠN BÁN HÀNG')),
      size: 24,
    );

    b.left();

    if (!isWarehouseSlip && order.printCount > 1) {
      await b.line('*** BẢN IN LẠI — Lần in thứ ${order.printCount} ***');
    }

    await b.line('Số: ${order.orderNo.isEmpty ? '-' : order.orderNo}');
    await b.line('Ngày: ${_dateOnly.format(saleDate)}');

    final inAt = order.serviceStartedAt?.toLocal();
    final outAt = order.serviceEndedAt?.toLocal();
    if (inAt != null) {
      await b.line('Giờ vào: ${_date.format(inAt)}');
    }
    final isProvisionalTitle =
        (slipTitle ?? '').toUpperCase().contains('TẠM');
    if (outAt != null && !isWarehouseSlip && !isProvisionalTitle) {
      await b.line('Giờ ra: ${_date.format(outAt)}');
    }

    final tableLines = formatPosTablePrintLines(
      areaName: order.serviceAreaName,
      tableName: order.serviceResourceName ?? order.serviceResourceCode,
    );
    for (final line in tableLines) {
      await b.line(line);
    }

    await b.line(
      'KH: ${order.customerName ?? 'Khach le'}',
    );

    if (order.soldBy != null && order.soldBy!.trim().isNotEmpty) {
      await b.line('Thu ngân: ${order.soldBy!.trim()}');
    }

    await b.separator();

    await _printLineTable(b, lines);

    await _printReceiptSummary(
      b,
      subTotal: isSubset ? linesTotal : (order.subTotal > 0 ? order.subTotal : linesTotal),
      total: receiptTotal,
      orderDiscount: orderDiscount,
      lineDiscount: lineDiscount,
      vatAmount: isSubset ? 0 : vatAmount,
      surchargeAmount: isSubset ? 0 : surchargeAmount,
      includePayment: !isWarehouseSlip,
      order: isWarehouseSlip ? null : order,
    );

    if (isWarehouseSlip) {
      if (order.note != null && order.note!.trim().isNotEmpty) {
        await b.line('Ghi chú: ${order.note!.trim()}');
      }
      b.feed(1);
      await b.finishAsync();
      return b.bytes;
    }

    if (order.note != null && order.note!.trim().isNotEmpty) {

      await b.line('Ghi chú: ${order.note!.trim()}');

    }

    if (vietQrImageUrl != null && vietQrImageUrl.isNotEmpty) {

      b.feed(1);

      b.center();

      await b.line('Quét VietQR thanh toán');

      await b.line('${_money.format(order.total)} đ');

    }

    b.feed(1);

    b.center();

    await b.line('Cam on quy khach!');

    await b.finishAsync();

    var result = b.bytes;

    if (vietQrImageUrl != null && vietQrImageUrl.isNotEmpty) {

      final qrRaster = await PosThermalBitmapEncoder.networkPngToEscPos(

        vietQrImageUrl,

        maxWidth: PosThermalBitmapEncoder.paperDots(settings.paperWidthMm) - 48,

      );

      if (qrRaster != null) {

        result = PosThermalBitmapEncoder.insertRasterBeforeCut(result, qrRaster);

      }

    }

    return result;

  }



  static Future<void> _printLineTable(
    _EscPosBuilder b,
    List<PosSaleOrderLine> lines,
  ) async {
    b.left();
    final layout = PosReceiptLayout.fromSettingsChars(b.maxChars);
    String money(double v) => _money.format(v);
    await b.boldLine(layout.saleHeader, size: layout.k58 ? 19 : 21);
    await b.separator();

    for (final line in lines) {
      final name = line.productName;
      final qty = _qty.format(line.qty);
      final saleUnit = line.qty > 0 ? line.lineTotal / line.qty : line.unitPrice;
      final price = money(
        line.discountAmount > 0 ? saleUnit : line.unitPrice,
      );
      final original = line.discountAmount > 0
          ? money(line.unitPrice)
          : null;
      final total = money(line.lineTotal);
      final rows = layout.saleItemRows(
        name: name,
        qty: qty,
        price: price,
        total: total,
        originalPrice: original,
      );
      for (final row in rows) {
        await b.line(row);
      }
      final note = line.lineNote?.trim();
      if (note != null && note.isNotEmpty) {
        await b.line(' * $note');
      }
    }
  }

  static Future<void> _printReceiptSummary(
    _EscPosBuilder b, {
    required double total,
    double subTotal = 0,
    double orderDiscount = 0,
    double lineDiscount = 0,
    double vatAmount = 0,
    double surchargeAmount = 0,
    bool includePayment = true,
    PosSaleOrder? order,
  }) async {
    b.left();
    await b.separator();
    final hangTotal = subTotal > 0 ? subTotal : total;
    await b.pair('Tong thanh tien:', _money.format(hangTotal));
    final ck = orderDiscount > 0 ? orderDiscount : lineDiscount;
    if (ck > 0) {
      await b.pair('Chiet khau:', _money.format(ck));
    }
    if (vatAmount > 0) {
      await b.pair('VAT:', _money.format(vatAmount));
    }
    if (surchargeAmount > 0) {
      await b.pair('Phu thu:', _money.format(surchargeAmount));
    }
    await b.boldPair('Tong cong:', _money.format(total));
    if (includePayment && order != null) {
      await b.pair('Thanh toan:', _money.format(order.paidAmount));
      if (order.balanceDue > 0) {
        await b.pair('Con no:', _money.format(order.balanceDue));
      }
    }
  }



  static List<PosSaleOrderLine> _mergeLines(List<PosSaleOrderLine> lines) {

    final map = <String, PosSaleOrderLine>{};

    for (final l in lines) {

      final key =

          '${l.productId}|${l.variantId}|${l.unitName}|${l.unitPrice}|${l.lineNote}|${l.discountAmount}';

      final hit = map[key];

      if (hit == null) {

        map[key] = l;

      } else {

        map[key] = PosSaleOrderLine(

          id: hit.id,

          productId: hit.productId,

          productName: hit.productName,

          variantId: hit.variantId,

          unitName: hit.unitName,

          qty: hit.qty + l.qty,

          unitPrice: hit.unitPrice,

          lineTotal: hit.lineTotal + l.lineTotal,

          discountAmount: hit.discountAmount + l.discountAmount,

          lineNote: hit.lineNote,

        );

      }

    }

    return map.values.toList();

  }

}



class _EscPosBuilder {

  _EscPosBuilder._(this._settings)

      : _textMode = _settings.resolvedTextMode,

        _paperDots = PosThermalBitmapEncoder.paperDots(_settings.paperWidthMm);



  final PosThermalPrinterSettings _settings;

  final PosThermalTextMode _textMode;

  final int _paperDots;

  final List<int> _buf = [];

  final List<PosReceiptImageLine> _imageLines = [];

  bool _centered = false;

  bool get _useImageBatch => _textMode == PosThermalTextMode.image;

  double get _bodyFontSize => _settings.paperWidthMm <= 58 ? 20.0 : 22.0;



  int get maxChars => _settings.paperWidthMm <= 58 ? 32 : 48;



  List<int> get bytes => List<int>.from(_buf);



  static Future<_EscPosBuilder> create(PosThermalPrinterSettings settings) async {

    final b = _EscPosBuilder._(settings);

    b._add([0x1B, 0x40]);

    switch (b._textMode) {

      case PosThermalTextMode.tcvn3:

        b._add(PosEscPosTextCodec.initTcvn3());

      case PosThermalTextMode.cp1258:

        b._add(PosEscPosTextCodec.initCp1258());

      case PosThermalTextMode.utf8:

        b._add(PosEscPosTextCodec.initUtf8());

      case PosThermalTextMode.image:

      case PosThermalTextMode.ascii:

      case PosThermalTextMode.auto:

        break;

    }

    if (b._useImageBatch) {

      await PosThermalBitmapEncoder.ensureFont();

    }

    // GS W — đặt độ rộng vùng in (80mm = 576 dots) để máy K80 không in như K58.
    if (b._settings.paperWidthMm > 58) {
      b._add([0x1D, 0x57, 0x40, 0x02]);
    }

    b.left();

    return b;

  }



  void _add(List<int> data) => _buf.addAll(data);

  void appendRaw(List<int> data) => _add(data);

  void left() {
    _centered = false;
    if (!_useImageBatch) {
      _add([0x1B, 0x61, 0x00]);
    }
  }

  void center() {
    _centered = true;
    if (!_useImageBatch) {
      _add([0x1B, 0x61, 0x01]);
    }
  }

  void _queueImageLine(
    String text, {
    bool bold = false,
    double? fontSize,
  }) {
    _imageLines.add(
      PosReceiptImageLine(
        text: tr(text),
        bold: bold,
        center: _centered,
        fontSize: fontSize ?? _bodyFontSize,
      ),
    );
  }

  Future<void> line(String text) async {
    if (text.trim().isEmpty) {
      if (_useImageBatch) {
        _queueImageLine(' ', fontSize: 10);
      } else {
        _add([0x0A]);
      }
      return;
    }

    switch (_textMode) {
      case PosThermalTextMode.image:
        _queueImageLine(text);
      case PosThermalTextMode.tcvn3:
        _add(PosEscPosTextCodec.encodeTcvn3(text));
        _add([0x0A]);
      case PosThermalTextMode.cp1258:
        _add(PosEscPosTextCodec.encodeCp1258(text));
        _add([0x0A]);
      case PosThermalTextMode.utf8:
        _add(PosEscPosTextCodec.encodeUtf8(text));
        _add([0x0A]);
      case PosThermalTextMode.ascii:
      case PosThermalTextMode.auto:
        _add(PosEscPosTextCodec.encodeUtf8(
          PosEscPosTextCodec.stripDiacritics(text),
        ));
        _add([0x0A]);
    }
  }

  Future<void> boldLine(String text, {double size = 24}) async {
    if (_useImageBatch) {
      _queueImageLine(text, bold: true, fontSize: size);
      return;
    }

    _add([0x1B, 0x45, 0x01]);
    await line(text);
    _add([0x1B, 0x45, 0x00]);
  }

  Future<void> pair(String left, String right) async {
    String l;
    String r;
    if (_textMode == PosThermalTextMode.tcvn3 ||
        _textMode == PosThermalTextMode.cp1258 ||
        _textMode == PosThermalTextMode.utf8 ||
        _useImageBatch) {
      l = left.trim();
      r = right.trim();
    } else {
      l = PosEscPosTextCodec.stripDiacritics(left);
      r = PosEscPosTextCodec.stripDiacritics(right);
    }
    final space = maxChars - l.length - r.length;
    final combined =
        space >= 1 ? '$l${' ' * space}$r' : (l.isEmpty ? r : '$l $r');

    if (_useImageBatch) {
      _queueImageLine(
        combined,
        fontSize: _settings.paperWidthMm <= 58 ? 19 : 20,
      );
      return;
    }

    if (space >= 1) {
      await line('$l${' ' * space}$r');
    } else {
      await line(l);
      await line(r);
    }
  }

  Future<void> boldPair(String left, String right) async {
    if (_useImageBatch) {
      _queueImageLine(
        '${left.trim()}  ${right.trim()}',
        bold: true,
        fontSize: 22,
      );
      return;
    }

    _add([0x1B, 0x45, 0x01]);
    await pair(left, right);
    _add([0x1B, 0x45, 0x00]);
  }

  Future<void> separator() async {
    final sep = List.filled(maxChars, '-').join();
    if (_useImageBatch) {
      _queueImageLine(sep, fontSize: _settings.paperWidthMm <= 58 ? 18 : 20);
      return;
    }
    await line(sep);
  }

  void feed(int lines) {
    if (_useImageBatch) {
      for (var i = 0; i < lines; i++) {
        _queueImageLine(' ', fontSize: 10);
      }
      return;
    }
    for (var i = 0; i < lines; i++) {
      _add([0x0A]);
    }
  }

  Future<void> finishAsync() async {
    if (_useImageBatch && _imageLines.isNotEmpty) {
      final raster = await PosThermalBitmapEncoder.receiptToRaster(
        _imageLines,
        paperDots: _paperDots,
      );
      if (raster != null && PosThermalBitmapEncoder.rasterHasInk(raster)) {
        _add(raster);
      } else {
        for (final ln in _imageLines) {
          final t = ln.text.trim();
          if (t.isEmpty) continue;
          _add(PosEscPosTextCodec.encodeUtf8(
            PosEscPosTextCodec.stripDiacritics(ln.text),
          ));
          _add([0x0A]);
        }
      }
      _imageLines.clear();
    }

    final n = _settings.resolvedFeedBeforeCut.clamp(10, 28);
    if (!_useImageBatch) {
      feed(2);
    }
    _add([0x1B, 0x64, n]);
    _add([0x1D, 0x56, _settings.partialCut ? 0x01 : 0x00]);
    // Bip / mở két sau cắt — stripTrailingCut (Sunmi) giữ lại các lệnh này.
    PosPrinterPeripheral.appendEscPosTrailing(
      _buf,
      _settings,
      openDrawer: _settings.openCashDrawer,
    );
  }
}

