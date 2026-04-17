import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models/hrm.dart';
import '../models/employee.dart';
import '../utils/responsive_helper.dart';
import '../widgets/loading_widget.dart';
import '../widgets/empty_state.dart';
import '../widgets/notification_overlay.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';

// =====================================================
// SCHEDULE APPROVAL SCREEN - BẢN NÂNG CẤP
// =====================================================
// Tab 1: Tổng quan theo ca (Shift Overview with Quotas)
//   - Mỗi ca hiển thị bảng 7 ngày với chỉ số định biên
//   - Thanh tiến trình (đã xếp / max) cho mỗi ngày
//   - Cảnh báo vượt định biên
//
// Tab 2: Phân bổ nhân viên (Employee Distribution)
//   - Thống kê trung bình ca/NV, min, max
//   - Cảnh báo mất cân bằng phân ca
// =====================================================

class _EmployeeSummary {
  final String employeeId;
  final int totalRegistered;
  final int approved;
  final int pending;
  final int rejected;
  final int scheduledShifts;

  _EmployeeSummary({
    required this.employeeId,
    required this.totalRegistered,
    required this.approved,
    required this.pending,
    required this.rejected,
    required this.scheduledShifts,
  });
}

class ScheduleApprovalScreen extends StatefulWidget {
  const ScheduleApprovalScreen({super.key});

  @override
  State<ScheduleApprovalScreen> createState() => _ScheduleApprovalScreenState();
}

