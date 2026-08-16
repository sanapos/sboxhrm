import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';

import '../models/pos_sale_order.dart';
import 'pos_print_template_compiler.dart';
import 'pos_printer_transport.dart';
import 'pos_receipt_layout.dart';
import 'pos_table_label.dart';
import 'pos_topping_format.dart';
import 'pos_thermal_bitmap.dart';
import 'pos_thermal_printer_settings.dart';
import '../l10n/app_tr.dart';

/// Layout hóa đơn theo khổ giấy — cột vừa khổ, không dư khoảng trống.
class _SunmiReceiptLayout {
  const _SunmiReceiptLayout._({
    required this.k58,
    required this.chars,
    required this.titleSize,
    required this.bodySize,
    required this.smallSize,
    required this.totalSize,
    required this.colLeft,
    required this.colRight,
    required this.itemLeft,
    required this.itemRight,
  });

  factory _SunmiReceiptLayout.fromMm(int paperWidthMm) {
    final k58 = paperWidthMm <= 58;
    if (k58) {
      // K57/K58: chữ to, cột đủ 32 để căn hết khổ.
      return const _SunmiReceiptLayout._(
        k58: true,
        chars: 32,
        titleSize: 40,
        bodySize: 26,
        smallSize: 22,
        totalSize: 32,
        colLeft: 20,
        colRight: 12,
        itemLeft: 20,
        itemRight: 12,
      );
    }
    return const _SunmiReceiptLayout._(
      k58: false,
      chars: 48,
      titleSize: 44,
      bodySize: 30,
      smallSize: 24,
      totalSize: 38,
      colLeft: 30,
      colRight: 18,
      itemLeft: 32,
      itemRight: 16,
    );
  }

  final bool k58;
  final int chars;
  final int titleSize;
  final int bodySize;
  final int smallSize;
  final int totalSize;
  final int colLeft;
  final int colRight;
  final int itemLeft;
  final int itemRight;

  String get dash => List.filled(chars, '-').join();
  String get equals => List.filled(chars, '=').join();
}

/// In hóa đơn Sunmi — mẫu K58/K80 rõ hàng, đậm tổng, đẩy giấy đủ sau in.
class PosSunmiNativePrint {
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

  /// Đẩy giấy tới mép xé Sunmi V2s (~3–4 cm). Provisional trước đó chỉ feed 4 → kẹt giấy.
  static const _minFeedSunmi = 18;
  static const _minFeedKitchen = 6;
  static const _maxFeed = 28;

  static Future<bool> printSaleOrder(
    PosSaleOrder order, {
    required PosThermalPrinterSettings settings,
    String? storeName,
    String? storeAddress,
    String? storePhone,
    bool mergeSameItems = true,
    int copies = 1,
    bool warehouseSlip = false,
    String? slipTitle,
    String? documentTitle,
    List<PosSaleOrderLine>? linesOverride,
  }) async {
    if (kIsWeb || !settings.enabled) return false;
    if (!await PosPrinterTransport.isSunmiDevice()) return false;

    try {
      final bound = await PosPrinterTransport.ensureSunmiBound();
      if (!bound) return false;

      final layout = _SunmiReceiptLayout.fromMm(settings.paperWidthMm);
      final raw = linesOverride ?? order.lines;
      final lines = mergeSameItems ? _mergeLines(raw) : raw;
      final titleOverride = slipTitle ?? documentTitle;
      // HĐ / tạm tính đều đẩy giấy đủ — không dùng feed kho ngắn.
      final feed = warehouseSlip
          ? _resolveFeed(settings.resolvedFeedBeforeCut, min: _minFeedKitchen)
          : _resolveFeed(settings.resolvedFeedBeforeCut, min: _minFeedSunmi);
      for (var c = 0; c < copies.clamp(1, 10); c++) {
        final ok = await _printOne(
          order: order,
          lines: lines,
          layout: layout,
          storeName: storeName,
          storeAddress: storeAddress,
          storePhone: storePhone,
          feedLines: feed,
          warehouseSlip: warehouseSlip,
          slipTitle: titleOverride,
          documentTitle: documentTitle,
        );
        if (!ok) return false;
      }
      return true;
    } catch (e) {
      debugPrint('Sunmi native sale print failed: $e');
      return false;
    }
  }

