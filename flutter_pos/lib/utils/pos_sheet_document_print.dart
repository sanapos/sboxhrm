import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

import '../models/pos_print_template.dart';
import '../models/pos_purchase.dart';
import '../models/pos_sale_order.dart';
import '../models/pos_stock_issue_doc.dart';
import '../services/api_service.dart';
import 'api_datetime.dart';
import 'pos_html_print.dart';
import 'pos_print_store_info.dart';
import 'pos_print_template_defaults.dart';
import 'pos_print_template_loader.dart';
import 'pos_print_template_renderer.dart';
import 'pos_vietnamese_money_words.dart';

/// In chứng từ khổ trang (A4/A5, máy in mực) theo mẫu in của cửa hàng:
/// nhập hàng, trả hàng nhập, chuyển hàng, xuất kho, phiếu thu / chi…
/// Cửa hàng chưa có mẫu A4/A5 cho loại này → dùng mẫu chuẩn A4 (cùng nguồn PrintTemplates/Sheet với máy chủ).

final _money = NumberFormat('#,##0', 'vi_VN');
final _qty = NumberFormat('#,##0.###', 'vi_VN');

String posSheetMoney(num? v) => _money.format(v ?? 0);
String posSheetQty(num? v) => _qty.format(v ?? 0);

/// Ngày giờ chứng từ: Ngay / Gio / Ngay_So / Thang / Nam (mẫu kế toán «Ngày … tháng … năm …»).
Map<String, String> posSheetDateData(DateTime? when) {
  final d = (when ?? DateTime.now()).toLocal();
  return {
    'Ngay': DateFormat('dd/MM/yyyy').format(d),
    'Gio': DateFormat('HH:mm').format(d),
    'Ngay_So': DateFormat('dd').format(d),
    'Thang': DateFormat('MM').format(d),
    'Nam': '${d.year}',
  };
}

String posSheetMoneyWords(num? amount) {
  final v = (amount ?? 0).abs().round();
  return v == 0 ? '' : vietnameseMoneyInWords(v);
}

final _unfilledToken = RegExp(r'\{[A-Z][A-Za-z0-9_]*\}');

/// Mã trường chứng từ không có dữ liệu (mẫu cửa hàng tự thêm, phiếu thiếu trường) → để trống, không in «{Ma_Truong}».
String posSheetDropUnfilledTokens(String html) => html.replaceAll(_unfilledToken, '');

bool _isPageTemplate(PosPrintTemplate t) {
  if (!t.isActive || t.isDocx) return false;
  if (t.paperSize != PosPrintPaperSizes.a4 && t.paperSize != PosPrintPaperSizes.a5) return false;
  final html = t.htmlContent.trimLeft();
  return html.isNotEmpty && !html.startsWith('<!--POS_TEMPLATE_V2');
}

/// Mẫu A4/A5 cửa hàng dùng cho [documentType]: mẫu mặc định nếu là khổ trang, không thì mẫu khổ trang đầu tiên.
Future<PosPrintTemplate?> resolvePosSheetTemplate(String documentType) async {
  List<PosPrintTemplate> list;
  try {
    list = await loadPosPrintTemplates(ApiService(), documentType);
  } catch (_) {
    return null;
  }
  final pages = list.where(_isPageTemplate).toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  if (pages.isEmpty) return null;
  return pages.firstWhere((t) => t.isDefault, orElse: () => pages.first);
}

/// Dựng HTML chứng từ khổ trang đã điền dữ liệu (kèm khung trang A4/A5).
Future<({String html, String paperSize})> renderPosSheetDocument({
  required String documentType,
  required Map<String, String> data,
  List<Map<String, String>> lines = const [],
}) async {
  final tpl = await resolvePosSheetTemplate(documentType);
  final paper = tpl?.paperSize ?? PosPrintPaperSizes.a4;
  final templateHtml =
      tpl?.htmlContent ?? posPrintDefaultHtml(documentType: documentType, paperSize: paper);
  final store = await PosPrintStoreInfo.load();
  final merged = <String, String>{
    'Ten_Cua_Hang': store.storeName ?? '',
    'Dia_Chi_Chi_Nhanh': store.address ?? '',
    'Dien_Thoai_Chi_Nhanh': store.phone ?? '',
    'Tieu_De_In': (PosPrintDocumentTypes.all[documentType] ?? '').toUpperCase(),
    ...posSheetDateData(null),
    ...data,
  };
  // Cột STT tự đánh số khi dữ liệu dòng chưa có.
  final numbered = [
    for (var i = 0; i < lines.length; i++) {'STT': '${i + 1}', ...lines[i]},
  ];
  final html = renderPosPrintTemplateHtml(
    templateHtml,
    data: merged,
    lineItems: numbered,
    paperSize: paper,
  );
  return (html: posSheetDropUnfilledTokens(html), paperSize: paper);
}

