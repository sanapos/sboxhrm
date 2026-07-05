import 'package:flutter/material.dart';

import '../models/pos_print_template.dart';
import '../models/pos_sale_order.dart';
import '../models/pos_store_printer.dart';
import '../services/pos_product_printer_service.dart';
import 'pos_html_print.dart';
import 'pos_print_config_session.dart';
import 'pos_print_orchestrator.dart';
import 'pos_print_template_renderer.dart';
import 'pos_store_printer_mapper.dart';
import 'pos_thermal_printer_service.dart';
import 'pos_thermal_printer_settings.dart';

/// Phương thức in phiếu xuất kho khi thử lại.
enum WarehouseSlipPrintMethod {
  assigned('Máy in gán SP'),
  pickPrinter('Chọn máy in cửa hàng'),
  localThermal('Máy in cục bộ (LAN/BT)'),
  htmlPreview('Xem HTML / In A4-A5');

  const WarehouseSlipPrintMethod(this.label);
  final String label;
}

enum PendingWarehousePrintReason {
  noPrinterAssignment('Chưa gán máy in'),
  printerNotFound('Máy in không tồn tại'),
  dispatchFailed('Gửi lệnh in thất bại');

  const PendingWarehousePrintReason(this.label);
  final String label;
}

/// Phiếu treo chưa in được — hiển thị trên màn thu ngân.
class PendingWarehousePrintJob {
  PendingWarehousePrintJob({
    required this.id,
    required this.order,
    this.printerId,
    this.printerName = '',
    this.errorMessage,
    this.reason = PendingWarehousePrintReason.dispatchFailed,
    DateTime? createdAt,
    this.tabId,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final int? tabId;
  final PosSaleOrder order;
  final String? printerId;
  final String printerName;
  final String? errorMessage;
  final PendingWarehousePrintReason reason;
  final DateTime createdAt;

  List<PosSaleOrderLine> get lines => order.lines;

  String get lineSummary {
    final names = lines
        .map((l) => '${l.productName} × ${formatWarehouseQty(l.qty)}')
        .take(3)
        .join(', ');
    if (lines.length > 3) return '$names…';
    return names;
  }

  String get orderLabel =>
      order.orderNo.isEmpty ? 'Giỏ tạm' : order.orderNo;
}

String formatWarehouseQty(double qty) {
  if (qty == qty.roundToDouble()) return qty.toStringAsFixed(0);
  return qty.toStringAsFixed(2);
}

/// Kết quả in theo từng máy in.
class WarehouseSlipPrinterAttempt {
  const WarehouseSlipPrinterAttempt({
    required this.lines,
    this.printerId,
    this.printerName = '',
    this.success = false,
    this.errorMessage,
    this.reason = PendingWarehousePrintReason.dispatchFailed,
  });

  final String? printerId;
  final String printerName;
  final List<PosSaleOrderLine> lines;
  final bool success;
  final String? errorMessage;
  final PendingWarehousePrintReason reason;
}

/// Kết quả in phiếu báo xuất kho.
class WarehouseSlipPrintResult {
  const WarehouseSlipPrintResult({
    this.attempts = const [],
    this.noPrinterLines = const [],
  });

  final List<WarehouseSlipPrinterAttempt> attempts;
  final List<PosSaleOrderLine> noPrinterLines;

  int get successCount => attempts.where((a) => a.success).length;

  int get failCount => attempts.where((a) => !a.success).length;

  bool get anySuccess => successCount > 0;

  bool get hasFailures =>
      failCount > 0 || noPrinterLines.isNotEmpty;

  List<PosSaleOrderLine> get printedLines => attempts
      .where((a) => a.success)
      .expand((a) => a.lines)
      .toList();

  List<WarehouseSlipPrinterAttempt> get failedAttempts =>
      attempts.where((a) => !a.success).toList();

  List<String> get successPrinterNames =>
      attempts.where((a) => a.success).map((a) => a.printerName).toList();

  List<String> get failedPrinterNames =>
      attempts.where((a) => !a.success).map((a) => a.printerName).toList();

  String summaryMessage({required int lineCount}) {
    if (successCount == 0 && failCount == 0 && noPrinterLines.isNotEmpty) {
      final names = noPrinterLines
          .map((l) => l.productName)
          .toSet()
          .take(3)
          .join(', ');
      final extra = noPrinterLines.map((l) => l.productName).toSet().length > 3
          ? '…'
          : '';
      return 'Chưa gán máy in: $names$extra. Vào Máy in cửa hàng → Sản phẩm in kho.';
    }
    if (successCount > 0 && failCount == 0 && noPrinterLines.isEmpty) {
      return successCount > 1
          ? 'Đã gửi $successCount phiếu tới ${successPrinterNames.join(', ')}'
          : 'Phiếu xuất kho đã gửi tới ${successPrinterNames.isNotEmpty ? successPrinterNames.first : 'máy in'}';
    }
    final parts = <String>[];
    if (successCount > 0) {
      parts.add('Thành công: ${successPrinterNames.join(', ')}');
    }
    if (failCount > 0) {
      parts.add('Lỗi: ${failedPrinterNames.join(', ')}');
    }
    if (noPrinterLines.isNotEmpty) {
      final names =
          noPrinterLines.map((l) => l.productName).toSet().take(2).join(', ');
      parts.add('Chưa gán máy in: $names');
    }
    return parts.join(' · ');
  }

  List<PendingWarehousePrintJob> toPendingJobs({
    required PosSaleOrder order,
    int? tabId,
  }) {
    final jobs = <PendingWarehousePrintJob>[];
    var seq = 0;
    for (final attempt in failedAttempts) {
      jobs.add(
        PendingWarehousePrintJob(
          id: '${DateTime.now().millisecondsSinceEpoch}_${seq++}',
          tabId: tabId,
          order: orderWithLines(order, attempt.lines),
          printerId: attempt.printerId,
          printerName: attempt.printerName,
          errorMessage: attempt.errorMessage,
          reason: attempt.reason,
        ),
      );
    }
    if (noPrinterLines.isNotEmpty) {
      jobs.add(
        PendingWarehousePrintJob(
          id: '${DateTime.now().millisecondsSinceEpoch}_nopr',
          tabId: tabId,
          order: orderWithLines(order, noPrinterLines),
          reason: PendingWarehousePrintReason.noPrinterAssignment,
          errorMessage: 'Chưa gán máy in cho sản phẩm',
        ),
      );
    }
    return jobs;
  }
}

PosSaleOrder orderWithLines(PosSaleOrder order, List<PosSaleOrderLine> lines) =>
    PosSaleOrder(
      id: order.id,
      orderNo: order.orderNo,
      status: order.status,
      note: order.note,
      customerName: order.customerName,
      lines: lines,
      lineCount: lines.length,
      saleDate: order.saleDate,
      createdAt: order.createdAt,
    );

String warehouseLineKey(PosSaleOrderLine line) =>
    '${line.productId}|${line.variantId ?? ''}';

/// Lọc dòng đơn — bỏ phần đã báo kho trước đó.
PosSaleOrder filterWarehouseSlipOrder(
  PosSaleOrder order,
  Map<String, double> alreadyPrinted,
) {
  if (alreadyPrinted.isEmpty) return order;
  final lines = <PosSaleOrderLine>[];
  for (final line in order.lines) {
    final skip = alreadyPrinted[warehouseLineKey(line)] ?? 0;
    final pending = line.qty - skip;
    if (pending <= 0) continue;
    lines.add(
      PosSaleOrderLine(
        id: line.id,
        productId: line.productId,
        variantId: line.variantId,
        productName: line.productName,
        unitName: line.unitName,
        qty: pending,
        unitPrice: line.unitPrice,
        discountAmount: line.discountAmount,
        lineTotal: line.lineTotal,
        lineNote: line.lineNote,
      ),
    );
  }
  return orderWithLines(order, lines);
}

/// Tạo đơn tạm từ giỏ hàng để in phiếu báo xuất kho trước thanh toán.
PosSaleOrder buildWarehouseSlipOrderFromCart({
  required List<PosSaleOrderLine> lines,
  String? note,
  String? customerName,
}) =>
    PosSaleOrder(
      id: '',
      orderNo: 'TẠM',
      status: 'Draft',
      note: note,
      customerName: customerName,
      lines: lines,
      lineCount: lines.length,
    );

PosThermalPrinterSettings _thermalSettingsForTemplate(
  PosThermalPrinterSettings settings,
  PosPrintTemplate? template,
) {
  if (template != null && PosPrintPaperSizes.isThermal(template.paperSize)) {
    return settings.copyWith(paperSize: template.paperSize);
  }
  return settings;
}

String slipTitleFromTemplate(PosPrintTemplate? template) {
  if (template == null) return warehouseSlipDefaultTitle();
  final html = template.htmlContent;
  final tokenMatch =
      RegExp(r'\{\{\s*Tieu_De_In\s*\}\}').firstMatch(html) != null;
  if (tokenMatch) return warehouseSlipDefaultTitle();
  final h1 = RegExp(r'<h1[^>]*>([^<]+)</h1>', caseSensitive: false)
      .firstMatch(html)
      ?.group(1)
      ?.trim();
  if (h1 != null && h1.isNotEmpty) return h1;
  if (template.name.trim().isNotEmpty) return template.name.trim().toUpperCase();
  return warehouseSlipDefaultTitle();
}

Future<List<int>> _buildWarehouseEscPosBytes({
  required PosSaleOrder order,
  required PosStorePrinter printer,
  required List<PosSaleOrderLine> lines,
  required PosPrintTemplate? template,
  String? branchName,
  String? storeAddress,
  String? storePhone,
}) async {
  var settings = toThermalSettings(printer);
  settings = _thermalSettingsForTemplate(settings, template);
  return PosThermalPrinterService.buildSaleOrderEscPosBytes(
    order,
    settings: settings,
    storeName: branchName,
    storeAddress: storeAddress,
    storePhone: storePhone,
    mergeSameItems: false,
    linesOverride: lines,
    warehouseSlip: true,
    slipTitle: slipTitleFromTemplate(template),
  );
}

Future<bool> _dispatchWarehouseBytes({
  required PosStorePrinter printer,
  required List<int> bytes,
  required PosSaleOrder order,
  bool waitForCompletion = true,
}) =>
    PosPrintOrchestrator.instance.dispatchEscPos(
      documentType: PosCloudDocumentTypes.stockIssue,
      bytes: bytes,
      printerId: printer.id,
      referenceNo: order.orderNo.isEmpty ? null : order.orderNo,
      referenceId: order.id.isEmpty ? null : order.id,
      showFeedback: false,
      successTitle: 'In phiếu xuất kho',
      waitForCompletion: waitForCompletion,
      skipDedup: order.id.isEmpty,
    );

/// In phiếu báo xuất kho theo máy in gán cho từng sản phẩm.
Future<WarehouseSlipPrintResult> printWarehouseSlipForOrder({
  required PosSaleOrder order,
  String? branchName,
  String? storeAddress,
  String? storePhone,
  String? templateId,
  bool forceRefreshConfig = false,
  bool waitForCompletion = true,
}) async {
  if (order.lines.isEmpty) {
    return const WarehouseSlipPrintResult();
  }

  if (forceRefreshConfig) {
    PosPrintConfigSession.instance.invalidate();
  }
  await PosPrintConfigSession.instance.warmUp(warehouseTemplateId: templateId);
  final template =
      await PosPrintConfigSession.instance.warehouseTemplate(templateId);

  final svc = PosProductPrinterService.instance;
  final groups = <String, List<PosSaleOrderLine>>{};
  final noPrinterLines = <PosSaleOrderLine>[];

  final printerIds = await Future.wait(
    order.lines.map((line) async => (
          line: line,
          printerId: await svc.resolvePrinterId(line.productId),
        )),
  );

  for (final row in printerIds) {
    final pid = row.printerId;
    if (pid == null || pid.isEmpty) {
      noPrinterLines.add(row.line);
      continue;
    }
    groups.putIfAbsent(pid, () => []).add(row.line);
  }

  if (groups.isEmpty) {
    return WarehouseSlipPrintResult(noPrinterLines: noPrinterLines);
  }

  final attempts = <WarehouseSlipPrinterAttempt>[];

  for (final entry in groups.entries) {
    PosStorePrinter? printer;
    for (final p in PosPrintOrchestrator.instance.printers) {
      if (p.id == entry.key) {
        printer = p;
        break;
      }
    }
    if (printer == null) {
      attempts.add(
        WarehouseSlipPrinterAttempt(
          printerId: entry.key,
          lines: entry.value,
          errorMessage: 'Máy in không còn trong cấu hình cửa hàng',
          reason: PendingWarehousePrintReason.printerNotFound,
        ),
      );
      continue;
    }

    final bytes = await _buildWarehouseEscPosBytes(
      order: order,
      printer: printer,
      lines: entry.value,
      template: template,
      branchName: branchName,
      storeAddress: storeAddress,
      storePhone: storePhone,
    );

    final ok = await _dispatchWarehouseBytes(
      printer: printer,
      bytes: bytes,
      order: order,
      waitForCompletion: waitForCompletion,
    );

    attempts.add(
      WarehouseSlipPrinterAttempt(
        printerId: printer.id,
        printerName: printer.name,
        lines: entry.value,
        success: ok,
        errorMessage: ok
            ? null
            : 'Không in được trên ${printer.name}. Kiểm tra Print Agent hoặc kết nối máy in.',
        reason: ok
            ? PendingWarehousePrintReason.dispatchFailed
            : PendingWarehousePrintReason.dispatchFailed,
      ),
    );
  }

  return WarehouseSlipPrintResult(
    attempts: attempts,
    noPrinterLines: noPrinterLines,
  );
}

/// In một job treo với phương thức do thu ngân chọn.
Future<WarehouseSlipPrintResult> printWarehouseSlipWithMethod({
  required BuildContext context,
  required PosSaleOrder order,
  required WarehouseSlipPrintMethod method,
  String? branchName,
  String? storeAddress,
  String? storePhone,
  String? templateId,
  String? overridePrinterId,
}) async {
  if (order.lines.isEmpty) {
    return const WarehouseSlipPrintResult();
  }

  await PosPrintConfigSession.instance.warmUp(warehouseTemplateId: templateId);
  final template =
      await PosPrintConfigSession.instance.warehouseTemplate(templateId);

  switch (method) {
    case WarehouseSlipPrintMethod.assigned:
      return printWarehouseSlipForOrder(
        order: order,
        branchName: branchName,
        storeAddress: storeAddress,
        storePhone: storePhone,
        templateId: templateId,
      );

    case WarehouseSlipPrintMethod.pickPrinter:
      final printerId = overridePrinterId;
      if (printerId == null || printerId.isEmpty) {
        return const WarehouseSlipPrintResult();
      }
      PosStorePrinter? printer;
      for (final p in PosPrintOrchestrator.instance.printers) {
        if (p.id == printerId) {
          printer = p;
          break;
        }
      }
      if (printer == null) {
        return WarehouseSlipPrintResult(
          attempts: [
            WarehouseSlipPrinterAttempt(
              printerId: printerId,
              lines: order.lines,
              errorMessage: 'Không tìm thấy máy in',
              reason: PendingWarehousePrintReason.printerNotFound,
            ),
          ],
        );
      }
      final bytes = await _buildWarehouseEscPosBytes(
        order: order,
        printer: printer,
        lines: order.lines,
        template: template,
        branchName: branchName,
        storeAddress: storeAddress,
        storePhone: storePhone,
      );
      final ok = await _dispatchWarehouseBytes(
        printer: printer,
        bytes: bytes,
        order: order,
      );
      return WarehouseSlipPrintResult(
        attempts: [
          WarehouseSlipPrinterAttempt(
            printerId: printer.id,
            printerName: printer.name,
            lines: order.lines,
            success: ok,
            errorMessage: ok ? null : 'In thất bại trên ${printer.name}',
          ),
        ],
      );

    case WarehouseSlipPrintMethod.localThermal:
      final thermal = await PosThermalPrinterSettings.load();
      if (!thermal.enabled) {
        return WarehouseSlipPrintResult(
          attempts: [
            WarehouseSlipPrinterAttempt(
              lines: order.lines,
              errorMessage: 'Chưa bật máy in cục bộ trong Thiết lập in',
              reason: PendingWarehousePrintReason.dispatchFailed,
            ),
          ],
        );
      }
      var settings = _thermalSettingsForTemplate(thermal, template);
      final bytes = await PosThermalPrinterService.buildSaleOrderEscPosBytes(
        order,
        settings: settings,
        storeName: branchName,
        storeAddress: storeAddress,
        storePhone: storePhone,
        mergeSameItems: false,
        warehouseSlip: true,
        slipTitle: slipTitleFromTemplate(template),
      );
      final ok = await PosPrintOrchestrator.instance.dispatchLocalEscPos(
        bytes: bytes,
        showFeedback: false,
        successTitle: 'In phiếu xuất kho',
        settingsOverride: settings,
        documentType: PosPrintDocumentTypes.stockIssue,
        referenceId: order.id.isEmpty ? null : order.id,
        referenceNo: order.orderNo.isEmpty ? null : order.orderNo,
        skipDedup: order.id.isEmpty,
      );
      return WarehouseSlipPrintResult(
        attempts: [
          WarehouseSlipPrinterAttempt(
            printerName: 'Máy in cục bộ',
            lines: order.lines,
            success: ok,
            errorMessage: ok ? null : 'Không kết nối máy in cục bộ',
          ),
        ],
      );

    case WarehouseSlipPrintMethod.htmlPreview:
      if (template != null && template.htmlContent.trim().isNotEmpty) {
        final html = renderWarehouseSlipTemplate(
          template.htmlContent,
          order,
          storeName: branchName,
          storeAddress: storeAddress,
          storePhone: storePhone,
          paperSize: template.paperSize,
          titleOverride: slipTitleFromTemplate(template),
        );
        if (context.mounted) {
          await showPosHtmlPrintDialog(
            context,
            title:
                'Phiếu xuất kho ${order.orderNo.isEmpty ? 'tạm' : order.orderNo}',
            htmlDocument: html,
          );
        }
        return WarehouseSlipPrintResult(
          attempts: [
            WarehouseSlipPrinterAttempt(
              printerName: 'HTML',
              lines: order.lines,
              success: true,
            ),
          ],
        );
      }
      return WarehouseSlipPrintResult(
        attempts: [
          WarehouseSlipPrinterAttempt(
            lines: order.lines,
            errorMessage: 'Chưa có mẫu HTML phiếu xuất kho',
            reason: PendingWarehousePrintReason.dispatchFailed,
          ),
        ],
      );
  }
}

@Deprecated('Use printWarehouseSlipForOrder')
Future<bool> printKitchenTicketsForOrder({
  required PosSaleOrder order,
  String? branchName,
  String? storeAddress,
  String? storePhone,
  String? templateId,
}) async {
  final r = await printWarehouseSlipForOrder(
    order: order,
    branchName: branchName,
    storeAddress: storeAddress,
    storePhone: storePhone,
    templateId: templateId,
  );
  return r.anySuccess;
}
