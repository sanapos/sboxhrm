import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Lịch sử hủy món / hủy đơn / trả hàng — lọc thao tác & trước/sau tạm tính.
class PosCancelReturnHistoryScreen extends StatefulWidget {
  const PosCancelReturnHistoryScreen({super.key});

  @override
  State<PosCancelReturnHistoryScreen> createState() =>
      _PosCancelReturnHistoryScreenState();
}

enum _ActionFilter { all, kitchenVoid, saleCancel, saleReturn }

enum _BillPhaseFilter { all, before, after }

class _PosCancelReturnHistoryScreenState
    extends State<PosCancelReturnHistoryScreen> {
  final _api = ApiService();
  final _fmt = DateFormat('dd/MM/yyyy HH:mm:ss');
  final _dayFmt = DateFormat('dd/MM/yyyy');
  final _money = NumberFormat('#,##0', 'vi_VN');
  final _qty = NumberFormat('#,##0.###', 'vi_VN');
  final _actorCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];

  DateTime _from = DateTime.now().subtract(const Duration(days: 7));
  DateTime _to = DateTime.now();
  _ActionFilter _action = _ActionFilter.all;
  _BillPhaseFilter _phase = _BillPhaseFilter.all;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _actorCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  String? get _actionTypeParam => switch (_action) {
        _ActionFilter.kitchenVoid => 'KitchenVoid',
        _ActionFilter.saleCancel => 'SaleCancel',
        _ActionFilter.saleReturn => 'SaleReturn',
        _ActionFilter.all => null,
      };

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final fromUtc = DateTime(_from.year, _from.month, _from.day).toUtc();
    final toUtc = DateTime(_to.year, _to.month, _to.day, 23, 59, 59).toUtc();
    final res = await _api.getPosCancelReturnAudits(
      from: fromUtc,
      to: toUtc,
      actionType: _actionTypeParam,
      afterBillOnly: _phase == _BillPhaseFilter.after ? true : null,
      beforeBillOnly: _phase == _BillPhaseFilter.before ? true : null,
      actor: _actorCtrl.text.trim().isEmpty ? null : _actorCtrl.text.trim(),
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      take: 400,
    );
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? 'Không tải được lịch sử';
      });
      return;
    }
    final data = res['data'] as Map;
    final raw = data['items'] ?? data['Items'];
    final list = <Map<String, dynamic>>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) list.add(Map<String, dynamic>.from(e));
      }
    }
    setState(() {
      _loading = false;
      _items = list;
    });
  }

  Future<void> _pickDay({required bool isFrom}) async {
    final initial = isFrom ? _from : _to;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d == null) return;
    setState(() {
      if (isFrom) {
        _from = d;
      } else {
        _to = d;
      }
    });
    await _load();
  }

  String _actionLabel(String? t) => switch (t) {
        'KitchenVoid' => 'Hủy món bếp',
        'SaleCancel' => 'Hủy đơn',
        'SaleReturn' => 'Trả hàng',
        _ => t ?? '—',
      };

  Color _actionColor(String? t) => switch (t) {
        'KitchenVoid' => const Color(0xFFB45309),
        'SaleCancel' => const Color(0xFFDC2626),
        'SaleReturn' => const Color(0xFF2563EB),
        _ => PosTheme.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Lịch sử hủy / trả')),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        actions: [
          IconButton(
            tooltip: tr('Tải lại'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDay(isFrom: true),
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(tr('Từ ${_dayFmt.format(_from)}')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickDay(isFrom: false),
                          icon: const Icon(Icons.event, size: 16),
                          label: Text(tr('Đến ${_dayFmt.format(_to)}')),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<_ActionFilter>(
                    value: _action,
                    decoration: InputDecoration(
                      labelText: tr('Loại thao tác'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                          value: _ActionFilter.all, child: Text(tr('Tất cả'))),
                      DropdownMenuItem(
                          value: _ActionFilter.kitchenVoid,
                          child: Text(tr('Hủy món bếp'))),
                      DropdownMenuItem(
                          value: _ActionFilter.saleCancel,
                          child: Text(tr('Hủy đơn'))),
                      DropdownMenuItem(
                          value: _ActionFilter.saleReturn,
                          child: Text(tr('Trả hàng'))),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _action = v);
                      unawaited(_load());
                    },
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<_BillPhaseFilter>(
                    value: _phase,
                    decoration: InputDecoration(
                      labelText: tr('Trước / sau tạm tính'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                          value: _BillPhaseFilter.all,
                          child: Text(tr('Tất cả'))),
                      DropdownMenuItem(
                          value: _BillPhaseFilter.before,
                          child: Text(tr('Trước tạm tính'))),
                      DropdownMenuItem(
                          value: _BillPhaseFilter.after,
                          child: Text(tr('Sau tạm tính'))),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _phase = v);
                      unawaited(_load());
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _actorCtrl,
                          decoration: InputDecoration(
                            labelText: tr('Người hủy'),
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _load(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            labelText: tr('Mã đơn / bàn / lý do'),
                            isDense: true,
                            border: const OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _load(),
                        ),
                      ),
                      IconButton(
                        onPressed: _load,
                        icon: const Icon(Icons.search),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(tr(_error!)))
                    : _items.isEmpty
                        ? Center(child: Text(tr('Chưa có bản ghi')))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                            itemCount: _items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, i) => _tile(_items[i]),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _tile(Map<String, dynamic> m) {
    final action = m['actionType']?.toString();
    final after = m['afterProvisionalBill'] == true;
    final occurred = DateTime.tryParse(m['occurredAt']?.toString() ?? '');
    final amount = (m['amount'] as num?)?.toDouble() ?? 0;
    final qty = (m['qty'] as num?)?.toDouble() ?? 0;
    final product = m['productName']?.toString() ?? '';
    final reason = m['reason']?.toString() ?? '';
    final note = m['detailNote']?.toString() ?? '';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _actionColor(action).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tr(_actionLabel(action)),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _actionColor(action),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: after
                        ? const Color(0xFFFFEDD5)
                        : const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tr(after ? 'Sau tạm tính' : 'Trước tạm tính'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: after
                          ? const Color(0xFFC2410C)
                          : const Color(0xFF047857),
                    ),
                  ),
                ),
                const Spacer(),
                if (amount > 0)
                  Text(
                    tr('${_money.format(amount)}đ'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              tr([
                if ((m['orderNo'] ?? '').toString().isNotEmpty) m['orderNo'],
                if ((m['resourceName'] ?? '').toString().isNotEmpty)
                  m['resourceName'],
              ].whereType<Object>().join(' · ')),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            if (product.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                tr(qty > 0 ? '$product × ${_qty.format(qty)}' : product),
                style: const TextStyle(
                    fontSize: 13, color: PosTheme.textSecondary),
              ),
            ],
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(tr('Lý do: $reason'),
                  style: const TextStyle(fontSize: 13)),
            ],
            if (note.isNotEmpty)
              Text(tr('Ghi chú: $note'),
                  style: const TextStyle(
                      fontSize: 12, color: PosTheme.textSecondary)),
            const SizedBox(height: 6),
            Text(
              tr([
                if (occurred != null) _fmt.format(occurred.toLocal()),
                if ((m['actor'] ?? '').toString().isNotEmpty) m['actor'],
                if ((m['deviceName'] ?? '').toString().isNotEmpty)
                  m['deviceName'],
              ].whereType<Object>().join(' · ')),
              style: const TextStyle(
                  fontSize: 11, color: PosTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
