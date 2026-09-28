import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../models/comm_v2.dart';
import '../../services/api_service.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'comm_common.dart';

/// Thẻ bài trên bảng tin: tác giả, kênh, nội dung rút gọn, ảnh, tệp, bình chọn, sự kiện, xác nhận đọc, cảm xúc.
class CommPostCard extends StatefulWidget {
  const CommPostCard({
    super.key,
    required this.post,
    required this.ctx,
    required this.onOpen,
    required this.onChanged,
    this.onEdit,
    this.expanded = false,
  });

  final CommPost post;
  final CommContext ctx;
  final VoidCallback onOpen;
  /// Bài thay đổi (xóa / ghim / duyệt) → bảng tin tải lại.
  final VoidCallback onChanged;
  final VoidCallback? onEdit;
  /// Trang chi tiết: hiện đủ nội dung.
  final bool expanded;

  @override
  State<CommPostCard> createState() => _CommPostCardState();
}

class _CommPostCardState extends State<CommPostCard> {
  final _api = ApiService();
  bool _busy = false;

  CommPost get p => widget.post;

  Future<void> _react(int type) async {
    final before = p.myReaction;
    setState(() {
      if (before == type) {
        p.myReaction = null;
        p.reactionTotal--;
        p.reactions[type] = (p.reactions[type] ?? 1) - 1;
      } else {
        if (before != null) p.reactions[before] = (p.reactions[before] ?? 1) - 1;
        if (before == null) p.reactionTotal++;
        p.myReaction = type;
        p.reactions[type] = (p.reactions[type] ?? 0) + 1;
      }
    });
    final r = await _api.reactCommPost(p.id, type);
    if (r['isSuccess'] != true && mounted) commToast(context, '${r['message']}', error: true);
  }

