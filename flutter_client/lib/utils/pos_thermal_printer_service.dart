import 'dart:io' show Platform, Socket;

import 'dart:typed_data';



import 'package:device_info_plus/device_info_plus.dart';

import 'package:flutter/foundation.dart';

import 'package:intl/intl.dart';

import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';



import '../models/pos_sale_order.dart';

import 'pos_esc_pos_text_codec.dart';

import 'pos_thermal_bitmap.dart';

import 'pos_thermal_printer_settings.dart';

import 'pos_vietnamese_money_words.dart';



/// In hóa đơn ra máy in nhiệt (LAN / Sunmi / Bluetooth).

class PosThermalPrinterService {

  static final _money = NumberFormat('#,##0', 'vi_VN');

  static final _qty = NumberFormat('#,##0.##', 'vi_VN');

  static final _date = DateFormat('dd/MM/yyyy HH:mm');



  static Future<bool> isSunmiDevice() async {

    if (kIsWeb || !Platform.isAndroid) return false;

    try {

      final info = await DeviceInfoPlugin().androidInfo;

      final brand = info.brand.toLowerCase();

      final man = info.manufacturer.toLowerCase();

      return brand.contains('sunmi') || man.contains('sunmi');

    } catch (_) {

      return false;

    }

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

    final host = settings.lanHost?.trim();

    if (host == null || host.isEmpty) return false;

    try {

      final socket = await Socket.connect(

        host,

        settings.lanPort,

        timeout: const Duration(seconds: 8),

      );

      socket.add(bytes);

      await socket.flush();

      await Future<void>.delayed(const Duration(milliseconds: 300));

      await socket.close();

      return true;

    } catch (e) {

      debugPrint('LAN print failed: $e');

      return false;

    }

  }



  static Future<bool> _sendSunmi(

    PosThermalPrinterSettings settings,

    List<int> bytes,

  ) async {

    if (!await isSunmiDevice()) return false;

    try {

      await SunmiPrinter.bindingPrinter();

      await SunmiPrinter.printRawData(Uint8List.fromList(bytes));

      await SunmiPrinter.lineWrap(settings.resolvedFeedBeforeCut);

      return true;

    } catch (e) {

      debugPrint('Sunmi print failed: $e');

      return false;

    }

  }



  static Future<bool> _sendBluetooth(
    PosThermalPrinterSettings settings,
    List<int> bytes,
  ) async {
    final addr = settings.bluetoothAddress?.trim();
    if (addr == null || addr.isEmpty) return false;
    try {
      final connected = await PrintBluetoothThermal.connect(
        macPrinterAddress: addr,
      );
      if (connected != true) return false;

      const chunkSize = 512;
      for (var i = 0; i < bytes.length; i += chunkSize) {
        final end = i + chunkSize < bytes.length ? i + chunkSize : bytes.length;
        final ok = await PrintBluetoothThermal.writeBytes(bytes.sublist(i, end));
        if (ok != true) return false;
        if (end < bytes.length) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      }

      await Future<void>.delayed(const Duration(milliseconds: 600));
      return true;
    } catch (e) {
      debugPrint('Bluetooth print failed: $e');
      return false;
    }
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

      await b.line(storeAddress.trim());

    }

    if (storePhone != null && storePhone.trim().isNotEmpty) {

      await b.line('ĐT: ${storePhone.trim()}');

    }

    await b.separator();

    b.center();

    await b.boldLine(
      isWarehouseSlip
          ? (slipTitle?.trim().isNotEmpty == true
              ? slipTitle!.trim()
              : 'PHIẾU BÁO XUẤT KHO')
          : (order.printCount > 1 ? 'HÓA ĐƠN BÁN HÀNG IN LẠI' : 'HÓA ĐƠN BÁN HÀNG'),
      size: 24,
    );

    b.left();

    if (!isWarehouseSlip && order.printCount > 1) {
      await b.line('*** Bản in lại — thông báo chủ cửa hàng ***');
    }

    await b.line('Mã: ${order.orderNo.isEmpty ? '-' : order.orderNo}');

    await b.line('Ngày: ${_date.format(saleDate)}');

