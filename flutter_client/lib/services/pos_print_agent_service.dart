import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pos_store_printer.dart';
import '../models/pos_sale_order.dart';
import '../services/api_service.dart';
import '../services/signalr_service.dart';
import '../models/pos_print_template.dart';
import '../models/pos_print_template_v2.dart';
import '../utils/pos_device_identity.dart';
import '../utils/pos_local_printers_store.dart';
import '../utils/pos_print_agent_settings.dart';
import '../utils/pos_print_config_session.dart';
import '../utils/pos_print_role.dart';
import '../utils/pos_printer_readiness.dart';
import '../utils/pos_print_orchestrator.dart';
import '../utils/pos_print_template_runtime.dart';
import '../utils/pos_receipt_layout.dart';
import '../utils/pos_printer_transport.dart';
import '../utils/pos_store_printer_mapper.dart';
import '../utils/pos_sunmi_native_print.dart';
import '../utils/pos_thermal_printer_settings.dart';
import '../widgets/notification_overlay.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Print Agent: thi?t b? nh?n job in cloud (LAN/BT/USB) v? in c?c b?.
class PosPrintAgentService {
  PosPrintAgentService._();
  static final PosPrintAgentService instance = PosPrintAgentService._();

  static const _settledPrefsKey = 'pos_print_agent_settled_job_ids';

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
  /// Job d? complete/fail ? timeout kh?ng du?c ghi d? th?nh Failed sau khi gi?y d? in.
  /// Persist nh? d? tr?nh restart Agent ? reclaim ? in ch?ng.
  final _settledJobIds = <String>{};
  bool _settledLoaded = false;
  Timer? _claimDebounce;
  String? _lastRegisterError;
  bool _warnedNoPrinters = false;
  DateTime? _lastConfigRefreshAt;
  DateTime? _lastRegisterAt;
  StreamSubscription<Map<String, dynamic>>? _forceStopSub;
  StreamSubscription<bool>? _connSub;
  bool _ensureRunningInFlight = false;
  /// PrinterIds l?n heartbeat th?nh c?ng g?n nh?t (server AssignedPrinterIdsJson).
  List<String> _registeredPrinterIds = const [];
  DateTime? _lastOfflineMarkAt;

  bool get isRunning => _running;
  bool get isRegistered => _agentId != null && _agentId!.isNotEmpty;
  String? get agentId => _agentId;
  String? get lastRegisterError => _lastRegisterError;
  List<String> get registeredPrinterIds =>
      List<String>.unmodifiable(_registeredPrinterIds);

  /// T?m d?ng claim (tr?nh dua v?i test cloud tr?n ch?nh m?y Agent).
  bool _claimsPaused = false;

  void pauseClaims() => _claimsPaused = true;
  void resumeClaims() {
    _claimsPaused = false;
    _scheduleClaim();
  }

  /// ?p claim ngay (sau khi t?o job tr?n m?y kh?c / c?ng m?y).
  void nudgeClaim() => _scheduleClaim();

