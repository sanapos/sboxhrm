import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../models/pos_print_template.dart';
import '../../screens/pos_print_templates_screen.dart';
import '../../services/api_service.dart';
import '../../screens/pos/pos_local_printers_screen.dart';
import '../../screens/pos/pos_store_printers_screen.dart';
import '../../utils/pos_barcode_print.dart';
import '../../utils/pos_label_printer_service.dart';
import '../../utils/pos_label_printer_settings.dart';
import '../../utils/pos_print_template_loader.dart';
import '../../utils/pos_print_config_session.dart';
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
                title: Text(tr(t.shortLabel)),
                subtitle: t.isDefault
                    ? Text(tr('Mặc định cửa hàng'))
                    : Text(tr(PosPrintPaperSizes.shortLabel(t.paperSize))),
                trailing: selectedId == t.id
                    ? const Icon(Icons.check, color: _blue)
                    : null,
                onTap: () async {
                  onPick(t.id);
                  try {
                    await _api.setDefaultPosPrintTemplate(t.id);
                    PosPrintConfigSession.instance.invalidate();
                  } catch (_) {}
                  if (ctx.mounted) Navigator.pop(ctx);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    await _print.save();
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
            ? tr('Kiểm tra cáp USB OTG, cấp quyền thiết bị, chọn đúng cổng đã lưu')
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
                  tooltip: tr('Máy in nội bộ'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PosLocalPrintersScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.phone_android),
                ),
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
                              builder: (_) => const PosLocalPrintersScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.phone_android, size: 18),
                        label: Text(tr('Máy nội bộ')),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const PosStorePrintersScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.print_outlined, size: 18),
                        label: Text(tr('Máy cửa hàng')),
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
                    activeColor: _blue,
                    onChanged: (v) =>
                        setState(() => _print = _print.copyWith(autoPrint: v)),
                  ),
                ]),
                _sectionTitle('Hóa đơn'),
                _card([
                  SwitchListTile(
                    title: Text(tr('Gộp hàng cùng loại khi in')),
                    value: _print.mergeSameItems,
                    activeColor: _blue,
                    onChanged: (v) =>
                        setState(() => _print = _print.copyWith(mergeSameItems: v)),
                  ),
                  SwitchListTile(
                    title: Text(tr('In mã VietQR trên hóa đơn')),
                    subtitle: Text(tr('In QR tổng tiền đơn (cần thiết lập tài khoản NH)'),
                      style: TextStyle(fontSize: 11),
                    ),
                    value: _print.printVietQrOnReceipt,
                    activeColor: _blue,
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
                      tr(() {
                        if (_templates.isEmpty) return 'Chưa có mẫu';
                        final t = _templates
                            .where((x) => x.id == _resolveTemplateId())
                            .firstOrNull;
                        if (t == null) return 'Mặc định';
                        return '${t.name} · ${PosPrintPaperSizes.displayLabel(t.paperSize)}';
                      }()),
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
                                          tr(PosPrintPaperSizes.displayLabel(
                                              t.paperSize)),
                                        ),
                                        trailing: _resolveTemplateId() == t.id
                                            ? const Icon(Icons.check, color: _blue)
                                            : null,
                                        onTap: () async {
                                          setState(() =>
                                              _print = _print.copyWith(templateId: t.id));
                                          try {
                                            await _api.setDefaultPosPrintTemplate(t.id);
                                            PosPrintConfigSession.instance.invalidate();
                                          } catch (_) {}
                                          if (ctx.mounted) Navigator.pop(ctx);
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
                    title: Text(tr('Thiết kế mẫu hóa đơn')),
                    subtitle: Text(tr('Loại mẫu: Hóa đơn (SaleInvoice)')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openTemplateEditor(
                      documentType: PosPrintDocumentTypes.saleInvoice,
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                _sectionTitle('Tem dán ly (trà sữa)'),
                _card([
                  Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      tr('Chọn một chế độ. «Tự in khi thanh toán» = in tem sau TT.\n'
                          'Khổ máy tem mặc định 50×30. Loại mẫu thiết kế: Tem báo bếp.'),
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
                                  v == PosCupLabelPrintMode.onCheckout,
                            ));
                      },
                    ),
                  ),
                  if (_print.cupLabelPrintMode.enabled)
                    SwitchListTile(
                      title: Text(tr('In tem khi Báo bếp / thông báo bếp')),
                      subtitle: Text(
                        tr('Mặc định bật. Tắt nếu chỉ muốn in tem thủ công hoặc sau TT.'),
                        style: const TextStyle(fontSize: 11),
                      ),
                      value: _print.printCupOnKitchenNotify,
                      activeColor: _blue,
                      onChanged: (v) => setState(() =>
                          _print = _print.copyWith(printCupOnKitchenNotify: v)),
                    ),
                  ListTile(
                    leading: const Icon(Icons.label_outline, color: _blue),
                    title: Text(tr('Thiết kế mẫu tem báo bếp / tem ly')),
                    subtitle: Text(tr('Loại mẫu: Tem báo bếp (KitchenLabel)')),
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
                      tr('Tem mã hàng / mã vạch / giá. In từ danh mục hàng hóa. Loại mẫu: Tem sản phẩm.'),
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
                _sectionTitle('Phiếu báo bếp'),
                _card([
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      tr('• Thủ công: chỉ in khi bấm Báo bếp.\n'
                          '• Tự động sau TT: Báo bếp vẫn in trước được; lúc thanh toán chỉ in phần chưa báo (đã in hết thì không in lại).\n'
                          'Tem ly: tùy chọn «In tem khi Báo bếp» — phần đã in tem không in lại lúc TT.'),
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                  ...PosKitchenSlipPrintMode.values.map(
                    (mode) => RadioListTile<PosKitchenSlipPrintMode>(
                      title: Text(tr(mode.label)),
                      value: mode,
                      groupValue: _print.kitchenSlipPrintMode,
                      activeColor: _blue,
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _print =
                            _print.copyWith(kitchenSlipPrintMode: v));
                      },
                    ),
                  ),
                  ListTile(
                    leading:
                        const Icon(Icons.design_services_outlined, color: _blue),
                    title: Text(tr('Thiết kế mẫu phiếu báo bếp')),
                    subtitle: Text(tr('Loại: Phiếu chế biến (KitchenSlip) · khổ K58/K80/A5/A4')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openTemplateEditor(
                      documentType: PosPrintDocumentTypes.kitchenSlip,
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.phone_android, color: _blue),
                    title: Text(tr('Máy in nội bộ (gán Báo bếp)')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PosLocalPrintersScreen(),
                        ),
                      );
                    },
                  ),
                ]),
                const SizedBox(height: 16),
                _sectionTitle('Phiếu báo xuất kho'),
                _card([
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(
                      tr('Độc lập với báo bếp. «Tự động sau thanh toán» vẫn in dù đã báo bếp trước đó. Gán vai trò Báo kho trên máy in nội bộ.'),
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
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
                      tr(() {
                        if (_warehouseTemplates.isEmpty) return 'Chưa có mẫu';
                        final t = _warehouseTemplates
                            .where((x) => x.id == _resolveWarehouseTemplateId())
                            .firstOrNull;
                        if (t == null) return 'Mặc định';
                        return '${t.name} · ${PosPrintPaperSizes.displayLabel(t.paperSize)}';
                      }()),
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
                    subtitle: Text(tr('Loại mẫu: Phiếu xuất kho (StockIssue)')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openTemplateEditor(
                      documentType: PosPrintDocumentTypes.stockIssue,
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                _sectionTitle('Máy in trên thiết bị này'),
                _card([
                  ListTile(
                    leading: const Icon(Icons.phone_android, color: _blue),
                    title: Text(tr('Máy in nội bộ')),
                    subtitle: Text(
                      tr('Thêm máy → In thử. Gán món và vai trò Hóa đơn / Báo bếp — bán trên máy này in ngay, không cần Agent.'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PosLocalPrintersScreen(),
                        ),
                      );
                    },
                  ),
                ]),
                const SizedBox(height: 16),
                _sectionTitle('Máy in cửa hàng (Cloud / Agent)'),
                _card([
                  ListTile(
                    leading: const Icon(Icons.cloud_outlined, color: _blue),
                    title: Text(tr('Máy in cửa hàng')),
                    subtitle: Text(
                      tr('Máy dùng chung cửa hàng. A7/web in được khi máy cắm cổng bật Agent.'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PosStorePrintersScreen(),
                        ),
                      );
                    },
                  ),
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
