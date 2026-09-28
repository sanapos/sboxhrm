import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/image_source_picker.dart';
import '../../widgets/ai_assist_sheet.dart';
import '../../widgets/notification_overlay.dart';
import 'feedback_ui.dart';

/// Mở biểu mẫu gửi kiến nghị / khiếu nại. Trả về true khi đã gửi.
Future<bool> showFeedbackCompose(BuildContext context, {required List<Map<String, dynamic>> managers}) async {
  final wide = MediaQuery.of(context).size.width >= 720;
  final page = _FeedbackCompose(managers: managers);
  final ok = wide
      ? await showDialog<bool>(
          context: context,
          builder: (_) => Dialog(
            insetPadding: const EdgeInsets.all(24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 680, maxHeight: 820), child: page),
          ),
        )
      : await Navigator.of(context).push<bool>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => page));
  return ok == true;
}

class _FeedbackCompose extends StatefulWidget {
  const _FeedbackCompose({required this.managers});
  final List<Map<String, dynamic>> managers;

  @override
  State<_FeedbackCompose> createState() => _FeedbackComposeState();
}

class _PendingImage {
  _PendingImage(this.bytes, this.name);
  final Uint8List bytes;
  final String name;
}

class _FeedbackComposeState extends State<_FeedbackCompose> {
  final _api = ApiService();
  final _titleCtl = TextEditingController();
  final _contentCtl = TextEditingController();

  String _category = 'Complaint';
  String? _topic;
  int? _priority; // null = theo mặc định của loại phiếu
  String? _recipientId;
  bool _anonymous = false;
  bool _sending = false;
  final List<_PendingImage> _images = [];

  @override
  void dispose() {
    _titleCtl.dispose();
    _contentCtl.dispose();
    super.dispose();
  }

  int get _effectivePriority => _priority ?? (_category == 'Complaint' ? 2 : 1);

  Future<void> _addImages() async {
    final picked = await pickImagesWithCamera(context, allowMultiple: true);
    if (picked == null || !mounted) return;
    setState(() {
      for (final p in picked) {
        if (_images.length >= 6) break;
        _images.add(_PendingImage(p.bytes, p.name.isEmpty ? 'anh.jpg' : p.name));
      }
    });
  }

