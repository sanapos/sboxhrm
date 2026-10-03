import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../models/comm_v2.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../services/signalr_service.dart';
import '../../utils/navigation_notifier.dart';
import '../../utils/store_role_helper.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'comm_common.dart';
import 'comm_editor.dart';
import 'comm_post.dart';

/// Truyền thông v2 — mạng xã hội nội bộ.
class CommHubScreen extends StatefulWidget {
  const CommHubScreen({super.key, this.debugContext});

  /// Kiểm thử: bỏ qua đăng nhập, dùng ngữ cảnh dựng sẵn.
  final CommContext? debugContext;

  @override
  State<CommHubScreen> createState() => _CommHubScreenState();
}

const _filters = <(String, String, IconData)>[
  ('all', 'Tất cả', Icons.dynamic_feed_outlined),
  ('required', 'Bắt buộc đọc', Icons.verified_user_outlined),
  ('events', 'Sự kiện', Icons.event_outlined),
  ('polls', 'Bình chọn', Icons.poll_outlined),
  ('files', 'Tài liệu', Icons.folder_open_outlined),
  ('saved', 'Đã lưu', Icons.bookmark_border_rounded),
  ('mine', 'Bài của tôi', Icons.person_outline),
];

class _CommHubScreenState extends State<CommHubScreen> {
  final _api = ApiService();
  final _search = TextEditingController();
  final _scroll = ScrollController();
  CommContext? _ctx;
  String? _channelId;
  String _filter = 'all';
  final List<CommPost> _posts = [];
  int _total = 0;
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  CommSidebar? _sidebar;
  Timer? _debounce;
  int _seq = 0;
  // Lọc theo người đăng / thẻ (bấm tên tác giả hoặc #thẻ trên bài).
  String? _authorId;
  String? _authorName;
  String? _tag;
  // Realtime: bài mới của người khác chờ hiện ở banner «N bài mới».
  final Set<String> _incoming = {};
  final Map<String, Timer> _refreshTimers = {};
  StreamSubscription<Map<String, dynamic>>? _rt;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    NavigationNotifier.notificationHighlightId.addListener(_consumeHighlight);
    _rt = SignalRService().onCommFeedEvent.listen(_onRealtime);
    _init();
  }

  @override
  void dispose() {
    _rt?.cancel();
    for (final t in _refreshTimers.values) {
      t.cancel();
    }
    NavigationNotifier.notificationHighlightId.removeListener(_consumeHighlight);
    _scroll.dispose();
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600 && !_loadingMore && _posts.length < _total) {
      _loadMore();
    }
  }

  Future<void> _init() async {
    if (widget.debugContext != null) {
      _ctx = widget.debugContext;
    } else {
      final auth = context.read<AuthProvider>();
      final perms = context.read<PermissionProvider>();
      final roleManager = StoreRoleHelper.isManagerOrAbove(auth.userRole);
      // Kiểm duyệt theo bảng quyền: Truyền thông › Duyệt hoặc Sửa.
      final moderator = perms.canApprove('Communication') || perms.canEdit('Communication');
      final isManager = moderator || roleManager;
      final results = await Future.wait([
        _api.getCommChannels(),
        _api.getEmployeesForSelect(pageSize: 1000).then((v) => {'data': v}),
        if (isManager) _api.getBranchesForSelect(),
        if (isManager) _api.getDepartmentsForSelect(),
      ]);
      List<({String id, String name})> named(Map<String, dynamic>? r) {
        final d = r?['data'];
        final list = d is Map ? (d['items'] ?? d['data']) : d;
        return list is List
            ? list.whereType<Map>().map((e) => (id: '${e['id']}', name: '${e['name'] ?? e['branchName'] ?? e['departmentName'] ?? ''}')).toList()
            : const [];
      }

      final emps = (results[1]['data'] as List? ?? const []).whereType<Map>().map((e) {
        final m = Map<String, dynamic>.from(e);
        final name = '${m['lastName'] ?? ''} ${m['firstName'] ?? ''}'.trim();
        return CommPerson(
          employeeId: '${m['id']}',
          userId: m['applicationUserId']?.toString(),
          name: name.isEmpty ? '${m['fullName'] ?? m['employeeCode'] ?? ''}' : name,
          branchId: m['branchId']?.toString(),
          departmentId: m['departmentId']?.toString(),
          position: m['position']?.toString(),
          photo: m['photoUrl']?.toString(),
        );
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      final u = auth.user;
      _ctx = CommContext(
        isManager: moderator,
        canManageChannels: roleManager,
        channels: _parseChannels(results[0]),
        people: emps,
        branches: isManager ? named(results[2]) : const [],
        departments: isManager ? named(results[3]) : const [],
        myName: u?.fullName ?? '',
        myUserId: u?.id,
      );
    }
    if (!mounted) return;
    setState(() {});
    await _reload();
    _consumeHighlight();
  }

  List<CommChannel> _parseChannels(Map<String, dynamic> r) => r['data'] is List
      ? (r['data'] as List).whereType<Map>().map((e) => CommChannel.fromJson(Map<String, dynamic>.from(e))).toList()
      : [];

  void _consumeHighlight() {
    final id = NavigationNotifier.notificationHighlightId.value;
    if (_ctx == null || id == null || id.isEmpty || NavigationNotifier.currentModuleCode.value != 'Communication') return;
    NavigationNotifier.notificationHighlightId.value = null;
    _open(id);
  }

  Future<void> _reload() async {
    final seq = ++_seq;
    setState(() => _loading = true);
    final r = await Future.wait([
      _api.getCommFeed(channelId: _channelId, filter: _filter, search: _search.text.trim(), page: 1, authorId: _authorId, tag: _tag),
      _api.getCommSidebar(),
      if (widget.debugContext == null) _api.getCommChannels(),
    ]);
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      _page = 1;
      _incoming.clear();
      _posts
        ..clear()
        ..addAll(_items(r[0]));
      _total = r[0]['data'] is Map ? ((r[0]['data'] as Map)['totalCount'] as num? ?? 0).toInt() : 0;
      if (r[1]['data'] is Map) _sidebar = CommSidebar.fromJson(Map<String, dynamic>.from(r[1]['data'] as Map));
      if (r.length > 2 && r[2]['data'] is List) _ctx!.channels = _parseChannels(r[2]);
    });
  }

  List<CommPost> _items(Map<String, dynamic> r) {
    final d = r['data'];
    final list = d is Map ? d['items'] : null;
    return list is List ? list.whereType<Map>().map((e) => CommPost.fromJson(Map<String, dynamic>.from(e))).toList() : [];
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    final r = await _api.getCommFeed(
        channelId: _channelId, filter: _filter, search: _search.text.trim(), page: _page + 1, authorId: _authorId, tag: _tag);
    if (!mounted) return;
    setState(() {
      _loadingMore = false;
      final more = _items(r);
      if (more.isNotEmpty) {
        _page++;
        _posts.addAll(more.where((m) => !_posts.any((p) => p.id == m.id)));
      } else {
        _total = _posts.length;
      }
    });
  }

  /// Sự kiện realtime: bài mới → banner; bài sửa / bình luận / cảm xúc → tải lại riêng bài đó.
  void _onRealtime(Map<String, dynamic> e) {
    if (!mounted || _ctx == null) return;
    if ('${e['by']}' == _ctx!.myUserId) return; // thao tác của chính mình đã cập nhật tại chỗ
    final id = '${e['postId'] ?? e['id'] ?? ''}';
    if (id.isEmpty) return;
    final idx = _posts.indexWhere((p) => p.id == id);
    if (e['event'] == 'post') {
      switch (e['action']) {
        case 'created':
          if (idx < 0) setState(() => _incoming.add(id));
          if (idx >= 0) _refreshPost(id);
        case 'deleted':
        case 'rejected':
          if (idx >= 0) setState(() => _posts.removeAt(idx));
        default:
          if (idx >= 0) _refreshPost(id);
      }
      return;
    }
    if (idx >= 0) _refreshPost(id);
  }

  /// Tải lại một bài (gộp nhiều sự kiện liên tiếp), không tính lượt xem.
  void _refreshPost(String id) {
    _refreshTimers[id]?.cancel();
    _refreshTimers[id] = Timer(const Duration(milliseconds: 600), () async {
      _refreshTimers.remove(id);
      final r = await _api.getCommPost(id, markRead: false);
      if (!mounted) return;
      final i = _posts.indexWhere((p) => p.id == id);
      if (i < 0) return;
      setState(() {
        if (r['isSuccess'] == true && r['data'] is Map) {
          final fresh = CommPost.fromJson(Map<String, dynamic>.from(r['data'] as Map));
          // Giữ trạng thái đã đọc tại chỗ; bài chi tiết trả về không kèm 2 bình luận mới nhất thì giữ bản cũ.
          if (fresh.latestComments.isEmpty) fresh.latestComments.addAll(_posts[i].latestComments);
          _posts[i] = fresh;
        } else {
          _posts.removeAt(i);
        }
      });
    });
  }

  void _showIncoming() {
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    _reload();
  }

  void _filterAuthor(String id, String name) {
    setState(() {
      _authorId = id;
      _authorName = name;
    });
    _reload();
  }

  void _filterTag(String tag) {
    setState(() => _tag = tag);
    _reload();
  }

  void _setChannel(String? id) {
    setState(() => _channelId = id);
    _reload();
  }

  void _setFilter(String f) {
    setState(() => _filter = f);
    _reload();
  }

  Future<void> _compose({bool ai = false, CommPost? edit, String? mode}) async {
    final ctx = _ctx;
    if (ctx == null) return;
    if (edit == null && !ctx.channels.any((c) => c.canPost)) {
      commToast(context, 'Bạn chưa được đăng vào kênh nào', error: true);
      return;
    }
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => CommEditorPage(ctx: ctx, post: edit, initialChannelId: _channelId, startWithAi: ai, initialMode: mode),
    ));
    if (ok == true) {
      _reload();
      if (edit == null && mounted) commToast(context, 'Đã lưu bài viết');
    }
  }

  Future<void> _editById(CommPost p) async {
    final r = await _api.getCommPost(p.id, markRead: false);
    if (!mounted || r['data'] is! Map) return;
    await _compose(edit: CommPost.fromJson(Map<String, dynamic>.from(r['data'] as Map)));
  }

  Future<void> _open(String id, {bool focusComment = false}) async {
    final ctx = _ctx;
    if (ctx == null) return;
    final result = await Navigator.of(context).push<Object?>(MaterialPageRoute(
      builder: (_) => CommPostDetailPage(postId: id, ctx: ctx, onEdit: _editById, focusComment: focusComment),
    ));
    if (!mounted) return;
    final i = _posts.indexWhere((p) => p.id == id);
    if (result == true) {
      _reload();
    } else if (result == commDetailDeleted) {
      if (i >= 0) setState(() => _posts.removeAt(i));
    } else if (result is CommPost) {
      if (i >= 0) setState(() => _posts[i] = result);
    } else if (i >= 0) {
      setState(() => _posts[i].myRead = true);
    }
  }

  // ─── Giao diện ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final ctx = _ctx;
    if (ctx == null) return const ColoredBox(color: SboxColors.page, child: SboxLoading());
    final showLeft = w >= 1000;
    final showRight = w >= 1280;
    final feed = _feed(ctx, compact: !showLeft);
    return ColoredBox(
      color: SboxColors.page,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (showLeft) SizedBox(width: 250, child: _channelsColumn(ctx)),
        Expanded(child: feed),
        if (showRight) SizedBox(width: 300, child: _rightColumn(ctx)),
      ]),
    );
  }

  Widget _channelsColumn(CommContext ctx) {
    Widget item({String? id, required String name, required IconData icon, required Color color, int unread = 0}) {
      final sel = _channelId == id;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Material(
          color: sel ? SboxColors.brand50 : Colors.transparent,
          borderRadius: SboxRadius.mdAll,
          child: InkWell(
            borderRadius: SboxRadius.mdAll,
            onTap: () => _setChannel(id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(children: [
                Icon(icon, size: 20, color: sel ? SboxColors.brand700 : color),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(tr(name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SboxType.smallStyle(sel ? SboxColors.brand800 : SboxColors.text).copyWith(fontWeight: sel || unread > 0 ? FontWeight.w700 : FontWeight.w500)),
                ),
                if (unread > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                    decoration: BoxDecoration(color: SboxColors.danger, borderRadius: SboxRadius.pillAll),
                    child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
              ]),
            ),
          ),
        ),
      );
    }

    final totalUnread = ctx.channels.fold<int>(0, (a, c) => a + c.unread);
    return ListView(padding: const EdgeInsets.fromLTRB(12, 20, 8, 24), children: [
      Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 12),
        child: Text(tr('Truyền thông'), style: SboxType.headlineStyle()),
      ),
      item(name: 'Tất cả bài viết', icon: Icons.home_outlined, color: SboxColors.slate500, unread: totalUnread),
      const Padding(padding: EdgeInsets.fromLTRB(10, 14, 10, 6), child: Divider(height: 1)),
      Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 6), child: Text(tr('Kênh'), style: SboxType.captionStyle())),
      for (final c in ctx.channels) item(id: c.id, name: c.name, icon: c.iconData, color: c.colorValue, unread: c.unread),
      if (ctx.canManageChannels) ...[
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _manageChannels, icon: const Icon(Icons.tune_rounded, size: 18), label: Text(tr('Quản lý kênh')))),
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _openInsights, icon: const Icon(Icons.insights_outlined, size: 18), label: Text(tr('Thống kê truyền thông')))),
      ],
    ]);
  }

  Widget _feed(CommContext ctx, {required bool compact}) {
    final ch = ctx.channel(_channelId);
    final filters = [
      ..._filters,
      if (ctx.isManager) ('pending', 'Chờ duyệt${(_sidebar?.pendingApproval ?? 0) > 0 ? ' (${_sidebar!.pendingApproval})' : ''}', Icons.pending_actions_outlined),
    ];
    final header = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (compact)
        SizedBox(
          height: 40,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(label: Text(tr('Tất cả')), selected: _channelId == null, onSelected: (_) => _setChannel(null)),
            ),
            for (final c in ctx.channels)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  avatar: Icon(c.iconData, size: 16, color: _channelId == c.id ? Colors.white : c.colorValue),
                  label: Text(c.unread > 0 ? '${c.name} · ${c.unread}' : c.name),
                  selected: _channelId == c.id,
                  selectedColor: c.colorValue,
                  labelStyle: TextStyle(color: _channelId == c.id ? Colors.white : SboxColors.text),
                  onSelected: (_) => _setChannel(c.id),
                ),
              ),
          ]),
        ),
      if (ch != null && !compact) ...[
        Row(children: [
          Icon(ch.iconData, color: ch.colorValue),
          const SizedBox(width: 8),
          Expanded(child: Text(tr(ch.name), style: SboxType.titleStyle())),
        ]),
        if ((ch.description ?? '').isNotEmpty) Text(tr(ch.description!), style: SboxType.smallStyle()),
        const SizedBox(height: 12),
      ],
      if (compact && _sidebar != null) ...[const SizedBox(height: 10), _mobileStrip(ctx)],
      const SizedBox(height: 10),
      _composerBox(ctx, compact: compact),
      const SizedBox(height: 12),
      // Điện thoại: 1 nút lọc (đủ mọi lựa chọn trong menu) + ô tìm rộng — không cắt chữ «Bắt buộc đọc».
      if (compact)
        Row(children: [
          PopupMenuButton<String>(
            tooltip: tr('Lọc bài'),
            initialValue: _filter,
            onSelected: _setFilter,
            itemBuilder: (_) => [
              for (final f in filters)
                PopupMenuItem(
                  value: f.$1,
                  child: Row(children: [
                    Icon(f.$3, size: 18, color: _filter == f.$1 ? SboxColors.brand600 : SboxColors.slate500),
                    const SizedBox(width: 10),
                    Text(tr(f.$2), style: TextStyle(fontWeight: _filter == f.$1 ? FontWeight.w700 : FontWeight.w500)),
                  ]),
                ),
            ],
            child: Builder(builder: (_) {
              final cur = filters.firstWhere((f) => f.$1 == _filter, orElse: () => filters.first);
              final on = cur.$1 != 'all';
              return Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: on ? SboxColors.brand50 : SboxColors.surface,
                  borderRadius: SboxRadius.pillAll,
                  border: Border.all(color: on ? SboxColors.brand200 : SboxColors.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(cur.$3, size: 17, color: on ? SboxColors.brand700 : SboxColors.slate600),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 110),
                    child: Text(tr(cur.$2), maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: SboxType.smallStyle(on ? SboxColors.brand700 : SboxColors.textSecondary).copyWith(fontWeight: FontWeight.w600)),
                  ),
                  const Icon(Icons.expand_more_rounded, size: 18, color: SboxColors.slate500),
                ]),
              );
            }),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: _search,
                decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search, size: 18), hintText: tr('Tìm bài'), contentPadding: const EdgeInsets.symmetric(vertical: 8)),
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 400), _reload);
                },
              ),
            ),
          ),
        ])
      else
      Row(children: [
        Expanded(
          child: SizedBox(
            height: 36,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final f in filters)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    avatar: Icon(f.$3, size: 16),
                    label: Text(tr(f.$2)),
                    selected: _filter == f.$1,
                    onSelected: (_) => _setFilter(f.$1),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: compact ? 130 : 220,
          height: 36,
          child: TextField(
            controller: _search,
            decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search, size: 18), hintText: tr('Tìm bài'), contentPadding: const EdgeInsets.symmetric(vertical: 8)),
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), _reload);
            },
          ),
        ),
      ]),
      if (_authorId != null || _tag != null) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          if (_authorId != null)
            InputChip(
              avatar: CommAvatar(name: _authorName ?? '?', size: 22),
              label: Text(tr('Bài của ${_authorName ?? ''}')),
              onDeleted: () {
                setState(() {
                  _authorId = null;
                  _authorName = null;
                });
                _reload();
              },
            ),
          if (_tag != null)
            InputChip(
              avatar: const Icon(Icons.tag_rounded, size: 16),
              label: Text(_tag!),
              onDeleted: () {
                setState(() => _tag = null);
                _reload();
              },
            ),
        ]),
      ],
      const SizedBox(height: 12),
    ]);

    final list = RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 16, compact ? 12 : 16, 40),
        itemCount: _posts.length + 2,
        itemBuilder: (_, i) {
          Widget child;
          if (i == 0) {
            child = header;
          } else if (i == _posts.length + 1) {
            child = _loading
                ? const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
                : _posts.isEmpty
                    ? SboxEmptyState(
                        icon: Icons.forum_outlined,
                        title: _filter == 'required' ? 'Bạn đã đọc hết văn bản bắt buộc' : 'Chưa có bài viết',
                        message: _filter == 'all' ? 'Chia sẻ tin tức, thông báo, tài liệu cho mọi người.' : 'Đổi bộ lọc để xem bài khác.',
                      )
                    : _loadingMore
                        ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
                        : const SizedBox(height: 16);
          } else {
            final p = _posts[i - 1];
            child = Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: CommPostCard(
                key: ValueKey('${p.id}-${p.version}-${p.status.index}-${p.comments}'),
                post: p,
                ctx: ctx,
                onOpen: () => _open(p.id),
                onChanged: _reload,
                onRemoved: () => setState(() => _posts.removeWhere((x) => x.id == p.id)),
                onEdit: () => _editById(p),
                onAuthor: _filterAuthor,
                onTag: _filterTag,
                onChannel: _setChannel,
              ),
            );
          }
          return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: child));
        },
      ),
    );
    final canPost = ctx.channels.any((c) => c.canPost);
    return Stack(children: [
      list,
      if (_incoming.isNotEmpty)
        Positioned(
          top: 12,
          left: 0,
          right: 0,
          child: Center(
            child: Material(
              color: SboxColors.brand600,
              elevation: 4,
              borderRadius: SboxRadius.pillAll,
              child: InkWell(
                borderRadius: SboxRadius.pillAll,
                onTap: _showIncoming,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.arrow_upward_rounded, size: 16, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(tr('${_incoming.length} bài mới'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      if (compact && canPost)
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: 'comm-compose',
            tooltip: tr('Viết bài'),
            onPressed: () => _compose(),
            child: const Icon(Icons.edit_rounded),
          ),
        ),
    ]);
  }

  /// Điện thoại: dải thẻ «việc của bạn» ngay đầu bảng tin (thay cột phải của máy tính).
  Widget _mobileStrip(CommContext ctx) {
    final s = _sidebar!;
    Widget tile(IconData icon, Color color, String label, String value, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Material(
            color: SboxColors.surface,
            borderRadius: SboxRadius.mdAll,
            child: InkWell(
              borderRadius: SboxRadius.mdAll,
              onTap: onTap,
              child: Container(
                width: 150,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(borderRadius: SboxRadius.mdAll, border: Border.all(color: SboxColors.border)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(icon, size: 18, color: color),
                    const Spacer(),
                    Text(value, style: SboxType.titleStyle(color)),
                  ]),
                  const SizedBox(height: 4),
                  Text(tr(label), maxLines: 2, overflow: TextOverflow.ellipsis, style: SboxType.captionStyle(SboxColors.text)),
                ]),
              ),
            ),
          ),
        );
    final tiles = <Widget>[
      if (s.requiredPending > 0)
        tile(Icons.verified_user_outlined, SboxColors.danger, 'Cần đọc, xác nhận', '${s.requiredPending}', () => _setFilter('required')),
      if (s.pendingApproval > 0 && ctx.isManager)
        tile(Icons.pending_actions_outlined, SboxColors.warning, 'Bài chờ duyệt', '${s.pendingApproval}', () => _setFilter('pending')),
      if (s.openPolls > 0) tile(Icons.poll_outlined, SboxColors.warning, 'Bình chọn chưa trả lời', '${s.openPolls}', () => _setFilter('polls')),
      if (s.events.isNotEmpty) tile(Icons.event_outlined, SboxColors.brand600, 'Sự kiện sắp tới', '${s.events.length}', () => _setFilter('events')),
      if (s.birthdays.isNotEmpty) tile(Icons.cake_outlined, SboxColors.violet, 'Sinh nhật 7 ngày', '${s.birthdays.length}', _showBirthdays),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return SizedBox(height: 84, child: ListView(scrollDirection: Axis.horizontal, children: tiles));
  }

  void _showBirthdays() {
    final s = _sidebar;
    if (s == null) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        Text(tr('Sinh nhật 7 ngày tới'), style: SboxType.titleStyle()),
        const SizedBox(height: 8),
        for (final b in s.birthdays)
          ListTile(
            leading: CommAvatar(name: b.name, photo: b.photo, size: 36),
            title: Text(b.name),
            trailing: Text('${b.date.day}/${b.date.month}', style: SboxType.smallStyle()),
          ),
      ]),
    );
  }

  Widget _composerBox(CommContext ctx, {bool compact = false}) {
    final canPost = ctx.channels.any((c) => c.canPost);
    if (!canPost) return const SizedBox.shrink();
    // 4 nút chia đều 1 hàng (chữ tự thu nhỏ) — nút AI không rớt xuống hàng riêng.
    Widget action(IconData icon, String label, Color color, VoidCallback onTap) => Expanded(
          child: TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8)),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 19, color: color),
                const SizedBox(width: 5),
                Text(tr(label), maxLines: 1, style: SboxType.smallStyle(SboxColors.textSecondary).copyWith(fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(color: SboxColors.surface, borderRadius: SboxRadius.lgAll, border: Border.all(color: SboxColors.border)),
      child: Column(children: [
        Row(children: [
          CommAvatar(name: ctx.myName.isEmpty ? 'Tôi' : ctx.myName, size: 40),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              borderRadius: SboxRadius.pillAll,
              onTap: () => _compose(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(color: SboxColors.slate50, borderRadius: SboxRadius.pillAll, border: Border.all(color: SboxColors.border)),
                child: Text(tr('Chia sẻ điều gì đó với mọi người…'), style: SboxType.bodyStyle(SboxColors.textMuted)),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          action(Icons.photo_library_outlined, 'Ảnh', SboxColors.success, () => _compose(mode: 'image')),
          action(Icons.description_outlined, compact ? 'Tệp' : 'Word / PDF / Excel', SboxColors.brand600, () => _compose(mode: 'file')),
          action(Icons.poll_outlined, 'Bình chọn', SboxColors.warning, () => _compose(mode: 'poll')),
          action(Icons.auto_awesome, compact ? 'AI' : 'Viết bằng AI', SboxColors.violet, () => _compose(ai: true)),
        ]),
      ]),
    );
  }

  Widget _rightColumn(CommContext ctx) {
    final s = _sidebar;
    Widget box(String title, IconData icon, Color color, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SboxCard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [Icon(icon, size: 18, color: color), const SizedBox(width: 8), Text(tr(title), style: SboxType.bodyStrong())]),
              const SizedBox(height: 8),
              ...children,
            ]),
          ),
        );
    return ListView(padding: const EdgeInsets.fromLTRB(8, 20, 16, 24), children: [
      box('Cần bạn xử lý', Icons.task_alt_rounded, SboxColors.danger, [
        if ((s?.requiredPending ?? 0) == 0 && (s?.openPolls ?? 0) == 0 && (s?.pendingApproval ?? 0) == 0)
          Text(tr('Không có việc tồn — tuyệt vời!'), style: SboxType.smallStyle()),
        for (final r in s?.required ?? const <CommBrief>[])
          InkWell(
            onTap: () => _open(r.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                const Icon(Icons.circle, size: 7, color: SboxColors.danger),
                const SizedBox(width: 8),
                Expanded(child: Text(r.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: SboxType.smallStyle(SboxColors.text))),
              ]),
            ),
          ),
        if ((s?.openPolls ?? 0) > 0)
          TextButton(onPressed: () => _setFilter('polls'), child: Text(tr('${s!.openPolls} bình chọn chưa trả lời'))),
        if ((s?.pendingApproval ?? 0) > 0)
          TextButton(onPressed: () => _setFilter('pending'), child: Text(tr('${s!.pendingApproval} bài chờ bạn duyệt'))),
      ]),
      box('Sắp diễn ra', Icons.event_outlined, SboxColors.warning, [
        if ((s?.events ?? const []).isEmpty) Text(tr('Chưa có sự kiện'), style: SboxType.smallStyle()),
        for (final e in s?.events ?? const <CommBrief>[])
          InkWell(
            onTap: () => _open(e.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Container(
                  width: 40,
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  decoration: BoxDecoration(color: SboxColors.warningSoft, borderRadius: SboxRadius.smAll),
                  child: Column(children: [
                    Text('${e.at?.day ?? ''}', style: SboxType.bodyStrong(SboxColors.warningText)),
                    Text('Th${e.at?.month ?? ''}', style: SboxType.captionStyle(SboxColors.warningText).copyWith(fontSize: 10)),
                  ]),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: SboxType.smallStyle(SboxColors.text))),
              ]),
            ),
          ),
      ]),
      box('Sinh nhật 7 ngày tới', Icons.cake_outlined, SboxColors.violet, [
        if ((s?.birthdays ?? const []).isEmpty) Text(tr('Không có sinh nhật'), style: SboxType.smallStyle()),
        for (final b in s?.birthdays ?? const <({String name, DateTime date, String? photo})>[])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              CommAvatar(name: b.name, photo: b.photo, size: 30),
              const SizedBox(width: 8),
              Expanded(child: Text(b.name, style: SboxType.smallStyle(SboxColors.text))),
              Text('${b.date.day}/${b.date.month}', style: SboxType.captionStyle()),
            ]),
          ),
      ]),
    ]);
  }

  // ─── Quản lý kênh & thống kê ──────────────────────────────────

  Future<void> _manageChannels() async {
    await showDialog<void>(context: context, builder: (_) => _ChannelManager(ctx: _ctx!, api: _api));
    _reload();
  }

  void _openInsights() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CommInsightsPage(ctx: _ctx!)));
  }
}

