import 'dart:async';
import 'dart:collection';
// ignore_for_file: unused_import, unused_element, unused_field, unused_local_variable
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/attendance.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/api_datetime.dart';
import '../utils/attendance_load_utils.dart';
import '../utils/attendance_date_range_presets.dart';
import '../utils/salary_profile_load_utils.dart';
import '../utils/dashboard_ui_capabilities.dart';
import '../utils/number_formatter.dart';
import '../utils/shift_records_calculator.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/pos/pos_mobile_widgets.dart';
import '../widgets/pos/pos_theme.dart';
import '../design_system/design_system.dart';
import '../utils/responsive_helper.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/app_scroll_safe.dart';
import '../widgets/ai_assistant_sheet.dart';
import '../widgets/dashboard/employee_module_grid.dart';
import '../utils/navigation_notifier.dart';
import 'main_layout.dart';
import 'leave_screen.dart';
import 'attendance_corrections_screen.dart';
import 'attendance_approval_screen.dart';
import '../widgets/hrm_pushed_screen_shell.dart';
import 'attendance_by_shift_screen.dart';
import 'advance_requests_screen.dart';
import 'hr_documents_screen.dart';
import 'employees_screen.dart';
import 'overtime_screen.dart';
import '../models/task.dart';
import 'task_management_screen.dart';
import 'penalty_tickets_screen.dart';
import 'cash_transaction_screen.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

int? _approvalStatusCode(dynamic status) {
  if (status == null) return null;
  if (status is num) return status.toInt();
  final s = status.toString().trim().toLowerCase();
  if (s == 'pending' || s == 'chờ duyệt') return 0;
  if (s == 'approved' || s == 'đã duyệt') return 1;
  if (s == 'rejected' || s == 'từ chối') return 2;
  return int.tryParse(s);
}

bool _isPendingApprovalStatus(dynamic status) =>
    _approvalStatusCode(status) == 0;

/// Chỉ giữ phiếu status = Pending (0); thiếu status → giữ (API pending-only).
List<dynamic> _pendingApprovalItemsOnly(List<dynamic> items) => items
    .where((e) {
      if (e is! Map) return false;
      final status = e['status'] ?? e['Status'];
      if (status == null) return true;
      return _isPendingApprovalStatus(status);
    })
    .toList();

