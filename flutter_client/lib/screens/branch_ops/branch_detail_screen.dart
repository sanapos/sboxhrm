import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../../widgets/reports/report_drill_sheet.dart';
import '../../widgets/sbox/sbox_basics.dart' show SboxTone;
import '../../widgets/sbox/sbox_charts.dart';
import '../../widgets/sbox/sbox_report.dart';
import '../pos_sale_order_editor_screen.dart';
import '../staff/staff_nav.dart';
import 'branch_ops_ui.dart';
import 'branch_stock_view.dart';
import 'stock_transfer_screen.dart';

/// Chi tiết 1 chi nhánh: Tổng quan (KPI so kỳ trước, biểu đồ, top) · Kho · Nhân sự · Chuyển kho.
class BranchDetailScreen extends StatefulWidget {
  const BranchDetailScreen({super.key, required this.branchId, this.branchName = '', this.initialPeriod});

  final String branchId;
  final String branchName;
  final BranchPeriod? initialPeriod;

  @override
  State<BranchDetailScreen> createState() => _BranchDetailScreenState();
}

class _BranchDetailScreenState extends State<BranchDetailScreen> {
  late BranchPeriod _period = widget.initialPeriod ?? BranchPeriod.thisMonth();
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await ApiService().getBranchOverview(widget.branchId, _period.from, _period.to);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r['isSuccess'] == true && r['data'] is Map) {
        _data = Map<String, dynamic>.from(r['data'] as Map);
      } else {
        _error = r['message']?.toString() ?? 'Không tải được dữ liệu chi nhánh';
      }
    });
  }

  List<Map<String, dynamic>> _list(String key) =>
      [for (final x in (_data[key] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];

  Map<String, dynamic> _map(String key) => Map<String, dynamic>.from((_data[key] as Map?) ?? const {});

  @override
  Widget build(BuildContext context) {
    final branch = _map('branch');
    final name = (branch['name'] ?? widget.branchName).toString();
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: SboxColors.slate50,
        appBar: AppBar(
          title: Row(children: [
            Flexible(child: Text(tr(name.isEmpty ? 'Chi nhánh' : name), overflow: TextOverflow.ellipsis)),
            if (branch['isHeadquarter'] == true) ...[
              SizedBox(width: 8),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: SboxColors.brand50, borderRadius: BorderRadius.circular(99)),
                child: Text(tr('Trụ sở'),
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: SboxColors.appBarFg(SboxColors.brand700))),
              ),
            ],
          ]),
          bottom: sboxBarTabs(TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: tr('Tổng quan')),
              Tab(text: tr('Kho')),
              Tab(text: tr('Nhân sự')),
              Tab(text: tr('Chuyển kho')),
            ],
          )),
        ),
        body: TabBarView(children: [
          _overviewTab(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: BranchStockView(branchId: widget.branchId, embedded: true),
          ),
          _staffTab(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: StockTransferScreen(branchId: widget.branchId, embedded: true),
          ),
        ]),
      ),
    );
  }

  // ─────────────── Tổng quan ───────────────

  Widget _overviewTab() {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          BranchPeriodBar(
            value: _period,
            onChanged: (p) {
              setState(() => _period = p);
              _load();
            },
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            BranchBox(child: Text(tr(_error!)))
          else ...[
            _kpis(),
            const SizedBox(height: 12),
            _charts(),
            const SizedBox(height: 12),
            _lowStock(),
          ],
        ],
      ),
    );
  }

  Widget _kpis() {
    final c = _map('current');
    final p = _map('previous');
    SboxKpi k(String label, String key, IconData icon, SboxTone tone,
            {bool higherIsBetter = true, String? note, VoidCallback? onTap}) =>
        SboxKpi(
          label: label,
          value: key == 'orders' || key == 'employees' ? bQty(c[key]) : bMoneyShort(c[key]),
          icon: icon,
          tone: tone,
          current: bNum(c[key]),
          previous: p.isEmpty ? null : bNum(p[key]),
          higherIsBetter: higherIsBetter,
          compareLabel: 'kỳ trước',
          note: note,
          onTap: onTap,
        );
    final net = bNum(c['netProfit']);
    String prevOf(String key, {bool qty = false}) =>
        p.isEmpty ? '' : ' Kỳ trước (cùng số ngày, ngay trước kỳ này): ${qty ? bQty(p[key]) : bMoney(bNum(p[key]))}.';
    return SboxKpiStrip(maxColumns: 6, items: [
      k('Doanh thu', 'revenue', Icons.payments_outlined, SboxTone.brand,
          onTap: () => _ordersDrill('Doanh thu',
              note: 'Doanh thu = Σ tiền hàng các đơn hoàn tất của chi nhánh (đã trừ giảm giá, hàng khách trả; chưa VAT).'
                  '${prevOf('revenue')}')),
      k('Số đơn', 'orders', Icons.receipt_outlined, SboxTone.neutral,
          onTap: () => _ordersDrill('Số đơn', note: 'Đơn hoàn tất của chi nhánh trong kỳ.${prevOf('orders', qty: true)}')),
      k('Lãi gộp', 'grossProfit', Icons.trending_up_rounded, SboxTone.success,
          onTap: () => _ordersDrill('Lãi gộp',
              profit: true,
              note: 'Lãi gộp = Doanh thu ${bMoney(bNum(c['revenue']))} − Giá vốn ${bMoney(bNum(c['cogs']))} = '
                  '${bMoney(bNum(c['grossProfit']))} (biên ${bNum(c['grossMarginPct']).toStringAsFixed(1).replaceAll('.', ',')}%). '
                  'Mỗi dòng: tiền đơn − giá vốn đơn.${prevOf('grossProfit')}')),
      k('Chi phí', 'expenses', Icons.receipt_long_outlined, SboxTone.warning,
          higherIsBetter: false,
          note: 'Lương ${bMoneyShort(c['payroll'])}',
          onTap: () => _cashDrill('Chi phí', 'expense',
              note: 'Phiếu chi không thuộc bán / nhập / trả hàng, không gồm chi lương, ứng lương, mua tài sản. '
                  'Phiếu thu hoàn ứng công tác ghi số âm. Lương (${bMoney(bNum(c['payroll']))}) tính riêng — xem trong «Lãi ròng».'
                  '${prevOf('expenses')}')),
      k('Lãi ròng', 'netProfit', Icons.savings_outlined, net >= 0 ? SboxTone.success : SboxTone.danger,
          onTap: () => _netDrill(c, prevOf('netProfit'))),
      SboxKpi(
        label: 'Giá trị tồn kho',
        value: bMoneyShort(c['stockValue']),
        icon: Icons.inventory_2_outlined,
        tone: SboxTone.violet,
        note: '${bQty(_data['outOfStock'])} mặt hàng hết',
        onTap: () => _stockDrill(false),
      ),
    ]);
  }

  // ─────────────── Chi tiết số liệu («số này từ đâu ra») ───────────────

  Map<String, String> get _q => {
        'from': '${_period.from.year}-${_period.from.month.toString().padLeft(2, '0')}-${_period.from.day.toString().padLeft(2, '0')}',
        'to': '${_period.to.year}-${_period.to.month.toString().padLeft(2, '0')}-${_period.to.day.toString().padLeft(2, '0')}',
      };

  /// Tải trước rồi mở sheet — để dòng tổng / ghi chú cắt bớt lấy đúng số API.
  Future<Map<String, dynamic>?> _fetch(String path, [Map<String, String> query = const {}]) async {
    final nav = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final r = await ApiService().getReportJson('/api/branch-ops/$path', query: query);
    nav.pop();
    if (r['isSuccess'] == true && r['data'] is Map) return Map<String, dynamic>.from(r['data'] as Map);
    messenger?.showSnackBar(SnackBar(content: Text(tr(r['message']?.toString() ?? 'Không tải được dữ liệu'))));
    return null;
  }

  List<Map<String, dynamic>> _items(Map<String, dynamic> d) =>
      [for (final x in (d['items'] as List? ?? const [])) if (x is Map) Map<String, dynamic>.from(x)];

  String? _cut(Map<String, dynamic> d, int shown, String unit) =>
      d['truncated'] == true ? 'Hiện $shown / ${bQty(d['count'])} $unit mới nhất; tổng tính trên tất cả.' : null;

  static String _when(Object? raw) {
    var t = DateTime.tryParse('${raw ?? ''}');
    if (t == null) return '';
    if (t.isUtc) t = t.toLocal();
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(t.day)}/${two(t.month)} ${two(t.hour)}:${two(t.minute)}';
  }

  Future<void> _ordersDrill(String title, {String? note, bool profit = false}) async {
    final d = await _fetch('drill/orders/${widget.branchId}', _q);
    if (d == null || !mounted) return;
    final canOpen = staffCanOpen(context, 'PosSaleOrders', listen: false);
    final items = _items(d);
    await showReportDrillSheet(
      context,
      title: title,
      subtitle: '${_map('branch')['name'] ?? widget.branchName} · ${_period.rangeText}',
      note: note,
      countLabel: bQty(d['count']),
      total: profit
          ? 'Lãi gộp ${bMoney(bNum(d['grossProfit']))}'
          : 'Tổng ${bMoney(bNum(d['revenue']))} · ${bQty(d['count'])} đơn',
      footer: _cut(d, items.length, 'đơn'),
      emptyText: 'Không có đơn trong kỳ',
      rows: [
        for (final o in items)
          ReportDrillRow(
            title: '${o['orderNo'] ?? ''}',
            icon: Icons.receipt_long_rounded,
            subtitle: [
              _when(o['saleAt']),
              if ('${o['customerName'] ?? ''}'.isNotEmpty) '${o['customerName']}',
              if ('${o['soldBy'] ?? ''}'.isNotEmpty) 'NV: ${o['soldBy']}',
              if (profit) 'tiền ${bMoney(bNum(o['total']))} · giá vốn ${bMoney(bNum(o['cogs']))}',
            ].where((s) => s.isNotEmpty).join(' · '),
            trailing: bMoney(bNum(profit ? o['profit'] : o['total'])),
            trailingColor: profit && bNum(o['profit']) < 0 ? SboxColors.dangerText : null,
            onTap: !canOpen || '${o['id'] ?? ''}'.isEmpty
                ? null
                : () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => PosHubScope.pushed(child: PosSaleOrderEditorScreen(orderId: '${o['id']}')),
                    )),
          ),
      ],
    );
  }

  Future<void> _cashDrill(String title, String kind, {String? note}) async {
    final d = await _fetch('drill/cash/${widget.branchId}', {..._q, 'kind': kind});
    if (d == null || !mounted) return;
    final items = _items(d);
    await showReportDrillSheet(
      context,
      title: title,
      subtitle: '${_map('branch')['name'] ?? widget.branchName} · ${_period.rangeText}',
      note: note,
      countLabel: bQty(d['count']),
      total: 'Tổng ${bMoney(bNum(d['total']))}',
      footer: _cut(d, items.length, 'phiếu'),
      emptyText: 'Không có phiếu trong kỳ',
      rows: [
        for (final x in items)
          ReportDrillRow(
            title: '${x['description'] ?? ''}'.trim().isEmpty ? '${x['transactionCode'] ?? ''}' : '${x['description']}',
            icon: '${x['type']}' == 'Income' ? Icons.south_west_rounded : Icons.north_east_rounded,
            subtitle: [
              '${x['transactionCode'] ?? ''}',
              _when(x['transactionDate']),
              if ('${x['category'] ?? ''}'.isNotEmpty) '${x['category']}',
              if ('${x['contactName'] ?? ''}'.isNotEmpty) '${x['contactName']}',
            ].where((s) => s.isNotEmpty).join(' · '),
            trailing: bMoney(bNum(x['amount'])),
            trailingColor: bNum(x['amount']) < 0 ? SboxColors.successText : null,
          ),
      ],
    );
  }

  Future<void> _payrollDrill() async {
    final d = await _fetch('drill/payroll/${widget.branchId}', _q);
    if (d == null || !mounted) return;
    final items = _items(d);
    await showReportDrillSheet(
      context,
      title: 'Lương',
      subtitle: '${_map('branch')['name'] ?? widget.branchName} · ${_period.rangeText}',
      note: 'Lương gộp các phiếu lương (không hủy) của nhân viên thuộc chi nhánh × phần ngày của tháng nằm trong kỳ.',
      countLabel: bQty(d['count']),
      total: 'Tổng ${bMoney(bNum(d['total']))}',
      footer: _cut(d, items.length, 'phiếu lương'),
      emptyText: 'Không có phiếu lương',
      rows: [
        for (final s in items)
          ReportDrillRow(
            title: '${s['employeeName'] ?? ''}',
            subtitle: 'Tháng ${s['month']}/${s['year']} · lương gộp ${bMoney(bNum(s['grossSalary']))}'
                '${bNum(s['sharePct']) < 100 ? ' × ${bNum(s['sharePct']).toStringAsFixed(1).replaceAll('.', ',')}%' : ''}',
            trailing: bMoney(bNum(s['amount'])),
          ),
      ],
    );
  }

  Future<void> _stockDrill(bool outOfStock) async {
    final d = await _fetch('drill/stock/${widget.branchId}', {'outOfStock': '$outOfStock'});
    if (d == null || !mounted) return;
    final items = _items(d);
    await showReportDrillSheet(
      context,
      title: outOfStock ? 'Mặt hàng hết' : 'Giá trị tồn kho',
      subtitle: '${_map('branch')['name'] ?? widget.branchName}',
      note: outOfStock
          ? 'Hàng hóa có tồn tại chi nhánh ≤ 0.'
          : 'Giá trị tồn = Σ tồn tại chi nhánh (số âm tính 0) × giá vốn, chỉ hàng hóa.',
      countLabel: bQty(d['count']),
      total: outOfStock ? null : 'Tổng ${bMoney(bNum(d['total']))}',
      footer: d['truncated'] == true ? 'Hiện ${items.length} / ${bQty(d['count'])} mặt hàng.' : null,
      rows: [
        for (final s in items)
          ReportDrillRow(
            title: '${s['name'] ?? ''}',
            icon: Icons.inventory_2_outlined,
            subtitle: '${s['productCode'] ?? ''} · tồn ${bQty(s['qty'])} ${s['unitName'] ?? ''} × ${bMoney(bNum(s['costPrice']))}',
            trailing: outOfStock ? bQty(s['qty']) : bMoney(bNum(s['stockValue'])),
            trailingColor: bNum(s['qty']) <= 0 ? SboxColors.dangerText : null,
          ),
      ],
    );
  }

  void _netDrill(Map<String, dynamic> c, String prevNote) {
    ReportDrillRow row(String label, num v, {IconData icon = Icons.add_rounded, VoidCallback? onTap}) => ReportDrillRow(
          title: label,
          icon: v < 0 ? Icons.remove_rounded : icon,
          trailing: bMoney(v),
          trailingColor: v < 0 ? SboxColors.dangerText : null,
          onTap: onTap,
        );
    final shipping = bNum(c['surchargeIncome']) + bNum(c['deliveryFeeIncome']);
    showReportDrillSheet(
      context,
      title: 'Lãi ròng',
      subtitle: '${_map('branch')['name'] ?? widget.branchName} · ${_period.rangeText}',
      note: 'Lãi ròng = lãi gộp + phụ thu, phí GH − cước hãng − khấu hao + cọc khách bỏ + thu khác − chi phí − lương.$prevNote',
      showCount: false,
      total: 'Lãi ròng ${bMoney(bNum(c['netProfit']))}',
      rows: [
        row('Lãi gộp', bNum(c['grossProfit']), onTap: () => _ordersDrill('Lãi gộp', profit: true)),
        if (shipping != 0) row('Phụ thu, phí giao hàng thu khách', shipping),
        if (bNum(c['carrierCost']) != 0) row('Cước hãng vận chuyển', -bNum(c['carrierCost'])),
        if (bNum(c['depreciation']) != 0) row('Khấu hao tài sản', -bNum(c['depreciation'])),
        if (bNum(c['forfeitedDeposits']) != 0) row('Cọc khách bỏ', bNum(c['forfeitedDeposits'])),
        row('Thu khác', bNum(c['otherIncome']), onTap: () => _cashDrill('Thu khác', 'otherIncome')),
        row('Chi phí', -bNum(c['expenses']), onTap: () => _cashDrill('Chi phí', 'expense')),
        row('Lương', -bNum(c['payroll']), onTap: _payrollDrill),
      ],
    );
  }

  Widget _charts() {
    final daily = _list('daily');
    final labels = [for (final d in daily) sboxDayLabel(d['date'])];
    return SboxInsightPanel(bottomGap: 0, charts: [
      if (daily.length > 1)
        SboxChartCard(
          title: 'Doanh thu và lãi gộp theo ngày',
          wide: true,
          child: SboxLineChart(
            valueFormat: (v) => SboxFmt.money(v),
            labels: labels,
            series: [
              SboxSeries(name: 'Doanh thu', values: [for (final d in daily) bNum(d['revenue'])], color: SboxColors.brand500),
              SboxSeries(name: 'Lãi gộp', values: [for (final d in daily) bNum(d['profit'])], color: SboxColors.success),
            ],
          ),
        ),
      SboxChartCard(
        title: 'Top sản phẩm',
        child: SboxRankList(
          maxItems: 8,
          items: [
            for (final t in _list('topProducts'))
              SboxSlice(t['productName']?.toString() ?? '', bNum(t['revenue']), caption: '${bQty(t['qty'])} sp'),
          ],
        ),
      ),
      SboxChartCard(
        title: 'Top nhân viên bán',
        child: SboxRankList(
          maxItems: 8,
          color: SboxColors.violet,
          items: [
            for (final t in _list('topSellers'))
              SboxSlice((t['name'] ?? '').toString().isEmpty ? '—' : t['name'].toString(), bNum(t['revenue']),
                  caption: '${bQty(t['orders'])} đơn'),
          ],
        ),
      ),
    ]);
  }

  Widget _lowStock() {
    final low = _list('lowStock');
    return BranchBox(
      title: 'Hàng sắp hết tại chi nhánh',
      trailing: Text('${low.length}', style: const TextStyle(fontWeight: FontWeight.w800, color: SboxColors.warningText)),
      child: low.isEmpty
          ? Text(tr('Không có mặt hàng dưới mức tồn tối thiểu'), style: const TextStyle(color: SboxColors.slate500))
          : Column(children: [
              for (final l in low)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded, size: 16, color: SboxColors.warning),
                    const SizedBox(width: 8),
                    Expanded(child: Text(l['name']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis)),
                    Text(tr('${bQty(l['qty'])} / tối thiểu ${bQty(l['minStockQty'])}'),
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                  ]),
                ),
            ]),
    );
  }

  // ─────────────── Nhân sự ───────────────

  Widget _staffTab() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final emps = _list('employees');
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
        children: [
          Text(tr('${emps.length} nhân viên đang thuộc chi nhánh'),
              style: const TextStyle(fontWeight: FontWeight.w700, color: SboxColors.slate600)),
          const SizedBox(height: 8),
          if (emps.isEmpty)
            BranchBox(child: Text(tr('Chưa có nhân viên nào gán vào chi nhánh này')))
          else
            for (final e in emps)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: SboxColors.slate200),
                ),
                child: ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: SboxColors.isBoss ? SboxColors.iconBox : SboxColors.brand50,
                    foregroundImage: (e['photoUrl'] ?? '').toString().startsWith('http')
                        ? NetworkImage(e['photoUrl'].toString())
                        : null,
                    child: Text(
                      (e['name'] ?? '?').toString().trim().split(' ').last.characters.take(1).toString().toUpperCase(),
                      style: const TextStyle(color: SboxColors.isBoss ? SboxColors.gold : SboxColors.brand700, fontWeight: FontWeight.w800),
                    ),
                  ),
                  title: Text(e['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(tr([e['position'], e['department']]
                      .where((x) => (x ?? '').toString().isNotEmpty)
                      .join(' · '))),
                ),
              ),
        ],
      ),
    );
  }
}
