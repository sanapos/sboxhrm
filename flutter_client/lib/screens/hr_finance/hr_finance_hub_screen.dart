import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../models/cash_transaction.dart';
import '../../models/hr_finance.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/store_role_helper.dart';
import '../../widgets/sbox/sbox_ui.dart';
import '../business_trip_expense_screen.dart';
import '../cash_transaction_screen.dart';
import 'hr_fin_actions.dart';
import 'hr_fin_common.dart';
import 'hr_fin_ledger.dart';

/// Các tab của Tài chính nhân sự.
enum HrFinTab { overview, inbox, advances, rewards, cash, people, me, settings }

extension on HrFinTab {
  String get label => switch (this) {
        HrFinTab.overview => 'Tổng quan',
        HrFinTab.inbox => 'Cần xử lý',
        HrFinTab.advances => 'Ứng lương',
        HrFinTab.rewards => 'Thưởng & phạt',
        HrFinTab.cash => 'Sổ quỹ',
        HrFinTab.people => 'Theo nhân viên',
        HrFinTab.me => 'Của tôi',
        HrFinTab.settings => 'Cài đặt',
      };

  IconData get icon => switch (this) {
        HrFinTab.overview => Icons.space_dashboard_outlined,
        HrFinTab.inbox => Icons.inbox_outlined,
        HrFinTab.advances => Icons.payments_outlined,
        HrFinTab.rewards => Icons.emoji_events_outlined,
        HrFinTab.cash => Icons.account_balance_wallet_outlined,
        HrFinTab.people => Icons.people_alt_outlined,
        HrFinTab.me => Icons.person_outline,
        HrFinTab.settings => Icons.tune_rounded,
      };
}

/// Tài chính nhân sự — một cửa cho thu chi, ứng lương, thưởng, phạt, công tác phí.
class HrFinanceHubScreen extends StatefulWidget {
  const HrFinanceHubScreen({super.key, this.initialTab, this.initialRewardKind, this.debugViewer});

  final HrFinTab? initialTab;

  /// '' / bonus / penalty / ticket
  final String? initialRewardKind;
  final HrFinViewer? debugViewer;

  @override
  State<HrFinanceHubScreen> createState() => _HrFinanceHubScreenState();
}

class _HrFinanceHubScreenState extends State<HrFinanceHubScreen> {
  final _api = ApiService();
  late final HrFinActions _actions = HrFinActions(_api, HrFinSettings());
  HrFinViewer _viewer = const HrFinViewer(isManager: false);
  bool _ready = false;
  HrFinTab _tab = HrFinTab.overview;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int _seq = 0;
  bool _loading = false;

  List<HrFinPerson> _people = [];
  HrFinSummary? _summary;
  List<HrFinItem> _inbox = [];
  List<HrFinItem> _advances = [];
  List<HrFinItem> _rewards = [];
  List<CashTransaction> _cash = [];
  HrFinSettings _settings = HrFinSettings();

  String _inboxFilter = '';
  final Set<String> _selected = {};
  String _rewardKind = '';
  String _advanceFilter = '';
  String _peopleSearch = '';
  HrFinPerson? _person;
  HrFinLedger? _ledger;
  bool _ledgerLoading = false;

  @override
  void initState() {
    super.initState();
    _rewardKind = widget.initialRewardKind ?? '';
    _init();
  }

  Future<void> _init() async {
    if (widget.debugViewer != null) {
      _viewer = widget.debugViewer!;
    } else {
      final role = context.read<AuthProvider>().userRole;
      String? empId;
      final me = await _api.getMyEmployee();
      if (me['isSuccess'] == true && me['data'] is Map) {
        final d = me['data'] as Map;
        empId = (d['id'] ?? d['Id'])?.toString();
      }
      _viewer = HrFinViewer(isManager: StoreRoleHelper.isManagerOrAbove(role), employeeId: empId);
    }
    if (!mounted) return;
    setState(() {
      _tab = _viewer.isManager ? (widget.initialTab ?? HrFinTab.overview) : HrFinTab.me;
      _ready = true;
    });
    final s = await _api.getHrFinSettings();
    if (s['isSuccess'] == true && s['data'] is Map) {
      _settings = HrFinSettings.fromJson(Map<String, dynamic>.from(s['data'] as Map));
      _actions.settings = _settings;
    }
    if (_viewer.isManager) {
      final list = await _api.getEmployeesForSelect(pageSize: 500);
      if (mounted) setState(() => _people = HrFinPerson.fromEmployees(list));
    }
    await _load();
  }

  List<HrFinTab> get _tabs => _viewer.isManager
      ? HrFinTab.values
      : const [HrFinTab.me];

