import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../services/pos_product_printer_service.dart';
import '../../utils/pos_barcode_print.dart';
import '../../utils/pos_label_printer_service.dart';
import '../../utils/pos_label_printer_settings.dart';
import '../../utils/pos_local_printers_store.dart';
import '../../utils/pos_print_orchestrator.dart';
import '../../utils/pos_printer_readiness.dart';
import '../../utils/pos_thermal_printer_service.dart';
import '../../utils/pos_thermal_printer_settings.dart';
import '../../utils/pos_usb_printer.dart';
import '../../utils/pos_printer_hardware.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';
import 'pos_product_printer_assignment_screen.dart';

/// Quản lý nhiều máy in nội bộ (nhiệt + tem) trên thiết bị này.
class PosLocalPrintersScreen extends StatefulWidget {
  const PosLocalPrintersScreen({super.key});

  @override
  State<PosLocalPrintersScreen> createState() => _PosLocalPrintersScreenState();
}

class _PosLocalPrintersScreenState extends State<PosLocalPrintersScreen> {
  final _store = PosLocalPrintersStore.instance;
  final _api = ApiService();
  List<PosLocalPrinterProfile> _items = [];
  bool _loading = true;
  bool _syncing = false;
  final Map<String, PosPrinterLinkStatus> _linkStatus = {};
  Timer? _probeTimer;
  StreamSubscription<Map<String, dynamic>>? _usbEventSub;

