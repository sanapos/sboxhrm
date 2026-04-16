import '../utils/file_saver.dart' as file_saver;
import 'package:excel/excel.dart' as excel_lib;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models/cash_transaction.dart';
import '../widgets/loading_widget.dart';
import '../widgets/empty_state.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../widgets/notification_overlay.dart';
import '../utils/responsive_helper.dart';
import '../widgets/app_button.dart';

class CashTransactionScreen extends StatefulWidget {
  const CashTransactionScreen({super.key});

  @override
  State<CashTransactionScreen> createState() => _CashTransactionScreenState();
}

class _CashTransactionScreenState extends State<CashTransactionScreen> {
  final ApiService _apiService = ApiService();
  final _currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
  final _dateFormat = DateFormat('dd/MM/yyyy');

  // Data
  List<CashTransaction> _transactions = [];
  List<TransactionCategory> _categories = [];
  List<BankAccount> _bankAccounts = [];
  List<VietQRBank> _vietQRBanks = [];
  CashTransactionSummary? _summary;

  // Loading states
  bool _isLoading = true;
  // ignore: unused_field
  int _totalTransactions = 0;
  int _currentPage = 1;
  int _pageSize = 20;
  final List<int> _pageSizeOptions = [20, 50, 100, 200];

  // Date preset filter
  String _datePreset = 'thisMonth';
  DateTimeRange? _customDateRange;

  // Filters
  CashTransactionType? _typeFilter;
  String? _categoryFilter;
  CashTransactionStatus? _statusFilter;

  // Mobile UI state
  bool _showMobileFilters = false;
  bool _showMobileSummary = false;

