import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_einvoice.dart';
import '../../services/api_service.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Tổng hợp xuất hóa đơn điện tử theo khoảng thời gian.
class PosEInvoiceReportScreen extends StatefulWidget {
  const PosEInvoiceReportScreen({super.key});

  @override
  State<PosEInvoiceReportScreen> createState() =>
      _PosEInvoiceReportScreenState();
}

class _PosEInvoiceReportScreenState extends State<PosEInvoiceReportScreen> {
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
    final res = await _api.getPosEInvoiceSummary(from: _time.from, to: _time.to);
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

  @override
  Widget build(BuildContext context) {
    final issued = _num(_data?['issuedCount']);
    final skipped = _num(_data?['skippedCount']);
    final failed = _num(_data?['failedCount']);
    final pending = _num(_data?['pendingCount']);
    final none = _num(_data?['noneCount']);
    final total = _num(_data?['totalCompleted']);

    return PosReportMobileScaffold(
      title: 'Hóa đơn điện tử',
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
                  title: 'Tổng hợp xuất HĐĐT',
                  child: Column(
                    children: [
                      PosReportMetricTiles(
                        tiles: [
                          (
                            label: posEInvoiceStatusLabel('Issued'),
                            value: issued,
                            color: const Color(0xFF166534),
                          ),
                          (
                            label: posEInvoiceStatusLabel('Skipped'),
                            value: skipped,
                            color: const Color(0xFF475569),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      PosReportMetricTiles(
                        tiles: [
                          (
                            label: posEInvoiceStatusLabel('Failed'),
                            value: failed,
                            color: Colors.red.shade700,
                          ),
                          (
                            label: 'Đơn hoàn thành',
                            value: total,
                            color: PosTheme.kiotBlue,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PosReportCard(
                  title: 'Doanh thu đã xuất / chưa xuất',
                  child: PosReportMetricTiles(
                    moneyFmt: _moneyFmt,
                    tiles: [
                      (
                        label: 'Đã xuất',
                        value: _num(_data?['issuedAmount']),
                        color: const Color(0xFF166534),
                      ),
                      (
                        label: 'Không xuất',
                        value: _num(_data?['skippedAmount']),
                        color: const Color(0xFF475569),
                      ),
                      (
                        label: 'Lỗi xuất',
                        value: _num(_data?['failedAmount']),
                        color: Colors.red.shade700,
                      ),
                    ],
                  ),
                ),
                if (pending > 0 || none > 0)
                  PosReportCard(
                    title: 'Chờ xử lý',
                    child: Text(
                      tr('Đang xử lý: ${pending.toStringAsFixed(0)} · Chưa xuất: ${none.toStringAsFixed(0)}'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
            ),
    );
  }
}