  Future<void> ensureRunning(String? storeId, {bool forceReregister = false}) async {
    // Web kh?ng in du?c BT/LAN/USB ? kh?ng dang k? Agent (tr?nh claim r?i fail).
    // M?y Android/tablet c?nh m?y in m?i ch?y Agent.
    if (kIsWeb) {
      await stop();
      return;
    }
    if (storeId == null || storeId.isEmpty) return;
    if (_ensureRunningInFlight) return;
    _ensureRunningInFlight = true;
    try {
      final settings = await PosPrintAgentSettings.load();
      if (!settings.enabled) {
        await stop();
        return;
      }
      // App m? l?i / SignalR reconnect: lu?n join l?i group + heartbeat,
      // kh?ng ch? khi forceReregister (tr?nh ph?i t?t-b?t Agent tay).
      if (_running && _storeId == storeId) {
        await _waitForSignalR();
        await _signalR.joinPrintAgentGroup(storeId);
        await _register(refreshPrinters: forceReregister);
        _scheduleClaim();
        return;
      }

      await stop(markOffline: false);
      _storeId = storeId;
      _deviceId = await PosPrintOrchestrator.stableDeviceId();
      _running = true;
      await _loadSettledJobIds();

      await _waitForSignalR();
      await _signalR.joinPrintAgentGroup(storeId);
      await _register(refreshPrinters: true);

      // Heartbeat 12s ? server stale 90s; Oppo th?y Agent online ?n d?nh hon.
      _heartbeatTimer =
          Timer.periodic(const Duration(seconds: 12), (_) => _register());
      _claimTimer =
          Timer.periodic(const Duration(seconds: 3), (_) => _scheduleClaim());
      await _jobNewSub?.cancel();
      _jobNewSub = _signalR.onPrintJobNew.listen((_) => _scheduleClaim());
      await _forceStopSub?.cancel();
      _forceStopSub = _signalR.onPrintAgentHeartbeat.listen(_onRemoteForceStop);
      await _connSub?.cancel();
      _connSub = _signalR.onConnectionStateChanged.listen((connected) {
        if (!connected || !_running || _storeId == null) return;
        // Debounce reconnect ? tr?nh b?o ensureRunning khi hub dao d?ng.
        unawaited(ensureRunning(_storeId!));
      });

      debugPrint('??? Print Agent started for store $storeId');
    } finally {
      _ensureRunningInFlight = false;
    }
  }

  Future<void> _waitForSignalR({int maxAttempts = 8}) async {
    for (var i = 0; i < maxAttempts; i++) {
      if (_signalR.isConnected) return;
      await Future.delayed(Duration(milliseconds: 250 + (i * 150)));
    }
  }

  Future<void> _onRemoteForceStop(Map<String, dynamic> data) async {
    final deviceId =
        (data['deviceId'] ?? data['DeviceId'])?.toString() ?? '';
    final forceStop = data['forceStop'] == true || data['ForceStop'] == true;
    final online = data['isOnline'] == true || data['IsOnline'] == true;
    if (!forceStop || online) return;
    if (deviceId.isEmpty || deviceId != _deviceId) return;
    if (!_running) return;

    debugPrint('??? Print Agent force-stopped by remote device');
    final settings = await PosPrintAgentSettings.load();
    await settings.copyWith(enabled: false).save();
    await stop(markOffline: false);
    NotificationOverlayManager().showWarning(
      title: 'Agent đã tắt từ máy khác',
      message: tr('Chỉ giữ Agent trên máy gắn máy in'),
    );
  }

