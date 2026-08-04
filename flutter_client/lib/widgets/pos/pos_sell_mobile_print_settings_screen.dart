import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../models/pos_print_template.dart';
import '../../screens/pos_print_templates_screen.dart';
import '../../services/api_service.dart';
import '../../screens/pos/pos_store_printers_screen.dart';
import '../../utils/pos_barcode_print.dart';
import '../../utils/pos_label_printer_service.dart';
import '../../utils/pos_label_printer_settings.dart';
import '../../utils/pos_print_template_loader.dart';
import '../../utils/pos_sell_print_settings.dart';
import '../../utils/pos_printer_transport.dart';
import '../../utils/pos_thermal_printer_service.dart';
import '../../utils/pos_thermal_printer_settings.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/safe_navigator.dart';
import '../hrm_page_chrome.dart';
import '../notification_overlay.dart';
import 'pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

const _blue = PosTheme.kiotBlue;

/// Thiết lập in + máy in nhiệt — giao diện mobile full-screen.
class PosSellMobilePrintSettingsScreen extends StatefulWidget {
  const PosSellMobilePrintSettingsScreen({
    super.key,
    required this.initialPrintSettings,
    required this.initialThermalSettings,
  });

  final PosSellPrintSettings initialPrintSettings;
  final PosThermalPrinterSettings initialThermalSettings;

  @override
  State<PosSellMobilePrintSettingsScreen> createState() =>
      _PosSellMobilePrintSettingsScreenState();
}

