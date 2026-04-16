import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import '../../utils/file_saver.dart' as file_saver;

import 'package:excel/excel.dart' as excel_lib;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/attendance.dart';
import '../../models/device.dart';
import '../../models/employee.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../utils/responsive_helper.dart';
import '../../l10n/app_localizations.dart';

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

  const PayrollSummaryTab({
    super.key,
    required this.attendances,
    required this.devices,
    required this.fromDate,
    required this.toDate,
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
  // ignore: unused_field
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

  // Attendance loaded for selected period (independent of widget.attendances)
  List<Attendance> _periodAttendances = [];

  // ═══ State ═══
  bool _isLoading = true;
  bool _showMobileFilters = false;
  bool _showMobileSummary = false;
  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();
  String _searchQuery = '';
  String _selectedPeriod = 'thisMonth';
  String _sortColumn = 'code';
  bool _sortAscending = true;
  Set<String> _selectedEmployeeIds = {}; // empty = all employees

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_columnsInitialized) {
      _columnsInitialized = true;
      _initColumns();
    }
  }

  void _initColumns() {
    _columns = [
      PayrollColumn(key: 'stt', label: 'STT'),
      PayrollColumn(key: 'name', label: _l10n.employeeName),
      PayrollColumn(key: 'code', label: _l10n.employeeCode),
      PayrollColumn(key: 'department', label: _l10n.department),
      PayrollColumn(key: 'salaryType', label: _l10n.salaryType),
      PayrollColumn(key: 'standardDays', label: _l10n.standardWorkDays),
      PayrollColumn(key: 'workDays', label: _l10n.totalWorkDays),
      PayrollColumn(key: 'totalHours', label: _l10n.totalHours),
      PayrollColumn(key: 'otTotalHours', label: _l10n.overtime),
      PayrollColumn(key: 'baseSalary', label: _l10n.baseSalary),
      PayrollColumn(key: 'completionSalary', label: _l10n.completionSalary),
      PayrollColumn(key: 'dailySalary', label: _l10n.dailySalary),
      PayrollColumn(key: 'shiftSalary', label: _l10n.shiftSalary),
      PayrollColumn(key: 'hourlySalary', label: _l10n.hourSalary),
      PayrollColumn(key: 'otSalary', label: _l10n.overtimeSalary),
      PayrollColumn(key: 'totalAllowance', label: _l10n.allowance),
      PayrollColumn(key: 'bonus', label: _l10n.bonusAmount),
      PayrollColumn(key: 'penalty', label: _l10n.penaltyAmount),
      PayrollColumn(key: 'kpiSalary', label: _l10n.kpiSalary),
      PayrollColumn(key: 'productionAmount', label: 'Sản lượng'),
      PayrollColumn(key: 'bhxh', label: 'BHXH'),
      PayrollColumn(key: 'pit', label: 'TNCN'),
      PayrollColumn(key: 'totalSalary', label: _l10n.totalSalary),
      PayrollColumn(key: 'advance', label: _l10n.advancePaid),
      PayrollColumn(key: 'netSalary', label: _l10n.netSalary),
    ];
    _loadColumnPreferences();
  }

  Future<void> _loadColumnPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('payroll_columns_v8');
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
      final list = _columns.map((c) => {'key': c.key, 'visible': c.visible}).toList();
      await prefs.setString('payroll_columns_v8', jsonEncode(list));
    } catch (_) {}
  }

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  // ──────── Data loading ────────
  Future<void> _loadPayrollData() async {
    setState(() => _isLoading = true);
    _cachedPayrollData = null;
    try {
      // Load employees
      final empList = await _apiService.getEmployees();
      _employees = empList
          .map((e) => Employee.fromJson(e as Map<String, dynamic>))
          .toList();

      // Load salary profiles in batch (single API call)
      _employeeSalaryProfiles = [];
      final allProfiles = await _apiService.getEmployeeSalaryProfiles();
      final profileMap = <String, dynamic>{};
      for (final p in allProfiles) {
        if (p is Map<String, dynamic>) {
          final eid = p['employeeId']?.toString() ?? '';
          if (eid.isNotEmpty) profileMap[eid] = p;
        }
      }
      for (final emp in _employees) {
        _employeeSalaryProfiles.add({
          'employeeId': emp.id,
          'employeeCode': emp.employeeCode,
          'profile': profileMap[emp.id],
        });
      }

      // Load settings in parallel
      final results = await Future.wait([
        _apiService.getInsuranceSettings(),
        _apiService.getSalarySettings(),
        _apiService.getPenaltySettings(),
        _apiService.getTransactions(fromDate: _fromDate, toDate: _toDate),
        _apiService.getAdvanceRequests(fromDate: _fromDate, toDate: _toDate),
        _apiService.getShifts(),
        _apiService.getAllowanceSettings(),
        _apiService.getHolidaySettings(_fromDate.year),
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

      // Load tax settings & shift salary levels & employee tax deductions (optional, may fail)
      try {
        _taxSettings = await _apiService.getTaxSettings();
      } catch (_) {
        _taxSettings = {};
      }
      try {
        final levels = await _apiService.getShiftSalaryLevels();
        if (levels['data'] != null && levels['data'] is List) {
          _shiftSalaryLevels = (levels['data'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      } catch (_) {
        _shiftSalaryLevels = [];
      }
      try {
        final deductions = await _apiService.getEmployeeTaxDeductions();
        _employeeTaxDeductions = deductions
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      } catch (_) {
        _employeeTaxDeductions = [];
      }
      // Load KPI targets, KPI salaries & commission settings
      try {
        _commissionSettings = await _apiService.getCommissionSettings();
        final periodsRes = await _apiService.getKpiPeriods();
        if (periodsRes['isSuccess'] == true) {
          final periods = List<Map<String, dynamic>>.from(periodsRes['data'] ?? []);
          String? matchPeriodId;
          for (final p in periods) {
            final pStart = DateTime.tryParse(p['periodStart']?.toString() ?? '');
            final pEnd = DateTime.tryParse(p['periodEnd']?.toString() ?? '');
            if (pStart != null && pEnd != null &&
                !_fromDate.isAfter(pEnd) && !_toDate.isBefore(pStart)) {
              matchPeriodId = p['id']?.toString();
              break;
            }
          }
          if (matchPeriodId != null) {
            final targetsRes = await _apiService.getKpiEmployeeTargets(periodId: matchPeriodId);
            if (targetsRes['isSuccess'] == true) {
              _kpiEmployeeTargets = List<Map<String, dynamic>>.from(targetsRes['data'] ?? []);
            }

          }
        }
      } catch (_) {
        _kpiEmployeeTargets = [];
        _commissionSettings = {};
      }

      // Load production summaries for payroll
      try {
        final prodRes = await _apiService.getProductionSummary(
          fromDate: _fromDate,
          toDate: _toDate,
        );
        if (prodRes['isSuccess'] == true) {
          _productionSummaries = List<Map<String, dynamic>>.from(prodRes['data'] ?? []);
        }
      } catch (_) {
        _productionSummaries = [];
      }

      // Load attendances for the selected date range (not relying on widget.attendances)
      try {
        final deviceIds = widget.devices.map((d) => d.id).toList();
        if (deviceIds.isNotEmpty) {
          final result = await _apiService.getAttendances(
            deviceIds: deviceIds,
            fromDate: _fromDate,
            toDate: _toDate,
            page: 1,
            pageSize: 500,
          );
          _periodAttendances = (result['items'] as List?)
              ?.map((item) => Attendance.fromJson(item as Map<String, dynamic>))
              .toList() ?? [];
        } else {
          _periodAttendances = widget.attendances;
        }
      } catch (_) {
        _periodAttendances = widget.attendances;
      }
    } catch (e) {
      debugPrint('Error loading payroll data: $e');
    }
    if (mounted) setState(() => _isLoading = false);
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

  // ──────── Helper: check if a date is holiday ────────
  bool _isHoliday(DateTime date) {
    for (final h in _holidays) {
      final hDate = h['date'] != null ? DateTime.tryParse(h['date'].toString()) : null;
      if (hDate == null) continue;
      final isRecurring = h['isRecurring'] == true;
      final dateMatch = isRecurring
          ? hDate.month == date.month && hDate.day == date.day
          : hDate.year == date.year && hDate.month == date.month && hDate.day == date.day;
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
        for (var d = monthStart; !d.isAfter(monthEnd); d = d.add(const Duration(days: 1))) {
          if (d.weekday == DateTime.sunday) offDays++;
        }
        break;
      case 'saturday':
        for (var d = monthStart; !d.isAfter(monthEnd); d = d.add(const Duration(days: 1))) {
          if (d.weekday == DateTime.saturday) offDays++;
        }
        break;
      case 'sat-sun':
        for (var d = monthStart; !d.isAfter(monthEnd); d = d.add(const Duration(days: 1))) {
          if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) offDays++;
        }
        break;
      case 'sat-afternoon-sun':
        for (var d = monthStart; !d.isAfter(monthEnd); d = d.add(const Duration(days: 1))) {
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
        for (var d = monthStart; !d.isAfter(monthEnd); d = d.add(const Duration(days: 1))) {
          if ((paidDayOff.contains('Sunday') && d.weekday == DateTime.sunday) ||
              (paidDayOff.contains('Saturday') && d.weekday == DateTime.saturday)) {
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
      final emp2 = _employees
          .where((e) => e.employeeCode == att.employeeId)
          .firstOrNull;
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
  double _getInsuranceSalaryRaw(
      String socialInsType, double baseSalary, double completionSalary, double customInsuranceSalary) {
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
          case 1: return _toDouble(_insuranceSettings['minSalaryRegion1'], 4960000);
          case 2: return _toDouble(_insuranceSettings['minSalaryRegion2'], 4410000);
          case 3: return _toDouble(_insuranceSettings['minSalaryRegion3'], 3860000);
          case 4: return _toDouble(_insuranceSettings['minSalaryRegion4'], 3450000);
          default: return _toDouble(_insuranceSettings['minSalaryRegion1'], 4960000);
        }
      case '4':
        return customInsuranceSalary;
      default:
        return 0;
    }
  }

  double _calculateInsuranceSalary(
      String socialInsType, double baseSalary, double completionSalary, double customInsuranceSalary) {
    final maxIns = _toDouble(_insuranceSettings['maxInsuranceSalary'], 46800000);
    final raw = _getInsuranceSalaryRaw(socialInsType, baseSalary, completionSalary, customInsuranceSalary);
    // Áp dụng mức trần BHXH (20x lương cơ sở)
    return raw > maxIns ? maxIns : raw;
  }

  /// BHTN cap = 20 × regional minimum salary (different from BHXH cap)
  double _calculateBhtnInsuranceSalary(
      String socialInsType, double baseSalary, double completionSalary, double customInsuranceSalary) {
    final raw = _getInsuranceSalaryRaw(socialInsType, baseSalary, completionSalary, customInsuranceSalary);
    if (raw == 0) return 0;
    // BHTN cap = 20 × lương tối thiểu vùng (theo luật Việc làm 2013)
    final region = _toInt(_insuranceSettings['defaultRegion'], 1);
    double regionMin;
    switch (region) {
      case 1: regionMin = _toDouble(_insuranceSettings['minSalaryRegion1'], 4960000); break;
      case 2: regionMin = _toDouble(_insuranceSettings['minSalaryRegion2'], 4410000); break;
      case 3: regionMin = _toDouble(_insuranceSettings['minSalaryRegion3'], 3860000); break;
      case 4: regionMin = _toDouble(_insuranceSettings['minSalaryRegion4'], 3450000); break;
      default: regionMin = _toDouble(_insuranceSettings['minSalaryRegion1'], 4960000);
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

  /// Parse SalaryRateType: backend sends string enum ("Hourly","Monthly","Daily","Shift") or int
  static int _parseRateType(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) {
      switch (v) {
        case 'Hourly': return 0;
        case 'Monthly': return 1;
        case 'Daily': return 2;
        case 'Shift': return 3;
        default: return int.tryParse(v) ?? 1;
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
          .where((e) => e['employeeId'] == emp.id || e['employeeCode'] == emp.employeeCode)
          .firstOrNull;
      profile = sp?['profile'] as Map<String, dynamic>?;
    }

    final benefit = profile?['benefit'] as Map<String, dynamic>?;
    final double baseSalary = _toDouble(benefit?['rate']);
    final int rateType = _parseRateType(benefit?['rateType']);
    final double completionSalary = _toDouble(benefit?['completionSalary']);
    final double mealAllowancePerDay = _toDouble(benefit?['mealAllowance']);
    final double responsibilityAllowance = _toDouble(benefit?['responsibilityAllowance']);
    final int shiftsPerDay = _toInt(benefit?['shiftsPerDay'], 1);
    final String socialInsType = (benefit?['socialInsuranceType'] ?? 0).toString();
    final double customInsuranceSalary = _toDouble(benefit?['insuranceSalary']);
    final bool hasHealthInsurance = benefit?['hasHealthInsurance'] == true;

    // Overtime settings
    final int holidayOtType = _toInt(benefit?['holidayOvertimeType'], 1);
    final double holidayOtDailyRate = _toDouble(benefit?['holidayOvertimeDailyRate']);
    final int hourlyOtType = _toInt(benefit?['hourlyOvertimeType'], 1);
    final double hourlyOtFixedRate = _toDouble(benefit?['hourlyOvertimeFixedRate']);

    // Shift salary
    final int shiftSalaryType = _toInt(benefit?['shiftSalaryType']);
    final double fixedShiftRate = _toDouble(benefit?['fixedShiftRate']);

    // Paid leave settings
    final String paidDayOff = benefit?['weeklyOffDays']?.toString() ?? 'Sunday';
    final String paidLeaveType = benefit?['paidLeaveType']?.toString() ?? 'sunday';

    // Standard work days - calculate dynamically based on paidLeaveType and month
    final double standardWorkDays = _calcStandardWorkDays(paidLeaveType, paidDayOff);

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
    final double standardDayHours = _toDouble(benefit?['standardHoursPerDay'], 8.0);

    // Salary type label
    String salaryTypeLabel;
    switch (rateType) {
      case 0: salaryTypeLabel = _l10n.hourly; break;
      case 1: salaryTypeLabel = _l10n.monthly; break;
      case 2: salaryTypeLabel = _l10n.daily; break;
      case 3: salaryTypeLabel = 'Ca'; break;
      default: salaryTypeLabel = _l10n.monthly;
    }

    // ═══ Calculate attendance stats ═══
    final attendanceByDate = <String, List<Attendance>>{};
    for (final att in empAttendances) {
      final key = DateFormat('yyyy-MM-dd').format(att.attendanceTime);
      attendanceByDate.putIfAbsent(key, () => []).add(att);
    }

    double totalWorkHours = 0;
    double standardHours = 0;
    double otHoursWeekday = 0;
    double otHoursWeekend = 0;
    double otHoursHoliday = 0;
    int workDays = 0;
    int lateCount = 0;
    int lateMinutes = 0;
    int earlyCount = 0;
    int earlyMinutes = 0;
    int paidLeaveDays = 0;
    int absentDays = 0;
    int totalShifts = 0;

    for (final entry in attendanceByDate.entries) {
      final dayAtts = entry.value
        ..sort((a, b) => a.attendanceTime.compareTo(b.attendanceTime));
      if (dayAtts.isEmpty) continue;

      final date = dayAtts.first.attendanceTime;
      final isHol = _isHoliday(date);
      final isWkend = _isWeekend(date);

      // Try attendanceState-based IN/OUT first
      var checkIns = dayAtts.where((a) => a.attendanceState == 0).toList();
      var checkOuts = dayAtts.where((a) => a.attendanceState == 1).toList();

      // Fallback: if device doesn't distinguish IN/OUT (all same state),
      // use chronological: first punch = IN, last punch = OUT
      if ((checkIns.isEmpty || checkOuts.isEmpty) && dayAtts.length >= 2) {
        checkIns = [dayAtts.first];
        checkOuts = [dayAtts.last];
      } else if (checkIns.isEmpty && checkOuts.isEmpty && dayAtts.length == 1) {
        checkIns = [dayAtts.first];
        checkOuts = [];
      }

      if (checkIns.isEmpty && checkOuts.isEmpty) continue;

      double dayHours = 0;
      if (checkIns.isNotEmpty && checkOuts.isNotEmpty) {
        final firstIn = checkIns.first.attendanceTime;
        final lastOut = checkOuts.last.attendanceTime;
        final rawHours = lastOut.difference(firstIn).inMinutes / 60.0;
        dayHours = rawHours > 5 ? rawHours - 1.0 : rawHours;
        if (dayHours < 0) dayHours = 0;
      } else if (checkIns.isNotEmpty) {
        dayHours = standardDayHours;
      } else if (checkOuts.isNotEmpty) {
        dayHours = standardDayHours;
      }

      totalWorkHours += dayHours;

      if (isHol) {
        otHoursHoliday += dayHours;
      } else if (isWkend) {
        otHoursWeekend += dayHours;
      } else {
        workDays++;
        if (dayHours <= standardDayHours) {
          standardHours += dayHours;
        } else {
          standardHours += standardDayHours;
          otHoursWeekday += dayHours - standardDayHours;
        }
      }

      if (checkIns.isNotEmpty) {
        totalShifts += shiftsPerDay;
      }

      // Late/early detection using scheduled times from Benefit
      if (checkIns.isNotEmpty && !isWkend && !isHol) {
        final firstIn = checkIns.first.attendanceTime;
        final scheduledIn = DateTime(firstIn.year, firstIn.month, firstIn.day, scheduledInHour, scheduledInMin);
        if (firstIn.isAfter(scheduledIn.add(const Duration(minutes: 5)))) {
          lateCount++;
          lateMinutes += firstIn.difference(scheduledIn).inMinutes;
        }
      }
      if (checkOuts.isNotEmpty && !isWkend && !isHol) {
        final lastOut = checkOuts.last.attendanceTime;
        final scheduledOut = DateTime(lastOut.year, lastOut.month, lastOut.day, scheduledOutHour, scheduledOutMin);
        if (lastOut.isBefore(scheduledOut.subtract(const Duration(minutes: 5)))) {
          earlyCount++;
          earlyMinutes += scheduledOut.difference(lastOut).inMinutes;
        }
      }
    }

    // Count paid leave and absent days
    for (var d = _fromDate; !d.isAfter(_toDate); d = d.add(const Duration(days: 1))) {
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
          isPaidOff = d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
          break;
        case 'sat-afternoon-sun':
          isPaidOff = d.weekday == DateTime.sunday;
          // Saturday afternoon is counted as 0.5 in standardWorkDays calculation
          break;
        case 'off-1':
        case 'off-2':
        case 'off-3':
        case 'off-4':
          isPaidOff = false; // off-X days are flat deductions from standardWorkDays, not per-day
          break;
        default:
          // Fallback: use weeklyOffDays
          isPaidOff = (paidDayOff.contains('Sunday') && d.weekday == DateTime.sunday) ||
              (paidDayOff.contains('Saturday') && d.weekday == DateTime.saturday);
      }

      if (isPaidOff) {
        paidLeaveDays++;
      } else if (!attendanceByDate.containsKey(key) && d.isBefore(DateTime.now())) {
        absentDays++;
      }
    }

    // ═══ Salary calculation ═══
    double workSalary = 0;
    double hourlyRate = 0;

    switch (rateType) {
      case 0: // Hourly
        hourlyRate = baseSalary;
        workSalary = baseSalary * standardHours;
        break;
      case 1: // Monthly
        hourlyRate = standardWorkDays > 0 ? baseSalary / standardWorkDays / standardDayHours : 0;
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
          workSalary = fixedShiftRate * totalShifts;
          hourlyRate = fixedShiftRate / standardDayHours;
        } else {
          double levelRate = fixedShiftRate;
          for (final level in _shiftSalaryLevels) {
            // Filter by employee if EmployeeIds specified
            final levelEmpIds = level['employeeIds']?.toString();
            if (levelEmpIds != null && levelEmpIds.isNotEmpty && emp != null) {
              try {
                final ids = jsonDecode(levelEmpIds) as List;
                if (!ids.contains(emp.id)) continue;
              } catch (_) {}
            }
            final minShifts = _toInt(level['minShifts']);
            final maxShifts = _toInt(level['maxShifts'], 99999);
            final rate = _toDouble(level['rate'], fixedShiftRate);
            if (totalShifts >= minShifts && totalShifts <= maxShifts) {
              levelRate = rate;
              break;
            }
          }
          workSalary = levelRate * totalShifts;
          hourlyRate = levelRate / standardDayHours;
        }
        break;
    }

    // Completion salary (monthly only)
    double completionSalaryAmount = 0;
    if (rateType == 1 && completionSalary > 0 && standardWorkDays > 0) {
      completionSalaryAmount = (completionSalary / standardWorkDays) * workDays;
    }

    // ═══ OT salary ═══
    double otSalary = 0;
    if (hourlyOtType == 0) {
      otSalary = (otHoursWeekday + otHoursWeekend + otHoursHoliday) * hourlyOtFixedRate;
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
    // Per-day allowances × actual work days
    final double totalAllowance = (mealAllowancePerDay + responsibilityAllowance) * workDays;

    // ═══ Bonuses & penalties from transactions ═══
    double bonusTotal = 0;
    double penaltyTotal = 0;
    final empId = emp?.id;
    for (final tx in _transactions) {
      // Match by employeeId or employeeUserId (backward compatibility)
      final txEmpId = tx['employeeId']?.toString();
      final txEmpUserId = tx['employeeUserId']?.toString();
      if (txEmpId != empId && txEmpUserId != empId &&
          txEmpId != empCode && txEmpUserId != empCode) {
        continue;
      }
      final txType = tx['type']?.toString().toLowerCase() ?? '';
      final amount = _toDouble(tx['amount']);
      final status = tx['status']?.toString().toLowerCase() ?? '';
      if (status == 'rejected' || status == 'cancelled') continue;
      // Only count unpaid transactions (paymentMethod is null/empty)
      final txPaymentMethod = tx['paymentMethod']?.toString() ?? '';
      final isUnpaid = txPaymentMethod.isEmpty;
      if (!isUnpaid) continue;
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
    final double earlyL15 = _toDouble(_penaltySettings['earlyLeaveDeduction15Min']);
    final double earlyL30 = _toDouble(_penaltySettings['earlyLeaveDeduction30Min']);
    final double earlyL60 = _toDouble(_penaltySettings['earlyLeaveDeduction60Min']);
    final double unauthorizedLeavePenalty = _toDouble(_penaltySettings['unauthorizedLeaveDeduction']);

    // Fallback to generic rates
    final double penaltyPerLate = _toDouble(_penaltySettings['lateDeduction'], late15);
    final double penaltyPerEarly = _toDouble(_penaltySettings['earlyLeaveDeduction'], earlyL15);
    final double penaltyPerAbsent = _toDouble(_penaltySettings['absentDeduction'], unauthorizedLeavePenalty);

    if (late15 > 0 || late30 > 0 || late60 > 0) {
      // Tiered late penalty (approximate: use average late minutes per incident)
      for (final entry in attendanceByDate.entries) {
        final dayAtts = entry.value;
        final date = dayAtts.first.attendanceTime;
        if (_isHoliday(date) || _isWeekend(date)) continue;
        final checkIns = dayAtts.where((a) => a.attendanceState == 0).toList();
        if (checkIns.isEmpty) continue;
        final firstIn = checkIns.first.attendanceTime;
        final scheduledIn = DateTime(firstIn.year, firstIn.month, firstIn.day, scheduledInHour, scheduledInMin);
        final lateMins = firstIn.difference(scheduledIn).inMinutes;
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
      // Tiered early leave penalty
      for (final entry in attendanceByDate.entries) {
        final dayAtts = entry.value;
        final date = dayAtts.first.attendanceTime;
        if (_isHoliday(date) || _isWeekend(date)) continue;
        final checkOuts = dayAtts.where((a) => a.attendanceState == 1).toList();
        if (checkOuts.isEmpty) continue;
        final lastOut = checkOuts.last.attendanceTime;
        final scheduledOut = DateTime(lastOut.year, lastOut.month, lastOut.day, scheduledOutHour, scheduledOutMin);
        final earlyMins = scheduledOut.difference(lastOut).inMinutes;
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
      latePenaltyTotal = (penaltyPerLate * lateCount) +
          (penaltyPerEarly * earlyCount);
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
    final double bhytPart = hasHealthInsurance ? 0 : insuranceSalary * bhytRate / 100;
    final double bhtnPart = bhtnInsuranceSalary * bhtnRate / 100;
    final double unionFeePart = insuranceSalary * unionFeeRate / 100;
    final double totalInsurance = bhxhPart + bhytPart + bhtnPart + unionFeePart;

    // ═══ Tax (PIT – Vietnamese progressive) ═══
    final double grossIncome = workSalary + completionSalaryAmount + otSalary + totalAllowance + bonusTotal;
    final double taxableIncome = grossIncome - totalInsurance;
    double pit = 0;
    final double personalDeduction = _toDouble(_taxSettings['personalDeduction'], 11000000);
    final double dependentDeduction = _toDouble(_taxSettings['dependentDeduction'], 4400000);

    // Get dependents from employee tax deductions
    int dependents = 0;
    if (emp != null) {
      final empTaxDed = _employeeTaxDeductions
          .where((d) => d['employeeId']?.toString() == emp.id ||
              d['employeeUserId']?.toString() == emp.id)
          .firstOrNull;
      if (empTaxDed != null) {
        dependents = _toInt(empTaxDed['numberOfDependents']);
      }
    }

    final double taxable = taxableIncome - personalDeduction - (dependentDeduction * dependents);
    if (taxable > 0) {
      pit = _calculatePIT(taxable);
    }

    // ═══ Advance (filter by PaidDate within period) ═══
    double advanceTotal = 0;
    for (final req in _advanceRequests) {
      final reqEmpId = req['employeeId']?.toString() ??
          req['employeeUserId']?.toString();
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
    final kpiTarget = _kpiEmployeeTargets.cast<Map<String, dynamic>?>().firstWhere(
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
      final totalTierBonus = tierBonuses.fold<double>(0, (s, b) => s + _toDouble(b['bonus']));
      kpiSalaryAmount = salaryHT + penaltyBonus + totalTierBonus;
    }

    // ═══ Sales & Commission ═══
    double salesAmount = 0;
    double commissionAmount = 0;
    final empTarget = _kpiEmployeeTargets.cast<Map<String, dynamic>?>().firstWhere(
      (t) => t?['employeeId']?.toString() == emp?.id && t?['criteriaType'] == 0,
      orElse: () => null,
    );
    if (empTarget != null) {
      salesAmount = _toDouble(empTarget['actualValue']);
      commissionAmount = _calculateCommission(salesAmount);
    }

    // ═══ Production / Piece-rate salary ═══
    double productionAmount = 0;
    final prodSummary = _productionSummaries.cast<Map<String, dynamic>?>().firstWhere(
      (s) => s?['employeeId']?.toString() == emp?.id ||
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
        completionSalaryAmount +
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
    final double otTotalHours = otHoursWeekday + otHoursWeekend + otHoursHoliday;

    return {
      'code': empCode,
      'name': empName,
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
      'completionSalary': completionSalaryAmount,
      'dailySalary': dailySalary,
      'shiftSalary': shiftSalary,
      'hourlySalary': hourlySalary,
      'workSalary': workSalary,
      'otSalary': otSalary,
      'mealAllowance': mealAllowancePerDay,
      'responsibilityAllowance': responsibilityAllowance,
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

    // Group attendance by resolved employee code
    final attendances = _periodAttendances.isNotEmpty ? _periodAttendances : widget.attendances;
    final grouped = <String, List<Attendance>>{};
    for (final att in attendances) {
      final code = _resolveAttEmployeeCode(att);
      if (code == '-') continue;
      grouped.putIfAbsent(code, () => []).add(att);
    }

    // Also add employees with salary profiles but no attendance
    for (final emp in _employees) {
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

  // ──────── Public methods (called from PayrollScreen AppBar) ────────

  void showColumnSelectorDialog() {
    // Work on a temporary copy of columns so we can reorder without affecting state until apply
    var tempColumns = _columns.map((c) => PayrollColumn(
      key: c.key, label: c.label, defaultVisible: c.defaultVisible, visible: c.visible,
    )).toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) {
          // Exclude frozen columns from reordering
          final reorderableCols = tempColumns.where((c) => !_frozenKeys.contains(c.key)).toList();

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.view_column, color: Colors.blue),
                const SizedBox(width: 8),
                const Expanded(child: Text('Chọn & sắp xếp cột', style: TextStyle(fontSize: 16))),
                TextButton(
                  onPressed: () {
                    setDialogState(() {
                      // Reset to defaults
                      tempColumns = _columns.map((c) {
                        final orig = _columns.firstWhere((o) => o.key == c.key);
                        return PayrollColumn(
                          key: orig.key, label: orig.label,
                          defaultVisible: orig.defaultVisible, visible: orig.defaultVisible,
                        );
                      }).toList();
                      _initColumns();
                      tempColumns = _columns.map((c) => PayrollColumn(
                        key: c.key, label: c.label,
                        defaultVisible: c.defaultVisible, visible: c.defaultVisible,
                      )).toList();
                    });
                  },
                  child: const Text('Mặc định', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            content: SizedBox(
              width: math.min(460, MediaQuery.of(context).size.width - 32).toDouble(),
              height: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Frozen columns (not reorderable)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 4),
                    child: Text('Cột cố định (không thể di chuyển)',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ),
                  ...tempColumns.where((c) => _frozenKeys.contains(c.key)).map((col) =>
                    Container(
                      margin: const EdgeInsets.only(bottom: 2),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline, size: 14, color: Colors.grey.shade400),
                          const SizedBox(width: 8),
                          Expanded(child: Text(col.label, style: const TextStyle(fontSize: 13, color: Colors.grey))),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4, left: 4),
                    child: Text('Kéo để sắp xếp thứ tự cột',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ),
                  // Reorderable columns
                  Expanded(
                    child: ReorderableListView.builder(
                      itemCount: reorderableCols.length,
                      onReorder: (oldIndex, newIndex) {
                        setDialogState(() {
                          if (newIndex > oldIndex) newIndex--;
                          // Find in tempColumns (skip frozen ones)
                          final nonFrozen = tempColumns.where((c) => !_frozenKeys.contains(c.key)).toList();
                          final item = nonFrozen.removeAt(oldIndex);
                          nonFrozen.insert(newIndex, item);
                          // Rebuild tempColumns: frozen first, then reordered non-frozen
                          final frozen = tempColumns.where((c) => _frozenKeys.contains(c.key)).toList();
                          tempColumns = [...frozen, ...nonFrozen];
                        });
                      },
                      itemBuilder: (_, i) {
                        final col = reorderableCols[i];
                        return Container(
                          key: ValueKey(col.key),
                          margin: const EdgeInsets.only(bottom: 2),
                          decoration: BoxDecoration(
                            color: col.visible ? Colors.blue.shade50 : Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: col.visible ? Colors.blue.shade200 : Colors.grey.shade200,
                              width: 0.5,
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.only(left: 8, right: 0),
                            leading: Checkbox(
                              value: col.visible,
                              onChanged: (v) => setDialogState(() => col.visible = v ?? true),
                              visualDensity: VisualDensity.compact,
                            ),
                            title: Text(col.label, style: const TextStyle(fontSize: 13)),
                            trailing: ReorderableDragStartListener(
                              index: i,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Icon(Icons.drag_handle, size: 18, color: Colors.grey.shade400),
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
                    final orig = _columns.firstWhere((c) => c.key == t.key, orElse: () => t);
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

  void exportToExcel() async {
    try {
      final data = _buildPayrollData();
      if (data.isEmpty) {
        appNotification.showError(
            title: 'Lỗi', message: 'Không có dữ liệu để xuất');
        return;
      }

      final wb = excel_lib.Excel.createExcel();
      final sheet = wb['Tổng hợp lương'];

      // Title
      sheet.appendRow([excel_lib.TextCellValue('BẢNG TỔNG HỢP LƯƠNG')]);

      // Period
      final period =
          'Kỳ lương: ${DateFormat('dd/MM/yyyy').format(_fromDate)} - ${DateFormat('dd/MM/yyyy').format(_toDate)}';
      sheet.appendRow([excel_lib.TextCellValue(period)]);
      sheet.appendRow([
        excel_lib.TextCellValue(
            'Xuất lúc: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}')
      ]);
      sheet.appendRow([]);

      // Headers – visible columns only
      final visibleCols = _columns.where((c) => c.visible).toList();
      sheet.appendRow(
          visibleCols.map((c) => excel_lib.TextCellValue(c.label)).toList());

      // Data rows
      for (int i = 0; i < data.length; i++) {
        final row = data[i];
        final cells = <excel_lib.CellValue>[];
        for (final col in visibleCols) {
          cells.add(_excelCellValue(col.key, row, i));
        }
        sheet.appendRow(cells);
      }

      // Summary
      sheet.appendRow([]);
      final totalNet = data.fold<double>(
          0, (s, r) => s + ((r['netSalary'] as num?) ?? 0).toDouble());
      final totalBase = data.fold<double>(
          0, (s, r) => s + ((r['baseSalary'] as num?) ?? 0).toDouble());
      final totalWork = data.fold<double>(
          0, (s, r) => s + ((r['workSalary'] as num?) ?? 0).toDouble());
      final totalIns = data.fold<double>(
          0, (s, r) => s + ((r['totalInsurance'] as num?) ?? 0).toDouble());

      sheet.appendRow([
        excel_lib.TextCellValue('TỔNG CỘNG'),
        excel_lib.TextCellValue(''),
        excel_lib.TextCellValue('${data.length} nhân viên'),
        excel_lib.TextCellValue('Lương cơ bản: ${_currencyFmt.format(totalBase.round())}'),
        excel_lib.TextCellValue('Tổng lương: ${_currencyFmt.format(totalWork.round())}'),
        excel_lib.TextCellValue('Tổng bảo hiểm: ${_currencyFmt.format(totalIns.round())}'),
        excel_lib.TextCellValue('Thực nhận: ${_currencyFmt.format(totalNet.round())}'),
      ]);

      wb.delete('Sheet1');
      final bytes = wb.encode();
      if (bytes != null) {
        await file_saver.saveFileBytes(bytes,
            'tong_hop_luong_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx',
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        appNotification.showSuccess(
            title: 'Thành công',
            message: 'Đã xuất Excel (${data.length} nhân viên)');
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
        return excel_lib.DoubleCellValue(
            (row[key] as num?)?.toDouble() ?? 0);
    }
  }

  Future<void> exportToPng() async {
    try {
      final boundary = _tableKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        appNotification.showError(
            title: 'Lỗi', message: 'Không thể chụp bảng');
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      await file_saver.saveFileBytes(bytes,
          'tong_hop_luong_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.png',
          'image/png');
      appNotification.showSuccess(
          title: 'Thành công', message: 'Đã xuất file PNG');
    } catch (e) {
      appNotification.showError(
          title: 'Lỗi', message: 'Không thể xuất PNG: $e');
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
          final lastMonth = DateTime(now.year, now.month - 1, 1);
          _fromDate = lastMonth;
          _toDate = DateTime(now.year, now.month, 0);
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
          _toDate = DateTime(_toDate.year, _toDate.month, _toDate.day, 23, 59, 59);
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
          _detailRow('Tổng giờ', '${(row['totalHours'] as num).toStringAsFixed(1)}h'),
          _detailRow('Giờ chuẩn', '${(row['standardHours'] as num).toStringAsFixed(1)}h'),
          _detailRow('Tăng ca', '${(row['otTotalHours'] as num).toStringAsFixed(1)}h'),
          _detailRow('Tăng ca ngày thường', '${(row['otHoursWeekday'] as num).toStringAsFixed(1)}h'),
          _detailRow('Tăng ca cuối tuần', '${(row['otHoursWeekend'] as num).toStringAsFixed(1)}h'),
          _detailRow('Tăng ca ngày lễ', '${(row['otHoursHoliday'] as num).toStringAsFixed(1)}h'),
          _detailRow('Đi trễ', '${row['lateCount']} lần (${row['lateMinutes']} phút)'),
          _detailRow('Về sớm', '${row['earlyCount']} lần (${row['earlyMinutes']} phút)'),
        ]),
        _detailSection('Thu nhập', [
          _detailRow('Loại lương', row['salaryType']),
          _detailRow('Lương cơ bản', _fmtCurrency(row['baseSalary'])),
          _detailRow('Lương hoàn thành', _fmtCurrency(row['completionSalary'])),
          _detailRow('Lương theo ngày', _fmtCurrency(row['dailySalary'])),
          _detailRow('Lương theo ca', _fmtCurrency(row['shiftSalary'])),
          _detailRow('Lương theo giờ', _fmtCurrency(row['hourlySalary'])),
          _detailRow('Lương tăng ca', _fmtCurrency(row['otSalary'])),
          _detailRow('Phụ cấp ăn trưa', _fmtCurrency(row['mealAllowance'])),
          _detailRow('Phụ cấp trách nhiệm', _fmtCurrency(row['responsibilityAllowance'])),
          _detailRow('Phụ cấp khác', _fmtCurrency(row['otherAllowance'])),
          _detailRow('Thưởng', _fmtCurrency(row['bonus']),
              color: Colors.green),
        ]),
        _detailSection('Khấu trừ', [
          _detailRow('Phạt giao dịch', _fmtDeduction(row['penalty']),
              color: Colors.red),
          _detailRow('Phạt đi trễ', _fmtDeduction(row['latePenalty']),
              color: Colors.red),
          _detailRow('Mức đóng bảo hiểm', _fmtCurrency(row['insuranceSalary'])),
          _detailRow('BHXH (${(_insuranceSettings['bhxhEmployeeRate'] ?? 8)}%)',
              _fmtDeduction(row['bhxhPart']), color: Colors.red),
          _detailRow('BHYT (${(_insuranceSettings['bhytEmployeeRate'] ?? 1.5)}%)',
              _fmtDeduction(row['bhytPart']), color: Colors.red),
          _detailRow('BHTN (${(_insuranceSettings['bhtnEmployeeRate'] ?? 1)}%)',
              _fmtDeduction(row['bhtnPart']), color: Colors.red),
          _detailRow('Đoàn phí (${(_insuranceSettings['unionFeeEmployeeRate'] ?? 1)}%)',
              _fmtDeduction(row['unionFeePart']), color: Colors.red),
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
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
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
                title: Text(row['name'] ?? 'Chi tiết', overflow: TextOverflow.ellipsis),
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
        builder: (ctx) => AlertDialog(
          title: titleRow,
          content: SizedBox(
            width: math.min(500, MediaQuery.of(context).size.width - 32).toDouble(),
            child: SingleChildScrollView(child: contentBody),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Đóng')),
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
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          Text(value,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: color)),
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
            Text('Đang tính toán lương...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    final payrollData = _buildPayrollData();
    // Auto-hide columns where all rows have no data (0 or empty)
    const alwaysShow = {'stt', 'name', 'code', 'netSalary'};
    final visibleCols = _columns.where((c) {
      if (!c.visible) return false;
      if (alwaysShow.contains(c.key)) return true;
      if (payrollData.isEmpty) return true;
      for (final row in payrollData) {
        final v = row[c.key];
        if (v == null) continue;
        if (v is num && v != 0) return true;
        if (v is String && v.isNotEmpty) return true;
      }
      return false;
    }).toList();

    // Pagination
    final isMobile = Responsive.isMobile(context);
    final totalRows = payrollData.length;
    final totalPages = (totalRows / _rowsPerPage).ceil().clamp(1, 999999);
    if (_currentPage > totalPages) _currentPage = totalPages;
    final startIdx = isMobile ? 0 : (_currentPage - 1) * _rowsPerPage;
    final endIdx = isMobile ? totalRows : (startIdx + _rowsPerPage).clamp(0, totalRows);
    final pagedData = payrollData.sublist(startIdx, endIdx);

    return Padding(
      padding: EdgeInsets.all(Responsive.isMobile(context) ? 10 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildToolbar(),
          const SizedBox(height: 12),
          if (Responsive.isMobile(context)) ...[
            InkWell(
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
            if (_showMobileSummary) ...[
              const SizedBox(height: 8),
              _buildSummaryCards(payrollData),
            ],
          ] else ...[
            _buildSummaryCards(payrollData),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: payrollData.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.account_balance_wallet_outlined,
                            size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text('Không có dữ liệu lương',
                            style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
                        const SizedBox(height: 4),
                        Text('Hãy kiểm tra khoảng thời gian đã chọn',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                      ],
                    ),
                  )
                : Responsive.isMobile(context)
                    ? ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemCount: pagedData.length,
                        itemBuilder: (_, index) {
                            final row = pagedData[index];
                            final name = row['name']?.toString() ?? '';
                            final code = row['code']?.toString() ?? '';
                            final netSalary = ((row['netSalary'] as num?) ?? 0).round();
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
                                  onTap: () => _showEmployeeDetail(row),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    child: Row(children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                                        child: Text(name.isNotEmpty ? name[0] : '?', style: const TextStyle(color: Color(0xFF1E3A5F), fontWeight: FontWeight.bold, fontSize: 14)),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                          Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                                          const SizedBox(height: 2),
                                          Text([code, '${(row['workDays'] as num?)?.toInt() ?? 0} ngày'].join(' · '),
                                            style: const TextStyle(color: Color(0xFF71717A), fontSize: 12)),
                                        ]),
                                      ),
                                      Text(_currencyFmt.format(netSalary), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: netSalary >= 0 ? Colors.green.shade700 : Colors.red)),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.chevron_right, size: 18, color: Color(0xFFA1A1AA)),
                                    ]),
                                  ),
                                ),
                              ),
                            );
                          },
                        )
                    : Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _buildTable(pagedData, visibleCols, startIndex: startIdx),
                    ),
                  ),
          ),
          if (payrollData.isNotEmpty && !isMobile) ...[const SizedBox(height: 12), _buildPagination(totalRows, totalPages)],
        ],
      ),
    );
  }

  String _periodLabel(String period) {
    switch (period) {
      case 'thisMonth': return 'Tháng này';
      case 'lastMonth': return 'Tháng trước';
      case 'thisWeek': return 'Tuần này';
      case 'lastWeek': return 'Tuần trước';
      case 'today': return 'Hôm nay';
      case 'yesterday': return 'Hôm qua';
      case 'custom': return 'Tùy chọn';
      default: return period;
    }
  }

  void _showEmployeeFilterDialog() {
    final tempSelected = Set<String>.from(_selectedEmployeeIds);
    String filterQuery = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) {
          final filtered = _employees.where((e) {
            if (filterQuery.isEmpty) return true;
            final q = filterQuery.toLowerCase();
            return e.fullName.toLowerCase().contains(q) ||
                e.employeeCode.toLowerCase().contains(q) ||
                (e.department ?? '').toLowerCase().contains(q);
          }).toList();

          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.people, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                const Expanded(child: Text('Chọn nhân viên', style: TextStyle(fontSize: 16))),
                TextButton(
                  onPressed: () => setDialogState(() => tempSelected.clear()),
                  child: const Text('Bỏ chọn tất cả', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            content: SizedBox(
              width: math.min(400, MediaQuery.of(context).size.width - 32).toDouble(),
              height: 450,
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Tìm nhân viên...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
                          title: Text(emp.fullName, style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                            '${emp.employeeCode} • ${emp.department ?? ''}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          ),
                          secondary: CircleAvatar(
                            radius: 16,
                            backgroundColor: isSelected ? Colors.blue.shade100 : Colors.grey.shade200,
                            child: Text(
                              emp.fullName.isNotEmpty ? emp.fullName[0].toUpperCase() : '?',
                              style: TextStyle(
                                fontSize: 12,
                                color: isSelected ? Colors.blue.shade700 : Colors.grey.shade600,
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
                          ? 'Hiển thị tất cả nhân viên'
                          : 'Đã chọn ${tempSelected.length} nhân viên',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE4E4E7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today, size: 14, color: Theme.of(context).primaryColor),
            const SizedBox(width: 6),
            Text(
              _periodLabel(_selectedPeriod),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).primaryColor),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 18, color: Theme.of(context).primaryColor),
          ],
        ),
      ),
    );

    final fromDate = InkWell(
      onTap: () => _pickSingleDate(isFrom: true),
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
            Icon(Icons.calendar_today, size: 13, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(DateFormat('dd/MM/yyyy').format(_fromDate), style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );

    final dateSep = Text('—', style: TextStyle(color: Colors.grey.shade400, fontSize: 13));

    final toDate = InkWell(
      onTap: () => _pickSingleDate(isFrom: false),
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
            Icon(Icons.calendar_today, size: 13, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(DateFormat('dd/MM/yyyy').format(_toDate), style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );

    final employeeFilter = InkWell(
      onTap: _showEmployeeFilterDialog,
      borderRadius: BorderRadius.circular(8),
      child: Container(
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 14,
                color: _selectedEmployeeIds.isNotEmpty
                    ? Theme.of(context).primaryColor
                    : Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(
              _selectedEmployeeIds.isEmpty
                  ? 'Tất cả NV'
                  : '${_selectedEmployeeIds.length} NV',
              style: TextStyle(
                fontSize: 13,
                color: _selectedEmployeeIds.isNotEmpty
                    ? Theme.of(context).primaryColor
                    : null,
              ),
            ),
            if (_selectedEmployeeIds.isNotEmpty) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: () {
                  setState(() {
                    _selectedEmployeeIds.clear();
                    _cachedPayrollData = null;
                  });
                },
                child: Icon(Icons.close, size: 14, color: Theme.of(context).primaryColor),
              ),
            ],
          ],
        ),
      ),
    );

    final searchField = SizedBox(
      height: 36,
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Tìm nhanh...',
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          prefixIcon: Icon(Icons.search, size: 16, color: Colors.grey.shade400),
          filled: true,
          fillColor: const Color(0xFFFAFAFA),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
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
          setState(() { _searchQuery = v; _currentPage = 1; });
        },
      ),
    );

    final recordCount = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${_buildPayrollData().length} NV',
        style: const TextStyle(fontSize: 12, color: Color(0xFF1E3A5F), fontWeight: FontWeight.w600),
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: isMobile
          ? Column(
              children: [
                Row(
                  children: [
                    Expanded(child: searchField),
                    const SizedBox(width: 8),
                    recordCount,
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => setState(() => _showMobileFilters = !_showMobileFilters),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 36,
                        width: 36,
                        decoration: BoxDecoration(
                          color: _showMobileFilters ? Theme.of(context).primaryColor.withValues(alpha: 0.1) : const Color(0xFFFAFAFA),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _showMobileFilters ? Theme.of(context).primaryColor.withValues(alpha: 0.3) : const Color(0xFFE4E4E7)),
                        ),
                        child: Stack(
                          children: [
                            Center(child: Icon(_showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined, size: 18, color: _showMobileFilters ? Theme.of(context).primaryColor : Colors.grey.shade600)),
                            if (_selectedPeriod != 'thisMonth' || _selectedEmployeeIds.isNotEmpty)
                              Positioned(top: 4, right: 4, child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle))),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (_showMobileFilters) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Flexible(child: periodDropdown),
                      const SizedBox(width: 6),
                      Expanded(child: fromDate),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: dateSep,
                      ),
                      Expanded(child: toDate),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      employeeFilter,
                    ],
                  ),
                ],
              ],
            )
          : Row(
              children: [
                periodDropdown,
                const SizedBox(width: 12),
                fromDate,
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: dateSep,
                ),
                toDate,
                const SizedBox(width: 12),
                employeeFilter,
                const SizedBox(width: 12),
                Expanded(child: searchField),
                const SizedBox(width: 12),
                recordCount,
              ],
            ),
    );
  }

  PopupMenuItem<String> _periodMenuItem(String value, String label, IconData icon) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 16,
              color: _selectedPeriod == value ? Colors.blue : Colors.grey.shade600),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(
            fontSize: 13,
            fontWeight: _selectedPeriod == value ? FontWeight.bold : FontWeight.normal,
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
    final totalBase = data.fold<double>(
        0, (s, r) => s + ((r['baseSalary'] as num?) ?? 0).toDouble());
    final totalAllowance = data.fold<double>(
        0, (s, r) => s + ((r['totalAllowance'] as num?) ?? 0).toDouble());
    final totalBonus = data.fold<double>(
        0, (s, r) => s + ((r['bonus'] as num?) ?? 0).toDouble());
    final totalPenalty = data.fold<double>(
        0, (s, r) => s + ((r['penalty'] as num?) ?? 0).toDouble() + ((r['latePenalty'] as num?) ?? 0).toDouble());
    final totalIns = data.fold<double>(
        0, (s, r) => s + ((r['totalInsurance'] as num?) ?? 0).toDouble());
    final totalAdv = data.fold<double>(
        0, (s, r) => s + ((r['advance'] as num?) ?? 0).toDouble());
    final totalKpiSalary = data.fold<double>(
        0, (s, r) => s + ((r['kpiSalary'] as num?) ?? 0).toDouble());
    final avgWorkDays = data.isEmpty
        ? 0
        : data.fold<int>(0, (s, r) => s + ((r['workDays'] as num?) ?? 0).toInt()) ~/ data.length;

    final isMobile = MediaQuery.of(context).size.width < 768;

    final items = [
      _SummaryItem('Tổng lương CB', _currencyFmt.format(totalBase.round()), const Color(0xFF1E3A5F)),
      _SummaryItem('Phụ cấp', _currencyFmt.format(totalAllowance.round()), const Color(0xFF2D5F8B)),
      _SummaryItem('Thưởng', _currencyFmt.format(totalBonus.round()), const Color(0xFF1E3A5F)),
      _SummaryItem('Phạt', _currencyFmt.format(totalPenalty.round()), const Color(0xFFEF4444)),
      _SummaryItem('Bảo hiểm', _currencyFmt.format(totalIns.round()), const Color(0xFFF59E0B)),
      _SummaryItem('Ứng lương', _currencyFmt.format(totalAdv.round()), const Color(0xFF0F2340)),
      _SummaryItem('KPI', _currencyFmt.format(totalKpiSalary.round()), const Color(0xFFEC4899)),
      _SummaryItem('Ngày công TB', '$avgWorkDays ngày', const Color(0xFF1E3A5F)),
    ];
    final netItem = _SummaryItem('THỰC NHẬN', _currencyFmt.format(totalNet.round()), const Color(0xFF22C55E));

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
                  Expanded(child: i + 1 < items.length ? _mobileSummaryChip(items[i + 1]) : const SizedBox.shrink()),
                ],
              ),
            ),
          const SizedBox(height: 6),
          _mobileSummaryChip(netItem, highlight: true),
        ],
      );
    }

    // Desktop: single row with Expanded chips
    return Row(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          Expanded(child: _miniChip(items[i].label, items[i].value, items[i].color)),
          if (i < items.length - 1) const SizedBox(width: 8),
        ],
        const SizedBox(width: 8),
        Expanded(child: _miniChip(netItem.label, netItem.value, netItem.color)),
      ],
    );
  }

  Widget _mobileSummaryChip(_SummaryItem item, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: highlight ? item.color.withValues(alpha: 0.12) : item.color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: item.color.withValues(alpha: highlight ? 0.3 : 0.12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label, style: TextStyle(fontSize: 10, color: item.color.withValues(alpha: 0.7), fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(item.value, style: TextStyle(fontSize: highlight ? 14 : 12, fontWeight: FontWeight.bold, color: item.color)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 4),
          Flexible(child: Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  // Fixed/frozen column keys (always shown, pinned left)
  static const _frozenKeys = {'stt', 'name'};

  Widget _buildPagination(int totalRows, int totalPages) {
    final isMobile = Responsive.isMobile(context);
    if (isMobile) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$totalRows dòng', style: const TextStyle(fontSize: 12, color: Color(0xFF1E3A5F), fontWeight: FontWeight.w600)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPageNavBtn(Icons.chevron_left, _currentPage > 1, () => setState(() { _currentPage--; })),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text('$_currentPage / $totalPages', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                _buildPageNavBtn(Icons.chevron_right, _currentPage < totalPages, () => setState(() { _currentPage++; })),
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
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$totalRows dòng', style: const TextStyle(fontSize: 12, color: Color(0xFF1E3A5F), fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 16),
          Text('Hiển thị', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(width: 6),
          PopupMenuButton<int>(
            onSelected: (v) => setState(() { _rowsPerPage = v; _currentPage = 1; _cachedPayrollData = null; }),
            offset: const Offset(0, -200),
            itemBuilder: (_) => [10, 20, 50, 100].map((n) => PopupMenuItem(
              value: n,
              height: 36,
              child: Text('$n', style: TextStyle(
                fontSize: 12,
                fontWeight: n == _rowsPerPage ? FontWeight.bold : FontWeight.normal,
                color: n == _rowsPerPage ? Colors.blue : Colors.black87,
              )),
            )).toList(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$_rowsPerPage', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey.shade600),
                ],
              ),
            ),
          ),
          Text(' / trang', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const Spacer(),
          _buildPageNavBtn(Icons.first_page, _currentPage > 1, () => setState(() { _currentPage = 1; })),
          const SizedBox(width: 4),
          _buildPageNavBtn(Icons.chevron_left, _currentPage > 1, () => setState(() { _currentPage--; })),
          const SizedBox(width: 4),
          ..._buildPageNumbers(totalPages),
          const SizedBox(width: 4),
          _buildPageNavBtn(Icons.chevron_right, _currentPage < totalPages, () => setState(() { _currentPage++; })),
          const SizedBox(width: 4),
          _buildPageNavBtn(Icons.last_page, _currentPage < totalPages, () => setState(() { _currentPage = totalPages; })),
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
          child: Text('...', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
        );
      }
      final isActive = p == _currentPage;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: Material(
          color: isActive ? Theme.of(context).primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: isActive ? null : () => setState(() { _currentPage = p; }),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              alignment: Alignment.center,
              child: Text('$p', style: TextStyle(
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
          child: Icon(icon, size: 18, color: enabled ? Colors.grey.shade700 : Colors.grey.shade300),
        ),
      ),
    );
  }

  Widget _buildTable(
      List<Map<String, dynamic>> data, List<PayrollColumn> visibleCols, {int startIndex = 0}) {
    final frozenCols = visibleCols.where((c) => _frozenKeys.contains(c.key)).toList();
    final scrollableCols = visibleCols.where((c) => !_frozenKeys.contains(c.key)).toList();

    const double rowHeight = 40;
    const double headerHeight = 44;
    const double cellPadding = 8;

    double colWidth(PayrollColumn col) {
      switch (col.key) {
        case 'stt': return 40;
        case 'code': return 110;
        case 'name': return 160;
        case 'department': return 100;
        case 'salaryType': return 80;
        case 'standardDays': return 85;
        case 'workDays': return 72;
        case 'totalHours': return 68;
        case 'otTotalHours': return 65;
        default: return 110;
      }
    }

    final frozenWidth = frozenCols.fold<double>(0, (s, c) => s + colWidth(c));

    Widget buildCell(String key, Map<String, dynamic> row, int index, double width) {
      return InkWell(
        onTap: () => _showEmployeeDetail(row),
        child: Container(
          width: width,
          height: rowHeight,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: cellPadding),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7), width: 0.5)),
          ),
          child: Text(
            _formatCellValue(key, row, index),
            style: TextStyle(
              fontSize: 11,
              fontWeight: key == 'netSalary' ? FontWeight.bold : FontWeight.normal,
              color: _getCellColor(key, row),
            ),
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
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11, color: Color(0xFF71717A)),
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
                          children: frozenCols.map((c) => buildHeaderCell(c, colWidth(c))).toList(),
                        ),
                      ),
                      // Frozen data rows
                      Expanded(
                        child: ScrollConfiguration(
                          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                          child: ListView.builder(
                            controller: _verticalScrollController,
                            itemCount: data.length,
                            itemExtent: rowHeight,
                            itemBuilder: (_, i) {
                              final row = data[i];
                              return Container(
                                color: i.isEven ? Colors.white : const Color(0xFFFAFAFA),
                                child: Row(
                                  children: frozenCols.map((c) => buildCell(c.key, row, i, colWidth(c))).toList(),
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
                        width: scrollableCols.fold<double>(0, (s, c) => s + colWidth(c)),
                        child: Column(
                          children: [
                            // Scrollable header
                            Container(
                              color: const Color(0xFFFAFAFA),
                              child: Row(
                                children: scrollableCols.map((c) => buildHeaderCell(c, colWidth(c))).toList(),
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
                                    color: i.isEven ? Colors.white : const Color(0xFFFAFAFA),
                                    child: Row(
                                      children: scrollableCols.map((c) => buildCell(c.key, row, i, colWidth(c))).toList(),
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
        final sorted = list..sort((a, b) => ((a['milestonePercent'] ?? 0) as num).compareTo((b['milestonePercent'] ?? 0) as num));
        final migrated = <Map<String, dynamic>>[];
        for (int i = 0; i < sorted.length; i++) {
          final from = (sorted[i]['milestonePercent'] as num?)?.toDouble() ?? 0;
          final to = i + 1 < sorted.length ? (sorted[i + 1]['milestonePercent'] as num?)?.toDouble() ?? -1 : -1.0;
          migrated.add({'fromPct': from, 'toPct': to, 'rate': sorted[i]['bonusAmount'] ?? 0, 'rateType': 0});
        }
        return migrated;
      }
      return list;
    } catch (_) { return []; }
  }

  List<Map<String, dynamic>> _kpiParsePenaltyTiers(String? json) {
    if (json == null || json.isEmpty || json == 'null') return [];
    try { return (jsonDecode(json) as List).cast<Map<String, dynamic>>(); }
    catch (_) { return []; }
  }

  double _kpiCalcPenaltyBonus(Map<String, dynamic> target) {
    final pTiers = _kpiParsePenaltyTiers(target['penaltyTiersJson']?.toString());
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
        if (rateType == 2) { bonus = rate; }
        else if (rateType == 3) { bonus = cs * rate / 100; }
        else {
          final fromVal = tgt * fromPct / 100;
          final toVal = toPct < 0 ? act : tgt * toPct / 100;
          final inBand = (act < toVal ? act : toVal) - fromVal;
          if (inBand > 0) bonus = rateType == 1 ? inBand * rate / 100 : inBand * rate;
        }
      }
      return {'fromPct': fromPct, 'toPct': toPct, 'rate': rate, 'rateType': rateType, 'bonus': bonus};
    }).toList();
  }

  String _formatCellValue(String key, Map<String, dynamic> row, int index) {
    switch (key) {
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
        return sd == sd.roundToDouble() ? '${sd.toInt()}' : sd.toStringAsFixed(1);
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

}

class _SummaryItem {
  final String label;
  final String value;
  final Color color;
  const _SummaryItem(this.label, this.value, this.color);
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
