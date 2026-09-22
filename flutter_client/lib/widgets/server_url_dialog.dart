import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import 'notification_overlay.dart';

/// Đổi máy chủ API và kiểm tra kết nối trước khi lưu.
Future<void> showServerUrlDialog(BuildContext context) async {
  final controller = TextEditingController(text: ApiService.baseUrl);
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      var busy = false;
      String? error;
      return StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(tr('Cấu hình Server')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: tr('URL Server API'),
                  hintText: 'https://sbox.sana.vn',
                  errorText: error,
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
              ),
              const SizedBox(height: 8),
              Text(
                tr('App sẽ gọi thử máy chủ trước khi lưu.'),
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx, false),
              child: Text(tr('Hủy')),
            ),
            ElevatedButton(
              onPressed: busy
                  ? null
                  : () async {
                      setLocal(() {
                        busy = true;
                        error = null;
                      });
                      final err = await ApiService.applyBaseUrl(controller.text);
                      if (!ctx.mounted) return;
                      if (err != null) {
                        setLocal(() {
                          busy = false;
                          error = err;
                        });
                        return;
                      }
                      Navigator.pop(ctx, true);
                    },
              child: Text(tr(busy ? 'Đang kiểm tra...' : 'Lưu')),
            ),
          ],
        ),
      );
    },
  );
  controller.dispose();
  if (saved != true || !context.mounted) return;
  NotificationOverlayManager().showSuccess(
    title: tr('Đã lưu máy chủ'),
    message: ApiService.baseUrl,
  );
  final auth = context.read<AuthProvider>();
  if (auth.isAuthenticated) {
    await auth.logout();
  }
}
