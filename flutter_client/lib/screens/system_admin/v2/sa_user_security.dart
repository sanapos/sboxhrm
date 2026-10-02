import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_tr.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/api_service.dart';
import '../../../widgets/sbox/sbox_ui.dart';
import 'sa_v2_common.dart';

/// Bảo mật & hỗ trợ tài khoản: đặt lại mật khẩu, mở khóa, đăng xuất mọi thiết bị, đăng nhập thay.
Future<void> showSaUserSecurityDialog(BuildContext context, Map<String, dynamic> user, {ApiService? api}) {
  return showDialog<void>(context: context, builder: (_) => _SaUserSecurityDialog(user: user, api: api ?? ApiService()));
}

class _SaUserSecurityDialog extends StatefulWidget {
  const _SaUserSecurityDialog({required this.user, required this.api});
  final Map<String, dynamic> user;
  final ApiService api;

  @override
  State<_SaUserSecurityDialog> createState() => _SaUserSecurityDialogState();
}

class _SaUserSecurityDialogState extends State<_SaUserSecurityDialog> {
  Map<String, dynamic>? _d;
  bool _busy = false;
  String get _id => '${widget.user['id'] ?? widget.user['userId'] ?? ''}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.api.saUserSecurity(_id);
    if (!mounted) return;
    setState(() => _d = r['data'] is Map ? Map<String, dynamic>.from(r['data'] as Map) : {});
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() call, String ok) async {
    setState(() => _busy = true);
    final r = await call();
    if (!mounted) return;
    setState(() => _busy = false);
    if (saOk(context, r, ok)) _load();
  }

  Future<void> _resetPassword() async {
    if (!await SboxDialogs.confirm(context, title: 'Đặt lại mật khẩu?', message: 'Tạo mật khẩu tạm mới, đăng xuất phiên hiện tại và báo cho người dùng.', confirmLabel: 'Đặt lại')) return;
    setState(() => _busy = true);
    final r = await widget.api.saResetPassword(_id);
    if (!mounted) return;
    setState(() => _busy = false);
    final pwd = r['data'] is Map ? '${(r['data'] as Map)['password']}' : null;
    if (r['isSuccess'] != true || pwd == null) {
      saToast(context, '${r['message'] ?? 'Không đặt lại được'}', error: true);
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Mật khẩu tạm')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Chỉ hiện một lần. Gửi cho người dùng qua kênh an toàn và yêu cầu đổi ngay.')),
          const SizedBox(height: 12),
          SelectableText(pwd, style: const TextStyle(fontFamily: 'monospace', fontSize: 20, fontWeight: FontWeight.w700)),
        ]),
        actions: [
          TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: pwd)),
            icon: const Icon(Icons.copy, size: 16),
            label: Text(tr('Sao chép')),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Xong'))),
        ],
      ),
    );
    _load();
  }

  Future<void> _impersonate() async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Đăng nhập thay để hỗ trợ')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Bạn sẽ thấy và thao tác như người dùng này. Thao tác được ghi nhật ký; chủ cửa hàng nhận thông báo. '
              'Phiên tự hết hạn theo thời hạn token, bấm «Thoát» trên thanh vàng để quay lại.')),
          const SizedBox(height: 12),
          TextField(controller: ctrl, autofocus: true, maxLines: 2, decoration: saInput('Lý do hỗ trợ', hint: 'VD: Khách báo không in được hóa đơn')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(tr('Đăng nhập thay'))),
        ],
      ),
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    final r = await widget.api.saImpersonate(_id, reason);
    if (!mounted) return;
    setState(() => _busy = false);
    final d = r['data'];
    if (r['isSuccess'] != true || d is! Map || d['accessToken'] == null) {
      saToast(context, '${r['message'] ?? 'Không đăng nhập thay được'}', error: true);
      return;
    }
    final label = '${d['userName'] ?? d['email']} · ${d['storeName'] ?? d['storeCode'] ?? ''}';
    final auth = context.read<AuthProvider>();
    Navigator.of(context).pop();
    await auth.startImpersonation('${d['accessToken']}', label);
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final u = widget.user;
    final locked = d?['lockedUntil'] != null;
    return AlertDialog(
      title: Text(tr('Bảo mật & hỗ trợ — ${u['fullName'] ?? u['email'] ?? ''}')),
      content: SizedBox(
        width: 520,
        child: d == null
            ? const SizedBox(height: 120, child: SboxLoading())
            : SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    SboxStatusChip(label: d['isActive'] == true ? 'Đang hoạt động' : 'Đã vô hiệu', tone: d['isActive'] == true ? SboxTone.success : SboxTone.neutral, dot: true),
                    if (locked) SboxStatusChip(label: 'Bị khóa đến ${saDate(d['lockedUntil'])}', tone: SboxTone.danger),
                    SboxStatusChip(label: 'Sai mật khẩu ${d['failedAttempts'] ?? 0} lần', tone: SboxTone.neutral),
                    SboxStatusChip(label: d['hasSession'] == true ? 'Có phiên đăng nhập' : 'Không có phiên', tone: SboxTone.neutral),
                  ]),
                  const SizedBox(height: 8),
                  Text('${d['role'] ?? ''} · ${d['storeName'] ?? ''} (${d['storeCode'] ?? ''}) · đăng nhập gần nhất ${saDate(d['lastLoginAt'])}', style: SboxType.smallStyle()),
                  const SizedBox(height: 12),
                  Text(tr('Thiết bị nhận thông báo'), style: SboxType.captionStyle()),
                  if ((d['devices'] as List? ?? []).isEmpty) Text(tr('Không có'), style: SboxType.smallStyle()),
                  for (final dv in (d['devices'] as List? ?? []).whereType<Map>())
                    Text('• ${dv['deviceName'] ?? dv['platform']} (${dv['platform']}) · ${saDate(dv['createdAt'])}', style: SboxType.smallStyle(SboxColors.text)),
                  const SizedBox(height: 12),
                  Text(tr('Đăng nhập gần đây'), style: SboxType.captionStyle()),
                  for (final l in (d['logins'] as List? ?? []).whereType<Map>())
                    Text('• ${saDate(l['timestamp'])} · ${l['action'] == 'LoginFailed' ? 'Sai mật khẩu' : 'Thành công'} · ${l['ipAddress'] ?? ''}',
                        style: SboxType.smallStyle(l['action'] == 'LoginFailed' ? SboxColors.dangerText : SboxColors.text)),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    SboxButton.secondary(label: 'Đặt lại mật khẩu', icon: Icons.lock_reset, size: SboxButtonSize.sm, onPressed: _busy ? null : _resetPassword),
                    SboxButton.secondary(label: 'Mở khóa đăng nhập', icon: Icons.lock_open, size: SboxButtonSize.sm,
                        onPressed: _busy ? null : () => _run(() => widget.api.saUnlockUser(_id), 'Đã mở khóa')),
                    SboxButton.secondary(label: 'Đăng xuất mọi thiết bị', icon: Icons.logout, size: SboxButtonSize.sm,
                        onPressed: _busy ? null : () => _run(() => widget.api.saRevokeSessions(_id), 'Đã đăng xuất mọi thiết bị')),
                    SboxButton(label: 'Đăng nhập thay', icon: Icons.support_agent, size: SboxButtonSize.sm, onPressed: _busy ? null : _impersonate),
                  ]),
                ]),
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Đóng')))],
    );
  }
}
