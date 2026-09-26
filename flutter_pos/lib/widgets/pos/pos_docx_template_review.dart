import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../utils/file_saver.dart' as file_saver;
import '../notification_overlay.dart';
import 'pos_docx_editor_stub.dart'
    if (dart.library.js_interop) 'pos_docx_editor_web.dart';
import 'pos_pdf_iframe_stub.dart'
    if (dart.library.js_interop) 'pos_pdf_iframe_web.dart';
import 'pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

const _docxMime =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

/// Tải file .docx của khách → AI gắn mã trường → mở màn xem lại. Trả `true` nếu đã tạo mẫu.
Future<bool> importPosDocxTemplateWithAi(
  BuildContext context,
  ApiService api, {
  required String documentType,
  /// File .docx đã chọn sẵn (nút tải mẫu chung); null = mở hộp chọn file.
  PlatformFile? file,
}) async {
  var f = file;
  if (f == null) {
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['docx'],
      withData: true,
    );
    if (pick == null || pick.files.isEmpty) return false;
    f = pick.files.first;
  }
  if (f.bytes == null || !context.mounted) return false;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(children: [
        const CircularProgressIndicator(),
        const SizedBox(width: 16),
        Expanded(child: Text(tr('AI đang đọc mẫu Word… (30–60 giây)'))),
      ]),
    ),
  );
  final res = await api.importPosDocxTemplate(
    bytes: f.bytes!,
    fileName: f.name,
    documentType: documentType,
    name: f.name.replaceAll(RegExp(r'\.docx$', caseSensitive: false), ''),
  );
  if (!context.mounted) return false;
  Navigator.of(context, rootNavigator: true).pop();
  if (res['isSuccess'] != true || res['data'] is! Map) {
    NotificationOverlayManager().showError(
      title: tr('Không tạo được mẫu Word'),
      message: res['message']?.toString() ?? tr('Vui lòng thử lại'),
    );
    return false;
  }
  final data = Map<String, dynamic>.from(res['data'] as Map);
  await showPosDocxTemplateReview(context, api, data['templateId'].toString(), initial: data);
  return true;
}

/// Xem lại / sửa các chỗ đã gắn mã trường trong mẫu Word. Trả `true` nếu có lưu.
Future<bool> showPosDocxTemplateReview(
  BuildContext context,
  ApiService api,
  String templateId, {
  Map<String, dynamic>? initial,
}) async {
  final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _DocxReviewPage(api: api, templateId: templateId, initial: initial),
  ));
  return saved == true;
}

/// Trường đặc biệt: sửa câu chữ cố định / xóa chữ (khớp máy chủ).
const _textField = '_Text';
const _clearField = '_Xoa';

class _Item {
  _Item(this.paragraphId, this.find, this.field, this.context, {this.start, this.text});
  final String paragraphId;
  final String find;
  String field;
  final String? context;
  /// Vị trí ký tự trong chữ gốc của đoạn (chọn trên màn soạn).
  final int? start;
  /// Câu chữ mới khi field = _Text.
  String? text;

  _Item copy() => _Item(paragraphId, find, field, context, start: start, text: text);

  bool overlaps(String pid, int s, int e) =>
      pid == paragraphId && start != null && s < start! + find.length && e > start!;

  Map<String, dynamic> toJson() => {
        'paragraphId': paragraphId,
        'find': find,
        'field': field,
        'context': context,
        if (start != null) 'start': start,
        if (text != null) 'text': text,
      };
}

class _DocxReviewPage extends StatefulWidget {
  const _DocxReviewPage({required this.api, required this.templateId, this.initial});
  final ApiService api;
  final String templateId;
  final Map<String, dynamic>? initial;

  @override
  State<_DocxReviewPage> createState() => _DocxReviewPageState();
}

class _DocxReviewPageState extends State<_DocxReviewPage> {
  final _items = <_Item>[];
  var _removeRows = <String>[];
  var _paragraphs = <Map<String, dynamic>>[];
  var _warnings = <String>[];
  var _docFields = <MapEntry<String, String>>[];
  var _lineFields = <MapEntry<String, String>>[];
  String _name = '';
  bool _aiUsed = false;
  bool _loading = true;
  bool _saving = false;
  /// Đã lưu / thay file ít nhất một lần → màn trước cần tải lại.
  bool _changed = false;
  /// Tăng sau mỗi lần lưu để các tab xem trước dựng lại PDF.
  int _previewVersion = 0;

