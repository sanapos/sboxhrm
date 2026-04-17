import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/file_saver.dart' as file_saver;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as excel_lib;
import '../services/api_service.dart';
import '../models/hrm.dart';
import '../models/employee.dart';
import '../widgets/loading_widget.dart';
import '../utils/responsive_helper.dart';
import '../l10n/app_localizations.dart';

import '../widgets/notification_overlay.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../providers/auth_provider.dart';
import 'main_layout.dart';

class WorkScheduleScreen extends StatefulWidget {
  const WorkScheduleScreen({super.key});

  @override
  State<WorkScheduleScreen> createState() => _WorkScheduleScreenState();
}

class _WorkScheduleScreenState extends State<WorkScheduleScreen> with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  bool _isEmployee = false;
  late TabController _tabController;

  AppLocalizations get _l10n => AppLocalizations.of(context);

  // GlobalKeys for PNG export
  final GlobalKey _shiftCentricTableKey = GlobalKey();
  final GlobalKey _scheduleTableKey = GlobalKey();
  final GlobalKey _approvedTableKey = GlobalKey();
  
  List<WorkSchedule> _schedules = [];
  List<ScheduleRegistration> _registrations = [];
  List<Shift> _shifts = [];
  List<Employee> _employees = [];
  List<Map<String, dynamic>> _departments = [];
  String? _selectedDepartment;
  bool _isLoading = true;
  bool _showMobileFilters = false;
  
  DateTime _selectedWeekStart = _getWeekStart(DateTime.now());
  String? _selectedEmployeeId;

  // Pagination
  int _schedulePage = 1;
  int _approvedPage = 1;
  int _schedulePageSize = 50;
  final List<int> _pageSizeOptions = [20, 50, 100, 200];

  /// Employees filtered by selected department
  List<Employee> get _filteredEmployees {
    if (_selectedDepartment == null) return _employees;
    return _employees.where((e) => e.department == _selectedDepartment).toList();
  }
  
  // Pending registrations (local, not submitted yet)
  final List<Map<String, dynamic>> _pendingRegistrations = [];

  // Staffing quotas loaded from server
  List<Map<String, dynamic>> _staffingQuotas = [];

  // Focused day index for single-day detail view in manager grid (null = show all 7 days)
  int? _focusedDayIndex;
  int? _pendingFocusedDay;
  int? _approvedFocusedDay;

  // Helper: get the effective user ID for an employee (Employee.Id for DB compatibility)
  String _effectiveUserId(Employee e) => e.id;

  static DateTime _getWeekStart(DateTime date) {
    final d = date.subtract(Duration(days: date.weekday - 1));
    return DateTime(d.year, d.month, d.day);
  }

  @override
  void initState() {
    super.initState();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    _isEmployee = authProvider.userRole == 'Employee';
    _tabController = TabController(length: _isEmployee ? 1 : 3, vsync: this);
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      _pendingRegistrations.clear();
      if (_isEmployee) {
        // Employee: load shifts, own schedules and own registrations
        await Future.wait([
          _loadShifts(),
          _loadSchedules(),
          _loadRegistrations(),
        ]);
      } else {
        await Future.wait([
          _loadShifts(),
          _loadEmployees(),
          _loadDepartments(),
          _loadSchedules(),
          _loadRegistrations(),
          _loadStaffingQuotas(),
        ]);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadShifts() async {
    final shifts = await _apiService.getShifts();
    if (!mounted) return;
    setState(() {
      _shifts = shifts.map((s) => Shift.fromJson(s)).toList();
      // Sort by startTime so shifts display in chronological order
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

  Future<void> _loadDepartments() async {
    try {
      final result = await _apiService.getDepartments(pageSize: 200, isActive: true);
      if (!mounted) return;
      if (result['isSuccess'] == true && result['data'] != null) {
        final data = result['data'];
        final items = data is List ? data : (data['items'] ?? []);
        setState(() {
          _departments = List<Map<String, dynamic>>.from(items);
        });
      }
    } catch (e) {
      debugPrint('Load departments error: $e');
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

  /// Get staffing quota for a specific shift (and optionally department)
  Map<String, dynamic>? _getQuotaForShift(String shiftId, {String? department}) {
    // First try department-specific quota
    if (department != null) {
      final deptQuota = _staffingQuotas.where((q) =>
        q['shiftTemplateId'] == shiftId && q['department'] == department).firstOrNull;
      if (deptQuota != null) return deptQuota;
    }
    // Fall back to global quota (department == null)
    return _staffingQuotas.where((q) =>
      q['shiftTemplateId'] == shiftId && (q['department'] == null || q['department'] == '')).firstOrNull;
  }

  Future<void> _loadSchedules() async {
    final DateTime fromDate;
    final DateTime toDate;
    // Both employee and manager use weekly view now
    fromDate = _selectedWeekStart;
    toDate = _selectedWeekStart.add(const Duration(days: 6));
    
    final Map<String, dynamic> result;
    if (_isEmployee) {
      result = await _apiService.getMyWorkSchedules(
        fromDate: fromDate,
        toDate: toDate,
        pageSize: 500,
      );
    } else {
      result = await _apiService.getWorkSchedules(
        fromDate: fromDate,
        toDate: toDate,
        employeeUserId: _selectedEmployeeId,
        pageSize: 500,
      );
    }
    
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
    final DateTime fromDate;
    final DateTime toDate;
    // Both employee and manager use weekly view now
    fromDate = _selectedWeekStart;
    toDate = _selectedWeekStart.add(const Duration(days: 6));
    
    final Map<String, dynamic> result;
    if (_isEmployee) {
      result = await _apiService.getMyScheduleRegistrations(
        fromDate: fromDate,
        toDate: toDate,
        pageSize: 500,
      );
    } else {
      result = await _apiService.getScheduleRegistrations(
        fromDate: fromDate,
        toDate: toDate,
        pageSize: 500,
      );
    }
    
    if (!mounted) return;
    if (result['isSuccess'] == true && result['data'] != null) {
      final data = result['data'];
      final items = data is List ? data : (data['items'] ?? []);
      setState(() {
        _registrations = (items as List).map((r) => ScheduleRegistration.fromJson(r)).toList();
      });
    }
  }

  void _previousWeek() {
    setState(() {
      _selectedWeekStart = _selectedWeekStart.subtract(const Duration(days: 7));
      _focusedDayIndex = null;
      _pendingFocusedDay = null;
      _approvedFocusedDay = null;
    });
    _loadSchedules();
    _loadRegistrations();
  }

  void _nextWeek() {
    setState(() {
      _selectedWeekStart = _selectedWeekStart.add(const Duration(days: 7));
      _focusedDayIndex = null;
      _pendingFocusedDay = null;
      _approvedFocusedDay = null;
    });
    _loadSchedules();
    _loadRegistrations();
  }

  void _goToThisWeek() {
    setState(() {
      _selectedWeekStart = _getWeekStart(DateTime.now());
      _focusedDayIndex = null;
      _pendingFocusedDay = null;
      _approvedFocusedDay = null;
    });
    _loadSchedules();
    _loadRegistrations();
  }

  int _getWeekNumber(DateTime date) {
    final firstDayOfYear = DateTime(date.year, 1, 1);
    final daysSinceFirstDay = date.difference(firstDayOfYear).inDays;
    return ((daysSinceFirstDay + firstDayOfYear.weekday) / 7).ceil();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF1F5F9),
        body: LoadingWidget(),
      );
    }
    if (_isEmployee) {
      return Scaffold(
        backgroundColor: const Color(0xFFF1F5F9),
        body: _buildEmployeeCalendarView(),
        floatingActionButton: _pendingRegistrations.isNotEmpty
            ? FloatingActionButton.extended(
                onPressed: _submitAllRegistrations,
                backgroundColor: const Color(0xFF1E3A5F),
                icon: const Icon(Icons.send, size: 18),
                label: Text('Gửi đăng ký (${_pendingRegistrations.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
              )
            : null,
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          _buildWeekSelector(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildTabShiftCentric(),
                _buildTabPendingRegistrations(),
                _buildTabApprovedSchedule(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: _pendingRegistrations.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _submitAllRegistrations,
              backgroundColor: const Color(0xFF1E3A5F),
              icon: const Icon(Icons.send, size: 18),
              label: Text('Gửi (${_pendingRegistrations.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: const Color(0xFF1E3A5F),
        unselectedLabelColor: const Color(0xFF71717A),
        indicatorColor: const Color(0xFF1E3A5F),
        indicatorWeight: 3,
        isScrollable: Responsive.isMobile(context),
        tabAlignment: Responsive.isMobile(context) ? TabAlignment.start : TabAlignment.fill,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        tabs: [
          Tab(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.work_history, size: 16),
              const SizedBox(width: 6),
              Flexible(child: Text(Responsive.isMobile(context) ? 'Theo ca' : _l10n.byShift, overflow: TextOverflow.ellipsis)),
            ]),
          ),
          Tab(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.hourglass_empty, size: 16),
              const SizedBox(width: 6),
              Flexible(child: Text(Responsive.isMobile(context) ? 'Chờ duyệt' : _l10n.pendingSchedule, overflow: TextOverflow.ellipsis)),
              if (_pendingRegistrations.isNotEmpty || _registrations.where((r) => r.status == ScheduleRegistrationStatus.pending).isNotEmpty) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_pendingRegistrations.length + _registrations.where((r) => r.status == ScheduleRegistrationStatus.pending).length}',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ]),
          ),
          Tab(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_circle, size: 16),
              const SizedBox(width: 6),
              Flexible(child: Text(Responsive.isMobile(context) ? 'Đã duyệt' : _l10n.approvedSchedule, overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildTabShiftCentric() {
    final canExport = Provider.of<PermissionProvider>(context, listen: false).canExport('WorkSchedule');
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCopyScheduleToolbar(),
          _buildManagerActionToolbar(),
          if (canExport)
            _buildExportBar(
              onExportExcel: _exportShiftCentricExcel,
              onExportPng: _exportShiftCentricPng,
            ),
          // Interactive grid (user sees this)
          _buildShiftCentricTable(),
          // Manager grid legend
          Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE4E4E7)),
            ),
            child: Wrap(
              spacing: 12, runSpacing: 6,
              children: [
                _buildLegendDot(const Color(0xFF1E3A5F), 'Đã xếp lịch'),
                _buildLegendDot(const Color(0xFF059669), 'Đã duyệt'),
                _buildLegendDot(const Color(0xFFD97706), 'Chờ duyệt'),
                _buildLegendDot(const Color(0xFF8B5CF6), 'Chưa gửi'),
                if (_staffingQuotas.isNotEmpty) ...[
                  _buildLegendDot(const Color(0xFFEF4444), 'Thiếu nhân sự'),
                  _buildLegendDot(const Color(0xFFF59E0B), 'Vượt định mức'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabPendingRegistrations() {
    final canExport = Provider.of<PermissionProvider>(context, listen: false).canExport('WorkSchedule');
    final canApprove = Provider.of<PermissionProvider>(context, listen: false).canView('ScheduleApproval');
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCopyScheduleToolbar(),
          if (canApprove)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: OutlinedButton.icon(
                onPressed: () => NavigationNotifier.goTo(NavigationNotifier.scheduleApproval),
                icon: const Icon(Icons.assignment_turned_in, size: 16, color: Color(0xFFF59E0B)),
                label: const Text('Duyệt lịch làm việc', style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFF59E0B)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ),
          if (canExport)
            _buildExportBar(
              onExportExcel: _exportScheduleTableExcel,
              onExportPng: () => _exportTableToPng(_scheduleTableKey, 'DangKyChoDuyet'),
            ),
          RepaintBoundary(
            key: _scheduleTableKey,
            child: Container(
              color: const Color(0xFFFAFAFA),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildExportHeader('ĐĂNG KÝ CHỜ DUYỆT', const Color(0xFFF59E0B)),
                _buildPendingGrid(),
                _buildCompactLegend(),
              ]),
            ),
          ),
          if (_pendingRegistrations.isNotEmpty) _buildPendingRegistrations(),
        ],
      ),
    );
  }

  Widget _buildTabApprovedSchedule() {
    final canExport = Provider.of<PermissionProvider>(context, listen: false).canExport('WorkSchedule');
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canExport)
            _buildExportBar(
              onExportExcel: _exportApprovedExcel,
              onExportPng: () => _exportTableToPng(_approvedTableKey, 'LichDaDuyet'),
            ),
          RepaintBoundary(
            key: _approvedTableKey,
            child: Container(
              color: const Color(0xFFFAFAFA),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildExportHeader('LỊCH LÀM VIỆC ĐÃ DUYỆT', const Color(0xFF1E3A5F)),
                _buildApprovedGrid(),
                _buildCompactLegend(),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportBar({VoidCallback? onExportExcel, VoidCallback? onExportPng}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (onExportExcel != null)
            OutlinedButton.icon(
              onPressed: onExportExcel,
              icon: const Icon(Icons.table_chart_outlined, size: 14),
              label: const Text('Excel', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF22C55E),
                side: const BorderSide(color: Color(0xFF22C55E)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
              ),
            ),
          if (onExportExcel != null) const SizedBox(width: 6),
          if (onExportPng != null)
            OutlinedButton.icon(
              onPressed: onExportPng,
              icon: const Icon(Icons.image_outlined, size: 14),
              label: const Text('PNG', style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF1E3A5F),
                side: const BorderSide(color: Color(0xFF1E3A5F)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
              ),
            ),
        ],
      ),
    );
  }

  // ==================== EMPLOYEE CALENDAR VIEW ====================
  Widget _buildEmployeeCalendarView() {
    final weekEnd = _selectedWeekStart.add(const Duration(days: 6));
    final weekNumber = _getWeekNumber(_selectedWeekStart);
    final dateFormat = DateFormat('dd/MM');
    final days = List.generate(7, (i) => _selectedWeekStart.add(Duration(days: i)));
    final dayLabels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    final now = DateTime.now();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final myUserId = authProvider.user?.id;

    return Column(
      children: [
        // Week navigation
        Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE4E4E7)),
          ),
          child: Row(
            children: [
              InkWell(
                onTap: _previousWeek,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.chevron_left, size: 20, color: Color(0xFF71717A)),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _goToThisWeek,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(color: const Color(0xFF1E3A5F), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.today, size: 18, color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _nextWeek,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.chevron_right, size: 20, color: Color(0xFF71717A)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    'T$weekNumber (${dateFormat.format(_selectedWeekStart)}-${dateFormat.format(weekEnd)})',
                    style: const TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.w600, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Shift-day grid table
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                // Grid table
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE4E4E7)),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                  child: Column(
                    children: [
                      // Header row: empty corner + day columns
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E3A5F).withValues(alpha: 0.06),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        ),
                        child: Row(
                          children: [
                            // Corner cell
                            Container(
                              width: 90,
                              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                              decoration: const BoxDecoration(border: Border(right: BorderSide(color: Color(0xFFE4E4E7)))),
                              child: const Text('Ca / Ngày', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1E3A5F)), textAlign: TextAlign.center),
                            ),
                            // Day columns
                            ...List.generate(7, (di) {
                              final day = days[di];
                              final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
                              final isSun = di == 6;
                              return Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isToday ? const Color(0xFF1E3A5F).withValues(alpha: 0.1) : null,
                                    border: di < 6 ? const Border(right: BorderSide(color: Color(0xFFE4E4E7))) : null,
                                  ),
                                  child: Column(
                                    children: [
                                      Text(dayLabels[di], style: TextStyle(
                                        fontSize: 11, fontWeight: FontWeight.w700,
                                        color: isToday ? const Color(0xFF1E3A5F) : (isSun ? const Color(0xFFEF4444) : const Color(0xFF71717A)),
                                      )),
                                      Text('${day.day}/${day.month}', style: TextStyle(
                                        fontSize: 10,
                                        color: isToday ? const Color(0xFF1E3A5F) : const Color(0xFF71717A),
                                      )),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      // Shift rows
                      if (_shifts.isEmpty)
                        const Padding(padding: EdgeInsets.all(24), child: Text('Chưa có ca làm việc', style: TextStyle(color: Color(0xFF71717A))))
                      else
                        ..._shifts.asMap().entries.map((entry) {
                          final si = entry.key;
                          final shift = entry.value;
                          final isLast = si == _shifts.length - 1;
                          return Container(
                            decoration: BoxDecoration(
                              border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
                            ),
                            child: Row(
                              children: [
                                // Shift name cell
                                Container(
                                  width: 90,
                                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                                  decoration: const BoxDecoration(border: Border(right: BorderSide(color: Color(0xFFE4E4E7)))),
                                  child: Column(
                                    children: [
                                      Text(shift.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF18181B)), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      Text('${_formatTime(shift.startTime)}-${_formatTime(shift.endTime)}', style: const TextStyle(fontSize: 9, color: Color(0xFF71717A)), textAlign: TextAlign.center),
                                    ],
                                  ),
                                ),
                                // Day cells for this shift
                                ...List.generate(7, (di) {
                                  final day = days[di];
                                  final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
                                  return Expanded(child: _buildEmpGridCell(shift, day, di, isToday, myUserId));
                                }),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Legend
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE4E4E7)),
                  ),
                  child: Wrap(
                    spacing: 12, runSpacing: 6,
                    children: [
                      _buildLegendDot(const Color(0xFF1E3A5F), 'Đã xếp lịch'),
                      _buildLegendDot(const Color(0xFF059669), 'Đã duyệt'),
                      _buildLegendDot(const Color(0xFFD97706), 'Chờ duyệt'),
                      _buildLegendDot(const Color(0xFFEF4444), 'Từ chối'),
                      _buildLegendDot(const Color(0xFF8B5CF6), 'Đăng ký mới'),
                    ],
                  ),
                ),

                // Submitted registrations for this week
                if (_registrations.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildEmpWeekRegistrationsList(days),
                ],

                const SizedBox(height: 80), // space for FAB
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(3), border: Border.all(color: color, width: 1.5))),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildEmpGridCell(Shift shift, DateTime day, int dayIndex, bool isToday, String? myUserId) {
    // Check if already has confirmed work schedule
    final hasSchedule = _schedules.any((s) =>
      s.shiftId == shift.id && s.date.day == day.day && s.date.month == day.month && s.date.year == day.year);
    // Check submitted registrations
    final reg = _registrations.cast<ScheduleRegistration?>().firstWhere((r) =>
      r!.shiftId == shift.id && r.date.day == day.day && r.date.month == day.month && r.date.year == day.year,
      orElse: () => null);
    // Check local pending
    final hasPendingLocal = _pendingRegistrations.any((r) =>
      r['shiftId'] == shift.id && (r['date'] as DateTime).day == day.day && (r['date'] as DateTime).month == day.month && (r['date'] as DateTime).year == day.year);

    // Determine cell state
    Color bgColor;
    Color borderColor;
    Widget? icon;

    if (hasSchedule) {
      bgColor = const Color(0xFF1E3A5F).withValues(alpha: 0.12);
      borderColor = const Color(0xFF1E3A5F);
      icon = const Icon(Icons.check, size: 18, color: Color(0xFF1E3A5F));
    } else if (reg != null && reg.status == ScheduleRegistrationStatus.approved) {
      bgColor = const Color(0xFF059669).withValues(alpha: 0.12);
      borderColor = const Color(0xFF059669);
      icon = const Icon(Icons.check_circle, size: 18, color: Color(0xFF059669));
    } else if (reg != null && reg.status == ScheduleRegistrationStatus.pending) {
      bgColor = const Color(0xFFFEF3C7);
      borderColor = const Color(0xFFD97706);
      icon = const Icon(Icons.hourglass_empty, size: 16, color: Color(0xFFD97706));
    } else if (reg != null && reg.status == ScheduleRegistrationStatus.rejected) {
      bgColor = const Color(0xFFFEE2E2);
      borderColor = const Color(0xFFEF4444);
      icon = const Icon(Icons.close, size: 16, color: Color(0xFFEF4444));
    } else if (hasPendingLocal) {
      bgColor = const Color(0xFF8B5CF6).withValues(alpha: 0.12);
      borderColor = const Color(0xFF8B5CF6);
      icon = const Icon(Icons.add_circle, size: 18, color: Color(0xFF8B5CF6));
    } else {
      bgColor = isToday ? const Color(0xFFF1F5F9) : Colors.white;
      borderColor = const Color(0xFFE4E4E7);
      icon = null;
    }

    return GestureDetector(
      onTap: () => _toggleEmpShiftDay(shift, day, hasSchedule, reg, hasPendingLocal),
      child: Container(
        height: 48,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: borderColor, width: (hasSchedule || reg != null || hasPendingLocal) ? 1.5 : 0.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(child: icon ?? Icon(Icons.add, size: 14, color: Colors.grey[300])),
      ),
    );
  }

  void _toggleEmpShiftDay(Shift shift, DateTime day, bool hasSchedule, ScheduleRegistration? reg, bool hasPendingLocal) {
    // Already confirmed by manager → show swap / leave options
    if (hasSchedule) {
      _showShiftActionSheet(shift, day, isScheduled: true);
      return;
    }
    // Already approved → show swap / leave options
    if (reg != null && reg.status == ScheduleRegistrationStatus.approved) {
      _showShiftActionSheet(shift, day, reg: reg, isApproved: true);
      return;
    }
    // Already pending on server → allow delete
    if (reg != null && reg.status == ScheduleRegistrationStatus.pending) {
      _showPendingActionSheet(shift, day, reg);
      return;
    }
    // Rejected → allow re-register or ignore
    if (reg != null && reg.status == ScheduleRegistrationStatus.rejected) {
      _showRejectedActionSheet(shift, day, reg);
      return;
    }
    // Toggle local pending registration
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (hasPendingLocal) {
      setState(() {
        _pendingRegistrations.removeWhere((r) =>
          r['shiftId'] == shift.id &&
          (r['date'] as DateTime).day == day.day &&
          (r['date'] as DateTime).month == day.month &&
          (r['date'] as DateTime).year == day.year);
      });
    } else {
      setState(() {
        _pendingRegistrations.add({
          'shiftId': shift.id,
          'employeeId': authProvider.user?.id,
          'date': DateTime(day.year, day.month, day.day),
          'isDayOff': false,
          'note': '',
        });
      });
    }
  }

  // === BOTTOM SHEET: Pending registration actions (delete) ===
  void _showPendingActionSheet(Shift shift, DateTime day, ScheduleRegistration reg) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.hourglass_empty, color: Color(0xFFD97706), size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('${shift.name} - ${day.day}/${day.month}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(8)),
                child: const Text('Chờ duyệt', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFD97706))),
              ),
            ]),
            const SizedBox(height: 16),
            _actionTile(Icons.delete_outline, 'Xóa đăng ký', 'Hủy đăng ký ca này', const Color(0xFFEF4444), () {
              Navigator.pop(ctx);
              _deleteMyRegistration(reg, shift, day);
            }),
          ]),
        ),
      ),
    );
  }

  // === BOTTOM SHEET: Rejected registration actions ===
  void _showRejectedActionSheet(Shift shift, DateTime day, ScheduleRegistration reg) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.cancel, color: Color(0xFFEF4444), size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('${shift.name} - ${day.day}/${day.month}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(8)),
                child: const Text('Từ chối', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFEF4444))),
              ),
            ]),
            if (reg.rejectionReason != null && reg.rejectionReason!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(8)),
                child: Text('Lý do: ${reg.rejectionReason}', style: const TextStyle(fontSize: 12, color: Color(0xFFEF4444))),
              ),
            ],
            const SizedBox(height: 16),
            _actionTile(Icons.delete_outline, 'Xóa đăng ký', 'Xóa đăng ký bị từ chối', const Color(0xFFEF4444), () {
              Navigator.pop(ctx);
              _deleteMyRegistration(reg, shift, day);
            }),
          ]),
        ),
      ),
    );
  }

  // === BOTTOM SHEET: Scheduled/Approved shift actions (swap, leave) ===
  void _showShiftActionSheet(Shift shift, DateTime day, {ScheduleRegistration? reg, bool isScheduled = false, bool isApproved = false}) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Row(children: [
              Icon(isScheduled ? Icons.check : Icons.check_circle, color: isScheduled ? const Color(0xFF1E3A5F) : const Color(0xFF059669), size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('${shift.name} - ${day.day}/${day.month}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isScheduled ? const Color(0xFF1E3A5F).withValues(alpha: 0.1) : const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(isScheduled ? 'Đã xếp lịch' : 'Đã duyệt', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isScheduled ? const Color(0xFF1E3A5F) : const Color(0xFF059669))),
              ),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              const SizedBox(width: 28),
              Text('${_formatTime(shift.startTime)} - ${_formatTime(shift.endTime)}', style: const TextStyle(fontSize: 12, color: Color(0xFF71717A))),
            ]),
            const SizedBox(height: 16),
            _actionTile(Icons.swap_horiz, 'Đổi ca', 'Yêu cầu đổi ca với nhân viên khác', const Color(0xFF1E3A5F), () {
              Navigator.pop(ctx);
              _showSwapDialog(shift, day);
            }),
            const SizedBox(height: 6),
            _actionTile(Icons.event_busy, 'Xin nghỉ phép', 'Gửi đơn xin nghỉ phép ca này', const Color(0xFFF59E0B), () {
              Navigator.pop(ctx);
              _showLeaveShiftDialog(shift, day);
            }),
          ]),
        ),
      ),
    );
  }

  Widget _actionTile(IconData icon, String title, String subtitle, Color color, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: color)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
      trailing: Icon(Icons.chevron_right, color: color.withValues(alpha: 0.5)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      tileColor: color.withValues(alpha: 0.03),
    );
  }

  // === DELETE REGISTRATION (employee self-service) ===
  Future<void> _deleteMyRegistration(ScheduleRegistration reg, Shift shift, DateTime day) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(children: [
          Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
          SizedBox(width: 8),
          Text('Xác nhận xóa'),
        ]),
        content: Text('Xóa đăng ký ${shift.name} ngày ${day.day}/${day.month}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await _apiService.deleteScheduleRegistration(reg.id);
    if (result['isSuccess'] == true) {
      appNotification.showSuccess(title: 'Đã xóa', message: 'Đã xóa đăng ký ${shift.name} ngày ${day.day}/${day.month}');
      _loadRegistrations();
    } else {
      appNotification.showError(title: 'Lỗi', message: result['message'] ?? 'Không thể xóa đăng ký');
    }
  }

  // === SHIFT SWAP DIALOG ===
  void _showSwapDialog(Shift shift, DateTime day) {
    String? targetEmployeeId;
    String? targetShiftId;
    final noteCtrl = TextEditingController();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    // Employees in same department (exclude self)
    final myDept = _employees.cast<Employee?>().firstWhere(
      (e) => e!.id == authProvider.user?.id || _effectiveUserId(e!) == authProvider.user?.id,
      orElse: () => null,
    )?.department;
    final availableEmployees = _employees.where((e) {
      final uid = _effectiveUserId(e);
      return uid != authProvider.user?.id && (myDept == null || e.department == myDept);
    }).toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.swap_horiz, color: Color(0xFF1E3A5F)),
            SizedBox(width: 8),
            Expanded(child: Text('Đổi ca', style: TextStyle(fontSize: 16))),
          ]),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Current shift info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(10)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Ca hiện tại:', style: TextStyle(fontSize: 11, color: Color(0xFF71717A))),
                    const SizedBox(height: 4),
                    Text('${shift.name} (${_formatTime(shift.startTime)}-${_formatTime(shift.endTime)})', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Text('Ngày ${day.day}/${day.month}/${day.year}', style: const TextStyle(fontSize: 12, color: Color(0xFF71717A))),
                  ]),
                ),
                const SizedBox(height: 14),
                // Target employee
                DropdownButtonFormField<String>(
                  value: targetEmployeeId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Nhân viên muốn đổi',
                    prefixIcon: const Icon(Icons.person, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                  items: availableEmployees.map((e) => DropdownMenuItem(
                    value: _effectiveUserId(e),
                    child: Text('${e.fullName} (${e.employeeCode})', overflow: TextOverflow.ellipsis),
                  )).toList(),
                  onChanged: (v) => setDialogState(() => targetEmployeeId = v),
                ),
                const SizedBox(height: 12),
                // Target shift (optional - can swap for a different shift)
                DropdownButtonFormField<String>(
                  value: targetShiftId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Ca muốn nhận (tùy chọn)',
                    prefixIcon: const Icon(Icons.schedule, size: 18),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Cùng ca')),
                    ..._shifts.map((s) => DropdownMenuItem(
                      value: s.id,
                      child: Text('${s.name} (${_formatTime(s.startTime)}-${_formatTime(s.endTime)})'),
                    )),
                  ],
                  onChanged: (v) => setDialogState(() => targetShiftId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(
                    labelText: 'Ghi chú',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton.icon(
              onPressed: targetEmployeeId == null ? null : () async {
                Navigator.pop(ctx);
                await _submitShiftSwap(
                  shift: shift,
                  day: day,
                  targetEmployeeId: targetEmployeeId!,
                  targetShiftId: targetShiftId,
                  note: noteCtrl.text.trim(),
                );
              },
              icon: const Icon(Icons.send, size: 16),
              label: const Text('Gửi yêu cầu'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F)),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _submitShiftSwap({required Shift shift, required DateTime day, required String targetEmployeeId, String? targetShiftId, required String note}) async {
    final data = {
      'sourceShiftId': shift.id,
      'sourceDate': DateTime(day.year, day.month, day.day).toIso8601String(),
      'targetEmployeeUserId': targetEmployeeId,
      if (targetShiftId != null) 'targetShiftId': targetShiftId,
      'targetDate': DateTime(day.year, day.month, day.day).toIso8601String(),
      if (note.isNotEmpty) 'note': note,
    };

    final result = await _apiService.createShiftSwap(data);
    if (result['isSuccess'] == true) {
      appNotification.showSuccess(title: 'Đã gửi', message: 'Yêu cầu đổi ca đã được gửi đến nhân viên');
    } else {
      appNotification.showError(title: 'Lỗi', message: result['message'] ?? 'Không thể gửi yêu cầu đổi ca');
    }
  }

  // === LEAVE REQUEST PER SHIFT DIALOG ===
  void _showLeaveShiftDialog(Shift shift, DateTime day) {
    int selectedType = 0;
    final reasonCtrl = TextEditingController();
    
    final leaveTypes = [
      (0, 'Phép năm', Icons.beach_access_rounded, Colors.teal),
      (2, 'Việc riêng có lương', Icons.paid_rounded, Colors.blue),
      (3, 'Việc riêng không lương', Icons.money_off_rounded, Colors.amber),
      (4, 'Ốm đau', Icons.local_hospital_rounded, Colors.red),
      (6, 'Nghỉ bù', Icons.swap_horiz_rounded, Colors.indigo),
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.event_busy, color: Color(0xFFF59E0B)),
            SizedBox(width: 8),
            Expanded(child: Text('Xin nghỉ phép', style: TextStyle(fontSize: 16))),
          ]),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Shift info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(10)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Nghỉ phép cho:', style: TextStyle(fontSize: 11, color: Color(0xFF71717A))),
                    const SizedBox(height: 4),
                    Text('${shift.name} (${_formatTime(shift.startTime)}-${_formatTime(shift.endTime)})', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Text('Ngày ${day.day}/${day.month}/${day.year}', style: const TextStyle(fontSize: 12, color: Color(0xFF71717A))),
                  ]),
                ),
                const SizedBox(height: 14),
                // Leave type chips
                Wrap(spacing: 6, runSpacing: 6, children: leaveTypes.map((t) {
                  final isSelected = selectedType == t.$1;
                  return ChoiceChip(
                    label: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(t.$3, size: 14, color: isSelected ? Colors.white : t.$4),
                      const SizedBox(width: 4),
                      Text(t.$2, style: TextStyle(fontSize: 11, color: isSelected ? Colors.white : t.$4)),
                    ]),
                    selected: isSelected,
                    selectedColor: t.$4,
                    backgroundColor: t.$4.withValues(alpha: 0.08),
                    side: BorderSide(color: t.$4.withValues(alpha: isSelected ? 1 : 0.3)),
                    onSelected: (_) => setDialogState(() => selectedType = t.$1),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  );
                }).toList()),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  decoration: InputDecoration(
                    labelText: 'Lý do',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                await _submitLeaveForShift(
                  shift: shift,
                  day: day,
                  type: selectedType,
                  reason: reasonCtrl.text.trim(),
                );
              },
              icon: const Icon(Icons.send, size: 16),
              label: const Text('Gửi đơn'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _submitLeaveForShift({required Shift shift, required DateTime day, required int type, required String reason}) async {
    final result = await _apiService.createLeave(
      shiftIds: [shift.id],
      startDate: DateTime(day.year, day.month, day.day),
      endDate: DateTime(day.year, day.month, day.day),
      type: type,
      reason: reason.isNotEmpty ? reason : null,
    );

    if (result['isSuccess'] == true) {
      appNotification.showSuccess(title: 'Đã gửi', message: 'Đơn nghỉ phép ${shift.name} ngày ${day.day}/${day.month} đã được gửi');
    } else {
      appNotification.showError(title: 'Lỗi', message: result['message'] ?? 'Không thể gửi đơn nghỉ phép');
    }
  }

  Widget _buildEmpWeekRegistrationsList(List<DateTime> days) {
    final weekStart = DateTime(_selectedWeekStart.year, _selectedWeekStart.month, _selectedWeekStart.day);
    final weekEndDate = weekStart.add(const Duration(days: 6));
    final weekRegs = _registrations.where((r) {
      final d = DateTime(r.date.year, r.date.month, r.date.day);
      return !d.isBefore(weekStart) && !d.isAfter(weekEndDate);
    }).toList()..sort((a, b) => a.date.compareTo(b.date));

    if (weekRegs.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Đăng ký tuần này (${weekRegs.length})', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF18181B))),
          const Divider(height: 12),
          ...weekRegs.map((reg) {
            final shift = reg.shiftId != null ? _shifts.cast<Shift?>().firstWhere((s) => s!.id == reg.shiftId, orElse: () => null) : null;
            Color statusColor;
            String statusText;
            IconData statusIcon;
            switch (reg.status) {
              case ScheduleRegistrationStatus.approved: statusColor = const Color(0xFF059669); statusText = 'Đã duyệt'; statusIcon = Icons.check_circle; break;
              case ScheduleRegistrationStatus.rejected: statusColor = const Color(0xFFEF4444); statusText = 'Từ chối'; statusIcon = Icons.cancel; break;
              default: statusColor = const Color(0xFFD97706); statusText = 'Chờ duyệt'; statusIcon = Icons.hourglass_empty;
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(statusIcon, size: 16, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${DateFormat('E dd/MM', 'vi').format(reg.date)} - ${shift?.name ?? (reg.isDayOff ? 'Nghỉ' : 'Ca')}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF18181B)),
                    ),
                  ),
                  // Action buttons based on status
                  if (reg.status == ScheduleRegistrationStatus.pending && shift != null) ...[
                    InkWell(
                      onTap: () => _deleteMyRegistration(reg, shift, reg.date),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(6)),
                        child: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFEF4444)),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (reg.status == ScheduleRegistrationStatus.rejected && shift != null) ...[
                    InkWell(
                      onTap: () => _deleteMyRegistration(reg, shift, reg.date),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(6)),
                        child: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFEF4444)),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (reg.status == ScheduleRegistrationStatus.approved && shift != null) ...[
                    InkWell(
                      onTap: () => _showSwapDialog(shift, reg.date),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: const Color(0xFF1E3A5F).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                        child: const Icon(Icons.swap_horiz, size: 14, color: Color(0xFF1E3A5F)),
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => _showLeaveShiftDialog(shift, reg.date),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(6)),
                        child: const Icon(Icons.event_busy, size: 14, color: Color(0xFFF59E0B)),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text(statusText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildWeekSelector() {
    final weekEnd = _selectedWeekStart.add(const Duration(days: 6));
    final weekNumber = _getWeekNumber(_selectedWeekStart);
    final dateFormat = DateFormat('dd/MM');
    final isMobile = Responsive.isMobile(context);

    final navRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton.icon(
          onPressed: _previousWeek,
          icon: const Icon(Icons.chevron_left, size: 18),
          label: isMobile ? const SizedBox.shrink() : Text(_l10n.prevWeek),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF71717A),
            side: const BorderSide(color: Color(0xFFE4E4E7)),
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12, vertical: 8),
            minimumSize: Size.zero,
          ),
        ),
        const SizedBox(width: 6),
        ElevatedButton.icon(
          onPressed: _goToThisWeek,
          icon: const Icon(Icons.today, size: 16),
          label: isMobile ? const SizedBox.shrink() : Text(_l10n.thisWeek),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E3A5F),
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 16, vertical: 8),
            minimumSize: Size.zero,
          ),
        ),
        const SizedBox(width: 6),
        OutlinedButton.icon(
          onPressed: _nextWeek,
          icon: isMobile ? const SizedBox.shrink() : Text(_l10n.nextWeek),
          label: const Icon(Icons.chevron_right, size: 18),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF71717A),
            side: const BorderSide(color: Color(0xFFE4E4E7)),
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 8 : 12, vertical: 8),
            minimumSize: Size.zero,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isMobile
                ? 'T$weekNumber (${dateFormat.format(_selectedWeekStart)}-${dateFormat.format(weekEnd)})'
                : 'Tuần $weekNumber (${dateFormat.format(_selectedWeekStart)} - ${dateFormat.format(weekEnd)})',
              style: const TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.w600, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );

    final deptDropdown = DropdownButtonFormField<String>(
      value: _selectedDepartment,
      isExpanded: true,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
        prefixIcon: const Icon(Icons.business, size: 16, color: Color(0xFF71717A)),
        isDense: true,
      ),
      hint: Text(_l10n.department, style: const TextStyle(fontSize: 13)),
      style: const TextStyle(color: Color(0xFF18181B), fontSize: 13),
      items: [
        DropdownMenuItem<String>(value: null, child: Text(_l10n.allDepartments)),
        ..._departments.map((d) => DropdownMenuItem<String>(
          value: d['name']?.toString() ?? '',
          child: Text(d['name']?.toString() ?? '', overflow: TextOverflow.ellipsis),
        )),
      ],
      onChanged: (value) {
        setState(() { _selectedDepartment = value; _selectedEmployeeId = null; });
        _loadSchedules();
        _loadRegistrations();
      },
    );
    final empDropdown = DropdownButtonFormField<String>(
      value: _selectedEmployeeId,
      isExpanded: true,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
        prefixIcon: const Icon(Icons.person_search, size: 16, color: Color(0xFF71717A)),
        isDense: true,
      ),
      hint: Text(_l10n.employee, style: const TextStyle(fontSize: 13)),
      style: const TextStyle(color: Color(0xFF18181B), fontSize: 13),
      items: [
        DropdownMenuItem<String>(value: null, child: Text(_l10n.allEmployees)),
        ..._filteredEmployees.map((e) => DropdownMenuItem<String>(
          value: _effectiveUserId(e),
          child: Text(e.fullName, overflow: TextOverflow.ellipsis),
        )),
      ],
      onChanged: (value) {
        setState(() => _selectedEmployeeId = value);
        _loadSchedules();
        _loadRegistrations();
      },
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: isMobile
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: navRow),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => setState(() => _showMobileFilters = !_showMobileFilters),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      height: 36,
                      width: 36,
                      decoration: BoxDecoration(
                        color: _showMobileFilters ? const Color(0xFF1E3A5F).withValues(alpha: 0.1) : const Color(0xFFFAFAFA),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _showMobileFilters ? const Color(0xFF1E3A5F).withValues(alpha: 0.3) : const Color(0xFFE4E4E7)),
                      ),
                      child: Stack(
                        children: [
                          Center(child: Icon(_showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined, size: 18, color: _showMobileFilters ? const Color(0xFF1E3A5F) : Colors.grey.shade600)),
                          if (_selectedDepartment != null || _selectedEmployeeId != null)
                            Positioned(top: 4, right: 4, child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_showMobileFilters) ...[              const SizedBox(height: 8),
              Row(children: [Expanded(child: deptDropdown), const SizedBox(width: 8), Expanded(child: empDropdown)]),
              ],
            ],
          )
        : Row(
            children: [
              navRow,
              const Spacer(),
              SizedBox(width: 200, child: deptDropdown),
              const SizedBox(width: 8),
              SizedBox(width: 220, child: empDropdown),
            ],
          ),
    );
  }

  Widget _buildCopyScheduleToolbar() {
    final isMobile = Responsive.isMobile(context);
    final buttons = [
      _buildCopyButton(icon: Icons.today, label: _l10n.copyDay, color: const Color(0xFF1E3A5F), onTap: _showCopyDayDialog),
      _buildCopyButton(icon: Icons.date_range, label: _l10n.copyWeek, color: const Color(0xFF1E3A5F), onTap: _showCopyWeekDialog),
      _buildCopyButton(icon: Icons.calendar_month, label: _l10n.copyMonth, color: const Color(0xFF0F2340), onTap: _showCopyMonthDialog),
    ];
    final helpBtn = InkWell(
      onTap: _showScheduleGuide,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFB923C).withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.help_outline, size: 16, color: Color(0xFFFB923C)),
            SizedBox(width: 6),
            Text('Hướng dẫn', style: TextStyle(color: Color(0xFFFB923C), fontWeight: FontWeight.w600, fontSize: 12)),
          ],
        ),
      ),
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: isMobile
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Icon(Icons.copy_all, size: 16, color: Color(0xFF1E3A5F)),
                const SizedBox(width: 6),
                ...buttons.expand((b) => [b, const SizedBox(width: 6)]),
                helpBtn,
              ],
            ),
          )
        : Row(
            children: [
              const Icon(Icons.copy_all, size: 18, color: Color(0xFF1E3A5F)),
              const SizedBox(width: 8),
              Text(_l10n.copySchedule, style: const TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(width: 12),
              ...buttons.expand((b) => [b, const SizedBox(width: 8)]),
              const Spacer(),
              helpBtn,
            ],
          ),
    );
  }

  Widget _buildManagerActionToolbar() {
    final isMobile = Responsive.isMobile(context);
    final actionButtons = [
      _buildCopyButton(
        icon: Icons.notifications_active,
        label: 'Nhắc đăng ký',
        color: const Color(0xFFD97706),
        onTap: _showSendReminderDialog,
      ),
      _buildCopyButton(
        icon: Icons.group_add,
        label: 'Yêu cầu bổ sung ca',
        color: const Color(0xFF059669),
        onTap: _showRequestCoverageDialog,
      ),
      _buildCopyButton(
        icon: Icons.tune,
        label: 'Định mức nhân sự',
        color: const Color(0xFF7C3AED),
        onTap: _showStaffingQuotaDialog,
      ),
    ];
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: isMobile
        ? SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Icon(Icons.manage_accounts, size: 16, color: Color(0xFF1E3A5F)),
                const SizedBox(width: 6),
                ...actionButtons.expand((b) => [b, const SizedBox(width: 6)]),
              ],
            ),
          )
        : Row(
            children: [
              const Icon(Icons.manage_accounts, size: 18, color: Color(0xFF1E3A5F)),
              const SizedBox(width: 8),
              const Text('Quản lý', style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(width: 12),
              ...actionButtons.expand((b) => [b, const SizedBox(width: 8)]),
            ],
          ),
    );
  }

  Widget _buildCopyButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
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
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  // ==================== COPY DAY SCHEDULE ====================
  void _showCopyDayDialog() {
    DateTime sourceDate = DateTime.now();
    List<DateTime> targetDates = [];
    List<String> selectedEmployeeIds = [];
    bool applyToAllEmployees = true;
    DateTime calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.today, color: Color(0xFF1E3A5F)),
                SizedBox(width: 8),
                Text('Sao chép lịch ngày', style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: Responsive.dialogWidth(context),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Sao chép lịch từ một ngày sang các ngày khác.', style: TextStyle(color: Color(0xFF71717A), fontSize: 13)),
                    const SizedBox(height: 16),
                    // Source date picker
                    Text(_l10n.sourceDate, style: const TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: sourceDate,
                          firstDate: DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) setDialogState(() => sourceDate = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE4E4E7)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 16, color: Color(0xFF71717A)),
                            const SizedBox(width: 8),
                            Text(DateFormat('dd/MM/yyyy (EEEE)', 'vi').format(sourceDate), style: const TextStyle(color: Color(0xFF18181B))),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Target dates - inline calendar
                    Row(
                      children: [
                        Text(_l10n.targetDate, style: const TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.w600)),
                        const Spacer(),
                        if (targetDates.isNotEmpty)
                          TextButton(
                            onPressed: () => setDialogState(() => targetDates.clear()),
                            child: Text('Xóa tất cả (${targetDates.length})', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildInlineCalendar(calendarMonth, targetDates, setDialogState, (m) => setDialogState(() => calendarMonth = m)),
                    if (targetDates.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: (List.of(targetDates)..sort()).map((d) => Chip(
                          backgroundColor: const Color(0xFFEFF6FF),
                          label: Text(DateFormat('dd/MM (EEE)', 'vi').format(d), style: const TextStyle(fontSize: 11, color: Color(0xFF18181B))),
                          deleteIcon: const Icon(Icons.close, size: 14),
                          onDeleted: () => setDialogState(() => targetDates.remove(d)),
                        )).toList(),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // Employee selection
                    _buildEmployeeMultiSelect(
                      applyToAll: applyToAllEmployees,
                      selectedIds: selectedEmployeeIds,
                      activeColor: const Color(0xFF1E3A5F),
                      onToggleAll: (v) => setDialogState(() {
                        applyToAllEmployees = v;
                        if (v) selectedEmployeeIds.clear();
                      }),
                      onToggleEmployee: (id, checked) => setDialogState(() {
                        if (checked) { selectedEmployeeIds.add(id); }
                        else { selectedEmployeeIds.remove(id); }
                      }),
                      onSelectAllEmployees: () => setDialogState(() {
                        selectedEmployeeIds = _employees.map((e) => _effectiveUserId(e)).toList();
                      }),
                      onDeselectAllEmployees: () => setDialogState(() => selectedEmployeeIds.clear()),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_l10n.cancel, style: const TextStyle(color: Color(0xFF71717A))),
              ),
              ElevatedButton.icon(
                onPressed: targetDates.isEmpty || (!applyToAllEmployees && selectedEmployeeIds.isEmpty)
                    ? null
                    : () {
                        Navigator.pop(context);
                        _executeCopyDay(sourceDate, targetDates, applyToAllEmployees ? null : selectedEmployeeIds);
                      },
                icon: const Icon(Icons.content_copy, size: 16),
                label: const Text('Sao chép'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F), foregroundColor: Colors.white),
              ),
            ],
          );
        },
      ),
    );
  }

  // Inline calendar widget for multi-date selection
  Widget _buildInlineCalendar(DateTime calendarMonth, List<DateTime> selectedDates, void Function(void Function()) setDialogState, void Function(DateTime) onMonthChanged) {
    final firstDay = DateTime(calendarMonth.year, calendarMonth.month, 1);
    final lastDay = DateTime(calendarMonth.year, calendarMonth.month + 1, 0);
    final startWeekday = firstDay.weekday; // 1=Monday
    final daysInMonth = lastDay.day;
    final dayNames = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    final today = DateTime.now();

    List<Widget> weekRows = [];
    // Build rows
    int dayCounter = 1;
    for (int row = 0; row < 6 && dayCounter <= daysInMonth; row++) {
      List<Widget> cells = [];
      for (int col = 0; col < 7; col++) {
        if (row == 0 && col < startWeekday - 1 || dayCounter > daysInMonth) {
          cells.add(const Expanded(child: SizedBox(height: 36)));
        } else {
          final day = dayCounter;
          final date = DateTime(calendarMonth.year, calendarMonth.month, day);
          final isSelected = selectedDates.any((d) => d.year == date.year && d.month == date.month && d.day == date.day);
          final isToday = date.year == today.year && date.month == today.month && date.day == today.day;
          cells.add(Expanded(
            child: GestureDetector(
              onTap: () => setDialogState(() {
                if (isSelected) {
                  selectedDates.removeWhere((d) => d.year == date.year && d.month == date.month && d.day == date.day);
                } else {
                  selectedDates.add(date);
                }
              }),
              child: Container(
                height: 36,
                margin: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF1E3A5F) : (isToday ? const Color(0xFFEFF6FF) : null),
                  borderRadius: BorderRadius.circular(6),
                  border: isToday && !isSelected ? Border.all(color: const Color(0xFF1E3A5F), width: 1) : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$day',
                  style: TextStyle(
                    color: isSelected ? Colors.white : (col == 6 ? const Color(0xFFEF4444) : const Color(0xFF18181B)),
                    fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ));
          dayCounter++;
        }
      }
      weekRows.add(Row(children: cells));
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Column(
        children: [
          // Month navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => onMonthChanged(DateTime(calendarMonth.year, calendarMonth.month - 1)),
                icon: const Icon(Icons.chevron_left, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              Text(
                'Tháng ${calendarMonth.month}/${calendarMonth.year}',
                style: const TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold, fontSize: 14),
              ),
              IconButton(
                onPressed: () => onMonthChanged(DateTime(calendarMonth.year, calendarMonth.month + 1)),
                icon: const Icon(Icons.chevron_right, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Day names header
          Row(
            children: dayNames.map((d) => Expanded(
              child: Center(child: Text(d, style: TextStyle(color: d == 'CN' ? const Color(0xFFEF4444) : const Color(0xFF71717A), fontSize: 11, fontWeight: FontWeight.w600))),
            )).toList(),
          ),
          const SizedBox(height: 4),
          ...weekRows,
        ],
      ),
    );
  }

  // Shared employee multi-select widget
  Widget _buildEmployeeMultiSelect({
    required bool applyToAll,
    required List<String> selectedIds,
    required Color activeColor,
    required void Function(bool) onToggleAll,
    required void Function(String id, bool checked) onToggleEmployee,
    required VoidCallback onSelectAllEmployees,
    required VoidCallback onDeselectAllEmployees,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: Text(_l10n.applyToAll, style: const TextStyle(color: Color(0xFF18181B), fontSize: 13)),
          value: applyToAll,
          onChanged: onToggleAll,
          activeThumbColor: activeColor,
          contentPadding: EdgeInsets.zero,
        ),
        if (!applyToAll) ...[
          Row(
            children: [
              const Text('Chọn nhân viên:', style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.w600, fontSize: 13)),
              const Spacer(),
              TextButton(
                onPressed: onSelectAllEmployees,
                child: Text(_l10n.selectAll, style: const TextStyle(fontSize: 11)),
              ),
              TextButton(
                onPressed: onDeselectAllEmployees,
                child: Text(_l10n.deselectAll, style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444))),
              ),
            ],
          ),
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE4E4E7)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _employees.length,
              itemBuilder: (context, index) {
                final employee = _employees[index];
                final effId = _effectiveUserId(employee);
                final isChecked = selectedIds.contains(effId);
                return CheckboxListTile(
                  value: isChecked,
                  onChanged: (v) => onToggleEmployee(effId, v ?? false),
                  title: Text(employee.fullName, style: const TextStyle(fontSize: 13)),
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: activeColor,
                );
              },
            ),
          ),
          if (selectedIds.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Đã chọn ${selectedIds.length}/${_employees.length} nhân viên', style: TextStyle(color: activeColor, fontSize: 11, fontWeight: FontWeight.w500)),
            ),
        ],
      ],
    );
  }

  Future<void> _executeCopyDay(DateTime sourceDate, List<DateTime> targetDates, List<String>? employeeIds) async {
    setState(() => _isLoading = true);
    try {
    final employees = employeeIds != null
        ? _employees.where((e) => employeeIds.contains(_effectiveUserId(e))).toList()
        : _employees;

    // Fetch source day data from API to ensure we have it even if it's outside current week
    final srcResult = await _apiService.getWorkSchedules(fromDate: sourceDate, toDate: sourceDate, pageSize: 500);
    List<WorkSchedule> srcSchedules = [];
    if (srcResult['isSuccess'] == true && srcResult['data'] != null) {
      final data = srcResult['data'];
      final items = data is List ? data : (data['items'] ?? []);
      srcSchedules = (items as List).map((s) => WorkSchedule.fromJson(s)).toList();
    }
    final srcRegResult = await _apiService.getScheduleRegistrations(fromDate: sourceDate, toDate: sourceDate, pageSize: 500);
    List<ScheduleRegistration> srcRegs = [];
    if (srcRegResult['isSuccess'] == true && srcRegResult['data'] != null) {
      final data = srcRegResult['data'];
      final items = data is List ? data : (data['items'] ?? []);
      srcRegs = (items as List).map((r) => ScheduleRegistration.fromJson(r)).toList();
    }

    int addedCount = 0;
    for (final employee in employees) {
      final effId = _effectiveUserId(employee);
      final daySchedules = srcSchedules.where((s) =>
          s.employeeUserId == effId && s.date.day == sourceDate.day && s.date.month == sourceDate.month && s.date.year == sourceDate.year).toList();
      final dayRegs = srcRegs.where((r) =>
          r.employeeUserId == effId && r.date.day == sourceDate.day && r.date.month == sourceDate.month && r.date.year == sourceDate.year &&
          r.status != ScheduleRegistrationStatus.rejected).toList();

      List<Map<String, dynamic>> sourceItems = [];
      if (daySchedules.isNotEmpty) {
        for (final s in daySchedules) {
          sourceItems.add({'shiftId': s.shiftId, 'isDayOff': s.isDayOff, 'note': s.note});
        }
      } else if (dayRegs.isNotEmpty) {
        for (final r in dayRegs) {
          sourceItems.add({'shiftId': r.shiftId, 'isDayOff': r.isDayOff, 'note': r.note});
        }
      }

      if (sourceItems.isEmpty) continue;

      for (final targetDate in targetDates) {
        for (final item in sourceItems) {
          _addPendingRegistration(effId, targetDate, item['isDayOff'] == true ? null : item['shiftId'], item['isDayOff'] ?? false, item['note']);
          addedCount++;
        }
      }
    }

    if (addedCount > 0) {
      appNotification.showSuccess(
        title: _l10n.copySuccess,
        message: 'Đã thêm $addedCount đăng ký vào danh sách chờ gửi',
      );
      // Navigate to target week
      final firstTarget = (List.of(targetDates)..sort()).first;
      setState(() => _selectedWeekStart = _getWeekStart(firstTarget));
      await _loadSchedules();
      await _loadRegistrations();
    } else {
      appNotification.showWarning(
        title: 'Không có dữ liệu',
        message: 'Ngày nguồn không có lịch để sao chép',
      );
    }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ==================== COPY WEEK SCHEDULE ====================
  void _showCopyWeekDialog() {
    DateTime sourceWeekStart = _selectedWeekStart;
    DateTime targetWeekStart = _selectedWeekStart.add(const Duration(days: 7));
    int numberOfWeeks = 1;
    List<String> selectedEmployeeIds = [];
    bool applyToAllEmployees = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final sourceWeekEnd = sourceWeekStart.add(const Duration(days: 6));
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.date_range, color: Color(0xFF1E3A5F)),
                SizedBox(width: 8),
                Text('Sao chép lịch tuần', style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: Responsive.dialogWidth(context),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Sao chép toàn bộ lịch của một tuần sang các tuần tiếp theo.',
                        style: TextStyle(color: Color(0xFF71717A), fontSize: 13)),
                    const SizedBox(height: 16),
                    // Source week
                    const Text('Tuần nguồn:', style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: sourceWeekStart,
                          firstDate: DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            sourceWeekStart = _getWeekStart(picked);
                            targetWeekStart = sourceWeekStart.add(const Duration(days: 7));
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          border: Border.all(color: const Color(0xFF1E3A5F).withValues(alpha: 0.3)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.date_range, size: 16, color: Color(0xFF1E3A5F)),
                            const SizedBox(width: 8),
                            Text(
                              'Tuần ${_getWeekNumber(sourceWeekStart)}: ${DateFormat('dd/MM').format(sourceWeekStart)} - ${DateFormat('dd/MM/yyyy').format(sourceWeekEnd)}',
                              style: const TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Target week
                    const Text('Tuần đích bắt đầu từ:', style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: targetWeekStart,
                          firstDate: DateTime.now().subtract(const Duration(days: 365)),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) setDialogState(() => targetWeekStart = _getWeekStart(picked));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE4E4E7)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 16, color: Color(0xFF71717A)),
                            const SizedBox(width: 8),
                            Text(
                              'Tuần ${_getWeekNumber(targetWeekStart)}: ${DateFormat('dd/MM').format(targetWeekStart)} - ${DateFormat('dd/MM/yyyy').format(targetWeekStart.add(const Duration(days: 6)))}',
                              style: const TextStyle(color: Color(0xFF18181B)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Number of weeks
                    const Text('Số tuần sao chép:', style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          onPressed: numberOfWeeks > 1 ? () => setDialogState(() => numberOfWeeks--) : null,
                          icon: const Icon(Icons.remove_circle_outline),
                          color: const Color(0xFF1E3A5F),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('$numberOfWeeks tuần', style: const TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                        IconButton(
                          onPressed: numberOfWeeks < 12 ? () => setDialogState(() => numberOfWeeks++) : null,
                          icon: const Icon(Icons.add_circle_outline),
                          color: const Color(0xFF1E3A5F),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Preview
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAFAFA),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Sẽ sao chép đến:', style: TextStyle(color: Color(0xFF71717A), fontSize: 11)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: List.generate(numberOfWeeks, (i) {
                              final wStart = targetWeekStart.add(Duration(days: 7 * i));
                              return Chip(
                                backgroundColor: const Color(0xFFEFF6FF),
                                label: Text('Tuần ${_getWeekNumber(wStart)}: ${DateFormat('dd/MM').format(wStart)}', style: const TextStyle(fontSize: 10, color: Color(0xFF1E3A5F))),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Employee selection
                    _buildEmployeeMultiSelect(
                      applyToAll: applyToAllEmployees,
                      selectedIds: selectedEmployeeIds,
                      activeColor: const Color(0xFF1E3A5F),
                      onToggleAll: (v) => setDialogState(() {
                        applyToAllEmployees = v;
                        if (v) selectedEmployeeIds.clear();
                      }),
                      onToggleEmployee: (id, checked) => setDialogState(() {
                        if (checked) { selectedEmployeeIds.add(id); }
                        else { selectedEmployeeIds.remove(id); }
                      }),
                      onSelectAllEmployees: () => setDialogState(() {
                        selectedEmployeeIds = _employees.map((e) => _effectiveUserId(e)).toList();
                      }),
                      onDeselectAllEmployees: () => setDialogState(() => selectedEmployeeIds.clear()),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_l10n.cancel, style: const TextStyle(color: Color(0xFF71717A))),
              ),
              ElevatedButton.icon(
                onPressed: (!applyToAllEmployees && selectedEmployeeIds.isEmpty)
                    ? null
                    : () {
                        Navigator.pop(context);
                        _executeCopyWeek(sourceWeekStart, targetWeekStart, numberOfWeeks, applyToAllEmployees ? null : selectedEmployeeIds);
                      },
                icon: const Icon(Icons.content_copy, size: 16),
                label: const Text('Sao chép'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F), foregroundColor: Colors.white),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _executeCopyWeek(DateTime sourceWeekStart, DateTime targetWeekStart, int numberOfWeeks, List<String>? employeeIds) async {
    final fromDate = sourceWeekStart;
    final toDate = sourceWeekStart.add(const Duration(days: 6));

    // Get source week schedules
    final result = await _apiService.getWorkSchedules(fromDate: fromDate, toDate: toDate, pageSize: 500);
    List<WorkSchedule> sourceSchedules = [];
    if (result['isSuccess'] == true && result['data'] != null) {
      final data = result['data'];
      final items = data is List ? data : (data['items'] ?? []);
      sourceSchedules = (items as List).map((s) => WorkSchedule.fromJson(s)).toList();
    }

    // Also get source week registrations
    final regResult = await _apiService.getScheduleRegistrations(fromDate: fromDate, toDate: toDate, pageSize: 500);
    List<ScheduleRegistration> sourceRegs = [];
    if (regResult['isSuccess'] == true && regResult['data'] != null) {
      final data = regResult['data'];
      final items = data is List ? data : (data['items'] ?? []);
      sourceRegs = (items as List).map((r) => ScheduleRegistration.fromJson(r)).toList();
    }

    final employees = employeeIds != null
        ? _employees.where((e) => employeeIds.contains(_effectiveUserId(e))).toList()
        : _employees;

    int addedCount = 0;
    for (final employee in employees) {
      final effId = _effectiveUserId(employee);
      for (int dayIdx = 0; dayIdx < 7; dayIdx++) {
        final sourceDay = sourceWeekStart.add(Duration(days: dayIdx));
        final daySchedules = sourceSchedules.where((s) =>
            s.employeeUserId == effId && s.date.day == sourceDay.day && s.date.month == sourceDay.month && s.date.year == sourceDay.year).toList();
        final dayRegs = sourceRegs.where((r) =>
            r.employeeUserId == effId && r.date.day == sourceDay.day && r.date.month == sourceDay.month && r.date.year == sourceDay.year &&
            r.status != ScheduleRegistrationStatus.rejected).toList();

        List<Map<String, dynamic>> sourceItems = [];
        if (daySchedules.isNotEmpty) {
          for (final s in daySchedules) {
            sourceItems.add({'shiftId': s.shiftId, 'isDayOff': s.isDayOff, 'note': s.note});
          }
        } else if (dayRegs.isNotEmpty) {
          for (final r in dayRegs) {
            sourceItems.add({'shiftId': r.shiftId, 'isDayOff': r.isDayOff, 'note': r.note});
          }
        }

        if (sourceItems.isEmpty) continue;

        for (int weekIdx = 0; weekIdx < numberOfWeeks; weekIdx++) {
          final targetDay = targetWeekStart.add(Duration(days: 7 * weekIdx + dayIdx));
          for (final item in sourceItems) {
            _addPendingRegistration(effId, targetDay, item['isDayOff'] == true ? null : item['shiftId'], item['isDayOff'] ?? false, item['note']);
            addedCount++;
          }
        }
      }
    }

    if (addedCount > 0) {
      appNotification.showSuccess(title: 'Sao chép tuần thành công', message: 'Đã thêm $addedCount đăng ký vào danh sách chờ gửi');
    } else {
      appNotification.showWarning(title: 'Không có dữ liệu', message: 'Tuần nguồn không có lịch để sao chép');
    }
  }

  // ==================== COPY MONTH SCHEDULE ====================
  void _showCopyMonthDialog() {
    int sourceMonth = DateTime.now().month;
    int sourceYear = DateTime.now().year;
    int targetMonth = sourceMonth == 12 ? 1 : sourceMonth + 1;
    int targetYear = sourceMonth == 12 ? sourceYear + 1 : sourceYear;
    List<String> selectedEmployeeIds = [];
    bool applyToAllEmployees = true;

    final monthNames = ['', 'Tháng 1', 'Tháng 2', 'Tháng 3', 'Tháng 4', 'Tháng 5', 'Tháng 6',
        'Tháng 7', 'Tháng 8', 'Tháng 9', 'Tháng 10', 'Tháng 11', 'Tháng 12'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.calendar_month, color: Color(0xFF0F2340)),
                SizedBox(width: 8),
                Text('Sao chép lịch tháng', style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: Responsive.dialogWidth(context),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Sao chép lịch theo từng tuần trong tháng nguồn sang tháng đích.',
                        style: TextStyle(color: Color(0xFF71717A), fontSize: 13)),
                    const SizedBox(height: 16),
                    // Source month/year
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Tháng nguồn:', style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      initialValue: sourceMonth,
                                      decoration: InputDecoration(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        isDense: true,
                                      ),
                                      items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(monthNames[i + 1]))),
                                      onChanged: (v) => setDialogState(() => sourceMonth = v!),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 100,
                                    child: DropdownButtonFormField<int>(
                                      initialValue: sourceYear,
                                      decoration: InputDecoration(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        isDense: true,
                                      ),
                                      items: List.generate(3, (i) => DropdownMenuItem(value: DateTime.now().year - 1 + i, child: Text('${DateTime.now().year - 1 + i}'))),
                                      onChanged: (v) => setDialogState(() => sourceYear = v!),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Icon(Icons.arrow_forward, color: Color(0xFF0F2340)),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Tháng đích:', style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      initialValue: targetMonth,
                                      decoration: InputDecoration(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        isDense: true,
                                      ),
                                      items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text(monthNames[i + 1]))),
                                      onChanged: (v) => setDialogState(() => targetMonth = v!),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 100,
                                    child: DropdownButtonFormField<int>(
                                      initialValue: targetYear,
                                      decoration: InputDecoration(
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        isDense: true,
                                      ),
                                      items: List.generate(3, (i) => DropdownMenuItem(value: DateTime.now().year - 1 + i, child: Text('${DateTime.now().year - 1 + i}'))),
                                      onChanged: (v) => setDialogState(() => targetYear = v!),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Employee selection
                    _buildEmployeeMultiSelect(
                      applyToAll: applyToAllEmployees,
                      selectedIds: selectedEmployeeIds,
                      activeColor: const Color(0xFF0F2340),
                      onToggleAll: (v) => setDialogState(() {
                        applyToAllEmployees = v;
                        if (v) selectedEmployeeIds.clear();
                      }),
                      onToggleEmployee: (id, checked) => setDialogState(() {
                        if (checked) { selectedEmployeeIds.add(id); }
                        else { selectedEmployeeIds.remove(id); }
                      }),
                      onSelectAllEmployees: () => setDialogState(() {
                        selectedEmployeeIds = _employees.map((e) => _effectiveUserId(e)).toList();
                      }),
                      onDeselectAllEmployees: () => setDialogState(() => selectedEmployeeIds.clear()),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(_l10n.cancel, style: const TextStyle(color: Color(0xFF71717A))),
              ),
              ElevatedButton.icon(
                onPressed: (!applyToAllEmployees && selectedEmployeeIds.isEmpty)
                    ? null
                    : () {
                        Navigator.pop(context);
                        _executeCopyMonth(sourceMonth, sourceYear, targetMonth, targetYear, applyToAllEmployees ? null : selectedEmployeeIds);
                      },
                icon: const Icon(Icons.content_copy, size: 16),
                label: const Text('Sao chép'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F2340), foregroundColor: Colors.white),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _executeCopyMonth(int sourceMonth, int sourceYear, int targetMonth, int targetYear, List<String>? employeeIds) async {
    setState(() => _isLoading = true);
    try {
      final sourceStart = DateTime(sourceYear, sourceMonth, 1);
      final sourceEnd = DateTime(sourceYear, sourceMonth + 1, 0);
      final targetStart = DateTime(targetYear, targetMonth, 1);

      // Get all schedules for source month
      final result = await _apiService.getWorkSchedules(fromDate: sourceStart, toDate: sourceEnd, pageSize: 500);
      List<WorkSchedule> sourceSchedules = [];
      if (result['isSuccess'] == true && result['data'] != null) {
        final data = result['data'];
        final items = data is List ? data : (data['items'] ?? []);
        sourceSchedules = (items as List).map((s) => WorkSchedule.fromJson(s)).toList();
      }

      // Also get registrations for source month
      final regResult = await _apiService.getScheduleRegistrations(fromDate: sourceStart, toDate: sourceEnd, pageSize: 500);
      List<ScheduleRegistration> sourceRegs = [];
      if (regResult['isSuccess'] == true && regResult['data'] != null) {
        final data = regResult['data'];
        final items = data is List ? data : (data['items'] ?? []);
        sourceRegs = (items as List).map((r) => ScheduleRegistration.fromJson(r)).toList();
      }

      final employees = employeeIds != null
          ? _employees.where((e) => employeeIds.contains(_effectiveUserId(e))).toList()
          : _employees;

      final daysInSourceMonth = sourceEnd.day;
      final daysInTargetMonth = DateTime(targetYear, targetMonth + 1, 0).day;
      final daysToCopy = daysInSourceMonth < daysInTargetMonth ? daysInSourceMonth : daysInTargetMonth;

      int addedCount = 0;
      for (final employee in employees) {
        final effId = _effectiveUserId(employee);
        for (int dayIdx = 0; dayIdx < daysToCopy; dayIdx++) {
          final sourceDay = sourceStart.add(Duration(days: dayIdx));
          final targetDay = targetStart.add(Duration(days: dayIdx));

          final daySchedules = sourceSchedules.where((s) =>
              s.employeeUserId == effId && s.date.day == sourceDay.day && s.date.month == sourceDay.month && s.date.year == sourceDay.year).toList();
          final dayRegs = sourceRegs.where((r) =>
              r.employeeUserId == effId && r.date.day == sourceDay.day && r.date.month == sourceDay.month && r.date.year == sourceDay.year &&
              r.status != ScheduleRegistrationStatus.rejected).toList();

          List<Map<String, dynamic>> sourceItems = [];
          if (daySchedules.isNotEmpty) {
            for (final s in daySchedules) {
              sourceItems.add({'shiftId': s.shiftId, 'isDayOff': s.isDayOff, 'note': s.note});
            }
          } else if (dayRegs.isNotEmpty) {
            for (final r in dayRegs) {
              sourceItems.add({'shiftId': r.shiftId, 'isDayOff': r.isDayOff, 'note': r.note});
            }
          }

          if (sourceItems.isEmpty) continue;

          for (final item in sourceItems) {
            _addPendingRegistration(effId, targetDay, item['isDayOff'] == true ? null : item['shiftId'], item['isDayOff'] ?? false, item['note']);
            addedCount++;
          }
        }
      }

      if (addedCount > 0) {
        appNotification.showSuccess(title: 'Sao chép tháng thành công', message: 'Đã thêm $addedCount đăng ký vào danh sách chờ gửi');
        setState(() => _selectedWeekStart = _getWeekStart(targetStart));
        await _loadSchedules();
        await _loadRegistrations();
      } else {
        appNotification.showWarning(title: 'Không có dữ liệu', message: 'Tháng nguồn không có lịch để sao chép');
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ==================== HELP/GUIDE DIALOG ====================
  void _showScheduleGuide() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.menu_book, color: Color(0xFFFB923C)),
            SizedBox(width: 8),
            Text('Hướng dẫn đăng ký lịch làm việc', style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: SizedBox(
          width: Responsive.dialogWidth(context),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildGuideSection(
                  '1. Đăng ký ca làm việc',
                  Icons.edit_calendar,
                  const Color(0xFF1E3A5F),
                  [
                    'Click vào ô trống trong bảng lịch để đăng ký ca cho nhân viên.',
                    'Chọn ca làm việc hoặc loại nghỉ phép trong hộp thoại.',
                    'Đăng ký sẽ vào "Danh sách chờ gửi" (màu vàng).',
                    'Nhấn "Gửi tất cả đăng ký" để gửi duyệt.',
                  ],
                ),
                const Divider(height: 32),
                _buildGuideSection(
                  '2. Sao chép lịch ngày',
                  Icons.today,
                  const Color(0xFF1E3A5F),
                  [
                    'Chọn ngày nguồn có lịch làm việc.',
                    'Chọn một hoặc nhiều ngày đích muốn sao chép đến.',
                    'Có thể áp dụng cho tất cả hoặc một nhân viên cụ thể.',
                    'Lịch sao chép sẽ vào danh sách chờ gửi.',
                  ],
                ),
                const Divider(height: 32),
                _buildGuideSection(
                  '3. Sao chép lịch tuần',
                  Icons.date_range,
                  const Color(0xFF1E3A5F),
                  [
                    'Chọn tuần nguồn chứa lịch muốn sao chép.',
                    'Chọn tuần đích bắt đầu và số tuần muốn sao chép.',
                    'Lịch mỗi ngày (T2→T2, T3→T3,...) sẽ được sao chép tương ứng.',
                    'Hỗ trợ sao chép đến tối đa 12 tuần liên tiếp.',
                  ],
                ),
                const Divider(height: 32),
                _buildGuideSection(
                  '4. Sao chép lịch tháng',
                  Icons.calendar_month,
                  const Color(0xFF0F2340),
                  [
                    'Chọn tháng nguồn và tháng đích.',
                    'Lịch ngày 1→1, ngày 2→2,... sẽ được sao chép tương ứng.',
                    'Nếu tháng đích ít ngày hơn, các ngày thừa sẽ bị bỏ qua.',
                    'Sau khi sao chép, trang sẽ chuyển đến tuần đầu của tháng đích.',
                  ],
                ),
                const Divider(height: 32),
                _buildGuideSection(
                  '5. Trạng thái đăng ký',
                  Icons.info_outline,
                  const Color(0xFFF59E0B),
                  [
                    '🟡 Chờ gửi: Đăng ký chưa gửi (có thể xóa/sửa).',
                    '🟠 Chờ duyệt: Đã gửi, chờ quản lý duyệt.',
                    '🟢 Đã duyệt: Đăng ký được chấp nhận.',
                    '🔴 Từ chối: Đăng ký bị từ chối (xem lý do).',
                  ],
                ),
                const Divider(height: 32),
                _buildGuideSection(
                  '6. Duyệt đăng ký (cho quản lý)',
                  Icons.fact_check,
                  const Color(0xFFEF4444),
                  [
                    'Tab "Duyệt theo nhân viên": Xem và duyệt theo từng nhân viên.',
                    'Tab "Duyệt theo ca": Xem và duyệt theo từng ca làm việc.',
                    'Có thể duyệt/từ chối từng đăng ký hoặc duyệt hàng loạt.',
                    'Sử dụng bộ lọc trạng thái để nhanh chóng tìm đăng ký cần xử lý.',
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F), foregroundColor: Colors.white),
            child: const Text('Đã hiểu'),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideSection(String title, IconData icon, Color color, List<String> steps) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
        const SizedBox(height: 8),
        ...steps.map((step) => Padding(
              padding: const EdgeInsets.only(left: 28, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(color: Color(0xFF71717A))),
                  Expanded(child: Text(step, style: const TextStyle(color: Color(0xFF52525B), fontSize: 13, height: 1.4))),
                ],
              ),
            )),
      ],
    );
  }

  // ignore: unused_element
  void _showWeekPicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedWeekStart,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _selectedWeekStart = _getWeekStart(picked);
      });
      _loadSchedules();
    }
  }

  // ══════════════════════════════════════════════
  //  PENDING GRID (Tab 2) — Employee-centric, per-day status cells
  // ══════════════════════════════════════════════
  Widget _buildPendingGrid() {
    final days = List.generate(7, (i) => _selectedWeekStart.add(Duration(days: i)));
    final dayLabels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    final now = DateTime.now();
    final canEdit = Provider.of<PermissionProvider>(context, listen: false).canEdit('WorkSchedule');
    final focused = _pendingFocusedDay;

    if (focused != null) {
      return _buildPendingDayDetail(days[focused], dayLabels[focused], canEdit);
    }

    final emps = _filteredEmployees;
    // Filter employees that have any pending/local/confirmed registrations this week
    final activeEmps = emps.where((emp) {
      final eid = _effectiveUserId(emp);
      for (final day in days) {
        if (_getSchedulesForDay(eid, day).isNotEmpty) return true;
        if (_getPendingRegistrations(eid, day).isNotEmpty) return true;
        if (_getRegistrationsForDay(eid, day).isNotEmpty) return true;
      }
      return false;
    }).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Container(
                  width: 110,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                  decoration: const BoxDecoration(border: Border(right: BorderSide(color: Color(0xFFE4E4E7)))),
                  child: const Text('Nhân viên', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFA16207)), textAlign: TextAlign.center),
                ),
                ...List.generate(7, (di) {
                  final day = days[di];
                  final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
                  final isSun = di == 6;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _pendingFocusedDay = di),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: isToday ? const Color(0xFFF59E0B).withValues(alpha: 0.12) : null,
                          border: di < 6 ? const Border(right: BorderSide(color: Color(0xFFE4E4E7))) : null,
                        ),
                        child: Column(
                          children: [
                            Text(dayLabels[di], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                              color: isToday ? const Color(0xFFA16207) : (isSun ? const Color(0xFFEF4444) : const Color(0xFF71717A)))),
                            Text('${day.day}/${day.month}', style: TextStyle(fontSize: 10,
                              color: isToday ? const Color(0xFFA16207) : const Color(0xFF71717A))),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          // Employee rows
          if (activeEmps.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Chưa có đăng ký nào', style: TextStyle(color: Color(0xFF71717A)))))
          else
            ...activeEmps.asMap().entries.map((entry) {
              final emp = entry.value;
              final isLast = entry.key == activeEmps.length - 1;
              return Container(
                decoration: BoxDecoration(border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFE4E4E7)))),
                child: Row(
                  children: [
                    Container(
                      width: 110,
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                      decoration: const BoxDecoration(border: Border(right: BorderSide(color: Color(0xFFE4E4E7)))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(emp.fullName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF18181B)), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(emp.employeeCode, style: const TextStyle(fontSize: 9, color: Color(0xFF71717A))),
                        ],
                      ),
                    ),
                    ...List.generate(7, (di) {
                      final day = days[di];
                      final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
                      return Expanded(child: _buildPendingCell(emp, day, isToday, canEdit));
                    }),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildPendingCell(Employee emp, DateTime day, bool isToday, bool canEdit) {
    final eid = _effectiveUserId(emp);
    final schedules = _getSchedulesForDay(eid, day);
    final localPending = _getPendingRegistrations(eid, day);
    final submittedRegs = _getRegistrationsForDay(eid, day);
    final pendingRegs = submittedRegs.where((r) => r.status == ScheduleRegistrationStatus.pending).toList();
    final approvedRegs = submittedRegs.where((r) => r.status == ScheduleRegistrationStatus.approved).toList();
    final rejectedRegs = submittedRegs.where((r) => r.status == ScheduleRegistrationStatus.rejected).toList();

    final totalItems = schedules.length + localPending.length + pendingRegs.where((r) => schedules.every((s) => s.employeeUserId != r.employeeUserId)).length + approvedRegs.where((r) => schedules.every((s) => s.employeeUserId != r.employeeUserId)).length;

    if (totalItems == 0 && rejectedRegs.isEmpty) {
      return GestureDetector(
        onTap: canEdit ? () => _showRegisterDialog(emp, day) : null,
        child: Container(
          height: 48, margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(color: isToday ? const Color(0xFFF5F5F4) : Colors.white, borderRadius: BorderRadius.circular(4)),
          child: Center(child: Icon(Icons.add, size: 12, color: Colors.grey[300])),
        ),
      );
    }

    // Build status dots
    final dots = <Widget>[];
    if (schedules.isNotEmpty) dots.add(_statusDot(const Color(0xFF1E3A5F)));
    if (approvedRegs.isNotEmpty) dots.add(_statusDot(const Color(0xFF059669)));
    if (pendingRegs.isNotEmpty) dots.add(_statusDot(const Color(0xFFD97706)));
    if (localPending.isNotEmpty) dots.add(_statusDot(const Color(0xFF8B5CF6)));
    if (rejectedRegs.isNotEmpty) dots.add(_statusDot(const Color(0xFFEF4444)));

    // Primary color
    Color borderColor;
    Color bgColor;
    if (pendingRegs.isNotEmpty || localPending.isNotEmpty) {
      borderColor = const Color(0xFFD97706); bgColor = const Color(0xFFFEF3C7);
    } else if (schedules.isNotEmpty) {
      borderColor = const Color(0xFF1E3A5F); bgColor = const Color(0xFF1E3A5F).withValues(alpha: 0.08);
    } else if (approvedRegs.isNotEmpty) {
      borderColor = const Color(0xFF059669); bgColor = const Color(0xFF059669).withValues(alpha: 0.08);
    } else {
      borderColor = const Color(0xFFEF4444); bgColor = const Color(0xFFFEE2E2);
    }

    // Count labels
    final labels = <Widget>[];
    final confirmedCount = schedules.where((s) => !s.isDayOff).length;
    final dayOffCount = schedules.where((s) => s.isDayOff).length;
    final pendCount = pendingRegs.length + localPending.length;
    if (confirmedCount > 0) labels.add(Text('$confirmedCount ca', style: const TextStyle(fontSize: 9, color: Color(0xFF1E3A5F), fontWeight: FontWeight.w600)));
    if (dayOffCount > 0) labels.add(const Text('Nghỉ', style: TextStyle(fontSize: 9, color: Color(0xFF71717A), fontWeight: FontWeight.w600)));
    if (pendCount > 0) labels.add(Text('$pendCount chờ', style: const TextStyle(fontSize: 9, color: Color(0xFFA16207), fontWeight: FontWeight.w600)));
    if (rejectedRegs.isNotEmpty) labels.add(Text('${rejectedRegs.length} từ chối', style: const TextStyle(fontSize: 8, color: Color(0xFFEF4444))));

    return GestureDetector(
      onTap: canEdit ? () => _showRegisterDialog(emp, day) : null,
      child: Container(
        height: 48, margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(color: bgColor, border: Border.all(color: borderColor, width: 1.2), borderRadius: BorderRadius.circular(4)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ...labels,
            if (dots.isNotEmpty) Row(mainAxisAlignment: MainAxisAlignment.center, children: dots),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingDayDetail(DateTime day, String dayLabel, bool canEdit) {
    final dateStr = DateFormat('EEEE dd/MM/yyyy', 'vi').format(day);
    final emps = _filteredEmployees;
    // Group data per employee for this day
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: () => setState(() => _pendingFocusedDay = null),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE4E4E7))),
                    child: const Icon(Icons.arrow_back, size: 18, color: Color(0xFFA16207)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text('$dayLabel — $dateStr', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFA16207)))),
              ],
            ),
          ),
          // Employee rows for this day
          ...() {
            final rows = <Widget>[];
            for (final emp in emps) {
              final eid = _effectiveUserId(emp);
              final schedules = _getSchedulesForDay(eid, day);
              final localPending = _getPendingRegistrations(eid, day);
              final submittedRegs = _getRegistrationsForDay(eid, day);
              if (schedules.isEmpty && localPending.isEmpty && submittedRegs.isEmpty) continue;

              final chips = <Widget>[];
              for (final ws in schedules) {
                if (ws.isDayOff) {
                  chips.add(_empChip('Nghỉ', const Color(0xFF71717A), Icons.nightlight_round));
                } else {
                  final shift = _shifts.firstWhere((s) => s.id == ws.shiftId, orElse: () => Shift(id: '', name: 'Ca', code: '', startTime: '', endTime: '', isActive: true, createdAt: DateTime.now()));
                  chips.add(_empChip(shift.name, const Color(0xFF1E3A5F), Icons.check_circle));
                }
              }
              for (final r in submittedRegs) {
                if (schedules.any((s) => s.shiftId == r.shiftId && s.employeeUserId == r.employeeUserId)) continue;
                Color c; IconData ic; String suffix;
                switch (r.status) {
                  case ScheduleRegistrationStatus.pending: c = const Color(0xFFD97706); ic = Icons.hourglass_empty; suffix = ' (chờ)'; break;
                  case ScheduleRegistrationStatus.approved: c = const Color(0xFF059669); ic = Icons.check_circle; suffix = ' (duyệt)'; break;
                  case ScheduleRegistrationStatus.rejected: c = const Color(0xFFEF4444); ic = Icons.cancel; suffix = ' (từ chối)'; break;
                }
                if (r.isDayOff) {
                  chips.add(_empChip('Nghỉ$suffix', c, ic));
                } else {
                  final shift = r.shiftId != null ? _shifts.firstWhere((s) => s.id == r.shiftId, orElse: () => Shift(id: '', name: 'Ca', code: '', startTime: '', endTime: '', isActive: true, createdAt: DateTime.now())) : null;
                  chips.add(_empChip('${shift?.name ?? 'Ca'}$suffix', c, ic));
                }
              }
              for (final p in localPending) {
                if (p['isDayOff'] == true) {
                  chips.add(_empChip('Nghỉ (chưa gửi)', const Color(0xFF8B5CF6), Icons.schedule_send));
                } else {
                  final shift = p['shiftId'] != null ? _shifts.firstWhere((s) => s.id == p['shiftId'], orElse: () => Shift(id: '', name: 'Ca', code: '', startTime: '', endTime: '', isActive: true, createdAt: DateTime.now())) : null;
                  chips.add(_empChip('${shift?.name ?? 'Ca'} (chưa gửi)', const Color(0xFF8B5CF6), Icons.schedule_send));
                }
              }

              rows.add(Container(
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7)))),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 120, child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(emp.fullName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF18181B))),
                        Text(emp.employeeCode, style: const TextStyle(fontSize: 10, color: Color(0xFF71717A))),
                      ],
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: Wrap(spacing: 4, runSpacing: 4, children: chips)),
                    if (canEdit)
                      InkWell(
                        onTap: () => _showRegisterDialog(emp, day),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                          child: const Icon(Icons.edit_calendar, size: 16, color: Color(0xFFA16207)),
                        ),
                      ),
                  ],
                ),
              ));
            }
            if (rows.isEmpty) return [const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Không có đăng ký', style: TextStyle(color: Color(0xFF71717A)))))];
            return rows;
          }(),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════
  //  APPROVED GRID (Tab 3) — Employee-centric, per-day approved cells
  // ══════════════════════════════════════════════
  Widget _buildApprovedGrid() {
    final days = List.generate(7, (i) => _selectedWeekStart.add(Duration(days: i)));
    final dayLabels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    final now = DateTime.now();
    final focused = _approvedFocusedDay;

    if (focused != null) {
      return _buildApprovedDayDetail(days[focused], dayLabels[focused]);
    }

    final emps = _filteredEmployees;
    // Filter employees that have confirmed/approved registrations this week
    final activeEmps = emps.where((emp) {
      final eid = _effectiveUserId(emp);
      for (final day in days) {
        if (_getSchedulesForDay(eid, day).isNotEmpty) return true;
        final regs = _getRegistrationsForDay(eid, day);
        if (regs.any((r) => r.status == ScheduleRegistrationStatus.approved)) return true;
      }
      return false;
    }).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E3A5F).withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Container(
                  width: 110,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                  decoration: const BoxDecoration(border: Border(right: BorderSide(color: Color(0xFFE4E4E7)))),
                  child: const Text('Nhân viên', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1E3A5F)), textAlign: TextAlign.center),
                ),
                ...List.generate(7, (di) {
                  final day = days[di];
                  final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
                  final isSun = di == 6;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _approvedFocusedDay = di),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: isToday ? const Color(0xFF1E3A5F).withValues(alpha: 0.12) : null,
                          border: di < 6 ? const Border(right: BorderSide(color: Color(0xFFE4E4E7))) : null,
                        ),
                        child: Column(
                          children: [
                            Text(dayLabels[di], style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                              color: isToday ? const Color(0xFF1E3A5F) : (isSun ? const Color(0xFFEF4444) : const Color(0xFF71717A)))),
                            Text('${day.day}/${day.month}', style: TextStyle(fontSize: 10,
                              color: isToday ? const Color(0xFF1E3A5F) : const Color(0xFF71717A))),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          // Employee rows
          if (activeEmps.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Chưa có lịch đã duyệt', style: TextStyle(color: Color(0xFF71717A)))))
          else
            ...activeEmps.asMap().entries.map((entry) {
              final emp = entry.value;
              final isLast = entry.key == activeEmps.length - 1;
              return Container(
                decoration: BoxDecoration(border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFE4E4E7)))),
                child: Row(
                  children: [
                    Container(
                      width: 110,
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                      decoration: const BoxDecoration(border: Border(right: BorderSide(color: Color(0xFFE4E4E7)))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(emp.fullName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF18181B)), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(emp.department ?? emp.employeeCode, style: const TextStyle(fontSize: 9, color: Color(0xFF71717A))),
                        ],
                      ),
                    ),
                    ...List.generate(7, (di) {
                      final day = days[di];
                      final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
                      return Expanded(child: _buildApprovedCell(emp, day, isToday));
                    }),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildApprovedCell(Employee emp, DateTime day, bool isToday) {
    final eid = _effectiveUserId(emp);
    final schedules = _getSchedulesForDay(eid, day);
    final approvedRegs = _getRegistrationsForDay(eid, day).where((r) => r.status == ScheduleRegistrationStatus.approved).toList();
    final uniqueApproved = approvedRegs.where((r) => schedules.every((s) => s.shiftId != r.shiftId || s.employeeUserId != r.employeeUserId)).toList();

    final totalShifts = schedules.where((s) => !s.isDayOff).length + uniqueApproved.where((r) => !r.isDayOff).length;
    final hasDayOff = schedules.any((s) => s.isDayOff) || uniqueApproved.any((r) => r.isDayOff);

    if (totalShifts == 0 && !hasDayOff) {
      return Container(
        height: 48, margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(color: isToday ? const Color(0xFFF5F5F4) : Colors.white, borderRadius: BorderRadius.circular(4)),
        child: Center(child: Text('—', style: TextStyle(color: Colors.grey[300], fontSize: 14))),
      );
    }

    // Build compact display
    final labels = <Widget>[];
    if (hasDayOff) {
      labels.add(const Text('Nghỉ', style: TextStyle(fontSize: 9, color: Color(0xFF71717A), fontWeight: FontWeight.w600)));
    }
    if (totalShifts > 0) {
      labels.add(Text('$totalShifts ca', style: const TextStyle(fontSize: 10, color: Color(0xFF1E3A5F), fontWeight: FontWeight.w700)));
    }

    return Container(
      height: 48, margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: hasDayOff && totalShifts == 0 ? const Color(0xFF71717A).withValues(alpha: 0.06) : const Color(0xFF1E3A5F).withValues(alpha: 0.08),
        border: Border.all(color: hasDayOff && totalShifts == 0 ? const Color(0xFF71717A) : const Color(0xFF1E3A5F), width: 1.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: labels,
      ),
    );
  }

  Widget _buildApprovedDayDetail(DateTime day, String dayLabel) {
    final dateStr = DateFormat('EEEE dd/MM/yyyy', 'vi').format(day);
    final emps = _filteredEmployees;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1E3A5F).withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: () => setState(() => _approvedFocusedDay = null),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE4E4E7))),
                    child: const Icon(Icons.arrow_back, size: 18, color: Color(0xFF1E3A5F)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text('$dayLabel — $dateStr', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF1E3A5F)))),
              ],
            ),
          ),
          // Group by shift
          if (_shifts.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Text('Chưa có ca', style: TextStyle(color: Color(0xFF71717A))))
          else
            ..._shifts.asMap().entries.map((entry) {
              final si = entry.key;
              final shift = entry.value;
              final isLast = si == _shifts.length - 1;
              // Get confirmed + approved for this shift on this day
              final confirmedScheds = _getSchedulesForShiftDay(shift.id, day);
              final approvedRegs = _getRegistrationsForShiftDay(shift.id, day).where((r) => r.status == ScheduleRegistrationStatus.approved).toList();
              final uniqueApprovedRegs = approvedRegs.where((r) => confirmedScheds.every((s) => s.employeeUserId != r.employeeUserId)).toList();

              final names = <Map<String, dynamic>>[];
              for (final ws in confirmedScheds) {
                final emp = _employees.firstWhere((e) => _effectiveUserId(e) == ws.employeeUserId, orElse: () => Employee.empty());
                names.add({'name': emp.fullName, 'color': const Color(0xFF1E3A5F), 'icon': Icons.check_circle, 'isDayOff': ws.isDayOff});
              }
              for (final r in uniqueApprovedRegs) {
                final emp = _employees.firstWhere((e) => _effectiveUserId(e) == r.employeeUserId, orElse: () => Employee.empty());
                names.add({'name': emp.fullName, 'color': const Color(0xFF059669), 'icon': Icons.verified, 'isDayOff': r.isDayOff});
              }

              return Container(
                decoration: BoxDecoration(border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFE4E4E7)))),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: const Color(0xFF1E3A5F).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                            child: Text(shift.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1E3A5F))),
                          ),
                          const SizedBox(width: 8),
                          Text('${_formatTime(shift.startTime)} - ${_formatTime(shift.endTime)}', style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
                          const Spacer(),
                          Text('${names.where((n) => n['isDayOff'] != true).length} NV', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF1E3A5F))),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (names.isEmpty)
                        Text('Chưa có nhân viên', style: TextStyle(fontSize: 11, color: Colors.grey[400]))
                      else
                        Wrap(
                          spacing: 4, runSpacing: 4,
                          children: names.map((n) => _empChip(
                            n['isDayOff'] == true ? '${n['name']} (Nghỉ)' : n['name'] as String,
                            n['color'] as Color,
                            n['icon'] as IconData,
                          )).toList(),
                        ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildScheduleTable() {
    final days = List.generate(7, (i) => _selectedWeekStart.add(Duration(days: i)));
    final dayNames = ['THỨ 2', 'THỨ 3', 'THỨ 4', 'THỨ 5', 'THỨ 6', 'THỨ 7', 'CHỦ NHẬT'];
    final dateFormat = DateFormat('d/M');
    final today = DateTime.now();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final allEmps = _filteredEmployees;
          final isMobile = constraints.maxWidth < 600;
          final totalPages = (allEmps.length / _schedulePageSize).ceil();
          final safePage = _schedulePage.clamp(1, totalPages == 0 ? 1 : totalPages);
          final startIdx = isMobile ? 0 : (safePage - 1) * _schedulePageSize;
          final endIdx = isMobile ? allEmps.length : (startIdx + _schedulePageSize).clamp(0, allEmps.length);
          final pageEmps = allEmps.sublist(startIdx, endIdx);
          if (isMobile) {
            return Column(children: [
              _buildMobileScheduleCards(pageEmps, days, dayNames, dateFormat),
            ]);
          }
          return Column(children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
          dataRowColor: WidgetStateProperty.all(Colors.white),
          dataRowMinHeight: 56,
          dataRowMaxHeight: 64,
          border: TableBorder.all(color: const Color(0xFFE4E4E7), width: 1),
          columns: [
            const DataColumn(
              label: Expanded(child: Text('NHÂN VIÊN', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold))),
            ),
            ...List.generate(7, (i) {
              final day = days[i];
              final isToday = day.day == today.day && day.month == today.month && day.year == today.year;
              return DataColumn(
                label: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      dayNames[i],
                      style: TextStyle(
                        color: isToday ? const Color(0xFF1E3A5F) : const Color(0xFF18181B),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      dateFormat.format(day),
                      style: TextStyle(
                        color: isToday ? const Color(0xFF1E3A5F) : const Color(0xFF71717A),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              );
            }),
            const DataColumn(
              label: Expanded(child: Text('TỔNG CA', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold))),
            ),
          ],
          rows: pageEmps.isEmpty
              ? [
                  DataRow(cells: [
                    DataCell(
                      Center(
                        child: Text('Chưa có nhân viên', style: TextStyle(color: Colors.grey[400])),
                      ),
                    ),
                    ...List.generate(8, (_) => const DataCell(Text(''))),
                  ]),
                ]
              : pageEmps.map((employee) {
                  int totalShifts = 0;
                  return DataRow(
                    cells: [
                      DataCell(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              employee.fullName.toUpperCase(),
                              style: const TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            Text(
                              employee.phone ?? employee.employeeCode,
                              style: const TextStyle(color: Color(0xFF71717A), fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      ...List.generate(7, (dayIndex) {
                        final day = days[dayIndex];
                        final effectiveId = _effectiveUserId(employee);
                        final schedules = _getSchedulesForDay(effectiveId, day);
                        final pendingRegs = _getPendingRegistrations(effectiveId, day);
                        final submittedRegs = _getRegistrationsForDay(effectiveId, day);
                        
                        // Count work shifts
                        totalShifts += schedules.where((s) => !s.isDayOff).length;
                        if (pendingRegs.isNotEmpty && pendingRegs.first['isDayOff'] != true) {
                          totalShifts += pendingRegs.length;
                        }
                        // Count approved registrations not yet in schedules
                        totalShifts += submittedRegs.where((r) => r.status == ScheduleRegistrationStatus.approved && !r.isDayOff && schedules.isEmpty).length;
                        
                        return DataCell(
                          _buildScheduleCell(employee, day, schedules, pendingRegs, submittedRegs),
                        );
                      }),
                      DataCell(
                        Center(
                          child: Text(
                            '$totalShifts',
                            style: TextStyle(
                              color: totalShifts > 0 ? const Color(0xFF1E3A5F) : Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          if (totalPages > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
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
                        value: _schedulePageSize,
                        isDense: true,
                        style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                        items: _pageSizeOptions.map((s) => DropdownMenuItem(value: s, child: Text('$s'))).toList(),
                        onChanged: (v) {
                          if (v != null) setState(() { _schedulePageSize = v; _schedulePage = 1; });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(icon: const Icon(Icons.first_page), onPressed: safePage > 1 ? () => setState(() => _schedulePage = 1) : null),
                  IconButton(icon: const Icon(Icons.chevron_left), onPressed: safePage > 1 ? () => setState(() => _schedulePage--) : null),
                  Text('Hiển thị ${(safePage - 1) * _schedulePageSize + 1}-${(safePage * _schedulePageSize).clamp(0, allEmps.length)} / ${allEmps.length} nhân viên', style: const TextStyle(fontSize: 13)),
                  IconButton(icon: const Icon(Icons.chevron_right), onPressed: safePage < totalPages ? () => setState(() => _schedulePage++) : null),
                  IconButton(icon: const Icon(Icons.last_page), onPressed: safePage < totalPages ? () => setState(() => _schedulePage = totalPages) : null),
                ],
              ),
              ),
            ),
          ]);
        },
      ),
    );
  }

  List<WorkSchedule> _getSchedulesForDay(String employeeId, DateTime day) {
    return _schedules.where(
      (s) => s.employeeUserId == employeeId &&
             s.date.day == day.day &&
             s.date.month == day.month &&
             s.date.year == day.year,
    ).toList();
  }

  List<Map<String, dynamic>> _getPendingRegistrations(String employeeId, DateTime day) {
    return _pendingRegistrations.where(
      (r) => r['employeeId'] == employeeId &&
             (r['date'] as DateTime).day == day.day &&
             (r['date'] as DateTime).month == day.month &&
             (r['date'] as DateTime).year == day.year,
    ).toList();
  }

  List<ScheduleRegistration> _getRegistrationsForDay(String employeeId, DateTime day) {
    return _registrations.where(
      (r) => r.employeeUserId == employeeId &&
             r.date.day == day.day &&
             r.date.month == day.month &&
             r.date.year == day.year,
    ).toList();
  }

  // ── Shift-day helpers (for shift-centric table) ──
  List<WorkSchedule> _getSchedulesForShiftDay(String shiftId, DateTime day) {
    return _schedules.where((s) =>
      s.shiftId == shiftId && s.date.day == day.day && s.date.month == day.month && s.date.year == day.year
    ).toList();
  }

  List<Map<String, dynamic>> _getPendingForShiftDay(String shiftId, DateTime day) {
    return _pendingRegistrations.where((r) =>
      r['shiftId'] == shiftId &&
      (r['date'] as DateTime).day == day.day &&
      (r['date'] as DateTime).month == day.month &&
      (r['date'] as DateTime).year == day.year
    ).toList();
  }

  List<ScheduleRegistration> _getRegistrationsForShiftDay(String shiftId, DateTime day) {
    return _registrations.where((r) =>
      r.shiftId == shiftId && r.date.day == day.day && r.date.month == day.month && r.date.year == day.year
    ).toList();
  }

  // ══════════════════════════════════════════════
  //  SHIFT-CENTRIC TABLE (Grid layout — tap day header to zoom)
  // ══════════════════════════════════════════════
  Widget _buildShiftCentricTable() {
    final days = List.generate(7, (i) => _selectedWeekStart.add(Duration(days: i)));
    final dayLabels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    final now = DateTime.now();
    final canEdit = Provider.of<PermissionProvider>(context, listen: false).canEdit('WorkSchedule');
    final focused = _focusedDayIndex;

    // If a day is focused, show single-day detail view
    if (focused != null) {
      return _buildSingleDayDetail(days[focused], dayLabels[focused], canEdit);
    }

    // Normal 7-day grid
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row: corner + day columns
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0891B2).withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Container(
                  width: 80,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  decoration: const BoxDecoration(border: Border(right: BorderSide(color: Color(0xFFE4E4E7)))),
                  child: const Text('Ca / Ngày', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF0891B2)), textAlign: TextAlign.center),
                ),
                ...List.generate(7, (di) {
                  final day = days[di];
                  final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
                  final isSun = di == 6;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _focusedDayIndex = di),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: isToday ? const Color(0xFF0891B2).withValues(alpha: 0.12) : null,
                          border: di < 6 ? const Border(right: BorderSide(color: Color(0xFFE4E4E7))) : null,
                        ),
                        child: Column(
                          children: [
                            Text(dayLabels[di], style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700,
                              color: isToday ? const Color(0xFF0891B2) : (isSun ? const Color(0xFFEF4444) : const Color(0xFF71717A)),
                            )),
                            Text('${day.day}/${day.month}', style: TextStyle(
                              fontSize: 10,
                              color: isToday ? const Color(0xFF0891B2) : const Color(0xFF71717A),
                            )),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          // Shift rows
          if (_shifts.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Text('Chưa có ca làm việc', style: TextStyle(color: Color(0xFF71717A))))
          else
            ..._shifts.asMap().entries.map((entry) {
              final si = entry.key;
              final shift = entry.value;
              final isLast = si == _shifts.length - 1;
              return Container(
                decoration: BoxDecoration(
                  border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
                ),
                child: Row(
                  children: [
                    // Shift name cell
                    Container(
                      width: 80,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      decoration: const BoxDecoration(border: Border(right: BorderSide(color: Color(0xFFE4E4E7)))),
                      child: Column(
                        children: [
                          Text(shift.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF18181B)), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text('${_formatTime(shift.startTime)}-${_formatTime(shift.endTime)}', style: const TextStyle(fontSize: 9, color: Color(0xFF71717A)), textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                    // Day cells for this shift
                    ...List.generate(7, (di) {
                      final day = days[di];
                      final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
                      return Expanded(child: _buildManagerGridCell(shift, day, isToday, canEdit));
                    }),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  /// Single-day detail view: shows employee names per shift for one day
  Widget _buildSingleDayDetail(DateTime day, String dayLabel, bool canEdit) {
    final dateStr = DateFormat('EEEE dd/MM/yyyy', 'vi').format(day);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with back button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0891B2).withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: () => setState(() => _focusedDayIndex = null),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE4E4E7))),
                    child: const Icon(Icons.arrow_back, size: 18, color: Color(0xFF0891B2)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('$dayLabel — $dateStr', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0891B2))),
                ),
              ],
            ),
          ),
          // Shift rows with employee names
          if (_shifts.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Text('Chưa có ca', style: TextStyle(color: Color(0xFF71717A))))
          else
            ..._shifts.asMap().entries.map((entry) {
              final si = entry.key;
              final shift = entry.value;
              final isLast = si == _shifts.length - 1;
              final schedules = _getSchedulesForShiftDay(shift.id, day);
              final pendingLocal = _getPendingForShiftDay(shift.id, day);
              final submittedRegs = _getRegistrationsForShiftDay(shift.id, day);
              final uniqueRegs = submittedRegs.where((r) => schedules.every((s) => s.employeeUserId != r.employeeUserId)).toList();

              return Container(
                decoration: BoxDecoration(border: isLast ? null : const Border(bottom: BorderSide(color: Color(0xFFE4E4E7)))),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Shift header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: const Color(0xFF0891B2).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                            child: Text(shift.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0891B2))),
                          ),
                          const SizedBox(width: 8),
                          Text('${_formatTime(shift.startTime)} - ${_formatTime(shift.endTime)}', style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
                          const Spacer(),
                          Text('${schedules.length + uniqueRegs.length + pendingLocal.length} NV', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0891B2))),
                          if (canEdit) ...[
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => _showAssignEmployeeToShiftDialog(shift, day),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(color: const Color(0xFF0891B2).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                                child: const Icon(Icons.person_add, size: 16, color: Color(0xFF0891B2)),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Employee list
                      if (schedules.isEmpty && uniqueRegs.isEmpty && pendingLocal.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text('Chưa có nhân viên', style: TextStyle(fontSize: 12, color: Colors.grey[400], fontStyle: FontStyle.italic)),
                        )
                      else
                        Wrap(
                          spacing: 6, runSpacing: 4,
                          children: [
                            // Confirmed schedules
                            ...schedules.map((ws) {
                              final emp = _employees.firstWhere((e) => _effectiveUserId(e) == ws.employeeUserId, orElse: () => Employee.empty());
                              return _empChip(emp.fullName, const Color(0xFF1E3A5F), Icons.check);
                            }),
                            // Submitted registrations
                            ...uniqueRegs.map((reg) {
                              final emp = _employees.firstWhere((e) => _effectiveUserId(e) == reg.employeeUserId, orElse: () => Employee.empty());
                              Color c; IconData ic;
                              switch (reg.status) {
                                case ScheduleRegistrationStatus.approved: c = const Color(0xFF059669); ic = Icons.check_circle; break;
                                case ScheduleRegistrationStatus.rejected: c = const Color(0xFFEF4444); ic = Icons.cancel; break;
                                default: c = const Color(0xFFD97706); ic = Icons.hourglass_empty;
                              }
                              return _empChip(emp.fullName, c, ic);
                            }),
                            // Local pending
                            ...pendingLocal.map((reg) {
                              final emp = _employees.firstWhere((e) => _effectiveUserId(e) == reg['employeeId'], orElse: () => Employee.empty());
                              return _empChip(emp.fullName, const Color(0xFF8B5CF6), Icons.add_circle);
                            }),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _empChip(String name, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(name, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildManagerGridCell(Shift shift, DateTime day, bool isToday, bool canEdit) {
    final schedules = _getSchedulesForShiftDay(shift.id, day);
    final pendingLocal = _getPendingForShiftDay(shift.id, day);
    final submittedRegs = _getRegistrationsForShiftDay(shift.id, day);
    final pendingRegs = submittedRegs.where((r) => r.status == ScheduleRegistrationStatus.pending).toList();
    final approvedRegs = submittedRegs.where((r) => r.status == ScheduleRegistrationStatus.approved).toList();
    // Unique employees: exclude duplicates between confirmed and submitted
    final confirmedCount = schedules.length;
    final approvedCount = approvedRegs.where((r) => schedules.every((s) => s.employeeUserId != r.employeeUserId)).length;
    final pendingCount = pendingRegs.where((r) => schedules.every((s) => s.employeeUserId != r.employeeUserId)).length;
    final localCount = pendingLocal.length;
    final totalCount = confirmedCount + approvedCount + pendingCount + localCount;

    // Quota check
    final quota = _getQuotaForShift(shift.id);
    final bool belowWarning = quota != null && totalCount <= (quota['warningThreshold'] ?? 0) && totalCount < (quota['minEmployees'] ?? 0);
    final bool aboveMax = quota != null && totalCount > (quota['maxEmployees'] ?? 999);

    Color bgColor;
    Color borderColor;
    Widget content;

    if (totalCount == 0) {
      bgColor = belowWarning ? const Color(0xFFFEE2E2) : (isToday ? const Color(0xFFF1F5F9) : Colors.white);
      borderColor = belowWarning ? const Color(0xFFEF4444) : const Color(0xFFE4E4E7);
      content = belowWarning
        ? const Icon(Icons.warning_amber, size: 14, color: Color(0xFFEF4444))
        : Icon(Icons.add, size: 14, color: Colors.grey[300]);
    } else {
      // Primary color by highest-priority status present
      if (confirmedCount > 0) {
        bgColor = const Color(0xFF1E3A5F).withValues(alpha: 0.08);
        borderColor = const Color(0xFF1E3A5F);
      } else if (approvedCount > 0) {
        bgColor = const Color(0xFF059669).withValues(alpha: 0.08);
        borderColor = const Color(0xFF059669);
      } else if (pendingCount > 0) {
        bgColor = const Color(0xFFFEF3C7);
        borderColor = const Color(0xFFD97706);
      } else {
        bgColor = const Color(0xFF8B5CF6).withValues(alpha: 0.08);
        borderColor = const Color(0xFF8B5CF6);
      }

      // Override colors for quota violations
      if (belowWarning) {
        bgColor = const Color(0xFFFEE2E2);
        borderColor = const Color(0xFFEF4444);
      } else if (aboveMax) {
        bgColor = const Color(0xFFFEF3C7);
        borderColor = const Color(0xFFF59E0B);
      }

      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (belowWarning) const Padding(padding: EdgeInsets.only(right: 2), child: Icon(Icons.arrow_downward, size: 10, color: Color(0xFFEF4444))),
              if (aboveMax) const Padding(padding: EdgeInsets.only(right: 2), child: Icon(Icons.arrow_upward, size: 10, color: Color(0xFFF59E0B))),
              Text('$totalCount', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: belowWarning ? const Color(0xFFEF4444) : (aboveMax ? const Color(0xFFF59E0B) : borderColor))),
              if (quota != null) Text('/${quota['maxEmployees']}', style: const TextStyle(fontSize: 9, color: Color(0xFF71717A))),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (confirmedCount > 0) _statusDot(const Color(0xFF1E3A5F)),
              if (approvedCount > 0) _statusDot(const Color(0xFF059669)),
              if (pendingCount > 0) _statusDot(const Color(0xFFD97706)),
              if (localCount > 0) _statusDot(const Color(0xFF8B5CF6)),
            ],
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: canEdit ? () => _showAssignEmployeeToShiftDialog(shift, day) : () => _showCellDetailDialog(shift, day),
      onLongPress: (belowWarning && canEdit) ? () => _showRequestCoverageDialog(preselectedShift: shift, preselectedDate: day) : null,
      child: Container(
        height: 56,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(color: borderColor, width: (totalCount > 0 || belowWarning) ? 1.5 : 0.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(child: content),
      ),
    );
  }

  Widget _statusDot(Color color) {
    return Container(
      width: 6, height: 6,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  void _showCellDetailDialog(Shift shift, DateTime day) {
    final schedules = _getSchedulesForShiftDay(shift.id, day);
    final pendingLocal = _getPendingForShiftDay(shift.id, day);
    final submittedRegs = _getRegistrationsForShiftDay(shift.id, day);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(shift.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF18181B))),
          Text('${DateFormat('EEEE dd/MM/yyyy', 'vi').format(day)} • ${_formatTime(shift.startTime)}-${_formatTime(shift.endTime)}',
            style: const TextStyle(fontSize: 12, color: Color(0xFF71717A))),
        ]),
        content: SizedBox(
          width: 300,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (schedules.isNotEmpty) ...[
                  const Text('Đã xếp lịch', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF1E3A5F))),
                  const SizedBox(height: 4),
                  ...schedules.map((ws) {
                    final emp = _employees.firstWhere((e) => _effectiveUserId(e) == ws.employeeUserId, orElse: () => Employee.empty());
                    return _detailEmpRow(emp.fullName, const Color(0xFF1E3A5F), Icons.check);
                  }),
                  const SizedBox(height: 8),
                ],
                if (submittedRegs.isNotEmpty) ...[
                  ...submittedRegs.where((r) => schedules.every((s) => s.employeeUserId != r.employeeUserId)).map((reg) {
                    final emp = _employees.firstWhere((e) => _effectiveUserId(e) == reg.employeeUserId, orElse: () => Employee.empty());
                    Color c; IconData ic; String label;
                    switch (reg.status) {
                      case ScheduleRegistrationStatus.approved: c = const Color(0xFF059669); ic = Icons.check_circle; label = 'Duyệt'; break;
                      case ScheduleRegistrationStatus.rejected: c = const Color(0xFFEF4444); ic = Icons.cancel; label = 'Từ chối'; break;
                      default: c = const Color(0xFFD97706); ic = Icons.hourglass_empty; label = 'Chờ duyệt';
                    }
                    return _detailEmpRow('${emp.fullName} ($label)', c, ic);
                  }),
                  const SizedBox(height: 8),
                ],
                if (pendingLocal.isNotEmpty) ...[
                  const Text('Chưa gửi', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF8B5CF6))),
                  const SizedBox(height: 4),
                  ...pendingLocal.map((reg) {
                    final emp = _employees.firstWhere((e) => _effectiveUserId(e) == reg['employeeId'], orElse: () => Employee.empty());
                    return _detailEmpRow(emp.fullName, const Color(0xFF8B5CF6), Icons.add_circle);
                  }),
                ],
                if (schedules.isEmpty && submittedRegs.isEmpty && pendingLocal.isEmpty)
                  const Text('Chưa có nhân viên nào', style: TextStyle(color: Color(0xFF71717A), fontSize: 13)),
              ],
            ),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng'))],
      ),
    );
  }

  Widget _detailEmpRow(String name, Color color, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(name, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  void _showAssignEmployeeToShiftDialog(Shift shift, DateTime day) {
    final searchCtrl = TextEditingController();
    List<Employee> filtered = List.from(_filteredEmployees);
    final assignedIds = <String>{};
    final selectedIds = <String>{}; // multi-select
    // Collect already-assigned employee IDs
    for (final s in _getSchedulesForShiftDay(shift.id, day)) {
      assignedIds.add(s.employeeUserId);
    }
    for (final p in _getPendingForShiftDay(shift.id, day)) {
      assignedIds.add(p['employeeId'] as String);
    }
    for (final r in _getRegistrationsForShiftDay(shift.id, day).where((r) => r.status != ScheduleRegistrationStatus.rejected)) {
      assignedIds.add(r.employeeUserId);
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void filter() {
            final q = searchCtrl.text.toLowerCase();
            setDialogState(() {
              filtered = _filteredEmployees.where((e) {
                final name = e.fullName.toLowerCase();
                final code = e.employeeCode.toLowerCase();
                return name.contains(q) || code.contains(q);
              }).toList();
            });
          }

          // Select/deselect all visible (non-assigned)
          final availableFiltered = filtered.where((e) => !assignedIds.contains(_effectiveUserId(e))).toList();
          final allSelected = availableFiltered.isNotEmpty && availableFiltered.every((e) => selectedIds.contains(_effectiveUserId(e)));

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: const Color(0xFF0891B2).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.person_add, color: Color(0xFF0891B2), size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text('Thêm NV vào ${shift.name}', style: const TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold, fontSize: 16))),
              ]),
              const SizedBox(height: 4),
              Text('${DateFormat('EEEE dd/MM/yyyy', 'vi').format(day)}  •  ${_formatTime(shift.startTime)} - ${_formatTime(shift.endTime)}',
                style: const TextStyle(fontSize: 13, color: Color(0xFF71717A))),
            ]),
            content: SizedBox(
              width: Responsive.dialogWidth(context), height: 450,
              child: Column(children: [
                TextField(
                  controller: searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Tìm nhân viên...', prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), isDense: true,
                  ),
                  onChanged: (_) => filter(),
                ),
                const SizedBox(height: 8),
                // Select all / count row
                Row(children: [
                  InkWell(
                    onTap: () {
                      setDialogState(() {
                        if (allSelected) {
                          for (final e in availableFiltered) {
                            selectedIds.remove(_effectiveUserId(e));
                          }
                        } else {
                          for (final e in availableFiltered) {
                            selectedIds.add(_effectiveUserId(e));
                          }
                        }
                      });
                    },
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(allSelected ? Icons.check_box : Icons.check_box_outline_blank, color: const Color(0xFF0891B2), size: 20),
                      const SizedBox(width: 4),
                      Text(allSelected ? 'Bỏ chọn tất cả' : 'Chọn tất cả', style: const TextStyle(fontSize: 12, color: Color(0xFF0891B2))),
                    ]),
                  ),
                  const Spacer(),
                  if (selectedIds.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0xFF0891B2).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: Text('Đã chọn: ${selectedIds.length}', style: const TextStyle(fontSize: 12, color: Color(0xFF0891B2), fontWeight: FontWeight.bold)),
                    ),
                ]),
                const SizedBox(height: 8),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text('Không tìm thấy nhân viên'))
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final emp = filtered[i];
                            final effId = _effectiveUserId(emp);
                            final isAssigned = assignedIds.contains(effId);
                            final isSelected = selectedIds.contains(effId);
                            return ListTile(
                              leading: isAssigned
                                  ? CircleAvatar(
                                      backgroundColor: Colors.grey[200],
                                      child: Text(
                                        emp.firstName.isNotEmpty ? emp.firstName[0].toUpperCase() : '?',
                                        style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
                                      ),
                                    )
                                  : Icon(
                                      isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                                      color: isSelected ? const Color(0xFF0891B2) : Colors.grey[400],
                                    ),
                              title: Text(emp.fullName, style: TextStyle(
                                color: isAssigned ? Colors.grey : isSelected ? const Color(0xFF0891B2) : null,
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              )),
                              subtitle: Text(emp.employeeCode, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                              trailing: isAssigned
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(12)),
                                      child: const Text('Đã phân', style: TextStyle(fontSize: 11, color: Color(0xFF71717A))),
                                    )
                                  : isSelected
                                      ? const Icon(Icons.check_circle, color: Color(0xFF0891B2))
                                      : null,
                              onTap: isAssigned ? null : () {
                                setDialogState(() {
                                  if (isSelected) {
                                    selectedIds.remove(effId);
                                  } else {
                                    selectedIds.add(effId);
                                  }
                                });
                              },
                            );
                          },
                        ),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () { searchCtrl.dispose(); Navigator.pop(ctx); }, child: const Text('Đóng', style: TextStyle(color: Color(0xFF71717A)))),
              FilledButton.icon(
                onPressed: selectedIds.isEmpty ? null : () {
                  searchCtrl.dispose();
                  Navigator.pop(ctx);
                  for (final empId in selectedIds) {
                    _addPendingRegistration(empId, day, shift.id, false, null);
                  }
                },
                icon: const Icon(Icons.check, size: 18),
                label: Text('Thêm ${selectedIds.isEmpty ? '' : '(${selectedIds.length})'}'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0891B2),
                  disabledBackgroundColor: Colors.grey[300],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildScheduleCell(Employee employee, DateTime day, List<WorkSchedule> schedules, List<Map<String, dynamic>> pendingRegs, [List<ScheduleRegistration> submittedRegs = const []]) {
    // Nếu có pending registration (chờ gửi - màu vàng)
    if (pendingRegs.isNotEmpty) {
      // Day off pending
      if (pendingRegs.first['isDayOff'] == true) {
        final note = pendingRegs.first['note'] ?? 'Nghỉ phép';
        return InkWell(
          onTap: () => _removePendingRegistration(_effectiveUserId(employee), day),
          child: Container(
            width: 100,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3CD),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFC107), width: 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  note,
                  style: const TextStyle(color: Color(0xFF856404), fontWeight: FontWeight.bold, fontSize: 10),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
                const Text(
                  'Chờ gửi',
                  style: TextStyle(color: Color(0xFF856404), fontSize: 9),
                ),
              ],
            ),
          ),
        );
      }
      // Multiple shifts pending - sort by shift startTime
      final sortedPendingRegs = List<Map<String, dynamic>>.from(pendingRegs);
      sortedPendingRegs.sort((a, b) {
        final shiftA = _shifts.firstWhere((s) => s.id == a['shiftId'], orElse: () => Shift(id: '', name: '', code: '', startTime: '99:99', endTime: '', isActive: true, createdAt: DateTime.now()));
        final shiftB = _shifts.firstWhere((s) => s.id == b['shiftId'], orElse: () => Shift(id: '', name: '', code: '', startTime: '99:99', endTime: '', isActive: true, createdAt: DateTime.now()));
        return shiftA.startTime.compareTo(shiftB.startTime);
      });
      final shiftNames = sortedPendingRegs.map((reg) {
        final shift = _shifts.firstWhere(
          (s) => s.id == reg['shiftId'],
          orElse: () => Shift(id: '', name: 'Ca', code: '', startTime: '', endTime: '', isActive: true, createdAt: DateTime.now()),
        );
        return shift.name;
      }).toList();
      return InkWell(
        onTap: () => _removePendingRegistration(_effectiveUserId(employee), day),
        child: Container(
          width: 100,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3CD),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFFFC107), width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              ...shiftNames.map((name) => Text(
                name,
                style: const TextStyle(color: Color(0xFF856404), fontWeight: FontWeight.bold, fontSize: 10),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              )),
              const Text(
                'Chờ gửi',
                style: TextStyle(color: Color(0xFF856404), fontSize: 9),
              ),
            ],
          ),
        ),
      );
    }

    // Nếu đã có lịch (đã đăng ký)
    if (schedules.isNotEmpty) {
      // Check if any schedule is day off
      final dayOffSchedule = schedules.where((s) => s.isDayOff).firstOrNull;
      if (dayOffSchedule != null) {
        // Nghỉ phép - màu xanh lá
        final leaveLabel = (dayOffSchedule.note != null && dayOffSchedule.note!.isNotEmpty) ? dayOffSchedule.note! : 'Nghỉ phép';
        return InkWell(
          onTap: () => _showRegisterDialog(employee, day),
          child: Container(
            width: 100,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E3A5F), Color(0xFF059669)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.beach_access, color: Colors.white, size: 14),
                const SizedBox(height: 1),
                Text(
                  leaveLabel,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 9),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      } else {
        // Ca đã đăng ký - màu xanh dương (supports multiple shifts, sorted by startTime)
        final sortedSchedules = List<WorkSchedule>.from(schedules);
        sortedSchedules.sort((a, b) {
          final shiftA = a.shiftId != null ? _shifts.firstWhere((s) => s.id == a.shiftId, orElse: () => Shift(id: '', name: '', code: '', startTime: '99:99', endTime: '', isActive: true, createdAt: DateTime.now())) : null;
          final shiftB = b.shiftId != null ? _shifts.firstWhere((s) => s.id == b.shiftId, orElse: () => Shift(id: '', name: '', code: '', startTime: '99:99', endTime: '', isActive: true, createdAt: DateTime.now())) : null;
          return (shiftA?.startTime ?? '99:99').compareTo(shiftB?.startTime ?? '99:99');
        });
        final shiftWidgets = <Widget>[];
        for (final schedule in sortedSchedules) {
          final shift = schedule.shiftId != null
              ? _shifts.firstWhere(
                  (s) => s.id == schedule.shiftId,
                  orElse: () => Shift(id: '', name: 'Ca làm', code: '', startTime: '', endTime: '', isActive: true, createdAt: DateTime.now()),
                )
              : null;
          shiftWidgets.add(Text(
            shift?.name ?? 'Ca làm',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ));
          if (shift != null) {
            shiftWidgets.add(Text(
              '${_formatTime(shift.startTime)} - ${_formatTime(shift.endTime)}',
              style: const TextStyle(color: Colors.white70, fontSize: 8),
            ));
          }
        }
        return InkWell(
          onTap: () => _showRegisterDialog(employee, day),
          child: Container(
            width: 100,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E3A5F), Color(0xFF1E3A5F)],
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: shiftWidgets,
            ),
          ),
        );
      }
    }

    // Submitted registrations (pending / rejected)
    if (submittedRegs.isNotEmpty && schedules.isEmpty) {
      final activeRegs = submittedRegs.where((r) => r.status != ScheduleRegistrationStatus.approved).toList();
      if (activeRegs.isNotEmpty) {
        Color bgColor;
        Color borderColor;
        String statusText;
        final firstReg = activeRegs.first;
        
        switch (firstReg.status) {
          case ScheduleRegistrationStatus.pending:
            bgColor = const Color(0xFFFEF3C7);
            borderColor = const Color(0xFFF59E0B);
            statusText = 'Chờ duyệt';
            break;
          case ScheduleRegistrationStatus.rejected:
            bgColor = const Color(0xFFFEE2E2);
            borderColor = const Color(0xFFEF4444);
            statusText = 'Từ chối';
            break;
          default:
            bgColor = const Color(0xFFD1FAE5);
            borderColor = const Color(0xFF1E3A5F);
            statusText = 'Đã duyệt';
        }

        final sortedActiveRegs = List<ScheduleRegistration>.from(activeRegs);
        sortedActiveRegs.sort((a, b) {
          final shiftA = a.shiftId != null ? _shifts.firstWhere((s) => s.id == a.shiftId, orElse: () => Shift(id: '', name: '', code: '', startTime: '99:99', endTime: '', isActive: true, createdAt: DateTime.now())) : null;
          final shiftB = b.shiftId != null ? _shifts.firstWhere((s) => s.id == b.shiftId, orElse: () => Shift(id: '', name: '', code: '', startTime: '99:99', endTime: '', isActive: true, createdAt: DateTime.now())) : null;
          return (shiftA?.startTime ?? '99:99').compareTo(shiftB?.startTime ?? '99:99');
        });

        final regLabels = sortedActiveRegs.map((r) {
          if (r.isDayOff) return r.note ?? 'Nghỉ phép';
          final shift = r.shiftId != null
              ? _shifts.firstWhere((s) => s.id == r.shiftId, orElse: () => Shift(id: '', name: 'Ca', code: '', startTime: '', endTime: '', isActive: true, createdAt: DateTime.now()))
              : null;
          return shift?.name ?? 'Ca';
        }).toList();

        return InkWell(
          onTap: () => _showRegisterDialog(employee, day),
          child: Container(
            width: 100,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor, width: 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                ...regLabels.map((label) => Text(
                  label,
                  style: TextStyle(color: borderColor, fontWeight: FontWeight.bold, fontSize: 10),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                )),
                Text(
                  statusText,
                  style: TextStyle(color: borderColor, fontSize: 9),
                ),
              ],
            ),
          ),
        );
      }
    }

    // Chưa đăng ký - click để đăng ký
    return InkWell(
      onTap: () => _showRegisterDialog(employee, day),
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE4E4E7), style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_circle_outline, color: Colors.grey[400], size: 18),
            const SizedBox(height: 2),
            Text(
              'Đăng ký',
              style: TextStyle(color: Colors.grey[400], fontSize: 9),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(String timeString) {
    final parts = timeString.split(':');
    if (parts.length >= 2) {
      return '${parts[0]}:${parts[1]}';
    }
    return timeString;
  }

  void _showRegisterDialog(Employee employee, DateTime day) {
    Set<String> selectedShiftIds = {};
    bool isDayOff = false;
    String leaveType = 'Nghỉ phép năm';
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Đăng ký ca - ${employee.lastName} ${employee.firstName}',
            style: const TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ngày: ${DateFormat('EEEE, dd/MM/yyyy', 'vi').format(day)}',
                style: const TextStyle(color: Color(0xFF71717A)),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Nghỉ phép', style: TextStyle(color: Color(0xFF18181B))),
                value: isDayOff,
                onChanged: (value) => setDialogState(() {
                  isDayOff = value;
                  if (value) selectedShiftIds.clear();
                }),
                activeThumbColor: const Color(0xFF1E3A5F),
              ),
              if (isDayOff) ...[
                const SizedBox(height: 8),
                const Text('Loại nghỉ phép:', style: TextStyle(color: Color(0xFF18181B))),
                const SizedBox(height: 8),
                ...['Nghỉ phép năm', 'Nghỉ phép có lương', 'Nghỉ phép không lương'].map((type) => RadioListTile<String>(
                  title: Text(type, style: const TextStyle(color: Color(0xFF18181B))),
                  value: type,
                  // ignore: deprecated_member_use
                  groupValue: leaveType,
                  // ignore: deprecated_member_use
                  onChanged: (value) => setDialogState(() => leaveType = value!),
                  activeColor: const Color(0xFF1E3A5F),
                  dense: true,
                )),
              ],
              if (!isDayOff) ...[
                const SizedBox(height: 16),
                const Text('Chọn ca làm việc:', style: TextStyle(color: Color(0xFF18181B))),
                const SizedBox(height: 8),
                ..._shifts.map((shift) => CheckboxListTile(
                  title: Text(shift.name, style: const TextStyle(color: Color(0xFF18181B))),
                  subtitle: Text(
                    '${_formatTime(shift.startTime)} - ${_formatTime(shift.endTime)}',
                    style: const TextStyle(color: Color(0xFF71717A)),
                  ),
                  value: selectedShiftIds.contains(shift.id),
                  onChanged: (value) => setDialogState(() {
                    if (value == true) {
                      selectedShiftIds.add(shift.id);
                    } else {
                      selectedShiftIds.remove(shift.id);
                    }
                  }),
                  activeColor: const Color(0xFF1E3A5F),
                  controlAffinity: ListTileControlAffinity.leading,
                )),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A))),
            ),
            ElevatedButton(
              onPressed: () {
                if (!isDayOff && selectedShiftIds.isEmpty) {
                  appNotification.showWarning(
                    title: 'Thiếu thông tin',
                    message: 'Vui lòng chọn ít nhất một ca làm việc',
                  );
                  return;
                }
                if (isDayOff) {
                  _addPendingRegistration(_effectiveUserId(employee), day, null, true, leaveType);
                } else {
                  for (final shiftId in selectedShiftIds) {
                    _addPendingRegistration(_effectiveUserId(employee), day, shiftId, false, null);
                  }
                }
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F)),
              child: const Text('Thêm vào danh sách chờ'),
            ),
          ],
        ),
      ),
    );
  }

  void _addPendingRegistration(String employeeId, DateTime day, String? shiftId, bool isDayOff, String? note) {
    setState(() {
      if (isDayOff) {
        // For day off, remove all existing pending for same employee and day
        _pendingRegistrations.removeWhere(
          (r) => r['employeeId'] == employeeId &&
                 (r['date'] as DateTime).day == day.day &&
                 (r['date'] as DateTime).month == day.month &&
                 (r['date'] as DateTime).year == day.year,
        );
        _pendingRegistrations.add({
          'employeeId': employeeId,
          'date': day,
          'shiftId': shiftId,
          'isDayOff': isDayOff,
          'note': note,
        });
      } else {
        // For shifts, remove day-off pending if exists, then add shift (avoid duplicate)
        _pendingRegistrations.removeWhere(
          (r) => r['employeeId'] == employeeId &&
                 (r['date'] as DateTime).day == day.day &&
                 (r['date'] as DateTime).month == day.month &&
                 (r['date'] as DateTime).year == day.year &&
                 (r['isDayOff'] == true || r['shiftId'] == shiftId),
        );
        _pendingRegistrations.add({
          'employeeId': employeeId,
          'date': day,
          'shiftId': shiftId,
          'isDayOff': false,
          'note': note,
        });
      }
    });
  }

  void _removePendingRegistration(String employeeId, DateTime day) {
    setState(() {
      _pendingRegistrations.removeWhere(
        (r) => r['employeeId'] == employeeId &&
               (r['date'] as DateTime).day == day.day &&
               (r['date'] as DateTime).month == day.month &&
               (r['date'] as DateTime).year == day.year,
      );
    });
  }

  Widget _buildPendingRegistrations() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF3CD), Color(0xFFFFF9E6)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: const Border(
          left: BorderSide(color: Color(0xFFFFC107), width: 4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.schedule_send, color: Color(0xFF856404)),
                  const SizedBox(width: 8),
                  Text(
                    'Danh sách đăng ký chờ gửi (${_pendingRegistrations.length})',
                    style: const TextStyle(
                      color: Color(0xFF856404),
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _clearAllPendingRegistrations,
                    icon: const Icon(Icons.delete_sweep, size: 18),
                    label: const Text('Xóa tất cả'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF856404),
                      side: const BorderSide(color: Color(0xFF856404)),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _submitAllRegistrations,
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('Gửi tất cả đăng ký'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E3A5F),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _pendingRegistrations.map((reg) {
              final employee = _employees.firstWhere(
                (e) => _effectiveUserId(e) == reg['employeeId'],
                orElse: () => Employee.empty(),
              );
              final shift = reg['shiftId'] != null
                  ? _shifts.firstWhere((s) => s.id == reg['shiftId'], orElse: () => Shift(id: '', name: 'Ca', code: '', startTime: '', endTime: '', isActive: true, createdAt: DateTime.now()))
                  : null;
              return Chip(
                backgroundColor: const Color(0xFFFFE082),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () {
                  setState(() {
                    _pendingRegistrations.remove(reg);
                  });
                },
                label: Text(
                  '${employee.firstName} - ${DateFormat('dd/MM').format(reg['date'])} - ${reg['isDayOff'] == true ? (reg['note'] ?? 'Nghỉ phép') : shift?.name ?? ''}',
                  style: const TextStyle(color: Color(0xFF856404), fontSize: 12),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _clearAllPendingRegistrations() {
    setState(() {
      _pendingRegistrations.clear();
    });
  }

  Future<void> _submitAllRegistrations() async {
    if (_pendingRegistrations.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      int successCount = 0;
      int failCount = 0;
      for (final reg in _pendingRegistrations) {
        final shiftId = reg['shiftId'];
        final result = await _apiService.createScheduleRegistration({
          'employeeUserId': reg['employeeId'],
          'shiftId': (shiftId != null && shiftId.toString().isNotEmpty) ? shiftId : null,
          'date': (reg['date'] as DateTime).toIso8601String(),
          'isDayOff': reg['isDayOff'] ?? false,
          'note': reg['note'] ?? (reg['isDayOff'] == true ? 'Nghỉ phép' : ''),
        });
        if (result['isSuccess'] == true) {
          successCount++;
        } else {
          failCount++;
          debugPrint('❌ Failed to create registration: ${result['message']}');
        }
      }
      
      if (mounted) {
        if (failCount == 0) {
          appNotification.showSuccess(
            title: 'Đăng ký thành công',
            message: 'Đã gửi $successCount đăng ký',
          );
        } else {
          appNotification.showError(
            title: 'Đăng ký không hoàn tất',
            message: 'Thành công: $successCount, Thất bại: $failCount',
          );
        }
      }
      
      setState(() {
        _pendingRegistrations.clear();
      });
      
      await _loadSchedules();
      await _loadRegistrations();
    } catch (e) {
      if (mounted) {
        appNotification.showError(
          title: 'Lỗi',
          message: '$e',
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ignore: unused_element
  Widget _buildSubmittedRegistrations() {
    // Filter registrations for the current week
    final weekEnd = _selectedWeekStart.add(const Duration(days: 6));
    final weekRegs = _registrations.where((r) {
      final regDate = DateTime(r.date.year, r.date.month, r.date.day);
      final weekStart = DateTime(_selectedWeekStart.year, _selectedWeekStart.month, _selectedWeekStart.day);
      final end = DateTime(weekEnd.year, weekEnd.month, weekEnd.day);
      return !regDate.isBefore(weekStart) && !regDate.isAfter(end);
    }).toList()..sort((a, b) => a.date.compareTo(b.date));

    if (weekRegs.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.list_alt, color: Color(0xFF1E3A5F)),
              const SizedBox(width: 8),
              Text(
                'Danh sách yêu cầu đã gửi (${weekRegs.length})',
                style: const TextStyle(
                  color: Color(0xFF18181B),
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              // Status summary
              _buildStatusBadge('Chờ duyệt', const Color(0xFFF59E0B), weekRegs.where((r) => r.status == ScheduleRegistrationStatus.pending).length),
              const SizedBox(width: 8),
              _buildStatusBadge('Đã duyệt', const Color(0xFF1E3A5F), weekRegs.where((r) => r.status == ScheduleRegistrationStatus.approved).length),
              const SizedBox(width: 8),
              _buildStatusBadge('Từ chối', const Color(0xFFEF4444), weekRegs.where((r) => r.status == ScheduleRegistrationStatus.rejected).length),
            ],
          ),
          const SizedBox(height: 12),
          ...weekRegs.map((reg) {
            final employee = _employees.firstWhere(
              (e) => _effectiveUserId(e) == reg.employeeUserId,
              orElse: () => Employee.empty(),
            );
            final shift = reg.shiftId != null && reg.shiftId!.isNotEmpty
                ? _shifts.firstWhere((s) => s.id == reg.shiftId, orElse: () => Shift(id: '', name: 'Ca', code: '', startTime: '', endTime: '', isActive: true, createdAt: DateTime.now()))
                : null;

            Color statusColor;
            IconData statusIcon;
            String statusText;
            switch (reg.status) {
              case ScheduleRegistrationStatus.approved:
                statusColor = const Color(0xFF1E3A5F);
                statusIcon = Icons.check_circle;
                statusText = 'Đã duyệt';
                break;
              case ScheduleRegistrationStatus.rejected:
                statusColor = const Color(0xFFEF4444);
                statusIcon = Icons.cancel;
                statusText = 'Từ chối';
                break;
              default:
                statusColor = const Color(0xFFF59E0B);
                statusIcon = Icons.hourglass_empty;
                statusText = 'Chờ duyệt';
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(statusIcon, color: statusColor, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${employee.fullName} - ${DateFormat('dd/MM/yyyy (EEEE)', 'vi').format(reg.date)}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF18181B)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          reg.isDayOff
                              ? (reg.note != null && reg.note!.isNotEmpty ? reg.note! : 'Nghỉ phép')
                              : (shift?.name ?? 'Ca'),
                          style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
                        ),
                        if (reg.status == ScheduleRegistrationStatus.rejected && reg.rejectionReason != null && reg.rejectionReason!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Lý do: ${reg.rejectionReason}',
                            style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontStyle: FontStyle.italic),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Delete button for pending registrations
                  if (reg.status == ScheduleRegistrationStatus.pending && Provider.of<PermissionProvider>(context, listen: false).canDelete('WorkSchedule')) ...[
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 20),
                      tooltip: 'Xóa đăng ký',
                      onPressed: () => _deleteRegistration(reg.id),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(String label, Color color, int count) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }

  // ══════════════════════════════════════════════
  //  APPROVED SCHEDULE TABLE (Lịch đã duyệt)
  // ══════════════════════════════════════════════
  Widget _buildApprovedScheduleTable() {
    final days = List.generate(7, (i) => _selectedWeekStart.add(Duration(days: i)));
    final dayNames = ['THỨ 2', 'THỨ 3', 'THỨ 4', 'THỨ 5', 'THỨ 6', 'THỨ 7', 'CHỦ NHẬT'];
    final dateFormat = DateFormat('d/M');
    final today = DateTime.now();
    final emps = _filteredEmployees;

    // Only approved registrations + confirmed work schedules
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 600;
          final totalPages = (emps.length / _schedulePageSize).ceil();
          final safePage = _approvedPage.clamp(1, totalPages == 0 ? 1 : totalPages);
          final startIdx = isMobile ? 0 : (safePage - 1) * _schedulePageSize;
          final endIdx = isMobile ? emps.length : (startIdx + _schedulePageSize).clamp(0, emps.length);
          final pageEmps = emps.sublist(startIdx, endIdx);
          if (isMobile) {
            return Column(children: [
              _buildMobileApprovedCards(pageEmps, days, dayNames, dateFormat),
            ]);
          }
          return Column(children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFF1E3A5F).withValues(alpha: 0.08)),
          dataRowColor: WidgetStateProperty.all(Colors.white),
          dataRowMinHeight: 56,
          dataRowMaxHeight: 140,
          border: TableBorder.all(color: const Color(0xFFE4E4E7), width: 1),
          columns: [
            const DataColumn(
              label: Expanded(child: Text('NHÂN VIÊN', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF1E3A5F), fontWeight: FontWeight.bold, fontSize: 12))),
            ),
            ...List.generate(7, (i) {
              final day = days[i];
              final isToday = day.day == today.day && day.month == today.month && day.year == today.year;
              return DataColumn(
                label: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(dayNames[i], style: TextStyle(
                      color: isToday ? const Color(0xFF1E3A5F) : const Color(0xFF18181B),
                      fontWeight: FontWeight.bold, fontSize: 12,
                    )),
                    Text(dateFormat.format(day), style: TextStyle(
                      color: isToday ? const Color(0xFF1E3A5F) : const Color(0xFF71717A), fontSize: 11,
                    )),
                  ],
                ),
              );
            }),
            const DataColumn(
              label: Expanded(child: Text('TỔNG CA', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF1E3A5F), fontWeight: FontWeight.bold, fontSize: 12))),
            ),
          ],
          rows: pageEmps.isEmpty
              ? [
                  DataRow(cells: [
                    DataCell(Center(child: Text('Chưa có nhân viên', style: TextStyle(color: Colors.grey[400])))),
                    ...List.generate(8, (_) => const DataCell(Text(''))),
                  ]),
                ]
              : pageEmps.map((employee) {
                  int totalApproved = 0;
                  return DataRow(
                    cells: [
                      DataCell(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(employee.fullName.toUpperCase(),
                              style: const TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.w600, fontSize: 13)),
                            Text(employee.department ?? employee.employeeCode,
                              style: const TextStyle(color: Color(0xFF71717A), fontSize: 11)),
                          ],
                        ),
                      ),
                      ...List.generate(7, (dayIndex) {
                        final day = days[dayIndex];
                        final effectiveId = _effectiveUserId(employee);
                        // Get confirmed schedules (from WorkSchedule)
                        final confirmedSchedules = _getSchedulesForDay(effectiveId, day);
                        // Get approved registrations
                        final approvedRegs = _getRegistrationsForDay(effectiveId, day)
                            .where((r) => r.status == ScheduleRegistrationStatus.approved)
                            .toList();

                        // Combine: confirmed schedules + approved registrations not yet in schedules
                        final allApproved = <Widget>[];
                        for (final ws in confirmedSchedules) {
                          if (ws.isDayOff) {
                            allApproved.add(_buildApprovedChip('Nghỉ', const Color(0xFF71717A), Icons.nightlight_round));
                          } else {
                            final shift = _shifts.firstWhere((s) => s.id == ws.shiftId, orElse: () => Shift(id: '', name: 'Ca', code: '', startTime: '', endTime: '', isActive: true, createdAt: DateTime.now()));
                            final shiftTime = shift.startTime.isNotEmpty && shift.endTime.isNotEmpty ? '${_formatTime(shift.startTime)}-${_formatTime(shift.endTime)}' : '';
                            allApproved.add(_buildApprovedChip(shift.name, const Color(0xFF1E3A5F), Icons.check_circle, time: shiftTime));
                            totalApproved++;
                          }
                        }
                        for (final reg in approvedRegs.where((r) => confirmedSchedules.every((s) => s.shiftId != r.shiftId || s.employeeUserId != r.employeeUserId))) {
                          if (reg.isDayOff) {
                            allApproved.add(_buildApprovedChip(reg.note ?? 'Nghỉ', const Color(0xFF71717A), Icons.nightlight_round));
                          } else {
                            final shift = reg.shiftId != null ? _shifts.firstWhere((s) => s.id == reg.shiftId, orElse: () => Shift(id: '', name: 'Ca', code: '', startTime: '', endTime: '', isActive: true, createdAt: DateTime.now())) : null;
                            final shiftTime = shift != null && shift.startTime.isNotEmpty && shift.endTime.isNotEmpty ? '${_formatTime(shift.startTime)}-${_formatTime(shift.endTime)}' : '';
                            allApproved.add(_buildApprovedChip(shift?.name ?? 'Ca', const Color(0xFF1E3A5F), Icons.check_circle, time: shiftTime));
                            totalApproved++;
                          }
                        }

                        return DataCell(
                          Container(
                            width: 120,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: allApproved.isEmpty
                                ? Center(child: Text('—', style: TextStyle(color: Colors.grey[300], fontSize: 16)))
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: allApproved,
                                  ),
                          ),
                        );
                      }),
                      DataCell(
                        Center(child: Text('$totalApproved', style: TextStyle(
                          color: totalApproved > 0 ? const Color(0xFF1E3A5F) : Colors.grey,
                          fontWeight: FontWeight.bold, fontSize: 16,
                        ))),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          if (totalPages > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
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
                          value: _schedulePageSize,
                          isDense: true,
                          style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                          items: _pageSizeOptions.map((s) => DropdownMenuItem(value: s, child: Text('$s'))).toList(),
                          onChanged: (v) {
                            if (v != null) setState(() { _schedulePageSize = v; _approvedPage = 1; });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    IconButton(icon: const Icon(Icons.first_page), onPressed: safePage > 1 ? () => setState(() => _approvedPage = 1) : null),
                    IconButton(icon: const Icon(Icons.chevron_left), onPressed: safePage > 1 ? () => setState(() => _approvedPage--) : null),
                    Text('${(safePage - 1) * _schedulePageSize + 1}-${(safePage * _schedulePageSize).clamp(0, emps.length)} / ${emps.length}', style: const TextStyle(fontSize: 13)),
                    IconButton(icon: const Icon(Icons.chevron_right), onPressed: safePage < totalPages ? () => setState(() => _approvedPage++) : null),
                    IconButton(icon: const Icon(Icons.last_page), onPressed: safePage < totalPages ? () => setState(() => _approvedPage = totalPages) : null),
                  ],
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }

  Widget _buildApprovedChip(String label, Color color, IconData icon, {String? time}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                if (time != null && time.isNotEmpty)
                  Text(time, style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.7)), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportHeader(String title, Color color) {
    final weekEnd = _selectedWeekStart.add(const Duration(days: 6));
    final dateFormat = DateFormat('dd/MM/yyyy');
    final weekNumber = _getWeekNumber(_selectedWeekStart);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Flexible(child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color), overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Flexible(child: Text('Tuần $weekNumber: ${dateFormat.format(_selectedWeekStart)} - ${dateFormat.format(weekEnd)}',
            style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.8)), overflow: TextOverflow.ellipsis)),
          if (_selectedDepartment != null) ...[
            const SizedBox(width: 8),
            Flexible(child: Text('Phòng ban: $_selectedDepartment',
              style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.8)), overflow: TextOverflow.ellipsis)),
          ],
        ],
      ),
    );
  }

  Widget _buildCompactLegend() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Row(
        children: [
          const Text('Chú thích: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF71717A))),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                ..._shifts.map((s) => Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: const Color(0xFF1E3A5F), borderRadius: BorderRadius.circular(4))),
                    const SizedBox(width: 4),
                    Text('${s.name}: ${_formatTime(s.startTime)}-${_formatTime(s.endTime)}',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
                  ],
                )),
                _buildCompactLegendDot(const Color(0xFF1E3A5F), 'Đã duyệt'),
                _buildCompactLegendDot(const Color(0xFFF59E0B), 'Chờ duyệt'),
                _buildCompactLegendDot(const Color(0xFFEF4444), 'Từ chối'),
                _buildCompactLegendDot(const Color(0xFFFFC107), 'Chờ gửi'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildLegend() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Chú thích:',
            style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          // Shift list with times
          if (_shifts.isNotEmpty) ...[
            const Text('Danh sách ca làm việc:', style: TextStyle(color: Color(0xFF71717A), fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: _shifts.map((shift) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF1E3A5F).withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(color: const Color(0xFF1E3A5F), borderRadius: BorderRadius.circular(4)),
                      ),
                      const SizedBox(width: 8),
                      Text(shift.name, style: const TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(width: 8),
                      Text('${_formatTime(shift.startTime)} - ${_formatTime(shift.endTime)}',
                        style: const TextStyle(color: Color(0xFF71717A), fontSize: 12)),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
          // Status legend
          const Text('Trạng thái:', style: TextStyle(color: Color(0xFF71717A), fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _buildLegendItem(
                const LinearGradient(colors: [Color(0xFF1E3A5F), Color(0xFF1E3A5F)]),
                'Ca đã đăng ký',
              ),
              _buildLegendItem(
                const LinearGradient(colors: [Color(0xFF1E3A5F), Color(0xFF059669)]),
                'Nghỉ phép',
              ),
              _buildLegendItemWithBorder(
                const Color(0xFFFFF3CD),
                const Color(0xFFFFC107),
                'Chờ gửi (chưa gửi)',
              ),
              _buildLegendItemWithBorder(
                const Color(0xFFFEF3C7),
                const Color(0xFFF59E0B),
                'Chờ duyệt (đã gửi)',
              ),
              _buildLegendItemWithBorder(
                const Color(0xFFDCFCE7),
                const Color(0xFF1E3A5F),
                'Đã duyệt',
              ),
              _buildLegendItemWithBorder(
                const Color(0xFFFEE2E2),
                const Color(0xFFEF4444),
                'Bị từ chối',
              ),
              _buildLegendItemWithBorder(
                const Color(0xFFFAFAFA),
                const Color(0xFFE4E4E7),
                'Chưa đăng ký (Click để đăng ký)',
                isDashed: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Gradient gradient, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Color(0xFF18181B), fontSize: 14)),
      ],
    );
  }

  Widget _buildLegendItemWithBorder(Color color, Color borderColor, String label, {bool isDashed = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: borderColor, width: 2),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(color: Color(0xFF18181B), fontSize: 14)),
      ],
    );
  }

  // ==================== EXPORT METHODS ====================

  Future<void> _exportTableToPng(GlobalKey tableKey, String fileNamePrefix) async {
    try {
      final boundary = tableKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        appNotification.showError(title: 'Lỗi', message: 'Không tìm thấy bảng dữ liệu để chụp');
        return;
      }
      final pixelRatio = kIsWeb ? 2.0 : 3.0;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        appNotification.showError(title: 'Lỗi', message: 'Không thể tạo ảnh');
        return;
      }
      final pngBytes = byteData.buffer.asUint8List();
      final fileName = '${fileNamePrefix}_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.png';
      await file_saver.saveFileBytes(pngBytes, fileName, 'image/png');
      appNotification.showSuccess(title: 'Xuất PNG', message: 'Đã xuất ảnh $fileName');
    } catch (e) {
      appNotification.showError(title: 'Lỗi xuất PNG', message: '$e');
    }
  }

  /// Export shift-centric table as PNG with full employee names (using offscreen overlay)
  Future<void> _exportShiftCentricPng() async {
    final exportKey = GlobalKey();
    final overlayState = Overlay.of(context);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => Positioned(
        left: -5000, top: -5000, // offscreen
        child: Material(
          color: Colors.white,
          child: RepaintBoundary(
            key: exportKey,
            child: SizedBox(
              width: 800,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _buildExportHeader('THEO CA LÀM VIỆC', const Color(0xFF0891B2)),
                  _buildShiftCentricExportView(),
                  const SizedBox(height: 8),
                  _buildCompactLegend(),
                ]),
              ),
            ),
          ),
        ),
      ),
    );

    overlayState.insert(entry);
    // Wait for layout — web (CanvasKit) needs more time
    await Future.delayed(Duration(milliseconds: kIsWeb ? 500 : 200));

    try {
      final boundary = exportKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        appNotification.showError(title: 'Lỗi', message: 'Không thể tạo ảnh');
        entry.remove();
        return;
      }
      final pixelRatio = kIsWeb ? 2.0 : 3.0;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        appNotification.showError(title: 'Lỗi', message: 'Không thể tạo ảnh');
        entry.remove();
        return;
      }
      final pngBytes = byteData.buffer.asUint8List();
      final fileName = 'TheoCalamViec_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.png';
      await file_saver.saveFileBytes(pngBytes, fileName, 'image/png');
      appNotification.showSuccess(title: 'Xuất PNG', message: 'Đã xuất ảnh $fileName');
    } catch (e) {
      appNotification.showError(title: 'Lỗi xuất PNG', message: '$e');
    } finally {
      entry.remove();
    }
  }

  /// Full detail view for export: shows all 7 days with employee names per shift
  Widget _buildShiftCentricExportView() {
    final days = List.generate(7, (i) => _selectedWeekStart.add(Duration(days: i)));
    final dayLabels = ['Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'CN'];
    final dateFormat = DateFormat('dd/MM');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(7, (di) {
        final day = days[di];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE4E4E7)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Day header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0891B2).withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: Text('${dayLabels[di]} ${dateFormat.format(day)}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0891B2))),
              ),
              // Shift rows for this day
              ..._shifts.map((shift) {
                final schedules = _getSchedulesForShiftDay(shift.id, day);
                final pendingLocal = _getPendingForShiftDay(shift.id, day);
                final submittedRegs = _getRegistrationsForShiftDay(shift.id, day);
                final uniqueRegs = submittedRegs.where((r) => schedules.every((s) => s.employeeUserId != r.employeeUserId)).toList();
                final names = <String>[];
                for (final ws in schedules) names.add(_employees.firstWhere((e) => _effectiveUserId(e) == ws.employeeUserId, orElse: () => Employee.empty()).fullName);
                for (final r in uniqueRegs) names.add(_employees.firstWhere((e) => _effectiveUserId(e) == r.employeeUserId, orElse: () => Employee.empty()).fullName);
                for (final p in pendingLocal) names.add(_employees.firstWhere((e) => _effectiveUserId(e) == p['employeeId'], orElse: () => Employee.empty()).fullName);

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text('${shift.name} (${_formatTime(shift.startTime)}-${_formatTime(shift.endTime)})',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF18181B))),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(names.isEmpty ? '—' : names.join(', '),
                          style: TextStyle(fontSize: 11, color: names.isEmpty ? Colors.grey : const Color(0xFF18181B))),
                      ),
                      SizedBox(width: 30, child: Text('${names.length}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF0891B2)))),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 4),
            ],
          ),
        );
      }),
    );
  }

  void _exportShiftCentricExcel() {
    try {
      final days = List.generate(7, (i) => _selectedWeekStart.add(Duration(days: i)));
      final dayNames = ['Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'CN'];
      final dateFormat = DateFormat('dd/MM');

      final wb = excel_lib.Excel.createExcel();
      final sheet = wb['Theo ca'];
      wb.delete('Sheet1');

      // Title
      final weekEnd = _selectedWeekStart.add(const Duration(days: 6));
      final weekNumber = _getWeekNumber(_selectedWeekStart);
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = excel_lib.TextCellValue('THEO CA LÀM VIỆC');
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value =
          excel_lib.TextCellValue('Tuần $weekNumber: ${DateFormat('dd/MM/yyyy').format(_selectedWeekStart)} - ${DateFormat('dd/MM/yyyy').format(weekEnd)}${_selectedDepartment != null ? ' | Phòng ban: $_selectedDepartment' : ''}');

      // Header
      const hRow = 3;
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: hRow)).value = excel_lib.TextCellValue('CA LÀM VIỆC');
      for (int i = 0; i < 7; i++) {
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: i + 1, rowIndex: hRow)).value =
            excel_lib.TextCellValue('${dayNames[i]} ${dateFormat.format(days[i])}');
      }
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: hRow)).value = excel_lib.TextCellValue('TỔNG NV');

      // Data rows
      int row = hRow + 1;
      for (final shift in _shifts) {
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
            excel_lib.TextCellValue('${shift.name} (${_formatTime(shift.startTime)}-${_formatTime(shift.endTime)})');
        int total = 0;
        for (int d = 0; d < 7; d++) {
          final day = days[d];
          final schedules = _getSchedulesForShiftDay(shift.id, day);
          final pendingLocal = _getPendingForShiftDay(shift.id, day);
          final submittedRegs = _getRegistrationsForShiftDay(shift.id, day);
          final names = <String>[];
          for (final ws in schedules) {
            names.add(_employees.firstWhere((e) => _effectiveUserId(e) == ws.employeeUserId, orElse: () => Employee.empty()).fullName);
          }
          for (final p in pendingLocal) {
            names.add(_employees.firstWhere((e) => _effectiveUserId(e) == p['employeeId'], orElse: () => Employee.empty()).fullName);
          }
          for (final r in submittedRegs.where((r) => schedules.every((s) => s.employeeUserId != r.employeeUserId))) {
            names.add(_employees.firstWhere((e) => _effectiveUserId(e) == r.employeeUserId, orElse: () => Employee.empty()).fullName);
          }
          total += names.length;
          sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: d + 1, rowIndex: row)).value =
              excel_lib.TextCellValue(names.join(', '));
        }
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row)).value = excel_lib.IntCellValue(total);
        row++;
      }

      // Legend
      row += 1;
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = excel_lib.TextCellValue('CHÚ THÍCH:');
      row++;
      for (final s in _shifts) {
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
            excel_lib.TextCellValue('${s.name}: ${_formatTime(s.startTime)} - ${_formatTime(s.endTime)}');
        row++;
      }

      _downloadExcel(wb, 'TheoCalamViec');
    } catch (e) {
      appNotification.showError(title: 'Lỗi xuất Excel', message: '$e');
    }
  }

  void _exportScheduleTableExcel() {
    try {
      final days = List.generate(7, (i) => _selectedWeekStart.add(Duration(days: i)));
      final dayNames = ['Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'CN'];
      final dateFormat = DateFormat('dd/MM');
      final emps = _filteredEmployees;

      final wb = excel_lib.Excel.createExcel();
      final sheet = wb['DangKy'];
      wb.delete('Sheet1');

      // Title
      final weekEnd = _selectedWeekStart.add(const Duration(days: 6));
      final weekNumber = _getWeekNumber(_selectedWeekStart);
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = excel_lib.TextCellValue('ĐĂNG KÝ CHỜ DUYỆT - LỊCH LÀM VIỆC THEO NHÂN VIÊN');
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value =
          excel_lib.TextCellValue('Tuần $weekNumber: ${DateFormat('dd/MM/yyyy').format(_selectedWeekStart)} - ${DateFormat('dd/MM/yyyy').format(weekEnd)}${_selectedDepartment != null ? ' | Phòng ban: $_selectedDepartment' : ''}');

      // Header
      const hRow = 3;
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: hRow)).value = excel_lib.TextCellValue('NHÂN VIÊN');
      for (int i = 0; i < 7; i++) {
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: i + 1, rowIndex: hRow)).value =
            excel_lib.TextCellValue('${dayNames[i]} ${dateFormat.format(days[i])}');
      }
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: hRow)).value = excel_lib.TextCellValue('TỔNG CA');

      int row = hRow + 1;
      for (final employee in emps) {
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
            excel_lib.TextCellValue('${employee.fullName} (${employee.employeeCode})');
        int totalShifts = 0;
        for (int d = 0; d < 7; d++) {
          final day = days[d];
          final effectiveId = _effectiveUserId(employee);
          final schedules = _getSchedulesForDay(effectiveId, day);
          final pendingRegs = _getPendingRegistrations(effectiveId, day);
          final submittedRegs = _getRegistrationsForDay(effectiveId, day);
          final items = <String>[];
          for (final ws in schedules) {
            if (ws.isDayOff) {
              items.add('Nghỉ');
            } else {
              final shift = _shifts.firstWhere((s) => s.id == ws.shiftId, orElse: () => Shift(id: '', name: 'Ca', code: '', startTime: '', endTime: '', isActive: true, createdAt: DateTime.now()));
              items.add(shift.name);
              totalShifts++;
            }
          }
          for (final p in pendingRegs) {
            if (p['isDayOff'] == true) {
              items.add('Nghỉ (chờ)');
            } else {
              final shift = _shifts.firstWhere((s) => s.id == p['shiftId'], orElse: () => Shift(id: '', name: 'Ca', code: '', startTime: '', endTime: '', isActive: true, createdAt: DateTime.now()));
              items.add('${shift.name} (chờ)');
              totalShifts++;
            }
          }
          for (final r in submittedRegs.where((r) => schedules.isEmpty)) {
            if (r.isDayOff) {
              items.add('Nghỉ');
            } else {
              final shift = r.shiftId != null ? _shifts.firstWhere((s) => s.id == r.shiftId, orElse: () => Shift(id: '', name: 'Ca', code: '', startTime: '', endTime: '', isActive: true, createdAt: DateTime.now())) : null;
              final statusLabel = r.status == ScheduleRegistrationStatus.approved ? '✓' : r.status == ScheduleRegistrationStatus.rejected ? '✗' : '⏳';
              items.add('${shift?.name ?? "Ca"} $statusLabel');
              if (r.status == ScheduleRegistrationStatus.approved && !r.isDayOff) totalShifts++;
            }
          }
          sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: d + 1, rowIndex: row)).value =
              excel_lib.TextCellValue(items.join(', '));
        }
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row)).value = excel_lib.IntCellValue(totalShifts);
        row++;
      }

      // Legend
      row += 1;
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = excel_lib.TextCellValue('CHÚ THÍCH:');
      row++;
      for (final s in _shifts) {
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
            excel_lib.TextCellValue('${s.name}: ${_formatTime(s.startTime)} - ${_formatTime(s.endTime)}');
        row++;
      }
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
          excel_lib.TextCellValue('✓ Đã duyệt  |  ⏳ Chờ duyệt  |  ✗ Từ chối  |  (chờ) Chờ gửi');

      _downloadExcel(wb, 'DangKyChoDuyet');
    } catch (e) {
      appNotification.showError(title: 'Lỗi xuất Excel', message: '$e');
    }
  }

  void _exportApprovedExcel() {
    try {
      final days = List.generate(7, (i) => _selectedWeekStart.add(Duration(days: i)));
      final dayNames = ['Thứ 2', 'Thứ 3', 'Thứ 4', 'Thứ 5', 'Thứ 6', 'Thứ 7', 'CN'];
      final dateFormat = DateFormat('dd/MM');
      final emps = _filteredEmployees;

      final wb = excel_lib.Excel.createExcel();
      final sheet = wb['DaDuyet'];
      wb.delete('Sheet1');

      // Title
      final weekEnd = _selectedWeekStart.add(const Duration(days: 6));
      final weekNumber = _getWeekNumber(_selectedWeekStart);
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = excel_lib.TextCellValue('LỊCH LÀM VIỆC ĐÃ DUYỆT');
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value =
          excel_lib.TextCellValue('Tuần $weekNumber: ${DateFormat('dd/MM/yyyy').format(_selectedWeekStart)} - ${DateFormat('dd/MM/yyyy').format(weekEnd)}${_selectedDepartment != null ? ' | Phòng ban: $_selectedDepartment' : ''}');

      // Header
      const hRow = 3;
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: hRow)).value = excel_lib.TextCellValue('NHÂN VIÊN');
      for (int i = 0; i < 7; i++) {
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: i + 1, rowIndex: hRow)).value =
            excel_lib.TextCellValue('${dayNames[i]} ${dateFormat.format(days[i])}');
      }
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: hRow)).value = excel_lib.TextCellValue('TỔNG CA');

      int row = hRow + 1;
      for (final employee in emps) {
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
            excel_lib.TextCellValue('${employee.fullName} (${employee.employeeCode})');
        int totalApproved = 0;
        for (int d = 0; d < 7; d++) {
          final day = days[d];
          final effectiveId = _effectiveUserId(employee);
          final confirmedSchedules = _getSchedulesForDay(effectiveId, day);
          final approvedRegs = _getRegistrationsForDay(effectiveId, day)
              .where((r) => r.status == ScheduleRegistrationStatus.approved)
              .toList();
          final items = <String>[];
          for (final ws in confirmedSchedules) {
            if (ws.isDayOff) {
              items.add('Nghỉ');
            } else {
              final shift = _shifts.firstWhere((s) => s.id == ws.shiftId, orElse: () => Shift(id: '', name: 'Ca', code: '', startTime: '', endTime: '', isActive: true, createdAt: DateTime.now()));
              items.add('${shift.name} (${_formatTime(shift.startTime)}-${_formatTime(shift.endTime)})');
              totalApproved++;
            }
          }
          for (final reg in approvedRegs.where((r) => confirmedSchedules.every((s) => s.shiftId != r.shiftId || s.employeeUserId != r.employeeUserId))) {
            if (reg.isDayOff) {
              items.add(reg.note ?? 'Nghỉ');
            } else {
              final shift = reg.shiftId != null ? _shifts.firstWhere((s) => s.id == reg.shiftId, orElse: () => Shift(id: '', name: 'Ca', code: '', startTime: '', endTime: '', isActive: true, createdAt: DateTime.now())) : null;
              items.add('${shift?.name ?? "Ca"} (${shift != null ? "${_formatTime(shift.startTime)}-${_formatTime(shift.endTime)}" : ""})');
              totalApproved++;
            }
          }
          sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: d + 1, rowIndex: row)).value =
              excel_lib.TextCellValue(items.join(', '));
        }
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row)).value = excel_lib.IntCellValue(totalApproved);
        row++;
      }

      // Legend
      row += 1;
      sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = excel_lib.TextCellValue('CHÚ THÍCH:');
      row++;
      for (final s in _shifts) {
        sheet.cell(excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value =
            excel_lib.TextCellValue('${s.name}: ${_formatTime(s.startTime)} - ${_formatTime(s.endTime)}');
        row++;
      }

      _downloadExcel(wb, 'LichDaDuyet');
    } catch (e) {
      appNotification.showError(title: 'Lỗi xuất Excel', message: '$e');
    }
  }

  void _downloadExcel(excel_lib.Excel wb, String fileNamePrefix) {
    final bytes = wb.encode();
    if (bytes != null) {
      final fileName = '${fileNamePrefix}_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.xlsx';
      file_saver.saveFileBytes(bytes, fileName, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      appNotification.showSuccess(title: 'Xuất Excel', message: 'Đã xuất file $fileName');
    }
  }

  Widget _buildMobileScheduleCards(List<Employee> pageEmps, List<DateTime> days, List<String> dayNames, DateFormat dateFormat) {
    if (pageEmps.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text('Chưa có nhân viên', style: TextStyle(color: Colors.grey[400]))),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: pageEmps.length,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemBuilder: (context, index) {
          final employee = pageEmps[index];
          int totalShifts = 0;
          final dayWidgets = <Widget>[];
          for (int di = 0; di < 7; di++) {
            final day = days[di];
            final effectiveId = _effectiveUserId(employee);
            final schedules = _getSchedulesForDay(effectiveId, day);
            final pendingRegs = _getPendingRegistrations(effectiveId, day);
            final submittedRegs = _getRegistrationsForDay(effectiveId, day);
          totalShifts += schedules.where((s) => !s.isDayOff).length;
          if (pendingRegs.isNotEmpty && pendingRegs.first['isDayOff'] != true) {
            totalShifts += pendingRegs.length;
          }
          totalShifts += submittedRegs.where((r) => r.status == ScheduleRegistrationStatus.approved && !r.isDayOff && schedules.isEmpty).length;
          String shiftLabel = '—';
          Color shiftColor = const Color(0xFF71717A);
          Color bgColor = Colors.transparent;
          if (pendingRegs.isNotEmpty) {
            if (pendingRegs.first['isDayOff'] == true) {
              shiftLabel = pendingRegs.first['note'] ?? 'Nghỉ phép';
              shiftColor = const Color(0xFF856404);
              bgColor = const Color(0xFFFFF3CD);
            } else {
              final names = pendingRegs.map((reg) {
                final shift = _shifts.firstWhere((s) => s.id == reg['shiftId'], orElse: () => Shift(id: '', name: 'Ca', code: '', startTime: '', endTime: '', isActive: true, createdAt: DateTime.now()));
                return shift.name;
              }).toList();
              shiftLabel = names.join(', ');
              shiftColor = const Color(0xFF856404);
              bgColor = const Color(0xFFFFF3CD);
            }
          } else if (schedules.isNotEmpty) {
            final dayOff = schedules.where((s) => s.isDayOff).firstOrNull;
            if (dayOff != null) {
              shiftLabel = dayOff.note ?? 'Nghỉ phép';
              shiftColor = const Color(0xFF059669);
              bgColor = const Color(0xFFD1FAE5);
            } else {
              final names = schedules.map((s) {
                final shift = s.shiftId != null ? _shifts.firstWhere((sh) => sh.id == s.shiftId, orElse: () => Shift(id: '', name: 'Ca', code: '', startTime: '', endTime: '', isActive: true, createdAt: DateTime.now())) : null;
                return shift?.name ?? 'Ca';
              }).toList();
              shiftLabel = names.join(', ');
              shiftColor = const Color(0xFF1E3A5F);
              bgColor = const Color(0xFF1E3A5F).withValues(alpha: 0.08);
            }
          } else if (submittedRegs.isNotEmpty) {
            final first = submittedRegs.first;
            if (first.status == ScheduleRegistrationStatus.pending) {
              shiftLabel = 'Chờ duyệt';
              shiftColor = const Color(0xFFF59E0B);
              bgColor = const Color(0xFFFEF3C7);
            } else if (first.status == ScheduleRegistrationStatus.rejected) {
              shiftLabel = 'Từ chối';
              shiftColor = const Color(0xFFEF4444);
              bgColor = const Color(0xFFFEE2E2);
            } else {
              final shift = first.shiftId != null ? _shifts.firstWhere((s) => s.id == first.shiftId, orElse: () => Shift(id: '', name: 'Ca', code: '', startTime: '', endTime: '', isActive: true, createdAt: DateTime.now())) : null;
              shiftLabel = shift?.name ?? 'Đã duyệt';
              shiftColor = const Color(0xFF1E3A5F);
              bgColor = const Color(0xFFD1FAE5);
            }
          }
          dayWidgets.add(
            InkWell(
              onTap: () => _showRegisterDialog(employee, day),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text('${dayNames[di]} ${dateFormat.format(day)}', style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(shiftLabel, style: TextStyle(fontSize: 12, color: shiftColor, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4E4E7)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(employee.fullName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF18181B))),
                          Text(employee.phone ?? employee.employeeCode, style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
                        ]),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: totalShifts > 0 ? const Color(0xFF1E3A5F).withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('$totalShifts ca', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: totalShifts > 0 ? const Color(0xFF1E3A5F) : Colors.grey)),
                      ),
                    ],
                  ),
                  const Divider(height: 12),
                  ...dayWidgets,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileShiftCentricCards(List<DateTime> days, List<String> dayNames, DateFormat dateFormat) {
    if (_shifts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text('Chưa có ca', style: TextStyle(color: Colors.grey[400]))),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _shifts.length,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemBuilder: (context, index) {
        final shift = _shifts[index];
        int totalEmployees = 0;
        final dayWidgets = <Widget>[];
        for (int di = 0; di < 7; di++) {
          final day = days[di];
          final schedules = _getSchedulesForShiftDay(shift.id, day);
          final pendingLocal = _getPendingForShiftDay(shift.id, day);
          final submittedRegs = _getRegistrationsForShiftDay(shift.id, day);
          totalEmployees += schedules.length + pendingLocal.length +
              submittedRegs.where((r) => r.status != ScheduleRegistrationStatus.rejected && schedules.every((s) => s.employeeUserId != r.employeeUserId)).length;
          final empNames = <Widget>[];
          for (final ws in schedules) {
            final empName = _employees.firstWhere((e) => _effectiveUserId(e) == ws.employeeUserId, orElse: () => Employee.empty()).fullName;
            empNames.add(Container(
              margin: const EdgeInsets.only(right: 4, bottom: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFF1E3A5F).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(empName, style: const TextStyle(fontSize: 10, color: Color(0xFF1E3A5F), fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
            ));
          }
          for (final reg in pendingLocal) {
            final empName = _employees.firstWhere((e) => _effectiveUserId(e) == reg['employeeId'], orElse: () => Employee.empty()).fullName;
            empNames.add(Container(
              margin: const EdgeInsets.only(right: 4, bottom: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: const Color(0xFFFFC107).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4), border: Border.all(color: const Color(0xFFFFC107), width: 1)),
              child: Text(empName, style: const TextStyle(fontSize: 10, color: Color(0xFF856404), fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
            ));
          }
          dayWidgets.add(
            InkWell(
              onTap: Provider.of<PermissionProvider>(context, listen: false).canEdit('WorkSchedule') ? () => _showAssignEmployeeToShiftDialog(shift, day) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text('${dayNames[di]} ${dateFormat.format(day)}', style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: empNames.isEmpty
                          ? Text('—', style: TextStyle(fontSize: 12, color: Colors.grey[300]))
                          : Wrap(spacing: 4, runSpacing: 2, children: empNames),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4E4E7)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(shift.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF0891B2))),
                          Text('${_formatTime(shift.startTime)} - ${_formatTime(shift.endTime)}', style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
                        ]),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: totalEmployees > 0 ? const Color(0xFF0891B2).withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('$totalEmployees NV', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: totalEmployees > 0 ? const Color(0xFF0891B2) : Colors.grey)),
                      ),
                    ],
                  ),
                  const Divider(height: 12),
                  ...dayWidgets,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileApprovedCards(List<Employee> pageEmps, List<DateTime> days, List<String> dayNames, DateFormat dateFormat) {
    if (pageEmps.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: Text('Chưa có nhân viên', style: TextStyle(color: Colors.grey[400]))),
      );
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: pageEmps.length,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemBuilder: (context, index) {
          final employee = pageEmps[index];
          int totalApproved = 0;
          final dayWidgets = <Widget>[];
          for (int di = 0; di < 7; di++) {
            final day = days[di];
            final effectiveId = _effectiveUserId(employee);
          final confirmedSchedules = _getSchedulesForDay(effectiveId, day);
          final approvedRegs = _getRegistrationsForDay(effectiveId, day)
              .where((r) => r.status == ScheduleRegistrationStatus.approved)
              .toList();
          String shiftLabel = '—';
          Color shiftColor = const Color(0xFF71717A);
          Color bgColor = Colors.transparent;
          final items = <String>[];
          for (final ws in confirmedSchedules) {
            if (ws.isDayOff) {
              items.add('Nghỉ');
            } else {
              final shift = _shifts.firstWhere((s) => s.id == ws.shiftId, orElse: () => Shift(id: '', name: 'Ca', code: '', startTime: '', endTime: '', isActive: true, createdAt: DateTime.now()));
              items.add(shift.name);
              totalApproved++;
            }
          }
          for (final reg in approvedRegs.where((r) => confirmedSchedules.every((s) => s.shiftId != r.shiftId || s.employeeUserId != r.employeeUserId))) {
            if (reg.isDayOff) {
              items.add(reg.note ?? 'Nghỉ');
            } else {
              final shift = reg.shiftId != null ? _shifts.firstWhere((s) => s.id == reg.shiftId, orElse: () => Shift(id: '', name: 'Ca', code: '', startTime: '', endTime: '', isActive: true, createdAt: DateTime.now())) : null;
              items.add(shift?.name ?? 'Ca');
              totalApproved++;
            }
          }
          if (items.isNotEmpty) {
            shiftLabel = items.join(', ');
            final hasLeave = items.any((i) => i == 'Nghỉ' || i.contains('Nghỉ'));
            if (hasLeave && items.length == 1) {
              shiftColor = const Color(0xFF059669);
              bgColor = const Color(0xFFD1FAE5);
            } else {
              shiftColor = const Color(0xFF1E3A5F);
              bgColor = const Color(0xFF1E3A5F).withValues(alpha: 0.08);
            }
          }
          dayWidgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text('${dayNames[di]} ${dateFormat.format(day)}', style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(shiftLabel, style: TextStyle(fontSize: 12, color: shiftColor, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4E4E7)),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(employee.fullName.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF18181B))),
                          Text(employee.department ?? employee.employeeCode, style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
                        ]),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: totalApproved > 0 ? const Color(0xFF1E3A5F).withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('$totalApproved ca', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: totalApproved > 0 ? const Color(0xFF1E3A5F) : Colors.grey)),
                      ),
                    ],
                  ),
                  const Divider(height: 12),
                  ...dayWidgets,
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteRegistration(String regId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xác nhận xóa', style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold)),
        content: const Text('Bạn có chắc chắn muốn xóa đăng ký này?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final result = await _apiService.deleteScheduleRegistration(regId);
      if (mounted) {
        if (result['isSuccess'] == true) {
          appNotification.showSuccess(
            title: 'Xóa đăng ký',
            message: 'Đã xóa đăng ký thành công',
          );
        } else {
          appNotification.showError(
            title: 'Lỗi',
            message: result['message'] ?? 'Không thể xóa đăng ký',
          );
        }
      }
      await _loadSchedules();
      await _loadRegistrations();
    } catch (e) {
      if (mounted) {
        appNotification.showError(
          title: 'Lỗi',
          message: '$e',
        );
      }
    }
  }

  // ══════════════════════════════════════════════
  // Send Schedule Reminder Dialog
  // ══════════════════════════════════════════════
  void _showSendReminderDialog() {
    String? selectedDept = _selectedDepartment;
    final fromDate = _selectedWeekStart;
    final toDate = _selectedWeekStart.add(const Duration(days: 6));
    bool isSending = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.notifications_active, color: Color(0xFFD97706)),
            SizedBox(width: 8),
            Expanded(child: Text('Nhắc nhở đăng ký lịch', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          ]),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Gửi thông báo đến nhân viên chưa đăng ký lịch làm việc cho tuần ${DateFormat('dd/MM').format(fromDate)} - ${DateFormat('dd/MM/yyyy').format(toDate)}.',
                  style: const TextStyle(fontSize: 13, color: Color(0xFF71717A))),
                const SizedBox(height: 16),
                const Text('Phòng ban:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 4),
                DropdownButtonFormField<String?>(
                  value: selectedDept,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Tất cả phòng ban')),
                    ..._departments.map((d) => DropdownMenuItem<String?>(
                      value: d['name']?.toString(),
                      child: Text(d['name']?.toString() ?? ''),
                    )),
                  ],
                  onChanged: (v) => setDialogState(() => selectedDept = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ElevatedButton.icon(
              onPressed: isSending ? null : () async {
                setDialogState(() => isSending = true);
                final result = await _apiService.sendScheduleReminder({
                  'fromDate': fromDate.toIso8601String(),
                  'toDate': toDate.toIso8601String(),
                  if (selectedDept != null) 'department': selectedDept,
                });
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (result['isSuccess'] == true) {
                  final count = result['data'] ?? 0;
                  appNotification.showSuccess(title: 'Thành công', message: 'Đã gửi nhắc nhở đến $count nhân viên');
                } else {
                  appNotification.showError(title: 'Lỗi', message: result['message'] ?? 'Không thể gửi nhắc nhở');
                }
              },
              icon: isSending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send, size: 16),
              label: const Text('Gửi nhắc nhở'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706), foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════
  // Request Shift Coverage Dialog
  // ══════════════════════════════════════════════
  void _showRequestCoverageDialog({Shift? preselectedShift, DateTime? preselectedDate}) {
    Shift? selectedShift = preselectedShift ?? (_shifts.isNotEmpty ? _shifts.first : null);
    DateTime selectedDate = preselectedDate ?? DateTime.now();
    String? selectedDept = _selectedDepartment;
    final messageController = TextEditingController();
    bool isSending = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.group_add, color: Color(0xFF059669)),
            SizedBox(width: 8),
            Expanded(child: Text('Yêu cầu bổ sung ca', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          ]),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Gửi thông báo yêu cầu nhân viên đăng ký bổ sung cho ca làm cụ thể.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF71717A))),
                  const SizedBox(height: 16),
                  const Text('Ca làm việc:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<Shift>(
                    value: selectedShift,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: _shifts.map((s) => DropdownMenuItem<Shift>(
                      value: s,
                      child: Text('${s.name} (${_formatTime(s.startTime)}-${_formatTime(s.endTime)})', style: const TextStyle(fontSize: 13)),
                    )).toList(),
                    onChanged: (v) => setDialogState(() => selectedShift = v),
                  ),
                  const SizedBox(height: 12),
                  const Text('Ngày:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate,
                        firstDate: DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setDialogState(() => selectedDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE4E4E7)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        const Icon(Icons.calendar_today, size: 16, color: Color(0xFF71717A)),
                        const SizedBox(width: 8),
                        Text(DateFormat('EEEE dd/MM/yyyy', 'vi').format(selectedDate), style: const TextStyle(fontSize: 13)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Phòng ban:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String?>(
                    value: selectedDept,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Tất cả phòng ban')),
                      ..._departments.map((d) => DropdownMenuItem<String?>(
                        value: d['name']?.toString(),
                        child: Text(d['name']?.toString() ?? ''),
                      )),
                    ],
                    onChanged: (v) => setDialogState(() => selectedDept = v),
                  ),
                  const SizedBox(height: 12),
                  const Text('Tin nhắn (tùy chọn):', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: messageController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Để trống sẽ dùng tin nhắn mặc định',
                      hintStyle: const TextStyle(fontSize: 12, color: Color(0xFFA1A1AA)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ElevatedButton.icon(
              onPressed: (isSending || selectedShift == null) ? null : () async {
                setDialogState(() => isSending = true);
                final result = await _apiService.requestShiftCoverage({
                  'shiftTemplateId': selectedShift!.id,
                  'date': selectedDate.toIso8601String(),
                  if (selectedDept != null) 'department': selectedDept,
                  if (messageController.text.isNotEmpty) 'message': messageController.text,
                });
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (result['isSuccess'] == true) {
                  final count = result['data'] ?? 0;
                  appNotification.showSuccess(title: 'Thành công', message: 'Đã gửi yêu cầu đến $count nhân viên');
                } else {
                  appNotification.showError(title: 'Lỗi', message: result['message'] ?? 'Không thể gửi yêu cầu');
                }
              },
              icon: isSending ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send, size: 16),
              label: const Text('Gửi yêu cầu'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════
  // Staffing Quota Settings Dialog
  // ══════════════════════════════════════════════
  void _showStaffingQuotaDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(children: [
              Icon(Icons.tune, color: Color(0xFF7C3AED)),
              SizedBox(width: 8),
              Expanded(child: Text('Định mức nhân sự', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            ]),
            content: SizedBox(
              width: 500,
              height: 400,
              child: Column(
                children: [
                  const Text('Cài đặt số lượng nhân viên tối thiểu, tối đa cho mỗi ca theo phòng ban.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF71717A))),
                  const SizedBox(height: 12),
                  Expanded(
                    child: _staffingQuotas.isEmpty
                      ? const Center(child: Text('Chưa có định mức nào', style: TextStyle(color: Color(0xFF71717A))))
                      : ListView.separated(
                          itemCount: _staffingQuotas.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final q = _staffingQuotas[i];
                            return ListTile(
                              dense: true,
                              title: Text(q['shiftName'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              subtitle: Text(
                                '${q['department'] ?? 'Tất cả'} | Min: ${q['minEmployees']} - Max: ${q['maxEmployees']} | Cảnh báo ≤ ${q['warningThreshold']}',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF71717A)),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                                onPressed: () async {
                                  final result = await _apiService.deleteStaffingQuota(q['id']);
                                  if (result['isSuccess'] == true) {
                                    await _loadStaffingQuotas();
                                    if (ctx.mounted) setDialogState(() {});
                                  }
                                },
                              ),
                            );
                          },
                        ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showAddQuotaDialog();
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Thêm định mức'),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED), foregroundColor: Colors.white),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddQuotaDialog() {
    Shift? selectedShift = _shifts.isNotEmpty ? _shifts.first : null;
    String? selectedDept;
    int minEmployees = 1;
    int maxEmployees = 10;
    int warningThreshold = 2;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.add_circle, color: Color(0xFF7C3AED)),
            SizedBox(width: 8),
            Expanded(child: Text('Thêm định mức nhân sự', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          ]),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ca làm việc:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<Shift>(
                    value: selectedShift,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: _shifts.map((s) => DropdownMenuItem<Shift>(
                      value: s,
                      child: Text('${s.name} (${_formatTime(s.startTime)}-${_formatTime(s.endTime)})', style: const TextStyle(fontSize: 13)),
                    )).toList(),
                    onChanged: (v) => setDialogState(() => selectedShift = v),
                  ),
                  const SizedBox(height: 12),
                  const Text('Phòng ban:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String?>(
                    value: selectedDept,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Tất cả phòng ban')),
                      ..._departments.map((d) => DropdownMenuItem<String?>(
                        value: d['name']?.toString(),
                        child: Text(d['name']?.toString() ?? ''),
                      )),
                    ],
                    onChanged: (v) => setDialogState(() => selectedDept = v),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Tối thiểu:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 4),
                        TextFormField(
                          initialValue: '$minEmployees',
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onChanged: (v) => minEmployees = int.tryParse(v) ?? 1,
                        ),
                      ],
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Tối đa:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 4),
                        TextFormField(
                          initialValue: '$maxEmployees',
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onChanged: (v) => maxEmployees = int.tryParse(v) ?? 10,
                        ),
                      ],
                    )),
                  ]),
                  const SizedBox(height: 12),
                  const Text('Ngưỡng cảnh báo (≤ giá trị này sẽ cảnh báo thiếu):', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  TextFormField(
                    initialValue: '$warningThreshold',
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      helperText: 'Nếu số nhân viên ≤ giá trị này, ô lịch sẽ hiện cảnh báo đỏ',
                      helperStyle: const TextStyle(fontSize: 11),
                    ),
                    onChanged: (v) => warningThreshold = int.tryParse(v) ?? 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ElevatedButton.icon(
              onPressed: (isSaving || selectedShift == null) ? null : () async {
                setDialogState(() => isSaving = true);
                final result = await _apiService.upsertStaffingQuota({
                  'shiftTemplateId': selectedShift!.id,
                  if (selectedDept != null) 'department': selectedDept,
                  'minEmployees': minEmployees,
                  'maxEmployees': maxEmployees,
                  'warningThreshold': warningThreshold,
                });
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (result['isSuccess'] == true) {
                  await _loadStaffingQuotas();
                  appNotification.showSuccess(title: 'Thành công', message: 'Đã lưu định mức nhân sự');
                  _showStaffingQuotaDialog(); // Re-open list
                } else {
                  appNotification.showError(title: 'Lỗi', message: result['message'] ?? 'Không thể lưu');
                }
              },
              icon: isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save, size: 16),
              label: const Text('Lưu'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED), foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
