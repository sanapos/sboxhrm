import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_tr.dart';
import '../../models/zk_gateway.dart';
import '../../services/zk_gateway_client.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/notification_overlay.dart';
import 'zk_gateway_detail_screen.dart';
import 'zk_gateway_setup_screen.dart';
import 'zk_gateway_widgets.dart';

/// Danh sách các gateway ESP32 tìm thấy trong mạng nội bộ.
///
/// Không lấy danh sách từ máy chủ mà dò trực tiếp trong LAN: gateway có thể
/// được DHCP đổi IP bất cứ lúc nào, và lúc cài đặt lần đầu nó còn chưa từng
/// liên lạc với máy chủ.
class ZkGatewayListScreen extends StatefulWidget {
  const ZkGatewayListScreen({super.key});

  @override
  State<ZkGatewayListScreen> createState() => _ZkGatewayListScreenState();
}

class _ZkGatewayListScreenState extends State<ZkGatewayListScreen> {
  final _client = ZkGatewayClient();

  List<ZkGatewayInfo> _gateways = const [];
  bool _scanning = false;
  bool _firstScanDone = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _discover();
  }

  Future<void> _discover() async {
    if (kIsWeb) return;
    setState(() => _scanning = true);
    final found = await _client.discover();
    if (!mounted) return;
    setState(() {
      _gateways = found;
      _scanning = false;
      _firstScanDone = true;
    });
  }

  Future<void> _openSetup() async {
    final added = await Navigator.of(context).push<ZkGatewayInfo>(
      MaterialPageRoute(builder: (_) => const ZkGatewaySetupScreen()),
    );
    if (added != null && mounted) {
      appNotification.showSuccess(
        title: tr('Đã thêm gateway'),
        message: added.displayName,
      );
    }
    await _discover();
  }

  Future<void> _openDetail(ZkGatewayInfo info) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ZkGatewayDetailScreen(info: info)),
    );
    await _discover();
  }

  Future<void> _openWeb(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      appNotification.showError(
        title: tr('Không mở được trình duyệt'),
        message: tr('Hãy mở tay địa chỉ: $url'),
      );
    }
  }

  // ignore: unused_element
  Future<void> _copyLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    appNotification.showSuccess(
      title: tr('Đã sao chép'),
      message: url,
    );
  }

  /// Cho nhập tay IP/hostname khi iOS hoặc router chặn dò tìm UDP.
  Future<void> _addByIp() async {
    final ctrl = TextEditingController(text: ZkGatewayClient.portalHost);
    final host = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Nhập địa chỉ gateway')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: tr('sboxadms.local hoặc 192.168.1.36'),
                labelText: tr('Hostname hoặc IP'),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              tr('Trên iPhone, nếu dò tìm không thấy thì nhập sboxadms.local '
                  'hoặc IP LAN của mạch, rồi bấm Kết nối trong app hoặc Mở web.'),
              style: const TextStyle(fontSize: 12, color: HrmPageChrome.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Huỷ')),
          ),
          TextButton(
            onPressed: () {
              final h = ctrl.text.trim();
              if (h.isEmpty) return;
              Navigator.pop(ctx);
              _openWeb(h.startsWith('http') ? h : 'http://$h');
            },
            child: Text(tr('Mở web')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(tr('Kết nối')),
          ),
        ],
      ),
    );
    if (host == null || host.isEmpty) return;

    final target = host
        .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '')
        .split('/')
        .first
        .trim();
    if (target.isEmpty) return;

    try {
      final info = await _client.fetchInfo(target);
      if (info.ip.isNotEmpty) {
        await _client.rememberHost(info.ip);
      } else {
        await _client.rememberHost(target);
      }
      if (!mounted) return;
      await _openDetail(info);
    } catch (e) {
      if (!mounted) return;
      appNotification.showError(
        title: tr('Không kết nối được'),
        message: tr(e is ZkGatewayException ? e.message : e.toString()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HrmPageChrome.scaffoldBackground(context),
      appBar: HrmPageChrome.appBar(
        title: tr('Gateway WiFi'),
        actions: [
          IconButton(
            tooltip: tr('Nhập IP thủ công'),
            onPressed: _addByIp,
            icon: const Icon(Icons.keyboard_alt_outlined, size: 21),
          ),
          IconButton(
            tooltip: tr('Dò tìm lại'),
            onPressed: _scanning ? null : _discover,
            icon: const Icon(Icons.refresh, size: 21),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _discover,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
          children: [
            _header(),
            const SizedBox(height: 14),
            if (kIsWeb)
              _webNotice()
            else if (_scanning && _gateways.isEmpty)
              _scanningCard()
            else if (_gateways.isEmpty && _firstScanDone)
              _emptyCard()
            else ...[
              for (final gw in _gateways) ...[
                GatewayCard(info: gw, onTap: () => _openDetail(gw)),
                const SizedBox(height: 10),
              ],
              if (_scanning)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: HrmPageChrome.primaryNavy.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.router, color: HrmPageChrome.primaryNavy),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('Gateway chấm công WiFi'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: HrmPageChrome.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      kIsWeb
                          ? tr('Quản lý bằng app điện thoại')
                          : _gateways.isEmpty
                              ? tr('Chưa thấy gateway')
                              : _gateways.length == 1
                                  ? tr('1 gateway trong mạng WiFi')
                                  : '${_gateways.length} ${tr('gateway trong mạng WiFi')}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: HrmPageChrome.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!kIsWeb) const SizedBox(height: 14),
          if (!kIsWeb)
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _openSetup,
                icon: const Icon(Icons.add, size: 19),
                label: Text(
                  tr('Thêm gateway'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: HrmPageChrome.primaryNavy,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          // Phần hướng dẫn kết nối lần đầu đã được gom vào _emptyCard / setup wizard;
          // không còn hiển thị card "Trang web cấu hình trên mạch" trên giao diện người dùng.
        ],
      ),
    );
  }

  /// Trình duyệt không mở được socket UDP, và gọi thẳng HTTP vào thiết bị cũng
  /// bị chặn bởi CORS, nên bản web chỉ hướng dẫn thay vì hỏng giữa đường.
  Widget _webNotice() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.phone_android,
              size: 27,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            tr('Hãy dùng app trên điện thoại'),
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              color: HrmPageChrome.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr('Việc cài đặt gateway cần nói chuyện trực tiếp với mạch trong '
                'mạng nội bộ, điều mà trình duyệt không cho phép.'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: HrmPageChrome.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _scanningCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      alignment: Alignment.center,
      child: Column(
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.6),
          ),
          const SizedBox(height: 14),
          Text(
            tr('Đang dò tìm gateway (Bonjour + UDP)...'),
            style: const TextStyle(
              fontSize: 13.5,
              color: HrmPageChrome.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: Color(0xFFF1F5F9),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.wifi_find, size: 27, color: Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 14),
          Text(
            tr('Chưa tìm thấy gateway nào'),
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              color: HrmPageChrome.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr('Nếu đây là lần cài đầu tiên, bấm "Thêm gateway" ở trên.'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              height: 1.5,
              color: HrmPageChrome.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          GatewayNoteBox(
            text:
                'Cách xử lý khi đã cài mà không thấy:\n'
                '1. Điện thoại cùng WiFi với gateway (không dùng 4G).\n'
                '2. Gateway còn điện.\n'
                '3. Bấm Dò tìm lại — IP có thể đã đổi.\n'
                '4. Vẫn lỗi: dùng nút "Thêm theo IP" để nhập IP gateway vào mạng.',
            icon: Icons.help_outline,
            color: const Color(0xFFF59E0B),
          ),
          const SizedBox(height: 12),
          GatewayNoteBox(
            text: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
                ? 'Điện thoại phải cùng WiFi với gateway. App dò bằng Bonjour '
                    '(_sboxgw._tcp) cộng UDP. Lần đầu iOS hỏi quyền Mạng cục bộ — '
                    'chọn Cho phép rồi bấm dò lại. Nếu đã từ chối: '
                    'Cài đặt → SBOX HRM → Mạng cục bộ → bật. '
                    'Vẫn không thấy thì nhập IP gateway bằng nút "Thêm theo IP".'
                : 'Điện thoại phải ở cùng WiFi với gateway. Một số router bật '
                    'chế độ cách ly thiết bị làm dò tìm không thấy — khi đó dùng '
                    'nút "Thêm theo IP" góc trên để nhập IP của gateway.',
            icon: Icons.help_outline,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addByIp,
              icon: const Icon(Icons.keyboard, size: 18),
              label: Text(tr('Thêm theo IP')),
            ),
          ),
        ],
      ),
    );
  }
}
