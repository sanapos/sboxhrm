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

/// LN theo hàng / nhóm / kênh / nhân viên — bấm dòng mở hóa đơn gốc.
class PosProfitReportScreen extends StatefulWidget {
  const PosProfitReportScreen({super.key, this.initialDim = 'product'});

  final String initialDim;

  @override
  State<PosProfitReportScreen> createState() => _PosProfitReportScreenState();
}

class _PosProfitReportScreenState extends State<PosProfitReportScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _pngKey = GlobalKey();
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
        ? await _api.getPosProfitByProduct(
            from: _time.from, to: _time.to, limit: 500)
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

  Future<void> _exportExcel() async {
    final items = _items();
    await PosReportExport.excel(
      context: context,
      title: 'Báo cáo lợi nhuận',
      sheetName: 'Loi nhuan',
      filePrefix: 'POS_LoiNhuan',
      periodLabel: _time.displayLabel,
      filterLabel: _dim,
      headers: const [
        'Tên',
        'Mã',
        'SL',
        'Doanh thu',
        'Giá vốn',
        'LN',
        'Biên %',
        'Số HĐ',
      ],
      rows: [
        for (final r in items)
          [
            r['productName'] ?? r['label'] ?? '',
            r['productCode'] ?? '',
            _n(r['qty']),
            _n(r['revenue']),
            _n(r['cogs']),
            _n(r['profit']),
            _n(r['marginPct']),
            _n(r['orderCount']).toInt(),
          ],
      ],
      summaryLines: [
        'DT ${_n(_data?['totalRevenue'])}',
        'COGS ${_n(_data?['totalCogs'])}',
        'LN ${_n(_data?['totalProfit'])}',
      ],
    );
  }

  void _openRow(Map<String, dynamic> r) {
    final pid = '${r['productId'] ?? r['id'] ?? ''}';
    final soldBy = _dim == 'staff' ? '${r['label'] ?? r['soldBy'] ?? ''}' : null;
    unawaited(PosReportOpen.sales(
      context,
      from: _time.from,
      to: _time.to,
      productId: _dim == 'product' && pid.isNotEmpty ? pid : null,
      soldBy: (soldBy ?? '').trim().isEmpty ? null : soldBy,
      search: _dim == 'product' || _dim == 'staff'
          ? null
          : '${r['label'] ?? r['productName'] ?? ''}',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items();
    return PosReportMobileScaffold(
      title: 'Lợi nhuận',
      time: _time,
      pngKey: _pngKey,
      onExportExcel: () => unawaited(_exportExcel()),
      onExportPng: () => unawaited(PosReportExport.png(
        context: context,
        key: _pngKey,
        filePrefix: 'POS_LoiNhuan',
      )),
      onTimeChanged: (s) async {
        setState(() => _time = s);
        await _load();
      },
      onRefresh: _load,
      body: _loading
          ? ListView(children: const [
              SizedBox(
                  height: 240,
                  child: Center(
                      child: CircularProgressIndicator(color: PosTheme.kiotBlue))),
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
                PosReportCard(
                  title: 'Tổng kỳ',
                  subtitle: _time.displayLabel,
                  child: PosReportMetricTiles(
                    moneyFmt: _moneyFmt,
                    onTileTap: (_) => unawaited(PosReportOpen.sales(
                      context,
                      from: _time.from,
                      to: _time.to,
                    )),
                    tiles: [
                      (
                        label: 'DT',
                        value: _n(_data?['totalRevenue']),
                        color: PosTheme.kiotBlue
                      ),
                      (
                        label: 'COGS',
                        value: _n(_data?['totalCogs']),
                        color: Colors.amber.shade700
                      ),
                      (
                        label: 'LN',
                        value: _n(_data?['totalProfit']),
                        color: const Color(0xFF166534)
                      ),
                    ],
                  ),
                ),
                PosReportCard(
                  title: _dim == 'product'
                      ? 'Theo hàng · bấm để mở HĐ'
                      : 'Chi tiết · bấm để mở HĐ',
                  child: items.isEmpty
                      ? const PosReportEmpty()
                      : Column(
                          children: [
                            for (var i = 0; i < items.length; i++) ...[
                              if (i > 0) const Divider(height: 16),
                              InkWell(
                                onTap: () => _openRow(items[i]),
                                child: _row(items[i]),
                              ),
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
        '${r['orderCount'] ?? ''} đơn · biên ${_n(r['marginPct']).toStringAsFixed(1)}%';
    final profit = _n(r['profit']);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(name),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                tr(_dim == 'product'
                    ? '${r['productCode'] ?? ''} · SL ${r['qty'] ?? 0} · DT ${_moneyFmt.format(_n(r['revenue']))} · biên ${_n(r['marginPct']).toStringAsFixed(1)}%'
                    : sub.toString()),
                style: const TextStyle(
                    fontSize: 12, color: PosTheme.textSecondary),
              ),
            ],
          ),
        ),
        PosReportMoneyLabel(
          profit,
          color: profit < 0
              ? const Color(0xFFB42318)
              : const Color(0xFF166534),
        ),
        const Icon(Icons.chevron_right, size: 18, color: Color(0xFF8A9199)),
      ],
    );
  }
}
