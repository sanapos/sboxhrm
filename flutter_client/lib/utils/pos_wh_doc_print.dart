import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/pos_purchase.dart';
import '../models/pos_stock_count.dart';
import '../models/pos_stock_issue_doc.dart';
import '../providers/auth_provider.dart';
import '../widgets/pos/pos_stock_issue_config.dart';
import '../widgets/pos/pos_stock_issue_helpers.dart';
import '../models/pos_print_template.dart';
import 'pos_purchase_receipt_print.dart';
import 'pos_sheet_document_print.dart';
import 'pos_simple_doc_print.dart';
import 'pos_stock_count_print.dart';

/// In phiếu kho (nhập, trả hàng nhập, kiểm kho, xuất hủy / dùng nội bộ) — dùng chung cho
/// màn danh sách dạng bảng và màn chi tiết phiếu dạng mobile (C20, điện thoại).

final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
final _qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'vi_VN');

String _branchName(BuildContext context) =>
    Provider.of<AuthProvider>(context, listen: false).currentUser?.department ?? '';

Future<void> printPurchaseReceiptDoc(BuildContext context, PosPurchaseReceipt r) {
  final auth = Provider.of<AuthProvider>(context, listen: false);
  return printPosPurchaseReceipt(
    context: context,
    receiptNo: r.receiptNo,
    importDate: r.importDate?.toLocal() ?? r.createdAt?.toLocal() ?? DateTime.now(),
    branchName: auth.currentUser?.department,
    createdBy: r.createdBy ?? auth.currentUser?.fullName,
    supplierName: r.supplierName,
    inputInvoiceNo: r.inputInvoiceNo,
    note: r.note,
    status: r.status,
    linesTotal: r.totalCost,
    totalVat: r.totalVat,
    discountAmount: r.discountAmount,
    discountIsPercent: r.discountIsPercent,
    discountInput: r.discountInput,
    paidAmount: r.paidAmount,
    grandTotal: r.grandTotal != 0 ? r.grandTotal : r.totalCost + r.totalVat - r.discountAmount,
    lines: r.lines,
    purchaseOrderNo: r.purchaseOrderNo,
  );
}

/// Số NCC cần hoàn của phiếu trả hàng nhập.
double purchaseReturnSupplierOwed(PosPurchaseReturn r) {
  if (r.supplierRefundAmount > 0) return r.supplierRefundAmount;
  return r.totalAmount - r.discountAmount;
}

Future<void> printPurchaseReturnDoc(BuildContext context, PosPurchaseReturn r) async {
  // Mẫu in A4/A5 «Trả hàng nhập» của cửa hàng; lỗi dựng mẫu → bảng PDF đơn giản bên dưới.
  try {
    final owed = purchaseReturnSupplierOwed(r);
    await printPosSheetDocument(
      context,
      documentType: PosPrintDocumentTypes.purchaseReturn,
      title: 'Phiếu trả hàng nhập ${r.returnNo}',
      referenceNo: r.returnNo,
      referenceId: r.id,
      lines: posPurchaseLinesPrintData(r.lines),
      data: {
        ...posSheetDateData(r.returnDate),
        'Ma_Don_Hang': r.returnNo,
        'Nha_Cung_Cap': r.supplierName ?? '',
        'Ma_Phieu_Goc': r.sourceReceiptNo ?? '',
        'Chi_Nhanh': _branchName(context),
        'Nguoi_Lap': r.createdBy ?? '',
        'Ghi_Chu': r.note ?? '',
        'Tong_So_Luong': posSheetQty(r.lines.fold<double>(0, (a, l) => a + l.qty)),
        'Tong_Tien_Hang': posSheetMoney(r.totalAmount),
        'Chiet_Khau_Hoa_Don': posSheetMoney(r.discountAmount),
        'Tong_Cong': posSheetMoney(owed),
        'Tong_Cong_Bang_Chu': posSheetMoneyWords(owed),
        'NCC_Da_Hoan': posSheetMoney(r.refundReceived),
        'Con_Lai': posSheetMoney(owed - r.refundReceived),
      },
    );
    return;
  } catch (e) {
    debugPrint('printPurchaseReturnDoc (mẫu in) lỗi, dùng PDF: $e');
  }
  if (!context.mounted) return;
  final when = r.returnDate?.toLocal();
  final statusLabel = switch (r.status) {
    'Draft' => 'Phiếu tạm',
    'Completed' => 'Đã trả hàng',
    'Cancelled' => 'Đã hủy',
    _ => r.status,
  };
  await printPosSimpleDoc(
    context,
    title: 'PHIẾU TRẢ HÀNG NHẬP',
    docNo: r.returnNo,
    statusLabel: statusLabel,
    infoLines: [
      if (when != null) 'Ngày trả: ${_dateFmt.format(when)}',
      'Nhà cung cấp: ${r.supplierName ?? '—'}',
      if (r.sourceReceiptNo != null && r.sourceReceiptNo!.isNotEmpty) 'Từ phiếu nhập: ${r.sourceReceiptNo}',
      'Người tạo: ${r.createdBy ?? '—'}',
    ],
    headers: const ['STT', 'Mã hàng', 'Tên hàng', 'SL', 'Giá trả lại', 'Giảm giá', 'Thành tiền'],
    rows: [
      for (var i = 0; i < r.lines.length; i++)
        [
          '${i + 1}',
          r.lines[i].productCode,
          '${r.lines[i].productName}${r.lines[i].unitName?.isNotEmpty == true ? ' (${r.lines[i].unitName})' : ''}',
          r.lines[i].qty.toStringAsFixed(r.lines[i].qty == r.lines[i].qty.roundToDouble() ? 0 : 2),
          _moneyFmt.format(r.lines[i].costPrice),
          _moneyFmt.format(r.lines[i].discountAmount),
          _moneyFmt.format(r.lines[i].lineTotal),
        ],
    ],
    totalLines: [
      'Tổng tiền hàng: ${_moneyFmt.format(r.totalAmount)} đ',
      'Giảm giá: ${_moneyFmt.format(r.discountAmount)} đ',
      'NCC đã trả: ${_moneyFmt.format(r.refundReceived)} đ',
      'NCC cần trả: ${_moneyFmt.format(purchaseReturnSupplierOwed(r))} đ',
    ],
    note: r.note,
  );
}

