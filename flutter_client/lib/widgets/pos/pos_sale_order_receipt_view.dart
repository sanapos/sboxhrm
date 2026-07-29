import 'package:flutter/material.dart';

import 'package:intl/intl.dart';



import '../../models/pos_sale_order.dart';

import 'pos_product_image.dart';

import 'pos_sale_order_helpers.dart';

import 'pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';



/// Hiển thị tờ hóa đơn read-only — đủ trường như bản in cho khách.

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

    final balance =

        order.balanceDue != 0 ? order.balanceDue : order.total - order.paidAmount;



    return Material(

      color: Colors.white,

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.stretch,

        children: [

          if (showMeta) _buildInvoiceHeader(money),

          if (order.lines.isEmpty)

            Padding(

              padding: EdgeInsets.all(24),

              child: Center(

                child: Text(tr('Đơn không có dòng hàng'),

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

                          tr(order.note!.trim()),

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

                if (order.voucherDiscount > 0)

                  _sumRow(

                    'Voucher${order.voucherCode != null ? ' (${order.voucherCode})' : ''}',

                    '-${money.format(order.voucherDiscount)}',

                    negative: true,

                  ),

                if (order.pointsDiscount > 0)

                  _sumRow(

                    'Đổi điểm${order.pointsRedeemed > 0 ? ' (${order.pointsRedeemed.toStringAsFixed(0)} điểm)' : ''}',

                    '-${money.format(order.pointsDiscount)}',

                    negative: true,

                  ),

                _sumRow('Tổng cộng', money.format(order.total), bold: true, accent: true),

                _sumRow('Đã thanh toán (${order.paymentMethod})', money.format(order.paidAmount)),

                if (balance > 0) _sumRow('Còn lại', money.format(balance)),

                if (order.returnedAmount > 0)

                  _sumRow('Đã trả hàng', money.format(order.returnedAmount), negative: true),

                if (order.pointsEarned > 0)

                  Padding(

                    padding: const EdgeInsets.only(top: 4),

                    child: Text(tr('Tích điểm: +${order.pointsEarned.toStringAsFixed(0)} điểm'),

                      style: const TextStyle(fontSize: 12, color: Color(0xFF059669)),

                    ),

                  ),

              ],

            ),

          ),

        ],

      ),

    );

  }



  Widget _buildInvoiceHeader(NumberFormat money) {

    final dt = order.saleDate ?? order.createdAt;

    final dateStr = dt != null

        ? DateFormat('dd/MM/yyyy HH:mm', 'vi_VN').format(dt.toLocal())

        : '—';

    final customerLabel = _customerLabel();



    return Container(

      padding: const EdgeInsets.fromLTRB(_sidePadding, 10, _sidePadding, 8),

      decoration: BoxDecoration(
        border: const Border(bottom: BorderSide(color: PosTheme.border)),
        color: order.status == 'Cancelled'
            ? Colors.red.shade50.withValues(alpha: 0.55)
            : const Color(0xFFFAFBFC),
      ),

      child: Column(

        crossAxisAlignment: CrossAxisAlignment.stretch,

        children: [

          Row(

            children: [

              Expanded(

                child: Text(
                  tr(order.orderNo),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: posSaleOrderAccentColor(order.status),
                    decoration: order.status == 'Cancelled'
                        ? TextDecoration.lineThrough
                        : null,
                    decorationColor: Colors.red.shade400,
                  ),
                ),

              ),

              posSaleOrderStatusChip(order.status, returnStatus: order.returnStatus),

            ],

          ),

          const SizedBox(height: 4),

          Text(tr('${money.format(order.total)} đ'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: order.status == 'Cancelled' ? Colors.red.shade800 : null,
              decoration: order.status == 'Cancelled'
                  ? TextDecoration.lineThrough
                  : null,
              decorationColor: Colors.red.shade400,
            ),
          ),

          const SizedBox(height: 8),

          _infoLine('Ngày bán', dateStr),

          if (order.createdBy != null && order.createdBy!.trim().isNotEmpty)

            _infoLine('Người tạo', order.createdBy!.trim()),

          if (order.soldBy != null && order.soldBy!.trim().isNotEmpty)

            _infoLine('Người bán', order.soldBy!.trim()),

          _infoLine('Khách hàng', customerLabel),

          if (order.customerPhone != null && order.customerPhone!.trim().isNotEmpty)

            _infoLine('SĐT khách', order.customerPhone!.trim()),

          if (order.salesChannel != null && order.salesChannel!.trim().isNotEmpty)

            _infoLine('Kênh bán', order.salesChannel!.trim()),

          if (order.priceListName != null && order.priceListName!.trim().isNotEmpty)

            _infoLine('Bảng giá', order.priceListName!.trim()),

          _infoLine('Thanh toán', order.paymentMethod),

          if (order.isDelivery) ...[

            const Divider(height: 16),

            Text(tr('Giao hàng'),

              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: PosTheme.textSecondary),

            ),

            const SizedBox(height: 4),

            if (order.deliveryAddress != null && order.deliveryAddress!.trim().isNotEmpty)

              _infoLine('Địa chỉ', order.deliveryAddress!.trim()),

            if (order.deliveryPhone != null && order.deliveryPhone!.trim().isNotEmpty)

              _infoLine('SĐT nhận', order.deliveryPhone!.trim()),

            if (order.deliveryPartner != null && order.deliveryPartner!.trim().isNotEmpty)

              _infoLine('Đối tác GH', order.deliveryPartner!.trim()),

            if (order.deliveryStatus != null && order.deliveryStatus!.trim().isNotEmpty)

              _infoLine('Trạng thái GH', order.deliveryStatus!.trim()),

          ],

        ],

      ),

    );

  }



  String _customerLabel() {

    final name = order.customerName?.trim();

    if (name != null && name.isNotEmpty) {

      if (order.customerCode != null && order.customerCode!.trim().isNotEmpty) {

        return '${order.customerCode!.trim()} — $name';

      }

      return name;

    }

    return 'Khách lẻ';

  }



  Widget _infoLine(String label, String value) => Padding(

        padding: const EdgeInsets.only(bottom: 3),

        child: RichText(

          text: TextSpan(

            style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.35),

            children: [

              TextSpan(

                text: tr('$label: '),

                style: const TextStyle(color: PosTheme.textSecondary),

              ),

              TextSpan(text: tr(value)),

            ],

          ),

        ),

      );



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

          SizedBox(width: _wStt, child: Text(tr('STT'), style: hdr)),

          SizedBox(width: _wImg + _gapImg),

          Expanded(child: Text(tr('Mặt hàng'), style: hdr)),

          SizedBox(width: _wQty, child: Text(tr('SL'), style: hdr, textAlign: TextAlign.center)),

          SizedBox(width: _wUnit, child: Text(tr('ĐVT'), style: hdr, textAlign: TextAlign.center)),

          SizedBox(width: _wPrice, child: Text(tr('Đơn giá'), style: hdr, textAlign: TextAlign.right)),

          SizedBox(width: _wTotal, child: Text(tr('Thành tiền'), style: hdr, textAlign: TextAlign.right)),

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

                tr('$index'),

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

                    tr(line.productName),

                    maxLines: 1,

                    overflow: TextOverflow.ellipsis,

                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),

                  ),

                  if (line.lineNote != null && line.lineNote!.trim().isNotEmpty)

                    Text(

                      tr('↳ ${line.lineNote!.trim()}'),

                      maxLines: 1,

                      overflow: TextOverflow.ellipsis,

                      style: const TextStyle(fontSize: 10, color: _blue),

                    ),

                  if (line.discountAmount > 0)

                    Text(

                      tr('CK: -${money.format(line.discountAmount)}'),

                      style: TextStyle(fontSize: 10, color: Colors.red.shade700),

                    ),

                  if (line.serialNumbers.isNotEmpty)

                    Text(

                      tr('Seri: ${line.serialNumbers.join(', ')}'),

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

                tr(qtyFmt.format(line.qty)),

                textAlign: TextAlign.center,

                style: const TextStyle(fontSize: 12),

              ),

            ),

            SizedBox(

              width: _wUnit,

              child: Text(

                tr(line.unitName ?? '—'),

                textAlign: TextAlign.center,

                maxLines: 1,

                overflow: TextOverflow.ellipsis,

                style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),

              ),

            ),

            SizedBox(

              width: _wPrice,

              child: Text(

                tr(money.format(line.unitPrice)),

                textAlign: TextAlign.right,

                style: const TextStyle(fontSize: 12),

              ),

            ),

            SizedBox(

              width: _wTotal,

              child: Text(

                tr(money.format(line.lineTotal)),

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

              tr(label),

              style: TextStyle(

                fontSize: bold ? 13 : 12,

                fontWeight: bold ? FontWeight.w600 : FontWeight.normal,

                color: accent ? const Color(0xFF0F172A) : PosTheme.textSecondary,

              ),

            ),

          ),

          Text(tr('$value đ'),

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


