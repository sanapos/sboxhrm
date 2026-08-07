import 'package:flutter/material.dart';

import '../models/pos_print_template.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';
import '../utils/pos_barcode_print.dart';
import '../utils/pos_print_template_loader.dart';
import '../utils/pos_print_template_defaults.dart';
import '../utils/pos_print_template_renderer.dart';
import '../utils/pos_print_template_v2_codec.dart';
import '../utils/pos_print_template_v2_presets.dart';
import '../utils/pos_print_template_compiler.dart';
import '../utils/pos_print_template_runtime.dart';
import '../utils/pos_print_orchestrator.dart';
import '../utils/pos_printer_transport.dart';
import '../utils/pos_thermal_printer_settings.dart';
import '../models/pos_print_template_v2.dart';
import '../widgets/pos/pos_print_template_v2_editor.dart';
import '../utils/responsive_helper.dart';
import '../widgets/hrm/hrm_settings_mobile_kit.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/pos/pos_module_toolbar.dart';
import '../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

const _blue = Color(0xFF2563EB);

class PosPrintTemplatesScreen extends StatefulWidget {
  const PosPrintTemplatesScreen({
    super.key,
    this.embeddedInSettings = false,
    this.initialDocumentType,
  });

  /// Hiển thị trong Thiết lập HRM (ẩn toolbar POS).
  final bool embeddedInSettings;

  /// Loại chứng từ mở sẵn (vd. StockIssue cho phiếu xuất kho).
  final String? initialDocumentType;

  @override
  State<PosPrintTemplatesScreen> createState() => _PosPrintTemplatesScreenState();
}

class _PosPrintTemplatesScreenState extends State<PosPrintTemplatesScreen> {
  final _api = ApiService();
  final _nameCtrl = TextEditingController();
  final _docTypeScrollCtrl = ScrollController();

