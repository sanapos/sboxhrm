import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/notification_overlay.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';

/// Màn hình quản lý phiếu phạt
class PenaltyTicketsScreen extends StatefulWidget {
  final String? highlightId;
  const PenaltyTicketsScreen({super.key, this.highlightId});

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
  String _datePreset = 'this_month'; // today, yesterday, this_week, last_week, this_month, last_month, custom, all

  // Multi-select for bulk approve
  final Set<String> _selectedIds = {};
  bool get _isSelectionMode => _selectedIds.isNotEmpty;

  bool _showMobileFilters = false;
  bool _showMobileSummary = false;

  @override
  void initState() {
    super.initState();
    _applyDatePreset('this_month', reload: false);
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
        range = DateTimeRange(start: DateTime(today.year, today.month, 1), end: today);
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
    } finally {
      if (mounted) setState(() => _isLoading = false);
      _maybeOpenHighlight();
    }
  }

  bool _highlightOpened = false;
  void _maybeOpenHighlight() {
    if (_highlightOpened) return;
    final id = widget.highlightId;
    if (id == null || id.isEmpty) return;
    Map<String, dynamic>? match;
    for (final t in _tickets) {
      if (t['id']?.toString() == id) { match = t; break; }
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
        _tickets = List<Map<String, dynamic>>.from(result['data']['items'] ?? []);
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
      final result = await _apiService.getEmployees();
      if (mounted) {
        setState(() => _employees = List<Map<String, dynamic>>.from(result));
      }
    } catch (_) {}
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'Late': return 'Đi trễ';
      case 'EarlyLeave': return 'Về sớm';
      case 'ForgotCheck': return 'Quên chấm công';
      case 'UnauthorizedLeave': return 'Nghỉ không phép';
      case 'Violation': return 'Vi phạm';
      case 'Repeat': return 'Tái phạm';
      default: return type;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Pending': return Colors.orange;
      case 'Approved': return Colors.green;
      case 'AutoApproved': return Colors.blue;
      case 'Cancelled': return Colors.grey;
      default: return Colors.black;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'Pending': return 'Chờ duyệt';
      case 'Approved': return 'Đã duyệt';
      case 'AutoApproved': return 'Tự động duyệt';
      case 'Cancelled': return 'Đã hủy';
      default: return status;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'Late': return Icons.schedule;
      case 'EarlyLeave': return Icons.exit_to_app;
      case 'ForgotCheck': return Icons.fingerprint;
      case 'UnauthorizedLeave': return Icons.event_busy;
      case 'Violation': return Icons.warning;
      default: return Icons.gavel;
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return '';
    try {
      final dt = DateTime.parse(date.toString());
      return DateFormat('dd/MM/yyyy').format(dt);
    } catch (_) {
      return date.toString();
    }
  }

  String _formatDateTime(dynamic date) {
    if (date == null) return '\u2014';
    try {
      final dt = DateTime.parse(date.toString());
      return DateFormat('dd/MM/yyyy HH:mm').format(dt);
    } catch (_) {
      return date.toString();
    }
  }

  // ─── Actions ───
  Future<void> _approveTicket(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Duyệt phiếu phạt', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Duyệt phiếu phạt sẽ tạo phiếu thu tương ứng. Bạn có chắc?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Không', style: TextStyle(color: Color(0xFF71717A)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
            child: const Text('Duyệt', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final result = await _apiService.approvePenaltyTicket(id);
      if (mounted) {
        if (result['isSuccess'] == true) {
          appNotification.showSuccess(title: 'Thành công', message: 'Đã duyệt phiếu phạt và tạo phiếu thu');
          await _loadData(showLoading: false);
        } else {
          appNotification.showError(title: 'Lỗi', message: result['message'] ?? 'Lỗi');
        }
      }
    }
  }

  Future<void> _unapproveTicket(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hoàn duyệt phiếu phạt', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Hoàn duyệt sẽ xóa phiếu thu liên quan và đưa phiếu phạt về trạng thái chờ duyệt. Bạn có chắc?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Không', style: TextStyle(color: Color(0xFF71717A)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Hoàn duyệt', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final result = await _apiService.unapprovePenaltyTicket(id);
      if (mounted) {
        if (result['isSuccess'] == true) {
          appNotification.showSuccess(title: 'Thành công', message: 'Đã hoàn duyệt phiếu phạt');
          await _loadData(showLoading: false);
        } else {
          appNotification.showError(title: 'Lỗi', message: result['message'] ?? 'Lỗi');
        }
      }
    }
  }

  Future<void> _cancelTicket(String id) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hủy phiếu phạt', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Bạn có chắc muốn hủy phiếu phạt này?'),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: 'Lý do hủy',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Không', style: TextStyle(color: Color(0xFF71717A)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hủy phạt', style: TextStyle(color: Colors.white)),
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
          appNotification.showSuccess(title: 'Thành công', message: 'Đã hủy phiếu phạt');
          await _loadData(showLoading: false);
        } else {
          appNotification.showError(title: 'Lỗi', message: result['message'] ?? 'Lỗi');
        }
      }
    } else {
      reasonController.dispose();
    }
  }

  Future<void> _deleteTicket(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xóa phiếu phạt', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Bạn có chắc muốn xóa phiếu phạt này? Chỉ xóa được phiếu đang chờ duyệt.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Không', style: TextStyle(color: Color(0xFF71717A)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final result = await _apiService.deletePenaltyTicket(id);
      if (mounted) {
        if (result['isSuccess'] == true) {
          appNotification.showSuccess(title: 'Thành công', message: 'Đã xóa phiếu phạt');
          await _loadData(showLoading: false);
        } else {
          appNotification.showError(title: 'Lỗi', message: result['message'] ?? 'Lỗi');
        }
      }
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _dateRange ?? DateTimeRange(
        start: DateTime.now().subtract(const Duration(days: 30)),
        end: DateTime.now(),
      ),
    );
    if (picked != null) {
      setState(() { _dateRange = picked; _datePreset = 'custom'; _currentPage = 1; });
      await _loadTickets();
    }
  }

  // ─── Bulk approve ───
  Future<void> _bulkApprove() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Duyệt nhanh', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Duyệt ${ids.length} phiếu phạt đã chọn? Hệ thống sẽ tạo phiếu thu tương ứng cho từng phiếu.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Không', style: TextStyle(color: Color(0xFF71717A)))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
            child: Text('Duyệt ${ids.length}', style: const TextStyle(color: Colors.white)),
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
        if (r['isSuccess'] == true) { ok++; } else { fail++; }
      } catch (_) { fail++; }
    }
    if (mounted) {
      _selectedIds.clear();
      if (fail == 0) {
        appNotification.showSuccess(title: 'Thành công', message: 'Đã duyệt $ok phiếu');
      } else {
        appNotification.showWarning(title: 'Hoàn tất', message: 'Duyệt thành công $ok, lỗi $fail');
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
      appNotification.showWarning(title: 'Không thể sửa', message: 'Chỉ sửa được phiếu đang chờ duyệt');
      return;
    }

    final amountCtrl = TextEditingController(text: isEditing ? (ticket['amount'] ?? 0).toString() : '');
    final descCtrl = TextEditingController(text: ticket?['description'] ?? '');
    final minutesCtrl = TextEditingController(text: isEditing ? (ticket['minutesLateOrEarly'] ?? '').toString() : '');
    String selectedType = isEditing ? (ticket['type'] ?? 'Violation') : 'Violation';
    String? selectedEmployeeId = isEditing ? ticket['employeeId']?.toString() : null;
    DateTime selectedDate = isEditing ? (DateTime.tryParse(ticket['violationDate'] ?? '') ?? DateTime.now()) : DateTime.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final isMobile = Responsive.isMobile(context);

          Future<void> onSubmit() async {
            if (!isEditing && selectedEmployeeId == null) {
              appNotification.showWarning(title: 'Thiếu thông tin', message: 'Vui lòng chọn nhân viên');
              return;
            }
            final amount = double.tryParse(amountCtrl.text);
            if (amount == null || amount <= 0) {
              appNotification.showWarning(title: 'Thiếu thông tin', message: 'Vui lòng nhập số tiền hợp lệ');
              return;
            }

            Navigator.pop(context);

            Map<String, dynamic> result;
            if (isEditing) {
              result = await _apiService.updatePenaltyTicket(ticket['id'].toString(), {
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
            }

            if (mounted) {
              if (result['isSuccess'] == true) {
                appNotification.showSuccess(title: 'Thành công', message: isEditing ? 'Đã cập nhật phiếu phạt' : 'Đã tạo phiếu phạt');
                await _loadData(showLoading: false);
              } else {
                appNotification.showError(title: 'Lỗi', message: result['message'] ?? 'Lỗi');
              }
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
                  const Text('Nhân viên *', style: TextStyle(color: Color(0xFF71717A), fontSize: 13)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedEmployeeId,
                    dropdownColor: Colors.white,
                    isExpanded: true,
                    decoration: _inputDecor('Chọn nhân viên'),
                    items: _employees.map<DropdownMenuItem<String>>((emp) {
                      final name = '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}'.trim();
                      final code = emp['employeeCode'] ?? '';
                      return DropdownMenuItem(value: emp['id'].toString(), child: Text('$code - $name', overflow: TextOverflow.ellipsis));
                    }).toList(),
                    onChanged: (v) => setDialogState(() => selectedEmployeeId = v),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text('Loại phạt *', style: TextStyle(color: Color(0xFF71717A), fontSize: 13)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  dropdownColor: Colors.white,
                  isExpanded: true,
                  decoration: _inputDecor('Chọn loại phạt'),
                  items: types.map<DropdownMenuItem<String>>((t) {
                    return DropdownMenuItem(value: t['value'] as String, child: Text(t['label'] as String));
                  }).toList(),
                  onChanged: (v) => setDialogState(() => selectedType = v ?? 'Violation'),
                ),
                const SizedBox(height: 16),
                const Text('Số tiền phạt (VNĐ) *', style: TextStyle(color: Color(0xFF71717A), fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Color(0xFF18181B), fontSize: 14),
                  decoration: _inputDecor('50000'),
                ),
                const SizedBox(height: 16),
                if (!isEditing) ...[
                  const Text('Ngày vi phạm *', style: TextStyle(color: Color(0xFF71717A), fontSize: 13)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2024),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) setDialogState(() => selectedDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE4E4E7)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 16, color: Color(0xFF71717A)),
                          const SizedBox(width: 8),
                          Text(DateFormat('dd/MM/yyyy').format(selectedDate), style: const TextStyle(fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text('Số phút trễ/sớm', style: TextStyle(color: Color(0xFF71717A), fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: minutesCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Color(0xFF18181B), fontSize: 14),
                  decoration: _inputDecor('15'),
                ),
                const SizedBox(height: 16),
                const Text('Mô tả', style: TextStyle(color: Color(0xFF71717A), fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  style: const TextStyle(color: Color(0xFF18181B), fontSize: 14),
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
                    isEditing ? 'Sửa phiếu phạt' : 'Tạo phiếu phạt',
                    style: const TextStyle(color: Color(0xFF18181B), fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  actions: [
                    TextButton.icon(
                      onPressed: onSubmit,
                      icon: const Icon(Icons.save, size: 18),
                      label: Text(isEditing ? 'Cập nhật' : 'Tạo'),
                      style: TextButton.styleFrom(foregroundColor: const Color(0xFF0F2340)),
                    ),
                  ],
                ),
                body: formBody,
              ),
            );
          }

          return Dialog(
            backgroundColor: Colors.white,
            insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: math.min(480, MediaQuery.of(context).size.width - 32).toDouble(),
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(isEditing ? 'Sửa phiếu phạt' : 'Tạo phiếu phạt', style: const TextStyle(color: Color(0xFF18181B), fontSize: 18, fontWeight: FontWeight.bold))),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Color(0xFF71717A))),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Flexible(child: formBody),
                  const SizedBox(height: 20),
                  const Divider(color: Color(0xFFE4E4E7)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A)))),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: onSubmit,
                        icon: Icon(isEditing ? Icons.save : Icons.add, size: 18),
                        label: Text(isEditing ? 'Cập nhật' : 'Tạo phiếu'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0F2340),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0F2340))),
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
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
              Container(width: 40, height: 4, decoration: BoxDecoration(color: const Color(0xFFE4E4E7), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              CircleAvatar(
                radius: 28,
                backgroundColor: _getStatusColor(status).withValues(alpha: 0.15),
                child: Icon(_getTypeIcon(type), color: _getStatusColor(status), size: 28),
              ),
              const SizedBox(height: 12),
              Text(ticket['employeeName'] ?? 'N/A', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF18181B))),
              if (ticket['employeeCode'] != null)
                Text(ticket['employeeCode'], style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 13)),
              const SizedBox(height: 8),
              Text(ticket['ticketCode'] ?? '', style: const TextStyle(color: Color(0xFF71717A), fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: _getStatusColor(status).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: Text(_getStatusLabel(status), style: TextStyle(color: _getStatusColor(status), fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 10),
                  Text('${_currencyFormat.format(amount)}đ',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red[700])),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: Color(0xFFE4E4E7)),
              const SizedBox(height: 8),
              _detailRow(Icons.category_outlined, 'Loại phạt', _getTypeLabel(type)),
              _detailRow(Icons.calendar_today, 'Ngày vi phạm', _formatDate(ticket['violationDate'])),
              if (ticket['minutesLateOrEarly'] != null)
                _detailRow(Icons.timer_outlined, 'Số phút', '${ticket['minutesLateOrEarly']} phút'),
              if (ticket['shiftStartTime'] != null)
                _detailRow(Icons.access_time, 'Ca làm', '${ticket['shiftStartTime']} - ${ticket['shiftEndTime'] ?? ''}'),
              if (ticket['actualPunchTime'] != null)
                _detailRow(Icons.fingerprint, 'Giờ chấm thực tế', _formatDateTime(ticket['actualPunchTime'])),
              _detailRow(Icons.layers, 'Bậc phạt', 'Bậc ${ticket['penaltyTier'] ?? 1}'),
              if (ticket['description'] != null && (ticket['description'] as String).isNotEmpty)
                _detailRow(Icons.notes, 'Mô tả', ticket['description']),
              if (ticket['processedByName'] != null)
                _detailRow(Icons.person_outline, 'Người xử lý', ticket['processedByName']),
              if (ticket['processedDate'] != null)
                _detailRow(Icons.event_available, 'Ngày xử lý', _formatDateTime(ticket['processedDate'])),
              if (isCancelled && ticket['cancellationReason'] != null)
                _detailRow(Icons.cancel_outlined, 'Lý do hủy', ticket['cancellationReason']),
              if (isApproved && ticket['cashTransactionCode'] != null)
                _detailRow(Icons.receipt_long, 'Phiếu thu', ticket['cashTransactionCode']),
              _detailRow(Icons.access_time_filled, 'Ngày tạo', _formatDateTime(ticket['createdAt'])),
              const SizedBox(height: 16),
              const Divider(color: Color(0xFFE4E4E7)),
              const SizedBox(height: 16),
              if (isPending) ...[
                Row(
                  children: [
                    if (Provider.of<PermissionProvider>(context, listen: false).canEdit('PenaltyTickets'))
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () { Navigator.pop(context); _showTicketDialog(ticket: ticket); },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Sửa'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF71717A),
                          side: const BorderSide(color: Color(0xFFE4E4E7)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (Provider.of<PermissionProvider>(context, listen: false).canApprove('PenaltyTickets'))
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () { Navigator.pop(context); _cancelTicket(ticket['id'].toString()); },
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Hủy phạt'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                          side: const BorderSide(color: Colors.orange),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (Provider.of<PermissionProvider>(context, listen: false).canApprove('PenaltyTickets'))
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () { Navigator.pop(context); _approveTicket(ticket['id'].toString()); },
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Duyệt'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
                if (Provider.of<PermissionProvider>(context, listen: false).canDelete('PenaltyTickets')) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () { Navigator.pop(context); _deleteTicket(ticket['id'].toString()); },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Xóa phiếu'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ],
              if (isApproved && Provider.of<PermissionProvider>(context, listen: false).canApprove('PenaltyTickets'))
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () { Navigator.pop(context); _unapproveTicket(ticket['id'].toString()); },
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Hoàn duyệt'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange,
                      side: const BorderSide(color: Colors.orange),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Color(0xFF71717A), fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(color: Color(0xFF18181B), fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  // ─── Build ───
  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Phiếu phạt', style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold)),
        actions: [
          if (isMobile)
            IconButton(
              icon: Stack(
                children: [
                  Icon(_showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined, color: const Color(0xFF18181B)),
                  if (_filterStatus != null || _filterType != null)
                    Positioned(right: 0, top: 0, child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle))),
                ],
              ),
              onPressed: () => setState(() => _showMobileFilters = !_showMobileFilters),
              tooltip: 'Bộ lọc',
            ),
          if (!isMobile && Provider.of<PermissionProvider>(context, listen: false).canCreate('PenaltyTickets'))
            ElevatedButton.icon(
              onPressed: () => _showTicketDialog(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Tạo phiếu phạt'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F2340),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          IconButton(icon: const Icon(Icons.date_range, color: Color(0xFF18181B)), onPressed: _pickDateRange, tooltip: 'Chọn khoảng thời gian'),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: isMobile && Provider.of<PermissionProvider>(context, listen: false).canCreate('PenaltyTickets')
          ? FloatingActionButton(
              onPressed: () => _showTicketDialog(),
              backgroundColor: const Color(0xFF0F2340),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (isMobile) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: InkWell(
                      onTap: () => setState(() => _showMobileSummary = !_showMobileSummary),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
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
                  if (_showMobileSummary) _buildStatsCards(),
                ] else ...[
                  _buildStatsCards(),
                ],
                if (!isMobile || _showMobileFilters) _buildFilterBar(),
                if (_isSelectionMode) _buildBulkActionBar(),
                Expanded(child: _buildTicketList()),
                if (_totalCount > _pageSize) _buildPagination(),
              ],
            ),
    );
  }

  Widget _buildStatsCards() {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(child: _buildStatCard('Chờ duyệt', _stats['totalPending'] ?? 0, Colors.orange,
            amount: (_stats['pendingAmount'] as num?)?.toDouble())),
          const SizedBox(width: 8),
          Expanded(child: _buildStatCard('Đã duyệt', ((_stats['totalApproved'] ?? 0) as int) + ((_stats['totalAutoApproved'] ?? 0) as int), Colors.green,
            amount: (_stats['approvedAmount'] as num?)?.toDouble())),
          const SizedBox(width: 8),
          Expanded(child: _buildStatCard('Đã hủy', _stats['totalCancelled'] ?? 0, Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, dynamic count, Color color, {double? amount}) {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Color(0xFFE4E4E7))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$count', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF71717A)), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (amount != null && amount > 0)
              Text('${_currencyFormat.format(amount)}đ', style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
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
                  label: Text(_datePreset == 'custom' && _dateRange != null
                      ? '${DateFormat('dd/MM').format(_dateRange!.start)} - ${DateFormat('dd/MM').format(_dateRange!.end)}'
                      : 'Lựa chọn khác'),
                  backgroundColor: _datePreset == 'custom' ? const Color(0xFF0F2340) : Colors.white,
                  labelStyle: TextStyle(fontSize: 12, color: _datePreset == 'custom' ? Colors.white : const Color(0xFF18181B)),
                  side: const BorderSide(color: Color(0xFFE4E4E7)),
                  onPressed: _pickDateRange,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _filterStatus,
                  dropdownColor: Colors.white,
                  decoration: const InputDecoration(
                    labelText: 'Trạng thái',
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Tất cả')),
                    DropdownMenuItem(value: '0', child: Text('Chờ duyệt')),
                    DropdownMenuItem(value: '1', child: Text('Đã duyệt')),
                    DropdownMenuItem(value: '3', child: Text('Tự động duyệt')),
                    DropdownMenuItem(value: '2', child: Text('Đã hủy')),
                  ],
                  onChanged: (v) {
                    setState(() { _filterStatus = v; _currentPage = 1; });
                    _loadTickets();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _filterType,
                  dropdownColor: Colors.white,
                  decoration: const InputDecoration(
                    labelText: 'Loại',
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Tất cả')),
                    DropdownMenuItem(value: '1', child: Text('Đi trễ')),
                    DropdownMenuItem(value: '2', child: Text('Về sớm')),
                    DropdownMenuItem(value: '3', child: Text('Quên chấm công')),
                    DropdownMenuItem(value: '4', child: Text('Nghỉ không phép')),
                    DropdownMenuItem(value: '5', child: Text('Vi phạm')),
                    DropdownMenuItem(value: '6', child: Text('Tái phạm')),
                  ],
                  onChanged: (v) {
                    setState(() { _filterType = v; _currentPage = 1; });
                    _loadTickets();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _datePresetChip(String preset, String label) {
    final selected = _datePreset == preset;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => _applyDatePreset(preset),
      backgroundColor: Colors.white,
      selectedColor: const Color(0xFF0F2340),
      labelStyle: TextStyle(color: selected ? Colors.white : const Color(0xFF18181B)),
      side: const BorderSide(color: Color(0xFFE4E4E7)),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildBulkActionBar() {
    final canApprove = Provider.of<PermissionProvider>(context, listen: false).canApprove('PenaltyTickets');
    final pendingOnPage = _tickets.where((t) => t['status'] == 'Pending').length;
    return Container(
      color: const Color(0xFFFFF7ED),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => setState(() => _selectedIds.clear()),
            tooltip: 'Bỏ chọn',
            visualDensity: VisualDensity.compact,
          ),
          Text('Đã chọn ${_selectedIds.length} phiếu', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const Spacer(),
          if (pendingOnPage > _selectedIds.where((id) => _tickets.any((t) => t['id'].toString() == id && t['status'] == 'Pending')).length)
            TextButton(
              onPressed: _selectAllPendingOnPage,
              child: Text('Chọn tất cả chờ duyệt ($pendingOnPage)', style: const TextStyle(fontSize: 12)),
            ),
          if (canApprove) ...[
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _bulkApprove,
              icon: const Icon(Icons.check, size: 16),
              label: Text('Duyệt ${_selectedIds.length}'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTicketList() {
    if (_tickets.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text('Không có phiếu phạt', style: TextStyle(fontSize: 16, color: Colors.grey)),
          ],
        ),
      );
    }

    return Responsive.isMobile(context) ? _buildMobileList() : _buildDesktopList();
  }

  Widget _buildMobileList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: _tickets.length,
      itemBuilder: (_, i) {
        final ticket = _tickets[i];
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
                  border: Border.all(color: isSelected ? Colors.orange : const Color(0xFFE4E4E7), width: isSelected ? 1.5 : 1),
                ),
                child: Row(
                  children: [
                    if (_isSelectionMode && isPending)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                          color: isSelected ? Colors.orange : const Color(0xFFA1A1AA),
                          size: 22,
                        ),
                      ),
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: _getStatusColor(status).withValues(alpha: 0.15),
                      child: Icon(_getTypeIcon(type), color: _getStatusColor(status), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(ticket['employeeName'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF18181B))),
                          const SizedBox(height: 2),
                          Text(
                            [_getTypeLabel(type), _formatDate(ticket['violationDate'])].where((s) => s.isNotEmpty).join(' \u00b7 '),
                            style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${_currencyFormat.format(amount)}\u0111',
                          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[700], fontSize: 13)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: _getStatusColor(status).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                          child: Text(_getStatusLabel(status), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _getStatusColor(status))),
                        ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, color: Color(0xFFA1A1AA), size: 20),
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
      itemCount: _tickets.length,
      itemBuilder: (context, index) {
        final ticket = _tickets[index];
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
            side: BorderSide(color: isSelected ? Colors.orange : const Color(0xFFE4E4E7), width: isSelected ? 1.5 : 1),
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
                              isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                              color: isSelected ? Colors.orange : const Color(0xFFA1A1AA),
                              size: 22,
                            ),
                          ),
                        ),
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: _getStatusColor(status).withValues(alpha: 0.15),
                        child: Icon(_getTypeIcon(type), color: _getStatusColor(status), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(ticket['employeeName'] ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(
                              [_getTypeLabel(type), _formatDate(ticket['violationDate']), ticket['ticketCode'] ?? ''].where((s) => s.isNotEmpty).join(' \u00b7 '),
                              style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Text('${_currencyFormat.format(amount)}\u0111',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red[700], fontSize: 15)),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: _getStatusColor(status).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                        child: Text(_getStatusLabel(status), style: TextStyle(fontSize: 11, color: _getStatusColor(status), fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  if (ticket['description'] != null && (ticket['description'] as String).isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(ticket['description'], style: const TextStyle(fontSize: 12, color: Color(0xFF71717A)), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                  if (isPending || isApproved) ...[
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (isPending) ...[
                          if (Provider.of<PermissionProvider>(context, listen: false).canEdit('PenaltyTickets'))
                          _actionBtn(Icons.edit_outlined, 'Sửa', const Color(0xFF71717A), () => _showTicketDialog(ticket: ticket)),
                          if (Provider.of<PermissionProvider>(context, listen: false).canEdit('PenaltyTickets'))
                          const SizedBox(width: 6),
                          if (Provider.of<PermissionProvider>(context, listen: false).canDelete('PenaltyTickets'))
                          _actionBtn(Icons.delete_outline, 'Xóa', Colors.red, () => _deleteTicket(ticket['id'].toString())),
                          if (Provider.of<PermissionProvider>(context, listen: false).canDelete('PenaltyTickets'))
                          const SizedBox(width: 6),
                          if (Provider.of<PermissionProvider>(context, listen: false).canApprove('PenaltyTickets'))
                          _actionBtn(Icons.close, 'Hủy phạt', Colors.orange, () => _cancelTicket(ticket['id'].toString())),
                          if (Provider.of<PermissionProvider>(context, listen: false).canApprove('PenaltyTickets'))
                          const SizedBox(width: 6),
                          if (Provider.of<PermissionProvider>(context, listen: false).canApprove('PenaltyTickets'))
                          ElevatedButton.icon(
                            onPressed: () => _approveTicket(ticket['id'].toString()),
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text('Duyệt', style: TextStyle(fontSize: 12)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF16A34A),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              minimumSize: Size.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                        if (isApproved) ...[
                          if (ticket['cashTransactionCode'] != null) ...[
                            Text('Phiếu thu: ${ticket['cashTransactionCode']}', style: TextStyle(fontSize: 11, color: Colors.green[600])),
                            const SizedBox(width: 8),
                          ],
                          if (Provider.of<PermissionProvider>(context, listen: false).canApprove('PenaltyTickets'))
                          _actionBtn(Icons.undo, 'Hoàn duyệt', Colors.orange, () => _unapproveTicket(ticket['id'].toString())),
                        ],
                      ],
                    ),
                  ],
                  if (status == 'Cancelled' && ticket['cancellationReason'] != null) ...[
                    const SizedBox(height: 6),
                    Text('Lý do hủy: ${ticket['cancellationReason']}',
                      style: TextStyle(fontSize: 11, color: Colors.red[300], fontStyle: FontStyle.italic)),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _actionBtn(IconData icon, String label, Color color, VoidCallback onPressed) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
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
          Text('Hiển thị $start-$end / $_totalCount', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
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
                onPressed: _currentPage > 1 ? () { setState(() => _currentPage--); _loadTickets(); } : null,
                visualDensity: VisualDensity.compact,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFF0F2340), borderRadius: BorderRadius.circular(8)),
                child: Text('$_currentPage / $totalPages', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20),
                onPressed: _currentPage < totalPages ? () { setState(() => _currentPage++); _loadTickets(); } : null,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }
}