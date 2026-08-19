import 'dart:math' as math;
import '../../utils/file_saver.dart' as file_saver;
import '../../utils/web_canvas.dart' as web_canvas;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../utils/mobile_attendance_vertical_layout.dart';
import 'package:excel/excel.dart' as excel_lib;
import '../../models/attendance.dart';
import '../../models/device.dart';
import '../../widgets/notification_overlay.dart';
import '../../utils/attendance_load_utils.dart';
import '../../utils/attendance_date_range_presets.dart';
import '../../utils/attendance_leave_lookup.dart';
import '../../utils/absence_day_actions.dart';
import '../../utils/attendance_record_resolver.dart';
import '../../utils/attendance_viewport_preserve.dart';
import '../../utils/shift_records_calculator.dart';
import '../../utils/paid_leave_schedule_utils.dart';
import '../../utils/travel_hours_load_utils.dart';
import '../../utils/travel_salary_utils.dart';
import '../../services/api_service.dart';
import '../../widgets/attendance_frozen_employee_name_cell.dart';
import '../../widgets/hrm_collapsible_overview.dart';
import '../../widgets/hrm_mini_stat_chip.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/attendance_correction_reason_field.dart';
import '../../widgets/attendance_delete_confirm_dialog.dart';
import '../../widgets/synced_scroll_list_view.dart'
    show SyncedScrollListView, linkHorizontalScrollControllers;
import '../../widgets/pinned_box_header_delegate.dart';
import '../../utils/excel_report_builder.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Model cho yêu cầu chỉnh sửa chấm công
class AttendanceCorrectionRequest {
  final String id;
  final String employeeName;
  final String employeeCode;
  final String? pin; // PIN/mã chấm công gốc
  final String? attendanceId; // ID bản ghi attendance gốc
  final String? employeeUserId;
  /// Employee.Id (HR) — dùng cho chấm công thủ công trực tiếp vào DB.
  final String? employeeGuid;
  final String? deviceId;
  final DateTime requestDate;
  final DateTime correctionDate;
  final String reason;
  final String correctionType; // 'add', 'edit', 'delete'
  final String requestedTime;
  final int punchIndex; // Lần chấm công (1-10)
  final DateTime? originalTime; // Thời gian cũ (nếu sửa/xóa)
  final String? newType;
  final String? approverId;
  final String? approverName;

  AttendanceCorrectionRequest({
    required this.id,
    required this.employeeName,
    required this.employeeCode,
    this.pin,
    this.attendanceId,
    this.employeeUserId,
    this.employeeGuid,
    this.deviceId,
    required this.requestDate,
    required this.correctionDate,
    required this.reason,
    required this.correctionType,
    required this.requestedTime,
    required this.punchIndex,
    this.originalTime,
    this.newType,
    this.approverId,
    this.approverName,
  });
}

class AttendanceSummaryTab extends StatefulWidget {
  final List<Attendance> attendances;
  final List<Device> devices;
  final DateTime fromDate;
  final DateTime toDate;
  final Future<void> Function(AttendanceCorrectionRequest)?
      onCorrectionRequest;
  final int dayEndHour;
  final int dayEndMinute;
  final double minHoursForWorkDay;
  final bool decimalWorkDayEnabled;
  final double standardWorkHours;
  final List<dynamic> holidays;
  final List<dynamic> salaryProfiles;
  final Map<String, dynamic>? storeSalarySettings;
  final List<Map<String, dynamic>> shiftTemplates;
  final List<Map<String, dynamic>> shiftSalaryLevels;
  final List<dynamic> approvedLeaves;

  /// Nếu false, ẩn toàn bộ nút chỉnh công (nhân viên thường khi tắt chấm công bù).
  final bool allowCorrection;

  /// Admin/Giám đốc/ có quyền duyệt → backend tự động duyệt khi lưu.
  final bool directApplyCorrections;

  /// Danh sách chi nhánh để nhóm hiển thị theo branch (optional)
  final List<Map<String, dynamic>>? branches;

  /// Danh sách nhân viên để lookup branchName từ employeeCode (optional)
  final List<Map<String, dynamic>>? employeesList;

  /// Mobile: header/filter từ màn cha — cuộn chung với nội dung tab.
  final List<Widget>? mobileLeadingSections;

  /// Đổi preset → cha tải lại log đúng khoảng ngày (tránh chỉ có 30 ngày gần nhất).
  final void Function(String preset)? onDateRangeChanged;

  /// Preset đang tải ở màn cha — giữ đồng bộ khi tab bị recreate sau loading.
  final String? dateRangePreset;

  /// Sau khi tạo phép / phiếu phạt từ ô Vắng → tải lại dữ liệu.
  final VoidCallback? onDataChanged;

  /// Giờ đi đường (mobile) theo nhân viên / theo ngày — từ màn cha.
  final Map<String, double> travelHoursByEmployeeKey;
  final Map<String, double> travelHoursByEmployeeDateKey;
  /// NV được bật chấm đi đường trên thiết bị mobile.
  final Set<String> travelEligibleEmployeeKeys;

  /// Lịch làm việc (WorkSchedule) — paidLeaveType=schedule.
  final List<Map<String, dynamic>> workSchedules;

  const AttendanceSummaryTab({
    super.key,
    required this.attendances,
    required this.devices,
    required this.fromDate,
    required this.toDate,
    this.onCorrectionRequest,
    this.dayEndHour = 0,
    this.dayEndMinute = 0,
    this.minHoursForWorkDay = 0,
    this.decimalWorkDayEnabled = false,
    this.standardWorkHours = 8,
    this.holidays = const [],
    this.salaryProfiles = const [],
    this.storeSalarySettings,
    this.shiftTemplates = const [],
    this.shiftSalaryLevels = const [],
    this.approvedLeaves = const [],
    this.allowCorrection = true,
    this.directApplyCorrections = false,
    this.branches,
    this.employeesList,
    this.mobileLeadingSections,
    this.onDateRangeChanged,
    this.dateRangePreset,
    this.onDataChanged,
    this.travelHoursByEmployeeKey = const {},
    this.travelHoursByEmployeeDateKey = const {},
    this.travelEligibleEmployeeKeys = const {},
    this.workSchedules = const [],
  });

  @override
  State<AttendanceSummaryTab> createState() => _AttendanceSummaryTabState();
}

class _AttendanceSummaryTabState extends State<AttendanceSummaryTab> {
  late String _selectedPreset;
  Set<String> _selectedEmployeeIds =
      {}; // Set of selected employee IDs for multi-select
  int _rowsPerPage = 50;
  int _currentPage = 0;
  bool _isExporting = false;
  bool _showOverviewPanel = true;
  final GlobalKey _tableKey = GlobalKey();
  String _shiftFilter = 'all'; // 'all' | 'missing' | 'complete'

  bool get _showTravelColumns => isTravelFeatureVisible(
        storeSalarySettings: widget.storeSalarySettings,
        salaryProfiles: widget.salaryProfiles,
      );

  // Sorting
  String _sortColumn = 'name';
  bool _sortAscending = true;

  // Cache dòng tổng hợp thô (tính nền); sort/lọc áp dụng sync khi hiển thị.
  List<_DailySummary>? _cachedSummaryRows;
  int? _cachedSummaryRowsFp;
  bool _isSummarizing = false;
  int _summaryBuildToken = 0;
  static final DateFormat _summaryDateKeyFmt = DateFormat('yyyy-MM-dd');
  String? _openDetailLookupKey;
  void Function(void Function())? _openDetailDialogSetState;
  BuildContext? _openDetailHostContext;
  int _openDetailMaxPunches = 2;
  int _openDetailMaxShifts = 1;
  Map<String, DailyShiftRecord>? _shiftRecordByKey;
  int? _shiftRecordsFp;

  List<_DailySummary>? _cachedDisplaySummaries;
  int? _cachedDisplayFp;
  ({int maxPunches, int maxShifts})? _cachedTableCols;
  int? _cachedTableColsFp;
  ({double totalHours, int uniqueEmployees, int totalShifts})?
      _cachedOverviewStats;
  int? _cachedOverviewStatsFp;

  // Lookup maps for holiday/restday coefficients (built from salaryProfiles)
  Map<String, String> _employeeCodeToWeeklyOffDays = {};
  Map<String, String> _employeeCodeToPaidLeaveType = {};
  Map<String, double> _employeeCodeToHolidayMultiplier = {};
  Map<String, int> _employeeCodeToHolidayOvertimeType = {};
  Map<String, int> _employeeCodeToShiftsPerDay = {};
  // Map employeeCode -> employeeGuid (Employee.Id) so we can match against
  // holiday.employeeIds which stores GUIDs.
  Map<String, String> _employeeCodeToGuid = {};
  // Map employeeCode -> rateType (0=hourly,1=monthly,2=daily,3=shift)
  Map<String, int> _employeeCodeToRateType = {};
  Set<String> _scheduleDayOffKeys = {};
  Set<String> _scheduleWorkDayKeys = {};
  Set<String> _employeesWithSchedule = {};

  // Map employeeCode -> branchName (built from widget.employeesList)
  Map<String, String> _codeTobranchName = {};
  // PIN hoặc mã HR → applicationUserId / mã HR chuẩn
  Map<String, String> _codeOrPinToApplicationUserId = {};
  Map<String, String> _codeOrPinToHrEmployeeCode = {};

  final ScrollController _desktopTableHScrollHeader = ScrollController();
  final ScrollController _desktopTableHScrollBody = ScrollController();
  final ScrollController _listScrollController = ScrollController();
  final AttendanceViewportPreserve _viewportPreserve =
      AttendanceViewportPreserve();
  bool _desktopScrollLinked = false;

