import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_tr.dart';
import '../../models/zk_gateway.dart';
import '../../services/api_service.dart';
import '../../services/zk_gateway_client.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/notification_overlay.dart';
import 'zk_gateway_device_screen.dart';
import 'zk_gateway_setup_screen.dart';
import 'zk_gateway_user_errors.dart';
import 'zk_gateway_widgets.dart';

/// Trang chi tiết một gateway: trạng thái đồng bộ, các thao tác điều khiển
/// và đổi tên. Mọi lệnh gọi thẳng vào IP LAN của thiết bị.
class ZkGatewayDetailScreen extends StatefulWidget {
  const ZkGatewayDetailScreen({super.key, required this.info});

  final ZkGatewayInfo info;

  @override
  State<ZkGatewayDetailScreen> createState() => _ZkGatewayDetailScreenState();
}

class _ZkGatewayDetailScreenState extends State<ZkGatewayDetailScreen> {
  final _client = ZkGatewayClient();

  late ZkGatewayInfo _info;
  ZkGatewayStatus? _status;
  ZkGatewayConfig? _config;
  Timer? _timer;
  bool _loading = true;
  bool _busy = false;
  String? _loadError;
  /// Hướng dẫn xử lý khi mất kết nối API (hiện trên thẻ lỗi).
  String? _loadGuide;
  bool _advancedOpen = false;

  /// Bản trên server (null = chưa tải / không có quyền / chưa publish).
  String? _serverVersion;
  String? _serverAppSha;
  String? _serverNotes;
  int? _serverBytes;
  String? _serverReleaseError;
  String? _deviceAppSha;
  bool _otaChecking = false;

