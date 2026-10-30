import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../models/cash_transaction.dart';
import '../../models/pos_purchase.dart';
import '../../models/pos_sale_order.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/api_datetime.dart';
import '../../utils/pos_print_store_info.dart';
import '../../utils/pos_sale_order_print.dart';
import '../../utils/pos_sell_print_settings.dart';
import '../../utils/pos_vietnamese_money_words.dart';
import '../notification_overlay.dart';
import 'pos_sale_order_receipt_view.dart';
import 'pos_theme.dart';

/// Xem chứng từ gốc dạng tờ phiếu (read-only) khi bấm từ báo cáo POS:
/// hóa đơn bán, phiếu nhập hàng, phiếu trả hàng NCC, phiếu thu / chi.
///
/// Trước đây báo cáo mở màn SỬA phiếu (ô nhập bị khóa, thanh điều hướng POS) — khó đọc,
/// và màn sửa đơn đòi quyền Hàng hóa nên người chỉ xem báo cáo bị «Không có quyền».
class PosDocumentViews {
  PosDocumentViews._();

  static final _api = ApiService();
  static final money = NumberFormat('#,##0', 'vi_VN');
  static final qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
  static final dateTimeFmt = DateFormat('dd/MM/yyyy HH:mm', 'vi_VN');

  // ─── Khung chung ─────────────────────────────────────────────────────────

