import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/sbox_app_variant.dart';
import '../../l10n/app_tr.dart';
import '../../models/comm_v2.dart';
import '../../services/api_service.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'comm_common.dart';

/// Báo cáo vi phạm, chặn người dùng, điều khoản cộng đồng của Bản tin nội bộ (App Store guideline 1.2).

/// App Nhân Viên trên iOS chỉ cho xem, bình luận, thả cảm xúc — không đăng bài, không soạn bằng AI.
bool get commComposeHidden => SboxAppVariant.staffApp && !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

const commReportReasons = <(String, String)>[
  ('spam', 'Spam, quảng cáo'),
  ('harassment', 'Quấy rối, xúc phạm, bắt nạt'),
  ('inappropriate', 'Nội dung không phù hợp, phản cảm'),
  ('false_info', 'Thông tin sai sự thật'),
  ('other', 'Lý do khác'),
];

String commReportReasonLabel(String code) =>
    commReportReasons.where((r) => r.$1 == code).map((r) => r.$2).firstOrNull ?? 'Lý do khác';

/// Lần đầu bình luận / đăng bài trên iOS: đồng ý quy tắc cộng đồng (không chấp nhận nội dung xấu). Trả true nếu được viết.
Future<bool> ensureCommTerms(BuildContext context, String? userId) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return true;
  final key = 'comm_terms_v1_${userId ?? ''}';
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(key) == true) return true;
    if (!context.mounted) return false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Quy tắc Bản tin nội bộ')),
        content: SingleChildScrollView(
          child: Text(tr(
            'Bản tin là nơi trao đổi công việc trong cửa hàng. Khi viết bình luận, bạn đồng ý:\n\n'
            '• Không đăng nội dung xúc phạm, quấy rối, phân biệt đối xử, khiêu dâm, bạo lực hay spam.\n'
            '• Không chia sẻ thông tin cá nhân của người khác khi chưa được đồng ý.\n\n'
            'Cửa hàng không chấp nhận nội dung vi phạm. Bạn có thể bấm «Báo cáo» trên bài hoặc bình luận, '
            'hoặc «Chặn» người viết. Quản lý cửa hàng xem báo cáo, gỡ nội dung vi phạm và có thể khóa tài khoản người vi phạm.',
          )),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Để sau'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Tôi đồng ý'))),
        ],
      ),
    );
    if (ok != true) return false;
    await prefs.setBool(key, true);
    return true;
  } catch (_) {
    return true;
  }
}

/// Báo cáo bài ([postId]) hoặc bình luận ([commentId]). Trả true khi đã gửi — nội dung bị ẩn với người báo cáo.
Future<bool> showCommReportSheet(BuildContext context, {String? postId, String? commentId}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReportSheet(postId: postId, commentId: commentId),
  );
  return sent == true;
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({this.postId, this.commentId});

  final String? postId;
  final String? commentId;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String? _reason;
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null || _busy) return;
    setState(() => _busy = true);
    final api = ApiService();
    final note = _note.text.trim();
    final r = widget.commentId != null
        ? await api.reportCommComment(widget.commentId!, reason, note: note)
        : await api.reportCommPost(widget.postId!, reason, note: note);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['isSuccess'] == true) {
      commToast(context, 'Đã gửi báo cáo cho quản lý. Bạn sẽ không thấy nội dung này nữa.');
      Navigator.pop(context, true);
    } else {
      commToast(context, '${r['message'] ?? 'Không gửi được báo cáo'}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(tr(widget.commentId != null ? 'Báo cáo bình luận' : 'Báo cáo bài viết'), style: SboxType.titleStyle()),
          const SizedBox(height: 4),
          Text(tr('Quản lý cửa hàng sẽ xem và xử lý. Người viết không biết ai báo cáo.'), style: SboxType.smallStyle()),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: _reason,
            onChanged: (v) => setState(() => _reason = v),
            child: Column(children: [
              for (final r in commReportReasons)
                RadioListTile<String>(value: r.$1, title: Text(tr(r.$2)), contentPadding: EdgeInsets.zero, dense: true),
            ]),
          ),
          TextField(
            controller: _note,
            maxLength: 500,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(labelText: tr('Ghi chú thêm (không bắt buộc)')),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _reason == null || _busy ? null : _send,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.flag_outlined),
            label: Text(tr('Gửi báo cáo')),
          ),
        ]),
      ),
    );
  }
}

