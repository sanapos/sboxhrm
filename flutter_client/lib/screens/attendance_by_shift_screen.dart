import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../widgets/hrm_page_chrome.dart';
import 'package:intl/intl.dart';
import '../models/attendance.dart';
import '../models/device.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import 'attendance/attendance_by_shift_tab.dart';
import 'attendance/attendance_summary_tab.dart'
    show AttendanceCorrectionRequest;
import 'main_layout.dart' show ScreenRefreshNotifier;
import '../widgets/notification_overlay.dart';
import '../utils/attendance_load_utils.dart';
import '../utils/attendance_date_range_presets.dart';
import '../utils/report_screen_helpers.dart';
import '../utils/attendance_correction_privilege.dart';
import '../utils/vietnamese_font.dart';

/// M\u00e0n h\u00ecnh t\u1ed5ng h\u1ee3p ch\u1ea5m c\u00f4ng theo ca \u2014 wrapper cho [AttendanceByShiftTab].
class AttendanceByShiftScreen extends StatefulWidget {
  const AttendanceByShiftScreen({super.key});

  @override
  State<AttendanceByShiftScreen> createState() =>
      _AttendanceByShiftScreenState();
}

class _AttendanceByShiftScreenState extends State<AttendanceByShiftScreen> {
  final ApiService _apiService = ApiService();
  final _tabKey = GlobalKey();

  List<Attendance> _attendances = [];
  List<Device> _devices = [];
  List<Map<String, dynamic>> _shiftTemplates = [];
  List<Map<String, dynamic>> _shiftSalaryLevels = [];
  String? _selectedBranchId;
  final _branchFilter = ReportBranchFilter();
  List<Map<String, dynamic>> _salaryProfiles = [];
  List<dynamic> _holidays = [];
  List<dynamic> _approvedLeaves = [];
  int _dayEndHour = 0;
  int _dayEndMinute = 0;
  bool _isLoading = true;
  // ignore: unused_field
  bool _allowManualCorrection = true;

  String _loadPreset = 'month';
  late DateTime _fromDate;
  late DateTime _toDate;

  _AttendanceByShiftScreenState() {
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
    ScreenRefreshNotifier.attendanceByShift.addListener(_onExternalRefresh);
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
    ScreenRefreshNotifier.attendanceByShift.removeListener(_onExternalRefresh);
    super.dispose();
  }