  /// Màn rộng: hộp thoại giữa màn (≤ 760px). Điện thoại: trang kéo từ dưới lên.
  static Future<void> _present(
    BuildContext context, {
    required String title,
    required Widget Function(BuildContext ctx) body,
    List<Widget> Function(BuildContext ctx)? actions,
  }) async {
    final wide = MediaQuery.of(context).size.width >= 700;

    Widget frame(BuildContext ctx, ScrollController? scroll) {
      final acts = actions?.call(ctx) ?? const <Widget>[];
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 6, 6),
            child: Row(children: [
              Expanded(
                child: Text(tr(title),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: tr('Đóng'),
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close),
              ),
            ]),
          ),
          const Divider(height: 1),
          Flexible(
            child: Container(
              color: const Color(0xFFF2F4F7),
              child: SingleChildScrollView(
                controller: scroll,
                padding: const EdgeInsets.all(12),
                child: body(ctx),
              ),
            ),
          ),
          if (acts.isNotEmpty) ...[
            const Divider(height: 1),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: acts,
                ),
              ),
            ),
          ],
        ],
      );
    }

    if (wide) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: frame(ctx, null),
          ),
        ),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        builder: (_, scroll) => frame(ctx, scroll),
      ),
    );
  }

  static Future<Map<String, dynamic>?> _loadMap(
    BuildContext context,
    Future<Map<String, dynamic>> Function() load,
    String what,
  ) async {
    final res = await load();
    if (res['isSuccess'] == true && res['data'] is Map) {
      return Map<String, dynamic>.from(res['data'] as Map);
    }
    if (context.mounted) {
      NotificationOverlayManager().showError(
        title: 'Không mở được $what',
        message: res['message']?.toString() ?? '',
      );
    }
    return null;
  }

  // ─── Hóa đơn bán ─────────────────────────────────────────────────────────

  /// Tờ hóa đơn + lịch sử thanh toán + In. Phiếu tạm mới có «Mở để sửa».
  static Future<void> sale(
    BuildContext context,
    String id, {
    Future<void> Function(BuildContext context, String id)? openEditor,
  }) async {
    if (id.isEmpty) return;
    final results = await Future.wait([_api.getPosSale(id), _api.getPosSalePayments(id)]);
    if (!context.mounted) return;
    final res = results[0];
    if (res['isSuccess'] != true || res['data'] is! Map) {
      NotificationOverlayManager().showError(
        title: 'Không mở được hóa đơn',
        message: res['message']?.toString() ?? '',
      );
      return;
    }
    final order = PosSaleOrder.fromJson(Map<String, dynamic>.from(res['data'] as Map));
    final payRes = results[1];
    // Không có quyền / lỗi tải → ẩn mục (không báo nhầm «Chưa có thanh toán»).
    final payments = payRes['isSuccess'] == true && payRes['data'] is List
        ? (payRes['data'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : null;
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final canEditDraft = order.status == 'Draft' &&
        openEditor != null &&
        perm.canView('PosProducts') &&
        perm.canEdit('PosSell');

    await _present(
      context,
      title: order.status == 'Draft' ? 'Phiếu tạm ${order.orderNo}' : 'Hóa đơn ${order.orderNo}',
      body: (_) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _paper(PosSaleOrderReceiptView(order: order)),
          if (payments != null) ...[
            const SizedBox(height: 10),
            _paper(_SalePayments(order: order, payments: payments)),
          ],
        ],
      ),
      actions: (ctx) => [
        if (canEditDraft)
          OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              openEditor(context, order.id);
            },
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(tr('Mở để sửa')),
          ),
        if (order.status != 'Draft')
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
            onPressed: () => _printSale(ctx, order),
            icon: const Icon(Icons.print_outlined, size: 18),
            label: Text(tr('In hóa đơn')),
          ),
      ],
    );
  }

  static Future<void> _printSale(BuildContext context, PosSaleOrder order) async {
    final settings = await PosSellPrintSettings.load();
    final store = await PosPrintStoreInfo.load();
    if (!context.mounted) return;
    await printPosSaleOrder(
      context: context,
      order: order,
      branchName: store.storeName,
      storeAddress: store.address,
      storePhone: store.phone,
      mergeSameItems: settings.mergeSameItems,
      copies: settings.copies,
      templateId: settings.templateId,
      skipDedup: true,
      showFeedback: true,
    );
  }

  // ─── Phiếu nhập / trả hàng NCC ───────────────────────────────────────────

  static Future<void> purchaseReceipt(BuildContext context, String id) async {
    if (id.isEmpty) return;
    final data = await _loadMap(context, () => _api.getPosPurchaseReceipt(id), 'phiếu nhập');
    if (data == null || !context.mounted) return;
    final r = PosPurchaseReceipt.fromJson(data);
    await _present(
      context,
      title: 'Phiếu nhập ${r.receiptNo}',
      body: (_) => _paper(PosPurchaseDocumentPaper.receipt(r)),
    );
  }

  static Future<void> purchaseReturn(BuildContext context, String id) async {
    if (id.isEmpty) return;
    final data = await _loadMap(context, () => _api.getPosPurchaseReturn(id), 'phiếu trả hàng');
    if (data == null || !context.mounted) return;
    final r = PosPurchaseReturn.fromJson(data);
    await _present(
      context,
      title: 'Phiếu trả hàng ${r.returnNo}',
      body: (_) => _paper(PosPurchaseDocumentPaper.purchaseReturn(r)),
    );
  }

  // ─── Phiếu thu / chi ─────────────────────────────────────────────────────

  /// [onOpenSale] mở hóa đơn gốc của phiếu thu bán hàng.
  static Future<void> cashTx(
    BuildContext context,
    Map<String, dynamic> row, {
    String? saleIdFallback,
    void Function(BuildContext context, String saleId)? onOpenSale,
    void Function(BuildContext context, String invoiceNo)? onOpenInvoiceNo,
    String? invoiceNoFallback,
  }) async {
    final id = '${row['id'] ?? row['Id'] ?? ''}'.trim();
    var data = Map<String, dynamic>.from(row);
    if (id.isNotEmpty) {
      final res = await _api.getCashTransaction(id);
      if (res['isSuccess'] == true && res['data'] is Map) {
        data = Map<String, dynamic>.from(res['data'] as Map);
      }
    }
    if (!context.mounted) return;
    CashTransaction? tx;
    try {
      tx = CashTransaction.fromJson(data);
    } catch (_) {
      tx = null;
    }
    final sourceIsSale = (tx?.sourceType ?? '').toLowerCase().contains('pos_sale') &&
        (tx?.sourceId ?? '').isNotEmpty;
    final saleId = sourceIsSale ? tx!.sourceId : saleIdFallback;
    final income = tx?.type == CashTransactionType.income ||
        (tx == null && '${data['type']}'.toLowerCase().contains('income'));

    await _present(
      context,
      title: income ? 'Phiếu thu' : 'Phiếu chi',
      body: (_) => _paper(PosCashVoucherPaper(data: data, tx: tx, income: income)),
      actions: (ctx) => [
        if (saleId != null && onOpenSale != null)
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
            onPressed: () {
              Navigator.pop(ctx);
              onOpenSale(context, saleId);
            },
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: Text(tr('Mở hóa đơn gốc')),
          )
        else if (invoiceNoFallback != null && onOpenInvoiceNo != null)
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
            onPressed: () {
              Navigator.pop(ctx);
              onOpenInvoiceNo(context, invoiceNoFallback);
            },
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: Text(tr('Mở hóa đơn $invoiceNoFallback')),
          ),
      ],
    );
  }

  // ─── Tiện ích ────────────────────────────────────────────────────────────

  static Widget _paper(Widget child) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: PosTheme.border),
          boxShadow: const [
            BoxShadow(color: Color(0x0F101828), blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );

  static String fmtDate(DateTime? dt) => dt == null ? '—' : dateTimeFmt.format(dt.toLocal());

  static String statusLabel(String status) => switch (status) {
        'Draft' => 'Phiếu tạm',
        'Completed' => 'Hoàn thành',
        'Cancelled' => 'Đã hủy',
        _ => status,
      };

  static Color statusColor(String status) => switch (status) {
        'Draft' => const Color(0xFFB54708),
        'Cancelled' => const Color(0xFFB42318),
        _ => SboxColors.success,
      };
}

