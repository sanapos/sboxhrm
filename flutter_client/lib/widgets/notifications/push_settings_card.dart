import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../notification_overlay.dart';
import '../sbox/sbox_ui.dart';
import '../settings/settings_page.dart';

/// Thẻ "Đẩy lên điện thoại": bật/tắt đẩy, giờ yên lặng (không chuông), cho phép thông báo khẩn, gửi thử.
class PushSettingsCard extends StatefulWidget {
  const PushSettingsCard({super.key});

  @override
  State<PushSettingsCard> createState() => _PushSettingsCardState();
}

class _PushSettingsCardState extends State<PushSettingsCard> {
  final _api = ApiService();
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;

  bool _pushEnabled = true;
  bool _quietEnabled = false;
  TimeOfDay _quietStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _quietEnd = const TimeOfDay(hour: 7, minute: 0);
  bool _allowUrgent = true;
  int _devices = 0;
  bool _inQuietNow = false;
  bool _storeAllowsPush = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  TimeOfDay _parse(String? hm, TimeOfDay fallback) {
    final p = (hm ?? '').split(':');
    if (p.length < 2) return fallback;
    final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
    if (h == null || m == null) return fallback;
    return TimeOfDay(hour: h, minute: m);
  }

  String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _apply(Map d) {
    _pushEnabled = d['pushEnabled'] != false;
    _quietEnabled = d['quietEnabled'] == true;
    _quietStart = _parse(d['quietStart']?.toString(), _quietStart);
    _quietEnd = _parse(d['quietEnd']?.toString(), _quietEnd);
    _allowUrgent = d['allowUrgentInQuiet'] != false;
    _devices = (d['activeDevices'] as num?)?.toInt() ?? 0;
    _inQuietNow = d['inQuietNow'] == true;
    _storeAllowsPush = d['storeAllowsPush'] != false;
  }

  Future<void> _load() async {
    final r = await _api.getPushSettings();
    if (!mounted) return;
    setState(() {
      if (r['isSuccess'] == true && r['data'] is Map) _apply(r['data'] as Map);
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final r = await _api.updatePushSettings({
      'pushEnabled': _pushEnabled,
      'quietEnabled': _quietEnabled,
      'quietStart': _fmt(_quietStart),
      'quietEnd': _fmt(_quietEnd),
      'allowUrgentInQuiet': _allowUrgent,
    });
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (r['isSuccess'] == true && r['data'] is Map) _apply(r['data'] as Map);
    });
    if (r['isSuccess'] != true) {
      NotificationOverlayManager().showError(title: 'Lưu thất bại', message: r['message']?.toString() ?? '');
      _load();
    }
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    final r = await _api.sendTestPush();
    if (!mounted) return;
    setState(() => _testing = false);
    final d = r['data'];
    if (r['isSuccess'] == true && d is Map) {
      final devices = (d['devices'] as num?)?.toInt() ?? 0;
      final hint = d['hint']?.toString() ?? '';
      if (devices == 0) {
        NotificationOverlayManager().showWarning(title: 'Chưa có điện thoại', message: hint);
      } else {
        NotificationOverlayManager().showSuccess(title: 'Đã gửi thông báo thử', message: hint);
      }
    } else {
      NotificationOverlayManager().showError(title: 'Không gửi được', message: r['message']?.toString() ?? '');
    }
  }

  Future<void> _pick(bool start) async {
    final t = await showTimePicker(
      context: context,
      initialTime: start ? _quietStart : _quietEnd,
      helpText: start ? tr('Bắt đầu yên lặng') : tr('Kết thúc yên lặng'),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t == null) return;
    setState(() => start ? _quietStart = t : _quietEnd = t);
    _save();
  }

  void _preset(TimeOfDay s, TimeOfDay e) {
    setState(() {
      _quietEnabled = true;
      _quietStart = s;
      _quietEnd = e;
    });
    _save();
  }

