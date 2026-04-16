import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../utils/number_formatter.dart';
import '../widgets/notification_overlay.dart';
import '../utils/responsive_helper.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';

/// Màn hình Thưởng phạt
class BonusPenaltyScreen extends StatefulWidget {
  const BonusPenaltyScreen({super.key});

  @override
  State<BonusPenaltyScreen> createState() => _BonusPenaltyScreenState();
}

class _BonusPenaltyScreenState extends State<BonusPenaltyScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabController;

  AppLocalizations get _l10n => AppLocalizations.of(context);

  bool _isLoading = false;
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _employees = [];
  int _totalCount = 0;
  int _currentPage = 1;
  int _pageSize = 20;
  final List<int> _pageSizeOptions = [20, 50, 100, 200];

  // Bộ lọc thời gian
  String _datePreset = 'thisMonth';
  DateTimeRange? _customDateRange;

  // Bộ lọc nhân viên (tìm kiếm)
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Bộ lọc loại
  String _filterType = 'all'; // all, Bonus, Penalty

  // Multi-select for batch operations
  final Set<String> _selectedIds = {};
  bool _isSelectMode = false;

  // Mobile UI state
  bool _showMobileFilters = false;
  bool _showMobileSummary = false;

  final _currencyFormat = NumberFormat('#,###', 'vi_VN');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _selectedIds.clear();
          _isSelectMode = false;
        });
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════
  // DATE RANGE HELPERS
  // ══════════════════════════════════════════════════
  DateTimeRange get _selectedDateRange {
    final now = DateTime.now();
    switch (_datePreset) {
      case 'today':
        return DateTimeRange(
            start: DateTime(now.year, now.month, now.day),
            end: DateTime(now.year, now.month, now.day, 23, 59, 59));
      case 'yesterday':
        final y = now.subtract(const Duration(days: 1));
        return DateTimeRange(
            start: DateTime(y.year, y.month, y.day),
            end: DateTime(y.year, y.month, y.day, 23, 59, 59));
      case 'thisWeek':
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        return DateTimeRange(
            start: DateTime(weekStart.year, weekStart.month, weekStart.day),
            end: DateTime(now.year, now.month, now.day, 23, 59, 59));
      case 'lastWeek':
        final thisWeekStart = now.subtract(Duration(days: now.weekday - 1));
        final lastWeekStart = thisWeekStart.subtract(const Duration(days: 7));
        final lastWeekEnd = thisWeekStart.subtract(const Duration(days: 1));
        return DateTimeRange(
            start: DateTime(
                lastWeekStart.year, lastWeekStart.month, lastWeekStart.day),
            end: DateTime(lastWeekEnd.year, lastWeekEnd.month, lastWeekEnd.day,
                23, 59, 59));
      case 'thisMonth':
        return DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: DateTime(now.year, now.month + 1, 0, 23, 59, 59));
      case 'lastMonth':
        final lastMonth = DateTime(now.year, now.month - 1, 1);
        return DateTimeRange(
            start: lastMonth,
            end: DateTime(now.year, now.month, 0, 23, 59, 59));
      case 'custom':
        if (_customDateRange != null) return _customDateRange!;
        return DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: DateTime(now.year, now.month + 1, 0, 23, 59, 59));
      default:
        return DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: DateTime(now.year, now.month + 1, 0, 23, 59, 59));
    }
  }

  // ignore: unused_element
  String get _datePresetLabel {
    switch (_datePreset) {
      case 'today':
        return 'Hôm nay';
      case 'yesterday':
        return 'Hôm qua';
      case 'thisWeek':
        return 'Tuần này';
      case 'lastWeek':
        return 'Tuần trước';
      case 'thisMonth':
        return 'Tháng này';
      case 'lastMonth':
        return 'Tháng trước';
      case 'custom':
        if (_customDateRange != null) {
          return '${DateFormat('dd/MM').format(_customDateRange!.start)} - ${DateFormat('dd/MM').format(_customDateRange!.end)}';
        }
        return 'Tùy chọn';
      default:
        return 'Tháng này';
    }
  }

  // ══════════════════════════════════════════════════
  // DATA LOADING
  // ══════════════════════════════════════════════════
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final range = _selectedDateRange;
      final empFuture = _apiService.getEmployees();
      final txFuture = _apiService.getTransactions(
        fromDate: range.start,
        toDate: range.end,
        type: _filterType == 'all' ? null : _filterType,
        page: _currentPage,
        pageSize: _pageSize,
      );
      final results = await Future.wait([empFuture, txFuture]);

      final empResult = results[0];
      final txResult = results[1];

      final employees = empResult as List<dynamic>;

      List<Map<String, dynamic>> transactions = [];
      int totalCount = 0;
      final txData = txResult as Map<String, dynamic>;
      if (txData['isSuccess'] == true) {
        final data = txData['data'];
        if (data is Map && data['items'] is List) {
          transactions = (data['items'] as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          totalCount = data['totalCount'] ?? transactions.length;
        } else if (data is List) {
          transactions = data.map((e) => Map<String, dynamic>.from(e)).toList();
          totalCount = transactions.length;
        }
      }

      if (mounted) {
        setState(() {
          _employees =
              employees.map((e) => Map<String, dynamic>.from(e)).toList();
          _transactions = transactions;
          _totalCount = totalCount;
          _isLoading = false;
          _selectedIds.clear();
        });
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ══════════════════════════════════════════════════
  // FILTERED DATA
  // ══════════════════════════════════════════════════
  List<Map<String, dynamic>> get _filteredTransactions {
    if (_searchQuery.isEmpty) return _transactions;
    final q = _searchQuery.toLowerCase();
    return _transactions.where((t) {
      final name = (t['employeeName']?.toString() ?? '').toLowerCase();
      final code = (t['employeeCode']?.toString() ?? '').toLowerCase();
      return name.contains(q) || code.contains(q);
    }).toList();
  }

  List<Map<String, dynamic>> get _bonusTransactions =>
      _filteredTransactions.where((t) => t['type'] == 'Bonus').toList();

  List<Map<String, dynamic>> get _penaltyTransactions =>
      _filteredTransactions.where((t) => t['type'] == 'Penalty').toList();

  double get _totalBonus => _bonusTransactions.fold(
      0.0, (s, t) => s + ((t['amount'] as num?)?.toDouble() ?? 0));

  double get _totalPenalty => _penaltyTransactions.fold(
      0.0, (s, t) => s + ((t['amount'] as num?)?.toDouble() ?? 0).abs());

  List<Map<String, dynamic>> get _currentTabItems =>
      _tabController.index == 0 ? _bonusTransactions : _penaltyTransactions;

  // Pending transactions for batch approve
  List<Map<String, dynamic>> get _pendingInCurrentTab =>
      _currentTabItems.where((t) => t['status'] == 'Pending').toList();

  // Approved (Completed) but not paid transactions for batch pay
  List<Map<String, dynamic>> get _approvedUnpaidInCurrentTab => _currentTabItems
      .where((t) =>
          t['status'] == 'Completed' &&
          (t['paymentMethod'] == null || t['paymentMethod'].toString().isEmpty))
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Row 1: Tabs
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: Theme.of(context).primaryColor,
              unselectedLabelColor: Colors.grey,
              indicatorWeight: 3,
              tabs: [
                Tab(
                    icon: const Icon(Icons.card_giftcard),
                    text: '${_l10n.bonus} (${_bonusTransactions.length})'),
                Tab(
                    icon: const Icon(Icons.gavel),
                    text: '${_l10n.penalty} (${_penaltyTransactions.length})'),
              ],
            ),
          ),
          // Row 2: Filters
          if (Responsive.isMobile(context)) ...[
            _buildMobileFilterToggle(),
            if (_showMobileFilters) _buildFilterBar(),
          ] else
            _buildFilterBar(),
          if (Responsive.isMobile(context)) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: InkWell(
                onTap: () => setState(() => _showMobileSummary = !_showMobileSummary),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.analytics_outlined, size: 16, color: Colors.blue.shade700),
                      const SizedBox(width: 6),
                      Text('Tổng quan', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.blue.shade700)),
                      const Spacer(),
                      Icon(_showMobileSummary ? Icons.expand_less : Icons.expand_more, size: 20, color: Colors.blue.shade700),
                    ],
                  ),
                ),
              ),
            ),
            if (_showMobileSummary) _buildSummaryCards(),
          ] else ...[
            _buildSummaryCards(),
          ],
          // Row 3: Batch action bar (when in select mode)
          if (_isSelectMode) _buildBatchActionBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildTransactionList(_bonusTransactions, isBonus: true),
                      _buildTransactionList(_penaltyTransactions,
                          isBonus: false),
                    ],
                  ),
          ),
          if (!Responsive.isMobile(context)) _buildPaginationControls(),
        ],
      ),
      floatingActionButton: Provider.of<PermissionProvider>(context, listen: false).canCreate('BonusPenalty') ? FloatingActionButton.extended(
        onPressed: () => _showCreateEditDialog(),
        icon: const Icon(Icons.add),
        label: Text(_l10n.addNew),
      ) : null,
    );
  }

  bool _hasActiveFilters() {
    return _datePreset != 'thisMonth' || _filterType != 'all' || _searchQuery.isNotEmpty;
  }

  Widget _buildMobileFilterToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => setState(() => _showMobileFilters = !_showMobileFilters),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _showMobileFilters
                    ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
                    size: 16,
                    color: _showMobileFilters ? Theme.of(context).primaryColor : Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _showMobileFilters ? 'Ẩn bộ lọc' : 'Bộ lọc',
                    style: TextStyle(
                      fontSize: 12,
                      color: _showMobileFilters ? Theme.of(context).primaryColor : Colors.grey.shade600,
                    ),
                  ),
                  if (_hasActiveFilters()) ...[
                    const SizedBox(width: 4),
                    Container(
                      width: 8, height: 8,
                      decoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Spacer(),
          Text(
            '${_currentTabItems.length} bản ghi',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final isMobile = Responsive.isMobile(context);
    final timeDropdown = SizedBox(
      width: isMobile ? null : 170,
      child: DropdownButtonFormField<String>(
        initialValue: _datePreset,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: _l10n.period,
          isDense: true,
          prefixIcon: const Icon(Icons.calendar_today, size: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        items: [
          DropdownMenuItem(value: 'today', child: Text(_l10n.today)),
          DropdownMenuItem(value: 'yesterday', child: Text(_l10n.yesterday)),
          DropdownMenuItem(value: 'thisWeek', child: Text(_l10n.thisWeek)),
          DropdownMenuItem(value: 'lastWeek', child: Text(_l10n.lastWeek)),
          DropdownMenuItem(value: 'thisMonth', child: Text(_l10n.thisMonth)),
          DropdownMenuItem(value: 'lastMonth', child: Text(_l10n.lastMonth)),
          DropdownMenuItem(value: 'custom', child: Text(_l10n.custom)),
        ],
        onChanged: (v) async {
          if (v == null) return;
          if (v == 'custom') {
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
              initialDateRange: _customDateRange ??
                  DateTimeRange(
                    start: DateTime.now().subtract(const Duration(days: 30)),
                    end: DateTime.now(),
                  ),
            );
            if (picked != null) {
              _customDateRange = picked;
              _datePreset = 'custom';
              _currentPage = 1;
              _loadData();
            }
          } else {
            _datePreset = v;
            _currentPage = 1;
            _loadData();
          }
        },
      ),
    );
    final typeDropdown = SizedBox(
      width: isMobile ? null : 130,
      child: DropdownButtonFormField<String>(
        initialValue: _filterType,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: _l10n.type,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        items: [
          DropdownMenuItem(value: 'all', child: Text(_l10n.all)),
          DropdownMenuItem(value: 'Bonus', child: Text(_l10n.bonus)),
          DropdownMenuItem(value: 'Penalty', child: Text(_l10n.penalty)),
        ],
        onChanged: (v) {
          if (v != null) {
            _filterType = v;
            _currentPage = 1;
            _loadData();
          }
        },
      ),
    );
    final searchField = SizedBox(
      width: isMobile ? null : 240,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          labelText: _l10n.searchEmployee,
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
    final selectBtn = OutlinedButton.icon(
      onPressed: () => setState(() {
        _isSelectMode = !_isSelectMode;
        if (!_isSelectMode) _selectedIds.clear();
      }),
      icon: Icon(_isSelectMode ? Icons.close : Icons.checklist, size: 18),
      label: Text(_isSelectMode ? _l10n.cancel : 'Chọn'),
      style: OutlinedButton.styleFrom(
        foregroundColor: _isSelectMode ? Colors.red : Colors.blue,
        side: BorderSide(
            color: _isSelectMode ? Colors.red.shade300 : Colors.blue.shade300),
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: timeDropdown),
                  const SizedBox(width: 8),
                  Expanded(child: typeDropdown)
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: searchField),
                  const SizedBox(width: 8),
                  selectBtn
                ]),
              ],
            )
          : Row(
              children: [
                timeDropdown,
                const SizedBox(width: 12),
                typeDropdown,
                const SizedBox(width: 12),
                searchField,
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _isSelectMode = !_isSelectMode;
                    if (!_isSelectMode) _selectedIds.clear();
                  }),
                  icon: Icon(_isSelectMode ? Icons.close : Icons.checklist,
                      size: 18),
                  label: Text(_isSelectMode ? 'Hủy chọn' : 'Chọn phiếu'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _isSelectMode ? Colors.red : Colors.blue,
                    side: BorderSide(
                        color: _isSelectMode
                            ? Colors.red.shade300
                            : Colors.blue.shade300),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildBatchActionBar() {
    final pendingSelected = _selectedIds
        .where((id) => _currentTabItems
            .any((t) => t['id']?.toString() == id && t['status'] == 'Pending'))
        .toList();
    final approvedSelected = _selectedIds
        .where((id) => _currentTabItems.any(
            (t) => t['id']?.toString() == id && t['status'] == 'Completed'))
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border(bottom: BorderSide(color: Colors.blue.shade100)),
      ),
      child: Row(
        children: [
          // Select all pending
          TextButton.icon(
            onPressed: _pendingInCurrentTab.isEmpty
                ? null
                : () => setState(() {
                      final allPendingIds = _pendingInCurrentTab
                          .map((t) => t['id']?.toString() ?? '')
                          .where((id) => id.isNotEmpty)
                          .toSet();
                      if (_selectedIds.containsAll(allPendingIds)) {
                        _selectedIds.removeAll(allPendingIds);
                      } else {
                        _selectedIds.addAll(allPendingIds);
                      }
                    }),
            icon: const Icon(Icons.select_all, size: 16),
            label: Text('Chọn chờ duyệt (${_pendingInCurrentTab.length})',
                style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),
          // Select all approved
          TextButton.icon(
            onPressed: _approvedUnpaidInCurrentTab.isEmpty
                ? null
                : () => setState(() {
                      final allApprovedIds = _approvedUnpaidInCurrentTab
                          .map((t) => t['id']?.toString() ?? '')
                          .where((id) => id.isNotEmpty)
                          .toSet();
                      if (_selectedIds.containsAll(allApprovedIds)) {
                        _selectedIds.removeAll(allApprovedIds);
                      } else {
                        _selectedIds.addAll(allApprovedIds);
                      }
                    }),
            icon: const Icon(Icons.select_all, size: 16),
            label: Text('Chọn đã duyệt (${_approvedUnpaidInCurrentTab.length})',
                style: const TextStyle(fontSize: 12)),
          ),
          const Spacer(),
          Text('Đã chọn: ${_selectedIds.length}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 16),
          // Batch approve
          if (pendingSelected.isNotEmpty && Provider.of<PermissionProvider>(context, listen: false).canApprove('BonusPenalty'))
            ElevatedButton.icon(
              onPressed: () => _batchApprove(pendingSelected),
              icon: const Icon(Icons.check_circle, size: 16),
              label: Text('Duyệt (${pendingSelected.length})'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green, foregroundColor: Colors.white),
            ),
          if (pendingSelected.isNotEmpty) const SizedBox(width: 8),
          // Batch pay
          if (approvedSelected.isNotEmpty)
            ElevatedButton.icon(
              onPressed: () => _showPaymentDialog(approvedSelected),
              icon: Icon(
                  _tabController.index == 1
                      ? Icons.receipt_long
                      : Icons.payment,
                  size: 16),
              label: Text(_tabController.index == 1
                  ? 'Thu tiền phạt (${approvedSelected.length})'
                  : 'Thanh toán (${approvedSelected.length})'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _tabController.index == 1 ? Colors.teal : Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  // Computed amounts for summary
  double get _paidBonusAmount => _bonusTransactions
      .where((t) =>
          t['status'] == 'Completed' &&
          (t['paymentMethod']?.toString() ?? '').isNotEmpty)
      .fold(0.0, (s, t) => s + ((t['amount'] as num?)?.toDouble() ?? 0));

  double get _unpaidBonusAmount => _totalBonus - _paidBonusAmount;

  double get _paidPenaltyAmount => _penaltyTransactions
      .where((t) =>
          t['status'] == 'Completed' &&
          (t['paymentMethod']?.toString() ?? '').isNotEmpty)
      .fold(0.0, (s, t) => s + ((t['amount'] as num?)?.toDouble() ?? 0).abs());

  double get _unpaidPenaltyAmount => _totalPenalty - _paidPenaltyAmount;

  Widget _buildSummaryCards() {
    final isBonus = _tabController.index == 0;

    final List<
        ({
          Color bgColor,
          Color fgColor,
          IconData icon,
          String title,
          String amount,
          String? subtitle
        })> items;
    if (isBonus) {
      items = [
        (
          bgColor: Colors.green.shade50,
          fgColor: Colors.green.shade700,
          icon: Icons.trending_up,
          title: _l10n.totalBonus,
          amount: '${_currencyFormat.format(_totalBonus)} đ',
          subtitle: '${_bonusTransactions.length} khoản'
        ),
        (
          bgColor: Colors.blue.shade50,
          fgColor: Colors.blue.shade700,
          icon: Icons.check_circle,
          title: _l10n.paid,
          amount: '${_currencyFormat.format(_paidBonusAmount)} đ',
          subtitle: null
        ),
        (
          bgColor: Colors.orange.shade50,
          fgColor: Colors.orange.shade700,
          icon: Icons.hourglass_empty,
          title: _l10n.pendingPayment,
          amount: '${_currencyFormat.format(_unpaidBonusAmount)} đ',
          subtitle: null
        ),
      ];
    } else {
      items = [
        (
          bgColor: Colors.red.shade50,
          fgColor: Colors.red.shade700,
          icon: Icons.trending_down,
          title: _l10n.totalPenalty,
          amount: '${_currencyFormat.format(_totalPenalty)} đ',
          subtitle: '${_penaltyTransactions.length} khoản'
        ),
        (
          bgColor: Colors.blue.shade50,
          fgColor: Colors.blue.shade700,
          icon: Icons.check_circle,
          title: _l10n.penaltyCollected,
          amount: '${_currencyFormat.format(_paidPenaltyAmount)} đ',
          subtitle: null
        ),
        (
          bgColor: Colors.orange.shade50,
          fgColor: Colors.orange.shade700,
          icon: Icons.hourglass_empty,
          title: _l10n.penaltyPending,
          amount: '${_currencyFormat.format(_unpaidPenaltyAmount)} đ',
          subtitle: null
        ),
      ];
    }

    Widget buildCard(int i, {bool expanded = true}) {
      final c = items[i];
      final card = Card(
        color: c.bgColor,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(c.icon, color: c.fgColor),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(c.title,
                        style: TextStyle(
                            color: c.fgColor, fontWeight: FontWeight.w600))),
              ]),
              const SizedBox(height: 8),
              Text(c.amount,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: c.fgColor)),
              if (c.subtitle != null)
                Text(c.subtitle!,
                    style: TextStyle(
                        color: c.fgColor.withValues(alpha: 0.6), fontSize: 12)),
            ],
          ),
        ),
      );
      return expanded ? Expanded(child: card) : card;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 500) {
          return Column(children: [
            for (int i = 0; i < items.length; i++)
              buildCard(i, expanded: false),
          ]);
        }
        return Row(children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            buildCard(i),
          ],
        ]);
      }),
    );
  }

  Widget _buildPaginationControls() {
    final totalPages = (_totalCount / _pageSize).ceil();
    if (totalPages <= 1 && _totalCount <= _pageSize) return const SizedBox.shrink();

    final start = _totalCount > 0 ? (_currentPage - 1) * _pageSize + 1 : 0;
    final end = (_currentPage * _pageSize).clamp(0, _totalCount);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(
            'Hiển thị $start-$end / $_totalCount',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Hiển thị:', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(width: 8),
              Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  border: Border.all(color: const Color(0xFFE4E4E7)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _pageSize,
                    isDense: true,
                    style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                    items: _pageSizeOptions.map((s) => DropdownMenuItem(value: s, child: Text('$s'))).toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() { _pageSize = v; _currentPage = 1; });
                        _loadData();
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.first_page, size: 20),
                onPressed: _currentPage > 1
                    ? () { setState(() => _currentPage = 1); _loadData(); }
                    : null,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: _currentPage > 1
                    ? () { setState(() => _currentPage--); _loadData(); }
                    : null,
                visualDensity: VisualDensity.compact,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('$_currentPage / $totalPages',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: _currentPage < totalPages
                    ? () { setState(() => _currentPage++); _loadData(); }
                    : null,
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.last_page, size: 20),
                onPressed: _currentPage < totalPages
                    ? () { setState(() => _currentPage = totalPages); _loadData(); }
                    : null,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionList(List<Map<String, dynamic>> items,
      {required bool isBonus}) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isBonus ? Icons.card_giftcard : Icons.gavel,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              isBonus ? 'Chưa có khoản thưởng nào' : 'Chưa có khoản phạt nào',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (Provider.of<PermissionProvider>(context, listen: false).canCreate('BonusPenalty'))
            ElevatedButton.icon(
              onPressed: () => _showCreateEditDialog(
                  presetType: isBonus ? 'Bonus' : 'Penalty'),
              icon: const Icon(Icons.add, size: 18),
              label: Text(isBonus ? 'Thêm thưởng' : 'Thêm phạt'),
            ),
          ],
        ),
      );
    }

    if (Responsive.isMobile(context)) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: items.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4E4E7)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _buildTxDeckItem(items[i], isBonus: isBonus),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final tx = items[index];
        final txId = tx['id']?.toString() ?? '';
        final amount = ((tx['amount'] as num?)?.toDouble() ?? 0).abs();
        final status = tx['status']?.toString() ?? 'Pending';
        final desc = tx['description']?.toString() ?? '';
        final note = tx['note']?.toString() ?? '';
        final empName = tx['employeeName']?.toString() ?? '';
        final empCode = tx['employeeCode']?.toString() ?? '';
        final date =
            DateTime.tryParse(tx['transactionDate']?.toString() ?? '') ??
                DateTime.now();
        final paymentMethod = tx['paymentMethod']?.toString() ?? '';
        final isPaid = paymentMethod.isNotEmpty;

        Color statusColor;
        String statusLabel;
        switch (status) {
          case 'Completed':
            if (isPaid) {
              statusColor = Colors.blue;
              statusLabel = isBonus ? _l10n.paid : _l10n.penaltyCollected;
            } else {
              statusColor = Colors.green;
              statusLabel = _l10n.approved;
            }
            break;
          case 'Cancelled':
            statusColor = Colors.grey;
            statusLabel = _l10n.cancelled;
            break;
          default:
            statusColor = Colors.orange;
            statusLabel = _l10n.pending;
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: _isSelectMode
                ? () {
                    setState(() {
                      if (_selectedIds.contains(txId)) {
                        _selectedIds.remove(txId);
                      } else {
                        _selectedIds.add(txId);
                      }
                    });
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header: checkbox (select mode) + avatar + tên NV + số tiền
                  Row(
                    children: [
                      if (_isSelectMode) ...[
                        Checkbox(
                          value: _selectedIds.contains(txId),
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _selectedIds.add(txId);
                            } else {
                              _selectedIds.remove(txId);
                            }
                          }),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: 4),
                      ],
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: isBonus
                            ? Colors.green.shade100
                            : Colors.red.shade100,
                        child: Icon(
                          isBonus ? Icons.card_giftcard : Icons.gavel,
                          size: 18,
                          color: isBonus
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(empName.isNotEmpty ? empName : empCode,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600))),
                      Text(
                        '${isBonus ? '+' : '-'}${_currencyFormat.format(amount)} đ',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isBonus
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Nội dung
                  if (desc.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 46),
                      child: Text(desc, style: const TextStyle(fontSize: 13)),
                    ),
                  if (note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 46),
                      child: Text(note,
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                              fontStyle: FontStyle.italic)),
                    ),
                  // Ngày + trạng thái + phương thức thanh toán
                  Padding(
                    padding: const EdgeInsets.only(left: 46, top: 4),
                    child: Row(
                      children: [
                        Text(DateFormat('dd/MM/yyyy').format(date),
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade500)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(statusLabel,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: statusColor,
                                  fontWeight: FontWeight.w600)),
                        ),
                        if (isPaid) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _paymentMethodLabel(paymentMethod),
                              style: TextStyle(
                                  fontSize: 10, color: Colors.indigo.shade700),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Divider + nút hành động
                  if (!_isSelectMode) ...[
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (status != 'Completed' && Provider.of<PermissionProvider>(context, listen: false).canEdit('BonusPenalty')) ...[
                          _ActionBtn(
                              icon: Icons.edit_rounded,
                              label: _l10n.edit,
                              color: Colors.blue,
                              onTap: () => _handleAction('edit', tx)),
                          const SizedBox(width: 6),
                        ],
                        if (status == 'Pending' && Provider.of<PermissionProvider>(context, listen: false).canApprove('BonusPenalty')) ...[
                          _ActionBtn(
                              icon: Icons.check_circle_outline,
                              label: _l10n.approveLabel,
                              color: Colors.green,
                              onTap: () => _handleAction('approve', tx)),
                          const SizedBox(width: 6),
                        ],
                        if (status == 'Completed' && !isPaid) ...[
                          _ActionBtn(
                            icon: isBonus ? Icons.payment : Icons.receipt_long,
                            label:
                                isBonus ? _l10n.payment : _l10n.collectPenalty,
                            color: isBonus ? Colors.blue : Colors.teal,
                            onTap: () => _showPaymentDialog([txId]),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (status == 'Completed' && !isPaid && Provider.of<PermissionProvider>(context, listen: false).canApprove('BonusPenalty')) ...[
                          _ActionBtn(
                              icon: Icons.undo_rounded,
                              label: _l10n.reverseApproval,
                              color: Colors.orange,
                              onTap: () => _handleAction('unapprove', tx)),
                          const SizedBox(width: 6),
                        ],
                        if (status == 'Pending' && Provider.of<PermissionProvider>(context, listen: false).canApprove('BonusPenalty')) ...[
                          _ActionBtn(
                              icon: Icons.cancel_outlined,
                              label: _l10n.cancel,
                              color: Colors.orange,
                              onTap: () => _handleAction('cancel', tx)),
                          const SizedBox(width: 6),
                        ],
                        if (Provider.of<PermissionProvider>(context, listen: false).canDelete('BonusPenalty'))
                        _ActionBtn(
                            icon: Icons.delete_forever_outlined,
                            label: _l10n.delete,
                            color: Colors.red.shade700,
                            onTap: () => _handleAction('delete', tx)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTxDeckItem(Map<String, dynamic> tx, {required bool isBonus}) {
    final txId = tx['id']?.toString() ?? '';
    final amount = ((tx['amount'] as num?)?.toDouble() ?? 0).abs();
    final status = tx['status']?.toString() ?? 'Pending';
    final empName = tx['employeeName']?.toString() ?? '';
    final empCode = tx['employeeCode']?.toString() ?? '';
    final date = DateTime.tryParse(tx['transactionDate']?.toString() ?? '') ?? DateTime.now();
    final desc = tx['description']?.toString() ?? '';

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'Completed':
        statusColor = Colors.green; statusLabel = _l10n.approved;
        break;
      case 'Cancelled':
        statusColor = Colors.grey; statusLabel = _l10n.cancelled;
        break;
      default:
        statusColor = Colors.orange; statusLabel = _l10n.pending;
    }

    return InkWell(
      onTap: _isSelectMode ? () => setState(() { _selectedIds.contains(txId) ? _selectedIds.remove(txId) : _selectedIds.add(txId); }) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          if (_isSelectMode) Checkbox(value: _selectedIds.contains(txId), onChanged: (v) => setState(() { v == true ? _selectedIds.add(txId) : _selectedIds.remove(txId); }), visualDensity: VisualDensity.compact, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
          CircleAvatar(
            radius: 18,
            backgroundColor: isBonus ? Colors.green.shade100 : Colors.red.shade100,
            child: Icon(isBonus ? Icons.card_giftcard : Icons.gavel, size: 16, color: isBonus ? Colors.green.shade700 : Colors.red.shade700),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(empName.isNotEmpty ? empName : empCode, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                [
                  if (desc.isNotEmpty) desc,
                  (DateFormat('dd/MM/yyyy').format(date)),
                ].join(' · '),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              '${isBonus ? '+' : '-'}${_currencyFormat.format(amount)} đ',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isBonus ? Colors.green.shade700 : Colors.red.shade700),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(statusLabel, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w600)),
            ),
          ]),
        ]),
      ),
    );
  }

  String _paymentMethodLabel(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return _l10n.cash;
      case 'banktransfer':
        return _l10n.bankTransfer;
      case 'vietqr':
        return 'VietQR';
      case 'card':
        return 'Thẻ';
      case 'ewallet':
        return _l10n.eWallet;
      default:
        return method;
    }
  }

  // ══════════════════════════════════════════════════
  // BATCH OPERATIONS
  // ══════════════════════════════════════════════════
  Future<void> _batchApprove(List<String> ids) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_l10n.batchApprove),
        content: Text('Bạn có chắc muốn duyệt ${ids.length} phiếu đã chọn?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_l10n.cancel)),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: Text(_l10n.approveAll),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isLoading = true);
    final result = await _apiService.bulkApproveTransactions(ids);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['isSuccess'] == true) {
      final data = result['data'];
      final s = data?['success'] ?? ids.length;
      final f = data?['failed'] ?? 0;
      _showSnackBar(
          'Đã duyệt $s/${ids.length} phiếu${f > 0 ? ' ($f lỗi)' : ''}',
          f > 0 ? Colors.orange : Colors.green);
      _loadData();
    } else {
      _showSnackBar('Lỗi: ${result['message']}', Colors.red);
    }
  }

  void _showPaymentDialog(List<String> ids) {
    String selectedMethod = 'Cash';
    final totalAmount = _currentTabItems
        .where((t) => ids.contains(t['id']?.toString()))
        .fold<double>(
            0, (s, t) => s + ((t['amount'] as num?)?.toDouble() ?? 0).abs());
    final isPenaltyTab = _tabController.index == 1;
    final dialogTitle = isPenaltyTab
        ? 'Thu tiền phạt ${ids.length} phiếu'
        : 'Thanh toán ${ids.length} phiếu';
    final amountLabel =
        isPenaltyTab ? 'Tổng tiền thu phạt' : 'Tổng tiền thanh toán';
    final noteText = isPenaltyTab
        ? 'Sẽ tạo phiếu thu trong Thu chi với tổng số tiền trên.'
        : 'Sẽ tạo phiếu chi trong Thu chi với tổng số tiền trên.';
    final btnLabel = isPenaltyTab ? 'Thu tiền' : 'Thanh toán';
    final isMobile = Responsive.isMobile(context);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final formContent = SingleChildScrollView(
            padding: isMobile ? const EdgeInsets.all(16) : EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.account_balance_wallet,
                          color: Colors.blue.shade700, size: 28),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(amountLabel,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.blue.shade600)),
                          Text('${_currencyFormat.format(totalAmount)} đ',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade800)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(_l10n.paymentMethod,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 8),
                ...['Cash', 'BankTransfer', 'Card', 'EWallet'].map((method) {
                  final label = _paymentMethodLabel(method);
                  final icon = _paymentMethodIcon(method);
                  return RadioListTile<String>(
                    value: method,
                    // ignore: deprecated_member_use
                    groupValue: selectedMethod,
                    title: Row(
                      children: [
                        Icon(icon, size: 20, color: Colors.grey.shade700),
                        const SizedBox(width: 8),
                        Text(label),
                      ],
                    ),
                    dense: true,
                    // ignore: deprecated_member_use
                    onChanged: (v) =>
                        setDialogState(() => selectedMethod = v!),
                  );
                }),
                const SizedBox(height: 8),
                Text(
                  noteText,
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic),
                ),
              ],
            ),
          );
          Future<void> onPay() async {
            Navigator.pop(ctx);
            await _executeBatchPay(ids, selectedMethod);
          }
          if (isMobile) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity, height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(dialogTitle),
                    leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                  ),
                  body: formContent,
                  bottomNavigationBar: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: Text(_l10n.cancel)),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: onPay,
                        icon: const Icon(Icons.check),
                        label: Text(btnLabel),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: isPenaltyTab ? Colors.teal : Colors.blue),
                      ),
                    ]),
                  ),
                ),
              ),
            );
          }
          return AlertDialog(
            title: Row(
              children: [
                Icon(isPenaltyTab ? Icons.receipt_long : Icons.payment,
                    color: isPenaltyTab ? Colors.teal : Colors.blue),
                const SizedBox(width: 8),
                Text(dialogTitle),
              ],
            ),
            content: SizedBox(
              width: Responsive.dialogWidth(context),
              child: formContent,
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(_l10n.cancel)),
              ElevatedButton.icon(
                onPressed: onPay,
                icon: const Icon(Icons.check),
                label: Text(btnLabel),
                style: ElevatedButton.styleFrom(
                    backgroundColor: isPenaltyTab ? Colors.teal : Colors.blue),
              ),
            ],
          );
        },
      ),
    );
  }

  IconData _paymentMethodIcon(String method) {
    switch (method) {
      case 'Cash':
        return Icons.money;
      case 'BankTransfer':
        return Icons.account_balance;
      case 'Card':
        return Icons.credit_card;
      case 'EWallet':
        return Icons.phone_android;
      default:
        return Icons.payment;
    }
  }

  Future<void> _executeBatchPay(List<String> ids, String paymentMethod) async {
    setState(() => _isLoading = true);
    final result = await _apiService.bulkPayTransactions(ids, paymentMethod);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['isSuccess'] == true) {
      final data = result['data'];
      final s = data?['success'] ?? ids.length;
      final f = data?['failed'] ?? 0;
      final isPenalty = _tabController.index == 1;
      _showSnackBar(
        isPenalty
            ? 'Đã thu phạt $s/${ids.length} phiếu${f > 0 ? ' ($f lỗi)' : ''}. Phiếu thu đã được tạo.'
            : 'Đã thanh toán $s/${ids.length} phiếu${f > 0 ? ' ($f lỗi)' : ''}. Phiếu chi đã được tạo.',
        f > 0 ? Colors.orange : Colors.green,
      );
      _selectedIds.clear();
      _loadData();
    } else {
      _showSnackBar('Lỗi: ${result['message']}', Colors.red);
    }
  }

  // ══════════════════════════════════════════════════
  // SINGLE ITEM ACTIONS
  // ══════════════════════════════════════════════════
  Future<void> _handleAction(String action, Map<String, dynamic> tx) async {
    final id = tx['id']?.toString();
    if (id == null) return;

    switch (action) {
      case 'edit':
        _showCreateEditDialog(editTx: tx);
        break;
      case 'approve':
        final confirmApprove = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Xác nhận duyệt'),
            content: const Text('Bạn có chắc muốn duyệt phiếu này?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(_l10n.cancel)),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: Text(_l10n.approveLabel),
              ),
            ],
          ),
        );
        if (confirmApprove == true) {
          final result =
              await _apiService.updateTransactionStatus(id, 'Completed');
          if (result['isSuccess'] == true) {
            _showSnackBar('Đã duyệt thành công', Colors.green);
            _loadData();
          } else {
            _showSnackBar('Lỗi: ${result['message']}', Colors.red);
          }
        }
        break;
      case 'unapprove':
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Xác nhận hoàn duyệt'),
            content: const Text(
                'Phiếu sẽ chuyển về trạng thái "Chờ duyệt". Bạn có chắc?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(_l10n.cancel)),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: Text(_l10n.reverseApproval),
              ),
            ],
          ),
        );
        if (confirm == true) {
          final result =
              await _apiService.updateTransactionStatus(id, 'Pending');
          if (result['isSuccess'] == true) {
            _showSnackBar('Đã hoàn duyệt', Colors.orange);
            _loadData();
          } else {
            _showSnackBar('Lỗi: ${result['message']}', Colors.red);
          }
        }
        break;
      case 'cancel':
        final confirmCancel = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Xác nhận hủy'),
            content: const Text('Bạn có chắc muốn hủy phiếu này?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(_l10n.cancel)),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text('Hủy phiếu'),
              ),
            ],
          ),
        );
        if (confirmCancel == true) {
          final result =
              await _apiService.updateTransactionStatus(id, 'Cancelled');
          if (result['isSuccess'] == true) {
            _showSnackBar('Đã hủy', Colors.orange);
            _loadData();
          } else {
            _showSnackBar('Lỗi: ${result['message']}', Colors.red);
          }
        }
        break;
      case 'delete':
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Xác nhận xóa'),
            content: const Text('Bạn có chắc muốn xóa khoản này?'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(_l10n.cancel)),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: Text(_l10n.delete),
              ),
            ],
          ),
        );
        if (confirm == true) {
          final result = await _apiService.deleteTransaction(id);
          if (result['isSuccess'] == true) {
            _showSnackBar('Đã xóa', Colors.green);
            _loadData();
          } else {
            _showSnackBar('Lỗi: ${result['message']}', Colors.red);
          }
        }
        break;
    }
  }

  void _showSnackBar(String msg, Color color) {
    if (!mounted) return;
    if (color == Colors.green) {
      appNotification.showSuccess(title: 'Thành công', message: msg);
    } else if (color == Colors.red) {
      appNotification.showError(title: _l10n.error, message: msg);
    } else {
      appNotification.showWarning(title: 'Cảnh báo', message: msg);
    }
  }

  // ══════════════════════════════════════════════════
  // DIALOG TẠO / CHỈNH SỬA THƯỞNG / PHẠT
  // ══════════════════════════════════════════════════

  // Danh mục thưởng
  static const _bonusCategories = [
    'Thưởng lễ, tết',
    'Thưởng hoàn thành công việc',
    'Thưởng chuyên cần',
    'Thưởng sáng kiến',
    'Thưởng doanh số',
    'Thưởng thâm niên',
    'Thưởng đột xuất',
    'Thưởng khác',
  ];

  // Danh mục phạt
  static const _penaltyCategories = [
    'Đi trễ',
    'Về sớm',
    'Nghỉ không phép',
    'Vi phạm tác phong',
    'Vi phạm nội quy',
    'Vi phạm an toàn lao động',
    'Không hoàn thành công việc',
    'Vi phạm quy định công ty',
    'Phạt khác',
  ];

  void _showCreateEditDialog(
      {String? presetType, Map<String, dynamic>? editTx}) {
    final bool isEdit = editTx != null;

    // Pre-fill from editTx or defaults
    String type = editTx?['type']?.toString() ?? presetType ?? 'Bonus';
    String category = editTx?['description']?.toString() ??
        (type == 'Bonus' ? _bonusCategories.first : _penaltyCategories.first);
    final amountCtrl = TextEditingController(
      text: isEdit
          ? formatNumber(((editTx['amount'] as num?)?.toDouble() ?? 0).abs())
          : '',
    );
    final noteCtrl =
        TextEditingController(text: editTx?['note']?.toString() ?? '');
    Set<String> selectedEmployeeIds = {};
    bool selectAll = false;
    DateTime selectedDate = isEdit
        ? (DateTime.tryParse(editTx['transactionDate']?.toString() ?? '') ??
            DateTime.now())
        : DateTime.now();
    bool isSaving = false;
    String empSearchQuery = '';

    // For edit mode, pre-select the employee
    if (isEdit) {
      final empId = editTx['employeeId']?.toString() ??
          editTx['employeeUserId']?.toString();
      if (empId != null && empId.isNotEmpty) {
        selectedEmployeeIds.add(empId);
      }
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final categories =
              type == 'Bonus' ? _bonusCategories : _penaltyCategories;
          if (!categories.contains(category)) {
            category = categories.first;
          }

          // Filter employees for search
          final filteredEmps = empSearchQuery.isEmpty
              ? _employees
              : _employees.where((e) {
                  final name = '${e['lastName'] ?? ''} ${e['firstName'] ?? ''}'
                      .trim()
                      .toLowerCase();
                  final code =
                      (e['employeeCode']?.toString() ?? '').toLowerCase();
                  return name.contains(empSearchQuery.toLowerCase()) ||
                      code.contains(empSearchQuery.toLowerCase());
                }).toList();

          final isMobile = Responsive.isMobile(ctx);

          final dialogTitle = isEdit
              ? 'Chỉnh sửa ${type == 'Bonus' ? 'thưởng' : 'phạt'}'
              : (type == 'Bonus' ? 'Thêm thưởng' : 'Thêm phạt');

          final employeeListWidget = !isEdit
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Nhân viên áp dụng',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => setDialogState(() {
                            selectAll = !selectAll;
                            if (selectAll) {
                              selectedEmployeeIds = _employees
                                  .map((e) => e['id']?.toString() ?? '')
                                  .where((id) => id.isNotEmpty)
                                  .toSet();
                            } else {
                              selectedEmployeeIds.clear();
                            }
                          }),
                          icon: Icon(
                              selectAll ? Icons.deselect : Icons.select_all,
                              size: 16),
                          label: Text(selectAll ? 'Bỏ chọn' : 'Chọn tất cả',
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    Text(
                        'Đã chọn ${selectedEmployeeIds.length}/${_employees.length}',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Tìm nhân viên...',
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 18),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ),
                      onChanged: (v) =>
                          setDialogState(() => empSearchQuery = v),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: isMobile ? null : 200,
                      constraints: isMobile
                          ? null
                          : const BoxConstraints(maxHeight: 200),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        shrinkWrap: isMobile,
                        physics: isMobile
                            ? const NeverScrollableScrollPhysics()
                            : null,
                        itemCount: filteredEmps.length,
                        itemBuilder: (_, i) {
                          final emp = filteredEmps[i];
                          final empId = emp['id']?.toString() ?? '';
                          final name =
                              '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'
                                  .trim();
                          final code =
                              emp['employeeCode'] ?? emp['phoneNumber'] ?? '';
                          final dept = emp['departmentName'] ?? '';
                          return CheckboxListTile(
                            dense: true,
                            value: selectedEmployeeIds.contains(empId),
                            onChanged: (v) => setDialogState(() {
                              if (v == true) {
                                selectedEmployeeIds.add(empId);
                              } else {
                                selectedEmployeeIds.remove(empId);
                              }
                              selectAll = selectedEmployeeIds.length ==
                                  _employees.length;
                            }),
                            title: Text(name,
                                style: const TextStyle(fontSize: 13)),
                            subtitle: Text(
                                '$code${dept.isNotEmpty ? ' - $dept' : ''}',
                                style: const TextStyle(fontSize: 11)),
                          );
                        },
                      ),
                    ),
                  ],
                )
              : Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person,
                          size: 18, color: Colors.grey),
                      const SizedBox(width: 8),
                      Text(
                        editTx['employeeName']?.toString() ??
                            editTx['employeeCode']?.toString() ??
                            'N/A',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                );

          final formFields = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IgnorePointer(
                ignoring: isEdit,
                child: Opacity(
                  opacity: isEdit ? 0.6 : 1.0,
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'Bonus',
                          label: Text('Thưởng'),
                          icon: Icon(Icons.card_giftcard)),
                      ButtonSegment(
                          value: 'Penalty',
                          label: Text('Phạt'),
                          icon: Icon(Icons.gavel)),
                    ],
                    selected: {type},
                    onSelectionChanged: (v) => setDialogState(() {
                      type = v.first;
                      category = (type == 'Bonus'
                              ? _bonusCategories
                              : _penaltyCategories)
                          .first;
                    }),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: categories.contains(category)
                    ? category
                    : categories.first,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Danh mục *',
                  prefixIcon: const Icon(Icons.category),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                items: categories
                    .map(
                        (c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) =>
                    setDialogState(() => category = v ?? category),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandSeparatorFormatter()],
                decoration: InputDecoration(
                  labelText: 'Số tiền (VNĐ) *',
                  prefixIcon: const Icon(Icons.attach_money),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today),
                title: Text(
                    'Ngày: ${DateFormat('dd/MM/yyyy').format(selectedDate)}'),
                trailing: const Icon(Icons.edit_calendar),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) {
                    setDialogState(() => selectedDate = picked);
                  }
                },
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Ghi chú',
                  prefixIcon: const Icon(Icons.note),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 16),
              employeeListWidget,
            ],
          );

          final formContent = SingleChildScrollView(
            padding: isMobile ? const EdgeInsets.all(16) : EdgeInsets.zero,
            child: formFields,
          );

          final onSave = isSaving
              ? null
              : () {
                  if (isEdit) {
                    _submitEditDialog(
                        ctx,
                        setDialogState,
                        editTx,
                        type,
                        category,
                        amountCtrl,
                        noteCtrl,
                        selectedDate,
                        () => isSaving,
                        (v) => setDialogState(() => isSaving = v));
                  } else {
                    _submitCreateDialog(
                      ctx,
                      setDialogState,
                      type,
                      category,
                      amountCtrl,
                      noteCtrl,
                      selectedEmployeeIds,
                      selectedDate,
                      () => isSaving,
                      (v) => setDialogState(() => isSaving = v),
                      autoApprove: false,
                    );
                  }
                };

          final onCreateApprove = (!isEdit && !isSaving)
              ? () => _submitCreateDialog(
                    ctx,
                    setDialogState,
                    type,
                    category,
                    amountCtrl,
                    noteCtrl,
                    selectedEmployeeIds,
                    selectedDate,
                    () => isSaving,
                    (v) => setDialogState(() => isSaving = v),
                    autoApprove: true,
                  )
              : null;

          final saveIcon = isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(isEdit ? Icons.save : Icons.add);

          final saveLabel = Text(isSaving
              ? 'Đang lưu...'
              : (isEdit ? 'Cập nhật' : 'Tạo phiếu'));

          if (isMobile) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(dialogTitle),
                    leading: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                  body: formContent,
                  bottomNavigationBar: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Hủy'),
                        ),
                        if (!isEdit) ...[
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: onCreateApprove,
                            icon: isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.check_circle),
                            label: const Text('Tạo & Duyệt'),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.green),
                          ),
                        ],
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: onSave,
                          icon: saveIcon,
                          label: saveLabel,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  type == 'Bonus' ? Icons.card_giftcard : Icons.gavel,
                  color: type == 'Bonus' ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(dialogTitle),
              ],
            ),
            content: SizedBox(
              width: Responsive.dialogWidth(context),
              child: formContent,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy'),
              ),
              if (!isEdit) ...[
                OutlinedButton.icon(
                  onPressed: onCreateApprove,
                  icon: isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_circle),
                  label: const Text('Tạo & Duyệt'),
                  style:
                      OutlinedButton.styleFrom(foregroundColor: Colors.green),
                ),
                const SizedBox(width: 4),
              ],
              ElevatedButton.icon(
                onPressed: onSave,
                icon: saveIcon,
                label: saveLabel,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _submitCreateDialog(
    BuildContext ctx,
    StateSetter setDialogState,
    String type,
    String category,
    TextEditingController amountCtrl,
    TextEditingController noteCtrl,
    Set<String> selectedEmployeeIds,
    DateTime selectedDate,
    bool Function() getIsSaving,
    void Function(bool) setIsSaving, {
    required bool autoApprove,
  }) async {
    final amount =
        double.tryParse(amountCtrl.text.replaceAll(RegExp(r'[^\d]'), ''));
    if (amount == null || amount <= 0) {
      _showSnackBar('Vui lòng nhập số tiền hợp lệ', Colors.orange);
      return;
    }
    if (selectedEmployeeIds.isEmpty) {
      _showSnackBar('Vui lòng chọn ít nhất 1 nhân viên', Colors.orange);
      return;
    }

    setIsSaving(true);

    int success = 0;
    int failed = 0;
    List<String> createdIds = [];

    for (final empId in selectedEmployeeIds) {
      final result = await _apiService.createTransaction({
        'employeeId': empId,
        'type': type,
        'transactionDate': selectedDate.toIso8601String(),
        'forMonth': selectedDate.month,
        'forYear': selectedDate.year,
        'amount': type == 'Penalty' ? -amount : amount,
        'description': category,
        'note': noteCtrl.text.trim(),
      });
      if (result['isSuccess'] == true) {
        success++;
        final txId = result['data']?['id']?.toString();
        if (txId != null) createdIds.add(txId);
      } else {
        failed++;
      }
    }

    // Auto-approve if requested
    if (autoApprove && createdIds.isNotEmpty) {
      final approveResult =
          await _apiService.bulkApproveTransactions(createdIds);
      if (approveResult['isSuccess'] != true) {
        _showSnackBar('Tạo thành công nhưng duyệt lỗi', Colors.orange);
      }
    }

    setIsSaving(false);

    if (failed > 0 && success == 0) {
      _showSnackBar('Không thể tạo phiếu, vui lòng thử lại', Colors.red);
      return;
    }

    if (ctx.mounted) Navigator.pop(ctx);
    _showSnackBar(
      autoApprove
          ? 'Đã tạo & duyệt $success/${selectedEmployeeIds.length} phiếu${failed > 0 ? ' ($failed lỗi)' : ''}'
          : 'Đã tạo $success/${selectedEmployeeIds.length} phiếu${failed > 0 ? ' ($failed lỗi)' : ''}',
      failed > 0 ? Colors.orange : Colors.green,
    );
    _loadData();
  }

  Future<void> _submitEditDialog(
    BuildContext ctx,
    StateSetter setDialogState,
    Map<String, dynamic> editTx,
    String type,
    String category,
    TextEditingController amountCtrl,
    TextEditingController noteCtrl,
    DateTime selectedDate,
    bool Function() getIsSaving,
    void Function(bool) setIsSaving,
  ) async {
    final amount =
        double.tryParse(amountCtrl.text.replaceAll(RegExp(r'[^\d]'), ''));
    if (amount == null || amount <= 0) {
      _showSnackBar('Vui lòng nhập số tiền hợp lệ', Colors.orange);
      return;
    }

    setIsSaving(true);
    final txId = editTx['id']?.toString();
    if (txId == null) return;

    final result = await _apiService.updateTransaction(txId, {
      'type': type,
      'amount': type == 'Penalty' ? -amount : amount,
      'description': category,
      'note': noteCtrl.text.trim(),
      'transactionDate': selectedDate.toIso8601String(),
    });

    setIsSaving(false);

    if (result['isSuccess'] == true) {
      if (ctx.mounted) Navigator.pop(ctx);
      _showSnackBar('Đã cập nhật thành công', Colors.green);
      _loadData();
    } else {
      _showSnackBar('Lỗi: ${result['message']}', Colors.red);
    }
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