/// Lịch sử thanh toán của hóa đơn (thu khi bán / cọc / thu nợ sau) + còn phải thu.
class _SalePayments extends StatelessWidget {
  const _SalePayments({required this.order, required this.payments});

  final PosSaleOrder order;
  final List<Map<String, dynamic>> payments;

  @override
  Widget build(BuildContext context) {
    final m = PosDocumentViews.money;
    double paid = 0;
    final rows = <Widget>[];
    for (final p in payments) {
      final amount = ((p['amount'] ?? p['Amount']) as num?)?.toDouble() ?? 0;
      paid += amount;
      final kind = (p['kind'] ?? p['Kind'] ?? 'sale').toString();
      final paidAt = p['paidAt'] ?? p['PaidAt'];
      final dt = paidAt != null ? parseApiUtcDateTime(paidAt.toString()) : null;
      final method = (p['paymentMethod'] ?? p['PaymentMethod'])?.toString() ?? '';
      final label = switch (kind) {
        'deposit' => 'Tiền cọc',
        'debt' => 'Thu nợ',
        _ => 'Thu khi bán',
      };
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('$label · ${p['paymentNo'] ?? p['PaymentNo'] ?? ''}'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              Text(
                tr([if (dt != null) PosDocumentViews.fmtDate(dt), if (method.isNotEmpty) method].join(' · ')),
                style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),
              ),
            ]),
          ),
          Text('${m.format(amount)} đ', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
      ));
    }
    final balance = order.balanceDue != 0 ? order.balanceDue : order.total - order.paidAmount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Lịch sử thanh toán'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              tr(order.status == 'Completed' ? 'Chưa có thanh toán' : 'Đơn chưa hoàn thành — chưa ghi nhận thanh toán'),
              style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
            ),
          )
        else
          ...rows,
        const Divider(height: 14),
        Row(children: [
          Expanded(child: Text(tr('Đã thu'), style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary))),
          Text('${m.format(paid)} đ', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
        if (order.status == 'Completed' && balance > 0.5)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(children: [
              Expanded(
                child: Text(tr('Còn phải thu'), style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
              ),
              Text('${m.format(balance)} đ',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.red.shade700)),
            ]),
          ),
      ]),
    );
  }
}

/// Tờ phiếu nhập hàng / trả hàng NCC: đầu phiếu, bảng hàng, tổng — như bản in.
class PosPurchaseDocumentPaper extends StatelessWidget {
  const PosPurchaseDocumentPaper._({
    required this.kindLabel,
    required this.code,
    required this.status,
    required this.meta,
    required this.lines,
    required this.totals,
    this.note,
  });

