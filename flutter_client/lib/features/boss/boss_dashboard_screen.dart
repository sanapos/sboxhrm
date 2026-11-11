import 'dart:async';

import 'package:flutter/material.dart';

import 'boss_load_error.dart';

import '../../l10n/app_tr.dart';
import '../../screens/staff/staff_nav.dart';
import '../../services/api_service.dart';
import '../../services/branch_session.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/sbox/sbox_basics.dart';
import '../../widgets/sbox/sbox_charts.dart';
import 'boss_issues_card.dart';
import 'boss_overview_sheets.dart';
import 'boss_reports_screen.dart';
import 'boss_staff_today_screen.dart';

/// SBOX BOSS — «Tổng quan hôm nay»: doanh thu ngày kinh doanh hiện tại so với cùng giờ hôm qua /
/// tuần trước, doanh thu theo giờ, phương thức thanh toán, bàn đang mở, nhân viên đã chấm công.
/// Tự làm mới mỗi phút khi đang mở và khi đổi chi nhánh.
class BossDashboardScreen extends StatefulWidget {
  const BossDashboardScreen({super.key, this.onOpenInbox});

  /// Chuyển sang tab «Cần duyệt» (khối «Cần xử lý»).
  final VoidCallback? onOpenInbox;

  @override
  State<BossDashboardScreen> createState() => _BossDashboardScreenState();
}

