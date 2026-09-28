import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../models/comm_v2.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/navigation_notifier.dart';
import '../../utils/store_role_helper.dart';
import '../../widgets/sbox/sbox_ui.dart';
import '../communication_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    NavigationNotifier.notificationHighlightId.addListener(_consumeHighlight);
    _init();
  }

  @override
  void dispose() {
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
      final isManager = StoreRoleHelper.isManagerOrAbove(auth.userRole);
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
        isManager: isManager,
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
      _api.getCommFeed(channelId: _channelId, filter: _filter, search: _search.text.trim(), page: 1),
      _api.getCommSidebar(),
      if (widget.debugContext == null) _api.getCommChannels(),
    ]);
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      _page = 1;
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
    final r = await _api.getCommFeed(channelId: _channelId, filter: _filter, search: _search.text.trim(), page: _page + 1);
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

  void _setChannel(String? id) {
    setState(() => _channelId = id);
    _reload();
  }

  void _setFilter(String f) {
    setState(() => _filter = f);
    _reload();
  }

  Future<void> _compose({bool ai = false, CommPost? edit}) async {
    final ctx = _ctx;
    if (ctx == null) return;
    if (edit == null && !ctx.channels.any((c) => c.canPost)) {
      commToast(context, 'Bạn chưa được đăng vào kênh nào', error: true);
      return;
    }
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => CommEditorPage(ctx: ctx, post: edit, initialChannelId: _channelId, startWithAi: ai),
    ));
    if (ok == true) _reload();
  }

  Future<void> _editById(CommPost p) async {
    final r = await _api.getCommPost(p.id, markRead: false);
    if (!mounted || r['data'] is! Map) return;
    await _compose(edit: CommPost.fromJson(Map<String, dynamic>.from(r['data'] as Map)));
  }

  Future<void> _open(String id) async {
    final ctx = _ctx;
    if (ctx == null) return;
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => CommPostDetailPage(postId: id, ctx: ctx, onEdit: _editById),
    ));
    if (changed == true) {
      _reload();
    } else {
      final i = _posts.indexWhere((p) => p.id == id);
      if (i >= 0) setState(() => _posts[i].myRead = true);
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
      if (ctx.isManager) ...[
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _manageChannels, icon: const Icon(Icons.tune_rounded, size: 18), label: Text(tr('Quản lý kênh')))),
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _openInsights, icon: const Icon(Icons.insights_outlined, size: 18), label: Text(tr('Thống kê truyền thông')))),
        Align(alignment: Alignment.centerLeft, child: TextButton.icon(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => Scaffold(appBar: AppBar(title: Text(tr('Truyền thông (giao diện cũ)'))), body: const CommunicationScreen()),
          )),
          icon: const Icon(Icons.history_rounded, size: 18),
          label: Text(tr('Giao diện cũ')),
        )),
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
      if (compact && (_sidebar?.requiredPending ?? 0) > 0) ...[const SizedBox(height: 8), _requiredBanner()],
      const SizedBox(height: 10),
      _composerBox(ctx),
      const SizedBox(height: 12),
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
      const SizedBox(height: 12),
    ]);

    return RefreshIndicator(
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
                key: ValueKey(p.id),
                post: p,
                ctx: ctx,
                onOpen: () => _open(p.id),
                onChanged: _reload,
                onEdit: () => _editById(p),
              ),
            );
          }
          return Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: child));
        },
      ),
    );
  }

  Widget _composerBox(CommContext ctx) {
    final canPost = ctx.channels.any((c) => c.canPost);
    if (!canPost) return const SizedBox.shrink();
    Widget action(IconData icon, String label, Color color, VoidCallback onTap) => TextButton.icon(
          onPressed: onTap,
          icon: Icon(icon, size: 19, color: color),
          label: Text(tr(label), style: SboxType.smallStyle(SboxColors.textSecondary).copyWith(fontWeight: FontWeight.w600)),
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
        Wrap(alignment: WrapAlignment.spaceAround, children: [
          action(Icons.photo_library_outlined, 'Ảnh', SboxColors.success, () => _compose()),
          action(Icons.description_outlined, 'Word / PDF / Excel', SboxColors.brand600, () => _compose()),
          action(Icons.poll_outlined, 'Bình chọn', SboxColors.warning, () => _compose()),
          action(Icons.auto_awesome, 'Viết bằng AI', SboxColors.violet, () => _compose(ai: true)),
        ]),
      ]),
    );
  }

  Widget _requiredBanner() {
    final s = _sidebar!;
    return Material(
      color: SboxColors.dangerSoft,
      borderRadius: SboxRadius.mdAll,
      child: InkWell(
        borderRadius: SboxRadius.mdAll,
        onTap: () => _setFilter('required'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            const Icon(Icons.verified_user_outlined, color: SboxColors.danger),
            const SizedBox(width: 10),
            Expanded(child: Text(tr('Bạn có ${s.requiredPending} văn bản cần đọc và xác nhận'), style: SboxType.smallStyle(SboxColors.dangerText).copyWith(fontWeight: FontWeight.w600))),
            const Icon(Icons.chevron_right_rounded, color: SboxColors.dangerText),
          ]),
        ),
      ),
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
                  DropdownMenuItem(value: 0, child: Text(tr('Mọi nhân viên'))),
                  DropdownMenuItem(value: 1, child: Text(tr('Chỉ quản lý'))),
                ],
                onChanged: (v) => set(() => policy = v ?? 0),
              ),
              if (policy == 0)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: approval,
                  onChanged: (v) => set(() => approval = v),
                  title: Text(tr('Bài nhân viên cần duyệt')),
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
                c.postPolicy == 0 ? 'Mọi người được đăng' : 'Chỉ quản lý đăng',
                if (c.requireApproval) 'cần duyệt',
                if (c.branchId != null) 'riêng chi nhánh',
              ].join(' · '))),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(c)),
                if (!c.isSystem)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      await widget.api.deleteCommChannel(c.id);
                      setState(() => _channels.remove(c));
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
