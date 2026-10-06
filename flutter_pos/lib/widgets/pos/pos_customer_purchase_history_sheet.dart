import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/api_datetime.dart';
import 'pos_theme.dart';

/// Lịch sử mua của một khách — mở từ màn bán hàng (gõ SĐT → «Lịch sử mua») để tra lại khách đã mua gì,
/// giá bao nhiêu. Hai cách xem: theo đơn (ngày, từng món, SL × đơn giá) và theo mặt hàng (giá gần nhất,
/// thấp / cao nhất, số lần mua). [onAddProduct] (tùy chọn) = thêm lại món vào đơn đang bán.
Future<void> showPosCustomerPurchaseHistory(
  BuildContext context, {
  required String customerId,
  required String customerName,
  String? phone,
  Future<void> Function(String productId)? onAddProduct,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: SboxColors.slate50,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: _HistorySheet(
        customerId: customerId,
        customerName: customerName,
        phone: phone,
        onAddProduct: onAddProduct,
      ),
    ),
  );
}

class _HistorySheet extends StatefulWidget {
  const _HistorySheet({required this.customerId, required this.customerName, this.phone, this.onAddProduct});

  final String customerId;
  final String customerName;
  final String? phone;
  final Future<void> Function(String productId)? onAddProduct;

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet> {
  final _api = ApiService();
  final _money = NumberFormat('#,##0', 'vi_VN');
  final _qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
  final _search = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  String? _error;
  int _tab = 0; // 0 = theo đơn, 1 = theo mặt hàng
  int _days = 365;
  Map<String, dynamic>? _data;
  final Set<String> _adding = {};
  /// Số lần đã thêm vào đơn trong lần mở này — hiện ngay trên nút (thông báo nổi bị bảng che).
  final Map<String, int> _added = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getPosCustomerPurchaseHistory(widget.customerId, search: _search.text, days: _days);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true && res['data'] is Map) {
        _data = Map<String, dynamic>.from(res['data'] as Map);
      } else {
        _error = res['message']?.toString() ?? 'Không tải được lịch sử mua';
      }
    });
  }

  double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  String _m(dynamic v) => '${_money.format(_n(v))}đ';
  String _date(dynamic v, {bool time = true}) {
    final d = v == null ? null : parseApiUtcDateTime(v.toString());
    if (d == null) return '—';
    return DateFormat(time ? 'dd/MM/yyyy HH:mm' : 'dd/MM/yyyy').format(d.toLocal());
  }

  List<Map<String, dynamic>> _list(String key) =>
      ((_data?[key] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

  Future<void> _add(String productId, String name) async {
    final add = widget.onAddProduct;
    if (add == null || _adding.contains(productId)) return;
    setState(() => _adding.add(productId));
    await add(productId);
    if (!mounted) return;
    setState(() {
      _adding.remove(productId);
      _added[productId] = (_added[productId] ?? 0) + 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _data?['customer'] is Map ? Map<String, dynamic>.from(_data!['customer'] as Map) : null;
    final debt = _n(c?['currentDebt']);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Đầu bảng: khách + tổng mua + công nợ.
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.history, color: PosTheme.kiotBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Lịch sử mua hàng'), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                Text(tr(widget.customerName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ]),
            ),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            if ((widget.phone ?? c?['phone'] ?? '').toString().isNotEmpty)
              _chip(Icons.call_outlined, (widget.phone ?? c?['phone']).toString()),
            _chip(Icons.receipt_long_outlined, '${_data?['orderCount'] ?? 0} đơn · ${_m(_data?['totalAmount'])}'),
            _chip(Icons.savings_outlined, 'Tổng mua ${_m(c?['totalPurchase'])}'),
            if (debt > 0) _chip(Icons.warning_amber_rounded, 'Đang nợ ${_m(debt)}', color: SboxColors.danger),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _search,
                  onChanged: (_) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 400), _load);
                  },
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: tr('Tìm món / mã đơn…'),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    contentPadding: EdgeInsets.zero,
                    filled: true,
                    fillColor: SboxColors.slate50,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: SboxColors.slate200)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: SboxColors.slate200)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<int>(
              tooltip: tr('Khoảng thời gian'),
              initialValue: _days,
              onSelected: (v) {
                setState(() => _days = v);
                _load();
              },
              itemBuilder: (_) => [
                for (final (d, label) in const [(30, '30 ngày'), (90, '3 tháng'), (180, '6 tháng'), (365, '1 năm'), (1095, '3 năm')])
                  PopupMenuItem(value: d, child: Text(tr(label))),
              ],
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: SboxColors.slate200),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined, size: 16, color: SboxColors.slate500),
                  const SizedBox(width: 6),
                  Text(tr(switch (_days) { 30 => '30 ngày', 90 => '3 tháng', 180 => '6 tháng', 1095 => '3 năm', _ => '1 năm' }),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const Icon(Icons.expand_more, size: 18),
                ]),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 0, icon: const Icon(Icons.receipt_long_outlined, size: 18), label: Text(tr('Theo đơn'))),
              ButtonSegment(value: 1, icon: const Icon(Icons.inventory_2_outlined, size: 18), label: Text(tr('Theo mặt hàng'))),
            ],
            selected: {_tab},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _tab = s.first),
          ),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(tr(_error!)))
                : _tab == 0
                    ? _ordersView()
                    : _productsView(),
      ),
    ]);
  }

  Widget _chip(IconData icon, String text, {Color? color}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: (color ?? PosTheme.kiotBlue).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color ?? PosTheme.kiotBlue),
          const SizedBox(width: 4),
          Text(tr(text), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color ?? SboxColors.slate700)),
        ]),
      );

  Widget _empty(String text) => ListView(children: [
        const SizedBox(height: 60),
        const Icon(Icons.shopping_bag_outlined, size: 48, color: SboxColors.slate300),
        const SizedBox(height: 10),
        Text(tr(text), textAlign: TextAlign.center, style: const TextStyle(color: SboxColors.slate500)),
      ]);

  Widget _ordersView() {
    final orders = _list('orders');
    if (orders.isEmpty) return _empty('Khách chưa mua đơn nào trong khoảng thời gian này');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final o = orders[i];
        final lines = ((o['lines'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        final disc = _n(o['discount']);
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SboxColors.slate200),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_date(o['date']), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(tr([o['orderNo'], if ((o['soldBy'] ?? '').toString().isNotEmpty) 'NV: ${o['soldBy']}']
                          .join(' · ')),
                      style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(_m(o['total']),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: PosTheme.kiotBlue)),
                if ((o['paymentMethod'] ?? '').toString().isNotEmpty)
                  Text(tr('${o['paymentMethod']}'), style: const TextStyle(fontSize: 11, color: SboxColors.slate500)),
              ]),
            ]),
            const Divider(height: 14),
            for (final l in lines) _lineRow(l),
            if (disc > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tr('Giảm giá đơn: −${_m(disc)}'),
                    textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: SboxColors.danger)),
              ),
          ]),
        );
      },
    );
  }

  Widget _lineRow(Map<String, dynamic> l) {
    final qty = _n(l['qty']);
    final returned = _n(l['returnedQty']);
    final lineDisc = _n(l['discountAmount']);
    final unit = (l['unitName'] ?? '').toString();
    final pid = (l['productId'] ?? '').toString();
    final name = (l['productName'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(name), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            Text(
              tr('${_qtyFmt.format(qty)}${unit.isEmpty ? '' : ' $unit'} × ${_m(l['unitPrice'])}'
                  '${lineDisc > 0 ? ' · giảm ${_m(lineDisc)}' : ''}'),
              style: const TextStyle(fontSize: 12, color: SboxColors.slate600),
            ),
            if (returned > 0)
              Text(tr('Đã trả lại ${_qtyFmt.format(returned)}${unit.isEmpty ? '' : ' $unit'}'),
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFFC2410C), fontWeight: FontWeight.w600)),
            if ((l['lineNote'] ?? '').toString().trim().isNotEmpty)
              Text(tr('↳ ${l['lineNote']}'), style: const TextStyle(fontSize: 11.5, color: PosTheme.kiotBlue)),
          ]),
        ),
        const SizedBox(width: 8),
        Text(_m(l['lineTotal']), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        if (widget.onAddProduct != null && pid.isNotEmpty)
          SizedBox(
            width: 36,
            height: 28,
            child: IconButton(
              tooltip: tr('Thêm lại vào đơn'),
              padding: EdgeInsets.zero,
              onPressed: _adding.contains(pid) ? null : () => _add(pid, name),
              icon: Icon(_added.containsKey(pid) ? Icons.check_circle : Icons.add_shopping_cart,
                  size: 18, color: _added.containsKey(pid) ? SboxColors.success : PosTheme.kiotBlue),
            ),
          ),
      ]),
    );
  }

  Widget _productsView() {
    final products = _list('products');
    if (products.isEmpty) return _empty('Chưa có mặt hàng nào');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: products.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final p = products[i];
        final last = _n(p['lastPrice']);
        final min = _n(p['minPrice']);
        final max = _n(p['maxPrice']);
        final cur = p['currentPrice'] == null ? null : _n(p['currentPrice']);
        final unit = (p['unitName'] ?? '').toString();
        final pid = (p['productId'] ?? '').toString();
        final name = (p['productName'] ?? '').toString();
        final changed = cur != null && (cur - last).abs() >= 1;
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SboxColors.slate200),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(name), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  tr('Mua ${p['timesBought']} lần · ${_qtyFmt.format(_n(p['totalQty']))}${unit.isEmpty ? '' : ' $unit'}'
                      ' · gần nhất ${_date(p['lastDate'], time: false)}'),
                  style: const TextStyle(fontSize: 12, color: SboxColors.slate600),
                ),
                if (min != max)
                  Text(tr('Giá đã bán: ${_m(min)} – ${_m(max)}'),
                      style: const TextStyle(fontSize: 12, color: SboxColors.slate600)),
                if (changed)
                  Text(tr('Giá hiện tại: ${_m(cur)} (${cur > last ? 'tăng' : 'giảm'} ${_m((cur - last).abs())})'),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cur > last ? const Color(0xFFC2410C) : SboxColors.success)),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(tr('Giá lần trước'), style: const TextStyle(fontSize: 11, color: SboxColors.slate500)),
              Text(_m(last), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: PosTheme.kiotBlue)),
              if (widget.onAddProduct != null && pid.isNotEmpty)
                TextButton.icon(
                  onPressed: _adding.contains(pid) ? null : () => _add(pid, name),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
                  icon: Icon(_added.containsKey(pid) ? Icons.check_circle : Icons.add_shopping_cart,
                      size: 16, color: _added.containsKey(pid) ? SboxColors.success : null),
                  label: Text(tr(_added.containsKey(pid) ? 'Đã thêm (${_added[pid]})' : 'Thêm vào đơn'),
                      style: TextStyle(fontSize: 12, color: _added.containsKey(pid) ? SboxColors.success : null)),
                ),
            ]),
          ]),
        );
      },
    );
  }
}