  /// ?p dang k? l?i (g?n chip m?y in l?n server tru?c khi claim).
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
    await _connSub?.cancel();
    _heartbeatTimer = null;
    _claimTimer = null;
    _claimDebounce = null;
    _jobNewSub = null;
    _forceStopSub = null;
    _connSub = null;
    _activeJobIds.clear();
    _notifiedReceiveJobIds.clear();
    // Gi? _settledJobIds (+ prefs) ? tr?nh restart Agent in ch?ng job v?a in.
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
    _registeredPrinterIds = const [];
    debugPrint('??? Print Agent stopped');
  }

  Future<void> _register({bool refreshPrinters = false}) async {
    if (!_running || _storeId == null) return;
    // Ch?ng b?o register (UI/heartbeat) ? t?i thi?u 8s gi?a 2 l?n tr? khi refresh m?y in.
    final now = DateTime.now();
    if (!refreshPrinters &&
        _lastRegisterAt != null &&
        now.difference(_lastRegisterAt!) < const Duration(seconds: 8)) {
      return;
    }
    _lastRegisterAt = now;
    final settings = await PosPrintAgentSettings.load();
    if (!settings.enabled) {
      await stop();
      return;
    }

    // Heartbeat nh? ? kh?ng refresh m?y in m?i l?n (tr?nh ch?m / l?i m?ng l?m Agent offline).
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
    // B? chip m?y in d? x?a / kh?ng c?n tr?n server ? so kh?p GUID kh?ng ph?n bi?t hoa/thu?ng.
    if (_printers.isNotEmpty && printerIds.isNotEmpty) {
      final alive = {
        for (final p in _printers) PosPrintRole.normalizePrinterId(p.id),
      };
      final filtered = printerIds
          .where((id) => alive.contains(PosPrintRole.normalizePrinterId(id)))
          .toList();
      if (filtered.length != printerIds.length) {
        printerIds = filtered;
        await settings.copyWith(assignedPrinterIds: printerIds).save();
        debugPrint(
          '??? Print Agent: d? b? chip m?y in d? x?a, c?n ${printerIds.length}',
        );
      }
    }
    if (printerIds.isEmpty) {
      // Kh?ng t? g?n h?t m?y c?a h?ng ? user d? t?t chip th? gi? tr?ng
      // (tru?c d?y khi?n danh s?ch ?nh?y? l?i 6 m?y sau m?i heartbeat).
      _registeredPrinterIds = const [];
      _lastRegisterError = 'Chưa chọn chip máy in cho Agent';
      await _markOfflineOnServerIfNeeded();
      _agentId = null;
      if (!_warnedNoPrinters) {
        _warnedNoPrinters = true;
        NotificationOverlayManager().showWarning(
          title: 'Agent chưa gắn máy in',
          message: tr('Bật Agent và chọn ít nhất một chip máy in bên dưới'),
        );
      }
      return;
    }
    _warnedNoPrinters = false;

    // ?ang k? d? chip user d? ch?n ? k? c? USB t?m m?t (ADB / r?t c?p).
    // L?c printable tru?c d?y khi?n A6 ch? c?n Sunmi ? b?o b?p Zywell
    // agentOnlineForPrinter=0, kh?ng ai Claim. Claim l?c in: release n?u chua c? c?ng.
    final printableNow = await _filterLocallyPrintableIds(printerIds);
    if (printableNow.isEmpty) {
      debugPrint(
        '??? Print Agent: ${printerIds.length} chip d? ch?n nhung chua th?y c?ng in '
        '? v?n dang k? (USB c? th? b? ADB chi?m)',
      );
      if (!_warnedNoPrinters) {
        _warnedNoPrinters = true;
        NotificationOverlayManager().showWarning(
          title: 'Agent: chưa thấy cổng in',
          message: tr(
            'Vẫn nhận lệnh cloud. Rút USB ADB nếu in Tem/Zywell; kiểm tra chip máy in',
          ),
        );
      }
    } else {
      _warnedNoPrinters = false;
    }

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
        _registeredPrinterIds = List<String>.from(printerIds);
        _lastRegisterError = null;
        _lastOfflineMarkAt = null;
        _scheduleClaim();
        debugPrint(
          '??? Print Agent registered id=$_agentId printers=${printerIds.length}',
        );
      } else {
        // Gi? agentId cu n?u heartbeat l?i t?m th?i ? tr?nh Oppo m?t Agent gi?a ch?ng.
        _lastRegisterError =
            res['message']?.toString() ?? 'Đăng ký Agent thất bại';
        debugPrint('Print Agent register soft-fail: $_lastRegisterError');
      }
    } catch (e) {
      _lastRegisterError = e.toString();
      debugPrint('Print Agent register failed: $e');
    }
  }

  Future<void> _markOfflineOnServerIfNeeded() async {
    final deviceId = _deviceId;
    if (deviceId == null || deviceId.isEmpty) return;
    final now = DateTime.now();
    if (_lastOfflineMarkAt != null &&
        now.difference(_lastOfflineMarkAt!) < const Duration(seconds: 20)) {
      return;
    }
    _lastOfflineMarkAt = now;
    try {
      await _api.markPosPrintAgentOffline(deviceId: deviceId);
    } catch (e) {
      debugPrint('Print Agent mark offline: $e');
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
    // Job đã nhận nhưng chưa chốt. Lỗi bất ngờ (mất mạng lúc markPrinting, lỗi
    // cổng in…) mà bỏ qua thì job nằm Claimed tới khi server hủy STUCK — phiếu
    // bếp mất mà thu ngân không hề biết.
    String? claimedJobId;
    try {
      final res = await _api.claimPosPrintJob(_agentId!);
      if (res['isSuccess'] != true) return;
      final raw = res['data'];
      if (raw == null) return;
      if (raw is! Map) return;
      final data = Map<String, dynamic>.from(raw);

      final jobId = data['jobId']?.toString() ?? data['JobId']?.toString() ?? '';
      if (jobId.isEmpty) return;

      // ??/dang x? l? job n?y ? KH?NG fail (tr?nh b?o ?kh?ng in du?c?
      // trong khi l?n claim d?u d? in ra gi?y, r?i reclaim/claim l?i).
      if (_settledJobIds.contains(jobId)) {
        // App ch?/Agent claim l?i job d? in: complete tr?n server d? kh?ng
        // reclaim ? Queued ? in l?i phi?u b?p khi in h?a don sau.
        debugPrint('Print Agent: job $jobId d? settle ? complete l?i tr?n server');
        try {
          await _api.completePosPrintJob(jobId, _agentId!);
        } catch (e) {
          debugPrint('Print Agent: complete tr?ng job $jobId: $e');
        }
        return;
      }
      if (_activeJobIds.contains(jobId)) {
        debugPrint('Print Agent: b? claim tr?ng job $jobId (dang x? l?)');
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

      // Job do ch?nh m?y n?y g?i l?n cloud ? d? Agent kh?c (A6) nh?n, kh?ng t? claim.
      if (PosPrintSessionRegistry.isOutbound(jobId)) {
        debugPrint('Print Agent: b? claim job outbound $jobId (m?y g?i)');
        await _api.releasePosPrintJob(
          jobId,
          _agentId!,
          errorCode: 'OUTBOUND_SKIP',
          errorMessage: 'Máy gửi lệnh — nhả cho Print Agent',
        );
        return;
      }

      // ClaimNext d? l?c AssignedPrinterIdsJson tr?n server ? kh?ng fail ?kh?ng ph?c v??
      // khi SharedPreferences chip l?ch t?m th?i (A7 b?o d? d? A6 v?n in du?c).
      // Ch? nh? khi c?ng in kh?ng c? tr?n m?y n?y.
      if (!await _canPrintPrinterLocally(printerId)) {
        debugPrint(
          'Print Agent: nh? job $jobId ? m?y n?y kh?ng k?t n?i c?ng in $printerId',
        );
        await _api.releasePosPrintJob(
          jobId,
          _agentId!,
          errorCode: 'NOT_LOCAL_PORT',
          errorMessage: 'Máy này không kết nối được cổng in — nhả cho Agent khác',
        );
        return;
      }

      _activeJobIds.add(jobId);
      claimedJobId = jobId;
      if (_activeJobIds.length > 50) {
        _activeJobIds.remove(_activeJobIds.first);
      }

      _notifyReceivedOnce(data, jobId);

      // Payload tem TSPL l?n: claim ??i khi v? r?ng / c?t ? l?y l?i qua GET.
      var formatEarly =
          data['payloadFormat']?.toString() ?? data['PayloadFormat']?.toString() ?? '';
      var payloadEarly =
          data['payload']?.toString() ?? data['Payload']?.toString() ?? '';
      if (payloadEarly.trim().isEmpty ||
          (formatEarly == 'EscPosBase64' && payloadEarly.length < 32)) {
        try {
          final full = await _api.getPosPrintJob(jobId);
          if (full['isSuccess'] == true && full['data'] is Map) {
            final m = Map<String, dynamic>.from(full['data'] as Map);
            final p = m['payload']?.toString() ?? m['Payload']?.toString() ?? '';
            if (p.trim().isNotEmpty) {
              data['payload'] = p;
              data['Payload'] = p;
              data['payloadFormat'] =
                  m['payloadFormat']?.toString() ?? formatEarly;
            }
          }
        } catch (e) {
          debugPrint('Print Agent: refill payload $jobId: $e');
        }
      }

      await _api.markPosPrintJobPrinting(jobId, _agentId!);
      // Timeout ? tr?nh 1 job USB/tem treo Agent ng?ng claim.
      // USB native block isolate: timeout ch? k?ch khi future yield; v?n fail
      // n?u send c? timeout ri?ng.
      try {
        await _executeJob(data, jobId).timeout(const Duration(seconds: 75));
      } on TimeoutException {
        debugPrint('Print Agent: job $jobId timeout 75s');
        if (_settledJobIds.contains(jobId)) return;
        try {
          final statusRes = await _api.getPosPrintJob(jobId);
          final st = (statusRes['data'] is Map)
              ? (statusRes['data'] as Map)['status']?.toString()
              : null;
          if (st == 'Completed' || st == 'Failed' || st == 'Expired') {
            _markJobSettled(jobId);
            return;
          }
        } catch (_) {}
        if (_settledJobIds.contains(jobId)) return;
        try {
          await _api.failPosPrintJob(
            jobId,
            _agentId!,
            errorCode: 'PRINT_TIMEOUT',
            errorMessage:
                'In quá 75 giây — kiểm tra USB tem (rút ADB) / giấy / máy',
          );
          _markJobSettled(jobId);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Print Agent claim error: $e');
      await _failAbandonedJob(claimedJobId, e);
    } finally {
      _claimInFlight = false;
      // X? h?ng d?i ngay ? kh?ng ch? timer 3s.
      if (_running && !_claimsPaused) _scheduleClaim();
    }
  }

  /// Báo hỏng job đã nhận nhưng chưa in xong, để máy gửi thấy lỗi ngay thay vì
  /// chờ server hủy STUCK sau 3 phút (thu ngân tưởng bếp đã nhận món).
  Future<void> _failAbandonedJob(String? jobId, Object error) async {
    if (jobId == null || jobId.isEmpty) return;
    if (_settledJobIds.contains(jobId)) return;
    final agentId = _agentId;
    if (agentId == null) {
      _activeJobIds.remove(jobId);
      return;
    }
    try {
      await _api.failPosPrintJob(
        jobId,
        agentId,
        errorCode: 'AGENT_ERROR',
        errorMessage: 'Agent lỗi khi in — thử lại hoặc chọn máy khác ($error)',
      );
      _markJobSettled(jobId);
    } catch (e) {
      debugPrint('Print Agent: không báo hỏng được job $jobId: $e');
      _activeJobIds.remove(jobId);
    }
  }

  void _markJobSettled(String jobId) {
    _activeJobIds.remove(jobId);
    _settledJobIds.add(jobId);
    if (_settledJobIds.length > 120) {
      final drop = _settledJobIds.take(_settledJobIds.length - 100).toList();
      for (final id in drop) {
        _settledJobIds.remove(id);
      }
    }
    unawaited(_persistSettledJobIds());
  }

  Future<void> _loadSettledJobIds() async {
    if (_settledLoaded) return;
    _settledLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_settledPrefsKey) ?? const [];
      _settledJobIds
        ..clear()
        ..addAll(raw.where((e) => e.trim().isNotEmpty).take(120));
    } catch (e) {
      debugPrint('Print Agent load settled ids: $e');
    }
  }

  Future<void> _persistSettledJobIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _settledPrefsKey,
        _settledJobIds.take(100).toList(growable: false),
      );
    } catch (_) {}
  }

  void _notifyReceivedOnce(Map<String, dynamic> job, String jobId) {
    if (_notifiedReceiveJobIds.contains(jobId)) return;
    _notifiedReceiveJobIds.add(jobId);
    if (_notifiedReceiveJobIds.length > 50) {
      _notifiedReceiveJobIds.remove(_notifiedReceiveJobIds.first);
    }
    // M?y Agent: 1 d?ng g?n ? kh?ng ch?ng toast v?i m?y g?i.
    final ref = job['referenceNo']?.toString() ?? '';
    NotificationOverlayManager().show(
      title: 'Đã nhận lệnh in',
      message: ref.isNotEmpty ? 'Đơn $ref — đang in…' : 'Đang in chứng từ…',
      duration: const Duration(seconds: 2),
      relatedEntityType: kPosPrintNotifyKind,
    );
  }

  /// TSPL thu?ng b?t d?u b?ng SIZE / CLS / BITMAP ? EscPos b?t d?u ESC (@?).
  static bool _payloadLooksLikeTspl(List<int> bytes) {
    if (bytes.isEmpty) return false;
    final n = bytes.length < 96 ? bytes.length : 96;
    final head = String.fromCharCodes(bytes.take(n));
    final u = head.toUpperCase();
    return u.contains('SIZE ') ||
        u.contains('CLS') ||
        u.contains('BITMAP') ||
        u.contains('PRINT ');
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
      _markJobSettled(jobId);
      return;
    }

    // Uu ti?n c?ng USB/BT/LAN d? luu tr?n m?y Agent (in n?i b? OK) ?
    // cloud d?i khi thi?u/sai usbDeviceName ? job Completed nhung kh?ng ra gi?y.
    final local =
        await PosLocalPrintersStore.instance.resolveForStorePrinter(printer);
    final settings = local != null
        ? local.toThermalSettings()
        : toThermalSettings(printer);
    var ok = true;

    if (format == 'SaleOrderJson') {
      // Sunmi: in native gi?ng m?y in n?i b? (UTF-8, c? ch? d?ng).
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
        // Uu ti?n order nh?ng trong payload (?n d?nh hon g?i l?i API).
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
          throw const FormatException('KitchenSlipJson khong phai object');
        }

        final slipMap = Map<String, dynamic>.from(map);
        final kind = slipMap['kind']?.toString() ?? '';
        if (kind == 'kdsReady') {
          ok = await _printKdsReadySlip(
            printer: printer,
            settings: settings,
            slipMap: slipMap,
            copies: copies,
          );
        } else {
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
        final nativeLines =
            <({String name, String qty, String? unit, String? note})>[];
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
        final sentAt =
            DateTime.tryParse(sentAtRaw)?.toLocal() ?? DateTime.now();
        final isCancel = slipMap['isCancel'] == true;
        final tableName = slipMap['tableName']?.toString() ?? 'Ban';
        final senderName = slipMap['senderName']?.toString() ?? 'admin';
        final orderNo = slipMap['orderNo']?.toString() ?? '';
        final cutPerItem = slipMap['cutPerItem'] == true;
        final onSunmi = await PosPrinterTransport.isSunmiDevice();
        final preferNative = onSunmi &&
            (printer.isSunmi ||
                settings.connectionType == PosThermalConnectionType.sunmi ||
                settings.printerBrand == PosThermalPrinterBrand.sunmi);

        Future<bool> printGroup(
          List<({String name, String qty, String? unit, String? note})> group,
        ) async {
          var groupOk = false;
          if (preferNative) {
            final kitchenSettings = settings.copyWith(
              connectionType: PosThermalConnectionType.sunmi,
              printerBrand: PosThermalPrinterBrand.sunmi,
              feedBeforeCut: 2,
              openCashDrawer: false,
            );
            groupOk = true;
            for (var i = 0; i < copies.clamp(1, 10); i++) {
              final sent = await PosSunmiNativePrint.printKitchenSlip(
                tableName: tableName,
                isCancel: isCancel,
                lines: group,
                senderName: senderName,
                orderNo: orderNo,
                sentAt: sentAt,
                settings: kitchenSettings,
              );
              if (!sent) {
                groupOk = false;
                break;
              }
            }
          }
          if (!groupOk) {
            groupOk = await _printKitchenSlipEscPos(
              settings: settings.copyWith(openCashDrawer: false),
              isCancel: isCancel,
              tableName: tableName,
              lines: group,
              senderName: senderName,
              orderNo: orderNo,
              sentAt: sentAt,
              copies: copies,
            );
          }
          return groupOk;
        }

        if (cutPerItem && nativeLines.length > 1) {
          ok = true;
          for (final line in nativeLines) {
            if (!await printGroup([line])) {
              ok = false;
              break;
            }
          }
        } else {
          ok = await printGroup(nativeLines);
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
      // Sunmi: ESC/POS qua printEscPos hay l?i font ti?ng Vi?t / in ra l?nh th?.
      // M?i job tr?n m?y Sunmi ? uu ti?n native (test JSON ho?c test slip).
      final isTest = referenceNo.toUpperCase() == 'TEST' ||
          referenceNo.toUpperCase().startsWith('TEST');
      final onSunmi = printer.isSunmi &&
          await PosPrinterTransport.isSunmiDevice();
      if (onSunmi && isTest) {
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
      } else if (onSunmi && !isTest) {
        // Kh?ng dump ESC/POS l?n Sunmi (font/r?c). Job ph?i l? SaleOrderJson.
        await _api.failPosPrintJob(
          jobId,
          _agentId!,
          errorCode: 'UNSUPPORTED_ON_SUNMI',
          errorMessage:
              'Sunmi không in EscPosBase64 (lỗi font VN). Dùng SaleOrderJson / TestPrintJson.',
        );
        _markJobSettled(jobId);
        return;
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
        // M?y tem TSPL nh?n nh?m EscPos ? USB ghi OK nhung kh?ng ra tem.
        if (printer.isLabelPrinter) {
          final proto = (printer.textMode ?? 'tspl').toLowerCase();
          if (proto.contains('tspl') && !_payloadLooksLikeTspl(bytes)) {
            await _api.failPosPrintJob(
              jobId,
              _agentId!,
              errorCode: 'WRONG_LABEL_PROTOCOL',
              errorMessage:
                  'Máy tem TSPL nhận lệnh ESC/POS — cập nhật app gửi tem (TSPL)',
            );
            _markJobSettled(jobId);
            return;
          }
        }
        final sunmiFeed = printer.isSunmi ? 4 : settings.resolvedFeedBeforeCut;
        // Kh?ng ?p Sunmi n?i b? cho job m?y LAN/BT/USB (tem).
        final conn = settings.connectionType;
        // Tem TSPL d? ch?a PRINT 1,1 ? copies>1 s? ra g?p d?i/g?p ba.
        final effectiveCopies = (printer.isLabelPrinter ||
                _payloadLooksLikeTspl(bytes))
            ? 1
            : copies.clamp(1, 10);
        for (var i = 0; i < effectiveCopies; i++) {
          final sent = await PosPrinterTransport.send(
            connectionType: conn,
            bluetoothAddress: settings.bluetoothAddress,
            lanHost: settings.lanHost,
            lanPort: settings.lanPort,
            usbDeviceName: settings.usbDeviceName,
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
      _markJobSettled(jobId);
      return;
    }

    if (ok) {
      _markJobSettled(jobId);
      await _api.completePosPrintJob(jobId, _agentId!);
      await _api.reportPosPrinterHealth(printer.id, status: 'Online');
      NotificationOverlayManager().showSuccess(
        title: 'In xong',
        message: referenceNo.isNotEmpty
            ? 'Đơn $referenceNo — ${printer.name}'
            : printer.name,
        relatedEntityType: kPosPrintNotifyKind,
        duration: const Duration(seconds: 2),
      );
    } else {
      _markJobSettled(jobId);
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

  Future<bool> _printKdsReadySlip({
    required PosStorePrinter printer,
    required PosThermalPrinterSettings settings,
    required Map<String, dynamic> slipMap,
    required int copies,
  }) async {
    final product = slipMap['productName']?.toString() ?? '';
    final qty = slipMap['qty']?.toString() ?? '1';
    final table = slipMap['tableName']?.toString() ?? '';
    final area = slipMap['areaName']?.toString() ?? '';
    final orderNo = slipMap['orderNo']?.toString() ?? '';
    String fmt(dynamic raw) {
      final t = DateTime.tryParse(raw?.toString() ?? '');
      if (t == null) return '';
      final l = t.toLocal();
      return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
    }

    final called = fmt(slipMap['calledAt']);
    final ready = fmt(slipMap['readyAt']);
    final textLines = <String>[
      '$qty × $product',
      if (area.trim().isNotEmpty) area.trim(),
      table,
      if (orderNo.trim().isNotEmpty)
        'HĐ: ${PosReceiptLayout.formatSaleInvoiceNo(orderNo)}',
      if (called.isNotEmpty) 'Gọi: $called',
      'Ra món: ${ready.isEmpty ? DateFormat('HH:mm').format(DateTime.now()) : ready}',
    ];
    final onSunmi = await PosPrinterTransport.isSunmiDevice();
    if (onSunmi) {
      var ok = true;
      for (var i = 0; i < copies.clamp(1, 10); i++) {
        final sent = await PosSunmiNativePrint.printTextReport(
          title: 'RA MÓN',
          lines: textLines,
          settings: settings.copyWith(openCashDrawer: false),
        );
        if (!sent) {
          ok = false;
          break;
        }
      }
      return ok;
    }
    return _printKitchenSlipEscPos(
      settings: settings.copyWith(openCashDrawer: false),
      isCancel: false,
      tableName: area.trim().isEmpty ? table : '${area.trim()} · $table',
      lines: [
        (
          name: product,
          qty: qty,
          unit: null,
          note: 'Gọi $called · Ra $ready',
        ),
      ],
      senderName: 'KDS',
      orderNo: orderNo,
      sentAt: DateTime.tryParse(slipMap['readyAt']?.toString() ?? '') ??
          DateTime.now(),
      copies: copies,
    );
  }

  Future<bool> _printKitchenSlipEscPos({
    required PosThermalPrinterSettings settings,
    required bool isCancel,
    required String tableName,
    required List<({String name, String qty, String? unit, String? note})> lines,
    required String senderName,
    required String orderNo,
    required DateTime sentAt,
    required int copies,
  }) async {
    final tpl = await PosPrintConfigSession.instance
        .kitchenTemplate(isCancel: isCancel);
    final v2 = PosPrintTemplateRuntime.resolveOrPreset(
      template: tpl,
      documentType: isCancel
          ? PosPrintDocumentTypes.kitchenVoid
          : PosPrintDocumentTypes.kitchenSlip,
      paperSize: settings.paperSize,
      printerProfile: PosPrintPrinterProfiles.forPaperAndBrand(
        paperSize: settings.paperSize,
        isSunmi: settings.printerBrand == PosThermalPrinterBrand.sunmi,
        isZywell: settings.printerBrand == PosThermalPrinterBrand.zywell,
      ),
    );
    final output = PosPrintTemplateRuntime.compileKitchenSlip(
      template: v2,
      tableName: tableName,
      isCancel: isCancel,
      lines: lines,
      senderName: senderName,
      orderNo: orderNo,
      sentAt: sentAt,
    );
    final bytes = await PosPrintTemplateRuntime.buildCompiledEscPosBytes(
      output: output,
      settings: settings,
    );
    for (var i = 0; i < copies.clamp(1, 10); i++) {
      final sent = await PosPrinterTransport.send(
        connectionType: settings.connectionType,
        bluetoothAddress: settings.bluetoothAddress,
        lanHost: settings.lanHost,
        lanPort: settings.lanPort,
        usbDeviceName: settings.usbDeviceName,
        bytes: bytes,
        sunmiFeedLines: settings.resolvedFeedBeforeCut,
      );
      if (!sent) return false;
    }
    return true;
  }

  /// Heartbeat ch? b?o printerIds m? m?y n?y th?c s? in du?c (USB g?n / Sunmi / LAN-BT).
  Future<List<String>> _filterLocallyPrintableIds(List<String> ids) async {
    if (ids.isEmpty) return ids;
    final out = <String>[];
    for (final id in ids) {
      if (await _canPrintPrinterLocally(id)) out.add(id);
    }
    return out;
  }

  Future<bool> _canPrintPrinterLocally(String printerId) async {
    if (printerId.isEmpty) return false;
    PosStorePrinter? printer =
        _printers.where((p) => p.id == printerId).firstOrNull;
    if (printer == null) {
      try {
        final res = await _api.getPosStorePrinter(printerId);
        if (res['isSuccess'] == true && res['data'] is Map) {
          printer =
              PosStorePrinter.fromJson(res['data'] as Map<String, dynamic>);
        }
      } catch (_) {}
    }
    if (printer == null) return false;

    final local =
        await PosLocalPrintersStore.instance.resolveForStorePrinter(printer);
    final settings = local != null
        ? local.toThermalSettings()
        : toThermalSettings(printer);

    // LAN / BT: Agent b?t k? tr?n m?ng d?u c? th? g?i ? gi? chip.
    if (settings.connectionType == PosThermalConnectionType.lan ||
        settings.connectionType == PosThermalConnectionType.bluetooth) {
      return true;
    }

    final usbList = await PosPrinterReadiness.listUsbDevices();
    return PosPrinterReadiness.probePort(
      connectionType: settings.connectionType,
      usbDeviceName: settings.usbDeviceName,
      lanHost: settings.lanHost,
      lanPort: settings.lanPort,
      bluetoothAddress: settings.bluetoothAddress,
      usbList: usbList,
    );
  }
}
