import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/pos_print_template.dart';
import '../models/pos_print_template_v2.dart';
import '../models/pos_sale_order.dart';
import '../models/pos_store_printer.dart';
import '../services/api_service.dart';
import '../services/pos_product_printer_service.dart';
import 'pos_html_print.dart';
import 'pos_print_template_runtime.dart';
import 'pos_print_config_session.dart';
import 'pos_print_orchestrator.dart';
import 'pos_print_template_renderer.dart';
import 'pos_printer_transport.dart';
import 'pos_receipt_layout.dart';
import 'pos_store_printer_mapper.dart';
import 'pos_sunmi_native_print.dart';
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

String slipTitleFromTemplate(PosPrintTemplate? template, {String? override}) {
  if (override != null && override.trim().isNotEmpty) return override.trim();
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

/// Tiêu đề phiếu báo chế biến (F&B).
String kitchenSendSlipTitle() => 'PHIẾU BÁO CHẾ BIẾN';

/// Tiêu đề phiếu hủy món đã báo bếp.
String kitchenCancelSlipTitle() => 'PHIẾU HỦY BẾP';

Future<List<int>> _buildWarehouseEscPosBytes({
  required PosSaleOrder order,
  required PosStorePrinter printer,
  required List<PosSaleOrderLine> lines,
  required PosPrintTemplate? template,
  String? branchName,
  String? storeAddress,
  String? storePhone,
  String? slipTitleOverride,
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
    slipTitle: slipTitleFromTemplate(template, override: slipTitleOverride),
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

/// Cloud → Agent Sunmi: JSON native (cùng mẫu in local), không gửi ESC/POS.
Future<bool> _dispatchWarehouseNativeCloud({
  required PosStorePrinter printer,
  required PosSaleOrder order,
  required List<PosSaleOrderLine> lines,
  String? branchName,
  String? storeAddress,
  String? storePhone,
  String? slipTitle,
  bool waitForCompletion = true,
}) {
  return PosPrintOrchestrator.instance.enqueueWarehouseSlipJson(
    printer: printer,
    order: order,
    lines: lines,
    storeName: branchName,
    storeAddress: storeAddress,
    storePhone: storePhone,
    slipTitle: slipTitle,
    waitForCompletion: waitForCompletion,
  );
}

/// In phiếu báo xuất kho theo máy in gán cho từng sản phẩm.
///
/// Khi đã bật máy in cục bộ (Sunmi/BT/LAN): in local trước.
/// Nếu vẫn còn SP gán máy in cửa hàng (bếp/kho), tiếp tục gửi cloud.
Future<WarehouseSlipPrintResult> printWarehouseSlipForOrder({
  required PosSaleOrder order,
  String? branchName,
  String? storeAddress,
  String? storePhone,
  String? templateId,
  bool forceRefreshConfig = false,
  bool waitForCompletion = true,
  String? slipTitleOverride,
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

  final attempts = <WarehouseSlipPrinterAttempt>[];
  var localPrintedAll = false;

  // Ưu tiên máy in cục bộ khi đã bật (đặc biệt Sunmi handheld).
  if (!kIsWeb) {
    final thermal = await PosThermalPrinterSettings.load();
    if (thermal.enabled) {
      final localOk = await _tryLocalWarehousePrint(
        order: order,
        lines: order.lines,
        template: template,
        branchName: branchName,
        storeAddress: storeAddress,
        storePhone: storePhone,
        thermal: thermal,
        slipTitleOverride: slipTitleOverride,
      );
      if (localOk) {
        localPrintedAll = true;
        attempts.add(
          WarehouseSlipPrinterAttempt(
            printerName: 'Máy in cục bộ',
            lines: order.lines,
            success: true,
          ),
        );
        if (groups.isEmpty) {
          return WarehouseSlipPrintResult(attempts: attempts);
        }
        // Có gán máy bếp/kho: vẫn gửi cloud cho từng nhóm.
      } else if (groups.isEmpty) {
        return WarehouseSlipPrintResult(
          attempts: [
            WarehouseSlipPrinterAttempt(
              printerName: 'Máy in cục bộ',
              lines: order.lines,
              errorMessage: 'Không in được trên máy in cục bộ',
              reason: PendingWarehousePrintReason.dispatchFailed,
            ),
          ],
          noPrinterLines: noPrinterLines,
        );
      }
      // Local lỗi nhưng vẫn còn máy cloud → bỏ qua local, gửi cloud.
    } else if (groups.isEmpty) {
      return WarehouseSlipPrintResult(noPrinterLines: noPrinterLines);
    }
  } else if (groups.isEmpty) {
    return WarehouseSlipPrintResult(noPrinterLines: noPrinterLines);
  }

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
      slipTitleOverride: slipTitleOverride,
    );

    final title = slipTitleFromTemplate(template, override: slipTitleOverride);
    final ok = printer.isSunmi
        ? await _dispatchWarehouseNativeCloud(
            printer: printer,
            order: order,
            lines: entry.value,
            branchName: branchName,
            storeAddress: storeAddress,
            storePhone: storePhone,
            slipTitle: title,
            waitForCompletion: waitForCompletion,
          )
        : await _dispatchWarehouseBytes(
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
        reason: PendingWarehousePrintReason.dispatchFailed,
      ),
    );
  }

  return WarehouseSlipPrintResult(
    attempts: attempts,
    // Đã in đủ trên máy cục bộ → không treo SP chưa gán máy cloud.
    noPrinterLines: localPrintedAll ? const [] : noPrinterLines,
  );
}

Future<bool> _tryLocalWarehousePrint({
  required PosSaleOrder order,
  required List<PosSaleOrderLine> lines,
  required PosPrintTemplate? template,
  String? branchName,
  String? storeAddress,
  String? storePhone,
  required PosThermalPrinterSettings thermal,
  String? slipTitleOverride,
}) async {
  var settings = _thermalSettingsForTemplate(thermal, template);
  settings = await PosPrinterTransport.prepareLocalSettings(settings);
  final title = slipTitleFromTemplate(template, override: slipTitleOverride);

  if (settings.connectionType == PosThermalConnectionType.sunmi ||
      await PosPrinterTransport.isSunmiDevice()) {
    try {
      final sunmiOk = await PosSunmiNativePrint.printSaleOrder(
        order,
        settings: settings.copyWith(
          connectionType: PosThermalConnectionType.sunmi,
          printerBrand: PosThermalPrinterBrand.sunmi,
        ),
        storeName: branchName,
        storeAddress: storeAddress,
        storePhone: storePhone,
        mergeSameItems: false,
        warehouseSlip: true,
        slipTitle: title,
        linesOverride: lines,
      );
      if (sunmiOk) return true;
    } catch (e) {
      debugPrint('Sunmi native warehouse print failed: $e');
    }
  }

  try {
    final bytes = await PosThermalPrinterService.buildSaleOrderEscPosBytes(
      order,
      settings: settings,
      storeName: branchName,
      storeAddress: storeAddress,
      storePhone: storePhone,
      mergeSameItems: false,
      warehouseSlip: true,
      slipTitle: title,
      linesOverride: lines,
    );
    return PosPrintOrchestrator.instance.dispatchLocalEscPos(
      bytes: bytes,
      showFeedback: false,
      successTitle: title,
      settingsOverride: settings,
      documentType: PosPrintDocumentTypes.stockIssue,
      referenceId: order.id.isEmpty ? null : order.id,
      referenceNo: order.orderNo.isEmpty ? null : order.orderNo,
      skipDedup: order.id.isEmpty,
    );
  } catch (e) {
    debugPrint('Local warehouse ESC/POS failed: $e');
    return false;
  }
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
      final ok = await _tryLocalWarehousePrint(
        order: order,
        lines: order.lines,
        template: template,
        branchName: branchName,
        storeAddress: storeAddress,
        storePhone: storePhone,
        thermal: thermal,
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

/// Dòng món trên phiếu bếp ngắn.
class KitchenTicketLine {
  const KitchenTicketLine({
    required this.productName,
    required this.qty,
    this.unitName,
    this.note,
    this.productId,
  });

  final String productName;
  final double qty;
  final String? unitName;
  final String? note;
  /// Dùng để tra máy in gán riêng cho SP/nhóm hàng (báo bếp đa máy in).
  final String? productId;
}

/// Phiếu bếp/hủy theo mẫu: tên bàn giữa, meta, bảng Tên hàng|SL (SL + ĐVT).
///
/// [skipDedup]: mặc định false — chặn in trùng cùng nội dung trong ~25s
/// (bấm Báo bếp 2 lần / auto-retry sau khi Agent đã nhận job). Truyền true
/// chỉ khi người dùng chủ động "In lại" từ phiếu treo.
Future<bool> printKitchenCompactSlip({
  required String tableName,
  required bool isCancel,
  required List<KitchenTicketLine> lines,
  required String senderName,
  DateTime? sentAt,
  String? orderNo,
  bool skipDedup = false,
  bool waitForCompletion = true,
}) async {
  if (lines.isEmpty) return false;

  final dedupRef = _kitchenDedupReference(
    orderNo: orderNo,
    isCancel: isCancel,
    lines: lines,
  );

  // Món có gán máy in riêng (SP hoặc nhóm hàng) → tách phiếu, in đúng máy đó
  // thay vì dồn hết vào 1 máy in mặc định/local.
  final svc = PosProductPrinterService.instance;
  final hasAnyProductId = lines.any((l) => (l.productId ?? '').isNotEmpty);
  if (hasAnyProductId) {
    await PosPrintOrchestrator.instance.refreshConfig();
    final resolved = await Future.wait(lines.map((l) async => (
          line: l,
          printerId: (l.productId ?? '').isEmpty
              ? null
              : await svc.resolvePrinterId(l.productId!),
        )));
    final assignedGroups = <String, List<KitchenTicketLine>>{};
    final defaultLines = <KitchenTicketLine>[];
    for (final row in resolved) {
      if (row.printerId == null || row.printerId!.isEmpty) {
        defaultLines.add(row.line);
      } else {
        assignedGroups.putIfAbsent(row.printerId!, () => []).add(row.line);
      }
    }

    if (assignedGroups.isNotEmpty) {
      var allOk = true;
      for (final entry in assignedGroups.entries) {
        final printer = PosPrintOrchestrator.instance.printers
            .where((p) => p.id == entry.key)
            .firstOrNull;
        if (printer == null) {
          // Máy in gán đã xóa/không còn — in theo mặc định để không mất món.
          defaultLines.addAll(entry.value);
          continue;
        }
        final ok = await PosPrintOrchestrator.instance.dispatchKitchenSlip(
          printer: printer,
          tableName: tableName,
          isCancel: isCancel,
          lines: [
            for (final l in entry.value)
              (
                productName: l.productName,
                qty: l.qty,
                unitName: l.unitName,
                note: l.note,
              ),
          ],
          senderName: senderName.trim().isEmpty ? 'admin' : senderName.trim(),
          sentAt: sentAt ?? DateTime.now(),
          orderNo: (orderNo ?? '').trim(),
          referenceNo: dedupRef,
          showFeedback: false,
          successTitle: isCancel ? 'Hủy bếp' : 'Báo bếp',
          skipDedup: skipDedup,
          waitForCompletion: waitForCompletion,
        );
        if (!ok) allOk = false;
      }
      if (defaultLines.isEmpty) return allOk;
      final defaultOk = await _printKitchenCompactSlipDefault(
        tableName: tableName,
        isCancel: isCancel,
        lines: defaultLines,
        senderName: senderName,
        sentAt: sentAt,
        orderNo: orderNo,
        skipDedup: skipDedup,
        dedupRef: dedupRef,
        waitForCompletion: waitForCompletion,
      );
      return allOk && defaultOk;
    }
  }

  return _printKitchenCompactSlipDefault(
    tableName: tableName,
    isCancel: isCancel,
    lines: lines,
    senderName: senderName,
    sentAt: sentAt,
    orderNo: orderNo,
    skipDedup: skipDedup,
    dedupRef: dedupRef,
    waitForCompletion: waitForCompletion,
  );
}

/// Khóa chống in trùng: loại phiếu + mã HĐ + danh sách món/SL.
String _kitchenDedupReference({
  required String? orderNo,
  required bool isCancel,
  required List<KitchenTicketLine> lines,
}) {
  final code = (orderNo ?? '').trim();
  final items = lines
      .map((l) =>
          '${(l.productId ?? '').trim().isNotEmpty ? l.productId : l.productName}:${l.qty}')
      .join('|');
  return '${isCancel ? 'kvoid' : 'ksend'}|$code|$items';
}

/// In lên máy in bếp mặc định (local nếu bật, hoặc máy in cloud đầu tiên gán
/// cho StockIssue) — dùng cho món không có máy in riêng theo SP/nhóm hàng.
Future<bool> _printKitchenCompactSlipDefault({
  required String tableName,
  required bool isCancel,
  required List<KitchenTicketLine> lines,
  required String senderName,
  DateTime? sentAt,
  String? orderNo,
  bool skipDedup = false,
  String? dedupRef,
  bool waitForCompletion = true,
}) async {
  if (lines.isEmpty) return false;
  final qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
  final timeFmt = DateFormat('dd/MM/yyyy HH:mm');
  final table =
      tableName.trim().isEmpty ? 'Bàn' : tableName.trim();
  final when = timeFmt.format(sentAt ?? DateTime.now());
  final sender =
      senderName.trim().isEmpty ? 'admin' : senderName.trim();
  final code = (orderNo ?? '').trim().isEmpty ? '-' : orderNo!.trim();

  Future<PosThermalPrinterSettings> loadSettings() async {
    if (!kIsWeb) {
      final thermal = await PosThermalPrinterSettings.load();
      if (thermal.enabled) {
        return PosPrinterTransport.prepareLocalSettings(thermal);
      }
    }
    final printers = PosPrintOrchestrator.instance
        .resolvePrinters(PosCloudDocumentTypes.stockIssue);
    if (printers.isNotEmpty) return toThermalSettings(printers.first);
    return const PosThermalPrinterSettings();
  }

  final settings = await loadSettings();
  final layout = PosReceiptLayout.fromMm(settings.paperWidthMm);
  final body = <String>[
    if (isCancel) '*** PHIEU HUY ***' else '*** BAO CHE BIEN ***',
    'Ma HD: $code',
    'NV: $sender',
    'Ngay: $when',
    layout.equals,
    layout.kitchenHeader,
    layout.equals,
    for (var i = 0; i < lines.length; i++)
      ...layout.kitchenItemRows(
        index: i + 1,
        name: lines[i].productName,
        qty: qtyFmt.format(lines[i].qty),
        unit: lines[i].unitName,
        note: lines[i].note,
      ),
    layout.equals,
  ];

  if (!kIsWeb) {
    final thermal = await PosThermalPrinterSettings.load();
    if (thermal.enabled) {
      final prepared = await PosPrinterTransport.prepareLocalSettings(thermal);
      final kitchenSettings = prepared.copyWith(
        feedBeforeCut: 12,
        openCashDrawer: false,
      );
      if (kitchenSettings.connectionType == PosThermalConnectionType.sunmi ||
          await PosPrinterTransport.isSunmiDevice()) {
        try {
          final docType = isCancel
              ? PosPrintDocumentTypes.kitchenVoid
              : PosPrintDocumentTypes.kitchenSlip;
          final paper = kitchenSettings.paperWidthMm <= 58
              ? PosPrintPaperSizes.k58
              : PosPrintPaperSizes.k80;
          final tplEntity =
              await PosPrintTemplateRuntime.loadDefaultTemplate(ApiService(), docType);
          final v2 = PosPrintTemplateRuntime.resolveOrPreset(
            template: tplEntity,
            documentType: docType,
            paperSize: paper,
            printerProfile: PosPrintPrinterProfiles.sunmiK58,
          );
          final output = PosPrintTemplateRuntime.compileKitchenSlip(
            template: v2,
            tableName: table,
            isCancel: isCancel,
            lines: [
              for (final l in lines)
                (
                  name: l.productName,
                  qty: qtyFmt.format(l.qty),
                  unit: l.unitName,
                  note: l.note,
                ),
            ],
            senderName: sender,
            orderNo: code == '-' ? '' : code,
            sentAt: sentAt ?? DateTime.now(),
          );
          final v2Ok = await PosPrintTemplateRuntime.printCompiledSunmi(
            output: output,
            settings: kitchenSettings.copyWith(
              connectionType: PosThermalConnectionType.sunmi,
              printerBrand: PosThermalPrinterBrand.sunmi,
            ),
            kitchenFeed: true,
          );
          if (v2Ok) return true;
        } catch (e) {
          debugPrint('Kitchen V2 template print failed: $e');
        }
        try {
          final ok = await PosSunmiNativePrint.printKitchenSlip(
            tableName: table,
            isCancel: isCancel,
            lines: [
              for (final l in lines)
                (
                  name: l.productName,
                  qty: qtyFmt.format(l.qty),
                  unit: l.unitName,
                  note: l.note,
                ),
            ],
            senderName: sender,
            orderNo: code == '-' ? '' : code,
            sentAt: sentAt ?? DateTime.now(),
            settings: kitchenSettings.copyWith(
              connectionType: PosThermalConnectionType.sunmi,
              printerBrand: PosThermalPrinterBrand.sunmi,
            ),
          );
          if (ok) return true;
        } catch (e) {
          debugPrint('Sunmi kitchen compact failed: $e');
        }
      }
      try {
        final bytes = await PosThermalPrinterService.buildTextEscPosBytes(
          settings: kitchenSettings,
          title: table,
          lines: body,
        );
        return PosPrintOrchestrator.instance.dispatchLocalEscPos(
          bytes: bytes,
          showFeedback: false,
          successTitle: isCancel ? 'Hủy bếp' : 'Báo bếp',
          settingsOverride: kitchenSettings,
          documentType: PosPrintDocumentTypes.stockIssue,
          skipDedup: skipDedup,
          referenceNo: dedupRef ?? (code == '-' ? null : code),
          waitForCompletion: waitForCompletion,
        );
      } catch (e) {
        debugPrint('Local kitchen compact failed: $e');
      }
    }
  }

  await PosPrintOrchestrator.instance.refreshConfig();
  final printers = PosPrintOrchestrator.instance
      .resolvePrinters(PosCloudDocumentTypes.stockIssue);
  if (printers.isNotEmpty) {
    final p = printers.first;
    return PosPrintOrchestrator.instance.dispatchKitchenSlip(
      printer: p,
      tableName: table,
      isCancel: isCancel,
      lines: [
        for (final l in lines)
          (
            productName: l.productName,
            qty: l.qty,
            unitName: l.unitName,
            note: l.note,
          ),
      ],
      senderName: sender,
      sentAt: sentAt ?? DateTime.now(),
      orderNo: code == '-' ? '' : code,
      referenceNo: dedupRef ?? (code == '-' ? null : code),
      showFeedback: false,
      successTitle: isCancel ? 'Hủy bếp' : 'Báo bếp',
      skipDedup: skipDedup,
      waitForCompletion: waitForCompletion,
    );
  }

  return false;
}

