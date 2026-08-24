import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/pos_print_template.dart';
import '../models/pos_print_template_v2.dart';
import '../models/pos_sale_order.dart';
import '../models/pos_store_printer.dart';
import '../services/api_service.dart';
import '../services/pos_product_printer_service.dart';
import '../widgets/notification_overlay.dart';
import 'package:sbox_pos/l10n/app_tr.dart';
import 'pos_html_print.dart';
import 'pos_print_template_runtime.dart';
import 'pos_print_config_session.dart';
import 'pos_local_printers_store.dart';
import 'pos_print_orchestrator.dart';
import 'pos_print_role.dart';
import 'pos_print_template_renderer.dart';
import 'pos_printer_readiness.dart';
import 'pos_printer_transport.dart';
import 'pos_receipt_layout.dart';
import 'pos_store_printer_mapper.dart';
import 'pos_sunmi_native_print.dart';
import 'pos_thermal_printer_service.dart';
import 'pos_thermal_printer_settings.dart';
import 'pos_usb_printer.dart';

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

/// Chống bấm báo bếp chồng khi cùng phiếu (dedupRef) đang gửi.
final _kitchenCompactInFlight = <String, Future<bool>>{};

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
  final v2 = PosPrintTemplateRuntime.parseTemplate(template);
  if (v2 != null) {
    // Ưu tiên tiêu đề cố định trong block text của preset StockIssue.
    for (final b in v2.blocks) {
      if (b.type == PosPrintBlockType.field && b.field == 'Tieu_De_In') {
        break;
      }
      if (b.type == PosPrintBlockType.text &&
          (b.text ?? '').contains('XUẤT KHO')) {
        return b.text!.trim();
      }
    }
  }
  final html = template.htmlContent;
  final h1 = RegExp(r'<h1[^>]*>([^<]+)</h1>', caseSensitive: false)
      .firstMatch(html)
      ?.group(1)
      ?.trim();
  if (h1 != null &&
      h1.isNotEmpty &&
      !h1.contains('{{') &&
      !RegExp(r'kh[oổ]\s*k\d+', caseSensitive: false).hasMatch(h1)) {
    return h1;
  }
  // Không dùng tên mẫu («KHỔ K80 - MẪU 1») làm tiêu đề phiếu.
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
  final title = slipTitleFromTemplate(template, override: slipTitleOverride);
  final v2 = PosPrintTemplateRuntime.resolveOrPreset(
    template: template,
    documentType: PosPrintDocumentTypes.stockIssue,
    paperSize: settings.paperSize,
    printerProfile: PosPrintPrinterProfiles.forPaperAndBrand(
      paperSize: settings.paperSize,
      isSunmi: settings.connectionType == PosThermalConnectionType.sunmi ||
          settings.printerBrand == PosThermalPrinterBrand.sunmi,
      isZywell: settings.printerBrand == PosThermalPrinterBrand.zywell,
    ),
  );
  final output = PosPrintTemplateRuntime.compileStockIssue(
    template: v2,
    order: order,
    lines: lines,
    storeName: branchName,
    storeAddress: storeAddress,
    storePhone: storePhone,
    titleOverride: title,
  );
  return PosPrintTemplateRuntime.buildCompiledEscPosBytes(
    output: output,
    settings: settings,
  );
}

