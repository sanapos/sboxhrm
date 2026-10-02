import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

import '../../l10n/app_tr.dart';
import '../../models/comm_v2.dart';
import '../../services/api_service.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'comm_common.dart';

const _kDocExts = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'csv', 'jpg', 'jpeg', 'png', 'webp'];
const _kImageExts = ['jpg', 'jpeg', 'png', 'webp', 'gif'];

/// Chuyển khối AI ({type, text} có **đậm**) thành Quill Delta.
List<Map<String, dynamic>> commBlocksToOps(List<CommAiBlock> blocks, {List<({String q, String a})> faq = const []}) {
  final ops = <Map<String, dynamic>>[];
  void inline(String text) {
    final re = RegExp(r'\*\*(.+?)\*\*');
    var last = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > last) ops.add({'insert': text.substring(last, m.start)});
      ops.add({'insert': m.group(1), 'attributes': {'bold': true}});
      last = m.end;
    }
    if (last < text.length) ops.add({'insert': text.substring(last)});
  }

  void line(String type, String text) {
    final clean = text.replaceAll('\n', ' ').trim();
    if (clean.isEmpty) return;
    inline(clean);
    final attrs = switch (type) {
      'h1' || 'h2' => {'header': 2},
      'h3' => {'header': 3},
      'bullet' => {'list': 'bullet'},
      'ordered' => {'list': 'ordered'},
      'quote' => {'blockquote': true},
      _ => null,
    };
    ops.add(attrs == null ? {'insert': '\n'} : {'insert': '\n', 'attributes': attrs});
  }

  for (final b in blocks) {
    line(b.type, b.text);
  }
  if (faq.isNotEmpty) {
    line('h3', 'Câu hỏi thường gặp');
    for (final f in faq) {
      ops.add({'insert': f.q.trim(), 'attributes': {'bold': true}});
      ops.add({'insert': '\n'});
      line('p', f.a);
    }
  }
  if (ops.isEmpty || !(ops.last['insert'] as String).endsWith('\n')) ops.add({'insert': '\n'});
  return ops;
}

String commDeltaToHtml(quill.Document doc) {
  final ops = <Map<String, dynamic>>[];
  for (final op in doc.toDelta().toList()) {
    final map = <String, dynamic>{'insert': op.data};
    if (op.attributes != null && op.attributes!.isNotEmpty) map['attributes'] = Map<String, dynamic>.from(op.attributes!);
    ops.add(map);
  }
  return QuillDeltaToHtmlConverter(ops, ConverterOptions(multiLineBlockquote: true, multiLineHeader: false, multiLineCodeblock: true)).convert();
}

/// Trình soạn bài: tiêu đề, định dạng, ảnh, tệp, bình chọn, sự kiện, đối tượng nhận, xác nhận đọc, hẹn giờ, AI.
class CommEditorPage extends StatefulWidget {
  const CommEditorPage({super.key, required this.ctx, this.post, this.initialChannelId, this.startWithAi = false, this.initialMode});
  final CommContext ctx;
  final CommPost? post;
  final String? initialChannelId;
  final bool startWithAi;
  /// Mở sẵn: image (chọn ảnh) / file (chọn tài liệu) / poll (bật bình chọn).
  final String? initialMode;

  @override
  State<CommEditorPage> createState() => _CommEditorPageState();
}

class _CommEditorPageState extends State<CommEditorPage> {
  final _api = ApiService();
  final _title = TextEditingController();
  final _tags = TextEditingController();
  final _location = TextEditingController();
  final _pollQ = TextEditingController();
  final List<TextEditingController> _pollOpts = [];
  late quill.QuillController _ctrl;
  final _focus = FocusNode();
  final _scroll = ScrollController();

  String? _channelId;
  final List<String> _images = [];
  final List<CommAttachment> _files = [];
  bool _pollOn = false;
  bool _pollMultiple = false;
  bool _eventOn = false;
  DateTime? _eventAt;
  CommAudience _audience = CommAudience();
  bool _requireAck = false;
  DateTime? _ackDeadline;
  int _priority = 1;
  bool _pinned = false;
  bool _allowComments = true;
  DateTime? _scheduledAt;
  bool _bumpVersion = false;
  bool _aiGenerated = false;
  String? _summary;

  bool _uploading = false;
  bool _saving = false;
  bool _preview = false;
  bool _showAi = false;

  bool get _editing => widget.post != null;
  bool get _wasPublished => widget.post?.status == CommStatus.published;
  List<CommChannel> get _postable => widget.ctx.channels.where((c) => c.canPost).toList();
  CommChannel? get _channel => widget.ctx.channel(_channelId);