  // Inline summary for transactions tab
  CashTransactionSummary? _inlineSummary;
  bool _isSummaryLoading = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

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
          start: DateTime(lastWeekStart.year, lastWeekStart.month, lastWeekStart.day),
          end: DateTime(lastWeekEnd.year, lastWeekEnd.month, lastWeekEnd.day, 23, 59, 59));
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

  String get _datePresetLabel {
    switch (_datePreset) {
      case 'today': return 'Hôm nay';
      case 'yesterday': return 'Hôm qua';
      case 'thisWeek': return 'Tuần này';
      case 'lastWeek': return 'Tuần trước';
      case 'thisMonth': return 'Tháng này';
      case 'lastMonth': return 'Tháng trước';
      case 'custom':
        if (_customDateRange != null) {
          return '${DateFormat('dd/MM').format(_customDateRange!.start)} - ${DateFormat('dd/MM').format(_customDateRange!.end)}';
        }
        return 'Tùy chọn';
      default: return 'Tháng này';
    }
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _loadTransactions(),
        _loadCategories(),
        _loadBankAccounts(),
        _loadSummary(),
        _loadInlineSummary(),
        _loadVietQRBanks(),
      ]);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTransactions() async {
    final range = _selectedDateRange;
    final result = await _apiService.getCashTransactions(
      type: _typeFilter?.value,
      categoryId: _categoryFilter,
      status: _statusFilter?.value,
      fromDate: range.start,
      toDate: range.end,
      pageNumber: _currentPage,
      pageSize: _pageSize,
    );

    if (result['isSuccess'] == true && result['data'] != null) {
      final data = result['data'];
      setState(() {
        _transactions = (data['items'] as List?)
                ?.map((e) => CashTransaction.fromJson(e))
                .toList() ??
            [];
        _totalTransactions = data['totalCount'] ?? 0;
      });
    }
  }

  Future<void> _loadCategories() async {
    final result = await _apiService.getTransactionCategories();
    if (result['isSuccess'] == true && result['data'] != null) {
      setState(() {
        _categories = (result['data'] as List?)
                ?.map((e) => TransactionCategory.fromJson(e))
                .toList() ??
            [];
      });
    }

    // Initialize default categories if empty (only try once)
    if (_categories.isEmpty) {
      final initResult = await _apiService.initDefaultTransactionCategories();
      if (initResult['isSuccess'] == true) {
        final retryResult = await _apiService.getTransactionCategories();
        if (retryResult['isSuccess'] == true && retryResult['data'] != null) {
          setState(() {
            _categories = (retryResult['data'] as List?)
                    ?.map((e) => TransactionCategory.fromJson(e))
                    .toList() ??
                [];
          });
        }
      }
    }
  }

  Future<void> _loadBankAccounts() async {
    final result = await _apiService.getBankAccounts();
    if (result['isSuccess'] == true && result['data'] != null) {
      setState(() {
        _bankAccounts = (result['data'] as List?)
                ?.map((e) => BankAccount.fromJson(e))
                .toList() ??
            [];
      });
    }
  }

  Future<void> _loadVietQRBanks() async {
    final result = await _apiService.getVietQRBanks();
    if (result['isSuccess'] == true && result['data'] != null) {
      setState(() {
        _vietQRBanks = (result['data'] as List?)
                ?.map((e) => VietQRBank.fromJson(e))
                .toList() ??
            [];
      });
    }
  }

  Future<void> _loadSummary() async {
    final range = _selectedDateRange;
    final result = await _apiService.getCashTransactionSummary(
      fromDate: range.start,
      toDate: range.end,
    );
    if (result['isSuccess'] == true && result['data'] != null) {
      setState(() {
        _summary = CashTransactionSummary.fromJson(result['data']);
      });
    }
  }

  Future<void> _loadInlineSummary() async {
    setState(() => _isSummaryLoading = true);
    final range = _selectedDateRange;
    final result = await _apiService.getCashTransactionSummary(
      fromDate: range.start,
      toDate: range.end,
    );
    if (result['isSuccess'] == true && result['data'] != null && mounted) {
      setState(() {
        _inlineSummary = CashTransactionSummary.fromJson(result['data']);
        _isSummaryLoading = false;
      });
    } else {
      if (mounted) setState(() => _isSummaryLoading = false);
    }
  }

  void _onFiltersChanged() {
    _currentPage = 1;
    _loadTransactions();
    _loadInlineSummary();
  }

  void _showTransactionForm([CashTransaction? transaction]) {
    showDialog(
      context: context,
      builder: (context) => _TransactionFormDialog(
        transaction: transaction,
        categories: _categories,
        bankAccounts: _bankAccounts,
        onSaved: () {
          _loadTransactions();
          _loadSummary();
          _loadInlineSummary();
        },
      ),
    );
  }

  void _showCategoryForm([TransactionCategory? category]) {
    showDialog(
      context: context,
      builder: (context) => _CategoryFormDialog(
        category: category,
        onSaved: _loadCategories,
      ),
    );
  }

  void _showBankAccountForm([BankAccount? account]) {
    showDialog(
      context: context,
      builder: (context) => _BankAccountFormDialog(
        account: account,
        vietQRBanks: _vietQRBanks,
        onSaved: _loadBankAccounts,
      ),
    );
  }

  void _showVietQRDialog(CashTransaction transaction) {
    if (_bankAccounts.isEmpty) {
      appNotification.showWarning(
        title: 'Cảnh báo',
        message: 'Vui lòng thêm tài khoản ngân hàng trước',
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => _VietQRDialog(
        transaction: transaction,
        bankAccounts: _bankAccounts,
      ),
    );
  }

  Future<void> _deleteTransaction(CashTransaction transaction) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text(
            'Bạn có chắc muốn xóa giao dịch "${transaction.transactionCode}"?'),
        actions: [
          AppDialogActions.delete(
            onCancel: () => Navigator.pop(context, false),
            onConfirm: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final result = await _apiService.deleteCashTransaction(transaction.id);
      if (result['isSuccess'] == true && mounted) {
        appNotification.showSuccess(
          title: 'Thành công',
          message: 'Đã xóa giao dịch',
        );
        _loadTransactions();
        _loadSummary();
        _loadInlineSummary();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý Thu Chi', overflow: TextOverflow.ellipsis, maxLines: 1),
        actions: [
          if (Responsive.isMobile(context))
            IconButton(
              icon: Stack(
                children: [
                  Icon(_showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined),
                  if (_typeFilter != null || _statusFilter != null || _categoryFilter != null || _datePreset != 'thisMonth')
                    Positioned(
                      right: 0, top: 0,
                      child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle)),
                    ),
                ],
              ),
              onPressed: () => setState(() => _showMobileFilters = !_showMobileFilters),
              tooltip: 'Bộ lọc',
            ),
          IconButton(
            icon: const Icon(Icons.category_outlined),
            onPressed: () => _showCategoryManagement(),
            tooltip: 'Danh mục',
          ),
          IconButton(
            icon: const Icon(Icons.account_balance_outlined),
            onPressed: () => _showBankAccountManagement(),
            tooltip: 'Tài khoản',
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingWidget()
          : _buildTransactionsTab(),
      floatingActionButton: Responsive.isMobile(context) && Provider.of<PermissionProvider>(context, listen: false).canCreate('CashTransaction')
          ? FloatingActionButton.extended(
              onPressed: () => _showTransactionForm(),
              icon: const Icon(Icons.add),
              label: const Text('Thu/Chi'),
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  void _showCategoryManagement() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.category),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Danh mục thu chi',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () {
                      Navigator.pop(context);
                      _showCategoryForm();
                    },
                    tooltip: 'Thêm danh mục',
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            Expanded(
              child: _categories.isEmpty
                  ? const Center(child: Text('Chưa có danh mục'))
                  : ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: [
                        _buildCategorySection('Thu nhập',
                          _categories.where((c) => c.type == CashTransactionType.income).toList(),
                          Colors.green),
                        const SizedBox(height: 16),
                        _buildCategorySection('Chi phí',
                          _categories.where((c) => c.type == CashTransactionType.expense).toList(),
                          Colors.red),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBankAccountManagement() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.account_balance),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Tài khoản ngân hàng',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () {
                      Navigator.pop(context);
                      _showBankAccountForm();
                    },
                    tooltip: 'Thêm tài khoản',
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 24),
            Expanded(
              child: _bankAccounts.isEmpty
                  ? const Center(child: Text('Chưa có tài khoản'))
                  : ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      children: _bankAccounts.map((account) => _buildBankAccountCard(account)).toList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // FAB removed - add transaction button is now in the filter bar

  Future<void> _exportCashTransactionsExcel() async {
    try {
      // Fetch ALL transactions matching current filters (not just current page)
      final range = _selectedDateRange;
      final result = await _apiService.getCashTransactions(
        type: _typeFilter?.value,
        categoryId: _categoryFilter,
        status: _statusFilter?.value,
        fromDate: range.start,
        toDate: range.end,
        pageNumber: 1,
        pageSize: 5000,
      );

      List<CashTransaction> data = [];
      if (result['isSuccess'] == true && result['data'] != null) {
        final respData = result['data'];
        data = (respData['items'] as List?)
                ?.map((e) => CashTransaction.fromJson(e))
                .toList() ??
            [];
      }

      if (data.isEmpty) {
        appNotification.showError(title: 'Lỗi', message: 'Không có dữ liệu để xuất');
        return;
      }

      final wb = excel_lib.Excel.createExcel();
      final sheet = wb['Thu Chi'];

      // Title
      sheet.appendRow([excel_lib.TextCellValue('DANH SÁCH PHIẾU THU CHI')]);
      sheet.merge(excel_lib.CellIndex.indexByString('A1'), excel_lib.CellIndex.indexByString('L1'));

      // Date info
      final dateInfo = '${DateFormat('dd/MM/yyyy').format(range.start)} - ${DateFormat('dd/MM/yyyy').format(range.end)}';
      sheet.appendRow([excel_lib.TextCellValue(dateInfo)]);
      sheet.merge(excel_lib.CellIndex.indexByString('A2'), excel_lib.CellIndex.indexByString('L2'));
      sheet.appendRow([]); // blank row

      // Headers
      final headers = ['STT', 'Mã phiếu', 'Loại', 'Danh mục', 'Số tiền', 'Ngày GD', 'Mô tả', 'Người liên hệ', 'SĐT', 'PT thanh toán', 'Trạng thái', 'Đã TT', 'Ghi chú NB'];
      sheet.appendRow(headers.map((h) => excel_lib.TextCellValue(h)).toList());

      double totalIncome = 0, totalExpense = 0;

      // Data
      for (int i = 0; i < data.length; i++) {
        final t = data[i];
        final isIncome = t.type == CashTransactionType.income;
        if (isIncome) {
          totalIncome += t.amount;
        } else {
          totalExpense += t.amount;
        }

        sheet.appendRow([
          excel_lib.IntCellValue(i + 1),
          excel_lib.TextCellValue(t.transactionCode),
          excel_lib.TextCellValue(isIncome ? 'Thu' : 'Chi'),
          excel_lib.TextCellValue(t.categoryName),
          excel_lib.DoubleCellValue(t.amount),
          excel_lib.TextCellValue(DateFormat('dd/MM/yyyy HH:mm').format(t.transactionDate)),
          excel_lib.TextCellValue(t.description),
          excel_lib.TextCellValue(t.contactName ?? ''),
          excel_lib.TextCellValue(t.contactPhone ?? ''),
          excel_lib.TextCellValue(t.paymentMethod.label),
          excel_lib.TextCellValue(t.status.label),
          excel_lib.TextCellValue(t.isPaid ? 'Đã TT' : 'Chưa TT'),
          excel_lib.TextCellValue(t.internalNote ?? ''),
        ]);
      }

      // Summary rows
      sheet.appendRow([]);
      sheet.appendRow([
        excel_lib.TextCellValue(''),
        excel_lib.TextCellValue(''),
        excel_lib.TextCellValue('TỔNG THU'),
        excel_lib.TextCellValue(''),
        excel_lib.DoubleCellValue(totalIncome),
      ]);
      sheet.appendRow([
        excel_lib.TextCellValue(''),
        excel_lib.TextCellValue(''),
        excel_lib.TextCellValue('TỔNG CHI'),
        excel_lib.TextCellValue(''),
        excel_lib.DoubleCellValue(totalExpense),
      ]);
      sheet.appendRow([
        excel_lib.TextCellValue(''),
        excel_lib.TextCellValue(''),
        excel_lib.TextCellValue('CHÊNH LỆCH'),
        excel_lib.TextCellValue(''),
        excel_lib.DoubleCellValue(totalIncome - totalExpense),
      ]);

      // Remove default sheet
      wb.delete('Sheet1');

      final bytes = wb.encode();
      if (bytes != null) {
        final blob = bytes;
        await file_saver.saveFileBytes(blob, 'thu_chi_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        appNotification.showSuccess(title: 'Thành công', message: 'Đã xuất file Excel (${data.length} phiếu)');
      }
    } catch (e) {
      appNotification.showError(title: 'Lỗi', message: 'Không thể xuất Excel: $e');
    }
  }

  Widget _buildTransactionsTab() {
    final isMobile = Responsive.isMobile(context);
    return Column(
      children: [
        if (!isMobile || _showMobileFilters) _buildFilterBar(),
        if (isMobile) ...[
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
          if (_showMobileSummary) _buildInlineSummaryRow(),
        ] else ...[
          _buildInlineSummaryRow(),
        ],
        Expanded(child: _buildTransactionList()),
        if (!isMobile) _buildPaginationControls(),
      ],
    );
  }

  Widget _buildFilterBar() {
    final hasFilters = _typeFilter != null ||
        _statusFilter != null ||
        _categoryFilter != null ||
        _datePreset != 'thisMonth';

    final isMobile = Responsive.isMobile(context);
    final dropdownWidth = isMobile ? null : 160.0;

    Widget dateDropdown = DropdownButtonFormField<String>(
      initialValue: _datePreset,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Thời gian',
        isDense: true,
        prefixIcon: const Icon(Icons.calendar_today, size: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      items: const [
        DropdownMenuItem(value: 'today', child: Text('Hôm nay')),
        DropdownMenuItem(value: 'yesterday', child: Text('Hôm qua')),
        DropdownMenuItem(value: 'thisWeek', child: Text('Tuần này')),
        DropdownMenuItem(value: 'lastWeek', child: Text('Tuần trước')),
        DropdownMenuItem(value: 'thisMonth', child: Text('Tháng này')),
        DropdownMenuItem(value: 'lastMonth', child: Text('Tháng trước')),
        DropdownMenuItem(value: 'custom', child: Text('Tùy chọn...')),
      ],
      onChanged: (v) async {
        if (v == null) return;
        if (v == 'custom') {
          final picked = await showDateRangePicker(
            context: context,
            firstDate: DateTime(2020),
            lastDate: DateTime(2030),
            initialDateRange: _customDateRange,
          );
          if (picked != null) {
            setState(() {
              _customDateRange = DateTimeRange(
                start: picked.start,
                end: DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59),
              );
              _datePreset = 'custom';
            });
            _onFiltersChanged();
          }
        } else {
          setState(() => _datePreset = v);
          _onFiltersChanged();
        }
      },
    );

    Widget typeDropdown = DropdownButtonFormField<CashTransactionType?>(
      initialValue: _typeFilter,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Loại',
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('Tất cả')),
        ...CashTransactionType.values
            .map((t) => DropdownMenuItem(value: t, child: Text(t.label))),
      ],
      onChanged: (v) {
        setState(() {
          _typeFilter = v;
          _categoryFilter = null;
        });
        _onFiltersChanged();
      },
    );

    Widget statusDropdown = DropdownButtonFormField<CashTransactionStatus?>(
      initialValue: _statusFilter,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Trạng thái',
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('Tất cả')),
        ...CashTransactionStatus.values
            .map((s) => DropdownMenuItem(value: s, child: Text(s.label))),
      ],
      onChanged: (v) {
        setState(() => _statusFilter = v);
        _onFiltersChanged();
      },
    );

    Widget categoryDropdown = DropdownButtonFormField<String?>(
      initialValue: _categoryFilter,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Danh mục',
        isDense: true,
        prefixIcon: const Icon(Icons.category, size: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('Tất cả')),
        ..._categories
            .where((c) => _typeFilter == null || c.type == _typeFilter)
            .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
      ],
      onChanged: (v) {
        setState(() => _categoryFilter = v);
        _onFiltersChanged();
      },
    );

    final clearBtn = hasFilters
        ? IconButton(
            icon: const Icon(Icons.clear_all, size: 20),
            tooltip: 'Xóa lọc',
            onPressed: () {
              setState(() {
                _datePreset = 'thisMonth';
                _customDateRange = null;
                _typeFilter = null;
                _statusFilter = null;
                _categoryFilter = null;
              });
              _onFiltersChanged();
            },
          )
        : null;

    final actionButtons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (clearBtn != null) clearBtn,
        if (Provider.of<PermissionProvider>(context, listen: false).canExport('CashTransaction'))
        IconButton(
          icon: Icon(Icons.file_download, size: 20, color: Colors.green.shade700),
          tooltip: 'Xuất Excel',
          onPressed: _exportCashTransactionsExcel,
        ),
        if (Provider.of<PermissionProvider>(context, listen: false).canCreate('CashTransaction'))
        const SizedBox(width: 4),
        if (Provider.of<PermissionProvider>(context, listen: false).canCreate('CashTransaction'))
        FilledButton.icon(
          onPressed: () => _showTransactionForm(),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Thu/Chi'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
      ],
    );

    if (isMobile) {
      return Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Column(
          children: [
            Row(children: [
              Expanded(child: dateDropdown),
              const SizedBox(width: 8),
              Expanded(child: typeDropdown),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: statusDropdown),
              const SizedBox(width: 8),
              Expanded(child: categoryDropdown),
            ]),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [actionButtons],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.start,
              children: [
                SizedBox(width: dropdownWidth, child: dateDropdown),
                SizedBox(width: 120, child: typeDropdown),
                SizedBox(width: 140, child: statusDropdown),
                SizedBox(width: 160, child: categoryDropdown),
              ],
            ),
          ),
          const SizedBox(width: 8),
          actionButtons,
        ],
      ),
    );
  }

  Widget _buildInlineSummaryRow() {
    if (_isSummaryLoading) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: LinearProgressIndicator(),
      );
    }
    if (_inlineSummary == null) return const SizedBox.shrink();

    final s = _inlineSummary!;

    Widget incomeCard = Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.arrow_downward, color: Colors.green.shade700, size: 16),
              const SizedBox(width: 6),
              Text('Thu', style: TextStyle(
                color: Colors.green.shade700, fontWeight: FontWeight.w600, fontSize: 13)),
            ]),
            const SizedBox(height: 4),
            Text(_currencyFormat.format(s.totalIncome),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                color: Colors.green.shade700)),
            Text('${s.incomeTransactions} giao dịch', style: TextStyle(
              color: Colors.green.shade400, fontSize: 11)),
          ],
        ),
      ),
    );

    Widget expenseCard = Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.arrow_upward, color: Colors.red.shade700, size: 16),
              const SizedBox(width: 6),
              Text('Chi', style: TextStyle(
                color: Colors.red.shade700, fontWeight: FontWeight.w600, fontSize: 13)),
            ]),
            const SizedBox(height: 4),
            Text(_currencyFormat.format(s.totalExpense),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                color: Colors.red.shade700)),
            Text('${s.expenseTransactions} giao dịch', style: TextStyle(
              color: Colors.red.shade400, fontSize: 11)),
          ],
        ),
      ),
    );

    Widget balanceCard = Card(
      color: s.balance >= 0 ? Colors.blue.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(s.balance >= 0 ? Icons.trending_up : Icons.trending_down,
                color: s.balance >= 0 ? Colors.blue.shade700 : Colors.orange.shade700, size: 16),
              const SizedBox(width: 6),
              Text('Số dư', style: TextStyle(
                color: s.balance >= 0 ? Colors.blue.shade700 : Colors.orange.shade700,
                fontWeight: FontWeight.w600, fontSize: 13)),
            ]),
            const SizedBox(height: 4),
            Text(_currencyFormat.format(s.balance),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                color: s.balance >= 0 ? Colors.blue.shade700 : Colors.orange.shade700)),
            Text(_datePresetLabel, style: TextStyle(
              color: Colors.grey.shade400, fontSize: 11)),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 500) {
          return Column(
            children: [
              incomeCard,
              const SizedBox(height: 4),
              expenseCard,
              const SizedBox(height: 4),
              balanceCard,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: incomeCard),
            const SizedBox(width: 8),
            Expanded(child: expenseCard),
            const SizedBox(width: 8),
            Expanded(child: balanceCard),
          ],
        );
      }),
    );
  }

  Future<void> _updateTransactionStatus(
      CashTransaction transaction, CashTransactionStatus newStatus) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận'),
        content: Text(
            'Bạn có chắc muốn chuyển trạng thái giao dịch sang "${newStatus.label}"?'),
        actions: [
          AppDialogActions(
            onCancel: () => Navigator.pop(ctx, false),
            onConfirm: () => Navigator.pop(ctx, true),
            confirmLabel: 'Xác nhận',
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await _apiService.updateCashTransactionStatus(
        transaction.id, newStatus.value);
    if (result['isSuccess'] == true && mounted) {
      appNotification.showSuccess(
        title: 'Thành công',
        message: 'Đã cập nhật: ${newStatus.label}',
      );
      _loadTransactions();
      _loadInlineSummary();
    } else if (mounted) {
      appNotification.showError(
        title: 'Lỗi',
        message: result['message'] ?? 'Có lỗi xảy ra',
      );
    }
  }

  Widget _buildTransactionList() {
    if (_transactions.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long,
        title: 'Chưa có giao dịch',
        description: 'Nhấn nút + để thêm giao dịch thu/chi mới',
      );
    }

    return RefreshIndicator(
      onRefresh: _loadTransactions,
      child: Responsive.isMobile(context)
        ? ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: _transactions.length,
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
                child: _buildTxDeckItem(_transactions[i]),
              ),
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _transactions.length,
            itemBuilder: (context, index) => _buildTransactionCard(_transactions[index]),
          ),
    );
  }

  Widget _buildPaginationControls() {
    final totalPages = (_totalTransactions / _pageSize).ceil();
    if (totalPages <= 1 && _totalTransactions <= _pageSize) return const SizedBox.shrink();

    final start = _totalTransactions > 0 ? (_currentPage - 1) * _pageSize + 1 : 0;
    final end = (_currentPage * _pageSize).clamp(0, _totalTransactions);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text('Hiển thị $start-$end / $_totalTransactions',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
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
                        _loadTransactions();
                        _loadInlineSummary();
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
                icon: const Icon(Icons.chevron_left, size: 20),
                onPressed: _currentPage > 1
                    ? () { setState(() => _currentPage--); _loadTransactions(); _loadInlineSummary(); }
                    : null,
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
                    ? () { setState(() => _currentPage++); _loadTransactions(); _loadInlineSummary(); }
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTxDeckItem(CashTransaction transaction) {
    final isIncome = transaction.type == CashTransactionType.income;
    final color = isIncome ? Colors.green : Colors.red;
    final formatter = NumberFormat('#,###', 'vi_VN');

    return InkWell(
      onTap: () => _showTransactionForm(transaction),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: color.withAlpha(30), borderRadius: BorderRadius.circular(8)),
            child: Icon(isIncome ? Icons.arrow_downward : Icons.arrow_upward, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(transaction.description, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                [transaction.transactionCode, transaction.categoryName, DateFormat('dd/MM/yyyy').format(transaction.transactionDate)].join(' · '),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          Text(
            '${isIncome ? '+' : '-'}${formatter.format(transaction.amount)} đ',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color),
          ),
        ]),
      ),
    );
  }

  Widget _buildTransactionCard(CashTransaction transaction) {
    final isIncome = transaction.type == CashTransactionType.income;
    final color = isIncome ? Colors.green : Colors.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                    color: color,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.description,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${transaction.transactionCode} • ${transaction.categoryName}',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${isIncome ? '+' : '-'}${_currencyFormat.format(transaction.amount)}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      _dateFormat.format(transaction.transactionDate),
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildStatusChip(transaction.status),
                const SizedBox(width: 8),
                _buildPaymentMethodChip(transaction.paymentMethod),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (Provider.of<PermissionProvider>(context, listen: false).canEdit('CashTransaction'))
                _ActionBtn(
                  icon: Icons.edit_rounded,
                  label: 'Sửa',
                  color: Colors.blue,
                  onTap: () => _showTransactionForm(transaction),
                ),
                if (Provider.of<PermissionProvider>(context, listen: false).canEdit('CashTransaction'))
                const SizedBox(width: 6),
                if (transaction.status == CashTransactionStatus.pending ||
                    transaction.status == CashTransactionStatus.waitingPayment) ...[
                  if (Provider.of<PermissionProvider>(context, listen: false).canApprove('CashTransaction')) ...[
                  _ActionBtn(
                    icon: Icons.check_circle_outline,
                    label: 'Hoàn thành',
                    color: Colors.green,
                    onTap: () => _updateTransactionStatus(
                        transaction, CashTransactionStatus.completed),
                  ),
                  const SizedBox(width: 6),
                  _ActionBtn(
                    icon: Icons.cancel_outlined,
                    label: 'Hủy',
                    color: Colors.orange,
                    onTap: () => _updateTransactionStatus(
                        transaction, CashTransactionStatus.cancelled),
                  ),
                  const SizedBox(width: 6),
                  ],
                ],
                if (transaction.paymentMethod == PaymentMethodType.vietQR ||
                    transaction.paymentMethod == PaymentMethodType.bankTransfer) ...[
                  _ActionBtn(
                    icon: Icons.qr_code_2,
                    label: 'VietQR',
                    color: Colors.purple,
                    onTap: () => _showVietQRDialog(transaction),
                  ),
                  const SizedBox(width: 6),
                ],
                if (Provider.of<PermissionProvider>(context, listen: false).canDelete('CashTransaction'))
                _ActionBtn(
                  icon: Icons.delete_forever_outlined,
                  label: 'Xóa',
                  color: Colors.red.shade700,
                  onTap: () => _deleteTransaction(transaction),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(CashTransactionStatus status) {
    Color color;
    switch (status) {
      case CashTransactionStatus.completed:
        color = Colors.green;
        break;
      case CashTransactionStatus.pending:
        color = Colors.orange;
        break;
      case CashTransactionStatus.waitingPayment:
        color = Colors.blue;
        break;
      case CashTransactionStatus.cancelled:
        color = Colors.red;
        break;
    }

    return Chip(
      label: Text(status.label),
      backgroundColor: color.withAlpha(30),
      labelStyle: TextStyle(color: color, fontSize: 11),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildPaymentMethodChip(PaymentMethodType method) {
    return Chip(
      avatar: Icon(
        _getPaymentMethodIcon(method),
        size: 14,
      ),
      label: Text(method.label),
      backgroundColor: Colors.grey.withAlpha(30),
      labelStyle: const TextStyle(fontSize: 11),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  IconData _getPaymentMethodIcon(PaymentMethodType method) {
    switch (method) {
      case PaymentMethodType.cash:
        return Icons.payments;
      case PaymentMethodType.bankTransfer:
        return Icons.account_balance;
      case PaymentMethodType.vietQR:
        return Icons.qr_code_2;
      case PaymentMethodType.card:
        return Icons.credit_card;
      case PaymentMethodType.eWallet:
        return Icons.account_balance_wallet;
      case PaymentMethodType.other:
        return Icons.more_horiz;
    }
  }

  // ignore: unused_element
  Widget _buildCategoryList() {
    if (_categories.isEmpty) {
      return const EmptyState(
        icon: Icons.category,
        title: 'Chưa có danh mục',
        description: 'Nhấn nút + để thêm danh mục mới',
      );
    }

    final incomeCategories =
        _categories.where((c) => c.type == CashTransactionType.income).toList();
    final expenseCategories =
        _categories.where((c) => c.type == CashTransactionType.expense).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCategorySection('Thu nhập', incomeCategories, Colors.green),
        const SizedBox(height: 16),
        _buildCategorySection('Chi phí', expenseCategories, Colors.red),
      ],
    );
  }

  Widget _buildCategorySection(
      String title, List<TransactionCategory> categories, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.circle, color: color, size: 12),
            const SizedBox(width: 8),
            Text(
              '$title (${categories.length})',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...categories.map((category) => _buildCategoryTile(category, color)),
      ],
    );
  }

  Widget _buildCategoryTile(TransactionCategory category, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withAlpha(30),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            _getCategoryIcon(category.icon),
            color: color,
            size: 20,
          ),
        ),
        title: Text(category.name),
        subtitle: category.description != null
            ? Text(
                category.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (category.isSystem)
              const Chip(
                label: Text('Hệ thống'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            IconButton(
              icon: const Icon(Icons.edit, size: 18),
              onPressed: () => _showCategoryForm(category),
            ),
          ],
        ),
        onTap: () => _showCategoryForm(category),
      ),
    );
  }

  IconData _getCategoryIcon(String? iconName) {
    switch (iconName) {
      case 'sell':
        return Icons.sell;
      case 'work':
        return Icons.work;
      case 'savings':
        return Icons.savings;
      case 'card_giftcard':
        return Icons.card_giftcard;
      case 'trending_up':
        return Icons.trending_up;
      case 'shopping_cart':
        return Icons.shopping_cart;
      case 'payments':
        return Icons.payments;
      case 'home':
        return Icons.home;
      case 'local_gas_station':
        return Icons.local_gas_station;
      case 'bolt':
        return Icons.bolt;
      case 'phone':
        return Icons.phone;
      case 'restaurant':
        return Icons.restaurant;
      case 'emoji_transportation':
        return Icons.emoji_transportation;
      case 'health_and_safety':
        return Icons.health_and_safety;
      case 'school':
        return Icons.school;
      case 'more_horiz':
        return Icons.more_horiz;
      default:
        return Icons.category;
    }
  }

  // ignore: unused_element
  Widget _buildBankAccountList() {
    if (_bankAccounts.isEmpty) {
      return const EmptyState(
        icon: Icons.account_balance,
        title: 'Chưa có tài khoản ngân hàng',
        description: 'Thêm tài khoản ngân hàng để sử dụng VietQR',
      );
    }

    if (Responsive.isMobile(context)) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _bankAccounts.length,
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
            child: _buildBankDeckItem(_bankAccounts[i]),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _bankAccounts.length,
      itemBuilder: (context, index) =>
          _buildBankAccountCard(_bankAccounts[index]),
    );
  }

  Widget _buildBankDeckItem(BankAccount account) {
    return InkWell(
      onTap: () => _showBankAccountForm(account),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: Colors.blue.withAlpha(30), borderRadius: BorderRadius.circular(8)),
            child: account.bankLogoUrl != null
              ? ClipRRect(borderRadius: BorderRadius.circular(8), child: CachedNetworkImage(imageUrl: account.bankLogoUrl!, fit: BoxFit.contain, width: 36, height: 36, errorWidget: (_, __, ___) => const Icon(Icons.account_balance, color: Colors.blue, size: 18)))
              : const Icon(Icons.account_balance, color: Colors.blue, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(account.accountName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                [account.bankName, account.accountNumber].join(' · '),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          if (account.isDefault) Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: const Text('Mặc định', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.green)),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFA1A1AA)),
        ]),
      ),
    );
  }

  Widget _buildBankAccountCard(BankAccount account) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.blue.withAlpha(30),
            borderRadius: BorderRadius.circular(8),
          ),
          child: account.bankLogoUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: account.bankLogoUrl!,
                    fit: BoxFit.contain,
                    errorWidget: (_, __, ___) =>
                        const Icon(Icons.account_balance, color: Colors.blue),
                  ),
                )
              : const Icon(Icons.account_balance, color: Colors.blue),
        ),
        title: Text(
          account.accountName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(account.bankName),
            Text(
              account.accountNumber,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (account.isDefault)
              const Chip(
                label: Text('Mặc định'),
                backgroundColor: Colors.green,
                labelStyle: TextStyle(color: Colors.white, fontSize: 11),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            PopupMenuButton(
              itemBuilder: (context) => [
                if (Provider.of<PermissionProvider>(context, listen: false).canEdit('CashTransaction'))
                const PopupMenuItem(
                  value: 'edit',
                  child: ListTile(
                    leading: Icon(Icons.edit),
                    title: Text('Sửa'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (!account.isDefault)
                  const PopupMenuItem(
                    value: 'default',
                    child: ListTile(
                      leading: Icon(Icons.star),
                      title: Text('Đặt mặc định'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                const PopupMenuItem(
                  value: 'qr',
                  child: ListTile(
                    leading: Icon(Icons.qr_code_2),
                    title: Text('Xem QR'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                if (Provider.of<PermissionProvider>(context, listen: false).canDelete('CashTransaction'))
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete, color: Colors.red),
                    title: Text('Xóa', style: TextStyle(color: Colors.red)),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
              onSelected: (value) async {
                switch (value) {
                  case 'edit':
                    _showBankAccountForm(account);
                    break;
                  case 'default':
                    await _apiService.setDefaultBankAccount(account.id);
                    _loadBankAccounts();
                    break;
                  case 'qr':
                    _showBankQRDialog(account);
                    break;
                  case 'delete':
                    _deleteBankAccount(account);
                    break;
                }
              },
            ),
          ],
        ),
        onTap: () => _showBankAccountForm(account),
      ),
    );
  }

  Future<void> _deleteBankAccount(BankAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa tài khoản "${account.accountName}"?'),
        actions: [
          AppDialogActions.delete(
            onCancel: () => Navigator.pop(context, false),
            onConfirm: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final result = await _apiService.deleteBankAccount(account.id);
      if (result['isSuccess'] == true && mounted) {
        appNotification.showSuccess(
          title: 'Thành công',
          message: 'Đã xóa tài khoản',
        );
        _loadBankAccounts();
      }
    }
  }

  void _showBankQRDialog(BankAccount account) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(account.accountName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CachedNetworkImage(
              imageUrl: account.generateVietQRUrl(),
              width: 250,
              height: 250,
              placeholder: (_, __) => const SizedBox(
                width: 250,
                height: 250,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              account.bankName,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(account.accountNumber),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildSummaryView() {
    if (_summary == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary cards
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'Thu nhập',
                  _summary!.totalIncome,
                  Colors.green,
                  Icons.arrow_downward,
                  '${_summary!.incomeTransactions} giao dịch',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  'Chi phí',
                  _summary!.totalExpense,
                  Colors.red,
                  Icons.arrow_upward,
                  '${_summary!.expenseTransactions} giao dịch',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildSummaryCard(
            'Số dư',
            _summary!.balance,
            _summary!.balance >= 0 ? Colors.blue : Colors.orange,
            _summary!.balance >= 0 ? Icons.trending_up : Icons.trending_down,
            'Tổng ${_summary!.totalTransactions} giao dịch',
          ),
          const SizedBox(height: 24),

          // Income by category
          if (_summary!.incomeByCategory.isNotEmpty) ...[
            const Text(
              'Thu nhập theo danh mục',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._summary!.incomeByCategory.map((c) => _buildCategorySummaryTile(c, Colors.green)),
            const SizedBox(height: 24),
          ],

          // Expense by category
          if (_summary!.expenseByCategory.isNotEmpty) ...[
            const Text(
              'Chi phí theo danh mục',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ..._summary!.expenseByCategory.map((c) => _buildCategorySummaryTile(c, Colors.red)),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    double amount,
    Color color,
    IconData icon,
    String subtitle,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _currencyFormat.format(amount),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategorySummaryTile(CategorySummary category, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircularProgressIndicator(
          value: category.percentage / 100,
          backgroundColor: Colors.grey[200],
          valueColor: AlwaysStoppedAnimation(color),
          strokeWidth: 3,
        ),
        title: Text(category.categoryName),
        subtitle: Text('${category.count} giao dịch'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _currencyFormat.format(category.amount),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              '${category.percentage.toStringAsFixed(1)}%',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== DIALOGS ====================

class _TransactionFormDialog extends StatefulWidget {
  final CashTransaction? transaction;
  final List<TransactionCategory> categories;
  final List<BankAccount> bankAccounts;
  final VoidCallback onSaved;

  const _TransactionFormDialog({
    this.transaction,
    required this.categories,
    required this.bankAccounts,
    required this.onSaved,
  });

  @override
  State<_TransactionFormDialog> createState() => _TransactionFormDialogState();
}

class _TransactionFormDialogState extends State<_TransactionFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _contactNameController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _noteController = TextEditingController();

  CashTransactionType _type = CashTransactionType.income;
  String? _categoryId;
  PaymentMethodType _paymentMethod = PaymentMethodType.cash;
  String? _bankAccountId;
  DateTime _transactionDate = DateTime.now();
  bool _isPaid = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.transaction != null) {
      final t = widget.transaction!;
      _type = t.type;
      _categoryId = t.categoryId;
      _amountController.text = t.amount.toStringAsFixed(0);
      _descriptionController.text = t.description;
      _paymentMethod = t.paymentMethod;
      _bankAccountId = t.bankAccountId;
      _transactionDate = t.transactionDate;
      _contactNameController.text = t.contactName ?? '';
      _contactPhoneController.text = t.contactPhone ?? '';
      _noteController.text = t.internalNote ?? '';
      _isPaid = t.isPaid;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _contactNameController.dispose();
    _contactPhoneController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  List<TransactionCategory> get _filteredCategories =>
      widget.categories.where((c) => c.type == _type).toList();

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoryId == null) {
      appNotification.showWarning(title: 'Thiếu thông tin', message: 'Vui lòng chọn danh mục');
      return;
    }

    setState(() => _isLoading = true);

    final data = {
      'type': _type.value,
      'categoryId': _categoryId,
      'amount': double.parse(_amountController.text.replaceAll(RegExp(r'[^\d]'), '')),
      'transactionDate': _transactionDate.toIso8601String(),
      'description': _descriptionController.text,
      'paymentMethod': _paymentMethod.value,
      if (_bankAccountId != null) 'bankAccountId': _bankAccountId,
      if (_contactNameController.text.isNotEmpty) 'contactName': _contactNameController.text,
      if (_contactPhoneController.text.isNotEmpty) 'contactPhone': _contactPhoneController.text,
      if (_noteController.text.isNotEmpty) 'internalNote': _noteController.text,
      'isPaid': _isPaid,
    };

    final result = widget.transaction == null
        ? await _apiService.createCashTransaction(data)
        : await _apiService.updateCashTransaction(widget.transaction!.id, data);

    setState(() => _isLoading = false);

    if (result['isSuccess'] == true && mounted) {
      Navigator.pop(context);
      widget.onSaved();
      appNotification.showSuccess(
        title: 'Thành công',
        message: widget.transaction == null ? 'Đã tạo giao dịch' : 'Đã cập nhật giao dịch',
      );
    } else if (mounted) {
      appNotification.showError(
        title: 'Lỗi',
        message: result['message'] ?? 'Có lỗi xảy ra',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final dialogTitle = widget.transaction == null ? 'Thêm giao dịch' : 'Sửa giao dịch';

    final formBody = Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Transaction type toggle
          SegmentedButton<CashTransactionType>(
                  segments: CashTransactionType.values
                      .map((t) => ButtonSegment(
                            value: t,
                            label: Text(t.label),
                            icon: Icon(
                              t == CashTransactionType.income
                                  ? Icons.arrow_downward
                                  : Icons.arrow_upward,
                              color: t == CashTransactionType.income
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ))
                      .toList(),
                  selected: {_type},
                  onSelectionChanged: (v) => setState(() {
                    _type = v.first;
                    _categoryId = null;
                  }),
                ),
                const SizedBox(height: 16),

                // Category dropdown
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Danh mục *',
                    prefixIcon: Icon(Icons.category),
                  ),
                  initialValue: _categoryId,
                  items: _filteredCategories
                      .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _categoryId = v),
                  validator: (v) => v == null ? 'Chọn danh mục' : null,
                ),
                const SizedBox(height: 16),

                // Amount
                TextFormField(
                  controller: _amountController,
                  decoration: const InputDecoration(
                    labelText: 'Số tiền *',
                    prefixIcon: Icon(Icons.attach_money),
                    suffixText: 'đ',
                  ),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    _ThousandsSeparatorInputFormatter(),
                  ],
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Nhập số tiền';
                    final amount = double.tryParse(v.replaceAll(RegExp(r'[^\d]'), ''));
                    if (amount == null || amount <= 0) return 'Số tiền không hợp lệ';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Description
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Mô tả *',
                    prefixIcon: Icon(Icons.description),
                  ),
                  maxLines: 2,
                  validator: (v) => v?.isEmpty ?? true ? 'Nhập mô tả' : null,
                ),
                const SizedBox(height: 16),

                // Transaction date
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today),
                  title: const Text('Ngày giao dịch'),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(_transactionDate)),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _transactionDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 30)),
                    );
                    if (date != null) setState(() => _transactionDate = date);
                  },
                ),
                const SizedBox(height: 16),

                // Payment method
                DropdownButtonFormField<PaymentMethodType>(
                  decoration: const InputDecoration(
                    labelText: 'Phương thức thanh toán',
                    prefixIcon: Icon(Icons.payment),
                  ),
                  initialValue: _paymentMethod,
                  items: PaymentMethodType.values
                      .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                      .toList(),
                  onChanged: (v) => setState(() => _paymentMethod = v!),
                ),
                const SizedBox(height: 16),

                // Bank account (if bank transfer or VietQR)
                if (_paymentMethod == PaymentMethodType.bankTransfer ||
                    _paymentMethod == PaymentMethodType.vietQR) ...[
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Tài khoản ngân hàng',
                      prefixIcon: Icon(Icons.account_balance),
                    ),
                    initialValue: _bankAccountId,
                    items: widget.bankAccounts
                        .map((a) => DropdownMenuItem(
                              value: a.id,
                              child: Text('${a.bankShortName ?? a.bankName} - ${a.accountNumber}'),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _bankAccountId = v),
                  ),
                  const SizedBox(height: 16),
                ],

                // Contact info
                ExpansionTile(
                  title: const Text('Thông tin liên hệ'),
                  tilePadding: EdgeInsets.zero,
                  children: [
                    TextFormField(
                      controller: _contactNameController,
                      decoration: const InputDecoration(
                        labelText: 'Tên liên hệ',
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _contactPhoneController,
                      decoration: const InputDecoration(
                        labelText: 'Số điện thoại',
                        prefixIcon: Icon(Icons.phone),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _noteController,
                      decoration: const InputDecoration(
                        labelText: 'Ghi chú nội bộ',
                        prefixIcon: Icon(Icons.note),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Is paid
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Đã thanh toán'),
                  value: _isPaid,
                  onChanged: (v) => setState(() => _isPaid = v),
                ),
              ],
            ),
          );

    if (isMobile) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(dialogTitle),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  onPressed: _isLoading ? null : _save,
                  child: _isLoading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(widget.transaction == null ? 'Tạo' : 'Lưu'),
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: formBody,
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(dialogTitle),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(child: formBody),
      ),
      actions: [
        AppDialogActions(
          onConfirm: _isLoading ? null : _save,
          confirmLabel: widget.transaction == null ? 'Tạo' : 'Lưu',
          isLoading: _isLoading,
        ),
      ],
    );
  }
}

class _ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    final number = int.tryParse(newValue.text.replaceAll('.', ''));
    if (number == null) return oldValue;

    final formatted = NumberFormat('#,###', 'vi_VN').format(number);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _CategoryFormDialog extends StatefulWidget {
  final TransactionCategory? category;
  final VoidCallback onSaved;

  const _CategoryFormDialog({
    this.category,
    required this.onSaved,
  });

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  CashTransactionType _type = CashTransactionType.income;
  String _icon = 'category';
  bool _isLoading = false;

  final _icons = [
    'sell', 'work', 'savings', 'card_giftcard', 'trending_up',
    'shopping_cart', 'payments', 'home', 'local_gas_station',
    'bolt', 'phone', 'restaurant', 'emoji_transportation',
    'health_and_safety', 'school', 'more_horiz', 'category',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.category != null) {
      final c = widget.category!;
      _nameController.text = c.name;
      _descriptionController.text = c.description ?? '';
      _type = c.type;
      _icon = c.icon ?? 'category';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final data = {
      'name': _nameController.text,
      'type': _type.value,
      'icon': _icon,
      if (_descriptionController.text.isNotEmpty) 'description': _descriptionController.text,
    };

    final result = widget.category == null
        ? await _apiService.createTransactionCategory(data)
        : await _apiService.updateTransactionCategory(widget.category!.id, data);

    setState(() => _isLoading = false);

    if (result['isSuccess'] == true && mounted) {
      Navigator.pop(context);
      widget.onSaved();
      appNotification.showSuccess(
        title: 'Thành công',
        message: widget.category == null ? 'Đã tạo danh mục' : 'Đã cập nhật danh mục',
      );
    } else if (mounted) {
      appNotification.showError(
        title: 'Lỗi',
        message: result['message'] ?? 'Có lỗi xảy ra',
      );
    }
  }

  IconData _getIcon(String name) {
    switch (name) {
      case 'sell': return Icons.sell;
      case 'work': return Icons.work;
      case 'savings': return Icons.savings;
      case 'card_giftcard': return Icons.card_giftcard;
      case 'trending_up': return Icons.trending_up;
      case 'shopping_cart': return Icons.shopping_cart;
      case 'payments': return Icons.payments;
      case 'home': return Icons.home;
      case 'local_gas_station': return Icons.local_gas_station;
      case 'bolt': return Icons.bolt;
      case 'phone': return Icons.phone;
      case 'restaurant': return Icons.restaurant;
      case 'emoji_transportation': return Icons.emoji_transportation;
      case 'health_and_safety': return Icons.health_and_safety;
      case 'school': return Icons.school;
      case 'more_horiz': return Icons.more_horiz;
      default: return Icons.category;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final dialogTitle = widget.category == null ? 'Thêm danh mục' : 'Sửa danh mục';

    final formBody = Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Type toggle
          SegmentedButton<CashTransactionType>(
                segments: CashTransactionType.values
                    .map((t) => ButtonSegment(value: t, label: Text(t.label)))
                    .toList(),
                selected: {_type},
                onSelectionChanged: (v) => setState(() => _type = v.first),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Tên danh mục *',
                  prefixIcon: Icon(Icons.label),
                ),
                validator: (v) => v?.isEmpty ?? true ? 'Nhập tên danh mục' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Mô tả',
                  prefixIcon: Icon(Icons.description),
                ),
              ),
              const SizedBox(height: 16),

              // Icon selector
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Biểu tượng:'),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _icons.map((name) {
                  final isSelected = _icon == name;
                  return InkWell(
                    onTap: () => setState(() => _icon = name),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Colors.grey.withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                        border: isSelected
                            ? Border.all(color: Theme.of(context).colorScheme.primary)
                            : null,
                      ),
                      child: Icon(_getIcon(name), size: 24),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );

    if (isMobile) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(dialogTitle),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  onPressed: _isLoading ? null : _save,
                  child: _isLoading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(widget.category == null ? 'Tạo' : 'Lưu'),
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: formBody,
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(dialogTitle),
      content: SizedBox(
        width: 350,
        child: SingleChildScrollView(child: formBody),
      ),
      actions: [
        AppDialogActions(
          onConfirm: _isLoading ? null : _save,
          confirmLabel: widget.category == null ? 'Tạo' : 'Lưu',
          isLoading: _isLoading,
        ),
      ],
    );
  }
}

class _BankAccountFormDialog extends StatefulWidget {
  final BankAccount? account;
  final List<VietQRBank> vietQRBanks;
  final VoidCallback onSaved;

  const _BankAccountFormDialog({
    this.account,
    required this.vietQRBanks,
    required this.onSaved,
  });

  @override
  State<_BankAccountFormDialog> createState() => _BankAccountFormDialogState();
}

class _BankAccountFormDialogState extends State<_BankAccountFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();
  final _accountNameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _noteController = TextEditingController();

  String? _selectedBankCode;
  bool _isDefault = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.account != null) {
      final a = widget.account!;
      _accountNameController.text = a.accountName;
      _accountNumberController.text = a.accountNumber;
      _selectedBankCode = a.bankCode;
      _noteController.text = a.note ?? '';
      _isDefault = a.isDefault;
    }
  }

  @override
  void dispose() {
    _accountNameController.dispose();
    _accountNumberController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  VietQRBank? get _selectedBank =>
      widget.vietQRBanks.firstWhere(
        (b) => b.bin == _selectedBankCode,
        orElse: () => widget.vietQRBanks.first,
      );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBankCode == null) {
      appNotification.showWarning(title: 'Thiếu thông tin', message: 'Vui lòng chọn ngân hàng');
      return;
    }

    setState(() => _isLoading = true);

    final bank = _selectedBank!;
    final data = {
      'accountName': _accountNameController.text,
      'accountNumber': _accountNumberController.text,
      'bankCode': bank.bin,
      'bankName': bank.name,
      'bankShortName': bank.shortName,
      'bankLogoUrl': bank.logoUrl,
      'isDefault': _isDefault,
      if (_noteController.text.isNotEmpty) 'note': _noteController.text,
    };

    final result = widget.account == null
        ? await _apiService.createBankAccount(data)
        : await _apiService.updateBankAccount(widget.account!.id, data);

    setState(() => _isLoading = false);

    if (result['isSuccess'] == true && mounted) {
      Navigator.pop(context);
      widget.onSaved();
      appNotification.showSuccess(
        title: 'Thành công',
        message: widget.account == null ? 'Đã tạo tài khoản' : 'Đã cập nhật tài khoản',
      );
    } else if (mounted) {
      appNotification.showError(
        title: 'Lỗi',
        message: result['message'] ?? 'Có lỗi xảy ra',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final dialogTitle = widget.account == null ? 'Thêm tài khoản' : 'Sửa tài khoản';

    final formBody = Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Bank selector
          DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  labelText: 'Ngân hàng *',
                  prefixIcon: Icon(Icons.account_balance),
                ),
                initialValue: _selectedBankCode,
                items: widget.vietQRBanks
                    .map((b) => DropdownMenuItem(
                          value: b.bin,
                          child: Row(
                            children: [
                              if (b.logoUrl.isNotEmpty)
                                CachedNetworkImage(
                                  imageUrl: b.logoUrl,
                                  width: 24,
                                  height: 24,
                                  errorWidget: (_, __, ___) => const Icon(Icons.account_balance),
                                ),
                              const SizedBox(width: 8),
                              Expanded(child: Text(b.shortName)),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selectedBankCode = v),
                validator: (v) => v == null ? 'Chọn ngân hàng' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _accountNameController,
                decoration: const InputDecoration(
                  labelText: 'Tên chủ tài khoản *',
                  prefixIcon: Icon(Icons.person),
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (v) => v?.isEmpty ?? true ? 'Nhập tên chủ tài khoản' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _accountNumberController,
                decoration: const InputDecoration(
                  labelText: 'Số tài khoản *',
                  prefixIcon: Icon(Icons.numbers),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Nhập số tài khoản';
                  if (v.length < 6) return 'Số tài khoản không hợp lệ';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _noteController,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú',
                  prefixIcon: Icon(Icons.note),
                ),
              ),
              const SizedBox(height: 16),

              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Tài khoản mặc định'),
                subtitle: const Text('Sử dụng khi tạo mã VietQR'),
                value: _isDefault,
                onChanged: (v) => setState(() => _isDefault = v),
              ),
            ],
          ),
        );

    if (isMobile) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(dialogTitle),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  onPressed: _isLoading ? null : _save,
                  child: _isLoading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(widget.account == null ? 'Tạo' : 'Lưu'),
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: formBody,
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(dialogTitle),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(child: formBody),
      ),
      actions: [
        AppDialogActions(
          onConfirm: _isLoading ? null : _save,
          confirmLabel: widget.account == null ? 'Tạo' : 'Lưu',
          isLoading: _isLoading,
        ),
      ],
    );
  }
}

