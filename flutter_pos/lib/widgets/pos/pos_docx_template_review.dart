import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../utils/file_saver.dart' as file_saver;
import '../notification_overlay.dart';
import 'pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

const _docxMime =
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document';

/// Tải file .docx của khách → AI gắn mã trường → mở màn xem lại. Trả `true` nếu đã tạo mẫu.
Future<bool> importPosDocxTemplateWithAi(
  BuildContext context,
  ApiService api, {
  required String documentType,
}) async {
  final pick = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['docx'],
    withData: true,
  );
  if (pick == null || pick.files.isEmpty || pick.files.first.bytes == null) return false;
  final f = pick.files.first;
  if (!context.mounted) return false;

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

class _Item {
  _Item(this.paragraphId, this.find, this.field, this.context);
  final String paragraphId;
  final String find;
  String field;
  final String? context;

  Map<String, dynamic> toJson() =>
      {'paragraphId': paragraphId, 'find': find, 'field': field, 'context': context};
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

  @override
  void initState() {
    super.initState();
    _load();
  }

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
    NotificationOverlayManager().showSuccess(
      title: tr('Đã lưu mẫu Word'),
      message: tr('Xuất báo giá / hợp đồng sẽ dùng mẫu này (PDF hoặc Word).'),
    );
    Navigator.of(context).pop(true);
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
    Navigator.of(context).pop(true);
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
    return Scaffold(
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
      ),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: _addManual,
              icon: const Icon(Icons.add),
              label: Text(tr('Gắn thêm trường')),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
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
                          tr('Bố cục, bảng, logo của file giữ nguyên. Dòng hàng đầu tiên trong bảng sẽ được lặp lại theo số mặt hàng.'),
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                        ),
                        for (final w in _warnings)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('• $w',
                                style: TextStyle(color: Colors.orange.shade800, fontSize: 12)),
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
