import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/pos_product.dart';
import '../models/pos_sale_order.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';
import '../utils/pos_sell_stock_patch.dart';
import '../widgets/pos/pos_cancel_return_reason_dialog.dart';
import '../widgets/pos/pos_mobile_widgets.dart';
import '../widgets/pos/pos_pick_sale_order_dialog.dart';
import '../widgets/pos/pos_product_image.dart';
import '../widgets/pos/pos_theme.dart';
import 'main_layout.dart' show ScreenRefreshNotifier;
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

const _kiotBlue = PosTheme.kiotBlue;

/// Trả hàng bán — chọn hóa đơn hoàn thành, nhập SL trả từng dòng.
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
  List<_ReturnHistory> _history = [];
  bool _loading = true;
  bool _submitting = false;
  String _refundPaymentMethod = 'Tiền mặt';
  static const _refundMethods = [
    'Tiền mặt',
    'Chuyển khoản',
    'VietQR',
    'Thẻ',
    'Ví điện tử',
  ];
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
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickOrder() async {
    final picked = await showPosPickSaleOrderDialog(context);
    if (!mounted) return;
    if (picked == null) return;
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

  Future<void> _loadReturnHistory(String orderId) async {
    _history = [];
    final res = await _api.getPosSaleReturns(orderId);
    if (res['isSuccess'] == true && res['data'] is List) {
      _history = (res['data'] as List)
          .map((e) => _ReturnHistory.fromJson(e as Map<String, dynamic>))
          .toList();
    }
  }

  Future<void> _loadOrder(String id) async {
    setState(() => _loading = true);
    final res = await _api.getPosSale(id);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final order = PosSaleOrder.fromJson(res['data'] as Map<String, dynamic>);
      if (order.status != 'Completed') {
        setState(() => _loading = false);
        NotificationOverlayManager().showWarning(
          title: 'Trả hàng',
          message: tr('Chỉ trả hàng trên đơn đã hoàn thành'),
        );
        return;
      }
      for (final l in _lines) {
        l.qtyCtrl.dispose();
      }
      _lines.clear();
      for (final l in order.lines) {
        if (l.returnedQty >= l.qty) continue;
        _lines.add(_ReturnLine(line: l, qtyCtrl: TextEditingController(text: tr('0'))));
      }
      await _loadProductMeta(order);
      await _loadReturnHistory(id);
      if (!mounted) return;
      setState(() {
        _order = order;
        _refundPaymentMethod = order.paymentMethod.trim().isNotEmpty
            ? order.paymentMethod
            : 'Tiền mặt';
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
      NotificationOverlayManager().showError(
        title: 'Trả hàng',
        message: res['message']?.toString() ?? 'Không tải được hóa đơn',
      );
    }
  }

  double _returnQty(_ReturnLine rl) =>
      double.tryParse(rl.qtyCtrl.text.replaceAll(',', '.')) ?? 0;

  double _unitRefund(PosSaleOrderLine l) {
    if (l.qty <= 0) return l.unitPrice;
    if (l.lineTotal > 0) return l.lineTotal / l.qty;
    return l.unitPrice;
  }

  double get _returnTotal {
    var sum = 0.0;
    for (final rl in _lines) {
      final q = _returnQty(rl);
      if (q > 0) sum += q * _unitRefund(rl.line);
    }
    return sum;
  }

  void _setReturnQty(_ReturnLine rl, double value) {
    final max = rl.maxReturnable;
    var next = value;
    if (next < 0) next = 0;
    if (next > max) next = max;
    rl.qtyCtrl.text = next == next.roundToDouble()
        ? next.toStringAsFixed(0)
        : next.toStringAsFixed(2);
    setState(() {});
  }

  void _adjustReturnQty(_ReturnLine rl, double delta) {
    _setReturnQty(rl, _returnQty(rl) + delta);
  }

  Future<void> _voidReturn(String returnNo) async {
    final order = _order;
    if (order == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Hủy phiếu trả hàng')),
        content: Text(tr('Hủy phiếu $returnNo?\nTrừ lại kho, hoàn tác tiền trên đơn ${order.orderNo}.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Không'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(tr('Hủy trả')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _submitting = true);
    final res = await _api.cancelPosSaleReturn(order.id, returnNo);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (res['isSuccess'] == true && res['data'] is Map) {
      final updated =
          PosSaleOrder.fromJson(res['data'] as Map<String, dynamic>);
      for (final l in _lines) {
        l.qtyCtrl.dispose();
      }
      _lines.clear();
      for (final l in updated.lines) {
        if (l.returnedQty >= l.qty) continue;
        _lines.add(
            _ReturnLine(line: l, qtyCtrl: TextEditingController(text: tr('0'))));
      }
      await _loadReturnHistory(order.id);
      setState(() => _order = updated);
      ScreenRefreshNotifier.refreshPosAfterStockChange();
      NotificationOverlayManager().showSuccess(
        title: 'Đã hủy trả hàng',
        message: '$returnNo · ${updated.orderNo}',
      );
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không hủy được phiếu trả',
      );
    }
  }

  Future<void> _submit() async {
    final order = _order;
    if (order == null) return;

    final bodyLines = <Map<String, dynamic>>[];
    for (final rl in _lines) {
      final qty = _returnQty(rl);
      if (qty <= 0) continue;
      if (qty > rl.maxReturnable) {
        NotificationOverlayManager().showWarning(
          title: 'Trả hàng',
          message: tr('Vượt SL còn lại: ${rl.line.productName}'),
        );
        return;
      }
      bodyLines.add({
        'productId': rl.line.productId,
        'qty': qty,
        if (rl.line.variantId != null) 'variantId': rl.line.variantId,
      });
    }
    if (bodyLines.isEmpty) {
      NotificationOverlayManager()
          .showWarning(title: 'Trả hàng', message: tr('Chưa nhập số lượng trả'));
      return;
    }

    final reasonCfg = await fetchCancelReturnReasonConfig(_api);
    if (!mounted) return;
    final reasonResult = await showPosCancelReturnReasonDialog(
      context,
      config: reasonCfg,
      title: 'Lý do trả hàng',
    );
    if (reasonResult == null || !mounted) return;

    setState(() => _submitting = true);
    final note = _noteCtrl.text.trim();
    final res = await _api.returnPosSale(order.id, {
      'lines': bodyLines,
      if (note.isNotEmpty) 'note': note,
      'refundPaymentMethod': _refundPaymentMethod,
      if (reasonResult.reason.isNotEmpty) 'reason': reasonResult.reason,
      if ((reasonResult.detailNote ?? '').isNotEmpty)
        'detailNote': reasonResult.detailNote,
    });
    if (!mounted) return;
    setState(() => _submitting = false);

    if (res['isSuccess'] == true) {
      final refund = res['data'] is Map
          ? (res['data'] as Map)['refundTotal']
          : null;
      final stockLines = bodyLines
          .map(
            (line) => PosSellStockLineDelta(
              productId: line['productId']?.toString() ?? '',
              variantId: line['variantId']?.toString(),
              qty: _num(line['qty']),
              addBack: true,
            ),
          )
          .where((l) => l.productId.isNotEmpty && l.qty > 0)
          .toList();
      NotificationOverlayManager().showSuccess(
        title: 'Trả hàng thành công',
        message: refund != null
            ? 'Hoàn ${_moneyFmt.format(_num(refund))} · $_refundPaymentMethod'
            : 'Đã ghi nhận trả hàng · ${order.orderNo}',
      );
      ScreenRefreshNotifier.refreshPosAfterStockChange(sellStockLines: stockLines);
      Navigator.of(context).pop(true);
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

  bool get _mobile => posUseMobileList(context);

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    final canReturn = perm.canEdit('PosSell') || perm.canEdit('PosProducts');

    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr(_order != null ? 'Trả hàng · ${_order!.orderNo}' : 'Trả hàng bán')),
        backgroundColor: _kiotBlue,
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: _pickOrder,
            icon: const Icon(Icons.receipt_long, color: Colors.white, size: 18),
            label: Text(tr('Đổi HĐ'), style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kiotBlue))
          : _order == null
              ? _buildEmptyPick()
              : _mobile
                  ? _buildMobileBody()
                  : _buildDesktopBody(),
      bottomNavigationBar: _order != null ? _buildBottomBar(canReturn) : null,
    );
  }

  Widget _buildEmptyPick() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.assignment_return_outlined,
                size: 56, color: _kiotBlue.withOpacity(0.6)),
            const SizedBox(height: 16),
            Text(tr('Trả hàng bán hàng'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(tr('Chọn hóa đơn đã hoàn thành để trả một phần hoặc toàn bộ hàng.'),
              textAlign: TextAlign.center,
              style: TextStyle(color: PosTheme.textSecondary),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _kiotBlue,
                minimumSize: const Size(220, 48),
              ),
              onPressed: _pickOrder,
              icon: const Icon(Icons.search),
              label: Text(tr('Chọn hóa đơn')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderHeader(PosSaleOrder o) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: PosTheme.mobileCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr(o.orderNo),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _kiotBlue,
                  ),
                ),
              ),
              if (o.createdAt != null)
                Text(
                  tr(_dateFmt.format(o.createdAt!.toLocal())),
                  style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(tr('${tr('Khách: ')}${o.customerName ?? 'Khách lẻ'}')),
          if ((o.soldBy ?? o.createdBy)?.isNotEmpty == true)
            Text(tr('NV: ${o.soldBy ?? o.createdBy}'),
                style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
          const SizedBox(height: 8),
          Row(
            children: [
              _chip('Tổng HĐ', _moneyFmt.format(o.total)),
              if (o.returnedAmount > 0) ...[
                const SizedBox(width: 8),
                _chip('Đã trả', _moneyFmt.format(o.returnedAmount), orange: true),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value, {bool orange = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: orange ? Colors.orange.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        tr('$label: $value'),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: orange ? Colors.orange.shade800 : _kiotBlue,
        ),
      ),
    );
  }

  Widget _buildMobileBody() {
    final o = _order!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      children: [
        _buildOrderHeader(o),
        if (_history.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildHistorySection(),
        ],
        const SizedBox(height: 12),
        Text(tr('Chọn hàng trả'),
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 8),
        if (_lines.isEmpty)
          Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text(tr('Đã trả hết hàng trong đơn'))),
          )
        else
          ..._lines.map((rl) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _mobileLineCard(rl),
              )),
        const SizedBox(height: 8),
        _buildRefundMethodPicker(),
        const SizedBox(height: 8),
        TextField(
          controller: _noteCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            hintText: tr('Ghi chú trả hàng'),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildRefundMethodPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: PosTheme.mobileCardDecoration(),
      child: DropdownButtonFormField<String>(
        value: _refundMethods.contains(_refundPaymentMethod)
            ? _refundPaymentMethod
            : _refundMethods.first,
        decoration: InputDecoration(
          labelText: tr('Phương thức hoàn tiền'),
          border: InputBorder.none,
        ),
        items: _refundMethods
            .map((m) => DropdownMenuItem(value: m, child: Text(tr(m))))
            .toList(),
        onChanged: _submitting
            ? null
            : (v) {
                if (v == null) return;
                setState(() => _refundPaymentMethod = v);
              },
      ),
    );
  }

  Widget _buildHistorySection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: PosTheme.mobileCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('Lịch sử trả'),
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          ..._history.take(5).map((h) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        tr(h.returnNo),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: h.isVoided
                              ? PosTheme.textSecondary
                              : _kiotBlue,
                          decoration:
                              h.isVoided ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    if (h.isVoided)
                      Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(tr('Đã hủy'),
                            style: TextStyle(fontSize: 10)),
                      )
                    else
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                            minWidth: 32, minHeight: 32),
                        tooltip: tr('Hủy phiếu trả'),
                        icon: const Icon(Icons.cancel_outlined,
                            size: 18, color: Colors.red),
                        onPressed: _submitting
                            ? null
                            : () => _voidReturn(h.returnNo),
                      ),
                    Text(
                      tr(_moneyFmt.format(h.refundAmount)),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: h.isVoided
                            ? PosTheme.textSecondary
                            : null,
                        decoration:
                            h.isVoided ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _mobileLineCard(_ReturnLine rl) {
    final l = rl.line;
    final meta = _productMeta[l.productId];
    final ret = _returnQty(rl);
    final unit = _unitRefund(l);
    final lineTotal = ret * unit;
    final code = meta?.productCode ?? meta?.barcode ?? '';

    return Container(
      decoration: PosTheme.mobileCardDecoration(),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              PosProductImage(
                productId: l.productId,
                imageUrl: meta?.imageUrl,
                size: 36,
                borderRadius: 6,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(l.productName),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    Text(
                      tr([
                        if (code.isNotEmpty) code,
                        '${_moneyFmt.format(unit)}/${l.unitName ?? 'cái'}',
                        'Còn ${_qtyFmt.format(rl.maxReturnable)}',
                      ].join(' · ')),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 10, color: PosTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              if (ret > 0)
                Text(tr(_moneyFmt.format(lineTotal)),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: _kiotBlue)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _qtyBtn(Icons.remove, ret > 0 ? () => _adjustReturnQty(rl, -1) : null),
              Expanded(
                child: TextField(
                  controller: rl.qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
                  ],
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    border: const OutlineInputBorder(),
                    labelText: tr('SL trả'),
                    labelStyle: const TextStyle(fontSize: 11),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (v) {
                    _setReturnQty(rl, double.tryParse(v.replaceAll(',', '.')) ?? 0);
                  },
                ),
              ),
              _qtyBtn(Icons.add, ret < rl.maxReturnable ? () => _adjustReturnQty(rl, 1) : null,
                  primary: true),
              const SizedBox(width: 4),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: rl.maxReturnable > 0
                    ? () => _setReturnQty(rl, rl.maxReturnable)
                    : null,
                child: Text(tr('Hết'), style: const TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback? onTap, {bool primary = false}) {
    return Material(
      color: primary ? _kiotBlue : Colors.grey.shade200,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(icon, size: 18, color: primary ? Colors.white : Colors.black87),
        ),
      ),
    );
  }

  Widget _buildDesktopBody() {
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
                        child: Text(tr('${tr('Trả hàng / ')}${o.orderNo} — ${o.soldBy ?? o.createdBy ?? ''}'),
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
                    ? Center(child: Text(tr('Đã trả hết hàng trong đơn')))
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: _lines.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: PosTheme.border),
                        itemBuilder: (_, i) => _desktopLineRow(_lines[i], i),
                      ),
              ),
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildRefundMethodPicker(),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _noteCtrl,
                      decoration: InputDecoration(
                        hintText: tr('Ghi chú trả hàng'),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
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
      child: Row(
        children: [
          SizedBox(width: 28, child: Text(tr('STT'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
          SizedBox(width: 44),
          Expanded(child: Text(tr('Tên hàng'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
          SizedBox(width: 56, child: Text(tr('ĐVT'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
          SizedBox(width: 120, child: Text(tr('SL trả'), textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
          SizedBox(width: 72, child: Text(tr('Giá'), textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
          SizedBox(width: 80, child: Text(tr('T.Tiền'), textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  Widget _desktopLineRow(_ReturnLine rl, int index) {
    final l = rl.line;
    final meta = _productMeta[l.productId];
    final ret = _returnQty(rl);
    final unit = _unitRefund(l);
    final lineTotal = ret * unit;

    return Material(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 28,
              child: Text(tr('${index + 1}'),
                  style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
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
                  Text(tr(l.productName),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  Text(tr('Còn trả ${_qtyFmt.format(rl.maxReturnable)}'),
                    style: const TextStyle(fontSize: 10, color: PosTheme.textSecondary),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 56,
              child: Text(tr(l.unitName ?? 'cái'), style: const TextStyle(fontSize: 12)),
            ),
            SizedBox(
              width: 120,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    icon: const Icon(Icons.remove, size: 16),
                    onPressed: ret > 0 ? () => _adjustReturnQty(rl, -1) : null,
                  ),
                  Text(
                    tr('${_qtyFmt.format(ret)} / ${_qtyFmt.format(rl.maxReturnable)}'),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    icon: const Icon(Icons.add, size: 16, color: _kiotBlue),
                    onPressed:
                        ret < rl.maxReturnable ? () => _adjustReturnQty(rl, 1) : null,
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 72,
              child: Text(tr(_moneyFmt.format(unit)),
                  textAlign: TextAlign.right, style: const TextStyle(fontSize: 12)),
            ),
            SizedBox(
              width: 80,
              child: Text(tr(_moneyFmt.format(lineTotal)),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
          Text(tr(o.soldBy ?? o.createdBy ?? '—'),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          if (o.createdAt != null)
            Text(tr(_dateFmt.format(o.createdAt!.toLocal())),
                style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
          const SizedBox(height: 8),
          Text(tr('${tr('Khách: ')}${o.customerName ?? 'Khách lẻ'}'), style: const TextStyle(fontSize: 13)),
          const Divider(height: 24),
          _sumRow('Tổng HĐ', _moneyFmt.format(o.total)),
          if (o.returnedAmount > 0)
            _sumRow('Đã trả trước', _moneyFmt.format(o.returnedAmount)),
          _sumRow('Tiền trả lần này', _moneyFmt.format(_returnTotal)),
          const Spacer(),
          _sumRow('Cần trả khách', _moneyFmt.format(_returnTotal),
              bold: true, blue: true),
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
            child: Text(tr(label),
                style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w600 : null)),
          ),
          Text(
            tr(value),
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

  Widget _buildBottomBar(bool canReturn) {
    return Material(
      color: Colors.white,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr('Cần trả khách'),
                        style: TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
                    Text(
                      tr(_moneyFmt.format(_returnTotal)),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _kiotBlue,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: !canReturn || _submitting || _lines.isEmpty ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: _kiotBlue,
                  minimumSize: Size(_mobile ? 140 : 180, 48),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(tr('TRẢ HÀNG'),
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReturnLine {
  _ReturnLine({required this.line, required this.qtyCtrl});

  final PosSaleOrderLine line;
  final TextEditingController qtyCtrl;

  double get maxReturnable =>
      (line.qty - line.returnedQty).clamp(0, line.qty);
}

class _ReturnHistory {
  _ReturnHistory({
    required this.returnNo,
    required this.refundAmount,
    this.createdAt,
    this.isVoided = false,
  });

  final String returnNo;
  final double refundAmount;
  final DateTime? createdAt;
  final bool isVoided;

  factory _ReturnHistory.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return _ReturnHistory(
      returnNo: (json['returnNo'] ?? json['ReturnNo'] ?? '').toString(),
      refundAmount: n(json['refundAmount'] ?? json['RefundAmount']),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      isVoided: json['isVoided'] == true || json['IsVoided'] == true,
    );
  }
}
