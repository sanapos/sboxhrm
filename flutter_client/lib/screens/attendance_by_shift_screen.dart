import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/attendance.dart';
import '../models/device.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import 'attendance/attendance_by_shift_tab.dart';
import 'attendance/attendance_summary_tab.dart' show AttendanceCorrectionRequest;
import 'main_layout.dart' show ScreenRefreshNotifier;
import '../widgets/notification_overlay.dart';

/// Màn hình tổng hợp theo ca - standalone wrapper cho AttendanceByShiftTab
/// Tự load dữ liệu (attendances + devices) và nhúng AttendanceByShiftTab
class AttendanceByShiftScreen extends StatefulWidget {
  const AttendanceByShiftScreen({super.key});

  @override
  State<AttendanceByShiftScreen> createState() => _AttendanceByShiftScreenState();
}

class _AttendanceByShiftScreenState extends State<AttendanceByShiftScreen> {
  final ApiService _apiService = ApiService();
  final _tabKey = GlobalKey();

  List<Attendance> _attendances = [];
  List<Device> _devices = [];
  List<Map<String, dynamic>> _shiftTemplates = [];
  List<Map<String, dynamic>> _shiftSalaryLevels = [];
  List<Map<String, dynamic>> _salaryProfiles = [];
  List<dynamic> _holidays = [];
  int _dayEndHour = 0;
  int _dayEndMinute = 0;
  bool _isLoading = true;

  final DateTime _fromDate = DateTime.now().subtract(const Duration(days: 30));
  final DateTime _toDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
    ScreenRefreshNotifier.attendanceByShift.addListener(_onExternalRefresh);
  }

  void _onExternalRefresh() {
    if (mounted) {
      _loadData();
    }
  }

  @override
  void dispose() {
    ScreenRefreshNotifier.attendanceByShift.removeListener(_onExternalRefresh);
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      // Load devices - dùng getDevices(storeOnly: true) để lấy thiết bị trong store
      final devicesRaw = await _apiService.getDevices(storeOnly: true);
      final devices = (devicesRaw)
          .map((d) => Device.fromJson(d as Map<String, dynamic>))
          .toList();

      // Load attendances from all devices
      final deviceIds = devices.map((d) => d.id).toList();

      List<Attendance> attendances = [];
      if (deviceIds.isNotEmpty) {
        final result = await _apiService.getAttendances(
          deviceIds: deviceIds,
          fromDate: _fromDate,
          toDate: _toDate,
          page: 1,
          pageSize: 500,
        );
        attendances = (result['items'] as List?)
                ?.map((item) => Attendance.fromJson(item))
                .toList() ??
            [];
      }

      // Load shift templates, shift salary levels, salary profiles, holidays, day_end_time in parallel
      final shiftsFuture = _apiService.getShifts();
      final salaryLevelsFuture = _apiService.getShiftSalaryLevels();
      final salaryProfilesFuture = _apiService.getSalaryProfiles();
      final holidaysFuture = _apiService.getHolidaySettings(0);
      final dayEndFuture = _apiService.getAppSetting('day_end_time');

      final shiftsResult = await shiftsFuture;
      final salaryLevelsResult = await salaryLevelsFuture;
      final salaryProfilesResult = await salaryProfilesFuture;
      final holidaysResult = await holidaysFuture;

      final shiftTemplates = shiftsResult
          .map((s) => s as Map<String, dynamic>)
          .toList();
      final shiftSalaryLevels = ((salaryLevelsResult['data']?['items'] ?? salaryLevelsResult['data'] ?? []) as List)
          .map((s) => s as Map<String, dynamic>)
          .toList();
      final salaryProfiles = salaryProfilesResult
          .map((s) => s as Map<String, dynamic>)
          .toList();

      // Parse day_end_time
      final dayEndResult = await dayEndFuture;
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

      if (mounted) {
        setState(() {
          _devices = devices;
          _attendances = attendances;
          _shiftTemplates = shiftTemplates;
          _shiftSalaryLevels = shiftSalaryLevels;
          _salaryProfiles = salaryProfiles;
          _holidays = holidaysResult;
          _dayEndHour = deh;
          _dayEndMinute = dem;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.primaryColor;
    final isMobile = Responsive.isMobile(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          // Gradient header
          Container(
            padding: EdgeInsets.fromLTRB(isMobile ? 14 : 24, 18, isMobile ? 14 : 24, 18),
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
                    child: const Icon(Icons.view_timeline, size: 22, color: Colors.white),
                  ),
                if (!isMobile) const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tổng hợp theo ca',
                        style: TextStyle(fontSize: isMobile ? 16 : 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        'Tổng hợp chấm công theo ca · ${_attendances.length} bản ghi',
                        style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8)),
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
                      const PopupMenuItem(value: 'excel', child: Row(children: [Icon(Icons.table_chart_outlined, size: 18), SizedBox(width: 8), Text('Xuất Excel')])),
                      const PopupMenuItem(value: 'png', child: Row(children: [Icon(Icons.image_outlined, size: 18), SizedBox(width: 8), Text('Xuất PNG')])),
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
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : AttendanceByShiftTab(
                    key: _tabKey,
                    attendances: _attendances,
                    devices: _devices,
                    fromDate: _fromDate,
                    toDate: _toDate,
                    shiftTemplates: _shiftTemplates,
                    shiftSalaryLevels: _shiftSalaryLevels,
                    salaryProfiles: _salaryProfiles,
                    holidays: _holidays,
                    dayEndHour: _dayEndHour,
                    dayEndMinute: _dayEndMinute,
                    onDataChanged: _loadData,
                  ),
          ),
        ],
      ),
    );
  }

  /// Gửi yêu cầu chấm công lên backend → Xử lý yêu cầu CC
  // ignore: unused_element
  Future<void> _handleCorrectionRequest(AttendanceCorrectionRequest request) async {
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
    if (request.correctionType == 'edit' || request.correctionType == 'delete') {
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
            NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã gửi yêu cầu chấm công thành công');
          }
        } else {
          NotificationOverlayManager().showError(title: 'Lỗi', message: 'Gửi yêu cầu thất bại. Vui lòng thử lại.');
        }
      }
    } catch (e) {
      debugPrint('Error creating correction request: $e');
      if (mounted) {
        NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi: $e');
      }
    }
  }

  Widget _buildHeaderActionBtn(IconData icon, String label, VoidCallback? onTap) {
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
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
