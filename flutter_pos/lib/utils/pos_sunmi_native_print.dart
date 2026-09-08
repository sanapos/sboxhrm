import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sbox_pos/shims/sunmi_api_shim.dart';

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
      // K58: chữ vừa khổ, khỏi vỡ cột.
      return const _SunmiReceiptLayout._(
        k58: true,
        chars: 32,
        titleSize: 32,
        bodySize: 20,
        smallSize: 18,
        totalSize: 26,
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

  /// Tôn trọng số dòng đã chỉnh (0 = không đẩy thêm).
  static const _maxFeed = 40;

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
    double vatAmount = 0,
    bool vatIncludedInPrice = true,
    double vatRate = 0,
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
      final feed = _resolveFeed(settings.resolvedFeedBeforeCut);
      final double effectiveVat = vatAmount > 0
          ? vatAmount
          : (vatIncludedInPrice ? 0.0 : order.vatAmount);
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
          vatAmount: effectiveVat,
          vatRate: vatRate,
        );
        if (!ok) return false;
      }
      return true;
    } catch (e) {
      debugPrint('Sunmi native sale print failed: $e');
      return false;
    }
  }

  static int _resolveFeed(int configured, {int min = 0}) {
    if (configured <= 0) return 0;
    final n = configured.clamp(0, _maxFeed);
    return n < min ? min : n;
  }

  static Future<void> _feedPaper(int lines) async {
    await PosPrinterTransport.finishSunmiSlip(feedLines: lines);
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
      final feed = _resolveFeed(settings.resolvedFeedBeforeCut);
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
          text: 'Gọi lúc: $date',
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
      await _printImageLines(layout, img, trailingFeedLines: feed);
      await _feedPaper(feed);
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
        _beginSlipBatch();
        await _center(title, size: layout.titleSize, bold: true);
        await _rule(layout);
        for (final raw in lines) {
          final line = raw.trimRight();
          if (line.isEmpty) {
            _slipBatch?.add(const PosReceiptImageLine(text: ''));
            continue;
          }
          if (line.replaceAll(RegExp(r'[─\-═=]'), '').trim().isEmpty) {
            await _rule(layout);
            continue;
          }
          if (line.contains('──') || line.startsWith('--')) {
            final label =
                line.replaceAll(RegExp(r'[─\-═=\s]+'), ' ').trim();
            if (label.isEmpty) {
              await _rule(layout);
            } else {
              await _center(label, size: layout.smallSize, bold: true);
            }
            continue;
          }
          await _left(line, size: layout.bodySize);
        }
        if (footer != null && footer.trim().isNotEmpty) {
          await _rule(layout);
          await _center(footer.trim(), size: layout.smallSize);
        }
        await _commitSlipBatch(layout, feedLines: feed);
        await PosPrinterTransport.finishSunmiSlip(feedLines: feed);
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
      _beginSlipBatch();

      if (storeName.trim().isNotEmpty) {
        await _center(storeName.trim(), size: layout.titleSize, bold: true);
      }
      await _center('TỔNG KẾT CUỐI NGÀY', size: layout.bodySize + 2, bold: true);
      await _center('Bill $badge', size: layout.smallSize);
      await _rule(layout);

      await _left('NV: $staffLabel', size: layout.bodySize);
      await _left('Từ: $periodFrom', size: layout.smallSize);
      await _left('Đến: $periodTo', size: layout.smallSize);
      await _rule(layout);

      await _center('BÁN HÀNG', size: layout.smallSize, bold: true);
      for (final row in salesRows) {
        await _pair(layout, row.left, row.right, bold: row.bold);
      }
      await _rule(layout);

      if (refundRows.isNotEmpty) {
        await _center('TRẢ / HỦY', size: layout.smallSize, bold: true);
        for (final row in refundRows) {
          await _pair(layout, row.left, row.right, bold: row.bold);
        }
        await _rule(layout);
      }

      await _center('THANH TOÁN', size: layout.smallSize, bold: true);
      for (final row in paymentRows) {
        await _pair(layout, row.left, row.right, bold: row.bold);
      }
      await _rule(layout);
      await _pair(layout, 'THỰC THU', actualReceived, bold: true);
      await _rule(layout);

      if (products.isNotEmpty) {
        await _center('HÀNG BÁN', size: layout.smallSize, bold: true);
        await _rule(layout);
        for (final p in products) {
          final nameMax = layout.chars - 2;
          final chunks = _wrap(p.name, nameMax);
          await _left(chunks.first, size: layout.bodySize, bold: true);
          for (var i = 1; i < chunks.length; i++) {
            await _left(chunks[i], size: layout.smallSize);
          }
          await _pair(layout, '  SL ${p.qty}', p.amount);
        }
        await _rule(layout);
      }

      await _center(footer, size: layout.smallSize);
      await _commitSlipBatch(layout, feedLines: feed);
      await _feedPaper(feed);
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
      final feed = _resolveFeed(settings.resolvedFeedBeforeCut);
      final dots = PosThermalBitmapEncoder.paperDots(settings.paperWidthMm);
      final handheld = !await PosPrinterTransport.sunmiHasAutoCutter();
      for (var c = 0; c < copies.clamp(1, 10); c++) {
        final batch = <PosReceiptImageLine>[];
        _handheldEscAcc = handheld ? <int>[] : null;
        _handheldAccDots = dots;
        Future<void> flushBatch() async {
          if (batch.isEmpty) return;
          final png = await PosThermalBitmapEncoder.receiptToPng(
            List<PosReceiptImageLine>.from(batch),
            paperDots: dots,
            frameStyle: output.frameStyle,
            frameInsetMm: output.frameInsetMm,
            frameMarginMm: output.frameMarginMm,
            trailingFeedLines: 0,
          );
          batch.clear();
          if (png != null) {
            await _emitSunmiPng(png);
          }
        }

        try {
          for (final step in output.steps) {
            if (step is PosPrintCompiledQr) {
              await flushBatch();
              await _printCompiledQr(step, layout);
              continue;
            }
            if (step is PosPrintCompiledBarcode) {
              await flushBatch();
              await _flushHandheldAccNow();
              await _printCompiledBarcode(step);
              continue;
            }
            final img = compiledStepToImageLine(step);
            if (img != null) batch.add(img);
          }
          await flushBatch();
          if (handheld) {
            await _commitHandheldAcc(feedLines: feed, paperDots: dots);
          } else {
            await PosPrinterTransport.finishSunmiSlip(feedLines: feed);
          }
        } finally {
          _handheldEscAcc = null;
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
      final handheld = !await PosPrinterTransport.sunmiHasAutoCutter();
      final layout = _SunmiReceiptLayout.fromMm(handheld ? 58 : paperWidthMm);
      debugPrint(
        'Sunmi testPrint handheld=$handheld feed=$feedLines '
        'mm=${handheld ? 58 : paperWidthMm}',
      );
      // Một ảnh duy nhất — V2s printImage từng dòng sẽ đẩy đuôi trắng rất dài.
      await _printImageLines(layout, [
        _imgCenter(storeLabel, layout.titleSize),
        _imgCenter(
          layout.k58 ? 'Mẫu in thử K58' : 'Mẫu in thử K80',
          layout.bodySize,
        ),
        _imgDiv(),
        _imgCenter('Tiếng Việt: ĂÂÊÔƠƯ Đ', layout.bodySize),
        _imgSale(layout, name: 'Tên hàng', qty: 'SL', price: 'Đ.giá', total: 'T.tiền', header: true),
        _imgSale(layout, name: 'Món thử', qty: '1', price: '2.850.000', total: '2.850.000'),
        _imgDiv(),
        _imgPair(layout, 'TỔNG CỘNG', '125.000 đ', bold: true),
        _imgDiv(),
      ], trailingFeedLines: _resolveFeed(feedLines));
      await _feedPaper(_resolveFeed(feedLines));
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
    double vatAmount = 0,
    double vatRate = 0,
  }) async {
    final saleDate =
        order.saleDate?.toLocal() ?? order.createdAt?.toLocal() ?? DateTime.now();

    final shop = storeName?.trim().isNotEmpty == true
        ? storeName!.trim()
        : 'CỬA HÀNG';
    _beginSlipBatch();
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
    await _rule(layout);

    await _saleItemRow(
      layout,
      name: 'Tên hàng',
      qty: 'SL',
      price: 'Đ.giá',
      total: 'T.T',
      header: true,
    );
    await _rule(layout);

    String moneyCell(double v) => layout.k58
        ? PosReceiptLayout.moneyItemCompact(v)
        : PosReceiptLayout.moneyItem(v);

    for (final line in lines) {
      final saleUnit = line.qty > 0 ? line.lineTotal / line.qty : line.unitPrice;
      final unitPrice =
          line.discountAmount > 0 ? saleUnit : line.unitPrice;
      final name = line.productName.trim().isEmpty ? 'Món' : line.productName.trim();
      await _saleItemRow(
        layout,
        name: name,
        qty: _qty.format(line.qty),
        price: moneyCell(unitPrice),
        total: moneyCell(line.lineTotal),
      );
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

    await _rule(layout);

    final lineDiscount = lines.fold<double>(0, (s, l) => s + l.discountAmount);
    final linesTotal = lines.fold<double>(0, (s, l) => s + l.lineTotal);
    final receiptTotal = warehouseSlip ? linesTotal : order.total;
    final hangTotal = warehouseSlip
        ? linesTotal
        : (order.subTotal > 0 ? order.subTotal : linesTotal);

    await _pair(layout, 'Tổng tiền hàng:', _money.format(hangTotal));
    final ck = order.discount > 0 ? order.discount : lineDiscount;
    if (!warehouseSlip && ck > 0) {
      await _pair(layout, 'Chiết khấu:', _money.format(ck));
    }
    if (!warehouseSlip && vatAmount > 0) {
      final vatLabel = vatRate > 0
          ? 'VAT (${vatRate.toStringAsFixed(vatRate % 1 == 0 ? 0 : 1)}%):'
          : 'VAT:';
      await _pair(layout, vatLabel, _money.format(vatAmount));
    }
    await _pair(
      layout,
      'TỔNG CỘNG:',
      _money.format(receiptTotal),
      bold: true,
    );

    if (warehouseSlip) {
      if (order.note != null && order.note!.trim().isNotEmpty) {
        await _left('Ghi chú: ${order.note!.trim()}', size: layout.smallSize);
      }
      await _commitSlipBatch(layout, feedLines: feedLines);
      await _feedPaper(feedLines);
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
    await _rule(layout);
    await _center('Cảm ơn quý khách!', size: layout.bodySize, bold: true);

    await _commitSlipBatch(layout, feedLines: feedLines);
    await _feedPaper(feedLines);
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
      await _emitSunmiPng(png);
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

  /// Gộp nhiều dòng thành 1 printImage — V2s đẩy đuôi trắng sau mỗi ảnh.
  static List<PosReceiptImageLine>? _slipBatch;

  /// V2s mẫu V2: gom mọi GS v 0 thành 1 printEscPos rồi mới nhồi feed.
  static List<int>? _handheldEscAcc;
  static int _handheldAccDots = 384;

  static Future<void> _flushHandheldAccNow() async {
    final acc = _handheldEscAcc;
    if (acc == null || acc.isEmpty) return;
    await SunmiPrinter.printEscPos(List<int>.from(acc));
    acc.clear();
  }

  static Future<void> _commitHandheldAcc({
    required int feedLines,
    required int paperDots,
  }) async {
    var payload = List<int>.from(_handheldEscAcc ?? const <int>[]);
    _handheldEscAcc = null;
    payload = PosThermalBitmapEncoder.appendHandheldFeed(
      payload,
      feedLines,
      paperDots: paperDots,
    );
    if (payload.isEmpty) return;
    await SunmiPrinter.printEscPos(payload);
  }

  static Future<bool> _tryAccText(
    String text, {
    required int size,
    required bool center,
    bool bold = false,
  }) async {
    if (_handheldEscAcc == null) return false;
    final raster = await PosThermalBitmapEncoder.textLineToRaster(
      text,
      paperDots: _handheldAccDots,
      fontSize: size.toDouble(),
      bold: bold,
      center: center,
    );
    if (raster != null && raster.isNotEmpty) {
      _handheldEscAcc!.addAll(PosPrinterTransport.stripTrailingCut(raster));
    }
    return true;
  }

  static void _beginSlipBatch() {
    _slipBatch = <PosReceiptImageLine>[];
  }

  static Future<void> _commitSlipBatch(
    _SunmiReceiptLayout layout, {
    int feedLines = 0,
  }) async {
    final lines = _slipBatch;
    _slipBatch = null;
    if (lines == null || lines.isEmpty) return;
    await _printImageLines(layout, lines, trailingFeedLines: feedLines);
  }

  static PosReceiptImageLine _imgCenter(String text, int size, {bool bold = true}) =>
      PosReceiptImageLine(
        text: text,
        fontSize: size.toDouble(),
        bold: bold,
        center: true,
      );

  static PosReceiptImageLine _imgLeft(String text, int size, {bool bold = true}) =>
      PosReceiptImageLine(
        text: text,
        fontSize: size.toDouble(),
        bold: bold,
      );

  static PosReceiptImageLine _imgDiv() =>
      const PosReceiptImageLine(text: '', isDivider: true);

  static PosReceiptImageLine _imgPair(
    _SunmiReceiptLayout layout,
    String left,
    String right, {
    bool bold = false,
  }) =>
      PosReceiptImageLine(
        text: left,
        rightText: right,
        fontSize: bold
            ? (layout.k58 ? 22 : 24)
            : (layout.k58 ? 20 : 22).toDouble(),
        bold: true,
      );

  static PosReceiptImageLine _imgSale(
    _SunmiReceiptLayout layout, {
    required String name,
    required String qty,
    required String price,
    required String total,
    bool header = false,
  }) {
    final hasCols = qty.trim().isNotEmpty ||
        price.trim().isNotEmpty ||
        total.trim().isNotEmpty;
    return PosReceiptImageLine(
      text: name,
      colQty: hasCols ? qty : null,
      colPrice: hasCols ? price : null,
      colTotal: hasCols ? total : null,
      fontSize: layout.k58 ? (header ? 17 : 15) : 22,
      bold: header,
    );
  }

  static Future<void> _printImageLines(
    _SunmiReceiptLayout layout,
    List<PosReceiptImageLine> lines, {
    int trailingFeedLines = 0,
  }) async {
    final handheld = !await PosPrinterTransport.sunmiHasAutoCutter();
    final dots = handheld ? 384 : (layout.k58 ? 384 : 576);
    // V2s không dao: printImage của SDK tự đẩy ~1 đoạn giấy sau mỗi ảnh.
    // Raster phải đúng 384 chấm — ảnh scale=2 (768) in GS v 0 sẽ quấn ra thêm 1 khúc.
    if (handheld) {
      final raster = await PosThermalBitmapEncoder.receiptToRaster(
        lines,
        paperDots: dots,
        initPrinter: false,
        keepPx: 0,
      );
      if (raster != null && raster.isNotEmpty) {
        // LF sau GS v 0 bị firmware V2s bỏ qua — số dòng chỉnh không đổi.
        // Nhồi hàng trắng vào chiều cao bitmap (1 dòng = 24 chấm ≈ 3mm).
        final payload = PosThermalBitmapEncoder.appendHandheldFeed(
          PosPrinterTransport.stripTrailingCut(raster),
          trailingFeedLines,
          paperDots: dots,
        );
        await SunmiPrinter.printEscPos(payload);
      }
      return;
    }
    // Máy có dao: feed do finishSunmiSlip (lineWrap + cut) xử lý, không bake ảnh.
    final png = await PosThermalBitmapEncoder.receiptToPng(
      lines,
      paperDots: dots,
      trailingFeedLines: 0,
    );
    if (png != null) {
      await SunmiPrinter.printImage(png, align: SunmiPrintAlign.CENTER);
    }
  }

  static Future<void> _emitSunmiPng(Uint8List png) async {
    if (await PosPrinterTransport.sunmiHasAutoCutter()) {
      await SunmiPrinter.printImage(png, align: SunmiPrintAlign.CENTER);
      return;
    }
    final raster = await PosThermalBitmapEncoder.pngToEscPos(png);
    if (raster == null || raster.isEmpty) return;
    final bytes = PosPrinterTransport.stripTrailingCut(raster);
    if (_handheldEscAcc != null) {
      _handheldEscAcc!.addAll(bytes);
      return;
    }
    await SunmiPrinter.printEscPos(bytes);
  }

  /// Đường kẻ full khổ: font tỉ lệ nên 32 ký tự '=' ở size 18 chỉ ~3/4 giấy K58.
  static Future<void> _rule(_SunmiReceiptLayout layout) async {
    final batch = _slipBatch;
    if (batch != null) {
      batch.add(_imgDiv());
      return;
    }
    final png = await PosThermalBitmapEncoder.horizontalRulePng(
      paperDots: layout.k58 ? 384 : 576,
      thickness: 2,
    );
    if (png != null) {
      await _emitSunmiPng(png);
    }
  }

  static Future<void> _center(String text, {int size = 24, bool bold = false}) async {
    final batch = _slipBatch;
    if (batch != null) {
      batch.add(_imgCenter(text, size, bold: bold));
      return;
    }
    if (await _tryAccText(text, size: size, center: true, bold: bold)) return;
    await SunmiPrinter.printText(
      text,
      style: SunmiTextStyle(
        align: SunmiPrintAlign.CENTER,
        fontSize: size,
        bold: true,
      ),
    );
  }

  static Future<void> _left(String text, {int size = 24, bool bold = false}) async {
    final batch = _slipBatch;
    if (batch != null) {
      batch.add(_imgLeft(text, size, bold: bold));
      return;
    }
    if (await _tryAccText(text, size: size, center: false, bold: bold)) return;
    await SunmiPrinter.printText(
      text,
      style: SunmiTextStyle(
        align: SunmiPrintAlign.LEFT,
        fontSize: size,
        bold: true,
      ),
    );
  }

  static Future<void> _saleItemRow(
    _SunmiReceiptLayout layout, {
    required String name,
    required String qty,
    required String price,
    required String total,
    bool header = false,
  }) async {
    debugPrint('SALE PRINT row name="$name" qty="$qty" price="$price" total="$total"');
    final batch = _slipBatch;
    if (batch != null) {
      batch.add(_imgSale(
        layout,
        name: name,
        qty: qty,
        price: price,
        total: total,
        header: header,
      ));
      return;
    }
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
          fontSize: layout.k58 ? (header ? 17 : 15) : 22,
          bold: header,
        ),
      ],
      paperDots: layout.k58 ? 384 : 576,
    );
    if (png != null) {
      await _emitSunmiPng(png);
    }
  }

  static Future<void> _pair(
    _SunmiReceiptLayout layout,
    String left,
    String right, {
    bool bold = false,
  }) async {
    final batch = _slipBatch;
    if (batch != null) {
      batch.add(_imgPair(layout, left, right, bold: bold));
      return;
    }
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
      await _emitSunmiPng(png);
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