class _VietQRDialog extends StatefulWidget {
  final CashTransaction transaction;
  final List<BankAccount> bankAccounts;

  const _VietQRDialog({
    required this.transaction,
    required this.bankAccounts,
  });

  @override
  State<_VietQRDialog> createState() => _VietQRDialogState();
}

class _VietQRDialogState extends State<_VietQRDialog> {
  late BankAccount _selectedAccount;
  String? _qrUrl;

  @override
  void initState() {
    super.initState();
    _selectedAccount = widget.bankAccounts.firstWhere(
      (a) => a.isDefault,
      orElse: () => widget.bankAccounts.first,
    );
    _generateQR();
  }

  void _generateQR() {
    setState(() {
      _qrUrl = _selectedAccount.generateVietQRUrl(
        amount: widget.transaction.amount,
        description: '${widget.transaction.transactionCode} ${widget.transaction.description}',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
    final isMobile = Responsive.isMobile(context);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Bank selector
        DropdownButton<String>(
            value: _selectedAccount.id,
            isExpanded: true,
            items: widget.bankAccounts
                .map((a) => DropdownMenuItem(
                      value: a.id,
                      child: Text('${a.bankShortName ?? a.bankName} - ${a.accountNumber}'),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() {
                  _selectedAccount = widget.bankAccounts.firstWhere((a) => a.id == v);
                });
                _generateQR();
              }
            },
          ),
          const SizedBox(height: 16),

          // QR Code
          if (_qrUrl != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: CachedNetworkImage(
                imageUrl: _qrUrl!,
                width: 250,
                height: 250,
                placeholder: (_, __) => const SizedBox(
                  width: 250,
                  height: 250,
                  child: Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (_, __, ___) => const SizedBox(
                  width: 250,
                  height: 250,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error, size: 48, color: Colors.red),
                        SizedBox(height: 8),
                        Text('Không thể tải mã QR'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),

          // Transaction info
          Text(
            currencyFormat.format(widget.transaction.amount),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.transaction.transactionCode,
            style: TextStyle(
              color: Colors.grey[600],
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _selectedAccount.accountName,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          Text(_selectedAccount.bankName),
          Text(
            _selectedAccount.accountNumber,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ],
      );

    if (isMobile) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Thanh toán VietQR'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: content,
          ),
        ),
      );
    }

    return AlertDialog(
      title: const Text('Thanh toán VietQR'),
      content: content,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({required this.icon, required this.label, required this.color, required this.onTap});

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
            Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
