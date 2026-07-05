import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/pos_store_printer.dart';
import '../services/api_service.dart';
import '../services/signalr_service.dart';
import '../utils/pos_print_agent_settings.dart';
import '../utils/pos_print_role.dart';
import '../utils/pos_print_orchestrator.dart';
import '../utils/pos_printer_transport.dart';
import '../utils/pos_store_printer_mapper.dart';
import '../widgets/notification_overlay.dart';

/// Print Agent: thiết bị nhận job in cloud (LAN/BT/USB) và in cục bộ.
class PosPrintAgentService {
  PosPrintAgentService._();
  static final PosPrintAgentService instance = PosPrintAgentService._();

  final _api = ApiService();
  final _signalR = SignalRService();

  Timer? _heartbeatTimer;
  Timer? _claimTimer;
  StreamSubscription<Map<String, dynamic>>? _jobNewSub;
  String? _storeId;
  String? _agentId;
  String? _deviceId;
  bool _running = false;
  bool _claimInFlight = false;
  List<PosStorePrinter> _printers = [];
  final _activeJobIds = <String>{};
  final _notifiedReceiveJobIds = <String>{};
  Timer? _claimDebounce;

  bool get isRunning => _running;

  Future<void> ensureRunning(String? storeId) async {
    if (storeId == null || storeId.isEmpty) return;
    final settings = await PosPrintAgentSettings.load();
    if (!settings.enabled) {
      await stop();
      return;
    }
    if (_running && _storeId == storeId) return;

    await stop();
    _storeId = storeId;
    _deviceId = await PosPrintOrchestrator.stableDeviceId();
    _running = true;

    await _signalR.joinPrintAgentGroup(storeId);
    await _register();

    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) => _register());
    _claimTimer = Timer.periodic(const Duration(seconds: 4), (_) => _scheduleClaim());
    _jobNewSub = _signalR.onPrintJobNew.listen((_) => _scheduleClaim());

    debugPrint('🖨️ Print Agent started for store $storeId');
  }

  Future<void> stop() async {
    _running = false;
    _heartbeatTimer?.cancel();
    _claimTimer?.cancel();
    _claimDebounce?.cancel();
    await _jobNewSub?.cancel();
    _heartbeatTimer = null;
    _claimTimer = null;
    _claimDebounce = null;
    _jobNewSub = null;
    _activeJobIds.clear();
    _notifiedReceiveJobIds.clear();
    if (_storeId != null) {
      await _signalR.leavePrintAgentGroup(_storeId!);
    }
    _storeId = null;
    _agentId = null;
    debugPrint('🖨️ Print Agent stopped');
  }

  Future<void> _register() async {
    if (!_running || _storeId == null) return;
    final settings = await PosPrintAgentSettings.load();
    if (!settings.enabled) {
      await stop();
      return;
    }

    await PosPrintOrchestrator.instance.refreshConfig(force: true);
    _printers = PosPrintOrchestrator.instance.printers;

    final printerIds = settings.assignedPrinterIds;
    if (printerIds.isEmpty) return;

    try {
      final res = await _api.registerPosPrintAgent(
        deviceId: _deviceId ?? await PosPrintOrchestrator.stableDeviceId(),
        deviceName: 'SBOX POS',
        printerIds: printerIds,
      );
      if (res['isSuccess'] == true && res['data'] is Map) {
        _agentId = (res['data'] as Map)['agentId']?.toString();
      }
    } catch (e) {
      debugPrint('Print Agent register failed: $e');
    }
  }

  void _scheduleClaim() {
    if (!_running) return;
    _claimDebounce?.cancel();
    _claimDebounce = Timer(const Duration(milliseconds: 250), _tryClaim);
  }

  Future<void> _tryClaim() async {
    if (!_running || _claimInFlight || _agentId == null) return;
    _claimInFlight = true;
    try {
      final res = await _api.claimPosPrintJob(_agentId!);
      if (res['isSuccess'] != true) return;
      final data = res['data'];
      if (data == null) return;
      if (data is! Map<String, dynamic>) return;

      final jobId = data['jobId']?.toString() ?? '';
      if (jobId.isEmpty) return;
      if (PosPrintSessionRegistry.isOutbound(jobId)) return;
      if (_activeJobIds.contains(jobId)) return;

      final printerId = data['printerId']?.toString() ?? '';
      if (printerId.isEmpty) return;
      if (!await PosPrintRole.isAgentForPrinter(printerId)) return;

      _activeJobIds.add(jobId);
      if (_activeJobIds.length > 50) {
        _activeJobIds.remove(_activeJobIds.first);
      }

      _notifyReceivedOnce(data, jobId);

      await _api.markPosPrintJobPrinting(jobId, _agentId!);
      await _executeJob(data, jobId);
    } catch (e) {
      debugPrint('Print Agent claim error: $e');
    } finally {
      _claimInFlight = false;
    }
  }

  void _notifyReceivedOnce(Map<String, dynamic> job, String jobId) {
    if (_notifiedReceiveJobIds.contains(jobId)) return;
    _notifiedReceiveJobIds.add(jobId);
    if (_notifiedReceiveJobIds.length > 50) {
      _notifiedReceiveJobIds.remove(_notifiedReceiveJobIds.first);
    }
    final ref = job['referenceNo']?.toString() ?? '';
    NotificationOverlayManager().show(
      title: 'Đã nhận lệnh in',
      message: ref.isNotEmpty ? 'Đơn $ref — đang in…' : 'Đang in chứng từ…',
      duration: const Duration(seconds: 4),
    );
  }

  Future<void> _executeJob(Map<String, dynamic> job, String jobId) async {
    final printerId = job['printerId']?.toString() ?? '';
    final format = job['payloadFormat']?.toString() ?? '';
    final payload = job['payload']?.toString() ?? '';
    final copies = (job['copies'] as num?)?.toInt() ?? 1;

    PosStorePrinter? printer =
        _printers.where((p) => p.id == printerId).firstOrNull;
    if (printer == null && printerId.isNotEmpty) {
      final res = await _api.getPosStorePrinter(printerId);
      if (res['isSuccess'] == true && res['data'] is Map) {
        printer = PosStorePrinter.fromJson(res['data'] as Map<String, dynamic>);
      }
    }
    if (printer == null) {
      await _api.failPosPrintJob(
        jobId,
        _agentId!,
        errorCode: 'NO_PRINTER',
        errorMessage: 'Không tìm thấy cấu hình máy in',
      );
      return;
    }

    List<int> bytes;
    try {
      if (format == 'EscPosBase64') {
        bytes = base64Decode(payload);
      } else {
        await _api.failPosPrintJob(
          jobId,
          _agentId!,
          errorCode: 'UNSUPPORTED_FORMAT',
          errorMessage: 'Agent chỉ hỗ trợ EscPosBase64',
        );
        return;
      }
    } catch (e) {
      await _api.failPosPrintJob(
        jobId,
        _agentId!,
        errorCode: 'BAD_PAYLOAD',
        errorMessage: 'Payload không hợp lệ',
      );
      return;
    }

    final settings = toThermalSettings(printer);
    var ok = true;
    for (var i = 0; i < copies.clamp(1, 10); i++) {
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
      await _api.completePosPrintJob(jobId, _agentId!);
      await _api.reportPosPrinterHealth(printer.id, status: 'Online');
      final ref = job['referenceNo']?.toString() ?? '';
      NotificationOverlayManager().showSuccess(
        title: 'In xong',
        message: ref.isNotEmpty
            ? 'Đơn $ref — ${printer.name}'
            : printer.name,
      );
    } else {
      await _api.failPosPrintJob(
        jobId,
        _agentId!,
        errorCode: 'PRINT_FAILED',
        errorMessage: 'Không gửi được dữ liệu tới máy in BT',
      );
      await _api.reportPosPrinterHealth(
        printer.id,
        status: 'Offline',
        errorMessage: 'In thất bại trên agent',
      );
    }
  }
}