Future<bool> _dispatchWarehouseBytes({
  required PosStorePrinter printer,
  required List<int> bytes,
  required PosSaleOrder order,
  bool waitForCompletion = true,
  bool preferDirectPrint = false,
}) async {
  // In lại / nội bộ: chỉ khi có profile máy nội bộ trên máy này.
  // LAN từ Agent/cloud (không có local) → không TCP, đi cloud.
  if (!kIsWeb) {
    final ownedLocal =
        await PosLocalPrintersStore.instance.resolveForStorePrinter(printer);
    final onSunmiHw = await PosPrinterTransport.isSunmiDevice();
    final onDevice = ownedLocal != null &&
        PosLocalPrintersStore.profileAllowsDirectLocal(ownedLocal);
    final tryDirect = onDevice || (printer.isSunmi && onSunmiHw);

    if (tryDirect) {
      final settings = (onDevice
              ? ownedLocal!.toThermalSettings()
              : toThermalSettings(printer))
          .copyWith(openCashDrawer: false);
      final ok = await PosPrintOrchestrator.instance.dispatchLocalEscPos(
        bytes: bytes,
        showFeedback: false,
        successTitle: 'In phiếu xuất kho',
        settingsOverride: settings,
        skipDedup: true,
        waitForCompletion: waitForCompletion,
      );
      if (ok) return true;
      if (!preferDirectPrint && (onDevice || printer.isDeviceLocal)) {
        return false;
      }
    }
  }

  return PosPrintOrchestrator.instance.dispatchEscPos(
    documentType: PosCloudDocumentTypes.stockIssue,
    bytes: bytes,
    printerId: printer.id,
    referenceNo: order.orderNo.isEmpty ? null : order.orderNo,
    referenceId: order.id.isEmpty ? null : order.id,
    showFeedback: false,
    successTitle: 'In phiếu xuất kho',
    waitForCompletion: waitForCompletion,
    skipDedup: order.id.isEmpty || preferDirectPrint,
  );
}

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

  await PosPrintOrchestrator.instance.refreshConfig();
  final stockCapableIds = <String>{
    for (final p in PosPrintOrchestrator.instance.printers)
      if (p.documentTypes.contains(PosCloudDocumentTypes.stockIssue) ||
          p.documentTypes.contains(PosLocalPrinterRoles.stockIssue))
        p.id,
  };

  final printerIds = await Future.wait(
    order.lines.map((line) async => (
          line: line,
          printerId: await svc.resolvePrinterId(line.productId),
        )),
  );

  for (final row in printerIds) {
    final pid = row.printerId;
    // Chỉ nhận máy gán SP nếu máy đó thật sự có vai trò Xuất kho —
    // tránh phiếu kho in nhầm máy Báo bếp.
    if (pid == null ||
        pid.isEmpty ||
        !stockCapableIds.contains(pid)) {
      noPrinterLines.add(row.line);
      continue;
    }
    groups.putIfAbsent(pid, () => []).add(row.line);
  }

  final attempts = <WarehouseSlipPrinterAttempt>[];
  var localPrintedAll = false;

  // Ưu tiên máy nội bộ vai trò StockIssue — KHÔNG fallback máy hóa đơn/Sunmi.
  if (!kIsWeb) {
    final stockLocals = await PosLocalPrintersStore.instance
        .forRole(PosLocalPrinterRoles.stockIssue);
    final thermalCandidates = <PosThermalPrinterSettings>[
      for (final p in stockLocals.where((p) => !p.isLabel)) p.toThermalSettings(),
    ];

    if (thermalCandidates.isNotEmpty) {
      var localOk = false;
      String localName = 'Máy in cục bộ';
      for (final thermal in thermalCandidates) {
        final ok = await _tryLocalWarehousePrint(
          order: order,
          lines: order.lines,
          template: template,
          branchName: branchName,
          storeAddress: storeAddress,
          storePhone: storePhone,
          thermal: thermal,
          slipTitleOverride: slipTitleOverride,
        );
        if (ok) {
          localOk = true;
          localName = thermal.connectionType.label;
          break;
        }
      }
      if (localOk) {
        localPrintedAll = true;
        attempts.add(
          WarehouseSlipPrinterAttempt(
            printerName: localName,
            lines: order.lines,
            success: true,
          ),
        );
        // Đã in đủ cục bộ → không in thêm lên máy gán món (tránh phiếu kép / báo bếp).
        return WarehouseSlipPrintResult(
          attempts: attempts,
          noPrinterLines: const [],
        );
      } else if (groups.isEmpty && noPrinterLines.isNotEmpty) {
        return WarehouseSlipPrintResult(
          attempts: [
            WarehouseSlipPrinterAttempt(
              printerName: 'Máy in xuất kho',
              lines: order.lines,
              errorMessage: 'Không in được trên máy in xuất kho nội bộ',
              reason: PendingWarehousePrintReason.dispatchFailed,
            ),
          ],
          noPrinterLines: noPrinterLines,
        );
      }
    }
  }

  // Không có máy StockIssue nội bộ / cloud gán SP → gom in máy StockIssue cửa hàng.
  if (groups.isEmpty) {
    final stockCloud = PosPrintOrchestrator.instance
        .resolvePrinters(PosCloudDocumentTypes.stockIssue);
    if (stockCloud.isNotEmpty) {
      for (final line in [...noPrinterLines]) {
        groups.putIfAbsent(stockCloud.first.id, () => []).add(line);
      }
      noPrinterLines.clear();
    } else if (noPrinterLines.isNotEmpty || order.lines.isNotEmpty) {
      // Không cấu hình máy xuất kho → báo rõ, không đẩy sang bếp/Sunmi.
      return WarehouseSlipPrintResult(
        attempts: [
          WarehouseSlipPrinterAttempt(
            printerName: 'Xuất kho',
            lines: order.lines,
            errorMessage:
                'Chưa có máy in vai trò «Báo xuất kho». Vào Máy in nội bộ → Sửa máy nhiệt → bật Báo xuất kho.',
            reason: PendingWarehousePrintReason.printerNotFound,
          ),
        ],
        noPrinterLines: order.lines,
      );
    } else {
      return const WarehouseSlipPrintResult();
    }
  }

  if (groups.isEmpty) {
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
  final v2 = PosPrintTemplateRuntime.resolveOrPreset(
    template: template,
    documentType: PosPrintDocumentTypes.stockIssue,
    paperSize: settings.paperSize,
    printerProfile: PosPrintPrinterProfiles.forPaperAndBrand(
      paperSize: settings.paperSize,
      isSunmi: settings.connectionType == PosThermalConnectionType.sunmi ||
          settings.printerBrand == PosThermalPrinterBrand.sunmi,
      isZywell: settings.printerBrand == PosThermalPrinterBrand.zywell,
    ),
  );
  final output = PosPrintTemplateRuntime.compileStockIssue(
    template: v2,
    order: order,
    lines: lines,
    storeName: branchName,
    storeAddress: storeAddress,
    storePhone: storePhone,
    titleOverride: title,
  );

  if (settings.connectionType == PosThermalConnectionType.sunmi) {
    try {
      final sunmiOk = await PosPrintTemplateRuntime.printCompiledSunmi(
        output: output,
        settings: settings.copyWith(
          connectionType: PosThermalConnectionType.sunmi,
          printerBrand: PosThermalPrinterBrand.sunmi,
        ),
        kitchenFeed: true,
      );
      if (sunmiOk) return true;
    } catch (e) {
      debugPrint('Sunmi StockIssue compile print failed: $e');
    }
  }

  try {
    final bytes = await PosPrintTemplateRuntime.buildCompiledEscPosBytes(
      output: output,
      settings: settings,
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
    debugPrint('Local warehouse StockIssue ESC/POS failed: $e');
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
      final printerId = overridePrinterId?.trim();
      if (printerId == null || printerId.isEmpty) {
        return const WarehouseSlipPrintResult();
      }
      PosStorePrinter? printer;
      for (final p in PosPrintOrchestrator.instance.printers) {
        if (p.id.toLowerCase() == printerId.toLowerCase()) {
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
      // In lại chọn máy: in toàn bộ dòng lên máy đã chọn — bỏ gán SP→máy in.
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
        preferDirectPrint: true,
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
    this.sentBefore,
    this.lineKey,
    this.calledAt,
  });

  final String productName;
  final double qty;
  final String? unitName;
  final String? note;
  /// Dùng để tra máy in gán riêng cho SP/nhóm hàng (báo bếp đa máy in).
  final String? productId;

  /// SL của dòng này đã báo bếp TRƯỚC lần gửi này (mốc phần đang báo).
  ///
  /// Bán 1 phần → báo bếp → thêm 1 phần → báo bếp: cả hai lần đều là
  /// «món X, 1 phần» nên mã chống trùng cũ trùng nhau, phần thứ hai bị nuốt
  /// trong 25s (đã đánh dấu đã gửi nên không báo lại được). Mốc này tách
  /// hai lần gửi thành hai phiếu khác nhau, vẫn chặn bấm đúp cùng một phần.
  final double? sentBefore;

  /// Định danh dòng giỏ (rowId máy bán / Id dòng đơn phía server).
  ///
  /// Thêm phần mới cho món đã báo bếp sinh **dòng mới** chứ không cộng SL,
  /// nên hai lần báo đều là «món X, 1 phần, đã gửi 0» — thiếu khóa này thì
  /// phiếu thứ hai trùng mã và bị nuốt trong 25s.
  final String? lineKey;

  /// Giờ gọi món (báo bếp). Null = dùng thời điểm in phiếu.
  final DateTime? calledAt;
}

/// Phiếu bếp/hủy theo mẫu: tên bàn giữa, meta, bảng Tên hàng|SL (SL + ĐVT).
///
/// Cloud chưa in xong sau ~30s → phiếu treo (máy gửi) kèm đúng nhóm món của máy đó.
typedef KitchenPrintHangCallback = void Function({
  required String jobId,
  required String printerId,
  required String printerName,
  required List<KitchenTicketLine> lines,
  String? referenceNo,
});

/// Khi một máy trong fan-out trả false ngay (không enqueue được).
typedef KitchenPrinterFailedCallback = void Function({
  required String printerId,
  required String printerName,
  required List<KitchenTicketLine> lines,
  required String errorMessage,
});

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
  /// Toast «Đã gửi lệnh in» giống tem / hóa đơn (mặc định bật).
  bool showFeedback = true,
  /// In lại: ép in lên máy này (bỏ qua gán SP / máy mặc định).
  String? overridePrinterId,
  /// Đối tượng máy đã chọn (tránh mất máy sau refreshConfig).
  PosStorePrinter? overridePrinter,
  /// Cloud chưa in xong sau ~30s → phiếu treo theo từng máy (đúng nhóm món).
  KitchenPrintHangCallback? onCloudHang,
  /// Dispatch thất bại ngay trên một máy trong fan-out.
  KitchenPrinterFailedCallback? onPrinterFailed,
}) async {
  if (lines.isEmpty) return false;

  final dedupRef = _kitchenDedupReference(
    orderNo: orderNo,
    isCancel: isCancel,
    lines: lines,
  );

  // skipDedup=true (retry từ pending sheet): không dùng _kitchenCompactInFlight
  // để tránh trả về future đã complete/fail của lần gửi trước.
  if (!skipDedup) {
    final existing = _kitchenCompactInFlight[dedupRef];
    if (existing != null) {
      if (showFeedback) {
        NotificationOverlayManager().showWarning(
          title: 'Đang gửi báo bếp',
          message: tr('Lệnh trước chưa xong — vui lòng đợi'),
          relatedEntityType: kPosPrintNotifyKind,
        );
      }
      return existing;
    }
  }

  final future = _printKitchenCompactSlipLocked(
    tableName: tableName,
    isCancel: isCancel,
    lines: lines,
    senderName: senderName,
    sentAt: sentAt,
    orderNo: orderNo,
    skipDedup: skipDedup,
    waitForCompletion: waitForCompletion,
    showFeedback: showFeedback,
    overridePrinterId: overridePrinterId,
    overridePrinter: overridePrinter,
    onCloudHang: onCloudHang,
    onPrinterFailed: onPrinterFailed,
    dedupRef: dedupRef,
  );
  _kitchenCompactInFlight[dedupRef] = future;
  try {
    return await future;
  } finally {
    if (identical(_kitchenCompactInFlight[dedupRef], future)) {
      _kitchenCompactInFlight.remove(dedupRef);
    }
  }
}

