import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../utils/attendance_correction_privilege.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/page_top_actions.dart';
import '../models/attendance.dart';
import '../models/device.dart';
import '../services/api_service.dart';
import '../utils/travel_hours_load_utils.dart';
import '../utils/travel_eligibility_utils.dart';
import 'attendance/attendance_summary_tab.dart';
import 'package:intl/intl.dart';
import 'main_layout.dart' show ScreenRefreshNotifier;
import '../utils/responsive_helper.dart';
import '../utils/vietnamese_font.dart';
import '../widgets/notification_overlay.dart';
import '../utils/attendance_load_utils.dart';
import '../utils/attendance_date_range_presets.dart';
import '../utils/attendance_correction_submit.dart';
import '../utils/attendance_record_resolver.dart';
import '../utils/attendance_correction_dates.dart';
import '../utils/branch_filter_helper.dart';
import '../utils/department_filter_helper.dart';
import '../utils/report_screen_helpers.dart';
import '../widgets/reports/hrm_report_widgets.dart';
import '../utils/salary_profile_load_utils.dart';
import '../utils/paid_leave_schedule_utils.dart';
import '../utils/shift_records_calculator.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Màn hình tổng hợp chấm công - standalone wrapper cho AttendanceSummaryTab
/// Tự load dữ liệu (attendances + devices) và nhúng AttendanceSummaryTab
class AttendanceSummaryScreen extends StatefulWidget {
  const AttendanceSummaryScreen({super.key});

  @override
  State<AttendanceSummaryScreen> createState() =>
      _AttendanceSummaryScreenState();
}

class _AttendanceSummaryScreenState extends State<AttendanceSummaryScreen> {
  final ApiService _apiService = ApiService();
  final _tabKey = GlobalKey();

  List<Attendance> _attendances = [];
  List<Device> _devices = [];
  List<dynamic> _holidays = [];
  List<dynamic> _salaryProfiles = [];
  List<Map<String, dynamic>> _shiftTemplates = [];
  List<Map<String, dynamic>> _shiftSalaryLevels = [];
  List<dynamic> _approvedLeaves = [];
  List<Map<String, dynamic>> _workSchedules = [];
  String? _selectedBranchId;
  String? _selectedDepartmentId;
  final _branchFilter = ReportBranchFilter();
  int _dayEndHour = 0;
  int _dayEndMinute = 0;
  double _minHoursForWorkDay = 0;
  bool _decimalWorkDayEnabled = false;
  double _standardWorkHours = 8;
  bool _isLoading = true;
  String _loadMessage = 'Đang tải dữ liệu...';
  bool _allowManualCorrection = true;

  String _loadPreset = 'month';
  late DateTime _fromDate;
  late DateTime _toDate;
  bool _attendanceLoadTruncated = false;
  int? _attendanceExpectedCount;
  Map<String, double> _travelHoursByEmployeeKey = {};
  Map<String, double> _travelHoursByEmployeeDateKey = {};
  Set<String> _travelEligibleEmployeeKeys = {};
  Map<String, dynamic>? _salarySettings;