  Future<void> _load() async {
    if (!_viewer.isManager) return;
    final seq = ++_seq;
    setState(() => _loading = true);
    final y = _month.year, m = _month.month;
    final futures = <String, Future<Map<String, dynamic>>>{
      if (_tab == HrFinTab.overview || _tab == HrFinTab.cash || _tab == HrFinTab.advances) 'summary': _api.getHrFinSummary(y, m),
      'inbox': _api.getHrFinInbox(),
      if (_tab == HrFinTab.advances) 'advances': _api.getHrFinAdvances(y, m),
      if (_tab == HrFinTab.rewards) 'rewards': _api.getHrFinRewards(y, m),
      if (_tab == HrFinTab.cash)
        'cash': _api.getCashTransactions(pageSize: 100, fromDate: _month, toDate: DateTime(y, m + 1).subtract(const Duration(seconds: 1))),
    };
    final keys = futures.keys.toList();
    final values = await Future.wait(futures.values);
    if (!mounted || seq != _seq) return;
    final r = {for (var i = 0; i < keys.length; i++) keys[i]: values[i]};
    setState(() {
      _loading = false;
      if (r['summary']?['data'] is Map) _summary = HrFinSummary(Map<String, dynamic>.from(r['summary']!['data'] as Map));
      if (r['inbox'] != null) {
        _inbox = HrFinItem.listFrom(r['inbox']!['data']);
        _selected.removeWhere((id) => !_inbox.any((i) => i.id == id));
      }
      if (r['advances'] != null) _advances = HrFinItem.listFrom(r['advances']!['data']);
      if (r['rewards'] != null) _rewards = HrFinItem.listFrom(r['rewards']!['data']);
      if (r['cash'] != null) {
        final d = r['cash']!['data'];
        final list = d is Map ? (d['items'] ?? d['data']) : d;
        _cash = list is List
            ? list.whereType<Map>().map((e) => CashTransaction.fromJson(Map<String, dynamic>.from(e))).toList()
            : [];
      }
    });
  }

  void _setTab(HrFinTab t) {
    setState(() => _tab = t);
    if (t == HrFinTab.people && _person != null && _ledger == null) _loadLedger(_person!);
    _load();
  }

  Future<void> _act(HrFinItem it) async {
    if (await _actions.run(context, it)) _load();
  }

  Future<void> _detail(HrFinItem it) async {
    if (await _actions.showDetail(context, it, canAct: true)) _load();
  }

