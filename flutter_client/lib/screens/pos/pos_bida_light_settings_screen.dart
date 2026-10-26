import '../../widgets/hrm_page_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../services/zk_gateway_ble.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/settings/settings_page.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import 'pos_bida_light_ble_setup_screen.dart';

/// Đèn bàn bi-a: bộ ESP32-C3 + relay hỏi máy chủ — mở bàn thì đèn sáng, thanh toán thì tắt.
class PosBidaLightSettingsScreen extends StatefulWidget {
  const PosBidaLightSettingsScreen({super.key});

  @override
  State<PosBidaLightSettingsScreen> createState() => _PosBidaLightSettingsScreenState();
}

class _PosBidaLightSettingsScreenState extends State<PosBidaLightSettingsScreen> {
  final _api = ApiService();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _enabled = false;
  bool _pausedOn = true;
  String? _deviceKey;

  /// Bluetooth chỉ có trên app điện thoại (Android / iOS), không có trên web.
  final bool _bleSupported = createZkGatewayBle(profile: SboxBleProfile.bidaLight).isSupported;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _apply(Map<String, dynamic> res) {
    final d = res['data'];
    if (res['isSuccess'] == true && d is Map) {
      _enabled = d['enabled'] == true;
      _pausedOn = d['pausedOn'] != false;
      _deviceKey = d['deviceKey'] as String?;
      _error = null;
    } else {
      _error = (res['message'] as String?) ?? 'Không tải được';
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getPosBidaLight();
    if (!mounted) return;
    setState(() {
      _apply(res);
      _loading = false;
    });
  }

  Future<void> _save({required bool enabled, bool rotate = false, bool? pausedOn}) async {
    if (_saving) return;
    setState(() => _saving = true);
    final res = await _api.savePosBidaLight(enabled: enabled, rotate: rotate, pausedOn: pausedOn);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (res['isSuccess'] == true) _apply(res);
    });
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: (res['message'] as String?) ?? 'Không lưu được',
      );
    }
  }

  Future<void> _rotate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Đổi khóa thiết bị?')),
        content: Text(tr('Mọi bộ relay đang dùng khóa cũ sẽ ngừng nhận trạng thái bàn cho tới khi dán khóa mới vào trang cấu hình của nó.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Đổi khóa'))),
        ],
      ),
    );
    if (ok == true) await _save(enabled: true, rotate: true);
  }

  Future<void> _copyKey() async {
    final k = _deviceKey;
    if (k == null) return;
    await Clipboard.setData(ClipboardData(text: k));
    NotificationOverlayManager().showSuccess(title: 'Đã sao chép', message: 'Dán vào ô «Khóa thiết bị» trên trang của bộ relay');
  }

  @override
  Widget build(BuildContext context) {
    final page = SettingsPage(
      title: 'Đèn bàn bi-a',
      subtitle: 'Bộ ESP32-C3 + relay tự bật đèn khi mở bàn, tắt khi thanh toán',
      icon: Icons.lightbulb_outline_rounded,
      loading: _loading,
      error: _error,
      onRetry: _load,
      saving: _saving,
      children: [
        SettingsSection(
          title: 'Bộ điều khiển đèn',
          icon: Icons.power_settings_new_rounded,
          children: [
            SettingsTile(
              label: 'Bật điều khiển đèn',
              help: 'Tắt = mọi bộ relay bị từ chối và giữ nguyên trạng thái đèn hiện tại',
              control: Switch(
                value: _enabled,
                onChanged: _saving ? null : (v) => _save(enabled: v),
              ),
            ),
            if (_enabled)
              SettingsTile(
                label: 'Tạm dừng giờ vẫn sáng đèn',
                help: 'Bàn đang tạm dừng tính giờ: bật = đèn vẫn sáng, tắt = tắt đèn tới khi chạy lại',
                control: Switch(
                  value: _pausedOn,
                  onChanged: _saving ? null : (v) => _save(enabled: true, pausedOn: v),
                ),
              ),
          ],
        ),
        if (_enabled && _deviceKey != null)
          SettingsSection(
            title: 'Khóa thiết bị',
            subtitle: 'Dán vào trang cấu hình của bộ relay (WiFi SBOX-Den-xxxx, http://192.168.4.1)',
            icon: Icons.key_rounded,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SelectableText(
                  _deviceKey!,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13.5),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  if (_bleSupported)
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PosBidaLightBleSetupScreen(deviceKey: _deviceKey!),
                        ),
                      ),
                      icon: const Icon(Icons.bluetooth_rounded, size: 18),
                      label: Text(tr('Cài bộ đèn qua Bluetooth')),
                    ),
                  FilledButton.tonalIcon(
                    onPressed: _copyKey,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: Text(tr('Sao chép khóa')),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _rotate,
                    icon: const Icon(Icons.autorenew_rounded, size: 18),
                    label: Text(tr('Đổi khóa')),
                  ),
                ]),
              ),
              const SettingsNote(
                'Trên điện thoại: bấm «Cài bộ đèn qua Bluetooth» — app tự gửi WiFi + khóa, rồi bạn bấm «Thử đèn» '
                'từng kênh và chọn bàn tương ứng. Không có Bluetooth: dán khóa vào trang của bộ relay '
                '(WiFi SBOX-Den-xxxx, http://192.168.4.1). Một cửa hàng dùng được nhiều bộ relay với cùng một khóa.',
              ),
            ],
          ),
      ],
    );
    if (HrmPageChrome.isHubBody(context)) return page;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Đèn bàn bi-a'))),
      body: page,
    );
  }
}
