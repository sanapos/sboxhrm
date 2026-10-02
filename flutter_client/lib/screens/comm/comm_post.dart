import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_tr.dart';
import '../../models/comm_v2.dart';
import '../../services/api_service.dart';
import '../../services/signalr_service.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'comm_common.dart';

/// Kết quả đóng trang chi tiết: bài đã cập nhật, bài bị xóa, hoặc cần tải lại.
const commDetailDeleted = 'deleted';

Future<void> commCopyLink(BuildContext context, CommPost p) async {
  await Clipboard.setData(ClipboardData(text: commPostLink(p.id, origin: kIsWeb ? Uri.base.origin : null)));
  if (context.mounted) commToast(context, 'Đã sao chép liên kết bài viết');
}

/// Thẻ bài trên bảng tin kiểu mạng xã hội: tác giả, kênh, nội dung «Xem thêm» tại chỗ, ảnh, tệp, bình chọn,
/// sự kiện, xác nhận đọc, cảm xúc (rê chuột để chọn), 2 bình luận mới nhất và ô bình luận ngay dưới bài.
class CommPostCard extends StatefulWidget {
  const CommPostCard({
    super.key,
    required this.post,
    required this.ctx,
    required this.onOpen,
    required this.onChanged,
    this.onRemoved,
    this.onEdit,
    this.onAuthor,
    this.onTag,
    this.onChannel,
    this.onCommentTap,
    this.expanded = false,
  });

  final CommPost post;
  final CommContext ctx;
  /// Mở trang chi tiết (đủ bình luận).
  final VoidCallback onOpen;
  /// Bài thay đổi trạng thái (duyệt / từ chối / ghim) → bảng tin tải lại.
  final VoidCallback onChanged;
  /// Bài bị xóa → bỏ khỏi danh sách tại chỗ.
  final VoidCallback? onRemoved;
  final VoidCallback? onEdit;
  final void Function(String authorId, String name)? onAuthor;
  final void Function(String tag)? onTag;
  final void Function(String channelId)? onChannel;
  /// Trang chi tiết: bấm «Bình luận» chuyển tới ô nhập bên dưới.
  final VoidCallback? onCommentTap;
  /// Trang chi tiết: đủ nội dung, không có xem trước bình luận.
  final bool expanded;

  @override
  State<CommPostCard> createState() => _CommPostCardState();
}

class _CommPostCardState extends State<CommPostCard> {
  final _api = ApiService();
  final _comment = TextEditingController();
  final _commentFocus = FocusNode();
  bool _busy = false;
  bool _more = false;
  bool _showBox = false;
  bool _sending = false;

  CommPost get p => widget.post;
  bool get _moderator => p.canModerate || widget.ctx.isManager;

  @override
  void dispose() {
    _comment.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  // ─── Cảm xúc: cập nhật ngay, lỗi thì trả lại như cũ ─────────────

  void _applyReaction(int? next) {
    final before = p.myReaction;
    if (before == next) return;
    if (before != null) p.reactions[before] = ((p.reactions[before] ?? 1) - 1).clamp(0, 1 << 30);
    if (next != null) p.reactions[next] = (p.reactions[next] ?? 0) + 1;
    if (before == null && next != null) p.reactionTotal++;
    if (before != null && next == null) p.reactionTotal--;
    p.myReaction = next;
  }

  Future<void> _react(int type) async {
    final before = p.myReaction;
    final next = before == type ? null : type;
    setState(() => _applyReaction(next));
    final r = await _api.reactCommPost(p.id, type);
    if (!mounted) return;
    if (r['isSuccess'] != true) {
      setState(() => _applyReaction(before));
      commToast(context, '${r['message'] ?? 'Không gửi được cảm xúc'}', error: true);
    } else {
      final server = r['data'] == null ? null : (r['data'] as num).toInt();
      if (server != p.myReaction) setState(() => _applyReaction(server));
    }
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
    final prevVotes = [...poll.myVotes];
    final prevCounts = {for (final o in poll.options) o.id: o.votes};
    final prevVoters = poll.totalVoters;
    final next = poll.multiple
        ? (poll.myVotes.contains(optionId) ? (poll.myVotes.toList()..remove(optionId)) : [...poll.myVotes, optionId])
        : (poll.myVotes.length == 1 && poll.myVotes.first == optionId ? <String>[] : [optionId]);
    setState(() {
      for (final o in poll.options) {
        if (poll.myVotes.contains(o.id)) o.votes--;
        if (next.contains(o.id)) o.votes++;
      }
      if (prevVotes.isEmpty && next.isNotEmpty) poll.totalVoters++;
      if (prevVotes.isNotEmpty && next.isEmpty) poll.totalVoters--;
      poll.myVotes = next;
    });
    final r = await _api.voteCommPoll(p.id, next);
    if (!mounted || r['isSuccess'] == true) return;
    setState(() {
      for (final o in poll.options) {
        o.votes = prevCounts[o.id] ?? o.votes;
      }
      poll.myVotes = prevVotes;
      poll.totalVoters = prevVoters;
    });
    commToast(context, '${r['message']}', error: true);
  }

  Future<void> _toggleSave() async {
    final before = p.mySaved;
    setState(() => p.mySaved = !before);
    final r = await _api.saveCommBookmark(p.id);
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      setState(() => p.mySaved = r['data'] == true);
      commToast(context, p.mySaved ? 'Đã lưu bài' : 'Đã bỏ lưu');
    } else {
      setState(() => p.mySaved = before);
      commToast(context, '${r['message']}', error: true);
    }
  }