/// Bình luận của người khác: chọn báo cáo hoặc chặn người viết. Trả 'reported' / 'blocked' / null.
Future<String?> showCommCommentModeration(BuildContext context, CommComment c) async {
  final pick = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.flag_outlined, color: SboxColors.danger),
          title: Text(tr('Báo cáo bình luận')),
          subtitle: Text(tr('Gửi quản lý cửa hàng xem xét')),
          onTap: () => Navigator.pop(ctx, 'report'),
        ),
        ListTile(
          leading: const Icon(Icons.block_rounded, color: SboxColors.danger),
          title: Text(tr('Chặn ${c.userName ?? 'người này'}')),
          subtitle: Text(tr('Không thấy bài, bình luận của người này nữa')),
          onTap: () => Navigator.pop(ctx, 'block'),
        ),
        const SizedBox(height: 8),
      ]),
    ),
  );
  if (pick == null || !context.mounted) return null;
  if (pick == 'report') return await showCommReportSheet(context, commentId: c.id) ? 'reported' : null;
  return await confirmCommBlock(context, c.userId, c.userName) ? 'blocked' : null;
}

/// Chặn người dùng: không thấy bài, bình luận và không nhận thông báo từ họ. Trả true khi đã chặn.
Future<bool> confirmCommBlock(BuildContext context, String userId, String? name) async {
  final who = (name ?? '').trim().isEmpty ? 'người này' : name!.trim();
  final ok = await SboxDialogs.confirm(
    context,
    title: 'Chặn $who?',
    message: 'Bạn sẽ không thấy bài viết, bình luận và không nhận thông báo từ $who trong Bản tin. '
        'Văn bản bắt buộc đọc vẫn hiện. Gỡ chặn trong Bản tin › Người đã chặn.',
    confirmLabel: 'Chặn',
    danger: true,
    icon: Icons.block_rounded,
  );
  if (!ok || !context.mounted) return false;
  final r = await ApiService().blockCommUser(userId);
  if (!context.mounted) return false;
  if (r['isSuccess'] == true) {
    commToast(context, 'Đã chặn $who');
    return true;
  }
  commToast(context, '${r['message'] ?? 'Không chặn được'}', error: true);
  return false;
}

/// Danh sách người mình đã chặn, gỡ chặn được.
class CommBlockedUsersPage extends StatefulWidget {
  const CommBlockedUsersPage({super.key});

  @override
  State<CommBlockedUsersPage> createState() => _CommBlockedUsersPageState();
}

