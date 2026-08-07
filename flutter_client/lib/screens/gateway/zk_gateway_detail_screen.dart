import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_tr.dart';
import '../../models/zk_gateway.dart';
import '../../services/zk_gateway_client.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/notification_overlay.dart';
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

  @override
  void initState() {
    super.initState();
    _info = widget.info;
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _refresh(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final status = await _client.fetchStatus(_info.ip);
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = e is ZkGatewayException ? e.message : tr('Không kết nối được thiết bị');
      });
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
    return _card(title: 'Trang web trên mạch', children: [
      Text(
        tr('Mở Safari/Chrome để cấu hình đầy đủ: nhân viên, vân tay, mở cửa, '
            'xuất chấm công CSV.'),
        style: const TextStyle(
          fontSize: 12.5,
          height: 1.45,
          color: HrmPageChrome.textMuted,
        ),
      ),
      const SizedBox(height: 12),
      _actionRow(
        icon: Icons.open_in_browser,
        label: 'Mở web theo IP',
        desc: ipUrl,
        onTap: () => _openPortal(),
      ),
      _actionRow(
        icon: Icons.language,
        label: 'Mở http://sboxadms.local',
        desc: 'Tên cố định trong mạng nội bộ',
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
    return _card(title: 'Đồng bộ', children: [
      _tiles([
        (label: 'Đã đẩy lên máy chủ', value: '${s.uploadedTotal}'),
        (label: 'Lô gần nhất', value: '${s.uploadedLast}'),
        (label: 'Lệnh đã thực thi', value: '${s.commands}'),
      ]),
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
        text: 'Mở ${ZkGatewayClient.portalUrl} hoặc '
            'http://${s.wifiIp.isEmpty ? _info.ip : s.wifiIp} trên trình duyệt '
            'để nạp firmware / quản lý máy chấm công.',
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
