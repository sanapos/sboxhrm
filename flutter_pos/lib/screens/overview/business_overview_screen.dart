// Bản port từ flutter_client (SBOX POS Android 7) — chỉ phần bán hàng, bỏ chấm công / lương / phạt (app POS không có HRM).
import 'dart:async';

import 'package:flutter/material.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../pos_sale_order_list_screen.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../utils/navigation_notifier.dart';
import '../../utils/permission_navigation.dart';
import '../../widgets/sbox/sbox_ui.dart';

/// Chế độ tổng quan theo gói + quyền người xem.
enum OverviewMode { hrm, pos, combined }


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
  List<Map<String, dynamic>> _todos = const [];
  Map<String, dynamic>? _highlights;

  bool get _hasPos => widget.mode != OverviewMode.hrm;
  /// flutter_pos (SBOX POS Android 6) chỉ có phần bán hàng.
  bool get _hasHrm => false;

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

  // Không trả `const []`: bảng «Nhân viên hôm nay» sort tại chỗ — vai trò không xem được
  // Dashboard/manager (403) làm màn Tổng quan văng «Cannot modify a constant list».
  static List<Map<String, dynamic>> _list(dynamic v) =>
      v is List ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : <Map<String, dynamic>>[];

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
      'highlights': _api.getOverviewHighlights(),
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
      _highlights = r['highlights'] is Map ? _data(Map<String, dynamic>.from(r['highlights'] as Map)) : null;
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

  /// Danh sách đơn đúng kỳ đang xem (lọc người bán khi có) — thay cho chỉ chuyển module không kèm ngày.
  void _openOrders({String? soldBy, String? soldByLabel}) {
    if (!_can('PosSaleOrders')) {
      if (_can('PosSalesReport')) _go('PosSalesReport');
      return;
    }
    final (f, t) = _period.range();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PosHubScope.pushed(
        child: PosSaleOrderListScreen(
          initialFrom: f,
          initialTo: t,
          initialSoldBy: soldBy,
          initialSoldByLabel: soldByLabel,
        ),
      ),
    ));
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




  String _dayLabel(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    if (d == null) return '';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  /// Người xem không có quyền «Xem giá vốn & lợi nhuận»: máy chủ bỏ trường lãi.
  bool get _profitHidden => _sales != null && !_sales!.containsKey('totalProfit');

  /// Khách còn nợ trong kỳ ≈ doanh thu (gồm VAT) − đã thu.
  double get _unpaid {
    final rev = _n(_sales?['totalRevenueInclVat'] ?? _sales?['totalRevenue']);
    final paid = _n(_sales?['totalPaid']);
    return rev > paid ? rev - paid : 0;
  }

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
    void report() => _can('PosSalesReport') ? _go('PosSalesReport') : null;
    return [
      SboxKpi(
          label: 'Doanh thu',
          value: SboxFmt.money(rev),
          icon: Icons.payments_outlined,
          current: rev,
          previous: _salesPrev == null ? null : pRev,
          compareLabel: cmp,
          onTap: report),
      if (_profitHidden)
        SboxKpi(
            label: 'Đã thu',
            value: SboxFmt.money(_n(_sales?['totalPaid'])),
            icon: Icons.account_balance_wallet_outlined,
            tone: SboxTone.success,
            current: _n(_sales?['totalPaid']),
            previous: _salesPrev == null ? null : _n(_salesPrev?['totalPaid']),
            compareLabel: cmp,
            onTap: report)
      else
        SboxKpi(
            // «Lợi nhuận gộp» bị hiểu là lãi thật — ghi rõ chưa trừ chi phí (lãi ròng ở báo cáo Lãi lỗ).
            label: 'Lãi gộp (chưa trừ chi phí)',
            value: SboxFmt.money(profit),
            icon: Icons.trending_up_rounded,
            tone: SboxTone.success,
            current: profit,
            previous: _salesPrev == null ? null : pProfit,
            compareLabel: cmp,
            onTap: report),
      SboxKpi(
          label: 'Số đơn',
          value: SboxFmt.number(orders),
          icon: Icons.receipt_long_outlined,
          tone: SboxTone.violet,
          current: orders,
          previous: _salesPrev == null ? null : pOrders,
          compareLabel: cmp,
          onTap: () => _openOrders()),
      SboxKpi(
          label: 'Giá trị TB/đơn',
          value: SboxFmt.money(aov),
          icon: Icons.shopping_basket_outlined,
          tone: SboxTone.neutral,
          current: aov,
          previous: _salesPrev == null ? null : pAov,
          compareLabel: cmp,
          onTap: report),
    ];
  }

  /// «Đã thu» + «Chưa thu» (khi ô lãi gộp chiếm chỗ «Đã thu») — đủ cặp, chủ quán thấy ngay tiền đã về / còn nợ.
  List<SboxKpi> _moneyKpis() => [
        if (!_profitHidden)
          SboxKpi(
            label: 'Đã thu',
            value: SboxFmt.money(_n(_sales?['totalPaid'])),
            icon: Icons.account_balance_wallet_outlined,
            tone: SboxTone.success,
            current: _n(_sales?['totalPaid']),
            previous: _salesPrev == null ? null : _n(_salesPrev?['totalPaid']),
            compareLabel: _period.compareLabel,
            onTap: () => _can('CashTransaction') ? _go('CashTransaction') : (_can('PosSalesReport') ? _go('PosSalesReport') : null),
          ),
        _unpaidKpi(),
      ];

  /// «Chưa thu»: phần khách còn nợ trong kỳ — số chủ quán cần hơn «Doanh thu / NV có mặt».
  SboxKpi _unpaidKpi() => SboxKpi(
        label: 'Chưa thu (khách nợ)',
        value: SboxFmt.money(_unpaid),
        icon: Icons.request_quote_outlined,
        tone: _unpaid > 0 ? SboxTone.danger : SboxTone.neutral,
        note: 'Đã thu ${SboxFmt.money(_n(_sales?['totalPaid']))}',
        onTap: () => _can('PosSalesReport') ? _go('PosSalesReport') : null,
      );


  /// Hàng số liệu có tiêu đề — tách «Bán hàng · kỳ đã chọn» khỏi «Nhân sự · hôm nay» (trước nằm lẫn một lưới,
  /// chọn «Tháng này» thì doanh thu cả tháng đứng cạnh «Vắng hôm nay»).
  Widget _kpiGroup(String title, List<SboxKpi> items) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: SboxSpace.sm),
            child: Text(tr(title), style: SboxType.captionStyle(SboxColors.textMuted).copyWith(fontWeight: FontWeight.w700)),
          ),
          SboxKpiStrip(items: items),
        ],
      );

  // ─── Biểu đồ ────────────────────────────────────────────────────

  /// Máy chủ chỉ trả ngày có bán → ngày 0 đồng biến mất khỏi trục (vd thiếu hôm nay).
  /// Điền đủ mọi ngày trong kỳ với 0 để trục ngày liên tục, khớp «7 ngày gần nhất».
  List<Map<String, dynamic>> _fillDays(List<Map<String, dynamic>> rows) {
    final (from, to) = _shortPeriod ? SboxPeriod.last7.range() : _period.range();
    String key(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final byDay = {for (final r in rows) '${r['date'] ?? ''}'.split('T').first: r};
    final out = <Map<String, dynamic>>[];
    for (var d = DateTime(from.year, from.month, from.day);
        !d.isAfter(to) && out.length < 92;
        d = DateTime(d.year, d.month, d.day + 1)) {
      out.add(byDay[key(d)] ?? {'date': key(d), 'revenue': 0, 'profit': 0});
    }
    return out.isEmpty ? rows : out;
  }

  Widget _revenueChart({bool wide = false}) {
    final days = _fillDays(_list(_salesTrend?['profitByDay']));
    return SboxChartCard(
      title: _profitHidden ? 'Doanh thu' : 'Doanh thu & lợi nhuận',
      subtitle: _shortPeriod ? '7 ngày gần nhất' : _period.label,
      wide: wide,
      onMore: _can('PosSalesReport') ? () => _go('PosSalesReport') : null,
      child: SboxBarChart(
        onTapIndex: _can('PosSalesReport') ? (_) => _go('PosSalesReport') : null,
        labels: [for (final d in days) _dayLabel(d['date'])],
        series: [
          SboxSeries(name: 'Doanh thu', values: [for (final d in days) _n(d['revenue'])]),
          if (!_profitHidden)
            SboxSeries(name: 'Lợi nhuận', values: [for (final d in days) _n(d['profit'])], color: SboxColors.success),
        ],
      ),
    );
  }










  Widget _paymentDonut() {
    final pays = _list(_sales?['byPayment']);
    return SboxChartCard(
      title: 'Cơ cấu thanh toán',
      subtitle: _period.label,
      onMore: _can('CashTransaction') ? () => _go('CashTransaction') : (_can('PosSalesReport') ? () => _go('PosSalesReport') : null),
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
          'scheduleReg' => Icons.how_to_reg_rounded,
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
          // «Duyệt lịch làm việc» giờ mở Ca làm việc → Cần duyệt (màn cũ chỉ khi thiếu quyền Ca làm việc).
          'shiftSwap' => ('ScheduleApproval', () => NavigationNotifier.scheduleApprovalTab.value = 3),
          'scheduleReg' => ('ScheduleApproval', () => NavigationNotifier.scheduleApprovalTab.value = 0),
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
      items.add(SboxTodoItem(
          label: 'Hàng đã hết',
          count: _n(_stock!['outOfStockCount']).round(),
          tone: SboxTone.danger,
          icon: Icons.remove_shopping_cart_outlined,
          onTap: _can('PosProducts') ? () => _go('PosProducts') : null));
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
      // Bấm một nhân viên → các đơn người đó bán trong kỳ.
      onRowTap: (r) => _openOrders(
        soldBy: '${r['soldBy'] ?? ''}'.isEmpty ? null : '${r['soldBy']}',
        soldByLabel: '${r['displayName'] ?? r['soldBy'] ?? ''}',
      ),
      columns: [
        SboxColumn(label: 'Nhân viên', primary: true, flex: 3, text: (r) => '${r['displayName'] ?? r['soldBy'] ?? '—'}', sortValue: (r) => '${r['displayName'] ?? r['soldBy'] ?? ''}'),
        // Doanh thu đứng trước: thẻ điện thoại đưa cột số đầu tiên lên góc phải không kèm nhãn —
        // trước là «8» (số đơn) trơ trọi.
        SboxColumn(label: 'Doanh thu', numeric: true, flex: 2, text: (r) => SboxFmt.money(_n(r['revenue'])), sortValue: (r) => _n(r['revenue'])),
        SboxColumn(label: 'Số đơn', numeric: true, flex: 1, text: (r) => SboxFmt.number(_n(r['orderCount'])), sortValue: (r) => _n(r['orderCount'])),
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


  // ─── Lương hôm nay ───────────────────────────────────────────────


  // ─── Tin mới: truyền thông, công việc, KPI, phản ánh, sản lượng ─────

  Map<String, dynamic> _hl(String key) =>
      _highlights?[key] is Map ? Map<String, dynamic>.from(_highlights![key] as Map) : const {};

  String _when(dynamic iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    if (d == null) return '';
    final l = d.isUtc ? d.toLocal() : d;
    final now = DateTime.now();
    if (l.year == now.year && l.month == now.month && l.day == now.day) {
      return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
    }
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}';
  }

  Widget _newsCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required String module,
    List<(String, SboxTone)> chips = const [],
    required List<Map<String, dynamic>> items,
    bool showWhen = true,
  }) {
    return SboxChartCard(
      title: title,
      subtitle: subtitle,
      onMore: () => _go(module),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (chips.isNotEmpty)
          Wrap(spacing: SboxSpace.sm, runSpacing: SboxSpace.xs, children: [
            for (final c in chips) SboxStatusChip(label: c.$1, tone: c.$2),
          ]),
        if (chips.isNotEmpty && items.isNotEmpty) const SizedBox(height: SboxSpace.sm),
        for (final it in items)
          InkWell(
            onTap: () => _go(module),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Icon(icon, size: 18, color: SboxColors.textMuted),
                const SizedBox(width: SboxSpace.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${it['title'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    if ('${it['detail'] ?? ''}'.isNotEmpty)
                      Text('${it['detail']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SboxType.captionStyle(SboxColors.textMuted)),
                  ]),
                ),
                if (showWhen && _when(it['when']).isNotEmpty)
                  Text(_when(it['when']), style: SboxType.captionStyle(SboxColors.textMuted)),
              ]),
            ),
          ),
      ]),
    );
  }

  /// Chỉ khối có tin mới và người xem mở được module.
  List<Widget> _newsCards() {
    if (_highlights == null) return const [];
    final out = <Widget>[];
    final comm = _hl('communication');
    if (comm['hasNews'] == true && _can('Communication')) {
      out.add(_newsCard(
        title: 'Truyền thông nội bộ',
        subtitle: '${_n(comm['count']).round()} bài mới trong 3 ngày',
        icon: Icons.campaign_outlined,
        module: 'Communication',
        items: _list(comm['items']),
      ));
    }
    final task = _hl('tasks');
    if (task['hasNews'] == true && _can('Task')) {
      out.add(_newsCard(
        title: 'Công việc',
        subtitle: 'Hôm nay',
        icon: Icons.task_alt_outlined,
        module: 'Task',
        chips: [
          if (_n(task['overdue']) > 0) ('Quá hạn ${_n(task['overdue']).round()}', SboxTone.danger),
          if (_n(task['dueToday']) > 0) ('Hạn hôm nay ${_n(task['dueToday']).round()}', SboxTone.warning),
          if (_n(task['newToday']) > 0) ('Mới giao ${_n(task['newToday']).round()}', SboxTone.brand),
          if (_n(task['doneToday']) > 0) ('Xong ${_n(task['doneToday']).round()}', SboxTone.success),
        ],
        items: _list(task['items']),
      ));
    }
    final kpi = _hl('kpi');
    if (kpi['hasNews'] == true && _can('KPI')) {
      out.add(_newsCard(
        title: 'KPI',
        subtitle: [
          '${_n(kpi['updated']).round()} kết quả mới cập nhật',
          if ('${kpi['periodName'] ?? ''}'.isNotEmpty) '${kpi['periodName']}',
        ].join(' · '),
        icon: Icons.insights_outlined,
        module: 'KPI',
        chips: [
          if (kpi['avgCompletion'] != null) ('Hoàn thành TB ${SboxFmt.pct(_n(kpi['avgCompletion']))}', SboxTone.brand),
        ],
        items: _list(kpi['items']),
        showWhen: false,
      ));
    }
    final fb = _hl('feedback');
    if (fb['hasNews'] == true && _can('Feedback')) {
      out.add(_newsCard(
        title: 'Phản ánh / ý kiến',
        subtitle: '${_n(fb['pending']).round()} chưa xử lý · ${_n(fb['newCount']).round()} mới trong 3 ngày',
        icon: Icons.forum_outlined,
        module: 'Feedback',
        items: _list(fb['items']),
      ));
    }
    final prod = _hl('production');
    if (prod['hasNews'] == true && _can('Production')) {
      out.add(_newsCard(
        title: 'Sản lượng hôm nay',
        subtitle: '${_n(prod['entries']).round()} lượt nhập · ${_n(prod['employees']).round()} nhân viên',
        icon: Icons.precision_manufacturing_outlined,
        module: 'Production',
        chips: [
          ('SL ${SboxFmt.number(_n(prod['quantity']))}', SboxTone.brand),
          if (_n(prod['amount']) > 0) (SboxFmt.money(_n(prod['amount'])), SboxTone.success),
        ],
        items: _list(prod['items']),
        showWhen: false,
      ));
    }
    return out;
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

    if (_loading && _sales == null && _todos.isEmpty) {
      return SboxReportLayout(header: header, filters: filters, children: const [SizedBox(height: 240, child: SboxLoading(message: 'Đang tải số liệu…'))]);
    }

    final List<SboxKpi> kpis;
    final List<Widget> charts;
    Widget? table;
    String? tableTitle;
    final kpiGroups = <Widget>[];
    kpis = const [];
    kpiGroups.add(_kpiGroup('Bán hàng · ${_period.label}', [..._posKpis(), ..._moneyKpis()]));
    charts = [_revenueChart(), _todoCard(), ..._newsCards(), _topProducts(), _paymentDonut()];
    table = _staffTable();
    tableTitle = 'Doanh thu theo nhân viên bán';
    return Stack(children: [
      SboxReportLayout(
        header: widget.leading.isEmpty ? header : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, const SizedBox(height: SboxSpace.md), ...widget.leading]),
        filters: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (filters != null) ...[filters, const SizedBox(height: SboxSpace.md)],
          for (var i = 0; i < kpiGroups.length; i++) ...[
            if (i > 0) const SizedBox(height: SboxSpace.lg),
            kpiGroups[i],
          ],
        ]),
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
