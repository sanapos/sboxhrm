import 'package:flutter/material.dart';

import 'boss_load_error.dart';

import '../../l10n/app_tr.dart';
import '../../models/cash_transaction.dart';
import '../../screens/pos/pos_risk_report_screen.dart';
import '../../services/api_service.dart';
import '../../services/branch_session.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/branch_switcher.dart';
import '../../widgets/pos/pos_party_debt_detail_page.dart';
import '../../widgets/reports/report_drill_sheet.dart';
import '../../widgets/sbox/sbox_basics.dart';
import '../../widgets/sbox/sbox_charts.dart';
import '../../screens/staff/staff_nav.dart';
import 'boss_end_of_day_screen.dart';
import 'boss_manage_screen.dart' show openBossModule;
import 'boss_icon_badge.dart';
import 'boss_overview_sheets.dart';

/// Báo cáo trên SBOX BOSS — mỗi loại gọi đúng endpoint báo cáo POS sẵn có (cùng số liệu với web / máy POS).
enum BossReportType {
  business('Kinh doanh', 'Doanh thu, lợi nhuận, so kỳ trước và cùng kỳ năm trước', Icons.insights_rounded, true),
  pnl('Lãi lỗ', 'Doanh thu − giá vốn − chi phí = lãi ròng', Icons.account_balance_rounded, true),
  profit('Lãi theo món', 'Món lãi nhiều nhất, món đang lỗ', Icons.restaurant_menu_rounded, true),
  cashbook('Sổ quỹ', 'Tồn đầu, thu, chi, tồn cuối theo từng quỹ', Icons.account_balance_wallet_rounded, true),
  expenses('Chi phí', 'Chi theo danh mục', Icons.receipt_rounded, true),
  staff('Nhân viên bán hàng', 'Doanh số, số đơn theo nhân viên', Icons.badge_rounded, true),
  purchases('Nhập hàng', 'Tiền nhập, còn nợ nhà cung cấp', Icons.local_shipping_rounded, true),
  stock('Kho', 'Tồn kho, hàng hết, lô hết hạn, gợi ý nhập', Icons.inventory_2_rounded, false),
  debt('Công nợ', 'Khách nợ, nợ nhà cung cấp, tuổi nợ', Icons.request_quote_rounded, false);

  const BossReportType(this.label, this.subtitle, this.icon, this.hasPeriod);
  final String label;
  final String subtitle;
  final IconData icon;
  final bool hasPeriod;
}

/// SBOX BOSS — tab «Báo cáo»: danh sách báo cáo; «Nguy cơ gian lận» mở màn báo cáo rủi ro sẵn có.
class BossReportsScreen extends StatelessWidget {
  const BossReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    void open(Widget w) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    Widget tile(IconData icon, String title, String sub, VoidCallback onTap, {SboxTone tone = SboxTone.brand}) =>
        ListTile(
          leading: BossIconBadge(icon, size: 40, color: tone == SboxTone.brand ? null : tone.solid),
          title: Text(tr(title), style: SboxType.bodyStrong()),
          subtitle: Text(tr(sub)),
          trailing: const Icon(Icons.chevron_right_rounded, color: SboxColors.slate400),
          onTap: onTap,
        );
    final hr = [
      for (final h in _hrReports)
        if (staffCanOpen(context, h.$1)) h,
    ];
    return ListView(padding: const EdgeInsets.all(SboxSpace.lg), children: [
      SboxCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          tile(Icons.receipt_long_rounded, 'Cuối ngày', 'Tiền két, thực thu, hủy đơn, món bán chạy theo ngày', () {
            open(Scaffold(
              backgroundColor: SboxColors.page,
              appBar: AppBar(
                backgroundColor: SboxColors.bar,
                foregroundColor: SboxColors.isBoss ? SboxColors.onBar : SboxColors.white,
                title: Text(tr('Cuối ngày')),
                actions: const [
                  Padding(
                    padding: EdgeInsets.only(right: SboxSpace.sm),
                    child: Center(child: BranchSwitcher(compact: true, onDark: true)),
                  ),
                ],
              ),
              body: const BossEndOfDayScreen(),
            ));
          }),
          for (final t in BossReportType.values)
            tile(t.icon, t.label, t.subtitle, () => open(BossReportDetailScreen(type: t))),
          tile(Icons.policy_rounded, 'Nguy cơ gian lận', 'Hủy món sau tạm tính, đá bill, giảm giá tay…',
              () => open(const PosRiskReportScreen()),
              tone: SboxTone.danger),
        ]),
      ),
      // Báo cáo nhân sự (trước chỉ có ở tab Quản lý, chưa có Đi trễ / Về sớm và Phiếu phạt) — chỉ mục có quyền.
      if (hr.isNotEmpty) ...[
        const SizedBox(height: SboxSpace.md),
        SboxCard(
          title: 'Nhân sự',
          padding: EdgeInsets.zero,
          child: Column(children: [
            for (final h in hr) tile(h.$2, h.$3, h.$4, () => openBossModule(context, h.$1), tone: h.$5),
          ]),
        ),
      ],
    ]);
  }
}

/// (mã chức năng, biểu tượng, tên, mô tả, tông màu) — mở qua [openBossModule] như tab Quản lý.
const _hrReports = <(String, IconData, String, String, SboxTone)>[
  ('AttendanceSummary', Icons.table_chart_rounded, 'Tổng hợp chấm công', 'Ngày công, giờ làm từng nhân viên',
      SboxTone.brand),
  ('LateEarlyReport', Icons.alarm_rounded, 'Đi trễ / Về sớm', 'Số lần, số phút theo ca trong thiết lập lương',
      SboxTone.warning),
  ('PenaltyTickets', Icons.gavel_rounded, 'Phiếu phạt', 'Phạt đi trễ / về sớm tự động, chờ duyệt, đã thu',
      SboxTone.danger),
  ('Payroll', Icons.payments_rounded, 'Bảng lương', 'Lương, thưởng, phạt, ứng theo kỳ', SboxTone.success),
];

/// Kỳ báo cáo chọn nhanh.
enum _Period { today, yesterday, week, month, lastMonth, custom }

extension on _Period {
  String get label => switch (this) {
        _Period.today => 'Hôm nay',
        _Period.yesterday => 'Hôm qua',
        _Period.week => '7 ngày',
        _Period.month => 'Tháng này',
        _Period.lastMonth => 'Tháng trước',
        _Period.custom => 'Tùy chọn',
      };
}

double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

List<Map<String, dynamic>> _list(Object? v) =>
    [for (final e in (v is List ? v : const [])) if (e is Map) Map<String, dynamic>.from(e)];

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};

String _signedPct(Object? v) {
  final d = _num(v);
  return '${d >= 0 ? '+' : ''}${SboxFmt.pct(d)}';
}

/// Một báo cáo: thanh chọn kỳ + nội dung theo loại. Đổi chi nhánh ở thanh trên là tải lại.
class BossReportDetailScreen extends StatefulWidget {
  const BossReportDetailScreen({super.key, required this.type, this.startToday = false});

  final BossReportType type;

  /// Mở từ Tổng quan hôm nay: vào thẳng kỳ «Hôm nay» (Sổ quỹ / Lãi lỗ mặc định mở cả tháng).
  final bool startToday;

  @override
  State<BossReportDetailScreen> createState() => _BossReportDetailScreenState();
}

class _BossReportDetailScreenState extends State<BossReportDetailScreen> {
  _Period _period = _Period.today;
  late DateTimeRange _range = _rangeOf(_Period.today);
  List<Map<String, dynamic>?> _data = const [];
  String? _error;
  bool _loading = true;
  int _seq = 0;

  static DateTime _d(DateTime x) => DateTime(x.year, x.month, x.day);