  Future<void> _ack() async {
    setState(() => _busy = true);
    final r = await _api.ackCommPost(p.id);
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['isSuccess'] == true) {
      setState(() {
        p.myAcked = true;
        p.ackCount++;
      });
      commToast(context, 'Đã xác nhận đọc');
    } else {
      commToast(context, '${r['message']}', error: true);
    }
  }

  Future<void> _vote(String optionId) async {
    final poll = p.poll!;
    if (poll.closed) return;
    final next = poll.multiple
        ? (poll.myVotes.contains(optionId) ? (poll.myVotes.toList()..remove(optionId)) : [...poll.myVotes, optionId])
        : [optionId];
    final r = await _api.voteCommPoll(p.id, next);
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      final wasVoter = poll.myVotes.isNotEmpty;
      setState(() {
        for (final o in poll.options) {
          if (poll.myVotes.contains(o.id)) o.votes--;
          if (next.contains(o.id)) o.votes++;
        }
        poll.myVotes = next;
        if (!wasVoter && next.isNotEmpty) poll.totalVoters++;
        if (wasVoter && next.isEmpty) poll.totalVoters--;
      });
    } else {
      commToast(context, '${r['message']}', error: true);
    }
  }

  Future<void> _menu(String v) async {
    switch (v) {
      case 'edit':
        widget.onEdit?.call();
      case 'pin':
        await _api.pinCommPost(p.id, !p.isPinned);
        widget.onChanged();
      case 'readers':
        await showCommReaders(context, p);
      case 'save':
        final r = await _api.saveCommBookmark(p.id);
        if (r['isSuccess'] == true && mounted) {
          setState(() => p.mySaved = r['data'] == true);
          commToast(context, p.mySaved ? 'Đã lưu bài' : 'Đã bỏ lưu');
        }
      case 'approve':
      case 'reject':
        final r = await _api.approveCommPost(p.id, v == 'approve');
        if (mounted) commToast(context, r['isSuccess'] == true ? (v == 'approve' ? 'Đã duyệt và đăng' : 'Đã từ chối') : '${r['message']}', error: r['isSuccess'] != true);
        widget.onChanged();
      case 'delete':
        final ok = await SboxDialogs.confirm(context, title: 'Xóa bài «${p.title}»?', message: 'Bài được chuyển vào lưu trữ, lịch sử xác nhận đọc vẫn giữ.', confirmLabel: 'Xóa', danger: true);
        if (!ok) return;
        await _api.deleteCommPost(p.id);
        widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final chColor = commColor(p.channelColor);
    final ackPending = p.requireAck && !p.myAcked && p.status == CommStatus.published;
    return Container(
      decoration: BoxDecoration(
        color: SboxColors.surface,
        borderRadius: SboxRadius.lgAll,
        border: Border.all(color: ackPending ? SboxColors.danger.withValues(alpha: 0.45) : SboxColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (p.isPinned || p.status != CommStatus.published)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: p.status == CommStatus.published ? SboxColors.brand50 : SboxColors.warningSoft,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(SboxRadius.lg)),
            ),
            child: Row(children: [
              Icon(p.status == CommStatus.published ? Icons.push_pin_rounded : Icons.info_outline, size: 14,
                  color: p.status == CommStatus.published ? SboxColors.brand700 : SboxColors.warningText),
              const SizedBox(width: 6),
              Text(
                tr(switch (p.status) {
                  CommStatus.draft => 'Bản nháp — chỉ bạn thấy',
                  CommStatus.pendingApproval => 'Đang chờ quản lý duyệt',
                  CommStatus.scheduled => 'Hẹn đăng ${p.scheduledAt == null ? '' : commTimeAgo(p.scheduledAt!)}',
                  CommStatus.rejected => 'Bị từ chối',
                  CommStatus.archived => 'Đã lưu trữ',
                  _ => 'Bài được ghim',
                }),
                style: SboxType.captionStyle(p.status == CommStatus.published ? SboxColors.brand700 : SboxColors.warningText).copyWith(fontWeight: FontWeight.w600),
              ),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CommAvatar(name: p.authorName ?? '?', photo: p.authorAvatar, size: 42),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.authorName ?? '—', style: SboxType.bodyStrong()),
                const SizedBox(height: 2),
                Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (p.channelName != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(color: chColor.withValues(alpha: 0.12), borderRadius: SboxRadius.pillAll),
                      child: Text(tr(p.channelName!), style: SboxType.captionStyle(chColor).copyWith(fontWeight: FontWeight.w600)),
                    ),
                  Text(commTimeAgo(p.when), style: SboxType.captionStyle()),
                  if (p.audience != null && !p.audience!.isEveryone) const Icon(Icons.group_outlined, size: 14, color: SboxColors.slate400),
                ]),
              ]),
            ),
            if (p.urgent) const Padding(padding: EdgeInsets.only(right: 4, top: 4), child: SboxStatusChip(label: 'Quan trọng', tone: SboxTone.danger)),
            PopupMenuButton<String>(
              tooltip: tr('Thêm'),
              onSelected: _menu,
              itemBuilder: (_) => [
                PopupMenuItem(value: 'save', child: ListTile(dense: true, leading: Icon(p.mySaved ? Icons.bookmark : Icons.bookmark_border), title: Text(tr(p.mySaved ? 'Bỏ lưu' : 'Lưu bài')))),
                if (p.canEdit) PopupMenuItem(value: 'edit', child: ListTile(dense: true, leading: const Icon(Icons.edit_outlined), title: Text(tr('Sửa bài')))),
                if (widget.ctx.isManager && p.status == CommStatus.published)
                  PopupMenuItem(value: 'pin', child: ListTile(dense: true, leading: const Icon(Icons.push_pin_outlined), title: Text(tr(p.isPinned ? 'Bỏ ghim' : 'Ghim lên đầu')))),
                if (p.canEdit && p.status == CommStatus.published)
                  PopupMenuItem(value: 'readers', child: ListTile(dense: true, leading: const Icon(Icons.fact_check_outlined), title: Text(tr('Ai đã đọc')))),
                if (widget.ctx.isManager && p.status == CommStatus.pendingApproval) ...[
                  PopupMenuItem(value: 'approve', child: ListTile(dense: true, leading: const Icon(Icons.check_circle_outline), title: Text(tr('Duyệt và đăng')))),
                  PopupMenuItem(value: 'reject', child: ListTile(dense: true, leading: const Icon(Icons.block_outlined), title: Text(tr('Từ chối')))),
                ],
                if (p.canEdit) PopupMenuItem(value: 'delete', child: ListTile(dense: true, leading: const Icon(Icons.delete_outline, color: SboxColors.danger), title: Text(tr('Xóa bài')))),
              ],
            ),
          ]),
        ),
        InkWell(
          onTap: widget.expanded ? null : widget.onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (p.requireAck)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    SboxStatusChip(label: p.myAcked ? 'Bạn đã xác nhận' : 'Bắt buộc đọc', tone: p.myAcked ? SboxTone.success : SboxTone.danger, icon: Icons.verified_user_outlined),
                    if (p.version > 1) ...[const SizedBox(width: 6), SboxStatusChip(label: 'Bản ${p.version}', tone: SboxTone.violet)],
                    if (p.ackDeadline != null && !p.myAcked) ...[
                      const SizedBox(width: 6),
                      Text(tr('hạn ${p.ackDeadline!.day}/${p.ackDeadline!.month}'), style: SboxType.captionStyle(SboxColors.dangerText)),
                    ],
                  ]),
                ),
              if (p.title.isNotEmpty) Text(p.title, style: SboxType.titleStyle()),
              const SizedBox(height: 6),
              if (widget.expanded)
                CommHtml(html: p.contentHtml)
              else if ((p.summary ?? '').isNotEmpty)
                Text(p.summary!, maxLines: 4, overflow: TextOverflow.ellipsis, style: SboxType.bodyStyle(SboxColors.textSecondary))
              else
                CommHtml(html: p.contentHtml, maxLines: 5),
              if (!widget.expanded && p.contentHtml.length > 400)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(tr('Xem thêm'), style: SboxType.smallStyle(SboxColors.brand700).copyWith(fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
        ),
        if (p.eventAt != null) Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: _eventBox()),
        if (p.allImages.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: CommImageGrid(urls: p.allImages)),
        if (p.files.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(children: [
              for (final f in p.files) Padding(padding: const EdgeInsets.only(bottom: 6), child: CommFileTile(file: f, dense: true)),
            ]),
          ),
        if (p.poll != null) Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: _pollBox(p.poll!)),
        if (p.tagList.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(spacing: 6, children: [for (final t in p.tagList) Text('#$t', style: SboxType.captionStyle(SboxColors.brand700))]),
          ),
        if (p.requireAck && p.status == CommStatus.published) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: _ackBox()),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(children: [
            if (p.reactionTotal > 0) ...[
              Text(commReactions.where((r) => (p.reactions[r.$1] ?? 0) > 0).map((r) => r.$2).take(3).join(), style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 4),
              Text('${p.reactionTotal}', style: SboxType.captionStyle()),
            ],
            const Spacer(),
            if (p.comments > 0) Text(tr('${p.comments} bình luận'), style: SboxType.captionStyle()),
            if (p.views > 0) ...[const SizedBox(width: 10), Text(tr('${p.views} lượt xem'), style: SboxType.captionStyle())],
          ]),
        ),
        const Divider(height: 1, color: SboxColors.divider),
        if (p.status == CommStatus.published)
          Row(children: [
            Expanded(child: _reactButton()),
            Expanded(
              child: TextButton.icon(
                onPressed: p.allowComments ? widget.onOpen : null,
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 19),
                label: Text(tr('Bình luận')),
                style: TextButton.styleFrom(foregroundColor: SboxColors.slate600),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: () => _menu('save'),
                icon: Icon(p.mySaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, size: 19),
                label: Text(tr(p.mySaved ? 'Đã lưu' : 'Lưu')),
                style: TextButton.styleFrom(foregroundColor: p.mySaved ? SboxColors.brand700 : SboxColors.slate600),
              ),
            ),
          ])
        else
          const SizedBox(height: 8),
      ]),
    );
  }

  Widget _reactButton() {
    final mine = commReactions.where((r) => r.$1 == p.myReaction).firstOrNull;
    return GestureDetector(
      onLongPress: _pickReaction,
      child: TextButton.icon(
        onPressed: () => _react(p.myReaction ?? 0),
        onLongPress: _pickReaction,
        icon: mine == null ? const Icon(Icons.thumb_up_outlined, size: 19) : Text(mine.$2, style: const TextStyle(fontSize: 17)),
        label: Text(tr(mine?.$3 ?? 'Thích')),
        style: TextButton.styleFrom(foregroundColor: mine == null ? SboxColors.slate600 : SboxColors.brand700),
      ),
    );
  }

  Future<void> _pickReaction() async {
    final box = context.findRenderObject() as RenderBox?;
    final pos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final picked = await showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx + 16, pos.dy + (box?.size.height ?? 0) - 90, pos.dx + 300, 0),
      items: [
        PopupMenuItem(
          enabled: false,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            for (final r in commReactions)
              InkWell(
                onTap: () => Navigator.pop(context, r.$1),
                child: Tooltip(message: tr(r.$3), child: Padding(padding: const EdgeInsets.all(6), child: Text(r.$2, style: const TextStyle(fontSize: 26)))),
              ),
          ]),
        ),
      ],
    );
    if (picked != null) _react(picked);
  }

  Widget _eventBox() {
    final d = p.eventAt!;
    const months = ['', 'Th1', 'Th2', 'Th3', 'Th4', 'Th5', 'Th6', 'Th7', 'Th8', 'Th9', 'Th10', 'Th11', 'Th12'];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: SboxColors.warningSoft.withValues(alpha: 0.6), borderRadius: SboxRadius.mdAll),
      child: Row(children: [
        Container(
          width: 52,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(color: SboxColors.surface, borderRadius: SboxRadius.mdAll),
          child: Column(children: [
            Text(months[d.month], style: SboxType.captionStyle(SboxColors.dangerText).copyWith(fontWeight: FontWeight.w700)),
            Text('${d.day}', style: SboxType.headlineStyle()),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Sự kiện · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'), style: SboxType.bodyStrong()),
            if ((p.eventLocation ?? '').isNotEmpty)
              Row(children: [
                const Icon(Icons.place_outlined, size: 14, color: SboxColors.slate500),
                const SizedBox(width: 4),
                Expanded(child: Text(p.eventLocation!, style: SboxType.smallStyle())),
              ]),
          ]),
        ),
      ]),
    );
  }

  Widget _pollBox(CommPoll poll) {
    final total = poll.totalVotes;
    final voted = poll.myVotes.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: SboxColors.border), borderRadius: SboxRadius.mdAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.poll_outlined, size: 18, color: SboxColors.warning),
          const SizedBox(width: 6),
          Expanded(child: Text(poll.question, style: SboxType.bodyStrong())),
        ]),
        const SizedBox(height: 8),
        for (final o in poll.options)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: InkWell(
              borderRadius: SboxRadius.mdAll,
              onTap: poll.closed ? null : () => _vote(o.id),
              child: Stack(children: [
                if (voted || poll.closed)
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: total == 0 ? 0 : o.votes / total,
                      child: Container(
                        decoration: BoxDecoration(
                          color: poll.myVotes.contains(o.id) ? SboxColors.brand100 : SboxColors.slate100,
                          borderRadius: SboxRadius.mdAll,
                        ),
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: SboxRadius.mdAll,
                    border: Border.all(color: poll.myVotes.contains(o.id) ? SboxColors.brand500 : SboxColors.border),
                  ),
                  child: Row(children: [
                    Icon(
                      poll.myVotes.contains(o.id)
                          ? (poll.multiple ? Icons.check_box : Icons.radio_button_checked)
                          : (poll.multiple ? Icons.check_box_outline_blank : Icons.radio_button_unchecked),
                      size: 18,
                      color: poll.myVotes.contains(o.id) ? SboxColors.brand600 : SboxColors.slate400,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(o.text, style: SboxType.smallStyle(SboxColors.text))),
                    if (voted || poll.closed) Text('${total == 0 ? 0 : (o.votes * 100 / total).round()}% · ${o.votes}', style: SboxType.captionStyle()),
                  ]),
                ),
              ]),
            ),
          ),
        Text(
          tr('${poll.totalVoters} người đã bình chọn${poll.multiple ? ' · chọn nhiều' : ''}${poll.closed ? ' · đã đóng' : ''}'),
          style: SboxType.captionStyle(),
        ),
      ]),
    );
  }

  Widget _ackBox() {
    final rate = p.audienceCount == 0 ? 0.0 : p.ackCount / p.audienceCount;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: p.myAcked ? SboxColors.successSoft.withValues(alpha: 0.6) : SboxColors.dangerSoft.withValues(alpha: 0.5),
        borderRadius: SboxRadius.mdAll,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(
              tr(p.myAcked ? 'Bạn đã đọc và xác nhận văn bản này' : 'Vui lòng đọc kỹ và xác nhận đã hiểu'),
              style: SboxType.smallStyle(p.myAcked ? SboxColors.successText : SboxColors.dangerText).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (!p.myAcked)
            SboxButton(label: 'Tôi đã đọc và cam kết', icon: Icons.check_rounded, size: SboxButtonSize.sm, loading: _busy, onPressed: _busy ? null : _ack),
        ]),
        if (p.canEdit || widget.ctx.isManager) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: SboxRadius.pillAll,
            child: LinearProgressIndicator(
              value: rate.clamp(0, 1),
              minHeight: 6,
              backgroundColor: Colors.white,
              valueColor: const AlwaysStoppedAnimation(SboxColors.success),
            ),
          ),
          const SizedBox(height: 4),
          InkWell(
            onTap: () => showCommReaders(context, p),
            child: Text(tr('${p.ackCount}/${p.audienceCount} người đã xác nhận — xem danh sách'), style: SboxType.captionStyle(SboxColors.brand700)),
          ),
        ],
      ]),
    );
  }
}

