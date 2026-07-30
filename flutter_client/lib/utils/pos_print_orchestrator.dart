import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/hrm.dart';
import '../models/pos_sale_order.dart';
import '../models/pos_store_printer.dart';
import '../services/api_service.dart';
import '../services/pos_print_agent_service.dart';
import '../services/signalr_service.dart';
import '../widgets/notification_overlay.dart';
import 'pos_device_identity.dart';
import 'pos_label_printer_service.dart';
import 'pos_print_agent_settings.dart';
import 'pos_print_role.dart';
import 'pos_printer_transport.dart';
import 'pos_receipt_layout.dart';
import 'pos_store_printer_mapper.dart';
import 'pos_sunmi_native_print.dart';
import 'pos_thermal_printer_service.dart';
import 'pos_thermal_printer_settings.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Điều phối in cloud qua Máy in cửa hàng + Print Agent.
/// In LAN/BT cục bộ: dùng [dispatchLocalEscPos] (Thiết lập máy in nhiệt).
class PosPrintOrchestrator {
  PosPrintOrchestrator._();
  static final PosPrintOrchestrator instance = PosPrintOrchestrator._();

  final _api = ApiService();
  final _signalR = SignalRService();
  final _pendingJobs = <String, Completer<_JobOutcome>>{};
  final _jobMeta = <String, _JobFeedbackMeta>{};
  final _feedbackSent = <String>{};

  List<PosStorePrinter> _printers = [];
  List<PosPrinterRoute> _routes = [];
  DateTime? _cacheAt;
  StreamSubscription<Map<String, dynamic>>? _statusSub;
  bool _listening = false;

  static const _cacheTtl = Duration(minutes: 3);
  static const _jobTimeout = Duration(seconds: 90);

  Future<void> ensureListening() async {
    if (_listening) return;
    _listening = true;
    _statusSub = _signalR.onPrintJobStatusChanged.listen(_onJobStatus);
  }

  void dispose() {
    _statusSub?.cancel();
    _listening = false;
    for (final c in _pendingJobs.values) {
      if (!c.isCompleted) {
        c.complete(const _JobOutcome(false, 'Đã hủy'));
      }
    }
    _pendingJobs.clear();
    _jobMeta.clear();
    _feedbackSent.clear();
  }

  void _finishJob(String jobId, _JobOutcome outcome, {bool showFeedback = true}) {
    final completer = _pendingJobs[jobId];
    if (completer != null && !completer.isCompleted) {
      completer.complete(outcome);
    }
    _pendingJobs.remove(jobId);
    if (!showFeedback || _feedbackSent.contains(jobId)) {
      _jobMeta.remove(jobId);
      return;
    }
    _feedbackSent.add(jobId);
    _jobMeta.remove(jobId);

    if (outcome.ok) {
      // Máy gửi lệnh: không toast thêm khi agent xa in xong (tránh trùng "nhận in").
      return;
    }
    NotificationOverlayManager().showError(
      title: 'In thất bại',
      message: outcome.error ?? 'Không in được chứng từ',
    );
  }

  void _onJobStatus(Map<String, dynamic> data) {
    final jobId = data['jobId']?.toString() ?? data['id']?.toString() ?? '';
    if (jobId.isEmpty) return;
    if (!_pendingJobs.containsKey(jobId)) return;

    final status = data['status']?.toString() ?? '';
    final printerName = data['printerName']?.toString() ?? '';
    final error = data['errorMessage']?.toString();

    if (status == 'Completed') {
      _finishJob(
        jobId,
        _JobOutcome(true, null, printerName: printerName),
      );
    } else if (status == 'Failed' ||
        status == 'Expired' ||
        status == 'Cancelled') {
      _finishJob(
        jobId,
        _JobOutcome(false, error ?? 'In thất bại', printerName: printerName),
      );
    }
  }

  Future<void> invalidateCache() async {
    _cacheAt = null;
    _printers = [];
    _routes = [];
  }

  Future<bool> refreshConfig({bool force = false}) async {
    if (!force &&
        _cacheAt != null &&
        DateTime.now().difference(_cacheAt!) < _cacheTtl &&
        _printers.isNotEmpty) {
      return true;
    }
    try {
      final printersRes = await _api.getPosStorePrinters();
      if (printersRes['isSuccess'] != true) return false;
      final routesRes = await _api.getPosPrinterRoutes();
      _printers = (printersRes['data'] as List? ?? [])
          .map((e) => PosStorePrinter.fromJson(e as Map<String, dynamic>))
          .where((p) => p.isActive)
          .toList();
      _routes = (routesRes['data'] as List? ?? [])
          .map((e) => PosPrinterRoute.fromJson(e as Map<String, dynamic>))
          .toList();
      _cacheAt = DateTime.now();
      return _printers.isNotEmpty;
    } catch (e) {
      debugPrint('PosPrintOrchestrator.refreshConfig: $e');
      return false;
    }
  }

  List<PosStorePrinter> get printers => List.unmodifiable(_printers);

  PosStorePrinter? resolvePrinter(String documentType) {
    final list = resolvePrinters(documentType);
    return list.isEmpty ? null : list.first;
  }

  /// Tất cả máy in gán cho loại chứng từ (in đa máy).
  List<PosStorePrinter> resolvePrinters(String documentType) {
    if (_printers.isEmpty) return const [];

    final routed = _routes
        .where((r) => r.documentType == documentType)
        .map((r) => _printers.where((p) => p.id == r.printerId).firstOrNull)
        .whereType<PosStorePrinter>()
        .toList();
    if (routed.isNotEmpty) return routed;

    final tagged =
        _printers.where((p) => p.documentTypes.contains(documentType)).toList();
    if (tagged.isNotEmpty) return tagged;

    if (_printers.length == 1) return [_printers.first];

    final def = _printers.where((p) => p.isDefault).firstOrNull ?? _printers.firstOrNull;
    return def != null ? [def] : const [];
  }

