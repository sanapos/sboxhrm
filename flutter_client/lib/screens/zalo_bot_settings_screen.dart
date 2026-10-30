import 'package:flutter/material.dart';

import '../l10n/app_tr.dart';
import '../services/zalo_bot_api.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/sbox/sbox_ui.dart';
import '../widgets/settings/settings_page.dart';

/// Thiết lập SBOX › Zalo bot: token bot của cửa hàng, nhóm thông báo gửi qua Zalo, ai đã liên kết.
class ZaloBotSettingsScreen extends StatefulWidget {
  const ZaloBotSettingsScreen({super.key, this.api});

  final ZaloBotApi? api;

  @override
  State<ZaloBotSettingsScreen> createState() => _ZaloBotSettingsScreenState();
}

class _ZaloBotSettingsScreenState extends State<ZaloBotSettingsScreen> {
  late final ZaloBotApi _api = widget.api ?? ZaloBotApi();
  final _token = TextEditingController();
  final _botLink = TextEditingController();

  Map<String, dynamic>? _s;
  List<Map<String, dynamic>> _links = [];
  bool _loading = true;
  bool _saving = false;
  bool _busy = false;
  String? _error;

  bool _enabled = false;
  bool _hideMoney = false;
  Set<String> _cats = {};
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _token.dispose();
    _botLink.dispose();
    super.dispose();
  }

  void _apply(Map<String, dynamic> s) {
    _s = s;
    _enabled = s['enabled'] == true;
    _hideMoney = s['hideMoney'] == true;
    _cats = {for (final c in (s['categories'] as List? ?? const [])) c.toString()};
    _botLink.text = (s['botLink'] ?? '').toString();
    _token.clear();
    _dirty = false;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _api.getSettings();
    final l = await _api.getLinks();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r['isSuccess'] == true && r['data'] is Map) {
        _apply(Map<String, dynamic>.from(r['data'] as Map));
      } else {
        _error = (r['message'] ?? 'Không tải được thiết lập').toString();
      }
      _links = [
        if (l['isSuccess'] == true && l['data'] is List)
          for (final e in l['data'] as List)
            if (e is Map) Map<String, dynamic>.from(e),
      ];
    });
  }

  void _mark(VoidCallback fn) => setState(() {
        fn();
        _dirty = true;
      });

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final r = await _api.saveSettings(
      enabled: _enabled,
      botToken: _token.text,
      botLink: _botLink.text.trim().isEmpty ? null : _botLink.text.trim(),
      categories: _cats.toList(),
      hideMoney: _hideMoney,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (r['isSuccess'] == true && r['data'] is Map) {
      setState(() => _apply(Map<String, dynamic>.from(r['data'] as Map)));
      NotificationOverlayManager().showSuccess(title: 'Đã lưu', message: 'Đã lưu thiết lập Zalo bot');
    } else {
      NotificationOverlayManager().showError(title: 'Lỗi', message: (r['message'] ?? 'Không lưu được').toString());
    }
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() call, String okMessage) async {
    if (_busy) return;
    setState(() => _busy = true);
    final r = await call();
    if (!mounted) return;
    setState(() => _busy = false);
    if (r['isSuccess'] == true) {
      if (r['data'] is Map) setState(() => _apply(Map<String, dynamic>.from(r['data'] as Map)));
      NotificationOverlayManager().showSuccess(title: 'Xong', message: okMessage);
    } else {
      NotificationOverlayManager().showError(title: 'Lỗi', message: (r['message'] ?? 'Không thực hiện được').toString());
    }
  }

  Future<void> _unlink(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Hủy liên kết Zalo?')),
        content: Text(tr('{name} sẽ không nhận thông báo qua Zalo nữa (vẫn nhận trong app).')
            .replaceAll('{name}', (row['name'] ?? '').toString())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Đóng'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Hủy liên kết'))),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() => _api.unlinkUser(row['userId'].toString()), 'Đã hủy liên kết');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final hasToken = s?['hasToken'] == true;
    final webhookOk = s?['webhookOk'] == true;
    final lastError = s?['lastError']?.toString();
    final all = [
      for (final c in (s?['allCategories'] as List? ?? const []))
        if (c is Map) (c['code'].toString(), c['label'].toString()),
    ];
    final linked = _links.where((r) => r['linked'] == true).toList();

    final page = SettingsPage(
      title: 'Zalo bot',
      subtitle: 'Gửi thông báo lương, phạt, duyệt đơn… cho nhân viên qua Zalo',
      icon: Icons.forum_outlined,
      loading: _loading,
      error: _error,
      onRetry: _load,
      saving: _saving,
      dirty: _dirty,
      onSave: _save,
      onDiscard: () => setState(() => _apply(_s!)),
      children: [
        SettingsSection(
          title: 'Kết nối bot',
          subtitle: 'Mỗi cửa hàng dùng bot Zalo riêng, miễn phí',
          icon: Icons.link_rounded,
          trailing: SboxStatusChip(
            label: hasToken ? (s?['botName']?.toString() ?? 'Đã kết nối') : 'Chưa kết nối',
            tone: hasToken ? SboxTone.success : SboxTone.neutral,
            dot: true,
          ),
          children: [
            const SettingsNote(
              '1. Vào bot.zapps.me (Zalo Bot Platform), đăng nhập Zalo và tạo bot.\n'
              '2. Sao chép token bot và link chia sẻ bot, dán vào hai ô dưới rồi bấm Lưu.\n'
              '3. Nhân viên vào Cài đặt › Liên kết Zalo, lấy mã 6 số và gửi mã cho bot.',
              icon: Icons.info_outline_rounded,
            ),
            SettingsTile(
              label: 'Token bot',
              help: hasToken ? 'Đã lưu (mã hóa). Để trống nếu giữ nguyên.' : 'Dạng 123456789:abc…',
              inline: false,
              control: SizedBox(
                width: 360,
                child: TextField(
                  controller: _token,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    hintText: tr(hasToken ? 'Dán token mới để thay' : 'Dán token bot'),
                  ),
                  onChanged: (_) => setState(() => _dirty = true),
                ),
              ),
            ),
            SettingsTile(
              label: 'Link mở bot',
              help: 'Hiện cho nhân viên khi liên kết (https://…)',
              inline: false,
              control: SizedBox(
                width: 360,
                child: TextField(
                  controller: _botLink,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(isDense: true, border: OutlineInputBorder(), hintText: 'https://'),
                  onChanged: (_) => setState(() => _dirty = true),
                ),
              ),
            ),
            if (hasToken)
              SettingsTile(
                label: 'Nhận tin từ Zalo (webhook)',
                help: webhookOk
                    ? 'Đang hoạt động — nhân viên gửi mã cho bot là liên kết được'
                    : (lastError ?? 'Chưa đăng ký được. Máy chủ phải có tên miền https công khai.'),
                inline: false,
                control: Row(mainAxisSize: MainAxisSize.min, children: [
                  SboxStatusChip(
                    label: webhookOk ? 'Hoạt động' : 'Lỗi',
                    tone: webhookOk ? SboxTone.success : SboxTone.danger,
                    dot: true,
                  ),
                  const SizedBox(width: 8),
                  SboxButton.secondary(
                    label: 'Đăng ký lại',
                    icon: Icons.refresh_rounded,
                    size: SboxButtonSize.sm,
                    loading: _busy,
                    onPressed: _busy ? null : () => _run(_api.registerWebhook, 'Đã đăng ký lại webhook'),
                  ),
                ]),
              ),
            if (hasToken && webhookOk && lastError != null && lastError.isNotEmpty)
              SettingsNote(lastError, icon: Icons.warning_amber_rounded, tone: SboxTone.warning),
          ],
        ),
        SettingsSection(
          title: 'Gửi thông báo qua Zalo',
          subtitle: 'Thông báo trong app vẫn gửi như cũ; Zalo là kênh thêm',
          icon: Icons.notifications_active_outlined,
          children: [
            SettingsTile(
              label: 'Bật gửi qua Zalo',
              help: hasToken ? 'Chỉ gửi cho người đã liên kết Zalo' : 'Nhập token bot trước',
              control: Switch(
                value: _enabled,
                onChanged: hasToken || _token.text.trim().isNotEmpty ? (v) => _mark(() => _enabled = v) : null,
              ),
            ),
            SettingsTile(
              label: 'Nhóm thông báo',
              help: 'Chọn loại thông báo được gửi qua Zalo',
              inline: false,
              control: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final (code, label) in all)
                  FilterChip(
                    label: Text(tr(label)),
                    selected: _cats.contains(code),
                    onSelected: (v) => _mark(() => v ? _cats.add(code) : _cats.remove(code)),
                  ),
              ]),
            ),
            SettingsTile(
              label: 'Ẩn số tiền',
              help: 'Tin lương / phạt hiện «***đ», nhân viên mở app để xem số tiền',
              control: Switch(value: _hideMoney, onChanged: (v) => _mark(() => _hideMoney = v)),
            ),
          ],
        ),
        SettingsSection(
          title: 'Nhân viên đã liên kết',
          subtitle: '{n}/{total} tài khoản'
              .replaceAll('{n}', '${linked.length}')
              .replaceAll('{total}', '${_links.length}'),
          icon: Icons.people_alt_outlined,
          trailing: hasToken
              ? SboxButton.secondary(
                  label: 'Gửi tin thử cho tôi',
                  icon: Icons.send_rounded,
                  size: SboxButtonSize.sm,
                  loading: _busy,
                  onPressed: _busy ? null : () => _run(_api.sendTest, 'Đã gửi tin thử, kiểm tra Zalo của bạn'),
                )
              : null,
          children: [
            if (linked.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  tr('Chưa ai liên kết. Nhân viên vào Cài đặt › Liên kết Zalo để lấy mã.'),
                  style: const TextStyle(color: SboxColors.slate500),
                ),
              ),
            for (final r in linked)
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Divider(height: 1, color: SboxColors.divider),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.verified_user_outlined, color: SboxColors.success),
                  title: Text((r['name'] ?? '').toString()),
                  subtitle: Text('${tr('Zalo')}: ${r['zaloName'] ?? '—'}'),
                  trailing: IconButton(
                    tooltip: tr('Hủy liên kết'),
                    icon: const Icon(Icons.link_off_rounded),
                    onPressed: _busy ? null : () => _unlink(r),
                  ),
                ),
              ]),
          ],
        ),
      ],
    );
    if (HrmPageChrome.isHubBody(context)) return page;
    return Scaffold(appBar: AppBar(title: Text(tr('Zalo bot'))), body: page);
  }
}