  Future<void> _menu(String v) async {
    switch (v) {
      case 'edit':
        widget.onEdit?.call();
      case 'link':
        await commCopyLink(context, p);
      case 'pin':
        final r = await _api.pinCommPost(p.id, !p.isPinned);
        if (!mounted) return;
        if (r['isSuccess'] == true) {
          commToast(context, p.isPinned ? 'Đã bỏ ghim' : 'Đã ghim lên đầu bảng tin');
          widget.onChanged();
        } else {
          commToast(context, '${r['message']}', error: true);
        }
      case 'readers':
        await showCommReaders(context, p);
      case 'save':
        await _toggleSave();
      case 'approve':
      case 'reject':
        final r = await _api.approveCommPost(p.id, v == 'approve');
        if (!mounted) return;
        commToast(context, r['isSuccess'] == true ? (v == 'approve' ? 'Đã duyệt và đăng' : 'Đã từ chối') : '${r['message']}',
            error: r['isSuccess'] != true);
        widget.onChanged();
      case 'delete':
        final ok = await SboxDialogs.confirm(context,
            title: 'Xóa bài «${p.title}»?',
            message: 'Bài được chuyển vào lưu trữ, lịch sử xác nhận đọc vẫn giữ.',
            confirmLabel: 'Xóa',
            danger: true);
        if (!ok || !mounted) return;
        final r = await _api.deleteCommPost(p.id);
        if (!mounted) return;
        if (r['isSuccess'] == true) {
          commToast(context, 'Đã xóa bài');
          (widget.onRemoved ?? widget.onChanged)();
        } else {
          commToast(context, '${r['message']}', error: true);
        }
    }
  }

  // ─── Bình luận nhanh ngay dưới bài ──────────────────────────────

  void _openBox() {
    if (widget.onCommentTap != null) {
      widget.onCommentTap!();
      return;
    }
    setState(() => _showBox = true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _commentFocus.requestFocus());
  }