  void _openLegacy(Widget screen, String title) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: SboxColors.page,
        appBar: AppBar(title: Text(tr(title)), backgroundColor: SboxColors.white, surfaceTintColor: SboxColors.white),
        body: screen,
      ),
    ));
  }

  // ─── Khung ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = SboxSpace.pagePadding(w);
    if (!_ready) return const ColoredBox(color: SboxColors.page, child: SboxLoading());
    final pending = _inbox.length;
    return ColoredBox(
      color: SboxColors.page,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, pad + 24),
          children: [
            SboxPageHeader(
              title: 'Tài chính nhân sự',
              subtitle: _viewer.isManager ? 'Ứng lương · thưởng · phạt · công tác phí · sổ quỹ' : 'Tiền của tôi: ứng lương, thưởng, phạt',
              actions: [
                if (_viewer.isManager) ...[
                  SboxButton.secondary(
                    label: 'Thưởng / phạt',
                    icon: Icons.add_rounded,
                    onPressed: () async {
                      if (await _actions.createReward(context, _people)) _load();
                    },
                  ),
                  SboxButton(
                    label: 'Ứng lương',
                    icon: Icons.add_rounded,
                    onPressed: () async {
                      if (await _actions.requestAdvance(context, people: _people)) _load();
                    },
                  ),
                ],
              ],
            ),
            const SizedBox(height: SboxSpace.md),
            if (_tabs.length > 1) ...[
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final t in _tabs)
                    Padding(
                      padding: const EdgeInsets.only(right: SboxSpace.xs),
                      child: _TabPill(
                        label: t.label,
                        icon: t.icon,
                        selected: t == _tab,
                        badge: t == HrFinTab.inbox && pending > 0 ? pending : null,
                        onTap: () => _setTab(t),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: SboxSpace.md),
            ],
            _body(),
          ],
        ),
      ),
    );
  }

  Widget _monthRow({List<Widget> trailing = const []}) {
    return Wrap(spacing: SboxSpace.sm, runSpacing: SboxSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
      HrFinMonthBar(month: _month, onChanged: (m) {
        setState(() => _month = m);
        _load();
      }),
      if (_loading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
      ...trailing,
    ]);
  }

  Widget _body() => switch (_tab) {
        HrFinTab.overview => _overview(),
        HrFinTab.inbox => _inboxView(),
        HrFinTab.advances => _advancesView(),
        HrFinTab.rewards => _rewardsView(),
        HrFinTab.cash => _cashView(),
        HrFinTab.people => _peopleView(),
        HrFinTab.me => HrFinMyMoney(api: _api, actions: _actions),
        HrFinTab.settings => _SettingsView(api: _api, initial: _settings, onSaved: (s) {
            _settings = s;
            _actions.settings = s;
          }),
      };

  // ─── Tổng quan ─────────────────────────────────────────────────

  Widget _overview() {
    final s = _summary;
    if (s == null) return Column(children: [_monthRow(), const SboxLoading()]);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final approvals = _inbox.where((i) => i.action == 'approve').length;
    final pays = _inbox.where((i) => i.action == 'pay').toList();
    final disputes = _inbox.where((i) => i.action == 'resolve').length;
    final labels = [for (final d in s.daily) '${d.date.day}'];

    final todo = SboxCard(
      title: 'Việc cần làm',
      trailing: SboxButton.ghost(label: 'Mở hộp duyệt', size: SboxButtonSize.sm, onPressed: () => _setTab(HrFinTab.inbox)),
      child: Column(children: [
        _TodoRow(icon: Icons.fact_check_outlined, tone: SboxTone.warning, label: 'Chờ duyệt', value: '$approvals', onTap: () {
          _inboxFilter = 'approve';
          _setTab(HrFinTab.inbox);
        }),
        _TodoRow(
            icon: Icons.payments_outlined,
            tone: SboxTone.brand,
            label: 'Chờ chi / thu',
            value: '${pays.length} · ${hrFinMoney(pays.fold<double>(0, (a, b) => a + b.amount))}',
            onTap: () {
              _inboxFilter = 'pay';
              _setTab(HrFinTab.inbox);
            }),
        _TodoRow(icon: Icons.feedback_outlined, tone: SboxTone.danger, label: 'Khiếu nại', value: '$disputes', onTap: () {
          _inboxFilter = 'resolve';
          _setTab(HrFinTab.inbox);
        }),
      ]),
    );

    final charts = <Widget>[
      SboxChartCard(
        title: 'Tiền chi cho nhân viên',
        subtitle: hrFinMonthLabel(_month),
        child: SboxDonutChart(
          slices: [for (final b in s.breakdown) if (b.amount > 0) SboxSlice(b.label, b.amount)],
          centerLabel: 'Tổng',
          centerValue: SboxFmt.compact(s.breakdown.fold<double>(0, (a, b) => a + b.amount)),
        ),
      ),
      SboxChartCard(
        title: 'Thưởng / phạt theo nhân viên',
        subtitle: 'Nhiều nhất trong tháng',
        child: SboxBarChart(
          labels: [for (final e in s.topEmployees.take(8)) e.name.split(' ').last],
          series: [
            SboxSeries(name: 'Thưởng', values: [for (final e in s.topEmployees.take(8)) e.bonus], color: SboxColors.success),
            SboxSeries(name: 'Phạt', values: [for (final e in s.topEmployees.take(8)) e.penalty], color: SboxColors.danger),
          ],
          height: 220,
        ),
      ),
      SboxChartCard(
        title: 'Dòng tiền sổ quỹ theo ngày',
        subtitle: 'Phiếu thu / chi đã hoàn tất',
        wide: true,
        child: SboxLineChart(
          labels: labels,
          series: [
            SboxSeries(name: 'Thu', values: [for (final d in s.daily) d.cashIn], color: SboxColors.success),
            SboxSeries(name: 'Chi', values: [for (final d in s.daily) d.cashOut], color: SboxColors.danger),
          ],
          height: 220,
        ),
      ),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _monthRow(),
      const SizedBox(height: SboxSpace.md),
      SboxKpiStrip(items: [
        SboxKpi(label: 'Ứng lương đã chi', value: hrFinMoney(s.n('advancePaid')), icon: Icons.payments_outlined,
            note: 'Trừ lương kỳ này ${hrFinMoney(s.n('advanceToDeduct'))}', onTap: () => _setTab(HrFinTab.advances)),
        SboxKpi(label: 'Thưởng', value: hrFinMoney(s.n('bonus')), icon: Icons.card_giftcard_outlined, tone: SboxTone.success,
            onTap: () {
              _rewardKind = 'bonus';
              _setTab(HrFinTab.rewards);
            }),
        SboxKpi(label: 'Phạt', value: hrFinMoney(s.n('penalty')), icon: Icons.gavel_outlined, tone: SboxTone.danger,
            note: 'Phiếu phạt ${hrFinMoney(s.n('ticketPenalty'))}', onTap: () {
              _rewardKind = 'penalty';
              _setTab(HrFinTab.rewards);
            }),
        SboxKpi(label: 'Công tác phí', value: hrFinMoney(s.n('tripSettled')), icon: Icons.flight_takeoff_outlined, tone: SboxTone.violet,
            note: 'Ứng công tác ${hrFinMoney(s.n('tripAdvancePaid'))}'),
        SboxKpi(label: 'Thu quỹ', value: hrFinMoney(s.n('cashIn')), icon: Icons.south_west_rounded, tone: SboxTone.success,
            onTap: () => _setTab(HrFinTab.cash)),
        SboxKpi(label: 'Chi quỹ', value: hrFinMoney(s.n('cashOut')), icon: Icons.north_east_rounded, tone: SboxTone.warning,
            onTap: () => _setTab(HrFinTab.cash)),
      ]),
      const SizedBox(height: SboxSpace.md),
      if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 2, child: todo),
          const SizedBox(width: SboxSpace.md),
          Expanded(flex: 3, child: charts[0]),
        ])
      else ...[
        todo,
        const SizedBox(height: SboxSpace.md),
        charts[0],
      ],
      const SizedBox(height: SboxSpace.md),
      ...sboxChartRows(charts.sublist(1), twoCol: wide, gap: SboxSpace.md),
    ]);
  }

  // ─── Hộp duyệt ─────────────────────────────────────────────────

  Widget _inboxView() {
    final list = _inbox.where((i) => _inboxFilter.isEmpty || i.action == _inboxFilter).toList();
    final selectable = list.where((i) => i.action == 'approve' && !i.isTrip && i.kind != 'advance').toList();
    final counts = {
      '': _inbox.length,
      'approve': _inbox.where((i) => i.action == 'approve').length,
      'pay': _inbox.where((i) => i.action == 'pay').length,
      'resolve': _inbox.where((i) => i.action == 'resolve').length,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      HrFinSegment<String>(
        value: _inboxFilter,
        options: {
          '': 'Tất cả (${counts['']})',
          'approve': 'Chờ duyệt (${counts['approve']})',
          'pay': 'Chờ chi / thu (${counts['pay']})',
          'resolve': 'Khiếu nại (${counts['resolve']})',
        },
        onChanged: (v) => setState(() {
          _inboxFilter = v;
          _selected.clear();
        }),
      ),
      if (selectable.isNotEmpty) ...[
        const SizedBox(height: SboxSpace.sm),
        Row(children: [
          TextButton.icon(
            onPressed: () => setState(() {
              if (_selected.length == selectable.length) {
                _selected.clear();
              } else {
                _selected
                  ..clear()
                  ..addAll(selectable.map((e) => e.id));
              }
            }),
            icon: const Icon(Icons.checklist_rounded, size: 18),
            label: Text(tr(_selected.length == selectable.length ? 'Bỏ chọn' : 'Chọn tất cả thưởng/phạt')),
          ),
          const Spacer(),
          if (_selected.isNotEmpty)
            SboxButton(label: 'Duyệt ${_selected.length} phiếu', icon: Icons.done_all_rounded, size: SboxButtonSize.sm, onPressed: _bulkApprove),
        ]),
      ],
      const SizedBox(height: SboxSpace.sm),
      HrFinItemList(
        emptyIcon: Icons.task_alt_rounded,
        emptyTitle: 'Không có việc cần xử lý',
        emptyMessage: 'Yêu cầu ứng lương, phiếu thưởng/phạt, công tác phí chờ duyệt sẽ hiện ở đây',
        children: [
          for (final it in list)
            HrFinItemTile(
              item: it,
              onTap: () => _detail(it),
              onAction: () => _act(it),
              selected: _selected.contains(it.id),
              onSelect: selectable.contains(it) ? (v) => setState(() => v ? _selected.add(it.id) : _selected.remove(it.id)) : null,
            ),
        ],
      ),
    ]);
  }

  Future<void> _bulkApprove() async {
    final items = _inbox.where((i) => _selected.contains(i.id)).toList();
    final ok = await SboxDialogs.confirm(context,
        title: 'Duyệt ${items.length} phiếu?',
        message: 'Thưởng/phạt được xử lý theo cài đặt mặc định (trừ/cộng lương hoặc tiền mặt). Phiếu phạt tự động được duyệt trừ lương.',
        confirmLabel: 'Duyệt tất cả');
    if (!ok || !mounted) return;
    var done = 0;
    for (final it in items) {
      final Map<String, dynamic> r;
      if (it.kind == 'ticket') {
        r = await _api.approvePenaltyTicket(it.id);
      } else {
        final st = it.settlement ?? (it.kind == 'penalty' ? _settings.penaltyDefaultSettlement : _settings.bonusDefaultSettlement);
        r = await _api.updateTransactionStatus(it.id, 'Completed', disbursementMode: st == 'cash' ? 'Cash' : 'Salary');
      }
      if (r['isSuccess'] == true) done++;
    }
    if (!mounted) return;
    hrFinToast(context, 'Đã duyệt $done/${items.length} phiếu', error: done < items.length);
    _selected.clear();
    _load();
  }

  // ─── Ứng lương ─────────────────────────────────────────────────

  Widget _advancesView() {
    final all = _advances;
    final list = all.where((i) => switch (_advanceFilter) {
          'approve' => i.action == 'approve',
          'pay' => i.action == 'pay',
          'paid' => i.status == 'Paid',
          'rejected' => i.isCancelled,
          _ => true,
        }).toList();
    double sum(bool Function(HrFinItem) f) => all.where(f).fold(0, (a, b) => a + b.amount);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _monthRow(),
      const SizedBox(height: SboxSpace.md),
      SboxKpiStrip(maxColumns: 4, items: [
        SboxKpi(label: 'Chờ duyệt', value: hrFinMoney(sum((i) => i.action == 'approve')), icon: Icons.hourglass_top_rounded, tone: SboxTone.warning,
            note: '${all.where((i) => i.action == 'approve').length} yêu cầu'),
        SboxKpi(label: 'Đã duyệt · chờ chi', value: hrFinMoney(sum((i) => i.action == 'pay')), icon: Icons.payments_outlined,
            note: '${all.where((i) => i.action == 'pay').length} yêu cầu'),
        SboxKpi(label: 'Đã chi trong tháng', value: hrFinMoney(_summary?.n('advancePaid') ?? 0), icon: Icons.task_alt_rounded, tone: SboxTone.success),
        SboxKpi(label: 'Trừ lương kỳ này', value: hrFinMoney(_summary?.n('advanceToDeduct') ?? 0), icon: Icons.receipt_long_outlined, tone: SboxTone.violet,
            note: 'Theo kỳ trừ + trả góp'),
      ]),
      const SizedBox(height: SboxSpace.md),
      HrFinSegment<String>(
        value: _advanceFilter,
        options: const {'': 'Tất cả', 'approve': 'Chờ duyệt', 'pay': 'Chờ chi', 'paid': 'Đã chi', 'rejected': 'Từ chối / hủy'},
        onChanged: (v) => setState(() => _advanceFilter = v),
      ),
      const SizedBox(height: SboxSpace.sm),
      HrFinItemList(
        emptyIcon: Icons.payments_outlined,
        emptyTitle: 'Chưa có yêu cầu ứng lương',
        children: [for (final it in list) HrFinItemTile(item: it, onTap: () => _detail(it), onAction: () => _act(it))],
      ),
    ]);
  }

  // ─── Thưởng & phạt ─────────────────────────────────────────────

  Widget _rewardsView() {
    final list = _rewards.where((i) => switch (_rewardKind) {
          'bonus' => i.kind == 'bonus',
          'penalty' => i.kind == 'penalty' || i.kind == 'ticket',
          'ticket' => i.kind == 'ticket',
          _ => true,
        }).toList();
    double sum(bool Function(HrFinItem) f) => _rewards.where((i) => i.isApproved && f(i)).fold(0, (a, b) => a + b.amount);
    final byReason = <String, double>{};
    for (final i in _rewards.where((i) => i.isApproved && i.isPenalty)) {
      final k = i.kind == 'ticket' ? i.title.replaceAll(RegExp(r'\s\d+ phút$'), '') : 'Phạt thủ công';
      byReason[k] = (byReason[k] ?? 0) + i.amount;
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _monthRow(),
      const SizedBox(height: SboxSpace.md),
      SboxKpiStrip(maxColumns: 4, items: [
        SboxKpi(label: 'Thưởng đã duyệt', value: hrFinMoney(sum((i) => i.kind == 'bonus')), icon: Icons.card_giftcard_outlined, tone: SboxTone.success),
        SboxKpi(label: 'Phạt thủ công', value: hrFinMoney(sum((i) => i.kind == 'penalty')), icon: Icons.gavel_outlined, tone: SboxTone.danger),
        SboxKpi(label: 'Phiếu phạt chấm công', value: hrFinMoney(sum((i) => i.kind == 'ticket')), icon: Icons.alarm_outlined, tone: SboxTone.warning),
        SboxKpi(label: 'Đang khiếu nại', value: '${_rewards.where((i) => i.isDisputeOpen).length}', icon: Icons.feedback_outlined, tone: SboxTone.violet),
      ]),
      if (byReason.isNotEmpty) ...[
        const SizedBox(height: SboxSpace.md),
        SboxChartCard(
          title: 'Phạt theo lý do',
          child: SboxRankList(
            items: [for (final e in (byReason.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) SboxSlice(e.key, e.value)],
            color: SboxColors.danger,
          ),
        ),
      ],
      const SizedBox(height: SboxSpace.md),
      Row(children: [
        Expanded(
          child: HrFinSegment<String>(
            value: _rewardKind,
            options: const {'': 'Tất cả', 'bonus': 'Thưởng', 'penalty': 'Phạt', 'ticket': 'Phiếu phạt tự động'},
            onChanged: (v) => setState(() => _rewardKind = v),
          ),
        ),
      ]),
      const SizedBox(height: SboxSpace.sm),
      HrFinItemList(
        emptyIcon: Icons.emoji_events_outlined,
        emptyTitle: 'Chưa có phiếu trong tháng',
        children: [for (final it in list) HrFinItemTile(item: it, onTap: () => _detail(it), onAction: () => _act(it))],
      ),
    ]);
  }

  // ─── Sổ quỹ ────────────────────────────────────────────────────

  Widget _cashView() {
    final s = _summary;
    final pending = _cash.where((c) => !c.isPaid && c.status != CashTransactionStatus.cancelled).toList();
    final byCat = <String, double>{};
    for (final c in _cash.where((c) => c.isPaid && c.type == CashTransactionType.expense)) {
      final k = c.categoryName.isEmpty ? 'Khác' : c.categoryName;
      byCat[k] = (byCat[k] ?? 0) + c.amount;
    }
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _monthRow(trailing: [
        SboxButton(label: 'Mở sổ quỹ đầy đủ', icon: Icons.open_in_new_rounded, size: SboxButtonSize.sm,
            onPressed: () => _openLegacy(const CashTransactionScreen(), 'Sổ quỹ thu chi')),
        SboxButton.ghost(label: 'Công tác phí', icon: Icons.flight_takeoff_outlined, size: SboxButtonSize.sm,
            onPressed: () => _openLegacy(const BusinessTripExpenseScreen(), 'Công tác phí')),
      ]),
      const SizedBox(height: SboxSpace.md),
      SboxKpiStrip(maxColumns: 4, items: [
        SboxKpi(label: 'Tổng thu', value: hrFinMoney(s?.n('cashIn') ?? 0), icon: Icons.south_west_rounded, tone: SboxTone.success),
        SboxKpi(label: 'Tổng chi', value: hrFinMoney(s?.n('cashOut') ?? 0), icon: Icons.north_east_rounded, tone: SboxTone.danger),
        SboxKpi(label: 'Chênh lệch', value: hrFinMoney((s?.n('cashIn') ?? 0) - (s?.n('cashOut') ?? 0)), icon: Icons.balance_rounded),
        SboxKpi(label: 'Chờ thanh toán', value: '${pending.length}', icon: Icons.hourglass_top_rounded, tone: SboxTone.warning,
            note: hrFinMoney(pending.fold<double>(0, (a, b) => a + b.amount))),
      ]),
      const SizedBox(height: SboxSpace.md),
      ...sboxChartRows([
        SboxChartCard(
          title: 'Thu chi theo ngày',
          child: SboxBarChart(
            labels: [for (final d in s?.daily ?? const <({DateTime date, double cashIn, double cashOut})>[]) '${d.date.day}'],
            series: [
              SboxSeries(name: 'Thu', values: [for (final d in s?.daily ?? const <({DateTime date, double cashIn, double cashOut})>[]) d.cashIn], color: SboxColors.success),
              SboxSeries(name: 'Chi', values: [for (final d in s?.daily ?? const <({DateTime date, double cashIn, double cashOut})>[]) d.cashOut], color: SboxColors.danger),
            ],
            height: 220,
          ),
        ),
        SboxChartCard(
          title: 'Chi theo danh mục',
          child: SboxRankList(items: [for (final e in (byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))) SboxSlice(e.key, e.value)]),
        ),
      ], twoCol: wide, gap: SboxSpace.md),
      const SizedBox(height: SboxSpace.md),
      Text(tr('Phiếu gần đây'), style: SboxType.titleSmStyle()),
      const SizedBox(height: SboxSpace.sm),
      HrFinItemList(
        emptyIcon: Icons.account_balance_wallet_outlined,
        emptyTitle: 'Chưa có phiếu thu chi trong tháng',
        children: [
          for (final c in _cash.take(60))
            HrFinItemTile(
              showEmployee: false,
              item: HrFinItem(
                kind: 'cash',
                id: c.id,
                code: c.transactionCode,
                title: c.description.isEmpty ? c.categoryName : c.description,
                subtitle: [c.categoryName, if (c.contactName != null && c.contactName!.isNotEmpty) c.contactName!].join(' · '),
                amount: c.amount,
                direction: c.type == CashTransactionType.expense ? 'out' : 'in',
                status: c.isPaid ? 'Completed' : (c.status == CashTransactionStatus.cancelled ? 'Cancelled' : 'WaitingPayment'),
                date: c.transactionDate,
                action: !c.isPaid && c.status != CashTransactionStatus.cancelled ? 'pay' : null,
                evidence: [if (c.receiptImageUrl != null && c.receiptImageUrl!.isNotEmpty) c.receiptImageUrl!],
              ),
              onAction: () async {
                final it = HrFinItem(
                    kind: 'cash', id: c.id, title: c.description, amount: c.amount,
                    direction: c.type == CashTransactionType.expense ? 'in' : 'out', date: c.transactionDate, action: 'pay');
                if (await _actions.payCash(context, it)) _load();
              },
            ),
        ],
      ),
    ]);
  }

  // ─── Theo nhân viên ────────────────────────────────────────────

  Future<void> _loadLedger(HrFinPerson p) async {
    setState(() {
      _person = p;
      _ledgerLoading = true;
    });
    final now = DateTime.now();
    final r = await _api.getHrFinLedger(p.id, from: DateTime(now.year, now.month - 5), to: DateTime(now.year, now.month + 1));
    if (!mounted || _person?.id != p.id) return;
    setState(() {
      _ledgerLoading = false;
      _ledger = r['isSuccess'] == true && r['data'] is Map ? HrFinLedger.fromJson(Map<String, dynamic>.from(r['data'] as Map)) : null;
    });
  }

  Widget _peopleView() {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final q = _peopleSearch.trim().toLowerCase();
    final people = _people.where((p) => q.isEmpty || p.name.toLowerCase().contains(q) || (p.code ?? '').toLowerCase().contains(q)).toList();
    final list = Container(
      decoration: BoxDecoration(color: SboxColors.white, borderRadius: SboxRadius.lgAll, border: Border.all(color: SboxColors.border)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(SboxSpace.sm),
          child: TextField(
            decoration: hrFinInput('Tìm nhân viên').copyWith(prefixIcon: const Icon(Icons.search_rounded, size: 18)),
            onChanged: (v) => setState(() => _peopleSearch = v),
          ),
        ),
        const Divider(height: 1),
        SizedBox(
          height: wide ? 560 : 320,
          child: ListView.separated(
            itemCount: people.length,
            separatorBuilder: (_, __) => const Divider(height: 1, color: SboxColors.divider),
            itemBuilder: (_, i) {
              final p = people[i];
              final sel = p.id == _person?.id;
              return ListTile(
                selected: sel,
                selectedTileColor: SboxColors.brand50,
                dense: true,
                leading: HrFinAvatar(name: p.name, photo: p.photo, size: 32),
                title: Text(p.name, style: SboxType.bodyStrong()),
                subtitle: Text([p.code, p.department].whereType<String>().where((e) => e.isNotEmpty).join(' · '), style: SboxType.captionStyle()),
                onTap: () => _loadLedger(p),
              );
            },
          ),
        ),
      ]),
    );
    final detail = _person == null
        ? const SboxEmptyState(icon: Icons.person_search_outlined, title: 'Chọn một nhân viên', message: 'Xem toàn bộ ứng lương, thưởng, phạt, công tác 6 tháng gần nhất')
        : _ledgerLoading || _ledger == null
            ? const SboxLoading()
            : HrFinLedgerView(
                ledger: _ledger!,
                onTapItem: (it) => _detail(it),
                header: Row(children: [
                  HrFinAvatar(name: _ledger!.employeeName, photo: _ledger!.photoUrl, size: 44),
                  const SizedBox(width: SboxSpace.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_ledger!.employeeName, style: SboxType.titleStyle()),
                      Text('6 tháng gần nhất · ${[_ledger!.employeeCode, _ledger!.department].whereType<String>().join(' · ')}',
                          style: SboxType.captionStyle()),
                    ]),
                  ),
                  SboxButton.secondary(
                    label: 'Thưởng / phạt',
                    icon: Icons.add_rounded,
                    size: SboxButtonSize.sm,
                    onPressed: () async {
                      if (await _actions.createReward(context, _people, preset: _person)) _loadLedger(_person!);
                    },
                  ),
                ]),
              );
    if (wide) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 320, child: list),
        const SizedBox(width: SboxSpace.md),
        Expanded(child: detail),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [list, const SizedBox(height: SboxSpace.md), detail]);
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({required this.label, required this.icon, required this.selected, required this.onTap, this.badge});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? SboxColors.brand600 : SboxColors.white,
      shape: StadiumBorder(side: BorderSide(color: selected ? SboxColors.brand600 : SboxColors.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: selected ? SboxColors.white : SboxColors.slate500),
            const SizedBox(width: 6),
            Text(tr(label), style: SboxType.smallStyle(selected ? SboxColors.white : SboxColors.text).copyWith(fontWeight: FontWeight.w600)),
            if (badge != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: selected ? SboxColors.white : SboxColors.danger, borderRadius: SboxRadius.pillAll),
                child: Text('$badge',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: selected ? SboxColors.brand700 : SboxColors.white)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _TodoRow extends StatelessWidget {
  const _TodoRow({required this.icon, required this.tone, required this.label, required this.value, required this.onTap});
  final IconData icon;
  final SboxTone tone;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: SboxRadius.mdAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SboxSpace.sm),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: tone.bg, borderRadius: SboxRadius.mdAll),
            child: Icon(icon, size: 18, color: tone.fg),
          ),
          const SizedBox(width: SboxSpace.md),
          Expanded(child: Text(tr(label), style: SboxType.bodyStyle())),
          Text(value, style: SboxType.bodyStrong()),
          const Icon(Icons.chevron_right_rounded, color: SboxColors.slate400),
        ]),
      ),
    );
  }
}