  /// [silent] true khi sửa/xóa/thêm chấm công — không overlay loading (giữ vị trí cuộn).
  Future<void> _loadData({bool silent = false}) async {
    if (!mounted) return;
    if (!silent) {
      setState(() => _isLoading = true);
    }

    try {
      await _branchFilter.ensureEmployees(_apiService);
      // Load devices \u2014 d\u00f9ng getDevices(storeOnly: true) \u0111\u1ec3 l\u1ea5y thi\u1ebft b\u1ecb trong store
      final devicesRaw = await _apiService.getDevices(storeOnly: true);
      final devices = (devicesRaw)
          .map((d) => Device.fromJson(d as Map<String, dynamic>))
          .toList();

      final deviceIds = devices.map((d) => d.id).toList();

      final dayEndResult = await _apiService
          .getAppSetting('day_end_time')
          .catchError((_) => <String, dynamic>{});
      int deh = 0, dem = 0;
      if (dayEndResult['isSuccess'] == true && dayEndResult['data'] is Map) {
        final data = dayEndResult['data'] as Map;
        final value = data['value']?.toString() ?? '00:00:00';
        final parts = value.split(':');
        if (parts.length >= 2) {
          deh = int.tryParse(parts[0]) ?? 0;
          dem = int.tryParse(parts[1]) ?? 0;
        }
      }

      final range = AttendanceDateRangePresets.resolve(_loadPreset);
      _fromDate = range.start;
      _toDate = range.end;
      final fetchFrom = AttendanceDateRangePresets.fetchFromDate(
        _fromDate,
        dayEndHour: deh,
        dayEndMinute: dem,
      );
      final fromStr = fetchFrom.toIso8601String().substring(0, 10);
      final toStr = _toDate.toIso8601String().substring(0, 10);

      final attLoad = await loadAttendancesForPeriodResult(
        _apiService,
        deviceIds: deviceIds,
        fromDate: _fromDate,
        toDate: _toDate,
        dayEndHour: deh,
        dayEndMinute: dem,
        pageSize: 1000,
      );
      final attendances = attLoad.items;

      final p2 = await Future.wait([
        _apiService.getShifts().catchError((_) => <dynamic>[]),
        _apiService
            .getShiftSalaryLevels()
            .catchError((_) => <String, dynamic>{}),
        _apiService.getSalaryProfiles().catchError((_) => <dynamic>[]),
        _apiService.getHolidaySettings(0).catchError((_) => <dynamic>[]),
        _apiService
            .getAppSetting('allow_manual_correction')
            .catchError((_) => <String, dynamic>{}),
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

      final shiftsRaw = p2[0] as List;
      final shiftTemplates =
          shiftsRaw.map((s) => s as Map<String, dynamic>).toList();

      final salaryLevelsResult = p2[1] as Map<String, dynamic>;
      final shiftSalaryLevels = ((salaryLevelsResult['data']?['items'] ??
              salaryLevelsResult['data'] ??
              []) as List)
          .map((s) => s as Map<String, dynamic>)
          .toList();

      final salaryProfilesRaw = p2[2] as List;
      final salaryProfiles =
          salaryProfilesRaw.map((s) => s as Map<String, dynamic>).toList();

      final holidaysResult = p2[3] as List<dynamic>;

      bool allowManual = true;
      final allowManualResult = p2[4] as Map<String, dynamic>;
      if (allowManualResult['isSuccess'] == true &&
          allowManualResult['data'] is Map) {
        allowManual =
            (allowManualResult['data'] as Map)['value']?.toString() != 'false';
      }

      final approvedLeaves = [
        ...(p2[5] as List<dynamic>),
        ...(p2[6] as List<dynamic>),
      ];

      if (mounted) {
        setState(() {
          _devices = devices;
          _attendances = attendances;
          _shiftTemplates = shiftTemplates;
          _shiftSalaryLevels = shiftSalaryLevels;
          _salaryProfiles = salaryProfiles;
          _holidays = holidaysResult;
          _approvedLeaves = approvedLeaves;
          _dayEndHour = deh;
          _dayEndMinute = dem;
          _allowManualCorrection = allowManual;
          if (!silent) _isLoading = false;
        });
        if (attLoad?.truncated == true && mounted) {
          appNotification.showWarning(
            title: 'Dữ liệu có thể chưa đủ',
            message:
                'Đã tải ${attendances.length} log. Thu hẹp khoảng ngày nếu thiếu ngày gần đây.',
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

  List<Widget> _byShiftPageChromeSections(bool isMobile, Color primary) => [
        Container(
            padding: EdgeInsets.fromLTRB(
                isMobile ? 14 : 24, 18, isMobile ? 14 : 24, 18),
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
                if (!isMobile)
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.view_timeline,
                        size: 22, color: Colors.white),
                  ),
                if (!isMobile) const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'T\u1ed5ng h\u1ee3p ch\u1ea5m c\u00f4ng theo ca',
                        style: vietnameseTextStyle(TextStyle(
                            fontSize: isMobile ? 16 : 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                      ),
                      Text(
                        'T\u1ed5ng h\u1ee3p ch\u1ea5m c\u00f4ng theo ca \u00b7 ${_attendances.length} b\u1ea3n ghi',
                        style: vietnameseTextStyle(TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.8))),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isMobile)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    onSelected: (value) {
                      if (value == 'excel') {
                        (_tabKey.currentState as dynamic)?.exportToExcel();
                      } else if (value == 'png') {
                        (_tabKey.currentState as dynamic)?.exportToPng();
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                          value: 'excel',
                          child: Row(children: [
                            const Icon(Icons.table_chart_outlined, size: 18),
                            const SizedBox(width: 8),
                            Text('Xu\u1ea5t Excel', style: vietnameseTextStyle())
                          ])),
                      PopupMenuItem(
                          value: 'png',
                          child: Row(children: [
                            const Icon(Icons.image_outlined, size: 18),
                            const SizedBox(width: 8),
                            Text('Xu\u1ea5t PNG', style: vietnameseTextStyle())
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
          if (_salaryProfiles.isEmpty && !_isLoading)
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
                          'Ch\u01b0a c\u00f3 b\u1ea3ng l\u01b0\u01a1ng c\u1ea5u h\u00ecnh \u2014 h\u1ec7 s\u1ed1 ca/l\u01b0\u01a1ng c\u00f3 th\u1ec3 kh\u00f4ng ch\u00ednh x\u00e1c. '
                          'V\u00e0o Thi\u1ebft l\u1eadp l\u01b0\u01a1ng \u0111\u1ec3 c\u1ea5u h\u00ecnh.',
                          style: vietnameseTextStyle(TextStyle(
                              fontSize: 12, color: Colors.blue.shade900)),
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
                          key: ValueKey('branch_$_selectedBranchId'),
                          value: _selectedBranchId,
                          isExpanded: true,
                          isDense: true,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF111827)),
                          icon: const Icon(Icons.keyboard_arrow_down,
                              size: 18, color: Color(0xFF9CA3AF)),
                          items: [
                            DropdownMenuItem<String?>(
                                value: null,
                                child: Text('T\u1ea5t c\u1ea3 chi nh\u00e1nh',
                                    style: vietnameseTextStyle(
                                        const TextStyle(fontSize: 13)))),
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
    final isMobile = Responsive.isMobile(context);
    final chrome = _byShiftPageChromeSections(isMobile, primary);
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: AttendanceByShiftTab(
                    key: _tabKey,
                    attendances: _filteredAttendances,
                    devices: _devices,
                    fromDate: _fromDate,
                    toDate: _toDate,
                    dateRangePreset: _loadPreset,
                    shiftTemplates: _shiftTemplates,
                    shiftSalaryLevels: _shiftSalaryLevels,
                    salaryProfiles: _salaryProfiles,
                    holidays: _holidays,
                    approvedLeaves: _approvedLeaves,
                    employeesList: _branchFilter.employees,
                    dayEndHour: _dayEndHour,
                    dayEndMinute: _dayEndMinute,
                    allowCorrection: canShowButtons,
                    directApplyCorrections: canDirectCorrection,
                    onDataChanged: () => _loadData(silent: true),
                    onDateRangeChanged: _onDatePresetChanged,
                  ),
                ),
                if (_isLoading)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: Colors.white.withValues(alpha: 0.72),
                        child: Center(
                          child: Card(
                            elevation: 4,
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const CircularProgressIndicator(),
                                  const SizedBox(height: 12),
                                  Text('Đang tải dữ liệu…',
                                      style: vietnameseTextStyle(
                                          const TextStyle(fontSize: 13))),
                                ],
                              ),
                            ),
                          ),
                        ),
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

  /// G\u1eedi y\u00eau c\u1ea7u ch\u1ea5m c\u00f4ng l\u00ean backend \u2014 x\u1eed l\u00fd y\u00eau c\u1ea7u CC
  // ignore: unused_element
  Future<void> _handleCorrectionRequest(
      AttendanceCorrectionRequest request) async {
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

    String? newTime;
    DateTime? newDate;
    String? oldTime;
    DateTime? oldDate;

    if (request.correctionType == 'add' || request.correctionType == 'edit') {
      // Backend expects TimeSpan format "HH:mm:ss"
      final t = request.requestedTime; // "HH:mm"
      newTime = t.contains(':') && t.split(':').length == 2 ? '$t:00' : t;
      newDate = request.correctionDate;
    }
    if (request.correctionType == 'edit' ||
        request.correctionType == 'delete') {
      if (request.originalTime != null) {
        oldTime = DateFormat('HH:mm:ss').format(request.originalTime!);
        oldDate = request.correctionDate;
      }
    }

    try {
      final success = await _apiService.createAttendanceCorrection(
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

      if (mounted) {
        if (success['isSuccess'] == true) {
          // Reload data to reflect changes
          await _loadData();
          if (mounted) {
            NotificationOverlayManager().showSuccess(
                title: 'Th\u00e0nh c\u00f4ng',
                message: '\u0110\u00e3 g\u1eedi y\u00eau c\u1ea7u ch\u1ea5m c\u00f4ng th\u00e0nh c\u00f4ng');
          }
        } else {
          NotificationOverlayManager().showError(
              title: 'L\u1ed7i',
              message: attendanceCorrectionErrorMessage(success));
        }
      }
    } catch (e) {
      debugPrint('Error creating correction request: $e');
      if (mounted) {
        NotificationOverlayManager()
            .showError(title: 'L\u1ed7i', message: 'L\u1ed7i: $e');
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
      IconData icon, String label, VoidCallback? onTap) {
    return Material(
      color: Colors.white.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(label,
                  style: vietnameseTextStyle(const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w600))),
            ],
          ),
        ),
      ),
    );
  }
}
