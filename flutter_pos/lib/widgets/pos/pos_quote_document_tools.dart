import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_print_template.dart';
import '../../models/pos_quote.dart';
import '../../services/api_service.dart';
import '../../utils/api_datetime.dart';
import '../../utils/pos_html_print.dart';
import '../../utils/pos_print_template_loader.dart';
import '../notification_overlay.dart';

/// Công cụ trên MỘT chứng từ đã lập (hợp đồng, biên bản, đề nghị TT, báo giá):
/// chọn mẫu riêng, lịch sử nội dung, khôi phục theo mẫu. Không đụng mẫu in chung.

/// Chọn mẫu in cho riêng chứng từ [doc]. true = đã đổi.
Future<bool> pickPosQuoteDocumentTemplate(
  BuildContext context, {
  required String quoteId,
  required PosQuoteDocument doc,
  ApiService? api,
}) async {
  final client = api ?? ApiService();
  List<PosPrintTemplate> list;
  try {
    list = await loadPosPrintTemplates(client, doc.kind);
  } catch (_) {
    list = const [];
  }
  if (!context.mounted) return false;
  const followDefault = '__default__';
  final current = doc.printTemplateId ?? followDefault;
  final picked = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(tr('Mẫu in cho ${doc.docNo}')),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            doc.isCustomWording
                ? tr('Chứng từ này đang in lời văn đã sửa riêng — mẫu mới áp dụng khi «Khôi phục theo mẫu».')
                : tr('Chỉ đổi cho chứng từ này. Mẫu chung và các chứng từ khác giữ nguyên.'),
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
        _templateOption(ctx, followDefault, tr('Theo báo giá / mặc định cửa hàng'), current, null),
        for (final t in list)
          _templateOption(ctx, t.id, t.name, current, t.isDocx ? tr('Mẫu Word') : null),
      ],
    ),
  );
  if (picked == null || picked == current || !context.mounted) return false;
  final res = await client.setPosQuoteDocumentTemplate(
      quoteId, doc.id, picked == followDefault ? null : picked);
  if (res['isSuccess'] != true) {
    NotificationOverlayManager().showError(
      title: 'Chưa đổi được mẫu',
      message: res['message']?.toString() ?? tr('Vui lòng thử lại'),
    );
    return false;
  }
  NotificationOverlayManager().showSuccess(
    title: 'Đã đổi mẫu',
    message: tr('Chỉ áp dụng cho ${doc.docNo}'),
  );
  return true;
}

Widget _templateOption(BuildContext ctx, String value, String label, String current, String? tag) {
  final selected = value == current;
  return SimpleDialogOption(
    onPressed: () => Navigator.pop(ctx, value),
    child: Row(
      children: [
        Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
            size: 18, color: selected ? Theme.of(ctx).colorScheme.primary : Colors.black45),
        const SizedBox(width: 10),
        Expanded(child: Text(label)),
        if (tag != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF2B579A).withValues(alpha: .12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(tag, style: const TextStyle(fontSize: 11, color: Color(0xFF2B579A))),
          ),
      ],
    ),
  );
}

/// «Khôi phục theo mẫu»: bỏ lời văn sửa riêng, dựng lại từ số liệu hiện tại (bản cũ vào lịch sử).
Future<bool> restorePosQuoteDocumentToTemplate(
  BuildContext context, {
  required String quoteId,
  required PosQuoteDocument doc,
  ApiService? api,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Khôi phục theo mẫu?')),
      content: Text(tr('${doc.docNo} sẽ in lại theo mẫu với số liệu mới nhất của báo giá. '
          'Lời văn đã sửa được lưu trong «Lịch sử» — có thể quay lại.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Khôi phục'))),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  final res = await (api ?? ApiService()).updatePosQuoteDocumentWording(quoteId, doc.id, restore: true);
  if (res['isSuccess'] != true) {
    NotificationOverlayManager().showError(
      title: 'Chưa khôi phục được',
      message: res['message']?.toString() ?? tr('Vui lòng thử lại'),
    );
    return false;
  }
  NotificationOverlayManager().showSuccess(title: 'Đã khôi phục', message: doc.docNo);
  return true;
}