  @override
  void initState() {
    super.initState();
    _selectedPreset = widget.dateRangePreset ?? 'month';
    _buildLookupMaps();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleSummaryBuild();
    });
  }

  void _scheduleSummaryBuild() {
    final fp = _summaryRowsFp;
    if (_cachedSummaryRows != null && _cachedSummaryRowsFp == fp) return;
    if (_isSummarizing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _startSummaryBuild(fp);
    });
  }

  Future<void> _startSummaryBuild(int fp) async {
    if (!mounted) return;
    if (_cachedSummaryRows != null && _cachedSummaryRowsFp == fp) return;
    if (_isSummarizing) return;

    final token = ++_summaryBuildToken;
    setState(() => _isSummarizing = true);

    try {
      await Future<void>.delayed(Duration.zero);
      if (!mounted || token != _summaryBuildToken || fp != _summaryRowsFp) {
        return;
      }

      final data = await _computeDailySummaryDataAsync();
      if (!mounted || token != _summaryBuildToken || fp != _summaryRowsFp) {
        return;
      }

      setState(() {
        _cachedSummaryRows = data;
        _cachedSummaryRowsFp = fp;
        _isSummarizing = false;
        _invalidateDisplayDerivedCache();
      });
      _refreshOpenDetailDialog();
    } catch (e, st) {
      debugPrint('Summary compute error: $e\n$st');
      if (mounted && token == _summaryBuildToken) {
        setState(() => _isSummarizing = false);
      }
    }
  }

  void _ensureDesktopTableScrollLinked() {
    if (_desktopScrollLinked) return;
    _desktopScrollLinked = true;
    linkHorizontalScrollControllers(
      _desktopTableHScrollHeader,
      _desktopTableHScrollBody,
    );
  }

  void _notifyDataChanged() {
    _viewportPreserve.capture(listScroll: _listScrollController);
    widget.onDataChanged?.call();
  }

  @override
  void dispose() {
    _listScrollController.dispose();
    _desktopTableHScrollHeader.dispose();
    _desktopTableHScrollBody.dispose();
    super.dispose();
  }

  BoxDecoration get _tableCardDecoration => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      );

  /// Chiều cao vùng bảng có cuộn dọc riêng (desktop).
  double _tableBodyViewportHeight(BuildContext context) {
    final mq = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final reserved = pad.top + pad.bottom + 240;
    return (mq.height - reserved).clamp(260.0, 520.0);
  }

  static const int _mobileVisibleEmployeeRows = 10;

  double _mobileListViewportHeight(double rowHeight) =>
      _mobileVisibleEmployeeRows * rowHeight;

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

  static const _tableInnerScrollPhysics = ClampingScrollPhysics(
    parent: AlwaysScrollableScrollPhysics(),
  );

  @override
  void didUpdateWidget(covariant AttendanceSummaryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    final preset = widget.dateRangePreset;
    if (preset != null &&
        preset != _selectedPreset &&
        preset != oldWidget.dateRangePreset) {
      _selectedPreset = preset;
      _cachedSummaryRows = null;
      _invalidateDisplayDerivedCache();
      _currentPage = 0;
    }
    if (oldWidget.fromDate != widget.fromDate ||
        oldWidget.toDate != widget.toDate) {
      _cachedSummaryRows = null;
      _invalidateDisplayDerivedCache();
      _shiftRecordByKey = null;
    }
    if (oldWidget.salaryProfiles != widget.salaryProfiles ||
        oldWidget.shiftTemplates != widget.shiftTemplates ||
        oldWidget.shiftSalaryLevels != widget.shiftSalaryLevels ||
        oldWidget.employeesList != widget.employeesList ||
        oldWidget.workSchedules != widget.workSchedules) {
      _buildLookupMaps(); // already nulls _cachedSummaryRows
    } else if (oldWidget.attendances != widget.attendances ||
        oldWidget.holidays != widget.holidays ||
        oldWidget.branches != widget.branches ||
        oldWidget.fromDate != widget.fromDate ||
        oldWidget.toDate != widget.toDate) {
      _cachedSummaryRows = null;
      _invalidateDisplayDerivedCache();
      _shiftRecordByKey = null;
      if (oldWidget.attendances != widget.attendances) {
        _viewportPreserve.restore(listScroll: _listScrollController);
      }
    }
    if (_cachedSummaryRows == null ||
        _cachedSummaryRowsFp != _summaryRowsFp ||
        oldWidget.attendances != widget.attendances) {
      _scheduleSummaryBuild();
    }
    if (oldWidget.attendances != widget.attendances) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshOpenDetailDialog();
      });
    }
  }

  String _detailLookupKey(_DailySummary s) =>
      '${s.employeeId}|${_summaryDateKeyFmt.format(s.date)}';

  _DailySummary? _summaryForDetailKey(String key) {
    for (final s in _dailySummaryData) {
      if (_detailLookupKey(s) == key) return s;
    }
    return null;
  }

  void _clearOpenDetailDialogRefs() {
    _openDetailLookupKey = null;
    _openDetailDialogSetState = null;
    _openDetailHostContext = null;
  }

  BuildContext get _correctionDialogContext =>
      _openDetailHostContext ?? context;

  _DailySummary _liveSummaryForDetail(_DailySummary fallback) {
    final key = _openDetailLookupKey;
    if (key == null) return fallback;
    return _summaryForDetailKey(key) ?? fallback;
  }

  void _refreshOpenDetailDialog({bool force = false}) {
    final setDialog = _openDetailDialogSetState;
    final key = _openDetailLookupKey;
    if (setDialog == null || key == null) return;
    final updated = _summaryForDetailKey(key);
    if (updated == null) {
      if (_isSummarizing && !force) {
        setDialog(() {});
        return;
      }
      _clearOpenDetailDialogRefs();
      final nav = Navigator.of(_correctionDialogContext);
      if (nav.canPop()) nav.pop();
      return;
    }
    setDialog(() {});
  }

  Future<void> _applyCorrectionRequest(
      AttendanceCorrectionRequest request) async {
    final handler = widget.onCorrectionRequest;
    if (handler == null) return;
    _viewportPreserve.capture(listScroll: _listScrollController);
    await handler(request);
    if (!mounted) return;
    _cachedSummaryRows = null;
    _invalidateDisplayDerivedCache();
    _shiftRecordByKey = null;
    if (_openDetailLookupKey != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshOpenDetailDialog(force: true);
      });
    }
  }

  int get _summaryRowsFp => Object.hash(
        _selectedPreset,
        widget.dateRangePreset,
        widget.fromDate.millisecondsSinceEpoch,
        widget.toDate.millisecondsSinceEpoch,
        Object.hashAll(_selectedEmployeeIds),
        identityHashCode(widget.attendances),
        widget.salaryProfiles.length,
        widget.shiftTemplates.length,
        widget.shiftSalaryLevels.length,
        widget.holidays.length,
        widget.branches?.length,
        widget.employeesList?.length,
        widget.approvedLeaves.length,
        widget.dayEndHour,
        widget.dayEndMinute,
      );

  int get _shiftRecordsCacheFp => Object.hash(
        _summaryRowsFp,
        identityHashCode(_filteredAttendances),
      );

  int get _displayDataFp => Object.hash(
        _summaryRowsFp,
        _cachedSummaryRowsFp,
        _sortColumn,
        _sortAscending,
        _shiftFilter,
      );

  void _invalidateDisplayDerivedCache() {
    _cachedDisplaySummaries = null;
    _cachedDisplayFp = null;
    _cachedTableCols = null;
    _cachedTableColsFp = null;
    _cachedOverviewStats = null;
    _cachedOverviewStatsFp = null;
  }

  void _rebuildDisplayDerivedCache(
      List<_DailySummary> summaries, int fp) {
    _cachedTableCols = _tableColumnLimits(summaries);
    _cachedTableColsFp = fp;
    var totalHours = 0.0;
    var totalShifts = 0;
    final uniqueEmployees = <String>{};
    for (final s in summaries) {
      totalHours += s.totalHours;
      uniqueEmployees.add(s.employeeId);
      if (s.shift1Hours > 0) totalShifts++;
      if (s.shift2Hours > 0) totalShifts++;
      if (s.shift3Hours > 0) totalShifts++;
      if (s.shift4Hours > 0) totalShifts++;
      if (s.shift5Hours > 0) totalShifts++;
    }
    _cachedOverviewStats = (
      totalHours: totalHours,
      uniqueEmployees: uniqueEmployees.length,
      totalShifts: totalShifts,
    );
    _cachedOverviewStatsFp = fp;
  }

  List<Map<String, dynamic>> _salaryProfilesForShiftCalc() {
    return widget.salaryProfiles
        .whereType<Map>()
        .map((p) => Map<String, dynamic>.from(p))
        .toList();
  }

  Map<String, DailyShiftRecord> _shiftRecordLookup() {
    final fp = _shiftRecordsCacheFp;
    if (_shiftRecordByKey != null && _shiftRecordsFp == fp) {
      return _shiftRecordByKey!;
    }
    final range = _selectedDateRange;
    final records = computeDailyShiftRecords(
      attendances: _filteredAttendances,
      fromDate: range.start,
      toDate: range.end,
      shiftTemplates: widget.shiftTemplates,
      shiftSalaryLevels: widget.shiftSalaryLevels,
      salaryProfiles: _salaryProfilesForShiftCalc(),
      employeesList: widget.employeesList
          ?.map((e) => Map<String, dynamic>.from(e))
          .toList(),
      holidays: widget.holidays,
      dayEndHour: widget.dayEndHour,
      dayEndMinute: widget.dayEndMinute,
      minHoursForWorkDay: widget.minHoursForWorkDay,
      decimalWorkDayEnabled: widget.decimalWorkDayEnabled,
      standardWorkHours: widget.standardWorkHours,
      scheduleDayOffKeys: _scheduleDayOffKeys,
    );
    _shiftRecordByKey = dailyShiftRecordByAttendanceKey(records);
    _shiftRecordsFp = fp;
    return _shiftRecordByKey!;
  }

  void _buildLookupMaps() {
    _cachedSummaryRows = null; // salary-profile/employee data changed
    _invalidateDisplayDerivedCache();
    _shiftRecordByKey = null;
    _employeeCodeToWeeklyOffDays = {};
    _employeeCodeToHolidayMultiplier = {};
    _employeeCodeToHolidayOvertimeType = {};
    _employeeCodeToShiftsPerDay = {};
    _employeeCodeToGuid = {};
    _employeeCodeToRateType = {};
    // Build branch lookup from employeesList
    _codeTobranchName = {};
    _codeOrPinToApplicationUserId = {};
    _codeOrPinToHrEmployeeCode = {};
    if (widget.employeesList != null) {
      for (final emp in widget.employeesList!) {
        final code = emp['employeeCode']?.toString() ?? '';
        final pin = emp['pin']?.toString() ?? '';
        final userId = emp['applicationUserId']?.toString() ?? '';
        final empId = emp['id']?.toString() ?? '';
        if (code.isNotEmpty) {
          _codeTobranchName[code] = emp['branchName']?.toString() ?? '';
          if (empId.isNotEmpty) _employeeCodeToGuid[code] = empId;
          if (userId.isNotEmpty) {
            _codeOrPinToApplicationUserId[code] = userId;
            _codeOrPinToHrEmployeeCode[code] = code;
          }
        }
        if (pin.isNotEmpty) {
          if (empId.isNotEmpty) _employeeCodeToGuid[pin] = empId;
          if (userId.isNotEmpty) {
            _codeOrPinToApplicationUserId[pin] = userId;
            if (code.isNotEmpty) _codeOrPinToHrEmployeeCode[pin] = code;
          }
        }
      }
    }
    _employeeCodeToPaidLeaveType = {};
    for (final profile in widget.salaryProfiles) {
      if (profile is! Map<String, dynamic>) continue;
      final shiftsPerDay = (profile['shiftsPerDay'] as num?)?.toInt() ?? 1;
      var weeklyOffDays = profile['weeklyOffDays']?.toString() ?? '';
      var paidLeaveType = profile['paidLeaveType']?.toString() ?? '';
      final nestedBenefit = profile['benefit'];
      if (paidLeaveType.isEmpty && nestedBenefit is Map) {
        paidLeaveType = nestedBenefit['paidLeaveType']?.toString() ?? '';
      }
      if (weeklyOffDays.isEmpty && nestedBenefit is Map) {
        weeklyOffDays = nestedBenefit['weeklyOffDays']?.toString() ?? '';
      }
      if (isSchedulePaidLeaveType(paidLeaveType) ||
          isFlatOffPaidLeaveType(paidLeaveType)) {
        weeklyOffDays = '';
      }
      final holidayMultiplier =
          (profile['holidayMultiplier'] as num?)?.toDouble() ?? 2.0;
      final holidayOvertimeType =
          (profile['holidayOvertimeType'] as num?)?.toInt() ?? 1;
      final rateType = _parseRateType(profile['rateType']);
      final employees = profile['employees'] as List? ?? [];
      for (final emp in employees) {
        if (emp is Map<String, dynamic>) {
          final code = emp['employeeCode']?.toString() ?? '';
          final guid = emp['id']?.toString() ?? '';
          if (code.isNotEmpty) {
            _employeeCodeToWeeklyOffDays[code] = weeklyOffDays;
            _employeeCodeToPaidLeaveType[code] = paidLeaveType;
            if (guid.isNotEmpty) {
              _employeeCodeToPaidLeaveType[guid] = paidLeaveType;
            }
            _employeeCodeToHolidayMultiplier[code] = holidayMultiplier;
            _employeeCodeToHolidayOvertimeType[code] = holidayOvertimeType;
            _employeeCodeToShiftsPerDay[code] = shiftsPerDay;
            _employeeCodeToRateType[code] = rateType;
            if (guid.isNotEmpty) _employeeCodeToGuid[code] = guid;
          }
        }
      }
    }
    _scheduleDayOffKeys = buildScheduleDayOffKeys(
      widget.workSchedules,
      employeeCodeToGuid: _employeeCodeToGuid,
    );
    _scheduleWorkDayKeys = buildScheduleWorkDayKeys(
      widget.workSchedules,
      employeeCodeToGuid: _employeeCodeToGuid,
    );
    _employeesWithSchedule = buildEmployeesWithSchedule(widget.workSchedules);
    if (widget.employeesList != null) {
      for (final emp in widget.employeesList!) {
        final code = emp['employeeCode']?.toString() ?? '';
        final pin = emp['pin']?.toString() ?? '';
        if (code.isEmpty || pin.isEmpty) continue;
        if (_employeeCodeToWeeklyOffDays.containsKey(code)) {
          _employeeCodeToWeeklyOffDays[pin] =
              _employeeCodeToWeeklyOffDays[code]!;
        }
        if (_employeeCodeToPaidLeaveType.containsKey(code)) {
          _employeeCodeToPaidLeaveType[pin] =
              _employeeCodeToPaidLeaveType[code]!;
        }
        if (_employeeCodeToHolidayMultiplier.containsKey(code)) {
          _employeeCodeToHolidayMultiplier[pin] =
              _employeeCodeToHolidayMultiplier[code]!;
        }
        if (_employeeCodeToHolidayOvertimeType.containsKey(code)) {
          _employeeCodeToHolidayOvertimeType[pin] =
              _employeeCodeToHolidayOvertimeType[code]!;
        }
        if (_employeeCodeToShiftsPerDay.containsKey(code)) {
          _employeeCodeToShiftsPerDay[pin] = _employeeCodeToShiftsPerDay[code]!;
        }
      }
    }
  }

  /// Check if a date is a weekly off day for a given employee
  bool _isWeeklyOffDay(DateTime date, String employeeCode) {
    final guid = _employeeCodeToGuid[employeeCode];
    final ids = <String>[
      employeeCode,
      if (guid != null && guid.isNotEmpty) guid,
    ];
    if (scheduleKeyHit(_scheduleDayOffKeys, date, ids)) return true;

    final paidLeaveType = _employeeCodeToPaidLeaveType[employeeCode] ??
        _employeeCodeToPaidLeaveType[guid ?? ''] ??
        '';
    if (isSchedulePaidLeaveType(paidLeaveType) ||
        isFlatOffPaidLeaveType(paidLeaveType)) {
      return false;
    }

    final weeklyOff =
        (_employeeCodeToWeeklyOffDays[employeeCode] ?? '').trim();
    if (weeklyOff.isEmpty) return false;
    final weekday = date.weekday;
    if (weeklyOff.contains('Sunday') && weekday == DateTime.sunday) return true;
    if (weeklyOff.contains('Saturday') && weekday == DateTime.saturday) {
      return true;
    }
    return false;
  }

  /// Get holiday salaryRate or null. Holiday scope can be by employeeCode or
  /// employeeId (GUID). API stores GUIDs in `employeeIds`.
  double? _getHolidayRate(DateTime date, String employeeCode) {
    final empGuid = _employeeCodeToGuid[employeeCode];
    for (final h in widget.holidays) {
      if (h is! Map<String, dynamic>) continue;
      final holidayDate = DateTime.tryParse(h['date']?.toString() ?? '');
      if (holidayDate == null) continue;
      final isRecurring = h['isRecurring'] == true;
      final dateMatch = isRecurring
          ? holidayDate.month == date.month && holidayDate.day == date.day
          : holidayDate.year == date.year &&
              holidayDate.month == date.month &&
              holidayDate.day == date.day;
      if (!dateMatch) continue;
      final employeeCodes = h['employeeCodes'] as List?;
      final employeeIds = h['employeeIds'] as List?;
      // Combine both lists – any match (by code or GUID) is enough.
      final scopeList = <String>[
        if (employeeCodes != null)
          ...employeeCodes.map((e) => e?.toString() ?? ''),
        if (employeeIds != null) ...employeeIds.map((e) => e?.toString() ?? ''),
      ].where((s) => s.isNotEmpty).toList();
      if (scopeList.isNotEmpty) {
        final inScope = scopeList
            .any((s) => s == employeeCode || (empGuid != null && s == empGuid));
        if (!inScope) continue;
      }
      return (h['salaryRate'] as num?)?.toDouble() ?? 3.0;
    }
    return null;
  }

  DateTime _getLogicalDate(DateTime punchTime) =>
      AttendanceDateRangePresets.logicalWorkDay(
        punchTime,
        dayEndHour: widget.dayEndHour,
        dayEndMinute: widget.dayEndMinute,
      );

  AttendancePunchRef? _attendancePunchRef(
      _DailySummary summary, int punchIndex) {
    final time = summary.getPunch(punchIndex);
    if (time == null) return null;
    return resolveAttendancePunchRef(
      attendances: widget.attendances,
      employeeKey: summary.employeeId,
      employeeCode: summary.employeeCode,
      pin: summary.pin,
      workDate: summary.date,
      punchTime: time,
      preferredId: summary.getPunchId(punchIndex),
      logicalDayOf: _getLogicalDate,
    );
  }

  String? _attendanceIdForPunch(_DailySummary summary, int punchIndex) =>
      _attendancePunchRef(summary, punchIndex)?.id;

  /// Unique employees: punches + HR roster (để hiện NV chưa chấm trong khoảng).
  List<_EmployeeOption> get _allEmployees {
    final Map<String, _EmployeeOption> map = {};
    for (final att in widget.attendances) {
      final id = att.employeeId ?? att.enrollNumber ?? 'unknown';
      if (!map.containsKey(id)) {
        final name = att.employeeName?.isNotEmpty == true
            ? att.employeeName!
            : (att.deviceUserName?.isNotEmpty == true
                ? att.deviceUserName!
                : '-');
        final code = att.employeeId?.isNotEmpty == true
            ? att.employeeId!
            : (att.enrollNumber ?? '-');
        map[id] = _EmployeeOption(
          id: id,
          name: name,
          code: code,
        );
      }
    }
    final roster = widget.employeesList;
    if (roster != null) {
      for (final emp in roster) {
        final code = emp['employeeCode']?.toString() ?? '';
        final pin = emp['pin']?.toString() ?? '';
        final id = code.isNotEmpty ? code : (pin.isNotEmpty ? pin : '');
        if (id.isEmpty || map.containsKey(id)) continue;
        final name = emp['fullName']?.toString() ??
            emp['name']?.toString() ??
            emp['employeeName']?.toString() ??
            '-';
        map[id] = _EmployeeOption(id: id, name: name, code: code.isNotEmpty ? code : id);
      }
    }
    final list = map.values.toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  DateTimeRange get _selectedDateRange => AttendanceDateRangePresets.resolve(
        _selectedPreset,
        customFrom: widget.fromDate,
        customTo: widget.toDate,
      );

  /// Lọc attendances theo preset và search
  List<Attendance> get _filteredAttendances {
    final range = _selectedDateRange;
    var result = widget.attendances.where((att) {
      final logical = _getLogicalDate(att.punchTime);
      return AttendanceDateRangePresets.isLogicalDayInRange(logical, range);
    }).toList();

    // Filter theo selected employees
    if (_selectedEmployeeIds.isNotEmpty) {
      result = result.where((att) {
        final id = att.employeeId ?? att.enrollNumber ?? 'unknown';
        return _selectedEmployeeIds.contains(id);
      }).toList();
    }

    return result;
  }

  /// Dữ liệu tổng hợp hiển thị (sort/lọc sync trên cache tính nền).
  List<_DailySummary> get _dailySummaryData {
    final rowsFp = _summaryRowsFp;
    if (_cachedSummaryRows == null || _cachedSummaryRowsFp != rowsFp) {
      _scheduleSummaryBuild();
      if (_openDetailLookupKey != null &&
          _cachedSummaryRows != null &&
          _cachedSummaryRows!.isNotEmpty) {
        final fp = _displayDataFp;
        if (_cachedDisplaySummaries != null && _cachedDisplayFp == fp) {
          return _cachedDisplaySummaries!;
        }
        final filtered = _applySortAndFilter(_cachedSummaryRows!);
        _cachedDisplaySummaries = filtered;
        _cachedDisplayFp = fp;
        _rebuildDisplayDerivedCache(filtered, fp);
        return filtered;
      }
      return const [];
    }
    final fp = _displayDataFp;
    if (_cachedDisplaySummaries != null && _cachedDisplayFp == fp) {
      return _cachedDisplaySummaries!;
    }
    final filtered = _applySortAndFilter(_cachedSummaryRows!);
    _cachedDisplaySummaries = filtered;
    _cachedDisplayFp = fp;
    _rebuildDisplayDerivedCache(filtered, fp);
    return filtered;
  }

  Widget _buildSummarizingPlaceholder() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 48),
      decoration: _tableCardDecoration,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 14),
          Text(tr('Đang xử lý tổng hợp...'),
            style: TextStyle(fontSize: 13, color: Color(0xFF52525B)),
          ),
        ],
      ),
    );
  }

  Map<String, int> _branchOrderMap() {
    final branches = widget.branches;
    if (branches == null || branches.isEmpty) return const {};
    final map = <String, int>{};
    for (var i = 0; i < branches.length; i++) {
      final name = branches[i]['name']?.toString() ?? '';
      if (name.isNotEmpty) map[name] = i;
    }
    return map;
  }

  Future<List<_DailySummary>> _computeDailySummaryDataAsync() async {
    await Future<void>.delayed(Duration.zero);
    final shiftLookup = _shiftRecordLookup();
    final filteredData = _filteredAttendances;
    final groupedByEmployeeDate = <String, List<Attendance>>{};

    for (final att in filteredData) {
      final employeeKey = att.employeeId ?? att.enrollNumber ?? 'unknown';
      final logicalDate = _getLogicalDate(att.punchTime);
      final dateKey = _summaryDateKeyFmt.format(logicalDate);
      final key = '$employeeKey|$dateKey';
      groupedByEmployeeDate.putIfAbsent(key, () => []).add(att);
    }

    final summaries = <_DailySummary>[];
    final keys = groupedByEmployeeDate.keys.toList();
    var processed = 0;

    for (final key in keys) {
      final attendances = groupedByEmployeeDate[key]!;
      if (attendances.isEmpty) continue;

      final first = attendances.first;
      final date = _getLogicalDate(first.punchTime);
      final layout = layoutSummaryDayPunches(
        attendances,
        dayEndHour: widget.dayEndHour,
        dayEndMinute: widget.dayEndMinute,
      );
      final punches = layout.punchTimes;
      final punchIds = layout.punchIds;
      final shiftHours = layout.shiftHours;

      final empCodeForLookup = first.employeeId?.isNotEmpty == true
          ? first.employeeId!
          : (first.enrollNumber ?? '-');

      var totalShiftHours = shiftHours.fold(0.0, (sum, h) => sum + h);

      final dateKey = _summaryDateKeyFmt.format(date);
      final shiftRec = shiftLookup['$empCodeForLookup|$dateKey'];
      final holidayRate = _getHolidayRate(date, empCodeForLookup);
      final isHoliday = holidayRate != null;
      final isRestDay = !isHoliday && _isWeeklyOffDay(date, empCodeForLookup);
      final holidayMultiplier =
          _employeeCodeToHolidayMultiplier[empCodeForLookup] ?? 2.0;
      final holidayOvertimeType =
          _employeeCodeToHolidayOvertimeType[empCodeForLookup] ?? 1;
      var effectiveMultiplier = 1.0;
      if (isHoliday) {
        effectiveMultiplier = holidayRate!;
      } else if (isRestDay && holidayOvertimeType == 1) {
        effectiveMultiplier = holidayMultiplier;
      }
      final workCount = shiftRec?.workCount ?? 0.0;
      if (shiftRec != null && shiftRec.workHours > 0) {
        totalShiftHours = shiftRec.workHours;
      }

      final empName = first.employeeName?.isNotEmpty == true
          ? first.employeeName!
          : (first.deviceUserName?.isNotEmpty == true
              ? first.deviceUserName!
              : '-');
      final empCode = first.employeeId?.isNotEmpty == true
          ? first.employeeId!
          : (first.enrollNumber ?? '-');
      final hrCode = _codeOrPinToHrEmployeeCode[empCode] ?? empCode;
      final applicationUserId = _codeOrPinToApplicationUserId[empCode];
      final employeeGuid =
          _employeeCodeToGuid[empCode] ?? _employeeCodeToGuid[hrCode];

      summaries.add(_DailySummary(
        employeeId: empCode,
        employeeName: empName,
        employeeCode: hrCode,
        pin: first.enrollNumber,
        applicationUserId: applicationUserId,
        employeeGuid: employeeGuid,
        date: date,
        punch1: punches[0],
        punch2: punches[1],
        punch3: punches[2],
        punch4: punches[3],
        punch5: punches[4],
        punch6: punches[5],
        punch7: punches[6],
        punch8: punches[7],
        punch9: punches[8],
        punch10: punches[9],
        punchId1: punchIds[0],
        punchId2: punchIds[1],
        punchId3: punchIds[2],
        punchId4: punchIds[3],
        punchId5: punchIds[4],
        punchId6: punchIds[5],
        punchId7: punchIds[6],
        punchId8: punchIds[7],
        punchId9: punchIds[8],
        punchId10: punchIds[9],
        shift1Hours: shiftHours[0],
        shift2Hours: shiftHours[1],
        shift3Hours: shiftHours[2],
        shift4Hours: shiftHours[3],
        shift5Hours: shiftHours[4],
        totalHours: totalShiftHours,
        totalPunches: layout.totalPunches,
        workCount: workCount,
        effectiveMultiplier: effectiveMultiplier,
        isHoliday: isHoliday,
        isRestDay: isRestDay,
        branchName: _codeTobranchName[empCode] ?? '',
      ));

      processed++;
      final yieldEvery = keys.length > 400
          ? 25
          : keys.length > 150
              ? 40
              : 60;
      if (processed % yieldEvery == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    return _appendUnpaidAbsentPlaceholders(summaries);
  }

  /// Thêm dòng trống (0 chấm) cho NV×ngày làm việc vắng — hiện nút + / Thêm công.
  List<_DailySummary> _appendUnpaidAbsentPlaceholders(
    List<_DailySummary> summaries,
  ) {
    final roster = widget.employeesList;
    if (roster == null || roster.isEmpty) return summaries;

    final existing = <String>{};
    for (final s in summaries) {
      existing.add('${s.employeeId}|${_summaryDateKeyFmt.format(s.date)}');
      if (s.pin != null && s.pin!.isNotEmpty) {
        existing.add('${s.pin}|${_summaryDateKeyFmt.format(s.date)}');
      }
      if (s.employeeCode.isNotEmpty) {
        existing.add('${s.employeeCode}|${_summaryDateKeyFmt.format(s.date)}');
      }
    }

    final leaveCtx = _verticalSummaryLeaveContext();
    final dates = attendanceDaysInRange(_selectedDateRange);
    final out = List<_DailySummary>.from(summaries);

    for (final emp in roster) {
      final code = emp['employeeCode']?.toString() ?? '';
      final pin = emp['pin']?.toString() ?? '';
      final empId = code.isNotEmpty ? code : pin;
      if (empId.isEmpty) continue;

      if (_selectedEmployeeIds.isNotEmpty &&
          !_selectedEmployeeIds.contains(empId) &&
          !_selectedEmployeeIds.contains(code) &&
          !_selectedEmployeeIds.contains(pin)) {
        continue;
      }

      final name = emp['fullName']?.toString() ??
          emp['name']?.toString() ??
          emp['employeeName']?.toString() ??
          '-';
      final hrCode = _codeOrPinToHrEmployeeCode[empId] ??
          (code.isNotEmpty ? code : empId);
      final applicationUserId = _codeOrPinToApplicationUserId[empId] ??
          _codeOrPinToApplicationUserId[code];
      final employeeGuid =
          _employeeCodeToGuid[empId] ?? _employeeCodeToGuid[hrCode];
      final paidLeaveType = _employeeCodeToPaidLeaveType[hrCode] ??
          _employeeCodeToPaidLeaveType[empId] ??
          _employeeCodeToPaidLeaveType[employeeGuid ?? ''] ??
          '';
      final scheduleMode = isSchedulePaidLeaveType(paidLeaveType);
      final hasAnySchedule = _employeesWithSchedule.contains(hrCode) ||
          _employeesWithSchedule.contains(empId) ||
          _employeesWithSchedule.contains(pin) ||
          (employeeGuid != null &&
              employeeGuid.isNotEmpty &&
              _employeesWithSchedule.contains(employeeGuid)) ||
          (applicationUserId != null &&
              applicationUserId.isNotEmpty &&
              _employeesWithSchedule.contains(applicationUserId));

      for (final date in dates) {
        final dateKey = _summaryDateKeyFmt.format(date);
        if (existing.contains('$empId|$dateKey') ||
            (code.isNotEmpty && existing.contains('$code|$dateKey')) ||
            (pin.isNotEmpty && existing.contains('$pin|$dateKey'))) {
          continue;
        }

        final ids = <String>[
          hrCode,
          empId,
          if (pin.isNotEmpty) pin,
          if (employeeGuid != null && employeeGuid.isNotEmpty) employeeGuid,
          if (applicationUserId != null && applicationUserId.isNotEmpty)
            applicationUserId,
        ];
        if (scheduleMode) {
          if (!hasAnySchedule) continue;
          if (scheduleKeyHit(_scheduleDayOffKeys, date, ids)) continue;
          if (!scheduleKeyHit(_scheduleWorkDayKeys, date, ids)) continue;
        }

        final kind = leaveCtx.leaveLookup.classify(
          day: date,
          employeeCode: hrCode,
          employeeUserId: leaveCtx.empUserIdMap[hrCode] ??
              leaveCtx.empUserIdMap[empId] ??
              applicationUserId,
          hrEmployeeId: leaveCtx.hrEmpIdMap[hrCode] ??
              leaveCtx.hrEmpIdMap[empId] ??
              employeeGuid,
          displayEmployeeId: empId,
          isHoliday: _getHolidayRate(date, hrCode) != null ||
              _getHolidayRate(date, empId) != null,
          isWeeklyOff: _isWeeklyOffDay(date, hrCode) ||
              _isWeeklyOffDay(date, empId),
        );
        if (kind != AbsenceCellKind.unpaidAbsent) continue;

        out.add(_DailySummary(
          employeeId: empId,
          employeeName: name,
          employeeCode: hrCode,
          pin: pin.isNotEmpty ? pin : null,
          applicationUserId: applicationUserId,
          employeeGuid: employeeGuid,
          date: date,
          shift1Hours: 0,
          shift2Hours: 0,
          totalHours: 0,
          totalPunches: 0,
          workCount: 0,
          branchName: _codeTobranchName[empId] ??
              _codeTobranchName[hrCode] ??
              '',
        ));
        existing.add('$empId|$dateKey');
      }
    }
    return out;
  }

  _DailySummary _placeholderSummaryForAbsent({
    required String empId,
    required String empName,
    required String empCode,
    required DateTime date,
  }) {
    final hrCode = _codeOrPinToHrEmployeeCode[empId] ?? empCode;
    return _DailySummary(
      employeeId: empId,
      employeeName: empName,
      employeeCode: hrCode,
      pin: empId != hrCode ? empId : null,
      applicationUserId: _codeOrPinToApplicationUserId[empId] ??
          _codeOrPinToApplicationUserId[hrCode],
      employeeGuid:
          _employeeCodeToGuid[empId] ?? _employeeCodeToGuid[hrCode],
      date: date,
      shift1Hours: 0,
      shift2Hours: 0,
      totalHours: 0,
      totalPunches: 0,
      workCount: 0,
      branchName: _codeTobranchName[empId] ?? _codeTobranchName[hrCode] ?? '',
    );
  }

  List<_DailySummary> _applySortAndFilter(List<_DailySummary> summaries) {
    final sorted = List<_DailySummary>.from(summaries);
    final branchOrder = _branchOrderMap();
    final branchFallback = branchOrder.length;

    int branchOrderOf(String branchName) =>
        branchOrder[branchName] ?? branchFallback;

    sorted.sort((a, b) {
      if (branchOrder.isNotEmpty) {
        final bo = branchOrderOf(a.branchName)
            .compareTo(branchOrderOf(b.branchName));
        if (bo != 0) return bo;
      }
      int cmp;
      if (_sortColumn == 'date') {
        cmp = a.date.compareTo(b.date);
        if (cmp == 0) cmp = a.employeeName.compareTo(b.employeeName);
      } else if (_sortColumn == 'name') {
        cmp = a.employeeName.compareTo(b.employeeName);
        if (cmp == 0) cmp = a.date.compareTo(b.date);
      } else if (_sortColumn == 'code') {
        cmp = a.employeeCode.compareTo(b.employeeCode);
        if (cmp == 0) cmp = a.date.compareTo(b.date);
      } else if (_sortColumn == 'totalHours') {
        cmp = a.totalHours.compareTo(b.totalHours);
        if (cmp == 0) cmp = a.date.compareTo(b.date);
      } else {
        cmp = a.employeeName.compareTo(b.employeeName);
        if (cmp == 0) cmp = a.date.compareTo(b.date);
      }
      return _sortAscending ? cmp : -cmp;
    });

    if (_shiftFilter == 'missing') {
      return sorted
          .where((s) => s.totalPunches % 2 != 0 || s.totalPunches < 2)
          .toList();
    }
    if (_shiftFilter == 'complete') {
      return sorted
          .where((s) => s.totalPunches >= 2 && s.totalPunches % 2 == 0)
          .toList();
    }
    return sorted;
  }

  String _getDayOfWeekVN(int weekday) {
    switch (weekday) {
      case 1:
        return 'Thứ 2';
      case 2:
        return 'Thứ 3';
      case 3:
        return 'Thứ 4';
      case 4:
        return 'Thứ 5';
      case 5:
        return 'Thứ 6';
      case 6:
        return 'Thứ 7';
      case 7:
        return 'CN';
      default:
        return '-';
    }
  }

  /// Parse rateType: backend can send string ("Hourly","Monthly","Daily","Shift") or int
  static int _parseRateType(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toInt();
    final s = v.toString().toLowerCase();
    if (s == 'monthly' || s == '1') return 1;
    if (s == 'daily' || s == '2') return 2;
    if (s == 'shift' || s == '3') return 3;
    return 0; // hourly
  }

  Color _getDayColor(int weekday) {
    if (weekday == 7) return Colors.red;
    if (weekday == 6) return Colors.orange;
    return Colors.grey;
  }

  String _formatDecimalHours(double hours) {
    if (hours <= 0) return '-';
    return hours.toStringAsFixed(2);
  }

  double _travelHoursForSummary(_DailySummary s) {
    if (!_showTravelColumns) return 0;
    return lookupTravelHoursForDay(
      widget.travelHoursByEmployeeDateKey,
      date: s.date,
      employeeId: s.employeeId,
      employeeCode: s.employeeCode,
      applicationUserId: s.applicationUserId,
      employeeGuid: s.employeeGuid,
      pin: s.pin,
    );
  }

  double _travelHoursTotalForEmployee({
    String? employeeId,
    String? employeeCode,
    String? applicationUserId,
    String? employeeGuid,
    String? pin,
  }) {
    if (!_showTravelColumns) return 0;
    return lookupTravelHoursTotal(
      widget.travelHoursByEmployeeKey,
      employeeId: employeeId,
      employeeCode: employeeCode,
      applicationUserId: applicationUserId,
      employeeGuid: employeeGuid,
      pin: pin,
    );
  }

  Widget _buildTravelHoursCell(double hours, {bool bold = false}) {
    if (hours <= 0) {
      return Text(tr('—'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: Color(0xFFA1A1AA)));
    }
    return Text(
      tr(_formatHours(hours)),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
        color: HrmPageChrome.chipLight,
      ),
    );
  }

  String _formatHours(double hours) {
    if (hours <= 0) return '-';
    final h = hours.floor();
    final m = ((hours - h) * 60).round();
    if (m == 0) return '${h}h';
    return '${h}h${m.toString().padLeft(2, '0')}';
  }

  /// Số cặp ca (1–5) có ít nhất một lần chấm trong [_DailySummary].
  int _summaryShiftPairCount(_DailySummary s) {
    var n = 0;
    for (var i = 1; i <= 5; i++) {
      if (s.getPunch(i * 2 - 1) != null || s.getPunch(i * 2) != null) {
        n++;
      }
    }
    return n;
  }

  /// Số cột Lần 1..N và Giờ ca 1..M theo dữ liệu thực tế (tối đa 10 lần / 5 ca).
  ({int maxPunches, int maxShifts}) _tableColumnLimits(
      List<_DailySummary> summaries) {
    var maxUsedPunchSlot = 2;
    var maxUsedShiftSlot = 1;
    for (final s in summaries) {
      for (var i = 1; i <= 10; i++) {
        if (s.getPunch(i) != null && i > maxUsedPunchSlot) {
          maxUsedPunchSlot = i;
        }
      }
      final pairSlots = _summaryShiftPairCount(s);
      if (pairSlots > maxUsedShiftSlot) maxUsedShiftSlot = pairSlots;
      for (var i = 5; i >= 1; i--) {
        if (s.getShiftHours(i) > 0) {
          if (i > maxUsedShiftSlot) maxUsedShiftSlot = i;
          break;
        }
      }
    }
    var maxPunches = maxUsedPunchSlot < 2
        ? 2
        : ((maxUsedPunchSlot + 1) ~/ 2) * 2;
    if (maxPunches > 10) maxPunches = 10;
    var maxShifts = math.max(maxUsedShiftSlot, maxPunches ~/ 2);
    if (maxShifts > 5) maxShifts = 5;
    return (maxPunches: maxPunches, maxShifts: maxShifts);
  }

  @override
  Widget build(BuildContext context) {
    final summaries = _dailySummaryData;
    final range = _selectedDateRange;

    final displayFp = _displayDataFp;
    final overview = _cachedOverviewStatsFp == displayFp
        ? _cachedOverviewStats
        : null;
    final double totalHours = overview?.totalHours ??
        summaries.fold<double>(0.0, (sum, s) => sum + s.totalHours);
    final uniqueEmployees = overview?.uniqueEmployees ??
        summaries.map((s) => s.employeeId).toSet().length;
    var totalShifts = overview?.totalShifts ?? 0;
    if (overview == null) {
      for (final s in summaries) {
        if (s.shift1Hours > 0) totalShifts++;
        if (s.shift2Hours > 0) totalShifts++;
        if (s.shift3Hours > 0) totalShifts++;
        if (s.shift4Hours > 0) totalShifts++;
        if (s.shift5Hours > 0) totalShifts++;
      }
    }

    // Pagination
    final totalRows = summaries.length;
    final totalPages = (totalRows / _rowsPerPage).ceil();
    if (_currentPage >= totalPages && totalPages > 0) {
      _currentPage = totalPages - 1;
    }
    final startIndex = _currentPage * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage).clamp(0, totalRows);
    final pagedSummaries = totalRows > 0
        ? summaries.sublist(startIndex, endIndex)
        : <_DailySummary>[];

    final cols = _cachedTableColsFp == displayFp && _cachedTableCols != null
        ? _cachedTableCols!
        : _tableColumnLimits(summaries);
    final maxPunches = cols.maxPunches;
    final maxShifts = cols.maxShifts;

    final isMobileLayout = MediaQuery.sizeOf(context).width < 600;

    Widget buildOverviewSection() {
      return HrmCollapsibleOverview(
        expanded: _showOverviewPanel,
        onToggle: () =>
            setState(() => _showOverviewPanel = !_showOverviewPanel),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatsRow(
                totalRows, uniqueEmployees, totalHours, totalShifts),
            const SizedBox(height: 10),
            _buildFilters(range, embedded: true),
          ],
        ),
      );
    }

    if (isMobileLayout) {
      final useVerticalLayout = preferMobileVerticalAttendanceView(
        userRole: Provider.of<AuthProvider>(context, listen: false).userRole,
        uniqueEmployeeCount: uniqueEmployees,
      );
      final tableSlivers = _isSummarizing && summaries.isEmpty
          ? <Widget>[SliverToBoxAdapter(child: _buildSummarizingPlaceholder())]
          : summaries.isEmpty
              ? <Widget>[
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(child: _buildEmptyTableCard()),
                  ),
                ]
              : useVerticalLayout
                  ? _buildMobileVerticalAttendanceSlivers(
                      summaries, maxPunches, maxShifts)
                  : _buildMobileEmployeeSummarySlivers(
                      summaries, maxPunches, maxShifts);

      return CustomScrollView(
        controller: _listScrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.mobileLeadingSections != null) ...[
                    ...widget.mobileLeadingSections!,
                    const SizedBox(height: 12),
                  ],
                  buildOverviewSection(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          ...tableSlivers,
        ],
      );
    }

    final tableSlivers = _isSummarizing && summaries.isEmpty
        ? <Widget>[
            SliverToBoxAdapter(child: _buildSummarizingPlaceholder()),
          ]
        : summaries.isEmpty
        ? <Widget>[
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(child: _buildEmptyTableCard()),
            ),
          ]
        : _buildDesktopTableSlivers(
            pagedSummaries: pagedSummaries,
            allSummaries: summaries,
            maxPunches: maxPunches,
            maxShifts: maxShifts,
            startIndex: startIndex,
            totalRows: totalRows,
            totalPages: totalPages,
          );

    return CustomScrollView(
      controller: _listScrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                buildOverviewSection(),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        ...tableSlivers,
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
          sliver: SliverToBoxAdapter(child: SizedBox(height: 8)),
        ),
      ],
    );
  }

  Widget _buildEmptyTableCard() {
    return Container(
      height: 200,
      decoration: _tableCardDecoration,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(tr('Không có dữ liệu'),
                style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  static const TextStyle _summaryHeaderTextStyle = TextStyle(
    fontWeight: FontWeight.w600,
    fontSize: 12,
    color: Color(0xFF71717A),
  );

  int _summaryColumnCount(int maxPunches, int maxShifts) =>
      5 + maxPunches + maxShifts + (_showTravelColumns ? 4 : 3);

  Map<int, TableColumnWidth> _summaryDesktopColumnWidths(
      int maxPunches, int maxShifts) {
    final widths = <int, TableColumnWidth>{
      0: const FixedColumnWidth(52),
      1: const FixedColumnWidth(172),
      2: const FixedColumnWidth(104),
      3: const FixedColumnWidth(60),
      4: const FixedColumnWidth(108),
    };
    var idx = 5;
    for (var i = 0; i < maxPunches; i++) {
      widths[idx++] = const FixedColumnWidth(78);
    }
    for (var i = 0; i < maxShifts; i++) {
      widths[idx++] = const FixedColumnWidth(78);
    }
    widths[idx++] = const FixedColumnWidth(82);
    if (_showTravelColumns) {
      widths[idx++] = const FixedColumnWidth(72);
    }
    widths[idx++] = const FixedColumnWidth(96);
    widths[idx] = const FixedColumnWidth(88);
    return widths;
  }

  double _summaryDesktopTableMinWidth(int maxPunches, int maxShifts) {
    return _summaryDesktopColumnWidths(maxPunches, maxShifts)
        .values
        .whereType<FixedColumnWidth>()
        .fold<double>(0, (sum, w) => sum + w.value);
  }

  Map<int, TableColumnWidth> _summaryColumnWidthsForTargetWidth(
    int maxPunches,
    int maxShifts,
    double targetWidth,
  ) {
    final base = _summaryDesktopColumnWidths(maxPunches, maxShifts);
    final keys = base.keys.toList()..sort();
    final baseValues = keys
        .map((k) => (base[k]! as FixedColumnWidth).value)
        .toList();
    final baseTotal = baseValues.fold<double>(0, (s, w) => s + w);
    if (baseTotal <= 0 || targetWidth <= 0) return base;
    final scale = targetWidth / baseTotal;
    final result = <int, TableColumnWidth>{};
    for (var i = 0; i < keys.length; i++) {
      result[keys[i]] = FixedColumnWidth(baseValues[i] * scale);
    }
    return result;
  }

  Widget _summaryTableCell(
    Widget child, {
    Alignment alignment = Alignment.center,
    EdgeInsetsGeometry padding =
        const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
  }) {
    return Padding(
      padding: padding,
      child: Align(alignment: alignment, child: child),
    );
  }

  Widget _summaryHeaderText(String label) => Text(
        tr(label),
        textAlign: TextAlign.center,
        style: _summaryHeaderTextStyle,
      );

  String _dailySummaryRowKey(_DailySummary s) =>
      '${s.employeeId}|${_summaryDateKeyFmt.format(s.date)}';

  Map<String, _EmployeePeriodTotals> _employeeTotalsFrom(
      List<_DailySummary> summaries) {
    final map = <String, _EmployeePeriodTotals>{};
    for (final s in summaries) {
      map
          .putIfAbsent(
            s.employeeId,
            () => _EmployeePeriodTotals(
              employeeId: s.employeeId,
              employeeName: s.employeeName,
              employeeCode: s.employeeCode,
            ),
          )
          .add(s);
    }
    return map;
  }

  Map<String, String> _employeeLastRowKeys(List<_DailySummary> summaries) {
    final last = <String, String>{};
    for (final s in summaries) {
      last[s.employeeId] = _dailySummaryRowKey(s);
    }
    return last;
  }

  TableRow _buildEmployeeSubtotalTableRow(
    _EmployeePeriodTotals totals,
    int maxPunches,
    int maxShifts,
    List<Color> shiftColors,
  ) {
    final workStr = totals.totalWork > 0
        ? (totals.totalWork % 1 == 0
            ? totals.totalWork.toInt().toString()
            : totals.totalWork.toStringAsFixed(1))
        : '-';
    final cells = <Widget>[
      _summaryTableCell(const SizedBox.shrink()),
      _summaryTableCell(
        Text(
          tr('Σ ${totals.employeeName}'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: HrmPageChrome.primaryNavy,
          ),
        ),
      ),
      _summaryTableCell(
        Text(
          tr(totals.employeeCode),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF71717A),
          ),
        ),
      ),
      _summaryTableCell(
        Text(tr('Tổng'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.blue.shade700,
          ),
        ),
      ),
      _summaryTableCell(
        Text(tr('${totals.presentDays} ngày'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF52525B),
          ),
        ),
      ),
    ];
    for (var i = 0; i < maxPunches; i++) {
      cells.add(_summaryTableCell(
        Text(tr('—'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
      ));
    }
    for (var i = 1; i <= maxShifts; i++) {
      final h = totals.shiftAt(i);
      cells.add(_summaryTableCell(
        h > 0
            ? _buildHoursBadge(h, shiftColors[i - 1], isBold: true)
            : Text(tr('—'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
      ));
    }
    cells.addAll([
      _summaryTableCell(
        totals.totalHours > 0
            ? _buildHoursBadge(totals.totalHours, Colors.green, isBold: true)
            : Text(tr('—'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
      ),
      if (_showTravelColumns)
        _summaryTableCell(_buildTravelHoursCell(
          _travelHoursTotalForEmployee(
            employeeId: totals.employeeId,
            employeeCode: totals.employeeCode,
          ),
          bold: true,
        )),
      _summaryTableCell(
        Text(
          tr(workStr),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: totals.totalWork > 0
                ? Colors.blue.shade700
                : const Color(0xFFA1A1AA),
          ),
        ),
      ),
      _summaryTableCell(
        Text(
          tr(totals.totalHours > 0
              ? _formatDecimalHours(totals.totalHours)
              : '—'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: totals.totalHours > 0
                ? Colors.blue.shade700
                : const Color(0xFFA1A1AA),
          ),
        ),
      ),
    ]);
    return TableRow(
      decoration: const BoxDecoration(color: Color(0xFFEFF6FF)),
      children: cells,
    );
  }

  Widget _summarySortableHeader(String label, String sortKey) {
    final active = _sortColumn == sortKey;
    return InkWell(
      onTap: () {
        setState(() {
          if (_sortColumn == sortKey) {
            _sortAscending = !_sortAscending;
          } else {
            _sortColumn = sortKey;
            _sortAscending = true;
          }
          _invalidateDisplayDerivedCache();
        });
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(child: _summaryHeaderText(label)),
          if (active) ...[
            const SizedBox(width: 2),
            Icon(
              _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 14,
              color: const Color(0xFF71717A),
            ),
          ],
        ],
      ),
    );
  }

  TableRow _buildSummaryHeaderTableRow(int maxPunches, int maxShifts) {
    final cells = <Widget>[
      _summaryTableCell(_summaryHeaderText('STT')),
      _summaryTableCell(_summarySortableHeader('Tên nhân viên', 'name')),
      _summaryTableCell(_summarySortableHeader('Mã nhân viên', 'code')),
      _summaryTableCell(_summaryHeaderText('Thứ')),
      _summaryTableCell(_summarySortableHeader('Ngày', 'date')),
    ];
    for (var i = 1; i <= maxPunches; i++) {
      cells.add(_summaryTableCell(_summaryHeaderText('Lần $i')));
    }
    for (var i = 1; i <= maxShifts; i++) {
      cells.add(_summaryTableCell(_summaryHeaderText('Giờ ca $i')));
    }
    cells.addAll([
      _summaryTableCell(_summarySortableHeader('Tổng giờ', 'totalHours')),
      if (_showTravelColumns)
        _summaryTableCell(_summaryHeaderText('Đi đường')),
      _summaryTableCell(_summaryHeaderText('Số công')),
      _summaryTableCell(_summaryHeaderText('Giờ thập phân')),
    ]);
    return TableRow(
      decoration: const BoxDecoration(color: Color(0xFFFAFAFA)),
      children: cells,
    );
  }

  Widget _buildSummaryDesktopTable({
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

  List<Widget> _buildDesktopTableSlivers({
    required List<_DailySummary> pagedSummaries,
    required List<_DailySummary> allSummaries,
    required int maxPunches,
    required int maxShifts,
    required int startIndex,
    required int totalRows,
    required int totalPages,
  }) {
    _ensureDesktopTableScrollLinked();
    const headerH = 44.0;
    final columnWidths = _summaryDesktopColumnWidths(maxPunches, maxShifts);
    final tableMinWidth = _summaryDesktopTableMinWidth(maxPunches, maxShifts);
    final headerRow = _buildSummaryHeaderTableRow(maxPunches, maxShifts);
    final daySttMap = _employeeDaySttMap(allSummaries);
    final dataRows = _buildSummaryDataTableRows(
      pagedSummaries,
      allSummaries,
      maxPunches,
      maxShifts,
      daySttMap,
    );

    Widget buildHeaderTable() {
      return _buildSummaryDesktopTable(
        columnWidths: columnWidths,
        rows: [headerRow],
      );
    }

    Widget buildBodyTable() {
      return _buildSummaryDesktopTable(
        columnWidths: columnWidths,
        rows: dataRows,
      );
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverPersistentHeader(
          pinned: true,
          delegate: PinnedBoxHeaderDelegate(
            extent: headerH,
            backgroundColor: const Color(0xFFFAFAFA),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Scrollbar(
                  thumbVisibility: true,
                  controller: _desktopTableHScrollHeader,
                  child: SingleChildScrollView(
                    controller: _desktopTableHScrollHeader,
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: math.max(constraints.maxWidth, tableMinWidth),
                      ),
                      child: buildHeaderTable(),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        sliver: SliverToBoxAdapter(
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(12),
            ),
            child: Container(
              decoration: _tableCardDecoration,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final bodyH = _tableBodyViewportHeight(context);
                      return SizedBox(
                        height: bodyH,
                        child: Scrollbar(
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            primary: false,
                            physics: _tableInnerScrollPhysics,
                            child: Scrollbar(
                              thumbVisibility: true,
                              controller: _desktopTableHScrollBody,
                              notificationPredicate: (n) =>
                                  n.depth == 1 && n is ScrollUpdateNotification,
                              child: SingleChildScrollView(
                                controller: _desktopTableHScrollBody,
                                scrollDirection: Axis.horizontal,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minWidth: math.max(
                                        constraints.maxWidth, tableMinWidth),
                                  ),
                                  child: RepaintBoundary(
                                    key: _tableKey,
                                    child: buildBodyTable(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  _buildPaginationBar(
                    totalRows,
                    totalPages,
                    onOpenFullscreen: () => _openDetailTableFullscreen(
                      allSummaries: allSummaries,
                      maxPunches: maxPunches,
                      maxShifts: maxShifts,
                    ),
                  ),
                  _buildBottomHorizontalScrollBar(tableMinWidth),
                ],
              ),
            ),
          ),
        ),
      ),
    ];
  }

  /// Stats cards row — nền trắng, viền xanh, thấp gọn.
  Widget _buildStatsRow(
      int totalRows, int uniqueEmployees, double totalHours, int totalShifts) {
    return HrmStatBar(
      items: [
        HrmStatItem(
            icon: Icons.list_alt, label: 'Bản ghi', value: '$totalRows'),
        HrmStatItem(
            icon: Icons.people,
            label: 'Nhân viên',
            value: '$uniqueEmployees'),
        HrmStatItem(
          icon: Icons.schedule,
          label: 'Tổng giờ',
          value:
              '${_formatHours(totalHours)} (${totalHours.toStringAsFixed(1)}h)',
        ),
        HrmStatItem(
            icon: Icons.work_history, label: 'Số ca', value: '$totalShifts'),
      ],
      padding: EdgeInsets.zero,
      gap: 6,
      valueFontSize: 14,
    );
  }

  void _openDetailTableFullscreen({
    required List<_DailySummary> allSummaries,
    required int maxPunches,
    required int maxShifts,
  }) {
    if (allSummaries.isEmpty) return;

    final vBody = ScrollController();
    final hBody = ScrollController();
    final daySttMap = _employeeDaySttMap(allSummaries);
    final headerRow = _buildSummaryHeaderTableRow(maxPunches, maxShifts);
    final dataRows = _buildSummaryDataTableRows(
      allSummaries,
      allSummaries,
      maxPunches,
      maxShifts,
      daySttMap,
    );
    final columnWidths = _summaryDesktopColumnWidths(maxPunches, maxShifts);
    final tableMinWidth = _summaryDesktopTableMinWidth(maxPunches, maxShifts);

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return Dialog.fullscreen(
          child: Scaffold(
            backgroundColor: const Color(0xFFFAFAFA),
            appBar: AppBar(
              title: Text(tr('Bảng chấm công chi tiết'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              leading: IconButton(
                tooltip: tr('Thoát chế độ toàn màn hình'),
                icon: const Icon(Icons.fullscreen_exit),
                onPressed: () => Navigator.pop(dialogCtx),
              ),
              actions: [
                TextButton.icon(
                  onPressed: () => Navigator.pop(dialogCtx),
                  icon: const Icon(Icons.close, size: 18),
                  label: Text(tr('Thoát')),
                ),
              ],
            ),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Scrollbar(
                  thumbVisibility: true,
                  controller: hBody,
                  child: SingleChildScrollView(
                    controller: hBody,
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: tableMinWidth),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFFFAFAFA),
                          border: Border(
                            bottom: BorderSide(color: Color(0xFFE4E4E7)),
                          ),
                        ),
                        child: _buildSummaryDesktopTable(
                          columnWidths: columnWidths,
                          rows: [headerRow],
                        ),
                      ),
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
                      child: Scrollbar(
                        thumbVisibility: true,
                        controller: hBody,
                        child: SingleChildScrollView(
                          controller: hBody,
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints:
                                BoxConstraints(minWidth: tableMinWidth),
                            child: _buildSummaryDesktopTable(
                              columnWidths: columnWidths,
                              rows: dataRows,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      top: BorderSide(color: Color(0xFFE4E4E7)),
                    ),
                  ),
                  child: Text(tr('${allSummaries.length} bản ghi · ${daySttMap.length} nhân viên'),
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
                    controller: hBody,
                    child: SingleChildScrollView(
                      controller: hBody,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(width: tableMinWidth, height: 1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(() {
      vBody.dispose();
      hBody.dispose();
    });
  }

  /// Pagination bar
  Widget _buildPaginationBar(
    int totalRows,
    int totalPages, {
    VoidCallback? onOpenFullscreen,
  }) {
    final startRow = totalRows == 0 ? 0 : _currentPage * _rowsPerPage + 1;
    final endRow = ((_currentPage + 1) * _rowsPerPage).clamp(0, totalRows);

    final recordsInfo = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.format_list_numbered,
              size: 13, color: Colors.green.shade600),
          const SizedBox(width: 4),
          Text(tr('Hiển thị $startRow-$endRow / $totalRows bản ghi'),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.green.shade700),
          ),
        ],
      ),
    );

    final rowsPerPage = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(tr('Số dòng:'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        const SizedBox(width: 6),
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFA),
            border: Border.all(color: const Color(0xFFE4E4E7)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _rowsPerPage,
              isDense: true,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).textTheme.bodyMedium?.color),
              items: [
                DropdownMenuItem(value: 20, child: Text(tr('20'))),
                DropdownMenuItem(value: 50, child: Text(tr('50'))),
                DropdownMenuItem(value: 100, child: Text(tr('100'))),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _rowsPerPage = v;
                    _currentPage = 0;
                  });
                }
              },
            ),
          ),
        ),
      ],
    );

    final pageNav = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPageNavBtn(Icons.first_page,
            _currentPage > 0 ? () => setState(() => _currentPage = 0) : null),
        _buildPageNavBtn(Icons.chevron_left,
            _currentPage > 0 ? () => setState(() => _currentPage--) : null),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            tr('${_currentPage + 1} / ${totalPages == 0 ? 1 : totalPages}'),
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
          ),
        ),
        _buildPageNavBtn(
            Icons.chevron_right,
            _currentPage < totalPages - 1
                ? () => setState(() => _currentPage++)
                : null),
        _buildPageNavBtn(
            Icons.last_page,
            _currentPage < totalPages - 1
                ? () => setState(() => _currentPage = totalPages - 1)
                : null),
      ],
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
        border: Border(top: BorderSide(color: Colors.grey.shade100)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 500) {
            return Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [recordsInfo, rowsPerPage],
                ),
                if (onOpenFullscreen != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: onOpenFullscreen,
                      icon: const Icon(Icons.fullscreen, size: 18),
                      label: Text(tr('Toàn màn hình')),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                pageNav,
              ],
            );
          }
          return Row(
            children: [
              recordsInfo,
              const SizedBox(width: 16),
              rowsPerPage,
              if (onOpenFullscreen != null) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: tr('Xem toàn màn hình'),
                  child: Material(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap: onOpenFullscreen,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.fullscreen,
                                size: 18, color: HrmPageChrome.chipMid),
                            SizedBox(width: 6),
                            Text(tr('Toàn màn hình'),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: HrmPageChrome.chipMid,
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
              pageNav,
            ],
          );
        },
      ),
    );
  }

  Widget _buildPageNavBtn(IconData icon, VoidCallback? onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: onPressed != null ? const Color(0xFFFAFAFA) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            child: Icon(icon,
                size: 18,
                color: onPressed != null
                    ? Colors.grey.shade700
                    : Colors.grey.shade300),
          ),
        ),
      ),
    );
  }

  Map<String, Map<String, dynamic>> _employeeInfoLookup() {
    final map = <String, Map<String, dynamic>>{};
    final list = widget.employeesList;
    if (list == null) return map;
    for (final emp in list) {
      void reg(String? key) {
        if (key != null && key.isNotEmpty) map[key] = emp;
      }
      reg(emp['employeeCode']?.toString());
      reg(emp['pin']?.toString());
      reg(emp['id']?.toString());
      reg(emp['applicationUserId']?.toString());
    }
    return map;
  }

  Map<String, dynamic>? _employeeInfoFor(_DailySummary s) {
    final lookup = _employeeInfoLookup();
    return lookup[s.employeeId] ??
        lookup[s.employeeCode] ??
        (s.pin != null ? lookup[s.pin!] : null);
  }

  String _employeeDisplayName(Map<String, dynamic>? info, _DailySummary s) {
    if (info == null) return s.employeeName;
    final fn = info['firstName']?.toString() ?? '';
    final ln = info['lastName']?.toString() ?? '';
    final full = '$fn $ln'.trim();
    return full.isNotEmpty ? full : s.employeeName;
  }

  List<String> _orderedUniqueEmployeeIds(List<_DailySummary> summaries) {
    final seen = <String>{};
    final order = <String>[];
    for (final s in summaries) {
      if (seen.add(s.employeeId)) order.add(s.employeeId);
    }
    return order;
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

  List<String> _excelDetailHeaders(int maxPunches, int maxShifts) {
    final headers = <String>['STT', 'Thứ', 'Ngày'];
    for (var i = 1; i <= maxPunches; i++) {
      headers.add('Lần $i');
    }
    for (var i = 1; i <= maxShifts; i++) {
      headers.add('Giờ ca $i');
    }
    headers.add('Tổng giờ');
    if (_showTravelColumns) headers.add('Đi đường');
    headers.addAll(['Số công', 'Giờ thập phân']);
    return headers;
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

  String _excelRef(int col, int row) =>
      '${_excelColLetter(col)}${row + 1}';

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

  excel_lib.CellStyle _excelLeftStyle({
    int fontSize = 11,
    bool italic = false,
  }) {
    return excel_lib.CellStyle(
      fontSize: fontSize,
      italic: italic,
      horizontalAlign: excel_lib.HorizontalAlign.Left,
      verticalAlign: excel_lib.VerticalAlign.Center,
    );
  }

  Map<String, Map<String, int>> _employeeDaySttMap(
      List<_DailySummary> allSummaries) {
    final map = <String, Map<String, int>>{};
    final counters = <String, int>{};
    for (final s in allSummaries) {
      final n = (counters[s.employeeId] ?? 0) + 1;
      counters[s.employeeId] = n;
      map.putIfAbsent(s.employeeId, () => {})[_dailySummaryRowKey(s)] = n;
    }
    return map;
  }

  List<String> _attendanceExportInfoLines(
    Map<String, dynamic>? empInfo,
    List<_DailySummary> empRows,
  ) {
    final displayName = _employeeDisplayName(empInfo, empRows.first);
    final empCode = empRows.first.employeeCode;
    final department = empInfo?['department']?.toString() ??
        empInfo?['departmentName']?.toString() ??
        '';
    final phone =
        empInfo?['phoneNumber']?.toString() ?? empInfo?['phone']?.toString() ?? '';
    final branch =
        empInfo?['branchName']?.toString() ?? empRows.first.branchName;
    final position = empInfo?['position']?.toString() ?? '';
    final pin = empInfo?['pin']?.toString() ?? empRows.first.pin ?? '';

    final lines = <String>[
      'Họ và tên: ${displayName.isNotEmpty ? displayName : '—'}',
      'Mã nhân viên: ${empCode.isNotEmpty ? empCode : '—'}',
    ];
    if (pin.isNotEmpty && pin != empCode) {
      lines.add('Mã chấm công (PIN): $pin');
    }
    lines.addAll([
      'Phòng ban: ${department.isNotEmpty ? department : '—'}',
      'Số điện thoại: ${phone.isNotEmpty ? phone : '—'}',
    ]);
    if (branch.isNotEmpty) lines.add('Chi nhánh: $branch');
    if (position.isNotEmpty) lines.add('Chức vụ: $position');
    return lines;
  }

  int _excelWriteEmployeeAttendanceBlock({
    required excel_lib.Sheet sheet,
    required int startRow,
    required List<_DailySummary> empRows,
    required _EmployeePeriodTotals totals,
    required Map<String, dynamic>? empInfo,
    required int maxPunches,
    required int maxShifts,
    required DateTimeRange range,
    required int colCount,
    required bool isLastEmployee,
  }) {
    final titleStyle = ExcelReportBuilder.titleStyle();
    final infoStyle = _excelLeftStyle();
    final headerStyle = ExcelReportBuilder.headerStyle();
    final dataStyle = _excelCenterStyle();
    final numStyle =
        _excelCenterStyle(numberFormat: excel_lib.NumFormat.standard_2);
    final totalStyle = _excelCenterStyle(
      bold: true,
      backgroundHex: '#EFF6FF',
    );
    final sigTitleStyle = _excelCenterStyle(bold: true);
    final sigHintStyle = _excelCenterStyle(fontSize: 10, italic: true);

    final lastCol = colCount - 1;
    final punchStartCol = 3;
    final shiftStartCol = punchStartCol + maxPunches;
    final totalHoursCol = shiftStartCol + maxShifts;
    final travelCol = _showTravelColumns ? totalHoursCol + 1 : -1;
    final workCountCol = totalHoursCol + (_showTravelColumns ? 2 : 1);
    final decimalHoursCol = workCountCol + 1;

    var row = startRow;

    _excelMergedText(
      sheet,
      row: row,
      colStart: 0,
      colEnd: lastCol,
      text: tr('BẢNG CHẤM CÔNG CHI TIẾT'),
      style: titleStyle,
    );
    row++;

    _excelMergedText(
      sheet,
      row: row,
      colStart: 0,
      colEnd: lastCol,
      text:
          tr('Từ ngày ${DateFormat('dd/MM/yyyy').format(range.start)} đến ngày ${DateFormat('dd/MM/yyyy').format(range.end)}'),
      style: _excelCenterStyle(fontSize: 12),
    );
    row += 2;

    for (final line in _attendanceExportInfoLines(empInfo, empRows)) {
      _excelMergedText(
        sheet,
        row: row,
        colStart: 0,
        colEnd: lastCol,
        text: tr(line),
        style: infoStyle,
      );
      row++;
    }
    row++;

    final headerRow = row;
    final headers = _excelDetailHeaders(maxPunches, maxShifts);
    ExcelReportBuilder.applyHeaderRow(sheet, headerRow, headers,
        style: headerStyle);
    row++;

    final firstDataRow = row;
    for (var i = 0; i < empRows.length; i++) {
      final s = empRows[i];
      var col = 0;
      _excelSetCell(
        sheet,
        row,
        col++,
        excel_lib.IntCellValue(i + 1),
        style: dataStyle,
      );
      _excelSetCell(
        sheet,
        row,
        col++,
        excel_lib.TextCellValue(_getDayOfWeekVN(s.date.weekday)),
        style: dataStyle,
      );
      _excelSetCell(
        sheet,
        row,
        col++,
        excel_lib.TextCellValue(DateFormat('dd/MM/yyyy').format(s.date)),
        style: dataStyle,
      );

      for (var p = 1; p <= maxPunches; p++) {
        final punch = s.getPunch(p);
        _excelSetCell(
          sheet,
          row,
          col++,
          excel_lib.TextCellValue(
              punch != null ? DateFormat('HH:mm').format(punch) : ''),
          style: dataStyle,
        );
      }

      for (var sh = 1; sh <= maxShifts; sh++) {
        final h = s.getShiftHours(sh);
        _excelSetCell(
          sheet,
          row,
          col++,
          excel_lib.DoubleCellValue(double.parse(h.toStringAsFixed(2))),
          style: numStyle,
        );
      }

      final shiftRange =
          '${_excelRef(shiftStartCol, row)}:${_excelRef(shiftStartCol + maxShifts - 1, row)}';
      _excelSetCell(
        sheet,
        row,
        totalHoursCol,
        excel_lib.FormulaCellValue('=SUM($shiftRange)'),
        style: numStyle,
      );
      final travelH = _travelHoursForSummary(s);
      if (_showTravelColumns) {
        _excelSetCell(
          sheet,
          row,
          travelCol,
          travelH > 0
              ? excel_lib.DoubleCellValue(
                  double.parse(travelH.toStringAsFixed(2)))
              : excel_lib.TextCellValue(''),
          style: numStyle,
        );
      }
      _excelSetCell(
        sheet,
        row,
        workCountCol,
        excel_lib.DoubleCellValue(
            double.parse(s.workCount.toStringAsFixed(2))),
        style: numStyle,
      );
      _excelSetCell(
        sheet,
        row,
        decimalHoursCol,
        excel_lib.FormulaCellValue('=${_excelRef(totalHoursCol, row)}'),
        style: numStyle,
      );
      row++;
    }

    final lastDataRow = row - 1;
    final totalRow = row;

    _excelSetCell(sheet, totalRow, 0, excel_lib.TextCellValue(''),
        style: totalStyle);
    _excelSetCell(sheet, totalRow, 1, excel_lib.TextCellValue('TỔNG CỘNG'),
        style: totalStyle);

    if (empRows.isNotEmpty) {
      final punchCol = _excelRef(punchStartCol, firstDataRow);
      final punchEnd = _excelRef(punchStartCol, lastDataRow);
      _excelSetCell(
        sheet,
        totalRow,
        2,
        excel_lib.FormulaCellValue(
            '=COUNTIF($punchCol:$punchEnd,"<>")&" ngày"'),
        style: totalStyle,
      );

      for (var sh = 0; sh < maxShifts; sh++) {
        final c = shiftStartCol + sh;
        final refStart = _excelRef(c, firstDataRow);
        final refEnd = _excelRef(c, lastDataRow);
        _excelSetCell(
          sheet,
          totalRow,
          c,
          excel_lib.FormulaCellValue('=SUM($refStart:$refEnd)'),
          style: totalStyle,
        );
      }

      final thStart = _excelRef(totalHoursCol, firstDataRow);
      final thEnd = _excelRef(totalHoursCol, lastDataRow);
      _excelSetCell(
        sheet,
        totalRow,
        totalHoursCol,
        excel_lib.FormulaCellValue('=SUM($thStart:$thEnd)'),
        style: totalStyle,
      );

      if (_showTravelColumns) {
        final travelStart = _excelRef(travelCol, firstDataRow);
        final travelEnd = _excelRef(travelCol, lastDataRow);
        _excelSetCell(
          sheet,
          totalRow,
          travelCol,
          excel_lib.FormulaCellValue('=SUM($travelStart:$travelEnd)'),
          style: totalStyle,
        );
      }

      final wcStart = _excelRef(workCountCol, firstDataRow);
      final wcEnd = _excelRef(workCountCol, lastDataRow);
      _excelSetCell(
        sheet,
        totalRow,
        workCountCol,
        excel_lib.FormulaCellValue('=SUM($wcStart:$wcEnd)'),
        style: totalStyle,
      );

      final decStart = _excelRef(decimalHoursCol, firstDataRow);
      final decEnd = _excelRef(decimalHoursCol, lastDataRow);
      _excelSetCell(
        sheet,
        totalRow,
        decimalHoursCol,
        excel_lib.FormulaCellValue('=SUM($decStart:$decEnd)'),
        style: totalStyle,
      );
    } else {
      _excelSetCell(sheet, totalRow, 2,
          excel_lib.TextCellValue('${totals.presentDays} ngày'),
          style: totalStyle);
    }

    for (var p = 0; p < maxPunches; p++) {
      _excelSetCell(sheet, totalRow, punchStartCol + p,
          excel_lib.TextCellValue(''), style: totalStyle);
    }

    row = totalRow + 2;

    final part = (colCount / 3).floor().clamp(1, colCount);
    final sig1End = part - 1;
    final sig2Start = part;
    final sig2End = (part * 2 - 1).clamp(sig2Start, lastCol);
    final sig3Start = part * 2;
    _excelMergedText(sheet,
        row: row,
        colStart: 0,
        colEnd: sig1End,
        text: tr('Người lập'),
        style: sigTitleStyle);
    _excelMergedText(sheet,
        row: row,
        colStart: sig2Start,
        colEnd: sig2End,
        text: tr('Nhân viên'),
        style: sigTitleStyle);
    _excelMergedText(sheet,
        row: row,
        colStart: sig3Start,
        colEnd: lastCol,
        text: tr('Giám đốc'),
        style: sigTitleStyle);
    row += 4;
    _excelMergedText(sheet,
        row: row,
        colStart: 0,
        colEnd: sig1End,
        text: tr('(Ký, ghi rõ họ tên)'),
        style: sigHintStyle);
    _excelMergedText(sheet,
        row: row,
        colStart: sig2Start,
        colEnd: sig2End,
        text: tr('(Ký, ghi rõ họ tên)'),
        style: sigHintStyle);
    _excelMergedText(sheet,
        row: row,
        colStart: sig3Start,
        colEnd: lastCol,
        text: tr('(Ký, ghi rõ họ tên)'),
        style: sigHintStyle);
    row += 2;

    if (!isLastEmployee) row += 3;

    return row;
  }

  String? _excelFilterDescription() {
    final parts = <String>[];
    if (_selectedEmployeeIds.isNotEmpty) {
      parts.add('${_selectedEmployeeIds.length} nhân viên được chọn');
    }
    if (_shiftFilter == 'missing') {
      parts.add('Thiếu chấm công');
    } else if (_shiftFilter == 'complete') {
      parts.add('Chấm công đủ cặp');
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Export to Excel — mỗi nhân viên một khối: tiêu đề, thông tin, bảng chi tiết, ký.
  Future<void> exportToExcel() async {
    final summaries = _dailySummaryData;
    if (summaries.isEmpty || _isExporting) return;
    setState(() => _isExporting = true);

    try {
      final cols = _tableColumnLimits(summaries);
      final maxPunches = cols.maxPunches;
      final maxShifts = cols.maxShifts;
      final colCount = _excelDetailHeaders(maxPunches, maxShifts).length;
      final range = _selectedDateRange;

      final excelFile =
          ExcelReportBuilder.createWorkbook(sheetName: 'Chấm công');
      final sheet = excelFile['Chấm công'];

      sheet.setColumnWidth(0, 5);
      sheet.setColumnWidth(1, 10);
      sheet.setColumnWidth(2, 12);
      for (var i = 3; i < colCount; i++) {
        sheet.setColumnWidth(i, i < 3 + maxPunches ? 9 : 11);
      }

      final empTotals = _employeeTotalsFrom(summaries);
      final byEmployee = <String, List<_DailySummary>>{};
      for (final s in summaries) {
        byEmployee.putIfAbsent(s.employeeId, () => []).add(s);
      }
      final orderedIds = _orderedUniqueEmployeeIds(summaries);

      var row = 0;
      final filterDesc = _excelFilterDescription();
      if (filterDesc != null) {
        _excelMergedText(
          sheet,
          row: row,
          colStart: 0,
          colEnd: colCount - 1,
          text: tr('Bộ lọc: $filterDesc'),
          style: _excelCenterStyle(fontSize: 10, italic: true),
        );
        row += 2;
      }

      for (var i = 0; i < orderedIds.length; i++) {
        final empId = orderedIds[i];
        final empRows = byEmployee[empId] ?? [];
        if (empRows.isEmpty) continue;
        final totals = empTotals[empId];
        if (totals == null) continue;
        row = _excelWriteEmployeeAttendanceBlock(
          sheet: sheet,
          startRow: row,
          empRows: empRows,
          totals: totals,
          empInfo: _employeeInfoFor(empRows.first),
          maxPunches: maxPunches,
          maxShifts: maxShifts,
          range: range,
          colCount: colCount,
          isLastEmployee: i == orderedIds.length - 1,
        );
      }

      final bytes = excelFile.encode();
      if (bytes != null) {
        final fileName =
            'Bang_cham_cong_chi_tiet_${DateFormat('ddMMyyyy').format(range.start)}_${DateFormat('ddMMyyyy').format(range.end)}.xlsx';
        await file_saver.saveAndOpenFileBytes(bytes, fileName,
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        if (mounted) {
          NotificationOverlayManager().showSuccess(
              title: 'Xuất Excel',
              message: tr('Đã lưu ${orderedIds.length} nhân viên vào Tải về/SBOX HRM: $fileName'));
        }
      }
    } catch (e) {
      if (mounted) {
        NotificationOverlayManager()
            .showError(title: 'Lỗi', message: tr('Không thể xuất Excel: $e'));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  List<String> _pngDetailRowCells(_DailySummary s, int stt, int maxPunches,
      int maxShifts) {
    final cells = <String>[
      '$stt',
      _getDayOfWeekVN(s.date.weekday),
      DateFormat('dd/MM/yyyy').format(s.date),
    ];
    for (var p = 1; p <= maxPunches; p++) {
      final punch = s.getPunch(p);
      cells.add(punch != null ? DateFormat('HH:mm').format(punch) : '');
    }
    for (var sh = 1; sh <= maxShifts; sh++) {
      final h = s.getShiftHours(sh);
      cells.add(h > 0 ? h.toStringAsFixed(2) : '');
    }
    cells.add(s.totalHours > 0 ? s.totalHours.toStringAsFixed(2) : '');
    if (_showTravelColumns) {
      cells.add(_travelHoursForSummary(s) > 0
          ? _travelHoursForSummary(s).toStringAsFixed(2)
          : '');
    }
    cells.add(s.workCount > 0 ? s.workCount.toStringAsFixed(2) : '');
    cells.add(
        s.totalHours > 0 ? s.totalHours.toStringAsFixed(2) : '');
    return cells;
  }

  List<String> _pngTotalRowCells(
      _EmployeePeriodTotals totals, int maxPunches, int maxShifts) {
    final cells = <String>[
      '',
      'TỔNG CỘNG',
      '${totals.presentDays} ngày',
    ];
    for (var p = 0; p < maxPunches; p++) {
      cells.add('');
    }
    for (var sh = 1; sh <= maxShifts; sh++) {
      final h = totals.shiftAt(sh);
      cells.add(h > 0 ? h.toStringAsFixed(2) : '');
    }
    cells.addAll([
      totals.totalHours > 0 ? totals.totalHours.toStringAsFixed(2) : '',
      if (_showTravelColumns)
        _travelHoursTotalForEmployee(
                    employeeId: totals.employeeId,
                    employeeCode: totals.employeeCode,
                  ) >
                0
            ? _travelHoursTotalForEmployee(
                    employeeId: totals.employeeId,
                    employeeCode: totals.employeeCode)
                .toStringAsFixed(2)
            : '',
      totals.totalWork > 0 ? totals.totalWork.toStringAsFixed(2) : '',
      totals.totalHours > 0 ? totals.totalHours.toStringAsFixed(2) : '',
    ]);
    return cells;
  }

  double _pngEstimateColWidths(
    List<String> headers,
    List<List<String>> allRows,
    double minW,
    double maxW,
  ) {
    final widths = <double>[];
    for (var c = 0; c < headers.length; c++) {
      var w = headers[c].length * 8.0 + 20;
      for (final row in allRows) {
        if (c < row.length) {
          final cw = row[c].length * 7.0 + 20;
          if (cw > w) w = cw;
        }
      }
      widths.add(w.clamp(minW, maxW));
    }
    return widths.fold(0.0, (sum, w) => sum + w);
  }

  double _pngEmployeeBlockHeight({
    required int infoLineCount,
    required int dataRowCount,
    required bool addSpacer,
  }) {
    const titleH = 34.0;
    const periodH = 26.0;
    const infoH = 22.0;
    const gap = 10.0;
    const headerH = 34.0;
    const rowH = 28.0;
    const totalH = 30.0;
    const sigBlockH = 88.0;
    final spacerH = addSpacer ? 24.0 : 0.0;
    return titleH +
        periodH +
        gap +
        infoLineCount * infoH +
        gap +
        headerH +
        dataRowCount * rowH +
        totalH +
        gap +
        sigBlockH +
        spacerH;
  }

  void _pngDrawCenteredText(
    dynamic ctx,
    String text,
    double cx,
    double cy, {
    required String color,
    required String font,
  }) {
    ctx.fillStyle = color;
    ctx.font = font;
    ctx.textAlign = 'center';
    ctx.fillText(text, cx, cy);
    ctx.textAlign = 'left';
  }

  void _pngDrawAttendanceExport(
    dynamic ctx, {
    required double width,
    required double height,
    required List<_DailySummary> summaries,
    required Map<String, _EmployeePeriodTotals> empTotals,
    required List<String> orderedIds,
    required Map<String, List<_DailySummary>> byEmployee,
    required int maxPunches,
    required int maxShifts,
    required DateTimeRange range,
    String? filterDesc,
  }) {
    const rowH = 28.0;
    const headerH = 34.0;
    const infoH = 22.0;
    const titleH = 34.0;
    const periodH = 26.0;
    const gap = 10.0;
    const sigBlockH = 88.0;
    const pad = 12.0;

    final headers = _excelDetailHeaders(maxPunches, maxShifts);
    final allSampleRows = <List<String>>[];
    for (final id in orderedIds) {
      final empRows = byEmployee[id] ?? [];
      for (var i = 0; i < empRows.length; i++) {
        allSampleRows
            .add(_pngDetailRowCells(empRows[i], i + 1, maxPunches, maxShifts));
      }
      final totals = empTotals[id];
      if (totals != null) {
        allSampleRows.add(_pngTotalRowCells(totals, maxPunches, maxShifts));
      }
    }
    final tableWidth =
        _pngEstimateColWidths(headers, allSampleRows, 48, 120).clamp(600, 1400);
    final colWidths = <double>[];
    for (var c = 0; c < headers.length; c++) {
      var w = headers[c].length * 8.0 + 20;
      for (final row in allSampleRows) {
        if (c < row.length) {
          final cw = row[c].length * 7.0 + 20;
          if (cw > w) w = cw;
        }
      }
      colWidths.add(w.clamp(48, 120));
    }
    final scale = tableWidth / colWidths.fold(0.0, (s, w) => s + w);
    for (var i = 0; i < colWidths.length; i++) {
      colWidths[i] *= scale;
    }

    ctx.fillStyle = '#FFFFFF';
    ctx.fillRect(0, 0, width, height);

    var y = pad;
    if (filterDesc != null) {
      _pngDrawCenteredText(ctx, 'Bộ lọc: $filterDesc', width / 2, y + 12,
          color: '#71717A', font: 'italic 11px Arial, sans-serif');
      y += 24;
    }

    final tableLeft = (width - tableWidth) / 2;

    for (var ei = 0; ei < orderedIds.length; ei++) {
      final empId = orderedIds[ei];
      final empRows = byEmployee[empId] ?? [];
      final totals = empTotals[empId];
      if (empRows.isEmpty || totals == null) continue;
      final empInfo = _employeeInfoFor(empRows.first);
      final infoLines = _attendanceExportInfoLines(empInfo, empRows);

      _pngDrawCenteredText(
          ctx, 'BẢNG CHẤM CÔNG CHI TIẾT', width / 2, y + 20,
          color: '#0F172A', font: 'bold 16px Arial, sans-serif');
      y += titleH;

      _pngDrawCenteredText(
        ctx,
        'Từ ngày ${DateFormat('dd/MM/yyyy').format(range.start)} đến ngày ${DateFormat('dd/MM/yyyy').format(range.end)}',
        width / 2,
        y + 16,
        color: '#334155',
        font: '12px Arial, sans-serif',
      );
      y += periodH + gap;

      for (final line in infoLines) {
        ctx.fillStyle = '#334155';
        ctx.font = '11px Arial, sans-serif';
        ctx.textAlign = 'left';
        ctx.fillText(line, tableLeft + 8, y + 14);
        ctx.textAlign = 'left';
        y += infoH;
      }
      y += gap;

      final tableTop = y;
      ctx.fillStyle = '#6366F1';
      ctx.fillRect(tableLeft, tableTop, tableWidth, headerH);
      var x = tableLeft;
      for (var c = 0; c < headers.length; c++) {
        _pngDrawCenteredText(
          ctx,
          headers[c],
          x + colWidths[c] / 2,
          tableTop + headerH / 2 + 5,
          color: '#FFFFFF',
          font: 'bold 11px Arial, sans-serif',
        );
        x += colWidths[c];
      }
      y += headerH;

      for (var ri = 0; ri < empRows.length; ri++) {
        final cells =
            _pngDetailRowCells(empRows[ri], ri + 1, maxPunches, maxShifts);
        if (ri.isOdd) {
          ctx.fillStyle = '#F8FAFC';
          ctx.fillRect(tableLeft, y, tableWidth, rowH);
        }
        x = tableLeft;
        for (var c = 0; c < cells.length; c++) {
          final punchCol = c >= 3 && c < 3 + maxPunches;
          String color = '#334155';
          if (punchCol && cells[c].isNotEmpty) {
            color = (c - 2).isOdd ? '#059669' : '#DC2626';
          } else if (c >= 3 + maxPunches && c < 3 + maxPunches + maxShifts) {
            color = cells[c].isNotEmpty ? '#0D9488' : '#334155';
          } else if (c == cells.length - 3 && cells[c].isNotEmpty) {
            color = '#16A34A';
          } else if (c >= cells.length - 2 && cells[c].isNotEmpty) {
            color = '#1D4ED8';
          }
          _pngDrawCenteredText(
            ctx,
            cells[c],
            x + colWidths[c] / 2,
            y + rowH / 2 + 5,
            color: color,
            font: '11px Arial, sans-serif',
          );
          x += colWidths[c];
        }
        ctx.strokeStyle = '#E2E8F0';
        ctx.beginPath();
        ctx.moveTo(tableLeft, y + rowH);
        ctx.lineTo(tableLeft + tableWidth, y + rowH);
        ctx.stroke();
        y += rowH;
      }

      final totalCells = _pngTotalRowCells(totals, maxPunches, maxShifts);
      ctx.fillStyle = '#EFF6FF';
      ctx.fillRect(tableLeft, y, tableWidth, rowH + 2);
      x = tableLeft;
      for (var c = 0; c < totalCells.length; c++) {
        _pngDrawCenteredText(
          ctx,
          totalCells[c],
          x + colWidths[c] / 2,
          y + rowH / 2 + 5,
          color: '#1D4ED8',
          font: 'bold 11px Arial, sans-serif',
        );
        x += colWidths[c];
      }
      ctx.strokeStyle = '#93C5FD';
      ctx.beginPath();
      ctx.moveTo(tableLeft, y + rowH);
      ctx.lineTo(tableLeft + tableWidth, y + rowH);
      ctx.stroke();
      y += rowH + gap;

      final sigW = tableWidth / 3;
      final sigLabels = ['Người lập', 'Nhân viên', 'Giám đốc'];
      for (var si = 0; si < 3; si++) {
        final cx = tableLeft + sigW * si + sigW / 2;
        _pngDrawCenteredText(ctx, sigLabels[si], cx, y + 14,
            color: '#0F172A', font: 'bold 11px Arial, sans-serif');
      }
      y += 52;
      for (var si = 0; si < 3; si++) {
        final cx = tableLeft + sigW * si + sigW / 2;
        _pngDrawCenteredText(ctx, '(Ký, ghi rõ họ tên)', cx, y + 12,
            color: '#71717A', font: 'italic 10px Arial, sans-serif');
      }
      y += sigBlockH - 52;

      ctx.strokeStyle = '#CBD5E1';
      ctx.lineWidth = 1;
      ctx.strokeRect(tableLeft, tableTop, tableWidth, y - tableTop);

      if (ei < orderedIds.length - 1) y += 24;
    }
  }

  /// Export to PNG — cùng bố cục Excel: từng nhân viên, thông tin, bảng, ký.
  Future<void> exportToPng() async {
    final summaries = _dailySummaryData;
    if (summaries.isEmpty) {
      NotificationOverlayManager().showWarning(
          title: 'Không có dữ liệu', message: tr('Không có dữ liệu để xuất'));
      return;
    }

    setState(() => _isExporting = true);

    try {
      final cols = _tableColumnLimits(summaries);
      final maxPunches = cols.maxPunches;
      final maxShifts = cols.maxShifts;
      final range = _selectedDateRange;
      final empTotals = _employeeTotalsFrom(summaries);
      final byEmployee = <String, List<_DailySummary>>{};
      for (final s in summaries) {
        byEmployee.putIfAbsent(s.employeeId, () => []).add(s);
      }
      final orderedIds = _orderedUniqueEmployeeIds(summaries);
      final filterDesc = _excelFilterDescription();

      var totalHeight = 24.0;
      if (filterDesc != null) totalHeight += 24;
      for (var i = 0; i < orderedIds.length; i++) {
        final empRows = byEmployee[orderedIds[i]] ?? [];
        if (empRows.isEmpty) continue;
        final infoCount = _attendanceExportInfoLines(
                _employeeInfoFor(empRows.first), empRows)
            .length;
        totalHeight += _pngEmployeeBlockHeight(
          infoLineCount: infoCount,
          dataRowCount: empRows.length,
          addSpacer: i < orderedIds.length - 1,
        );
      }
      totalHeight += 24;

      const totalWidth = 1100.0;
      void drawFn(dynamic ctx) => _pngDrawAttendanceExport(
            ctx,
            width: totalWidth,
            height: totalHeight,
            summaries: summaries,
            empTotals: empTotals,
            orderedIds: orderedIds,
            byEmployee: byEmployee,
            maxPunches: maxPunches,
            maxShifts: maxShifts,
            range: range,
            filterDesc: filterDesc,
          );

      final rangeLabel =
          '${DateFormat('ddMMyyyy').format(range.start)}_${DateFormat('ddMMyyyy').format(range.end)}';
      final fileName = 'Bang_cham_cong_chi_tiet_$rangeLabel.png';

      final dataUrl = web_canvas.renderToPngDataUrl(
        width: totalWidth.toInt(),
        height: totalHeight.toInt(),
        draw: drawFn,
      );

      if (dataUrl != null) {
        await file_saver.saveAndOpenDataUrl(dataUrl, fileName);
        if (mounted) {
          NotificationOverlayManager().showSuccess(
              title: 'Xuất PNG',
              message: tr('Đã lưu ${orderedIds.length} nhân viên vào Ảnh/SBOX HRM: $fileName'));
        }
      } else {
        final pngBytes = await web_canvas.renderToPngBytes(
          width: totalWidth.toInt(),
          height: totalHeight.toInt(),
          draw: drawFn,
        );
        if (pngBytes != null && mounted) {
          await file_saver.saveAndOpenFileBytes(
              pngBytes, fileName, 'image/png');
          NotificationOverlayManager().showSuccess(
              title: 'Xuất PNG',
              message: tr('Đã lưu ${orderedIds.length} nhân viên vào Ảnh/SBOX HRM: $fileName'));
        } else if (mounted) {
          NotificationOverlayManager()
              .showError(title: 'Lỗi', message: tr('Không thể xuất PNG'));
        }
      }
    } catch (e) {
      if (mounted) {
        NotificationOverlayManager()
            .showError(title: 'Lỗi', message: tr('Lỗi xuất PNG: $e'));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// Employee multi-select filter button
  Widget _buildEmployeeFilter() {
    final employees = _allEmployees;
    final selectedCount = _selectedEmployeeIds.length;

    return InkWell(
      onTap: () => _showEmployeeSelectionDialog(employees),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 36,
        constraints: const BoxConstraints(minWidth: 160, maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selectedCount > 0
                ? Theme.of(context).primaryColor
                : const Color(0xFFE4E4E7),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people,
                size: 14,
                color: selectedCount > 0
                    ? Theme.of(context).primaryColor
                    : Colors.grey[500]),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                tr(selectedCount == 0
                    ? 'Tất cả nhân viên (${employees.length})'
                    : '$selectedCount nhân viên đã chọn'),
                style: TextStyle(
                  fontSize: 12,
                  color: selectedCount > 0
                      ? Theme.of(context).primaryColor
                      : Colors.grey[600],
                  fontWeight:
                      selectedCount > 0 ? FontWeight.w600 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (selectedCount > 0) ...[
              const SizedBox(width: 4),
              InkWell(
                onTap: () => setState(() {
                  _selectedEmployeeIds = {};
                  _currentPage = 0;
                }),
                child: Icon(Icons.close, size: 14, color: Colors.grey[500]),
              ),
            ],
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey[500]),
          ],
        ),
      ),
    );
  }

  /// Show employee multi-select dialog
  void _showEmployeeSelectionDialog(List<_EmployeeOption> employees) {
    final tempSelected = Set<String>.from(_selectedEmployeeIds);
    String searchText = '';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final filtered = searchText.isEmpty
                ? employees
                : employees
                    .where((e) =>
                        e.name
                            .toLowerCase()
                            .contains(searchText.toLowerCase()) ||
                        e.code.toLowerCase().contains(searchText.toLowerCase()))
                    .toList();

            return ScrollableAlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.people, color: Colors.blue, size: 22),
                  const SizedBox(width: 8),
                  Text(tr('Chọn nhân viên'),
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      if (tempSelected.length == employees.length) {
                        setDialogState(() => tempSelected.clear());
                      } else {
                        setDialogState(() =>
                            tempSelected.addAll(employees.map((e) => e.id)));
                      }
                    },
                    child: Text(
                      tr(tempSelected.length == employees.length
                          ? 'Bỏ chọn tất cả'
                          : 'Chọn tất cả'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              content: SizedBox(
                width: math
                    .min(380, MediaQuery.of(context).size.width - 32)
                    .toDouble(),
                height: 400,
                child: Column(
                  children: [
                    // Search box
                    TextField(
                      decoration: InputDecoration(
                        hintText: tr('Tìm nhân viên...'),
                        hintStyle: const TextStyle(fontSize: 13),
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      style: const TextStyle(fontSize: 13),
                      onChanged: (v) => setDialogState(() => searchText = v),
                    ),
                    const SizedBox(height: 8),
                    // Info bar
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Text(tr('Đã chọn: ${tempSelected.length}/${employees.length}'),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Employee list
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (ctx, index) {
                          final emp = filtered[index];
                          final isSelected = tempSelected.contains(emp.id);
                          return InkWell(
                            onTap: () {
                              setDialogState(() {
                                if (isSelected) {
                                  tempSelected.remove(emp.id);
                                } else {
                                  tempSelected.add(emp.id);
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Theme.of(context)
                                        .primaryColor
                                        .withValues(alpha: 0.08)
                                    : null,
                                border: Border(
                                    bottom: BorderSide(
                                        color: Colors.grey.shade200)),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected
                                        ? Icons.check_box
                                        : Icons.check_box_outline_blank,
                                    size: 20,
                                    color: isSelected
                                        ? Theme.of(context).primaryColor
                                        : Colors.grey,
                                  ),
                                  const SizedBox(width: 10),
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: Colors.blue.shade100,
                                    child: Text(
                                        tr(emp.name.isNotEmpty
                                            ? emp.name[0].toUpperCase()
                                            : '?'),
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue.shade700)),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(tr(emp.name),
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500)),
                                        Text(tr(emp.code),
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade600)),
                                      ],
                                    ),
                                  ),
                                ],
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
                  child: Text(tr('Hủy')),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _selectedEmployeeIds = tempSelected;
                      _invalidateDisplayDerivedCache();
                      _currentPage = 0;
                    });
                    Navigator.pop(ctx);
                  },
                  child: Text(tr('Áp dụng')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ─── Bảng dọc (mobile — nhân viên / chạm tên NV) ─────────────────────────

  ({
    AttendanceLeaveLookup leaveLookup,
    Map<String, String> empUserIdMap,
    Map<String, String> hrEmpIdMap,
  }) _verticalSummaryLeaveContext() {
    final leaveLookup = AttendanceLeaveLookup.fromLeaves(
      widget.approvedLeaves,
      employeesList: widget.employeesList,
      includePending: true,
    );
    final empUserIdMap = <String, String>{};
    final hrEmpIdMap = <String, String>{};
    if (widget.employeesList != null) {
      for (final e in widget.employeesList!) {
        final code = e['employeeCode']?.toString() ?? '';
        final appId = e['applicationUserId']?.toString() ?? '';
        final hrId = e['id']?.toString() ?? '';
        if (code.isNotEmpty) {
          if (appId.isNotEmpty) empUserIdMap[code] = appId;
          if (hrId.isNotEmpty) hrEmpIdMap[code] = hrId;
        }
      }
    }
    return (
      leaveLookup: leaveLookup,
      empUserIdMap: empUserIdMap,
      hrEmpIdMap: hrEmpIdMap,
    );
  }

  String _verticalSummaryPunchText(_DailySummary s, int maxShifts) {
    final parts = <String>[];
    for (var si = 0; si < maxShifts; si++) {
      final pin = s.getPunch(si * 2 + 1);
      final pout = s.getPunch(si * 2 + 2);
      if (pin == null && pout == null) continue;
      final inStr = pin != null ? DateFormat('HH:mm').format(pin) : '—';
      final outStr = pout != null ? DateFormat('HH:mm').format(pout) : '—';
      parts.add(maxShifts > 1 ? 'C${si + 1} $inStr·$outStr' : '$inStr·$outStr');
    }
    return parts.isEmpty ? '—' : parts.join('\n');
  }

  String _verticalWorkCountLabel(double workCount) {
    if (workCount <= 0) return '—';
    return workCount % 1 == 0
        ? workCount.toInt().toString()
        : workCount.toStringAsFixed(1);
  }

  Widget _verticalSummaryAbsenceCell({
    required DateTime date,
    required String empId,
    required String empName,
    required String empCode,
    required AttendanceLeaveLookup leaveLookup,
    required Map<String, String> empUserIdMap,
    required Map<String, String> hrEmpIdMap,
  }) {
    final kind = leaveLookup.classify(
      day: date,
      employeeCode: empCode,
      employeeUserId: empUserIdMap[empCode] ?? empUserIdMap[empId],
      hrEmployeeId: hrEmpIdMap[empCode] ?? hrEmpIdMap[empId],
      displayEmployeeId: empId,
      isHoliday: _getHolidayRate(date, empCode) != null,
      isWeeklyOff: _isWeeklyOffDay(date, empCode),
    );
    final label = switch (kind) {
      AbsenceCellKind.holiday => ('Lễ', HrmPageChrome.chipMid),
      AbsenceCellKind.weeklyOff => ('Nghỉ', HrmPageChrome.chipSoft),
      AbsenceCellKind.approvedLeave => ('Phép', HrmPageChrome.chipLight),
      AbsenceCellKind.pendingLeave => ('Chờ phép', HrmPageChrome.chipDark),
      AbsenceCellKind.unpaidAbsent => ('Vắng', const Color(0xFFEF4444)),
    };
    return mobileAttendanceAbsenceLabel(
      label.$1,
      color: label.$2,
      onTap: kind == AbsenceCellKind.unpaidAbsent
          ? () {
              AbsenceDayActions.showForAbsentDay(
                context: context,
                api: ApiService(),
                employeeName: empName,
                employeeCode: empCode,
                displayEmployeeId: empId,
                applicationUserId:
                    empUserIdMap[empCode] ?? empUserIdMap[empId],
                hrEmployeeId: hrEmpIdMap[empCode] ?? hrEmpIdMap[empId],
                date: date,
                employees: widget.employeesList,
                onCompleted: _notifyDataChanged,
                onAddWork: widget.allowCorrection
                    ? () {
                        final summary = _placeholderSummaryForAbsent(
                          empId: empId,
                          empName: empName,
                          empCode: empCode,
                          date: date,
                        );
                        _showAddPunchDialog(summary, 1, true, context);
                      }
                    : null,
              );
            }
          : null,
    );
  }

  MobileAttendanceVerticalTable _buildVerticalSummaryTable({
    required String empId,
    required String empName,
    required String empCode,
    required List<_DailySummary> summaries,
    required int maxPunches,
    required int maxShifts,
    String? title,
  }) {
    final dates = attendanceDaysInRange(_selectedDateRange);
    final lookup = <String, _DailySummary>{};
    for (final s in summaries) {
      if (s.employeeId == empId) {
        lookup[DateFormat('yyyy-MM-dd').format(s.date)] = s;
      }
    }
    final leaveCtx = _verticalSummaryLeaveContext();
    final today = DateTime.now();

    final rows = dates.map((date) {
      final summary = lookup[DateFormat('yyyy-MM-dd').format(date)];
      final isToday = date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      return MobileAttendanceVerticalRow(
        day: attendanceVerticalDateShort(date),
        weekday: attendanceVerticalWeekdayShort(date),
        attendance: summary == null
            ? _verticalSummaryAbsenceCell(
                date: date,
                empId: empId,
                empName: empName,
                empCode: empCode,
                leaveLookup: leaveCtx.leaveLookup,
                empUserIdMap: leaveCtx.empUserIdMap,
                hrEmpIdMap: leaveCtx.hrEmpIdMap,
              )
            : mobileAttendancePunchText(
                _verticalSummaryPunchText(summary, maxShifts),
              ),
        shiftHours: [
          for (var i = 1; i <= maxShifts; i++)
            summary != null && summary.getShiftHours(i) > 0
                ? _formatHours(summary.getShiftHours(i))
                : '—',
        ],
        totalHours: summary != null && summary.totalHours > 0
            ? _formatHours(summary.totalHours)
            : '—',
        travelHours: summary != null
            ? (_travelHoursForSummary(summary) > 0
                ? _formatHours(_travelHoursForSummary(summary))
                : '—')
            : '—',
        totalWork: summary != null
            ? _verticalWorkCountLabel(summary.workCount)
            : '—',
        isToday: isToday,
        onTap: summary != null
            ? () => _showRowDetailDialog(summary, maxPunches, maxShifts)
            : null,
      );
    }).toList();

    var totalHours = 0.0;
    var totalTravel = 0.0;
    var totalWork = 0.0;
    var presentDays = 0;
    final shiftTotals = List<double>.filled(maxShifts, 0);
    for (final s in summaries) {
      if (s.employeeId != empId) continue;
      totalHours += s.totalHours;
      totalTravel += _travelHoursForSummary(s);
      totalWork += s.workCount;
      if (s.totalPunches > 0) presentDays++;
      for (var i = 1; i <= maxShifts; i++) {
        shiftTotals[i - 1] += s.getShiftHours(i);
      }
    }

    final totalRow = rows.isEmpty
        ? null
        : MobileAttendanceVerticalRow(
            day: 'TỔNG',
            weekday: 'CỘNG',
            attendance: Center(
              child: Text(
                tr(presentDays > 0 ? '$presentDays ngày' : '—'),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E40AF),
                ),
              ),
            ),
            shiftHours: [
              for (var i = 0; i < maxShifts; i++)
                shiftTotals[i] > 0 ? _formatHours(shiftTotals[i]) : '—',
            ],
            totalHours:
                totalHours > 0 ? _formatHours(totalHours) : '—',
            travelHours:
                totalTravel > 0 ? _formatHours(totalTravel) : '—',
            totalWork:
                totalWork > 0 ? _verticalWorkCountLabel(totalWork) : '—',
          );

    return MobileAttendanceVerticalTable(
      title: title ?? 'Bảng dọc · $empName',
      rows: rows,
      totalRow: totalRow,
      maxShifts: maxShifts,
      showTravel: _showTravelColumns,
    );
  }

  void _showEmployeeVerticalAttendanceSheet({
    required String empId,
    required String empName,
    required String empCode,
    required List<_DailySummary> summaries,
    required int maxPunches,
    required int maxShifts,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => Scaffold(
          backgroundColor: HrmPageChrome.background,
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(empName), overflow: TextOverflow.ellipsis),
                Text(tr('Mã $empCode'),
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: _buildVerticalSummaryTable(
              empId: empId,
              empName: empName,
              empCode: empCode,
              summaries: summaries,
              maxPunches: maxPunches,
              maxShifts: maxShifts,
              title: empName,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMobileVerticalAttendanceSlivers(
    List<_DailySummary> summaries,
    int maxPunches,
    int maxShifts,
  ) {
    if (summaries.isEmpty) return const [];
    final empId = summaries.first.employeeId;
    final empName = summaries.first.employeeName;
    final empCode = summaries.first.employeeCode;

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        sliver: SliverToBoxAdapter(
          child: _buildVerticalSummaryTable(
            empId: empId,
            empName: empName,
            empCode: empCode,
            summaries: summaries,
            maxPunches: maxPunches,
            maxShifts: maxShifts,
          ),
        ),
      ),
    ];
  }

  // ─── Mobile: danh sách NV (tap xem chi tiết) ─────────────────────────────

  String _mobileEmployeeInitials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    String first(String s) => s.isNotEmpty ? s[0] : '';
    if (parts.length == 1) return first(parts[0]).toUpperCase();
    return '${first(parts[0])}${first(parts.last)}'.toUpperCase();
  }

  Widget _mobileCompactHourChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        tr('$label $value'),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _mobileEmployeeMetricChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(height: 4),
            Text(
              tr(value),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              tr(label),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9,
                color: color.withValues(alpha: 0.85),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildMobileEmployeeSummarySlivers(
    List<_DailySummary> summaries,
    int maxPunches,
    int maxShifts,
  ) {
    final empMap = <String, String>{};
    final empCodeMap = <String, String>{};
    for (final s in summaries) {
      empMap[s.employeeId] = s.employeeName;
      empCodeMap[s.employeeId] = s.employeeCode;
    }
    final roster = widget.employeesList;
    if (roster != null) {
      for (final emp in roster) {
        final code = emp['employeeCode']?.toString() ?? '';
        final pin = emp['pin']?.toString() ?? '';
        final id = code.isNotEmpty ? code : pin;
        if (id.isEmpty || empMap.containsKey(id)) continue;
        if (_selectedEmployeeIds.isNotEmpty &&
            !_selectedEmployeeIds.contains(id) &&
            !_selectedEmployeeIds.contains(code) &&
            !_selectedEmployeeIds.contains(pin)) {
          continue;
        }
        empMap[id] = emp['fullName']?.toString() ??
            emp['name']?.toString() ??
            emp['employeeName']?.toString() ??
            '-';
        empCodeMap[id] = code.isNotEmpty ? code : id;
      }
    }
    final employees = empMap.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    final dates = attendanceDaysInRange(_selectedDateRange);
    final lookup = <String, _DailySummary>{};
    for (final s in summaries) {
      lookup['${s.employeeId}|${DateFormat('yyyy-MM-dd').format(s.date)}'] = s;
    }

    _DailySummary? getSummary(String empId, DateTime day) =>
        lookup['$empId|${DateFormat('yyyy-MM-dd').format(day)}'];

    double totalHoursFor(String empId) => dates.fold<double>(
        0.0, (sum, d) => sum + (getSummary(empId, d)?.totalHours ?? 0.0));

    double totalWorkFor(String empId) => dates.fold<double>(
        0.0, (sum, d) => sum + (getSummary(empId, d)?.workCount ?? 0.0));

    double totalTravelFor(String empId) => dates.fold<double>(0.0, (sum, d) {
          final s = getSummary(empId, d);
          return sum + (s != null ? _travelHoursForSummary(s) : 0.0);
        });

    int presentDaysFor(String empId) => dates
        .where((d) => (getSummary(empId, d)?.totalPunches ?? 0) > 0)
        .length;

    int expectedDaysFor(String empId) {
      final code = empCodeMap[empId] ?? '';
      return dates.where((d) => !_isWeeklyOffDay(d, code)).length;
    }

    String formatWork(double w) => w <= 0
        ? '—'
        : (w % 1 == 0 ? w.toInt().toString() : w.toStringAsFixed(1));

    final grandHours =
        employees.fold<double>(0.0, (s, e) => s + totalHoursFor(e.key));
    final grandWork =
        employees.fold<double>(0.0, (s, e) => s + totalWorkFor(e.key));

    Widget buildEmployeeCard(int index) {
      final empId = employees[index].key;
      final empName = employees[index].value;
      final empCode = empCodeMap[empId] ?? empId;
      final hours = totalHoursFor(empId);
      final travel = totalTravelFor(empId);
      final work = totalWorkFor(empId);
      final present = presentDaysFor(empId);
      final expected = expectedDaysFor(empId);
      final workRatio = expected > 0 ? (work / expected).clamp(0.0, 1.0) : 0.0;
      final workColor = work <= 0
          ? const Color(0xFFA1A1AA)
          : (expected > 0 && work >= expected
              ? const Color(0xFF16A34A)
              : HrmPageChrome.chipMid);
      final shiftHourChips = <Widget>[];
      for (var i = 1; i <= maxShifts; i++) {
        final h = dates.fold<double>(
            0.0, (sum, d) => sum + (getSummary(empId, d)?.getShiftHours(i) ?? 0));
        if (h > 0) {
          shiftHourChips.add(_mobileCompactHourChip(
            label: 'Ca $i',
            value: _formatHours(h),
            color: const Color(0xFF0F766E),
          ));
        }
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => _showEmployeeVerticalAttendanceSheet(
              empId: empId,
              empName: empName,
              empCode: empCode,
              summaries:
                  summaries.where((s) => s.employeeId == empId).toList(),
              maxPunches: maxPunches,
              maxShifts: maxShifts,
            ),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFE4E4E7)),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor:
                            HrmPageChrome.primaryNavy.withValues(alpha: 0.12),
                        child: Text(
                          tr(_mobileEmployeeInitials(empName)),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: HrmPageChrome.primaryNavy,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr(empName),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF18181B),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tr(empCode),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF71717A),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right,
                          color: Color(0xFF94A3B8), size: 22),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _mobileEmployeeMetricChip(
                        icon: Icons.schedule_rounded,
                        label: 'Giờ làm',
                        value: hours > 0 ? _formatHours(hours) : '—',
                        color: HrmPageChrome.chipMid,
                      ),
                      if (_showTravelColumns) ...[
                        const SizedBox(width: 8),
                        _mobileEmployeeMetricChip(
                          icon: Icons.directions_car_rounded,
                          label: 'Đi đường',
                          value: travel > 0 ? _formatHours(travel) : '—',
                          color: HrmPageChrome.chipMid,
                        ),
                      ],
                      const SizedBox(width: 8),
                      _mobileEmployeeMetricChip(
                        icon: Icons.calendar_today_rounded,
                        label: 'Ngày công',
                        value: formatWork(work),
                        color: workColor,
                      ),
                    ],
                  ),
                  if (shiftHourChips.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: shiftHourChips,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _mobileEmployeeMetricChip(
                        icon: Icons.fingerprint_rounded,
                        label: 'Có chấm',
                        value: present > 0 ? '$present ngày' : '—',
                        color: const Color(0xFF16A34A),
                      ),
                    ],
                  ),
                  if (expected > 0) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: workRatio,
                              minHeight: 5,
                              backgroundColor: const Color(0xFFE4E4E7),
                              color: workColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(tr('${formatWork(work)}/$expected công'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: workColor,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget buildGrandTotalCard() {
      return Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              HrmPageChrome.primaryNavy.withValues(alpha: 0.08),
              const Color(0xFFDBEAFE),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF93C5FD)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Tổng cộng'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: HrmPageChrome.primaryNavy,
                    ),
                  ),
                  Text(tr('${employees.length} nhân viên'),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  tr(grandHours > 0 ? _formatHours(grandHours) : '—'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: HrmPageChrome.chipMid,
                  ),
                ),
                Text(tr('tổng giờ'),
                    style: TextStyle(fontSize: 9, color: Color(0xFF71717A))),
                const SizedBox(height: 4),
                Text(
                  tr(formatWork(grandWork)),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: HrmPageChrome.chipMid,
                  ),
                ),
                Text(tr('tổng công'),
                    style: TextStyle(fontSize: 9, color: Color(0xFF71717A))),
              ],
            ),
          ],
        ),
      );
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        sliver: SliverToBoxAdapter(
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.groups_rounded,
                    size: 18, color: HrmPageChrome.primaryNavy),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(tr('Danh sách nhân viên'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF18181B),
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tr('${employees.length} NV'),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: HrmPageChrome.primaryNavy,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        sliver: SliverToBoxAdapter(
          child: Text(tr('Chạm thẻ nhân viên để xem bảng chi tiết điểm danh theo ngày'),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => buildEmployeeCard(index),
            childCount: employees.length,
          ),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        sliver: SliverToBoxAdapter(child: buildGrandTotalCard()),
      ),
    ];
  }
  void _showRowDetailDialog(
      _DailySummary summary, int maxPunches, int maxShifts) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    _openDetailLookupKey = _detailLookupKey(summary);
    _openDetailMaxPunches = maxPunches;
    _openDetailMaxShifts = maxShifts;

    _DailySummary liveSummary() =>
        _summaryForDetailKey(_openDetailLookupKey!) ?? summary;

    bool hasLaterPunch(_DailySummary s, int afterIndex) {
      for (var j = afterIndex + 1; j <= 10; j++) {
        if (s.getPunch(j) != null) return true;
      }
      return false;
    }

    // Build punch section with interactive add/edit buttons
    Widget buildPunchSection(_DailySummary s, BuildContext hostContext) {
      final rows = <Widget>[];
      for (int i = 1; i <= maxPunches; i++) {
        final time = s.getPunch(i);
        final isIn = i % 2 == 1;
        final shouldShow = time != null ||
            i == 1 ||
            hasLaterPunch(s, i - 1) ||
            (i > 1 && s.getPunch(i - 1) != null);
        if (!shouldShow) continue;
        rows.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: (isIn ? Colors.green : Colors.orange)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(isIn ? Icons.login : Icons.logout,
                    size: 15, color: isIn ? Colors.green : Colors.orange),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(tr('Lần $i (${isIn ? "Vào" : "Ra"})'),
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
              ),
              _buildPunchTime(
                time,
                isIn: isIn,
                summary: s,
                punchIndex: i,
                hostContext: hostContext,
              ),
            ],
          ),
        ));
      }
      if (rows.isEmpty) {
        rows.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.login, size: 15, color: Colors.green),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: Text(tr('Lần 1 (Vào)'),
                    style: TextStyle(fontSize: 13, color: Colors.grey))),
            _buildPunchTime(null,
                isIn: true, summary: s, punchIndex: 1, hostContext: hostContext),
          ]),
        ));
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(tr('Chấm công'),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                    letterSpacing: 0.5)),
          ),
          ...rows,
        ],
      );
    }

    Widget buildDetailContent(_DailySummary s, BuildContext hostContext) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildPunchSection(s, hostContext),
          const Divider(height: 24),
          for (int i = 1; i <= maxShifts; i++)
            if (s.getShiftHours(i) > 0)
              _buildDetailRow(
                'Giờ ca $i',
                _formatHours(s.getShiftHours(i)),
                icon: Icons.schedule,
                iconColor: [
                  Colors.teal,
                  Colors.indigo,
                  Colors.purple,
                  Colors.orange,
                  Colors.brown
                ][i - 1],
              ),
          const Divider(height: 24),
          _buildDetailRow(
            'Tổng giờ',
            _formatHours(s.totalHours),
            icon: Icons.timer,
            iconColor: Colors.green,
            isBold: true,
          ),
          if (_showTravelColumns && _travelHoursForSummary(s) > 0)
            _buildDetailRow(
              'Giờ đi đường',
              _formatHours(_travelHoursForSummary(s)),
              icon: Icons.directions_car,
              iconColor: Colors.orange.shade700,
              isBold: true,
            ),
          _buildDetailRow(
            'Giờ thập phân',
            _formatDecimalHours(s.totalHours),
            icon: Icons.onetwothree,
            iconColor: Colors.blue.shade700,
            isBold: true,
          ),
          _buildDetailRow(
            'Tổng lần chấm',
            '${s.totalPunches}',
            icon: Icons.fingerprint,
            iconColor: Colors.purple,
          ),
        ],
      );
    }

    if (isMobile) {
      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            _openDetailDialogSetState = setDialogState;
            _openDetailHostContext = ctx;
            final live = liveSummary();
            return Dialog(
              insetPadding: EdgeInsets.zero,
              child: SizedBox(
                width: double.infinity,
                height: double.infinity,
                child: Scaffold(
                  appBar: AppBar(
                    leading: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx)),
                    title: Text(tr(live.employeeName),
                        overflow: TextOverflow.ellipsis),
                  ),
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: Colors.blue.shade100,
                              child: Text(
                                tr(live.employeeName.isNotEmpty
                                    ? live.employeeName[0].toUpperCase()
                                    : '?'),
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(tr(live.employeeName),
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold)),
                                  Text(tr('Mã: ${live.employeeCode}'),
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today,
                                  size: 16, color: Colors.grey.shade600),
                              const SizedBox(width: 8),
                              Text(
                                tr('${_getDayOfWeekVN(live.date.weekday)}, ${DateFormat('dd/MM/yyyy').format(live.date)}'),
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        buildDetailContent(live, ctx),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ).whenComplete(_clearOpenDetailDialogRefs);
    } else {
      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) {
            _openDetailDialogSetState = setDialogState;
            _openDetailHostContext = ctx;
            final live = liveSummary();
            return Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 420, maxHeight: 600),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .primaryColor
                            .withValues(alpha: 0.08),
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(12)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.blue.shade100,
                            child: Text(
                              tr(live.employeeName.isNotEmpty
                                  ? live.employeeName[0].toUpperCase()
                                  : '?'),
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tr(live.employeeName),
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold)),
                                Text(tr('Mã: ${live.employeeCode}'),
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => Navigator.pop(ctx),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(
                            bottom: BorderSide(color: Colors.grey.shade200)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today,
                              size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 8),
                          Text(
                            tr('${_getDayOfWeekVN(live.date.weekday)}, ${DateFormat('dd/MM/yyyy').format(live.date)}'),
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: buildDetailContent(live, ctx),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(tr('Đóng')),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ).whenComplete(_clearOpenDetailDialogRefs);
    }
  }

  Widget _buildDetailRow(String label, String value,
      {IconData? icon, Color? iconColor, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          if (icon != null) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: (iconColor ?? Colors.grey).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, size: 15, color: iconColor),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(tr(label),
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          ),
          Text(
            tr(value),
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isBold ? Colors.black : Colors.grey.shade800,
            ),
          ),
        ],
      ),
    );
  }

  /// Build TableRows with optional branch-group headers (desktop).
  List<TableRow> _buildSummaryDataTableRows(
    List<_DailySummary> pagedSummaries,
    List<_DailySummary> allSummaries,
    int maxPunches,
    int maxShifts,
    Map<String, Map<String, int>> daySttMap,
  ) {
    final shiftColors = [
      Colors.teal,
      Colors.indigo,
      Colors.purple,
      Colors.orange,
      Colors.brown
    ];
    final bool groupByBranch = widget.branches != null &&
        widget.branches!.isNotEmpty &&
        _codeTobranchName.isNotEmpty;
    final primaryColor = Theme.of(context).primaryColor;
    final colCount = _summaryColumnCount(maxPunches, maxShifts);
    final List<TableRow> rows = [];
    String? currentBranch;
    int dataRowIndex = 0;
    final empTotals = _employeeTotalsFrom(allSummaries);
    final empLastRowKeys = _employeeLastRowKeys(allSummaries);

    // Pre-compute branch employee counts
    final Map<String, int> branchEmpCounts = {};
    if (groupByBranch) {
      for (final s in allSummaries) {
        final lbl = s.branchName.isEmpty ? 'Chưa có chi nhánh' : s.branchName;
        branchEmpCounts.putIfAbsent(lbl, () => 0);
      }
      for (final s in allSummaries) {
        final lbl = s.branchName.isEmpty ? 'Chưa có chi nhánh' : s.branchName;
        branchEmpCounts[lbl] = (branchEmpCounts[lbl] ?? 0);
      }
      // Count unique employees per branch
      final Map<String, Set<String>> branchEmps = {};
      for (final s in allSummaries) {
        final lbl = s.branchName.isEmpty ? 'Chưa có chi nhánh' : s.branchName;
        branchEmps.putIfAbsent(lbl, () => {}).add(s.employeeCode);
      }
      for (final e in branchEmps.entries) {
        branchEmpCounts[e.key] = e.value.length;
      }
    }

    for (final summary in pagedSummaries) {
      // Branch header row (insert when branch changes)
      if (groupByBranch) {
        final branchLabel = summary.branchName.isEmpty
            ? 'Chưa có chi nhánh'
            : summary.branchName;
        if (branchLabel != currentBranch) {
          currentBranch = branchLabel;
          final empCount = branchEmpCounts[branchLabel] ?? 0;
          rows.add(TableRow(
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.06),
            ),
            children: [
              _summaryTableCell(
                Row(
                  children: [
                    Icon(Icons.account_tree_outlined,
                        size: 14, color: primaryColor),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        tr(branchLabel),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: primaryColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        tr('$empCount NV'),
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.white),
                      ),
                    ),
                  ],
                ),
                alignment: Alignment.centerLeft,
              ),
              for (int i = 1; i < colCount; i++)
                _summaryTableCell(const SizedBox.shrink()),
            ],
          ));
        }
      }

      // Regular data row
      final dayOfWeek = _getDayOfWeekVN(summary.date.weekday);
      final stt = daySttMap[summary.employeeId]?[_dailySummaryRowKey(summary)] ??
          1;
      final cells = <Widget>[
        _summaryTableCell(Text(
          tr('$stt'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        )),
        _summaryTableCell(
          InkWell(
            onTap: () =>
                _showRowDetailDialog(summary, maxPunches, maxShifts),
            child: Text(
              tr(summary.employeeName),
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ),
        _summaryTableCell(
          Text(
            tr(summary.employeeCode),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        _summaryTableCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _getDayColor(summary.date.weekday).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              tr(dayOfWeek),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _getDayColor(summary.date.weekday),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        _summaryTableCell(
          Text(
            tr(DateFormat('dd/MM/yyyy').format(summary.date)),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ];

      for (int i = 1; i <= maxPunches; i++) {
        final isIn = i % 2 == 1;
        cells.add(_summaryTableCell(
          _buildPunchTime(
            summary.getPunch(i),
            isIn: isIn,
            summary: summary,
            punchIndex: i,
            hostContext: context,
          ),
        ));
      }

      for (int i = 1; i <= maxShifts; i++) {
        cells.add(_summaryTableCell(
          _buildHoursBadge(summary.getShiftHours(i), shiftColors[i - 1]),
        ));
      }

      cells.add(_summaryTableCell(
        _buildHoursBadge(summary.totalHours, Colors.green, isBold: true),
      ));

      if (_showTravelColumns) {
        cells.add(_summaryTableCell(
          _buildTravelHoursCell(_travelHoursForSummary(summary)),
        ));
      }

      cells.add(_summaryTableCell(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: summary.isHoliday
                ? Colors.deepOrange.withValues(alpha: 0.12)
                : (summary.isRestDay && summary.effectiveMultiplier > 1
                    ? Colors.purple.withValues(alpha: 0.12)
                    : (summary.workCount > 0
                        ? Colors.blue.withValues(alpha: 0.10)
                        : Colors.transparent)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            tr(summary.workCount > 0
                ? (summary.effectiveMultiplier != 1.0
                    ? '${summary.workCount.toStringAsFixed(2)} (x${summary.effectiveMultiplier.toStringAsFixed(summary.effectiveMultiplier % 1 == 0 ? 0 : 1)})'
                    : summary.workCount.toStringAsFixed(2))
                : '-'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: summary.isHoliday
                  ? Colors.deepOrange
                  : (summary.isRestDay && summary.effectiveMultiplier > 1
                      ? Colors.purple
                      : (summary.workCount > 0
                          ? Colors.blue.shade700
                          : Colors.grey)),
            ),
          ),
        ),
      ));

      cells.add(_summaryTableCell(
        Text(
          tr(_formatDecimalHours(summary.totalHours)),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color:
                summary.totalHours > 0 ? Colors.blue.shade700 : Colors.grey,
          ),
        ),
      ));

      rows.add(TableRow(
        children: cells,
      ));

      final rowKey = _dailySummaryRowKey(summary);
      if (empLastRowKeys[summary.employeeId] == rowKey) {
        final totals = empTotals[summary.employeeId];
        if (totals != null) {
          rows.add(_buildEmployeeSubtotalTableRow(
            totals,
            maxPunches,
            maxShifts,
            shiftColors,
          ));
        }
      }
    }

    return rows;
  }

  // Filter bar
  Widget _buildFilters(DateTimeRange range, {bool embedded = false}) {
    final isMobile = MediaQuery.of(context).size.width < 768;

    final datePreset = _buildDropdown<String>(
      value: _selectedPreset,
      width: isMobile ? 120 : null,
      icon: Icons.calendar_today,
      items: [
        DropdownMenuItem(value: 'today', child: Text(tr('Hôm nay'))),
        DropdownMenuItem(value: 'yesterday', child: Text(tr('Hôm qua'))),
        DropdownMenuItem(value: 'week', child: Text(tr('Tuần này'))),
        DropdownMenuItem(value: 'lastWeek', child: Text(tr('Tuần trước'))),
        DropdownMenuItem(value: 'month', child: Text(tr('Tháng này'))),
        DropdownMenuItem(value: 'lastMonth', child: Text(tr('Tháng trước'))),
      ],
      onChanged: (v) {
        if (v != null) {
          setState(() {
            _selectedPreset = v;
            _currentPage = 0;
          });
          widget.onDateRangeChanged?.call(v);
        }
      },
    );

    final dateRange = _buildDateRangeDisplay(range, compact: isMobile);

    final employeeFilter = _buildEmployeeFilter();

    final shiftFilter = _buildDropdown<String>(
      value: _shiftFilter,
      width: isMobile ? 150 : null,
      icon: Icons.warning_amber_rounded,
      items: [
        DropdownMenuItem(value: 'all', child: Text(tr('Tất cả ca'))),
        DropdownMenuItem(value: 'missing', child: Text(tr('Thiếu chấm công'))),
        DropdownMenuItem(value: 'complete', child: Text(tr('Đủ chấm công'))),
      ],
      onChanged: (v) {
        if (v != null) {
          setState(() {
            _shiftFilter = v;
            _invalidateDisplayDerivedCache();
            _currentPage = 0;
          });
        }
      },
    );

    final recordCount = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.table_chart,
              color: Theme.of(context).primaryColor, size: 14),
          const SizedBox(width: 5),
          Text(tr('${_dailySummaryData.length} bản ghi'),
            style: TextStyle(
              color: Theme.of(context).primaryColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    final filterBody = isMobile
        ? Column(
            children: [
              Row(children: [recordCount]),
              const SizedBox(height: 8),
              Row(
                children: [
                  datePreset,
                  const SizedBox(width: 8),
                  Expanded(child: dateRange),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: employeeFilter),
                  const SizedBox(width: 8),
                  Expanded(child: shiftFilter),
                ],
              ),
            ],
          )
        : Row(
            children: [
              Expanded(child: datePreset),
              const SizedBox(width: 12),
              Expanded(child: dateRange),
              const SizedBox(width: 12),
              Expanded(child: employeeFilter),
              const SizedBox(width: 12),
              Expanded(child: shiftFilter),
              const SizedBox(width: 12),
              recordCount,
            ],
          );

    if (embedded) return filterBody;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: filterBody,
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    double? width,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      width: width,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          icon: const Icon(Icons.keyboard_arrow_down, size: 16),
          style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).textTheme.bodyMedium?.color),
          dropdownColor: Theme.of(context).cardColor,
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item.value,
                    child: Row(
                      children: [
                        Icon(icon, size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 6),
                        Expanded(
                            child: DefaultTextStyle(
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color),
                          overflow: TextOverflow.ellipsis,
                          child: item.child,
                        )),
                      ],
                    ),
                  ))
              .toList(),
          selectedItemBuilder: (context) => items
              .map((item) => Row(
                    children: [
                      Icon(icon,
                          size: 14, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 6),
                      Expanded(
                          child: DefaultTextStyle(
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).textTheme.bodyMedium?.color),
                        overflow: TextOverflow.ellipsis,
                        child: item.child,
                      )),
                    ],
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildDateRangeDisplay(DateTimeRange range, {bool compact = false}) {
    final fmt = compact ? DateFormat('dd/MM/yy') : DateFormat('dd/MM/yyyy');
    return Container(
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
          Icon(Icons.date_range,
              size: 14, color: Theme.of(context).primaryColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              tr('${fmt.format(range.start)} \u2013 ${fmt.format(range.end)}'),
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Widget hiển thị thời gian chấm công - có thể click để sửa/xóa
  Widget _buildPunchTime(
    DateTime? time, {
    required bool isIn,
    required _DailySummary summary,
    required int punchIndex,
    required BuildContext hostContext,
  }) {
    if (time == null) {
      if (!widget.allowCorrection) {
        return Center(
          child: Text(tr('—'),
              style: TextStyle(fontSize: 11, color: Color(0xFFA1A1AA))),
        );
      }
      return Center(
        child: InkWell(
          onTap: () =>
              _showAddPunchDialog(summary, punchIndex, isIn, hostContext),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              border: Border.all(
                  color: Colors.grey.withValues(alpha: 0.3),
                  style: BorderStyle.solid),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.add, size: 14, color: Colors.grey),
          ),
        ),
      );
    }

    if (!widget.allowCorrection) {
      return Center(
        child: Text(
          tr(DateFormat('HH:mm').format(time)),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isIn ? HrmPageChrome.chip : const Color(0xFFDC2626),
          ),
        ),
      );
    }

    return Center(
      child: InkWell(
        onTap: () =>
            _showEditPunchDialog(summary, punchIndex, time, isIn, hostContext),
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: (isIn ? Colors.green : Colors.red).withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: (isIn ? Colors.green : Colors.red).withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isIn ? Icons.login : Icons.logout,
                size: 12,
                color: isIn ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 3),
              Text(
                tr(DateFormat('HH:mm').format(time)),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: isIn ? Colors.green : Colors.red,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.edit,
                size: 10,
                color: (isIn ? Colors.green : Colors.red).withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _deviceIdForEmployee(_DailySummary summary) {
    for (final att in widget.attendances) {
      final key = att.employeeId ?? att.enrollNumber;
      if (key != null &&
          (key == summary.employeeCode ||
              key == summary.pin ||
              key == summary.employeeId) &&
          att.deviceId != null &&
          att.deviceId!.isNotEmpty) {
        return att.deviceId;
      }
    }
    return widget.devices.isNotEmpty ? widget.devices.first.id : null;
  }

  /// Hiển thị dialog thêm chấm công mới
  void _showAddPunchDialog(
      _DailySummary summary, int punchIndex, bool isIn, BuildContext hostContext) {
    final live = _liveSummaryForDetail(summary);
    if (!widget.allowCorrection) return;
    TimeOfDay selectedTime = TimeOfDay.now();
    DateTime selectedDate = live.date;
    final reasonController = TextEditingController();
    final canFine = Provider.of<PermissionProvider>(context, listen: false)
        .canCreate('PenaltyTickets');

    showDialog(
      context: hostContext,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => ScrollableAlertDialog(
          title: Row(
            children: [
              Icon(Icons.add_circle, color: Colors.blue),
              SizedBox(width: 8),
              Text(tr('Thêm chấm công')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thông tin nhân viên
                Card(
                  color: Colors.grey.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Nhân viên: ${live.employeeName}'),
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Text(tr('Mã NV: ${live.employeeCode}')),
                        Text(tr('${tr('Ngày: ')}${DateFormat('dd/MM/yyyy').format(selectedDate)}')),
                        Text(tr('Lần chấm: $punchIndex (${isIn ? "Vào" : "Ra"})')),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Chọn ngày (cho ca qua đêm)
                Text(tr('Ngày chấm công:'),
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogCtx,
                      initialDate: selectedDate,
                      firstDate: widget.fromDate,
                      lastDate: widget.toDate,
                    );
                    if (picked != null) {
                      setDialogState(() => selectedDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          tr(DateFormat('dd/MM/yyyy').format(selectedDate)),
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        if (selectedDate != live.date) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(tr('Ngày hôm sau'),
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.orange.shade800)),
                          ),
                        ],
                        const Spacer(),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Chọn giờ
                Text(tr('Chọn giờ chấm công:'),
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: dialogCtx,
                      initialTime: selectedTime,
                    );
                    if (picked != null) {
                      setDialogState(() => selectedTime = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(isIn ? Icons.login : Icons.logout,
                            color: isIn ? Colors.green : Colors.red),
                        const SizedBox(width: 8),
                        Text(
                          tr('${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}'),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        const Icon(Icons.access_time),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                AttendanceCorrectionReasonField(
                  controller: reasonController,
                  kind: AttendanceCorrectionReasonKind.add,
                  employeeName: live.employeeName,
                  employeeCode: live.employeeCode,
                  date: selectedDate,
                  timeText:
                      '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                  punchLabel: isIn ? 'Vào' : 'Ra',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(tr('Hủy')),
            ),
            if (canFine)
              OutlinedButton.icon(
                onPressed: () async {
                  if (reasonController.text.trim().isEmpty) {
                    appNotification.showError(
                        title: 'Lỗi', message: tr('Vui lòng nhập lý do'));
                    return;
                  }
                  if (live.employeeGuid == null ||
                      live.employeeGuid!.isEmpty) {
                    appNotification.showError(
                        title: 'Lỗi',
                        message: tr('Không tìm thấy hồ sơ nhân viên. Hãy chọn lại chi nhánh để tải danh sách NV, hoặc liên kết PIN máy với hồ sơ HR.'));
                    return;
                  }

                  final timeStr =
                      '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';
                  final api = ApiService();
                  final result = await api.createAttendanceCorrection(
                    action: 0,
                    pin: live.pin,
                    employeeName: live.employeeName,
                    employeeCode: live.employeeCode,
                    newDate: DateTime(
                        selectedDate.year, selectedDate.month, selectedDate.day),
                    newTime: '$timeStr:00',
                    newType: isIn ? 'CheckIn' : 'CheckOut',
                    reason: reasonController.text.trim(),
                  );
                  Navigator.pop(dialogCtx);
                  if (result['isSuccess'] != true) {
                    appNotification.showError(
                        title: 'Lỗi',
                        message: result['message'] ?? 'Có lỗi xảy ra');
                    return;
                  }
                  _notifyDataChanged();
                  final fined = await _createForgotCheckPenaltyTicket(
                    employeeId: live.employeeGuid!,
                    employeeName: live.employeeName,
                    violationDate: selectedDate,
                  );
                  appNotification.showSuccess(
                      title: 'Thành công',
                      message: fined
                          ? 'Đã bổ sung chấm công và tạo phiếu phạt quên chấm công'
                          : 'Đã bổ sung chấm công (chưa tạo được phiếu phạt)');
                },
                icon: const Icon(Icons.gavel, size: 16, color: Colors.orange),
                label: Text(tr('Thêm công và phạt'),
                    style: TextStyle(color: Colors.orange)),
                style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.orange)),
              ),
            FilledButton.icon(
              onPressed: () async {
                if (reasonController.text.trim().isEmpty) {
                  appNotification.showError(
                      title: 'Lỗi', message: tr('Vui lòng nhập lý do'));
                  return;
                }
                if (live.employeeGuid == null ||
                    live.employeeGuid!.isEmpty) {
                  appNotification.showError(
                      title: 'Lỗi',
                      message: tr('Không tìm thấy hồ sơ nhân viên. Hãy chọn lại chi nhánh để tải danh sách NV, hoặc liên kết PIN máy với hồ sơ HR.'));
                  return;
                }

                final requestedTime = DateTime(
                  selectedDate.year,
                  selectedDate.month,
                  selectedDate.day,
                  selectedTime.hour,
                  selectedTime.minute,
                );

                final request = AttendanceCorrectionRequest(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  employeeName: live.employeeName,
                  employeeCode: live.employeeCode,
                  pin: live.pin,
                  employeeUserId: live.applicationUserId,
                  employeeGuid: live.employeeGuid,
                  deviceId: _deviceIdForEmployee(live),
                  attendanceId: null, // Thêm mới nên không có ID cũ
                  requestDate: DateTime.now(),
                  correctionDate: selectedDate,
                  reason: reasonController.text.trim(),
                  correctionType: 'add',
                  requestedTime: DateFormat('HH:mm').format(requestedTime),
                  punchIndex: punchIndex,
                  newType: isIn ? 'CheckIn' : 'CheckOut',
                );

                Navigator.pop(dialogCtx);
                await _applyCorrectionRequest(request);
              },
              icon: Icon(widget.directApplyCorrections
                  ? Icons.check_circle
                  : Icons.send),
              label: Text(tr(widget.directApplyCorrections
                  ? 'Áp dụng ngay'
                  : 'Gửi yêu cầu')),
            ),
          ],
        ),
      ),
    );
  }

  /// Tạo phiếu phạt "Quên chấm công" theo mức phạt trong Thiết lập phạt.
  /// Dùng cho nút "Thêm công và phạt" khi bổ sung chấm công thủ công.
  Future<bool> _createForgotCheckPenaltyTicket({
    required String employeeId,
    required String employeeName,
    required DateTime violationDate,
  }) async {
    try {
      final api = ApiService();
      final settingsResult = await api.getPenaltySettings();
      final amount = double.tryParse(
              (settingsResult['data']?['forgotCheckPenalty'] ?? 0)
                  .toString()) ??
          0;
      if (amount <= 0) {
        appNotification.showWarning(
            title: 'Không tạo được phiếu phạt',
            message: tr('Mức phạt "Quên chấm công" chưa được cấu hình (0đ). Vui lòng vào Thiết lập phạt để cài đặt.'));
        return false;
      }

      final createResult = await api.createPenaltyTicket({
        'employeeId': employeeId,
        'type': 'ForgotCheck',
        'amount': amount,
        'violationDate': violationDate.toIso8601String(),
        'description':
            'Quên chấm công - bổ sung chấm công thủ công ($employeeName)',
      });
      if (createResult['isSuccess'] != true) {
        appNotification.showWarning(
            title: 'Không tạo được phiếu phạt',
            message: createResult['message'] ?? 'Có lỗi xảy ra');
        return false;
      }

      final ticketId = createResult['data']?['id']?.toString();
      final canApprovePenalty = mounted &&
          Provider.of<PermissionProvider>(context, listen: false)
              .canApprove('PenaltyTickets');
      if (ticketId != null && canApprovePenalty) {
        await api.approvePenaltyTicket(ticketId);
      }
      return true;
    } catch (e) {
      appNotification.showWarning(
          title: 'Không tạo được phiếu phạt', message: e.toString());
      return false;
    }
  }

  /// Hiển thị dialog sửa/xóa chấm công
  void _showEditPunchDialog(_DailySummary summary, int punchIndex,
      DateTime currentTime, bool isIn, BuildContext hostContext) {
    final live = _liveSummaryForDetail(summary);
    if (!widget.allowCorrection) return;
    TimeOfDay selectedTime =
        TimeOfDay(hour: currentTime.hour, minute: currentTime.minute);
    final reasonController = TextEditingController();

    showDialog(
      context: hostContext,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => ScrollableAlertDialog(
          title: Row(
            children: [
              Icon(Icons.edit, color: Colors.orange),
              SizedBox(width: 8),
              Text(tr('Sửa/Xóa chấm công')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thông tin nhân viên
                Card(
                  color: Colors.grey.withValues(alpha: 0.1),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Nhân viên: ${live.employeeName}'),
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                        Text(tr('Mã NV: ${live.employeeCode}')),
                        Text(tr('${tr('Ngày: ')}${DateFormat('dd/MM/yyyy').format(live.date)}')),
                        Text(tr('Lần chấm: $punchIndex (${isIn ? "Vào" : "Ra"})')),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(tr('Giờ hiện tại: ')),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: (isIn ? Colors.green : Colors.red)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                tr(DateFormat('HH:mm').format(currentTime)),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isIn ? Colors.green : Colors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Chọn giờ mới
                Text(tr('Sửa thành giờ mới:'),
                    style: TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: dialogCtx,
                      initialTime: selectedTime,
                    );
                    if (picked != null) {
                      setDialogState(() => selectedTime = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.orange),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(isIn ? Icons.login : Icons.logout,
                            color: isIn ? Colors.green : Colors.red),
                        const SizedBox(width: 8),
                        Text(
                          tr('${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}'),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const Spacer(),
                        const Icon(Icons.access_time),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                AttendanceCorrectionReasonField(
                  controller: reasonController,
                  kind: AttendanceCorrectionReasonKind.edit,
                  employeeName: live.employeeName,
                  employeeCode: live.employeeCode,
                  date: live.date,
                  originalTimeText: DateFormat('HH:mm').format(currentTime),
                  timeText:
                      '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                  punchLabel: isIn ? 'Vào' : 'Ra',
                ),
              ],
            ),
          ),
          actions: [
            // Nút xóa
            TextButton.icon(
              onPressed: () {
                Navigator.pop(dialogCtx);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    _confirmDeletePunch(
                        live, punchIndex, currentTime, isIn, hostContext);
                  }
                });
              },
              icon: const Icon(Icons.delete, color: Colors.red),
              label: Text(tr('Xóa'), style: TextStyle(color: Colors.red)),
            ),
            // Dùng SizedBox thay cho Spacer trong AlertDialog actions
            const SizedBox(width: 16),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(tr('Hủy')),
            ),
            FilledButton.icon(
              onPressed: () async {
                if (reasonController.text.trim().isEmpty) {
                  appNotification.showError(
                      title: 'Lỗi', message: tr('Vui lòng nhập lý do'));
                  return;
                }

                final requestedTime = DateTime(
                  live.date.year,
                  live.date.month,
                  live.date.day,
                  selectedTime.hour,
                  selectedTime.minute,
                );

                final punchRef = _attendancePunchRef(live, punchIndex);
                if (punchRef == null) {
                  appNotification.showError(
                    title: 'Lỗi',
                    message: tr('Không tìm thấy bản ghi chấm công. Vui lòng tải lại dữ liệu.'),
                  );
                  return;
                }

                final request = AttendanceCorrectionRequest(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  employeeName: live.employeeName,
                  employeeCode: live.employeeCode,
                  pin: punchRef.pin ?? live.pin,
                  employeeUserId: live.applicationUserId,
                  attendanceId: punchRef.id,
                  requestDate: DateTime.now(),
                  correctionDate: live.date,
                  reason: reasonController.text.trim(),
                  correctionType: 'edit',
                  requestedTime: DateFormat('HH:mm').format(requestedTime),
                  punchIndex: punchIndex,
                  originalTime: currentTime,
                  newType: isIn ? 'CheckIn' : 'CheckOut',
                );

                Navigator.pop(dialogCtx);
                await _applyCorrectionRequest(request);
              },
              icon: Icon(widget.directApplyCorrections
                  ? Icons.check_circle
                  : Icons.send),
              label: Text(tr(widget.directApplyCorrections
                  ? 'Áp dụng sửa'
                  : 'Gửi yêu cầu sửa')),
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            ),
          ],
        ),
      ),
    );
  }

  /// Dialog xác nhận xóa chấm công
  Future<void> _confirmDeletePunch(
      _DailySummary summary,
      int punchIndex,
      DateTime currentTime,
      bool isIn,
      BuildContext hostContext) async {
    final live = _liveSummaryForDetail(summary);
    final reason = await showAttendanceDeleteConfirmDialog(
      context: hostContext,
      employeeName: live.employeeName,
      employeeCode: live.employeeCode,
      date: live.date,
      punchIndex: punchIndex,
      punchTime: currentTime,
      isIn: isIn,
      directApply: widget.directApplyCorrections,
    );
    if (reason == null || !mounted) return;

    final punchRef = _attendancePunchRef(live, punchIndex);
    if (punchRef == null) {
      appNotification.showError(
        title: 'Lỗi',
        message: tr('Không tìm thấy bản ghi chấm công trên server. Vui lòng tải lại dữ liệu.'),
      );
      return;
    }

    final request = AttendanceCorrectionRequest(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      employeeName: live.employeeName,
      employeeCode: live.employeeCode,
      pin: punchRef.pin ?? live.pin,
      employeeUserId: live.applicationUserId,
      attendanceId: punchRef.id,
      requestDate: DateTime.now(),
      correctionDate: live.date,
      reason: reason,
      correctionType: 'delete',
      requestedTime: DateFormat('HH:mm').format(currentTime),
      punchIndex: punchIndex,
      originalTime: currentTime,
    );

    await _applyCorrectionRequest(request);
  }

  Widget _buildHoursBadge(double hours, Color color, {bool isBold = false}) {
    if (hours <= 0) {
      return Text(
        tr('-'),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: Colors.grey),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tr(_formatHours(hours)),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildStatCard(
      String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr(label),
                      style: TextStyle(color: Colors.grey[600], fontSize: 10)),
                  const SizedBox(height: 2),
                  Text(tr(value),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: color)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DailySummary {
  final String employeeId;
  final String employeeName;
  final String employeeCode;
  final String? pin; // PIN/mã chấm công
  final String? applicationUserId;
  final String? employeeGuid;
  final DateTime date;
  final DateTime? punch1;
  final DateTime? punch2;
  final DateTime? punch3;
  final DateTime? punch4;
  final DateTime? punch5;
  final DateTime? punch6;
  final DateTime? punch7;
  final DateTime? punch8;
  final DateTime? punch9;
  final DateTime? punch10;
  // Lưu attendance IDs tương ứng với mỗi punch (để có thể xác định chính xác bản ghi)
  final String? punchId1;
  final String? punchId2;
  final String? punchId3;
  final String? punchId4;
  final String? punchId5;
  final String? punchId6;
  final String? punchId7;
  final String? punchId8;
  final String? punchId9;
  final String? punchId10;
  final double shift1Hours;
  final double shift2Hours;
  final double shift3Hours;
  final double shift4Hours;
  final double shift5Hours;
  final double totalHours;
  final int totalPunches; // Tổng số lần chấm công
  final double workCount; // Số công (đã nhân hệ số ngày lễ/ngày nghỉ nếu có)
  final double effectiveMultiplier; // 1.0 = bình thường, >1 = ngày lễ/nghỉ
  final bool isHoliday;
  final bool isRestDay;
  final String branchName; // Tên chi nhánh (lookup từ employeesList)

  _DailySummary({
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    this.pin,
    this.applicationUserId,
    this.employeeGuid,
    required this.date,
    this.punch1,
    this.punch2,
    this.punch3,
    this.punch4,
    this.punch5,
    this.punch6,
    this.punch7,
    this.punch8,
    this.punch9,
    this.punch10,
    this.punchId1,
    this.punchId2,
    this.punchId3,
    this.punchId4,
    this.punchId5,
    this.punchId6,
    this.punchId7,
    this.punchId8,
    this.punchId9,
    this.punchId10,
    required this.shift1Hours,
    required this.shift2Hours,
    this.shift3Hours = 0,
    this.shift4Hours = 0,
    this.shift5Hours = 0,
    required this.totalHours,
    this.totalPunches = 0,
    this.workCount = 0,
    this.effectiveMultiplier = 1.0,
    this.isHoliday = false,
    this.isRestDay = false,
    this.branchName = '',
  });

  // Lấy punch time theo index (1-10)
  DateTime? getPunch(int index) {
    switch (index) {
      case 1:
        return punch1;
      case 2:
        return punch2;
      case 3:
        return punch3;
      case 4:
        return punch4;
      case 5:
        return punch5;
      case 6:
        return punch6;
      case 7:
        return punch7;
      case 8:
        return punch8;
      case 9:
        return punch9;
      case 10:
        return punch10;
      default:
        return null;
    }
  }

  // Lấy attendance ID theo punch index (1-10)
  String? getPunchId(int index) {
    switch (index) {
      case 1:
        return punchId1;
      case 2:
        return punchId2;
      case 3:
        return punchId3;
      case 4:
        return punchId4;
      case 5:
        return punchId5;
      case 6:
        return punchId6;
      case 7:
        return punchId7;
      case 8:
        return punchId8;
      case 9:
        return punchId9;
      case 10:
        return punchId10;
      default:
        return null;
    }
  }

  // Lấy shift hours theo index (1-5)
  double getShiftHours(int index) {
    switch (index) {
      case 1:
        return shift1Hours;
      case 2:
        return shift2Hours;
      case 3:
        return shift3Hours;
      case 4:
        return shift4Hours;
      case 5:
        return shift5Hours;
      default:
        return 0;
    }
  }
}

class _EmployeePeriodTotals {
  final String employeeId;
  final String employeeName;
  final String employeeCode;
  double totalHours = 0;
  double totalWork = 0;
  int presentDays = 0;
  final List<double> _shiftHours = [0, 0, 0, 0, 0];

  _EmployeePeriodTotals({
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
  });

  void add(_DailySummary s) {
    totalHours += s.totalHours;
    totalWork += s.workCount;
    if (s.totalPunches > 0) presentDays++;
    _shiftHours[0] += s.shift1Hours;
    _shiftHours[1] += s.shift2Hours;
    _shiftHours[2] += s.shift3Hours;
    _shiftHours[3] += s.shift4Hours;
    _shiftHours[4] += s.shift5Hours;
  }

  double shiftAt(int index) {
    if (index < 1 || index > 5) return 0;
    return _shiftHours[index - 1];
  }
}

class _EmployeeOption {
  final String id;
  final String name;
  final String code;
  _EmployeeOption({required this.id, required this.name, required this.code});
}
