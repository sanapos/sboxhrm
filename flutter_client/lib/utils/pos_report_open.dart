import 'package:flutter/material.dart';

import '../models/pos_product.dart';
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