  // ── Soạn trực quan (web) ──
  String? _editorHtml;
  String? _editorError;
  bool _editorBusy = false;
  /// Trạng thái trước mỗi thao tác (Hoàn tác).
  final _history = <(List<_Item>, List<String>)>[];

  @override
  void initState() {
    super.initState();
    _load();
    if (posDocxEditorSupported) _loadEditor();
  }

  Future<void> _loadEditor() async {
    final res = await widget.api.getPosDocxTemplateEditor(widget.templateId);
    if (!mounted) return;
    setState(() {
      if (res['isSuccess'] == true && res['data'] is Map) {
        _editorHtml = (res['data'] as Map)['html']?.toString();
        _editorError = null;
      } else {
        _editorError = res['message']?.toString() ?? tr('Không dựng được trang soạn');
      }
    });
  }

  String _paraText(String pid) {
    for (final p in _paragraphs) {
      if (p['id'] == pid) return '${p['text']}';
    }
    return '';
  }

  /// Áp một thao tác soạn: ghi lại để Hoàn tác, lưu ngay, dựng lại trang soạn + bản xem PDF.
  Future<void> _commit(List<_Item> items, List<String> removeRows) async {
    if (_editorBusy) return;
    _history.add((_items.map((e) => e.copy()).toList(), List.of(_removeRows)));
    if (_history.length > 50) _history.removeAt(0);
    await _persist(items, removeRows);
  }