  static DateTimeRange _rangeOf(_Period p) {
    final t = _d(DateTime.now());
    return switch (p) {
      _Period.today => DateTimeRange(start: t, end: t),
      _Period.yesterday => DateTimeRange(start: t.subtract(const Duration(days: 1)), end: t.subtract(const Duration(days: 1))),
      _Period.week => DateTimeRange(start: t.subtract(const Duration(days: 6)), end: t),
      _Period.month => DateTimeRange(start: DateTime(t.year, t.month), end: t),
      _Period.lastMonth => DateTimeRange(
          start: DateTime(t.year, t.month - 1), end: DateTime(t.year, t.month).subtract(const Duration(days: 1))),
      _Period.custom => DateTimeRange(start: t, end: t),
    };
  }

  @override
  void initState() {
    super.initState();
    if (!widget.startToday && (widget.type == BossReportType.cashbook || widget.type == BossReportType.pnl)) {
      _period = _Period.month;
      _range = _rangeOf(_Period.month);
    }
    BranchSession.instance.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    BranchSession.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _pickPeriod(_Period p) async {
    if (p == _Period.custom) {
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: _d(DateTime.now()),
        initialDateRange: _range,
      );
      if (r == null) return;
      _range = DateTimeRange(start: _d(r.start), end: _d(r.end));
    } else {
      _range = _rangeOf(p);
    }
    setState(() => _period = p);
    _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ApiService();
    final from = _range.start;
    final to = _range.end;
    final calls = switch (widget.type) {
      BossReportType.business => [api.getPosBusinessAnalysis(from: from, to: to)],
      BossReportType.pnl => [api.getPosPnlReport(from: from, to: to)],
      BossReportType.profit => [api.getPosProfitByProduct(from: from, to: to, limit: 200)],
      BossReportType.cashbook => [api.getPosCashbookReport(from: from, to: to)],
      BossReportType.expenses => [api.getPosExpenseReport(from: from, to: to)],
      BossReportType.staff => [api.getPosStaffSummary(from: from, to: to)],
      BossReportType.purchases => [api.getPosPurchasesReport(from: from, to: to)],
      BossReportType.stock => [
          api.getPosStockReportSummary(),
          api.getPosStockLotReportSummary(),
          api.getPosReorderSuggestions(),
          api.getPosStockHealthReport(limit: 30),
        ],
      BossReportType.debt => [api.getPosCustomerDebtReport(), api.getPosSupplierDebtReport()],
    };
    final results = await Future.wait(calls);
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      _data = [for (final r in results) r['isSuccess'] == true && r['data'] is Map ? Map<String, dynamic>.from(r['data'] as Map) : null];
      if (_data.isNotEmpty && _data.first == null) {
        _error = results.first['message']?.toString() ?? 'Không tải được báo cáo';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.type;
    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: AppBar(
        backgroundColor: SboxColors.bar,
        foregroundColor: SboxColors.isBoss ? SboxColors.onBar : SboxColors.white,
        title: Text(tr(t.label)),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: SboxSpace.sm),
            child: Center(child: BranchSwitcher(compact: true, onDark: true)),
          ),
        ],
      ),
      body: Column(children: [
        if (t.hasPeriod)
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: SboxSpace.md, vertical: SboxSpace.sm),
              children: [
                for (final p in _Period.values)
                  Padding(
                    padding: const EdgeInsets.only(right: SboxSpace.sm),
                    child: ChoiceChip(
                      label: Text(p == _Period.custom && _period == _Period.custom
                          ? '${_range.start.day}/${_range.start.month} – ${_range.end.day}/${_range.end.month}'
                          : tr(p.label)),
                      selected: _period == p,
                      onSelected: (_) => _pickPeriod(p),
                    ),
                  ),
              ],
            ),
          ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _error != null
              ? BossLoadError(title: 'Không tải được báo cáo', message: _error, onRetry: _load)
              : _data.isEmpty || _data.first == null
                  ? const SboxLoading()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(SboxSpace.lg, SboxSpace.sm, SboxSpace.lg, SboxSpace.xxl),
                        children: _body(),
                      ),
                    ),
        ),
      ]),
    );
  }

  static const _gap = SizedBox(height: SboxSpace.md);

  Widget _pair(Widget a, Widget b) => Row(children: [Expanded(child: a), const SizedBox(width: SboxSpace.md), Expanded(child: b)]);

  Widget _metric(String label, num? v,
          {SboxTone tone = SboxTone.brand, String? delta, bool? up, bool money = true, VoidCallback? onTap}) =>
      SboxMetricCard(
        label: label,
        value: money ? SboxFmt.compact(v) : SboxFmt.number(v),
        tone: tone,
        delta: delta,
        deltaUp: up,
        onTap: onTap,
      );

  /// Dòng (nhãn, số tiền, màu, bấm) — dòng có [VoidCallback] hiện mũi tên và mở chi tiết.
  Widget _lines(String title, List<(String, num?, Color?, VoidCallback?)> rows) => SboxCard(
        title: title,
        child: Column(children: [
          for (final r in rows)
            InkWell(
              onTap: r.$4,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: SboxSpace.xs),
                child: Row(children: [
                  Expanded(child: Text(tr(r.$1), style: SboxType.bodyStyle(SboxColors.textSecondary))),
                  Text(SboxFmt.money(r.$2), style: SboxType.moneyStyle(c: r.$3 ?? SboxColors.text)),
                  if (r.$4 != null) const Icon(Icons.chevron_right_rounded, size: 18, color: SboxColors.slate400),
                ]),
              ),
            ),
        ]),
      );

  Widget _rank(String title, List<SboxSlice> items,
          {int max = 10, Color color = SboxColors.brand500, String? subtitle, void Function(int index)? onTapIndex}) =>
      SboxCard(
        title: title,
        subtitle: subtitle,
        child: SboxRankList(
          items: items,
          maxItems: max,
          color: color,
          onTap: onTapIndex == null
              ? null
              : (s) {
                  final i = items.indexOf(s);
                  if (i >= 0) onTapIndex(i);
                },
        ),
      );

  // ─── Chi tiết số liệu («số này từ đâu ra») ────────────────────────────────

  static String _dmy(DateTime d) => '${d.day}/${d.month}/${d.year}';

  String get _periodText =>
      _range.start == _range.end ? _dmy(_range.start) : '${_dmy(_range.start)} – ${_dmy(_range.end)}';

  static String _dm(Object? raw) {
    var d = DateTime.tryParse('${raw ?? ''}');
    if (d == null) return '';
    if (d.isUtc) d = d.toLocal();
    return '${d.day}/${d.month}/${d.year}';
  }

  void _sheet(String title, List<ReportDrillRow> rows,
          {String? note, String? total, String? footer, String? countLabel, bool period = true, bool showCount = true}) =>
      showReportDrillSheet(
        context,
        title: title,
        subtitle: period ? _periodText : null,
        note: note,
        rows: rows,
        total: total,
        footer: footer,
        countLabel: countLabel,
        showCount: showCount,
      );

  void _orders(String title, {String? note, String? staffKey, String? productId, bool showTotal = true}) =>
      showBossSalesOrdersDrill(
        context,
        title: title,
        from: _range.start,
        to: _range.end,
        staffKey: staffKey,
        productId: productId,
        subtitle: _periodText,
        note: note,
        showTotal: showTotal,
      );

  void _cash(String title, String route, Map<String, String> query, {String? note}) => showBossCashDrill(
        context,
        title: title,
        path: '/api/pos/reports/drill-boss/$route',
        query: {'from': _range.start.toIso8601String(), 'to': _range.end.toIso8601String(), ...query},
        subtitle: _periodText,
        note: note,
      );

  /// Lãi / doanh thu / giá vốn theo món (profit/by-product) — [d] là dữ liệu báo cáo «Lãi theo món».
  void _productSheet(String title, Map<String, dynamic> d, {required String field, String? note, String? category}) {
    var items = _list(d['items']);
    if (category != null) items = items.where((i) => '${i['categoryName'] ?? 'Khác'}' == category).toList();
    if (field != 'profit') items = items.where((i) => _num(i[field]) != 0).toList();
    items.sort((a, b) => _num(b[field]).compareTo(_num(a[field])));
    final totalKey = switch (field) { 'revenue' => 'totalRevenue', 'cogs' => 'totalCogs', _ => 'totalProfit' };
    final truncated = d['truncated'] == true;
    final sum = items.fold<double>(0, (a, i) => a + _num(i[field]));
    _sheet(
      title,
      [
        for (final i in items)
          ReportDrillRow(
            title: '${i['productName'] ?? ''}',
            icon: Icons.restaurant_menu_rounded,
            subtitle: '${tr('Bán')} ${SboxFmt.qty(_num(i['qty']))} · ${tr('doanh thu')} ${SboxFmt.money(_num(i['revenue']))}'
                ' · ${tr('giá vốn')} ${SboxFmt.money(_num(i['cogs']))}',
            trailing: SboxFmt.money(_num(i[field])),
            trailingColor: _num(i[field]) < 0 ? SboxColors.dangerText : null,
            onTap: '${i['productId'] ?? ''}'.isEmpty || _num(i['revenue']) == 0
                ? null
                : () => _orders('Đơn có ${i['productName'] ?? ''}',
                    productId: '${i['productId']}',
                    showTotal: false,
                    note: 'Số tiền mỗi dòng là cả đơn, không riêng món này.'),
          ),
      ],
      note: note,
      total: 'Tổng ${SboxFmt.money(category == null && !truncated ? _num(d[totalKey]) : sum)}',
      footer: truncated
          ? 'Cửa hàng có ${SboxFmt.number(_num(d['skuCount']))} món; danh sách chỉ giữ món lãi nhiều nhất và lỗ nhiều nhất, '
              'dòng tổng tính trên mọi món.'
          : null,
    );
  }

  /// Tải «Lãi theo món» cùng kỳ (dùng cho Kinh doanh / Lãi lỗ) rồi mở danh sách theo món.
  Future<void> _profitByProduct(String title, {required String field, String? note, String? category}) async {
    final d = await bossDrillFetch(context, () async {
      final r = await ApiService().getPosProfitByProduct(from: _range.start, to: _range.end, limit: 1000);
      if (r['isSuccess'] != true || r['data'] is! Map) throw Exception(r['message'] ?? 'Không tải được báo cáo');
      return Map<String, dynamic>.from(r['data'] as Map);
    });
    if (d == null || !mounted) return;
    _productSheet(title, d, field: field, note: note, category: category);
  }

  ReportDrillRow _receiptRow(Map<String, dynamic> r, num value, {String? extra}) => ReportDrillRow(
        title: '${r['receiptNo'] ?? r['returnNo'] ?? ''}',
        icon: Icons.local_shipping_rounded,
        subtitle: [
          _dm(r['date']),
          '${r['supplierName'] ?? ''}'.isEmpty ? tr('Không chọn NCC') : '${r['supplierName']}',
          if (extra != null) extra,
        ].where((s) => s.isNotEmpty).join(' · '),
        trailing: SboxFmt.money(value),
      );

  ReportDrillRow _debtRow(Map<String, dynamic> c, String field) => ReportDrillRow(
        title: '${c['name'] ?? ''}',
        subtitle: [
          if ('${c['customerCode'] ?? c['supplierCode'] ?? ''}'.isNotEmpty) '${c['customerCode'] ?? c['supplierCode']}',
          if ('${c['phone'] ?? ''}'.isNotEmpty) '${c['phone']}',
          if (_num(c['debtOver90']) > 0 && field == 'currentDebt')
            '${tr('quá 90 ngày')} ${SboxFmt.money(_num(c['debtOver90']))}',
        ].join(' · '),
        trailing: SboxFmt.money(_num(c[field])),
      );

  void _debtSheet(String title, Map<String, dynamic> m, String field, String totalKey, {String? note}) {
    final items = _list(m['items']).where((c) => _num(c[field]) != 0).toList()
      ..sort((a, b) => _num(b[field]).compareTo(_num(a[field])));
    _sheet(title, [for (final c in items) _debtRow(c, field)],
        period: false, note: note, total: 'Tổng ${SboxFmt.money(_num(m[totalKey]))}');
  }

  List<Widget> _body() {
    final d = _data.first!;
    switch (widget.type) {
      case BossReportType.business:
        final cur = _map(d['current']);
        final prev = _map(d['previous']);
        final ch = _map(d['changePct']);
        final yoy = _map(d['changePctYoy']);
        final prevNote = 'Kỳ trước (cùng số ngày, ngay trước kỳ này): doanh thu ${SboxFmt.money(_num(prev['revenue']))}, '
            '${SboxFmt.number(_num(prev['orderCount']))} đơn, lợi nhuận gộp ${SboxFmt.money(_num(prev['profit']))}.';
        void revenueOrders() => _orders('Doanh thu',
            note: 'Doanh thu = Σ tiền hàng các đơn hoàn thành (đã trừ giảm giá và hàng khách trả, chưa VAT) = '
                '${SboxFmt.money(_num(cur['revenue']))} (${_signedPct(ch['revenue'])} so kỳ trước). $prevNote');
        void grossProfit() => _profitByProduct('Lợi nhuận gộp theo món',
            field: 'profit',
            note: 'Lợi nhuận gộp = Doanh thu ${SboxFmt.money(_num(cur['revenue']))} − Giá vốn ${SboxFmt.money(_num(cur['cogs']))} = '
                '${SboxFmt.money(_num(cur['profit']))} (${_signedPct(ch['profit'])} so kỳ trước). $prevNote');
        return [
          _pair(
            _metric('Doanh thu', _num(cur['revenue']),
                delta: '${_signedPct(ch['revenue'])} ${tr('kỳ trước')}', up: _num(ch['revenue']) >= 0, onTap: revenueOrders),
            _metric('Lợi nhuận gộp', _num(cur['profit']),
                tone: SboxTone.success,
                delta: '${_signedPct(ch['profit'])} ${tr('kỳ trước')}',
                up: _num(ch['profit']) >= 0,
                onTap: grossProfit),
          ),
          _gap,
          _pair(
            _metric('Số đơn', _num(cur['orderCount']),
                money: false,
                tone: SboxTone.neutral,
                delta: '${_signedPct(ch['orders'])} ${tr('kỳ trước')}',
                up: _num(ch['orders']) >= 0,
                onTap: () => _orders('Số đơn',
                    note: '${SboxFmt.number(_num(cur['orderCount']))} đơn hoàn thành trong kỳ '
                        '(${_signedPct(ch['orders'])} so kỳ trước). $prevNote')),
            _metric('TB / đơn', _num(cur['avgOrderValue']),
                tone: SboxTone.neutral,
                delta: '${tr('Kỳ trước')} ${SboxFmt.compact(_num(prev['avgOrderValue']))}',
                onTap: () => _orders('TB / đơn',
                    note: 'TB / đơn = Doanh thu ${SboxFmt.money(_num(cur['revenue']))} ÷ ${SboxFmt.number(_num(cur['orderCount']))} đơn '
                        '= ${SboxFmt.money(_num(cur['avgOrderValue']))}. Kỳ trước: ${SboxFmt.money(_num(prev['revenue']))} ÷ '
                        '${SboxFmt.number(_num(prev['orderCount']))} đơn = ${SboxFmt.money(_num(prev['avgOrderValue']))}.')),
          ),
          _gap,
          _lines('Chi tiết', [
            ('Doanh thu (gồm VAT)', _num(cur['revenueInclVat']), null, () => _orders('Doanh thu (gồm VAT)',
                note: 'Doanh thu ${SboxFmt.money(_num(cur['revenue']))} + VAT ${SboxFmt.money(_num(cur['vat']))} = '
                    '${SboxFmt.money(_num(cur['revenueInclVat']))}. Số tiền mỗi đơn dưới đây chưa gồm VAT.')),
            ('Giảm giá', _num(cur['discount']), SboxColors.warningText, null),
            ('Hàng khách trả', _num(cur['refund']), SboxColors.dangerText, null),
            ('Giá vốn', _num(cur['cogs']), null, () => _profitByProduct('Giá vốn theo món',
                field: 'cogs',
                note: 'Giá vốn của các món đã bán trong kỳ (đã trừ hàng khách trả) — báo cáo Kinh doanh: '
                    '${SboxFmt.money(_num(cur['cogs']))}.')),
            ('Lợi nhuận gộp', _num(cur['profit']), SboxColors.successText, grossProfit),
          ]),
          _gap,
          SboxCard(
            title: 'So cùng kỳ năm trước',
            child: Text(
              tr('Doanh thu ${_signedPct(yoy['revenue'])} · lợi nhuận ${_signedPct(yoy['profit'])} · số đơn ${_signedPct(yoy['orders'])}'),
              style: SboxType.bodyStyle(),
            ),
          ),
          _gap,
          _rank('Theo kênh bán', [
            for (final c in _list(d['byChannel']))
              SboxSlice(tr('${c['channel'] ?? 'Khác'}'), _num(c['revenue']), caption: '${SboxFmt.number(_num(c['count']))} ${tr('đơn')}'),
          ]),
          _gap,
          () {
            final cats = _list(d['topCategories']);
            return _rank('Nhóm hàng bán chạy', [
              for (final c in cats) SboxSlice('${c['categoryName'] ?? ''}', _num(c['revenue'])),
            ], color: SboxColors.violet, onTapIndex: (i) {
              final name = '${cats[i]['categoryName'] ?? 'Khác'}';
              _profitByProduct('Nhóm $name',
                  field: 'revenue',
                  category: name,
                  note: 'Doanh thu các món thuộc nhóm «$name» trong kỳ: ${SboxFmt.money(_num(cats[i]['revenue']))}.');
            });
          }(),
        ];
      case BossReportType.pnl:
        final net = _num(d['netProfit']);
        final revenue = _num(d['revenue']);
        final lines = _list(d['lines']);
        void revenueOrders() => _orders('Doanh thu thuần',
            note: 'Doanh thu thuần = Σ tiền hàng các đơn hoàn thành trong kỳ (đã trừ giảm giá, hàng khách trả; chưa VAT) '
                '= ${SboxFmt.money(revenue)}.');
        void netSheet() => _sheet(
              'Lãi ròng',
              [
                for (final l in lines)
                  if ('${l['code']}' != '50' && _num(l['amount']) != 0)
                    ReportDrillRow(
                      title: '${l['label'] ?? ''}',
                      icon: Icons.account_balance_rounded,
                      subtitle: '${l['code']}' == '10' || '${l['code']}' == '20' ? tr('Dòng tổng phụ, không cộng thêm') : null,
                      trailing: SboxFmt.money(_num(l['amount'])),
                      trailingColor: _num(l['amount']) < 0 ? SboxColors.dangerText : null,
                      onTap: _pnlLineTap(d, '${l['code']}'),
                    ),
              ],
              note: 'Lãi ròng = Lợi nhuận gộp − hao hụt kho + phụ thu / phí giao − cước vận chuyển − khấu hao − chi phí hoạt động '
                  '+ cọc khách bỏ + thu nhập khác = ${SboxFmt.money(net)}. Biên lãi ròng = Lãi ròng ÷ Doanh thu thuần '
                  '${SboxFmt.money(revenue)} = ${SboxFmt.pct(_num(d['netMarginPct']))}.',
              total: 'Lãi ròng ${SboxFmt.money(net)}',
              showCount: false,
            );
        return [
          _pair(
            _metric('Doanh thu thuần', revenue, onTap: revenueOrders),
            _metric('Lãi ròng', net,
                tone: net >= 0 ? SboxTone.success : SboxTone.danger,
                delta: '${tr('Biên')} ${SboxFmt.pct(_num(d['netMarginPct']))}',
                up: net >= 0,
                onTap: netSheet),
          ),
          _gap,
          SboxCard(
            title: 'Báo cáo lãi lỗ',
            child: Column(children: [
              for (final l in lines)
                InkWell(
                  onTap: _pnlLineTap(d, '${l['code']}') ?? ('${l['code']}' == '50' ? netSheet : null),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: SboxSpace.xs),
                    child: Row(children: [
                      Expanded(
                        child: Text(tr('${l['label'] ?? ''}'),
                            style: '${l['code']}' == '50' || '${l['code']}' == '20'
                                ? SboxType.bodyStrong()
                                : SboxType.bodyStyle(SboxColors.textSecondary)),
                      ),
                      Text(SboxFmt.money(_num(l['amount'])),
                          style: SboxType.moneyStyle(c: _num(l['amount']) < 0 ? SboxColors.dangerText : SboxColors.text)),
                      if (_pnlLineTap(d, '${l['code']}') != null || '${l['code']}' == '50')
                        const Icon(Icons.chevron_right_rounded, size: 18, color: SboxColors.slate400),
                    ]),
                  ),
                ),
            ]),
          ),
          _gap,
          () {
            final cats = _list(d['expenseByCategory']);
            return _rank('Chi phí theo danh mục', [
              for (final c in cats) SboxSlice(tr('${c['category'] ?? ''}'), _num(c['amount'])),
            ], color: SboxColors.danger, onTapIndex: (i) {
              final name = '${cats[i]['category'] ?? ''}';
              if (name == 'Lương — phần đã ứng trước') {
                _sheet(name, const [],
                    note: 'Phiếu chi lương chỉ ghi số thực nhận (đã trừ tiền ứng). Kỳ lương được chi lần đầu trong kỳ này '
                        'được cộng lại phần ứng đã trừ: ${SboxFmt.money(_num(cats[i]['amount']))}. Khoản này không có phiếu chi riêng.');
                return;
              }
              _cash('Chi phí · ${tr(name)}', 'pnl-cash', {'kind': 'expense', 'category': name});
            });
          }(),
        ];
      case BossReportType.profit:
        final items = _list(d['items']);
        final losses = items.where((i) => _num(i['profit']) < 0).toList()
          ..sort((a, b) => _num(a['profit']).compareTo(_num(b['profit'])));
        void productOrders(Map<String, dynamic> i) => _orders('Đơn có ${i['productName'] ?? ''}',
            productId: '${i['productId'] ?? ''}', showTotal: false, note: 'Số tiền mỗi dòng là cả đơn, không riêng món này.');
        final rankItems = [
          for (final i in items)
            SboxSlice('${i['productName'] ?? ''}', _num(i['profit']),
                caption: '${tr('Bán')} ${SboxFmt.qty(_num(i['qty']))} · ${tr('biên')} ${SboxFmt.pct(_num(i['marginPct']))}'),
        ];
        return [
          _pair(
            _metric('Lợi nhuận gộp', _num(d['totalProfit']),
                tone: SboxTone.success,
                delta: '${tr('Biên')} ${SboxFmt.pct(_num(d['marginPct']))}',
                onTap: () => _productSheet('Lợi nhuận gộp theo món', d,
                    field: 'profit',
                    note: 'Lợi nhuận gộp = Doanh thu ${SboxFmt.money(_num(d['totalRevenue']))} − Giá vốn '
                        '${SboxFmt.money(_num(d['totalCogs']))} = ${SboxFmt.money(_num(d['totalProfit']))}. '
                        'Biên = Lợi nhuận gộp ÷ Doanh thu = ${SboxFmt.pct(_num(d['marginPct']))}.')),
            _metric('Doanh thu', _num(d['totalRevenue']),
                delta: '${SboxFmt.number(_num(d['skuCount']))} ${tr('món')}',
                onTap: () => _productSheet('Doanh thu theo món', d,
                    field: 'revenue',
                    note: 'Doanh thu từng món = tiền dòng bán đã phân bổ giảm giá đơn, trừ hàng khách trả (chưa VAT). '
                        '${SboxFmt.number(_num(d['skuCount']))} món có bán hoặc có giá vốn trong kỳ.')),
          ),
          _gap,
          _rank('Lãi nhiều nhất', rankItems, color: SboxColors.success, onTapIndex: (i) => productOrders(items[i])),
          if (losses.isNotEmpty) ...[
            _gap,
            SboxCard(
              title: 'Đang lỗ (giá bán thấp hơn giá vốn)',
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final i in losses.take(15))
                  ListTile(
                    dense: true,
                    onTap: _num(i['revenue']) == 0 ? null : () => productOrders(i),
                    title: Text('${i['productName'] ?? ''}'),
                    subtitle: Text('${tr('Bán')} ${SboxFmt.qty(_num(i['qty']))} · ${tr('doanh thu')} ${SboxFmt.money(_num(i['revenue']))}'),
                    trailing: Text(SboxFmt.money(_num(i['profit'])), style: SboxType.moneyStyle(c: SboxColors.dangerText)),
                  ),
              ]),
            ),
          ],
        ];
      case BossReportType.cashbook:
        final days = _list(d['byDay']);
        final methods = _list(d['balanceByMethod']);
        void income() => _cash('Phiếu thu', 'cashbook', {'type': 'Income'});
        void expense() => _cash('Phiếu chi', 'cashbook', {'type': 'Expense'});
        void byMethod(String title, String field, String note) => _sheet(
              title,
              [
                for (final b in methods)
                  ReportDrillRow(
                    title: tr(PaymentMethodType.parse(b['paymentMethod']).label),
                    icon: Icons.account_balance_wallet_rounded,
                    subtitle: '${tr('Đầu kỳ')} ${SboxFmt.money(_num(b['opening']))} · ${tr('thu')} ${SboxFmt.money(_num(b['income']))}'
                        ' · ${tr('chi')} ${SboxFmt.money(_num(b['expense']))}',
                    trailing: SboxFmt.money(_num(b[field])),
                    onTap: () => _cash('Phiếu · ${tr(PaymentMethodType.parse(b['paymentMethod']).label)}', 'cashbook',
                        {'type': field == 'expense' ? 'Expense' : 'Income', 'paymentMethod': '${b['paymentMethod'] ?? ''}'}),
                  ),
              ],
              note: note,
              total: 'Tổng ${SboxFmt.money(methods.fold<double>(0, (a, b) => a + _num(b[field])))}',
            );
        return [
          _pair(_metric('Thu', _num(d['income']), tone: SboxTone.success, onTap: income),
              _metric('Chi', _num(d['expense']), tone: SboxTone.danger, onTap: expense)),
          _gap,
          if (d.containsKey('openingBalance'))
            _lines('Tồn quỹ', [
              ('Tồn đầu kỳ', _num(d['openingBalance']), null, methods.isEmpty
                  ? null
                  : () => byMethod('Tồn đầu kỳ', 'opening',
                      'Tồn đầu kỳ = Σ thu − Σ chi của mọi phiếu hoàn thành trước ngày ${_dmy(_range.start)}, tách theo quỹ. '
                          'Bấm một quỹ để xem phiếu thu trong kỳ của quỹ đó.')),
              ('Thu trong kỳ', _num(d['income']), SboxColors.successText, income),
              ('Chi trong kỳ', _num(d['expense']), SboxColors.dangerText, expense),
              ('Tồn cuối kỳ', _num(d['closingBalance']), SboxColors.brand700, methods.isEmpty
                  ? null
                  : () => byMethod('Tồn cuối kỳ', 'closing',
                      'Tồn cuối = Tồn đầu ${SboxFmt.money(_num(d['openingBalance']))} + Thu ${SboxFmt.money(_num(d['income']))} − '
                          'Chi ${SboxFmt.money(_num(d['expense']))} = ${SboxFmt.money(_num(d['closingBalance']))}. '
                          'Bấm một quỹ để xem phiếu thu trong kỳ của quỹ đó.')),
            ]),
          if (d.containsKey('balanceByMethod')) ...[
            _gap,
            _lines('Tồn cuối theo quỹ', [
              for (final b in methods)
                (
                  tr(PaymentMethodType.parse(b['paymentMethod']).label),
                  _num(b['closing']),
                  null,
                  () => _sheet(
                        'Quỹ ${tr(PaymentMethodType.parse(b['paymentMethod']).label)}',
                        [
                          ReportDrillRow(
                              title: 'Tồn đầu kỳ', icon: Icons.flag_rounded, trailing: SboxFmt.money(_num(b['opening']))),
                          ReportDrillRow(
                            title: 'Thu trong kỳ',
                            icon: Icons.south_west_rounded,
                            trailing: '+${SboxFmt.money(_num(b['income']))}',
                            trailingColor: SboxColors.successText,
                            onTap: () => _cash('Phiếu thu · ${tr(PaymentMethodType.parse(b['paymentMethod']).label)}', 'cashbook',
                                {'type': 'Income', 'paymentMethod': '${b['paymentMethod'] ?? ''}'}),
                          ),
                          ReportDrillRow(
                            title: 'Chi trong kỳ',
                            icon: Icons.north_east_rounded,
                            trailing: '−${SboxFmt.money(_num(b['expense']))}',
                            trailingColor: SboxColors.dangerText,
                            onTap: () => _cash('Phiếu chi · ${tr(PaymentMethodType.parse(b['paymentMethod']).label)}', 'cashbook',
                                {'type': 'Expense', 'paymentMethod': '${b['paymentMethod'] ?? ''}'}),
                          ),
                        ],
                        note: 'Tồn cuối = Tồn đầu + Thu − Chi của riêng quỹ này.',
                        total: 'Tồn cuối ${SboxFmt.money(_num(b['closing']))}',
                        showCount: false,
                      ),
                ),
            ]),
          ],
          if (days.length > 1) ...[
            _gap,
            SboxCard(
              title: 'Thu chi theo ngày',
              child: SboxBarChart(
                height: 200,
                labels: [
                  for (final x in days)
                    () {
                      final dt = DateTime.tryParse('${x['date']}');
                      return dt == null ? '' : '${dt.day}/${dt.month}';
                    }(),
                ],
                series: [
                  SboxSeries(name: tr('Thu'), values: [for (final x in days) _num(x['income'])], color: SboxColors.success),
                  SboxSeries(name: tr('Chi'), values: [for (final x in days) _num(x['expense'])], color: SboxColors.danger),
                ],
              ),
            ),
          ],
        ];
      case BossReportType.expenses:
        final cats = _list(d['byCategory']);
        const excludedNote = 'Không gồm phiếu chi nhập hàng (vào giá vốn), trả hàng khách (giảm doanh thu), hoàn cọc đặt chỗ.';
        void all() => _cash('Phiếu chi phí', 'expenses', const {}, note: excludedNote);
        return [
          _pair(
            _metric('Tổng chi phí', _num(d['total']), tone: SboxTone.danger, onTap: all),
            _metric('Số phiếu chi', _num(d['count']), money: false, tone: SboxTone.neutral, onTap: all),
          ),
          _gap,
          _rank('Theo danh mục', [
            for (final c in cats)
              SboxSlice(tr('${c['category'] ?? ''}'), _num(c['total']), caption: '${SboxFmt.number(_num(c['count']))} ${tr('phiếu')}'),
          ], color: SboxColors.danger, onTapIndex: (i) {
            final name = '${cats[i]['category'] ?? 'Khác'}';
            _cash('Chi phí · ${tr(name)}', 'expenses', {'category': name});
          }),
          _gap,
          SboxCard(
            title: 'Phiếu chi gần nhất',
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final i in _list(d['items']).take(30))
                ListTile(
                  dense: true,
                  title: Text('${i['description'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${i['transactionCode'] ?? ''} · ${tr('${i['category'] ?? ''}')}'),
                  trailing: Text(SboxFmt.money(_num(i['amount'])), style: SboxType.moneyStyle()),
                ),
            ]),
          ),
        ];
      case BossReportType.staff:
        final staff = _list(d['staff']);
        void staffOrders(Map<String, dynamic> s) => _orders('Đơn của ${s['displayName'] ?? s['soldBy'] ?? ''}',
            staffKey: '${s['staffKey'] ?? ''}',
            note: '${SboxFmt.number(_num(s['orderCount']))} đơn · doanh số ${SboxFmt.money(_num(s['revenue']))} · '
                'TB / đơn ${SboxFmt.money(_num(s['avgOrder']))} (= doanh số ÷ số đơn).');
        return [
          _pair(
            _metric('Doanh số', _num(d['totalRevenue']),
                onTap: () => _orders('Doanh số',
                    note: 'Doanh số = Σ tiền hàng các đơn hoàn thành trong kỳ (chưa VAT) = ${SboxFmt.money(_num(d['totalRevenue']))}, '
                        '${SboxFmt.number(_num(d['orderCount']))} đơn.')),
            _metric('Nhân viên bán', _num(d['staffCount']),
                money: false,
                tone: SboxTone.neutral,
                delta: '${SboxFmt.number(_num(d['orderCount']))} ${tr('đơn')}',
                onTap: () => _sheet(
                      'Nhân viên bán',
                      [
                        for (final s in staff)
                          ReportDrillRow(
                            title: '${s['displayName'] ?? s['soldBy'] ?? ''}',
                            subtitle: '${SboxFmt.number(_num(s['orderCount']))} ${tr('đơn')} · ${tr('TB')} ${SboxFmt.money(_num(s['avgOrder']))}',
                            trailing: SboxFmt.money(_num(s['revenue'])),
                            onTap: () => staffOrders(s),
                          ),
                      ],
                      note: 'Mỗi người ghi trên đơn (người bán) là một dòng; đơn không ghi người bán gộp «Chưa ghi người bán».',
                      total: 'Tổng ${SboxFmt.money(_num(d['totalRevenue']))} · ${SboxFmt.number(_num(d['orderCount']))} đơn',
                    )),
          ),
          _gap,
          _rank('Doanh số theo nhân viên', [
            for (final s in staff)
              SboxSlice('${s['displayName'] ?? s['soldBy'] ?? ''}', _num(s['revenue']),
                  caption: '${SboxFmt.number(_num(s['orderCount']))} ${tr('đơn')} · ${tr('TB')} ${SboxFmt.compact(_num(s['avgOrder']))}'),
          ], max: 30, onTapIndex: (i) => staffOrders(staff[i])),
        ];
      case BossReportType.purchases:
        final receipts = _list(d['receipts']);
        final returns = _list(d['returns']);
        final suppliers = _list(d['bySupplier']);
        void receiptSheet(String title, List<Map<String, dynamic>> list, {String? note}) => _sheet(
              title,
              [
                for (final r in list)
                  _receiptRow(r, _num(r['grandTotal']),
                      extra: _num(r['balanceDue']) != 0 ? '${tr('còn nợ')} ${SboxFmt.money(_num(r['balanceDue']))}' : null),
              ],
              note: note,
              total: 'Tổng ${SboxFmt.money(list.fold<double>(0, (a, r) => a + _num(r['grandTotal'])))}',
            );
        return [
          _pair(
            _metric('Tiền nhập hàng', _num(d['receiptAmount']),
                delta: '${SboxFmt.number(_num(d['receiptCount']))} ${tr('phiếu')}',
                onTap: () => receiptSheet('Phiếu nhập hàng', receipts,
                    note: 'Tiền mỗi phiếu = tiền hàng + VAT − chiết khấu (phiếu nhập hoàn thành trong kỳ).')),
            _metric('Còn nợ NCC', _num(d['balanceDue']),
                tone: SboxTone.warning,
                onTap: () => _sheet(
                      'Phiếu nhập còn nợ',
                      [
                        for (final r in receipts.where((r) => _num(r['balanceDue']) != 0))
                          _receiptRow(r, _num(r['balanceDue']),
                              extra: '${tr('phiếu')} ${SboxFmt.money(_num(r['grandTotal']))} · ${tr('đã trả')} ${SboxFmt.money(_num(r['paidAmount']))}'),
                      ],
                      note: 'Còn nợ = tiền phiếu − đã trả, chỉ tính các phiếu nhập trong kỳ (không gồm nợ phiếu kỳ trước).',
                      total: 'Tổng ${SboxFmt.money(_num(d['balanceDue']))}',
                    )),
          ),
          _gap,
          _lines('Chi tiết', [
            ('Đã trả trong kỳ', _num(d['paidInPeriod']), null, () => _sheet(
                  'Tiền đã trả trên phiếu nhập trong kỳ',
                  [
                    for (final r in receipts.where((r) => _num(r['paidAmount']) != 0))
                      _receiptRow(r, _num(r['paidAmount'])),
                  ],
                  note: 'Đã trả trong kỳ ${SboxFmt.money(_num(d['paidInPeriod']))} = mọi khoản trả nhà cung cấp trong kỳ, gồm cả trả nợ '
                      'phiếu kỳ trước — nên có thể lớn hơn tổng tiền đã trả trên các phiếu nhập trong kỳ dưới đây '
                      '(${SboxFmt.money(_num(d['paidOnReceipts']))}).',
                  total: 'Tổng trên phiếu ${SboxFmt.money(_num(d['paidOnReceipts']))}',
                )),
            ('Trả hàng nhà cung cấp', _num(d['returnAmount']), null, () => _sheet(
                  'Phiếu trả hàng NCC',
                  [for (final r in returns) _receiptRow(r, _num(r['netAmount']))],
                  note: 'Tiền mỗi phiếu = tiền hàng trả + VAT − chiết khấu.',
                  total: 'Tổng ${SboxFmt.money(_num(d['returnAmount']))}',
                )),
            ('Nhập thuần', _num(d['netAmount']), SboxColors.brand700, () => _sheet(
                  'Nhập thuần',
                  [
                    ReportDrillRow(
                      title: 'Tiền nhập hàng',
                      icon: Icons.add_rounded,
                      subtitle: '${SboxFmt.number(_num(d['receiptCount']))} ${tr('phiếu')}',
                      trailing: SboxFmt.money(_num(d['receiptAmount'])),
                      onTap: () => receiptSheet('Phiếu nhập hàng', receipts),
                    ),
                    ReportDrillRow(
                      title: 'Trả hàng nhà cung cấp',
                      icon: Icons.remove_rounded,
                      subtitle: '${SboxFmt.number(_num(d['returnCount']))} ${tr('phiếu')}',
                      trailing: '−${SboxFmt.money(_num(d['returnAmount']))}',
                      trailingColor: SboxColors.dangerText,
                    ),
                  ],
                  note: 'Nhập thuần = Tiền nhập hàng − Trả hàng nhà cung cấp.',
                  total: 'Nhập thuần ${SboxFmt.money(_num(d['netAmount']))}',
                  showCount: false,
                )),
          ]),
          _gap,
          _rank('Theo nhà cung cấp', [
            for (final s in suppliers)
              SboxSlice('${s['supplierName'] ?? ''}', _num(s['amount']), caption: '${tr('Còn nợ')} ${SboxFmt.compact(_num(s['balanceDue']))}'),
          ], color: SboxColors.violet, onTapIndex: (i) {
            final s = suppliers[i];
            receiptSheet('${s['supplierName'] ?? ''}', receipts.where((r) => '${r['supplierId']}' == '${s['supplierId']}').toList(),
                note: '${SboxFmt.number(_num(s['receiptCount']))} ${tr('phiếu')} · ${tr('đã trả')} ${SboxFmt.money(_num(s['paid']))} · '
                    '${tr('còn nợ')} ${SboxFmt.money(_num(s['balanceDue']))}');
          }),
          _gap,
          _rank('Hàng nhập nhiều nhất', [
            for (final p in _list(d['topProducts']))
              SboxSlice('${p['productName'] ?? ''}', _num(p['amount']), caption: '${SboxFmt.qty(_num(p['qty']))} ${p['unitName'] ?? ''}'),
          ]),
        ];
      case BossReportType.stock:
        final lots = _data.length > 1 ? _data[1] ?? const {} : const <String, dynamic>{};
        final reorder = _data.length > 2 ? _data[2] ?? const {} : const <String, dynamic>{};
        final health = _data.length > 3 ? _data[3] ?? const {} : const <String, dynamic>{};
        final healthNote = 'Tính trên 30 ngày gần nhất. Bán chạy: còn đủ bán dưới ${SboxFmt.number(_num(health['hotDays']))} ngày '
            'hoặc đã hết / dưới tối thiểu. Bán chậm: tồn đủ bán ≥ ${SboxFmt.number(_num(health['idleDays']))} ngày. '
            'Không bán được: còn tồn nhưng không bán trong kỳ.';
        return [
          _pair(
            _metric('Giá trị tồn kho', _num(d['inventoryValue']),
                onTap: () => showBossStockProductsDrill(context,
                    title: 'Giá trị tồn kho',
                    sortValue: true,
                    note: 'Giá trị tồn = Σ tồn × giá vốn từng mặt hàng (hàng có biến thể tính theo từng biến thể). '
                        'Tồn âm kéo tổng xuống.')),
            _metric('Mặt hàng', _num(d['totalSkus']),
                money: false,
                tone: SboxTone.neutral,
                onTap: () => showBossStockProductsDrill(context,
                    title: 'Mặt hàng theo dõi tồn', note: 'Hàng hóa, nguyên vật liệu, topping và combo có quản lý tồn.')),
          ),
          _gap,
          _pair(
            _metric('Đã hết', _num(d['outOfStock']),
                money: false,
                tone: SboxTone.danger,
                onTap: () => showBossStockProductsDrill(context, title: 'Hàng đã hết', filter: 'OutOfStock')),
            _metric('Dưới tồn tối thiểu', _num(d['belowMin']),
                money: false,
                tone: SboxTone.warning,
                onTap: () => showBossStockProductsDrill(context, title: 'Dưới tồn tối thiểu', filter: 'BelowMin')),
          ),
          if (lots.isNotEmpty) ...[
            _gap,
            SboxCard(
              title: 'Hạn sử dụng',
              child: Column(children: [
                _kv('Lô đã hết hạn', '${SboxFmt.number(_num(lots['expiredLotCount']))} · ${SboxFmt.money(_num(lots['expiredValue']))}',
                    SboxColors.dangerText,
                    onTap: () => showBossStockLotsDrill(context, title: 'Lô đã hết hạn', filter: 'expired')),
                _kv('Lô sắp hết hạn',
                    '${SboxFmt.number(_num(lots['expiringSoonLotCount']))} · ${SboxFmt.money(_num(lots['expiringSoonValue']))}',
                    SboxColors.warningText,
                    onTap: () => showBossStockLotsDrill(context, title: 'Lô sắp hết hạn', filter: 'expiring')),
              ]),
            ),
          ],
          if (health.isNotEmpty) ...[
            _gap,
            SboxCard(
              title: 'Tốc độ bán',
              child: Column(children: [
                _kv('Bán chạy', '${SboxFmt.number(_num(health['hotCount']))} · ${SboxFmt.money(_num(health['hotValue']))}', SboxColors.successText,
                    onTap: () => showBossStockHealthDrill(context, title: 'Bán chạy', mode: 'hot', note: healthNote)),
                _kv('Bán chậm', '${SboxFmt.number(_num(health['slowCount']))} · ${SboxFmt.money(_num(health['slowValue']))}', SboxColors.warningText,
                    onTap: () => showBossStockHealthDrill(context, title: 'Bán chậm', mode: 'slow', note: healthNote)),
                _kv('Không bán được (${SboxFmt.number(_num(health['idleDays']))} ${tr('ngày')})',
                    '${SboxFmt.number(_num(health['deadCount']))} · ${SboxFmt.money(_num(health['deadValue']))}', SboxColors.dangerText,
                    onTap: () => showBossStockHealthDrill(context, title: 'Không bán được', mode: 'dead', note: healthNote)),
              ]),
            ),
          ],
          if (reorder.isNotEmpty) ...[
            _gap,
            SboxCard(
              title: 'Cần nhập thêm',
              subtitle: tr('${SboxFmt.number(_num(reorder['count']))} mặt hàng · dự tính ${SboxFmt.money(_num(reorder['totalAmount']))}'),
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final i in _list(reorder['items']).take(30))
                  ListTile(
                    dense: true,
                    title: Text('${i['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${tr('Tồn')} ${SboxFmt.qty(_num(i['onHand']))} / ${tr('tối thiểu')} ${SboxFmt.qty(_num(i['minStock']))}'
                        '${(i['supplierName'] ?? '').toString().isEmpty ? '' : ' · ${i['supplierName']}'}'),
                    trailing: Text('+${SboxFmt.qty(_num(i['suggestQty']))} ${i['unitName'] ?? ''}',
                        style: SboxType.bodyStrong(i['outOfStock'] == true ? SboxColors.dangerText : SboxColors.text)),
                  ),
                if (_list(reorder['items']).length > 30)
                  ListTile(
                    dense: true,
                    title: Text(tr('Xem đủ ${SboxFmt.number(_num(reorder['count']))} mặt hàng'),
                        style: SboxType.bodyStrong(SboxColors.brand700)),
                    trailing: const Icon(Icons.chevron_right_rounded, color: SboxColors.slate400),
                    onTap: () => _sheet(
                      'Cần nhập thêm',
                      [
                        for (final i in _list(reorder['items']))
                          ReportDrillRow(
                            title: '${i['name'] ?? ''}',
                            icon: Icons.add_shopping_cart_rounded,
                            subtitle: '${tr('Tồn')} ${SboxFmt.qty(_num(i['onHand']))} / ${tr('tối thiểu')} ${SboxFmt.qty(_num(i['minStock']))}'
                                ' · +${SboxFmt.qty(_num(i['suggestQty']))} ${i['unitName'] ?? ''}',
                            trailing: SboxFmt.money(_num(i['amount'])),
                          ),
                      ],
                      period: false,
                      note: 'Hàng có tồn ≤ tồn tối thiểu. Gợi ý nhập = tồn tối đa − tồn (chưa đặt tối đa → 2 × tối thiểu − tồn); '
                          'tiền dự tính = gợi ý nhập × giá vốn.',
                      total: 'Dự tính ${SboxFmt.money(_num(reorder['totalAmount']))}',
                    ),
                  ),
              ]),
            ),
          ],
        ];
      case BossReportType.debt:
        final sup = _data.length > 1 ? _data[1] ?? const {} : const <String, dynamic>{};
        const buckets = [
          ('0–30 ngày', 'sumDebt0To30', 'debt0To30'),
          ('31–60 ngày', 'sumDebt31To60', 'debt31To60'),
          ('61–90 ngày', 'sumDebt61To90', 'debt61To90'),
          ('Trên 90 ngày', 'sumDebtOver90', 'debtOver90'),
        ];
        const bucketColors = <Color?>[null, SboxColors.warningText, SboxColors.warningText, SboxColors.dangerText];
        Widget aging(Map<String, dynamic> m, String who) => Column(children: [
              for (var i = 0; i < buckets.length; i++)
                _kv(buckets[i].$1, SboxFmt.money(_num(m[buckets[i].$2])), bucketColors[i],
                    onTap: () => _debtSheet('$who nợ ${buckets[i].$1}', m, buckets[i].$3, buckets[i].$2,
                        note: 'Tuổi nợ tính từ ngày của đơn / phiếu còn nợ. Nợ không gắn đơn (nợ đầu kỳ, điều chỉnh) '
                            'không có tuổi nên không nằm trong nhóm nào.')),
            ]);
        return [
          _pair(
            _metric('Khách đang nợ', _num(d['sumDebt']),
                tone: SboxTone.warning,
                delta: '${SboxFmt.number(_num(d['totalCustomers']))} ${tr('khách')}',
                onTap: () => _debtSheet('Khách đang nợ', d, 'currentDebt', 'sumDebt')),
            _metric('Nợ nhà cung cấp', _num(sup['sumDebt']),
                tone: SboxTone.danger,
                delta: '${SboxFmt.number(_num(sup['totalSuppliers']))} ${tr('NCC')}',
                onTap: sup.isEmpty ? null : () => _debtSheet('Nợ nhà cung cấp', sup, 'currentDebt', 'sumDebt')),
          ),
          _gap,
          SboxCard(title: 'Tuổi nợ khách', child: aging(d, 'Khách')),
          _gap,
          _debtList('Khách nợ nhiều nhất', _list(d['items']), isCustomer: true),
          if (sup.isNotEmpty) ...[
            _gap,
            SboxCard(
              title: 'Tuổi nợ nhà cung cấp',
              subtitle: _num(sup['sumOpenReceiptDebt']) > _num(sup['sumDebt'])
                  ? '${tr('Tính theo phiếu nhập còn nợ. Đã có')} ${SboxFmt.money(_num(sup['sumOpenReceiptDebt']) - _num(sup['sumDebt']))} ${tr('trả hàng, trả nợ chưa gắn phiếu')}'
                  : null,
              child: aging(sup, 'NCC'),
            ),
            _gap,
            _debtList('Nợ nhà cung cấp nhiều nhất', _list(sup['items']), isCustomer: false),
          ],
        ];
    }
  }

  /// Danh sách nợ: bấm một dòng xem nợ từ những chứng từ nào, sổ đối chiếu.
  Widget _debtList(String title, List<Map<String, dynamic>> rows, {required bool isCustomer}) => SboxCard(
        title: title,
        subtitle: rows.isEmpty ? null : 'Bấm để xem chứng từ còn nợ',
        padding: EdgeInsets.zero,
        child: Column(children: [
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(SboxSpace.lg),
              child: Text(tr('Không có công nợ'), style: SboxType.bodyStyle(SboxColors.textMuted)),
            ),
          for (var i = 0; i < rows.length && i < 30; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              dense: true,
              title: Text('${rows[i]['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis, style: SboxType.bodyStrong()),
              subtitle: Text(
                '${rows[i]['phone'] ?? ''}${_num(rows[i]['debtOver90']) > 0 ? ' · ${tr('quá 90 ngày')} ${SboxFmt.compact(_num(rows[i]['debtOver90']))}' : ''}',
              ),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(SboxFmt.money(_num(rows[i]['currentDebt'])), style: SboxType.moneyStyle(c: SboxColors.dangerText)),
                const Icon(Icons.chevron_right_rounded, color: SboxColors.slate400),
              ]),
              onTap: () => showPosPartyDebtDetail(
                context,
                isCustomer: isCustomer,
                id: '${rows[i]['id']}',
                name: '${rows[i]['name'] ?? ''}',
                phone: rows[i]['phone']?.toString(),
                debt: _num(rows[i]['currentDebt']),
              ),
            ),
          ],
        ]),
      );

  /// Bấm một dòng Lãi lỗ → danh sách nguồn (null = dòng chưa có danh sách chi tiết).
  VoidCallback? _pnlLineTap(Map<String, dynamic> d, String code) => switch (code) {
        '10' => () => _orders('Doanh thu thuần',
            note: 'Doanh thu thuần = Σ tiền hàng các đơn hoàn thành trong kỳ (đã trừ giảm giá, hàng khách trả; chưa VAT) '
                '= ${SboxFmt.money(_num(d['revenue']))}.'),
        '11' => () => _profitByProduct('Giá vốn theo món',
            field: 'cogs',
            note: 'Giá vốn hàng bán = giá vốn lúc bán ${SboxFmt.money(_num(d['saleCost']))} − giá vốn hàng khách trả '
                '${SboxFmt.money(_num(d['returnedCost']))} = ${SboxFmt.money(_num(d['cogs']))}.'),
        '20' => () => _profitByProduct('Lợi nhuận gộp theo món',
            field: 'profit',
            note: 'Lợi nhuận gộp = Doanh thu thuần ${SboxFmt.money(_num(d['revenue']))} − Giá vốn ${SboxFmt.money(_num(d['cogs']))} '
                '= ${SboxFmt.money(_num(d['grossProfit']))}. Biên gộp ${SboxFmt.pct(_num(d['marginPct']))}.'),
        '21' => () => _cash('Chi phí hoạt động', 'pnl-cash', const {'kind': 'expense'},
            note: 'Phiếu chi sổ quỹ trừ nhập hàng, trả hàng khách, hoàn cọc, ứng lương, mua tài sản. '
                'Phiếu «Thu hoàn ứng công tác» ghi số âm (giảm chi phí).'
                '${_list(d['expenseByCategory']).any((c) => '${c['category']}' == 'Lương — phần đã ứng trước') ? ' Dòng «Lương — phần đã ứng trước» không có phiếu riêng nên tổng dưới đây nhỏ hơn số trên báo cáo.' : ''}'),
        '22' => () => _cash('Thu nhập khác', 'pnl-cash', const {'kind': 'otherIncome'},
            note: 'Phiếu thu sổ quỹ trừ tiền bán hàng, thu nợ khách, cọc đặt chỗ, thu trả hàng NCC, thu hộ COD, hoàn ứng công tác, mất cọc.'),
        '26' => () => _cash('Cọc khách bỏ', 'pnl-cash', const {'kind': 'forfeited'}),
        _ => null,
      };

  Widget _kv(String k, String v, Color? c, {VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: SboxSpace.xs),
          child: Row(children: [
            Expanded(child: Text(tr(k), style: SboxType.bodyStyle(SboxColors.textSecondary))),
            Text(v, style: SboxType.bodyStrong(c ?? SboxColors.text)),
            if (onTap != null) const Icon(Icons.chevron_right_rounded, size: 18, color: SboxColors.slate400),
          ]),
        ),
      );
}
