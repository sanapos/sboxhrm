import 'package:flutter/material.dart';
import '../models/attendance.dart';
import '../models/device.dart';
import '../services/api_service.dart';
import 'attendance/attendance_summary_tab.dart';
import 'package:intl/intl.dart';
import 'main_layout.dart' show ScreenRefreshNotifier;
import '../utils/responsive_helper.dart';
import '../widgets/notification_overlay.dart';

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
    ScreenRefreshNotifier.attendanceSummary.addListener(_onExternalRefresh);
  }

  void _onExternalRefresh() {
    if (mounted) {
      _loadData();
    }
  }

  @override
  void dispose() {
    ScreenRefreshNotifier.attendanceSummary.removeListener(_onExternalRefresh);
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

      // Load day_end_time setting
      int deh = 0, dem = 0;
      try {
        final dayEndResult = await _apiService.getAppSetting('day_end_time');
        if (dayEndResult['isSuccess'] == true && dayEndResult['data'] is Map) {
          final data = dayEndResult['data'] as Map;
          final value = data['value']?.toString() ?? '00:00:00';
          final parts = value.split(':');
          if (parts.length >= 2) {
            deh = int.tryParse(parts[0]) ?? 0;
            dem = int.tryParse(parts[1]) ?? 0;
          }
        }
      } catch (e) {
        debugPrint('Load day end time error: $e');
      }

      if (mounted) {
        setState(() {
          _devices = devices;
          _attendances = attendances;
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

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          // Gradient header
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
                  padding: EdgeInsets.all(Responsive.isMobile(context) ? 8 : 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.analytics, size: Responsive.isMobile(context) ? 18 : 22, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tổng hợp chấm công',
                        style: TextStyle(fontSize: Responsive.isMobile(context) ? 16 : 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      if (!Responsive.isMobile(context))
                        Text(
                          'Tổng hợp dữ liệu chấm công theo nhân viên và ngày · ${_attendances.length} bản ghi',
                          style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8)),
                        ),
                    ],
                  ),
                ),
                if (Responsive.isMobile(context))
                  PopupMenuButton<String>(
                    icon: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.more_vert, size: 18, color: Colors.white),
                    ),
                    onSelected: (v) {
                      if (v == 'excel') (_tabKey.currentState as dynamic)?.exportToExcel();
                      if (v == 'png') (_tabKey.currentState as dynamic)?.exportToPng();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'excel', child: Row(children: [Icon(Icons.table_chart_outlined, size: 18), SizedBox(width: 10), Text('Xuất Excel')])),
                      PopupMenuItem(value: 'png', child: Row(children: [Icon(Icons.image_outlined, size: 18), SizedBox(width: 10), Text('Xuất PNG')])),
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
                : AttendanceSummaryTab(
                    key: _tabKey,
                    attendances: _attendances,
                    devices: _devices,
                    fromDate: _fromDate,
                    toDate: _toDate,
                    onCorrectionRequest: _handleCorrectionRequest,
                    dayEndHour: _dayEndHour,
                    dayEndMinute: _dayEndMinute,
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
        pin: request.pin, // PIN để backend tìm đúng nhân viên
        employeeName: request.employeeName, // Tên nhân viên gửi trực tiếp
        employeeCode: request.employeeCode, // Mã nhân viên gửi trực tiếp
        employeeUserId: request.employeeUserId,
        attendanceId: request.attendanceId,
        oldDate: oldDate,
        oldTime: oldTime,
        newDate: newDate,
        newTime: newTime,
        newType: request.newType, // 'CheckIn', 'CheckOut', or null for auto
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

  Widget _buildHeaderActionBtn(IconData icon, String tooltip, VoidCallback? onTap) {
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
