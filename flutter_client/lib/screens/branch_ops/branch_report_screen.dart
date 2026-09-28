import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/sbox/sbox_basics.dart' show SboxTone;
import '../../widgets/sbox/sbox_charts.dart';
import '../../widgets/sbox/sbox_report.dart';
import '../../widgets/sbox/sbox_table.dart';
import 'branch_detail_screen.dart';
import 'branch_ops_ui.dart';

/// Báo cáo so sánh các chi nhánh: doanh thu, lãi gộp, chi phí, lương, lãi ròng, tồn kho, nhân sự.
class BranchReportScreen extends StatefulWidget {
  const BranchReportScreen({super.key});

  @override
  State<BranchReportScreen> createState() => _BranchReportScreenState();
}

class _BranchReportScreenState extends State<BranchReportScreen> {
  BranchPeriod _period = BranchPeriod.thisMonth();
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
    final r = await ApiService().getBranchCompare(_period.from, _period.to);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r['isSuccess'] == true && r['data'] is Map) {
        _data = Map<String, dynamic>.from(r['data'] as Map);
      } else {
        _error = r['message']?.toString() ?? 'Không tải được báo cáo';
      }
    });
  }

  List<Map<String, dynamic>> get _rows =>
      [for (final b in (_data['branches'] as List? ?? const [])) Map<String, dynamic>.from(b as Map)];

  Map<String, dynamic> get _totals => Map<String, dynamic>.from((_data['totals'] as Map?) ?? const {});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SboxColors.slate50,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
          children: [
            Row(children: [
              const Icon(Icons.account_tree_rounded, color: SboxColors.brand600),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr('Báo cáo chi nhánh'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: SboxColors.slate900)),
              ),
              IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh_rounded), tooltip: tr('Tải lại')),
            ]),
            const SizedBox(height: 8),
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
              BranchBox(
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded, color: SboxColors.warningText),
                  const SizedBox(width: 8),
                  Expanded(child: Text(tr(_error!))),
                ]),
              )
            else ...[
              _kpis(),
              const SizedBox(height: 12),
              _charts(),
              const SizedBox(height: 12),
              _table(),
              const SizedBox(height: 10),
              Text(
                tr('Doanh thu = tổng đơn hoàn tất (chưa VAT). Lãi gộp = doanh thu − trả hàng − giá vốn. '
                    'Chi phí = phiếu chi thủ công (không gồm nhập hàng / trả NCC / lương). '
                    'Lương = lương gộp các phiếu lương của nhân viên thuộc chi nhánh trong các tháng của kỳ. '
                    'Lãi ròng = lãi gộp + thu khác − chi phí − lương.'),
                style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kpis() {
    final t = _totals;
    final net = bNum(t['netProfit']);
    return SboxKpiStrip(maxColumns: 6, items: [
      SboxKpi(
        label: 'Doanh thu',
        value: bMoneyShort(t['revenue']),
        icon: Icons.payments_outlined,
        tone: SboxTone.brand,
        note: '${bQty(t['orders'])} đơn · TB ${bMoneyShort(t['avgOrder'])}',
      ),
      SboxKpi(
        label: 'Lãi gộp',
        value: bMoneyShort(t['grossProfit']),
        icon: Icons.trending_up_rounded,
        tone: SboxTone.success,
        note: 'Biên ${bNum(t['grossMarginPct']).toStringAsFixed(1).replaceAll('.', ',')}%',
      ),
      SboxKpi(
        label: 'Chi phí + lương',
        value: bMoneyShort(bNum(t['expenses']) + bNum(t['payroll'])),
        icon: Icons.receipt_long_outlined,
        tone: SboxTone.warning,
        note: 'Lương ${bMoneyShort(t['payroll'])}',
      ),
      SboxKpi(
        label: 'Lãi ròng',
        value: bMoneyShort(net),
        icon: Icons.savings_outlined,
        tone: net >= 0 ? SboxTone.success : SboxTone.danger,
        note: net >= 0 ? 'Có lãi' : 'Đang lỗ',
      ),
      SboxKpi(
        label: 'Giá trị tồn kho',
        value: bMoneyShort(t['stockValue']),
        icon: Icons.inventory_2_outlined,
        tone: SboxTone.violet,
      ),
      SboxKpi(
        label: 'Nhân sự',
        value: bQty(t['employees']),
        icon: Icons.groups_outlined,
        tone: SboxTone.neutral,
        note: '${_rows.length} chi nhánh',
      ),
    ]);
  }

  static const _palette = [
    SboxColors.brand500,
    SboxColors.success,
    SboxColors.violet,
    SboxColors.warning,
    SboxColors.danger,
    Color(0xFF0EA5E9),
    Color(0xFFF97316),
    Color(0xFF14B8A6),
  ];

  Widget _charts() {
    final rows = _rows;
    if (rows.isEmpty) return const SizedBox.shrink();
    final names = [for (final r in rows) r['name']?.toString() ?? '—'];
    final daily = Map<String, dynamic>.from((_data['daily'] as Map?) ?? const {});
    final labels = [for (final d in (daily['labels'] as List? ?? const [])) sboxDayLabel(d)];
    final series = [
      for (var i = 0; i < (daily['series'] as List? ?? const []).length; i++)
        SboxSeries(
          name: ((daily['series'] as List)[i] as Map)['name']?.toString() ?? '',
          values: [for (final v in (((daily['series'] as List)[i] as Map)['values'] as List? ?? const [])) bNum(v)],
          color: _palette[i % _palette.length],
        ),
    ];
    return SboxInsightPanel(bottomGap: 0, charts: [
      SboxChartCard(
        title: 'Doanh thu và lãi ròng theo chi nhánh',
        child: SboxBarChart(
          valueFormat: (v) => SboxFmt.money(v),
          labels: names,
          series: [
            SboxSeries(name: 'Doanh thu', values: [for (final r in rows) bNum(r['revenue'])], color: SboxColors.brand500),
            SboxSeries(name: 'Lãi gộp', values: [for (final r in rows) bNum(r['grossProfit'])], color: SboxColors.success),
            SboxSeries(name: 'Lãi ròng', values: [for (final r in rows) bNum(r['netProfit'])], color: SboxColors.violet),
          ],
        ),
      ),
      SboxChartCard(
        title: 'Tỷ trọng doanh thu',
        child: SboxDonutChart(
          valueFormat: (v) => SboxFmt.money(v),
          slices: [
            for (var i = 0; i < rows.length; i++)
              SboxSlice(names[i], bNum(rows[i]['revenue']), color: _palette[i % _palette.length]),
          ],
        ),
      ),
      if (labels.length > 1 && labels.length <= 62)
        SboxChartCard(
          title: 'Doanh thu theo ngày',
          wide: true,
          child: SboxLineChart(
            area: false,
            valueFormat: (v) => SboxFmt.money(v),
            labels: labels,
            series: series,
          ),
        ),
    ]);
  }

  Widget _table() {
    final rows = _rows;
    Widget money(num v, {Color? color}) => Text(bMoney(v),
        textAlign: TextAlign.right,
        style: TextStyle(fontWeight: FontWeight.w600, color: color ?? SboxColors.slate900, fontSize: 13));
    return BranchBox(
      title: 'So sánh chi nhánh',
      trailing: Text(tr('Bấm một dòng để xem chi tiết'), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: SboxDataTable<Map<String, dynamic>>(
        rows: rows,
        pageSize: 50,
        emptyTitle: 'Chưa có chi nhánh',
        onRowTap: (r) => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => BranchDetailScreen(
            branchId: r['branchId'].toString(),
            branchName: r['name']?.toString() ?? '',
            initialPeriod: _period,
          ),
        )),
        columns: [
          SboxColumn(
            label: 'Chi nhánh',
            primary: true,
            minWidth: 160,
            cell: (r) => Row(children: [
              Flexible(
                child: Text(r['name']?.toString() ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              if (r['isHeadquarter'] == true) ...[
                const SizedBox(width: 6),
                Text(tr('Trụ sở'), style: const TextStyle(fontSize: 11, color: SboxColors.brand600, fontWeight: FontWeight.w700)),
              ],
            ]),
            sortValue: (r) => r['name']?.toString(),
          ),
          SboxColumn(label: 'Doanh thu', numeric: true, minWidth: 120, cell: (r) => money(bNum(r['revenue'])), sortValue: (r) => bNum(r['revenue'])),
          SboxColumn(label: 'Đơn', numeric: true, minWidth: 70, text: (r) => bQty(r['orders']), sortValue: (r) => bNum(r['orders']), hideOnMobile: true),
          SboxColumn(label: 'TB / đơn', numeric: true, minWidth: 100, text: (r) => bMoney(bNum(r['avgOrder'])), hideOnMobile: true),
          SboxColumn(
              label: 'Lãi gộp',
              numeric: true,
              minWidth: 120,
              cell: (r) => money(bNum(r['grossProfit']), color: SboxColors.successText),
              sortValue: (r) => bNum(r['grossProfit'])),
          SboxColumn(
              label: '% LG',
              numeric: true,
              minWidth: 64,
              text: (r) => '${bNum(r['grossMarginPct']).toStringAsFixed(1).replaceAll('.', ',')}%',
              hideOnMobile: true),
          SboxColumn(label: 'Chi phí', numeric: true, minWidth: 110, text: (r) => bMoney(bNum(r['expenses'])), hideOnMobile: true),
          SboxColumn(label: 'Lương', numeric: true, minWidth: 110, text: (r) => bMoney(bNum(r['payroll'])), hideOnMobile: true),
          SboxColumn(
              label: 'Lãi ròng',
              numeric: true,
              minWidth: 120,
              cell: (r) {
                final v = bNum(r['netProfit']);
                return money(v, color: v >= 0 ? SboxColors.successText : SboxColors.dangerText);
              },
              sortValue: (r) => bNum(r['netProfit'])),
          SboxColumn(label: 'Tồn kho', numeric: true, minWidth: 110, text: (r) => bMoney(bNum(r['stockValue'])), hideOnMobile: true),
          SboxColumn(label: 'NV', numeric: true, minWidth: 56, text: (r) => bQty(r['employees']), hideOnMobile: true),
        ],
      ),
    );
  }
}
