import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../services/api_service.dart';
import '../theme/sbox_tokens.dart';
import '../utils/image_source_picker.dart';
import '../widgets/auth_cached_image.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/notification_overlay.dart';
import 'feedback/feedback_ui.dart';

/// Chi tiết kiến nghị / khiếu nại: nội dung gốc, dòng thời gian trao đổi (tin nhắn, ghi chú nội bộ, sự kiện),
/// bảng xử lý (trạng thái, mức độ, người xử lý, hạn) cho người xử lý; đánh giá / mở lại / thu hồi cho người gửi.
class FeedbackDetailScreen extends StatefulWidget {
  const FeedbackDetailScreen({super.key, required this.feedbackId, required this.isMine});
  final String feedbackId;
  final bool isMine;

  @override
  State<FeedbackDetailScreen> createState() => _FeedbackDetailScreenState();
}

class _FeedbackDetailScreenState extends State<FeedbackDetailScreen> {
  final _api = ApiService();
  final _replyCtl = TextEditingController();
  final _scrollCtl = ScrollController();

  Map<String, dynamic>? _f;
  List<Map<String, dynamic>> _replies = [];
  List<Map<String, dynamic>> _handlers = [];
  Map<String, dynamic> _ctx = {};
  bool _loading = true;
  bool _sending = false;
  bool _internal = false;
  String? _error;

  bool get _canManage => _ctx['canManage'] == true;
  bool get _isSender => _ctx['isOriginalSender'] == true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _replyCtl.dispose();
    _scrollCtl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _rows(dynamic v) => [
        for (final x in (v as List? ?? const []))
          if (x is Map) Map<String, dynamic>.from(x),
      ];

