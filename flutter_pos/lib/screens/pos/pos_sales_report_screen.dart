import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Báo cáo bán hàng kiểu KiotViet — doanh thu, lợi nhuận, top NV.
class PosSalesReportScreen extends StatefulWidget {
  const PosSalesReportScreen({super.key});

  @override
  State<PosSalesReportScreen> createState() => _PosSalesReportScreenState();
}

class _PosSalesReportScreenState extends State<PosSalesReportScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');

  PosKiotTimeFilterState _time =
      const PosKiotTimeFilterState(preset: PosKiotTimePreset.thisWeek);
  bool _loading = true;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosSalesReportSummary(
      from: _time.from,
      to: _time.to,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true && res['data'] is Map) {
        _data = Map<String, dynamic>.from(res['data'] as Map);
      } else {
        _data = null;
      }
    });
  }

  double _num(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  @override
  Widget build(BuildContext context) {
    final storeName = _data?['storeName']?.toString() ?? '';
    final revenue = _num(_data?['totalRevenue']);
    final cogs = _num(_data?['totalCogs']);
    final profit = _num(_data?['totalProfit']);

    final byDay = (_data?['byDay'] as List?) ?? [];
    final barPoints = byDay.whereType<Map>().map((d) {
      final dt = _parseDate(d['date']) ?? DateTime.now();
      return (date: dt, value: _num(d['total']));
    }).toList();

    final profitByDay = (_data?['profitByDay'] as List?) ?? [];
    final linePoints = profitByDay.whereType<Map>().map((d) {
      final dt = _parseDate(d['date']) ?? DateTime.now();
      return (
        date: dt,
        revenue: _num(d['revenue']),
        cogs: _num(d['cogs']),
        profit: _num(d['profit']),
      );
    }).toList();

    final topEmployees = (_data?['topEmployees'] as List?) ?? [];

    return PosReportMobileScaffold(
      title: 'Báo cáo bán hàng',
      time: _time,
      onTimeChanged: (PosKiotTimeFilterState s) async {
        setState(() => _time = s);
        await _load();
      },
      onRefresh: _load,
      body: _loading
          ? ListView(
              children: const [
                SizedBox(
                  height: 240,
                  child: Center(
                    child: CircularProgressIndicator(color: PosTheme.kiotBlue),
                  ),
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                PosReportCard(
                  title: 'Doanh thu',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PosReportBarChart(points: barPoints),
                      const SizedBox(height: 10),
                      PosReportBranchFooter(branchName: storeName),
                    ],
                  ),
                ),
                PosReportCard(
                  title: 'Doanh thu theo chi nhánh',
                  child: Column(
                    children: [
                      PosReportDonut(
                        total: revenue,
                        moneyFmt: _moneyFmt,
                        slices: [
                          (
                            label: storeName.isEmpty ? 'Chi nhánh' : storeName,
                            value: revenue,
                            color: PosTheme.kiotBlue,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      PosReportBranchFooter(branchName: storeName),
                    ],
                  ),
                ),
                PosReportCard(
                  title: 'Lợi nhuận',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PosReportMultiLineChart(points: linePoints),
                      const SizedBox(height: 12),
                      PosReportMetricTiles(
                        moneyFmt: _moneyFmt,
                        tiles: [
                          (label: 'Lợi nhuận', value: profit, color: PosTheme.kiotBlue),
                          (label: 'Doanh thu', value: revenue, color: Colors.red),
                          (label: 'Giá vốn', value: cogs, color: Colors.amber.shade700),
                        ],
                      ),
                    ],
                  ),
                ),
                PosReportCard(
                  title: 'Top nhân viên bán tốt',
                  trailing: TextButton(
                    onPressed: () {},
                    child: Text(tr('Xem thêm >'), style: TextStyle(fontSize: 12)),
                  ),
                  child: PosReportRankList(
                    items: topEmployees.whereType<Map<String, dynamic>>().toList(),
                    labelOf: (e) =>
                        e['soldBy']?.toString().trim().isNotEmpty == true
                            ? e['soldBy'].toString()
                            : '—',
                    valueOf: (e) => _num(e['revenue']),
                    moneyFmt: _moneyFmt,
                  ),
                ),
              ],
            ),
    );
  }
}