/// Xem trước + in chứng từ khổ trang (hộp in hệ thống / máy in A4 qua Print Agent).
Future<void> printPosSheetDocument(
  BuildContext context, {
  required String documentType,
  required String title,
  required Map<String, String> data,
  List<Map<String, String>> lines = const [],
  String? referenceNo,
  String? referenceId,
}) async {
  final doc = await renderPosSheetDocument(documentType: documentType, data: data, lines: lines);
  if (!context.mounted) return;
  await showPosHtmlPrintDialog(
    context,
    title: '$title · ${doc.paperSize}',
    htmlDocument: doc.html,
    a4Paper: doc.paperSize == PosPrintPaperSizes.a4,
    agentPagePrint: true,
    agentDocumentType: documentType,
    referenceNo: referenceNo,
    referenceId: referenceId,
  );
}

/// Hỏi in loại chứng từ nào (vd phiếu nhập nháp: «Nhập hàng» hay «Đặt hàng nhập»). Null = hủy.
Future<String?> pickPosSheetDocumentType(BuildContext context, List<String> documentTypes) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(tr('Chọn mẫu in')),
      children: [
        for (final t in documentTypes)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, t),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                const Icon(Icons.print_outlined, size: 20),
                const SizedBox(width: 12),
                Text(tr(PosPrintDocumentTypes.all[t] ?? t)),
              ]),
            ),
          ),
      ],
    ),
  );
}

/// In đơn bán thành chứng từ khổ trang khác hóa đơn (đơn đặt hàng / phiếu giao hàng) theo mẫu A4/A5
/// của cửa hàng. Không ghi đếm lần in hóa đơn.
Future<void> printPosSaleSheet(BuildContext context, PosSaleOrder order, String documentType) async {
  final tpl = await resolvePosSheetTemplate(documentType);
  final paper = tpl?.paperSize ?? PosPrintPaperSizes.a4;
  final templateHtml =
      tpl?.htmlContent ?? posPrintDefaultHtml(documentType: documentType, paperSize: paper);
  final store = await PosPrintStoreInfo.load();
  final html = renderSaleOrderTemplate(
    templateHtml,
    order,
    storeName: store.storeName,
    storeAddress: store.address,
    storePhone: store.phone,
    paperSize: paper,
  );
  if (!context.mounted) return;
  await showPosHtmlPrintDialog(
    context,
    title: '${PosPrintDocumentTypes.all[documentType] ?? ''} ${order.orderNo} · $paper',
    htmlDocument: posSheetDropUnfilledTokens(html),
    a4Paper: paper == PosPrintPaperSizes.a4,
    agentPagePrint: true,
    agentDocumentType: documentType,
    referenceNo: order.orderNo,
    referenceId: order.id,
  );
}

/// Dòng hàng phiếu nhập / trả hàng nhập → token dòng mẫu in.
List<Map<String, String>> posPurchaseLinesPrintData(List<PosPurchaseLine> lines) {
  final dateFmt = DateFormat('dd/MM/yyyy');
  return [
    for (final l in lines)
      {
        'Ma_Hang': l.productCode,
        'Ten_Hang_Hoa': l.productName,
        'Ten_Hang_Goc': l.productName,
        'Don_Vi_Tinh': l.unitName ?? '',
        'So_Luong': posSheetQty(l.qty),
        'Don_Gia': posSheetMoney(l.costPrice),
        'Chiet_Khau': posSheetMoney(l.discountAmount),
        'Thanh_Tien': posSheetMoney(l.lineTotal),
        'Ghi_Chu': [
          if ((l.lotNo ?? '').trim().isNotEmpty) 'Lô ${l.lotNo!.trim()}',
          if (l.expiryDate != null) 'HSD ${dateFmt.format(l.expiryDate!.toLocal())}',
          if (l.serialNumbers.isNotEmpty) 'Serial: ${l.serialNumbers.join(', ')}',
          if ((l.lineNote ?? '').trim().isNotEmpty) l.lineNote!.trim(),
        ].join(' · '),
      },
  ];
}