class _BossDashboardScreenState extends State<BossDashboardScreen> with WidgetsBindingObserver {
  static const _refreshEvery = Duration(seconds: 60);

  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = false;
  Timer? _timer;
  String? _branch;
  /// Tăng khi người dùng làm mới / đổi chi nhánh → khối «Cần xử lý» tải lại (không theo nhịp 1 phút).
  int _issuesTick = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _branch = BranchSession.instance.currentId;
    BranchSession.instance.addListener(_onBranchChanged);
    _load();
    _timer = Timer.periodic(_refreshEvery, (_) => _load(silent: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    BranchSession.instance.removeListener(_onBranchChanged);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(silent: true);
  }

  void _onBranchChanged() {
    final id = BranchSession.instance.currentId;
    if (id == _branch) return;
    _branch = id;
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (_loading) return;
    _loading = true;
    if (!silent && mounted) {
      setState(() {
        _error = null;
        _issuesTick++;
      });
    }
    final r = await ApiService().getBossDashboard();
    _loading = false;
    if (!mounted) return;
    setState(() {
      if (r['isSuccess'] == true && r['data'] is Map) {
        _data = Map<String, dynamic>.from(r['data'] as Map);
        _error = null;
      } else if (!silent || _data == null) {
        _error = r['message']?.toString() ?? 'Không tải được số liệu';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (d == null) {
      if (_error != null) {
        return BossLoadError(title: 'Không tải được số liệu', message: _error, onRetry: _load);
      }
      return const SboxLoading(message: 'Đang tải số liệu hôm nay…');
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        // Đáy chừa chỗ cho nút nổi «+» (trước che thẻ «Hôm qua cả ngày» và dòng «Cập nhật lúc»).
        padding: const EdgeInsets.fromLTRB(SboxSpace.lg, SboxSpace.md, SboxSpace.lg, 104),
        children: [
          _RevenueHero(data: d),
          const SizedBox(height: SboxSpace.md),
          BossIssuesCard(refreshTick: _issuesTick, onOpenInbox: widget.onOpenInbox),
          const SizedBox(height: SboxSpace.md),
          _MoneyCard(data: d),
          if (_hasAnomalies(d)) ...[
            const SizedBox(height: SboxSpace.md),
            _AnomaliesCard(data: d),
          ],
          const SizedBox(height: SboxSpace.md),
          _CompareRow(data: d),
          const SizedBox(height: SboxSpace.md),
          _HourlyChart(data: d),
          const SizedBox(height: SboxSpace.md),
          _PaymentsCard(data: d),
          const SizedBox(height: SboxSpace.md),
          _LiveRow(data: d),
          const SizedBox(height: SboxSpace.md),
          Center(
            child: Text(
              tr('Cập nhật lúc ${_hhmm(d['generatedAt'])} · kéo xuống để làm mới'),
              style: SboxType.captionStyle(),
            ),
          ),
        ],
      ),
    );
  }
}

double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};

String _hhmm(Object? isoUtc) {
  final t = DateTime.tryParse('${isoUtc ?? ''}');
  if (t == null) return '—';
  final l = t.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// % thay đổi so với kỳ trước; null khi kỳ trước bằng 0 (không so được).
double? bossDeltaPct(double current, double previous) =>
    previous <= 0 ? null : (current - previous) / previous * 100;

class _RevenueHero extends StatelessWidget {
  const _RevenueHero({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final today = _map(data['today']);
    final ySame = _map(data['yesterdaySameTime']);
    final revenue = _num(today['revenue']);
    final delta = bossDeltaPct(revenue, _num(ySame['revenue']));
    final unpaid = _num(today['unpaid']);
    final discount = _num(today['discount']);
    // Máy chủ cũ chưa trả lãi gộp → không hiện dòng này.
    final gross = today['grossProfit'] is num ? _num(today['grossProfit']) : null;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [SboxColors.brand700, SboxColors.brand500],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: SboxRadius.lgAll,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            onTap: () => bossOpenReport(context, BossReportType.business),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(SboxSpace.lg, SboxSpace.lg, SboxSpace.sm, SboxSpace.sm),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(tr('Doanh thu hôm nay'), style: SboxType.smallStyle(SboxColors.brand100))),
                  IconButton(
                    tooltip: tr('Các số tính thế nào?'),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.help_outline_rounded, color: SboxColors.white, size: 20),
                    onPressed: () => showBossNumbersHelp(context),
                  ),
                ]),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(SboxFmt.money(revenue),
                      style: SboxType.moneyStyle(size: SboxType.display, c: SboxColors.white)),
                ),
                const SizedBox(height: SboxSpace.sm),
                Row(children: [
                  Flexible(child: _DeltaPill(delta: delta, caption: 'so với cùng giờ hôm qua')),
                  const SizedBox(width: SboxSpace.xs),
                  const Icon(Icons.chevron_right_rounded, color: SboxColors.brand100, size: 18),
                ]),
                if (discount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: SboxSpace.xs),
                    child: Text(tr('Đã giảm giá ${SboxFmt.money(discount)}'),
                        style: SboxType.captionStyle(SboxColors.brand100)),
                  ),
              ]),
            ),
          ),
          // Lãi gộp = doanh thu − giá vốn (như báo cáo Lãi lỗ) — trước Tổng quan chỉ có doanh thu.
          if (gross != null)
            InkWell(
              onTap: () => bossOpenReport(context, BossReportType.pnl),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(SboxSpace.lg, 0, SboxSpace.sm, SboxSpace.xs),
                child: Row(children: [
                  Text(tr('Lãi gộp'), style: SboxType.smallStyle(SboxColors.brand100)),
                  const SizedBox(width: SboxSpace.sm),
                  Text(SboxFmt.money(gross), style: SboxType.moneyStyle(size: SboxType.body, c: SboxColors.white)),
                  if (revenue > 0) ...[
                    const SizedBox(width: SboxSpace.xs),
                    Text('(${SboxFmt.pct(gross / revenue * 100)})', style: SboxType.captionStyle(SboxColors.brand100)),
                  ],
                  const Icon(Icons.chevron_right_rounded, color: SboxColors.brand100, size: 18),
                ]),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(SboxSpace.sm, 0, SboxSpace.sm, SboxSpace.sm),
            child: Row(children: [
              _HeroStat(
                label: 'Số đơn',
                value: SboxFmt.number(_num(today['orderCount'])),
                onTap: () => showBossOrdersSheet(context, title: 'Đơn hôm nay'),
              ),
              _HeroStat(
                label: 'TB / đơn',
                value: SboxFmt.compact(_num(today['avgOrder'])),
                onTap: () => bossOpenReport(context, BossReportType.business),
              ),
              _HeroStat(
                label: 'Đã thu',
                value: SboxFmt.compact(_num(today['collected'])),
                onTap: () => bossOpenEndOfDay(context),
              ),
              _HeroStat(
                label: 'Chưa thu',
                value: unpaid > 0 ? SboxFmt.compact(unpaid) : '0',
                highlight: unpaid > 0,
                onTap: () => showBossOrdersSheet(context, title: 'Đơn khách còn nợ hôm nay', kind: 'unpaid'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value, required this.onTap, this.highlight = false});

  final String label;
  final String value;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          borderRadius: SboxRadius.mdAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SboxSpace.sm, vertical: SboxSpace.xs),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(label), style: SboxType.captionStyle(SboxColors.brand100)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: SboxType.moneyStyle(
                        size: SboxType.titleSm, c: highlight ? const Color(0xFFFFE08A) : SboxColors.white)),
              ),
            ]),
          ),
        ),
      );
}

