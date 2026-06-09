import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../models/cash_transaction.dart';
import '../utils/report_screen_helpers.dart';
import '../utils/report_access_utils.dart';
import '../utils/cash_report_helpers.dart';
import '../providers/auth_provider.dart';
import '../utils/api_datetime.dart';
import '../utils/vietnamese_text_fix.dart';

const _cRowH = 54.0;
const _cHdrH = 44.0;
const _cStickyW = 168.0;
const _cTheme = Color(0xFF0EA5E9);

class CashReportScreen extends StatefulWidget {
  const CashReportScreen({super.key});
  @override
  State<CashReportScreen> createState() => _CashReportScreenState();
}

class _CashReportScreenState extends State<CashReportScreen> {
  final ApiService _api = ApiService();
  final _fmtDate = DateFormat('dd/MM/yyyy');
  final _fmtMoney = NumberFormat('#,##0', 'vi_VN');

  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  String _datePreset = 'this_month';
  int? _typeFilter;
  String? _statusFilter;
  String? _categoryFilter;
  int? _amountMinFilter;
  bool _filtersExpanded = false;
  bool _loading = false;
  String? _loadError;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _categories = [];
  CashReportSummary _summary = const CashReportSummary();
  String _empSearch = '';
  Map<String, double> _runningBalances = {};
  final _listSectionKey = GlobalKey();

  List<Map<String, dynamic>> get _filtered {
    Iterable<Map<String, dynamic>> rows = _items.where(
        (t) => cashReportInDateRange(t, _from, _to));
    if (_typeFilter != null) {
      rows = rows.where((t) => cashReportRowType(t).value == _typeFilter);
    }
    if (_statusFilter != null && _statusFilter!.isNotEmpty) {
      rows = rows.where((t) => cashReportMatchesStatusFilter(t, _statusFilter));
    }
    if (_categoryFilter != null && _categoryFilter!.isNotEmpty) {
      rows = rows.where(
          (t) => cashReportMatchesCategoryFilter(t, _categoryFilter));
    }
    if (_amountMinFilter != null) {
      rows = rows.where(
          (t) => cashReportMatchesAmountFilter(t, _amountMinFilter));
    }
    if (_empSearch.isNotEmpty) {
      final q = _empSearch.toLowerCase();
      rows = rows.where((t) =>
          (t['createdByUserName']?.toString() ?? '')
              .toLowerCase()
              .contains(q) ||
          (t['transactionCode']?.toString() ?? '')
              .toLowerCase()
              .contains(q) ||
          (t['description']?.toString() ?? '').toLowerCase().contains(q));
    }
    return rows.toList();
  }

  int get _clientFilterCount {
    var n = 0;
    if (_statusFilter != null) n++;
    if (_categoryFilter != null) n++;
    if (_amountMinFilter != null) n++;
    if (_empSearch.isNotEmpty) n++;
    return n;
  }

