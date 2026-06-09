import 'dart:convert';
import 'dart:math' as math;
import '../../utils/file_saver.dart' as file_saver;
import '../../utils/web_canvas.dart' as web_canvas;

import 'package:excel/excel.dart' as excel_lib;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/attendance.dart';
import '../../models/device.dart';
import '../../models/employee.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../utils/responsive_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/report_salary_setup_hint.dart';
import '../../utils/excel_report_builder.dart';
import '../../widgets/synced_scroll_list_view.dart'
    show HorizontallySyncedClip;
import '../../utils/shift_records_calculator.dart';
import '../../utils/allowance_calculator.dart';
import '../../utils/mobile_attendance_vertical_layout.dart';
import '../main_layout.dart' show NavigationNotifier;

// ═══════════════════════════════════════════════════════════════
//  PayrollColumn – định nghĩa 1 cột bảng lương
// ═══════════════════════════════════════════════════════════════
class PayrollColumn {
  final String key;
  final String label;
  final bool defaultVisible;
  bool visible;

  PayrollColumn({
    required this.key,
    required this.label,
    this.defaultVisible = true,
    bool? visible,
  }) : visible = visible ?? defaultVisible;
}

// ═══════════════════════════════════════════════════════════════
//  PayrollSummaryTab
// ═══════════════════════════════════════════════════════════════
class PayrollSummaryTab extends StatefulWidget {
  final List<Attendance> attendances;
  final List<Device> devices;
  final DateTime fromDate;
  final DateTime toDate;
  final String? branchId;
  final List<Widget>? mobileLeadingSections;

  const PayrollSummaryTab({
    super.key,
    required this.attendances,
    required this.devices,
    required this.fromDate,
    required this.toDate,
    this.branchId,
    this.mobileLeadingSections,
  });

  @override
  State<PayrollSummaryTab> createState() => PayrollSummaryTabState();
}

class PayrollSummaryTabState extends State<PayrollSummaryTab> {
  final ApiService _apiService = ApiService();
  final _currencyFmt = NumberFormat('#,###', 'vi_VN');
  final GlobalKey _tableKey = GlobalKey();

  // ═══ Data ═══
  List<Employee> _employees = [];
  List<Map<String, dynamic>> _employeeSalaryProfiles = [];
  Map<String, dynamic> _insuranceSettings = {};
  // ignore: unused_field
  Map<String, dynamic> _salarySettings = {};
  Map<String, dynamic> _penaltySettings = {};
  Map<String, dynamic> _taxSettings = {};
  List<Map<String, dynamic>> _allowanceSettings = [];
  List<Map<String, dynamic>> _transactions = [];
  List<Map<String, dynamic>> _advanceRequests = [];
  // ignore: unused_field
  List<Map<String, dynamic>> _shifts = [];
  List<Map<String, dynamic>> _holidays = [];
  List<Map<String, dynamic>> _shiftSalaryLevels = [];
  List<Map<String, dynamic>> _employeeTaxDeductions = [];
  List<Map<String, dynamic>> _kpiEmployeeTargets = [];

  Map<String, dynamic> _commissionSettings = {};
  List<Map<String, dynamic>> _productionSummaries = [];

  // Attendance loaded for selected period (from parent screen)
  List<Attendance> _periodAttendances = [];

  int _dayEndHour = 0;
  int _dayEndMinute = 0;
  List<DailyShiftRecord>? _cachedShiftRecords;
  Map<String, List<DailyShiftRecord>>? _shiftRecordsByEmpKey;

  // ═══ State ═══
  bool _isLoading = true;
  bool _isFinalizing = false;
  /// NV đang hoạt động nhưng chưa có bảng lương (bị loại khỏi tổng hợp).
  int _notConfiguredSalaryCount = 0;
  bool _showMobileSummary = false;
  bool _payrollFiltersExpanded = false;
  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String _selectedPeriod = 'thisMonth';
  String _sortColumn = 'code';
  bool _sortAscending = true;
  Set<String> _selectedEmployeeIds = {}; // empty = all employees
  String? _selectedDepartment; // null = all departments

  // ═══ Pagination ═══
  int _currentPage = 1;
  int _rowsPerPage = 20;

  // ═══ Columns ═══
  List<PayrollColumn> _columns = [];
  bool _columnsInitialized = false;

  AppLocalizations get _l10n => AppLocalizations.of(context);

  // Scroll controllers for synced scrolling
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _desktopTableHScrollBody = ScrollController();
  final ScrollController _desktopTableVScroll = ScrollController();

  static const _employeeSignColumnKey = 'employeeSign';

  /// Ký cuối bảng (không gồm NV — NV ký ở cột [employeeSign] từng dòng).
  static const _payrollFooterSignatureLabels = [
    'Người lập',
    'Kế toán',
    'Thủ quỹ',
    'Giám đốc',
  ];

  // Cache
  List<Map<String, dynamic>>? _cachedPayrollData;

  // ──────── Lifecycle ────────
  @override
  void initState() {
    super.initState();
    _fromDate = widget.fromDate;
    _toDate = widget.toDate;
    _loadPayrollData();
  }