  factory PosPurchaseDocumentPaper.receipt(PosPurchaseReceipt r) {
    final m = PosDocumentViews.money;
    return PosPurchaseDocumentPaper._(
      kindLabel: 'PHIẾU NHẬP HÀNG',
      code: r.receiptNo,
      status: r.status,
      meta: [
        ('Ngày nhập', PosDocumentViews.fmtDate(r.importDate ?? r.createdAt)),
        ('Nhà cung cấp', _supplier(r.supplierCode, r.supplierName)),
        if ((r.inputInvoiceNo ?? '').isNotEmpty)
          ('Số HĐ đầu vào', [if ((r.inputInvoiceSerial ?? '').isNotEmpty) r.inputInvoiceSerial!, r.inputInvoiceNo!].join(' · ')),
        if (r.inputInvoiceDate != null) ('Ngày HĐ', DateFormat('dd/MM/yyyy').format(r.inputInvoiceDate!)),
        if ((r.purchaseOrderNo ?? '').isNotEmpty) ('Đơn đặt hàng', r.purchaseOrderNo!),
        ('Người nhập', (r.importedBy ?? r.createdBy ?? '').isEmpty ? '—' : (r.importedBy ?? r.createdBy)!),
      ],
      lines: r.lines,
      note: r.note,
      totals: [
        ('Tổng tiền hàng (${PosDocumentViews.qtyFmt.format(r.totalQty)} SP)', m.format(r.totalCost), false),
        if (r.discountAmount > 0) ('Giảm giá', '-${m.format(r.discountAmount)}', false),
        if (r.totalVat > 0) ('Thuế VAT', m.format(r.totalVat), false),
        ('Cần trả NCC', m.format(r.grandTotal), true),
        ('Đã trả NCC', m.format(r.paidAmount), false),
        if (r.balanceDue > 0.5) ('Còn nợ NCC', m.format(r.balanceDue), false),
      ],
    );
  }

  factory PosPurchaseDocumentPaper.purchaseReturn(PosPurchaseReturn r) {
    final m = PosDocumentViews.money;
    return PosPurchaseDocumentPaper._(
      kindLabel: 'PHIẾU TRẢ HÀNG NHẬP',
      code: r.returnNo,
      status: r.status,
      meta: [
        ('Ngày trả', PosDocumentViews.fmtDate(r.returnDate)),
        ('Nhà cung cấp', _supplier(null, r.supplierName)),
        if ((r.sourceReceiptNo ?? '').isNotEmpty) ('Theo phiếu nhập', r.sourceReceiptNo!),
        ('Người trả', (r.returnedBy ?? r.createdBy ?? '').isEmpty ? '—' : (r.returnedBy ?? r.createdBy)!),
      ],
      lines: r.lines,
      note: r.note,
      totals: [
        ('Tổng tiền hàng trả', m.format(r.totalAmount), false),
        if (r.discountAmount > 0) ('Giảm giá', '-${m.format(r.discountAmount)}', false),
        // refundDue (server) = tổng trả − giảm giá − NCC đã hoàn = phần NCC CÒN phải hoàn.
        ('Giá trị trả NCC', m.format(r.totalAmount - r.discountAmount), true),
        ('NCC đã hoàn tiền', m.format(r.refundReceived), false),
        if (r.refundDue > 0.5) ('NCC còn phải hoàn', m.format(r.refundDue), false),
      ],
    );
  }

  static String _supplier(String? code, String? name) {
    final n = (name ?? '').trim();
    final c = (code ?? '').trim();
    if (n.isEmpty && c.isEmpty) return '—';
    return c.isEmpty ? n : '$n ($c)';
  }