  int copiesFor(String documentType, {String? printerId, int fallback = 1}) {
    if (printerId != null && printerId.isNotEmpty) {
      final perPrinter = _routes
          .where((r) =>
              r.documentType == documentType && r.printerId == printerId)
          .firstOrNull;
      if (perPrinter != null) return perPrinter.defaultCopies;
    }
    final route =
        _routes.where((r) => r.documentType == documentType).firstOrNull;
    return route?.defaultCopies ?? fallback;
  }

  /// Gửi byte ESC/POS qua cloud (Máy in cửa hàng → Print Agent).
  ///
  /// [forceCloud]: bỏ qua in trực tiếp trên Agent — luôn enqueue cloud
  /// (dùng cho «Test in qua cloud» trên chính máy Sunmi).
  Future<bool> dispatchEscPos({
    required String documentType,
    required List<int> bytes,
    int copies = 1,
    String? referenceNo,
    String? referenceId,
    String? printerId,
    bool showFeedback = true,
    String? successTitle,
    bool waitForCompletion = true,
    bool skipDedup = false,
    bool forceCloud = false,
  }) async {
    if (kIsWeb) return false;

    if (!skipDedup &&
        PosPrintDedup.shouldSkip(
          documentType: documentType,
          referenceId: referenceId,
          referenceNo: referenceNo,
          printerId: printerId,
        )) {
      return true;
    }

    await ensureListening();
    final hasCloud = await refreshConfig();
    PosStorePrinter? printer = printerId != null
        ? _printers.where((p) => p.id == printerId).firstOrNull
        : null;
    printer ??= resolvePrinter(documentType);

    if (printer != null) {
      final n = copies.clamp(1, 10);

      // Thiết bị gắn máy in → in trực tiếp, không qua cloud (trừ forceCloud).
      if (!forceCloud && await PosPrintRole.isAgentForPrinter(printer.id)) {
        return _printDirectOnStorePrinter(
          printer: printer,
          bytes: bytes,
          copies: n,
          referenceNo: referenceNo,
          showFeedback: showFeedback,
          successTitle: successTitle,
        );
      }

      if (!hasCloud) return false;
      final payload = base64Encode(bytes);
      final res = await _api.createPosPrintJob(
        documentType: documentType,
        payloadFormat: 'EscPosBase64',
        payload: payload,
        copies: n,
        referenceNo: referenceNo,
        referenceId: referenceId,
        printerId: printer.id,
      );
      if (res['isSuccess'] != true) {
        if (showFeedback) {
          NotificationOverlayManager().showError(
            title: 'Không gửi lệnh in',
            message: res['message']?.toString() ?? 'Lỗi máy chủ',
          );
        }
        return false;
      }

      final data = res['data'] as Map<String, dynamic>?;
      final jobId = data?['jobId']?.toString() ?? '';
      if (jobId.isEmpty) return false;

      // Fail nhanh khi chắc chắn không có Agent nào online cho máy in này —
      // tránh báo "Đã gửi lệnh in" giả khi job sẽ nằm hàng đợi rồi tự hủy
      // sau 20 phút mà không ai biết (trang lưu hóa đơn "in không ra").
      if (_failFastNoAgent(printer, data, jobId, showFeedback: showFeedback)) {
        return false;
      }

      PosPrintSessionRegistry.markOutbound(jobId);

      _jobMeta[jobId] = _JobFeedbackMeta(
        referenceNo: referenceNo,
        printerName: printer.name,
      );

      if (showFeedback) {
        final ref = referenceNo?.trim() ?? '';
        NotificationOverlayManager().show(
          title: 'Đã gửi lệnh in',
          message: ref.isNotEmpty
              ? 'Đơn $ref → ${printer.name}'
              : 'Đã gửi tới Print Agent (${printer.name})',
          type: NotificationType.success,
          duration: const Duration(seconds: 3),
        );
      }

      if (!waitForCompletion) {
        // Không chặn UI, nhưng vẫn theo dõi ngầm để báo lỗi thật nếu job
        // kẹt/hết hạn — trước đây bỏ qua hoàn toàn nên mất tích không dấu vết.
        unawaited(
          _waitJob(jobId, showFeedback: true).whenComplete(
            () => PosPrintSessionRegistry.clearOutbound(jobId),
          ),
        );
        return true;
      }

      final outcome = await _waitJob(jobId, showFeedback: showFeedback);
      PosPrintSessionRegistry.clearOutbound(jobId);
      return outcome.ok;
    }

    return false;
  }

  /// In cùng lúc lên mọi máy in được gán cho [documentType].
  Future<bool> dispatchEscPosToAll({
    required String documentType,
    required Future<List<int>> Function(PosStorePrinter printer) buildBytes,
    int copies = 1,
    String? referenceNo,
    String? referenceId,
    bool showFeedback = true,
    String? successTitle,
    bool skipDedup = false,
  }) async {
    if (kIsWeb) return false;

    if (!skipDedup &&
        PosPrintDedup.shouldSkip(
          documentType: documentType,
          referenceId: referenceId,
          referenceNo: referenceNo,
        )) {
      return true;
    }

    await ensureListening();
    await refreshConfig();
    final printers = resolvePrinters(documentType);
    if (printers.isEmpty) return false;

    var okCount = 0;
    var failCount = 0;
    final okNames = <String>[];

    for (final printer in printers) {
      final bytes = await buildBytes(printer);
      final n = copiesFor(documentType, printerId: printer.id, fallback: copies);
      final isAgent = await PosPrintRole.isAgentForPrinter(printer.id);
      final ok = await dispatchEscPos(
        documentType: documentType,
        bytes: bytes,
        copies: n,
        referenceNo: referenceNo,
        referenceId: referenceId,
        printerId: printer.id,
        showFeedback: false,
        successTitle: successTitle,
        waitForCompletion: isAgent,
        skipDedup: true,
      );
      if (ok) {
        okCount++;
        okNames.add(printer.name);
      } else {
        failCount++;
      }
    }

    if (showFeedback) {
      final ref = referenceNo?.trim() ?? '';
      if (okCount > 0) {
        final names = okNames.join(', ');
        NotificationOverlayManager().show(
          title: okCount > 1 ? 'Đã gửi lệnh in ($okCount máy)' : 'Đã gửi lệnh in',
          message: ref.isNotEmpty ? 'Đơn $ref → $names' : names,
          type: NotificationType.success,
          duration: const Duration(seconds: 4),
        );
      }
      if (failCount > 0) {
        NotificationOverlayManager().showError(
          title: 'In thất bại',
          message: failCount == printers.length
              ? 'Không in được trên máy in đã chọn'
              : '$failCount/${printers.length} máy in không in được',
        );
      }
    }

    return okCount > 0;
  }

