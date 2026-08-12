import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_tr.dart';
import '../../models/zk_gateway.dart';
import '../../services/zk_gateway_client.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/notification_overlay.dart';
import 'zk_gateway_user_errors.dart';
import 'zk_gateway_widgets.dart';

/// Trình hướng dẫn thêm gateway mới, theo lối các app thiết bị thông minh:
/// nối điện thoại vào sóng của thiết bị -> chọn WiFi nhà -> chờ nó lên mạng.
///
/// Cố tình không tự động nối WiFi hộ người dùng: iOS không cho phép, còn
/// Android chỉ cho trong điều kiện hạn hẹp và hay thất bại âm thầm. Hướng dẫn
/// từng bước rồi tự kiểm tra lại đáng tin cậy hơn nhiều.
class ZkGatewaySetupScreen extends StatefulWidget {
  const ZkGatewaySetupScreen({super.key, this.existing});

  /// Có giá trị khi cấu hình lại một gateway đã dùng được (bỏ qua bước nối AP).
  final ZkGatewayInfo? existing;

  @override
  State<ZkGatewaySetupScreen> createState() => _ZkGatewaySetupScreenState();
}

class _ZkGatewaySetupScreenState extends State<ZkGatewaySetupScreen> {
  final _client = ZkGatewayClient();

  final _nameCtrl = TextEditingController();
  final _ssidCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _deviceIpCtrl = TextEditingController();
  final _commKeyCtrl = TextEditingController(text: '0');

  static const _fixedServerUrl = 'https://sboxhrm.com';

  /// IP dùng để nói chuyện với ESP trong lúc cài: AP hoặc IP LAN nếu cấu hình lại.
  late String _targetIp;

  int _step = 0;
  bool _busy = false;
  bool _obscurePass = true;

  ZkGatewayInfo? _probed;
  List<ZkWifiAp> _aps = const [];
  ZkGatewayInfo? _result;
  String? _waitMessage;

