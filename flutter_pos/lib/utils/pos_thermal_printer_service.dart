import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'package:intl/intl.dart';

import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';



import '../models/pos_sale_order.dart';
import '../models/pos_print_template_v2.dart';
import 'pos_topping_format.dart';

import 'pos_esc_pos_text_codec.dart';

import 'pos_print_template_compiler.dart';

import 'pos_thermal_bitmap.dart';

import 'pos_printer_transport.dart';
import 'pos_printer_hardware.dart';
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

  static String _fmtTimedMinutes(int minutes) {
    if (minutes <= 0) return '0p';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return '${h}h${m.toString().padLeft(2, '0')}';
    if (h > 0) return '${h}h';
    return '${m}p';
  }
  static final _dateOnly = DateFormat('dd/MM/yyyy');



  static Future<bool> isSunmiDevice() async {
    return PosPrinterTransport.isSunmiDevice();
  }



  static Future<List<Map<String, String>>> listBluetoothDevices() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return [];
    final r = await PosPrinterHardware.listBluetoothForPicker();
    return r.devices;
  }

  /// Giống [listBluetoothDevices] kèm gợi ý khi danh sách rỗng.
  static Future<({List<Map<String, String>> devices, String? hint})>
      listBluetoothDevicesWithHint() =>
          PosPrinterHardware.listBluetoothForPicker();




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

    // Chỉ in native Sunmi khi kết nối đã chọn là Sunmi — không ép máy Sunmi
    // khi đang cấu hình USB / BT / LAN ngoài.
    if (settings.connectionType == PosThermalConnectionType.sunmi) {
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

  /// In lần lượt 4 chế độ chữ (image / tcvn3 / cp1258 / utf8) để chọn mode đúng máy.
  /// Trả về số phiếu gửi thành công.
  /// [sunmiNativeOnly] = true khi máy Sunmi (ESC/POS mode không dùng cho HĐ native).
  static Future<int> probeTextModes(PosThermalPrinterSettings settings) async {
    if (kIsWeb) return 0;

    // Chỉ khi cấu hình kết nối Sunmi — không ghi đè USB/BT/LAN.
    if (settings.connectionType == PosThermalConnectionType.sunmi) {
      final ok = await PosSunmiNativePrint.printTest(
        storeLabel: 'SBOX POS — Sunmi UTF-8',
        feedLines: settings.resolvedFeedBeforeCut,
        paperWidthMm: settings.paperWidthMm,
      );
      return ok ? -1 : 0;
    }

    const modes = [
      PosThermalTextMode.image,
      PosThermalTextMode.tcvn3,
      PosThermalTextMode.cp1258,
      PosThermalTextMode.utf8,
    ];
    var okCount = 0;
    for (final mode in modes) {
      final draft = settings.copyWith(enabled: true, textMode: mode);
      final bytes = await _buildProbeReceipt(draft, mode);
      final ok = await _sendBytes(draft, bytes);
      if (ok) okCount++;
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
    return okCount;
  }

  static Future<List<int>> _buildProbeReceipt(
    PosThermalPrinterSettings settings,
    PosThermalTextMode mode,
  ) async {
    final b = await _EscPosBuilder.create(settings);
    b.center();
    await b.boldLine('SBOX — THU CHE DO CHU', size: 24);
    await b.line('Mode: ${mode.key}');
    await b.line(mode.label);
    await b.line('Tieng Viet: Dau phong da ca');
    await b.line('Có dấu: Đậu phộng — 35.000đ');
    await b.line('Hoa: ĂÂÊÔƠƯ ĐẠ');
    await b.line(_date.format(DateTime.now()));
    await b.finishAsync();
    return b.bytes;
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

    double deliveryFee = 0,

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

        deliveryFee: deliveryFee,

      );



  static Future<List<int>> buildTestEscPosBytes(

    PosThermalPrinterSettings settings,

  ) =>

      _buildTestReceipt(settings);



  /// In từ mẫu V2 đã biên dịch (bitmap Zywell / ESC/POS).
  ///
  /// Chế độ ảnh: cùng [compiledStepToImageLine] như A6 Sunmi native —
  /// 4 cột hàng hóa, không ép chuỗi monospace (Agent/XP-80C hay lệch cột).
  static Future<List<int>> buildCompiledEscPosBytes(
    PosPrintCompiledOutput output, {
    required PosThermalPrinterSettings settings,
  }) async {
    final b = await _EscPosBuilder.create(settings);
    b._frameStyle = output.frameStyle;
    b._frameInsetMm = output.frameInsetMm;
    b._frameMarginMm = output.frameMarginMm;
    for (final step in output.steps) {
      if (step is PosPrintCompiledQr) {
        if (b._useImageBatch) await b.flushImageBatch();
        b.center();
        if (step.title != null && step.title!.trim().isNotEmpty) {
          await b.line(step.title!.trim());
        }
        if (b._useImageBatch) await b.flushImageBatch();
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
        continue;
      }
      if (step is PosPrintCompiledBarcode) {
        if (b._useImageBatch) await b.flushImageBatch();
        b.printCode128(
          step.data,
          height: step.height,
          showText: step.showText,
        );
        continue;
      }

      // Ảnh: pipeline V2 giống A6 (cột SL / Đ.giá / TT).
      if (b._useImageBatch) {
        final img = compiledStepToImageLine(step);
        if (img != null) b.queueReceiptImageLine(img);
        continue;
      }

      if (step is PosPrintCompiledLine) {
        final line = step;
        if (line.isDivider) {
          b.left();
          b.appendRaw(PosThermalBitmapEncoder.horizontalRuleEscPos(
            paperDots: PosThermalBitmapEncoder.paperDots(settings.paperWidthMm),
          ));
          continue;
        }
        if (line.center) {
          b.center();
        } else if (line.right) {
          b.right();
        } else {
          b.left();
        }
        if (line.text.trim().isEmpty) {
          b.feed(1);
          continue;
        }
        if (line.bold) {
          await b.boldLine(line.text, size: line.fontSize);
        } else {
          await b.line(line.text);
        }
      } else if (step is PosPrintCompiledSaleRow) {
        b.left();
        final layout = PosReceiptLayout.fromSettingsChars(b.maxChars);
        final rows = step.nameOnly
            ? PosReceiptLayout.wrap(step.name, layout.chars)
            : (step.showQty && !step.showPrice && !step.showTotal)
                ? [layout.pair(step.name, step.qty)]
                : layout.saleItemRows(
                    name: step.name,
                    qty: step.showQty ? step.qty : '',
                    price: step.showPrice ? step.price : '',
                    total: step.showTotal ? step.total : '',
                  );
        for (final row in rows) {
          if (step.bold) {
            await b.boldLine(row, size: step.fontSize);
          } else {
            await b.line(row);
          }
        }
      } else if (step is PosPrintCompiledPair) {
        b.left();
        if (step.bold) {
          await b.boldPair(step.left, step.right);
        } else {
          await b.pair(step.left, step.right);
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
        return PosPrinterTransport.send(
          connectionType: PosThermalConnectionType.usb,
          usbDeviceName: settings.usbDeviceName,
          lanHost: settings.lanHost,
          lanPort: settings.lanPort,
          bytes: bytes,
          sunmiFeedLines: settings.resolvedFeedBeforeCut,
        );
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

    double deliveryFee = 0,

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

    await b.line(
      'Số HĐ: ${order.orderNo.isEmpty ? '-' : PosReceiptLayout.formatSaleInvoiceNo(order.orderNo)}',
    );
    final tableLine = formatPosTableOneLine(
      areaName: order.serviceAreaName,
      tableName: order.serviceResourceName ?? order.serviceResourceCode,
    );
    if (tableLine.isNotEmpty) {
      await b.line(tableLine);
    }
    await b.line('Ngày: ${DateFormat('dd/MM/yyyy HH:mm').format(saleDate)}');

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
    final timedDuration = order.lines
        .map((l) => l.durationMinutes)
        .whereType<int>()
        .fold<int?>(null, (a, b) => a == null ? b : (a > b ? a : b));
    final timedBillable = order.lines
        .map((l) => l.billableMinutes)
        .whereType<int>()
        .fold<int?>(null, (a, b) => a == null ? b : (a > b ? a : b));
    if (timedDuration != null || timedBillable != null || inAt != null) {
      final wall = (inAt != null)
          ? (() {
              final end = outAt ?? DateTime.now();
              final m = end.difference(inAt).inMinutes;
              return m < 0 ? 0 : m;
            })()
          : timedDuration;
      final bill = timedBillable ?? wall;
      if (wall != null && wall > 0) {
        final wallLabel = _fmtTimedMinutes(wall);
        if (bill != null && bill != wall) {
          await b.line('Thời lượng: $wallLabel (tính ${_fmtTimedMinutes(bill)})');
        } else {
          await b.line('Thời lượng: $wallLabel');
        }
      } else if (bill != null && bill > 0) {
        await b.line('Thời lượng tính: ${_fmtTimedMinutes(bill)}');
      }
    }

    await b.line(
      'KH: ${order.customerName ?? 'Khach le'}',
    );

    if (order.soldBy != null && order.soldBy!.trim().isNotEmpty) {
      await b.line('Thu ngân: ${order.soldBy!.trim()}');
    }

    await b.separator();

    await _printLineTable(b, lines);

    final extraSurcharge = isSubset
        ? 0.0
        : (surchargeAmount > 0 ? surchargeAmount : order.surchargeAmount);
    final extraShip = isSubset
        ? 0.0
        : (deliveryFee > 0 ? deliveryFee : order.deliveryFee);
    final extraVat = isSubset ? 0.0 : vatAmount;
    final payableTotal = receiptTotal + extraVat + extraSurcharge + extraShip;

    await _printReceiptSummary(
      b,
      subTotal: isSubset ? linesTotal : (order.subTotal > 0 ? order.subTotal : linesTotal),
      total: payableTotal,
      orderDiscount: orderDiscount,
      lineDiscount: lineDiscount,
      vatAmount: extraVat,
      surchargeAmount: extraSurcharge,
      deliveryFee: extraShip,
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
    String money(double v) => PosReceiptLayout.moneyItem(v);
    for (final h in layout.saleHeaders) {
      await b.boldLine(h, size: layout.k58 ? 19 : 21);
    }
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
      final note = posToppingNoteFromSaleLine(line, withPrice: true);
      if (note.isNotEmpty) {
        for (final part in note.split('\n')) {
          final t = part.trim();
          if (t.isEmpty) continue;
          await b.line(t.startsWith('+') ? '  $t' : ' * $t');
        }
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
    double deliveryFee = 0,
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
    if (deliveryFee > 0) {
      await b.pair('Phi giao hang:', _money.format(deliveryFee));
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

  PosPrintFrameStyle _frameStyle = PosPrintFrameStyle.none;

  double _frameInsetMm = 2.5;

  double _frameMarginMm = 1.5;

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

        b._add(PosEscPosTextCodec.initCp1258(page: b._settings.escPosCodePage));

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

  /// ESC/POS CODE128 (GS k 73).
  void printCode128(String data, {int height = 60, bool showText = true}) {
    final code = data.trim();
    if (code.isEmpty) return;
    if (_useImageBatch) {
      _imageLines.add(PosReceiptImageLine(
        text: code,
        fontSize: 20,
        bold: true,
        center: true,
      ));
      return;
    }
    center();
    final h = height.clamp(1, 255);
    _add([0x1D, 0x68, h]); // GS h n
    _add([0x1D, 0x48, showText ? 0x02 : 0x00]); // GS H n — dưới / không
    _add([0x1D, 0x77, 0x02]); // GS w — độ rộng module
    final bytes = code.codeUnits.where((c) => c >= 32 && c <= 126).toList();
    if (bytes.isEmpty) return;
    // CODE128: m=73, n=length, data
    _add([0x1D, 0x6B, 73, bytes.length, ...bytes]);
    _add([0x0A]);
  }

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

  void right() {
    _centered = false;
    if (!_useImageBatch) {
      _add([0x1B, 0x61, 0x02]);
    }
  }

  void _queueImageLine(
    String text, {
    String? rightText,
    bool bold = false,
    double? fontSize,
    bool isDivider = false,
  }) {
    _imageLines.add(
      PosReceiptImageLine(
        text: isDivider ? '' : tr(text),
        rightText: rightText == null || rightText.trim().isEmpty
            ? null
            : tr(rightText),
        bold: bold,
        center: _centered,
        fontSize: fontSize ?? _bodyFontSize,
        isDivider: isDivider,
      ),
    );
  }

  /// Hàng ảnh từ mẫu V2 (có cột sale) — khớp A6 Sunmi.
  void queueReceiptImageLine(PosReceiptImageLine line) {
    _imageLines.add(line);
  }

  /// Đẩy batch ảnh ra ESC/POS trước QR/barcode (giữ đúng thứ tự in).
  Future<void> flushImageBatch() async {
    if (!_useImageBatch || _imageLines.isEmpty) return;
    final raster = await PosThermalBitmapEncoder.receiptToRaster(
      _imageLines,
      paperDots: _paperDots,
      frameStyle: _frameStyle,
      frameInsetMm: _frameInsetMm,
      frameMarginMm: _frameMarginMm,
    );
    _imageLines.clear();
    if (raster != null && PosThermalBitmapEncoder.rasterHasInk(raster)) {
      _add(raster);
    }
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

    if (_useImageBatch) {
      _queueImageLine(
        l,
        rightText: r,
        fontSize: _settings.paperWidthMm <= 58 ? 22 : 26,
      );
      return;
    }

    final space = maxChars - l.length - r.length;
    if (space >= 1) {
      await line('$l${' ' * space}$r');
    } else {
      final keep = (maxChars - r.length - 1).clamp(1, maxChars);
      final clipped = l.length > keep ? l.substring(0, keep) : l;
      await line('$clipped $r');
    }
  }

  Future<void> boldPair(String left, String right) async {
    if (_useImageBatch) {
      _queueImageLine(
        left.trim(),
        rightText: right.trim(),
        bold: true,
        fontSize: _settings.paperWidthMm <= 58 ? 24 : 28,
      );
      return;
    }

    _add([0x1B, 0x45, 0x01]);
    await pair(left, right);
    _add([0x1B, 0x45, 0x00]);
  }

  Future<void> separator() async {
    if (_useImageBatch) {
      _queueImageLine('', isDivider: true);
      return;
    }
    left();
    appendRaw(PosThermalBitmapEncoder.horizontalRuleEscPos(
      paperDots: _paperDots,
    ));
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
        frameStyle: _frameStyle,
        frameInsetMm: _frameInsetMm,
        frameMarginMm: _frameMarginMm,
      );
      if (raster != null && PosThermalBitmapEncoder.rasterHasInk(raster)) {
        _add(raster);
      } else {
        // Không bỏ dấu im lặng — giữ UTF-8 có dấu; nếu máy không đọc được
        // user dùng "Thử chế độ chữ" để chọn TCVN/CP1258/Image.
        debugPrint('Raster image failed — fallback UTF-8 có dấu (không strip)');
        for (final ln in _imageLines) {
          final t = ln.text.trim();
          if (t.isEmpty) continue;
          _add(PosEscPosTextCodec.encodeUtf8(ln.text));
          _add([0x0A]);
        }
      }
      _imageLines.clear();
    }

    final n = _settings.resolvedFeedBeforeCut.clamp(1, 28);
    if (!_useImageBatch && !_settings.compactCutFeed) {
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