/// Danh sách đã đọc / đã xác nhận / chưa đọc + nút nhắc.
Future<void> showCommReaders(BuildContext context, CommPost p) async {
  final api = ApiService();
  final r = await api.getCommReaders(p.id);
  if (!context.mounted) return;
  if (r['isSuccess'] != true || r['data'] is! Map) {
    commToast(context, '${r['message'] ?? 'Không tải được'}', error: true);
    return;
  }
  final d = r['data'] as Map;
  final people = (d['people'] as List? ?? []).whereType<Map>().map((e) => CommReader.fromJson(Map<String, dynamic>.from(e))).toList();
  final pending = people.where((x) => p.requireAck ? !x.ackCurrent : x.readAt == null).toList();
  final done = people.where((x) => !pending.contains(x)).toList();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      builder: (ctx, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        Text(tr(p.requireAck ? 'Xác nhận đọc' : 'Lượt đọc'), style: SboxType.titleStyle()),
        const SizedBox(height: 4),
        Text(tr('${d['readCount']} đã xem · ${d['ackCount']} đã xác nhận · ${d['audienceCount']} người nhận'), style: SboxType.smallStyle()),
        const SizedBox(height: 12),
        if (pending.isNotEmpty)
          SboxButton(
            label: 'Nhắc ${pending.length} người chưa ${p.requireAck ? 'xác nhận' : 'đọc'}',
            icon: Icons.notifications_active_outlined,
            expand: true,
            onPressed: () async {
              final rr = await api.remindCommReaders(p.id);
              if (ctx.mounted) commToast(ctx, rr['isSuccess'] == true ? 'Đã nhắc ${rr['data']} người' : '${rr['message']}', error: rr['isSuccess'] != true);
            },
          ),
        const SizedBox(height: 12),
        Text(tr('Chưa ${p.requireAck ? 'xác nhận' : 'đọc'} (${pending.length})'), style: SboxType.captionStyle(SboxColors.dangerText)),
        for (final x in pending)
          ListTile(
            dense: true,
            leading: CommAvatar(name: x.name, size: 32),
            title: Text(x.name),
            subtitle: x.readAt != null ? Text(tr('Đã xem ${commTimeAgo(x.readAt!)} trước, chưa xác nhận')) : null,
          ),
        const SizedBox(height: 8),
        Text(tr('Đã ${p.requireAck ? 'xác nhận' : 'đọc'} (${done.length})'), style: SboxType.captionStyle(SboxColors.successText)),
        for (final x in done)
          ListTile(
            dense: true,
            leading: CommAvatar(name: x.name, size: 32),
            title: Text(x.name),
            trailing: const Icon(Icons.check_circle, color: SboxColors.success, size: 18),
            subtitle: Text(commTimeAgo((p.requireAck ? x.ackAt : x.readAt) ?? DateTime.now())),
          ),
      ]),
    ),
  );
}

