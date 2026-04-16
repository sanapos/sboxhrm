import 'package:flutter/material.dart';
import '../utils/file_saver.dart' as file_saver;
import '../utils/web_canvas.dart' as web_canvas;
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as excel_lib;
import '../services/api_service.dart';
import '../widgets/loading_widget.dart';
import '../widgets/empty_state.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/app_button.dart';
import '../utils/responsive_helper.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';

class AttendanceApprovalScreen extends StatefulWidget {
  const AttendanceApprovalScreen({super.key});

  @override
  State<AttendanceApprovalScreen> createState() =>
      _AttendanceApprovalScreenState();
}

class _AttendanceApprovalScreenState extends State<AttendanceApprovalScreen> {
  final ApiService _apiService = ApiService();

  // Data
  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _employees = [];
  int _totalCount = 0;
  bool _isLoading = true;

  // Filters
  int _statusFilter = -1; // -1 = all, 0 = pending, 1 = approved, 2 = rejected
  int _actionFilter = -1; // -1 = all, 0 = add, 1 = edit, 2 = delete
  Set<String> _selectedEmployeeIds = {};
  String _selectedDatePreset = 'all';
  DateTime? _fromDate;
  DateTime? _toDate;
  bool _isExporting = false;

  // Sorting
  String _sortColumn = 'createdAt';
  bool _sortAscending = false;

  // Mobile UI state
  bool _showMobileFilters = false;

  // Pagination
  int _currentPage = 1;
  int _itemsPerPage = 50;
  final List<int> _pageSizeOptions = [25, 50, 100, 200];

  @override
  void initState() {
    super.initState();
    _loadEmployees();
    _loadData();
  }

  Future<void> _loadEmployees() async {
    try {
      final employees = await _apiService.getEmployees(pageSize: 500);
      if (mounted) {
        setState(() => _employees = List<Map<String, dynamic>>.from(
            employees.map((e) => e as Map<String, dynamic>)));
      }
    } catch (e) {
      debugPrint('Error loading employees: $e');
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final result = await _apiService.getAttendanceCorrections(
        page: _currentPage,
        pageSize: _itemsPerPage,
        status: _statusFilter >= 0 ? _statusFilter : null,
        fromDate: _fromDate,
        toDate: _toDate,
        employeeUserId: _selectedEmployeeIds.length == 1
            ? _selectedEmployeeIds.first
            : null,
      );
      if (mounted) {
        setState(() {
          if (result['isSuccess'] == true && result['data'] != null) {
            final data = result['data'];
            var items = List<Map<String, dynamic>>.from(data['items'] ?? []);
            // Client-side filters
            if (_selectedEmployeeIds.length > 1) {
              items = items.where((r) {
                final empUserId = r['employeeUserId']?.toString() ?? '';
                return _selectedEmployeeIds.contains(empUserId);
              }).toList();
            }
            if (_actionFilter >= 0) {
              items = items.where((r) {
                return _parseAction(r['action']) == _actionFilter;
              }).toList();
            }
            // Sort
            items.sort((a, b) {
              int cmp = 0;
              switch (_sortColumn) {
                case 'newDate':
                  final da = DateTime.tryParse(
                      '${a['newDate'] ?? ''} ${a['newTime'] ?? ''}');
                  final db = DateTime.tryParse(
                      '${b['newDate'] ?? ''} ${b['newTime'] ?? ''}');
                  cmp = (da ?? DateTime(1900)).compareTo(db ?? DateTime(1900));
                  break;
                case 'createdAt':
                  final da =
                      DateTime.tryParse(a['createdAt']?.toString() ?? '');
                  final db =
                      DateTime.tryParse(b['createdAt']?.toString() ?? '');
                  cmp = (da ?? DateTime(1900)).compareTo(db ?? DateTime(1900));
                  break;
                case 'approvedDate':
                  final da =
                      DateTime.tryParse(a['approvedDate']?.toString() ?? '');
                  final db =
                      DateTime.tryParse(b['approvedDate']?.toString() ?? '');
                  cmp = (da ?? DateTime(1900)).compareTo(db ?? DateTime(1900));
                  break;
              }
              return _sortAscending ? cmp : -cmp;
            });
            _requests = items;
            _totalCount = _selectedEmployeeIds.length > 1 || _actionFilter >= 0
                ? items.length
                : (data['totalCount'] ?? 0);
          } else {
            _requests = [];
            _totalCount = 0;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading correction requests: $e');
      if (mounted) {
        appNotification.showError(
            title: 'Lỗi', message: 'Không thể tải dữ liệu');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyDatePreset(String preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _selectedDatePreset = preset;
      switch (preset) {
        case 'today':
          _fromDate = today;
          _toDate = today.add(const Duration(days: 1));
          break;
        case 'yesterday':
          _fromDate = today.subtract(const Duration(days: 1));
          _toDate = today;
          break;
        case 'this_week':
          _fromDate = today.subtract(Duration(days: today.weekday - 1));
          _toDate = today.add(const Duration(days: 1));
          break;
        case 'last_week':
          final startOfThisWeek =
              today.subtract(Duration(days: today.weekday - 1));
          _fromDate = startOfThisWeek.subtract(const Duration(days: 7));
          _toDate = startOfThisWeek;
          break;
        case 'this_month':
          _fromDate = DateTime(now.year, now.month, 1);
          _toDate = today.add(const Duration(days: 1));
          break;
        case 'last_month':
          _fromDate = DateTime(now.year, now.month - 1, 1);
          _toDate = DateTime(now.year, now.month, 1);
          break;
        case 'all':
          _fromDate = null;
          _toDate = null;
          break;
      }
      _currentPage = 1;
    });
    _loadData();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _fromDate != null && _toDate != null
          ? DateTimeRange(start: _fromDate!, end: _toDate!)
          : null,
    );
    if (picked != null) {
      setState(() {
        _selectedDatePreset = 'custom';
        _fromDate = picked.start;
        _toDate = picked.end.add(const Duration(days: 1));
        _currentPage = 1;
      });
      _loadData();
    }
  }

  // ── Actions ──

  Future<void> _approveRequest(Map<String, dynamic> req) async {
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Duyệt yêu cầu'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Nhân viên: ${req['employeeName'] ?? ''} (${req['employeeCode'] ?? ''})'),
              const SizedBox(height: 4),
              Text('Loại: ${_getActionLabel(req['action'])}'),
              const SizedBox(height: 4),
              Text('Lý do: ${req['reason'] ?? ''}'),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú (tùy chọn)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          AppDialogActions(
            onCancel: () => Navigator.pop(ctx, false),
            onConfirm: () => Navigator.pop(ctx, true),
            confirmLabel: 'Duyệt',
            confirmIcon: Icons.check,
            confirmVariant: AppButtonVariant.success,
          ),
        ],
      ),
    );
    if (confirmed != true) {
      noteController.dispose();
      return;
    }

    final result = await _apiService.approveAttendanceCorrection(
      requestId: req['id'],
      isApproved: true,
      approverNote: noteController.text.isNotEmpty ? noteController.text : null,
    );
    noteController.dispose();
    if (result['isSuccess'] == true) {
      appNotification.showSuccess(
          title: 'Thành công', message: 'Đã duyệt yêu cầu');
      _loadData();
    } else {
      appNotification.showError(
          title: 'Lỗi', message: result['message'] ?? 'Có lỗi xảy ra');
    }
  }

