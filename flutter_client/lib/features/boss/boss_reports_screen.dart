import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../screens/pos/pos_risk_report_screen.dart';
import '../../services/api_service.dart';
import '../../services/branch_session.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/branch_switcher.dart';
import '../../widgets/sbox/sbox_basics.dart';
import '../../widgets/sbox/sbox_charts.dart';
import 'boss_end_of_day_screen.dart';

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
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: tone.bg, borderRadius: SboxRadius.mdAll),
            child: Icon(icon, color: tone.fg),
          ),
          title: Text(tr(title), style: SboxType.bodyStrong()),
          subtitle: Text(tr(sub)),
          trailing: const Icon(Icons.chevron_right_rounded, color: SboxColors.slate400),
          onTap: onTap,
        );
    return ListView(padding: const EdgeInsets.all(SboxSpace.lg), children: [
      SboxCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          tile(Icons.receipt_long_rounded, 'Cuối ngày', 'Tiền két, thực thu, hủy đơn, món bán chạy theo ngày', () {
            open(Scaffold(
              backgroundColor: SboxColors.page,
              appBar: AppBar(
                backgroundColor: SboxColors.brand700,
                foregroundColor: SboxColors.white,
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
    ]);
  }
}

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
  const BossReportDetailScreen({super.key, required this.type});

  final BossReportType type;

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
    if (widget.type == BossReportType.cashbook || widget.type == BossReportType.pnl) {
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
        backgroundColor: SboxColors.brand700,
        foregroundColor: SboxColors.white,
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
              ? SboxEmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Không tải được báo cáo',
                  message: _error,
                  action: SboxButton(label: 'Thử lại', onPressed: _load),
                )
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

  Widget _metric(String label, num? v, {SboxTone tone = SboxTone.brand, String? delta, bool? up, bool money = true}) =>
      SboxMetricCard(
        label: label,
        value: money ? SboxFmt.compact(v) : SboxFmt.number(v),
        tone: tone,
        delta: delta,
        deltaUp: up,
      );

  Widget _lines(String title, List<(String, num?, Color?)> rows) => SboxCard(
        title: title,
        child: Column(children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: SboxSpace.xs),
              child: Row(children: [
                Expanded(child: Text(tr(r.$1), style: SboxType.bodyStyle(SboxColors.textSecondary))),
                Text(SboxFmt.money(r.$2), style: SboxType.moneyStyle(c: r.$3 ?? SboxColors.text)),
              ]),
            ),
        ]),
      );

  Widget _rank(String title, List<SboxSlice> items, {int max = 10, Color color = SboxColors.brand500, String? subtitle}) =>
      SboxCard(
        title: title,
        subtitle: subtitle,
        child: SboxRankList(items: items, maxItems: max, color: color),
      );

  List<Widget> _body() {
    final d = _data.first!;
    switch (widget.type) {
      case BossReportType.business:
        final cur = _map(d['current']);
        final prev = _map(d['previous']);
        final ch = _map(d['changePct']);
        final yoy = _map(d['changePctYoy']);
        return [
          _pair(
            _metric('Doanh thu', _num(cur['revenue']), delta: '${_signedPct(ch['revenue'])} ${tr('kỳ trước')}', up: _num(ch['revenue']) >= 0),
            _metric('Lợi nhuận gộp', _num(cur['profit']),
                tone: SboxTone.success, delta: '${_signedPct(ch['profit'])} ${tr('kỳ trước')}', up: _num(ch['profit']) >= 0),
          ),
          _gap,
          _pair(
            _metric('Số đơn', _num(cur['orderCount']), money: false, tone: SboxTone.neutral,
                delta: '${_signedPct(ch['orders'])} ${tr('kỳ trước')}', up: _num(ch['orders']) >= 0),
            _metric('TB / đơn', _num(cur['avgOrderValue']), tone: SboxTone.neutral,
                delta: '${tr('Kỳ trước')} ${SboxFmt.compact(_num(prev['avgOrderValue']))}'),
          ),
          _gap,
          _lines('Chi tiết', [
            ('Doanh thu (gồm VAT)', _num(cur['revenueInclVat']), null),
            ('Giảm giá', _num(cur['discount']), SboxColors.warningText),
            ('Hàng khách trả', _num(cur['refund']), SboxColors.dangerText),
            ('Giá vốn', _num(cur['cogs']), null),
            ('Lợi nhuận gộp', _num(cur['profit']), SboxColors.successText),
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
          _rank('Nhóm hàng bán chạy', [
            for (final c in _list(d['topCategories'])) SboxSlice('${c['categoryName'] ?? ''}', _num(c['revenue'])),
          ], color: SboxColors.violet),
        ];
      case BossReportType.pnl:
        final net = _num(d['netProfit']);
        return [
          _pair(
            _metric('Doanh thu thuần', _num(d['revenue'])),
            _metric('Lãi ròng', net,
                tone: net >= 0 ? SboxTone.success : SboxTone.danger,
                delta: '${tr('Biên')} ${SboxFmt.pct(_num(d['netMarginPct']))}', up: net >= 0),
          ),
          _gap,
          SboxCard(
            title: 'Báo cáo lãi lỗ',
            child: Column(children: [
              for (final l in _list(d['lines']))
                Padding(
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
                  ]),
                ),
            ]),
          ),
          _gap,
          _rank('Chi phí theo danh mục', [
            for (final c in _list(d['expenseByCategory'])) SboxSlice(tr('${c['category'] ?? ''}'), _num(c['amount'])),
          ], color: SboxColors.danger),
        ];
      case BossReportType.profit:
        final items = _list(d['items']);
        final losses = items.where((i) => _num(i['profit']) < 0).toList()
          ..sort((a, b) => _num(a['profit']).compareTo(_num(b['profit'])));
        return [
          _pair(
            _metric('Lợi nhuận gộp', _num(d['totalProfit']), tone: SboxTone.success,
                delta: '${tr('Biên')} ${SboxFmt.pct(_num(d['marginPct']))}'),
            _metric('Doanh thu', _num(d['totalRevenue']), delta: '${SboxFmt.number(_num(d['skuCount']))} ${tr('món')}'),
          ),
          _gap,
          _rank('Lãi nhiều nhất', [
            for (final i in items)
              SboxSlice('${i['productName'] ?? ''}', _num(i['profit']),
                  caption: '${tr('Bán')} ${SboxFmt.qty(_num(i['qty']))} · ${tr('biên')} ${SboxFmt.pct(_num(i['marginPct']))}'),
          ], color: SboxColors.success),
          if (losses.isNotEmpty) ...[
            _gap,
            SboxCard(
              title: 'Đang lỗ (giá bán thấp hơn giá vốn)',
              padding: EdgeInsets.zero,
              child: Column(children: [
                for (final i in losses.take(15))
                  ListTile(
                    dense: true,
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
        return [
          _pair(_metric('Thu', _num(d['income']), tone: SboxTone.success), _metric('Chi', _num(d['expense']), tone: SboxTone.danger)),
          _gap,
          if (d.containsKey('openingBalance'))
            _lines('Tồn quỹ', [
              ('Tồn đầu kỳ', _num(d['openingBalance']), null),
              ('Thu trong kỳ', _num(d['income']), SboxColors.successText),
              ('Chi trong kỳ', _num(d['expense']), SboxColors.dangerText),
              ('Tồn cuối kỳ', _num(d['closingBalance']), SboxColors.brand700),
            ]),
          if (d.containsKey('balanceByMethod')) ...[
            _gap,
            _lines('Tồn cuối theo quỹ', [
              for (final b in _list(d['balanceByMethod'])) (tr('${b['paymentMethod'] ?? ''}'), _num(b['closing']), null),
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
        return [
          _pair(
            _metric('Tổng chi phí', _num(d['total']), tone: SboxTone.danger),
            _metric('Số phiếu chi', _num(d['count']), money: false, tone: SboxTone.neutral),
          ),
          _gap,
          _rank('Theo danh mục', [
            for (final c in _list(d['byCategory']))
              SboxSlice(tr('${c['category'] ?? ''}'), _num(c['total']), caption: '${SboxFmt.number(_num(c['count']))} ${tr('phiếu')}'),
          ], color: SboxColors.danger),
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
        return [
          _pair(
            _metric('Doanh số', _num(d['totalRevenue'])),
            _metric('Nhân viên bán', _num(d['staffCount']), money: false, tone: SboxTone.neutral,
                delta: '${SboxFmt.number(_num(d['orderCount']))} ${tr('đơn')}'),
          ),
          _gap,
          _rank('Doanh số theo nhân viên', [
            for (final s in _list(d['staff']))
              SboxSlice('${s['displayName'] ?? s['soldBy'] ?? ''}', _num(s['revenue']),
                  caption: '${SboxFmt.number(_num(s['orderCount']))} ${tr('đơn')} · ${tr('TB')} ${SboxFmt.compact(_num(s['avgOrder']))}'),
          ], max: 30),
        ];
      case BossReportType.purchases:
        return [
          _pair(
            _metric('Tiền nhập hàng', _num(d['receiptAmount']), delta: '${SboxFmt.number(_num(d['receiptCount']))} ${tr('phiếu')}'),
            _metric('Còn nợ NCC', _num(d['balanceDue']), tone: SboxTone.warning),
          ),
          _gap,
          _lines('Chi tiết', [
            ('Đã trả trong kỳ', _num(d['paidInPeriod']), null),
            ('Trả hàng nhà cung cấp', _num(d['returnAmount']), null),
            ('Nhập thuần', _num(d['netAmount']), SboxColors.brand700),
          ]),
          _gap,
          _rank('Theo nhà cung cấp', [
            for (final s in _list(d['bySupplier']))
              SboxSlice('${s['supplierName'] ?? ''}', _num(s['amount']), caption: '${tr('Còn nợ')} ${SboxFmt.compact(_num(s['balanceDue']))}'),
          ], color: SboxColors.violet),
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
        return [
          _pair(
            _metric('Giá trị tồn kho', _num(d['inventoryValue'])),
            _metric('Mặt hàng', _num(d['totalSkus']), money: false, tone: SboxTone.neutral),
          ),
          _gap,
          _pair(
            _metric('Đã hết', _num(d['outOfStock']), money: false, tone: SboxTone.danger),
            _metric('Dưới tồn tối thiểu', _num(d['belowMin']), money: false, tone: SboxTone.warning),
          ),
          if (lots.isNotEmpty) ...[
            _gap,
            SboxCard(
              title: 'Hạn sử dụng',
              child: Column(children: [
                _kv('Lô đã hết hạn', '${SboxFmt.number(_num(lots['expiredLotCount']))} · ${SboxFmt.money(_num(lots['expiredValue']))}',
                    SboxColors.dangerText),
                _kv('Lô sắp hết hạn',
                    '${SboxFmt.number(_num(lots['expiringSoonLotCount']))} · ${SboxFmt.money(_num(lots['expiringSoonValue']))}',
                    SboxColors.warningText),
              ]),
            ),
          ],
          if (health.isNotEmpty) ...[
            _gap,
            SboxCard(
              title: 'Tốc độ bán',
              child: Column(children: [
                _kv('Bán chạy', '${SboxFmt.number(_num(health['hotCount']))} · ${SboxFmt.money(_num(health['hotValue']))}', SboxColors.successText),
                _kv('Bán chậm', '${SboxFmt.number(_num(health['slowCount']))} · ${SboxFmt.money(_num(health['slowValue']))}', SboxColors.warningText),
                _kv('Không bán được (${SboxFmt.number(_num(health['idleDays']))} ${tr('ngày')})',
                    '${SboxFmt.number(_num(health['deadCount']))} · ${SboxFmt.money(_num(health['deadValue']))}', SboxColors.dangerText),
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
              ]),
            ),
          ],
        ];
      case BossReportType.debt:
        final sup = _data.length > 1 ? _data[1] ?? const {} : const <String, dynamic>{};
        Widget aging(Map<String, dynamic> m) => Column(children: [
              _kv('0–30 ngày', SboxFmt.money(_num(m['sumDebt0To30'])), null),
              _kv('31–60 ngày', SboxFmt.money(_num(m['sumDebt31To60'])), SboxColors.warningText),
              _kv('61–90 ngày', SboxFmt.money(_num(m['sumDebt61To90'])), SboxColors.warningText),
              _kv('Trên 90 ngày', SboxFmt.money(_num(m['sumDebtOver90'])), SboxColors.dangerText),
            ]);
        return [
          _pair(
            _metric('Khách đang nợ', _num(d['sumDebt']), tone: SboxTone.warning,
                delta: '${SboxFmt.number(_num(d['totalCustomers']))} ${tr('khách')}'),
            _metric('Nợ nhà cung cấp', _num(sup['sumDebt']), tone: SboxTone.danger,
                delta: '${SboxFmt.number(_num(sup['totalSuppliers']))} ${tr('NCC')}'),
          ),
          _gap,
          SboxCard(title: 'Tuổi nợ khách', child: aging(d)),
          _gap,
          _rank('Khách nợ nhiều nhất', [
            for (final c in _list(d['items']))
              SboxSlice('${c['name'] ?? ''}', _num(c['currentDebt']),
                  caption: '${c['phone'] ?? ''}${_num(c['debtOver90']) > 0 ? ' · ${tr('quá 90 ngày')} ${SboxFmt.compact(_num(c['debtOver90']))}' : ''}'),
          ], color: SboxColors.warning),
          if (sup.isNotEmpty) ...[
            _gap,
            SboxCard(title: 'Tuổi nợ nhà cung cấp', child: aging(sup)),
            _gap,
            _rank('Nợ nhà cung cấp nhiều nhất', [
              for (final s in _list(sup['items'])) SboxSlice('${s['name'] ?? ''}', _num(s['currentDebt']), caption: '${s['phone'] ?? ''}'),
            ], color: SboxColors.danger),
          ],
        ];
    }
  }

  Widget _kv(String k, String v, Color? c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: SboxSpace.xs),
        child: Row(children: [
          Expanded(child: Text(tr(k), style: SboxType.bodyStyle(SboxColors.textSecondary))),
          Text(v, style: SboxType.bodyStrong(c ?? SboxColors.text)),
        ]),
      );
}
