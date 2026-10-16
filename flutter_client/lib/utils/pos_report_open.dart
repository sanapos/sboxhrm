import 'package:flutter/material.dart';

import '../models/pos_product.dart';
import '../screens/pos/pos_product_detail_screen.dart';
import '../screens/pos/pos_product_editor_page.dart';
import '../screens/pos_purchase_receipt_list_screen.dart';
import '../screens/pos_sale_order_editor_screen.dart';
import '../screens/pos_sale_order_list_screen.dart';
import '../services/api_service.dart';
import '../widgets/pos/pos_document_views.dart';
import '../widgets/pos/pos_hub_scope.dart';

/// Mở phiếu gốc / danh sách tổng hợp từ báo cáo POS (A6 + A7).
class PosReportOpen {
  static final _api = ApiService();
  static final _hdRe = RegExp(r'HD\d{6,}', caseSensitive: false);

  /// Hóa đơn gốc dạng tờ hóa đơn (read-only). Phiếu tạm có nút «Mở để sửa».
  static Future<void> sale(BuildContext context, String id) =>
      PosDocumentViews.sale(context, id, openEditor: editSale);

  /// Màn sửa đơn — chỉ dùng cho phiếu tạm.
  static Future<void> editSale(BuildContext context, String id) async {
    if (id.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PosSaleOrderEditorScreen(orderId: id),
      ),
    );
  }

  static Future<void> sales(
    BuildContext context, {
    DateTime? from,
    DateTime? to,
    String? search,
    String? soldBy,
    String? paymentMethod,
    String? customerId,
    String? customerName,
    String? productId,
    String? voucherCode,
    bool hasVoucher = false,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PosHubScope(
          embeddedInHub: false,
          pushedSubPage: true,
          child: PosSaleOrderListScreen(
            initialFrom: from,
            initialTo: to,
            initialSearch: search ?? customerName,
            initialSoldBy: soldBy,
            initialPaymentMethod: paymentMethod,
            initialCustomerId: customerId,
            initialProductId: productId,
            initialVoucherCode: voucherCode,
            initialHasVoucher: hasVoucher,
          ),
        ),
      ),
    );
  }

  /// Thông tin hàng + thẻ kho (nhập / xuất / bán từng lần).
  static Future<void> productDetail(BuildContext context, String id) async {
    if (id.isEmpty) return;
    final res = await _api.getPosProduct(id);
    if (!context.mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PosProductDetailScreen(
          product: PosProduct.fromJson(Map<String, dynamic>.from(res['data'] as Map)),
        ),
      ));
    }
  }

  /// Bấm một mặt hàng trong báo cáo: xem thẻ kho / các hóa đơn đã bán hàng này.
  static Future<void> productMenu(
    BuildContext context, {
    required String id,
    required String name,
    DateTime? from,
    DateTime? to,
  }) async {
    if (id.isEmpty) return;
    final a = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700))),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('Thẻ kho & thông tin hàng'),
            onTap: () => Navigator.pop(ctx, 'card'),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('Hóa đơn đã bán hàng này'),
            onTap: () => Navigator.pop(ctx, 'sales'),
          ),
        ]),
      ),
    );
    if (a == null || !context.mounted) return;
    if (a == 'card') {
      await productDetail(context, id);
    } else {
      await sales(context, from: from, to: to, productId: id);
    }
  }

  static Future<void> purchaseReceipt(BuildContext context, String id) =>
      PosDocumentViews.purchaseReceipt(context, id);

  static Future<void> purchases(
    BuildContext context, {
    String? search,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PosHubScope(
          embeddedInHub: false,
          pushedSubPage: true,
          child: PosPurchaseReceiptListScreen(initialSearch: search),
        ),
      ),
    );
  }

  static Future<void> purchaseReturn(BuildContext context, String id) =>
      PosDocumentViews.purchaseReturn(context, id);

  static Future<void> product(
    BuildContext context, {
    String? id,
    String? name,
    DateTime? from,
    DateTime? to,
    bool preferSales = false,
  }) async {
    if (preferSales) {
      await sales(
        context,
        from: from,
        to: to,
        productId: (id ?? '').trim().isEmpty ? null : id,
        search: (id ?? '').trim().isEmpty ? name : null,
      );
      return;
    }
    if (id != null && id.isNotEmpty) {
      final res = await _api.getPosProduct(id);
      if (!context.mounted) return;
      if (res['isSuccess'] == true && res['data'] is Map) {
        final p = PosProduct.fromJson(
          Map<String, dynamic>.from(res['data'] as Map),
        );
        await PosProductEditorPage.open(
          context,
          productType: p.productType,
          product: p,
        );
        return;
      }
    }
    if (!context.mounted) return;
    await sales(context, from: from, to: to, search: name);
  }

  /// Phiếu thu / chi dạng tờ phiếu; phiếu thu bán hàng có nút «Mở hóa đơn gốc».
  static Future<void> cashTx(
    BuildContext context,
    Map<String, dynamic> row,
  ) {
    final desc = '${row['description'] ?? row['Description'] ?? ''}';
    final note = '${row['internalNote'] ?? row['InternalNote'] ?? ''}';
    return PosDocumentViews.cashTx(
      context,
      row,
      saleIdFallback: saleIdFromNote(note),
      invoiceNoFallback: invoiceNoFromText('$desc $note'),
      onOpenSale: (ctx, id) => sale(ctx, id),
      onOpenInvoiceNo: (ctx, no) => sales(ctx, search: no),
    );
  }

  /// Phiếu thu nợ khách → hóa đơn gốc: thu theo đơn mở đơn đó; thu chung mở các đơn ghi trong ghi chú
  /// («Trừ nợ đơn: HD…»). Không có gì → các đơn của khách (nếu có [customerId]).
  static Future<void> debtPaymentOrders(
    BuildContext context, {
    String? orderId,
    String? note,
    String? paymentNo,
    String? customerId,
    String? customerName,
  }) async {
    final oid = (orderId ?? '').trim();
    if (oid.isNotEmpty && oid != 'null') return sale(context, oid);
    final nos = _hdRe.allMatches(note ?? '').map((m) => m.group(0)!).toSet().toList();
    if (nos.length == 1) return sales(context, search: nos.first);
    if (nos.isEmpty) {
      if ((customerId ?? '').isEmpty) return;
      return sales(context, customerId: customerId, customerName: customerName);
    }
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(title: Text('Phiếu ${paymentNo ?? ''} đã trừ nợ các đơn'.replaceAll('  ', ' '))),
          for (final no in nos)
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined),
              title: Text(no),
              onTap: () {
                Navigator.pop(ctx);
                sales(context, search: no);
              },
            ),
        ]),
      ),
    );
  }

  static String? saleIdFromNote(String? note) {
    if (note == null || note.isEmpty) return null;
    const prefix = 'pos bán hàng #';
    final lower = note.toLowerCase();
    final i = lower.indexOf(prefix);
    if (i < 0) return null;
    final rest = note.substring(i + prefix.length);
    final id = rest.split(RegExp(r'[|,\s]')).first.trim();
    return id.length >= 32 ? id : null;
  }

  static String? invoiceNoFromText(String? text) {
    if (text == null || text.isEmpty) return null;
    return _hdRe.firstMatch(text)?.group(0);
  }
}