class _ChannelManager extends StatefulWidget {
  const _ChannelManager({required this.ctx, required this.api});
  final CommContext ctx;
  final ApiService api;

  @override
  State<_ChannelManager> createState() => _ChannelManagerState();
}

class _ChannelManagerState extends State<_ChannelManager> {
  late List<CommChannel> _channels = [...widget.ctx.channels];

  Future<void> _edit([CommChannel? c]) async {
    final name = TextEditingController(text: c?.name ?? '');
    final desc = TextEditingController(text: c?.description ?? '');
    var policy = c?.postPolicy ?? 0;
    var approval = c?.requireApproval ?? false;
    String? branch = c?.branchId;
    String? dept = c?.departmentId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(tr(c == null ? 'Kênh mới' : 'Sửa kênh')),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: InputDecoration(labelText: tr('Tên kênh'))),
              TextField(controller: desc, decoration: InputDecoration(labelText: tr('Mô tả'))),
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: policy,
                decoration: InputDecoration(labelText: tr('Ai được đăng')),
                items: [
                  DropdownMenuItem(value: 0, child: Text(tr('Mọi người có quyền đăng bài'))),
                  DropdownMenuItem(value: 1, child: Text(tr('Chỉ người kiểm duyệt'))),
                ],
                onChanged: (v) => set(() => policy = v ?? 0),
              ),
              if (policy == 0)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: approval,
                  onChanged: (v) => set(() => approval = v),
                  title: Text(tr('Bài cần duyệt trước khi hiện')),
                  subtitle: Text(tr('Sửa bài đã duyệt cũng phải duyệt lại')),
                ),
              if (widget.ctx.branches.isNotEmpty)
                DropdownButtonFormField<String?>(
                  value: branch,
                  decoration: InputDecoration(labelText: tr('Kênh riêng chi nhánh')),
                  items: [
                    DropdownMenuItem(value: null, child: Text(tr('Toàn công ty'))),
                    for (final b in widget.ctx.branches) DropdownMenuItem(value: b.id, child: Text(b.name)),
                  ],
                  onChanged: (v) => set(() => branch = v),
                ),
              if (widget.ctx.departments.isNotEmpty)
                DropdownButtonFormField<String?>(
                  value: widget.ctx.departments.any((d) => d.id == dept) ? dept : null,
                  decoration: InputDecoration(labelText: tr('Kênh riêng phòng ban')),
                  items: [
                    DropdownMenuItem(value: null, child: Text(tr('Mọi phòng ban'))),
                    for (final d in widget.ctx.departments) DropdownMenuItem(value: d.id, child: Text(d.name)),
                  ],
                  onChanged: (v) => set(() => dept = v),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final r = await widget.api.saveCommChannel({
      'name': name.text.trim(),
      'description': desc.text.trim(),
      'icon': c?.icon ?? (branch != null ? 'store' : 'groups'),
      'color': c?.color,
      'postPolicy': policy,
      'requireApproval': policy == 0 && approval,
      'branchId': branch,
      'departmentId': dept,
      'sortOrder': c?.sortOrder ?? 0,
    }, id: c?.id);
    if (!mounted) return;
    if (r['isSuccess'] != true) {
      commToast(context, '${r['message']}', error: true);
      return;
    }
    final list = await widget.api.getCommChannels();
    if (!mounted) return;
    setState(() => _channels = list['data'] is List
        ? (list['data'] as List).whereType<Map>().map((e) => CommChannel.fromJson(Map<String, dynamic>.from(e))).toList()
        : _channels);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Quản lý kênh')),
      content: SizedBox(
        width: 520,
        height: 480,
        child: ListView(children: [
          for (final c in _channels)
            ListTile(
              leading: Icon(c.iconData, color: c.colorValue),
              title: Text(c.name),
              subtitle: Text(tr([
                c.postPolicy == 0 ? 'Mọi người được đăng' : 'Chỉ người kiểm duyệt đăng',
                if (c.requireApproval) 'cần duyệt',
                if (c.branchId != null) 'riêng chi nhánh',
                if (c.departmentId != null) 'riêng phòng ban',
              ].join(' · '))),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(c)),
                if (!c.isSystem)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: tr('Xóa kênh'),
                    onPressed: () async {
                      final ok = await SboxDialogs.confirm(context,
                          title: 'Xóa kênh «${c.name}»?',
                          message: 'Các bài trong kênh được chuyển sang Bảng tin.',
                          confirmLabel: 'Xóa',
                          danger: true);
                      if (!ok) return;
                      final r = await widget.api.deleteCommChannel(c.id);
                      if (!mounted) return;
                      if (r['isSuccess'] == true) {
                        setState(() => _channels.remove(c));
                      } else {
                        commToast(context, '${r['message']}', error: true);
                      }
                    },
                  ),
              ]),
            ),
        ]),
      ),
      actions: [
        TextButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: Text(tr('Thêm kênh'))),
        FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Xong'))),
      ],
    );
  }
}

