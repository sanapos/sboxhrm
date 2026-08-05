import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/navigation_notifier.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/page_top_actions.dart';
import 'business_trip_case_detail_screen.dart';
import '../utils/responsive_helper.dart';
import 'business_trip_categories_screen.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

const _theme = HrmPageChrome.primaryNavy;

List<Map<String, dynamic>> _parseCaseItems(dynamic data) {
  dynamic raw;
  if (data is Map) {
    raw = data['items'] ?? data['Items'];
  } else if (data is List) {
    raw = data;
  }
  if (raw is! List) return [];
  return raw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
}

String _avatarCode(dynamic code) {
  final s = (code ?? '?').toString().trim();
  if (s.isEmpty) return '?';
  return s.length >= 2 ? s.substring(0, 2) : s;
}

String _apiErrorMessage(Map<String, dynamic> res) {
  final msg = res['message']?.toString();
  if (msg != null && msg.trim().isNotEmpty) return msg.trim();
  final detail = res['detail']?.toString();
  if (detail != null && detail.trim().isNotEmpty) return detail.trim();
  return 'Đã xảy ra lỗi. Vui lòng thử lại.';
}

double _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

class BusinessTripExpenseScreen extends StatefulWidget {
  const BusinessTripExpenseScreen({super.key});

  @override
  State<BusinessTripExpenseScreen> createState() =>
      _BusinessTripExpenseScreenState();
}

class _BusinessTripExpenseScreenState extends State<BusinessTripExpenseScreen> {
  final ApiService _api = ApiService();
  final _currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');
  final _dateFmt = DateFormat('dd/MM/yyyy');
  List<Map<String, dynamic>> _cases = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _employees = [];
  bool _loading = true;
  bool _filtersExpanded = false;
  String? _loadError;

  DateTime? _fromDate;
  DateTime? _toDate;
  String? _employeeUserId;
  String? _categoryId;
  int? _statusFilter;

  @override
  void initState() {
    super.initState();
    _bootstrap().then((_) async {
      await _openHighlightedCase();
      if (!mounted) return;
      if (NavigationNotifier.takePendingAiOpenCreate('business_trip')) {
        await _openCreate();
      }
    });
  }

