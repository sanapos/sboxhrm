import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_customer.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_customer_debt_collect_dialog.dart';
import '../../widgets/pos/pos_customer_form_dialog.dart';
import '../../widgets/pos/pos_mobile_widgets.dart';
import '../../widgets/pos/pos_theme.dart';

class PosCustomersScreen extends StatefulWidget {
  const PosCustomersScreen({super.key});

  @override
  State<PosCustomersScreen> createState() => _PosCustomersScreenState();
}

class _PosCustomersScreenState extends State<PosCustomersScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  List<PosCustomer> _items = [];
  bool _loading = true;
  bool _debtOnly = false;
  double _sumDebt = 0;

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
    final res = await _api.getPosCustomers(
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      hasDebt: _debtOnly ? true : null,
      pageSize: 100,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final data = res['data'] as Map<String, dynamic>;
      final raw = data['items'] as List? ?? [];
      setState(() {
        _items = raw
            .map((e) => PosCustomer.fromJson(e as Map<String, dynamic>))
            .toList();
        _sumDebt = (data['sumDebt'] is num)
            ? (data['sumDebt'] as num).toDouble()
            : double.tryParse('${data['sumDebt']}') ?? 0;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không tải được khách hàng',
      );
    }
  }

  Future<void> _openAdd() async {
    final created = await showDialog<dynamic>(
      context: context,
      builder: (_) => const PosCustomerFormDialog(),
    );
    if (created != null) _load();
  }

  Future<void> _openDetail(PosCustomer c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PosCustomerDetailScreen(customer: c, onChanged: _load),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      floatingActionButton: FloatingActionButton(
        onPressed: _openAdd,
        child: const Icon(Icons.person_add),
      ),
      body: ColoredBox(
      color: PosTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PosMobileKiotHeader(title: 'Khách hàng'),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: PosTheme.inputDecoration(label: 'Tìm tên, SĐT, mã KH'),
                    onSubmitted: (_) => _load(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Còn nợ'),
                  selected: _debtOnly,
                  onSelected: (v) {
                    setState(() => _debtOnly = v);
                    _load();
                  },
                ),
                const Spacer(),
                Text(
                  'Tổng nợ: ${_moneyFmt.format(_sumDebt)} đ',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _items.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 80),
                              Center(child: Text('Chưa có khách hàng')),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                            itemCount: _items.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) {
                              final c = _items[i];
                              return Material(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  onTap: () => _openDetail(c),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: PosTheme.kiotBlueLight,
                                          child: Text(
                                            c.name.isNotEmpty
                                                ? c.name[0].toUpperCase()
                                                : 'K',
                                            style: const TextStyle(
                                              color: PosTheme.kiotBlue,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(c.name,
                                                  style: const TextStyle(
                                                      fontWeight: FontWeight.w600)),
                                              if (c.phone != null && c.phone!.isNotEmpty)
                                                Text(c.phone!,
                                                    style: const TextStyle(
                                                        fontSize: 12,
                                                        color: PosTheme.textSecondary)),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            if (c.currentDebt > 0)
                                              Text(
                                                'Nợ ${_moneyFmt.format(c.currentDebt)}',
                                                style: const TextStyle(
                                                  color: Colors.red,
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            if (c.pointBalance > 0)
                                              Text(
                                                '${_moneyFmt.format(c.pointBalance)} điểm',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: PosTheme.kiotBlue,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
      ),
    );
  }
}

class _PosCustomerDetailScreen extends StatefulWidget {
  const _PosCustomerDetailScreen({required this.customer, required this.onChanged});

  final PosCustomer customer;
  final VoidCallback onChanged;

  @override
  State<_PosCustomerDetailScreen> createState() => _PosCustomerDetailScreenState();
}

class _PosCustomerDetailScreenState extends State<_PosCustomerDetailScreen> {
  final _api = ApiService();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  late PosCustomer _customer;
  bool _loading = true;
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    final res = await _api.getPosCustomerHistory(_customer.id);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final data = res['data'] as Map<String, dynamic>;
      setState(() {
        _orders = (data['orders'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _payments = (data['payments'] as List? ?? [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _collectDebt() async {
    final ok = await showPosCustomerDebtCollectDialog(context, customer: _customer);
    if (ok == true) {
      widget.onChanged();
      final res = await _api.getPosCustomers(search: _customer.name, pageSize: 1);
      if (res['isSuccess'] == true && res['data'] is Map) {
        final items = (res['data'] as Map)['items'] as List? ?? [];
        if (items.isNotEmpty) {
          setState(() => _customer = PosCustomer.fromJson(items.first as Map<String, dynamic>));
        }
      }
      _loadHistory();
    }
  }

  Future<void> _edit() async {
    final updated = await showDialog<dynamic>(
      context: context,
      builder: (_) => PosCustomerFormDialog(customer: _customer),
    );
    if (updated is Map<String, dynamic>) {
      setState(() => _customer = PosCustomer.fromJson(updated));
      widget.onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(_customer.name),
        actions: [
          IconButton(onPressed: _edit, icon: const Icon(Icons.edit_outlined)),
        ],
      ),
      floatingActionButton: _customer.currentDebt > 0
          ? FloatingActionButton.extended(
              onPressed: _collectDebt,
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Thu nợ'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Container(
                  decoration: PosTheme.mobileCardDecoration(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoRow('Mã KH', _customer.customerCode),
                      if (_customer.phone != null) _infoRow('SĐT', _customer.phone!),
                      _infoRow('Tổng mua', '${_moneyFmt.format(_customer.totalPurchase)} đ'),
                      _infoRow('Công nợ', '${_moneyFmt.format(_customer.currentDebt)} đ',
                          highlight: _customer.currentDebt > 0),
                      _infoRow('Điểm', _moneyFmt.format(_customer.pointBalance)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text('Lịch sử thu nợ',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 8),
                if (_payments.isEmpty)
                  const Text('Chưa có phiếu thu', style: TextStyle(color: PosTheme.textSecondary))
                else
                  ..._payments.map((p) => _historyTile(
                        title: p['paymentNo']?.toString() ?? '—',
                        subtitle: p['paymentMethod']?.toString() ?? '',
                        amount: (p['amount'] is num) ? (p['amount'] as num).toDouble() : 0,
                        positive: true,
                      )),
                const SizedBox(height: 16),
                const Text('Đơn bán gần đây',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 8),
                if (_orders.isEmpty)
                  const Text('Chưa có đơn', style: TextStyle(color: PosTheme.textSecondary))
                else
                  ..._orders.map((o) {
                    final total = (o['total'] is num) ? (o['total'] as num).toDouble() : 0.0;
                    final paid = (o['paidAmount'] is num) ? (o['paidAmount'] as num).toDouble() : 0.0;
                    return _historyTile(
                      title: o['orderNo']?.toString() ?? '—',
                      subtitle: 'Thanh toán ${ _moneyFmt.format(paid)}/${_moneyFmt.format(total)}',
                      amount: total - paid,
                      positive: false,
                    );
                  }),
              ],
            ),
    );
  }

  Widget _infoRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(color: PosTheme.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
                color: highlight ? Colors.red : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyTile({
    required String title,
    required String subtitle,
    required double amount,
    required bool positive,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: PosTheme.mobileCardDecoration(),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
              ],
            ),
          ),
          Text(
            '${positive ? '+' : ''}${_moneyFmt.format(amount)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: positive ? Colors.green : Colors.orange,
            ),
          ),
        ],
      ),
    );
  }
}