/// Trang chi tiết: đủ nội dung + bình luận (trả lời, @nhắc tên).
class CommPostDetailPage extends StatefulWidget {
  const CommPostDetailPage({super.key, required this.postId, required this.ctx, this.onEdit});
  final String postId;
  final CommContext ctx;
  final Future<void> Function(CommPost post)? onEdit;

  @override
  State<CommPostDetailPage> createState() => _CommPostDetailPageState();
}

class _CommPostDetailPageState extends State<CommPostDetailPage> {
  final _api = ApiService();
  final _input = TextEditingController();
  final _focus = FocusNode();
  CommPost? _post;
  List<CommComment> _comments = [];
  bool _loading = true;
  bool _sending = false;
  bool _changed = false;
  CommComment? _replyTo;
  final Map<String, String> _mentions = {}; // tên → userId

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await Future.wait([_api.getCommPost(widget.postId), _api.getCommComments(widget.postId)]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _post = r[0]['data'] is Map ? CommPost.fromJson(Map<String, dynamic>.from(r[0]['data'] as Map)) : null;
      _comments = r[1]['data'] is List
          ? (r[1]['data'] as List).whereType<Map>().map((e) => CommComment.fromJson(Map<String, dynamic>.from(e))).toList()
          : [];
    });
  }

  Future<void> _mention() async {
    final people = widget.ctx.people.where((p) => p.userId != null).toList();
    var q = '';
    final picked = await showDialog<CommPerson>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr('Nhắc tên')),
          content: SizedBox(
            width: 380,
            height: 420,
            child: Column(children: [
              TextField(autofocus: true, decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: tr('Tìm đồng nghiệp')), onChanged: (v) => set(() => q = v.trim().toLowerCase())),
              Expanded(
                child: ListView(children: [
                  for (final p in people.where((p) => q.isEmpty || p.name.toLowerCase().contains(q)).take(50))
                    ListTile(leading: CommAvatar(name: p.name, photo: p.photo, size: 32), title: Text(p.name), subtitle: p.position == null ? null : Text(p.position!), onTap: () => Navigator.pop(ctx, p)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
    if (picked == null) return;
    _mentions[picked.name] = picked.userId!;
    final t = _input.text;
    _input.text = '${t.isEmpty || t.endsWith(' ') ? t : '$t '}@${picked.name} ';
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
    _focus.requestFocus();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final mentionIds = _mentions.entries.where((e) => text.contains('@${e.key}')).map((e) => e.value).toList();
    setState(() => _sending = true);
    final r = await _api.addCommComment(widget.postId, text, parentId: _replyTo?.parentCommentId ?? _replyTo?.id, mentionUserIds: mentionIds);
    if (!mounted) return;
    setState(() => _sending = false);
    if (r['isSuccess'] == true) {
      _input.clear();
      _mentions.clear();
      _replyTo = null;
      _changed = true;
      _load();
    } else {
      commToast(context, '${r['message']}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _post;
    final roots = _comments.where((c) => c.parentCommentId == null).toList();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        backgroundColor: SboxColors.page,
        appBar: AppBar(
          backgroundColor: SboxColors.surface,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop(_changed)),
          title: Text(tr(p?.channelName ?? 'Bài viết')),
        ),
        body: _loading
            ? const SboxLoading()
            : p == null
                ? const SboxEmptyState(title: 'Không mở được bài viết', message: 'Bài đã bị xóa hoặc bạn không thuộc đối tượng nhận.')
                : Column(children: [
                    Expanded(
                      child: ListView(padding: const EdgeInsets.all(16), children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 760),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              CommPostCard(
                                post: p,
                                ctx: widget.ctx,
                                expanded: true,
                                onOpen: () {},
                                onChanged: () {
                                  _changed = true;
                                  Navigator.of(context).pop(true);
                                },
                                onEdit: widget.onEdit == null
                                    ? null
                                    : () async {
                                        await widget.onEdit!(p);
                                        _changed = true;
                                        _load();
                                      },
                              ),
                              const SizedBox(height: 16),
                              Text(tr('Bình luận (${_comments.length})'), style: SboxType.titleSmStyle()),
                              const SizedBox(height: 8),
                              if (_comments.isEmpty)
                                Text(tr(p.allowComments ? 'Hãy là người đầu tiên bình luận' : 'Bài viết đã tắt bình luận'), style: SboxType.smallStyle()),
                              for (final c in roots) ...[
                                _comment(c),
                                for (final rep in _comments.where((x) => x.parentCommentId == c.id))
                                  Padding(padding: const EdgeInsets.only(left: 44), child: _comment(rep)),
                              ],
                            ]),
                          ),
                        ),
                      ]),
                    ),
                    if (p.allowComments && p.status == CommStatus.published) _composer(),
                  ]),
      ),
    );
  }

  Widget _comment(CommComment c) {
    final spans = <TextSpan>[];
    final re = RegExp(r'@([^\s@][^@\n]{0,40}?)(?=\s|$)');
    var last = 0;
    for (final m in re.allMatches(c.content)) {
      if (m.start > last) spans.add(TextSpan(text: c.content.substring(last, m.start)));
      spans.add(TextSpan(text: m.group(0), style: const TextStyle(color: SboxColors.brand700, fontWeight: FontWeight.w600)));
      last = m.end;
    }
    if (last < c.content.length) spans.add(TextSpan(text: c.content.substring(last)));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CommAvatar(name: c.userName ?? '?', photo: c.avatar, size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: SboxColors.surface, borderRadius: SboxRadius.lgAll, border: Border.all(color: SboxColors.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.userName ?? '—', style: SboxType.smallStyle(SboxColors.text).copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text.rich(TextSpan(children: spans), style: SboxType.bodyStyle()),
              ]),
            ),
            Row(children: [
              Text(commTimeAgo(c.createdAt), style: SboxType.captionStyle()),
              TextButton(
                onPressed: () {
                  setState(() => _replyTo = c);
                  _focus.requestFocus();
                },
                child: Text(tr('Trả lời')),
              ),
              if (c.canDelete)
                TextButton(
                  onPressed: () async {
                    await _api.deleteCommComment(c.id);
                    _changed = true;
                    _load();
                  },
                  child: Text(tr('Xóa'), style: const TextStyle(color: SboxColors.slate500)),
                ),
            ]),
          ]),
        ),
      ]),
    );
  }

  Widget _composer() {
    return Material(
      color: SboxColors.surface,
      elevation: 6,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (_replyTo != null)
              Row(children: [
                Expanded(child: Text(tr('Trả lời ${_replyTo!.userName ?? ''}'), style: SboxType.captionStyle())),
                IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => setState(() => _replyTo = null)),
              ]),
            Row(children: [
              IconButton(tooltip: tr('Nhắc tên đồng nghiệp'), icon: const Icon(Icons.alternate_email_rounded), onPressed: _mention),
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  minLines: 1,
                  maxLines: 5,
                  decoration: InputDecoration(hintText: tr('Viết bình luận…'), isDense: true),
                ),
              ),
              IconButton(
                tooltip: tr('Gửi'),
                icon: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded, color: SboxColors.brand600),
                onPressed: _sending ? null : _send,
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
