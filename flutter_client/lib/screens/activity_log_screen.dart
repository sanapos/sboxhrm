import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_tr.dart';
import '../services/api_service.dart';
import '../utils/file_saver.dart';
import '../widgets/notification_overlay.dart';

const _blue = Color(0xFF2563EB);

/// Lịch sử thao tác của cửa hàng (30 ngày): ai thêm / sửa / xóa gì, lúc nào, ở chức năng nào.
class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _hm = DateFormat('HH:mm:ss');
  final _dmy = DateFormat('dd/MM/yyyy');
  Timer? _debounce;

  late DateTime _from;
  late DateTime _to;
  String _range = 'today';
  String? _userId;
  String? _module;
  String? _action;

  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _modules = [];
  int _total = 0, _creates = 0, _updates = 0, _deletes = 0;
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _from = DateTime(n.year, n.month, n.day);
    _to = _from;
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _setRange(String r) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    setState(() {
      _range = r;
      switch (r) {
        case 'today':
          _from = today;
          _to = today;
        case 'yesterday':
          _from = today.subtract(const Duration(days: 1));
          _to = _from;
        case '7d':
          _from = today.subtract(const Duration(days: 6));
          _to = today;
        case '30d':
          _from = today.subtract(const Duration(days: 29));
          _to = today;
      }
    });
    _reload();
  }

  Future<void> _pickRange() async {
    final n = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: n.subtract(const Duration(days: 30)),
      lastDate: n,
      initialDateRange: DateTimeRange(start: _from, end: _to),
      helpText: tr('Chọn khoảng ngày (tối đa 30 ngày gần nhất)'),
    );
    if (r == null) return;
    setState(() {
      _range = 'custom';
      _from = r.start;
      _to = r.end;
    });
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
    });
    final results = await Future.wait([
      _api.getActivityLogFilters(from: _from, to: _to),
      _fetch(1),
    ]);
    if (!mounted) return;
    final f = results[0];
    setState(() {
      if (f['isSuccess'] == true && f['data'] is Map) {
        final d = f['data'] as Map;
        _users = ((d['users'] as List?) ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _modules = ((d['modules'] as List?) ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        if (_userId != null && !_users.any((u) => u['userId'] == _userId)) _userId = null;
        if (_module != null && !_modules.any((m) => m['code'] == _module)) _module = null;
      }
      _loading = false;
    });
  }

  Future<Map<String, dynamic>> _fetch(int page) async {
    final res = await _api.getActivityLogs(
      from: _from,
      to: _to,
      userId: _userId,
      module: _module,
      action: _action,
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
        _creates = (d['creates'] as num?)?.toInt() ?? 0;
        _updates = (d['updates'] as num?)?.toInt() ?? 0;
        _deletes = (d['deletes'] as num?)?.toInt() ?? 0;
        _page = page;
      } else {
        _error = res['message']?.toString() ?? tr('Không tải được lịch sử thao tác');
      }
    });
    return res;
  }

  Future<void> _applyFilters() async {
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
    final res = await _api.downloadActivityLogsExcel(
        from: _from, to: _to, userId: _userId, module: _module, action: _action, search: _searchCtrl.text);
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(title: 'Không xuất được Excel', message: res['message']?.toString() ?? '');
      return;
    }
    await saveAndOpenFileBytes(List<int>.from(res['data'] as List), 'lich_su_thao_tac.xlsx',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
  }

  // ─── Giao diện ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFilterBar(wide),
          _buildSummary(),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _chip(String key, String label) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(tr(label)),
          selected: _range == key,
          onSelected: (_) => _setRange(key),
          visualDensity: VisualDensity.compact,
        ),
      );

  Widget _buildFilterBar(bool wide) {
    final dateLabel = _from == _to ? _dmy.format(_from) : '${_dmy.format(_from)} – ${_dmy.format(_to)}';
    final userBox = DropdownButtonFormField<String?>(
      value: _userId,
      isExpanded: true,
      decoration: _dec(tr('Người thao tác'), Icons.person_outline),
      items: [
        DropdownMenuItem(value: null, child: Text(tr('Tất cả mọi người'))),
        for (final u in _users)
          DropdownMenuItem(
            value: '${u['userId']}',
            child: Text('${u['name'] ?? u['email'] ?? ''} (${u['count']})', overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        setState(() => _userId = v);
        _applyFilters();
      },
    );
    final moduleBox = DropdownButtonFormField<String?>(
      value: _module,
      isExpanded: true,
      decoration: _dec(tr('Chức năng'), Icons.apps_outlined),
      items: [
        DropdownMenuItem(value: null, child: Text(tr('Tất cả chức năng'))),
        for (final m in _modules)
          DropdownMenuItem(
            value: '${m['code']}',
            child: Text('${m['name']} (${m['count']})', overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        setState(() => _module = v);
        _applyFilters();
      },
    );
    final searchBox = TextField(
      controller: _searchCtrl,
      decoration: _dec(tr('Tìm: số hóa đơn, tên hàng, khách…'), Icons.search),
      onChanged: (_) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 450), _applyFilters);
      },
    );
    final actions = SegmentedButton<String?>(
      segments: [
        ButtonSegment(value: null, label: Text(tr('Tất cả'))),
        ButtonSegment(value: 'Create', label: Text(tr('Thêm')), icon: const Icon(Icons.add, size: 16)),
        ButtonSegment(value: 'Update', label: Text(tr('Sửa')), icon: const Icon(Icons.edit_outlined, size: 16)),
        ButtonSegment(value: 'Delete', label: Text(tr('Xóa')), icon: const Icon(Icons.delete_outline, size: 16)),
      ],
      selected: {_action},
      showSelectedIcon: false,
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      onSelectionChanged: (s) {
        setState(() => _action = s.first);
        _applyFilters();
      },
    );

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            const Icon(Icons.history, color: _blue),
            const SizedBox(width: 8),
            Expanded(
              child: Text(tr('Lịch sử thao tác'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
            ),
            Text(tr('Lưu 30 ngày gần nhất'), style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
            const SizedBox(width: 8),
            IconButton(tooltip: tr('Tải lại'), onPressed: _loading ? null : _reload, icon: const Icon(Icons.refresh)),
            IconButton(
              tooltip: tr('Xuất Excel'),
              onPressed: _loading ? null : _export,
              icon: const Icon(Icons.table_view_outlined),
            ),
          ]),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _chip('today', 'Hôm nay'),
              _chip('yesterday', 'Hôm qua'),
              _chip('7d', '7 ngày'),
              _chip('30d', '30 ngày'),
              ActionChip(
                avatar: const Icon(Icons.date_range, size: 16),
                label: Text(_range == 'custom' ? dateLabel : tr('Chọn ngày')),
                onPressed: _pickRange,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 10),
              actions,
            ]),
          ),
          const SizedBox(height: 10),
          if (wide)
            Row(children: [
              Expanded(flex: 3, child: searchBox),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: userBox),
              const SizedBox(width: 10),
              Expanded(flex: 2, child: moduleBox),
            ])
          else ...[
            searchBox,
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: userBox),
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
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
      );

  Widget _buildSummary() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Wrap(spacing: 8, runSpacing: 6, children: [
          _stat('Tổng', _total, const Color(0xFF334155)),
          _stat('Thêm', _creates, const Color(0xFF16A34A)),
          _stat('Sửa', _updates, const Color(0xFFD97706)),
          _stat('Xóa', _deletes, const Color(0xFFDC2626)),
        ]),
      );

  Widget _stat(String label, int n, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '${tr(label)} ', style: const TextStyle(color: Color(0xFF64748B), fontSize: 12.5)),
          TextSpan(text: '$n', style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 13)),
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
          const Icon(Icons.history_toggle_off, size: 48, color: Color(0xFFCBD5E1)),
          const SizedBox(height: 8),
          Text(tr('Không có thao tác nào trong khoảng đã chọn'), style: const TextStyle(color: Color(0xFF64748B))),
        ]),
      );
    }
    // Nhóm theo ngày.
    final children = <Widget>[];
    String? lastDay;
    for (final it in _items) {
      final t = DateTime.tryParse('${it['timestamp']}')?.toLocal();
      final day = t == null ? '' : _dmy.format(t);
      if (day != lastDay) {
        lastDay = day;
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
          child: Text(_dayTitle(t), style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF475569))),
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

  Widget _row(Map<String, dynamic> it, DateTime? t) {
    final (label, color, icon) = _actionStyle('${it['action']}');
    final name = '${it['userName'] ?? it['userEmail'] ?? tr('Không rõ')}';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Color(0xFFE2E8F0))),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showDetail(it),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(children: [
            SizedBox(
              width: 64,
              child: Text(t == null ? '' : _hm.format(t),
                  style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], color: Color(0xFF64748B), fontSize: 12.5)),
            ),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: color.withOpacity(.12), shape: BoxShape.circle),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: name, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                    TextSpan(text: ' ${tr(label).toLowerCase()} ', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                    TextSpan(text: '${it['entityName'] ?? ''}', style: const TextStyle(color: Color(0xFF1E293B))),
                  ]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    '${it['moduleName'] ?? ''}',
                    if ((it['userRole'] ?? '').toString().isNotEmpty) '${it['userRole']}',
                    if ((it['device'] ?? '').toString().isNotEmpty) '${it['device']}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                ),
              ]),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFCBD5E1)),
          ]),
        ),
      ),
    );
  }

  (String, Color, IconData) _actionStyle(String a) => switch (a) {
        'Create' => ('Thêm', const Color(0xFF16A34A), Icons.add),
        'Delete' => ('Xóa', const Color(0xFFDC2626), Icons.delete_outline),
        _ => ('Sửa', const Color(0xFFD97706), Icons.edit_outlined),
      };

  Future<void> _showDetail(Map<String, dynamic> it) async {
    final res = await _api.getActivityLogDetail('${it['id']}');
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      NotificationOverlayManager().showError(title: 'Không tải được chi tiết', message: res['message']?.toString() ?? '');
      return;
    }
    final d = res['data'] as Map;
    final details = d['details'] is Map ? d['details'] as Map : const {};
    final changes = ((details['changes'] as List?) ?? []).whereType<Map>().toList();
    final t = DateTime.tryParse('${it['timestamp']}')?.toLocal();
    final (label, color, _) = _actionStyle('${it['action']}');
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(12)),
            child: Text(tr(label), style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text('${it['entityName'] ?? ''}', style: const TextStyle(fontSize: 16), maxLines: 2)),
        ]),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _kv(tr('Người thao tác'), '${it['userName'] ?? ''} ${it['userEmail'] == null ? '' : '(${it['userEmail']})'}'),
              _kv(tr('Vai trò'), '${it['userRole'] ?? ''}'),
              _kv(tr('Thời gian'), t == null ? '' : DateFormat('dd/MM/yyyy HH:mm:ss').format(t)),
              _kv(tr('Chức năng'), '${it['moduleName'] ?? ''}'),
              _kv(tr('Thiết bị'), '${it['device'] ?? ''}${(it['ipAddress'] ?? '').toString().isEmpty ? '' : ' · IP ${it['ipAddress']}'}'),
              const Divider(height: 20),
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
          SizedBox(width: 120, child: Text(k, style: const TextStyle(color: Color(0xFF64748B), fontSize: 13))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _changeBlock(Map c) {
    final (label, color, _) = _actionStyle('${c['op'] == 'Create' ? 'Create' : c['op'] == 'Delete' ? 'Delete' : 'Update'}');
    final fields = ((c['fields'] as List?) ?? []).whereType<Map>().toList();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          color: const Color(0xFFF8FAFC),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '${tr(label)} ', style: TextStyle(color: color, fontWeight: FontWeight.w800)),
            TextSpan(text: '${c['typeName'] ?? c['type']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            if ((c['label'] ?? '').toString().isNotEmpty) TextSpan(text: ' «${c['label']}»'),
          ])),
        ),
        if (fields.isNotEmpty)
          Table(
            columnWidths: const {0: FlexColumnWidth(1.1), 1: FlexColumnWidth(1.4), 2: FlexColumnWidth(1.4)},
            border: const TableBorder(horizontalInside: BorderSide(color: Color(0xFFF1F5F9))),
            children: [
              TableRow(children: [
                for (final h in [c['op'] == 'Create' ? 'Trường' : 'Trường', 'Trước', 'Sau'])
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                    child: Text(tr(h), style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w700)),
                  ),
              ]),
              for (final f in fields)
                TableRow(children: [
                  _cell(activityFieldLabel('${f['field']}'), bold: true),
                  _cell(f['old'] == null ? '—' : '${f['old']}', color: const Color(0xFFB91C1C)),
                  _cell(f['new'] == null ? '—' : '${f['new']}', color: const Color(0xFF15803D)),
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

/// Tên trường dễ hiểu (không có → tách chữ từ tên kỹ thuật).
String activityFieldLabel(String field) {
  const map = {
    'Name': 'Tên', 'FullName': 'Họ tên', 'FirstName': 'Tên', 'LastName': 'Họ', 'Code': 'Mã', 'Barcode': 'Mã vạch',
    'Price': 'Giá', 'BasePrice': 'Giá bán', 'SalePrice': 'Giá bán', 'CostPrice': 'Giá vốn', 'UnitPrice': 'Đơn giá',
    'Qty': 'Số lượng', 'Quantity': 'Số lượng', 'OnHand': 'Tồn kho', 'StockQuantity': 'Tồn kho',
    'Total': 'Tổng tiền', 'SubTotal': 'Tiền hàng', 'Discount': 'Giảm giá', 'DiscountAmount': 'Giảm giá',
    'PaidAmount': 'Đã trả', 'Amount': 'Số tiền', 'BalanceDue': 'Còn nợ', 'VatAmount': 'Thuế VAT',
    'Status': 'Trạng thái', 'Note': 'Ghi chú', 'LineNote': 'Ghi chú dòng', 'Reason': 'Lý do',
    'Phone': 'Điện thoại', 'PhoneNumber': 'Điện thoại', 'Email': 'Email', 'Address': 'Địa chỉ',
    'CustomerId': 'Khách hàng', 'CustomerName': 'Tên khách', 'ProductId': 'Hàng hóa', 'ProductName': 'Tên hàng',
    'CategoryId': 'Nhóm hàng', 'UnitName': 'Đơn vị tính', 'IsActive': 'Đang dùng', 'IsDefault': 'Mặc định',
    'PaymentMethod': 'Hình thức thanh toán', 'SaleDate': 'Ngày bán', 'OrderNo': 'Số hóa đơn',
    'EmployeeId': 'Nhân viên', 'DepartmentId': 'Phòng ban', 'Salary': 'Lương', 'BaseSalary': 'Lương cơ bản',
    'StartDate': 'Từ ngày', 'EndDate': 'Đến ngày', 'AttendanceTime': 'Giờ chấm', 'Role': 'Vai trò',
    'Value': 'Giá trị', 'Key': 'Mã cài đặt', 'Title': 'Tiêu đề', 'Description': 'Mô tả',
    'Password': 'Mật khẩu', 'PlainTextPassword': 'Mật khẩu', 'PasswordHash': 'Mật khẩu',
  };
  final known = map[field];
  if (known != null) return known;
  return field.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
}
