import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_mobile_widgets.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/reports/pos_report_widgets.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

class PosCustomerDebtReportScreen extends StatefulWidget {
  const PosCustomerDebtReportScreen({super.key});

  @override
  State<PosCustomerDebtReportScreen> createState() =>
      _PosCustomerDebtReportScreenState();
}

class _PosCustomerDebtReportScreenState extends State<PosCustomerDebtReportScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  bool _loading = true;
  double _sumDebt = 0;
  double _sum0 = 0;
  double _sum31 = 0;
  double _sum61 = 0;
  double _sum90 = 0;
  int _totalCustomers = 0;
  bool _includeZero = false;
  List<Map<String, dynamic>> _items = [];

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
    final res = await _api.getPosCustomerDebtReport(
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      includeZeroDebt: _includeZero,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final data = res['data'] as Map<String, dynamic>;
      setState(() {
        _sumDebt = (data['sumDebt'] is num)
            ? (data['sumDebt'] as num).toDouble()
            : double.tryParse('${data['sumDebt']}') ?? 0;
        _sum0 = _n(data['sumDebt0To30']);
        _sum31 = _n(data['sumDebt31To60']);
        _sum61 = _n(data['sumDebt61To90']);
        _sum90 = _n(data['sumDebtOver90']);
        _totalCustomers = (data['totalCustomers'] is num)
            ? (data['totalCustomers'] as num).toInt()
            : int.tryParse('${data['totalCustomers']}') ?? 0;
        _items = (data['items'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không tải báo cáo',
      );
    }
  }

  double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: PosTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PosMobileKiotHeader(title: 'Báo cáo công nợ KH'),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: PosTheme.inputDecoration(label: 'Tìm khách hàng'),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(onPressed: _load, icon: const Icon(Icons.refresh)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                label: Text(tr('Gồm khách nợ 0')),
                selected: _includeZero,
                onSelected: (v) {
                  setState(() => _includeZero = v);
                  _load();
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              decoration: PosTheme.mobileCardDecoration(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('$_totalCustomers khách còn nợ'),
                                style: const TextStyle(color: PosTheme.textSecondary)),
                            PosReportMoneyLabel(
                              _sumDebt,
                              fontSize: 20,
                              maxWidth: 280,
                              align: Alignment.centerLeft,
                              color: const Color(0xFF2B3437),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.account_balance_wallet_outlined,
                          size: 36, color: PosTheme.kiotBlue),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _agingChip('0–30', _sum0, const Color(0xFF166534)),
                      _agingChip('31–60', _sum31, const Color(0xFFCA8A04)),
                      _agingChip('61–90', _sum61, Colors.orange.shade800),
                      _agingChip('>90', _sum90, Colors.red.shade700),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) {
                        final row = _items[i];
                        final debt = _n(row['currentDebt']);
                        final openDebt = _n(row['openOrderDebt']);
                        final d0 = _n(row['debt0To30']);
                        final d31 = _n(row['debt31To60']);
                        final d61 = _n(row['debt61To90']);
                        final d90 = _n(row['debtOver90']);
                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr(row['name']?.toString() ?? '—'),
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                ),
                                if (row['phone'] != null)
                                  Text(
                                    tr(row['phone'].toString()),
                                    style: const TextStyle(
                                        fontSize: 12, color: PosTheme.textSecondary),
                                  ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        tr('Tổng nợ: ${posReportMoney(debt)}'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF2B3437),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    if (openDebt > 0)
                                      Text(tr('Nợ đơn mở: ${_moneyFmt.format(openDebt)}'),
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                  ],
                                ),
                                if (d0 + d31 + d61 + d90 > 0) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      if (d0 > 0) _agingChip('0–30', d0, const Color(0xFF166534)),
                                      if (d31 > 0) _agingChip('31–60', d31, const Color(0xFFCA8A04)),
                                      if (d61 > 0) _agingChip('61–90', d61, Colors.orange.shade800),
                                      if (d90 > 0) _agingChip('>90', d90, Colors.red.shade700),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _agingChip(String label, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: ${posReportMoney(amount)}',
        style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
