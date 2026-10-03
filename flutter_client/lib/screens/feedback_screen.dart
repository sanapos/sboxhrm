import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../theme/sbox_tokens.dart';
import '../utils/navigation_notifier.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/page_top_actions.dart';
import 'feedback/feedback_compose_sheet.dart';
import 'feedback/feedback_report_view.dart';
import 'feedback/feedback_ui.dart';
import 'feedback_detail_screen.dart';

/// Kiến nghị / khiếu nại: «Của tôi» (phiếu tôi gửi), «Cần xử lý» (hòm thư của người xử lý), «Báo cáo».
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> with SingleTickerProviderStateMixin {
  final _api = ApiService();
  late final TabController _tabCtl;
  late final List<String> _tabs;
  late final bool _handler;
  VoidCallback? _highlightListener;

  // Của tôi
  List<Map<String, dynamic>> _mine = [];
  bool _mineLoading = true;
  String _mineFilter = 'all';
  final _mineSearch = TextEditingController();

  // Cần xử lý
  List<Map<String, dynamic>> _inbox = [];
  Map<String, dynamic> _counts = {};
  bool _inboxLoading = true;
  bool _inboxMore = false;
  int _inboxPage = 1;
  String _inboxQuick = 'open';
  String? _fCategory;
  String? _fTopic;
  int? _fPriority;
  String? _fRecipient; // 'general' | employeeId
  final _inboxSearch = TextEditingController();
  Timer? _debounce;

  List<Map<String, dynamic>> _managers = [];

  bool _isHandlerRole() {
    final r = Provider.of<AuthProvider>(context, listen: false).userRole.toLowerCase();
    return const {'admin', 'superadmin', 'director', 'manager', 'departmenthead', 'accountant', 'agent'}.contains(r) ||
        Provider.of<PermissionProvider>(context, listen: false).canApprove('Feedback');
  }

  @override
  void initState() {
    super.initState();
    _handler = _isHandlerRole();
    _tabs = ['mine', if (_handler) 'inbox', if (_handler) 'report'];
    final preferInbox = NavigationNotifier.feedbackPreferInbox.value;
    _tabCtl = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: _handler && preferInbox ? 1 : (_handler ? 1 : 0),
    );
    _tabCtl.addListener(() {
      if (!_tabCtl.indexIsChanging) setState(() {});
    });
    _highlightListener = () {
      if (NavigationNotifier.notificationHighlightId.value != null) _consumeHighlight();
    };
    NavigationNotifier.notificationHighlightId.addListener(_highlightListener!);

    _loadManagers();
    Future.wait([_loadMine(), if (_handler) _loadInbox()]).then((_) {
      if (preferInbox) NavigationNotifier.feedbackPreferInbox.value = false;
      _consumeHighlight();
      if (NavigationNotifier.takePendingAiOpenCreate('feedback')) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _compose();
        });
      }
    });
  }

  @override
  void dispose() {
    if (_highlightListener != null) {
      NavigationNotifier.notificationHighlightId.removeListener(_highlightListener!);
    }
    _debounce?.cancel();
    _tabCtl.dispose();
    _mineSearch.dispose();
    _inboxSearch.dispose();
    super.dispose();
  }

  // ═════════════ DỮ LIỆU ═════════════

  List<Map<String, dynamic>> _rows(dynamic v) => [
        for (final x in (v as List? ?? const []))
          if (x is Map) Map<String, dynamic>.from(x),
      ];

  Future<void> _loadManagers() async {
    final res = await _api.getFeedbackManagers();
    if (mounted && res['isSuccess'] == true) setState(() => _managers = _rows(res['data']));
  }

  Future<void> _loadMine() async {
    final res = await _api.getMyFeedbacks(search: _mineSearch.text);
    if (!mounted) return;
    setState(() {
      _mineLoading = false;
      if (res['isSuccess'] == true) _mine = _rows(res['data']);
    });
  }

  Future<void> _loadInbox({bool more = false}) async {
    if (!more) setState(() => _inboxLoading = _inbox.isEmpty);
    final page = more ? _inboxPage + 1 : 1;
    final res = await _api.getFeedbacks(
      status: switch (_inboxQuick) {
        'open' => 'Open',
        'pending' => 'Pending',
        'resolved' => 'Resolved',
        _ => null,
      },
      overdue: _inboxQuick == 'overdue',
      assignedToMe: _inboxQuick == 'mine',
      category: _fCategory,
      topic: _fTopic,
      priority: _fPriority,
      generalMailboxOnly: _fRecipient == 'general',
      recipientEmployeeId: _fRecipient == 'general' ? null : _fRecipient,
      search: _inboxSearch.text,
      page: page,
      pageSize: 30,
    );
    if (!mounted) return;
    setState(() {
      _inboxLoading = false;
      if (res['isSuccess'] == true) {
        final d = res['data'] as Map<String, dynamic>? ?? const {};
        final items = _rows(d['items']);
        _inbox = more ? [..._inbox, ...items] : items;
        _inboxPage = page;
        _inboxMore = _inbox.length < FeedbackUi.n(d['total']);
        _counts = Map<String, dynamic>.from(d['counts'] as Map? ?? const {});
      }
    });
  }

  Future<void> _reloadAll() => Future.wait([_loadMine(), if (_handler) _loadInbox()]);

  Future<void> _consumeHighlight() async {
    final id = NavigationNotifier.notificationHighlightId.value;
    if (id == null || id.isEmpty || !mounted) return;
    NavigationNotifier.notificationHighlightId.value = null;
    final isMine = _mine.any((f) => f['id']?.toString() == id);
    await _openDetail(id, isMine: isMine);
  }

  Future<void> _openDetail(String id, {required bool isMine}) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FeedbackDetailScreen(feedbackId: id, isMine: isMine),
    ));
    if (mounted) _reloadAll();
  }

  Future<void> _compose() async {
    final ok = await showFeedbackCompose(context, managers: _managers);
    if (!ok || !mounted) return;
    _tabCtl.animateTo(0);
    _loadMine();
  }

  // ═════════════ GIAO DIỆN ═════════════

  String _tab() => _tabs[_tabCtl.index];

  @override
  Widget build(BuildContext context) {
    final canCreate = Provider.of<PermissionProvider>(context, listen: false).canCreate('Feedback');
    return RegisterPageTopActions(
      actions: [
        if (canCreate && _tab() != 'report')
          HrmTopBarAction(
            icon: Icons.add_rounded,
            label: 'Gửi kiến nghị',
            primary: true,
            showLabel: true,
            onPressed: _compose,
          ),
      ],
      child: Scaffold(
        backgroundColor: HrmPageChrome.background,
        body: Column(children: [
          if (_tabs.length > 1)
            Material(
              color: Colors.white,
              child: TabBar(
                controller: _tabCtl,
                labelColor: SboxColors.brand700,
                unselectedLabelColor: SboxColors.slate500,
                indicatorColor: SboxColors.brand600,
                indicatorWeight: 3,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                tabs: [
                  for (final t in _tabs)
                    Tab(
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(switch (t) {
                          'mine' => Icons.outbox_rounded,
                          'inbox' => Icons.inbox_rounded,
                          _ => Icons.insights_rounded,
                        }, size: 18),
                        const SizedBox(width: 6),
                        Text(tr(switch (t) { 'mine' => 'Của tôi', 'inbox' => 'Cần xử lý', _ => 'Báo cáo' })),
                        if (t == 'inbox' && FeedbackUi.n(_counts['open']) > 0) ...[
                          const SizedBox(width: 6),
                          FeedbackUi.pill('${FeedbackUi.n(_counts['open'])}',
                              FeedbackUi.n(_counts['overdue']) > 0 ? SboxColors.danger : SboxColors.brand600,
                              solid: true),
                        ],
                      ]),
                    ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabCtl,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final t in _tabs)
                  switch (t) {
                    'mine' => _mineTab(),
                    'inbox' => _inboxTab(),
                    _ => const FeedbackReportView(),
                  },
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ── Của tôi ──

  Widget _mineTab() {
    final waitingRate = _mine.where((f) =>
        (f['status'] == 'Resolved' || f['status'] == 'Closed') && f['rating'] == null).length;
    final list = _mine.where((f) => switch (_mineFilter) {
          'open' => FeedbackUi.isOpen(f['status']?.toString()),
          'done' => !FeedbackUi.isOpen(f['status']?.toString()),
          'rate' => (f['status'] == 'Resolved' || f['status'] == 'Closed') && f['rating'] == null,
          _ => true,
        }).toList();
    return RefreshIndicator(
      onRefresh: _loadMine,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          _mineHero(waitingRate),
          const SizedBox(height: 12),
          _searchBox(_mineSearch, 'Tìm theo tiêu đề, nội dung, mã phiếu', _loadMine),
          const SizedBox(height: 10),
          _chips([
            ('all', 'Tất cả', _mine.length),
            ('open', 'Đang xử lý', _mine.where((f) => FeedbackUi.isOpen(f['status']?.toString())).length),
            ('done', 'Đã xong', _mine.where((f) => !FeedbackUi.isOpen(f['status']?.toString())).length),
            if (waitingRate > 0) ('rate', 'Chờ đánh giá', waitingRate),
          ], _mineFilter, (k) => setState(() => _mineFilter = k)),
          const SizedBox(height: 8),
          if (_mineLoading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (list.isEmpty)
            _empty(Icons.outbox_rounded, _mine.isEmpty ? 'Bạn chưa gửi kiến nghị nào' : 'Không có phiếu phù hợp',
                _mine.isEmpty ? 'Có vướng mắc về lương, chế độ, môi trường làm việc…? Hãy gửi để được giải quyết.' : null)
          else
            ...list.map((f) => _card(f, mine: true)),
        ],
      ),
    );
  }

  Widget _mineHero(int waitingRate) {
    final open = _mine.where((f) => FeedbackUi.isOpen(f['status']?.toString())).length;
    final done = _mine.length - open;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [SboxColors.brand700, SboxColors.brand500]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Tiếng nói của bạn được lắng nghe'),
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              tr('$open đang xử lý · $done đã xong'
                  '${waitingRate > 0 ? ' · $waitingRate chờ bạn đánh giá' : ''}'),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ]),
        ),
        const Icon(Icons.record_voice_over_rounded, color: Colors.white54, size: 40),
      ]),
    );
  }

  // ── Cần xử lý ──

  Widget _inboxTab() {
    final activeFilters = [_fCategory, _fTopic, _fPriority, _fRecipient].where((x) => x != null).length;
    return RefreshIndicator(
      onRefresh: _loadInbox,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          Row(children: [
            Expanded(
              child: _searchBox(_inboxSearch, 'Tìm theo tiêu đề, nội dung, mã phiếu', () => _loadInbox()),
            ),
            const SizedBox(width: 8),
            Badge(
              isLabelVisible: activeFilters > 0,
              label: Text('$activeFilters'),
              child: IconButton.filledTonal(
                tooltip: tr('Bộ lọc'),
                onPressed: _filterSheet,
                icon: const Icon(Icons.tune_rounded),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          _chips([
            ('open', 'Đang mở', FeedbackUi.n(_counts['open'])),
            ('pending', 'Chờ tiếp nhận', FeedbackUi.n(_counts['pending'])),
            ('overdue', 'Quá hạn', FeedbackUi.n(_counts['overdue'])),
            ('mine', 'Giao cho tôi', FeedbackUi.n(_counts['assignedToMe'])),
            ('resolved', 'Đã giải quyết', FeedbackUi.n(_counts['resolved'])),
            ('all', 'Tất cả', FeedbackUi.n(_counts['all'])),
          ], _inboxQuick, (k) {
            setState(() => _inboxQuick = k);
            _loadInbox();
          }, danger: const {'overdue'}),
          const SizedBox(height: 8),
          if (_inboxLoading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (_inbox.isEmpty)
            _empty(Icons.inbox_rounded, 'Không có phiếu nào', 'Mọi kiến nghị trong mục này đã được xử lý.')
          else ...[
            ..._inbox.map((f) => _card(f, mine: false)),
            if (_inboxMore)
              Center(
                child: TextButton.icon(
                  onPressed: () => _loadInbox(more: true),
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text(tr('Xem thêm')),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _filterSheet() async {
    String? c = _fCategory, t = _fTopic, r = _fRecipient;
    int? p = _fPriority;
    final apply = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        Widget group(String title, List<Widget> chips) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: chips),
              ]),
            );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              group('Loại phiếu', [
                for (final e in FeedbackUi.categories.entries)
                  ChoiceChip(label: Text(tr(e.value)), selected: c == e.key,
                      onSelected: (s) => setS(() => c = s ? e.key : null)),
              ]),
              group('Mức độ', [
                for (final e in FeedbackUi.priorities.entries)
                  ChoiceChip(label: Text(tr(e.value)), selected: p == e.key,
                      onSelected: (s) => setS(() => p = s ? e.key : null)),
              ]),
              group('Chủ đề', [
                for (final x in FeedbackUi.topics)
                  ChoiceChip(label: Text(tr(x)), selected: t == x, onSelected: (s) => setS(() => t = s ? x : null)),
              ]),
              group('Gửi tới', [
                ChoiceChip(label: Text(tr('Hòm thư chung')), selected: r == 'general',
                    onSelected: (s) => setS(() => r = s ? 'general' : null)),
                for (final m in _managers)
                  ChoiceChip(label: Text(m['name']?.toString() ?? ''), selected: r == m['id']?.toString(),
                      onSelected: (s) => setS(() => r = s ? m['id']?.toString() : null)),
              ]),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setS(() {
                      c = null;
                      t = null;
                      p = null;
                      r = null;
                    }),
                    child: Text(tr('Xoá lọc')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Áp dụng'))),
                ),
              ]),
            ]),
          ),
        );
      }),
    );
    if (apply == true) {
      setState(() {
        _fCategory = c;
        _fTopic = t;
        _fPriority = p;
        _fRecipient = r;
      });
      _loadInbox();
    }
  }

  // ── Thành phần chung ──

  Widget _searchBox(TextEditingController ctl, String hint, VoidCallback onSearch) => TextField(
        controller: ctl,
        onChanged: (_) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 450), onSearch);
        },
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded),
          hintText: tr(hint),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: SboxColors.slate200)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: SboxColors.slate200)),
        ),
      );

  Widget _chips(List<(String, String, int)> items, String selected, ValueChanged<String> onTap,
      {Set<String> danger = const {}}) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final (k, label, count) in items)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              selected: selected == k,
              onSelected: (_) => onTap(k),
              label: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(tr(label)),
                const SizedBox(width: 6),
                Text('$count',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: danger.contains(k) && count > 0 ? SboxColors.danger : SboxColors.slate600)),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _empty(IconData icon, String title, String? sub) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(children: [
          Icon(icon, size: 56, color: SboxColors.slate300),
          const SizedBox(height: 12),
          Text(tr(title), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: SboxColors.slate700)),
          if (sub != null) ...[
            const SizedBox(height: 6),
            Text(tr(sub), textAlign: TextAlign.center, style: const TextStyle(color: SboxColors.slate500)),
          ],
        ]),
      );

  Widget _card(Map<String, dynamic> f, {required bool mine}) {
    final status = f['status']?.toString();
    final priority = FeedbackUi.n(f['priority']);
    final category = f['category']?.toString();
    final open = FeedbackUi.isOpen(status);
    final rating = f['rating'];
    final who = f['isAnonymous'] == true
        ? (mine ? 'Bạn (ẩn danh)' : 'Ẩn danh')
        : mine
            ? 'Bạn'
            : [f['senderName'], f['senderDepartment']].where((x) => (x?.toString() ?? '').isNotEmpty).join(' · ');
    final to = f['assigneeName'] ?? f['recipientName'] ?? 'Hòm thư chung';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openDetail(f['id'].toString(), isMine: mine || f['isMine'] == true),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: f['overdue'] == true ? SboxColors.danger.withValues(alpha: 0.5) : SboxColors.slate200),
            ),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(width: 5, color: open ? FeedbackUi.priorityColor(priority) : SboxColors.slate200),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(FeedbackUi.categoryIcon(category), size: 16, color: FeedbackUi.categoryColor(category)),
                        const SizedBox(width: 6),
                        Text(tr(FeedbackUi.categories[category] ?? ''),
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: FeedbackUi.categoryColor(category))),
                        if ((f['code']?.toString() ?? '').isNotEmpty) ...[
                          const Text('  ·  ', style: TextStyle(color: SboxColors.slate300)),
                          Text(f['code'].toString(), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                        ],
                        const Spacer(),
                        Text(tr(FeedbackUi.ago(FeedbackUi.date(f['updatedAt']) ?? FeedbackUi.date(f['createdAt']))),
                            style: const TextStyle(fontSize: 11.5, color: SboxColors.slate400)),
                      ]),
                      const SizedBox(height: 6),
                      Text(f['title']?.toString() ?? '',
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: SboxColors.slate900)),
                      const SizedBox(height: 3),
                      Text(f['content']?.toString() ?? '',
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: SboxColors.slate600)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        FeedbackUi.statusPill(status),
                        if (priority >= 2 && open) FeedbackUi.priorityPill(priority),
                        FeedbackUi.duePill(f),
                        if ((f['topic']?.toString() ?? '').isNotEmpty)
                          FeedbackUi.pill(f['topic'].toString(), SboxColors.slate500),
                        if (FeedbackUi.n(f['reopenCount']) > 0)
                          FeedbackUi.pill('Mở lại ${FeedbackUi.n(f['reopenCount'])} lần', SboxColors.violet),
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        Icon(f['isAnonymous'] == true ? Icons.visibility_off_rounded : Icons.person_outline_rounded,
                            size: 15, color: SboxColors.slate400),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(tr(who),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                        ),
                        const Icon(Icons.arrow_right_alt_rounded, size: 16, color: SboxColors.slate300),
                        Flexible(
                          child: Text(tr(to.toString()),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                        ),
                        const Spacer(),
                        if (rating != null) FeedbackUi.stars(FeedbackUi.n(rating), size: 14),
                        if (FeedbackUi.n(f['replyCount']) > 0) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.chat_bubble_outline_rounded, size: 14, color: SboxColors.slate400),
                          const SizedBox(width: 3),
                          Text('${FeedbackUi.n(f['replyCount'])}',
                              style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                        ],
                      ]),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