/// Khối «Tiền hôm nay»: thu, chi, thu − chi — bấm từng dòng ra Cuối ngày / Chi phí / Sổ quỹ.
class _MoneyCard extends StatelessWidget {
  const _MoneyCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final t = _map(data['today']);
    final collected = _num(t['collected']);
    final expense = _num(t['expense']);
    final cashIn = _num(t['collectedCash']);
    final cashOut = _num(t['expenseCash']);
    Widget row(IconData icon, String label, String value, String? sub, Color color, VoidCallback onTap) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SboxSpace.lg, vertical: SboxSpace.sm),
            child: Row(children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: SboxSpace.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(label), style: SboxType.bodyStyle()),
                  if (sub != null) Text(tr(sub), style: SboxType.captionStyle()),
                ]),
              ),
              Text(value, style: SboxType.moneyStyle(size: SboxType.body, c: color)),
              const Icon(Icons.chevron_right_rounded, color: SboxColors.slate400),
            ]),
          ),
        );
    return SboxCard(
      title: 'Tiền hôm nay',
      padding: EdgeInsets.zero,
      child: Column(children: [
        row(Icons.south_west_rounded, 'Đã thu', SboxFmt.money(collected), 'Tiền mặt ${SboxFmt.money(cashIn)}',
            SboxColors.successText, () => bossOpenEndOfDay(context)),
        const Divider(height: 1),
        row(Icons.north_east_rounded, 'Đã chi', SboxFmt.money(expense),
            '${SboxFmt.number(_num(t['expenseCount']))} phiếu chi · tiền mặt ${SboxFmt.money(cashOut)}',
            SboxColors.dangerText, () => bossOpenReport(context, BossReportType.expenses)),
        const Divider(height: 1),
        row(Icons.account_balance_wallet_rounded, 'Thu − chi', SboxFmt.money(collected - expense),
            'Tiền mặt thu − chi ${SboxFmt.money(cashIn - cashOut)}', SboxColors.text,
            () => bossOpenReport(context, BossReportType.cashbook)),
      ]),
    );
  }
}

bool _hasAnomalies(Map<String, dynamic> d) {
  final t = _map(d['today']);
  return _num(t['canceledCount']) > 0 || _num(t['discount']) > 0;
}

/// «Bất thường hôm nay»: đơn hủy, giảm giá — bấm ra danh sách đơn hủy / báo cáo nguy cơ gian lận.
class _AnomaliesCard extends StatelessWidget {
  const _AnomaliesCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final t = _map(data['today']);
    final canceled = _num(t['canceledCount']).toInt();
    final discount = _num(t['discount']);
    return SboxCard(
      title: 'Cần để mắt hôm nay',
      padding: EdgeInsets.zero,
      child: Column(children: [
        if (canceled > 0)
          ListTile(
            leading: const Icon(Icons.cancel_outlined, color: SboxColors.dangerText),
            title: Text(tr('Đơn hủy')),
            subtitle: Text(tr('${SboxFmt.money(_num(t['canceledTotal']))} — xem ai hủy, hủy lúc nào')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              SboxStatusChip(label: '$canceled', tone: SboxTone.danger),
              const Icon(Icons.chevron_right_rounded, color: SboxColors.slate400),
            ]),
            onTap: () => showBossOrdersSheet(context, title: 'Đơn hủy hôm nay', kind: 'canceled'),
          ),
        if (canceled > 0 && discount > 0) const Divider(height: 1),
        if (discount > 0)
          ListTile(
            leading: const Icon(Icons.discount_outlined, color: SboxColors.warningText),
            title: Text(tr('Giảm giá')),
            subtitle: Text(tr('Giảm trên đơn, voucher, điểm — xem chi tiết ở Kinh doanh')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(SboxFmt.money(discount), style: SboxType.bodyStrong()),
              const Icon(Icons.chevron_right_rounded, color: SboxColors.slate400),
            ]),
            onTap: () => bossOpenReport(context, BossReportType.business),
          ),
      ]),
    );
  }
}

