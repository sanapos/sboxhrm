import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../widgets/app_scroll_safe.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/api_datetime.dart';
import '../utils/responsive_helper.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/hrm_responsive_list_layout.dart';
import '../widgets/notification_overlay.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../utils/navigation_notifier.dart';
import '../widgets/hrm_pushed_screen_shell.dart';
import '../widgets/page_top_actions.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Màn hình quản lý phiếu phạt
class PenaltyTicketsScreen extends StatefulWidget {
  final String? highlightId;

  /// Numeric status string to pre-filter: '0'=Pending, '1'=Approved, '2'=Cancelled, '3'=AutoApproved
  final String? initialFilterStatus;
  const PenaltyTicketsScreen(
      {super.key, this.highlightId, this.initialFilterStatus});

  @override
  State<PenaltyTicketsScreen> createState() => _PenaltyTicketsScreenState();
}

class _PenaltyTicketsScreenState extends State<PenaltyTicketsScreen> {
  final ApiService _apiService = ApiService();
  final _currencyFormat = NumberFormat('#,###', 'vi_VN');

  bool _isLoading = false;
  List<Map<String, dynamic>> _tickets = [];
  List<Map<String, dynamic>> _employees = [];
  int _totalCount = 0;
  int _currentPage = 1;
  int _pageSize = 20;
  final List<int> _pageSizeOptions = [20, 50, 100, 200];

  Map<String, dynamic> _stats = {};

  String? _filterStatus;
  String? _filterType;
  DateTimeRange? _dateRange;
  String _datePreset =
      'this_month'; // today, yesterday, this_week, last_week, this_month, last_month, custom, all
  String? _selectedBranchId;
  List<Map<String, dynamic>> _branches = [];

  List<Map<String, dynamic>> get _filteredTickets {
    if (_selectedBranchId == null) return _tickets;
    final ids = _employees
        .where((e) => e['branchId']?.toString() == _selectedBranchId)
        .map((e) => e['id']?.toString() ?? '')
        .toSet();
    return _tickets
        .where((t) => ids.contains(t['employeeId']?.toString()))
        .toList();
  }

  // Multi-select for bulk approve
  final Set<String> _selectedIds = {};
  bool get _isSelectionMode => _selectedIds.isNotEmpty;

