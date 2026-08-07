import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_mobile_widgets.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

class PosWarrantyLookupScreen extends StatefulWidget {
  const PosWarrantyLookupScreen({super.key});

  @override
  State<PosWarrantyLookupScreen> createState() => _PosWarrantyLookupScreenState();
}

class _PosWarrantyLookupScreenState extends State<PosWarrantyLookupScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  int _mode = 0;
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _expiring = [];

  static final _dateFmt = DateFormat('dd/MM/yyyy', 'vi_VN');

  @override
  void initState() {
    super.initState();
    _loadExpiring();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExpiring() async {
    final res = await _api.getPosWarrantyExpiring(days: 30);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final data = res['data'] as Map<String, dynamic>;
      final raw = data['items'];
      setState(() {
        _expiring = raw is List
            ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : [];
      });
    }
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) {
      NotificationOverlayManager().showInfo(
        title: 'Tra cứu bảo hành',
        message: tr('Nhập seri, SĐT hoặc mã đơn'),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await _api.lookupPosWarranty(
        serial: _mode == 0 ? q : null,
        phone: _mode == 1 ? q : null,
        orderNo: _mode == 2 ? q : null,
      );
      if (!mounted) return;
      if (res['isSuccess'] != true) {
        NotificationOverlayManager().showError(
          title: 'Lỗi',
          message: res['message']?.toString() ?? 'Tra cứu thất bại',
        );
        return;
      }
      final data = res['data'] as Map<String, dynamic>?;
      final raw = data?['items'];
      setState(() {
        _items = raw is List
            ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
            : [];
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: PosTheme.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PosMobileKiotHeader(title: 'Tra cứu bảo hành'),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 0, label: Text(tr('Seri'))),
                ButtonSegment(value: 1, label: Text(tr('SĐT'))),
                ButtonSegment(value: 2, label: Text(tr('Mã đơn'))),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: PosTheme.inputDecoration(
                      label: _mode == 0
                          ? 'Seri / IMEI'
                          : _mode == 1
                              ? 'Số điện thoại khách'
                              : 'Mã đơn hàng',
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _loading ? null : _search,
                  child: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(tr('Tra')),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
              children: [
                if (_items.isNotEmpty) ...[
                  _sectionTitle('Kết quả tra cứu (${_items.length})'),
                  ..._items.map(_warrantyCard),
                ],
                if (_items.isEmpty && !_loading)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(tr('Nhập thông tin và bấm Tra cứu'),
                        style: TextStyle(color: PosTheme.textSecondary),
                      ),
                    ),
                  ),
                if (_expiring.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _sectionTitle('Sắp hết BH (30 ngày) — ${_expiring.length}'),
                  ..._expiring.map(_warrantyCard),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          tr(text),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      );

  Widget _warrantyCard(Map<String, dynamic> r) {
    final expiry = DateTime.tryParse('${r['warrantyExpiry'] ?? r['WarrantyExpiry'] ?? ''}');
    final saleDate = DateTime.tryParse('${r['saleDate'] ?? r['SaleDate'] ?? ''}');
    final status = (r['status'] ?? r['Status'] ?? 'Active').toString();
    final months = (r['warrantyMonths'] ?? r['WarrantyMonths'] as num?)?.toInt() ?? 0;
    final now = DateTime.now();
    Color? statusColor;
    if (status != 'Active') {
      statusColor = Colors.grey;
    } else if (expiry != null && expiry.isBefore(now)) {
      statusColor = const Color(0xFFEF4444);
    } else if (expiry != null && expiry.difference(now).inDays <= 30) {
      statusColor = const Color(0xFFF59E0B);
    } else {
      statusColor = const Color(0xFF10B981);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: PosTheme.mobileCardDecoration(),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr((r['serialNumber'] ?? r['SerialNumber'] ?? '').toString()),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  tr(_statusLabel(status)),
                  style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (r['imei'] != null || r['Imei'] != null)
            Text(
              tr('IMEI: ${r['imei'] ?? r['Imei']}'),
              style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
            ),
          const SizedBox(height: 4),
          Text(
            tr((r['productName'] ?? r['ProductName'] ?? '').toString()),
            style: const TextStyle(fontSize: 13),
          ),
          Text(
            tr([
              if (months > 0) 'BH $months tháng',
              if (saleDate != null) 'Mua: ${_dateFmt.format(saleDate.toLocal())}',
              if (expiry != null) 'Hết BH: ${_dateFmt.format(expiry.toLocal())}',
            ].join(' · ')),
            style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),
          ),
          Text(
            tr([
              'Đơn: ${r['orderNo'] ?? r['OrderNo'] ?? '—'}',
              if (r['customerName'] ?? r['CustomerName'] != null)
                'KH: ${r['customerName'] ?? r['CustomerName']}',
              if (r['customerPhone'] ?? r['CustomerPhone'] != null)
                'SĐT: ${r['customerPhone'] ?? r['CustomerPhone']}',
            ].join(' · ')),
            style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
        'Active' => 'Còn BH',
        'Returned' => 'Đã trả',
        'Voided' => 'Huỷ',
        'Replaced' => 'Thay thế',
        _ => status,
      };
}