/// Dòng phiếu xuất kho → token dòng mẫu in.
List<Map<String, String>> posStockIssueLinesPrintData(List<PosStockIssueLine> lines) => [
      for (final l in lines)
        {
          'Ma_Hang': l.productCode,
          'Ten_Hang_Hoa': l.productName,
          'Ten_Hang_Goc': l.productName,
          'Don_Vi_Tinh': l.unitName ?? '',
          'So_Luong': posSheetQty(l.qty),
          'Don_Gia': posSheetMoney(l.costPrice),
          'Thanh_Tien': posSheetMoney(l.lineTotal),
          'Ghi_Chu': l.serialNumbers.isEmpty ? '' : 'Serial: ${l.serialNumbers.join(', ')}',
        },
    ];

/// Dữ liệu chung phiếu xuất kho (mẫu 02-VT). [kindTitle] = tên loại xuất (Xuất hủy, Xuất dùng nội bộ…).
Map<String, String> posStockIssuePrintData(PosStockIssueDoc doc, String kindTitle) => {
      ...posSheetDateData(doc.issuedAt ?? doc.completedAt ?? doc.createdAt),
      'Ma_Don_Hang': doc.issueNo,
      'Nguoi_Nhan': doc.recipientName ?? '',
      'Ly_Do': [kindTitle, if ((doc.categoryName ?? '').trim().isNotEmpty) doc.categoryName!.trim()].join(' — '),
      'Nguoi_Lap': doc.issuedBy ?? doc.createdBy ?? '',
      'Ghi_Chu': doc.note ?? '',
      'Tong_So_Luong': posSheetQty(doc.totalQty),
      'Tong_Cong': posSheetMoney(doc.totalValue),
      'Tong_Cong_Bang_Chu': posSheetMoneyWords(doc.totalValue),
    };

/// Phiếu chuyển hàng — JSON phiếu từ /api/branch-ops/transfers.
Future<void> printPosStockTransferSheet(BuildContext context, Map<String, dynamic> transfer) {
  num n(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;
  String when(Object? v) {
    final d = v == null ? null : parseApiUtcDateTime(v);
    return d == null ? '' : DateFormat('dd/MM/yyyy HH:mm').format(d.toLocal());
  }

  final rawLines = [
    for (final l in (transfer['lines'] as List? ?? const [])) Map<String, dynamic>.from(l as Map),
  ];
  num totalValue = 0;
  final lines = <Map<String, String>>[];
  for (final l in rawLines) {
    final price = n(l['unitCost'] ?? l['costPrice'] ?? l['price']);
    final value = price * n(l['qty']);
    totalValue += value;
    lines.add({
      'Ma_Hang': '${l['sku'] ?? l['productCode'] ?? ''}',
      'Ten_Hang_Hoa': '${l['productName'] ?? ''}',
      'Ten_Hang_Goc': '${l['productName'] ?? ''}',
      'Don_Vi_Tinh': '${l['unit'] ?? ''}',
      'So_Luong': posSheetQty(n(l['qty'])),
      'SL_Nhan': l['receivedQty'] == null ? '' : posSheetQty(n(l['receivedQty'])),
      'Don_Gia': price == 0 ? '' : posSheetMoney(price),
      'Thanh_Tien': price == 0 ? '' : posSheetMoney(value),
    });
  }
  final received = rawLines.any((l) => l['receivedQty'] != null);
  final created = transfer['createdAt'] == null ? null : parseApiUtcDateTime(transfer['createdAt']);
  final no = '${transfer['transferNo'] ?? ''}';
  return printPosSheetDocument(
    context,
    documentType: PosPrintDocumentTypes.stockTransfer,
    title: 'Phiếu chuyển hàng $no',
    referenceNo: no,
    referenceId: transfer['id']?.toString(),
    lines: lines,
    data: {
      ...posSheetDateData(created),
      'Ma_Don_Hang': no,
      'Trang_Thai': '${transfer['statusLabel'] ?? ''}',
      'Kho_Di': '${transfer['fromBranchName'] ?? ''}',
      'Kho_Den': '${transfer['toBranchName'] ?? ''}',
      'Ngay_Chuyen': when(transfer['sentAt']),
      'Ngay_Nhan': when(transfer['receivedAt']),
      'Nguoi_Lap': '${transfer['createdByName'] ?? ''}',
      'Nguoi_Nhan': '${transfer['receivedByName'] ?? ''}',
      'Ghi_Chu': '${transfer['note'] ?? ''}',
      'Tong_So_Luong': posSheetQty(n(transfer['totalQty'])),
      'Tong_SL_Nhan': received
          ? posSheetQty(rawLines.fold<num>(0, (a, l) => a + n(l['receivedQty'])))
          : '',
      'Tong_Cong': totalValue == 0 ? '' : posSheetMoney(totalValue),
    },
  );
}
