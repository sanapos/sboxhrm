import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/pos_sell_industry.dart';
import '../../services/api_service.dart';
import '../../services/zk_gateway_ble.dart';
import '../../theme/sbox_tokens.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Cài bộ đèn bi-a (ESP32-C3 + relay) qua Bluetooth: tìm thiết bị → WiFi + khóa → gán lần lượt
/// từng kênh relay cho bàn (có nút bật thử đèn) → xong.
class PosBidaLightBleSetupScreen extends StatefulWidget {
  const PosBidaLightBleSetupScreen({super.key, required this.deviceKey});

  /// Khóa thiết bị của cửa hàng (Thiết lập → Đèn bàn bi-a).
  final String deviceKey;

  @override
  State<PosBidaLightBleSetupScreen> createState() => _PosBidaLightBleSetupScreenState();
}

class _ChannelRow {
  _ChannelRow({required this.gpio, this.resourceCode});
  int gpio;
  String? resourceCode;
}

class _PosBidaLightBleSetupScreenState extends State<PosBidaLightBleSetupScreen> {
  static const _stepTitles = ['Tìm thiết bị', 'WiFi', 'Gán đèn cho bàn', 'Xong'];
  static const _defaultPins = [0, 1, 3, 4, 5, 6, 7, 10, 20, 21];

  final _api = ApiService();
  final _ble = createZkGatewayBle(profile: SboxBleProfile.bidaLight);
  final _ssidCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  int _step = 0;
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  List<ZkBleDevice> _devices = [];
  StreamSubscription<List<ZkBleDevice>>? _scanSub;
  bool _scanning = false;

  Map<String, dynamic> _info = {};
  String? _adminPass;
  List<int> _pins = _defaultPins;
  bool _activeLow = true;
  final List<_ChannelRow> _channels = [];
  List<PosServiceResourceDto> _resources = [];
  int? _testingIndex;

  @override
  void initState() {
    super.initState();
    _loadResources();
    _scan();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    unawaited(_ble.dispose());
    _ssidCtrl.dispose();
    _passCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _say(String? msg, {bool error = false}) {
    if (!mounted) return;
    setState(() {
      _message = msg;
      _messageIsError = error;
    });
  }

  Future<void> _loadResources() async {
    final res = await _api.getPosServiceResources(heal: false);
    if (!mounted || res['isSuccess'] != true || res['data'] is! List) return;
    final list = <PosServiceResourceDto>[
      for (final e in res['data'] as List)
        if (e is Map) PosServiceResourceDto.fromJson(Map<String, dynamic>.from(e)),
    ]..sort((a, b) {
        final s = a.sortOrder.compareTo(b.sortOrder);
        return s != 0 ? s : a.code.compareTo(b.code);
      });
    setState(() => _resources = list);
  }

  // ── Bước 1: tìm thiết bị ─────────────────────────────────────────────

  Future<void> _scan() async {
    await _scanSub?.cancel();
    setState(() {
      _scanning = true;
      _devices = [];
      _message = null;
    });
    _scanSub = _ble.scan(timeout: const Duration(seconds: 12)).listen(
      (list) {
        if (mounted) setState(() => _devices = list);
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() => _scanning = false);
        _say(e.toString(), error: true);
      },
      onDone: () {
        if (mounted) setState(() => _scanning = false);
      },
    );
  }

