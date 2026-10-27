import 'package:flutter/material.dart';

import '../l10n/app_tr.dart';
import '../services/ai_morning_brief_api.dart';
import '../widgets/sbox/sbox_ui.dart';
import '../widgets/settings/settings_page.dart';

/// «Bản tin sáng tự động» trong Thiết lập SBOX › Trợ lý AI: mỗi sáng gửi chủ / quản lý doanh thu hôm qua, hàng sắp hết,
/// đơn chờ duyệt, ai đi trễ / vắng, công nợ khách kèm 1–2 gợi ý của AI. Lưu riêng (nút «Lưu bản tin»), không theo nút
/// Lưu của trang.
class AiMorningBriefSection extends StatefulWidget {
  const AiMorningBriefSection({super.key, this.api});

  final AiMorningBriefApi? api;

  @override
  State<AiMorningBriefSection> createState() => _AiMorningBriefSectionState();
}

class _AiMorningBriefSectionState extends State<AiMorningBriefSection> {
  late final AiMorningBriefApi _api = widget.api ?? AiMorningBriefApi();

  static const _recipientOptions = <(String, String)>[
    ('owner', 'Chủ cửa hàng / Admin'),
    ('manager', 'Quản lý / Giám đốc / Trưởng phòng'),
    ('accountant', 'Kế toán'),
    ('sales_viewers', 'Mọi người xem được báo cáo bán hàng'),
  ];

  static const _sectionOptions = <(String, String)>[
    ('sales', 'Doanh thu'),
    ('stock', 'Hàng sắp hết'),
    ('approvals', 'Đơn chờ duyệt'),
    ('attendance', 'Đi trễ / vắng'),
    ('debt', 'Công nợ khách'),
  ];

  bool _loading = true;
  String? _error;
  bool _saving = false;
  bool _canEdit = false;
  bool _moduleAllowed = true;
  bool _enabled = false;
  TimeOfDay _time = const TimeOfDay(hour: 7, minute: 0);
  Set<String> _recipients = {'owner', 'manager'};
  Set<String> _sections = {'sales', 'stock', 'approvals', 'attendance', 'debt'};
  String _savedKey = '';

  bool _previewing = false;
  String? _previewText;
  String? _previewNote;

  bool _historyLoaded = false;
  bool _historyLoading = false;
  List<Map<String, dynamic>> _history = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String get _timeText => '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';

  String get _key => [
        _enabled,
        _timeText,
        (_recipients.toList()..sort()).join(','),
        (_sections.toList()..sort()).join(','),
      ].join('|');

  bool get _dirty => !_loading && _key != _savedKey;

