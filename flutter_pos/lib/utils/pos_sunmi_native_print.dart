import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sbox_pos/shims/sunmi_api_shim.dart';

import '../models/pos_sale_order.dart';
import 'pos_print_template_compiler.dart';
import 'pos_printer_transport.dart';
import 'pos_table_label.dart';
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

  /// Tôn trọng feed cấu hình; phiếu bếp/kho có sàn tối thiểu để khỏi cắt mất món.
  static const _minFeedSunmi = 8;
  static const _minFeedKitchen = 6;
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
      final feed = warehouseSlip
          ? _resolveFeed(settings.resolvedFeedBeforeCut, min: _minFeedKitchen)
          : _resolveFeed(settings.resolvedFeedBeforeCut, min: _minFeedSunmi);
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
    final n = configured.clamp(0, _maxFeed);
    return n < min ? min : n;
  }

  static Future<void> _feedPaper(int lines) async {
    final n = lines.clamp(0, _maxFeed);
    if (n <= 0) return;
    await SunmiPrinter.lineWrap(n);
  }

  /// Báo cáo dạng dòng chữ (tổng kết cuối ngày, v.v.) — UTF-8 native.

  /// Phiếu bếp/hủy — dùng printRow (không pad khoảng trắng) để khỏi xuống hàng trên Sunmi.
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
      final feed =
          _resolveFeed(settings.resolvedFeedBeforeCut, min: _minFeedKitchen);
      final date = DateFormat('dd/MM/yyyy HH:mm').format(sentAt);

      await _center(tableName.trim().isEmpty ? 'Bàn' : tableName.trim(),
          size: layout.titleSize, bold: true);
      await _center(
        isCancel ? '*** PHIẾU HỦY ***' : '*** BÁO CHẾ BIẾN ***',
        size: layout.titleSize - 2,
        bold: true,
      );
      await _left('Mã HĐ: ${orderNo.isEmpty ? '-' : orderNo}',
          size: layout.bodySize, bold: true);
      await _left('NV: $senderName', size: layout.bodySize, bold: true);
      await _left('Ngày: $date', size: layout.bodySize, bold: true);
      await _rule(layout);

      await SunmiPrinter.printRow(
        cols: [
          SunmiColumn(
            text: tr('Tên hàng'),
            width: 22,
            style: SunmiTextStyle(fontSize: layout.bodySize, bold: true),
          ),
          SunmiColumn(
            text: tr('SL'),
            width: 8,
            style: SunmiTextStyle(
              fontSize: layout.bodySize,
              bold: true,
              align: SunmiPrintAlign.RIGHT,
            ),
          ),
        ],
      );
      await _rule(layout);

      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        final u = (l.unit ?? '').trim();
        final right = u.isEmpty ? l.qty : '${l.qty} $u';
        await SunmiPrinter.printRow(
          cols: [
            SunmiColumn(
              text: tr('${i + 1}. ${l.name}'),
              width: 22,
              style: SunmiTextStyle(fontSize: layout.bodySize, bold: true),
            ),
            SunmiColumn(
              text: tr(right),
              width: 8,
              style: SunmiTextStyle(
                fontSize: layout.bodySize,
                bold: true,
                align: SunmiPrintAlign.RIGHT,
              ),
            ),
          ],
        );
        final note = (l.note ?? '').trim();
        if (note.isNotEmpty) {
          await _left(' * $note', size: layout.smallSize);
        }
      }
      await _rule(layout);
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
        await _rule(layout);
        for (final raw in lines) {
          final line = raw.trimRight();
          if (line.isEmpty) {
            await SunmiPrinter.printText(' ');
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
          await SunmiPrinter.printRow(
            cols: [
              SunmiColumn(
                text: tr('  SL ${p.qty}'),
                width: layout.itemLeft,
                style: SunmiTextStyle(fontSize: layout.smallSize, bold: true),
              ),
              SunmiColumn(
                text: tr(p.amount),
                width: layout.itemRight,
                style: SunmiTextStyle(
                  fontSize: layout.smallSize,
                  bold: true,
                  align: SunmiPrintAlign.RIGHT,
                ),
              ),
            ],
          );
        }
        await _rule(layout);
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
      for (var c = 0; c < copies.clamp(1, 10); c++) {
        for (final step in output.steps) {
          if (step is PosPrintCompiledLine) {
            final line = step;
            if (line.isDivider) {
              final png = await PosThermalBitmapEncoder.horizontalRulePng(
                paperDots: PosThermalBitmapEncoder.paperDots(
                  settings.paperWidthMm,
                ),
              );
              if (png != null) {
                await SunmiPrinter.printImage(
                  png,
                  align: SunmiPrintAlign.CENTER,
                );
              }
              continue;
            }
            final size = layout.k58
                ? line.fontSize.round()
                : line.fontSize.round().clamp(layout.bodySize, 48);
            if (line.center) {
              await _center(line.text, size: size, bold: line.bold);
            } else if (line.right) {
              await SunmiPrinter.printText(
                line.text,
                style: SunmiTextStyle(
                  align: SunmiPrintAlign.RIGHT,
                  fontSize: size,
                  bold: true,
                ),
              );
            } else {
              await _left(line.text, size: size, bold: line.bold);
            }
          } else if (step is PosPrintCompiledPair) {
            final pair = step;
            final pairSize = layout.k58
                ? pair.fontSize.round()
                : pair.fontSize.round().clamp(layout.bodySize, 48);
            await SunmiPrinter.printRow(
              cols: [
                SunmiColumn(
                  text: tr(pair.left),
                  width: layout.itemLeft,
                  style: SunmiTextStyle(
                    fontSize: pairSize,
                    bold: true,
                  ),
                ),
                SunmiColumn(
                  text: tr(pair.right),
                  width: layout.itemRight,
                  style: SunmiTextStyle(
                    fontSize: pairSize,
                    bold: true,
                    align: SunmiPrintAlign.RIGHT,
                  ),
                ),
              ],
            );
          } else if (step is PosPrintCompiledQr) {
            await _printCompiledQr(step, layout);
          } else if (step is PosPrintCompiledBarcode) {
            await _printCompiledBarcode(step);
          }
        }
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
      await _rule(layout);
      await _center('Tiếng Việt: ĂÂÊÔƠƯ Đ', size: layout.bodySize);
      await SunmiPrinter.printRow(
        cols: [
          SunmiColumn(
            text: tr('SL x Giá'),
            width: layout.itemLeft,
            style: SunmiTextStyle(fontSize: layout.smallSize, bold: true),
          ),
          SunmiColumn(
            text: tr('Thành tiền'),
            width: layout.itemRight,
            style: SunmiTextStyle(
              fontSize: layout.smallSize,
              bold: true,
              align: SunmiPrintAlign.RIGHT,
            ),
          ),
        ],
      );
      await _rule(layout);
      await _pair(layout, 'TỔNG CỘNG', '125.000 đ', bold: true);
      await _rule(layout);
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
    double vatAmount = 0,
    double vatRate = 0,
  }) async {
    final saleDate =
        order.saleDate?.toLocal() ?? order.createdAt?.toLocal() ?? DateTime.now();
    final dateOnly = DateFormat('dd/MM/yyyy');

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

    await _left('Số: ${order.orderNo.isEmpty ? '-' : order.orderNo}',
        size: layout.bodySize, bold: true);
    await _left('Ngày: ${dateOnly.format(saleDate)}',
        size: layout.bodySize, bold: true);
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
    final tableLines = formatPosTablePrintLines(
      areaName: order.serviceAreaName,
      tableName: order.serviceResourceName ?? order.serviceResourceCode,
    );
    for (final line in tableLines) {
      await _left(line, size: layout.bodySize, bold: true);
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

    // Cột ~30; tiền có dấu chấm nghìn (800.000).
    final nameW = layout.k58 ? 10 : 12;
    final priceW = 8;
    final qtyW = 3;
    final totalW = layout.k58 ? 9 : 7;
    Future<void> printCols({
      required String name,
      required String price,
      required String qty,
      required String total,
      required int size,
      bool bold = false,
    }) =>
        SunmiPrinter.printRow(
          cols: [
            SunmiColumn(
              text: tr(name),
              width: nameW,
              style: SunmiTextStyle(fontSize: size, bold: bold),
            ),
            SunmiColumn(
              text: tr(price),
              width: priceW,
              style: SunmiTextStyle(
                fontSize: size,
                bold: bold,
                align: SunmiPrintAlign.RIGHT,
              ),
            ),
            SunmiColumn(
              text: tr(qty),
              width: qtyW,
              style: SunmiTextStyle(
                fontSize: size,
                bold: bold,
                align: SunmiPrintAlign.RIGHT,
              ),
            ),
            SunmiColumn(
              text: tr(total),
              width: totalW,
              style: SunmiTextStyle(
                fontSize: size,
                bold: bold,
                align: SunmiPrintAlign.RIGHT,
              ),
            ),
          ],
        );

    await printCols(
      name: 'Tên hàng',
      price: 'Đ.giá',
      qty: 'SL',
      total: 'TT',
      size: layout.bodySize,
      bold: true,
    );
    await _rule(layout);

    String moneyCell(double v) => _money.format(v);

    for (final line in lines) {
      final saleUnit = line.qty > 0 ? line.lineTotal / line.qty : line.unitPrice;
      final unitPrice =
          line.discountAmount > 0 ? saleUnit : line.unitPrice;
      await printCols(
        name: line.productName,
        price: moneyCell(unitPrice),
        qty: _qty.format(line.qty),
        total: moneyCell(line.lineTotal),
        size: layout.bodySize,
        bold: true,
      );
      if (line.discountAmount > 0) {
        await printCols(
          name: '',
          price: '~${moneyCell(line.unitPrice)}',
          qty: '',
          total: '',
          size: layout.smallSize,
        );
      }
      final note = line.lineNote?.trim();
      if (note != null && note.isNotEmpty) {
        await _left(' * $note', size: layout.smallSize);
      }
    }

    await _rule(layout);

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
    if (!warehouseSlip && vatAmount > 0) {
      final vatLabel = vatRate > 0
          ? 'VAT (${vatRate.toStringAsFixed(vatRate % 1 == 0 ? 0 : 1)}%):'
          : 'VAT:';
      await _pair(layout, vatLabel, _money.format(vatAmount));
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
    await _rule(layout);
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
    final png = await PosThermalBitmapEncoder.networkPngBytes(
      qr.imageUrl,
      maxWidth: qr.size,
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

  /// Đường kẻ full khổ: font tỉ lệ nên 32 ký tự '=' ở size 18 chỉ ~3/4 giấy K58.
  static Future<void> _rule(_SunmiReceiptLayout layout) async {
    final png = await PosThermalBitmapEncoder.horizontalRulePng(
      paperDots: layout.k58 ? 384 : 576,
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

  static Future<void> _pair(
    _SunmiReceiptLayout layout,
    String left,
    String right, {
    bool bold = false,
  }) =>
      SunmiPrinter.printRow(
        cols: [
          SunmiColumn(
            text: tr(left),
            width: layout.colLeft,
            style: SunmiTextStyle(
              fontSize: bold ? layout.totalSize : layout.bodySize,
              bold: true,
            ),
          ),
          SunmiColumn(
            text: tr(right),
            width: layout.colRight,
            style: SunmiTextStyle(
              fontSize: bold ? layout.totalSize : layout.bodySize,
              bold: true,
              align: SunmiPrintAlign.RIGHT,
            ),
          ),
        ],
      );

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