  @override
  void initState() {
    super.initState();
    _info = widget.info;
    _refresh();
    _loadServerRelease();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadServerRelease() async {
    setState(() => _otaChecking = true);
    try {
      final res = await ApiService().getZkGatewayRelease();
      if (!mounted) return;
      if (res['isSuccess'] == true && res['data'] is Map) {
        final d = Map<String, dynamic>.from(res['data'] as Map);
        setState(() {
          _serverVersion = d['versionName']?.toString() ?? d['VersionName']?.toString();
          _serverAppSha = d['appSha']?.toString() ?? d['AppSha']?.toString();
          _serverNotes = d['releaseNotes']?.toString() ?? d['ReleaseNotes']?.toString();
          final b = d['fileBytes'] ?? d['FileBytes'];
          _serverBytes = b is int ? b : int.tryParse(b?.toString() ?? '');
          _serverReleaseError = null;
          _otaChecking = false;
        });
      } else {
        setState(() {
          _serverVersion = null;
          _serverAppSha = null;
          _serverNotes = null;
          _serverBytes = null;
          _serverReleaseError =
              res['message']?.toString() ?? tr('Chưa có firmware trên máy chủ');
          _otaChecking = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _serverReleaseError = tr('Không kiểm tra được bản mới');
        _otaChecking = false;
      });
    }
  }

  bool get _updateAvailable {
    final local = (_status?.version.isNotEmpty == true)
        ? _status!.version
        : _info.version;
    final remote = _serverVersion;
    if (remote == null || remote.isEmpty) return false;

    final localSha = (_deviceAppSha != null && _deviceAppSha!.isNotEmpty)
        ? _deviceAppSha!
        : _info.appSha;
    final remoteSha = _serverAppSha;
    if (localSha.isNotEmpty && remoteSha != null && remoteSha.isNotEmpty) {
      return localSha.toLowerCase() != remoteSha.toLowerCase();
    }
    if (local.isEmpty) return true;
    return local != remote;
  }

  Future<void> _updateFirmwareFromServer() async {
    if (_busy) return;
    if (_serverVersion == null) {
      await _loadServerRelease();
      if (!mounted) return;
      if (_serverVersion == null) {
        appNotification.showError(
          title: tr('Cập nhật firmware'),
          message: tr(_serverReleaseError ?? 'Chưa có firmware trên máy chủ'),
        );
        return;
      }
    }

    final local = _status?.version.isNotEmpty == true ? _status!.version : _info.version;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Cập nhật firmware gateway')),
        content: Text(
          tr(
            'Tải bản $_serverVersion từ máy chủ rồi nạp qua WiFi LAN vào ${_info.ip}.\n\n'
            'Thiết bị hiện tại: ${local.isEmpty ? "?" : local}'
            '${(_deviceAppSha != null && _deviceAppSha!.isNotEmpty) ? " (sha $_deviceAppSha)" : ""}.\n'
            'Gateway sẽ khởi động lại sau khi nạp xong. Giữ điện thoại cùng mạng WiFi.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Cập nhật'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      appNotification.showSuccess(
        title: tr('OTA'),
        message: tr('Đang tải firmware từ máy chủ...'),
      );
      final dl = await ApiService().downloadZkGatewayFirmware();
      if (dl['isSuccess'] != true || dl['data'] is! List<int>) {
        throw ZkGatewayException(
          dl['message']?.toString() ?? 'Không tải được firmware',
        );
      }
      final bytes = dl['data'] as List<int>;
      if (!mounted) return;
      appNotification.showSuccess(
        title: tr('OTA'),
        message: tr('Đang nạp ${(bytes.length / 1024).round()} KB vào gateway...'),
      );
      await _client.uploadFirmware(_info.ip, bytes);
      if (!mounted) return;
      appNotification.showSuccess(
        title: tr('Đã nạp firmware'),
        message: tr('Gateway đang khởi động lại...'),
      );
      await Future.delayed(const Duration(seconds: 8));
      if (!mounted) return;
      await _refresh();
      await _loadServerRelease();
    } on ZkGatewayAuthException {
      if (!mounted) return;
      final unlocked = await _promptUnlock();
      if (unlocked) await _updateFirmwareFromServer();
    } catch (e) {
      if (!mounted) return;
      _notifyGatewayError(e, fallbackTitle: 'Cập nhật thất bại');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notifyGatewayError(Object e, {String fallbackTitle = 'Không kết nối được gateway'}) {
    final err = ZkGatewayUserError.from(e, fallbackTitle: fallbackTitle);
    final short = err.message.split('\n').where((l) => l.trim().isNotEmpty).first;
    appNotification.showError(title: tr(err.title), message: tr(short));
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(err.title)),
        content: SingleChildScrollView(
          child: Text(
            tr(err.message),
            style: const TextStyle(fontSize: 13.5, height: 1.45),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Đã hiểu')),
          ),
        ],
      ),
    );
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final status = await _client.fetchStatus(_info.ip);
      ZkGatewayInfo? info;
      ZkGatewayConfig? cfg;
      if (!silent || (_deviceAppSha == null || _deviceAppSha!.isEmpty)) {
        try {
          info = await _client.fetchInfo(_info.ip);
        } catch (_) {}
      }
      try {
        cfg = await _client.fetchConfig(_info.ip);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _status = status;
        if (cfg != null) _config = cfg;
        if (info != null) {
          _info = _info.copyWith(
            ip: info.ip.isNotEmpty ? info.ip : null,
            version: info.version.isNotEmpty ? info.version : null,
            appSha: info.appSha.isNotEmpty ? info.appSha : null,
          );
          if (info.appSha.isNotEmpty) _deviceAppSha = info.appSha;
        }
        _loading = false;
        _loadError = null;
        _loadGuide = null;
      });
    } on ZkGatewayAuthException catch (e) {
      if (!mounted) return;
      final ok = await _promptUnlock();
      if (ok) {
        await _refresh(silent: silent);
      } else {
        final err = ZkGatewayUserError.from(e);
        setState(() {
          _loading = false;
          _loadError = err.title;
          _loadGuide = err.message;
        });
        if (!silent) _notifyGatewayError(e);
      }
    } catch (e) {
      if (!mounted) return;
      final err = ZkGatewayUserError.from(
        e,
        fallbackTitle: 'Không kết nối được gateway',
      );
      setState(() {
        _loading = false;
        _loadError = err.title;
        _loadGuide = err.message;
      });
      if (!silent) {
        _notifyGatewayError(e);
      }
    }
  }

