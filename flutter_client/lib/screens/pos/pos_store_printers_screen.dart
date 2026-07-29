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
import '../../utils/pos_print_orchestrator.dart';
import '../../utils/pos_thermal_printer_service.dart';
import '../../utils/pos_thermal_printer_settings.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import 'pos_product_printer_assignment_screen.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

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
  List<_OnlinePrintAgent> _onlineAgents = [];
  bool _multiAgent = false;
  bool _hasPrinterConflict = false;
  Timer? _agentPoll;
  String? _myDeviceId;
  StreamSubscription<Map<String, dynamic>>? _agentHbSub;

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
    _agentPoll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && !_loading && !_agentsLoading) {
        unawaited(_loadOnlineAgents(silent: true));
      }
    });
    _agentHbSub = SignalRService().onPrintAgentHeartbeat.listen((data) {
      if (!mounted || _agentsLoading) return;
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

    // Cập nhật list ngay từ SignalR — không chờ API.
    if (mounted && deviceId.isNotEmpty) {
      _upsertAgentFromHeartbeat(data, online: isOnlineFlag);
    }

    if (mounted && !_agentsLoading) {
      unawaited(_loadOnlineAgents(silent: true));
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
    final rawIds = data['printerIds'] ?? data['PrinterIds'];
    if (rawIds is List) {
      for (final id in rawIds) {
        final pid = id.toString();
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
    final agent = _OnlinePrintAgent(
      deviceId: deviceId,
      deviceName: (data['deviceName'] ?? data['DeviceName'])?.toString() ?? '',
      accountDisplay: account.isNotEmpty ? account : 'Agent',
      printerNames: names,
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
      if (mounted) unawaited(_loadOnlineAgents(silent: true));
      unawaited(PosPrintOrchestrator.instance.refreshConfig(force: true));
    }
  }

  Future<void> _loadOnlineAgents({bool silent = false}) async {
    if (_agentsLoading) return;
    _agentsLoading = true;
    try {
      if (_agent.enabled && PosPrintAgentService.instance.isRunning) {
        unawaited(
          PosPrintAgentService.instance.forceRegister(refreshPrinters: false),
        );
      }

      // Lấy tất cả rồi lọc — tránh onlineOnly rỗng do timezone server cũ.
      final res = await _api
          .getPosPrintAgents(onlineOnly: false, staleSeconds: 180)
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
            180;
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

      final merged = <String, _OnlinePrintAgent>{
        for (final a in _onlineAgents)
          if (a.isOnline) a.deviceId: a,
        for (final a in list) a.deviceId: a,
      };

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
      if (agentPrinters.isEmpty) {
        NotificationOverlayManager().showWarning(
          title: 'Chưa có máy in cloud',
          message: tr('Thêm máy in LAN/BT/USB trong danh sách bên dưới'),
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
      // Lần đầu bật: gán hết máy in cloud cho thiết bị này (chỉ 1 máy nên bật Agent).
      if (_agent.assignedPrinterIds.isEmpty && agentPrinters.isNotEmpty) {
        _agent = _agent.copyWith(
          enabled: true,
          assignedPrinterIds: agentPrinters.map((p) => p.id).toList(),
          accountLabel: label,
        );
      } else {
        _agent = _agent.copyWith(enabled: true, accountLabel: label);
      }
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
          title: 'Đã lưu',
          message: tr('Phân loại máy in theo chứng từ'),
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
            tooltip: tr('Gán sản phẩm cho máy in'),
            onPressed: _printers.isEmpty
                ? null
                : () {
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
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                children: [
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: PosTheme.kiotBlue,
        icon: const Icon(Icons.add),
        label: Text(tr('Thêm máy in')),
      ),
    );
  }

  Widget _agentCard() {
    final agentPrinters = _printers.where((p) => p.needsPrintAgent).toList();
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
                '1) Thêm máy in Zywell/LAN (IP:9100) vào danh sách bên dưới.\n'
                '2) Chỉ 1 máy (Sunmi / điện thoại gần máy in): bật công tắc này + chọn chip máy in — giữ app mở.\n'
                '3) Điện thoại thu ngân khác: tắt công tắc này. In → lệnh gửi máy chủ → máy ở bước 2 in ra.\n'
                'Lưu ý: máy thu ngân tắt «máy in cục bộ» nếu muốn chỉ in qua máy chủ.'),
                style: TextStyle(fontSize: 12, height: 1.35, color: Color(0xFF1E3A5F)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr(_agent.enabled
                  ? 'Máy này đang nhận lệnh in cho chip đã chọn'
                  : 'Tắt trên máy thu ngân — chỉ bật trên 1 máy gần máy in'),
              style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
            ),
            if (agentPrinters.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(tr('Chưa có máy in cửa hàng — bấm «Thêm máy in» (LAN/BT/Sunmi)'),
                  style: TextStyle(fontSize: 11, color: Colors.orange),
                ),
              ),
            if (agentPrinters.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: agentPrinters.map((p) {
                  final selected = _agent.assignedPrinterIds.contains(p.id);
                  return FilterChip(
                    label: Text(tr(p.name), style: const TextStyle(fontSize: 11)),
                    selected: selected,
                    onSelected: (v) async {
                      var ids = List<String>.from(_agent.assignedPrinterIds);
                      if (v) {
                        if (!ids.contains(p.id)) ids.add(p.id);
                      } else {
                        ids.remove(p.id);
                      }
                      _agent = _agent.copyWith(
                        assignedPrinterIds: ids,
                        accountLabel: _accountLabelForHeartbeat(),
                      );
                      await _agent.save();
                      setState(() {});
                      final storeId = Provider.of<AuthProvider>(context, listen: false)
                          .user?.storeId;
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Danh sách máy in'),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            if (_printers.isEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Chưa có máy in. Thêm máy in LAN/BT/Sunmi cho in cloud.'),
                    style: TextStyle(color: PosTheme.textSecondary),
                  ),
                  TextButton.icon(
                    onPressed: () => unawaited(_load()),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: Text(tr('Tải lại danh sách')),
                  ),
                ],
              ),
            ..._printers.map(_printerTile),
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
    final statusColor = p.isOnline
        ? Colors.green
        : p.healthStatus == 'Offline'
            ? Colors.red
            : Colors.grey;
    final kind = p.isLabelPrinter ? 'Tem nhãn' : 'Hóa đơn';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: PosTheme.kiotBlueLight,
        child: Icon(
          _connectionIcon(p),
          color: PosTheme.kiotBlue,
          size: 20,
        ),
      ),
      title: Text(tr(p.name)),
      subtitle: Text(
        tr('$kind · ${p.connectionType}${p.needsPrintAgent ? ' · Cần Agent' : ' · In trực tiếp'}'),
        style: const TextStyle(fontSize: 11),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: statusColor),
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
                    ),
                  ),
                );
              } else if (a == 'test' || a == 'test_cloud') {
                final ok = await PosPrintOrchestrator.instance.testPrinter(
                  p,
                  forceRemote: a == 'test_cloud',
                );
                if (!ok && mounted) {
                  NotificationOverlayManager().showError(
                    title: 'Test thất bại',
                    message: p.name,
                  );
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
                    // Xóa ngay trên UI — không chờ reload (tránh list cũ nếu API chậm).
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
            itemBuilder: (_) => [
              PopupMenuItem(value: 'products', child: Text(tr('Sản phẩm in kho'))),
              PopupMenuItem(value: 'test', child: Text(tr('Test in cục bộ'))),
              PopupMenuItem(
                value: 'test_cloud',
                child: Text(tr('Test in qua cloud (máy thu ngân)')),
              ),
              PopupMenuItem(value: 'edit', child: Text(tr('Sửa'))),
              PopupMenuItem(value: 'delete', child: Text(tr('Xóa'))),
            ],
          ),
        ],
      ),
      onTap: () => _openEditor(p),
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
    if (_printers.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Máy in theo loại chứng từ'),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            Text(tr('Chọn một hoặc nhiều máy in — bấm in sẽ gửi tới tất cả máy đã chọn.'),
              style: TextStyle(fontSize: 11, color: PosTheme.textSecondary),
            ),
            const SizedBox(height: 8),
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
                      children: _printers.map((p) {
                        return FilterChip(
                          label:
                              Text(tr(p.name), style: const TextStyle(fontSize: 11)),
                          selected: selectedIds.contains(p.id),
                          onSelected: (v) => _toggleRoute(e.key, p.id, v),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _savingRoutes ? null : _saveRoutes,
                icon: _savingRoutes
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save, size: 18),
                label: Text(tr('Lưu phân loại')),
              ),
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
  String? _btAddr;
  String? _btName;
  bool _isDefault = false;
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
      }
      _btAddr = e.bluetoothAddress;
      _btName = e.bluetoothName;
      _btMacCtrl.text = e.bluetoothAddress ?? '';
      _lanHostCtrl.text = e.lanHost ?? '';
      _lanPortCtrl.text = '${e.lanPort}';
      _usbNameCtrl.text = e.usbDeviceName ?? '';
      _isDefault = e.isDefault;
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
        'feedBeforeCut': _isLabel ? _gapMm : (_connection == 'Sunmi' ? 14 : 8),
        'partialCut': !_isLabel,
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
              initialValue: _connection,
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
              onChanged: (v) => setState(() => _connection = v ?? 'Lan'),
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
                initialValue: _templateId,
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
                initialValue: _protocol,
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
                initialValue: _gapMm,
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
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _brand,
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
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _paper,
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
    this.lastHeartbeatAt,
  });

  final String deviceId;
  final String deviceName;
  final String accountDisplay;
  final List<String> printerNames;
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

  factory _OnlinePrintAgent.fromJson(Map<String, dynamic> json) {
    final names = (json['printerNames'] as List? ?? json['PrinterNames'] as List?)
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
      isOnline: isOnline,
      lastHeartbeatAt: hb,
    );
  }
}
