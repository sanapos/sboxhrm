import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../models/pos_store_printer.dart';
import '../services/api_service.dart';
import '../services/signalr_service.dart';
import '../widgets/notification_overlay.dart';
import 'pos_label_printer_service.dart';
import 'pos_print_agent_settings.dart';
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
  }

  void _onJobStatus(Map<String, dynamic> data) {
    final jobId = data['jobId']?.toString() ?? data['id']?.toString() ?? '';
    if (jobId.isEmpty) return;
    final status = data['status']?.toString() ?? '';
    final printerName = data['printerName']?.toString() ?? '';
    final error = data['errorMessage']?.toString();

    final completer = _pendingJobs[jobId];
    if (completer == null) return;

    if (status == 'Completed') {
      completer.complete(_JobOutcome(true, null, printerName: printerName));
      _pendingJobs.remove(jobId);
      NotificationOverlayManager().showSuccess(
        title: 'In thành công',
        message: printerName.isNotEmpty
            ? 'Đã in qua $printerName'
            : 'Lệnh in đã hoàn tất',
      );
    } else if (status == 'Failed' ||
        status == 'Expired' ||
        status == 'Cancelled') {
      completer.complete(_JobOutcome(false, error ?? 'In thất bại'));
      _pendingJobs.remove(jobId);
      NotificationOverlayManager().showError(
        title: 'In thất bại',
        message: error ?? 'Không in được chứng từ',
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
    if (_printers.isEmpty) return null;

    final route =
        _routes.where((r) => r.documentType == documentType).firstOrNull;
    if (route != null) {
      final p = _printers.where((x) => x.id == route.printerId).firstOrNull;
      if (p != null) return p;
    }

    final tagged =
        _printers.where((p) => p.documentTypes.contains(documentType)).toList();
    if (tagged.length == 1) return tagged.first;

    if (_printers.length == 1) return _printers.first;

    return _printers.where((p) => p.isDefault).firstOrNull ??
        _printers.firstOrNull;
  }

  int copiesFor(String documentType, {int fallback = 1}) {
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
  }) async {
    if (kIsWeb) return false;

    await ensureListening();
    final hasCloud = await refreshConfig();
    PosStorePrinter? printer = printerId != null
        ? _printers.where((p) => p.id == printerId).firstOrNull
        : null;
    printer ??= resolvePrinter(documentType);

    if (printer != null) {
      final n = copies.clamp(1, 10);

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

      if (showFeedback) {
        NotificationOverlayManager().show(
          title: 'Đang in…',
          message: 'Chờ Print Agent (${printer.name})',
          duration: const Duration(seconds: 4),
        );
      }

      final outcome = await _waitJob(jobId);
      return outcome.ok;
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
  }) async {
    if (kIsWeb) return false;

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

  Future<_JobOutcome> _waitJob(String jobId) async {
    final completer = Completer<_JobOutcome>();
    _pendingJobs[jobId] = completer;

    Timer(_jobTimeout, () {
      if (!completer.isCompleted) {
        completer.complete(
            const _JobOutcome(false, 'Hết thời gian chờ Print Agent'));
        _pendingJobs.remove(jobId);
      }
    });

    unawaited(_pollJobUntilDone(jobId, completer));
    return completer.future;
  }

  Future<void> _pollJobUntilDone(
      String jobId, Completer<_JobOutcome> completer) async {
    for (var i = 0; i < 18; i++) {
      if (completer.isCompleted) return;
      await Future<void>.delayed(const Duration(seconds: 5));
      if (completer.isCompleted) return;
      try {
        final res = await _api.getPosPrintJob(jobId);
        if (res['isSuccess'] != true || res['data'] is! Map) continue;
        final status = (res['data'] as Map)['status']?.toString() ?? '';
        if (status == 'Completed' && !completer.isCompleted) {
          completer.complete(const _JobOutcome(true, null));
          _pendingJobs.remove(jobId);
        } else if ((status == 'Failed' || status == 'Expired') &&
            !completer.isCompleted) {
          final err = (res['data'] as Map)['errorMessage']?.toString();
          completer.complete(_JobOutcome(false, err ?? status));
          _pendingJobs.remove(jobId);
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
