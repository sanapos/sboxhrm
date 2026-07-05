import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../models/hrm.dart';
import '../models/pos_store_printer.dart';
import '../services/api_service.dart';
import '../services/signalr_service.dart';
import '../widgets/notification_overlay.dart';
import 'pos_label_printer_service.dart';
import 'pos_print_agent_settings.dart';
import 'pos_print_role.dart';
import 'pos_printer_transport.dart';
import 'pos_store_printer_mapper.dart';
import 'pos_thermal_printer_service.dart';
import 'pos_thermal_printer_settings.dart';

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

      // Thiết bị gắn máy in → in trực tiếp, không qua cloud.
      if (await PosPrintRole.isAgentForPrinter(printer.id)) {
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

      if (!waitForCompletion) return true;

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

    var ok = true;
    for (var i = 0; i < copies; i++) {
      final sent = await PosPrinterTransport.send(
        connectionType: settings.connectionType,
        bluetoothAddress: settings.bluetoothAddress,
        lanHost: settings.lanHost,
        lanPort: settings.lanPort,
        bytes: bytes,
        sunmiFeedLines: settings.resolvedFeedBeforeCut,
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
        message: 'Không kết nối được ${printer.name}',
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
            message: 'Không kết nối được máy in cục bộ',
          );
        }
        return false;
      }
    }
    if (showFeedback) {
      NotificationOverlayManager().showSuccess(
        title: successTitle ?? 'In thành công',
        message: 'Máy in cục bộ (cùng mạng)',
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
          const _JobOutcome(false, 'Hết thời gian chờ Print Agent'),
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

  Future<bool> testPrinter(PosStorePrinter printer) async {
    if (printer.isLabelPrinter) {
      final settings = toLabelSettings(printer);
      return PosLabelPrinterService.testPrint(settings);
    }
    final settings = toThermalSettings(printer);
    final bytes = await PosThermalPrinterService.buildTestEscPosBytes(settings);

    return dispatchEscPos(
      documentType: PosCloudDocumentTypes.saleInvoice,
      bytes: bytes,
      printerId: printer.id,
      referenceNo: 'TEST',
      showFeedback: true,
      successTitle: 'Test in OK',
    );
  }

  static Future<String> stableDeviceId() async {
    final settings = await PosPrintAgentSettings.load();
    if (settings.deviceId != null && settings.deviceId!.isNotEmpty) {
      return settings.deviceId!;
    }
    String? id;
    try {
      if (!kIsWeb && Platform.isAndroid) {
        final android = await DeviceInfoPlugin().androidInfo;
        id = android.id;
      } else if (!kIsWeb && Platform.isIOS) {
        final ios = await DeviceInfoPlugin().iosInfo;
        id = ios.identifierForVendor;
      }
    } catch (e) {
      debugPrint('stableDeviceId: $e');
    }
    id ??= 'pos_${DateTime.now().millisecondsSinceEpoch}';
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
