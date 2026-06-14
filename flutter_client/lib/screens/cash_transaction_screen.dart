import '../utils/file_saver.dart' as file_saver;
import 'package:excel/excel.dart' as excel_lib;
import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import '../widgets/hrm_page_chrome.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models/cash_transaction.dart';
import '../models/fund_transfer.dart';
import '../widgets/loading_widget.dart';
import '../widgets/empty_state.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../widgets/notification_overlay.dart';
import '../utils/responsive_helper.dart';
import '../widgets/app_button.dart';
import '../widgets/hrm_responsive_list_layout.dart';
import '../widgets/app_scroll_safe.dart';

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
  bool _showMobileSummary = false;

  // Inline summary for transactions tab
  CashTransactionSummary? _inlineSummary;
  bool _isSummaryLoading = false;

  // Chuyển quỹ
  String _viewMode = 'transactions';
  List<FundTransfer> _fundTransfers = [];
  List<FundBalance> _fundBalances = [];
  bool _isFundLoading = false;

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
        final firstThis = DateTime(now.year, now.month, 1);
        final lastDayPrev = firstThis.subtract(const Duration(days: 1));
        return DateTimeRange(
          start: DateTime(lastDayPrev.year, lastDayPrev.month, 1),
          end: DateTime(lastDayPrev.year, lastDayPrev.month, lastDayPrev.day,
              23, 59, 59));
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
        _loadFundTransfers(),
        _loadFundBalances(),
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
    await _apiService.repairTransactionCategoryEncoding();
    // Đồng bộ đủ danh mục hệ thống Thu + Chi (bổ sung thiếu, không chỉ khi rỗng).
    await _apiService.initDefaultTransactionCategories();

    final result = await _apiService.getTransactionCategories();
    if (result['isSuccess'] == true && result['data'] != null) {
      setState(() {
        _categories = _flattenTransactionCategories(result['data'] as List?);
      });
    }
  }

  List<TransactionCategory> _flattenTransactionCategories(List? raw) {
    if (raw == null) return [];
    final out = <TransactionCategory>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final cat = TransactionCategory.fromJson(Map<String, dynamic>.from(item));
      out.add(cat);
      for (final sub in cat.subCategories) {
        out.add(sub);
      }
    }
    return out;
  }

  Future<void> _loadFundTransfers() async {
    if (mounted) setState(() => _isFundLoading = true);
    try {
      final range = _selectedDateRange;
      final result = await _apiService.getFundTransfers(
        fromDate: range.start,
        toDate: range.end,
        pageSize: 100,
      );
      if (result['isSuccess'] == true && result['data'] != null) {
        final data = result['data'];
        final items = data is List
            ? data
            : (data is Map && data['items'] is List ? data['items'] : []);
        if (mounted) {
          setState(() {
            _fundTransfers = (items as List?)
                    ?.map((e) =>
                        FundTransfer.fromJson(Map<String, dynamic>.from(e as Map)))
                    .toList() ??
                [];
          });
        }
      }
    } finally {
      if (mounted) setState(() => _isFundLoading = false);
    }
  }

  Future<void> _loadFundBalances() async {
    final result = await _apiService.getFundBalances();
    if (result['isSuccess'] == true && result['data'] is List) {
      setState(() {
        _fundBalances = (result['data'] as List)
            .map((e) => FundBalance.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      });
    }
  }

  void _switchViewMode(String mode) {
    if (_viewMode == mode) return;
    setState(() => _viewMode = mode);
    if (mode == 'transfers') {
      _loadFundTransfers();
      _loadFundBalances();
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
    if (_viewMode == 'transfers') {
      _loadFundTransfers();
    } else {
      _loadTransactions();
      _loadInlineSummary();
    }
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
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) => _CategoryFormDialog(
        category: category,
        onSaved: _loadCategories,
      ),
    );
  }

  void _openCategoryFormFromSheet([TransactionCategory? category]) {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showCategoryForm(category);
    });
  }

  void _showBankAccountForm([BankAccount? account]) {
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) => _BankAccountFormDialog(
        account: account,
        vietQRBanks: _vietQRBanks,
        onSaved: _loadBankAccounts,
      ),
    );
  }

  void _openBankAccountFormFromSheet([BankAccount? account]) {
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showBankAccountForm(account);
    });
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
      builder: (context) => ScrollableAlertDialog(
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
      backgroundColor: HrmPageChrome.background,
      appBar: AppBar(
        title: const Text('Quản lý Thu Chi', overflow: TextOverflow.ellipsis, maxLines: 1),
        actions: [
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
          : _viewMode == 'transfers'
              ? _buildFundTransfersTab()
              : _buildTransactionsTab(),
      floatingActionButton: Responsive.isMobile(context) &&
              Provider.of<PermissionProvider>(context, listen: false).canCreate('CashTransaction')
          ? FloatingActionButton.extended(
              onPressed: () => _viewMode == 'transfers'
                  ? _showFundTransferForm()
                  : _showTransactionForm(),
              icon: Icon(_viewMode == 'transfers' ? Icons.swap_horiz : Icons.add),
              label: Text(_viewMode == 'transfers' ? 'Chuyển quỹ' : 'Thu/Chi'),
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  void _showCategoryManagement() {
    showAppSheet(
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
                  if (Provider.of<PermissionProvider>(context, listen: false)
                      .canCreate('CashTransaction'))
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => _openCategoryFormFromSheet(),
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
    showAppSheet(
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
                  if (Provider.of<PermissionProvider>(context, listen: false)
                      .canCreate('CashTransaction'))
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => _openBankAccountFormFromSheet(),
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
    final canCreate = Provider.of<PermissionProvider>(context, listen: false)
        .canCreate('CashTransaction');
    return HrmResponsiveListLayout(
      fabAware: isMobile && canCreate,
      extendedFab: true,
      headerSections: _cashTransactionsHeaderSections(isMobile),
      desktopBody: Column(
        children: [
          Expanded(child: _buildTransactionList()),
          _buildPaginationControls(),
        ],
      ),
      mobileSlivers: (_) => _cashTransactionsMobileSlivers(),
    );
  }

  Widget _buildViewModeBar() {
    final isMobile = Responsive.isMobile(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(isMobile ? 12 : 16, 8, isMobile ? 12 : 16, 0),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(
            value: 'transactions',
            label: Text('Thu / Chi'),
            icon: Icon(Icons.receipt_long, size: 18),
          ),
          ButtonSegment(
            value: 'transfers',
            label: Text('Chuyển quỹ'),
            icon: Icon(Icons.swap_horiz, size: 18),
          ),
        ],
        selected: {_viewMode},
        onSelectionChanged: (s) => _switchViewMode(s.first),
      ),
    );
  }

  Widget _buildFundTransfersTab() {
    final isMobile = Responsive.isMobile(context);
    final canCreate = Provider.of<PermissionProvider>(context, listen: false)
        .canCreate('CashTransaction');
    return HrmResponsiveListLayout(
      fabAware: isMobile && canCreate,
      extendedFab: true,
      headerSections: [
        _buildViewModeBar(),
        _buildTransferFilterBar(),
        _buildFundBalancesRow(),
      ],
      desktopBody: _buildFundTransferList(),
      mobileSlivers: (_) => _fundTransfersMobileSlivers(),
    );
  }

  Widget _buildTransferFilterBar() {
    final isMobile = Responsive.isMobile(context);
    final dropdownWidth = isMobile ? null : 160.0;

    final dateDropdown = DropdownButtonFormField<String>(
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

    final actionButtons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (Provider.of<PermissionProvider>(context, listen: false).canCreate('CashTransaction'))
          FilledButton.icon(
            onPressed: _showFundTransferForm,
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Chuyển quỹ'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
      ],
    );

    if (isMobile) {
      return HrmFilterBar(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        children: [
          dateDropdown,
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [actionButtons]),
        ],
      );
    }

    return HrmFilterBar(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: [
        Row(
          children: [
            SizedBox(width: dropdownWidth, child: dateDropdown),
            const Spacer(),
            actionButtons,
          ],
        ),
      ],
    );
  }

  Widget _buildFundBalancesRow() {
    if (_fundBalances.isEmpty) return const SizedBox.shrink();

    final isMobile = Responsive.isMobile(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(isMobile ? 12 : 16, 4, isMobile ? 12 : 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet, size: 16, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Text('Số dư quỹ',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Colors.blue.shade700)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _fundBalances.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _buildFundBalanceCard(_fundBalances[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFundBalanceCard(FundBalance balance) {
    final color = balance.isCash ? Colors.green : Colors.indigo;
    return Container(
      width: 160,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            balance.isCash ? 'Tiền mặt' : (balance.bankShortName ?? balance.label),
            style: TextStyle(fontSize: 11, color: color.shade700, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            _currencyFormat.format(balance.balance),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color.shade800),
          ),
        ],
      ),
    );
  }

  Widget _buildFundTransferList() {
    if (_isFundLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_fundTransfers.isEmpty) {
      return const EmptyState(
        icon: Icons.swap_horiz,
        title: 'Chưa có phiếu chuyển quỹ',
        description: 'Nhấn "Chuyển quỹ" để chuyển tiền giữa các quỹ',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _fundTransfers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _buildFundTransferCard(_fundTransfers[i]),
    );
  }

  List<Widget> _fundTransfersMobileSlivers() {
    if (_isFundLoading) {
      return [
        const SliverFillRemaining(
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_fundTransfers.isEmpty) {
      return [
        HrmScrollSlivers.fillRemaining(
          child: const EmptyState(
            icon: Icons.swap_horiz,
            title: 'Chưa có phiếu chuyển quỹ',
            description: 'Nhấn "Chuyển quỹ" để chuyển tiền giữa các quỹ',
          ),
        ),
      ];
    }
    return HrmScrollSlivers.fromListViewBuilder(
      itemCount: _fundTransfers.length,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _buildFundTransferCard(_fundTransfers[i]),
      ),
    );
  }

  Widget _buildFundTransferCard(FundTransfer transfer) {
    final canDelete =
        Provider.of<PermissionProvider>(context, listen: false).canDelete('CashTransaction');

    return Container(
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
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    transfer.transferCode,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  DateFormat('dd/MM/yyyy').format(transfer.transferDate),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                if (canDelete) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                    tooltip: 'Xóa',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => _deleteFundTransfer(transfer),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    transfer.fromFundLabel,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, size: 18, color: Colors.blue.shade600),
                ),
                Expanded(
                  child: Text(
                    transfer.toFundLabel,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _currencyFormat.format(transfer.amount),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade800,
              ),
            ),
            if (transfer.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                transfer.description,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
            if (transfer.createdByUserName.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Tạo bởi: ${transfer.createdByUserName}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showFundTransferForm() {
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) => _FundTransferFormDialog(
        bankAccounts: _bankAccounts,
        fundBalances: _fundBalances,
        onSaved: () {
          _loadFundTransfers();
          _loadFundBalances();
        },
      ),
    );
  }

  Future<void> _deleteFundTransfer(FundTransfer transfer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa phiếu chuyển quỹ'),
        content: Text('Xóa phiếu ${transfer.transferCode}? Số dư quỹ sẽ được cập nhật lại.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await _apiService.deleteFundTransfer(transfer.id);
    if (result['isSuccess'] == true && mounted) {
      appNotification.showSuccess(title: 'Thành công', message: 'Đã xóa phiếu chuyển quỹ');
      _loadFundTransfers();
      _loadFundBalances();
    } else if (mounted) {
      appNotification.showError(title: 'Lỗi', message: result['message'] ?? 'Không thể xóa');
    }
  }

  List<Widget> _cashTransactionsHeaderSections(bool isMobile) => [
        _buildViewModeBar(),
        _buildFilterBar(),
        if (isMobile) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: InkWell(
              onTap: () =>
                  setState(() => _showMobileSummary = !_showMobileSummary),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.analytics_outlined,
                        size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 6),
                    Text('Tổng quan',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Colors.blue.shade700)),
                    const Spacer(),
                    Icon(
                        _showMobileSummary
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 20,
                        color: Colors.blue.shade700),
                  ],
                ),
              ),
            ),
          ),
          if (_showMobileSummary) _buildInlineSummaryRow(),
        ] else
          _buildInlineSummaryRow(),
      ];

  List<Widget> _cashTransactionsMobileSlivers() {
    if (_transactions.isEmpty) {
      return [
        HrmScrollSlivers.fillRemaining(
          child: const EmptyState(
            icon: Icons.receipt_long,
            title: 'Chưa có giao dịch',
            description: 'Nhấn nút + để thêm giao dịch thu/chi mới',
          ),
        ),
      ];
    }
    return HrmScrollSlivers.fromListViewBuilder(
      itemCount: _transactions.length,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          onPressed: () => _viewMode == 'transfers'
              ? _showFundTransferForm()
              : _showTransactionForm(),
          icon: Icon(_viewMode == 'transfers' ? Icons.swap_horiz : Icons.add, size: 18),
          label: Text(_viewMode == 'transfers' ? 'Chuyển quỹ' : 'Thu/Chi'),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
      ],
    );

    if (isMobile) {
      return HrmFilterBar(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
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
      );
    }

    return HrmFilterBar(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      children: [
        Row(
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
      ],
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

    Widget pendingIncomeCard = Card(
      color: Colors.teal.shade50,
      child: InkWell(
        onTap: () {
          setState(() => _statusFilter = CashTransactionStatus.waitingPayment);
          _onFiltersChanged();
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.hourglass_top, color: Colors.teal.shade700, size: 16),
                const SizedBox(width: 6),
                Text('Chờ thu',
                    style: TextStyle(
                        color: Colors.teal.shade700,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ]),
              const SizedBox(height: 4),
              Text(_currencyFormat.format(s.pendingIncomeAmount),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade700)),
              Text('${s.pendingIncomeCount} phiếu',
                  style: TextStyle(color: Colors.teal.shade400, fontSize: 11)),
            ],
          ),
        ),
      ),
    );

    Widget pendingExpenseCard = Card(
      color: Colors.amber.shade50,
      child: InkWell(
        onTap: () {
          setState(() => _statusFilter = CashTransactionStatus.waitingPayment);
          _onFiltersChanged();
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.payments_outlined,
                    color: Colors.amber.shade800, size: 16),
                const SizedBox(width: 6),
                Text('Chờ chi',
                    style: TextStyle(
                        color: Colors.amber.shade800,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ]),
              const SizedBox(height: 4),
              Text(_currencyFormat.format(s.pendingExpenseAmount),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade800)),
              Text('${s.pendingExpenseCount} phiếu',
                  style:
                      TextStyle(color: Colors.amber.shade600, fontSize: 11)),
            ],
          ),
        ),
      ),
    );

    final hasPending = s.pendingTransactions > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 500;
        final completedRow = narrow
            ? Column(
                children: [
                  incomeCard,
                  const SizedBox(height: 4),
                  expenseCard,
                  const SizedBox(height: 4),
                  balanceCard,
                ],
              )
            : Row(
                children: [
                  Expanded(child: incomeCard),
                  const SizedBox(width: 8),
                  Expanded(child: expenseCard),
                  const SizedBox(width: 8),
                  Expanded(child: balanceCard),
                ],
              );

        if (!hasPending) return completedRow;

        final pendingRow = narrow
            ? Column(
                children: [
                  pendingIncomeCard,
                  const SizedBox(height: 4),
                  pendingExpenseCard,
                ],
              )
            : Row(
                children: [
                  Expanded(child: pendingIncomeCard),
                  const SizedBox(width: 8),
                  Expanded(child: pendingExpenseCard),
                ],
              );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            completedRow,
            const SizedBox(height: 8),
            Text('Phiếu chờ thanh toán',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            pendingRow,
          ],
        );
      }),
    );
  }

  Future<void> _showPayTransactionDialog(CashTransaction transaction) async {
    var selectedMethod = transaction.paymentMethod;
    String? selectedBankAccountId = transaction.bankAccountId;
    final isIncome = transaction.type == CashTransactionType.income;
    final actionLabel = isIncome ? 'Thu tiền' : 'Thanh toán';
    final dialogTitle =
        isIncome ? 'Thu phiếu ${transaction.transactionCode}' : 'Chi phiếu ${transaction.transactionCode}';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final needsBank = selectedMethod == PaymentMethodType.bankTransfer ||
              selectedMethod == PaymentMethodType.vietQR;
          final storeAccounts = _bankAccounts.where((a) => a.isActive).toList();

          return ScrollableAlertDialog(
            title: Text(dialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(transaction.description,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(
                        _currencyFormat.format(transaction.amount),
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade800),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Phương thức thanh toán',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 8),
                ...PaymentMethodType.values
                    .where((m) => m != PaymentMethodType.other)
                    .map((method) => RadioListTile<PaymentMethodType>(
                          value: method,
                          // ignore: deprecated_member_use
                          groupValue: selectedMethod,
                          dense: true,
                          title: Row(
                            children: [
                              Icon(_getPaymentMethodIcon(method), size: 18),
                              const SizedBox(width: 8),
                              Text(method.label),
                            ],
                          ),
                          // ignore: deprecated_member_use
                          onChanged: (v) => setDialogState(() {
                            selectedMethod = v!;
                            if (v != PaymentMethodType.bankTransfer &&
                                v != PaymentMethodType.vietQR) {
                              selectedBankAccountId = null;
                            }
                          }),
                        )),
                if (needsBank) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: selectedBankAccountId,
                    decoration: const InputDecoration(
                      labelText: 'Tài khoản ngân hàng',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: storeAccounts
                        .map((a) => DropdownMenuItem(
                              value: a.id,
                              child: Text('${a.bankName} - ${a.accountNumber}'),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setDialogState(() => selectedBankAccountId = v),
                  ),
                ],
              ],
            ),
            actions: [
              AppDialogActions(
                onCancel: () => Navigator.pop(ctx, false),
                onConfirm: () {
                  if (needsBank &&
                      (selectedBankAccountId == null ||
                          selectedBankAccountId!.isEmpty)) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                          content: Text('Vui lòng chọn tài khoản ngân hàng')),
                    );
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                confirmLabel: actionLabel,
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || !mounted) return;

    final result = await _apiService.updateCashTransactionStatus(
      transaction.id,
      {
        'status': 'Completed',
        'isPaid': true,
        'paymentMethod': selectedMethod.apiName,
        if (selectedBankAccountId != null)
          'bankAccountId': selectedBankAccountId,
      },
    );

    if (result['isSuccess'] == true && mounted) {
      appNotification.showSuccess(
        title: 'Thành công',
        message: 'Đã $actionLabel: ${transaction.transactionCode}',
      );
      _loadTransactions();
      _loadInlineSummary();
      _loadSummary();
    } else if (mounted) {
      appNotification.showError(
        title: 'Lỗi',
        message: result['message'] ?? 'Có lỗi xảy ra',
      );
    }
  }

  void _showMobileTxActions(CashTransaction transaction) {
    final perms = Provider.of<PermissionProvider>(context, listen: false);
    final isIncome = transaction.type == CashTransactionType.income;
    final canPay = transaction.isAwaitingPayment &&
        (perms.canEdit('CashTransaction') || perms.canApprove('CashTransaction'));

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text(
                  transaction.description,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ),
              if (canPay)
                ListTile(
                  leading: Icon(
                    isIncome ? Icons.savings : Icons.payment,
                    color: Colors.green,
                  ),
                  title: Text(isIncome ? 'Thu tiền' : 'Thanh toán'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showPayTransactionDialog(transaction);
                  },
                ),
              if (perms.canEdit('CashTransaction'))
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.blue),
                  title: const Text('Sửa'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showTransactionForm(transaction);
                  },
                ),
              if (canPay)
                ListTile(
                  leading: const Icon(Icons.cancel, color: Colors.orange),
                  title: const Text('Hủy'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _updateTransactionStatus(
                        transaction, CashTransactionStatus.cancelled);
                  },
                ),
              if (transaction.paymentMethod == PaymentMethodType.vietQR ||
                  transaction.paymentMethod == PaymentMethodType.bankTransfer)
                ListTile(
                  leading: const Icon(Icons.qr_code_2, color: Colors.purple),
                  title: const Text('VietQR'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showVietQRDialog(transaction);
                  },
                ),
              if (perms.canDelete('CashTransaction'))
                ListTile(
                  leading: Icon(Icons.delete, color: Colors.red.shade700),
                  title: Text('Xóa',
                      style: TextStyle(color: Colors.red.shade700)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteTransaction(transaction);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateTransactionStatus(
      CashTransaction transaction, CashTransactionStatus newStatus) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
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

    final statusName = switch (newStatus) {
      CashTransactionStatus.completed => 'Completed',
      CashTransactionStatus.cancelled => 'Cancelled',
      CashTransactionStatus.waitingPayment => 'WaitingPayment',
      CashTransactionStatus.pending => 'Pending',
    };
    final result = await _apiService.updateCashTransactionStatus(
        transaction.id, {'status': statusName});
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
      onTap: () => _showMobileTxActions(transaction),
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
              if (transaction.isAwaitingPayment) ...[
                const SizedBox(height: 4),
                _buildStatusChip(transaction.displayStatus),
              ],
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
                _buildStatusChip(transaction.displayStatus),
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
                if (transaction.isAwaitingPayment) ...[
                  if (Provider.of<PermissionProvider>(context, listen: false)
                          .canEdit('CashTransaction') ||
                      Provider.of<PermissionProvider>(context, listen: false)
                          .canApprove('CashTransaction')) ...[
                    _ActionBtn(
                      icon: isIncome ? Icons.savings : Icons.payment,
                      label: isIncome ? 'Thu tiền' : 'Thanh toán',
                      color: Colors.green,
                      onTap: () => _showPayTransactionDialog(transaction),
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

  Future<void> _deleteCategory(TransactionCategory category) async {
    final isSystem = category.isSystem;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text(isSystem ? 'Ẩn danh mục' : 'Xóa danh mục'),
        content: Text(isSystem
            ? 'Danh mục hệ thống "${category.name}" sẽ được ẩn khỏi danh sách (không xóa hẳn).'
            : 'Xóa danh mục "${category.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isSystem ? 'Ẩn' : 'Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await _apiService.deleteTransactionCategory(category.id);
    if (result['isSuccess'] == true && mounted) {
      appNotification.showSuccess(
        title: 'Thành công',
        message: isSystem ? 'Đã ẩn danh mục' : 'Đã xóa danh mục',
      );
      _loadCategories();
    } else if (mounted) {
      appNotification.showError(
        title: 'Lỗi',
        message: result['message']?.toString() ?? 'Không thể xóa danh mục',
      );
    }
  }

  Widget _buildCategoryTile(TransactionCategory category, Color color) {
    final canEdit =
        Provider.of<PermissionProvider>(context, listen: false).canEdit('CashTransaction');
    final canDelete =
        Provider.of<PermissionProvider>(context, listen: false).canDelete('CashTransaction');

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
            if (canEdit)
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                onPressed: () => _openCategoryFormFromSheet(category),
                tooltip: 'Sửa',
              ),
            if (canDelete)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                onPressed: () => _deleteCategory(category),
                tooltip: category.isSystem ? 'Ẩn' : 'Xóa',
              ),
          ],
        ),
        onTap: canEdit ? () => _openCategoryFormFromSheet(category) : null,
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
      onTap: Provider.of<PermissionProvider>(context, listen: false).canEdit('CashTransaction')
          ? () => _showBankAccountForm(account)
          : null,
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
                    _openBankAccountFormFromSheet(account);
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
        onTap: Provider.of<PermissionProvider>(context, listen: false).canEdit('CashTransaction')
            ? () => _openBankAccountFormFromSheet(account)
            : null,
      ),
    );
  }

  Future<void> _deleteBankAccount(BankAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ScrollableAlertDialog(
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
      builder: (context) => ScrollableAlertDialog(
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

String? _defaultBankAccountId(List<BankAccount> accounts) {
  if (accounts.isEmpty) return null;
  final preferred = accounts.where((a) => a.isDefault).firstOrNull;
  return (preferred ?? accounts.first).id;
}

BankAccount _resolveBankAccountForTransaction(
  CashTransaction transaction,
  List<BankAccount> accounts,
) {
  if (accounts.isEmpty) {
    throw StateError('No bank accounts');
  }
  if (transaction.bankAccountId != null) {
    final linked = accounts.where((a) => a.id == transaction.bankAccountId).firstOrNull;
    if (linked != null) return linked;
  }
  final preferred = accounts.where((a) => a.isDefault).firstOrNull;
  return preferred ?? accounts.first;
}

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

  bool _needsBankAccount(PaymentMethodType method) =>
      method == PaymentMethodType.bankTransfer || method == PaymentMethodType.vietQR;

  void _onPaymentMethodChanged(PaymentMethodType method) {
    setState(() {
      _paymentMethod = method;
      if (_needsBankAccount(method)) {
        _bankAccountId ??= _defaultBankAccountId(widget.bankAccounts);
      } else {
        _bankAccountId = null;
      }
    });
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
    if (_needsBankAccount(_paymentMethod) && _bankAccountId == null) {
      appNotification.showWarning(
        title: 'Thiếu thông tin',
        message: 'Vui lòng chọn tài khoản ngân hàng',
      );
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
                  onChanged: (v) {
                    if (v != null) _onPaymentMethodChanged(v);
                  },
                ),
                const SizedBox(height: 16),

                // Bank account (if bank transfer or VietQR)
                if (_needsBankAccount(_paymentMethod)) ...[
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Tài khoản ngân hàng *',
                      prefixIcon: Icon(Icons.account_balance),
                    ),
                    initialValue: _bankAccountId,
                    items: widget.bankAccounts
                        .map((a) => DropdownMenuItem(
                              value: a.id,
                              child: Text(
                                '${a.bankShortName ?? a.bankName} - ${a.accountNumber}'
                                '${a.isDefault ? ' (Mặc định)' : ''}',
                              ),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _bankAccountId = v),
                    validator: (v) => v == null ? 'Chọn tài khoản ngân hàng' : null,
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

    return ScrollableAlertDialog(
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

    final data = widget.category == null
        ? <String, dynamic>{
            'name': _nameController.text.trim(),
            'type': _type.value,
            'icon': _icon,
            if (_descriptionController.text.isNotEmpty)
              'description': _descriptionController.text.trim(),
          }
        : <String, dynamic>{
            'name': _nameController.text.trim(),
            'icon': _icon,
            'sortOrder': widget.category!.sortOrder,
            'isActive': widget.category!.isActive,
            if (_descriptionController.text.isNotEmpty)
              'description': _descriptionController.text.trim(),
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

  Future<void> _delete() async {
    final category = widget.category;
    if (category == null) return;
    final isSystem = category.isSystem;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        title: Text(isSystem ? 'Ẩn danh mục' : 'Xóa danh mục'),
        content: Text(isSystem
            ? 'Danh mục hệ thống sẽ được ẩn khỏi danh sách.'
            : 'Xóa danh mục "${category.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isSystem ? 'Ẩn' : 'Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isLoading = true);
    final result = await _apiService.deleteTransactionCategory(category.id);
    setState(() => _isLoading = false);

    if (result['isSuccess'] == true && mounted) {
      Navigator.pop(context);
      widget.onSaved();
      appNotification.showSuccess(
        title: 'Thành công',
        message: isSystem ? 'Đã ẩn danh mục' : 'Đã xóa danh mục',
      );
    } else if (mounted) {
      appNotification.showError(
        title: 'Lỗi',
        message: result['message']?.toString() ?? 'Không thể xóa danh mục',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final isEdit = widget.category != null;
    final isSystem = widget.category?.isSystem == true;
    final canDelete = isEdit &&
        Provider.of<PermissionProvider>(context, listen: false)
            .canDelete('CashTransaction');
    final dialogTitle = widget.category == null ? 'Thêm danh mục' : 'Sửa danh mục';

    final formBody = Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isSystem)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Danh mục hệ thống: có thể đổi tên/mô tả/biểu tượng. Xóa sẽ ẩn khỏi danh sách.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ),
          if (!isEdit)
            SegmentedButton<CashTransactionType>(
                segments: CashTransactionType.values
                    .map((t) => ButtonSegment(value: t, label: Text(t.label)))
                    .toList(),
                selected: {_type},
                onSelectionChanged: (v) => setState(() => _type = v.first),
              ),
          if (!isEdit) const SizedBox(height: 16),

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
              if (canDelete)
                TextButton(
                  onPressed: _isLoading ? null : _delete,
                  child: Text(
                    isSystem ? 'Ẩn' : 'Xóa',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
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

    return ScrollableAlertDialog(
      title: Text(dialogTitle),
      content: SizedBox(
        width: 350,
        child: SingleChildScrollView(child: formBody),
      ),
      actions: [
        if (canDelete)
          TextButton(
            onPressed: _isLoading ? null : _delete,
            child: Text(
              isSystem ? 'Ẩn' : 'Xóa',
              style: const TextStyle(color: Colors.red),
            ),
          ),
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

    return ScrollableAlertDialog(
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
    _selectedAccount = _resolveBankAccountForTransaction(
      widget.transaction,
      widget.bankAccounts,
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
                      child: Text(
                        '${a.bankShortName ?? a.bankName} - ${a.accountNumber}'
                        '${a.isDefault ? ' (Mặc định)' : ''}',
                      ),
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

    return ScrollableAlertDialog(
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

const _cashFundKey = '__cash__';

class _FundTransferFormDialog extends StatefulWidget {
  final List<BankAccount> bankAccounts;
  final List<FundBalance> fundBalances;
  final VoidCallback onSaved;

  const _FundTransferFormDialog({
    required this.bankAccounts,
    required this.fundBalances,
    required this.onSaved,
  });

  @override
  State<_FundTransferFormDialog> createState() => _FundTransferFormDialogState();
}

class _FundTransferFormDialogState extends State<_FundTransferFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _noteController = TextEditingController();

  String _fromFund = _cashFundKey;
  String _toFund = '';
  DateTime _transferDate = DateTime.now();
  bool _isLoading = false;

  List<DropdownMenuItem<String>> get _fundOptions {
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem(value: _cashFundKey, child: Text('Tiền mặt')),
      ...widget.bankAccounts.map((a) {
        final label = '${a.bankShortName ?? a.bankName} - ${a.accountNumber}';
        return DropdownMenuItem(value: a.id, child: Text(label, overflow: TextOverflow.ellipsis));
      }),
    ];
    return items;
  }

  String? _balanceHint(String fundKey) {
    if (fundKey == _cashFundKey) {
      final cash = widget.fundBalances.where((b) => b.isCash).firstOrNull;
      if (cash != null) {
        return 'Số dư: ${NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(cash.balance)}';
      }
    } else {
      final bank = widget.fundBalances.where((b) => b.bankAccountId == fundKey).firstOrNull;
      if (bank != null) {
        return 'Số dư: ${NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(bank.balance)}';
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    if (widget.bankAccounts.isNotEmpty) {
      _toFund = widget.bankAccounts.first.id;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String? _fundIdToApi(String key) => key == _cashFundKey ? null : key;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _transferDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _transferDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_fromFund == _toFund) {
      appNotification.showError(title: 'Lỗi', message: 'Quỹ nguồn và quỹ đích phải khác nhau');
      return;
    }

    final amount = double.tryParse(_amountController.text.replaceAll('.', '')) ?? 0;
    if (amount <= 0) {
      appNotification.showError(title: 'Lỗi', message: 'Số tiền phải lớn hơn 0');
      return;
    }

    setState(() => _isLoading = true);

    final data = <String, dynamic>{
      'fromBankAccountId': _fundIdToApi(_fromFund),
      'toBankAccountId': _fundIdToApi(_toFund),
      'amount': amount,
      'transferDate': _transferDate.toIso8601String(),
      'description': _descriptionController.text.trim(),
      if (_noteController.text.trim().isNotEmpty) 'internalNote': _noteController.text.trim(),
    };

    final result = await _apiService.createFundTransfer(data);
    setState(() => _isLoading = false);

    if (result['isSuccess'] == true && mounted) {
      Navigator.pop(context);
      widget.onSaved();
      appNotification.showSuccess(title: 'Thành công', message: 'Đã tạo phiếu chuyển quỹ');
    } else if (mounted) {
      appNotification.showError(title: 'Lỗi', message: result['message'] ?? 'Có lỗi xảy ra');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final fromHint = _balanceHint(_fromFund);
    final toHint = _balanceHint(_toFund);

    final formBody = Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _fromFund,
            decoration: InputDecoration(
              labelText: 'Quỹ nguồn',
              helperText: fromHint,
              border: const OutlineInputBorder(),
            ),
            items: _fundOptions,
            onChanged: (v) {
              if (v != null) setState(() => _fromFund = v);
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _toFund.isEmpty ? null : _toFund,
            decoration: InputDecoration(
              labelText: 'Quỹ đích',
              helperText: toHint,
              border: const OutlineInputBorder(),
            ),
            items: _fundOptions,
            onChanged: (v) {
              if (v != null) setState(() => _toFund = v);
            },
            validator: (v) => v == null || v.isEmpty ? 'Chọn quỹ đích' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _amountController,
            decoration: const InputDecoration(
              labelText: 'Số tiền',
              border: OutlineInputBorder(),
              suffixText: 'đ',
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [_ThousandsSeparatorInputFormatter()],
            validator: (v) {
              final n = double.tryParse((v ?? '').replaceAll('.', '')) ?? 0;
              if (n <= 0) return 'Nhập số tiền hợp lệ';
              return null;
            },
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Ngày chuyển',
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.calendar_today),
              ),
              child: Text(DateFormat('dd/MM/yyyy').format(_transferDate)),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: 'Nội dung',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _noteController,
            decoration: const InputDecoration(
              labelText: 'Ghi chú nội bộ',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
        ],
      ),
    );

    if (isMobile) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Chuyển quỹ'),
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
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Tạo'),
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: formBody),
        ),
      );
    }

    return ScrollableAlertDialog(
      title: const Text('Chuyển quỹ'),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: formBody)),
      actions: [
        AppDialogActions(
          onConfirm: _isLoading ? null : _save,
          confirmLabel: 'Tạo',
          isLoading: _isLoading,
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