  Future<void> _connect(ZkBleDevice d) async {
    setState(() => _busy = true);
    _say('Đang kết nối ${d.displayName}…');
    try {
      await _scanSub?.cancel();
      await _ble.connect(d.id);
      final info = await _ble.readInfo();
      if (info['product'] != 'sbox-bida-light') {
        throw const ZkBleException('Thiết bị này không phải bộ đèn bi-a SBOX');
      }
      _applyInfo(info);
      if (info['locked'] == true) {
        final ok = await _askAdminPass();
        if (!ok) {
          await _ble.disconnect();
          throw const ZkBleException('Cần mật khẩu quản lý của bộ đèn để cài đặt');
        }
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = 1;
      });
      _say(null);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _say(e.toString(), error: true);
    }
  }

  void _applyInfo(Map<String, dynamic> info) {
    _info = info;
    final pins = (info['pins'] as List?)?.whereType<num>().map((e) => e.toInt()).toList();
    if (pins != null && pins.isNotEmpty) _pins = pins;
    _activeLow = info['activeLow'] != false;
    _ssidCtrl.text = (info['wifiSsid'] ?? '').toString();
    _nameCtrl.text = (info['name'] ?? '').toString();

    _channels.clear();
    final rows = (info['ch'] as List?) ?? const [];
    for (final r in rows) {
      if (r is! List || r.length < 2) continue;
      final gpio = (r[0] as num?)?.toInt() ?? -1;
      if (gpio < 0) continue;
      final code = (r[1] ?? '').toString();
      _channels.add(_ChannelRow(gpio: gpio, resourceCode: code.isEmpty ? null : code));
    }
    if (_channels.isEmpty) {
      for (final p in _pins.take(8)) {
        _channels.add(_ChannelRow(gpio: p));
      }
    }
  }

  Future<bool> _askAdminPass() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Mật khẩu quản lý')),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(hintText: tr('Mật khẩu đã đặt trên trang của bộ đèn')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Tiếp tục'))),
        ],
      ),
    );
    if (ok == true && ctrl.text.isNotEmpty) {
      _adminPass = ctrl.text;
      return true;
    }
    return false;
  }

  /// Ghi một lệnh rồi chờ trạng thái kết thúc (thiết bị báo qua notify; dự phòng đọc lại mỗi 2 giây).
  Future<ZkBleProvStatus> _command(
    Map<String, dynamic> payload, {
    required Set<String> doneStates,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final completer = Completer<ZkBleProvStatus>();
    void check(ZkBleProvStatus st) {
      if (!completer.isCompleted && (doneStates.contains(st.state) || st.state == 'failed' || st.state == 'denied')) {
        completer.complete(st);
      }
    }

    final sub = _ble.statusNotifications().listen(check);
    final poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        check(await _ble.readStatus());
      } catch (_) {}
    });
    try {
      await _ble.writeConfig({...payload, if (_adminPass != null) 'pass': _adminPass});
      return await completer.future.timeout(
        timeout,
        onTimeout: () => const ZkBleProvStatus(state: 'failed', message: 'Thiết bị không trả lời — thử lại'),
      );
    } finally {
      poll.cancel();
      await sub.cancel();
    }
  }

  // ── Bước 2: WiFi ─────────────────────────────────────────────────────

  Future<void> _sendWifi() async {
    final ssid = _ssidCtrl.text.trim();
    if (ssid.isEmpty) {
      _say('Nhập tên WiFi của quán (WiFi 2.4 GHz)', error: true);
      return;
    }
    setState(() => _busy = true);
    _say('Đang gửi WiFi và khóa thiết bị… bộ đèn đang vào mạng, chờ tối đa 1 phút');
    try {
      final st = await _command(
        {
          'op': 'wifi',
          'name': _nameCtrl.text.trim(),
          'wifiSsid': ssid,
          'wifiPass': _passCtrl.text,
          'deviceKey': widget.deviceKey,
        },
        doneStates: {'online'},
        timeout: const Duration(seconds: 90),
      );
      if (!mounted) return;
      setState(() => _busy = false);
      if (st.state == 'online') {
        _say('Đã vào WiFi${st.ip.isNotEmpty ? ' (IP ${st.ip})' : ''} và kết nối máy chủ thành công');
        setState(() => _step = 2);
      } else {
        _say(_deviceMessage(st), error: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _say(e.toString(), error: true);
    }
  }

  // ── Bước 3: gán đèn cho bàn ──────────────────────────────────────────

  Future<void> _testChannel(int index) async {
    setState(() => _testingIndex = index);
    try {
      final st = await _command(
        {'op': 'test', 'gpio': _channels[index].gpio},
        doneStates: {'testing'},
        timeout: const Duration(seconds: 8),
      );
      if (st.state != 'testing') _say(_deviceMessage(st), error: true);
      await Future<void>.delayed(const Duration(seconds: 3));
    } catch (e) {
      _say(e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _testingIndex = null);
    }
  }

  /// Gán bàn theo thứ tự sơ đồ cho các kênh còn trống: kênh 1 ← bàn 1, kênh 2 ← bàn 2…
  void _autoAssign() {
    final used = _channels.map((c) => c.resourceCode).whereType<String>().toSet();
    final free = _resources.where((r) => !used.contains(r.code)).toList();
    setState(() {
      for (final c in _channels) {
        if (c.resourceCode == null && free.isNotEmpty) c.resourceCode = free.removeAt(0).code;
      }
    });
  }

  void _setChannelCount(int n) {
    setState(() {
      while (_channels.length > n) {
        _channels.removeLast();
      }
      while (_channels.length < n) {
        final used = _channels.map((c) => c.gpio).toSet();
        final pin = _pins.firstWhere((p) => !used.contains(p), orElse: () => -1);
        if (pin < 0) break;
        _channels.add(_ChannelRow(gpio: pin));
      }
    });
  }

  Future<void> _saveChannels() async {
    final pins = _channels.map((c) => c.gpio).toList();
    if (pins.toSet().length != pins.length) {
      _say('Hai kênh đang dùng chung một chân GPIO', error: true);
      return;
    }
    final codes = _channels.map((c) => c.resourceCode).whereType<String>().toList();
    if (codes.toSet().length != codes.length) {
      _say('Một bàn đang gán cho hai kênh', error: true);
      return;
    }
    setState(() => _busy = true);
    _say('Đang lưu…');
    try {
      final st = await _command(
        {
          'op': 'channels',
          'activeLow': _activeLow,
          'ch': [
            for (final c in _channels) [c.gpio, c.resourceCode ?? ''],
          ],
        },
        doneStates: {'saved'},
      );
      if (!mounted) return;
      setState(() => _busy = false);
      if (st.state == 'saved') {
        _say(null);
        setState(() => _step = 3);
      } else {
        _say(_deviceMessage(st), error: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _say(e.toString(), error: true);
    }
  }

  String _deviceMessage(ZkBleProvStatus st) {
    if (st.state == 'denied') return 'Sai mật khẩu quản lý của bộ đèn';
    // Firmware báo không dấu — thêm lời khuyên cho lỗi hay gặp.
    final m = st.message;
    if (m.contains('tu choi khoa')) {
      return 'Máy chủ từ chối khóa thiết bị — kiểm tra «Bật điều khiển đèn» trong Thiết lập → Đèn bàn bi-a';
    }
    if (m.contains('WiFi')) return 'Không vào được WiFi — kiểm tra tên / mật khẩu, WiFi phải là 2.4 GHz';
    return m.isEmpty ? 'Thiết bị báo lỗi' : m;
  }

  String _resourceLabel(String code) {
    for (final r in _resources) {
      if (r.code == code) return r.name == r.code ? r.code : '${r.name} (${r.code})';
    }
    return '$code (không có trên sơ đồ)';
  }

  // ── Giao diện ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Cài bộ đèn qua Bluetooth'))),
      body: SafeArea(
        child: Column(children: [
          _stepBar(),
          if (_message != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _messageIsError ? const Color(0xFFFDECEC) : const Color(0xFFEAF3FD),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                tr(_message!),
                style: TextStyle(color: _messageIsError ? SboxColors.danger : SboxColors.slate800),
              ),
            ),
          Expanded(
            child: switch (_step) {
              0 => _buildScan(),
              1 => _buildWifi(),
              2 => _buildChannels(),
              _ => _buildDone(),
            },
          ),
        ]),
      ),
    );
  }

  Widget _stepBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          for (var i = 0; i < _stepTitles.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= _step ? SboxColors.brand600 : SboxColors.slate300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(_stepTitles[i]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: i == _step ? FontWeight.w700 : FontWeight.w500,
                    color: i == _step ? SboxColors.slate900 : SboxColors.slate500,
                  ),
                ),
              ]),
            ),
          ],
        ]),
      );

  Widget _buildScan() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(
        tr('Cấp điện cho bộ đèn, để điện thoại gần đó và bật Bluetooth. '
            'Bộ đèn đã cài rồi thì nhấn nhanh nút BOOT trên mạch để mở Bluetooth thêm 10 phút.'),
        style: const TextStyle(color: SboxColors.slate600),
      ),
      const SizedBox(height: 12),
      for (final d in _devices)
        Card(
          child: ListTile(
            leading: const Icon(Icons.lightbulb_outline_rounded),
            title: Text(d.displayName),
            subtitle: Text('${tr('Sóng')} ${d.rssi} dBm'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _busy ? null : () => _connect(d),
          ),
        ),
      if (_devices.isEmpty && !_scanning)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(tr('Không thấy bộ đèn nào (tên SBOX-Den-xxxx)'), textAlign: TextAlign.center),
        ),
      const SizedBox(height: 12),
      _scanning
          ? const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
          : OutlinedButton.icon(
              onPressed: _busy ? null : _scan,
              icon: const Icon(Icons.bluetooth_searching_rounded),
              label: Text(tr('Dò lại')),
            ),
    ]);
  }

  Widget _buildWifi() {
    final alreadyOnline = _info['wifi'] == true && _info['provisioned'] == true;
    return ListView(padding: const EdgeInsets.all(16), children: [
      TextField(
        controller: _nameCtrl,
        decoration: InputDecoration(labelText: tr('Tên bộ đèn (ví dụ: Tủ điện tầng 1)')),
        maxLength: 63,
      ),
      TextField(
        controller: _ssidCtrl,
        decoration: InputDecoration(labelText: tr('Tên WiFi của quán (2.4 GHz)')),
        maxLength: 63,
      ),
      TextField(
        controller: _passCtrl,
        obscureText: true,
        decoration: InputDecoration(labelText: tr('Mật khẩu WiFi')),
        maxLength: 63,
      ),
      const SizedBox(height: 8),
      Text(
        tr('Khóa thiết bị của cửa hàng được gửi kèm tự động.'),
        style: const TextStyle(fontSize: 12.5, color: SboxColors.slate500),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _busy ? null : _sendWifi,
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.wifi_rounded),
        label: Text(tr('Gửi và kết nối')),
      ),
      if (alreadyOnline) ...[
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _busy ? null : () => setState(() => _step = 2),
          child: Text(tr('Giữ WiFi hiện tại, sang gán đèn')),
        ),
      ],
    ]);
  }

  Widget _buildChannels() {
    final codes = {for (final r in _resources) r.code};
    final extraCodes = _channels
        .map((c) => c.resourceCode)
        .whereType<String>()
        .where((c) => !codes.contains(c))
        .toSet();
    return Column(children: [
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 16), children: [
          Text(
            tr('Lần lượt bấm «Thử đèn» ở từng kênh: đèn bàn nào sáng 3 giây thì chọn bàn đó.'),
            style: const TextStyle(color: SboxColors.slate600),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Text(tr('Số kênh relay')),
            const SizedBox(width: 12),
            DropdownButton<int>(
              value: _channels.length.clamp(1, _pins.length),
              items: [
                for (var n = 1; n <= _pins.length; n++) DropdownMenuItem(value: n, child: Text('$n')),
              ],
              onChanged: _busy ? null : (n) => _setChannelCount(n ?? 8),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _busy || _resources.isEmpty ? null : _autoAssign,
              icon: const Icon(Icons.format_list_numbered_rounded, size: 18),
              label: Text(tr('Gán theo thứ tự')),
            ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _activeLow,
            onChanged: _busy ? null : (v) => setState(() => _activeLow = v),
            title: Text(tr('Module relay kích mức thấp')),
            subtitle: Text(tr('Đa số module relay 5V. Thử đèn mà relay làm ngược thì đổi ô này.')),
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < _channels.length; i++) _channelCard(i, extraCodes),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _saveChannels,
            icon: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_rounded),
            label: Text(tr('Lưu vào bộ đèn')),
          ),
        ),
      ),
    ]);
  }

  Widget _channelCard(int i, Set<String> extraCodes) {
    final c = _channels[i];
    final testing = _testingIndex == i;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('${tr('Kênh')} ${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(width: 12),
            DropdownButton<int>(
              value: c.gpio,
              items: [
                for (final p in _pins) DropdownMenuItem(value: p, child: Text('GPIO $p')),
              ],
              onChanged: _busy ? null : (v) => setState(() => c.gpio = v ?? c.gpio),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _busy || _testingIndex != null ? null : () => _testChannel(i),
              icon: testing
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.lightbulb_rounded, size: 18),
              label: Text(tr('Thử đèn')),
            ),
          ]),
          const SizedBox(height: 6),
          DropdownButtonFormField<String?>(
            // initialValue chỉ đọc lúc tạo — đổi key để «Gán theo thứ tự» vẽ lại đúng bàn.
            key: ValueKey('ch$i-${c.resourceCode}'),
            initialValue: c.resourceCode,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Bàn'), isDense: true),
            items: [
              DropdownMenuItem<String?>(value: null, child: Text(tr('— Không gắn bàn —'))),
              for (final r in _resources)
                DropdownMenuItem<String?>(value: r.code, child: Text(_resourceLabel(r.code))),
              for (final code in extraCodes)
                DropdownMenuItem<String?>(value: code, child: Text(_resourceLabel(code))),
            ],
            onChanged: _busy ? null : (v) => setState(() => c.resourceCode = v),
          ),
        ]),
      ),
    );
  }

  Widget _buildDone() {
    final assigned = _channels.where((c) => c.resourceCode != null).length;
    return ListView(padding: const EdgeInsets.all(24), children: [
      const Icon(Icons.check_circle_rounded, size: 64, color: SboxColors.success),
      const SizedBox(height: 12),
      Text(
        tr('Đã cài xong bộ đèn'),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      Text(
        '${tr('Đã gán')} $assigned ${tr('kênh cho bàn. Mở bàn trên POS thì đèn sáng sau vài giây, thanh toán thì tắt.')}',
        textAlign: TextAlign.center,
        style: const TextStyle(color: SboxColors.slate600),
      ),
      const SizedBox(height: 24),
      FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(tr('Xong'))),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: () => setState(() => _step = 2), child: Text(tr('Sửa lại gán đèn'))),
    ]);
  }
}