class _DeltaPill extends StatelessWidget {
  const _DeltaPill({required this.delta, required this.caption});

  final double? delta;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final d = delta;
    final up = d != null && d >= 0;
    final text = d == null ? tr('Chưa có số hôm qua để so') : '${up ? '+' : ''}${SboxFmt.pct(d)} ${tr(caption)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SboxSpace.sm, vertical: SboxSpace.xxs),
      decoration: BoxDecoration(color: SboxColors.white.withValues(alpha: 0.16), borderRadius: SboxRadius.pillAll),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (d != null) ...[
          Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded, size: 16, color: SboxColors.white),
          const SizedBox(width: SboxSpace.xs),
        ],
        Flexible(child: Text(text, style: SboxType.captionStyle(SboxColors.white))),
      ]),
    );
  }
}

class _CompareRow extends StatelessWidget {
  const _CompareRow({required this.data});

  final Map<String, dynamic> data;

  static const _weekdays = ['Thứ Hai', 'Thứ Ba', 'Thứ Tư', 'Thứ Năm', 'Thứ Sáu', 'Thứ Bảy', 'Chủ nhật'];

  @override
  Widget build(BuildContext context) {
    final revenue = _num(_map(data['today'])['revenue']);
    final week = _num(_map(data['lastWeekSameTime'])['revenue']);
    final yFull = _num(_map(data['yesterdayFull'])['revenue']);
    final wDelta = bossDeltaPct(revenue, week);
    final biz = DateTime.tryParse('${data['businessDate'] ?? ''}') ?? DateTime.now();
    final weekday = tr(_weekdays[biz.weekday - 1]);
    final hm = _hhmmNow();
    void open() => bossOpenReport(context, BossReportType.business);
    return Row(children: [
      Expanded(
        child: SboxMetricCard(
          // Trước chỉ ghi «Tuần trước» — chủ quán tưởng là doanh thu cả tuần.
          label: '$weekday tuần trước, tới $hm',
          value: SboxFmt.compact(week),
          tone: SboxTone.neutral,
          delta: wDelta == null ? tr('chưa so được') : '${tr('Hôm nay')} ${wDelta >= 0 ? '+' : ''}${SboxFmt.pct(wDelta)}',
          deltaUp: wDelta == null ? null : wDelta >= 0,
          onTap: open,
        ),
      ),
      const SizedBox(width: SboxSpace.md),
      Expanded(
        child: SboxMetricCard(
          label: 'Hôm qua cả ngày',
          value: SboxFmt.compact(yFull),
          tone: SboxTone.neutral,
          delta: '${SboxFmt.number(_num(_map(data['yesterdayFull'])['orderCount']))} ${tr('đơn')}',
          onTap: open,
        ),
      ),
    ]);
  }
}

String _hhmmNow() {
  final n = DateTime.now();
  return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
}