  /// In hóa đơn qua cloud — Sunmi dùng native (giống máy in nội bộ), máy khác ESC/POS.
  Future<bool> dispatchSaleOrder({
    required PosSaleOrder order,
    required Future<List<int>> Function(PosStorePrinter printer) buildEscPos,
    String? storeName,
    String? storeAddress,
    String? storePhone,
    bool mergeSameItems = true,
    String? documentTitle,
    int copies = 1,
    String? referenceNo,
    String? referenceId,
    bool showFeedback = true,
    String? successTitle,
    bool skipDedup = false,
  }) async {
    if (kIsWeb) return false;

    if (!skipDedup &&
        PosPrintDedup.shouldSkip(
          documentType: PosCloudDocumentTypes.saleInvoice,
          referenceId: referenceId,
          referenceNo: referenceNo,
        )) {
      return true;
    }

    await ensureListening();
    await refreshConfig();
    final printers = resolvePrinters(PosCloudDocumentTypes.saleInvoice);
    if (printers.isEmpty) return false;

    var okCount = 0;
    var failCount = 0;
    final okNames = <String>[];

    for (final printer in printers) {
      final n = copiesFor(
        PosCloudDocumentTypes.saleInvoice,
        printerId: printer.id,
        fallback: copies,
      );
      final isAgent = await PosPrintRole.isAgentForPrinter(printer.id);
      final onSunmiHw = await PosPrinterTransport.isSunmiDevice();
      final useNative = printer.isSunmi && (isAgent ? onSunmiHw : true);

      bool ok;
      if (useNative && isAgent && onSunmiHw) {
        ok = await _printSaleNativeOnThisDevice(
          printer: printer,
          order: order,
          copies: n,
          storeName: storeName,
          storeAddress: storeAddress,
          storePhone: storePhone,
          mergeSameItems: mergeSameItems,
          documentTitle: documentTitle,
          referenceNo: referenceNo,
          showFeedback: false,
          successTitle: successTitle,
        );
      } else if (useNative && !isAgent) {
        ok = await _enqueueSaleOrderJson(
          printer: printer,
          order: order,
          copies: n,
          storeName: storeName,
          storeAddress: storeAddress,
          storePhone: storePhone,
          mergeSameItems: mergeSameItems,
          documentTitle: documentTitle,
          referenceNo: referenceNo,
          referenceId: referenceId,
          showFeedback: false,
          // Không chờ Completed cứng: Agent nhận/Printing = đã in được trên máy online.
          waitForCompletion: false,
        );
      } else {
        final bytes = await buildEscPos(printer);
        ok = await dispatchEscPos(
          documentType: PosCloudDocumentTypes.saleInvoice,
          bytes: bytes,
          copies: n,
          referenceNo: referenceNo,
          referenceId: referenceId,
          printerId: printer.id,
          showFeedback: false,
          successTitle: successTitle,
          waitForCompletion: isAgent,
          skipDedup: true,
        );
      }

      if (ok) {
        okCount++;
        okNames.add(printer.name);
      } else {
        failCount++;
      }
    }

    if (showFeedback) {
      final ref = referenceNo?.trim() ?? '';
      if (okCount > 0) {
        final names = okNames.join(', ');
        NotificationOverlayManager().show(
          title: okCount > 1 ? 'Đã gửi lệnh in ($okCount máy)' : 'Đã gửi lệnh in',
          message: ref.isNotEmpty ? 'Đơn $ref → $names' : names,
          type: NotificationType.success,
          duration: const Duration(seconds: 4),
        );
      }
      if (failCount > 0) {
        NotificationOverlayManager().showError(
          title: 'In thất bại',
          message: failCount == printers.length
              ? 'Không in được trên máy in đã chọn'
              : '$failCount/${printers.length} máy in không in được',
        );
      }
    }

    return okCount > 0;
  }

  Future<bool> _printSaleNativeOnThisDevice({
    required PosStorePrinter printer,
    required PosSaleOrder order,
    required int copies,
    String? storeName,
    String? storeAddress,
    String? storePhone,
    bool mergeSameItems = true,
    String? documentTitle,
    String? referenceNo,
    bool showFeedback = true,
    String? successTitle,
  }) async {
    final settings = toThermalSettings(printer);
    final ref = referenceNo?.trim() ?? '';
    if (showFeedback) {
      NotificationOverlayManager().show(
        title: 'Đã nhận lệnh in',
        message: ref.isNotEmpty
            ? 'Đơn $ref — đang in trên ${printer.name}…'
            : 'Đang in trên ${printer.name}…',
        duration: const Duration(seconds: 4),
      );
    }

    var ok = true;
    for (var i = 0; i < copies.clamp(1, 10); i++) {
      final sent = await PosSunmiNativePrint.printSaleOrder(
        order,
        settings: settings,
        storeName: storeName,
        storeAddress: storeAddress,
        storePhone: storePhone,
        mergeSameItems: mergeSameItems,
        copies: 1,
        documentTitle: documentTitle,
      );
      if (!sent) {
        ok = false;
        break;
      }
    }

    if (ok) {
      unawaited(_api.reportPosPrinterHealth(printer.id, status: 'Online'));
      if (showFeedback) {
        NotificationOverlayManager().showSuccess(
          title: successTitle ?? 'In xong',
          message: ref.isNotEmpty ? 'Đơn $ref — ${printer.name}' : printer.name,
        );
      }
      return true;
    }
    unawaited(_api.reportPosPrinterHealth(
      printer.id,
      status: 'Offline',
      errorMessage: 'Sunmi native print failed',
    ));
    if (showFeedback) {
      NotificationOverlayManager().showError(
        title: 'In thất bại',
        message: tr('Không in được trên ${printer.name}'),
      );
    }
    return false;
  }

