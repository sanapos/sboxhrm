import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// LN theo hàng / nhóm / kênh / nhân viên.
class PosProfitReportScreen extends StatefulWidget {
  const PosProfitReportScreen({super.key, this.initialDim = 'product'});

  final String initialDim;

  @override
  State<PosProfitReportScreen> createState() => _PosProfitReportScreenState();
}

class _PosProfitReportScreenState extends State<PosProfitReportScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisWeek);
  late String _dim;
  bool _loading = true;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _dim = widget.initialDim;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = _dim == 'product'
        ? await _api.getPosProfitByProduct(from: _time.from, to: _time.to)
        : await _api.getPosProfitByDimension(
            from: _time.from, to: _time.to, groupBy: _dim);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res['isSuccess'] == true && res['data'] is Map
          ? Map<String, dynamic>.from(res['data'] as Map)
          : null;
    });
  }

  double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  List<Map<String, dynamic>> _items() => ((_data?['items'] as List?) ?? [])
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  @override
  Widget build(BuildContext context) {
    final items = _items();
    return PosReportMobileScaffold(
      title: 'Lợi nhuận theo chiều',
      time: _time,
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
                Wrap(
                  spacing: 8,
                  children: [
                    for (final e in [
                      ('product', 'Hàng'),
                      ('category', 'Nhóm'),
                      ('channel', 'Kênh'),
                      ('staff', 'NV'),
                    ])
                      FilterChip(
                        label: Text(tr(e.$2)),
                        selected: _dim == e.$1,
                        onSelected: (_) {
                          setState(() => _dim = e.$1);
                          _load();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_dim == 'product')
                  PosReportCard(
                    title: 'Tổng kỳ',
                    child: PosReportMetricTiles(
                      moneyFmt: _moneyFmt,
                      tiles: [
                        (label: 'DT', value: _n(_data?['totalRevenue']), color: PosTheme.kiotBlue),
                        (label: 'COGS', value: _n(_data?['totalCogs']), color: Colors.amber.shade700),
                        (label: 'LN', value: _n(_data?['totalProfit']), color: const Color(0xFF166534)),
                      ],
                    ),
                  ),
                PosReportCard(
                  title: _dim == 'product' ? 'Theo hàng' : 'Chi tiết',
                  child: items.isEmpty
                      ? Text(tr('Chưa có dữ liệu'), style: const TextStyle(color: PosTheme.textSecondary))
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
    final name = r['productName']?.toString() ?? r['label']?.toString() ?? '—';
    final sub = r['productCode']?.toString() ??
        '${r['orderCount'] ?? ''} đơn · biên ${ _n(r['marginPct']).toStringAsFixed(1)}%';
    final profit = _n(r['profit']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(tr(name), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text(
              _moneyFmt.format(profit),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: profit < 0 ? Colors.red : const Color(0xFF166534),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          tr(_dim == 'product'
              ? '${r['productCode'] ?? ''} · SL ${r['qty'] ?? 0} · DT ${_moneyFmt.format(_n(r['revenue']))} · biên ${_n(r['marginPct']).toStringAsFixed(1)}%'
              : sub.toString()),
          style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
        ),
      ],
    );
  }
}
