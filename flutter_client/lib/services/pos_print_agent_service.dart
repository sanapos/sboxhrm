import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../models/pos_store_printer.dart';
import '../models/pos_sale_order.dart';
import '../services/api_service.dart';
import '../services/signalr_service.dart';
import '../utils/pos_device_identity.dart';
import '../utils/pos_print_agent_settings.dart';
import '../utils/pos_print_role.dart';
import '../utils/pos_print_orchestrator.dart';
import '../utils/pos_printer_transport.dart';
import '../utils/pos_store_printer_mapper.dart';
import '../utils/pos_sunmi_native_print.dart';
import '../utils/pos_thermal_printer_settings.dart';
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
  String? _lastRegisterError;
  bool _warnedNoPrinters = false;
  DateTime? _lastConfigRefreshAt;
  StreamSubscription<Map<String, dynamic>>? _forceStopSub;

  bool get isRunning => _running;
  bool get isRegistered => _agentId != null && _agentId!.isNotEmpty;
  String? get agentId => _agentId;
  String? get lastRegisterError => _lastRegisterError;

  /// Tạm dừng claim (tránh đua với test cloud trên chính máy Agent).
  bool _claimsPaused = false;

  void pauseClaims() => _claimsPaused = true;
  void resumeClaims() {
    _claimsPaused = false;
    _scheduleClaim();
  }

  /// Ép claim ngay (sau khi tạo job trên máy khác / cùng máy).
  void nudgeClaim() => _scheduleClaim();

  Future<void> ensureRunning(String? storeId, {bool forceReregister = false}) async {
    if (storeId == null || storeId.isEmpty) return;
    final settings = await PosPrintAgentSettings.load();
    if (!settings.enabled) {
      await stop();
      return;
    }
    if (_running && _storeId == storeId) {
      if (forceReregister) await _register(refreshPrinters: true);
      return;
    }

    await stop(markOffline: false);
    _storeId = storeId;
    _deviceId = await PosPrintOrchestrator.stableDeviceId();
    _running = true;

    await _signalR.joinPrintAgentGroup(storeId);
    await _register(refreshPrinters: true);

    // Heartbeat 12s — server stale 90s; Oppo thấy Agent online ổn định hơn.
    _heartbeatTimer =
        Timer.periodic(const Duration(seconds: 12), (_) => _register());
    _claimTimer =
        Timer.periodic(const Duration(seconds: 3), (_) => _scheduleClaim());
    _jobNewSub = _signalR.onPrintJobNew.listen((_) => _scheduleClaim());
    await _forceStopSub?.cancel();
    _forceStopSub = _signalR.onPrintAgentHeartbeat.listen(_onRemoteForceStop);

    debugPrint('🖨️ Print Agent started for store $storeId');
  }

  Future<void> _onRemoteForceStop(Map<String, dynamic> data) async {
    final deviceId =
        (data['deviceId'] ?? data['DeviceId'])?.toString() ?? '';
    final forceStop = data['forceStop'] == true || data['ForceStop'] == true;
    final online = data['isOnline'] == true || data['IsOnline'] == true;
    if (!forceStop || online) return;
    if (deviceId.isEmpty || deviceId != _deviceId) return;
    if (!_running) return;

    debugPrint('🖨️ Print Agent force-stopped by remote device');
    final settings = await PosPrintAgentSettings.load();
    await settings.copyWith(enabled: false).save();
    await stop(markOffline: false);
    NotificationOverlayManager().showWarning(
      title: 'Agent đã tắt từ máy khác',
      message: 'Chỉ giữ Agent trên máy gần máy in',
    );
  }

  /// Ép đăng ký lại (gắn chip máy in lên server trước khi claim).
  Future<bool> forceRegister({bool refreshPrinters = false}) async {
    if (!_running || _storeId == null) return false;
    await _register(refreshPrinters: refreshPrinters);
    return isRegistered;
  }

  Future<void> stop({bool markOffline = true}) async {
    final wasRunning = _running;
    final deviceId = _deviceId;
    final storeId = _storeId;
    _running = false;
    _heartbeatTimer?.cancel();
    _claimTimer?.cancel();
    _claimDebounce?.cancel();
    await _jobNewSub?.cancel();
    await _forceStopSub?.cancel();
    _heartbeatTimer = null;
    _claimTimer = null;
    _claimDebounce = null;
    _jobNewSub = null;
    _forceStopSub = null;
    _activeJobIds.clear();
    _notifiedReceiveJobIds.clear();
    if (storeId != null) {
      await _signalR.leavePrintAgentGroup(storeId);
    }
    if (markOffline && wasRunning && deviceId != null && deviceId.isNotEmpty) {
      try {
        await _api.markPosPrintAgentOffline(deviceId: deviceId);
      } catch (_) {}
    }
    _storeId = null;
    _agentId = null;
    debugPrint('🖨️ Print Agent stopped');
  }

  Future<void> _register({bool refreshPrinters = false}) async {
    if (!_running || _storeId == null) return;
    final settings = await PosPrintAgentSettings.load();
    if (!settings.enabled) {
      await stop();
      return;
    }

    // Heartbeat nhẹ — không refresh máy in mỗi lần (tránh chậm / lỗi mạng làm Agent offline).
    final needRefresh = refreshPrinters ||
        _printers.isEmpty ||
        _lastConfigRefreshAt == null ||
        DateTime.now().difference(_lastConfigRefreshAt!) >
            const Duration(minutes: 2);
    if (needRefresh) {
      await PosPrintOrchestrator.instance
          .refreshConfig(force: refreshPrinters || _printers.isEmpty);
      _printers = PosPrintOrchestrator.instance.printers;
      _lastConfigRefreshAt = DateTime.now();
    }

    var printerIds = List<String>.from(settings.assignedPrinterIds);
    // Bỏ chip máy in đã xóa / không còn trên server — tránh Agent claim sai ID.
    if (_printers.isNotEmpty && printerIds.isNotEmpty) {
      final alive = _printers.map((p) => p.id).toSet();
      final filtered =
          printerIds.where((id) => alive.contains(id)).toList();
      if (filtered.length != printerIds.length) {
        printerIds = filtered;
        await settings.copyWith(assignedPrinterIds: printerIds).save();
        debugPrint(
          '🖨️ Print Agent: đã bỏ chip máy in đã xóa, còn ${printerIds.length}',
        );
      }
    }
    if (printerIds.isEmpty && _printers.isNotEmpty) {
      printerIds = _printers.map((p) => p.id).toList();
      await settings.copyWith(assignedPrinterIds: printerIds).save();
    }
    if (printerIds.isEmpty) {
      _agentId = null;
      _lastRegisterError = 'Chưa chọn chip máy in cho Agent';
      if (!_warnedNoPrinters) {
        _warnedNoPrinters = true;
        NotificationOverlayManager().showWarning(
          title: 'Agent chưa gán máy in',
          message: 'Bật Agent và chọn ít nhất một chip máy in bên dưới',
        );
      }
      return;
    }
    _warnedNoPrinters = false;

    try {
      final device = await PosDeviceIdentity.get(refreshName: true);
      final res = await _api.registerPosPrintAgent(
        deviceId: _deviceId ?? await PosPrintOrchestrator.stableDeviceId(),
        deviceName: device.name,
        employeeName: settings.accountLabel,
        printerIds: printerIds,
      );
      if (res['isSuccess'] == true && res['data'] is Map) {
        final data = res['data'] as Map;
        _agentId =
            data['agentId']?.toString() ?? data['AgentId']?.toString();
        _lastRegisterError = null;
        _scheduleClaim();
        debugPrint(
          '🖨️ Print Agent registered id=$_agentId printers=${printerIds.length}',
        );
      } else {
        // Giữ agentId cũ nếu heartbeat lỗi tạm thời — tránh Oppo mất Agent giữa chừng.
        _lastRegisterError =
            res['message']?.toString() ?? 'Đăng ký Agent thất bại';
        debugPrint('Print Agent register soft-fail: $_lastRegisterError');
      }
    } catch (e) {
      _lastRegisterError = e.toString();
      debugPrint('Print Agent register failed: $e');
    }
  }

  void _scheduleClaim() {
    if (!_running) return;
    _claimDebounce?.cancel();
    _claimDebounce = Timer(const Duration(milliseconds: 250), _tryClaim);
  }

  Future<void> _tryClaim() async {
    if (!_running || _claimsPaused || _claimInFlight || _agentId == null) return;
    _claimInFlight = true;
    try {
      final res = await _api.claimPosPrintJob(_agentId!);
      if (res['isSuccess'] != true) return;
      final raw = res['data'];
      if (raw == null) return;
      if (raw is! Map) return;
      final data = Map<String, dynamic>.from(raw);

      final jobId = data['jobId']?.toString() ?? data['JobId']?.toString() ?? '';
      if (jobId.isEmpty) return;

      // Đã claim trên server — không được return im lặng (job sẽ kẹt Claimed).
      if (_activeJobIds.contains(jobId)) {
        await _api.failPosPrintJob(
          jobId,
          _agentId!,
          errorCode: 'DUP_CLAIM',
          errorMessage: 'Job đang được xử lý',
        );
        return;
      }

      final printerId =
          data['printerId']?.toString() ?? data['PrinterId']?.toString() ?? '';
      if (printerId.isEmpty) {
        await _api.failPosPrintJob(
          jobId,
          _agentId!,
          errorCode: 'NO_PRINTER_ID',
          errorMessage: 'Job thiếu printerId',
        );
        return;
      }
      if (!await PosPrintRole.isAgentForPrinter(printerId)) {
        debugPrint(
          'Print Agent: bỏ job $jobId — printerId $printerId không trong chip đã chọn',
        );
        await _api.failPosPrintJob(
          jobId,
          _agentId!,
          errorCode: 'PRINTER_MISMATCH',
          errorMessage: 'Agent không phục vụ máy in này — chọn lại chip máy in',
        );
        return;
      }

      _activeJobIds.add(jobId);
      if (_activeJobIds.length > 50) {
        _activeJobIds.remove(_activeJobIds.first);
      }

      _notifyReceivedOnce(data, jobId);

      await _api.markPosPrintJobPrinting(jobId, _agentId!);
      // Timeout — tránh 1 job treo Sunmi làm Agent ngừng claim.
      try {
        await _executeJob(data, jobId).timeout(const Duration(seconds: 45));
      } on TimeoutException {
        debugPrint('Print Agent: job $jobId timeout 45s');
        try {
          await _api.failPosPrintJob(
            jobId,
            _agentId!,
            errorCode: 'PRINT_TIMEOUT',
            errorMessage: 'In quá 45 giây — kiểm tra giấy / máy Sunmi',
          );
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Print Agent claim error: $e');
    } finally {
      _claimInFlight = false;
      // Xả hàng đợi ngay — không chờ timer 3s.
      if (_running && !_claimsPaused) _scheduleClaim();
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
    final printerId =
        job['printerId']?.toString() ?? job['PrinterId']?.toString() ?? '';
    final format =
        job['payloadFormat']?.toString() ?? job['PayloadFormat']?.toString() ?? '';
    final payload = job['payload']?.toString() ?? job['Payload']?.toString() ?? '';
    final copies = (job['copies'] as num?)?.toInt() ??
        (job['Copies'] as num?)?.toInt() ??
        1;
    final referenceNo =
        job['referenceNo']?.toString() ?? job['ReferenceNo']?.toString() ?? '';

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

    final settings = toThermalSettings(printer);
    var ok = true;

    if (format == 'SaleOrderJson') {
      // Sunmi: in native giống máy in nội bộ (UTF-8, cỡ chữ đúng).
      try {
        final map = jsonDecode(payload);
        if (map is! Map) {
          throw const FormatException('SaleOrderJson không phải object');
        }
        if (!await PosPrinterTransport.isSunmiDevice()) {
          await _api.failPosPrintJob(
            jobId,
            _agentId!,
            errorCode: 'NOT_SUNMI',
            errorMessage: 'Job SaleOrderJson cần máy Sunmi làm Agent',
          );
          return;
        }

        PosSaleOrder? order;
        // Ưu tiên order nhúng trong payload (ổn định hơn gọi lại API).
        final orderMap = map['order'];
        if (orderMap is Map) {
          try {
            order = PosSaleOrder.fromJson(Map<String, dynamic>.from(orderMap));
          } catch (e) {
            debugPrint('Print Agent: parse order payload failed: $e');
          }
        }
        final orderId = map['orderId']?.toString() ?? '';
        if (order == null && orderId.isNotEmpty) {
          final saleRes = await _api.getPosSale(orderId);
          if (saleRes['isSuccess'] == true && saleRes['data'] is Map) {
            order = PosSaleOrder.fromJson(
              Map<String, dynamic>.from(saleRes['data'] as Map),
            );
          }
        }
        if (order == null) {
          await _api.failPosPrintJob(
            jobId,
            _agentId!,
            errorCode: 'NO_ORDER',
            errorMessage: 'Không tải được đơn để in Sunmi',
          );
          return;
        }

        final warehouseSlip = map['warehouseSlip'] == true;
        List<PosSaleOrderLine>? linesOverride;
        final linesRaw = map['linesOverride'] ?? map['lines'];
        if (linesRaw is List) {
          linesOverride = linesRaw
              .whereType<Map>()
              .map((e) => PosSaleOrderLine.fromJson(Map<String, dynamic>.from(e)))
              .toList();
          if (linesOverride.isEmpty) linesOverride = null;
        }

        for (var i = 0; i < copies.clamp(1, 10); i++) {
          final sent = await PosSunmiNativePrint.printSaleOrder(
            order,
            settings: settings,
            storeName: map['storeName']?.toString(),
            storeAddress: map['storeAddress']?.toString(),
            storePhone: map['storePhone']?.toString(),
            mergeSameItems: map['mergeSameItems'] != false && !warehouseSlip,
            copies: 1,
            documentTitle: map['documentTitle']?.toString() ??
                map['slipTitle']?.toString(),
            warehouseSlip: warehouseSlip,
            slipTitle: map['slipTitle']?.toString(),
            linesOverride: linesOverride,
          );
          if (!sent) {
            ok = false;
            break;
          }
        }
      } catch (e) {
        await _api.failPosPrintJob(
          jobId,
          _agentId!,
          errorCode: 'BAD_PAYLOAD',
          errorMessage: 'SaleOrderJson lỗi: $e',
        );
        return;
      }
    } else if (format == 'KitchenSlipJson') {
      try {
        final map = jsonDecode(payload);
        if (map is! Map) {
          throw const FormatException('KitchenSlipJson không phải object');
        }
        if (!await PosPrinterTransport.isSunmiDevice()) {
          await _api.failPosPrintJob(
            jobId,
            _agentId!,
            errorCode: 'NOT_SUNMI',
            errorMessage: 'Job KitchenSlipJson cần máy Sunmi làm Agent',
          );
          return;
        }

        final slipMap = Map<String, dynamic>.from(map);
        final linesRaw = slipMap['lines'];
        if (linesRaw is! List || linesRaw.isEmpty) {
          await _api.failPosPrintJob(
            jobId,
            _agentId!,
            errorCode: 'NO_LINES',
            errorMessage: 'Phiếu bếp không có món',
          );
          return;
        }

        final qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
        final nativeLines = <({String name, String qty, String? unit, String? note})>[];
        for (final item in linesRaw) {
          if (item is! Map) continue;
          final row = Map<String, dynamic>.from(item);
          final name = row['productName']?.toString() ?? '';
          if (name.isEmpty) continue;
          final qtyNum = (row['qty'] as num?)?.toDouble() ?? 0;
          nativeLines.add((
            name: name,
            qty: qtyFmt.format(qtyNum),
            unit: row['unitName']?.toString(),
            note: row['note']?.toString(),
          ));
        }
        if (nativeLines.isEmpty) {
          await _api.failPosPrintJob(
            jobId,
            _agentId!,
            errorCode: 'NO_LINES',
            errorMessage: 'Phiếu bếp không có món hợp lệ',
          );
          return;
        }

        final sentAtRaw = slipMap['sentAt']?.toString() ?? '';
        final sentAt = DateTime.tryParse(sentAtRaw)?.toLocal() ?? DateTime.now();
        final kitchenSettings = settings.copyWith(
          connectionType: PosThermalConnectionType.sunmi,
          printerBrand: PosThermalPrinterBrand.sunmi,
          feedBeforeCut: 12,
        );

        for (var i = 0; i < copies.clamp(1, 10); i++) {
          final sent = await PosSunmiNativePrint.printKitchenSlip(
            tableName: slipMap['tableName']?.toString() ?? 'Bàn',
            isCancel: slipMap['isCancel'] == true,
            lines: nativeLines,
            senderName: slipMap['senderName']?.toString() ?? 'admin',
            orderNo: slipMap['orderNo']?.toString() ?? '',
            sentAt: sentAt,
            settings: kitchenSettings,
          );
          if (!sent) {
            ok = false;
            break;
          }
        }
      } catch (e) {
        await _api.failPosPrintJob(
          jobId,
          _agentId!,
          errorCode: 'BAD_PAYLOAD',
          errorMessage: 'KitchenSlipJson lỗi: $e',
        );
        return;
      }
    } else if (format == 'TestPrintJson') {
      try {
        if (!await PosPrinterTransport.isSunmiDevice()) {
          await _api.failPosPrintJob(
            jobId,
            _agentId!,
            errorCode: 'NOT_SUNMI',
            errorMessage: 'Job TestPrintJson cần máy Sunmi làm Agent',
          );
          return;
        }
        Map<String, dynamic> map = {};
        if (payload.trim().isNotEmpty) {
          final decoded = jsonDecode(payload);
          if (decoded is Map) map = Map<String, dynamic>.from(decoded);
        }
        for (var i = 0; i < copies.clamp(1, 10); i++) {
          final sent = await PosSunmiNativePrint.printTest(
            storeLabel: map['storeLabel']?.toString() ?? printer.name,
            feedLines: settings.resolvedFeedBeforeCut,
            paperWidthMm: settings.paperWidthMm,
          );
          if (!sent) {
            ok = false;
            break;
          }
        }
      } catch (e) {
        await _api.failPosPrintJob(
          jobId,
          _agentId!,
          errorCode: 'BAD_PAYLOAD',
          errorMessage: 'TestPrintJson lỗi: $e',
        );
        return;
      }
    } else if (format == 'EscPosBase64') {
      // Sunmi: ESC/POS qua printEscPos hay lỗi font tiếng Việt / in ra lệnh thô.
      // Job test hoặc chip Sunmi → ưu tiên native.
      final isTest = referenceNo.toUpperCase() == 'TEST' ||
          referenceNo.toUpperCase().startsWith('TEST');
      if (printer.isSunmi &&
          await PosPrinterTransport.isSunmiDevice() &&
          isTest) {
        for (var i = 0; i < copies.clamp(1, 10); i++) {
          final sent = await PosSunmiNativePrint.printTest(
            storeLabel: printer.name,
            feedLines: settings.resolvedFeedBeforeCut,
            paperWidthMm: settings.paperWidthMm,
          );
          if (!sent) {
            ok = false;
            break;
          }
        }
      } else {
        List<int> bytes;
        try {
          bytes = base64Decode(payload);
        } catch (e) {
          await _api.failPosPrintJob(
            jobId,
            _agentId!,
            errorCode: 'BAD_PAYLOAD',
            errorMessage: 'Payload không hợp lệ',
          );
          return;
        }
        final sunmiFeed = printer.isSunmi ? 4 : settings.resolvedFeedBeforeCut;
        // Ép cổng Sunmi nội bộ khi Agent chạy trên Sunmi.
        final conn = (printer.isSunmi &&
                await PosPrinterTransport.isSunmiDevice())
            ? PosThermalConnectionType.sunmi
            : settings.connectionType;
        for (var i = 0; i < copies.clamp(1, 10); i++) {
          final sent = await PosPrinterTransport.send(
            connectionType: conn,
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
      }
    } else {
      await _api.failPosPrintJob(
        jobId,
        _agentId!,
        errorCode: 'UNSUPPORTED_FORMAT',
        errorMessage: 'Agent không hỗ trợ $format',
      );
      return;
    }

    if (ok) {
      await _api.completePosPrintJob(jobId, _agentId!);
      await _api.reportPosPrinterHealth(printer.id, status: 'Online');
      NotificationOverlayManager().showSuccess(
        title: 'In xong',
        message: referenceNo.isNotEmpty
            ? 'Đơn $referenceNo — ${printer.name}'
            : printer.name,
      );
    } else {
      await _api.failPosPrintJob(
        jobId,
        _agentId!,
        errorCode: 'PRINT_FAILED',
        errorMessage: printer.isSunmi
            ? 'Không in được trên Sunmi'
            : 'Không gửi được dữ liệu tới máy in',
      );
      await _api.reportPosPrinterHealth(
        printer.id,
        status: 'Offline',
        errorMessage: 'In thất bại trên agent',
      );
    }
  }
}
