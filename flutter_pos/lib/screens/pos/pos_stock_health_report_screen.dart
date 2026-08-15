import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

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
        'dead' => const Color(0xFF64748B),
        _ => PosTheme.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    final items = ((_data?['items'] as List?) ?? [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    return PosReportMobileScaffold(
      title: 'Tồn chậm / cháy hàng',
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
    final lastSold = DateTime.tryParse('${r['lastSoldAt'] ?? ''}');
    final lastIn = DateTime.tryParse('${r['lastInboundAt'] ?? ''}');
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