    await b.line('KH: ${order.customerName ?? 'Khách lẻ'}');

    if (order.soldBy != null && order.soldBy!.trim().isNotEmpty) {

      await b.line('NV: ${order.soldBy!.trim()}');

    }

    await b.separator();

    await _printLineTable(b, lines);

    await _printReceiptSummary(
      b,
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

    await b.line('Cảm ơn quý khách!');

    await b.line('Hẹn gặp lại!');

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



  static String _formatUnitPriceCell(PosSaleOrderLine line) {
    if (line.discountAmount <= 0) return _money.format(line.unitPrice);
    final saleUnit =
        line.qty > 0 ? line.lineTotal / line.qty : line.unitPrice;
    return '${_money.format(line.unitPrice)}>${_money.format(saleUnit)}';
  }



  static Future<void> _printLineTable(
    _EscPosBuilder b,
    List<PosSaleOrderLine> lines,
  ) async {
    b.left();
    final wide = b.maxChars >= 44;
    if (wide) {
      await b.boldLine(
        'STT Hàng hóa                  SL   Giá bán  Thành tiền',
        size: 20,
      );
    } else {
      await b.boldLine('STT Hàng hóa           SL  Giá bán    TT', size: 19);
    }
    await b.separator();

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final stt = '${i + 1}'.padLeft(2);
      var name = line.productName;
      if (line.unitName != null && line.unitName!.trim().isNotEmpty) {
        name = '$name (${line.unitName!.trim()})';
      }
      final qty = _qty.format(line.qty);
      final price = _formatUnitPriceCell(line);
      final total = _money.format(line.lineTotal);

      if (wide) {
        final nameWidth = 22;
        final chunks = PosThermalBitmapEncoder.wrapText(name, nameWidth);
        final first = chunks.first.padRight(nameWidth);
        await b.line(
          '$stt $first ${qty.padLeft(3)} ${price.padLeft(9)} ${total.padLeft(10)}',
        );
        for (var c = 1; c < chunks.length; c++) {
          await b.line('   ${chunks[c]}');
        }
      } else {
        final chunks = PosThermalBitmapEncoder.wrapText(name, b.maxChars - 4);
        await b.line('$stt ${chunks.first}');
        for (var c = 1; c < chunks.length; c++) {
          await b.line('   ${chunks[c]}');
        }
        await b.line('      ${qty.padLeft(3)} x $price  $total');
      }

      final note = line.lineNote?.trim();
      if (note != null && note.isNotEmpty) {
        await b.line('   • $note');
      }
    }
  }



  static Future<void> _printReceiptSummary(
    _EscPosBuilder b, {
    required double total,
    double orderDiscount = 0,
    double lineDiscount = 0,
    double vatAmount = 0,
    double surchargeAmount = 0,
    bool includePayment = true,
    PosSaleOrder? order,
  }) async {
    b.left();
    await b.separator();
    if (orderDiscount > 0) {
      await b.pair('Chiết khấu', '-${_money.format(orderDiscount)} đ');
    } else if (lineDiscount > 0) {
      await b.pair('Chiết khấu SP', '-${_money.format(lineDiscount)} đ');
    }
    if (vatAmount > 0) {
      await b.pair('VAT', '${_money.format(vatAmount)} đ');
    }
    if (surchargeAmount > 0) {
      await b.pair('Phụ thu', '${_money.format(surchargeAmount)} đ');
    }
    await b.boldPair('TỔNG CỘNG', '${_money.format(total)} đ');
    b.center();
    await b.line(vietnameseMoneyInWords(total.round()));
    b.left();
    if (includePayment && order != null) {
      await b.pair('Thanh toán', '${_money.format(order.paidAmount)} đ');
      if (order.balanceDue > 0) {
        await b.pair('Còn nợ', '${_money.format(order.balanceDue)} đ');
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
        text: text,
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

    final n = _settings.resolvedFeedBeforeCut;
    if (!_useImageBatch) {
      feed(1);
    }
    _add([0x1B, 0x64, n.clamp(0, 255)]);
    _add([0x1D, 0x56, _settings.partialCut ? 0x01 : 0x00]);
  }
}