  bool _showMobileSummary = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialFilterStatus != null) {
      _filterStatus = widget.initialFilterStatus;
      _applyDatePreset('all', reload: false);
    } else {
      final fromNav = NavigationNotifier.penaltyTicketsFilterStatus.value;
      if (fromNav != null) {
        _filterStatus = fromNav;
        _applyDatePreset('all', reload: false);
      } else {
        _applyDatePreset('this_month', reload: false);
      }
    }
    NavigationNotifier.penaltyTicketsFilterStatus.value = null;
    _loadData();
  }

  void _applyDatePreset(String preset, {bool reload = true}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTimeRange? range;
    switch (preset) {
      case 'today':
        range = DateTimeRange(start: today, end: today);
        break;
      case 'yesterday':
        final y = today.subtract(const Duration(days: 1));
        range = DateTimeRange(start: y, end: y);
        break;
      case 'this_week':
        final weekStart = today.subtract(Duration(days: today.weekday - 1));
        range = DateTimeRange(start: weekStart, end: today);
        break;
      case 'last_week':
        final weekStart = today.subtract(Duration(days: today.weekday - 1));
        final lastWeekStart = weekStart.subtract(const Duration(days: 7));
        final lastWeekEnd = weekStart.subtract(const Duration(days: 1));
        range = DateTimeRange(start: lastWeekStart, end: lastWeekEnd);
        break;
      case 'this_month':
        range = DateTimeRange(
            start: DateTime(today.year, today.month, 1), end: today);
        break;
      case 'last_month':
        final firstThis = DateTime(today.year, today.month, 1);
        final lastPrev = firstThis.subtract(const Duration(days: 1));
        final firstPrev = DateTime(lastPrev.year, lastPrev.month, 1);
        range = DateTimeRange(start: firstPrev, end: lastPrev);
        break;
      case 'all':
        range = null;
        break;
      case 'custom':
        // Keep current range; caller will open picker
        return;
    }
    setState(() {
      _datePreset = preset;
      _dateRange = range;
      _currentPage = 1;
    });
    if (reload) _loadTickets();
  }

  Future<void> _loadData({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);
    try {
      await Future.wait([
        _loadTickets(),
        _loadStats(),
        _loadEmployees(),
      ]);
      if (_branches.isEmpty) {
        try {
          final br = await _apiService.getBranchesForSelect();
          final bd = br['data'];
          if (bd is List && mounted) {
            setState(() => _branches =
                bd.map((b) => Map<String, dynamic>.from(b as Map)).toList());
          }
        } catch (_) {}
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
      _maybeOpenHighlight();
    }
  }

  bool _highlightOpened = false;
  void _maybeOpenHighlight() {
    if (_highlightOpened) return;
    final id = widget.highlightId ??
        NavigationNotifier.notificationHighlightId.value;
    NavigationNotifier.notificationHighlightId.value = null;
    if (id == null || id.isEmpty) return;
    Map<String, dynamic>? match;
    for (final t in _tickets) {
      final sid = id.toString();
      if (t['id']?.toString() == sid || t['Id']?.toString() == sid) {
        match = t;
        break;
      }
    }
    if (match == null) return;
    _highlightOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showDetailSheet(match!);
    });
  }

  Future<void> _loadTickets() async {
    final result = await _apiService.getPenaltyTickets(
      page: _currentPage,
      pageSize: _pageSize,
      status: _filterStatus,
      type: _filterType,
      fromDate: _dateRange?.start,
      toDate: _dateRange?.end,
    );

    if (mounted && result['isSuccess'] == true && result['data'] != null) {
      setState(() {
        _tickets =
            List<Map<String, dynamic>>.from(result['data']['items'] ?? []);
        _totalCount = result['data']['totalCount'] ?? 0;
      });
    }
  }

  Future<void> _loadStats() async {
    final now = DateTime.now();
    final result = await _apiService.getPenaltyTicketStats(
      month: now.month,
      year: now.year,
    );

    if (mounted && result['isSuccess'] == true && result['data'] != null) {
      setState(() {
        _stats = Map<String, dynamic>.from(result['data']);
      });
    }
  }

  Future<void> _loadEmployees() async {
    if (_employees.isNotEmpty) return;
    try {
      final result = await _apiService.getEmployeesForSelect();
      if (mounted) {
        setState(() => _employees = List<Map<String, dynamic>>.from(result));
      }
    } catch (_) {}
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'Late':
        return 'Đi trễ';
      case 'EarlyLeave':
        return 'Về sớm';
      case 'ForgotCheck':
        return 'Quên chấm công';
      case 'UnauthorizedLeave':
        return 'Nghỉ không phép';
      case 'Violation':
        return 'Vi phạm';
      case 'Repeat':
        return 'Tái phạm';
      default:
        return type;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Pending':
        return Colors.orange;
      case 'Approved':
        return Colors.green;
      case 'AutoApproved':
        return Colors.blue;
      case 'Cancelled':
        return const Color(0xFFDC2626);
      default:
        return Colors.black;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'Pending':
        return 'Chờ duyệt';
      case 'Approved':
        return 'Đã duyệt';
      case 'AutoApproved':
        return 'Tự động duyệt';
      case 'Cancelled':
        return 'Đã hủy';
      default:
        return status;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'Late':
        return Icons.schedule;
      case 'EarlyLeave':
        return Icons.exit_to_app;
      case 'ForgotCheck':
        return Icons.fingerprint;
      case 'UnauthorizedLeave':
        return Icons.event_busy;
      case 'Violation':
        return Icons.warning;
      default:
        return Icons.gavel;
    }
  }

  String _formatDate(dynamic date) =>
      formatApiCalendarDate(date, empty: '');

  String _formatDateTime(dynamic date) =>
      formatApiDateTime(date);

  String _formatPunchTime(dynamic date) => formatAttendanceWallClock(
        date,
        pattern: 'dd/MM/yyyy HH:mm',
      );

  // ─── Actions ───
  Future<void> _approveTicket(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ScrollableAlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('Duyệt phiếu phạt'),
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(tr('Duyệt phiếu phạt sẽ tạo phiếu thu tương ứng. Bạn có chắc?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Không'),
                  style: TextStyle(color: Color(0xFF71717A)))),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A)),
            child: Text(tr('Duyệt')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final result = await _apiService.approvePenaltyTicket(id);
      if (mounted) {
        if (result['isSuccess'] == true) {
          // Optimistic update: immediately reflect Approved status in the list
          setState(() {
            final idx = _tickets.indexWhere((t) => t['id'].toString() == id);
            if (idx >= 0) {
              _tickets[idx] = Map<String, dynamic>.from(_tickets[idx])
                ..['status'] = 'Approved'
                ..['processedDate'] = DateTime.now().toIso8601String();
            }
          });
          appNotification.showSuccess(
              title: 'Thành công',
              message: tr('Đã duyệt phiếu phạt và tạo phiếu thu'));
          await _loadData(showLoading: false);
        } else {
          appNotification.showError(
              title: 'Lỗi', message: result['message'] ?? 'Lỗi');
        }
      }
    }
  }

  Future<void> _unapproveTicket(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ScrollableAlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('Hoàn duyệt phiếu phạt'),
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(tr('Hoàn duyệt sẽ xóa phiếu thu liên quan và đưa phiếu phạt về trạng thái chờ duyệt. Bạn có chắc?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Không'),
                  style: TextStyle(color: Color(0xFF71717A)))),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: Text(tr('Hoàn duyệt')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final result = await _apiService.unapprovePenaltyTicket(id);
      if (mounted) {
        if (result['isSuccess'] == true) {
          appNotification.showSuccess(
              title: 'Thành công', message: tr('Đã hoàn duyệt phiếu phạt'));
          await _loadData(showLoading: false);
        } else {
          appNotification.showError(
              title: 'Lỗi', message: result['message'] ?? 'Lỗi');
        }
      }
    }
  }

  Future<void> _cancelTicket(String id) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ScrollableAlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('Hủy phiếu phạt'),
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('Bạn có chắc muốn hủy phiếu phạt này?')),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: tr('Lý do hủy'),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Không'),
                  style: TextStyle(color: Color(0xFF71717A)))),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(tr('Hủy phạt')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final reason = reasonController.text;
      reasonController.dispose();
      final result = await _apiService.cancelPenaltyTicket(id, reason: reason);
      if (mounted) {
        if (result['isSuccess'] == true) {
          appNotification.showSuccess(
              title: 'Thành công', message: tr('Đã hủy phiếu phạt'));
          await _loadData(showLoading: false);
        } else {
          appNotification.showError(
              title: 'Lỗi', message: result['message'] ?? 'Lỗi');
        }
      }
    } else {
      reasonController.dispose();
    }
  }

  Future<void> _deleteTicket(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ScrollableAlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('Xóa phiếu phạt'),
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(tr('Bạn có chắc muốn xóa phiếu phạt này? Chỉ xóa được phiếu đang chờ duyệt.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Không'),
                  style: TextStyle(color: Color(0xFF71717A)))),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final result = await _apiService.deletePenaltyTicket(id);
      if (mounted) {
        if (result['isSuccess'] == true) {
          appNotification.showSuccess(
              title: 'Thành công', message: tr('Đã xóa phiếu phạt'));
          await _loadData(showLoading: false);
        } else {
          appNotification.showError(
              title: 'Lỗi', message: result['message'] ?? 'Lỗi');
        }
      }
    }
  }

  Future<void> _backfillFromAttendance() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 30)),
            end: DateTime.now(),
          ),
      helpText: 'Chọn khoảng ngày quét lại',
    );
    if (picked == null || !mounted) return;

    if (picked.end.difference(picked.start).inDays > 62) {
      appNotification.showWarning(
        title: 'Khoảng ngày quá dài',
        message: tr('Chỉ quét tối đa 62 ngày mỗi lần. Vui lòng chọn khoảng ngắn hơn.'),
      );
      return;
    }

    final fromLabel = DateFormat('dd/MM/yyyy').format(picked.start);
    final toLabel = DateFormat('dd/MM/yyyy').format(picked.end);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ScrollableAlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('Quét lại chấm công'),
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          tr('Hệ thống sẽ quét chấm công từ $fromLabel đến $toLabel '
          'và tạo phiếu phạt đi trễ/về sớm/quên chấm còn thiếu (nếu có). '
          'Thao tác có thể mất vài phút.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Hủy'),
                style: TextStyle(color: Color(0xFF71717A))),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
                backgroundColor: HrmPageChrome.primaryNavy),
            child: Text(tr('Quét lại')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final result = await _apiService.backfillPenaltyTicketsFromAttendance(
        from: picked.start,
        to: picked.end,
      );
      if (!mounted) return;
      if (result['isSuccess'] == true) {
        final data = result['data'];
        final processed = data is Map ? data['processedPunches'] : null;
        final msg = data is Map && data['message'] != null
            ? data['message'].toString()
            : 'Đã quét ${processed ?? 0} lần chấm công';
        appNotification.showSuccess(title: 'Hoàn tất', message: msg);
        await _loadData(showLoading: false);
      } else {
        appNotification.showError(
          title: 'Lỗi',
          message: result['message']?.toString() ?? 'Không thể quét lại chấm công',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _dateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 30)),
            end: DateTime.now(),
          ),
    );
    if (picked != null) {
      setState(() {
        _dateRange = picked;
        _datePreset = 'custom';
        _currentPage = 1;
      });
      await _loadTickets();
    }
  }

  // ─── Bulk approve ───
  Future<void> _bulkApprove() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ScrollableAlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('Duyệt nhanh'),
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(tr('Duyệt ${ids.length} phiếu phạt đã chọn? Hệ thống sẽ tạo phiếu thu tương ứng cho từng phiếu.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Không'),
                  style: TextStyle(color: Color(0xFF71717A)))),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A)),
            child: Text(tr('Duyệt ${ids.length}')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isLoading = true);
    int ok = 0, fail = 0;
    for (final id in ids) {
      try {
        final r = await _apiService.approvePenaltyTicket(id);
        if (r['isSuccess'] == true) {
          ok++;
        } else {
          fail++;
        }
      } catch (_) {
        fail++;
      }
    }
    if (mounted) {
      _selectedIds.clear();
      if (fail == 0) {
        appNotification.showSuccess(
            title: 'Thành công', message: tr('Đã duyệt $ok phiếu'));
      } else {
        appNotification.showWarning(
            title: 'Hoàn tất', message: tr('Duyệt thành công $ok, lỗi $fail'));
      }
      await _loadData(showLoading: false);
    }
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAllPendingOnPage() {
    setState(() {
      for (final t in _tickets) {
        if (t['status'] == 'Pending') {
          _selectedIds.add(t['id'].toString());
        }
      }
    });
  }

  // ─── Create / Edit Dialog ───
  void _showTicketDialog({Map<String, dynamic>? ticket}) {
    final isEditing = ticket != null;
    final isPending = ticket?['status'] == 'Pending';

    if (isEditing && !isPending) {
      appNotification.showWarning(
          title: 'Không thể sửa', message: tr('Chỉ sửa được phiếu đang chờ duyệt'));
      return;
    }

    final amountCtrl = TextEditingController(
        text: tr(isEditing ? (ticket['amount'] ?? 0).toString() : ''));
    final descCtrl = TextEditingController(text: tr(ticket?['description'] ?? ''));
    final minutesCtrl = TextEditingController(
        text: tr(isEditing ? (ticket['minutesLateOrEarly'] ?? '').toString() : ''));
    String selectedType =
        isEditing ? (ticket['type'] ?? 'Violation') : 'Violation';
    String? selectedEmployeeId =
        isEditing ? ticket['employeeId']?.toString() : null;
    DateTime selectedDate = isEditing
        ? (parseApiCalendarDate(ticket['violationDate']) ?? DateTime.now())
        : DateTime.now();
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isMobile = Responsive.isMobile(context);
          final canApproveCreate = !isEditing &&
              Provider.of<PermissionProvider>(context, listen: false)
                  .canApprove('PenaltyTickets');

          Future<void> onSubmit({bool autoApprove = false}) async {
            if (isSaving) return;
            if (!isEditing && selectedEmployeeId == null) {
              appNotification.showWarning(
                  title: 'Thiếu thông tin', message: tr('Vui lòng chọn nhân viên'));
              return;
            }
            final amount = double.tryParse(amountCtrl.text);
            if (amount == null || amount <= 0) {
              appNotification.showWarning(
                  title: 'Thiếu thông tin',
                  message: tr('Vui lòng nhập số tiền hợp lệ'));
              return;
            }

            setDialogState(() => isSaving = true);

            Map<String, dynamic> result;
            if (isEditing) {
              result = await _apiService
                  .updatePenaltyTicket(ticket['id'].toString(), {
                'type': selectedType,
                'amount': amount,
                'description': descCtrl.text,
              });
            } else {
              result = await _apiService.createPenaltyTicket({
                'employeeId': selectedEmployeeId,
                'type': selectedType,
                'amount': amount,
                'violationDate': selectedDate.toIso8601String(),
                'minutesLateOrEarly': int.tryParse(minutesCtrl.text),
                'description': descCtrl.text.isEmpty ? null : descCtrl.text,
              });

              if (result['isSuccess'] == true && autoApprove) {
                final ticketId = result['data']?['id']?.toString();
                if (ticketId != null) {
                  final approveResult =
                      await _apiService.approvePenaltyTicket(ticketId);
                  if (approveResult['isSuccess'] != true) {
                    if (mounted) {
                      Navigator.pop(context);
                      appNotification.showWarning(
                          title: 'Tạo thành công',
                          message: approveResult['message'] ??
                              'Không thể duyệt phiếu phạt');
                      await _loadData(showLoading: false);
                    }
                    return;
                  }
                }
              }
            }

            if (!mounted) return;
            Navigator.pop(context);

            if (result['isSuccess'] == true) {
              appNotification.showSuccess(
                  title: 'Thành công',
                  message: isEditing
                      ? 'Đã cập nhật phiếu phạt'
                      : (autoApprove
                          ? 'Đã tạo & duyệt phiếu phạt'
                          : 'Đã tạo phiếu phạt'));
              await _loadData(showLoading: false);
            } else {
              appNotification.showError(
                  title: 'Lỗi', message: result['message'] ?? 'Lỗi');
            }
          }

          final types = [
            {'value': 'Late', 'label': 'Đi trễ'},
            {'value': 'EarlyLeave', 'label': 'Về sớm'},
            {'value': 'ForgotCheck', 'label': 'Quên chấm công'},
            {'value': 'UnauthorizedLeave', 'label': 'Nghỉ không phép'},
            {'value': 'Violation', 'label': 'Vi phạm nội quy'},
            {'value': 'Repeat', 'label': 'Tái phạm'},
          ];

          Widget formBody = SingleChildScrollView(
            padding: EdgeInsets.all(isMobile ? 16 : 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isEditing) ...[
                  Text(tr('Nhân viên *'),
                      style: TextStyle(color: Color(0xFF71717A), fontSize: 13)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedEmployeeId,
                    dropdownColor: Colors.white,
                    isExpanded: true,
                    decoration: _inputDecor('Chọn nhân viên'),
                    items: _employees.map<DropdownMenuItem<String>>((emp) {
                      final name =
                          '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'
                              .trim();
                      final code = emp['employeeCode'] ?? '';
                      return DropdownMenuItem(
                          value: emp['id'].toString(),
                          child: Text(tr('$code - $name'),
                              overflow: TextOverflow.ellipsis));
                    }).toList(),
                    onChanged: (v) =>
                        setDialogState(() => selectedEmployeeId = v),
                  ),
                  const SizedBox(height: 16),
                ],
                Text(tr('Loại phạt *'),
                    style: TextStyle(color: Color(0xFF71717A), fontSize: 13)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  dropdownColor: Colors.white,
                  isExpanded: true,
                  decoration: _inputDecor('Chọn loại phạt'),
                  items: types.map<DropdownMenuItem<String>>((t) {
                    return DropdownMenuItem(
                        value: t['value'] as String,
                        child: Text(tr(t['label'] as String)));
                  }).toList(),
                  onChanged: (v) =>
                      setDialogState(() => selectedType = v ?? 'Violation'),
                ),
                const SizedBox(height: 16),
                Text(tr('Số tiền phạt (VNĐ) *'),
                    style: TextStyle(color: Color(0xFF71717A), fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  style:
                      const TextStyle(color: Color(0xFF18181B), fontSize: 14),
                  decoration: _inputDecor('50000'),
                ),
                const SizedBox(height: 16),
                if (!isEditing) ...[
                  Text(tr('Ngày vi phạm *'),
                      style: TextStyle(color: Color(0xFF71717A), fontSize: 13)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2024),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE4E4E7)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today,
                              size: 16, color: Color(0xFF71717A)),
                          const SizedBox(width: 8),
                          Text(tr(DateFormat('dd/MM/yyyy').format(selectedDate)),
                              style: const TextStyle(fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Text(tr('Số phút trễ/sớm'),
                    style: TextStyle(color: Color(0xFF71717A), fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: minutesCtrl,
                  keyboardType: TextInputType.number,
                  style:
                      const TextStyle(color: Color(0xFF18181B), fontSize: 14),
                  decoration: _inputDecor('15'),
                ),
                const SizedBox(height: 16),
                Text(tr('Mô tả'),
                    style: TextStyle(color: Color(0xFF71717A), fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  style:
                      const TextStyle(color: Color(0xFF18181B), fontSize: 14),
                  decoration: _inputDecor('Ghi chú thêm...'),
                ),
              ],
            ),
          );

          if (isMobile) {
            return Dialog.fullscreen(
              backgroundColor: Colors.white,
              child: Scaffold(
                backgroundColor: Colors.white,
                appBar: AppBar(
                  backgroundColor: Colors.white,
                  elevation: 0,
                  leading: IconButton(
                    icon: const Icon(Icons.close, color: Color(0xFF18181B)),
                    onPressed: () => Navigator.pop(context),
                  ),
                  title: Text(
                    tr(isEditing ? 'Sửa phiếu phạt' : 'Tạo phiếu phạt'),
                    style: const TextStyle(
                        color: Color(0xFF18181B),
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                body: formBody,
                bottomNavigationBar: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed:
                              isSaving ? null : () => Navigator.pop(context),
                          child: Text(tr('Hủy')),
                        ),
                        const Spacer(),
                        if (canApproveCreate) ...[
                          OutlinedButton.icon(
                            onPressed: isSaving
                                ? null
                                : () => onSubmit(autoApprove: true),
                            icon: isSaving
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.check_circle, size: 16),
                            label: Text(tr('Tạo & Duyệt'),
                                style: TextStyle(fontSize: 13)),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.green),
                          ),
                          const SizedBox(width: 8),
                        ],
                        FilledButton.icon(
                          onPressed: isSaving ? null : () => onSubmit(),
                          icon: isSaving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : Icon(isEditing ? Icons.save : Icons.add,
                                  size: 16),
                          label: Text(
                              tr(isSaving
                                  ? 'Đang lưu...'
                                  : (isEditing ? 'Cập nhật' : 'Tạo phiếu')),
                              style: const TextStyle(fontSize: 13)),
                          style: FilledButton.styleFrom(
                              backgroundColor: HrmPageChrome.primaryNavy),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }

          return Dialog(
            backgroundColor: Colors.white,
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: math
                  .min(480, MediaQuery.of(context).size.width - 32)
                  .toDouble(),
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.85),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: Text(
                              tr(isEditing ? 'Sửa phiếu phạt' : 'Tạo phiếu phạt'),
                              style: const TextStyle(
                                  color: Color(0xFF18181B),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold))),
                      IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close,
                              color: Color(0xFF71717A))),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Flexible(child: formBody),
                  const SizedBox(height: 20),
                  const Divider(color: Color(0xFFE4E4E7)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton(
                          onPressed: isSaving
                              ? null
                              : () => Navigator.pop(context),
                          child: Text(tr('Hủy'),
                              style: TextStyle(color: Color(0xFF71717A)))),
                      const Spacer(),
                      if (canApproveCreate) ...[
                        OutlinedButton.icon(
                          onPressed: isSaving
                              ? null
                              : () => onSubmit(autoApprove: true),
                          icon: isSaving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : const Icon(Icons.check_circle),
                          label: Text(tr('Tạo & Duyệt')),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.green),
                        ),
                        const SizedBox(width: 8),
                      ],
                      FilledButton.icon(
                        onPressed: isSaving ? null : () => onSubmit(),
                        icon: isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Icon(isEditing ? Icons.save : Icons.add,
                                size: 18),
                        label: Text(tr(isSaving
                            ? 'Đang lưu...'
                            : (isEditing ? 'Cập nhật' : 'Tạo phiếu'))),
                        style: FilledButton.styleFrom(
                          backgroundColor: HrmPageChrome.primaryNavy,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  InputDecoration _inputDecor(String hint) {
    return InputDecoration(
      hintText: tr(hint),
      hintStyle: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: HrmPageChrome.primaryNavy)),
    );
  }

  // ─── Detail Bottom Sheet ───
  void _showDetailSheet(Map<String, dynamic> ticket) {
    final status = ticket['status'] as String? ?? '';
    final type = ticket['type'] as String? ?? '';
    final amount = (ticket['amount'] as num?)?.toDouble() ?? 0;
    final isPending = status == 'Pending';
    final isApproved = status == 'Approved' || status == 'AutoApproved';
    final isCancelled = status == 'Cancelled';

    showAppSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            children: [
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: const Color(0xFFE4E4E7),
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              CircleAvatar(
                radius: 28,
                backgroundColor:
                    _getStatusColor(status).withValues(alpha: 0.15),
                child: Icon(_getTypeIcon(type),
                    color: _getStatusColor(status), size: 28),
              ),
              const SizedBox(height: 12),
              Text(tr(ticket['employeeName'] ?? 'N/A'),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF18181B))),
              if (ticket['employeeCode'] != null)
                Text(tr(ticket['employeeCode']),
                    style: const TextStyle(
                        color: Color(0xFFA1A1AA), fontSize: 13)),
              const SizedBox(height: 8),
              Text(tr(ticket['ticketCode'] ?? ''),
                  style: const TextStyle(
                      color: Color(0xFF71717A),
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: _getStatusColor(status).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(tr(_getStatusLabel(status)),
                        style: TextStyle(
                            color: _getStatusColor(status),
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 10),
                  Text(tr('${_currencyFormat.format(amount)}đ'),
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.red[700])),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: Color(0xFFE4E4E7)),
              const SizedBox(height: 8),
              _detailRow(
                  Icons.category_outlined, 'Loại phạt', _getTypeLabel(type)),
              _detailRow(Icons.calendar_today, 'Ngày vi phạm',
                  _formatDate(ticket['violationDate'])),
              if (ticket['minutesLateOrEarly'] != null)
                _detailRow(Icons.timer_outlined, 'Số phút',
                    '${ticket['minutesLateOrEarly']} phút'),
              if (ticket['shiftStartTime'] != null)
                _detailRow(Icons.access_time, 'Ca làm',
                    '${ticket['shiftStartTime']} - ${ticket['shiftEndTime'] ?? ''}'),
              if (ticket['actualPunchTime'] != null)
                _detailRow(Icons.fingerprint, 'Giờ chấm thực tế',
                    _formatPunchTime(ticket['actualPunchTime'])),
              _detailRow(Icons.layers, 'Bậc phạt',
                  'Bậc ${ticket['penaltyTier'] ?? 1}'),
              if (ticket['description'] != null &&
                  (ticket['description'] as String).isNotEmpty)
                _detailRow(Icons.notes, 'Mô tả', ticket['description']),
              if (ticket['processedByName'] != null)
                _detailRow(Icons.person_outline, 'Người xử lý',
                    ticket['processedByName']),
              if (ticket['processedDate'] != null)
                _detailRow(Icons.event_available, 'Ngày xử lý',
                    _formatDateTime(ticket['processedDate'])),
              if (isCancelled && ticket['cancellationReason'] != null)
                _detailRow(Icons.cancel_outlined, 'Lý do hủy',
                    ticket['cancellationReason']),
              if (isApproved && ticket['cashTransactionCode'] != null)
                _detailRow(Icons.receipt_long, 'Phiếu thu',
                    ticket['cashTransactionCode']),
              _detailRow(Icons.access_time_filled, 'Ngày tạo',
                  _formatDateTime(ticket['createdAt'])),
              const SizedBox(height: 16),
              const Divider(color: Color(0xFFE4E4E7)),
              const SizedBox(height: 16),
              if (isPending) ...[
                Row(
                  children: [
                    if (Provider.of<PermissionProvider>(context, listen: false)
                        .canEdit('PenaltyTickets'))
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _showTicketDialog(ticket: ticket);
                          },
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: Text(tr('Sửa')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF71717A),
                            side: const BorderSide(color: Color(0xFFE4E4E7)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    if (Provider.of<PermissionProvider>(context, listen: false)
                        .canApprove('PenaltyTickets'))
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _cancelTicket(ticket['id'].toString());
                          },
                          icon: const Icon(Icons.close, size: 18),
                          label: Text(tr('Hủy phạt')),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange,
                            side: const BorderSide(color: Colors.orange),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    const SizedBox(width: 8),
                    if (Provider.of<PermissionProvider>(context, listen: false)
                        .canApprove('PenaltyTickets'))
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _approveTicket(ticket['id'].toString());
                          },
                          icon: const Icon(Icons.check, size: 18),
                          label: Text(tr('Duyệt')),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF16A34A),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                  ],
                ),
                if (Provider.of<PermissionProvider>(context, listen: false)
                    .canDelete('PenaltyTickets')) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _deleteTicket(ticket['id'].toString());
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: Text(tr('Xóa phiếu')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ],
              if (isApproved &&
                  Provider.of<PermissionProvider>(context, listen: false)
                      .canApprove('PenaltyTickets'))
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _unapproveTicket(ticket['id'].toString());
                    },
                    icon: const Icon(Icons.undo, size: 18),
                    label: Text(tr('Hoàn duyệt')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF71717A)),
          const SizedBox(width: 12),
          SizedBox(
              width: 110,
              child: Text(tr(label),
                  style:
                      const TextStyle(color: Color(0xFF71717A), fontSize: 13))),
          Expanded(
              child: Text(tr(value),
                  style: const TextStyle(
                      color: Color(0xFF18181B),
                      fontSize: 13,
                      fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  List<Widget> _buildTopActions(bool isMobile, bool canCreateTicket) {
    return [
      HrmTopBarAction(
        icon: Icons.sync,
        label: 'Quét lại chấm công',
        onPressed: _isLoading ? null : _backfillFromAttendance,
      ),
      HrmTopBarAction(
        icon: Icons.date_range,
        label: 'Chọn khoảng thời gian',
        onPressed: _pickDateRange,
      ),
      if (canCreateTicket && !isMobile)
        HrmTopBarAction(
          icon: Icons.add,
          label: 'Tạo phiếu phạt',
          primary: true,
          showLabel: true,
          onPressed: () => _showTicketDialog(),
        ),
    ];
  }

  // ─── Build ───
  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final canCreateTicket =
        Provider.of<PermissionProvider>(context, listen: false)
            .canCreate('PenaltyTickets');
    return RegisterPageTopActions(
      actions: _buildTopActions(isMobile, canCreateTicket),
      child: Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      floatingActionButton: isMobile && canCreateTicket
          ? FloatingActionButton(
              onPressed: () => _showTicketDialog(),
              backgroundColor: HrmPageChrome.primaryNavy,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: HrmPushedScreenShell.maybeWrap(
        context,
        title: 'Phiếu phạt',
        child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : HrmResponsiveListLayout(
              fabAware: isMobile && canCreateTicket,
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
              headerSections: _penaltyPageHeaderSections(isMobile),
              desktopBody: Column(
                children: [
                  if (_isSelectionMode) _buildBulkActionBar(),
                  Expanded(child: _buildTicketList()),
                  if (_totalCount > _pageSize) _buildPagination(),
                ],
              ),
              mobileSlivers: (_) => _penaltyMobileSlivers(),
            ),
      ),
    ),
    );
  }

  List<Widget> _penaltyPageHeaderSections(bool isMobile) => [
        if (isMobile) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: InkWell(
              onTap: () =>
                  setState(() => _showMobileSummary = !_showMobileSummary),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Icon(Icons.analytics_outlined,
                        size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 6),
                    Text(tr('Tổng quan'),
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
          if (_showMobileSummary) _buildStatsCards(),
        ] else
          _buildStatsCards(),
        _buildFilterBar(),
        if (_isSelectionMode) _buildBulkActionBar(),
      ];

  List<Widget> _penaltyMobileSlivers() {
    if (_filteredTickets.isEmpty) {
      return [
        HrmScrollSlivers.fillRemaining(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                SizedBox(height: 16),
                Text(tr('Không có phiếu phạt'),
                    style: TextStyle(fontSize: 16, color: Colors.grey)),
              ],
            ),
          ),
        ),
      ];
    }
    final slivers = HrmScrollSlivers.fromListViewBuilder(
      itemCount: _filteredTickets.length,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemBuilder: (_, i) {
        final ticket = _filteredTickets[i];
        final id = ticket['id'].toString();
        final status = ticket['status'] as String? ?? '';
        final type = ticket['type'] as String? ?? '';
        final amount = (ticket['amount'] as num?)?.toDouble() ?? 0;
        final isPending = status == 'Pending';
        final isSelected = _selectedIds.contains(id);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: isSelected ? const Color(0xFFFFFBEB) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            elevation: 0,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                if (_isSelectionMode && isPending) {
                  _toggleSelection(id);
                } else {
                  _showDetailSheet(ticket);
                }
              },
              onLongPress: isPending ? () => _toggleSelection(id) : null,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: isSelected
                          ? Colors.orange
                          : const Color(0xFFE4E4E7),
                      width: isSelected ? 1.5 : 1),
                ),
                child: Row(
                  children: [
                    if (_isSelectionMode && isPending)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: isSelected
                              ? Colors.orange
                              : const Color(0xFFA1A1AA),
                          size: 22,
                        ),
                      ),
                    CircleAvatar(
                      radius: 20,
                      backgroundColor:
                          _getStatusColor(status).withValues(alpha: 0.15),
                      child: Icon(_getTypeIcon(type),
                          color: _getStatusColor(status), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr(ticket['employeeName'] ?? 'N/A'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Color(0xFF18181B))),
                          const SizedBox(height: 2),
                          Text(
                            tr([
                              _getTypeLabel(type),
                              _formatDate(ticket['violationDate'])
                            ].where((s) => s.isNotEmpty).join(' \u00b7 ')),
                            style: const TextStyle(
                                color: Color(0xFF71717A), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(tr('${_currencyFormat.format(amount)}\u0111'),
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red[700],
                                fontSize: 13)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getStatusColor(status)
                                .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(tr(_getStatusLabel(status)),
                              style: TextStyle(
                                  color: _getStatusColor(status),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (_totalCount > _pageSize) {
      slivers.add(HrmScrollSlivers.toBox(_buildPagination()));
    }
    return slivers;
  }

  Widget _buildStatsCards() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
              child: _buildStatCard(
                  'Chờ duyệt', _stats['totalPending'] ?? 0, Colors.orange,
                  amount: (_stats['pendingAmount'] as num?)?.toDouble())),
          const SizedBox(width: 8),
          Expanded(
              child: _buildStatCard(
                  'Đã duyệt',
                  ((_stats['totalApproved'] ?? 0) as int) +
                      ((_stats['totalAutoApproved'] ?? 0) as int),
                  Colors.green,
                  amount: (_stats['approvedAmount'] as num?)?.toDouble())),
          const SizedBox(width: 8),
          Expanded(
              child: _buildStatCard(
                  'Đã hủy', _stats['totalCancelled'] ?? 0, const Color(0xFFDC2626))),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, dynamic count, Color color,
      {double? amount}) {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFFE4E4E7))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('$count'),
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            Text(tr(label),
                style: const TextStyle(fontSize: 11, color: Color(0xFF71717A)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (amount != null && amount > 0)
              Text(tr('${_currencyFormat.format(amount)}đ'),
                  style: TextStyle(
                      fontSize: 10, color: color, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date preset chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: Responsive.horizontalScrollPadding,
            clipBehavior: Clip.none,
            child: Row(
              children: [
                _datePresetChip('today', 'Hôm nay'),
                const SizedBox(width: 6),
                _datePresetChip('yesterday', 'Hôm qua'),
                const SizedBox(width: 6),
                _datePresetChip('this_week', 'Tuần này'),
                const SizedBox(width: 6),
                _datePresetChip('last_week', 'Tuần trước'),
                const SizedBox(width: 6),
                _datePresetChip('this_month', 'Tháng này'),
                const SizedBox(width: 6),
                _datePresetChip('last_month', 'Tháng trước'),
                const SizedBox(width: 6),
                _datePresetChip('all', 'Tất cả'),
                const SizedBox(width: 6),
                ActionChip(
                  avatar: const Icon(Icons.date_range, size: 16),
                  label: Text(tr(_datePreset == 'custom' && _dateRange != null
                      ? '${DateFormat('dd/MM').format(_dateRange!.start)} - ${DateFormat('dd/MM').format(_dateRange!.end)}'
                      : 'Lựa chọn khác')),
                  backgroundColor: _datePreset == 'custom'
                      ? HrmPageChrome.primaryNavy
                      : Colors.white,
                  labelStyle: TextStyle(
                      fontSize: 12,
                      color: _datePreset == 'custom'
                          ? Colors.white
                          : const Color(0xFF18181B)),
                  side: const BorderSide(color: Color(0xFFE4E4E7)),
                  onPressed: _pickDateRange,
                ),
                if (Provider.of<PermissionProvider>(context, listen: false)
                    .canCreate('PenaltyTickets')) ...[
                  const SizedBox(width: 6),
                  ActionChip(
                    avatar: const Icon(Icons.sync, size: 16),
                    label: Text(tr('Quét lại')),
                    backgroundColor: Colors.white,
                    labelStyle: const TextStyle(
                        fontSize: 12, color: Color(0xFF18181B)),
                    side: const BorderSide(color: Color(0xFFE4E4E7)),
                    onPressed: _isLoading ? null : _backfillFromAttendance,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (Responsive.isMobile(context))
            ...HrmFilterBar.mobileStack([
              DropdownButtonFormField<String?>(
                initialValue: _filterStatus,
                isExpanded: true,
                dropdownColor: Colors.white,
                decoration: InputDecoration(
                  labelText: tr('Trạng thái'),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(value: null, child: Text(tr('Tất cả'))),
                  DropdownMenuItem(value: '0', child: Text(tr('Chờ duyệt'))),
                  DropdownMenuItem(value: '1', child: Text(tr('Đã duyệt'))),
                  DropdownMenuItem(value: '3', child: Text(tr('Tự động duyệt'))),
                  DropdownMenuItem(value: '2', child: Text(tr('Đã hủy'))),
                ],
                onChanged: (v) {
                  setState(() {
                    _filterStatus = v;
                    _currentPage = 1;
                  });
                  _loadTickets();
                },
              ),
              DropdownButtonFormField<String?>(
                initialValue: _filterType,
                isExpanded: true,
                dropdownColor: Colors.white,
                decoration: InputDecoration(
                  labelText: tr('Loại'),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(value: null, child: Text(tr('Tất cả'))),
                  DropdownMenuItem(value: '1', child: Text(tr('Đi trễ'))),
                  DropdownMenuItem(value: '2', child: Text(tr('Về sớm'))),
                  DropdownMenuItem(value: '3', child: Text(tr('Quên chấm công'))),
                  DropdownMenuItem(
                      value: '4', child: Text(tr('Nghỉ không phép'))),
                  DropdownMenuItem(value: '5', child: Text(tr('Vi phạm'))),
                  DropdownMenuItem(value: '6', child: Text(tr('Tái phạm'))),
                ],
                onChanged: (v) {
                  setState(() {
                    _filterType = v;
                    _currentPage = 1;
                  });
                  _loadTickets();
                },
              ),
            ])
          else
            Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _filterStatus,
                  dropdownColor: Colors.white,
                  decoration: InputDecoration(
                    labelText: tr('Trạng thái'),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem(value: null, child: Text(tr('Tất cả'))),
                    DropdownMenuItem(value: '0', child: Text(tr('Chờ duyệt'))),
                    DropdownMenuItem(value: '1', child: Text(tr('Đã duyệt'))),
                    DropdownMenuItem(value: '3', child: Text(tr('Tự động duyệt'))),
                    DropdownMenuItem(value: '2', child: Text(tr('Đã hủy'))),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _filterStatus = v;
                      _currentPage = 1;
                    });
                    _loadTickets();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _filterType,
                  dropdownColor: Colors.white,
                  decoration: InputDecoration(
                    labelText: tr('Loại'),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    DropdownMenuItem(value: null, child: Text(tr('Tất cả'))),
                    DropdownMenuItem(value: '1', child: Text(tr('Đi trễ'))),
                    DropdownMenuItem(value: '2', child: Text(tr('Về sớm'))),
                    DropdownMenuItem(value: '3', child: Text(tr('Quên chấm công'))),
                    DropdownMenuItem(
                        value: '4', child: Text(tr('Nghỉ không phép'))),
                    DropdownMenuItem(value: '5', child: Text(tr('Vi phạm'))),
                    DropdownMenuItem(value: '6', child: Text(tr('Tái phạm'))),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _filterType = v;
                      _currentPage = 1;
                    });
                    _loadTickets();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_branches.isNotEmpty)
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE4E4E7)),
              ),
              child: Row(children: [
                const Icon(Icons.account_tree_outlined,
                    size: 16, color: Color(0xFF6B7280)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _selectedBranchId,
                      isExpanded: true,
                      isDense: true,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF111827)),
                      icon: const Icon(Icons.keyboard_arrow_down,
                          size: 18, color: Color(0xFF9CA3AF)),
                      items: [
                        DropdownMenuItem<String?>(
                            value: null,
                            child: Text(tr('Tất cả chi nhánh'),
                                style: TextStyle(fontSize: 13))),
                        ..._branches.map((b) => DropdownMenuItem<String?>(
                            value: b['id']?.toString(),
                            child: Text(tr(b['name']?.toString() ?? ''),
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13)))),
                      ],
                      onChanged: (v) => setState(() => _selectedBranchId = v),
                    ),
                  ),
                ),
                if (_selectedBranchId != null)
                  InkWell(
                    onTap: () => setState(() => _selectedBranchId = null),
                    child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close,
                            size: 14, color: Color(0xFF9CA3AF))),
                  ),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _datePresetChip(String preset, String label) {
    final selected = _datePreset == preset;
    return ChoiceChip(
      label: Text(tr(label), style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => _applyDatePreset(preset),
      backgroundColor: Colors.white,
      selectedColor: HrmPageChrome.primaryNavy,
      labelStyle:
          TextStyle(color: selected ? Colors.white : const Color(0xFF18181B)),
      side: const BorderSide(color: Color(0xFFE4E4E7)),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildBulkActionBar() {
    final canApprove = Provider.of<PermissionProvider>(context, listen: false)
        .canApprove('PenaltyTickets');
    final pendingOnPage =
        _tickets.where((t) => t['status'] == 'Pending').length;
    return Container(
      color: const Color(0xFFFFF7ED),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => setState(() => _selectedIds.clear()),
            tooltip: tr('Bỏ chọn'),
            visualDensity: VisualDensity.compact,
          ),
          Text(tr('Đã chọn ${_selectedIds.length} phiếu'),
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const Spacer(),
          if (pendingOnPage >
              _selectedIds
                  .where((id) => _tickets.any((t) =>
                      t['id'].toString() == id && t['status'] == 'Pending'))
                  .length)
            TextButton(
              onPressed: _selectAllPendingOnPage,
              child: Text(tr('Chọn tất cả chờ duyệt ($pendingOnPage)'),
                  style: const TextStyle(fontSize: 12)),
            ),
          if (canApprove) ...[
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _bulkApprove,
              icon: const Icon(Icons.check, size: 16),
              label: Text(tr('Duyệt ${_selectedIds.length}')),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTicketList() {
    if (_filteredTickets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text(tr('Không có phiếu phạt'),
                style: TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      );
    }

    return Responsive.isMobile(context)
        ? _buildMobileList()
        : _buildDesktopList();
  }

  Widget _buildMobileList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _filteredTickets.length,
      itemBuilder: (_, i) {
        final ticket = _filteredTickets[i];
        final id = ticket['id'].toString();
        final status = ticket['status'] as String? ?? '';
        final type = ticket['type'] as String? ?? '';
        final amount = (ticket['amount'] as num?)?.toDouble() ?? 0;
        final isPending = status == 'Pending';
        final isSelected = _selectedIds.contains(id);

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: isSelected ? const Color(0xFFFFFBEB) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            elevation: 0,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                if (_isSelectionMode && isPending) {
                  _toggleSelection(id);
                } else {
                  _showDetailSheet(ticket);
                }
              },
              onLongPress: isPending ? () => _toggleSelection(id) : null,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color:
                          isSelected ? Colors.orange : const Color(0xFFE4E4E7),
                      width: isSelected ? 1.5 : 1),
                ),
                child: Row(
                  children: [
                    if (_isSelectionMode && isPending)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          isSelected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: isSelected
                              ? Colors.orange
                              : const Color(0xFFA1A1AA),
                          size: 22,
                        ),
                      ),
                    CircleAvatar(
                      radius: 20,
                      backgroundColor:
                          _getStatusColor(status).withValues(alpha: 0.15),
                      child: Icon(_getTypeIcon(type),
                          color: _getStatusColor(status), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr(ticket['employeeName'] ?? 'N/A'),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Color(0xFF18181B))),
                          const SizedBox(height: 2),
                          Text(
                            tr([
                              _getTypeLabel(type),
                              _formatDate(ticket['violationDate'])
                            ].where((s) => s.isNotEmpty).join(' \u00b7 ')),
                            style: const TextStyle(
                                color: Color(0xFF71717A), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(tr('${_currencyFormat.format(amount)}\u0111'),
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red[700],
                                fontSize: 13)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: _getStatusColor(status)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6)),
                          child: Text(tr(_getStatusLabel(status)),
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: _getStatusColor(status))),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right,
                        color: Color(0xFFA1A1AA), size: 20),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopList() {
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _filteredTickets.length,
      itemBuilder: (context, index) {
        final ticket = _filteredTickets[index];
        final id = ticket['id'].toString();
        final status = ticket['status'] as String? ?? '';
        final type = ticket['type'] as String? ?? '';
        final isPending = status == 'Pending';
        final isApproved = status == 'Approved' || status == 'AutoApproved';
        final amount = (ticket['amount'] as num?)?.toDouble() ?? 0;
        final isSelected = _selectedIds.contains(id);

        return Card(
          color: isSelected ? const Color(0xFFFFFBEB) : Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
                color: isSelected ? Colors.orange : const Color(0xFFE4E4E7),
                width: isSelected ? 1.5 : 1),
          ),
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              if (_isSelectionMode && isPending) {
                _toggleSelection(id);
              } else {
                _showDetailSheet(ticket);
              }
            },
            onLongPress: isPending ? () => _toggleSelection(id) : null,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isPending)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            onTap: () => _toggleSelection(id),
                            child: Icon(
                              isSelected
                                  ? Icons.check_box
                                  : Icons.check_box_outline_blank,
                              color: isSelected
                                  ? Colors.orange
                                  : const Color(0xFFA1A1AA),
                              size: 22,
                            ),
                          ),
                        ),
                      CircleAvatar(
                        radius: 18,
                        backgroundColor:
                            _getStatusColor(status).withValues(alpha: 0.15),
                        child: Icon(_getTypeIcon(type),
                            color: _getStatusColor(status), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr(ticket['employeeName'] ?? 'N/A'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(
                              tr([
                                _getTypeLabel(type),
                                _formatDate(ticket['violationDate']),
                                ticket['ticketCode'] ?? ''
                              ].where((s) => s.isNotEmpty).join(' \u00b7 ')),
                              style: const TextStyle(
                                  color: Color(0xFF71717A), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Text(tr('${_currencyFormat.format(amount)}\u0111'),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.red[700],
                              fontSize: 15)),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color:
                                _getStatusColor(status).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8)),
                        child: Text(tr(_getStatusLabel(status)),
                            style: TextStyle(
                                fontSize: 11,
                                color: _getStatusColor(status),
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  if (ticket['description'] != null &&
                      (ticket['description'] as String).isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(tr(ticket['description']),
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF71717A)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                  if (isPending || isApproved) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (isPending) ...[
                          if (Provider.of<PermissionProvider>(context,
                                  listen: false)
                              .canEdit('PenaltyTickets'))
                            _actionBtn(
                                Icons.edit_outlined,
                                'Sửa',
                                const Color(0xFF71717A),
                                () => _showTicketDialog(ticket: ticket)),
                          if (Provider.of<PermissionProvider>(context,
                                  listen: false)
                              .canEdit('PenaltyTickets'))
                            const SizedBox(width: 6),
                          if (Provider.of<PermissionProvider>(context,
                                  listen: false)
                              .canDelete('PenaltyTickets'))
                            _actionBtn(Icons.delete_outline, 'Xóa', Colors.red,
                                () => _deleteTicket(ticket['id'].toString())),
                          if (Provider.of<PermissionProvider>(context,
                                  listen: false)
                              .canDelete('PenaltyTickets'))
                            const SizedBox(width: 6),
                          if (Provider.of<PermissionProvider>(context,
                                  listen: false)
                              .canApprove('PenaltyTickets'))
                            _actionBtn(Icons.close, 'Hủy phạt', Colors.orange,
                                () => _cancelTicket(ticket['id'].toString())),
                          if (Provider.of<PermissionProvider>(context,
                                  listen: false)
                              .canApprove('PenaltyTickets'))
                            const SizedBox(width: 6),
                          if (Provider.of<PermissionProvider>(context,
                                  listen: false)
                              .canApprove('PenaltyTickets'))
                            FilledButton.icon(
                              onPressed: () =>
                                  _approveTicket(ticket['id'].toString()),
                              icon: const Icon(Icons.check, size: 16),
                              label: Text(tr('Duyệt'),
                                  style: TextStyle(fontSize: 12)),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF16A34A),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                minimumSize: Size.zero,
                              ),
                            ),
                        ],
                        if (isApproved) ...[
                          if (ticket['cashTransactionCode'] != null) ...[
                            Text(tr('${tr('Phiếu thu: ')}${ticket['cashTransactionCode']}'),
                                style: TextStyle(
                                    fontSize: 11, color: Colors.green[600])),
                            const SizedBox(width: 8),
                          ],
                          if (Provider.of<PermissionProvider>(context,
                                  listen: false)
                              .canApprove('PenaltyTickets'))
                            _actionBtn(
                                Icons.undo,
                                'Hoàn duyệt',
                                Colors.orange,
                                () =>
                                    _unapproveTicket(ticket['id'].toString())),
                        ],
                      ],
                    ),
                  ],
                  if (status == 'Cancelled' &&
                      ticket['cancellationReason'] != null) ...[
                    const SizedBox(height: 6),
                    Text(tr('${tr('Lý do hủy: ')}${ticket['cancellationReason']}'),
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.red[300],
                            fontStyle: FontStyle.italic)),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _actionBtn(
      IconData icon, String label, Color color, VoidCallback onPressed) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(tr(label), style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.5)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildPagination() {
    final totalPages = (_totalCount / _pageSize).ceil();
    final start = _totalCount > 0 ? (_currentPage - 1) * _pageSize + 1 : 0;
    final end = (_currentPage * _pageSize).clamp(0, _totalCount);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          Text(tr('Hiển thị $start-$end / $_totalCount'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('Hiển thị:'),
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
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
                    items: _pageSizeOptions
                        .map((s) =>
                            DropdownMenuItem(value: s, child: Text(tr('$s'))))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _pageSize = v;
                          _currentPage = 1;
                        });
                        _loadTickets();
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
                    ? () {
                        setState(() => _currentPage--);
                        _loadTickets();
                      }
                    : null,
                visualDensity: VisualDensity.compact,
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                    color: HrmPageChrome.primaryNavy,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(tr('$_currentPage / $totalPages'),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: _currentPage < totalPages
                    ? () {
                        setState(() => _currentPage++);
                        _loadTickets();
                      }
                    : null,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
