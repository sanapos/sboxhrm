import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_product.dart';
import '../../services/api_service.dart';
import '../../utils/pos_stock_receipt_print.dart';
import 'pos_stock_card_table.dart';
import 'pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Chi tiết chứng từ thẻ kho (phiếu nhập / điều chỉnh / bán).
Future<void> showPosStockDocumentSheet(
  BuildContext context, {
  required PosStockTransaction tx,
  required NumberFormat moneyFmt,
  required DateFormat dateFmt,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (_, scrollCtrl) => _PosStockDocumentSheet(
        tx: tx,
        moneyFmt: moneyFmt,
        dateFmt: dateFmt,
        scrollController: scrollCtrl,
      ),
    ),
  );
}

class _PosStockDocumentSheet extends StatefulWidget {
  const _PosStockDocumentSheet({
    required this.tx,
    required this.moneyFmt,
    required this.dateFmt,
    required this.scrollController,
  });

  final PosStockTransaction tx;
  final NumberFormat moneyFmt;
  final DateFormat dateFmt;
  final ScrollController scrollController;

  @override
  State<_PosStockDocumentSheet> createState() => _PosStockDocumentSheetState();
}

class _PosStockDocumentSheetState extends State<_PosStockDocumentSheet> {
  final _api = ApiService();
  PosStockReceipt? _receipt;
  Map<String, dynamic>? _issue;
  Map<String, dynamic>? _count;
  Map<String, dynamic>? _sale;
  Map<String, dynamic>? _purchaseReturn;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    final t = widget.tx;
    if (t.stockReceiptId != null && t.stockReceiptId!.isNotEmpty) {
      setState(() => _loading = true);
      final res = await _api.getPosStockReceipt(t.stockReceiptId!);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (res['isSuccess'] == true && res['data'] != null) {
          _receipt = PosStockReceipt.fromJson(res['data'] as Map<String, dynamic>);
        }
      });
      return;
    }
    if (t.stockIssueId != null && t.stockIssueId!.isNotEmpty) {
      setState(() => _loading = true);
      final res = await _api.getPosStockIssue(t.stockIssueId!);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (res['isSuccess'] == true) _issue = res['data'] as Map<String, dynamic>?;
      });
      return;
    }
    if (t.stockCountId != null && t.stockCountId!.isNotEmpty) {
      setState(() => _loading = true);
      final res = await _api.getPosStockCount(t.stockCountId!);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (res['isSuccess'] == true) _count = res['data'] as Map<String, dynamic>?;
      });
      return;
    }
    if (t.saleOrderId != null && t.saleOrderId!.isNotEmpty) {
      setState(() => _loading = true);
      final res = await _api.getPosSale(t.saleOrderId!);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (res['isSuccess'] == true) _sale = res['data'] as Map<String, dynamic>?;
      });
      return;
    }
    if (t.purchaseReturnId != null && t.purchaseReturnId!.isNotEmpty) {
      setState(() => _loading = true);
      final res = await _api.getPosPurchaseReturn(t.purchaseReturnId!);
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (res['isSuccess'] == true) {
          _purchaseReturn = res['data'] as Map<String, dynamic>?;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tx;
    final typeLabel = PosStockCardTable.txTypeLabel(t.transactionType);
    final doc = t.referenceNo ?? '—';
    final when = t.createdAt != null ? widget.dateFmt.format(t.createdAt!) : '—';

    return Material(
      color: Colors.white,
      child: ListView(
        controller: widget.scrollController,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            tr(doc),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: PosTheme.kiotBlue,
            ),
          ),
          const SizedBox(height: 4),
          Text(tr(typeLabel), style: const TextStyle(fontSize: 14)),
          Text(tr(when), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const Divider(height: 24),
          _row('Mã hàng', t.productCode),
          _row('Tên hàng', t.productName),
          if (t.unitName != null && t.unitName!.isNotEmpty)
            _row('Đơn vị', t.unitName!),
          _row('Số lượng',
              '${t.qtyChange >= 0 ? '+' : ''}${widget.moneyFmt.format(t.qtyChange)}'),
          _row('Tồn cuối', widget.moneyFmt.format(t.qtyAfter)),
          if (t.unitCost != null && t.unitCost! > 0)
            _row('Giá vốn', widget.moneyFmt.format(t.unitCost!)),
          if (t.lineAmount != null && t.lineAmount! > 0)
            _row('Giá trị', widget.moneyFmt.format(t.lineAmount!)),
          if (t.partnerName != null && t.partnerName!.isNotEmpty)
            _row('Đối tác', t.partnerName!),
          if (t.note != null && t.note!.isNotEmpty) _row('Ghi chú', t.note!),
          if (t.createdBy != null && t.createdBy!.isNotEmpty)
            _row('Người tạo', t.createdBy!),
          if (_loading) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_receipt != null) ...[
            const SizedBox(height: 20),
            Text(tr('Chi tiết phiếu nhập'),
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            if (_receipt!.supplierName != null)
              _row('Nhà cung cấp', _receipt!.supplierName!),
            _row('Tổng SL', widget.moneyFmt.format(_receipt!.totalQty)),
            _row('Tổng tiền', widget.moneyFmt.format(_receipt!.totalCost)),
            ..._receipt!.lines.map((l) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(tr('${l.productCode} · ${l.productName}'),
                            style: const TextStyle(fontSize: 12)),
                      ),
                      Text(tr('${widget.moneyFmt.format(l.qty)} × ${widget.moneyFmt.format(l.costPrice)}'),
                          style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                )),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => printPosStockReceipt(_receipt!),
              icon: const Icon(Icons.print, size: 18),
              label: Text(tr('In phiếu nhập')),
            ),
          ],
          if (_issue != null) ...[
            const SizedBox(height: 20),
            Text(tr('Chi tiết phiếu xuất'),
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            if ((_issue!['reason'] ?? _issue!['Reason']) != null)
              _row('Lý do', (_issue!['reason'] ?? _issue!['Reason']).toString()),
            _row('Tổng SL',
                widget.moneyFmt.format(_issue!['totalQty'] ?? _issue!['TotalQty'] ?? 0)),
            ...List<Map<String, dynamic>>.from(
                    (_issue!['lines'] ?? _issue!['Lines']) as List? ?? [])
                .map((l) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                                tr('${l['productCode'] ?? l['ProductCode']} · ${l['productName'] ?? l['ProductName']}'),
                                style: const TextStyle(fontSize: 12)),
                          ),
                          Text(tr(widget.moneyFmt.format(l['qty'] ?? l['Qty'] ?? 0)),
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    )),
          ],
          if (_count != null) ...[
            const SizedBox(height: 20),
            Text(tr('Chi tiết kiểm kê'),
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            _row('Tên phiếu', (_count!['name'] ?? _count!['Name'] ?? '').toString()),
            _row('Trạng thái', (_count!['status'] ?? _count!['Status'] ?? '').toString()),
          ],
          if (_sale != null) ...[
            const SizedBox(height: 20),
            Text(tr('Chi tiết đơn bán'),
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            _row('Mã đơn', (_sale!['orderNo'] ?? _sale!['OrderNo'] ?? '').toString()),
            _row('Khách hàng',
                (_sale!['customerName'] ?? _sale!['CustomerName'] ?? 'Khách lẻ').toString()),
            _row('Tổng', widget.moneyFmt.format(_sale!['total'] ?? _sale!['Total'] ?? 0)),
            _row('Đã thu', widget.moneyFmt.format(_sale!['paidAmount'] ?? _sale!['PaidAmount'] ?? 0)),
            ...List<Map<String, dynamic>>.from(
                    (_sale!['lines'] ?? _sale!['Lines']) as List? ?? [])
                .map((l) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                                tr('${l['productName'] ?? l['ProductName']}'),
                                style: const TextStyle(fontSize: 12)),
                          ),
                          Text(
                              tr('${widget.moneyFmt.format(l['qty'] ?? l['Qty'] ?? 0)} × ${widget.moneyFmt.format(l['unitPrice'] ?? l['UnitPrice'] ?? 0)}'),
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    )),
          ],
          if (_purchaseReturn != null) ...[
            const SizedBox(height: 20),
            Text(tr('Chi tiết trả hàng NCC'),
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 8),
            _row('Mã phiếu',
                (_purchaseReturn!['returnNo'] ?? _purchaseReturn!['ReturnNo'] ?? '').toString()),
            if ((_purchaseReturn!['supplierName'] ?? _purchaseReturn!['SupplierName']) != null)
              _row('Nhà cung cấp',
                  (_purchaseReturn!['supplierName'] ?? _purchaseReturn!['SupplierName']).toString()),
            _row('Tổng tiền',
                widget.moneyFmt.format(_purchaseReturn!['totalAmount'] ?? _purchaseReturn!['TotalAmount'] ?? 0)),
            _row('Đã nhận hoàn',
                widget.moneyFmt.format(_purchaseReturn!['refundReceived'] ?? _purchaseReturn!['RefundReceived'] ?? 0)),
            ...List<Map<String, dynamic>>.from(
                    (_purchaseReturn!['lines'] ?? _purchaseReturn!['Lines']) as List? ?? [])
                .map((l) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                                tr('${l['productCode'] ?? l['ProductCode']} · ${l['productName'] ?? l['ProductName']}'),
                                style: const TextStyle(fontSize: 12)),
                          ),
                          Text(tr(widget.moneyFmt.format(l['qty'] ?? l['Qty'] ?? 0)),
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    )),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(tr(label),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ),
          Expanded(child: Text(tr(value), style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
