import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../utils/pos_payment_gateway_listener.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Danh sách đơn chờ / đã xác nhận chuyển khoản (Tingee webhook).
class PosTransferConfirmScreen extends StatefulWidget {
  const PosTransferConfirmScreen({super.key});

  @override
  State<PosTransferConfirmScreen> createState() =>
      _PosTransferConfirmScreenState();
}

class _PosTransferConfirmScreenState extends State<PosTransferConfirmScreen>
    with SingleTickerProviderStateMixin {
  final _api = PosPaymentGatewayApi(ApiService());
  final _money = NumberFormat('#,###', 'vi_VN');
  late TabController _tabs;
  bool _loading = true;
  Map<String, dynamic>? _credits;
  List<Map<String, dynamic>> _waiting = const [];
  List<Map<String, dynamic>> _confirmed = const [];

  void _onPaymentConfirmed(Map<String, dynamic> _) => unawaited(_reload());

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    PosPaymentGatewayListener.instance.addListener(_onPaymentConfirmed);
    unawaited(_reload());
  }

  @override
  void dispose() {
    PosPaymentGatewayListener.instance.removeListener(_onPaymentConfirmed);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final credits = await _api.getCredits();
    final waiting = await _api.listIntents(status: 'Waiting');
    final confirmed = await _api.listIntents(status: 'Confirmed');
    if (!mounted) return;
    setState(() {
      _credits = credits;
      _waiting = waiting;
      _confirmed = confirmed;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final remain = (_credits?['remainingCount'] as num?)?.toInt() ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Xác nhận chuyển khoản')),
        backgroundColor: PosTheme.kiotBlue,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: tr('Chờ CK (${_waiting.length})')),
            Tab(text: tr('Đã xác nhận (${_confirmed.length})')),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Chip(
                label: Text(tr('Còn $remain lượt TB')),
                backgroundColor: remain <= 10
                    ? Colors.orange.shade100
                    : Colors.green.shade100,
              ),
            ),
          ),
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [
                _listPane(_waiting, waiting: true),
                _listPane(_confirmed, waiting: false),
              ],
            ),
    );
  }

  Widget _listPane(List<Map<String, dynamic>> rows, {required bool waiting}) {
    if (rows.isEmpty) {
      return Center(
        child: Text(
          tr(waiting ? 'Không có đơn chờ xác nhận' : 'Chưa có đơn đã xác nhận'),
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final r = rows[i];
          final orderNo = (r['orderNo'] ?? r['externalOrderId'] ?? '').toString();
          final amount = (r['amountExpected'] as num?)?.toDouble() ?? 0;
          final table = (r['tableName'] ?? '').toString();
          final confirmedAt = r['confirmedAt']?.toString();
          return Card(
            child: ListTile(
              title: Text(tr(orderNo.isEmpty ? '—' : orderNo),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(tr([
                if (table.isNotEmpty) table,
                '${_money.format(amount)}đ',
                if (confirmedAt != null && confirmedAt.isNotEmpty)
                  confirmedAt.substring(0, 16),
              ].join(' · '))),
              trailing: waiting
                  ? const Icon(Icons.hourglass_top, color: Colors.orange)
                  : const Icon(Icons.check_circle, color: Colors.green),
            ),
          );
        },
      ),
    );
  }
}
