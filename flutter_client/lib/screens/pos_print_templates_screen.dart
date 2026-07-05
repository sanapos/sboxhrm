import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/pos_print_template.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';
import '../utils/pos_print_template_defaults.dart';
import '../utils/pos_print_template_renderer.dart';
import '../utils/pos_html_print.dart';
import '../utils/responsive_helper.dart';
import '../widgets/pos/pos_html_preview_stub.dart'
    if (dart.library.js_interop) '../widgets/pos/pos_html_preview_web.dart';
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
  final _editorCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  String _docType = PosPrintDocumentTypes.saleInvoice;
  List<PosPrintTemplate> _templates = [];
  List<PosPrintTemplatePreset> _presets = [];
  PosPrintTemplate? _selected;
  bool _loading = true;
  bool _saving = false;
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
    _editorCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPresets() async {
    final res = await _api.getPosPrintTemplatePresets(documentType: _docType);
    if (res['isSuccess'] == true && res['data'] is List) {
      _presets = (res['data'] as List)
          .map((e) => PosPrintTemplatePreset.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  String _htmlForPaper(String paperSize) {
    final fromPreset =
        _presets.where((p) => p.paperSize == paperSize).firstOrNull?.htmlContent;
    if (fromPreset != null && fromPreset.trim().isNotEmpty) return fromPreset;
    return posPrintDefaultHtml(documentType: _docType, paperSize: paperSize);
  }

  void _applyLocalDefault({String paperSize = PosPrintPaperSizes.k80}) {
    _selected = null;
    _editorCtrl.text = _htmlForPaper(paperSize);
    _nameCtrl.text = posPrintDefaultTemplateName(paperSize);
    _dirty = false;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _loadPresets();

    var res = await _api.getPosPrintTemplates(documentType: _docType);
    if (res['isSuccess'] == true && res['data'] is List) {
      _templates = (res['data'] as List)
          .map((e) => PosPrintTemplate.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    if (_templates.isEmpty) {
      await _api.seedPosPrintTemplates(documentType: _docType);
      res = await _api.getPosPrintTemplates(documentType: _docType);
      if (res['isSuccess'] == true && res['data'] is List) {
        _templates = (res['data'] as List)
            .map((e) => PosPrintTemplate.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    }

    _selected = _templates.where((t) => t.isDefault).firstOrNull ??
        _templates.firstOrNull;

    if (_selected != null) {
      final html = _selected!.htmlContent.trim().isNotEmpty
          ? _selected!.htmlContent
          : _htmlForPaper(_selected!.paperSize);
      _editorCtrl.text = html;
      _nameCtrl.text = _selected!.name;
    } else {
      _applyLocalDefault();
    }
    _dirty = false;

    if (!mounted) return;
    setState(() => _loading = false);
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
        _editorCtrl.text =
            t.htmlContent.trim().isNotEmpty ? t.htmlContent : _htmlForPaper(t.paperSize);
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

  String get _previewHtml {
    final src = _editorCtrl.text.trim();
    if (src.isEmpty) return '';
    return renderSampleTemplatePreview(
      src,
      documentType: _docType,
      paperSize: _selected?.paperSize ?? PosPrintPaperSizes.k80,
    );
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
    final body = _selected!.copyWith(
      name: name,
      htmlContent: _editorCtrl.text,
      documentType: _docType,
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
    String html = presets.isNotEmpty ? presets.first.htmlContent : '';
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
                    setDlg(() {
                      paper = v;
                      final preset = presets.where((p) => p.paperSize == v).firstOrNull;
                      if (preset != null) html = preset.htmlContent;
                    });
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
                      if (preset != null) {
                        html = preset.htmlContent;
                        if (nameCtrl.text == 'Mẫu in mới') {
                          nameCtrl.text = preset.name;
                        }
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

    final res = await _api.createPosPrintTemplate({
      'name': nameCtrl.text.trim().isEmpty ? PosPrintPaperSizes.labels[paper] : nameCtrl.text.trim(),
      'documentType': _docType,
      'paperSize': paper,
      'htmlContent': html,
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

  void _insertToken(String token) {
    final text = _editorCtrl.text;
    final sel = _editorCtrl.selection;
    final insert = '{$token}';
    final start = sel.start >= 0 ? sel.start : text.length;
    final end = sel.end >= 0 ? sel.end : text.length;
    final next = text.replaceRange(start, end, insert);
    _editorCtrl.text = next;
    _editorCtrl.selection = TextSelection.collapsed(offset: start + insert.length);
    setState(() {
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
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
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Card(
                            margin: EdgeInsets.zero,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                                  child: TextField(
                                    controller: _nameCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'Tên mẫu in',
                                      isDense: true,
                                    ),
                                    onChanged: (_) => setState(() => _dirty = true),
                                  ),
                                ),
                                _tokenToolbar(),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: TextField(
                                      controller: _editorCtrl,
                                      maxLines: null,
                                      expands: true,
                                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                                      decoration: const InputDecoration(
                                        hintText: 'HTML mẫu in — dùng {Token} và <!--BEGIN_ITEMS-->...<!--END_ITEMS-->',
                                        border: OutlineInputBorder(),
                                      ),
                                      onChanged: (_) => setState(() {
                                        _dirty = true;
                                      }),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Card(
                            margin: EdgeInsets.zero,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                                  child: Row(
                                    children: [
                                      const Text('Xem trước mẫu in',
                                          style: TextStyle(fontWeight: FontWeight.w600)),
                                      const Spacer(),
                                      if (kIsWeb)
                                        TextButton.icon(
                                          onPressed: _previewHtml.isEmpty
                                              ? null
                                              : () => showPosHtmlPrintDialog(
                                                    context,
                                                    title: 'Xem trước in',
                                                    htmlDocument: _previewHtml,
                                                  ),
                                          icon: const Icon(Icons.print, size: 18),
                                          label: const Text('In thử'),
                                        ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        border: Border.all(color: PosTheme.border),
                                        color: Colors.grey.shade50,
                                      ),
                                      child: _previewHtml.isEmpty
                                          ? const Center(child: Text('Chưa có nội dung'))
                                          : buildPosHtmlPreview(_previewHtml),
                                    ),
                                  ),
                                ),
                              ],
                            ),
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
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            labelColor: _blue,
            tabs: [
              Tab(text: 'Soạn mẫu'),
              Tab(text: 'Xem trước'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                Card(
                  margin: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                        child: TextField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Tên mẫu in',
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() => _dirty = true),
                        ),
                      ),
                      _tokenToolbar(),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: TextField(
                            controller: _editorCtrl,
                            maxLines: null,
                            expands: true,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                            decoration: const InputDecoration(
                              hintText: 'HTML mẫu in — {Token}, <!--BEGIN_ITEMS-->...',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setState(() => _dirty = true),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Card(
                  margin: const EdgeInsets.all(12),
                  child: _previewHtml.isEmpty
                      ? const Center(child: Text('Chưa có nội dung'))
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: buildPosHtmlPreview(_previewHtml),
                        ),
                ),
              ],
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
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Mẫu in', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            selector,
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _addTemplate,
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Thêm'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _selected == null ? null : _deleteTemplate,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Xóa'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
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
                ),
              ],
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

  Widget _tokenToolbar() {
    Widget chips(String title, List<(String, String)> tokens) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: tokens
                  .map((t) => ActionChip(
                        label: Text(t.$2, style: const TextStyle(fontSize: 11)),
                        onPressed: () => _insertToken(t.$1),
                      ))
                  .toList(),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          chips('Cửa hàng', PosPrintTokens.store),
          chips('Đơn hàng', PosPrintTokens.order),
          chips('Khách', PosPrintTokens.customer),
          chips('Dòng hàng', PosPrintTokens.line),
          chips('Tổng', PosPrintTokens.totals),
        ],
      ),
    );
  }
}