  Future<void> _sendComment() async {
    final text = _comment.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final r = await _api.addCommComment(p.id, text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (r['isSuccess'] != true) {
      commToast(context, '${r['message'] ?? 'Không gửi được bình luận'}', error: true);
      return;
    }
    _comment.clear();
    setState(() {
      p.comments++;
      if (r['data'] is Map) p.latestComments.add(CommComment.fromJson(Map<String, dynamic>.from(r['data'] as Map)));
    });
  }

  Future<void> _likeComment(CommComment c) async {
    final before = (c.myLiked, c.likeCount);
    setState(() {
      c.myLiked = !c.myLiked;
      c.likeCount += c.myLiked ? 1 : -1;
    });
    final r = await _api.likeCommComment(c.id);
    if (!mounted) return;
    if (r['isSuccess'] == true && r['data'] is Map) {
      final d = Map<String, dynamic>.from(r['data'] as Map);
      setState(() {
        c.myLiked = d['myLiked'] == true;
        c.likeCount = (d['likeCount'] as num? ?? c.likeCount).toInt();
      });
    } else if (r['isSuccess'] != true) {
      setState(() {
        c.myLiked = before.$1;
        c.likeCount = before.$2;
      });
    }
  }

  // ─── Giao diện ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ackPending = p.requireAck && !p.myAcked && p.status == CommStatus.published;
    final published = p.status == CommStatus.published;
    final long = !widget.expanded && commLongHtml(p.contentHtml);
    final preview = widget.expanded ? const <CommComment>[] : p.latestComments.where((c) => c.parentCommentId == null).toList();
    final shown = preview.length > 2 ? preview.sublist(preview.length - 2) : preview;
    return Container(
      decoration: BoxDecoration(
        color: SboxColors.surface,
        borderRadius: SboxRadius.lgAll,
        border: Border.all(color: ackPending ? SboxColors.danger.withValues(alpha: 0.45) : SboxColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (p.isPinned || !published) _statusBar(),
        _header(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (p.requireAck) _ackChips(),
            if (p.title.isNotEmpty)
              InkWell(
                onTap: widget.expanded ? null : widget.onOpen,
                child: Text(p.title, style: SboxType.titleStyle()),
              ),
            const SizedBox(height: 6),
            if (widget.expanded || _more || !long)
              CommHtml(html: p.contentHtml)
            else ...[
              CommHtml(html: p.contentHtml, maxLines: 6),
              InkWell(
                onTap: () => setState(() => _more = true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(tr('Xem thêm'), style: SboxType.smallStyle(SboxColors.brand700).copyWith(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ]),
        ),
        if (p.eventAt != null) Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 0), child: _eventBox()),
        if (p.allImages.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: CommImageGrid(urls: p.allImages, height: p.allImages.length == 1 ? 320 : 260),
          ),
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
            child: Wrap(spacing: 8, runSpacing: 4, children: [
              for (final t in p.tagList)
                InkWell(
                  onTap: widget.onTag == null ? null : () => widget.onTag!(t),
                  child: Text('#$t', style: SboxType.smallStyle(SboxColors.brand700).copyWith(fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
        if (p.requireAck && published) Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 0), child: _ackBox()),
        _statsRow(),
        const Divider(height: 1, indent: 12, endIndent: 12, color: SboxColors.divider),
        if (published) _actionRow() else const SizedBox(height: 8),
        if (published && (shown.isNotEmpty || _showBox) && !widget.expanded) ...[
          const Divider(height: 1, indent: 12, endIndent: 12, color: SboxColors.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (p.comments > shown.length)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 30), foregroundColor: SboxColors.slate600),
                    onPressed: widget.onOpen,
                    child: Text(tr('Xem tất cả ${p.comments} bình luận'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              for (final c in shown)
                CommCommentBubble(
                  comment: c,
                  compact: true,
                  onLike: () => _likeComment(c),
                  onReply: widget.onOpen,
                ),
              if (p.allowComments) _inlineBox(),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _statusBar() {
    final published = p.status == CommStatus.published;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: published ? SboxColors.brand50 : SboxColors.warningSoft,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(SboxRadius.lg)),
      ),
      child: Row(children: [
        Icon(published ? Icons.push_pin_rounded : Icons.info_outline, size: 14, color: published ? SboxColors.brand700 : SboxColors.warningText),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            tr(switch (p.status) {
              CommStatus.draft => 'Bản nháp — chỉ bạn thấy',
              CommStatus.pendingApproval => 'Đang chờ duyệt — chỉ bạn và người kiểm duyệt thấy',
              CommStatus.scheduled => 'Hẹn đăng ${p.scheduledAt == null ? '' : commTimeAgo(p.scheduledAt!)}',
              CommStatus.rejected => 'Bị từ chối — sửa lại rồi gửi duyệt',
              CommStatus.archived => 'Đã lưu trữ',
              _ => 'Bài được ghim',
            }),
            style: SboxType.captionStyle(published ? SboxColors.brand700 : SboxColors.warningText).copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (_moderator && p.status == CommStatus.pendingApproval) ...[
          TextButton(onPressed: () => _menu('reject'), child: Text(tr('Từ chối'))),
          const SizedBox(width: 4),
          FilledButton.tonal(onPressed: () => _menu('approve'), child: Text(tr('Duyệt'))),
        ],
      ]),
    );
  }

  Widget _header() {
    final chColor = commColor(p.channelColor);
    final author = p.authorName ?? '—';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 6, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.onAuthor == null ? null : () => widget.onAuthor!(p.authorId, author),
          child: CommAvatar(name: p.authorName ?? '?', photo: p.authorAvatar, size: 42),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InkWell(
              onTap: widget.onAuthor == null ? null : () => widget.onAuthor!(p.authorId, author),
              child: Text(author, style: SboxType.bodyStrong()),
            ),
            const SizedBox(height: 2),
            Wrap(spacing: 6, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
              if (p.channelName != null)
                InkWell(
                  borderRadius: SboxRadius.pillAll,
                  onTap: widget.onChannel == null || p.channelId == null ? null : () => widget.onChannel!(p.channelId!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(color: chColor.withValues(alpha: 0.12), borderRadius: SboxRadius.pillAll),
                    child: Text(tr(p.channelName!), style: SboxType.captionStyle(chColor).copyWith(fontWeight: FontWeight.w600)),
                  ),
                ),
              Tooltip(
                message: '${p.when.day}/${p.when.month}/${p.when.year} ${p.when.hour.toString().padLeft(2, '0')}:${p.when.minute.toString().padLeft(2, '0')}',
                child: Text(commTimeAgo(p.when), style: SboxType.captionStyle()),
              ),
              if (p.audience != null && !p.audience!.isEveryone)
                Tooltip(message: tr('Gửi cho một nhóm người'), child: const Icon(Icons.group_outlined, size: 14, color: SboxColors.slate400)),
              if (p.isAiGenerated)
                Tooltip(message: tr('Soạn với trợ lý AI'), child: const Icon(Icons.auto_awesome, size: 13, color: SboxColors.violet)),
            ]),
          ]),
        ),
        if (p.urgent) const Padding(padding: EdgeInsets.only(right: 2, top: 4), child: SboxStatusChip(label: 'Quan trọng', tone: SboxTone.danger)),
        PopupMenuButton<String>(
          tooltip: tr('Thêm'),
          icon: const Icon(Icons.more_horiz_rounded),
          onSelected: _menu,
          itemBuilder: (_) => [
            _item('save', p.mySaved ? Icons.bookmark : Icons.bookmark_border, p.mySaved ? 'Bỏ lưu' : 'Lưu bài'),
            if (p.status == CommStatus.published) _item('link', Icons.link_rounded, 'Sao chép liên kết'),
            if (p.canEdit && widget.onEdit != null) _item('edit', Icons.edit_outlined, 'Sửa bài'),
            if (_moderator && p.status == CommStatus.published) _item('pin', Icons.push_pin_outlined, p.isPinned ? 'Bỏ ghim' : 'Ghim lên đầu'),
            if (p.canEdit && p.status == CommStatus.published) _item('readers', Icons.fact_check_outlined, 'Ai đã đọc'),
            if (_moderator && p.status == CommStatus.pendingApproval) ...[
              _item('approve', Icons.check_circle_outline, 'Duyệt và đăng'),
              _item('reject', Icons.block_outlined, 'Từ chối'),
            ],
            if (p.canEdit) _item('delete', Icons.delete_outline, 'Xóa bài', danger: true),
          ],
        ),
      ]),
    );
  }

