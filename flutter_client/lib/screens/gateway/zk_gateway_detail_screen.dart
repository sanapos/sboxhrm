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
  Timer? _timer;
  bool _loading = true;
  bool _busy = false;
  String? _loadError;

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
      appNotification.showError(
        title: tr('Cập nhật thất bại'),
        message: tr(e is ZkGatewayException ? e.message : e.toString()),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final status = await _client.fetchStatus(_info.ip);
      ZkGatewayInfo? info;
      if (!silent || (_deviceAppSha == null || _deviceAppSha!.isEmpty)) {
        try {
          info = await _client.fetchInfo(_info.ip);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _status = status;
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
      });
    } on ZkGatewayAuthException {
      if (!mounted) return;
      final ok = await _promptUnlock();
      if (ok) {
        await _refresh(silent: silent);
      } else {
        setState(() {
          _loading = false;
          _loadError = tr('Gateway đang khóa — nhập mật khẩu để quản lý');
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e is ZkGatewayException ? e.message : tr('Không kết nối được thiết bị');
      });
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
      appNotification.showError(
        title: tr('Không thực hiện được'),
        message: tr(e is ZkGatewayException ? e.message : e.toString()),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _refresh(silent: true);
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
      appNotification.showError(
        title: tr('Đổi tên thất bại'),
        message: tr(e is ZkGatewayException ? e.message : e.toString()),
      );
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
      appNotification.showError(
        title: tr('Không đọc được cấu hình'),
        message: tr(e is ZkGatewayException ? e.message : e.toString()),
      );
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
    } catch (e) {
      if (!mounted) return;
      appNotification.showError(
        title: tr('Lưu thất bại'),
        message: tr(e is ZkGatewayException ? e.message : e.toString()),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _portalIp =>
      (_status?.wifiIp.isNotEmpty == true) ? _status!.wifiIp : _info.ip;

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
              _webPortalCard(),
              const SizedBox(height: 14),
              _deviceCard(_status!),
              const SizedBox(height: 14),
              _syncCard(_status!),
              const SizedBox(height: 14),
              _firmwareCard(_status!),
              const SizedBox(height: 14),
              _actionsCard(),
              const SizedBox(height: 14),
              _systemCard(_status!),
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
        _loadError ?? '',
        style: const TextStyle(fontSize: 13.5, color: Color(0xFFDC2626)),
      ),
      const SizedBox(height: 12),
      const GatewayNoteBox(
        text: 'Gateway có thể đã đổi địa chỉ IP. Quay lại danh sách và dò tìm lại.',
        icon: Icons.help_outline,
        color: Color(0xFFF59E0B),
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

  Widget _webPortalCard() {
    final ipUrl = ZkGatewayClient.portalUrlForIp(_portalIp);
    return _card(title: 'Máy chấm công (trên LAN)', children: [
      Text(
        tr('Quản lý nhân viên, đăng ký vân tay, mở cửa và xem/xuất chấm công '
            'trực tiếp trong app — không cần mở trình duyệt.'),
        style: const TextStyle(
          fontSize: 12.5,
          height: 1.45,
          color: HrmPageChrome.textMuted,
        ),
      ),
      const SizedBox(height: 12),
      _actionRow(
        icon: Icons.fingerprint,
        label: 'Quản lý máy chấm công',
        desc: 'Nhân viên · vân tay · mở cửa · log',
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ZkGatewayDeviceScreen(info: _info),
            ),
          );
        },
      ),
      _actionRow(
        icon: Icons.open_in_browser,
        label: 'Mở web theo IP (tuỳ chọn)',
        desc: ipUrl,
        onTap: () => _openPortal(),
      ),
      _actionRow(
        icon: Icons.language,
        label: 'Mở http://sboxadms.local',
        desc: 'Trang web trên mạch nếu cần',
        onTap: () => _openPortal(useHost: true),
      ),
      _actionRow(
        icon: Icons.copy,
        label: 'Sao chép link web',
        desc: ipUrl,
        onTap: _copyPortalLink,
        last: true,
      ),
    ]);
  }

  Widget _connectionCard(ZkGatewayStatus s) {
    return _card(title: 'Kết nối', children: [
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
      const SizedBox(height: 12),
      _tiles([
        (label: 'Địa chỉ gateway', value: s.wifiIp.isEmpty ? _info.ip : s.wifiIp),
        (label: 'Độ mạnh sóng', value: '${s.rssi} dBm'),
      ]),
    ]);
  }

  Widget _deviceCard(ZkGatewayStatus s) {
    return _card(title: 'Máy chấm công', children: [
      _tiles([
        (label: 'Số seri', value: s.serial.isEmpty ? tr('chưa đọc được') : s.serial),
        (label: 'Nền tảng', value: s.devicePlatform.isEmpty ? '-' : s.devicePlatform),
        (label: 'Firmware máy', value: s.deviceFirmware.isEmpty ? '-' : s.deviceFirmware),
        (label: 'Nhân viên', value: '${s.users}'),
        (label: 'Vân tay', value: '${s.fingers}'),
        (label: 'Bản ghi trên máy', value: '${s.records}'),
      ]),
    ]);
  }

  Widget _syncCard(ZkGatewayStatus s) {
    final ym = s.lastAutoClearYm;
    final lastClear = ym > 0
        ? '${ym % 100}/${ym ~/ 100}'
        : tr('chưa có');
    return _card(title: 'Đồng bộ', children: [
      _tiles([
        (label: 'Đã đẩy lên máy chủ', value: '${s.uploadedTotal}'),
        (label: 'Lô gần nhất', value: '${s.uploadedLast}'),
        (label: 'Lệnh đã thực thi', value: '${s.commands}'),
        (label: 'Xóa log định kỳ gần nhất', value: lastClear),
      ]),
    ]);
  }

  Widget _firmwareCard(ZkGatewayStatus s) {
    final local = s.version.isNotEmpty ? s.version : (_info.version.isEmpty ? '-' : _info.version);
    final remote = _serverVersion ?? '-';
    final sizeKb = _serverBytes != null ? '${(_serverBytes! / 1024).round()} KB' : '-';
    final statusText = _otaChecking
        ? tr('Đang kiểm tra...')
        : (_serverReleaseError != null
            ? (_serverReleaseError!)
            : (_updateAvailable
                ? tr('Có bản mới trên máy chủ')
                : tr('Đã là bản mới nhất (hoặc chưa có trên server)')));

    return _card(title: 'Firmware gateway (OTA)', children: [
      _tiles([
        (label: 'Trên thiết bị', value: local),
        (label: 'Trên máy chủ', value: remote),
        if (_deviceAppSha != null && _deviceAppSha!.isNotEmpty)
          (label: 'SHA thiết bị', value: _deviceAppSha!),
        if (_serverAppSha != null && _serverAppSha!.isNotEmpty)
          (label: 'SHA máy chủ', value: _serverAppSha!),
        (label: 'Dung lượng', value: sizeKb),
      ]),
      const SizedBox(height: 10),
      Text(
        statusText,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: _updateAvailable ? const Color(0xFFD97706) : HrmPageChrome.textMuted,
        ),
      ),
      if (_serverNotes != null && _serverNotes!.trim().isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(
          _serverNotes!,
          style: const TextStyle(fontSize: 12, color: HrmPageChrome.textMuted, height: 1.35),
        ),
      ],
      const SizedBox(height: 12),
      _actionRow(
        icon: Icons.system_update_alt,
        label: _updateAvailable ? 'Cập nhật từ máy chủ' : 'Nạp lại bản trên máy chủ',
        desc: 'Tải zk_gateway.bin rồi OTA qua WiFi LAN',
        onTap: _updateFirmwareFromServer,
      ),
      _actionRow(
        icon: Icons.refresh,
        label: 'Kiểm tra bản mới',
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
    ]);
  }

  Widget _systemCard(ZkGatewayStatus s) {
    final h = s.uptimeSeconds ~/ 3600;
    final m = (s.uptimeSeconds % 3600) ~/ 60;
    return _card(title: 'Hệ thống', children: [
      _tiles([
        (label: 'Thời gian chạy', value: '${h}h ${m}m'),
        (label: 'RAM còn trống', value: '${(s.freeHeap / 1024).round()} KB'),
        (label: 'Firmware gateway', value: s.version.isEmpty ? '-' : s.version),
      ]),
      const SizedBox(height: 12),
      GatewayNoteBox(
        text: 'Dùng thẻ Firmware gateway (OTA) phía trên để cập nhật từ máy chủ, '
            'hoặc mở ${ZkGatewayClient.portalUrl} / '
            'http://${s.wifiIp.isEmpty ? _info.ip : s.wifiIp} trên trình duyệt.',
        icon: Icons.system_update_alt,
      ),
    ]);
  }

  Widget _actionsCard() {
    return _card(title: 'Thao tác', children: [
      _actionRow(
        icon: Icons.sync,
        label: 'Đồng bộ lại toàn bộ chấm công',
        desc: 'Đọc lại từ mốc hiện tại và đẩy phần còn thiếu',
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
        desc: 'Đặt lại đồng hồ máy theo giờ chuẩn',
        onTap: () => _action('clock', 'Chỉnh giờ máy chấm công'),
      ),
      _actionRow(
        icon: Icons.restart_alt,
        label: 'Xoá mốc đồng bộ',
        desc: 'Gửi lại mọi bản ghi còn trên máy, máy chủ tự loại trùng',
        onTap: () => _action('resetmark', 'Xoá mốc đồng bộ', confirm: true),
      ),
      _actionRow(
        icon: Icons.fingerprint,
        label: 'Quản lý máy chấm công',
        desc: 'Nhân viên, vân tay, mở cửa, xuất CSV trong app',
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ZkGatewayDeviceScreen(info: _info),
            ),
          );
        },
      ),
      _actionRow(
        icon: Icons.lock_outline,
        label: 'Mật khẩu bảo mật',
        desc: 'Khóa cấu hình gateway; quên thì reset qua sóng AP',
        onTap: _openPasswordSettings,
      ),
      _actionRow(
        icon: Icons.delete_sweep_outlined,
        label: 'Xóa log định kỳ theo tháng',
        desc: 'Chọn ngày/giờ; đồng bộ trước rồi mới xóa trên máy',
        onTap: _openAutoClearSettings,
      ),
      _actionRow(
        icon: Icons.settings_ethernet,
        label: 'Cấu hình lại',
        desc: 'Đổi WiFi, IP máy chấm công, máy chủ',
        onTap: _openReconfigure,
      ),
      _actionRow(
        icon: Icons.power_settings_new,
        label: 'Khởi động lại gateway',
        desc: 'Mạch sẽ khởi động lại sau 1 giây',
        onTap: () => _action('reboot', 'Khởi động lại gateway', confirm: true),
        danger: true,
        last: true,
      ),
    ]);
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