  final String kindLabel;
  final String code;
  final String status;
  final List<(String, String)> meta;
  final List<PosPurchaseLine> lines;
  final List<(String, String, bool)> totals;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final cancelled = status == 'Cancelled';
    return LayoutBuilder(builder: (context, c) {
      final compact = c.maxWidth < 520;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Đầu phiếu
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          color: cancelled ? Colors.red.shade50.withValues(alpha: 0.55) : const Color(0xFFFAFBFC),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(kindLabel),
                      style: const TextStyle(
                          fontSize: 11, letterSpacing: 0.6, color: PosTheme.textSecondary, fontWeight: FontWeight.w600)),
                  Text(code,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: cancelled ? Colors.red.shade700 : PosTheme.kiotBlue,
                        decoration: cancelled ? TextDecoration.lineThrough : null,
                      )),
                ]),
              ),
              _StatusChip(status: status),
            ]),
            const SizedBox(height: 8),
            for (final (k, v) in meta) _MetaRow(label: k, value: v),
          ]),
        ),
        const Divider(height: 1, color: PosTheme.border),
        // Bảng hàng
        if (lines.isEmpty)
          Padding(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: Text(tr('Phiếu không có dòng hàng'), style: const TextStyle(color: PosTheme.textSecondary)),
            ),
          )
        else ...[
          if (!compact) const _LineHeader(),
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0) const Divider(height: 1, indent: 12, endIndent: 12, color: PosTheme.border),
            compact ? _LineCompact(index: i + 1, line: lines[i]) : _LineWide(index: i + 1, line: lines[i]),
          ],
        ],
        // Tổng
        Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
          decoration: const BoxDecoration(
            color: Color(0xFFFAFBFC),
            border: Border(top: BorderSide(color: PosTheme.border)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if ((note ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(tr('Ghi chú: ${note!.trim()}'),
                    style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
              ),
            for (final (k, v, bold) in totals)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  Expanded(
                    child: Text(tr(k),
                        style: TextStyle(
                            fontSize: bold ? 14 : 13,
                            fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
                            color: bold ? null : PosTheme.textSecondary)),
                  ),
                  Text(v,
                      style: TextStyle(
                          fontSize: bold ? 15 : 13,
                          fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                          color: bold ? PosTheme.kiotBlue : null)),
                ]),
              ),
          ]),
        ),
      ]);
    });
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final color = PosDocumentViews.statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(tr(PosDocumentViews.statusLabel(status)),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 120,
            child: Text(tr(label), style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
          ),
          Expanded(child: Text(tr(value), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ]),
      );
}

const _wStt = 28.0;
const _wQty = 64.0;
const _wPrice = 96.0;
const _wTotal = 104.0;
const _hdrStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: PosTheme.textSecondary);

class _LineHeader extends StatelessWidget {
  const _LineHeader();

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFFF5F7FA),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(children: [
          SizedBox(width: _wStt, child: Text(tr('STT'), style: _hdrStyle)),
          Expanded(child: Text(tr('Mặt hàng'), style: _hdrStyle)),
          SizedBox(width: _wQty, child: Text(tr('SL'), style: _hdrStyle, textAlign: TextAlign.right)),
          SizedBox(width: _wPrice, child: Text(tr('Đơn giá'), style: _hdrStyle, textAlign: TextAlign.right)),
          SizedBox(width: _wTotal, child: Text(tr('Thành tiền'), style: _hdrStyle, textAlign: TextAlign.right)),
        ]),
      );
}

String _lineExtra(PosPurchaseLine l) => [
      if ((l.lotNo ?? '').isNotEmpty) 'Lô ${l.lotNo}',
      if (l.expiryDate != null) 'HSD ${DateFormat('dd/MM/yyyy').format(l.expiryDate!)}',
      if (l.discountAmount > 0) 'Giảm ${PosDocumentViews.money.format(l.discountAmount)}',
      if (l.serialNumbers.isNotEmpty) 'Seri: ${l.serialNumbers.join(', ')}',
      if ((l.lineNote ?? '').isNotEmpty) l.lineNote!,
    ].join(' · ');

class _LineWide extends StatelessWidget {
  const _LineWide({required this.index, required this.line});
  final int index;
  final PosPurchaseLine line;

  @override
  Widget build(BuildContext context) {
    final m = PosDocumentViews.money;
    final extra = _lineExtra(line);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: _wStt, child: Text('$index', style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(line.productName), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            Text(tr([line.productCode, if ((line.unitName ?? '').isNotEmpty) line.unitName!].join(' · ')),
                style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary)),
            if (extra.isNotEmpty)
              Text(tr(extra), style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary)),
          ]),
        ),
        SizedBox(
            width: _wQty,
            child: Text(PosDocumentViews.qtyFmt.format(line.qty),
                style: const TextStyle(fontSize: 13), textAlign: TextAlign.right)),
        SizedBox(
            width: _wPrice,
            child: Text(m.format(line.costPrice), style: const TextStyle(fontSize: 13), textAlign: TextAlign.right)),
        SizedBox(
            width: _wTotal,
            child: Text(m.format(line.lineTotal),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
      ]),
    );
  }
}

class _LineCompact extends StatelessWidget {
  const _LineCompact({required this.index, required this.line});
  final int index;
  final PosPurchaseLine line;