  @override
  void initState() {
    super.initState();
    final p = widget.post;
    _ctrl = quill.QuillController.basic();
    if (p != null) {
      _title.text = p.title;
      _tags.text = p.tags ?? '';
      _channelId = p.channelId;
      _images.addAll(p.images);
      _files.addAll(p.attachments);
      _requireAck = p.requireAck;
      _ackDeadline = p.ackDeadline;
      _priority = p.priority;
      _pinned = p.isPinned;
      _allowComments = p.allowComments;
      _audience = p.audience ?? CommAudience();
      _scheduledAt = p.scheduledAt;
      _aiGenerated = p.isAiGenerated;
      _summary = p.summary;
      if (p.eventAt != null) {
        _eventOn = true;
        _eventAt = p.eventAt;
        _location.text = p.eventLocation ?? '';
      }
      if (p.poll != null) {
        _pollOn = true;
        _pollQ.text = p.poll!.question;
        _pollMultiple = p.poll!.multiple;
        for (final o in p.poll!.options) {
          _pollOpts.add(TextEditingController(text: o.text));
        }
      }
      _loadContent(p);
    } else {
      _channelId = widget.initialChannelId != null && _postable.any((c) => c.id == widget.initialChannelId)
          ? widget.initialChannelId
          : (_postable.isEmpty ? null : _postable.first.id);
    }
    if (_pollOpts.isEmpty) _pollOpts.addAll([TextEditingController(), TextEditingController()]);
    _showAi = widget.startWithAi;
    _ctrl.addListener(_onDocChanged);
    if (p == null) {
      switch (widget.initialMode) {
        case 'poll':
          _pollOn = true;
        case 'image':
        case 'file':
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _addFiles(images: widget.initialMode == 'image');
          });
      }
    }
  }

  void _loadContent(CommPost p) {
    try {
      if (p.contentDelta != null && p.contentDelta!.isNotEmpty) {
        final ops = jsonDecode(p.contentDelta!) as List;
        _ctrl = quill.QuillController(document: quill.Document.fromJson(ops), selection: const TextSelection.collapsed(offset: 0));
        return;
      }
    } catch (_) {/* dữ liệu hỏng → dùng chữ thuần */}
    final text = p.contentHtml
        .replaceAll(RegExp(r'<br\s*/?>|</p>|</h\d>|</li>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .trim();
    _ctrl = quill.QuillController(
      document: quill.Document()..insert(0, text.isEmpty ? '' : text),
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  void _onDocChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onDocChanged);
    _ctrl.dispose();
    _focus.dispose();
    _scroll.dispose();
    for (final c in [_title, _tags, _location, _pollQ, ..._pollOpts]) {
      c.dispose();
    }
    super.dispose();
  }

  // ─── Tệp ─────────────────────────────────────────────────────

  Future<List<({List<int> bytes, String name})>?> _pick(List<String> exts, {bool multiple = true}) async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: multiple, withData: true, type: FileType.custom, allowedExtensions: exts);
    if (r == null) return null;
    final out = <({List<int> bytes, String name})>[];
    for (final f in r.files) {
      if (f.bytes == null) continue;
      if (f.size > 20 * 1024 * 1024) {
        if (mounted) commToast(context, '${f.name} vượt quá 20 MB', error: true);
        continue;
      }
      out.add((bytes: f.bytes!, name: f.name));
    }
    return out;
  }

  Future<void> _addFiles({required bool images}) async {
    final picked = await _pick(images ? _kImageExts : _kDocExts);
    if (picked == null || picked.isEmpty) return;
    setState(() => _uploading = true);
    final r = await _api.commUpload(picked);
    if (!mounted) return;
    setState(() => _uploading = false);
    if (r['isSuccess'] != true || r['data'] is! Map) {
      commToast(context, '${r['message'] ?? 'Không tải được tệp'}', error: true);
      return;
    }
    final d = r['data'] as Map;
    final atts = (d['attachments'] as List? ?? []).whereType<Map>().map((e) => CommAttachment.fromJson(Map<String, dynamic>.from(e)));
    setState(() {
      for (final a in atts) {
        if (a.isImage) {
          _images.add(a.url);
        } else {
          _files.add(a);
        }
      }
    });
    final warns = (d['warnings'] as List? ?? []).map((e) => '$e').toList();
    if (warns.isNotEmpty) commToast(context, warns.join('\n'), error: true);
  }

  // ─── AI ──────────────────────────────────────────────────────

  /// Áp bản nháp AI: thay nội dung (hoặc chèn cuối), đặt tiêu đề, gợi ý kênh / bắt buộc đọc.
  void _applyDraft(CommAiDraft d, {bool append = false}) {
    final ops = commBlocksToOps(d.blocks, faq: d.faq);
    setState(() {
      final merged = append && _ctrl.document.toPlainText().trim().isNotEmpty
          ? [..._ctrl.document.toDelta().toJson(), ...ops]
          : ops;
      _ctrl.removeListener(_onDocChanged);
      _ctrl.dispose();
      _ctrl = quill.QuillController(document: quill.Document.fromJson(merged), selection: const TextSelection.collapsed(offset: 0));
      _ctrl.addListener(_onDocChanged);
      if (d.title.isNotEmpty && (_title.text.trim().isEmpty || !append)) _title.text = d.title;
      if (d.summary.isNotEmpty) _summary = d.summary;
      if (d.tags.isNotEmpty && _tags.text.trim().isEmpty) _tags.text = d.tags.take(5).join(', ');
      if (!_editing && d.suggestedChannel != null) {
        final ch = _postable.where((c) => c.key == d.suggestedChannel).firstOrNull;
        if (ch != null) _channelId = ch.id;
      }
      if (d.suggestRequireAck && widget.ctx.isManager) _requireAck = true;
      _aiGenerated = true;
    });
  }

  void _addAiAttachments(List<CommAttachment> atts) {
    setState(() {
      for (final a in atts) {
        if (a.isImage) {
          _images.add(a.url);
        } else {
          _files.add(a);
        }
      }
    });
  }

  // ─── Lưu ─────────────────────────────────────────────────────

  Future<void> _save({required bool publish}) async {
    final text = _ctrl.document.toPlainText().trim();
    if (_title.text.trim().isEmpty && text.isEmpty && _images.isEmpty && _files.isEmpty && !_pollOn) {
      commToast(context, 'Bài viết đang trống', error: true);
      return;
    }
    if (_channelId == null) {
      commToast(context, 'Chọn kênh đăng bài', error: true);
      return;
    }
    if (_pollOn && (_pollQ.text.trim().isEmpty || _pollOpts.where((c) => c.text.trim().isNotEmpty).length < 2)) {
      commToast(context, 'Bình chọn cần câu hỏi và ít nhất 2 lựa chọn', error: true);
      return;
    }
    final existingPollIds = widget.post?.poll?.options.map((o) => o.id).toList() ?? const <String>[];
    final data = <String, dynamic>{
      'channelId': _channelId,
      'title': _title.text.trim(),
      'summary': _summary,
      'contentHtml': text.isEmpty ? '' : commDeltaToHtml(_ctrl.document),
      'contentDelta': jsonEncode(_ctrl.document.toDelta().toJson()),
      'images': _images,
      'attachments': _files.map((f) => f.toJson()).toList(),
      'priority': _priority,
      'requireAck': _requireAck,
      'ackDeadline': _requireAck ? _ackDeadline?.toUtc().toIso8601String() : null,
      'audience': _audience.toJson(),
      'poll': _pollOn
          ? {
              'question': _pollQ.text.trim(),
              'multiple': _pollMultiple,
              'options': [
                for (var i = 0; i < _pollOpts.length; i++)
                  if (_pollOpts[i].text.trim().isNotEmpty)
                    {'id': i < existingPollIds.length ? existingPollIds[i] : 'o${i + 1}', 'text': _pollOpts[i].text.trim()},
              ],
            }
          : null,
      'eventAt': _eventOn ? _eventAt?.toUtc().toIso8601String() : null,
      'eventLocation': _eventOn ? _location.text.trim() : null,
      'scheduledAt': _scheduledAt?.toUtc().toIso8601String(),
      'allowComments': _allowComments,
      'tags': _tags.text.trim(),
      'isPinned': _pinned,
      'publish': publish,
      'bumpVersion': _bumpVersion,
      'isAiGenerated': _aiGenerated,
    };
    setState(() => _saving = true);
    final r = await _api.saveCommPost(data, id: widget.post?.id);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['isSuccess'] == true) {
      final status = r['data'] is Map ? CommStatus.values[((r['data'] as Map)['status'] as num? ?? 0).toInt().clamp(0, 5)] : null;
      commToast(context, switch (status) {
        CommStatus.pendingApproval => 'Đã gửi, chờ quản lý duyệt',
        CommStatus.scheduled => 'Đã hẹn giờ đăng',
        CommStatus.draft => 'Đã lưu nháp',
        _ => 'Đã đăng bài',
      });
      Navigator.of(context).pop(true);
    } else {
      commToast(context, '${r['message'] ?? 'Không lưu được'}', error: true);
    }
  }

  // ─── Giao diện ───────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final publishLabel = _channel?.requireApproval == true && !widget.ctx.isManager
        ? 'Gửi duyệt'
        : (_scheduledAt != null ? 'Hẹn giờ đăng' : (_wasPublished ? 'Cập nhật' : 'Đăng bài'));
    // Quill cần bản dịch riêng — thiếu sẽ lỗi «màn xám» trên web.
    return Localizations.override(
      context: context,
      delegates: const [quill.FlutterQuillLocalizations.delegate],
      child: Scaffold(
        backgroundColor: SboxColors.page,
        appBar: AppBar(
          backgroundColor: SboxColors.surface,
          surfaceTintColor: Colors.transparent,
          title: Text(tr(_editing ? 'Sửa bài viết' : 'Tạo bài viết')),
          actions: [
            TextButton.icon(
              onPressed: () => setState(() => _preview = !_preview),
              icon: Icon(_preview ? Icons.edit_outlined : Icons.visibility_outlined),
              label: Text(tr(_preview ? 'Soạn tiếp' : 'Xem trước')),
            ),
            if (!wide)
              IconButton(
                tooltip: tr('Trợ lý AI'),
                icon: const Icon(Icons.auto_awesome, color: SboxColors.violet),
                onPressed: _openAiSheet,
              ),
            if (!_wasPublished)
              TextButton(onPressed: _saving ? null : () => _save(publish: false), child: Text(tr('Lưu nháp'))),
            Padding(
              padding: const EdgeInsets.only(right: 12, left: 4),
              child: SboxButton(
                label: publishLabel,
                icon: Icons.send_rounded,
                size: SboxButtonSize.sm,
                loading: _saving,
                onPressed: _saving ? null : () => _save(publish: true),
              ),
            ),
          ],
        ),
        body: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: _preview
                ? _previewView()
                : ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 16, 16, 48), children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 820),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          _channelPicker(),
                          const SizedBox(height: SboxSpace.md),
                          _editorCard(),
                          const SizedBox(height: SboxSpace.md),
                          _mediaSection(),
                          if (_pollOn) ...[const SizedBox(height: SboxSpace.md), _pollCard()],
                          if (_eventOn) ...[const SizedBox(height: SboxSpace.md), _eventCard()],
                          const SizedBox(height: SboxSpace.md),
                          _settingsCard(),
                        ]),
                      ),
                    ),
                  ]),
          ),
          if (wide && _showAi) ...[
            const VerticalDivider(width: 1, color: SboxColors.border),
            SizedBox(
              width: 380,
              child: CommAiPanel(
                channelKey: _channel?.key,
                currentText: () => _ctrl.document.toPlainText(),
                currentTitle: () => _title.text,
                onDraft: _applyDraft,
                onAttachments: _addAiAttachments,
                onClose: () => setState(() => _showAi = false),
              ),
            ),
          ],
        ]),
        floatingActionButton: wide && !_showAi
            ? FloatingActionButton.extended(
                backgroundColor: SboxColors.violet,
                foregroundColor: Colors.white,
                onPressed: () => setState(() => _showAi = true),
                icon: const Icon(Icons.auto_awesome),
                label: Text(tr('Trợ lý AI')),
              )
            : null,
      ),
    );
  }

  void _openAiSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.85,
        child: CommAiPanel(
          channelKey: _channel?.key,
          currentText: () => _ctrl.document.toPlainText(),
          currentTitle: () => _title.text,
          onDraft: (d, {bool append = false}) {
            _applyDraft(d, append: append);
            Navigator.pop(ctx);
          },
          onAttachments: _addAiAttachments,
          onClose: () => Navigator.pop(ctx),
        ),
      ),
    );
  }

  Widget _channelPicker() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        Text(tr('Đăng vào'), style: SboxType.smallStyle()),
        const SizedBox(width: 8),
        for (final c in _postable)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              avatar: Icon(c.iconData, size: 16, color: _channelId == c.id ? Colors.white : c.colorValue),
              label: Text(c.name),
              selected: _channelId == c.id,
              selectedColor: c.colorValue,
              labelStyle: TextStyle(color: _channelId == c.id ? Colors.white : SboxColors.text, fontWeight: FontWeight.w600),
              onSelected: (_) => setState(() => _channelId = c.id),
            ),
          ),
      ]),
    );
  }

  Widget _editorCard() {
    return Container(
      decoration: BoxDecoration(color: SboxColors.surface, borderRadius: SboxRadius.lgAll, border: Border.all(color: SboxColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: TextField(
            controller: _title,
            maxLines: null,
            style: SboxType.headlineStyle(),
            decoration: InputDecoration(
              hintText: tr('Tiêu đề bài viết'),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
            ),
          ),
        ),
        CommFormatToolbar(controller: _ctrl),
        const Divider(height: 1, color: SboxColors.divider),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 280),
          child: quill.QuillEditor(
            controller: _ctrl,
            focusNode: _focus,
            scrollController: ScrollController(),
            config: quill.QuillEditorConfig(
              placeholder: tr('Viết nội dung… hoặc bấm «Trợ lý AI» để AI viết từ yêu cầu hay từ tài liệu Word/PDF/Excel'),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              scrollable: false,
              expands: false,
              customStyles: quill.DefaultStyles(
                paragraph: quill.DefaultTextBlockStyle(
                  const TextStyle(fontSize: 16, height: 1.6, color: SboxColors.slate800),
                  const quill.HorizontalSpacing(0, 0),
                  const quill.VerticalSpacing(4, 4),
                  const quill.VerticalSpacing(0, 0),
                  null,
                ),
                h1: quill.DefaultTextBlockStyle(
                  const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.3, color: SboxColors.slate900),
                  const quill.HorizontalSpacing(0, 0),
                  const quill.VerticalSpacing(14, 6),
                  const quill.VerticalSpacing(0, 0),
                  null,
                ),
                h2: quill.DefaultTextBlockStyle(
                  const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, height: 1.35, color: SboxColors.slate900),
                  const quill.HorizontalSpacing(0, 0),
                  const quill.VerticalSpacing(12, 4),
                  const quill.VerticalSpacing(0, 0),
                  null,
                ),
                h3: quill.DefaultTextBlockStyle(
                  const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w700, height: 1.4, color: SboxColors.slate900),
                  const quill.HorizontalSpacing(0, 0),
                  const quill.VerticalSpacing(10, 4),
                  const quill.VerticalSpacing(0, 0),
                  null,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(children: [
            if (_aiGenerated) const SboxStatusChip(label: 'Có AI hỗ trợ', tone: SboxTone.violet, icon: Icons.auto_awesome),
            const Spacer(),
            Text('${_ctrl.document.toPlainText().trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length} từ',
                style: SboxType.captionStyle()),
          ]),
        ),
      ]),
    );
  }

  Widget _mediaSection() {
    Widget chip(IconData icon, String label, Color color, VoidCallback onTap, {bool active = false}) => Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 8),
          child: ActionChip(
            avatar: Icon(icon, size: 18, color: color),
            label: Text(tr(label)),
            backgroundColor: active ? color.withValues(alpha: 0.12) : SboxColors.surface,
            side: BorderSide(color: active ? color : SboxColors.border),
            onPressed: _uploading ? null : onTap,
          ),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(children: [
        chip(Icons.photo_library_outlined, 'Ảnh', SboxColors.success, () => _addFiles(images: true)),
        chip(Icons.attach_file_rounded, 'Word / PDF / Excel', SboxColors.brand600, () => _addFiles(images: false)),
        chip(Icons.poll_outlined, 'Bình chọn', SboxColors.warning, () => setState(() => _pollOn = !_pollOn), active: _pollOn),
        chip(Icons.event_outlined, 'Sự kiện', SboxColors.danger, () => setState(() {
              _eventOn = !_eventOn;
              _eventAt ??= DateTime.now().add(const Duration(days: 1));
            }), active: _eventOn),
        if (_uploading) const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
      ]),
      if (_images.isNotEmpty) ...[
        const SizedBox(height: 4),
        CommImageGrid(urls: _images, height: 200, onRemove: (i) => setState(() => _images.removeAt(i))),
      ],
      if (_files.isNotEmpty) ...[
        const SizedBox(height: 8),
        for (var i = 0; i < _files.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: CommFileTile(file: _files[i], dense: true, onRemove: () => setState(() => _files.removeAt(i))),
          ),
      ],
    ]);
  }

  Widget _pollCard() {
    return SboxCard(
      title: 'Bình chọn',
      trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _pollOn = false)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(controller: _pollQ, decoration: InputDecoration(labelText: tr('Câu hỏi'), hintText: tr('Chọn ngày tổ chức team building?'))),
        const SizedBox(height: 8),
        for (var i = 0; i < _pollOpts.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Icon(_pollMultiple ? Icons.check_box_outline_blank : Icons.radio_button_unchecked, size: 18, color: SboxColors.slate400),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _pollOpts[i], decoration: InputDecoration(isDense: true, hintText: tr('Lựa chọn ${i + 1}')))),
              if (_pollOpts.length > 2)
                IconButton(icon: const Icon(Icons.remove_circle_outline, size: 18), onPressed: () => setState(() => _pollOpts.removeAt(i).dispose())),
            ]),
          ),
        Row(children: [
          if (_pollOpts.length < 12)
            TextButton.icon(onPressed: () => setState(() => _pollOpts.add(TextEditingController())), icon: const Icon(Icons.add), label: Text(tr('Thêm lựa chọn'))),
          const Spacer(),
          Text(tr('Chọn nhiều'), style: SboxType.smallStyle()),
          Switch(value: _pollMultiple, onChanged: (v) => setState(() => _pollMultiple = v)),
        ]),
      ]),
    );
  }

  Widget _eventCard() {
    return SboxCard(
      title: 'Sự kiện',
      trailing: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _eventOn = false)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.schedule_outlined),
          title: Text(_eventAt == null ? tr('Chọn thời gian') : _fmt(_eventAt!)),
          onTap: () async {
            final d = await _pickDateTime(_eventAt);
            if (d != null) setState(() => _eventAt = d);
          },
        ),
        TextField(controller: _location, decoration: InputDecoration(labelText: tr('Địa điểm'), prefixIcon: const Icon(Icons.place_outlined))),
      ]),
    );
  }

  Widget _settingsCard() {
    final m = widget.ctx.isManager;
    return SboxCard(
      title: 'Thiết lập đăng',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (m)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.groups_outlined),
            title: Text(tr('Người nhận')),
            subtitle: Text(tr(_audienceLabel())),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _editAudience,
          ),
        if (m) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.verified_user_outlined),
            value: _requireAck,
            onChanged: (v) => setState(() => _requireAck = v),
            title: Text(tr('Bắt buộc đọc và xác nhận')),
            subtitle: Text(tr('Mọi người bấm «Tôi đã đọc và cam kết»; bạn xem được ai chưa đọc')),
          ),
          if (_requireAck)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 56),
              title: Text(_ackDeadline == null ? tr('Hạn xác nhận: không đặt') : tr('Hạn xác nhận: ${_fmt(_ackDeadline!)}')),
              trailing: _ackDeadline == null ? const Icon(Icons.event_outlined) : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _ackDeadline = null)),
              onTap: () async {
                final d = await _pickDateTime(_ackDeadline ?? DateTime.now().add(const Duration(days: 3)));
                if (d != null) setState(() => _ackDeadline = d);
              },
            ),
          if (_wasPublished && _requireAck)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.history_edu_outlined),
              value: _bumpVersion,
              onChanged: (v) => setState(() => _bumpVersion = v),
              title: Text(tr('Lưu thành phiên bản mới (bản ${widget.post!.version + 1})')),
              subtitle: Text(tr('Mọi người phải đọc và xác nhận lại')),
            ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.flag_outlined),
            title: Text(tr('Mức độ')),
            trailing: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: 1, label: Text(tr('Thường'))),
                ButtonSegment(value: 2, label: Text(tr('Quan trọng'))),
                ButtonSegment(value: 3, label: Text(tr('Khẩn'))),
              ],
              selected: {_priority.clamp(1, 3)},
              onSelectionChanged: (s) => setState(() => _priority = s.first),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.push_pin_outlined),
            value: _pinned,
            onChanged: (v) => setState(() => _pinned = v),
            title: Text(tr('Ghim lên đầu bảng tin')),
          ),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.chat_bubble_outline),
          value: _allowComments,
          onChanged: (v) => setState(() => _allowComments = v),
          title: Text(tr('Cho phép bình luận')),
        ),
        if (!_wasPublished)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule_send_outlined),
            title: Text(_scheduledAt == null ? tr('Đăng ngay') : tr('Hẹn đăng lúc ${_fmt(_scheduledAt!)}')),
            trailing: _scheduledAt == null
                ? TextButton(
                    onPressed: () async {
                      final d = await _pickDateTime(DateTime.now().add(const Duration(hours: 1)));
                      if (d != null) setState(() => _scheduledAt = d);
                    },
                    child: Text(tr('Hẹn giờ')),
                  )
                : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _scheduledAt = null)),
          ),
        TextField(
          controller: _tags,
          decoration: InputDecoration(labelText: tr('Thẻ'), hintText: tr('nội quy, chấm công, 2026'), prefixIcon: const Icon(Icons.sell_outlined)),
        ),
      ]),
    );
  }

  String _audienceLabel() {
    final a = _audience;
    if (a.isEveryone) return 'Toàn công ty';
    final parts = <String>[
      if (a.branchIds.isNotEmpty) '${a.branchIds.length} chi nhánh',
      if (a.departmentIds.isNotEmpty) '${a.departmentIds.length} phòng ban',
      if (a.positions.isNotEmpty) a.positions.join(', '),
      if (a.employeeIds.isNotEmpty) '${a.employeeIds.length} người',
    ];
    return parts.join(' · ');
  }

  Future<void> _editAudience() async {
    final r = await showDialog<CommAudience>(context: context, builder: (_) => CommAudienceDialog(ctx: widget.ctx, initial: _audience));
    if (r != null) setState(() => _audience = r);
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<DateTime?> _pickDateTime(DateTime? initial) async {
    final base = initial ?? DateTime.now();
    final d = await showDatePicker(context: context, initialDate: base, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d == null || !mounted) return null;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    return DateTime(d.year, d.month, d.day, t?.hour ?? 8, t?.minute ?? 0);
  }

  Widget _previewView() {
    final ch = _channel;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SboxCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CommAvatar(name: widget.ctx.myName, size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.ctx.myName, style: SboxType.bodyStrong()),
                    Text(tr('${ch?.name ?? ''} · Xem trước'), style: SboxType.captionStyle()),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              if (_title.text.trim().isNotEmpty) Text(_title.text.trim(), style: SboxType.titleStyle()),
              const SizedBox(height: 8),
              CommHtml(html: commDeltaToHtml(_ctrl.document)),
              if (_images.isNotEmpty) ...[const SizedBox(height: 8), CommImageGrid(urls: _images)],
              for (final f in _files) Padding(padding: const EdgeInsets.only(top: 6), child: CommFileTile(file: f, dense: true)),
            ]),
          ),
        ),
      ),
    ]);
  }
}