/// Thống kê truyền thông cho quản lý: tỷ lệ đọc, văn bản chưa xác nhận.
class CommInsightsPage extends StatefulWidget {
  const CommInsightsPage({super.key, required this.ctx});
  final CommContext ctx;

  @override
  State<CommInsightsPage> createState() => _CommInsightsPageState();
}

class _CommInsightsPageState extends State<CommInsightsPage> {
  final _api = ApiService();
  Map<String, dynamic>? _data;
  List<CommPostStat> _posts = [];

  @override
  void initState() {
    super.initState();
    _api.getCommInsights().then((r) {
      if (!mounted) return;
      setState(() {
        _data = r['data'] is Map ? Map<String, dynamic>.from(r['data'] as Map) : {};
        _posts = (_data!['posts'] as List? ?? []).whereType<Map>().map((e) => CommPostStat.fromJson(Map<String, dynamic>.from(e))).toList();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: AppBar(backgroundColor: SboxColors.surface, surfaceTintColor: Colors.transparent, title: Text(tr('Thống kê truyền thông'))),
      body: d == null
          ? const SboxLoading()
          : SboxReportLayout(
              kpis: [
                SboxKpi(label: 'Bài 30 ngày', value: SboxFmt.number(d['posts30'] as num? ?? 0), icon: Icons.article_outlined),
                SboxKpi(label: 'Tỷ lệ đọc TB', value: SboxFmt.pct(d['avgReadRate'] as num? ?? 0), icon: Icons.visibility_outlined, tone: SboxTone.success),
                SboxKpi(label: 'Văn bản bắt buộc', value: SboxFmt.number(d['requiredPosts'] as num? ?? 0), icon: Icons.verified_user_outlined, tone: SboxTone.violet),
                SboxKpi(label: 'Lượt chưa xác nhận', value: SboxFmt.number(d['outstandingAcks'] as num? ?? 0), icon: Icons.pending_actions_outlined, tone: SboxTone.danger),
              ],
              charts: [
                SboxChartCard(
                  title: 'Tỷ lệ đọc theo bài',
                  wide: true,
                  child: SboxRankList(
                    maxItems: 10,
                    valueFormat: (v) => SboxFmt.pct(v),
                    items: [for (final p in _posts) SboxSlice(p.title, p.readRate, caption: '${p.read}/${p.audience}')],
                  ),
                ),
              ],
              tableTitle: 'Chi tiết bài viết',
              table: SboxDataTable<CommPostStat>(
                rows: _posts,
                pageSize: 20,
                emptyTitle: 'Chưa có bài trong 30 ngày',
                columns: [
                  SboxColumn(label: 'Bài viết', primary: true, flex: 4, text: (p) => p.title, sortValue: (p) => p.title),
                  SboxColumn(label: 'Kênh', flex: 2, hideOnMobile: true, text: (p) => p.channelName ?? '—'),
                  SboxColumn(label: 'Người nhận', numeric: true, text: (p) => '${p.audience}', sortValue: (p) => p.audience),
                  SboxColumn(label: 'Đã đọc', numeric: true, text: (p) => '${p.read} (${SboxFmt.pct(p.readRate)})', sortValue: (p) => p.readRate),
                  SboxColumn(label: 'Xác nhận', numeric: true, text: (p) => p.requireAck ? '${p.acked}/${p.audience}' : '—', sortValue: (p) => p.acked),
                  SboxColumn(label: 'Tương tác', numeric: true, hideOnMobile: true, text: (p) => '${p.reactions + p.comments}', sortValue: (p) => p.reactions + p.comments),
                ],
              ),
            ),
    );
  }
}
