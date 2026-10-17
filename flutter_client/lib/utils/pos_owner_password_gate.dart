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

/// «Sau tạm tính cần quản lý duyệt»: máy chủ chặn hủy món / hủy đơn / thu ít hơn tạm tính → chủ / quản lý nhập
/// mật khẩu ngay trên máy này; máy chủ cấp mã duyệt 5 phút, app gửi lại thao tác. Trả true khi đã duyệt.
Future<bool> confirmPosManagerApproval(BuildContext context, String reason) async {
  final password = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final ctrl = TextEditingController();
      var obscure = true;
      return StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          icon: const Icon(Icons.admin_panel_settings_outlined, size: 32, color: Color(0xFFD97706)),
          title: Text(tr('Cần quản lý duyệt')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr(reason.replaceFirst(RegExp(r'^Cần quản lý duyệt:\s*'), '')),
                style: const TextStyle(height: 1.35),
              ),
              const SizedBox(height: 6),
              Text(
                tr('Khách đã nhận phiếu tạm tính — thay đổi làm giảm tiền phải có chủ / quản lý xác nhận. '
                    'Người duyệt được ghi vào lịch sử hủy / trả.'),
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B), height: 1.35),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                obscureText: obscure,
                autofocus: true,
                onSubmitted: (_) => Navigator.pop(ctx, ctrl.text),
                decoration: InputDecoration(
                  labelText: tr('Mật khẩu chủ / quản lý'),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    tooltip: obscure ? tr('Hiện') : tr('Ẩn'),
                    onPressed: () => setLocal(() => obscure = !obscure),
                    icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Không làm nữa'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(tr('Duyệt'))),
          ],
        ),
      );
    },
  );
  final trimmed = password?.trim() ?? '';
  if (trimmed.isEmpty) return false;
  final res = await ApiService().verifyPosOwnerPassword(trimmed, purpose: 'after-bill');
  final data = res['data'] is Map ? res['data'] as Map : null;
  final token = data?['approvalToken']?.toString();
  if (res['isSuccess'] == true && token != null && token.isNotEmpty) {
    ApiService.setPosApprovalToken(token, seconds: (data?['expiresInSeconds'] as num?)?.toInt() ?? 300);
    NotificationOverlayManager().showSuccess(
      title: 'Đã duyệt',
      message: tr('Quản lý ${data?['approvedBy'] ?? ''} đã duyệt — có hiệu lực 5 phút'),
    );
    return true;
  }
  NotificationOverlayManager().showError(
    title: 'Không duyệt được',
    message: tr('${res['message'] ?? 'Mật khẩu chủ / quản lý không đúng'}'),
  );
  return false;
}

/// Gắn màn POS đang mở để ApiService mở hộp «Cần quản lý duyệt» khi máy chủ chặn (màn mở sau cùng được dùng).
class PosManagerApproval {
  PosManagerApproval._();

  static final _contexts = <BuildContext>[];

  static void attach(BuildContext context) {
    _contexts.add(context);
    ApiService.onPosManagerApproval = _handle;
  }

  static void detach(BuildContext context) {
    _contexts.remove(context);
    if (_contexts.isEmpty) ApiService.onPosManagerApproval = null;
  }

  static Future<bool> _handle(String message) async {
    for (final c in _contexts.reversed) {
      if (c.mounted) return confirmPosManagerApproval(c, message);
    }
    return false;
  }
}