bool _canApprovePendingType(String type, PermissionProvider perm) {
  switch (type) {
    case 'leave':
      return perm.canApprove('Leave');
    case 'correction':
      return perm.canApprove('AttendanceApproval');
    case 'swap':
      return perm.canApprove('ScheduleApproval') ||
          perm.canApprove('ShiftSwap');
    case 'advance':
      return perm.canApprove('AdvanceRequests');
    case 'mobile':
      return perm.canApprove('MobileAttendanceApproval') ||
          perm.canApprove('MobileAttendance');
    default:
      return false;
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  AppLocalizations get _l10n => AppLocalizations.of(context);

  final ApiService _api = ApiService();
  bool _isLoading = true;
  bool _isEmployee = false;
  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  // Employee dashboard data
  Map<String, dynamic> _employeeDashboard = {};
  String _employeeStatsPeriod = 'month';
  List<Attendance> _employeeRawPunches = [];
  bool _employeeRawPunchesExpanded = false;
  List<DailyShiftRecord> _employeeShiftRecords = [];

  // Data
  Map<String, dynamic> _dailyReport = {};
  List<dynamic> _dailyReportItems = [];
  DateTime? _selectedDate; // null => today
  DateTime? _rangeStart; // for week/month preset; null => single day
  DateTime? _rangeEnd;
  String _presetKey =
      'today'; // today|yesterday|thisWeek|lastWeek|thisMonth|lastMonth|custom
  List<dynamic> _todayLeaves = [];
  List<dynamic> _devices = [];
  List<dynamic> _communications = [];
  List<dynamic> _employees = [];
  List<dynamic> _birthdayEmployees = []; // Full-store, unfiltered birthday list
  List<dynamic> _shiftTemplates =
      []; // Store shift templates (for overnight detection)

  // Inputs cho thuật toán "Tổng hợp theo ca" — dùng để tính KPI "Đi trễ / Về
  // sớm" trên Dashboard đồng nhất với tab. Dashboard không nhề logic này
  // trên backend daily report nữa.
  List<Attendance> _rawAttendances = [];
  List<Map<String, dynamic>> _shiftTemplatesTyped = [];
  List<Map<String, dynamic>> _shiftSalaryLevels = [];
  List<Map<String, dynamic>> _salaryProfiles = [];
  List<dynamic> _holidaysSettings = [];
  int _dayEndHour = 0;
  int _dayEndMinute = 0;
  double _minHoursForWorkDay = 0;
  bool _decimalWorkDayEnabled = false;
  double _standardWorkHours = 8;
  List<DailyShiftRecord> _shiftRecords = const [];
  // Per-shift late/early entries — KHÔNG gộp theo ngày, mỗi ca riêng 1 dòng.
  List<DailyShiftLateEntry> _lateShiftEntries = const [];
  // Tất cả các cặp ca trong ngày — dùng cho realtime attendance card
  // để hiển thị mỗi ca mỗi dòng (không gộp theo nhân viên).
  List<DailyShiftPair> _shiftPairs = const [];

  // Rolling banner
  int _bannerIndex = 0;
  Timer? _bannerTimer;
  Timer? _scrollResumeBannerTimer;
  late final ScrollController _scrollController;
  List<dynamic> _kpiResults = [];
  Map<String, dynamic> _kpiDashboard = {};
  List<dynamic> _todaySchedules = [];

  // Phase 3 data
  List<dynamic> _pendingLeaves = [];
  List<dynamic> _pendingCorrections = [];
  List<dynamic> _pendingSwaps = [];
  List<dynamic> _pendingAdvances = [];
  List<dynamic> _pendingMobileAttendance = [];
  int _pendingMobileAttendanceCount = 0;
  Map<String, dynamic> _taskStats = {};
  Map<String, dynamic> _overtimeStats = {};
  Map<String, dynamic> _penaltyStats = {};
  Map<String, dynamic> _cashSummary = {};
  Map<String, dynamic> _monthlyReport = {};
  List<dynamic> _expiringDocs = []; // sắp hết hạn (≤30 ngày)
  List<dynamic> _expiredContracts = []; // đã hết hạn

  bool _dashboardModeResolved = false;

  List<String>? _allowedModules(BuildContext context) =>
      Provider.of<AuthProvider>(context, listen: false).user?.allowedModules;

  DashboardUiCapabilities _caps(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    return DashboardUiCapabilities.from(
      perm,
      role: auth.userRole,
      allowedModules: auth.user?.allowedModules,
    );
  }

  void _resolveDashboardMode(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    if (!perm.isLoaded) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final caps = DashboardUiCapabilities.from(
      perm,
      role: auth.userRole,
      allowedModules: auth.user?.allowedModules,
    );
    final useEmp = caps.useEmployeeLayout;
    if (!_dashboardModeResolved || _isEmployee != useEmp) {
      final switching = _isEmployee != useEmp;
      _dashboardModeResolved = true;
      _isEmployee = useEmp;
      if (switching || _isLoading) {
        if (useEmp) {
          _loadEmployeeData();
        } else {
          _loadAllData(caps);
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _clockTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    ScreenRefreshNotifier.dashboard.addListener(_onExternalDashboardRefresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _resolveDashboardMode(context);
    });
  }

  void _onExternalDashboardRefresh() {
    if (!mounted) return;
    if (_isEmployee) {
      _loadEmployeeData();
    } else {
      _loadAllData(_caps(context));
    }
  }

  @override
  void dispose() {
    ScreenRefreshNotifier.dashboard.removeListener(_onExternalDashboardRefresh);
    _clockTimer?.cancel();
    _bannerTimer?.cancel();
    _scrollResumeBannerTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  bool _handleDashboardScrollNotification(ScrollNotification notification) {
    if (_bannerItems.length <= 1) return false;
    if (notification is UserScrollNotification &&
        notification.direction != ScrollDirection.idle) {
      _bannerTimer?.cancel();
    } else if (notification is ScrollEndNotification) {
      _scrollResumeBannerTimer?.cancel();
      _scrollResumeBannerTimer =
          Timer(const Duration(milliseconds: 700), () {
        if (mounted) _startBannerTimer();
      });
    }
    return false;
  }

  Widget _wrapDashboardScroll(Widget scrollable) {
    return NotificationListener<ScrollNotification>(
      onNotification: _handleDashboardScrollNotification,
      child: scrollable,
    );
  }

  Widget _dashboardSection(Widget child) => RepaintBoundary(child: child);

  void _startBannerTimer() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      final items = _bannerItems;
      if (items.length > 1) {
        setState(() => _bannerIndex = (_bannerIndex + 1) % items.length);
      }
    });
  }

  (DateTime, DateTime) _employeeStatsDateRange() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    switch (_employeeStatsPeriod) {
      case 'week':
        return (
          DateTime(now.year, now.month, now.day).subtract(const Duration(days: 7)),
          end,
        );
      case 'year':
        return (DateTime(now.year - 1, now.month, now.day), end);
      default:
        if (now.month == 1) {
          return (DateTime(now.year - 1, 12, now.day), end);
        }
        return (DateTime(now.year, now.month - 1, now.day), end);
    }
  }

  Future<void> _loadEmployeeData() async {
    setState(() => _isLoading = true);
    try {
      final (rangeStart, rangeEnd) = _employeeStatsDateRange();

      final results = await Future.wait([
        _api.getEmployeeDashboard(period: _employeeStatsPeriod),
        _api.getMyLeaves(pageSize: 10),
        _api.getMyEmployee(),
        _safe(
            () => _api.getCommunications(page: 1, pageSize: 5),
            <String, dynamic>{},
            'employee-comms'),
        _safe(
            () => _api.getAppSetting('day_end_time'),
            <String, dynamic>{},
            'employee-day-end'),
        _safe(
            () => _api.getAppSetting('min_hours_for_work_day'),
            <String, dynamic>{},
            'employee-min-hours'),
        _safe(
            () => _api.getAppSetting('decimal_work_day_enabled'),
            <String, dynamic>{},
            'employee-decimal-work-day'),
        _safe(() => _api.getSalarySettings(), <String, dynamic>{}, 'employee-salary'),
        _safe(() => _api.getShifts(), <dynamic>[], 'employee-shifts'),
        _safe(
            () => _api.getShiftSalaryLevels(),
            <String, dynamic>{},
            'employee-shift-levels'),
        loadAttendanceSalaryProfiles(_api, preferSelfServiceApi: true),
        _safe(() => _api.getHolidaySettings(0), <dynamic>[], 'employee-holidays'),
      ]);

      var dayEndHour = 0;
      var dayEndMinute = 0;
      final dayEndResp = results[4] as Map<String, dynamic>;
      if (dayEndResp['isSuccess'] == true && dayEndResp['data'] is Map) {
        final value =
            (dayEndResp['data'] as Map)['value']?.toString() ?? '00:00:00';
        final parts = value.split(':');
        if (parts.length >= 2) {
          dayEndHour = int.tryParse(parts[0]) ?? 0;
          dayEndMinute = int.tryParse(parts[1]) ?? 0;
        }
      }
      var minHoursForWorkDay = 0.0;
      final minHoursResp = results[5] as Map<String, dynamic>;
      if (minHoursResp['isSuccess'] == true && minHoursResp['data'] is Map) {
        minHoursForWorkDay = parseMinHoursForWorkDay(
          appSettingValue:
              (minHoursResp['data'] as Map)['value']?.toString(),
        );
      }
      var decimalWorkDayEnabled = false;
      final decimalResp = results[6] as Map<String, dynamic>;
      if (decimalResp['isSuccess'] == true && decimalResp['data'] is Map) {
        decimalWorkDayEnabled = parseDecimalWorkDayEnabled(
          appSettingValue:
              (decimalResp['data'] as Map)['value']?.toString(),
        );
      }
      final salarySettings = results[7] as Map<String, dynamic>;
      if (minHoursForWorkDay == 0) {
        minHoursForWorkDay = parseMinHoursForWorkDay(salarySettings: salarySettings);
      }
      if (!decimalWorkDayEnabled) {
        decimalWorkDayEnabled =
            parseDecimalWorkDayEnabled(salarySettings: salarySettings);
      }
      final standardWorkHours = parseStandardWorkHours(salarySettings: salarySettings);

      final attLoad = await loadAttendancesForPeriodResult(
        _api,
        deviceIds: const [],
        fromDate: rangeStart,
        toDate: rangeEnd,
        dayEndHour: dayEndHour,
        dayEndMinute: dayEndMinute,
        pageSize: 500,
        maxPagesHardCap: 8,
      );

      final shiftsRaw = results[8] as List<dynamic>;
      final shiftTemplates = shiftsRaw
          .whereType<Map>()
          .map((s) => Map<String, dynamic>.from(s))
          .toList();

      final sslResp = results[9] as Map<String, dynamic>;
      final sslData = sslResp['data'];
      final shiftSalaryLevels = (sslData is Map
              ? (sslData['items'] as List? ?? const [])
              : (sslData is List ? sslData : const []))
          .whereType<Map>()
          .map((s) => Map<String, dynamic>.from(s))
          .toList();

      final salaryProfiles = results[10] as List<Map<String, dynamic>>;
      final holidays = results[11] as List<dynamic>;

      final empResp = results[2] as Map<String, dynamic>;
      final employeesList = <Map<String, dynamic>>[];
      if (empResp['isSuccess'] == true && empResp['data'] is Map) {
        employeesList.add(Map<String, dynamic>.from(empResp['data'] as Map));
      }

      final fetchFrom = AttendanceDateRangePresets.fetchFromDate(
        rangeStart,
        dayEndHour: dayEndHour,
        dayEndMinute: dayEndMinute,
      );
      final shiftRecords = computeDailyShiftRecords(
        attendances: attLoad.items,
        fromDate: fetchFrom,
        toDate: rangeEnd,
        shiftTemplates: shiftTemplates,
        shiftSalaryLevels: shiftSalaryLevels,
        salaryProfiles: salaryProfiles,
        holidays: holidays,
        dayEndHour: dayEndHour,
        dayEndMinute: dayEndMinute,
        minHoursForWorkDay: minHoursForWorkDay,
        decimalWorkDayEnabled: decimalWorkDayEnabled,
        standardWorkHours: standardWorkHours,
        employeesList: employeesList,
      )..sort((a, b) => b.date.compareTo(a.date));

      if (mounted) {
        final dashResp = results[0] as Map<String, dynamic>;
        final leavesResp = results[1] as Map<String, dynamic>;
        final commsResp = results[3] as Map<String, dynamic>;
        final rawPunches = List<Attendance>.from(attLoad.items)
          ..sort((a, b) => b.attendanceTime.compareTo(a.attendanceTime));

        setState(() {
          _employeeDashboard =
              (dashResp['data'] as Map<String, dynamic>?) ?? {};
          _employeeRawPunches = rawPunches;
          _employeeRawPunchesExpanded = false;
          _employeeShiftRecords = shiftRecords;
          _todayLeaves = _extractList(leavesResp);
          _communications = _extractList(commsResp);
          if (empResp['isSuccess'] == true && empResp['data'] != null) {
            _employees = [empResp['data']];
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Employee dashboard load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Memoized derived values (recomputed once per _loadAllData)
  List<Map<String, dynamic>> _memoLate = const [];
  List<Map<String, dynamic>> _memoAbsent = const [];
  List<Map<String, dynamic>> _memoNotScheduled = const [];
  int _memoCheckIns = 0;
  int _memoCheckOuts = 0;
  int _memoPresentCount = 0; // distinct employees with ≥1 punch (from raw)
  int _memoCurrentShiftPresentCount = 0; // present in currently-active shift(s)
  List<String> _memoCurrentShiftNames =
      const []; // name(s) of the active shift right now
  int _memoAbsentCount =
      0; // scheduled employees with no punch (daily report − raw)
  int _memoOnlineDevices = 0;
  int _touchedDonutIndex = -1; // index of tapped pie section (-1 = none)
  /// Ngày làm việc hiệu dụng (đã điều chỉnh overnight). Được set trong
  /// _loadAllData() và dùng trong _recomputeMemoized() để windowStart/End
  /// khớp với cửa sổ đã fetch _rawAttendances.
  DateTime? _effectiveDate;

  /// Safely run an API call; log and return [fallback] on error so one failing
  /// endpoint never takes down the entire dashboard batch.
  Future<T> _safe<T>(
      Future<T> Function() call, T fallback, String label) async {
    try {
      return await call().timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('[dashboard] $label failed: $e');
      return fallback;
    }
  }

  Future<void> _loadAllData([DashboardUiCapabilities? caps]) async {
    final c = caps ?? _caps(context);
    if (c.useEmployeeLayout) return;

    setState(() => _isLoading = true);
    final now = DateTime.now();

    // ─── Bước 0 đã được bỏ: day_end_time được đọc từ giá trị cache
    // (_dayEndHour/_dayEndMinute được giữ nguyên giữa các lần load).
    // Phase 2 sẽ cập nhật lại từ API. Phase 3 xử lý overnight correction
    // sau khi Phase 2 hoàn thành. Loại bỏ sequential bottleneck này giúp
    // Phase 1 bắt đầu ngay lập tức, giảm ~200-1000ms thời gian chờ ban đầu.

    DateTime target = _selectedDate ?? now;

    // Overnight adjustment: before day_end_time, "today" still belongs to previous work day.
    if (_selectedDate == null && (_dayEndHour != 0 || _dayEndMinute != 0)) {
      final cutoffMinutes = _dayEndHour * 60 + _dayEndMinute;
      final nowMinutes = now.hour * 60 + now.minute;
      if (nowMinutes < cutoffMinutes) {
        target = now.subtract(const Duration(days: 1));
      }
    }
    // Lưu target đã điều chỉnh overnight để _recomputeMemoized() dùng
    // cùng cửa sổ ngày với data đã fetch (tránh window lệch gây count = 0).
    // Khi _selectedDate != null (xem lịch sử): _effectiveDate = null để
    // _recomputeMemoized() dùng _selectedDate trực tiếp.
    _effectiveDate = _selectedDate == null ? target : null;

    final todayStr =
        '${target.year}-${target.month.toString().padLeft(2, '0')}-${target.day.toString().padLeft(2, '0')}';
    final dayStart = DateTime(target.year, target.month, target.day);
    final dayEnd = DateTime(target.year, target.month, target.day, 23, 59, 59);

    // ─── Cửa sổ fetch attendance: khi có day_end_time = H:M, ngày làm việc D
    // là [D H:M, D+1 H:M). Ví dụ: dayEnd=05:00 → lấy punches 02/05 05:00 → 03/05 05:00.
    // Khi không có cắt ca (00:00), dùng window lịch thông thường [D 00:00, D 23:59].
    final hasDayEnd = _dayEndHour != 0 || _dayEndMinute != 0;
    final attFromDate = hasDayEnd
        ? DateTime(
            target.year, target.month, target.day, _dayEndHour, _dayEndMinute)
        : dayStart;
    final attToDate = hasDayEnd
        ? DateTime(target.year, target.month, target.day + 1, _dayEndHour,
            _dayEndMinute)
        : dayEnd;
    final monthStart = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    final monthEnd =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${lastDay.toString().padLeft(2, '0')}';

    // Phase 1 — minimum data to paint the dashboard. Only 3 calls.
    // Backend applies AppSettings day_end_time for the daily report window.
    final emptyMap = <String, dynamic>{};
    final emptyList = <dynamic>[];

    // Khoảng ngày cho các chip phụ thuộc bộ lọc (Nghỉ phép, Vi phạm):
    // - Preset đơn ngày (today/yesterday/custom): fromDate = toDate = ngày đó
    // - Preset đa ngày (thisWeek/lastWeek/thisMonth/lastMonth):
    //     fromDate = _rangeStart, toDate = target (cuối khoảng, đã cap về today)
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final filterFromStr = _rangeStart != null ? fmt(_rangeStart!) : todayStr;
    final filterToStr = todayStr;

    final criticalFutures = <Future<dynamic>>[];
    if (c.loadDailyReport) {
      criticalFutures.add(_safe(
          () => _api.getDailyAttendanceReport(date: todayStr),
          emptyMap,
          'daily'));
    }
    if (c.loadDevices) {
      criticalFutures.add(
          _safe(() => _api.getDevices(storeOnly: true), emptyList, 'devices'));
    }
    if (c.loadEmployees) {
      criticalFutures.add(
          _safe(() => _api.getEmployeesForSelect(pageSize: 200), emptyList, 'employees'));
    }

    final critical = criticalFutures.isEmpty
        ? <dynamic>[]
        : await Future.wait(criticalFutures);

    if (!mounted) return;
    var ci = 0;
    Map<String, dynamic> dailyData = {};
    if (c.loadDailyReport && critical.isNotEmpty) {
      final dailyResp = critical[ci++] as Map<String, dynamic>;
      dailyData = (dailyResp['data'] as Map<String, dynamic>?) ?? {};
    }
    setState(() {
      _dailyReport = dailyData;
      _dailyReportItems = (dailyData['items'] as List<dynamic>?) ?? [];
      if (c.loadDevices && ci < critical.length) {
        _devices = critical[ci++] as List<dynamic>;
      } else if (!c.loadDevices) {
        _devices = const [];
      }
      if (c.loadEmployees && ci < critical.length) {
        _employees = critical[ci++] as List<dynamic>;
      } else if (!c.loadEmployees) {
        _employees = const [];
      }
      // Xóa dữ liệu raw/derived cũ (từ ngày trước) để Phase 1 dùng fallback
      // daily-report thay vì tính từ data stale → tránh flash sai trước Phase 2.
      _rawAttendances = const [];
      _shiftPairs = const [];
      // Xóa todayLeaves cũ: _absentWithPermission fallback về _todayLeaves khi
      // daily-report rỗng → nếu không clear thì hiện data ngày cũ.
      _todayLeaves = const [];
      _isLoading = false;
      _recomputeMemoized();
    });

    // Phase 2 — chỉ gọi API khi user có quyền module tương ứng.
    final batchKeys = <String>[];
    final batchJobs = <Future<dynamic>>[];
    void queue(String key, Future<dynamic> job) {
      batchKeys.add(key);
      batchJobs.add(job);
    }

    if (c.loadCommunications) {
      queue('comms', _safe(() => _api.getCommunications(page: 1, pageSize: 5),
          emptyMap, 'comms'));
    }
    if (c.loadKpi) {
      queue('kpi-results',
          _safe(() => _api.getKpiResults(), emptyMap, 'kpi-results'));
      queue('kpi-dashboard',
          _safe(() => _api.getKpiDashboard(), emptyMap, 'kpi-dashboard'));
    }
    if (c.loadLeaves) {
      queue('leaves-today', _safe(
          () => _api.getAllLeaves(
              status: 'Approved',
              fromDate: filterFromStr,
              toDate: filterToStr,
              pageSize: 100),
          emptyMap,
          'leaves-today'));
    }
    if (c.loadSchedules) {
      queue('schedules', _safe(
          () => _api.getWorkSchedules(
              fromDate: dayStart, toDate: dayEnd, pageSize: 500),
          emptyMap,
          'schedules'));
    }
    if (c.loadPendingApprovals) {
      queue('pending-leaves', _safe(
          () => _api.getPendingLeaves(pageSize: 100), emptyMap, 'pending-leaves'));
      queue('corrections', _safe(
          () => _api.getAttendanceCorrections(pageSize: 100, status: 0),
          emptyMap,
          'corrections'));
      queue('swaps', _safe(
          () => _api.getShiftSwapsPendingApproval(), emptyMap, 'swaps'));
      queue('mobile-pending', _safe(
          () => _api.getPendingMobileAttendance(), emptyMap, 'mobile-pending'));
    }
    if (c.loadTasks) {
      queue('tasks', _safe(() => _api.getTaskStatistics(), emptyMap, 'tasks'));
    }
    if (c.loadOvertime) {
      queue('ot', _safe(() => _api.getOvertimeStatistics(), emptyMap, 'ot'));
    }
    if (c.loadPenalty) {
      queue('penalty', _safe(
          () => _api.getPenaltyTicketStats(
              fromDate: filterFromStr, toDate: filterToStr),
          emptyMap,
          'penalty'));
    }
    if (c.loadCash) {
      queue('cash', _safe(
          () => _api.getCashTransactionSummary(
              fromDate: monthStart, toDate: monthEnd),
          emptyMap,
          'cash'));
    }
    if (c.loadContracts) {
      queue('contracts',
          _safe(() => _api.getExpiringContracts(), emptyMap, 'contracts'));
    }
    if (c.loadAdvances) {
      queue('advances', _safe(() => _api.getAdvanceRequests(status: 0, pageSize: 100),
          emptyMap, 'advances'));
    }
    if (c.loadBirthdays) {
      queue('birthdays', _safe(() => _api.getBirthdays(), emptyList, 'birthdays'));
    }
    if (c.loadRawAttendances) {
      queue('shifts', _safe(() => _api.getShifts(), emptyList, 'shifts'));
      queue('shift-salary-levels', _safe(
          () => _api.getShiftSalaryLevels(), emptyMap, 'shift-salary-levels'));
      queue('salary-profiles',
          _safe(() => _api.getSalaryProfiles(), emptyList, 'salary-profiles'));
      queue('holidays',
          _safe(() => _api.getHolidaySettings(0), emptyList, 'holidays'));
      queue('day-end',
          _safe(() => _api.getAppSetting('day_end_time'), emptyMap, 'day-end'));
      queue('min-hours-work-day', _safe(
          () => _api.getAppSetting('min_hours_for_work_day'),
          emptyMap,
          'min-hours-work-day'));
      queue('decimal-work-day', _safe(
          () => _api.getAppSetting('decimal_work_day_enabled'),
          emptyMap,
          'decimal-work-day'));
      queue('salary-settings',
          _safe(() => _api.getSalarySettings(), emptyMap, 'salary-settings'));
    }

    final batchResults = batchJobs.isEmpty
        ? <dynamic>[]
        : await Future.wait(batchJobs);
    final byKey = <String, dynamic>{};
    for (var i = 0; i < batchKeys.length; i++) {
      byKey[batchKeys[i]] = batchResults[i];
    }

    // Tải đủ log chấm công (phân trang) sau khi có day_end_time từ batch.
    List<Attendance> phase2RawAttendances = const [];
    if (c.loadRawAttendances) {
      final dayEndResp = (byKey['day-end'] as Map<String, dynamic>?) ?? {};
      var deh = _dayEndHour;
      var dem = _dayEndMinute;
      if (dayEndResp['isSuccess'] == true && dayEndResp['data'] is Map) {
        final dv =
            (dayEndResp['data'] as Map)['value']?.toString() ?? '00:00:00';
        final parts = dv.split(':');
        if (parts.length >= 2) {
          deh = int.tryParse(parts[0]) ?? 0;
          dem = int.tryParse(parts[1]) ?? 0;
        }
      }
      final deviceIds = _devices
          .map((d) => (d is Map ? d['id']?.toString() ?? '' : ''))
          .where((s) => s.isNotEmpty)
          .toList();
      if (deviceIds.isNotEmpty) {
        final attLoad = await loadAttendancesForPeriodResult(
          _api,
          deviceIds: deviceIds,
          fromDate: attFromDate,
          toDate: attToDate,
          dayEndHour: deh,
          dayEndMinute: dem,
          pageSize: 1000,
          parallelPages: 6,
        );
        phase2RawAttendances = attLoad.items;
        if (attLoad.truncated && mounted) {
          appNotification.showWarning(
            title: 'Tổng quan: log chấm công có thể chưa đủ',
            message: tr('Đã tải ${attLoad.items.length} bản ghi. Thu hẹp kỳ xem nếu thiếu ngày cuối.'),
          );
        }
      }
    }

    if (!mounted) return;
    Map<String, dynamic> mapOf(String k) =>
        (byKey[k] as Map<String, dynamic>?) ?? {};

    setState(() {
      _communications =
          c.loadCommunications ? _extractList(mapOf('comms')) : const [];
      _kpiResults = c.loadKpi ? _extractList(mapOf('kpi-results')) : const [];
      _todayLeaves =
          c.loadLeaves ? _extractList(mapOf('leaves-today')) : const [];
      _kpiDashboard = c.loadKpi
          ? (mapOf('kpi-dashboard')['data'] as Map<String, dynamic>?) ?? {}
          : {};
      _todaySchedules =
          c.loadSchedules ? _extractList(mapOf('schedules')) : const [];
      _pendingLeaves = c.loadPendingApprovals
          ? _pendingApprovalItemsOnly(_extractList(mapOf('pending-leaves')))
          : const [];
      _pendingCorrections = c.loadPendingApprovals
          ? _pendingApprovalItemsOnly(_extractList(mapOf('corrections')))
          : const [];
      _pendingSwaps = c.loadPendingApprovals
          ? _pendingApprovalItemsOnly(_extractList(mapOf('swaps')))
          : const [];
      _pendingMobileAttendance = const [];
      _pendingMobileAttendanceCount = 0;
      if (c.loadPendingApprovals) {
        final mp = mapOf('mobile-pending');
        if (mp['isSuccess'] == true && mp['data'] != null) {
          final d = mp['data'];
          final items = d is List ? d : (d['items'] as List? ?? []);
          _pendingMobileAttendance = items;
          _pendingMobileAttendanceCount = items.length;
        }
      }
      _taskStats = c.loadTasks
          ? (mapOf('tasks')['data'] as Map<String, dynamic>?) ?? mapOf('tasks')
          : {};
      _overtimeStats = c.loadOvertime
          ? (mapOf('ot')['data'] as Map<String, dynamic>?) ?? mapOf('ot')
          : {};
      _penaltyStats = c.loadPenalty
          ? (mapOf('penalty')['data'] as Map<String, dynamic>?) ??
              mapOf('penalty')
          : {};
      _cashSummary = c.loadCash
          ? (mapOf('cash')['data'] as Map<String, dynamic>?) ?? mapOf('cash')
          : {};
      _monthlyReport = {};
      if (c.loadContracts) {
        final contractsMap = mapOf('contracts');
        _expiringDocs = (contractsMap['expiring'] as List?) ?? [];
        _expiredContracts = (contractsMap['expired'] as List?) ?? [];
      } else {
        _expiringDocs = const [];
        _expiredContracts = const [];
      }
      _pendingAdvances = c.loadAdvances
          ? _pendingApprovalItemsOnly(_extractList(mapOf('advances')))
          : const [];
      _birthdayEmployees = c.loadBirthdays
          ? (byKey['birthdays'] as List<dynamic>? ?? const [])
          : const [];
      _shiftTemplates = c.loadRawAttendances
          ? (byKey['shifts'] as List<dynamic>? ?? const [])
          : const [];

      if (c.loadRawAttendances) {
        _rawAttendances = phase2RawAttendances;
        _shiftTemplatesTyped =
            _shiftTemplates.whereType<Map<String, dynamic>>().toList();
        final sslMap = mapOf('shift-salary-levels');
        final sslData = sslMap['data'];
        final sslList = sslData is Map
            ? (sslData['items'] as List? ?? const [])
            : (sslData is List ? sslData : const []);
        _shiftSalaryLevels =
            sslList.whereType<Map<String, dynamic>>().toList();
        final spList = byKey['salary-profiles'] as List<dynamic>? ?? const [];
        _salaryProfiles = spList.whereType<Map<String, dynamic>>().toList();
        _holidaysSettings =
            byKey['holidays'] as List<dynamic>? ?? const [];
        final dayEndResp = mapOf('day-end');
        if (dayEndResp['isSuccess'] == true && dayEndResp['data'] is Map) {
          final dv =
              (dayEndResp['data'] as Map)['value']?.toString() ?? '00:00:00';
          final parts = dv.split(':');
          if (parts.length >= 2) {
            _dayEndHour = int.tryParse(parts[0]) ?? 0;
            _dayEndMinute = int.tryParse(parts[1]) ?? 0;
          }
        }
        final minHoursResp = mapOf('min-hours-work-day');
        if (minHoursResp['isSuccess'] == true && minHoursResp['data'] is Map) {
          _minHoursForWorkDay = parseMinHoursForWorkDay(
            appSettingValue:
                (minHoursResp['data'] as Map)['value']?.toString(),
          );
        }
        final decimalResp = mapOf('decimal-work-day');
        if (decimalResp['isSuccess'] == true && decimalResp['data'] is Map) {
          _decimalWorkDayEnabled = parseDecimalWorkDayEnabled(
            appSettingValue:
                (decimalResp['data'] as Map)['value']?.toString(),
          );
        }
        final salaryMap = mapOf('salary-settings');
        if (_minHoursForWorkDay == 0) {
          _minHoursForWorkDay = parseMinHoursForWorkDay(salarySettings: salaryMap);
        }
        if (!_decimalWorkDayEnabled) {
          _decimalWorkDayEnabled =
              parseDecimalWorkDayEnabled(salarySettings: salaryMap);
        }
        _standardWorkHours = parseStandardWorkHours(salarySettings: salaryMap);
      } else {
        _rawAttendances = const [];
        _shiftPairs = const [];
        _shiftRecords = const [];
        _lateShiftEntries = const [];
      }
      _recomputeMemoized();
    });

    // After Phase 2 loads day_end_time, re-fetch daily report for the corrected work day.
    if (c.loadDailyReport &&
        c.loadRawAttendances &&
        _selectedDate == null) {
      final hasDayEndNow = _dayEndHour != 0 || _dayEndMinute != 0;
      if (hasDayEndNow) {
        final nowNow = DateTime.now();
        final cutoffMinutes = _dayEndHour * 60 + _dayEndMinute;
        final nowMinutes = nowNow.hour * 60 + nowNow.minute;
        final correctedDate = nowMinutes < cutoffMinutes
            ? nowNow.subtract(const Duration(days: 1))
            : nowNow;
        final cStr =
            '${correctedDate.year}-${correctedDate.month.toString().padLeft(2, '0')}-${correctedDate.day.toString().padLeft(2, '0')}';
        final corrected = await _safe(
            () => _api.getDailyAttendanceReport(date: cStr),
            <String, dynamic>{},
            'daily-dayend');
        if (mounted) {
          final cData = (corrected['data'] as Map<String, dynamic>?) ?? {};
          setState(() {
            _dailyReport = cData;
            _dailyReportItems = (cData['items'] as List<dynamic>?) ?? [];
            _recomputeMemoized();
          });
        }
      }
    }

    _startBannerTimer();
  }

  /// Recompute all list-scanning derived values in O(n) once per refresh,
  /// instead of re-iterating _dailyReportItems on every widget rebuild.
  void _recomputeMemoized() {
    final late = <Map<String, dynamic>>[];
    final absent = <Map<String, dynamic>>[];
    final notSched = <Map<String, dynamic>>[];
    var ins = 0;
    var outs = 0;

    // ─── Tính "Đi trễ / Về sớm" theo cùng thuật toán với tab "Tổng hợp
    // theo ca". Dashboard không còn nhờ backend daily report cho con số
    // này nữa (backend daily report dùng dữ liệu khác → mismatch).
    // Dùng _effectiveDate (đã điều chỉnh overnight trong _loadAllData)
    // để windowStart/End khớp với cửa sổ đã fetch _rawAttendances.
    final target = _effectiveDate ?? _selectedDate ?? DateTime.now();
    final dayStart = DateTime(target.year, target.month, target.day);
    final dayEnd = DateTime(target.year, target.month, target.day, 23, 59, 59);
    // Cửa sổ thực tế của _rawAttendances: khi có overnight cutoff, window là
    // [D+cutoff, D+1+cutoff). Truyền cho compute* để không bỏ sót punch
    // đêm khuya (May3 00:00-05:00) của NV ca qua đêm.
    final hasCutoffR = _dayEndHour != 0 || _dayEndMinute != 0;
    final attFrom = hasCutoffR
        ? DateTime(
            target.year, target.month, target.day, _dayEndHour, _dayEndMinute)
        : dayStart;
    final attTo = hasCutoffR
        ? DateTime(target.year, target.month, target.day + 1, _dayEndHour,
            _dayEndMinute)
        : dayEnd;

    // ─── Skip các thuật toán nặng O(n²) khi chưa có dữ liệu raw.
    // Sau Phase 1, _rawAttendances luôn rỗng → không cần compute.
    // Chỉ chạy đầy đủ sau Phase 2 khi có dữ liệu thực.
    final List<DailyShiftRecord> shiftRecords;
    if (_rawAttendances.isEmpty) {
      _shiftRecords = const [];
      _lateShiftEntries = const [];
      _shiftPairs = const [];
      shiftRecords = const [];
    } else {
      shiftRecords = computeDailyShiftRecords(
        attendances: _rawAttendances,
        fromDate: attFrom,
        toDate: attTo,
        shiftTemplates: _shiftTemplatesTyped,
        shiftSalaryLevels: _shiftSalaryLevels,
        salaryProfiles: _salaryProfiles,
        holidays: _holidaysSettings,
        dayEndHour: _dayEndHour,
        dayEndMinute: _dayEndMinute,
        minHoursForWorkDay: _minHoursForWorkDay,
        decimalWorkDayEnabled: _decimalWorkDayEnabled,
        standardWorkHours: _standardWorkHours,
      );
      _shiftRecords = shiftRecords;
      _lateShiftEntries = computeDailyShiftLateEntries(
        attendances: _rawAttendances,
        fromDate: attFrom,
        toDate: attTo,
        shiftTemplates: _shiftTemplatesTyped,
        shiftSalaryLevels: _shiftSalaryLevels,
        salaryProfiles: _salaryProfiles,
        dayEndHour: _dayEndHour,
        dayEndMinute: _dayEndMinute,
      );
      _shiftPairs = computeDailyShiftPairs(
        attendances: _rawAttendances,
        fromDate: attFrom,
        toDate: attTo,
        shiftTemplates: _shiftTemplatesTyped,
        shiftSalaryLevels: _shiftSalaryLevels,
        salaryProfiles: _salaryProfiles,
        dayEndHour: _dayEndHour,
        dayEndMinute: _dayEndMinute,
      );
    }
    // empCode → record (để map ngược về _dailyReportItems khi click vào KPI)
    final lateCodes = <String>{};
    for (final r in shiftRecords) {
      if (r.lateMinutes > 0 || r.earlyMinutes > 0) {
        lateCodes.add(r.employeeId);
      }
    }

    for (final raw in _dailyReportItems) {
      if (raw is! Map<String, dynamic>) continue;
      final status = (raw['status'] ?? '').toString().toLowerCase();
      // Map record về _dailyReportItems theo employeeCode để giữ payload
      // gốc cho UI (giữ giao diện danh sách click vào card không đổi).
      final code = (raw['employeeCode'] ?? '').toString();
      if (lateCodes.contains(code)) {
        late.add(raw);
      }
      if (status.contains('vắng') || status.contains('absent')) {
        absent.add(raw);
      }
      if (status.contains('không có lịch') ||
          status.contains('ngày nghỉ') ||
          status.contains('nghỉ lễ')) {
        notSched.add(raw);
      }
    }

    // ─── Vào / Ra: đếm trực tiếp từ raw attendances trong cửa sổ "ngày làm
    // việc". Khi có overnight cutoff (ví dụ 04:00), window của ngày D là
    // [D 04:00, D+1 04:00) — bao gồm toàn bộ giờ làm trong ngày.
    // Khi không có cutoff (00:00), window là [D 00:00, D 23:59].
    final hasCutoff = _dayEndHour != 0 || _dayEndMinute != 0;
    final windowStart = hasCutoff
        ? DateTime(
            target.year, target.month, target.day, _dayEndHour, _dayEndMinute)
        : dayStart;
    final windowEnd = hasCutoff
        ? DateTime(target.year, target.month, target.day + 1, _dayEndHour,
            _dayEndMinute)
        : dayEnd;
    final byEmp = <String, List<DateTime>>{};
    // presentKeys: tất cả các mã định danh của nhân viên đã chấm công
    // trong cửa sổ ngày. Dùng nhiều key để cross-match với daily report.
    final presentKeys = <String>{};
    for (final a in _rawAttendances) {
      final t = a.attendanceTime;
      if (t.isBefore(windowStart) || !t.isBefore(windowEnd)) continue;
      final empKey = (a.employeeId ?? a.pin ?? a.employeeName ?? '').toString();
      if (empKey.isEmpty) continue;
      presentKeys.add(empKey);
      // Also add PIN separately for cross-matching with daily report
      if (a.pin != null && a.pin!.isNotEmpty) presentKeys.add(a.pin!);
      if (a.employeeName != null && a.employeeName!.isNotEmpty) {
        presentKeys.add(a.employeeName!);
      }
      (byEmp[empKey] ??= <DateTime>[]).add(t);
    }
    for (final times in byEmp.values) {
      times.sort();
      for (var i = 0; i < times.length; i++) {
        if (i.isEven) {
          ins++; // 1st, 3rd, ...
        } else {
          outs++; // 2nd, 4th, ...
        }
      }
    }

    // Fallback: nếu shiftRecords có người mà _dailyReportItems chưa có
    // (vd raw attendances đã load nhưng daily report chưa kịp fetch xong),
    // vẫn đẩy dữ liệu cơ bản vào late list để KPI không bị 0.
    if (late.isEmpty && lateCodes.isNotEmpty) {
      for (final r in shiftRecords) {
        if (r.lateMinutes > 0 || r.earlyMinutes > 0) {
          late.add({
            'employeeCode': r.employeeId,
            'employeeName': r.employeeName,
            'lateMinutes': r.lateMinutes,
            'earlyLeaveMinutes': r.earlyMinutes,
            'status': r.status,
          });
        }
      }
    }

    _memoLate = late;
    _memoAbsent = absent;
    _memoNotScheduled = notSched;
    _memoCheckIns = ins;
    _memoCheckOuts = outs;

    // ─── Có mặt = distinct employees from raw (real-time, consistent với Vào/Ra)
    _memoPresentCount = byEmp.length;

    // ─── Có mặt theo ca hiện tại (realtime): tìm các ca đang active lúc now,
    // rồi đếm distinct NV trong _shiftPairs có checkIn và shiftName khớp.
    // Chỉ tính khi đang xem ngày hôm nay (không áp dụng cho ngày lịch sử).
    if (_selectedDate == null && _shiftTemplatesTyped.isNotEmpty) {
      final nowMin = DateTime.now().hour * 60 + DateTime.now().minute;
      final activeNames = <String>{};
      for (final st in _shiftTemplatesTyped) {
        final name = st['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        final sMin = _parseShiftTime(st['startTime']?.toString());
        final eMin = _parseShiftTime(st['endTime']?.toString());
        if (sMin == 0 && eMin == 0) continue;
        // Cho phép cửa sổ rộng ±30 phút trước start để NV vừa vào được tính
        final windowStart = (sMin - 30).clamp(0, 1439);
        final bool active;
        if (sMin <= eMin) {
          // Ca không qua đêm
          active = nowMin >= windowStart && nowMin < eMin;
        } else {
          // Ca qua đêm (ví dụ 22:00-06:00)
          active = nowMin >= windowStart || nowMin < eMin;
        }
        if (active) activeNames.add(name);
      }
      _memoCurrentShiftNames = activeNames.toList();
      if (activeNames.isNotEmpty) {
        final seen = <String>{};
        for (final p in _shiftPairs) {
          if (p.checkIn == null) continue;
          if (!activeNames.contains(p.shiftName)) continue;
          final key = p.employeeCode.isNotEmpty ? p.employeeCode : p.employeeId;
          seen.add(key);
        }
        _memoCurrentShiftPresentCount = seen.length;
      } else {
        // Ngoài giờ làm: hiển thị tổng ngày
        _memoCurrentShiftPresentCount = _memoPresentCount;
      }
    } else {
      // Ngày lịch sử hoặc chưa load shift template: dùng tổng ngày
      _memoCurrentShiftPresentCount = _memoPresentCount;
      _memoCurrentShiftNames = const [];
    }

    // ─── Vắng = nhân viên trong daily report (có lịch) mà KHÔNG có trong raw.
    // Cross-match bằng employeeCode / employeeId / pin (từ nhiều field).
    // _memoAbsent và _memoAbsentCount đều dùng cùng logic để nhất quán.
    if (_rawAttendances.isNotEmpty) {
      final crossAbsent = <Map<String, dynamic>>[];
      for (final raw in _dailyReportItems) {
        if (raw is! Map<String, dynamic>) continue;
        final s = (raw['status'] ?? '').toString().toLowerCase();
        // Bỏ qua nhân viên không có lịch / ngày nghỉ / nghỉ lễ / đã nghỉ phép
        // LƯU Ý: KHÔNG dùng s.contains('phép') vì "Vắng không phép" cũng chứa
        // chữ "phép" → sẽ bị skip nhầm → absent = 0. Chỉ skip "nghỉ phép" cụ thể.
        if (s.contains('không có lịch') ||
            s.contains('ngày nghỉ') ||
            s.contains('nghỉ lễ') ||
            s.contains('nghỉ phép') ||
            s.contains('leave')) {
          continue;
        }
        // Cross-match bằng nhiều identifier để tránh lệch khi employeeCode ≠ pin
        final code = (raw['employeeCode'] ??
                raw['employeeId'] ??
                raw['employeeName'] ??
                '')
            .toString();
        final empId = (raw['employeeId'] ?? '').toString();
        final pin = (raw['pin'] ?? raw['enrollNumber'] ?? '').toString();
        final inRaw = presentKeys.contains(code) ||
            (empId.isNotEmpty && presentKeys.contains(empId)) ||
            (pin.isNotEmpty && presentKeys.contains(pin));
        if (!inRaw) crossAbsent.add(raw);
      }
      _memoAbsent = crossAbsent;
      _memoAbsentCount = crossAbsent.length;
    } else {
      // Fallback khi raw chưa load: dùng status-based list/count.
      _memoAbsentCount = absent.length;
      // _memoAbsent đã được set = absent (status-based) ở trên.
    }

    // Online device count — cached (recomputed when _devices changes).
    var online = 0;
    for (final d in _devices) {
      if (d is Map && _isDeviceOnline(d)) online++;
    }
    _memoOnlineDevices = online;
  }

  /// Online-device heuristic — copy EXACT logic from
  /// `device_management_settings_screen.dart` so the Dashboard and the HRM
  /// Settings screen always show the same counts.
  bool _isDeviceOnline(Map d) {
    // Ưu tiên dùng trạng thái do backend tính sẵn
    final status = d['deviceStatus']?.toString().toLowerCase();
    if (status != null && status.isNotEmpty) {
      return status == 'online';
    }
    // Fallback: tính từ lastOnline (server lưu UTC, phải parse đúng)
    final lastOnline = d['lastOnline'];
    if (lastOnline == null) return false;
    try {
      final raw = lastOnline.toString();
      final dateStr =
          (raw.contains('Z') || raw.contains('+')) ? raw : '${raw}Z';
      final dt = DateTime.parse(dateStr);
      return DateTime.now().toUtc().difference(dt).inMinutes < 5;
    } catch (_) {
      return false;
    }
  }

  List<dynamic> _extractList(Map<String, dynamic> data) {
    final d = data['data'];
    if (d is List) return d;
    if (d is Map) {
      return d['items'] ?? d['data'] ?? d['results'] ?? d['records'] ?? [];
    }
    return [];
  }

  // ===== COMPUTED DATA (from Daily Attendance Report) =====
  // These read pre-computed memoized lists populated by _recomputeMemoized().
  List<dynamic> get _todayEmployees => _dailyReportItems;
  List<dynamic> get _lateEmployees => _memoLate;
  List<dynamic> get _absentEmployeesList => _memoAbsent;

  int get _totalEmployees {
    // Match the detail list length.
    if (_dailyReportItems.isNotEmpty) return _dailyReportItems.length;
    final fromReport = ((_dailyReport['totalEmployees'] ?? 0) as num).toInt();
    return fromReport > 0 ? fromReport : _employees.length;
  }

  // Chip counts từ raw attendances (nhất quán với Vào/Ra)
  // Khi xem hôm nay: ưu tiên đếm theo ca đang active (realtime).
  // Khi xem ngày lịch sử: tổng toàn ngày.
  // Khi raw chưa load: dùng backend `present` từ _dailyReport để tránh
  // flash "0 có mặt" trong lúc chờ Phase 2.
  int get _presentCount => _rawAttendances.isNotEmpty
      ? _memoCurrentShiftPresentCount
      : (_dailyReport['present'] is num
          ? (_dailyReport['present'] as num).toInt()
          : _kpiDetailData('present').length);

  /// Label phụ cho chip "Có mặt" — tên ca đang active (nếu có).
  String get _presentShiftLabel {
    if (_memoCurrentShiftNames.isEmpty) return 'Có mặt';
    if (_memoCurrentShiftNames.length == 1) return _memoCurrentShiftNames.first;
    // Nhiều ca active (hiếm): lấy 2 tên đầu
    return _memoCurrentShiftNames.take(2).join(' · ');
  }

  int get _absentCount => _dailyReportItems.isNotEmpty
      ? _memoAbsentCount
      : _kpiDetailData('absent').length;
  int get _lateCount => _lateShiftEntries.isNotEmpty
      ? _lateShiftEntries.length
      : _memoLate.length;
  int get _checkIns => _memoCheckIns;
  int get _checkOuts => _memoCheckOuts;
  double get _attendanceRate {
    // Khi raw attendances đã load: tính live từ present/total.
    if (_rawAttendances.isNotEmpty) {
      final denom = _totalEmployees;
      if (denom <= 0) return 0;
      return (_presentCount / denom).clamp(0.0, 1.0) * 100.0;
    }
    // Khi chưa có raw: ưu tiên dùng attendanceRate từ backend daily report
    // (đã tính đúng denominator = scheduledCount - onLeave).
    final fromReport = _dailyReport['attendanceRate'];
    if (fromReport is num && fromReport >= 0) {
      final v = fromReport.toDouble();
      // Backend trả về percentage (0–100). Nếu server trả về fraction (0–1),
      // nhân với 100 để nhất quán hiển thị.
      return (v > 1.0 ? v : v * 100.0).clamp(0.0, 100.0);
    }
    // Fallback: tính thủ công từ _presentCount / _totalEmployees.
    final denom = _totalEmployees;
    if (denom <= 0) return 0;
    return (_presentCount / denom).clamp(0.0, 1.0) * 100.0;
  }

  int get _onlineDevices => _memoOnlineDevices;
  int get _totalDevices => _devices.length;

  List<Map<String, dynamic>> get _todayBirthdays {
    final today = DateTime.now();
    final bdays = <Map<String, dynamic>>[];
    final src = _birthdayEmployees.isNotEmpty ? _birthdayEmployees : _employees;
    for (final e in src) {
      if (e is Map<String, dynamic>) {
        final dob = e['dateOfBirth'] ?? e['birthday'];
        if (dob != null) {
          try {
            final d = DateTime.parse(dob.toString());
            if (d.month == today.month && d.day == today.day) {
              bdays.add(e);
            }
          } catch (_) {}
        }
      }
    }
    return bdays;
  }

  List<Map<String, dynamic>> get _monthlyBirthdays {
    final today = DateTime.now();
    final monthly = <Map<String, dynamic>>[];
    final src = _birthdayEmployees.isNotEmpty ? _birthdayEmployees : _employees;
    for (final e in src) {
      if (e is Map<String, dynamic>) {
        final dob = e['dateOfBirth'] ?? e['birthday'];
        if (dob != null) {
          try {
            final d = DateTime.parse(dob.toString());
            if (d.month == today.month) {
              // Skip today's birthdays (already shown separately)
              if (d.day == today.day) continue;
              monthly.add({...e, '_birthdayDay': d.day});
            }
          } catch (_) {}
        }
      }
    }
    monthly.sort((a, b) =>
        (a['_birthdayDay'] as int).compareTo(b['_birthdayDay'] as int));
    return monthly;
  }

  /// Items shown in the rotating top banner: birthday + doc expiry + pending counts
  List<Map<String, dynamic>> get _bannerItems {
    final items = <Map<String, dynamic>>[];

    // Today's birthdays
    for (final e in _todayBirthdays) {
      final ln = (e['lastName'] ?? '').toString().trim();
      final fn = (e['firstName'] ?? '').toString().trim();
      final full = (e['fullName'] ?? '').toString().trim();
      final name = full.isNotEmpty
          ? full
          : ([ln, fn].where((s) => s.isNotEmpty).join(' '));
      items.add({
        'icon': '🎂',
        'color': 0xFFEC4899,
        'text': 'Sinh nhật hôm nay: $name',
        'kind': 'birthday_detail',
      });
    }

    // Expiring documents (≤ 30 days)
    final now = DateTime.now();
    for (final d in _expiringDocs) {
      final expStr = (d['expiryDate'] ?? d['endDate'] ?? '').toString();
      final exp = DateTime.tryParse(expStr);
      if (exp != null) {
        final days = exp.difference(now).inDays;
        if (days >= 0 && days <= 30) {
          final empName =
              (d['employeeName'] ?? d['fullName'] ?? d['name'] ?? '')
                  .toString();
          final docType =
              (d['contractType'] ?? d['documentType'] ?? d['type'] ?? 'HĐ')
                  .toString();
          items.add({
            'icon': '📄',
            'color': 0xFFEA580C,
            'text':
                'Sắp hết hạn ($days ngày): $docType${empName.isNotEmpty ? ' – $empName' : ''}',
            'kind': 'docs_detail',
          });
        }
      }
    }

    // Pending approvals summary
    final pendingTotal = _pendingLeaves.length +
        _pendingCorrections.length +
        _pendingSwaps.length +
        _pendingAdvances.length +
        _pendingMobileAttendanceCount;
    if (pendingTotal > 0) {
      items.add({
        'icon': '⏳',
        'color': 0xFFEF4444,
        'text': 'Có $pendingTotal yêu cầu chờ duyệt',
        'kind': 'pending_all',
      });
    }

    return items;
  }

  /// Cửa sổ ngày làm việc: [D+day_end_time, D+1+day_end_time).
  ({DateTime target, DateTime windowStart, DateTime windowEnd})
      _attendanceDayWindow() {
    final target = _effectiveDate ?? _selectedDate ?? DateTime.now();
    final dayStart = DateTime(target.year, target.month, target.day);
    final dayEnd = DateTime(target.year, target.month, target.day, 23, 59, 59);
    final hasCutoff = _dayEndHour != 0 || _dayEndMinute != 0;
    final windowStart = hasCutoff
        ? DateTime(
            target.year, target.month, target.day, _dayEndHour, _dayEndMinute)
        : dayStart;
    final windowEnd = hasCutoff
        ? DateTime(target.year, target.month, target.day + 1, _dayEndHour,
            _dayEndMinute)
        : dayEnd;
    return (target: target, windowStart: windowStart, windowEnd: windowEnd);
  }

  bool _isInAttendanceWindow(
      DateTime t, DateTime windowStart, DateTime windowEnd) {
    return !t.isBefore(windowStart) && t.isBefore(windowEnd);
  }

  String _attendanceEmployeeKey(Attendance a) =>
      (a.employeeId ?? a.pin ?? a.employeeName ?? '').toString();

  /// id → thứ tự lần chấm (0-based) trong ngày làm việc, sort tăng dần/NV.
  Map<String, int> _computePunchIndexInDay() {
    final window = _attendanceDayWindow();
    final empPunches = <String, List<Attendance>>{};
    for (final a in _rawAttendances) {
      if (!_isInAttendanceWindow(
          a.attendanceTime, window.windowStart, window.windowEnd)) {
        continue;
      }
      final key = _attendanceEmployeeKey(a);
      if (key.isEmpty) continue;
      (empPunches[key] ??= <Attendance>[]).add(a);
    }
    final punchIndex = <String, int>{};
    for (final list in empPunches.values) {
      list.sort((a, b) => a.attendanceTime.compareTo(b.attendanceTime));
      final workList =
          list.where((a) => !Attendance.isTravelAttendanceState(a.attendanceState)).toList();
      for (var i = 0; i < workList.length; i++) {
        punchIndex[workList[i].id] = i;
      }
    }
    return punchIndex;
  }

  List<Attendance> _punchesInDayWindow({bool descending = false}) {
    final window = _attendanceDayWindow();
    final punches = _rawAttendances
        .where((a) => _isInAttendanceWindow(
            a.attendanceTime, window.windowStart, window.windowEnd))
        .toList();
    punches.sort((a, b) => descending
        ? b.attendanceTime.compareTo(a.attendanceTime)
        : a.attendanceTime.compareTo(b.attendanceTime));
    return punches;
  }

  List<Map<String, dynamic>> get _absentWithPermission {
    // On-leave employees from daily report (status = "Nghỉ phép")
    final fromReport =
        _dailyReportItems.whereType<Map<String, dynamic>>().where((e) {
      final status = (e['status'] ?? '').toString().toLowerCase().trim();
      // Match "Nghỉ phép" / "leave" — but EXCLUDE:
      //   - "Ngày nghỉ" (day off, not a leave application)
      //   - "Vắng không phép" / "Vắng mặt" (absent WITHOUT permission, even though
      //     the literal text contains "phép" / "không phép")
      if (status.contains('vắng') ||
          status.contains('không phép') ||
          status.contains('ngày nghỉ') ||
          status.contains('nghỉ lễ') ||
          status.contains('absent')) {
        return false;
      }
      return status == 'nghỉ phép' ||
          status.contains('leave') ||
          status.contains('phép');
    }).toList();
    // Also include from leave API if report has none
    final source = fromReport.isNotEmpty
        ? fromReport
        : _todayLeaves.whereType<Map<String, dynamic>>().toList();
    // Dedupe by employee identity — leave API may return one row per day for a multi-day leave
    // or report + leave fallback overlap → caused names appearing twice.
    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final e in source) {
      final key = (e['employeeId'] ??
              e['employeeUserId'] ??
              e['employeeCode'] ??
              e['userId'] ??
              e['id'] ??
              e['employeeName'] ??
              '')
          .toString();
      if (key.isEmpty || seen.add(key)) {
        unique.add(e);
      }
    }
    return unique;
  }

  List<Map<String, dynamic>> get _absentWithoutPermission => _memoAbsent;

  /// Employees not scheduled today (no work schedule or day off)
  List<Map<String, dynamic>> get _notScheduledEmployees => _memoNotScheduled;

  /// Number of employees scheduled to work today
  int get _scheduledCount {
    return _totalEmployees - _notScheduledEmployees.length;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PermissionProvider>(
      builder: (context, perm, _) {
        if (perm.isLoaded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _resolveDashboardMode(context);
          });
        }

        if (_isLoading) {
          return Scaffold(
            backgroundColor: HrmPageChrome.background,
            body: LoadingWidget(message: _l10n.loadingOverview),
          );
        }

        final authUser = Provider.of<AuthProvider>(context, listen: false);
        final caps = DashboardUiCapabilities.from(
          perm,
          role: authUser.userRole,
          allowedModules: authUser.user?.allowedModules,
        );

        final isMobile = MediaQuery.of(context).size.width < 768;
        final body = _isEmployee
            ? _buildEmployeeDashboard(caps, isMobile: isMobile)
            : isMobile
                ? _buildMobileManagerDashboard(caps)
                : _wrapDashboardScroll(RefreshIndicator(
                    onRefresh: () => _loadAllData(caps),
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _dashboardSection(_buildHeader()),
                          const SizedBox(height: 14),
                          if (_bannerItems.isNotEmpty) ...[
                            _dashboardSection(_buildRollingBanner()),
                            const SizedBox(height: 10),
                          ],
                          if (caps.isOverviewOnly) ...[
                            _dashboardSection(_buildOverviewOnlyCard()),
                            const SizedBox(height: 16),
                          ],
                          if (caps.showQuickActions) ...[
                            _dashboardSection(_buildQuickActions(caps)),
                            const SizedBox(height: 16),
                          ],
                          if (caps.showAttendanceHero) ...[
                            _dashboardSection(_buildHeroOverview(caps)),
                            const SizedBox(height: 14),
                          ],
                          if (caps.showShiftSchedule) ...[
                            _dashboardSection(_buildTodayShiftSchedule()),
                            const SizedBox(height: 20),
                          ],
                          if (caps.loadPendingApprovals &&
                              caps.insightPending) ...[
                            _dashboardSection(_buildPendingApprovalsCard()),
                            const SizedBox(height: 16),
                          ],
                          if (caps.showInsightSection &&
                              !caps.showAttendanceHero) ...[
                            _buildInsightSectionTitle(),
                            const SizedBox(height: 10),
                            _dashboardSection(_buildInsightChipsRow(caps)),
                            const SizedBox(height: 20),
                          ],
                          if (caps.showMainGrid)
                            _dashboardSection(_buildMainGrid(caps)),
                        ],
                      ),
                    ),
                  ));

        return Scaffold(
          backgroundColor:
              isMobile ? PosTheme.background : AppColors.scaffold,
          body: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: isMobile
                ? body
                : Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth:
                            Responsive.maxContentWidth(context, dashboard: true) ??
                                1440,
                      ),
                      child: body,
                    ),
                  ),
          ),
          floatingActionButton: caps.showAiFab
              ? FloatingActionButton.extended(
                  onPressed: () => showAiAssistant(context),
                  backgroundColor: AppColors.secondary,
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: Text(tr('Trợ lý AI')),
                  tooltip: tr('Mở trợ lý ảo HRM'),
                )
              : null,
        );
      },
    );
  }

  Widget _buildOverviewOnlyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppColors.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Quyền tổng quan'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(tr('Tài khoản chỉ có quyền xem Tổng quan. Dùng Trang chủ để mở các module khác đã được cấp, hoặc liên hệ quản trị để bổ sung gói quyền (Chấm công, Thiết lập HRM…).'),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () =>
                      NavigationNotifier.goTo(NavigationNotifier.home),
                  icon: const Icon(Icons.home_outlined, size: 18),
                  label: Text(tr('Mở Trang chủ')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _dashboardProfileSubtitle() {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    if (user == null) return 'Chi nhánh';
    if (user.department != null && user.department!.trim().isNotEmpty) {
      return user.department!.trim();
    }
    if (user.position != null && user.position!.trim().isNotEmpty) {
      return user.position!.trim();
    }
    if (user.email.isNotEmpty) return user.email;
    return 'Chi nhánh';
  }

  Widget _buildMobileManagerDashboard(DashboardUiCapabilities caps) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final fullName = auth.user?.fullName ?? 'User';

    return _wrapDashboardScroll(RefreshIndicator(
      color: PosTheme.kiotBlue,
      onRefresh: () => _loadAllData(caps),
      child: ListView(
        controller: _scrollController,
        cacheExtent: 800,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        children: [
          _dashboardSection(PosMobileProfileCard(
            name: fullName,
            subtitle: _dashboardProfileSubtitle(),
          )),
          const SizedBox(height: 12),
          if (_bannerItems.isNotEmpty) ...[
            _dashboardSection(_buildRollingBanner()),
            const SizedBox(height: 12),
          ],
          if (caps.isOverviewOnly) ...[
            _dashboardSection(_buildOverviewOnlyCard()),
            const SizedBox(height: 12),
          ],
          if (caps.showQuickActions) ...[
            _dashboardSection(_buildQuickActions(caps, mobileGrid: true)),
            const SizedBox(height: 12),
          ],
          if (caps.showInsightSection) ...[
            _dashboardSection(_buildInsightChipsRow(caps, mobileGrid: true)),
            const SizedBox(height: 12),
          ],
          if (caps.showAttendanceHero) ...[
            _dashboardSection(_buildHeroOverview(caps, mobileGrid: true)),
            const SizedBox(height: 12),
          ],
          if (caps.showShiftSchedule) ...[
            _dashboardSection(_buildTodayShiftSchedule()),
            const SizedBox(height: 12),
          ],
          if (caps.loadPendingApprovals && caps.insightPending) ...[
            _dashboardSection(_buildPendingApprovalsCard()),
            const SizedBox(height: 12),
          ],
          if (caps.showMainGrid) _dashboardSection(_buildMainGrid(caps)),
        ],
      ),
    ));
  }

  Widget _buildInsightSectionTitle() {
    return Text(tr('Chỉ số nhân sự & vận hành'),
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF475569),
      ),
    );
  }

  /// Cùng palette banner chào như [main_layout] Trang chủ.
  ({String greeting, IconData icon, Color accent}) _greetingForTime() {
    if (_now.hour < 12) {
      return (
        greeting: _l10n.goodMorning,
        icon: Icons.wb_sunny_rounded,
        accent: const Color(0xFFFCD34D),
      );
    }
    if (_now.hour < 18) {
      return (
        greeting: _l10n.goodAfternoon,
        icon: Icons.wb_twilight_rounded,
        accent: const Color(0xFFFB923C),
      );
    }
    return (
      greeting: _l10n.goodEvening,
      icon: Icons.nightlight_round,
      accent: const Color(0xFFA78BFA),
    );
  }

  BoxDecoration get _homeGreetingBannerDecoration => BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HrmPageChrome.primaryNavy,
            HrmPageChrome.primaryNavy.withValues(alpha: 0.85),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: HrmPageChrome.primaryNavy.withValues(alpha: 0.3),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      );

  // ===================== HEADER =====================
  Widget _buildHeader() {
    final greet = _greetingForTime();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final fullName = auth.user?.fullName ?? 'User';
    final role = auth.userRole;
    final initials = _initialsOf(fullName);
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');

    return Container(
      decoration: _homeGreetingBannerDecoration,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.12),
              border: Border.all(color: Colors.white24, width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              tr(initials),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(greet.icon, color: greet.accent, size: 18),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        tr('${greet.greeting},'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  tr(fullName),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _headerBadge(role),
                    const SizedBox(width: 6),
                    _headerBadge(
                        '${_weekday(_now.weekday)} • ${_now.day}/${_now.month}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr('$hh:$mm'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  tr(_now.year.toString()),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _initialsOf(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts[parts.length - 2].characters.first +
            parts.last.characters.first)
        .toUpperCase();
  }

  Widget _headerBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        tr(text),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // ===================== ROLLING BANNER =====================
  void _onBannerTap(Map<String, dynamic> item) {
    final kind = (item['kind'] ?? '').toString();
    if (kind.isEmpty) return;
    switch (kind) {
      case 'birthday_detail':
        _showInsightDetail(_InsightChipData(
            Icons.cake_outlined,
            'Sinh nhật',
            '${_todayBirthdays.length}',
            const Color(0xFFEC4899),
            'birthday_detail'));
        break;
      case 'docs_detail':
        _showInsightDetail(_InsightChipData(
            Icons.assignment_late_outlined,
            'HĐ hết hạn',
            '${_expiringDocs.length + _expiredContracts.length}',
            const Color(0xFFEA580C),
            'docs_detail'));
        break;
      case 'pending_all':
        final pendingTotal = _pendingLeaves.length +
            _pendingCorrections.length +
            _pendingSwaps.length +
            _pendingAdvances.length +
            _pendingMobileAttendanceCount;
        _showInsightDetail(_InsightChipData(
            Icons.pending_actions_outlined,
            'Chờ duyệt',
            '$pendingTotal',
            const Color(0xFFEF4444),
            'pending_all'));
        break;
    }
  }

  Widget _buildRollingBanner() {
    final items = _bannerItems;
    if (items.isEmpty) return const SizedBox.shrink();

    final idx = _bannerIndex.clamp(0, items.length - 1);
    final item = items[idx];
    final color = Color(item['color'] as int);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: child,
      ),
      child: GestureDetector(
        onTap: () => _onBannerTap(item),
        child: Container(
        key: ValueKey(idx),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Row(
          children: [
            Text(tr(item['icon'] as String), style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                tr(item['text'] as String),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (items.length > 1) ...[
              const SizedBox(width: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(
                    items.length,
                    (i) => Container(
                          width: i == idx ? 12 : 5,
                          height: 5,
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          decoration: BoxDecoration(
                            color: i == idx
                                ? color
                                : color.withValues(alpha: 0.30),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        )),
              ),
            ],
            const Icon(Icons.chevron_right, size: 16, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
      ),
    );
  }

  // ===================== QUICK ACTIONS =====================
  Widget _buildQuickActions(DashboardUiCapabilities caps,
      {bool mobileGrid = false}) {
    final actions = <_QuickAction>[
      if (caps.quickLeave)
        _QuickAction(Icons.beach_access_rounded, 'Xin nghỉ',
            const Color(0xFFF59E0B), () => NavigationNotifier.goToLeaves()),
      if (caps.quickShiftSwap)
        _QuickAction(Icons.swap_horiz_rounded, 'Đổi ca', const Color(0xFF8B5CF6),
            () {
          final perm =
              Provider.of<PermissionProvider>(context, listen: false);
          if (perm.canView('ShiftSwap')) {
            NavigationNotifier.goToShiftSwap();
          } else {
            NavigationNotifier.scheduleApprovalTab.value = 3;
            NavigationNotifier.goTo(NavigationNotifier.scheduleApproval);
          }
        }),
      if (caps.quickPayroll)
        _QuickAction(Icons.payments_rounded, 'Phiếu lương',
            const Color(0xFF06B6D4), () {
          final perm =
              Provider.of<PermissionProvider>(context, listen: false);
          NavigationNotifier.goToPayModule(
            preferPayslip: perm.canView('Payslip'),
          );
        }),
      if (caps.quickCommunication)
        _QuickAction(
            Icons.campaign_rounded,
            'Truyền thông',
            const Color(0xFFEC4899),
            () => NavigationNotifier.goToCommunication()),
      if (caps.quickAi)
        _QuickAction(Icons.auto_awesome_rounded, 'Trợ lý AI',
            const Color(0xFF6366F1), () => showAiAssistant(context)),
    ];

    if (actions.isEmpty) return const SizedBox.shrink();

    if (mobileGrid) {
      return PosMobileHubSectionGrid(
        title: 'Truy cập nhanh',
        items: actions
            .map(
              (a) => PosMobileHubGridItem(
                label: a.label,
                icon: a.icon,
                onTap: a.onTap,
              ),
            )
            .toList(),
      );
    }

    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: actions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _buildQuickActionTile(actions[i]),
      ),
    );
  }

  Widget _buildQuickActionTile(_QuickAction a) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: a.onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 84,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: a.color.withValues(alpha: 0.18)),
            boxShadow: [
              BoxShadow(
                color: a.color.withValues(alpha: 0.12),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [a.color, Color.lerp(a.color, Colors.white, 0.35)!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: a.color.withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(a.icon, color: Colors.white, size: 20),
              ),
              const SizedBox(height: 6),
              Text(
                tr(a.label),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===================== HERO OVERVIEW (donut + KPI + date filter) =====================
  Widget _buildHeroOverview(DashboardUiCapabilities caps,
      {bool mobileGrid = false}) {
    final rate = _attendanceRate.clamp(0, 100).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF8FAFC), Color(0xFFEFF3F8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E9F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              const Icon(Icons.analytics_outlined,
                  size: 18, color: HrmPageChrome.primaryNavy),
              const SizedBox(width: 6),
              Expanded(
                child: Text(tr('Tổng quan chấm công'),
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: HrmPageChrome.primaryNavy),
                ),
              ),
              if (_rangeLabel().isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: HrmPageChrome.primaryNavy.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    tr(_rangeLabel()),
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: HrmPageChrome.primaryNavy),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // Filter row — own line, horizontally scrollable so nothing is cut off
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildPresetChip('today', 'Hôm nay'),
                const SizedBox(width: 6),
                _buildPresetChip('yesterday', 'Hôm qua'),
                const SizedBox(width: 6),
                _buildPresetChip('thisWeek', 'Tuần này'),
                const SizedBox(width: 6),
                _buildPresetChip('lastWeek', 'Tuần trước'),
                const SizedBox(width: 6),
                _buildPresetChip('thisMonth', 'Tháng này'),
                const SizedBox(width: 6),
                _buildPresetChip('lastMonth', 'Tháng trước'),
                const SizedBox(width: 6),
                InkWell(
                  onTap: _pickCustomDate,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _presetKey == 'custom'
                          ? HrmPageChrome.primaryNavy
                          : Colors.white,
                      border: Border.all(
                          color: _presetKey == 'custom'
                              ? HrmPageChrome.primaryNavy
                              : const Color(0xFFE4E9F0)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_month,
                            size: 14,
                            color: _presetKey == 'custom'
                                ? Colors.white
                                : const Color(0xFF475569)),
                        const SizedBox(width: 4),
                        Text(tr('Lựa chọn khác'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _presetKey == 'custom'
                                ? Colors.white
                                : const Color(0xFF475569),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final useSideBySide = constraints.maxWidth >= 960;
              final donutCard = _buildDonutCard(rate);
              final tiles = _buildHeroKpiTiles();
              if (useSideBySide) {
                // Row + CrossAxisAlignment.start — tránh Stack Overflow từ IntrinsicHeight.
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 272, child: donutCard),
                    const SizedBox(width: 14),
                    Expanded(child: tiles),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  donutCard,
                  const SizedBox(height: 12),
                  tiles,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          if (caps.showInsightSection && !mobileGrid) ...[
            const Divider(height: 1, color: Color(0xFFE4E9F0)),
            const SizedBox(height: 12),
            Text(tr('Chỉ số nhân sự & vận hành'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 10),
            _buildInsightChipsRow(caps, mobileGrid: mobileGrid),
          ],
        ],
      ),
    );
  }

  // ===================== TODAY SHIFT SCHEDULE =====================
  Widget _buildTodayShiftSchedule() {
    // ── 1. scheduleByShift: shiftName → List of schedule rows ───────────────
    final scheduledByShift = <String, List<Map<String, dynamic>>>{};
    for (final s in _todaySchedules.whereType<Map<String, dynamic>>()) {
      if (s['isDayOff'] == true) continue;
      final shiftName = (s['shiftName'] ?? '').toString();
      if (shiftName.isEmpty) continue;
      (scheduledByShift[shiftName] ??= []).add(s);
    }

    // ── 2. attendedByShift: shiftName → List<DailyShiftPair> (checked-in) ───
    // Dedup: 1 NV chấm nhiều lần → nhiều pairs cùng shift → chỉ giữ pair đầu tiên
    final attendedByShift = <String, List<DailyShiftPair>>{};
    final seenEmpPerShift = <String, Set<String>>{};
    for (final p in _shiftPairs) {
      if (p.checkIn == null) continue;
      final shiftKey = p.shiftName.isNotEmpty ? p.shiftName : 'Không rõ';
      final empKey = p.employeeId.isNotEmpty ? p.employeeId : p.employeeCode;
      final seenSet = (seenEmpPerShift[shiftKey] ??= <String>{});
      if (!seenSet.add(empKey)) continue; // đã có → bỏ qua duplicate
      (attendedByShift[shiftKey] ??= []).add(p);
    }

    // ── 3. Union of shifts to display ───────────────────────────────────────
    final allShiftNames = <String>{}
      ..addAll(scheduledByShift.keys)
      ..addAll(attendedByShift.keys);

    if (allShiftNames.isEmpty) return const SizedBox.shrink();

    // ── 4. Dept lookup from _dailyReportItems (by name + code) ───────────────
    final nameToReport = <String, Map<String, dynamic>>{};
    final codeToReport = <String, Map<String, dynamic>>{};
    for (final r in _dailyReportItems.whereType<Map<String, dynamic>>()) {
      final nm = (r['employeeName'] ?? '').toString().toLowerCase().trim();
      if (nm.isNotEmpty) nameToReport.putIfAbsent(nm, () => r);
      final cd = (r['employeeCode'] ?? r['employeeId'] ?? '').toString();
      if (cd.isNotEmpty) codeToReport.putIfAbsent(cd, () => r);
    }

    // Helper: build employee card list from schedule rows (for "Lịch"/"Vắng")
    List<Map<String, dynamic>> scheduleEmpCards(
        List<Map<String, dynamic>> rows) {
      return rows.map((s) {
        final name = (s['employeeName'] ?? s['fullName'] ?? '').toString();
        final code =
            (s['employeeCode'] ?? s['employeeUserId'] ?? '').toString();
        // Try to enrich with dept from daily report
        final r =
            codeToReport[code] ?? nameToReport[name.toLowerCase().trim()] ?? s;
        final dept = (r['departmentName'] ?? r['department'] ?? '').toString();
        return {
          'name': name.isNotEmpty ? name : code,
          'dept': dept.isNotEmpty ? dept : 'Không có phòng ban',
        };
      }).toList();
    }

    // Helper: build employee card list from shiftPairs (for "Có mặt")
    List<Map<String, dynamic>> attendedEmpCards(List<DailyShiftPair> pairs) {
      return pairs.map((p) {
        final name = p.employeeName.isNotEmpty && p.employeeName != '-'
            ? p.employeeName
            : '';
        final code = p.employeeCode.isNotEmpty ? p.employeeCode : p.employeeId;
        final r =
            nameToReport[name.toLowerCase().trim()] ?? codeToReport[code] ?? {};
        final dept = (r['departmentName'] ?? r['department'] ?? '').toString();
        return {
          'name': name.isNotEmpty ? name : code,
          'dept': dept.isNotEmpty ? dept : 'Không có phòng ban',
          'checkIn': p.checkIn != null ? _formatTime(p.checkIn!) : '',
        };
      }).toList();
    }

    void showShiftEmpList(
        String title, Color color, List<Map<String, dynamic>> empCards) {
      final deptOrder = <String>[];
      final byDept = <String, List<Map<String, dynamic>>>{};
      for (final e in empCards) {
        final dept = e['dept'] as String;
        if (!byDept.containsKey(dept)) {
          deptOrder.add(dept);
          byDept[dept] = [];
        }
        byDept[dept]!.add(e);
      }
      deptOrder.sort((a, b) => byDept[b]!.length.compareTo(byDept[a]!.length));
      for (final list in byDept.values) {
        list.sort(
            (a, b) => (a['name'] as String).compareTo(b['name'] as String));
      }

      showAppSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (_, sc) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 10),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.groups_rounded, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(title),
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A))),
                      Text(tr('${empCards.length} NV · ${deptOrder.length} phòng ban'),
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  )),
                  IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx)),
                ]),
              ),
              const Divider(height: 1),
              Expanded(
                child: empCards.isEmpty
                    ? Center(
                        child: Text(tr('Không có nhân viên'),
                            style: TextStyle(color: Colors.grey.shade500)))
                    : ListView.builder(
                        controller: sc,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        itemCount: deptOrder.length,
                        itemBuilder: (_, di) {
                          final dept = deptOrder[di];
                          final emps = byDept[dept]!;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                          color: color.withValues(alpha: 0.25)),
                                    ),
                                    child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.business_rounded,
                                              size: 12, color: color),
                                          const SizedBox(width: 4),
                                          Text(tr(dept),
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: color)),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(10)),
                                            child: Text(tr('${emps.length}'),
                                                style: TextStyle(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                    color: color)),
                                          ),
                                        ]),
                                  ),
                                  const SizedBox(height: 6),
                                  ...emps.map((e) => Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 5),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.04),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                              color: color.withValues(
                                                  alpha: 0.12)),
                                        ),
                                        child: Row(children: [
                                          CircleAvatar(
                                            radius: 14,
                                            backgroundColor:
                                                color.withValues(alpha: 0.15),
                                            child: Text(
                                              tr((e['name'] as String).isNotEmpty
                                                  ? (e['name'] as String)[0]
                                                      .toUpperCase()
                                                  : '?'),
                                              style: TextStyle(
                                                  color: color,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 11),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(tr(e['name'] as String),
                                                style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 13),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis),
                                          ),
                                          if ((e['checkIn'] as String? ?? '')
                                              .isNotEmpty) ...[
                                            const Icon(Icons.login,
                                                size: 11,
                                                color: Color(0xFF22C55E)),
                                            const SizedBox(width: 2),
                                            Text(tr(e['checkIn'] as String),
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xFF16A34A),
                                                    fontWeight:
                                                        FontWeight.w600)),
                                          ],
                                        ]),
                                      )),
                                ]),
                          );
                        },
                      ),
              ),
            ]),
          ),
        ),
      );
    }

    // ── 5. Sort shifts: most scheduled first, then most attended ─────────────
    final shiftNames = allShiftNames.toList()
      ..sort((a, b) {
        final sa = scheduledByShift[a]?.length ?? 0;
        final sb = scheduledByShift[b]?.length ?? 0;
        if (sb != sa) return sb.compareTo(sa);
        return (attendedByShift[b]?.length ?? 0)
            .compareTo(attendedByShift[a]?.length ?? 0);
      });

    const palette = [
      Color(0xFF22C55E),
      Color(0xFF3B82F6),
      Color(0xFF8B5CF6),
      Color(0xFFF59E0B),
      Color(0xFF10B981),
      Color(0xFFEC4899),
    ];

    Widget chip(IconData icon, String label, int count, Color color,
        VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.28)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
            Text(tr(label),
                style: TextStyle(
                    fontSize: 10, color: color, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Text(tr('$count'),
                style: TextStyle(
                    fontSize: 13, color: color, fontWeight: FontWeight.bold)),
          ]),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E9F0)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.calendar_today_rounded,
                size: 16, color: HrmPageChrome.primaryNavy),
            const SizedBox(width: 6),
            Expanded(
              child: Text(tr('Lịch làm việc hôm nay'),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: HrmPageChrome.primaryNavy)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: HrmPageChrome.primaryNavy.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(tr('${shiftNames.length} ca'),
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: HrmPageChrome.primaryNavy)),
            ),
          ]),
          const SizedBox(height: 10),
          ...List.generate(shiftNames.length, (i) {
            final shiftName = shiftNames[i];
            final shiftColor = palette[i % palette.length];
            final schedRows = scheduledByShift[shiftName] ?? [];
            final attendedPairs = attendedByShift[shiftName] ?? [];

            final schedCount = schedRows.length;
            final presentCount = attendedPairs.length;
            final absentCount =
                (schedCount - presentCount).clamp(0, schedCount);

            // Absent = scheduled employees NOT in attended (match by name since codes differ)
            final attendedNames = attendedPairs
                .map((p) => p.employeeName.toLowerCase().trim())
                .toSet();
            final absentRows = schedRows.where((s) {
              final nm =
                  (s['employeeName'] ?? '').toString().toLowerCase().trim();
              return nm.isEmpty || !attendedNames.contains(nm);
            }).toList();

            // Shift time: prefer schedule record's shiftStartTime/shiftEndTime, fallback to template
            String timeStr = '';
            if (schedRows.isNotEmpty) {
              final first = schedRows.first;
              final st = (first['shiftStartTime'] ?? first['startTime'] ?? '')
                  .toString();
              final et =
                  (first['shiftEndTime'] ?? first['endTime'] ?? '').toString();
              if (st.isNotEmpty && et.isNotEmpty) {
                timeStr =
                    '${st.substring(0, math.min(5, st.length))} – ${et.substring(0, math.min(5, et.length))}';
              }
            }
            if (timeStr.isEmpty) {
              final tmpl = _shiftTemplatesTyped.firstWhere(
                (t) =>
                    (t['name'] ?? '').toString().toLowerCase() ==
                    shiftName.toLowerCase(),
                orElse: () => <String, dynamic>{},
              );
              final st = (tmpl['startTime'] ?? '').toString();
              final et = (tmpl['endTime'] ?? '').toString();
              if (st.isNotEmpty && et.isNotEmpty) {
                timeStr =
                    '${st.substring(0, math.min(5, st.length))} – ${et.substring(0, math.min(5, et.length))}';
              }
            }

            final schedCards = scheduleEmpCards(schedRows);
            final attendedCards = attendedEmpCards(attendedPairs);
            final absentCards = scheduleEmpCards(absentRows);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: shiftColor.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: shiftColor.withValues(alpha: 0.18)),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                              color: shiftColor, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(tr(shiftName),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: shiftColor)),
                      if (timeStr.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(tr(timeStr),
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500)),
                      ],
                    ]),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        chip(
                            Icons.event_available_rounded,
                            'Lịch',
                            schedCount,
                            HrmPageChrome.primaryNavy,
                            () => showShiftEmpList('Lịch – $shiftName',
                                HrmPageChrome.primaryNavy, schedCards)),
                        chip(
                            Icons.how_to_reg_rounded,
                            'Có mặt',
                            presentCount,
                            const Color(0xFF22C55E),
                            () => showShiftEmpList('Có mặt – $shiftName',
                                const Color(0xFF22C55E), attendedCards)),
                        chip(
                            Icons.person_off_rounded,
                            'Vắng',
                            absentCards.length,
                            const Color(0xFFEF4444),
                            () => showShiftEmpList('Vắng – $shiftName',
                                const Color(0xFFEF4444), absentCards)),
                      ],
                    ),
                  ]),
            );
          }),
        ],
      ),
    );
  }

  // ===================== INSIGHT CHIPS ROW =====================
  Widget _buildInsightChipsRow(DashboardUiCapabilities caps,
      {bool mobileGrid = false}) {
    final pendingTotal = _pendingLeaves.length +
        _pendingCorrections.length +
        _pendingSwaps.length +
        _pendingAdvances.length +
        _pendingMobileAttendanceCount;
    // Backend OvertimeStatistics: pendingCount = chờ duyệt trong tháng.
    final otCount = _toInt(_overtimeStats['pendingCount'] ??
        _overtimeStats['totalPending'] ??
        0);
    final taskTotal =
        _toInt(_taskStats['totalTasks'] ?? _taskStats['total'] ?? 0);
    final taskDone = _toInt(_taskStats['completedCount'] ??
        _taskStats['completed'] ??
        _taskStats['done'] ??
        0);
    // Backend PenaltyTicketStats: chỉ hiển thị phiếu chờ duyệt trên chip.
    final penaltyCount = _toInt(_penaltyStats['totalPending'] ?? 0);
    final cashIn =
        ((_cashSummary['totalIncome'] ?? _cashSummary['totalIn'] ?? 0) as num)
            .toDouble();
    final cashOut =
        ((_cashSummary['totalExpense'] ?? _cashSummary['totalOut'] ?? 0) as num)
            .toDouble();
    final cashInCount = _toInt(_cashSummary['incomeTransactions'] ?? 0);
    final cashOutCount = _toInt(_cashSummary['expenseTransactions'] ?? 0);

    final chips = <_InsightChipData>[
      if (caps.insightLeave)
        _InsightChipData(
            Icons.beach_access_outlined,
            'Nghỉ phép',
            '${_absentWithPermission.length}',
            const Color(0xFFF59E0B),
            'leave_today'),
      if (caps.insightPending)
        _InsightChipData(Icons.pending_actions_outlined, 'Chờ duyệt',
            '$pendingTotal', const Color(0xFFEF4444), 'pending_all'),
      if (caps.insightBirthday)
        _InsightChipData(
            Icons.cake_outlined,
            'Sinh nhật',
            '${_todayBirthdays.length}',
            const Color(0xFFEC4899),
            'birthday_detail'),
      if (caps.insightOvertime)
        _InsightChipData(Icons.av_timer_outlined, 'OT chờ duyệt', '$otCount',
            const Color(0xFF8B5CF6), 'overtime_detail'),
      if (caps.insightTask)
        _InsightChipData(
            Icons.task_alt_outlined,
            'Công việc',
            taskTotal > 0 ? '$taskDone/$taskTotal' : '0',
            const Color(0xFF2D5F8B),
            'task_detail'),
      if (caps.insightPenalty)
        _InsightChipData(Icons.gavel_outlined, 'Vi phạm', '$penaltyCount',
            const Color(0xFFDC2626), 'penalty_detail'),
      if (caps.insightContracts)
        _InsightChipData(
            Icons.assignment_late_outlined,
            'HĐ hết hạn',
            '${_expiringDocs.length + _expiredContracts.length}',
            const Color(0xFFEA580C),
            'docs_detail'),
      if (caps.insightAdvance)
        _InsightChipData(
            Icons.account_balance_wallet_outlined,
            'Ứng lương',
            '${_pendingAdvances.length}',
            const Color(0xFF10B981),
            'advance_detail'),
      if (caps.insightNewHires)
        _InsightChipData(
            Icons.groups_outlined,
            'NV mới (90 ngày)',
            '${_newHiresThisMonth()}',
            HrmPageChrome.primaryNavy,
            'newhires_detail'),
      if (caps.insightCash) ...[
        _InsightChipData(
            Icons.arrow_downward_rounded,
            'Phiếu thu',
            cashInCount > 0 ? '$cashInCount phiếu' : _fmtMoney(cashIn),
            const Color(0xFF16A34A),
            'receipt_detail'),
        _InsightChipData(
            Icons.arrow_upward_rounded,
            'Phiếu chi',
            cashOutCount > 0 ? '$cashOutCount phiếu' : _fmtMoney(cashOut),
            const Color(0xFFEF4444),
            'payment_detail'),
      ],
    ];

    if (chips.isEmpty) return const SizedBox.shrink();

    final today = chips
        .where((c) =>
            c.kind == 'leave_today' ||
            c.kind == 'pending_all' ||
            c.kind == 'birthday_detail')
        .toList();
    final ops = chips
        .where((c) =>
            c.kind == 'overtime_detail' ||
            c.kind == 'task_detail' ||
            c.kind == 'penalty_detail')
        .toList();
    final hrFin = chips
        .where((c) =>
            c.kind == 'docs_detail' ||
            c.kind == 'advance_detail' ||
            c.kind == 'newhires_detail' ||
            c.kind == 'receipt_detail' ||
            c.kind == 'payment_detail')
        .toList();

    if (mobileGrid) {
      return Column(
        children: [
          if (today.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildMobileInsightGrid('Hôm nay', today),
            ),
          if (ops.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildMobileInsightGrid('Vận hành', ops),
            ),
          if (hrFin.isNotEmpty)
            _buildMobileInsightGrid('Hồ sơ & tài chính', hrFin),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (today.isNotEmpty) _buildInsightGroup('Hôm nay', today),
        if (ops.isNotEmpty) _buildInsightGroup('Vận hành', ops),
        if (hrFin.isNotEmpty) _buildInsightGroup('Hồ sơ & tài chính', hrFin),
      ],
    );
  }

  Widget _buildMobileInsightGrid(String title, List<_InsightChipData> items) {
    return PosMobileHubSectionGrid(
      title: title,
      items: items
          .map(
            (c) => PosMobileHubGridItem(
              label: '${c.label}\n${c.value}',
              icon: c.icon,
              onTap: () => _showInsightDetail(c),
            ),
          )
          .toList(),
    );
  }

  Widget _buildInsightGroup(String title, List<_InsightChipData> items) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(title),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xFF94A3B8),
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              final cols = w >= 900 ? 3 : (w >= 520 ? 2 : 1);
              const gap = 8.0;
              final itemW = (w - gap * (cols - 1)) / cols;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final c in items)
                    SizedBox(width: itemW, child: _buildInsightChip(c)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInsightChip(_InsightChipData c) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showInsightDetail(c),
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE4E9F0)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(c.icon, size: 18, color: c.color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(c.label),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tr(c.value),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: c.color,
                        height: 1.15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 16, color: c.color.withValues(alpha: 0.45)),
            ],
          ),
        ),
      ),
    );
  }

  int _newHiresThisMonth() {
    final cutoff = DateTime.now().subtract(const Duration(days: 90));
    var count = 0;
    for (final e in _employees) {
      if (e is Map) {
        final join = e['joinDate'] ?? e['hireDate'] ?? e['startDate'];
        if (join != null) {
          try {
            final d = DateTime.parse(join.toString());
            if (d.isAfter(cutoff)) count++;
          } catch (_) {}
        }
      }
    }
    return count;
  }

  String _fmtMoney(double v) {
    if (v.abs() >= 1000000000) return '${(v / 1000000000).toStringAsFixed(1)}B';
    if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v.abs() >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }

  /// Dialog xác nhận duyệt ứng lương nhanh từ dashboard — cho phép quản lý
  /// sửa số tiền duyệt thấp hơn số tiền nhân viên yêu cầu ban đầu. Trả về
  /// số tiền đã xác nhận, hoặc null nếu người dùng hủy.
  Future<double?> _showAdvanceApproveAmountDialog(
      Map<String, dynamic> item) async {
    final requestedAmount =
        ((item['requestedAmount'] ?? item['amount'] ?? 0) as num).toDouble();
    final priorApproved = item['approvedAmount'] != null
        ? (item['approvedAmount'] as num).toDouble()
        : null;
    final initialAmount = priorApproved ?? requestedAmount;
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');
    final amountController = TextEditingController(
        text: tr(NumberFormat('#,###').format(initialAmount)));
    String? errorText;
    final employeeName = (item['employeeName'] ?? '').toString();

    return showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => ScrollableAlertDialog(
          title: Text(tr('Xác nhận duyệt ứng lương')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (employeeName.isNotEmpty) Text(tr('Nhân viên: $employeeName')),
              const SizedBox(height: 4),
              Text(tr('Số tiền yêu cầu: ${currency.format(requestedAmount)}')),
              if (priorApproved != null &&
                  priorApproved != requestedAmount) ...[
                const SizedBox(height: 4),
                Text(tr('Đề xuất bước trước: ${currency.format(priorApproved)}'),
                  style:
                      TextStyle(color: Colors.orange.shade800, fontSize: 13),
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
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('Hủy'))),
            FilledButton(
              onPressed: () {
                final parsed =
                    parseFormattedNumber(amountController.text)?.toDouble();
                if (parsed == null || parsed <= 0) {
                  setDialogState(
                      () => errorText = 'Vui lòng nhập số tiền hợp lệ');
                  return;
                }
                if (parsed > requestedAmount) {
                  setDialogState(() => errorText =
                      'Không được vượt số tiền yêu cầu (${currency.format(requestedAmount)})');
                  return;
                }
                Navigator.pop(ctx, parsed);
              },
              child: Text(tr('Duyệt')),
            ),
          ],
        ),
      ),
    );
  }

  // ===================== INSIGHT DETAIL SHEET =====================
  void _showInsightDetail(_InsightChipData c) {
    final List<Map<String, dynamic>> items;
    Widget? customContent;

    switch (c.kind) {
      case 'leave_today':
        items = [];
        customContent = _buildLeaveTodayDetailContent();
        break;
      case 'pending_all':
        items = [];
        customContent = _buildPendingAllDetailContent(c.color);
        break;
      case 'birthday_detail':
        items = [];
        customContent = _buildBirthdayDetailContent();
        break;
      case 'overtime_detail':
        items = [];
        customContent = _buildOvertimeDetailContent();
        break;
      case 'task_detail':
        items = [];
        customContent = _buildTaskDetailContent();
        break;
      case 'penalty_detail':
        items = [];
        customContent = _buildPenaltyDetailContent();
        break;
      case 'docs_detail':
        items = [];
        customContent = _buildContractDetailContent();
        break;
      case 'advance_detail':
        items = [];
        customContent = _buildAdvanceDetailContent(c.color);
        break;
      case 'finance_detail':
      case 'receipt_detail':
      case 'payment_detail':
        items = [];
        customContent = _buildFinanceDetailContent();
        break;
      case 'newhires_detail':
        final cutoff = DateTime.now().subtract(const Duration(days: 90));
        items = _employees.whereType<Map<String, dynamic>>().where((e) {
          final join = e['joinDate'] ?? e['hireDate'] ?? e['startDate'];
          if (join == null) return false;
          try {
            final d = DateTime.parse(join.toString());
            return d.isAfter(cutoff);
          } catch (_) {
            return false;
          }
        }).toList();
        items.sort((a, b) {
          final da = DateTime.tryParse(
                  (a['joinDate'] ?? a['hireDate'] ?? a['startDate'] ?? '')
                      .toString()) ??
              DateTime(2000);
          final db = DateTime.tryParse(
                  (b['joinDate'] ?? b['hireDate'] ?? b['startDate'] ?? '')
                      .toString()) ??
              DateTime(2000);
          return db.compareTo(da);
        });
        break;
      default:
        items = [];
    }

    showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: c.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(c.icon, color: c.color, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tr(c.label),
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          Text(tr(() {
                            if (c.kind == 'advance_detail') {
                              final advances = _pendingAdvances
                                  .whereType<Map<String, dynamic>>()
                                  .toList();
                              final total = advances.fold<double>(
                                  0,
                                  (s, e) =>
                                      s +
                                      ((e['requestedAmount'] ??
                                              e['amount'] ??
                                              0) as num)
                                          .toDouble());
                              return '${advances.length} phiếu • ${_fmtMoney(total)}đ';
                            }
                            return customContent != null
                                ? c.value
                                : '${items.length} mục';
                          }()),
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: customContent != null
                    ? SingleChildScrollView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        child: customContent,
                      )
                    : items.isEmpty
                        ? _emptyState('Không có dữ liệu')
                        : ListView.separated(
                            controller: scrollController,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 6),
                            itemBuilder: (_, i) => _buildInsightDetailRow(
                                c.kind, items[i], c.color),
                          ),
              ),
              // CTA: open the source management screen
              Builder(builder: (_) {
                final cta = _ctaForKind(c.kind);
                if (cta == null) return const SizedBox.shrink();
                return SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: c.color,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          if (cta.onNavigate != null) {
                            cta.onNavigate!();
                          } else if (cta.screen != null) {
                            Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => cta.screen!));
                          }
                        },
                        icon: Icon(cta.icon, size: 18),
                        label: Text(tr(cta.label),
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInsightDetailRow(
      String kind, Map<String, dynamic> item, Color accent) {
    final ln = (item['lastName'] ?? '').toString().trim();
    final fn = (item['firstName'] ?? '').toString().trim();
    final fullFromParts = [ln, fn].where((s) => s.isNotEmpty).join(' ');
    final name =
        (item['fullName'] ?? item['employeeName'] ?? item['name'] ?? '')
                .toString()
                .trim()
                .isNotEmpty
            ? (item['fullName'] ?? item['employeeName'] ?? item['name'])
                .toString()
                .trim()
            : (fullFromParts.isNotEmpty ? fullFromParts : '-');
    final sub1 =
        (item['departmentName'] ?? item['department'] ?? item['_type'] ?? '')
            .toString();
    final sub2 =
        (item['leaveType'] ?? item['type'] ?? item['contractType'] ?? '')
            .toString();

    String badge = '';
    if (kind == 'birthday_detail') {
      final dob = item['dateOfBirth'] ?? item['birthday'];
      badge = dob != null ? _fmtDate(dob) : '';
    } else if (kind == 'newhires_detail') {
      final join = item['joinDate'] ?? item['hireDate'] ?? item['startDate'];
      if (join != null) {
        try {
          final d = DateTime.parse(join.toString());
          final diff = DateTime.now().difference(d).inDays;
          badge = diff == 0 ? 'Hôm nay' : '$diff ngày';
        } catch (_) {}
      }
    } else if (kind == 'pending_all') {
      badge = (item['_type'] ?? '').toString();
    } else if (kind == 'docs_detail') {
      final contractEnd =
          item['contractEndDate'] ?? item['expiryDate'] ?? item['endDate'];
      final daysLeft = (item['daysUntilExpiry'] as num?)?.toInt();
      if (daysLeft != null) {
        badge = daysLeft == 0 ? 'Hôm nay' : '$daysLeft ngày';
      } else if (contractEnd != null) {
        badge = _fmtDate(contractEnd);
      }
    } else if (kind == 'advance_detail') {
      final amt = (item['requestedAmount'] ?? item['amount'] ?? 0) as num;
      badge = '${_fmtMoney(amt.toDouble())}đ';
    }

    return InkWell(
      onTap: () => _navigateFromInsightRow(kind, item),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.blueGrey.shade100),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: accent.withValues(alpha: .12),
              child: Text(
                  tr(name.isNotEmpty ? name.characters.first.toUpperCase() : '?'),
                  style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(name),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (sub1.isNotEmpty || sub2.isNotEmpty)
                    Text(tr([sub1, sub2].where((s) => s.isNotEmpty).join(' • ')),
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF71717A)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (badge.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: accent.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(tr(badge),
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: accent)),
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  /// Navigate from an insight-detail row to the source screen so the user can
  /// review / approve / edit the underlying record.
  void _openPendingRecord(String typeKey, Map<String, dynamic> item) {
    Navigator.of(context, rootNavigator: false).maybePop();
    final id = (item['id'] ?? item['Id'] ?? '').toString();
    final hi = id.isEmpty ? null : id;
    switch (typeKey) {
      case 'leave':
        NavigationNotifier.goToLeaves(highlightId: hi, pendingOnly: true);
        break;
      case 'correction':
        NavigationNotifier.goToAttendanceApproval(
            statusFilter: 0, tab: 0, highlightId: hi);
        break;
      case 'swap':
        NavigationNotifier.goToScheduleApproval(tab: 3, highlightId: hi);
        break;
      case 'advance':
        NavigationNotifier.goToAdvanceRequestsNav(
            highlightId: hi, pendingOnly: true);
        break;
      case 'mobile':
        NavigationNotifier.goToAttendanceApproval(
            statusFilter: 0, tab: 1, highlightId: hi);
        break;
    }
  }

  void _navigateFromInsightRow(String kind, Map<String, dynamic> item) {
    // Close the bottom sheet first.
    Navigator.of(context, rootNavigator: false).maybePop();
    final type = (item['_type'] ?? '').toString();
    final itemId = (item['id'] ?? item['Id'] ?? '').toString();
    final hi = itemId.isEmpty ? null : itemId;

    String? resolved;
    if (kind == 'pending_all') {
      switch (type) {
        case 'Đơn nghỉ phép':
          resolved = 'leave';
          NavigationNotifier.goToLeaves(highlightId: hi, pendingOnly: true);
          break;
        case 'Chỉnh sửa CC':
          resolved = 'corrections';
          NavigationNotifier.goToAttendanceApproval(
              statusFilter: 0, tab: 0, highlightId: hi);
          break;
        case 'Đổi ca':
          resolved = 'swap';
          NavigationNotifier.goToScheduleApproval(tab: 3, highlightId: hi);
          break;
        case 'Ứng lương':
          resolved = 'advance';
          NavigationNotifier.goToAdvanceRequestsNav(
              highlightId: hi, pendingOnly: true);
          break;
      }
    } else {
      switch (kind) {
        case 'leave_today':
          resolved = 'leave';
          NavigationNotifier.goToLeaves(highlightId: hi);
          break;
        case 'advance_detail':
          resolved = 'advance';
          NavigationNotifier.goToAdvanceRequestsNav(highlightId: hi);
          break;
        case 'docs_detail':
          resolved = 'docs';
          if (Provider.of<PermissionProvider>(context, listen: false)
              .canView('HrDocument')) {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => HrmPushedScreenShell(
                title: 'Tài liệu HR',
                child: HrDocumentsScreen(highlightId: hi),
              ),
            ));
          } else {
            NavigationNotifier.goToEmployeesHighlight(hi);
          }
          break;
        case 'birthday_detail':
        case 'newhires_detail':
          resolved = 'employee';
          NavigationNotifier.goToEmployeesHighlight(hi);
          break;
      }
    }

    if (resolved == null) return;
    final empName =
        (item['employeeName'] ?? item['fullName'] ?? item['name'] ?? '')
            .toString();
    if (empName.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('Mở $resolved cho: $empName')),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Returns CTA configuration mapping a chip kind to the management screen
  /// the user should be taken to from the insight bottom sheet.
  _InsightCta? _ctaForKind(String kind) {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    switch (kind) {
      case 'leave_today':
        return _InsightCta('Mở quản lý nghỉ phép', Icons.event_busy, null,
            onNavigate: () => NavigationNotifier.goToLeaves());
      case 'pending_all':
        return _InsightCta(
            'Mở duyệt chấm công (CC/Mobile)',
            Icons.fact_check_outlined,
            null,
            onNavigate: NavigationNotifier.goToAttendanceCorrections);
      case 'birthday_detail':
      case 'newhires_detail':
        return _InsightCta('Mở danh sách nhân viên',
            Icons.people_alt_outlined, null,
            onNavigate: NavigationNotifier.goToEmployees);
      case 'overtime_detail':
        if (!perm.canView('Overtime')) {
          return null;
        }
        return _InsightCta('Mở quản lý tăng ca', Icons.access_time, null,
            onNavigate: NavigationNotifier.goToOvertimeFromDashboard);
      case 'task_detail':
        return _InsightCta('Mở quản lý công việc', Icons.checklist, null,
            onNavigate: () => NavigationNotifier.goToTaskManagementNav());
      case 'penalty_detail':
        return _InsightCta(
            'Mở phiếu vi phạm',
            Icons.report_gmailerrorred,
            null,
            onNavigate: () =>
                NavigationNotifier.goToPenaltyTicketsNav(filterStatus: '0'));
      case 'docs_detail':
        return _InsightCta(
          perm.canView('HrDocument')
              ? 'Mở tài liệu HR'
              : 'Mở danh sách nhân viên',
          perm.canView('HrDocument')
              ? Icons.folder_open_outlined
              : Icons.people_alt_outlined,
          null,
          onNavigate: () {
            if (perm.canView('HrDocument')) {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const HrmPushedScreenShell(
                  title: 'Tài liệu HR',
                  child: HrDocumentsScreen(),
                ),
              ));
            } else {
              NavigationNotifier.goToEmployees();
            }
          },
        );
      case 'advance_detail':
        return _InsightCta('Mở phiếu ứng lương', Icons.payments_outlined, null,
            onNavigate: () =>
                NavigationNotifier.goToAdvanceRequestsNav(pendingOnly: true));
      case 'finance_detail':
      case 'receipt_detail':
      case 'payment_detail':
        return _InsightCta('Mở thu chi',
            Icons.account_balance_wallet_outlined, null,
            onNavigate: NavigationNotifier.goToCashTransaction);
    }
    return null;
  }

  Widget _buildPendingAllDetailContent(Color accentColor) {
    final leaves = _pendingLeaves.whereType<Map<String, dynamic>>().toList();
    final corrections =
        _pendingCorrections.whereType<Map<String, dynamic>>().toList();
    final swaps = _pendingSwaps.whereType<Map<String, dynamic>>().toList();
    final advances =
        _pendingAdvances.whereType<Map<String, dynamic>>().toList();
    final mobile =
        _pendingMobileAttendance.whereType<Map<String, dynamic>>().toList();

    if (leaves.isEmpty &&
        corrections.isEmpty &&
        swaps.isEmpty &&
        advances.isEmpty &&
        mobile.isEmpty) {
      return _emptyState('Không có phiếu chờ duyệt');
    }

    // Local state for loading indicators per item
    final loadingIds = <String>{};

    Future<void> doApprove(String type, Map<String, dynamic> item,
        {bool approve = true, String? reason}) async {
      final id = (item['id'] ?? item['Id'] ?? '').toString();
      if (id.isEmpty) return;
      try {
        Map<String, dynamic> result;
        switch (type) {
          case 'leave':
            result = approve
                ? await _api.approveLeave(id)
                : await _api.rejectLeave(id, reason);
            break;
          case 'correction':
            result = await _api.approveAttendanceCorrection(
                requestId: id, isApproved: approve, approverNote: reason);
            break;
          case 'swap':
            result = approve
                ? await _api.approveShiftSwap(id, approve: true)
                : await _api.approveShiftSwap(id,
                    approve: false, rejectionReason: reason);
            break;
          case 'advance':
            double? advanceApprovedAmount;
            if (approve) {
              advanceApprovedAmount =
                  await _showAdvanceApproveAmountDialog(item);
              if (advanceApprovedAmount == null) return; // đã hủy
            }
            // Luôn gửi số tiền duyệt để backend lưu đúng (kể cả = số yêu cầu).
            result = await _api.approveAdvanceRequest(
                requestId: id,
                isApproved: approve,
                rejectionReason: reason,
                approvedAmount: approve ? advanceApprovedAmount : null);
            break;
          case 'mobile':
            result = await _api.approveMobileAttendance(
              recordId: id,
              approved: approve,
              rejectionReason: reason,
            );
            break;
          default:
            return;
        }
        final ok = result['isSuccess'] == true || result['isSuccess'] == 'true';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr(ok
                ? (approve ? 'Đã duyệt thành công' : 'Đã từ chối')
                : (result['message'] ?? 'Thao tác thất bại').toString())),
            backgroundColor:
                ok ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
            duration: const Duration(seconds: 2),
          ));
          if (ok) _loadAllData(); // refresh
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr('Lỗi: $e')),
            backgroundColor: const Color(0xFFEF4444),
          ));
        }
      }
    }

    Widget pendingCard({
      required Map<String, dynamic> item,
      required String typeKey,
      required String typeLabel,
      required Color color,
      required String title,
      required String subtitle,
      String? extraInfo,
      String? dateStr,
    }) {
      final id = (item['id'] ?? item['Id'] ?? '').toString();
      return StatefulBuilder(builder: (ctx, setS) {
        final isLoading = loadingIds.contains(id);

        Future<void> approve() async {
          setS(() => loadingIds.add(id));
          await doApprove(typeKey, item, approve: true);
          setS(() => loadingIds.remove(id));
        }

        Future<void> reject() async {
          // For leave/advance/correction, show a quick reason dialog
          String? reason;
          if (typeKey == 'leave' ||
              typeKey == 'advance' ||
              typeKey == 'correction' ||
              typeKey == 'mobile') {
            final ctrl = TextEditingController();
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (_) => ScrollableAlertDialog(
                title: Text(tr('Lý do từ chối'),
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                content: TextField(
                  controller: ctrl,
                  decoration: InputDecoration(
                      hintText: tr('Nhập lý do...'), border: OutlineInputBorder()),
                  maxLines: 2,
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(tr('Hủy'))),
                  FilledButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white),
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(tr('Từ chối')),
                  ),
                ],
              ),
            );
            if (confirmed != true) return;
            reason = ctrl.text.trim();
          }
          setS(() => loadingIds.add(id));
          await doApprove(typeKey, item, approve: false, reason: reason);
          setS(() => loadingIds.remove(id));
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: .2)),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Header
            InkWell(
              onTap: () => _openPendingRecord(typeKey, item),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(10)),
              child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
              child: Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(tr(typeLabel),
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: color)),
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(tr(title),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                const Icon(Icons.open_in_new_rounded,
                    size: 14, color: Color(0xFF94A3B8)),
              ]),
            ),
            ),
            // Details
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (subtitle.isNotEmpty)
                      Text(tr(subtitle),
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF6B7280))),
                    if (dateStr != null && dateStr.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(children: [
                        const Icon(Icons.calendar_today_outlined,
                            size: 11, color: Color(0xFF9CA3AF)),
                        const SizedBox(width: 4),
                        Text(tr(dateStr),
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF6B7280))),
                      ]),
                    ],
                    if (extraInfo != null && extraInfo.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.notes_rounded,
                                size: 11, color: Color(0xFF9CA3AF)),
                            const SizedBox(width: 4),
                            Expanded(
                                child: Text(tr(extraInfo),
                                    style: const TextStyle(
                                        fontSize: 11, color: Color(0xFF6B7280)),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis)),
                          ]),
                    ],
                  ]),
            ),
            // Action buttons
            if (isLoading)
              const Padding(
                padding: EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Center(
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else if (_canApprovePendingType(
                typeKey, Provider.of<PermissionProvider>(context)))
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: const BorderSide(color: Color(0xFFEF4444)),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7)),
                      ),
                      icon: const Icon(Icons.close, size: 14),
                      label:
                          Text(tr('Từ chối'), style: TextStyle(fontSize: 12)),
                      onPressed: reject,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF22C55E),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(7)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.check, size: 14),
                      label:
                          Text(tr('Duyệt'), style: TextStyle(fontSize: 12)),
                      onPressed: approve,
                    ),
                  ),
                ]),
              ),
          ]),
        );
      });
    }

    String fmtDateRange(dynamic start, dynamic end) {
      if (start == null) return '';
      try {
        final s = DateTime.parse(start.toString());
        if (end == null) return '${s.day}/${s.month}/${s.year}';
        final e = DateTime.parse(end.toString());
        if (s.year == e.year && s.month == e.month && s.day == e.day) {
          return '${s.day}/${s.month}/${s.year}';
        }
        return '${s.day}/${s.month} – ${e.day}/${e.month}/${e.year}';
      } catch (_) {
        return start.toString();
      }
    }

    Widget sectionHeader(String title, int count, Color color) => Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(tr('$count'),
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold, color: color)),
            ),
            const SizedBox(width: 8),
            Text(tr(title),
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Đơn nghỉ phép ──
        if (leaves.isNotEmpty) ...[
          sectionHeader(
              'Đơn nghỉ phép', leaves.length, const Color(0xFFF59E0B)),
          ...leaves.map((item) {
            final name =
                (item['employeeName'] ?? item['fullName'] ?? '').toString();
            final dept =
                (item['department'] ?? item['departmentName'] ?? '').toString();
            final leaveTypeRaw = item['type'] ?? item['leaveType'];
            final leaveTypeStr = () {
              if (leaveTypeRaw == null) return 'Nghỉ phép';
              final t = leaveTypeRaw is int
                  ? leaveTypeRaw
                  : int.tryParse(leaveTypeRaw.toString()) ?? -1;
              const labels = {
                0: 'Phép năm',
                1: 'Lễ tết',
                2: 'VR có lương',
                3: 'VR không lương',
                4: 'Ốm đau',
                5: 'Thai sản',
                6: 'Nghỉ bù',
                7: 'Nghỉ dài hạn'
              };
              return labels[t] ?? 'Nghỉ phép';
            }();
            final totalDays = item['totalDays'] ?? item['totalShifts'];
            final daysStr = totalDays != null
                ? '${(totalDays as num).toStringAsFixed(totalDays == (totalDays).truncate() ? 0 : 1)} ngày'
                : '';
            final subtitle = [dept, leaveTypeStr, daysStr]
                .where((s) => s.isNotEmpty)
                .join(' • ');
            return pendingCard(
              item: item,
              typeKey: 'leave',
              typeLabel: 'Nghỉ phép',
              color: const Color(0xFFF59E0B),
              title: name.isEmpty ? 'N/A' : name,
              subtitle: subtitle,
              dateStr: fmtDateRange(item['startDate'], item['endDate']),
              extraInfo: (item['reason'] ?? '').toString().trim().isNotEmpty
                  ? item['reason'].toString()
                  : null,
            );
          }),
        ],
        // ── Chỉnh sửa CC ──
        if (corrections.isNotEmpty) ...[
          sectionHeader('Chỉnh sửa chấm công', corrections.length,
              const Color(0xFF6366F1)),
          ...corrections.map((item) {
            final name =
                (item['employeeName'] ?? item['fullName'] ?? '').toString();
            final action =
                (item['action'] ?? item['correctionType'] ?? '').toString();
            final newTime = (item['newTime'] ?? '').toString();
            final newDate = item['newDate'] ?? item['correctionDate'];
            final reason = (item['reason'] ?? '').toString().trim();
            return pendingCard(
              item: item,
              typeKey: 'correction',
              typeLabel: 'Chỉnh CC',
              color: const Color(0xFF6366F1),
              title: name.isEmpty ? 'N/A' : name,
              subtitle:
                  [action, newTime].where((s) => s.isNotEmpty).join(' → '),
              dateStr: newDate != null ? fmtDateRange(newDate, null) : '',
              extraInfo: reason.isNotEmpty ? reason : null,
            );
          }),
        ],
        // ── Đổi ca ──
        if (swaps.isNotEmpty) ...[
          sectionHeader('Đổi ca', swaps.length, const Color(0xFF8B5CF6)),
          ...swaps.map((item) {
            final requester =
                (item['requesterName'] ?? item['employeeName'] ?? '')
                    .toString();
            final target =
                (item['targetName'] ?? item['targetEmployeeName'] ?? '')
                    .toString();
            final shiftFrom =
                (item['originalShiftName'] ?? item['shiftName'] ?? '')
                    .toString();
            final shiftTo = (item['targetShiftName'] ?? '').toString();
            final dateFrom = item['originalDate'] ?? item['shiftDate'];
            final dateTo = item['targetDate'];
            return pendingCard(
              item: item,
              typeKey: 'swap',
              typeLabel: 'Đổi ca',
              color: const Color(0xFF8B5CF6),
              title: requester.isEmpty ? 'N/A' : requester,
              subtitle: target.isNotEmpty ? 'Đổi với: $target' : '',
              dateStr: shiftFrom.isNotEmpty || shiftTo.isNotEmpty
                  ? [shiftFrom, shiftTo].where((s) => s.isNotEmpty).join(' ⇄ ')
                  : fmtDateRange(dateFrom, dateTo),
              extraInfo: (item['reason'] ?? '').toString().trim().isNotEmpty
                  ? item['reason'].toString()
                  : null,
            );
          }),
        ],
        // ── Ứng lương ──
        if (advances.isNotEmpty) ...[
          sectionHeader('Ứng lương', advances.length, const Color(0xFF0EA5E9)),
          ...advances.map((item) {
            final name =
                (item['employeeName'] ?? item['fullName'] ?? '').toString();
            final dept =
                (item['department'] ?? item['departmentName'] ?? '').toString();
            final amt = (item['requestedAmount'] ?? item['amount'] ?? 0) as num;
            final reason = (item['reason'] ?? '').toString().trim();
            return pendingCard(
              item: item,
              typeKey: 'advance',
              typeLabel: 'Ứng lương',
              color: const Color(0xFF0EA5E9),
              title: name.isEmpty ? 'N/A' : name,
              subtitle: [dept, '${_fmtMoney(amt.toDouble())}đ']
                  .where((s) => s.isNotEmpty)
                  .join(' • '),
              dateStr:
                  fmtDateRange(item['requestDate'] ?? item['createdAt'], null),
              extraInfo: reason.isNotEmpty ? reason : null,
            );
          }),
        ],
        // ── Chấm công Mobile ──
        if (mobile.isNotEmpty) ...[
          sectionHeader(
              'Chấm công Mobile', mobile.length, HrmPageChrome.primaryNavy),
          ...mobile.map((item) {
            final name =
                (item['employeeName'] ?? item['fullName'] ?? '').toString();
            final dept =
                (item['department'] ?? item['departmentName'] ?? '').toString();
            final punchType =
                (item['punchType'] ?? item['type'] ?? item['action'] ?? '')
                    .toString();
            final punchTime = item['punchTime'] ??
                item['checkTime'] ??
                item['attendanceTime'] ??
                item['createdAt'];
            return pendingCard(
              item: item,
              typeKey: 'mobile',
              typeLabel: 'Mobile',
              color: HrmPageChrome.primaryNavy,
              title: name.isEmpty ? 'N/A' : name,
              subtitle: [dept, punchType]
                  .where((s) => s.isNotEmpty)
                  .join(' • '),
              dateStr: punchTime != null ? fmtDateRange(punchTime, null) : '',
              extraInfo: (item['note'] ?? item['reason'] ?? '')
                  .toString()
                  .trim()
                  .isNotEmpty
                  ? (item['note'] ?? item['reason']).toString()
                  : null,
            );
          }),
        ],
      ],
    );
  }

  Widget _buildAdvanceDetailContent(Color accentColor) {
    final initialList =
        _pendingAdvances.whereType<Map<String, dynamic>>().toList();
    if (initialList.isEmpty) {
      return _emptyState('Không có phiếu ứng lương chờ duyệt');
    }

    // ValueNotifier drives the list so items disappear immediately after approve/reject
    final listNotifier =
        ValueNotifier<List<Map<String, dynamic>>>(List.from(initialList));
    final loadingIds = <String>{};

    String fmtDate(dynamic d) {
      if (d == null) return '';
      try {
        final dt = DateTime.parse(d.toString());
        return '${dt.day}/${dt.month}/${dt.year}';
      } catch (_) {
        return d.toString();
      }
    }

    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: listNotifier,
      builder: (ctx, advances, _) {
        if (advances.isEmpty) {
          return _emptyState('Tất cả phiếu đã được xử lý');
        }

        final totalAmount = advances.fold<double>(
          0,
          (sum, item) =>
              sum +
              ((item['requestedAmount'] ?? item['amount'] ?? 0) as num)
                  .toDouble(),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Banner tổng tiền ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: .08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF10B981).withValues(alpha: .2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    const Icon(Icons.account_balance_wallet_outlined,
                        size: 16, color: Color(0xFF10B981)),
                    const SizedBox(width: 6),
                    Text(tr('${advances.length} phiếu chờ duyệt'),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF10B981))),
                  ]),
                  Text(tr('${_fmtMoney(totalAmount)}đ'),
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF059669))),
                ],
              ),
            ),
            // ── Danh sách phiếu ──
            ...advances.map((item) {
              final id = (item['id'] ?? item['Id'] ?? '').toString();
              final name =
                  (item['employeeName'] ?? item['fullName'] ?? '').toString();
              final dept = (item['department'] ?? item['departmentName'] ?? '')
                  .toString();
              final amt =
                  (item['requestedAmount'] ?? item['amount'] ?? 0) as num;
              final reason = (item['reason'] ?? '').toString().trim();
              final dateStr = fmtDate(item['requestDate'] ?? item['createdAt']);

              return StatefulBuilder(builder: (ctx2, setS) {
                final isLoading = loadingIds.contains(id);

                Future<void> doAction(bool approve,
                    {String? rejectReason, double? approvedAmountOverride}) async {
                  setS(() => loadingIds.add(id));
                  try {
                    final result = await _api.approveAdvanceRequest(
                        requestId: id,
                        isApproved: approve,
                        rejectionReason: rejectReason,
                        // Luôn gửi số tiền duyệt khi approve (kể cả = số YC).
                        approvedAmount:
                            approve ? approvedAmountOverride : null);
                    final ok = result['isSuccess'] == true ||
                        result['isSuccess'] == 'true';
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(tr(ok
                            ? (approve ? 'Đã duyệt thành công' : 'Đã từ chối')
                            : (result['message'] ?? 'Thao tác thất bại')
                                .toString())),
                        backgroundColor: ok
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFEF4444),
                        duration: const Duration(seconds: 2),
                      ));
                      if (ok) {
                        // Remove item immediately from local list → UI cập nhật ngay
                        listNotifier.value = listNotifier.value
                            .where((e) =>
                                (e['id'] ?? e['Id'] ?? '').toString() != id)
                            .toList();
                        _loadAllData(); // refresh dashboard numbers in background
                        return; // item gone, no need to setS remove
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(tr('Lỗi: $e')),
                        backgroundColor: const Color(0xFFEF4444),
                      ));
                    }
                  }
                  setS(() => loadingIds.remove(id));
                }

                Future<void> onApprove() async {
                  final approvedAmount =
                      await _showAdvanceApproveAmountDialog(item);
                  if (approvedAmount == null) return; // đã hủy
                  await doAction(true, approvedAmountOverride: approvedAmount);
                }

                Future<void> onReject() async {
                  final ctrl = TextEditingController();
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (_) => ScrollableAlertDialog(
                      title: Text(tr('Lý do từ chối'),
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      content: TextField(
                        controller: ctrl,
                        decoration: InputDecoration(
                            hintText: tr('Nhập lý do...'),
                            border: OutlineInputBorder()),
                        maxLines: 2,
                      ),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: Text(tr('Hủy'))),
                        FilledButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEF4444),
                              foregroundColor: Colors.white),
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(tr('Từ chối')),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  await doAction(false, rejectReason: ctrl.text.trim());
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF10B981).withValues(alpha: .2)),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header row
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981)
                                    .withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(tr('Ứng lương'),
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF10B981))),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(tr(name.isEmpty ? 'N/A' : name),
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF059669)
                                    .withValues(alpha: .1),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Text(tr('${_fmtMoney(amt.toDouble())}đ'),
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF059669))),
                            ),
                          ]),
                        ),
                        // Detail
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (dept.isNotEmpty)
                                  Text(tr(dept),
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF6B7280))),
                                if (dateStr.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Row(children: [
                                    const Icon(Icons.calendar_today_outlined,
                                        size: 11, color: Color(0xFF9CA3AF)),
                                    const SizedBox(width: 4),
                                    Text(tr(dateStr),
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF6B7280))),
                                  ]),
                                ],
                                if (reason.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.notes_rounded,
                                            size: 11, color: Color(0xFF9CA3AF)),
                                        const SizedBox(width: 4),
                                        Expanded(
                                            child: Text(tr(reason),
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xFF6B7280)),
                                                maxLines: 2,
                                                overflow:
                                                    TextOverflow.ellipsis)),
                                      ]),
                                ],
                              ]),
                        ),
                        // Action buttons
                        if (isLoading)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(10, 0, 10, 10),
                            child: Center(
                                child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))),
                          )
                        else if (_canApprovePendingType(
                            'advance',
                            Provider.of<PermissionProvider>(context)))
                          Padding(
                            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                            child: Row(children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFEF4444),
                                    side: const BorderSide(
                                        color: Color(0xFFEF4444)),
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 6),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(7)),
                                  ),
                                  icon: const Icon(Icons.close, size: 14),
                                  label: Text(tr('Từ chối'),
                                      style: TextStyle(fontSize: 12)),
                                  onPressed: onReject,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF22C55E),
                                    foregroundColor: Colors.white,
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 6),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(7)),
                                    elevation: 0,
                                  ),
                                  icon: const Icon(Icons.check, size: 14),
                                  label: Text(tr('Duyệt'),
                                      style: TextStyle(fontSize: 12)),
                                  onPressed: onApprove,
                                ),
                              ),
                            ]),
                          ),
                      ]),
                );
              });
            }),
          ],
        );
      },
    );
  }

  Widget _buildLeaveTodayDetailContent() {
    // Combine today's leaves from report + leave API, deduplicated
    final all = _absentWithPermission.cast<Map<String, dynamic>>();

    if (all.isEmpty) {
      return _emptyState('Không có nhân viên nghỉ phép hôm nay');
    }

    int normalizeLeaveType(dynamic type) {
      if (type is int) return type;
      final s = type?.toString().toLowerCase() ?? '';
      switch (s) {
        case 'annualleave':
        case 'annual':
        case '0':
          return 0;
        case 'holiday':
        case '1':
          return 1;
        case 'personalpaid':
        case '2':
          return 2;
        case 'personalunpaid':
        case '3':
          return 3;
        case 'sickleave':
        case 'sick':
        case '4':
          return 4;
        case 'maternityleave':
        case 'maternity':
        case '5':
          return 5;
        case 'compensatoryleave':
        case 'compensatory':
        case '6':
          return 6;
        case 'longtermleave':
        case 'longterm':
        case '7':
          return 7;
        default:
          return -1;
      }
    }

    String leaveTypeLabel(dynamic type) {
      final t = normalizeLeaveType(type);
      switch (t) {
        case 0:
          return 'Phép năm';
        case 1:
          return 'Lễ tết';
        case 2:
          return 'VR có lương';
        case 3:
          return 'VR không lương';
        case 4:
          return 'Ốm đau';
        case 5:
          return 'Thai sản';
        case 6:
          return 'Nghỉ bù';
        case 7:
          return 'Nghỉ dài hạn';
        default:
          return 'Nghỉ phép';
      }
    }

    // Group by leave type label
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final item in all) {
      final label = leaveTypeLabel(
          item['type'] ?? item['leaveType'] ?? item['contractType']);
      grouped.putIfAbsent(label, () => []).add(item);
    }

    Widget leaveCard(Map<String, dynamic> d) {
      final ln = (d['lastName'] ?? '').toString();
      final fn = (d['firstName'] ?? '').toString();
      final empName = (d['employeeName'] ?? d['fullName'] ?? d['name'] ?? '')
          .toString()
          .trim();
      final fullName = empName.isNotEmpty ? empName : '$ln $fn'.trim();
      final dept = (d['department'] ?? d['departmentName'] ?? '').toString();
      final start = d['startDate'] ?? d['shiftDate'] ?? d['date'];
      final end = d['endDate'];
      final totalDays = d['totalDays'] ?? d['totalShifts'];
      final reason = (d['reason'] ?? d['note'] ?? '').toString().trim();
      final isHalf = d['isHalfShift'] == true;

      String dateRange = '';
      if (start != null && end != null) {
        try {
          final s = DateTime.parse(start.toString());
          final e = DateTime.parse(end.toString());
          if (s.day == e.day && s.month == e.month && s.year == e.year) {
            dateRange = '${s.day}/${s.month}/${s.year}';
          } else {
            dateRange = '${s.day}/${s.month} – ${e.day}/${e.month}/${e.year}';
          }
        } catch (_) {
          dateRange = start.toString();
        }
      } else if (start != null) {
        try {
          final s = DateTime.parse(start.toString());
          dateRange = '${s.day}/${s.month}/${s.year}';
        } catch (_) {
          dateRange = start.toString();
        }
      }

      String daysStr = '';
      if (totalDays != null) {
        final n = (totalDays as num).toDouble();
        daysStr = n == n.truncateToDouble()
            ? '${n.toInt()} ngày'
            : '${n.toStringAsFixed(1)} ngày';
      } else if (isHalf) {
        daysStr = 'Nửa ca';
      }

      return InkWell(
        onTap: () {
          Navigator.of(context, rootNavigator: false).maybePop();
          final empId = (d['employeeId'] ??
                  d['employeeUserId'] ??
                  d['userId'] ??
                  d['leaveId'] ??
                  d['id'] ??
                  '')
              .toString();
          NavigationNotifier.goToLeaves(
              highlightId: empId.isEmpty ? null : empId);
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border:
              Border.all(color: const Color(0xFFF59E0B).withValues(alpha: .2)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFFFEF3C7),
              child: Text(
                tr(fullName.isNotEmpty
                    ? fullName.characters.first.toUpperCase()
                    : '?'),
                style: const TextStyle(
                    color: Color(0xFFD97706),
                    fontWeight: FontWeight.bold,
                    fontSize: 13),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(tr(fullName.isEmpty ? 'N/A' : fullName),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (dept.isNotEmpty)
                    Text(tr(dept),
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF71717A))),
                ])),
            if (daysStr.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(tr(daysStr),
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFD97706))),
              ),
          ]),
          if (dateRange.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 12, color: Color(0xFF6B7280)),
              const SizedBox(width: 4),
              Text(tr(dateRange),
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
            ]),
          ],
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.notes_rounded,
                  size: 12, color: Color(0xFF9CA3AF)),
              const SizedBox(width: 4),
              Expanded(
                  child: Text(tr(reason),
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF6B7280)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis)),
            ]),
          ],
        ]),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(tr('${entry.value.length}'),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFD97706))),
              ),
              const SizedBox(width: 8),
              Text(tr(entry.key),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
          ),
          ...entry.value.map(leaveCard),
        ],
      ],
    );
  }

  Widget _buildContractDetailContent() {
    final expiring = _expiringDocs.whereType<Map<String, dynamic>>().toList();
    final expired =
        _expiredContracts.whereType<Map<String, dynamic>>().toList();

    if (expiring.isEmpty && expired.isEmpty) {
      return _emptyState('Không có hợp đồng cần xử lý');
    }

    Widget contractRow(Map<String, dynamic> d, {bool isExpired = false}) {
      final firstName = (d['firstName'] ?? '').toString();
      final lastName = (d['lastName'] ?? '').toString();
      final fullName = '$lastName $firstName'.trim();
      final dept = (d['department'] ?? '').toString();
      final days = (d['daysUntilExpiry'] as num?)?.toInt() ?? 0;
      final accent =
          isExpired ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
      final badge = isExpired
          ? '${(-days)} ngày trước'
          : (days == 0 ? 'Hôm nay' : '$days ngày');

      return InkWell(
        onTap: () {
          Navigator.of(context, rootNavigator: false).maybePop();
          final empId = (d['employeeId'] ??
                  d['userId'] ??
                  d['employeeUserId'] ??
                  d['id'] ??
                  '')
              .toString();
          final hi = empId.isEmpty ? null : empId;
          final perm =
              Provider.of<PermissionProvider>(context, listen: false);
          if (perm.canView('HrDocument')) {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => HrmPushedScreenShell(
                title: 'Tài liệu HR',
                child: HrDocumentsScreen(highlightId: hi),
              ),
            ));
          } else {
            NavigationNotifier.goToEmployeesHighlight(hi);
          }
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withValues(alpha: .2)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isExpired ? Icons.warning_rounded : Icons.schedule_rounded,
                size: 16,
                color: accent,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(tr(fullName.isEmpty ? 'N/A' : fullName),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (dept.isNotEmpty)
                    Text(tr(dept),
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF71717A))),
                ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: accent.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(tr(badge),
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: accent)),
            ),
          ]),
        ),
      );
    }

    Widget sectionHeader(String title, int count, Color color) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(tr('$count'),
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold, color: color)),
            ),
            const SizedBox(width: 8),
            Text(tr(title),
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (expiring.isNotEmpty) ...[
          sectionHeader('Cần gia hạn (trong 30 ngày)', expiring.length,
              const Color(0xFFF59E0B)),
          ...expiring.map((d) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: contractRow(d),
              )),
        ],
        if (expired.isNotEmpty) ...[
          if (expiring.isNotEmpty) const SizedBox(height: 8),
          sectionHeader('Đã hết hạn', expired.length, const Color(0xFFEF4444)),
          ...expired.map((d) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: contractRow(d, isExpired: true),
              )),
        ],
      ],
    );
  }

  Widget _buildBirthdayDetailContent() {
    final today = DateTime.now();
    final todayDay = today.day;

    final past = <Map<String, dynamic>>[];
    final todayList = <Map<String, dynamic>>[];
    final upcoming = <Map<String, dynamic>>[];

    final src = _birthdayEmployees.isNotEmpty ? _birthdayEmployees : _employees;
    for (final e in src.whereType<Map<String, dynamic>>()) {
      final dob = e['dateOfBirth'] ?? e['birthday'];
      if (dob == null) continue;
      try {
        final d = DateTime.parse(dob.toString());
        if (d.month != today.month) continue;
        final row = {...e, '_birthdayDay': d.day, '_birthdayDate': d};
        if (d.day < todayDay) {
          past.add(row);
        } else if (d.day == todayDay) {
          todayList.add(row);
        } else {
          upcoming.add(row);
        }
      } catch (_) {}
    }
    past.sort((a, b) =>
        (a['_birthdayDay'] as int).compareTo(b['_birthdayDay'] as int));
    upcoming.sort((a, b) =>
        (a['_birthdayDay'] as int).compareTo(b['_birthdayDay'] as int));

    const pink = Color(0xFFEC4899);
    const green = Color(0xFF22C55E);
    const grey = Color(0xFF94A3B8);

    Widget empRow(Map<String, dynamic> e, Color color) {
      final ln = (e['lastName'] ?? '').toString().trim();
      final fn = (e['firstName'] ?? '').toString().trim();
      final fp = [ln, fn].where((s) => s.isNotEmpty).join(' ');
      final name = (e['fullName'] ?? e['employeeName'] ?? e['name'] ?? '')
          .toString()
          .trim();
      final displayName = name.isNotEmpty ? name : (fp.isNotEmpty ? fp : '-');
      final dept = (e['departmentName'] ?? e['department'] ?? '').toString();
      final day = e['_birthdayDay'] as int? ?? 0;
      final id = (e['id'] ?? e['Id'] ?? '').toString();

      return InkWell(
        onTap: () {
          Navigator.of(context).maybePop();
          NavigationNotifier.goToEmployeesHighlight(
              id.isEmpty ? null : id);
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withValues(alpha: 0.15),
              child: Text(
                tr(displayName.isNotEmpty ? displayName[0].toUpperCase() : '?'),
                style: TextStyle(
                    color: color, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(tr(displayName),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (dept.isNotEmpty)
                    Text(tr(dept),
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF71717A)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(tr('Ngày $day'),
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600, color: color),
              ),
            ),
          ]),
        ),
      );
    }

    Widget section(String title, IconData icon, Color color,
        List<Map<String, dynamic>> list,
        {String? subtitle}) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(tr(title),
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: color)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(10)),
              child: Text(tr('${list.length}'),
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ),
            if (subtitle != null) ...[
              const SizedBox(width: 6),
              Text(tr(subtitle),
                  style: TextStyle(
                      fontSize: 11, color: color.withValues(alpha: 0.7))),
            ],
          ]),
        ),
        if (list.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 4),
            child: Text(tr('Không có'),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          )
        else
          ...list.map((e) => empRow(e, color)),
        const SizedBox(height: 10),
      ]);
    }

    if (past.isEmpty && todayList.isEmpty && upcoming.isEmpty) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(tr('Không có sinh nhật trong tháng này'),
            style: TextStyle(color: Colors.grey.shade500)),
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (todayList.isNotEmpty)
        section('🎂 Hôm nay', Icons.cake_rounded, pink, todayList),
      section('Sắp tới', Icons.upcoming_rounded, green, upcoming,
          subtitle: upcoming.isNotEmpty ? '${upcoming.length} NV' : null),
      section('Đã qua trong tháng', Icons.history_rounded, grey, past),
    ]);
  }

  Widget _buildOvertimeDetailContent() {
    final total = _toInt(_overtimeStats['totalRequests'] ??
        _overtimeStats['totalOvertimeCount'] ??
        _overtimeStats['count'] ??
        0);
    final hours = ((_overtimeStats['totalActualHours'] ??
            _overtimeStats['totalPlannedHours'] ??
            _overtimeStats['totalOvertimeHours'] ??
            _overtimeStats['hours'] ??
            0) as num)
        .toDouble();
    final approved = _toInt(
        _overtimeStats['approvedCount'] ?? _overtimeStats['approved'] ?? 0);
    final pending = _toInt(
        _overtimeStats['pendingCount'] ?? _overtimeStats['pending'] ?? 0);
    final completed = _toInt(_overtimeStats['completedCount'] ?? 0);
    return Column(children: [
      _detailStatRow(Icons.receipt_long_outlined, 'Tổng đơn OT', '$total',
          const Color(0xFF8B5CF6)),
      const SizedBox(height: 8),
      _detailStatRow(Icons.timer_outlined, 'Tổng giờ OT',
          '${hours.toStringAsFixed(1)} giờ', const Color(0xFF8B5CF6)),
      const SizedBox(height: 8),
      _detailStatRow(Icons.check_circle_outline, 'Đã duyệt', '$approved',
          const Color(0xFF22C55E)),
      const SizedBox(height: 8),
      _detailStatRow(
          Icons.task_alt, 'Hoàn thành', '$completed', HrmPageChrome.primaryNavy),
      const SizedBox(height: 8),
      _detailStatRow(Icons.pending_outlined, 'Chờ duyệt', '$pending',
          const Color(0xFFF59E0B)),
    ]);
  }

  Widget _buildTaskDetailContent() {
    final total = _toInt(_taskStats['totalTasks'] ?? _taskStats['total'] ?? 0);
    final todo = _toInt(_taskStats['todoCount'] ??
        _taskStats['pending'] ??
        _taskStats['notStarted'] ??
        0);
    final inProg =
        _toInt(_taskStats['inProgressCount'] ?? _taskStats['inProgress'] ?? 0);
    final done = _toInt(_taskStats['completedCount'] ??
        _taskStats['completed'] ??
        _taskStats['done'] ??
        0);
    final overdue =
        _toInt(_taskStats['overdueCount'] ?? _taskStats['overdue'] ?? 0);
    final assigned = _toInt(_taskStats['assignedCount'] ?? 0);
    final rate = total > 0 ? (done / total * 100) : 0.0;

    void openTask({int? statusIndex, bool overdueOnly = false}) {
      Navigator.of(context, rootNavigator: false).maybePop();
      NavigationNotifier.goToTaskManagementNav(
        statusIndex: statusIndex,
        overdueOnly: overdueOnly,
      );
    }

    Widget tappableRow(IconData icon, String label, String value, Color color,
        {int? statusIndex, bool overdueOnly = false}) {
      return InkWell(
        onTap: () => openTask(
            statusIndex: statusIndex, overdueOnly: overdueOnly),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(
                  child: _detailStatRow(icon, label, value, color)),
              const Icon(Icons.chevron_right,
                  size: 16, color: Color(0xFFCBD5E1)),
            ],
          ),
        ),
      );
    }

    return Column(children: [
      tappableRow(Icons.checklist, 'Tổng công việc', '$total',
          const Color(0xFF2D5F8B)),
      const SizedBox(height: 8),
      tappableRow(Icons.radio_button_unchecked, 'Chờ làm', '$todo',
          const Color(0xFF71717A),
          statusIndex: WorkTaskStatus.todo.index),
      if (assigned > 0) ...[
        const SizedBox(height: 8),
        tappableRow(Icons.assignment_late_outlined, 'Chờ xác nhận', '$assigned',
            const Color(0xFFF59E0B),
            statusIndex: WorkTaskStatus.assigned.index),
      ],
      const SizedBox(height: 8),
      tappableRow(Icons.autorenew, 'Đang làm', '$inProg', const Color(0xFFF59E0B),
          statusIndex: WorkTaskStatus.inProgress.index),
      const SizedBox(height: 8),
      tappableRow(Icons.check_circle, 'Hoàn thành', '$done',
          const Color(0xFF22C55E),
          statusIndex: WorkTaskStatus.completed.index),
      const SizedBox(height: 8),
      tappableRow(Icons.warning_amber, 'Quá hạn', '$overdue',
          const Color(0xFFEF4444),
          overdueOnly: true),
      const SizedBox(height: 12),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(
          value: rate / 100,
          minHeight: 10,
          backgroundColor: const Color(0xFFE4E4E7),
          valueColor: AlwaysStoppedAnimation(rate >= 80
              ? const Color(0xFF22C55E)
              : rate >= 50
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFFEF4444)),
        ),
      ),
      const SizedBox(height: 4),
      Text(tr('Tỉ lệ hoàn thành: ${rate.toStringAsFixed(0)}%'),
          style: const TextStyle(fontSize: 12, color: Color(0xFF71717A))),
    ]);
  }

  Widget _buildPenaltyDetailContent() {
    // Backend PenaltyTicketStats returns: totalPending, totalApproved, totalAutoApproved,
    // totalCancelled, pendingAmount, approvedAmount.
    final pending = _toInt(_penaltyStats['totalPending'] ?? 0);
    final approved = _toInt(_penaltyStats['totalApproved'] ?? 0);
    final autoApproved = _toInt(_penaltyStats['totalAutoApproved'] ?? 0);
    final cancelled = _toInt(_penaltyStats['totalCancelled'] ?? 0);
    final total = pending + approved + autoApproved + cancelled;
    final totalFine = (((_penaltyStats['pendingAmount'] ?? 0) as num) +
            ((_penaltyStats['approvedAmount'] ?? 0) as num))
        .toDouble();

    // Navigate to PenaltyTicketsScreen pre-filtered by status.
    // statusFilter: null=all, '0'=Pending, '1'=Approved, '2'=Cancelled, '3'=AutoApproved
    void openFiltered(String? statusFilter) {
      Navigator.of(context, rootNavigator: false).maybePop();
      NavigationNotifier.goToPenaltyTicketsNav(filterStatus: statusFilter);
    }

    Widget tappableRow(IconData icon, String label, String value, Color color,
        String? statusFilter) {
      return InkWell(
        onTap: () => openFiltered(statusFilter),
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            _detailStatRow(icon, label, value, color),
            Positioned(
              right: 10,
              top: 0,
              bottom: 0,
              child: Center(
                child: Icon(Icons.chevron_right,
                    size: 16, color: color.withValues(alpha: 0.6)),
              ),
            ),
          ],
        ),
      );
    }

    return Column(children: [
      tappableRow(Icons.receipt_long, 'Tổng phiếu vi phạm', '$total',
          const Color(0xFFDC2626), null),
      const SizedBox(height: 8),
      _detailStatRow(Icons.attach_money, 'Tổng tiền phạt',
          '${_fmtMoney(totalFine)}đ', const Color(0xFFDC2626)),
      const SizedBox(height: 8),
      tappableRow(Icons.check_circle_outline, 'Đã duyệt', '$approved',
          const Color(0xFF22C55E), '1'),
      const SizedBox(height: 8),
      tappableRow(Icons.bolt_outlined, 'Tự duyệt', '$autoApproved',
          HrmPageChrome.primaryNavy, '3'),
      const SizedBox(height: 8),
      tappableRow(Icons.pending_outlined, 'Chờ xử lý', '$pending',
          const Color(0xFFF59E0B), '0'),
      const SizedBox(height: 8),
      tappableRow(Icons.cancel_outlined, 'Đã hủy', '$cancelled',
          const Color(0xFF71717A), '2'),
      const SizedBox(height: 10),
      Text(tr('Nhấn vào từng mục để xem danh sách'),
        style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade500,
            fontStyle: FontStyle.italic),
        textAlign: TextAlign.center,
      ),
    ]);
  }

  Widget _buildFinanceDetailContent() {
    final income =
        ((_cashSummary['totalIncome'] ?? _cashSummary['totalIn'] ?? 0) as num)
            .toDouble();
    final expense =
        ((_cashSummary['totalExpense'] ?? _cashSummary['totalOut'] ?? 0) as num)
            .toDouble();
    final net = income - expense;
    final txCount =
        _toInt(_cashSummary['totalTransactions'] ?? _cashSummary['count'] ?? 0);
    return Column(children: [
      _detailStatRow(Icons.trending_up, 'Tổng thu', '${_fmtMoney(income)}đ',
          const Color(0xFF22C55E)),
      const SizedBox(height: 8),
      _detailStatRow(Icons.trending_down, 'Tổng chi', '${_fmtMoney(expense)}đ',
          const Color(0xFFEF4444)),
      const SizedBox(height: 8),
      _detailStatRow(
          Icons.account_balance,
          'Tồn quỹ',
          '${net >= 0 ? '+' : ''}${_fmtMoney(net)}đ',
          net >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626)),
      const SizedBox(height: 8),
      _detailStatRow(
          Icons.receipt, 'Số giao dịch', '$txCount', const Color(0xFF2D5F8B)),
    ]);
  }

  Widget _detailStatRow(
      IconData icon, String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Text(tr(label),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500))),
        Text(tr(value),
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }

  // Short label shown in the title chip describing the active range
  String _rangeLabel() {
    String d(DateTime x) => '${x.day}/${x.month}';
    switch (_presetKey) {
      case 'today':
        return '';
      case 'yesterday':
        return 'Hôm qua';
      case 'custom':
        return _selectedDate == null ? '' : d(_selectedDate!);
      default:
        if (_rangeStart != null && _rangeEnd != null) {
          return '${d(_rangeStart!)} – ${d(_rangeEnd!)}';
        }
        return '';
    }
  }

  Widget _buildPresetChip(String key, String label) {
    final selected = _presetKey == key;
    return InkWell(
      onTap: () => _applyPreset(key),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? HrmPageChrome.primaryNavy : Colors.white,
          border: Border.all(
              color:
                  selected ? HrmPageChrome.primaryNavy : const Color(0xFFE4E9F0)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          tr(label),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  void _applyPreset(String key) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime? start;
    DateTime? end;
    DateTime? single;

    // Ngày làm việc hiệu dụng: nếu giờ hiện tại < day_end_time (cutoff),
    // ca làm việc hôm nay thực chất bắt đầu từ ngày hôm qua (lịch).
    // Ví dụ: cutoff = 05:00, lúc 02:00 AM → effectiveToday = hôm qua lịch.
    final hasCutoff = _dayEndHour != 0 || _dayEndMinute != 0;
    final nowMinutes = now.hour * 60 + now.minute;
    final cutoffMinutes = _dayEndHour * 60 + _dayEndMinute;
    final effectiveToday = (hasCutoff && nowMinutes < cutoffMinutes)
        ? today.subtract(const Duration(days: 1))
        : today;

    switch (key) {
      case 'today':
        single = effectiveToday;
        break;
      case 'yesterday':
        // "Hôm qua" = ngày làm việc trước ngày làm việc hiệu dụng hiện tại.
        // Ví dụ: cutoff=05:00, lúc 02:00 → effectiveToday=1/5 → yesterday=30/4
        //        cutoff=05:00, lúc 06:00 → effectiveToday=2/5 → yesterday=1/5
        single = effectiveToday.subtract(const Duration(days: 1));
        break;
      case 'thisWeek':
        // Monday = 1 ... Sunday = 7
        start = effectiveToday.subtract(Duration(days: effectiveToday.weekday - 1));
        end = start.add(const Duration(days: 6));
        break;
      case 'lastWeek':
        final thisMon =
            effectiveToday.subtract(Duration(days: effectiveToday.weekday - 1));
        start = thisMon.subtract(const Duration(days: 7));
        end = thisMon.subtract(const Duration(days: 1));
        break;
      case 'thisMonth':
        start = DateTime(effectiveToday.year, effectiveToday.month, 1);
        end = DateTime(effectiveToday.year, effectiveToday.month + 1, 0);
        break;
      case 'lastMonth':
        final firstThis = DateTime(effectiveToday.year, effectiveToday.month, 1);
        final lastDayPrev = firstThis.subtract(const Duration(days: 1));
        start = DateTime(lastDayPrev.year, lastDayPrev.month, 1);
        end = lastDayPrev;
        break;
    }

    setState(() {
      _presetKey = key;
      if (single != null) {
        _selectedDate =
            key == 'today' ? null : single; // null means "today" for API
        _rangeStart = null;
        _rangeEnd = null;
      } else if (start != null && end != null) {
        _rangeStart = start;
        _rangeEnd = end.isAfter(effectiveToday) ? effectiveToday : end;
        // Use the end of the range (capped to today) as the "target" day
        // for the daily snapshot.
        _selectedDate = _rangeEnd;
      }
    });
    _loadAllData();
  }

  int _daysAgo(DateTime d) {
    final now = DateTime.now();
    final a = DateTime(now.year, now.month, now.day);
    final b = DateTime(d.year, d.month, d.day);
    return a.difference(b).inDays;
  }

  Future<void> _pickCustomDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _presetKey = 'custom';
        _selectedDate = picked;
        _rangeStart = null;
        _rangeEnd = null;
      });
      _loadAllData();
    }
  }

  Widget _buildDateChip(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? HrmPageChrome.primaryNavy : Colors.white,
          border: Border.all(
              color:
                  selected ? HrmPageChrome.primaryNavy : const Color(0xFFE4E9F0)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          tr(label),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : const Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _buildDonutCard(double rate) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4E9F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('Tỉ lệ có mặt'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 4),
          _buildAttendanceDonut(rate),
        ],
      ),
    );
  }

  Widget _buildAttendanceDonut(double rate) {
    // Per-shift present counts from _shiftPairs
    final shiftCounts = <String, int>{};
    for (final p in _shiftPairs) {
      if (p.checkIn == null) continue;
      final key = p.shiftName.isNotEmpty ? p.shiftName : 'Không rõ';
      shiftCounts[key] = (shiftCounts[key] ?? 0) + 1;
    }
    final shiftNames = shiftCounts.keys.toList()
      ..sort((a, b) => shiftCounts[b]!.compareTo(shiftCounts[a]!));

    const palette = [
      Color(0xFF22C55E),
      Color(0xFF3B82F6),
      Color(0xFF8B5CF6),
      Color(0xFFF59E0B),
      Color(0xFF10B981),
      Color(0xFFEC4899),
    ];

    final double total = _totalEmployees > 0 ? _totalEmployees.toDouble() : 1.0;
    final double present = _presentCount.toDouble();
    final double absent = (total - present).clamp(0.0, total);

    final Color mainColor = rate >= 85
        ? const Color(0xFF22C55E)
        : rate >= 70
            ? const Color(0xFFF59E0B)
            : const Color(0xFFEF4444);

    // Build sections with touch-aware radius
    final sections = <PieChartSectionData>[];
    int sectionIdx = 0;
    if (shiftNames.isEmpty) {
      final isTouched = _touchedDonutIndex == 0;
      sections.add(PieChartSectionData(
        value: present > 0 ? present : 0.0001,
        color: mainColor,
        radius: isTouched ? 34 : 26,
        showTitle: false,
      ));
      sectionIdx++;
    } else {
      for (var i = 0; i < shiftNames.length; i++) {
        final isTouched = _touchedDonutIndex == sectionIdx;
        sections.add(PieChartSectionData(
          value: shiftCounts[shiftNames[i]]!.toDouble(),
          color: palette[i % palette.length],
          radius: isTouched ? 34 : 26,
          showTitle: false,
        ));
        sectionIdx++;
      }
    }
    // absent section index
    final absentIdx = sectionIdx;
    if (absent > 0) {
      final isTouched = _touchedDonutIndex == absentIdx;
      sections.add(PieChartSectionData(
        value: absent,
        color: const Color(0xFFE2E8F0),
        radius: isTouched ? 34 : 26,
        showTitle: false,
      ));
    }

    // Determine center display based on touched section
    String centerTop;
    String centerSub;
    Color centerColor;
    if (_touchedDonutIndex >= 0 && _touchedDonutIndex < sections.length) {
      final isAbsent = _touchedDonutIndex == absentIdx;
      if (isAbsent) {
        final absPct = total > 0 ? (absent / total * 100) : 0.0;
        centerTop = '${absPct.toStringAsFixed(1)}%';
        centerSub = '${absent.toInt()} NV vắng';
        centerColor = const Color(0xFF94A3B8);
      } else {
        final shiftIdx = shiftNames.isEmpty ? -1 : _touchedDonutIndex;
        if (shiftIdx >= 0 && shiftIdx < shiftNames.length) {
          final cnt = shiftCounts[shiftNames[shiftIdx]]!;
          final pct = total > 0 ? (cnt / total * 100) : 0.0;
          centerTop = '${pct.toStringAsFixed(1)}%';
          centerSub = '$cnt NV • ${shiftNames[shiftIdx]}';
          centerColor = palette[shiftIdx % palette.length];
        } else {
          final pct = total > 0 ? (present / total * 100) : 0.0;
          centerTop = '${pct.toStringAsFixed(1)}%';
          centerSub = '${present.toInt()} NV có mặt';
          centerColor = mainColor;
        }
      }
    } else {
      centerTop = '${rate.toStringAsFixed(1)}%';
      centerSub = '$_presentCount / $_totalEmployees NV';
      centerColor = mainColor;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 175,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 66,
                    startDegreeOffset: -90,
                    sections: sections,
                    pieTouchData: PieTouchData(
                      touchCallback:
                          (FlTouchEvent event, PieTouchResponse? resp) {
                        setState(() {
                          if (event is FlLongPressEnd ||
                              event is FlTapUpEvent ||
                              event is FlPointerExitEvent) {
                            _touchedDonutIndex = -1;
                          } else if (resp != null &&
                              resp.touchedSection != null) {
                            _touchedDonutIndex =
                                resp.touchedSection!.touchedSectionIndex;
                          }
                        });
                      },
                    ),
                  ),
                ),
              ),
              IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Text(
                          tr(centerTop),
                          key: ValueKey(centerTop),
                          style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: centerColor),
                        ),
                      ),
                      const SizedBox(height: 2),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: Text(
                          tr(centerSub),
                          key: ValueKey(centerSub),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF94A3B8),
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                      if (_touchedDonutIndex < 0) ...[
                        const SizedBox(height: 2),
                        Text(tr('Tỉ lệ có mặt'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (shiftNames.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            alignment: WrapAlignment.start,
            children: [
              for (var i = 0; i < shiftNames.length && i < 4; i++)
                _donutLegendItem(
                  palette[i % palette.length],
                  shiftNames[i],
                  shiftCounts[shiftNames[i]]!,
                ),
              if (shiftNames.length > 4)
                Padding(
                  padding: const EdgeInsets.only(left: 2, top: 2),
                  child: Text(
                    tr('+${shiftNames.length - 4} ca'),
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildHeroKpiTiles() {
    final tiles = <_HeroKpi>[
      _HeroKpi('Tổng NV', '$_totalEmployees', Icons.people_alt_rounded,
          HrmPageChrome.primaryNavy, 'total'),
      _HeroKpi(_presentShiftLabel, '$_presentCount', Icons.how_to_reg_rounded,
          const Color(0xFF22C55E), 'present'),
      _HeroKpi('Đi trễ / Về sớm', '$_lateCount', Icons.schedule_rounded,
          const Color(0xFFF59E0B), 'late'),
      _HeroKpi('Vắng', '$_absentCount', Icons.person_off_rounded,
          const Color(0xFFEF4444), 'absent'),
      _HeroKpi('Vào / Ra', '$_checkIns / $_checkOuts', Icons.swap_horiz_rounded,
          const Color(0xFF2D5F8B), 'inout'),
      _HeroKpi('Thiết bị', '$_onlineDevices/$_totalDevices',
          Icons.router_rounded, HrmPageChrome.primaryNavy, 'devices'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        // <520: 2 cột (2×2); >=520: 4 cột một hàng (desktop / tablet ngang)
        final cols = w >= 520 ? 4 : 2;
        final compact = cols <= 2;
        final gap = 8.0;
        final itemW = (w - gap * (cols - 1)) / cols;

        Widget grid(List<_HeroKpi> items) {
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final k in items)
                SizedBox(
                  width: itemW,
                  child: _buildHeroKpiTile(k, compact: compact),
                ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            grid(tiles.take(4).toList()),
            const SizedBox(height: 8),
            grid(tiles.skip(4).toList()),
          ],
        );
      },
    );
  }

  /// Nhãn ngắn trên mobile — tránh cắt "TANG CA..." / "Đi trễ / Về sớm".
  String _heroKpiShortLabel(_HeroKpi k, bool compact) {
    if (!compact) return k.label;
    switch (k.kind) {
      case 'total':
        return 'Tổng NV';
      case 'present':
        return 'Có mặt';
      case 'late':
        return 'Trễ / Sớm';
      case 'absent':
        return 'Vắng';
      case 'inout':
        return 'Vào / Ra';
      case 'devices':
        return 'Thiết bị';
      default:
        return k.label;
    }
  }

  Widget _buildHeroKpiTile(_HeroKpi k, {bool compact = false}) {
    final label = _heroKpiShortLabel(k, compact);
    final decoration = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE4E9F0)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    );

    if (compact) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showKpiDetail(k),
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            decoration: decoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: k.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(k.icon, size: 16, color: k.color),
                    ),
                    const Spacer(),
                    Text(
                      tr(k.value),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: k.color,
                        height: 1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  tr(label),
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                  maxLines: 2,
                  softWrap: true,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showKpiDetail(k),
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          decoration: decoration,
          child: Row(
            children: [
              Container(
                width: 3,
                height: 44,
                decoration: BoxDecoration(
                  color: k.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(label),
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr(k.value),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: k.color,
                        height: 1.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(k.icon, size: 18, color: k.color.withValues(alpha: 0.55)),
            ],
          ),
        ),
      ),
    );
  }

  // ===================== KPI DETAIL SHEET =====================
  void _showKpiDetail(_HeroKpi k) {
    if (k.kind == 'inout') {
      _showInOutDetail();
      return;
    }
    if (k.kind == 'late') {
      _showLateDetail();
      return;
    }
    if (k.kind == 'present') {
      _showPresentDetail();
      return;
    }
    if (k.kind == 'total') {
      _showTotalDetail();
      return;
    }
    if (k.kind == 'absent') {
      _showAbsentDetail();
      return;
    }
    final items = _kpiDetailData(k.kind);
    showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                // Drag handle
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: k.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(k.icon, color: k.color, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr(k.label),
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A))),
                            Text(tr('${items.length} mục'),
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // List
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inbox_outlined,
                                  size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 8),
                              Text(tr('Không có dữ liệu'),
                                  style:
                                      TextStyle(color: Colors.grey.shade600)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (_, i) => InkWell(
                            onTap: () {
                              Navigator.pop(ctx);
                              if (k.kind == 'late') {
                                NavigationNotifier.goToModule(
                                    'AttendanceByShift');
                              }
                            },
                            borderRadius: BorderRadius.circular(10),
                            child:
                                _buildKpiDetailRow(k.kind, items[i], k.color),
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Bottom-sheet Tổng NV — gom theo phòng ban, mỗi NV hiển thị ca lịch
  /// (vàng) và ca đã chấm vào (xanh).
  void _showTotalDetail() {
    // ── Build lookups ────────────────────────────────────────────────────────
    // schedulesByEmpId: employeeId/code → list of shiftName from work schedule today
    // Use LinkedHashSet to preserve insertion order while deduplicating.
    final schedulesByEmpId = <String, LinkedHashSet<String>>{};
    for (final s in _todaySchedules.whereType<Map<String, dynamic>>()) {
      if (s['isDayOff'] == true) continue;
      final shiftName =
          (s['shiftName'] ?? s['shift']?['name'] ?? '').toString();
      if (shiftName.isEmpty) continue;
      final id =
          (s['employeeId'] ?? s['employeeUserId'] ?? s['employeeCode'] ?? '')
              .toString();
      if (id.isEmpty) continue;
      (schedulesByEmpId[id] ??= LinkedHashSet<String>()).add(shiftName);
    }

    // checkedInShiftsByEmpCode: employeeCode/id → set of shiftName actually punched
    final checkedInByEmpCode = <String, Set<String>>{};
    for (final p in _shiftPairs) {
      if (p.checkIn == null) continue;
      final key = p.employeeCode.isNotEmpty ? p.employeeCode : p.employeeId;
      if (key.isEmpty) continue;
      (checkedInByEmpCode[key] ??= <String>{}).add(p.shiftName);
    }

    // Also mark employees with checkInTime from daily report (when shiftPairs may be sparse)
    final dailyCheckedInIds = <String>{};
    for (final r in _dailyReportItems.whereType<Map<String, dynamic>>()) {
      if (r['checkInTime'] != null) {
        final id = (r['employeeId'] ?? r['employeeCode'] ?? '').toString();
        if (id.isNotEmpty) dailyCheckedInIds.add(id);
      }
    }

    // ── Group _dailyReportItems by department ────────────────────────────────
    final deptOrder = <String>[];
    final byDept = <String, List<Map<String, dynamic>>>{};
    for (final raw in _dailyReportItems.whereType<Map<String, dynamic>>()) {
      final dept = (raw['departmentName'] ??
              raw['department'] ??
              raw['Department'] ??
              '')
          .toString();
      final deptLabel = dept.isNotEmpty ? dept : 'Không có phòng ban';
      if (!byDept.containsKey(deptLabel)) {
        deptOrder.add(deptLabel);
        byDept[deptLabel] = [];
      }
      byDept[deptLabel]!.add(raw);
    }
    // Sort: larger depts first; sort employees within each dept by name
    deptOrder.sort((a, b) => byDept[b]!.length.compareTo(byDept[a]!.length));
    for (final list in byDept.values) {
      list.sort((a, b) => (a['employeeName'] ?? '')
          .toString()
          .compareTo((b['employeeName'] ?? '').toString()));
    }

    showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (sheetCtx, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                // drag handle
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 12, 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:
                              HrmPageChrome.primaryNavy.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.people_alt_rounded,
                            color: HrmPageChrome.primaryNavy, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('Tổng nhân viên'),
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A))),
                            Text(tr('${_dailyReportItems.length} NV · ${deptOrder.length} phòng ban'),
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      // Legend
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        _totalLegendDot(const Color(0xFFF59E0B), 'Lịch'),
                        const SizedBox(width: 8),
                        _totalLegendDot(const Color(0xFF22C55E), 'Đã vào'),
                      ]),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Department list
                Expanded(
                  child: byDept.isEmpty
                      ? Center(
                          child: Text(tr('Chưa có dữ liệu'),
                              style: TextStyle(color: Colors.grey.shade500)))
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          itemCount: deptOrder.length,
                          itemBuilder: (_, di) {
                            final deptName = deptOrder[di];
                            final emps = byDept[deptName]!;
                            final presentCount = emps.where((e) {
                              final id =
                                  (e['employeeId'] ?? e['employeeCode'] ?? '')
                                      .toString();
                              return dailyCheckedInIds.contains(id) ||
                                  e['checkInTime'] != null;
                            }).length;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Department header
                                  Row(children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: HrmPageChrome.primaryNavy
                                            .withValues(alpha: 0.09),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.business_rounded,
                                                size: 13,
                                                color: HrmPageChrome.primaryNavy),
                                            const SizedBox(width: 4),
                                            Text(tr(deptName),
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: HrmPageChrome.primaryNavy)),
                                          ]),
                                    ),
                                    const SizedBox(width: 8),
                                    _inOutChip('$presentCount/${emps.length}',
                                        presentCount, const Color(0xFF22C55E)),
                                  ]),
                                  const SizedBox(height: 6),
                                  // Employee rows
                                  ...emps.map((emp) {
                                    final empId = (emp['employeeId'] ??
                                            emp['employeeCode'] ??
                                            '')
                                        .toString();
                                    final empCode =
                                        (emp['employeeCode'] ?? '').toString();
                                    final name = (emp['employeeName'] ??
                                            emp['fullName'] ??
                                            '?')
                                        .toString();
                                    final hasCheckedIn =
                                        emp['checkInTime'] != null ||
                                            dailyCheckedInIds.contains(empId) ||
                                            dailyCheckedInIds.contains(empCode);
                                    // Scheduled shifts for this employee (deduplicated)
                                    final scheduledShifts =
                                        (schedulesByEmpId[empId] ??
                                                schedulesByEmpId[empCode] ??
                                                <String>{})
                                            .toList();
                                    // Checked-in shifts
                                    final checkedShifts =
                                        checkedInByEmpCode[empCode] ??
                                            checkedInByEmpCode[empId] ??
                                            <String>{};
                                    final checkInStr =
                                        _formatTime(emp['checkInTime']);
                                    final checkOutStr =
                                        _formatTime(emp['checkOutTime']);
                                    final status = (emp['status'] ?? '')
                                        .toString()
                                        .toLowerCase();
                                    final isLate = status.contains('trễ') ||
                                        status.contains('muộn');
                                    final isEarly = status.contains('sớm');

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 5),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: hasCheckedIn
                                            ? const Color(0xFFF0FDF4)
                                            : const Color(0xFFF8FAFC),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: hasCheckedIn
                                              ? const Color(0xFF22C55E)
                                                  .withValues(alpha: 0.25)
                                              : Colors.grey.shade200,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(children: [
                                            CircleAvatar(
                                              radius: 16,
                                              backgroundColor: (hasCheckedIn
                                                      ? const Color(0xFF22C55E)
                                                      : const Color(0xFF94A3B8))
                                                  .withValues(alpha: 0.18),
                                              child: Text(
                                                tr(name.isNotEmpty
                                                    ? name[0].toUpperCase()
                                                    : '?'),
                                                style: TextStyle(
                                                  color: hasCheckedIn
                                                      ? const Color(0xFF16A34A)
                                                      : const Color(0xFF64748B),
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(tr(name),
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 13),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis),
                                            ),
                                            // Check-in / check-out times
                                            if (checkInStr.isNotEmpty) ...[
                                              const Icon(Icons.login,
                                                  size: 11,
                                                  color: Color(0xFF22C55E)),
                                              const SizedBox(width: 2),
                                              Text(tr(checkInStr),
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: isLate
                                                          ? const Color(
                                                              0xFFF59E0B)
                                                          : const Color(
                                                              0xFF16A34A))),
                                            ],
                                            if (checkOutStr.isNotEmpty) ...[
                                              const SizedBox(width: 5),
                                              const Icon(Icons.logout,
                                                  size: 11,
                                                  color: Color(0xFFEF4444)),
                                              const SizedBox(width: 2),
                                              Text(tr(checkOutStr),
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: isEarly
                                                          ? const Color(
                                                              0xFFF59E0B)
                                                          : const Color(
                                                              0xFFDC2626))),
                                            ],
                                            if (!hasCheckedIn)
                                              const Padding(
                                                padding:
                                                    EdgeInsets.only(left: 4),
                                                child: Icon(
                                                    Icons.person_off_outlined,
                                                    size: 14,
                                                    color: Color(0xFF94A3B8)),
                                              ),
                                          ]),
                                          // Shift chips: scheduled (yellow→green when punched) + extra punched
                                          if (scheduledShifts.isNotEmpty ||
                                              checkedShifts.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 5, left: 2),
                                              child: Wrap(
                                                spacing: 4,
                                                runSpacing: 3,
                                                children: [
                                                  // Scheduled shifts: green if punched, yellow if not
                                                  ...scheduledShifts.map((sn) {
                                                    final done = checkedShifts
                                                        .contains(sn);
                                                    return _shiftChip(
                                                        sn,
                                                        done
                                                            ? const Color(
                                                                0xFF22C55E)
                                                            : const Color(
                                                                0xFFF59E0B));
                                                  }),
                                                  // Extra: punched shifts not in schedule
                                                  ...checkedShifts
                                                      .where((sn) =>
                                                          !scheduledShifts
                                                              .contains(sn))
                                                      .map((sn) => _shiftChip(
                                                          sn,
                                                          const Color(
                                                              0xFF22C55E))),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _shiftChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          color == const Color(0xFF22C55E)
              ? Icons.check_circle_outline
              : Icons.schedule_outlined,
          size: 10,
          color: color,
        ),
        const SizedBox(width: 3),
        Text(tr(label),
            style: TextStyle(
                fontSize: 10, color: color, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _donutLegendItem(Color color, String label, int count) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(tr('$label: '),
          style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
      Text(tr('$count NV'),
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w700)),
    ]);
  }

  Widget _totalLegendDot(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 3),
      Text(tr(label),
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    ]);
  }

  /// Bottom-sheet Vắng mặt — nhân viên vắng hôm nay, gom theo ca lịch.
  void _showAbsentDetail() {
    // ── Build schedules: empId/code → LinkedHashSet<shiftName> ─────────────
    final schedulesByEmpId = <String, LinkedHashSet<String>>{};
    for (final s in _todaySchedules.whereType<Map<String, dynamic>>()) {
      if (s['isDayOff'] == true) continue;
      final shiftName =
          (s['shiftName'] ?? s['shift']?['name'] ?? '').toString();
      if (shiftName.isEmpty) continue;
      final id =
          (s['employeeId'] ?? s['employeeUserId'] ?? s['employeeCode'] ?? '')
              .toString();
      if (id.isEmpty) continue;
      (schedulesByEmpId[id] ??= LinkedHashSet<String>()).add(shiftName);
    }

    // ── Group absent employees by scheduled shift ────────────────────────
    // _memoAbsent đã được tính nhất quán với chip count trong _recomputeMemoized.
    // Dùng trực tiếp để tránh phân kỳ giữa chip và popup.
    final shiftOrder = <String>[];
    final byShift = <String, List<Map<String, dynamic>>>{};
    final noShiftAbsent = <Map<String, dynamic>>[];
    final seenEmpCodes = <String>{};

    // Dùng _memoAbsent trực tiếp — đã được tính nhất quán với chip count
    // trong _recomputeMemoized(), tránh phân kỳ logic giữa chip và popup.
    for (final raw in _memoAbsent) {
      final code = (raw['employeeCode'] ?? raw['employeeId'] ?? '').toString();
      final empId = (raw['employeeId'] ?? '').toString();

      final key = code.isNotEmpty ? code : empId;
      seenEmpCodes.add(key);

      final shifts = (schedulesByEmpId[code] ??
              schedulesByEmpId[empId] ??
              <String>{})
          .toList();
      if (shifts.isEmpty) {
        noShiftAbsent.add(raw);
      } else {
        for (final shiftName in shifts) {
          if (!byShift.containsKey(shiftName)) {
            shiftOrder.add(shiftName);
            byShift[shiftName] = [];
          }
          byShift[shiftName]!.add(raw);
        }
      }
    }

    // Khi không có lịch (schedulesByEmpId rỗng) → group theo phòng ban thay vì
    // dồn hết vào "Không rõ ca".
    if (byShift.isEmpty && noShiftAbsent.isNotEmpty) {
      final byDept = <String, List<Map<String, dynamic>>>{};
      for (final raw in noShiftAbsent) {
        final dept =
            (raw['departmentName'] ?? raw['department'] ?? 'Chưa phân bộ phận')
                .toString();
        final label = dept.isNotEmpty ? dept : 'Chưa phân bộ phận';
        (byDept[label] ??= []).add(raw);
      }
      // Move dept groups into byShift/shiftOrder (reuse same rendering)
      final deptKeys = byDept.keys.toList()
        ..sort((a, b) => byDept[b]!.length.compareTo(byDept[a]!.length));
      for (final d in deptKeys) {
        shiftOrder.add(d);
        byShift[d] = byDept[d]!;
      }
      noShiftAbsent.clear();
    }

    // Sort: most absent first per shift; employees by name
    shiftOrder.sort((a, b) => byShift[b]!.length.compareTo(byShift[a]!.length));
    for (final list in byShift.values) {
      list.sort((a, b) => (a['employeeName'] ?? '')
          .toString()
          .compareTo((b['employeeName'] ?? '').toString()));
    }
    noShiftAbsent.sort((a, b) => (a['employeeName'] ?? '')
        .toString()
        .compareTo((b['employeeName'] ?? '').toString()));

    final totalSections =
        shiftOrder.length + (noShiftAbsent.isNotEmpty ? 1 : 0);

    showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (sheetCtx, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                // Drag handle
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 12, 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFEF4444).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.person_off_rounded,
                            color: Color(0xFFEF4444), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('Vắng mặt'),
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A))),
                            Text(tr(() {
                              final reportDate = _effectiveDate ??
                                  _selectedDate ??
                                  DateTime.now();
                              final dateLabel =
                                  '${reportDate.day.toString().padLeft(2, '0')}/${reportDate.month.toString().padLeft(2, '0')}/${reportDate.year}';
                              return '${seenEmpCodes.length} NV · $dateLabel';
                            }()),
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Content
                Expanded(
                  child: (byShift.isEmpty && noShiftAbsent.isEmpty)
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_outline,
                                  size: 48, color: Colors.green.shade400),
                              const SizedBox(height: 8),
                              Text(tr('Không có ai vắng mặt'),
                                  style:
                                      TextStyle(color: Colors.grey.shade600)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          itemCount: totalSections,
                          itemBuilder: (_, idx) {
                            final isNoShift = idx == shiftOrder.length;
                            final shiftLabel =
                                isNoShift ? 'Không rõ ca' : shiftOrder[idx];
                            final emps = isNoShift
                                ? noShiftAbsent
                                : byShift[shiftLabel]!;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Shift header
                                  Row(children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEF4444)
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                            color: const Color(0xFFEF4444)
                                                .withValues(alpha: 0.3)),
                                      ),
                                      child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                                Icons.access_time_rounded,
                                                size: 12,
                                                color: Color(0xFFEF4444)),
                                            const SizedBox(width: 4),
                                            Text(tr(shiftLabel),
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFFEF4444))),
                                          ]),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(tr('${emps.length} vắng'),
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade700,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                  ]),
                                  const SizedBox(height: 6),
                                  // Employee cards
                                  ...emps.map((raw) {
                                    final empName = (raw['employeeName'] ??
                                            raw['fullName'] ??
                                            '')
                                        .toString();
                                    final dept = (raw['departmentName'] ??
                                            raw['department'] ??
                                            '')
                                        .toString();
                                    final status =
                                        (raw['status'] ?? '').toString();

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEF4444)
                                            .withValues(alpha: 0.04),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                            color: const Color(0xFFEF4444)
                                                .withValues(alpha: 0.15)),
                                      ),
                                      child: Row(children: [
                                        CircleAvatar(
                                          radius: 16,
                                          backgroundColor:
                                              const Color(0xFFEF4444)
                                                  .withValues(alpha: 0.12),
                                          child: Text(
                                            tr(empName.isNotEmpty
                                                ? empName[0].toUpperCase()
                                                : '?'),
                                            style: const TextStyle(
                                                color: Color(0xFFDC2626),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(tr(empName),
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 13),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis),
                                              if (dept.isNotEmpty)
                                                Text(tr(dept),
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors
                                                            .grey.shade500),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis),
                                            ],
                                          ),
                                        ),
                                        // Status badge
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEF4444)
                                                .withValues(alpha: 0.1),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            tr(status.isNotEmpty ? status : 'Vắng'),
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: Color(0xFFEF4444),
                                                fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ]),
                                    );
                                  }),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Bottom-sheet Có mặt — nhân viên đã chấm công hôm nay, gom theo ca.
  void _showPresentDetail() {
    // ── Group _shiftPairs by shiftName ──────────────────────────────────────
    // Only employees who actually checked in (checkIn != null).
    final shiftOrder = <String>[];
    final byShift = <String, List<DailyShiftPair>>{};

    // Fallback: nếu shiftPairs chưa có (raw chưa load), dùng _kpiDetailData
    final useShiftPairs = _shiftPairs.isNotEmpty;

    if (useShiftPairs) {
      for (final p in _shiftPairs) {
        if (p.checkIn == null) continue; // chưa vào không tính có mặt
        final shiftLabel = p.shiftName.isNotEmpty ? p.shiftName : 'Không rõ ca';
        if (!byShift.containsKey(shiftLabel)) {
          shiftOrder.add(shiftLabel);
          byShift[shiftLabel] = [];
        }
        byShift[shiftLabel]!.add(p);
      }
      // Sort each shift's employees alphabetically by name
      for (final list in byShift.values) {
        list.sort((a, b) => a.employeeName.compareTo(b.employeeName));
      }
      // Sort shifts by employee count desc
      shiftOrder
          .sort((a, b) => byShift[b]!.length.compareTo(byShift[a]!.length));
    }

    final totalPresent = useShiftPairs
        ? _shiftPairs.where((p) => p.checkIn != null).length
        : _kpiDetailData('present').length;

    String fmtTime(DateTime? t) {
      if (t == null) return '--:--';
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }

    String fmtMin(int m) {
      if (m <= 0) return '';
      if (m < 60) return '${m}ph';
      return '${m ~/ 60}g${m % 60 > 0 ? ' ${m % 60}ph' : ''}';
    }

    showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (sheetCtx, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                // drag handle
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 12, 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF22C55E).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.check_circle_outline_rounded,
                            color: Color(0xFF16A34A), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('Có mặt hôm nay'),
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A))),
                            Text(
                                tr('$totalPresent nhân viên'
                                '${useShiftPairs && shiftOrder.isNotEmpty ? ' · ${shiftOrder.length} ca' : ''}'),
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Body
                Expanded(
                  child: !useShiftPairs || byShift.isEmpty
                      // Fallback: danh sách phẳng từ _kpiDetailData
                      ? _buildPresentFallbackList(
                          scrollController, _kpiDetailData('present'))
                      // Chính: gom theo ca
                      : ListView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          itemCount: shiftOrder.length,
                          itemBuilder: (_, si) {
                            final shiftName = shiftOrder[si];
                            final emps = byShift[shiftName]!;
                            final lateInShift =
                                emps.where((e) => e.lateMinutes > 0).length;
                            final earlyInShift =
                                emps.where((e) => e.earlyMinutes > 0).length;

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Shift header row
                                  Row(children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2D5F8B)
                                            .withValues(alpha: 0.10),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.work_outline,
                                                size: 13,
                                                color: Color(0xFF2D5F8B)),
                                            const SizedBox(width: 4),
                                            Text(tr(shiftName),
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFF2D5F8B))),
                                          ]),
                                    ),
                                    const SizedBox(width: 8),
                                    _inOutChip('${emps.length} NV', emps.length,
                                        const Color(0xFF22C55E)),
                                    if (lateInShift > 0) ...[
                                      const SizedBox(width: 6),
                                      _lateBadge('⏰ $lateInShift trễ',
                                          const Color(0xFFF59E0B)),
                                    ],
                                    if (earlyInShift > 0) ...[
                                      const SizedBox(width: 4),
                                      _lateBadge('🚪 $earlyInShift sớm',
                                          const Color(0xFFEF4444)),
                                    ],
                                  ]),
                                  const SizedBox(height: 6),
                                  // Employee cards
                                  ...emps.map((emp) {
                                    final hasIssue = emp.lateMinutes > 0 ||
                                        emp.earlyMinutes > 0;
                                    final borderColor = hasIssue
                                        ? const Color(0xFFF59E0B)
                                            .withValues(alpha: 0.40)
                                        : const Color(0xFF22C55E)
                                            .withValues(alpha: 0.25);
                                    final bgColor = hasIssue
                                        ? const Color(0xFFFFFBEB)
                                        : const Color(0xFFF0FDF4);
                                    final avatarColor = hasIssue
                                        ? const Color(0xFFF59E0B)
                                        : const Color(0xFF22C55E);

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 5),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: bgColor,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: borderColor),
                                      ),
                                      child: Row(children: [
                                        CircleAvatar(
                                          radius: 17,
                                          backgroundColor: avatarColor
                                              .withValues(alpha: 0.18),
                                          child: Text(
                                            tr(emp.employeeName.isNotEmpty
                                                ? emp.employeeName[0]
                                                    .toUpperCase()
                                                : '?'),
                                            style: TextStyle(
                                                color: avatarColor,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(tr(emp.employeeName),
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      fontSize: 13,
                                                      color: Color(0xFF0F172A)),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis),
                                              if (emp.employeeCode.isNotEmpty)
                                                Text(tr(emp.employeeCode),
                                                    style: TextStyle(
                                                        fontSize: 11,
                                                        color: Colors
                                                            .grey.shade500)),
                                            ],
                                          ),
                                        ),
                                        // Times + badges
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Row(children: [
                                              const Icon(Icons.login,
                                                  size: 12,
                                                  color: Color(0xFF22C55E)),
                                              const SizedBox(width: 2),
                                              Text(tr(fmtTime(emp.checkIn)),
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color:
                                                          Color(0xFF16A34A))),
                                              if (emp.checkOut != null) ...[
                                                const SizedBox(width: 6),
                                                const Icon(Icons.logout,
                                                    size: 12,
                                                    color: Color(0xFFEF4444)),
                                                const SizedBox(width: 2),
                                                Text(tr(fmtTime(emp.checkOut)),
                                                    style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color:
                                                            Color(0xFFDC2626))),
                                              ],
                                            ]),
                                            const SizedBox(height: 2),
                                            Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (emp.lateMinutes > 0) ...[
                                                    _lateBadge(
                                                        '⏰ ${fmtMin(emp.lateMinutes)}',
                                                        const Color(
                                                            0xFFF59E0B)),
                                                    const SizedBox(width: 4),
                                                  ],
                                                  if (emp.earlyMinutes > 0)
                                                    _lateBadge(
                                                        '🚪 ${fmtMin(emp.earlyMinutes)}',
                                                        const Color(
                                                            0xFFEF4444)),
                                                ]),
                                          ],
                                        ),
                                      ]),
                                    );
                                  }),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Danh sách phẳng fallback khi chưa có shiftPairs.
  Widget _buildPresentFallbackList(
      ScrollController sc, List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return Center(
        child: Text(tr('Chưa có dữ liệu'),
            style: TextStyle(color: Colors.grey.shade500)),
      );
    }
    return ListView.separated(
      controller: sc,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 5),
      itemBuilder: (_, i) =>
          _buildKpiDetailRow('present', items[i], const Color(0xFF22C55E)),
    );
  }

  /// Bottom-sheet chi tiết Đi trễ / Về sớm — gom theo từng nhân viên.
  /// Mỗi nhân viên có thể có nhiều ca; expand để thấy chi tiết từng ca.
  void _showLateDetail() {
    // ── Group _lateShiftEntries by employee ──────────────────────────────────
    final empOrder = <String>[]; // preserve insert order
    final empMap = <String, List<DailyShiftLateEntry>>{}; // key = employeeCode
    final empNames = <String, String>{};
    for (final e in _lateShiftEntries) {
      final key = e.employeeCode.isNotEmpty ? e.employeeCode : e.employeeId;
      if (!empMap.containsKey(key)) {
        empOrder.add(key);
        empMap[key] = [];
        empNames[key] = e.employeeName;
      }
      empMap[key]!.add(e);
    }
    // Sort employees: worst offenders first (totalLate + totalEarly desc)
    empOrder.sort((a, b) {
      final aList = empMap[a]!;
      final bList = empMap[b]!;
      final aTotal =
          aList.fold(0, (s, r) => s + r.lateMinutes + r.earlyMinutes);
      final bTotal =
          bList.fold(0, (s, r) => s + r.lateMinutes + r.earlyMinutes);
      return bTotal.compareTo(aTotal);
    });

    final groups = empOrder
        .map((k) => _LateEmpGroup(
              code: k,
              name: empNames[k] ?? k,
              entries: empMap[k]!,
            ))
        .toList();

    final totalLateCount =
        _lateShiftEntries.where((e) => e.lateMinutes > 0).length;
    final totalEarlyCount =
        _lateShiftEntries.where((e) => e.earlyMinutes > 0).length;

    // ── Helpers ─────────────────────────────────────────────────────────────
    String fmtMin(int m) {
      if (m <= 0) return '';
      if (m < 60) return '${m}ph';
      return '${m ~/ 60}g${m % 60 > 0 ? ' ${m % 60}ph' : ''}';
    }

    String fmtTime(DateTime? t) {
      if (t == null) return '--:--';
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }

    showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.82,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (sheetCtx, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                // drag handle
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header row
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 12, 10),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFF59E0B).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.schedule_rounded,
                            color: Color(0xFFD97706), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('Đi trễ / Về sớm'),
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A))),
                            Text(tr('${groups.length} nhân viên'),
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                // Summary chips
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Row(children: [
                    _inOutChip('⏰ Đi trễ: $totalLateCount ca', totalLateCount,
                        const Color(0xFFF59E0B)),
                    const SizedBox(width: 8),
                    _inOutChip('🚪 Về sớm: $totalEarlyCount ca',
                        totalEarlyCount, const Color(0xFFEF4444)),
                  ]),
                ),
                const Divider(height: 1),
                // Employee list
                Expanded(
                  child: groups.isEmpty
                      ? Center(
                          child: Text(tr('Không có dữ liệu'),
                              style: TextStyle(color: Colors.grey.shade500)))
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          itemCount: groups.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, gi) {
                            final g = groups[gi];
                            final totLate =
                                g.entries.fold(0, (s, e) => s + e.lateMinutes);
                            final totEarly =
                                g.entries.fold(0, (s, e) => s + e.earlyMinutes);
                            final multiShift = g.entries.length > 1;

                            // Single-shift: flat card; multi-shift: ExpansionTile card
                            if (!multiShift) {
                              final en = g.entries.first;
                              return _buildLateEmpCard(
                                name: g.name,
                                shiftName: en.shiftName,
                                checkIn: fmtTime(en.checkIn),
                                checkOut: fmtTime(en.checkOut),
                                lateMin: en.lateMinutes,
                                earlyMin: en.earlyMinutes,
                                fmtMin: fmtMin,
                              );
                            }

                            // Multiple shifts → ExpansionTile
                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                    color: const Color(0xFFF59E0B)
                                        .withValues(alpha: 0.35)),
                              ),
                              color: const Color(0xFFFFFBEB),
                              child: Theme(
                                data: Theme.of(sheetCtx)
                                    .copyWith(dividerColor: Colors.transparent),
                                child: ExpansionTile(
                                  tilePadding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 4),
                                  childrenPadding: const EdgeInsets.only(
                                      left: 12, right: 12, bottom: 10),
                                  leading: CircleAvatar(
                                    radius: 20,
                                    backgroundColor: const Color(0xFFF59E0B)
                                        .withValues(alpha: 0.18),
                                    child: Text(
                                      tr(g.name.isNotEmpty
                                          ? g.name[0].toUpperCase()
                                          : '?'),
                                      style: const TextStyle(
                                          color: Color(0xFFD97706),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14),
                                    ),
                                  ),
                                  title: Text(tr(g.name),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: Color(0xFF0F172A)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  subtitle: Row(children: [
                                    Text(tr('${g.entries.length} ca'),
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade500)),
                                    if (totLate > 0) ...[
                                      const SizedBox(width: 6),
                                      _lateBadge('⏰ ${fmtMin(totLate)}',
                                          const Color(0xFFF59E0B)),
                                    ],
                                    if (totEarly > 0) ...[
                                      const SizedBox(width: 4),
                                      _lateBadge('🚪 ${fmtMin(totEarly)}',
                                          const Color(0xFFEF4444)),
                                    ],
                                  ]),
                                  children: g.entries.map((en) {
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: _buildLateShiftRow(
                                        shiftName: en.shiftName,
                                        checkIn: fmtTime(en.checkIn),
                                        checkOut: fmtTime(en.checkOut),
                                        lateMin: en.lateMinutes,
                                        earlyMin: en.earlyMinutes,
                                        fmtMin: fmtMin,
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Card phẳng cho nhân viên chỉ có 1 ca trễ.
  Widget _buildLateEmpCard({
    required String name,
    required String shiftName,
    required String checkIn,
    required String checkOut,
    required int lateMin,
    required int earlyMin,
    required String Function(int) fmtMin,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.18),
            child: Text(
              tr(name.isNotEmpty ? name[0].toUpperCase() : '?'),
              style: const TextStyle(
                  color: Color(0xFFD97706),
                  fontWeight: FontWeight.bold,
                  fontSize: 14),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(name),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: Color(0xFF0F172A)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                _buildLateShiftRow(
                  shiftName: shiftName,
                  checkIn: checkIn,
                  checkOut: checkOut,
                  lateMin: lateMin,
                  earlyMin: earlyMin,
                  fmtMin: fmtMin,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 1 dòng ca: tên ca + giờ vào/ra + badge trễ/sớm.
  Widget _buildLateShiftRow({
    required String shiftName,
    required String checkIn,
    required String checkOut,
    required int lateMin,
    required int earlyMin,
    required String Function(int) fmtMin,
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(tr(shiftName),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.login, size: 11, color: Color(0xFF22C55E)),
          const SizedBox(width: 2),
          Text(tr(checkIn),
              style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF16A34A),
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          const Icon(Icons.logout, size: 11, color: Color(0xFFEF4444)),
          const SizedBox(width: 2),
          Text(tr(checkOut),
              style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFFDC2626),
                  fontWeight: FontWeight.w600)),
        ]),
        if (lateMin > 0)
          _lateBadge('⏰ Trễ ${fmtMin(lateMin)}', const Color(0xFFF59E0B)),
        if (earlyMin > 0)
          _lateBadge('🚪 Sớm ${fmtMin(earlyMin)}', const Color(0xFFEF4444)),
      ],
    );
  }

  Widget _lateBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(tr(label),
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w700)),
    );
  }

  /// Bottom-sheet chi tiết Vào / Ra — hiển thị theo từng nhân viên:
  /// cặp (vào, ra) mỗi lần chấm. Thiếu ra = đang trong ca / quên chấm.
  void _showInOutDetail() {
    // Build per-employee ordered punch list from raw (same logic as KPI count).
    final window = _attendanceDayWindow();

    // empKey → sorted punches
    final empMap = <String, List<Attendance>>{};
    final empName = <String, String>{};
    for (final a in _rawAttendances) {
      final t = a.attendanceTime;
      if (!_isInAttendanceWindow(
          t, window.windowStart, window.windowEnd)) {
        continue;
      }
      final key = _attendanceEmployeeKey(a);
      if (key.isEmpty) continue;
      (empMap[key] ??= <Attendance>[]).add(a);
      if ((a.employeeName ?? '').isNotEmpty) empName[key] = a.employeeName!;
    }
    // Sort each employee's punches ascending
    for (final list in empMap.values) {
      list.sort((a, b) => a.attendanceTime.compareTo(b.attendanceTime));
    }

    // Build display rows: each employee → list of {in, out?, missing}
    final rows = <_InOutRow>[];
    for (final entry in empMap.entries) {
      final key = entry.key;
      final punches = entry.value;
      final name = empName[key] ?? key;
      // Group into pairs: [0]=in, [1]=out, [2]=in, [3]=out ...
      for (var i = 0; i < punches.length; i += 2) {
        final pIn = punches[i];
        final pOut = i + 1 < punches.length ? punches[i + 1] : null;
        rows.add(_InOutRow(
          name: name,
          pairIndex: i ~/ 2 + 1,
          checkIn: pIn.attendanceTime,
          checkOut: pOut?.attendanceTime,
          missing: pOut == null,
        ));
      }
    }
    // Sort: missing (cần chú ý) lên trên, rồi theo checkIn mới nhất
    rows.sort((a, b) {
      if (a.missing != b.missing) return a.missing ? -1 : 1;
      return b.checkIn.compareTo(a.checkIn);
    });

    final missingCount = rows.where((r) => r.missing).length;
    final completeCount = rows.where((r) => !r.missing).length;

    String fmtTime(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.80,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 12, 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF2D5F8B).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.swap_horiz_rounded,
                            color: Color(0xFF2D5F8B), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('Chi tiết Vào / Ra'),
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A))),
                            Text(
                                tr('$_checkIns vào · $_checkOuts ra'
                                '${missingCount > 0 ? ' · $missingCount chưa ra' : ''}'),
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                      IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                ),
                // Summary chips
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Row(children: [
                    _inOutChip(
                        '✅ Đủ cặp', completeCount, const Color(0xFF22C55E)),
                    const SizedBox(width: 8),
                    _inOutChip(
                        '⚠️ Thiếu ra', missingCount, const Color(0xFFF59E0B)),
                  ]),
                ),
                const Divider(height: 1),
                Expanded(
                  child: rows.isEmpty
                      ? Center(
                          child: Text(tr('Chưa có dữ liệu chấm công'),
                              style: TextStyle(color: Colors.grey.shade500)))
                      : ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          itemCount: rows.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 6),
                          itemBuilder: (_, i) {
                            final r = rows[i];
                            final color = r.missing
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFF22C55E);
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: color.withValues(alpha: 0.25)),
                              ),
                              child: Row(children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor:
                                      color.withValues(alpha: 0.15),
                                  child: Text(
                                    tr(r.name.isNotEmpty
                                        ? r.name[0].toUpperCase()
                                        : '?'),
                                    style: TextStyle(
                                        color: color,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(tr(r.name),
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      Text(tr('Lần ${r.pairIndex}'),
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade500)),
                                    ],
                                  ),
                                ),
                                // In time
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Row(children: [
                                      const Icon(Icons.login,
                                          size: 13, color: Color(0xFF22C55E)),
                                      const SizedBox(width: 3),
                                      Text(tr(fmtTime(r.checkIn)),
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF22C55E))),
                                    ]),
                                    const SizedBox(height: 2),
                                    if (r.checkOut != null)
                                      Row(children: [
                                        const Icon(Icons.logout,
                                            size: 13, color: Color(0xFFEF4444)),
                                        const SizedBox(width: 3),
                                        Text(tr(fmtTime(r.checkOut!)),
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFFEF4444))),
                                      ])
                                    else
                                      Row(children: [
                                        Icon(Icons.warning_amber_rounded,
                                            size: 13, color: Color(0xFFF59E0B)),
                                        SizedBox(width: 3),
                                        Text(tr('Chưa ra'),
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: Color(0xFFF59E0B))),
                                      ]),
                                  ],
                                ),
                              ]),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _inOutChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Text(tr('$label: $count'),
          style: TextStyle(
              fontSize: 12, color: color, fontWeight: FontWeight.w600)),
    );
  }

  List<Map<String, dynamic>> _kpiDetailData(String kind) {
    switch (kind) {
      case 'total':
        // Prefer the daily report roster (same source as the summary total)
        // and fall back to the employee list if it's empty.
        if (_dailyReportItems.isNotEmpty) {
          return _dailyReportItems
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        return _employees
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      case 'present':
        // "Present" = anybody whose status says có mặt / present / đúng giờ /
        // on time / đi muộn / late / sớm / early. We intentionally include
        // late arrivals because the backend's `present` count also includes
        // them.
        return _dailyReportItems
            .whereType<Map>()
            .where((r) {
              final s = (r['status'] ?? '').toString().toLowerCase();
              if (s.contains('vắng') ||
                  s.contains('absent') ||
                  s.contains('nghỉ')) {
                return false;
              }
              if (r['checkInTime'] != null) return true;
              return s.contains('có mặt') ||
                  s.contains('present') ||
                  s.contains('đúng giờ') ||
                  s.contains('on time') ||
                  s.contains('muộn') ||
                  s.contains('late') ||
                  s.contains('sớm') ||
                  s.contains('early');
            })
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      case 'late':
        // Ưu tiên dùng per-shift entries (không gộp theo ngày) —
        // mỗi ca trễ / về sớm = 1 dòng. Fallback về _memoLate khi raw
        // attendances chưa load.
        if (_lateShiftEntries.isNotEmpty) {
          return _lateShiftEntries.map((e) {
            final parts = <String>[];
            if (e.lateMinutes > 0) parts.add('Trễ ${e.lateMinutes} phút');
            if (e.earlyMinutes > 0) parts.add('Sớm ${e.earlyMinutes} phút');
            return <String, dynamic>{
              'employeeName': e.employeeName,
              'employeeCode': e.employeeCode,
              'departmentName': e.shiftName,
              'shiftName': e.shiftName,
              'checkInTime': e.checkIn?.toIso8601String(),
              'checkOutTime': e.checkOut?.toIso8601String(),
              'lateMinutes': e.lateMinutes,
              'earlyLeaveMinutes': e.earlyMinutes,
              'status': parts.join(' • '),
            };
          }).toList();
        }
        return _memoLate.map((e) => Map<String, dynamic>.from(e)).toList();
      case 'absent':
        // Nhất quán với _memoAbsentCount: nhân viên có lịch nhưng không có
        // checkInTime trong ngày (từ daily report) và không phải ngày nghỉ.
        return _dailyReportItems
            .whereType<Map>()
            .where((r) {
              final s = (r['status'] ?? '').toString().toLowerCase();
              if (s.contains('không có lịch') ||
                  s.contains('ngày nghỉ') ||
                  s.contains('nghỉ lễ')) {
                return false;
              }
              return r['checkInTime'] == null;
            })
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      case 'inout':
        return _dailyReportItems
            .whereType<Map>()
            .where((r) => r['checkInTime'] != null || r['checkOutTime'] != null)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      case 'devices':
        return _devices
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
    }
    return const [];
  }

  String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s trước';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    if (diff.inDays < 30) return '${diff.inDays} ngày trước';
    return '${t.day}/${t.month}/${t.year}';
  }

  Widget _buildKpiDetailRow(
      String kind, Map<String, dynamic> item, Color accent) {
    if (kind == 'devices') {
      final name = (item['deviceName'] ?? item['DeviceName'] ?? '-').toString();
      final sn =
          (item['serialNumber'] ?? item['SerialNumber'] ?? '').toString();
      final ip = (item['ipAddress'] ?? item['IpAddress'] ?? '').toString();
      final isOnline = _isDeviceOnline(item);
      final lastOnlineRaw = item['lastOnline'] ?? item['LastOnline'];
      String lastSeen = '';
      if (lastOnlineRaw != null && !isOnline) {
        try {
          final lo = DateTime.parse(lastOnlineRaw.toString()).toLocal();
          lastSeen = _relativeTime(lo);
        } catch (_) {}
      }
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.blueGrey.shade100),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor:
                  (isOnline ? const Color(0xFF22C55E) : const Color(0xFFEF4444))
                      .withValues(alpha: .12),
              child: Icon(Icons.router_rounded,
                  color: isOnline
                      ? const Color(0xFF22C55E)
                      : const Color(0xFFEF4444),
                  size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(name),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    tr([
                      if (sn.isNotEmpty) 'SN: $sn',
                      if (ip.isNotEmpty) 'IP: $ip',
                      if (lastSeen.isNotEmpty) 'Mất KN: $lastSeen',
                    ].join('  •  ')),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (isOnline
                        ? const Color(0xFF22C55E)
                        : const Color(0xFFEF4444))
                    .withValues(alpha: .1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                tr(isOnline ? 'Online' : 'Offline'),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isOnline
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFDC2626)),
              ),
            ),
          ],
        ),
      );
    }

    // Employee / attendance row
    final name = (item['fullName'] ??
            item['FullName'] ??
            item['employeeName'] ??
            item['EmployeeName'] ??
            '-')
        .toString();
    final code =
        (item['employeeCode'] ?? item['EmployeeCode'] ?? item['code'] ?? '')
            .toString();
    final dept = (item['department'] ??
            item['Department'] ??
            item['departmentName'] ??
            '')
        .toString();
    final ci = _formatTime(item['checkInTime']);
    final co = _formatTime(item['checkOutTime']);
    final status = (item['status'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueGrey.shade100),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: accent.withValues(alpha: .12),
            child: Text(
              tr(name.isNotEmpty ? name.characters.first.toUpperCase() : '?'),
              style: TextStyle(
                  color: accent, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(name),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  tr([
                    if (code.isNotEmpty) code,
                    if (dept.isNotEmpty) dept,
                  ].join('  •  ')),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (ci.isNotEmpty || co.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        if (ci.isNotEmpty) ...[
                          const Icon(Icons.login,
                              size: 12, color: Color(0xFF22C55E)),
                          const SizedBox(width: 3),
                          Text(tr(ci),
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF16A34A),
                                  fontWeight: FontWeight.w600)),
                        ],
                        if (ci.isNotEmpty && co.isNotEmpty)
                          const SizedBox(width: 10),
                        if (co.isNotEmpty) ...[
                          const Icon(Icons.logout,
                              size: 12, color: Color(0xFFEF4444)),
                          const SizedBox(width: 3),
                          Text(tr(co),
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFFDC2626),
                                  fontWeight: FontWeight.w600)),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (status.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                tr(status),
                style: TextStyle(
                    fontSize: kind == 'late' ? 11 : 10,
                    fontWeight: FontWeight.w600,
                    color: accent),
              ),
            ),
          if (kind == 'late') ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFA1A1AA)),
          ],
        ],
      ),
    );
  }

  /// Parse "HH:MM:SS" or "HH:MM" TimeSpan string to minutes-since-midnight.
  int _parseShiftTime(String? s) {
    if (s == null || s.isEmpty) return 0;
    final parts = s.split(':');
    if (parts.length < 2) return 0;
    return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
  }

  String _formatTime(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    try {
      final dt = DateTime.parse(s).toLocal();
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    } catch (_) {
      // fallback: show HH:mm portion if already formatted
      final m = RegExp(r'(\d{1,2}:\d{2})').firstMatch(s);
      return m?.group(1) ?? s;
    }
  }

  // ===================== MAIN GRID =====================
  Widget _buildMainGrid(DashboardUiCapabilities caps) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 1100;
        final isMedium = constraints.maxWidth > 700;

        Widget gap16() => const SizedBox(height: 16);

        Widget rowRealtimeAbsent() => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (caps.gridRealtime)
                  Expanded(
                      flex: 2, child: _buildRealtimeAttendanceCard()),
                if (caps.gridRealtime && caps.gridAbsent)
                  const SizedBox(width: 16),
                if (caps.gridAbsent)
                  Expanded(flex: 1, child: _buildAbsentCard()),
              ],
            );

        Widget colRealtimeAbsent() => Column(
              children: [
                if (caps.gridRealtime) _buildRealtimeAttendanceCard(),
                if (caps.gridRealtime && caps.gridAbsent) gap16(),
                if (caps.gridAbsent) _buildAbsentCard(),
                if (caps.gridLateEarly &&
                    (caps.gridRealtime || caps.gridAbsent))
                  gap16(),
                if (caps.gridLateEarly) _buildLateEarlyCard(),
              ],
            );

        Widget rowKpiNews() => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (caps.gridKpi) Expanded(child: _buildKpiCard()),
                if (caps.gridKpi && caps.gridNews) const SizedBox(width: 16),
                if (caps.gridNews) Expanded(child: _buildInternalNewsCard()),
              ],
            );

        Widget colKpiNews() => Column(
              children: [
                if (caps.gridKpi) _buildKpiCard(),
                if (caps.gridKpi && caps.gridNews) gap16(),
                if (caps.gridNews) _buildInternalNewsCard(),
              ],
            );

        final hasTop = caps.gridRealtime || caps.gridAbsent;
        final hasBottom = caps.gridKpi || caps.gridNews;

        if (isWide) {
          return Column(
            children: [
              if (hasTop) rowRealtimeAbsent(),
              if (hasTop && caps.gridLateEarly) gap16(),
              if (caps.gridLateEarly) _buildLateEarlyCard(),
              if ((hasTop || caps.gridLateEarly) && hasBottom) gap16(),
              if (hasBottom) rowKpiNews(),
            ],
          );
        }

        return Column(
          children: [
            if (hasTop || caps.gridLateEarly)
              isMedium ? rowRealtimeAbsent() : colRealtimeAbsent(),
            if (!isMedium && caps.gridLateEarly && !hasTop)
              _buildLateEarlyCard(),
            if ((hasTop || caps.gridLateEarly) && hasBottom) gap16(),
            if (hasBottom) (isMedium ? rowKpiNews() : colKpiNews()),
          ],
        );
      },
    );
  }

  // ===================== CARD: REALTIME ATTENDANCE =====================
  Widget _buildRealtimeAttendanceCard() {
    // Hiển thị lượt chấm trong cửa sổ ngày làm việc [giờ qua đêm, giờ qua đêm+1).
    // Vào/Ra = lẻ/chẵn theo thứ tự tăng dần per nhân viên (không dùng attendanceState).
    if (_rawAttendances.isNotEmpty) {
      final punchIndex = _computePunchIndexInDay();

      // Hiển thị mới nhất trên đầu; chỉ lấy punch trong cửa sổ ngày làm việc.
      const visibleRows = 5;
      final punches = _punchesInDayWindow(descending: true);
      const rowHeight = 52.0;

      return _DashCard(
        icon: Icons.monitor_heart_outlined,
        title: _l10n.realtimeAttendance,
        color: HrmPageChrome.primaryNavy,
        badge: '${punches.length} lượt',
        child: punches.isEmpty
            ? _emptyState(_l10n.noAttendanceToday)
            : ConstrainedBox(
                constraints:
                    const BoxConstraints(maxHeight: visibleRows * rowHeight),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: punches.length,
                  itemBuilder: (_, i) {
                    final a = punches[i];
                    if (a.isTravelPunch) {
                      return _attendancePunchRow(a, isTravel: true);
                    }
                    final idx = punchIndex[a.id] ?? 0;
                    final isCheckIn = idx.isEven;
                    return _attendancePunchRow(a, isCheckIn: isCheckIn);
                  },
                ),
              ),
      );
    }

    // Fallback: per-employee rows từ daily report (raw attendances chưa load).
    final working =
        _todayEmployees.whereType<Map<String, dynamic>>().where((e) {
      final s = (e['status'] ?? '').toString().toLowerCase();
      if (s.contains('vắng') ||
          s.contains('absent') ||
          s == 'nghỉ phép' ||
          s.contains('leave')) {
        return false;
      }
      if (s.contains('không có lịch') || s.contains('ngày nghỉ')) return false;
      if (e['checkInTime'] == null) return false;
      return true;
    }).toList();
    DateTime? ts(Map<String, dynamic> e) {
      final raw = e['checkOutTime'] ?? e['checkInTime'];
      if (raw == null) return null;
      return DateTime.tryParse(raw.toString());
    }

    working.sort((a, b) {
      final ta = ts(a);
      final tb = ts(b);
      if (ta == null && tb == null) return 0;
      if (ta == null) return 1;
      if (tb == null) return -1;
      return tb.compareTo(ta);
    });

    const visibleRows = 10;
    const rowHeight = 44.0;
    return _DashCard(
      icon: Icons.monitor_heart_outlined,
      title: _l10n.realtimeAttendance,
      color: HrmPageChrome.primaryNavy,
      badge: '${working.length} working',
      child: working.isEmpty
          ? _emptyState(_l10n.noAttendanceToday)
          : ConstrainedBox(
              constraints:
                  const BoxConstraints(maxHeight: visibleRows * rowHeight),
              child: Scrollbar(
                thumbVisibility: working.length > visibleRows,
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: working.length,
                  itemBuilder: (context, i) =>
                      _employeeAttendanceRow(working[i]),
                ),
              ),
            ),
    );
  }

  Widget _shiftPairRow(DailyShiftPair p) {
    final isLate = p.lateMinutes > 0;
    final isEarly = p.earlyMinutes > 0;
    final color =
        (isLate || isEarly) ? const Color(0xFFF59E0B) : const Color(0xFF22C55E);
    final statusParts = <String>[];
    if (isLate) statusParts.add('Trễ ${p.lateMinutes}p');
    if (isEarly) statusParts.add('Sớm ${p.earlyMinutes}p');
    final statusText =
        statusParts.isEmpty ? 'Đúng giờ' : statusParts.join(' • ');
    String fmt(DateTime? d) => d == null
        ? '--:--'
        : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: () {
        NavigationNotifier.goToModule('AttendanceByShift');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Text(
              tr(p.employeeName.isNotEmpty ? p.employeeName[0].toUpperCase() : '?'),
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(p.employeeName),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                  tr('${p.shiftName} · ${fmt(p.checkIn)} → ${fmt(p.checkOut)}'),
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(tr(statusText),
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  Widget _attendancePunchRow(Attendance a, {bool? isCheckIn, bool isTravel = false}) {
    final name = (a.employeeName ?? a.deviceUserName ?? a.pin ?? 'N/A');
    final checkIn = isTravel
        ? null
        : (isCheckIn ??
            (a.attendanceState == 0 ||
                a.attendanceState == 2 ||
                a.attendanceState == 4));
    final color = isTravel
        ? const Color(0xFF0EA5E9)
        : (checkIn == true
            ? const Color(0xFF22C55E)
            : const Color(0xFFEF4444));
    final stateLabel = isTravel ? a.punchTypeText : (checkIn == true ? 'Vào' : 'Ra');
    final t = a.attendanceTime;
    final timeStr =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
    final dateStr =
        '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: () {
        NavigationNotifier.goToModule('AttendanceByShift');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Text(
              tr(name.isNotEmpty ? name[0].toUpperCase() : '?'),
              style: TextStyle(
                  color: color, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(name),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                  tr('$dateStr · ${a.deviceName ?? ''}'.trim()),
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(tr(timeStr),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: HrmPageChrome.primaryNavy)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(tr(stateLabel),
                    style: TextStyle(
                        color: color,
                        fontSize: 10,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _employeeAttendanceRow(Map<String, dynamic> e) {
    final name = (e['employeeName'] ?? e['fullName'] ?? 'N/A').toString();
    final dept = (e['departmentName'] ?? e['department'] ?? '').toString();
    final status = (e['status'] ?? '').toString().toLowerCase();
    final checkIn = e['checkInTime'];
    final checkOut = e['checkOutTime'];
    final isLate =
        status.contains('muộn') || status.contains('trễ') || status == 'late';
    final isEarlyLeave = status.contains('sớm') || status.contains('early');
    final statusColor = (isLate || isEarlyLeave)
        ? const Color(0xFFF59E0B)
        : HrmPageChrome.primaryNavy;
    final statusText = isLate && isEarlyLeave
        ? '${_l10n.late} + Về sớm'
        : isLate
            ? _l10n.late
            : isEarlyLeave
                ? 'Về sớm'
                : _l10n.present;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: statusColor.withValues(alpha: 0.15),
          child: Text(tr(name.isNotEmpty ? name[0].toUpperCase() : '?'),
              style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
        ),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(name),
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          if (dept.isNotEmpty)
            Text(tr(dept),
                style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 11)),
        ])),
        if (checkIn != null)
          Text(tr(_fmtTime(checkIn)),
              style: const TextStyle(fontSize: 12, color: HrmPageChrome.primaryNavy)),
        if (checkOut != null) ...[
          Text(tr(' → '),
              style: TextStyle(fontSize: 10, color: Color(0xFFA1A1AA))),
          Text(tr(_fmtTime(checkOut)),
              style: const TextStyle(fontSize: 12, color: HrmPageChrome.primaryNavy)),
        ],
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(tr(statusText),
              style: TextStyle(
                  color: statusColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  // ===================== CARD: ABSENT EMPLOYEES =====================
  Widget _buildAbsentCard() {
    final withPerm = _absentWithPermission;
    final withoutPerm = _absentWithoutPermission;
    final notScheduled = _notScheduledEmployees;

    return _DashCard(
      icon: Icons.person_off_outlined,
      title: _l10n.absentEmployees,
      color: const Color(0xFFEF4444),
      badge: '${withPerm.length + withoutPerm.length} người',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel('${_l10n.authorized} (${withPerm.length})',
            const Color(0xFFF59E0B)),
        if (withPerm.isEmpty)
          _emptyRow('Không có')
        else
          ...withPerm.map((l) => _absentRow(
              (l['employeeName'] ?? l['fullName'] ?? 'N/A').toString(),
              _formatLeaveType(
                  (l['departmentName'] ?? l['type'] ?? 'Nghỉ phép').toString()),
              true)),
        const SizedBox(height: 12),
        _sectionLabel('${_l10n.unauthorized} (${withoutPerm.length})',
            const Color(0xFFEF4444)),
        if (withoutPerm.isEmpty)
          _emptyRow('Không có')
        else
          ...withoutPerm.map((e) => _absentRow(
              (e['employeeName'] ?? e['fullName'] ?? 'N/A').toString(),
              (e['departmentName'] ?? e['department'] ?? '').toString(),
              false)),
        if (notScheduled.isNotEmpty) ...[
          const SizedBox(height: 12),
          _sectionLabel('${_l10n.noSchedule} (${notScheduled.length})',
              const Color(0xFFA1A1AA)),
          ...notScheduled.map((e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(children: [
                  const Icon(Icons.event_busy,
                      size: 14, color: Color(0xFFA1A1AA)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          tr((e['employeeName'] ?? e['fullName'] ?? 'N/A')
                              .toString()),
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFFA1A1AA)))),
                ]),
              )),
        ],
      ]),
    );
  }

  Widget _absentRow(String name, String detail, bool hasPermission) {
    final color =
        hasPermission ? const Color(0xFFF59E0B) : const Color(0xFFEF4444);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(hasPermission ? Icons.event_busy : Icons.warning_amber_rounded,
            size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
            child: Text(tr(name),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500))),
        Text(tr(detail),
            style: const TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
      ]),
    );
  }

  // ===================== CARD: LATE / EARLY =====================
  Widget _buildLateEarlyCard() {
    final entries = _lateShiftEntries;
    // Khi có dữ liệu raw (per-shift) thì hiển thị từng ca riêng — không
    // gộp chung lại 1 ngày. Fallback về _lateEmployees (per-day) khi raw
    // attendances chưa kịp load.
    if (entries.isNotEmpty) {
      return _DashCard(
        icon: Icons.timer_off_outlined,
        title: _l10n.lateEarly,
        color: const Color(0xFFF59E0B),
        badge: '${entries.length} ca',
        child: Column(children: [
          ...entries.take(8).map((e) {
            final parts = <String>[];
            if (e.lateMinutes > 0) parts.add('${e.lateMinutes}p trễ');
            if (e.earlyMinutes > 0) parts.add('${e.earlyMinutes}p sớm');
            final lateLabel = parts.join(' | ');
            final timeStr = e.checkIn != null
                ? '${e.checkIn!.hour.toString().padLeft(2, '0')}:${e.checkIn!.minute.toString().padLeft(2, '0')}'
                : '';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                const Icon(Icons.schedule, size: 16, color: Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(e.employeeName),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500)),
                      Text(
                        tr([
                          if (e.shiftName.isNotEmpty) e.shiftName,
                          if (timeStr.isNotEmpty) timeStr,
                        ].join(' • ')),
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFFA1A1AA)),
                      ),
                    ],
                  ),
                ),
                if (lateLabel.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(tr(lateLabel),
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFD97706),
                            fontWeight: FontWeight.w600)),
                  ),
              ]),
            );
          }),
          if (entries.length > 8)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(tr('+${entries.length - 8} ca khác'),
                  style:
                      const TextStyle(color: Color(0xFF71717A), fontSize: 12)),
            ),
        ]),
      );
    }

    return _DashCard(
      icon: Icons.timer_off_outlined,
      title: _l10n.lateEarly,
      color: const Color(0xFFF59E0B),
      badge: '${_lateEmployees.length} người',
      child: Column(children: [
        if (_lateEmployees.isEmpty)
          _emptyState(_l10n.noLateEmployees)
        else
          ..._lateEmployees.take(6).map((e) {
            final name =
                (e['employeeName'] ?? e['fullName'] ?? 'N/A').toString();
            final dept =
                (e['departmentName'] ?? e['department'] ?? '').toString();
            final lateMinutes =
                e['lateMinutes'] ?? e['lateBy'] ?? e['averageLateTime'] ?? '';
            final earlyMinutes = e['earlyLeaveMinutes'] ?? 0;
            String lateLabel = '';
            if (lateMinutes is int && lateMinutes > 0) {
              lateLabel = '${lateMinutes}p trễ';
            } else if (lateMinutes.toString().isNotEmpty &&
                lateMinutes.toString() != '0') {
              lateLabel = _formatLateBy(lateMinutes);
            }
            if (earlyMinutes is int && earlyMinutes > 0) {
              if (lateLabel.isNotEmpty) lateLabel += ' | ';
              lateLabel += '${earlyMinutes}p sớm';
            }
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                const Icon(Icons.schedule, size: 16, color: Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(tr(name),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500)),
                      if (dept.isNotEmpty)
                        Text(tr(dept),
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFFA1A1AA))),
                    ])),
                if (lateLabel.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(tr(lateLabel),
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFD97706),
                            fontWeight: FontWeight.w600)),
                  ),
              ]),
            );
          }),
      ]),
    );
  }

  // ===================== CARD: BIRTHDAY =====================
  Widget _buildBirthdayCard() {
    final today = _todayBirthdays;
    final monthly = _monthlyBirthdays;
    final totalBirthdays = today.length + monthly.length;

    return _DashCard(
      icon: Icons.cake_outlined,
      title: _l10n.birthday,
      color: const Color(0xFFEC4899),
      badge: totalBirthdays > 0
          ? '$totalBirthdays ${_l10n.birthdayThisMonth}'
          : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (today.isNotEmpty) ...[
          _sectionLabel('🎂 Hôm nay', const Color(0xFFEC4899)),
          ...today.map((e) {
            final ln = (e['lastName'] ?? '').toString().trim();
            final fn = (e['firstName'] ?? '').toString().trim();
            final full = (e['fullName'] ?? '').toString().trim();
            final name = full.isNotEmpty
                ? full
                : ([ln, fn].where((s) => s.isNotEmpty).join(' ').isEmpty
                    ? 'N/A'
                    : [ln, fn].where((s) => s.isNotEmpty).join(' '));
            final dept = (e['department'] ?? '').toString();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFCE7F3),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(tr('🎉'), style: TextStyle(fontSize: 14)),
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(tr(name),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      if (dept.isNotEmpty)
                        Text(tr(dept),
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFFA1A1AA))),
                    ])),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFFEC4899), Color(0xFFF472B6)]),
                      borderRadius: BorderRadius.circular(12)),
                  child: Text(tr(_l10n.today),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
            );
          }),
          if (monthly.isNotEmpty) const SizedBox(height: 12),
        ],
        if (monthly.isNotEmpty) ...[
          _sectionLabel('📅 Trong tháng ${DateTime.now().month}',
              HrmPageChrome.primaryNavy),
          ...monthly.take(10).map((e) {
            final ln = (e['lastName'] ?? '').toString().trim();
            final fn = (e['firstName'] ?? '').toString().trim();
            final full = (e['fullName'] ?? '').toString().trim();
            final name = full.isNotEmpty
                ? full
                : ([ln, fn].where((s) => s.isNotEmpty).join(' ').isEmpty
                    ? 'N/A'
                    : [ln, fn].where((s) => s.isNotEmpty).join(' '));
            final dept = (e['department'] ?? '').toString();
            final day = e['_birthdayDay'] ?? 0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                const Icon(Icons.cake, size: 14, color: HrmPageChrome.primaryNavy),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(tr(name), style: const TextStyle(fontSize: 13)),
                      if (dept.toString().isNotEmpty)
                        Text(tr(dept.toString()),
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFFA1A1AA))),
                    ])),
                Text(tr('Ngày $day'),
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFFA1A1AA))),
              ]),
            );
          }),
        ],
        if (today.isEmpty && monthly.isEmpty)
          _emptyState('${_l10n.birthday} - ${_l10n.birthdayThisMonth}'),
      ]),
    );
  }

  // ===================== CARD: TODAY SCHEDULE =====================
  Widget _buildTodayScheduleCard() {
    final scheduledWorkers = _scheduledCount;
    final schedulesWithShift = _todaySchedules
        .whereType<Map<String, dynamic>>()
        .where((s) => s['isDayOff'] != true)
        .toList();

    // Group by shift name with attended count (checkInTime != null on daily report)
    final shiftTotal = <String, int>{};
    final shiftAttended = <String, int>{};

    // Build quick lookup: employeeId -> hasCheckedIn
    final attendedIds = <String>{};
    for (final r in _todayEmployees.whereType<Map<String, dynamic>>()) {
      if (r['checkInTime'] != null) {
        final id =
            (r['employeeId'] ?? r['employeeUserId'] ?? r['employeeCode'] ?? '')
                .toString();
        if (id.isNotEmpty) attendedIds.add(id);
      }
    }

    for (final s in schedulesWithShift) {
      final shiftName =
          (s['shiftName'] ?? s['shift']?['name'] ?? 'Ca chung').toString();
      shiftTotal[shiftName] = (shiftTotal[shiftName] ?? 0) + 1;
      final id =
          (s['employeeId'] ?? s['employeeUserId'] ?? s['employeeCode'] ?? '')
              .toString();
      if (id.isNotEmpty && attendedIds.contains(id)) {
        shiftAttended[shiftName] = (shiftAttended[shiftName] ?? 0) + 1;
      }
    }

    // Determine current shift
    final hour = _now.hour;
    String currentShift;
    IconData shiftIcon;
    Color shiftColor;
    if (hour >= 6 && hour < 14) {
      currentShift = 'Ca sáng';
      shiftIcon = Icons.wb_sunny;
      shiftColor = const Color(0xFFF59E0B);
    } else if (hour >= 14 && hour < 22) {
      currentShift = 'Ca chiều';
      shiftIcon = Icons.wb_twilight;
      shiftColor = const Color(0xFFEF4444);
    } else {
      currentShift = 'Ca đêm';
      shiftIcon = Icons.nightlight;
      shiftColor = HrmPageChrome.primaryNavy;
    }

    return _DashCard(
      icon: Icons.calendar_today_outlined,
      title: _l10n.todaySchedule,
      color: HrmPageChrome.primaryNavy,
      badge: '$scheduledWorkers NV được xếp lịch',
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              shiftColor.withValues(alpha: 0.1),
              shiftColor.withValues(alpha: 0.05)
            ]),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: shiftColor.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: shiftColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(shiftIcon, color: shiftColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(tr('Ca hiện tại'),
                      style: TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
                  const SizedBox(height: 2),
                  Text(tr(currentShift),
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: shiftColor)),
                ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                  color: shiftColor, borderRadius: BorderRadius.circular(20)),
              child: Text(tr('$_presentCount/$scheduledWorkers'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        const SizedBox(height: 14),
        if (shiftTotal.isNotEmpty)
          ...shiftTotal.entries.map((e) {
            final total = e.value;
            final attended = shiftAttended[e.key] ?? 0;
            final rate = total > 0 ? (attended / total) : 0.0;
            final rateColor = rate >= 0.8
                ? HrmPageChrome.primaryNavy
                : rate >= 0.5
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFFEF4444);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(children: [
                Row(children: [
                  const Icon(Icons.access_time,
                      size: 14, color: HrmPageChrome.primaryNavy),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(tr(e.key),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500))),
                  Text(tr('$attended/$total'),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: rateColor)),
                ]),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: rate,
                    minHeight: 5,
                    backgroundColor: const Color(0xFFE4E4E7),
                    valueColor: AlwaysStoppedAnimation(rateColor),
                  ),
                ),
              ]),
            );
          }),
        if (shiftTotal.isEmpty && scheduledWorkers == 0)
          _emptyState(_l10n.noScheduledToday),
        const SizedBox(height: 10),
        Row(children: [
          _scheduleInfoBox('Tổng NV', '$_totalEmployees', Icons.groups,
              HrmPageChrome.primaryNavy),
          const SizedBox(width: 10),
          _scheduleInfoBox('Xếp lịch', '$scheduledWorkers',
              Icons.event_available, HrmPageChrome.primaryNavy),
          const SizedBox(width: 10),
          _scheduleInfoBox('Nghỉ/Trống', '${_notScheduledEmployees.length}',
              Icons.event_busy, const Color(0xFFA1A1AA)),
        ]),
      ]),
    );
  }

  Widget _scheduleInfoBox(
      String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Column(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(tr(value),
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15, color: color)),
          Text(tr(label),
              style: const TextStyle(fontSize: 10, color: Color(0xFFA1A1AA)),
              textAlign: TextAlign.center),
        ]),
      ),
    );
  }


  // ===================== CARD: KPI =====================
  Widget _buildKpiCard() {
    final periodName = (_kpiDashboard['currentPeriodName'] ?? '').toString();
    final avgScore =
        ((_kpiDashboard['averageKpiScore'] ?? 0) as num).toDouble();
    final totalBonusAmount =
        ((_kpiDashboard['totalBonusAmount'] ?? 0) as num).toDouble();
    final totalKpiEmployees =
        ((_kpiDashboard['totalEmployees'] ?? 0) as num).toInt();
    final totalApproved =
        ((_kpiDashboard['totalApproved'] ?? 0) as num).toInt();
    final totalCalculated =
        ((_kpiDashboard['totalSalaryCalculated'] ?? 0) as num).toInt();
    final hasKpiDashboard = periodName.isNotEmpty;

    return _DashCard(
      icon: Icons.speed_outlined,
      title: _l10n.kpiToDate,
      color: const Color(0xFF2D5F8B),
      badge: hasKpiDashboard ? periodName : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // KPI Dashboard summary
        if (hasKpiDashboard) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                const Color(0xFF2D5F8B).withValues(alpha: 0.08),
                const Color(0xFF2D5F8B).withValues(alpha: 0.03),
              ]),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFF2D5F8B).withValues(alpha: 0.15)),
            ),
            child: Column(children: [
              Row(children: [
                Expanded(
                    child: _kpiSummaryItem(
                        'Điểm TB',
                        avgScore.toStringAsFixed(1),
                        avgScore >= 80
                            ? HrmPageChrome.primaryNavy
                            : avgScore >= 50
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFFEF4444))),
                Container(width: 1, height: 36, color: const Color(0xFFE4E4E7)),
                Expanded(
                    child: _kpiSummaryItem('NV đánh giá', '$totalKpiEmployees',
                        HrmPageChrome.primaryNavy)),
                Container(width: 1, height: 36, color: const Color(0xFFE4E4E7)),
                Expanded(
                    child: _kpiSummaryItem(
                        'Đã duyệt',
                        '$totalApproved/$totalCalculated',
                        HrmPageChrome.primaryNavy)),
              ]),
              if (totalBonusAmount > 0) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.monetization_on,
                      size: 14, color: HrmPageChrome.primaryNavy),
                  const SizedBox(width: 6),
                  Text(tr('Tổng thưởng KPI: ${_formatCurrency(totalBonusAmount)}'),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: HrmPageChrome.primaryNavy)),
                ]),
              ],
            ]),
          ),
          const SizedBox(height: 12),
        ],
        // Individual KPI results
        if (_kpiResults.isEmpty && !hasKpiDashboard)
          _emptyState('Chưa có dữ liệu KPI')
        else if (_kpiResults.isNotEmpty) ...[
          _sectionLabel(_l10n.topKpiEmployees, const Color(0xFF2D5F8B)),
          ..._kpiResults.take(5).map((k) {
            final name =
                (k['employeeName'] ?? k['kpiConfigName'] ?? k['name'] ?? 'N/A')
                    .toString();
            final score = ((k['weightedScore'] ??
                    k['actualValue'] ??
                    k['totalScore'] ??
                    0) as num)
                .toDouble();
            final target =
                ((k['targetValue'] ?? k['target'] ?? 100) as num).toDouble();
            final pct = (k['completionRate'] != null)
                ? ((k['completionRate'] as num).toDouble()).clamp(0.0, 100.0)
                : (target > 0 ? (score / target * 100).clamp(0.0, 100.0) : 0.0);
            Color kpiColor;
            String kpiLabel;
            if (pct >= 90) {
              kpiColor = HrmPageChrome.primaryNavy;
              kpiLabel = 'Xuất sắc';
            } else if (pct >= 70) {
              kpiColor = HrmPageChrome.primaryNavy;
              kpiLabel = 'Tốt';
            } else if (pct >= 50) {
              kpiColor = const Color(0xFFF59E0B);
              kpiLabel = 'Trung bình';
            } else {
              kpiColor = const Color(0xFFEF4444);
              kpiLabel = 'Cần cải thiện';
            }

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(
                    width: 36,
                    height: 36,
                    child: Stack(alignment: Alignment.center, children: [
                      CircularProgressIndicator(
                          value: pct / 100,
                          strokeWidth: 3,
                          backgroundColor: const Color(0xFFE4E4E7),
                          valueColor: AlwaysStoppedAnimation(kpiColor)),
                      Text(tr('${pct.toInt()}'),
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: kpiColor)),
                    ])),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(tr(name),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500)),
                      Text(tr(kpiLabel),
                          style: TextStyle(fontSize: 11, color: kpiColor)),
                    ])),
                Text(tr('${score.toStringAsFixed(0)}/${target.toStringAsFixed(0)}'),
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF71717A))),
              ]),
            );
          }),
        ],
      ]),
    );
  }

  Widget _kpiSummaryItem(String label, String value, Color color) {
    return Column(children: [
      Text(tr(value),
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      const SizedBox(height: 2),
      Text(tr(label),
          style: const TextStyle(fontSize: 10, color: Color(0xFFA1A1AA)),
          textAlign: TextAlign.center),
    ]);
  }

  String _formatCurrency(double amount) {
    if (amount >= 1e9) return '${(amount / 1e9).toStringAsFixed(1)} tỷ';
    if (amount >= 1e6) return '${(amount / 1e6).toStringAsFixed(1)} tr';
    if (amount >= 1e3) return '${(amount / 1e3).toStringAsFixed(0)}k';
    return amount.toStringAsFixed(0);
  }

  // ===================== CARD: INTERNAL NEWS =====================
  Widget _buildInternalNewsCard() {
    return _DashCard(
      icon: Icons.newspaper_outlined,
      title: _l10n.internalNews,
      color: HrmPageChrome.primaryNavy,
      child: _communications.isEmpty
          ? _emptyState('Chưa có bản tin nội bộ')
          : Column(
              children: _communications.take(5).map((c) {
              final title = (c['title'] ?? 'Không tiêu đề').toString();
              final type = (c['type'] ?? '').toString();
              final created = c['createdAt'] ?? c['publishedAt'];
              String typeLabel = 'Thông báo';
              IconData typeIcon = Icons.info_outline;
              Color typeColor = HrmPageChrome.primaryNavy;
              switch (type) {
                case 'News':
                  typeLabel = 'Tin tức';
                  typeIcon = Icons.article;
                  typeColor = HrmPageChrome.primaryNavy;
                case 'Event':
                  typeLabel = 'Sự kiện';
                  typeIcon = Icons.event;
                  typeColor = HrmPageChrome.primaryNavy;
                case 'Policy':
                  typeLabel = 'Chính sách';
                  typeIcon = Icons.policy;
                  typeColor = const Color(0xFFF59E0B);
                case 'Training':
                  typeLabel = 'Đào tạo';
                  typeIcon = Icons.school;
                  typeColor = const Color(0xFF2D5F8B);
                case 'Culture':
                  typeLabel = 'Văn hóa';
                  typeIcon = Icons.diversity_3;
                  typeColor = const Color(0xFFEC4899);
                case 'Recruitment':
                  typeLabel = 'Tuyển dụng';
                  typeIcon = Icons.person_add;
                  typeColor = HrmPageChrome.primaryNavy;
                case 'Regulation':
                  typeLabel = 'Quy định';
                  typeIcon = Icons.gavel;
                  typeColor = const Color(0xFFEF4444);
              }

              return InkWell(
                onTap: () => NavigationNotifier.goToCommunication(),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8)),
                        child: Icon(typeIcon, size: 16, color: typeColor)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(tr(title),
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Row(children: [
                            Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                    color: typeColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8)),
                                child: Text(tr(typeLabel),
                                    style: TextStyle(
                                        fontSize: 10, color: typeColor))),
                            if (created != null) ...[
                              const SizedBox(width: 6),
                              Text(tr(_fmtDate(created)),
                                  style: const TextStyle(
                                      fontSize: 10, color: Color(0xFFA1A1AA))),
                            ],
                          ]),
                        ])),
                    const Icon(Icons.chevron_right,
                        size: 16, color: Color(0xFFA1A1AA)),
                  ]),
                ),
              );
            }).toList()),
    );
  }

  // ===================== CARD: SALARY TODAY =====================
  Widget _buildSalaryTodayCard() {
    const workStart = 8;
    const workEnd = 17;
    final totalWorkHours = (workEnd - workStart).toDouble();
    final nowMinutes = _now.hour * 60 + _now.minute;
    final hoursWorked =
        ((nowMinutes - workStart * 60).clamp(0, (workEnd - workStart) * 60) /
            60.0);
    final progress = (hoursWorked / totalWorkHours).clamp(0.0, 1.0);

    return _DashCard(
      icon: Icons.payments_outlined,
      title: 'Lương ngày hôm nay',
      color: HrmPageChrome.primaryNavy,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              HrmPageChrome.primaryNavy.withValues(alpha: 0.08),
              HrmPageChrome.primaryNavy.withValues(alpha: 0.03)
            ]),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: HrmPageChrome.primaryNavy.withValues(alpha: 0.15)),
          ),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(tr('Tiến độ ngày làm việc'),
                  style: TextStyle(fontSize: 12, color: Color(0xFF71717A))),
              Text(tr('${(progress * 100).toStringAsFixed(0)}%'),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: HrmPageChrome.primaryNavy)),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: const Color(0xFFE4E4E7),
                    valueColor:
                        const AlwaysStoppedAnimation(HrmPageChrome.primaryNavy))),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _salaryInfo(
                  'Giờ vào', '${workStart.toString().padLeft(2, '0')}:00'),
              _salaryInfo('Giờ ra', '${workEnd.toString().padLeft(2, '0')}:00'),
              _salaryInfo('Đã làm', '${hoursWorked.toStringAsFixed(1)}h'),
              _salaryInfo('Còn lại',
                  '${(totalWorkHours - hoursWorked).clamp(0, totalWorkHours).toStringAsFixed(1)}h'),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: _salaryStatBox(
                  _l10n.present,
                  '$_presentCount/$_totalEmployees',
                  Icons.people,
                  HrmPageChrome.primaryNavy)),
          const SizedBox(width: 8),
          Expanded(
              child: _salaryStatBox(
                  _l10n.attendanceRate,
                  '${_attendanceRate.toStringAsFixed(1)}%',
                  Icons.pie_chart,
                  HrmPageChrome.primaryNavy)),
        ]),
      ]),
    );
  }

  Widget _salaryInfo(String label, String value) {
    return Column(children: [
      Text(tr(value),
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF18181B))),
      Text(tr(label),
          style: const TextStyle(fontSize: 10, color: Color(0xFFA1A1AA))),
    ]);
  }

  Widget _salaryStatBox(
      String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.12))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 8),
          Text(tr(value),
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14, color: color)),
          const SizedBox(height: 2),
          Text(tr(label),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Color(0xFFA1A1AA))),
        ],
      ),
    );
  }

  // ===================== CARD: DEVICE STATUS =====================
  Widget _buildDeviceStatusCard() {
    final online = _devices.whereType<Map>().where(_isDeviceOnline).toList();
    final offline =
        _devices.whereType<Map>().where((d) => !_isDeviceOnline(d)).toList();

    return _DashCard(
      icon: Icons.devices_other_outlined,
      title: 'Trạng thái thiết bị',
      color: HrmPageChrome.primaryNavy,
      badge: '$_onlineDevices/$_totalDevices online',
      child: Column(children: [
        Row(children: [
          _miniChip('Online', '${online.length}', HrmPageChrome.primaryNavy),
          const SizedBox(width: 8),
          _miniChip('Offline', '${offline.length}', const Color(0xFFEF4444)),
        ]),
        const SizedBox(height: 12),
        if (_devices.isEmpty)
          _emptyState('Chưa có thiết bị')
        else
          ..._devices.whereType<Map>().take(5).map((d) {
            final name = (d['deviceName'] ?? d['name'] ?? 'N/A').toString();
            final isOn = _isDeviceOnline(d);
            final ip = (d['ipAddress'] ?? '').toString();
            final loc = (d['location'] ?? '').toString();
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                        color: isOn
                            ? HrmPageChrome.primaryNavy
                            : const Color(0xFFEF4444),
                        shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(tr(name),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500)),
                      if (ip.isNotEmpty || loc.isNotEmpty)
                        Text(
                            tr([if (ip.isNotEmpty) ip, if (loc.isNotEmpty) loc]
                                .join(' • ')),
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFFA1A1AA))),
                    ])),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: (isOn
                              ? HrmPageChrome.primaryNavy
                              : const Color(0xFFEF4444))
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12)),
                  child: Text(tr(isOn ? 'Online' : 'Offline'),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isOn
                              ? HrmPageChrome.primaryNavy
                              : const Color(0xFFEF4444))),
                ),
              ]),
            );
          }),
      ]),
    );
  }

  // ===================== CARD: PENDING APPROVALS =====================
  Widget _buildPendingApprovalsCard() {
    final leaveCount = _pendingLeaves.length;
    final correctionCount = _pendingCorrections.length;
    final swapCount = _pendingSwaps.length;
    final advanceCount = _pendingAdvances.length;
    final mobileCount = _pendingMobileAttendanceCount;
    final totalPending = leaveCount +
        correctionCount +
        swapCount +
        advanceCount +
        mobileCount;

    return _DashCard(
      icon: Icons.pending_actions_outlined,
      title: 'Phê duyệt chờ xử lý',
      color: const Color(0xFFF59E0B),
      badge: totalPending > 0 ? '$totalPending đơn' : null,
      child: Column(children: [
        _approvalRow(Icons.event_busy, 'Đơn nghỉ phép', leaveCount,
            const Color(0xFFF59E0B),
            onTap: leaveCount > 0
                ? () => NavigationNotifier.goToLeaves(pendingOnly: true)
                : null),
        const SizedBox(height: 8),
        _approvalRow(Icons.edit_note, 'Chỉnh sửa chấm công', correctionCount,
            const Color(0xFF2D5F8B),
            onTap: correctionCount > 0
                ? NavigationNotifier.goToAttendanceCorrections
                : null),
        const SizedBox(height: 8),
        _approvalRow(Icons.swap_horiz, 'Đổi ca làm việc', swapCount,
            const Color(0xFFEC4899),
            onTap: swapCount > 0
                ? () => NavigationNotifier.goToScheduleApproval(tab: 3)
                : null),
        const SizedBox(height: 8),
        _approvalRow(Icons.account_balance_wallet_outlined, 'Yêu cầu ứng lương',
            advanceCount, const Color(0xFF10B981),
            onTap: advanceCount > 0
                ? () => NavigationNotifier.goToAdvanceRequestsNav(
                    pendingOnly: true)
                : null),
        if (mobileCount > 0) ...[
          const SizedBox(height: 8),
          _approvalRow(Icons.phone_android, 'Chấm công Mobile', mobileCount,
              HrmPageChrome.primaryNavy,
              onTap: () => NavigationNotifier.goToAttendanceApproval(
                  statusFilter: 0, tab: 1)),
        ],
        if (totalPending == 0) ...[
          const SizedBox(height: 12),
          _emptyState('Không có đơn chờ duyệt'),
        ],
        if (totalPending > 0) ...[
          const SizedBox(height: 16),
          InkWell(
            onTap: () {
              _showInsightDetail(_InsightChipData(
                  Icons.pending_actions_outlined,
                  'Chờ duyệt',
                  '$totalPending',
                  const Color(0xFFEF4444),
                  'pending_all'));
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 18, color: Color(0xFFD97706)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(tr('$totalPending đơn cần được xử lý'),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFD97706)))),
              const Icon(Icons.chevron_right,
                  size: 18, color: Color(0xFFD97706)),
            ]),
          ),
          ),
        ],
      ]),
    );
  }

  Widget _approvalRow(IconData icon, String label, int count, Color color,
      {VoidCallback? onTap}) {
    final row = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Text(tr(label),
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
              color: count > 0 ? color : const Color(0xFFE4E4E7),
              borderRadius: BorderRadius.circular(20)),
          child: Text(tr('$count'),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: count > 0 ? Colors.white : const Color(0xFFA1A1AA))),
        ),
      ]),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: row,
    );
  }

  // ===================== CARD: TASK OVERVIEW =====================
  Widget _buildTaskOverviewCard() {
    final total = _toInt(_taskStats['totalTasks'] ?? _taskStats['total'] ?? 0);
    final todo = _toInt(_taskStats['todoCount'] ??
        _taskStats['pending'] ??
        _taskStats['notStarted'] ??
        0);
    final inProgress =
        _toInt(_taskStats['inProgressCount'] ?? _taskStats['inProgress'] ?? 0);
    final done = _toInt(_taskStats['completedCount'] ??
        _taskStats['completed'] ??
        _taskStats['done'] ??
        0);
    final overdue =
        _toInt(_taskStats['overdueCount'] ?? _taskStats['overdue'] ?? 0);

    return _DashCard(
      icon: Icons.task_alt_outlined,
      title: 'Tổng quan công việc',
      color: const Color(0xFF2D5F8B),
      badge: total > 0 ? '$total việc' : null,
      child: total == 0
          ? _emptyState('Chưa có dữ liệu công việc')
          : Column(children: [
              Row(children: [
                _taskStatBox(
                  'Chờ làm',
                  '$todo',
                  Icons.hourglass_empty,
                  const Color(0xFFA1A1AA),
                  onTap: () => _openTaskManagement(
                      status: WorkTaskStatus.todo),
                ),
                const SizedBox(width: 8),
                _taskStatBox(
                  'Đang làm',
                  '$inProgress',
                  Icons.play_circle_outline,
                  const Color(0xFF2D5F8B),
                  onTap: () => _openTaskManagement(
                      status: WorkTaskStatus.inProgress),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                _taskStatBox(
                  'Hoàn thành',
                  '$done',
                  Icons.check_circle_outline,
                  HrmPageChrome.primaryNavy,
                  onTap: () => _openTaskManagement(
                      status: WorkTaskStatus.completed),
                ),
                const SizedBox(width: 8),
                _taskStatBox(
                  'Quá hạn',
                  '$overdue',
                  Icons.error_outline,
                  const Color(0xFFEF4444),
                  onTap: () =>
                      _openTaskManagement(overdueOnly: true),
                ),
              ]),
              if (total > 0) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 10,
                    child: Row(children: [
                      if (done > 0)
                        Expanded(
                            flex: done,
                            child: Container(color: HrmPageChrome.primaryNavy)),
                      if (inProgress > 0)
                        Expanded(
                            flex: inProgress,
                            child: Container(color: const Color(0xFF2D5F8B))),
                      if (todo > 0)
                        Expanded(
                            flex: todo,
                            child: Container(color: const Color(0xFFE4E4E7))),
                      if (overdue > 0)
                        Expanded(
                            flex: overdue,
                            child: Container(color: const Color(0xFFEF4444))),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                Text(tr('Tỷ lệ hoàn thành: ${total > 0 ? (done / total * 100).toStringAsFixed(0) : 0}%'),
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF71717A))),
              ],
            ]),
    );
  }

  void _openTaskManagement({
    WorkTaskStatus? status,
    bool overdueOnly = false,
  }) {
    NavigationNotifier.goToTaskManagementNav(
      statusIndex: overdueOnly ? null : status?.index,
      overdueOnly: overdueOnly,
    );
  }

  Widget _taskStatBox(
    String label,
    String value,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    final box = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(value),
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          Text(tr(label),
              style: const TextStyle(fontSize: 10, color: Color(0xFFA1A1AA))),
        ]),
      ]),
    );
    return Expanded(
      child: onTap == null
          ? box
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: box,
            ),
    );
  }

  // ===================== CARD: OVERTIME STATS =====================
  Widget _buildOvertimeStatsCard() {
    final totalHours = ((_overtimeStats['totalHours'] ??
            _overtimeStats['totalOvertimeHours'] ??
            0) as num)
        .toDouble();
    final totalEmployees = _toInt(_overtimeStats['totalEmployees'] ??
        _overtimeStats['employeeCount'] ??
        0);
    final pending = _toInt(
        _overtimeStats['pendingCount'] ?? _overtimeStats['pending'] ?? 0);
    final approved = _toInt(
        _overtimeStats['approvedCount'] ?? _overtimeStats['approved'] ?? 0);
    final totalAmount = ((_overtimeStats['totalAmount'] ??
            _overtimeStats['totalCost'] ??
            0) as num)
        .toDouble();

    return _DashCard(
      icon: Icons.more_time_outlined,
      title: 'Thống kê tăng ca',
      color: HrmPageChrome.primaryNavy,
      badge: totalHours > 0 ? '${totalHours.toStringAsFixed(1)}h' : null,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              HrmPageChrome.primaryNavy.withValues(alpha: 0.08),
              HrmPageChrome.primaryNavy.withValues(alpha: 0.03)
            ]),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: HrmPageChrome.primaryNavy.withValues(alpha: 0.15)),
          ),
          child: Row(children: [
            Expanded(
                child: _kpiSummaryItem('Tổng giờ TC',
                    totalHours.toStringAsFixed(1), HrmPageChrome.primaryNavy)),
            Container(width: 1, height: 36, color: const Color(0xFFE4E4E7)),
            Expanded(
                child: _kpiSummaryItem(
                    'Số NV', '$totalEmployees', const Color(0xFF2D5F8B))),
            Container(width: 1, height: 36, color: const Color(0xFFE4E4E7)),
            Expanded(
                child: _kpiSummaryItem(
                    'Chờ duyệt',
                    '$pending',
                    pending > 0
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFFA1A1AA))),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: HrmPageChrome.primaryNavy.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: HrmPageChrome.primaryNavy.withValues(alpha: 0.12)),
            ),
            child: Column(children: [
              const Icon(Icons.check_circle,
                  size: 20, color: HrmPageChrome.primaryNavy),
              const SizedBox(height: 4),
              Text(tr('$approved'),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: HrmPageChrome.primaryNavy)),
              Text(tr('Đã duyệt'),
                  style: TextStyle(fontSize: 10, color: Color(0xFFA1A1AA))),
            ]),
          )),
          const SizedBox(width: 8),
          Expanded(
              child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: HrmPageChrome.primaryNavy.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: HrmPageChrome.primaryNavy.withValues(alpha: 0.12)),
            ),
            child: Column(children: [
              const Icon(Icons.monetization_on,
                  size: 20, color: HrmPageChrome.primaryNavy),
              const SizedBox(height: 4),
              Text(tr(_formatCurrency(totalAmount)),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: HrmPageChrome.primaryNavy)),
              Text(tr('Chi phí TC'),
                  style: TextStyle(fontSize: 10, color: Color(0xFFA1A1AA))),
            ]),
          )),
        ]),
      ]),
    );
  }

  // ===================== CARD: PENALTY STATS =====================
  Widget _buildPenaltyStatsCard() {
    final totalTickets = _toInt(_penaltyStats['totalTickets'] ??
        _penaltyStats['total'] ??
        _penaltyStats['count'] ??
        0);
    final totalAmount = ((_penaltyStats['totalAmount'] ??
            _penaltyStats['totalFine'] ??
            0) as num)
        .toDouble();
    final lateCount =
        _toInt(_penaltyStats['lateCount'] ?? _penaltyStats['totalLate'] ?? 0);
    final absentCount = _toInt(
        _penaltyStats['absentCount'] ?? _penaltyStats['totalAbsent'] ?? 0);
    final otherCount =
        _toInt(_penaltyStats['otherCount'] ?? _penaltyStats['totalOther'] ?? 0);

    return _DashCard(
      icon: Icons.gavel_outlined,
      title: 'Thống kê vi phạm',
      color: const Color(0xFFEF4444),
      badge: totalTickets > 0 ? '$totalTickets phiếu' : null,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: const Color(0xFFEF4444).withValues(alpha: 0.15)),
          ),
          child: Row(children: [
            const Icon(Icons.receipt_long, size: 22, color: Color(0xFFEF4444)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(tr('$totalTickets phiếu phạt'),
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFEF4444))),
                  Text(tr('Tổng: ${_formatCurrency(totalAmount)}'),
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF71717A))),
                ])),
          ]),
        ),
        const SizedBox(height: 12),
        _penaltyTypeRow('Đi trễ', lateCount, const Color(0xFFF59E0B)),
        const SizedBox(height: 6),
        _penaltyTypeRow('Vắng mặt', absentCount, const Color(0xFFEF4444)),
        const SizedBox(height: 6),
        _penaltyTypeRow('Khác', otherCount, const Color(0xFFA1A1AA)),
        if (totalTickets == 0) ...[
          const SizedBox(height: 8),
          _emptyState('Không có vi phạm tháng này'),
        ],
      ]),
    );
  }

  Widget _penaltyTypeRow(String label, int count, Color color) {
    return Row(children: [
      Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 8),
      Expanded(child: Text(tr(label), style: const TextStyle(fontSize: 13))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12)),
        child: Text(tr('$count'),
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ),
    ]);
  }

  // ===================== CARD: FINANCIAL SUMMARY =====================
  Widget _buildFinancialSummaryCard() {
    final totalIncome =
        ((_cashSummary['totalIncome'] ?? _cashSummary['income'] ?? 0) as num)
            .toDouble();
    final totalExpense =
        ((_cashSummary['totalExpense'] ?? _cashSummary['expense'] ?? 0) as num)
            .toDouble();
    final balance = ((_cashSummary['balance'] ??
            _cashSummary['net'] ??
            (totalIncome - totalExpense)) as num)
        .toDouble();
    final transactionCount =
        _toInt(_cashSummary['transactionCount'] ?? _cashSummary['count'] ?? 0);

    return _DashCard(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Thu chi tháng ${_now.month}',
      color: HrmPageChrome.primaryNavy,
      badge: transactionCount > 0 ? '$transactionCount giao dịch' : null,
      child: Column(children: [
        Row(children: [
          Expanded(
              child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: HrmPageChrome.primaryNavy.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: HrmPageChrome.primaryNavy.withValues(alpha: 0.12)),
            ),
            child: Column(children: [
              const Icon(Icons.arrow_downward,
                  size: 20, color: HrmPageChrome.primaryNavy),
              const SizedBox(height: 4),
              Text(tr(_formatCurrency(totalIncome)),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: HrmPageChrome.primaryNavy)),
              Text(tr('Thu'),
                  style: TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
            ]),
          )),
          const SizedBox(width: 8),
          Expanded(
              child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.12)),
            ),
            child: Column(children: [
              const Icon(Icons.arrow_upward,
                  size: 20, color: Color(0xFFEF4444)),
              const SizedBox(height: 4),
              Text(tr(_formatCurrency(totalExpense)),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFEF4444))),
              Text(tr('Chi'),
                  style: TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
            ]),
          )),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              (balance >= 0 ? HrmPageChrome.primaryNavy : const Color(0xFFEF4444))
                  .withValues(alpha: 0.08),
              (balance >= 0 ? HrmPageChrome.primaryNavy : const Color(0xFFEF4444))
                  .withValues(alpha: 0.03)
            ]),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: (balance >= 0
                        ? HrmPageChrome.primaryNavy
                        : const Color(0xFFEF4444))
                    .withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            Icon(balance >= 0 ? Icons.trending_up : Icons.trending_down,
                size: 22,
                color: balance >= 0
                    ? HrmPageChrome.primaryNavy
                    : const Color(0xFFEF4444)),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(tr('Số dư'),
                      style: TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
                  Text(tr(_formatCurrency(balance.abs())),
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: balance >= 0
                              ? HrmPageChrome.primaryNavy
                              : const Color(0xFFEF4444))),
                ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: (balance >= 0
                          ? HrmPageChrome.primaryNavy
                          : const Color(0xFFEF4444))
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(tr(balance >= 0 ? 'Dương' : 'Âm'),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: balance >= 0
                          ? HrmPageChrome.primaryNavy
                          : const Color(0xFFEF4444))),
            ),
          ]),
        ),
      ]),
    );
  }

  // ===================== CARD: MONTHLY ATTENDANCE =====================
  Widget _buildMonthlyAttendanceCard() {
    final items = _monthlyReport['items'] as List<dynamic>? ?? [];
    final summary =
        _monthlyReport['summary'] as Map<String, dynamic>? ?? _monthlyReport;
    final totalWorkDays =
        _toInt(summary['totalWorkDays'] ?? summary['workingDays'] ?? 0);
    final avgAttendanceRate = ((summary['averageAttendanceRate'] ??
            summary['attendanceRate'] ??
            0) as num)
        .toDouble();
    final totalLate =
        _toInt(summary['totalLateCount'] ?? summary['lateCount'] ?? 0);
    final totalAbsent =
        _toInt(summary['totalAbsentCount'] ?? summary['absentCount'] ?? 0);

    return _DashCard(
      icon: Icons.calendar_month_outlined,
      title: 'Chấm công tháng ${_now.month}',
      color: const Color(0xFF2D5F8B),
      badge: avgAttendanceRate > 0
          ? '${avgAttendanceRate.toStringAsFixed(1)}%'
          : null,
      child: Column(children: [
        Row(children: [
          _monthStatBox('Ngày công', '$totalWorkDays', Icons.work_outline,
              HrmPageChrome.primaryNavy),
          const SizedBox(width: 8),
          _monthStatBox(
              'Tỷ lệ CC',
              '${avgAttendanceRate.toStringAsFixed(0)}%',
              Icons.pie_chart_outline,
              avgAttendanceRate >= 80
                  ? HrmPageChrome.primaryNavy
                  : const Color(0xFFF59E0B)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _monthStatBox(
              'Đi trễ', '$totalLate', Icons.schedule, const Color(0xFFF59E0B)),
          const SizedBox(width: 8),
          _monthStatBox('Vắng', '$totalAbsent', Icons.person_off,
              const Color(0xFFEF4444)),
        ]),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 14),
          _sectionLabel('NV nhiều ngày vắng nhất', const Color(0xFF2D5F8B)),
          ...items
              .whereType<Map<String, dynamic>>()
              .where(
                  (e) => _toInt(e['absentDays'] ?? e['totalAbsent'] ?? 0) > 0)
              .take(4)
              .map((e) {
            final name =
                (e['employeeName'] ?? e['fullName'] ?? 'N/A').toString();
            final absentDays = _toInt(e['absentDays'] ?? e['totalAbsent'] ?? 0);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                const Icon(Icons.person, size: 14, color: Color(0xFFEF4444)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(tr(name), style: const TextStyle(fontSize: 13))),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: Text(tr('$absentDays ngày'),
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFEF4444))),
                ),
              ]),
            );
          }),
        ],
        if (items.isEmpty && totalWorkDays == 0)
          _emptyState('Chưa có dữ liệu tháng này'),
      ]),
    );
  }

  Widget _monthStatBox(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.12)),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(value),
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14, color: color)),
            Text(tr(label),
                style: const TextStyle(fontSize: 10, color: Color(0xFFA1A1AA))),
          ]),
        ]),
      ),
    );
  }

  // ===================== CARD: EXPIRING CONTRACTS =====================
  Widget _buildExpiringDocsCard() {
    final total = _expiringDocs.length + _expiredContracts.length;

    Widget contractTile(dynamic d, {bool isExpired = false}) {
      final firstName = (d['firstName'] ?? '').toString();
      final lastName = (d['lastName'] ?? '').toString();
      final fullName = '$lastName $firstName'.trim();
      final department = (d['department'] ?? '').toString();
      final daysLeft = (d['daysUntilExpiry'] as num?)?.toInt() ?? 0;
      final isUrgent = !isExpired && daysLeft <= 7;
      final statusColor = isExpired
          ? const Color(0xFFEF4444)
          : (isUrgent ? const Color(0xFFEF4444) : const Color(0xFFF59E0B));
      final statusText = isExpired
          ? '${(-daysLeft)} ngày trước'
          : (daysLeft == 0 ? 'Hôm nay' : '$daysLeft ngày');

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(isExpired ? Icons.warning_rounded : Icons.schedule,
                size: 16, color: statusColor),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(tr(fullName.isEmpty ? 'N/A' : fullName),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (department.isNotEmpty)
                  Text(tr(department),
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFFA1A1AA))),
              ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12)),
            child: Text(tr(statusText),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: statusColor)),
          ),
        ]),
      );
    }

    return _DashCard(
      icon: Icons.assignment_late_outlined,
      title: 'Hợp đồng hết hạn',
      color: const Color(0xFFD97706),
      badge: total > 0 ? '$total NV' : null,
      child: total == 0
          ? _emptyState('Không có hợp đồng cần xử lý')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_expiringDocs.isNotEmpty) ...[
                  Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text(tr('Cần gia hạn'),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF59E0B))),
                  ),
                  ..._expiringDocs.take(3).map((d) => contractTile(d)),
                ],
                if (_expiredContracts.isNotEmpty) ...[
                  if (_expiringDocs.isNotEmpty) const SizedBox(height: 6),
                  Padding(
                    padding: EdgeInsets.only(bottom: 4),
                    child: Text(tr('Đã hết hạn'),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFEF4444))),
                  ),
                  ..._expiredContracts
                      .take(3)
                      .map((d) => contractTile(d, isExpired: true)),
                ],
              ],
            ),
    );
  }

  // ===================== HELPER WIDGETS =====================
  Widget _miniChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.15))),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(tr(value),
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15, color: color)),
            const SizedBox(height: 2),
            Text(tr(label),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, color: color.withValues(alpha: 0.8))),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 2),
      child: Text(tr(text),
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _emptyState(String message) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        Icon(Icons.inbox_outlined, size: 32, color: Colors.grey[300]),
        const SizedBox(height: 8),
        Text(tr(message),
            style: TextStyle(fontSize: 13, color: Colors.grey[400]),
            textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _emptyRow(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(tr(text),
          style: const TextStyle(fontSize: 12, color: Color(0xFFA1A1AA))),
    );
  }

  // ===================== FORMATTERS =====================
  int _toInt(dynamic v) => (v is int) ? v : int.tryParse(v.toString()) ?? 0;

  String _weekday(int wd) {
    const days = [
      '',
      'Thứ 2',
      'Thứ 3',
      'Thứ 4',
      'Thứ 5',
      'Thứ 6',
      'Thứ 7',
      'Chủ nhật'
    ];
    return days[wd];
  }

  /// Giờ chấm công VN — cùng quy ước màn Chấm công thô.
  String _fmtAttendanceTime(dynamic t, {String empty = '--:--'}) =>
      formatAttendanceWallClock(t, pattern: 'HH:mm', empty: empty);

  /// Shift start/end — local VN wall clock, not UTC.
  String _fmtShiftTime(dynamic t) {
    if (t == null) return '--:--';
    final raw = t.toString();
    if (RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(raw)) {
      final parts = raw.split(':');
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _fmtTime(dynamic t) {
    if (t == null) return '';
    final raw = t.toString();
    if (RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(raw)) {
      return _fmtShiftTime(t);
    }
    return _fmtAttendanceTime(t, empty: '');
  }

  String _fmtDate(dynamic d) {
    if (d == null) return '';
    try {
      final dt = DateTime.parse(d.toString());
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return d.toString();
    }
  }

  String _formatLateBy(dynamic value) {
    if (value == null) return '';
    final s = value.toString();
    if (s.contains(':')) {
      final parts = s.split(':');
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
      if (h > 0) return '${h}g${m}p trễ';
      if (m > 0) return '${m}p trễ';
      return 'Đúng giờ';
    }
    if (s.contains('min')) return s;
    return '${s}p trễ';
  }

  String _formatLeaveType(String type) {
    switch (type) {
      case 'AnnualLeave':
        return 'Phép năm';
      case 'Holiday':
        return 'Lễ tết';
      case 'PersonalPaid':
        return 'Việc riêng có lương';
      case 'PersonalUnpaid':
        return 'Việc riêng không lương';
      case 'SickLeave':
        return 'Ốm đau';
      case 'MaternityLeave':
        return 'Thai sản';
      case 'CompensatoryLeave':
        return 'Nghỉ bù';
      case 'LongTermLeave':
        return 'Nghỉ dài hạn';
      default:
        return type;
    }
  }


  // ===================== CARD: LEAVE ANALYTICS =====================
  Widget _buildLeaveAnalyticsCard() {
    // Build leave type breakdown from all known leave lists
    final allLeaves = <Map<String, dynamic>>[
      ..._pendingLeaves.whereType<Map<String, dynamic>>(),
      ..._todayLeaves.whereType<Map<String, dynamic>>(),
    ];

    final typeMap = <String, int>{};
    for (final l in allLeaves) {
      final t =
          _formatLeaveType((l['leaveType'] ?? l['type'] ?? 'Khác').toString());
      typeMap[t] = (typeMap[t] ?? 0) + 1;
    }

    final leaveTotal = allLeaves.length;
    final approved = allLeaves.where((l) {
      final s =
          (l['status'] ?? l['approvalStatus'] ?? '').toString().toLowerCase();
      return s.contains('approved') || s.contains('duyệt');
    }).length;
    final pending = _pendingLeaves.length;
    // Sum totalLeaveDays across all employees from the monthly report items.
    var monthlyLeaveDays = 0;
    final mItems = (_monthlyReport['items'] as List<dynamic>?) ?? const [];
    for (final it in mItems) {
      if (it is Map) monthlyLeaveDays += _toInt(it['totalLeaveDays'] ?? 0);
    }
    final annualUsed = monthlyLeaveDays > 0
        ? monthlyLeaveDays
        : _toInt(_monthlyReport['annualLeaveUsed'] ??
            _monthlyReport['leaveUsed'] ??
            0);
    final leaveTypes = (typeMap.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(5)
        .toList();

    return _DashCard(
      icon: Icons.event_note_outlined,
      title: 'Phân tích nghỉ phép',
      color: const Color(0xFFF59E0B),
      badge: '$leaveTotal đơn',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _leaveStatBox('Đã duyệt', '$approved', const Color(0xFF22C55E)),
          const SizedBox(width: 8),
          _leaveStatBox('Chờ duyệt', '$pending', const Color(0xFFF59E0B)),
          const SizedBox(width: 8),
          _leaveStatBox(
              'Ngày phép đã dùng', '$annualUsed', HrmPageChrome.primaryNavy),
        ]),
        if (leaveTypes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(tr('Phân loại nghỉ phép'),
              style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF71717A),
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ...leaveTypes.map((e) {
            final pct = leaveTotal > 0 ? e.value / leaveTotal : 0.0;
            const barColor = Color(0xFFF59E0B);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(
                    child: Text(tr(e.key),
                        style: const TextStyle(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 6,
                        backgroundColor: const Color(0xFFE4E4E7),
                        valueColor: const AlwaysStoppedAnimation(barColor)),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                    width: 22,
                    child: Text(tr('${e.value}'),
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFF59E0B)),
                        textAlign: TextAlign.right)),
              ]),
            );
          }),
        ],
        if (leaveTotal == 0) _emptyState('Không có dữ liệu nghỉ phép'),
      ]),
    );
  }

  Widget _leaveStatBox(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(tr(value),
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(tr(label),
              style: const TextStyle(fontSize: 9, color: Color(0xFF71717A)),
              textAlign: TextAlign.center,
              maxLines: 2),
        ]),
      ),
    );
  }


  Widget _buildEmployeeGreetingHeader(String empName, {String? deptName}) {
    final greet = _greetingForTime();
    final initials = _employeeInitials(empName);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: _homeGreetingBannerDecoration,
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.18),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              tr(initials),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white.withValues(alpha: 0.95),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(greet.icon, color: greet.accent, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      tr(greet.greeting),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  tr(empName.isNotEmpty ? empName : _l10n.loadingOverview),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white.withValues(alpha: 0.95),
                    letterSpacing: -0.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (deptName != null && deptName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    tr(deptName),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.78),
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    tr('${_weekday(_now.weekday)}, ${_now.day}/${_now.month}/${_now.year}'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w600,
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

  String _employeeInitials(String name) {
    final list =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (list.isEmpty) return '?';
    if (list.length == 1) return list.first[0].toUpperCase();
    return '${list.first[0]}${list.last[0]}'.toUpperCase();
  }

  // ===================== EMPLOYEE DASHBOARD =====================
  Widget _buildEmployeeDashboard(DashboardUiCapabilities caps,
      {bool isMobile = false}) {
    final todayShift =
        _employeeDashboard['todayShift'] as Map<String, dynamic>?;
    final nextShift = _employeeDashboard['nextShift'] as Map<String, dynamic>?;
    final attendance =
        _employeeDashboard['currentAttendance'] as Map<String, dynamic>?;
    final stats =
        _employeeDashboard['attendanceStats'] as Map<String, dynamic>?;
    final empMap =
        _employees.isNotEmpty && _employees[0] is Map ? _employees[0] as Map : null;
    final empName = empMap?['fullName']?.toString() ?? '';
    final deptName = empMap?['departmentName']?.toString() ??
        empMap?['department']?.toString();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final isWide = !isMobile && MediaQuery.of(context).size.width >= 768;
    final displayName =
        empName.isNotEmpty ? empName : (auth.user?.fullName ?? 'User');

    return _wrapDashboardScroll(RefreshIndicator(
      color: isMobile ? PosTheme.kiotBlue : null,
      onRefresh: _loadEmployeeData,
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          isMobile ? 12 : (isWide ? 20 : 12),
          isMobile ? 8 : (isWide ? 20 : 12),
          isMobile ? 12 : (isWide ? 20 : 12),
          100,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isMobile)
              _dashboardSection(PosMobileProfileCard(
                name: displayName,
                subtitle: deptName?.trim().isNotEmpty == true
                    ? deptName!.trim()
                    : _dashboardProfileSubtitle(),
              ))
            else
              _dashboardSection(
                  _buildEmployeeGreetingHeader(empName, deptName: deptName)),
            SizedBox(height: isMobile ? 12 : 14),
            if (caps.showQuickActions) ...[
              _dashboardSection(
                  _buildQuickActions(caps, mobileGrid: isMobile)),
              SizedBox(height: isMobile ? 12 : 14),
            ],
            _dashboardSection(_buildEmployeeAttendanceCard(attendance, todayShift)),
            _buildEmployeePunchCta(),
            const SizedBox(height: 16),
            _dashboardSection(const EmployeeModuleGrid()),
            const SizedBox(height: 16),
            if (stats != null) ...[
              _dashboardSection(_buildEmployeeStatsCard(stats)),
              const SizedBox(height: 16),
            ],
            _dashboardSection(_buildEmployeeShiftSummaryCard()),
            const SizedBox(height: 16),
            _dashboardSection(_buildEmployeeRawAttendanceCard()),
            const SizedBox(height: 16),
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _dashboardSection(_buildInternalNewsCard())),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _dashboardSection(
                        _buildEmployeeShiftCard(todayShift, nextShift)),
                  ),
                ],
              )
            else ...[
              _dashboardSection(_buildInternalNewsCard()),
              const SizedBox(height: 16),
              _dashboardSection(_buildEmployeeShiftCard(todayShift, nextShift)),
            ],
            const SizedBox(height: 16),
            _dashboardSection(_buildEmployeeLeavesCard()),
          ],
        ),
      ),
    ));
  }

  Widget _buildEmployeePunchCta() {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    if (!perm.canView('MobileAttendance')) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: NavigationNotifier.goToMobileAttendance,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0284C7), Color(0xFF0369A1)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.28),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.fingerprint_rounded, color: Colors.white, size: 26),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Chấm công ngay'),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(tr('Mở chấm công mobile'),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: Colors.white70),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _employeeStatsPeriodLabel() {
    switch (_employeeStatsPeriod) {
      case 'week':
        return '7 ngày qua';
      case 'year':
        return '12 tháng qua';
      default:
        return '30 ngày qua';
    }
  }

  Widget _buildEmployeeShiftSummaryCard() {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final records = _employeeShiftRecords;
    const previewCount = 14;

    return _DashCard(
      icon: Icons.view_week_rounded,
      title: 'Tổng hợp chấm công theo ca',
      color: const Color(0xFF7C3AED),
      badge: _employeeStatsPeriodLabel(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (records.isEmpty)
            _emptyState('Chưa có dữ liệu tổng hợp theo ca')
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F4F5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(tr('Ngày'),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF71717A))),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(tr('Ca'),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF71717A))),
                  ),
                  Expanded(
                    child: Text(tr('Vào'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF71717A))),
                  ),
                  Expanded(
                    child: Text(tr('Ra'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF71717A))),
                  ),
                  Expanded(
                    child: Text(tr('Giờ'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF71717A))),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            ...records.take(previewCount).map(_employeeShiftSummaryRow),
            if (records.length > previewCount)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(tr('và ${records.length - previewCount} ngày/ca khác'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF71717A),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
          if (perm.canView('AttendanceByShift') && records.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () =>
                    NavigationNotifier.goToModule('AttendanceByShift'),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text(tr('Mở báo cáo theo ca')),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF7C3AED),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _employeeShiftSummaryRow(DailyShiftRecord record) {
    final dateStr =
        '${record.date.day.toString().padLeft(2, '0')}/${record.date.month.toString().padLeft(2, '0')}';
    final weekday = _weekday(record.date.weekday).replaceFirst('Thứ ', 'T');
    final shiftLabel = record.shiftNames.isNotEmpty
        ? record.shiftNames.join(', ')
        : '—';
    final checkIn = record.punchTimes.isNotEmpty ? record.punchTimes.first : null;
    final checkOut =
        record.punchTimes.length > 1 ? record.punchTimes.last : null;
    final inText = checkIn == null
        ? '--:--'
        : formatAttendanceWallClock(checkIn, pattern: 'HH:mm');
    final outText = checkOut == null
        ? '--:--'
        : formatAttendanceWallClock(checkOut, pattern: 'HH:mm');
    final hoursText = '${record.workHours.toStringAsFixed(1)}h';

    final hasIssue = record.lateMinutes > 0 ||
        record.earlyMinutes > 0 ||
        record.status.toLowerCase().contains('thiếu');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasIssue
              ? record.statusColor.withValues(alpha: 0.25)
              : const Color(0xFFE4E4E7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(dateStr),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF18181B),
                      ),
                    ),
                    Text(
                      tr(weekday),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF71717A),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  tr(shiftLabel),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3F3F46),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                child: Text(
                  tr(inText),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF22C55E),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  tr(outText),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2D5F8B),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  tr(hoursText),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF18181B),
                  ),
                ),
              ),
            ],
          ),
          if (hasIssue) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: record.statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    tr(record.status),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: record.statusColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (record.lateMinutes > 0) ...[
                  const SizedBox(width: 6),
                  Text(tr('Trễ ${record.lateMinutes}p'),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                ],
                if (record.earlyMinutes > 0) ...[
                  const SizedBox(width: 6),
                  Text(tr('Sớm ${record.earlyMinutes}p'),
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmployeeRawAttendanceCard() {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final punches = _employeeRawPunches;
    const previewCount = 10;
    final hasMore = punches.length > previewCount;
    final visible = _employeeRawPunchesExpanded || !hasMore
        ? punches
        : punches.take(previewCount).toList();

    return _DashCard(
      icon: Icons.list_alt_rounded,
      title: 'Chấm công thô chi tiết',
      color: const Color(0xFF0284C7),
      badge: punches.isEmpty
          ? _employeeStatsPeriodLabel()
          : '${punches.length} bản ghi',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (punches.isEmpty)
            _emptyState('Chưa có log chấm công trong kỳ này')
          else ...[
            ...visible.map(_employeePunchRow),
            if (hasMore) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.center,
                child: TextButton.icon(
                  onPressed: () => setState(
                    () => _employeeRawPunchesExpanded =
                        !_employeeRawPunchesExpanded,
                  ),
                  icon: Icon(
                    _employeeRawPunchesExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 18,
                  ),
                  label: Text(
                    tr(_employeeRawPunchesExpanded
                        ? 'Thu gọn'
                        : 'Xem thêm (${punches.length - previewCount} bản ghi)'),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF0284C7),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
          if (perm.canView('Attendance') && punches.isNotEmpty) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: NavigationNotifier.goToAttendance,
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: Text(tr('Mở chấm công thô')),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF0284C7),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _employeePunchRow(Attendance punch) {
    final isTravel = punch.isTravelPunch;
    final isCheckIn = !isTravel && punch.attendanceState == 0;
    final isCheckOut = !isTravel && punch.attendanceState == 1;
    final badgeColor = isTravel
        ? const Color(0xFF0EA5E9)
        : isCheckIn
            ? const Color(0xFF22C55E)
            : isCheckOut
                ? HrmPageChrome.primaryNavy
                : const Color(0xFFF59E0B);
    final timeText = formatAttendanceWallClock(
      punch.attendanceTime,
      pattern: 'dd/MM/yyyy HH:mm:ss',
      empty: '--',
    );
    final device = punch.deviceName?.trim();
    final verify = punch.isFromMobile ? 'Mobile' : punch.verifyTypeText;
    final location = punch.locationName?.trim();
    final subtitleParts = <String>[
      if (device != null && device.isNotEmpty) device,
      verify,
      if (location != null && location.isNotEmpty) location,
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: badgeColor.withValues(alpha: 0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              tr(punch.punchTypeText),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: badgeColor,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(timeText),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF18181B),
                  ),
                ),
                if (subtitleParts.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    tr(subtitleParts.join(' · ')),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF71717A),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (punch.isFromMobile)
            const Icon(Icons.phone_android_rounded,
                size: 16, color: Color(0xFF0284C7)),
        ],
      ),
    );
  }

  Widget _buildEmployeeAttendanceCard(
      Map<String, dynamic>? attendance, Map<String, dynamic>? todayShift) {
    final status = attendance?['status']?.toString() ?? 'no-shift';
    final checkIn = attendance?['checkInTime'];
    final checkOut = attendance?['checkOutTime'];
    final lastPunch = attendance?['lastPunchTime'];
    final lastPunchIsOut = attendance?['lastPunchIsCheckOut'] == true;
    final isLate = attendance?['isLate'] == true;
    final lateMin = attendance?['lateMinutes'];

    String statusText;
    Color statusColor;
    IconData statusIcon;

    switch (status) {
      case 'checked-in':
        statusText = 'Đã chấm công vào';
        statusColor = const Color(0xFF22C55E);
        statusIcon = Icons.login_rounded;
        break;
      case 'checked-out':
        statusText = 'Đã chấm công ra';
        statusColor = HrmPageChrome.primaryNavy;
        statusIcon = Icons.logout_rounded;
        break;
      case 'not-started':
        statusText = 'Chưa chấm công';
        statusColor = const Color(0xFFF59E0B);
        statusIcon = Icons.access_time_filled;
        break;
      default:
        statusText = 'Không có ca hôm nay';
        statusColor = const Color(0xFF71717A);
        statusIcon = Icons.event_busy;
    }

    return _DashCard(
      icon: Icons.fingerprint_rounded,
      title: 'Chấm công hôm nay',
      color: HrmPageChrome.primaryNavy,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(statusText),
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: statusColor)),
                      if (isLate && lateMin != null)
                        Text(tr('Trễ $lateMin phút'),
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFFEF4444))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildTimeBox(
                    'Giờ vào',
                    _fmtAttendanceTime(checkIn),
                    const Color(0xFF22C55E)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildTimeBox(
                    'Giờ ra',
                    _fmtAttendanceTime(checkOut),
                    HrmPageChrome.primaryNavy),
              ),
            ],
          ),
          if (lastPunch != null) ...[
            const SizedBox(height: 8),
            _buildTimeBox(
              'Chấm gần nhất (${lastPunchIsOut ? 'Ra' : 'Vào'})',
              _fmtAttendanceTime(lastPunch),
              const Color(0xFF2D5F8B),
            ),
          ],
          if (todayShift != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildTimeBox(
                      'Ca bắt đầu',
                      _fmtShiftTime(todayShift['startTime']),
                      const Color(0xFF71717A)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTimeBox(
                      'Ca kết thúc',
                      _fmtShiftTime(todayShift['endTime']),
                      const Color(0xFF71717A)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeBox(String label, String time, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Text(tr(label),
              style:
                  TextStyle(fontSize: 11, color: color.withValues(alpha: 0.7))),
          const SizedBox(height: 4),
          Text(tr(time),
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildEmployeeStatsCard(Map<String, dynamic> stats) {
    final totalDays = stats['totalWorkDays'] ?? 0;
    final present = stats['presentDays'] ?? 0;
    final absent = stats['absentDays'] ?? 0;
    final lateCnt = stats['lateCheckIns'] ?? 0;
    final rate = (stats['attendanceRate'] ?? 0).toDouble();
    final avgHours = stats['averageWorkHours'] ?? '0.0';
    final period = (stats['period'] ?? _employeeStatsPeriod).toString();

    String periodLabel;
    switch (period) {
      case 'week':
        periodLabel = '7 ngày qua';
        break;
      case 'year':
        periodLabel = '12 tháng qua';
        break;
      default:
        periodLabel = '30 ngày qua';
    }

    return _DashCard(
      icon: Icons.bar_chart_rounded,
      title: 'Thống kê chấm công',
      color: const Color(0xFF2D5F8B),
      badge: periodLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _employeePeriodChip('Tuần', 'week'),
              const SizedBox(width: 8),
              _employeePeriodChip('Tháng', 'month'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                  child: _employeeStatTile('Có mặt', '$present',
                      '$totalDays ca', const Color(0xFF22C55E))),
              const SizedBox(width: 10),
              Expanded(
                  child: _employeeStatTile(
                      'Vắng', '$absent', 'ca', const Color(0xFFEF4444))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _employeeStatTile(
                      'Đi trễ', '$lateCnt', 'lần', const Color(0xFFF59E0B))),
              const SizedBox(width: 10),
              Expanded(
                  child: _employeeStatTile('TB giờ/ngày', avgHours, '',
                      const Color(0xFF2D5F8B))),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF2D5F8B).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(tr('Tỷ lệ có mặt: ${rate.toStringAsFixed(1)}%'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2D5F8B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _employeePeriodChip(String label, String period) {
    final selected = _employeeStatsPeriod == period;
    return ChoiceChip(
      label: Text(tr(label)),
      selected: selected,
      onSelected: (v) {
        if (!v || selected) return;
        setState(() => _employeeStatsPeriod = period);
        _loadEmployeeData();
      },
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: selected ? Colors.white : const Color(0xFF52525B),
      ),
      selectedColor: const Color(0xFF2D5F8B),
      backgroundColor: const Color(0xFFF4F4F5),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _employeeStatTile(
      String label, String value, String suffix, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(label),
              style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(tr(value),
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: color)),
              if (suffix.isNotEmpty) ...[
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(tr(suffix),
                      style: TextStyle(fontSize: 11, color: color)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(tr(value),
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          Text(tr(label),
              style: const TextStyle(fontSize: 11, color: Color(0xFF71717A))),
        ],
      ),
    );
  }

  Widget _buildEmployeeShiftCard(
      Map<String, dynamic>? todayShift, Map<String, dynamic>? nextShift) {
    return _DashCard(
      icon: Icons.schedule_rounded,
      title: 'Ca làm việc',
      color: HrmPageChrome.primaryNavy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (todayShift != null) ...[
            _shiftRow('Hôm nay', todayShift, const Color(0xFF22C55E)),
          ] else
            _emptyRow('Không có ca hôm nay'),
          if (nextShift != null) ...[
            const Divider(height: 16),
            _shiftRow('Ca tiếp theo', nextShift, const Color(0xFF2D5F8B)),
          ],
        ],
      ),
    );
  }

  Widget _shiftRow(String label, Map<String, dynamic> shift, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(Icons.work_outline, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(label),
                  style: TextStyle(
                      fontSize: 12, color: color, fontWeight: FontWeight.w600)),
              Text(
                tr('${_fmtShiftTime(shift['startTime'])} - ${_fmtShiftTime(shift['endTime'])}'),
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF18181B)),
              ),
              if (shift['description'] != null)
                Text(tr(shift['description'].toString()),
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF71717A))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmployeeLeavesCard() {
    return _DashCard(
      icon: Icons.event_note_rounded,
      title: 'Đơn nghỉ phép gần đây',
      color: const Color(0xFF7C3AED),
      badge: '${_todayLeaves.length}',
      child: _todayLeaves.isEmpty
          ? _emptyState('Chưa có đơn nghỉ phép')
          : Column(
              children: _todayLeaves.take(5).map((leave) {
                final l = leave as Map<String, dynamic>;
                final type = _formatLeaveType(l['leaveType']?.toString() ?? '');
                final status = l['status']?.toString() ?? '';
                final from = _fmtDate(l['fromDate']);
                final to = _fmtDate(l['toDate']);
                Color stColor;
                switch (status.toLowerCase()) {
                  case 'approved':
                    stColor = const Color(0xFF22C55E);
                    break;
                  case 'rejected':
                    stColor = const Color(0xFFEF4444);
                    break;
                  default:
                    stColor = const Color(0xFFF59E0B);
                }
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: stColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: stColor.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 36,
                        decoration: BoxDecoration(
                            color: stColor,
                            borderRadius: BorderRadius.circular(2)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr(type),
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                            Text(tr('$from - $to'),
                                style: const TextStyle(
                                    fontSize: 11, color: Color(0xFF71717A))),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: stColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12)),
                        child: Text(tr(status),
                            style: TextStyle(
                                fontSize: 11,
                                color: stColor,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

// ===================== REUSABLE CARD WIDGET =====================
class _DashCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final String? badge;
  final Widget child;

  const _DashCard(
      {required this.icon,
      required this.title,
      required this.color,
      required this.child,
      this.badge});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: color)),
          const SizedBox(width: 10),
          Expanded(
              child: Text(tr(title),
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF18181B)))),
          if (badge != null)
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(tr(badge!),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: color))),
        ]),
        const SizedBox(height: 16),
        child,
      ]),
    );
  }
}

class _HeroKpi {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String kind; // total|present|late|absent|inout|devices
  _HeroKpi(this.label, this.value, this.icon, this.color, this.kind);
}

class _InOutRow {
  final String name;
  final int pairIndex;
  final DateTime checkIn;
  final DateTime? checkOut;
  final bool missing;
  _InOutRow({
    required this.name,
    required this.pairIndex,
    required this.checkIn,
    this.checkOut,
    required this.missing,
  });
}

class _LateEmpGroup {
  final String code;
  final String name;
  final List<DailyShiftLateEntry> entries;
  _LateEmpGroup(
      {required this.code, required this.name, required this.entries});
  int get totalLateMinutes => entries.fold(0, (s, e) => s + e.lateMinutes);
  int get totalEarlyMinutes => entries.fold(0, (s, e) => s + e.earlyMinutes);
}

class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  _QuickAction(this.icon, this.label, this.color, this.onTap);
}

class _InsightChipData {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String kind;
  const _InsightChipData(
      this.icon, this.label, this.value, this.color, this.kind);
}

class _InsightCta {
  final String label;
  final IconData icon;
  final Widget? screen;
  final VoidCallback? onNavigate;
  const _InsightCta(this.label, this.icon, this.screen, {this.onNavigate});
}