class _CommBlockedUsersPageState extends State<CommBlockedUsersPage> {
  List<Map<String, dynamic>>? _rows;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await ApiService().getCommBlocks();
    if (!mounted) return;
    setState(() => _rows = (r['data'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
  }

  Future<void> _unblock(Map<String, dynamic> row) async {
    final r = await ApiService().unblockCommUser('${row['userId']}');
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      _changed = true;
      commToast(context, 'Đã bỏ chặn ${row['name'] ?? ''}');
      _load();
    } else {
      commToast(context, '${r['message']}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: SboxColors.page,
        appBar: AppBar(
          backgroundColor: SboxColors.appBarBg(SboxColors.surface),
          surfaceTintColor: Colors.transparent,
          title: Text(tr('Người đã chặn')),
        ),
        body: rows == null
            ? const SboxLoading()
            : rows.isEmpty
                ? const SboxEmptyState(
                    icon: Icons.block_rounded,
                    title: 'Bạn chưa chặn ai',
                    message: 'Chặn trong menu ⋯ của bài viết hoặc nút «Báo cáo» dưới bình luận.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final row = rows[i];
                      final name = '${row['name'] ?? '—'}';
                      return Material(
                        color: SboxColors.surface,
                        borderRadius: SboxRadius.mdAll,
                        child: ListTile(
                          leading: CommAvatar(name: name, size: 36),
                          title: Text(name),
                          trailing: OutlinedButton(onPressed: () => _unblock(row), child: Text(tr('Bỏ chặn'))),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}

/// Người kiểm duyệt: báo cáo vi phạm chờ xử lý / đã xử lý.
class CommReportsPage extends StatefulWidget {
  const CommReportsPage({super.key, this.onOpenPost});

  final void Function(String postId)? onOpenPost;

  @override
  State<CommReportsPage> createState() => _CommReportsPageState();
}

class _CommReportsPageState extends State<CommReportsPage> {
  String _status = 'open';
  List<Map<String, dynamic>>? _rows;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _rows = null);
    final r = await ApiService().getCommReports(status: _status);
    if (!mounted) return;
    if (r['isSuccess'] != true) commToast(context, '${r['message']}', error: true);
    setState(() => _rows = (r['data'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
  }

  Future<void> _resolve(Map<String, dynamic> row, bool remove) async {
    final isComment = row['commentId'] != null;
    if (remove) {
      final ok = await SboxDialogs.confirm(
        context,
        title: isComment ? 'Xóa bình luận bị báo cáo?' : 'Gỡ bài bị báo cáo?',
        message: isComment ? 'Bình luận và các phản hồi của nó bị xóa.' : 'Bài được chuyển vào lưu trữ, không còn hiện trên bảng tin.',
        confirmLabel: isComment ? 'Xóa' : 'Gỡ bài',
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    final r = await ApiService().resolveCommReport('${row['id']}', remove ? 'remove' : 'dismiss');
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      _changed = true;
      commToast(context, remove ? (isComment ? 'Đã xóa bình luận' : 'Đã gỡ bài') : 'Đã bỏ qua báo cáo');
      _load();
    } else {
      commToast(context, '${r['message']}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: SboxColors.page,
        appBar: AppBar(
          backgroundColor: SboxColors.appBarBg(SboxColors.surface),
          surfaceTintColor: Colors.transparent,
          title: Text(tr('Báo cáo vi phạm')),
        ),
        body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Wrap(spacing: 8, children: [
              ChoiceChip(label: Text(tr('Chờ xử lý')), selected: _status == 'open', onSelected: (_) {
                _status = 'open';
                _load();
              }),
              ChoiceChip(label: Text(tr('Đã xử lý')), selected: _status == 'done', onSelected: (_) {
                _status = 'done';
                _load();
              }),
            ]),
          ),
          Expanded(
            child: rows == null
                ? const SboxLoading()
                : rows.isEmpty
                    ? SboxEmptyState(
                        icon: Icons.verified_outlined,
                        title: _status == 'open' ? 'Không có báo cáo chờ xử lý' : 'Chưa xử lý báo cáo nào',
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) => Center(
                            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: _card(rows[i])),
                          ),
                        ),
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _card(Map<String, dynamic> row) {
    final isComment = row['commentId'] != null;
    final at = DateTime.tryParse('${row['createdAt']}')?.toLocal();
    final status = (row['status'] as num?)?.toInt() ?? 0;
    final exists = row['contentExists'] == true;
    final note = '${row['note'] ?? ''}'.trim();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: SboxColors.surface, borderRadius: SboxRadius.mdAll, border: Border.all(color: SboxColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SboxStatusChip(label: isComment ? 'Bình luận' : 'Bài viết', icon: isComment ? Icons.chat_bubble_outline : Icons.article_outlined),
          const SizedBox(width: 6),
          Flexible(child: SboxStatusChip(label: commReportReasonLabel('${row['reason']}'), tone: SboxTone.danger)),
          const Spacer(),
          if (at != null) Text(commTimeAgo(at), style: SboxType.captionStyle()),
        ]),
        const SizedBox(height: 10),
        Text(tr('Của ${row['targetUserName'] ?? '—'}'), style: SboxType.bodyStrong()),
        const SizedBox(height: 4),
        Text('${row['excerpt'] ?? ''}', maxLines: 6, overflow: TextOverflow.ellipsis, style: SboxType.bodyStyle()),
        if (isComment && (row['postTitle'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(tr('Trong bài «${row['postTitle']}»'), style: SboxType.captionStyle()),
        ],
        if (note.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(tr('Ghi chú: $note'), style: SboxType.smallStyle()),
        ],
        const SizedBox(height: 6),
        Text(tr('Người báo cáo: ${row['reporterName'] ?? '—'}'), style: SboxType.captionStyle()),
        if (status != 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(tr('${status == 1 ? 'Đã gỡ nội dung' : 'Đã bỏ qua'} · ${row['resolvedBy'] ?? ''}'),
                style: SboxType.captionStyle(status == 1 ? SboxColors.danger : SboxColors.slate500)),
          ),
        if (status == 0) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (exists)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: SboxColors.danger),
                onPressed: () => _resolve(row, true),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: Text(tr(isComment ? 'Xóa bình luận' : 'Gỡ bài')),
              ),
            OutlinedButton(onPressed: () => _resolve(row, false), child: Text(tr(exists ? 'Bỏ qua' : 'Đóng (nội dung đã xóa)'))),
            if (exists && widget.onOpenPost != null)
              TextButton(onPressed: () => widget.onOpenPost!('${row['postId']}'), child: Text(tr('Xem bài'))),
          ]),
        ],
      ]),
    );
  }
}