  PopupMenuItem<String> _item(String v, IconData icon, String label, {bool danger = false}) => PopupMenuItem(
        value: v,
        child: Row(children: [
          Icon(icon, size: 19, color: danger ? SboxColors.danger : SboxColors.slate600),
          const SizedBox(width: 10),
          Text(tr(label), style: TextStyle(color: danger ? SboxColors.danger : null)),
        ]),
      );

  Widget _ackChips() => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SboxStatusChip(
              label: p.myAcked ? 'Bạn đã xác nhận' : 'Bắt buộc đọc',
              tone: p.myAcked ? SboxTone.success : SboxTone.danger,
              icon: Icons.verified_user_outlined),
          if (p.version > 1) SboxStatusChip(label: 'Bản ${p.version}', tone: SboxTone.violet),
          if (p.ackDeadline != null && !p.myAcked)
            Text(tr('hạn ${p.ackDeadline!.day}/${p.ackDeadline!.month}'), style: SboxType.captionStyle(SboxColors.dangerText)),
        ]),
      );

  Widget _statsRow() {
    final top = commReactions.where((r) => (p.reactions[r.$1] ?? 0) > 0).toList()
      ..sort((a, b) => (p.reactions[b.$1] ?? 0).compareTo(p.reactions[a.$1] ?? 0));
    final hasAny = p.reactionTotal > 0 || p.comments > 0 || p.views > 0;
    if (!hasAny) return const SizedBox(height: 10);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(children: [
        if (p.reactionTotal > 0)
          InkWell(
            borderRadius: SboxRadius.pillAll,
            onTap: () => showCommReactors(context, p),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(top.take(3).map((r) => r.$2).join(), style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 4),
                Text(_reactionLabel(), style: SboxType.captionStyle()),
              ]),
            ),
          ),
        const Spacer(),
        if (p.comments > 0)
          InkWell(
            onTap: widget.expanded ? widget.onCommentTap : widget.onOpen,
            child: Text(tr('${p.comments} bình luận'), style: SboxType.captionStyle()),
          ),
        if (p.views > 0) ...[const SizedBox(width: 10), Text(tr('${p.views} lượt xem'), style: SboxType.captionStyle())],
      ]),
    );
  }

  /// «Bạn và 11 người khác» kiểu mạng xã hội.
  String _reactionLabel() {
    if (p.myReaction == null) return '${p.reactionTotal}';
    final others = p.reactionTotal - 1;
    return others <= 0 ? tr('Bạn') : tr('Bạn và $others người khác');
  }

  Widget _actionRow() {
    Widget btn(IconData icon, String label, VoidCallback? onTap, {Color? color}) => Expanded(
          child: TextButton.icon(
            onPressed: onTap,
            icon: Icon(icon, size: 19),
            label: Text(tr(label), overflow: TextOverflow.ellipsis),
            style: TextButton.styleFrom(foregroundColor: color ?? SboxColors.slate600, minimumSize: const Size(0, 42)),
          ),
        );
    Widget icon(IconData i, String tip, VoidCallback onTap, {Color? color}) =>
        IconButton(tooltip: tr(tip), icon: Icon(i, size: 20), color: color ?? SboxColors.slate600, onPressed: onTap);
    return LayoutBuilder(builder: (context, c) {
      // Điện thoại: Thích + Bình luận có chữ, Lưu / Liên kết chỉ biểu tượng.
      final narrow = c.maxWidth < 460;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(children: [
          Expanded(child: CommReactionButton(mine: p.myReaction, onReact: _react)),
          btn(Icons.chat_bubble_outline_rounded, 'Bình luận', p.allowComments ? _openBox : null),
          if (narrow) ...[
            icon(p.mySaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, p.mySaved ? 'Bỏ lưu' : 'Lưu bài', _toggleSave,
                color: p.mySaved ? SboxColors.brand700 : null),
            icon(Icons.link_rounded, 'Sao chép liên kết', () => commCopyLink(context, p)),
          ] else ...[
            btn(p.mySaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, p.mySaved ? 'Đã lưu' : 'Lưu', _toggleSave,
                color: p.mySaved ? SboxColors.brand700 : null),
            btn(Icons.link_rounded, 'Liên kết', () => commCopyLink(context, p)),
          ],
        ]),
      );
    });
  }

  Widget _inlineBox() {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        CommAvatar(name: widget.ctx.myName.isEmpty ? 'Tôi' : widget.ctx.myName, size: 30),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _comment,
            focusNode: _commentFocus,
            minLines: 1,
            maxLines: 4,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _sendComment(),
            decoration: InputDecoration(
              isDense: true,
              hintText: tr('Viết bình luận… (Enter để gửi)'),
              filled: true,
              fillColor: SboxColors.slate50,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: SboxColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: SboxColors.border)),
              suffixIcon: IconButton(
                tooltip: tr('Gửi'),
                icon: _sending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded, size: 18, color: SboxColors.brand600),
                onPressed: _sending ? null : _sendComment,
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _eventBox() {
    final d = p.eventAt!;
    const months = ['', 'Th1', 'Th2', 'Th3', 'Th4', 'Th5', 'Th6', 'Th7', 'Th8', 'Th9', 'Th10', 'Th11', 'Th12'];
    final past = d.isBefore(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: (past ? SboxColors.slate100 : SboxColors.warningSoft).withValues(alpha: 0.6), borderRadius: SboxRadius.mdAll),
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
            Text(tr('${past ? 'Đã diễn ra' : 'Sự kiện'} · ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'),
                style: SboxType.bodyStrong()),
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
              onTap: poll.closed || p.status != CommStatus.published ? null : () => _vote(o.id),
              child: Stack(children: [
                if (voted || poll.closed)
                  Positioned.fill(
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: total == 0 ? 0 : (o.votes / total).clamp(0.0, 1.0),
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
                    if (voted || poll.closed)
                      Text('${total == 0 ? 0 : (o.votes * 100 / total).round()}% · ${o.votes}', style: SboxType.captionStyle()),
                  ]),
                ),
              ]),
            ),
          ),
        Text(
          tr('${poll.totalVoters} người đã bình chọn${poll.multiple ? ' · chọn nhiều' : ''}${poll.closed ? ' · đã đóng' : voted && !poll.multiple ? ' · bấm lại để bỏ chọn' : ''}'),
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
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, alignment: WrapAlignment.spaceBetween, children: [
          Text(
            tr(p.myAcked ? 'Bạn đã đọc và xác nhận văn bản này' : 'Vui lòng đọc kỹ và xác nhận đã hiểu'),
            style: SboxType.smallStyle(p.myAcked ? SboxColors.successText : SboxColors.dangerText).copyWith(fontWeight: FontWeight.w600),
          ),
          if (!p.myAcked)
            SboxButton(label: 'Tôi đã đọc và cam kết', icon: Icons.check_rounded, size: SboxButtonSize.sm, loading: _busy, onPressed: _busy ? null : _ack),
        ]),
        if (p.canEdit || _moderator) ...[
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

/// Nút «Thích»: bấm = thích / bỏ; rê chuột (máy tính) hoặc nhấn giữ (điện thoại) để chọn cảm xúc khác.
class CommReactionButton extends StatefulWidget {
  const CommReactionButton({super.key, required this.mine, required this.onReact});
  final int? mine;
  final void Function(int type) onReact;

  @override
  State<CommReactionButton> createState() => _CommReactionButtonState();
}

class _CommReactionButtonState extends State<CommReactionButton> {
  final _link = LayerLink();
  final _portal = OverlayPortalController();
  Timer? _showT;
  Timer? _hideT;
  int? _hover;

  @override
  void dispose() {
    _showT?.cancel();
    _hideT?.cancel();
    super.dispose();
  }

  void _enter() {
    _hideT?.cancel();
    _showT?.cancel();
    _showT = Timer(const Duration(milliseconds: 450), () {
      if (mounted && !_portal.isShowing) _portal.show();
    });
  }

  void _exit() {
    _showT?.cancel();
    _hideT?.cancel();
    _hideT = Timer(const Duration(milliseconds: 350), () {
      if (mounted && _portal.isShowing) _portal.hide();
    });
  }

  void _pick(int type) {
    _showT?.cancel();
    _hideT?.cancel();
    if (_portal.isShowing) _portal.hide();
    widget.onReact(type);
  }

  @override
  Widget build(BuildContext context) {
    final mine = commReactions.where((r) => r.$1 == widget.mine).firstOrNull;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (_) => Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.topLeft,
            followerAnchor: Alignment.bottomLeft,
            offset: const Offset(4, -4),
            child: TapRegion(
              onTapOutside: (_) => _portal.hide(),
              child: MouseRegion(
                onEnter: (_) => _hideT?.cancel(),
                onExit: (_) => _exit(),
                child: Material(
                  elevation: 8,
                  color: SboxColors.surface,
                  shadowColor: Colors.black26,
                  borderRadius: BorderRadius.circular(28),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      for (final r in commReactions)
                        Tooltip(
                          message: tr(r.$3),
                          child: MouseRegion(
                            onEnter: (_) => setState(() => _hover = r.$1),
                            onExit: (_) => setState(() => _hover = null),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => _pick(r.$1),
                              child: AnimatedScale(
                                scale: _hover == r.$1 ? 1.35 : 1,
                                duration: const Duration(milliseconds: 120),
                                child: Padding(padding: const EdgeInsets.all(6), child: Text(r.$2, style: const TextStyle(fontSize: 26))),
                              ),
                            ),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
        child: MouseRegion(
          onEnter: (_) => _enter(),
          onExit: (_) => _exit(),
          child: TextButton.icon(
            onPressed: () => _pick(widget.mine ?? 0),
            onLongPress: () {
              _showT?.cancel();
              _portal.show();
            },
            icon: mine == null ? const Icon(Icons.thumb_up_outlined, size: 19) : Text(mine.$2, style: const TextStyle(fontSize: 17)),
            label: Text(tr(mine?.$3 ?? 'Thích'), overflow: TextOverflow.ellipsis),
            style: TextButton.styleFrom(
              foregroundColor: mine == null ? SboxColors.slate600 : SboxColors.brand700,
              minimumSize: const Size(0, 42),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bong bóng bình luận: tên, nội dung (tô @nhắc tên), thời gian, thích, trả lời, sửa / xóa.
class CommCommentBubble extends StatelessWidget {
  const CommCommentBubble({
    super.key,
    required this.comment,
    this.onLike,
    this.onReply,
    this.onEdit,
    this.onDelete,
    this.compact = false,
  });

  final CommComment comment;
  final VoidCallback? onLike;
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = comment;
    final spans = <TextSpan>[];
    final re = RegExp(r'@([^\s@][^@\n]{0,40}?)(?=\s|$)');
    var last = 0;
    for (final m in re.allMatches(c.content)) {
      if (m.start > last) spans.add(TextSpan(text: c.content.substring(last, m.start)));
      spans.add(TextSpan(text: m.group(0), style: const TextStyle(color: SboxColors.brand700, fontWeight: FontWeight.w600)));
      last = m.end;
    }
    if (last < c.content.length) spans.add(TextSpan(text: c.content.substring(last)));
    Widget action(String label, VoidCallback? onTap, {Color? color, FontWeight weight = FontWeight.w600}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(tr(label), style: SboxType.captionStyle(color ?? SboxColors.slate600).copyWith(fontWeight: weight)),
          ),
        );
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 6 : 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CommAvatar(name: c.userName ?? '?', photo: c.avatar, size: compact ? 30 : 34),
        const SizedBox(width: 8),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
                decoration: BoxDecoration(color: SboxColors.slate100, borderRadius: BorderRadius.circular(16)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.userName ?? '—', style: SboxType.smallStyle(SboxColors.text).copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 1),
                  Text.rich(TextSpan(children: spans), style: SboxType.bodyStyle()),
                ]),
              ),
              if (c.likeCount > 0)
                Positioned(
                  right: -6,
                  bottom: -8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: SboxColors.surface,
                      borderRadius: SboxRadius.pillAll,
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3)],
                    ),
                    child: Text('👍 ${c.likeCount}', style: const TextStyle(fontSize: 11)),
                  ),
                ),
            ]),
            Padding(
              padding: const EdgeInsets.only(left: 6, top: 2),
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(commTimeAgo(c.createdAt), style: SboxType.captionStyle()),
                if (c.edited) Text(tr(' · đã sửa'), style: SboxType.captionStyle()),
                if (onLike != null)
                  action(c.myLiked ? 'Đã thích' : 'Thích', onLike, color: c.myLiked ? SboxColors.brand700 : null),
                if (onReply != null) action('Trả lời', onReply),
                if (onEdit != null && c.canEdit) action('Sửa', onEdit, weight: FontWeight.w500),
                if (onDelete != null && c.canDelete) action('Xóa', onDelete, color: SboxColors.slate500, weight: FontWeight.w500),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Ai đã bày tỏ cảm xúc — chia tab theo loại.
Future<void> showCommReactors(BuildContext context, CommPost p) async {
  final api = ApiService();
  final r = await api.getCommReactors(p.id);
  if (!context.mounted) return;
  if (r['isSuccess'] != true || r['data'] is! List) {
    commToast(context, '${r['message'] ?? 'Không tải được'}', error: true);
    return;
  }
  final all = (r['data'] as List).whereType<Map>().map((e) => CommReactor.fromJson(Map<String, dynamic>.from(e))).toList();
  final types = commReactions.where((t) => all.any((x) => x.type == t.$1)).toList();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 520),
    builder: (ctx) => DefaultTabController(
      length: types.length + 1,
      child: SizedBox(
        height: MediaQuery.sizeOf(ctx).height * 0.6,
        child: Column(children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: tr('Tất cả ${all.length}')),
              for (final t in types) Tab(text: '${t.$2} ${all.where((x) => x.type == t.$1).length}'),
            ],
          ),
          Expanded(
            child: TabBarView(children: [
              for (final list in [all, for (final t in types) all.where((x) => x.type == t.$1).toList()])
                ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
                  for (final x in list)
                    ListTile(
                      leading: Stack(clipBehavior: Clip.none, children: [
                        CommAvatar(name: x.name, photo: x.avatar, size: 36),
                        Positioned(
                          right: -4,
                          bottom: -4,
                          child: Text(commReactions.firstWhere((t) => t.$1 == x.type, orElse: () => commReactions.first).$2,
                              style: const TextStyle(fontSize: 14)),
                        ),
                      ]),
                      title: Text(x.name),
                    ),
                ]),
            ]),
          ),
        ]),
      ),
    ),
  );
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

