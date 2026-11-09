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
        padding: const EdgeInsets.fromLTRB(SboxSpace.lg, SboxSpace.md, SboxSpace.lg, SboxSpace.xxl),
        children: [
          _RevenueHero(data: d),
          const SizedBox(height: SboxSpace.md),
          BossIssuesCard(refreshTick: _issuesTick, onOpenInbox: widget.onOpenInbox),
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
    return Container(
      padding: const EdgeInsets.all(SboxSpace.lg),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [SboxColors.brand700, SboxColors.brand500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: SboxRadius.lgAll,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Doanh thu hôm nay'), style: SboxType.smallStyle(SboxColors.brand100)),
        const SizedBox(height: SboxSpace.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(SboxFmt.money(revenue),
              style: SboxType.moneyStyle(size: SboxType.display, c: SboxColors.white)),
        ),
        const SizedBox(height: SboxSpace.sm),
        _DeltaPill(delta: delta, caption: 'so với cùng giờ hôm qua'),
        const SizedBox(height: SboxSpace.md),
        Row(children: [
          _HeroStat(label: 'Số đơn', value: SboxFmt.number(_num(today['orderCount']))),
          _HeroStat(label: 'TB / đơn', value: SboxFmt.compact(_num(today['avgOrder']))),
          _HeroStat(label: 'Đã thu', value: SboxFmt.compact(_num(today['collected']))),
        ]),
      ]),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(label), style: SboxType.captionStyle(SboxColors.brand100)),
          Text(value, style: SboxType.moneyStyle(size: SboxType.titleSm, c: SboxColors.white)),
        ]),
      );
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

  @override
  Widget build(BuildContext context) {
    final revenue = _num(_map(data['today'])['revenue']);
    final week = _num(_map(data['lastWeekSameTime'])['revenue']);
    final yFull = _num(_map(data['yesterdayFull'])['revenue']);
    final wDelta = bossDeltaPct(revenue, week);
    return Row(children: [
      Expanded(
        child: SboxMetricCard(
          label: 'Tuần trước',
          value: SboxFmt.compact(week),
          tone: SboxTone.neutral,
          delta: wDelta == null ? tr('cùng giờ') : '${wDelta >= 0 ? '+' : ''}${SboxFmt.pct(wDelta)} ${tr('cùng giờ')}',
          deltaUp: wDelta == null ? null : wDelta >= 0,
        ),
      ),
      const SizedBox(width: SboxSpace.md),
      Expanded(
        child: SboxMetricCard(
          label: 'Hôm qua cả ngày',
          value: SboxFmt.compact(yFull),
          tone: SboxTone.neutral,
          delta: '${SboxFmt.number(_num(_map(data['yesterdayFull'])['orderCount']))} ${tr('đơn')}',
        ),
      ),
    ]);
  }
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
      subtitle: 'Hôm nay so với hôm qua',
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
      child: SboxRankList(
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
    return Row(children: [
      Expanded(
        child: SboxMetricCard(
          label: 'Bàn đang mở',
          value: SboxFmt.number(_num(tables['count'])),
          icon: Icons.table_restaurant_rounded,
          delta: '${tr('Tạm tính')} ${SboxFmt.compact(_num(tables['amount']))}',
        ),
      ),
      const SizedBox(width: SboxSpace.md),
      Expanded(
        child: SboxMetricCard(
          label: 'Đã chấm công',
          value: active > 0
              ? '${SboxFmt.number(_num(staff['checkedIn']))}/${SboxFmt.number(active)}'
              : '0',
          delta: active > 0 ? tr('nhân viên') : tr('Chưa có nhân viên'),
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