  String _docType = PosPrintDocumentTypes.saleInvoice;
  List<PosPrintTemplate> _templates = [];
  PosPrintTemplate? _selected;
  PosPrintTemplateV2? _v2Template;
  /// Khi khác null: lưu HTML thuần (legacy), không encode V2.
  String? _legacyHtml;
  bool _loading = true;
  bool _saving = false;
  bool _testingPrint = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialDocumentType != null &&
        widget.initialDocumentType!.isNotEmpty) {
      _docType = widget.initialDocumentType!;
    }
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _docTypeScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    _templates = await loadPosPrintTemplates(_api, _docType);

    _selected = _templates.where((t) => t.isDefault).firstOrNull ??
        _templates.firstOrNull;

    if (_selected != null) {
      _bindTemplateContent(_selected);
      _nameCtrl.text = _selected!.name;
    } else {
      _applyLocalDefault();
    }
    _dirty = false;

    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _applyLocalDefault({String? paperSize}) {
    _selected = null;
    _legacyHtml = null;
    final paper = paperSize ??
        (_docType == PosPrintDocumentTypes.kitchenLabel
            ? PosPrintPaperSizes.label50x30
            : _docType == PosPrintDocumentTypes.barcodeLabel
                ? 'roll_1_50x30'
                : PosPrintPaperSizes.k80);
    _v2Template = PosPrintTemplateV2Presets.build(
      documentType: _docType,
      paperSize: paper,
      printerProfile: PosPrintPaperSizes.isLabelSize(paper)
          ? PosPrintPrinterProfiles.genericK58
          : PosPrintPrinterProfiles.sunmiK80,
      name: posPrintDefaultTemplateName(paper),
    );
    _nameCtrl.text = _v2Template!.name ?? posPrintDefaultTemplateName(paper);
    _dirty = false;
  }

  void _bindTemplateContent(PosPrintTemplate? t) {
    final parsed = PosPrintTemplateV2Codec.tryParse(t?.htmlContent);
    if (parsed != null) {
      _v2Template = parsed;
      _legacyHtml = null;
      return;
    }
    final raw = (t?.htmlContent ?? '').trim();
    if (raw.isNotEmpty && !PosPrintTemplateV2Codec.isV2Content(raw)) {
      // Giữ HTML thuần; vẫn tạo V2 preset để có thể quay lại chỉnh khối.
      _legacyHtml = t!.htmlContent;
      final paper = t.paperSize;
      final profile = paper == PosPrintPaperSizes.k58
          ? PosPrintPrinterProfiles.sunmiK58
          : PosPrintPrinterProfiles.sunmiK80;
      _v2Template = PosPrintTemplateV2Presets.build(
        documentType: _docType,
        paperSize: paper,
        printerProfile: profile,
        name: t.name,
      );
      return;
    }
    final paper = t?.paperSize ?? PosPrintPaperSizes.k80;
    final profile = paper == PosPrintPaperSizes.k58
        ? PosPrintPrinterProfiles.sunmiK58
        : PosPrintPrinterProfiles.sunmiK80;
    _legacyHtml = null;
    _v2Template = PosPrintTemplateV2Presets.build(
      documentType: _docType,
      paperSize: paper,
      printerProfile: profile,
      name: t?.name,
    );
  }

  void _selectTemplate(PosPrintTemplate? t) {
    if (_dirty) {
      _confirmDiscard(() => _applyTemplate(t));
      return;
    }
    _applyTemplate(t);
  }

  void _applyTemplate(PosPrintTemplate? t) {
    setState(() {
      _selected = t;
      if (t != null) {
        _bindTemplateContent(t);
        _nameCtrl.text = t.name;
      } else {
        _applyLocalDefault();
      }
      _dirty = false;
    });
  }

  void _onLegacyHtml(String html) {
    setState(() {
      _legacyHtml = html;
      _dirty = true;
    });
    NotificationOverlayManager().showSuccess(
      title: 'HTML thuần',
      message: tr('Đã gắn HTML. Bấm Lưu để ghi. In nhiệt nên dùng JSON V2.'),
    );
  }

  Future<void> _confirmDiscard(VoidCallback onOk) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Bỏ thay đổi?')),
        content: Text(tr('Mẫu in đang chỉnh sửa chưa lưu. Bỏ thay đổi?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Bỏ'))),
        ],
      ),
    );
    if (ok == true && mounted) onOk();
  }

  String? get _dropdownValue {
    final id = _selected?.id;
    if (id == null || id.isEmpty) return null;
    return _templates.any((t) => t.id == id) ? id : null;
  }

  Future<void> _save() async {
    if (_selected == null) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      NotificationOverlayManager().showError(title: 'Lỗi', message: tr('Nhập tên mẫu in'));
      return;
    }
    setState(() => _saving = true);
    final v2 = _v2Template!.copyWith(
      name: name,
      documentType: _docType,
      paperSize: _v2Template!.paperSize,
    );
    final htmlContent = _legacyHtml?.trim().isNotEmpty == true
        ? _legacyHtml!
        : PosPrintTemplateV2Codec.encode(v2);
    final apiPaper = PosPrintPaperSizes.toApiPaperSize(_docType, v2.paperSize);
    final body = _selected!.copyWith(
      name: name,
      htmlContent: htmlContent,
      documentType: _docType,
      paperSize: apiPaper,
    ).toSaveJson();
    final res = await _api.updatePosPrintTemplate(_selected!.id, body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      _dirty = false;
      NotificationOverlayManager().showSuccess(title: 'Đã lưu', message: tr('Mẫu in đã được cập nhật'));
      await _load();
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không lưu được',
      );
    }
  }

  List<(String key, String label)> _paperOptionsForDoc() {
    if (_docType == PosPrintDocumentTypes.kitchenLabel) {
      return PosPrintPaperSizes.kitchenLabelSizes
          .map((k) => (k, PosPrintPaperSizes.labels[k] ?? k))
          .toList();
    }
    if (_docType == PosPrintDocumentTypes.barcodeLabel) {
      return posBarcodeLabelTemplates
          .map((t) => (t.id, '${t.name} (${t.sizeLabel})'))
          .toList();
    }
    return [
      (PosPrintPaperSizes.k58, PosPrintPaperSizes.labels[PosPrintPaperSizes.k58]!),
      (PosPrintPaperSizes.k80, PosPrintPaperSizes.labels[PosPrintPaperSizes.k80]!),
      (PosPrintPaperSizes.a5, PosPrintPaperSizes.labels[PosPrintPaperSizes.a5]!),
      (PosPrintPaperSizes.a4, PosPrintPaperSizes.labels[PosPrintPaperSizes.a4]!),
    ];
  }

  Future<void> _addTemplate() async {
    final presetsRes = await _api.getPosPrintTemplatePresets(documentType: _docType);
    final presets = presetsRes['isSuccess'] == true && presetsRes['data'] is List
        ? (presetsRes['data'] as List)
            .map((e) => PosPrintTemplatePreset.fromJson(e as Map<String, dynamic>))
            .toList()
        : <PosPrintTemplatePreset>[];

    final paperOpts = _paperOptionsForDoc();
    String paper = paperOpts.first.$1;
    if (_docType == PosPrintDocumentTypes.barcodeLabel) {
      paper = 'roll_1_50x30';
    } else if (_docType == PosPrintDocumentTypes.kitchenLabel) {
      paper = PosPrintPaperSizes.label50x30;
    } else {
      paper = PosPrintPaperSizes.k80;
    }
    if (!paperOpts.any((e) => e.$1 == paper)) {
      paper = paperOpts.first.$1;
    }
    final nameCtrl = TextEditingController(text: tr('Mẫu in mới'));
    final isLabel = PosPrintPaperSizes.isLabelDoc(_docType);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(tr('Thêm mẫu in')),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(labelText: tr('Tên mẫu in')),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: paper,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tr(isLabel ? 'Khổ tem' : 'Khổ giấy'),
                  ),
                  items: paperOpts
                      .map((e) => DropdownMenuItem(
                            value: e.$1,
                            child: Text(tr(e.$2), overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setDlg(() => paper = v);
                  },
                ),
                if (presets.isNotEmpty && !isLabel) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: presets.any((p) => p.paperSize == paper)
                        ? paper
                        : presets.first.paperSize,
                    decoration: InputDecoration(labelText: tr('Mẫu gợi ý')),
                    items: presets
                        .map((p) => DropdownMenuItem(
                              value: p.paperSize,
                              child: Text(tr(p.name)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      final preset =
                          presets.where((p) => p.paperSize == v).firstOrNull;
                      setDlg(() {
                        paper = v;
                        if (preset != null && nameCtrl.text == 'Mẫu in mới') {
                          nameCtrl.text = preset.name;
                        }
                      });
                    },
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Bỏ qua'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Tạo'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    final stock = posBarcodeLabelTemplateById(paper);
    final displayName = nameCtrl.text.trim().isEmpty
        ? (stock != null
            ? '${stock.name} (${stock.sizeLabel})'
            : (PosPrintPaperSizes.labels[paper] ?? paper))
        : nameCtrl.text.trim();

    final v2Paper = paper;
    final v2Preset = PosPrintTemplateV2Presets.build(
      documentType: _docType,
      paperSize: v2Paper,
      printerProfile: PosPrintPaperSizes.isLabelSize(v2Paper)
          ? PosPrintPrinterProfiles.genericK58
          : (v2Paper == PosPrintPaperSizes.k58
              ? PosPrintPrinterProfiles.sunmiK58
              : PosPrintPrinterProfiles.zywellK80),
      name: displayName,
    );

    final res = await _api.createPosPrintTemplate({
      'name': displayName,
      'documentType': _docType,
      'paperSize': PosPrintPaperSizes.toApiPaperSize(_docType, v2Paper),
      'htmlContent': PosPrintTemplateV2Codec.encode(v2Preset),
      'isDefault': _templates.isEmpty,
      'isActive': true,
      'sortOrder': _templates.length,
    });
    if (res['isSuccess'] == true && res['data'] is Map) {
      NotificationOverlayManager().showSuccess(title: 'Đã tạo', message: tr('Mẫu in mới'));
      await _load();
      final created = PosPrintTemplate.fromJson(res['data'] as Map<String, dynamic>);
      _applyTemplate(created);
    }
  }

  Future<void> _testPrintTemplate() async {
    final v2 = _v2Template;
    if (v2 == null) return;
    setState(() => _testingPrint = true);
    try {
      final isKitchenSlip =
          v2.documentType == PosPrintDocumentTypes.kitchenSlip ||
              v2.documentType == PosPrintDocumentTypes.kitchenVoid;
      final isLabel = v2.documentType == PosPrintDocumentTypes.barcodeLabel ||
          v2.documentType == PosPrintDocumentTypes.kitchenLabel;
      final output = isKitchenSlip
          ? PosPrintTemplateRuntime.compileKitchenSlip(
              template: v2,
              tableName: 'Bàn 05',
              isCancel: v2.documentType == PosPrintDocumentTypes.kitchenVoid,
              lines: const [
                (name: 'Phở bò tái', qty: '2', unit: 'tô', note: 'Ít hành'),
                (name: 'Trà đá', qty: '2', unit: 'ly', note: null),
              ],
              senderName: 'NV Demo',
              orderNo: 'DH0001',
              sentAt: DateTime.now(),
            )
          : PosPrintTemplateCompiler.compile(
              template: v2,
              data: posPrintSampleData(documentType: v2.documentType),
              lineItems: isLabel ? const [] : posPrintSampleLines(),
            );

      final settings = (await PosThermalPrinterSettings.load()).copyWith(
        enabled: true,
        paperSize: v2.paperSize,
      );

      if (await PosPrinterTransport.isSunmiDevice() ||
          settings.connectionType == PosThermalConnectionType.sunmi) {
        final ok = await PosPrintTemplateRuntime.printCompiledSunmi(
          output: output,
          settings: settings.copyWith(
            connectionType: PosThermalConnectionType.sunmi,
            printerBrand: PosThermalPrinterBrand.sunmi,
          ),
          kitchenFeed: isKitchenSlip || isLabel,
        );
        if (!mounted) return;
        if (ok) {
          NotificationOverlayManager()
              .showSuccess(title: 'In thử', message: tr('Đã in mẫu trên Sunmi'));
        } else {
          NotificationOverlayManager().showError(
            title: 'In thử thất bại',
            message: tr('Sunmi không phản hồi'),
          );
        }
        return;
      }

      final bytes = await PosPrintTemplateRuntime.buildCompiledEscPosBytes(
        output: output,
        settings: settings,
      );
      final ok = await PosPrintOrchestrator.instance.dispatchLocalEscPos(
        bytes: bytes,
        settingsOverride: settings,
        documentType: v2.documentType,
        showFeedback: false,
        skipDedup: true,
      );
      if (!mounted) return;
      if (ok) {
        NotificationOverlayManager()
            .showSuccess(title: 'In thử', message: tr('Đã gửi mẫu in thử'));
      } else {
        NotificationOverlayManager().showError(
          title: 'In thử thất bại',
          message: tr('Kiểm tra kết nối máy in cục bộ'),
        );
      }
    } catch (e) {
      if (!mounted) return;
      NotificationOverlayManager().showError(
        title: 'In thử thất bại',
        message: e.toString(),
      );
    } finally {
      if (mounted) setState(() => _testingPrint = false);
    }
  }

  Future<void> _deleteTemplate() async {
    if (_selected == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xóa mẫu in?')),
        content: Text(tr('Xóa mẫu «${_selected!.name}»?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final res = await _api.deletePosPrintTemplate(_selected!.id);
    if (res['isSuccess'] == true) {
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.embeddedInSettings
          ? HrmPageChrome.scaffoldBackground(context)
          : const Color(0xFFF3F4F6),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.embeddedInSettings)
            const PosModuleToolbar(activeModule: 'PosSell'),
          Material(
            color: Colors.white,
            child: Container(
              height: 48,
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: PosTheme.border)),
              ),
              child: Scrollbar(
                controller: _docTypeScrollCtrl,
                thumbVisibility: true,
                trackVisibility: true,
                scrollbarOrientation: ScrollbarOrientation.bottom,
                child: SingleChildScrollView(
                  controller: _docTypeScrollCtrl,
                  scrollDirection: Axis.horizontal,
                  primary: false,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: PosPrintDocumentTypes.all.entries.map((e) {
                      final active = e.key == _docType;
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: TextButton(
                          onPressed: () {
                            if (e.key == _docType) return;
                            _docType = e.key;
                            _load();
                          },
                          style: TextButton.styleFrom(
                            foregroundColor:
                                active ? _blue : PosTheme.textPrimary,
                            backgroundColor:
                                active ? const Color(0xFFE8F0FE) : null,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Text(
                            tr(e.value),
                            style: TextStyle(
                              fontWeight:
                                  active ? FontWeight.w600 : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
          _buildTemplateSelectorBar(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Responsive.isMobile(context)
                    ? _buildMobileEditorBody()
                    : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextField(
                            controller: _nameCtrl,
                            decoration: InputDecoration(
                              labelText: tr('Tên mẫu in'),
                              isDense: true,
                            ),
                            onChanged: (_) => setState(() => _dirty = true),
                          ),
                        ),
                        if (_legacyHtml != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(8),
                              child: ListTile(
                                dense: true,
                                leading: const Icon(Icons.html, color: Color(0xFFB45309)),
                                title: Text(tr('Đang dùng HTML thuần')),
                                subtitle: Text(tr('Chỉnh khối V2 rồi lưu sẽ ghi đè HTML. Hoặc sửa HTML ở tab Mã nguồn.')),
                                trailing: TextButton(
                                  onPressed: () => setState(() {
                                    _legacyHtml = null;
                                    _dirty = true;
                                  }),
                                  child: Text(tr('Về V2')),
                                ),
                              ),
                            ),
                          ),
                        Expanded(
                          child: _v2Template == null
                              ? Center(child: Text(tr('Đang tải…')))
                              : PosPrintTemplateV2Editor(
                                  template: _v2Template!,
                                  onChanged: (v) => setState(() {
                                    _v2Template = v;
                                    _legacyHtml = null;
                                    _dirty = true;
                                  }),
                                  onLegacyHtml: _onLegacyHtml,
                                ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileEditorBody() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: tr('Tên mẫu in'),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() => _dirty = true),
            ),
          ),
          if (_legacyHtml != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Material(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(8),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.html, color: Color(0xFFB45309), size: 22),
                  title: Text(tr('HTML thuần'), style: TextStyle(fontSize: 13)),
                  trailing: TextButton(
                    onPressed: () => setState(() {
                      _legacyHtml = null;
                      _dirty = true;
                    }),
                    child: Text(tr('Về V2')),
                  ),
                ),
              ),
            ),
          Expanded(
            child: _v2Template == null
                ? const Center(child: CircularProgressIndicator())
                : PosPrintTemplateV2Editor(
                    compact: true,
                    template: _v2Template!,
                    onChanged: (v) => setState(() {
                      _v2Template = v;
                      _legacyHtml = null;
                      _dirty = true;
                    }),
                    onLegacyHtml: _onLegacyHtml,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateSelectorBar() {
    final selector = DropdownButtonFormField<String>(
      value: _dropdownValue,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        hintText: trN(_templates.isEmpty ? 'Chưa có mẫu — bấm +' : null),
      ),
      items: _templates
          .map((t) => DropdownMenuItem(
                value: t.id,
                child: Text(tr('${t.name} (${PosPrintPaperSizes.labels[t.paperSize] ?? t.paperSize})')),
              ))
          .toList(),
      onChanged: (id) {
        if (id == null) return;
        _selectTemplate(_templates.where((t) => t.id == id).firstOrNull);
      },
    );

    if (Responsive.isMobile(context)) {
      final embeddedKit =
          widget.embeddedInSettings && HrmSettingsMobileKit.active(context);
      return Padding(
        padding: EdgeInsets.fromLTRB(
            12, 10, 12, embeddedKit ? 8 : 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!embeddedKit)
              Text(tr('Mẫu in'), style: TextStyle(fontWeight: FontWeight.w600)),
            if (!embeddedKit) const SizedBox(height: 8),
            selector,
            const SizedBox(height: 8),
            if (embeddedKit)
              Row(
                children: [
                  HrmSettingsAddButton(
                    label: 'Thêm',
                    compact: true,
                    onPressed: _addTemplate,
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: tr('Xóa mẫu'),
                    onPressed: _selected == null ? null : _deleteTemplate,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                  ),
                  IconButton(
                    tooltip: tr('In thử'),
                    onPressed: _testingPrint || _v2Template == null ? null : _testPrintTemplate,
                    icon: _testingPrint
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.print_outlined, color: _blue),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _blue),
                    onPressed: _saving || _selected == null ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save, size: 16),
                    label: Text(tr('Lưu')),
                  ),
                ],
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _addTemplate,
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: Text(tr('Thêm')),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _selected == null ? null : _deleteTemplate,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(tr('Xóa')),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _testingPrint || _v2Template == null ? null : _testPrintTemplate,
                      icon: _testingPrint
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.print_outlined, size: 18),
                      label: Text(tr('In thử')),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: _blue),
                      onPressed: _saving || _selected == null ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save, size: 16),
                      label: Text(tr('Lưu')),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Text(tr('Mẫu in:'), style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(child: selector),
          IconButton(
            tooltip: tr('Thêm mẫu'),
            onPressed: _addTemplate,
            icon: const Icon(Icons.add_circle_outline, color: _blue),
          ),
          IconButton(
            tooltip: tr('Xóa mẫu'),
            onPressed: _selected == null ? null : _deleteTemplate,
            icon: const Icon(Icons.delete_outline, color: Colors.red),
          ),
          IconButton(
            tooltip: tr('In thử'),
            onPressed: _testingPrint || _v2Template == null ? null : _testPrintTemplate,
            icon: _testingPrint
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_outlined, color: _blue),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _blue),
            onPressed: _saving || _selected == null ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save, size: 18),
            label: Text(tr('Lưu')),
          ),
        ],
      ),
    );
  }
}
