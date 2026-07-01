import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../utils/attendance_correction_privilege.dart';
import '../widgets/hrm_page_chrome.dart';
import '../models/attendance.dart';
import '../models/device.dart';
import '../services/api_service.dart';
import '../utils/travel_hours_load_utils.dart';
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
import '../utils/report_screen_helpers.dart';
import '../utils/salary_profile_load_utils.dart';

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
  String? _selectedBranchId;
  final _branchFilter = ReportBranchFilter();
  int _dayEndHour = 0;
  int _dayEndMinute = 0;
  bool _isLoading = true;
  String _loadMessage = 'Đang tải dữ liệu...';
  bool _allowManualCorrection = true;

  String _loadPreset = 'month';
  late DateTime _fromDate;
  late DateTime _toDate;
  bool _attendanceLoadTruncated = false;
  Map<String, double> _travelHoursByEmployeeKey = {};
  Map<String, double> _travelHoursByEmployeeDateKey = {};

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
    await _branchFilter.loadBranches(_apiService);
    if (mounted) setState(() {});
  }

  List<Attendance> get _filteredAttendances {
    if (_selectedBranchId == null) return _attendances;
    final branchCodes = _branchFilter.codesForBranch(_selectedBranchId);
    if (branchCodes.isEmpty) return [];
    return _attendances
        .where((a) => branchCodes.contains(a.employeeId))
        .toList();
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
      await _branchFilter.ensureEmployees(_apiService);
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
      ]);
      final attLoad = phase2[0] as AttendanceLoadResult;
      final attendances = attLoad.items;
      final results = phase2[1] as List;
      final travelMaps = phase2[2] as TravelHoursMaps;

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

      if (mounted) {
        setState(() {
          _devices = devices;
          _attendances = attendances;
          _dayEndHour = deh;
          _dayEndMinute = dem;
          _holidays = holidays;
          _salaryProfiles = salaryProfiles;
          _shiftTemplates = shiftTemplates;
          _shiftSalaryLevels = shiftSalaryLevels;
          _approvedLeaves = approvedLeaves;
          _allowManualCorrection = allowManual;
          _attendanceLoadTruncated = attLoad.truncated;
          _travelHoursByEmployeeKey = travelMaps.byEmployeeKey;
          _travelHoursByEmployeeDateKey = travelMaps.byEmployeeDateKey;
          if (!silent) _isLoading = false;
        });
        if (attLoad.truncated && mounted) {
          final tc = attLoad.totalCount;
          final msg = tc != null && tc > attendances.length
              ? 'Đã tải ${attendances.length} / $tc log chấm công.'
              : 'Đã tải ${attendances.length} log (giới hạn tải).';
          appNotification.showWarning(
            title: 'Dữ liệu có thể chưa đủ',
            message: '$msg Thu hẹp khoảng ngày nếu thiếu ngày cuối tháng.',
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

  List<Widget> _summaryPageChromeSections(Color primary) => [
        Container(
            padding: EdgeInsets.fromLTRB(
              Responsive.isMobile(context) ? 14 : 24,
              Responsive.isMobile(context) ? 12 : 18,
              Responsive.isMobile(context) ? 14 : 24,
              Responsive.isMobile(context) ? 12 : 18,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primary, primary.withValues(alpha: 0.85)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding:
                      EdgeInsets.all(Responsive.isMobile(context) ? 8 : 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.analytics,
                      size: Responsive.isMobile(context) ? 18 : 22,
                      color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tổng hợp chấm công',
                        style: vietnameseTextStyle(TextStyle(
                            fontSize: Responsive.isMobile(context) ? 16 : 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                      ),
                      if (!Responsive.isMobile(context))
                        Text(
                          'Tổng hợp dữ liệu chấm công theo nhân viên và ngày · ${_attendances.length} bản ghi',
                          style: vietnameseTextStyle(TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.8))),
                        ),
                    ],
                  ),
                ),
                if (Responsive.isMobile(context))
                  PopupMenuButton<String>(
                    icon: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.more_vert,
                          size: 18, color: Colors.white),
                    ),
                    onSelected: (v) {
                      if (v == 'excel') {
                        (_tabKey.currentState as dynamic)?.exportToExcel();
                      }
                      if (v == 'png') {
                        (_tabKey.currentState as dynamic)?.exportToPng();
                      }
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                          value: 'excel',
                          child: Row(children: [
                            const Icon(Icons.table_chart_outlined, size: 18),
                            const SizedBox(width: 10),
                            Text('Xuất Excel',
                                style: vietnameseTextStyle()),
                          ])),
                      PopupMenuItem(
                          value: 'png',
                          child: Row(children: [
                            const Icon(Icons.image_outlined, size: 18),
                            const SizedBox(width: 10),
                            Text('Xuất PNG', style: vietnameseTextStyle()),
                          ])),
                    ],
                  )
                else ...[
                  _buildHeaderActionBtn(Icons.table_chart_outlined, 'Excel',
                      () => (_tabKey.currentState as dynamic)?.exportToExcel()),
                  const SizedBox(width: 8),
                  _buildHeaderActionBtn(Icons.image_outlined, 'PNG',
                      () => (_tabKey.currentState as dynamic)?.exportToPng()),
                ],
              ],
            ),
          ),
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
                          'Chưa có bảng lương cấu hình — hệ số ngày lễ/nghỉ trong tổng hợp có thể không chính xác. '
                          'Vào Thiết lập lương để cấu hình.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.blue.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_branchFilter.branches.isNotEmpty)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE4E4E7)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.account_tree_outlined,
                        size: 16, color: Color(0xFF6B7280)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          key: const ValueKey('branch_\$_selectedBranchId'),
                          value: _selectedBranchId,
                          isExpanded: true,
                          isDense: true,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF111827)),
                          icon: const Icon(Icons.keyboard_arrow_down,
                              size: 18, color: Color(0xFF9CA3AF)),
                          items: [
                            const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('T\u1ea5t c\u1ea3 chi nh\u00e1nh',
                                    style: TextStyle(fontSize: 13))),
                            ..._branchFilter.branches.map((b) => DropdownMenuItem<String?>(
                                value: b['id']?.toString(),
                                child: Text(b['name']?.toString() ?? '',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13)))),
                          ],
                          onChanged: (v) async {
                            if (v != null) {
                              await _branchFilter.ensureEmployees(_apiService);
                            }
                            if (mounted) setState(() => _selectedBranchId = v);
                          },
                        ),
                      ),
                    ),
                    if (_selectedBranchId != null)
                      InkWell(
                        onTap: () => setState(() => _selectedBranchId = null),
                        borderRadius: BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close,
                              size: 14, color: Color(0xFF9CA3AF)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
      ];

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final chrome = _summaryPageChromeSections(primary);
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

    return Scaffold(
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
                            _loadMessage,
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
                    holidays: _holidays,
                    salaryProfiles: _salaryProfiles,
                    shiftTemplates: _shiftTemplates,
                    shiftSalaryLevels: _shiftSalaryLevels,
                    approvedLeaves: _approvedLeaves,
                    allowCorrection: canShowButtons,
                    directApplyCorrections: canDirectCorrection,
                    branches: _branchFilter.branches,
                    employeesList: _branchFilter.employees,
                    onDataChanged: () => _loadData(),
                    travelHoursByEmployeeKey: _travelHoursByEmployeeKey,
                    travelHoursByEmployeeDateKey: _travelHoursByEmployeeDateKey,
                  ),
          ),
        ],
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
            message:
                'Không xác định được bản ghi chấm công. Vui lòng tải lại dữ liệu.',
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
            message:
                'Không xác định được giờ chấm công cần xóa. Vui lòng tải lại dữ liệu.',
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
            .showError(title: 'Lỗi', message: 'Lỗi: $e');
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
