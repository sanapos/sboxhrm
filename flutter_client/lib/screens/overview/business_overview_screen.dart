import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../utils/dashboard_ui_capabilities.dart';
import '../../utils/navigation_notifier.dart';
import '../../utils/permission_navigation.dart';
import '../../widgets/sbox/sbox_ui.dart';
import '../dashboard_screen.dart';

/// Chế độ tổng quan theo gói + quyền người xem.
enum OverviewMode { hrm, pos, combined }

/// Trang «Tổng quan»: nhân viên → màn cá nhân cũ; quản lý → tổng quan mới theo gói.
class OverviewRouterScreen extends StatelessWidget {
  const OverviewRouterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final perm = context.watch<PermissionProvider>();
    final auth = context.watch<AuthProvider>();
    if (!perm.isLoaded) return const SboxLoading();
    final caps = DashboardUiCapabilities.from(perm, role: auth.userRole, allowedModules: auth.user?.allowedModules);
    if (caps.useEmployeeLayout) return const DashboardScreen();
    final mode = BusinessOverviewScreen.resolveMode(perm, auth);
    if (mode == null) return const DashboardScreen();
    return BusinessOverviewScreen(mode: mode);
  }
}

class BusinessOverviewScreen extends StatefulWidget {
  const BusinessOverviewScreen({super.key, required this.mode, this.leading = const [], this.showLegacyLink = true, this.canAccess});

  final OverviewMode mode;
  /// Khối chèn đầu trang (vd «Truy cập nhanh» của app bán hàng).
  final List<Widget> leading;
  final bool showLegacyLink;
  /// Ghi đè kiểm tra quyền mở module (mặc định theo gói + vai trò) — dùng cho kiểm thử.
  final bool Function(String moduleCode)? canAccess;

  /// null = không đủ quyền xem số liệu quản lý.
  static OverviewMode? resolveMode(PermissionProvider perm, AuthProvider auth) {
    bool can(String code) => PermissionNavigation.canAccessModule(code,
        allowedModules: auth.user?.allowedModules, perm: perm, role: auth.userRole);
    final pos = can('PosSalesReport');
    final hrm = can('Dashboard') && (can('Attendance') || can('AttendanceSummary') || can('Employee'));
    if (pos && hrm) return OverviewMode.combined;
    if (pos) return OverviewMode.pos;
    if (hrm) return OverviewMode.hrm;
    return null;
  }

  @override
  State<BusinessOverviewScreen> createState() => _BusinessOverviewScreenState();
}

class _BusinessOverviewScreenState extends State<BusinessOverviewScreen> {
  final _api = ApiService();
  SboxPeriod _period = SboxPeriod.today;
  bool _loading = true;
  int _seq = 0;

  Map<String, dynamic>? _sales;
  Map<String, dynamic>? _salesPrev;
  Map<String, dynamic>? _salesTrend;
  Map<String, dynamic>? _stock;
  Map<String, dynamic>? _manager;
  List<Map<String, dynamic>> _trends = const [];
  List<Map<String, dynamic>> _todos = const [];

