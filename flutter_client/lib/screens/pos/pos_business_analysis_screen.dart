import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Phân tích tình hình kinh doanh — KPI, so sánh kỳ, kênh bán, nhóm hàng.
class PosBusinessAnalysisScreen extends StatefulWidget {
  const PosBusinessAnalysisScreen({super.key});

  @override
  State<PosBusinessAnalysisScreen> createState() =>
      _PosBusinessAnalysisScreenState();
}

class _PosBusinessAnalysisScreenState extends State<PosBusinessAnalysisScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _pctFmt = NumberFormat('#,##0.0', 'vi_VN');

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
    final res = await _api.getPosBusinessAnalysis(
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

  Widget _kpiTile({
    required String label,
    required double value,
    required double changePct,
    double yoyPct = 0,
    bool money = true,
    String? suffix,
  }) {
    final up = changePct >= 0;
    final changeColor = up ? Colors.green.shade700 : Colors.red.shade700;
    final yoyUp = yoyPct >= 0;
    final yoyColor = yoyUp ? Colors.green.shade700 : Colors.red.shade700;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: PosTheme.mobileCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(label), style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
          const SizedBox(height: 6),
          Text(
            tr(money ? _moneyFmt.format(value) : '${value.toStringAsFixed(0)}${suffix ?? ''}'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(up ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: changeColor),
              Text(tr('${_pctFmt.format(changePct.abs())}% so với kỳ trước'),
                style: TextStyle(fontSize: 11, color: changeColor),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            tr('${yoyUp ? '+' : '-'}${_pctFmt.format(yoyPct.abs())}% cùng kỳ năm trước'),
            style: TextStyle(fontSize: 11, color: yoyColor),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _data?['current'] is Map
        ? Map<String, dynamic>.from(_data!['current'] as Map)
        : <String, dynamic>{};
    final change = _data?['changePct'] is Map
        ? Map<String, dynamic>.from(_data!['changePct'] as Map)
        : <String, dynamic>{};
    final yoy = _data?['changePctYoy'] is Map
        ? Map<String, dynamic>.from(_data!['changePctYoy'] as Map)
        : <String, dynamic>{};

    final byChannel = (_data?['byChannel'] as List?) ?? [];
    final topCategories = (_data?['topCategories'] as List?) ?? [];
    final storeName = _data?['storeName']?.toString() ?? '';

    final revenue = _num(current['revenue']);
    final profit = _num(current['profit']);
    final orders = (current['orderCount'] as num?)?.toInt() ?? 0;
    final aov = _num(current['avgOrderValue']);
    final margin = _num(current['marginPct']);

    return PosReportMobileScaffold(
      title: 'Phân tích kinh doanh',
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
                if (storeName.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: PosReportBranchFooter(branchName: storeName),
                  ),
                _kpiTile(
                  label: 'Doanh thu',
                  value: revenue,
                  changePct: _num(change['revenue']),
                  yoyPct: _num(yoy['revenue']),
                ),
                const SizedBox(height: 8),
                _kpiTile(
                  label: 'Lợi nhuận',
                  value: profit,
                  changePct: _num(change['profit']),
                  yoyPct: _num(yoy['profit']),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _kpiTile(
                        label: 'Đơn hàng',
                        value: orders.toDouble(),
                        changePct: _num(change['orders']),
                        yoyPct: _num(yoy['orders']),
                        money: false,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _kpiTile(
                        label: 'TB/đơn',
                        value: aov,
                        changePct: 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _kpiTile(
                  label: 'Biên lợi nhuận',
                  value: margin,
                  changePct: 0,
                  money: false,
                  suffix: '%',
                ),
                const SizedBox(height: 10),
                PosReportCard(
                  title: 'Doanh thu theo kênh',
                  child: PosReportRankList(
                    items: byChannel.whereType<Map<String, dynamic>>().toList(),
                    labelOf: (c) => c['channel']?.toString() ?? 'Khác',
                    valueOf: (c) => _num(c['revenue']),
                    moneyFmt: _moneyFmt,
                  ),
                ),
                PosReportCard(
                  title: 'Top nhóm hàng',
                  child: PosReportRankList(
                    items: topCategories.whereType<Map<String, dynamic>>().toList(),
                    labelOf: (c) => c['categoryName']?.toString() ?? 'Khác',
                    valueOf: (c) => _num(c['revenue']),
                    moneyFmt: _moneyFmt,
                  ),
                ),
              ],
            ),
    );
  }
}
