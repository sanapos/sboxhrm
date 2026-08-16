import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import 'pos_profit_report_screen.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

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
  Map<String, dynamic>? _einvoice;

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
    final ei = await _api.getPosEInvoiceSummary(
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
      if (ei['isSuccess'] == true && ei['data'] is Map) {
        _einvoice = Map<String, dynamic>.from(ei['data'] as Map);
      } else {
        _einvoice = null;
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
    final vat = _num(_data?['totalVat']);
    final revenueInclVat = _num(_data?['totalRevenueInclVat']);
    final refund = _num(_data?['totalRefund']);
    final cogs = _num(_data?['totalCogs']);
    final profit = _num(_data?['totalProfit']);
    final margin = _num(_data?['profitMarginPct']);

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
                      const SizedBox(height: 12),
                      PosReportMetricTiles(
                        moneyFmt: _moneyFmt,
                        tiles: [
                          (
                            label: 'DT chưa VAT',
                            value: revenue,
                            color: PosTheme.kiotBlue,
                          ),
                          (
                            label: 'VAT',
                            value: vat,
                            color: const Color(0xFF7C3AED),
                          ),
                          (
                            label: 'DT gồm VAT',
                            value: revenueInclVat > 0 ? revenueInclVat : revenue + vat,
                            color: const Color(0xFF0F766E),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      PosReportMetricTiles(
                        moneyFmt: _moneyFmt,
                        tiles: [
                          (
                            label: 'Hoàn trả kỳ',
                            value: refund,
                            color: Colors.orange.shade800,
                          ),
                          (
                            label: 'Đã thu',
                            value: _num(_data?['totalPaid']),
                            color: const Color(0xFF166534),
                          ),
                          (
                            label: 'Giảm giá',
                            value: _num(_data?['totalDiscount']),
                            color: Colors.grey.shade700,
                          ),
                        ],
                      ),
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
                  title: 'Đặt chỗ / cọc',
                  child: PosReportMetricTiles(
                    moneyFmt: _moneyFmt,
                    tiles: [
                      (
                        label: 'Cọc đang giữ',
                        value: _num(_data?['reservationDepositHeld']),
                        color: const Color(0xFF0F766E),
                      ),
                      (
                        label: 'Cọc đã trừ HĐ',
                        value: _num(_data?['reservationDepositApplied']),
                        color: PosTheme.kiotBlue,
                      ),
                      (
                        label: 'Cọc mất',
                        value: _num(_data?['reservationDepositForfeited']),
                        color: Colors.red.shade700,
                      ),
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
                          (label: 'Doanh thu', value: revenue, color: const Color(0xFF0F766E)),
                          (label: 'Giá vốn', value: cogs, color: Colors.amber.shade700),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr('Biên LN: ${margin.toStringAsFixed(1)}%'),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: PosTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                PosReportCard(
                  title: 'Hóa đơn điện tử',
                  child: PosReportMetricTiles(
                    moneyFmt: _moneyFmt,
                    tiles: [
                      (
                        label: 'Đã xuất',
                        value: _num(_einvoice?['issuedCount']),
                        color: const Color(0xFF166534),
                      ),
                      (
                        label: 'Không xuất',
                        value: _num(_einvoice?['skippedCount']),
                        color: const Color(0xFF475569),
                      ),
                      (
                        label: 'Lỗi',
                        value: _num(_einvoice?['failedCount']),
                        color: Colors.red.shade700,
                      ),
                    ],
                  ),
                ),
                PosReportCard(
                  title: 'Top nhân viên bán tốt',
                  trailing: TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const PosProfitReportScreen(initialDim: 'staff'),
                        ),
                      );
                    },
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