  bool get _hasPos => widget.mode != OverviewMode.hrm;
  bool get _hasHrm => widget.mode != OverviewMode.pos;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant BusinessOverviewScreen old) {
    super.didUpdateWidget(old);
    if (old.mode != widget.mode) _load();
  }

  static Map<String, dynamic>? _data(Map<String, dynamic> r) =>
      r['isSuccess'] == true && r['data'] is Map ? Map<String, dynamic>.from(r['data'] as Map) : null;

  static List<Map<String, dynamic>> _list(dynamic v) =>
      v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];

  static double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

  /// Kỳ ngắn (hôm nay / hôm qua) → biểu đồ xu hướng lấy 7 ngày gần nhất cho có hình.
  bool get _shortPeriod => _period == SboxPeriod.today || _period == SboxPeriod.yesterday;

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => _loading = true);
    final (f, t) = _period.range();
    final (pf, pt) = _period.previousRange();
    final (tf, tt) = SboxPeriod.last7.range();
    final futures = <String, Future<dynamic>>{
      'todos': _api.getOverviewTodos(),
      if (_hasPos) 'sales': _api.getPosSalesReportSummary(from: f, to: t),
      if (_hasPos) 'salesPrev': _api.getPosSalesReportSummary(from: pf, to: pt),
      if (_hasPos && _shortPeriod) 'salesTrend': _api.getPosSalesReportSummary(from: tf, to: tt),
      if (_hasPos) 'stock': _api.getPosStockReportSummary(),
      if (_hasHrm) 'manager': _api.getManagerDashboard(),
      if (_hasHrm) 'trends': _api.getAttendanceTrends(days: _period.trendDays),
    };
    final keys = futures.keys.toList();
    final values = await Future.wait(futures.values);
    if (!mounted || seq != _seq) return;
    final r = {for (var i = 0; i < keys.length; i++) keys[i]: values[i]};
    setState(() {
      _loading = false;
      _todos = r['todos'] is Map ? _list((r['todos'] as Map)['data']) : const [];
      _sales = r['sales'] is Map ? _data(Map<String, dynamic>.from(r['sales'] as Map)) : null;
      _salesPrev = r['salesPrev'] is Map ? _data(Map<String, dynamic>.from(r['salesPrev'] as Map)) : null;
      _salesTrend = r['salesTrend'] is Map ? _data(Map<String, dynamic>.from(r['salesTrend'] as Map)) : _sales;
      _stock = r['stock'] is Map ? _data(Map<String, dynamic>.from(r['stock'] as Map)) : null;
      _manager = r['manager'] is Map ? _data(Map<String, dynamic>.from(r['manager'] as Map)) : null;
      _trends = _list(r['trends']);
    });
  }

  void _setPeriod(SboxPeriod p) {
    if (p == _period) return;
    setState(() => _period = p);
    _load();
  }

  void _go(String module, {VoidCallback? before}) {
    before?.call();
    NavigationNotifier.navigateToModule.value = null;
    NavigationNotifier.navigateToModule.value = module;
  }

  bool _can(String code) {
    if (widget.canAccess != null) return widget.canAccess!(code);
    final perm = context.read<PermissionProvider>();
    final auth = context.read<AuthProvider>();
    return PermissionNavigation.canAccessModule(code, allowedModules: auth.user?.allowedModules, perm: perm, role: auth.userRole);
  }

  String get _title => switch (widget.mode) {
        OverviewMode.hrm => 'Tổng quan nhân sự',
        OverviewMode.pos => 'Tổng quan bán hàng',
        OverviewMode.combined => 'Tổng quan kinh doanh & nhân sự',
      };

  // ─── Số liệu ────────────────────────────────────────────────────

  Map<String, dynamic> get _rate =>
      _manager?['attendanceRate'] is Map ? Map<String, dynamic>.from(_manager!['attendanceRate'] as Map) : const {};

  /// Chuyên cần hôm nay. Ưu tiên dòng hôm nay của biểu đồ chuyên cần: mọi nhân viên (cả người không có
  /// tài khoản app), theo chi nhánh đang xem, ngày nghỉ theo lịch / thiết lập lương, trễ có ân hạn —
  /// ô số và biểu đồ khớp nhau. Máy chủ cũ (không có dòng hôm nay) → số theo ca đã duyệt.
  /// checkedIn = đã chấm công vào (gồm cả người đi trễ).
  ({int total, int checkedIn, int late, int absent, int leave}) get _today {
    final now = DateTime.now();
    final todayKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final tr0 = _trends.where((d) => '${d['date']}' == todayKey).firstOrNull;
    if (tr0 != null && tr0.containsKey('onLeave')) {
      return (
        total: _n(tr0['total']).round(),
        checkedIn: _n(tr0['present']).round(),
        late: _n(tr0['late']).round(),
        absent: _n(tr0['absent']).round(),
        leave: _n(tr0['onLeave']).round(),
      );
    }
    final shifts = _n(_rate['totalEmployeesWithShift']).round();
    if (shifts > 0) {
      final late = _n(_rate['lateEmployees']).round();
      return (
        total: shifts,
        checkedIn: _n(_rate['presentEmployees']).round() + late,
        late: late,
        absent: _n(_rate['absentEmployees']).round(),
        leave: _n(_rate['onLeaveEmployees']).round(),
      );
    }
    final t = tr0;
    if (t == null) return (total: 0, checkedIn: 0, late: 0, absent: 0, leave: _n(_rate['onLeaveEmployees']).round());
    return (
      total: _n(t['total']).round(),
      checkedIn: _n(t['present']).round(),
      late: _n(t['late']).round(),
      absent: _n(t['absent']).round(),
      leave: _n(_rate['onLeaveEmployees']).round(),
    );
  }

  String _dayLabel(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  /// Người xem không có quyền «Xem giá vốn & lợi nhuận»: máy chủ bỏ trường lãi.
  bool get _profitHidden => _sales != null && !_sales!.containsKey('totalProfit');

  List<SboxKpi> _posKpis() {
    final cmp = _period.compareLabel;
    final rev = _n(_sales?['totalRevenue']);
    final profit = _n(_sales?['totalProfit']);
    final orders = _n(_sales?['orderCount']);
    final aov = orders > 0 ? rev / orders : 0.0;
    final pRev = _n(_salesPrev?['totalRevenue']);
    final pProfit = _n(_salesPrev?['totalProfit']);
    final pOrders = _n(_salesPrev?['orderCount']);
    final pAov = pOrders > 0 ? pRev / pOrders : 0.0;
    return [
      SboxKpi(label: 'Doanh thu', value: SboxFmt.money(rev), icon: Icons.payments_outlined, current: rev, previous: _salesPrev == null ? null : pRev, compareLabel: cmp),
      if (_profitHidden)
        SboxKpi(
            label: 'Đã thu',
            value: SboxFmt.money(_n(_sales?['totalPaid'])),
            icon: Icons.account_balance_wallet_outlined,
            tone: SboxTone.success,
            current: _n(_sales?['totalPaid']),
            previous: _salesPrev == null ? null : _n(_salesPrev?['totalPaid']),
            compareLabel: cmp)
      else
        SboxKpi(
            label: 'Lợi nhuận gộp',
            value: SboxFmt.money(profit),
            icon: Icons.trending_up_rounded,
            tone: SboxTone.success,
            current: profit,
            previous: _salesPrev == null ? null : pProfit,
            compareLabel: cmp),
      SboxKpi(label: 'Số đơn', value: SboxFmt.number(orders), icon: Icons.receipt_long_outlined, tone: SboxTone.violet, current: orders, previous: _salesPrev == null ? null : pOrders, compareLabel: cmp),
      SboxKpi(label: 'Giá trị TB/đơn', value: SboxFmt.money(aov), icon: Icons.shopping_basket_outlined, tone: SboxTone.neutral, current: aov, previous: _salesPrev == null ? null : pAov, compareLabel: cmp),
    ];
  }

  List<SboxKpi> _hrmKpis() {
    final t = _today;
    final rate = t.total > 0 ? t.checkedIn * 100 / t.total : 0.0;
    final punctual = t.checkedIn > 0 ? (t.checkedIn - t.late) * 100 / t.checkedIn : 100.0;
    return [
      SboxKpi(
          label: 'Có mặt hôm nay',
          value: t.total > 0 ? '${t.checkedIn}/${t.total}' : '${t.checkedIn}',
          icon: Icons.how_to_reg_outlined,
          tone: SboxTone.success,
          note: t.total > 0 ? 'Tỷ lệ ${SboxFmt.pct(rate)}' : 'Chưa có nhân viên'),
      SboxKpi(
          label: 'Đi trễ hôm nay',
          value: '${t.late}',
          icon: Icons.schedule_outlined,
          tone: SboxTone.warning,
          note: t.checkedIn > 0 ? 'Đúng giờ ${SboxFmt.pct(punctual)}' : 'Chưa ai chấm công'),
      SboxKpi(label: 'Vắng hôm nay', value: '${t.absent}', icon: Icons.person_off_outlined, tone: SboxTone.danger, note: 'Phải đi làm, chưa chấm công'),
      SboxKpi(label: 'Nghỉ phép hôm nay', value: '${t.leave}', icon: Icons.beach_access_outlined, tone: SboxTone.violet, note: 'Đơn đã duyệt'),
    ];
  }

  List<SboxKpi> _combinedKpis() {
    final pos = _posKpis();
    final hrm = _hrmKpis();
    final present = _today.checkedIn;
    final rev = _n(_sales?['totalRevenue']);
    return [
      pos[0],
      pos[1],
      pos[2],
      hrm[0],
      hrm[1],
      // Doanh thu cả kỳ ÷ số NV có mặt HÔM NAY vô nghĩa khi xem kỳ khác → chỉ hiện khi xem hôm nay.
      if (_period == SboxPeriod.today)
        SboxKpi(
          label: 'Doanh thu / NV có mặt',
          value: present > 0 ? SboxFmt.money(rev / present) : '—',
          icon: Icons.groups_2_outlined,
          tone: SboxTone.brand,
          note: 'Năng suất hôm nay',
        )
      else
        hrm[2],
    ];
  }

  // ─── Biểu đồ ────────────────────────────────────────────────────

  Widget _revenueChart({bool wide = false}) {
    final days = _list(_salesTrend?['profitByDay']);
    return SboxChartCard(
      title: _profitHidden ? 'Doanh thu' : 'Doanh thu & lợi nhuận',
      subtitle: _shortPeriod ? '7 ngày gần nhất' : _period.label,
      wide: wide,
      onMore: _can('PosSalesReport') ? () => _go('PosSalesReport') : null,
      child: SboxBarChart(
        labels: [for (final d in days) _dayLabel(d['date'])],
        series: [
          SboxSeries(name: 'Doanh thu', values: [for (final d in days) _n(d['revenue'])]),
          if (!_profitHidden)
            SboxSeries(name: 'Lợi nhuận', values: [for (final d in days) _n(d['profit'])], color: SboxColors.success),
        ],
      ),
    );
  }

  Widget _attendanceChart({bool wide = false}) {
    return SboxChartCard(
      title: 'Chuyên cần theo ngày',
      subtitle: '${_period.trendDays} ngày gần nhất',
      wide: wide,
      onMore: _can('AttendanceSummary') ? () => _go('AttendanceSummary') : null,
      child: SboxBarChart(
        stacked: true,
        valueFormat: (v) => '${SboxFmt.number(v)} lượt',
        axisFormat: (v) => SboxFmt.number(v),
        labels: [for (final d in _trends) _dayLabel(d['date'])],
        series: [
          SboxSeries(name: 'Đúng giờ', values: [for (final d in _trends) _n(d['onTime'])], color: SboxColors.success),
          SboxSeries(name: 'Đi trễ', values: [for (final d in _trends) _n(d['late'])], color: SboxColors.warning),
          SboxSeries(name: 'Vắng', values: [for (final d in _trends) _n(d['absent'])], color: SboxColors.danger),
        ],
      ),
    );
  }

  Widget _todayAttendanceCard() {
    return SboxChartCard(
      title: 'Hôm nay',
      subtitle: 'Tình trạng đi làm',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SboxRatioBar(parts: [
          SboxSlice('Đúng giờ', (_today.checkedIn - _today.late).clamp(0, 1 << 30).toDouble(), color: SboxColors.success),
          SboxSlice('Trễ', _today.late.toDouble(), color: SboxColors.warning),
          SboxSlice('Vắng', _today.absent.toDouble(), color: SboxColors.danger),
          SboxSlice('Nghỉ phép', _today.leave.toDouble(), color: SboxColors.violet),
        ]),
        const SizedBox(height: SboxSpace.lg),
        Text(tr('Đi trễ nhiều nhất'), style: SboxType.captionStyle()),
        const SizedBox(height: SboxSpace.xs),
        SboxRankList(
          emptyHeight: 60,
          color: SboxColors.warning,
          valueFormat: (v) => '${SboxFmt.number(v)} phút',
          items: [
            if (_todayTrend?['employees'] is List)
              for (final e in _list(_todayTrend!['employees']).where((e) => e['status'] == 'Late'))
                SboxSlice('${e['fullName'] ?? ''}', _n(e['lateMinutes']), caption: '${e['department'] ?? ''}')
            else
              for (final e in _list(_manager?['lateEmployees']))
                SboxSlice('${e['fullName'] ?? ''}', _lateMinutes(e['lateBy']), caption: '${e['department'] ?? ''}'),
          ],
        ),
      ]),
    );
  }

  static double _lateMinutes(dynamic v) {
    if (v is num) return v.toDouble();
    final s = '${v ?? ''}';
    final m = RegExp(r'^(?:(\d+)\.)?(\d+):(\d+)').firstMatch(s);
    if (m == null) return 0;
    return (int.tryParse(m.group(1) ?? '0') ?? 0) * 1440 + (int.parse(m.group(2)!)) * 60.0 + int.parse(m.group(3)!);
  }

  Widget _paymentDonut() {
    final pays = _list(_sales?['byPayment']);
    return SboxChartCard(
      title: 'Cơ cấu thanh toán',
      subtitle: _period.label,
      child: SboxDonutChart(
        centerValue: SboxFmt.compact(_n(_sales?['totalPaid'])),
        centerLabel: 'Đã thu',
        slices: [for (final p in pays) SboxSlice('${p['paymentMethod'] ?? 'Khác'}', _n(p['total']))],
      ),
    );
  }

  Widget _topProducts() {
    return SboxChartCard(
      title: 'Top hàng bán chạy',
      subtitle: 'Theo doanh thu · ${_period.label}',
      onMore: _can('PosSalesReport') ? () => _go('PosSalesReport') : null,
      child: SboxRankList(items: [
        for (final p in _list(_sales?['topProducts']))
          SboxSlice('${p['productName'] ?? ''}', _n(p['revenue']), caption: 'SL ${SboxFmt.number(_n(p['qty']))}'),
      ]),
    );
  }

  Widget _todoCard() {
    final allowHrm = _hasHrm, allowPos = _hasPos;
    IconData icon(String key) => switch (key) {
          'leave' => Icons.beach_access_outlined,
          'mobileAttendance' => Icons.phone_android_outlined,
          'correction' => Icons.edit_calendar_outlined,
          'shiftSwap' => Icons.swap_horiz_rounded,
          'advance' => Icons.request_quote_outlined,
          'outOfStock' => Icons.remove_shopping_cart_outlined,
          'lowStock' => Icons.inventory_outlined,
          'nearExpiry' => Icons.event_busy_outlined,
          'expiredLots' => Icons.dangerous_outlined,
          'onlinePending' => Icons.delivery_dining_outlined,
          'shippingIssue' => Icons.local_shipping_outlined,
          'codPending' => Icons.account_balance_wallet_outlined,
          _ => Icons.pending_actions_rounded,
        };
    SboxTone tone(String s) => switch (s) {
          'danger' => SboxTone.danger,
          'info' => SboxTone.brand,
          _ => SboxTone.warning,
        };
    (String, VoidCallback?)? target(String key) => switch (key) {
          'leave' => ('Leave', () => NavigationNotifier.leaveInitialTab.value = 1),
          'mobileAttendance' => ('AttendanceApproval', () => NavigationNotifier.attendanceApprovalTab.value = 1),
          'correction' => ('AttendanceApproval', () => NavigationNotifier.attendanceApprovalTab.value = 0),
          'shiftSwap' => ('ScheduleApproval', () => NavigationNotifier.scheduleApprovalTab.value = 2),
          'advance' => ('AdvanceRequests', () => NavigationNotifier.advanceRequestsStatusFilter.value = 0),
          'outOfStock' || 'lowStock' => ('PosProducts', null),
          'nearExpiry' || 'expiredLots' => ('PosSalesReport', null),
          'onlinePending' => ('PosQrOrder', null),
          'shippingIssue' || 'codPending' => ('PosSaleOrders', null),
          _ => null,
        };
    final items = <SboxTodoItem>[];
    for (final t in _todos) {
      final g = '${t['group']}';
      if (g == 'hrm' && !allowHrm || g == 'pos' && !allowPos) continue;
      final key = '${t['key']}';
      final tg = target(key);
      final can = tg != null && _can(tg.$1);
      if (tg != null && !can && g == 'hrm') continue;
      items.add(SboxTodoItem(
        label: '${t['label'] ?? key}',
        count: _n(t['count']).round(),
        tone: tone('${t['severity']}'),
        icon: icon(key),
        onTap: can ? () => _go(tg.$1, before: tg.$2) : null,
      ));
    }
    // Kho: dùng số liệu tồn kho khi API việc cần làm chưa có (máy chủ cũ).
    if (_hasPos && !_todos.any((t) => t['key'] == 'outOfStock') && _stock != null) {
      items.add(SboxTodoItem(label: 'Hàng đã hết', count: _n(_stock!['outOfStockCount']).round(), tone: SboxTone.danger, icon: Icons.remove_shopping_cart_outlined));
    }
    final total = items.fold<int>(0, (s, e) => s + e.count);
    return SboxChartCard(
      title: 'Việc cần xử lý',
      subtitle: total == 0 ? 'Đã xử lý hết' : '$total việc đang chờ',
      child: SboxTodoList(items: items),
    );
  }

  Widget _staffTable() {
    final rows = _list(_sales?['topEmployees']);
    final total = rows.fold<double>(0, (s, r) => s + _n(r['revenue']));
    return SboxDataTable<Map<String, dynamic>>(
      rows: rows,
      pageSize: 10,
      emptyTitle: 'Chưa có đơn bán trong kỳ',
      columns: [
        SboxColumn(label: 'Nhân viên', primary: true, flex: 3, text: (r) => '${r['soldBy'] ?? '—'}', sortValue: (r) => '${r['soldBy'] ?? ''}'),
        SboxColumn(label: 'Số đơn', numeric: true, flex: 1, text: (r) => SboxFmt.number(_n(r['orderCount'])), sortValue: (r) => _n(r['orderCount'])),
        SboxColumn(label: 'Doanh thu', numeric: true, flex: 2, text: (r) => SboxFmt.money(_n(r['revenue'])), sortValue: (r) => _n(r['revenue'])),
        SboxColumn(
            label: 'TB/đơn',
            numeric: true,
            flex: 2,
            hideOnMobile: true,
            text: (r) => SboxFmt.money(_n(r['orderCount']) > 0 ? _n(r['revenue']) / _n(r['orderCount']) : 0),
            sortValue: (r) => _n(r['orderCount']) > 0 ? _n(r['revenue']) / _n(r['orderCount']) : 0),
        SboxColumn(label: 'Tỷ trọng', numeric: true, flex: 1, text: (r) => SboxFmt.pct(total > 0 ? _n(r['revenue']) / total * 100 : 0), sortValue: (r) => _n(r['revenue'])),
      ],
    );
  }

  /// Dòng hôm nay của chuyên cần (chấm công thực tế) — null khi máy chủ cũ chưa trả.
  Map<String, dynamic>? get _todayTrend {
    final now = DateTime.now();
    final key = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return _trends.where((d) => '${d['date']}' == key).firstOrNull;
  }

  /// «Nhân viên hôm nay» theo chấm công thực tế: ai đã chấm (giờ vào / ra thật, ca khớp, trễ có ân hạn),
  /// ai phải đi làm mà chưa chấm (vắng), ai nghỉ phép — gồm cả NV không có tài khoản app.
  Widget _employeeTodayTable() {
    final actual = _todayTrend?['employees'];
    if (actual is List) return _actualTodayTable(_list(actual));
    return _legacyTodayTable();
  }

  Widget _actualTodayTable(List<Map<String, dynamic>> rows) {
    (String, SboxTone) status(Map<String, dynamic> r) => switch ('${r['status']}') {
          'Present' => ('Có mặt', SboxTone.success),
          'Late' => ('Trễ ${r['lateMinutes'] ?? 0}p', SboxTone.warning),
          'Absent' => ('Vắng', SboxTone.danger),
          'On Leave' => ('Nghỉ phép', SboxTone.violet),
          _ => ('—', SboxTone.neutral),
        };
    int order(dynamic s) => switch ('$s') { 'Absent' => 0, 'Late' => 1, 'On Leave' => 2, 'Present' => 3, _ => 4 };
    rows.sort((a, b) {
      final c = order(a['status']).compareTo(order(b['status']));
      return c != 0 ? c : '${a['checkIn'] ?? ''}'.compareTo('${b['checkIn'] ?? ''}');
    });
    String shift(Map<String, dynamic> r) {
      final name = '${r['shiftName'] ?? ''}';
      final s = r['shiftStart'], e = r['shiftEnd'];
      if (s == null) return name.isEmpty ? '—' : name;
      final time = e == null ? '$s' : '$s–$e';
      return name.isEmpty || name == 'Ca khác' ? time : '$name · $time';
    }
    return SboxDataTable<Map<String, dynamic>>(
      rows: rows,
      pageSize: 10,
      emptyTitle: 'Hôm nay chưa có ai chấm công',
      columns: [
        SboxColumn(label: 'Nhân viên', primary: true, flex: 3, text: (r) => '${r['fullName'] ?? ''}', sortValue: (r) => '${r['fullName'] ?? ''}'),
        SboxColumn(label: 'Phòng ban', flex: 2, hideOnMobile: true, text: (r) => '${r['department'] ?? ''}', sortValue: (r) => '${r['department'] ?? ''}'),
        SboxColumn(label: 'Ca', flex: 2, text: shift, sortValue: (r) => '${r['shiftStart'] ?? ''}'),
        SboxColumn(label: 'Vào', flex: 1, text: (r) => '${r['checkIn'] ?? '—'}', sortValue: (r) => '${r['checkIn'] ?? ''}'),
        SboxColumn(label: 'Ra', flex: 1, hideOnMobile: true, text: (r) => '${r['checkOut'] ?? '—'}'),
        SboxColumn(
          label: 'Trạng thái',
          flex: 2,
          cell: (r) {
            final (l, t) = status(r);
            return Align(alignment: Alignment.centerLeft, child: SboxStatusChip(label: l, tone: t, dot: true));
          },
          sortValue: (r) => order(r['status']),
        ),
      ],
    );
  }

  /// Máy chủ cũ: theo ca đã duyệt (bảng ca cũ).
  Widget _legacyTodayTable() {
    final rows = _list(_manager?['todayEmployees']);
    String hm(dynamic iso) {
      final d = DateTime.tryParse('${iso ?? ''}');
      if (d == null) return '—';
      final l = d.isUtc ? d.toLocal() : d;
      return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
    }

    (String, SboxTone) status(dynamic s) => switch ('$s') {
          'Present' => ('Có mặt', SboxTone.success),
          'Late' => ('Đi trễ', SboxTone.warning),
          'Absent' => ('Vắng', SboxTone.danger),
          'On Leave' => ('Nghỉ phép', SboxTone.violet),
          _ => ('Không có ca', SboxTone.neutral),
        };
    int order(dynamic s) => switch ('$s') { 'Absent' => 0, 'Late' => 1, 'On Leave' => 2, 'Present' => 3, _ => 4 };
    rows.sort((a, b) => order(a['status']).compareTo(order(b['status'])));
    return SboxDataTable<Map<String, dynamic>>(
      rows: rows,
      pageSize: 10,
      emptyTitle: 'Hôm nay chưa có ca làm việc',
      columns: [
        SboxColumn(label: 'Nhân viên', primary: true, flex: 3, text: (r) => '${r['fullName'] ?? ''}', sortValue: (r) => '${r['fullName'] ?? ''}'),
        SboxColumn(label: 'Phòng ban', flex: 2, hideOnMobile: true, text: (r) => '${r['department'] ?? ''}', sortValue: (r) => '${r['department'] ?? ''}'),
        SboxColumn(label: 'Ca', flex: 2, text: (r) => r['shiftStartTime'] == null ? '—' : '${hm(r['shiftStartTime'])}–${hm(r['shiftEndTime'])}'),
        SboxColumn(label: 'Vào', flex: 1, text: (r) => hm(r['checkInTime']), sortValue: (r) => '${r['checkInTime'] ?? ''}'),
        SboxColumn(label: 'Ra', flex: 1, hideOnMobile: true, text: (r) => hm(r['checkOutTime'])),
        SboxColumn(
          label: 'Trạng thái',
          flex: 2,
          cell: (r) {
            final (l, t) = status(r['status']);
            return Align(alignment: Alignment.centerLeft, child: SboxStatusChip(label: l, tone: t, dot: true));
          },
          sortValue: (r) => order(r['status']),
        ),
      ],
    );
  }

  // ─── Bố cục ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final header = SboxPageHeader(
      title: _title,
      subtitle: widget.mode == OverviewMode.hrm ? 'Chấm công, nghỉ phép và việc chờ duyệt' : 'Số liệu ${_period.label.toLowerCase()} so với ${_period.compareLabel}',
      actions: [
      ],
    );
    final filters = widget.mode == OverviewMode.hrm
        ? null
        : SboxPeriodBar(
            value: _period,
            onChanged: _setPeriod,
            options: const [SboxPeriod.today, SboxPeriod.yesterday, SboxPeriod.last7, SboxPeriod.thisMonth, SboxPeriod.lastMonth],
          );

    if (_loading && _sales == null && _manager == null && _todos.isEmpty) {
      return SboxReportLayout(header: header, filters: filters, children: const [SizedBox(height: 240, child: SboxLoading(message: 'Đang tải số liệu…'))]);
    }

    final List<SboxKpi> kpis;
    final List<Widget> charts;
    Widget? table;
    String? tableTitle;
    switch (widget.mode) {
      case OverviewMode.hrm:
        kpis = _hrmKpis();
        charts = [_attendanceChart(), _todoCard(), _todayAttendanceCard()];
        table = _employeeTodayTable();
        tableTitle = 'Nhân viên hôm nay';
      case OverviewMode.pos:
        kpis = _posKpis();
        charts = [_revenueChart(), _todoCard(), _topProducts(), _paymentDonut()];
        table = _staffTable();
        tableTitle = 'Doanh thu theo nhân viên bán';
      case OverviewMode.combined:
        kpis = _combinedKpis();
        charts = [_revenueChart(), _attendanceChart(), _todoCard(), _todayAttendanceCard(), _topProducts(), _paymentDonut()];
        table = _staffTable();
        tableTitle = 'Doanh thu theo nhân viên bán';
    }
    return Stack(children: [
      SboxReportLayout(
        header: widget.leading.isEmpty ? header : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, const SizedBox(height: SboxSpace.md), ...widget.leading]),
        filters: filters,
        kpis: kpis,
        charts: charts,
        table: table,
        tableTitle: tableTitle,
        onRefresh: _load,
      ),
      if (_loading) const Positioned(left: 0, right: 0, top: 0, child: LinearProgressIndicator(minHeight: 2)),
    ]);
  }
}
