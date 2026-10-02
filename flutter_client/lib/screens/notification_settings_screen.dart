import 'package:flutter/material.dart';

import '../l10n/app_tr.dart';
import '../services/api_service.dart';
import '../services/notification_preferences_cache.dart';
import '../utils/notification_group_settings.dart';
import '../widgets/notifications/push_settings_card.dart';
import '../widgets/sbox/sbox_ui.dart';
import '../widgets/settings/settings_page.dart';

/// Nhóm thông báo trên màn thiết lập (gom các mã loại thông báo của server).
class NotifGroup {
  const NotifGroup(this.title, this.desc, this.icon, this.codes);
  final String title;
  final String desc;
  final IconData icon;
  final List<String> codes;

  static const all = <NotifGroup>[
    NotifGroup('Chấm công & ca', 'Chấm công, chấm đi đường, máy chấm công, ca làm việc', Icons.fingerprint_rounded,
        ['attendance', 'travel_attendance', 'device', 'shift']),
    NotifGroup('Đơn từ & phê duyệt', 'Nghỉ phép, tăng ca, công tác, yêu cầu cần duyệt', Icons.approval_rounded,
        ['leave', 'overtime', 'approval', 'business_trip']),
    NotifGroup('Lương & tài chính', 'Phiếu lương, phiếu phạt, thu chi', Icons.payments_rounded, ['payroll', 'penalty', 'transaction']),
    NotifGroup('Công việc & nội bộ', 'Công việc, KPI, bản tin nội bộ, nhân sự, suất ăn', Icons.task_alt_rounded,
        ['task', 'kpi', 'internal_comm', 'hr', 'meal']),
    NotifGroup('Bán hàng', 'Đơn hàng, nhập hàng, tồn kho thấp, đơn QR', Icons.point_of_sale_rounded, ['pos']),
    NotifGroup('Hệ thống', 'Cảnh báo bảo mật (đổi tài khoản nhận tiền…), thông báo hệ thống', Icons.shield_outlined, ['system']),
  ];

  /// Nhóm của 1 mã; mã lạ cho vào «Hệ thống».
  static NotifGroup of(String code) => all.firstWhere((g) => g.codes.contains(code), orElse: () => all.last);
}

class _Pref {
  _Pref(this.code, this.name, this.desc, this.order, this.enabled);
  final String code;
  final String name;
  final String desc;
  final int order;
  bool enabled;
}

/// Thiết lập thông báo của chính mình (mỗi người tự bật / tắt).
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key, this.showPushCard = true});

  /// Thẻ cài đặt thông báo đẩy của máy này (ẩn trong test).
  final bool showPushCard;

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  final _api = ApiService();
  List<_Pref> _prefs = [];
  Map<String, bool> _saved = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  Map<String, bool> get _current => {for (final p in _prefs) p.code: p.enabled};
  bool get _dirty => _current.toString() != _saved.toString();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _api.getNotificationPreferences();
    if (!mounted) return;
    if (r['isSuccess'] == true && r['data'] is List) {
      final list = (r['data'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      setState(() {
        _prefs = [
          for (final e in list)
            _Pref('${e['categoryCode'] ?? ''}', '${e['categoryDisplayName'] ?? ''}', '${e['categoryDescription'] ?? ''}',
                (e['displayOrder'] as num?)?.toInt() ?? 0, e['isEnabled'] != false),
        ]..sort((a, b) => a.order.compareTo(b.order));
        _saved = _current;
        _loading = false;
      });
      NotificationPreferencesCache.instance.applyFromPreferenceList(list);
      await NotificationGroupSettings.syncFromPreferenceList(list);
    } else {
      setState(() {
        _loading = false;
        _error = r['message']?.toString() ?? 'Không tải được thiết lập thông báo';
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final prefs = [for (final p in _prefs) {'categoryCode': p.code, 'isEnabled': p.enabled}];
    final r = await _api.updateNotificationPreferences(prefs);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['isSuccess'] == true) {
      NotificationPreferencesCache.instance.applyFromPreferenceList(prefs);
      await NotificationGroupSettings.syncFromPreferenceList(prefs);
      setState(() => _saved = _current);
      _toast('Đã lưu thiết lập thông báo');
    } else {
      _toast(r['message']?.toString() ?? 'Không lưu được. Thông báo vẫn nhận như cũ.', error: true);
    }
  }

  void _toast(String m, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(m)),
        backgroundColor: error ? SboxColors.danger : null,
        behavior: SnackBarBehavior.floating,
      ));

  void _setAll(bool v) => setState(() {
        for (final p in _prefs) {
          p.enabled = v;
        }
      });

  @override
  Widget build(BuildContext context) {
    final on = _prefs.where((p) => p.enabled).length;
    return SettingsPage(
      title: 'Thông báo',
      subtitle: 'Chọn loại thông báo bạn muốn nhận — áp dụng cho tài khoản của bạn trên mọi thiết bị',
      icon: Icons.notifications_active_outlined,
      loading: _loading,
      error: _error,
      onRetry: _load,
      dirty: _dirty,
      saving: _saving,
      onSave: _save,
      onDiscard: () => setState(() {
        for (final p in _prefs) {
          p.enabled = _saved[p.code] ?? p.enabled;
        }
      }),
      headerActions: [
        PopupMenuButton<bool>(
          tooltip: tr('Bật / tắt tất cả'),
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: _setAll,
          itemBuilder: (_) => [
            PopupMenuItem(value: true, child: Text(tr('Bật tất cả'))),
            PopupMenuItem(value: false, child: Text(tr('Tắt tất cả'))),
          ],
        ),
      ],
      children: [
        if (widget.showPushCard) const PushSettingsCard(),
        if (_prefs.isNotEmpty)
          SettingsNote('Đang nhận $on/${_prefs.length} loại thông báo. Thông báo đã tắt vẫn xem được trong mục Thông báo của app, chỉ không đẩy lên điện thoại.',
              icon: Icons.info_outline_rounded),
        ...NotifGroup.all.map(_group).whereType<Widget>(),
      ],
    );
  }

  Widget? _group(NotifGroup g) {
    final items = _prefs.where((p) => NotifGroup.of(p.code) == g).toList();
    if (items.isEmpty) return null;
    final anyOn = items.any((p) => p.enabled);
    return SettingsSection(
      title: g.title,
      subtitle: g.desc,
      icon: g.icon,
      trailing: Switch(
        value: anyOn,
        onChanged: (v) => setState(() {
          for (final p in items) {
            p.enabled = v;
          }
        }),
      ),
      children: [
        for (var i = 0; i < items.length; i++)
          SettingsTile(
            label: items[i].name,
            help: items[i].desc.isEmpty ? null : items[i].desc,
            control: Switch(value: items[i].enabled, onChanged: (v) => setState(() => items[i].enabled = v)),
          ),
      ],
    );
  }
}