  Future<bool> _enqueueSaleOrderJson({
    required PosStorePrinter printer,
    required PosSaleOrder order,
    required int copies,
    String? storeName,
    String? storeAddress,
    String? storePhone,
    bool mergeSameItems = true,
    String? documentTitle,
    String? referenceNo,
    String? referenceId,
    bool showFeedback = true,
    bool waitForCompletion = true,
  }) async {
    // Gửi kèm full order — Agent in native giống Oppo, không phụ thuộc getPosSale.
    final payload = jsonEncode({
      'orderId': order.id,
      'order': order.toPrintAgentJson(),
      'storeName': storeName,
      'storeAddress': storeAddress,
      'storePhone': storePhone,
      'mergeSameItems': mergeSameItems,
      'documentTitle': documentTitle,
    });
    final res = await _api.createPosPrintJob(
      documentType: PosCloudDocumentTypes.saleInvoice,
      payloadFormat: 'SaleOrderJson',
      payload: payload,
      copies: copies.clamp(1, 10),
      referenceNo: referenceNo,
      referenceId: referenceId ?? order.id,
      printerId: printer.id,
    );
    if (res['isSuccess'] != true) {
      if (showFeedback) {
        NotificationOverlayManager().showError(
          title: 'Không gửi lệnh in',
          message: res['message']?.toString() ?? 'Lỗi máy chủ',
        );
      }
      return false;
    }
    final data = res['data'] as Map<String, dynamic>?;
    final jobId = data?['jobId']?.toString() ?? '';
    if (jobId.isEmpty) return false;

    if (_failFastNoAgent(printer, data, jobId, showFeedback: showFeedback)) {
      return false;
    }

    PosPrintSessionRegistry.markOutbound(jobId);
    if (showFeedback) {
      final ref = referenceNo?.trim() ?? '';
      NotificationOverlayManager().show(
        title: 'Đã gửi lệnh in',
        message: ref.isNotEmpty
            ? 'Đơn $ref → ${printer.name}'
            : 'Đã gửi tới Print Agent (${printer.name})',
        type: NotificationType.success,
        duration: const Duration(seconds: 3),
      );
    }
    if (!waitForCompletion) {
      unawaited(
        _waitJob(jobId, showFeedback: true).whenComplete(
          () => PosPrintSessionRegistry.clearOutbound(jobId),
        ),
      );
      return true;
    }
    final outcome = await _waitJob(jobId, showFeedback: showFeedback);
    PosPrintSessionRegistry.clearOutbound(jobId);
    return outcome.ok;
  }

  /// Trả `true` (đã tự fail job) khi máy in cần Agent nhưng server báo không
  /// có Agent nào online — tránh chờ 90s hoặc báo "đã gửi" giả.
  bool _failFastNoAgent(
    PosStorePrinter printer,
    Map<String, dynamic>? data,
    String jobId, {
    bool showFeedback = true,
  }) {
    final agentsOnline = data?['agentOnlineForPrinter'];
    if (!printer.requiresAgent ||
        agentsOnline is! num ||
        agentsOnline.toInt() > 0) {
      return false;
    }
    if (showFeedback) {
      NotificationOverlayManager().showError(
        title: 'Không có Print Agent',
        message: tr('${printer.name} chưa có Agent online. Mở app trên máy gắn máy in này → Bật Agent.'),
      );
    }
    unawaited(_api.failPosPrintJob(
      jobId,
      '',
      errorCode: 'NO_AGENT',
      errorMessage: 'Không có Agent online cho máy in',
    ));
    return true;
  }

  /// Phiếu xuất kho / báo chế biến kho → Agent Sunmi native (không ESC/POS).
  Future<bool> enqueueWarehouseSlipJson({
    required PosStorePrinter printer,
    required PosSaleOrder order,
    required List<PosSaleOrderLine> lines,
    String? storeName,
    String? storeAddress,
    String? storePhone,
    String? slipTitle,
    bool showFeedback = false,
    bool waitForCompletion = true,
  }) async {
    final payload = jsonEncode({
      'orderId': order.id,
      'order': order.toPrintAgentJson(),
      'linesOverride': lines.map((l) => l.toPrintAgentJson()).toList(),
      'warehouseSlip': true,
      'slipTitle': slipTitle,
      'documentTitle': slipTitle,
      'storeName': storeName,
      'storeAddress': storeAddress,
      'storePhone': storePhone,
      'mergeSameItems': false,
    });
    final res = await _api.createPosPrintJob(
      documentType: PosCloudDocumentTypes.stockIssue,
      payloadFormat: 'SaleOrderJson',
      payload: payload,
      copies: 1,
      referenceNo: order.orderNo.isEmpty ? null : order.orderNo,
      referenceId: order.id.isEmpty ? null : order.id,
      printerId: printer.id,
    );
    if (res['isSuccess'] != true) {
      if (showFeedback) {
        NotificationOverlayManager().showError(
          title: 'Không gửi phiếu kho',
          message: res['message']?.toString() ?? 'Lỗi máy chủ',
        );
      }
      return false;
    }
    final data = res['data'] as Map<String, dynamic>?;
    final jobId = data?['jobId']?.toString() ?? '';
    if (jobId.isEmpty) return false;

    if (_failFastNoAgent(printer, data, jobId, showFeedback: showFeedback)) {
      return false;
    }

    PosPrintSessionRegistry.markOutbound(jobId);
    PosPrintAgentService.instance.nudgeClaim();
    if (!waitForCompletion) {
      unawaited(
        _waitJob(jobId, showFeedback: true).whenComplete(
          () => PosPrintSessionRegistry.clearOutbound(jobId),
        ),
      );
      return true;
    }
    final outcome = await _waitJob(jobId, showFeedback: showFeedback);
    PosPrintSessionRegistry.clearOutbound(jobId);
    return outcome.ok;
  }