class _PosSellMobilePrintSettingsScreenState
    extends State<PosSellMobilePrintSettingsScreen> {
  final _api = ApiService();
  late PosSellPrintSettings _print = widget.initialPrintSettings;
  late PosThermalPrinterSettings _thermal;
  PosLabelPrinterSettings _label = const PosLabelPrinterSettings();
  List<PosPrintTemplate> _templates = [];
  List<PosPrintTemplate> _warehouseTemplates = [];
  List<Map<String, String>> _btDevices = [];
  List<Map<String, String>> _labelBtDevices = [];
  bool _loading = false;
  bool _testing = false;
  bool _testingLabel = false;
  bool _isSunmi = false;

  final _lanHostCtrl = TextEditingController();
  final _lanPortCtrl = TextEditingController(text: tr('9100'));
  final _usbNameCtrl = TextEditingController();
  final _labelLanHostCtrl = TextEditingController();
  final _labelLanPortCtrl = TextEditingController(text: tr('9100'));

  @override
  void initState() {
    super.initState();
    _thermal = widget.initialThermalSettings;
    _lanHostCtrl.text = _thermal.lanHost ?? '';
    _lanPortCtrl.text = '${_thermal.lanPort}';
    _usbNameCtrl.text = _thermal.usbDeviceName ?? '';
    PosLabelPrinterSettings.load().then((lp) {
      if (!mounted) return;
      setState(() {
        _label = lp;
        _labelLanHostCtrl.text = lp.lanHost ?? '';
        _labelLanPortCtrl.text = '${lp.lanPort}';
      });
    });
    _loadTemplates();
    _loadBluetoothInBackground();
    PosThermalPrinterService.isSunmiDevice().then((v) async {
      if (!mounted) return;
      setState(() => _isSunmi = v);
      if (!v) return;
      // Tự chọn máy in Sunmi tích hợp nếu chưa cấu hình BT/LAN.
      final hasBt = _thermal.bluetoothAddress?.trim().isNotEmpty == true;
      final hasLan = _thermal.lanHost?.trim().isNotEmpty == true;
      final alreadySunmi =
          _thermal.connectionType == PosThermalConnectionType.sunmi;
      if (!hasBt && !hasLan && (!alreadySunmi || !_thermal.enabled)) {
        setState(() {
          _thermal = _thermal.copyWith(
            enabled: true,
            connectionType: PosThermalConnectionType.sunmi,
            printerBrand: PosThermalPrinterBrand.sunmi,
            textMode: PosThermalTextMode.utf8,
            feedBeforeCut: _thermal.feedBeforeCut < 14 ? 14 : _thermal.feedBeforeCut,
          );
        });
      } else if (alreadySunmi) {
        setState(() {
          _thermal = _thermal.copyWith(
            textMode: _thermal.textMode == PosThermalTextMode.image
                ? PosThermalTextMode.utf8
                : _thermal.textMode,
            feedBeforeCut:
                _thermal.feedBeforeCut < 14 ? 14 : _thermal.feedBeforeCut,
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _lanHostCtrl.dispose();
    _lanPortCtrl.dispose();
    _usbNameCtrl.dispose();
    _labelLanHostCtrl.dispose();
    _labelLanPortCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBluetoothInBackground() async {
    final devices = await PosThermalPrinterService.listBluetoothDevices();
    if (mounted) setState(() => _btDevices = devices);
  }

  Future<void> _loadTemplates() async {
    setState(() => _loading = true);
    try {
      _templates = await loadPosPrintTemplates(_api, PosPrintDocumentTypes.saleInvoice)
          .timeout(const Duration(seconds: 12), onTimeout: () => <PosPrintTemplate>[]);
      _warehouseTemplates =
          await loadPosPrintTemplates(_api, PosPrintDocumentTypes.stockIssue)
              .timeout(const Duration(seconds: 12), onTimeout: () => <PosPrintTemplate>[]);
    } catch (e) {
      debugPrint('load print settings failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _load() async {
    await _loadTemplates();
    await _loadBluetoothInBackground();
  }

  String? _resolveTemplateId() {
    if (_templates.isEmpty) return null;
    final saved = _print.templateId;
    if (saved != null && _templates.any((t) => t.id == saved)) return saved;
    return _templates.where((t) => t.isDefault).firstOrNull?.id ??
        _templates.first.id;
  }

  String? _resolveWarehouseTemplateId() {
    if (_warehouseTemplates.isEmpty) return null;
    final saved = _print.warehouseTemplateId;
    if (saved != null && _warehouseTemplates.any((t) => t.id == saved)) {
      return saved;
    }
    return _warehouseTemplates.where((t) => t.isDefault).firstOrNull?.id ??
        _warehouseTemplates.first.id;
  }

  Future<void> _pickTemplate({
    required String title,
    required List<PosPrintTemplate> templates,
    required String? selectedId,
    required ValueChanged<String> onPick,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tr(title),
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            ...templates.map(
              (t) => ListTile(
                title: Text(tr(t.name)),
                subtitle: Text(
                  tr(PosPrintPaperSizes.labels[t.paperSize] ?? t.paperSize),
                ),
                trailing: selectedId == t.id
                    ? const Icon(Icons.check, color: _blue)
                    : null,
                onTap: () {
                  onPick(t.id);
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
    final port = int.tryParse(_lanPortCtrl.text.trim()) ?? 9100;
    _thermal = _thermal.copyWith(
      lanHost: _lanHostCtrl.text.trim(),
      lanPort: port,
      usbDeviceName: _usbNameCtrl.text.trim(),
    );
    await _print.save();
    await _thermal.save();
    final labelPort = int.tryParse(_labelLanPortCtrl.text.trim()) ?? 9100;
    _label = _label.copyWith(
      lanHost: _labelLanHostCtrl.text.trim(),
      lanPort: labelPort,
    );
    await _label.save();
    if (!mounted) return;
    NotificationOverlayManager()
        .showSuccess(title: 'Đã lưu', message: tr('Thiết lập in đã được cập nhật'));
    // Settings Hub nhúng màn này không push route — Navigator.pop sẽ gỡ MainLayout → màn đen.
    SafeNavigator.popPageIfPushed(context, (_print, _thermal));
  }

  Future<void> _testPrint() async {
    setState(() => _testing = true);
    final port = int.tryParse(_lanPortCtrl.text.trim()) ?? 9100;
    final draft = _thermal.copyWith(
      enabled: true,
      lanHost: _lanHostCtrl.text.trim(),
      lanPort: port,
      usbDeviceName: _usbNameCtrl.text.trim(),
    );
    final ok = await PosThermalPrinterService.testPrint(draft);
    if (!mounted) return;
    setState(() => _testing = false);
    if (ok) {
      NotificationOverlayManager()
          .showSuccess(title: 'In thử', message: tr('Đã gửi lệnh in thử'));
    } else {
      NotificationOverlayManager().showError(
        title: 'In thử thất bại',
        message: draft.connectionType == PosThermalConnectionType.usb
            ? tr('USB OTG chưa hỗ trợ. Chọn Bluetooth, LAN hoặc Sunmi.')
            : tr('Kiểm tra kết nối máy in và quyền Bluetooth/USB'),
      );
    }
  }

  Future<void> _probeTextModes() async {
    setState(() => _testing = true);
    final port = int.tryParse(_lanPortCtrl.text.trim()) ?? 9100;
    final draft = _thermal.copyWith(
      enabled: true,
      lanHost: _lanHostCtrl.text.trim(),
      lanPort: port,
      usbDeviceName: _usbNameCtrl.text.trim(),
    );
    final okCount = await PosThermalPrinterService.probeTextModes(draft);
    if (!mounted) return;
    setState(() => _testing = false);

    if (okCount <= 0) {
      NotificationOverlayManager().showError(
        title: 'Thử chế độ chữ thất bại',
        message: tr('Không gửi được phiếu thử. Kiểm tra kết nối máy in.'),
      );
      return;
    }

    final chosen = await showDialog<PosThermalTextMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Chọn chế độ chữ đúng')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('Đã in $okCount phiếu thử. Chọn phiếu tiếng Việt đọc đúng nhất:'),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              for (final m in [
                PosThermalTextMode.image,
                PosThermalTextMode.tcvn3,
                PosThermalTextMode.cp1258,
                PosThermalTextMode.utf8,
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr(m.label)),
                  subtitle: Text(m.key, style: const TextStyle(fontSize: 11)),
                  onTap: () => Navigator.pop(ctx, m),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Để sau')),
          ),
        ],
      ),
    );
    if (!mounted || chosen == null) return;
    setState(() => _thermal = _thermal.copyWith(textMode: chosen));
    NotificationOverlayManager().showSuccess(
      title: 'Đã chọn chế độ chữ',
      message: tr('${chosen.label} — bấm Lưu để áp dụng'),
    );
  }

  Future<void> _testLabelPrint() async {
    setState(() => _testingLabel = true);
    final port = int.tryParse(_labelLanPortCtrl.text.trim()) ?? 9100;
    final draft = _label.copyWith(
      enabled: true,
      lanHost: _labelLanHostCtrl.text.trim(),
      lanPort: port,
    );
    final ok = await PosLabelPrinterService.testPrint(draft);
    if (!mounted) return;
    setState(() => _testingLabel = false);
    if (ok) {
      NotificationOverlayManager()
          .showSuccess(title: 'In thử tem', message: tr('Đã gửi tem mẫu'));
    } else {
      NotificationOverlayManager().showError(
        title: 'In thử tem thất bại',
        message: tr('Kiểm tra kết nối và khổ giấy tem'),
      );
    }
  }

  Future<void> _openTemplateEditor({String? documentType}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PosPrintTemplatesScreen(
          embeddedInSettings: true,
          initialDocumentType: documentType,
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final embedded = HrmPageChrome.isEmbedded;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: embedded
          ? null
          : AppBar(
              title: Text(tr('Thiết lập in')),
              backgroundColor: Colors.white,
              foregroundColor: PosTheme.textPrimary,
              elevation: 0,
              actions: [
                IconButton(
                  tooltip: tr('Máy in cửa hàng'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PosStorePrintersScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.print_outlined),
                ),
                TextButton(
                  onPressed: _loading ? null : _save,
                  child: Text(tr('Lưu'),
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
      body: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              children: [
                if (embedded) ...[
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const PosStorePrintersScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.print_outlined, size: 18),
                        label: Text(tr('Máy in cửa hàng')),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: _loading ? null : _save,
                        child: Text(tr('Lưu')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                _sectionTitle('Khi thanh toán'),
                _card([
                  SwitchListTile(
                    title: Text(tr('In hóa đơn khi thanh toán')),
                    subtitle: Text(tr('Tự gửi lệnh in HĐ sau khi TT thành công'),
                      style: TextStyle(fontSize: 11),
                    ),
                    value: _print.autoPrint,
                    activeThumbColor: _blue,
                    onChanged: (v) =>
                        setState(() => _print = _print.copyWith(autoPrint: v)),
                  ),
                  SwitchListTile(
                    title: Text(tr('In tem ly khi thanh toán')),
                    subtitle: Text(
                      tr('Độc lập với in hóa đơn — tem món còn chờ in'),
                      style: TextStyle(fontSize: 11),
                    ),
                    value: _print.printCupOnCheckout,
                    activeThumbColor: _blue,
                    onChanged: (v) => setState(() {
                      _print = _print.copyWith(
                        printCupOnCheckout: v,
                        cupLabelPrintMode: v &&
                                _print.cupLabelPrintMode ==
                                    PosCupLabelPrintMode.off
                            ? PosCupLabelPrintMode.manual
                            : _print.cupLabelPrintMode,
                      );
                    }),
                  ),
                ]),
                _sectionTitle('Hóa đơn'),
                _card([
                  SwitchListTile(
                    title: Text(tr('Gộp hàng cùng loại khi in')),
                    value: _print.mergeSameItems,
                    activeThumbColor: _blue,
                    onChanged: (v) =>
                        setState(() => _print = _print.copyWith(mergeSameItems: v)),
                  ),
                  SwitchListTile(
                    title: Text(tr('In mã VietQR trên hóa đơn')),
                    subtitle: Text(tr('In QR tổng tiền đơn (cần thiết lập tài khoản NH)'),
                      style: TextStyle(fontSize: 11),
                    ),
                    value: _print.printVietQrOnReceipt,
                    activeThumbColor: _blue,
                    onChanged: (v) => setState(
                      () => _print = _print.copyWith(printVietQrOnReceipt: v),
                    ),
                  ),
                  ListTile(
                    title: Text(tr('Số bản in (liên)')),
                    trailing: DropdownButton<int>(
                      value: _print.copies.clamp(1, 10),
                      items: List.generate(
                        10,
                        (i) => DropdownMenuItem(value: i + 1, child: Text(tr('${i + 1}'))),
                      ),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _print = _print.copyWith(copies: v));
                      },
                    ),
                  ),
                  ListTile(
                    title: Text(tr('Mẫu in hóa đơn')),
                    subtitle: Text(
                      tr(_templates.isEmpty
                          ? 'Chưa có mẫu'
                          : _templates
                                  .where((t) => t.id == _resolveTemplateId())
                                  .firstOrNull
                                  ?.name ??
                              'Mặc định'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _templates.isEmpty
                        ? null
                        : () {
                            final id = _resolveTemplateId();
                            if (id == null) return;
                            setState(() => _print = _print.copyWith(templateId: id));
                            showModalBottomSheet<void>(
                              context: context,
                              builder: (ctx) => SafeArea(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text(tr('Chọn mẫu in'),
                                          style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                    ..._templates.map(
                                      (t) => ListTile(
                                        title: Text(tr(t.name)),
                                        subtitle: Text(
                                          tr(PosPrintPaperSizes.labels[t.paperSize] ??
                                              t.paperSize),
                                        ),
                                        trailing: _resolveTemplateId() == t.id
                                            ? const Icon(Icons.check, color: _blue)
                                            : null,
                                        onTap: () {
                                          setState(() =>
                                              _print = _print.copyWith(templateId: t.id));
                                          Navigator.pop(ctx);
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                  ),
                  ListTile(
                    leading: const Icon(Icons.design_services_outlined, color: _blue),
                    title: Text(tr('Thiết kế mẫu in (K58/K80/A5/A4)')),
                    subtitle: Text(tr('Mở trình soạn mẫu tối ưu mobile')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openTemplateEditor(),
                  ),
                ]),
                const SizedBox(height: 16),
                _sectionTitle('Tem dán ly (trà sữa)'),
                _card([
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(tr('In tem: tên món, topping, SL, giờ, bàn — in 1 lần như báo bếp (máy nhiệt/Sunmi).'),
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                  ...PosCupLabelPrintMode.values.map(
                    (mode) => RadioListTile<PosCupLabelPrintMode>(
                      title: Text(tr(mode.label)),
                      value: mode,
                      groupValue: _print.cupLabelPrintMode,
                      activeColor: _blue,
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _print = _print.copyWith(
                              cupLabelPrintMode: v,
                              printCupOnCheckout:
                                  v == PosCupLabelPrintMode.onCheckout
                                      ? true
                                      : _print.printCupOnCheckout,
                            ));
                      },
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.label_outline, color: _blue),
                    title: Text(tr('Thiết kế mẫu tem báo bếp / tem ly')),
                    subtitle: Text(tr('Sửa nhãn, bố cục in khi báo chế biến')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openTemplateEditor(
                      documentType: PosPrintDocumentTypes.kitchenLabel,
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                _sectionTitle('Tem dán sản phẩm'),
                _card([
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      tr('Tem mã hàng / mã vạch / giá dán lên sản phẩm. In từ danh mục hàng hóa.'),
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.view_week, color: _blue),
                    title: Text(tr('Thiết kế mẫu tem sản phẩm')),
                    subtitle: Text(tr('Tên hàng, barcode, mã, giá')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openTemplateEditor(
                      documentType: PosPrintDocumentTypes.barcodeLabel,
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                _sectionTitle('Phiếu báo xuất kho'),
                _card([
                  ...PosWarehousePrintMode.values.map(
                    (mode) => RadioListTile<PosWarehousePrintMode>(
                      title: Text(tr(mode.label)),
                      value: mode,
                      groupValue: _print.warehousePrintMode,
                      activeColor: _blue,
                      onChanged: (v) {
                        if (v == null) return;
                        setState(
                            () => _print = _print.copyWith(warehousePrintMode: v));
                      },
                    ),
                  ),
                  ListTile(
                    title: Text(tr('Mẫu in phiếu xuất kho')),
                    subtitle: Text(
                      tr(_warehouseTemplates.isEmpty
                          ? 'Chưa có mẫu'
                          : _warehouseTemplates
                                  .where((t) =>
                                      t.id == _resolveWarehouseTemplateId())
                                  .firstOrNull
                                  ?.name ??
                              'Mặc định'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _warehouseTemplates.isEmpty
                        ? null
                        : () async {
                            final id = _resolveWarehouseTemplateId();
                            if (id == null) return;
                            await _pickTemplate(
                              title: 'Chọn mẫu phiếu xuất kho',
                              templates: _warehouseTemplates,
                              selectedId: id,
                              onPick: (picked) => setState(() => _print =
                                  _print.copyWith(warehouseTemplateId: picked)),
                            );
                          },
                  ),
                  ListTile(
                    leading:
                        const Icon(Icons.design_services_outlined, color: _blue),
                    title: Text(tr('Thiết kế mẫu phiếu xuất kho')),
                    subtitle: Text(tr('K58/K80/A5/A4 — loại Phiếu xuất kho')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openTemplateEditor(
                      documentType: PosPrintDocumentTypes.stockIssue,
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                _sectionTitle('Máy in nhiệt'),
                _card([
                  SwitchListTile(
                    title: Text(tr('Dùng máy in nhiệt (cục bộ)')),
                    subtitle: Text(
                      tr('In trực tiếp trên thiết bị này (cùng mạng LAN). '
                      'In từ xa: dùng Máy in cửa hàng + Print Agent.'),
                      style: TextStyle(fontSize: 11),
                    ),
                    value: _thermal.enabled,
                    activeThumbColor: _blue,
                    onChanged: (v) => setState(() => _thermal = _thermal.copyWith(enabled: v)),
                  ),
                  if (_thermal.enabled) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: DropdownButtonFormField<String>(
                      value: _thermal.printerBrand.key,
                      decoration: InputDecoration(
                        labelText: tr('Hãng máy in'),
                        border: OutlineInputBorder(),
                        isDense: true,
                        helperText: tr('Zywell: in ảnh tiếng Việt chuẩn'),
                      ),
                      items: PosThermalPrinterBrand.values
                          .map((b) => DropdownMenuItem(
                                value: b.key,
                                child: Text(tr(b.label)),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _thermal = _thermal.copyWith(
                              printerBrand: PosThermalPrinterBrand.fromKey(v),
                            ));
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: DropdownButtonFormField<String>(
                      value: _thermal.textMode.key,
                      decoration: InputDecoration(
                        labelText: tr('Chế độ in chữ'),
                        border: OutlineInputBorder(),
                        isDense: true,
                        helperText: tr('Tự động: Zywell → in ảnh có dấu'),
                      ),
                      items: PosThermalTextMode.values
                          .map((m) => DropdownMenuItem(
                                value: m.key,
                                child: Text(tr(m.label)),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _thermal = _thermal.copyWith(
                              textMode: PosThermalTextMode.fromKey(v),
                            ));
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: DropdownButtonFormField<String>(
                      value: _thermal.paperSize,
                      decoration: InputDecoration(
                        labelText: tr('Khổ giấy'),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        DropdownMenuItem(value: 'K58', child: Text(tr('K58 (58mm)'))),
                        DropdownMenuItem(value: 'K80', child: Text(tr('K80 (80mm)'))),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _thermal = _thermal.copyWith(paperSize: v));
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Wrap(
                      spacing: 8,
                      children: PosThermalConnectionType.values.map((t) {
                        if (t == PosThermalConnectionType.sunmi && !_isSunmi) {
                          return const SizedBox.shrink();
                        }
                        final selected = _thermal.connectionType == t;
                        return ChoiceChip(
                          label: Text(tr(t.label)),
                          selected: selected,
                          selectedColor: PosTheme.kiotBlueLight,
                          onSelected: (_) => setState(
                            () => _thermal = _thermal.copyWith(
                              connectionType: t,
                              printerBrand: t == PosThermalConnectionType.sunmi
                                  ? PosThermalPrinterBrand.sunmi
                                  : _thermal.printerBrand,
                              enabled: t == PosThermalConnectionType.sunmi
                                  ? true
                                  : _thermal.enabled,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  if (_thermal.connectionType ==
                      PosThermalConnectionType.bluetooth) ...[
                    const Divider(height: 1),
                    ListTile(
                      title: Text(tr('Máy in Bluetooth đã ghép')),
                      subtitle: Text(
                        tr(_thermal.bluetoothName?.isNotEmpty == true
                            ? '${_thermal.bluetoothName} (${_thermal.bluetoothAddress})'
                            : 'Chưa chọn'),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        _btDevices =
                            await PosThermalPrinterService.listBluetoothDevices();
                        if (!mounted) return;
                        if (_btDevices.isEmpty) {
                          NotificationOverlayManager().showWarning(
                            title: 'Không có máy in',
                            message: tr('Ghép máy in Bluetooth trong Cài đặt Android trước'),
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
                                      style: TextStyle(
                                          fontSize: 17, fontWeight: FontWeight.w600)),
                                ),
                                ..._btDevices.map(
                                  (d) => ListTile(
                                    title: Text(tr(d['name'] ?? 'Máy in')),
                                    subtitle: Text(tr(d['address'] ?? '')),
                                    onTap: () {
                                      setState(() {
                                        _thermal = _thermal.copyWith(
                                          bluetoothName: d['name'],
                                          bluetoothAddress: d['address'],
                                        );
                                      });
                                      Navigator.pop(ctx);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                  if (_thermal.connectionType == PosThermalConnectionType.lan) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: TextField(
                        controller: _lanHostCtrl,
                        decoration: InputDecoration(
                          labelText: tr('IP máy in (LAN/WiFi)'),
                          hintText: tr('192.168.1.100'),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        controller: _lanPortCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: tr('Cổng (mặc định 9100)'),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                  if (_thermal.connectionType == PosThermalConnectionType.usb)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _usbNameCtrl,
                            decoration: InputDecoration(
                              labelText: tr('Tên thiết bị USB (tùy chọn)'),
                              helperText: tr(
                                'USB OTG ESC/POS chưa hỗ trợ. Sunmi: chọn cổng Sunmi. '
                                'Máy ngoài: dùng Bluetooth hoặc LAN.',
                              ),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            tr('Khuyến nghị: đổi sang Bluetooth / LAN / Sunmi để in tiếng Việt ổn định.'),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_thermal.connectionType == PosThermalConnectionType.sunmi)
                    ListTile(
                      leading: const Icon(Icons.print, color: _blue),
                      title: Text(tr('Máy in tích hợp Sunmi')),
                      subtitle: Text(
                        tr(_isSunmi
                            ? 'Đã nhận thiết bị Sunmi — bấm Lưu rồi In thử'
                            : 'Không nhận được máy in nội bộ trên thiết bị này'),
                      ),
                      trailing: TextButton(
                        onPressed: _testing
                            ? null
                            : () async {
                                final ok =
                                    await PosPrinterTransport.ensureSunmiBound();
                                if (!mounted) return;
                                if (ok) {
                                  NotificationOverlayManager().showSuccess(
                                    title: 'Đã kết nối máy in Sunmi',
                                    message: tr('Sẵn sàng in thử'),
                                  );
                                } else {
                                  NotificationOverlayManager().showError(
                                    title: 'Không kết nối được',
                                    message: tr('Kiểm tra máy in nội bộ Sunmi / giấy in'),
                                  );
                                }
                              },
                        child: Text(tr('Kết nối lại')),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(tr('Dòng trống trước cắt'),
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                        DropdownButton<int>(
                          value: _thermal.feedBeforeCut.clamp(5, 24),
                          items: List.generate(
                            20,
                            (i) => DropdownMenuItem(
                              value: i + 5,
                              child: Text(tr('${i + 5} dòng')),
                            ),
                          ),
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() =>
                                _thermal = _thermal.copyWith(feedBeforeCut: v));
                          },
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text(tr('Khuyến nghị Sunmi: 14–18 dòng — đẩy hết chữ khỏi đầu in trước khi cắt/xé.'),
                      style: TextStyle(fontSize: 12, color: PosTheme.textSecondary),
                    ),
                  ),
                  SwitchListTile(
                    title: Text(tr('Cắt một phần (partial)')),
                    subtitle: Text(
                      tr('Áp dụng máy nhiệt LAN/BT (ESC/POS). Sunmi dùng cutPaper; '
                      'máy không có dao cắt chỉ đẩy giấy để xé tay.'),
                    ),
                    value: _thermal.partialCut,
                    activeThumbColor: _blue,
                    onChanged: (v) =>
                        setState(() => _thermal = _thermal.copyWith(partialCut: v)),
                  ),
                  SwitchListTile(
                    title: Text(tr('Mở két tiền khi in hóa đơn')),
                    subtitle: Text(
                      tr('Gửi lệnh ESC p (LAN/BT) hoặc SunmiDrawer. '
                      'Két phải gắn cổng RJ11 máy in.'),
                    ),
                    value: _thermal.openCashDrawer,
                    activeThumbColor: _blue,
                    onChanged: (v) => setState(
                        () => _thermal = _thermal.copyWith(openCashDrawer: v)),
                  ),
                  if (_thermal.openCashDrawer)
                    SwitchListTile(
                      title: Text(tr('Chỉ mở két với tiền mặt')),
                      subtitle: Text(
                        tr('Tắt = mở két mọi hình thức thanh toán khi in HĐ.'),
                      ),
                      value: _thermal.openDrawerCashOnly,
                      activeThumbColor: _blue,
                      onChanged: (v) => setState(() =>
                          _thermal = _thermal.copyWith(openDrawerCashOnly: v)),
                    ),
                  SwitchListTile(
                    title: Text(tr('Bip loa máy in khi in')),
                    subtitle: Text(
                      tr('Lệnh ESC B — máy phải có loa (nhiều máy nhiệt / Sunmi).'),
                    ),
                    value: _thermal.beepOnPrint,
                    activeThumbColor: _blue,
                    onChanged: (v) => setState(
                        () => _thermal = _thermal.copyWith(beepOnPrint: v)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Column(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _testing ? null : _testPrint,
                          icon: _testing
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.print_outlined),
                          label: Text(tr('In thử')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _blue,
                            side: const BorderSide(color: _blue),
                            minimumSize: const Size(double.infinity, 56),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _testing ? null : _probeTextModes,
                          icon: const Icon(Icons.font_download_outlined),
                          label: Text(tr('Thử 4 chế độ chữ (sửa lỗi font)')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _blue,
                            side: BorderSide(color: _blue.withValues(alpha: 0.5)),
                            minimumSize: const Size(double.infinity, 48),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tr('In lần lượt Image / TCVN-3 / CP1258 / UTF-8 — chọn phiếu đọc đúng rồi Lưu.'),
                          style: TextStyle(
                            fontSize: 11,
                            color: PosTheme.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  ],
                ]),
                const SizedBox(height: 16),
                _sectionTitle('Máy in tem nhãn'),
                _card([
                  SwitchListTile(
                    title: Text(tr('Dùng máy in tem (cục bộ)')),
                    subtitle: Text(tr('Dự phòng — khuyến nghị thêm máy tem trong Máy in cửa hàng'),
                      style: TextStyle(fontSize: 11),
                    ),
                    value: _label.enabled,
                    activeThumbColor: _blue,
                    onChanged: (v) => setState(() => _label = _label.copyWith(enabled: v)),
                  ),
                  if (_label.enabled) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: DropdownButtonFormField<String>(
                      value: _label.templateId,
                      decoration: InputDecoration(
                        labelText: tr('Khổ giấy tem mặc định'),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: posBarcodeLabelTemplates
                          .map((t) => DropdownMenuItem(
                                value: t.id,
                                child: Text(
                                  tr('${t.sizeLabel} — ${t.name}'),
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _label = _label.copyWith(templateId: v));
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: DropdownButtonFormField<String>(
                      value: _label.protocol.key,
                      decoration: InputDecoration(
                        labelText: tr('Giao thức'),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: PosLabelPrinterProtocol.values
                          .map((p) => DropdownMenuItem(
                                value: p.key,
                                child: Text(tr(p.label)),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _label = _label.copyWith(
                              protocol: PosLabelPrinterProtocol.fromKey(v),
                            ));
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Wrap(
                      spacing: 8,
                      children: PosThermalConnectionType.values.map((t) {
                        if (t == PosThermalConnectionType.sunmi && !_isSunmi) {
                          return const SizedBox.shrink();
                        }
                        final selected = _label.connectionType == t;
                        return ChoiceChip(
                          label: Text(tr(t.label)),
                          selected: selected,
                          selectedColor: PosTheme.kiotBlueLight,
                          onSelected: (_) => setState(
                            () => _label = _label.copyWith(connectionType: t),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  if (_label.connectionType == PosThermalConnectionType.bluetooth)
                    ListTile(
                      title: Text(tr('Máy in tem Bluetooth')),
                      subtitle: Text(
                        tr(_label.bluetoothName?.isNotEmpty == true
                            ? '${_label.bluetoothName} (${_label.bluetoothAddress})'
                            : 'Chưa chọn'),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        _labelBtDevices =
                            await PosThermalPrinterService.listBluetoothDevices();
                        if (!mounted) return;
                        if (_labelBtDevices.isEmpty) {
                          NotificationOverlayManager().showWarning(
                            title: 'Không có máy in',
                            message: tr('Ghép máy in Bluetooth trong Cài đặt Android'),
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
                                  child: Text(tr('Chọn máy in tem'),
                                      style: TextStyle(
                                          fontSize: 17, fontWeight: FontWeight.w600)),
                                ),
                                ..._labelBtDevices.map(
                                  (d) => ListTile(
                                    title: Text(tr(d['name'] ?? 'Máy in')),
                                    subtitle: Text(tr(d['address'] ?? '')),
                                    onTap: () {
                                      setState(() {
                                        _label = _label.copyWith(
                                          bluetoothName: d['name'],
                                          bluetoothAddress: d['address'],
                                        );
                                      });
                                      Navigator.pop(ctx);
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  if (_label.connectionType == PosThermalConnectionType.lan) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: TextField(
                        controller: _labelLanHostCtrl,
                        decoration: InputDecoration(
                          labelText: tr('IP máy in tem'),
                          hintText: tr('192.168.1.100'),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: TextField(
                        controller: _labelLanPortCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: tr('Cổng (9100)'),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: OutlinedButton.icon(
                      onPressed: _testingLabel ? null : _testLabelPrint,
                      icon: _testingLabel
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.label_outline),
                      label: Text(tr('In thử tem')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _blue,
                        side: const BorderSide(color: _blue),
                        minimumSize: const Size(double.infinity, 56),
                      ),
                    ),
                  ),
                  ],
                ]),
              ],
            ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          tr(text),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _blue),
        ),
      );

  Widget _card(List<Widget> children) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: Column(children: children),
      );
}

/// Mở thiết lập in mobile hoặc popover desktop.
Future<(PosSellPrintSettings, PosThermalPrinterSettings)?> openPosSellPrintSettings(
  BuildContext context, {
  required PosSellPrintSettings initialPrint,
  required PosThermalPrinterSettings initialThermal,
  Offset? anchor,
}) async {
  if (Responsive.isMobile(context)) {
    final result = await Navigator.of(context).push<(PosSellPrintSettings, PosThermalPrinterSettings)>(
      MaterialPageRoute(
        builder: (_) => PosSellMobilePrintSettingsScreen(
          initialPrintSettings: initialPrint,
          initialThermalSettings: initialThermal,
        ),
      ),
    );
    return result;
  }
  return null;
}