  Future<void> _openHighlightedCase() async {
    final id = NavigationNotifier.notificationHighlightId.value;
    if (id == null || id.isEmpty || !mounted) return;
    NavigationNotifier.notificationHighlightId.value = null;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BusinessTripCaseDetailScreen(caseId: id),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await _api.seedBusinessTripExpenseCategories();
      final catRes = await _api.getBusinessTripExpenseCategories();
      if (catRes['isSuccess'] == true && catRes['data'] is List) {
        _categories = (catRes['data'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
          ..sort((a, b) => ((a['sortOrder'] as num?)?.toInt() ?? 0)
              .compareTo((b['sortOrder'] as num?)?.toInt() ?? 0));
      }
      final perms = Provider.of<PermissionProvider>(context, listen: false);
      final isManagerish = perms.canApprove('BusinessTripExpense') ||
          perms.canEdit('BusinessTripExpense');
      if (isManagerish) {
        final emps = await _api.getEmployeesForSelect(pageSize: 200);
        _employees = emps
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
      await _loadCases();
    } catch (e) {
      if (!mounted) return;
      _loadError = 'Lỗi tải: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCases() async {
    final res = await _api.getBusinessTripCases(
      pageSize: 100,
      employeeUserId: _employeeUserId,
      status: _statusFilter,
      fromDate: _fromDate,
      toDate: _toDate,
      categoryId: _categoryId,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      _cases = _parseCaseItems(res['data']);
      _loadError = null;
    } else {
      _cases = [];
      _loadError = _apiErrorMessage(res);
    }
    setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await _loadCases();
    } catch (e) {
      _loadError = 'Lỗi tải danh sách: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _clearFilters() {
    setState(() {
      _fromDate = null;
      _toDate = null;
      _employeeUserId = null;
      _categoryId = null;
      _statusFilter = null;
    });
    _load();
  }

  bool get _hasFilters =>
      _fromDate != null ||
      _toDate != null ||
      _employeeUserId != null ||
      _categoryId != null ||
      _statusFilter != null;

  bool _canCreate(BuildContext ctx) =>
      Provider.of<PermissionProvider>(ctx, listen: false)
          .canCreate('BusinessTripExpense');

  bool _canManageCategories(BuildContext ctx) =>
      Provider.of<PermissionProvider>(ctx, listen: false)
          .canEdit('BusinessTripExpense');

  Future<void> _pickFilterDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _fromDate : _toDate) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
  }

  Future<void> _openCreate() async {
    final createdId = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const _BusinessTripCreateScreen()),
    );
    if (!mounted) return;
    await _load();
    if (createdId != null && createdId.isNotEmpty && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BusinessTripCaseDetailScreen(caseId: createdId),
        ),
      );
      _load();
    }
  }

  Future<void> _openDetail(Map<String, dynamic> item) async {
    final id = item['id']?.toString();
    if (id == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BusinessTripCaseDetailScreen(caseId: id),
      ),
    );
    _load();
  }

  Future<void> _openCategories() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const BusinessTripCategoriesScreen()),
    );
    final catRes = await _api.getBusinessTripExpenseCategories();
    if (!mounted) return;
    if (catRes['isSuccess'] == true && catRes['data'] is List) {
      setState(() {
        _categories = (catRes['data'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    }
  }

  String _employeeLabel(Map<String, dynamic> e) {
    final code = e['employeeCode']?.toString() ?? '';
    final name = '${e['lastName'] ?? ''} ${e['firstName'] ?? ''}'.trim();
    final full = e['fullName']?.toString() ?? name;
    if (code.isEmpty) return full.isEmpty ? '—' : full;
    return '$code · $full';
  }

  String? _employeeUserIdOf(Map<String, dynamic> e) {
    return e['applicationUserId']?.toString() ??
        e['userId']?.toString() ??
        e['applicationUser']?['id']?.toString();
  }

  Widget _filtersCard() {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.filter_list, color: _theme),
            title: Text(tr('Bộ lọc'),
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              tr(_hasFilters
                  ? 'Đang lọc · ${_cases.length} hồ sơ'
                  : 'Theo thời gian, nhân viên, hạn mục, trạng thái'),
              style: const TextStyle(fontSize: 12),
            ),
            trailing: Icon(
                _filtersExpanded ? Icons.expand_less : Icons.expand_more),
            onTap: () =>
                setState(() => _filtersExpanded = !_filtersExpanded),
          ),
          if (_filtersExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickFilterDate(isFrom: true),
                          icon: const Icon(Icons.calendar_today, size: 16),
                          label: Text(tr(_fromDate == null
                              ? 'Từ ngày'
                              : _dateFmt.format(_fromDate!))),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _pickFilterDate(isFrom: false),
                          icon: const Icon(Icons.event, size: 16),
                          label: Text(tr(_toDate == null
                              ? 'Đến ngày'
                              : _dateFmt.format(_toDate!))),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_employees.isNotEmpty)
                    DropdownButtonFormField<String?>(
                      value: _employeeUserId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: tr('Nhân viên'),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                            value: null, child: Text(tr('Tất cả nhân viên'))),
                        ..._employees.map((e) {
                          final uid = _employeeUserIdOf(e);
                          return DropdownMenuItem<String?>(
                            value: uid,
                            child: Text(tr(_employeeLabel(e)),
                                overflow: TextOverflow.ellipsis),
                          );
                        }),
                      ],
                      onChanged: (v) => setState(() => _employeeUserId = v),
                    ),
                  if (_employees.isNotEmpty) const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    value: _categoryId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: tr('Hạn mục chi phí'),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                          value: null, child: Text(tr('Tất cả hạn mục'))),
                      ..._categories.map((c) => DropdownMenuItem<String?>(
                            value: c['id']?.toString(),
                            child: Text(tr(c['name']?.toString() ?? '')),
                          )),
                    ],
                    onChanged: (v) => setState(() => _categoryId = v),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int?>(
                    value: _statusFilter,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: tr('Trạng thái'),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem<int?>(
                          value: null, child: Text(tr('Tất cả trạng thái'))),
                      for (var i = 0; i <= 9; i++)
                        DropdownMenuItem<int?>(
                          value: i,
                          child: Text(tr(tripStatusLabel(i))),
                        ),
                    ],
                    onChanged: (v) => setState(() => _statusFilter = v),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (_hasFilters)
                        TextButton(
                            onPressed: _clearFilters,
                            child: Text(tr('Xóa lọc'))),
                      const Spacer(),
                      FilledButton(
                        style:
                            FilledButton.styleFrom(backgroundColor: _theme),
                        onPressed: _load,
                        child: Text(tr('Áp dụng')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _categoriesCard() {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: _theme.withValues(alpha: 0.25)),
      ),
      color: _theme.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.category_outlined, color: _theme),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr('Loại chi phí'),
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
                TextButton(
                  onPressed: _openCategories,
                  child: Text(tr(_canManageCategories(context)
                      ? 'Thêm / Sửa / Xóa'
                      : 'Xem danh mục')),
                ),
              ],
            ),
            Text(
              tr(_categories.isEmpty
                  ? 'Chưa có danh mục. Mở “Thêm / Sửa / Xóa” để khởi tạo mẫu.'
                  : 'Quản lý tên loại chi phí tại đây. Nhân viên chọn khi nhập tiền & hóa đơn.'),
              style:
                  TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.35),
            ),
            if (_categories.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _categories
                    .take(8)
                    .map(
                      (c) => ActionChip(
                        avatar: Icon(
                          c['requiresInvoice'] == true
                              ? Icons.receipt_long
                              : Icons.payments_outlined,
                          size: 16,
                          color: _theme,
                        ),
                        label: Text(tr(c['name']?.toString() ?? '')),
                        onPressed: () {
                          setState(() {
                            _categoryId = c['id']?.toString();
                            _filtersExpanded = true;
                          });
                          _load();
                        },
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final canCreate = _canCreate(context);

    return RegisterPageTopActions(
      actions: [
        HrmTopBarAction(
          icon: Icons.category_outlined,
          label: 'Loại chi phí',
          onPressed: _openCategories,
        ),
        HrmTopBarAction(
          icon: Icons.refresh,
          label: 'Tải lại',
          onPressed: _loading ? null : _load,
        ),
        if (canCreate && !isMobile)
          HrmTopBarAction(
            icon: Icons.add,
            label: 'Hồ sơ mới',
            primary: true,
            showLabel: true,
            onPressed: _openCreate,
          ),
      ],
      child: Scaffold(
      backgroundColor: HrmPageChrome.background,
      floatingActionButton: canCreate && isMobile
          ? FloatingActionButton.extended(
              backgroundColor: _theme,
              onPressed: _openCreate,
              icon: const Icon(Icons.add),
              label: Text(tr('Hồ sơ mới')),
            )
          : null,
      body: _loading
          ? const LoadingWidget()
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline,
                            size: 48, color: Colors.red.shade400),
                        const SizedBox(height: 12),
                        Text(tr(_loadError!), textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                            onPressed: _load, child: Text(tr('Thử lại'))),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: _filtersCard()),
                      SliverToBoxAdapter(child: _categoriesCard()),
                      if (_cases.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: EmptyState(
                            icon: Icons.flight_takeoff,
                            title: 'Chưa có hồ sơ công tác',
                            description: _canCreate(context)
                                ? 'Tạo hồ sơ mới rồi chọn loại chi phí, nhập số tiền và phân loại hóa đơn/giấy tờ.'
                                : 'Bạn chưa có quyền tạo hồ sơ công tác',
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
                          sliver: SliverList.separated(
                            itemCount: _cases.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (ctx, i) {
                              final c = _cases[i];
                              final advance = _asDouble(c['advanceAmount']);
                              final settled = _asDouble(c['settledAmount']);
                              final status = parseTripStatus(c['status']);
                              final stColor = tripStatusColor(status);
                              final isCancelled = status == 9;
                              return Card(
                                elevation: 0,
                                color: isCancelled
                                    ? const Color(0xFFFEF2F2)
                                    : null,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: isCancelled
                                        ? const Color(0xFFFECACA)
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor:
                                        stColor.withValues(alpha: 0.15),
                                    foregroundColor: stColor,
                                    child: Text(tr(_avatarCode(c['caseCode']))),
                                  ),
                                  title: Text(
                                    tr(c['title']?.toString() ?? '—'),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      decoration: isCancelled
                                          ? TextDecoration.lineThrough
                                          : null,
                                      color: isCancelled
                                          ? const Color(0xFF991B1B)
                                          : null,
                                    ),
                                  ),
                                  subtitle: Text(
                                    tr([
                                      if ((c['employeeName']?.toString() ?? '')
                                              .trim()
                                              .isNotEmpty ||
                                          (c['employeeCode']?.toString() ?? '')
                                              .trim()
                                              .isNotEmpty)
                                        [
                                          if ((c['employeeCode']?.toString() ??
                                                  '')
                                              .trim()
                                              .isNotEmpty)
                                            c['employeeCode'],
                                          if ((c['employeeName']?.toString() ??
                                                  '')
                                              .trim()
                                              .isNotEmpty)
                                            c['employeeName'],
                                        ].join(' · '),
                                      '${c['caseCode'] ?? ''} · ${tripStatusLabel(status)}',
                                      'Ứng: ${_currency.format(advance)} · HT: ${_currency.format(settled)}',
                                      if (!isCancelled)
                                        'Chạm để nhập chi phí / hóa đơn',
                                    ].where((e) => e.toString().trim().isNotEmpty).join('\n')),
                                  ),
                                  isThreeLine: true,
                                  trailing: isCancelled
                                      ? Text(tr('Hủy'),
                                          style: TextStyle(
                                            color: stColor,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12,
                                          ),
                                        )
                                      : const Icon(Icons.chevron_right),
                                  onTap: () => _openDetail(c),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
    ),
    );
  }
}

/// Màn tạo hồ sơ full-screen.
class _BusinessTripCreateScreen extends StatefulWidget {
  const _BusinessTripCreateScreen();

  @override
  State<_BusinessTripCreateScreen> createState() =>
      _BusinessTripCreateScreenState();
}

class _BusinessTripCreateScreenState extends State<_BusinessTripCreateScreen> {
  final ApiService _api = ApiService();
  final _dateFmt = DateFormat('dd/MM/yyyy');
  final _titleCtrl = TextEditingController();
  final _destCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _saving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _destCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isFrom) async {
    final current = isFrom ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      appNotification.showError(
        title: 'Thiếu thông tin',
        message: tr('Vui lòng nhập tiêu đề hồ sơ công tác'),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final res = await _api.createBusinessTripCase({
        'title': title,
        if (_destCtrl.text.trim().isNotEmpty)
          'destination': _destCtrl.text.trim(),
        if (_noteCtrl.text.trim().isNotEmpty) 'note': _noteCtrl.text.trim(),
        if (_fromDate != null) 'tripFromDate': _fromDate!.toIso8601String(),
        if (_toDate != null) 'tripToDate': _toDate!.toIso8601String(),
      });
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        final data = res['data'];
        final id = data is Map ? data['id']?.toString() : null;
        appNotification.showSuccess(
          title: 'Thành công',
          message: tr('Đã tạo hồ sơ — tiếp tục nhập chi phí'),
        );
        Navigator.pop(context, id);
      } else {
        appNotification.showError(
          title: 'Lỗi',
          message: _apiErrorMessage(res),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _dec(String label, {String? hint, IconData? icon}) {
    return InputDecoration(
      labelText: tr(label),
      hintText: trN(hint),
      prefixIcon: icon != null ? Icon(icon, color: _theme) : null,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _theme, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(tr('Hồ sơ công tác mới')),
        backgroundColor: _theme,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _theme.withValues(alpha: 0.12),
                        _theme.withValues(alpha: 0.04),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _theme.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.flight_takeoff, color: _theme),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(tr('Sau khi tạo, chọn loại chi phí (tiền ăn, xe, nhà nghỉ…), nhập số tiền và phân loại hóa đơn VAT / bán hàng / không giấy tờ.'),
                          style: TextStyle(fontSize: 13, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _titleCtrl,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: _dec('Tiêu đề *',
                      hint: 'VD: Công tác Hà Nội tuần 28',
                      icon: Icons.title),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _destCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: _dec('Điểm đến',
                      hint: 'VD: Hà Nội', icon: Icons.place_outlined),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => _pickDate(true),
                        icon: const Icon(Icons.calendar_today, size: 18),
                        label: Text(
                          tr(_fromDate == null
                              ? 'Từ ngày'
                              : _dateFmt.format(_fromDate!)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => _pickDate(false),
                        icon: const Icon(Icons.event, size: 18),
                        label: Text(
                          tr(_toDate == null
                              ? 'Đến ngày'
                              : _dateFmt.format(_toDate!)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _noteCtrl,
                  maxLines: 3,
                  decoration: _dec('Ghi chú', icon: Icons.notes_outlined),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _saving ? null : () => Navigator.pop(context),
                      child: Text(tr('Hủy')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: _theme,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _saving ? null : _submit,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.arrow_forward),
                      label: Text(tr(_saving ? 'Đang tạo…' : 'Tạo & nhập chi phí')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
