import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_tr.dart';
import '../models/pos_product.dart';
import '../screens/pos/pos_product_editor_page.dart';
import '../screens/pos_purchase_receipt_editor_screen.dart';
import '../screens/pos_purchase_receipt_list_screen.dart';
import '../screens/pos_purchase_return_editor_screen.dart';
import '../screens/pos_sale_order_editor_screen.dart';
import '../screens/pos_sale_order_list_screen.dart';
import '../services/api_service.dart';
import '../widgets/pos/pos_hub_scope.dart';
import '../widgets/pos/pos_theme.dart';

/// Mở phiếu gốc / danh sách tổng hợp từ báo cáo POS (A6 + A7).
class PosReportOpen {
  static final _api = ApiService();
  static final _hdRe = RegExp(r'HD\d{6,}', caseSensitive: false);

  static Future<void> sale(BuildContext context, String id) async {
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
          ),
        ),
      ),
    );
  }

  static Future<void> purchaseReceipt(BuildContext context, String id) async {
    if (id.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PosPurchaseReceiptEditorScreen(receiptId: id),
      ),
    );
  }

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

  static Future<void> purchaseReturn(BuildContext context, String id) async {
    if (id.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PosPurchaseReturnEditorScreen(returnId: id),
      ),
    );
  }

  static Future<void> product(
    BuildContext context, {
    String? id,
    String? name,
    DateTime? from,
    DateTime? to,
  }) async {
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

  static Future<void> cashTx(
    BuildContext context,
    Map<String, dynamic> row,
  ) async {
    final id = '${row['id'] ?? row['Id'] ?? ''}'.trim();
    Map<String, dynamic> data = Map<String, dynamic>.from(row);
    if (id.isNotEmpty) {
      final res = await _api.getCashTransaction(id);
      if (res['isSuccess'] == true && res['data'] is Map) {
        data = Map<String, dynamic>.from(res['data'] as Map);
      }
    }
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _CashTxSheet(data: data),
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

class _CashTxSheet extends StatelessWidget {
  const _CashTxSheet({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0', 'vi_VN');
    final code = '${data['transactionCode'] ?? data['TransactionCode'] ?? '—'}';
    final type = '${data['type'] ?? data['Type'] ?? ''}';
    final income = type.toLowerCase().contains('income');
    final amount = data['amount'] is num
        ? (data['amount'] as num).toDouble()
        : double.tryParse('${data['amount']}') ?? 0;
    final desc = '${data['description'] ?? data['Description'] ?? ''}';
    final note = '${data['internalNote'] ?? data['InternalNote'] ?? ''}';
    final method = '${data['paymentMethod'] ?? data['PaymentMethod'] ?? ''}';
    final cat = '${data['category'] ?? data['categoryName'] ?? ''}';
    final date = '${data['transactionDate'] ?? data['TransactionDate'] ?? ''}';
    final saleId = PosReportOpen.saleIdFromNote(note);
    final invoice = PosReportOpen.invoiceNoFromText('$desc $note');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8ECF0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              tr(income ? 'Phiếu thu' : 'Phiếu chi'),
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF586064),
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              code,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2B3437),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${income ? '+' : '-'}${fmt.format(amount)}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: income
                    ? const Color(0xFF166534)
                    : const Color(0xFFB42318),
              ),
            ),
            const SizedBox(height: 12),
            if (desc.isNotEmpty)
              Text(desc, style: const TextStyle(fontSize: 14, color: Color(0xFF2B3437))),
            if (cat.isNotEmpty || method.isNotEmpty || date.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  [cat, method, date].where((s) => s.isNotEmpty).join(' · '),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF8A9199)),
                ),
              ),
            const SizedBox(height: 16),
            if (saleId != null)
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
                onPressed: () {
                  Navigator.pop(context);
                  PosReportOpen.sale(context, saleId);
                },
                child: Text(tr('Mở hóa đơn gốc')),
              )
            else if (invoice != null)
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
                onPressed: () {
                  Navigator.pop(context);
                  PosReportOpen.sales(context, search: invoice);
                },
                child: Text(tr('Mở hóa đơn $invoice')),
              ),
          ],
        ),
      ),
    );
  }
}
