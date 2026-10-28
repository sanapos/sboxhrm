import 'package:flutter/material.dart';

import '../models/cash_transaction.dart';
import '../models/pos_print_template.dart';
import 'pos_sheet_document_print.dart';

/// In phiếu thu / phiếu chi (mẫu 01-TT / 02-TT, A4 hoặc A5 ngang) theo mẫu in của cửa hàng.
Future<void> printCashTransactionVoucher(BuildContext context, CashTransaction t) {
  final receipt = t.type == CashTransactionType.income;
  final method = t.paymentMethod.label +
      ((t.bankAccountName ?? '').trim().isEmpty ? '' : ' · ${t.bankAccountName!.trim()}');
  return printPosSheetDocument(
    context,
    documentType: receipt ? PosPrintDocumentTypes.cashReceipt : PosPrintDocumentTypes.cashPayment,
    title: '${receipt ? 'Phiếu thu' : 'Phiếu chi'} ${t.transactionCode}',
    referenceNo: t.transactionCode,
    referenceId: t.id,
    data: {
      ...posSheetDateData(t.paidDate ?? t.transactionDate),
      'Ma_Don_Hang': t.transactionCode,
      'Nguoi_Nop_Nhan': t.contactName ?? '',
      'SDT_Nguoi_Nop_Nhan': t.contactPhone ?? '',
      'Ly_Do': t.description,
      'Loai_Thu_Chi': t.categoryName,
      'Ma_Chung_Tu_Goc': t.isLinked ? t.sourceLabel : '',
      'Hinh_Thuc_Thanh_Toan': method,
      'So_Tien': posSheetMoney(t.amount),
      'So_Tien_Bang_Chu': posSheetMoneyWords(t.amount),
      // Bộ render thay chữ «…đồng chẵn» bằng tổng bằng chữ — giữ trùng số tiền phiếu.
      'Tong_Cong_Bang_Chu': posSheetMoneyWords(t.amount),
      'Nguoi_Lap': t.createdByUserName,
    },
  );
}
