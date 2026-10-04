import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../utils/pos_report_export.dart';
import '../../utils/pos_report_open.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../widgets/sbox/sbox_ui.dart';
/// Doanh thu / lần mua / khách mới theo kỳ.
class PosCustomerSalesReportScreen extends StatefulWidget {
  const PosCustomerSalesReportScreen({super.key});

  @override
  State<PosCustomerSalesReportScreen> createState() =>
      _PosCustomerSalesReportScreenState();
}

class _PosCustomerSalesReportScreenState extends State<PosCustomerSalesReportScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _dateFmt = DateFormat('dd/MM');
  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisMonth);
  bool _loading = true;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosCustomerSalesReport(
      from: _time.from,
      to: _time.to,
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res['isSuccess'] == true && res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
    });
  }

  double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    final items = ((_data?['items'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final rev = _n(_data?['totalRevenue']);
    final newCount = items.where((r) => r['isNew'] == true).length;
    final newRev = items.where((r) => r['isNew'] == true).fold<double>(0, (a, r) => a + _n(r['revenue']));
    final custCount = _n(_data?['customerCount'] ?? items.length);
    // Khách lẻ (đơn không gắn khách) tách riêng — không tính là «khách cũ», không chia vào DT TB / khách.
    final walkInRev = _n(_data?['walkInRevenue']);
    final namedRev = rev - walkInRev;
    final oldRev = items.where((r) => r['customerId'] != null && r['isNew'] != true).fold<double>(0, (a, r) => a + _n(r['revenue']));
    final insight = SboxInsightPanel(
      kpis: [
        SboxKpi(label: 'Doanh thu từ khách', value: SboxFmt.money(rev), icon: Icons.payments_outlined, note: _time.displayLabel),
        SboxKpi(label: 'Lợi nhuận', value: SboxFmt.money(_n(_data?['totalProfit'])), icon: Icons.trending_up_rounded, tone: SboxTone.success),
        SboxKpi(label: 'Khách mua', value: SboxFmt.number(custCount), icon: Icons.people_outline, tone: SboxTone.violet,
            note: '${SboxFmt.number(_n(_data?['newCustomerCount']))} khách mới'),
        SboxKpi(
            label: 'DT TB / khách',
            value: SboxFmt.money(custCount > 0 ? namedRev / custCount : 0),
            icon: Icons.person_outline,
            tone: SboxTone.neutral,
            note: walkInRev > 0 ? 'Khách lẻ ${SboxFmt.money(walkInRev)}' : null),
      ],
      charts: [
        SboxChartCard(
          title: 'Khách mua nhiều nhất',
          child: SboxRankList(items: [
            for (final r in items) SboxSlice(r['name']?.toString() ?? '—', _n(r['revenue']), caption: '${r['orderCount'] ?? 0} HĐ'),
          ]),
        ),
        SboxChartCard(
          title: 'Khách mới, khách cũ, khách lẻ',
          subtitle: 'Theo doanh thu',
          child: SboxDonutChart(slices: [
            SboxSlice('Khách cũ', oldRev),
            SboxSlice('Khách mới ($newCount)', newRev, color: SboxColors.success),
            if (walkInRev > 0) SboxSlice('Khách lẻ', walkInRev, color: SboxColors.slate400),
          ]),
        ),
      ],
    );
    return PosReportMobileScaffold(
      title: 'Bán theo khách',
      exportModule: 'PosSalesReport',
      time: _time,
      onExportExcel: () => unawaited(PosReportExport.excel(
        context: context,
        title: 'Bán theo khách',
        sheetName: 'Khach hang',
        filePrefix: 'POS_BanTheoKhach',
        periodLabel: _time.displayLabel,
        headers: const ['Khách', 'SĐT', 'Số HĐ', 'DT', 'LN', 'Nợ'],
        rows: [
          for (final r in items)
            [
              r['name'] ?? '',
              r['phone'] ?? r['customerCode'] ?? '',
              r['orderCount'] ?? 0,
              _n(r['revenue']),
              _n(r['profit']),
              _n(r['currentDebt']),
            ],
        ],
      )),
      onTimeChanged: (s) async {
        setState(() => _time = s);
        await _load();
      },
      onRefresh: _load,
      body: _loading
          ? ListView(children: const [
              SizedBox(height: 240, child: Center(child: CircularProgressIndicator(color: PosTheme.kiotBlue))),
            ])
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: PosTheme.inputDecoration(label: 'Tìm khách'),
                  onSubmitted: (_) => _load(),
                ),
                const SizedBox(height: 10),
                insight,
                PosReportCard(
                  title: 'Tổng kỳ',
                  child: PosReportMetricTiles(
                    moneyFmt: _moneyFmt,
                    tiles: [
                      (
                        label: 'DT',
                        value: _n(_data?['totalRevenue']),
                        color: PosTheme.kiotBlue,
                      ),
                      (
                        label: 'LN',
                        value: _n(_data?['totalProfit']),
                        color: SboxColors.successText,
                      ),
                      (
                        label: 'KH mới',
                        value: (_data?['newCustomerCount'] as num?)?.toDouble() ?? 0,
                        color: SboxColors.violet,
                      ),
                    ],
                  ),
                ),
                PosReportCard(
                  title: '${_data?['customerCount'] ?? items.length} khách',
                  child: items.isEmpty
                      ? const PosReportEmpty()
                      : Column(
                          children: [
                            for (var i = 0; i < items.length; i++) ...[
                              if (i > 0) const Divider(height: 16),
                              _row(items[i]),
                            ],
                          ],
                        ),
                ),
              ],
            ),
    );
  }

  Widget _row(Map<String, dynamic> r) {
    final last = DateTime.tryParse('${r['lastPurchaseAt'] ?? ''}');
    final isNew = r['isNew'] == true;
    final cid = '${r['customerId'] ?? r['id'] ?? ''}';
    return InkWell(
      onTap: () => unawaited(PosReportOpen.sales(
        context,
        from: _time.from,
        to: _time.to,
        customerId: cid.isEmpty ? null : cid,
        customerName: r['name']?.toString(),
      )),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(tr(r['name']?.toString() ?? '—'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (isNew)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: SboxColors.violet.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(tr('Mới'),
                    style: const TextStyle(fontSize: 11, color: SboxColors.violet)),
              ),
          ],
        ),
        Text(
          tr('${r['phone'] ?? r['customerCode'] ?? ''} · ${r['orderCount'] ?? 0} đơn · DT ${_moneyFmt.format(_n(r['revenue']))} · LN ${_moneyFmt.format(_n(r['profit']))}'),
          style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
        ),
        Text(
          tr('Mua cuối: ${last == null ? '—' : _dateFmt.format(last)} · Nợ ${_moneyFmt.format(_n(r['currentDebt']))}'),
          style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),
        ),
      ],
      ),
    );
  }
}
