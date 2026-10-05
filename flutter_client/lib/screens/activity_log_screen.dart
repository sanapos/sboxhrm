import 'dart:async';
import '../utils/export_permission_guard.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_tr.dart';
import '../services/api_service.dart';
import '../utils/file_saver.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/page_top_actions.dart';

import '../theme/sbox_tokens.dart';

/// Lịch sử thao tác của cửa hàng (30 ngày): ai thêm / sửa / xóa gì, lúc nào, ở chức năng nào.
class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _hm = DateFormat('HH:mm');
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
    if (!ensureCanExport(context, 'ActivityLog')) return;
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
    // Xuất Excel đăng ký vào thanh thao tác chung: điện thoại → nút nổi góc dưới phải, máy tính → thanh trên.
    return RegisterPageTopActions(
      actions: [
        HrmTopBarAction(
          icon: Icons.file_download_outlined,
          label: 'Xuất Excel',
          onPressed: _loading ? null : _export,
        ),
      ],
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F7F9),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildFilterBar(wide),
            _buildSummary(),
            Expanded(child: _buildList()),
          ],
        ),
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
        DropdownMenuItem(value: null, child: Text(tr('Mọi người'))),
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
        DropdownMenuItem(value: null, child: Text(tr('Mọi chức năng'))),
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
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tiêu đề đã ở thanh trên của app — chỉ giữ bộ lọc thời gian.
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
        fillColor: SboxColors.slate50,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: SboxColors.slate200)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: SboxColors.slate200)),
      );

  /// Tổng / Thêm / Sửa / Xóa — bấm để lọc loại thao tác (thay cụm nút chọn cũ quá rộng trên điện thoại).
  Widget _buildSummary() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _stat('Tất cả', _total, SboxColors.slate700, null),
                _stat('Thêm', _creates, SboxColors.success, 'Create'),
                _stat('Sửa', _updates, SboxColors.warning, 'Update'),
                _stat('Xóa', _deletes, SboxColors.danger, 'Delete'),
              ]),
            ),
          ),
          const SizedBox(width: 6),
          Text(tr('Lưu 30 ngày'), style: const TextStyle(fontSize: 11.5, color: SboxColors.slate400)),
        ]),
      );

  Widget _stat(String label, int n, Color c, String? action) {
    final selected = _action == action;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: selected ? c.withOpacity(.10) : Colors.white,
        shape: StadiumBorder(side: BorderSide(color: selected ? c : SboxColors.slate200, width: selected ? 1.4 : 1)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () {
            if (_action == action) return;
            setState(() => _action = action);
            _applyFilters();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${tr(label)} ', style: const TextStyle(color: SboxColors.slate600, fontSize: 13)),
                TextSpan(text: '$n', style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 13)),
              ]),
              maxLines: 1,
              softWrap: false,
            ),
          ),
        ),
      ),
    );
  }

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
          Text(tr('Không có thao tác nào trong khoảng đã chọn'), style: const TextStyle(color: SboxColors.slate500)),
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

  /// Một thao tác: biểu tượng màu theo loại · người làm + giờ cùng hàng (giờ «HH:mm» canh phải, không xuống dòng)
  /// · «Thêm / Sửa / Xóa <đối tượng>» · chức năng / vai trò / thiết bị.
  /// Trước đây cột giờ cố định 64px ghi «HH:mm:ss» — chữ máy lớn là giây rớt xuống dòng.
  Widget _row(Map<String, dynamic> it, DateTime? t) {
    final (label, color, icon) = _actionStyle('${it['action']}');
    final name = '${it['userName'] ?? it['userEmail'] ?? tr('Không rõ')}';
    final entity = '${it['entityName'] ?? ''}'.trim();
    final meta = [
      '${it['moduleName'] ?? ''}',
      if ((it['userRole'] ?? '').toString().isNotEmpty) '${it['userRole']}',
      if ((it['device'] ?? '').toString().isNotEmpty) '${it['device']}',
    ].where((x) => x.trim().isNotEmpty).join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SboxColors.slate200),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showDetail(it),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: color.withOpacity(.12), shape: BoxShape.circle),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, color: SboxColors.slate900, fontSize: 14)),
                    ),
                    const SizedBox(width: 8),
                    Text(t == null ? '' : _hm.format(t),
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                            fontFeatures: [FontFeature.tabularFigures()],
                            color: SboxColors.slate500,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${tr(label)} ', style: TextStyle(color: color, fontWeight: FontWeight.w700)),
                      TextSpan(text: entity.isEmpty ? tr('(không tên)') : entity, style: const TextStyle(color: SboxColors.slate800)),
                    ]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, height: 1.3),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(tr(meta),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: SboxColors.slate400)),
                  ],
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  (String, Color, IconData) _actionStyle(String a) => switch (a) {
        'Create' => ('Thêm', SboxColors.success, Icons.add),
        'Delete' => ('Xóa', SboxColors.danger, Icons.delete_outline),
        _ => ('Sửa', SboxColors.warning, Icons.edit_outlined),
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
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Center(
              child: Container(width: 40, height: 4,
                  decoration: BoxDecoration(color: SboxColors.slate300, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(14)),
                child: Text(tr(label), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${it['entityName'] ?? ''}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), maxLines: 2),
              ),
            ]),
            const SizedBox(height: 12),
            _kv(tr('Người thao tác'), '${it['userName'] ?? ''} ${it['userEmail'] == null ? '' : '(${it['userEmail']})'}'),
            _kv(tr('Vai trò'), '${it['userRole'] ?? ''}'),
            _kv(tr('Thời gian'), t == null ? '' : DateFormat('dd/MM/yyyy HH:mm:ss').format(t)),
            _kv(tr('Chức năng'), '${it['moduleName'] ?? ''}'),
            _kv(tr('Thiết bị'), '${it['device'] ?? ''}${(it['ipAddress'] ?? '').toString().isEmpty ? '' : ' · IP ${it['ipAddress']}'}'),
            const Divider(height: 24),
            if (changes.isEmpty)
              Text(tr('Không có chi tiết thay đổi.'), style: const TextStyle(color: SboxColors.slate500))
            else
              for (final c in changes) _changeBlock(c),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 108, child: Text(k, style: const TextStyle(color: SboxColors.slate500, fontSize: 13))),
          Expanded(child: Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _changeBlock(Map c) {
    final (label, color, _) = _actionStyle('${c['op'] == 'Create' ? 'Create' : c['op'] == 'Delete' ? 'Delete' : 'Update'}');
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
        for (final f in fields)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${f['fieldName'] ?? activityFieldLabel('${f['field']}')}',
                  style: const TextStyle(fontSize: 12.5, color: SboxColors.slate500, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, runSpacing: 2, children: [
                if (c['op'] != 'Create')
                  SelectableText(f['old'] == null ? '—' : '${f['old']}',
                      style: const TextStyle(fontSize: 13.5, color: SboxColors.dangerText,
                          decoration: TextDecoration.lineThrough)),
                if (c['op'] != 'Create' && c['op'] != 'Delete')
                  const Icon(Icons.arrow_forward, size: 14, color: SboxColors.slate400),
                if (c['op'] != 'Delete')
                  SelectableText(f['new'] == null ? '—' : '${f['new']}',
                      style: const TextStyle(fontSize: 13.5, color: SboxColors.payHover, fontWeight: FontWeight.w600)),
              ]),
            ]),
          ),
      ]),
    );
  }

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
