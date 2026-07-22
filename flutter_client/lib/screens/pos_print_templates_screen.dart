import 'package:flutter/material.dart';

import '../models/pos_print_template.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';
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

  String _docType = PosPrintDocumentTypes.saleInvoice;
  List<PosPrintTemplate> _templates = [];
  PosPrintTemplate? _selected;
  PosPrintTemplateV2? _v2Template;
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
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    _templates = await loadPosPrintTemplates(_api, _docType);

    _selected = _templates.where((t) => t.isDefault).firstOrNull ??
        _templates.firstOrNull;

    if (_selected != null) {
      _v2Template = _v2FromTemplate(_selected);
      _nameCtrl.text = _selected!.name;
    } else {
      _applyLocalDefault();
    }
    _dirty = false;

    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _applyLocalDefault({String paperSize = PosPrintPaperSizes.k80}) {
    _selected = null;
    _v2Template = PosPrintTemplateV2Presets.build(
      documentType: _docType,
      paperSize: paperSize,
      printerProfile: PosPrintPrinterProfiles.sunmiK80,
      name: posPrintDefaultTemplateName(paperSize),
    );
    _nameCtrl.text = _v2Template!.name ?? posPrintDefaultTemplateName(paperSize);
    _dirty = false;
  }

  PosPrintTemplateV2 _v2FromTemplate(PosPrintTemplate? t) {
    final parsed = PosPrintTemplateV2Codec.tryParse(t?.htmlContent);
    if (parsed != null) return parsed;
    final paper = t?.paperSize ?? PosPrintPaperSizes.k80;
    final profile = paper == PosPrintPaperSizes.k58
        ? PosPrintPrinterProfiles.sunmiK58
        : PosPrintPrinterProfiles.sunmiK80;
    return PosPrintTemplateV2Presets.build(
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
        _v2Template = _v2FromTemplate(t);
        _nameCtrl.text = t.name;
      } else {
        _applyLocalDefault();
      }
      _dirty = false;
    });
  }

  Future<void> _confirmDiscard(VoidCallback onOk) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bỏ thay đổi?'),
        content: const Text('Mẫu in đang chỉnh sửa chưa lưu. Bỏ thay đổi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Bỏ')),
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
      NotificationOverlayManager().showError(title: 'Lỗi', message: 'Nhập tên mẫu in');
      return;
    }
    setState(() => _saving = true);
    final v2 = _v2Template!.copyWith(
      name: name,
      documentType: _docType,
      paperSize: _v2Template!.paperSize,
    );
    final body = _selected!.copyWith(
      name: name,
      htmlContent: PosPrintTemplateV2Codec.encode(v2),
      documentType: _docType,
      paperSize: v2.paperSize,
    ).toSaveJson();
    final res = await _api.updatePosPrintTemplate(_selected!.id, body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      _dirty = false;
      NotificationOverlayManager().showSuccess(title: 'Đã lưu', message: 'Mẫu in đã được cập nhật');
      await _load();
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không lưu được',
      );
    }
  }

  Future<void> _addTemplate() async {
    final presetsRes = await _api.getPosPrintTemplatePresets(documentType: _docType);
    final presets = presetsRes['isSuccess'] == true && presetsRes['data'] is List
        ? (presetsRes['data'] as List)
            .map((e) => PosPrintTemplatePreset.fromJson(e as Map<String, dynamic>))
            .toList()
        : <PosPrintTemplatePreset>[];

    String paper = PosPrintPaperSizes.k80;
    final nameCtrl = TextEditingController(text: 'Mẫu in mới');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Thêm mẫu in'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Tên mẫu in'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: paper,
                  decoration: const InputDecoration(labelText: 'Khổ giấy'),
                  items: PosPrintPaperSizes.labels.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setDlg(() => paper = v);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: paper,
                  decoration: const InputDecoration(labelText: 'Mẫu gợi ý'),
                  items: presets
                      .map((p) => DropdownMenuItem(
                            value: p.paperSize,
                            child: Text(p.name),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    final preset = presets.where((p) => p.paperSize == v).firstOrNull;
                    setDlg(() {
                      paper = v;
                      if (preset != null && nameCtrl.text == 'Mẫu in mới') {
                        nameCtrl.text = preset.name;
                      }
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Bỏ qua')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tạo')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    final v2Preset = PosPrintTemplateV2Presets.build(
      documentType: _docType,
      paperSize: paper,
      printerProfile: paper == PosPrintPaperSizes.k58
          ? PosPrintPrinterProfiles.sunmiK58
          : PosPrintPrinterProfiles.zywellK80,
      name: nameCtrl.text.trim().isEmpty ? PosPrintPaperSizes.labels[paper] : nameCtrl.text.trim(),
    );

    final res = await _api.createPosPrintTemplate({
      'name': nameCtrl.text.trim().isEmpty ? PosPrintPaperSizes.labels[paper] : nameCtrl.text.trim(),
      'documentType': _docType,
      'paperSize': paper,
      'htmlContent': PosPrintTemplateV2Codec.encode(v2Preset),
      'isDefault': _templates.isEmpty,
      'isActive': true,
      'sortOrder': _templates.length,
    });
    if (res['isSuccess'] == true && res['data'] is Map) {
      NotificationOverlayManager().showSuccess(title: 'Đã tạo', message: 'Mẫu in mới');
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
      final isKitchen = v2.documentType == PosPrintDocumentTypes.kitchenSlip ||
          v2.documentType == PosPrintDocumentTypes.kitchenVoid;
      final output = isKitchen
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
              lineItems: posPrintSampleLines(),
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
          kitchenFeed: isKitchen,
        );
        if (!mounted) return;
        if (ok) {
          NotificationOverlayManager()
              .showSuccess(title: 'In thử', message: 'Đã in mẫu trên Sunmi');
        } else {
          NotificationOverlayManager().showError(
            title: 'In thử thất bại',
            message: 'Sunmi không phản hồi',
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
            .showSuccess(title: 'In thử', message: 'Đã gửi mẫu in thử');
      } else {
        NotificationOverlayManager().showError(
          title: 'In thử thất bại',
          message: 'Kiểm tra kết nối máy in cục bộ',
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
        title: const Text('Xóa mẫu in?'),
        content: Text('Xóa mẫu «${_selected!.name}»?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa'),
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
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: PosTheme.border)),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
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
                          foregroundColor: active ? _blue : PosTheme.textPrimary,
                          backgroundColor: active ? const Color(0xFFE8F0FE) : null,
                        ),
                        child: Text(e.value,
                            style: TextStyle(
                              fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                              fontSize: 13,
                            )),
                      ),
                    );
                  }).toList(),
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
                            decoration: const InputDecoration(
                              labelText: 'Tên mẫu in',
                              isDense: true,
                            ),
                            onChanged: (_) => setState(() => _dirty = true),
                          ),
                        ),
                        Expanded(
                          child: _v2Template == null
                              ? const Center(child: Text('Đang tải…'))
                              : PosPrintTemplateV2Editor(
                                  template: _v2Template!,
                                  onChanged: (v) => setState(() {
                                    _v2Template = v;
                                    _dirty = true;
                                  }),
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
              decoration: const InputDecoration(
                labelText: 'Tên mẫu in',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() => _dirty = true),
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
                      _dirty = true;
                    }),
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
        hintText: _templates.isEmpty ? 'Chưa có mẫu — bấm +' : null,
      ),
      items: _templates
          .map((t) => DropdownMenuItem(
                value: t.id,
                child: Text('${t.name} (${PosPrintPaperSizes.labels[t.paperSize] ?? t.paperSize})'),
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
              const Text('Mẫu in', style: TextStyle(fontWeight: FontWeight.w600)),
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
                    tooltip: 'Xóa mẫu',
                    onPressed: _selected == null ? null : _deleteTemplate,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                  ),
                  IconButton(
                    tooltip: 'In thử',
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
                    label: const Text('Lưu'),
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
                      label: const Text('Thêm'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _selected == null ? null : _deleteTemplate,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Xóa'),
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
                      label: const Text('In thử'),
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
                      label: const Text('Lưu'),
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
          const Text('Mẫu in:', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(child: selector),
          IconButton(
            tooltip: 'Thêm mẫu',
            onPressed: _addTemplate,
            icon: const Icon(Icons.add_circle_outline, color: _blue),
          ),
          IconButton(
            tooltip: 'Xóa mẫu',
            onPressed: _selected == null ? null : _deleteTemplate,
            icon: const Icon(Icons.delete_outline, color: Colors.red),
          ),
          IconButton(
            tooltip: 'In thử',
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
            label: const Text('Lưu'),
          ),
        ],
      ),
    );
  }
}
