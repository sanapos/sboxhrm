import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

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
    return PosReportMobileScaffold(
      title: 'Bán theo khách',
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
                TextField(
                  controller: _searchCtrl,
                  decoration: PosTheme.inputDecoration(label: 'Tìm khách'),
                  onSubmitted: (_) => _load(),
                ),
                const SizedBox(height: 10),
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
                        color: const Color(0xFF166534),
                      ),
                      (
                        label: 'KH mới',
                        value: (_data?['newCustomerCount'] as num?)?.toDouble() ?? 0,
                        color: const Color(0xFF7C3AED),
                      ),
                    ],
                  ),
                ),
                PosReportCard(
                  title: '${_data?['customerCount'] ?? items.length} khách',
                  child: items.isEmpty
                      ? Text(tr('Chưa có dữ liệu'),
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
    final last = DateTime.tryParse('${r['lastPurchaseAt'] ?? ''}');
    final isNew = r['isNew'] == true;
    return Column(
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
                  color: const Color(0xFF7C3AED).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(tr('Mới'),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF7C3AED))),
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
    );
  }
}