  void _toggle(VoidCallback change) {
    if (_saving) return;
    setState(change);
    _save();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SboxCard(
        child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    return SettingsSection(
      title: 'Đẩy lên điện thoại',
      subtitle: _devices == 0
          ? 'Chưa có điện thoại nào nhận — mở app SBOX trên điện thoại và cho phép thông báo'
          : '$_devices thiết bị đang nhận · tự lưu khi thay đổi',
      icon: Icons.phone_iphone_rounded,
      trailing: Switch(value: _pushEnabled, onChanged: _saving ? null : (v) => _toggle(() => _pushEnabled = v)),
      children: [
        if (!_storeAllowsPush)
          _banner(Icons.info_outline_rounded, SboxColors.warningSoft, SboxColors.warningText,
              'Gói dịch vụ của cửa hàng chưa bật thông báo đẩy — thông báo vẫn hiện trong app.'),
        if (_pushEnabled) ...[
          SettingsTile(
            label: 'Giờ yên lặng',
            help: _quietEnabled
                ? 'Từ ${_fmt(_quietStart)} đến ${_fmt(_quietEnd)} không chuông, không rung${_inQuietNow ? ' · đang yên lặng' : ''}'
                : 'Tắt chuông thông báo vào giờ nghỉ',
            control: Switch(value: _quietEnabled, onChanged: _saving ? null : (v) => _toggle(() => _quietEnabled = v)),
          ),
          if (_quietEnabled) ...[
            Row(children: [
              Expanded(child: _timeBox('Bắt đầu', _quietStart, () => _pick(true))),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward_rounded, size: 18, color: SboxColors.slate400),
              ),
              Expanded(child: _timeBox('Kết thúc', _quietEnd, () => _pick(false))),
            ]),
            const SizedBox(height: 8),
            // Mẫu nhanh: 1 hàng, cuộn ngang nếu máy hẹp — không rớt dòng lẻ.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _presetChip('Ban đêm 22:00–07:00', const TimeOfDay(hour: 22, minute: 0), const TimeOfDay(hour: 7, minute: 0)),
                const SizedBox(width: 6),
                _presetChip('Nghỉ trưa 12:00–13:30', const TimeOfDay(hour: 12, minute: 0), const TimeOfDay(hour: 13, minute: 30)),
                const SizedBox(width: 6),
                _presetChip('Đêm muộn 23:00–06:00', const TimeOfDay(hour: 23, minute: 0), const TimeOfDay(hour: 6, minute: 0)),
              ]),
            ),
            SettingsTile(
              label: 'Thông báo khẩn vẫn đổ chuông',
              help: 'Cần duyệt, cảnh báo, lỗi thiết bị',
              control: Switch(value: _allowUrgent, onChanged: _saving ? null : (v) => _toggle(() => _allowUrgent = v)),
            ),
          ],
        ],
        const Divider(height: 1, color: SboxColors.divider),
        Row(children: [
          if (_saving) ...[
            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6)),
            const SizedBox(width: 8),
            Text(tr('Đang lưu…'), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
          ],
          const Spacer(),
          TextButton.icon(
            onPressed: _testing ? null : _test,
            icon: _testing
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6))
                : const Icon(Icons.send_to_mobile_rounded, size: 18),
            label: Text(tr('Gửi thử cho tôi')),
          ),
        ]),
      ],
    );
  }

  Widget _banner(IconData icon, Color bg, Color fg, String text) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(child: Text(tr(text), style: TextStyle(fontSize: 12, color: fg))),
        ]),
      );

  Widget _timeBox(String label, TimeOfDay t, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: SboxColors.violetSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(label), style: const TextStyle(fontSize: 11, color: SboxColors.violetText)),
            Text(_fmt(t),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: SboxColors.violetText)),
          ]),
        ),
      );

  Widget _presetChip(String label, TimeOfDay s, TimeOfDay e) {
    final active = _quietStart == s && _quietEnd == e;
    return ChoiceChip(
      label: Text(tr(label), style: const TextStyle(fontSize: 12)),
      selected: active,
      visualDensity: VisualDensity.compact,
      onSelected: (_) => _preset(s, e),
    );
  }
}