  /// In phiếu báo chế biến / hủy — Sunmi dùng native (UTF-8), máy khác ESC/POS.
  Future<bool> dispatchKitchenSlip({
    required PosStorePrinter printer,
    required String tableName,
    required bool isCancel,
    required List<({
      String productName,
      double qty,
      String? unitName,
      String? note,
    })> lines,
    required String senderName,
    required DateTime sentAt,
    String? orderNo,
    String? referenceNo,
    bool showFeedback = false,
    String? successTitle,
    bool skipDedup = false,
    bool waitForCompletion = true,
  }) async {
    if (kIsWeb || lines.isEmpty) return false;

    if (!skipDedup &&
        PosPrintDedup.shouldSkip(
          documentType: PosCloudDocumentTypes.stockIssue,
          referenceNo: referenceNo,
          printerId: printer.id,
        )) {
      return true;
    }

    final isAgent = await PosPrintRole.isAgentForPrinter(printer.id);
    final onSunmiHw = await PosPrinterTransport.isSunmiDevice();
    final useNative = printer.isSunmi && (isAgent ? onSunmiHw : true);

    if (useNative && isAgent && onSunmiHw) {
      return _printKitchenNativeOnThisDevice(
        printer: printer,
        tableName: tableName,
        isCancel: isCancel,
        lines: lines,
        senderName: senderName,
        sentAt: sentAt,
        orderNo: orderNo,
        showFeedback: showFeedback,
        successTitle: successTitle,
      );
    }

    if (useNative && !isAgent) {
      return _enqueueKitchenSlipJson(
        printer: printer,
        tableName: tableName,
        isCancel: isCancel,
        lines: lines,
        senderName: senderName,
        sentAt: sentAt,
        orderNo: orderNo,
        referenceNo: referenceNo,
        showFeedback: showFeedback,
        waitForCompletion: waitForCompletion,
      );
    }

    final qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
    final timeFmt = DateFormat('dd/MM/yyyy HH:mm');
    final table = tableName.trim().isEmpty ? 'Bàn' : tableName.trim();
    final sender = senderName.trim().isEmpty ? 'admin' : senderName.trim();
    final code = (orderNo ?? '').trim().isEmpty ? '-' : orderNo!.trim();
    final when = timeFmt.format(sentAt);
    final settings = toThermalSettings(printer).copyWith(
      feedBeforeCut: 12,
      openCashDrawer: false,
    );
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
    final bytes = await PosThermalPrinterService.buildTextEscPosBytes(
      settings: settings,
      title: table,
      lines: body,
    );
    return dispatchEscPos(
      documentType: PosCloudDocumentTypes.stockIssue,
      bytes: bytes,
      printerId: printer.id,
      referenceNo: referenceNo,
      showFeedback: showFeedback,
      successTitle: successTitle,
      waitForCompletion: waitForCompletion,
      skipDedup: skipDedup,
    );
  }

  Future<bool> _printKitchenNativeOnThisDevice({
    required PosStorePrinter printer,
    required String tableName,
    required bool isCancel,
    required List<({
      String productName,
      double qty,
      String? unitName,
      String? note,
    })> lines,
    required String senderName,
    required DateTime sentAt,
    String? orderNo,
    bool showFeedback = true,
    String? successTitle,
  }) async {
    final settings = toThermalSettings(printer).copyWith(
      feedBeforeCut: 12,
      openCashDrawer: false,
    );
    final qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
    final ok = await PosSunmiNativePrint.printKitchenSlip(
      tableName: tableName,
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
      senderName: senderName,
      orderNo: orderNo ?? '',
      sentAt: sentAt,
      settings: settings.copyWith(
        connectionType: PosThermalConnectionType.sunmi,
        printerBrand: PosThermalPrinterBrand.sunmi,
      ),
    );
    if (ok) {
      unawaited(_api.reportPosPrinterHealth(printer.id, status: 'Online'));
      if (showFeedback) {
        NotificationOverlayManager().showSuccess(
          title: successTitle ?? (isCancel ? 'Hủy bếp' : 'Báo bếp'),
          message: printer.name,
        );
      }
      return true;
    }
    unawaited(_api.reportPosPrinterHealth(
      printer.id,
      status: 'Offline',
      errorMessage: 'Sunmi kitchen native failed',
    ));
    if (showFeedback) {
      NotificationOverlayManager().showError(
        title: 'In thất bại',
        message: tr('Không in được trên ${printer.name}'),
      );
    }
    return false;
  }

  Future<bool> _enqueueKitchenSlipJson({
    required PosStorePrinter printer,
    required String tableName,
    required bool isCancel,
    required List<({
      String productName,
      double qty,
      String? unitName,
      String? note,
    })> lines,
    required String senderName,
    required DateTime sentAt,
    String? orderNo,
    String? referenceNo,
    bool showFeedback = true,
    bool waitForCompletion = true,
  }) async {
    await ensureListening();
    final payload = jsonEncode({
      'tableName': tableName,
      'isCancel': isCancel,
      'senderName': senderName,
      'orderNo': orderNo ?? '',
      'sentAt': sentAt.toUtc().toIso8601String(),
      'lines': [
        for (final l in lines)
          {
            'productName': l.productName,
            'qty': l.qty,
            if (l.unitName != null && l.unitName!.trim().isNotEmpty)
              'unitName': l.unitName!.trim(),
            if (l.note != null && l.note!.trim().isNotEmpty) 'note': l.note!.trim(),
          },
      ],
    });
    final res = await _api.createPosPrintJob(
      documentType: PosCloudDocumentTypes.stockIssue,
      payloadFormat: 'KitchenSlipJson',
      payload: payload,
      copies: 1,
      referenceNo: referenceNo,
      printerId: printer.id,
    );
    if (res['isSuccess'] != true) {
      if (showFeedback) {
        NotificationOverlayManager().showError(
          title: 'Không gửi lệnh in',
          message: res['message']?.toString() ?? 'Lỗi máy chủ',
        );
      }
      return false;
    }
    final data = res['data'] as Map<String, dynamic>?;
    final jobId = data?['jobId']?.toString() ?? '';
    if (jobId.isEmpty) return false;

    if (_failFastNoAgent(printer, data, jobId, showFeedback: showFeedback)) {
      return false;
    }

    PosPrintSessionRegistry.markOutbound(jobId);
    if (showFeedback) {
      final ref = referenceNo?.trim() ?? '';
      NotificationOverlayManager().show(
        title: 'Đã gửi lệnh in',
        message: ref.isNotEmpty
            ? '$ref → ${printer.name}'
            : 'Đã gửi tới Print Agent (${printer.name})',
        type: NotificationType.success,
        duration: const Duration(seconds: 3),
      );
    }
    if (!waitForCompletion) {
      unawaited(
        _waitJob(jobId, showFeedback: true).whenComplete(
          () => PosPrintSessionRegistry.clearOutbound(jobId),
        ),
      );
      return true;
    }
    final outcome = await _waitJob(jobId, showFeedback: showFeedback);
    PosPrintSessionRegistry.clearOutbound(jobId);
    return outcome.ok;
  }