Future<bool> _printKitchenCompactSlipLocked({
  required String tableName,
  required bool isCancel,
  required List<KitchenTicketLine> lines,
  required String senderName,
  DateTime? sentAt,
  String? orderNo,
  bool skipDedup = false,
  bool waitForCompletion = true,
  bool showFeedback = true,
  String? overridePrinterId,
  PosStorePrinter? overridePrinter,
  KitchenPrintHangCallback? onCloudHang,
  KitchenPrinterFailedCallback? onPrinterFailed,
  required String dedupRef,
}) async {
  PosPrintHangCallback? wrapHang(List<KitchenTicketLine> hangLines) {
    if (onCloudHang == null) return null;
    return ({
      required String jobId,
      required String documentType,
      required String printerId,
      required String printerName,
      String? referenceNo,
    }) {
      onCloudHang(
        jobId: jobId,
        printerId: printerId,
        printerName: printerName,
        lines: hangLines,
        referenceNo: referenceNo,
      );
    };
  }

  final wantOverrideId = overridePrinterId?.trim() ?? '';
    if (overridePrinter != null || wantOverrideId.isNotEmpty) {
    PosStorePrinter? printer = overridePrinter == null
        ? null
        : PosPrintOrchestrator.instance.preferCloudAgentPrinter(overridePrinter);
    if (printer == null) {
      await PosPrintOrchestrator.instance.refreshConfig();
      printer = PosPrintOrchestrator.instance.printerById(wantOverrideId);
      if (printer == null) {
        debugPrint('Kitchen reprint: printer not found id=$wantOverrideId');
        return false;
      }
    }
    // In lại chọn máy: ép in máy này (bỏ gán SP). preferDirectPrint để thử
    // LAN/BT/USB trên thiết bị trước khi cloud — tránh fail vì máy chưa «gán» SP.
    final overrideRef = skipDedup
        ? kitchenRefFit('$dedupRef|r|${DateTime.now().millisecondsSinceEpoch}')
        : dedupRef;
    return PosPrintOrchestrator.instance.dispatchKitchenSlip(
      printer: printer,
      tableName: tableName,
      isCancel: isCancel,
      lines: [
        for (final l in lines)
          (
            productName: l.productName,
            qty: l.qty,
            unitName: l.unitName,
            note: PosPrintTemplateRuntime.kitchenCallNote(
              l.note,
              l.calledAt ?? sentAt ?? DateTime.now(),
            ),
          ),
      ],
      senderName: senderName.trim().isEmpty ? 'admin' : senderName.trim(),
      sentAt: sentAt ?? DateTime.now(),
      orderNo: (orderNo ?? '').trim(),
      referenceNo: overrideRef,
      showFeedback: showFeedback,
      successTitle: isCancel ? 'Hủy bếp' : 'Báo bếp',
      skipDedup: true,
      waitForCompletion: waitForCompletion,
      preferDirectPrint: true,
      forceCloud: false,
      onHang: wrapHang(lines),
    );
  }

  // Món có gán máy in riêng (SP hoặc nhóm hàng) → tách phiếu, in đúng máy đó
  // thay vì dồn hết vào 1 máy in mặc định/local.
  // skipDedup=true (in lại) vẫn fan-out theo gán SP — chỉ overridePrinter mới ép 1 máy.
  final svc = PosProductPrinterService.instance;
  final hasAnyProductId = lines.any((l) => (l.productId ?? '').isNotEmpty);
  if (hasAnyProductId) {
    // Dùng cache TTL (máy in 3 phút, gán SP 5 phút). Bust mỗi lần bấm
    // Thông báo làm máy đơ: 3 API + parse JSON trên isolate UI.
    await PosPrintOrchestrator.instance.refreshConfig();
    await svc.preload();
    final resolved = await Future.wait(lines.map((l) async => (
          line: l,
          printerId: (l.productId ?? '').isEmpty
              ? null
              : await svc.resolvePrinterId(l.productId!),
        )));
    // Gán SP/nhóm là store-wide (cả máy Agent). Tắt Agent trên A6 không
    // xóa map này — remap local→cloud twin khiến phiếu đi hàng đợi không ai nhận.
    final agentOn = kIsWeb || await PosPrintRole.isPrintAgentDevice();
    final assignedGroups = <String, List<KitchenTicketLine>>{};
    final defaultLines = <KitchenTicketLine>[];
    for (final row in resolved) {
      if (row.printerId == null || row.printerId!.isEmpty) {
        defaultLines.add(row.line);
      } else {
        // Agent bật: gộp twin local/cloud. Agent tắt: giữ ID gốc (máy cục bộ).
        final canonical = agentOn
            ? (PosPrintOrchestrator.instance
                    .printerById(row.printerId)
                    ?.id ??
                row.printerId!)
            : row.printerId!;
        assignedGroups.putIfAbsent(canonical, () => []).add(row.line);
      }
    }
    debugPrint(
      'Kitchen DBG: resolved=${resolved.map((r) => '${r.line.productName}->${r.printerId}').join(', ')} '
      'assignedGroups=${assignedGroups.keys.toList()} defaultLines=${defaultLines.length}',
    );

    if (assignedGroups.isNotEmpty) {
      var allOk = true;
      final hasLocalKitchen = await _kitchenHasLocalSlipPrinters();
      // Agent bật / máy khác: in đúng máy đã gán. Agent tắt + có máy bếp
      // cục bộ: không đẩy hàng đợi Agent — fallback máy nội bộ.
      for (final entry in assignedGroups.entries) {
        final groupLines = entry.value;
        final printer = (agentOn
                ? PosPrintOrchestrator.instance.printerById(entry.key)
                : _kitchenPrinterWithoutCloudRemap(entry.key)) ??
            PosPrintOrchestrator.instance.printerById(entry.key);
        if (printer == null) {
          if (!agentOn && hasLocalKitchen) {
            debugPrint(
              'Kitchen DBG: printer id=${entry.key} not found — Agent tắt, fallback local',
            );
            defaultLines.addAll(groupLines);
            continue;
          }
          debugPrint(
            'Kitchen DBG: printer id=${entry.key} not found — KHÔNG fallback default',
          );
          allOk = false;
          onPrinterFailed?.call(
            printerId: entry.key,
            printerName: 'Máy đã gán (không tìm thấy)',
            lines: groupLines,
            errorMessage:
                'Không tìm thấy máy in đã gán — kiểm tra Máy in cửa hàng / gán SP',
          );
          continue;
        }
        final kitchenDoc = isCancel
            ? PosCloudDocumentTypes.kitchenVoid
            : PosCloudDocumentTypes.kitchenSlip;
        debugPrint(
          'Kitchen DBG: printer=${printer.name} id=${printer.id} '
          'documentTypes=${printer.documentTypes} isDeviceLocal=${printer.isDeviceLocal} '
          'conn=${printer.connectionType} kitchenDoc=$kitchenDoc',
        );
        // Gán SP → máy là nguồn sự thật. Không chặn vì documentTypes/route
        // lệch cache (user đã gán Báo bếp + món nhưng cache trống → báo sai
        // «chưa gán vai trò» rồi đưa vào phiếu treo).
        final hasKitchenRole = printer.documentTypes.contains(kitchenDoc) ||
            printer.documentTypes.contains(PosCloudDocumentTypes.kitchenSlip) ||
            PosPrintOrchestrator.instance
                .resolvePrinters(kitchenDoc)
                .any((p) => p.id.toLowerCase() == printer.id.toLowerCase()) ||
            PosPrintOrchestrator.instance
                .resolvePrinters(PosCloudDocumentTypes.kitchenSlip)
                .any((p) => p.id.toLowerCase() == printer.id.toLowerCase());
        if (!hasKitchenRole) {
          debugPrint(
            'Kitchen DBG: ${printer.name} thiếu role trên cache — vẫn in vì đã gán SP',
          );
        }
        final role = isCancel
            ? PosLocalPrinterRoles.kitchenVoid
            : PosLocalPrinterRoles.kitchenSlip;
        final onDevice = !kIsWeb
            ? await PosLocalPrintersStore.instance
                .resolveOnDeviceForStorePrinter(printer, documentRole: role)
            : null;
        final canLocalPort =
            onDevice != null || await _kitchenAssignedHasLocalPort(printer);
        if (!agentOn && !canLocalPort && hasLocalKitchen) {
          debugPrint(
            'Kitchen DBG: bỏ gán ${printer.name} (${printer.connectionType}) '
            '— Agent tắt, không có cổng local, fallback máy bếp nội bộ '
            'lines=${groupLines.length}',
          );
          defaultLines.addAll(groupLines);
          continue;
        }
        debugPrint(
          'Kitchen DBG: dispatching assigned printer ${printer.name} '
          '(${printer.connectionType}) localPort=$canLocalPort '
          'lines=${groupLines.length}',
        );
        // Ref theo máy + món nhóm — fan-out 2 máy không chung 1 ReferenceNo;
        // retry (skipDedup) thêm suffix để không dính job Queued cũ.
        final groupRef = _kitchenDedupReference(
          orderNo: orderNo,
          isCancel: isCancel,
          lines: groupLines,
          printerId: printer.id,
        );
        final refNo = skipDedup
            ? kitchenRefFit(
                '$groupRef|r|${DateTime.now().millisecondsSinceEpoch}')
            : groupRef;
        // Có cổng trên máy này → in local. Không ép cloud khi Agent tắt.
        final ok = await PosPrintOrchestrator.instance.dispatchKitchenSlip(
          printer: printer,
          tableName: tableName,
          isCancel: isCancel,
          lines: [
            for (final l in groupLines)
              (
                productName: l.productName,
                qty: l.qty,
                unitName: l.unitName,
                note: PosPrintTemplateRuntime.kitchenCallNote(
              l.note,
              l.calledAt ?? sentAt ?? DateTime.now(),
            ),
              ),
          ],
          senderName: senderName.trim().isEmpty ? 'admin' : senderName.trim(),
          sentAt: sentAt ?? DateTime.now(),
          orderNo: (orderNo ?? '').trim(),
          referenceNo: refNo,
          showFeedback: showFeedback,
          successTitle: isCancel ? 'Hủy bếp' : 'Báo bếp',
          skipDedup: skipDedup,
          waitForCompletion: waitForCompletion,
          preferDirectPrint: canLocalPort,
          forceCloud: false,
          onHang: wrapHang(groupLines),
        );
        if (!ok) {
          allOk = false;
          onPrinterFailed?.call(
            printerId: printer.id,
            printerName: printer.name,
            lines: groupLines,
            errorMessage: 'Gửi lệnh in thất bại — ${printer.name}',
          );
        }
      }
      // Món chưa gán, hoặc gán máy Agent không in được khi Agent tắt.
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
        showFeedback: showFeedback,
        onCloudHang: wrapHang(defaultLines),
        onPrinterFailed: onPrinterFailed,
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
    showFeedback: showFeedback,
    onCloudHang: wrapHang(lines),
    onPrinterFailed: onPrinterFailed,
  );
}

/// Khóa chống in trùng: loại phiếu + mã HĐ + (máy) + danh sách món/SL.
String _kitchenDedupReference({
  required String? orderNo,
  required bool isCancel,
  required List<KitchenTicketLine> lines,
  String? printerId,
}) {
  final code = (orderNo ?? '').trim();
  final items = lines
      .map((l) =>
          '${(l.productId ?? '').trim().isNotEmpty ? l.productId : l.productName}:${l.qty}'
          '${l.sentBefore == null ? '' : '@${l.sentBefore}'}'
          '${(l.lineKey ?? '').isEmpty ? '' : '#${l.lineKey}'}')
      .join('|');
  final p = (printerId ?? '').trim();
  final prefix = isCancel ? 'kvoid' : 'ksend';
  // Không dùng μs — dedupRef dùng chung cho mọi lần bấm Hủy cùng order+món.
  // Retry từ pending sheet (skipDedup=true) thêm |r|ms ở caller.
  if (p.isNotEmpty) return kitchenRefFit('$prefix|$code|$p|$items');
  return kitchenRefFit('$prefix|$code|$items');
}

/// PosPrintJobs.ReferenceNo là varchar(64): ref ghép (order + id máy + id món)
/// vượt 64 làm API trả 500 → không tạo được job → phiếu rơi vào hàng chờ.
/// Rút gọn ổn định: giữ đầu ref cho dễ đọc, phần đuôi thay bằng hash.
String kitchenRefFit(String ref, {int maxLen = 64}) {
  if (ref.length <= maxLen) return ref;
  final hash = _kitchenRefHash(ref);
  return '${ref.substring(0, maxLen - hash.length - 1)}~$hash';
}

String _kitchenRefHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

/// In lên máy in bếp theo vai trò (nội bộ KitchenSlip/KitchenVoid hoặc route cloud).
/// Không dùng máy chỉ hóa đơn / singleton nhiệt.
///
/// Thứ tự:
/// 1) Có máy in **nội bộ sẵn sàng** trên thiết bị này → in local (không cần Agent).
/// 2) Không có → đẩy **cloud** (A7/web; A6 chỉ khi không có cổng bếp cục bộ).
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
  bool showFeedback = true,
  PosPrintHangCallback? onCloudHang,
  KitchenPrinterFailedCallback? onPrinterFailed,
}) async {
  if (lines.isEmpty) return false;
  final qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
  final table =
      tableName.trim().isEmpty ? 'Bàn' : tableName.trim();
  final sender =
      senderName.trim().isEmpty ? 'admin' : senderName.trim();
  final code = (orderNo ?? '').trim().isEmpty ? '-' : orderNo!.trim();
  final localRole = isCancel
      ? PosLocalPrinterRoles.kitchenVoid
      : PosLocalPrinterRoles.kitchenSlip;
  final cloudDoc = isCancel
      ? PosCloudDocumentTypes.kitchenVoid
      : PosCloudDocumentTypes.kitchenSlip;
  final at = sentAt ?? DateTime.now();
  final linePayload = [
    for (final l in lines)
      (
        productName: l.productName,
        qty: l.qty,
        unitName: l.unitName,
        note: PosPrintTemplateRuntime.kitchenCallNote(
          l.note,
          l.calledAt ?? at,
        ),
      ),
  ];
  final baseRef = dedupRef ?? (code == '-' ? null : code);
  final refNo = (skipDedup && baseRef != null && baseRef.isNotEmpty)
      ? kitchenRefFit('$baseRef|r|${DateTime.now().millisecondsSinceEpoch}')
      : baseRef;

  // 1) Máy này có cổng in (USB/BT/LAN/Sunmi) → in local, không cần bật Agent.
  if (!kIsWeb) {
    var kitchenLocals =
        await PosLocalPrintersStore.instance.forRoleOnDevice(localRole);
    if (kitchenLocals.isEmpty && isCancel) {
      kitchenLocals = await PosLocalPrintersStore.instance
          .forRoleOnDevice(PosLocalPrinterRoles.kitchenSlip);
    }
    kitchenLocals = _preferExternalKitchenLocals(kitchenLocals);
    if (kitchenLocals.isNotEmpty) {
      final usbList = await PosPrinterReadiness.listUsbDevices();
      final usbProfiles = kitchenLocals
          .where((p) => p.connectionType == PosThermalConnectionType.usb)
          .map((p) => (id: p.id, savedRaw: p.usbDeviceName))
          .toList();
      final usbMatched =
          PosUsbPrinter.matchProfilesExclusive(usbProfiles, usbList);
      final readyLocals = <PosLocalPrinterProfile>[];
      for (final local in kitchenLocals) {
        final matched =
            local.connectionType == PosThermalConnectionType.usb
                ? usbMatched[local.id]
                : null;
        final st = await PosPrinterReadiness.probeLocal(
          local,
          usbList: usbList,
          matchedUsb: matched,
          useMatchedUsbOnly:
              local.connectionType == PosThermalConnectionType.usb,
        );
        if (st == PosPrinterLinkStatus.ready) readyLocals.add(local);
      }
      if (readyLocals.isNotEmpty) {
        if (lines.length > 1 && readyLocals.any((p) => p.cutPerItem)) {
          var splitOk = false;
          for (final line in lines) {
            final ok = await _printKitchenCompactSlipDefault(
              tableName: tableName,
              isCancel: isCancel,
              lines: [line],
              senderName: senderName,
              sentAt: sentAt,
              orderNo: orderNo,
              skipDedup: true,
              dedupRef: kitchenRefFit(
                  '${dedupRef ?? orderNo ?? 'k'}|${line.productName}'),
              waitForCompletion: waitForCompletion,
              showFeedback: false,
              onCloudHang: onCloudHang,
              onPrinterFailed: onPrinterFailed,
            );
            if (ok) splitOk = true;
          }
          if (showFeedback && splitOk) {
            NotificationOverlayManager().showSuccess(
              title: isCancel ? 'Hủy bếp' : 'Báo bếp',
              message: '${lines.length} phiếu (cắt từng món)',
            );
          }
          return splitOk;
        }
        var anyOk = false;
        final tpl = await PosPrintConfigSession.instance
            .kitchenTemplate(isCancel: isCancel, force: true);
        for (final local in readyLocals) {
          final kitchenSettings = local.toThermalSettings().copyWith(
                openCashDrawer: false,
                compactCutFeed: true,
              );
          final v2 = PosPrintTemplateRuntime.resolveOrPreset(
            template: tpl,
            documentType: isCancel
                ? PosPrintDocumentTypes.kitchenVoid
                : PosPrintDocumentTypes.kitchenSlip,
            paperSize: kitchenSettings.paperSize,
            printerProfile: PosPrintPrinterProfiles.forPaperAndBrand(
              paperSize: kitchenSettings.paperSize,
              isSunmi: kitchenSettings.connectionType ==
                      PosThermalConnectionType.sunmi ||
                  kitchenSettings.printerBrand ==
                      PosThermalPrinterBrand.sunmi,
              isZywell: kitchenSettings.printerBrand ==
                  PosThermalPrinterBrand.zywell,
            ),
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
                  note: PosPrintTemplateRuntime.kitchenCallNote(
                    l.note,
                    l.calledAt ?? at,
                  ),
                ),
            ],
            senderName: sender,
            orderNo: code == '-' ? '' : code,
            sentAt: at,
          );
          if (kitchenSettings.connectionType ==
              PosThermalConnectionType.sunmi) {
            try {
              final ok = await PosPrintTemplateRuntime.printCompiledSunmi(
                output: output,
                settings: kitchenSettings.copyWith(
                  connectionType: PosThermalConnectionType.sunmi,
                  printerBrand: PosThermalPrinterBrand.sunmi,
                ),
                kitchenFeed: true,
              );
              if (ok) {
                anyOk = true;
                break;
              }
              continue;
            } catch (e) {
              debugPrint('Sunmi kitchen template print failed: $e');
            }
          }
          try {
            final bytes =
                await PosPrintTemplateRuntime.buildCompiledEscPosBytes(
              output: output,
              settings: kitchenSettings,
            );
            final ok =
                await PosPrintOrchestrator.instance.dispatchLocalEscPos(
              bytes: bytes,
              showFeedback: showFeedback,
              successTitle: isCancel ? 'Hủy bếp' : 'Báo bếp',
              settingsOverride: kitchenSettings,
              skipDedup: skipDedup,
              documentType: cloudDoc,
              referenceNo: refNo,
              // Luôn chờ local thật — waitForCompletion=false trả OK giả.
              waitForCompletion: true,
            );
            if (ok) {
              anyOk = true;
              break;
            }
          } catch (e) {
            debugPrint('Local kitchen template print failed: $e');
          }
        }
        if (anyOk) return true;
      }
    }
  }

  // 2) Không có máy nội bộ sẵn sàng → cloud về Agent (A7 → A6).
  // Phiếu bếp mặc định: chỉ 1 máy (isDefault hoặc máy đầu) — tránh in hết
  // USB + WiFi khi món chưa gán / fallback.
  await PosPrintOrchestrator.instance.refreshConfig();
  var cloudPrinters =
      PosPrintOrchestrator.instance.resolvePrinters(cloudDoc);
  if (cloudPrinters.isEmpty && isCancel) {
    cloudPrinters = PosPrintOrchestrator.instance
        .resolvePrinters(PosCloudDocumentTypes.kitchenSlip);
  }
  if (cloudPrinters.isEmpty) {
    debugPrint(
      'Kitchen: không có máy cloud cho $cloudDoc — kiểm tra gán Phiếu chế biến',
    );
    if (showFeedback) {
      NotificationOverlayManager().showError(
        title: isCancel ? 'Không gửi hủy bếp' : 'Không gửi báo bếp',
        message: tr('Chưa gán máy in Phiếu chế biến (cloud/Agent)'),
        relatedEntityType: kPosPrintNotifyKind,
      );
    }
    return false;
  }
  cloudPrinters = _preferExternalKitchenCloud(cloudPrinters);
  if (cloudPrinters.length > 1) {
    final picked = cloudPrinters.first;
    debugPrint(
      'Kitchen default: ${cloudPrinters.length} máy cloud → chỉ «${picked.name}» '
      '(${picked.connectionType}, không dùng isDefault hóa đơn)',
    );
    cloudPrinters = [picked];
  }

  debugPrint(
    'Kitchen cloud → ${cloudPrinters.map((p) => p.name).join(", ")} '
    '(orchestrator decides local vs cloud, feedback=$showFeedback)',
  );
  var anyCloudOk = false;
  for (var i = 0; i < cloudPrinters.length; i++) {
    final p = cloudPrinters[i];
    final ok = await PosPrintOrchestrator.instance.dispatchKitchenSlip(
      printer: p,
      tableName: table,
      isCancel: isCancel,
      lines: linePayload,
      senderName: sender,
      sentAt: at,
      orderNo: code == '-' ? '' : code,
      referenceNo: refNo,
      // Chỉ toast 1 lần (máy đầu) — overlay đã coalesce pos_print.
      showFeedback: showFeedback && i == 0,
      successTitle: isCancel ? 'Hủy bếp' : 'Báo bếp',
      skipDedup: skipDedup,
      waitForCompletion: waitForCompletion,
      preferDirectPrint: true,
      // A7 không có cổng → orchestrator tự cloud. A6 có cổng → in local dù Agent tắt.
      forceCloud: false,
      onHang: onCloudHang,
    );
    if (ok) {
      anyCloudOk = true;
    } else {
      onPrinterFailed?.call(
        printerId: p.id,
        printerName: p.name,
        lines: lines,
        errorMessage: 'Gửi lệnh in thất bại — ${p.name}',
      );
    }
  }
  return anyCloudOk;
}

