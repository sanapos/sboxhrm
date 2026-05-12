import 'dart:convert';
import 'dart:math' as math;
import '../../utils/file_saver.dart' as file_saver;
import '../../utils/web_canvas.dart' as web_canvas;

import 'package:excel/excel.dart' as excel_lib;
import 'package:flutter/material.dart';
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
  final String? branchId;

  const PayrollSummaryTab({
    super.key,
    required this.attendances,
    required this.devices,
    required this.fromDate,
    required this.toDate,
    this.branchId,
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
  void didUpdateWidget(PayrollSummaryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.branchId != widget.branchId) {
      _cachedPayrollData = null;
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
      final list =
          _columns.map((c) => {'key': c.key, 'visible': c.visible}).toList();
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
      // Loại bỏ NV chưa thiết lập bảng lương khỏi tổng hợp lương.
      _employees =
          _employees.where((e) => profileMap.containsKey(e.id)).toList();
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
          final periods =
              List<Map<String, dynamic>>.from(periodsRes['data'] ?? []);
          String? matchPeriodId;
          for (final p in periods) {
            final pStart =
                DateTime.tryParse(p['periodStart']?.toString() ?? '');
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
            final targetsRes = await _apiService.getKpiEmployeeTargets(
                periodId: matchPeriodId);
            if (targetsRes['isSuccess'] == true) {
              _kpiEmployeeTargets =
                  List<Map<String, dynamic>>.from(targetsRes['data'] ?? []);
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
          _productionSummaries =
              List<Map<String, dynamic>>.from(prodRes['data'] ?? []);
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
                  ?.map((item) =>
                      Attendance.fromJson(item as Map<String, dynamic>))
                  .toList() ??
              [];
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

    final benefit = profile?['benefit'] as Map<String, dynamic>?;
    final double baseSalary = _toDouble(benefit?['rate']);
    final int rateType = _parseRateType(benefit?['rateType']);
    final double completionSalary = _toDouble(benefit?['completionSalary']);
    final double mealAllowancePerDay = _toDouble(benefit?['mealAllowance']);
    final double responsibilityAllowance =
        _toDouble(benefit?['responsibilityAllowance']);
    final int shiftsPerDay = _toInt(benefit?['shiftsPerDay'], 1);
    // Chế độ chấm công: 'checkin' = chỉ cần chấm vào, 'checkout' = chỉ cần chấm ra,
    // 'both' = phải có cả vào và ra mới tính công, 'any' = chỉ cần 1 punch, 'none' = không yêu cầu.
    final String attendanceMode =
        (benefit?['attendanceMode'] ?? 'both').toString();
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

      // Áp dụng attendanceMode: ngày không thoả điều kiện thì không tính công.
      bool dayValid;
      switch (attendanceMode) {
        case 'checkin':
          dayValid = checkIns.isNotEmpty;
          break;
        case 'checkout':
          dayValid = checkOuts.isNotEmpty;
          break;
        case 'both':
          dayValid = checkIns.isNotEmpty && checkOuts.isNotEmpty;
          break;
        case 'any':
          dayValid = checkIns.isNotEmpty || checkOuts.isNotEmpty;
          break;
        case 'none':
        default:
          dayValid = true;
      }
      if (!dayValid) continue;

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

      // Đếm số ca thực tế: mỗi cặp IN-OUT phải đảm bảo >= 2/3 số giờ ca.
      // Số giờ tối thiểu 1 ca = (standardDayHours / shiftsPerDay) * 2/3
      if (checkIns.isNotEmpty) {
        final hoursPerShift = shiftsPerDay > 0
            ? standardDayHours / shiftsPerDay
            : standardDayHours;
        final minHoursForShift = hoursPerShift * (2.0 / 3.0);
        // Dùng logic pairing: min(checkIns, max(checkOuts, 1)), tối đa shiftsPerDay
        final pairCount = math.min(
          checkIns.length,
          math.max(checkOuts.length, 1),
        );
        final actualPairCount = math.min(pairCount, shiftsPerDay);
        int validShifts = 0;
        for (int i = 0; i < actualPairCount; i++) {
          final inTime = checkIns[i].attendanceTime;
          if (i < checkOuts.length) {
            final outTime = checkOuts[i].attendanceTime;
            final pairHours =
                math.max(0.0, outTime.difference(inTime).inMinutes / 60.0);
            if (pairHours >= minHoursForShift) validShifts++;
          } else {
            // Không có checkout tương ứng: giả sử làm đủ ca (đã qua attendanceMode filter)
            validShifts++;
          }
        }
        totalShifts += validShifts;
      }

      // Late/early detection using scheduled times from Benefit
      if (checkIns.isNotEmpty && !isWkend && !isHol) {
        final firstIn = checkIns.first.attendanceTime;
        final scheduledIn = DateTime(firstIn.year, firstIn.month, firstIn.day,
            scheduledInHour, scheduledInMin);
        if (firstIn.isAfter(scheduledIn.add(const Duration(minutes: 5)))) {
          lateCount++;
          lateMinutes += firstIn.difference(scheduledIn).inMinutes;
        }
      }
      if (checkOuts.isNotEmpty && !isWkend && !isHol) {
        final lastOut = checkOuts.last.attendanceTime;
        final scheduledOut = DateTime(lastOut.year, lastOut.month, lastOut.day,
            scheduledOutHour, scheduledOutMin);
        if (lastOut
            .isBefore(scheduledOut.subtract(const Duration(minutes: 5)))) {
          earlyCount++;
          earlyMinutes += scheduledOut.difference(lastOut).inMinutes;
        }
      }
    }

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
      } else if (!attendanceByDate.containsKey(key) &&
          d.isBefore(DateTime.now())) {
        absentDays++;
      }
    }

    // ═══ Salary calculation ═══
    double workSalary = 0;
    double hourlyRate = 0;
    double shiftLevelAllowance = 0;
    bool shiftIsNightShift = false;

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
          workSalary = fixedShiftRate * totalShifts;
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
            shiftIsNightShift = matchedLevel['isNightShift'] == true;
            switch (lvlRateType) {
              case 'hourly':
                final effHourly = lvlHourlyRate > 0
                    ? lvlHourlyRate
                    : fixedShiftRate / standardDayHours;
                workSalary = effHourly * totalWorkHours;
                hourlyRate = effHourly;
                break;
              case 'multiplier':
                final perShift = fixedShiftRate * lvlMultiplier;
                workSalary = perShift * totalShifts;
                hourlyRate = perShift / standardDayHours;
                break;
              default: // 'fixed'
                workSalary = lvlFixedRate * totalShifts;
                hourlyRate = lvlFixedRate / standardDayHours;
            }
            // Ca đêm: cộng thêm 30% theo luật lao động
            if (shiftIsNightShift) {
              workSalary *= 1.3;
            }
          } else {
            // Không tìm thấy mức lương ca, dùng fixedShiftRate từ Benefit
            workSalary = fixedShiftRate * totalShifts;
            hourlyRate = fixedShiftRate / standardDayHours;
          }
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
    // Per-day allowances × actual work days (built-in từ Benefit)
    // shiftLevelAllowance: phụ cấp ca từ ShiftSalaryLevel (theo số ca)
    double totalAllowance =
        (mealAllowancePerDay + responsibilityAllowance) * workDays +
            shiftLevelAllowance;

    // Cộng thêm phụ cấp từ AllowanceSettings (Fixed = cố định/kỳ, Daily = theo ngày công)
    // Lọc theo EmployeeIds và StartDate/EndDate.
    final empIdForAllowance = emp?.id;
    for (final al in _allowanceSettings) {
      // Filter EmployeeIds (JSON array). null/empty = áp dụng tất cả.
      final empIdsRaw = al['employeeIds'];
      if (empIdsRaw != null && empIdsRaw.toString().isNotEmpty) {
        try {
          final ids = jsonDecode(empIdsRaw.toString()) as List;
          if (empIdForAllowance == null || !ids.contains(empIdForAllowance)) {
            continue;
          }
        } catch (_) {
          continue;
        }
      }
      // Filter ngày hiệu lực
      final startStr = al['startDate']?.toString();
      final endStr = al['endDate']?.toString();
      if (startStr != null && startStr.isNotEmpty) {
        final s = DateTime.tryParse(startStr);
        if (s != null && s.isAfter(_toDate)) continue;
      }
      if (endStr != null && endStr.isNotEmpty) {
        final e = DateTime.tryParse(endStr);
        if (e != null && e.isBefore(_fromDate)) continue;
      }
      final amount = _toDouble(al['amount']);
      if (amount <= 0) continue;
      final type = al['type']?.toString().toLowerCase() ?? '';
      // Type: 'fixed'/'0' = cố định toàn kỳ, 'daily'/'1' = nhân workDays.
      if (type == 'daily' || type == '1') {
        totalAllowance += amount * workDays;
      } else {
        totalAllowance += amount;
      }
    }

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
      // Tiered late penalty (approximate: use average late minutes per incident)
      for (final entry in attendanceByDate.entries) {
        final dayAtts = entry.value;
        final date = dayAtts.first.attendanceTime;
        if (_isHoliday(date) || _isWeekend(date)) continue;
        final checkIns = dayAtts.where((a) => a.attendanceState == 0).toList();
        if (checkIns.isEmpty) continue;
        final firstIn = checkIns.first.attendanceTime;
        final scheduledIn = DateTime(firstIn.year, firstIn.month, firstIn.day,
            scheduledInHour, scheduledInMin);
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
        final scheduledOut = DateTime(lastOut.year, lastOut.month, lastOut.day,
            scheduledOutHour, scheduledOutMin);
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
        completionSalaryAmount +
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
    final double otTotalHours =
        otHoursWeekday + otHoursWeekend + otHoursHoliday;

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

          return AlertDialog(
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
                      // Reset to defaults
                      tempColumns = _columns.map((c) {
                        final orig = _columns.firstWhere((o) => o.key == c.key);
                        return PayrollColumn(
                          key: orig.key,
                          label: orig.label,
                          defaultVisible: orig.defaultVisible,
                          visible: orig.defaultVisible,
                        );
                      }).toList();
                      _initColumns();
                      tempColumns = _columns
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
        excel_lib.TextCellValue(
            'Lương cơ bản: ${_currencyFmt.format(totalBase.round())}'),
        excel_lib.TextCellValue(
            'Tổng lương: ${_currencyFmt.format(totalWork.round())}'),
        excel_lib.TextCellValue(
            'Tổng bảo hiểm: ${_currencyFmt.format(totalIns.round())}'),
        excel_lib.TextCellValue(
            'Thực nhận: ${_currencyFmt.format(totalNet.round())}'),
      ]);

      wb.delete('Sheet1');
      final bytes = wb.encode();
      if (bytes != null) {
        final fn =
            'tong_hop_luong_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
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

  Future<void> exportToPng() async {
    try {
      final data = _buildPayrollData();
      if (data.isEmpty) {
        appNotification.showError(title: 'Lỗi', message: 'Không có dữ liệu để xuất');
        return;
      }

      final visibleCols = _columns.where((c) => c.visible).toList();
      final headers = visibleCols.map((c) => c.label).toList();

      // Build rows
      final rows = <List<String>>[];
      for (int i = 0; i < data.length; i++) {
        final row = data[i];
        final cells = <String>[];
        for (final col in visibleCols) {
          final v = row[col.key];
          if (v == null) {
            cells.add('-');
          } else if (col.key == 'stt') {
            cells.add('${i + 1}');
          } else if (v is double || v is int) {
            final n = (v as num).toDouble();
            if (col.key.contains('alary') || col.key.contains('salary') ||
                col.key.contains('Salary') || col.key.contains('allowance') ||
                col.key.contains('deduction') || col.key.contains('bonus') ||
                col.key.contains('Amount') || col.key.contains('insurance') ||
                col.key.contains('advance') || col.key.contains('penalty') ||
                col.key.contains('meal') || col.key.contains('debt')) {
              cells.add(n == 0 ? '-' : _currencyFmt.format(n.round()));
            } else if (col.key.contains('Minutes') || col.key.contains('minutes')) {
              cells.add(n == 0 ? '-' : '${n.toInt()}P');
            } else if (n == n.roundToDouble()) {
              cells.add(n == 0 ? '0' : '${n.toInt()}');
            } else {
              cells.add(n.toStringAsFixed(2));
            }
          } else {
            cells.add(v.toString().isEmpty ? '-' : v.toString());
          }
        }
        rows.add(cells);
      }

      // Summary row
      final summaryRow = List<String>.filled(headers.length, '');
      summaryRow[0] = 'TỔNG';
      for (int c = 0; c < visibleCols.length; c++) {
        final key = visibleCols[c].key;
        if (['stt', 'code', 'name', 'department', 'position', 'salaryType'].contains(key)) continue;
        final total = data.fold<double>(0, (s, r) => s + ((r[key] as num?) ?? 0).toDouble());
        if (total != 0) {
          if (key.contains('alary') || key.contains('allowance') || key.contains('deduction') ||
              key.contains('bonus') || key.contains('insurance') || key.contains('advance') ||
              key.contains('penalty') || key.contains('meal') || key.contains('debt')) {
            summaryRow[c] = _currencyFmt.format(total.round());
          } else if (key.contains('Minutes') || key.contains('minutes')) {
            summaryRow[c] = '${total.toInt()}P';
          } else {
            summaryRow[c] = total == total.roundToDouble()
                ? '${total.toInt()}'
                : total.toStringAsFixed(2);
          }
        }
      }
      rows.add(summaryRow);

      const double cellPadding = 10;
      const double fontSize = 12;
      const double headerFontSize = 13;
      const double rowHeight = 30;
      const double headerHeight = 40;
      const double titleHeight = 50;

      final colWidths = <double>[];
      for (int c = 0; c < headers.length; c++) {
        double maxW = headers[c].length * 8.5 + cellPadding * 2;
        for (final row in rows) {
          if (c < row.length) {
            final w = row[c].length * 7.5 + cellPadding * 2;
            if (w > maxW) maxW = w;
          }
        }
        if (c == 2) maxW = maxW.clamp(120.0, 200.0); // Name column
        colWidths.add(maxW.clamp(55.0, 200.0));
      }

      final totalWidth = colWidths.fold(0.0, (sum, w) => sum + w) + 2;
      final totalHeight = titleHeight + headerHeight + rows.length * rowHeight + 2;

      void drawCanvas(dynamic ctx) {
        ctx.fillStyle = '#FFFFFF';
        ctx.fillRect(0, 0, totalWidth, totalHeight);

        ctx.fillStyle = '#1a1a1a';
        ctx.font = 'bold 16px Arial, sans-serif';
        final period =
            'Tổng hợp lương: ${DateFormat('dd/MM/yyyy').format(_fromDate)} - ${DateFormat('dd/MM/yyyy').format(_toDate)}';
        ctx.fillText(period, 10, 32);

        // Header row
        double x = 1;
        const headerY = titleHeight;
        ctx.fillStyle = '#1E3A5F';
        ctx.fillRect(1, headerY, totalWidth - 2, headerHeight);

        for (int c = 0; c < headers.length; c++) {
          ctx.fillStyle = '#FFFFFF';
          ctx.font = 'bold ${headerFontSize}px Arial, sans-serif';
          ctx.fillText(headers[c], x + cellPadding, headerY + headerHeight / 2 + 5);
          ctx.strokeStyle = '#2d5a8e';
          ctx.lineWidth = 0.5;
          ctx.beginPath();
          ctx.moveTo(x + colWidths[c], headerY);
          ctx.lineTo(x + colWidths[c], totalHeight);
          ctx.stroke();
          x += colWidths[c];
        }

        // Data rows
        for (int r = 0; r < rows.length; r++) {
          final rowY = titleHeight + headerHeight + r * rowHeight;
          final isLast = r == rows.length - 1;
          if (isLast) {
            ctx.fillStyle = '#EBF5FF';
            ctx.fillRect(1, rowY, totalWidth - 2, rowHeight);
          } else if (r % 2 == 1) {
            ctx.fillStyle = '#F8FAFC';
            ctx.fillRect(1, rowY, totalWidth - 2, rowHeight);
          }
          ctx.strokeStyle = '#E2E8F0';
          ctx.beginPath();
          ctx.moveTo(1, rowY + rowHeight);
          ctx.lineTo(totalWidth - 1, rowY + rowHeight);
          ctx.stroke();

          x = 1;
          for (int c = 0; c < rows[r].length && c < colWidths.length; c++) {
            final cellText = rows[r][c];
            if (isLast) {
              ctx.fillStyle = '#1E40AF';
              ctx.font = 'bold ${fontSize}px Arial, sans-serif';
            } else {
              ctx.fillStyle = '#334155';
              ctx.font = '${fontSize}px Arial, sans-serif';
            }
            ctx.fillText(cellText, x + cellPadding, rowY + rowHeight / 2 + 4);
            x += colWidths[c];
          }
        }

        ctx.strokeStyle = '#CBD5E1';
        ctx.lineWidth = 1;
        ctx.strokeRect(1, titleHeight, totalWidth - 2, totalHeight - titleHeight - 1);
      }

      final fileName =
          'tong_hop_luong_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.png';

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
          await file_saver.saveAndOpenFileBytes(pngBytes, fileName, 'image/png');
        } else {
          appNotification.showError(title: 'Lỗi', message: 'Không thể xuất PNG');
          return;
        }
      }
      appNotification.showSuccess(
          title: 'Thành công',
          message: 'Đã lưu PNG vào Ảnh/SBOX HRM: $fileName');
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
          _detailRow('Lương hoàn thành', _fmtCurrency(row['completionSalary'])),
          _detailRow('Lương theo ngày', _fmtCurrency(row['dailySalary'])),
          _detailRow('Lương theo ca', _fmtCurrency(row['shiftSalary'])),
          _detailRow('Lương theo giờ', _fmtCurrency(row['hourlySalary'])),
          _detailRow('Lương tăng ca', _fmtCurrency(row['otSalary'])),
          _detailRow('Phụ cấp ăn trưa', _fmtCurrency(row['mealAllowance'])),
          _detailRow('Phụ cấp trách nhiệm',
              _fmtCurrency(row['responsibilityAllowance'])),
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
        builder: (ctx) => AlertDialog(
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

    return Padding(
      padding: EdgeInsets.all(Responsive.isMobile(context) ? 10 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildToolbar(),
          const SizedBox(height: 12),
          if (Responsive.isMobile(context)) ...[
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
                            style: TextStyle(
                                color: Colors.grey.shade500, fontSize: 15)),
                        const SizedBox(height: 4),
                        Text('Hãy kiểm tra khoảng thời gian đã chọn',
                            style: TextStyle(
                                color: Colors.grey.shade400, fontSize: 12)),
                      ],
                    ),
                  )
                : RepaintBoundary(
                    key: _tableKey,
                    child: _buildCrossTabPayroll(payrollData),
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
                const Expanded(
                    child:
                        Text('Chọn nhân viên', style: TextStyle(fontSize: 16))),
                TextButton(
                  onPressed: () => setDialogState(() => tempSelected.clear()),
                  child: const Text('Bỏ chọn tất cả',
                      style: TextStyle(fontSize: 12)),
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
                          ? 'Hiển thị tất cả nhân viên'
                          : 'Đã chọn ${tempSelected.length} nhân viên',
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
            Icon(Icons.calendar_today,
                size: 14, color: Theme.of(context).primaryColor),
            const SizedBox(width: 6),
            Text(
              _periodLabel(_selectedPeriod),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).primaryColor),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down,
                size: 18, color: Theme.of(context).primaryColor),
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
            Text(DateFormat('dd/MM/yyyy').format(_fromDate),
                style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    );

    final dateSep =
        Text('—', style: TextStyle(color: Colors.grey.shade400, fontSize: 13));

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
            Text(DateFormat('dd/MM/yyyy').format(_toDate),
                style: const TextStyle(fontSize: 13)),
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
            Icon(Icons.people_outline,
                size: 14,
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
                child: Icon(Icons.close,
                    size: 14, color: Theme.of(context).primaryColor),
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
        color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${_buildPayrollData().length} NV',
        style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF1E3A5F),
            fontWeight: FontWeight.w600),
      ),
    );

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
                      onTap: () => setState(
                          () => _showMobileFilters = !_showMobileFilters),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        height: 36,
                        width: 36,
                        decoration: BoxDecoration(
                          color: _showMobileFilters
                              ? Theme.of(context)
                                  .primaryColor
                                  .withValues(alpha: 0.1)
                              : const Color(0xFFFAFAFA),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _showMobileFilters
                                  ? Theme.of(context)
                                      .primaryColor
                                      .withValues(alpha: 0.3)
                                  : const Color(0xFFE4E4E7)),
                        ),
                        child: Stack(
                          children: [
                            Center(
                                child: Icon(
                                    _showMobileFilters
                                        ? Icons.filter_alt
                                        : Icons.filter_alt_outlined,
                                    size: 18,
                                    color: _showMobileFilters
                                        ? Theme.of(context).primaryColor
                                        : Colors.grey.shade600)),
                            if (_selectedPeriod != 'thisMonth' ||
                                _selectedEmployeeIds.isNotEmpty)
                              Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Container(
                                      width: 7,
                                      height: 7,
                                      decoration: const BoxDecoration(
                                          color: Colors.orange,
                                          shape: BoxShape.circle))),
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
    final totalBase = data.fold<double>(
        0, (s, r) => s + ((r['baseSalary'] as num?) ?? 0).toDouble());
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
      _SummaryItem('Tổng lương CB', _currencyFmt.format(totalBase.round()),
          const Color(0xFF1E3A5F), Icons.account_balance_wallet_outlined),
      _SummaryItem('Phụ cấp', _currencyFmt.format(totalAllowance.round()),
          const Color(0xFF2D5F8B), Icons.card_giftcard_outlined),
      _SummaryItem('Thưởng', _currencyFmt.format(totalBonus.round()),
          const Color(0xFF8B5CF6), Icons.emoji_events_outlined),
      _SummaryItem('Phạt', _currencyFmt.format(totalPenalty.round()),
          const Color(0xFFEF4444), Icons.gavel_outlined),
      _SummaryItem('Bảo hiểm', _currencyFmt.format(totalIns.round()),
          const Color(0xFFF59E0B), Icons.health_and_safety_outlined),
      _SummaryItem('Ứng lương', _currencyFmt.format(totalAdv.round()),
          const Color(0xFF0F2340), Icons.payments_outlined),
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

  // ignore: unused_element
  Widget _buildPagination(int totalRows, int totalPages) {
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
                    color: Color(0xFF1E3A5F),
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
              color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text('$totalRows dòng',
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF1E3A5F),
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

  // ──────── Format cell for cross-tab ────────
  String _formatPayrollCell(String key, Map<String, dynamic> row) {
    switch (key) {
      case 'workDays':
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
        final h = (row[key] as num?)?.toDouble() ?? 0;
        if (h == 0) return '0';
        return '${h.toStringAsFixed(1)}h';
      case 'lateMinutes':
      case 'earlyMinutes':
        final m = (row[key] as num?)?.toInt() ?? 0;
        if (m == 0) return '0';
        return '${m}p';
      case 'penalty':
      case 'latePenalty':
      case 'totalInsurance':
      case 'pit':
        final val = (row[key] as num?)?.toDouble() ?? 0;
        if (val == 0) return '0';
        return '-${_fmtShort(val.round())}';
      case 'advance':
        final val = (row[key] as num?)?.toDouble() ?? 0;
        if (val == 0) return '0';
        return _fmtShort(val.round());
      default:
        final val = (row[key] as num?)?.toDouble() ?? 0;
        if (val == 0) return '0';
        return _fmtShort(val.round());
    }
  }

  String _fmtShort(int n) {
    if (n == 0) return '0';
    final abs = n.abs();
    final sign = n < 0 ? '-' : '';
    if (abs >= 1000000) {
      return '$sign${(abs / 1000000).toStringAsFixed(abs >= 10000000 ? 1 : 2)}M';
    }
    if (abs >= 1000) return '$sign${(abs / 1000).toStringAsFixed(0)}k';
    return _currencyFmt.format(n);
  }

  // ──────── Cross-tab payroll layout ────────
  Widget _buildCrossTabPayroll(List<Map<String, dynamic>> data) {
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

    const empColW = 150.0;
    const rowH = 46.0;
    const hdrH = 44.0;

    Widget empCell(Map<String, dynamic> row, int idx) {
      final isEven = idx.isEven;
      final name = row['name']?.toString() ?? '';
      final code = row['code']?.toString() ?? '';
      final dept = row['department']?.toString() ?? '';
      return InkWell(
        onTap: () => _showEmployeeDetail(row),
        child: Container(
          width: empColW,
          height: rowH,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: isEven ? const Color(0xFFF4F4F5) : Colors.white,
            border: const Border(
              right: BorderSide(color: Color(0xFFD4D4D8)),
              bottom: BorderSide(color: Color(0xFFE4E4E7), width: 0.5),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF18181B)),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1),
              Text('$code${dept.isNotEmpty ? ' · $dept' : ''}',
                  style: const TextStyle(fontSize: 9, color: Color(0xFF71717A)),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1),
            ],
          ),
        ),
      );
    }

    Widget buildSection({
      required String title,
      required Color titleColor,
      required List<String> colKeys,
      required List<String> colLabels,
      required List<double> colWidths,
    }) {
      Color cellColor(String key, Map<String, dynamic> row) {
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

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header bar
          Container(
            color: titleColor.withValues(alpha: 0.08),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              Container(
                  width: 3,
                  height: 13,
                  color: titleColor,
                  margin: const EdgeInsets.only(right: 7)),
              Text(title,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: titleColor)),
            ]),
          ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Frozen employee column
                Column(
                  children: [
                    Container(
                      width: empColW,
                      height: hdrH,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: const BoxDecoration(
                        color: Color(0xFF1E3A5F),
                        border: Border(
                          right: BorderSide(color: Colors.white24),
                          bottom: BorderSide(color: Colors.white24, width: 0.5),
                        ),
                      ),
                      child: const Text('Nhân viên',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    ),
                    ...data.asMap().entries.map((e) => empCell(e.value, e.key)),
                  ],
                ),
                // Scrollable columns
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: SizedBox(
                      width: colWidths.fold<double>(0, (s, w) => s + w),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header row
                          Row(
                            children: List.generate(
                                colKeys.length,
                                (i) => Container(
                                      width: colWidths[i],
                                      height: hdrH,
                                      alignment: Alignment.center,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF1E3A5F),
                                        border: Border(
                                          right: BorderSide(
                                              color: Colors.white24,
                                              width: 0.5),
                                          bottom: BorderSide(
                                              color: Colors.white24,
                                              width: 0.5),
                                        ),
                                      ),
                                      child: Text(colLabels[i],
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600)),
                                    )),
                          ),
                          // Data rows
                          ...data.asMap().entries.map((e) {
                            final row = e.value;
                            final isEven = e.key.isEven;
                            return InkWell(
                              onTap: () => _showEmployeeDetail(row),
                              child: Container(
                                color: isEven
                                    ? const Color(0xFFF9F9F9)
                                    : Colors.white,
                                child: Row(
                                  children: List.generate(colKeys.length, (i) {
                                    final key = colKeys[i];
                                    return Container(
                                      width: colWidths[i],
                                      height: rowH,
                                      alignment: Alignment.center,
                                      decoration: const BoxDecoration(
                                        border: Border(
                                          right: BorderSide(
                                              color: Color(0xFFE4E4E7),
                                              width: 0.5),
                                          bottom: BorderSide(
                                              color: Color(0xFFE4E4E7),
                                              width: 0.5),
                                        ),
                                      ),
                                      child: Text(
                                        _formatPayrollCell(key, row),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: key == 'netSalary' ||
                                                  key == 'totalSalary'
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: cellColor(key, row),
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildSection(
            title: 'BẢNG CHẤM CÔNG',
            titleColor: const Color(0xFF16A34A),
            colKeys: [
              'workDays',
              'standardDays',
              'totalHours',
              'otTotalHours',
              'lateCount',
              'lateMinutes',
              'earlyCount',
              'earlyMinutes'
            ],
            colLabels: [
              'Công',
              'Chuẩn',
              'Giờ làm',
              'Tăng ca',
              'Đi trễ',
              'Tổng trễ',
              'Về sớm',
              'Tổng sớm'
            ],
            colWidths: [60, 60, 70, 70, 60, 68, 60, 68],
          ),
          const SizedBox(height: 8),
          buildSection(
            title: 'BẢNG THU NHẬP',
            titleColor: const Color(0xFF2563EB),
            colKeys: [
              'baseSalary',
              'completionSalary',
              'dailySalary',
              'shiftSalary',
              'hourlySalary',
              'otSalary',
              'totalAllowance',
              'bonus',
              'kpiSalary',
              'productionAmount'
            ],
            colLabels: [
              'L.Cơ bản',
              'L.Hoàn thành',
              'L.Ngày',
              'L.Ca',
              'L.Giờ',
              'L.Tăng ca',
              'Phụ cấp',
              'Thưởng',
              'KPI',
              'Sản lượng'
            ],
            colWidths: [100, 100, 90, 90, 90, 100, 90, 90, 90, 100],
          ),
          const SizedBox(height: 8),
          buildSection(
            title: 'BẢNG KHẤU TRỪ',
            titleColor: const Color(0xFFDC2626),
            colKeys: [
              'latePenalty',
              'penalty',
              'totalInsurance',
              'pit',
              'advance'
            ],
            colLabels: [
              'Phạt trễ/sớm',
              'Phạt khác',
              'Bảo hiểm',
              'TNCN',
              'Ứng lương'
            ],
            colWidths: [100, 90, 100, 90, 90],
          ),
          const SizedBox(height: 8),
          buildSection(
            title: 'BẢNG TỔNG CỘNG',
            titleColor: const Color(0xFF7C3AED),
            colKeys: ['totalSalary', 'totalDeduction', 'netSalary'],
            colLabels: ['Tổng lương', 'Tổng khấu trừ', 'THỰC NHẬN'],
            colWidths: [130, 120, 140],
          ),
          const SizedBox(height: 20),
        ],
      ),
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