class _ScheduleApprovalScreenState extends State<ScheduleApprovalScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabController;

  List<WorkSchedule> _schedules = [];
  List<ScheduleRegistration> _registrations = [];
  List<Shift> _shifts = [];
  List<Employee> _employees = [];
  List<Map<String, dynamic>> _staffingQuotas = [];
  bool _isLoading = true;

  DateTime _selectedWeekStart = _getWeekStart(DateTime.now());
  String? _selectedStatusFilter;

  String _effectiveUserId(Employee e) => e.id;

  static DateTime _getWeekStart(DateTime date) {
    final d = date.subtract(Duration(days: date.weekday - 1));
    return DateTime(d.year, d.month, d.day);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ==================== DATA LOADING ====================
  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _loadShifts(),
        _loadEmployees(),
        _loadSchedules(),
        _loadRegistrations(),
        _loadStaffingQuotas(),
      ]);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadShifts() async {
    final shifts = await _apiService.getShifts();
    if (!mounted) return;
    setState(() {
      _shifts = shifts.map((s) => Shift.fromJson(s)).toList();
      _shifts.sort((a, b) {
        final aTime = a.startTime.replaceAll(RegExp(r'[^0-9:]'), '');
        final bTime = b.startTime.replaceAll(RegExp(r'[^0-9:]'), '');
        return aTime.compareTo(bTime);
      });
    });
  }

  Future<void> _loadEmployees() async {
    final employees = await _apiService.getEmployees();
    if (!mounted) return;
    setState(() {
      _employees = employees.map((e) => Employee.fromJson(e)).toList();
    });
  }

  Future<void> _loadSchedules() async {
    final fromDate = _selectedWeekStart;
    final toDate = _selectedWeekStart.add(const Duration(days: 6));
    final result = await _apiService.getWorkSchedules(fromDate: fromDate, toDate: toDate);
    if (!mounted) return;
    if (result['isSuccess'] == true && result['data'] != null) {
      final data = result['data'];
      final items = data is List ? data : (data['items'] ?? []);
      setState(() {
        _schedules = (items as List).map((s) => WorkSchedule.fromJson(s)).toList();
      });
    }
  }

  Future<void> _loadRegistrations() async {
    int? statusInt;
    if (_selectedStatusFilter != null) {
      switch (_selectedStatusFilter) {
        case 'Pending': statusInt = 0; break;
        case 'Approved': statusInt = 1; break;
        case 'Rejected': statusInt = 2; break;
      }
    }
    final fromDate = _selectedWeekStart;
    final toDate = _selectedWeekStart.add(const Duration(days: 6));
    final result = await _apiService.getScheduleRegistrations(
      status: statusInt, fromDate: fromDate, toDate: toDate,
    );
    if (!mounted) return;
    if (result['isSuccess'] == true && result['data'] != null) {
      final data = result['data'];
      final items = data is List ? data : (data['items'] ?? []);
      setState(() {
        _registrations = (items as List).map((r) => ScheduleRegistration.fromJson(r)).toList();
      });
    }
  }

  Future<void> _loadStaffingQuotas() async {
    try {
      final result = await _apiService.getStaffingQuotas();
      if (!mounted) return;
      if (result['isSuccess'] == true && result['data'] != null) {
        setState(() {
          _staffingQuotas = List<Map<String, dynamic>>.from(result['data']);
        });
      }
    } catch (e) {
      debugPrint('Load staffing quotas error: $e');
    }
  }

  // ==================== COMPUTED HELPERS ====================
  Map<String, dynamic>? _getQuotaForShift(String shiftId) {
    return _staffingQuotas.where((q) =>
      q['shiftTemplateId'] == shiftId &&
      (q['department'] == null || q['department'] == '')).firstOrNull;
  }

  int _scheduledCount(String? shiftId, DateTime date) {
    if (shiftId == null) return 0;
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    return _schedules.where((s) =>
      s.shiftId == shiftId &&
      DateFormat('yyyy-MM-dd').format(s.date) == dateStr &&
      !s.isDayOff).length;
  }

  int _pendingCountForShiftDay(String? shiftId, DateTime date) {
    if (shiftId == null) return 0;
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    return _registrations.where((r) =>
      r.shiftId == shiftId &&
      DateFormat('yyyy-MM-dd').format(r.date) == dateStr &&
      r.status == ScheduleRegistrationStatus.pending &&
      !r.isDayOff).length;
  }

  List<ScheduleRegistration> _regsForShiftDay(String? shiftId, DateTime date) {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    return _registrations.where((r) =>
      r.shiftId == shiftId &&
      DateFormat('yyyy-MM-dd').format(r.date) == dateStr).toList();
  }

  Color _getQuotaColor(int scheduled, Map<String, dynamic>? quota) {
    if (quota == null) return const Color(0xFF71717A);
    final maxEmp = (quota['maxEmployees'] ?? 0) as int;
    final minEmp = (quota['minEmployees'] ?? 0) as int;
    final warnThreshold = (quota['warningThreshold'] ?? 2) as int;
    if (maxEmp == 0) return const Color(0xFF71717A);
    if (scheduled >= maxEmp) return const Color(0xFFEF4444);
    if (maxEmp - scheduled <= warnThreshold) return const Color(0xFFF59E0B);
    if (scheduled < minEmp) return const Color(0xFF3B82F6);
    return const Color(0xFF22C55E);
  }

  Map<String, _EmployeeSummary> _computeEmployeeSummaries() {
    final Map<String, _EmployeeSummary> result = {};
    final Map<String, Map<String, int>> regCounts = {};

    for (var reg in _registrations) {
      final eid = reg.employeeUserId;
      regCounts.putIfAbsent(eid, () => {'total': 0, 'approved': 0, 'pending': 0, 'rejected': 0});
      regCounts[eid]!['total'] = (regCounts[eid]!['total'] ?? 0) + 1;
      switch (reg.status) {
        case ScheduleRegistrationStatus.approved: regCounts[eid]!['approved'] = (regCounts[eid]!['approved'] ?? 0) + 1; break;
        case ScheduleRegistrationStatus.pending: regCounts[eid]!['pending'] = (regCounts[eid]!['pending'] ?? 0) + 1; break;
        case ScheduleRegistrationStatus.rejected: regCounts[eid]!['rejected'] = (regCounts[eid]!['rejected'] ?? 0) + 1; break;
      }
    }

    final Map<String, int> scheduleCounts = {};
    for (var s in _schedules) {
      if (!s.isDayOff) {
        scheduleCounts[s.employeeUserId] = (scheduleCounts[s.employeeUserId] ?? 0) + 1;
      }
    }

    final allIds = <String>{...regCounts.keys, ...scheduleCounts.keys};
    for (var eid in allIds) {
      final rc = regCounts[eid] ?? {};
      result[eid] = _EmployeeSummary(
        employeeId: eid,
        totalRegistered: rc['total'] ?? 0,
        approved: rc['approved'] ?? 0,
        pending: rc['pending'] ?? 0,
        rejected: rc['rejected'] ?? 0,
        scheduledShifts: scheduleCounts[eid] ?? 0,
      );
    }
    return result;
  }

  int _getPendingCount() => _registrations.where((r) => r.status == ScheduleRegistrationStatus.pending).length;

  bool get _canApprove => Provider.of<PermissionProvider>(context, listen: false).canApprove('ScheduleApproval');
  bool get _canDelete => Provider.of<PermissionProvider>(context, listen: false).canDelete('ScheduleApproval');

  Employee _findEmployee(String empId) {
    try {
      return _employees.firstWhere((e) => e.id == empId || _effectiveUserId(e) == empId);
    } catch (_) { return Employee.empty(); }
  }

  // ==================== NAVIGATION ====================
  void _previousWeek() {
    setState(() { _selectedWeekStart = _selectedWeekStart.subtract(const Duration(days: 7)); });
    _loadSchedules(); _loadRegistrations();
  }

  void _nextWeek() {
    setState(() { _selectedWeekStart = _selectedWeekStart.add(const Duration(days: 7)); });
    _loadSchedules(); _loadRegistrations();
  }

  void _goToThisWeek() {
    setState(() { _selectedWeekStart = _getWeekStart(DateTime.now()); });
    _loadSchedules(); _loadRegistrations();
  }

  int _getWeekNumber(DateTime date) {
    final firstDayOfYear = DateTime(date.year, 1, 1);
    return ((date.difference(firstDayOfYear).inDays + firstDayOfYear.weekday) / 7).ceil();
  }

  String _formatTime(String timeString) {
    final parts = timeString.split(':');
    return parts.length >= 2 ? '${parts[0]}:${parts[1]}' : timeString;
  }

  // ==================== BUILD ====================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        toolbarHeight: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF1E3A5F),
          labelColor: const Color(0xFF1E3A5F),
          unselectedLabelColor: const Color(0xFF71717A),
          tabs: [
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.dashboard, size: 18),
                const SizedBox(width: 6),
                const Text('Tổng quan ca'),
                if (_getPendingCount() > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(10)),
                    child: Text('${_getPendingCount()}', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
              ]),
            ),
            const Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.people, size: 18),
                SizedBox(width: 6),
                Text('Phân bổ nhân viên'),
              ]),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const LoadingWidget()
          : TabBarView(
              controller: _tabController,
              children: [
                _buildShiftOverviewTab(),
                _buildEmployeeDistributionTab(),
              ],
            ),
    );
  }

  // ==================== WEEK SELECTOR ====================
  Widget _buildWeekSelector() {
    final weekEnd = _selectedWeekStart.add(const Duration(days: 6));
    final weekNumber = _getWeekNumber(_selectedWeekStart);
    final dateFormat = DateFormat('dd/MM');
    final isMobile = Responsive.isMobile(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: isMobile
          ? Column(children: [
              Row(children: [
                Expanded(child: OutlinedButton.icon(
                  onPressed: _previousWeek,
                  icon: const Icon(Icons.chevron_left, size: 18),
                  label: const Text('Trước', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF71717A), side: const BorderSide(color: Color(0xFFE4E4E7)), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                )),
                const SizedBox(width: 6),
                Expanded(child: ElevatedButton.icon(
                  onPressed: _goToThisWeek,
                  icon: const Icon(Icons.today, size: 16),
                  label: const Text('Tuần này', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                )),
                const SizedBox(width: 6),
                Expanded(child: OutlinedButton.icon(
                  onPressed: _nextWeek,
                  icon: const Text('Sau', style: TextStyle(fontSize: 12)),
                  label: const Icon(Icons.chevron_right, size: 18),
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF71717A), side: const BorderSide(color: Color(0xFFE4E4E7)), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                )),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    'Tuần $weekNumber (${dateFormat.format(_selectedWeekStart)} - ${dateFormat.format(weekEnd)})',
                    style: const TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.w600, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                )),
                const SizedBox(width: 8),
                Expanded(child: _buildStatusFilterDropdown()),
              ]),
            ])
          : Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton.icon(
                onPressed: _previousWeek,
                icon: const Icon(Icons.chevron_left, size: 18),
                label: const Text('Tuần trước'),
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF71717A), side: const BorderSide(color: Color(0xFFE4E4E7)), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              ),
              ElevatedButton.icon(
                onPressed: _goToThisWeek,
                icon: const Icon(Icons.today, size: 18),
                label: const Text('Tuần này'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
              ),
              OutlinedButton.icon(
                onPressed: _nextWeek,
                icon: const Text('Tuần sau'),
                label: const Icon(Icons.chevron_right, size: 18),
                style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF71717A), side: const BorderSide(color: Color(0xFFE4E4E7)), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(8)),
                child: Text(
                  'Tuần $weekNumber (${dateFormat.format(_selectedWeekStart)} - ${dateFormat.format(weekEnd)})',
                  style: const TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              SizedBox(width: 180, child: _buildStatusFilterDropdown()),
            ]),
    );
  }

  Widget _buildStatusFilterDropdown() {
    return DropdownButtonFormField<String>(
      key: ValueKey('status_filter_${_selectedStatusFilter ?? 'all'}'),
      value: _selectedStatusFilter,
      isExpanded: true,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
        filled: true, fillColor: const Color(0xFFFAFAFA),
        prefixIcon: const Icon(Icons.filter_list, size: 18, color: Color(0xFFF59E0B)),
        isDense: true,
      ),
      hint: const Text('Tất cả', style: TextStyle(fontSize: 13)),
      style: const TextStyle(color: Color(0xFF18181B), fontSize: 13),
      items: const [
        DropdownMenuItem<String>(value: null, child: Text('Tất cả')),
        DropdownMenuItem<String>(value: 'Pending', child: Text('Chờ duyệt')),
        DropdownMenuItem<String>(value: 'Approved', child: Text('Đã duyệt')),
        DropdownMenuItem<String>(value: 'Rejected', child: Text('Từ chối')),
      ],
      onChanged: (value) {
        setState(() { _selectedStatusFilter = value; });
        _loadRegistrations();
      },
    );
  }

  // ==================== TAB 1: TỔNG QUAN THEO CA ====================
  Widget _buildShiftOverviewTab() {
    // Collect shifts that have registrations or schedules
    final shiftIdsWithActivity = <String>{};
    for (var r in _registrations) {
      if (r.shiftId != null) shiftIdsWithActivity.add(r.shiftId!);
    }
    for (var s in _schedules) {
      if (s.shiftId != null && !s.isDayOff) shiftIdsWithActivity.add(s.shiftId!);
    }

    final activeShifts = _shifts.where((s) => shiftIdsWithActivity.contains(s.id)).toList();
    final hasDayOffRegs = _registrations.any((r) => r.isDayOff);

    return Column(
      children: [
        _buildWeekSelector(),
        Expanded(
          child: activeShifts.isEmpty && !hasDayOffRegs
              ? const EmptyState(icon: Icons.dashboard, title: 'Chưa có đăng ký nào', description: 'Không có đăng ký lịch làm việc trong tuần này')
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: activeShifts.length + (hasDayOffRegs ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index < activeShifts.length) {
                      return _buildShiftPanel(activeShifts[index]);
                    } else {
                      return _buildDayOffPanel();
                    }
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildShiftPanel(Shift shift) {
    final isMobile = Responsive.isMobile(context);
    final quota = _getQuotaForShift(shift.id);
    final maxEmp = (quota?['maxEmployees'] ?? 0) as int;
    final minEmp = (quota?['minEmployees'] ?? 0) as int;
    final warnThreshold = (quota?['warningThreshold'] ?? 2) as int;
    final days = List.generate(7, (i) => _selectedWeekStart.add(Duration(days: i)));

    final allPending = _registrations.where((r) =>
      r.shiftId == shift.id && r.status == ScheduleRegistrationStatus.pending).toList();
    final allProcessed = _registrations.where((r) =>
      r.shiftId == shift.id && r.status != ScheduleRegistrationStatus.pending).toList();
    final allForShift = _registrations.where((r) => r.shiftId == shift.id).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // === SHIFT HEADER ===
          Container(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E3A5F).withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: const Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
            ),
            child: isMobile
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: const Color(0xFF1E3A5F), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.schedule, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(shift.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF18181B))),
                        Text('${_formatTime(shift.startTime)} - ${_formatTime(shift.endTime)}', style: const TextStyle(fontSize: 12, color: Color(0xFF71717A))),
                      ])),
                      if (quota != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF1E3A5F).withValues(alpha: 0.3)),
                          ),
                          child: Text('$minEmp-$maxEmp người', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E3A5F))),
                        ),
                    ]),
                    if (allPending.isNotEmpty || allProcessed.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                        if (allPending.isNotEmpty) _buildCountBadge('${allPending.length} chờ duyệt', const Color(0xFFF59E0B)),
                        if (allProcessed.isNotEmpty) ...[const SizedBox(width: 6), _buildCountBadge('${allProcessed.length} đã xử lý', const Color(0xFF1E3A5F))],
                        const SizedBox(width: 12),
                        if (allPending.isNotEmpty && _canApprove) ...[_batchBtn('Duyệt tất cả', Icons.check, const Color(0xFF1E3A5F), () => _approveAllForShift(allPending), filled: true), const SizedBox(width: 6), _batchBtn('Từ chối tất cả', Icons.close, const Color(0xFFEF4444), () => _rejectAllForShift(allPending)), const SizedBox(width: 6)],
                        if (allProcessed.isNotEmpty && _canApprove) ...[_batchBtn('Hoàn duyệt', Icons.undo, const Color(0xFFF59E0B), () => _undoAllApprovals(allProcessed)), const SizedBox(width: 6)],
                        if (allForShift.isNotEmpty && _canDelete) _batchBtn('Xóa tất cả', Icons.delete_outline, const Color(0xFFEF4444), () => _deleteAllRegistrations(allForShift)),
                      ])),
                    ],
                  ])
                : Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: const Color(0xFF1E3A5F), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.schedule, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(shift.name, style: const TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(width: 8),
                    Text('(${_formatTime(shift.startTime)} - ${_formatTime(shift.endTime)})', style: const TextStyle(color: Color(0xFF71717A), fontSize: 13)),
                    if (quota != null) ...[
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF1E3A5F).withValues(alpha: 0.3)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.groups, size: 14, color: Color(0xFF1E3A5F)),
                          const SizedBox(width: 4),
                          Text('Định biên: $minEmp-$maxEmp', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E3A5F))),
                        ]),
                      ),
                    ],
                    const Spacer(),
                    if (allPending.isNotEmpty) ...[
                      _buildCountBadge('${allPending.length} chờ duyệt', const Color(0xFFF59E0B)),
                      const SizedBox(width: 6),
                    ],
                    if (allProcessed.isNotEmpty) ...[
                      _buildCountBadge('${allProcessed.length} đã xử lý', const Color(0xFF1E3A5F)),
                      const SizedBox(width: 6),
                    ],
                    if (allProcessed.isNotEmpty && _canApprove) ...[
                      _batchBtn('Hoàn duyệt', Icons.undo, const Color(0xFFF59E0B), () => _undoAllApprovals(allProcessed)),
                      const SizedBox(width: 6),
                    ],
                    if (allForShift.isNotEmpty && _canDelete) ...[
                      _batchBtn('Xóa tất cả', Icons.delete_outline, const Color(0xFFEF4444), () => _deleteAllRegistrations(allForShift)),
                      const SizedBox(width: 6),
                    ],
                    if (allPending.isNotEmpty && _canApprove) ...[
                      _batchBtn('Từ chối tất cả', Icons.close, const Color(0xFFEF4444), () => _rejectAllForShift(allPending)),
                      const SizedBox(width: 6),
                      _batchBtn('Duyệt tất cả', Icons.check, const Color(0xFF1E3A5F), () => _approveAllForShift(allPending), filled: true),
                    ],
                  ]),
          ),

          // === WEEK QUOTA SUMMARY STRIP ===
          _buildWeekQuotaStrip(shift, days, quota, maxEmp, minEmp, warnThreshold),

          // === PER-DAY DETAILS ===
          if (isMobile)
            ..._buildMobileDaySections(shift, days, quota, maxEmp, minEmp, warnThreshold)
          else
            _buildDesktopShiftTable(shift, days, quota, maxEmp, warnThreshold),
        ],
      ),
    );
  }

  Widget _buildDayOffPanel() {
    final dayOffRegs = _registrations.where((r) => r.isDayOff).toList();
    if (dayOffRegs.isEmpty) return const SizedBox.shrink();
    dayOffRegs.sort((a, b) => a.date.compareTo(b.date));
    final pending = dayOffRegs.where((r) => r.status == ScheduleRegistrationStatus.pending).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            border: const Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.beach_access, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Expanded(child: Text('Đăng ký nghỉ phép', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
            if (pending.isNotEmpty && _canApprove) ...[
              _buildCountBadge('${pending.length} chờ', const Color(0xFFF59E0B)),
              const SizedBox(width: 6),
              _batchBtn('Duyệt tất cả', Icons.check, const Color(0xFF1E3A5F), () => _approveAllForShift(pending), filled: true),
            ],
          ]),
        ),
        ...dayOffRegs.map((reg) {
          final emp = _findEmployee(reg.employeeUserId);
          return _buildRegRow(reg, emp);
        }),
      ]),
    );
  }

  // === WEEK QUOTA STRIP: 7 mini boxes showing scheduled/max per day ===
  Widget _buildWeekQuotaStrip(Shift shift, List<DateTime> days, Map<String, dynamic>? quota, int maxEmp, int minEmp, int warnThreshold) {
    final dayLabels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    final today = DateTime.now();
    final dateFormat = DateFormat('d/M');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF4F4F5)))),
      child: Row(
        children: List.generate(7, (i) {
          final day = days[i];
          final scheduled = _scheduledCount(shift.id, day);
          final pending = _pendingCountForShiftDay(shift.id, day);
          final isToday = day.year == today.year && day.month == today.month && day.day == today.day;
          final isSunday = i == 6;

          Color dotColor;
          if (quota != null) {
            dotColor = _getQuotaColor(scheduled, quota);
          } else {
            dotColor = scheduled > 0 ? const Color(0xFF22C55E) : const Color(0xFFE4E4E7);
          }

          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
              decoration: BoxDecoration(
                color: isToday ? const Color(0xFF1E3A5F).withValues(alpha: 0.08) : dotColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isToday ? const Color(0xFF1E3A5F).withValues(alpha: 0.4) : dotColor.withValues(alpha: 0.25),
                  width: isToday ? 1.5 : 1,
                ),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(dayLabels[i], style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold,
                  color: isToday ? const Color(0xFF1E3A5F) : isSunday ? const Color(0xFFEF4444) : const Color(0xFF71717A),
                )),
                Text(dateFormat.format(day), style: TextStyle(fontSize: 9, color: isToday ? const Color(0xFF1E3A5F) : const Color(0xFFA1A1AA))),
                const SizedBox(height: 4),
                Text(
                  quota != null ? '$scheduled/$maxEmp' : '$scheduled',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: dotColor),
                ),
                if (quota != null && maxEmp > 0) ...[
                  const SizedBox(height: 3),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: SizedBox(
                      height: 4,
                      child: LinearProgressIndicator(
                        value: (scheduled / maxEmp).clamp(0.0, 1.0),
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation(dotColor),
                      ),
                    ),
                  ),
                ],
                if (pending > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('+$pending', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B))),
                  ),
              ]),
            ),
          );
        }),
      ),
    );
  }

  // === MOBILE: Per-day sections ===
  List<Widget> _buildMobileDaySections(Shift shift, List<DateTime> days, Map<String, dynamic>? quota, int maxEmp, int minEmp, int warnThreshold) {
    final widgets = <Widget>[];
    final dayNames = ['Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'Chủ nhật'];
    final dateFormat = DateFormat('dd/MM');
    final today = DateTime.now();

    for (int i = 0; i < 7; i++) {
      final day = days[i];
      final regs = _regsForShiftDay(shift.id, day);
      final scheduled = _scheduledCount(shift.id, day);
      final pending = regs.where((r) => r.status == ScheduleRegistrationStatus.pending).toList();
      final isToday = day.year == today.year && day.month == today.month && day.day == today.day;

      if (regs.isEmpty && scheduled == 0) continue;

      final projected = scheduled + pending.length;
      final overQuota = quota != null && maxEmp > 0 && projected > maxEmp;

      widgets.add(Container(
        decoration: BoxDecoration(
          border: const Border(bottom: BorderSide(color: Color(0xFFF4F4F5))),
          color: isToday ? const Color(0xFF1E3A5F).withValues(alpha: 0.03) : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Day header with quota bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isToday ? const Color(0xFF1E3A5F).withValues(alpha: 0.05) : const Color(0xFFF8FAFC),
              border: const Border(bottom: BorderSide(color: Color(0xFFF4F4F5))),
            ),
            child: Row(children: [
              Text('${dayNames[i]} ${dateFormat.format(day)}', style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: isToday ? const Color(0xFF1E3A5F) : const Color(0xFF18181B),
              )),
              const Spacer(),
              if (quota != null && maxEmp > 0) ...[
                _buildMiniQuotaChip(scheduled, maxEmp, quota),
                const SizedBox(width: 6),
              ],
              if (pending.isNotEmpty)
                _buildCountBadge('${pending.length} chờ', const Color(0xFFF59E0B)),
              if (pending.length > 1 && _canApprove) ...[
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => _approveAllForShift(pending),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFF1E3A5F), borderRadius: BorderRadius.circular(6)),
                    child: const Text('Duyệt', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ]),
          ),
          // Over-quota warning
          if (overQuota)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: const Color(0xFFEF4444).withValues(alpha: 0.08),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFEF4444)),
                const SizedBox(width: 6),
                Expanded(child: Text(
                  'Nếu duyệt hết: $projected/$maxEmp → vượt ${projected - maxEmp} người',
                  style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444), fontWeight: FontWeight.w500),
                )),
              ]),
            ),
          // Employee rows
          ...regs.map((reg) {
            final emp = _findEmployee(reg.employeeUserId);
            return _buildRegRow(reg, emp);
          }),
        ]),
      ));
    }
    return widgets;
  }

  Widget _buildMiniQuotaChip(int scheduled, int maxEmp, Map<String, dynamic> quota) {
    final color = _getQuotaColor(scheduled, quota);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text('$scheduled/$maxEmp', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _buildRegRow(ScheduleRegistration reg, Employee employee) {
    final dateStr = DateFormat('EEE dd/MM', 'vi').format(reg.date);
    Color statusBg, statusText;
    IconData statusIcon;
    String statusLabel;
    switch (reg.status) {
      case ScheduleRegistrationStatus.approved:
        statusBg = const Color(0xFF22C55E).withValues(alpha: 0.08);
        statusText = const Color(0xFF22C55E);
        statusIcon = Icons.check_circle;
        statusLabel = 'Đã duyệt';
        break;
      case ScheduleRegistrationStatus.rejected:
        statusBg = const Color(0xFFEF4444).withValues(alpha: 0.08);
        statusText = const Color(0xFFEF4444);
        statusIcon = Icons.cancel;
        statusLabel = 'Từ chối';
        break;
      default:
        statusBg = const Color(0xFFF59E0B).withValues(alpha: 0.08);
        statusText = const Color(0xFFF59E0B);
        statusIcon = Icons.hourglass_empty;
        statusLabel = 'Chờ duyệt';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF4F4F5)))),
      child: Row(children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: const Color(0xFF1E3A5F),
          child: Text(
            employee.firstName.isNotEmpty ? employee.firstName[0].toUpperCase() : '?',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(employee.fullName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF18181B))),
          Row(children: [
            Text(employee.employeeCode, style: const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
            if (reg.isDayOff) ...[
              const SizedBox(width: 6),
              Text('• $dateStr', style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
            ],
            if (reg.note != null && reg.note!.isNotEmpty) ...[
              const SizedBox(width: 6),
              Flexible(child: Text('• ${reg.note}', style: const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA), fontStyle: FontStyle.italic), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ]),
        ])),
        const SizedBox(width: 6),
        if (reg.status == ScheduleRegistrationStatus.pending)
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (_canApprove) ...[
              _actionIcon(Icons.check, const Color(0xFF22C55E), () => _approveRegistration(reg.id), 'Duyệt'),
              const SizedBox(width: 5),
              _actionIcon(Icons.close, const Color(0xFFEF4444), () => _rejectRegistration(reg.id), 'Từ chối'),
            ],
            if (_canDelete) ...[
              const SizedBox(width: 5),
              _actionIcon(Icons.delete_outline, const Color(0xFF71717A), () => _deleteRegistration(reg.id), 'Xóa'),
            ],
          ])
        else
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(6)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(statusIcon, size: 12, color: statusText),
                const SizedBox(width: 3),
                Text(statusLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusText)),
              ]),
            ),
            if (_canApprove) ...[const SizedBox(width: 5), _actionIcon(Icons.undo, const Color(0xFFF59E0B), () => _undoRegistrationApproval(reg.id), 'Hoàn duyệt')],
            if (_canDelete) ...[const SizedBox(width: 5), _actionIcon(Icons.delete_outline, const Color(0xFFEF4444), () => _deleteRegistration(reg.id), 'Xóa')],
          ]),
      ]),
    );
  }

  // === DESKTOP: Shift table matrix ===
  Widget _buildDesktopShiftTable(Shift shift, List<DateTime> days, Map<String, dynamic>? quota, int maxEmp, int warnThreshold) {
    final dayNames = ['THỨ 2', 'THỨ 3', 'THỨ 4', 'THỨ 5', 'THỨ 6', 'THỨ 7', 'CN'];
    final dateFormat = DateFormat('d/M');
    final today = DateTime.now();

    // Collect unique employees for this shift
    final Set<String> employeeIds = {};
    for (var reg in _registrations.where((r) => r.shiftId == shift.id)) {
      employeeIds.add(reg.employeeUserId);
    }
    final employees = employeeIds.map((id) => _findEmployee(id)).toList();
    if (employees.isEmpty) return const SizedBox.shrink();

    // Build lookup: empId_dateKey → ScheduleRegistration
    final Map<String, ScheduleRegistration> regLookup = {};
    for (var reg in _registrations.where((r) => r.shiftId == shift.id)) {
      regLookup['${reg.employeeUserId}_${DateFormat('yyyy-MM-dd').format(reg.date)}'] = reg;
    }

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Table(
        border: TableBorder.all(color: const Color(0xFFE4E4E7), width: 1, borderRadius: BorderRadius.circular(8)),
        columnWidths: {0: const FlexColumnWidth(2.2), for (int i = 1; i <= 7; i++) i: const FlexColumnWidth(1), 8: const FlexColumnWidth(1.3)},
        children: [
          // HEADER ROW with quota indicators
          TableRow(
            decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
            children: [
              _buildTableHeaderCell('NHÂN VIÊN'),
              ...List.generate(7, (i) {
                final day = days[i];
                final isToday = day.year == today.year && day.month == today.month && day.day == today.day;
                final isSunday = i == 6;
                final scheduled = _scheduledCount(shift.id, day);
                final pending = _pendingCountForShiftDay(shift.id, day);
                final qColor = quota != null ? _getQuotaColor(scheduled, quota) : const Color(0xFF71717A);

                return TableCell(child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  decoration: isToday ? BoxDecoration(color: const Color(0xFF1E3A5F).withValues(alpha: 0.08)) : null,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(dayNames[i], style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                      color: isToday ? const Color(0xFF1E3A5F) : isSunday ? const Color(0xFFEF4444) : const Color(0xFF71717A))),
                    Text(dateFormat.format(day), style: TextStyle(fontSize: 9, color: isToday ? const Color(0xFF1E3A5F) : const Color(0xFFA1A1AA))),
                    const SizedBox(height: 4),
                    // Quota chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: qColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        quota != null ? '$scheduled/$maxEmp' : '$scheduled',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: qColor),
                      ),
                    ),
                    if (pending > 0)
                      Text('+$pending chờ', style: const TextStyle(fontSize: 8, color: Color(0xFFF59E0B), fontWeight: FontWeight.w600)),
                    // Per-day batch approve button
                    if (pending > 0 && _canApprove) ...[
                      const SizedBox(height: 3),
                      InkWell(
                        onTap: () {
                          final dayRegs = _registrations.where((r) =>
                            r.shiftId == shift.id &&
                            r.status == ScheduleRegistrationStatus.pending &&
                            DateFormat('yyyy-MM-dd').format(r.date) == DateFormat('yyyy-MM-dd').format(day)).toList();
                          _approveAllForShift(dayRegs);
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(color: const Color(0xFF1E3A5F), borderRadius: BorderRadius.circular(4)),
                          child: Text('Duyệt $pending', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ]),
                ));
              }),
              _buildTableHeaderCell('TỔNG NV'),
            ],
          ),
          // EMPLOYEE ROWS
          ...employees.map((employee) {
            final empRegs = _registrations.where((r) => r.shiftId == shift.id && r.employeeUserId == employee.id).toList();
            final approvedCount = empRegs.where((r) => r.status == ScheduleRegistrationStatus.approved).length;
            final pendingCount = empRegs.where((r) => r.status == ScheduleRegistrationStatus.pending).length;

            return TableRow(children: [
              _buildEmployeeNameCell(employee),
              ...List.generate(7, (dayIdx) {
                final dateKey = DateFormat('yyyy-MM-dd').format(days[dayIdx]);
                final key = '${employee.id}_$dateKey';
                final keyAlt = '${_effectiveUserId(employee)}_$dateKey';
                final reg = regLookup[key] ?? regLookup[keyAlt];
                return _buildDesktopGridCell(reg);
              }),
              // Employee total column
              TableCell(
                verticalAlignment: TableCellVerticalAlignment.middle,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (approvedCount > 0)
                      Text('$approvedCount✓', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF22C55E))),
                    if (pendingCount > 0)
                      Text('$pendingCount⏳', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFF59E0B))),
                    if (approvedCount == 0 && pendingCount == 0)
                      const Text('-', style: TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
                  ]),
                ),
              ),
            ]);
          }),
        ],
      ),
    );
  }

  Widget _buildTableHeaderCell(String text) {
    return TableCell(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF71717A))),
    ));
  }

  Widget _buildEmployeeNameCell(Employee employee) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(children: [
          CircleAvatar(radius: 14, backgroundColor: const Color(0xFF1E3A5F),
            child: Text(employee.firstName.isNotEmpty ? employee.firstName[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
          const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(employee.fullName, style: const TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.w600, fontSize: 12), overflow: TextOverflow.ellipsis),
            Text(employee.employeeCode, style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 10)),
          ])),
        ]),
      ),
    );
  }

  Widget _buildDesktopGridCell(ScheduleRegistration? reg) {
    if (reg == null) return const TableCell(verticalAlignment: TableCellVerticalAlignment.middle, child: SizedBox(height: 52));

    Color bgColor, statusColor;
    IconData statusIcon;
    String tooltip;
    switch (reg.status) {
      case ScheduleRegistrationStatus.approved:
        bgColor = const Color(0xFF22C55E).withValues(alpha: 0.08);
        statusColor = const Color(0xFF22C55E);
        statusIcon = Icons.check_circle;
        tooltip = 'Đã duyệt';
        break;
      case ScheduleRegistrationStatus.rejected:
        bgColor = const Color(0xFFEF4444).withValues(alpha: 0.08);
        statusColor = const Color(0xFFEF4444);
        statusIcon = Icons.cancel;
        tooltip = 'Từ chối';
        break;
      default:
        bgColor = const Color(0xFFF59E0B).withValues(alpha: 0.08);
        statusColor = const Color(0xFFF59E0B);
        statusIcon = Icons.hourglass_empty;
        tooltip = 'Chờ duyệt';
    }

    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Container(
        decoration: BoxDecoration(color: bgColor),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: reg.status == ScheduleRegistrationStatus.pending
            ? Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                if (_canApprove) ...[
                  Tooltip(message: 'Duyệt', child: InkWell(onTap: () => _approveRegistration(reg.id), borderRadius: BorderRadius.circular(4),
                    child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: const Color(0xFF22C55E), borderRadius: BorderRadius.circular(4)),
                      child: const Icon(Icons.check, color: Colors.white, size: 14)))),
                  const SizedBox(width: 4),
                  Tooltip(message: 'Từ chối', child: InkWell(onTap: () => _rejectRegistration(reg.id), borderRadius: BorderRadius.circular(4),
                    child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(4)),
                      child: const Icon(Icons.close, color: Colors.white, size: 14)))),
                ],
                if (_canDelete) ...[
                  const SizedBox(width: 4),
                  Tooltip(message: 'Xóa', child: InkWell(onTap: () => _deleteRegistration(reg.id), borderRadius: BorderRadius.circular(4),
                    child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: const Color(0xFF71717A), borderRadius: BorderRadius.circular(4)),
                      child: const Icon(Icons.delete_outline, color: Colors.white, size: 14)))),
                ],
              ])
            : Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                Tooltip(message: tooltip, child: Icon(statusIcon, color: statusColor, size: 18)),
                if (_canApprove) ...[
                  const SizedBox(width: 4),
                  Tooltip(message: 'Hoàn duyệt', child: InkWell(onTap: () => _undoRegistrationApproval(reg.id), borderRadius: BorderRadius.circular(4),
                    child: Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(color: const Color(0xFFF59E0B), borderRadius: BorderRadius.circular(4)),
                      child: const Icon(Icons.undo, color: Colors.white, size: 12)))),
                ],
                if (_canDelete) ...[
                  const SizedBox(width: 3),
                  Tooltip(message: 'Xóa', child: InkWell(onTap: () => _deleteRegistration(reg.id), borderRadius: BorderRadius.circular(4),
                    child: Container(padding: const EdgeInsets.all(3), decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(4)),
                      child: const Icon(Icons.delete_outline, color: Colors.white, size: 12)))),
                ],
              ]),
      ),
    );
  }

  // ==================== TAB 2: PHÂN BỔ NHÂN VIÊN ====================
  // Compute employees who have NO registrations and NO schedules for selected week
  List<Employee> _getUnregisteredEmployees() {
    final registeredIds = <String>{};
    for (var reg in _registrations) {
      registeredIds.add(reg.employeeUserId);
    }
    for (var s in _schedules) {
      registeredIds.add(s.employeeUserId);
    }
    return _employees.where((e) => !registeredIds.contains(_effectiveUserId(e))).toList();
  }

  Widget _buildEmployeeDistributionTab() {
    final summaries = _computeEmployeeSummaries();
    final unregistered = _getUnregisteredEmployees();
    final isMobile = Responsive.isMobile(context);
    final sortedEntries = summaries.entries.toList()
      ..sort((a, b) => a.value.scheduledShifts.compareTo(b.value.scheduledShifts));

    return Column(
      children: [
        _buildWeekSelector(),
        if (unregistered.isNotEmpty) _buildUnregisteredSection(unregistered),
        if (summaries.isNotEmpty) _buildStatsOverview(summaries),
        if (summaries.isEmpty && unregistered.isEmpty)
          const Expanded(child: EmptyState(icon: Icons.people, title: 'Chưa có dữ liệu', description: 'Không có đăng ký hoặc lịch làm việc trong tuần này'))
        else
          Expanded(
            child: isMobile
                ? _buildMobileEmployeeDistribution(sortedEntries)
                : _buildDesktopEmployeeDistribution(sortedEntries),
          ),
      ],
    );
  }

  // === UNREGISTERED EMPLOYEES SECTION ===
  Widget _buildUnregisteredSection(List<Employee> unregistered) {
    final isMobile = Responsive.isMobile(context);
    final weekEnd = _selectedWeekStart.add(const Duration(days: 6));
    final dateFormat = DateFormat('dd/MM');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: EdgeInsets.all(isMobile ? 12 : 16),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFEF4444).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Chưa đăng ký lịch (${unregistered.length})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFFEF4444))),
              Text('Tuần ${dateFormat.format(_selectedWeekStart)} - ${dateFormat.format(weekEnd)}', style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
            ])),
            ElevatedButton.icon(
              onPressed: () => _sendReminderToAll(unregistered),
              icon: const Icon(Icons.notifications_active, size: 16),
              label: Text(isMobile ? 'Nhắc tất cả' : 'Gửi nhắc nhở tất cả', style: const TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
              ),
            ),
          ]),
        ),
        // Employee list
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: unregistered.map((emp) => _buildUnregisteredChip(emp)).toList(),
          ),
        ),
      ]),
    );
  }

  Widget _buildUnregisteredChip(Employee emp) {
    return GestureDetector(
      onTap: () => _sendReminderToEmployee(emp),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.15),
            child: Text(
              emp.firstName.isNotEmpty ? emp.firstName[0].toUpperCase() : '?',
              style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 10),
            ),
          ),
          const SizedBox(width: 6),
          Text(emp.fullName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF18181B))),
          const SizedBox(width: 4),
          const Icon(Icons.notifications_none, size: 14, color: Color(0xFFEF4444)),
        ]),
      ),
    );
  }

  // === SEND REMINDER ===
  Future<void> _sendReminderToAll(List<Employee> employees) async {
    final confirmed = await _showConfirmDialog(
      'Gửi nhắc nhở',
      'Gửi thông báo nhắc nhở đăng ký lịch đến ${employees.length} nhân viên?',
      'Gửi nhắc nhở',
      const Color(0xFFEF4444),
    );
    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final fromDate = _selectedWeekStart;
      final toDate = _selectedWeekStart.add(const Duration(days: 6));
      final result = await _apiService.sendScheduleReminder({
        'fromDate': fromDate.toIso8601String(),
        'toDate': toDate.toIso8601String(),
        'employeeUserIds': employees.map((e) => _effectiveUserId(e)).toList(),
      });
      if (mounted) {
        if (result['isSuccess'] == true) {
          final count = result['data'] ?? employees.length;
          appNotification.showSuccess(title: 'Đã gửi nhắc nhở', message: 'Đã gửi thông báo đến $count nhân viên yêu cầu đăng ký lịch');
        } else {
          appNotification.showError(title: 'Lỗi', message: result['message'] ?? 'Không thể gửi nhắc nhở');
        }
      }
    } catch (e) {
      if (mounted) appNotification.showError(title: 'Lỗi', message: '$e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _sendReminderToEmployee(Employee emp) async {
    final confirmed = await _showConfirmDialog(
      'Gửi nhắc nhở',
      'Gửi thông báo nhắc nhở đăng ký lịch đến ${emp.fullName}?',
      'Gửi',
      const Color(0xFFEF4444),
    );
    if (confirmed != true) return;

    try {
      final fromDate = _selectedWeekStart;
      final toDate = _selectedWeekStart.add(const Duration(days: 6));
      final result = await _apiService.sendScheduleReminder({
        'fromDate': fromDate.toIso8601String(),
        'toDate': toDate.toIso8601String(),
        'employeeUserIds': [_effectiveUserId(emp)],
      });
      if (mounted) {
        if (result['isSuccess'] == true) {
          appNotification.showSuccess(title: 'Đã gửi', message: 'Đã gửi nhắc nhở đến ${emp.fullName}');
        } else {
          appNotification.showError(title: 'Lỗi', message: result['message'] ?? 'Không thể gửi nhắc nhở');
        }
      }
    } catch (e) {
      if (mounted) appNotification.showError(title: 'Lỗi', message: '$e');
    }
  }

  Widget _buildStatsOverview(Map<String, _EmployeeSummary> summaries) {
    final values = summaries.values.toList();
    final totalRegs = values.fold<int>(0, (sum, s) => sum + s.totalRegistered);
    final totalApproved = values.fold<int>(0, (sum, s) => sum + s.approved);
    final totalPending = values.fold<int>(0, (sum, s) => sum + s.pending);
    final totalRejected = values.fold<int>(0, (sum, s) => sum + s.rejected);
    final scheduledValues = values.map((s) => s.scheduledShifts).toList();
    final avgScheduled = values.isNotEmpty ? scheduledValues.reduce((a, b) => a + b) / values.length : 0.0;
    final maxScheduled = scheduledValues.isNotEmpty ? scheduledValues.reduce(max) : 0;
    final minScheduled = scheduledValues.isNotEmpty ? scheduledValues.reduce(min) : 0;

    final empMax = maxScheduled > 0 ? values.where((s) => s.scheduledShifts == maxScheduled).map((s) => _findEmployee(s.employeeId).fullName).join(', ') : '-';
    final empMin = values.where((s) => s.scheduledShifts == minScheduled).map((s) => _findEmployee(s.employeeId).fullName).join(', ');

    final isMobile = Responsive.isMobile(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: EdgeInsets.all(isMobile ? 12 : 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF1E3A5F), Color(0xFF2D5986)]),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: const Color(0xFF1E3A5F).withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          // Top row: key metrics
          Row(children: [
            _statBox('Tổng ĐK', '$totalRegs', Colors.white),
            _statBox('Đã duyệt', '$totalApproved', const Color(0xFF22C55E)),
            _statBox('Chờ duyệt', '$totalPending', const Color(0xFFF59E0B)),
            _statBox('Từ chối', '$totalRejected', const Color(0xFFEF4444)),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: isMobile
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('📊 Trung bình: ${avgScheduled.toStringAsFixed(1)} ca/nhân viên', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text('⬆ Nhiều nhất: $empMax ($maxScheduled ca)', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11)),
                    Text('⬇ Ít nhất: $empMin ($minScheduled ca)', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11)),
                    if (maxScheduled - minScheduled > 3)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: const Color(0xFFEF4444).withValues(alpha: 0.3), borderRadius: BorderRadius.circular(6)),
                          child: const Text('⚠ Chênh lệch lớn - cần cân bằng lại phân ca', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                      ),
                  ])
                : Row(children: [
                    Expanded(child: Text('📊 TB: ${avgScheduled.toStringAsFixed(1)} ca/NV', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600))),
                    Expanded(child: Text('⬆ Nhiều nhất: $empMax ($maxScheduled ca)', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11))),
                    Expanded(child: Text('⬇ Ít nhất: $empMin ($minScheduled ca)', style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11))),
                    if (maxScheduled - minScheduled > 3)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFFEF4444).withValues(alpha: 0.3), borderRadius: BorderRadius.circular(6)),
                        child: const Text('⚠ Mất cân bằng', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                  ]),
          ),
        ],
      ),
    );
  }

  Widget _statBox(String label, String value, Color valueColor) {
    return Expanded(child: Column(children: [
      Text(value, style: TextStyle(color: valueColor, fontSize: 20, fontWeight: FontWeight.bold)),
      Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
    ]));
  }

  Widget _buildMobileEmployeeDistribution(List<MapEntry<String, _EmployeeSummary>> entries) {
    final values = entries.map((e) => e.value).toList();
    final avgScheduled = values.isNotEmpty ? values.fold<int>(0, (s, v) => s + v.scheduledShifts) / values.length : 0.0;
    final maxScheduled = values.isNotEmpty ? values.map((s) => s.scheduledShifts).reduce(max) : 1;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final emp = _findEmployee(entry.key);
        final summary = entry.value;
        return _buildMobileEmployeeCard(emp, summary, avgScheduled, maxScheduled);
      },
    );
  }

  Widget _buildMobileEmployeeCard(Employee emp, _EmployeeSummary summary, double avgScheduled, int maxScheduled) {
    final isUnder = summary.scheduledShifts < avgScheduled - 1.5 && summary.pending > 0;
    final isOver = summary.scheduledShifts > avgScheduled + 1.5;
    final isZero = summary.scheduledShifts == 0 && summary.totalRegistered > 0;
    final barRatio = maxScheduled > 0 ? summary.scheduledShifts / maxScheduled : 0.0;

    Color borderColor = const Color(0xFFE4E4E7);
    String? warningText;
    if (isZero) {
      borderColor = const Color(0xFFEF4444);
      warningText = '⚠ Chưa được xếp ca nào';
    } else if (isUnder) {
      borderColor = const Color(0xFFF59E0B);
      warningText = '⚠ Ít ca hơn trung bình';
    } else if (isOver) {
      borderColor = const Color(0xFF3B82F6);
      warningText = '📌 Nhiều ca hơn trung bình';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: isZero || isUnder || isOver ? 1.5 : 1),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: const Color(0xFF1E3A5F),
            child: Text(emp.firstName.isNotEmpty ? emp.firstName[0].toUpperCase() : '?',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(emp.fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF18181B))),
            Text(emp.employeeCode, style: const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isZero ? const Color(0xFFEF4444).withValues(alpha: 0.1) : const Color(0xFF1E3A5F).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('${summary.scheduledShifts} ca', style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.bold,
              color: isZero ? const Color(0xFFEF4444) : const Color(0xFF1E3A5F),
            )),
          ),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 6,
            child: LinearProgressIndicator(
              value: barRatio.clamp(0.0, 1.0),
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation(
                isZero ? const Color(0xFFEF4444)
                    : isUnder ? const Color(0xFFF59E0B)
                    : isOver ? const Color(0xFF3B82F6)
                    : const Color(0xFF22C55E)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          _miniCountChip('${summary.totalRegistered} ĐK', const Color(0xFF71717A)),
          const SizedBox(width: 6),
          _miniCountChip('${summary.approved} duyệt', const Color(0xFF22C55E)),
          const SizedBox(width: 6),
          _miniCountChip('${summary.pending} chờ', const Color(0xFFF59E0B)),
          if (summary.rejected > 0) ...[
            const SizedBox(width: 6),
            _miniCountChip('${summary.rejected} TC', const Color(0xFFEF4444)),
          ],
        ]),
        if (warningText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(warningText, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: borderColor)),
          ),
      ]),
    );
  }

  Widget _miniCountChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _buildDesktopEmployeeDistribution(List<MapEntry<String, _EmployeeSummary>> entries) {
    final values = entries.map((e) => e.value).toList();
    final avgScheduled = values.isNotEmpty ? values.fold<int>(0, (s, v) => s + v.scheduledShifts) / values.length : 0.0;
    final maxBar = values.isNotEmpty ? values.map((s) => s.scheduledShifts).reduce(max) : 1;

    return SingleChildScrollView(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE4E4E7)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
          dataRowColor: WidgetStateProperty.all(Colors.white),
          border: TableBorder.all(color: const Color(0xFFF4F4F5), width: 1),
          columns: const [
            DataColumn(label: Text('NHÂN VIÊN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
            DataColumn(label: Text('CA ĐÃ XẾP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), numeric: true),
            DataColumn(label: Text('PHÂN BỔ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
            DataColumn(label: Text('TỔNG ĐK', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), numeric: true),
            DataColumn(label: Text('DUYỆT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), numeric: true),
            DataColumn(label: Text('CHỜ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), numeric: true),
            DataColumn(label: Text('TỪ CHỐI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)), numeric: true),
            DataColumn(label: Text('TRẠNG THÁI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
          ],
          rows: entries.map((entry) {
            final emp = _findEmployee(entry.key);
            final s = entry.value;
            final isZero = s.scheduledShifts == 0 && s.totalRegistered > 0;
            final isUnder = s.scheduledShifts < avgScheduled - 1.5 && s.pending > 0;
            final isOver = s.scheduledShifts > avgScheduled + 1.5;
            final barRatio = maxBar > 0 ? s.scheduledShifts / maxBar : 0.0;

            Color barColor = const Color(0xFF22C55E);
            if (isZero) barColor = const Color(0xFFEF4444);
            else if (isUnder) barColor = const Color(0xFFF59E0B);
            else if (isOver) barColor = const Color(0xFF3B82F6);

            String statusText = '✅ Bình thường';
            Color statusColor = const Color(0xFF22C55E);
            if (isZero) { statusText = '🔴 Chưa xếp ca'; statusColor = const Color(0xFFEF4444); }
            else if (isUnder) { statusText = '🟡 Ít ca'; statusColor = const Color(0xFFF59E0B); }
            else if (isOver) { statusText = '🔵 Nhiều ca'; statusColor = const Color(0xFF3B82F6); }

            return DataRow(
              color: isZero ? WidgetStateProperty.all(const Color(0xFFEF4444).withValues(alpha: 0.04)) : null,
              cells: [
                DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                  CircleAvatar(radius: 14, backgroundColor: const Color(0xFF1E3A5F),
                    child: Text(emp.firstName.isNotEmpty ? emp.firstName[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(emp.fullName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                    Text(emp.employeeCode, style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 10)),
                  ]),
                ])),
                DataCell(Text('${s.scheduledShifts}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: barColor))),
                DataCell(SizedBox(width: 120, child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(height: 8, child: LinearProgressIndicator(
                    value: barRatio.clamp(0.0, 1.0),
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation(barColor),
                  )),
                ))),
                DataCell(Text('${s.totalRegistered}', style: const TextStyle(fontSize: 13))),
                DataCell(Text('${s.approved}', style: const TextStyle(fontSize: 13, color: Color(0xFF22C55E), fontWeight: FontWeight.w600))),
                DataCell(Text('${s.pending}', style: TextStyle(fontSize: 13, color: s.pending > 0 ? const Color(0xFFF59E0B) : const Color(0xFFA1A1AA), fontWeight: s.pending > 0 ? FontWeight.w600 : FontWeight.normal))),
                DataCell(Text('${s.rejected}', style: TextStyle(fontSize: 13, color: s.rejected > 0 ? const Color(0xFFEF4444) : const Color(0xFFA1A1AA)))),
                DataCell(Text(statusText, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor))),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // ==================== SHARED WIDGETS ====================
  Widget _actionIcon(IconData icon, Color color, VoidCallback onTap, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
          child: Icon(icon, color: Colors.white, size: 16),
        ),
      ),
    );
  }

  Widget _batchBtn(String label, IconData icon, Color color, VoidCallback onTap, {bool filled = false}) {
    if (filled) {
      return ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color, foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          minimumSize: Size.zero,
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      style: OutlinedButton.styleFrom(
        foregroundColor: color, side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
      ),
    );
  }

  Widget _buildCountBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }

  // ==================== APPROVAL ACTIONS ====================
  Future<void> _approveRegistration(String regId) async {
    final confirmed = await _showConfirmDialog('Xác nhận duyệt', 'Bạn có chắc chắn muốn duyệt đăng ký này?', 'Duyệt', const Color(0xFF1E3A5F));
    if (confirmed != true) return;
    try {
      await _apiService.approveScheduleRegistration(regId, {'isApproved': true});
      if (mounted) appNotification.showSuccess(title: 'Duyệt đăng ký', message: 'Đã duyệt đăng ký');
      await _loadSchedules(); await _loadRegistrations();
    } catch (e) {
      if (mounted) appNotification.showError(title: 'Lỗi', message: '$e');
    }
  }

  Future<void> _rejectRegistration(String regId) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Từ chối đăng ký', style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Bạn có chắc chắn muốn từ chối đăng ký này?'),
          const SizedBox(height: 12),
          TextField(controller: reasonController, decoration: InputDecoration(
            labelText: 'Lý do từ chối', hintText: 'Nhập lý do...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ), maxLines: 2),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A)))),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)), child: const Text('Từ chối')),
        ],
      ),
    );
    if (confirmed != true) { reasonController.dispose(); return; }
    final reason = reasonController.text.trim().isNotEmpty ? reasonController.text.trim() : 'Từ chối bởi quản lý';
    reasonController.dispose();
    try {
      await _apiService.approveScheduleRegistration(regId, {'isApproved': false, 'rejectionReason': reason});
      if (mounted) appNotification.showWarning(title: 'Từ chối đăng ký', message: 'Đã từ chối đăng ký');
      await _loadSchedules(); await _loadRegistrations();
    } catch (e) {
      if (mounted) appNotification.showError(title: 'Lỗi', message: '$e');
    }
  }

  Future<void> _undoRegistrationApproval(String regId) async {
    try {
      final result = await _apiService.undoScheduleRegistrationApproval(regId);
      if (mounted) {
        if (result['isSuccess'] == true) {
          appNotification.showSuccess(title: 'Hoàn duyệt', message: 'Đã hoàn duyệt đăng ký');
        } else {
          appNotification.showError(title: 'Lỗi', message: result['message'] ?? 'Không thể hoàn duyệt');
        }
      }
      await _loadSchedules(); await _loadRegistrations();
    } catch (e) {
      if (mounted) appNotification.showError(title: 'Lỗi', message: '$e');
    }
  }

  Future<void> _deleteRegistration(String regId) async {
    final confirmed = await _showConfirmDialog('Xác nhận xóa', 'Bạn có chắc chắn muốn xóa đăng ký này?', 'Xóa', const Color(0xFFEF4444));
    if (confirmed != true) return;
    try {
      final result = await _apiService.deleteScheduleRegistration(regId);
      if (mounted) {
        if (result['isSuccess'] == true) {
          appNotification.showSuccess(title: 'Xóa đăng ký', message: 'Đã xóa đăng ký thành công');
        } else {
          appNotification.showError(title: 'Lỗi', message: result['message'] ?? 'Không thể xóa đăng ký');
        }
      }
      await _loadSchedules(); await _loadRegistrations();
    } catch (e) {
      if (mounted) appNotification.showError(title: 'Lỗi', message: '$e');
    }
  }

  // ==================== BATCH ACTIONS ====================
  Future<void> _approveAllForShift(List<ScheduleRegistration> regs) async {
    final confirmed = await _showConfirmDialog('Xác nhận duyệt hàng loạt', 'Bạn có chắc chắn muốn duyệt ${regs.length} đăng ký?', 'Duyệt tất cả', const Color(0xFF1E3A5F));
    if (confirmed != true) return;
    setState(() => _isLoading = true);
    try {
      for (var reg in regs) { await _apiService.approveScheduleRegistration(reg.id, {'isApproved': true}); }
      if (mounted) appNotification.showSuccess(title: 'Duyệt hàng loạt', message: 'Đã duyệt ${regs.length} đăng ký');
      await _loadSchedules(); await _loadRegistrations();
    } catch (e) {
      if (mounted) appNotification.showError(title: 'Lỗi', message: '$e');
    } finally { setState(() => _isLoading = false); }
  }

  Future<void> _rejectAllForShift(List<ScheduleRegistration> regs) async {
    final confirmed = await _showConfirmDialog('Xác nhận từ chối hàng loạt', 'Bạn có chắc chắn muốn từ chối ${regs.length} đăng ký?', 'Từ chối tất cả', const Color(0xFFEF4444));
    if (confirmed != true) return;
    setState(() => _isLoading = true);
    try {
      for (var reg in regs) { await _apiService.approveScheduleRegistration(reg.id, {'isApproved': false, 'rejectionReason': 'Từ chối hàng loạt'}); }
      if (mounted) appNotification.showWarning(title: 'Từ chối hàng loạt', message: 'Đã từ chối ${regs.length} đăng ký');
      await _loadSchedules(); await _loadRegistrations();
    } catch (e) {
      if (mounted) appNotification.showError(title: 'Lỗi', message: '$e');
    } finally { setState(() => _isLoading = false); }
  }

  Future<void> _undoAllApprovals(List<ScheduleRegistration> regs) async {
    final confirmed = await _showConfirmDialog('Xác nhận hoàn duyệt', 'Bạn có chắc chắn muốn hoàn duyệt ${regs.length} đăng ký?', 'Hoàn duyệt', const Color(0xFFF59E0B));
    if (confirmed != true) return;
    setState(() => _isLoading = true);
    try {
      for (var reg in regs) { await _apiService.undoScheduleRegistrationApproval(reg.id); }
      if (mounted) appNotification.showSuccess(title: 'Hoàn duyệt hàng loạt', message: 'Đã hoàn duyệt ${regs.length} đăng ký');
      await _loadSchedules(); await _loadRegistrations();
    } catch (e) {
      if (mounted) appNotification.showError(title: 'Lỗi', message: '$e');
    } finally { setState(() => _isLoading = false); }
  }

  Future<void> _deleteAllRegistrations(List<ScheduleRegistration> regs) async {
    final confirmed = await _showConfirmDialog('Xác nhận xóa', 'Bạn có chắc chắn muốn xóa ${regs.length} đăng ký?', 'Xóa tất cả', const Color(0xFFEF4444));
    if (confirmed != true) return;
    setState(() => _isLoading = true);
    try {
      for (var reg in regs) { await _apiService.deleteScheduleRegistration(reg.id); }
      if (mounted) appNotification.showSuccess(title: 'Xóa hàng loạt', message: 'Đã xóa ${regs.length} đăng ký');
      await _loadSchedules(); await _loadRegistrations();
    } catch (e) {
      if (mounted) appNotification.showError(title: 'Lỗi', message: '$e');
    } finally { setState(() => _isLoading = false); }
  }

  // ==================== DIALOGS ====================
  Future<bool?> _showConfirmDialog(String title, String content, String confirmText, Color confirmColor) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold)),
        content: Text(content),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A)))),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: confirmColor), child: Text(confirmText)),
        ],
      ),
    );
  }
}
