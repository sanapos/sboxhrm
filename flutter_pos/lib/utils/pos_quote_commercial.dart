import 'package:flutter/material.dart';

import '../l10n/app_tr.dart';
import '../models/pos_quote.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';

const posQuotePackageKinds = [
  'Contract',
  'PaymentRequest',
  'Handover',
  'Acceptance',
];

/// Lập chứng từ thương mại. Báo giá chưa gửi vẫn lập được — máy chủ tự nhận.
Future<PosQuoteDocument?> createPosQuoteCommercialDoc(
  BuildContext context, {
  required PosQuote quote,
  required String kind,
  bool includeImages = false,
  String? note,
}) async {
  final api = ApiService();
  final current = quote;
  // Không hỏi ghi chú khi lập chứng từ (người dùng không biết ghi chú dùng vào đâu).
  final resolvedNote = note;

  if (!context.mounted) return null;

  final res = kind == 'StockIssue'
      ? await api.createPosQuoteStockIssue(
          current.id,
          note: resolvedNote,
          includeImages: includeImages,
        )
      : await api.createPosQuoteDocument(
          current.id,
          kind,
          note: resolvedNote,
          includeImages: includeImages,
        );
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
  // Chỉ xác nhận — không hỏi ghi chú.
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
