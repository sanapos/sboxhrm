import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_sale_order.dart';
import '../../services/api_service.dart';
import '../../utils/pos_kiot_time_range.dart';
import 'pos_theme.dart';

const _kiotBlue = PosTheme.kiotBlue;

/// Dialog chọn hóa đơn trả hàng kiểu KiotViet.
Future<PosSaleOrder?> showPosPickSaleOrderDialog(BuildContext context) async {
  return showDialog<PosSaleOrder>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _PosPickSaleOrderDialog(),
  );
}

class _PosPickSaleOrderDialog extends StatefulWidget {
  const _PosPickSaleOrderDialog();

  @override
  State<_PosPickSaleOrderDialog> createState() => _PosPickSaleOrderDialogState();
}

class _PosPickSaleOrderDialogState extends State<_PosPickSaleOrderDialog> {
  final _api = ApiService();
  final _orderNoCtrl = TextEditingController();
  final _customerCtrl = TextEditingController();
  final _productCodeCtrl = TextEditingController();
  final _productNameCtrl = TextEditingController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'vi_VN');

  DateTime? _from;
  DateTime? _to;
  bool _loading = false;
  List<PosSaleOrder> _items = [];
  int _total = 0;
  int _page = 1;
  static const _pageSize = 7;

  @override
  void initState() {
    super.initState();
    final range = resolvePosKiotTimePreset(PosKiotTimePreset.thisMonth);
    _from = range.$1;
    _to = range.$2;
    _load();
  }

  @override
  void dispose() {
    _orderNoCtrl.dispose();
    _customerCtrl.dispose();
    _productCodeCtrl.dispose();
    _productNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({int page = 1}) async {
    setState(() {
      _loading = true;
      _page = page;
    });
    final search = [
      _orderNoCtrl.text.trim(),
      _productCodeCtrl.text.trim(),
      _productNameCtrl.text.trim(),
    ].where((s) => s.isNotEmpty).join(' ');

    final res = await _api.getPosSales(
      search: search.isEmpty ? null : search,
      customerName: _customerCtrl.text.trim().isEmpty ? null : _customerCtrl.text.trim(),
      statuses: const ['Completed'],
      from: _from,
      to: _to,
      page: page,
      pageSize: _pageSize,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final data = res['data'] as Map;
      setState(() {
        _loading = false;
        _total = (data['total'] as num?)?.toInt() ?? 0;
        _items = ((data['items'] as List?) ?? [])
            .map((e) => PosSaleOrder.fromJson(e as Map<String, dynamic>))
            .toList();
      });
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(
        start: _from ?? DateTime(now.year, now.month, 1),
        end: _to ?? now,
      ),
      locale: const Locale('vi', 'VN'),
    );
    if (picked == null) return;
    setState(() {
      _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
      _to = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
    });
    await _load();
  }

  void _select(PosSaleOrder order) => Navigator.pop(context, order);

  @override
  Widget build(BuildContext context) {
    final totalPages = (_total / _pageSize).ceil().clamp(1, 9999);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 960,
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Chọn hóa đơn trả hàng',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: 220,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        border: Border(right: BorderSide(color: PosTheme.border)),
                        color: Color(0xFFFAFBFC),
                      ),
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          const Text('Tìm kiếm', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(height: 8),
                          _filterField(_orderNoCtrl, 'Theo mã hóa đơn'),
                          const SizedBox(height: 6),
                          _filterField(_customerCtrl, 'Theo khách hàng hoặc ĐT'),
                          const SizedBox(height: 6),
                          _filterField(_productCodeCtrl, 'Theo mã hàng'),
                          const SizedBox(height: 6),
                          _filterField(_productNameCtrl, 'Theo tên hàng'),
                          const SizedBox(height: 12),
                          const Text('Thời gian', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _pickDateRange,
                            icon: const Icon(Icons.date_range, size: 16),
                            label: Text(
                              _from != null && _to != null
                                  ? '${DateFormat('dd/MM/yyyy').format(_from!)} – ${DateFormat('dd/MM/yyyy').format(_to!)}'
                                  : 'Chọn khoảng ngày',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: _kiotBlue),
                            onPressed: _loading ? null : () => _load(),
                            child: const Text('Lọc'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(child: _buildTable()),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  if (totalPages > 1)
                    Row(
                      children: [
                        IconButton(
                          onPressed: _page > 1 && !_loading ? () => _load(page: _page - 1) : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text('$_page / $totalPages', style: const TextStyle(fontSize: 13)),
                        IconButton(
                          onPressed: _page < totalPages && !_loading
                              ? () => _load(page: _page + 1)
                              : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  const Spacer(),
                  Text(
                    'Hiển thị ${_items.isEmpty ? 0 : ((_page - 1) * _pageSize + 1)} – '
                    '${(_page - 1) * _pageSize + _items.length} trên tổng số $_total hóa đơn',
                    style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterField(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
      style: const TextStyle(fontSize: 12),
      onSubmitted: (_) => _load(),
    );
  }

  Widget _buildTable() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kiotBlue));
    }
    if (_items.isEmpty) {
      return const Center(child: Text('Không có hóa đơn phù hợp'));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(_kiotBlue),
        headingTextStyle: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
        dataRowMinHeight: 40,
        columns: const [
          DataColumn(label: Text('Mã hóa đơn')),
          DataColumn(label: Text('Thời gian')),
          DataColumn(label: Text('Nhân viên')),
          DataColumn(label: Text('Khách hàng')),
          DataColumn(label: Text('Tổng cộng'), numeric: true),
          DataColumn(label: Text('')),
        ],
        rows: _items.map((o) {
          return DataRow(cells: [
            DataCell(Text(o.orderNo, style: const TextStyle(color: _kiotBlue, fontWeight: FontWeight.w600))),
            DataCell(Text(o.createdAt != null ? _dateFmt.format(o.createdAt!.toLocal()) : '—')),
            DataCell(Text(o.soldBy ?? o.createdBy ?? '—', overflow: TextOverflow.ellipsis)),
            DataCell(Text(o.customerName ?? 'Khách lẻ', overflow: TextOverflow.ellipsis)),
            DataCell(Text(_moneyFmt.format(o.total))),
            DataCell(
              OutlinedButton(
                onPressed: () => _select(o),
                style: OutlinedButton.styleFrom(foregroundColor: _kiotBlue),
                child: const Text('Chọn'),
              ),
            ),
          ]);
        }).toList(),
      ),
    );
  }
}