class _HourlyChart extends StatelessWidget {
  const _HourlyChart({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final rows = [for (final r in (data['byHour'] as List? ?? const [])) _map(r)];
    // Bỏ các giờ đầu / cuối không có đơn ở cả hai ngày (quán mở 7h–22h không vẽ 24 cột trống).
    final first = rows.indexWhere((r) => _num(r['today']) > 0 || _num(r['yesterday']) > 0);
    final last = rows.lastIndexWhere((r) => _num(r['today']) > 0 || _num(r['yesterday']) > 0);
    final shown = first < 0 ? const <Map<String, dynamic>>[] : rows.sublist(first, last + 1);
    return SboxCard(
      title: 'Doanh thu theo giờ',
      subtitle: shown.isEmpty ? 'Hôm nay so với hôm qua' : 'Hôm nay so với hôm qua · chạm một giờ để xem đơn',
      child: shown.isEmpty
          ? const SboxEmptyState(icon: Icons.show_chart_rounded, title: 'Chưa có đơn hôm nay')
          : SboxLineChart(
              height: 200,
              labels: [for (final r in shown) '${_num(r['hour']).toInt()}h'],
              series: [
                SboxSeries(name: tr('Hôm nay'), values: [for (final r in shown) _num(r['today'])]),
                SboxSeries(
                  name: tr('Hôm qua'),
                  values: [for (final r in shown) _num(r['yesterday'])],
                  color: SboxColors.slate400,
                ),
              ],
              dashedSeries: const {1},
              maxLabels: 8,
              onTapIndex: (i) {
                final h = _num(shown[i]['hour']).toInt();
                showBossOrdersSheet(context, title: 'Đơn từ ${h}h đến ${h + 1}h', hour: h);
              },
            ),
    );
  }
}

class _PaymentsCard extends StatelessWidget {
  const _PaymentsCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final rows = [for (final r in (data['byPayment'] as List? ?? const [])) _map(r)];
    return SboxCard(
      title: 'Tiền đã thu theo phương thức',
      subtitle: 'Bấm để xem tiền két, thực thu (Cuối ngày)',
      onTap: () => bossOpenEndOfDay(context),
      child: SboxRankList(
        onTap: (_) => bossOpenEndOfDay(context),
        items: [
          for (final r in rows)
            SboxSlice(tr('${r['label'] ?? 'Khác'}'), _num(r['total']),
                caption: '${SboxFmt.number(_num(r['count']))} ${tr('lượt')}'),
        ],
        maxItems: 6,
      ),
    );
  }
}

class _LiveRow extends StatelessWidget {
  const _LiveRow({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final tables = _map(data['openTables']);
    final staff = _map(data['staff']);
    final active = _num(staff['active']).toInt();
    final late = _num(staff['late']).toInt();
    final onLeave = _num(staff['onLeave']).toInt();
    final staffNote = [
      if (late > 0) '${tr('Trễ')} $late',
      if (onLeave > 0) '${tr('Nghỉ phép')} $onLeave',
    ];
    return Row(children: [
      Expanded(
        child: SboxMetricCard(
          label: 'Bàn đang mở',
          value: SboxFmt.number(_num(tables['count'])),
          icon: Icons.table_restaurant_rounded,
          delta: '${tr('Tạm tính')} ${SboxFmt.compact(_num(tables['amount']))}',
          onTap: () => showBossOpenTablesSheet(
            context,
            [for (final e in (tables['items'] as List? ?? const [])) if (e is Map) Map<String, dynamic>.from(e)],
            _num(tables['amount']),
          ),
        ),
      ),
      const SizedBox(width: SboxSpace.md),
      Expanded(
        child: SboxMetricCard(
          label: 'Đã chấm công',
          value: active > 0
              ? '${SboxFmt.number(_num(staff['checkedIn']))}/${SboxFmt.number(active)}'
              : '0',
          // Đi trễ theo ca trong thiết lập lương (cùng màn «Nhân viên hôm nay»).
          delta: active == 0
              ? tr('Chưa có nhân viên')
              : staffNote.isEmpty
                  ? tr('nhân viên')
                  : staffNote.join(' · '),
          // Thiếu quyền Chấm công: vẫn bấm được nhưng báo lý do (trước bấm im lặng, tưởng lỗi).
          onTap: staffCanOpen(context, 'Attendance')
              ? () => Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => const BossStaffTodayScreen()))
              : () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(tr('Tài khoản chưa có quyền xem Chấm công — nhờ chủ cửa hàng cấp quyền để xem ai đã đi làm.')),
                  )),
          tone: SboxTone.success,
        ),
      ),
    ]);
  }
}
