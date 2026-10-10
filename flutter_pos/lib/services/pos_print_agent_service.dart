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
import '../utils/pos_kds_alert.dart';
import '../utils/pos_print_agent_settings.dart';
import '../utils/pos_print_config_session.dart';
import '../utils/pos_print_role.dart';
import '../utils/pos_printer_readiness.dart';
import '../utils/pos_print_orchestrator.dart';
import '../utils/pos_print_template_runtime.dart';
import '../utils/pos_sell_store_settings.dart';
import '../utils/pos_print_template_renderer.dart';
import '../utils/pos_receipt_layout.dart';
import '../utils/pos_printer_transport.dart';
import '../utils/pos_store_printer_mapper.dart';
import '../utils/pos_sunmi_native_print.dart';
import '../utils/pos_thermal_printer_settings.dart';
import '../widgets/notification_overlay.dart';
import 'package:sbox_pos/l10n/app_tr.dart';
import '../utils/pos_print_template_v2_codec.dart';
import '../utils/pos_print_template_compiler.dart';

/// Print Agent: thiết bị nhận job in cloud (LAN/BT/USB) về in cục bộ.
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
  /// Job đã complete/fail → timeout không được ghi đè thành Failed sau khi giấy đã in.
  /// Persist nhẹ để tránh restart Agent → reclaim → in chồng.
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
  /// PrinterIds lần heartbeat thành công gần nhất (server AssignedPrinterIdsJson).
  List<String> _registeredPrinterIds = const [];
  DateTime? _lastOfflineMarkAt;

  bool get isRunning => _running;
  bool get isRegistered => _agentId != null && _agentId!.isNotEmpty;
  String? get agentId => _agentId;
  String? get lastRegisterError => _lastRegisterError;
  List<String> get registeredPrinterIds =>
      List<String>.unmodifiable(_registeredPrinterIds);

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
    // Web không in được BT/LAN/USB → không đăng ký Agent (tránh claim rồi fail).
    // Máy Android/tablet cạnh máy in mới chạy Agent.
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
      // App mở lại / SignalR reconnect: luôn join lại group + heartbeat,
      // không chỉ khi forceReregister (tránh phải tắt-bật Agent tay).
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

      // Heartbeat 12s ← server stale 90s; Oppo thấy Agent online ổn định hơn.
      _heartbeatTimer =
          Timer.periodic(const Duration(seconds: 12), (_) => _register());
      _claimTimer =
          Timer.periodic(const Duration(seconds: 2), (_) => _scheduleClaim());
      await _jobNewSub?.cancel();
      _jobNewSub = _signalR.onPrintJobNew.listen((_) => _scheduleClaim());
      await _forceStopSub?.cancel();
      _forceStopSub = _signalR.onPrintAgentHeartbeat.listen(_onRemoteForceStop);
      await _connSub?.cancel();
      _connSub = _signalR.onConnectionStateChanged.listen((connected) {
        if (!connected || !_running || _storeId == null) return;
        // Debounce reconnect → tránh bão ensureRunning khi hub dao động.
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
    await _connSub?.cancel();
    _heartbeatTimer = null;
    _claimTimer = null;
    _claimDebounce = null;
    _jobNewSub = null;
    _forceStopSub = null;
    _connSub = null;
    _activeJobIds.clear();
    _notifiedReceiveJobIds.clear();
    // Giữ _settledJobIds (+ prefs) → tránh restart Agent in chồng job vừa in.
    if (storeId != null) {
      await _signalR.leavePrintAgentGroup(storeId);
    }
    if (markOffline && wasRunning && deviceId != null && deviceId.isNotEmpty) {
      try {
        await _api.markPosPrintAgentOffline(
          deviceId: deviceId,
          forceStop: false,
        );
      } catch (_) {}
    }
    _storeId = null;
    _agentId = null;
    _registeredPrinterIds = const [];
    debugPrint('??? Print Agent stopped');
  }

  Future<void> _register({bool refreshPrinters = false}) async {
    if (!_running || _storeId == null) return;
    // Chống bão register (UI/heartbeat) — tối thiểu 8s giữa 2 lần trừ khi refresh máy in.
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
    // Bỏ chip máy in đã xóa / không còn trên server — so khớp GUID không phân biệt hoa/thường.
    if (_printers.isNotEmpty && printerIds.isNotEmpty) {
      final alive = {
        for (final p in _printers) PosPrintRole.normalizePrinterId(p.id),
      };
      final filtered = printerIds
          .where((id) => alive.contains(PosPrintRole.normalizePrinterId(id)))
          .toList();
      if (filtered.length != printerIds.length) {
        // Sau reshare: twin mới có thể chưa kịp vào list (hoặc vừa bị orphan cleanup).
        // Đừng ghi prefs rỗng ngay — vẫn heartbeat với id vừa gán.
        if (filtered.isEmpty && refreshPrinters && printerIds.isNotEmpty) {
          debugPrint(
            '??? Print Agent: giữ chip vừa gán (list server tạm thiếu ${printerIds.length})',
          );
        } else {
          printerIds = filtered;
          await settings.copyWith(assignedPrinterIds: printerIds).save();
          debugPrint(
            '??? Print Agent: bỏ chip máy in đã xóa, còn ${printerIds.length}',
          );
        }
      }
    }
    // Sunmi chưa cài máy nội bộ: không đăng ký claim — hardware in ≠ đã cài.
    if (printerIds.isNotEmpty) {
      final claimable = <String>[];
      for (final id in printerIds) {
        final p = _printers
            .where((x) => PosPrintRole.matchesPrinterId(x.id, id))
            .firstOrNull;
        if (p == null || !p.isSunmi) {
          claimable.add(id);
        } else if (await _canPrintPrinterLocally(id)) {
          claimable.add(id);
        }
      }
      printerIds = claimable;
    }
    if (printerIds.isEmpty) {
      // Không tự gắn hết máy của hàng — user đã tắt chip thì giữ trống
      // (trước đây khiến danh sách «nhảy» lại 6 máy sau mỗi heartbeat).
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

    // Đăng ký đủ chip user đã chọn — kể cả USB tạm mất (ADB / rút cáp).
    // Lọc printable trước đây khiến A6 chỉ còn Sunmi → báo bếp Zywell
    // agentOnlineForPrinter=0, không ai Claim. Claim lúc in: release nếu chưa có cổng.
    final printableNow = await _filterLocallyPrintableIds(printerIds);
    if (printableNow.isEmpty) {
      debugPrint(
        '⚠️ Print Agent: ${printerIds.length} chip đã chọn nhưng chưa thấy cổng in '
        '— vẫn đăng ký (USB có thể bị ADB chiếm)',
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
        // Chỉ Online khi cổng in còn sẵn sàng — USB rút không bị heartbeat ép Online.
        onlinePrinterIds: printableNow,
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
        // Giữ agentId cũ nếu heartbeat lỗi tạm thời → tránh Oppo mất Agent giữa chừng.
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
      await _api.markPosPrintAgentOffline(
        deviceId: deviceId,
        forceStop: false,
      );
    } catch (e) {
      debugPrint('Print Agent mark offline: $e');
    }
  }

  void _scheduleClaim() {
    if (!_running) return;
    _claimDebounce?.cancel();
    _claimDebounce = Timer(const Duration(milliseconds: 80), _tryClaim);
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

      // Đã/đang xử lý job này → KHÔNG fail (tránh báo «không in được»
      // trong khi lần claim đầu đã in ra giấy, rồi reclaim/claim lại).
      if (_settledJobIds.contains(jobId)) {
        // App chủ/Agent claim lại job đã in: complete trên server để không
        // reclaim → Queued → in lại phiếu bếp khi in hóa đơn sau.
        debugPrint('Print Agent: job $jobId đã settle → complete lại trên server');
        try {
          await _api.completePosPrintJob(jobId, _agentId!);
        } catch (e) {
          debugPrint('Print Agent: complete trùng job $jobId: $e');
        }
        return;
      }
      if (_activeJobIds.contains(jobId)) {
        debugPrint('Print Agent: bỏ claim trùng job $jobId (đang xử lý)');
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

      // Job do chính máy này gửi lên cloud → để Agent khác (A6) nhận, không tự claim.
      if (PosPrintSessionRegistry.isOutbound(jobId)) {
        debugPrint('Print Agent: bỏ claim job outbound $jobId (máy gửi)');
        await _api.releasePosPrintJob(
          jobId,
          _agentId!,
          errorCode: 'OUTBOUND_SKIP',
          errorMessage: 'Máy gửi lệnh — nhả cho Print Agent',
        );
        return;
      }

      // ClaimNext đã lọc AssignedPrinterIdsJson trên server → không fail «không phục vụ»
      // khi SharedPreferences chip lệch tạm thời (A7 báo đủ để A6 vẫn in được).
      // Chỉ nhả khi cổng in không có trên máy này.
      if (!await _canPrintPrinterLocally(printerId)) {
        debugPrint(
          'Print Agent: nhả job $jobId — máy này không kết nối cổng in $printerId',
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

      // Payload tem TSPL lớn: claim đôi khi về rỗng / cắt → lấy lại qua GET.
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

      // Chỉ in khi server xác nhận «đang in». Không xác nhận được mà vẫn in thì
      // server còn coi job là Claimed → có thể nhả cho Agent khác → in 2 phiếu.
      var marked = await _api.markPosPrintJobPrinting(jobId, _agentId!);
      if (marked['isSuccess'] != true) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        marked = await _api.markPosPrintJobPrinting(jobId, _agentId!);
      }
      if (marked['isSuccess'] != true) {
        debugPrint('Print Agent: không xác nhận được bắt đầu in $jobId — nhả, không in');
        _activeJobIds.remove(jobId);
        claimedJobId = null;
        try {
          await _api.releasePosPrintJob(
            jobId,
            _agentId!,
            errorCode: 'MARK_PRINTING_FAILED',
            errorMessage: 'Agent không xác nhận được bắt đầu in — xếp lại hàng đợi',
          );
        } catch (_) {}
        return;
      }
      // Timeout — tránh 1 job USB/tem treo làm Agent ngừng claim.
      // USB native block isolate: timeout chỉ kích khi future yield; vẫn fail
      // nếu send có timeout riêng.
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
                'Quá 75 giây chưa xác nhận in xong — CÓ THỂ ĐÃ IN, kiểm tra giấy trước khi in lại',
          );
          _markJobSettled(jobId);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Print Agent claim error: $e');
      await _failAbandonedJob(claimedJobId, e);
    } finally {
      _claimInFlight = false;
      // Xử hàng đợi ngay — không chờ timer 3s.
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
    // Máy Agent: 1 dòng gọn — không chồng toast với máy gửi.
    final format =
        (job['payloadFormat'] ?? job['PayloadFormat'] ?? '').toString();
    final doc =
        (job['documentType'] ?? job['DocumentType'] ?? '').toString().toLowerCase();
    final kitchen = format == 'KitchenSlipJson' || doc.contains('kitchen');
    if (kitchen) unawaited(_tingKitchenIfEnabled());
    final ref = job['referenceNo']?.toString() ?? '';
    NotificationOverlayManager().show(
      title: 'Đã nhận lệnh in',
      message: ref.isNotEmpty ? 'Đơn $ref — đang in…' : 'Đang in chứng từ…',
      duration: const Duration(seconds: 2),
      relatedEntityType: kPosPrintNotifyKind,
    );
  }

  Future<void> _tingKitchenIfEnabled() async {
    if (!await PosKdsAlert.printTingEnabled()) return;
    await PosKdsAlert.playTing();
  }

  /// TSPL thường bắt đầu bằng SIZE / CLS / BITMAP; EscPos bắt đầu ESC (@…).
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

    // Ưu tiên cổng USB/BT/LAN đã lưu trên máy Agent (in nội bộ OK) —
    // cloud đôi khi thiếu/sai usbDeviceName → job Completed nhưng không ra giấy.
    final local =
        await PosLocalPrintersStore.instance.resolveForStorePrinter(printer, exactPort: true);
    final settings = local != null
        ? local.toThermalSettings()
        : toThermalSettings(printer);
    var ok = true;

    if (format == 'SaleOrderJson') {
      // Sunmi: compile mẫu thiết kế store (cùng local) — không hardcode layout.
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

        final vatIncludedFlag = map['vatIncludedInPrice'];
        bool? vatIncludedInPrice;
        if (vatIncludedFlag == true) {
          vatIncludedInPrice = true;
        } else if (vatIncludedFlag == false) {
          vatIncludedInPrice = false;
        }
        ok = await _printSaleOrderWithStoreTemplate(
          order: order,
          settings: settings,
          storeName: map['storeName']?.toString(),
          storeAddress: map['storeAddress']?.toString(),
          storePhone: map['storePhone']?.toString(),
          mergeSameItems: map['mergeSameItems'] != false && !warehouseSlip,
          documentTitle: map['documentTitle']?.toString() ??
              map['slipTitle']?.toString(),
          warehouseSlip: warehouseSlip,
          linesOverride: linesOverride,
          copies: copies,
          vatIncludedInPrice: vatIncludedInPrice,
        );
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

        Future<bool> printGroup(
          List<({String name, String qty, String? unit, String? note})> group,
        ) async {
          return _printKitchenSlipEscPos(
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
    
    } else if (format == 'TemplatePreviewJson') {
      // In thử mẫu V2 từ editor — Agent compile đúng draft, Sunmi native / ESC.
      try {
        final map = jsonDecode(payload);
        if (map is! Map) {
          throw const FormatException('TemplatePreviewJson không phải object');
        }
        final content = map['templateContent']?.toString() ?? '';
        final docType = map['documentType']?.toString() ??
            PosPrintDocumentTypes.saleInvoice;
        final paperSize = (map['paperSize']?.toString() ?? '').trim().isNotEmpty
            ? map['paperSize'].toString()
            : settings.paperSize;
        final v2raw = PosPrintTemplateV2Codec.tryParse(content);
        if (v2raw == null) {
          await _api.failPosPrintJob(
            jobId,
            _agentId!,
            errorCode: 'BAD_TEMPLATE',
            errorMessage: 'Không parse được mẫu V2 preview',
          );
          _markJobSettled(jobId);
          return;
        }
        final v2 = v2raw.copyWith(
          documentType: docType,
          paperSize: paperSize,
        );
        final mode = map['mode']?.toString() ?? 'sale';
        late final PosPrintCompiledOutput output;
        if (mode == 'kitchenSlip') {
          final k = map['kitchen'];
          final km = k is Map ? Map<String, dynamic>.from(k) : <String, dynamic>{};
          final linesRaw = km['lines'];
          final lines = <({String name, String qty, String? unit, String? note})>[];
          if (linesRaw is List) {
            for (final e in linesRaw) {
              if (e is! Map) continue;
              lines.add((
                name: e['name']?.toString() ?? e['Ten_Hang_Hoa']?.toString() ?? '',
                qty: e['qty']?.toString() ?? e['So_Luong']?.toString() ?? '1',
                unit: e['unit']?.toString() ?? e['Don_Vi_Tinh']?.toString(),
                note: e['note']?.toString() ?? e['Ghi_Chu']?.toString(),
              ));
            }
          }
          output = PosPrintTemplateRuntime.compileKitchenSlip(
            template: v2,
            tableName: km['tableName']?.toString() ?? 'Bàn',
            isCancel: km['isCancel'] == true ||
                docType == PosPrintDocumentTypes.kitchenVoid,
            lines: lines.isEmpty
                ? const [
                    (name: 'Món demo', qty: '1', unit: null, note: null),
                  ]
                : lines,
            senderName: km['senderName']?.toString() ?? 'NV',
            orderNo: km['orderNo']?.toString() ?? 'DH0001',
            sentAt: DateTime.tryParse(km['sentAt']?.toString() ?? '') ??
                DateTime.now(),
          );
        } else {
          final dataRaw = map['data'];
          final data = <String, String>{};
          if (dataRaw is Map) {
            dataRaw.forEach((k, v) {
              data[k.toString()] = v?.toString() ?? '';
            });
          }
          final items = <Map<String, String>>[];
          final li = map['lineItems'];
          if (li is List) {
            for (final e in li) {
              if (e is! Map) continue;
              items.add({
                for (final me in e.entries)
                  me.key.toString(): me.value?.toString() ?? '',
              });
            }
          }
          output = PosPrintTemplateCompiler.compile(
            template: v2,
            data: data,
            lineItems: items,
          );
        }
        final kitchenFeed = map['kitchenFeed'] == true || mode == 'kitchenSlip';
        final targetSunmi =
            printer.isSunmi ||
            settings.connectionType == PosThermalConnectionType.sunmi;
        if (targetSunmi && await PosPrinterTransport.isSunmiDevice()) {
          ok = await PosPrintTemplateRuntime.printCompiledSunmi(
            output: output,
            settings: settings.copyWith(
              connectionType: PosThermalConnectionType.sunmi,
              printerBrand: PosThermalPrinterBrand.sunmi,
              paperSize: paperSize,
            ),
            copies: copies.clamp(1, 10),
            kitchenFeed: kitchenFeed,
          );
        } else {
          final bytes =
              await PosPrintTemplateRuntime.buildCompiledEscPosBytes(
            output: output,
            settings: settings.copyWith(paperSize: paperSize),
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
            if (!sent) {
              ok = false;
              break;
            }
          }
        }
      } catch (e) {
        await _api.failPosPrintJob(
          jobId,
          _agentId!,
          errorCode: 'TEMPLATE_PREVIEW_FAIL',
          errorMessage: 'TemplatePreviewJson lỗi: $e',
        );
        _markJobSettled(jobId);
        return;
      }

    } else if (format == 'EscPosBase64') {
      // Sunmi: ESC/POS qua printEscPos hay lỗi font tiếng Việt / in ra lệnh thô.
      // Mọi job trên máy Sunmi → ưu tiên native (test JSON hoặc test slip).
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
        // Không dump ESC/POS lên Sunmi (font/rác). Job phải là SaleOrderJson.
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
        // Máy tem TSPL nhận nhầm EscPos → USB ghi OK nhưng không ra tem.
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
        // Không ép Sunmi nội bộ cho job máy LAN/BT/USB (tem).
        final conn = settings.connectionType;
        // Tem TSPL đã chứa PRINT 1,1 → copies>1 sẽ ra gấp đôi/gấp ba.
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
    final table = slipMap['tableName']?.toString() ?? '';
    final area = slipMap['areaName']?.toString() ?? '';

    final qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
    final itemRows = <String>[];
    DateTime? earliestCall;
    final linesRaw = slipMap['lines'];
    if (linesRaw is List) {
      for (final item in linesRaw) {
        if (item is! Map) continue;
        final row = Map<String, dynamic>.from(item);
        final name = row['productName']?.toString() ?? '';
        if (name.isEmpty) continue;
        final qtyNum = (row['qty'] as num?)?.toDouble() ??
            double.tryParse('${row['qty']}') ??
            1;
        itemRows.add('${qtyFmt.format(qtyNum)} × $name');
        final c = DateTime.tryParse(row['calledAt']?.toString() ?? '');
        if (c != null && (earliestCall == null || c.isBefore(earliestCall!))) {
          earliestCall = c;
        }
      }
    }
    if (itemRows.isEmpty) {
      final product = slipMap['productName']?.toString() ?? '';
      final qty = slipMap['qty'];
      final qtyNum = qty is num
          ? qty.toDouble()
          : double.tryParse('$qty') ?? 1;
      if (product.isNotEmpty) {
        itemRows.add('${qtyFmt.format(qtyNum)} × $product');
      }
    }
    if (itemRows.isEmpty) return false;

    earliestCall ??= DateTime.tryParse(slipMap['calledAt']?.toString() ?? '');
    final readyAt = DateTime.tryParse(slipMap['readyAt']?.toString() ?? '') ??
        DateTime.now();
    final calledAt = earliestCall ?? readyAt;
    final compiledLines =
        <({String name, String qty, String? unit, String? note})>[];
    if (linesRaw is List) {
      for (final item in linesRaw) {
        if (item is! Map) continue;
        final row = Map<String, dynamic>.from(item);
        final name = row['productName']?.toString() ?? '';
        if (name.isEmpty) continue;
        final qtyNum = (row['qty'] as num?)?.toDouble() ??
            double.tryParse('${row['qty']}') ??
            1;
        compiledLines.add((
          name: name,
          qty: qtyFmt.format(qtyNum),
          unit: row['unitName']?.toString(),
          note: row['note']?.toString(),
        ));
      }
    }
    if (compiledLines.isEmpty) {
      for (final row in itemRows) {
        compiledLines.add((
          name: row.contains(' × ')
              ? row.split(' × ').skip(1).join(' × ')
              : row,
          qty: row.contains(' × ') ? row.split(' × ').first : '1',
          unit: null,
          note: null,
        ));
      }
    }
    final paperSize = PosPrintPaperSizes.fromWidthMm(settings.paperWidthMm);
    final output = PosPrintTemplateRuntime.compileKdsReadySlip(
      paperSize: paperSize,
      printerProfile: PosPrintPrinterProfiles.forPaperAndBrand(
        paperSize: paperSize,
        isSunmi: settings.printerBrand == PosThermalPrinterBrand.sunmi,
        isZywell: settings.printerBrand == PosThermalPrinterBrand.zywell,
      ),
      tableName: table,
      areaName: area,
      orderNo: slipMap['orderNo']?.toString() ?? '',
      calledAt: calledAt,
      readyAt: readyAt,
      lines: compiledLines,
    );
    final printSettings = settings.copyWith(openCashDrawer: false);
    final targetIsSunmi =
        printSettings.connectionType == PosThermalConnectionType.sunmi ||
            printSettings.printerBrand == PosThermalPrinterBrand.sunmi;
    if (targetIsSunmi && await PosPrinterTransport.isSunmiDevice()) {
      return PosPrintTemplateRuntime.printCompiledSunmi(
        output: output,
        settings: printSettings,
        copies: copies.clamp(1, 10),
        kitchenFeed: true,
      );
    }
    final bytes = await PosPrintTemplateRuntime.buildCompiledEscPosBytes(
      output: output,
      settings: printSettings,
    );
    for (var i = 0; i < copies.clamp(1, 10); i++) {
      final sent = await PosPrinterTransport.send(
        connectionType: printSettings.connectionType,
        bluetoothAddress: printSettings.bluetoothAddress,
        lanHost: printSettings.lanHost,
        lanPort: printSettings.lanPort,
        usbDeviceName: printSettings.usbDeviceName,
        bytes: bytes,
        sunmiFeedLines: printSettings.resolvedFeedBeforeCut,
      );
      if (!sent) return false;
    }
    return true;
  }


  /// Gia da gom thue: uu tien flag job; khong co thi doc thiet lap ban hang local.
  Future<bool> _resolveVatIncludedInPrice(bool? fromJob) async {
    if (fromJob != null) return fromJob;
    try {
      final s = await PosSellStoreSettings.load();
      return s.taxMode == PosSellTaxMode.includedInPrice;
    } catch (_) {
      return true;
    }
  }

  /// In hóa đơn / tạm tính / xuất kho theo mẫu thiết kế store (đồng bộ local Sunmi).
  Future<bool> _printSaleOrderWithStoreTemplate({
    required PosSaleOrder order,
    required PosThermalPrinterSettings settings,
    String? storeName,
    String? storeAddress,
    String? storePhone,
    bool mergeSameItems = true,
    String? documentTitle,
    bool warehouseSlip = false,
    List<PosSaleOrderLine>? linesOverride,
    int copies = 1,
    bool? vatIncludedInPrice,
  }) async {
    final docType = warehouseSlip
        ? PosPrintDocumentTypes.stockIssue
        : PosPrintDocumentTypes.saleInvoice;
    final paperSize = PosPrintPaperSizes.fromWidthMm(settings.paperWidthMm);
    final template = await resolvePosPrintTemplate(
      documentType: docType,
      paperSize: paperSize,
    );
    final v2 = PosPrintTemplateRuntime.resolveOrPreset(
      template: template,
      documentType: docType,
      paperSize: paperSize,
      printerProfile: PosPrintPrinterProfiles.forPaperAndBrand(
        paperSize: paperSize,
        isSunmi: true,
        isZywell: settings.printerBrand == PosThermalPrinterBrand.zywell,
      ),
    );

    final output = warehouseSlip
        ? PosPrintTemplateRuntime.compileStockIssue(
            template: v2,
            order: order,
            lines: linesOverride ?? order.lines,
            storeName: storeName,
            storeAddress: storeAddress,
            storePhone: storePhone,
            titleOverride: documentTitle,
          )
        : PosPrintTemplateRuntime.compileSaleOrder(
            template: v2,
            order: order,
            storeName: storeName,
            storeAddress: storeAddress,
            storePhone: storePhone,
            mergeSameItems: mergeSameItems && linesOverride == null,
            titleOverride: documentTitle,
            linesOverride: linesOverride,
            vatIncludedInPrice: await _resolveVatIncludedInPrice(vatIncludedInPrice),
          );

    return PosPrintTemplateRuntime.printCompiledSunmi(
      output: output,
      settings: settings,
      copies: copies.clamp(1, 10),
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
    final tpl = await PosPrintConfigSession.instance.kitchenTemplate(
      isCancel: isCancel,
      force: true,
      paperSize: PosPrintPaperSizes.fromWidthMm(settings.paperWidthMm),
    );
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
    // Chỉ in native Sunmi khi ĐÍCH job là máy Sunmi. Job Zywell LAN/USB
    // không được dump ra máy in trong A6 chỉ vì Agent chạy trên Sunmi.
    final targetIsSunmi =
        settings.connectionType == PosThermalConnectionType.sunmi ||
            settings.printerBrand == PosThermalPrinterBrand.sunmi;
    if (targetIsSunmi && await PosPrinterTransport.isSunmiDevice()) {
      return PosPrintTemplateRuntime.printCompiledSunmi(
        output: output,
        settings: settings,
        copies: copies.clamp(1, 10),
        kitchenFeed: true,
      );
    }
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

  /// Heartbeat chỉ báo printerIds mà máy này thực sự in được (USB gắn / Sunmi / LAN-BT).
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

    // Chip Sunmi: chỉ Online / claim khi đã cài máy in nội bộ trên máy này.
    // Hardware Sunmi chưa cài → nhả job cho Agent máy đã cài (A6 K80).
    if (printer.isSunmi) {
      final sunmiLocal =
          await PosLocalPrintersStore.instance.resolveForStorePrinter(printer, exactPort: true);
      return sunmiLocal != null &&
          PosLocalPrintersStore.profileAllowsDirectLocal(sunmiLocal) &&
          sunmiLocal.connectionType == PosThermalConnectionType.sunmi &&
          await PosPrinterTransport.isSunmiDevice();
    }

    final local =
        await PosLocalPrintersStore.instance.resolveForStorePrinter(printer, exactPort: true);
    final settings = local != null
        ? local.toThermalSettings()
        : toThermalSettings(printer);

    // BT: có địa chỉ → giữ chip. LAN: probe TCP (Zywell/XP mất kết nối → không Online).
    if (settings.connectionType == PosThermalConnectionType.bluetooth) {
      return (settings.bluetoothAddress ?? '').trim().isNotEmpty;
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