// ═════════════════ Thanh định dạng ═════════════════

class CommFormatToolbar extends StatelessWidget {
  const CommFormatToolbar({super.key, required this.controller});
  final quill.QuillController controller;

  static const _colors = <(String, Color)>[
    ('#0F172A', Color(0xFF0F172A)),
    ('#DC2626', Color(0xFFDC2626)),
    ('#EA580C', Color(0xFFEA580C)),
    ('#16A34A', Color(0xFF16A34A)),
    ('#158DC0', Color(0xFF158DC0)),
    ('#7C3AED', Color(0xFF7C3AED)),
  ];

  bool _has(quill.Attribute a) {
    final attrs = controller.getSelectionStyle().attributes;
    final cur = attrs[a.key];
    return cur != null && (a.value == null || cur.value == a.value);
  }

  void _toggle(quill.Attribute a) {
    controller.formatSelection(_has(a) ? quill.Attribute.clone(a, null) : a);
  }

  Future<void> _link(BuildContext context) async {
    final ctrl = TextEditingController(text: controller.getSelectionStyle().attributes[quill.Attribute.link.key]?.value?.toString() ?? '');
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Chèn liên kết')),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'https://')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: Text(tr('Bỏ liên kết'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(tr('Chèn'))),
        ],
      ),
    );
    if (url == null) return;
    if (url.isEmpty) {
      controller.formatSelection(quill.Attribute.clone(quill.Attribute.link, null));
    } else {
      final safe = url.startsWith('http') || url.startsWith('mailto:') || url.startsWith('tel:') ? url : 'https://$url';
      controller.formatSelection(quill.LinkAttribute(safe));
    }
  }

  @override
  Widget build(BuildContext context) {
    final header = controller.getSelectionStyle().attributes[quill.Attribute.header.key]?.value;
    Widget btn(IconData icon, String tip, VoidCallback? onTap, {bool active = false}) => Tooltip(
          message: tr(tip),
          child: InkWell(
            borderRadius: SboxRadius.smAll,
            onTap: onTap,
            child: Container(
              width: 34,
              height: 34,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(color: active ? SboxColors.brand50 : null, borderRadius: SboxRadius.smAll),
              child: Icon(icon, size: 19, color: onTap == null ? SboxColors.slate300 : (active ? SboxColors.brand700 : SboxColors.slate600)),
            ),
          ),
        );
    Widget sep() => Container(width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 4), color: SboxColors.border);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        btn(Icons.undo_rounded, 'Hoàn tác', controller.hasUndo ? controller.undo : null),
        btn(Icons.redo_rounded, 'Làm lại', controller.hasRedo ? controller.redo : null),
        sep(),
        PopupMenuButton<int>(
          tooltip: tr('Kiểu chữ'),
          onSelected: (v) => controller.formatSelection(switch (v) {
            1 => quill.Attribute.h1,
            2 => quill.Attribute.h2,
            3 => quill.Attribute.h3,
            _ => quill.Attribute.clone(quill.Attribute.header, null),
          }),
          itemBuilder: (_) => [
            PopupMenuItem(value: 0, child: Text(tr('Đoạn văn'))),
            PopupMenuItem(value: 1, child: Text(tr('Tiêu đề lớn'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
            PopupMenuItem(value: 2, child: Text(tr('Tiêu đề vừa'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
            PopupMenuItem(value: 3, child: Text(tr('Tiêu đề nhỏ'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          ],
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(border: Border.all(color: SboxColors.border), borderRadius: SboxRadius.smAll),
            child: Row(children: [
              Text(tr(switch (header) { 1 => 'Tiêu đề lớn', 2 => 'Tiêu đề vừa', 3 => 'Tiêu đề nhỏ', _ => 'Đoạn văn' }), style: SboxType.smallStyle(SboxColors.text)),
              const Icon(Icons.arrow_drop_down_rounded),
            ]),
          ),
        ),
        sep(),
        btn(Icons.format_bold_rounded, 'Đậm', () => _toggle(quill.Attribute.bold), active: _has(quill.Attribute.bold)),
        btn(Icons.format_italic_rounded, 'Nghiêng', () => _toggle(quill.Attribute.italic), active: _has(quill.Attribute.italic)),
        btn(Icons.format_underline_rounded, 'Gạch chân', () => _toggle(quill.Attribute.underline), active: _has(quill.Attribute.underline)),
        btn(Icons.format_strikethrough_rounded, 'Gạch ngang', () => _toggle(quill.Attribute.strikeThrough), active: _has(quill.Attribute.strikeThrough)),
        PopupMenuButton<(String, bool)>(
          tooltip: tr('Màu chữ / tô nền'),
          onSelected: (v) => controller.formatSelection(v.$2 ? quill.BackgroundAttribute(v.$1) as quill.Attribute : quill.ColorAttribute(v.$1)),
          itemBuilder: (_) => [
            PopupMenuItem(enabled: false, child: Text(tr('Màu chữ'), style: SboxType.captionStyle())),
            for (final c in _colors) PopupMenuItem(value: (c.$1, false), child: Row(children: [Icon(Icons.format_color_text, color: c.$2), const SizedBox(width: 8), Text(c.$1)])),
            PopupMenuItem(enabled: false, child: Text(tr('Tô nền'), style: SboxType.captionStyle())),
            for (final c in const [('#FEF3C7', Color(0xFFFEF3C7)), ('#DCFCE7', Color(0xFFDCFCE7)), ('#DBEAFE', Color(0xFFDBEAFE)), ('#FEE2E2', Color(0xFFFEE2E2))])
              PopupMenuItem(value: (c.$1, true), child: Row(children: [Container(width: 22, height: 16, color: c.$2), const SizedBox(width: 8), Text(c.$1)])),
          ],
          child: const Padding(padding: EdgeInsets.all(7), child: Icon(Icons.format_color_text_rounded, size: 19, color: SboxColors.slate600)),
        ),
        sep(),
        btn(Icons.format_list_bulleted_rounded, 'Danh sách chấm', () => _toggle(quill.Attribute.ul), active: _has(quill.Attribute.ul)),
        btn(Icons.format_list_numbered_rounded, 'Danh sách số', () => _toggle(quill.Attribute.ol), active: _has(quill.Attribute.ol)),
        btn(Icons.checklist_rounded, 'Danh sách việc', () => _toggle(quill.Attribute.unchecked), active: _has(quill.Attribute.unchecked)),
        btn(Icons.format_quote_rounded, 'Trích dẫn', () => _toggle(quill.Attribute.blockQuote), active: _has(quill.Attribute.blockQuote)),
        sep(),
        btn(Icons.format_align_left_rounded, 'Căn trái', () => controller.formatSelection(quill.Attribute.clone(quill.Attribute.align, null))),
        btn(Icons.format_align_center_rounded, 'Căn giữa', () => _toggle(quill.Attribute.centerAlignment), active: _has(quill.Attribute.centerAlignment)),
        btn(Icons.format_align_right_rounded, 'Căn phải', () => _toggle(quill.Attribute.rightAlignment), active: _has(quill.Attribute.rightAlignment)),
        sep(),
        btn(Icons.link_rounded, 'Liên kết', () => _link(context), active: _has(quill.Attribute.link)),
        btn(Icons.format_clear_rounded, 'Xóa định dạng', () {
          for (final a in <quill.Attribute>[quill.Attribute.bold, quill.Attribute.italic, quill.Attribute.underline, quill.Attribute.strikeThrough,
            quill.Attribute.color, quill.Attribute.background, quill.Attribute.link]) {
            controller.formatSelection(quill.Attribute.clone(a, null));
          }
        }),
      ]),
    );
  }
}

// ═════════════════ Chọn người nhận ═════════════════

class CommAudienceDialog extends StatefulWidget {
  const CommAudienceDialog({super.key, required this.ctx, required this.initial});
  final CommContext ctx;
  final CommAudience initial;

  @override
  State<CommAudienceDialog> createState() => _CommAudienceDialogState();
}

class _CommAudienceDialogState extends State<CommAudienceDialog> {
  late bool _all = widget.initial.isEveryone;
  late final Set<String> _branches = {...widget.initial.branchIds};
  late final Set<String> _depts = {...widget.initial.departmentIds};
  late final Set<String> _positions = {...widget.initial.positions};
  late final Set<String> _people = {...widget.initial.employeeIds};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final c = widget.ctx;
    Widget group(String title, Iterable<({String id, String label})> items, Set<String> sel) {
      final list = items.toList();
      if (list.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(title), style: SboxType.captionStyle()),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final it in list)
              FilterChip(label: Text(it.label), selected: sel.contains(it.id), onSelected: (v) => setState(() => v ? sel.add(it.id) : sel.remove(it.id))),
          ]),
        ]),
      );
    }

    final people = c.people.where((p) => _q.isEmpty || p.name.toLowerCase().contains(_q)).take(60).toList();
    return AlertDialog(
      title: Text(tr('Người nhận bài')),
      content: SizedBox(
        width: 520,
        height: 520,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<bool>(
            segments: [ButtonSegment(value: true, label: Text(tr('Toàn công ty'))), ButtonSegment(value: false, label: Text(tr('Chọn nhóm / người')))],
            selected: {_all},
            onSelectionChanged: (s) => setState(() => _all = s.first),
          ),
          const SizedBox(height: 12),
          if (!_all)
            Expanded(
              child: ListView(children: [
                group('Chi nhánh', c.branches.map((b) => (id: b.id, label: b.name)), _branches),
                group('Phòng ban', c.departments.map((d) => (id: d.id, label: d.name)), _depts),
                group('Chức danh', c.positions.map((p) => (id: p, label: p)), _positions),
                Text(tr('Từng người (${_people.length})'), style: SboxType.captionStyle()),
                TextField(
                  decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search), hintText: tr('Tìm nhân viên')),
                  onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                ),
                for (final p in people)
                  CheckboxListTile(
                    dense: true,
                    value: _people.contains(p.employeeId),
                    onChanged: (v) => setState(() => v == true ? _people.add(p.employeeId) : _people.remove(p.employeeId)),
                    title: Text(p.name),
                    subtitle: p.position == null ? null : Text(p.position!),
                  ),
              ]),
            )
          else
            Expanded(child: Center(child: Text(tr('Mọi nhân viên đang làm việc đều nhận được bài'), style: SboxType.smallStyle()))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy'))),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            CommAudience(
              all: _all,
              branchIds: _branches.toList(),
              departmentIds: _depts.toList(),
              positions: _positions.toList(),
              employeeIds: _people.toList(),
            ),
          ),
          child: Text(tr('Xong')),
        ),
      ],
    );
  }
}

