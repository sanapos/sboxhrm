import 'package:excel/excel.dart' as excel_lib;
import '../utils/file_saver.dart' as file_saver;
import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/hrm.dart';
import '../models/employee.dart';
import '../models/cash_transaction.dart';
import '../services/api_service.dart';
import '../utils/number_formatter.dart';
import '../widgets/loading_widget.dart';
import '../widgets/empty_state.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/hrm_responsive_list_layout.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/safe_layout_widgets.dart';
import '../utils/responsive_helper.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/navigation_notifier.dart';
import '../widgets/hrm_pushed_screen_shell.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';
import 'package:zkteco_flutter_client/l10n/app_ui_locale.dart';
import '../design_system/design_system.dart';

class AdvanceRequestsScreen extends StatefulWidget {
  final String? highlightId;
  const AdvanceRequestsScreen({super.key, this.highlightId});

  @override
  State<AdvanceRequestsScreen> createState() => _AdvanceRequestsScreenState();
}

class _AdvanceRequestsScreenState extends State<AdvanceRequestsScreen> {
  final ApiService _apiService = ApiService();
  List<AdvanceRequest> _allRequests = [];
  List<Employee> _employees = [];
  bool _isLoading = true;
  Employee? _myEmployee; // loaded for employee-role users

  AppLocalizations get _l10n => AppLocalizations.of(context);

  // Filters
  AdvanceRequestStatus? _selectedStatus;
  String _selectedTimePreset = 'all';
  DateTime? _fromDate;
  DateTime? _toDate;
  String _searchQuery = '';
  Employee? _selectedEmployee;
  String? _selectedBranchId;
  List<Map<String, dynamic>> _branches = [];

  // Sorting
  String _sortColumn = 'requestDate';
  bool _sortAscending = false;

  // Mobile UI state
  bool _showMobileSummary = false;

  // Pagination
  int _currentPage = 1;
  int _itemsPerPage = 25;
  final List<int> _pageSizeOptions = [25, 50, 100, 200];

  final _currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');