  _AttendanceSummaryScreenState() {
    final range = AttendanceDateRangePresets.resolve('month');
    _fromDate = range.start;
    _toDate = range.end;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      _loadEmployeesAndBranches();
    });
    ScreenRefreshNotifier.attendanceSummary.addListener(_onExternalRefresh);
  }

  Future<void> _loadEmployeesAndBranches() async {
    await _branchFilter.loadOrgFilters(_apiService);
    if (mounted) setState(() {});
  }

  List<Map<String, dynamic>> get _orgEmployees =>
      _branchFilter.scopedEmployees(
        branchId: _selectedBranchId,
        departmentId: _selectedDepartmentId,
      ) ??
      _branchFilter.employees;

  List<Attendance> get _filteredAttendances {
    final keys = _branchFilter.scopeIdentityKeys(
      branchId: _selectedBranchId,
      departmentId: _selectedDepartmentId,
    );
    if (keys == null) return _attendances;
    if (keys.isEmpty) return const [];
    return _attendances.where((a) {
      final code = a.employeeId;
      if (code != null && code.isNotEmpty && keys.contains(code)) return true;
      final pin = a.pin;
      if (pin != null && pin.isNotEmpty && keys.contains(pin)) return true;
      return false;
    }).toList();
  }

  void _onExternalRefresh() {
    if (mounted) {
      _loadData();
    }
  }

  void _onDatePresetChanged(String preset) {
    _loadPreset = preset;
    _loadData();
  }

  @override
  void dispose() {
    ScreenRefreshNotifier.attendanceSummary.removeListener(_onExternalRefresh);
    super.dispose();
  }

  /// [silent] true sau chỉnh công — tải lại không che màn hình, giữ vị trí bảng.
  Future<void> _loadData({bool silent = false}) async {
    if (!mounted) return;
    final isEmployee = isEmployeeUserRole(
      context.read<AuthProvider>().user?.role,
    );
    if (!silent) {
      setState(() {
        _isLoading = true;
        _loadMessage = 'Đang tải dữ liệu...';
      });
    }

    try {
      await _branchFilter.ensureEmployees(
        _apiService,
        branchId: _selectedBranchId,
      );
      if (!mounted) return;

      final range = AttendanceDateRangePresets.resolve(_loadPreset);
      _fromDate = range.start;
      _toDate = range.end;
      final toStr = _toDate.toIso8601String().substring(0, 10);

      // NV: không gọi getDevices (API manager) — server tự resolve máy khi deviceIds rỗng.
      final phase1 = await Future.wait([
        isEmployee
            ? Future<List<dynamic>>.value([])
            : _apiService.getDevices(storeOnly: true),
        _apiService
            .getAppSetting('day_end_time')
            .catchError((_) => <String, dynamic>{}),
        _apiService
            .getAppSetting('allow_manual_correction')
            .catchError((_) => <String, dynamic>{}),
        _apiService
            .getAppSetting('min_hours_for_work_day')
            .catchError((_) => <String, dynamic>{}),
        _apiService
            .getAppSetting('decimal_work_day_enabled')
            .catchError((_) => <String, dynamic>{}),
        _apiService.getSalarySettings().catchError((_) => <String, dynamic>{}),
      ]);

      final devicesRaw = phase1[0] as List;
      final devices = devicesRaw
          .map((d) => Device.fromJson(d as Map<String, dynamic>))
          .toList();
      final deviceIds = devices.map((d) => d.id).toList();

      int deh = 0, dem = 0;
      final dayEndResult = phase1[1] as Map<String, dynamic>;
      if (dayEndResult['isSuccess'] == true && dayEndResult['data'] is Map) {
        final value =
            (dayEndResult['data'] as Map)['value']?.toString() ?? '00:00:00';
        final parts = value.split(':');
        if (parts.length >= 2) {
          deh = int.tryParse(parts[0]) ?? 0;
          dem = int.tryParse(parts[1]) ?? 0;
        }
      }

      bool allowManual = true;
      final amcResult = phase1[2] as Map<String, dynamic>;
      if (amcResult['isSuccess'] == true && amcResult['data'] is Map) {
        allowManual =
            (amcResult['data'] as Map)['value']?.toString() != 'false';
      }

      double minHoursForWorkDay = 0;
      final minHoursResult = phase1[3] as Map<String, dynamic>;
      if (minHoursResult['isSuccess'] == true && minHoursResult['data'] is Map) {
        minHoursForWorkDay = parseMinHoursForWorkDay(
          appSettingValue:
              (minHoursResult['data'] as Map)['value']?.toString(),
        );
      }

      var decimalWorkDayEnabled = false;
      final decimalResult = phase1[4] as Map<String, dynamic>;
      if (decimalResult['isSuccess'] == true && decimalResult['data'] is Map) {
        decimalWorkDayEnabled = parseDecimalWorkDayEnabled(
          appSettingValue:
              (decimalResult['data'] as Map)['value']?.toString(),
        );
      }

      final salarySettings = phase1[5] as Map<String, dynamic>;
      _salarySettings = salarySettings;
      if (minHoursForWorkDay == 0) {
        minHoursForWorkDay = parseMinHoursForWorkDay(salarySettings: salarySettings);
      }
      if (!decimalWorkDayEnabled) {
        decimalWorkDayEnabled =
            parseDecimalWorkDayEnabled(salarySettings: salarySettings);
      }
      final standardWorkHours = parseStandardWorkHours(salarySettings: salarySettings);

      final fetchFrom = AttendanceDateRangePresets.fetchFromDate(
        _fromDate,
        dayEndHour: deh,
        dayEndMinute: dem,
      );
      final fromStr = fetchFrom.toIso8601String().substring(0, 10);

      if (mounted) {
        setState(() => _loadMessage = 'Đang tải log chấm công...');
      }

      // Log + metadata song song (log có tiến trình từng trang)
      final attendancesFuture = loadAttendancesForPeriodResult(
        _apiService,
        deviceIds: deviceIds,
        fromDate: _fromDate,
        toDate: _toDate,
        dayEndHour: deh,
        dayEndMinute: dem,
        pageSize: 1000,
        parallelPages: 6,
        onProgress: (msg) {
          if (mounted) setState(() => _loadMessage = msg);
        },
      );

      final metadataFuture = Future.wait([
        _apiService.getShifts().catchError((_) => <dynamic>[]),
        _apiService
            .getShiftSalaryLevels()
            .catchError((_) => <String, dynamic>{}),
        _apiService
            .getHolidaySettings(0)
            .catchError((_) => <dynamic>[]),
        loadAttendanceSalaryProfiles(
          _apiService,
          preferSelfServiceApi: isEmployee,
        ),
        loadLeavesForPeriod(
          _apiService,
          fromDate: fromStr,
          toDate: toStr,
          status: 'Approved',
        ).catchError((_) => <dynamic>[]),
        loadLeavesForPeriod(
          _apiService,
          fromDate: fromStr,
          toDate: toStr,
          status: 'Pending',
        ).catchError((_) => <dynamic>[]),
        (isEmployee
                ? _apiService.getMyWorkSchedules(
                    fromDate: _fromDate,
                    toDate: _toDate,
                    pageSize: 1000,
                  )
                : _apiService.getWorkSchedules(
                    fromDate: _fromDate,
                    toDate: _toDate,
                    pageSize: 1000,
                  ))
            .catchError((_) => <String, dynamic>{}),
      ]);

      final phase2 = await Future.wait([
        attendancesFuture,
        metadataFuture,
        loadTravelHoursMaps(
          api: _apiService,
          fromDate: _fromDate,
          toDate: _toDate,
          employeesList: _branchFilter.employees,
        ),
        loadTravelEligibleEmployeeKeys(
          _apiService,
          employeesList: _branchFilter.employees,
        ),
      ]);
      final attLoad = phase2[0] as AttendanceLoadResult;
      final attendances = attLoad.items;
      final results = phase2[1] as List;
      final travelMaps = phase2[2] as TravelHoursMaps;
      final travelEligibleKeys = phase2[3] as Set<String>;

      final shiftsRaw = results[0] as List;
      final shiftTemplates = shiftsRaw
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList();
      final salaryLevelsResult = results[1] as Map<String, dynamic>;
      final shiftSalaryLevels = ((salaryLevelsResult['data']?['items'] ??
              salaryLevelsResult['data'] ??
              []) as List)
          .map((s) => Map<String, dynamic>.from(s as Map))
          .toList();

      final holidays = results[2] as List<dynamic>;
      final salaryProfiles = List<Map<String, dynamic>>.from(results[3] as List);

      final approvedLeaves = [
        ...(results[4] as List<dynamic>),
        ...(results[5] as List<dynamic>),
      ];
      final workSchedules = extractWorkScheduleItems(
        results[6] is Map<String, dynamic>
            ? results[6] as Map<String, dynamic>
            : <String, dynamic>{},
      );

      if (mounted) {
        setState(() {
          _devices = devices;
          _attendances = attendances;
          _dayEndHour = deh;
          _dayEndMinute = dem;
          _minHoursForWorkDay = minHoursForWorkDay;
          _decimalWorkDayEnabled = decimalWorkDayEnabled;
          _standardWorkHours = standardWorkHours;
          _holidays = holidays;
          _salaryProfiles = salaryProfiles;
          _shiftTemplates = shiftTemplates;
          _shiftSalaryLevels = shiftSalaryLevels;
          _approvedLeaves = approvedLeaves;
          _workSchedules = workSchedules;
          _allowManualCorrection = allowManual;
          _attendanceLoadTruncated = attLoad.truncated;
          _attendanceExpectedCount = attLoad.totalCount;
          _travelHoursByEmployeeKey = travelMaps.byEmployeeKey;
          _travelHoursByEmployeeDateKey = travelMaps.byEmployeeDateKey;
          _travelEligibleEmployeeKeys = travelEligibleKeys;
          if (!silent) _isLoading = false;
        });
        if (attLoad.isIncomplete && mounted) {
          final tc = attLoad.totalCount;
          final msg = tc != null && tc > attendances.length
              ? 'Đã tải ${attendances.length} / $tc log. Thiếu dữ liệu cuối kỳ — vuốt xuống tải lại hoặc thu hẹp ngày.'
              : 'Đã tải ${attendances.length} log (có thể chưa đủ).';
          appNotification.showWarning(
            title: 'Dữ liệu chấm công chưa đủ',
            message: msg,
          );
        }
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted && !silent) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Widget> _summaryPageChromeSections() => [
          if (_salaryProfiles.isEmpty &&
              !_isLoading &&
              !isEmployeeUserRole(
                context.watch<AuthProvider>().user?.role,
              ))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
              child: Material(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 18, color: Colors.blue.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr('Chưa có bảng lương cấu hình — hệ số ngày lễ/nghỉ trong tổng hợp có thể không chính xác. '
                          'Vào Thiết lập lương để cấu hình.'),
                          style: TextStyle(
                              fontSize: 12, color: Colors.blue.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (BranchFilterHelper.showBranchFilter(_branchFilter.branches) ||
              DepartmentFilterHelper.showDepartmentFilter(
                  _branchFilter.departments))
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: ReportOrgFilterRow(
                dense: true,
                orgFilter: _branchFilter,
                selectedBranchId: _selectedBranchId,
                onBranchChanged: (v) async {
                  await _branchFilter.ensureEmployees(
                    _apiService,
                    branchId: v,
                  );
                  if (mounted) setState(() => _selectedBranchId = v);
                },
                selectedDepartmentId: _selectedDepartmentId,
                onDepartmentChanged: (v) {
                  if (mounted) setState(() => _selectedDepartmentId = v);
                },
              ),
            ),
          if (_attendanceLoadTruncated ||
              (_attendanceExpectedCount != null &&
                  _attendances.length < _attendanceExpectedCount!))
            Material(
              color: const Color(0xFFFFF7ED),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 20, color: Colors.orange.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr(_attendanceExpectedCount != null
                            ? 'Chỉ tải được ${_attendances.length} / ${_attendanceExpectedCount!} log chấm công — báo cáo có thể thiếu ngày cuối tháng.'
                            : 'Log chấm công có thể chưa đủ — kéo xuống để tải lại.'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade900,
                          height: 1.35,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _loadData,
                      child: Text(tr('Tải lại')),
                    ),
                  ],
                ),
              ),
            ),
      ];

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final chrome = _summaryPageChromeSections();
    final auth = context.watch<AuthProvider>();
    final perm = context.watch<PermissionProvider>();
    final canShowButtons = canShowCorrectionButtons(
      role: auth.user?.role,
      allowManualSetting: _allowManualCorrection,
      permissions: perm,
    );
    final canDirectCorrection = canDirectAttendanceCorrection(
      role: auth.user?.role,
      allowManualSetting: _allowManualCorrection,
      permissions: perm,
    );

    final topActions = <Widget>[
      HrmTopBarAction(
        icon: Icons.image_outlined,
        label: 'Xuất PNG',
        onPressed: () => (_tabKey.currentState as dynamic)?.exportToPng(),
      ),
      HrmTopBarAction(
        icon: Icons.table_chart_outlined,
        label: 'Xuất Excel',
        onPressed: () => (_tabKey.currentState as dynamic)?.exportToExcel(),
      ),
    ];

    return RegisterPageTopActions(
      actions: topActions,
      child: Scaffold(
        backgroundColor: HrmPageChrome.background,
        body: Column(
          children: [
            ...chrome,
            Expanded(
            child: _isLoading
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            tr(_loadMessage),
                            textAlign: TextAlign.center,
                            style: vietnameseTextStyle(const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF52525B),
                            )),
                          ),
                        ],
                      ),
                    ),
                  )
                : AttendanceSummaryTab(
                    key: _tabKey,
                    attendances: _filteredAttendances,
                    devices: _devices,
                    fromDate: _fromDate,
                    toDate: _toDate,
                    dateRangePreset: _loadPreset,
                    onDateRangeChanged: _onDatePresetChanged,
                    onCorrectionRequest: _handleCorrectionRequest,
                    dayEndHour: _dayEndHour,
                    dayEndMinute: _dayEndMinute,
                    minHoursForWorkDay: _minHoursForWorkDay,
                    decimalWorkDayEnabled: _decimalWorkDayEnabled,
                    standardWorkHours: _standardWorkHours,
                    holidays: _holidays,
                    salaryProfiles: _salaryProfiles,
                    storeSalarySettings: _salarySettings,
                    shiftTemplates: _shiftTemplates,
                    shiftSalaryLevels: _shiftSalaryLevels,
                    approvedLeaves: _approvedLeaves,
                    allowCorrection: canShowButtons,
                    directApplyCorrections: canDirectCorrection,
                    branches: _branchFilter.branches,
                    employeesList: _orgEmployees,
                    onDataChanged: () => _loadData(),
                    travelHoursByEmployeeKey: _travelHoursByEmployeeKey,
                    travelHoursByEmployeeDateKey: _travelHoursByEmployeeDateKey,
                    travelEligibleEmployeeKeys: _travelEligibleEmployeeKeys,
                    workSchedules: _workSchedules,
                  ),
          ),
        ],
      ),
      ),
    );
  }

  /// Gửi yêu cầu chấm công lên backend → Xử lý yêu cầu CC
  Future<void> _handleCorrectionRequest(
      AttendanceCorrectionRequest request) async {
    // Map correctionType string → backend Action enum int
    int action;
    switch (request.correctionType) {
      case 'add':
        action = 0;
        break;
      case 'edit':
        action = 1;
        break;
      case 'delete':
        action = 2;
        break;
      default:
        action = 0;
    }

    // Parse thời gian yêu cầu
    String? newTime;
    DateTime? newDate;
    String? oldTime;
    DateTime? oldDate;

    if (request.correctionType == 'add' || request.correctionType == 'edit') {
      final t = request.requestedTime;
      newTime = t.contains(':') && t.split(':').length == 2 ? '$t:00' : t;
      newDate = DateTime(
        request.correctionDate.year,
        request.correctionDate.month,
        request.correctionDate.day,
      );
    }
    if (request.correctionType == 'edit' ||
        request.correctionType == 'delete') {
      if (request.originalTime != null) {
        oldTime = correctionTimeOnly(request.originalTime!);
        oldDate = DateTime(
          request.originalTime!.year,
          request.originalTime!.month,
          request.originalTime!.day,
        );
      }
    }

    try {
      final perm = context.read<PermissionProvider>();
      final auth = context.read<AuthProvider>();
      final expectedDirect = canDirectAttendanceCorrection(
        role: auth.user?.role,
        allowManualSetting: _allowManualCorrection,
        permissions: perm,
      );

      if (request.correctionType == 'edit' &&
          !isValidAttendanceGuid(request.attendanceId)) {
        if (mounted) {
          NotificationOverlayManager().showError(
            title: 'Lỗi',
            message: tr('Không xác định được bản ghi chấm công. Vui lòng tải lại dữ liệu.'),
          );
        }
        return;
      }
      if (request.correctionType == 'delete' &&
          !isValidAttendanceGuid(request.attendanceId) &&
          request.originalTime == null) {
        if (mounted) {
          NotificationOverlayManager().showError(
            title: 'Lỗi',
            message: tr('Không xác định được giờ chấm công cần xóa. Vui lòng tải lại dữ liệu.'),
          );
        }
        return;
      }

      Map<String, dynamic> success;

      if (request.correctionType == 'delete') {
        success = await submitAttendanceDelete(
          api: _apiService,
          expectedDirect: expectedDirect,
          attendanceId: request.attendanceId,
          createCorrection: () => _apiService.createAttendanceCorrection(
            action: action,
            pin: request.pin,
            employeeName: request.employeeName,
            employeeCode: request.employeeCode,
            employeeUserId: request.employeeUserId,
            attendanceId: request.attendanceId,
            oldDate: oldDate,
            oldTime: oldTime,
            newDate: newDate,
            newTime: newTime,
            newType: request.newType,
            reason: request.reason,
            targetApproverId: request.approverId,
            targetApproverName: request.approverName,
          ),
        );
      } else {
        success = await _apiService.createAttendanceCorrection(
          action: action,
          pin: request.pin,
          employeeName: request.employeeName,
          employeeCode: request.employeeCode,
          employeeUserId: request.employeeUserId,
          attendanceId: request.attendanceId,
          oldDate: oldDate,
          oldTime: oldTime,
          newDate: newDate,
          newTime: newTime,
          newType: request.newType,
          reason: request.reason,
          targetApproverId: request.approverId,
          targetApproverName: request.approverName,
        );
      }

      if (mounted) {
        if (success['isSuccess'] == true) {
          await _loadData(silent: true);
          if (mounted) {
            final directDelete = success['directDelete'] == true;
            final msg = (request.correctionType == 'delete' && directDelete)
                ? (success['message']?.toString().isNotEmpty == true
                    ? success['message'].toString()
                    : 'Đã xóa chấm công')
                : attendanceCorrectionSuccessMessage(
                    success,
                    expectedDirect: expectedDirect,
                  );
            NotificationOverlayManager().showSuccess(
                title: 'Thành công', message: msg);
          }
        } else {
          final errMsg = attendanceCorrectionErrorMessage(success);
          NotificationOverlayManager().showError(
              title: 'Lỗi', message: errMsg);
        }
      }
    } catch (e) {
      debugPrint('Error creating correction request: $e');
      if (mounted) {
        NotificationOverlayManager()
            .showError(title: 'Lỗi', message: tr('Lỗi: $e'));
      }
    }
  }

  static List<dynamic> _parseLeaveItems(Map<String, dynamic> result) {
    if (result['isSuccess'] != true) return [];
    final data = result['data'];
    if (data is Map) return (data['items'] as List?) ?? [];
    if (data is List) return data;
    return [];
  }

  Widget _buildHeaderActionBtn(
      IconData icon, String tooltip, VoidCallback? onTap) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