  Future<void> _submit() async {
    final title = _titleCtl.text.trim();
    final content = _contentCtl.text.trim();
    if (title.isEmpty || content.isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Thiếu thông tin', message: 'Vui lòng nhập tiêu đề và nội dung');
      return;
    }
    setState(() => _sending = true);
    final urls = <String>[];
    for (final img in _images) {
      final name = img.name.contains('.') ? img.name : '${img.name}.jpg';
      final res = await _api.uploadFeedbackImageBytes(img.bytes, name);
      final url = (res['data'] as Map?)?['fileUrl']?.toString();
      if (res['isSuccess'] == true && url != null) urls.add(url);
    }
    final res = await _api.createFeedback({
      'title': title,
      'content': content,
      'category': _category,
      'topic': _topic,
      'priority': _effectivePriority,
      'isAnonymous': _anonymous,
      if (_recipientId != null) 'recipientEmployeeId': _recipientId,
      'imageUrls': urls,
    });
    if (!mounted) return;
    setState(() => _sending = false);
    if (res['isSuccess'] == true) {
      final code = (res['data'] as Map?)?['code']?.toString();
      NotificationOverlayManager().showSuccess(
        title: 'Đã gửi',
        message: '${code != null ? 'Mã phiếu $code. ' : ''}'
            '${_anonymous ? 'Danh tính của bạn được giữ kín.' : 'Bạn sẽ nhận thông báo khi có phản hồi.'}',
      );
      Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(title: 'Không gửi được', message: res['message']?.toString() ?? '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: SboxColors.slate900,
        elevation: 0,
        title: Text(tr('Gửi kiến nghị / khiếu nại'), style: const TextStyle(fontWeight: FontWeight.w700)),
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          _label('Bạn muốn gửi'),
          Row(children: [
            for (final c in const ['Complaint', 'Suggestion', 'General'])
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: c == 'General' ? 0 : 8),
                  child: _typeCard(c),
                ),
              ),
          ]),
          const SizedBox(height: 18),
          _label('Chủ đề'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in FeedbackUi.topics)
              ChoiceChip(
                label: Text(tr(t)),
                selected: _topic == t,
                onSelected: (s) => setState(() => _topic = s ? t : null),
              ),
          ]),
          const SizedBox(height: 18),
          TextField(
            controller: _titleCtl,
            maxLength: 300,
            decoration: InputDecoration(
              labelText: tr('Tiêu đề *'),
              hintText: tr('Tóm tắt ngắn gọn vấn đề'),
              border: const OutlineInputBorder(),
              suffixIcon: AiAssistIconButton(
                kind: 'feedback',
                title: 'AI gợi ý tiêu đề',
                targetController: _titleCtl,
                tooltip: tr('AI gợi ý tiêu đề'),
                contextBuilder: () => 'Loại: ${FeedbackUi.categories[_category]}. '
                    '${_topic != null ? 'Chủ đề: $_topic. ' : ''}'
                    '${_contentCtl.text.trim().isNotEmpty ? 'Nội dung: ${_contentCtl.text.trim()}. ' : ''}'
                    'Gợi ý 1 tiêu đề ngắn gọn (tối đa 100 ký tự). Chỉ trả về tiêu đề.',
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _contentCtl,
            minLines: 5,
            maxLines: 10,
            maxLength: 5000,
            decoration: InputDecoration(
              labelText: tr('Nội dung *'),
              hintText: tr('Sự việc thế nào, xảy ra khi nào, ảnh hưởng ra sao, bạn đề xuất cách giải quyết gì?'),
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
              suffixIcon: AiAssistIconButton(
                kind: 'feedback',
                title: 'AI soạn nội dung',
                targetController: _contentCtl,
                tooltip: tr('AI soạn nội dung'),
                contextBuilder: () => 'Loại: ${FeedbackUi.categories[_category]}. '
                    '${_topic != null ? 'Chủ đề: $_topic. ' : ''}'
                    '${_titleCtl.text.trim().isNotEmpty ? 'Tiêu đề: ${_titleCtl.text.trim()}. ' : ''}'
                    'Viết nội dung lịch sự, rõ sự việc, thời gian, ảnh hưởng và đề xuất giải pháp.',
              ),
            ),
          ),
          const SizedBox(height: 6),
          _label('Ảnh đính kèm (tối đa 6)'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < _images.length; i++)
              Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(_images[i].bytes, width: 76, height: 76, fit: BoxFit.cover),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: InkWell(
                    onTap: () => setState(() => _images.removeAt(i)),
                    child: const CircleAvatar(
                      radius: 11,
                      backgroundColor: Colors.black54,
                      child: Icon(Icons.close_rounded, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ]),
            if (_images.length < 6)
              InkWell(
                onTap: _addImages,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: SboxColors.slate300),
                    color: SboxColors.slate50,
                  ),
                  child: const Icon(Icons.add_a_photo_outlined, color: SboxColors.slate500),
                ),
              ),
          ]),
          const SizedBox(height: 18),
          _label('Mức độ'),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              for (final p in const [1, 2, 3])
                ButtonSegment(value: p, label: Text(tr(FeedbackUi.priorities[p]!))),
            ],
            selected: {_effectivePriority.clamp(1, 3)},
            onSelectionChanged: (v) => setState(() => _priority = v.first),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              tr('Hạn phản hồi: ${switch (_effectivePriority) { 3 => '1 ngày', 2 => '2 ngày', _ => '3 ngày' }} kể từ khi gửi'),
              style: const TextStyle(fontSize: 12, color: SboxColors.slate500),
            ),
          ),
          const SizedBox(height: 18),
          _label('Gửi tới'),
          DropdownButtonFormField<String?>(
            initialValue: _recipientId,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            items: [
              DropdownMenuItem(
                value: null,
                child: Text(tr('Hòm thư chung — ban quản lý tiếp nhận')),
              ),
              for (final m in widget.managers)
                DropdownMenuItem(
                  value: m['id']?.toString(),
                  child: Text(
                    [
                      m['name'],
                      if ((m['position']?.toString() ?? '').isNotEmpty) m['position'],
                      if ((m['department']?.toString() ?? '').isNotEmpty) m['department'],
                    ].join(' · '),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _recipientId = v),
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(
              color: _anonymous ? SboxColors.violet.withValues(alpha: 0.08) : SboxColors.slate50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _anonymous ? SboxColors.violet.withValues(alpha: 0.4) : SboxColors.slate200),
            ),
            child: SwitchListTile(
              value: _anonymous,
              onChanged: (v) => setState(() => _anonymous = v),
              secondary: Icon(_anonymous ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  color: _anonymous ? SboxColors.violet : SboxColors.slate500),
              title: Text(tr('Gửi ẩn danh'), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(tr(_anonymous
                  ? 'Không ai (kể cả quản trị) thấy tên, mã, bộ phận của bạn. Bạn vẫn theo dõi và trao đổi được trong «Của tôi».'
                  : 'Người xử lý thấy tên và bộ phận của bạn để liên hệ khi cần.')),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton.icon(
            onPressed: _sending ? null : _submit,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            icon: _sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.send_rounded),
            label: Text(tr(_sending ? 'Đang gửi…' : 'Gửi ${FeedbackUi.categories[_category]!.toLowerCase()}')),
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(tr(t), style: const TextStyle(fontWeight: FontWeight.w700, color: SboxColors.slate700)),
      );

  Widget _typeCard(String c) {
    final sel = _category == c;
    final color = FeedbackUi.categoryColor(c);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() {
        _category = c;
        _priority = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: sel ? color.withValues(alpha: 0.1) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: sel ? color : SboxColors.slate200, width: sel ? 1.6 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(FeedbackUi.categoryIcon(c), color: color),
          const SizedBox(height: 6),
          Text(tr(FeedbackUi.categories[c]!),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w700, color: sel ? color : SboxColors.slate800)),
          Text(tr(FeedbackUi.categoryHints[c]!),
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: SboxColors.slate500)),
        ]),
      ),
    );
  }
}