// ═════════════════ Trợ lý AI ═════════════════

typedef CommDraftCallback = void Function(CommAiDraft draft, {bool append});

class CommAiPanel extends StatefulWidget {
  const CommAiPanel({
    super.key,
    required this.currentText,
    required this.currentTitle,
    required this.onDraft,
    required this.onAttachments,
    this.onClose,
    this.channelKey,
  });

  final String Function() currentText;
  final String Function() currentTitle;
  final CommDraftCallback onDraft;
  final ValueChanged<List<CommAttachment>> onAttachments;
  final VoidCallback? onClose;
  final String? channelKey;

  @override
  State<CommAiPanel> createState() => _CommAiPanelState();
}

class _CommAiPanelState extends State<CommAiPanel> with SingleTickerProviderStateMixin {
  final _api = ApiService();
  late final _tabs = TabController(length: 3, vsync: this);
  final _prompt = TextEditingController();
  final _instruction = TextEditingController();
  String _tone = 'professional';
  bool _busy = false;
  String? _status;
  CommAiDraft? _draft;
  List<String> _warnings = [];

  static const _tones = <(String, String)>[
    ('professional', 'Chuyên nghiệp'),
    ('friendly', 'Thân thiện'),
    ('formal', 'Trang trọng'),
    ('inspirational', 'Truyền cảm hứng'),
    ('short', 'Ngắn gọn'),
  ];