// ─── Cài đặt ─────────────────────────────────────────────────────

class _SettingsView extends StatefulWidget {
  const _SettingsView({required this.api, required this.initial, required this.onSaved});
  final ApiService api;
  final HrFinSettings initial;
  final ValueChanged<HrFinSettings> onSaved;

  @override
  State<_SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<_SettingsView> {
  late final HrFinSettings s = HrFinSettings.fromJson(widget.initial.toJson());
  late final _pct = TextEditingController(text: s.advanceLimitPercent?.toStringAsFixed(0) ?? '');
  late final _amt = TextEditingController(text: s.advanceLimitAmount == null ? '' : hrFinMoneyText(s.advanceLimitAmount!));
  late final _times = TextEditingController(text: s.advanceMaxRequestsPerPeriod?.toString() ?? '');
  late final _days = TextEditingController(text: '${s.disputeWindowDays}');
  bool _saving = false;

  Future<void> _save() async {
    s.advanceLimitPercent = double.tryParse(_pct.text.trim());
    s.advanceLimitAmount = hrFinParseMoney(_amt.text);
    s.advanceMaxRequestsPerPeriod = int.tryParse(_times.text.trim());
    s.disputeWindowDays = int.tryParse(_days.text.trim()) ?? 7;
    setState(() => _saving = true);
    final r = await widget.api.saveHrFinSettings(s.toJson());
    if (!mounted) return;
    setState(() => _saving = false);
    if (hrFinResult(context, r, 'Đã lưu cài đặt')) widget.onSaved(s);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final advance = SboxCard(
      title: 'Hạn mức ứng lương',
      subtitle: 'Áp dụng mỗi kỳ lương, lấy mức nhỏ hơn giữa % lương và số tiền',
      child: Column(children: [
        TextField(controller: _pct, keyboardType: TextInputType.number,
            decoration: hrFinInput('% lương tháng ước tính', suffix: '%', helper: 'Để trống = không giới hạn theo %. Lương ước tính theo chế độ lương đang áp dụng (ngày × 26, giờ × 8 × 26).')),
        const SizedBox(height: SboxSpace.md),
        TextField(controller: _amt, keyboardType: TextInputType.number, inputFormatters: [HrFinMoneyFormatter()],
            decoration: hrFinInput('Số tiền tối đa mỗi kỳ', suffix: '₫', helper: 'Để trống = không giới hạn theo số tiền')),
        const SizedBox(height: SboxSpace.md),
        Row(children: [
          Expanded(child: TextField(controller: _times, keyboardType: TextInputType.number, decoration: hrFinInput('Số lần ứng tối đa / kỳ'))),
          const SizedBox(width: SboxSpace.sm),
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: s.advanceMaxInstallments.clamp(1, 12),
              decoration: hrFinInput('Trả góp tối đa'),
              items: [for (var i = 1; i <= 12; i++) DropdownMenuItem(value: i, child: Text(i == 1 ? 'Không trả góp' : '$i kỳ'))],
              onChanged: (v) => setState(() => s.advanceMaxInstallments = v ?? 3),
            ),
          ),
        ]),
      ]),
    );
    final reward = SboxCard(
      title: 'Thưởng / phạt',
      subtitle: 'Cách xử lý tiền mặc định khi duyệt',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Thưởng'), style: SboxType.captionStyle()),
        const SizedBox(height: 4),
        HrFinSettlementPicker(value: s.bonusDefaultSettlement, isPenalty: false, onChanged: (v) => setState(() => s.bonusDefaultSettlement = v)),
        const SizedBox(height: SboxSpace.md),
        Text(tr('Phạt'), style: SboxType.captionStyle()),
        const SizedBox(height: 4),
        HrFinSettlementPicker(value: s.penaltyDefaultSettlement, isPenalty: true, onChanged: (v) => setState(() => s.penaltyDefaultSettlement = v)),
        const SizedBox(height: SboxSpace.md),
        TextField(controller: _days, keyboardType: TextInputType.number,
            decoration: hrFinInput('Hạn khiếu nại phiếu phạt', suffix: 'ngày', helper: '0 = không giới hạn')),
      ]),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: advance),
          const SizedBox(width: SboxSpace.md),
          Expanded(child: reward),
        ])
      else ...[
        advance,
        const SizedBox(height: SboxSpace.md),
        reward,
      ],
      const SizedBox(height: SboxSpace.md),
      Align(
        alignment: Alignment.centerRight,
        child: SboxButton(label: 'Lưu cài đặt', icon: Icons.save_outlined, loading: _saving, onPressed: _save),
      ),
    ]);
  }
}
