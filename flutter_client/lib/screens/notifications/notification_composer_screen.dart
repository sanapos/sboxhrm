import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import 'notification_sent_screen.dart';
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
        branchId = m['branchId']?.toString(),
        hasApp = m['hasApp'] == true;
  final String userId, name;
  final String? code, department, position, branchId;
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
  final Set<String> _branches = {};
  List<Map<String, dynamic>> _branchList = [];
  final _link = TextEditingController();
  DateTime? _scheduleAt;

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
    _link.dispose();
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
        _branchList = [for (final x in (d['branches'] as List? ?? const [])) Map<String, dynamic>.from(x as Map)];
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
        'branches' => _employees.where((e) => _branches.contains(e.branchId ?? _hqBranchId)).toList(),
        _ => _employees,
      };

  String get _hqBranchId =>
      _branchList.where((b) => b['isHeadquarter'] == true).map((b) => b['id'].toString()).firstOrNull ?? '';

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
        'branches': _branches.toList(),
        if (_link.text.trim().isNotEmpty) 'link': _link.text.trim(),
        if (_scheduleAt != null && !dryRun) 'scheduleAt': _scheduleAt!.toUtc().toIso8601String(),
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
        title: Text(tr(_scheduleAt != null
            ? 'Hẹn ${DateFormat('HH:mm dd/MM').format(_scheduleAt!)} gửi cho ${targets.length} nhân viên?'
            : 'Gửi cho ${targets.length} nhân viên?')),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _statLine(Icons.phone_iphone_rounded, SboxColors.success, '$withApp người nhận trên điện thoại'),
          if (targets.length - withApp > 0)
            _statLine(Icons.phonelink_erase_rounded, SboxColors.slate500,
                '${targets.length - withApp} người chưa cài app — sẽ thấy khi mở web / app'),
          if (!_storeAllowsPush)
            _statLine(Icons.info_outline_rounded, SboxColors.warningText,
                'Gói dịch vụ chưa bật đẩy thông báo — chỉ hiện trong app'),
          const SizedBox(height: 8),
          Text(tr(_scheduleAt != null
                  ? 'Người nhận được tính lại đúng giờ gửi. Có thể hủy trong «Đã gửi» trước giờ hẹn.'
                  : 'Sau khi gửi chỉ thu hồi được với người chưa đọc (trong «Đã gửi»).'),
              style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
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
      if (d['scheduled'] == true) {
        NotificationOverlayManager().showSuccess(
          title: 'Đã hẹn giờ',
          message: tr('Sẽ gửi lúc ${DateFormat('HH:mm dd/MM').format(_scheduleAt ?? DateTime.now())} cho ${d['recipients'] ?? targets.length} người'),
        );
        setState(() {
          _title.clear();
          _body.clear();
          _link.clear();
          _templateId = null;
          _scheduleAt = null;
        });
        _load();
        return;
      }
      final queued = d['queued'] == true;
      final skipped = (d['skipped'] as num?)?.toInt() ?? 0;
      final delivered = (d['delivered'] as num?)?.toInt() ?? -1;
      NotificationOverlayManager().showSuccess(
        title: queued ? 'Đang gửi' : 'Đã gửi thông báo',
        message: queued
            ? tr('Đang gửi nền cho ${d['recipients'] ?? targets.length} người — xem tiến độ ở «Đã gửi»')
            : tr('${delivered >= 0 ? delivered : (d['recipients'] ?? targets.length)} người nhận · ${d['withApp'] ?? withApp} trên điện thoại'
                '${skipped > 0 ? ' · $skipped người đã tắt nhóm thông báo này' : ''}'),
      );
      setState(() {
        _title.clear();
        _body.clear();
        _link.clear();
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

  String get _audienceSummary {
    final n = _targets.length;
    return switch (_audience) {
      'departments' => _depts.isEmpty ? 'Chọn phòng ban' : '${_depts.length} phòng ban · $n người',
      'users' => _users.isEmpty ? 'Chọn người nhận' : '${_users.length} người đã chọn',
      'branches' => _branches.isEmpty ? 'Chọn chi nhánh' : '${_branches.length} chi nhánh · $n người',
      _ => 'Tất cả nhân viên · $n người',
    };
  }

  Future<void> _pickSchedule() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.bolt_rounded),
            title: Text(tr('Gửi ngay')),
            trailing: _scheduleAt == null ? const Icon(Icons.check_rounded, color: SboxColors.brand600) : null,
            onTap: () => Navigator.pop(ctx, 'now'),
          ),
          ListTile(
            leading: const Icon(Icons.schedule_send_rounded),
            title: Text(tr('Hẹn giờ gửi…')),
            subtitle: Text(tr('Người nhận được tính lại vào đúng giờ gửi')),
            trailing: _scheduleAt != null ? const Icon(Icons.check_rounded, color: SboxColors.brand600) : null,
            onTap: () => Navigator.pop(ctx, 'schedule'),
          ),
        ]),
      ),
    );
    if (choice == 'now') {
      setState(() => _scheduleAt = null);
    } else if (choice == 'schedule' && mounted) {
      final base = _scheduleAt ?? DateTime.now().add(const Duration(hours: 1));
      final d = await showDatePicker(
        context: context,
        initialDate: base,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 90)),
      );
      if (d == null || !mounted) return;
      final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
      if (t == null || !mounted) return;
      final at = DateTime(d.year, d.month, d.day, t.hour, t.minute);
      if (at.isBefore(DateTime.now().add(const Duration(minutes: 1)))) {
        NotificationOverlayManager().showWarning(title: 'Giờ hẹn chưa hợp lệ', message: tr('Chọn giờ sau hiện tại ít nhất 1 phút'));
        return;
      }
      setState(() => _scheduleAt = at);
    }
  }

  void _openSent() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationSentScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final form = <Widget>[
      _audienceRow(),
      const SizedBox(height: 10),
      _contentCard(),
      const SizedBox(height: 10),
      _optionsRow(),
    ];
    return Scaffold(
      backgroundColor: SboxColors.slate50,
      appBar: AppBar(
        title: Text(tr('Gửi thông báo')),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          TextButton.icon(
            onPressed: _openSent,
            icon: const Icon(Icons.history_rounded, size: 18),
            label: Text(tr('Đã gửi')),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : wide
              ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: ListView(padding: const EdgeInsets.all(20), children: form)),
                  SizedBox(
                    width: 380,
                    child: ListView(padding: const EdgeInsets.fromLTRB(0, 20, 20, 20), children: [
                      _previewSection(),
                      const SizedBox(height: 14),
                      _sendButton(),
                    ]),
                  ),
                ])
              : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), children: form),
      bottomNavigationBar: !_loading && !wide
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(children: [
                  OutlinedButton.icon(
                    onPressed: _showPreviewSheet,
                    icon: const Icon(Icons.visibility_rounded, size: 18),
                    label: Text(tr('Xem trước')),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: _sendButton()),
                ]),
              ),
            )
          : null,
    );
  }

  void _showPreviewSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 16), child: _previewSection()),
      ),
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

  // ── Người nhận: một dòng gọn, chạm để chọn trong bảng riêng ──
  Widget _audienceRow() {
    final targets = _targets;
    final withApp = targets.where((e) => e.hasApp).length;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _pickAudience,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: targets.isEmpty ? SboxColors.warning : SboxColors.slate200),
          ),
          child: Row(children: [
            const Icon(Icons.groups_rounded, color: SboxColors.brand500),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Gửi cho'), style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
                Text(tr(_audienceSummary), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                if (targets.isNotEmpty)
                  Text(tr('$withApp người có app trên điện thoại'),
                      style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: SboxColors.slate400),
          ]),
        ),
      ),
    );
  }

  Future<void> _pickAudience() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          void both(VoidCallback f) {
            setState(f);
            setSheet(() {});
          }

          final q = _search.text.trim().toLowerCase();
          final filtered = _employees
              .where((e) =>
                  q.isEmpty ||
                  e.name.toLowerCase().contains(q) ||
                  (e.code ?? '').toLowerCase().contains(q) ||
                  (e.department ?? '').toLowerCase().contains(q))
              .toList();
          return SizedBox(
            height: MediaQuery.sizeOf(ctx).height * 0.82,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(ctx).bottom + 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: Text(tr('Chọn người nhận'),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                  Text(tr('${_targets.length} người'),
                      style: const TextStyle(fontWeight: FontWeight.w700, color: SboxColors.brand600)),
                ]),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'all', label: Text(tr('Tất cả'))),
                    ButtonSegment(value: 'departments', label: Text(tr('Phòng ban'))),
                    if (_branchList.isNotEmpty) ButtonSegment(value: 'branches', label: Text(tr('Chi nhánh'))),
                    ButtonSegment(value: 'users', label: Text(tr('Chọn người'))),
                  ],
                  selected: {_audience},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => both(() => _audience = v.first),
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
                  Expanded(
                    child: SingleChildScrollView(
                      child: Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final d in _departments)
                          FilterChip(
                            label: Text('${tr(d['name']?.toString() ?? '')} · ${d['count']}',
                                style: const TextStyle(fontSize: 12.5)),
                            selected: _depts.contains(d['key']?.toString() ?? ''),
                            onSelected: (v) => both(() {
                              final k = d['key']?.toString() ?? '';
                              v ? _depts.add(k) : _depts.remove(k);
                            }),
                          ),
                      ]),
                    ),
                  ),
                if (_audience == 'branches')
                  Expanded(
                    child: SingleChildScrollView(
                      child: Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final b in _branchList)
                          FilterChip(
                            label: Text('${b['name']}${b['isHeadquarter'] == true ? ' (trụ sở)' : ''} · ${b['count']}',
                                style: const TextStyle(fontSize: 12.5)),
                            selected: _branches.contains(b['id'].toString()),
                            onSelected: (v) => both(() {
                              final k = b['id'].toString();
                              v ? _branches.add(k) : _branches.remove(k);
                            }),
                          ),
                      ]),
                    ),
                  ),
                if (_audience == 'users') ...[
                  TextField(
                    controller: _search,
                    onChanged: (_) => setSheet(() {}),
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      hintText: tr('Tìm tên, mã NV, phòng ban…'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  Row(children: [
                    TextButton(
                      onPressed: () => both(() => _users.addAll(filtered.map((e) => e.userId))),
                      child: Text(tr('Chọn ${filtered.length} người đang lọc')),
                    ),
                    if (_users.isNotEmpty)
                      TextButton(onPressed: () => both(_users.clear), child: Text(tr('Bỏ chọn (${_users.length})'))),
                  ]),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final e = filtered[i];
                        return CheckboxListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _users.contains(e.userId),
                          onChanged: (v) => both(() => v == true ? _users.add(e.userId) : _users.remove(e.userId)),
                          title: Text(e.name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            [e.code, e.department, e.position].where((x) => (x ?? '').isNotEmpty).join(' · '),
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          secondary: Icon(e.hasApp ? Icons.phone_iphone_rounded : Icons.phonelink_erase_rounded,
                              size: 18, color: e.hasApp ? SboxColors.success : SboxColors.slate300),
                        );
                      },
                    ),
                  ),
                ],
                if (_audience == 'all') const Spacer(),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                  child: Text(tr('Xong')),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ── Nội dung: mẫu một hàng ngang + tiêu đề + nội dung ──
  Widget _contentCard() {
    final mine = _templates.where((t) => t['builtIn'] != true).toList();
    final builtIn = _templates.where((t) => t['builtIn'] == true).toList();
    Widget chip(Map<String, dynamic> t) {
      final meta = NotificationCategoryMeta.of(t['categoryCode']?.toString());
      final isMine = t['builtIn'] != true;
      final selected = isMine && _templateId == t['id']?.toString();
      return GestureDetector(
        onLongPress: isMine ? () => _templateMenu(t) : null,
        child: ActionChip(
          avatar: Icon(meta.icon, size: 16, color: meta.color),
          label: Text(tr(t['name']?.toString() ?? ''), style: const TextStyle(fontSize: 12.5)),
          backgroundColor: selected ? meta.color.withValues(alpha: 0.12) : null,
          visualDensity: VisualDensity.compact,
          onPressed: () => _useTemplate(t),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SboxColors.slate200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.auto_awesome_rounded, size: 16, color: SboxColors.brand500),
          const SizedBox(width: 6),
          Text(tr('Dùng mẫu nhanh'), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          if (mine.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(tr('(giữ lâu mẫu của bạn để sửa / xoá)'),
                  style: const TextStyle(fontSize: 11, color: SboxColors.slate500)),
            ),
        ]),
        const SizedBox(height: 6),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [for (final t in [...mine, ...builtIn]) Padding(padding: const EdgeInsets.only(right: 6), child: chip(t))],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _title,
          focusNode: _titleFocus,
          maxLength: 200,
          textInputAction: TextInputAction.next,
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
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _link,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(
            labelText: tr('Liên kết kèm theo (không bắt buộc)'),
            hintText: 'https://…',
            prefixIcon: const Icon(Icons.link_rounded, size: 18),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        Row(children: [
          PopupMenuButton<String>(
            tooltip: tr('Chèn tên người nhận, ngày…'),
            onSelected: _insertVar,
            itemBuilder: (_) => [
              for (final v in _vars) PopupMenuItem(value: v.$1, child: Text('${v.$1}  ·  ${tr(v.$2)}')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.data_object_rounded, size: 16, color: SboxColors.brand600),
                const SizedBox(width: 4),
                Text(tr('Chèn tên / ngày'),
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: SboxColors.brand600)),
              ]),
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _title.text.trim().isEmpty || _body.text.trim().isEmpty ? null : () => _saveAsTemplate(),
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: Text(tr('Lưu thành mẫu')),
          ),
        ]),
        if (_hasBlanks)
          Container(
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
      ]),
    );
  }

  Future<void> _templateMenu(Map<String, dynamic> t) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.system_update_alt_rounded),
            title: Text(tr('Cập nhật mẫu bằng nội dung đang soạn')),
            onTap: () => Navigator.pop(ctx, 'update'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: SboxColors.danger),
            title: Text(tr('Xoá mẫu'), style: const TextStyle(color: SboxColors.danger)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ]),
      ),
    );
    if (v == 'update') {
      _saveAsTemplate(existing: t);
    } else if (v == 'delete') {
      _deleteTemplate(t);
    }
  }

  // ── Loại + mức độ: hai nút nhỏ, không chiếm chỗ ──
  Widget _optionsRow() {
    final cat = NotificationCategoryMeta.of(_category);
    final level = NotificationLevelMeta.of(_level);
    Widget pick<T>({
      required String label,
      required IconData icon,
      required Color color,
      required String value,
      required List<PopupMenuEntry<T>> items,
      required ValueChanged<T> onSelected,
    }) =>
        Expanded(
          child: PopupMenuButton<T>(
            onSelected: onSelected,
            itemBuilder: (_) => items,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SboxColors.slate200),
              ),
              child: Row(children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr(label), style: const TextStyle(fontSize: 10.5, color: SboxColors.slate500)),
                    Text(tr(value),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ]),
                ),
                const Icon(Icons.arrow_drop_down_rounded, color: SboxColors.slate400),
              ]),
            ),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        pick<String>(
          label: 'Loại',
          icon: cat.icon,
          color: cat.color,
          value: cat.label,
          items: [
            for (final c in NotificationCategoryMeta.composable)
              PopupMenuItem(
                value: c.code,
                child: Row(children: [Icon(c.icon, size: 18, color: c.color), const SizedBox(width: 8), Text(tr(c.label))]),
              ),
          ],
          onSelected: (v) => setState(() => _category = v),
        ),
        const SizedBox(width: 10),
        pick<int>(
          label: 'Mức độ',
          icon: level.icon,
          color: level.color,
          value: level.label,
          items: [
            for (final l in NotificationLevelMeta.levels)
              PopupMenuItem(
                value: l.value,
                child: Row(children: [Icon(l.icon, size: 18, color: l.color), const SizedBox(width: 8), Text(tr(l.label))]),
              ),
          ],
          onSelected: (v) => setState(() => _level = v),
        ),
      ]),
      const SizedBox(height: 10),
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _pickSchedule,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _scheduleAt == null ? SboxColors.slate200 : SboxColors.brand500),
          ),
          child: Row(children: [
            Icon(_scheduleAt == null ? Icons.bolt_rounded : Icons.schedule_send_rounded,
                size: 18, color: SboxColors.brand600),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Thời điểm gửi'), style: const TextStyle(fontSize: 10.5, color: SboxColors.slate500)),
                Text(
                  _scheduleAt == null ? tr('Gửi ngay') : DateFormat('HH:mm · dd/MM/yyyy').format(_scheduleAt!),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ]),
            ),
            const Icon(Icons.arrow_drop_down_rounded, color: SboxColors.slate400),
          ]),
        ),
      ),
      if (_level == 2)
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(tr('Mức "Quan trọng" vẫn đổ chuông trong giờ yên lặng của nhân viên.'),
              style: const TextStyle(fontSize: 11.5, color: SboxColors.slate500)),
        ),
    ]);
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
        label: Text(tr(_sending ? 'Đang gửi…' : (_scheduleAt != null ? 'Hẹn giờ gửi cho $n người' : 'Gửi cho $n người')),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        style: FilledButton.styleFrom(
          backgroundColor: SboxColors.brand500,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