  Future<void> _persist(List<_Item> items, List<String> removeRows) async {
    setState(() => _editorBusy = true);
    final res = await widget.api.savePosDocxTemplateMapping(
      widget.templateId,
      items.map((e) => e.toJson()).toList(),
      removeRows,
    );
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      setState(() => _editorBusy = false);
      NotificationOverlayManager().showError(
          title: tr('Không lưu được'), message: res['message']?.toString() ?? tr('Vui lòng thử lại'));
      return;
    }
    setState(() {
      if (res['data'] is Map) _apply(Map<String, dynamic>.from(res['data'] as Map));
      _changed = true;
      _previewVersion++;
    });
    await _loadEditor();
    if (mounted) setState(() => _editorBusy = false);
  }

  Future<void> _undo() async {
    if (_history.isEmpty || _editorBusy) return;
    final (items, rows) = _history.removeLast();
    await _persist(items, rows);
  }

  Future<void> _restoreOriginal() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Khôi phục mẫu gốc?')),
        content: Text(tr('Bỏ toàn bộ trường đã gắn, chữ đã sửa và dòng đã bỏ — mẫu trở về đúng file bạn tải lên. '
            'Có thể Hoàn tác.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Khôi phục'))),
        ],
      ),
    );
    if (ok == true) await _commit([], []);
  }

  /// Chọn trường dữ liệu (tìm theo tên) — nhóm Chứng từ / Dòng hàng.
  Future<String?> _pickField({String? current, String? selectedText}) {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        var q = '';
        return StatefulBuilder(builder: (ctx, setLocal) {
          bool match(MapEntry<String, String> e) =>
              q.isEmpty || e.value.toLowerCase().contains(q) || e.key.toLowerCase().contains(q);
          final doc = _docFields.where((e) => e.key != _clearField && match(e)).toList();
          final line = _lineFields.where(match).toList();
          Widget tile(MapEntry<String, String> e, bool isLine) => ListTile(
                dense: true,
                selected: e.key == current,
                leading: Icon(isLine ? Icons.table_rows_outlined : Icons.label_outline,
                    size: 18, color: isLine ? const Color(0xFF0284C7) : const Color(0xFFD97706)),
                title: Text(e.value),
                subtitle: Text('{${e.key}}', style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                onTap: () => Navigator.pop(ctx, e.key),
              );
          return AlertDialog(
            title: Text(selectedText == null ? tr('Chọn trường dữ liệu') : tr('Gắn «$selectedText» với trường')),
            content: SizedBox(
              width: 520,
              height: 460,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: tr('Tìm: khách hàng, tổng cộng, ngày…'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (v) => setLocal(() => q = v.trim().toLowerCase()),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        if (doc.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
                            child: Text(tr('Thông tin chứng từ'),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                        for (final e in doc) tile(e, false),
                        if (line.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 10, 8, 2),
                            child: Text(tr('Dòng hàng (dòng bảng được lặp theo số mặt hàng)'),
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                        for (final e in line) tile(e, true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy')))],
          );
        });
      },
    );
  }

  Future<String?> _askText(String title, String initial) async {
    final ctrl = TextEditingController(text: initial);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            minLines: 1,
            maxLines: 6,
            decoration: InputDecoration(
              helperText: tr('Giữ nguyên định dạng chữ (font, cỡ, đậm) của chỗ đang sửa.'),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Áp dụng'))),
        ],
      ),
    );
    final v = ctrl.text;
    ctrl.dispose();
    return ok == true ? v : null;
  }

  List<String> _toggleRow(String pid) {
    final rows = List.of(_removeRows);
    rows.contains(pid) ? rows.remove(pid) : rows.add(pid);
    return rows;
  }

  /// Thao tác từ trang soạn: bôi đen chữ / bấm ô trường / chuột phải đoạn.
  Future<void> _onEditorMessage(Map<String, dynamic> m) async {
    if (_editorBusy) return;
    final type = m['type'];
    if (type == 'warn') {
      NotificationOverlayManager().showWarning(title: tr('Chọn lại'), message: tr('${m['msg'] ?? ''}'));
      return;
    }
    final pid = '${m['pid'] ?? ''}';
    final inTable = m['inTable'] == true;
    final rowRemoved = m['rowRemoved'] == true;

    if (type == 'select') {
      final start = (m['start'] as num).toInt();
      final end = (m['end'] as num).toInt();
      final text = _paraText(pid);
      if (text.isEmpty || start < 0 || end > text.length || end <= start) return;
      if (_items.any((it) => it.overlaps(pid, start, end))) {
        NotificationOverlayManager().showWarning(
            title: tr('Chồng lên chỗ đã gắn'), message: tr('Bấm vào ô màu để đổi / bỏ chỗ đó trước.'));
        return;
      }
      final find = text.substring(start, end);
      final action = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text('«${find.length > 60 ? '${find.substring(0, 60)}…' : find}»',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(tr('Chọn cách xử lý chữ đã bôi đen')),
              ),
              ListTile(
                leading: const Icon(Icons.label_outline, color: Color(0xFFD97706)),
                title: Text(tr('Gắn trường dữ liệu động')),
                subtitle: Text(tr('Khi in sẽ thay bằng dữ liệu thật (tên khách, tổng tiền…)')),
                onTap: () => Navigator.pop(ctx, 'field'),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: Color(0xFF16A34A)),
                title: Text(tr('Sửa câu chữ')),
                onTap: () => Navigator.pop(ctx, 'text'),
              ),
              ListTile(
                leading: const Icon(Icons.backspace_outlined, color: Color(0xFFDC2626)),
                title: Text(tr('Xóa chữ này khi in')),
                onTap: () => Navigator.pop(ctx, 'clear'),
              ),
              if (inTable)
                ListTile(
                  leading: const Icon(Icons.table_rows_outlined),
                  title: Text(rowRemoved ? tr('Giữ lại dòng bảng này') : tr('Bỏ cả dòng bảng này khi in (dòng mẫu thừa)')),
                  onTap: () => Navigator.pop(ctx, 'row'),
                ),
            ],
          ),
        ),
      );
      if (action == null || !mounted) return;
      final items = _items.map((e) => e.copy()).toList();
      switch (action) {
        case 'field':
          final f = await _pickField(selectedText: find.length > 40 ? '${find.substring(0, 40)}…' : find);
          if (f == null) return;
          items.add(_Item(pid, find, f, text, start: start));
        case 'text':
          final v = await _askText(tr('Sửa câu chữ'), find);
          if (v == null || v == find) return;
          items.add(_Item(pid, find, _textField, text, start: start, text: v));
        case 'clear':
          items.add(_Item(pid, find, _clearField, text, start: start));
        case 'row':
          await _commit(_items.map((e) => e.copy()).toList(), _toggleRow(pid));
          return;
      }
      await _commit(items, List.of(_removeRows));
      return;
    }

    if (type == 'chip') {
      final start = (m['start'] as num).toInt();
      final idx = _items.indexWhere((it) => it.paragraphId == pid && it.start == start);
      if (idx < 0) return;
      final it = _items[idx];
      final isText = it.field == _textField;
      final isClear = it.field == _clearField;
      final action = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(isText
                    ? tr('Chữ đã sửa: «${it.text ?? ''}»')
                    : isClear
                        ? tr('Chữ đã xóa: «${it.find}»')
                        : tr('Trường: ${_label(it.field)}'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(tr('Chữ gốc: «${it.find}»')),
              ),
              if (!isText && !isClear)
                ListTile(
                  leading: const Icon(Icons.swap_horiz),
                  title: Text(tr('Đổi sang trường khác')),
                  onTap: () => Navigator.pop(ctx, 'change'),
                ),
              if (isText)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: Text(tr('Sửa lại câu chữ')),
                  onTap: () => Navigator.pop(ctx, 'retext'),
                ),
              ListTile(
                leading: const Icon(Icons.undo, color: Color(0xFFDC2626)),
                title: Text(tr('Bỏ — trả lại chữ gốc')),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
              if (inTable)
                ListTile(
                  leading: const Icon(Icons.table_rows_outlined),
                  title: Text(rowRemoved ? tr('Giữ lại dòng bảng này') : tr('Bỏ cả dòng bảng này khi in')),
                  onTap: () => Navigator.pop(ctx, 'row'),
                ),
            ],
          ),
        ),
      );
      if (action == null || !mounted) return;
      final items = _items.map((e) => e.copy()).toList();
      switch (action) {
        case 'change':
          final f = await _pickField(current: it.field);
          if (f == null || f == it.field) return;
          items[idx].field = f;
        case 'retext':
          final v = await _askText(tr('Sửa câu chữ'), it.text ?? it.find);
          if (v == null) return;
          items[idx].text = v;
        case 'remove':
          items.removeAt(idx);
        case 'row':
          await _commit(items, _toggleRow(pid));
          return;
      }
      await _commit(items, List.of(_removeRows));
      return;
    }

    if (type == 'para' && inTable) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(rowRemoved ? tr('Giữ lại dòng bảng này?') : tr('Bỏ dòng bảng này khi in?')),
          content: Text(rowRemoved
              ? tr('Dòng sẽ được in như trong file gốc.')
              : tr('Dùng cho các dòng hàng mẫu thừa (dòng 2, 3… của bảng hàng trong file gốc).')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Đồng ý'))),
          ],
        ),
      );
      if (ok == true) await _commit(_items.map((e) => e.copy()).toList(), _toggleRow(pid));
    }
  }

  Widget _buildEditorTab() {
    if (_editorError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_editorError!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    if (_editorHtml == null) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: const Color(0xFFEFF6FF),
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                tr('Bôi đen chữ → gắn trường / sửa / xóa · Bấm ô màu để đổi hoặc bỏ · Chuột phải một dòng bảng để bỏ dòng mẫu'),
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF1E3A8A)),
              ),
              _legend(const Color(0xFFFDE68A), tr('Trường chứng từ')),
              _legend(const Color(0xFFBAE6FD), tr('Dòng hàng (lặp)')),
              _legend(const Color(0xFFDCFCE7), tr('Chữ đã sửa')),
              _legend(const Color(0xFFFEE2E2), tr('Chữ đã xóa')),
              TextButton.icon(
                onPressed: _history.isEmpty || _editorBusy ? null : _undo,
                icon: const Icon(Icons.undo, size: 18),
                label: Text(tr('Hoàn tác')),
              ),
              TextButton.icon(
                onPressed: _editorBusy || (_items.isEmpty && _removeRows.isEmpty) ? null : _restoreOriginal,
                icon: const Icon(Icons.restore, size: 18),
                label: Text(tr('Khôi phục mẫu gốc')),
              ),
              if (_editorBusy)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
        ),
        Expanded(child: PosDocxEditorFrame(html: _editorHtml!, onMessage: _onEditorMessage)),
      ],
    );
  }

  Widget _legend(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );

  void _apply(Map<String, dynamic> d) {
    _name = (d['name'] ?? '').toString();
    _aiUsed = d['aiUsed'] == true;
    _warnings = ((d['warnings'] as List?) ?? const []).map((e) => '$e').toList();
    _removeRows = ((d['removeRowParagraphIds'] as List?) ?? const []).map((e) => '$e').toList();
    _paragraphs = ((d['paragraphs'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    _items
      ..clear()
      ..addAll(((d['replacements'] as List?) ?? const []).whereType<Map>().map((e) => _Item(
            '${e['paragraphId']}',
            '${e['find']}',
            '${e['field']}',
            e['context']?.toString(),
            start: (e['start'] as num?)?.toInt(),
            text: e['text']?.toString(),
          )));
  }

  Future<void> _load() async {
    final fields = await widget.api.getPosDocxTemplateFields();
    final mapping = widget.initial ??
        (await widget.api.getPosDocxTemplateMapping(widget.templateId))['data'];
    if (!mounted) return;
    setState(() {
      if (fields['isSuccess'] == true && fields['data'] is Map) {
        final f = fields['data'] as Map;
        List<MapEntry<String, String>> read(dynamic raw) => ((raw as List?) ?? const [])
            .whereType<Map>()
            .map((e) => MapEntry('${e['key']}', '${e['label']}'))
            .toList();
        _docFields = read(f['document']);
        _lineFields = read(f['line']);
      }
      if (mapping is Map) _apply(Map<String, dynamic>.from(mapping));
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final res = await widget.api.savePosDocxTemplateMapping(
      widget.templateId,
      _items.map((e) => e.toJson()).toList(),
      _removeRows,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: tr('Không lưu được'),
        message: res['message']?.toString() ?? tr('Vui lòng thử lại'),
      );
      return;
    }
    setState(() {
      if (res['data'] is Map) _apply(Map<String, dynamic>.from(res['data'] as Map));
      _changed = true;
      _previewVersion++;
    });
    if (posDocxEditorSupported) _loadEditor();
    NotificationOverlayManager().showSuccess(
      title: tr('Đã lưu mẫu Word'),
      message: tr('Xem tab «Bản in thử» để kiểm tra. Xuất báo giá / hợp đồng sẽ dùng mẫu này.'),
    );
  }

  Future<void> _download() async {
    final res = await widget.api.downloadPosDocxTemplate(widget.templateId);
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
          title: tr('Không tải được'), message: res['message']?.toString() ?? '');
      return;
    }
    await file_saver.saveAndOpenFileBytes(
        List<int>.from(res['data'] as List), '$_name.docx', _docxMime);
  }

  Future<void> _uploadEdited() async {
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['docx'],
      withData: true,
    );
    if (pick == null || pick.files.first.bytes == null) return;
    final res = await widget.api.replacePosDocxTemplate(
        widget.templateId, pick.files.first.bytes!, pick.files.first.name);
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
          title: tr('Không tải lên được'), message: res['message']?.toString() ?? '');
      return;
    }
    NotificationOverlayManager().showSuccess(
      title: tr('Đã thay mẫu Word'),
      message: tr('Dùng đúng file bạn đã sửa (giữ các mã {Truong} trong file).'),
    );
    final mapping = await widget.api.getPosDocxTemplateMapping(widget.templateId);
    if (!mounted) return;
    setState(() {
      if (mapping['data'] is Map) _apply(Map<String, dynamic>.from(mapping['data'] as Map));
      _changed = true;
      _previewVersion++;
      _history.clear(); // file gốc đã đổi
    });
    if (posDocxEditorSupported) _loadEditor();
  }

  String _label(String key) {
    for (final e in [..._docFields, ..._lineFields]) {
      if (e.key == key) return e.value;
    }
    return key;
  }

  List<DropdownMenuItem<String>> _fieldItems() => [
        for (final e in _docFields)
          DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
        for (final e in _lineFields)
          if (!_docFields.any((d) => d.key == e.key))
            DropdownMenuItem(
                value: e.key,
                child: Text('${tr('Dòng hàng')}: ${e.value}', overflow: TextOverflow.ellipsis)),
      ];

  Future<void> _addManual() async {
    if (_paragraphs.isEmpty) return;
    Map<String, dynamic>? para = _paragraphs.first;
    final findCtrl = TextEditingController(text: '${para['text']}');
    String? field = _docFields.isNotEmpty ? _docFields.first.key : null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(tr('Gắn thêm trường')),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<Map<String, dynamic>>(
                  isExpanded: true,
                  value: para,
                  decoration: InputDecoration(labelText: tr('Đoạn văn')),
                  items: [
                    for (final p in _paragraphs)
                      DropdownMenuItem(
                        value: p,
                        child: Text('${p['inTable'] == true ? '▦ ' : ''}${p['text']}',
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setLocal(() {
                    para = v;
                    findCtrl.text = '${v?['text'] ?? ''}';
                  }),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: findCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: tr('Chữ cần thay (xóa bớt để chỉ giữ phần dữ liệu)'),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: field,
                  decoration: InputDecoration(labelText: tr('Trường dữ liệu')),
                  items: _fieldItems(),
                  onChanged: (v) => setLocal(() => field = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Thêm'))),
          ],
        ),
      ),
    );
    final find = findCtrl.text;
    findCtrl.dispose();
    if (ok != true || para == null || field == null || find.trim().isEmpty) return;
    final text = '${para!['text']}';
    if (!text.contains(find)) {
      NotificationOverlayManager().showError(
          title: tr('Không khớp'), message: tr('Chữ cần thay phải nằm trong đoạn đã chọn.'));
      return;
    }
    setState(() {
      _items.add(_Item('${para!['id']}', find, field!, text));
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      // ignore: deprecated_member_use
      onPopInvoked: (didPop) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: DefaultTabController(
        length: posDocxEditorSupported ? 5 : 4,
        initialIndex: 1,
        child: Builder(
          builder: (context) => Scaffold(
            backgroundColor: PosTheme.background,
            appBar: AppBar(
              title: Text(_name.isEmpty ? tr('Mẫu Word') : _name),
              actions: [
                IconButton(
                    tooltip: tr('Tải file Word để sửa tay'),
                    onPressed: _loading ? null : _download,
                    icon: const Icon(Icons.download)),
                IconButton(
                    tooltip: tr('Tải lên bản đã sửa'),
                    onPressed: _loading ? null : _uploadEdited,
                    icon: const Icon(Icons.upload_file)),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: FilledButton.icon(
                    onPressed: _loading || _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save),
                    label: Text(tr('Lưu')),
                  ),
                ),
              ],
              bottom: TabBar(
                isScrollable: true,
                tabs: [
                  Tab(icon: const Icon(Icons.description_outlined, size: 18), text: tr('Mẫu gốc')),
                  if (posDocxEditorSupported)
                    Tab(icon: const Icon(Icons.edit_document, size: 18), text: tr('Soạn mẫu')),
                  Tab(icon: const Icon(Icons.highlight_alt, size: 18), text: tr('Mẫu gắn trường')),
                  Tab(icon: const Icon(Icons.print_outlined, size: 18), text: tr('Bản in thử')),
                  Tab(
                      icon: const Icon(Icons.list_alt, size: 18),
                      text: tr('Trường đã gắn (${_items.length})')),
                ],
              ),
            ),
            body: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _DocxPdfTab(
                        key: ValueKey('original-${widget.templateId}'),
                        api: widget.api,
                        templateId: widget.templateId,
                        view: 'original',
                        version: _previewVersion,
                        hint: tr('Đúng file bạn tải lên — dùng để so sánh với mẫu đã gắn trường.'),
                      ),
                      if (posDocxEditorSupported) _buildEditorTab(),
                      _DocxPdfTab(
                        key: ValueKey('fields-${widget.templateId}'),
                        api: widget.api,
                        templateId: widget.templateId,
                        view: 'fields',
                        version: _previewVersion,
                        hint: tr('Chỗ tô vàng = dữ liệu động của chứng từ; tô xanh = dòng hàng (lặp theo số mặt hàng). '
                            'Sai / thiếu: sửa ở tab «Trường đã gắn» rồi Lưu.'),
                      ),
                      _DocxPdfTab(
                        key: ValueKey('sample-${widget.templateId}'),
                        api: widget.api,
                        templateId: widget.templateId,
                        view: 'sample',
                        version: _previewVersion,
                        hint: tr('Mẫu điền dữ liệu giả (2 dòng hàng) — đúng như khi xuất PDF báo giá / hợp đồng.'),
                      ),
                      _buildFieldList(),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildFieldList() {
    return Scaffold(
      backgroundColor: PosTheme.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addManual,
        icon: const Icon(Icons.add),
        label: Text(tr('Gắn thêm trường')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _aiUsed
                        ? tr('AI đã gắn ${_items.length} chỗ dữ liệu. Kiểm tra từng chỗ, đổi trường nếu sai, xóa chỗ không cần.')
                        : tr('${_items.length} chỗ đang gắn trường.'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (_removeRows.isNotEmpty)
                    Text(tr('Đã bỏ ${_removeRows.length} dòng hàng mẫu thừa trong bảng.'),
                        style: TextStyle(color: Colors.grey.shade700)),
                  const SizedBox(height: 4),
                  Text(
                    tr('Bố cục, bảng, logo của file giữ nguyên. Dòng hàng đầu tiên trong bảng sẽ được lặp lại theo số mặt hàng. '
                        'Sửa xong bấm Lưu rồi xem lại tab «Mẫu gắn trường» / «Bản in thử».'),
                    style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                  ),
                  for (final w in _warnings)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('• $w', style: TextStyle(color: Colors.orange.shade800, fontSize: 12)),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final it in _items) _buildItem(it),
        ],
      ),
    );
  }

  Widget _buildItem(_Item it) {
    final ctx = it.context ?? '';
    final idx = ctx.indexOf(it.find);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (idx >= 0)
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: ctx.substring(0, idx)),
                        TextSpan(
                          text: it.find,
                          style: const TextStyle(
                              backgroundColor: Color(0xFFFFF3C4), fontWeight: FontWeight.w700),
                        ),
                        TextSpan(text: ctx.substring(idx + it.find.length)),
                      ]),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    )
                  else
                    Text(it.find, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: _fieldItems().any((e) => e.value == it.field) ? it.field : null,
                    hint: Text(_label(it.field)),
                    items: _fieldItems(),
                    onChanged: (v) => setState(() {
                      if (v != null) it.field = v;
                                    }),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: tr('Bỏ chỗ này (giữ chữ gốc)'),
              onPressed: () => setState(() {
                _items.remove(it);
                        }),
              icon: const Icon(Icons.delete_outline, color: Colors.red),
            ),
          ],
        ),
      ),
    );
  }
}

