import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n/app_tr.dart';
import '../models/pos_print_template.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_pdf_preview_dialog.dart';
import 'pos_print_template_renderer.dart';

/// Hồ sơ thương mại cửa hàng (tên công ty, MST, tài khoản, logo, con dấu) — nhớ 5 phút.
Map<String, dynamic>? _profileCache;
DateTime? _profileAt;

Future<Map<String, dynamic>?> _commercialProfile() async {
  final at = _profileAt;
  if (at != null && DateTime.now().difference(at) < const Duration(minutes: 5)) return _profileCache;
  try {
    final res = await ApiService().getPosCommercialProfile();
    if (res['isSuccess'] == true && res['data'] is Map) {
      _profileCache = Map<String, dynamic>.from(res['data'] as Map);
      _profileAt = DateTime.now();
    }
  } catch (_) {}
  return _profileCache;
}

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
  // Mẫu Word hóa đơn hay có tên công ty, MST, tài khoản, logo, con dấu của bên bán → lấy từ hồ sơ thương mại.
  final filled = withPosCommercialProfile(data, await _commercialProfile());
  final res = await ApiService().renderPosDocxTemplate(
    template.id,
    data: filled,
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