  Future<bool> _promptUnlock() async {
    final ctrl = TextEditingController();
    final pass = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Gateway đang khóa')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Nhập mật khẩu quản trị đã đặt trên thiết bị.')),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(labelText: tr('Mật khẩu')),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
            const SizedBox(height: 8),
            Text(
              tr('Quên mật khẩu: nối điện thoại vào sóng SBOX-Gateway-XXXX rồi bấm Đặt lại.'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Huỷ')),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx, '__RESET__');
            },
            child: Text(tr('Đặt lại')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(tr('Mở khóa')),
          ),
        ],
      ),
    );
    if (pass == null || pass.isEmpty) return false;

    if (pass == '__RESET__') {
      return _resetPasswordViaAp();
    }

    try {
      await _client.verifyPassword(_info.ip, pass);
      await _client.rememberPassword(pass, serial: _info.serial, ip: _info.ip);
      return true;
    } catch (_) {
      if (!mounted) return false;
      appNotification.showError(
        title: tr('Sai mật khẩu'),
        message: tr('Không mở được khóa gateway'),
      );
      return false;
    }
  }

  Future<bool> _resetPasswordViaAp() async {
    try {
      // Chỉ thành công khi điện thoại đang nối AP cấu hình của ESP.
      await _client.clearPortalPassword(ZkGatewayClient.apAddress);
      await _client.forgetPassword(serial: _info.serial, ip: _info.ip);
      if (!mounted) return false;
      appNotification.showSuccess(
        title: tr('Đã đặt lại mật khẩu'),
        message: tr('Đã xóa khóa khi đang ở sóng cấu hình'),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      appNotification.showError(
        title: tr('Chưa đặt lại được'),
        message: tr(
          'Hãy nối WiFi vào sóng SBOX-Gateway-XXXX (mật khẩu sbox12345), '
          'rồi mở lại mục này và bấm Đặt lại.',
        ),
      );
      return false;
    }
  }

  Future<void> _openPasswordSettings() async {
    var locked = _info.locked;
    try {
      final st = await _client.fetchAuthStatus(_info.ip);
      locked = st['locked'] == true;
    } catch (_) {}
    if (!mounted) return;

    final newCtrl = TextEditingController();
    final oldCtrl = TextEditingController();
    final saved = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Mật khẩu gateway')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                locked
                    ? tr('Đổi mật khẩu hiện tại, hoặc xóa khóa.')
                    : tr('Đặt mật khẩu để khóa cấu hình / thao tác trên gateway.'),
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
              if (locked) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: oldCtrl,
                  obscureText: true,
                  decoration: InputDecoration(labelText: tr('Mật khẩu cũ')),
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: newCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: locked ? tr('Mật khẩu mới') : tr('Mật khẩu (tối thiểu 4 ký tự)'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Huỷ'))),
          if (locked)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'clear'),
              child: Text(tr('Xóa khóa')),
            ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'set'),
            child: Text(tr('Lưu')),
          ),
        ],
      ),
    );

    if (saved == null) return;
    setState(() => _busy = true);
    try {
      if (saved == 'clear') {
        final old = oldCtrl.text;
        await _client.clearPortalPassword(_info.ip, password: old.isEmpty ? null : old);
        await _client.forgetPassword(serial: _info.serial, ip: _info.ip);
        setState(() => _info = _info.copyWith(locked: false));
        appNotification.showSuccess(title: tr('Đã xóa khóa'), message: tr('Gateway không còn mật khẩu'));
      } else {
        final pass = newCtrl.text.trim();
        if (pass.length < 4) {
          throw const ZkGatewayException('Mật khẩu phải từ 4 ký tự');
        }
        await _client.setPortalPassword(
          _info.ip,
          pass,
          oldPassword: locked ? oldCtrl.text : null,
        );
        await _client.rememberPassword(pass, serial: _info.serial, ip: _info.ip);
        setState(() => _info = _info.copyWith(locked: true));
        appNotification.showSuccess(title: tr('Đã lưu mật khẩu'), message: tr('Gateway đã được khóa'));
      }
    } on ZkGatewayAuthException {
      appNotification.showError(title: tr('Sai mật khẩu cũ'), message: tr('Không đổi được khóa'));
    } catch (e) {
      appNotification.showError(
        title: tr('Thất bại'),
        message: tr(e is ZkGatewayException ? e.message : e.toString()),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _action(String what, String label, {bool confirm = false}) async {
    if (confirm && !await _confirm(label)) return;

    setState(() => _busy = true);
    try {
      await _client.runAction(_info.ip, what);
      if (!mounted) return;
      appNotification.showSuccess(
        title: tr('Đã gửi lệnh'),
        message: tr(label),
      );
    } catch (e) {
      if (!mounted) return;
      _notifyGatewayError(e, fallbackTitle: 'Không thực hiện được');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _refresh(silent: true);
  }

  /// Reset cấu hình gateway (ESP): xóa NVS → WiFi, IP máy chấm công,
  /// mật khẩu portal. Gateway reboot về AP mode (SBOX-Gateway-XXXX).
  /// KHÔNG xóa dữ liệu trên máy chấm công.
  /// 2 lớp confirm để tránh bấm nhầm.
  /// Lớp 2 phải gõ chính xác "RESET" (giống portal web).
  Future<void> _factoryResetEsp() async {
    if (_busy) return;

    // Lớp 1 - cảnh báo chung
    final ok1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Reset cấu hình mạch ESP')),
        content: SingleChildScrollView(
          child: Text(
            tr(
              'Mạch ESP gateway sẽ bị xóa cấu hình:\n'
              '• Mạng WiFi đang kết nối\n'
              '• Địa chỉ IP máy chấm công\n'
              '• Mật khẩu cổng thông tin (nếu có)\n\n'
              'Sau khi reset, mạch phát sóng SBOX-Gateway-XXXX\n'
              '(mật khẩu sbox12345). Dùng WiFi đó để mở 192.168.4.1 '
              'hoặc bấm Thêm gateway trong app.\n\n'
              '⚠️ Máy chấm công KHÔNG bị ảnh hưởng — log + nhân viên '
              'vẫn còn trên máy và trên sboxhrm.',
            ),
            style: const TextStyle(fontSize: 13, height: 1.45),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Huỷ')),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Tôi đã hiểu, tiếp tục')),
          ),
        ],
      ),
    );
    if (ok1 != true || !mounted) return;

    // Lớp 2 - gõ RESET để xác nhận
    final ctrl = TextEditingController();
    final ok2 = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xác nhận lần cuối')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Gõ RESET (chữ in hoa) để xác nhận reset cấu hình gateway:'),
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'RESET',
                border: const OutlineInputBorder(),
                errorText: ctrl.text.trim() != 'RESET' && ctrl.text.isNotEmpty
                    ? tr('Phải gõ đúng RESET')
                    : null,
              ),
              onChanged: (_) {
                if (ctx.mounted) (ctx as Element).markNeedsBuild();
              },
              onSubmitted: (v) {
                if (v.trim() == 'RESET') Navigator.pop(ctx, true);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Huỷ')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (ctrl.text.trim() != 'RESET') return;
              Navigator.pop(ctx, true);
            },
            child: Text(tr('Reset gateway')),
          ),
        ],
      ),
    );
    if (ok2 != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await _client.runAction(_info.ip, 'factory_reset');
      if (!mounted) return;
      appNotification.showSuccess(
        title: tr('Đã reset cấu hình mạch ESP'),
        message: tr(
          'Mạch đang reboot về chế độ cấu hình. '
          'Nối điện thoại vào WiFi SBOX-Gateway-XXXX (mật khẩu sbox12345), '
          'rồi bấm Thêm gateway để cấu hình lại. '
          'Dữ liệu trên máy chấm công không bị xóa.',
        ),
      );
      // Sau reset, gateway ngắt LAN → dừng timer và về danh sách.
      _timer?.cancel();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      _notifyGatewayError(e, fallbackTitle: 'Reset thất bại');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Khôi phục xuất xưởng MÁY CHẤM CÔNG: xóa sạch log + nhân viên + vân tay
  /// + khuôn mặt + thẻ trên máy ZK (gọi CLEAR_DATA qua ESP).
  /// Đây KHÔNG phải reset ESP — ESP vẫn chạy bình thường, WiFi/IP máy giữ nguyên.
  /// 2 lớp confirm để tránh bấm nhầm (mất toàn bộ dữ liệu trên máy).
  /// Lớp 2 phải gõ chính xác "RESET" (giống portal web).
  Future<void> _factoryResetDevice() async {
    if (_busy) return;

    final users = _status?.users ?? 0;
    final records = _status?.records ?? 0;

    // Lớp 1 - cảnh báo chung
    final ok1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Khôi phục xuất xưởng máy ZK')),
        content: SingleChildScrollView(
          child: Text(
            tr(
              'Máy chấm công sẽ bị XÓA SẠCH:\n'
              '• Toàn bộ log chấm công ($records bản ghi)\n'
              '• Toàn bộ nhân viên + vân tay + khuôn mặt + thẻ ($users người)\n'
              '• Cấu hình riêng của máy (mật khẩu máy, menu, ...)\n\n'
              'Sau khi reset:\n'
              '• Mạch ESP vẫn hoạt động bình thường (WiFi, IP máy giữ nguyên).\n'
              '• Máy chấm công restart và cần đăng ký lại nhân viên từ đầu.\n'
              '• Dữ liệu chấm công trên sboxhrm vẫn giữ nguyên.\n\n'
              '⚠️ Thao tác này KHÔNG thể hoàn tác. '
              'Không nhầm với “Reset cấu hình mạch ESP”.',
            ),
            style: const TextStyle(fontSize: 13, height: 1.45),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Huỷ')),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Tôi đã hiểu, tiếp tục')),
          ),
        ],
      ),
    );
    if (ok1 != true || !mounted) return;

    // Lớp 2 - gõ RESET để xác nhận (giống portal web)
    final ctrl = TextEditingController();
    final ok2 = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xác nhận lần cuối')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Gõ RESET (chữ in hoa) để xác nhận xóa toàn bộ dữ liệu '
                  'trên máy chấm công:'),
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'RESET',
                border: const OutlineInputBorder(),
                errorText: ctrl.text.trim() != 'RESET' && ctrl.text.isNotEmpty
                    ? tr('Phải gõ đúng RESET')
                    : null,
              ),
              onChanged: (_) {
                if (ctx.mounted) (ctx as Element).markNeedsBuild();
              },
              onSubmitted: (v) {
                if (v.trim() == 'RESET') Navigator.pop(ctx, true);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Huỷ')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (ctrl.text.trim() != 'RESET') return;
              Navigator.pop(ctx, true);
            },
            child: Text(tr('Xóa sạch máy chấm công')),
          ),
        ],
      ),
    );
    if (ok2 != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final msg = await _client.deviceControl(_info.ip, action: 'factory_reset');
      if (!mounted) return;
      appNotification.showSuccess(
        title: tr('Đã xóa sạch máy chấm công'),
        message: msg.isNotEmpty ? msg : tr('Máy đang khởi động lại...'),
      );
      // Máy restart → ESP sẽ tự identify lại, không cần stop timer
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted) return;
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      _notifyGatewayError(e, fallbackTitle: 'Xóa thất bại');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String what) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xác nhận')),
        content: Text(tr('Thực hiện: $what?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Huỷ')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Đồng ý')),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _rename() async {
    final ctrl = TextEditingController(text: _info.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Đổi tên gateway')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 40,
          decoration: InputDecoration(
            hintText: tr('VD: Cửa trước - tầng 1'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Huỷ')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(tr('Lưu')),
          ),
        ],
      ),
    );
    if (name == null) return;

    try {
      await _client.saveConfig(_info.ip, {'gwName': name});
      if (!mounted) return;
      setState(() => _info = _info.copyWith(name: name));
      appNotification.showSuccess(
        title: tr('Đã đổi tên'),
        message: name.isEmpty ? tr('Đã xoá tên gợi nhớ') : name,
      );
    } catch (e) {
      if (!mounted) return;
      _notifyGatewayError(e, fallbackTitle: 'Đổi tên thất bại');
    }
  }

  Future<void> _openReconfigure() async {
    final updated = await Navigator.of(context).push<ZkGatewayInfo>(
      MaterialPageRoute(builder: (_) => ZkGatewaySetupScreen(existing: _info)),
    );
    if (updated != null && mounted) {
      setState(() => _info = updated);
    }
    await _refresh(silent: true);
  }

  Future<void> _openAutoClearSettings() async {
    setState(() => _busy = true);
    ZkGatewayConfig? cfg;
    try {
      cfg = await _client.fetchConfig(_info.ip);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _notifyGatewayError(e, fallbackTitle: 'Không đọc được cấu hình');
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);

    var enabled = cfg.autoClearAttlog;
    final dayCtrl = TextEditingController(text: '${cfg.autoClearDay}');
    final hourCtrl = TextEditingController(text: '${cfg.autoClearHour}');
    final minCtrl = TextEditingController(text: '${cfg.autoClearMin}');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(tr('Xóa log định kỳ')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(
                      'Máy chỉ xóa toàn bộ log (không theo khoảng ngày). '
                      'Gateway đồng bộ lên server trước rồi mới xóa. '
                      'Dữ liệu trên sboxhrm vẫn giữ.',
                    ),
                    style: const TextStyle(fontSize: 13, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Bật lịch hàng tháng')),
                    value: enabled,
                    onChanged: (v) => setLocal(() => enabled = v),
                  ),
                  TextField(
                    controller: dayCtrl,
                    enabled: enabled,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: tr('Ngày trong tháng (1–28)'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: hourCtrl,
                          enabled: enabled,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(labelText: tr('Giờ (0–23)')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: minCtrl,
                          enabled: enabled,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(labelText: tr('Phút (0–59)')),
                        ),
                      ),
                    ],
                  ),
                  if (cfg!.lastAutoClearYm > 0) ...[
                    const SizedBox(height: 10),
                    Text(
                      tr(
                        'Lần xóa gần nhất: '
                        '${cfg.lastAutoClearYm % 100}/${cfg.lastAutoClearYm ~/ 100}',
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Huỷ')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('Lưu')),
              ),
            ],
          ),
        );
      },
    );

    if (saved != true) return;

    var day = int.tryParse(dayCtrl.text.trim()) ?? 1;
    var hour = int.tryParse(hourCtrl.text.trim()) ?? 2;
    var min = int.tryParse(minCtrl.text.trim()) ?? 0;
    day = day.clamp(1, 28);
    hour = hour.clamp(0, 23);
    min = min.clamp(0, 59);

    setState(() => _busy = true);
    try {
      await _client.saveConfig(_info.ip, {
        'autoClearAttlog': enabled,
        'autoClearDay': day,
        'autoClearHour': hour,
        'autoClearMin': min,
      });
      if (!mounted) return;
      appNotification.showSuccess(
        title: tr('Đã lưu'),
        message: enabled
            ? tr('Xóa log lúc $hour:${min.toString().padLeft(2, '0')} ngày $day hàng tháng')
            : tr('Đã tắt xóa log định kỳ'),
      );
      await _refresh(silent: true);
    } catch (e) {
      if (!mounted) return;
      _notifyGatewayError(e, fallbackTitle: 'Lưu thất bại');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _portalIp =>
      (_status?.wifiIp.isNotEmpty == true) ? _status!.wifiIp : _info.ip;

  // Lưu helper mở portal web (chỉ dùng nội bộ kỹ thuật khi cần debug nâng cao).
  // Bỏ khỏi UI người dùng cuối; có thể gọi lại từ menu ẩn nếu cần trong tương lai.
  // ignore: unused_element
  Future<void> _openPortal({bool useHost = false}) async {
    final url = useHost
        ? ZkGatewayClient.portalUrl
        : ZkGatewayClient.portalUrlForIp(_portalIp);
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      appNotification.showError(
        title: tr('Không mở được trình duyệt'),
        message: tr('Hãy mở tay: $url'),
      );
    }
  }

  // ignore: unused_element
  Future<void> _copyPortalLink() async {
    final url = ZkGatewayClient.portalUrlForIp(_portalIp);
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    appNotification.showSuccess(title: tr('Đã sao chép'), message: url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HrmPageChrome.scaffoldBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          _info.displayName,
          style: const TextStyle(
            color: HrmPageChrome.textDark,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        iconTheme: const IconThemeData(color: HrmPageChrome.textDark),
        actions: [
          IconButton(
            tooltip: tr('Đổi tên'),
            onPressed: _busy ? null : _rename,
            icon: const Icon(Icons.drive_file_rename_outline, size: 21),
          ),
          IconButton(
            tooltip: tr('Làm mới'),
            onPressed: _busy ? null : () => _refresh(),
            icon: const Icon(Icons.refresh, size: 21),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
          children: [
            if (_loading && _status == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_loadError != null && _status == null)
              _errorCard()
            else if (_status != null) ...[
              _connectionCard(_status!),
              const SizedBox(height: 14),
              _wifiCard(),
              const SizedBox(height: 14),
              _deviceSimpleCard(_status!),
              const SizedBox(height: 14),
              _autoClearCard(_status!),
              const SizedBox(height: 14),
              _syncActionsCard(_status!),
              const SizedBox(height: 14),
              _advancedSection(_status!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(title),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
              color: HrmPageChrome.textMuted,
            ),
          ),
          const SizedBox(height: 13),
          ...children,
        ],
      ),
    );
  }

  Widget _errorCard() {
    return _card(title: 'Không liên lạc được', children: [
      Text(
        _loadError ?? tr('Không kết nối được gateway'),
        style: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFFDC2626),
        ),
      ),
      const SizedBox(height: 12),
      GatewayNoteBox(
        text: _loadGuide ?? ZkGatewayUserError.connectionChecklist,
        icon: Icons.help_outline,
        color: const Color(0xFFF59E0B),
      ),
      const SizedBox(height: 12),
      _actionRow(
        icon: Icons.refresh,
        label: 'Thử kết nối lại',
        desc: 'Gọi lại API trạng thái gateway',
        onTap: () => _refresh(),
        last: true,
      ),
    ]);
  }

  /// Lưới 2 cột các ô nhãn/giá trị.
  Widget _tiles(List<({String label, String value})> items) {
    return LayoutBuilder(
      builder: (context, c) {
        final twoCols = c.maxWidth > 380;
        final width = twoCols ? (c.maxWidth - 8) / 2 : c.maxWidth;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .map((e) => SizedBox(
                    width: width,
                    child: GatewayInfoTile(label: e.label, value: e.value),
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _connectionCard(ZkGatewayStatus s) {
    final hint = ZkGatewayUserError.statusHint(s);
    return _card(title: 'Trạng thái', children: [
      Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          GatewayStatusChip(label: s.wifiConnected ? 'WiFi OK' : 'Mất WiFi', ok: s.wifiConnected),
          GatewayStatusChip(
            label: s.deviceOnline ? 'Máy chấm công OK' : 'Mất máy chấm công',
            ok: s.deviceOnline,
          ),
          GatewayStatusChip(
            label: s.serverOnline ? 'Máy chủ OK' : 'Mất máy chủ',
            ok: s.serverOnline,
          ),
          if (s.apActive) const GatewayStatusChip(label: 'Sóng cấu hình đang bật', ok: true),
        ],
      ),
      if (s.error.isNotEmpty) ...[
        const SizedBox(height: 12),
        GatewayNoteBox(
          text: s.error,
          icon: Icons.error_outline,
          color: const Color(0xFFDC2626),
        ),
      ],
      if (hint != null) ...[
        const SizedBox(height: 12),
        GatewayNoteBox(
          text: hint,
          icon: Icons.lightbulb_outline,
          color: const Color(0xFFF59E0B),
        ),
      ],
      const SizedBox(height: 12),
      _tiles([
        (label: 'Địa chỉ gateway', value: s.wifiIp.isEmpty ? _info.ip : s.wifiIp),
      ]),
    ]);
  }

  Widget _wifiCard() {
    final ssid = _config?.wifiSsid.trim() ?? '';
    return _card(title: 'WiFi', children: [
      _tiles([
        (label: 'Mạng đang dùng', value: ssid.isEmpty ? tr('chưa đọc được') : ssid),
        (
          label: 'Địa chỉ gateway',
          value: (_status?.wifiIp.isNotEmpty == true) ? _status!.wifiIp : _info.ip,
        ),
      ]),
      const SizedBox(height: 12),
      _actionRow(
        icon: Icons.wifi,
        label: 'Đổi WiFi / cấu hình máy',
        desc: 'Chọn mạng nhà và IP máy chấm công',
        onTap: _openReconfigure,
        last: true,
      ),
    ]);
  }

  Widget _deviceSimpleCard(ZkGatewayStatus s) {
    final deviceIp = _config?.deviceIp.trim() ?? _info.deviceIp;
    return _card(title: 'Máy chấm công', children: [
      _tiles([
        (label: 'IP máy', value: deviceIp.isEmpty ? '-' : deviceIp),
        (label: 'Số seri', value: s.serial.isEmpty ? tr('chưa đọc được') : s.serial),
        (label: 'Nhân viên', value: '${s.users}'),
        (label: 'Bản ghi trên máy', value: '${s.records}'),
      ]),
      const SizedBox(height: 12),
      _actionRow(
        icon: Icons.fingerprint,
        label: 'Quản lý trên máy',
        desc: 'Nhân viên · vân tay · mở cửa · xem log',
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ZkGatewayDeviceScreen(info: _info),
            ),
          );
        },
        last: true,
      ),
    ]);
  }

  Widget _autoClearCard(ZkGatewayStatus s) {
    final cfg = _config;
    final enabled = cfg?.autoClearAttlog == true;
    final schedule = cfg == null
        ? tr('Đang tải...')
        : (enabled
            ? tr(
                'Ngày ${cfg.autoClearDay} · '
                '${cfg.autoClearHour.toString().padLeft(2, '0')}:'
                '${cfg.autoClearMin.toString().padLeft(2, '0')} hàng tháng',
              )
            : tr('Đang tắt'));
    final ym = s.lastAutoClearYm;
    final lastClear = ym > 0 ? '${ym % 100}/${ym ~/ 100}' : tr('chưa có');
    return _card(title: 'Xóa dữ liệu định kỳ', children: [
      _tiles([
        (label: 'Lịch xóa log trên máy', value: schedule),
        (label: 'Lần xóa gần nhất', value: lastClear),
      ]),
      const SizedBox(height: 8),
      Text(
        tr('Gateway đồng bộ lên máy chủ trước rồi mới xóa log trên máy. '
            'Dữ liệu trên sboxhrm vẫn giữ.'),
        style: const TextStyle(
          fontSize: 12,
          height: 1.4,
          color: HrmPageChrome.textMuted,
        ),
      ),
      const SizedBox(height: 12),
      _actionRow(
        icon: Icons.delete_sweep_outlined,
        label: 'Cấu hình xóa định kỳ',
        desc: 'Bật/tắt và chọn ngày giờ trong tháng',
        onTap: _openAutoClearSettings,
        last: true,
      ),
    ]);
  }

  Widget _syncActionsCard(ZkGatewayStatus s) {
    return _card(title: 'Đồng bộ', children: [
      _tiles([
        (label: 'Đã đẩy lên máy chủ', value: '${s.uploadedTotal}'),
        (label: 'Lô gần nhất', value: '${s.uploadedLast}'),
      ]),
      const SizedBox(height: 12),
      _actionRow(
        icon: Icons.sync,
        label: 'Đồng bộ lại chấm công',
        desc: 'Đọc và đẩy phần còn thiếu lên máy chủ',
        onTap: () => _action('resync', 'Đồng bộ lại toàn bộ chấm công'),
      ),
      _actionRow(
        icon: Icons.group_add_outlined,
        label: 'Đẩy danh sách nhân viên',
        desc: 'Gửi nhân viên trên máy lên máy chủ',
        onTap: () => _action('users', 'Đẩy danh sách nhân viên'),
      ),
      _actionRow(
        icon: Icons.schedule,
        label: 'Chỉnh giờ máy chấm công',
        desc: 'Đặt đồng hồ máy theo giờ chuẩn',
        onTap: () => _action('clock', 'Chỉnh giờ máy chấm công'),
        last: true,
      ),
    ]);
  }

  Widget _advancedSection(ZkGatewayStatus s) {
    return _card(title: 'Dành cho kỹ thuật', children: [
      InkWell(
        onTap: () => setState(() => _advancedOpen = !_advancedOpen),
        borderRadius: BorderRadius.circular(9),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  tr(_advancedOpen
                      ? 'Thu gọn cấu hình nâng cao'
                      : 'Hiện thêm (web, mật khẩu, OTA…)'),
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: HrmPageChrome.textDark,
                  ),
                ),
              ),
              Icon(
                _advancedOpen ? Icons.expand_less : Icons.expand_more,
                color: HrmPageChrome.textMuted,
              ),
            ],
          ),
        ),
      ),
      if (_advancedOpen) ...[
        const Divider(height: 1),
        const SizedBox(height: 4),
        Text(
          tr('Các mục dưới đây dành cho kỹ thuật viên. Người dùng cửa hàng '
              'thường chỉ cần các khối phía trên.'),
          style: const TextStyle(
            fontSize: 12,
            height: 1.4,
            color: HrmPageChrome.textMuted,
          ),
        ),
        const SizedBox(height: 8),
        _actionRow(
          icon: Icons.lock_outline,
          label: 'Mật khẩu bảo mật',
          desc: 'Khóa cấu hình gateway',
          onTap: _openPasswordSettings,
        ),
        _actionRow(
          icon: Icons.restart_alt,
          label: 'Xóa mốc đồng bộ',
          desc: 'Gửi lại mọi bản ghi còn trên máy',
          onTap: () => _action('resetmark', 'Xoá mốc đồng bộ', confirm: true),
        ),
        _actionRow(
          icon: Icons.power_settings_new,
          label: 'Khởi động lại gateway',
          desc: 'Mạch khởi động lại sau 1 giây',
          onTap: () => _action('reboot', 'Khởi động lại gateway', confirm: true),
          danger: true,
        ),
        _actionRow(
          icon: Icons.restore,
          label: 'Reset cấu hình mạch ESP',
          desc: 'Xóa WiFi/IP đã lưu trên mạch — KHÔNG xóa dữ liệu máy ZK',
          onTap: _factoryResetEsp,
          danger: true,
        ),
        _actionRow(
          icon: Icons.factory_outlined,
          label: 'Khôi phục xuất xưởng máy ZK',
          desc: 'Xóa sạch log + nhân viên + vân tay trên máy (CLEAR_DATA)',
          onTap: _factoryResetDevice,
          danger: true,
          last: true,
        ),
        const SizedBox(height: 8),
        _firmwareCompact(s),
      ],
    ]);
  }

  Widget _firmwareCompact(ZkGatewayStatus s) {
    final local = s.version.isNotEmpty ? s.version : (_info.version.isEmpty ? '-' : _info.version);
    final remote = _serverVersion ?? '-';
    final sizeKb = _serverBytes != null ? '${(_serverBytes! / 1024).round()} KB' : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(
            _otaChecking
                ? 'Firmware: đang kiểm tra máy chủ…'
                : 'Firmware: thiết bị $local · máy chủ $remote'
                    '${sizeKb != null ? ' ($sizeKb)' : ''}',
          ),
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: HrmPageChrome.textMuted,
          ),
        ),
        if (_serverNotes != null && _serverNotes!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _serverNotes!,
              style: const TextStyle(
                fontSize: 12,
                color: HrmPageChrome.textMuted,
                height: 1.35,
              ),
            ),
          ),
        if (_updateAvailable)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              tr('Có bản mới trên máy chủ'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFFD97706),
              ),
            ),
          ),
        _actionRow(
          icon: Icons.system_update_alt,
          label: _updateAvailable ? 'Cập nhật firmware' : 'Nạp lại firmware máy chủ',
          desc: 'OTA qua WiFi LAN',
          onTap: _updateFirmwareFromServer,
        ),
        _actionRow(
          icon: Icons.refresh,
          label: 'Kiểm tra bản firmware',
          desc: 'Hỏi máy chủ sboxhrm.com',
          onTap: () async {
            await _loadServerRelease();
            if (!mounted) return;
            appNotification.showSuccess(
              title: tr('Firmware'),
              message: tr(_serverVersion != null
                  ? 'Máy chủ: $_serverVersion'
                  : (_serverReleaseError ?? 'Chưa có bản')),
            );
          },
          last: true,
        ),
      ],
    );
  }


  Widget _actionRow({
    required IconData icon,
    required String label,
    required String desc,
    required VoidCallback onTap,
    bool danger = false,
    bool last = false,
  }) {
    final color = danger ? const Color(0xFFDC2626) : HrmPageChrome.primaryNavy;
    return Column(
      children: [
        InkWell(
          onTap: _busy ? null : onTap,
          borderRadius: BorderRadius.circular(9),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(label),
                        style: TextStyle(
                          fontSize: 13.8,
                          fontWeight: FontWeight.w700,
                          color: danger ? color : HrmPageChrome.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tr(desc),
                        style: const TextStyle(
                          fontSize: 11.8,
                          color: HrmPageChrome.textMuted,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 19, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
        ),
        if (!last) const Divider(height: 1),
      ],
    );
  }
}