  @override
  void didUpdateWidget(PayrollSummaryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.branchId != widget.branchId ||
        oldWidget.attendances != widget.attendances) {
      _cachedPayrollData = null;
      _cachedShiftRecords = null;
      _shiftRecordsByEmpKey = null;
      if (oldWidget.branchId != widget.branchId) {
        _selectedDepartment = null;
        _pruneEmployeeSelectionToPool();
        _currentPage = 1;
      }
      if (mounted) setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_columnsInitialized) {
      _columnsInitialized = true;
      _initColumns();
    }
  }

  List<PayrollColumn> _defaultPayrollColumns() {
    return [
      PayrollColumn(key: 'stt', label: 'STT'),
      PayrollColumn(key: 'name', label: _l10n.employeeName),
      PayrollColumn(key: 'code', label: _l10n.employeeCode),
      PayrollColumn(
        key: 'department',
        label: _l10n.department,
        defaultVisible: false,
      ),
      PayrollColumn(key: 'salaryType', label: _l10n.salaryType),
      PayrollColumn(key: 'standardDays', label: _l10n.standardWorkDays),
      PayrollColumn(key: 'workDays', label: _l10n.totalWorkDays),
      PayrollColumn(key: 'totalHours', label: _l10n.totalHours),
      PayrollColumn(
        key: 'otTotalHours',
        label: _l10n.overtime,
        defaultVisible: false,
      ),
      PayrollColumn(key: 'baseSalary', label: _l10n.baseSalary),
      PayrollColumn(key: 'workSalary', label: 'Lương theo công'),
      PayrollColumn(key: 'completionSalary', label: _l10n.completionSalary),
      PayrollColumn(
        key: 'dailySalary',
        label: _l10n.dailySalary,
        defaultVisible: false,
      ),
      PayrollColumn(
        key: 'shiftSalary',
        label: _l10n.shiftSalary,
        defaultVisible: false,
      ),
      PayrollColumn(
        key: 'hourlySalary',
        label: _l10n.hourSalary,
        defaultVisible: false,
      ),
      PayrollColumn(key: 'otSalary', label: _l10n.overtimeSalary),
      PayrollColumn(key: 'allowanceFixed', label: 'PC cố định'),
      PayrollColumn(key: 'allowanceDaily', label: 'PC theo ngày'),
      PayrollColumn(key: 'totalAllowance', label: 'Tổng PC kỳ'),
      PayrollColumn(key: 'bonus', label: _l10n.bonusAmount),
      PayrollColumn(
        key: 'penalty',
        label: _l10n.penaltyAmount,
        defaultVisible: false,
      ),
      PayrollColumn(
        key: 'kpiSalary',
        label: _l10n.kpiSalary,
        defaultVisible: false,
      ),
      PayrollColumn(
        key: 'productionAmount',
        label: 'Sản lượng',
        defaultVisible: false,
      ),
      PayrollColumn(key: 'bhxh', label: 'BHXH', defaultVisible: false),
      PayrollColumn(key: 'pit', label: 'TNCN', defaultVisible: false),
      PayrollColumn(key: 'totalSalary', label: _l10n.totalSalary),
      PayrollColumn(
        key: 'advance',
        label: _l10n.advancePaid,
        defaultVisible: false,
      ),
      PayrollColumn(key: 'netSalary', label: _l10n.netSalary),
      PayrollColumn(
        key: _employeeSignColumnKey,
        label: 'Ký tên',
        defaultVisible: false,
      ),
    ];
  }

  void _initColumns() {
    _columns = _defaultPayrollColumns();
    _loadColumnPreferences();
  }

  List<PayrollColumn> _visiblePayrollColumns() {
    final visible = _columns.where((c) => c.visible).toList();
    if (!visible.any((c) => c.key == _employeeSignColumnKey)) {
      final signCol = _columns.firstWhere(
        (c) => c.key == _employeeSignColumnKey,
        orElse: () => PayrollColumn(
          key: _employeeSignColumnKey,
          label: 'Ký tên',
        ),
      );
      visible.add(signCol);
    }
    return visible;
  }

  Future<void> _loadColumnPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('payroll_columns_v10');
      if (saved != null) {
        final List<dynamic> list = jsonDecode(saved);
        // Rebuild _columns in saved order, preserving visibility
        final orderedCols = <PayrollColumn>[];
        final remaining = List<PayrollColumn>.from(_columns);
        for (final item in list) {
          final key = item['key'] as String;
          final visible = item['visible'] as bool;
          final idx = remaining.indexWhere((c) => c.key == key);
          if (idx >= 0) {
            remaining[idx].visible = visible;
            orderedCols.add(remaining.removeAt(idx));
          }
        }
        // Append any new columns not in saved preferences
        orderedCols.addAll(remaining);
        _columns = orderedCols;
      }
    } catch (_) {}
  }

  Future<void> _saveColumnPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list =
          _columns.map((c) => {'key': c.key, 'visible': c.visible}).toList();
      await prefs.setString('payroll_columns_v10', jsonEncode(list));
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    _desktopTableHScrollBody.dispose();
    _desktopTableVScroll.dispose();
    super.dispose();
  }

  // ──────── Data loading ────────
  Future<T> _loadWithTimeout<T>(Future<T> future, T fallback,
      {Duration timeout = const Duration(seconds: 15)}) async {
    try {
      return await future.timeout(timeout);
    } catch (e) {
      debugPrint('Payroll load timeout/error: $e');
      return fallback;
    }
  }

  static String _normEmpId(String id) => id.toLowerCase().trim();

  void _putSalaryProfile(
    Map<String, dynamic> profileMap,
    String employeeId,
    Map<String, dynamic> profile,
  ) {
    final key = _normEmpId(employeeId);
    if (key.isEmpty) return;
    profileMap[key] = profile;
    final fromProfile = profile['employeeId']?.toString() ?? '';
    if (fromProfile.isNotEmpty) {
      profileMap[_normEmpId(fromProfile)] = profile;
    }
  }

  /// Tải map employeeId → hồ sơ lương (batch cho quản lý; NV dùng /api/benefits/me).
  Future<Map<String, dynamic>> _loadSalaryProfileMap(
    List<Employee> employees, {
    bool preferSelfServiceApi = false,
  }) async {
    final profileMap = <String, dynamic>{};

    if (preferSelfServiceApi) {
      final meProfile = await _loadWithTimeout(
        _apiService.getMyEmployeeSalaryProfile(),
        null,
      );
      if (meProfile != null && employees.isNotEmpty) {
        _putSalaryProfile(profileMap, employees.first.id, meProfile);
      }
    }

    if (profileMap.isEmpty) {
      final allProfiles = await _loadWithTimeout(
        _apiService.getEmployeeSalaryProfiles(),
        <dynamic>[],
      );
      for (final p in allProfiles) {
        if (p is Map<String, dynamic>) {
          final eid = p['employeeId']?.toString() ?? '';
          if (eid.isNotEmpty) _putSalaryProfile(profileMap, eid, p);
        }
      }
    }

    for (final emp in employees) {
      final key = _normEmpId(emp.id);
      if (key.isNotEmpty && profileMap.containsKey(key)) continue;
      final profile = await _apiService.getEmployeeSalaryProfile(emp.id);
      if (profile != null) {
        _putSalaryProfile(profileMap, emp.id, profile);
      }
    }

    return profileMap;
  }

  bool _isEmployeeRole(BuildContext context) {
    final role =
        Provider.of<AuthProvider>(context, listen: false).userRole.trim();
    return role.toLowerCase() == 'employee';
  }

  Future<void> _loadPeriodAttendances() async {
    final fromDay = DateTime(_fromDate.year, _fromDate.month, _fromDate.day);
    final toEnd = DateTime(
      _toDate.year,
      _toDate.month,
      _toDate.day,
      23,
      59,
      59,
    );

    // Chỉ dùng log màn cha đã tải — không gọi lại /api/attendances/devices (tránh quay hàng trăm trang).
    _periodAttendances = widget.attendances.where((a) {
      final t = a.attendanceTime;
      return !t.isBefore(fromDay) && !t.isAfter(toEnd);
    }).toList();
  }

  Future<void> _loadPayrollData() async {
    setState(() => _isLoading = true);
    _cachedPayrollData = null;
    _cachedShiftRecords = null;
    _shiftRecordsByEmpKey = null;
    try {
      try {
        final dayEndResult =
            await _loadWithTimeout(_apiService.getAppSetting('day_end_time'), {});
        if (dayEndResult['isSuccess'] == true && dayEndResult['data'] is Map) {
          final value = (dayEndResult['data'] as Map)['value']?.toString() ?? '';
          final parts = value.split(':');
          if (parts.length >= 2) {
            _dayEndHour = int.tryParse(parts[0]) ?? 0;
            _dayEndMinute = int.tryParse(parts[1]) ?? 0;
          }
        }
      } catch (_) {}
      // Load employees (paged API — request large page)
      final empList = await _loadWithTimeout(
        _apiService.getEmployees(pageSize: 1000),
        <dynamic>[],
      );
      _employees = empList
          .map((e) => Employee.fromJson(e as Map<String, dynamic>))
          .toList();

      // Hồ sơ lương: batch API chỉ manager+; NV dùng /api/benefits/me.
      _employeeSalaryProfiles = [];
      final activeEmployees =
          _employees.where((e) => e.isActive).toList(growable: false);
      final profileMap = await _loadSalaryProfileMap(
        activeEmployees,
        preferSelfServiceApi: mounted && _isEmployeeRole(context),
      );
      // Loại bỏ NV chưa thiết lập bảng lương khỏi tổng hợp lương.
      _notConfiguredSalaryCount = activeEmployees
          .where((e) => !profileMap.containsKey(_normEmpId(e.id)))
          .length;
      _employees = activeEmployees
          .where((e) => profileMap.containsKey(_normEmpId(e.id)))
          .toList();
      for (final emp in _employees) {
        _employeeSalaryProfiles.add({
          'employeeId': emp.id,
          'employeeCode': emp.employeeCode,
          'profile': profileMap[_normEmpId(emp.id)],
        });
      }

      // Load settings in parallel (each call capped — tránh quay mãi)
      final results = await Future.wait([
        _loadWithTimeout(_apiService.getInsuranceSettings(), {}),
        _loadWithTimeout(_apiService.getSalarySettings(), {}),
        _loadWithTimeout(_apiService.getPenaltySettings(), {}),
        _loadWithTimeout(
          _apiService.getTransactions(fromDate: _fromDate, toDate: _toDate),
          <String, dynamic>{},
        ),
        _loadWithTimeout(
          _apiService.getAdvanceRequests(fromDate: _fromDate, toDate: _toDate),
          <String, dynamic>{},
        ),
        _loadWithTimeout(_apiService.getShifts(), <dynamic>[]),
        _loadWithTimeout(_apiService.getAllowanceSettings(), <dynamic>[]),
        _loadWithTimeout(
            _apiService.getHolidaySettings(_fromDate.year), <dynamic>[]),
      ]);

      _insuranceSettings = results[0] is Map<String, dynamic>
          ? results[0] as Map<String, dynamic>
          : {};
      _salarySettings = results[1] is Map<String, dynamic>
          ? results[1] as Map<String, dynamic>
          : {};
      // getPenaltySettings returns raw response with isSuccess/data
      final penaltyResult = results[2] as Map<String, dynamic>;
      _penaltySettings = penaltyResult['data'] is Map<String, dynamic>
          ? penaltyResult['data'] as Map<String, dynamic>
          : penaltyResult;

      final txnResult = results[3] as Map<String, dynamic>;
      _transactions = _extractList(txnResult['items'] ?? txnResult['data']);

      final advResult = results[4] as Map<String, dynamic>;
      _advanceRequests = _extractList(advResult['items'] ?? advResult['data']);

      _shifts = _extractList(results[5]);
      _allowanceSettings = _extractList(results[6]);
      _holidays = _extractList(results[7]);

      // Optional settings (timeout — tránh quay mãi khi API chậm/treo)
      final taxRes = await _loadWithTimeout(
        _apiService.getTaxSettings(),
        <String, dynamic>{},
      );
      _taxSettings =
          taxRes is Map<String, dynamic> ? taxRes : <String, dynamic>{};
      final levels = await _loadWithTimeout(
        _apiService.getShiftSalaryLevels(),
        <String, dynamic>{},
      );
      if (levels['data'] is List) {
        _shiftSalaryLevels = (levels['data'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      } else {
        _shiftSalaryLevels = [];
      }
      final deductions = await _loadWithTimeout(
        _apiService.getEmployeeTaxDeductions(),
        <dynamic>[],
      );
      _employeeTaxDeductions = deductions
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      _commissionSettings = await _loadWithTimeout(
        _apiService.getCommissionSettings(),
        <String, dynamic>{},
      );
      final periodsRes = await _loadWithTimeout(
        _apiService.getKpiPeriods(),
        <String, dynamic>{'isSuccess': false},
      );
      if (periodsRes['isSuccess'] == true) {
        final periods =
            List<Map<String, dynamic>>.from(periodsRes['data'] ?? []);
        String? matchPeriodId;
        for (final p in periods) {
          final pStart = DateTime.tryParse(p['periodStart']?.toString() ?? '');
          final pEnd = DateTime.tryParse(p['periodEnd']?.toString() ?? '');
          if (pStart != null &&
              pEnd != null &&
              !_fromDate.isAfter(pEnd) &&
              !_toDate.isBefore(pStart)) {
            matchPeriodId = p['id']?.toString();
            break;
          }
        }
        if (matchPeriodId != null) {
          final targetsRes = await _loadWithTimeout(
            _apiService.getKpiEmployeeTargets(periodId: matchPeriodId),
            <String, dynamic>{'isSuccess': false},
          );
          if (targetsRes['isSuccess'] == true) {
            _kpiEmployeeTargets =
                List<Map<String, dynamic>>.from(targetsRes['data'] ?? []);
          }
        }
      } else {
        _kpiEmployeeTargets = [];
      }

      final prodRes = await _loadWithTimeout(
        _apiService.getProductionSummary(
          fromDate: _fromDate,
          toDate: _toDate,
        ),
        <String, dynamic>{'isSuccess': false},
      );
      if (prodRes['isSuccess'] == true) {
        _productionSummaries =
            List<Map<String, dynamic>>.from(prodRes['data'] ?? []);
      } else {
        _productionSummaries = [];
      }

      await _loadPeriodAttendances();
    } catch (e) {
      debugPrint('Error loading payroll data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ──────── Helper: safely extract list from dynamic response ────────
  List<Map<String, dynamic>> _extractList(dynamic data) {
    if (data is List) {
      return data
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (data is Map) {
      // Might be {items: [...], totalCount: ...}
      final items = data['items'] ?? data['data'];
      if (items is List) {
        return items
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }
    return [];
  }

  List<Map<String, dynamic>> _salaryProfilesForShiftCalc() {
    final out = <Map<String, dynamic>>[];
    for (final entry in _employeeSalaryProfiles) {
      final raw = entry['profile'];
      if (raw is! Map) continue;
      final profile = Map<String, dynamic>.from(raw);
      final benefit = profile['benefit'];
      if (benefit is Map) {
        final b = Map<String, dynamic>.from(benefit);
        profile['shiftsPerDay'] = b['shiftsPerDay'];
        profile['weeklyOffDays'] = b['weeklyOffDays'];
        profile['holidayMultiplier'] = b['holidayMultiplier'];
        profile['holidayOvertimeType'] = b['holidayOvertimeType'];
        profile['description'] = b['description'] ?? profile['description'];
      }
      final empId = entry['employeeId']?.toString() ?? '';
      final empCode = entry['employeeCode']?.toString() ?? '';
      profile['employees'] = [
        {'id': empId, 'employeeCode': empCode},
      ];
      out.add(profile);
    }
    return out;
  }

  void _ensureShiftRecordsCache() {
    if (_cachedShiftRecords != null) return;
    final attendances =
        _periodAttendances.isNotEmpty ? _periodAttendances : widget.attendances;
    _cachedShiftRecords = computeDailyShiftRecords(
      attendances: attendances,
      fromDate: _fromDate,
      toDate: _toDate,
      shiftTemplates: _shifts,
      shiftSalaryLevels: _shiftSalaryLevels,
      salaryProfiles: _salaryProfilesForShiftCalc(),
      holidays: _holidays,
      dayEndHour: _dayEndHour,
      dayEndMinute: _dayEndMinute,
    );
    _shiftRecordsByEmpKey = {};
    for (final r in _cachedShiftRecords!) {
      for (final key in {r.employeeCode, r.employeeId}) {
        if (key.isEmpty || key == '-') continue;
        _shiftRecordsByEmpKey!.putIfAbsent(key, () => []).add(r);
      }
    }
  }

  List<DailyShiftRecord> _shiftRecordsForEmployee(String empCode) {
    _ensureShiftRecordsCache();
    final keys = <String>{empCode};
    final emp = _findEmployee(empCode);
    if (emp != null) {
      keys.add(emp.id);
      keys.add(emp.employeeCode);
    }
    final list = <DailyShiftRecord>[];
    final seenDates = <String>{};
    for (final k in keys) {
      for (final r in _shiftRecordsByEmpKey?[k] ?? const []) {
        final dk = '${r.employeeCode}|${DateFormat('yyyy-MM-dd').format(r.date)}';
        if (seenDates.add(dk)) list.add(r);
      }
    }
    return list;
  }

  // ──────── Helper: check if a date is holiday ────────
  bool _isHoliday(DateTime date) {
    for (final h in _holidays) {
      final hDate =
          h['date'] != null ? DateTime.tryParse(h['date'].toString()) : null;
      if (hDate == null) continue;
      final isRecurring = h['isRecurring'] == true;
      final dateMatch = isRecurring
          ? hDate.month == date.month && hDate.day == date.day
          : hDate.year == date.year &&
              hDate.month == date.month &&
              hDate.day == date.day;
      if (dateMatch) return true;
    }
    return false;
  }

  bool _isWeekend(DateTime date) {
    return date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
  }

  /// Calculate standard work days based on the full month (not date range)
  double _calcStandardWorkDays(String paidLeaveType, String paidDayOff) {
    // Use the month of _fromDate to determine the full month
    final year = _fromDate.year;
    final month = _fromDate.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final monthStart = DateTime(year, month, 1);
    final monthEnd = DateTime(year, month, daysInMonth);
    double offDays = 0;

    switch (paidLeaveType) {
      case 'sunday':
        for (var d = monthStart;
            !d.isAfter(monthEnd);
            d = d.add(const Duration(days: 1))) {
          if (d.weekday == DateTime.sunday) offDays++;
        }
        break;
      case 'saturday':
        for (var d = monthStart;
            !d.isAfter(monthEnd);
            d = d.add(const Duration(days: 1))) {
          if (d.weekday == DateTime.saturday) offDays++;
        }
        break;
      case 'sat-sun':
        for (var d = monthStart;
            !d.isAfter(monthEnd);
            d = d.add(const Duration(days: 1))) {
          if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) {
            offDays++;
          }
        }
        break;
      case 'sat-afternoon-sun':
        for (var d = monthStart;
            !d.isAfter(monthEnd);
            d = d.add(const Duration(days: 1))) {
          if (d.weekday == DateTime.sunday) {
            offDays++;
          } else if (d.weekday == DateTime.saturday) {
            offDays += 0.5;
          }
        }
        break;
      case 'off-1':
        offDays = 1;
        break;
      case 'off-2':
        offDays = 2;
        break;
      case 'off-3':
        offDays = 3;
        break;
      case 'off-4':
        offDays = 4;
        break;
      default:
        for (var d = monthStart;
            !d.isAfter(monthEnd);
            d = d.add(const Duration(days: 1))) {
          if ((paidDayOff.contains('Sunday') && d.weekday == DateTime.sunday) ||
              (paidDayOff.contains('Saturday') &&
                  d.weekday == DateTime.saturday)) {
            offDays++;
          }
        }
    }

    return daysInMonth - offDays;
  }

  // ──────── Resolution helpers ────────
  String _resolveAttEmployeeCode(Attendance att) {
    if (att.employeeId != null && att.employeeId!.isNotEmpty) {
      final emp = _employees.where((e) => e.id == att.employeeId).firstOrNull;
      if (emp != null) return emp.employeeCode;
      final emp2 =
          _employees.where((e) => e.employeeCode == att.employeeId).firstOrNull;
      if (emp2 != null) return emp2.employeeCode;
      return att.employeeId!;
    }
    if (att.pin != null && att.pin!.isNotEmpty) {
      final emp = _employees
          .where((e) => e.pin == att.pin || e.employeeCode == att.pin)
          .firstOrNull;
      if (emp != null) return emp.employeeCode;
      return att.pin!;
    }
    return '-';
  }

  // _resolveAttEmployeeName used via _calcEmployeePayroll
  String resolveAttEmployeeName(Attendance att) {
    final code = _resolveAttEmployeeCode(att);
    final emp = _employees.where((e) => e.employeeCode == code).firstOrNull;
    if (emp != null) return emp.fullName;
    if (att.employeeName != null && att.employeeName!.isNotEmpty) {
      return att.employeeName!;
    }
    if (att.deviceUserName != null && att.deviceUserName!.isNotEmpty) {
      return att.deviceUserName!;
    }
    return '-';
  }

  Employee? _findEmployee(String code) {
    return _employees
        .where((e) => e.employeeCode == code || e.id == code)
        .firstOrNull;
  }

  // ──────── Insurance salary calculation ────────
  // Returns raw salary before cap (for BHXH and BHTN which have different caps)
  double _getInsuranceSalaryRaw(String socialInsType, double baseSalary,
      double completionSalary, double customInsuranceSalary) {
    switch (socialInsType) {
      case '0':
        return 0; // Không đóng
      case '1':
        return baseSalary;
      case '2':
        return baseSalary + completionSalary;
      case '3':
        final region = _toInt(_insuranceSettings['defaultRegion'], 1);
        switch (region) {
          case 1:
            return _toDouble(_insuranceSettings['minSalaryRegion1'], 4960000);
          case 2:
            return _toDouble(_insuranceSettings['minSalaryRegion2'], 4410000);
          case 3:
            return _toDouble(_insuranceSettings['minSalaryRegion3'], 3860000);
          case 4:
            return _toDouble(_insuranceSettings['minSalaryRegion4'], 3450000);
          default:
            return _toDouble(_insuranceSettings['minSalaryRegion1'], 4960000);
        }
      case '4':
        return customInsuranceSalary;
      default:
        return 0;
    }
  }

  double _calculateInsuranceSalary(String socialInsType, double baseSalary,
      double completionSalary, double customInsuranceSalary) {
    final maxIns =
        _toDouble(_insuranceSettings['maxInsuranceSalary'], 46800000);
    final raw = _getInsuranceSalaryRaw(
        socialInsType, baseSalary, completionSalary, customInsuranceSalary);
    // Áp dụng mức trần BHXH (20x lương cơ sở)
    return raw > maxIns ? maxIns : raw;
  }

  /// BHTN cap = 20 × regional minimum salary (different from BHXH cap)
  double _calculateBhtnInsuranceSalary(String socialInsType, double baseSalary,
      double completionSalary, double customInsuranceSalary) {
    final raw = _getInsuranceSalaryRaw(
        socialInsType, baseSalary, completionSalary, customInsuranceSalary);
    if (raw == 0) return 0;
    // BHTN cap = 20 × lương tối thiểu vùng (theo luật Việc làm 2013)
    final region = _toInt(_insuranceSettings['defaultRegion'], 1);
    double regionMin;
    switch (region) {
      case 1:
        regionMin = _toDouble(_insuranceSettings['minSalaryRegion1'], 4960000);
        break;
      case 2:
        regionMin = _toDouble(_insuranceSettings['minSalaryRegion2'], 4410000);
        break;
      case 3:
        regionMin = _toDouble(_insuranceSettings['minSalaryRegion3'], 3860000);
        break;
      case 4:
        regionMin = _toDouble(_insuranceSettings['minSalaryRegion4'], 3450000);
        break;
      default:
        regionMin = _toDouble(_insuranceSettings['minSalaryRegion1'], 4960000);
    }
    final maxBhtn = regionMin * 20;
    return raw > maxBhtn ? maxBhtn : raw;
  }

  // ──────── Safe numeric parsing helpers ────────
  static double _toDouble(dynamic v, [double d = 0]) {
    if (v == null) return d;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? d;
    return d;
  }

  static int _toInt(dynamic v, [int d = 0]) {
    if (v == null) return d;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? d;
    return d;
  }

  static double _benefitField(Map<String, dynamic>? benefit, String key) {
    if (benefit == null) return 0;
    final pascal = key.isEmpty ? key : '${key[0].toUpperCase()}${key.substring(1)}';
    return _toDouble(benefit[key] ?? benefit[pascal]);
  }

  /// Đọc phụ cấp từ danh mục — cùng thuật toán màn Thiết lập lương.
  /// PC cố định / theo ngày = mức cấu hình; Tổng PC kỳ = thực nhận theo công/giờ.
  ({
    double fixedAllowance,
    double dailyAllowanceRate,
    double hourlyAllowanceRate,
    double total,
  }) _calcEmployeeAllowances({
    required String? employeeId,
    required double workDays,
    required double totalWorkHours,
    required double shiftLevelAllowance,
  }) {
    final empId = employeeId ?? '';
    final fixedTotal = AllowanceCalculator.sumForEmployee(
      allowances: _allowanceSettings,
      employeeId: empId,
      allowanceType: 0,
    );
    final dailyRateTotal = AllowanceCalculator.sumForEmployee(
      allowances: _allowanceSettings,
      employeeId: empId,
      allowanceType: 1,
    );
    final hourlyRateTotal = AllowanceCalculator.sumForEmployee(
      allowances: _allowanceSettings,
      employeeId: empId,
      allowanceType: 2,
    );

    final total = shiftLevelAllowance +
        fixedTotal +
        dailyRateTotal * workDays +
        hourlyRateTotal * totalWorkHours;
    return (
      fixedAllowance: fixedTotal,
      dailyAllowanceRate: dailyRateTotal,
      hourlyAllowanceRate: hourlyRateTotal,
      total: total,
    );
  }

  /// Parse SalaryRateType: backend sends string enum ("Hourly","Monthly","Daily","Shift") or int
  static int _parseRateType(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      switch (v) {
        case 'Hourly':
          return 0;
        case 'Monthly':
          return 1;
        case 'Daily':
          return 2;
        case 'Shift':
          return 3;
        default:
          return int.tryParse(v) ?? 1;
      }
    }
    return 1; // default Monthly
  }

  // ──────── Salary calculation per employee ────────
  Map<String, dynamic> _calcEmployeePayroll(
      String empCode, List<Attendance> empAttendances) {
    final emp = _findEmployee(empCode);
    final empName = emp?.fullName ?? empCode;

    // Salary profile
    Map<String, dynamic>? profile;
    if (emp != null) {
      final sp = _employeeSalaryProfiles
          .where((e) =>
              e['employeeId'] == emp.id ||
              e['employeeCode'] == emp.employeeCode)
          .firstOrNull;
      profile = sp?['profile'] as Map<String, dynamic>?;
    }

    Map<String, dynamic>? benefit;
    if (profile != null) {
      final rawBenefit = profile['benefit'] ?? profile['Benefit'];
      if (rawBenefit is Map) {
        benefit = Map<String, dynamic>.from(rawBenefit);
      }
    }
    final double baseSalary = _benefitField(benefit, 'rate');
    final int rateType = _parseRateType(benefit?['rateType'] ?? benefit?['RateType']);
    final double completionSalary = _benefitField(benefit, 'completionSalary');
    final String socialInsType =
        (benefit?['socialInsuranceType'] ?? 0).toString();
    final double customInsuranceSalary = _toDouble(benefit?['insuranceSalary']);
    final bool hasHealthInsurance = benefit?['hasHealthInsurance'] == true;

    // Overtime settings
    final int holidayOtType = _toInt(benefit?['holidayOvertimeType'], 1);
    final double holidayOtDailyRate =
        _toDouble(benefit?['holidayOvertimeDailyRate']);
    final int hourlyOtType = _toInt(benefit?['hourlyOvertimeType'], 1);
    final double hourlyOtFixedRate =
        _toDouble(benefit?['hourlyOvertimeFixedRate']);

    // Shift salary
    final int shiftSalaryType = _toInt(benefit?['shiftSalaryType']);
    final double fixedShiftRate = _toDouble(benefit?['fixedShiftRate']);

    // Paid leave settings
    final String paidDayOff = benefit?['weeklyOffDays']?.toString() ?? 'Sunday';
    final String paidLeaveType =
        benefit?['paidLeaveType']?.toString() ?? 'sunday';

    // Standard work days - calculate dynamically based on paidLeaveType and month
    final double standardWorkDays =
        _calcStandardWorkDays(paidLeaveType, paidDayOff);

    // Scheduled check-in/check-out from benefit
    final String? checkInStr = benefit?['checkIn']?.toString();
    final String? checkOutStr = benefit?['checkOut']?.toString();
    int scheduledInHour = 8, scheduledInMin = 0;
    int scheduledOutHour = 17, scheduledOutMin = 0;
    if (checkInStr != null && checkInStr.contains(':')) {
      final parts = checkInStr.split(':');
      scheduledInHour = int.tryParse(parts[0]) ?? 8;
      scheduledInMin = int.tryParse(parts[1]) ?? 0;
    }
    if (checkOutStr != null && checkOutStr.contains(':')) {
      final parts = checkOutStr.split(':');
      scheduledOutHour = int.tryParse(parts[0]) ?? 17;
      scheduledOutMin = int.tryParse(parts[1]) ?? 0;
    }

    // Standard hours per day
    final double standardDayHours =
        _toDouble(benefit?['standardHoursPerDay'], 8.0);

    // Salary type label
    String salaryTypeLabel;
    switch (rateType) {
      case 0:
        salaryTypeLabel = _l10n.hourly;
        break;
      case 1:
        salaryTypeLabel = _l10n.monthly;
        break;
      case 2:
        salaryTypeLabel = _l10n.daily;
        break;
      case 3:
        salaryTypeLabel = 'Ca';
        break;
      default:
        salaryTypeLabel = _l10n.monthly;
    }

    // ═══ Chấm công: cùng nguồn & thuật toán tab "Tổng hợp theo ca" ═══
    final shiftRecords = _shiftRecordsForEmployee(empCode);
    final shiftPairs = computeDailyShiftPairs(
      attendances: empAttendances,
      fromDate: _fromDate,
      toDate: _toDate,
      shiftTemplates: _shifts,
      shiftSalaryLevels: _shiftSalaryLevels,
      salaryProfiles: _salaryProfilesForShiftCalc(),
      dayEndHour: _dayEndHour,
      dayEndMinute: _dayEndMinute,
    );
    final attStats = aggregatePayrollStatsFromShiftRecords(
      records: shiftRecords,
      standardDayHours: standardDayHours,
      shiftPairs: shiftPairs,
    );

    final totalWorkHours = attStats.totalWorkHours;
    final standardHours = attStats.standardHours;
    final otHoursWeekday = attStats.otHoursWeekday;
    final otHoursWeekend = attStats.otHoursWeekend;
    final otHoursHoliday = attStats.otHoursHoliday;
    final workDays = attStats.workDays;
    final lateCount = attStats.lateCount;
    final lateMinutes = attStats.lateMinutes;
    final earlyCount = attStats.earlyCount;
    final earlyMinutes = attStats.earlyMinutes;
    final totalShifts = attStats.totalShifts;
    final overnightShifts = attStats.overnightShifts;

    final daysWithWork = <String>{
      for (final r in shiftRecords)
        if (r.workCount > 0) DateFormat('yyyy-MM-dd').format(r.date),
    };

    int paidLeaveDays = 0;
    int absentDays = 0;

    // Count paid leave and absent days
    for (var d = _fromDate;
        !d.isAfter(_toDate);
        d = d.add(const Duration(days: 1))) {
      final key = DateFormat('yyyy-MM-dd').format(d);
      if (_isHoliday(d)) continue;

      bool isPaidOff = false;
      switch (paidLeaveType) {
        case 'sunday':
          isPaidOff = d.weekday == DateTime.sunday;
          break;
        case 'saturday':
          isPaidOff = d.weekday == DateTime.saturday;
          break;
        case 'sat-sun':
          isPaidOff =
              d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
          break;
        case 'sat-afternoon-sun':
          isPaidOff = d.weekday == DateTime.sunday;
          // Saturday afternoon is counted as 0.5 in standardWorkDays calculation
          break;
        case 'off-1':
        case 'off-2':
        case 'off-3':
        case 'off-4':
          isPaidOff =
              false; // off-X days are flat deductions from standardWorkDays, not per-day
          break;
        default:
          // Fallback: use weeklyOffDays
          isPaidOff =
              (paidDayOff.contains('Sunday') && d.weekday == DateTime.sunday) ||
                  (paidDayOff.contains('Saturday') &&
                      d.weekday == DateTime.saturday);
      }

      if (isPaidOff) {
        paidLeaveDays++;
      } else if (!daysWithWork.contains(key) && d.isBefore(DateTime.now())) {
        absentDays++;
      }
    }

    // ═══ Salary calculation ═══
    double workSalary = 0;
    double hourlyRate = 0;
    double shiftLevelAllowance = 0;

    switch (rateType) {
      case 0: // Hourly
        hourlyRate = baseSalary;
        workSalary = baseSalary * standardHours;
        break;
      case 1: // Monthly
        hourlyRate = standardWorkDays > 0
            ? baseSalary / standardWorkDays / standardDayHours
            : 0;
        workSalary = standardWorkDays > 0
            ? (baseSalary / standardWorkDays) * workDays
            : 0;
        break;
      case 2: // Daily
        hourlyRate = baseSalary / standardDayHours;
        workSalary = baseSalary * workDays;
        break;
      case 3: // Shift-based
        if (shiftSalaryType == 0) {
          workSalary = applyOvernightShiftCoefficient(
            workSalary: fixedShiftRate * totalShifts,
            totalShifts: totalShifts,
            overnightShifts: overnightShifts,
          );
          hourlyRate = fixedShiftRate / standardDayHours;
        } else {
          // Two-pass: prefer level targeting this employee specifically,
          // then fall back to default level (no employeeIds restriction).
          Map<String, dynamic>? matchedLevel;
          for (final level in _shiftSalaryLevels) {
            if (level['isActive'] == false) continue;
            final levelEmpIds = level['employeeIds']?.toString();
            if (levelEmpIds == null || levelEmpIds.isEmpty) continue;
            if (emp == null) continue;
            try {
              final ids = jsonDecode(levelEmpIds) as List;
              if (ids.contains(emp.id)) {
                matchedLevel = level;
                break;
              }
            } catch (_) {}
          }
          if (matchedLevel == null) {
            for (final level in _shiftSalaryLevels) {
              if (level['isActive'] == false) continue;
              final levelEmpIds = level['employeeIds']?.toString();
              if (levelEmpIds == null || levelEmpIds.isEmpty) {
                matchedLevel = level;
                break;
              }
            }
          }
          if (matchedLevel != null) {
            final lvlRateType = matchedLevel['rateType']?.toString() ?? 'fixed';
            final lvlFixedRate =
                _toDouble(matchedLevel['fixedRate'], fixedShiftRate);
            final lvlHourlyRate = _toDouble(matchedLevel['hourlyRate']);
            final lvlMultiplier = _toDouble(matchedLevel['multiplier'], 1.0);
            shiftLevelAllowance =
                _toDouble(matchedLevel['shiftAllowance']) * totalShifts;
            switch (lvlRateType) {
              case 'hourly':
                final effHourly = lvlHourlyRate > 0
                    ? lvlHourlyRate
                    : fixedShiftRate / standardDayHours;
                workSalary = effHourly * totalWorkHours;
                // Ca qua đêm: +30% trên giờ chuẩn/ca đêm
                if (overnightShifts > 0) {
                  workSalary +=
                      effHourly * standardDayHours * overnightShifts * 0.3;
                }
                hourlyRate = effHourly;
                break;
              case 'multiplier':
                final perShift = fixedShiftRate * lvlMultiplier;
                workSalary = applyOvernightShiftCoefficient(
                  workSalary: perShift * totalShifts,
                  totalShifts: totalShifts,
                  overnightShifts: overnightShifts,
                );
                hourlyRate = perShift / standardDayHours;
                break;
              default: // 'fixed'
                workSalary = applyOvernightShiftCoefficient(
                  workSalary: lvlFixedRate * totalShifts,
                  totalShifts: totalShifts,
                  overnightShifts: overnightShifts,
                );
                hourlyRate = lvlFixedRate / standardDayHours;
            }
          } else {
            // Không tìm thấy mức lương ca, dùng fixedShiftRate từ Benefit
            workSalary = applyOvernightShiftCoefficient(
              workSalary: fixedShiftRate * totalShifts,
              totalShifts: totalShifts,
              overnightShifts: overnightShifts,
            );
            hourlyRate = fixedShiftRate / standardDayHours;
          }
        }
        break;
    }

    // Lương hoàn thành theo công (monthly only) — mức tháng prorate giống lương CB.
    double completionSalaryEarned = 0;
    if (rateType == 1 && completionSalary > 0 && standardWorkDays > 0) {
      completionSalaryEarned =
          (completionSalary / standardWorkDays) * workDays;
    }

    // ═══ OT salary ═══
    double otSalary = 0;
    if (hourlyOtType == 0) {
      otSalary = (otHoursWeekday + otHoursWeekend + otHoursHoliday) *
          hourlyOtFixedRate;
    } else if (hourlyOtType == 1) {
      otSalary += otHoursWeekday * hourlyRate * 1.5;
      otSalary += otHoursWeekend * hourlyRate * 2.0;
      otSalary += otHoursHoliday * hourlyRate * 3.0;
    }

    double holidayDaySalary = 0;
    if (holidayOtType == 0 && otHoursHoliday > 0) {
      final holidayWorkDays = (otHoursHoliday / standardDayHours).ceil();
      holidayDaySalary = holidayOtDailyRate * holidayWorkDays;
    }
    otSalary += holidayDaySalary;

    // ═══ Allowances ═══
    final allowanceBreakdown = _calcEmployeeAllowances(
      employeeId: emp?.id,
      workDays: workDays,
      totalWorkHours: totalWorkHours,
      shiftLevelAllowance: shiftLevelAllowance,
    );
    final totalAllowance = allowanceBreakdown.total;
    final fixedAllowancePaid = allowanceBreakdown.fixedAllowance;
    final dailyAllowanceRate = allowanceBreakdown.dailyAllowanceRate;

    // ═══ Bonuses & penalties from transactions ═══
    double bonusTotal = 0;
    double penaltyTotal = 0;
    final empId = emp?.id;
    for (final tx in _transactions) {
      // Match by employeeId or employeeUserId (backward compatibility)
      final txEmpId = tx['employeeId']?.toString();
      final txEmpUserId = tx['employeeUserId']?.toString();
      if (txEmpId != empId &&
          txEmpUserId != empId &&
          txEmpId != empCode &&
          txEmpUserId != empCode) {
        continue;
      }
      final txType = tx['type']?.toString().toLowerCase() ?? '';
      final amount = _toDouble(tx['amount']);
      final status = tx['status']?.toString().toLowerCase() ?? '';
      if (status == 'rejected' || status == 'cancelled') continue;
      // Bỏ qua thưởng/phạt đã chi tiền mặt; giữ thưởng chi vào lương (PaymentMethod=Salary)
      final txPaymentMethod = tx['paymentMethod']?.toString() ?? '';
      final isCashPaid =
          txPaymentMethod.isNotEmpty && txPaymentMethod != 'Salary';
      if (isCashPaid) continue;
      if (txType == 'bonus' || txType == 'reward' || txType == 'thưởng') {
        bonusTotal += amount;
      } else if (txType == 'penalty' || txType == 'fine' || txType == 'phạt') {
        penaltyTotal += amount.abs(); // Ensure positive for deduction
      }
    }

    // ═══ Late/early penalties from penalty settings (tiered system) ═══
    double latePenaltyTotal = 0;
    // Use tiered penalty rates if available, otherwise flat rates
    final double late15 = _toDouble(_penaltySettings['lateDeduction15Min']);
    final double late30 = _toDouble(_penaltySettings['lateDeduction30Min']);
    final double late60 = _toDouble(_penaltySettings['lateDeduction60Min']);
    final double earlyL15 =
        _toDouble(_penaltySettings['earlyLeaveDeduction15Min']);
    final double earlyL30 =
        _toDouble(_penaltySettings['earlyLeaveDeduction30Min']);
    final double earlyL60 =
        _toDouble(_penaltySettings['earlyLeaveDeduction60Min']);
    final double unauthorizedLeavePenalty =
        _toDouble(_penaltySettings['unauthorizedLeaveDeduction']);

    // Fallback to generic rates
    final double penaltyPerLate =
        _toDouble(_penaltySettings['lateDeduction'], late15);
    final double penaltyPerEarly =
        _toDouble(_penaltySettings['earlyLeaveDeduction'], earlyL15);
    final double penaltyPerAbsent = _toDouble(
        _penaltySettings['absentDeduction'], unauthorizedLeavePenalty);

    if (late15 > 0 || late30 > 0 || late60 > 0) {
      for (final r in shiftRecords) {
        if (_isHoliday(r.date) || _isWeekend(r.date)) continue;
        final lateMins = r.lateMinutes;
        if (lateMins > 5) {
          if (lateMins >= 60) {
            latePenaltyTotal += late60 > 0 ? late60 : penaltyPerLate;
          } else if (lateMins >= 30) {
            latePenaltyTotal += late30 > 0 ? late30 : penaltyPerLate;
          } else {
            latePenaltyTotal += late15 > 0 ? late15 : penaltyPerLate;
          }
        }
      }
      for (final r in shiftRecords) {
        if (_isHoliday(r.date) || _isWeekend(r.date)) continue;
        final earlyMins = r.earlyMinutes;
        if (earlyMins > 5) {
          if (earlyMins >= 60) {
            latePenaltyTotal += earlyL60 > 0 ? earlyL60 : penaltyPerEarly;
          } else if (earlyMins >= 30) {
            latePenaltyTotal += earlyL30 > 0 ? earlyL30 : penaltyPerEarly;
          } else {
            latePenaltyTotal += earlyL15 > 0 ? earlyL15 : penaltyPerEarly;
          }
        }
      }
    } else {
      // Flat rate penalties (backward compatible)
      latePenaltyTotal =
          (penaltyPerLate * lateCount) + (penaltyPerEarly * earlyCount);
    }
    // Absent penalty
    latePenaltyTotal += penaltyPerAbsent * absentDays;

    // ═══ Insurance (BHXH, BHYT, BHTN, Đoàn phí) ═══
    // Use correct field names from InsuranceSetting entity (camelCase from C#)
    final double bhxhRate =
        _toDouble(_insuranceSettings['bhxhEmployeeRate'], 8);
    final double bhytRate =
        _toDouble(_insuranceSettings['bhytEmployeeRate'], 1.5);
    final double bhtnRate =
        _toDouble(_insuranceSettings['bhtnEmployeeRate'], 1);
    final double unionFeeRate =
        _toDouble(_insuranceSettings['unionFeeEmployeeRate'], 1);

    final double insuranceSalary = _calculateInsuranceSalary(
        socialInsType, baseSalary, completionSalary, customInsuranceSalary);
    // BHTN uses different cap (20x regional min salary, not 20x base salary)
    final double bhtnInsuranceSalary = _calculateBhtnInsuranceSalary(
        socialInsType, baseSalary, completionSalary, customInsuranceSalary);

    // If socialInsType == '0' (chưa đóng BHXH), insuranceSalary = 0 => all = 0
    // Otherwise: mức đóng × hệ số tổng NLĐ đóng
    final double bhxhPart = insuranceSalary * bhxhRate / 100;
    final double bhytPart =
        hasHealthInsurance ? 0 : insuranceSalary * bhytRate / 100;
    final double bhtnPart = bhtnInsuranceSalary * bhtnRate / 100;
    final double unionFeePart = insuranceSalary * unionFeeRate / 100;
    final double totalInsurance = bhxhPart + bhytPart + bhtnPart + unionFeePart;

    // ═══ Tax (PIT – Vietnamese progressive) ═══
    final double grossIncome = workSalary +
        completionSalaryEarned +
        otSalary +
        totalAllowance +
        bonusTotal;
    final double taxableIncome = grossIncome - totalInsurance;
    double pit = 0;
    final double personalDeduction =
        _toDouble(_taxSettings['personalDeduction'], 11000000);
    final double dependentDeduction =
        _toDouble(_taxSettings['dependentDeduction'], 4400000);

    // Get dependents from employee tax deductions
    int dependents = 0;
    if (emp != null) {
      final empTaxDed = _employeeTaxDeductions
          .where((d) =>
              d['employeeId']?.toString() == emp.id ||
              d['employeeUserId']?.toString() == emp.id)
          .firstOrNull;
      if (empTaxDed != null) {
        dependents = _toInt(empTaxDed['numberOfDependents']);
      }
    }

    final double taxable =
        taxableIncome - personalDeduction - (dependentDeduction * dependents);
    if (taxable > 0) {
      pit = _calculatePIT(taxable);
    }

    // ═══ Advance (filter by PaidDate within period) ═══
    double advanceTotal = 0;
    for (final req in _advanceRequests) {
      final reqEmpId =
          req['employeeId']?.toString() ?? req['employeeUserId']?.toString();
      if (reqEmpId != empId && reqEmpId != empCode) continue;
      final status = req['status'];
      final isPaid = req['isPaid'] == true;
      if ((status == 1 || status == 'Approved') && isPaid) {
        // Filter by payment date
        final paidDateStr = req['paidDate']?.toString();
        if (paidDateStr == null) continue;
        final paidDate = DateTime.tryParse(paidDateStr);
        if (paidDate == null) continue;
        if (paidDate.isBefore(_fromDate) || paidDate.isAfter(_toDate)) continue;
        advanceTotal += _toDouble(req['amount']);
      }
    }

    // ═══ KPI Salary (Lương KPI = Tổng thưởng từ KPI targets) ═══
    double kpiSalaryAmount = 0;
    final kpiTarget =
        _kpiEmployeeTargets.cast<Map<String, dynamic>?>().firstWhere(
              (t) => t?['employeeId']?.toString() == emp?.id,
              orElse: () => null,
            );
    if (kpiTarget != null) {
      final tgt = ((kpiTarget['targetValue'] ?? 0) as num).toDouble();
      final act = ((kpiTarget['actualValue'] ?? 0) as num).toDouble();
      final pct = tgt > 0 ? act / tgt * 100 : 0.0;
      final cs = ((kpiTarget['completionSalary'] ?? 0) as num).toDouble();
      final salaryHT = pct >= 100 ? cs : 0.0;
      final penaltyBonus = _kpiCalcPenaltyBonus(kpiTarget);
      final tierBonuses = _kpiCalcTierBonuses(kpiTarget);
      final totalTierBonus =
          tierBonuses.fold<double>(0, (s, b) => s + _toDouble(b['bonus']));
      kpiSalaryAmount = salaryHT + penaltyBonus + totalTierBonus;
    }

    // ═══ Sales & Commission ═══
    double salesAmount = 0;
    double commissionAmount = 0;
    final empTarget =
        _kpiEmployeeTargets.cast<Map<String, dynamic>?>().firstWhere(
              (t) =>
                  t?['employeeId']?.toString() == emp?.id &&
                  t?['criteriaType'] == 0,
              orElse: () => null,
            );
    if (empTarget != null) {
      salesAmount = _toDouble(empTarget['actualValue']);
      commissionAmount = _calculateCommission(salesAmount);
    }

    // ═══ Production / Piece-rate salary ═══
    double productionAmount = 0;
    final prodSummary =
        _productionSummaries.cast<Map<String, dynamic>?>().firstWhere(
              (s) =>
                  s?['employeeId']?.toString() == emp?.id ||
                  s?['employeeCode']?.toString() == empCode,
              orElse: () => null,
            );
    if (prodSummary != null) {
      productionAmount = _toDouble(prodSummary['totalAmount']);
    }

    // ═══ Total deductions ═══
    final double totalDeduction =
        penaltyTotal + latePenaltyTotal + totalInsurance + pit + advanceTotal;

    // ═══ Net salary ═══
    final double totalSalary = workSalary +
        completionSalaryEarned +
        otSalary +
        totalAllowance +
        bonusTotal +
        commissionAmount +
        kpiSalaryAmount +
        productionAmount;
    final double netSalary = totalSalary - totalDeduction;

    // ═══ Salary by type ═══
    final double dailySalary = rateType == 2 ? workSalary : 0;
    final double shiftSalary = rateType == 3 ? workSalary : 0;
    final double hourlySalary = rateType == 0 ? workSalary : 0;
    final double otTotalHours =
        otHoursWeekday + otHoursWeekend + otHoursHoliday;

    final salaryProfileId =
        (benefit?['id'] ?? benefit?['Id'])?.toString() ?? '';

    return {
      'code': empCode,
      'name': empName,
      'employeeUserId': emp?.applicationUserId ?? '',
      'employeeId': emp?.id ?? '',
      'salaryProfileId': salaryProfileId,
      'department': emp?.department ?? '',
      'position': emp?.position ?? '',
      'salaryType': salaryTypeLabel,
      'standardDays': standardWorkDays,
      'workDays': workDays,
      'paidLeaveDays': paidLeaveDays,
      'totalHours': totalWorkHours,
      'standardHours': standardHours,
      'otTotalHours': otTotalHours,
      'otHoursWeekday': otHoursWeekday,
      'otHoursWeekend': otHoursWeekend,
      'otHoursHoliday': otHoursHoliday,
      'lateCount': lateCount,
      'lateMinutes': lateMinutes,
      'earlyCount': earlyCount,
      'earlyMinutes': earlyMinutes,
      'absentDays': absentDays,
      'baseSalary': baseSalary,
      'completionSalary': completionSalary,
      'completionSalaryEarned': completionSalaryEarned,
      'dailySalary': dailySalary,
      'shiftSalary': shiftSalary,
      'hourlySalary': hourlySalary,
      'workSalary': workSalary,
      'otSalary': otSalary,
      'allowanceFixed': fixedAllowancePaid,
      'allowanceDaily': dailyAllowanceRate,
      'mealAllowance': fixedAllowancePaid,
      'responsibilityAllowance': dailyAllowanceRate,
      'otherAllowance': 0,
      'totalAllowance': totalAllowance,
      'bonus': bonusTotal,
      'penalty': penaltyTotal,
      'kpiSalary': kpiSalaryAmount,
      'productionAmount': productionAmount,
      'commission': commissionAmount,
      'latePenalty': latePenaltyTotal,
      'bhxh': totalInsurance,
      'bhxhPart': bhxhPart,
      'bhytPart': bhytPart,
      'bhtnPart': bhtnPart,
      'unionFeePart': unionFeePart,
      'insuranceSalary': insuranceSalary,
      'totalInsurance': totalInsurance,
      'taxableIncome': taxable > 0 ? taxable : 0,
      'pit': pit,
      'totalSalary': totalSalary,
      'advance': advanceTotal,
      'totalDeduction': totalDeduction,
      'netSalary': netSalary,
    };
  }

  // ──────── Commission calculation ────────
  double _calculateCommission(double sales) {
    if (sales <= 0 || _commissionSettings.isEmpty) return 0;
    final type = _commissionSettings['commissionType'] ?? 'flat';
    final flatRate = _toDouble(_commissionSettings['flatRate']);
    final threshold = _toDouble(_commissionSettings['minSalesThreshold']);
    final maxCap = _toDouble(_commissionSettings['maxCommissionCap']);

    double commission = 0;
    switch (type) {
      case 'flat':
        commission = sales * flatRate / 100;
        break;
      case 'tiered':
        final tiers = _commissionSettings['tiers'] as List? ?? [];
        for (final tier in tiers) {
          final min = _toDouble(tier['minSales']);
          final max = _toDouble(tier['maxSales'], double.infinity);
          final rate = _toDouble(tier['rate']);
          if (sales <= min) continue;
          final inBand = (sales > max ? max : sales) - min;
          if (inBand > 0) commission += inBand * rate / 100;
        }
        break;
      case 'threshold':
        if (sales > threshold) {
          commission = (sales - threshold) * flatRate / 100;
        }
        break;
    }
    if (maxCap > 0 && commission > maxCap) commission = maxCap;
    return commission;
  }

  // ──────── PIT calculation (progressive tax Vietnam) ────────
  double _calculatePIT(double taxableIncome) {
    // Vietnamese progressive PIT rates
    if (taxableIncome <= 0) return 0;
    double tax = 0;
    double remaining = taxableIncome;

    final brackets = [
      [5000000.0, 0.05],
      [5000000.0, 0.10],
      [8000000.0, 0.15],
      [14000000.0, 0.20],
      [20000000.0, 0.25],
      [28000000.0, 0.30],
      [double.infinity, 0.35],
    ];

    for (final bracket in brackets) {
      final limit = bracket[0];
      final rate = bracket[1];
      if (remaining <= 0) break;
      final taxable = remaining > limit ? limit : remaining;
      tax += taxable * rate;
      remaining -= taxable;
    }

    return tax;
  }

  // ──────── Build payroll rows ────────
  List<Map<String, dynamic>> _buildPayrollData() {
    if (_cachedPayrollData != null) return _cachedPayrollData!;
    _ensureShiftRecordsCache();

    // Filter employees by branch if specified
    final employees = widget.branchId == null
        ? _employees
        : _employees.where((e) => e.branchId == widget.branchId).toList();
    final branchCodes = widget.branchId == null
        ? null
        : employees.map((e) => e.employeeCode).toSet();

    // Group attendance by resolved employee code
    final attendances =
        _periodAttendances.isNotEmpty ? _periodAttendances : widget.attendances;
    final grouped = <String, List<Attendance>>{};
    for (final att in attendances) {
      final code = _resolveAttEmployeeCode(att);
      if (code == '-') continue;
      if (branchCodes != null && !branchCodes.contains(code)) continue;
      grouped.putIfAbsent(code, () => []).add(att);
    }

    // Also add employees with salary profiles but no attendance
    for (final emp in employees) {
      if (!grouped.containsKey(emp.employeeCode)) {
        grouped[emp.employeeCode] = [];
      }
    }

    final rows = <Map<String, dynamic>>[];
    for (final entry in grouped.entries) {
      rows.add(_calcEmployeePayroll(entry.key, entry.value));
    }

    // Sort
    rows.sort((a, b) {
      final aVal = a[_sortColumn];
      final bVal = b[_sortColumn];
      int cmp = 0;
      if (aVal is num && bVal is num) {
        cmp = aVal.compareTo(bVal);
      } else {
        cmp = (aVal?.toString() ?? '').compareTo(bVal?.toString() ?? '');
      }
      return _sortAscending ? cmp : -cmp;
    });

    // Filter
    var result = rows;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = rows.where((r) {
        return (r['code'] as String).toLowerCase().contains(q) ||
            (r['name'] as String).toLowerCase().contains(q) ||
            (r['department'] as String).toLowerCase().contains(q);
      }).toList();
    }

    // Filter by department
    if (_selectedDepartment != null && _selectedDepartment!.isNotEmpty) {
      result = result
          .where((r) => r['department']?.toString() == _selectedDepartment)
          .toList();
    }

    // Filter by selected employees
    if (_selectedEmployeeIds.isNotEmpty) {
      result = result.where((r) {
        final code = r['code']?.toString() ?? '';
        final emp = _findEmployee(code);
        return _selectedEmployeeIds.contains(emp?.id) ||
            _selectedEmployeeIds.contains(code);
      }).toList();
    }

    _cachedPayrollData = result;
    return result;
  }

  List<Employee> _employeesInBranch() {
    if (widget.branchId == null) return _employees;
    return _employees.where((e) => e.branchId == widget.branchId).toList();
  }

  List<String> _availableDepartments() {
    final depts = _employeesInBranch()
        .map((e) => e.department?.trim())
        .where((d) => d != null && d.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    depts.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return depts;
  }

  /// Nhân viên trong phạm vi lọc (chi nhánh + phòng ban) — dùng cho dialog chọn NV.
  List<Employee> _payrollEmployeePool() {
    var pool = _employeesInBranch();
    if (_selectedDepartment != null && _selectedDepartment!.isNotEmpty) {
      pool = pool.where((e) => e.department == _selectedDepartment).toList();
    }
    pool.sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    return pool;
  }

  void _pruneEmployeeSelectionToPool() {
    if (_selectedEmployeeIds.isEmpty) return;
    final poolIds = _payrollEmployeePool().map((e) => e.id).toSet();
    _selectedEmployeeIds.removeWhere((id) => !poolIds.contains(id));
  }

  bool _canFinalizePayroll() {
    if (!mounted) return false;
    if (_isEmployeeRole(context)) return false;
    return context.read<PermissionProvider>().canExport('Payroll');
  }

  List<Map<String, dynamic>> _payrollRowsForFinalize({required bool allInTable}) {
    final cached = _cachedPayrollData;
    _cachedPayrollData = null;
    final savedIds = Set<String>.from(_selectedEmployeeIds);
    if (allInTable) _selectedEmployeeIds.clear();
    final rows = List<Map<String, dynamic>>.from(_buildPayrollData());
    _selectedEmployeeIds = savedIds;
    _cachedPayrollData = cached;
    return rows;
  }

  Future<void> _showFinalizePayrollDialog() async {
    final hasSelection = _selectedEmployeeIds.isNotEmpty;
    final selectedCount = hasSelection ? _selectedEmployeeIds.length : 0;
    final allCount = _payrollRowsForFinalize(allInTable: true).length;

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chốt lương'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kỳ: ${DateFormat('dd/MM/yyyy').format(_fromDate)} — '
              '${DateFormat('dd/MM/yyyy').format(_toDate)}',
            ),
            const SizedBox(height: 8),
            const Text(
              'Sau khi chốt, hệ thống tạo phiếu lương tại menu Phiếu lương.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          if (hasSelection)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'selected'),
              child: Text('Chốt $selectedCount NV đã chọn'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'all'),
            child: Text('Chốt tất cả ($allCount NV)'),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    final rows = choice == 'selected' && hasSelection
        ? _payrollRowsForFinalize(allInTable: false)
        : _payrollRowsForFinalize(allInTable: true);
    if (rows.isEmpty) {
      appNotification.showWarning(
        title: 'Chốt lương',
        message: 'Không có nhân viên để chốt lương',
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận chốt lương'),
        content: Text(
          'Tạo phiếu lương cho ${rows.length} nhân viên?\n'
          'Phiếu đã tồn tại cùng kỳ sẽ được cập nhật.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Chốt lương'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await _finalizePayrollRows(rows);
  }

  Future<void> _finalizePayrollRows(List<Map<String, dynamic>> rows) async {
    setState(() => _isFinalizing = true);
    try {
      final items = <Map<String, dynamic>>[];
      final skipped = <String>[];

      for (final row in rows) {
        final code = row['code']?.toString() ?? '';
        final emp = _findEmployee(code);
        final userId = row['employeeUserId']?.toString() ??
            emp?.applicationUserId ??
            '';
        final employeeId = emp?.id ?? row['employeeId']?.toString() ?? '';
        final profileId = row['salaryProfileId']?.toString() ?? '';
        if (employeeId.isEmpty || profileId.isEmpty) {
          skipped.add(row['name']?.toString() ?? code);
          continue;
        }
        final penalty = _toDouble(row['penalty']) + _toDouble(row['latePenalty']);
        final advance = _toDouble(row['advance']);
        final item = <String, dynamic>{
          'employeeId': employeeId,
          'salaryProfileId': profileId,
          'regularWorkUnits': _toDouble(row['workDays']),
          'overtimeUnits': _toDouble(row['otTotalHours']),
          'baseSalary': _toDouble(row['baseSalary']),
          'overtimePay': _toDouble(row['otSalary']),
          'bonus': _toDouble(row['bonus']),
          'deductions': penalty + advance,
          'allowances': _toDouble(row['totalAllowance']),
          'socialInsurance': _toDouble(row['bhxhPart']),
          'healthInsurance': _toDouble(row['bhytPart']),
          'unemploymentInsurance': _toDouble(row['bhtnPart']),
          'tax': _toDouble(row['pit']),
          'grossSalary': _toDouble(row['totalSalary']),
          'netSalary': _toDouble(row['netSalary']),
        };
        if (userId.isNotEmpty) item['employeeUserId'] = userId;
        items.add(item);
      }

      if (items.isEmpty) {
        appNotification.showWarning(
          title: 'Chốt lương',
          message: 'Không có NV hợp lệ (thiếu hồ sơ hoặc bảng lương)',
        );
        return;
      }

      final periodMonth = _toDate.month;
      final periodYear = _toDate.year;
      final res = await _apiService.finalizePayroll({
        'year': periodYear,
        'month': periodMonth,
        'periodStart': DateTime(_fromDate.year, _fromDate.month, _fromDate.day)
            .toIso8601String(),
        'periodEnd': DateTime(_toDate.year, _toDate.month, _toDate.day, 23, 59, 59)
            .toIso8601String(),
        'overwriteExisting': true,
        'items': items,
      });

      if (!mounted) return;
      if (res['isSuccess'] == true) {
        final data = res['data'] as Map<String, dynamic>? ?? {};
        final created = (data['created'] as num?)?.toInt() ?? 0;
        final updated = (data['updated'] as num?)?.toInt() ?? 0;
        final skipCount = (data['skipped'] as num?)?.toInt() ?? 0;
        final serverErrors = (data['errors'] as List?)
                ?.map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList() ??
            [];
        var msg = 'Chốt lương: $created mới, $updated cập nhật';
        if (skipCount > 0) msg += ', $skipCount bỏ qua';
        if (skipped.isNotEmpty) {
          msg += '\n${skipped.length} NV thiếu hồ sơ/bảng lương (phía app)';
        }
        if (serverErrors.isNotEmpty) {
          msg += '\n${serverErrors.take(3).join('\n')}';
        }
        appNotification.showSuccess(title: 'Chốt lương', message: msg);
      } else {
        final data = res['data'] as Map<String, dynamic>? ?? {};
        final serverErrors = (data['errors'] as List?)
                ?.map((e) => e.toString())
                .where((e) => e.isNotEmpty)
                .toList() ??
            [];
        var msg = res['message']?.toString() ?? 'Chốt lương thất bại';
        if (serverErrors.isNotEmpty) {
          msg += '\n${serverErrors.take(3).join('\n')}';
        }
        appNotification.showError(title: 'Chốt lương', message: msg);
      }
    } catch (e) {
      if (mounted) {
        appNotification.showError(
          title: 'Chốt lương',
          message: 'Lỗi: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _isFinalizing = false);
    }
  }

  Widget _buildFinalizeButton() {
    if (!_canFinalizePayroll()) return const SizedBox.shrink();
    return FilledButton.icon(
      onPressed: _isFinalizing ? null : _showFinalizePayrollDialog,
      icon: _isFinalizing
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.lock_outline, size: 18),
      label: Text(_isFinalizing ? 'Đang chốt...' : 'Chốt lương'),
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF059669),
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }

  // ──────── Public methods (called from PayrollScreen AppBar) ────────

  void showColumnSelectorDialog() {
    // Work on a temporary copy of columns so we can reorder without affecting state until apply
    var tempColumns = _columns
        .map((c) => PayrollColumn(
              key: c.key,
              label: c.label,
              defaultVisible: c.defaultVisible,
              visible: c.visible,
            ))
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) {
          // Exclude frozen columns from reordering
          final reorderableCols =
              tempColumns.where((c) => !_frozenKeys.contains(c.key)).toList();

          return ScrollableAlertDialog(
            title: Row(
              children: [
                const Icon(Icons.view_column, color: Colors.blue),
                const SizedBox(width: 8),
                const Expanded(
                    child: Text('Chọn & sắp xếp cột',
                        style: TextStyle(fontSize: 16))),
                TextButton(
                  onPressed: () {
                    setDialogState(() {
                      tempColumns = _defaultPayrollColumns()
                          .map((c) => PayrollColumn(
                                key: c.key,
                                label: c.label,
                                defaultVisible: c.defaultVisible,
                                visible: c.defaultVisible,
                              ))
                          .toList();
                    });
                  },
                  child: const Text('Mặc định', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            content: SizedBox(
              width: math
                  .min(460, MediaQuery.of(context).size.width - 32)
                  .toDouble(),
              height: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Frozen columns (not reorderable)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 4),
                    child: Text('Cột cố định (không thể di chuyển)',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500)),
                  ),
                  ...tempColumns.where((c) => _frozenKeys.contains(c.key)).map(
                        (col) => Container(
                          margin: const EdgeInsets.only(bottom: 2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.lock_outline,
                                  size: 14, color: Colors.grey.shade400),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(col.label,
                                      style: const TextStyle(
                                          fontSize: 13, color: Colors.grey))),
                            ],
                          ),
                        ),
                      ),
                  const Divider(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 4),
                    child: Text('Kéo để sắp xếp thứ tự cột',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500)),
                  ),
                  // Reorderable columns
                  Expanded(
                    child: ReorderableListView.builder(
                      itemCount: reorderableCols.length,
                      onReorder: (oldIndex, newIndex) {
                        setDialogState(() {
                          if (newIndex > oldIndex) newIndex--;
                          // Find in tempColumns (skip frozen ones)
                          final nonFrozen = tempColumns
                              .where((c) => !_frozenKeys.contains(c.key))
                              .toList();
                          final item = nonFrozen.removeAt(oldIndex);
                          nonFrozen.insert(newIndex, item);
                          // Rebuild tempColumns: frozen first, then reordered non-frozen
                          final frozen = tempColumns
                              .where((c) => _frozenKeys.contains(c.key))
                              .toList();
                          tempColumns = [...frozen, ...nonFrozen];
                        });
                      },
                      itemBuilder: (_, i) {
                        final col = reorderableCols[i];
                        return Container(
                          key: ValueKey(col.key),
                          margin: const EdgeInsets.only(bottom: 2),
                          decoration: BoxDecoration(
                            color: col.visible
                                ? Colors.blue.shade50
                                : Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: col.visible
                                  ? Colors.blue.shade200
                                  : Colors.grey.shade200,
                              width: 0.5,
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.only(left: 8, right: 0),
                            leading: Checkbox(
                              value: col.visible,
                              onChanged: (v) =>
                                  setDialogState(() => col.visible = v ?? true),
                              visualDensity: VisualDensity.compact,
                            ),
                            title: Text(col.label,
                                style: const TextStyle(fontSize: 13)),
                            trailing: ReorderableDragStartListener(
                              index: i,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                child: Icon(Icons.drag_handle,
                                    size: 18, color: Colors.grey.shade400),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () {
                  // Apply order and visibility from tempColumns
                  _columns = tempColumns.map((t) {
                    final orig = _columns.firstWhere((c) => c.key == t.key,
                        orElse: () => t);
                    orig.visible = t.visible;
                    return orig;
                  }).toList();
                  _saveColumnPreferences();
                  _cachedPayrollData = null;
                  setState(() {});
                  Navigator.pop(ctx);
                },
                child: const Text('Áp dụng'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _excelMergedText(
    excel_lib.Sheet sheet, {
    required int row,
    required int colStart,
    required int colEnd,
    required String text,
    excel_lib.CellStyle? style,
  }) {
    final cell = sheet.cell(
      excel_lib.CellIndex.indexByColumnRow(
          columnIndex: colStart, rowIndex: row),
    );
    cell.value = excel_lib.TextCellValue(text);
    if (style != null) cell.cellStyle = style;
    if (colEnd > colStart) {
      sheet.merge(
        excel_lib.CellIndex.indexByColumnRow(
            columnIndex: colStart, rowIndex: row),
        excel_lib.CellIndex.indexByColumnRow(columnIndex: colEnd, rowIndex: row),
      );
    }
  }

  void _excelSetCell(
    excel_lib.Sheet sheet,
    int row,
    int col,
    excel_lib.CellValue value, {
    excel_lib.CellStyle? style,
  }) {
    final cell = sheet.cell(
      excel_lib.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    );
    cell.value = value;
    if (style != null) cell.cellStyle = style;
  }

  String _excelColLetter(int colIndex) {
    var col = colIndex + 1;
    final buf = StringBuffer();
    while (col > 0) {
      final rem = (col - 1) % 26;
      buf.write(String.fromCharCode(65 + rem));
      col = (col - 1) ~/ 26;
    }
    return buf.toString().split('').reversed.join();
  }

  String _excelRef(int col, int row) => '${_excelColLetter(col)}${row + 1}';

  excel_lib.CellStyle _excelCenterStyle({
    bool bold = false,
    int fontSize = 11,
    String? backgroundHex,
    bool italic = false,
    excel_lib.NumFormat? numberFormat,
  }) {
    return excel_lib.CellStyle(
      bold: bold,
      italic: italic,
      fontSize: fontSize,
      horizontalAlign: excel_lib.HorizontalAlign.Center,
      verticalAlign: excel_lib.VerticalAlign.Center,
      backgroundColorHex: backgroundHex != null
          ? excel_lib.ExcelColor.fromHexString(backgroundHex)
          : excel_lib.ExcelColor.none,
      numberFormat: numberFormat ?? excel_lib.NumFormat.standard_0,
    );
  }

  excel_lib.CellStyle _excelLeftStyle({int fontSize = 11}) {
    return excel_lib.CellStyle(
      fontSize: fontSize,
      horizontalAlign: excel_lib.HorizontalAlign.Left,
      verticalAlign: excel_lib.VerticalAlign.Center,
    );
  }

  void _excelWritePayrollSignatures(
    excel_lib.Sheet sheet, {
    required int row,
    required int colCount,
  }) {
    final sigTitleStyle = _excelCenterStyle(bold: true);
    final sigHintStyle = _excelCenterStyle(fontSize: 10, italic: true);
    final part = (colCount / _payrollFooterSignatureLabels.length)
        .floor()
        .clamp(1, colCount);
    for (var i = 0; i < _payrollFooterSignatureLabels.length; i++) {
      final start = i * part;
      final end = i == _payrollFooterSignatureLabels.length - 1
          ? colCount - 1
          : math.min((i + 1) * part - 1, colCount - 1);
      _excelMergedText(
        sheet,
        row: row,
        colStart: start,
        colEnd: end,
        text: _payrollFooterSignatureLabels[i],
        style: sigTitleStyle,
      );
    }
    row += 4;
    for (var i = 0; i < _payrollFooterSignatureLabels.length; i++) {
      final start = i * part;
      final end = i == _payrollFooterSignatureLabels.length - 1
          ? colCount - 1
          : math.min((i + 1) * part - 1, colCount - 1);
      _excelMergedText(
        sheet,
        row: row,
        colStart: start,
        colEnd: end,
        text: '(Ký, ghi rõ họ tên)',
        style: sigHintStyle,
      );
    }
  }

  void exportToExcel() async {
    try {
      final data = _buildPayrollData();
      if (data.isEmpty) {
        appNotification.showError(
            title: 'Lỗi', message: 'Không có dữ liệu để xuất');
        return;
      }

      final visibleCols = _visiblePayrollColumns();
      final colCount = visibleCols.length;
      final wb = ExcelReportBuilder.createWorkbook(sheetName: 'Tổng hợp lương');
      final sheet = wb['Tổng hợp lương'];
      final headerStyle = ExcelReportBuilder.headerStyle();
      final dataStyle = _excelCenterStyle();
      final leftStyle = _excelLeftStyle();
      final totalStyle = _excelCenterStyle(
        bold: true,
        backgroundHex: '#EFF6FF',
      );
      for (var i = 0; i < colCount; i++) {
        sheet.setColumnWidth(i, _payrollColWidth(visibleCols[i]) / 7);
      }

      var row = 0;
      final lastCol = colCount - 1;
      _excelMergedText(
        sheet,
        row: row,
        colStart: 0,
        colEnd: lastCol,
        text: 'BẢNG TỔNG HỢP LƯƠNG',
        style: ExcelReportBuilder.titleStyle(),
      );
      row++;
      _excelMergedText(
        sheet,
        row: row,
        colStart: 0,
        colEnd: lastCol,
        text:
            'Kỳ lương: ${DateFormat('dd/MM/yyyy').format(_fromDate)} – ${DateFormat('dd/MM/yyyy').format(_toDate)}',
        style: _excelCenterStyle(fontSize: 12),
      );
      row++;
      _excelMergedText(
        sheet,
        row: row,
        colStart: 0,
        colEnd: lastCol,
        text:
            'Xuất lúc: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}  |  ${data.length} nhân viên',
        style: _excelCenterStyle(fontSize: 10, italic: true),
      );
      row += 2;

      final headerRow = row;
      ExcelReportBuilder.applyHeaderRow(
        sheet,
        headerRow,
        visibleCols.map((c) => c.label).toList(),
        style: headerStyle,
      );
      row++;

      final firstDataRow = row;
      final signStyle = _excelCenterStyle();
      for (var i = 0; i < data.length; i++) {
        final emp = data[i];
        for (var c = 0; c < visibleCols.length; c++) {
          final col = visibleCols[c];
          if (col.key == _employeeSignColumnKey) {
            _excelSetCell(
              sheet,
              row,
              c,
              excel_lib.TextCellValue(''),
              style: signStyle,
            );
          } else {
            _excelSetCell(
              sheet,
              row,
              c,
              _excelCellValue(col.key, emp, i),
              style: _isPayrollLeftAlignKey(col.key) ? leftStyle : dataStyle,
            );
          }
        }
        row++;
      }
      final lastDataRow = row - 1;
      final totalRow = row;

      for (var c = 0; c < visibleCols.length; c++) {
        final col = visibleCols[c];
        if (col.key == 'stt') {
          _excelSetCell(sheet, totalRow, c, excel_lib.TextCellValue(''),
              style: totalStyle);
        } else if (col.key == 'name') {
          _excelSetCell(sheet, totalRow, c,
              excel_lib.TextCellValue('TỔNG CỘNG'), style: totalStyle);
        } else if (col.key == 'code') {
          _excelSetCell(sheet, totalRow, c,
              excel_lib.TextCellValue('${data.length} NV'), style: totalStyle);
        } else if (col.key == _employeeSignColumnKey) {
          _excelSetCell(sheet, totalRow, c, excel_lib.TextCellValue(''),
              style: totalStyle);
        } else if (_isPayrollNumericKey(col.key) && lastDataRow >= firstDataRow) {
          final refStart = _excelRef(c, firstDataRow);
          final refEnd = _excelRef(c, lastDataRow);
          _excelSetCell(
            sheet,
            totalRow,
            c,
            excel_lib.FormulaCellValue('=SUM($refStart:$refEnd)'),
            style: _excelCenterStyle(
              bold: true,
              backgroundHex: '#EFF6FF',
              numberFormat: excel_lib.NumFormat.standard_0,
            ),
          );
        } else {
          _excelSetCell(sheet, totalRow, c, excel_lib.TextCellValue(''),
              style: totalStyle);
        }
      }

      row = totalRow + 2;
      _excelWritePayrollSignatures(sheet, row: row, colCount: colCount);

      final bytes = wb.encode();
      if (bytes != null) {
        final fn =
            'Bang_tong_hop_luong_${DateFormat('ddMMyyyy').format(_fromDate)}_${DateFormat('ddMMyyyy').format(_toDate)}.xlsx';
        await file_saver.saveAndOpenFileBytes(
            bytes,
            fn,
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        appNotification.showSuccess(
            title: 'Xuất Excel',
            message: 'Đã lưu vào Tải về/SBOX HRM: $fn');
      }
    } catch (e) {
      appNotification.showError(
          title: 'Lỗi', message: 'Không thể xuất Excel: $e');
    }
  }

  excel_lib.CellValue _excelCellValue(
      String key, Map<String, dynamic> row, int index) {
    switch (key) {
      case 'stt':
        return excel_lib.IntCellValue(index + 1);
      case 'code':
      case 'name':
      case 'department':
      case 'position':
      case 'salaryType':
        return excel_lib.TextCellValue(row[key]?.toString() ?? '');
      case _employeeSignColumnKey:
        return excel_lib.TextCellValue('');
      case 'workDays':
      case 'paidLeaveDays':
      case 'lateCount':
      case 'earlyCount':
      case 'lateMinutes':
      case 'earlyMinutes':
      case 'absentDays':
      case 'standardDays':
        return excel_lib.IntCellValue((row[key] as num?)?.toInt() ?? 0);
      default:
        return excel_lib.DoubleCellValue((row[key] as num?)?.toDouble() ?? 0);
    }
  }

  String _pngPayrollCellText(String key, Map<String, dynamic> row, int index) {
    if (key == 'stt') return '${index + 1}';
    if (key == _employeeSignColumnKey) return '';
    return _formatCellValue(key, row, index);
  }

  List<String> _pngPayrollTotalCells(
    List<Map<String, dynamic>> data,
    List<PayrollColumn> visibleCols,
  ) {
    return visibleCols.map((col) {
      if (col.key == 'stt') return '';
      if (col.key == 'name') return 'TỔNG CỘNG';
      if (col.key == 'code') return '${data.length} NV';
      if (!_isPayrollNumericKey(col.key)) return '';
      final total = data.fold<double>(
          0, (s, r) => s + ((r[col.key] as num?) ?? 0).toDouble());
      if (total == 0) return '';
      if (col.key == 'penalty' ||
          col.key == 'bhxh' ||
          col.key == 'totalInsurance' ||
          col.key == 'pit') {
        return '-${_currencyFmt.format(total.round())}';
      }
      if (col.key == 'totalHours' || col.key == 'otTotalHours') {
        return total.toStringAsFixed(1);
      }
      if (col.key == 'workDays' ||
          col.key == 'standardDays' ||
          col.key == 'lateCount' ||
          col.key == 'earlyCount') {
        return total == total.roundToDouble()
            ? '${total.toInt()}'
            : total.toStringAsFixed(1);
      }
      return _currencyFmt.format(total.round());
    }).toList();
  }

  static const double _pngPad = 12.0;

  void _pngDrawPayrollExport(
    dynamic ctx, {
    required double width,
    required double height,
    required List<Map<String, dynamic>> data,
    required List<PayrollColumn> visibleCols,
    required List<double> colWidths,
    required double tableWidth,
  }) {
    const rowH = 28.0;
    const headerH = 34.0;
    const titleH = 34.0;
    const periodH = 26.0;
    const gap = 10.0;
    const sigBlockH = 88.0;
    const pad = _pngPad;
    const cellFont = '11px Arial, sans-serif';
    const cellFontBold = 'bold 11px Arial, sans-serif';

    final headers = visibleCols.map((c) => c.label).toList();
    final tableLeft = pad;

    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0, 0, width, height);

    var y = pad;
    ctx.fillStyle = '#0F172A';
    ctx.font = 'bold 16px Arial, sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText('BẢNG TỔNG HỢP LƯƠNG', width / 2, y + 20);
    y += titleH;
    ctx.fillStyle = '#334155';
    ctx.font = '12px Arial, sans-serif';
    ctx.fillText(
      'Kỳ lương: ${DateFormat('dd/MM/yyyy').format(_fromDate)} – ${DateFormat('dd/MM/yyyy').format(_toDate)}',
      width / 2,
      y + 16,
    );
    y += periodH + gap;

    final tableTop = y;
    ctx.fillStyle = '#6366F1';
    ctx.fillRect(tableLeft, tableTop, tableWidth, headerH);
    var x = tableLeft;
    for (var c = 0; c < headers.length; c++) {
      ctx.fillStyle = '#FFFFFF';
      ctx.font = cellFontBold;
      ctx.textAlign = 'center';
      ctx.fillText(headers[c], x + colWidths[c] / 2, tableTop + headerH / 2 + 5);
      x += colWidths[c];
    }
    y += headerH;

    for (var ri = 0; ri < data.length; ri++) {
      if (ri.isOdd) {
        ctx.fillStyle = '#F8FAFC';
        ctx.fillRect(tableLeft, y, tableWidth, rowH);
      }
      x = tableLeft;
      for (var c = 0; c < visibleCols.length; c++) {
        final col = visibleCols[c];
        final text = _pngPayrollCellText(col.key, data[ri], ri);
        String fillColor = '#334155';
        if (col.key == 'netSalary') {
          fillColor = '#1D4ED8';
        } else if (col.key == 'totalSalary') {
          fillColor = '#15803D';
        } else if (col.key == 'penalty' ||
            col.key == 'totalInsurance' ||
            col.key == 'pit') {
          final v = (data[ri][col.key] as num?)?.toDouble() ?? 0;
          if (v > 0) fillColor = '#DC2626';
        } else if (col.key == 'bonus') {
          final v = (data[ri][col.key] as num?)?.toDouble() ?? 0;
          if (v > 0) fillColor = '#15803D';
        }
        ctx.fillStyle = fillColor;
        ctx.font = cellFont;
        if (_isPayrollLeftAlignKey(col.key)) {
          ctx.textAlign = 'left';
          ctx.fillText(text, x + 6, y + rowH / 2 + 5);
        } else {
          ctx.textAlign = 'center';
          ctx.fillText(text, x + colWidths[c] / 2, y + rowH / 2 + 5);
        }
        x += colWidths[c];
      }
      ctx.strokeStyle = '#E2E8F0';
      ctx.beginPath();
      ctx.moveTo(tableLeft, y + rowH);
      ctx.lineTo(tableLeft + tableWidth, y + rowH);
      ctx.stroke();
      y += rowH;
    }

    final totalCells = _pngPayrollTotalCells(data, visibleCols);
    ctx.fillStyle = '#EFF6FF';
    ctx.fillRect(tableLeft, y, tableWidth, rowH + 2);
    x = tableLeft;
    for (var c = 0; c < totalCells.length; c++) {
      ctx.fillStyle = '#1D4ED8';
      ctx.font = cellFontBold;
      ctx.textAlign = 'center';
      ctx.fillText(totalCells[c], x + colWidths[c] / 2, y + rowH / 2 + 5);
      x += colWidths[c];
    }
    y += rowH + gap;

    final sigW = tableWidth / _payrollFooterSignatureLabels.length;
    for (var si = 0; si < _payrollFooterSignatureLabels.length; si++) {
      final cx = tableLeft + sigW * si + sigW / 2;
      ctx.fillStyle = '#0F172A';
      ctx.font = cellFontBold;
      ctx.textAlign = 'center';
      ctx.fillText(_payrollFooterSignatureLabels[si], cx, y + 14);
    }
    y += 52;
    for (var si = 0; si < _payrollFooterSignatureLabels.length; si++) {
      final cx = tableLeft + sigW * si + sigW / 2;
      ctx.fillStyle = '#71717A';
      ctx.font = 'italic 10px Arial, sans-serif';
      ctx.fillText('(Ký, ghi rõ họ tên)', cx, y + 12);
    }
    y += sigBlockH - 52;

    ctx.strokeStyle = '#CBD5E1';
    ctx.lineWidth = 1;
    ctx.strokeRect(tableLeft, tableTop, tableWidth, y - tableTop);
    ctx.textAlign = 'left';
  }

  Future<void> exportToPng() async {
    try {
      final data = _buildPayrollData();
      if (data.isEmpty) {
        appNotification.showError(
            title: 'Lỗi', message: 'Không có dữ liệu để xuất');
        return;
      }

      final visibleCols = _visiblePayrollColumns();
      final sampleRows = <List<String>>[];
      for (var i = 0; i < data.length; i++) {
        sampleRows.add(visibleCols
            .map((c) => _pngPayrollCellText(c.key, data[i], i))
            .toList());
      }
      sampleRows.add(_pngPayrollTotalCells(data, visibleCols));

      final rawColWidths = <double>[];
      for (var c = 0; c < visibleCols.length; c++) {
        var w = visibleCols[c].label.length * 8.0 + 20;
        for (final row in sampleRows) {
          if (c < row.length) {
            final cw = row[c].length * 7.0 + 20;
            if (cw > w) w = cw;
          }
        }
        rawColWidths.add(w.clamp(52, _payrollColWidth(visibleCols[c])));
      }
      final naturalTableW = rawColWidths.fold<double>(0, (s, w) => s + w);
      final totalWidth = math.max(1100.0, naturalTableW + 2 * _pngPad);
      final tableWidth = totalWidth - 2 * _pngPad;
      final scale = tableWidth / naturalTableW;
      final colWidths = rawColWidths.map((w) => w * scale).toList();

      const rowH = 28.0;
      const headerH = 34.0;
      const titleH = 34.0;
      const periodH = 26.0;
      const gap = 10.0;
      const sigBlockH = 88.0;
      final totalHeight = _pngPad +
          titleH +
          periodH +
          gap +
          headerH +
          data.length * rowH +
          rowH +
          gap +
          sigBlockH +
          _pngPad +
          16;

      void drawCanvas(dynamic ctx) => _pngDrawPayrollExport(
            ctx,
            width: totalWidth,
            height: totalHeight,
            data: data,
            visibleCols: visibleCols,
            colWidths: colWidths,
            tableWidth: tableWidth,
          );

      final fileName =
          'Bang_tong_hop_luong_${DateFormat('ddMMyyyy').format(_fromDate)}_${DateFormat('ddMMyyyy').format(_toDate)}.png';

      final dataUrl = web_canvas.renderToPngDataUrl(
        width: totalWidth.toInt(),
        height: totalHeight.toInt(),
        draw: drawCanvas,
      );

      if (dataUrl != null) {
        await file_saver.saveAndOpenDataUrl(dataUrl, fileName);
      } else {
        final pngBytes = await web_canvas.renderToPngBytes(
          width: totalWidth.toInt(),
          height: totalHeight.toInt(),
          draw: drawCanvas,
        );
        if (pngBytes != null) {
          await file_saver.saveAndOpenFileBytes(
              pngBytes, fileName, 'image/png');
        } else {
          appNotification.showError(
              title: 'Lỗi', message: 'Không thể xuất PNG');
          return;
        }
      }
      appNotification.showSuccess(
          title: 'Xuất PNG',
          message: 'Đã lưu vào Ảnh/SBOX HRM: $fileName');
    } catch (e) {
      appNotification.showError(title: 'Lỗi', message: 'Không thể xuất PNG: $e');
    }
  }

  // ──────── Date range / period ────────
  void _setPeriod(String period) {
    final now = DateTime.now();
    setState(() {
      _selectedPeriod = period;
      _cachedPayrollData = null;
      _currentPage = 1;
      switch (period) {
        case 'thisMonth':
          _fromDate = DateTime(now.year, now.month, 1);
          _toDate = now;
          break;
        case 'lastMonth':
          final firstThis = DateTime(now.year, now.month, 1);
          final lastDayPrev = firstThis.subtract(const Duration(days: 1));
          _fromDate = DateTime(lastDayPrev.year, lastDayPrev.month, 1);
          _toDate = DateTime(lastDayPrev.year, lastDayPrev.month,
              lastDayPrev.day, 23, 59, 59);
          break;
        case 'thisWeek':
          // Monday of current week
          final weekday = now.weekday; // 1=Mon, 7=Sun
          _fromDate = now.subtract(Duration(days: weekday - 1));
          _fromDate = DateTime(_fromDate.year, _fromDate.month, _fromDate.day);
          _toDate = now;
          break;
        case 'lastWeek':
          final weekday = now.weekday;
          final thisMonday = now.subtract(Duration(days: weekday - 1));
          _fromDate = thisMonday.subtract(const Duration(days: 7));
          _fromDate = DateTime(_fromDate.year, _fromDate.month, _fromDate.day);
          _toDate = thisMonday.subtract(const Duration(days: 1));
          _toDate =
              DateTime(_toDate.year, _toDate.month, _toDate.day, 23, 59, 59);
          break;
        case 'today':
          _fromDate = DateTime(now.year, now.month, now.day);
          _toDate = now;
          break;
        case 'yesterday':
          final yd = now.subtract(const Duration(days: 1));
          _fromDate = DateTime(yd.year, yd.month, yd.day);
          _toDate = DateTime(yd.year, yd.month, yd.day, 23, 59, 59);
          break;
        case 'custom':
          break;
      }
    });
    if (period != 'custom') {
      _loadPayrollData();
    }
  }

  Future<void> _pickSingleDate({required bool isFrom}) async {
    final initial = isFrom ? _fromDate : _toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('vi', 'VN'),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
          if (_fromDate.isAfter(_toDate)) _toDate = _fromDate;
        } else {
          _toDate = picked;
          if (_toDate.isBefore(_fromDate)) _fromDate = _toDate;
        }
        _selectedPeriod = 'custom';
        _cachedPayrollData = null;
        _currentPage = 1;
      });
      _loadPayrollData();
    }
  }

  // ──────── Employee detail dialog ────────
  void _showEmployeeDetail(Map<String, dynamic> row) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    final titleRow = Row(
      children: [
        CircleAvatar(
          backgroundColor: Colors.blue.shade100,
          child: Text(
            (row['name'] as String).isNotEmpty
                ? (row['name'] as String)[0].toUpperCase()
                : '?',
            style: TextStyle(
                color: Colors.blue.shade700, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(row['name'] ?? '', style: const TextStyle(fontSize: 16)),
              Text('${row['code']} • ${row['department']}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ],
    );

    final contentBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailSection('Chấm công', [
          _detailRow('Tổng công', '${row['workDays']}'),
          _detailRow('Công chuẩn', '${row['standardDays']}'),
          _detailRow('Ngày phép', '${row['paidLeaveDays']}'),
          _detailRow('Ngày vắng', '${row['absentDays']} ngày'),
          _detailRow(
              'Tổng giờ', '${(row['totalHours'] as num).toStringAsFixed(1)}h'),
          _detailRow('Giờ chuẩn',
              '${(row['standardHours'] as num).toStringAsFixed(1)}h'),
          _detailRow(
              'Tăng ca', '${(row['otTotalHours'] as num).toStringAsFixed(1)}h'),
          _detailRow('Tăng ca ngày thường',
              '${(row['otHoursWeekday'] as num).toStringAsFixed(1)}h'),
          _detailRow('Tăng ca cuối tuần',
              '${(row['otHoursWeekend'] as num).toStringAsFixed(1)}h'),
          _detailRow('Tăng ca ngày lễ',
              '${(row['otHoursHoliday'] as num).toStringAsFixed(1)}h'),
          _detailRow(
              'Đi trễ', '${row['lateCount']} lần (${row['lateMinutes']} phút)'),
          _detailRow('Về sớm',
              '${row['earlyCount']} lần (${row['earlyMinutes']} phút)'),
        ]),
        _detailSection('Thu nhập', [
          _detailRow('Loại lương', row['salaryType']),
          _detailRow('Lương cơ bản', _fmtCurrency(row['baseSalary'])),
          _detailRow('Lương theo công', _fmtCurrency(row['workSalary'])),
          _detailRow(
              'Lương hoàn thành (mức tháng)', _fmtCurrency(row['completionSalary'])),
          _detailRow('Lương HT theo công',
              _fmtCurrency(row['completionSalaryEarned'])),
          _detailRow('Lương theo ngày', _fmtCurrency(row['dailySalary'])),
          _detailRow('Lương theo ca', _fmtCurrency(row['shiftSalary'])),
          _detailRow('Lương theo giờ', _fmtCurrency(row['hourlySalary'])),
          _detailRow('Lương tăng ca', _fmtCurrency(row['otSalary'])),
          _detailRow('Phụ cấp cố định', _fmtCurrency(row['allowanceFixed'])),
          _detailRow('Phụ cấp theo ngày (mức/ngày)',
              _fmtCurrency(row['allowanceDaily'])),
          _detailRow('Tổng PC kỳ (theo công/giờ)',
              _fmtCurrency(row['totalAllowance']),
              color: Colors.green.shade700),
          _detailRow('Phụ cấp khác', _fmtCurrency(row['otherAllowance'])),
          _detailRow('Thưởng', _fmtCurrency(row['bonus']), color: Colors.green),
        ]),
        _detailSection('Khấu trừ', [
          _detailRow('Phạt giao dịch', _fmtDeduction(row['penalty']),
              color: Colors.red),
          _detailRow('Phạt đi trễ', _fmtDeduction(row['latePenalty']),
              color: Colors.red),
          _detailRow('Mức đóng bảo hiểm', _fmtCurrency(row['insuranceSalary'])),
          _detailRow('BHXH (${(_insuranceSettings['bhxhEmployeeRate'] ?? 8)}%)',
              _fmtDeduction(row['bhxhPart']),
              color: Colors.red),
          _detailRow(
              'BHYT (${(_insuranceSettings['bhytEmployeeRate'] ?? 1.5)}%)',
              _fmtDeduction(row['bhytPart']),
              color: Colors.red),
          _detailRow('BHTN (${(_insuranceSettings['bhtnEmployeeRate'] ?? 1)}%)',
              _fmtDeduction(row['bhtnPart']),
              color: Colors.red),
          _detailRow(
              'Đoàn phí (${(_insuranceSettings['unionFeeEmployeeRate'] ?? 1)}%)',
              _fmtDeduction(row['unionFeePart']),
              color: Colors.red),
          _detailRow('Tổng BHXH NLĐ đóng', _fmtDeduction(row['totalInsurance']),
              color: Colors.red),
          _detailRow('TNCN', _fmtDeduction(row['pit']), color: Colors.red),
          _detailRow('Ứng lương', _fmtCurrency(row['advance'])),
        ]),
        const Divider(thickness: 2),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('THỰC NHẬN',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(_fmtCurrency(row['netSalary']),
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.blue.shade700)),
            ],
          ),
        ),
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
                title: Text(row['name'] ?? 'Chi tiết',
                    overflow: TextOverflow.ellipsis),
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
            width: math
                .min(500, MediaQuery.of(context).size.width - 32)
                .toDouble(),
            child: SingleChildScrollView(child: contentBody),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
          ],
        ),
      );
    }
  }

  Widget _detailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.blue.shade700)),
        ),
        ...children,
        const Divider(),
      ],
    );
  }

  Widget _detailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          Text(value,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }

  String _fmtCurrency(dynamic val) {
    final v = _toDouble(val);
    if (v == 0) return '0';
    return '${_currencyFmt.format(v.round())} đ';
  }

  String _fmtDeduction(dynamic val) {
    final v = _toDouble(val);
    if (v == 0) return '0';
    return '-${_currencyFmt.format(v.round())} đ';
  }

  // ──────── Build ────────
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Đang tính toán lương...',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final payrollData = _buildPayrollData();
    final isMobile = Responsive.isMobile(context);

    final toolbarBlock = <Widget>[
      if (isMobile && widget.mobileLeadingSections != null) ...[
        ...widget.mobileLeadingSections!,
        const SizedBox(height: 12),
      ],
      _buildToolbar(),
      if (_notConfiguredSalaryCount > 0 && !_isEmployeeRole(context))
        ReportSalarySetupBanner(
          notConfiguredCount: _notConfiguredSalaryCount,
          dense: isMobile,
          onOpenSalarySettings: () => NavigationNotifier.goToSalarySettings(),
        ),
      const SizedBox(height: 12),
    ];

    final summaryBlock = isMobile
        ? <Widget>[
            InkWell(
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
            if (_showMobileSummary) ...[
              const SizedBox(height: 8),
              _buildSummaryCards(payrollData),
            ],
          ]
        : <Widget>[_buildSummaryCards(payrollData)];

    Widget emptyPayrollWidget() =>
        _notConfiguredSalaryCount > 0 && !_isEmployeeRole(context)
        ? ReportSalarySetupEmptyState(
            notConfiguredCount: _notConfiguredSalaryCount,
            onOpenSalarySettings: () =>
                NavigationNotifier.goToSalarySettings(),
          )
        : Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.account_balance_wallet_outlined,
                    size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text('Không có dữ liệu lương',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                    'Hãy kiểm tra khoảng thời gian hoặc bộ lọc nhân viên',
                    style: TextStyle(
                        color: Colors.grey.shade400, fontSize: 12)),
              ],
            ),
          );

    if (isMobile) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...toolbarBlock,
            ...summaryBlock,
            const SizedBox(height: 12),
            if (payrollData.isEmpty)
              emptyPayrollWidget()
            else
              RepaintBoundary(
                key: _tableKey,
                child: _buildCompactPayrollList(payrollData),
              ),
            const SizedBox(height: 16),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...toolbarBlock,
          ...summaryBlock,
          const SizedBox(height: 12),
          Expanded(
            child: payrollData.isEmpty
                ? emptyPayrollWidget()
                : RepaintBoundary(
                    key: _tableKey,
                    child: _buildCompactPayrollList(payrollData),
                  ),
          ),
        ],
      ),
    );
  }

  String _periodLabel(String period) {
    switch (period) {
      case 'thisMonth':
        return 'Tháng này';
      case 'lastMonth':
        return 'Tháng trước';
      case 'thisWeek':
        return 'Tuần này';
      case 'lastWeek':
        return 'Tuần trước';
      case 'today':
        return 'Hôm nay';
      case 'yesterday':
        return 'Hôm qua';
      case 'custom':
        return 'Tùy chọn';
      default:
        return period;
    }
  }

  String _payrollFilterSummary() {
    final parts = <String>[
      _periodLabel(_selectedPeriod),
      '${DateFormat('dd/MM/yy').format(_fromDate)} — ${DateFormat('dd/MM/yy').format(_toDate)}',
    ];
    if (_selectedDepartment != null && _selectedDepartment!.isNotEmpty) {
      parts.add(_selectedDepartment!);
    }
    if (_selectedEmployeeIds.isEmpty) {
      parts.add('Tất cả NV (${_payrollEmployeePool().length})');
    } else {
      parts.add('${_selectedEmployeeIds.length} NV đã chọn');
    }
    if (_searchQuery.trim().isNotEmpty) {
      parts.add('Tìm: ${_searchQuery.trim()}');
    }
    return parts.join(' · ');
  }

  void _resetPayrollFilters() {
    _setPeriod('thisMonth');
    _searchController.clear();
    setState(() {
      _selectedDepartment = null;
      _selectedEmployeeIds.clear();
      _searchQuery = '';
      _cachedPayrollData = null;
      _currentPage = 1;
    });
  }

  void _showEmployeeFilterDialog() {
    final pool = _payrollEmployeePool();
    final tempSelected = Set<String>.from(_selectedEmployeeIds);
    String filterQuery = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) {
          final filtered = pool.where((e) {
            if (filterQuery.isEmpty) return true;
            final q = filterQuery.toLowerCase();
            return e.fullName.toLowerCase().contains(q) ||
                e.employeeCode.toLowerCase().contains(q) ||
                (e.department ?? '').toLowerCase().contains(q);
          }).toList();

          return ScrollableAlertDialog(
            title: Row(
              children: [
                const Icon(Icons.people, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                    child:
                        Text('Chọn nhân viên', style: TextStyle(fontSize: 16))),
                TextButton(
                  onPressed: () {
                    setDialogState(() {
                      if (tempSelected.length == pool.length) {
                        tempSelected.clear();
                      } else {
                        tempSelected
                          ..clear()
                          ..addAll(pool.map((e) => e.id));
                      }
                    });
                  },
                  child: Text(
                    tempSelected.length == pool.length
                        ? 'Bỏ chọn tất cả'
                        : 'Chọn tất cả',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: math
                  .min(400, MediaQuery.of(context).size.width - 32)
                  .toDouble(),
              height: 450,
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Tìm nhân viên...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (v) => setDialogState(() => filterQuery = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final emp = filtered[i];
                        final isSelected = tempSelected.contains(emp.id);
                        return CheckboxListTile(
                          dense: true,
                          value: isSelected,
                          onChanged: (v) {
                            setDialogState(() {
                              if (v == true) {
                                tempSelected.add(emp.id);
                              } else {
                                tempSelected.remove(emp.id);
                              }
                            });
                          },
                          title: Text(emp.fullName,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                            '${emp.employeeCode} • ${emp.department ?? ''}',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600),
                          ),
                          secondary: CircleAvatar(
                            radius: 16,
                            backgroundColor: isSelected
                                ? Colors.blue.shade100
                                : Colors.grey.shade200,
                            child: Text(
                              emp.fullName.isNotEmpty
                                  ? emp.fullName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                fontSize: 12,
                                color: isSelected
                                    ? Colors.blue.shade700
                                    : Colors.grey.shade600,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      tempSelected.isEmpty
                          ? 'Hiển thị tất cả nhân viên (${pool.length})'
                          : 'Đã chọn ${tempSelected.length}/${pool.length} nhân viên',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy'),
              ),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _selectedEmployeeIds = tempSelected;
                    _cachedPayrollData = null;
                    _currentPage = 1;
                  });
                  Navigator.pop(ctx);
                },
                child: const Text('Áp dụng'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildToolbar() {
    final isMobile = MediaQuery.of(context).size.width < 768;

    final periodDropdown = PopupMenuButton<String>(
      onSelected: (period) {
        if (period == 'custom') {
          setState(() => _selectedPeriod = 'custom');
        } else {
          _setPeriod(period);
        }
      },
      itemBuilder: (_) => [
        _periodMenuItem('thisMonth', 'Tháng này', Icons.calendar_today),
        _periodMenuItem('lastMonth', 'Tháng trước', Icons.calendar_month),
        _periodMenuItem('thisWeek', 'Tuần này', Icons.view_week),
        _periodMenuItem('lastWeek', 'Tuần trước', Icons.view_week_outlined),
        _periodMenuItem('today', 'Hôm nay', Icons.today),
        _periodMenuItem('yesterday', 'Hôm qua', Icons.event),
        const PopupMenuDivider(),
        _periodMenuItem('custom', 'Tùy chọn khác...', Icons.date_range),
      ],
      child: Container(
        width: isMobile ? double.infinity : null,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE4E4E7)),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today,
                size: 14, color: Theme.of(context).primaryColor),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _periodLabel(_selectedPeriod),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).primaryColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.arrow_drop_down,
                size: 18, color: Theme.of(context).primaryColor),
          ],
        ),
      ),
    );

    Widget _datePill(DateTime date, bool isFrom) => InkWell(
          onTap: () => _pickSingleDate(isFrom: isFrom),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFA),
              border: Border.all(color: const Color(0xFFE4E4E7)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today,
                    size: 13, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                // full format for desktop, compact for mobile
                Text(
                  isMobile
                      ? DateFormat('dd/MM/yy').format(date)
                      : DateFormat('dd/MM/yyyy').format(date),
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        );

    final fromDate = _datePill(_fromDate, true);

    final dateSep =
        Text('—', style: TextStyle(color: Colors.grey.shade400, fontSize: 13));

    final toDate = _datePill(_toDate, false);

    final poolCount = _payrollEmployeePool().length;
    final employeeFilter = InkWell(
      onTap: _showEmployeeFilterDialog,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _selectedEmployeeIds.isNotEmpty
              ? Theme.of(context).primaryColor.withValues(alpha: 0.08)
              : const Color(0xFFFAFAFA),
          border: Border.all(
            color: _selectedEmployeeIds.isNotEmpty
                ? Theme.of(context).primaryColor.withValues(alpha: 0.3)
                : const Color(0xFFE4E4E7),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.people_outline,
                size: 14,
                color: _selectedEmployeeIds.isNotEmpty
                    ? Theme.of(context).primaryColor
                    : Colors.grey.shade600),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _selectedEmployeeIds.isEmpty
                    ? 'Tất cả NV ($poolCount)'
                    : '${_selectedEmployeeIds.length} NV đã chọn',
                style: TextStyle(
                  fontSize: 13,
                  color: _selectedEmployeeIds.isNotEmpty
                      ? Theme.of(context).primaryColor
                      : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_selectedEmployeeIds.isNotEmpty) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: () {
                  setState(() {
                    _selectedEmployeeIds.clear();
                    _cachedPayrollData = null;
                    _currentPage = 1;
                  });
                },
                child: Icon(Icons.close,
                    size: 14, color: Theme.of(context).primaryColor),
              ),
            ],
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down,
                size: 18,
                color: _selectedEmployeeIds.isNotEmpty
                    ? Theme.of(context).primaryColor
                    : Colors.grey.shade500),
          ],
        ),
      ),
    );

    final departmentFilter = Container(
      width: double.infinity,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _selectedDepartment != null
            ? Theme.of(context).primaryColor.withValues(alpha: 0.08)
            : const Color(0xFFFAFAFA),
        border: Border.all(
          color: _selectedDepartment != null
              ? Theme.of(context).primaryColor.withValues(alpha: 0.3)
              : const Color(0xFFE4E4E7),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _availableDepartments().contains(_selectedDepartment)
              ? _selectedDepartment
              : null,
          isExpanded: true,
          isDense: true,
          icon: Icon(Icons.arrow_drop_down,
              size: 18,
              color: _selectedDepartment != null
                  ? Theme.of(context).primaryColor
                  : Colors.grey.shade500),
          hint: Row(
            children: [
              Icon(Icons.business_outlined,
                  size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Phòng ban',
                  style: TextStyle(fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          selectedItemBuilder: (_) => [
            Row(
              children: [
                Icon(Icons.business_outlined,
                    size: 14,
                    color: Theme.of(context).primaryColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Phòng ban',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            ..._availableDepartments().map(
              (d) => Row(
                children: [
                  Icon(Icons.business_outlined,
                      size: 14, color: Theme.of(context).primaryColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      d,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(_l10n.allDepartments,
                  style: const TextStyle(fontSize: 13)),
            ),
            ..._availableDepartments().map(
              (d) => DropdownMenuItem<String?>(
                value: d,
                child: Text(d,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
          onChanged: (v) {
            setState(() {
              _selectedDepartment = v;
              _pruneEmployeeSelectionToPool();
              _cachedPayrollData = null;
              _currentPage = 1;
            });
          },
        ),
      ),
    );

    final searchField = SizedBox(
      height: 36,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Tìm nhanh...',
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          prefixIcon: Icon(Icons.search, size: 16, color: Colors.grey.shade400),
          filled: true,
          fillColor: const Color(0xFFFAFAFA),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Theme.of(context).primaryColor),
          ),
        ),
        style: const TextStyle(fontSize: 13),
        onChanged: (v) {
          _cachedPayrollData = null;
          setState(() {
            _searchQuery = v;
            _currentPage = 1;
          });
        },
      ),
    );

    final recordCount = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${_buildPayrollData().length} NV',
        style: const TextStyle(
            fontSize: 12,
            color: HrmPageChrome.primaryNavy,
            fontWeight: FontWeight.w600),
      ),
    );

    final filterFields = isMobile
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              periodDropdown,
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: fromDate),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: dateSep,
                  ),
                  Expanded(child: toDate),
                ],
              ),
              const SizedBox(height: 8),
              departmentFilter,
              const SizedBox(height: 8),
              employeeFilter,
              const SizedBox(height: 8),
              searchField,
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  periodDropdown,
                  fromDate,
                  dateSep,
                  toDate,
                  SizedBox(width: 200, child: departmentFilter),
                  SizedBox(width: 220, child: employeeFilter),
                  SizedBox(width: 240, child: searchField),
                ],
              ),
            ],
          );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _payrollFiltersExpanded,
          onExpansionChanged: (v) => setState(() => _payrollFiltersExpanded = v),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: const Text(
            'Bộ lọc',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            _payrollFilterSummary(),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              recordCount,
              const SizedBox(width: 4),
              Icon(
                _payrollFiltersExpanded
                    ? Icons.expand_less
                    : Icons.expand_more,
                color: Colors.grey[600],
                size: 22,
              ),
            ],
          ),
          children: [
            filterFields,
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton(
                  onPressed: _resetPayrollFilters,
                  child: const Text('Xóa lọc'),
                ),
                const Spacer(),
                if (_canFinalizePayroll()) _buildFinalizeButton(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _periodMenuItem(
      String value, String label, IconData icon) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon,
              size: 16,
              color: _selectedPeriod == value
                  ? Colors.blue
                  : Colors.grey.shade600),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: _selectedPeriod == value
                    ? FontWeight.bold
                    : FontWeight.normal,
                color: _selectedPeriod == value ? Colors.blue : null,
              )),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(List<Map<String, dynamic>> data) {
    if (data.isEmpty) return const SizedBox.shrink();

    final totalNet = data.fold<double>(
        0, (s, r) => s + ((r['netSalary'] as num?) ?? 0).toDouble());
    final totalWorkSalary = data.fold<double>(
        0, (s, r) => s + ((r['workSalary'] as num?) ?? 0).toDouble());
    final totalAllowance = data.fold<double>(
        0, (s, r) => s + ((r['totalAllowance'] as num?) ?? 0).toDouble());
    final totalBonus = data.fold<double>(
        0, (s, r) => s + ((r['bonus'] as num?) ?? 0).toDouble());
    final totalPenalty = data.fold<double>(
        0,
        (s, r) =>
            s +
            ((r['penalty'] as num?) ?? 0).toDouble() +
            ((r['latePenalty'] as num?) ?? 0).toDouble());
    final totalIns = data.fold<double>(
        0, (s, r) => s + ((r['totalInsurance'] as num?) ?? 0).toDouble());
    final totalAdv = data.fold<double>(
        0, (s, r) => s + ((r['advance'] as num?) ?? 0).toDouble());
    final totalKpiSalary = data.fold<double>(
        0, (s, r) => s + ((r['kpiSalary'] as num?) ?? 0).toDouble());
    final avgWorkDays = data.isEmpty
        ? 0
        : data.fold<int>(
                0, (s, r) => s + ((r['workDays'] as num?) ?? 0).toInt()) ~/
            data.length;

    final isMobile = MediaQuery.of(context).size.width < 768;

    final items = [
      _SummaryItem(
          'Tổng lương theo công',
          _currencyFmt.format(totalWorkSalary.round()),
          HrmPageChrome.primaryNavy,
          Icons.account_balance_wallet_outlined),
      _SummaryItem('Phụ cấp', _currencyFmt.format(totalAllowance.round()),
          const Color(0xFF2D5F8B), Icons.card_giftcard_outlined),
      _SummaryItem('Thưởng', _currencyFmt.format(totalBonus.round()),
          const Color(0xFF8B5CF6), Icons.emoji_events_outlined),
      _SummaryItem('Phạt', _currencyFmt.format(totalPenalty.round()),
          const Color(0xFFEF4444), Icons.gavel_outlined),
      _SummaryItem('Bảo hiểm', _currencyFmt.format(totalIns.round()),
          const Color(0xFFF59E0B), Icons.health_and_safety_outlined),
      _SummaryItem('Ứng lương', _currencyFmt.format(totalAdv.round()),
          HrmPageChrome.primaryNavy, Icons.payments_outlined),
      _SummaryItem('KPI', _currencyFmt.format(totalKpiSalary.round()),
          const Color(0xFFEC4899), Icons.flag_outlined),
      _SummaryItem('Ngày công TB', '$avgWorkDays ngày', const Color(0xFF14B8A6),
          Icons.event_available_outlined),
    ];
    final netItem = _SummaryItem(
        'THỰC NHẬN',
        _currencyFmt.format(totalNet.round()),
        const Color(0xFF22C55E),
        Icons.savings_outlined);

    if (isMobile) {
      // Mobile: 2-column grid + full-width net salary
      return Column(
        children: [
          for (int i = 0; i < items.length; i += 2)
            Padding(
              padding: EdgeInsets.only(bottom: i < items.length - 2 ? 6 : 0),
              child: Row(
                children: [
                  Expanded(child: _mobileSummaryChip(items[i])),
                  const SizedBox(width: 6),
                  Expanded(
                      child: i + 1 < items.length
                          ? _mobileSummaryChip(items[i + 1])
                          : const SizedBox.shrink()),
                ],
              ),
            ),
          const SizedBox(height: 6),
          _mobileSummaryChip(netItem, highlight: true),
        ],
      );
    }

    // Desktop: Net hero card on top + flexible Wrap of summary tiles below.
    // Tiles wrap to 2-3 rows naturally so labels/values are never truncated.
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        // Choose how many tiles per row based on width to keep 3-row max.
        // 8 items → 4 cols (2 rows) >= 1100, 3 cols (3 rows) >= 820, else 2 cols.
        final perRow = w >= 1100 ? 4 : (w >= 820 ? 3 : 2);
        const spacing = 10.0;
        final tileWidth = (w - spacing * (perRow - 1)) / perRow;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _netHeroCard(netItem),
            const SizedBox(height: 10),
            Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final it in items)
                  SizedBox(width: tileWidth, child: _summaryTile(it)),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _netHeroCard(_SummaryItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [item.color.withValues(alpha: 0.95), const Color(0xFF15803D)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: item.color.withValues(alpha: 0.25),
              blurRadius: 16,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(item.icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${item.label} (tổng toàn công ty)',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${item.value} ₫',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryTile(_SummaryItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: item.color.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(item.icon, color: item.color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item.value,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: item.color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileSummaryChip(_SummaryItem item, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: highlight
            ? item.color.withValues(alpha: 0.12)
            : item.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: item.color.withValues(alpha: highlight ? 0.3 : 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: highlight ? 32 : 26,
            height: highlight ? 32 : 26,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: highlight ? 0.18 : 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child:
                Icon(item.icon, color: item.color, size: highlight ? 18 : 14),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label,
                    style: TextStyle(
                        fontSize: 10,
                        color: item.color.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(item.value,
                      style: TextStyle(
                          fontSize: highlight ? 15 : 12,
                          fontWeight: FontWeight.bold,
                          color: item.color)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Fixed/frozen column keys (always shown, pinned left)
  static const _frozenKeys = {'stt', 'name'};

  Widget _buildPagination(
    int totalRows,
    int totalPages, {
    VoidCallback? onOpenFullscreen,
  }) {
    final isMobile = Responsive.isMobile(context);
    if (isMobile) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$totalRows dòng',
                style: const TextStyle(
                    fontSize: 12,
                    color: HrmPageChrome.primaryNavy,
                    fontWeight: FontWeight.w600)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPageNavBtn(
                    Icons.chevron_left,
                    _currentPage > 1,
                    () => setState(() {
                          _currentPage--;
                        })),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('$_currentPage / $totalPages',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                _buildPageNavBtn(
                    Icons.chevron_right,
                    _currentPage < totalPages,
                    () => setState(() {
                          _currentPage++;
                        })),
              ],
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$totalRows dòng',
                style: const TextStyle(
                    fontSize: 12,
                    color: HrmPageChrome.primaryNavy,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 16),
          Text('Hiển thị',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(width: 6),
          PopupMenuButton<int>(
            onSelected: (v) => setState(() {
              _rowsPerPage = v;
              _currentPage = 1;
              _cachedPayrollData = null;
            }),
            offset: const Offset(0, -200),
            itemBuilder: (_) => [10, 20, 50, 100]
                .map((n) => PopupMenuItem(
                      value: n,
                      height: 36,
                      child: Text('$n',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: n == _rowsPerPage
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: n == _rowsPerPage
                                ? Colors.blue
                                : Colors.black87,
                          )),
                    ))
                .toList(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$_rowsPerPage',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black87)),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down,
                      size: 16, color: Colors.grey.shade600),
                ],
              ),
            ),
          ),
          Text(' / trang',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          if (onOpenFullscreen != null) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: 'Xem toàn màn hình',
              child: Material(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  onTap: onOpenFullscreen,
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.fullscreen,
                            size: 18, color: Color(0xFF2563EB)),
                        SizedBox(width: 6),
                        Text(
                          'Toàn màn hình',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          const Spacer(),
          _buildPageNavBtn(
              Icons.first_page,
              _currentPage > 1,
              () => setState(() {
                    _currentPage = 1;
                  })),
          const SizedBox(width: 4),
          _buildPageNavBtn(
              Icons.chevron_left,
              _currentPage > 1,
              () => setState(() {
                    _currentPage--;
                  })),
          const SizedBox(width: 4),
          ..._buildPageNumbers(totalPages),
          const SizedBox(width: 4),
          _buildPageNavBtn(
              Icons.chevron_right,
              _currentPage < totalPages,
              () => setState(() {
                    _currentPage++;
                  })),
          const SizedBox(width: 4),
          _buildPageNavBtn(
              Icons.last_page,
              _currentPage < totalPages,
              () => setState(() {
                    _currentPage = totalPages;
                  })),
        ],
      ),
    );
  }

  List<Widget> _buildPageNumbers(int totalPages) {
    final pages = <int>[];
    if (totalPages <= 7) {
      pages.addAll(List.generate(totalPages, (i) => i + 1));
    } else {
      pages.add(1);
      int start = (_currentPage - 1).clamp(2, totalPages - 4);
      int end = (_currentPage + 1).clamp(4, totalPages - 1);
      if (start > 2) pages.add(-1); // ellipsis
      for (int i = start; i <= end; i++) {
        pages.add(i);
      }
      if (end < totalPages - 1) pages.add(-1); // ellipsis
      pages.add(totalPages);
    }
    return pages.map((p) {
      if (p == -1) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text('...',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
        );
      }
      final isActive = p == _currentPage;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Material(
          color: isActive ? Theme.of(context).primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: isActive
                ? null
                : () => setState(() {
                      _currentPage = p;
                    }),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              alignment: Alignment.center,
              child: Text('$p',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                    color: isActive ? Colors.white : Colors.grey.shade700,
                  )),
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildPageNavBtn(IconData icon, bool enabled, VoidCallback onTap) {
    return Material(
      color: enabled ? const Color(0xFFF1F5F9) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: Icon(icon,
              size: 18,
              color: enabled ? Colors.grey.shade700 : Colors.grey.shade300),
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildTable(
      List<Map<String, dynamic>> data, List<PayrollColumn> visibleCols) {
    final frozenCols =
        visibleCols.where((c) => _frozenKeys.contains(c.key)).toList();
    final scrollableCols =
        visibleCols.where((c) => !_frozenKeys.contains(c.key)).toList();

    const double rowHeight = 44;
    const double headerHeight = 46;
    const double cellPadding = 10;

    double colWidth(PayrollColumn col) {
      switch (col.key) {
        case 'stt':
          return 44;
        case 'code':
          return 110;
        case 'name':
          return 170;
        case 'department':
          return 110;
        case 'salaryType':
          return 90;
        case 'standardDays':
          return 90;
        case 'workDays':
          return 78;
        case 'totalHours':
          return 74;
        case 'otTotalHours':
          return 70;
        default:
          return 118;
      }
    }

    final frozenWidth = frozenCols.fold<double>(0, (s, c) => s + colWidth(c));

    Widget buildCell(
        String key, Map<String, dynamic> row, int index, double width) {
      final isEven = index.isEven;
      return InkWell(
        onTap: () => _showEmployeeDetail(row),
        child: Container(
          width: width,
          height: rowHeight,
          alignment: key == 'name' ||
                  key == 'code' ||
                  key == 'department' ||
                  key == 'salaryType'
              ? Alignment.centerLeft
              : Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: cellPadding),
          decoration: BoxDecoration(
            color: isEven ? Colors.white : const Color(0xFFFAFBFC),
            border: const Border(
                bottom: BorderSide(color: Color(0xFFE4E4E7), width: 0.5)),
          ),
          child: Text(
            _formatCellValue(key, row, index),
            style: TextStyle(
              fontSize: 12,
              fontWeight: key == 'netSalary'
                  ? FontWeight.bold
                  : (key == 'name' ? FontWeight.w600 : FontWeight.normal),
              color: _getCellColor(key, row),
            ),
            maxLines: key == 'name' ? 1 : null,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    }

    Widget buildHeaderCell(PayrollColumn col, double width) {
      final isCurrentSort = _sortColumn == col.key;
      return InkWell(
        onTap: () {
          setState(() {
            if (_sortColumn == col.key) {
              _sortAscending = !_sortAscending;
            } else {
              _sortColumn = col.key;
              _sortAscending = true;
            }
            _cachedPayrollData = null;
          });
        },
        child: Container(
          width: width,
          height: headerHeight,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: cellPadding),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(col.label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        color: Color(0xFF71717A)),
                    overflow: TextOverflow.ellipsis),
              ),
              if (isCurrentSort)
                Icon(
                  _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 12,
                  color: Colors.blue.shade700,
                ),
            ],
          ),
        ),
      );
    }

    return RepaintBoundary(
      key: _tableKey,
      child: Container(
        color: Colors.white,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Row(
              children: [
                // ── Frozen columns (left) ──
                SizedBox(
                  width: frozenWidth,
                  child: Column(
                    children: [
                      // Frozen header
                      Container(
                        color: const Color(0xFFFAFAFA),
                        child: Row(
                          children: frozenCols
                              .map((c) => buildHeaderCell(c, colWidth(c)))
                              .toList(),
                        ),
                      ),
                      // Frozen data rows
                      Expanded(
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context)
                              .copyWith(scrollbars: false),
                          child: ListView.builder(
                            controller: _verticalScrollController,
                            itemCount: data.length,
                            itemExtent: rowHeight,
                            itemBuilder: (_, i) {
                              final row = data[i];
                              return Container(
                                color: i.isEven
                                    ? Colors.white
                                    : const Color(0xFFFAFAFA),
                                child: Row(
                                  children: frozenCols
                                      .map((c) =>
                                          buildCell(c.key, row, i, colWidth(c)))
                                      .toList(),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Divider between frozen and scrollable
                Container(width: 1, color: Colors.grey.shade300),
                // ── Scrollable columns (right) ──
                Expanded(
                  child: Scrollbar(
                    controller: _horizontalScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _horizontalScrollController,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: scrollableCols.fold<double>(
                            0, (s, c) => s + colWidth(c)),
                        child: Column(
                          children: [
                            // Scrollable header
                            Container(
                              color: const Color(0xFFFAFAFA),
                              child: Row(
                                children: scrollableCols
                                    .map((c) => buildHeaderCell(c, colWidth(c)))
                                    .toList(),
                              ),
                            ),
                            // Scrollable data rows (synced with frozen vertical scroll)
                            Expanded(
                              child: _SyncedListView(
                                mainController: _verticalScrollController,
                                itemCount: data.length,
                                itemExtent: rowHeight,
                                itemBuilder: (_, i) {
                                  final row = data[i];
                                  return Container(
                                    color: i.isEven
                                        ? Colors.white
                                        : const Color(0xFFFAFAFA),
                                    child: Row(
                                      children: scrollableCols
                                          .map((c) => buildCell(
                                              c.key, row, i, colWidth(c)))
                                          .toList(),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Color? _getCellColor(String key, Map<String, dynamic> row) {
    switch (key) {
      case 'netSalary':
        final val = (row[key] as num?)?.toDouble() ?? 0;
        return val >= 0 ? Colors.blue.shade700 : Colors.red;
      case 'penalty':
      case 'latePenalty':
      case 'bhxh':
      case 'bhyt':
      case 'bhtn':
      case 'unionFee':
      case 'totalInsurance':
      case 'pit':
        final val = (row[key] as num?)?.toDouble() ?? 0;
        return val > 0 ? Colors.red : null;
      case 'bonus':
        final val = (row[key] as num?)?.toDouble() ?? 0;
        return val > 0 ? Colors.green.shade700 : null;
      case 'advance':
        final val = (row[key] as num?)?.toDouble() ?? 0;
        return val > 0 ? Colors.orange.shade700 : null;
      default:
        return null;
    }
  }

  // ──────── KPI Tier/Penalty calculation helpers ────────
  List<Map<String, dynamic>> _kpiParseTiers(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final list = (jsonDecode(json) as List).cast<Map<String, dynamic>>();
      if (list.isNotEmpty && list.first.containsKey('milestonePercent')) {
        final sorted = list
          ..sort((a, b) => ((a['milestonePercent'] ?? 0) as num)
              .compareTo((b['milestonePercent'] ?? 0) as num));
        final migrated = <Map<String, dynamic>>[];
        for (int i = 0; i < sorted.length; i++) {
          final from = (sorted[i]['milestonePercent'] as num?)?.toDouble() ?? 0;
          final to = i + 1 < sorted.length
              ? (sorted[i + 1]['milestonePercent'] as num?)?.toDouble() ?? -1
              : -1.0;
          migrated.add({
            'fromPct': from,
            'toPct': to,
            'rate': sorted[i]['bonusAmount'] ?? 0,
            'rateType': 0
          });
        }
        return migrated;
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  List<Map<String, dynamic>> _kpiParsePenaltyTiers(String? json) {
    if (json == null || json.isEmpty || json == 'null') return [];
    try {
      return (jsonDecode(json) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  double _kpiCalcPenaltyBonus(Map<String, dynamic> target) {
    final pTiers =
        _kpiParsePenaltyTiers(target['penaltyTiersJson']?.toString());
    if (pTiers.isEmpty) return 0;
    final tgt = ((target['targetValue'] ?? 0) as num).toDouble();
    final act = ((target['actualValue'] ?? 0) as num).toDouble();
    final pct = tgt > 0 ? act / tgt * 100 : 0.0;
    if (pct >= 100) return 0;
    for (final tier in pTiers) {
      final fromPct = ((tier['fromPct'] ?? 0) as num).toDouble();
      final toPct = ((tier['toPct'] ?? 100) as num).toDouble();
      final rate = ((tier['rate'] ?? 0) as num).toDouble();
      if (pct >= fromPct && pct < toPct) return rate;
    }
    return 0;
  }

  List<Map<String, dynamic>> _kpiCalcTierBonuses(Map<String, dynamic> target) {
    final tiers = _kpiParseTiers(target['bonusTiersJson']?.toString());
    final tgt = ((target['targetValue'] ?? 0) as num).toDouble();
    final act = ((target['actualValue'] ?? 0) as num).toDouble();
    final pct = tgt > 0 ? act / tgt * 100 : 0.0;
    final cs = ((target['completionSalary'] ?? 0) as num).toDouble();
    return tiers.map((tier) {
      final fromPct = ((tier['fromPct'] ?? 0) as num).toDouble();
      final toPct = ((tier['toPct'] ?? -1) as num).toDouble();
      final rate = ((tier['rate'] ?? 0) as num).toDouble();
      final rateType = ((tier['rateType'] ?? 0) as num).toInt();
      double bonus = 0;
      if (pct >= 100 && pct > fromPct) {
        if (rateType == 2) {
          bonus = rate;
        } else if (rateType == 3) {
          bonus = cs * rate / 100;
        } else {
          final fromVal = tgt * fromPct / 100;
          final toVal = toPct < 0 ? act : tgt * toPct / 100;
          final inBand = (act < toVal ? act : toVal) - fromVal;
          if (inBand > 0) {
            bonus = rateType == 1 ? inBand * rate / 100 : inBand * rate;
          }
        }
      }
      return {
        'fromPct': fromPct,
        'toPct': toPct,
        'rate': rate,
        'rateType': rateType,
        'bonus': bonus
      };
    }).toList();
  }

  String _formatCellValue(String key, Map<String, dynamic> row, int index) {
    switch (key) {
      case _employeeSignColumnKey:
        return '';
      case 'stt':
        return '${(_currentPage - 1) * _rowsPerPage + index + 1}';
      case 'code':
      case 'name':
      case 'department':
      case 'position':
      case 'salaryType':
        return row[key]?.toString() ?? '';
      case 'workDays':
      case 'paidLeaveDays':
      case 'absentDays':
      case 'lateCount':
      case 'earlyCount':
        return '${(row[key] as num?)?.toInt() ?? 0}';
      case 'standardDays':
        final sd = (row[key] as num?)?.toDouble() ?? 0;
        return sd == sd.roundToDouble()
            ? '${sd.toInt()}'
            : sd.toStringAsFixed(1);
      case 'totalHours':
      case 'standardHours':
      case 'otTotalHours':
      case 'otHoursWeekday':
      case 'otHoursWeekend':
      case 'otHoursHoliday':
        return (row[key] as num?)?.toStringAsFixed(1) ?? '0';
      case 'lateMinutes':
      case 'earlyMinutes':
        return '${(row[key] as num?)?.toInt() ?? 0}';
      case 'penalty':
      case 'bhxh':
      case 'bhyt':
      case 'bhtn':
      case 'unionFee':
      case 'totalInsurance':
      case 'pit':
        final val = (row[key] as num?)?.toDouble() ?? 0;
        if (val == 0) return '0';
        return '-${_currencyFmt.format(val.round())}';
      default:
        final val = (row[key] as num?)?.toDouble() ?? 0;
        if (val == 0) return '0';
        return _currencyFmt.format(val.round());
    }
  }

  Widget _buildPayrollHorizontalClip({
    required double tableMinWidth,
    required Widget child,
    required ScrollController hController,
  }) {
    return HorizontallySyncedClip(
      controller: hController,
      contentWidth: tableMinWidth,
      child: child,
    );
  }

  double _payrollColWidth(PayrollColumn col) {
    switch (col.key) {
      case 'stt':
        return 48;
      case 'code':
        return 96;
      case 'name':
        return 168;
      case 'department':
        return 112;
      case 'salaryType':
        return 88;
      case 'standardDays':
      case 'workDays':
        return 72;
      case 'totalHours':
      case 'otTotalHours':
        return 76;
      case 'workSalary':
      case 'netSalary':
      case 'totalSalary':
        return 124;
      case _employeeSignColumnKey:
        return 96;
      default:
        return 104;
    }
  }

  Map<int, TableColumnWidth> _payrollDesktopColumnWidths(
      List<PayrollColumn> visibleCols) {
    final widths = <int, TableColumnWidth>{};
    for (var i = 0; i < visibleCols.length; i++) {
      widths[i] = FixedColumnWidth(_payrollColWidth(visibleCols[i]));
    }
    return widths;
  }

  double _payrollDesktopTableMinWidth(List<PayrollColumn> visibleCols) {
    return visibleCols.fold<double>(0, (s, c) => s + _payrollColWidth(c));
  }

  bool _isPayrollNumericKey(String key) {
    return !{
      'stt',
      'code',
      'name',
      'department',
      'position',
      'salaryType',
      _employeeSignColumnKey,
    }.contains(key);
  }

  bool _isPayrollLeftAlignKey(String key) {
    return {'name', 'code', 'department', 'salaryType'}.contains(key);
  }

  Widget _payrollTableCell(
    Widget child, {
    Alignment alignment = Alignment.center,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Align(alignment: alignment, child: child),
    );
  }

  Widget _payrollHeaderText(String text) => Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Color(0xFF52525B),
        ),
      );

  TableRow _buildPayrollHeaderRow(List<PayrollColumn> visibleCols) {
    return TableRow(
      decoration: const BoxDecoration(color: Color(0xFFFAFAFA)),
      children: visibleCols
          .map((c) => _payrollTableCell(_payrollHeaderText(c.label)))
          .toList(),
    );
  }

  TableRow _buildPayrollDataRow(
    Map<String, dynamic> row,
    int index,
    List<PayrollColumn> visibleCols, {
    int? absoluteStt,
  }) {
    return TableRow(
      children: visibleCols.map((col) {
        final align = _isPayrollLeftAlignKey(col.key)
            ? Alignment.centerLeft
            : Alignment.center;
        final color = _getCellColor(col.key, row);
        if (col.key == _employeeSignColumnKey) {
          return _payrollTableCell(
            Container(
              height: 28,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE4E4E7)),
                borderRadius: BorderRadius.circular(4),
                color: const Color(0xFFFAFAFA),
              ),
            ),
          );
        }
        final cellText = col.key == 'stt' && absoluteStt != null
            ? '$absoluteStt'
            : _formatCellValue(col.key, row, index);
        return _payrollTableCell(
          Text(
            cellText,
            textAlign:
                _isPayrollLeftAlignKey(col.key) ? TextAlign.left : TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: col.key == 'netSalary' || col.key == 'totalSalary'
                  ? FontWeight.w700
                  : (col.key == 'name' ? FontWeight.w600 : FontWeight.normal),
              color: color ?? const Color(0xFF18181B),
            ),
            maxLines: col.key == 'name' ? 1 : null,
            overflow: TextOverflow.ellipsis,
          ),
          alignment: align,
        );
      }).toList(),
    );
  }

  String _payrollTotalCellText(
    PayrollColumn col,
    List<Map<String, dynamic>> allData,
  ) {
    if (col.key == 'stt' || col.key == _employeeSignColumnKey) return '';
    if (col.key == 'name') return 'TỔNG CỘNG';
    if (col.key == 'code') return '${allData.length} NV';
    if (!_isPayrollNumericKey(col.key)) return '—';

    final total = allData.fold<double>(
        0, (s, r) => s + ((r[col.key] as num?) ?? 0).toDouble());
    if (total == 0) return '—';
    if (col.key == 'workDays' ||
        col.key == 'standardDays' ||
        col.key == 'lateCount' ||
        col.key == 'earlyCount' ||
        col.key == 'lateMinutes' ||
        col.key == 'earlyMinutes' ||
        col.key == 'absentDays') {
      return total == total.roundToDouble()
          ? '${total.toInt()}'
          : total.toStringAsFixed(1);
    }
    if (col.key == 'totalHours' ||
        col.key == 'otTotalHours' ||
        col.key == 'standardHours') {
      return total.toStringAsFixed(1);
    }
    if (col.key == 'penalty' ||
        col.key == 'bhxh' ||
        col.key == 'bhyt' ||
        col.key == 'bhtn' ||
        col.key == 'unionFee' ||
        col.key == 'totalInsurance' ||
        col.key == 'pit') {
      return total == 0 ? '—' : '-${_currencyFmt.format(total.round())}';
    }
    return _currencyFmt.format(total.round());
  }

  TableRow _buildPayrollTotalRow(
    List<Map<String, dynamic>> allData,
    List<PayrollColumn> visibleCols,
  ) {
    return TableRow(
      decoration: const BoxDecoration(color: Color(0xFFEFF6FF)),
      children: visibleCols.map((col) {
        final text = _payrollTotalCellText(col, allData);
        return _payrollTableCell(
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: col.key == 'netSalary'
                  ? Colors.blue.shade800
                  : const Color(0xFF1E40AF),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPayrollDesktopTable({
    required Map<int, TableColumnWidth> columnWidths,
    required List<TableRow> rows,
  }) {
    return Table(
      columnWidths: columnWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(
        horizontalInside: BorderSide(color: Colors.grey.shade200, width: 0.5),
        verticalInside: BorderSide(color: Colors.grey.shade200, width: 0.5),
      ),
      children: rows,
    );
  }

  Widget _buildBottomHorizontalScrollBar(double tableMinWidth) {
    return Container(
      height: 18,
      decoration: const BoxDecoration(
        color: Color(0xFFFAFAFA),
        border: Border(top: BorderSide(color: Color(0xFFE4E4E7))),
      ),
      child: Scrollbar(
        thumbVisibility: true,
        controller: _desktopTableHScrollBody,
        child: SingleChildScrollView(
          controller: _desktopTableHScrollBody,
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: tableMinWidth, height: 1),
        ),
      ),
    );
  }

  void _openPayrollTableFullscreen(
    List<Map<String, dynamic>> allData,
    List<PayrollColumn> visibleCols,
  ) {
    if (allData.isEmpty) return;
    final vBody = ScrollController();
    final headerRow = _buildPayrollHeaderRow(visibleCols);
    final dataRows = allData
        .asMap()
        .entries
        .map((e) => _buildPayrollDataRow(
              e.value,
              e.key,
              visibleCols,
              absoluteStt: e.key + 1,
            ))
        .toList();
    dataRows.add(_buildPayrollTotalRow(allData, visibleCols));

    final hScroll = ScrollController();
    final columnWidths = _payrollDesktopColumnWidths(visibleCols);
    final tableMinWidth = _payrollDesktopTableMinWidth(visibleCols);
    const headerH = 44.0;

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: const Color(0xFFFAFAFA),
          appBar: AppBar(
            title: const Text('Bảng tổng hợp lương',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            leading: IconButton(
              tooltip: 'Thoát chế độ toàn màn hình',
              icon: const Icon(Icons.fullscreen_exit),
              onPressed: () => Navigator.pop(dialogCtx),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.pop(dialogCtx),
                icon: const Icon(Icons.close, size: 18),
                label: const Text('Thoát'),
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: headerH,
                decoration: const BoxDecoration(
                  color: Color(0xFFFAFAFA),
                  border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
                ),
                child: _buildPayrollHorizontalClip(
                  tableMinWidth: tableMinWidth,
                  hController: hScroll,
                  child: _buildPayrollDesktopTable(
                    columnWidths: columnWidths,
                    rows: [headerRow],
                  ),
                ),
              ),
              Expanded(
                child: Scrollbar(
                  thumbVisibility: true,
                  controller: vBody,
                  child: SingleChildScrollView(
                    controller: vBody,
                    primary: false,
                    child: _buildPayrollHorizontalClip(
                      tableMinWidth: tableMinWidth,
                      hController: hScroll,
                      child: _buildPayrollDesktopTable(
                        columnWidths: columnWidths,
                        rows: dataRows,
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                height: 18,
                decoration: const BoxDecoration(
                  color: Color(0xFFFAFAFA),
                  border: Border(top: BorderSide(color: Color(0xFFE4E4E7))),
                ),
                child: Scrollbar(
                  thumbVisibility: true,
                  controller: hScroll,
                  child: SingleChildScrollView(
                    controller: hScroll,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(width: tableMinWidth, height: 1),
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE4E4E7))),
                ),
                child: Text(
                  '${allData.length} nhân viên · Kỳ ${DateFormat('dd/MM/yyyy').format(_fromDate)} – ${DateFormat('dd/MM/yyyy').format(_toDate)}',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      vBody.dispose();
      hScroll.dispose();
    });
  }

  Widget _buildCompactPayrollList(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_chart, size: 56, color: Colors.grey.shade200),
            const SizedBox(height: 12),
            Text('Không có dữ liệu',
                style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    final detailCols = _visiblePayrollColumns()
        .where((c) => !{
              'stt',
              'name',
              'code',
              'department',
              _employeeSignColumnKey,
            }.contains(c.key))
        .toList();

    final totalPages = math.max(1, (data.length / _rowsPerPage).ceil());
    if (_currentPage > totalPages) _currentPage = totalPages;
    if (_currentPage < 1) _currentPage = 1;
    final start = (_currentPage - 1) * _rowsPerPage;
    final end = math.min(start + _rowsPerPage, data.length);
    final paged = data.sublist(start, end);

    Widget buildExpandedDetail(Map<String, dynamic> row, int index) {
      if (detailCols.isEmpty) {
        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _showEmployeeDetail(row),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Xem chi tiết đầy đủ'),
          ),
        );
      }
      final detailRows = detailCols
          .map((col) {
            final value = _formatCellValue(col.key, row, index);
            if (value.isEmpty || value == '—') return null;
            return MapEntry(col, value);
          })
          .whereType<MapEntry<PayrollColumn, String>>()
          .toList();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFAFAFA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE4E4E7)),
            ),
            child: Column(
              children: [
                for (var i = 0; i < detailRows.length; i++) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 11,
                          child: Text(
                            detailRows[i].key.label,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 9,
                          child: Text(
                            detailRows[i].value,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _payrollCellDisplayColor(
                                detailRows[i].key.key,
                                row,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (i < detailRows.length - 1)
                    const Divider(height: 1, color: Color(0xFFE4E4E7)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _showEmployeeDetail(row),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Xem chi tiết đầy đủ'),
            ),
          ),
        ],
      );
    }

    final tiles = paged.asMap().entries.map((entry) {
      final pageIndex = entry.key;
      final row = entry.value;
      final globalIndex = start + pageIndex;
      final code = row['code']?.toString() ?? '';
      final dept = row['department']?.toString() ?? '';
      final subtitle = [
        if (code.isNotEmpty) code,
        if (dept.isNotEmpty) dept,
      ].join(' · ');
      return Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding:
              const EdgeInsets.fromLTRB(16, 0, 16, 12),
          leading: CircleAvatar(
            radius: 16,
            backgroundColor: Colors.blue.shade50,
            child: Text(
              '${globalIndex + 1}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
          ),
          title: Text(
            row['name']?.toString() ?? '',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: subtitle.isEmpty
              ? null
              : Text(subtitle, style: const TextStyle(fontSize: 12)),
          trailing: Text(
            _fmtCurrency(row['netSalary']),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Color(0xFF1D4ED8),
            ),
          ),
          children: [buildExpandedDetail(row, globalIndex)],
        ),
      );
    }).toList();

    final totalNet = data.fold<double>(
      0,
      (sum, row) => sum + _toDouble(row['netSalary']),
    );
    final isMobile = MediaQuery.of(context).size.width < 600;
    final listView = ListView(
      padding: EdgeInsets.zero,
      shrinkWrap: isMobile,
      physics: isMobile
          ? const NeverScrollableScrollPhysics()
          : const AlwaysScrollableScrollPhysics(),
      children: tiles,
    );

    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Bảng lương',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                Text(
                  '${data.length} NV',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE4E4E7)),
          if (isMobile)
            listView
          else
            Expanded(child: listView),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50.withValues(alpha: 0.35),
              border: const Border(
                top: BorderSide(color: Color(0xFFE4E4E7)),
              ),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'TỔNG THỰC NHẬN',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                Text(
                  _fmtCurrency(totalNet),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.blue.shade800,
                  ),
                ),
              ],
            ),
          ),
          _buildPagination(data.length, totalPages),
        ],
      ),
    );
  }

  Widget _buildUnifiedPayrollTable(List<Map<String, dynamic>> data) {
    if (data.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.table_chart, size: 56, color: Colors.grey.shade200),
            const SizedBox(height: 12),
            Text('Không có dữ liệu',
                style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    final visibleCols = _visiblePayrollColumns();
    final totalPages = math.max(1, (data.length / _rowsPerPage).ceil());
    if (_currentPage > totalPages) _currentPage = totalPages;
    if (_currentPage < 1) _currentPage = 1;
    final start = (_currentPage - 1) * _rowsPerPage;
    final end = math.min(start + _rowsPerPage, data.length);
    final paged = data.sublist(start, end);

    final columnWidths = _payrollDesktopColumnWidths(visibleCols);
    final tableMinWidth = _payrollDesktopTableMinWidth(visibleCols);
    const headerH = 44.0;

    final headerRow = _buildPayrollHeaderRow(visibleCols);
    final dataRows = paged
        .asMap()
        .entries
        .map((e) => _buildPayrollDataRow(e.value, e.key, visibleCols))
        .toList();
    dataRows.add(_buildPayrollTotalRow(data, visibleCols));

    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: headerH,
            child: _buildPayrollHorizontalClip(
              tableMinWidth: tableMinWidth,
              hController: _desktopTableHScrollBody,
              child: _buildPayrollDesktopTable(
                columnWidths: columnWidths,
                rows: [headerRow],
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE4E4E7)),
          Expanded(
            child: Scrollbar(
              thumbVisibility: true,
              controller: _desktopTableVScroll,
              child: SingleChildScrollView(
                controller: _desktopTableVScroll,
                primary: false,
                child: _buildPayrollHorizontalClip(
                  tableMinWidth: tableMinWidth,
                  hController: _desktopTableHScrollBody,
                  child: _buildPayrollDesktopTable(
                    columnWidths: columnWidths,
                    rows: dataRows,
                  ),
                ),
              ),
            ),
          ),
          _buildPagination(
            data.length,
            totalPages,
            onOpenFullscreen: () =>
                _openPayrollTableFullscreen(data, visibleCols),
          ),
          _buildBottomHorizontalScrollBar(tableMinWidth),
        ],
      ),
    );
  }

  // ──────── Vertical payroll layout (mobile) ────────
  List<PayrollColumn> _mobileVerticalPayrollColumns() {
    return _visiblePayrollColumns()
        .where((c) => !{
              'stt',
              'name',
              'code',
              'department',
              'position',
              'salaryType',
              _employeeSignColumnKey,
            }.contains(c.key))
        .toList();
  }

  Color _payrollCellDisplayColor(String key, Map<String, dynamic> row) {
    final c = _getCellColor(key, row);
    if (c != null) return c;
    switch (key) {
      case 'netSalary':
        return const Color(0xFF1D4ED8);
      case 'totalSalary':
        return const Color(0xFF15803D);
      case 'totalDeduction':
        return Colors.red.shade700;
      default:
        return const Color(0xFF18181B);
    }
  }

  Widget _buildVerticalPayrollTable(List<Map<String, dynamic>> data) {
    final cols = _mobileVerticalPayrollColumns();
    if (cols.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            'Chưa có cột dữ liệu hiển thị.\nVui lòng bật thêm cột trong cài đặt bảng lương.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF71717A)),
          ),
        ),
      );
    }
    final headers = cols.map((c) => c.label).toList();
    final widths = cols.map((c) => _payrollColWidth(c)).toList();

    final rows = data.asMap().entries.map((entry) {
      final index = entry.key;
      final row = entry.value;
      final code = row['code']?.toString() ?? '';
      final dept = row['department']?.toString() ?? '';
      return MobilePayrollVerticalRow(
        employeeName: row['name']?.toString() ?? '',
        employeeSubtitle: '$code${dept.isNotEmpty ? ' · $dept' : ''}',
        cells: cols
            .map((c) => _formatCellValue(c.key, row, index))
            .toList(),
        cellColors:
            cols.map((c) => _payrollCellDisplayColor(c.key, row)).toList(),
        onTap: () => _showEmployeeDetail(row),
      );
    }).toList();

    final totalRow = rows.isEmpty
        ? null
        : MobilePayrollVerticalRow(
            employeeName: 'TỔNG CỘNG',
            employeeSubtitle: '${data.length} NV',
            cells: cols.map((c) => _payrollTotalCellText(c, data)).toList(),
            cellColors: cols.map((c) {
              final text = _payrollTotalCellText(c, data);
              if (text.isEmpty || text == '—') return null;
              if (c.key == 'netSalary') return Colors.blue.shade800;
              if (c.key == 'totalSalary') return const Color(0xFF15803D);
              if (c.key == 'totalDeduction') return Colors.red.shade700;
              return const Color(0xFF1E40AF);
            }).toList(),
          );

    return MobilePayrollVerticalTable(
      title: 'Tổng hợp lương',
      headers: headers,
      columnWidths: widths,
      rows: rows,
      totalRow: totalRow,
    );
  }
}

class _SummaryItem {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _SummaryItem(this.label, this.value, this.color, this.icon);
}

/// A ListView that follows the scroll position of a main ScrollController.
class _SyncedListView extends StatefulWidget {
  final ScrollController mainController;
  final int itemCount;
  final double itemExtent;
  final IndexedWidgetBuilder itemBuilder;

  const _SyncedListView({
    required this.mainController,
    required this.itemCount,
    required this.itemExtent,
    required this.itemBuilder,
  });

  @override
  State<_SyncedListView> createState() => _SyncedListViewState();
}

class _SyncedListViewState extends State<_SyncedListView> {
  late final ScrollController _followerController;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _followerController = ScrollController();
    widget.mainController.addListener(_onMainScroll);
    _followerController.addListener(_onFollowerScroll);
  }

  void _onMainScroll() {
    if (_isSyncing) return;
    _isSyncing = true;
    if (_followerController.hasClients && widget.mainController.hasClients) {
      _followerController.jumpTo(widget.mainController.offset);
    }
    _isSyncing = false;
  }

  void _onFollowerScroll() {
    if (_isSyncing) return;
    _isSyncing = true;
    if (widget.mainController.hasClients && _followerController.hasClients) {
      widget.mainController.jumpTo(_followerController.offset);
    }
    _isSyncing = false;
  }

  @override
  void dispose() {
    widget.mainController.removeListener(_onMainScroll);
    _followerController.removeListener(_onFollowerScroll);
    _followerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView.builder(
        controller: _followerController,
        itemCount: widget.itemCount,
        itemExtent: widget.itemExtent,
        itemBuilder: widget.itemBuilder,
      ),
    );
  }
}
