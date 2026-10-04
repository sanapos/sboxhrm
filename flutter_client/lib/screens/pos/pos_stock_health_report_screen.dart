import 'package:flutter/material.dart';
import '../../utils/api_datetime.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';
import '../../widgets/sbox/sbox_ui.dart';
/// Cháy hàng / chậm / chết tồn.
class PosStockHealthReportScreen extends StatefulWidget {
  const PosStockHealthReportScreen({super.key});

  @override
  State<PosStockHealthReportScreen> createState() =>
      _PosStockHealthReportScreenState();
}

class _PosStockHealthReportScreenState extends State<PosStockHealthReportScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _dateFmt = DateFormat('dd/MM/yyyy');
  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisMonth);
  String _mode = 'all';
  bool _loading = true;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosStockHealthReport(
      from: _time.from,
      to: _time.to,
      mode: _mode,
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

  String _statusVi(String? s) => switch (s) {
        'hot' => 'Cháy / dưới min',
        'slow' => 'Chậm',
        'dead' => 'Chết tồn',
        _ => s ?? '',
      };

  Color _statusColor(String? s) => switch (s) {
        'hot' => Colors.red.shade700,
        'slow' => const Color(0xFFCA8A04),
        'dead' => SboxColors.slate500,
        _ => PosTheme.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    final items = ((_data?['items'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final hot = _n(_data?['hotCount']), slow = _n(_data?['slowCount']), dead = _n(_data?['deadCount']);
    final byStatus = <String, double>{};
    for (final r in items) {
      final k = _statusVi(r['status']?.toString());
      byStatus[k] = (byStatus[k] ?? 0) + _n(r['stockValue']);
    }
    final insight = SboxInsightPanel(
      kpis: [
        SboxKpi(label: 'Cháy hàng', value: SboxFmt.number(hot), icon: Icons.local_fire_department_outlined, tone: SboxTone.danger, note: 'Bán nhanh, sắp hết'),
        SboxKpi(label: 'Bán chậm', value: SboxFmt.number(slow), icon: Icons.hourglass_bottom_rounded, tone: SboxTone.warning),
        SboxKpi(label: 'Chết tồn', value: SboxFmt.number(dead), icon: Icons.block_outlined, tone: SboxTone.neutral, note: 'Không bán trong kỳ'),
        SboxKpi(
            label: 'Giá trị tồn trong danh sách',
            value: SboxFmt.money(items.fold<double>(0, (a, r) => a + _n(r['stockValue']))),
            icon: Icons.warehouse_outlined,
            tone: SboxTone.violet),
      ],
      charts: [
        SboxChartCard(
          title: 'Vốn nằm trong kho theo tình trạng',
          child: SboxDonutChart(slices: [for (final e in byStatus.entries) SboxSlice(e.key, e.value)]),
        ),
        SboxChartCard(
          title: 'Tồn giá trị lớn nhất',
          child: SboxRankList(
            color: SboxColors.violet,
            items: [for (final r in items) SboxSlice(r['name']?.toString() ?? '—', _n(r['stockValue']), caption: 'Tồn ${r['onHandQty'] ?? 0}')],
          ),
        ),
      ],
    );
    return PosReportMobileScaffold(
      title: 'Tồn chậm / cháy hàng',
      exportModule: 'PosReportStock',
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
                      ('all', 'Cần xử lý'),
                      ('hot', 'Cháy ${_data?['hotCount'] ?? 0}'),
                      ('slow', 'Chậm ${_data?['slowCount'] ?? 0}'),
                      ('dead', 'Chết tồn ${_data?['deadCount'] ?? 0}'),
                    ])
                      FilterChip(
                        label: Text(tr(e.$2)),
                        selected: _mode == e.$1,
                        onSelected: (_) {
                          setState(() => _mode = e.$1);
                          _load();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                insight,
                PosReportCard(
                  title: 'Danh sách',
                  child: items.isEmpty
                      ? Text(tr('Không có hàng trong bộ lọc'),
                          style: const TextStyle(color: PosTheme.textSecondary))
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
    final lastSold = parseApiUtcDateTime(r['lastSoldAt']);
    final lastIn = parseApiUtcDateTime(r['lastInboundAt']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(tr(r['name']?.toString() ?? '—'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            Text(
              tr(_statusVi(r['status']?.toString())),
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _statusColor(r['status']?.toString())),
            ),
          ],
        ),
        Text(
          tr('${r['productCode']} · Tồn ${r['onHandQty']} · GT ${_moneyFmt.format(_n(r['stockValue']))}'),
          style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
        ),
        Text(
          tr('Bán kỳ: ${r['qtySold'] ?? 0} · DT ${_moneyFmt.format(_n(r['revenue']))} · ${lastSold == null ? 'chưa bán' : 'bán ${_dateFmt.format(lastSold)}'} · ${lastIn == null ? 'chưa nhập' : 'nhập ${_dateFmt.format(lastIn)}'}'),
          style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),
        ),
      ],
    );
  }
}