  Future<void> _rejectRequest(Map<String, dynamic> req) async {
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Từ chối yêu cầu'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Nhân viên: ${req['employeeName'] ?? ''} (${req['employeeCode'] ?? ''})'),
              const SizedBox(height: 4),
              Text('Loại: ${_getActionLabel(req['action'])}'),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'Lý do từ chối *',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          AppDialogActions(
            onCancel: () => Navigator.pop(ctx, false),
            onConfirm: () {
              if (noteController.text.trim().isEmpty) {
                appNotification.showWarning(
                    title: 'Cảnh báo', message: 'Vui lòng nhập lý do từ chối');
                return;
              }
              Navigator.pop(ctx, true);
            },
            confirmLabel: 'Từ chối',
            confirmIcon: Icons.close,
            confirmVariant: AppButtonVariant.danger,
          ),
        ],
      ),
    );
    if (confirmed != true) {
      noteController.dispose();
      return;
    }

    final result = await _apiService.approveAttendanceCorrection(
      requestId: req['id'],
      isApproved: false,
      approverNote: noteController.text.trim(),
    );
    noteController.dispose();
    if (result['isSuccess'] == true) {
      appNotification.showSuccess(
          title: 'Thành công', message: 'Đã từ chối yêu cầu');
      _loadData();
    } else {
      appNotification.showError(
          title: 'Lỗi', message: result['message'] ?? 'Có lỗi xảy ra');
    }
  }

  Future<void> _undoApproval(Map<String, dynamic> req) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hoàn duyệt'),
        content: Text(
            'Bạn có chắc muốn hoàn duyệt yêu cầu của ${req['employeeName'] ?? ''}?\n\nChấm công đã ghi sẽ bị xóa.'),
        actions: [
          AppDialogActions(
            onCancel: () => Navigator.pop(ctx, false),
            onConfirm: () => Navigator.pop(ctx, true),
            confirmLabel: 'Hoàn duyệt',
            confirmIcon: Icons.undo,
            confirmVariant: AppButtonVariant.warning,
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result =
        await _apiService.undoAttendanceCorrectionApproval(req['id']);
    if (result['isSuccess'] == true) {
      appNotification.showSuccess(
          title: 'Thành công', message: 'Đã hoàn duyệt yêu cầu');
      _loadData();
    } else {
      appNotification.showError(
          title: 'Lỗi', message: result['message'] ?? 'Có lỗi xảy ra');
    }
  }

  Future<void> _deleteRequest(Map<String, dynamic> req) async {
    final status = _parseStatus(req['status']);
    if (status == 1) {
      appNotification.showWarning(
          title: 'Không thể xóa',
          message: 'Yêu cầu đã duyệt không thể xóa. Hãy hoàn duyệt trước.');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa yêu cầu'),
        content: Text(
            'Bạn có chắc muốn xóa yêu cầu của ${req['employeeName'] ?? ''}?'),
        actions: [
          AppDialogActions.delete(
            onCancel: () => Navigator.pop(ctx, false),
            onConfirm: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await _apiService.deleteAttendanceCorrection(req['id']);
    if (result['isSuccess'] == true) {
      appNotification.showSuccess(
          title: 'Thành công', message: 'Đã xóa yêu cầu');
      _loadData();
    } else {
      appNotification.showError(
          title: 'Lỗi', message: result['message'] ?? 'Có lỗi xảy ra');
    }
  }

  // ── Helpers ──

  static int _parseAction(dynamic action) {
    if (action is int) return action;
    if (action is num) return action.toInt();
    final s = action?.toString() ?? '';
    final parsed = int.tryParse(s);
    if (parsed != null) return parsed;
    switch (s) {
      case 'Add':
        return 0;
      case 'Edit':
        return 1;
      case 'Delete':
        return 2;
      default:
        return -1;
    }
  }

  static int _parseStatus(dynamic status) {
    if (status is int) return status;
    if (status is num) return status.toInt();
    final s = status?.toString() ?? '';
    final parsed = int.tryParse(s);
    if (parsed != null) return parsed;
    switch (s) {
      case 'Pending':
        return 0;
      case 'Approved':
        return 1;
      case 'Rejected':
        return 2;
      default:
        return 0;
    }
  }

  String _getActionLabel(dynamic action) {
    switch (_parseAction(action)) {
      case 0:
        return 'Thêm mới';
      case 1:
        return 'Chỉnh sửa';
      case 2:
        return 'Xóa';
      default:
        return 'Không rõ';
    }
  }

  Color _getActionColor(dynamic action) {
    switch (_parseAction(action)) {
      case 0:
        return Colors.green;
      case 1:
        return Colors.blue;
      case 2:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusLabel(dynamic status) {
    switch (_parseStatus(status)) {
      case 0:
        return 'Chờ duyệt';
      case 1:
        return 'Đã duyệt';
      case 2:
        return 'Từ chối';
      default:
        return 'Không rõ';
    }
  }

  Color _getStatusColor(dynamic status) {
    switch (_parseStatus(status)) {
      case 0:
        return Colors.orange;
      case 1:
        return Colors.green;
      case 2:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return '--';
    try {
      final dt = date is DateTime ? date : DateTime.parse(date.toString());
      return DateFormat('dd/MM/yyyy').format(dt);
    } catch (_) {
      return '--';
    }
  }

  String _formatTime(dynamic time) {
    if (time == null) return '--';
    try {
      final t = time.toString();
      // TimeSpan comes as "HH:mm:ss" or "HH:mm:ss.fffffff"
      final parts = t.split(':');
      if (parts.length >= 2) {
        return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
      }
      return t;
    } catch (_) {
      return '--';
    }
  }

  String _formatDateTime(dynamic dt) {
    if (dt == null) return '--';
    try {
      final d = dt is DateTime ? dt : DateTime.parse(dt.toString());
      return DateFormat('dd/MM/yyyy HH:mm').format(d.toLocal());
    } catch (_) {
      return '--';
    }
  }

  String _getApprovalStatusLabel(int status) {
    switch (status) {
      case 0: return 'Chờ duyệt';
      case 1: return 'Đã duyệt';
      case 2: return 'Từ chối';
      case 3: return 'Đã hủy';
      case 4: return 'Hết hạn';
      default: return 'Không rõ';
    }
  }

  Color _getApprovalStatusColor(int status) {
    switch (status) {
      case 0: return Colors.orange;
      case 1: return Colors.green;
      case 2: return Colors.red;
      case 3: return Colors.grey;
      case 4: return Colors.grey;
      default: return Colors.grey;
    }
  }

  IconData _getApprovalStatusIcon(int status) {
    switch (status) {
      case 0: return Icons.hourglass_empty;
      case 1: return Icons.check_circle;
      case 2: return Icons.cancel;
      case 3: return Icons.block;
      case 4: return Icons.timer_off;
      default: return Icons.help_outline;
    }
  }

  Widget _buildApprovalProgress(Map<String, dynamic> req) {
    final totalLevels = req['totalApprovalLevels'] ?? 1;
    final currentStep = req['currentApprovalStep'] ?? 0;
    final records = req['approvalRecords'] as List? ?? [];
    final statusInt = _parseStatus(req['status']);

    if (totalLevels <= 1 && records.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.account_tree, size: 14, color: Colors.blueGrey),
            const SizedBox(width: 4),
            Text(
              'Tiến trình duyệt ($currentStep/$totalLevels)',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blueGrey),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (records.isNotEmpty) ...[
          ...records.map((record) {
            final stepStatus = record['status'] ?? 0;
            final stepStatusInt = stepStatus is int ? stepStatus : int.tryParse(stepStatus.toString()) ?? 0;
            final color = _getApprovalStatusColor(stepStatusInt);
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(_getApprovalStatusIcon(stepStatusInt), size: 16, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 11, color: Colors.black87),
                        children: [
                          TextSpan(
                            text: record['stepName'] ?? 'Bước ${record['stepOrder'] ?? '?'}',
                            style: TextStyle(fontWeight: FontWeight.w600, color: color),
                          ),
                          const TextSpan(text: ': '),
                          TextSpan(
                            text: stepStatusInt == 0
                              ? (record['assignedUserName'] ?? 'Chưa xác định')
                              : (record['actualUserName'] ?? record['assignedUserName'] ?? '--'),
                          ),
                          if (record['note'] != null && record['note'].toString().isNotEmpty) ...[
                            TextSpan(text: ' - ', style: TextStyle(color: Colors.grey[500])),
                            TextSpan(text: record['note'], style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (record['actionDate'] != null)
                    Text(
                      _formatDateTime(record['actionDate']),
                      style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    ),
                ],
              ),
            );
          }),
        ] else ...[
          // Fallback: show simple progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: statusInt == 2 ? 1.0 : (totalLevels > 0 ? currentStep / totalLevels : 0),
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(
                statusInt == 2 ? Colors.red : (currentStep >= totalLevels ? Colors.green : Colors.blue),
              ),
              minHeight: 6,
            ),
          ),
        ],
      ],
    );
  }

  void _showRequestDetail(Map<String, dynamic> req) {
    final statusInt = _parseStatus(req['status']);
    final totalLevels = req['totalApprovalLevels'] ?? 1;
    final records = req['approvalRecords'] as List? ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: scrollController,
            children: [
              // Header
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _getStatusColor(req['status']).withValues(alpha: 0.15),
                    child: Icon(Icons.description, color: _getStatusColor(req['status'])),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(req['employeeName'] ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Text(req['employeeCode'] ?? '', style: TextStyle(fontSize: 13, color: Colors.grey[600])),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(req['status']).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(_getStatusLabel(req['status']),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _getStatusColor(req['status']))),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Request info
              _detailRow('Loại yêu cầu', _getActionLabel(req['action'])),
              _detailRow('Ngày mới', _formatDate(req['newDate'])),
              _detailRow('Giờ mới', _formatTime(req['newTime'])),
              _detailRow('Ngày cũ', _formatDate(req['oldDate'])),
              _detailRow('Giờ cũ', _formatTime(req['oldTime'])),
              _detailRow('Lý do', req['reason'] ?? '--'),
              _detailRow('Ngày tạo', _formatDateTime(req['createdAt'])),

              // Approval progress section
              if (totalLevels > 1 || records.isNotEmpty) ...[
                const Divider(height: 24),
                const Text('Tiến trình duyệt đa cấp', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _buildApprovalTimeline(records, statusInt),
              ] else ...[
                const Divider(height: 24),
                _detailRow('Người duyệt', req['approvedByName'] ?? '--'),
                _detailRow('Ngày duyệt', _formatDateTime(req['approvedDate'])),
                _detailRow('Ghi chú duyệt', req['approverNote'] ?? '--'),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildApprovalTimeline(List records, int requestStatus) {
    if (records.isEmpty) {
      return const Text('Chưa có dữ liệu duyệt', style: TextStyle(fontSize: 12, color: Colors.grey));
    }

    return Column(
      children: records.asMap().entries.map((entry) {
        final idx = entry.key;
        final record = entry.value;
        final isLast = idx == records.length - 1;
        final stepStatus = record['status'] ?? 0;
        final stepStatusInt = stepStatus is int ? stepStatus : int.tryParse(stepStatus.toString()) ?? 0;
        final color = _getApprovalStatusColor(stepStatusInt);

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Timeline line + dot
              SizedBox(
                width: 30,
                child: Column(
                  children: [
                    Container(
                      width: 20, height: 20,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: color, width: 2),
                      ),
                      child: Icon(_getApprovalStatusIcon(stepStatusInt), size: 12, color: color),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(width: 2, color: Colors.grey[300]),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Step content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            record['stepName'] ?? 'Bước ${record['stepOrder'] ?? idx + 1}',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _getApprovalStatusLabel(stepStatusInt),
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stepStatusInt == 0
                          ? 'Người duyệt: ${record['assignedUserName'] ?? 'Chưa xác định'}'
                          : 'Người duyệt: ${record['actualUserName'] ?? record['assignedUserName'] ?? '--'}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      ),
                      if (record['note'] != null && record['note'].toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Ghi chú: ${record['note']}',
                            style: TextStyle(fontSize: 11, color: Colors.grey[600], fontStyle: FontStyle.italic),
                          ),
                        ),
                      if (record['actionDate'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            _formatDateTime(record['actionDate']),
                            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildApprovalProgressCompact(Map<String, dynamic> req) {
    final totalLevels = req['totalApprovalLevels'] ?? 1;
    final currentStep = req['currentApprovalStep'] ?? 0;
    final statusInt = _parseStatus(req['status']);

    if (totalLevels <= 1) {
      return Text(statusInt == 0 ? 'Đơn cấp' : '--', style: TextStyle(fontSize: 11, color: Colors.grey[500]));
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(totalLevels, (i) {
          Color dotColor;
          if (statusInt == 2) {
            dotColor = i < currentStep ? Colors.green : (i == currentStep ? Colors.red : Colors.grey[300]!);
          } else {
            dotColor = i < currentStep ? Colors.green : (i == currentStep && statusInt == 0 ? Colors.orange : Colors.grey[300]!);
          }
          return Container(
            width: 12, height: 12,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: dotColor.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: dotColor, width: 1.5),
            ),
            child: i < currentStep
              ? Icon(Icons.check, size: 8, color: dotColor)
              : (i == currentStep && statusInt == 2
                  ? Icon(Icons.close, size: 8, color: dotColor)
                  : null),
          );
        }),
        const SizedBox(width: 4),
        Icon(Icons.info_outline, size: 12, color: Colors.blue[300]),
      ],
    );
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final isMobile = Responsive.isMobile(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border:
            Border(bottom: BorderSide(color: Colors.grey[300]!, width: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.fact_check_outlined,
              size: 20, color: Theme.of(context).primaryColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Duyệt chấm công',
                style: TextStyle(fontSize: isMobile ? 16 : 18, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('$_totalCount',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor)),
          ),
          const SizedBox(width: 8),
          if (isMobile) ...[
            GestureDetector(
              onTap: () => setState(() => _showMobileFilters = !_showMobileFilters),
              child: Container(
                padding: const EdgeInsets.all(6),
                child: Stack(
                  children: [
                    Icon(
                      _showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
                      size: 20, color: Theme.of(context).primaryColor,
                    ),
                    if (_selectedDatePreset != 'all' || _selectedEmployeeIds.isNotEmpty || _actionFilter != -1)
                      Positioned(
                        right: 0, top: 0,
                        child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle)),
                      ),
                  ],
                ),
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: Theme.of(context).primaryColor),
              onSelected: (value) {
                if (value == 'excel') _exportToExcel();
                if (value == 'png') _exportToPng();
              },
              itemBuilder: (context) => [
                if (Provider.of<PermissionProvider>(context, listen: false).canExport('AttendanceApproval'))
                const PopupMenuItem(value: 'excel', child: Row(children: [Icon(Icons.table_chart_outlined, size: 18, color: Colors.green), SizedBox(width: 8), Text('Xuất Excel')])),
                if (Provider.of<PermissionProvider>(context, listen: false).canExport('AttendanceApproval'))
                const PopupMenuItem(value: 'png', child: Row(children: [Icon(Icons.image_outlined, size: 18, color: Colors.blue), SizedBox(width: 8), Text('Xuất PNG')])),
              ],
            ),
          ]
          else ...[
            _buildHeaderButton(Icons.table_chart_outlined, 'Excel', Colors.green,
                _exportToExcel),
            const SizedBox(width: 8),
            _buildHeaderButton(
                Icons.image_outlined, 'PNG', Colors.blue, _exportToPng),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderButton(
      IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildHeaderAction(
      IconData icon, String tooltip, Color color, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: color),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        splashRadius: 18,
      ),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        children: [
          _buildStatusTabs(),
          const SizedBox(height: 6),
          if (!Responsive.isMobile(context) || _showMobileFilters) ...[
            _buildFilters(),
            const SizedBox(height: 6),
          ],
          Expanded(
            child: _isLoading
                ? const LoadingWidget(message: 'Đang tải dữ liệu...')
                : _requests.isEmpty
                    ? const EmptyState(
                        icon: Icons.fact_check_outlined,
                        title: 'Không có yêu cầu',
                        description: 'Chưa có yêu cầu chấm công nào')
                    : Column(
                        children: [
                          Expanded(child: _buildTable()),
                          if (!Responsive.isMobile(context)) _buildPagination(),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusTabs() {
    final tabs = [
      {'label': 'Tất cả', 'value': -1, 'color': Colors.grey},
      {'label': 'Chờ duyệt', 'value': 0, 'color': Colors.orange},
      {'label': 'Đã duyệt', 'value': 1, 'color': Colors.green},
      {'label': 'Từ chối', 'value': 2, 'color': Colors.red},
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: tabs.map((tab) {
          final isSelected = _statusFilter == tab['value'];
          final color = tab['color'] as Color;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _statusFilter = tab['value'] as int;
                  _currentPage = 1;
                });
                _loadData();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? color.withValues(alpha: 0.15) : null,
                  borderRadius: BorderRadius.circular(6),
                  border: isSelected
                      ? Border.all(color: color.withValues(alpha: 0.5))
                      : null,
                ),
                child: Center(
                  child: Text(
                    tab['label'] as String,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? color : Colors.grey[600],
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _buildDropdown<String>(
            value: _selectedDatePreset,
            items: const [
              DropdownMenuItem(value: 'all', child: Text('Tất cả')),
              DropdownMenuItem(value: 'today', child: Text('Hôm nay')),
              DropdownMenuItem(value: 'yesterday', child: Text('Hôm qua')),
              DropdownMenuItem(value: 'this_week', child: Text('Tuần này')),
              DropdownMenuItem(value: 'last_week', child: Text('Tuần trước')),
              DropdownMenuItem(value: 'this_month', child: Text('Tháng này')),
              DropdownMenuItem(value: 'last_month', child: Text('Tháng trước')),
              DropdownMenuItem(value: 'custom', child: Text('Tùy chọn')),
            ],
            onChanged: (val) {
              if (val == 'custom') {
                _pickDateRange();
              } else if (val != null) {
                _applyDatePreset(val);
              }
            },
            width: 130,
          ),
          if (_fromDate != null && _toDate != null)
            InkWell(
              onTap: _pickDateRange,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${DateFormat('dd/MM').format(_fromDate!)} - ${DateFormat('dd/MM').format(_toDate!)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          _buildEmployeeFilter(),
          _buildDropdown<int>(
            value: _actionFilter,
            items: const [
              DropdownMenuItem(value: -1, child: Text('Tất cả loại')),
              DropdownMenuItem(value: 0, child: Text('Thêm mới')),
              DropdownMenuItem(value: 1, child: Text('Chỉnh sửa')),
              DropdownMenuItem(value: 2, child: Text('Xóa')),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _actionFilter = val;
                  _currentPage = 1;
                });
                _loadData();
              }
            },
            width: 130,
          ),
          Text(
            '$_totalCount yêu cầu',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildEmployeeFilter() {
    final selectedCount = _selectedEmployeeIds.length;
    return InkWell(
      onTap: () => _showEmployeeSelectionDialog(),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 38,
        constraints: const BoxConstraints(minWidth: 160, maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selectedCount > 0
                ? Theme.of(context).primaryColor
                : Colors.grey[400]!,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people,
                size: 16,
                color: selectedCount > 0
                    ? Theme.of(context).primaryColor
                    : Colors.grey[600]),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                selectedCount == 0
                    ? 'Tất cả nhân viên'
                    : 'Nhân viên ($selectedCount)',
                style: TextStyle(
                  fontSize: 12,
                  color: selectedCount > 0
                      ? Theme.of(context).primaryColor
                      : Colors.grey[700],
                  fontWeight:
                      selectedCount > 0 ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey[600]),
          ],
        ),
      ),
    );
  }

  void _showEmployeeSelectionDialog() {
    Set<String> tempSelected = Set.from(_selectedEmployeeIds);
    String searchQuery = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final filtered = _employees.where((e) {
            if (searchQuery.isEmpty) return true;
            final name = '${e['lastName'] ?? ''} ${e['firstName'] ?? ''}'
                .trim()
                .toLowerCase();
            final code = (e['employeeCode'] ?? '').toString().toLowerCase();
            return name.contains(searchQuery.toLowerCase()) ||
                code.contains(searchQuery.toLowerCase());
          }).toList();

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.people, size: 20),
                const SizedBox(width: 8),
                const Text('Chọn nhân viên', style: TextStyle(fontSize: 16)),
                const Spacer(),
                TextButton(
                  onPressed: () => setDialogState(() => tempSelected.clear()),
                  child: const Text('Bỏ chọn tất cả',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            content: SizedBox(
              width: Responsive.dialogWidth(context),
              height: 400,
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm nhân viên...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (v) => setDialogState(() => searchQuery = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final emp = filtered[i];
                        final empId = emp['applicationUserId']?.toString() ??
                            emp['id']?.toString() ??
                            '';
                        final name =
                            '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'
                                .trim();
                        final code = emp['employeeCode']?.toString() ?? '';
                        final isSelected = tempSelected.contains(empId);
                        return CheckboxListTile(
                          dense: true,
                          value: isSelected,
                          title:
                              Text(name, style: const TextStyle(fontSize: 13)),
                          subtitle: Text(code,
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey[600])),
                          onChanged: (val) {
                            setDialogState(() {
                              if (val == true) {
                                tempSelected.add(empId);
                              } else {
                                tempSelected.remove(empId);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              AppDialogActions(
                onConfirm: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _selectedEmployeeIds = tempSelected;
                    _currentPage = 1;
                  });
                  _loadData();
                },
                confirmLabel: 'Áp dụng (${tempSelected.length})',
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    double width = 120,
  }) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<T>(
        initialValue: value,
        items: items,
        onChanged: onChanged,
        isExpanded: true,
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
        ),
        style: const TextStyle(fontSize: 13, color: Colors.black87),
      ),
    );
  }

  Widget _buildTable() {
    final startIndex = (_currentPage - 1) * _itemsPerPage;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return _buildMobileCardList(startIndex);
        }
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: Colors.grey[300]!),
          ),
          child: Scrollbar(
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                      minWidth: MediaQuery.of(context).size.width - 280),
                  child: DataTable(
                    showCheckboxColumn: false,
                    headingRowHeight: 40,
                    dataRowMinHeight: 38,
                    dataRowMaxHeight: 52,
                    columnSpacing: 16,
                    horizontalMargin: 12,
                    sortColumnIndex: _sortColumn == 'newDate'
                        ? 4
                        : _sortColumn == 'createdAt'
                            ? 9
                            : _sortColumn == 'approvedDate'
                                ? 11
                                : null,
                    sortAscending: _sortAscending,
                    headingRowColor: WidgetStateProperty.all(Colors.grey[50]),
                    columns: [
                      const DataColumn(
                          label: Expanded(
                              child: Text('STT',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)))),
                      const DataColumn(
                          label: Expanded(
                              child: Text('Tên nhân viên',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)))),
                      const DataColumn(
                          label: Expanded(
                              child: Text('Loại',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)))),
                      const DataColumn(
                          label: Expanded(
                              child: Text('Trạng thái',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)))),
                      DataColumn(
                          label: const Expanded(
                              child: Text('Ngày mới',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12))),
                          onSort: (_, asc) {
                            setState(() {
                              _sortColumn = 'newDate';
                              _sortAscending = asc;
                            });
                            _loadData();
                          }),
                      const DataColumn(
                          label: Expanded(
                              child: Text('Giờ mới',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)))),
                      const DataColumn(
                          label: Expanded(
                              child: Text('Ngày cũ',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)))),
                      const DataColumn(
                          label: Expanded(
                              child: Text('Giờ cũ',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)))),
                      const DataColumn(
                          label: Expanded(
                              child: Text('Lý do',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)))),
                      DataColumn(
                          label: const Expanded(
                              child: Text('Ngày tạo',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12))),
                          onSort: (_, asc) {
                            setState(() {
                              _sortColumn = 'createdAt';
                              _sortAscending = asc;
                            });
                            _loadData();
                          }),
                      const DataColumn(
                          label: Expanded(
                              child: Text('Người duyệt',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)))),
                      DataColumn(
                          label: const Expanded(
                              child: Text('Ngày duyệt',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12))),
                          onSort: (_, asc) {
                            setState(() {
                              _sortColumn = 'approvedDate';
                              _sortAscending = asc;
                            });
                            _loadData();
                          }),
                      const DataColumn(
                          label: Expanded(
                              child: Text('Ghi chú duyệt',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)))),
                      const DataColumn(
                          label: Expanded(
                              child: Text('Tiến trình',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)))),
                      const DataColumn(
                          label: Expanded(
                              child: Text('Hành động',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12)))),
                    ],
                    rows: _requests.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final req = entry.value;
                      final status = req['status'] ?? 0;
                      final statusInt = _parseStatus(status);

                      return DataRow(
                        cells: [
                          DataCell(Center(
                              child: Text('${startIndex + idx + 1}',
                                  style: const TextStyle(fontSize: 12)))),
                          DataCell(Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(req['employeeName'] ?? '',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500)),
                                Text(req['employeeCode'] ?? '',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey[600])),
                              ],
                            ),
                          )),
                          DataCell(Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getActionColor(req['action'])
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _getActionLabel(req['action']),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _getActionColor(req['action']),
                                ),
                              ),
                            ),
                          )),
                          DataCell(Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _getStatusColor(status)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _getStatusLabel(status),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _getStatusColor(status),
                                ),
                              ),
                            ),
                          )),
                          DataCell(Center(
                              child: Text(_formatDate(req['newDate']),
                                  style: const TextStyle(fontSize: 12)))),
                          DataCell(Center(
                              child: Text(_formatTime(req['newTime']),
                                  style: const TextStyle(fontSize: 12)))),
                          DataCell(Center(
                              child: Text(_formatDate(req['oldDate']),
                                  style: const TextStyle(fontSize: 12)))),
                          DataCell(Center(
                              child: Text(_formatTime(req['oldTime']),
                                  style: const TextStyle(fontSize: 12)))),
                          DataCell(Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 150),
                              child: Text(req['reason'] ?? '',
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2),
                            ),
                          )),
                          DataCell(Center(
                              child: Text(_formatDateTime(req['createdAt']),
                                  style: const TextStyle(fontSize: 12)))),
                          DataCell(Center(
                              child: Text(req['approvedByName'] ?? '--',
                                  style: const TextStyle(fontSize: 12)))),
                          DataCell(Center(
                              child: Text(_formatDateTime(req['approvedDate']),
                                  style: const TextStyle(fontSize: 12)))),
                          DataCell(Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 120),
                              child: Text(req['approverNote'] ?? '--',
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis),
                            ),
                          )),
                          DataCell(
                            Center(
                              child: InkWell(
                                onTap: () => _showRequestDetail(req),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 160),
                                  child: _buildApprovalProgressCompact(req),
                                ),
                              ),
                            ),
                          ),
                          DataCell(Center(
                              child: _buildActionButtons(req, statusInt))),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileCardList(int startIndex) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _requests.length,
      itemBuilder: (_, index) {
          final req = _requests[index];
          final status = _parseStatus(req['status']);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE4E4E7)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _showRequestDetail(req),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(
                    children: [
                      Row(children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: _getStatusColor(req['status']).withValues(alpha: 0.15),
                          child: Icon(Icons.access_time, color: _getStatusColor(req['status']), size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(req['employeeName'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text([req['employeeCode'] ?? '', '${_formatDate(req['oldDate'])} → ${_formatDate(req['newDate'])}'].where((s) => s.isNotEmpty).join(' · '),
                              style: const TextStyle(color: Color(0xFF71717A), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ]),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: _getStatusColor(req['status']).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: Text(_getStatusLabel(req['status']), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _getStatusColor(req['status']))),
                        ),
                        if (status == 0) ...[
                          const SizedBox(width: 6),
                          if (Provider.of<PermissionProvider>(context, listen: false).canApprove('AttendanceApproval'))
                          InkWell(onTap: () => _approveRequest(req), child: const Icon(Icons.check_circle_outline, size: 22, color: Colors.green)),
                          const SizedBox(width: 4),
                          if (Provider.of<PermissionProvider>(context, listen: false).canApprove('AttendanceApproval'))
                          InkWell(onTap: () => _rejectRequest(req), child: const Icon(Icons.cancel_outlined, size: 22, color: Colors.red)),
                        ],
                      ]),
                      if ((req['totalApprovalLevels'] ?? 1) > 1) ...[
                        const SizedBox(height: 8),
                        _buildApprovalProgress(req),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
    );
  }
  Widget _buildActionButtons(Map<String, dynamic> req, int status) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Pending: Approve + Reject
        if (status == 0) ...[
          if (Provider.of<PermissionProvider>(context, listen: false).canApprove('AttendanceApproval'))
          _buildActionBtn(
            icon: Icons.check_circle_outline,
            tooltip: 'Duyệt',
            color: Colors.green,
            onTap: () => _approveRequest(req),
          ),
          const SizedBox(width: 4),
          if (Provider.of<PermissionProvider>(context, listen: false).canApprove('AttendanceApproval'))
          _buildActionBtn(
            icon: Icons.cancel_outlined,
            tooltip: 'Từ chối',
            color: Colors.red,
            onTap: () => _rejectRequest(req),
          ),
        ],
        // Approved: Undo
        if (status == 1 && Provider.of<PermissionProvider>(context, listen: false).canApprove('AttendanceApproval'))
          _buildActionBtn(
            icon: Icons.undo,
            tooltip: 'Hoàn duyệt',
            color: Colors.orange,
            onTap: () => _undoApproval(req),
          ),
        // Pending or Rejected: Delete
        if ((status == 0 || status == 2) && Provider.of<PermissionProvider>(context, listen: false).canDelete('AttendanceApproval')) ...[
          const SizedBox(width: 4),
          _buildActionBtn(
            icon: Icons.delete_outline,
            tooltip: 'Xóa',
            color: Colors.red[300]!,
            onTap: () => _deleteRequest(req),
          ),
        ],
      ],
    );
  }

  Widget _buildActionBtn({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Tooltip(
        message: tooltip,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 18, color: color),
        ),
      ),
    );
  }

  Widget _buildPagination() {
    final totalPages = (_totalCount / _itemsPerPage).ceil();
    final start = _totalCount > 0 ? (_currentPage - 1) * _itemsPerPage + 1 : 0;
    final end = (_currentPage * _itemsPerPage).clamp(0, _totalCount);
    final isMobile = Responsive.isMobile(context);

    final pageNav = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: _currentPage > 1
              ? () {
                  setState(() => _currentPage = 1);
                  _loadData();
                }
              : null,
          icon: const Icon(Icons.first_page, size: 18),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          splashRadius: 16,
        ),
        IconButton(
          onPressed: _currentPage > 1
              ? () {
                  setState(() => _currentPage--);
                  _loadData();
                }
              : null,
          icon: const Icon(Icons.chevron_left, size: 18),
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          splashRadius: 16,
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text('$_currentPage / $totalPages',
              style: TextStyle(fontSize: 12, color: Colors.grey[800])),
          ),
          IconButton(
            onPressed: _currentPage < totalPages
                ? () {
                    setState(() => _currentPage++);
                    _loadData();
                  }
                : null,
            icon: const Icon(Icons.chevron_right, size: 18),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            splashRadius: 16,
          ),
          IconButton(
            onPressed: _currentPage < totalPages
                ? () {
                    setState(() => _currentPage = totalPages);
                    _loadData();
                  }
                : null,
            icon: const Icon(Icons.last_page, size: 18),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            splashRadius: 16,
          ),
        ],
      );

    final infoRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Hiển thị $start-$end / $_totalCount',
          style: TextStyle(fontSize: 12, color: Colors.grey[700]),
        ),
        const SizedBox(width: 8),
        Text('Số dòng:',
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(width: 4),
        Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(4),
          ),
          child: DropdownButton<int>(
            value: _itemsPerPage,
            underline: const SizedBox(),
            isDense: true,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
            items: _pageSizeOptions
                .map((s) => DropdownMenuItem(value: s, child: Text('$s')))
                .toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _itemsPerPage = val;
                  _currentPage = 1;
                });
                _loadData();
              }
            },
          ),
        ),
      ],
    );

    return Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12, vertical: 8),
      child: isMobile
          ? Column(
              children: [
                infoRow,
                const SizedBox(height: 6),
                pageNav,
              ],
            )
          : Row(
              children: [
                infoRow,
                const Spacer(),
                pageNav,
              ],
            ),
    );
  }

  void _exportToExcel() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final wb = excel_lib.Excel.createExcel();
      final sheet = wb['Duyệt chấm công'];
      wb.delete('Sheet1');

      final headers = [
        'STT',
        'Tên nhân viên',
        'Mã NV',
        'Loại',
        'Trạng thái',
        'Ngày mới',
        'Giờ mới',
        'Ngày cũ',
        'Giờ cũ',
        'Lý do',
        'Ngày tạo',
        'Người duyệt',
        'Ngày duyệt',
        'Ghi chú duyệt'
      ];
      sheet.appendRow(headers.map((h) => excel_lib.TextCellValue(h)).toList());

      for (int i = 0; i < _requests.length; i++) {
        final req = _requests[i];
        sheet.appendRow([
          excel_lib.IntCellValue(i + 1),
          excel_lib.TextCellValue(req['employeeName'] ?? ''),
          excel_lib.TextCellValue(req['employeeCode'] ?? ''),
          excel_lib.TextCellValue(_getActionLabel(req['action'])),
          excel_lib.TextCellValue(_getStatusLabel(req['status'])),
          excel_lib.TextCellValue(_formatDate(req['newDate'])),
          excel_lib.TextCellValue(_formatTime(req['newTime'])),
          excel_lib.TextCellValue(_formatDate(req['oldDate'])),
          excel_lib.TextCellValue(_formatTime(req['oldTime'])),
          excel_lib.TextCellValue(req['reason'] ?? ''),
          excel_lib.TextCellValue(_formatDateTime(req['createdAt'])),
          excel_lib.TextCellValue(req['approvedByName'] ?? ''),
          excel_lib.TextCellValue(_formatDateTime(req['approvedDate'])),
          excel_lib.TextCellValue(req['approverNote'] ?? ''),
        ]);
      }

      final bytes = wb.encode();
      if (bytes != null) {
        await file_saver.saveFileBytes(bytes,
            'duyet_cham_cong_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx',
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        appNotification.showSuccess(
            title: 'Thành công', message: 'Đã xuất file Excel');
      }
    } catch (e) {
      appNotification.showError(
          title: 'Lỗi', message: 'Không thể xuất Excel: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _exportToPng() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final headers = [
        'STT',
        'Tên nhân viên',
        'Loại',
        'Trạng thái',
        'Ngày mới',
        'Giờ mới',
        'Ngày cũ',
        'Giờ cũ',
        'Lý do',
        'Ngày tạo',
        'Người duyệt',
        'Ngày duyệt',
        'Ghi chú duyệt'
      ];
      final colWidths = [
        40,
        150,
        80,
        80,
        90,
        70,
        90,
        70,
        150,
        120,
        120,
        120,
        120
      ];
      final totalWidth = colWidths.fold<int>(0, (sum, w) => sum + w) + 20;
      const rowHeight = 28;
      const headerHeight = 36;
      const titleHeight = 40;
      final totalHeight =
          titleHeight + headerHeight + (_requests.length * rowHeight) + 20;

      final canvas = web_canvas.renderToPngDataUrl(
        width: totalWidth,
        height: totalHeight,
        draw: (ctx) {
          // Background
          ctx.fillStyle = '#FFFFFF';
          ctx.fillRect(0, 0, totalWidth.toDouble(), totalHeight.toDouble());

          // Title
          ctx.fillStyle = '#1a1a1a';
          ctx.font = 'bold 16px Arial';
          ctx.fillText('Duyệt chấm công', 10, 28);

          // Header
          ctx.fillStyle = '#f5f5f5';
          ctx.fillRect(0, titleHeight.toDouble(), totalWidth.toDouble(),
              headerHeight.toDouble());
          ctx.fillStyle = '#333333';
          ctx.font = 'bold 12px Arial';
          double x = 10;
          for (int i = 0; i < headers.length; i++) {
            ctx.fillText(headers[i], x, titleHeight + 23);
            x += colWidths[i];
          }

          // Rows
          ctx.font = '11px Arial';
          for (int r = 0; r < _requests.length; r++) {
            final req = _requests[r];
            final y = titleHeight + headerHeight + (r * rowHeight);
            if (r % 2 == 1) {
              ctx.fillStyle = '#fafafa';
              ctx.fillRect(
                  0, y.toDouble(), totalWidth.toDouble(), rowHeight.toDouble());
            }
            ctx.fillStyle = '#333333';
            x = 10;
            final cells = [
              '${r + 1}',
              req['employeeName'] ?? '',
              _getActionLabel(req['action']),
              _getStatusLabel(req['status']),
              _formatDate(req['newDate']),
              _formatTime(req['newTime']),
              _formatDate(req['oldDate']),
              _formatTime(req['oldTime']),
              req['reason'] ?? '',
              _formatDateTime(req['createdAt']),
              req['approvedByName'] ?? '',
              _formatDateTime(req['approvedDate']),
              req['approverNote'] ?? '',
            ];
            for (int i = 0; i < cells.length; i++) {
              final text = cells[i].length > 20
                  ? '${cells[i].substring(0, 20)}...'
                  : cells[i];
              ctx.fillText(text, x, y + 19);
              x += colWidths[i];
            }
          }
        },
      );

      if (canvas != null) {
        await file_saver.saveDataUrl(canvas,
            'duyet_cham_cong_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.png');
        appNotification.showSuccess(
            title: 'Thành công', message: 'Đã xuất file PNG');
      } else {
        // Mobile fallback: use async renderer
        final pngBytes = await web_canvas.renderToPngBytes(
          width: totalWidth,
          height: totalHeight,
          draw: (ctx) {
            ctx.fillStyle = '#FFFFFF';
            ctx.fillRect(0, 0, totalWidth.toDouble(), totalHeight.toDouble());
            ctx.fillStyle = '#1a1a1a';
            ctx.font = 'bold 16px Arial';
            ctx.fillText('Duyệt chấm công', 10, 28);
            ctx.fillStyle = '#f5f5f5';
            ctx.fillRect(0, titleHeight.toDouble(), totalWidth.toDouble(), headerHeight.toDouble());
            ctx.fillStyle = '#333333';
            ctx.font = 'bold 12px Arial';
            double x2 = 10;
            for (int i = 0; i < headers.length; i++) {
              ctx.fillText(headers[i], x2, titleHeight + 23);
              x2 += colWidths[i];
            }
            ctx.font = '11px Arial';
            for (int r = 0; r < _requests.length; r++) {
              final req = _requests[r];
              final y = titleHeight + headerHeight + (r * rowHeight);
              if (r % 2 == 1) {
                ctx.fillStyle = '#fafafa';
                ctx.fillRect(0, y.toDouble(), totalWidth.toDouble(), rowHeight.toDouble());
              }
              ctx.fillStyle = '#333333';
              x2 = 10;
              final cells = [
                '${r + 1}',
                req['employeeName'] ?? '',
                _getActionLabel(req['action']),
                _getStatusLabel(req['status']),
                _formatDate(req['newDate']),
                _formatTime(req['newTime']),
                _formatDate(req['oldDate']),
                _formatTime(req['oldTime']),
                req['reason'] ?? '',
                _formatDateTime(req['createdAt']),
                req['approvedByName'] ?? '',
                _formatDateTime(req['approvedDate']),
                req['approverNote'] ?? '',
              ];
              for (int i = 0; i < cells.length; i++) {
                final text = cells[i].length > 20 ? '${cells[i].substring(0, 20)}...' : cells[i];
                ctx.fillText(text, x2, y + 19);
                x2 += colWidths[i];
              }
            }
          },
        );
        if (pngBytes != null) {
          final fileName = 'duyet_cham_cong_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.png';
          await file_saver.saveFileBytes(pngBytes, fileName, 'image/png');
          appNotification.showSuccess(title: 'Thành công', message: 'Đã xuất file PNG');
        } else {
          appNotification.showError(title: 'Lỗi', message: 'Không thể xuất PNG');
        }
      }
    } catch (e) {
      appNotification.showError(
          title: 'Lỗi', message: 'Không thể xuất PNG: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }
}
