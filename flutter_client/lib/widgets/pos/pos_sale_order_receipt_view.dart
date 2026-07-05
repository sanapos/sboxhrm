import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_sale_order.dart';
import 'pos_product_image.dart';
import 'pos_theme.dart';

/// Hiển thị tờ hóa đơn read-only — bố cục giống giỏ hàng màn Thu ngân.
class PosSaleOrderReceiptView extends StatelessWidget {
  const PosSaleOrderReceiptView({
    super.key,
    required this.order,
    this.showMeta = true,
  });

  final PosSaleOrder order;
  final bool showMeta;

  static const _blue = Color(0xFF2563EB);
  static const _sidePadding = 12.0;
  static const _hdrH = 30.0;
  static const _rowH = 50.0;
  static const _wStt = 26.0;
  static const _wImg = 36.0;
  static const _gapImg = 8.0;
  static const _wQty = 52.0;
  static const _wUnit = 56.0;
  static const _wPrice = 80.0;
  static const _wTotal = 88.0;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0', 'vi_VN');
    final qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
    final dt = order.saleDate ?? order.createdAt;
    final balance =
        order.balanceDue != 0 ? order.balanceDue : order.total - order.paidAmount;

    return Material(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showMeta) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(_sidePadding, 10, _sidePadding, 8),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: PosTheme.border)),
                color: Color(0xFFFAFBFC),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          order.orderNo,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _blue,
                          ),
                        ),
                      ),
                      Text(
                        '${money.format(order.total)} đ',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (dt != null)
                        DateFormat('dd/MM/yyyy HH:mm', 'vi_VN').format(dt.toLocal()),
                      order.customerName ?? 'Khách lẻ',
                      order.paymentMethod,
                    ].join(' · '),
                    style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
                  ),
                  if (order.soldBy != null && order.soldBy!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'NV: ${order.soldBy!.trim()}',
                        style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (order.lines.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Text(
                  'Đơn không có dòng hàng',
                  style: TextStyle(color: PosTheme.textSecondary),
                ),
              ),
            )
          else ...[
            _cartHeader(),
            ...List.generate(order.lines.length, (i) {
              final line = order.lines[order.lines.length - 1 - i];
              final index = order.lines.length - i;
              return Column(
                children: [
                  if (i > 0)
                    const Divider(height: 1, indent: 12, endIndent: 12, color: PosTheme.border),
                  _cartRow(line, index, money, qtyFmt),
                ],
              );
            }),
          ],
          Container(
            padding: const EdgeInsets.fromLTRB(_sidePadding, 8, _sidePadding, 10),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: PosTheme.border)),
              color: Color(0xFFFAFBFC),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (order.note != null && order.note!.trim().isNotEmpty) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.edit_outlined, size: 14, color: PosTheme.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          order.note!.trim(),
                          style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                _sumRow('Tạm tính', money.format(order.subTotal)),
                if (order.discount > 0)
                  _sumRow('Giảm giá', '-${money.format(order.discount)}', negative: true),
                _sumRow('Tổng cộng', money.format(order.total), bold: true, accent: true),
                _sumRow('Đã thanh toán', money.format(order.paidAmount)),
                if (balance > 0) _sumRow('Còn lại', money.format(balance)),
                if (order.returnedAmount > 0)
                  _sumRow('Đã trả hàng', money.format(order.returnedAmount), negative: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartHeader() {
    const hdr = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: PosTheme.textSecondary,
    );
    return Container(
      height: _hdrH,
      padding: const EdgeInsets.symmetric(horizontal: _sidePadding),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: PosTheme.border)),
      ),
      child: Row(
        children: [
          const SizedBox(width: _wStt, child: Text('STT', style: hdr)),
          SizedBox(width: _wImg + _gapImg),
          const Expanded(child: Text('Mặt hàng', style: hdr)),
          const SizedBox(width: _wQty, child: Text('SL', style: hdr, textAlign: TextAlign.center)),
          const SizedBox(width: _wUnit, child: Text('ĐVT', style: hdr, textAlign: TextAlign.center)),
          const SizedBox(width: _wPrice, child: Text('Đơn giá', style: hdr, textAlign: TextAlign.right)),
          const SizedBox(width: _wTotal, child: Text('Thành tiền', style: hdr, textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _cartRow(
    PosSaleOrderLine line,
    int index,
    NumberFormat money,
    NumberFormat qtyFmt,
  ) {
    return SizedBox(
      height: line.serialNumbers.isNotEmpty ? _rowH + 14 : _rowH,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _sidePadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: _wStt,
              child: Text(
                '$index',
                style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),
              ),
            ),
            PosProductImage(
              productId: line.productId,
              imageUrl: null,
              size: _wImg,
              borderRadius: 4,
            ),
            SizedBox(width: _gapImg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    line.productName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  if (line.lineNote != null && line.lineNote!.trim().isNotEmpty)
                    Text(
                      '↳ ${line.lineNote!.trim()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: _blue),
                    ),
                  if (line.discountAmount > 0)
                    Text(
                      'CK: -${money.format(line.discountAmount)}',
                      style: TextStyle(fontSize: 10, color: Colors.red.shade700),
                    ),
                  if (line.serialNumbers.isNotEmpty)
                    Text(
                      'Seri: ${line.serialNumbers.join(', ')}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: Color(0xFF059669)),
                    ),
                ],
              ),
            ),
            SizedBox(
              width: _wQty,
              child: Text(
                qtyFmt.format(line.qty),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            SizedBox(
              width: _wUnit,
              child: Text(
                line.unitName ?? '—',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),
              ),
            ),
            SizedBox(
              width: _wPrice,
              child: Text(
                money.format(line.unitPrice),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            SizedBox(
              width: _wTotal,
              child: Text(
                money.format(line.lineTotal),
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sumRow(
    String label,
    String value, {
    bool bold = false,
    bool accent = false,
    bool negative = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: bold ? 13 : 12,
                fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
                color: accent ? const Color(0xFF0F172A) : PosTheme.textSecondary,
              ),
            ),
          ),
          Text(
            '$value đ',
            style: TextStyle(
              fontSize: bold ? 14 : 12,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: accent
                  ? _blue
                  : negative
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}