/// USB/LAN/BT bếp trước máy in trong Sunmi. `isDefault` thường là hóa đơn.
List<PosLocalPrinterProfile> _preferExternalKitchenLocals(
  List<PosLocalPrinterProfile> locals,
) {
  if (locals.isEmpty) return locals;
  final ranked = [...locals]..sort((a, b) =>
      _kitchenPortRank(a.connectionType).compareTo(_kitchenPortRank(b.connectionType)));
  final external = ranked
      .where((p) => p.connectionType != PosThermalConnectionType.sunmi)
      .toList();
  return external.isNotEmpty ? external : ranked;
}

List<PosStorePrinter> _preferExternalKitchenCloud(List<PosStorePrinter> printers) {
  if (printers.length <= 1) return printers;
  final ranked = [...printers]..sort((a, b) {
      final byPort = _kitchenCloudRank(a).compareTo(_kitchenCloudRank(b));
      if (byPort != 0) return byPort;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  final external = ranked.where((p) => !p.isSunmi).toList();
  return external.isNotEmpty ? external : ranked;
}

int _kitchenPortRank(PosThermalConnectionType t) => switch (t) {
      PosThermalConnectionType.usb => 0,
      PosThermalConnectionType.lan => 1,
      PosThermalConnectionType.bluetooth => 2,
      PosThermalConnectionType.sunmi => 3,
    };

int _kitchenCloudRank(PosStorePrinter p) {
  if (p.isUsb) return 0;
  if (p.isLan) return 1;
  if (p.isBluetooth) return 2;
  if (p.isSunmi) return 3;
  return 2;
}

/// Không remap local → twin Agent. Dùng khi Agent tắt để in đúng máy cục bộ.
PosStorePrinter? _kitchenPrinterWithoutCloudRemap(String id) {
  final want = id.trim().toLowerCase();
  if (want.isEmpty) return null;
  return PosPrintOrchestrator.instance.printers
      .where((x) => x.id.toLowerCase() == want)
      .firstOrNull;
}

Future<bool> _kitchenHasLocalSlipPrinters() async {
  if (kIsWeb) return false;
  var locals = await PosLocalPrintersStore.instance
      .forRoleOnDevice(PosLocalPrinterRoles.kitchenSlip);
  if (locals.isEmpty) {
    locals = await PosLocalPrintersStore.instance
        .forRoleOnDevice(PosLocalPrinterRoles.kitchenVoid);
  }
  return locals.isNotEmpty;
}

Future<bool> _kitchenAssignedHasLocalPort(PosStorePrinter printer) async {
  if (kIsWeb) return false;
  final local =
      await PosLocalPrintersStore.instance.resolveForStorePrinter(printer);
  if (local != null &&
      PosLocalPrintersStore.profileAllowsDirectLocal(local)) {
    return true;
  }
  return printer.isSunmi && await PosPrinterTransport.isSunmiDevice();
}

