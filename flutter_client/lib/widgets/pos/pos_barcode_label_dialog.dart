import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/pos_print_template.dart';
import '../../models/pos_product.dart';
import '../../models/pos_store_printer.dart';
import '../../screens/pos_print_templates_screen.dart';
import '../../utils/pos_barcode_print.dart';
import '../../utils/pos_label_printer_service.dart';
import '../../utils/pos_label_printer_settings.dart';
import '../../utils/pos_print_orchestrator.dart';
import '../../utils/pos_sell_store_settings.dart';
import '../../utils/pos_store_printer_mapper.dart';
import '../../utils/pos_thermal_printer_service.dart';
import '../../utils/pos_thermal_printer_settings.dart';
import '../../utils/responsive_helper.dart';
import '../notification_overlay.dart';
import 'pos_pdf_preview_dialog.dart';
import 'pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Dialog chọn loại giấy in tem mã — giao diện kiểu KiotViet.
Future<void> showPosBarcodeLabelDialog(
  BuildContext context,
  List<PosProduct> products,
) async {
  if (products.isEmpty) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _PosBarcodeLabelDialog(products: products),
  );
}

class _PosBarcodeLabelDialog extends StatefulWidget {
  const _PosBarcodeLabelDialog({required this.products});

  final List<PosProduct> products;

  @override
  State<_PosBarcodeLabelDialog> createState() => _PosBarcodeLabelDialogState();
}

class _PosBarcodeLabelDialogState extends State<_PosBarcodeLabelDialog> {
  int _copies = 1;
  late final TextEditingController _copiesCtrl;
  late final TextEditingController _lanHostCtrl;
  late final TextEditingController _lanPortCtrl;
  PosBarcodeCodeField _codeField = PosBarcodeCodeField.productCode;
  PosBarcodePriceMode _priceMode = PosBarcodePriceMode.withVnd;
  PosBarcodeUnitMode _unitMode = PosBarcodeUnitMode.withoutUnit;
  PosBarcodeStoreMode _storeMode = PosBarcodeStoreMode.withoutStore;
  PosBarcodeLabelTemplate? _selectedTemplate;
  PosLabelPrinterSettings _labelPrinter = const PosLabelPrinterSettings();
  String? _storeName;
  List<Map<String, String>> _btDevices = [];
  bool _printing = false;
  bool _printerExpanded = false;

  @override
  void initState() {
    super.initState();
    _copiesCtrl = TextEditingController(text: tr('1'));
    _lanHostCtrl = TextEditingController();
    _lanPortCtrl = TextEditingController(text: tr('9100'));
    _selectedTemplate = posBarcodeLabelTemplateById(_labelPrinter.templateId) ??
        defaultBarcodeLabelTemplate;
    _loadPrinterSettings();
  }

  Future<void> _loadPrinterSettings() async {
    final lp = await PosLabelPrinterSettings.load();
    final store = await PosSellStoreSettings.load();
    if (!mounted) return;
    setState(() {
      _labelPrinter = lp;
      _storeName = store.storeName;
      _lanHostCtrl.text = lp.lanHost ?? '';
      _lanPortCtrl.text = '${lp.lanPort}';
      _selectedTemplate ??=
          posBarcodeLabelTemplateById(lp.templateId) ?? defaultBarcodeLabelTemplate;
    });
    _btDevices = await PosThermalPrinterService.listBluetoothDevices();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _copiesCtrl.dispose();
    _lanHostCtrl.dispose();
    _lanPortCtrl.dispose();
    super.dispose();
  }

  PosBarcodePrintOptions _options(PosBarcodeLabelTemplate template) =>
      PosBarcodePrintOptions(
        template: template,
        copiesPerProduct: _copies,
        codeField: _codeField,
        priceMode: _priceMode,
        unitMode: _unitMode,
        storeMode: _storeMode,
        storeName: _storeName,
      );

  PosLabelPrinterSettings _draftPrinterSettings() {
    final port = int.tryParse(_lanPortCtrl.text.trim()) ?? 9100;
    return _labelPrinter.copyWith(
      enabled: true,
      templateId: _selectedTemplate?.id ?? _labelPrinter.templateId,
      lanHost: _lanHostCtrl.text.trim(),
      lanPort: port,
    );
  }

  Future<void> _savePrinterSettings() async {
    await _draftPrinterSettings().save();
    if (mounted) setState(() => _labelPrinter = _draftPrinterSettings());
  }

