import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/notifications/notification_category_meta.dart';

/// Quản lý soạn & gửi thông báo cho nhân viên: mẫu có sẵn / mẫu cửa hàng, biến {ten}…,
/// chọn người nhận (tất cả / phòng ban / từng người), xem trước trên điện thoại.
class NotificationComposerScreen extends StatefulWidget {
  const NotificationComposerScreen({super.key});

  @override
  State<NotificationComposerScreen> createState() => _NotificationComposerScreenState();
}

class _Emp {
  _Emp(Map m)
      : userId = m['userId']?.toString() ?? '',
        name = m['name']?.toString() ?? '',
        code = m['code']?.toString(),
        department = m['department']?.toString(),
        position = m['position']?.toString(),
        hasApp = m['hasApp'] == true;
  final String userId, name;
  final String? code, department, position;
  final bool hasApp;
}

class _NotificationComposerScreenState extends State<NotificationComposerScreen> {
  final _api = ApiService();
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _search = TextEditingController();
  final _bodyFocus = FocusNode();
  final _titleFocus = FocusNode();
  FocusNode? _lastFocus;

  bool _loading = true;
  bool _sending = false;
  List<Map<String, dynamic>> _templates = [];
  List<_Emp> _employees = [];
  List<Map<String, dynamic>> _departments = [];
  bool _storeAllowsPush = true;
  String _storeName = '';

  String? _templateId; // mẫu cửa hàng đang dùng (để đếm lượt dùng)
  String _category = 'internal_comm';
  int _level = 0;
  String _audience = 'all'; // all | departments | users
  final Set<String> _depts = {};
  final Set<String> _users = {};