  /// In trực tiếp trên thiết bị Agent (máy in gắn tại đây).
  Future<bool> _printDirectOnStorePrinter({
    required PosStorePrinter printer,
    required List<int> bytes,
    required int copies,
    String? referenceNo,
    bool showFeedback = true,
    String? successTitle,
  }) async {
    final settings = toThermalSettings(printer);
    final ref = referenceNo?.trim() ?? '';

    if (showFeedback) {
      NotificationOverlayManager().show(
        title: 'Đã nhận lệnh in',
        message: ref.isNotEmpty
            ? 'Đơn $ref — đang in trên ${printer.name}…'
            : 'Đang in trên ${printer.name}…',
        duration: const Duration(seconds: 4),
      );
    }

    // ESC/POS trên Sunmi: feed nhẹ (đã strip feed trong payload).
    final sunmiFeed = printer.isSunmi ? 4 : settings.resolvedFeedBeforeCut;

    var ok = true;
    for (var i = 0; i < copies; i++) {
      final sent = await PosPrinterTransport.send(
        connectionType: settings.connectionType,
        bluetoothAddress: settings.bluetoothAddress,
        lanHost: settings.lanHost,
        lanPort: settings.lanPort,
        bytes: bytes,
        sunmiFeedLines: sunmiFeed,
      );
      if (!sent) {
        ok = false;
        break;
      }
    }

    if (ok) {
      unawaited(_api.reportPosPrinterHealth(printer.id, status: 'Online'));
      if (showFeedback) {
        NotificationOverlayManager().showSuccess(
          title: successTitle ?? 'In xong',
          message: ref.isNotEmpty
              ? 'Đơn $ref — ${printer.name}'
              : printer.name,
        );
      }
      return true;
    }

    unawaited(_api.reportPosPrinterHealth(
      printer.id,
      status: 'Offline',
      errorMessage: 'Không kết nối được máy in',
    ));
    if (showFeedback) {
      NotificationOverlayManager().showError(
        title: 'In thất bại',
        message: tr('Không kết nối được ${printer.name}'),
      );
    }
    return false;
  }

  /// In trực tiếp trên thiết bị này (Thiết lập máy in nhiệt — LAN/BT/USB cục bộ).
  Future<bool> dispatchLocalEscPos({
    required List<int> bytes,
    int copies = 1,
    bool showFeedback = true,
    String? successTitle,
    PosThermalPrinterSettings? settingsOverride,
    String? documentType,
    String? referenceId,
    String? referenceNo,
    bool skipDedup = false,
  }) async {
    if (kIsWeb) return false;

    if (!skipDedup &&
        documentType != null &&
        PosPrintDedup.shouldSkip(
          documentType: documentType,
          referenceId: referenceId,
          referenceNo: referenceNo,
        )) {
      return true;
    }

    final local = settingsOverride ?? await PosThermalPrinterSettings.load();
    if (!local.enabled) return false;

    for (var c = 0; c < copies.clamp(1, 10); c++) {
      final ok = await _sendLocal(local, bytes);
      if (!ok) {
        if (showFeedback) {
          NotificationOverlayManager().showError(
            title: 'In thất bại',
            message: tr('Không kết nối được máy in cục bộ'),
          );
        }
        return false;
      }
    }
    if (showFeedback) {
      NotificationOverlayManager().showSuccess(
        title: successTitle ?? 'In thành công',
        message: tr('Máy in cục bộ (cùng mạng)'),
      );
    }
    return true;
  }

  Future<bool> _sendLocal(PosThermalPrinterSettings settings, List<int> bytes) =>
      PosPrinterTransport.send(
        connectionType: settings.connectionType,
        bluetoothAddress: settings.bluetoothAddress,
        lanHost: settings.lanHost,
        lanPort: settings.lanPort,
        bytes: bytes,
        sunmiFeedLines: settings.resolvedFeedBeforeCut,
      );

  Future<_JobOutcome> _waitJob(String jobId, {bool showFeedback = true}) async {
    final completer = Completer<_JobOutcome>();
    _pendingJobs[jobId] = completer;

    Timer(_jobTimeout, () {
      if (!completer.isCompleted) {
        _finishJob(
          jobId,
          const _JobOutcome(
            false,
            'Print Agent không nhận lệnh trong 90 giây. '
            'Kiểm tra Sunmi: Agent BẬT + đã chọn chip máy in + app đang mở.',
          ),
          showFeedback: showFeedback,
        );
      }
    });

    unawaited(_pollJobUntilDone(jobId, showFeedback: showFeedback));
    return completer.future;
  }

