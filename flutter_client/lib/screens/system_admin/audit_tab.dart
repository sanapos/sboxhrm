import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/file_saver.dart';
import '../../widgets/notification_overlay.dart';
import '../activity_log_screen.dart' show activityFieldLabel;

/// Nhật ký hệ thống (Super Admin): lọc tại server theo cửa hàng, tài khoản, nhóm / loại thao tác,
/// chức năng, kết quả, khoảng ngày, từ khóa. Nội dung tiếng Việt, xem chi tiết từng trường thay đổi.
class AuditTab extends StatefulWidget {
  const AuditTab({super.key});

  @override
  State<AuditTab> createState() => AuditTabState();
}

class AuditTabState extends State<AuditTab> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _hm = DateFormat('HH:mm:ss');
  final _dmy = DateFormat('dd/MM/yyyy');
  Timer? _debounce;

  String _range = '7d';
  DateTime? _from;
  DateTime? _to;
  String? _storeId; // '' = không gắn cửa hàng (quản trị hệ thống)
  String? _storeName;
  String? _userId;
  String? _userName;
  String? _kind; // data · auth · admin
  String? _action;
  String? _module;
  bool _failedOnly = false;

  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _stores = [];
  int _noStoreCount = 0;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _actions = [];
  List<Map<String, dynamic>> _modules = [];
  int _total = 0, _failed = 0, _page = 1;
  Map<String, int> _kinds = {};
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  static const _emptyGuid = '00000000-0000-0000-0000-000000000000';

  @override
  void initState() {
    super.initState();
    _applyRange('7d', reload: false);
    loadData();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _applyRange(String r, {bool reload = true}) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    _range = r;
    switch (r) {
      case 'today':
        _from = today;
        _to = today;
      case '7d':
        _from = today.subtract(const Duration(days: 6));
        _to = today;
      case '30d':
        _from = today.subtract(const Duration(days: 29));
        _to = today;
      case '90d':
        _from = today.subtract(const Duration(days: 89));
        _to = today;
      case 'all':
        _from = null;
        _to = null;
    }
    if (reload) loadData();
  }

  Future<void> _pickRange() async {
    final n = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(n.year - 2),
      lastDate: n,
      initialDateRange: _from == null ? null : DateTimeRange(start: _from!, end: _to ?? _from!),
    );
    if (r == null) return;
    setState(() {
      _range = 'custom';
      _from = r.start;
      _to = r.end;
    });
    loadData();
  }

  String? get _storeParam => _storeId == null ? null : (_storeId!.isEmpty ? _emptyGuid : _storeId);

  /// Tải lại danh mục lọc + trang đầu.
  Future<void> loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final results = await Future.wait([
      _api.getSaAuditFilters(storeId: _storeParam, from: _from, to: _to),
      _fetch(1),
    ]);
    if (!mounted) return;
    final f = results[0];
    setState(() {
      if (f['isSuccess'] == true && f['data'] is Map) {
        final d = f['data'] as Map;
        List<Map<String, dynamic>> list(String k) =>
            ((d[k] as List?) ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _stores = list('stores');
        _noStoreCount = (d['noStoreCount'] as num?)?.toInt() ?? 0;
        _users = list('users');
        _actions = list('actions');
        _modules = list('modules');
        if (_userId != null && !_users.any((u) => '${u['id']}' == _userId)) {
          _userId = null;
          _userName = null;
        }
        if (_action != null && !_actions.any((a) => a['code'] == _action)) _action = null;
        if (_module != null && !_modules.any((m) => m['code'] == _module)) _module = null;
      }
      _loading = false;
    });
  }

  Future<Map<String, dynamic>> _fetch(int page) async {
    final res = await _api.getSaAuditLogs(
      storeId: _storeParam,
      userId: _userId,
      action: _action,
      kind: _kind,
      module: _module,
      status: _failedOnly ? 'Failed' : null,
      from: _from,
      to: _to,
      search: _searchCtrl.text,
      page: page,
    );
    if (!mounted) return res;
    setState(() {
      if (res['isSuccess'] == true && res['data'] is Map) {
        final d = res['data'] as Map;
        final rows = ((d['items'] as List?) ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _items = page == 1 ? rows : [..._items, ...rows];
        _total = (d['total'] as num?)?.toInt() ?? 0;
        _failed = (d['failed'] as num?)?.toInt() ?? 0;
        _kinds = (d['kinds'] is Map)
            ? (d['kinds'] as Map).map((k, v) => MapEntry('$k', (v as num?)?.toInt() ?? 0))
            : {};
        _page = page;
        _error = null;
      } else {
        _error = res['message']?.toString() ?? tr('Không tải được nhật ký');
      }
    });
    return res;
  }

  Future<void> _refetch() async {
    setState(() => _loading = true);
    await _fetch(1);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _items.length >= _total) return;
    setState(() => _loadingMore = true);
    await _fetch(_page + 1);
    if (mounted) setState(() => _loadingMore = false);
  }

  Future<void> _export() async {
    final res = await _api.downloadSaAuditExcel(
      storeId: _storeParam,
      userId: _userId,
      action: _action,
      kind: _kind,
      module: _module,
      status: _failedOnly ? 'Failed' : null,
      from: _from,
      to: _to,
      search: _searchCtrl.text,
    );
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(title: 'Không xuất được Excel', message: res['message']?.toString() ?? '');
      return;
    }
    await saveAndOpenFileBytes(List<int>.from(res['data'] as List), 'nhat_ky_he_thong.xlsx',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  }

  /// Chọn từ danh sách dài (cửa hàng / tài khoản) có ô tìm.
  Future<Map<String, dynamic>?> _pickFromList({
    required String title,
    required List<Map<String, dynamic>> items,
    required String Function(Map<String, dynamic>) label,
    required String Function(Map<String, dynamic>) sub,
    Map<String, dynamic>? extra,
  }) {
    final ctrl = TextEditingController();
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final q = ctrl.text.trim().toLowerCase();
          final rows = [
            if (extra != null) extra,
            ...items.where((e) => q.isEmpty || '${label(e)} ${sub(e)}'.toLowerCase().contains(q)),
          ];
          return AlertDialog(
            title: Text(tr(title)),
            content: SizedBox(
              width: 460,
              height: 480,
              child: Column(children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: _dec(tr('Tìm…'), Icons.search),
                  onChanged: (_) => setD(() {}),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: rows.isEmpty
                      ? Center(child: Text(tr('Không có kết quả')))
                      : ListView.builder(
                          itemCount: rows.length,
                          itemBuilder: (_, i) => ListTile(
                            dense: true,
                            title: Text(label(rows[i]), maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(sub(rows[i]), maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: Text('${rows[i]['count'] ?? ''}',
                                style: const TextStyle(color: SboxColors.slate500, fontSize: 12)),
                            onTap: () => Navigator.pop(ctx, rows[i]),
                          ),
                        ),
                ),
              ]),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng')))],
          );
        },
      ),
    );
  }

  Future<void> _chooseStore() async {
    final r = await _pickFromList(
      title: 'Chọn cửa hàng',
      items: _stores,
      label: (e) => '${e['name'] ?? ''}',
      sub: (e) => e['code'] == null ? '' : 'Mã: ${e['code']}',
      extra: _noStoreCount > 0
          ? {'id': '', 'name': 'Quản trị hệ thống (không gắn cửa hàng)', 'count': _noStoreCount}
          : null,
    );
    if (r == null) return;
    setState(() {
      _storeId = '${r['id']}';
      _storeName = '${r['name']}';
      _userId = null;
      _userName = null;
    });
    loadData();
  }

  Future<void> _chooseUser() async {
    final r = await _pickFromList(
      title: 'Chọn tài khoản',
      items: _users,
      label: (e) => '${e['name'] ?? e['email'] ?? ''}',
      sub: (e) => '${e['email'] ?? ''}',
    );
    if (r == null) return;
    setState(() {
      _userId = '${r['id']}';
      _userName = '${r['name'] ?? r['email']}';
    });
    _refetch();
  }

  // ─── Giao diện ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Container(
      color: const Color(0xFFF6F7F9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFilterBar(wide),
          _buildSummary(),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _rangeChip(String key, String label) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(tr(label)),
          selected: _range == key,
          onSelected: (_) => setState(() => _applyRange(key)),
          visualDensity: VisualDensity.compact,
        ),
      );

  Widget _pickerButton({
    required IconData icon,
    required String label,
    required String? value,
    required VoidCallback onTap,
    required VoidCallback onClear,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: _dec(tr(label), icon).copyWith(
          suffixIcon: value == null
              ? const Icon(Icons.arrow_drop_down)
              : IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onClear, tooltip: tr('Bỏ lọc')),
        ),
        child: Text(value ?? tr('Tất cả'), maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _buildFilterBar(bool wide) {
    final dateLabel = _from == null
        ? tr('Chọn ngày')
        : (_from == _to ? _dmy.format(_from!) : '${_dmy.format(_from!)} – ${_dmy.format(_to!)}');
    final storeBox = _pickerButton(
      icon: Icons.storefront_outlined,
      label: 'Cửa hàng',
      value: _storeName,
      onTap: _chooseStore,
      onClear: () {
        setState(() {
          _storeId = null;
          _storeName = null;
        });
        loadData();
      },
    );
    final userBox = _pickerButton(
      icon: Icons.person_outline,
      label: 'Tài khoản',
      value: _userName,
      onTap: _chooseUser,
      onClear: () {
        setState(() {
          _userId = null;
          _userName = null;
        });
        _refetch();
      },
    );
    final actionBox = DropdownButtonFormField<String?>(
      value: _action,
      isExpanded: true,
      decoration: _dec(tr('Loại thao tác'), Icons.bolt_outlined),
      items: [
        DropdownMenuItem(value: null, child: Text(tr('Tất cả thao tác'))),
        for (final a in _actions.where((a) => _kind == null || a['kind'] == _kind))
          DropdownMenuItem(value: '${a['code']}', child: Text('${a['name']} (${a['count']})', overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) {
        setState(() => _action = v);
        _refetch();
      },
    );
    final moduleBox = DropdownButtonFormField<String?>(
      value: _module,
      isExpanded: true,
      decoration: _dec(tr('Chức năng'), Icons.apps_outlined),
      items: [
        DropdownMenuItem(value: null, child: Text(tr('Tất cả chức năng'))),
        for (final m in _modules)
          DropdownMenuItem(value: '${m['code']}', child: Text('${m['name']} (${m['count']})', overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (v) {
        setState(() => _module = v);
        _refetch();
      },
    );
    final searchBox = TextField(
      controller: _searchCtrl,
      decoration: _dec(tr('Tìm: email, tên, cửa hàng, IP, nội dung…'), Icons.search),
      onChanged: (_) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 450), _refetch);
      },
    );
    final kinds = SegmentedButton<String?>(
      segments: [
        ButtonSegment(value: null, label: Text(tr('Tất cả'))),
        ButtonSegment(value: 'data', label: Text(tr('Dữ liệu')), icon: const Icon(Icons.edit_note, size: 16)),
        ButtonSegment(value: 'auth', label: Text(tr('Đăng nhập')), icon: const Icon(Icons.login, size: 16)),
        ButtonSegment(value: 'admin', label: Text(tr('Quản trị')), icon: const Icon(Icons.admin_panel_settings_outlined, size: 16)),
      ],
      selected: {_kind},
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      onSelectionChanged: (s) {
        setState(() {
          _kind = s.first;
          _action = null;
        });
        _refetch();
      },
    );

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.manage_search, color: SboxColors.brand600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(tr('Nhật ký hệ thống'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: SboxColors.slate900)),
            ),
            FilterChip(
              label: Text(tr('Chỉ lỗi')),
              selected: _failedOnly,
              avatar: Icon(Icons.error_outline, size: 16, color: _failedOnly ? null : SboxColors.danger),
              onSelected: (v) {
                setState(() => _failedOnly = v);
                _refetch();
              },
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            IconButton(tooltip: tr('Xuất Excel'), onPressed: _loading ? null : _export, icon: const Icon(Icons.table_view_outlined)),
          ]),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _rangeChip('today', 'Hôm nay'),
              _rangeChip('7d', '7 ngày'),
              _rangeChip('30d', '30 ngày'),
              _rangeChip('90d', '90 ngày'),
              _rangeChip('all', 'Tất cả'),
              ActionChip(
                avatar: const Icon(Icons.date_range, size: 16),
                label: Text(_range == 'custom' ? dateLabel : tr('Chọn ngày')),
                onPressed: _pickRange,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 10),
              kinds,
            ]),
          ),
          const SizedBox(height: 10),
          if (wide) ...[
            Row(children: [
              Expanded(flex: 3, child: searchBox),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: storeBox),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: userBox),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: actionBox),
              const SizedBox(width: 10),
              Expanded(child: moduleBox),
            ]),
          ] else ...[
            searchBox,
            const SizedBox(height: 8),
            storeBox,
            const SizedBox(height: 8),
            userBox,
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: actionBox),
              const SizedBox(width: 8),
              Expanded(child: moduleBox),
            ]),
          ],
        ],
      ),
    );
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        isDense: true,
        filled: true,
        fillColor: SboxColors.slate50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: SboxColors.slate200)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: SboxColors.slate200)),
      );

  Widget _buildSummary() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Wrap(spacing: 8, runSpacing: 6, children: [
          _stat('Tổng', _total, SboxColors.slate700),
          _stat('Dữ liệu', _kinds['data'] ?? 0, SboxColors.brand600),
          _stat('Đăng nhập', _kinds['auth'] ?? 0, SboxColors.success),
          _stat('Quản trị', _kinds['admin'] ?? 0, SboxColors.warning),
          _stat('Lỗi', _failed, SboxColors.danger),
        ]),
      );

  Widget _stat(String label, int n, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: SboxColors.slate200)),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '${tr(label)} ', style: const TextStyle(color: SboxColors.slate500, fontSize: 13)),
          TextSpan(text: NumberFormat('#,##0', 'vi_VN').format(n), style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 13)),
        ])),
      );

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.red))));
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.history_toggle_off, size: 48, color: SboxColors.slate300),
          const SizedBox(height: 8),
          Text(tr('Không có nhật ký nào khớp bộ lọc'), style: const TextStyle(color: SboxColors.slate500)),
        ]),
      );
    }
    final children = <Widget>[];
    String? lastDay;
    for (final it in _items) {
      final t = DateTime.tryParse('${it['timestamp']}Z'.replaceAll('ZZ', 'Z'))?.toLocal();
      final day = t == null ? '' : _dmy.format(t);
      if (day != lastDay) {
        lastDay = day;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
          child: Text(_dayTitle(t), style: const TextStyle(fontWeight: FontWeight.w700, color: SboxColors.slate600)),
        ));
      }
      children.add(_row(it, t));
    }
    if (_items.length < _total) {
      children.add(Padding(
        padding: const EdgeInsets.all(12),
        child: Center(
          child: OutlinedButton.icon(
            onPressed: _loadingMore ? null : _loadMore,
            icon: _loadingMore
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.expand_more),
            label: Text(tr('Xem thêm (${_items.length}/$_total)')),
          ),
        ),
      ));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: children);
  }

  String _dayTitle(DateTime? t) {
    if (t == null) return '';
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final d = DateTime(t.year, t.month, t.day);
    if (d == today) return tr('Hôm nay · ${_dmy.format(t)}');
    if (d == today.subtract(const Duration(days: 1))) return tr('Hôm qua · ${_dmy.format(t)}');
    return _dmy.format(t);
  }

  (Color, IconData) _style(String action, bool failed) {
    if (failed) return (SboxColors.danger, Icons.error_outline);
    return switch (action) {
      'Create' => (SboxColors.success, Icons.add),
      'Update' => (SboxColors.warning, Icons.edit_outlined),
      'Delete' => (SboxColors.danger, Icons.delete_outline),
      'Login' => (SboxColors.brand600, Icons.login),
      'Logout' => (SboxColors.slate500, Icons.logout),
      'Impersonate' => (SboxColors.violet, Icons.support_agent),
      _ => (SboxColors.slate600, Icons.admin_panel_settings_outlined),
    };
  }

  Widget _row(Map<String, dynamic> it, DateTime? t) {
    final failed = it['status'] == 'Failed';
    final (color, icon) = _style('${it['action']}', failed);
    final who = '${it['userName'] ?? it['userEmail'] ?? tr('Không rõ')}';
    final meta = [
      if ((it['storeName'] ?? '').toString().isNotEmpty) '${it['storeName']}',
      if ((it['moduleName'] ?? '').toString().isNotEmpty && it['kind'] == 'data') '${it['moduleName']}',
      if ((it['userRole'] ?? '').toString().isNotEmpty) '${it['userRole']}',
      if ((it['device'] ?? '').toString().isNotEmpty) '${it['device']}',
      if ((it['ipAddress'] ?? '').toString().isNotEmpty) 'IP ${it['ipAddress']}',
    ].join(' · ');
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: failed ? SboxColors.danger.withValues(alpha: .4) : SboxColors.slate200)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showDetail(it),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(children: [
            SizedBox(
              width: 64,
              child: Text(t == null ? '' : _hm.format(t),
                  style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], color: SboxColors.slate500, fontSize: 13)),
            ),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: color.withValues(alpha: .12), shape: BoxShape.circle),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: who, style: const TextStyle(fontWeight: FontWeight.w700, color: SboxColors.slate900)),
                    TextSpan(text: ' ${'${it['actionName'] ?? ''}'.toLowerCase()} ', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                    TextSpan(text: '${it['summary'] ?? ''}', style: const TextStyle(color: SboxColors.slate800)),
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (failed && (it['errorMessage'] ?? '').toString().isNotEmpty)
                  Text('${it['errorMessage']}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: SboxColors.danger)),
                const SizedBox(height: 2),
                Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: SboxColors.slate400)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: SboxColors.slate300),
          ]),
        ),
      ),
    );
  }

  Future<void> _showDetail(Map<String, dynamic> it) async {
    final res = await _api.getSaAuditDetail('${it['id']}');
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      NotificationOverlayManager().showError(title: 'Không tải được chi tiết', message: res['message']?.toString() ?? '');
      return;
    }
    final d = res['data'] as Map;
    final details = d['details'] is Map ? d['details'] as Map : const {};
    final changes = ((details['changes'] as List?) ?? []).whereType<Map>().toList();
    final text = (d['text'] ?? '').toString();
    final t = DateTime.tryParse('${it['timestamp']}Z'.replaceAll('ZZ', 'Z'))?.toLocal();
    final failed = it['status'] == 'Failed';
    final (color, _) = _style('${it['action']}', failed);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(14)),
            child: Text('${it['actionName'] ?? ''}', style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text('${it['summary'] ?? ''}', style: const TextStyle(fontSize: 16), maxLines: 2)),
        ]),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _kv(tr('Thời gian'), t == null ? '' : DateFormat('dd/MM/yyyy HH:mm:ss').format(t)),
              _kv(tr('Cửa hàng'), '${it['storeName'] ?? tr('Quản trị hệ thống')}'),
              _kv(tr('Tài khoản'), '${it['userName'] ?? ''} ${it['userEmail'] == null ? '' : '(${it['userEmail']})'}'),
              _kv(tr('Vai trò'), '${it['userRole'] ?? ''}'),
              _kv(tr('Chức năng'), '${it['moduleName'] ?? ''}'),
              _kv(tr('Kết quả'), failed ? '${tr('Lỗi')}: ${it['errorMessage'] ?? ''}' : tr('Thành công')),
              _kv(tr('Thiết bị'), '${it['device'] ?? ''}${(it['ipAddress'] ?? '').toString().isEmpty ? '' : ' · IP ${it['ipAddress']}'}'),
              if ((details['endpoint'] ?? '').toString().isNotEmpty) _kv(tr('Thao tác API'), '${details['endpoint']}'),
              const Divider(height: 20),
              if (text.isNotEmpty) SelectableText(text, style: const TextStyle(fontSize: 13)),
              for (final c in changes) _changeBlock(c),
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng')))],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(k, style: const TextStyle(color: SboxColors.slate500, fontSize: 13))),
          Expanded(child: SelectableText(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _changeBlock(Map c) {
    final op = '${c['op']}';
    final (label, color) = switch (op) {
      'Create' => ('Thêm', SboxColors.success),
      'Delete' => ('Xóa', SboxColors.danger),
      _ => ('Sửa', SboxColors.warning),
    };
    final fields = ((c['fields'] as List?) ?? []).whereType<Map>().toList();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: SboxColors.slate200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          color: SboxColors.slate50,
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '${tr(label)} ', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
            TextSpan(text: '${c['typeName'] ?? c['type']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            if ((c['label'] ?? '').toString().isNotEmpty) TextSpan(text: ' «${c['label']}»'),
          ])),
        ),
        if (fields.isNotEmpty)
          Table(
            columnWidths: const {0: FlexColumnWidth(1.1), 1: FlexColumnWidth(1.4), 2: FlexColumnWidth(1.4)},
            border: const TableBorder(horizontalInside: BorderSide(color: SboxColors.slate100)),
            children: [
              TableRow(children: [
                for (final h in ['Trường', 'Trước', 'Sau'])
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                    child: Text(tr(h), style: const TextStyle(fontSize: 12, color: SboxColors.slate500, fontWeight: FontWeight.w700)),
                  ),
              ]),
              for (final f in fields)
                TableRow(children: [
                  _cell('${f['fieldName'] ?? activityFieldLabel('${f['field']}')}', bold: true),
                  _cell(f['old'] == null ? '—' : '${f['old']}', color: SboxColors.dangerText),
                  _cell(f['new'] == null ? '—' : '${f['new']}', color: SboxColors.payHover),
                ]),
            ],
          ),
      ]),
    );
  }

  Widget _cell(String s, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        child: SelectableText(s, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w600 : FontWeight.normal, color: color)),
      );
}
