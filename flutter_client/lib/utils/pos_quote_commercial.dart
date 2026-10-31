import 'package:flutter/material.dart';

import '../l10n/app_tr.dart';
import '../models/pos_quote.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_theme.dart';
import 'pos_busy.dart';

const posQuotePackageKinds = [
  'Contract',
  'PaymentRequest',
  'Handover',
  'Acceptance',
];

/// Lập chứng từ thương mại. Báo giá chưa gửi vẫn lập được — máy chủ tự nhận.
/// Không hỏi ghi chú nữa (người dùng không biết ghi chú để làm gì): cần thì sửa sau ở menu chứng từ
/// → «Ghi chú in trên chứng từ».
Future<PosQuoteDocument?> createPosQuoteCommercialDoc(
  BuildContext context, {
  required PosQuote quote,
  required String kind,
  bool includeImages = false,
  String? note,
}) async {
  final api = ApiService();
  final current = quote;
  final resolvedNote = note;

  if (!context.mounted || PosBusy.isBusy('create-doc')) return null;
  // Khung «Đang lập …» + chặn bấm lặp (bấm 2 lần từng tạo 2 hợp đồng).
  final res = await PosBusy.run(
    context,
    () => kind == 'StockIssue'
        ? api.createPosQuoteStockIssue(
            current.id,
            note: resolvedNote,
            includeImages: includeImages,
          )
        : api.createPosQuoteDocument(
            current.id,
            kind,
            note: resolvedNote,
            includeImages: includeImages,
          ),
    label: 'Đang lập ${PosQuoteDocument.kindLabel(kind).toLowerCase()}…',
    key: 'create-doc',
  );
  if (res == null) return null;
  if (res['isSuccess'] != true || res['data'] is! Map) {
    NotificationOverlayManager().showError(
      title: 'Lập chứng từ thất bại',
      message: res['message']?.toString() ?? tr('Không tạo được'),
    );
    return null;
  }
  final doc = PosQuoteDocument.fromJson(
      Map<String, dynamic>.from(res['data'] as Map));
  NotificationOverlayManager().showSuccess(
    title: PosQuoteDocument.kindLabel(kind),
    message: doc.docNo,
  );
  return doc;
}

/// Lập HĐ + đề nghị tạm ứng + bàn giao + nghiệm thu (bỏ qua loại đã có).
Future<bool> createPosQuoteCommercialPackage(
  BuildContext context, {
  required PosQuote quote,
  bool includeImages = false,
}) async {
  // Chỉ xác nhận — không hỏi ghi chú (sửa sau ở từng chứng từ).
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Tạo trọn bộ hồ sơ?')),
      content: Text(tr('Sẽ lập (nếu chưa có): hợp đồng, đề nghị tạm ứng, biên bản bàn giao, biên bản nghiệm thu.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Tạo hồ sơ'))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;

  final api = ApiService();
  var current = quote;

  final detailRes = await api.getPosQuote(current.id);
  if (detailRes['isSuccess'] == true && detailRes['data'] is Map) {
    current = PosQuote.fromJson(
        Map<String, dynamic>.from(detailRes['data'] as Map));
  }
  final existing = current.documents.map((d) => d.kind).toSet();
  var created = 0;
  if (!context.mounted) return false;
  for (final kind in posQuotePackageKinds) {
    if (existing.contains(kind)) continue;
    if (!context.mounted) return created > 0;
    final doc = await createPosQuoteCommercialDoc(
      context,
      quote: current,
      kind: kind,
      includeImages: includeImages,
    );
    if (doc != null) {
      created++;
      existing.add(kind);
    }
  }
  if (created == 0) {
    NotificationOverlayManager().showWarning(
      title: 'Hồ sơ đã đủ',
      message: tr('Báo giá này đã có hợp đồng, đề nghị TT, bàn giao và nghiệm thu.'),
    );
    return true;
  }
  NotificationOverlayManager().showSuccess(
    title: 'Đã lập hồ sơ',
    message: tr('Đã tạo $created chứng từ'),
  );
  return true;
}

/// Sửa «Ghi chú in trên chứng từ» — dòng «Ghi chú:» cuối bản in của riêng chứng từ này
/// (in sau ghi chú đơn của báo giá). Trả true khi đã lưu.
Future<bool> editPosQuoteDocumentNote(
  BuildContext context, {
  required String quoteId,
  required PosQuoteDocument doc,
}) async {
  final c = TextEditingController(text: (doc.note ?? '').trim());
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Ghi chú in trên chứng từ')),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            tr('In ở dòng «Ghi chú:» cuối chứng từ ${doc.docNo}, sau ghi chú đơn của báo giá. Chỉ chứng từ này có. Để trống nếu không cần.'),
            style: const TextStyle(fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            maxLines: 4,
            maxLength: 2000,
            decoration: PosTheme.inputDecoration(label: 'Ghi chú in'),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu'))),
      ],
    ),
  );
  final note = c.text.trim();
  c.dispose();
  if (ok != true || !context.mounted) return false;
  final res = await ApiService().updatePosQuoteDocumentNote(quoteId, doc.id, note);
  if (res['isSuccess'] != true) {
    NotificationOverlayManager().showError(
      title: 'Chưa lưu được ghi chú',
      message: res['message']?.toString() ?? doc.docNo,
    );
    return false;
  }
  NotificationOverlayManager().showSuccess(title: 'Đã lưu ghi chú in', message: doc.docNo);
  return true;
}
