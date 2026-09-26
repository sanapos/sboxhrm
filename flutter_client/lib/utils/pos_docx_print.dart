import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/app_tr.dart';
import '../models/pos_print_template.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_pdf_preview_dialog.dart';

/// In chứng từ bằng MẪU WORD (giữ bố cục file khách): gửi dữ liệu (cùng bộ trường như mẫu HTML)
/// lên máy chủ điền vào mẫu → PDF → xem trước / in. Trả `false` nếu lỗi (người gọi dùng mẫu HTML thay thế).
Future<bool> printWithPosDocxTemplate(
  BuildContext context, {
  required PosPrintTemplate template,
  required Map<String, String> data,
  required List<Map<String, String>> lines,
  required String title,
}) async {
  if (!template.isDocx) return false;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(children: [
        const CircularProgressIndicator(),
        const SizedBox(width: 16),
        Expanded(child: Text(tr('Đang điền mẫu Word…'))),
      ]),
    ),
  );
  final res = await ApiService().renderPosDocxTemplate(
    template.id,
    data: data,
    lines: lines,
    fileName: title.replaceAll(RegExp(r'[^\p{L}\p{N}_-]+', unicode: true), '_'),
  );
  if (!context.mounted) return false;
  Navigator.of(context, rootNavigator: true).pop();
  if (res['isSuccess'] != true || res['data'] is! List) {
    NotificationOverlayManager().showError(
      title: tr('Không in được bằng mẫu Word'),
      message: '${res['message'] ?? ''} — ${tr('dùng mẫu HTML thay thế')}',
    );
    return false;
  }
  await showPosPdfPreviewDialog(
    context,
    bytes: Uint8List.fromList(List<int>.from(res['data'] as List)),
    title: title,
  );
  return true;
}