  bool get _isReconfigure => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _targetIp = widget.existing?.ip ?? ZkGatewayClient.apAddress;
    if (_isReconfigure) {
      _step = 2;
      _probed = widget.existing;
      _prefillFromDevice();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ssidCtrl.dispose();
    _passCtrl.dispose();
    _deviceIpCtrl.dispose();
    _commKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _prefillFromDevice() async {
    try {
      final cfg = await _client.fetchConfig(_targetIp);
      if (!mounted) return;
      setState(() {
        _nameCtrl.text = cfg.gwName;
        _ssidCtrl.text = cfg.wifiSsid;
        _deviceIpCtrl.text = cfg.deviceIp;
        _commKeyCtrl.text = cfg.commKey.toString();
      });
    } catch (_) {
      // Chưa đọc được thì để người dùng nhập tay.
    }
  }

  void _fail(String title, Object err) {
    final mapped = ZkGatewayUserError.from(err, fallbackTitle: title);
    final short =
        mapped.message.split('\n').where((l) => l.trim().isNotEmpty).first;
    appNotification.showError(title: tr(mapped.title), message: tr(short));
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(mapped.title)),
        content: SingleChildScrollView(
          child: Text(
            tr(mapped.message),
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

  // ---------- Bước 1: xác nhận đã nối vào sóng thiết bị ----------

  Future<void> _probeDevice() async {
    setState(() => _busy = true);
    try {
      final info = await _client.fetchInfo(ZkGatewayClient.apAddress);
      if (!mounted) return;
      setState(() {
        _probed = info;
        _targetIp = ZkGatewayClient.apAddress;
        _step = 2;
      });
      await _prefillFromDevice();
      await _scanWifi();
    } catch (e) {
      _fail('Chưa thấy thiết bị', e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------- Bước 2: chọn WiFi và nhập thông số ----------

  Future<void> _scanWifi() async {
    setState(() => _busy = true);
    try {
      final aps = await _client.scanWifi(_targetIp);
      if (!mounted) return;
      setState(() => _aps = aps);
      if (aps.isEmpty) {
        appNotification.showWarning(
          title: tr('Không thấy mạng'),
          message: tr(
            'Gateway không bắt được WiFi 2.4GHz nào. Đưa gần router hơn rồi quét lại.',
          ),
        );
      }
    } catch (e) {
      _fail('Quét WiFi thất bại', e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _validate() {
    if (_ssidCtrl.text.trim().isEmpty) {
      appNotification.showWarning(
        title: tr('Thiếu WiFi'),
        message: tr('Hãy chọn mạng WiFi cho gateway.'),
      );
      return false;
    }
    if (_deviceIpCtrl.text.trim().isEmpty) {
      appNotification.showWarning(
        title: tr('Thiếu IP máy chấm công'),
        message: tr('Nhập IP của máy chấm công trong mạng LAN, ví dụ 192.168.1.35.'),
      );
      return false;
    }
    return true;
  }

  // ---------- Bước 3: lưu rồi chờ thiết bị lên mạng ----------

  Future<void> _saveAndWait() async {
    if (!_validate()) return;

    setState(() {
      _busy = true;
      _step = 3;
      _waitMessage = tr('Đang gửi cấu hình cho thiết bị...');
    });

    final config = ZkGatewayConfig(
      gwName: _nameCtrl.text.trim(),
      wifiSsid: _ssidCtrl.text.trim(),
      deviceIp: _deviceIpCtrl.text.trim(),
      commKey: int.tryParse(_commKeyCtrl.text.trim()) ?? 0,
      serverUrl: _fixedServerUrl,
    );

    try {
      await _client.saveConfig(
        _targetIp,
        config.toPayload(wifiPass: _passCtrl.text),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = 2;
      });
      _fail('Lưu cấu hình thất bại', e);
      return;
    }

    if (!mounted) return;
    setState(() {
      _waitMessage = tr(
        'Đã lưu. Thiết bị đang rời sóng riêng để vào WiFi của bạn.\n'
        'Hãy đưa điện thoại về lại WiFi nhà, app sẽ tự tìm thiết bị.',
      );
    });

    final found = await _client.waitUntilOnline(
      serial: _probed?.serial ?? '',
      duration: const Duration(seconds: 90),
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = found;
      _waitMessage = found != null
          ? null
          : tr('Chưa tìm thấy thiết bị trong mạng. Kiểm tra lại rồi thử dò lần nữa.');
    });
  }

  Future<void> _retryFind() async {
    setState(() {
      _busy = true;
      _waitMessage = tr('Đang dò tìm trong mạng...');
    });
    final found = await _client.waitUntilOnline(
      serial: _probed?.serial ?? '',
      duration: const Duration(seconds: 40),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = found;
      _waitMessage = found != null ? null : tr('Vẫn chưa thấy thiết bị.');
    });
  }

  // ---------- Giao diện ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HrmPageChrome.scaffoldBackground(context),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          tr(_isReconfigure ? 'Cấu hình lại gateway' : 'Thêm gateway'),
          style: const TextStyle(
            color: HrmPageChrome.textDark,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        iconTheme: const IconThemeData(color: HrmPageChrome.textDark),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildStepBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: switch (_step) {
                  0 => _buildIntro(),
                  1 => _buildJoinAp(),
                  2 => _buildConfigForm(),
                  _ => _buildWaiting(),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepBar() {
    const labels = ['Chuẩn bị', 'Nối thiết bị', 'Chọn WiFi', 'Hoàn tất'];
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Row(
        children: List.generate(labels.length, (i) {
          final done = i < _step;
          final active = i == _step;
          final color = done || active
              ? HrmPageChrome.primaryNavy
              : const Color(0xFFCBD5E1);
          return Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 3,
                        color: i == 0 ? Colors.transparent : color,
                      ),
                    ),
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: done || active ? HrmPageChrome.primaryNavy : Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: color, width: 2),
                      ),
                      child: done
                          ? const Icon(Icons.check, size: 13, color: Colors.white)
                          : Center(
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: active ? Colors.white : color,
                                ),
                              ),
                            ),
                    ),
                    Expanded(
                      child: Container(
                        height: 3,
                        color: i == labels.length - 1
                            ? Colors.transparent
                            : (i < _step ? HrmPageChrome.primaryNavy : const Color(0xFFCBD5E1)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  tr(labels[i]),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: active ? HrmPageChrome.primaryNavy : HrmPageChrome.textMuted,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _title(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          tr(text),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: HrmPageChrome.textDark,
          ),
        ),
      );

  Widget _primaryButton(String label, VoidCallback? onTap, {IconData? icon}) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: _busy ? null : onTap,
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Icon(icon ?? Icons.arrow_forward, size: 18),
        label: Text(
          tr(label),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: HrmPageChrome.primaryNavy,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        ),
      ),
    );
  }

  Widget _bullet(int n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: HrmPageChrome.primaryNavy.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$n',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: HrmPageChrome.primaryNavy,
                ),
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              tr(text),
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: HrmPageChrome.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntro() {
    return Column(
      children: [
        _card(children: [
          _title('Gateway làm được gì'),
          Text(
            tr('Gateway là mạch WiFi nhỏ cắm nguồn trong cùng mạng với máy chấm '
                'công. Nó đọc dữ liệu chấm công qua cổng 4370 rồi đẩy lên máy chủ, '
                'nhờ đó máy cũ không có chức năng máy chủ đám mây vẫn đồng bộ được.'),
            style: const TextStyle(
              fontSize: 13.5,
              height: 1.55,
              color: HrmPageChrome.textDark,
            ),
          ),
          const SizedBox(height: 16),
          _title('Cần chuẩn bị'),
          _bullet(1, 'Cấp nguồn USB cho mạch gateway và để gần máy chấm công.'),
          _bullet(2, 'Biết IP của máy chấm công trong mạng LAN (xem trong menu '
              'Comm/Ethernet của máy).'),
          _bullet(3, 'Mật khẩu WiFi 2.4GHz của nơi lắp đặt. Gateway không bắt '
              'được sóng 5GHz.'),
          const SizedBox(height: 12),
          _title('Các bước sẽ làm'),
          _bullet(1, 'Nối điện thoại vào sóng WiFi phát ra từ gateway.'),
          _bullet(2, 'Chọn WiFi 2.4GHz nhà và nhập mật khẩu để gateway vào mạng.'),
          _bullet(3, 'Nhập IP máy chấm công, kiểm tra kết nối là xong.'),
        ]),
        const SizedBox(height: 14),
        _primaryButton('Bắt đầu', () => setState(() => _step = 1)),
      ],
    );
  }

  Widget _buildJoinAp() {
    return Column(
      children: [
        _card(children: [
          _title('Nối điện thoại vào sóng của gateway'),
          _bullet(1, 'Mở phần WiFi trong Cài đặt của điện thoại.'),
          _bullet(2, 'Chọn mạng có tên bắt đầu bằng SBOX-Gateway-'),
          _bullet(3, 'Nhập mật khẩu: sbox12345'),
          _bullet(4, 'Quay lại app rồi bấm nút bên dưới.'),
          Row(
            children: [
              const Expanded(
                child: GatewayNoteBox(
                  text: 'Mật khẩu sóng cấu hình: sbox12345',
                  icon: Icons.wifi_password,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: tr('Sao chép mật khẩu'),
                onPressed: () {
                  Clipboard.setData(const ClipboardData(text: 'sbox12345'));
                  appNotification.showSuccess(
                    title: tr('Đã sao chép'),
                    message: tr('Mật khẩu sbox12345 đã vào bộ nhớ tạm.'),
                  );
                },
                icon: const Icon(Icons.copy, size: 18),
                color: HrmPageChrome.primaryNavy,
              ),
            ],
          ),
          const SizedBox(height: 10),
          const GatewayNoteBox(
            text: 'Điện thoại có thể báo "mạng này không có Internet" - đúng là '
                'như vậy, hãy chọn giữ kết nối.',
            icon: Icons.warning_amber_rounded,
            color: Color(0xFFF59E0B),
          ),
        ]),
        const SizedBox(height: 14),
        _primaryButton('Tôi đã kết nối, kiểm tra', _probeDevice, icon: Icons.search),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => setState(() => _step = 0),
          child: Text(tr('Quay lại')),
        ),
      ],
    );
  }

  Widget _buildConfigForm() {
    return Column(
      children: [
        if (_probed != null)
          _card(children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 20),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    tr('Đã thấy gateway${_probed!.version.isNotEmpty ? ' (${_probed!.version})' : ''}'),
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: HrmPageChrome.textDark,
                    ),
                  ),
                ),
              ],
            ),
          ]),
        if (_probed != null) const SizedBox(height: 14),
        _card(children: [
          _title('Chọn WiFi cho gateway'),
          Row(
            children: [
              Expanded(
                child: _field(
                  controller: _ssidCtrl,
                  label: 'Tên WiFi (SSID)',
                  hint: 'Bấm nút quét rồi chọn',
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: IconButton.filledTonal(
                  onPressed: _busy ? null : _scanWifi,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_find, size: 20),
                  tooltip: tr('Quét WiFi'),
                ),
              ),
            ],
          ),
          if (_aps.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 280),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListView.separated(
                primary: false,
                padding: EdgeInsets.zero,
                itemCount: _aps.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                itemBuilder: (_, i) {
                  final ap = _aps[i];
                  final selected = ap.ssid == _ssidCtrl.text.trim();
                  return Material(
                    color: selected
                        ? HrmPageChrome.primaryNavy.withValues(alpha: 0.08)
                        : Colors.transparent,
                    child: InkWell(
                      onTap: () => setState(() => _ssidCtrl.text = ap.ssid),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 28,
                              child: WifiSignalBars(bars: ap.bars),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ap.ssid,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: selected
                                          ? FontWeight.w800
                                          : FontWeight.w600,
                                      color: HrmPageChrome.textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    tr('${ap.rssi} dBm · ${ap.secure ? 'có mật khẩu' : 'mở'}'),
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: HrmPageChrome.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              selected
                                  ? Icons.check_circle
                                  : (ap.secure
                                      ? Icons.lock_outline
                                      : Icons.lock_open_outlined),
                              size: 18,
                              color: selected
                                  ? HrmPageChrome.primaryNavy
                                  : const Color(0xFF94A3B8),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            const GatewayNoteBox(
              text: 'Danh sách do chính gateway quét — chỉ hiện WiFi 2.4GHz '
                  'mà nó bắt được. Chọn trong đây để không sai chữ hoa/thường.',
            ),
          ],
          const SizedBox(height: 12),
          _field(
            controller: _passCtrl,
            label: 'Mật khẩu WiFi',
            hint: _isReconfigure ? 'để trống nếu không đổi' : 'nhập mật khẩu',
            obscure: _obscurePass,
            suffix: IconButton(
              onPressed: () => setState(() => _obscurePass = !_obscurePass),
              icon: Icon(
                _obscurePass ? Icons.visibility_off : Icons.visibility,
                size: 19,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        _card(children: [
          _title('Máy chấm công và máy chủ'),
          _field(
            controller: _nameCtrl,
            label: 'Tên gợi nhớ cho gateway',
            hint: 'VD: Cửa trước - tầng 1',
          ),
          const SizedBox(height: 12),
          _field(
            controller: _deviceIpCtrl,
            label: 'IP máy chấm công trong LAN',
            hint: '192.168.1.35',
            keyboardType: TextInputType.text,
          ),
          const SizedBox(height: 8),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Text(
                tr('Nâng cao (Comm Key)'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: HrmPageChrome.textMuted,
                ),
              ),
              children: [
                _field(
                  controller: _commKeyCtrl,
                  label: 'Comm Key của máy',
                  hint: '0 nếu máy không đặt',
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 8),
                Text(
                  tr('Chỉ đổi khi máy chấm công có đặt Comm Key. '
                      'Sai số này sẽ không kết nối được máy.'),
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: HrmPageChrome.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GatewayNoteBox(
            text: 'Máy chủ ADMS cố định: $_fixedServerUrl (không đổi được).',
            icon: Icons.lock_outline,
          ),
        ]),
        const SizedBox(height: 14),
        _primaryButton('Lưu và kết nối', _saveAndWait, icon: Icons.save_outlined),
        if (!_isReconfigure) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy ? null : () => setState(() => _step = 1),
            child: Text(tr('Quay lại')),
          ),
        ],
      ],
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(label),
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: HrmPageChrome.textMuted,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint == null ? null : tr(hint),
            hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            suffixIcon: suffix,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: HrmPageChrome.primaryNavy, width: 1.6),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWaiting() {
    if (_result != null) {
      return Column(
        children: [
          _card(children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF16A34A).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Color(0xFF16A34A)),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    tr('Gateway đã lên mạng'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: HrmPageChrome.textDark,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            GatewayInfoTile(label: 'Địa chỉ trong mạng', value: _result!.ip),
            const SizedBox(height: 8),
            GatewayInfoTile(
              label: 'Số seri máy chấm công',
              value: _result!.serial.isEmpty ? tr('đang đọc...') : _result!.serial,
            ),
            const SizedBox(height: 8),
            GatewayInfoTile(
              label: 'Máy chủ',
              value: tr(_result!.serverOnline ? 'đã kết nối' : 'chưa kết nối'),
            ),
          ]),
          const SizedBox(height: 14),
          _primaryButton(
            'Xong',
            () => Navigator.of(context).pop(_result),
            icon: Icons.done_all,
          ),
        ],
      );
    }

    return Column(
      children: [
        _card(children: [
          Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: _busy
                    ? const CircularProgressIndicator(strokeWidth: 2.4)
                    : const Icon(Icons.info_outline, color: Color(0xFFF59E0B)),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(
                  tr(_busy ? 'Đang thiết lập' : 'Chưa hoàn tất'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: HrmPageChrome.textDark,
                  ),
                ),
              ),
            ],
          ),
          if (_waitMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _waitMessage!,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.55,
                color: HrmPageChrome.textDark,
              ),
            ),
          ],
          if (!_busy) ...[
            const SizedBox(height: 14),
            const GatewayNoteBox(
              text: 'Kiểm tra: điện thoại đã về WiFi nhà chưa, mật khẩu WiFi có '
                  'đúng không, và mạng đó có phát 2.4GHz không.',
              icon: Icons.help_outline,
              color: Color(0xFFF59E0B),
            ),
          ],
        ]),
        const SizedBox(height: 14),
        if (!_busy) ...[
          _primaryButton('Dò tìm lại', _retryFind, icon: Icons.refresh),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() => _step = 2),
            child: Text(tr('Sửa lại cấu hình')),
          ),
        ],
      ],
    );
  }
}