  List<Map<String, dynamic>> get _categoryOptions {
    final seen = <String, String>{};
    for (final c in _categories) {
      final id = c['id']?.toString() ?? '';
      final name = fixVietnameseMojibake(c['name']?.toString() ?? '');
      if (name.isEmpty) continue;
      seen[id.isNotEmpty ? id : name] = name;
    }
    for (final t in _items) {
      final name = fixVietnameseMojibake(t['categoryName']?.toString() ?? '');
      if (name.isEmpty) continue;
      final id = t['categoryId']?.toString() ?? '';
      seen[id.isNotEmpty ? id : name] = name;
    }
    final out = seen.entries
        .map((e) => {'key': e.key, 'name': e.value})
        .toList();
    out.sort((a, b) =>
        (a['name'] as String).compareTo(b['name'] as String));
    return out;
  }

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _load();
  }

  Future<void> _loadCategories() async {
    try {
      final r = await _api.getTransactionCategories();
      if (!mounted) return;
      if (r['isSuccess'] == true && r['data'] is List) {
        final raw = r['data'] as List;
        final flat = <Map<String, dynamic>>[];
        void walk(List list) {
          for (final item in list) {
            if (item is! Map) continue;
            final m = Map<String, dynamic>.from(item);
            flat.add(m);
            final subs = m['subCategories'];
            if (subs is List && subs.isNotEmpty) walk(subs);
          }
        }
        walk(raw);
        setState(() => _categories = flat);
      }
    } catch (_) {}
  }

  void _onDateChanged(DateTime f, DateTime t, String p) {
    setState(() {
      _from = f;
      _to = t;
      _datePreset = p;
    });
    _load();
  }

  void _onTypeChanged(int? v) {
    setState(() => _typeFilter = v);
    _load();
  }

  void _applyStatusFilter(String? filter) {
    setState(() => _statusFilter = filter);
    _scrollToList();
  }

  void _clearClientFilters() {
    setState(() {
      _statusFilter = null;
      _categoryFilter = null;
      _amountMinFilter = null;
      _empSearch = '';
    });
  }

  void _scrollToList() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _listSectionKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  List<String> get _empSuggestions => _items
      .map((t) => t['createdByUserName']?.toString() ?? '')
      .where((n) => n.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final perm = Provider.of<PermissionProvider>(context, listen: false);
      final useReportApi = shouldUseCashReportApi(
        role: auth.user?.role,
        perm: perm,
      );
      final rangeStart = apiReportRangeStart(_from);
      final rangeEnd = apiReportRangeEnd(_to);
      final result = await loadCashReportTransactions(
        _api,
        from: rangeStart,
        to: rangeEnd,
        typeFilter: _typeFilter,
        useReportApi: useReportApi,
      );

      final periodItems = result.items
          .where((t) => cashReportInDateRange(t, _from, _to))
          .toList();
      final summary = CashReportSummary.fromRows(periodItems);

      if (mounted) {
        setState(() {
          _items = periodItems;
          _summary = summary;
          _runningBalances = cashReportRunningBalances(periodItems);
          _loadError = result.error;
        });
      }
    } catch (e) {
      debugPrint('cash_report _load error: $e');
      if (mounted) {
        setState(() => _loadError = 'Không tải được báo cáo thu chi: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportExcel() async {
    final data = _filtered;
    final rows = <List<dynamic>>[];
    for (int i = 0; i < data.length; i++) {
      final t = data[i];
      final date = cashReportRowDate(t);
      final type = cashReportRowType(t);
      final st = cashReportRowStatus(t);
      final bal = _runningBalances[t['id']?.toString() ?? ''];
      rows.add([
        i + 1,
        t['transactionCode']?.toString() ?? '',
        fixVietnameseMojibake(t['categoryName']?.toString() ?? ''),
        type.label,
        date != null ? _fmtDate.format(date) : '',
        cashReportRowAmount(t),
        st.label,
        bal != null ? bal : '',
        t['description']?.toString() ?? '',
        _paymentLabel(t['paymentMethod']),
        t['createdByUserName']?.toString() ?? '',
      ]);
    }
    await ClientExcelExport.export(
      context: context,
      title: 'Báo cáo thu chi',
      sheetName: 'Bao cao thu chi',
      filePrefix: 'BaoCaoThuChi',
      headers: const [
        'STT',
        'Mã GD',
        'Danh mục',
        'Loại',
        'Ngày',
        'Số tiền (đ)',
        'Trạng thái',
        'Số dư quỹ',
        'Mô tả',
        'Phương thức',
        'Người tạo',
      ],
      rows: rows,
      periodLabel: '${_fmtDate.format(_from)} – ${_fmtDate.format(_to)}',
      summaryLines: [
        'Đã thu: ${_fmtMoney.format(_summary.paidIncome)} đ',
        'Đã chi: ${_fmtMoney.format(_summary.paidExpense)} đ',
        'Số dư quỹ: ${_fmtMoney.format(_summary.fundBalance)} đ',
        'Chờ thu: ${_fmtMoney.format(_summary.pendingIncome)} đ',
        'Chờ chi: ${_fmtMoney.format(_summary.pendingExpense)} đ',
      ],
    );
  }

  String _paymentLabel(dynamic v) {
    final val = (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 1;
    try {
      return PaymentMethodType.fromValue(val).label;
    } catch (_) {
      return v?.toString() ?? '';
    }
  }

  Color _typeColor(CashTransactionType type) =>
      type == CashTransactionType.income
          ? const Color(0xFF16A34A)
          : const Color(0xFFDC2626);

  Color _statusColor(Map<String, dynamic> row) {
    if (cashReportRowIsCancelled(row)) return const Color(0xFF9CA3AF);
    if (cashReportRowIsPending(row)) return const Color(0xFFF59E0B);
    return const Color(0xFF16A34A);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('Báo cáo thu chi'),
        backgroundColor: _cTheme,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (Provider.of<PermissionProvider>(context, listen: false)
              .canExport('CashReport'))
            IconButton(
                icon: const Icon(Icons.file_download_outlined),
                tooltip: 'Xuất Excel',
                onPressed: _exportExcel),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildFilters(),
                reportLoadErrorBanner(_loadError),
                _buildSummary(),
                _buildFilterResultBar(),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  KeyedSubtree(
                    key: _listSectionKey,
                    child: _buildListSection(),
                  ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildFilters() {
    final cats = _categoryOptions;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReportDateRangeFilterBar(
            from: _from,
            to: _to,
            preset: _datePreset,
            compact: true,
            onChanged: _onDateChanged,
          ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: _filtersExpanded,
              onExpansionChanged: (v) => setState(() => _filtersExpanded = v),
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              title: Row(
                children: [
                  const Icon(Icons.tune, size: 18, color: Color(0xFF6B7280)),
                  const SizedBox(width: 6),
                  const Text('Bộ lọc',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  if (_clientFilterCount > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: _cTheme.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('$_clientFilterCount',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _cTheme)),
                    ),
                  ],
                  const Spacer(),
                  Text('${_filtered.length}/${_items.length}',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _filterDrop<int?>(
                      width: 108,
                      label: 'Loại',
                      value: _typeFilter,
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Tất cả')),
                        DropdownMenuItem(value: 1, child: Text('Thu')),
                        DropdownMenuItem(value: 2, child: Text('Chi')),
                      ],
                      onChanged: _onTypeChanged,
                    ),
                    _filterDrop<String?>(
                      width: 148,
                      label: 'Danh mục',
                      value: _categoryFilter,
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('Tất cả')),
                        ...cats.map((c) => DropdownMenuItem(
                              value: c['key'] as String,
                              child: Text(c['name'] as String,
                                  overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (v) => setState(() => _categoryFilter = v),
                    ),
                    _filterDrop<String?>(
                      width: 148,
                      label: 'Trạng thái',
                      value: _statusFilter,
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Tất cả')),
                        DropdownMenuItem(
                            value: 'paid_income', child: Text('Đã thu')),
                        DropdownMenuItem(
                            value: 'paid_expense', child: Text('Đã chi')),
                        DropdownMenuItem(
                            value: 'pending_income', child: Text('Chờ thu')),
                        DropdownMenuItem(
                            value: 'pending_expense', child: Text('Chờ chi')),
                        DropdownMenuItem(
                            value: 'pending', child: Text('Chờ thanh toán')),
                        DropdownMenuItem(
                            value: 'completed', child: Text('Đã vào/ra quỹ')),
                        DropdownMenuItem(
                            value: 'cancelled', child: Text('Đã hủy')),
                      ],
                      onChanged: (v) => _applyStatusFilter(v),
                    ),
                    _filterDrop<int?>(
                      width: 132,
                      label: 'Giá trị',
                      value: _amountMinFilter,
                      items: const [
                        DropdownMenuItem(value: null, child: Text('Tất cả')),
                        DropdownMenuItem(
                            value: CashReportAmountThresholds.oneMillion,
                            child: Text('≥ 1 triệu')),
                        DropdownMenuItem(
                            value: CashReportAmountThresholds.fiveMillion,
                            child: Text('≥ 5 triệu')),
                        DropdownMenuItem(
                            value: CashReportAmountThresholds.tenMillion,
                            child: Text('≥ 10 triệu')),
                        DropdownMenuItem(
                            value: CashReportAmountThresholds.fiftyMillion,
                            child: Text('≥ 50 triệu')),
                      ],
                      onChanged: (v) => setState(() => _amountMinFilter = v),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildEmpSearch('Người tạo / mã / mô tả...'),
                if (_clientFilterCount > 0)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _clearClientFilters,
                      icon: const Icon(Icons.filter_alt_off, size: 16),
                      label: const Text('Xóa bộ lọc',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterDrop<T>({
    required double width,
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return SizedBox(
      width: width,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 11),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            isDense: true,
            style: const TextStyle(fontSize: 12, color: Color(0xFF111827)),
            icon: const Icon(Icons.keyboard_arrow_down,
                size: 18, color: Color(0xFF9CA3AF)),
            items: items,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  Widget _buildFilterResultBar() {
    if (_clientFilterCount == 0 && _typeFilter == null) {
      return const SizedBox.shrink();
    }
    final parts = <String>[];
    if (_typeFilter == 1) parts.add('Thu');
    if (_typeFilter == 2) parts.add('Chi');
    if (_statusFilter != null) {
      parts.add(cashReportStatusFilterLabel(_statusFilter!));
    }
    if (_categoryFilter != null) {
      var catLabel = 'Danh mục';
      for (final c in _categoryOptions) {
        if (c['key'] == _categoryFilter) {
          catLabel = c['name'] as String;
          break;
        }
      }
      parts.add(catLabel);
    }
    if (_amountMinFilter != null) {
      parts.add(cashReportAmountFilterLabel(_amountMinFilter));
    }
    if (_empSearch.isNotEmpty) parts.add('Tìm: $_empSearch');

    return Container(
      color: const Color(0xFFE0F2FE),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_filtered.length} phiếu · ${parts.join(' · ')}',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0C4A6E)),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() => _typeFilter = null);
              _clearClientFilters();
              _load();
            },
            child: const Text('Bỏ lọc', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpSearch(String hint) {
    final suggestions = _empSuggestions;
    return Autocomplete<String>(
      optionsBuilder: (textEditingValue) {
        if (suggestions.isEmpty) return const Iterable<String>.empty();
        if (textEditingValue.text.isEmpty) return suggestions;
        final q = textEditingValue.text.toLowerCase();
        return suggestions.where((s) => s.toLowerCase().contains(q));
      },
      onSelected: (selection) => setState(() => _empSearch = selection),
      fieldViewBuilder: (context, fieldCtrl, focusNode, _) {
        return Container(
          height: 40,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFD1D5DB)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: fieldCtrl,
            focusNode: focusNode,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle:
                  const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
              prefixIcon: const Icon(Icons.person_search_outlined,
                  size: 18, color: Color(0xFF9CA3AF)),
              suffixIcon: _empSearch.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        fieldCtrl.clear();
                        setState(() => _empSearch = '');
                      })
                  : null,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 0, horizontal: 4),
              border: InputBorder.none,
              isDense: true,
            ),
            onChanged: (v) => setState(() => _empSearch = v),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                children: options
                    .map((option) => InkWell(
                          onTap: () => onSelected(option),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            child: Row(children: [
                              const Icon(Icons.person_outline,
                                  size: 16, color: Color(0xFF6B7280)),
                              const SizedBox(width: 8),
                              Flexible(
                                  child: Text(option,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF111827)))),
                            ]),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummary() {
    final s = _summary;
    final period = ReportDateRangePresets.presetLabel(_datePreset);
    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(top: 1),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  size: 16, color: Color(0xFF0EA5E9)),
              const SizedBox(width: 6),
              Text('Sổ quỹ · $period',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF111827))),
              const Spacer(),
              Text('${_filtered.length}/${_items.length} dòng',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 82,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _sumCard(
                  'Đã thu',
                  '${_fmtMoney.format(s.paidIncome)}đ',
                  '${s.paidIncomeCount} GD',
                  Icons.arrow_circle_down,
                  const Color(0xFF16A34A),
                  filter: 'paid_income',
                ),
                _sumCard(
                  'Đã chi',
                  '${_fmtMoney.format(s.paidExpense)}đ',
                  '${s.paidExpenseCount} GD',
                  Icons.arrow_circle_up,
                  const Color(0xFFDC2626),
                  filter: 'paid_expense',
                ),
                _sumCard(
                  'Số dư quỹ',
                  '${_fmtMoney.format(s.fundBalance)}đ',
                  'Đã thu − Đã chi',
                  Icons.savings_outlined,
                  s.fundBalance >= 0
                      ? const Color(0xFF0284C7)
                      : const Color(0xFFDC2626),
                  filter: 'completed',
                ),
                if (s.pendingIncome > 0 || s.pendingIncomeCount > 0)
                  _sumCard(
                    'Chờ thu',
                    '${_fmtMoney.format(s.pendingIncome)}đ',
                    '${s.pendingIncomeCount} phiếu',
                    Icons.hourglass_top,
                    const Color(0xFF0D9488),
                    filter: 'pending_income',
                  ),
                if (s.pendingExpense > 0 || s.pendingExpenseCount > 0)
                  _sumCard(
                    'Chờ chi',
                    '${_fmtMoney.format(s.pendingExpense)}đ',
                    '${s.pendingExpenseCount} phiếu',
                    Icons.payments_outlined,
                    const Color(0xFFF59E0B),
                    filter: 'pending_expense',
                  ),
                if (s.cancelledCount > 0)
                  _sumCard(
                    'Đã hủy',
                    '${s.cancelledCount}',
                    'phiếu',
                    Icons.block,
                    const Color(0xFF9CA3AF),
                    filter: 'cancelled',
                  ),
              ],
            ),
          ),
          if (_statusFilter != null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                label: Text(
                    'Lọc: ${cashReportStatusFilterLabel(_statusFilter!)}',
                    style: const TextStyle(fontSize: 11)),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () => setState(() => _statusFilter = null),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sumCard(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color, {
    String? filter,
  }) {
    final selected = filter != null && _statusFilter == filter;
    return GestureDetector(
      onTap: filter == null
          ? null
          : () => _applyStatusFilter(selected ? null : filter),
      child: Container(
        width: 152,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.16) : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? color : color.withValues(alpha: 0.22),
              width: selected ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold, color: color),
                overflow: TextOverflow.ellipsis),
            Text(subtitle,
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildListSection() {
    final narrow = MediaQuery.sizeOf(context).width < 720;
    return narrow ? _buildMobileList() : _buildTable();
  }

  Widget _buildMobileList() {
    final rows = _filtered;
    if (rows.isEmpty) return _emptyListState();
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final t = rows[i];
        final type = cashReportRowType(t);
        final amt = cashReportRowAmount(t);
        final st = cashReportRowStatus(t);
        final date = cashReportRowDate(t);
        final bal = _runningBalances[t['id']?.toString() ?? ''];
        final catName =
            fixVietnameseMojibake(t['categoryName']?.toString() ?? '—');
        return ListTile(
          dense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          title: Text(catName,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Text(
            '${date != null ? _fmtDate.format(date) : '—'} · ${t['transactionCode'] ?? ''}\n${st.label}${bal != null ? ' · SD: ${_fmtMoney.format(bal)}đ' : ''}',
            style: const TextStyle(fontSize: 11, height: 1.35),
          ),
          trailing: Text(
            '${type == CashTransactionType.income ? '+' : '-'}${_fmtMoney.format(amt)}đ',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _typeColor(type)),
          ),
        );
      },
    );
  }

  Widget _emptyListState() {
    final hasFilter = _clientFilterCount > 0 || _typeFilter != null;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined,
              size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            hasFilter ? 'Không có phiếu phù hợp bộ lọc' : 'Không có dữ liệu',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          if (hasFilter) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() => _typeFilter = null);
                _clearClientFilters();
              },
              child: const Text('Xóa bộ lọc'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTable() {
    final rows = _filtered;
    if (rows.isEmpty) return _emptyListState();

    const hdrBg = Color(0xFFE0F2FE);
    const evenBg = Colors.white;
    const oddBg = Color(0xFFF9FAFB);

    Widget hCell(String t, double w) => Container(
          width: w,
          height: _cHdrH,
          color: hdrBg,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(t,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: Color(0xFF374151))),
        );

    Widget dCell(String t, double w, int i,
            {Color? textColor, bool ellipsis = true}) =>
        Container(
          width: w,
          height: _cRowH,
          color: i.isEven ? evenBg : oddBg,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(t,
              style: TextStyle(
                  fontSize: 12, color: textColor ?? const Color(0xFF374151)),
              overflow: ellipsis ? TextOverflow.ellipsis : null),
        );

    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(top: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            // ═══ STICKY: Danh mục ═══
            Container(
              width: _cStickyW,
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(2, 0))
                ],
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: _cStickyW,
                      height: _cHdrH,
                      color: hdrBg,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: const Text('Danh mục',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: Color(0xFF374151))),
                    ),
                    ...List.generate(rows.length, (i) {
                      final t = rows[i];
                      final type = cashReportRowType(t);
                      final catName = fixVietnameseMojibake(
                          t['categoryName']?.toString() ?? '—');
                      final typeColor = _typeColor(type);
                      return Container(
                        width: _cStickyW,
                        height: _cRowH,
                        color: i.isEven ? evenBg : oddBg,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(catName,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF111827)),
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 1),
                                decoration: BoxDecoration(
                                  color: typeColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: typeColor.withValues(alpha: 0.35)),
                                ),
                                child: Text(type.label,
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: typeColor)),
                              ),
                            ]),
                      );
                    }),
                  ]),
            ),
            // ═══ SCROLLABLE COLUMNS ═══
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        hCell('Mã GD', 108),
                        hCell('Ngày', 104),
                        hCell('Số tiền', 120),
                        hCell('Trạng thái', 112),
                        hCell('Số dư quỹ', 120),
                        hCell('Mô tả', 180),
                        hCell('PTTT', 100),
                      ]),
                      ...List.generate(rows.length, (i) {
                        final t = rows[i];
                        final date = cashReportRowDate(t);
                        final type = cashReportRowType(t);
                        final amt = cashReportRowAmount(t);
                        final st = cashReportRowStatus(t);
                        final bal =
                            _runningBalances[t['id']?.toString() ?? ''];
                        final balText = bal != null
                            ? '${_fmtMoney.format(bal)}đ'
                            : '—';
                        return Row(children: [
                          dCell(
                              t['transactionCode']?.toString() ?? '—', 108, i),
                          dCell(date != null ? _fmtDate.format(date) : '—', 104,
                              i),
                          dCell('${_fmtMoney.format(amt)}đ', 120, i,
                              textColor: _typeColor(type)),
                          dCell(st.label, 112, i,
                              textColor: _statusColor(t)),
                          dCell(balText, 120, i,
                              textColor: const Color(0xFF0284C7)),
                          dCell(t['description']?.toString() ?? '', 180, i),
                          dCell(_paymentLabel(t['paymentMethod']), 100, i),
                        ]);
                      }),
                    ]),
              ),
            ),
          ],
        ),
    );
  }
}