  Future<void> _preview(PosBarcodeLabelTemplate template) async {
    setState(() => _selectedTemplate = template);
    try {
      final bytes = await buildPosBarcodeLabelPdfBytes(
        widget.products,
        options: _options(template),
      );
      if (!mounted) return;
      await showPosPdfPreviewDialog(
        context,
        bytes: bytes,
        title: 'Xem bản in — ${template.name}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Không tạo được bản in: $e'))),
      );
    }
  }

  Future<void> _printToDevice() async {
    final template = _selectedTemplate;
    if (template == null) {
      NotificationOverlayManager().showWarning(
        title: 'Chưa chọn khổ giấy',
        message: tr('Chọn mẫu tem và bấm «Xem bản in» hoặc chọn thẻ mẫu'),
      );
      return;
    }

    setState(() => _printing = true);
    await _savePrinterSettings();

    if (!kIsWeb) {
      await PosPrintOrchestrator.instance.refreshConfig();
      final cloudPrinter = PosPrintOrchestrator.instance
          .resolvePrinter(PosCloudDocumentTypes.barcodeLabel);
      if (cloudPrinter != null && cloudPrinter.isLabelPrinter) {
        final settings = toLabelSettings(cloudPrinter).copyWith(
          templateId: template.id,
        );
        final jobs = await PosLabelPrinterService.buildLabelByteJobs(
          widget.products,
          options: _options(template),
          settings: settings,
        );
        final cloudOk = await PosPrintOrchestrator.instance.dispatchLabelJobs(
          jobs: jobs,
          referenceNo: 'LABEL-${widget.products.length}',
        );
        if (!mounted) return;
        setState(() => _printing = false);
        if (cloudOk) return;
      }
    }

    final draft = _draftPrinterSettings();
    if (draft.connectionType == PosThermalConnectionType.bluetooth &&
        (draft.bluetoothAddress == null || draft.bluetoothAddress!.isEmpty)) {
      if (!mounted) return;
      setState(() => _printing = false);
      NotificationOverlayManager().showError(
        title: 'Chưa chọn máy in',
        message: tr('Cấu hình máy in tem trong Máy in cửa hàng hoặc Thiết lập in'),
      );
      return;
    }
    if (draft.connectionType == PosThermalConnectionType.lan &&
        (draft.lanHost == null || draft.lanHost!.trim().isEmpty)) {
      if (!mounted) return;
      setState(() => _printing = false);
      NotificationOverlayManager().showError(
        title: 'Thiếu IP máy in',
        message: tr('Nhập địa chỉ IP máy in tem (LAN/WiFi)'),
      );
      return;
    }

    final ok = await printPosBarcodeLabelsToDevice(
      widget.products,
      options: _options(template),
      settings: draft,
    );
    if (!mounted) return;
    setState(() => _printing = false);
    if (ok) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã gửi in tem',
        message: tr('${widget.products.length} mặt hàng × $_copies tem'),
      );
    } else {
      NotificationOverlayManager().showError(
        title: 'In tem thất bại',
        message: tr('Kiểm tra kết nối, khổ giấy và giao thức TSPL/ESC/POS'),
      );
    }
  }

  Future<void> _testLabelPrinter() async {
    final draft = _draftPrinterSettings();
    setState(() => _printing = true);
    final ok = await PosLabelPrinterService.testPrint(draft);
    if (!mounted) return;
    setState(() => _printing = false);
    if (ok) {
      NotificationOverlayManager()
          .showSuccess(title: 'In thử', message: tr('Đã gửi tem mẫu'));
    } else {
      NotificationOverlayManager().showError(
        title: 'In thử thất bại',
        message: tr('Kiểm tra kết nối máy in tem'),
      );
    }
  }

  Future<void> _exportExcel() async {
    if (_selectedTemplate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Chọn mẫu giấy trước'))),
      );
      return;
    }
    await exportPosBarcodeLabelsExcel(
      widget.products,
      options: _options(_selectedTemplate!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = Responsive.isMobile(context);
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: mobile ? 8 : 24,
        vertical: mobile ? 8 : 32,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: mobile ? size.width : (size.width * 0.92).clamp(720, 1100),
          maxHeight: size.height * (mobile ? 0.95 : 0.88),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(mobile),
            Expanded(
              child: mobile
                  ? ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        _buildOptionsPanel(),
                        const SizedBox(height: 12),
                        _buildPrinterPanel(),
                        const SizedBox(height: 12),
                        _buildTemplateGrid(),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 280,
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              _buildOptionsPanel(),
                              const SizedBox(height: 12),
                              _buildPrinterPanel(),
                            ],
                          ),
                        ),
                        const VerticalDivider(width: 1),
                        Expanded(child: _buildTemplateGrid()),
                      ],
                    ),
            ),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool mobile) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PosTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(tr('In tem mã hàng (${widget.products.length})'),
              style: TextStyle(
                fontSize: mobile ? 15 : 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PosPrintTemplatesScreen(
                    embeddedInSettings: true,
                    initialDocumentType: PosPrintDocumentTypes.barcodeLabel,
                  ),
                ),
              );
            },
            child: Text(tr('Mẫu in')),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: PosTheme.border)),
        color: Color(0xFFFAFBFC),
      ),
      child: Row(
        children: [
          OutlinedButton.icon(
            onPressed: _printing ? null : _exportExcel,
            icon: const Icon(Icons.table_chart_outlined, size: 18),
            label: Text(tr('Excel')),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _printing ? null : _printToDevice,
            icon: _printing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.print, size: 18),
            label: Text(tr('IN TEM')),
            style: FilledButton.styleFrom(
              backgroundColor: PosTheme.kiotBlue,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _fieldLabel('Số lượng in / mặt hàng'),
        TextField(
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: PosTheme.inputDecoration(label: ''),
          controller: _copiesCtrl,
          onChanged: (v) {
            final n = int.tryParse(v);
            if (n != null && n >= 1 && n <= 5000) setState(() => _copies = n);
          },
        ),
        const SizedBox(height: 10),
        _dropdown<PosBarcodeCodeField>(
          value: _codeField,
          items: PosBarcodeCodeField.values,
          label: (v) => v.label,
          onChanged: (v) => setState(() => _codeField = v!),
        ),
        const SizedBox(height: 8),
        _dropdown<PosBarcodePriceMode>(
          value: _priceMode,
          items: PosBarcodePriceMode.values,
          label: (v) => v.label,
          onChanged: (v) => setState(() => _priceMode = v!),
        ),
        const SizedBox(height: 8),
        _dropdown<PosBarcodeUnitMode>(
          value: _unitMode,
          items: PosBarcodeUnitMode.values,
          label: (v) => v.label,
          onChanged: (v) => setState(() => _unitMode = v!),
        ),
        const SizedBox(height: 8),
        _dropdown<PosBarcodeStoreMode>(
          value: _storeMode,
          items: PosBarcodeStoreMode.values,
          label: (v) => v.label,
          onChanged: (v) => setState(() => _storeMode = v!),
        ),
      ],
    );
  }

  Widget _buildPrinterPanel() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: ExpansionTile(
        initiallyExpanded: _printerExpanded || _labelPrinter.enabled,
        onExpansionChanged: (v) => setState(() => _printerExpanded = v),
        title: Text(tr('Máy in tem nhãn'),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          tr(_labelPrinter.enabled
              ? '${_labelPrinter.connectionType.label} · ${_labelPrinter.protocol.label}'
              : 'Bluetooth, LAN, USB — TSPL / ESC/POS'),
          style: const TextStyle(fontSize: 11),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Dùng máy in tem'), style: TextStyle(fontSize: 13)),
                  value: _labelPrinter.enabled,
                  activeThumbColor: PosTheme.kiotBlue,
                  onChanged: (v) =>
                      setState(() => _labelPrinter = _labelPrinter.copyWith(enabled: v)),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: PosThermalConnectionType.values.map((t) {
                    if (t == PosThermalConnectionType.sunmi && kIsWeb) {
                      return const SizedBox.shrink();
                    }
                    final selected = _labelPrinter.connectionType == t;
                    return ChoiceChip(
                      label: Text(tr(t.label), style: const TextStyle(fontSize: 11)),
                      selected: selected,
                      selectedColor: PosTheme.kiotBlueLight,
                      onSelected: (_) => setState(
                        () => _labelPrinter = _labelPrinter.copyWith(connectionType: t),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _labelPrinter.protocol.key,
                  decoration: InputDecoration(
                    labelText: tr('Giao thức'),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: PosLabelPrinterProtocol.values
                      .map((p) => DropdownMenuItem(value: p.key, child: Text(tr(p.label))))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _labelPrinter = _labelPrinter.copyWith(
                          protocol: PosLabelPrinterProtocol.fromKey(v),
                        ));
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(tr('Khe giấy (mm)'), style: TextStyle(fontSize: 12)),
                    const Spacer(),
                    DropdownButton<double>(
                      value: [2.0, 3.0, 4.0].contains(_labelPrinter.gapMm)
                          ? _labelPrinter.gapMm
                          : 2.0,
                      items: [
                        DropdownMenuItem(value: 2.0, child: Text(tr('2 mm'))),
                        DropdownMenuItem(value: 3.0, child: Text(tr('3 mm'))),
                        DropdownMenuItem(value: 4.0, child: Text(tr('4 mm'))),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _labelPrinter = _labelPrinter.copyWith(gapMm: v));
                      },
                    ),
                  ],
                ),
                if (_labelPrinter.connectionType ==
                    PosThermalConnectionType.bluetooth) ...[
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Máy Bluetooth'), style: TextStyle(fontSize: 12)),
                    subtitle: Text(
                      tr(_labelPrinter.bluetoothName?.isNotEmpty == true
                          ? '${_labelPrinter.bluetoothName}'
                          : 'Chưa chọn'),
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: _pickBluetoothPrinter,
                  ),
                ],
                if (_labelPrinter.connectionType == PosThermalConnectionType.lan) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _lanHostCtrl,
                    decoration: InputDecoration(
                      labelText: tr('IP máy in tem'),
                      hintText: tr('192.168.1.100'),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _lanPortCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: tr('Cổng (9100)'),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _printing ? null : _testLabelPrinter,
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: Text(tr('In thử tem mẫu')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickBluetoothPrinter() async {
    if (_btDevices.isEmpty) {
      _btDevices = await PosThermalPrinterService.listBluetoothDevices();
    }
    if (!mounted) return;
    if (_btDevices.isEmpty) {
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
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            ..._btDevices.map(
              (d) => ListTile(
                title: Text(tr(d['name'] ?? 'Máy in')),
                subtitle: Text(tr(d['address'] ?? '')),
                onTap: () {
                  setState(() {
                    _labelPrinter = _labelPrinter.copyWith(
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
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(tr(text), style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T) label,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      decoration: PosTheme.inputDecoration(label: ''),
      items: items
          .map((e) => DropdownMenuItem(
                value: e,
                child: Text(tr(label(e)), style: const TextStyle(fontSize: 12)),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildTemplateGrid() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Khổ giấy tem'),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: PosTheme.kiotBlue),
          ),
          const SizedBox(height: 4),
          Text(
            tr(_selectedTemplate != null
                ? 'Đang chọn: ${_selectedTemplate!.sizeLabel}'
                : 'Chọn khổ giấy khớp cuộn tem trên máy in'),
            style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: posBarcodeLabelTemplates.map((t) {
              final selected = _selectedTemplate?.id == t.id;
              return SizedBox(
                width: Responsive.isMobile(context) ? double.infinity : 200,
                child: InkWell(
                  onTap: () => setState(() => _selectedTemplate = t),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: selected ? PosTheme.kiotBlueLight : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? PosTheme.kiotBlue : PosTheme.border,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.label_outline,
                          size: 32,
                          color: selected ? PosTheme.kiotBlue : Colors.grey.shade500,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          tr(t.name),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          tr(t.sizeLabel),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 10, color: PosTheme.textSecondary),
                        ),
                        if (t.cols > 1)
                          Text(tr('${t.cols} nhãn/hàng'),
                            style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (selected)
                              const Icon(Icons.check_circle, color: PosTheme.kiotBlue, size: 16),
                            const Spacer(),
                            TextButton(
                              onPressed: () => _preview(t),
                              child: Text(tr('Xem PDF'), style: TextStyle(fontSize: 11)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Text(
            tr('Lưu ý: Khổ giấy tem phải khớp cài đặt trên máy in. TSPL dùng cho Xprinter, TSC, Zywell tem. '
            'Nếu lệch vị trí, chỉnh khe giấy (GAP).'),
            style: TextStyle(fontSize: 10, color: Colors.grey.shade700, height: 1.4),
          ),
        ],
      ),
    );
  }
}
