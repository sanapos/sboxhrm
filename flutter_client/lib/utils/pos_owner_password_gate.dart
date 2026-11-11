import 'dart:async';

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
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(ctx, _remoteApprovalChoice),
              icon: const Icon(Icons.phone_iphone_rounded, size: 18),
              label: Text(tr('Gửi chủ duyệt từ xa')),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(tr('Duyệt'))),
          ],
        ),
      );
    },
  );
  if (password == _remoteApprovalChoice) {
    if (!context.mounted) return false;
    return waitPosRemoteApproval(context, reason);
  }
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

/// Giá trị đặc biệt trả từ hộp «Cần quản lý duyệt» khi chọn gửi chủ duyệt từ xa (không thể là mật khẩu gõ tay).
const _remoteApprovalChoice = '\u0000remote';

/// «Duyệt từ xa»: gửi yêu cầu lên máy chủ (chủ / quản lý thấy trên SBOX BOSS), chờ tối đa 3 phút.
/// Được duyệt → nhận mã duyệt 5 phút như khi nhập mật khẩu tại máy. Trả true khi đã duyệt.
Future<bool> waitPosRemoteApproval(BuildContext context, String reason) async {
  final api = ApiService();
  // Kèm bàn / số món / tổng tiền — trước đây chủ chỉ thấy lý do, không biết bàn nào, bao nhiêu tiền.
  final snap = PosManagerApproval.currentSnapshot();
  final created = await api.createPosRemoteApproval(
      reason.replaceFirst(RegExp(r'^Cần quản lý duyệt:\s*'), ''),
      detail: snap?.detail,
      amount: snap?.amount);
  final data = created['data'] is Map ? created['data'] as Map : null;
  final id = data?['id']?.toString();
  if (created['isSuccess'] != true || id == null) {
    NotificationOverlayManager().showError(
      title: 'Không gửi được',
      message: tr('${created['message'] ?? 'Không gửi được yêu cầu duyệt'}'),
    );
    return false;
  }
  if (!context.mounted) return false;
  final total = (data?['expiresInSeconds'] as num?)?.toInt() ?? 180;
  final result = await showDialog<Map>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _RemoteApprovalWaitDialog(id: id, seconds: total, reason: reason),
  );
  final token = result?['approvalToken']?.toString();
  if (result?['status'] == 'approved' && token != null && token.isNotEmpty) {
    ApiService.setPosApprovalToken(token, seconds: (result?['tokenExpiresInSeconds'] as num?)?.toInt() ?? 300);
    NotificationOverlayManager().showSuccess(
      title: 'Đã duyệt',
      message: tr('${result?['decidedBy'] ?? 'Chủ cửa hàng'} đã duyệt từ xa — có hiệu lực 5 phút'),
    );
    return true;
  }
  if (result?['status'] == 'rejected') {
    final why = (result?['rejectReason'] ?? '').toString();
    NotificationOverlayManager().showError(
      title: 'Bị từ chối',
      message: tr('${result?['decidedBy'] ?? 'Chủ cửa hàng'} không duyệt${why.isEmpty ? '' : ': $why'}'),
    );
  } else if (result?['status'] == 'expired') {
    NotificationOverlayManager().showWarning(title: 'Hết thời gian', message: tr('Chưa ai duyệt — thử lại sau'));
  }
  return false;
}

class _RemoteApprovalWaitDialog extends StatefulWidget {
  const _RemoteApprovalWaitDialog({required this.id, required this.seconds, required this.reason});

  final String id;
  final int seconds;
  final String reason;

  @override
  State<_RemoteApprovalWaitDialog> createState() => _RemoteApprovalWaitDialogState();
}

class _RemoteApprovalWaitDialogState extends State<_RemoteApprovalWaitDialog> {
  late int _left = widget.seconds;
  Timer? _tick;
  Timer? _poll;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _left = _left > 0 ? _left - 1 : 0);
      if (_left == 0) _finish({'status': 'expired'});
    });
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  void _finish(Map result) {
    _tick?.cancel();
    _poll?.cancel();
    if (mounted) Navigator.pop(context, result);
  }

  Future<void> _check() async {
    if (_polling) return;
    _polling = true;
    final r = await ApiService().getPosRemoteApproval(widget.id);
    _polling = false;
    if (!mounted) return;
    final d = r['data'] is Map ? r['data'] as Map : null;
    if (r['isSuccess'] != true) return _finish({'status': 'expired'});
    final status = d?['status']?.toString() ?? 'pending';
    if (status != 'pending') _finish(d!);
  }

  Future<void> _cancel() async {
    _poll?.cancel();
    await ApiService().cancelPosRemoteApproval(widget.id);
    _finish({'status': 'cancelled'});
  }

  @override
  Widget build(BuildContext context) {
    final mm = (_left ~/ 60).toString();
    final ss = (_left % 60).toString().padLeft(2, '0');
    return AlertDialog(
      icon: const Icon(Icons.phone_iphone_rounded, size: 32, color: Color(0xFF0E7490)),
      title: Text(tr('Đang chờ chủ duyệt')),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          tr(widget.reason.replaceFirst(RegExp(r'^Cần quản lý duyệt:\s*'), '')),
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.35),
        ),
        const SizedBox(height: 16),
        const LinearProgressIndicator(),
        const SizedBox(height: 12),
        Text(
          tr('Đã gửi tới app SBOX BOSS của chủ / quản lý · còn $mm:$ss'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
        ),
      ]),
      actions: [TextButton(onPressed: _cancel, child: Text(tr('Hủy yêu cầu')))],
    );
  }
}

/// Thông tin kèm yêu cầu duyệt từ xa: «Khu A · Bàn 5 · 3 món» và tổng tiền.
typedef PosApprovalSnapshot = ({String? detail, double? amount});

/// Gắn màn POS đang mở để ApiService mở hộp «Cần quản lý duyệt» khi máy chủ chặn (màn mở sau cùng được dùng).
class PosManagerApproval {
  PosManagerApproval._();

  static final _contexts = <BuildContext>[];
  static final _snapshots = <BuildContext, PosApprovalSnapshot Function()>{};

  /// [snapshot]: bàn / số món / tổng tiền đang mở — gửi kèm yêu cầu duyệt từ xa để chủ biết duyệt gì.
  static void attach(BuildContext context, {PosApprovalSnapshot Function()? snapshot}) {
    _contexts.add(context);
    if (snapshot != null) _snapshots[context] = snapshot;
    ApiService.onPosManagerApproval = _handle;
  }

  static void detach(BuildContext context) {
    _contexts.remove(context);
    _snapshots.remove(context);
    if (_contexts.isEmpty) ApiService.onPosManagerApproval = null;
  }

  /// Bàn / tổng tiền của màn POS mở sau cùng (null khi màn đó không cung cấp).
  static PosApprovalSnapshot? currentSnapshot() {
    for (final c in _contexts.reversed) {
      if (!c.mounted) continue;
      try {
        return _snapshots[c]?.call();
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static Future<bool> _handle(String message) async {
    for (final c in _contexts.reversed) {
      if (c.mounted) return confirmPosManagerApproval(c, message);
    }
    return false;
  }
}