  static int _resolveFeed(int configured, {int min = _minFeedSunmi}) {
    final n = configured.clamp(3, _maxFeed);
    return n < min ? min : n;
  }

  static Future<void> _feedPaper(int lines) async {
    final n = lines.clamp(8, _maxFeed);
    await SunmiPrinter.lineWrap(n);
    // Thêm dòng trống — đầu in Sunmi cách mép xé khá xa.
    for (var i = 0; i < 4; i++) {
      await SunmiPrinter.printText(
        ' ',
        style: SunmiTextStyle(fontSize: 18),
      );
    }
  }

  /// Báo cáo dạng dòng chữ (tổng kết cuối ngày, v.v.) — UTF-8 native.

  /// Phiếu bếp/hủy — ảnh 576 điểm (T1 cắt printRow 22+8).
  static Future<bool> printKitchenSlip({
    required String tableName,
    required bool isCancel,
    required List<({String name, String qty, String? unit, String? note})> lines,
    required String senderName,
    required String orderNo,
    required DateTime sentAt,
    required PosThermalPrinterSettings settings,
  }) async {
    if (kIsWeb || !settings.enabled) return false;
    if (!await PosPrinterTransport.isSunmiDevice()) return false;
    if (lines.isEmpty) return false;

    try {
      final bound = await PosPrinterTransport.ensureSunmiBound();
      if (!bound) return false;

      final layout = _SunmiReceiptLayout.fromMm(settings.paperWidthMm);
      final feed = _resolveFeed(settings.resolvedFeedBeforeCut, min: _minFeedKitchen);
      final date = DateFormat('dd/MM/yyyy HH:mm').format(sentAt);
      final img = <PosReceiptImageLine>[
        PosReceiptImageLine(
          text: tableName.trim().isEmpty ? 'Bàn' : tableName.trim(),
          fontSize: 26,
          bold: true,
          center: true,
        ),
        PosReceiptImageLine(
          text: isCancel ? '*** PHIẾU HỦY ***' : '*** BÁO CHẾ BIẾN ***',
          fontSize: 24,
          bold: true,
          center: true,
        ),
        PosReceiptImageLine(
          text: 'Mã HĐ: ${orderNo.isEmpty ? '-' : PosReceiptLayout.formatSaleInvoiceNo(orderNo)}',
          fontSize: 20,
          bold: true,
        ),
        PosReceiptImageLine(
          text: 'NV: $senderName',
          fontSize: 20,
          bold: true,
        ),
        PosReceiptImageLine(
          text: 'Ngày: $date',
          fontSize: 20,
          bold: true,
        ),
        const PosReceiptImageLine(text: '', isDivider: true),
        const PosReceiptImageLine(
          text: 'Tên hàng',
          rightText: '',
          rightSlotFrac: 0.20,
          fontSize: 20,
          bold: true,
        ),
        const PosReceiptImageLine(text: '', isDivider: true),
      ];
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        final u = (l.unit ?? '').trim();
        final right = u.isEmpty ? l.qty : '${l.qty} $u';
        img.add(PosReceiptImageLine(
          text: '${i + 1}. ${l.name}',
          rightText: right,
          rightSlotFrac: 0.20,
          fontSize: 22,
          bold: true,
        ));
        final note = (l.note ?? '').trim();
        if (note.isNotEmpty) {
          for (final raw in note.split(RegExp(r'[\r\n]+'))) {
            final part = raw.trim();
            if (part.isEmpty) continue;
            final topping = part.startsWith('+');
            img.add(PosReceiptImageLine(
              text: topping ? '  $part' : '  * $part',
              fontSize: 14,
              bold: false,
            ));
          }
        }
      }
      img.add(const PosReceiptImageLine(text: '', isDivider: true));
      await _printImageLines(layout, img);
      await _feedPaper(feed);
      try {
        await SunmiPrinter.cutPaper();
      } catch (e) {
        debugPrint('Sunmi cutPaper: $e');
      }
      return PosPrinterTransport.verifySunmiAfterPrint();
    } catch (e) {
      debugPrint('Sunmi kitchen slip failed: $e');
      return false;
    }
  }

  static Future<bool> printTextReport({
    required String title,
    required List<String> lines,
    required PosThermalPrinterSettings settings,
    String? footer,
    int copies = 1,
  }) async {
    if (kIsWeb || !settings.enabled) return false;
    if (!await PosPrinterTransport.isSunmiDevice()) return false;

    try {
      final bound = await PosPrinterTransport.ensureSunmiBound();
      if (!bound) return false;

      final layout = _SunmiReceiptLayout.fromMm(settings.paperWidthMm);
      final feed = _resolveFeed(settings.resolvedFeedBeforeCut);
      for (var c = 0; c < copies.clamp(1, 10); c++) {
        await _center(title, size: layout.titleSize, bold: true);
        await _rule(layout.equals);
        for (final raw in lines) {
          final line = raw.trimRight();
          if (line.isEmpty) {
            await SunmiPrinter.printText(' ');
            continue;
          }
          if (line.replaceAll(RegExp(r'[─\-═=]'), '').trim().isEmpty) {
            await _rule(layout.dash);
            continue;
          }
          if (line.contains('──') || line.startsWith('--')) {
            final label =
                line.replaceAll(RegExp(r'[─\-═=\s]+'), ' ').trim();
            if (label.isEmpty) {
              await _rule(layout.dash);
            } else {
              await _center(label, size: layout.smallSize, bold: true);
            }
            continue;
          }
          await _left(line, size: layout.bodySize);
        }
        if (footer != null && footer.trim().isNotEmpty) {
          await _rule(layout.dash);
          await _center(footer.trim(), size: layout.smallSize);
        }
        await _feedPaper(feed);
        try {
          await SunmiPrinter.cutPaper();
        } catch (e) {
          debugPrint('Sunmi cutPaper: $e');
        }
      }
      return true;
    } catch (e) {
      debugPrint('Sunmi native text report failed: $e');
      return false;
    }
  }

  /// Tổng kết cuối ngày — layout chuyên nghiệp K58/K80 (cặp nhãn/số tiền).
  static Future<bool> printEndOfDayReport({
    required String storeName,
    required String staffLabel,
    required String periodFrom,
    required String periodTo,
    required List<({String left, String right, bool bold})> salesRows,
    required List<({String left, String right, bool bold})> refundRows,
    required List<({String left, String right, bool bold})> paymentRows,
    required String actualReceived,
    required List<({String name, String qty, String amount})> products,
    required String footer,
    required PosThermalPrinterSettings settings,
    String? paperBadge,
  }) async {
    if (kIsWeb || !settings.enabled) return false;
    if (!await PosPrinterTransport.isSunmiDevice()) return false;

    try {
      final bound = await PosPrinterTransport.ensureSunmiBound();
      if (!bound) return false;

      final layout = _SunmiReceiptLayout.fromMm(settings.paperWidthMm);
      final feed = _resolveFeed(settings.resolvedFeedBeforeCut);
      final badge = paperBadge ?? (layout.k58 ? 'K58' : 'K80');

      if (storeName.trim().isNotEmpty) {
        await _center(storeName.trim(), size: layout.titleSize, bold: true);
      }
      await _center('TỔNG KẾT CUỐI NGÀY', size: layout.bodySize + 2, bold: true);
      await _center('Bill $badge', size: layout.smallSize);
      await _rule(layout.equals);

      await _left('NV: $staffLabel', size: layout.bodySize);
      await _left('Từ: $periodFrom', size: layout.smallSize);
      await _left('Đến: $periodTo', size: layout.smallSize);
      await _rule(layout.dash);

      await _center('BÁN HÀNG', size: layout.smallSize, bold: true);
      for (final row in salesRows) {
        await _pair(layout, row.left, row.right, bold: row.bold);
      }
      await _rule(layout.dash);

      if (refundRows.isNotEmpty) {
        await _center('TRẢ / HỦY', size: layout.smallSize, bold: true);
        for (final row in refundRows) {
          await _pair(layout, row.left, row.right, bold: row.bold);
        }
        await _rule(layout.dash);
      }

      await _center('THANH TOÁN', size: layout.smallSize, bold: true);
      for (final row in paymentRows) {
        await _pair(layout, row.left, row.right, bold: row.bold);
      }
      await _rule(layout.equals);
      await _pair(layout, 'THỰC THU', actualReceived, bold: true);
      await _rule(layout.equals);

      if (products.isNotEmpty) {
        await _center('HÀNG BÁN', size: layout.smallSize, bold: true);
        await _rule(layout.dash);
        for (final p in products) {
          final nameMax = layout.chars - 2;
          final chunks = _wrap(p.name, nameMax);
          await _left(chunks.first, size: layout.bodySize, bold: true);
          for (var i = 1; i < chunks.length; i++) {
            await _left(chunks[i], size: layout.smallSize);
          }
          await _pair(layout, '  SL ${p.qty}', p.amount);
        }
        await _rule(layout.dash);
      }

      await _center(footer, size: layout.smallSize);
      await _feedPaper(feed);
      try {
        await SunmiPrinter.cutPaper();
      } catch (e) {
        debugPrint('Sunmi cutPaper: $e');
      }
      return true;
    } catch (e) {
      debugPrint('Sunmi EOD report failed: $e');
      return false;
    }
  }

  static Future<bool> printCompiled({
    required PosPrintCompiledOutput output,
    required PosThermalPrinterSettings settings,
    int copies = 1,
    bool kitchenFeed = false,
  }) async {
    if (kIsWeb || !settings.enabled) return false;
    if (!await PosPrinterTransport.isSunmiDevice()) return false;
    try {
      final bound = await PosPrinterTransport.ensureSunmiBound();
      if (!bound) return false;
      final layout = _SunmiReceiptLayout.fromMm(settings.paperWidthMm);
      final feed = _resolveFeed(
        settings.resolvedFeedBeforeCut,
        min: kitchenFeed ? _minFeedKitchen : _minFeedSunmi,
      );
      final dots = PosThermalBitmapEncoder.paperDots(settings.paperWidthMm);
      for (var c = 0; c < copies.clamp(1, 10); c++) {
        final batch = <PosReceiptImageLine>[];
        Future<void> flushBatch() async {
          if (batch.isEmpty) return;
          final png = await PosThermalBitmapEncoder.receiptToPng(
            List<PosReceiptImageLine>.from(batch),
            paperDots: dots,
          );
          batch.clear();
          if (png != null) {
            await SunmiPrinter.printImage(
              png,
              align: SunmiPrintAlign.CENTER,
            );
          }
        }

        for (final step in output.steps) {
          if (step is PosPrintCompiledQr) {
            await flushBatch();
            await _printCompiledQr(step, layout);
            continue;
          }
          if (step is PosPrintCompiledBarcode) {
            await flushBatch();
            await _printCompiledBarcode(step);
            continue;
          }
          final img = compiledStepToImageLine(step);
          if (img != null) batch.add(img);
        }
        await flushBatch();
        await _feedPaper(feed);
        try {
          await SunmiPrinter.cutPaper();
        } catch (e) {
          debugPrint('Sunmi cutPaper: $e');
        }
      }
      return PosPrinterTransport.verifySunmiAfterPrint();
    } catch (e) {
      debugPrint('Sunmi compiled print failed: $e');
      return false;
    }
  }

  static Future<bool> printTest({
    String storeLabel = 'SBOX POS',
    int feedLines = 14,
    int paperWidthMm = 58,
  }) async {
    if (kIsWeb || !await PosPrinterTransport.isSunmiDevice()) return false;
    try {
      final bound = await PosPrinterTransport.ensureSunmiBound();
      if (!bound) return false;
      final layout = _SunmiReceiptLayout.fromMm(paperWidthMm);

      await _center(storeLabel, size: layout.titleSize, bold: true);
      await _center(
        layout.k58 ? 'Mẫu in thử K58' : 'Mẫu in thử K80',
        size: layout.bodySize,
        bold: true,
      );
      await _rule(layout.dash);
      await _center('Tiếng Việt: ĂÂÊÔƠƯ Đ', size: layout.bodySize);
      await _saleItemRow(
        layout,
        name: 'Tên hàng',
        qty: 'SL',
        price: 'Đ.giá',
        total: 'T.tiền',
      );
      await _saleItemRow(
        layout,
        name: 'Món thử',
        qty: '1',
        price: '2.850.000',
        total: '2.850.000',
      );
      await _rule(layout.dash);
      await _pair(layout, 'TỔNG CỘNG', '125.000 đ', bold: true);
      await _rule(layout.equals);
      await _feedPaper(_resolveFeed(feedLines));
      try {
        await SunmiPrinter.cutPaper();
      } catch (e) {
        debugPrint('Sunmi cutPaper: $e');
      }
      return true;
    } catch (e) {
      debugPrint('Sunmi native test print failed: $e');
      return false;
    }
  }

  static Future<bool> _printOne({
    required PosSaleOrder order,
    required List<PosSaleOrderLine> lines,
    required _SunmiReceiptLayout layout,
    String? storeName,
    String? storeAddress,
    String? storePhone,
    required int feedLines,
    bool warehouseSlip = false,
    String? slipTitle,
    String? documentTitle,
  }) async {
    final saleDate =
        order.saleDate?.toLocal() ?? order.createdAt?.toLocal() ?? DateTime.now();

    final shop = storeName?.trim().isNotEmpty == true
        ? storeName!.trim()
        : 'CỬA HÀNG';
    await _center(shop, size: layout.titleSize, bold: true);
    if (storeAddress != null && storeAddress.trim().isNotEmpty) {
      await _center('DC: ${storeAddress.trim()}', size: layout.smallSize, bold: true);
    }
    if (storePhone != null && storePhone.trim().isNotEmpty) {
      await _center('SDT: ${storePhone.trim()}', size: layout.smallSize, bold: true);
    }

    final titleOverride = (documentTitle ?? slipTitle)?.trim();
    final isProvisional =
        (titleOverride ?? '').toUpperCase().contains('TẠM');
    if (warehouseSlip) {
      final title = (slipTitle != null && slipTitle.trim().isNotEmpty)
          ? slipTitle.trim()
          : 'PHIẾU XUẤT KHO';
      await _center(title, size: layout.titleSize - 2, bold: true);
    } else {
      final isReprint = order.printCount > 1 && !isProvisional;
      // Cùng layout HĐ bán — tạm tính chỉ đổi tiêu đề + dòng cảnh báo (không đổi cỡ/màu cột).
      await _center(
        (titleOverride != null && titleOverride.isNotEmpty)
            ? titleOverride
            : (isReprint ? 'HÓA ĐƠN BÁN HÀNG — IN LẠI' : 'HÓA ĐƠN BÁN HÀNG'),
        size: layout.titleSize - 2,
        bold: true,
      );
      if (isProvisional) {
        await _center(
          '*** CHƯA THANH TOÁN ***',
          size: layout.smallSize,
          bold: true,
        );
      } else if ((titleOverride == null || titleOverride.isEmpty) && isReprint) {
        await _center(
          '*** BẢN IN LẠI — Lần in thứ ${order.printCount} ***',
          size: layout.smallSize,
          bold: true,
        );
      }
    }

    await _left(
      'Số HĐ: ${order.orderNo.isEmpty ? '-' : PosReceiptLayout.formatSaleInvoiceNo(order.orderNo)}',
      size: layout.bodySize,
      bold: true,
    );
    final tableLine = formatPosTableOneLine(
      areaName: order.serviceAreaName,
      tableName: order.serviceResourceName ?? order.serviceResourceCode,
    );
    if (tableLine.isNotEmpty) {
      await _left(tableLine, size: layout.bodySize, bold: true);
    }
    await _left(
      'Ngày: ${DateFormat('dd/MM/yyyy HH:mm').format(saleDate)}',
      size: layout.bodySize,
      bold: true,
    );
    final inAt = order.serviceStartedAt?.toLocal();
    if (inAt != null) {
      await _left('Giờ vào: ${_date.format(inAt)}',
          size: layout.bodySize, bold: true);
    }
    // Tạm tính: không in Giờ ra giả; chỉ in khi đã đóng phiên / thanh toán.
    final outAt = order.serviceEndedAt?.toLocal();
    if (outAt != null && !warehouseSlip && !isProvisional) {
      await _left('Giờ ra: ${_date.format(outAt)}',
          size: layout.bodySize, bold: true);
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
          await _left(
            'Thời lượng: $wallLabel (tính ${_fmtTimedMinutes(bill)})',
            size: layout.bodySize,
            bold: true,
          );
        } else {
          await _left('Thời lượng: $wallLabel',
              size: layout.bodySize, bold: true);
        }
      } else if (bill != null && bill > 0) {
        await _left('Thời lượng tính: ${_fmtTimedMinutes(bill)}',
            size: layout.bodySize, bold: true);
      }
    }
    await _left(
      'KH: ${order.customerName ?? 'Khách lẻ'}',
      size: layout.bodySize,
      bold: true,
    );
    if (order.soldBy != null && order.soldBy!.trim().isNotEmpty) {
      final nv = order.soldBy!.trim();
      // Không in tên thiết bị lên phiếu.
      final looksDevice = nv.toUpperCase().contains('SUNMI') ||
          nv.toUpperCase().contains('V2S') ||
          nv.toUpperCase().contains('_GL');
      if (!looksDevice) {
        await _left('Thu ngân: $nv', size: layout.bodySize, bold: true);
      }
    }
    await _rule(layout.equals);

    // printRow width phải = 12. Cột 5+1+3+3: tên trái, SL/Đ.giá/T.tiền phải.
    final cols = PosReceiptLayout.fromMm(layout.k58 ? 58 : 80);
    await _saleItemRow(
      layout,
      name: 'Tên hàng',
      qty: 'SL',
      price: 'Đ.giá',
      total: 'T.tiền',
    );
    await _rule(layout.equals);

    String moneyCell(double v) => PosReceiptLayout.moneyItemCompact(v);

    for (final line in lines) {
      final saleUnit = line.qty > 0 ? line.lineTotal / line.qty : line.unitPrice;
      final unitPrice =
          line.discountAmount > 0 ? saleUnit : line.unitPrice;
      final name = line.productName.trim().isEmpty ? 'Món' : line.productName.trim();
      final chunks = PosReceiptLayout.wrap(name, cols.nameW);
      await _saleItemRow(
        layout,
        name: chunks.first,
        qty: _qty.format(line.qty),
        price: moneyCell(unitPrice),
        total: moneyCell(line.lineTotal),
      );
      for (var i = 1; i < chunks.length; i++) {
        await _saleItemRow(
          layout,
          name: chunks[i],
          qty: '',
          price: '',
          total: '',
        );
      }
      if (line.discountAmount > 0) {
        await _saleItemRow(
          layout,
          name: '  ~${moneyCell(line.unitPrice)}',
          qty: '',
          price: '',
          total: '',
        );
      }
      final note = posToppingNoteFromSaleLine(line, withPrice: true);
      if (note.isNotEmpty) {
        for (final part in note.split('\n')) {
          final t = part.trim();
          if (t.isEmpty) continue;
          await _left(t.startsWith('+') ? '  $t' : ' * $t', size: layout.smallSize);
        }
      }
    }

    await _rule(layout.equals);

    final lineDiscount = lines.fold<double>(0, (s, l) => s + l.discountAmount);
    final linesTotal = lines.fold<double>(0, (s, l) => s + l.lineTotal);
    final receiptTotal = warehouseSlip ? linesTotal : order.total;
    final hangTotal = warehouseSlip
        ? linesTotal
        : (order.subTotal > 0 ? order.subTotal : linesTotal);

    await _pair(layout, 'Tổng thành tiền:', _money.format(hangTotal));
    final ck = order.discount > 0 ? order.discount : lineDiscount;
    if (!warehouseSlip && ck > 0) {
      await _pair(layout, 'Chiết khấu:', _money.format(ck));
    }
    await _pair(
      layout,
      'Tổng cộng:',
      _money.format(receiptTotal),
      bold: true,
    );

    if (warehouseSlip) {
      if (order.note != null && order.note!.trim().isNotEmpty) {
        await _left('Ghi chú: ${order.note!.trim()}', size: layout.smallSize);
      }
      await _feedPaper(feedLines);
      try {
        await SunmiPrinter.cutPaper();
      } catch (e) {
        debugPrint('Sunmi cutPaper: $e');
      }
      return PosPrinterTransport.verifySunmiAfterPrint();
    }

    await _pair(layout, 'Thanh toán:', _money.format(order.paidAmount));
    if (order.balanceDue > 0) {
      await _pair(
        layout,
        'Còn nợ:',
        _money.format(order.balanceDue),
        bold: true,
      );
    }
    if (order.note != null && order.note!.trim().isNotEmpty) {
      await _left('Ghi chú: ${order.note!.trim()}', size: layout.smallSize);
    }
    await _rule(layout.equals);
    await _center('Cam on quy khach!', size: layout.bodySize, bold: true);

    await _feedPaper(feedLines);
    try {
      await SunmiPrinter.cutPaper();
    } catch (e) {
      debugPrint('Sunmi cutPaper: $e');
    }
    return PosPrinterTransport.verifySunmiAfterPrint();
  }

  static Future<void> _printCompiledQr(
    PosPrintCompiledQr qr,
    _SunmiReceiptLayout layout,
  ) async {
    if (qr.title != null && qr.title!.trim().isNotEmpty) {
      await _center(qr.title!.trim(), size: layout.smallSize, bold: true);
    }
    final dots = layout.k58 ? 384 : 576;
    final png = await PosThermalBitmapEncoder.qrCenteredOnPaper(
      qr.imageUrl,
      paperDots: dots,
    );
    if (png != null) {
      await SunmiPrinter.printImage(png, align: SunmiPrintAlign.CENTER);
    }
    if (qr.caption.trim().isNotEmpty) {
      await _center(qr.caption.trim(), size: layout.smallSize, bold: true);
    }
    if (qr.amountText != null && qr.amountText!.trim().isNotEmpty) {
      await _center('${qr.amountText!.trim()} đ', size: layout.bodySize, bold: true);
    }
  }

  static Future<void> _printCompiledBarcode(PosPrintCompiledBarcode barcode) async {
    final data = barcode.data.trim();
    if (data.isEmpty) return;
    try {
      await SunmiPrinter.printBarCode(
        data,
        style: SunmiBarcodeStyle(
          type: SunmiBarcodeType.CODE128,
          height: barcode.height.clamp(40, 162),
          size: 2,
          textPos: barcode.showText
              ? SunmiBarcodeTextPos.TEXT_UNDER
              : SunmiBarcodeTextPos.NO_TEXT,
          align: SunmiPrintAlign.CENTER,
        ),
      );
    } catch (e) {
      debugPrint('Sunmi barcode failed, fallback text: $e');
      await _center(data, size: 22, bold: true);
    }
  }

  static Future<void> _printImageLines(
    _SunmiReceiptLayout layout,
    List<PosReceiptImageLine> lines,
  ) async {
    final png = await PosThermalBitmapEncoder.receiptToPng(
      lines,
      paperDots: layout.k58 ? 384 : 576,
    );
    if (png != null) {
      await SunmiPrinter.printImage(png, align: SunmiPrintAlign.CENTER);
    }
  }

  /// Đường kẻ full khổ — ảnh, không dùng chuỗi '=' (T1 cắt/thiếu khổ).
  static Future<void> _rule(Object layoutOrSample) async {
    final k58 = layoutOrSample is _SunmiReceiptLayout
        ? layoutOrSample.k58
        : layoutOrSample.toString().length <= 40;
    final png = await PosThermalBitmapEncoder.horizontalRulePng(
      paperDots: k58 ? 384 : 576,
      thickness: 2,
    );
    if (png != null) {
      await SunmiPrinter.printImage(png, align: SunmiPrintAlign.CENTER);
    }
  }

  static Future<void> _center(String text, {int size = 24, bool bold = false}) =>
      SunmiPrinter.printText(
        text,
        style: SunmiTextStyle(
          align: SunmiPrintAlign.CENTER,
          fontSize: size,
          bold: true, // Sunmi: luôn đậm để nét rõ trên giấy nhiệt
        ),
      );

  static Future<void> _left(String text, {int size = 24, bool bold = false}) =>
      SunmiPrinter.printText(
        text,
        style: SunmiTextStyle(
          align: SunmiPrintAlign.LEFT,
          fontSize: size,
          bold: true, // nhiệt: luôn đậm cho nét rõ
        ),
      );

  /// Hàng hóa / tổng: vẽ ảnh đúng 576 điểm — T1 cắt printRow ở mép phải.
  static Future<void> _saleItemRow(
    _SunmiReceiptLayout layout, {
    required String name,
    required String qty,
    required String price,
    required String total,
  }) async {
    debugPrint('SALE PRINT row name="$name" qty="$qty" price="$price" total="$total"');
    final hasCols = qty.trim().isNotEmpty ||
        price.trim().isNotEmpty ||
        total.trim().isNotEmpty;
    final png = await PosThermalBitmapEncoder.receiptToPng(
      [
        PosReceiptImageLine(
          text: name,
          colQty: hasCols ? qty : null,
          colPrice: hasCols ? price : null,
          colTotal: hasCols ? total : null,
          fontSize: layout.k58 ? 20 : 22,
          bold: true,
        ),
      ],
      paperDots: layout.k58 ? 384 : 576,
    );
    if (png != null) {
      await SunmiPrinter.printImage(png, align: SunmiPrintAlign.CENTER);
    }
  }

  static Future<void> _pair(
    _SunmiReceiptLayout layout,
    String left,
    String right, {
    bool bold = false,
  }) async {
    final png = await PosThermalBitmapEncoder.receiptToPng(
      [
        PosReceiptImageLine(
          text: left,
          rightText: right,
          fontSize: bold
              ? (layout.k58 ? 22 : 24)
              : (layout.k58 ? 20 : 22),
          bold: true,
        ),
      ],
      paperDots: layout.k58 ? 384 : 576,
    );
    if (png != null) {
      await SunmiPrinter.printImage(png, align: SunmiPrintAlign.CENTER);
    }
  }

  static List<String> _wrap(String text, int maxChars) {
    if (text.length <= maxChars) return [text];
    final out = <String>[];
    var rest = text;
    while (rest.length > maxChars) {
      out.add(rest.substring(0, maxChars));
      rest = rest.substring(maxChars);
    }
    if (rest.isNotEmpty) out.add(rest);
    return out;
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
          discountAmount: hit.discountAmount + l.discountAmount,
          lineTotal: hit.lineTotal + l.lineTotal,
          lineNote: [
            if (hit.lineNote != null && hit.lineNote!.isNotEmpty) hit.lineNote,
            if (l.lineNote != null && l.lineNote!.isNotEmpty) l.lineNote,
          ].join('; '),
        );
      }
    }
    return map.values.toList();
  }
}