  Future<void> _load() async {
    final r = await _api.getSettings();
    if (!mounted) return;
    if (r['isSuccess'] != true) {
      setState(() {
        _loading = false;
        _error = r['message']?.toString() ?? 'Không tải được thiết lập bản tin';
      });
      return;
    }
    final d = r['data'] is Map ? Map<String, dynamic>.from(r['data'] as Map) : const <String, dynamic>{};
    final parts = (d['sendTime']?.toString() ?? '07:00').split(':');
    setState(() {
      _enabled = d['enabled'] == true;
      _time = TimeOfDay(
        hour: int.tryParse(parts.first) ?? 7,
        minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      );
      _recipients = ((d['recipients'] as List?) ?? const []).map((e) => e.toString()).toSet();
      _sections = ((d['sections'] as List?) ?? const []).map((e) => e.toString()).toSet();
      _canEdit = d['canEdit'] == true;
      _moduleAllowed = d['moduleAllowed'] != false;
      _savedKey = _key;
      _loading = false;
      _error = null;
    });
  }

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr(text)),
      backgroundColor: error ? SboxColors.danger : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _save() async {
    if (_enabled && _recipients.isEmpty) {
      _snack('Chọn ít nhất một nhóm người nhận', error: true);
      return;
    }
    if (_enabled && _sections.isEmpty) {
      _snack('Chọn ít nhất một mục trong bản tin', error: true);
      return;
    }
    setState(() => _saving = true);
    final r = await _api.saveSettings(
      enabled: _enabled,
      sendTime: _timeText,
      recipients: _recipients.toList(),
      sections: _sections.toList(),
    );
    if (!mounted) return;
    final ok = r['isSuccess'] == true;
    setState(() {
      _saving = false;
      if (ok) _savedKey = _key;
    });
    _snack(
      ok
          ? (_enabled ? 'Đã lưu — bản tin sẽ gửi lúc $_timeText mỗi sáng' : 'Đã lưu — bản tin sáng đang tắt')
          : (r['message']?.toString() ?? 'Không lưu được'),
      error: !ok,
    );
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: tr('Giờ gửi bản tin (giờ Việt Nam)'),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child ?? const SizedBox.shrink(),
      ),
    );
    if (t != null && mounted) setState(() => _time = t);
  }

  Future<void> _preview() async {
    setState(() {
      _previewing = true;
      _previewText = null;
      _previewNote = null;
    });
    final r = await _api.preview();
    if (!mounted) return;
    final ok = r['isSuccess'] == true;
    final d = r['data'] is Map ? Map<String, dynamic>.from(r['data'] as Map) : const <String, dynamic>{};
    setState(() {
      _previewing = false;
      if (!ok) {
        _previewNote = r['message']?.toString() ?? 'Không xem thử được';
        return;
      }
      _previewText = d['text']?.toString() ?? '';
      final aiError = d['aiError']?.toString();
      _previewNote = d['aiUsed'] == true
          ? 'Có gợi ý của AI. Cả ngày dùng chung một lần gọi AI — bản gửi theo giờ hẹn dùng lại gợi ý này.'
          : 'Bản tin chỉ có số liệu${aiError == null || aiError.isEmpty ? '' : ' — AI: $aiError'}';
    });
    if (_historyLoaded) _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _historyLoading = true);
    final r = await _api.history();
    if (!mounted) return;
    final list = r['data'] is List
        ? (r['data'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : <Map<String, dynamic>>[];
    setState(() {
      _history = list;
      _historyLoaded = true;
      _historyLoading = false;
    });
  }

  /// Giờ máy chủ lưu UTC (không kèm Z) → giờ Việt Nam.
  static DateTime? _vn(dynamic raw) {
    final s = raw?.toString();
    if (s == null || s.isEmpty) return null;
    final p = DateTime.tryParse(s.endsWith('Z') || s.contains('+') ? s : '${s}Z');
    return p?.toUtc().add(const Duration(hours: 7));
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  String _historyTitle(Map<String, dynamic> h) {
    final d = DateTime.tryParse(h['briefDate']?.toString() ?? '');
    return d == null ? tr('Bản tin') : tr('Bản tin ${_two(d.day)}/${_two(d.month)}');
  }

  String _historySubtitle(Map<String, dynamic> h) {
    final sent = _vn(h['sentAt']);
    final ai = h['aiUsed'] == true ? tr('có gợi ý AI') : tr('chỉ số liệu');
    if (h['status'] == 'sent' && sent != null) {
      return tr('Đã gửi ${_two(sent.hour)}:${_two(sent.minute)} · ${h['recipientCount'] ?? 0} người nhận · $ai');
    }
    return tr('Chưa gửi (đã xem thử) · $ai');
  }

  void _showHistory(Map<String, dynamic> h) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_historyTitle(h)),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(child: SelectableText(h['text']?.toString() ?? '')),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng')))],
      ),
    );
  }

  Widget _chips(List<(String, String)> options, Set<String> selected) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final o in options)
            FilterChip(
              label: Text(tr(o.$2)),
              selected: selected.contains(o.$1),
              onSelected: _canEdit
                  ? (v) => setState(() => v ? selected.add(o.$1) : selected.remove(o.$1))
                  : null,
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: 'Bản tin sáng tự động',
      subtitle: 'Mỗi sáng gửi chủ / quản lý doanh thu hôm qua, hàng sắp hết, đơn chờ duyệt, ai đi trễ / vắng, '
          'công nợ khách kèm 1–2 gợi ý của AI',
      icon: Icons.wb_sunny_outlined,
      trailing: _canEdit
          ? SboxButton.secondary(
              label: 'Lưu bản tin',
              icon: Icons.save_outlined,
              loading: _saving,
              onPressed: _saving || !_dirty ? null : _save,
            )
          : null,
      children: [
        if (_loading)
          const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator())
        else if (_error != null)
          SettingsNote(_error!, icon: Icons.error_outline_rounded, tone: SboxTone.danger)
        else ...[
          if (!_moduleAllowed)
            const SettingsNote('Gói dịch vụ của cửa hàng chưa có «Trợ lý AI» — bản tin sẽ không được gửi.',
                icon: Icons.lock_outline_rounded, tone: SboxTone.warning),
          SettingsTile(
            divider: false,
            label: 'Gửi bản tin mỗi sáng',
            help: 'Thông báo đẩy (tóm tắt) + thông báo trong app (đầy đủ). Bấm vào thông báo để mở Trợ lý AI',
            control: Switch(value: _enabled, onChanged: _canEdit ? (v) => setState(() => _enabled = v) : null),
          ),
          SettingsTile(
            label: 'Giờ gửi (giờ Việt Nam)',
            help: 'Số liệu là của ngày hôm trước. Máy chủ khởi động lại muộn vẫn gửi bù trong 6 tiếng sau giờ hẹn',
            control: OutlinedButton.icon(
              onPressed: _canEdit ? _pickTime : null,
              icon: const Icon(Icons.schedule_rounded, size: 18),
              label: Text(_timeText),
            ),
          ),
          SettingsTile(
            label: 'Người nhận',
            help: 'Mỗi người chỉ thấy mục mình có quyền xem; đơn chờ duyệt và chấm công lọc theo phạm vi quản lý',
            inline: false,
            control: _chips(_recipientOptions, _recipients),
          ),
          SettingsTile(
            label: 'Các mục trong bản tin',
            inline: false,
            control: _chips(_sectionOptions, _sections),
          ),
          const SizedBox(height: 4),
          const SettingsNote(
            'AI chỉ được gọi 1 lần mỗi ngày cho cả cửa hàng. AI lỗi hoặc hết lượt thì vẫn gửi bản tin số liệu.',
            icon: Icons.info_outline_rounded,
            tone: SboxTone.neutral,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SboxButton(
                label: 'Xem thử bản tin hôm nay',
                icon: Icons.visibility_outlined,
                loading: _previewing,
                onPressed: _canEdit && _moduleAllowed && !_previewing ? _preview : null,
              ),
            ],
          ),
          if (_previewNote != null) ...[
            const SizedBox(height: 8),
            SettingsNote(_previewNote!,
                icon: Icons.auto_awesome_outlined, tone: _previewText == null ? SboxTone.danger : SboxTone.brand),
          ],
          if (_previewText != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SboxColors.slate50,
                border: Border.all(color: SboxColors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: SelectableText(_previewText!, style: const TextStyle(fontSize: 13, height: 1.45)),
            ),
          ],
          if (_canEdit) ...[
            const SizedBox(height: 4),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(tr('Lịch sử 14 ngày gần nhất'),
                  style: const TextStyle(fontWeight: FontWeight.w700, color: SboxColors.slate800)),
              onExpansionChanged: (open) {
                if (open && !_historyLoaded && !_historyLoading) _loadHistory();
              },
              children: [
                if (_historyLoading)
                  const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator())
                else if (_history.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(tr('Chưa có bản tin nào'), style: const TextStyle(color: SboxColors.slate500)),
                  )
                else
                  for (final h in _history)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        h['status'] == 'sent' ? Icons.mark_email_read_outlined : Icons.drafts_outlined,
                        color: h['status'] == 'sent' ? SboxColors.success : SboxColors.slate400,
                      ),
                      title: Text(_historyTitle(h)),
                      subtitle: Text(_historySubtitle(h)),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _showHistory(h),
                    ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}
