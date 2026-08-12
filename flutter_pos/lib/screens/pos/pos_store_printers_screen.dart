import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/pos_store_printer.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/pos_print_agent_service.dart';
import '../../services/signalr_service.dart';
import '../../utils/pos_print_agent_settings.dart';
import '../../utils/pos_barcode_print.dart';
import '../../utils/pos_label_printer_settings.dart';
import '../../utils/pos_local_printers_store.dart';
import '../../utils/pos_print_orchestrator.dart';
import '../../utils/pos_printer_readiness.dart';
import '../../utils/pos_thermal_printer_service.dart';
import '../../utils/pos_thermal_printer_settings.dart';
import '../../utils/pos_store_printer_mapper.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import 'pos_local_printers_screen.dart';
import 'pos_product_printer_assignment_screen.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Quản lý máy in cửa hàng + routing chứng từ + Print Agent.
class PosStorePrintersScreen extends StatefulWidget {
  const PosStorePrintersScreen({super.key});

  @override
  State<PosStorePrintersScreen> createState() => _PosStorePrintersScreenState();
}

class _PosStorePrintersScreenState extends State<PosStorePrintersScreen> {
  final _api = ApiService();
  List<PosStorePrinter> _printers = [];
  List<PosPrinterRoute> _routes = [];
  PosPrintAgentSettings _agent = const PosPrintAgentSettings();
  bool _loading = true;
  bool _savingRoutes = false;
  bool _agentsLoading = false;
  List<Map<String, String>> _btDevices = [];
  /// Máy in đã cấu hình trên thiết bị này (chọn nhanh cho Agent).
  List<PosLocalPrinterProfile> _localPrinters = [];
  List<_OnlinePrintAgent> _onlineAgents = [];
  bool _multiAgent = false;
  bool _hasPrinterConflict = false;
  bool _agentAssignBusy = false;
  Timer? _agentPoll;
  String? _myDeviceId;
  StreamSubscription<Map<String, dynamic>>? _agentHbSub;
  /// Máy in sẵn sàng trên thiết bị này (USB hiện diện / Sunmi OK / LAN ping…).
  final Set<String> _readyPrinterIds = {};
  /// Máy đã cấu hình nhưng mất cổng / không ping được.
  final Set<String> _lostPrinterIds = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    // Bluetooth scan chậm — không chặn UI.
    if (!kIsWeb) {
      unawaited(PosThermalPrinterService.listBluetoothDevices().then((d) {
        if (mounted) setState(() => _btDevices = d);
      }));
    }
    _agentPoll = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted && !_loading && !_agentsLoading) {
        unawaited(_loadOnlineAgents(silent: true));
      }
    });
    _agentHbSub = SignalRService().onPrintAgentHeartbeat.listen((data) {
      if (!mounted) return;
      unawaited(_onAgentHeartbeatEvent(data));
    });
  }

  Future<void> _onAgentHeartbeatEvent(Map<String, dynamic> data) async {
    final deviceId =
        (data['deviceId'] ?? data['DeviceId'])?.toString() ?? '';
    final forceStop = data['forceStop'] == true || data['ForceStop'] == true;
    final isOnlineFlag =
        data['isOnline'] == true || data['IsOnline'] == true;

    if (forceStop &&
        !isOnlineFlag &&
        deviceId.isNotEmpty &&
        deviceId == _myDeviceId &&
        _agent.enabled) {
      _agent = _agent.copyWith(enabled: false);
      await _agent.save();
      await PosPrintAgentService.instance.stop(markOffline: false);
      if (mounted) {
        setState(() {});
        NotificationOverlayManager().showWarning(
          title: 'Agent đã tắt từ máy khác',
          message: tr('Chỉ giữ Agent trên máy gần máy in'),
        );
      }
    }

    // Cập nhật list ngay từ SignalR — không chờ API / không forceRegister
    // (tránh vòng lặp heartbeat → register → heartbeat làm Agent nghẽn, job hóa đơn «trôi»).
    if (mounted && deviceId.isNotEmpty) {
      _upsertAgentFromHeartbeat(data, online: isOnlineFlag);
    }
  }

  void _upsertAgentFromHeartbeat(
    Map<String, dynamic> data, {
    required bool online,
  }) {
    final deviceId =
        (data['deviceId'] ?? data['DeviceId'])?.toString() ?? '';
    if (deviceId.isEmpty) return;

    final names = <String>[];
    final ids = <String>[];
    final rawIds = data['printerIds'] ?? data['PrinterIds'];
    if (rawIds is List) {
      for (final id in rawIds) {
        final pid = id.toString();
        if (pid.isEmpty) continue;
        ids.add(pid);
        final p = _printers.where((x) => x.id == pid).firstOrNull;
        if (p != null) names.add(p.name);
      }
    }

    final account = (data['employeeName'] ??
            data['EmployeeName'] ??
            data['accountLabel'] ??
            '')
        .toString()
        .trim();

    // Heartbeat online nhưng printerIds rỗng tạm thời → giữ chip cũ (tránh chấm
    // Online nhấp nháy «Chưa có Agent» đến khi reload API).
    final existing = _onlineAgents
        .where((a) => a.deviceId == deviceId)
        .firstOrNull;
    final keepIds = online &&
            ids.isEmpty &&
            existing != null &&
            existing.printerIds.isNotEmpty;
    final effectiveIds = keepIds ? existing!.printerIds : ids;
    final effectiveNames = keepIds
        ? (existing!.printerNames.isNotEmpty
            ? existing.printerNames
            : names)
        : names;

    final agent = _OnlinePrintAgent(
      deviceId: deviceId,
      deviceName: (data['deviceName'] ?? data['DeviceName'])?.toString() ?? '',
      accountDisplay: account.isNotEmpty ? account : 'Agent',
      printerNames: effectiveNames,
      printerIds: effectiveIds,
      isOnline: online,
      lastHeartbeatAt: DateTime.now().toUtc(),
    );

    setState(() {
      final next = List<_OnlinePrintAgent>.from(_onlineAgents);
      final idx = next.indexWhere((a) => a.deviceId == deviceId);
      if (!online) {
        if (idx >= 0) next.removeAt(idx);
      } else if (idx >= 0) {
        next[idx] = agent;
      } else {
        next.insert(0, agent);
      }
      _onlineAgents = next;
      _multiAgent = next.length > 1;
    });
  }

  /// Máy cloud / Agent — chỉ hiện khi có Agent đang nhận (kể cả LAN/WiFi).
  List<PosStorePrinter> get _cloudAgentPrinters => _printers.where((p) {
        if (!p.isCloudAgentPrinter) return false;
        final covered = _onlineAgents.any((a) => a.coversPrinter(p.id));
        final mine =
            _agent.enabled && _agent.assignedPrinterIds.contains(p.id);
        return covered || mine;
      }).toList();

  /// Chỉ máy đang bật Print Agent mới được thêm/sửa/xóa máy in cloud cửa hàng.
  bool get _canManageCloudPrinters => _agent.enabled;

  bool _agentCoversPrinter(String printerId) =>
      _onlineAgents.any((a) => a.coversPrinter(printerId));

  String? _agentNameForPrinter(String printerId) {
    for (final a in _onlineAgents) {
      if (a.coversPrinter(printerId)) return a.displayTitle;
    }
    return null;
  }

  @override
  void dispose() {
    _agentPoll?.cancel();
    _agentHbSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _agent = await PosPrintAgentSettings.load()
          .timeout(const Duration(seconds: 3), onTimeout: () => _agent);
      _myDeviceId = await PosPrintOrchestrator.stableDeviceId()
          .timeout(const Duration(seconds: 3), onTimeout: () => _myDeviceId ?? '');
      if (_myDeviceId != null && _myDeviceId!.isEmpty) _myDeviceId = null;

      try {
        _localPrinters = await PosLocalPrintersStore.instance.loadAll();
      } catch (_) {
        _localPrinters = [];
      }

      final results = await Future.wait([
        _api.getPosStorePrinters(),
        _api.getPosPrinterRoutes(),
      ]).timeout(
        const Duration(seconds: 12),
        onTimeout: () => <Map<String, dynamic>>[
          {'isSuccess': false, 'message': 'Hết thời gian tải máy in'},
          {'isSuccess': false},
        ],
      );
      if (!mounted) return;
      final pr = results[0];
      final rt = results[1];

      if (pr['isSuccess'] == true) {
        final raw = pr['data'];
        final list = raw is List
            ? raw
            : (raw is Map && raw['items'] is List
                ? raw['items'] as List
                : const []);
        _printers = list
            .whereType<Map>()
            .map((e) => PosStorePrinter.fromJson(Map<String, dynamic>.from(e)))
            .where((p) => p.id.isNotEmpty)
            .toList();
      }
      if (_printers.isEmpty &&
          PosPrintOrchestrator.instance.printers.isNotEmpty) {
        _printers = List.from(PosPrintOrchestrator.instance.printers);
      }
      if (pr['isSuccess'] != true && _printers.isEmpty && mounted) {
        NotificationOverlayManager().showWarning(
          title: 'Không tải danh sách máy in',
          message: pr['message']?.toString() ?? 'Kéo xuống để thử lại',
        );
      }

      if (rt['isSuccess'] == true && rt['data'] is List) {
        _routes = (rt['data'] as List)
            .whereType<Map>()
            .map((e) => PosPrinterRoute.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (e) {
      debugPrint('PosStorePrintersScreen._load: $e');
      if (mounted) {
        NotificationOverlayManager().showError(
          title: 'Lỗi tải máy in',
          message: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
      if (mounted) {
        await _loadOnlineAgents(silent: true);
        unawaited(_purgeOrphanLocalCloudClones());
      }
      unawaited(PosPrintOrchestrator.instance.refreshConfig(force: true));
      unawaited(_refreshPrinterReadiness());
    }
  }

  Future<void> _linkLocalToStorePrinter(
    PosLocalPrinterProfile local,
    String storePrinterId,
  ) async {
    if (storePrinterId.isEmpty) return;
    if (local.storePrinterId == storePrinterId) return;
    final next = await PosLocalPrintersStore.instance.upsert(
      local.copyWith(storePrinterId: storePrinterId),
      syncServer: false,
    );
    final i = _localPrinters.indexWhere((p) => p.id == local.id);
    if (i >= 0) {
      _localPrinters[i] = next;
    }
  }

  /// Xóa máy cloud clone trùng máy nội bộ nhưng không còn được Agent nhận.
  Future<void> _purgeOrphanLocalCloudClones() async {
    if (_localPrinters.isEmpty || _printers.isEmpty) return;
    final assigned = _agent.assignedPrinterIds.toSet();
    final covered = <String>{};
    for (final a in _onlineAgents) {
      covered.addAll(a.printerIds);
    }
    final removeIds = <String>[];
    for (final p in _printers) {
      if (!p.isCloudAgentPrinter) continue;
      if (assigned.contains(p.id) || covered.contains(p.id)) continue;
      final matchLocal = _localPrinters.any((l) => _sameLocalConnection(p, l));
      if (!matchLocal) continue;
      removeIds.add(p.id);
    }
    if (removeIds.isEmpty) return;
    for (final id in removeIds) {
      try {
        await _api.deletePosStorePrinter(id);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _printers = _printers.where((p) => !removeIds.contains(p.id)).toList();
    });
  }

  /// Chỉ probe/report máy gán Agent trên thiết bị này — A7 thu ngân không
  /// được ghi Offline nhầm cho máy USB đang gắn ở A6.
  Future<void> _refreshPrinterReadiness() async {
    if (kIsWeb || !mounted) return;
    final targets = _printers
        .where((p) =>
            !p.isDeviceLocal &&
            _agent.enabled &&
            _agent.assignedPrinterIds.contains(p.id))
        .toList();
    if (targets.isEmpty) {
      if (mounted &&
          (_readyPrinterIds.isNotEmpty || _lostPrinterIds.isNotEmpty)) {
        setState(() {
          _readyPrinterIds.clear();
          _lostPrinterIds.clear();
        });
      }
      return;
    }

    final usbList = await PosPrinterReadiness.listUsbDevices();
    final ready = <String>{};
    final lost = <String>{};
    for (final p in targets) {
      final local =
          await PosLocalPrintersStore.instance.resolveForStorePrinter(p);
      final ok = p.isLabelPrinter
          ? await PosPrinterReadiness.probePort(
              connectionType: (local?.toLabelSettings() ?? toLabelSettings(p))
                  .connectionType,
              usbDeviceName:
                  (local?.toLabelSettings() ?? toLabelSettings(p)).usbDeviceName,
              lanHost: (local?.toLabelSettings() ?? toLabelSettings(p)).lanHost,
              lanPort: (local?.toLabelSettings() ?? toLabelSettings(p)).lanPort,
              bluetoothAddress: (local?.toLabelSettings() ?? toLabelSettings(p))
                  .bluetoothAddress,
              usbList: usbList,
            )
          : await PosPrinterReadiness.probePort(
              connectionType:
                  (local?.toThermalSettings() ?? toThermalSettings(p))
                      .connectionType,
              usbDeviceName:
                  (local?.toThermalSettings() ?? toThermalSettings(p))
                      .usbDeviceName,
              lanHost:
                  (local?.toThermalSettings() ?? toThermalSettings(p)).lanHost,
              lanPort:
                  (local?.toThermalSettings() ?? toThermalSettings(p)).lanPort,
              bluetoothAddress:
                  (local?.toThermalSettings() ?? toThermalSettings(p))
                      .bluetoothAddress,
              usbList: usbList,
            );
      if (ok) {
        ready.add(p.id);
        unawaited(_api.reportPosPrinterHealth(p.id, status: 'Online'));
      } else {
        lost.add(p.id);
        unawaited(_api.reportPosPrinterHealth(
          p.id,
          status: 'Offline',
          errorMessage: 'Mất kết nối nội bộ trên máy Agent',
        ));
      }
    }
    if (!mounted) return;
    setState(() {
      _readyPrinterIds
        ..clear()
        ..addAll(ready);
      _lostPrinterIds
        ..clear()
        ..addAll(lost);
    });
  }

  Future<void> _loadOnlineAgents({bool silent = false}) async {
    if (_agentsLoading) return;
    _agentsLoading = true;
    try {
      // Chỉ đăng ký lại khi user bấm tải lại (không silent) — silent poll/heartbeat
      // không được gọi forceRegister (gây bão heartbeat, claim/in hóa đơn bị nghẽn).
      if (!silent &&
          _agent.enabled &&
          PosPrintAgentService.instance.isRunning) {
        await PosPrintAgentService.instance
            .forceRegister(refreshPrinters: false);
      }

      // Lấy tất cả rồi lọc — tránh onlineOnly rỗng do timezone server cũ.
      final res = await _api
          .getPosPrintAgents(onlineOnly: false, staleSeconds: 240)
          .timeout(
        const Duration(seconds: 8),
        onTimeout: () => {
          'isSuccess': false,
          'message': 'Hết thời gian tải Agent',
        },
      );
      if (!mounted) return;

      List<_OnlinePrintAgent> parseAgents(Map data) {
        final raw = data['agents'] ?? data['Agents'];
        return (raw is List ? raw : const [])
            .whereType<Map>()
            .map((e) => _OnlinePrintAgent.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }

      bool isFresh(_OnlinePrintAgent a) {
        if (a.isOnline) return true;
        final hb = a.lastHeartbeatAt;
        if (hb == null) return false;
        return DateTime.now().toUtc().difference(hb.toUtc()).inSeconds.abs() <
            240;
      }

      if (res['isSuccess'] != true || res['data'] is! Map) {
        if (!silent) {
          NotificationOverlayManager().showWarning(
            title: 'Không tải được Agent',
            message: res['message']?.toString() ?? 'Thử lại',
          );
        }
        return; // giữ list SignalR
      }

      final data = res['data'] as Map;
      final list = parseAgents(data).where(isFresh).toList();

      // Ưu tiên SignalR (chip/tươi) khi API trả agent online nhưng printerIds trống.
      final merged = <String, _OnlinePrintAgent>{};
      for (final a in list) {
        merged[a.deviceId] = a;
      }
      for (final a in _onlineAgents) {
        if (!a.isOnline) continue;
        final cur = merged[a.deviceId];
        if (cur == null) {
          merged[a.deviceId] = a;
        } else if (cur.printerIds.isEmpty && a.printerIds.isNotEmpty) {
          merged[a.deviceId] = _OnlinePrintAgent(
            deviceId: cur.deviceId,
            deviceName: cur.deviceName.isNotEmpty ? cur.deviceName : a.deviceName,
            accountDisplay: cur.accountDisplay.isNotEmpty
                ? cur.accountDisplay
                : a.accountDisplay,
            printerNames: a.printerNames,
            printerIds: a.printerIds,
            isOnline: true,
            lastHeartbeatAt: cur.lastHeartbeatAt ?? a.lastHeartbeatAt,
          );
        }
      }

      if (_agent.enabled &&
          PosPrintAgentService.instance.isRunning &&
          PosPrintAgentService.instance.isRegistered &&
          (_myDeviceId ?? '').isNotEmpty &&
          !merged.containsKey(_myDeviceId)) {
        final names = _printers
            .where((p) => _agent.assignedPrinterIds.contains(p.id))
            .map((p) => p.name)
            .toList();
        merged[_myDeviceId!] = _OnlinePrintAgent(
          deviceId: _myDeviceId!,
          deviceName: 'Máy này',
          accountDisplay: _accountLabelForHeartbeat().isNotEmpty
              ? _accountLabelForHeartbeat()
              : 'Agent local',
          printerNames: names,
          printerIds: List<String>.from(_agent.assignedPrinterIds),
          isOnline: true,
          lastHeartbeatAt: DateTime.now().toUtc(),
        );
      }

      // deviceId heartbeat có thể khác _myDeviceId (android.id ngắn) — vẫn giữ.
      if (!mounted) return;
      setState(() {
        _onlineAgents = merged.values.toList();
        _multiAgent = _onlineAgents.length > 1;
        _hasPrinterConflict = data['hasPrinterConflict'] == true;
      });
    } catch (e) {
      debugPrint('PosStorePrintersScreen._loadOnlineAgents: $e');
    } finally {
      _agentsLoading = false;
    }
  }

  /// Tắt Agent trên máy khác (cùng cửa hàng) — không cần cầm máy đó.
  Future<void> _forceOfflineAgent(_OnlinePrintAgent a) async {
    if (a.deviceId.isEmpty || a.deviceId == _myDeviceId) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Tắt Agent máy kia?')),
        content: Text(tr('${tr('Tắt nhận lệnh in trên «')}${a.deviceName.isNotEmpty ? a.deviceName : 'Máy POS'}».\n'
          'Chỉ giữ Agent trên máy gần máy in (Sunmi).'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Hủy')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Tắt')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.markPosPrintAgentOffline(deviceId: a.deviceId);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã tắt Agent máy kia',
        message: a.deviceName.isNotEmpty ? a.deviceName : a.accountDisplay,
      );
      await _loadOnlineAgents(silent: true);
    } else {
      NotificationOverlayManager().showError(
        title: 'Không tắt được',
        message: res['message']?.toString() ?? 'Thử lại',
      );
    }
  }

  String _accountLabelForHeartbeat() {
    final u = Provider.of<AuthProvider>(context, listen: false).user;
    final parts = <String>[
      if ((u?.fullName ?? '').trim().isNotEmpty) u!.fullName.trim(),
      if ((u?.email ?? '').trim().isNotEmpty) u!.email.trim(),
    ];
    return parts.join(' · ');
  }

  String _printersForDoc(String docType) {
    final ids = _routes
        .where((x) => x.documentType == docType)
        .map((x) => x.printerId)
        .toList();
    if (ids.isEmpty) {
      if (_printers.length == 1) return _printers.first.name;
      final def = _printers.where((p) => p.isDefault).firstOrNull;
      return def?.name ?? '—';
    }
    return ids
        .map((id) => _printers.where((p) => p.id == id).firstOrNull?.name)
        .whereType<String>()
        .join(', ');
  }

  void _toggleRoute(String docType, String printerId, bool selected) {
    if (selected) {
      final exists = _routes.any(
          (r) => r.documentType == docType && r.printerId == printerId);
      if (!exists) {
        _routes.add(PosPrinterRoute(
          documentType: docType,
          printerId: printerId,
          defaultCopies: 1,
        ));
      }
    } else {
      _routes.removeWhere(
          (r) => r.documentType == docType && r.printerId == printerId);
    }
    setState(() {});
  }

  Future<void> _toggleAgent(bool v) async {
    final agentPrinters = _printers.where((p) => p.needsPrintAgent).toList();
    if (v) {
      if (agentPrinters.isEmpty &&
          _localPrinters.where((p) => p.enabled).isEmpty) {
        NotificationOverlayManager().showWarning(
          title: 'Chưa có máy in cloud',
          message: tr('Thêm máy in trên thiết bị (Máy in nội bộ) rồi chọn chip Agent'),
        );
      }

      await _loadOnlineAgents(silent: true);
      if (!mounted) return;
      final others = _onlineAgents
          .where((a) => a.deviceId != _myDeviceId && a.isOnline)
          .toList();
      if (others.isNotEmpty) {
        final lines = others
            .map((a) =>
                '• ${a.deviceName.isNotEmpty ? a.deviceName : 'Máy'} — ${a.accountDisplay}')
            .join('\n');
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('Đã có máy khác bật Agent')),
            content: Text(
              tr('Nên chỉ 1 máy nhận lệnh in.\n\n'
              'Đang bật:\n$lines\n\n'
              'Vẫn bật Agent trên máy này?'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Hủy')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('Vẫn bật')),
              ),
            ],
          ),
        );
        if (!mounted || ok != true) return;
      }

      final label = _accountLabelForHeartbeat();
      // Không tự gán chip khi bật Agent — user chọn chip thủ công.
      // (Trước đây empty → match hết máy local / cửa hàng → danh sách «nhảy» lại 6 máy.)
      _agent = _agent.copyWith(enabled: true, accountLabel: label);
    } else {
      _agent = _agent.copyWith(enabled: false);
    }
    await _agent.save();
    if (!mounted) return;
    setState(() {});
    final storeId =
        Provider.of<AuthProvider>(context, listen: false).user?.storeId;
    if (v && storeId != null && storeId.isNotEmpty) {
      await PosPrintAgentService.instance.ensureRunning(storeId);
      NotificationOverlayManager().showSuccess(
        title: 'Print Agent bật',
        message: tr('Giữ app mở — nhận lệnh in cloud (LAN/BT/USB)'),
      );
      await _loadOnlineAgents(silent: true);
    } else if (!v) {
      await PosPrintAgentService.instance.stop();
      await _loadOnlineAgents(silent: true);
    }
  }

  Future<void> _saveRoutes() async {
    setState(() => _savingRoutes = true);
    try {
      final body = _routes.map((r) => r.toJson()).toList();
      final res = await _api.savePosPrinterRoutes(body);
      if (res['isSuccess'] == true) {
        NotificationOverlayManager().showSuccess(
          title: 'Đã lưu phân loại',
          message: tr('Gán máy in theo chứng từ đã lưu lên máy chủ'),
        );
        await PosPrintOrchestrator.instance.invalidateCache();
      } else {
        NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: res['message']?.toString() ?? 'Không lưu được',
        );
      }
    } finally {
      if (mounted) setState(() => _savingRoutes = false);
    }
  }

  Future<void> _openEditor([PosStorePrinter? existing]) async {
    final saved = await showModalBottomSheet<PosStorePrinter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _PrinterEditorSheet(
        existing: existing,
        btDevices: _btDevices,
        onRefreshBluetooth: () async {
          final list = await PosThermalPrinterService.listBluetoothDevices();
          if (mounted) setState(() => _btDevices = list);
          return list;
        },
      ),
    );
    if (saved != null) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Máy in cửa hàng')),
        backgroundColor: PosTheme.kiotBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: tr('Máy in nội bộ'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PosLocalPrintersScreen(),
                ),
              ).then((_) => _load());
            },
            icon: const Icon(Icons.phone_android),
          ),
          IconButton(
            tooltip: tr('Gán sản phẩm cho máy in'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PosProductPrinterAssignmentScreen(
                    printers: _printers,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.restaurant_menu_outlined),
          ),
          IconButton(
            tooltip: tr('Lưu phân loại chứng từ'),
            onPressed: _loading || _savingRoutes ? null : _saveRoutes,
            icon: _savingRoutes
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                // Chừa chỗ FAB «Thêm máy in» — tránh che nút «Lưu phân loại».
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                children: [
                  Card(
                    color: const Color(0xFFFFF7ED),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        tr('Máy in cửa hàng = Print Agent / máy dùng chung cửa hàng.\n'
                            'Máy in nhiệt & tem gắn trực tiếp máy POS này → nút «Máy in nội bộ» (biểu tượng điện thoại).'),
                        style: const TextStyle(fontSize: 12.5, height: 1.35),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _agentCard(),
                  const SizedBox(height: 12),
                  _printersSection(),
                  const SizedBox(height: 12),
                  if (_printers.isNotEmpty) ...[
                    _productPrinterCard(),
                    const SizedBox(height: 12),
                  ],
                  _routesSection(),
                ],
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _canManageCloudPrinters
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              backgroundColor: PosTheme.kiotBlue,
              icon: const Icon(Icons.add),
              label: Text(tr('Thêm máy in')),
            )
          : null,
    );
  }

  String _localApiConnection(PosThermalConnectionType t) => switch (t) {
        PosThermalConnectionType.bluetooth => 'Bluetooth',
        PosThermalConnectionType.lan => 'Lan',
        PosThermalConnectionType.usb => 'Usb',
        PosThermalConnectionType.sunmi => 'Sunmi',
      };

  bool _sameLocalConnection(PosStorePrinter p, PosLocalPrinterProfile local) {
    final conn = _localApiConnection(local.connectionType);
    if (p.connectionType != conn) return false;
    switch (conn) {
      case 'Lan':
        return (p.lanHost ?? '').trim() == (local.lanHost ?? '').trim();
      case 'Bluetooth':
        return (p.bluetoothAddress ?? '').toLowerCase() ==
            (local.bluetoothAddress ?? '').toLowerCase();
      case 'Usb':
        return (p.usbDeviceName ?? '').trim() ==
            (local.usbDeviceName ?? '').trim();
      case 'Sunmi':
        return true;
      default:
        return p.name.trim() == local.name.trim();
    }
  }

  PosStorePrinter? _findAgentPrinterForLocal(PosLocalPrinterProfile local) {
    for (final p in _printers) {
      if (p.isDeviceLocal) continue;
      if (_sameLocalConnection(p, local)) return p;
    }
    return null;
  }

  bool _isLocalAssignedToAgent(PosLocalPrinterProfile local) {
    final match = _findAgentPrinterForLocal(local);
    if (match == null) return false;
    return _agent.assignedPrinterIds.contains(match.id);
  }

  Future<String?> _ensureCloudPrinterFromLocal(PosLocalPrinterProfile local) async {
    final existing = _findAgentPrinterForLocal(local);
    if (existing != null) {
      // Giữ storePrinterId device-local (gán món) — không ghi đè bằng id cloud Agent.
      if ((local.storePrinterId ?? '').trim().isEmpty) {
        await _linkLocalToStorePrinter(local, existing.id);
      }
      return existing.id;
    }

    final conn = _localApiConnection(local.connectionType);
    final body = <String, dynamic>{
      'name': local.name.trim().isEmpty ? 'Máy in Agent' : local.name.trim(),
      'connectionType': conn,
      'printerBrand': local.isLabel ? 'label' : local.printerBrand.key,
      'paperSize': local.isLabel ? local.labelTemplateId : local.paperSize,
      'textMode': local.isLabel ? local.labelProtocol.key : local.textMode.key,
      'bluetoothAddress':
          conn == 'Bluetooth' ? local.bluetoothAddress : null,
      'bluetoothName': conn == 'Bluetooth' ? local.bluetoothName : null,
      'lanHost': conn == 'Lan' && (local.lanHost ?? '').trim().isNotEmpty
          ? local.lanHost!.trim()
          : null,
      'lanPort': local.lanPort,
      'usbDeviceName':
          conn == 'Usb' && (local.usbDeviceName ?? '').trim().isNotEmpty
              ? local.usbDeviceName!.trim()
              : null,
      'feedBeforeCut': local.isLabel
          ? local.labelGapMm.round().clamp(1, 10)
          : local.feedBeforeCut,
      'partialCut': !local.isLabel && local.partialCut,
      'openCashDrawer': !local.isLabel && local.openCashDrawer,
      'openDrawerCashOnly': local.openDrawerCashOnly,
      'beepOnPrint': !local.isLabel && local.beepOnPrint,
      'isDefault': false,
      'sortOrder': 0,
      'isActive': true,
    };
    final res = await _api.createPosStorePrinter(body);
    if (res['isSuccess'] == true && res['data'] is Map) {
      final created = PosStorePrinter.fromJson(
        Map<String, dynamic>.from(res['data'] as Map),
      );
      if (created.id.isNotEmpty) {
        setState(() {
          _printers = [..._printers, created];
        });
        if ((local.storePrinterId ?? '').trim().isEmpty) {
          await _linkLocalToStorePrinter(local, created.id);
        }
        return created.id;
      }
    }
    if (mounted) {
      NotificationOverlayManager().showError(
        title: 'Không tạo máy in Agent',
        message: res['message']?.toString() ?? local.name,
      );
    }
    return null;
  }

  Future<void> _toggleLocalAsAgent(
    PosLocalPrinterProfile local,
    bool selected,
  ) async {
    setState(() => _agentAssignBusy = true);
    try {
      var ids = List<String>.from(_agent.assignedPrinterIds);
      if (selected) {
        final storeId = await _ensureCloudPrinterFromLocal(local);
        if (storeId == null || storeId.isEmpty) return;
        if (!ids.contains(storeId)) ids.add(storeId);
      } else {
        // Gỡ chip + xóa bản cloud clone (tránh A7 vẫn thấy đủ list máy nội bộ A6).
        final removeIds = <String>[];
        for (final p in _printers) {
          if (p.isDeviceLocal || !p.requiresAgent) continue;
          if (_sameLocalConnection(p, local)) {
            ids.remove(p.id);
            removeIds.add(p.id);
          }
        }
        for (final id in removeIds) {
          try {
            await _api.deletePosStorePrinter(id);
          } catch (_) {}
        }
        if (removeIds.isNotEmpty && mounted) {
          setState(() {
            _printers =
                _printers.where((p) => !removeIds.contains(p.id)).toList();
          });
        }
      }
      _agent = _agent.copyWith(
        assignedPrinterIds: ids,
        accountLabel: _accountLabelForHeartbeat(),
      );
      await _agent.save();
      if (mounted) setState(() {});
      final storeId =
          Provider.of<AuthProvider>(context, listen: false).user?.storeId;
      if (_agent.enabled && storeId != null && storeId.isNotEmpty) {
        await PosPrintAgentService.instance
            .ensureRunning(storeId, forceReregister: true);
        await _loadOnlineAgents(silent: true);
      }
      unawaited(_refreshPrinterReadiness());
    } finally {
      if (mounted) setState(() => _agentAssignBusy = false);
    }
  }

  Widget _agentCard() {
    // Chỉ hiện máy đã gán cho Agent này — không liệt kê cả cửa hàng.
    final agentPrinters = _printers
        .where((p) => _agent.assignedPrinterIds.contains(p.id))
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.hub_outlined, color: PosTheme.kiotBlue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr('Máy nhận lệnh in (Agent)'),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Switch(
                  value: _agent.enabled,
                  onChanged: _toggleAgent,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F7FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Text(
                tr('Cách dùng đơn giản (1 máy in + nhiều điện thoại):\n'
                '1) Thêm máy in trên thiết bị (Máy in nội bộ) hoặc «Thêm máy in» LAN/BT.\n'
                '2) Ở đây chọn chip máy in (có icon mây) — không cần nhập lại IP/MAC.\n'
                '3) Chỉ 1 máy gần máy in: bật công tắc Agent + giữ app mở.\n'
                '4) Máy thu ngân khác: tắt Agent — in qua máy chủ.'),
                style: TextStyle(fontSize: 12, height: 1.35, color: PosTheme.kiotBlue),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr(_agent.enabled
                  ? 'Máy này đang nhận lệnh in cho chip đã chọn'
                  : 'Tắt trên máy thu ngân — chỉ bật trên 1 máy gần máy in'),
              style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
            ),
            if (_localPrinters.where((p) => p.enabled).isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                tr('Chọn nhanh từ máy in trên thiết bị này'),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final local in _localPrinters.where((p) => p.enabled))
                    FilterChip(
                      avatar: Icon(
                        Icons.cloud_outlined,
                        size: 16,
                        color: _isLocalAssignedToAgent(local)
                            ? Colors.white
                            : const Color(0xFF0284C7),
                      ),
                      label: Text(
                        tr(local.name),
                        style: TextStyle(
                          fontSize: 11,
                          color: _isLocalAssignedToAgent(local)
                              ? Colors.white
                              : const Color(0xFF0C4A6E),
                        ),
                      ),
                      selected: _isLocalAssignedToAgent(local),
                      selectedColor: const Color(0xFF0284C7),
                      checkmarkColor: Colors.white,
                      backgroundColor: const Color(0xFFE0F2FE),
                      side: const BorderSide(color: Color(0xFF7DD3FC)),
                      onSelected: _agentAssignBusy
                          ? null
                          : (v) => unawaited(_toggleLocalAsAgent(local, v)),
                    ),
                ],
              ),
            ] else if (agentPrinters.isEmpty &&
                _localPrinters.where((p) => p.enabled).isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  tr('Chưa có máy in trên thiết bị — mở «Máy in nội bộ» để thêm, rồi chọn chip bên trên'),
                  style: const TextStyle(fontSize: 11, color: Colors.orange),
                ),
              ),
            if (agentPrinters.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                tr('Máy in Agent đang nhận lệnh'),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: agentPrinters.map((p) {
                  return FilterChip(
                    avatar: const Icon(
                      Icons.cloud_outlined,
                      size: 16,
                      color: Colors.white,
                    ),
                    label: Text(
                      tr(p.name),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                      ),
                    ),
                    selected: true,
                    selectedColor: const Color(0xFF0284C7),
                    checkmarkColor: Colors.white,
                    backgroundColor: const Color(0xFFE0F2FE),
                    side: const BorderSide(color: Color(0xFF7DD3FC)),
                    onSelected: (v) async {
                      if (v) return;
                      var ids = List<String>.from(_agent.assignedPrinterIds)
                        ..remove(p.id);
                      _agent = _agent.copyWith(
                        assignedPrinterIds: ids,
                        accountLabel: _accountLabelForHeartbeat(),
                      );
                      await _agent.save();
                      setState(() {});
                      final storeId =
                          Provider.of<AuthProvider>(context, listen: false)
                              .user
                              ?.storeId;
                      if (_agent.enabled &&
                          storeId != null &&
                          storeId.isNotEmpty) {
                        await PosPrintAgentService.instance
                            .ensureRunning(storeId, forceReregister: true);
                        await _loadOnlineAgents(silent: true);
                      }
                    },
                  );
                }).toList(),
              ),
            ],
            if (_agent.enabled && _agent.assignedPrinterIds.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(tr('⚠ Chưa chọn chip máy in — Agent không nhận được lệnh từ Oppo'),
                  style: TextStyle(color: Colors.orange, fontSize: 12),
                ),
              ),
            if (_agent.enabled &&
                _agent.assignedPrinterIds.isNotEmpty &&
                PosPrintAgentService.instance.isRunning &&
                !PosPrintAgentService.instance.isRegistered)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  tr('⚠ Agent chưa đăng ký server'
                  '${PosPrintAgentService.instance.lastRegisterError != null ? ': ${PosPrintAgentService.instance.lastRegisterError}' : ''}'),
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            if (_agent.enabled &&
                _agent.assignedPrinterIds.isNotEmpty &&
                PosPrintAgentService.instance.isRunning &&
                PosPrintAgentService.instance.isRegistered)
              Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(tr('● Agent đang chạy — sẵn sàng nhận lệnh in'),
                  style: TextStyle(color: Colors.green, fontSize: 12),
                ),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(tr('Agent đang online trên cửa hàng'),
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                IconButton(
                  tooltip: tr('Tải lại'),
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: () => unawaited(_loadOnlineAgents()),
                ),
              ],
            ),
            if (_multiAgent || _hasPrinterConflict)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFDBA74)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(_hasPrinterConflict
                          ? 'Cảnh báo: cùng máy in đang được ≥2 máy Agent nhận — dễ tranh lệnh / in trùng. Chỉ giữ 1 máy Agent.'
                          : 'Cảnh báo: đang có ${_onlineAgents.length} máy bật Agent. Nên chỉ bật trên máy gần máy in (Sunmi).'),
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: Color(0xFF9A3412),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_onlineAgents.any((a) => a.deviceId != _myDeviceId)) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () async {
                            final others = _onlineAgents
                                .where((a) => a.deviceId != _myDeviceId)
                                .toList();
                            for (final a in others) {
                              await _api.markPosPrintAgentOffline(
                                  deviceId: a.deviceId);
                            }
                            if (!mounted) return;
                            NotificationOverlayManager().showSuccess(
                              title: 'Đã gửi lệnh tắt Agent máy khác',
                              message: tr('Đợi vài giây rồi kéo refresh'),
                            );
                            await _loadOnlineAgents(silent: true);
                          },
                          icon: const Icon(Icons.power_settings_new, size: 16),
                          label: Text(tr('Tắt Agent các máy khác')),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF9A3412),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            if (_onlineAgents.isEmpty)
              Text(tr('Chưa có máy nào đang nhận lệnh in (Agent offline).'),
                style: TextStyle(fontSize: 12, color: PosTheme.textSecondary),
              )
            else
              ..._onlineAgents.map((a) {
                final mine = a.deviceId == _myDeviceId;
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: mine
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: mine
                          ? const Color(0xFF86EFAC)
                          : const Color(0xFFE5E7EB),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.smartphone,
                            size: 16,
                            color: mine
                                ? const Color(0xFF166534)
                                : PosTheme.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              tr(a.displayTitle),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: mine
                                    ? const Color(0xFF166534)
                                    : Colors.black87,
                              ),
                            ),
                          ),
                          if (mine)
                            Text(tr('Máy này'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF166534),
                              ),
                            )
                          else
                            TextButton(
                              onPressed: () => unawaited(_forceOfflineAgent(a)),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 28),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(tr('Tắt'),
                                  style: TextStyle(fontSize: 12)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(tr('Tài khoản: ${a.accountDisplay}'),
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (a.printerNames.isNotEmpty)
                        Text(
                          tr('Máy in: ${a.printerNames.join(', ')}'),
                          style: const TextStyle(
                            fontSize: 11,
                            color: PosTheme.textSecondary,
                          ),
                        ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _printersSection() {
    // Toàn bộ máy cloud cửa hàng — A7 thu ngân phải thấy để test/in qua Agent.
    final cloud = _cloudAgentPrinters;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Danh sách máy in cloud / Agent'),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              tr('Máy thu ngân (A7): xem Online khi Agent (A6) đang nhận chip đó. '
                  'In thử dùng «Test qua cloud».'),
              style: TextStyle(fontSize: 11, color: PosTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            if (cloud.isEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr('Chưa có máy in cloud. Trên máy Agent: chọn chip từ Máy in nội bộ, hoặc Thêm máy in LAN/BT.'),
                    style: TextStyle(color: PosTheme.textSecondary),
                  ),
                  TextButton.icon(
                    onPressed: () => unawaited(_load()),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(tr('Tải lại danh sách')),
                  ),
                ],
              ),
            ...cloud.map(_printerTile),
          ],
        ),
      ),
    );
  }

  IconData _connectionIcon(PosStorePrinter p) {
    if (p.isLabelPrinter) return Icons.label_outline;
    if (p.isSunmi) return Icons.point_of_sale_outlined;
    if (p.isLan) return Icons.wifi;
    if (p.isUsb) return Icons.usb;
    return Icons.bluetooth;
  }

  Widget _printerTile(PosStorePrinter p) {
    final locallyReady = _readyPrinterIds.contains(p.id);
    final locallyLost = _lostPrinterIds.contains(p.id);
    final viaAgent = _agentCoversPrinter(p.id);
    final agentTitle = _agentNameForPrinter(p.id);
    final mine =
        _agent.enabled && _agent.assignedPrinterIds.contains(p.id);
    final ready = locallyReady || viaAgent;
    final statusColor = ready
        ? Colors.green
        : (locallyLost || p.healthStatus == 'Offline')
            ? Colors.red
            : Colors.grey;
    final statusText = locallyReady
        ? 'Sẵn sàng · nội bộ'
        : viaAgent
            ? 'Online · Agent${agentTitle != null ? ' ($agentTitle)' : ''}'
            : (locallyLost || p.healthStatus == 'Offline'
                ? 'Mất kết nối'
                : 'Chưa có Agent');
    final isAgentCloud = !p.isDeviceLocal;
    final kind = p.isDeviceLocal
        ? 'Nội bộ'
        : (p.isLabelPrinter ? 'Tem nhãn · Agent' : 'Agent / cloud');
    final avatarBg = ready
        ? const Color(0xFFDCFCE7)
        : (locallyLost
            ? const Color(0xFFFEE2E2)
            : (isAgentCloud ? const Color(0xFFE0F2FE) : PosTheme.kiotBlueLight));
    final avatarFg = ready
        ? const Color(0xFF15803D)
        : (locallyLost
            ? const Color(0xFFB91C1C)
            : (isAgentCloud ? const Color(0xFF0284C7) : PosTheme.kiotBlue));
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: avatarBg,
        child: Icon(
          p.isDeviceLocal
              ? Icons.phone_android
              : (isAgentCloud ? Icons.cloud_outlined : _connectionIcon(p)),
          color: avatarFg,
          size: 20,
        ),
      ),
      title: Text(
        tr(mine ? '${p.name} · máy này' : p.name),
        style: TextStyle(
          color: isAgentCloud ? const Color(0xFF0C4A6E) : null,
          fontWeight: isAgentCloud ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      subtitle: Text(
        tr('$kind · ${p.connectionType} · $statusText'),
        style: TextStyle(
          fontSize: 11,
          color: ready
              ? const Color(0xFF15803D)
              : (isAgentCloud ? const Color(0xFF0369A1) : null),
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isAgentCloud)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.cloud_queue, size: 16, color: Color(0xFF0284C7)),
            ),
          Tooltip(
            message: statusText,
            child: Icon(Icons.circle, size: 10, color: statusColor),
          ),
          PopupMenuButton<String>(
            onSelected: (a) async {
              if (a == 'edit') {
                await _openEditor(p);
              } else if (a == 'products') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PosPrinterManageProductsScreen(
                      printerId: p.id,
                      printerName: p.name,
                      isLabel: p.isLabelPrinter,
                      purpose: purposeFromFlags(
                        isLabel: p.isLabelPrinter,
                        documentTypes: p.documentTypes,
                      ),
                    ),
                  ),
                );
              } else if (a == 'test' || a == 'test_cloud') {
                // A7: USB không sẵn sàng / không phải Agent local → luôn cloud.
                final locallyReady = _readyPrinterIds.contains(p.id);
                final forceCloud = a == 'test_cloud' ||
                    !locallyReady ||
                    (p.needsPrintAgent &&
                        !(_agent.enabled &&
                            _agent.assignedPrinterIds.contains(p.id)));
                final ok = await PosPrintOrchestrator.instance.testPrinter(
                  p,
                  forceRemote: forceCloud,
                );
                if (!mounted) return;
                if (ok) {
                  if (mine) setState(() => _readyPrinterIds.add(p.id));
                  unawaited(_refreshPrinterReadiness());
                }
              } else if (a == 'delete') {
                final yes = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text(tr('Xóa máy in?')),
                    content: Text(tr(p.name)),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: Text(tr('Hủy'))),
                      FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: Text(tr('Xóa'))),
                    ],
                  ),
                );
                if (yes == true) {
                  final deletedId = p.id;
                  final res = await _api.deletePosStorePrinter(deletedId);
                  if (!mounted) return;
                  if (res['isSuccess'] == true) {
                    setState(() {
                      _printers.removeWhere((x) => x.id == deletedId);
                      _routes.removeWhere((x) => x.printerId == deletedId);
                      if (_agent.assignedPrinterIds.contains(deletedId)) {
                        _agent = _agent.copyWith(
                          assignedPrinterIds: _agent.assignedPrinterIds
                              .where((id) => id != deletedId)
                              .toList(),
                        );
                        unawaited(_agent.save());
                      }
                    });
                    NotificationOverlayManager().showSuccess(
                      title: 'Đã xóa máy in',
                      message: p.name,
                    );
                    await _load();
                  } else {
                    NotificationOverlayManager().showError(
                      title: 'Không xóa được',
                      message: res['message']?.toString() ??
                          'Kiểm tra quyền PosSell (Sửa) hoặc thử lại',
                    );
                  }
                }
              }
            },
            itemBuilder: (_) {
              final locallyReady = _readyPrinterIds.contains(p.id);
              final isRemoteCloud = !locallyReady ||
                  (p.needsPrintAgent &&
                      !(_agent.enabled &&
                          _agent.assignedPrinterIds.contains(p.id)));
              return [
                PopupMenuItem(
                    value: 'products', child: Text(tr('Sản phẩm in kho'))),
                if (locallyReady)
                  PopupMenuItem(
                      value: 'test', child: Text(tr('Test in cục bộ'))),
                PopupMenuItem(
                  value: 'test_cloud',
                  child: Text(tr(isRemoteCloud
                      ? 'Test in qua cloud'
                      : 'Test in qua cloud (máy thu ngân)')),
                ),
                if (_canManageCloudPrinters) ...[
                  PopupMenuItem(value: 'edit', child: Text(tr('Sửa'))),
                  PopupMenuItem(value: 'delete', child: Text(tr('Xóa'))),
                ],
              ];
            },
          ),
        ],
      ),
      onTap: _canManageCloudPrinters
          ? () => _openEditor(p)
          : () {
              NotificationOverlayManager().show(
                title: 'Chỉ xem',
                message: tr(
                    'Máy in cloud — chỉ máy bật Print Agent mới được sửa. Dùng menu › Test qua cloud.'),
                duration: const Duration(seconds: 3),
              );
            },
    );
  }

  Widget _productPrinterCard() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.restaurant_menu_outlined, color: PosTheme.kiotBlue),
        title: Text(tr('Gán sản phẩm cho máy in'),
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(tr('Chọn máy in → thêm sản phẩm (tất cả, theo nhóm, từng món).'),
          style: TextStyle(fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PosProductPrinterAssignmentScreen(printers: _printers),
            ),
          );
        },
      ),
    );
  }

  Widget _routesSection() {
    // Máy cloud cửa hàng — đồng bộ với danh sách Agent/cloud.
    final routePrinters = _cloudAgentPrinters;
    if (routePrinters.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Máy in theo loại chứng từ'),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 6),
              Text(
                tr('Chưa có máy in Agent để gán. Thêm máy / chọn chip Agent ở thẻ trên.'),
                style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Máy in theo loại chứng từ'),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            Text(
              tr('Chọn máy in Agent cho từng loại chứng từ (hóa đơn, bếp, tem, kho…). '
                  'Bấm in sẽ gửi tới mọi máy đã chọn cho loại đó.'),
              style: TextStyle(fontSize: 11, color: PosTheme.textSecondary),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBAE6FD)),
              ),
              child: Text(
                tr('Nút «Lưu phân loại» chỉ lưu bảng gán máy in ↔ chứng từ trên máy chủ. '
                    'Không lưu công tắc Agent, chip máy in, hay danh sách máy.'),
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: Color(0xFF0C4A6E),
                ),
              ),
            ),
            const SizedBox(height: 10),
            ...PosCloudDocumentTypes.labels.entries.map((e) {
              final selectedIds = _routes
                  .where((r) => r.documentType == e.key)
                  .map((r) => r.printerId)
                  .toSet();
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(e.value),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    if (_printersForDoc(e.key) != '—')
                      Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 4),
                        child: Text(tr('Đang chọn: ${_printersForDoc(e.key)}'),
                          style: const TextStyle(
                              fontSize: 11, color: PosTheme.textSecondary),
                        ),
                      ),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: routePrinters.map((p) {
                        return FilterChip(
                          label: Text(tr(p.name),
                              style: const TextStyle(fontSize: 11)),
                          selected: selectedIds.contains(p.id),
                          onSelected: (v) => _toggleRoute(e.key, p.id, v),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 12),
            // Full-width + lệch trái vùng FAB — không bị «Thêm máy in» che.
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _savingRoutes ? null : _saveRoutes,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _savingRoutes
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save, size: 20),
                label: Text(
                  tr(_savingRoutes
                      ? 'Đang lưu…'
                      : 'Lưu phân loại chứng từ'),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr('Sau khi đổi chip chứng từ phải bấm Lưu — chưa lưu thì in vẫn theo cấu hình cũ.'),
              style: TextStyle(fontSize: 11, color: PosTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrinterEditorSheet extends StatefulWidget {
  const _PrinterEditorSheet({
    this.existing,
    required this.btDevices,
    required this.onRefreshBluetooth,
  });
  final PosStorePrinter? existing;
  final List<Map<String, String>> btDevices;
  final Future<List<Map<String, String>>> Function() onRefreshBluetooth;

  @override
  State<_PrinterEditorSheet> createState() => _PrinterEditorSheetState();
}

class _PrinterEditorSheetState extends State<_PrinterEditorSheet> {
  final _api = ApiService();
  final _nameCtrl = TextEditingController();
  final _lanHostCtrl = TextEditingController();
  final _lanPortCtrl = TextEditingController(text: tr('9100'));
  final _usbNameCtrl = TextEditingController();
  final _btMacCtrl = TextEditingController();
  String _printerKind = 'receipt';
  String _connection = 'Lan';
  String _brand = 'zywell';
  String _paper = 'K80';
  String _templateId = 'roll_1_50x30';
  String _protocol = 'tspl';
  int _gapMm = 2;
  int _feedBeforeCut = 1;
  String? _btAddr;
  String? _btName;
  bool _isDefault = false;
  bool _openCashDrawer = false;
  bool _openDrawerCashOnly = true;
  bool _beepOnPrint = false;
  bool _saving = false;
  bool _isSunmi = false;
  List<Map<String, String>> _btDevices = [];

  bool get _isLabel => _printerKind == 'label';

  @override
  void initState() {
    super.initState();
    _btDevices = List.from(widget.btDevices);
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _printerKind = e.isLabelPrinter ? 'label' : 'receipt';
      _connection = e.connectionType;
      if (e.isLabelPrinter) {
        _templateId = e.paperSize;
        _protocol = e.textMode ?? 'tspl';
        _gapMm = e.feedBeforeCut.clamp(1, 10);
      } else {
        _brand = e.printerBrand ?? 'zywell';
        _paper = e.paperSize;
        _feedBeforeCut = e.feedBeforeCut <= 0 ? 1 : e.feedBeforeCut;
      }
      _btAddr = e.bluetoothAddress;
      _btName = e.bluetoothName;
      _btMacCtrl.text = e.bluetoothAddress ?? '';
      _lanHostCtrl.text = e.lanHost ?? '';
      _lanPortCtrl.text = '${e.lanPort}';
      _usbNameCtrl.text = e.usbDeviceName ?? '';
      _isDefault = e.isDefault;
      _openCashDrawer = e.openCashDrawer;
      _openDrawerCashOnly = e.openDrawerCashOnly;
      _beepOnPrint = e.beepOnPrint;
    }
    PosThermalPrinterService.isSunmiDevice().then((v) {
      if (mounted) setState(() => _isSunmi = v);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _lanHostCtrl.dispose();
    _lanPortCtrl.dispose();
    _usbNameCtrl.dispose();
    _btMacCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickBluetooth() async {
    _btDevices = await widget.onRefreshBluetooth();
    if (!mounted) return;
    setState(() {});
    if (_btDevices.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Không tìm thấy máy in BT',
        message: tr('Ghép máy in trong Cài đặt Android → Bluetooth, rồi bấm Làm mới'),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(tr('Chọn máy in Bluetooth'),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            ..._btDevices.map(
              (d) => ListTile(
                title: Text(tr(d['name'] ?? 'Máy in')),
                subtitle: Text(tr(d['address'] ?? '')),
                onTap: () {
                  setState(() {
                    _btAddr = d['address'];
                    _btName = d['name'];
                    _btMacCtrl.text = d['address'] ?? '';
                  });
                  Navigator.pop(ctx);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    if (_connection == 'Bluetooth') {
      final mac = _btMacCtrl.text.trim().isNotEmpty
          ? _btMacCtrl.text.trim()
          : _btAddr;
      if (mac == null || mac.isEmpty) {
        NotificationOverlayManager().showError(
          title: 'Thiếu Bluetooth',
          message: tr('Chọn hoặc nhập địa chỉ MAC máy in'),
        );
        return;
      }
      _btAddr = mac;
    }
    if (_connection == 'Lan' && _lanHostCtrl.text.trim().isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Thiếu IP',
        message: tr('Nhập địa chỉ IP máy in LAN'),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'name': name,
        'connectionType': _connection,
        'printerBrand': _isLabel
            ? 'label'
            : (_connection == 'Sunmi' ? 'sunmi' : _brand),
        'paperSize': _isLabel ? _templateId : _paper,
        'textMode': _isLabel
            ? _protocol
            : (_connection == 'Sunmi' ? 'utf8' : 'auto'),
        'bluetoothAddress': _connection == 'Bluetooth' ? _btAddr : null,
        'bluetoothName': _connection == 'Bluetooth' ? _btName : null,
        'lanHost': _connection == 'Lan' && _lanHostCtrl.text.trim().isNotEmpty
            ? _lanHostCtrl.text.trim()
            : null,
        'lanPort': int.tryParse(_lanPortCtrl.text) ?? 9100,
        'usbDeviceName':
            _connection == 'Usb' && _usbNameCtrl.text.trim().isNotEmpty
                ? _usbNameCtrl.text.trim()
                : null,
        'feedBeforeCut': _isLabel ? _gapMm : _feedBeforeCut,
        'partialCut': !_isLabel,
        'openCashDrawer': !_isLabel && _openCashDrawer,
        'openDrawerCashOnly': _openDrawerCashOnly,
        'beepOnPrint': !_isLabel && _beepOnPrint,
        'isDefault': _isDefault,
        'sortOrder': 0,
        'isActive': true,
      };
      final Map<String, dynamic> res;
      if (widget.existing != null) {
        res = await _api.updatePosStorePrinter(widget.existing!.id, body);
      } else {
        res = await _api.createPosStorePrinter(body);
      }
      if (res['isSuccess'] == true && res['data'] is Map) {
        if (!mounted) return;
        Navigator.pop(
          context,
          PosStorePrinter.fromJson(res['data'] as Map<String, dynamic>),
        );
      } else {
        NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: res['message']?.toString() ?? 'Không lưu được',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final connections = <String, String>{
      'Lan': 'LAN / WiFi',
      'Bluetooth': 'Bluetooth',
      'Usb': 'USB',
      if (_isSunmi) 'Sunmi': 'Sunmi (máy tích hợp)',
    };

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr(widget.existing == null ? 'Thêm máy in' : 'Sửa máy in'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: tr('Tên máy in'),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'receipt', label: Text(tr('Hóa đơn'))),
                ButtonSegment(value: 'label', label: Text(tr('Tem nhãn'))),
              ],
              selected: {_printerKind},
              onSelectionChanged: (s) =>
                  setState(() => _printerKind = s.first),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _connection,
              decoration: InputDecoration(
                labelText: tr('Kết nối'),
                border: OutlineInputBorder(),
              ),
              items: connections.entries
                  .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(tr(e.value)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() {
                _connection = v ?? 'Lan';
                if (_connection == 'Sunmi') {
                  _brand = 'sunmi';
                }
              }),
            ),
            if (_connection == 'Lan') ...[
              const SizedBox(height: 10),
              TextField(
                controller: _lanHostCtrl,
                decoration: InputDecoration(
                  labelText: tr('IP máy in'),
                  hintText: tr('192.168.1.100'),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _lanPortCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr('Port (9100)'),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_connection == 'Bluetooth') ...[
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Máy in đã ghép')),
                subtitle: Text(
                  tr(_btName?.isNotEmpty == true
                      ? '$_btName ($_btAddr)'
                      : 'Chưa chọn — bấm để chọn'),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _pickBluetooth,
                ),
                onTap: _pickBluetooth,
              ),
              TextField(
                controller: _btMacCtrl,
                decoration: InputDecoration(
                  labelText: tr('Địa chỉ MAC (nhập tay nếu cần)'),
                  hintText: tr('AA:BB:CC:DD:EE:FF'),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => _btAddr = v.trim().isEmpty ? _btAddr : v.trim(),
              ),
            ],
            if (_connection == 'Usb') ...[
              const SizedBox(height: 10),
              TextField(
                controller: _usbNameCtrl,
                decoration: InputDecoration(
                  labelText: tr('Tên thiết bị USB (tùy chọn)'),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_connection == 'Sunmi')
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.print, color: PosTheme.kiotBlue),
                title: Text(tr('Máy in Sunmi tích hợp')),
                subtitle: Text(tr('Tự nhận trên thiết bị Sunmi')),
              ),
            if (_isLabel) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _templateId,
                decoration: InputDecoration(
                  labelText: tr('Khổ tem'),
                  border: OutlineInputBorder(),
                ),
                items: posBarcodeLabelTemplates
                    .map((t) => DropdownMenuItem(
                          value: t.id,
                          child: Text(tr('${t.sizeLabel} — ${t.name}'),
                              style: const TextStyle(fontSize: 12)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _templateId = v);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _protocol,
                decoration: InputDecoration(
                  labelText: tr('Giao thức'),
                  border: OutlineInputBorder(),
                ),
                items: PosLabelPrinterProtocol.values
                    .map((p) => DropdownMenuItem(
                          value: p.key,
                          child: Text(tr(p.label)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _protocol = v);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: _gapMm,
                decoration: InputDecoration(
                  labelText: tr('Khoảng cách tem (mm)'),
                  border: OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(value: 2, child: Text(tr('2 mm'))),
                  DropdownMenuItem(value: 3, child: Text(tr('3 mm'))),
                  DropdownMenuItem(value: 4, child: Text(tr('4 mm'))),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _gapMm = v);
                },
              ),
            ] else ...[
              if (_connection != 'Sunmi') ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: _brand,
                  decoration: InputDecoration(
                    labelText: tr('Hãng máy in'),
                    border: OutlineInputBorder(),
                  ),
                  items: PosThermalPrinterBrand.values
                      .map((b) => DropdownMenuItem(
                            value: b.key,
                            child: Text(tr(b.label)),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _brand = v ?? 'zywell'),
                ),
              ],
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _paper,
                decoration: InputDecoration(
                  labelText: tr('Khổ giấy'),
                  border: OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(value: 'K58', child: Text(tr('K58 (58mm)'))),
                  DropdownMenuItem(value: 'K80', child: Text(tr('K80 (80mm)'))),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _paper = v);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                value: _feedBeforeCut.clamp(1, 20),
                decoration: InputDecoration(
                  labelText: tr('Số dòng giãn cách trước khi cắt'),
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (var i = 1; i <= 10; i++)
                    DropdownMenuItem(value: i, child: Text('$i')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _feedBeforeCut = v);
                },
              ),
            ],
            if (!_isLabel) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Mở két tiền khi in hóa đơn')),
                subtitle: Text(tr('ESC p / SunmiDrawer — két gắn cổng RJ11 máy in')),
                value: _openCashDrawer,
                onChanged: (v) => setState(() => _openCashDrawer = v),
              ),
              if (_openCashDrawer)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Chỉ mở két với tiền mặt')),
                  value: _openDrawerCashOnly,
                  onChanged: (v) => setState(() => _openDrawerCashOnly = v),
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Bip loa máy in khi in')),
                subtitle: Text(tr('Lệnh ESC B')),
                value: _beepOnPrint,
                onChanged: (v) => setState(() => _beepOnPrint = v),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Máy in mặc định')),
              value: _isDefault,
              onChanged: (v) => setState(() => _isDefault = v),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(tr('Lưu')),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnlinePrintAgent {
  _OnlinePrintAgent({
    required this.deviceId,
    required this.deviceName,
    required this.accountDisplay,
    required this.printerNames,
    required this.isOnline,
    this.printerIds = const [],
    this.lastHeartbeatAt,
  });

  final String deviceId;
  final String deviceName;
  final String accountDisplay;
  final List<String> printerNames;
  final List<String> printerIds;
  final bool isOnline;
  final DateTime? lastHeartbeatAt;

  /// Tên máy ưu tiên model thiết bị; tránh hiện «SBOX POS» chung chung.
  String get displayTitle {
    final n = deviceName.trim();
    if (n.isNotEmpty &&
        n.toLowerCase() != 'sbox pos' &&
        n.toLowerCase() != 'android pos' &&
        n.toLowerCase() != 'máy pos') {
      return n;
    }
    if (accountDisplay.isNotEmpty && accountDisplay != 'Không rõ tài khoản') {
      return accountDisplay;
    }
    return n.isNotEmpty ? n : 'Máy POS';
  }

  bool coversPrinter(String printerId) {
    if (printerId.isEmpty || !isOnline) return false;
    return printerIds.any((id) => id.toLowerCase() == printerId.toLowerCase());
  }

  factory _OnlinePrintAgent.fromJson(Map<String, dynamic> json) {
    final names = (json['printerNames'] as List? ?? json['PrinterNames'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    final ids = (json['printerIds'] as List? ?? json['PrinterIds'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];
    final account = (json['accountLabel'] ??
                json['AccountLabel'] ??
                json['employeeName'] ??
                json['EmployeeName'] ??
                json['accountEmail'] ??
                json['accountUserName'] ??
                '')
            .toString()
            .trim();
    DateTime? hb;
    final rawHb = json['lastHeartbeatAt'] ?? json['LastHeartbeatAt'];
    if (rawHb != null) {
      final s = rawHb.toString();
      hb = DateTime.tryParse(s.endsWith('Z') || s.contains('+') ? s : '${s}Z');
    }
    final onlineRaw = json['isOnline'] ?? json['IsOnline'];
    final isOnline = onlineRaw == true ||
        onlineRaw?.toString().toLowerCase() == 'true' ||
        (onlineRaw == null &&
            hb != null &&
            DateTime.now().toUtc().difference(hb.toUtc()).inMinutes < 3);
    return _OnlinePrintAgent(
      deviceId: (json['deviceId'] ?? json['DeviceId'])?.toString() ?? '',
      deviceName: (json['deviceName'] ?? json['DeviceName'])?.toString() ?? '',
      accountDisplay: account.isNotEmpty ? account : 'Không rõ tài khoản',
      printerNames: names,
      printerIds: ids,
      isOnline: isOnline,
      lastHeartbeatAt: hb,
    );
  }
}