  @override
  void dispose() {
    _tabs.dispose();
    _prompt.dispose();
    _instruction.dispose();
    super.dispose();
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() call, String status) async {
    setState(() {
      _busy = true;
      _status = status;
      _draft = null;
      _warnings = [];
    });
    final r = await call();
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['isSuccess'] != true) {
      setState(() => _warnings = ['${r['message'] ?? 'AI chưa trả lời được — thử lại'}']);
      return;
    }
    final d = r['data'];
    if (d is Map && d.containsKey('draft')) {
      final atts = (d['attachments'] as List? ?? []).whereType<Map>().map((e) => CommAttachment.fromJson(Map<String, dynamic>.from(e))).toList();
      if (atts.isNotEmpty) widget.onAttachments(atts);
      setState(() {
        _warnings = (d['warnings'] as List? ?? []).map((e) => '$e').toList();
        _draft = d['draft'] is Map ? CommAiDraft.fromJson(Map<String, dynamic>.from(d['draft'] as Map)) : null;
      });
    } else if (d is Map) {
      setState(() => _draft = CommAiDraft.fromJson(Map<String, dynamic>.from(d)));
    }
  }

  Future<void> _fromDocs() async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true, withData: true, type: FileType.custom, allowedExtensions: _kDocExts);
    if (r == null || r.files.isEmpty) return;
    final files = [
      for (final f in r.files)
        if (f.bytes != null && f.size <= 20 * 1024 * 1024) (bytes: f.bytes!.toList(), name: f.name),
    ];
    if (files.isEmpty) return;
    await _run(
      () => _api.commUpload(files, aiDraft: true, instruction: _instruction.text.trim(), tone: _tone, channelKey: widget.channelKey),
      'AI đang đọc ${files.length} tài liệu và viết bài…',
    );
  }

  Future<void> _write(String action, [String? label]) async {
    final text = widget.currentText().trim();
    if (action != 'write' && text.isEmpty) {
      setState(() => _warnings = ['Bài đang trống — hãy viết vài dòng hoặc dùng tab «Viết mới»']);
      return;
    }
    if (action == 'write' && _prompt.text.trim().isEmpty) {
      setState(() => _warnings = ['Nhập yêu cầu cho AI']);
      return;
    }
    await _run(
      () => _api.commAiWrite({
        'action': action,
        'prompt': action == 'write' ? _prompt.text.trim() : null,
        'tone': _tone,
        'channelKey': widget.channelKey,
        'title': widget.currentTitle(),
        'currentText': action == 'write' ? null : text,
      }),
      label ?? 'AI đang viết…',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: SboxColors.surface,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(children: [
            const Icon(Icons.auto_awesome, color: SboxColors.violet),
            const SizedBox(width: 8),
            Expanded(child: Text(tr('Trợ lý viết bài AI'), style: SboxType.titleSmStyle())),
            if (widget.onClose != null) IconButton(icon: const Icon(Icons.close_rounded), onPressed: widget.onClose),
          ]),
        ),
        TabBar(controller: _tabs, labelColor: SboxColors.violet, indicatorColor: SboxColors.violet, tabs: [
          Tab(text: tr('Viết mới')),
          Tab(text: tr('Từ tài liệu')),
          Tab(text: tr('Chỉnh bài')),
        ]),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Text(tr('Giọng văn'), style: SboxType.captionStyle()),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final t in _tones) ChoiceChip(label: Text(tr(t.$2)), selected: _tone == t.$1, onSelected: (_) => setState(() => _tone = t.$1)),
            ]),
            const SizedBox(height: 14),
            AnimatedBuilder(
              animation: _tabs,
              builder: (ctx, _) => switch (_tabs.index) {
                0 => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    TextField(
                      controller: _prompt,
                      minLines: 4,
                      maxLines: 8,
                      decoration: InputDecoration(
                        hintText: tr('Ví dụ: Thông báo lịch nghỉ lễ 2/9: nghỉ từ 31/8 đến hết 2/9, ca trực luân phiên, thưởng lễ 300.000đ'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SboxButton(label: 'Viết bài', icon: Icons.auto_awesome, expand: true, loading: _busy, onPressed: _busy ? null : () => _write('write')),
                  ]),
                1 => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: SboxColors.violetSoft.withValues(alpha: 0.5),
                        borderRadius: SboxRadius.lgAll,
                        border: Border.all(color: SboxColors.violet.withValues(alpha: 0.4)),
                      ),
                      child: Column(children: [
                        const Icon(Icons.upload_file_rounded, size: 36, color: SboxColors.violet),
                        const SizedBox(height: 6),
                        Text(tr('Word, PDF, Excel, PowerPoint, ảnh chụp văn bản'), textAlign: TextAlign.center, style: SboxType.smallStyle(SboxColors.text)),
                        Text(tr('AI đọc tài liệu và dựng lại thành bài; tệp gốc được đính kèm vào bài'), textAlign: TextAlign.center, style: SboxType.captionStyle()),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _instruction,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(hintText: tr('Yêu cầu thêm (không bắt buộc): tóm tắt cho nhân viên bán hàng, nhấn mạnh mức phạt…')),
                    ),
                    const SizedBox(height: 10),
                    SboxButton(label: 'Chọn tài liệu cho AI đọc', icon: Icons.description_outlined, expand: true, loading: _busy, onPressed: _busy ? null : _fromDocs),
                  ]),
                _ => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (final a in const [
                      ('improve', Icons.auto_fix_high, 'Viết lại hay hơn'),
                      ('fix', Icons.spellcheck, 'Sửa chính tả, ngữ pháp'),
                      ('shorten', Icons.compress, 'Rút gọn'),
                      ('expand', Icons.expand, 'Viết chi tiết hơn'),
                      ('announce', Icons.campaign_outlined, 'Chuyển thành thông báo chính thức'),
                      ('summarize', Icons.summarize_outlined, 'Tóm tắt thành ý chính'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.all(12)),
                          onPressed: _busy ? null : () => _write(a.$1, 'AI đang ${a.$3.toLowerCase()}…'),
                          icon: Icon(a.$2, size: 18),
                          label: Text(tr(a.$3)),
                        ),
                      ),
                  ]),
              },
            ),
            if (_busy) ...[
              const SizedBox(height: 16),
              Row(children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: SboxColors.violet)),
                const SizedBox(width: 10),
                Expanded(child: Text(tr(_status ?? ''), style: SboxType.smallStyle())),
              ]),
            ],
            for (final w in _warnings)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: SboxColors.warningSoft, borderRadius: SboxRadius.mdAll),
                child: Text(tr(w), style: SboxType.smallStyle(SboxColors.warningText)),
              ),
            if (_draft != null) ...[const SizedBox(height: 16), _draftCard(_draft!)],
          ]),
        ),
      ]),
    );
  }

  Widget _draftCard(CommAiDraft d) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(border: Border.all(color: SboxColors.violet.withValues(alpha: 0.5)), borderRadius: SboxRadius.lgAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.auto_awesome, size: 16, color: SboxColors.violet),
          const SizedBox(width: 6),
          Text(tr('Bản nháp của AI'), style: SboxType.captionStyle(SboxColors.violetText)),
        ]),
        const SizedBox(height: 6),
        Text(d.title, style: SboxType.bodyStrong()),
        if (d.summary.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(d.summary, style: SboxType.smallStyle())),
        if (d.keyPoints.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final k in d.keyPoints.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('•  '),
                Expanded(child: Text(k, style: SboxType.smallStyle(SboxColors.text))),
              ]),
            ),
        ],
        const SizedBox(height: 6),
        Text(tr('${d.blocks.length} đoạn${d.faq.isEmpty ? '' : ' · ${d.faq.length} câu hỏi thường gặp'}${d.suggestRequireAck ? ' · gợi ý bắt buộc đọc' : ''}'),
            style: SboxType.captionStyle()),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: SboxButton(label: 'Dùng bài này', icon: Icons.check_rounded, size: SboxButtonSize.sm, onPressed: () => widget.onDraft(d))),
          const SizedBox(width: 8),
          SboxButton.secondary(label: 'Chèn cuối', size: SboxButtonSize.sm, onPressed: () => widget.onDraft(d, append: true)),
        ]),
      ]),
    );
  }
}