  Future<void> _load({bool scroll = false}) async {
    final res = await _api.getFeedbackReplies(widget.feedbackId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true) {
        final d = res['data'] as Map<String, dynamic>;
        _f = Map<String, dynamic>.from(d['feedback'] as Map);
        _replies = _rows(d['replies']);
        _handlers = _rows(d['handlers']);
        _ctx = Map<String, dynamic>.from(d['viewerContext'] as Map? ?? const {});
        _error = null;
      } else {
        _error = res['message']?.toString() ?? 'Không tải được phiếu';
      }
    });
    if (scroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtl.hasClients) {
          _scrollCtl.animateTo(_scrollCtl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });
    }
  }

  Future<void> _run(Future<Map<String, dynamic>> call, String ok) async {
    final res = await call;
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Kiến nghị', message: ok);
      _load(scroll: true);
    } else {
      NotificationOverlayManager().showError(title: 'Kiến nghị', message: res['message']?.toString() ?? 'Thao tác thất bại');
    }
  }

  // ═════════════ HÀNH ĐỘNG ═════════════

  Future<void> _send() async {
    final text = _replyCtl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    final res = await _api.createFeedbackReply(widget.feedbackId, {'content': text, 'internal': _internal});
    if (!mounted) return;
    setState(() => _sending = false);
    if (res['isSuccess'] == true) {
      _replyCtl.clear();
      _load(scroll: true);
    } else {
      NotificationOverlayManager().showError(title: 'Gửi phản hồi', message: res['message']?.toString() ?? '');
    }
  }

  Future<void> _sendImage() async {
    final picked = await pickSingleImageWithCamera(context);
    if (picked == null || !mounted) return;
    setState(() => _sending = true);
    final r = await _api.createFeedbackReply(widget.feedbackId, {'content': '📷 Hình ảnh', 'internal': _internal});
    final id = (r['data'] as Map?)?['id']?.toString();
    if (r['isSuccess'] == true && id != null) {
      final name = picked.name.contains('.') ? picked.name : 'anh.jpg';
      await _api.uploadFeedbackReplyImageBytes(widget.feedbackId, id, picked.bytes, name);
    }
    if (!mounted) return;
    setState(() => _sending = false);
    _load(scroll: true);
  }

  Future<void> _changeStatus(String status, String title, {bool askNote = false}) async {
    String? note;
    if (askNote) {
      note = await _askText(title,
          hint: status == 'Resolved' ? 'Kết quả giải quyết gửi tới người gửi (khuyến khích ghi rõ)' : 'Ghi chú cho người gửi (không bắt buộc)');
      if (note == null) return;
    }
    await _run(_api.updateFeedbackStatus(widget.feedbackId, status, note: note?.isEmpty == true ? null : note),
        'Đã chuyển sang «${FeedbackUi.statuses[status]}»');
  }

  Future<void> _rate() async {
    var stars = 5;
    final comment = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(tr('Bạn hài lòng với kết quả?')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            FeedbackUi.stars(stars, size: 36, onTap: (v) => setS(() => stars = v)),
            const SizedBox(height: 6),
            Text(tr(const ['', 'Rất không hài lòng', 'Không hài lòng', 'Bình thường', 'Hài lòng', 'Rất hài lòng'][stars]),
                style: const TextStyle(color: SboxColors.slate500)),
            const SizedBox(height: 12),
            TextField(
              controller: comment,
              maxLines: 3,
              decoration: InputDecoration(labelText: tr('Nhận xét (không bắt buộc)'), border: const OutlineInputBorder()),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Để sau'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Gửi đánh giá'))),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _run(_api.rateFeedback(widget.feedbackId, stars, comment: comment.text.trim()), 'Cảm ơn bạn đã đánh giá');
    }
    comment.dispose();
  }

  Future<void> _reopen() async {
    final reason = await _askText('Mở lại phiếu', hint: 'Vì sao kết quả chưa thoả đáng?', required: true);
    if (reason == null) return;
    await _run(_api.reopenFeedback(widget.feedbackId, reason: reason), 'Đã mở lại phiếu');
  }

  Future<void> _withdraw() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Thu hồi phiếu?')),
        content: Text(tr('Phiếu chưa được tiếp nhận sẽ bị xoá và không thể khôi phục.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Không'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SboxColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Thu hồi')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _api.deleteFeedback(widget.feedbackId);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Kiến nghị', message: 'Đã thu hồi phiếu');
      Navigator.pop(context);
    } else {
      NotificationOverlayManager().showError(title: 'Kiến nghị', message: res['message']?.toString() ?? '');
    }
  }

  Future<String?> _askText(String title, {String? hint, bool required = false}) async {
    final ctl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(title)),
        content: SizedBox(
          width: 460,
          child: TextField(
            controller: ctl,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(hintText: hint == null ? null : tr(hint), border: const OutlineInputBorder()),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Huỷ'))),
          FilledButton(
            onPressed: () {
              if (required && ctl.text.trim().isEmpty) return;
              Navigator.pop(ctx, ctl.text.trim());
            },
            child: Text(tr('Xác nhận')),
          ),
        ],
      ),
    );
    ctl.dispose();
    return res;
  }

  Future<void> _pickAssignee() async {
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(tr('Giao người xử lý'), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          if (_f?['assigneeEmployeeId'] != null)
            ListTile(
              leading: const Icon(Icons.person_off_outlined, color: SboxColors.danger),
              title: Text(tr('Bỏ giao')),
              onTap: () => Navigator.pop(ctx, '__clear'),
            ),
          for (final h in _handlers)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: SboxColors.brand50,
                child: Text((h['name']?.toString() ?? '?').trim().split(' ').last.characters.first,
                    style: const TextStyle(color: SboxColors.brand700, fontWeight: FontWeight.w700)),
              ),
              title: Text(h['name']?.toString() ?? ''),
              subtitle: Text([h['position'], h['department']]
                  .where((x) => (x?.toString() ?? '').isNotEmpty)
                  .join(' · ')),
              trailing: h['id']?.toString() == _f?['assigneeEmployeeId']?.toString()
                  ? const Icon(Icons.check_rounded, color: SboxColors.success)
                  : null,
              onTap: () => Navigator.pop(ctx, h['id']?.toString()),
            ),
        ]),
      ),
    );
    if (id == null) return;
    await _run(
      _api.manageFeedback(widget.feedbackId,
          id == '__clear' ? {'clearAssignee': true} : {'assigneeEmployeeId': id}),
      id == '__clear' ? 'Đã bỏ giao' : 'Đã giao người xử lý',
    );
  }

  Future<void> _pickPriority() async {
    final p = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final e in FeedbackUi.priorities.entries)
            ListTile(
              leading: Icon(Icons.flag_rounded, color: FeedbackUi.priorityColor(e.key)),
              title: Text(tr(e.value)),
              subtitle: Text(tr('Hạn xử lý ${switch (e.key) { 3 => '1 ngày', 2 => '2 ngày', 1 => '3 ngày', _ => '7 ngày' }} từ lúc gửi')),
              trailing: FeedbackUi.n(_f?['priority']) == e.key ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(ctx, e.key),
            ),
        ]),
      ),
    );
    if (p != null) await _run(_api.manageFeedback(widget.feedbackId, {'priority': p}), 'Đã đổi mức độ');
  }

  Future<void> _pickTopic() async {
    final t = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final x in FeedbackUi.topics)
            ListTile(
              title: Text(tr(x)),
              trailing: _f?['topic'] == x ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(ctx, x),
            ),
        ]),
      ),
    );
    if (t != null) await _run(_api.manageFeedback(widget.feedbackId, {'topic': t}), 'Đã đổi chủ đề');
  }

  Future<void> _pickDue() async {
    final cur = FeedbackUi.date(_f?['dueAt']) ?? DateTime.now().add(const Duration(days: 3));
    final d = await showDatePicker(
      context: context,
      initialDate: cur.isBefore(DateTime.now()) ? DateTime.now() : cur,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d == null) return;
    final due = DateTime(d.year, d.month, d.day, 17, 0);
    await _run(_api.manageFeedback(widget.feedbackId, {'dueAt': due.toIso8601String()}), 'Đã đặt hạn xử lý');
  }

  // ═════════════ GIAO DIỆN ═════════════

  @override
  Widget build(BuildContext context) {
    final f = _f;
    final wide = MediaQuery.of(context).size.width >= 1000;
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: SboxColors.slate900,
        elevation: 0,
        title: Text(
          f == null ? tr('Kiến nghị') : (f['code']?.toString() ?? tr(FeedbackUi.categories[f['category']] ?? 'Kiến nghị')),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(tooltip: tr('Làm mới'), onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : f == null
              ? Center(child: Text(tr(_error ?? 'Không tìm thấy phiếu')))
              : wide
                  ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(child: _conversation(f)),
                      Container(
                        width: 340,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(left: BorderSide(color: SboxColors.slate200)),
                        ),
                        child: ListView(padding: const EdgeInsets.all(16), children: _sidePanel(f)),
                      ),
                    ])
                  : _conversation(f, inlinePanel: true),
    );
  }

  Widget _conversation(Map<String, dynamic> f, {bool inlinePanel = false}) {
    return Column(children: [
      Expanded(
        child: ListView(
          controller: _scrollCtl,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
          children: [
            _header(f),
            if (inlinePanel) ...[
              const SizedBox(height: 12),
              _actionsBar(f),
            ],
            const SizedBox(height: 16),
            if (_replies.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(tr(_isSender ? 'Phiếu đã được gửi — bạn sẽ nhận thông báo khi có phản hồi.' : 'Chưa có trao đổi.'),
                      textAlign: TextAlign.center, style: const TextStyle(color: SboxColors.slate500)),
                ),
              )
            else
              ..._replies.map(_replyItem),
          ],
        ),
      ),
      if (_ctx['canReply'] == true) _composer(),
    ]);
  }

  Widget _header(Map<String, dynamic> f) {
    final category = f['category']?.toString();
    final images = [for (final u in (f['imageUrls'] as List? ?? const [])) u.toString()];
    final sender = f['isAnonymous'] == true
        ? (_isSender ? 'Bạn (gửi ẩn danh)' : 'Người gửi ẩn danh')
        : [f['senderName'], f['senderCode'], f['senderDepartment']]
            .where((x) => (x?.toString() ?? '').isNotEmpty)
            .join(' · ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SboxColors.slate200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          FeedbackUi.pill(FeedbackUi.categories[category] ?? '', FeedbackUi.categoryColor(category),
              icon: FeedbackUi.categoryIcon(category)),
          FeedbackUi.statusPill(f['status']?.toString()),
          FeedbackUi.priorityPill(FeedbackUi.n(f['priority'])),
          FeedbackUi.duePill(f),
          if ((f['topic']?.toString() ?? '').isNotEmpty) FeedbackUi.pill(f['topic'].toString(), SboxColors.slate500),
        ]),
        const SizedBox(height: 10),
        Text(f['title']?.toString() ?? '',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: SboxColors.slate900)),
        const SizedBox(height: 6),
        Row(children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: f['isAnonymous'] == true ? SboxColors.violet.withValues(alpha: 0.15) : SboxColors.brand50,
            child: Icon(f['isAnonymous'] == true ? Icons.visibility_off_rounded : Icons.person_rounded,
                size: 16, color: f['isAnonymous'] == true ? SboxColors.violet : SboxColors.brand600),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${tr(sender)} · ${DateFormat('HH:mm dd/MM/yyyy').format(FeedbackUi.date(f['createdAt']) ?? DateTime.now())}',
              style: const TextStyle(fontSize: 12.5, color: SboxColors.slate500),
            ),
          ),
        ]),
        const Divider(height: 22),
        _richText(f['content']?.toString() ?? ''),
        if (images.isNotEmpty) ...[
          const SizedBox(height: 12),
          _imageGrid(images, size: 110),
        ],
        if (f['rating'] != null) ...[
          const Divider(height: 22),
          Row(children: [
            Text(tr('Đánh giá: '), style: const TextStyle(fontWeight: FontWeight.w600)),
            FeedbackUi.stars(FeedbackUi.n(f['rating'])),
            if ((f['ratingComment']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text('“${f['ratingComment']}”',
                    style: const TextStyle(fontStyle: FontStyle.italic, color: SboxColors.slate600)),
              ),
            ],
          ]),
        ],
      ]),
    );
  }

  /// Thanh hành động (điện thoại) — gọn: thông tin xử lý + nút chính.
  Widget _actionsBar(Map<String, dynamic> f) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SboxColors.slate200),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _sidePanel(f, compact: true)),
      );

  List<Widget> _sidePanel(Map<String, dynamic> f, {bool compact = false}) {
    final status = f['status']?.toString();
    Widget info(IconData icon, String label, String value, {VoidCallback? onTap, Color? color}) => InkWell(
          onTap: _canManage ? onTap : null,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
            child: Row(children: [
              Icon(icon, size: 18, color: SboxColors.slate400),
              const SizedBox(width: 10),
              SizedBox(width: 92, child: Text(tr(label), style: const TextStyle(fontSize: 13, color: SboxColors.slate500))),
              Expanded(
                child: Text(tr(value),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color ?? SboxColors.slate800)),
              ),
              if (_canManage && onTap != null) const Icon(Icons.edit_rounded, size: 15, color: SboxColors.slate400),
            ]),
          ),
        );
    final due = FeedbackUi.date(f['dueAt']);
    final actions = <Widget>[
      if (_canManage) ...[
        if (status == 'Pending')
          FilledButton.icon(
            onPressed: () => _changeStatus('InProgress', 'Tiếp nhận xử lý', askNote: true),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(tr('Tiếp nhận')),
          ),
        if (FeedbackUi.isOpen(status))
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: SboxColors.success),
            onPressed: () => _changeStatus('Resolved', 'Kết quả giải quyết', askNote: true),
            icon: const Icon(Icons.task_alt_rounded),
            label: Text(tr('Đã giải quyết')),
          ),
        if (status == 'Resolved')
          OutlinedButton.icon(
            onPressed: () => _changeStatus('Closed', 'Đóng phiếu'),
            icon: const Icon(Icons.lock_outline_rounded),
            label: Text(tr('Đóng phiếu')),
          ),
        if (status == 'Resolved' || status == 'Closed')
          OutlinedButton.icon(
            onPressed: () => _changeStatus('InProgress', 'Xử lý lại', askNote: true),
            icon: const Icon(Icons.replay_rounded),
            label: Text(tr('Xử lý lại')),
          ),
        if (FeedbackUi.isOpen(status))
          TextButton.icon(
            onPressed: () => _changeStatus('Closed', 'Đóng phiếu (không xử lý)', askNote: true),
            icon: const Icon(Icons.block_rounded, size: 18),
            label: Text(tr('Đóng không xử lý')),
          ),
      ],
      if (_ctx['canRate'] == true)
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF5A524)),
          onPressed: _rate,
          icon: const Icon(Icons.star_rounded),
          label: Text(tr('Đánh giá kết quả')),
        ),
      if (_ctx['canReopen'] == true)
        OutlinedButton.icon(onPressed: _reopen, icon: const Icon(Icons.replay_rounded), label: Text(tr('Chưa thoả đáng — mở lại'))),
      if (_ctx['canWithdraw'] == true)
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: SboxColors.danger),
          onPressed: _withdraw,
          icon: const Icon(Icons.undo_rounded, size: 18),
          label: Text(tr('Thu hồi phiếu')),
        ),
    ];
    return [
      if (!compact)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(tr('Thông tin xử lý'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ),
      info(Icons.flag_rounded, 'Mức độ', FeedbackUi.priorities[FeedbackUi.n(f['priority'])] ?? '',
          onTap: _pickPriority, color: FeedbackUi.priorityColor(FeedbackUi.n(f['priority']))),
      info(Icons.schedule_rounded, 'Hạn xử lý',
          due == null ? '—' : '${DateFormat('HH:mm dd/MM').format(due)}'
              '${FeedbackUi.isOpen(status) ? ' (${FeedbackUi.dueText(due)})' : ''}',
          onTap: _pickDue, color: f['overdue'] == true ? SboxColors.danger : null),
      info(Icons.inbox_rounded, 'Gửi tới', f['recipientName']?.toString() ?? 'Hòm thư chung'),
      info(Icons.assignment_ind_rounded, 'Người xử lý', f['assigneeName']?.toString() ?? 'Chưa giao',
          onTap: _pickAssignee),
      info(Icons.label_outline_rounded, 'Chủ đề', f['topic']?.toString() ?? 'Chưa phân loại', onTap: _pickTopic),
      if (f['firstResponseAt'] != null)
        info(Icons.reply_rounded, 'Phản hồi đầu',
            FeedbackUi.ago(FeedbackUi.date(f['firstResponseAt']))),
      if (actions.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: actions),
      ],
      if (_canManage && !compact) ...[
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: SboxColors.slate50, borderRadius: BorderRadius.circular(12)),
          child: Text(
            tr(f['isAnonymous'] == true
                ? 'Phiếu ẩn danh: hệ thống không tiết lộ người gửi cho bất kỳ ai. Trao đổi trực tiếp tại đây, người gửi vẫn nhận được thông báo.'
                : 'Ghi chú nội bộ (bật ở ô nhập) chỉ người xử lý thấy, người gửi không thấy.'),
            style: const TextStyle(fontSize: 12, color: SboxColors.slate600),
          ),
        ),
      ],
    ];
  }

  Widget _replyItem(Map<String, dynamic> r) {
    final kind = FeedbackUi.n(r['kind']);
    final time = FeedbackUi.date(r['createdAt']);
    if (kind == 2) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          const Expanded(child: Divider(color: SboxColors.slate200)),
          Flexible(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '${r['content']} · ${time == null ? '' : DateFormat('HH:mm dd/MM').format(time)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500),
              ),
            ),
          ),
          const Expanded(child: Divider(color: SboxColors.slate200)),
        ]),
      );
    }
    final mine = r['isMine'] == true;
    final internal = kind == 1;
    final images = [for (final u in (r['imageUrls'] as List? ?? const [])) u.toString()];
    final name = r['senderName']?.toString() ??
        (r['isFromSender'] == true ? 'Người gửi (ẩn danh)' : 'Người xử lý');
    final bg = internal
        ? const Color(0xFFFFF7E0)
        : mine
            ? SboxColors.brand600
            : Colors.white;
    final fg = mine && !internal ? Colors.white : SboxColors.slate800;
    var content = r['content']?.toString() ?? '';
    if (images.isNotEmpty && content == '📷 Hình ảnh') content = '';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
            border: Border.all(
                color: internal ? const Color(0xFFF5C84C) : mine ? SboxColors.brand600 : SboxColors.slate200),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!mine || internal)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (internal) ...[
                    const Icon(Icons.lock_rounded, size: 12, color: Color(0xFFB7791F)),
                    const SizedBox(width: 4),
                    Text(tr('Ghi chú nội bộ · '),
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFB7791F))),
                  ],
                  Text(tr(mine ? 'Bạn' : name),
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700,
                          color: internal ? const Color(0xFFB7791F) : SboxColors.brand700)),
                ]),
              ),
            if (content.isNotEmpty) _richText(content, color: fg),
            if (images.isNotEmpty) ...[
              if (content.isNotEmpty) const SizedBox(height: 6),
              _imageGrid(images, size: 150),
            ],
            const SizedBox(height: 3),
            Text(time == null ? '' : DateFormat('HH:mm dd/MM').format(time),
                style: TextStyle(fontSize: 10.5, color: mine && !internal ? Colors.white70 : SboxColors.slate400)),
          ]),
        ),
      ),
    );
  }

  Widget _composer() => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: SboxColors.slate200)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_canManage)
              Row(children: [
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text(tr('Trả lời người gửi')),
                  selected: !_internal,
                  onSelected: (_) => setState(() => _internal = false),
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  avatar: const Icon(Icons.lock_rounded, size: 14),
                  label: Text(tr('Ghi chú nội bộ')),
                  selected: _internal,
                  selectedColor: const Color(0xFFFFF0C2),
                  onSelected: (_) => setState(() => _internal = true),
                  visualDensity: VisualDensity.compact,
                ),
              ]),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              IconButton(
                tooltip: tr('Gửi ảnh'),
                onPressed: _sending ? null : _sendImage,
                icon: const Icon(Icons.add_photo_alternate_outlined, color: SboxColors.slate500),
              ),
              Expanded(
                child: TextField(
                  controller: _replyCtl,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: tr(_internal ? 'Ghi chú cho người xử lý khác (người gửi không thấy)…' : 'Nhập phản hồi…'),
                    isDense: true,
                    filled: true,
                    fillColor: _internal ? const Color(0xFFFFF9E6) : SboxColors.slate50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
              ),
            ]),
          ]),
        ),
      );

  // ── Nội dung / ảnh ──

  Widget _richText(String text, {Color color = SboxColors.slate800}) {
    final urlRegex = RegExp(r'(https?://[^\s<>\[\]{}|\\^]+)', caseSensitive: false);
    final style = TextStyle(fontSize: 14, height: 1.45, color: color);
    final matches = urlRegex.allMatches(text).toList();
    if (matches.isEmpty) return SelectableText(text, style: style);
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in matches) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start), style: style));
      final url = m.group(0)!;
      spans.add(WidgetSpan(
        child: GestureDetector(
          onTap: () async {
            final uri = Uri.tryParse(url);
            if (uri != null && await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
          },
          child: Text(url, style: style.copyWith(decoration: TextDecoration.underline, color: SboxColors.brand500)),
        ),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last), style: style));
    return RichText(text: TextSpan(children: spans));
  }

  Widget _imageGrid(List<String> urls, {double size = 120}) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < urls.length; i++)
            GestureDetector(
              onTap: () => _showImages(urls, i),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AuthCachedImage(
                  imagePath: urls[i],
                  apiService: _api,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    width: size,
                    height: size,
                    color: SboxColors.slate200,
                    child: const Icon(Icons.broken_image_outlined, color: SboxColors.slate500),
                  ),
                ),
              ),
            ),
        ],
      );

  void _showImages(List<String> urls, int initial) {
    final ctl = PageController(initialPage: initial);
    showDialog(
      context: context,
      barrierColor: Colors.black,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(children: [
          PageView.builder(
            controller: ctl,
            itemCount: urls.length,
            itemBuilder: (_, i) => InteractiveViewer(
              maxScale: 6,
              child: Center(
                child: AuthCachedImage(
                  imagePath: urls[i],
                  apiService: _api,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) => const Icon(Icons.broken_image, color: Colors.white54, size: 64),
                ),
              ),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
        ]),
      ),
    );
  }
}