/// Trang chi tiết: đủ nội dung + bình luận (thích, sửa, trả lời 2 cấp, @nhắc tên gợi ý khi gõ).
/// Đóng trang trả về bài đã cập nhật để bảng tin thay tại chỗ (hoặc [commDetailDeleted]).
class CommPostDetailPage extends StatefulWidget {
  const CommPostDetailPage({super.key, required this.postId, required this.ctx, this.onEdit, this.focusComment = false});
  final String postId;
  final CommContext ctx;
  final Future<void> Function(CommPost post)? onEdit;
  /// Mở xong thì đặt con trỏ vào ô bình luận.
  final bool focusComment;

  @override
  State<CommPostDetailPage> createState() => _CommPostDetailPageState();
}

class _CommPostDetailPageState extends State<CommPostDetailPage> {
  final _api = ApiService();
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  CommPost? _post;
  List<CommComment> _comments = [];
  bool _loading = true;
  bool _sending = false;
  Object? _result;
  CommComment? _replyTo;
  final Map<String, String> _mentions = {}; // tên → userId
  final Set<String> _openThreads = {};
  List<CommPerson> _suggest = const [];
  StreamSubscription<Map<String, dynamic>>? _rt;
  bool _firstLoad = true;

  @override
  void initState() {
    super.initState();
    _input.addListener(_onTyping);
    _load();
    _rt = SignalRService().onCommFeedEvent.listen((e) {
      final id = '${e['postId'] ?? e['id'] ?? ''}';
      if (id != widget.postId || '${e['by']}' == widget.ctx.myUserId) return;
      if (e['event'] == 'post' && e['action'] == 'deleted') {
        if (mounted) Navigator.of(context).pop(commDetailDeleted);
        return;
      }
      _load();
    });
  }

