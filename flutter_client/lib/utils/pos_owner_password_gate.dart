import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Hộp thoại + API xác nhận mật khẩu chủ cửa hàng / quản lý.
/// Dùng cho thao tác nhạy cảm (trả bàn trống…).
Future<bool> confirmPosOwnerPassword(
  BuildContext context, {
  String title = 'Xác nhận chủ cửa hàng',
  String message =
      'Thao tác này có thể xóa đơn tạm và trả bàn về trống.\n'
      'Nhập mật khẩu tài khoản chủ cửa hàng hoặc quản lý để tiếp tục.',
}) async {
  final password = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final ctrl = TextEditingController();
      var obscure = true;
      return StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(tr(title)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr(message), style: const TextStyle(height: 1.35)),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                obscureText: obscure,
                autofocus: true,
                onSubmitted: (_) => Navigator.pop(ctx, ctrl.text),
                decoration: InputDecoration(
                  labelText: tr('Mật khẩu chủ cửa hàng'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    tooltip: obscure ? tr('Hiện') : tr('Ẩn'),
                    onPressed: () => setLocal(() => obscure = !obscure),
                    icon: Icon(
                      obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Huỷ')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(tr('Xác nhận')),
            ),
          ],
        ),
      );
    },
  );
  if (password == null) return false;
  final trimmed = password.trim();
  if (trimmed.isEmpty) {
    NotificationOverlayManager().showError(
      title: 'Thiếu mật khẩu',
      message: tr('Vui lòng nhập mật khẩu chủ cửa hàng'),
    );
    return false;
  }

  final res = await ApiService().verifyPosOwnerPassword(trimmed);
  if (res['isSuccess'] == true) return true;
  NotificationOverlayManager().showError(
    title: 'Không xác nhận được',
    message: tr('${res['message'] ?? 'Mật khẩu chủ cửa hàng không đúng'}'),
  );
  return false;
}
