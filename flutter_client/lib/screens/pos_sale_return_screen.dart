import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/pos_product.dart';
import '../models/pos_sale_order.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_pick_sale_order_dialog.dart';
import '../widgets/pos/pos_product_image.dart';
import '../widgets/pos/pos_theme.dart';

const _kiotBlue = PosTheme.kiotBlue;

/// Màn trả hàng POS kiểu KiotViet — chọn hóa đơn, nhập SL trả từng dòng.
class PosSaleReturnScreen extends StatefulWidget {
  const PosSaleReturnScreen({super.key, this.orderId});

  final String? orderId;

  @override
  State<PosSaleReturnScreen> createState() => _PosSaleReturnScreenState();
}

class _PosSaleReturnScreenState extends State<PosSaleReturnScreen> {
  final _api = ApiService();
  final _noteCtrl = TextEditingController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'vi_VN');

  PosSaleOrder? _order;
  final Map<String, PosProduct> _productMeta = {};
  bool _loading = true;
  bool _submitting = false;
  final List<_ReturnLine> _lines = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    for (final l in _lines) {
      l.qtyCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (widget.orderId != null) {
      await _loadOrder(widget.orderId!);
    } else {
      await _pickOrder();
    }
  }

  Future<void> _pickOrder() async {
    final picked = await showPosPickSaleOrderDialog(context);
    if (!mounted) return;
    if (picked == null) {
      if (_order == null) Navigator.pop(context);
      return;
    }
    await _loadOrder(picked.id);
  }

  Future<void> _loadProductMeta(PosSaleOrder order) async {
    _productMeta.clear();
    final ids = order.lines.map((l) => l.productId).toSet();
    for (final id in ids) {
      final res = await _api.getPosProduct(id);
      if (res['isSuccess'] == true && res['data'] is Map) {
        _productMeta[id] =
            PosProduct.fromJson(res['data'] as Map<String, dynamic>);
      }
    }
  }

  Future<void> _loadOrder(String id) async {
    setState(() => _loading = true);
    final res = await _api.getPosSale(id);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final order = PosSaleOrder.fromJson(res['data'] as Map<String, dynamic>);
      for (final l in _lines) {
        l.qtyCtrl.dispose();
      }
      _lines.clear();
      for (final l in order.lines) {
        _lines.add(_ReturnLine(line: l, qtyCtrl: TextEditingController(text: '0')));
      }
      await _loadProductMeta(order);
      if (!mounted) return;
      setState(() {
        _order = order;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
      NotificationOverlayManager().showError(
        title: 'Trả hàng',
        message: res['message']?.toString() ?? 'Không tải được hóa đơn',
      );
      if (_order == null && mounted) Navigator.pop(context);
    }
  }

  double _returnQty(_ReturnLine rl) =>
      double.tryParse(rl.qtyCtrl.text.replaceAll(',', '.')) ?? 0;

  double get _returnTotal {
    var sum = 0.0;
    for (final rl in _lines) {
      final q = _returnQty(rl);
      if (q > 0) sum += q * rl.line.unitPrice;
    }
    return sum;
  }

  void _adjustReturnQty(_ReturnLine rl, double delta) {
    final max = rl.line.qty;
    var next = _returnQty(rl) + delta;
    if (next < 0) next = 0;
    if (next > max) next = max;
    rl.qtyCtrl.text = next == next.roundToDouble()
        ? next.toStringAsFixed(0)
        : next.toStringAsFixed(2);
    setState(() {});
  }

  Future<void> _submit() async {
    final order = _order;
    if (order == null) return;

    final bodyLines = <Map<String, dynamic>>[];
    for (final rl in _lines) {
      final qty = _returnQty(rl);
      if (qty <= 0) continue;
      bodyLines.add({
        'productId': rl.line.productId,
        'qty': qty,
        if (rl.line.variantId != null) 'variantId': rl.line.variantId,
      });
    }
    if (bodyLines.isEmpty) {
      NotificationOverlayManager()
          .showWarning(title: 'Trả hàng', message: 'Chưa nhập số lượng trả');
      return;
    }

    setState(() => _submitting = true);
    final note = _noteCtrl.text.trim();
    final res = await _api.returnPosSale(order.id, {
      'lines': bodyLines,
      if (note.isNotEmpty) 'note': note,
    });
    if (!mounted) return;
    setState(() => _submitting = false);

    if (res['isSuccess'] == true) {
      final refund = res['data'] is Map
          ? (res['data'] as Map)['refundTotal']
          : null;
      NotificationOverlayManager().showSuccess(
        title: 'Trả hàng thành công',
        message: refund != null
            ? 'Đã trả ${_moneyFmt.format(_num(refund))} · ${order.orderNo}'
            : 'Đã ghi nhận trả hàng · ${order.orderNo}',
      );
      await _loadOrder(order.id);
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi trả hàng',
        message: res['message']?.toString() ?? 'Không trả được',
      );
    }
  }

  double _num(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    final canReturn = perm.canEdit('PosProducts') || perm.canCreate('PosSell');

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: _kiotBlue))
                  : _order == null
                      ? _buildEmptyPick()
                      : _buildBody(),
            ),
            if (_order != null) _buildFooter(canReturn),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Material(
      color: _kiotBlue,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (_order != null)
                      _tabChip('Trả hàng · ${_order!.orderNo}', active: true),
                  ],
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _pickOrder,
              icon: const Icon(Icons.receipt_long, color: Colors.white, size: 18),
              label: const Text('Chọn hóa đơn', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabChip(String label, {required bool active}) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? Colors.white : Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: active ? _kiotBlue : Colors.white,
        ),
      ),
    );
  }

  Widget _buildEmptyPick() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.receipt_long_outlined, size: 48, color: PosTheme.textSecondary),
          const SizedBox(height: 12),
          const Text('Chọn hóa đơn cần trả hàng'),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _kiotBlue),
            onPressed: _pickOrder,
            icon: const Icon(Icons.search),
            label: const Text('Chọn hóa đơn trả hàng'),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final o = _order!;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: InkWell(
                  onTap: _pickOrder,
                  child: Row(
                    children: [
                      const Icon(Icons.search, size: 18, color: PosTheme.textSecondary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Trả hàng / ${o.orderNo} — ${o.soldBy ?? o.createdBy ?? ''}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: _kiotBlue,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: PosTheme.textSecondary),
                    ],
                  ),
                ),
              ),
              _buildTableHeader(),
              Expanded(
                child: _lines.isEmpty
                    ? const Center(child: Text('Đơn không có dòng hàng'))
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: _lines.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: PosTheme.border),
                        itemBuilder: (_, i) => _lineRow(_lines[i], i),
                      ),
              ),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _noteCtrl,
                  decoration: const InputDecoration(
                    hintText: 'Ghi chú đơn hàng',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: 300, child: _buildSidebar(o)),
      ],
    );
  }

  Widget _buildTableHeader() {
    return Container(
      color: const Color(0xFFFAFBFC),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: const Row(
        children: [
          SizedBox(width: 28, child: Text('STT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
          SizedBox(width: 36),
          SizedBox(width: 44),
          Expanded(child: Text('Tên hàng', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
          SizedBox(width: 56, child: Text('ĐVT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
          SizedBox(width: 100, child: Text('SL trả', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
          SizedBox(width: 72, child: Text('Giá', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
          SizedBox(width: 80, child: Text('T.Tiền', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _lineRow(_ReturnLine rl, int index) {
    final l = rl.line;
    final meta = _productMeta[l.productId];
    final ret = _returnQty(rl);
    final lineTotal = ret * l.unitPrice;
    final code = meta?.productCode ?? meta?.barcode ?? '';

    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 28,
              child: Text('${index + 1}', style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
            ),
            SizedBox(
              width: 36,
              child: IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                onPressed: () {
                  rl.qtyCtrl.text = '0';
                  setState(() {});
                },
              ),
            ),
            PosProductImage(
              productId: l.productId,
              imageUrl: meta?.imageUrl,
              size: 40,
              borderRadius: 4,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.productName, maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  if (code.isNotEmpty)
                    Text(code, style: const TextStyle(fontSize: 10, color: PosTheme.textSecondary)),
                ],
              ),
            ),
            SizedBox(
              width: 56,
              child: Text(l.unitName ?? 'cái', style: const TextStyle(fontSize: 12)),
            ),
            SizedBox(
              width: 100,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    icon: const Icon(Icons.remove, size: 16),
                    onPressed: () => _adjustReturnQty(rl, -1),
                  ),
                  Text(
                    '${_qtyFmt.format(ret)} / ${_qtyFmt.format(l.qty)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    icon: const Icon(Icons.add, size: 16, color: _kiotBlue),
                    onPressed: () => _adjustReturnQty(rl, 1),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 72,
              child: Text(
                _moneyFmt.format(l.unitPrice),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            SizedBox(
              width: 80,
              child: Text(
                _moneyFmt.format(lineTotal),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(PosSaleOrder o) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(o.soldBy ?? o.createdBy ?? 'sbox',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          if (o.createdAt != null)
            Text(_dateFmt.format(o.createdAt!.toLocal()),
                style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
          const SizedBox(height: 8),
          Text('Khách: ${o.customerName ?? 'Khách lẻ'}', style: const TextStyle(fontSize: 13)),
          const Divider(height: 24),
          InkWell(
            onTap: _pickOrder,
            child: Text(
              'Trả hàng / ${o.orderNo}',
              style: const TextStyle(color: _kiotBlue, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 16),
          _sumRow('Tổng giá gốc hàng mua', _moneyFmt.format(o.subTotal)),
          _sumRow('Tổng tiền hàng trả', _moneyFmt.format(_returnTotal)),
          if (o.returnedAmount > 0)
            _sumRow('Đã trả trước', _moneyFmt.format(o.returnedAmount)),
          const Spacer(),
          _sumRow('Cần trả khách', _moneyFmt.format(_returnTotal), bold: true, blue: true),
        ],
      ),
    );
  }

  Widget _sumRow(String label, String value, {bool bold = false, bool blue = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w600 : null)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: bold ? 16 : 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: blue ? _kiotBlue : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(bool canReturn) {
    return Material(
      color: Colors.white,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: PosTheme.border))),
        child: Row(
          children: [
            const Spacer(),
            FilledButton(
              onPressed: !canReturn || _submitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: _kiotBlue,
                minimumSize: const Size(180, 48),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('TRẢ HÀNG', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReturnLine {
  _ReturnLine({required this.line, required this.qtyCtrl});
  final PosSaleOrderLine line;
  final TextEditingController qtyCtrl;
}
