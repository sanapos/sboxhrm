import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/pos_store_printer.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../services/pos_print_agent_service.dart';
import '../../utils/pos_print_agent_settings.dart';
import '../../utils/pos_barcode_print.dart';
import '../../utils/pos_label_printer_settings.dart';
import '../../utils/pos_print_orchestrator.dart';
import '../../utils/pos_thermal_printer_service.dart';
import '../../utils/pos_thermal_printer_settings.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import 'pos_product_printer_assignment_screen.dart';

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
  List<Map<String, String>> _btDevices = [];

  @override
  void initState() {
    super.initState();
    _load();
    if (!kIsWeb) {
      PosThermalPrinterService.listBluetoothDevices().then((d) {
        if (mounted) setState(() => _btDevices = d);
      });
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _agent = await PosPrintAgentSettings.load();
      await PosPrintOrchestrator.instance.refreshConfig(force: true);
      final pr = await _api.getPosStorePrinters();
      final rt = await _api.getPosPrinterRoutes();
      if (pr['isSuccess'] == true && pr['data'] is List) {
        _printers = (pr['data'] as List)
            .map((e) => PosStorePrinter.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      if (rt['isSuccess'] == true && rt['data'] is List) {
        _routes = (rt['data'] as List)
            .map((e) => PosPrinterRoute.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
          message: 'Thêm máy in LAN/BT/USB trong danh sách bên dưới',
        );
      }
      // Lần đầu bật: gán hết máy in cloud cho thiết bị này (chỉ 1 máy nên bật Agent).
      if (_agent.assignedPrinterIds.isEmpty && agentPrinters.isNotEmpty) {
        _agent = _agent.copyWith(
          enabled: true,
          assignedPrinterIds: agentPrinters.map((p) => p.id).toList(),
        );
      } else {
        _agent = _agent.copyWith(enabled: v);
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
        message: 'Giữ app mở — nhận lệnh in cloud (LAN/BT/USB)',
      );
    } else if (!v) {
      await PosPrintAgentService.instance.stop();
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
          message: 'Phân loại máy in theo chứng từ',
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
        title: const Text('Máy in cửa hàng'),
        backgroundColor: PosTheme.kiotBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Gán sản phẩm cho máy in',
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
        label: const Text('Thêm máy in'),
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
                const Expanded(
                  child: Text(
                    'Print Agent (in cloud)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Switch(
                  value: _agent.enabled,
                  onChanged: _toggleAgent,
                ),
              ],
            ),
            Text(
              _agent.enabled
                  ? 'Thiết bị này nhận lệnh in cho máy in đã chọn bên dưới'
                  : 'Chỉ bật trên 1 thiết bị đã gắn máy in (LAN/BT)',
              style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
            ),
            if (agentPrinters.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Thêm máy in LAN/BT/USB — in qua cloud (Print Agent)',
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
                    label: Text(p.name, style: const TextStyle(fontSize: 11)),
                    selected: selected,
                    onSelected: (v) async {
                      var ids = List<String>.from(_agent.assignedPrinterIds);
                      if (v) {
                        if (!ids.contains(p.id)) ids.add(p.id);
                      } else {
                        ids.remove(p.id);
                      }
                      _agent = _agent.copyWith(assignedPrinterIds: ids);
                      await _agent.save();
                      setState(() {});
                      final storeId = Provider.of<AuthProvider>(context, listen: false)
                          .user?.storeId;
                      if (_agent.enabled &&
                          storeId != null &&
                          storeId.isNotEmpty) {
                        await PosPrintAgentService.instance.ensureRunning(storeId);
                      }
                    },
                  );
                }).toList(),
              ),
            ],
            if (PosPrintAgentService.instance.isRunning)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  '● Agent đang chạy',
                  style: TextStyle(color: Colors.green, fontSize: 12),
                ),
              ),
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
            const Text('Danh sách máy in',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 8),
            if (_printers.isEmpty)
              const Text('Chưa có máy in. Thêm máy in LAN/BT/USB cho in cloud.',
                  style: TextStyle(color: PosTheme.textSecondary)),
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
      title: Text(p.name),
      subtitle: Text(
        '$kind · ${p.connectionType}${p.needsPrintAgent ? ' · Cần Agent' : ' · In trực tiếp'}',
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
              } else if (a == 'test') {
                final ok = await PosPrintOrchestrator.instance.testPrinter(p);
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
                    title: const Text('Xóa máy in?'),
                    content: Text(p.name),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('Hủy')),
                      FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          child: const Text('Xóa')),
                    ],
                  ),
                );
                if (yes == true) {
                  await _api.deletePosStorePrinter(p.id);
                  await _load();
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'products', child: Text('Sản phẩm in kho')),
              PopupMenuItem(value: 'test', child: Text('Test in')),
              PopupMenuItem(value: 'edit', child: Text('Sửa')),
              PopupMenuItem(value: 'delete', child: Text('Xóa')),
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
        title: const Text('Gán sản phẩm cho máy in',
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text(
          'Chọn máy in → thêm sản phẩm (tất cả, theo nhóm, từng món).',
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
            const Text('Máy in theo loại chứng từ',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 4),
            const Text(
              'Chọn một hoặc nhiều máy in — bấm in sẽ gửi tới tất cả máy đã chọn.',
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
                    Text(e.value,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    if (_printersForDoc(e.key) != '—')
                      Padding(
                        padding: const EdgeInsets.only(top: 2, bottom: 4),
                        child: Text(
                          'Đang chọn: ${_printersForDoc(e.key)}',
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
                              Text(p.name, style: const TextStyle(fontSize: 11)),
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
                label: const Text('Lưu phân loại'),
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
  final _lanPortCtrl = TextEditingController(text: '9100');
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
        message: 'Ghép máy in trong Cài đặt Android → Bluetooth, rồi bấm Làm mới',
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Chọn máy in Bluetooth',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            ..._btDevices.map(
              (d) => ListTile(
                title: Text(d['name'] ?? 'Máy in'),
                subtitle: Text(d['address'] ?? ''),
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
          message: 'Chọn hoặc nhập địa chỉ MAC máy in',
        );
        return;
      }
      _btAddr = mac;
    }
    if (_connection == 'Lan' && _lanHostCtrl.text.trim().isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Thiếu IP',
        message: 'Nhập địa chỉ IP máy in LAN',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'name': name,
        'connectionType': _connection,
        'printerBrand': _isLabel ? 'label' : _brand,
        'paperSize': _isLabel ? _templateId : _paper,
        'textMode': _isLabel ? _protocol : 'auto',
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
        'feedBeforeCut': _isLabel ? _gapMm : 8,
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
              widget.existing == null ? 'Thêm máy in' : 'Sửa máy in',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Tên máy in',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'receipt', label: Text('Hóa đơn')),
                ButtonSegment(value: 'label', label: Text('Tem nhãn')),
              ],
              selected: {_printerKind},
              onSelectionChanged: (s) =>
                  setState(() => _printerKind = s.first),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _connection,
              decoration: const InputDecoration(
                labelText: 'Kết nối',
                border: OutlineInputBorder(),
              ),
              items: connections.entries
                  .map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _connection = v ?? 'Lan'),
            ),
            if (_connection == 'Lan') ...[
              const SizedBox(height: 10),
              TextField(
                controller: _lanHostCtrl,
                decoration: const InputDecoration(
                  labelText: 'IP máy in',
                  hintText: '192.168.1.100',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _lanPortCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Port (9100)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_connection == 'Bluetooth') ...[
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Máy in đã ghép'),
                subtitle: Text(
                  _btName?.isNotEmpty == true
                      ? '$_btName ($_btAddr)'
                      : 'Chưa chọn — bấm để chọn',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _pickBluetooth,
                ),
                onTap: _pickBluetooth,
              ),
              TextField(
                controller: _btMacCtrl,
                decoration: const InputDecoration(
                  labelText: 'Địa chỉ MAC (nhập tay nếu cần)',
                  hintText: 'AA:BB:CC:DD:EE:FF',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => _btAddr = v.trim().isEmpty ? _btAddr : v.trim(),
              ),
            ],
            if (_connection == 'Usb') ...[
              const SizedBox(height: 10),
              TextField(
                controller: _usbNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Tên thiết bị USB (tùy chọn)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (_connection == 'Sunmi')
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.print, color: PosTheme.kiotBlue),
                title: Text('Máy in Sunmi tích hợp'),
                subtitle: Text('Tự nhận trên thiết bị Sunmi'),
              ),
            if (_isLabel) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _templateId,
                decoration: const InputDecoration(
                  labelText: 'Khổ tem',
                  border: OutlineInputBorder(),
                ),
                items: posBarcodeLabelTemplates
                    .map((t) => DropdownMenuItem(
                          value: t.id,
                          child: Text('${t.sizeLabel} — ${t.name}',
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
                decoration: const InputDecoration(
                  labelText: 'Giao thức',
                  border: OutlineInputBorder(),
                ),
                items: PosLabelPrinterProtocol.values
                    .map((p) => DropdownMenuItem(
                          value: p.key,
                          child: Text(p.label),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _protocol = v);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: _gapMm,
                decoration: const InputDecoration(
                  labelText: 'Khoảng cách tem (mm)',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 2, child: Text('2 mm')),
                  DropdownMenuItem(value: 3, child: Text('3 mm')),
                  DropdownMenuItem(value: 4, child: Text('4 mm')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _gapMm = v);
                },
              ),
            ] else ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _brand,
                decoration: const InputDecoration(
                  labelText: 'Hãng máy in',
                  border: OutlineInputBorder(),
                ),
                items: PosThermalPrinterBrand.values
                    .map((b) => DropdownMenuItem(
                          value: b.key,
                          child: Text(b.label),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _brand = v ?? 'zywell'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _paper,
                decoration: const InputDecoration(
                  labelText: 'Khổ giấy',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'K58', child: Text('K58 (58mm)')),
                  DropdownMenuItem(value: 'K80', child: Text('K80 (80mm)')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _paper = v);
                },
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Máy in mặc định'),
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
                  : const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }
}
