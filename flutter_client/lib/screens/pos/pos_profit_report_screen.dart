import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../utils/pos_report_export.dart';
import '../../utils/pos_report_open.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import '../../widgets/reports/report_drill_sheet.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../widgets/sbox/sbox_ui.dart';
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
      periodLabel: _time.exportLabel,
      filterLabel: 'Theo ${const {'product': 'hàng', 'category': 'nhóm hàng', 'channel': 'kênh bán', 'staff': 'nhân viên'}[_dim] ?? _dim}',
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
            r['productName'] ?? r['displayName'] ?? r['label'] ?? '',
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
        'Giá vốn ${_n(_data?['totalCogs'])}',
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
      soldByLabel: _dim == 'staff' ? r['displayName']?.toString() : null,
      search: _dim == 'product' || _dim == 'staff'
          ? null
          : '${r['label'] ?? r['productName'] ?? ''}',
    ));
  }

  static const _dimNames = {'product': 'hàng', 'category': 'nhóm hàng', 'channel': 'kênh bán', 'staff': 'nhân viên'};

  String _nameOf(Map<String, dynamic> r) =>
      r['productName']?.toString() ?? r['displayName']?.toString() ?? r['label']?.toString() ?? '—';

  /// Chip tổng → từng dòng của bảng chi tiết (theo hàng / nhóm / kênh / NV) cộng lại ra số chip.
  /// [field]: revenue / cogs / profit. [onlyLosing]: chỉ mục có lợi nhuận âm.
  void _drill(String title, String field, {bool onlyLosing = false, String? note}) {
    final items = _items().where((r) => !onlyLosing || _n(r['profit']) < 0).toList()
      ..sort((a, b) => onlyLosing
          ? _n(a['profit']).compareTo(_n(b['profit']))
          : _n(b[field]).compareTo(_n(a[field])));
    final sum = items.fold<double>(0, (s, r) => s + _n(r[field]));
    final dimName = _dimNames[_dim] ?? _dim;
    showReportDrillSheet(
      context,
      title: title,
      subtitle: 'Theo $dimName · ${_time.displayLabel}',
      note: note,
      total: 'Tổng ${_moneyFmt.format(sum)}',
      footer: _dim == 'product' && _items().length >= 500
          ? 'Chỉ hiện 500 mặt hàng đầu — tổng dòng có thể nhỏ hơn số trên chip.'
          : null,
      rows: [
        for (final r in items)
          ReportDrillRow(
            title: _nameOf(r),
            subtitle: [
              if ((r['productCode'] ?? '').toString().isNotEmpty) r['productCode'].toString(),
              if (_dim == 'product') 'SL ${SboxFmt.qty(_n(r['qty']))}',
              if (r['orderCount'] != null) '${_n(r['orderCount']).toInt()} đơn',
              'DT ${_moneyFmt.format(_n(r['revenue']))}',
              'vốn ${_moneyFmt.format(_n(r['cogs']))}',
              'biên ${SboxFmt.pct(_n(r['marginPct']))}',
            ].join(' · '),
            trailing: _moneyFmt.format(_n(r[field])),
            trailingColor: field == 'profit' && _n(r['profit']) < 0 ? const Color(0xFFB42318) : null,
            icon: _dim == 'product' ? Icons.inventory_2_outlined : null,
            onTap: () => _openRow(r),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items();
    String nameOf(Map<String, dynamic> r) =>
        r['productName']?.toString() ?? r['displayName']?.toString() ?? r['label']?.toString() ?? '—';
    final byRev = [...items]..sort((a, b) => _n(b['revenue']).compareTo(_n(a['revenue'])));
    final top = byRev.take(10).toList();
    final rev = _n(_data?['totalRevenue']);
    final profit = _n(_data?['totalProfit']);
    final losing = items.where((r) => _n(r['profit']) < 0).length;
    final dimLabel = const {'product': 'hàng', 'category': 'nhóm', 'channel': 'kênh', 'staff': 'nhân viên'}[_dim] ?? 'mục';
    final insight = SboxInsightPanel(
      kpis: [
        SboxKpi(label: 'Doanh thu', value: SboxFmt.money(rev), icon: Icons.payments_outlined, note: _time.displayLabel,
            onTap: () => _drill('Doanh thu', 'revenue')),
        SboxKpi(label: 'Giá vốn', value: SboxFmt.money(_n(_data?['totalCogs'])), icon: Icons.inventory_2_outlined, tone: SboxTone.warning,
            onTap: () => _drill('Giá vốn', 'cogs')),
        SboxKpi(label: 'Lợi nhuận gộp', value: SboxFmt.money(profit), icon: Icons.trending_up_rounded, tone: profit < 0 ? SboxTone.danger : SboxTone.success,
            note: 'Biên ${SboxFmt.pct(rev > 0 ? profit / rev * 100 : 0)}',
            onTap: () => _drill('Lợi nhuận gộp', 'profit',
                note: 'Lợi nhuận gộp = Doanh thu − Giá vốn = ${_moneyFmt.format(rev)} − '
                    '${_moneyFmt.format(_n(_data?['totalCogs']))} = ${_moneyFmt.format(profit)}.\n'
                    'Biên = Lợi nhuận ÷ Doanh thu = ${SboxFmt.pct(rev > 0 ? profit / rev * 100 : 0)}.')),
        SboxKpi(label: 'Mục bị lỗ', value: SboxFmt.number(losing), icon: Icons.report_gmailerrorred_outlined,
            tone: losing > 0 ? SboxTone.danger : SboxTone.neutral, note: 'Bán dưới giá vốn',
            onTap: () => _drill('Mục bị lỗ', 'profit', onlyLosing: true,
                note: 'Các ${_dimNames[_dim] ?? 'mục'} có lợi nhuận âm (doanh thu thấp hơn giá vốn) trong kỳ.')),
      ],
      charts: [
        SboxChartCard(
          title: 'Doanh thu và lợi nhuận theo $dimLabel',
          subtitle: 'Top 10 theo doanh thu',
          child: SboxBarChart(
            labels: [for (final r in top) nameOf(r)],
            series: [
              SboxSeries(name: 'Doanh thu', values: [for (final r in top) _n(r['revenue'])]),
              SboxSeries(name: 'Lợi nhuận', values: [for (final r in top) _n(r['profit'])], color: SboxColors.success),
            ],
          ),
        ),
        SboxChartCard(
          title: 'Lãi nhiều nhất',
          child: SboxRankList(
            color: SboxColors.success,
            items: [for (final r in items) SboxSlice(nameOf(r), _n(r['profit']), caption: 'biên ${SboxFmt.pct(_n(r['marginPct']))}')],
          ),
        ),
      ],
    );
    return PosReportMobileScaffold(
      title: 'Lợi nhuận',
      exportModule: 'PosReportProfit',
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
                insight,
                PosReportCard(
                  title: 'Tổng kỳ',
                  subtitle: _time.displayLabel,
                  child: PosReportMetricTiles(
                    moneyFmt: _moneyFmt,
                    onTileTap: (i) => switch (i) {
                      0 => _drill('Doanh thu', 'revenue'),
                      1 => _drill('Giá vốn', 'cogs'),
                      _ => _drill('Lợi nhuận', 'profit'),
                    },
                    tiles: [
                      (
                        label: 'DT',
                        value: _n(_data?['totalRevenue']),
                        color: PosTheme.kiotBlue
                      ),
                      (
                        label: 'Giá vốn',
                        value: _n(_data?['totalCogs']),
                        color: Colors.amber.shade700
                      ),
                      (
                        label: 'LN',
                        value: _n(_data?['totalProfit']),
                        color: SboxColors.successText
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
    final name = r['productName']?.toString() ?? r['displayName']?.toString() ?? r['label']?.toString() ?? '—';
    final sub = r['productCode']?.toString() ??
        '${r['orderCount'] ?? ''} đơn · biên ${SboxFmt.pct(_n(r['marginPct']))}';
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
                    ? '${r['productCode'] ?? ''} · SL ${SboxFmt.qty(_n(r['qty']))} · DT ${_moneyFmt.format(_n(r['revenue']))} · biên ${SboxFmt.pct(_n(r['marginPct']))}'
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
              : SboxColors.successText,
        ),
        const Icon(Icons.chevron_right, size: 18, color: Color(0xFF8A9199)),
      ],
    );
  }
}
