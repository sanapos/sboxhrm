import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_tr.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

/// Người dùng tự xóa tài khoản (App Store 5.1.1(v)): xác nhận mật khẩu → xóa → đăng xuất.
Future<void> showDeleteAccountDialog(BuildContext context) async {
  final api = ApiService();
  final info = await api.getAccountDeletionInfo();
  if (!context.mounted) return;
  final d = info['data'] is Map ? info['data'] as Map : const {};
  final closesStore = d['storeWillBeClosed'] == true;
  final pwd = TextEditingController();
  String? err;
  var busy = false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(child: Text(tr('Xóa tài khoản'))),
        ]),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('Tài khoản của bạn sẽ bị xóa vĩnh viễn: không thể đăng nhập lại, thông tin cá nhân (tên, email, số điện thoại) '
                'được xóa khỏi hệ thống. Chứng từ của cửa hàng (hóa đơn, chấm công) được giữ theo quy định pháp luật.')),
            if (closesStore) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                child: Text(
                  tr('Bạn là chủ cửa hàng «${d['storeName'] ?? ''}» và không còn quản trị viên nào khác — cửa hàng sẽ ngừng hoạt động.'),
                  style: TextStyle(color: Colors.red.shade800),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: pwd,
              obscureText: true,
              decoration: InputDecoration(labelText: tr('Nhập mật khẩu để xác nhận'), errorText: err, border: const OutlineInputBorder()),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: busy ? null : () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: busy
                ? null
                : () async {
                    if (pwd.text.isEmpty) return setS(() => err = tr('Nhập mật khẩu'));
                    setS(() => busy = true);
                    final r = await api.deleteMyAccount(pwd.text);
                    setS(() => busy = false);
                    if (r['isSuccess'] == true) {
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } else {
                      setS(() => err = '${r['message'] ?? tr('Không xóa được tài khoản')}');
                    }
                  },
            child: Text(tr('Xóa vĩnh viễn')),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Tài khoản đã được xóa'))));
  await Provider.of<AuthProvider>(context, listen: false).logout();
}