  static const _vars = [
    ('{ten}', 'Tên NV'),
    ('{hoten}', 'Họ tên'),
    ('{cuahang}', 'Cửa hàng'),
    ('{ngay}', 'Hôm nay'),
    ('{thang}', 'Tháng'),
    ('{gio}', 'Giờ'),
  ];

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
    _body.addListener(() => setState(() {}));
    _titleFocus.addListener(() => _titleFocus.hasFocus ? _lastFocus = _titleFocus : null);
    _bodyFocus.addListener(() => _bodyFocus.hasFocus ? _lastFocus = _bodyFocus : null);
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _search.dispose();
    _bodyFocus.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([_api.getStoreNotificationTemplates(), _api.getNotificationAudience()]);
    if (!mounted) return;
    setState(() {
      final t = results[0], a = results[1];
      if (t['isSuccess'] == true && t['data'] is List) {
        _templates = [for (final x in t['data'] as List) Map<String, dynamic>.from(x as Map)];
      }
      if (a['isSuccess'] == true && a['data'] is Map) {
        final d = a['data'] as Map;
        _employees = [for (final e in (d['employees'] as List? ?? const [])) _Emp(e as Map)];
        _departments = [for (final x in (d['departments'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
        _storeAllowsPush = d['storeAllowsPush'] != false;
        _storeName = d['storeName']?.toString() ?? '';
      } else if (a['isSuccess'] != true) {
        NotificationOverlayManager()
            .showError(title: 'Không tải được danh sách nhân viên', message: a['message']?.toString() ?? '');
      }
      _loading = false;
    });
  }

  // ── Người nhận ──
  List<_Emp> get _targets => switch (_audience) {
        'departments' => _employees.where((e) => _depts.contains(e.department ?? '')).toList(),
        'users' => _employees.where((e) => _users.contains(e.userId)).toList(),
        _ => _employees,
      };

  // ── Xem trước (khớp cách server thay biến) ──
  String _render(String text, String name) {
    final now = DateTime.now();
    final first = name.trim().isEmpty ? 'bạn' : name.trim().split(' ').last;
    return text.replaceAllMapped(RegExp(r'\{(ten|hoten|cuahang|ngay|thang|gio)\}', caseSensitive: false), (m) {
      switch (m.group(1)!.toLowerCase()) {
        case 'ten':
          return first;
        case 'hoten':
          return name.trim().isEmpty ? 'bạn' : name.trim();
        case 'cuahang':
          return _storeName.isEmpty ? 'Cửa hàng' : _storeName;
        case 'ngay':
          return DateFormat('dd/MM/yyyy').format(now);
        case 'thang':
          return DateFormat('MM/yyyy').format(now);
        case 'gio':
          return DateFormat('HH:mm').format(now);
      }
      return m.group(0)!;
    });
  }

  bool get _hasBlanks => RegExp(r'\[[^\]\{\}]{1,40}\]').hasMatch(_title.text + _body.text);

  void _useTemplate(Map<String, dynamic> t) {
    setState(() {
      _title.text = t['title']?.toString() ?? '';
      _body.text = t['body']?.toString() ?? '';
      _category = t['categoryCode']?.toString() ?? 'internal_comm';
      final ty = (t['type'] as num?)?.toInt() ?? 0;
      _level = NotificationLevelMeta.levels.any((l) => l.value == ty) ? ty : 0;
      _templateId = t['builtIn'] == true ? null : t['id']?.toString();
    });
    // Chọn chỗ [..] đầu tiên để sửa ngay
    final m = RegExp(r'\[[^\]]*\]').firstMatch(_body.text);
    if (m != null) {
      _bodyFocus.requestFocus();
      _body.selection = TextSelection(baseOffset: m.start, extentOffset: m.end);
    }
  }

  void _insertVar(String v) {
    final ctl = _lastFocus == _titleFocus ? _title : _body;
    final sel = ctl.selection;
    final text = ctl.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    ctl.value = TextEditingValue(
      text: text.replaceRange(start, end, v),
      selection: TextSelection.collapsed(offset: start + v.length),
    );
    (_lastFocus ?? _bodyFocus).requestFocus();
  }

  Future<void> _saveAsTemplate({Map<String, dynamic>? existing}) async {
    final nameCtl = TextEditingController(text: existing?['name']?.toString() ?? _title.text);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(existing == null ? 'Lưu thành mẫu' : 'Cập nhật mẫu')),
        content: TextField(
          controller: nameCtl,
          autofocus: true,
          decoration: InputDecoration(labelText: tr('Tên mẫu'), hintText: tr('VD: Nhắc họp đầu tuần')),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, nameCtl.text), child: Text(tr('Lưu'))),
        ],
      ),
    );
    if (name == null) return;
    final r = await _api.saveStoreNotificationTemplate({
      'name': name.trim(),
      'title': _title.text.trim(),
      'body': _body.text.trim(),
      'categoryCode': _category,
      'type': _level,
    }, id: existing?['id']?.toString());
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Đã lưu mẫu', message: name.trim());
      _templateId = (r['data'] is Map) ? (r['data'] as Map)['id']?.toString() : null;
      _load();
    } else {
      NotificationOverlayManager().showError(title: 'Không lưu được', message: r['message']?.toString() ?? '');
    }
  }

  Future<void> _deleteTemplate(Map<String, dynamic> t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xoá mẫu «${t['name']}»?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SboxColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Xoá')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _api.deleteStoreNotificationTemplate(t['id'].toString());
    if (!mounted) return;
    if (r['isSuccess'] == true) {
      if (_templateId == t['id']?.toString()) _templateId = null;
      _load();
    }
  }

  Map<String, dynamic> _payload({required bool dryRun}) => {
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'categoryCode': _category,
        'type': _level,
        'audience': _audience,
        'departments': _depts.toList(),
        'userIds': _users.toList(),
        if (_templateId != null) 'templateId': _templateId,
        'dryRun': dryRun,
      };

  Future<void> _send() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Thiếu nội dung', message: tr('Nhập tiêu đề và nội dung.'));
      return;
    }
    if (_hasBlanks) {
      NotificationOverlayManager().showWarning(
          title: 'Còn chỗ trống', message: tr('Thay các chỗ [ ... ] trong mẫu bằng nội dung thật trước khi gửi.'));
      return;
    }
    final targets = _targets;
    if (targets.isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Chưa chọn người nhận', message: '');
      return;
    }
    final withApp = targets.where((e) => e.hasApp).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.campaign_rounded, color: SboxColors.brand500, size: 34),
        title: Text(tr('Gửi cho ${targets.length} nhân viên?')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _statLine(Icons.phone_iphone_rounded, SboxColors.success, '$withApp người nhận trên điện thoại'),
          if (targets.length - withApp > 0)
            _statLine(Icons.phonelink_erase_rounded, SboxColors.slate500,
                '${targets.length - withApp} người chưa cài app — sẽ thấy khi mở web / app'),
          if (!_storeAllowsPush)
            _statLine(Icons.info_outline_rounded, SboxColors.warningText,
                'Gói dịch vụ chưa bật đẩy thông báo — chỉ hiện trong app'),
          const SizedBox(height: 8),
          Text(tr('Không thể thu hồi sau khi gửi.'), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Xem lại'))),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send_rounded, size: 18),
            label: Text(tr('Gửi ngay')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _sending = true);
    final r = await _api.sendStoreNotification(_payload(dryRun: false));
    if (!mounted) return;
    setState(() => _sending = false);
    if (r['isSuccess'] == true) {
      final d = r['data'] is Map ? r['data'] as Map : const {};
      NotificationOverlayManager().showSuccess(
        title: 'Đã gửi thông báo',
        message: tr('${d['recipients'] ?? targets.length} người nhận · ${d['withApp'] ?? withApp} trên điện thoại'),
      );
      setState(() {
        _title.clear();
        _body.clear();
        _templateId = null;
      });
      _load();
    } else {
      NotificationOverlayManager().showError(title: 'Không gửi được', message: r['message']?.toString() ?? '');
    }
  }

  Widget _statLine(IconData icon, Color color, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(tr(text), style: const TextStyle(fontSize: 13.5))),
        ]),
      );

  // ═══════════════════════ UI ═══════════════════════

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    return Scaffold(
      backgroundColor: SboxColors.slate50,
      appBar: AppBar(
        title: Text(tr('Gửi thông báo cho nhân viên')),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    flex: 3,
                    child: ListView(padding: const EdgeInsets.all(20), children: [
                      _templatesSection(),
                      const SizedBox(height: 14),
                      _contentSection(),
                      const SizedBox(height: 14),
                      _audienceSection(),
                    ]),
                  ),
                  SizedBox(
                    width: 380,
                    child: ListView(padding: const EdgeInsets.fromLTRB(0, 20, 20, 20), children: [
                      _previewSection(),
                      const SizedBox(height: 14),
                      _sendButton(),
                    ]),
                  ),
                ])
              : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 100), children: [
                  _templatesSection(),
                  const SizedBox(height: 12),
                  _contentSection(),
                  const SizedBox(height: 12),
                  _audienceSection(),
                  const SizedBox(height: 12),
                  _previewSection(),
                ]),
      bottomNavigationBar: !_loading && !wide
          ? SafeArea(
              child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 8), child: _sendButton()),
            )
          : null,
    );
  }

  Widget _card({required String title, IconData? icon, Widget? trailing, required Widget child}) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SboxColors.slate200),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 18, color: SboxColors.brand500), const SizedBox(width: 8)],
            Expanded(
              child: Text(tr(title),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: SboxColors.slate900)),
            ),
            if (trailing != null) trailing,
          ]),
          const SizedBox(height: 10),
          child,
        ]),
      );

  Widget _templatesSection() {
    final mine = _templates.where((t) => t['builtIn'] != true).toList();
    final builtIn = _templates.where((t) => t['builtIn'] == true).toList();
    Widget tile(Map<String, dynamic> t) {
      final meta = NotificationCategoryMeta.of(t['categoryCode']?.toString());
      final isMine = t['builtIn'] != true;
      final selected = isMine && _templateId == t['id']?.toString();
      return InkWell(
        onTap: () => _useTemplate(t),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 200,
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          decoration: BoxDecoration(
            color: selected ? meta.color.withValues(alpha: 0.08) : SboxColors.slate50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? meta.color : SboxColors.slate200),
          ),
          child: Row(children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: meta.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(meta.icon, size: 17, color: meta.color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(t['name']?.toString() ?? ''),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                Text(
                  tr(isMine
                      ? ((t['usageCount'] as num? ?? 0) > 0 ? 'Đã dùng ${t['usageCount']} lần' : 'Mẫu của cửa hàng')
                      : 'Mẫu có sẵn'),
                  style: const TextStyle(fontSize: 11, color: SboxColors.slate500),
                ),
              ]),
            ),
            if (isMine)
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                iconSize: 18,
                tooltip: tr('Tuỳ chọn'),
                onSelected: (v) {
                  if (v == 'update') {
                    _saveAsTemplate(existing: t);
                  } else if (v == 'delete') {
                    _deleteTemplate(t);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'update', child: Text(tr('Cập nhật bằng nội dung đang soạn'))),
                  PopupMenuItem(value: 'delete', child: Text(tr('Xoá mẫu'))),
                ],
              ),
          ]),
        ),
      );
    }

    return _card(
      title: 'Chọn mẫu',
      icon: Icons.auto_awesome_rounded,
      trailing: TextButton.icon(
        onPressed: _title.text.trim().isEmpty || _body.text.trim().isEmpty ? null : () => _saveAsTemplate(),
        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
        label: Text(tr('Lưu thành mẫu')),
      ),
      child: Wrap(spacing: 8, runSpacing: 8, children: [for (final t in [...mine, ...builtIn]) tile(t)]),
    );
  }

  Widget _contentSection() {
    return _card(
      title: 'Nội dung',
      icon: Icons.edit_note_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _title,
          focusNode: _titleFocus,
          maxLength: 200,
          decoration: InputDecoration(
            labelText: tr('Tiêu đề'),
            border: const OutlineInputBorder(),
            counterText: '',
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _body,
          focusNode: _bodyFocus,
          minLines: 4,
          maxLines: 8,
          maxLength: 2000,
          decoration: InputDecoration(
            labelText: tr('Nội dung'),
            alignLabelWithHint: true,
            border: const OutlineInputBorder(),
            helperText: tr('Bấm biến bên dưới để chèn — mỗi người nhận thấy tên của mình'),
          ),
        ),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final v in _vars)
            ActionChip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.data_object_rounded, size: 14),
              label: Text('${v.$1} ${tr(v.$2)}', style: const TextStyle(fontSize: 12)),
              onPressed: () => _insertVar(v.$1),
            ),
        ]),
        if (_hasBlanks)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: SboxColors.warningSoft, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              const Icon(Icons.edit_rounded, size: 16, color: SboxColors.warningText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr('Còn chỗ [ ... ] cần điền nội dung thật'),
                    style: const TextStyle(fontSize: 12.5, color: SboxColors.warningText)),
              ),
            ]),
          ),
        const SizedBox(height: 14),
        Text(tr('Loại thông báo'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final c in NotificationCategoryMeta.composable)
            ChoiceChip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(c.icon, size: 15, color: _category == c.code ? c.color : SboxColors.slate500),
              label: Text(tr(c.label), style: const TextStyle(fontSize: 12.5)),
              selected: _category == c.code,
              selectedColor: c.color.withValues(alpha: 0.14),
              onSelected: (_) => setState(() => _category = c.code),
            ),
        ]),
        const SizedBox(height: 12),
        Text(tr('Mức độ'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final l in NotificationLevelMeta.levels)
            ChoiceChip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(l.icon, size: 15, color: _level == l.value ? l.color : SboxColors.slate500),
              label: Text(tr(l.label), style: const TextStyle(fontSize: 12.5)),
              selected: _level == l.value,
              selectedColor: l.color.withValues(alpha: 0.14),
              onSelected: (_) => setState(() => _level = l.value),
            ),
        ]),
        if (_level == 2)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(tr('Thông báo "Quan trọng" vẫn đổ chuông trong giờ yên lặng của nhân viên.'),
                style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
          ),
      ]),
    );
  }

  Widget _audienceSection() {
    final targets = _targets;
    final q = _search.text.trim().toLowerCase();
    final filtered = _employees
        .where((e) =>
            q.isEmpty ||
            e.name.toLowerCase().contains(q) ||
            (e.code ?? '').toLowerCase().contains(q) ||
            (e.department ?? '').toLowerCase().contains(q))
        .toList();
    return _card(
      title: 'Người nhận',
      icon: Icons.groups_rounded,
      trailing: Text(tr('${targets.length} người'),
          style: const TextStyle(fontWeight: FontWeight.w700, color: SboxColors.brand600)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'all', icon: const Icon(Icons.public_rounded, size: 16), label: Text(tr('Tất cả'))),
            ButtonSegment(
                value: 'departments', icon: const Icon(Icons.account_tree_rounded, size: 16), label: Text(tr('Phòng ban'))),
            ButtonSegment(value: 'users', icon: const Icon(Icons.person_search_rounded, size: 16), label: Text(tr('Chọn người'))),
          ],
          selected: {_audience},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _audience = s.first),
        ),
        const SizedBox(height: 10),
        if (_employees.isEmpty)
          Text(tr('Chưa có nhân viên nào có tài khoản đăng nhập để nhận thông báo.'),
              style: const TextStyle(color: SboxColors.slate500, fontSize: 13)),
        if (_audience == 'all' && _employees.isNotEmpty)
          Text(
            tr('Gửi cho toàn bộ ${_employees.length} nhân viên đang làm có tài khoản '
                '(${_employees.where((e) => e.hasApp).length} người có app trên điện thoại).'),
            style: const TextStyle(fontSize: 13, color: SboxColors.slate600),
          ),
        if (_audience == 'departments')
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final d in _departments)
              FilterChip(
                visualDensity: VisualDensity.compact,
                label: Text('${tr(d['name']?.toString() ?? '')} · ${d['count']}', style: const TextStyle(fontSize: 12.5)),
                selected: _depts.contains(d['key']?.toString() ?? ''),
                onSelected: (v) => setState(() {
                  final k = d['key']?.toString() ?? '';
                  v ? _depts.add(k) : _depts.remove(k);
                }),
              ),
          ]),
        if (_audience == 'users') ...[
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              hintText: tr('Tìm tên, mã NV, phòng ban…'),
              border: const OutlineInputBorder(),
            ),
          ),
          Row(children: [
            TextButton(
              onPressed: () => setState(() => _users.addAll(filtered.map((e) => e.userId))),
              child: Text(tr('Chọn ${filtered.length} người đang lọc')),
            ),
            if (_users.isNotEmpty)
              TextButton(onPressed: () => setState(_users.clear), child: Text(tr('Bỏ chọn (${_users.length})'))),
          ]),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final e = filtered[i];
                return CheckboxListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _users.contains(e.userId),
                  onChanged: (v) => setState(() => v == true ? _users.add(e.userId) : _users.remove(e.userId)),
                  title: Text(e.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    [e.code, e.department, e.position].where((x) => (x ?? '').isNotEmpty).join(' · '),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  secondary: Tooltip(
                    message: tr(e.hasApp ? 'Có app trên điện thoại' : 'Chưa cài app — chỉ thấy khi mở web / app'),
                    child: Icon(e.hasApp ? Icons.phone_iphone_rounded : Icons.phonelink_erase_rounded,
                        size: 18, color: e.hasApp ? SboxColors.success : SboxColors.slate300),
                  ),
                );
              },
            ),
          ),
        ],
      ]),
    );
  }

  Widget _previewSection() {
    final targets = _targets;
    final sample = targets.isNotEmpty ? targets.first.name : 'Nguyễn Văn An';
    final meta = NotificationCategoryMeta.of(_category);
    final level = NotificationLevelMeta.of(_level);
    final title = _render(_title.text.trim().isEmpty ? 'Tiêu đề thông báo' : _title.text.trim(), sample);
    final body = _render(_body.text.trim().isEmpty ? 'Nội dung thông báo sẽ hiện ở đây…' : _body.text.trim(), sample);
    final withApp = targets.where((e) => e.hasApp).length;
    return _card(
      title: 'Xem trước',
      icon: Icons.visibility_rounded,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Khung "màn hình khoá" điện thoại
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1E293B), Color(0xFF334155)],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Text(DateFormat('HH:mm').format(DateTime.now()),
                  style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w300)),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(color: SboxColors.brand500, borderRadius: BorderRadius.circular(5)),
                    child: const Icon(Icons.notifications_rounded, size: 12, color: Colors.white),
                  ),
                  const SizedBox(width: 6),
                  Text('SBOX · ${tr(meta.label)}',
                      style: const TextStyle(fontSize: 11.5, color: SboxColors.slate600)),
                  const Spacer(),
                  Text(tr('bây giờ'), style: const TextStyle(fontSize: 11, color: SboxColors.slate500)),
                ]),
                const SizedBox(height: 6),
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: SboxColors.slate900)),
                const SizedBox(height: 2),
                Text(body,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: SboxColors.slate700, height: 1.35)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 8),
        Text(tr('Hiển thị như người nhận «$sample» thấy'),
            style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
        const SizedBox(height: 12),
        Row(children: [
          _pill(Icons.groups_rounded, '${targets.length} người nhận', SboxColors.brand600),
          const SizedBox(width: 6),
          _pill(Icons.phone_iphone_rounded, '$withApp có app', SboxColors.success),
          const SizedBox(width: 6),
          _pill(level.icon, level.label, level.color),
        ]),
        if (!_storeAllowsPush)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(tr('Gói dịch vụ chưa bật đẩy thông báo lên điện thoại — nhân viên sẽ thấy trong app.'),
                style: const TextStyle(fontSize: 12, color: SboxColors.warningText)),
          ),
      ]),
    );
  }

  Widget _pill(IconData icon, String text, Color color) => Flexible(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(tr(text),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
            ),
          ]),
        ),
      );

  Widget _sendButton() {
    final n = _targets.length;
    return SizedBox(
      height: 48,
      child: FilledButton.icon(
        onPressed: _sending || n == 0 ? null : _send,
        icon: _sending
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.send_rounded),
        label: Text(tr(_sending ? 'Đang gửi…' : 'Gửi cho $n người'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        style: FilledButton.styleFrom(
          backgroundColor: SboxColors.brand500,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