  @override
  void initState() {
    super.initState();
    _reload();
    _probeTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !_loading) unawaited(_refreshLinkStatus());
    });
    if (!kIsWeb && PosUsbPrinter.isSupported) {
      _usbEventSub = PosUsbPrinter.deviceEvents.listen((_) {
        if (mounted && !_loading) unawaited(_refreshLinkStatus());
      });
    }
  }

  @override
  void dispose() {
    _probeTimer?.cancel();
    unawaited(_usbEventSub?.cancel() ?? Future<void>.value());
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final list = await _store.loadAll();
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
    unawaited(_refreshLinkStatus());
  }

  Future<void> _refreshLinkStatus() async {
    if (kIsWeb || !mounted || _items.isEmpty) return;
    final usbList = await PosPrinterReadiness.listUsbDevices();
    final usbProfiles = _items
        .where((p) =>
            p.enabled && p.connectionType == PosThermalConnectionType.usb)
        .map((p) => (id: p.id, savedRaw: p.usbDeviceName))
        .toList();
    final usbMatched =
        PosUsbPrinter.matchProfilesExclusive(usbProfiles, usbList);

    final next = <String, PosPrinterLinkStatus>{};
    for (final p in _items) {
      final matched = p.connectionType == PosThermalConnectionType.usb
          ? usbMatched[p.id]
          : null;
      final status = await PosPrinterReadiness.probeLocal(
        p,
        usbList: usbList,
        matchedUsb: matched,
        useMatchedUsbOnly:
            p.connectionType == PosThermalConnectionType.usb,
      );
      next[p.id] = status;
      final sid = (p.storePrinterId ?? '').trim();
      if (sid.isEmpty) continue;
      if (status == PosPrinterLinkStatus.ready) {
        unawaited(_api.reportPosPrinterHealth(sid, status: 'Online'));
      } else if (status == PosPrinterLinkStatus.lost) {
        unawaited(_api.reportPosPrinterHealth(
          sid,
          status: 'Offline',
          errorMessage: 'Mất kết nối nội bộ',
        ));
      }
    }
    if (!mounted) return;
    setState(() {
      _linkStatus
        ..clear()
        ..addAll(next);
    });
  }

  Future<void> _syncAll() async {
    setState(() => _syncing = true);
    await _store.syncAll();
    await PosProductPrinterService.instance.invalidate();
    await _reload();
    if (!mounted) return;
    setState(() => _syncing = false);
    NotificationOverlayManager().showSuccess(
      title: 'Đã đồng bộ',
      message: tr('Máy nội bộ đã lên danh sách gán món toàn hệ thống'),
    );
  }

  Future<void> _edit([PosLocalPrinterProfile? existing]) async {
    final isNew = existing == null;
    final result = await showModalBottomSheet<PosLocalPrinterProfile>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (_) => _LocalPrinterEditorSheet(initial: existing),
    );
    if (result == null) return;
    final saved = await _store.upsert(result, syncServer: true);
    await PosProductPrinterService.instance.invalidate();
    await PosPrintOrchestrator.instance.invalidateCache();
    await _reload();
    if (!mounted) return;
    if (!isNew) return;

    final testNow = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('In thử máy vừa thêm?')),
        content: Text(
          tr('Gửi trang in thử tới «${saved.name}» để kiểm tra kết nối ngay.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Để sau')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('In thử')),
          ),
        ],
      ),
    );
    if (testNow == true && mounted) await _testProfile(saved);
  }

  Future<void> _testProfile(PosLocalPrinterProfile p) async {
    NotificationOverlayManager().show(
      title: 'Đang in thử…',
      message: p.name,
      duration: const Duration(seconds: 2),
    );
    final ok = p.isLabel
        ? await PosLabelPrinterService.testPrint(
            p.toLabelSettings().copyWith(enabled: true),
          )
        : await PosThermalPrinterService.testPrint(
            p.toThermalSettings().copyWith(enabled: true),
          );
    if (!mounted) return;
    if (ok) {
      setState(() => _linkStatus[p.id] = PosPrinterLinkStatus.ready);
      final sid = (p.storePrinterId ?? '').trim();
      if (sid.isNotEmpty) {
        unawaited(_api.reportPosPrinterHealth(sid, status: 'Online'));
      }
      NotificationOverlayManager().showSuccess(
        title: 'In thử OK',
        message: tr(p.name),
      );
    } else {
      setState(() => _linkStatus[p.id] = PosPrinterLinkStatus.lost);
      final sid = (p.storePrinterId ?? '').trim();
      if (sid.isNotEmpty) {
        unawaited(_api.reportPosPrinterHealth(
          sid,
          status: 'Offline',
          errorMessage: 'In thử thất bại',
        ));
      }
      NotificationOverlayManager().showError(
        title: 'In thử thất bại',
        message: tr(
          'Kiểm tra kết nối «${p.name}» (${p.connectionType.label})',
        ),
      );
    }
  }

  Future<void> _delete(PosLocalPrinterProfile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa máy in nội bộ?')),
        content: Text(tr(p.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Xóa'))),
        ],
      ),
    );
    if (ok != true) return;
    await _store.remove(p.id, syncServer: true);
    await PosProductPrinterService.instance.invalidate();
    await PosPrintOrchestrator.instance.invalidateCache();
    await _reload();
    if (!mounted) return;
    NotificationOverlayManager().showSuccess(
      title: 'Đã xóa',
      message: tr(p.name),
    );
  }

  Future<void> _assignProducts(PosLocalPrinterProfile p) async {
    // Luôn sync lại: storePrinterId cũ có thể trỏ máy Agent / đã xóa / sai cửa hàng
    // → API gán trả «Máy in không hợp lệ».
    final profile = await _store.ensureServerPrinter(p);
    final id = profile?.storePrinterId?.trim();
    if (profile == null || id == null || id.isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Chưa đồng bộ máy in',
        message: tr(
          'Không đẩy được máy «${p.name}» lên server.\n'
          'Kiểm tra mạng / đăng nhập cửa hàng rồi bấm Đồng bộ.',
        ),
      );
      return;
    }
    if (!mounted) return;
    await _reload();

    // Gán SP chỉ hợp lệ trên máy Agent/cloud — remap twin từ bản nội bộ.
    await PosPrintOrchestrator.instance.refreshConfig();
    final orch = PosPrintOrchestrator.instance;
    final localRow = orch.printers
        .where((x) => x.id.toLowerCase() == id.toLowerCase())
        .firstOrNull;
    final target =
        localRow == null ? null : orch.preferCloudAgentPrinter(localRow);
    if (target == null || target.isDeviceLocal) {
      NotificationOverlayManager().showWarning(
        title: tr('Gán món trên máy cửa hàng'),
        message: tr(
          'Gán sản phẩm chỉ áp dụng cho máy in cửa hàng (Agent/cloud).\n'
          'Tạo máy cửa hàng cùng cổng/tên với «${p.name}», rồi gán món tại đó. '
          'Máy nội bộ chỉ để in thử trên thiết bị này.',
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PosPrinterManageProductsScreen(
          printerId: target.id,
          printerName: target.name,
          isLabel: profile.isLabel,
          purpose: purposeFromRoles(profile.roles),
        ),
      ),
    );
    await PosProductPrinterService.instance.invalidate();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Máy in nội bộ')),
        backgroundColor: PosTheme.kiotBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: tr('Kiểm tra kết nối'),
            onPressed: _loading ? null : () => unawaited(_refreshLinkStatus()),
            icon: const Icon(Icons.wifi_tethering),
          ),
          IconButton(
            tooltip: tr('Gán sản phẩm (mọi máy)'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PosProductPrinterAssignmentScreen(),
                ),
              );
            },
            icon: const Icon(Icons.link),
          ),
          IconButton(
            tooltip: tr('Đồng bộ lên server'),
            onPressed: _syncing ? null : _syncAll,
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.cloud_upload_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        backgroundColor: PosTheme.kiotBlue,
        icon: const Icon(Icons.add),
        label: Text(tr('Thêm máy')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              children: [
                Card(
                  color: const Color(0xFFEFF6FF),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      tr('Hướng dẫn — máy in nội bộ\n'
                          '• Chỉ in trên thiết bị này (Bluetooth / LAN / USB / Sunmi), không qua PC Agent.\n'
                          '• Bật vai trò «Hóa đơn» trên máy nhiệt: khi thanh toán, máy này in trước; OK thì không gửi máy cửa hàng.\n'
                          '• Máy in nhiệt: hóa đơn, báo bếp, báo kho… · Máy tem: tem mã vạch / tem bếp.\n'
                          '• Chữ tiếng Việt lỗi: Hãng = Xprinter/Zywell + Chế độ chữ = «In ảnh» hoặc «Tự động» (không dùng UTF-8 thuần trên XP-80C).\n'
                          '• Máy dùng chung web/A7/PC → quay lại «Máy in cửa hàng».'),
                      style: const TextStyle(fontSize: 12.5, height: 1.35),
                    ),
                  ),
                ),
                if (_items.isNotEmpty &&
                    !_items.any((p) =>
                        p.enabled &&
                        !p.isLabel &&
                        p.roles.contains(PosLocalPrinterRoles.stockIssue))) ...[
                  const SizedBox(height: 8),
                  Card(
                    color: const Color(0xFFFFF7ED),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: Color(0xFFC2410C), size: 22),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              tr('Chưa có máy nhiệt với vai trò «Báo kho / xuất kho».\n'
                                  'Khi bật in xuất kho, app sẽ báo lỗi thay vì in nhầm máy báo bếp.\n'
                                  'Sửa một máy nhiệt (vd. zywel) → bật Báo kho / xuất kho.'),
                              style: const TextStyle(
                                fontSize: 12.5,
                                height: 1.35,
                                color: Color(0xFF9A3412),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                if (_items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      tr('Chưa có máy in nội bộ.\nBấm «Thêm máy» → chọn Máy in nhiệt hoặc Máy in tem.'),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ..._items.map((p) {
                    final roles =
                        p.roles.map(PosLocalPrinterRoles.label).join(' · ');
                    final canAssign =
                        PosLocalPrinterRoles.needsProductAssignment(p.roles);
                    final link = _linkStatus[p.id] ??
                        PosPrinterLinkStatus.unknown;
                    final ready = link == PosPrinterLinkStatus.ready;
                    final lost = link == PosPrinterLinkStatus.lost;
                    final statusColor = !p.enabled
                        ? Colors.grey
                        : ready
                            ? Colors.green
                            : lost
                                ? Colors.red
                                : Colors.grey;
                    final statusText = !p.enabled
                        ? 'Tắt'
                        : PosPrinterReadiness.labelVi(link);
                    final avatarBg = ready
                        ? const Color(0xFFDCFCE7)
                        : lost
                            ? const Color(0xFFFEE2E2)
                            : (p.enabled
                                ? PosTheme.kiotBlue.withOpacity(0.12)
                                : Colors.grey.shade200);
                    final avatarFg = ready
                        ? const Color(0xFF15803D)
                        : lost
                            ? const Color(0xFFB91C1C)
                            : (p.enabled ? PosTheme.kiotBlue : Colors.grey);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Card(
                        child: Column(
                          children: [
                            ListTile(
                              leading: CircleAvatar(
                                backgroundColor: avatarBg,
                                child: Icon(
                                  p.isLabel
                                      ? Icons.label_outline
                                      : Icons.receipt_long,
                                  color: avatarFg,
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      tr(p.name),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  Icon(Icons.circle,
                                      size: 10, color: statusColor),
                                  const SizedBox(width: 6),
                                  Text(
                                    tr(statusText),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: statusColor,
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                tr('${p.kind.labelVi} · ${p.enabled ? 'Bật' : 'Tắt'} · ${p.connectionType.label}\n$roles'),
                                style: const TextStyle(fontSize: 12),
                              ),
                              isThreeLine: true,
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) {
                                  if (v == 'test') _testProfile(p);
                                  if (v == 'edit') _edit(p);
                                  if (v == 'assign') _assignProducts(p);
                                  if (v == 'delete') _delete(p);
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                      value: 'test',
                                      child: Text(tr('In thử'))),
                                  PopupMenuItem(
                                      value: 'edit', child: Text(tr('Sửa'))),
                                  if (canAssign)
                                    PopupMenuItem(
                                      value: 'assign',
                                      child: Text(tr('Gán sản phẩm')),
                                    ),
                                  PopupMenuItem(
                                      value: 'delete', child: Text(tr('Xóa'))),
                                ],
                              ),
                              onTap: () => _edit(p),
                            ),
                            if (canAssign)
                              Align(
                                alignment: Alignment.centerRight,
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                                  child: TextButton.icon(
                                    onPressed: () => _assignProducts(p),
                                    icon: const Icon(Icons.link, size: 18),
                                    label: Text(tr('Gán sản phẩm')),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
    );
  }
}

class _LocalPrinterEditorSheet extends StatefulWidget {
  const _LocalPrinterEditorSheet({this.initial});
  final PosLocalPrinterProfile? initial;

  @override
  State<_LocalPrinterEditorSheet> createState() =>
      _LocalPrinterEditorSheetState();
}

class _LocalPrinterEditorSheetState extends State<_LocalPrinterEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _lanHost;
  late final TextEditingController _lanPort;
  late final TextEditingController _usbName;
  late final TextEditingController _btMac;
  late final TextEditingController _feedBeforeCut;
  late bool _enabled;
  late PosLocalPrinterKind _kind;
  late Set<String> _roles;
  late PosThermalConnectionType _type;
  late PosThermalPrinterBrand _brand;
  late PosThermalTextMode _textMode;
  late String _paperSize;
  late bool _openCashDrawer;
  late bool _openDrawerCashOnly;
  late bool _beepOnPrint;
  late bool _cutPerItem;
  late PosLabelPrinterProtocol _labelProtocol;
  late String _labelTemplateId;
  late double _labelGapMm;
  late double _labelShiftRightMm;
  late double _labelMarginRightMm;
  late double _labelMarginTopMm;
  late double _labelMarginBottomMm;
  late double _labelFontScale;
  late bool _labelShowHeader;
  late bool _labelShowTable;
  late bool _labelShowOrderNo;
  late bool _labelShowToppings;
  late bool _labelShowNote;
  late bool _labelShowQty;
  String? _btAddr;
  String? _btName;
  String? _usbStableId;
  String? _usbDisplayLabel;
  bool _isSunmi = false;
  bool _testing = false;
  List<Map<String, String>> _btDevices = [];
  List<PosUsbDevice> _usbDevices = [];
  bool _usbScanning = false;

  bool get _isLabel => _kind == PosLocalPrinterKind.label;

  static const _mmItems = <DropdownMenuItem<double>>[
    DropdownMenuItem(value: 0.0, child: Text('0 mm')),
    DropdownMenuItem(value: 1.0, child: Text('1 mm')),
    DropdownMenuItem(value: 2.0, child: Text('2 mm')),
    DropdownMenuItem(value: 3.0, child: Text('3 mm')),
    DropdownMenuItem(value: 4.0, child: Text('4 mm')),
    DropdownMenuItem(value: 5.0, child: Text('5 mm')),
    DropdownMenuItem(value: 6.0, child: Text('6 mm')),
  ];

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _name = TextEditingController(
      text: i?.name ??
          (_isLabelDefault(i) ? 'Máy in tem nội bộ' : 'Máy in nhiệt nội bộ'),
    );
    _lanHost = TextEditingController(text: i?.lanHost ?? '');
    _lanPort = TextEditingController(text: '${i?.lanPort ?? 9100}');
    _usbName = TextEditingController(text: i?.usbDeviceName ?? '');
    _btMac = TextEditingController(text: i?.bluetoothAddress ?? '');
    _feedBeforeCut =
        TextEditingController(text: '${i?.feedBeforeCut ?? 1}');
    _enabled = i?.enabled ?? true;
    _kind = i?.kind ?? PosLocalPrinterKind.receipt;
    _roles = {...(i?.roles ?? _defaultRoles(_kind))};
    _type = i?.connectionType ?? PosThermalConnectionType.bluetooth;
    _brand = i?.printerBrand ?? PosThermalPrinterBrand.zywell;
    _textMode = i?.textMode ?? PosThermalTextMode.auto;
    _paperSize = i?.paperSize ?? 'K80';
    _openCashDrawer = i?.openCashDrawer ?? false;
    _openDrawerCashOnly = i?.openDrawerCashOnly ?? true;
    _beepOnPrint = i?.beepOnPrint ?? false;
    _cutPerItem = i?.cutPerItem ?? false;
    _labelProtocol = i?.labelProtocol ?? PosLabelPrinterProtocol.tspl;
    _labelTemplateId = i?.labelTemplateId ?? 'roll_1_50x30';
    _labelGapMm = i?.labelGapMm ?? 2.0;
    _labelShiftRightMm = i?.labelShiftRightMm ?? 3.0;
    _labelMarginRightMm = i?.labelMarginRightMm ?? 2.0;
    _labelMarginTopMm = i?.labelMarginTopMm ?? 2.0;
    _labelMarginBottomMm = i?.labelMarginBottomMm ?? 2.0;
    _labelFontScale = i?.labelFontScale ?? 1.2;
    _labelShowHeader = i?.labelShowHeader ?? true;
    _labelShowTable = i?.labelShowTable ?? true;
    _labelShowOrderNo = i?.labelShowOrderNo ?? true;
    _labelShowToppings = i?.labelShowToppings ?? true;
    _labelShowNote = i?.labelShowNote ?? true;
    _labelShowQty = i?.labelShowQty ?? true;
    _btAddr = i?.bluetoothAddress;
    _btName = i?.bluetoothName;
    final savedUsb = (i?.usbDeviceName ?? '').trim();
    if (savedUsb.isNotEmpty) {
      _usbStableId = savedUsb;
      _usbDisplayLabel = savedUsb;
    }
    PosThermalPrinterService.isSunmiDevice().then((v) {
      if (mounted) setState(() => _isSunmi = v);
    });
    if (_type == PosThermalConnectionType.usb) {
      unawaited(_refreshUsbDevices(selectSaved: true));
    }
  }

  bool _isLabelDefault(PosLocalPrinterProfile? i) =>
      i?.kind == PosLocalPrinterKind.label;

  Set<String> _defaultRoles(PosLocalPrinterKind kind) => kind ==
          PosLocalPrinterKind.label
      ? {PosLocalPrinterRoles.barcodeLabel, PosLocalPrinterRoles.kitchenLabel}
      : {PosLocalPrinterRoles.saleInvoice};

  @override
  void dispose() {
    _name.dispose();
    _lanHost.dispose();
    _lanPort.dispose();
    _usbName.dispose();
    _btMac.dispose();
    _feedBeforeCut.dispose();
    super.dispose();
  }

  void _applySunmiDefaults() {
    _brand = PosThermalPrinterBrand.sunmi;
    _textMode = PosThermalTextMode.utf8;
    _paperSize = _paperSize.isEmpty ? 'K80' : _paperSize;
  }

  void _setKind(PosLocalPrinterKind kind) {
    setState(() {
      _kind = kind;
      _roles = _defaultRoles(kind);
      if (_name.text.trim().isEmpty ||
          _name.text == 'Máy in nhiệt nội bộ' ||
          _name.text == 'Máy in tem nội bộ' ||
          _name.text == 'Máy in nội bộ') {
        _name.text = kind == PosLocalPrinterKind.label
            ? 'Máy in tem nội bộ'
            : 'Máy in nhiệt nội bộ';
      }
    });
  }

  Future<void> _pickBluetooth() async {
    setState(() => _testing = true);
    String? hint;
    try {
      final r = await PosThermalPrinterService.listBluetoothDevicesWithHint();
      _btDevices = r.devices;
      hint = r.hint;
    } finally {
      if (mounted) setState(() => _testing = false);
    }
    if (!mounted) return;
    if (_btDevices.isEmpty) {
      final open = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Không thấy máy in Bluetooth')),
          content: Text(
            tr(hint ??
                'Ghép máy in trong Cài đặt Bluetooth (PIN 0000/1234), rồi thử lại. Hoặc nhập địa chỉ MAC bên dưới.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'mac'),
              child: Text(tr('Nhập MAC')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'settings'),
              child: Text(tr('Mở Bluetooth')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'retry'),
              child: Text(tr('Thử lại')),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (open == 'settings') {
        await PosPrinterHardware.openBluetoothSettings();
        return;
      }
      if (open == 'retry') {
        await _pickBluetooth();
        return;
      }
      // mac: focus field — already visible
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.5,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('Chọn máy in Bluetooth đã ghép'),
                        style: const TextStyle(
                            fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: tr('Cài đặt BT'),
                      onPressed: () async {
                        await PosPrinterHardware.openBluetoothSettings();
                      },
                      icon: const Icon(Icons.settings_bluetooth),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  children: [
                    for (final d in _btDevices)
                      ListTile(
                        title: Text(tr(d['name'] ?? 'Máy in')),
                        subtitle: Text(tr(d['address'] ?? '')),
                        onTap: () {
                          setState(() {
                            _btAddr = d['address'];
                            _btName = d['name'];
                            _btMac.text = d['address'] ?? '';
                          });
                          Navigator.pop(ctx);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refreshUsbDevices({bool selectSaved = false}) async {
    if (!PosUsbPrinter.isSupported) return;
    setState(() => _usbScanning = true);
    try {
      final list = await PosUsbPrinter.listDevices();
      if (!mounted) return;
      setState(() {
        _usbDevices = list;
        if (selectSaved && (_usbName.text).trim().isNotEmpty) {
          final hit = PosUsbPrinter.matchInList(list, _usbName.text) ??
              list
                  .where((d) =>
                      d.stableId == _usbStableId ||
                      d.deviceName == _usbStableId)
                  .firstOrNull;
          if (hit != null) {
            _usbStableId = hit.stableId;
            _usbDisplayLabel = hit.displayName;
            _usbName.text = hit.savedRef;
          }
        }
      });
    } finally {
      if (mounted) setState(() => _usbScanning = false);
    }
  }

  Future<void> _pickUsb() async {
    await _refreshUsbDevices();
    if (!mounted) return;
    final diag = await PosPrinterHardware.usbDiagnostics();
    final hint = diag['hint']?.toString();
    if (_usbDevices.isEmpty) {
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Không thấy cổng USB')),
          content: Text(
            tr(
              '${hint ?? ''}\n\n'
              '• Cắm máy in vào cổng USB Type-A phía sau/máy POS (không cắm vào cổng đang nối PC).\n'
              '• Bật nguồn máy in, chờ 3–5 giây rồi bấm Thử lại.\n'
              '• Nếu vẫn trống: dùng Bluetooth (ghép trước) hoặc LAN (IP máy in).',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'close'),
              child: Text(tr('Đóng')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'retry'),
              child: Text(tr('Thử lại')),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (action == 'retry') {
        await _pickUsb();
      }
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.55,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr('Chọn cổng / máy in USB'),
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: tr('Làm mới'),
                      onPressed: () async {
                        await _refreshUsbDevices();
                        if (ctx.mounted) (ctx as Element).markNeedsBuild();
                      },
                      icon: _usbScanning
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
              if (hint != null && hint.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    tr(hint),
                    style: TextStyle(
                        fontSize: 12, color: Colors.orange.shade800),
                  ),
                ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: _usbDevices.length,
                  itemBuilder: (_, i) {
                    final d = _usbDevices[i];
                    final selected = d.stableId == _usbStableId;
                    return ListTile(
                      selected: selected,
                      leading: Icon(
                        Icons.usb,
                        color: selected ? PosTheme.kiotBlue : null,
                      ),
                      title: Text(tr(d.displayName)),
                      subtitle: Text(
                        tr(
                          '${d.deviceName}\n'
                          'VID=${d.vendorId.toRadixString(16).toUpperCase()} '
                          'PID=${d.productId.toRadixString(16).toUpperCase()}'
                          '${d.hasPermission ? '' : ' · chưa cấp quyền'}',
                        ),
                      ),
                      isThreeLine: true,
                      trailing: selected
                          ? const Icon(Icons.check_circle,
                              color: PosTheme.kiotBlue)
                          : null,
                      onTap: () async {
                        var device = d;
                        if (!device.hasPermission) {
                          final ok =
                              await PosUsbPrinter.requestPermission(device);
                          if (!ok) {
                            NotificationOverlayManager().showError(
                              title: 'Chưa cấp quyền USB',
                              message: tr('Cho phép truy cập thiết bị để in'),
                            );
                            return;
                          }
                          await _refreshUsbDevices();
                          device = _usbDevices
                                  .where((x) => x.stableId == d.stableId)
                                  .firstOrNull ??
                              d;
                        }
                        if (!mounted) return;
                        setState(() {
                          _usbStableId = device.stableId;
                          _usbDisplayLabel = device.displayName;
                          // Lưu stableId|deviceName — phân biệt nhiều máy cùng model.
                          _usbName.text = device.savedRef;
                          if (_name.text.trim().isEmpty ||
                              _name.text == 'Máy in nhiệt nội bộ' ||
                              _name.text == 'Máy in tem nội bộ') {
                            _name.text =
                                device.productName?.trim().isNotEmpty == true
                                    ? device.productName!.trim()
                                    : 'USB ${device.vendorId}:${device.productId}';
                          }
                        });
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PosLocalPrinterProfile _buildDraft({required bool forTest}) {
    final base = widget.initial ??
        PosLocalPrinterProfile(
          id: _newId(),
          name: _name.text.trim().isEmpty
              ? (_isLabel ? 'Máy in tem nội bộ' : 'Máy in nhiệt nội bộ')
              : _name.text.trim(),
        );
    final port = int.tryParse(_lanPort.text.trim()) ?? 9100;
    final feed = int.tryParse(_feedBeforeCut.text.trim()) ?? 1;
    final mac = _btMac.text.trim().isNotEmpty ? _btMac.text.trim() : _btAddr;
    final allowed = PosLocalPrinterRoles.forKind(_kind).toSet();
    final roles = _roles.where(allowed.contains).toSet();
    if (_type == PosThermalConnectionType.sunmi) {
      _applySunmiDefaults();
    }
    return base.copyWith(
      name: _name.text.trim().isEmpty ? base.name : _name.text.trim(),
      enabled: forTest ? true : _enabled,
      kind: _kind,
      roles: roles.isEmpty ? _defaultRoles(_kind) : roles,
      connectionType: _type,
      printerBrand: _isLabel
          ? PosThermalPrinterBrand.zywell
          : (_type == PosThermalConnectionType.sunmi
              ? PosThermalPrinterBrand.sunmi
              : _brand),
      textMode: _type == PosThermalConnectionType.sunmi
          ? PosThermalTextMode.utf8
          : _textMode,
      paperSize: _paperSize,
      bluetoothAddress:
          _type == PosThermalConnectionType.bluetooth ? mac : null,
      bluetoothName:
          _type == PosThermalConnectionType.bluetooth ? _btName : null,
      lanHost: _type == PosThermalConnectionType.lan &&
              _lanHost.text.trim().isNotEmpty
          ? _lanHost.text.trim()
          : null,
      lanPort: port,
      usbDeviceName: _type == PosThermalConnectionType.usb
          ? ((_usbStableId ?? _usbName.text).trim().isNotEmpty
              ? (_usbStableId ?? _usbName.text).trim()
              : null)
          : null,
      feedBeforeCut: feed < 0 ? 1 : feed,
      partialCut: !_isLabel,
      cutPerItem: !_isLabel && _cutPerItem,
      openCashDrawer: !_isLabel && _openCashDrawer,
      openDrawerCashOnly: _openDrawerCashOnly,
      beepOnPrint: !_isLabel && _beepOnPrint,
      labelProtocol: _labelProtocol,
      labelTemplateId: _labelTemplateId,
      labelGapMm: _labelGapMm,
      labelShiftRightMm: _labelShiftRightMm,
      labelMarginRightMm: _labelMarginRightMm,
      labelMarginTopMm: _labelMarginTopMm,
      labelMarginBottomMm: _labelMarginBottomMm,
      labelFontScale: _labelFontScale,
      labelShowHeader: _labelShowHeader,
      labelShowTable: _labelShowTable,
      labelShowOrderNo: _labelShowOrderNo,
      labelShowToppings: _labelShowToppings,
      labelShowNote: _labelShowNote,
      labelShowQty: _labelShowQty,
    );
  }

  Future<void> _testPrint() async {
    if (_type == PosThermalConnectionType.bluetooth) {
      final mac = _btMac.text.trim().isNotEmpty ? _btMac.text.trim() : _btAddr;
      if (mac == null || mac.isEmpty) {
        NotificationOverlayManager().showError(
          title: 'Thiếu Bluetooth',
          message: tr('Chọn hoặc nhập địa chỉ MAC máy in'),
        );
        return;
      }
    }
    if (_type == PosThermalConnectionType.lan &&
        _lanHost.text.trim().isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Thiếu IP',
        message: tr('Nhập địa chỉ IP máy in LAN'),
      );
      return;
    }
    if (_type == PosThermalConnectionType.usb &&
        (_usbStableId ?? _usbName.text).trim().isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Chưa chọn cổng USB',
        message: tr('Bấm chọn máy in USB đang cắm'),
      );
      return;
    }
    setState(() => _testing = true);
    final draft = _buildDraft(forTest: true);
    final ok = _isLabel
        ? await PosLabelPrinterService.testPrint(draft.toLabelSettings())
        : await PosThermalPrinterService.testPrint(draft.toThermalSettings());
    if (!mounted) return;
    setState(() => _testing = false);
    if (ok) {
      NotificationOverlayManager()
          .showSuccess(title: 'In thử', message: tr('Đã gửi lệnh in thử'));
    } else {
      NotificationOverlayManager().showError(
        title: 'In thử thất bại',
        message: tr('Kiểm tra kết nối máy in và quyền Bluetooth/USB'),
      );
    }
  }

  void _save() {
    if (_type == PosThermalConnectionType.bluetooth) {
      final mac = _btMac.text.trim().isNotEmpty ? _btMac.text.trim() : _btAddr;
      if (mac == null || mac.isEmpty) {
        NotificationOverlayManager().showError(
          title: 'Thiếu Bluetooth',
          message: tr('Chọn hoặc nhập địa chỉ MAC máy in'),
        );
        return;
      }
    }
    if (_type == PosThermalConnectionType.lan &&
        _lanHost.text.trim().isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Thiếu IP',
        message: tr('Nhập địa chỉ IP máy in LAN'),
      );
      return;
    }
    if (_type == PosThermalConnectionType.usb &&
        (_usbStableId ?? _usbName.text).trim().isEmpty) {
      NotificationOverlayManager().showError(
        title: 'Chưa chọn cổng USB',
        message: tr('Bấm chọn máy in USB đang cắm'),
      );
      return;
    }
    Navigator.pop(context, _buildDraft(forTest: false));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final roleOptions = PosLocalPrinterRoles.forKind(_kind);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr(widget.initial == null
                  ? 'Thêm máy in nội bộ'
                  : 'Sửa máy in nội bộ'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: InputDecoration(
                labelText: tr('Tên máy'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            SegmentedButton<PosLocalPrinterKind>(
              segments: [
                ButtonSegment(
                  value: PosLocalPrinterKind.receipt,
                  label: Text(tr('Máy in nhiệt')),
                  icon: const Icon(Icons.receipt_long, size: 18),
                ),
                ButtonSegment(
                  value: PosLocalPrinterKind.label,
                  label: Text(tr('Máy in tem')),
                  icon: const Icon(Icons.label_outline, size: 18),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => _setKind(s.first),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Bật máy in')),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            DropdownButtonFormField<PosThermalConnectionType>(
              value: _type,
              decoration: InputDecoration(
                labelText: tr('Kết nối'),
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final e in PosThermalConnectionType.values)
                  if (e != PosThermalConnectionType.sunmi || _isSunmi)
                    DropdownMenuItem(value: e, child: Text(tr(e.label))),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _type = v;
                  if (v == PosThermalConnectionType.sunmi) {
                    _applySunmiDefaults();
                  }
                });
                if (v == PosThermalConnectionType.usb) {
                  unawaited(_refreshUsbDevices(selectSaved: true));
                }
              },
            ),
            if (_type == PosThermalConnectionType.lan) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _lanHost,
                decoration: InputDecoration(
                  labelText: tr('IP LAN'),
                  hintText: tr('192.168.1.100'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _lanPort,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr('Cổng'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            if (_type == PosThermalConnectionType.bluetooth) ...[
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
                  onPressed: _testing ? null : _pickBluetooth,
                ),
                onTap: _testing ? null : _pickBluetooth,
              ),
              TextField(
                controller: _btMac,
                decoration: InputDecoration(
                  labelText: tr('Địa chỉ MAC (nhập tay nếu cần)'),
                  hintText: tr('AA:BB:CC:DD:EE:FF'),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) =>
                    _btAddr = v.trim().isEmpty ? _btAddr : v.trim(),
              ),
            ],
            if (_type == PosThermalConnectionType.usb) ...[
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Cổng / máy in USB')),
                subtitle: Text(
                  tr((_usbDisplayLabel ?? '').isNotEmpty
                      ? '$_usbDisplayLabel\nĐã nhớ — lần sau tự dùng máy này'
                      : 'Chưa chọn — bấm để liệt kê cổng USB đang cắm'),
                ),
                isThreeLine: (_usbDisplayLabel ?? '').isNotEmpty,
                trailing: IconButton(
                  icon: _usbScanning
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.usb),
                  onPressed: _testing ? null : _pickUsb,
                ),
                onTap: _testing ? null : _pickUsb,
              ),
              Text(
                tr('Mỗi máy USB lưu VID/PID/serial riêng — nhiều máy không đá nhau.'),
                style: TextStyle(fontSize: 12, color: PosTheme.textSecondary),
              ),
            ],
            if (_type == PosThermalConnectionType.sunmi)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.print, color: PosTheme.kiotBlue),
                title: Text(tr('Máy in Sunmi tích hợp')),
                subtitle: Text(
                  tr('Tự dùng máy in trong máy — không cần BT/LAN/hãng/chế độ chữ.'),
                ),
              ),
            if (_isLabel) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _labelTemplateId,
                decoration: InputDecoration(
                  labelText: tr('Khổ tem'),
                  border: const OutlineInputBorder(),
                ),
                items: posBarcodeLabelTemplates
                    .map((t) => DropdownMenuItem(
                          value: t.id,
                          child: Text(
                            tr('${t.name} (${t.sizeLabel})'),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _labelTemplateId = v);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<PosLabelPrinterProtocol>(
                value: _labelProtocol,
                decoration: InputDecoration(
                  labelText: tr('Giao thức'),
                  border: const OutlineInputBorder(),
                ),
                items: PosLabelPrinterProtocol.values
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(tr(p.label)),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _labelProtocol = v);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<double>(
                value: _labelGapMm,
                decoration: InputDecoration(
                  labelText: tr('Khoảng cách tem (mm)'),
                  border: const OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 2.0, child: Text('2 mm')),
                  DropdownMenuItem(value: 3.0, child: Text('3 mm')),
                  DropdownMenuItem(value: 4.0, child: Text('4 mm')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _labelGapMm = v);
                },
              ),
              const SizedBox(height: 10),
              Text(
                tr('Lề nội dung tem (mm)'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<double>(
                      value: _labelMarginTopMm,
                      decoration: InputDecoration(
                        labelText: tr('Trên'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _mmItems,
                      onChanged: (v) {
                        if (v != null) setState(() => _labelMarginTopMm = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<double>(
                      value: _labelMarginBottomMm,
                      decoration: InputDecoration(
                        labelText: tr('Dưới'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _mmItems,
                      onChanged: (v) {
                        if (v != null) {
                          setState(() => _labelMarginBottomMm = v);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<double>(
                      value: _labelShiftRightMm,
                      decoration: InputDecoration(
                        labelText: tr('Trái'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                        helperText: tr('Tem lệch trái: thử 3–5'),
                      ),
                      items: _mmItems,
                      onChanged: (v) {
                        if (v != null) setState(() => _labelShiftRightMm = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<double>(
                      value: _labelMarginRightMm,
                      decoration: InputDecoration(
                        labelText: tr('Phải'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _mmItems,
                      onChanged: (v) {
                        if (v != null) setState(() => _labelMarginRightMm = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<double>(
                value: _labelFontScale,
                decoration: InputDecoration(
                  labelText: tr('Cỡ chữ tem'),
                  border: const OutlineInputBorder(),
                  helperText: tr('50×30 nên ≥ 1.2'),
                ),
                items: [
                  DropdownMenuItem(value: 0.9, child: Text(tr('Nhỏ (0.9)'))),
                  DropdownMenuItem(value: 1.0, child: Text(tr('Vừa (1.0)'))),
                  DropdownMenuItem(value: 1.2, child: Text(tr('Lớn (1.2)'))),
                  DropdownMenuItem(value: 1.4, child: Text(tr('Rất lớn (1.4)'))),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _labelFontScale = v);
                },
              ),
              const SizedBox(height: 8),
              Text(
                tr('Thông số in trên tem'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Tiêu đề TEM LY')),
                value: _labelShowHeader,
                onChanged: (v) => setState(() => _labelShowHeader = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Bàn / khu')),
                value: _labelShowTable,
                onChanged: (v) => setState(() => _labelShowTable = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Số hóa đơn')),
                value: _labelShowOrderNo,
                onChanged: (v) => setState(() => _labelShowOrderNo = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Topping')),
                value: _labelShowToppings,
                onChanged: (v) => setState(() => _labelShowToppings = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Ghi chú')),
                value: _labelShowNote,
                onChanged: (v) => setState(() => _labelShowNote = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Số lượng (SL)')),
                value: _labelShowQty,
                onChanged: (v) => setState(() => _labelShowQty = v),
              ),
            ] else ...[
              if (_type != PosThermalConnectionType.sunmi) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<PosThermalPrinterBrand>(
                  value: _brand,
                  decoration: InputDecoration(
                    labelText: tr('Hãng máy in'),
                    border: const OutlineInputBorder(),
                  ),
                  items: PosThermalPrinterBrand.values
                      .map((b) => DropdownMenuItem(
                            value: b,
                            child: Text(tr(b.label)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _brand = v);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<PosThermalTextMode>(
                  value: _textMode,
                  decoration: InputDecoration(
                    labelText: tr('Chế độ chữ'),
                    helperText: tr(
                        'XP-80C / Zywell: «In ảnh» hoặc «Tự động». UTF-8 thường lỗi font tiếng Việt.'),
                    border: const OutlineInputBorder(),
                  ),
                  items: PosThermalTextMode.values
                      .map((m) => DropdownMenuItem(
                            value: m,
                            child: Text(tr(m.label)),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _textMode = v);
                  },
                ),
              ],
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _paperSize,
                decoration: InputDecoration(
                  labelText: tr('Khổ giấy'),
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(value: 'K58', child: Text(tr('K58 (58mm)'))),
                  DropdownMenuItem(value: 'K80', child: Text(tr('K80 (80mm)'))),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _paperSize = v);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _feedBeforeCut,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr('Số dòng giãn cách trước khi cắt'),
                  helperText: tr('Mặc định 1'),
                  border: const OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('In bếp: cắt từng món')),
                subtitle: Text(tr('Mỗi món một phiếu — bếp treo/giao từng phần')),
                value: _cutPerItem,
                onChanged: (v) => setState(() => _cutPerItem = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('Mở két tiền khi in hóa đơn')),
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
                value: _beepOnPrint,
                onChanged: (v) => setState(() => _beepOnPrint = v),
              ),
            ],
            const SizedBox(height: 8),
            Text(tr('Vai trò chứng từ'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final role in roleOptions)
                  FilterChip(
                    label: Text(tr(PosLocalPrinterRoles.label(role))),
                    selected: _roles.contains(role),
                    onSelected: (on) {
                      setState(() {
                        if (on) {
                          _roles.add(role);
                        } else {
                          _roles.remove(role);
                        }
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _testing ? null : _testPrint,
              icon: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print),
              label: Text(tr('In thử')),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
              child: Text(tr('Lưu')),
            ),
          ],
        ),
      ),
    );
  }
}

String _newId() {
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
  return 'loc-$t';
}