  @override
  void dispose() {
    _rt?.cancel();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Chỉ lần mở đầu tính là đã xem; tải lại sau đó không cộng lượt xem.
    final markRead = _firstLoad;
    _firstLoad = false;
    final r = await Future.wait([_api.getCommPost(widget.postId, markRead: markRead), _api.getCommComments(widget.postId)]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r[0]['data'] is Map) _post = CommPost.fromJson(Map<String, dynamic>.from(r[0]['data'] as Map));
      if (r[1]['data'] is List) {
        _comments = (r[1]['data'] as List).whereType<Map>().map((e) => CommComment.fromJson(Map<String, dynamic>.from(e))).toList();
      }
      _post?.myRead = true;
    });
    if (widget.focusComment && markRead) WidgetsBinding.instance.addPostFrameCallback((_) => _focusComposer());
  }

  void _focusComposer() {
    _focus.requestFocus();
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  /// Trả bài về bảng tin với số bình luận + 2 bình luận mới nhất đã cập nhật.
  void _close() {
    final p = _post;
    if (_result == null && p != null) {
      p.comments = _comments.length;
      final roots = _comments.where((c) => c.parentCommentId == null).toList();
      p.latestComments
        ..clear()
        ..addAll(roots.length > 2 ? roots.sublist(roots.length - 2) : roots);
      _result = p;
    }
    Navigator.of(context).pop(_result);
  }

  // ─── @nhắc tên: gõ «@ten» hiện gợi ý ───────────────────────────

  (int, String)? _mentionQuery() {
    final sel = _input.selection;
    if (!sel.isValid || !sel.isCollapsed) return null;
    final before = _input.text.substring(0, sel.baseOffset);
    final at = before.lastIndexOf('@');
    if (at < 0 || (at > 0 && !RegExp(r'\s').hasMatch(before[at - 1]))) return null;
    final q = before.substring(at + 1);
    if (q.length > 30 || q.contains('\n')) return null;
    return (at, q);
  }

  void _onTyping() {
    final m = _mentionQuery();
    final q = m?.$2.toLowerCase().trim();
    final list = m == null
        ? const <CommPerson>[]
        : widget.ctx.people.where((p) => p.userId != null && (q!.isEmpty || p.name.toLowerCase().contains(q))).take(6).toList();
    if (list.length != _suggest.length || !list.every(_suggest.contains)) setState(() => _suggest = list);
  }

  void _insertMention(CommPerson p) {
    final m = _mentionQuery();
    if (m == null) return;
    final sel = _input.selection.baseOffset;
    final text = _input.text;
    final next = '${text.substring(0, m.$1)}@${p.name} ${text.substring(sel)}';
    _mentions[p.name] = p.userId!;
    _input.value = TextEditingValue(text: next, selection: TextSelection.collapsed(offset: m.$1 + p.name.length + 2));
    setState(() => _suggest = const []);
    _focus.requestFocus();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final mentionIds = _mentions.entries.where((e) => text.contains('@${e.key}')).map((e) => e.value).toList();
    final parent = _replyTo?.parentCommentId ?? _replyTo?.id;
    setState(() => _sending = true);
    final r = await _api.addCommComment(widget.postId, text, parentId: parent, mentionUserIds: mentionIds);
    if (!mounted) return;
    setState(() => _sending = false);
    if (r['isSuccess'] != true) {
      commToast(context, '${r['message']}', error: true);
      return;
    }
    _input.clear();
    _mentions.clear();
    setState(() {
      if (r['data'] is Map) _comments.add(CommComment.fromJson(Map<String, dynamic>.from(r['data'] as Map)));
      if (parent != null) {
        _openThreads.add(parent);
        for (final c in _comments.where((c) => c.id == parent)) {
          c.replyCount++;
        }
      }
      _replyTo = null;
      _post?.comments = _comments.length;
    });
  }

  Future<void> _like(CommComment c) async {
    final before = (c.myLiked, c.likeCount);
    setState(() {
      c.myLiked = !c.myLiked;
      c.likeCount += c.myLiked ? 1 : -1;
    });
    final r = await _api.likeCommComment(c.id);
    if (!mounted || r['isSuccess'] == true) return;
    setState(() {
      c.myLiked = before.$1;
      c.likeCount = before.$2;
    });
  }

  Future<void> _edit(CommComment c) async {
    final ctrl = TextEditingController(text: c.content);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Sửa bình luận')),
        content: SizedBox(
          width: 440,
          child: TextField(controller: ctrl, autofocus: true, minLines: 2, maxLines: 6, maxLength: 2000),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(tr('Lưu'))),
        ],
      ),
    );
    ctrl.dispose();
    if (next == null || next.isEmpty || next == c.content || !mounted) return;
    final before = c.content;
    setState(() {
      c.content = next;
      c.edited = true;
    });
    final r = await _api.editCommComment(c.id, next);
    if (!mounted || r['isSuccess'] == true) return;
    setState(() => c.content = before);
    commToast(context, '${r['message']}', error: true);
  }

  Future<void> _delete(CommComment c) async {
    final replies = _comments.where((x) => x.parentCommentId == c.id).length;
    final ok = await SboxDialogs.confirm(context,
        title: 'Xóa bình luận?',
        message: replies > 0 ? 'Các $replies phản hồi bên dưới cũng bị xóa.' : 'Không khôi phục được sau khi xóa.',
        confirmLabel: 'Xóa',
        danger: true);
    if (!ok || !mounted) return;
    final r = await _api.deleteCommComment(c.id);
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      setState(() {
        _comments.removeWhere((x) => x.id == c.id || x.parentCommentId == c.id);
        if (c.parentCommentId != null) {
          for (final p in _comments.where((p) => p.id == c.parentCommentId)) {
            p.replyCount = (p.replyCount - 1).clamp(0, 1 << 30);
          }
        }
        _post?.comments = _comments.length;
      });
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
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: SboxColors.page,
        appBar: AppBar(
          backgroundColor: SboxColors.surface,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _close),
          title: Text(tr(p?.channelName ?? 'Bài viết')),
          actions: [
            if (p != null && p.status == CommStatus.published)
              IconButton(tooltip: tr('Sao chép liên kết'), icon: const Icon(Icons.link_rounded), onPressed: () => commCopyLink(context, p)),
          ],
        ),
        body: _loading
            ? const SboxLoading()
            : p == null
                ? const SboxEmptyState(title: 'Không mở được bài viết', message: 'Bài đã bị xóa hoặc bạn không thuộc đối tượng nhận.')
                : Column(children: [
                    Expanded(
                      child: ListView(controller: _scroll, padding: const EdgeInsets.all(16), children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 760),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              CommPostCard(
                                post: p,
                                ctx: widget.ctx,
                                expanded: true,
                                onOpen: () {},
                                onCommentTap: _focusComposer,
                                onChanged: () {
                                  _result = true;
                                  _load();
                                },
                                onRemoved: () {
                                  _result = commDetailDeleted;
                                  Navigator.of(context).pop(commDetailDeleted);
                                },
                                onEdit: widget.onEdit == null
                                    ? null
                                    : () async {
                                        await widget.onEdit!(p);
                                        _result = true;
                                        _load();
                                      },
                              ),
                              const SizedBox(height: 16),
                              Text(tr('Bình luận (${_comments.length})'), style: SboxType.titleSmStyle()),
                              const SizedBox(height: 10),
                              if (_comments.isEmpty)
                                Text(tr(p.allowComments ? 'Hãy là người đầu tiên bình luận' : 'Bài viết đã tắt bình luận'), style: SboxType.smallStyle()),
                              for (final c in roots) ..._thread(c),
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

  List<Widget> _thread(CommComment c) {
    final replies = _comments.where((x) => x.parentCommentId == c.id).toList();
    final open = _openThreads.contains(c.id) || replies.length <= 1;
    void reply(CommComment target) {
      setState(() {
        _replyTo = target;
        _openThreads.add(c.id);
      });
      final name = target.userName;
      if (name != null && name.isNotEmpty && target.userId != widget.ctx.myUserId && !_input.text.contains('@$name')) {
        _mentions[name] = target.userId;
        _input.text = '@$name ${_input.text}';
        _input.selection = TextSelection.collapsed(offset: _input.text.length);
      }
      _focus.requestFocus();
    }

    Widget bubble(CommComment x) => CommCommentBubble(
          comment: x,
          onLike: () => _like(x),
          onReply: () => reply(x),
          onEdit: () => _edit(x),
          onDelete: () => _delete(x),
        );
    return [
      bubble(c),
      if (replies.isNotEmpty && !open)
        Padding(
          padding: const EdgeInsets.only(left: 44, bottom: 8),
          child: InkWell(
            onTap: () => setState(() => _openThreads.add(c.id)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.subdirectory_arrow_right_rounded, size: 18, color: SboxColors.slate500),
              const SizedBox(width: 4),
              Text(tr('Xem ${replies.length} phản hồi'), style: SboxType.smallStyle(SboxColors.slate600).copyWith(fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      if (open)
        for (final rep in replies) Padding(padding: const EdgeInsets.only(left: 44), child: bubble(rep)),
    ];
  }

  Widget _composer() {
    return Material(
      color: SboxColors.surface,
      elevation: 6,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_suggest.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(color: SboxColors.surface, borderRadius: SboxRadius.mdAll, border: Border.all(color: SboxColors.border)),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final s in _suggest)
                        ListTile(
                          dense: true,
                          leading: CommAvatar(name: s.name, photo: s.photo, size: 28),
                          title: Text(s.name),
                          subtitle: s.position == null ? null : Text(s.position!),
                          onTap: () => _insertMention(s),
                        ),
                    ]),
                  ),
                if (_replyTo != null)
                  Row(children: [
                    const Icon(Icons.reply_rounded, size: 16, color: SboxColors.slate500),
                    const SizedBox(width: 4),
                    Expanded(child: Text(tr('Đang trả lời ${_replyTo!.userName ?? ''}'), style: SboxType.captionStyle())),
                    IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => setState(() => _replyTo = null)),
                  ]),
                Row(children: [
                  CommAvatar(name: widget.ctx.myName.isEmpty ? 'Tôi' : widget.ctx.myName, size: 32),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _suggest.isNotEmpty ? _insertMention(_suggest.first) : _send(),
                      decoration: InputDecoration(
                        hintText: tr('Viết bình luận… gõ @ để nhắc tên'),
                        isDense: true,
                        filled: true,
                        fillColor: SboxColors.slate50,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: SboxColors.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: SboxColors.border)),
                      ),
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
        ),
      ),
    );
  }
}