Future<void> printStockIssueDoc(BuildContext context, PosStockIssueDoc doc, PosStockIssueConfig config) async {
  // Mẫu in A4/A5 «Xuất kho» (mẫu 02-VT) của cửa hàng; lỗi dựng mẫu → bảng PDF đơn giản bên dưới.
  try {
    await printPosSheetDocument(
      context,
      documentType: PosPrintDocumentTypes.stockIssue,
      title: '${config.title} ${doc.issueNo}',
      referenceNo: doc.issueNo,
      referenceId: doc.id,
      lines: posStockIssueLinesPrintData(doc.lines),
      data: posStockIssuePrintData(doc, config.title),
    );
    return;
  } catch (e) {
    debugPrint('printStockIssueDoc (mẫu in) lỗi, dùng PDF: $e');
  }
  if (!context.mounted) return;
  final when = (doc.issuedAt ?? doc.createdAt)?.toLocal();
  await printPosSimpleDoc(
    context,
    title: 'PHIẾU ${config.title.toUpperCase()}',
    docNo: doc.issueNo,
    statusLabel: stockIssueStatusLabel(doc.status),
    infoLines: [
      if (when != null) 'Ngày: ${_dateFmt.format(when)}',
      'Người tạo: ${doc.createdBy ?? '—'}',
      if (doc.categoryName != null && doc.categoryName!.isNotEmpty) 'Loại xuất: ${doc.categoryName}',
      if (doc.recipientName != null && doc.recipientName!.isNotEmpty) 'Người nhận: ${doc.recipientName}',
    ],
    headers: const ['STT', 'Mã hàng', 'Tên hàng', 'SL', 'Giá vốn', 'Thành tiền'],
    rows: [
      for (var i = 0; i < doc.lines.length; i++)
        [
          '${i + 1}',
          doc.lines[i].productCode,
          '${doc.lines[i].productName}${doc.lines[i].unitName?.isNotEmpty == true ? ' (${doc.lines[i].unitName})' : ''}',
          _qtyFmt.format(doc.lines[i].qty),
          _moneyFmt.format(doc.lines[i].costPrice),
          _moneyFmt.format(doc.lines[i].lineTotal),
        ],
    ],
    totalLines: ['Tổng SL: ${_qtyFmt.format(doc.totalQty)}', 'Tổng giá trị: ${_moneyFmt.format(doc.totalValue)} đ'],
    note: doc.note,
  );
}

Future<void> printStockCountDoc(BuildContext context, PosStockCount count) =>
    printPosStockCount(context: context, count: count, branchName: _branchName(context));
