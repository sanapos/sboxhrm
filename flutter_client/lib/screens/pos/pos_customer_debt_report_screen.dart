import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_mobile_widgets.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

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
  int _totalCustomers = 0;
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
    );
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final data = res['data'] as Map<String, dynamic>;
      setState(() {
        _sumDebt = (data['sumDebt'] is num)
            ? (data['sumDebt'] as num).toDouble()
            : double.tryParse('${data['sumDebt']}') ?? 0;
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
            padding: const EdgeInsets.all(12),
            child: Container(
              decoration: PosTheme.mobileCardDecoration(),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('$_totalCustomers khách còn nợ'),
                            style: const TextStyle(color: PosTheme.textSecondary)),
                        Text(tr('${_moneyFmt.format(_sumDebt)} đ'),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.account_balance_wallet_outlined,
                      size: 36, color: PosTheme.kiotBlue),
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
                                      child: Text(tr('Tổng nợ: ${_moneyFmt.format(debt)} đ'),
                                        style: const TextStyle(
                                          color: Colors.red,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    if (openDebt > 0)
                                      Text(tr('Nợ đơn mở: ${_moneyFmt.format(openDebt)}'),
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                  ],
                                ),
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
}