/// Một tab xem PDF mẫu Word (gốc / gắn trường / in thử) — dựng ở máy chủ bằng LibreOffice nên giống bản in.
class _DocxPdfTab extends StatefulWidget {
  const _DocxPdfTab({
    super.key,
    required this.api,
    required this.templateId,
    required this.view,
    required this.version,
    required this.hint,
  });

  final ApiService api;
  final String templateId;
  final String view;
  final int version;
  final String hint;

  @override
  State<_DocxPdfTab> createState() => _DocxPdfTabState();
}

class _DocxPdfTabState extends State<_DocxPdfTab> with AutomaticKeepAliveClientMixin {
  Uint8List? _pdf;
  String? _error;
  bool _loading = false;
  int _loadedVersion = -1;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _DocxPdfTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.version != _loadedVersion) _load();
  }

  Future<void> _load() async {
    final version = widget.version;
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await widget.api.getPosDocxTemplatePreview(widget.templateId, widget.view);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _loadedVersion = version;
      if (res['isSuccess'] == true && res['data'] is List) {
        _pdf = Uint8List.fromList(List<int>.from(res['data'] as List));
      } else {
        _error = res['message']?.toString() ?? tr('Không dựng được bản xem trước');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: const Color(0xFFFFFBEB),
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 16, color: Color(0xFF92400E)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(widget.hint, style: const TextStyle(fontSize: 12.5, color: Color(0xFF92400E))),
              ),
              IconButton(
                tooltip: tr('Tải lại'),
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(tr('Đang dựng trang in… (lần đầu 5–15 giây)')),
                    ],
                  ),
                )
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                      ),
                    )
                  : _pdf == null
                      ? const SizedBox.shrink()
                      : KeyedSubtree(
                          key: ValueKey('${widget.view}-$_loadedVersion'),
                          child: buildPosPdfPreview(_pdf!),
                        ),
        ),
      ],
    );
  }
}