  @override
  void initState() {
    super.initState();
    final sf = NavigationNotifier.advanceRequestsStatusFilter.value;
    if (sf >= 0 && sf < AdvanceRequestStatus.values.length) {
      _selectedStatus = AdvanceRequestStatus.values[sf];
    }
    NavigationNotifier.advanceRequestsStatusFilter.value = -1;
    _loadData();
    _loadEmployees();
    // Load own employee info for employee-role auto-selection in create dialog
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMyEmployee());
  }

  bool get _isEmployeeRole {
    final role = Provider.of<AuthProvider>(context, listen: false)
        .userRole
        .toLowerCase();
    return role == 'employee';
  }

  String? get _currentUserId =>
      Provider.of<AuthProvider>(context, listen: false).user?.id;

  bool get _isManagerOrAbove {
    final role = Provider.of<AuthProvider>(context, listen: false)
        .userRole
        .toLowerCase();
    return role == 'admin' ||
        role == 'manager' ||
        role == 'director' ||
        role == 'superadmin' ||
        role == 'departmenthead' ||
        role == 'agent';
  }

  bool _isOwnAdvance(AdvanceRequest request) =>
      _currentUserId != null &&
      request.employeeUserId == _currentUserId;

  bool _canCancelAdvance(AdvanceRequest request, PermissionProvider p) {
    if (request.status != AdvanceRequestStatus.pending) return false;
    if (_isOwnAdvance(request)) return true;
    return _isManagerOrAbove && p.canApprove('AdvanceRequests');
  }

  Future<void> _loadMyEmployee() async {
    try {
      final result = await _apiService.getMyEmployee();
      if (result['isSuccess'] == true && result['data'] != null && mounted) {
        setState(() {
          _myEmployee =
              Employee.fromJson(result['data'] as Map<String, dynamic>);
        });
      }
    } catch (e) {
      debugPrint('Error loading my employee: $e');
    }
  }

  Future<void> _loadEmployees() async {
    try {
      final employees = await _apiService.getEmployeesForSelect(pageSize: 500);
      if (mounted) {
        setState(() {
          _employees = employees.map((e) => Employee.fromJson(e)).toList();
        });
      }
      try {
        final br = await _apiService.getBranchesForSelect();
        final bd = br['data'];
        if (bd is List && mounted) {
          setState(() => _branches =
              bd.map((b) => Map<String, dynamic>.from(b as Map)).toList());
        }
      } catch (_) {}
    } catch (e) {
      debugPrint('Error loading employees: $e');
    }
  }

  // ==================== TIME PRESET ====================
  void _applyTimePreset(String preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    setState(() {
      _selectedTimePreset = preset;
      _currentPage = 1;
      switch (preset) {
        case 'today':
          _fromDate = today;
          _toDate = today
              .add(const Duration(days: 1))
              .subtract(const Duration(milliseconds: 1));
          break;
        case 'yesterday':
          _fromDate = today.subtract(const Duration(days: 1));
          _toDate = today.subtract(const Duration(milliseconds: 1));
          break;
        case 'this_week':
          _fromDate = today.subtract(Duration(days: today.weekday - 1));
          _toDate = now;
          break;
        case 'last_week':
          final startOfThisWeek =
              today.subtract(Duration(days: today.weekday - 1));
          _fromDate = startOfThisWeek.subtract(const Duration(days: 7));
          _toDate = startOfThisWeek.subtract(const Duration(milliseconds: 1));
          break;
        case 'this_month':
          _fromDate = DateTime(now.year, now.month, 1);
          _toDate = now;
          break;
        case 'last_month':
          final firstOfMonth = DateTime(now.year, now.month, 1);
          _fromDate = DateTime(now.year, now.month - 1, 1);
          _toDate = firstOfMonth.subtract(const Duration(milliseconds: 1));
          break;
        case 'custom':
          _pickCustomDateRange();
          return;
        case 'all':
        default:
          _fromDate = null;
          _toDate = null;
          break;
      }
    });
    _loadData();
  }

  Future<void> _pickCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _fromDate != null && _toDate != null
          ? DateTimeRange(start: _fromDate!, end: _toDate!)
          : null,
      locale: appUiLocale(),
    );
    if (picked != null) {
      setState(() {
        _selectedTimePreset = 'custom';
        _fromDate = picked.start;
        _toDate = DateTime(
            picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
        _currentPage = 1;
      });
      _loadData();
    }
  }

  // ==================== DATA LOADING ====================
  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final result = await _apiService.getAdvanceRequests(
        page: 1,
        pageSize: 500,
        status: _selectedStatus?.index,
        fromDate: _fromDate,
        toDate: _toDate,
      );

      if (result['isSuccess'] == true) {
        final data = result['data'];
        List<dynamic> items = [];
        if (data is Map && data['items'] != null) {
          items = data['items'] as List;
        } else if (data is List) {
          items = data;
        }

        setState(() {
          _allRequests = items.map((e) => AdvanceRequest.fromJson(e)).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading advance requests: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
      _maybeOpenHighlight();
      _maybeOpenAiCreate();
    }
  }

  bool _highlightOpened = false;
  void _maybeOpenHighlight() {
    if (_highlightOpened) return;
    final id = widget.highlightId ??
        NavigationNotifier.notificationHighlightId.value;
    NavigationNotifier.notificationHighlightId.value = null;
    if (id == null || id.isEmpty) return;
    AdvanceRequest? match;
    for (final r in _allRequests) {
      if (r.id == id) {
        match = r;
        break;
      }
    }
    if (match == null) return;
    _highlightOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showDetailDialog(match!);
    });
  }

  bool _aiCreateOpened = false;
  void _maybeOpenAiCreate() {
    if (_aiCreateOpened) return;
    if (!NavigationNotifier.takePendingAiOpenCreate('advance')) return;
    _aiCreateOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showCreateDialog();
    });
  }

  // ==================== FILTERED DATA ====================
  List<AdvanceRequest> get _filteredRequests {
    var list = _allRequests;
    if (_selectedBranchId != null) {
      final branchCodes = _employees
          .where((e) => e.branchId == _selectedBranchId)
          .map((e) => e.employeeCode)
          .toSet();
      list = list.where((r) => branchCodes.contains(r.employeeCode)).toList();
    }
    if (_selectedEmployee != null) {
      list = list
          .where((r) => r.employeeCode == _selectedEmployee!.employeeCode)
          .toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((r) {
        return r.employeeName.toLowerCase().contains(q) ||
            r.employeeCode.toLowerCase().contains(q);
      }).toList();
    }
    // Sort
    list.sort((a, b) {
      int cmp;
      switch (_sortColumn) {
        case 'amount':
          cmp = a.amount.compareTo(b.amount);
          break;
        case 'requestDate':
        default:
          cmp = a.requestDate.compareTo(b.requestDate);
      }
      return _sortAscending ? cmp : -cmp;
    });
    return list;
  }

  int? _getSortColumnIndex() {
    switch (_sortColumn) {
      case 'amount':
        return 3;
      case 'requestDate':
        return 7;
      default:
        return null;
    }
  }

  void _onSort(String column, bool ascending) {
    setState(() {
      _sortColumn = column;
      _sortAscending = ascending;
      _currentPage = 1;
    });
  }

  List<AdvanceRequest> get _pendingList => _filteredRequests
      .where((r) => r.status == AdvanceRequestStatus.pending)
      .toList();
  List<AdvanceRequest> get _waitingPaymentList => _filteredRequests
      .where((r) => r.status == AdvanceRequestStatus.approved && !r.isPaid)
      .toList();
  List<AdvanceRequest> get _rejectedList => _filteredRequests
      .where((r) => r.status == AdvanceRequestStatus.rejected)
      .toList();
  List<AdvanceRequest> get _paidList => _filteredRequests
      .where((r) => r.status == AdvanceRequestStatus.approved && r.isPaid)
      .toList();
  // Dùng payoutAmount (số tiền đã duyệt, fallback về số tiền yêu cầu khi
  // chưa duyệt) để tổng đúng số tiền thực tế chờ/đã thanh toán.
  double _sumAmount(List<AdvanceRequest> list) =>
      list.fold(0.0, (s, r) => s + r.payoutAmount);

  // ==================== ACTIONS ====================
  Future<void> _approveRequest(AdvanceRequest request, bool isApproved,
      {String? reason}) async {
    double? approvedAmount;
    if (isApproved) {
      approvedAmount = await _showApproveAmountDialog(request);
      if (approvedAmount == null) return;
    }

    final isPartial = isApproved && approvedAmount! < request.amount;

    // Luôn gửi số tiền duyệt (kể cả khi = số yêu cầu) để bước duyệt sau
    // trong quy trình đa cấp có thể ghi đè đúng số quản lý vừa xác nhận.
    final result = await _apiService.approveAdvanceRequest(
      requestId: request.id,
      isApproved: isApproved,
      rejectionReason: reason,
      approvedAmount: isApproved ? approvedAmount : null,
    );
    if (result['isSuccess'] == true) {
      appNotification.showSuccess(
        title: 'Thành công',
        message: isApproved
            ? (isPartial
                ? 'Đã duyệt ${_currencyFormat.format(approvedAmount)} (yêu cầu ban đầu ${_currencyFormat.format(request.amount)})'
                : _l10n.approvedMsg)
            : _l10n.rejectedMsg,
      );
      _loadData();
    } else {
      appNotification.showError(
          title: _l10n.error, message: result['message'] ?? 'Có lỗi xảy ra');
    }
  }

  /// Hiển thị dialog xác nhận duyệt với ô số tiền có thể sửa (cho phép quản
  /// lý duyệt thấp hơn số tiền nhân viên yêu cầu). Trả về số tiền đã xác
  /// nhận, hoặc null nếu người dùng hủy.
  Future<double?> _showApproveAmountDialog(AdvanceRequest request) async {
    // Ưu tiên số đã đề xuất ở bước duyệt trước (đa cấp), fallback số yêu cầu.
    final initialAmount = request.approvedAmount ?? request.amount;
    final amountController = TextEditingController(
        text: tr(NumberFormat('#,###').format(initialAmount)));
    String? errorText;

    return showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => ScrollableAlertDialog(
          title: Text(tr('Xác nhận duyệt ứng lương')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Nhân viên: ${request.employeeName} (${request.employeeCode})')),
              const SizedBox(height: 4),
              Text(tr('Số tiền yêu cầu: ${_currencyFormat.format(request.amount)}')),
              if (request.approvedAmount != null &&
                  request.approvedAmount != request.amount) ...[
                const SizedBox(height: 4),
                Text(tr('Đề xuất bước trước: ${_currencyFormat.format(request.approvedAmount!)}'),
                  style: TextStyle(color: Colors.orange.shade800, fontSize: 13),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                inputFormatters: [ThousandSeparatorFormatter()],
                decoration: InputDecoration(
                  labelText: tr('Số tiền duyệt *'),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.attach_money),
                  errorText: trN(errorText),
                  helperText: tr('Có thể duyệt thấp hơn số tiền yêu cầu (vd: YC 5tr → duyệt 3tr)'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(tr(_l10n.cancel))),
            FilledButton(
              onPressed: () {
                final parsed = parseFormattedNumber(amountController.text)
                    ?.toDouble();
                if (parsed == null || parsed <= 0) {
                  setDialogState(
                      () => errorText = 'Vui lòng nhập số tiền hợp lệ');
                  return;
                }
                if (parsed > request.amount) {
                  setDialogState(() => errorText =
                      'Không được vượt số tiền yêu cầu (${_currencyFormat.format(request.amount)})');
                  return;
                }
                Navigator.pop(ctx, parsed);
              },
              style: FilledButton.styleFrom(backgroundColor: HrmPageChrome.primaryNavy),
              child: Text(tr(_l10n.approveLabel),
                  style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _undoApprove(AdvanceRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(tr(_l10n.reverseApproval)),
        content: Text(tr('Bạn có chắc muốn hoàn duyệt yêu cầu này? Trạng thái sẽ quay lại "Chờ duyệt".')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr(_l10n.cancel))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text(tr(_l10n.reverseApproval)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await _apiService.undoApproveAdvanceRequest(request.id);
    if (result['isSuccess'] == true) {
      appNotification.showSuccess(
          title: 'Thành công', message: _l10n.reversedMsg);
      _loadData();
    } else {
      appNotification.showError(
          title: _l10n.error, message: result['message'] ?? 'Có lỗi xảy ra');
    }
  }

  Future<void> _payRequest(AdvanceRequest request) async {
    PaymentMethodType selectedMethod = PaymentMethodType.cash;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isMobile = Responsive.isMobile(ctx);

          final formContent = SingleChildScrollView(
            padding: isMobile ? const EdgeInsets.all(16) : EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.info.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.person,
                              size: 18, color: AppColors.info),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(tr(request.employeeName),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold))),
                        ],
                      ),
                      if (request.employeeCode.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(tr('${_l10n.employeeCode}: ${request.employeeCode}'),
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600])),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        tr(_currencyFormat.format(request.payoutAmount)),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                            color: AppColors.info),
                      ),
                      if (request.isPartiallyApproved)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(tr('Đã duyệt một phần (yêu cầu ban đầu: ${_currencyFormat.format(request.amount)})'),
                            style: TextStyle(
                                fontSize: 11, color: Colors.orange.shade800),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<PaymentMethodType>(
                  initialValue: selectedMethod,
                  decoration: InputDecoration(
                    labelText: tr(_l10n.paymentMethod),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.payment),
                  ),
                  items: PaymentMethodType.values
                      .where((m) => m != PaymentMethodType.other)
                      .map((m) => DropdownMenuItem(
                            value: m,
                            child: Row(
                              children: [
                                Icon(_getPaymentMethodIcon(m),
                                    size: 18, color: Colors.grey[700]),
                                const SizedBox(width: 8),
                                Text(tr(m.label)),
                              ],
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedMethod = v!),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: Colors.amber.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(tr('Xác nhận thanh toán sẽ tạo phiếu chi tự động trong thu chi.'),
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );

          if (isMobile) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(tr(_l10n.payAdvance)),
                    leading: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                  ),
                  body: formContent,
                  bottomNavigationBar: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(tr('Hủy'))),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green),
                          icon: const Icon(Icons.payment,
                              color: Colors.white, size: 18),
                          label: Text(tr('Thanh toán'),
                              style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return ScrollableAlertDialog(
            title: Text(tr(_l10n.payAdvance)),
            content: formContent,
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(tr('Hủy'))),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                icon: const Icon(Icons.payment, color: Colors.white, size: 18),
                label: Text(tr('Thanh toán'),
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true) return;

    final result = await _apiService.payAdvanceRequest(
      request.id,
      paymentMethod: selectedMethod.name,
    );
    if (result['isSuccess'] == true) {
      appNotification.showSuccess(
          title: 'Thành công', message: _l10n.paymentSuccess);
      _loadData();
    } else {
      appNotification.showError(
          title: _l10n.error, message: result['message'] ?? 'Có lỗi xảy ra');
    }
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

  void _showRejectDialog(AdvanceRequest request) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(tr(_l10n.rejectRequest)),
        content: SingleChildScrollView(
          child: TextField(
            controller: reasonController,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: tr(_l10n.rejectReason),
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr(_l10n.cancel))),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _approveRequest(request, false, reason: reasonController.text);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child:
                Text(tr(_l10n.reject), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ).then((_) => reasonController.dispose());
  }

  Future<void> _deleteRequest(AdvanceRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(tr(_l10n.deleteRequest)),
        content: Text(
          tr(request.isPaid
              ? 'Bạn có chắc muốn xóa yêu cầu ứng lương này?\nPhiếu chi liên quan cũng sẽ bị xóa.'
              : 'Bạn có chắc muốn xóa yêu cầu ứng lương này?'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr(_l10n.cancel))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child:
                Text(tr(_l10n.delete), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await _apiService.deleteAdvanceRequest(request.id);
    if (result['isSuccess'] == true) {
      appNotification.showSuccess(
          title: 'Thành công', message: tr('Đã xóa yêu cầu'));
      _loadData();
    } else {
      appNotification.showError(
          title: _l10n.error, message: result['message'] ?? 'Có lỗi xảy ra');
    }
  }

  Future<void> _cancelRequest(AdvanceRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(tr('Hủy yêu cầu')),
        content: Text(tr('Bạn có chắc muốn hủy yêu cầu ứng lương này?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr(_l10n.cancel))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text(tr('Hủy yêu cầu'),
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await _apiService.cancelAdvanceRequest(request.id);
    if (result['isSuccess'] == true) {
      appNotification.showSuccess(
          title: 'Thành công', message: tr('Đã hủy yêu cầu'));
      _loadData();
    } else {
      appNotification.showError(
          title: _l10n.error, message: result['message'] ?? 'Có lỗi xảy ra');
    }
  }

  List<Widget> _buildApprovalTimeline(AdvanceRequest request) {
    final records = List<ApprovalRecord>.from(request.approvalRecords)
      ..sort((a, b) => a.stepOrder.compareTo(b.stepOrder));

    return records.asMap().entries.map((entry) {
      final idx = entry.key;
      final record = entry.value;
      final isLast = idx == records.length - 1;

      Color dotColor;
      IconData dotIcon;
      switch (record.status) {
        case ApprovalStatus.approved:
          dotColor = Colors.green;
          dotIcon = Icons.check_circle;
          break;
        case ApprovalStatus.rejected:
          dotColor = Colors.red;
          dotIcon = Icons.cancel;
          break;
        case ApprovalStatus.cancelled:
          dotColor = Colors.grey;
          dotIcon = Icons.block;
          break;
        default:
          dotColor = Colors.orange;
          dotIcon = Icons.radio_button_unchecked;
          break;
      }

      return SafeTimelineRow(
        isLast: isLast,
        gutterWidth: 32,
        bottomPadding: 12,
        indicator: Icon(dotIcon, size: 18, color: dotColor),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(record.stepName ?? 'Cấp ${record.stepOrder}'),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: dotColor)),
            if (record.assignedUserName != null &&
                record.assignedUserName!.isNotEmpty)
              Text(tr('Phân công: ${record.assignedUserName}'),
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            if (record.actualUserName != null &&
                record.actualUserName!.isNotEmpty &&
                record.status != ApprovalStatus.pending)
              Text(tr('Thực hiện: ${record.actualUserName}'),
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            if (record.actionDate != null)
              Text(
                  tr(DateFormat('dd/MM/yyyy HH:mm').format(record.actionDate!)),
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            if (record.note != null && record.note!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(tr('"${record.note}"'),
                    style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey.shade700)),
              ),
          ],
        ),
      );
    }).toList();
  }

  void _showCreateDialog() {
    final amountController = TextEditingController();
    final reasonController = TextEditingController();
    final noteController = TextEditingController();
    final now = DateTime.now();
    int selectedMonth = now.month;
    int selectedYear = now.year;
    // For employee role: pre-select their own profile; for manager/admin: let them pick
    Employee? selectedEmployee = _isEmployeeRole ? _myEmployee : null;
    final isEmployeeMode = _isEmployeeRole;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isMobile = Responsive.isMobile(context);

          Future<Null> onSubmit() async {
            if (selectedEmployee == null) {
              appNotification.showWarning(
                  title: 'Cảnh báo', message: tr('Vui lòng chọn nhân viên'));
              return;
            }
            final amount =
                parseFormattedNumber(amountController.text)?.toDouble();
            if (amount == null || amount <= 0) {
              appNotification.showWarning(
                  title: 'Cảnh báo', message: tr('Vui lòng nhập số tiền hợp lệ'));
              return;
            }
            final result = await _apiService.createAdvanceRequest(
              amount: amount,
              reason: reasonController.text.isNotEmpty
                  ? reasonController.text
                  : null,
              note: noteController.text.isNotEmpty ? noteController.text : null,
              forMonth: selectedMonth,
              forYear: selectedYear,
              employeeUserId: selectedEmployee!.applicationUserId,
              employeeId: selectedEmployee!.id,
            );
            if (result['isSuccess'] == true) {
              if (context.mounted) Navigator.pop(context);
              appNotification.showSuccess(
                  title: 'Thành công', message: tr('Đã gửi yêu cầu ứng lương'));
              _loadData();
            } else {
              appNotification.showError(
                  title: 'Lỗi', message: result['message'] ?? 'Có lỗi xảy ra');
            }
          }

          final formContent = SingleChildScrollView(
            padding: isMobile ? const EdgeInsets.all(16) : EdgeInsets.zero,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Employee selection: read-only for employee role, autocomplete for manager/admin ──
                if (isEmployeeMode) ...[
                  // Employee role: show their own info as read-only
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.info.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.info.shade200),
                    ),
                    child: Row(children: [
                      Icon(Icons.person, size: 18, color: AppColors.info.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                          child: selectedEmployee != null
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                      Text(
                                          tr('${selectedEmployee!.lastName} ${selectedEmployee!.firstName}'),
                                          style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.info.shade800)),
                                      if (selectedEmployee!
                                          .employeeCode.isNotEmpty)
                                        Text(
                                            tr('${selectedEmployee!.employeeCode}${selectedEmployee!.department != null ? ' • ${selectedEmployee!.department}' : ''}'),
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: AppColors.info.shade600)),
                                    ])
                              : Text(tr('Chưa tìm thấy hồ sơ nhân viên'),
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.orange.shade700))),
                    ]),
                  ),
                ] else ...[
                  // Manager/Admin role: autocomplete to pick any employee
                  Autocomplete<Employee>(
                    displayStringForOption: (e) =>
                        '${e.lastName} ${e.firstName} (${e.employeeCode})',
                    optionsBuilder: (textEditingValue) {
                      if (textEditingValue.text.isEmpty) {
                        return _employees.take(20);
                      }
                      final q = textEditingValue.text.toLowerCase();
                      return _employees.where((e) {
                        final fullName =
                            '${e.lastName} ${e.firstName}'.toLowerCase();
                        return fullName.contains(q) ||
                            e.employeeCode.toLowerCase().contains(q);
                      }).take(20);
                    },
                    onSelected: (e) =>
                        setDialogState(() => selectedEmployee = e),
                    fieldViewBuilder:
                        (context, controller, focusNode, onFieldSubmitted) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: tr('Chọn nhân viên *'),
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.person_search),
                          hintText: tr('Tìm theo tên hoặc mã NV...'),
                          suffixIcon: selectedEmployee != null
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    controller.clear();
                                    setDialogState(
                                        () => selectedEmployee = null);
                                  },
                                )
                              : null,
                        ),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4,
                          borderRadius: BorderRadius.circular(8),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                                maxHeight: 250,
                                maxWidth: isMobile
                                    ? MediaQuery.of(context).size.width - 32
                                    : Responsive.dialogWidth(context)),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (context, index) {
                                final employee = options.elementAt(index);
                                return ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 16,
                                    backgroundColor: AppColors.info.shade100,
                                    child: Icon(
                                      employee.gender?.toLowerCase() ==
                                                  'female' ||
                                              employee.gender?.toLowerCase() ==
                                                  'nữ'
                                          ? Icons.woman_rounded
                                          : Icons.man_rounded,
                                      size: 18,
                                      color: AppColors.info.shade700,
                                    ),
                                  ),
                                  title: Text(
                                      tr('${employee.lastName} ${employee.firstName}'),
                                      style: const TextStyle(fontSize: 14)),
                                  subtitle: Text(
                                    tr('${employee.employeeCode}${employee.department != null ? ' • ${employee.department}' : ''}'),
                                    style: TextStyle(
                                        fontSize: 12, color: Colors.grey[600]),
                                  ),
                                  onTap: () => onSelected(employee),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  if (selectedEmployee != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle,
                              size: 16, color: Colors.green.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              tr('${selectedEmployee!.lastName} ${selectedEmployee!.firstName} (${selectedEmployee!.employeeCode})'),
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ], // end if selectedEmployee != null
                ], // end else (manager/admin block)
                const SizedBox(height: 16),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandSeparatorFormatter()],
                  decoration: InputDecoration(
                    labelText: tr('${_l10n.amount} *'),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.attach_money),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: selectedMonth,
                        decoration: InputDecoration(
                          labelText: tr('Tháng'),
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.calendar_month),
                        ),
                        items: List.generate(
                            12,
                            (i) => DropdownMenuItem(
                                value: i + 1, child: Text(tr('Tháng ${i + 1}')))),
                        onChanged: (v) =>
                            setDialogState(() => selectedMonth = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: selectedYear,
                        decoration: InputDecoration(
                          labelText: tr('Năm'),
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.date_range),
                        ),
                        items: List.generate(
                            5,
                            (i) => DropdownMenuItem(
                                value: now.year - 2 + i,
                                child: Text(tr('${now.year - 2 + i}')))),
                        onChanged: (v) =>
                            setDialogState(() => selectedYear = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: tr(_l10n.reason),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.note),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: noteController,
                  decoration: InputDecoration(
                    labelText: tr('Ghi chú (tùy chọn)'),
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.comment),
                  ),
                ),
              ],
            ),
          );

          if (isMobile) {
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    title: Text(tr('Yêu cầu ứng lương'),
                        overflow: TextOverflow.ellipsis, maxLines: 1),
                    leading: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  body: formContent,
                  bottomNavigationBar: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(tr(_l10n.cancel))),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: onSubmit,
                          icon: const Icon(Icons.send, size: 18),
                          label: Text(tr('Gửi yêu cầu')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return ScrollableAlertDialog(
            title: Text(tr('Yêu cầu ứng lương')),
            content: SizedBox(
              width: Responsive.dialogWidth(context),
              child: formContent,
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(tr(_l10n.cancel))),
              FilledButton.icon(
                onPressed: onSubmit,
                icon: const Icon(Icons.send, size: 18),
                label: Text(tr('Gửi yêu cầu')),
              ),
            ],
          );
        },
      ),
    ).then((_) {
      amountController.dispose();
      reasonController.dispose();
      noteController.dispose();
    });
  }

  // ==================== STATUS HELPERS ====================
  String _getStatusLabel(AdvanceRequest request) {
    if (request.status == AdvanceRequestStatus.approved && !request.isPaid) {
      return 'Chờ thanh toán';
    }
    if (request.status == AdvanceRequestStatus.approved && request.isPaid) {
      return 'Đã thanh toán';
    }
    return getAdvanceStatusLabel(request.status);
  }

  Color _getStatusColor(AdvanceRequest request) {
    if (request.status == AdvanceRequestStatus.approved && request.isPaid) {
      return HrmPageChrome.primaryNavy;
    }
    switch (request.status) {
      case AdvanceRequestStatus.pending:
        return const Color(0xFFF59E0B);
      case AdvanceRequestStatus.approved:
        return HrmPageChrome.primaryNavy;
      case AdvanceRequestStatus.rejected:
        return const Color(0xFFEF4444);
      case AdvanceRequestStatus.cancelled:
        return const Color(0xFFDC2626);
    }
  }

  IconData _getStatusIcon(AdvanceRequest request) {
    if (request.status == AdvanceRequestStatus.approved && request.isPaid) {
      return Icons.check_circle;
    }
    switch (request.status) {
      case AdvanceRequestStatus.pending:
        return Icons.hourglass_empty;
      case AdvanceRequestStatus.approved:
        return Icons.thumb_up;
      case AdvanceRequestStatus.rejected:
        return Icons.cancel;
      case AdvanceRequestStatus.cancelled:
        return Icons.block;
    }
  }

  // ==================== EXPORT ====================
  void _exportAdvanceRequestsExcel() async {
    try {
      final data = _filteredRequests;
      if (data.isEmpty) {
        appNotification.showError(
            title: 'Lỗi', message: tr('Không có dữ liệu để xuất'));
        return;
      }

      final wb = excel_lib.Excel.createExcel();
      final sheet = wb['Ứng lương'];

      sheet.appendRow([excel_lib.TextCellValue('DANH SÁCH ỨNG LƯƠNG')]);
      sheet.merge(excel_lib.CellIndex.indexByString('A1'),
          excel_lib.CellIndex.indexByString('J1'));

      final dateInfo = _selectedTimePreset == 'all'
          ? 'Tất cả thời gian'
          : _fromDate != null && _toDate != null
              ? '${DateFormat('dd/MM/yyyy').format(_fromDate!)} - ${DateFormat('dd/MM/yyyy').format(_toDate!)}'
              : '';
      sheet.appendRow([excel_lib.TextCellValue(dateInfo)]);
      sheet.merge(excel_lib.CellIndex.indexByString('A2'),
          excel_lib.CellIndex.indexByString('J2'));
      sheet.appendRow([]);

      final headers = [
        'STT',
        'Mã NV',
        'Họ tên',
        'Số tiền yêu cầu',
        'Số tiền đã duyệt',
        'Tháng/Năm',
        'Lý do',
        'Trạng thái',
        'Thanh toán',
        'PT thanh toán',
        'Ngày yêu cầu',
        'Ngày duyệt',
        'Người duyệt',
        'Ngày TT'
      ];
      sheet.appendRow(headers.map((h) => excel_lib.TextCellValue(h)).toList());

      for (int i = 0; i < data.length; i++) {
        final r = data[i];
        String statusLabel;
        if (r.status == AdvanceRequestStatus.pending) {
          statusLabel = 'Chờ duyệt';
        } else if (r.status == AdvanceRequestStatus.approved && !r.isPaid) {
          statusLabel = 'Chờ thanh toán';
        } else if (r.status == AdvanceRequestStatus.approved && r.isPaid) {
          statusLabel = 'Đã thanh toán';
        } else if (r.status == AdvanceRequestStatus.rejected) {
          statusLabel = 'Từ chối';
        } else {
          statusLabel = '';
        }

        sheet.appendRow([
          excel_lib.IntCellValue(i + 1),
          excel_lib.TextCellValue(r.employeeCode),
          excel_lib.TextCellValue(r.employeeName),
          excel_lib.DoubleCellValue(r.amount),
          excel_lib.DoubleCellValue(r.payoutAmount),
          excel_lib.TextCellValue(r.forMonth != null && r.forYear != null
              ? 'T${r.forMonth}/${r.forYear}'
              : ''),
          excel_lib.TextCellValue(r.reason ?? ''),
          excel_lib.TextCellValue(statusLabel),
          excel_lib.TextCellValue(r.isPaid ? 'Đã TT' : 'Chưa TT'),
          excel_lib.TextCellValue(r.paymentMethod ?? ''),
          excel_lib.TextCellValue(
              DateFormat('dd/MM/yyyy HH:mm').format(r.requestDate)),
          excel_lib.TextCellValue(r.approvedDate != null
              ? DateFormat('dd/MM/yyyy HH:mm').format(r.approvedDate!)
              : ''),
          excel_lib.TextCellValue(r.approvedByName ?? ''),
          excel_lib.TextCellValue(r.paidDate != null
              ? DateFormat('dd/MM/yyyy HH:mm').format(r.paidDate!)
              : ''),
        ]);
      }

      sheet.appendRow([]);
      sheet.appendRow([
        excel_lib.TextCellValue(''),
        excel_lib.TextCellValue(''),
        excel_lib.TextCellValue('TỔNG CỘNG'),
        excel_lib.DoubleCellValue(data.fold(0.0, (s, r) => s + r.amount)),
        excel_lib.DoubleCellValue(data.fold(0.0, (s, r) => s + r.payoutAmount)),
      ]);

      wb.delete('Sheet1');

      final bytes = wb.encode();
      if (bytes != null) {
        await file_saver.saveFileBytes(
            bytes,
            'ung_lương_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx',
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        appNotification.showSuccess(
            title: 'Thành công',
            message: tr('Đã xuất file Excel (${data.length} bản ghi)'));
      }
    } catch (e) {
      appNotification.showError(
          title: 'Lỗi', message: tr('Không thể xuất Excel: $e'));
    }
  }

  // ==================== DETAIL DIALOG ====================
  void _showDetailDialog(AdvanceRequest request) {
    final statusColor = _getStatusColor(request);
    final statusLabel = _getStatusLabel(request);
    final isMobile = MediaQuery.of(context).size.width < 768;

    final titleRow = Row(
      children: [
        Icon(_getStatusIcon(request), color: statusColor, size: 22),
        const SizedBox(width: 10),
        Expanded(
            child: Text(tr('Chi tiết ứng lương'), style: TextStyle(fontSize: 17))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(tr(statusLabel),
              style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12)),
        ),
      ],
    );

    final contentBody = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _detailRow(Icons.person, 'Nhân viên', request.employeeName),
        _detailRow(Icons.badge, _l10n.employeeCode, request.employeeCode),
        _detailRow(Icons.attach_money, _l10n.amount,
            _currencyFormat.format(request.amount),
            valueColor: AppColors.info),
        if (request.isPartiallyApproved)
          _detailRow(Icons.check_circle, 'Số tiền đã duyệt',
              _currencyFormat.format(request.approvedAmount!),
              valueColor: Colors.orange.shade800),
        if (request.forMonth != null && request.forYear != null)
          _detailRow(Icons.calendar_month, _l10n.monthYear,
              'T${request.forMonth}/${request.forYear}'),
        _detailRow(Icons.access_time, _l10n.requestDate,
            DateFormat('dd/MM/yyyy HH:mm').format(request.requestDate)),
        if (request.reason != null && request.reason!.isNotEmpty)
          _detailRow(Icons.note, _l10n.reason, request.reason!),
        if (request.note != null && request.note!.isNotEmpty)
          _detailRow(Icons.comment, 'Ghi chú', request.note!),
        if (request.approvedByName != null)
          _detailRow(
              Icons.verified_user, 'Người duyệt', request.approvedByName!),
        if (request.approvedDate != null)
          _detailRow(Icons.event_available, _l10n.approvedDate,
              DateFormat('dd/MM/yyyy HH:mm').format(request.approvedDate!)),
        if (request.rejectionReason != null &&
            request.rejectionReason!.isNotEmpty)
          _detailRow(
              Icons.info_outline, _l10n.rejectReason, request.rejectionReason!,
              valueColor: Colors.red),
        if (request.isPaid) ...[
          _detailRow(
              Icons.payment, 'PT thanh toán', request.paymentMethod ?? 'N/A'),
          if (request.paidDate != null)
            _detailRow(Icons.check_circle, 'Ngày TT',
                DateFormat('dd/MM/yyyy HH:mm').format(request.paidDate!),
                valueColor: HrmPageChrome.primaryNavy),
        ],
        // Approval timeline
        if (request.approvalRecords.isNotEmpty) ...[
          const SizedBox(height: 16),
          if (request.totalApprovalLevels > 1) ...[
            Row(
              children: [
                const Icon(Icons.linear_scale_rounded,
                    size: 18, color: Colors.blueGrey),
                const SizedBox(width: 8),
                Text(tr('Tiến trình duyệt: ${request.currentApprovalStep}/${request.totalApprovalLevels} cấp'),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: request.totalApprovalLevels > 0
                    ? request.currentApprovalStep / request.totalApprovalLevels
                    : 0,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  request.status == AdvanceRequestStatus.approved
                      ? Colors.green
                      : request.status == AdvanceRequestStatus.rejected
                          ? Colors.red
                          : AppColors.info,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Text(tr('Lịch sử phê duyệt'),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ..._buildApprovalTimeline(request),
        ],
      ],
    );

    if (isMobile) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: EdgeInsets.zero,
          child: SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
                title: Text(tr('Chi tiết ứng lương'),
                    overflow: TextOverflow.ellipsis, maxLines: 1),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleRow,
                    const SizedBox(height: 16),
                    contentBody,
                  ],
                ),
              ),
              bottomNavigationBar: Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  children: [
                    ..._buildDialogActions(request, ctx),
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(tr('Đóng'))),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => ScrollableAlertDialog(
          title: titleRow,
          content: SizedBox(
            width: Responsive.dialogWidth(context),
            child: SingleChildScrollView(child: contentBody),
          ),
          actions: [
            ..._buildDialogActions(request, ctx),
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng'))),
          ],
        ),
      );
    }
  }

  List<Widget> _buildDialogActions(AdvanceRequest request, BuildContext ctx) {
    final p = Provider.of<PermissionProvider>(context, listen: false);
    final List<Widget> actions = [];

    if (request.status == AdvanceRequestStatus.pending) {
      if (p.canApprove('AdvanceRequests') && !_isOwnAdvance(request)) {
        actions.addAll([
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _approveRequest(request, true);
            },
            icon: const Icon(Icons.check, size: 16, color: Colors.green),
            label: Text(tr(_l10n.approveLabel),
                style: const TextStyle(color: Colors.green)),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _showRejectDialog(request);
            },
            icon: const Icon(Icons.close, size: 16, color: Colors.red),
            label:
                Text(tr(_l10n.reject), style: const TextStyle(color: Colors.red)),
          ),
        ]);
      }
      if (_canCancelAdvance(request, p)) {
        actions.add(
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _cancelRequest(request);
            },
            icon: const Icon(Icons.block, size: 16, color: Colors.orange),
            label: Text(tr('Hủy'), style: TextStyle(color: Colors.orange)),
          ),
        );
      }
    } else if (request.status == AdvanceRequestStatus.approved &&
        !request.isPaid &&
        p.canApprove('AdvanceRequests')) {
      actions.addAll([
        TextButton.icon(
          onPressed: () {
            Navigator.pop(ctx);
            _undoApprove(request);
          },
          icon: const Icon(Icons.undo, size: 16, color: Colors.orange),
          label: Text(tr(_l10n.reverseApproval),
              style: const TextStyle(color: Colors.orange)),
        ),
        TextButton.icon(
          onPressed: () {
            Navigator.pop(ctx);
            _payRequest(request);
          },
          icon: const Icon(Icons.payment, size: 16, color: Colors.green),
          label:
              Text(tr(_l10n.payment), style: const TextStyle(color: Colors.green)),
        ),
      ]);
    } else if (request.status == AdvanceRequestStatus.rejected &&
        p.canApprove('AdvanceRequests')) {
      actions.add(
        TextButton.icon(
          onPressed: () {
            Navigator.pop(ctx);
            _undoApprove(request);
          },
          icon: const Icon(Icons.undo, size: 16, color: Colors.orange),
          label: Text(tr(_l10n.reverseApproval),
              style: const TextStyle(color: Colors.orange)),
        ),
      );
    }

    if (p.canDelete('AdvanceRequests') &&
        ((_isOwnAdvance(request) &&
                request.status == AdvanceRequestStatus.pending) ||
            _isManagerOrAbove ||
            p.canApprove('AdvanceRequests'))) {
      actions.add(
        TextButton.icon(
          onPressed: () {
            Navigator.pop(ctx);
            _deleteRequest(request);
          },
          icon: Icon(Icons.delete, size: 16, color: Colors.red.shade300),
          label:
              Text(tr(_l10n.delete), style: TextStyle(color: Colors.red.shade300)),
        ),
      );
    }
    return actions;
  }

  Widget _detailRow(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey[500]),
          const SizedBox(width: 10),
          SizedBox(
              width: 100,
              child: Text(tr(label),
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]))),
          Expanded(
              child: Text(tr(value),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: valueColor))),
        ],
      ),
    );
  }

  // ==================== EMPLOYEE PICKER ====================
  void _showEmployeePickerDialog() {
    String dialogSearch = '';
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isMobile = Responsive.isMobile(context);
            final filtered = dialogSearch.isEmpty
                ? _employees
                : _employees.where((e) {
                    final name = '${e.lastName} ${e.firstName}'.toLowerCase();
                    return name.contains(dialogSearch.toLowerCase()) ||
                        e.employeeCode
                            .toLowerCase()
                            .contains(dialogSearch.toLowerCase());
                  }).toList();

            final searchField = Padding(
              padding: isMobile
                  ? EdgeInsets.zero
                  : const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: tr('Tìm theo tên, mã nhân viên...'),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                style: const TextStyle(fontSize: 13),
                onChanged: (v) => setDialogState(() => dialogSearch = v),
              ),
            );

            final allEmployeesTile = ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 14,
                backgroundColor: Colors.grey.shade200,
                child: const Icon(Icons.people, size: 16, color: Colors.grey),
              ),
              title: Text(tr('Tất cả nhân viên'),
                  style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
              selected: _selectedEmployee == null,
              onTap: () {
                setState(() {
                  _selectedEmployee = null;
                  _currentPage = 1;
                });
                Navigator.pop(context);
              },
            );

            final employeeList = filtered.isEmpty
                ? Center(
                    child: Text(tr('Không tìm thấy nhân viên'),
                        style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final emp = filtered[index];
                      final isSelected = _selectedEmployee?.id == emp.id;
                      return ListTile(
                        dense: true,
                        selected: isSelected,
                        selectedTileColor: AppColors.info.shade50,
                        leading: CircleAvatar(
                          radius: 14,
                          backgroundColor: isSelected
                              ? AppColors.info.shade200
                              : AppColors.info.shade100,
                          child: Icon(
                            emp.gender?.toLowerCase() == 'female' ||
                                    emp.gender?.toLowerCase() == 'nữ'
                                ? Icons.woman_rounded
                                : Icons.man_rounded,
                            size: 16,
                            color: AppColors.info.shade700,
                          ),
                        ),
                        title: Text(tr('${emp.lastName} ${emp.firstName}'),
                            style: const TextStyle(fontSize: 13)),
                        subtitle: Text(tr(emp.employeeCode),
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[600])),
                        trailing: isSelected
                            ? Icon(Icons.check,
                                size: 18, color: AppColors.info.shade700)
                            : null,
                        onTap: () {
                          setState(() {
                            _selectedEmployee = emp;
                            _currentPage = 1;
                          });
                          Navigator.pop(context);
                        },
                      );
                    },
                  );

            if (isMobile) {
              return Dialog(
                insetPadding: EdgeInsets.zero,
                child: SizedBox(
                  width: double.infinity,
                  height: double.infinity,
                  child: Scaffold(
                    appBar: AppBar(
                      title: Text(tr('Chọn nhân viên')),
                      leading: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                    body: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: searchField,
                        ),
                        allEmployeesTile,
                        const Divider(height: 24),
                        Expanded(child: employeeList),
                      ],
                    ),
                  ),
                ),
              );
            }

            return ScrollableAlertDialog(
              title:
                  Text(tr('Chọn nhân viên'), style: TextStyle(fontSize: 16)),
              contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
              content: SizedBox(
                width: Responsive.dialogWidth(context),
                height: 450,
                child: Column(
                  children: [
                    searchField,
                    const SizedBox(height: 8),
                    allEmployeesTile,
                    const Divider(height: 24),
                    Expanded(child: employeeList),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('Đóng')))
              ],
            );
          },
        );
      },
    );
  }

  // ==================== UI BUILD ====================
  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final isMobile = Responsive.isMobile(context);

    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      body: HrmPushedScreenShell.maybeWrap(
        context,
        title: _l10n.advanceManagement,
        child: Column(
        children: [
          // ── Gradient Header ──
          Container(
            padding: EdgeInsets.fromLTRB(isMobile ? 14 : 24, isMobile ? 12 : 18,
                isMobile ? 14 : 24, isMobile ? 12 : 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primary, primary.withValues(alpha: 0.85)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                    color: primary.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(isMobile ? 8 : 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.account_balance_wallet,
                      size: isMobile ? 18 : 22, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(_l10n.salaryAdvance),
                          style: TextStyle(
                              fontSize: isMobile ? 16 : 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                      if (!isMobile)
                        Text(tr('Quản lý yêu cầu ứng lương nhân viên'),
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.8)),
                        ),
                    ],
                  ),
                ),
                if (isMobile) ...[
                  if (Provider.of<PermissionProvider>(context, listen: false)
                      .canCreate('AdvanceRequests'))
                    GestureDetector(
                      onTap: _showCreateDialog,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.add_circle_outline,
                            size: 18, color: Colors.white),
                      ),
                    ),
                  if (Provider.of<PermissionProvider>(context, listen: false)
                      .canExport('AdvanceRequests'))
                    const SizedBox(width: 4),
                  if (Provider.of<PermissionProvider>(context, listen: false)
                      .canExport('AdvanceRequests'))
                    GestureDetector(
                      onTap: _exportAdvanceRequestsExcel,
                      child: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.file_download_outlined,
                            size: 18, color: Colors.white),
                      ),
                    ),
                ] else ...[
                  if (Provider.of<PermissionProvider>(context, listen: false)
                      .canCreate('AdvanceRequests'))
                    _buildHeaderBtn(Icons.add_circle_outline, 'Tạo yêu cầu mới',
                        _showCreateDialog),
                  if (Provider.of<PermissionProvider>(context, listen: false)
                      .canExport('AdvanceRequests'))
                    const SizedBox(width: 8),
                  if (Provider.of<PermissionProvider>(context, listen: false)
                      .canExport('AdvanceRequests'))
                    _buildHeaderBtn(Icons.file_download_outlined, 'Xuất Excel',
                        _exportAdvanceRequestsExcel),
                ],
              ],
            ),
          ),
          // ── Content ──
          Expanded(
            child: HrmResponsiveListLayout(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              headerSections: _advancePageHeaderSections(isMobile),
              desktopBody: _isLoading
                  ? LoadingWidget(message: tr('Đang tải dữ liệu...'))
                  : _filteredRequests.isEmpty
                      ? const EmptyState(
                          icon: Icons.money_off,
                          title: 'Không có yêu cầu',
                          description: 'Chưa có yêu cầu ứng lương nào',
                        )
                      : Column(
                          children: [
                            Expanded(child: _buildDataTable()),
                            _buildPagination(),
                          ],
                        ),
              mobileSlivers: (_) => _advanceMobileSlivers(),
            ),
          ),
        ],
      ),
      ),
    );
  }

  List<Widget> _advancePageHeaderSections(bool isMobile) => [
        if (isMobile) ...[
          InkWell(
            onTap: () =>
                setState(() => _showMobileSummary = !_showMobileSummary),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.info.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.analytics_outlined,
                      size: 16, color: AppColors.info.shade700),
                  const SizedBox(width: 6),
                  Text(tr('Tổng quan'),
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppColors.info.shade700)),
                  const Spacer(),
                  Icon(
                      _showMobileSummary
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 20,
                      color: AppColors.info.shade700),
                ],
              ),
            ),
          ),
          if (_showMobileSummary) ...[
            const SizedBox(height: 8),
            _buildStatsRow(),
          ],
        ] else
          _buildStatsRow(),
        const SizedBox(height: 12),
        _buildFilters(),
        const SizedBox(height: 12),
      ];

  List<Widget> _advanceMobileSlivers() {
    if (_isLoading) {
      return [
        HrmScrollSlivers.fillRemaining(
            child: LoadingWidget(message: tr('Đang tải dữ liệu...'))),
      ];
    }
    if (_filteredRequests.isEmpty) {
      return [
        HrmScrollSlivers.fillRemaining(
          child: const EmptyState(
            icon: Icons.money_off,
            title: 'Không có yêu cầu',
            description: 'Chưa có yêu cầu ứng lương nào',
          ),
        ),
      ];
    }
    return HrmScrollSlivers.fromListViewBuilder(
      itemCount: _filteredRequests.length,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemBuilder: (_, i) => _buildAdvanceRequestMobileCard(_filteredRequests[i]),
    );
  }

  Widget _buildHeaderBtn(
      IconData icon, String tooltip, VoidCallback onPressed) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Container(
              padding: const EdgeInsets.all(10),
              child: Icon(icon, size: 20, color: Colors.white)),
        ),
      ),
    );
  }

  // ── Stats Row ──
  Widget _buildStatsRow() {
    final cards = [
      (
        label: _l10n.pending,
        count: _pendingList.length,
        amount: _sumAmount(_pendingList),
        icon: Icons.hourglass_empty,
        color: const Color(0xFFF59E0B)
      ),
      (
        label: _l10n.pendingPayment,
        count: _waitingPaymentList.length,
        amount: _sumAmount(_waitingPaymentList),
        icon: Icons.payment,
        color: HrmPageChrome.primaryNavy
      ),
      (
        label: _l10n.rejected,
        count: _rejectedList.length,
        amount: _sumAmount(_rejectedList),
        icon: Icons.cancel,
        color: const Color(0xFFEF4444)
      ),
      (
        label: _l10n.paid,
        count: _paidList.length,
        amount: _sumAmount(_paidList),
        icon: Icons.check_circle,
        color: HrmPageChrome.primaryNavy
      ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 500) {
        return Column(
          children: cards
              .map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildStatCard(
                        c.label, c.count, c.amount, c.icon, c.color,
                        fullWidth: true),
                  ))
              .toList(),
        );
      }
      return Row(
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            _buildStatCard(cards[i].label, cards[i].count, cards[i].amount,
                cards[i].icon, cards[i].color),
          ],
        ],
      );
    });
  }

  Widget _buildStatCard(
      String label, int count, double amount, IconData icon, Color color,
      {bool fullWidth = false}) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 20, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('$count'),
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: color)),
                Text(tr(label),
                    style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                const SizedBox(height: 2),
                Text(
                  tr(_currencyFormat.format(amount)),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color.withValues(alpha: 0.7)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (fullWidth) return content;
    return Expanded(child: content);
  }

  // ── Filters ──
  Widget _buildFilters() {
    final isMobile = Responsive.isMobile(context);

    final timePreset = _buildDropdown<String>(
      value: _selectedTimePreset,
      width: isMobile ? 120 : 130,
      icon: Icons.calendar_today,
      items: [
        DropdownMenuItem(value: 'all', child: Text(tr(_l10n.all))),
        DropdownMenuItem(value: 'today', child: Text(tr(_l10n.today))),
        DropdownMenuItem(value: 'yesterday', child: Text(tr(_l10n.yesterday))),
        DropdownMenuItem(value: 'this_week', child: Text(tr(_l10n.thisWeek))),
        DropdownMenuItem(value: 'last_week', child: Text(tr(_l10n.lastWeek))),
        DropdownMenuItem(value: 'this_month', child: Text(tr(_l10n.thisMonth))),
        DropdownMenuItem(value: 'last_month', child: Text(tr(_l10n.lastMonth))),
        DropdownMenuItem(value: 'custom', child: Text(tr(_l10n.custom))),
      ],
      onChanged: (v) {
        if (v != null) _applyTimePreset(v);
      },
    );

    final statusDropdown = _buildDropdown<AdvanceRequestStatus?>(
      value: _selectedStatus,
      width: isMobile ? 140 : 170,
      icon: Icons.flag,
      items: [
        DropdownMenuItem(value: null, child: Text(tr('Tất cả trạng thái'))),
        DropdownMenuItem(
            value: AdvanceRequestStatus.pending, child: Text(tr(_l10n.pending))),
        DropdownMenuItem(
            value: AdvanceRequestStatus.approved, child: Text(tr(_l10n.approved))),
        DropdownMenuItem(
            value: AdvanceRequestStatus.rejected, child: Text(tr(_l10n.rejected))),
      ],
      onChanged: (v) {
        setState(() {
          _selectedStatus = v;
          _currentPage = 1;
        });
        _loadData();
      },
    );

    final searchField = SizedBox(
      width: isMobile ? double.infinity : 200,
      height: 36,
      child: TextField(
        decoration: InputDecoration(
          hintText: tr('Tìm tên/mã nhân viên...'),
          hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
          prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
          isDense: true,
          filled: true,
          fillColor: const Color(0xFFFAFAFA),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                  color: Theme.of(context).primaryColor, width: 1.5)),
        ),
        style: const TextStyle(fontSize: 13),
        onChanged: (v) => setState(() {
          _searchQuery = v;
          _currentPage = 1;
        }),
      ),
    );

    final branchDropdown = _branches.isNotEmpty
        ? _buildDropdown<String?>(
            value: _selectedBranchId,
            width: isMobile ? 140 : 160,
            icon: Icons.account_tree_outlined,
            items: [
              DropdownMenuItem<String?>(
                  value: null, child: Text(tr('T\u1ea5t c\u1ea3 chi nh\u00e1nh'))),
              ..._branches.map((b) => DropdownMenuItem<String?>(
                  value: b['id']?.toString(),
                  child: Text(tr(b['name']?.toString() ?? ''),
                      overflow: TextOverflow.ellipsis))),
            ],
            onChanged: (v) => setState(() {
              _selectedBranchId = v;
              _currentPage = 1;
            }),
          )
        : const SizedBox.shrink();

    final countChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.analytics_outlined,
              size: 14, color: Theme.of(context).primaryColor),
          const SizedBox(width: 6),
          Text(tr('${_filteredRequests.length} yêu cầu'),
            style: TextStyle(
                color: Theme.of(context).primaryColor,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );

    if (isMobile) {
      return HrmFilterBar(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        children: [
            Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [timePreset, statusDropdown, branchDropdown]),
            const SizedBox(height: 8),
            searchField,
            const SizedBox(height: 8),
            Row(
              children: [
                _buildEmployeeChip(),
                const SizedBox(width: 8),
                if (_fromDate != null && _toDate != null) _buildDateRangeChip(),
                const Spacer(),
                countChip,
              ],
            ),
        ],
      );
    }

    return HrmFilterBar(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      children: [
        Row(
          children: [
            timePreset,
            const SizedBox(width: 8),
            if (_fromDate != null && _toDate != null) ...[
              _buildDateRangeChip(),
              const SizedBox(width: 8),
            ],
            statusDropdown,
            const SizedBox(width: 8),
            branchDropdown,
            const SizedBox(width: 8),
            _buildEmployeeChip(),
            const SizedBox(width: 8),
            searchField,
            const Spacer(),
            countChip,
          ],
        ),
      ],
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required double width,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      width: width,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down,
              size: 18, color: Colors.grey[500]),
          style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).textTheme.bodyMedium?.color),
          dropdownColor: Colors.white,
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item.value,
                    child: Row(
                      children: [
                        Icon(icon,
                            size: 15,
                            color: Theme.of(context)
                                .primaryColor
                                .withValues(alpha: 0.7)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DefaultTextStyle(
                            style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.color),
                            overflow: TextOverflow.ellipsis,
                            child: item.child,
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
          selectedItemBuilder: (context) => items
              .map((item) => Row(
                    children: [
                      Icon(icon,
                          size: 15, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DefaultTextStyle(
                          style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color),
                          overflow: TextOverflow.ellipsis,
                          child: item.child,
                        ),
                      ),
                    ],
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildDateRangeChip() {
    return InkWell(
      onTap: _pickCustomDateRange,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE4E4E7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.date_range,
                size: 15, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            Text(
              tr('${DateFormat('dd/MM/yyyy').format(_fromDate!)} - ${DateFormat('dd/MM/yyyy').format(_toDate!)}'),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(width: 4),
            Icon(Icons.edit, size: 12, color: Colors.grey[500]),
          ],
        ),
      ),
    );
  }

  Widget _buildEmployeeChip() {
    return InkWell(
      onTap: _showEmployeePickerDialog,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 36,
        constraints: const BoxConstraints(maxWidth: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE4E4E7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_search,
                size: 15, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                tr(_selectedEmployee != null
                    ? '${_selectedEmployee!.lastName} ${_selectedEmployee!.firstName}'
                    : 'Tất cả nhân viên'),
                style: TextStyle(
                    fontSize: 13,
                    color: _selectedEmployee != null ? null : Colors.grey[600]),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_selectedEmployee != null) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: () => setState(() => _selectedEmployee = null),
                child: Icon(Icons.close, size: 14, color: Colors.grey[500]),
              ),
            ] else
              Icon(Icons.keyboard_arrow_down,
                  size: 16, color: Colors.grey[500]),
          ],
        ),
      ),
    );
  }

  // ── Mobile Card List ──
  Widget _buildAdvanceRequestMobileCard(AdvanceRequest r) {
        final statusColor = _getStatusColor(r);
        return Padding(
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
                    offset: const Offset(0, 2))
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _showDetailDialog(r),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor:
                              HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                          child: Text(
                            tr(r.employeeName.isNotEmpty ? r.employeeName[0] : '?'),
                            style: const TextStyle(
                                color: HrmPageChrome.primaryNavy,
                                fontWeight: FontWeight.bold,
                                fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr(r.employeeName),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text(
                                tr([
                                  r.employeeCode,
                                  if (r.forMonth != null && r.forYear != null)
                                    'T${r.forMonth}/${r.forYear}'
                                ].join(' · ')),
                                style: const TextStyle(
                                    color: Color(0xFF71717A), fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_getStatusIcon(r),
                                  size: 12, color: statusColor),
                              const SizedBox(width: 4),
                              Text(tr(_getStatusLabel(r)),
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: statusColor)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr(_currencyFormat.format(r.payoutAmount)),
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: HrmPageChrome.primaryNavy),
                            ),
                            if (r.isPartiallyApproved)
                              Text(tr('YC ban đầu: ${_currencyFormat.format(r.amount)}'),
                                style: TextStyle(
                                    fontSize: 10, color: Colors.orange.shade800),
                              ),
                          ],
                        ),
                        Text(
                          tr(DateFormat('dd/MM/yyyy').format(r.requestDate)),
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF71717A)),
                        ),
                      ],
                    ),
                    if (r.reason != null && r.reason!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(tr(r.reason!),
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                    if (r.status == AdvanceRequestStatus.pending ||
                        (r.status == AdvanceRequestStatus.approved &&
                            !r.isPaid)) ...[
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Builder(builder: (ctx) {
                            final p = Provider.of<PermissionProvider>(ctx,
                                listen: false);
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                if (r.status == AdvanceRequestStatus.pending &&
                                    p.canApprove('AdvanceRequests') &&
                                    !_isOwnAdvance(r)) ...[
                                  _miniBtn(
                                      Icons.check,
                                      HrmPageChrome.primaryNavy,
                                      _l10n.approveLabel,
                                      () => _approveRequest(r, true)),
                                  const SizedBox(width: 6),
                                  _miniBtn(
                                      Icons.close,
                                      const Color(0xFFEF4444),
                                      _l10n.reject,
                                      () => _showRejectDialog(r)),
                                ],
                                if (r.status == AdvanceRequestStatus.pending &&
                                    _canCancelAdvance(r, p)) ...[
                                  const SizedBox(width: 6),
                                  _miniBtn(Icons.block, const Color(0xFFF59E0B),
                                      'Hủy', () => _cancelRequest(r)),
                                ],
                                if (r.status == AdvanceRequestStatus.approved &&
                                    !r.isPaid &&
                                    p.canApprove('AdvanceRequests')) ...[
                                  _miniBtn(
                                      Icons.undo,
                                      const Color(0xFFF59E0B),
                                      _l10n.reverseApproval,
                                      () => _undoApprove(r)),
                                  const SizedBox(width: 6),
                                  _miniBtn(
                                      Icons.payment,
                                      HrmPageChrome.primaryNavy,
                                      _l10n.payment,
                                      () => _payRequest(r)),
                                ],
                                if (p.canDelete('AdvanceRequests') &&
                                    ((_isOwnAdvance(r) &&
                                            r.status ==
                                                AdvanceRequestStatus.pending) ||
                                        _isManagerOrAbove ||
                                        p.canApprove('AdvanceRequests'))) ...[
                                  const SizedBox(width: 6),
                                  _miniBtn(Icons.delete_outline, Colors.grey,
                                      _l10n.delete, () => _deleteRequest(r)),
                                ],
                              ],
                            );
                          }),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
  }

  // ignore: unused_element
  Widget _buildMobileCardList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _filteredRequests.length,
      itemBuilder: (_, index) =>
          _buildAdvanceRequestMobileCard(_filteredRequests[index]),
    );
  }

  // ── Data Table ──
  Widget _buildDataTable() {
    final allFiltered = _filteredRequests;
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage).clamp(0, allFiltered.length);
    final displayed = allFiltered.sublist(startIndex, endIndex);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12), topRight: Radius.circular(12)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12), topRight: Radius.circular(12)),
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  minWidth: MediaQuery.of(context).size.width - 250),
              child: DataTable(
                showCheckboxColumn: false,
                sortColumnIndex: _getSortColumnIndex(),
                sortAscending: _sortAscending,
                headingRowColor:
                    WidgetStateProperty.all(const Color(0xFFFAFAFA)),
                dataRowColor: WidgetStateProperty.resolveWith<Color?>((states) {
                  if (states.contains(WidgetState.hovered)) {
                    return Theme.of(context)
                        .primaryColor
                        .withValues(alpha: 0.04);
                  }
                  return null;
                }),
                columnSpacing: 16,
                horizontalMargin: 16,
                headingRowHeight: 44,
                dataRowMinHeight: 42,
                dataRowMaxHeight: 48,
                dividerThickness: 0.5,
                columns: [
                  const DataColumn(label: _ColHeader('Số thứ tự')),
                  DataColumn(label: _ColHeader(_l10n.employeeCode)),
                  DataColumn(label: _ColHeader(_l10n.fullName)),
                  DataColumn(
                      label: _ColHeader(_l10n.amount),
                      onSort: (_, asc) => _onSort('amount', asc)),
                  DataColumn(label: _ColHeader(_l10n.monthYear)),
                  DataColumn(label: _ColHeader(_l10n.reason)),
                  DataColumn(label: _ColHeader(_l10n.status)),
                  DataColumn(
                      label: _ColHeader(_l10n.requestDate),
                      onSort: (_, asc) => _onSort('requestDate', asc)),
                  const DataColumn(label: _ColHeader('Người duyệt')),
                  const DataColumn(label: _ColHeader('Thao tác')),
                ],
                rows: displayed.asMap().entries.map((entry) {
                  final idx = startIndex + entry.key;
                  final r = entry.value;
                  final statusColor = _getStatusColor(r);

                  return DataRow(
                    onSelectChanged: (_) => _showDetailDialog(r),
                    cells: [
                      DataCell(Text(tr('${idx + 1}'),
                          style: const TextStyle(
                              fontSize: 12, color: Colors.grey))),
                      DataCell(Text(tr(r.employeeCode),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: HrmPageChrome.primaryNavy))),
                      DataCell(Text(tr(r.employeeName),
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w500))),
                      DataCell(Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tr(_currencyFormat.format(r.payoutAmount)),
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: HrmPageChrome.primaryNavy),
                          ),
                          if (r.isPartiallyApproved)
                            Text(
                              tr('YC: ${_currencyFormat.format(r.amount)}'),
                              style: TextStyle(
                                  fontSize: 10, color: Colors.orange.shade800),
                            ),
                        ],
                      )),
                      DataCell(
                        r.forMonth != null && r.forYear != null
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(6)),
                                child: Text(tr('T${r.forMonth}/${r.forYear}'),
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                              )
                            : Text(tr('-'),
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey)),
                      ),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 150),
                          child: Text(tr(r.reason ?? '-'),
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                              overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(_getStatusIcon(r),
                                  size: 12, color: statusColor),
                              const SizedBox(width: 4),
                              Text(tr(_getStatusLabel(r)),
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: statusColor)),
                            ],
                          ),
                        ),
                      ),
                      DataCell(Text(
                          tr(DateFormat('dd/MM/yyyy').format(r.requestDate)),
                          style: const TextStyle(fontSize: 12))),
                      DataCell(Text(tr(r.approvedByName ?? '-'),
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600]))),
                      DataCell(_buildRowActions(r)),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRowActions(AdvanceRequest r) {
    final p = Provider.of<PermissionProvider>(context, listen: false);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (r.status == AdvanceRequestStatus.pending &&
            p.canApprove('AdvanceRequests') &&
            !_isOwnAdvance(r)) ...[
          _miniBtn(Icons.check, HrmPageChrome.primaryNavy, _l10n.approveLabel,
              () => _approveRequest(r, true)),
          const SizedBox(width: 4),
          _miniBtn(Icons.close, const Color(0xFFEF4444), _l10n.reject,
              () => _showRejectDialog(r)),
        ],
        if (r.status == AdvanceRequestStatus.pending &&
            _canCancelAdvance(r, p)) ...[
          const SizedBox(width: 4),
          _miniBtn(Icons.block, const Color(0xFFF59E0B), 'Hủy',
              () => _cancelRequest(r)),
        ],
        if (r.status == AdvanceRequestStatus.approved &&
            !r.isPaid &&
            p.canApprove('AdvanceRequests')) ...[
          _miniBtn(Icons.undo, const Color(0xFFF59E0B), _l10n.reverseApproval,
              () => _undoApprove(r)),
          const SizedBox(width: 4),
          _miniBtn(Icons.payment, HrmPageChrome.primaryNavy, _l10n.payment,
              () => _payRequest(r)),
        ],
        if (p.canDelete('AdvanceRequests') &&
            ((_isOwnAdvance(r) &&
                    r.status == AdvanceRequestStatus.pending) ||
                _isManagerOrAbove ||
                p.canApprove('AdvanceRequests'))) ...[
          const SizedBox(width: 4),
          _miniBtn(Icons.delete_outline, Colors.grey, _l10n.delete,
              () => _deleteRequest(r)),
        ],
      ],
    );
  }

  Widget _miniBtn(
      IconData icon, Color color, String tooltip, VoidCallback onPressed) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 16, color: color),
          ),
        ),
      ),
    );
  }

  // ── Pagination ──
  Widget _buildPagination() {
    final totalItems = _filteredRequests.length;
    final totalPages = (totalItems / _itemsPerPage).ceil();
    if (totalPages <= 0) return const SizedBox.shrink();
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage).clamp(0, totalItems);
    final isMobile = Responsive.isMobile(context);

    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: isMobile ? 10 : 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
        border: Border(top: BorderSide(color: Color(0xFFE4E4E7))),
      ),
      child: isMobile
          ? Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(tr('Hiển thị ${startIndex + 1}-$endIndex / $totalItems'),
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(tr('Hiển thị:'),
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[500])),
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
                              value: _itemsPerPage,
                              isDense: true,
                              style: TextStyle(
                                  fontSize: 13, color: Colors.grey[800]),
                              items: _pageSizeOptions
                                  .map((s) => DropdownMenuItem(
                                      value: s, child: Text(tr('$s'))))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() {
                                    _itemsPerPage = v;
                                    _currentPage = 1;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildPageNavBtn(Icons.first_page, _currentPage > 1,
                        () => setState(() => _currentPage = 1)),
                    _buildPageNavBtn(Icons.chevron_left, _currentPage > 1,
                        () => setState(() => _currentPage--)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(tr('$_currentPage / $totalPages'),
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                    ),
                    const SizedBox(width: 8),
                    _buildPageNavBtn(
                        Icons.chevron_right,
                        _currentPage < totalPages,
                        () => setState(() => _currentPage++)),
                    _buildPageNavBtn(Icons.last_page, _currentPage < totalPages,
                        () => setState(() => _currentPage = totalPages)),
                  ],
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(tr('Hiển thị ${startIndex + 1}-$endIndex / $totalItems'),
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500),
                ),
                Row(
                  children: [
                    Text(tr('Hiển thị:'),
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[500])),
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
                          value: _itemsPerPage,
                          isDense: true,
                          style:
                              TextStyle(fontSize: 13, color: Colors.grey[800]),
                          items: _pageSizeOptions
                              .map((s) =>
                                  DropdownMenuItem(value: s, child: Text(tr('$s'))))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() {
                                _itemsPerPage = v;
                                _currentPage = 1;
                              });
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    _buildPageNavBtn(Icons.first_page, _currentPage > 1,
                        () => setState(() => _currentPage = 1)),
                    _buildPageNavBtn(Icons.chevron_left, _currentPage > 1,
                        () => setState(() => _currentPage--)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(tr('$_currentPage / $totalPages'),
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white)),
                    ),
                    const SizedBox(width: 8),
                    _buildPageNavBtn(
                        Icons.chevron_right,
                        _currentPage < totalPages,
                        () => setState(() => _currentPage++)),
                    _buildPageNavBtn(Icons.last_page, _currentPage < totalPages,
                        () => setState(() => _currentPage = totalPages)),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildPageNavBtn(IconData icon, bool enabled, VoidCallback onPressed) {
    return Material(
      color: enabled ? const Color(0xFFF1F5F9) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          child: Icon(icon,
              size: 20,
              color:
                  enabled ? Theme.of(context).primaryColor : Colors.grey[400]),
        ),
      ),
    );
  }
}

// Column header helper widget
class _ColHeader extends StatelessWidget {
  final String text;
  const _ColHeader(this.text);
  @override
  Widget build(BuildContext context) {
    return Text(
      tr(text),
      style: const TextStyle(
          fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF71717A)),
    );
  }
}