  @override
  Widget build(BuildContext context) {
    final m = PosDocumentViews.money;
    final extra = _lineExtra(line);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('$index. ${line.productName}'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Row(children: [
          Expanded(
            child: Text(
              tr('${PosDocumentViews.qtyFmt.format(line.qty)}${(line.unitName ?? '').isNotEmpty ? ' ${line.unitName}' : ''}'
                  ' × ${m.format(line.costPrice)}'),
              style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
            ),
          ),
          Text(m.format(line.lineTotal), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        ]),
        if (extra.isNotEmpty)
          Text(tr(extra), style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary)),
      ]),
    );
  }
}

/// Tờ phiếu thu / chi: loại phiếu, mã, ngày, người nộp / nhận, lý do, số tiền + bằng chữ, người lập.
class PosCashVoucherPaper extends StatelessWidget {
  const PosCashVoucherPaper({super.key, required this.data, required this.tx, required this.income});

  final Map<String, dynamic> data;
  final CashTransaction? tx;
  final bool income;

  String _s(String a, String b) => '${data[a] ?? data[b] ?? ''}'.trim();

  @override
  Widget build(BuildContext context) {
    final m = PosDocumentViews.money;
    final amount = tx?.amount ??
        (data['amount'] is num
            ? (data['amount'] as num).toDouble()
            : double.tryParse('${data['amount']}') ?? 0);
    final code = tx?.transactionCode ?? _s('transactionCode', 'TransactionCode');
    final date = tx?.transactionDate ?? parseApiUtcDateTime(_s('transactionDate', 'TransactionDate'));
    final party = [tx?.contactName ?? _s('contactName', 'ContactName'), tx?.contactPhone ?? '']
        .where((s) => s.trim().isNotEmpty)
        .join(' · ');
    final reason = tx?.description ?? _s('description', 'Description');
    final category = tx?.categoryName ?? _s('categoryName', 'category');
    final method = tx != null
        ? [tx!.paymentMethod.label, if ((tx!.bankAccountName ?? '').isNotEmpty) tx!.bankAccountName!].join(' · ')
        : _s('paymentMethod', 'PaymentMethod');
    final creator = tx?.createdByUserName ?? _s('createdByUserName', 'CreatedByUserName');
    final source = tx != null && tx!.sourceLabel.isNotEmpty ? tx!.sourceLabel : '';
    final rawNote = tx?.internalNote ?? _s('internalNote', 'InternalNote');
    // Ghi chú máy sinh để liên kết chứng từ («pos bán hàng #<guid>|0») — không hiện cho người dùng.
    final note = RegExp(r'#[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-').hasMatch(rawNote) ? '' : rawNote;
    final color = income ? SboxColors.successText : const Color(0xFFB42318);
    final words = vietnameseMoneyInWords(amount.round());

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        color: const Color(0xFFFAFBFC),
        child: Column(children: [
          Text(tr(income ? 'PHIẾU THU' : 'PHIẾU CHI'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1, color: color)),
          const SizedBox(height: 2),
          Text(tr('Số: ${code.isEmpty ? '—' : code}'),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          Text(tr('Ngày: ${date == null ? '—' : PosDocumentViews.fmtDate(date)}'),
              style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
        ]),
      ),
      const Divider(height: 1, color: PosTheme.border),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _MetaRow(label: income ? 'Người nộp' : 'Người nhận', value: party.isEmpty ? '—' : party),
          _MetaRow(label: 'Lý do', value: reason.isEmpty ? '—' : reason),
          if (category.isNotEmpty) _MetaRow(label: 'Loại thu chi', value: category),
          if (method.isNotEmpty) _MetaRow(label: 'Hình thức', value: method),
          if (source.isNotEmpty) _MetaRow(label: 'Chứng từ gốc', value: source),
          if (note.isNotEmpty) _MetaRow(label: 'Ghi chú', value: note),
          if (creator.isNotEmpty) _MetaRow(label: 'Người lập', value: creator),
        ]),
      ),
      Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 14),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(tr('Số tiền'), style: const TextStyle(fontSize: 13, color: PosTheme.textSecondary))),
            Text('${income ? '+' : '-'}${m.format(amount)} đ',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          ]),
          if (words.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(tr('Bằng chữ: $words'),
                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: PosTheme.textSecondary)),
            ),
        ]),
      ),
    ]);
  }
}