String _reasonLabel(String r) => switch (r) {
      'wording' => 'Trước khi sửa lời văn',
      'restore' => 'Trước khi khôi phục theo mẫu',
      'template' => 'Trước khi đổi mẫu',
      'revert' => 'Trước khi quay lại bản cũ',
      _ => r,
    };

/// Lịch sử nội dung chứng từ: xem từng bản, quay lại bản đã chọn. true = đã quay lại.
Future<bool> showPosQuoteDocumentHistory(
  BuildContext context, {
  required String quoteId,
  required PosQuoteDocument doc,
  ApiService? api,
}) async {
  final client = api ?? ApiService();
  final res = await client.getPosQuoteDocumentRevisions(quoteId, doc.id);
  if (!context.mounted) return false;
  final data = res['data'];
  final items = data is Map
      ? (data['items'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];
  if (items.isEmpty) {
    NotificationOverlayManager().showInfo(
      title: 'Chưa có lịch sử',
      message: tr('${doc.docNo} chưa sửa lần nào'),
    );
    return false;
  }
  final fmt = DateFormat('dd/MM/yyyy HH:mm');
  final reverted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.sizeOf(ctx).height * .7,
      child: Column(
        children: [
          ListTile(
            title: Text(tr('Lịch sử ${doc.docNo}'), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(tr('Mỗi lần sửa / khôi phục / đổi mẫu đều lưu lại bản trước đó.')),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = items[i];
                final id = (r['id'] ?? r['Id']).toString();
                final at = parseApiUtcDateTime(r['createdAt'] ?? r['CreatedAt'])?.toLocal();
                final by = (r['createdBy'] ?? r['CreatedBy'] ?? '').toString();
                final custom = (r['isCustomWording'] ?? r['IsCustomWording']) == true;
                return ListTile(
                  leading: Icon(custom ? Icons.edit_note : Icons.article_outlined),
                  title: Text(tr(_reasonLabel((r['reason'] ?? r['Reason'] ?? '').toString()))),
                  subtitle: Text([
                    if (at != null) fmt.format(at),
                    if (by.isNotEmpty) by,
                    custom ? tr('lời văn sửa riêng') : tr('theo mẫu'),
                  ].join(' · ')),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        tooltip: tr('Xem'),
                        icon: const Icon(Icons.visibility_outlined),
                        onPressed: () async {
                          final rv = await client.getPosQuoteDocumentRevision(quoteId, doc.id, id);
                          if (!ctx.mounted || rv['isSuccess'] != true || rv['data'] is! Map) return;
                          final html = ((rv['data'] as Map)['htmlContent'] ?? '').toString();
                          await showPosHtmlPrintDialog(ctx, title: doc.docNo, htmlDocument: html, a4Paper: true);
                        },
                      ),
                      TextButton(
                        onPressed: () async {
                          final rr = await client.restorePosQuoteDocumentRevision(quoteId, doc.id, id);
                          if (!ctx.mounted) return;
                          if (rr['isSuccess'] == true) {
                            Navigator.pop(ctx, true);
                          } else {
                            NotificationOverlayManager().showError(
                              title: 'Chưa quay lại được',
                              message: rr['message']?.toString() ?? tr('Vui lòng thử lại'),
                            );
                          }
                        },
                        child: Text(tr('Quay lại')),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
  if (reverted == true) {
    NotificationOverlayManager().showSuccess(title: 'Đã quay lại bản cũ', message: doc.docNo);
    return true;
  }
  return false;
}

/// Bản sửa riêng đã cũ: hỏi người dùng in tiếp bản đã sửa, cập nhật theo số liệu mới, hay sửa lại.
/// Trả 'print' / 'refresh' / 'edit' hoặc null (hủy).
Future<String?> askPosQuoteStaleWording(BuildContext context, String docNo) => showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Lời văn đã sửa đã cũ')),
        content: Text(tr('Báo giá đã thay đổi (giá, dòng hàng, đợt hoặc tiền đã thu) sau khi sửa lời văn $docNo. '
            'Bản đã sửa có thể ghi số liệu cũ.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'edit'), child: Text(tr('Sửa lại lời văn'))),
          TextButton(onPressed: () => Navigator.pop(ctx, 'refresh'), child: Text(tr('Cập nhật theo số liệu mới'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'print'), child: Text(tr('Vẫn in bản đã sửa'))),
        ],
      ),
    );
