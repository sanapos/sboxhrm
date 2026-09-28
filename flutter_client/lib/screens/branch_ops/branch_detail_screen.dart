import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/sbox/sbox_basics.dart' show SboxTone;
import '../../widgets/sbox/sbox_charts.dart';
import '../../widgets/sbox/sbox_report.dart';
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
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: SboxColors.brand50, borderRadius: BorderRadius.circular(99)),
                child: Text(tr('Trụ sở'),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: SboxColors.brand700)),
              ),
            ],
          ]),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: tr('Tổng quan')),
              Tab(text: tr('Kho')),
              Tab(text: tr('Nhân sự')),
              Tab(text: tr('Chuyển kho')),
            ],
          ),
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
    SboxKpi k(String label, String key, IconData icon, SboxTone tone, {bool higherIsBetter = true, String? note}) => SboxKpi(
          label: label,
          value: key == 'orders' || key == 'employees' ? bQty(c[key]) : bMoneyShort(c[key]),
          icon: icon,
          tone: tone,
          current: bNum(c[key]),
          previous: p.isEmpty ? null : bNum(p[key]),
          higherIsBetter: higherIsBetter,
          compareLabel: 'kỳ trước',
          note: note,
        );
    final net = bNum(c['netProfit']);
    return SboxKpiStrip(maxColumns: 6, items: [
      k('Doanh thu', 'revenue', Icons.payments_outlined, SboxTone.brand),
      k('Số đơn', 'orders', Icons.receipt_outlined, SboxTone.neutral),
      k('Lãi gộp', 'grossProfit', Icons.trending_up_rounded, SboxTone.success),
      k('Chi phí', 'expenses', Icons.receipt_long_outlined, SboxTone.warning,
          higherIsBetter: false, note: 'Lương ${bMoneyShort(c['payroll'])}'),
      k('Lãi ròng', 'netProfit', Icons.savings_outlined, net >= 0 ? SboxTone.success : SboxTone.danger),
      SboxKpi(
        label: 'Giá trị tồn kho',
        value: bMoneyShort(c['stockValue']),
        icon: Icons.inventory_2_outlined,
        tone: SboxTone.violet,
        note: '${bQty(_data['outOfStock'])} mặt hàng hết',
      ),
    ]);
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
                    backgroundColor: SboxColors.brand50,
                    foregroundImage: (e['photoUrl'] ?? '').toString().startsWith('http')
                        ? NetworkImage(e['photoUrl'].toString())
                        : null,
                    child: Text(
                      (e['name'] ?? '?').toString().trim().split(' ').last.characters.take(1).toString().toUpperCase(),
                      style: const TextStyle(color: SboxColors.brand700, fontWeight: FontWeight.w800),
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