  Future<void> _pollJobUntilDone(
    String jobId, {
    bool showFeedback = true,
  }) async {
    for (var i = 0; i < 18; i++) {
      if (!_pendingJobs.containsKey(jobId)) return;
      await Future<void>.delayed(const Duration(seconds: 5));
      if (!_pendingJobs.containsKey(jobId)) return;
      try {
        final res = await _api.getPosPrintJob(jobId);
        if (res['isSuccess'] != true || res['data'] is! Map) continue;
        final data = res['data'] as Map;
        final status = data['status']?.toString() ?? '';
        if (status == 'Completed') {
          _finishJob(
            jobId,
            const _JobOutcome(true, null),
            showFeedback: showFeedback,
          );
        } else if (status == 'Failed' || status == 'Expired') {
          final err = data['errorMessage']?.toString();
          _finishJob(
            jobId,
            _JobOutcome(false, err ?? status),
            showFeedback: showFeedback,
          );
        } else if (status == 'Claimed' || status == 'Printing') {
          // Agent đã nhận job — giấy thường đã/ sắp ra. Coi là thành công sớm
          // để máy gửi không báo «không in được» dù Agent online đã in.
          if (i >= 2) {
            _finishJob(
              jobId,
              const _JobOutcome(true, null),
              showFeedback: showFeedback,
            );
          }
        }
      } catch (_) {}
    }
  }

  Future<bool> dispatchLabelJobs({
    required List<List<int>> jobs,
    String? referenceNo,
    bool showFeedback = true,
  }) async {
    if (jobs.isEmpty || kIsWeb) return false;
    for (var i = 0; i < jobs.length; i++) {
      final ok = await dispatchEscPos(
        documentType: PosCloudDocumentTypes.barcodeLabel,
        bytes: jobs[i],
        referenceNo: referenceNo,
        showFeedback: showFeedback && i == jobs.length - 1,
        successTitle: 'In tem thành công',
      );
      if (!ok) return false;
    }
    return true;
  }

  /// [forceRemote]: bỏ qua in native cục bộ — gửi cloud như máy thu ngân (Oppo).
  Future<bool> testPrinter(
    PosStorePrinter printer, {
    bool forceRemote = false,
  }) async {
    if (printer.isLabelPrinter) {
      final settings = toLabelSettings(printer);
      return PosLabelPrinterService.testPrint(settings);
    }

    // Sunmi trên chính máy → in native cục bộ (không qua cloud).
    if (!forceRemote &&
        printer.isSunmi &&
        await PosPrinterTransport.isSunmiDevice()) {
      final settings = toThermalSettings(printer);
      final ok = await PosSunmiNativePrint.printTest(
        storeLabel: printer.name,
        feedLines: settings.resolvedFeedBeforeCut,
        paperWidthMm: settings.paperWidthMm,
      );
      if (ok) {
        NotificationOverlayManager().showSuccess(
          title: 'Test in OK',
          message: '${printer.name} (Sunmi native)',
        );
      }
      return ok;
    }

    // Chip Sunmi (Oppo / hoặc «Test qua cloud» trên V2s) → JSON native trên Agent.
    // Tránh ESC/POS (lỗi font / in ra lệnh ESC @… / lần 2 bị dedup).
    if (printer.isSunmi) {
      return _enqueueTestPrintJson(
        printer: printer,
        forceCloud: forceRemote,
        showFeedback: true,
      );
    }

    final settings = toThermalSettings(printer);
    final bytes = await PosThermalPrinterService.buildTestEscPosBytes(settings);

    return dispatchEscPos(
      documentType: PosCloudDocumentTypes.saleInvoice,
      bytes: bytes,
      printerId: printer.id,
      referenceNo: 'TEST-${DateTime.now().millisecondsSinceEpoch}',
      showFeedback: true,
      successTitle: 'Test in OK',
      skipDedup: true,
      forceCloud: forceRemote,
    );
  }

  /// Test in Sunmi qua cloud — Agent in native UTF-8.
  Future<bool> _enqueueTestPrintJson({
    required PosStorePrinter printer,
    bool forceCloud = false,
    bool showFeedback = true,
  }) async {
    await ensureListening();
    final hasCloud = await refreshConfig();

    // Agent trên chính máy + không forceCloud → native trực tiếp.
    if (!forceCloud && await PosPrintRole.isAgentForPrinter(printer.id)) {
      final settings = toThermalSettings(printer);
      final ok = await PosSunmiNativePrint.printTest(
        storeLabel: printer.name,
        feedLines: settings.resolvedFeedBeforeCut,
        paperWidthMm: settings.paperWidthMm,
      );
      if (ok && showFeedback) {
        NotificationOverlayManager().showSuccess(
          title: 'Test in OK',
          message: '${printer.name} (Sunmi native)',
        );
      }
      return ok;
    }

    if (!hasCloud) {
      if (showFeedback) {
        NotificationOverlayManager().showError(
          title: 'Test thất bại',
          message: tr('Chưa cấu hình in cloud / Print Agent'),
        );
      }
      return false;
    }

    final settings = toThermalSettings(printer);
    final refNo = 'TEST-${DateTime.now().millisecondsSinceEpoch}';
    final payload = jsonEncode({
      'storeLabel': printer.name,
      'paperWidthMm': settings.paperWidthMm,
      'feedLines': settings.resolvedFeedBeforeCut,
    });

    var res = await _api.createPosPrintJob(
      documentType: PosCloudDocumentTypes.saleInvoice,
      payloadFormat: 'TestPrintJson',
      payload: payload,
      copies: 1,
      referenceNo: refNo,
      printerId: printer.id,
    );

    // Server cũ chưa có TestPrintJson → EscPos; Agent Sunmi vẫn in native theo prefix TEST-.
    if (res['isSuccess'] != true) {
      final bytes =
          await PosThermalPrinterService.buildTestEscPosBytes(settings);
      res = await _api.createPosPrintJob(
        documentType: PosCloudDocumentTypes.saleInvoice,
        payloadFormat: 'EscPosBase64',
        payload: base64Encode(bytes),
        copies: 1,
        referenceNo: refNo,
        printerId: printer.id,
      );
    }
    if (res['isSuccess'] != true) {
      if (showFeedback) {
        NotificationOverlayManager().showError(
          title: 'Không gửi lệnh in',
          message: res['message']?.toString() ?? 'Lỗi máy chủ',
        );
      }
      return false;
    }

    final data = res['data'] as Map<String, dynamic>?;
    final jobId = data?['jobId']?.toString() ?? '';
    if (jobId.isEmpty) return false;

    // Trên chính máy Agent (V2s): tự claim + in native ngay.
    // Không chờ SignalR/timer — hay bị kẹt Claimed khiến «test cloud không ra».
    if (await PosPrintRole.isAgentForPrinter(printer.id)) {
      return _completeCloudTestOnLocalAgent(
        jobId: jobId,
        printer: printer,
        settings: settings,
        showFeedback: showFeedback,
      );
    }

    // Oppo: server báo chưa có Agent heartbeat gắn máy in → khỏi chờ 90s.
    final agentsOnline = data?['agentOnlineForPrinter'];
    if (agentsOnline is num && agentsOnline.toInt() <= 0) {
      if (showFeedback) {
        NotificationOverlayManager().showError(
          title: 'Không có Print Agent',
          message: tr('Sunmi chưa đăng ký Agent lên server. Mở app Sunmi → Bật Agent + chọn chip ${printer.name}.'),
        );
      }
      unawaited(_api.failPosPrintJob(
        jobId,
        '',
        errorCode: 'NO_AGENT',
        errorMessage: 'Không có Agent online cho máy in',
      ));
      return false;
    }

    PosPrintSessionRegistry.markOutbound(jobId);
    _jobMeta[jobId] = _JobFeedbackMeta(
      referenceNo: 'TEST',
      printerName: printer.name,
    );

    if (showFeedback) {
      NotificationOverlayManager().show(
        title: 'Đã gửi lệnh in',
        message: 'Test → Print Agent (${printer.name})',
        type: NotificationType.success,
        duration: const Duration(seconds: 3),
      );
    }

    PosPrintAgentService.instance.nudgeClaim();
    final outcome = await _waitJob(jobId, showFeedback: showFeedback);
    PosPrintSessionRegistry.clearOutbound(jobId);
    return outcome.ok;
  }

