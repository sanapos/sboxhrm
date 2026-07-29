import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/file_saver.dart' as file_saver;
import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' as excel_lib;
import '../services/api_service.dart';
import '../models/hrm.dart';
import '../models/employee.dart';
import '../widgets/loading_widget.dart';
import '../utils/responsive_helper.dart';
import '../l10n/app_localizations.dart';
import '../design_system/design_system.dart';

import '../widgets/notification_overlay.dart';
import '../widgets/app_scroll_safe.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../providers/auth_provider.dart';
import 'main_layout.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/hrm_fab_clearance.dart';
import '../widgets/shift_swap_ui.dart';
import '../utils/leave_salary_shifts.dart';
import '../utils/staffing_quota_utils.dart';
import '../utils/navigation_notifier.dart';
import 'settings_hub_screen.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

class WorkScheduleScreen extends StatefulWidget {
  const WorkScheduleScreen({super.key});

  @override
  State<WorkScheduleScreen> createState() => _WorkScheduleScreenState();
}

class _WorkScheduleScreenState extends State<WorkScheduleScreen>
    with SingleTickerProviderStateMixin {
  PermissionProvider get _perm =>
      Provider.of<PermissionProvider>(context, listen: false);
  bool get _canCancelRegistration =>
      _perm.canDelete('WorkSchedule') || _perm.canCreate('WorkSchedule');

  final ApiService _apiService = ApiService();
  bool _isEmployee = false;
  late TabController _tabController;

  AppLocalizations get _l10n => AppLocalizations.of(context);

  // GlobalKeys for PNG export
  final GlobalKey _scheduleTableKey = GlobalKey();
  final GlobalKey _approvedTableKey = GlobalKey();

  List<WorkSchedule> _schedules = [];
  List<ScheduleRegistration> _registrations = [];
  List<Shift> _shifts = [];
  List<Shift> _allShifts = [];
  List<dynamic> _shiftTemplatesRaw = [];
  String? _myEmployeeHrId;
  List<String> _myAssignedShiftIds = [];
  List<Employee> _employees = [];
  List<Map<String, dynamic>> _departments = [];
  List<Map<String, dynamic>> _branches = [];
  String? _selectedDepartment;
  String? _selectedBranchId;
  bool _isLoading = true;
  DateTime _selectedWeekStart = _getWeekStart(DateTime.now());
  String? _selectedEmployeeId;

  // Pagination
  int _schedulePage = 1;
  int _approvedPage = 1;
  int _schedulePageSize = 50;
  final List<int> _pageSizeOptions = [20, 50, 100, 200];

  /// Employees filtered by selected department
  List<Employee> get _filteredEmployees {
    var list = _employees;
    if (_selectedBranchId != null) {
      list = list.where((e) => e.branchId == _selectedBranchId).toList();
    }
    if (_selectedDepartment == null) return list;
    return list.where((e) => e.department == _selectedDepartment).toList();
  }

  // Pending registrations (local, not submitted yet)
  final List<Map<String, dynamic>> _pendingRegistrations = [];

  // Staffing quotas loaded from server
  List<Map<String, dynamic>> _staffingQuotas = [];
  List<Map<String, dynamic>> _swapColleagues = [];

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
        await _loadShifts();
        await Future.wait([
          _loadEmployeeShiftAssignments(),
          _loadSchedules(),
          _loadRegistrations(),
          _loadSwapColleagues(),
        ]);
      } else {
        await Future.wait([
          _loadShifts(),
          _loadEmployees(),
          _loadDepartments(),
          _loadBranches(),
          _loadSchedules(),
          _loadRegistrations(),
          _loadStaffingQuotas(),
          _loadSwapColleagues(),
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
      _shiftTemplatesRaw = shifts;
      _allShifts = shifts.map((s) => Shift.fromJson(s)).toList();
      _allShifts.sort((a, b) {
        final aTime = a.startTime.replaceAll(RegExp(r'[^0-9:]'), '');
        final bTime = b.startTime.replaceAll(RegExp(r'[^0-9:]'), '');
        return aTime.compareTo(bTime);
      });
      _applyEmployeeShiftFilter();
    });
  }

  Future<void> _loadEmployeeShiftAssignments() async {
    try {
      final results = await Future.wait([
        _apiService.getMyEmployee(),
        _apiService.getMyEmployeeSalaryProfile(),
        _apiService.getShiftSalaryLevels().catchError((_) => <String, dynamic>{}),
      ]);

      var hrId = '';
      final empResp = results[0] as Map<String, dynamic>;
      if (empResp['isSuccess'] == true && empResp['data'] is Map) {
        hrId = (empResp['data'] as Map)['id']?.toString() ?? '';
      }

      final benefit = results[1] as Map<String, dynamic>?;
      final sslResp = results[2] as Map<String, dynamic>;
      final sslData = sslResp['data'];
      final shiftSalaryLevels = (sslData is Map
              ? (sslData['items'] as List? ?? const [])
              : (sslData is List ? sslData : const []))
          .whereType<Map>()
          .map((s) => Map<String, dynamic>.from(s))
          .toList();

      final assigned = LeaveSalaryShifts.assignedShiftIdsForEmployee(
        employeeGuid: hrId,
        shiftTemplates: _shiftTemplatesRaw,
        employeeBenefit: benefit,
        shiftSalaryLevels: shiftSalaryLevels,
      );

      if (!mounted) return;
      setState(() {
        _myEmployeeHrId = hrId.isEmpty ? null : hrId;
        _myAssignedShiftIds = assigned;
        _applyEmployeeShiftFilter();
      });
    } catch (e) {
      debugPrint('Load employee shift assignments error: $e');
    }
  }

  void _applyEmployeeShiftFilter() {
    if (!_isEmployee) {
      _shifts = List<Shift>.from(_allShifts);
      return;
    }
    if (_myAssignedShiftIds.isEmpty) {
      _shifts = [];
      return;
    }
    final allowed = _myAssignedShiftIds.toSet();
    _shifts = _allShifts.where((s) => allowed.contains(s.id)).toList();
  }

  Shift? _shiftById(String? shiftId) {
    if (shiftId == null || shiftId.isEmpty) return null;
    for (final s in _allShifts) {
      if (s.id == shiftId) return s;
    }
    return null;
  }

  String _employeeShiftEmptyMessage() {
    if (_allShifts.isEmpty) return 'Chưa có ca làm việc';
    return 'Chưa cấu hình ca trong thiết lập lương';
  }

  Future<void> _loadEmployees() async {
    final employees = await _apiService.getEmployeesForSelect();
    if (!mounted) return;
    setState(() {
      _employees = employees.map((e) => Employee.fromJson(e)).toList();
    });
  }

  Future<void> _loadDepartments() async {
    try {
      final result =
          await _apiService.getDepartments(pageSize: 200, isActive: true);
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

  Future<void> _loadBranches() async {
    try {
      final result = await _apiService.getBranchesForSelect();
      if (!mounted) return;
      final data = result['data'];
      if (data is List) {
        setState(() {
          _branches =
              data.map((b) => Map<String, dynamic>.from(b as Map)).toList();
        });
      }
    } catch (e) {
      debugPrint('Load branches error: $e');
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

  Future<void> _loadSwapColleagues() async {
    try {
      final result = await _apiService.getShiftSwapColleagues();
      if (!mounted) return;
      if (result['isSuccess'] == true && result['data'] is List) {
        setState(() {
          _swapColleagues = List<Map<String, dynamic>>.from(result['data']);
        });
      }
    } catch (e) {
      debugPrint('Load swap colleagues error: $e');
    }
  }

  /// Get staffing quota for a specific shift (and optionally department)
  Map<String, dynamic>? _getQuotaForShift(String shiftId,
      {String? department}) {
    return StaffingQuotaUtils.pickQuotaForDepartment(
      _staffingQuotas,
      shiftId,
      department: department ?? _selectedDepartment,
    );
  }

  String? _departmentOfEmployee(String employeeUserId) {
    for (final e in _employees) {
      if (_effectiveUserId(e) == employeeUserId || e.id == employeeUserId) {
        return e.department;
      }
    }
    return null;
  }

  Map<String, int> _uniqueEmployeeCountsByDept(String shiftId, DateTime day) {
    final seen = <String>{};
    final counts = <String, int>{};
    void add(String userId) {
      if (userId.isEmpty || !seen.add(userId)) return;
      final dept = (_departmentOfEmployee(userId) ?? '').trim();
      counts[dept] = (counts[dept] ?? 0) + 1;
    }

    for (final s in _getSchedulesForShiftDay(shiftId, day)) {
      add(s.employeeUserId);
    }
    for (final r in _getRegistrationsForShiftDay(shiftId, day)) {
      if (!r.isDayOff) add(r.employeeUserId);
    }
    for (final r in _getPendingForShiftDay(shiftId, day)) {
      add(r['employeeUserId']?.toString() ?? '');
    }
    return counts;
  }

  ShiftDayStaffingStatus _evaluateShiftDayStaffing(String shiftId, DateTime day) {
    return StaffingQuotaUtils.evaluateShiftDay(
      quotas: _staffingQuotas,
      shiftId: shiftId,
      date: day,
      countByDepartment: _uniqueEmployeeCountsByDept(shiftId, day),
      filterDepartment: _selectedDepartment,
    );
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
        _schedules =
            (items as List).map((s) => WorkSchedule.fromJson(s)).toList();
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
        _registrations = (items as List)
            .map((r) => ScheduleRegistration.fromJson(r))
            .toList();
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
        backgroundColor: HrmPageChrome.background,
        body: LoadingWidget(),
      );
    }
    if (_isEmployee) {
      final showSubmitFab = _pendingRegistrations.isNotEmpty &&
          Provider.of<PermissionProvider>(context, listen: false)
              .canCreate('WorkSchedule');
      return Scaffold(
        backgroundColor: HrmPageChrome.background,
        body: HrmFabClearance(
          fabVisible: showSubmitFab,
          extendedFab: true,
          child: _buildEmployeeCalendarView(),
        ),
        floatingActionButton: showSubmitFab
            ? FloatingActionButton.extended(
                onPressed: _submitAllRegistrations,
                backgroundColor: HrmPageChrome.primaryNavy,
                icon: const Icon(Icons.send, size: 18),
                label: Text(tr('Gửi đăng ký (${_pendingRegistrations.length})'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              )
            : null,
      );
    }
    final showSubmitFab = _pendingRegistrations.isNotEmpty &&
        Provider.of<PermissionProvider>(context, listen: false)
            .canCreate('WorkSchedule');
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      body: Column(
        children: [
          _buildWeekSelector(),
          _buildTabBar(),
          Expanded(
            child: HrmFabClearance(
              fabVisible: showSubmitFab,
              extendedFab: true,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTabShiftCentric(),
                  _buildTabPendingRegistrations(),
                  _buildTabApprovedSchedule(),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: showSubmitFab
          ? FloatingActionButton.extended(
              onPressed: _submitAllRegistrations,
              backgroundColor: HrmPageChrome.primaryNavy,
              icon: const Icon(Icons.send, size: 18),
              label: Text(tr('Gửi (${_pendingRegistrations.length})'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
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
        labelColor: HrmPageChrome.primaryNavy,
        unselectedLabelColor: const Color(0xFF71717A),
        indicatorColor: HrmPageChrome.primaryNavy,
        indicatorWeight: 3,
        isScrollable: Responsive.isMobile(context),
        tabAlignment: Responsive.isMobile(context)
            ? TabAlignment.start
            : TabAlignment.fill,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        tabs: [
          Tab(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.work_history, size: 16),
              const SizedBox(width: 6),
              Flexible(
                  child: Text(
                      tr(Responsive.isMobile(context) ? 'Theo ca' : _l10n.byShift),
                      overflow: TextOverflow.ellipsis)),
            ]),
          ),
          Tab(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.hourglass_empty, size: 16),
              const SizedBox(width: 6),
              Flexible(
                  child: Text(
                      tr(Responsive.isMobile(context)
                          ? 'Chờ duyệt'
                          : _l10n.pendingSchedule),
                      overflow: TextOverflow.ellipsis)),
              if (_pendingRegistrations.isNotEmpty ||
                  _registrations
                      .where(
                          (r) => r.status == ScheduleRegistrationStatus.pending)
                      .isNotEmpty) ...[
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    tr('${_pendingRegistrations.length + _registrations.where((r) => r.status == ScheduleRegistrationStatus.pending).length}'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ]),
          ),
          Tab(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_circle, size: 16),
              const SizedBox(width: 6),
              Flexible(
                  child: Text(
                      tr(Responsive.isMobile(context)
                          ? 'Đã duyệt'
                          : _l10n.approvedSchedule),
                      overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildTabShiftCentric() {
    final canExport = Provider.of<PermissionProvider>(context, listen: false)
        .canExport('WorkSchedule');
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
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE4E4E7)),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                _buildLegendDot(HrmPageChrome.primaryNavy, 'Đã xếp lịch'),
                _buildLegendDot(const Color(0xFF059669), 'Đã duyệt'),
                _buildLegendDot(const Color(0xFFD97706), 'Chờ duyệt'),
                _buildLegendDot(const Color(0xFF8B5CF6), 'Chưa gửi'),
                if (_staffingQuotas.isNotEmpty) ...[
                  _buildLegendDot(const Color(0xFF3B82F6), 'Thiếu nhân sự'),
                  _buildLegendDot(const Color(0xFFF59E0B), 'Gần/vượt định mức'),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabPendingRegistrations() {
    final canExport = Provider.of<PermissionProvider>(context, listen: false)
        .canExport('WorkSchedule');
    final canApprove = Provider.of<PermissionProvider>(context, listen: false)
        .canApprove('ScheduleApproval');
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCopyScheduleToolbar(),
          if (canApprove)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: OutlinedButton.icon(
                onPressed: () => NavigationNotifier.goTo(
                    NavigationNotifier.scheduleApproval),
                icon: const Icon(Icons.assignment_turned_in,
                    size: 16, color: Color(0xFFF59E0B)),
                label: Text(tr('Duyệt lịch làm việc'),
                    style: TextStyle(
                        color: Color(0xFFF59E0B), fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFF59E0B)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ),
          if (canExport)
            _buildExportBar(
              onExportExcel: _exportScheduleTableExcel,
              onExportPng: () =>
                  _exportTableToPng(_scheduleTableKey, 'DangKyChoDuyet'),
            ),
          RepaintBoundary(
            key: _scheduleTableKey,
            child: Container(
              color: const Color(0xFFFAFAFA),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildExportHeader(
                        'ĐĂNG KÝ CHỜ DUYỆT', const Color(0xFFF59E0B)),
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
    final canExport = Provider.of<PermissionProvider>(context, listen: false)
        .canExport('WorkSchedule');
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canExport)
            _buildExportBar(
              onExportExcel: _exportApprovedExcel,
              onExportPng: () =>
                  _exportTableToPng(_approvedTableKey, 'LichDaDuyet'),
            ),
          RepaintBoundary(
            key: _approvedTableKey,
            child: Container(
              color: const Color(0xFFFAFAFA),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildExportHeader(
                        'LỊCH LÀM VIỆC ĐÃ DUYỆT', HrmPageChrome.primaryNavy),
                    _buildApprovedGrid(),
                    _buildCompactLegend(),
                  ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportBar(
      {VoidCallback? onExportExcel, VoidCallback? onExportPng}) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (onExportExcel != null)
            OutlinedButton.icon(
              onPressed: onExportExcel,
              icon: const Icon(Icons.table_chart_outlined, size: 14),
              label: Text(tr('Excel'), style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF22C55E),
                side: const BorderSide(color: Color(0xFF22C55E)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
              ),
            ),
          if (onExportExcel != null) const SizedBox(width: 6),
          if (onExportPng != null)
            OutlinedButton.icon(
              onPressed: onExportPng,
              icon: const Icon(Icons.image_outlined, size: 14),
              label: Text(tr('PNG'), style: TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(
                foregroundColor: HrmPageChrome.primaryNavy,
                side: const BorderSide(color: HrmPageChrome.primaryNavy),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
    final days =
        List.generate(7, (i) => _selectedWeekStart.add(Duration(days: i)));
    final dayLabels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    final now = DateTime.now();
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final myUserId = authProvider.user?.id;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: ShiftSwapFlowHelpBanner(
            compact: true,
            onTapDetail: () {
              NavigationNotifier.scheduleApprovalTab.value = 3;
              NavigationNotifier.goTo(NavigationNotifier.scheduleApproval);
            },
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
                  decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.chevron_left,
                      size: 20, color: Color(0xFF71717A)),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _goToThisWeek,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                      color: HrmPageChrome.primaryNavy,
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.today, size: 18, color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: _nextWeek,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.chevron_right,
                      size: 20, color: Color(0xFF71717A)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    tr('T$weekNumber (${dateFormat.format(_selectedWeekStart)}-${dateFormat.format(weekEnd)})'),
                    style: const TextStyle(
                        color: Color(0xFF18181B),
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
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
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2))
                    ],
                  ),
                  child: Column(
                    children: [
                      // Header row: empty corner + day columns
                      Container(
                        decoration: BoxDecoration(
                          color:
                              HrmPageChrome.primaryNavy.withValues(alpha: 0.06),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(12)),
                        ),
                        child: Row(
                          children: [
                            // Corner cell
                            Container(
                              width: 90,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 6),
                              decoration: const BoxDecoration(
                                  border: Border(
                                      right: BorderSide(
                                          color: Color(0xFFE4E4E7)))),
                              child: Text(tr('Ca / Ngày'),
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: HrmPageChrome.primaryNavy),
                                  textAlign: TextAlign.center),
                            ),
                            // Day columns
                            ...List.generate(7, (di) {
                              final day = days[di];
                              final isToday = day.year == now.year &&
                                  day.month == now.month &&
                                  day.day == now.day;
                              final isSun = di == 6;
                              return Expanded(
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isToday
                                        ? HrmPageChrome.primaryNavy
                                            .withValues(alpha: 0.1)
                                        : null,
                                    border: di < 6
                                        ? const Border(
                                            right: BorderSide(
                                                color: Color(0xFFE4E4E7)))
                                        : null,
                                  ),
                                  child: Column(
                                    children: [
                                      Text(tr(dayLabels[di]),
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: isToday
                                                ? HrmPageChrome.primaryNavy
                                                : (isSun
                                                    ? const Color(0xFFEF4444)
                                                    : const Color(0xFF71717A)),
                                          )),
                                      Text(tr('${day.day}/${day.month}'),
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: isToday
                                                ? HrmPageChrome.primaryNavy
                                                : const Color(0xFF71717A),
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
                        Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(tr(_employeeShiftEmptyMessage()),
                                style: const TextStyle(
                                    color: Color(0xFF71717A))))
                      else
                        ..._shifts.asMap().entries.map((entry) {
                          final si = entry.key;
                          final shift = entry.value;
                          final isLast = si == _shifts.length - 1;
                          return Container(
                            decoration: BoxDecoration(
                              border: isLast
                                  ? null
                                  : const Border(
                                      bottom:
                                          BorderSide(color: Color(0xFFE4E4E7))),
                            ),
                            child: Row(
                              children: [
                                // Shift name cell
                                Container(
                                  width: 90,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 10, horizontal: 6),
                                  decoration: const BoxDecoration(
                                      border: Border(
                                          right: BorderSide(
                                              color: Color(0xFFE4E4E7)))),
                                  child: Column(
                                    children: [
                                      Text(tr(shift.name),
                                          style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF18181B)),
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      Text(
                                          tr('${_formatTime(shift.startTime)}-${_formatTime(shift.endTime)}'),
                                          style: const TextStyle(
                                              fontSize: 9,
                                              color: Color(0xFF71717A)),
                                          textAlign: TextAlign.center),
                                    ],
                                  ),
                                ),
                                // Day cells for this shift
                                ...List.generate(7, (di) {
                                  final day = days[di];
                                  final isToday = day.year == now.year &&
                                      day.month == now.month &&
                                      day.day == now.day;
                                  return Expanded(
                                      child: _buildEmpGridCell(
                                          shift, day, di, isToday, myUserId));
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE4E4E7)),
                  ),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      _buildLegendDot(HrmPageChrome.primaryNavy, 'Đã xếp lịch'),
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
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: color, width: 1.5))),
        const SizedBox(width: 4),
        Text(tr(label),
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildEmpGridCell(
      Shift shift, DateTime day, int dayIndex, bool isToday, String? myUserId) {
    // Check if already has confirmed work schedule
    final hasSchedule = _schedules.any((s) =>
        s.shiftId == shift.id &&
        s.date.day == day.day &&
        s.date.month == day.month &&
        s.date.year == day.year);
    // Check submitted registrations
    final reg = _registrations.cast<ScheduleRegistration?>().firstWhere(
        (r) =>
            r!.shiftId == shift.id &&
            r.date.day == day.day &&
            r.date.month == day.month &&
            r.date.year == day.year,
        orElse: () => null);
    // Check local pending
    final hasPendingLocal = _pendingRegistrations.any((r) =>
        r['shiftId'] == shift.id &&
        (r['date'] as DateTime).day == day.day &&
        (r['date'] as DateTime).month == day.month &&
        (r['date'] as DateTime).year == day.year);

    // Determine cell state
    Color bgColor;
    Color borderColor;
    Widget? icon;

    if (hasSchedule) {
      bgColor = HrmPageChrome.primaryNavy.withValues(alpha: 0.12);
      borderColor = HrmPageChrome.primaryNavy;
      icon = const Icon(Icons.check, size: 18, color: HrmPageChrome.primaryNavy);
    } else if (reg != null &&
        reg.status == ScheduleRegistrationStatus.approved) {
      bgColor = const Color(0xFF059669).withValues(alpha: 0.12);
      borderColor = const Color(0xFF059669);
      icon = const Icon(Icons.check_circle, size: 18, color: Color(0xFF059669));
    } else if (reg != null &&
        reg.status == ScheduleRegistrationStatus.pending) {
      bgColor = const Color(0xFFFEF3C7);
      borderColor = const Color(0xFFD97706);
      icon =
          const Icon(Icons.hourglass_empty, size: 16, color: Color(0xFFD97706));
    } else if (reg != null &&
        reg.status == ScheduleRegistrationStatus.rejected) {
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
      onTap: () =>
          _toggleEmpShiftDay(shift, day, hasSchedule, reg, hasPendingLocal),
      child: Container(
        height: 48,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(
              color: borderColor,
              width:
                  (hasSchedule || reg != null || hasPendingLocal) ? 1.5 : 0.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(
            child: icon ?? Icon(Icons.add, size: 14, color: Colors.grey[300])),
      ),
    );
  }

  void _toggleEmpShiftDay(Shift shift, DateTime day, bool hasSchedule,
      ScheduleRegistration? reg, bool hasPendingLocal) {
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
  void _showPendingActionSheet(
      Shift shift, DateTime day, ScheduleRegistration reg) {
    showAppSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.hourglass_empty,
                  color: Color(0xFFD97706), size: 20),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(tr('${shift.name} - ${day.day}/${day.month}'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(tr('Chờ duyệt'),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFD97706))),
              ),
            ]),
            if (_canCancelRegistration) ...[
              const SizedBox(height: 16),
              _actionTile(Icons.delete_outline, 'Xóa đăng ký',
                  'Hủy đăng ký ca này', const Color(0xFFEF4444), () {
                Navigator.pop(ctx);
                _deleteMyRegistration(reg, shift, day);
              }),
            ],
          ]),
        ),
      ),
    );
  }

  // === BOTTOM SHEET: Rejected registration actions ===
  void _showRejectedActionSheet(
      Shift shift, DateTime day, ScheduleRegistration reg) {
    showAppSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Row(children: [
              const Icon(Icons.cancel, color: Color(0xFFEF4444), size: 20),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(tr('${shift.name} - ${day.day}/${day.month}'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(tr('Từ chối'),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFEF4444))),
              ),
            ]),
            if (reg.rejectionReason != null &&
                reg.rejectionReason!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(tr('Lý do: ${reg.rejectionReason}'),
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFFEF4444))),
              ),
            ],
            if (_canCancelRegistration) ...[
              const SizedBox(height: 16),
              _actionTile(Icons.delete_outline, 'Xóa đăng ký',
                  'Xóa đăng ký bị từ chối', const Color(0xFFEF4444), () {
                Navigator.pop(ctx);
                _deleteMyRegistration(reg, shift, day);
              }),
            ],
          ]),
        ),
      ),
    );
  }

  // === BOTTOM SHEET: Scheduled/Approved shift actions (swap, leave) ===
  void _showShiftActionSheet(Shift shift, DateTime day,
      {ScheduleRegistration? reg,
      bool isScheduled = false,
      bool isApproved = false}) {
    showAppSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Row(children: [
              Icon(isScheduled ? Icons.check : Icons.check_circle,
                  color: isScheduled
                      ? HrmPageChrome.primaryNavy
                      : const Color(0xFF059669),
                  size: 20),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(tr('${shift.name} - ${day.day}/${day.month}'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isScheduled
                      ? HrmPageChrome.primaryNavy.withValues(alpha: 0.1)
                      : const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(tr(isScheduled ? 'Đã xếp lịch' : 'Đã duyệt'),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isScheduled
                            ? HrmPageChrome.primaryNavy
                            : const Color(0xFF059669))),
              ),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              const SizedBox(width: 28),
              Text(
                  tr('${_formatTime(shift.startTime)} - ${_formatTime(shift.endTime)}'),
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF71717A))),
            ]),
            const SizedBox(height: 16),
            _actionTile(
                Icons.swap_horiz,
                'Đổi ca',
                'Yêu cầu đổi ca với nhân viên khác',
                HrmPageChrome.primaryNavy, () {
              Navigator.pop(ctx);
              _showSwapDialog(shift, day);
            }),
            const SizedBox(height: 6),
            _actionTile(Icons.event_busy, 'Xin nghỉ phép',
                'Gửi đơn xin nghỉ phép ca này', const Color(0xFFF59E0B), () {
              Navigator.pop(ctx);
              _showLeaveShiftDialog(shift, day);
            }),
          ]),
        ),
      ),
    );
  }

  Widget _actionTile(IconData icon, String title, String subtitle, Color color,
      VoidCallback onTap) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(tr(title),
          style: TextStyle(
              fontWeight: FontWeight.w600, fontSize: 14, color: color)),
      subtitle: Text(tr(subtitle),
          style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
      trailing: Icon(Icons.chevron_right, color: color.withValues(alpha: 0.5)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      tileColor: color.withValues(alpha: 0.03),
    );
  }

  // === DELETE REGISTRATION (employee self-service) ===
  Future<void> _deleteMyRegistration(
      ScheduleRegistration reg, Shift shift, DateTime day) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(children: [
          Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
          SizedBox(width: 8),
          Text(tr('Xác nhận xóa')),
        ]),
        content:
            Text(tr('Xóa đăng ký ${shift.name} ngày ${day.day}/${day.month}?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Hủy'))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            child: Text(tr('Xóa')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await _apiService.deleteScheduleRegistration(reg.id);
    if (result['isSuccess'] == true) {
      appNotification.showSuccess(
          title: 'Đã xóa',
          message: tr('Đã xóa đăng ký ${shift.name} ngày ${day.day}/${day.month}'));
      _loadRegistrations();
    } else {
      appNotification.showError(
          title: 'Lỗi', message: result['message'] ?? 'Không thể xóa đăng ký');
    }
  }

  // === SHIFT SWAP DIALOG ===
  void _showSwapDialog(Shift shift, DateTime day) {
    String? targetUserId;
    String? targetShiftId = shift.id;
    final noteCtrl = TextEditingController();

    final colleagues = _swapColleagues.isNotEmpty
        ? _swapColleagues
        : _employees
            .where((e) =>
                (e.applicationUserId ?? '').isNotEmpty &&
                e.applicationUserId != Provider.of<AuthProvider>(context, listen: false).user?.id)
            .map((e) => {
                  'userId': e.applicationUserId,
                  'fullName': e.fullName,
                  'employeeCode': e.employeeCode,
                })
            .toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        return ScrollableAlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(Icons.swap_horiz, color: HrmPageChrome.primaryNavy),
            SizedBox(width: 8),
            Expanded(child: Text(tr('Đổi ca'), style: TextStyle(fontSize: 16))),
          ]),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const ShiftSwapFlowHelpBanner(compact: true),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Ca hiện tại:'),
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFF71717A))),
                        const SizedBox(height: 4),
                        Text(
                            tr('${shift.name} (${_formatTime(shift.startTime)}-${_formatTime(shift.endTime)})'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(tr('Ngày ${day.day}/${day.month}/${day.year}'),
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF71717A))),
                      ]),
                ),
                const SizedBox(height: 14),
                // Target employee
                DropdownButtonFormField<String>(
                  initialValue: targetUserId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tr('Đồng nghiệp muốn đổi *'),
                    helperText: tr(colleagues.isEmpty
                        ? 'Chưa có danh sách — thử tải lại trang'
                        : 'Cùng phòng ban với bạn'),
                    prefixIcon: const Icon(Icons.person, size: 18),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                  items: colleagues
                      .map((c) => DropdownMenuItem(
                            value: c['userId']?.toString(),
                            child: Text(
                                tr('${c['fullName'] ?? ''} (${c['employeeCode'] ?? ''})'),
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) => setDialogState(() => targetUserId = v),
                ),
                const SizedBox(height: 12),
                // Target shift (optional - can swap for a different shift)
                DropdownButtonFormField<String>(
                  initialValue: targetShiftId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tr('Ca muốn nhận *'),
                    helperText: tr('Thường chọn cùng ca hoặc ca đồng nghiệp đang giữ'),
                    prefixIcon: const Icon(Icons.schedule, size: 18),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                  items: _shifts
                      .map((s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(
                                tr('${s.name} (${_formatTime(s.startTime)}-${_formatTime(s.endTime)})')),
                          ))
                      .toList(),
                  onChanged: (v) => setDialogState(() => targetShiftId = v ?? shift.id),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteCtrl,
                  decoration: InputDecoration(
                    labelText: tr('Ghi chú'),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
            FilledButton.icon(
              onPressed: targetUserId == null || targetShiftId == null
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      await _submitShiftSwap(
                        shift: shift,
                        day: day,
                        targetUserId: targetUserId!,
                        targetShiftId: targetShiftId!,
                        note: noteCtrl.text.trim(),
                      );
                    },
              icon: const Icon(Icons.send, size: 16),
              label: Text(tr('Gửi yêu cầu')),
              style: FilledButton.styleFrom(
                  backgroundColor: HrmPageChrome.primaryNavy),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _submitShiftSwap({
    required Shift shift,
    required DateTime day,
    required String targetUserId,
    required String targetShiftId,
    required String note,
  }) async {
    final result = await _apiService.createShiftSwap(
      targetUserId: targetUserId,
      requesterShiftId: shift.id,
      requesterDate: day,
      targetShiftId: targetShiftId,
      targetDate: day,
      reason: note,
    );
    if (result['isSuccess'] == true) {
      appNotification.showSuccess(
        title: 'Đã gửi',
        message: tr('Đồng nghiệp cần đồng ý, sau đó quản lý duyệt. Xem tiến độ tại Duyệt lịch → Đổi ca.'),
      );
    } else {
      appNotification.showError(
        title: 'Lỗi',
        message: result['message']?.toString() ?? 'Không thể gửi yêu cầu đổi ca',
      );
    }
  }

  // === LEAVE REQUEST PER SHIFT DIALOG ===
  void _showLeaveShiftDialog(Shift shift, DateTime day) {
    int selectedType = 0;
    final reasonCtrl = TextEditingController();

    final leaveTypes = [
      (0, 'Phép năm', Icons.beach_access_rounded, Colors.teal),
      (2, 'Việc riêng có lương', Icons.paid_rounded, AppColors.info),
      (3, 'Việc riêng không lương', Icons.money_off_rounded, Colors.amber),
      (4, 'Ốm đau', Icons.local_hospital_rounded, Colors.red),
      (6, 'Nghỉ bù', Icons.swap_horiz_rounded, Colors.indigo),
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        return ScrollableAlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(Icons.event_busy, color: Color(0xFFF59E0B)),
            SizedBox(width: 8),
            Expanded(
                child: Text(tr('Xin nghỉ phép'), style: TextStyle(fontSize: 16))),
          ]),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Shift info
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(10)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Nghỉ phép cho:'),
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFF71717A))),
                        const SizedBox(height: 4),
                        Text(
                            tr('${shift.name} (${_formatTime(shift.startTime)}-${_formatTime(shift.endTime)})'),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(tr('Ngày ${day.day}/${day.month}/${day.year}'),
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF71717A))),
                      ]),
                ),
                const SizedBox(height: 14),
                // Leave type chips
                Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: leaveTypes.map((t) {
                      final isSelected = selectedType == t.$1;
                      return ChoiceChip(
                        label: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(t.$3,
                              size: 14,
                              color: isSelected ? Colors.white : t.$4),
                          const SizedBox(width: 4),
                          Text(tr(t.$2),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: isSelected ? Colors.white : t.$4)),
                        ]),
                        selected: isSelected,
                        selectedColor: t.$4,
                        backgroundColor: t.$4.withValues(alpha: 0.08),
                        side: BorderSide(
                            color:
                                t.$4.withValues(alpha: isSelected ? 1 : 0.3)),
                        onSelected: (_) =>
                            setDialogState(() => selectedType = t.$1),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList()),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  decoration: InputDecoration(
                    labelText: tr('Lý do'),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
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
              label: Text(tr('Gửi đơn')),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B)),
            ),
          ],
        );
      }),
    );
  }

  Future<void> _submitLeaveForShift(
      {required Shift shift,
      required DateTime day,
      required int type,
      required String reason}) async {
    final result = await _apiService.createLeave(
      shiftIds: [shift.id],
      startDate: DateTime(day.year, day.month, day.day),
      endDate: DateTime(day.year, day.month, day.day),
      type: type,
      reason: reason.isNotEmpty ? reason : null,
    );

    if (result['isSuccess'] == true) {
      appNotification.showSuccess(
          title: 'Đã gửi',
          message: tr('Đơn nghỉ phép ${shift.name} ngày ${day.day}/${day.month} đã được gửi'));
    } else {
      appNotification.showError(
          title: 'Lỗi',
          message: result['message'] ?? 'Không thể gửi đơn nghỉ phép');
    }
  }

  Widget _buildEmpWeekRegistrationsList(List<DateTime> days) {
    final weekStart = DateTime(_selectedWeekStart.year,
        _selectedWeekStart.month, _selectedWeekStart.day);
    final weekEndDate = weekStart.add(const Duration(days: 6));
    final weekRegs = _registrations.where((r) {
      final d = DateTime(r.date.year, r.date.month, r.date.day);
      return !d.isBefore(weekStart) && !d.isAfter(weekEndDate);
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    if (weekRegs.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Đăng ký tuần này (${weekRegs.length})'),
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Color(0xFF18181B))),
          const Divider(height: 12),
          ...weekRegs.map((reg) {
            final shift = _shiftById(reg.shiftId);
            Color statusColor;
            String statusText;
            IconData statusIcon;
            switch (reg.status) {
              case ScheduleRegistrationStatus.approved:
                statusColor = const Color(0xFF059669);
                statusText = 'Đã duyệt';
                statusIcon = Icons.check_circle;
                break;
              case ScheduleRegistrationStatus.rejected:
                statusColor = const Color(0xFFEF4444);
                statusText = 'Từ chối';
                statusIcon = Icons.cancel;
                break;
              default:
                statusColor = const Color(0xFFD97706);
                statusText = 'Chờ duyệt';
                statusIcon = Icons.hourglass_empty;
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(statusIcon, size: 16, color: statusColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr('${DateFormat('E dd/MM', 'vi').format(reg.date)} - ${shift?.name ?? (reg.isDayOff ? 'Nghỉ' : 'Ca')}'),
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF18181B)),
                    ),
                  ),
                  // Action buttons based on status
                  if (_canCancelRegistration &&
                      reg.status == ScheduleRegistrationStatus.pending &&
                      shift != null) ...[
                    InkWell(
                      onTap: () => _deleteMyRegistration(reg, shift, reg.date),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(6)),
                        child: const Icon(Icons.delete_outline,
                            size: 14, color: Color(0xFFEF4444)),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (_canCancelRegistration &&
                      reg.status == ScheduleRegistrationStatus.rejected &&
                      shift != null) ...[
                    InkWell(
                      onTap: () => _deleteMyRegistration(reg, shift, reg.date),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(6)),
                        child: const Icon(Icons.delete_outline,
                            size: 14, color: Color(0xFFEF4444)),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (reg.status == ScheduleRegistrationStatus.approved &&
                      shift != null) ...[
                    InkWell(
                      onTap: () => _showSwapDialog(shift, reg.date),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                            color:
                                HrmPageChrome.primaryNavy.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6)),
                        child: const Icon(Icons.swap_horiz,
                            size: 14, color: HrmPageChrome.primaryNavy),
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => _showLeaveShiftDialog(shift, reg.date),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(6)),
                        child: const Icon(Icons.event_busy,
                            size: 14, color: Color(0xFFF59E0B)),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(tr(statusText),
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: statusColor)),
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
          label: isMobile ? const SizedBox.shrink() : Text(tr(_l10n.prevWeek)),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF71717A),
            side: const BorderSide(color: Color(0xFFE4E4E7)),
            padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 8 : 12, vertical: 8),
            minimumSize: Size.zero,
          ),
        ),
        const SizedBox(width: 6),
        FilledButton.icon(
          onPressed: _goToThisWeek,
          icon: const Icon(Icons.today, size: 16),
          label: isMobile ? const SizedBox.shrink() : Text(tr(_l10n.thisWeek)),
          style: ElevatedButton.styleFrom(
            backgroundColor: HrmPageChrome.primaryNavy,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 8 : 16, vertical: 8),
            minimumSize: Size.zero,
          ),
        ),
        const SizedBox(width: 6),
        OutlinedButton.icon(
          onPressed: _nextWeek,
          icon: isMobile ? const SizedBox.shrink() : Text(tr(_l10n.nextWeek)),
          label: const Icon(Icons.chevron_right, size: 18),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF71717A),
            side: const BorderSide(color: Color(0xFFE4E4E7)),
            padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 8 : 12, vertical: 8),
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
              tr(isMobile
                  ? 'T$weekNumber (${dateFormat.format(_selectedWeekStart)}-${dateFormat.format(weekEnd)})'
                  : 'Tuần $weekNumber (${dateFormat.format(_selectedWeekStart)} - ${dateFormat.format(weekEnd)})'),
              style: const TextStyle(
                  color: Color(0xFF18181B),
                  fontWeight: FontWeight.w600,
                  fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );

    final branchDropdown = _branches.isNotEmpty
        ? DropdownButtonFormField<String?>(
            initialValue: _selectedBranchId,
            isExpanded: true,
            decoration: InputDecoration(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
              filled: true,
              fillColor: const Color(0xFFFAFAFA),
              prefixIcon: const Icon(Icons.account_tree_outlined,
                  size: 16, color: Color(0xFF71717A)),
              isDense: true,
            ),
            hint: Text(tr('Chi nhánh'), style: TextStyle(fontSize: 13)),
            style: const TextStyle(color: Color(0xFF18181B), fontSize: 13),
            items: [
              DropdownMenuItem<String?>(
                  value: null,
                  child: Text(tr('Tất cả chi nhánh'),
                      overflow: TextOverflow.ellipsis)),
              ..._branches.map((b) => DropdownMenuItem<String?>(
                    value: b['id']?.toString(),
                    child: Text(tr(b['name']?.toString() ?? ''),
                        overflow: TextOverflow.ellipsis),
                  )),
            ],
            onChanged: (v) {
              setState(() {
                _selectedBranchId = v;
                _selectedDepartment = null;
                _selectedEmployeeId = null;
              });
              _loadSchedules();
              _loadRegistrations();
            },
          )
        : null;

    final deptDropdown = DropdownButtonFormField<String>(
      initialValue: _selectedDepartment,
      isExpanded: true,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
        prefixIcon:
            const Icon(Icons.business, size: 16, color: Color(0xFF71717A)),
        isDense: true,
      ),
      hint: Text(tr(_l10n.department), style: const TextStyle(fontSize: 13)),
      style: const TextStyle(color: Color(0xFF18181B), fontSize: 13),
      items: [
        DropdownMenuItem<String>(
            value: null, child: Text(tr(_l10n.allDepartments))),
        ..._departments.map((d) => DropdownMenuItem<String>(
              value: d['name']?.toString() ?? '',
              child: Text(tr(d['name']?.toString() ?? ''),
                  overflow: TextOverflow.ellipsis),
            )),
      ],
      onChanged: (value) {
        setState(() {
          _selectedDepartment = value;
          _selectedEmployeeId = null;
        });
        _loadSchedules();
        _loadRegistrations();
      },
    );
    final empDropdown = DropdownButtonFormField<String>(
      initialValue: _selectedEmployeeId,
      isExpanded: true,
      decoration: InputDecoration(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
        prefixIcon:
            const Icon(Icons.person_search, size: 16, color: Color(0xFF71717A)),
        isDense: true,
      ),
      hint: Text(tr(_l10n.employee), style: const TextStyle(fontSize: 13)),
      style: const TextStyle(color: Color(0xFF18181B), fontSize: 13),
      items: [
        DropdownMenuItem<String>(value: null, child: Text(tr(_l10n.allEmployees))),
        ..._filteredEmployees.map((e) => DropdownMenuItem<String>(
              value: _effectiveUserId(e),
              child: Text(tr(e.fullName), overflow: TextOverflow.ellipsis),
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
                  ],
                ),
                ...[
                  const SizedBox(height: 8),
                  if (branchDropdown != null) ...[
                    branchDropdown,
                    const SizedBox(height: 8),
                  ],
                  Row(children: [
                    Expanded(child: deptDropdown),
                    const SizedBox(width: 8),
                    Expanded(child: empDropdown)
                  ]),
                ],
              ],
            )
          : Row(
              children: [
                navRow,
                const Spacer(),
                if (branchDropdown != null) ...[
                  SizedBox(width: 180, child: branchDropdown),
                  const SizedBox(width: 8),
                ],
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
      _buildCopyButton(
          icon: Icons.today,
          label: _l10n.copyDay,
          color: HrmPageChrome.primaryNavy,
          onTap: _showCopyDayDialog),
      _buildCopyButton(
          icon: Icons.date_range,
          label: _l10n.copyWeek,
          color: HrmPageChrome.primaryNavy,
          onTap: _showCopyWeekDialog),
      _buildCopyButton(
          icon: Icons.calendar_month,
          label: _l10n.copyMonth,
          color: HrmPageChrome.primaryNavy,
          onTap: _showCopyMonthDialog),
    ];
    final helpBtn = InkWell(
      onTap: _showScheduleGuide,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(8),
          border:
              Border.all(color: const Color(0xFFFB923C).withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.help_outline, size: 16, color: Color(0xFFFB923C)),
            SizedBox(width: 6),
            Text(tr('Hướng dẫn'),
                style: TextStyle(
                    color: Color(0xFFFB923C),
                    fontWeight: FontWeight.w600,
                    fontSize: 12)),
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
                  const Icon(Icons.copy_all,
                      size: 16, color: HrmPageChrome.primaryNavy),
                  const SizedBox(width: 6),
                  ...buttons.expand((b) => [b, const SizedBox(width: 6)]),
                  helpBtn,
                ],
              ),
            )
          : Row(
              children: [
                const Icon(Icons.copy_all, size: 18, color: HrmPageChrome.primaryNavy),
                const SizedBox(width: 8),
                Text(tr(_l10n.copySchedule),
                    style: const TextStyle(
                        color: Color(0xFF18181B),
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
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
                  const Icon(Icons.manage_accounts,
                      size: 16, color: HrmPageChrome.primaryNavy),
                  const SizedBox(width: 6),
                  ...actionButtons.expand((b) => [b, const SizedBox(width: 6)]),
                ],
              ),
            )
          : Row(
              children: [
                const Icon(Icons.manage_accounts,
                    size: 18, color: HrmPageChrome.primaryNavy),
                const SizedBox(width: 8),
                Text(tr('Quản lý'),
                    style: TextStyle(
                        color: Color(0xFF18181B),
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
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
            Text(tr(label),
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w600, fontSize: 12)),
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
    DateTime calendarMonth =
        DateTime(DateTime.now().year, DateTime.now().month);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return ScrollableAlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.today, color: HrmPageChrome.primaryNavy),
                SizedBox(width: 8),
                Text(tr('Sao chép lịch ngày'),
                    style: TextStyle(
                        color: Color(0xFF18181B), fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: Responsive.dialogWidth(context),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Sao chép lịch từ một ngày sang các ngày khác.'),
                        style:
                            TextStyle(color: Color(0xFF71717A), fontSize: 13)),
                    const SizedBox(height: 16),
                    // Source date picker
                    Text(tr(_l10n.sourceDate),
                        style: const TextStyle(
                            color: Color(0xFF18181B),
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: sourceDate,
                          firstDate: DateTime.now()
                              .subtract(const Duration(days: 365)),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setDialogState(() => sourceDate = picked);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE4E4E7)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today,
                                size: 16, color: Color(0xFF71717A)),
                            const SizedBox(width: 8),
                            Text(
                                tr(DateFormat('dd/MM/yyyy (EEEE)', 'vi')
                                    .format(sourceDate)),
                                style:
                                    const TextStyle(color: Color(0xFF18181B))),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Target dates - inline calendar
                    Row(
                      children: [
                        Text(tr(_l10n.targetDate),
                            style: const TextStyle(
                                color: Color(0xFF18181B),
                                fontWeight: FontWeight.w600)),
                        const Spacer(),
                        if (targetDates.isNotEmpty)
                          TextButton(
                            onPressed: () =>
                                setDialogState(() => targetDates.clear()),
                            child: Text(tr('Xóa tất cả (${targetDates.length})'),
                                style: const TextStyle(
                                    color: Color(0xFFEF4444), fontSize: 12)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildInlineCalendar(
                        calendarMonth,
                        targetDates,
                        setDialogState,
                        (m) => setDialogState(() => calendarMonth = m)),
                    if (targetDates.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: (List.of(targetDates)..sort())
                            .map((d) => Chip(
                                  backgroundColor: const Color(0xFFEFF6FF),
                                  label: Text(
                                      tr(DateFormat('dd/MM (EEE)', 'vi').format(d)),
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF18181B))),
                                  deleteIcon: const Icon(Icons.close, size: 14),
                                  onDeleted: () => setDialogState(
                                      () => targetDates.remove(d)),
                                ))
                            .toList(),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // Employee selection
                    _buildEmployeeMultiSelect(
                      applyToAll: applyToAllEmployees,
                      selectedIds: selectedEmployeeIds,
                      activeColor: HrmPageChrome.primaryNavy,
                      onToggleAll: (v) => setDialogState(() {
                        applyToAllEmployees = v;
                        if (v) selectedEmployeeIds.clear();
                      }),
                      onToggleEmployee: (id, checked) => setDialogState(() {
                        if (checked) {
                          selectedEmployeeIds.add(id);
                        } else {
                          selectedEmployeeIds.remove(id);
                        }
                      }),
                      onSelectAllEmployees: () => setDialogState(() {
                        selectedEmployeeIds =
                            _employees.map((e) => _effectiveUserId(e)).toList();
                      }),
                      onDeselectAllEmployees: () =>
                          setDialogState(() => selectedEmployeeIds.clear()),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr(_l10n.cancel),
                    style: const TextStyle(color: Color(0xFF71717A))),
              ),
              FilledButton.icon(
                onPressed: targetDates.isEmpty ||
                        (!applyToAllEmployees && selectedEmployeeIds.isEmpty)
                    ? null
                    : () {
                        Navigator.pop(context);
                        _executeCopyDay(sourceDate, targetDates,
                            applyToAllEmployees ? null : selectedEmployeeIds);
                      },
                icon: const Icon(Icons.content_copy, size: 16),
                label: Text(tr('Sao chép')),
                style: FilledButton.styleFrom(backgroundColor: HrmPageChrome.primaryNavy),
              ),
            ],
          );
        },
      ),
    );
  }

  // Inline calendar widget for multi-date selection
  Widget _buildInlineCalendar(
      DateTime calendarMonth,
      List<DateTime> selectedDates,
      void Function(void Function()) setDialogState,
      void Function(DateTime) onMonthChanged) {
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
          final isSelected = selectedDates.any((d) =>
              d.year == date.year &&
              d.month == date.month &&
              d.day == date.day);
          final isToday = date.year == today.year &&
              date.month == today.month &&
              date.day == today.day;
          cells.add(Expanded(
            child: GestureDetector(
              onTap: () => setDialogState(() {
                if (isSelected) {
                  selectedDates.removeWhere((d) =>
                      d.year == date.year &&
                      d.month == date.month &&
                      d.day == date.day);
                } else {
                  selectedDates.add(date);
                }
              }),
              child: Container(
                height: 36,
                margin: const EdgeInsets.all(1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? HrmPageChrome.primaryNavy
                      : (isToday ? const Color(0xFFEFF6FF) : null),
                  borderRadius: BorderRadius.circular(6),
                  border: isToday && !isSelected
                      ? Border.all(color: HrmPageChrome.primaryNavy, width: 1)
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  tr('$day'),
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : (col == 6
                            ? const Color(0xFFEF4444)
                            : const Color(0xFF18181B)),
                    fontWeight: isSelected || isToday
                        ? FontWeight.bold
                        : FontWeight.normal,
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
                onPressed: () => onMonthChanged(
                    DateTime(calendarMonth.year, calendarMonth.month - 1)),
                icon: const Icon(Icons.chevron_left, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              Text(tr('Tháng ${calendarMonth.month}/${calendarMonth.year}'),
                style: const TextStyle(
                    color: Color(0xFF18181B),
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
              IconButton(
                onPressed: () => onMonthChanged(
                    DateTime(calendarMonth.year, calendarMonth.month + 1)),
                icon: const Icon(Icons.chevron_right, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Day names header
          Row(
            children: dayNames
                .map((d) => Expanded(
                      child: Center(
                          child: Text(tr(d),
                              style: TextStyle(
                                  color: d == 'CN'
                                      ? const Color(0xFFEF4444)
                                      : const Color(0xFF71717A),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600))),
                    ))
                .toList(),
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
          title: Text(tr(_l10n.applyToAll),
              style: const TextStyle(color: Color(0xFF18181B), fontSize: 13)),
          value: applyToAll,
          onChanged: onToggleAll,
          activeThumbColor: activeColor,
          contentPadding: EdgeInsets.zero,
        ),
        if (!applyToAll) ...[
          Row(
            children: [
              Text(tr('Chọn nhân viên:'),
                  style: TextStyle(
                      color: Color(0xFF18181B),
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              const Spacer(),
              TextButton(
                onPressed: onSelectAllEmployees,
                child:
                    Text(tr(_l10n.selectAll), style: const TextStyle(fontSize: 11)),
              ),
              TextButton(
                onPressed: onDeselectAllEmployees,
                child: Text(tr(_l10n.deselectAll),
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFFEF4444))),
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
                  title: Text(tr(employee.fullName),
                      style: const TextStyle(fontSize: 13)),
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
              child: Text(tr('Đã chọn ${selectedIds.length}/${_employees.length} nhân viên'),
                  style: TextStyle(
                      color: activeColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w500)),
            ),
        ],
      ],
    );
  }

  Future<void> _executeCopyDay(DateTime sourceDate, List<DateTime> targetDates,
      List<String>? employeeIds) async {
    setState(() => _isLoading = true);
    try {
      final employees = employeeIds != null
          ? _employees
              .where((e) => employeeIds.contains(_effectiveUserId(e)))
              .toList()
          : _employees;

      // Fetch source day data from API to ensure we have it even if it's outside current week
      final srcResult = await _apiService.getWorkSchedules(
          fromDate: sourceDate, toDate: sourceDate, pageSize: 500);
      List<WorkSchedule> srcSchedules = [];
      if (srcResult['isSuccess'] == true && srcResult['data'] != null) {
        final data = srcResult['data'];
        final items = data is List ? data : (data['items'] ?? []);
        srcSchedules =
            (items as List).map((s) => WorkSchedule.fromJson(s)).toList();
      }
      final srcRegResult = await _apiService.getScheduleRegistrations(
          fromDate: sourceDate, toDate: sourceDate, pageSize: 500);
      List<ScheduleRegistration> srcRegs = [];
      if (srcRegResult['isSuccess'] == true && srcRegResult['data'] != null) {
        final data = srcRegResult['data'];
        final items = data is List ? data : (data['items'] ?? []);
        srcRegs = (items as List)
            .map((r) => ScheduleRegistration.fromJson(r))
            .toList();
      }

      int addedCount = 0;
      for (final employee in employees) {
        final effId = _effectiveUserId(employee);
        final daySchedules = srcSchedules
            .where((s) =>
                s.employeeUserId == effId &&
                s.date.day == sourceDate.day &&
                s.date.month == sourceDate.month &&
                s.date.year == sourceDate.year)
            .toList();
        final dayRegs = srcRegs
            .where((r) =>
                r.employeeUserId == effId &&
                r.date.day == sourceDate.day &&
                r.date.month == sourceDate.month &&
                r.date.year == sourceDate.year &&
                r.status != ScheduleRegistrationStatus.rejected)
            .toList();

        List<Map<String, dynamic>> sourceItems = [];
        if (daySchedules.isNotEmpty) {
          for (final s in daySchedules) {
            sourceItems.add(
                {'shiftId': s.shiftId, 'isDayOff': s.isDayOff, 'note': s.note});
          }
        } else if (dayRegs.isNotEmpty) {
          for (final r in dayRegs) {
            sourceItems.add(
                {'shiftId': r.shiftId, 'isDayOff': r.isDayOff, 'note': r.note});
          }
        }

        if (sourceItems.isEmpty) continue;

        for (final targetDate in targetDates) {
          for (final item in sourceItems) {
            _addPendingRegistration(
                effId,
                targetDate,
                item['isDayOff'] == true ? null : item['shiftId'],
                item['isDayOff'] ?? false,
                item['note']);
            addedCount++;
          }
        }
      }

      if (addedCount > 0) {
        appNotification.showSuccess(
          title: _l10n.copySuccess,
          message: tr('Đã thêm $addedCount đăng ký vào danh sách chờ gửi'),
        );
        // Navigate to target week
        final firstTarget = (List.of(targetDates)..sort()).first;
        setState(() => _selectedWeekStart = _getWeekStart(firstTarget));
        await _loadSchedules();
        await _loadRegistrations();
      } else {
        appNotification.showWarning(
          title: 'Không có dữ liệu',
          message: tr('Ngày nguồn không có lịch để sao chép'),
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
          return ScrollableAlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.date_range, color: HrmPageChrome.primaryNavy),
                SizedBox(width: 8),
                Text(tr('Sao chép lịch tuần'),
                    style: TextStyle(
                        color: Color(0xFF18181B), fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: Responsive.dialogWidth(context),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Sao chép toàn bộ lịch của một tuần sang các tuần tiếp theo.'),
                        style:
                            TextStyle(color: Color(0xFF71717A), fontSize: 13)),
                    const SizedBox(height: 16),
                    // Source week
                    Text(tr('Tuần nguồn:'),
                        style: TextStyle(
                            color: Color(0xFF18181B),
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: sourceWeekStart,
                          firstDate: DateTime.now()
                              .subtract(const Duration(days: 365)),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            sourceWeekStart = _getWeekStart(picked);
                            targetWeekStart =
                                sourceWeekStart.add(const Duration(days: 7));
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          border: Border.all(
                              color: HrmPageChrome.primaryNavy
                                  .withValues(alpha: 0.3)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.date_range,
                                size: 16, color: HrmPageChrome.primaryNavy),
                            const SizedBox(width: 8),
                            Text(tr('${tr('Tuần ')}${_getWeekNumber(sourceWeekStart)}: ${DateFormat('dd/MM').format(sourceWeekStart)} - ${DateFormat('dd/MM/yyyy').format(sourceWeekEnd)}'),
                              style: const TextStyle(
                                  color: Color(0xFF18181B),
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Target week
                    Text(tr('Tuần đích bắt đầu từ:'),
                        style: TextStyle(
                            color: Color(0xFF18181B),
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: targetWeekStart,
                          firstDate: DateTime.now()
                              .subtract(const Duration(days: 365)),
                          lastDate:
                              DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setDialogState(
                              () => targetWeekStart = _getWeekStart(picked));
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE4E4E7)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today,
                                size: 16, color: Color(0xFF71717A)),
                            const SizedBox(width: 8),
                            Text(tr('${tr('Tuần ')}${_getWeekNumber(targetWeekStart)}: ${DateFormat('dd/MM').format(targetWeekStart)} - ${DateFormat('dd/MM/yyyy').format(targetWeekStart.add(const Duration(days: 6)))}'),
                              style: const TextStyle(color: Color(0xFF18181B)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Number of weeks
                    Text(tr('Số tuần sao chép:'),
                        style: TextStyle(
                            color: Color(0xFF18181B),
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          onPressed: numberOfWeeks > 1
                              ? () => setDialogState(() => numberOfWeeks--)
                              : null,
                          icon: const Icon(Icons.remove_circle_outline),
                          color: HrmPageChrome.primaryNavy,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(tr('$numberOfWeeks tuần'),
                              style: const TextStyle(
                                  color: Color(0xFF18181B),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14)),
                        ),
                        IconButton(
                          onPressed: numberOfWeeks < 12
                              ? () => setDialogState(() => numberOfWeeks++)
                              : null,
                          icon: const Icon(Icons.add_circle_outline),
                          color: HrmPageChrome.primaryNavy,
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
                          Text(tr('Sẽ sao chép đến:'),
                              style: TextStyle(
                                  color: Color(0xFF71717A), fontSize: 11)),
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: List.generate(numberOfWeeks, (i) {
                              final wStart =
                                  targetWeekStart.add(Duration(days: 7 * i));
                              return Chip(
                                backgroundColor: const Color(0xFFEFF6FF),
                                label: Text(tr('${tr('Tuần ')}${_getWeekNumber(wStart)}: ${DateFormat('dd/MM').format(wStart)}'),
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: HrmPageChrome.primaryNavy)),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
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
                      activeColor: HrmPageChrome.primaryNavy,
                      onToggleAll: (v) => setDialogState(() {
                        applyToAllEmployees = v;
                        if (v) selectedEmployeeIds.clear();
                      }),
                      onToggleEmployee: (id, checked) => setDialogState(() {
                        if (checked) {
                          selectedEmployeeIds.add(id);
                        } else {
                          selectedEmployeeIds.remove(id);
                        }
                      }),
                      onSelectAllEmployees: () => setDialogState(() {
                        selectedEmployeeIds =
                            _employees.map((e) => _effectiveUserId(e)).toList();
                      }),
                      onDeselectAllEmployees: () =>
                          setDialogState(() => selectedEmployeeIds.clear()),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr(_l10n.cancel),
                    style: const TextStyle(color: Color(0xFF71717A))),
              ),
              FilledButton.icon(
                onPressed: (!applyToAllEmployees && selectedEmployeeIds.isEmpty)
                    ? null
                    : () {
                        Navigator.pop(context);
                        _executeCopyWeek(
                            sourceWeekStart,
                            targetWeekStart,
                            numberOfWeeks,
                            applyToAllEmployees ? null : selectedEmployeeIds);
                      },
                icon: const Icon(Icons.content_copy, size: 16),
                label: Text(tr('Sao chép')),
                style: FilledButton.styleFrom(backgroundColor: HrmPageChrome.primaryNavy),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _executeCopyWeek(
      DateTime sourceWeekStart,
      DateTime targetWeekStart,
      int numberOfWeeks,
      List<String>? employeeIds) async {
    final fromDate = sourceWeekStart;
    final toDate = sourceWeekStart.add(const Duration(days: 6));

    // Get source week schedules
    final result = await _apiService.getWorkSchedules(
        fromDate: fromDate, toDate: toDate, pageSize: 500);
    List<WorkSchedule> sourceSchedules = [];
    if (result['isSuccess'] == true && result['data'] != null) {
      final data = result['data'];
      final items = data is List ? data : (data['items'] ?? []);
      sourceSchedules =
          (items as List).map((s) => WorkSchedule.fromJson(s)).toList();
    }

    // Also get source week registrations
    final regResult = await _apiService.getScheduleRegistrations(
        fromDate: fromDate, toDate: toDate, pageSize: 500);
    List<ScheduleRegistration> sourceRegs = [];
    if (regResult['isSuccess'] == true && regResult['data'] != null) {
      final data = regResult['data'];
      final items = data is List ? data : (data['items'] ?? []);
      sourceRegs =
          (items as List).map((r) => ScheduleRegistration.fromJson(r)).toList();
    }

    final employees = employeeIds != null
        ? _employees
            .where((e) => employeeIds.contains(_effectiveUserId(e)))
            .toList()
        : _employees;

    int addedCount = 0;
    for (final employee in employees) {
      final effId = _effectiveUserId(employee);
      for (int dayIdx = 0; dayIdx < 7; dayIdx++) {
        final sourceDay = sourceWeekStart.add(Duration(days: dayIdx));
        final daySchedules = sourceSchedules
            .where((s) =>
                s.employeeUserId == effId &&
                s.date.day == sourceDay.day &&
                s.date.month == sourceDay.month &&
                s.date.year == sourceDay.year)
            .toList();
        final dayRegs = sourceRegs
            .where((r) =>
                r.employeeUserId == effId &&
                r.date.day == sourceDay.day &&
                r.date.month == sourceDay.month &&
                r.date.year == sourceDay.year &&
                r.status != ScheduleRegistrationStatus.rejected)
            .toList();

        List<Map<String, dynamic>> sourceItems = [];
        if (daySchedules.isNotEmpty) {
          for (final s in daySchedules) {
            sourceItems.add(
                {'shiftId': s.shiftId, 'isDayOff': s.isDayOff, 'note': s.note});
          }
        } else if (dayRegs.isNotEmpty) {
          for (final r in dayRegs) {
            sourceItems.add(
                {'shiftId': r.shiftId, 'isDayOff': r.isDayOff, 'note': r.note});
          }
        }

        if (sourceItems.isEmpty) continue;

        for (int weekIdx = 0; weekIdx < numberOfWeeks; weekIdx++) {
          final targetDay =
              targetWeekStart.add(Duration(days: 7 * weekIdx + dayIdx));
          for (final item in sourceItems) {
            _addPendingRegistration(
                effId,
                targetDay,
                item['isDayOff'] == true ? null : item['shiftId'],
                item['isDayOff'] ?? false,
                item['note']);
            addedCount++;
          }
        }
      }
    }

    if (addedCount > 0) {
      appNotification.showSuccess(
          title: 'Sao chép tuần thành công',
          message: tr('Đã thêm $addedCount đăng ký vào danh sách chờ gửi'));
    } else {
      appNotification.showWarning(
          title: 'Không có dữ liệu',
          message: tr('Tuần nguồn không có lịch để sao chép'));
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

    final monthNames = [
      '',
      'Tháng 1',
      'Tháng 2',
      'Tháng 3',
      'Tháng 4',
      'Tháng 5',
      'Tháng 6',
      'Tháng 7',
      'Tháng 8',
      'Tháng 9',
      'Tháng 10',
      'Tháng 11',
      'Tháng 12'
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return ScrollableAlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.calendar_month, color: HrmPageChrome.primaryNavy),
                SizedBox(width: 8),
                Text(tr('Sao chép lịch tháng'),
                    style: TextStyle(
                        color: Color(0xFF18181B), fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: Responsive.dialogWidth(context),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Sao chép lịch theo từng tuần trong tháng nguồn sang tháng đích.'),
                        style:
                            TextStyle(color: Color(0xFF71717A), fontSize: 13)),
                    const SizedBox(height: 16),
                    // Source month/year
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr('Tháng nguồn:'),
                                  style: TextStyle(
                                      color: Color(0xFF18181B),
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      initialValue: sourceMonth,
                                      decoration: InputDecoration(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8),
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        isDense: true,
                                      ),
                                      items: List.generate(
                                          12,
                                          (i) => DropdownMenuItem(
                                              value: i + 1,
                                              child: Text(tr(monthNames[i + 1])))),
                                      onChanged: (v) => setDialogState(
                                          () => sourceMonth = v!),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 100,
                                    child: DropdownButtonFormField<int>(
                                      initialValue: sourceYear,
                                      decoration: InputDecoration(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8),
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        isDense: true,
                                      ),
                                      items: List.generate(
                                          3,
                                          (i) => DropdownMenuItem(
                                              value:
                                                  DateTime.now().year - 1 + i,
                                              child: Text(
                                                  tr('${DateTime.now().year - 1 + i}')))),
                                      onChanged: (v) =>
                                          setDialogState(() => sourceYear = v!),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: Icon(Icons.arrow_forward,
                              color: HrmPageChrome.primaryNavy),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr('Tháng đích:'),
                                  style: TextStyle(
                                      color: Color(0xFF18181B),
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: DropdownButtonFormField<int>(
                                      initialValue: targetMonth,
                                      decoration: InputDecoration(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8),
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        isDense: true,
                                      ),
                                      items: List.generate(
                                          12,
                                          (i) => DropdownMenuItem(
                                              value: i + 1,
                                              child: Text(tr(monthNames[i + 1])))),
                                      onChanged: (v) => setDialogState(
                                          () => targetMonth = v!),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 100,
                                    child: DropdownButtonFormField<int>(
                                      initialValue: targetYear,
                                      decoration: InputDecoration(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 8),
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(8)),
                                        isDense: true,
                                      ),
                                      items: List.generate(
                                          3,
                                          (i) => DropdownMenuItem(
                                              value:
                                                  DateTime.now().year - 1 + i,
                                              child: Text(
                                                  tr('${DateTime.now().year - 1 + i}')))),
                                      onChanged: (v) =>
                                          setDialogState(() => targetYear = v!),
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
                      activeColor: HrmPageChrome.primaryNavy,
                      onToggleAll: (v) => setDialogState(() {
                        applyToAllEmployees = v;
                        if (v) selectedEmployeeIds.clear();
                      }),
                      onToggleEmployee: (id, checked) => setDialogState(() {
                        if (checked) {
                          selectedEmployeeIds.add(id);
                        } else {
                          selectedEmployeeIds.remove(id);
                        }
                      }),
                      onSelectAllEmployees: () => setDialogState(() {
                        selectedEmployeeIds =
                            _employees.map((e) => _effectiveUserId(e)).toList();
                      }),
                      onDeselectAllEmployees: () =>
                          setDialogState(() => selectedEmployeeIds.clear()),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr(_l10n.cancel),
                    style: const TextStyle(color: Color(0xFF71717A))),
              ),
              FilledButton.icon(
                onPressed: (!applyToAllEmployees && selectedEmployeeIds.isEmpty)
                    ? null
                    : () {
                        Navigator.pop(context);
                        _executeCopyMonth(
                            sourceMonth,
                            sourceYear,
                            targetMonth,
                            targetYear,
                            applyToAllEmployees ? null : selectedEmployeeIds);
                      },
                icon: const Icon(Icons.content_copy, size: 16),
                label: Text(tr('Sao chép')),
                style: FilledButton.styleFrom(backgroundColor: HrmPageChrome.primaryNavy),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _executeCopyMonth(int sourceMonth, int sourceYear,
      int targetMonth, int targetYear, List<String>? employeeIds) async {
    setState(() => _isLoading = true);
    try {
      final sourceStart = DateTime(sourceYear, sourceMonth, 1);
      final sourceEnd = DateTime(sourceYear, sourceMonth + 1, 0);
      final targetStart = DateTime(targetYear, targetMonth, 1);

      // Get all schedules for source month
      final result = await _apiService.getWorkSchedules(
          fromDate: sourceStart, toDate: sourceEnd, pageSize: 500);
      List<WorkSchedule> sourceSchedules = [];
      if (result['isSuccess'] == true && result['data'] != null) {
        final data = result['data'];
        final items = data is List ? data : (data['items'] ?? []);
        sourceSchedules =
            (items as List).map((s) => WorkSchedule.fromJson(s)).toList();
      }

      // Also get registrations for source month
      final regResult = await _apiService.getScheduleRegistrations(
          fromDate: sourceStart, toDate: sourceEnd, pageSize: 500);
      List<ScheduleRegistration> sourceRegs = [];
      if (regResult['isSuccess'] == true && regResult['data'] != null) {
        final data = regResult['data'];
        final items = data is List ? data : (data['items'] ?? []);
        sourceRegs = (items as List)
            .map((r) => ScheduleRegistration.fromJson(r))
            .toList();
      }

      final employees = employeeIds != null
          ? _employees
              .where((e) => employeeIds.contains(_effectiveUserId(e)))
              .toList()
          : _employees;

      final daysInSourceMonth = sourceEnd.day;
      final daysInTargetMonth = DateTime(targetYear, targetMonth + 1, 0).day;
      final daysToCopy = daysInSourceMonth < daysInTargetMonth
          ? daysInSourceMonth
          : daysInTargetMonth;

      int addedCount = 0;
      for (final employee in employees) {
        final effId = _effectiveUserId(employee);
        for (int dayIdx = 0; dayIdx < daysToCopy; dayIdx++) {
          final sourceDay = sourceStart.add(Duration(days: dayIdx));
          final targetDay = targetStart.add(Duration(days: dayIdx));

          final daySchedules = sourceSchedules
              .where((s) =>
                  s.employeeUserId == effId &&
                  s.date.day == sourceDay.day &&
                  s.date.month == sourceDay.month &&
                  s.date.year == sourceDay.year)
              .toList();
          final dayRegs = sourceRegs
              .where((r) =>
                  r.employeeUserId == effId &&
                  r.date.day == sourceDay.day &&
                  r.date.month == sourceDay.month &&
                  r.date.year == sourceDay.year &&
                  r.status != ScheduleRegistrationStatus.rejected)
              .toList();

          List<Map<String, dynamic>> sourceItems = [];
          if (daySchedules.isNotEmpty) {
            for (final s in daySchedules) {
              sourceItems.add({
                'shiftId': s.shiftId,
                'isDayOff': s.isDayOff,
                'note': s.note
              });
            }
          } else if (dayRegs.isNotEmpty) {
            for (final r in dayRegs) {
              sourceItems.add({
                'shiftId': r.shiftId,
                'isDayOff': r.isDayOff,
                'note': r.note
              });
            }
          }

          if (sourceItems.isEmpty) continue;

          for (final item in sourceItems) {
            _addPendingRegistration(
                effId,
                targetDay,
                item['isDayOff'] == true ? null : item['shiftId'],
                item['isDayOff'] ?? false,
                item['note']);
            addedCount++;
          }
        }
      }

      if (addedCount > 0) {
        appNotification.showSuccess(
            title: 'Sao chép tháng thành công',
            message: tr('Đã thêm $addedCount đăng ký vào danh sách chờ gửi'));
        setState(() => _selectedWeekStart = _getWeekStart(targetStart));
        await _loadSchedules();
        await _loadRegistrations();
      } else {
        appNotification.showWarning(
            title: 'Không có dữ liệu',
            message: tr('Tháng nguồn không có lịch để sao chép'));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ==================== HELP/GUIDE DIALOG ====================
  void _showScheduleGuide() {
    showDialog(
      context: context,
      builder: (context) => ScrollableAlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.menu_book, color: Color(0xFFFB923C)),
            SizedBox(width: 8),
            Text(tr('Hướng dẫn đăng ký lịch làm việc'),
                style: TextStyle(
                    color: Color(0xFF18181B),
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
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
                  HrmPageChrome.primaryNavy,
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
                  HrmPageChrome.primaryNavy,
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
                  HrmPageChrome.primaryNavy,
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
                  HrmPageChrome.primaryNavy,
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
          FilledButton(
            onPressed: () => Navigator.pop(context),
            style: FilledButton.styleFrom(backgroundColor: HrmPageChrome.primaryNavy),
            child: Text(tr('Đã hiểu')),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideSection(
      String title, IconData icon, Color color, List<String> steps) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(tr(title),
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
        const SizedBox(height: 8),
        ...steps.map((step) => Padding(
              padding: const EdgeInsets.only(left: 28, bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('• '), style: TextStyle(color: Color(0xFF71717A))),
                  Expanded(
                      child: Text(tr(step),
                          style: const TextStyle(
                              color: Color(0xFF52525B),
                              fontSize: 13,
                              height: 1.4))),
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
    final days =
        List.generate(7, (i) => _selectedWeekStart.add(Duration(days: i)));
    final dayLabels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    final now = DateTime.now();
    final canEdit = Provider.of<PermissionProvider>(context, listen: false)
        .canEdit('WorkSchedule');
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Container(
                  width: 110,
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                  decoration: const BoxDecoration(
                      border:
                          Border(right: BorderSide(color: Color(0xFFE4E4E7)))),
                  child: Text(tr('Nhân viên'),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFA16207)),
                      textAlign: TextAlign.center),
                ),
                ...List.generate(7, (di) {
                  final day = days[di];
                  final isToday = day.year == now.year &&
                      day.month == now.month &&
                      day.day == now.day;
                  final isSun = di == 6;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _pendingFocusedDay = di),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: isToday
                              ? const Color(0xFFF59E0B).withValues(alpha: 0.12)
                              : null,
                          border: di < 6
                              ? const Border(
                                  right: BorderSide(color: Color(0xFFE4E4E7)))
                              : null,
                        ),
                        child: Column(
                          children: [
                            Text(tr(dayLabels[di]),
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isToday
                                        ? const Color(0xFFA16207)
                                        : (isSun
                                            ? const Color(0xFFEF4444)
                                            : const Color(0xFF71717A)))),
                            Text(tr('${day.day}/${day.month}'),
                                style: TextStyle(
                                    fontSize: 10,
                                    color: isToday
                                        ? const Color(0xFFA16207)
                                        : const Color(0xFF71717A))),
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
            Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                    child: Text(tr('Chưa có đăng ký nào'),
                        style: TextStyle(color: Color(0xFF71717A)))))
          else
            ...activeEmps.asMap().entries.map((entry) {
              final emp = entry.value;
              final isLast = entry.key == activeEmps.length - 1;
              return Container(
                decoration: BoxDecoration(
                    border: isLast
                        ? null
                        : const Border(
                            bottom: BorderSide(color: Color(0xFFE4E4E7)))),
                child: Row(
                  children: [
                    Container(
                      width: 110,
                      padding: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 6),
                      decoration: const BoxDecoration(
                          border: Border(
                              right: BorderSide(color: Color(0xFFE4E4E7)))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr(emp.fullName),
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF18181B)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(tr(emp.employeeCode),
                              style: const TextStyle(
                                  fontSize: 9, color: Color(0xFF71717A))),
                        ],
                      ),
                    ),
                    ...List.generate(7, (di) {
                      final day = days[di];
                      final isToday = day.year == now.year &&
                          day.month == now.month &&
                          day.day == now.day;
                      return Expanded(
                          child: _buildPendingCell(emp, day, isToday, canEdit));
                    }),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildPendingCell(
      Employee emp, DateTime day, bool isToday, bool canEdit) {
    final eid = _effectiveUserId(emp);
    final schedules = _getSchedulesForDay(eid, day);
    final localPending = _getPendingRegistrations(eid, day);
    final submittedRegs = _getRegistrationsForDay(eid, day);
    final pendingRegs = submittedRegs
        .where((r) => r.status == ScheduleRegistrationStatus.pending)
        .toList();
    final approvedRegs = submittedRegs
        .where((r) => r.status == ScheduleRegistrationStatus.approved)
        .toList();
    final rejectedRegs = submittedRegs
        .where((r) => r.status == ScheduleRegistrationStatus.rejected)
        .toList();

    final totalItems = schedules.length +
        localPending.length +
        pendingRegs
            .where((r) =>
                schedules.every((s) => s.employeeUserId != r.employeeUserId))
            .length +
        approvedRegs
            .where((r) =>
                schedules.every((s) => s.employeeUserId != r.employeeUserId))
            .length;

    if (totalItems == 0 && rejectedRegs.isEmpty) {
      return GestureDetector(
        onTap: canEdit ? () => _showRegisterDialog(emp, day) : null,
        child: Container(
          height: 48,
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
              color: isToday ? const Color(0xFFF5F5F4) : Colors.white,
              borderRadius: BorderRadius.circular(4)),
          child:
              Center(child: Icon(Icons.add, size: 12, color: Colors.grey[300])),
        ),
      );
    }

    // Build status dots
    final dots = <Widget>[];
    if (schedules.isNotEmpty) dots.add(_statusDot(HrmPageChrome.primaryNavy));
    if (approvedRegs.isNotEmpty) dots.add(_statusDot(const Color(0xFF059669)));
    if (pendingRegs.isNotEmpty) dots.add(_statusDot(const Color(0xFFD97706)));
    if (localPending.isNotEmpty) dots.add(_statusDot(const Color(0xFF8B5CF6)));
    if (rejectedRegs.isNotEmpty) dots.add(_statusDot(const Color(0xFFEF4444)));

    // Primary color
    Color borderColor;
    Color bgColor;
    if (pendingRegs.isNotEmpty || localPending.isNotEmpty) {
      borderColor = const Color(0xFFD97706);
      bgColor = const Color(0xFFFEF3C7);
    } else if (schedules.isNotEmpty) {
      borderColor = HrmPageChrome.primaryNavy;
      bgColor = HrmPageChrome.primaryNavy.withValues(alpha: 0.08);
    } else if (approvedRegs.isNotEmpty) {
      borderColor = const Color(0xFF059669);
      bgColor = const Color(0xFF059669).withValues(alpha: 0.08);
    } else {
      borderColor = const Color(0xFFEF4444);
      bgColor = const Color(0xFFFEE2E2);
    }

    // Count labels
    final labels = <Widget>[];
    final confirmedCount = schedules.where((s) => !s.isDayOff).length;
    final dayOffCount = schedules.where((s) => s.isDayOff).length;
    final pendCount = pendingRegs.length + localPending.length;
    if (confirmedCount > 0) {
      labels.add(Text(tr('$confirmedCount ca'),
          style: const TextStyle(
              fontSize: 9,
              color: HrmPageChrome.primaryNavy,
              fontWeight: FontWeight.w600)));
    }
    if (dayOffCount > 0) {
      labels.add(Text(tr('Nghỉ'),
          style: TextStyle(
              fontSize: 9,
              color: Color(0xFF71717A),
              fontWeight: FontWeight.w600)));
    }
    if (pendCount > 0) {
      labels.add(Text(tr('$pendCount chờ'),
          style: const TextStyle(
              fontSize: 9,
              color: Color(0xFFA16207),
              fontWeight: FontWeight.w600)));
    }
    if (rejectedRegs.isNotEmpty) {
      labels.add(Text(tr('${rejectedRegs.length} từ chối'),
          style: const TextStyle(fontSize: 8, color: Color(0xFFEF4444))));
    }

    return GestureDetector(
      onTap: canEdit ? () => _showRegisterDialog(emp, day) : null,
      child: Container(
        height: 48,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: borderColor, width: 1.2),
            borderRadius: BorderRadius.circular(4)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ...labels,
            if (dots.isNotEmpty)
              Row(mainAxisAlignment: MainAxisAlignment.center, children: dots),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: () => setState(() => _pendingFocusedDay = null),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE4E4E7))),
                    child: const Icon(Icons.arrow_back,
                        size: 18, color: Color(0xFFA16207)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(tr('$dayLabel — $dateStr'),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFA16207)))),
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
              if (schedules.isEmpty &&
                  localPending.isEmpty &&
                  submittedRegs.isEmpty) {
                continue;
              }

              final chips = <Widget>[];
              for (final ws in schedules) {
                if (ws.isDayOff) {
                  chips.add(_empChip(
                      'Nghỉ', const Color(0xFF71717A), Icons.nightlight_round));
                } else {
                  final shift = _shifts.firstWhere((s) => s.id == ws.shiftId,
                      orElse: () => Shift(
                          id: '',
                          name: 'Ca',
                          code: '',
                          startTime: '',
                          endTime: '',
                          isActive: true,
                          createdAt: DateTime.now()));
                  chips.add(_empChip(
                      shift.name, HrmPageChrome.primaryNavy, Icons.check_circle));
                }
              }
              for (final r in submittedRegs) {
                if (schedules.any((s) =>
                    s.shiftId == r.shiftId &&
                    s.employeeUserId == r.employeeUserId)) {
                  continue;
                }
                Color c;
                IconData ic;
                String suffix;
                switch (r.status) {
                  case ScheduleRegistrationStatus.pending:
                    c = const Color(0xFFD97706);
                    ic = Icons.hourglass_empty;
                    suffix = ' (chờ)';
                    break;
                  case ScheduleRegistrationStatus.approved:
                    c = const Color(0xFF059669);
                    ic = Icons.check_circle;
                    suffix = ' (duyệt)';
                    break;
                  case ScheduleRegistrationStatus.rejected:
                    c = const Color(0xFFEF4444);
                    ic = Icons.cancel;
                    suffix = ' (từ chối)';
                    break;
                }
                if (r.isDayOff) {
                  chips.add(_empChip('Nghỉ$suffix', c, ic));
                } else {
                  final shift = r.shiftId != null
                      ? _shifts.firstWhere((s) => s.id == r.shiftId,
                          orElse: () => Shift(
                              id: '',
                              name: 'Ca',
                              code: '',
                              startTime: '',
                              endTime: '',
                              isActive: true,
                              createdAt: DateTime.now()))
                      : null;
                  chips.add(_empChip('${shift?.name ?? 'Ca'}$suffix', c, ic));
                }
              }
              for (final p in localPending) {
                if (p['isDayOff'] == true) {
                  chips.add(_empChip('Nghỉ (chưa gửi)', const Color(0xFF8B5CF6),
                      Icons.schedule_send));
                } else {
                  final shift = p['shiftId'] != null
                      ? _shifts.firstWhere((s) => s.id == p['shiftId'],
                          orElse: () => Shift(
                              id: '',
                              name: 'Ca',
                              code: '',
                              startTime: '',
                              endTime: '',
                              isActive: true,
                              createdAt: DateTime.now()))
                      : null;
                  chips.add(_empChip('${shift?.name ?? 'Ca'} (chưa gửi)',
                      const Color(0xFF8B5CF6), Icons.schedule_send));
                }
              }

              rows.add(Container(
                decoration: const BoxDecoration(
                    border:
                        Border(bottom: BorderSide(color: Color(0xFFE4E4E7)))),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                        width: 120,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr(emp.fullName),
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF18181B))),
                            Text(tr(emp.employeeCode),
                                style: const TextStyle(
                                    fontSize: 10, color: Color(0xFF71717A))),
                          ],
                        )),
                    const SizedBox(width: 8),
                    Expanded(
                        child:
                            Wrap(spacing: 4, runSpacing: 4, children: chips)),
                    if (canEdit)
                      InkWell(
                        onTap: () => _showRegisterDialog(emp, day),
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6)),
                          child: const Icon(Icons.edit_calendar,
                              size: 16, color: Color(0xFFA16207)),
                        ),
                      ),
                  ],
                ),
              ));
            }
            if (rows.isEmpty) {
              return [
                Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                        child: Text(tr('Không có đăng ký'),
                            style: TextStyle(color: Color(0xFF71717A)))))
              ];
            }
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
    final days =
        List.generate(7, (i) => _selectedWeekStart.add(Duration(days: i)));
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
        if (regs.any((r) => r.status == ScheduleRegistrationStatus.approved)) {
          return true;
        }
      }
      return false;
    }).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            decoration: BoxDecoration(
              color: HrmPageChrome.primaryNavy.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Container(
                  width: 110,
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                  decoration: const BoxDecoration(
                      border:
                          Border(right: BorderSide(color: Color(0xFFE4E4E7)))),
                  child: Text(tr('Nhân viên'),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: HrmPageChrome.primaryNavy),
                      textAlign: TextAlign.center),
                ),
                ...List.generate(7, (di) {
                  final day = days[di];
                  final isToday = day.year == now.year &&
                      day.month == now.month &&
                      day.day == now.day;
                  final isSun = di == 6;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _approvedFocusedDay = di),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: isToday
                              ? HrmPageChrome.primaryNavy.withValues(alpha: 0.12)
                              : null,
                          border: di < 6
                              ? const Border(
                                  right: BorderSide(color: Color(0xFFE4E4E7)))
                              : null,
                        ),
                        child: Column(
                          children: [
                            Text(tr(dayLabels[di]),
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isToday
                                        ? HrmPageChrome.primaryNavy
                                        : (isSun
                                            ? const Color(0xFFEF4444)
                                            : const Color(0xFF71717A)))),
                            Text(tr('${day.day}/${day.month}'),
                                style: TextStyle(
                                    fontSize: 10,
                                    color: isToday
                                        ? HrmPageChrome.primaryNavy
                                        : const Color(0xFF71717A))),
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
            Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                    child: Text(tr('Chưa có lịch đã duyệt'),
                        style: TextStyle(color: Color(0xFF71717A)))))
          else
            ...activeEmps.asMap().entries.map((entry) {
              final emp = entry.value;
              final isLast = entry.key == activeEmps.length - 1;
              return Container(
                decoration: BoxDecoration(
                    border: isLast
                        ? null
                        : const Border(
                            bottom: BorderSide(color: Color(0xFFE4E4E7)))),
                child: Row(
                  children: [
                    Container(
                      width: 110,
                      padding: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 6),
                      decoration: const BoxDecoration(
                          border: Border(
                              right: BorderSide(color: Color(0xFFE4E4E7)))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr(emp.fullName),
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF18181B)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(tr(emp.department ?? emp.employeeCode),
                              style: const TextStyle(
                                  fontSize: 9, color: Color(0xFF71717A))),
                        ],
                      ),
                    ),
                    ...List.generate(7, (di) {
                      final day = days[di];
                      final isToday = day.year == now.year &&
                          day.month == now.month &&
                          day.day == now.day;
                      return Expanded(
                          child: _buildApprovedCell(emp, day, isToday));
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
    final approvedRegs = _getRegistrationsForDay(eid, day)
        .where((r) => r.status == ScheduleRegistrationStatus.approved)
        .toList();
    final uniqueApproved = approvedRegs
        .where((r) => schedules.every((s) =>
            s.shiftId != r.shiftId || s.employeeUserId != r.employeeUserId))
        .toList();

    final totalShifts = schedules.where((s) => !s.isDayOff).length +
        uniqueApproved.where((r) => !r.isDayOff).length;
    final hasDayOff = schedules.any((s) => s.isDayOff) ||
        uniqueApproved.any((r) => r.isDayOff);

    if (totalShifts == 0 && !hasDayOff) {
      return Container(
        height: 48,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
            color: isToday ? const Color(0xFFF5F5F4) : Colors.white,
            borderRadius: BorderRadius.circular(4)),
        child: Center(
            child: Text(tr('—'),
                style: TextStyle(color: Colors.grey[300], fontSize: 14))),
      );
    }

    // Build compact display
    final labels = <Widget>[];
    if (hasDayOff) {
      labels.add(Text(tr('Nghỉ'),
          style: TextStyle(
              fontSize: 9,
              color: Color(0xFF71717A),
              fontWeight: FontWeight.w600)));
    }
    if (totalShifts > 0) {
      labels.add(Text(tr('$totalShifts ca'),
          style: const TextStyle(
              fontSize: 10,
              color: HrmPageChrome.primaryNavy,
              fontWeight: FontWeight.w700)));
    }

    return Container(
      height: 48,
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: hasDayOff && totalShifts == 0
            ? const Color(0xFF71717A).withValues(alpha: 0.06)
            : HrmPageChrome.primaryNavy.withValues(alpha: 0.08),
        border: Border.all(
            color: hasDayOff && totalShifts == 0
                ? const Color(0xFF71717A)
                : HrmPageChrome.primaryNavy,
            width: 1.2),
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

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: HrmPageChrome.primaryNavy.withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: () => setState(() => _approvedFocusedDay = null),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE4E4E7))),
                    child: const Icon(Icons.arrow_back,
                        size: 18, color: HrmPageChrome.primaryNavy),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(tr('$dayLabel — $dateStr'),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: HrmPageChrome.primaryNavy))),
              ],
            ),
          ),
          // Group by shift
          if (_shifts.isEmpty)
            Padding(
                padding: EdgeInsets.all(24),
                child: Text(tr('Chưa có ca'),
                    style: TextStyle(color: Color(0xFF71717A))))
          else
            ..._shifts.asMap().entries.map((entry) {
              final si = entry.key;
              final shift = entry.value;
              final isLast = si == _shifts.length - 1;
              // Get confirmed + approved for this shift on this day
              final confirmedScheds = _getSchedulesForShiftDay(shift.id, day);
              final approvedRegs = _getRegistrationsForShiftDay(shift.id, day)
                  .where((r) => r.status == ScheduleRegistrationStatus.approved)
                  .toList();
              final uniqueApprovedRegs = approvedRegs
                  .where((r) => confirmedScheds
                      .every((s) => s.employeeUserId != r.employeeUserId))
                  .toList();

              final names = <Map<String, dynamic>>[];
              for (final ws in confirmedScheds) {
                final emp = _employees.firstWhere(
                    (e) => _effectiveUserId(e) == ws.employeeUserId,
                    orElse: () => Employee.empty());
                names.add({
                  'name': emp.fullName,
                  'color': HrmPageChrome.primaryNavy,
                  'icon': Icons.check_circle,
                  'isDayOff': ws.isDayOff
                });
              }
              for (final r in uniqueApprovedRegs) {
                final emp = _employees.firstWhere(
                    (e) => _effectiveUserId(e) == r.employeeUserId,
                    orElse: () => Employee.empty());
                names.add({
                  'name': emp.fullName,
                  'color': const Color(0xFF059669),
                  'icon': Icons.verified,
                  'isDayOff': r.isDayOff
                });
              }

              return Container(
                decoration: BoxDecoration(
                    border: isLast
                        ? null
                        : const Border(
                            bottom: BorderSide(color: Color(0xFFE4E4E7)))),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: HrmPageChrome.primaryNavy
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(tr(shift.name),
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: HrmPageChrome.primaryNavy)),
                          ),
                          const SizedBox(width: 8),
                          Text(
                              tr('${_formatTime(shift.startTime)} - ${_formatTime(shift.endTime)}'),
                              style: const TextStyle(
                                  fontSize: 11, color: Color(0xFF71717A))),
                          const Spacer(),
                          Text(
                              tr('${names.where((n) => n['isDayOff'] != true).length} NV'),
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: HrmPageChrome.primaryNavy)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (names.isEmpty)
                        Text(tr('Chưa có nhân viên'),
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[400]))
                      else
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: names
                              .map((n) => _empChip(
                                    n['isDayOff'] == true
                                        ? '${n['name']} (Nghỉ)'
                                        : n['name'] as String,
                                    n['color'] as Color,
                                    n['icon'] as IconData,
                                  ))
                              .toList(),
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

  // ══════════════════════════════════════════════
  //  BRANCH GROUPING HELPERS
  // ══════════════════════════════════════════════

  Widget _buildBranchGroupHeader(String branchName, int count) {
    final primary = Theme.of(context).primaryColor;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.account_tree_outlined, size: 15, color: primary),
                const SizedBox(width: 6),
                Text(tr(branchName),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: primary)),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: primary, borderRadius: BorderRadius.circular(10)),
                  child: Text(tr('$count'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: Divider(
                  color: primary.withValues(alpha: 0.25), thickness: 1)),
        ],
      ),
    );
  }

  /// Returns ordered list of [branchName, List<Employee>] pairs grouped by branch.
  List<MapEntry<String, List<Employee>>> _groupEmployeesByBranch(
      List<Employee> employees) {
    final Map<String, List<Employee>> groupMap = {};
    for (final e in employees) {
      final key =
          (e.branchName?.isNotEmpty == true) ? e.branchName! : '__none__';
      groupMap.putIfAbsent(key, () => []).add(e);
    }
    final branchOrder =
        _branches.map((b) => b['name']?.toString() ?? '').toList();
    final List<String> keys = [
      ...branchOrder.where((n) => groupMap.containsKey(n)),
      ...groupMap.keys
          .where((k) => !branchOrder.contains(k) && k != '__none__'),
      if (groupMap.containsKey('__none__')) '__none__',
    ];
    return keys
        .map((k) =>
            MapEntry(k == '__none__' ? 'Chưa có chi nhánh' : k, groupMap[k]!))
        .toList();
  }

  // ignore: unused_element
  Widget _buildScheduleTable() {
    final days =
        List.generate(7, (i) => _selectedWeekStart.add(Duration(days: i)));
    final dayNames = [
      'THỨ 2',
      'THỨ 3',
      'THỨ 4',
      'THỨ 5',
      'THỨ 6',
      'THỨ 7',
      'CHỦ NHẬT'
    ];
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
          final isMobile = constraints.maxWidth < 768;
          final totalPages = (allEmps.length / _schedulePageSize).ceil();
          final safePage =
              _schedulePage.clamp(1, totalPages == 0 ? 1 : totalPages);
          final startIdx = isMobile ? 0 : (safePage - 1) * _schedulePageSize;
          final endIdx = isMobile
              ? allEmps.length
              : (startIdx + _schedulePageSize).clamp(0, allEmps.length);
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
                  headingRowColor:
                      WidgetStateProperty.all(const Color(0xFFF1F5F9)),
                  dataRowColor: WidgetStateProperty.all(Colors.white),
                  dataRowMinHeight: 56,
                  dataRowMaxHeight: 64,
                  border:
                      TableBorder.all(color: const Color(0xFFE4E4E7), width: 1),
                  columns: [
                    DataColumn(
                      label: Expanded(
                          child: Text(tr('NHÂN VIÊN'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Color(0xFF18181B),
                                  fontWeight: FontWeight.bold))),
                    ),
                    ...List.generate(7, (i) {
                      final day = days[i];
                      final isToday = day.day == today.day &&
                          day.month == today.month &&
                          day.year == today.year;
                      return DataColumn(
                        label: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              tr(dayNames[i]),
                              style: TextStyle(
                                color: isToday
                                    ? HrmPageChrome.primaryNavy
                                    : const Color(0xFF18181B),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              tr(dateFormat.format(day)),
                              style: TextStyle(
                                color: isToday
                                    ? HrmPageChrome.primaryNavy
                                    : const Color(0xFF71717A),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    DataColumn(
                      label: Expanded(
                          child: Text(tr('TỔNG CA'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Color(0xFF18181B),
                                  fontWeight: FontWeight.bold))),
                    ),
                  ],
                  rows: pageEmps.isEmpty
                      ? [
                          DataRow(cells: [
                            DataCell(
                              Center(
                                child: Text(tr('Chưa có nhân viên'),
                                    style: TextStyle(color: Colors.grey[400])),
                              ),
                            ),
                            ...List.generate(
                                8, (_) => const DataCell(Text(''))),
                          ]),
                        ]
                      : _buildScheduleDesktopRows(pageEmps, days),
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
                            value: _schedulePageSize,
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
                                  _schedulePageSize = v;
                                  _schedulePage = 1;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                          icon: const Icon(Icons.first_page),
                          onPressed: safePage > 1
                              ? () => setState(() => _schedulePage = 1)
                              : null),
                      IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: safePage > 1
                              ? () => setState(() => _schedulePage--)
                              : null),
                      Text(tr('Hiển thị ${(safePage - 1) * _schedulePageSize + 1}-${(safePage * _schedulePageSize).clamp(0, allEmps.length)} / ${allEmps.length} nhân viên'),
                          style: const TextStyle(fontSize: 13)),
                      IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: safePage < totalPages
                              ? () => setState(() => _schedulePage++)
                              : null),
                      IconButton(
                          icon: const Icon(Icons.last_page),
                          onPressed: safePage < totalPages
                              ? () => setState(() => _schedulePage = totalPages)
                              : null),
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
    return _schedules
        .where(
          (s) =>
              s.employeeUserId == employeeId &&
              s.date.day == day.day &&
              s.date.month == day.month &&
              s.date.year == day.year,
        )
        .toList();
  }

  List<Map<String, dynamic>> _getPendingRegistrations(
      String employeeId, DateTime day) {
    return _pendingRegistrations
        .where(
          (r) =>
              r['employeeId'] == employeeId &&
              (r['date'] as DateTime).day == day.day &&
              (r['date'] as DateTime).month == day.month &&
              (r['date'] as DateTime).year == day.year,
        )
        .toList();
  }

  List<ScheduleRegistration> _getRegistrationsForDay(
      String employeeId, DateTime day) {
    return _registrations
        .where(
          (r) =>
              r.employeeUserId == employeeId &&
              r.date.day == day.day &&
              r.date.month == day.month &&
              r.date.year == day.year,
        )
        .toList();
  }

  // ── Shift-day helpers (for shift-centric table) ──
  List<WorkSchedule> _getSchedulesForShiftDay(String shiftId, DateTime day) {
    return _schedules
        .where((s) =>
            s.shiftId == shiftId &&
            s.date.day == day.day &&
            s.date.month == day.month &&
            s.date.year == day.year)
        .toList();
  }

  List<Map<String, dynamic>> _getPendingForShiftDay(
      String shiftId, DateTime day) {
    return _pendingRegistrations
        .where((r) =>
            r['shiftId'] == shiftId &&
            (r['date'] as DateTime).day == day.day &&
            (r['date'] as DateTime).month == day.month &&
            (r['date'] as DateTime).year == day.year)
        .toList();
  }

  List<ScheduleRegistration> _getRegistrationsForShiftDay(
      String shiftId, DateTime day) {
    return _registrations
        .where((r) =>
            r.shiftId == shiftId &&
            r.date.day == day.day &&
            r.date.month == day.month &&
            r.date.year == day.year)
        .toList();
  }

  // ══════════════════════════════════════════════
  //  SHIFT-CENTRIC TABLE (Grid layout — tap day header to zoom)
  // ══════════════════════════════════════════════
  Widget _buildShiftCentricTable() {
    final days =
        List.generate(7, (i) => _selectedWeekStart.add(Duration(days: i)));
    final dayLabels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    final now = DateTime.now();
    final canEdit = Provider.of<PermissionProvider>(context, listen: false)
        .canEdit('WorkSchedule');
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
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row: corner + day columns
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF0891B2).withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Container(
                  width: 80,
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  decoration: const BoxDecoration(
                      border:
                          Border(right: BorderSide(color: Color(0xFFE4E4E7)))),
                  child: Text(tr('Ca / Ngày'),
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0891B2)),
                      textAlign: TextAlign.center),
                ),
                ...List.generate(7, (di) {
                  final day = days[di];
                  final isToday = day.year == now.year &&
                      day.month == now.month &&
                      day.day == now.day;
                  final isSun = di == 6;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _focusedDayIndex = di),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: isToday
                              ? const Color(0xFF0891B2).withValues(alpha: 0.12)
                              : null,
                          border: di < 6
                              ? const Border(
                                  right: BorderSide(color: Color(0xFFE4E4E7)))
                              : null,
                        ),
                        child: Column(
                          children: [
                            Text(tr(dayLabels[di]),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: isToday
                                      ? const Color(0xFF0891B2)
                                      : (isSun
                                          ? const Color(0xFFEF4444)
                                          : const Color(0xFF71717A)),
                                )),
                            Text(tr('${day.day}/${day.month}'),
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isToday
                                      ? const Color(0xFF0891B2)
                                      : const Color(0xFF71717A),
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
            Padding(
                padding: EdgeInsets.all(24),
                child: Text(tr('Chưa có ca làm việc'),
                    style: TextStyle(color: Color(0xFF71717A))))
          else
            ..._shifts.asMap().entries.map((entry) {
              final si = entry.key;
              final shift = entry.value;
              final isLast = si == _shifts.length - 1;
              return Container(
                decoration: BoxDecoration(
                  border: isLast
                      ? null
                      : const Border(
                          bottom: BorderSide(color: Color(0xFFE4E4E7))),
                ),
                child: Row(
                  children: [
                    // Shift name cell
                    Container(
                      width: 80,
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 4),
                      decoration: const BoxDecoration(
                          border: Border(
                              right: BorderSide(color: Color(0xFFE4E4E7)))),
                      child: Column(
                        children: [
                          Text(tr(shift.name),
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF18181B)),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(
                              tr('${_formatTime(shift.startTime)}-${_formatTime(shift.endTime)}'),
                              style: const TextStyle(
                                  fontSize: 9, color: Color(0xFF71717A)),
                              textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                    // Day cells for this shift
                    ...List.generate(7, (di) {
                      final day = days[di];
                      final isToday = day.year == now.year &&
                          day.month == now.month &&
                          day.day == now.day;
                      return Expanded(
                          child: _buildManagerGridCell(
                              shift, day, isToday, canEdit));
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
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with back button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF0891B2).withValues(alpha: 0.08),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                InkWell(
                  onTap: () => setState(() => _focusedDayIndex = null),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE4E4E7))),
                    child: const Icon(Icons.arrow_back,
                        size: 18, color: Color(0xFF0891B2)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(tr('$dayLabel — $dateStr'),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0891B2))),
                ),
              ],
            ),
          ),
          // Shift rows with employee names
          if (_shifts.isEmpty)
            Padding(
                padding: EdgeInsets.all(24),
                child: Text(tr('Chưa có ca'),
                    style: TextStyle(color: Color(0xFF71717A))))
          else
            ..._shifts.asMap().entries.map((entry) {
              final si = entry.key;
              final shift = entry.value;
              final isLast = si == _shifts.length - 1;
              final schedules = _getSchedulesForShiftDay(shift.id, day);
              final pendingLocal = _getPendingForShiftDay(shift.id, day);
              final submittedRegs = _getRegistrationsForShiftDay(shift.id, day);
              final uniqueRegs = submittedRegs
                  .where((r) => schedules
                      .every((s) => s.employeeUserId != r.employeeUserId))
                  .toList();

              return Container(
                decoration: BoxDecoration(
                    border: isLast
                        ? null
                        : const Border(
                            bottom: BorderSide(color: Color(0xFFE4E4E7)))),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Shift header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: const Color(0xFF0891B2)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(tr(shift.name),
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0891B2))),
                          ),
                          const SizedBox(width: 8),
                          Text(
                              tr('${_formatTime(shift.startTime)} - ${_formatTime(shift.endTime)}'),
                              style: const TextStyle(
                                  fontSize: 11, color: Color(0xFF71717A))),
                          const Spacer(),
                          Text(
                              tr('${schedules.length + uniqueRegs.length + pendingLocal.length} NV'),
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0891B2))),
                          if (canEdit) ...[
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () =>
                                  _showAssignEmployeeToShiftDialog(shift, day),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                    color: const Color(0xFF0891B2)
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6)),
                                child: const Icon(Icons.person_add,
                                    size: 16, color: Color(0xFF0891B2)),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Employee list
                      if (schedules.isEmpty &&
                          uniqueRegs.isEmpty &&
                          pendingLocal.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(tr('Chưa có nhân viên'),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[400],
                                  fontStyle: FontStyle.italic)),
                        )
                      else
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            // Confirmed schedules
                            ...schedules.map((ws) {
                              final emp = _employees.firstWhere(
                                  (e) =>
                                      _effectiveUserId(e) == ws.employeeUserId,
                                  orElse: () => Employee.empty());
                              return _empChip(emp.fullName,
                                  HrmPageChrome.primaryNavy, Icons.check);
                            }),
                            // Submitted registrations
                            ...uniqueRegs.map((reg) {
                              final emp = _employees.firstWhere(
                                  (e) =>
                                      _effectiveUserId(e) == reg.employeeUserId,
                                  orElse: () => Employee.empty());
                              Color c;
                              IconData ic;
                              switch (reg.status) {
                                case ScheduleRegistrationStatus.approved:
                                  c = const Color(0xFF059669);
                                  ic = Icons.check_circle;
                                  break;
                                case ScheduleRegistrationStatus.rejected:
                                  c = const Color(0xFFEF4444);
                                  ic = Icons.cancel;
                                  break;
                                default:
                                  c = const Color(0xFFD97706);
                                  ic = Icons.hourglass_empty;
                              }
                              return _empChip(emp.fullName, c, ic);
                            }),
                            // Local pending
                            ...pendingLocal.map((reg) {
                              final emp = _employees.firstWhere(
                                  (e) =>
                                      _effectiveUserId(e) == reg['employeeId'],
                                  orElse: () => Employee.empty());
                              return _empChip(emp.fullName,
                                  const Color(0xFF8B5CF6), Icons.add_circle);
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
          Text(tr(name),
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildManagerGridCell(
      Shift shift, DateTime day, bool isToday, bool canEdit) {
    final schedules = _getSchedulesForShiftDay(shift.id, day);
    final pendingLocal = _getPendingForShiftDay(shift.id, day);
    final submittedRegs = _getRegistrationsForShiftDay(shift.id, day);
    final pendingRegs = submittedRegs
        .where((r) => r.status == ScheduleRegistrationStatus.pending)
        .toList();
    final approvedRegs = submittedRegs
        .where((r) => r.status == ScheduleRegistrationStatus.approved)
        .toList();
    // Unique employees: exclude duplicates between confirmed and submitted
    final confirmedCount = schedules.length;
    final approvedCount = approvedRegs
        .where(
            (r) => schedules.every((s) => s.employeeUserId != r.employeeUserId))
        .length;
    final pendingCount = pendingRegs
        .where(
            (r) => schedules.every((s) => s.employeeUserId != r.employeeUserId))
        .length;
    final localCount = pendingLocal.length;
    final totalCount =
        confirmedCount + approvedCount + pendingCount + localCount;

    // Quota check (theo thứ + phòng ban)
    final staffing = _evaluateShiftDayStaffing(shift.id, day);
    final quota = _getQuotaForShift(shift.id);
    final (_, maxForDay) = quota != null
        ? StaffingQuotaUtils.limitsForDate(quota, day)
        : (0, 0);
    final bool belowWarning = staffing.hasUnderMin;
    final bool aboveMax = staffing.hasOverMax;
    final bool nearMax = staffing.hasNearMax && !aboveMax;

    Color bgColor;
    Color borderColor;
    Widget content;

    if (totalCount == 0) {
      bgColor = belowWarning
          ? const Color(0xFFEFF6FF)
          : (isToday ? const Color(0xFFF1F5F9) : Colors.white);
      borderColor =
          belowWarning ? const Color(0xFF3B82F6) : const Color(0xFFE4E4E7);
      content = belowWarning
          ? const Icon(Icons.warning_amber, size: 14, color: Color(0xFF3B82F6))
          : Icon(Icons.add, size: 14, color: Colors.grey[300]);
    } else {
      // Primary color by highest-priority status present
      if (confirmedCount > 0) {
        bgColor = HrmPageChrome.primaryNavy.withValues(alpha: 0.08);
        borderColor = HrmPageChrome.primaryNavy;
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
        bgColor = const Color(0xFFEFF6FF);
        borderColor = const Color(0xFF3B82F6);
      } else if (aboveMax || nearMax) {
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
              if (belowWarning)
                const Padding(
                    padding: EdgeInsets.only(right: 2),
                    child: Icon(Icons.arrow_downward,
                        size: 10, color: Color(0xFF3B82F6))),
              if (aboveMax || nearMax)
                const Padding(
                    padding: EdgeInsets.only(right: 2),
                    child: Icon(Icons.arrow_upward,
                        size: 10, color: Color(0xFFF59E0B))),
              Text(tr('$totalCount'),
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      color: belowWarning
                          ? const Color(0xFF3B82F6)
                          : (aboveMax || nearMax
                              ? const Color(0xFFF59E0B)
                              : borderColor))),
              if (quota != null && maxForDay > 0)
                Text(tr('/$maxForDay'),
                    style:
                        const TextStyle(fontSize: 9, color: Color(0xFF71717A))),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (confirmedCount > 0) _statusDot(HrmPageChrome.primaryNavy),
              if (approvedCount > 0) _statusDot(const Color(0xFF059669)),
              if (pendingCount > 0) _statusDot(const Color(0xFFD97706)),
              if (localCount > 0) _statusDot(const Color(0xFF8B5CF6)),
            ],
          ),
        ],
      );
    }

    return GestureDetector(
      onTap: canEdit
          ? () => _showAssignEmployeeToShiftDialog(shift, day)
          : () => _showCellDetailDialog(shift, day),
      onLongPress: (belowWarning && canEdit)
          ? () => _showRequestCoverageDialog(
              preselectedShift: shift, preselectedDate: day)
          : null,
      child: Container(
        height: 56,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: bgColor,
          border: Border.all(
              color: borderColor,
              width: (totalCount > 0 || belowWarning) ? 1.5 : 0.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Center(child: content),
      ),
    );
  }

  Widget _statusDot(Color color) {
    return Container(
      width: 6,
      height: 6,
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
      builder: (ctx) => ScrollableAlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(shift.name),
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF18181B))),
          Text(
              tr('${DateFormat('EEEE dd/MM/yyyy', 'vi').format(day)} • ${_formatTime(shift.startTime)}-${_formatTime(shift.endTime)}'),
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
                  Text(tr('Đã xếp lịch'),
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: HrmPageChrome.primaryNavy)),
                  const SizedBox(height: 4),
                  ...schedules.map((ws) {
                    final emp = _employees.firstWhere(
                        (e) => _effectiveUserId(e) == ws.employeeUserId,
                        orElse: () => Employee.empty());
                    return _detailEmpRow(
                        emp.fullName, HrmPageChrome.primaryNavy, Icons.check);
                  }),
                  const SizedBox(height: 8),
                ],
                if (submittedRegs.isNotEmpty) ...[
                  ...submittedRegs
                      .where((r) => schedules
                          .every((s) => s.employeeUserId != r.employeeUserId))
                      .map((reg) {
                    final emp = _employees.firstWhere(
                        (e) => _effectiveUserId(e) == reg.employeeUserId,
                        orElse: () => Employee.empty());
                    Color c;
                    IconData ic;
                    String label;
                    switch (reg.status) {
                      case ScheduleRegistrationStatus.approved:
                        c = const Color(0xFF059669);
                        ic = Icons.check_circle;
                        label = 'Duyệt';
                        break;
                      case ScheduleRegistrationStatus.rejected:
                        c = const Color(0xFFEF4444);
                        ic = Icons.cancel;
                        label = 'Từ chối';
                        break;
                      default:
                        c = const Color(0xFFD97706);
                        ic = Icons.hourglass_empty;
                        label = 'Chờ duyệt';
                    }
                    return _detailEmpRow('${emp.fullName} ($label)', c, ic);
                  }),
                  const SizedBox(height: 8),
                ],
                if (pendingLocal.isNotEmpty) ...[
                  Text(tr('Chưa gửi'),
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: Color(0xFF8B5CF6))),
                  const SizedBox(height: 4),
                  ...pendingLocal.map((reg) {
                    final emp = _employees.firstWhere(
                        (e) => _effectiveUserId(e) == reg['employeeId'],
                        orElse: () => Employee.empty());
                    return _detailEmpRow(emp.fullName, const Color(0xFF8B5CF6),
                        Icons.add_circle);
                  }),
                ],
                if (schedules.isEmpty &&
                    submittedRegs.isEmpty &&
                    pendingLocal.isEmpty)
                  Text(tr('Chưa có nhân viên nào'),
                      style: TextStyle(color: Color(0xFF71717A), fontSize: 13)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng')))
        ],
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
          Expanded(
              child: Text(tr(name),
                  style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.w500))),
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
    for (final r in _getRegistrationsForShiftDay(shift.id, day)
        .where((r) => r.status != ScheduleRegistrationStatus.rejected)) {
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
          final availableFiltered = filtered
              .where((e) => !assignedIds.contains(_effectiveUserId(e)))
              .toList();
          final allSelected = availableFiltered.isNotEmpty &&
              availableFiltered
                  .every((e) => selectedIds.contains(_effectiveUserId(e)));

          return ScrollableAlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: const Color(0xFF0891B2).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.person_add,
                      color: Color(0xFF0891B2), size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(tr('Thêm NV vào ${shift.name}'),
                        style: const TextStyle(
                            color: Color(0xFF18181B),
                            fontWeight: FontWeight.bold,
                            fontSize: 16))),
              ]),
              const SizedBox(height: 4),
              Text(
                  tr('${DateFormat('EEEE dd/MM/yyyy', 'vi').format(day)}  •  ${_formatTime(shift.startTime)} - ${_formatTime(shift.endTime)}'),
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF71717A))),
            ]),
            content: SizedBox(
              width: Responsive.dialogWidth(context),
              height: 450,
              child: Column(children: [
                TextField(
                  controller: searchCtrl,
                  decoration: InputDecoration(
                    hintText: tr('Tìm nhân viên...'),
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    isDense: true,
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
                      Icon(
                          allSelected
                              ? Icons.check_box
                              : Icons.check_box_outline_blank,
                          color: const Color(0xFF0891B2),
                          size: 20),
                      const SizedBox(width: 4),
                      Text(tr(allSelected ? 'Bỏ chọn tất cả' : 'Chọn tất cả'),
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF0891B2))),
                    ]),
                  ),
                  const Spacer(),
                  if (selectedIds.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: const Color(0xFF0891B2).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12)),
                      child: Text(tr('Đã chọn: ${selectedIds.length}'),
                          style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF0891B2),
                              fontWeight: FontWeight.bold)),
                    ),
                ]),
                const SizedBox(height: 8),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(child: Text(tr('Không tìm thấy nhân viên')))
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
                                        tr(emp.firstName.isNotEmpty
                                            ? emp.firstName[0].toUpperCase()
                                            : '?'),
                                        style: const TextStyle(
                                            color: Colors.grey,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    )
                                  : Icon(
                                      isSelected
                                          ? Icons.check_box
                                          : Icons.check_box_outline_blank,
                                      color: isSelected
                                          ? const Color(0xFF0891B2)
                                          : Colors.grey[400],
                                    ),
                              title: Text(tr(emp.fullName),
                                  style: TextStyle(
                                    color: isAssigned
                                        ? Colors.grey
                                        : isSelected
                                            ? const Color(0xFF0891B2)
                                            : null,
                                    fontSize: 13,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                  )),
                              subtitle: Text(tr(emp.employeeCode),
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.grey[500])),
                              trailing: isAssigned
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                          color: const Color(0xFFE5E7EB),
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      child: Text(tr('Đã phân'),
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF71717A))),
                                    )
                                  : isSelected
                                      ? const Icon(Icons.check_circle,
                                          color: Color(0xFF0891B2))
                                      : null,
                              onTap: isAssigned
                                  ? null
                                  : () {
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
              TextButton(
                  onPressed: () {
                    searchCtrl.dispose();
                    Navigator.pop(ctx);
                  },
                  child: Text(tr('Đóng'),
                      style: TextStyle(color: Color(0xFF71717A)))),
              FilledButton.icon(
                onPressed: selectedIds.isEmpty
                    ? null
                    : () {
                        searchCtrl.dispose();
                        Navigator.pop(ctx);
                        for (final empId in selectedIds) {
                          _addPendingRegistration(
                              empId, day, shift.id, false, null);
                        }
                      },
                icon: const Icon(Icons.check, size: 18),
                label: Text(tr('${tr('Thêm ')}${selectedIds.isEmpty ? '' : '(${selectedIds.length})'}')),
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

  Widget _buildScheduleCell(Employee employee, DateTime day,
      List<WorkSchedule> schedules, List<Map<String, dynamic>> pendingRegs,
      [List<ScheduleRegistration> submittedRegs = const []]) {
    // Nếu có pending registration (chờ gửi - màu vàng)
    if (pendingRegs.isNotEmpty) {
      // Day off pending
      if (pendingRegs.first['isDayOff'] == true) {
        final note = pendingRegs.first['note'] ?? 'Nghỉ phép';
        return InkWell(
          onTap: () =>
              _removePendingRegistration(_effectiveUserId(employee), day),
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
                  tr(note),
                  style: const TextStyle(
                      color: Color(0xFF856404),
                      fontWeight: FontWeight.bold,
                      fontSize: 10),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(tr('Chờ gửi'),
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
        final shiftA = _shifts.firstWhere((s) => s.id == a['shiftId'],
            orElse: () => Shift(
                id: '',
                name: '',
                code: '',
                startTime: '99:99',
                endTime: '',
                isActive: true,
                createdAt: DateTime.now()));
        final shiftB = _shifts.firstWhere((s) => s.id == b['shiftId'],
            orElse: () => Shift(
                id: '',
                name: '',
                code: '',
                startTime: '99:99',
                endTime: '',
                isActive: true,
                createdAt: DateTime.now()));
        return shiftA.startTime.compareTo(shiftB.startTime);
      });
      final shiftNames = sortedPendingRegs.map((reg) {
        final shift = _shifts.firstWhere(
          (s) => s.id == reg['shiftId'],
          orElse: () => Shift(
              id: '',
              name: 'Ca',
              code: '',
              startTime: '',
              endTime: '',
              isActive: true,
              createdAt: DateTime.now()),
        );
        return shift.name;
      }).toList();
      return InkWell(
        onTap: () =>
            _removePendingRegistration(_effectiveUserId(employee), day),
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
                    tr(name),
                    style: const TextStyle(
                        color: Color(0xFF856404),
                        fontWeight: FontWeight.bold,
                        fontSize: 10),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  )),
              Text(tr('Chờ gửi'),
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
        final leaveLabel =
            (dayOffSchedule.note != null && dayOffSchedule.note!.isNotEmpty)
                ? dayOffSchedule.note!
                : 'Nghỉ phép';
        return InkWell(
          onTap: () => _showRegisterDialog(employee, day),
          child: Container(
            width: 100,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [HrmPageChrome.primaryNavy, Color(0xFF059669)],
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
                  tr(leaveLabel),
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 9),
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
          final shiftA = a.shiftId != null
              ? _shifts.firstWhere((s) => s.id == a.shiftId,
                  orElse: () => Shift(
                      id: '',
                      name: '',
                      code: '',
                      startTime: '99:99',
                      endTime: '',
                      isActive: true,
                      createdAt: DateTime.now()))
              : null;
          final shiftB = b.shiftId != null
              ? _shifts.firstWhere((s) => s.id == b.shiftId,
                  orElse: () => Shift(
                      id: '',
                      name: '',
                      code: '',
                      startTime: '99:99',
                      endTime: '',
                      isActive: true,
                      createdAt: DateTime.now()))
              : null;
          return (shiftA?.startTime ?? '99:99')
              .compareTo(shiftB?.startTime ?? '99:99');
        });
        final shiftWidgets = <Widget>[];
        for (final schedule in sortedSchedules) {
          final shift = schedule.shiftId != null
              ? _shifts.firstWhere(
                  (s) => s.id == schedule.shiftId,
                  orElse: () => Shift(
                      id: '',
                      name: 'Ca làm',
                      code: '',
                      startTime: '',
                      endTime: '',
                      isActive: true,
                      createdAt: DateTime.now()),
                )
              : null;
          shiftWidgets.add(Text(
            tr(shift?.name ?? 'Ca làm'),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ));
          if (shift != null) {
            shiftWidgets.add(Text(
              tr('${_formatTime(shift.startTime)} - ${_formatTime(shift.endTime)}'),
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
                colors: [HrmPageChrome.primaryNavy, HrmPageChrome.primaryNavy],
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
      final activeRegs = submittedRegs
          .where((r) => r.status != ScheduleRegistrationStatus.approved)
          .toList();
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
            borderColor = HrmPageChrome.primaryNavy;
            statusText = 'Đã duyệt';
        }

        final sortedActiveRegs = List<ScheduleRegistration>.from(activeRegs);
        sortedActiveRegs.sort((a, b) {
          final shiftA = a.shiftId != null
              ? _shifts.firstWhere((s) => s.id == a.shiftId,
                  orElse: () => Shift(
                      id: '',
                      name: '',
                      code: '',
                      startTime: '99:99',
                      endTime: '',
                      isActive: true,
                      createdAt: DateTime.now()))
              : null;
          final shiftB = b.shiftId != null
              ? _shifts.firstWhere((s) => s.id == b.shiftId,
                  orElse: () => Shift(
                      id: '',
                      name: '',
                      code: '',
                      startTime: '99:99',
                      endTime: '',
                      isActive: true,
                      createdAt: DateTime.now()))
              : null;
          return (shiftA?.startTime ?? '99:99')
              .compareTo(shiftB?.startTime ?? '99:99');
        });

        final regLabels = sortedActiveRegs.map((r) {
          if (r.isDayOff) return r.note ?? 'Nghỉ phép';
          final shift = r.shiftId != null
              ? _shifts.firstWhere((s) => s.id == r.shiftId,
                  orElse: () => Shift(
                      id: '',
                      name: 'Ca',
                      code: '',
                      startTime: '',
                      endTime: '',
                      isActive: true,
                      createdAt: DateTime.now()))
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
                      tr(label),
                      style: TextStyle(
                          color: borderColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 10),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    )),
                Text(
                  tr(statusText),
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
          border: Border.all(
              color: const Color(0xFFE4E4E7), style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_circle_outline, color: Colors.grey[400], size: 18),
            const SizedBox(height: 2),
            Text(tr('Đăng ký'),
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
        builder: (context, setDialogState) => ScrollableAlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(tr('Đăng ký ca - ${employee.lastName} ${employee.firstName}'),
            style: const TextStyle(
                color: Color(0xFF18181B), fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('${tr('Ngày: ')}${DateFormat('EEEE, dd/MM/yyyy', 'vi').format(day)}'),
                style: const TextStyle(color: Color(0xFF71717A)),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: Text(tr('Nghỉ phép'),
                    style: TextStyle(color: Color(0xFF18181B))),
                value: isDayOff,
                onChanged: (value) => setDialogState(() {
                  isDayOff = value;
                  if (value) selectedShiftIds.clear();
                }),
                activeThumbColor: HrmPageChrome.primaryNavy,
              ),
              if (isDayOff) ...[
                const SizedBox(height: 8),
                Text(tr('Loại nghỉ phép:'),
                    style: TextStyle(color: Color(0xFF18181B))),
                const SizedBox(height: 8),
                ...[
                  'Nghỉ phép năm',
                  'Nghỉ phép có lương',
                  'Nghỉ phép không lương'
                ].map((type) => RadioListTile<String>(
                      title: Text(tr(type),
                          style: const TextStyle(color: Color(0xFF18181B))),
                      value: type,
                      // ignore: deprecated_member_use
                      groupValue: leaveType,
                      // ignore: deprecated_member_use
                      onChanged: (value) =>
                          setDialogState(() => leaveType = value!),
                      activeColor: HrmPageChrome.primaryNavy,
                      dense: true,
                    )),
              ],
              if (!isDayOff) ...[
                const SizedBox(height: 16),
                Text(tr('Chọn ca làm việc:'),
                    style: TextStyle(color: Color(0xFF18181B))),
                const SizedBox(height: 8),
                ..._shifts.map((shift) => CheckboxListTile(
                      title: Text(tr(shift.name),
                          style: const TextStyle(color: Color(0xFF18181B))),
                      subtitle: Text(
                        tr('${_formatTime(shift.startTime)} - ${_formatTime(shift.endTime)}'),
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
                      activeColor: HrmPageChrome.primaryNavy,
                      controlAffinity: ListTileControlAffinity.leading,
                    )),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:
                  Text(tr('Hủy'), style: TextStyle(color: Color(0xFF71717A))),
            ),
            FilledButton(
              onPressed: () {
                if (!isDayOff && selectedShiftIds.isEmpty) {
                  appNotification.showWarning(
                    title: 'Thiếu thông tin',
                    message: tr('Vui lòng chọn ít nhất một ca làm việc'),
                  );
                  return;
                }
                if (isDayOff) {
                  _addPendingRegistration(
                      _effectiveUserId(employee), day, null, true, leaveType);
                } else {
                  for (final shiftId in selectedShiftIds) {
                    _addPendingRegistration(
                        _effectiveUserId(employee), day, shiftId, false, null);
                  }
                }
                Navigator.pop(context);
              },
              style: FilledButton.styleFrom(backgroundColor: HrmPageChrome.primaryNavy),
              child: Text(tr('Thêm vào danh sách chờ')),
            ),
          ],
        ),
      ),
    );
  }

  void _addPendingRegistration(String employeeId, DateTime day, String? shiftId,
      bool isDayOff, String? note) {
    setState(() {
      if (isDayOff) {
        // For day off, remove all existing pending for same employee and day
        _pendingRegistrations.removeWhere(
          (r) =>
              r['employeeId'] == employeeId &&
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
          (r) =>
              r['employeeId'] == employeeId &&
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
        (r) =>
            r['employeeId'] == employeeId &&
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
                  Text(tr('Danh sách đăng ký chờ gửi (${_pendingRegistrations.length})'),
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
                  if (_perm.canDelete('WorkSchedule'))
                    OutlinedButton.icon(
                      onPressed: _clearAllPendingRegistrations,
                      icon: const Icon(Icons.delete_sweep, size: 18),
                      label: Text(tr('Xóa tất cả')),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF856404),
                        side: const BorderSide(color: Color(0xFF856404)),
                      ),
                    ),
                  if (_perm.canCreate('WorkSchedule'))
                    FilledButton.icon(
                      onPressed: _submitAllRegistrations,
                      icon: const Icon(Icons.send, size: 18),
                      label: Text(tr('Gửi tất cả đăng ký')),
                      style: FilledButton.styleFrom(
                          backgroundColor: HrmPageChrome.primaryNavy),
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
                  ? _shifts.firstWhere((s) => s.id == reg['shiftId'],
                      orElse: () => Shift(
                          id: '',
                          name: 'Ca',
                          code: '',
                          startTime: '',
                          endTime: '',
                          isActive: true,
                          createdAt: DateTime.now()))
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
                  tr('${employee.firstName} - ${DateFormat('dd/MM').format(reg['date'])} - ${reg['isDayOff'] == true ? (reg['note'] ?? 'Nghỉ phép') : shift?.name ?? ''}'),
                  style:
                      const TextStyle(color: Color(0xFF856404), fontSize: 12),
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
          'shiftId': (shiftId != null && shiftId.toString().isNotEmpty)
              ? shiftId
              : null,
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
            message: tr('Đã gửi $successCount đăng ký'),
          );
        } else {
          appNotification.showError(
            title: 'Đăng ký không hoàn tất',
            message: tr('Thành công: $successCount, Thất bại: $failCount'),
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
      final weekStart = DateTime(_selectedWeekStart.year,
          _selectedWeekStart.month, _selectedWeekStart.day);
      final end = DateTime(weekEnd.year, weekEnd.month, weekEnd.day);
      return !regDate.isBefore(weekStart) && !regDate.isAfter(end);
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

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
              const Icon(Icons.list_alt, color: HrmPageChrome.primaryNavy),
              const SizedBox(width: 8),
              Text(tr('Danh sách yêu cầu đã gửi (${weekRegs.length})'),
                style: const TextStyle(
                  color: Color(0xFF18181B),
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              // Status summary
              _buildStatusBadge(
                  'Chờ duyệt',
                  const Color(0xFFF59E0B),
                  weekRegs
                      .where(
                          (r) => r.status == ScheduleRegistrationStatus.pending)
                      .length),
              const SizedBox(width: 8),
              _buildStatusBadge(
                  'Đã duyệt',
                  HrmPageChrome.primaryNavy,
                  weekRegs
                      .where((r) =>
                          r.status == ScheduleRegistrationStatus.approved)
                      .length),
              const SizedBox(width: 8),
              _buildStatusBadge(
                  'Từ chối',
                  const Color(0xFFEF4444),
                  weekRegs
                      .where((r) =>
                          r.status == ScheduleRegistrationStatus.rejected)
                      .length),
            ],
          ),
          const SizedBox(height: 12),
          ...weekRegs.map((reg) {
            final employee = _employees.firstWhere(
              (e) => _effectiveUserId(e) == reg.employeeUserId,
              orElse: () => Employee.empty(),
            );
            final shift = reg.shiftId != null && reg.shiftId!.isNotEmpty
                ? _shifts.firstWhere((s) => s.id == reg.shiftId,
                    orElse: () => Shift(
                        id: '',
                        name: 'Ca',
                        code: '',
                        startTime: '',
                        endTime: '',
                        isActive: true,
                        createdAt: DateTime.now()))
                : null;

            Color statusColor;
            IconData statusIcon;
            String statusText;
            switch (reg.status) {
              case ScheduleRegistrationStatus.approved:
                statusColor = HrmPageChrome.primaryNavy;
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
                          tr('${employee.fullName} - ${DateFormat('dd/MM/yyyy (EEEE)', 'vi').format(reg.date)}'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: Color(0xFF18181B)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          tr(reg.isDayOff
                              ? (reg.note != null && reg.note!.isNotEmpty
                                  ? reg.note!
                                  : 'Nghỉ phép')
                              : (shift?.name ?? 'Ca')),
                          style: const TextStyle(
                              color: Color(0xFF71717A), fontSize: 12),
                        ),
                        if (reg.status == ScheduleRegistrationStatus.rejected &&
                            reg.rejectionReason != null &&
                            reg.rejectionReason!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(tr('Lý do: ${reg.rejectionReason}'),
                            style: const TextStyle(
                                color: Color(0xFFEF4444),
                                fontSize: 11,
                                fontStyle: FontStyle.italic),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Delete button for pending registrations
                  if (reg.status == ScheduleRegistrationStatus.pending &&
                      Provider.of<PermissionProvider>(context, listen: false)
                          .canDelete('WorkSchedule')) ...[
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: Color(0xFFEF4444), size: 20),
                      tooltip: tr('Xóa đăng ký'),
                      onPressed: () => _deleteRegistration(reg.id),
                    ),
                    const SizedBox(width: 4),
                  ],
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      tr(statusText),
                      style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 11),
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
        tr('$label: $count'),
        style:
            TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }

  // ══════════════════════════════════════════════
  //  APPROVED SCHEDULE TABLE (Lịch đã duyệt)
  // ══════════════════════════════════════════════
  // ignore: unused_element
  Widget _buildApprovedScheduleTable() {
    final days =
        List.generate(7, (i) => _selectedWeekStart.add(Duration(days: i)));
    final dayNames = [
      'THỨ 2',
      'THỨ 3',
      'THỨ 4',
      'THỨ 5',
      'THỨ 6',
      'THỨ 7',
      'CHỦ NHẬT'
    ];
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
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 768;
          final totalPages = (emps.length / _schedulePageSize).ceil();
          final safePage =
              _approvedPage.clamp(1, totalPages == 0 ? 1 : totalPages);
          final startIdx = isMobile ? 0 : (safePage - 1) * _schedulePageSize;
          final endIdx = isMobile
              ? emps.length
              : (startIdx + _schedulePageSize).clamp(0, emps.length);
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
                  headingRowColor: WidgetStateProperty.all(
                      HrmPageChrome.primaryNavy.withValues(alpha: 0.08)),
                  dataRowColor: WidgetStateProperty.all(Colors.white),
                  dataRowMinHeight: 56,
                  dataRowMaxHeight: 140,
                  border:
                      TableBorder.all(color: const Color(0xFFE4E4E7), width: 1),
                  columns: [
                    DataColumn(
                      label: Expanded(
                          child: Text(tr('NHÂN VIÊN'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: HrmPageChrome.primaryNavy,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12))),
                    ),
                    ...List.generate(7, (i) {
                      final day = days[i];
                      final isToday = day.day == today.day &&
                          day.month == today.month &&
                          day.year == today.year;
                      return DataColumn(
                        label: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(tr(dayNames[i]),
                                style: TextStyle(
                                  color: isToday
                                      ? HrmPageChrome.primaryNavy
                                      : const Color(0xFF18181B),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                )),
                            Text(tr(dateFormat.format(day)),
                                style: TextStyle(
                                  color: isToday
                                      ? HrmPageChrome.primaryNavy
                                      : const Color(0xFF71717A),
                                  fontSize: 11,
                                )),
                          ],
                        ),
                      );
                    }),
                    DataColumn(
                      label: Expanded(
                          child: Text(tr('TỔNG CA'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: HrmPageChrome.primaryNavy,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12))),
                    ),
                  ],
                  rows: pageEmps.isEmpty
                      ? [
                          DataRow(cells: [
                            DataCell(Center(
                                child: Text(tr('Chưa có nhân viên'),
                                    style:
                                        TextStyle(color: Colors.grey[400])))),
                            ...List.generate(
                                8, (_) => const DataCell(Text(''))),
                          ]),
                        ]
                      : _buildApprovedDesktopRows(pageEmps, days),
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
                            value: _schedulePageSize,
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
                                  _schedulePageSize = v;
                                  _approvedPage = 1;
                                });
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                          icon: const Icon(Icons.first_page),
                          onPressed: safePage > 1
                              ? () => setState(() => _approvedPage = 1)
                              : null),
                      IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: safePage > 1
                              ? () => setState(() => _approvedPage--)
                              : null),
                      Text(
                          tr('${(safePage - 1) * _schedulePageSize + 1}-${(safePage * _schedulePageSize).clamp(0, emps.length)} / ${emps.length}'),
                          style: const TextStyle(fontSize: 13)),
                      IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: safePage < totalPages
                              ? () => setState(() => _approvedPage++)
                              : null),
                      IconButton(
                          icon: const Icon(Icons.last_page),
                          onPressed: safePage < totalPages
                              ? () => setState(() => _approvedPage = totalPages)
                              : null),
                    ],
                  ),
                ),
              ),
          ]);
        },
      ),
    );
  }

  Widget _buildApprovedChip(String label, Color color, IconData icon,
      {String? time}) {
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
                Text(tr(label),
                    style: TextStyle(
                        fontSize: 10,
                        color: color,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                if (time != null && time.isNotEmpty)
                  Text(tr(time),
                      style: TextStyle(
                          fontSize: 9, color: color.withValues(alpha: 0.7)),
                      overflow: TextOverflow.ellipsis),
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
          Flexible(
              child: Text(tr(title),
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13, color: color),
                  overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 8),
          Flexible(
              child: Text(tr('Tuần $weekNumber: ${dateFormat.format(_selectedWeekStart)} - ${dateFormat.format(weekEnd)}'),
                  style: TextStyle(
                      fontSize: 12, color: color.withValues(alpha: 0.8)),
                  overflow: TextOverflow.ellipsis)),
          if (_selectedDepartment != null) ...[
            const SizedBox(width: 8),
            Flexible(
                child: Text(tr('Phòng ban: $_selectedDepartment'),
                    style: TextStyle(
                        fontSize: 12, color: color.withValues(alpha: 0.8)),
                    overflow: TextOverflow.ellipsis)),
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
          Text(tr('Chú thích: '),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF71717A))),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                ..._shifts.map((s) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: HrmPageChrome.primaryNavy,
                                borderRadius: BorderRadius.circular(4))),
                        const SizedBox(width: 4),
                        Text(
                            tr('${s.name}: ${_formatTime(s.startTime)}-${_formatTime(s.endTime)}'),
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF71717A))),
                      ],
                    )),
                _buildCompactLegendDot(HrmPageChrome.primaryNavy, 'Đã duyệt'),
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
        Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 4),
        Text(tr(label),
            style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }

  // ignore: unused_element
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
          Text(tr('Chú thích:'),
            style: TextStyle(
                color: Color(0xFF18181B),
                fontWeight: FontWeight.bold,
                fontSize: 16),
          ),
          const SizedBox(height: 12),
          // Shift list with times
          if (_shifts.isNotEmpty) ...[
            Text(tr('Danh sách ca làm việc:'),
                style: TextStyle(
                    color: Color(0xFF71717A),
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: _shifts.map((shift) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: HrmPageChrome.primaryNavy.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: HrmPageChrome.primaryNavy,
                            borderRadius: BorderRadius.circular(4)),
                      ),
                      const SizedBox(width: 8),
                      Text(tr(shift.name),
                          style: const TextStyle(
                              color: Color(0xFF18181B),
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                      const SizedBox(width: 8),
                      Text(
                          tr('${_formatTime(shift.startTime)} - ${_formatTime(shift.endTime)}'),
                          style: const TextStyle(
                              color: Color(0xFF71717A), fontSize: 12)),
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
          ],
          // Status legend
          Text(tr('Trạng thái:'),
              style: TextStyle(
                  color: Color(0xFF71717A),
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 24,
            runSpacing: 12,
            children: [
              _buildLegendItem(
                const LinearGradient(
                    colors: [HrmPageChrome.primaryNavy, HrmPageChrome.primaryNavy]),
                'Ca đã đăng ký',
              ),
              _buildLegendItem(
                const LinearGradient(
                    colors: [HrmPageChrome.primaryNavy, Color(0xFF059669)]),
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
                HrmPageChrome.primaryNavy,
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
        Text(tr(label),
            style: const TextStyle(color: Color(0xFF18181B), fontSize: 14)),
      ],
    );
  }

  Widget _buildLegendItemWithBorder(
      Color color, Color borderColor, String label,
      {bool isDashed = false}) {
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
        Text(tr(label),
            style: const TextStyle(color: Color(0xFF18181B), fontSize: 14)),
      ],
    );
  }

  // ==================== EXPORT METHODS ====================

  Future<void> _exportTableToPng(
      GlobalKey tableKey, String fileNamePrefix) async {
    try {
      final boundary =
          tableKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        appNotification.showError(
            title: 'Lỗi', message: tr('Không tìm thấy bảng dữ liệu để chụp'));
        return;
      }
      const pixelRatio = kIsWeb ? 2.0 : 3.0;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        appNotification.showError(title: 'Lỗi', message: tr('Không thể tạo ảnh'));
        return;
      }
      final pngBytes = byteData.buffer.asUint8List();
      final fileName =
          '${fileNamePrefix}_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.png';
      await file_saver.saveAndOpenFileBytes(pngBytes, fileName, 'image/png');
      appNotification.showSuccess(
          title: 'Xuất PNG', message: tr('Đã xuất ảnh $fileName'));
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
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildExportHeader(
                          'THEO CA LÀM VIỆC', const Color(0xFF0891B2)),
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
    await Future.delayed(const Duration(milliseconds: kIsWeb ? 500 : 200));

    try {
      final boundary = exportKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        appNotification.showError(title: 'Lỗi', message: tr('Không thể tạo ảnh'));
        entry.remove();
        return;
      }
      const pixelRatio = kIsWeb ? 2.0 : 3.0;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        appNotification.showError(title: 'Lỗi', message: tr('Không thể tạo ảnh'));
        entry.remove();
        return;
      }
      final pngBytes = byteData.buffer.asUint8List();
      final fileName =
          'TheoCalamViec_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.png';
      await file_saver.saveAndOpenFileBytes(pngBytes, fileName, 'image/png');
      appNotification.showSuccess(
          title: 'Xuất PNG', message: tr('Đã xuất ảnh $fileName'));
    } catch (e) {
      appNotification.showError(title: 'Lỗi xuất PNG', message: '$e');
    } finally {
      entry.remove();
    }
  }

  /// Full detail view for export: shows all 7 days with employee names per shift
  Widget _buildShiftCentricExportView() {
    final days =
        List.generate(7, (i) => _selectedWeekStart.add(Duration(days: i)));
    final dayLabels = [
      'Thứ 2',
      'Thứ 3',
      'Thứ 4',
      'Thứ 5',
      'Thứ 6',
      'Thứ 7',
      'CN'
    ];
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0891B2).withValues(alpha: 0.1),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(8)),
                ),
                child: Text(tr('${dayLabels[di]} ${dateFormat.format(day)}'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Color(0xFF0891B2))),
              ),
              // Shift rows for this day
              ..._shifts.map((shift) {
                final schedules = _getSchedulesForShiftDay(shift.id, day);
                final pendingLocal = _getPendingForShiftDay(shift.id, day);
                final submittedRegs =
                    _getRegistrationsForShiftDay(shift.id, day);
                final uniqueRegs = submittedRegs
                    .where((r) => schedules
                        .every((s) => s.employeeUserId != r.employeeUserId))
                    .toList();
                final names = <String>[];
                for (final ws in schedules) {
                  names.add(_employees
                      .firstWhere(
                          (e) => _effectiveUserId(e) == ws.employeeUserId,
                          orElse: () => Employee.empty())
                      .fullName);
                }
                for (final r in uniqueRegs) {
                  names.add(_employees
                      .firstWhere(
                          (e) => _effectiveUserId(e) == r.employeeUserId,
                          orElse: () => Employee.empty())
                      .fullName);
                }
                for (final p in pendingLocal) {
                  names.add(_employees
                      .firstWhere((e) => _effectiveUserId(e) == p['employeeId'],
                          orElse: () => Employee.empty())
                      .fullName);
                }

                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 120,
                        child: Text(
                            tr('${shift.name} (${_formatTime(shift.startTime)}-${_formatTime(shift.endTime)})'),
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF18181B))),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(tr(names.isEmpty ? '—' : names.join(', ')),
                            style: TextStyle(
                                fontSize: 11,
                                color: names.isEmpty
                                    ? Colors.grey
                                    : const Color(0xFF18181B))),
                      ),
                      SizedBox(
                          width: 30,
                          child: Text(tr('${names.length}'),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0891B2)))),
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
      final days =
          List.generate(7, (i) => _selectedWeekStart.add(Duration(days: i)));
      final dayNames = [
        'Thứ 2',
        'Thứ 3',
        'Thứ 4',
        'Thứ 5',
        'Thứ 6',
        'Thứ 7',
        'CN'
      ];
      final dateFormat = DateFormat('dd/MM');

      final wb = excel_lib.Excel.createExcel();
      final sheet = wb['Theo ca'];
      wb.delete('Sheet1');

      // Title
      final weekEnd = _selectedWeekStart.add(const Duration(days: 6));
      final weekNumber = _getWeekNumber(_selectedWeekStart);
      sheet
          .cell(
              excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
          .value = excel_lib.TextCellValue('THEO CA LÀM VIỆC');
      sheet
              .cell(excel_lib.CellIndex.indexByColumnRow(
                  columnIndex: 0, rowIndex: 1))
              .value =
          excel_lib.TextCellValue(
              'Tuần $weekNumber: ${DateFormat('dd/MM/yyyy').format(_selectedWeekStart)} - ${DateFormat('dd/MM/yyyy').format(weekEnd)}${_selectedDepartment != null ? ' | Phòng ban: $_selectedDepartment' : ''}');

      // Header
      const hRow = 3;
      sheet
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 0, rowIndex: hRow))
          .value = excel_lib.TextCellValue('CA LÀM VIỆC');
      for (int i = 0; i < 7; i++) {
        sheet
                .cell(excel_lib.CellIndex.indexByColumnRow(
                    columnIndex: i + 1, rowIndex: hRow))
                .value =
            excel_lib.TextCellValue(
                '${dayNames[i]} ${dateFormat.format(days[i])}');
      }
      sheet
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 8, rowIndex: hRow))
          .value = excel_lib.TextCellValue('TỔNG NV');

      // Data rows
      int row = hRow + 1;
      for (final shift in _shifts) {
        sheet
                .cell(excel_lib.CellIndex.indexByColumnRow(
                    columnIndex: 0, rowIndex: row))
                .value =
            excel_lib.TextCellValue(
                '${shift.name} (${_formatTime(shift.startTime)}-${_formatTime(shift.endTime)})');
        int total = 0;
        for (int d = 0; d < 7; d++) {
          final day = days[d];
          final schedules = _getSchedulesForShiftDay(shift.id, day);
          final pendingLocal = _getPendingForShiftDay(shift.id, day);
          final submittedRegs = _getRegistrationsForShiftDay(shift.id, day);
          final names = <String>[];
          for (final ws in schedules) {
            names.add(_employees
                .firstWhere((e) => _effectiveUserId(e) == ws.employeeUserId,
                    orElse: () => Employee.empty())
                .fullName);
          }
          for (final p in pendingLocal) {
            names.add(_employees
                .firstWhere((e) => _effectiveUserId(e) == p['employeeId'],
                    orElse: () => Employee.empty())
                .fullName);
          }
          for (final r in submittedRegs.where((r) =>
              schedules.every((s) => s.employeeUserId != r.employeeUserId))) {
            names.add(_employees
                .firstWhere((e) => _effectiveUserId(e) == r.employeeUserId,
                    orElse: () => Employee.empty())
                .fullName);
          }
          total += names.length;
          sheet
              .cell(excel_lib.CellIndex.indexByColumnRow(
                  columnIndex: d + 1, rowIndex: row))
              .value = excel_lib.TextCellValue(names.join(', '));
        }
        sheet
            .cell(excel_lib.CellIndex.indexByColumnRow(
                columnIndex: 8, rowIndex: row))
            .value = excel_lib.IntCellValue(total);
        row++;
      }

      // Legend
      row += 1;
      sheet
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 0, rowIndex: row))
          .value = excel_lib.TextCellValue('CHÚ THÍCH:');
      row++;
      for (final s in _shifts) {
        sheet
                .cell(excel_lib.CellIndex.indexByColumnRow(
                    columnIndex: 0, rowIndex: row))
                .value =
            excel_lib.TextCellValue(
                '${s.name}: ${_formatTime(s.startTime)} - ${_formatTime(s.endTime)}');
        row++;
      }

      _downloadExcel(wb, 'TheoCalamViec');
    } catch (e) {
      appNotification.showError(title: 'Lỗi xuất Excel', message: '$e');
    }
  }

  void _exportScheduleTableExcel() {
    try {
      final days =
          List.generate(7, (i) => _selectedWeekStart.add(Duration(days: i)));
      final dayNames = [
        'Thứ 2',
        'Thứ 3',
        'Thứ 4',
        'Thứ 5',
        'Thứ 6',
        'Thứ 7',
        'CN'
      ];
      final dateFormat = DateFormat('dd/MM');
      final emps = _filteredEmployees;

      final wb = excel_lib.Excel.createExcel();
      final sheet = wb['DangKy'];
      wb.delete('Sheet1');

      // Title
      final weekEnd = _selectedWeekStart.add(const Duration(days: 6));
      final weekNumber = _getWeekNumber(_selectedWeekStart);
      sheet
              .cell(excel_lib.CellIndex.indexByColumnRow(
                  columnIndex: 0, rowIndex: 0))
              .value =
          excel_lib.TextCellValue(
              'ĐĂNG KÝ CHỜ DUYỆT - LỊCH LÀM VIỆC THEO NHÂN VIÊN');
      sheet
              .cell(excel_lib.CellIndex.indexByColumnRow(
                  columnIndex: 0, rowIndex: 1))
              .value =
          excel_lib.TextCellValue(
              'Tuần $weekNumber: ${DateFormat('dd/MM/yyyy').format(_selectedWeekStart)} - ${DateFormat('dd/MM/yyyy').format(weekEnd)}${_selectedDepartment != null ? ' | Phòng ban: $_selectedDepartment' : ''}');

      // Header
      const hRow = 3;
      sheet
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 0, rowIndex: hRow))
          .value = excel_lib.TextCellValue('NHÂN VIÊN');
      for (int i = 0; i < 7; i++) {
        sheet
                .cell(excel_lib.CellIndex.indexByColumnRow(
                    columnIndex: i + 1, rowIndex: hRow))
                .value =
            excel_lib.TextCellValue(
                '${dayNames[i]} ${dateFormat.format(days[i])}');
      }
      sheet
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 8, rowIndex: hRow))
          .value = excel_lib.TextCellValue('TỔNG CA');

      int row = hRow + 1;
      for (final employee in emps) {
        sheet
                .cell(excel_lib.CellIndex.indexByColumnRow(
                    columnIndex: 0, rowIndex: row))
                .value =
            excel_lib.TextCellValue(
                '${employee.fullName} (${employee.employeeCode})');
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
              final shift = _shifts.firstWhere((s) => s.id == ws.shiftId,
                  orElse: () => Shift(
                      id: '',
                      name: 'Ca',
                      code: '',
                      startTime: '',
                      endTime: '',
                      isActive: true,
                      createdAt: DateTime.now()));
              items.add(shift.name);
              totalShifts++;
            }
          }
          for (final p in pendingRegs) {
            if (p['isDayOff'] == true) {
              items.add('Nghỉ (chờ)');
            } else {
              final shift = _shifts.firstWhere((s) => s.id == p['shiftId'],
                  orElse: () => Shift(
                      id: '',
                      name: 'Ca',
                      code: '',
                      startTime: '',
                      endTime: '',
                      isActive: true,
                      createdAt: DateTime.now()));
              items.add('${shift.name} (chờ)');
              totalShifts++;
            }
          }
          for (final r in submittedRegs.where((r) => schedules.isEmpty)) {
            if (r.isDayOff) {
              items.add('Nghỉ');
            } else {
              final shift = r.shiftId != null
                  ? _shifts.firstWhere((s) => s.id == r.shiftId,
                      orElse: () => Shift(
                          id: '',
                          name: 'Ca',
                          code: '',
                          startTime: '',
                          endTime: '',
                          isActive: true,
                          createdAt: DateTime.now()))
                  : null;
              final statusLabel =
                  r.status == ScheduleRegistrationStatus.approved
                      ? '✓'
                      : r.status == ScheduleRegistrationStatus.rejected
                          ? '✗'
                          : '⏳';
              items.add('${shift?.name ?? "Ca"} $statusLabel');
              if (r.status == ScheduleRegistrationStatus.approved &&
                  !r.isDayOff) {
                totalShifts++;
              }
            }
          }
          sheet
              .cell(excel_lib.CellIndex.indexByColumnRow(
                  columnIndex: d + 1, rowIndex: row))
              .value = excel_lib.TextCellValue(items.join(', '));
        }
        sheet
            .cell(excel_lib.CellIndex.indexByColumnRow(
                columnIndex: 8, rowIndex: row))
            .value = excel_lib.IntCellValue(totalShifts);
        row++;
      }

      // Legend
      row += 1;
      sheet
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 0, rowIndex: row))
          .value = excel_lib.TextCellValue('CHÚ THÍCH:');
      row++;
      for (final s in _shifts) {
        sheet
                .cell(excel_lib.CellIndex.indexByColumnRow(
                    columnIndex: 0, rowIndex: row))
                .value =
            excel_lib.TextCellValue(
                '${s.name}: ${_formatTime(s.startTime)} - ${_formatTime(s.endTime)}');
        row++;
      }
      sheet
              .cell(excel_lib.CellIndex.indexByColumnRow(
                  columnIndex: 0, rowIndex: row))
              .value =
          excel_lib.TextCellValue(
              '✓ Đã duyệt  |  ⏳ Chờ duyệt  |  ✗ Từ chối  |  (chờ) Chờ gửi');

      _downloadExcel(wb, 'DangKyChoDuyet');
    } catch (e) {
      appNotification.showError(title: 'Lỗi xuất Excel', message: '$e');
    }
  }

  void _exportApprovedExcel() {
    try {
      final days =
          List.generate(7, (i) => _selectedWeekStart.add(Duration(days: i)));
      final dayNames = [
        'Thứ 2',
        'Thứ 3',
        'Thứ 4',
        'Thứ 5',
        'Thứ 6',
        'Thứ 7',
        'CN'
      ];
      final dateFormat = DateFormat('dd/MM');
      final emps = _filteredEmployees;

      final wb = excel_lib.Excel.createExcel();
      final sheet = wb['DaDuyet'];
      wb.delete('Sheet1');

      // Title
      final weekEnd = _selectedWeekStart.add(const Duration(days: 6));
      final weekNumber = _getWeekNumber(_selectedWeekStart);
      sheet
          .cell(
              excel_lib.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
          .value = excel_lib.TextCellValue('LỊCH LÀM VIỆC ĐÃ DUYỆT');
      sheet
              .cell(excel_lib.CellIndex.indexByColumnRow(
                  columnIndex: 0, rowIndex: 1))
              .value =
          excel_lib.TextCellValue(
              'Tuần $weekNumber: ${DateFormat('dd/MM/yyyy').format(_selectedWeekStart)} - ${DateFormat('dd/MM/yyyy').format(weekEnd)}${_selectedDepartment != null ? ' | Phòng ban: $_selectedDepartment' : ''}');

      // Header
      const hRow = 3;
      sheet
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 0, rowIndex: hRow))
          .value = excel_lib.TextCellValue('NHÂN VIÊN');
      for (int i = 0; i < 7; i++) {
        sheet
                .cell(excel_lib.CellIndex.indexByColumnRow(
                    columnIndex: i + 1, rowIndex: hRow))
                .value =
            excel_lib.TextCellValue(
                '${dayNames[i]} ${dateFormat.format(days[i])}');
      }
      sheet
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 8, rowIndex: hRow))
          .value = excel_lib.TextCellValue('TỔNG CA');

      int row = hRow + 1;
      for (final employee in emps) {
        sheet
                .cell(excel_lib.CellIndex.indexByColumnRow(
                    columnIndex: 0, rowIndex: row))
                .value =
            excel_lib.TextCellValue(
                '${employee.fullName} (${employee.employeeCode})');
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
              final shift = _shifts.firstWhere((s) => s.id == ws.shiftId,
                  orElse: () => Shift(
                      id: '',
                      name: 'Ca',
                      code: '',
                      startTime: '',
                      endTime: '',
                      isActive: true,
                      createdAt: DateTime.now()));
              items.add(
                  '${shift.name} (${_formatTime(shift.startTime)}-${_formatTime(shift.endTime)})');
              totalApproved++;
            }
          }
          for (final reg in approvedRegs.where((r) => confirmedSchedules.every(
              (s) =>
                  s.shiftId != r.shiftId ||
                  s.employeeUserId != r.employeeUserId))) {
            if (reg.isDayOff) {
              items.add(reg.note ?? 'Nghỉ');
            } else {
              final shift = reg.shiftId != null
                  ? _shifts.firstWhere((s) => s.id == reg.shiftId,
                      orElse: () => Shift(
                          id: '',
                          name: 'Ca',
                          code: '',
                          startTime: '',
                          endTime: '',
                          isActive: true,
                          createdAt: DateTime.now()))
                  : null;
              items.add(
                  '${shift?.name ?? "Ca"} (${shift != null ? "${_formatTime(shift.startTime)}-${_formatTime(shift.endTime)}" : ""})');
              totalApproved++;
            }
          }
          sheet
              .cell(excel_lib.CellIndex.indexByColumnRow(
                  columnIndex: d + 1, rowIndex: row))
              .value = excel_lib.TextCellValue(items.join(', '));
        }
        sheet
            .cell(excel_lib.CellIndex.indexByColumnRow(
                columnIndex: 8, rowIndex: row))
            .value = excel_lib.IntCellValue(totalApproved);
        row++;
      }

      // Legend
      row += 1;
      sheet
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 0, rowIndex: row))
          .value = excel_lib.TextCellValue('CHÚ THÍCH:');
      row++;
      for (final s in _shifts) {
        sheet
                .cell(excel_lib.CellIndex.indexByColumnRow(
                    columnIndex: 0, rowIndex: row))
                .value =
            excel_lib.TextCellValue(
                '${s.name}: ${_formatTime(s.startTime)} - ${_formatTime(s.endTime)}');
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
      final fileName =
          '${fileNamePrefix}_${DateFormat('ddMMyyyy_HHmm').format(DateTime.now())}.xlsx';
      file_saver.saveFileBytes(bytes, fileName,
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
      appNotification.showSuccess(
          title: 'Xuất Excel', message: tr('Đã xuất file $fileName'));
    }
  }

  List<DataRow> _buildScheduleDesktopRows(
      List<Employee> employees, List<DateTime> days) {
    if (_branches.isEmpty) {
      return _buildScheduleEmployeeRows(employees, days);
    }
    final primary = Theme.of(context).primaryColor;
    final groups = _groupEmployeesByBranch(employees);
    final List<DataRow> rows = [];
    for (final entry in groups) {
      rows.add(DataRow(
        color: WidgetStateProperty.all(primary.withValues(alpha: 0.07)),
        cells: [
          DataCell(Row(children: [
            Icon(Icons.account_tree_outlined, size: 14, color: primary),
            const SizedBox(width: 6),
            Text(tr(entry.key),
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: primary, fontSize: 13)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                  color: primary, borderRadius: BorderRadius.circular(9)),
              child: Text(tr('${entry.value.length}'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
          ])),
          ...List.generate(8, (_) => const DataCell(SizedBox())),
        ],
      ));
      rows.addAll(_buildScheduleEmployeeRows(entry.value, days));
    }
    return rows;
  }

  List<DataRow> _buildScheduleEmployeeRows(
      List<Employee> employees, List<DateTime> days) {
    return employees.map((employee) {
      int totalShifts = 0;
      return DataRow(
        cells: [
          DataCell(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(tr(employee.fullName.toUpperCase()),
                    style: const TextStyle(
                        color: Color(0xFF18181B),
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                Text(tr(employee.phone ?? employee.employeeCode),
                    style: const TextStyle(
                        color: Color(0xFF71717A), fontSize: 11)),
              ],
            ),
          ),
          ...List.generate(7, (dayIndex) {
            final day = days[dayIndex];
            final effectiveId = _effectiveUserId(employee);
            final schedules = _getSchedulesForDay(effectiveId, day);
            final pendingRegs = _getPendingRegistrations(effectiveId, day);
            final submittedRegs = _getRegistrationsForDay(effectiveId, day);
            totalShifts += schedules.where((s) => !s.isDayOff).length;
            if (pendingRegs.isNotEmpty &&
                pendingRegs.first['isDayOff'] != true) {
              totalShifts += pendingRegs.length;
            }
            totalShifts += submittedRegs
                .where((r) =>
                    r.status == ScheduleRegistrationStatus.approved &&
                    !r.isDayOff &&
                    schedules.isEmpty)
                .length;
            return DataCell(
              _buildScheduleCell(
                  employee, day, schedules, pendingRegs, submittedRegs),
            );
          }),
          DataCell(Center(
            child: Text(tr('$totalShifts'),
                style: TextStyle(
                    color:
                        totalShifts > 0 ? HrmPageChrome.primaryNavy : Colors.grey,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          )),
        ],
      );
    }).toList();
  }

  Widget _buildMobileScheduleCards(List<Employee> pageEmps, List<DateTime> days,
      List<String> dayNames, DateFormat dateFormat) {
    if (pageEmps.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
            child: Text(tr('Chưa có nhân viên'),
                style: TextStyle(color: Colors.grey[400]))),
      );
    }
    if (_branches.isNotEmpty) {
      final groups = _groupEmployeesByBranch(pageEmps);
      return Column(
        children: [
          for (final entry in groups) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _buildBranchGroupHeader(entry.key, entry.value.length),
            ),
            _buildMobileScheduleCardsRaw(
                entry.value, days, dayNames, dateFormat),
          ],
        ],
      );
    }
    return _buildMobileScheduleCardsRaw(pageEmps, days, dayNames, dateFormat);
  }

  Widget _buildMobileScheduleCardsRaw(List<Employee> pageEmps,
      List<DateTime> days, List<String> dayNames, DateFormat dateFormat) {
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
          totalShifts += submittedRegs
              .where((r) =>
                  r.status == ScheduleRegistrationStatus.approved &&
                  !r.isDayOff &&
                  schedules.isEmpty)
              .length;
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
                final shift = _shifts.firstWhere((s) => s.id == reg['shiftId'],
                    orElse: () => Shift(
                        id: '',
                        name: 'Ca',
                        code: '',
                        startTime: '',
                        endTime: '',
                        isActive: true,
                        createdAt: DateTime.now()));
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
                final shift = s.shiftId != null
                    ? _shifts.firstWhere((sh) => sh.id == s.shiftId,
                        orElse: () => Shift(
                            id: '',
                            name: 'Ca',
                            code: '',
                            startTime: '',
                            endTime: '',
                            isActive: true,
                            createdAt: DateTime.now()))
                    : null;
                return shift?.name ?? 'Ca';
              }).toList();
              shiftLabel = names.join(', ');
              shiftColor = HrmPageChrome.primaryNavy;
              bgColor = HrmPageChrome.primaryNavy.withValues(alpha: 0.08);
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
              final shift = first.shiftId != null
                  ? _shifts.firstWhere((s) => s.id == first.shiftId,
                      orElse: () => Shift(
                          id: '',
                          name: 'Ca',
                          code: '',
                          startTime: '',
                          endTime: '',
                          isActive: true,
                          createdAt: DateTime.now()))
                  : null;
              shiftLabel = shift?.name ?? 'Đã duyệt';
              shiftColor = HrmPageChrome.primaryNavy;
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
                      child: Text(tr('${dayNames[di]} ${dateFormat.format(day)}'),
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF71717A))),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(tr(shiftLabel),
                            style: TextStyle(
                                fontSize: 12,
                                color: shiftColor,
                                fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis),
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
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr(employee.fullName.toUpperCase()),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: Color(0xFF18181B))),
                              Text(tr(employee.phone ?? employee.employeeCode),
                                  style: const TextStyle(
                                      fontSize: 11, color: Color(0xFF71717A))),
                            ]),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: totalShifts > 0
                              ? HrmPageChrome.primaryNavy.withValues(alpha: 0.1)
                              : Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(tr('$totalShifts ca'),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: totalShifts > 0
                                    ? HrmPageChrome.primaryNavy
                                    : Colors.grey)),
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

  // ignore: unused_element
  Widget _buildMobileShiftCentricCards(
      List<DateTime> days, List<String> dayNames, DateFormat dateFormat) {
    if (_shifts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
            child:
                Text(tr('Chưa có ca'), style: TextStyle(color: Colors.grey[400]))),
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
          totalEmployees += schedules.length +
              pendingLocal.length +
              submittedRegs
                  .where((r) =>
                      r.status != ScheduleRegistrationStatus.rejected &&
                      schedules
                          .every((s) => s.employeeUserId != r.employeeUserId))
                  .length;
          final empNames = <Widget>[];
          for (final ws in schedules) {
            final empName = _employees
                .firstWhere((e) => _effectiveUserId(e) == ws.employeeUserId,
                    orElse: () => Employee.empty())
                .fullName;
            empNames.add(Container(
              margin: const EdgeInsets.only(right: 4, bottom: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4)),
              child: Text(tr(empName),
                  style: const TextStyle(
                      fontSize: 10,
                      color: HrmPageChrome.primaryNavy,
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
            ));
          }
          for (final reg in pendingLocal) {
            final empName = _employees
                .firstWhere((e) => _effectiveUserId(e) == reg['employeeId'],
                    orElse: () => Employee.empty())
                .fullName;
            empNames.add(Container(
              margin: const EdgeInsets.only(right: 4, bottom: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: const Color(0xFFFFC107).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFFFFC107), width: 1)),
              child: Text(tr(empName),
                  style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF856404),
                      fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis),
            ));
          }
          dayWidgets.add(
            InkWell(
              onTap: Provider.of<PermissionProvider>(context, listen: false)
                      .canEdit('WorkSchedule')
                  ? () => _showAssignEmployeeToShiftDialog(shift, day)
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 56,
                      child: Text(tr('${dayNames[di]} ${dateFormat.format(day)}'),
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF71717A))),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: empNames.isEmpty
                          ? Text(tr('—'),
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[300]))
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
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr(shift.name),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: Color(0xFF0891B2))),
                              Text(
                                  tr('${_formatTime(shift.startTime)} - ${_formatTime(shift.endTime)}'),
                                  style: const TextStyle(
                                      fontSize: 11, color: Color(0xFF71717A))),
                            ]),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: totalEmployees > 0
                              ? const Color(0xFF0891B2).withValues(alpha: 0.1)
                              : Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(tr('$totalEmployees NV'),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: totalEmployees > 0
                                    ? const Color(0xFF0891B2)
                                    : Colors.grey)),
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

  List<DataRow> _buildApprovedDesktopRows(
      List<Employee> employees, List<DateTime> days) {
    if (_branches.isEmpty) {
      return _buildApprovedEmployeeRows(employees, days);
    }
    final primary = Theme.of(context).primaryColor;
    final groups = _groupEmployeesByBranch(employees);
    final List<DataRow> rows = [];
    for (final entry in groups) {
      rows.add(DataRow(
        color: WidgetStateProperty.all(primary.withValues(alpha: 0.07)),
        cells: [
          DataCell(Row(children: [
            Icon(Icons.account_tree_outlined, size: 14, color: primary),
            const SizedBox(width: 6),
            Text(tr(entry.key),
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: primary, fontSize: 13)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                  color: primary, borderRadius: BorderRadius.circular(9)),
              child: Text(tr('${entry.value.length}'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
          ])),
          ...List.generate(8, (_) => const DataCell(SizedBox())),
        ],
      ));
      rows.addAll(_buildApprovedEmployeeRows(entry.value, days));
    }
    return rows;
  }

  List<DataRow> _buildApprovedEmployeeRows(
      List<Employee> employees, List<DateTime> days) {
    return employees.map((employee) {
      int totalApproved = 0;
      return DataRow(
        cells: [
          DataCell(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(tr(employee.fullName.toUpperCase()),
                  style: const TextStyle(
                      color: Color(0xFF18181B),
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              Text(tr(employee.department ?? employee.employeeCode),
                  style:
                      const TextStyle(color: Color(0xFF71717A), fontSize: 11)),
            ],
          )),
          ...List.generate(7, (dayIndex) {
            final day = days[dayIndex];
            final effectiveId = _effectiveUserId(employee);
            final confirmedSchedules = _getSchedulesForDay(effectiveId, day);
            final approvedRegs = _getRegistrationsForDay(effectiveId, day)
                .where((r) => r.status == ScheduleRegistrationStatus.approved)
                .toList();
            final allApproved = <Widget>[];
            for (final ws in confirmedSchedules) {
              if (ws.isDayOff) {
                allApproved.add(_buildApprovedChip(
                    'Nghỉ', const Color(0xFF71717A), Icons.nightlight_round));
              } else {
                final shift = _shifts.firstWhere((s) => s.id == ws.shiftId,
                    orElse: () => Shift(
                        id: '',
                        name: 'Ca',
                        code: '',
                        startTime: '',
                        endTime: '',
                        isActive: true,
                        createdAt: DateTime.now()));
                final shiftTime = shift.startTime.isNotEmpty &&
                        shift.endTime.isNotEmpty
                    ? '${_formatTime(shift.startTime)}-${_formatTime(shift.endTime)}'
                    : '';
                allApproved.add(_buildApprovedChip(
                    shift.name, HrmPageChrome.primaryNavy, Icons.check_circle,
                    time: shiftTime));
                totalApproved++;
              }
            }
            for (final reg in approvedRegs.where((r) =>
                confirmedSchedules.every((s) =>
                    s.shiftId != r.shiftId ||
                    s.employeeUserId != r.employeeUserId))) {
              if (reg.isDayOff) {
                allApproved.add(_buildApprovedChip(reg.note ?? 'Nghỉ',
                    const Color(0xFF71717A), Icons.nightlight_round));
              } else {
                final shift = reg.shiftId != null
                    ? _shifts.firstWhere((s) => s.id == reg.shiftId,
                        orElse: () => Shift(
                            id: '',
                            name: 'Ca',
                            code: '',
                            startTime: '',
                            endTime: '',
                            isActive: true,
                            createdAt: DateTime.now()))
                    : null;
                final shiftTime = shift != null &&
                        shift.startTime.isNotEmpty &&
                        shift.endTime.isNotEmpty
                    ? '${_formatTime(shift.startTime)}-${_formatTime(shift.endTime)}'
                    : '';
                allApproved.add(_buildApprovedChip(shift?.name ?? 'Ca',
                    HrmPageChrome.primaryNavy, Icons.check_circle,
                    time: shiftTime));
                totalApproved++;
              }
            }
            return DataCell(Container(
              width: 120,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: allApproved.isEmpty
                  ? Center(
                      child: Text(tr('—'),
                          style:
                              TextStyle(color: Colors.grey[300], fontSize: 16)))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: allApproved),
            ));
          }),
          DataCell(Center(
              child: Text(tr('$totalApproved'),
                  style: TextStyle(
                      color: totalApproved > 0
                          ? HrmPageChrome.primaryNavy
                          : Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)))),
        ],
      );
    }).toList();
  }

  Widget _buildMobileApprovedCards(List<Employee> pageEmps, List<DateTime> days,
      List<String> dayNames, DateFormat dateFormat) {
    if (pageEmps.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
            child: Text(tr('Chưa có nhân viên'),
                style: TextStyle(color: Colors.grey[400]))),
      );
    }
    if (_branches.isNotEmpty) {
      final groups = _groupEmployeesByBranch(pageEmps);
      return Column(
        children: [
          for (final entry in groups) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _buildBranchGroupHeader(entry.key, entry.value.length),
            ),
            _buildMobileApprovedCardsRaw(
                entry.value, days, dayNames, dateFormat),
          ],
        ],
      );
    }
    return _buildMobileApprovedCardsRaw(pageEmps, days, dayNames, dateFormat);
  }

  Widget _buildMobileApprovedCardsRaw(List<Employee> pageEmps,
      List<DateTime> days, List<String> dayNames, DateFormat dateFormat) {
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
              final shift = _shifts.firstWhere((s) => s.id == ws.shiftId,
                  orElse: () => Shift(
                      id: '',
                      name: 'Ca',
                      code: '',
                      startTime: '',
                      endTime: '',
                      isActive: true,
                      createdAt: DateTime.now()));
              items.add(shift.name);
              totalApproved++;
            }
          }
          for (final reg in approvedRegs.where((r) => confirmedSchedules.every(
              (s) =>
                  s.shiftId != r.shiftId ||
                  s.employeeUserId != r.employeeUserId))) {
            if (reg.isDayOff) {
              items.add(reg.note ?? 'Nghỉ');
            } else {
              final shift = reg.shiftId != null
                  ? _shifts.firstWhere((s) => s.id == reg.shiftId,
                      orElse: () => Shift(
                          id: '',
                          name: 'Ca',
                          code: '',
                          startTime: '',
                          endTime: '',
                          isActive: true,
                          createdAt: DateTime.now()))
                  : null;
              items.add(shift?.name ?? 'Ca');
              totalApproved++;
            }
          }
          if (items.isNotEmpty) {
            shiftLabel = items.join(', ');
            final hasLeave =
                items.any((i) => i == 'Nghỉ' || i.contains('Nghỉ'));
            if (hasLeave && items.length == 1) {
              shiftColor = const Color(0xFF059669);
              bgColor = const Color(0xFFD1FAE5);
            } else {
              shiftColor = HrmPageChrome.primaryNavy;
              bgColor = HrmPageChrome.primaryNavy.withValues(alpha: 0.08);
            }
          }
          dayWidgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 56,
                    child: Text(tr('${dayNames[di]} ${dateFormat.format(day)}'),
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF71717A))),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(tr(shiftLabel),
                          style: TextStyle(
                              fontSize: 12,
                              color: shiftColor,
                              fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
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
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2))
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr(employee.fullName.toUpperCase()),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: Color(0xFF18181B))),
                              Text(tr(employee.department ?? employee.employeeCode),
                                  style: const TextStyle(
                                      fontSize: 11, color: Color(0xFF71717A))),
                            ]),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: totalApproved > 0
                              ? HrmPageChrome.primaryNavy.withValues(alpha: 0.1)
                              : Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(tr('$totalApproved ca'),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: totalApproved > 0
                                    ? HrmPageChrome.primaryNavy
                                    : Colors.grey)),
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
      builder: (context) => ScrollableAlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('Xác nhận xóa'),
            style: TextStyle(
                color: Color(0xFF18181B), fontWeight: FontWeight.bold)),
        content: Text(tr('Bạn có chắc chắn muốn xóa đăng ký này?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                Text(tr('Hủy'), style: TextStyle(color: Color(0xFF71717A))),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444)),
            child: Text(tr('Xóa')),
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
            message: tr('Đã xóa đăng ký thành công'),
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
        builder: (ctx, setDialogState) => ScrollableAlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(Icons.notifications_active, color: Color(0xFFD97706)),
            SizedBox(width: 8),
            Expanded(
                child: Text(tr('Nhắc nhở đăng ký lịch'),
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          ]),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('${tr('Gửi thông báo đến nhân viên chưa đăng ký lịch làm việc cho tuần ')}${DateFormat('dd/MM').format(fromDate)} - ${DateFormat('dd/MM/yyyy').format(toDate)}.'),
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF71717A))),
                const SizedBox(height: 16),
                Text(tr('Phòng ban:'),
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 4),
                DropdownButtonFormField<String?>(
                  initialValue: selectedDept,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                        value: null, child: Text(tr('Tất cả phòng ban'))),
                    ..._departments.map((d) => DropdownMenuItem<String?>(
                          value: d['name']?.toString(),
                          child: Text(tr(d['name']?.toString() ?? '')),
                        )),
                  ],
                  onChanged: (v) => setDialogState(() => selectedDept = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
            FilledButton.icon(
              onPressed: isSending
                  ? null
                  : () async {
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
                        appNotification.showSuccess(
                            title: 'Thành công',
                            message: tr('Đã gửi nhắc nhở đến $count nhân viên'));
                      } else {
                        appNotification.showError(
                            title: 'Lỗi',
                            message:
                                result['message'] ?? 'Không thể gửi nhắc nhở');
                      }
                    },
              icon: isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send, size: 16),
              label: Text(tr('Gửi nhắc nhở')),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════
  // Request Shift Coverage Dialog
  // ══════════════════════════════════════════════
  void _showRequestCoverageDialog(
      {Shift? preselectedShift, DateTime? preselectedDate}) {
    Shift? selectedShift =
        preselectedShift ?? (_shifts.isNotEmpty ? _shifts.first : null);
    DateTime selectedDate = preselectedDate ?? DateTime.now();
    String? selectedDept = _selectedDepartment;
    final messageController = TextEditingController();
    bool isSending = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => ScrollableAlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(children: [
            Icon(Icons.group_add, color: Color(0xFF059669)),
            SizedBox(width: 8),
            Expanded(
                child: Text(tr('Yêu cầu bổ sung ca'),
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          ]),
          content: SizedBox(
            width: 400,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Gửi thông báo yêu cầu nhân viên đăng ký bổ sung cho ca làm cụ thể.'),
                      style: TextStyle(fontSize: 13, color: Color(0xFF71717A))),
                  const SizedBox(height: 16),
                  Text(tr('Ca làm việc:'),
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<Shift>(
                    initialValue: selectedShift,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    items: _shifts
                        .map((s) => DropdownMenuItem<Shift>(
                              value: s,
                              child: Text(
                                  tr('${s.name} (${_formatTime(s.startTime)}-${_formatTime(s.endTime)})'),
                                  style: const TextStyle(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (v) => setDialogState(() => selectedShift = v),
                  ),
                  const SizedBox(height: 12),
                  Text(tr('Ngày:'),
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: selectedDate,
                        firstDate:
                            DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE4E4E7)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(children: [
                        const Icon(Icons.calendar_today,
                            size: 16, color: Color(0xFF71717A)),
                        const SizedBox(width: 8),
                        Text(
                            tr(DateFormat('EEEE dd/MM/yyyy', 'vi')
                                .format(selectedDate)),
                            style: const TextStyle(fontSize: 13)),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(tr('Phòng ban:'),
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String?>(
                    initialValue: selectedDept,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                          value: null, child: Text(tr('Tất cả phòng ban'))),
                      ..._departments.map((d) => DropdownMenuItem<String?>(
                            value: d['name']?.toString(),
                            child: Text(tr(d['name']?.toString() ?? '')),
                          )),
                    ],
                    onChanged: (v) => setDialogState(() => selectedDept = v),
                  ),
                  const SizedBox(height: 12),
                  Text(tr('Tin nhắn (tùy chọn):'),
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: messageController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: tr('Để trống sẽ dùng tin nhắn mặc định'),
                      hintStyle: const TextStyle(
                          fontSize: 12, color: Color(0xFFA1A1AA)),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
            FilledButton.icon(
              onPressed: (isSending || selectedShift == null)
                  ? null
                  : () async {
                      setDialogState(() => isSending = true);
                      final result = await _apiService.requestShiftCoverage({
                        'shiftTemplateId': selectedShift!.id,
                        'date': selectedDate.toIso8601String(),
                        if (selectedDept != null) 'department': selectedDept,
                        if (messageController.text.isNotEmpty)
                          'message': messageController.text,
                      });
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (result['isSuccess'] == true) {
                        final count = result['data'] ?? 0;
                        appNotification.showSuccess(
                            title: 'Thành công',
                            message: tr('Đã gửi yêu cầu đến $count nhân viên'));
                      } else {
                        appNotification.showError(
                            title: 'Lỗi',
                            message:
                                result['message'] ?? 'Không thể gửi yêu cầu');
                      }
                    },
              icon: isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send, size: 16),
              label: Text(tr('Gửi yêu cầu')),
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  void _showStaffingQuotaDialog() {
    SettingsHubScreen.pendingSubIndex.value = 14;
    NavigationNotifier.goTo(NavigationNotifier.settingsHub);
  }
}