  /// V2s vừa là máy gửi vừa là Agent — in ngay, claim/complete nhanh (không chờ 5–10s).
  Future<bool> _completeCloudTestOnLocalAgent({
    required String jobId,
    required PosStorePrinter printer,
    required PosThermalPrinterSettings settings,
    bool showFeedback = true,
  }) async {
    final agent = PosPrintAgentService.instance;
    // Heartbeat nhẹ — không refresh toàn bộ máy in.
    await agent.forceRegister(refreshPrinters: false);
    if (!agent.isRegistered || agent.agentId == null) {
      if (showFeedback) {
        NotificationOverlayManager().showError(
          title: 'Test cloud thất bại',
          message: agent.lastRegisterError ??
              'Agent chưa đăng ký server — bật Agent + chọn chip máy in',
        );
      }
      return false;
    }

    final agentId = agent.agentId!;
    bool sameId(String a, String b) =>
        a.trim().toLowerCase() == b.trim().toLowerCase();

    agent.pauseClaims();
    try {
      // In native trước — người dùng thấy giấy ngay (~1s).
      final ok = await PosSunmiNativePrint.printTest(
        storeLabel: printer.name,
        feedLines: settings.resolvedFeedBeforeCut,
        paperWidthMm: settings.paperWidthMm,
      );
      if (!ok) {
        await _api.failPosPrintJob(
          jobId,
          agentId,
          errorCode: 'PRINT_FAILED',
          errorMessage: 'Sunmi native test thất bại',
        );
        if (showFeedback) {
          NotificationOverlayManager().showError(
            title: 'Test cloud thất bại',
            message: tr('Không in được trên Sunmi'),
          );
        }
        return false;
      }

      // Claim nhanh (tối đa ~1s) rồi complete — tránh job Queued bị máy khác in lại.
      Map<String, dynamic>? claimed;
      final byId = await _api.claimPosPrintJobById(jobId, agentId);
      final byIdData = byId['data'];
      if (byIdData is Map) {
        final map = Map<String, dynamic>.from(byIdData);
        final id = map['jobId']?.toString() ?? map['JobId']?.toString() ?? '';
        if (sameId(id, jobId)) claimed = map;
      }
      if (claimed == null) {
        for (var i = 0; i < 4; i++) {
          final claimRes = await _api.claimPosPrintJob(agentId);
          final raw = claimRes['data'];
          if (raw is Map) {
            final map = Map<String, dynamic>.from(raw);
            final claimedId =
                map['jobId']?.toString() ?? map['JobId']?.toString() ?? '';
            if (sameId(claimedId, jobId)) {
              claimed = map;
              break;
            }
            if (claimedId.isNotEmpty && !sameId(claimedId, jobId)) {
              await _api.failPosPrintJob(
                claimedId,
                agentId,
                errorCode: 'SUPERSEDED',
                errorMessage: 'Bỏ job cũ để ưu tiên test cloud',
              );
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 80));
        }
      }

      if (claimed != null) {
        await _api.markPosPrintJobPrinting(jobId, agentId);
        await _api.completePosPrintJob(jobId, agentId);
      } else {
        // Đánh Failed để không bị Agent in lần 2.
        await _api.failPosPrintJob(
          jobId,
          agentId,
          errorCode: 'LOCAL_TEST_DONE',
          errorMessage: 'Đã in trên máy Agent (claim bỏ qua)',
        );
      }
      await _api.reportPosPrinterHealth(printer.id, status: 'Online');

      if (showFeedback) {
        NotificationOverlayManager().showSuccess(
          title: 'Test cloud OK',
          message: '${printer.name} (qua cloud → Agent)',
        );
      }
      return true;
    } finally {
      agent.resumeClaims();
    }
  }

  static Future<String> stableDeviceId() async {
    final settings = await PosPrintAgentSettings.load();
    final existing = settings.deviceId?.trim() ?? '';
    // Bỏ android.id ngắn kiểu "235" — dùng UUID ổn định.
    if (existing.length >= 16) return existing;

    final identity = await PosDeviceIdentity.get();
    final id = identity.id;
    await settings.copyWith(deviceId: id).save();
    return id;
  }
}

class _JobOutcome {
  const _JobOutcome(this.ok, this.error, {this.printerName});
  final bool ok;
  final String? error;
  final String? printerName;
}

class _JobFeedbackMeta {
  const _JobFeedbackMeta({this.referenceNo, this.printerName});
  final String? referenceNo;
  final String? printerName;
}
