import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import '../utils/file_saver.dart' as file_saver;
import '../utils/platform_storage.dart' as platform_storage;
import 'package:flutter/material.dart';
import '../widgets/app_scroll_safe.dart';
import '../widgets/hrm_mini_stat_chip.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_lib;
import '../models/attendance.dart';
import '../models/device.dart';
import '../models/employee.dart';
import '../services/api_service.dart';
import '../services/signalr_service.dart';
import '../utils/attendance_load_utils.dart';
import '../utils/responsive_helper.dart';
import '../utils/branch_filter_helper.dart';
import '../utils/safe_navigator.dart';
import '../widgets/loading_widget.dart';
import '../widgets/empty_state.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/safe_layout_widgets.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../utils/attendance_correction_privilege.dart';
import '../widgets/app_button.dart';
import 'attendance/attendance_correction_tab.dart'
    show CorrectionRequestInternal, CorrectionStatus;
import 'main_layout.dart' show ScreenRefreshNotifier;
import '../l10n/app_localizations.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/hrm_collapsible_overview.dart';
import '../widgets/hrm_responsive_list_layout.dart';
import '../widgets/page_top_actions.dart';
import '../widgets/employee_search_picker.dart';
import '../models/mobile_attendance.dart';
import '../widgets/map_location_picker.dart';
import '../widgets/mobile_attendance_record_detail_sheet.dart';
import '../widgets/punch_location_preview.dart';
import '../widgets/punch_photo_preview.dart';
import '../widgets/device_sync_progress_overlay.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  AppLocalizations get _l10n => AppLocalizations.of(context);
  final ApiService _apiService = ApiService();
  final AttendanceSignalRService _signalRService = AttendanceSignalRService();
  List<Attendance> _attendances = [];
  List<Device> _devices = [];
  bool _isLoading = true;
  bool _isAutoRefresh = false;
  bool _isRealtimeConnected = false;
  Timer? _refreshTimer;
  StreamSubscription<Attendance>? _attendanceSubscription;
  final ScrollController _tableScrollController = ScrollController();

  // Danh sách yêu cầu chỉnh sửa chấm công (lưu ở state cha để chia sẻ giữa các tab)
  List<CorrectionRequestInternal> _pendingCorrectionRequests = [];
  List<CorrectionRequestInternal> _processedCorrectionRequests = [];

  // LocalStorage keys
  static const String _pendingRequestsKey = 'pending_correction_requests';
  static const String _processedRequestsKey = 'processed_correction_requests';

  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _toDate = DateTime.now();
  int _dayEndHour = 0;
  int _dayEndMinute = 0;
  List<String> _selectedDevices = [];
  String _searchPin = ''; // Tìm nhanh ID/tên (header)
  String? _filterEmployeeCode; // Mã NV trên máy chấm công
  String _selectedDatePreset =
      'week'; // Preset: today, yesterday, week, lastWeek, month, lastMonth, custom
  bool _attendanceLoadTruncated = false;
  int? _attendanceServerTotalCount;
  int?
      _selectedVerifyType; // null = all, 0 = password, 1 = fingerprint, 2 = card, 15 = face
  String? _selectedBranchId;
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _employeesList = [];

  // Sorting
  String _sortColumn = 'time';
  bool _sortAscending = false;

  // Mobile UI state
  bool _showMobileSearch = false;
  bool _showOverviewPanel = true;

  // Pagination
  int _currentPage = 1;
  int _itemsPerPage = 50;
  final List<int> _pageSizeOptions = [25, 50, 100, 200];

  @override
  void initState() {
    super.initState();
    _loadCorrectionRequestsFromStorage();
    _loadDevices();
    _loadEmployeesAndBranches();
    _connectSignalR();

    // Listen for external refresh triggers
    ScreenRefreshNotifier.attendance.addListener(_onExternalRefresh);
  }

  Future<void> _loadEmployeesAndBranches() async {
    final apiService = ApiService();
    final results = await Future.wait([
      apiService.getEmployees(pageSize: 1000).catchError((_) => <dynamic>[]),
      apiService
          .getBranchesForSelect()
          .catchError((_) => <String, dynamic>{}),
    ]);
    if (!mounted) return;
    final emps = results[0] as List;
    setState(() => _employeesList =
        emps.map((e) => Map<String, dynamic>.from(e as Map)).toList());
    final br = results[1] as Map<String, dynamic>;
    final bd = br['data'];
    if (bd is List) {
      setState(() => _branches =
          bd.map((b) => Map<String, dynamic>.from(b as Map)).toList());
    }
  }

  void _onExternalRefresh() {
    if (mounted) {
      debugPrint('🔄 AttendanceScreen: External refresh triggered');
      _loadAttendances(showLoading: false);
    }
  }

  /// Load correction requests from localStorage
  void _loadCorrectionRequestsFromStorage() {
    try {
      final pendingJson = platform_storage.storageGet(_pendingRequestsKey);
      final processedJson = platform_storage.storageGet(_processedRequestsKey);

      debugPrint('📦 Loading corrections from localStorage...');
      debugPrint('   Pending JSON: ${pendingJson?.length ?? 0} chars');
      debugPrint('   Processed JSON: ${processedJson?.length ?? 0} chars');

      if (pendingJson != null && pendingJson.isNotEmpty) {
        final List<dynamic> pendingList = jsonDecode(pendingJson);
        _pendingCorrectionRequests = pendingList
            .map((e) => _correctionRequestFromJson(e as Map<String, dynamic>))
            .toList();
        debugPrint(
            '   Loaded ${_pendingCorrectionRequests.length} pending requests');
      }

      if (processedJson != null && processedJson.isNotEmpty) {
        final List<dynamic> processedList = jsonDecode(processedJson);
        _processedCorrectionRequests = processedList
            .map((e) => _correctionRequestFromJson(e as Map<String, dynamic>))
            .toList();
        debugPrint(
            '   Loaded ${_processedCorrectionRequests.length} processed requests');

        // Debug: kiểm tra các approved requests
        final approved = _processedCorrectionRequests
            .where((r) => r.status == CorrectionStatus.approved)
            .toList();
        debugPrint('   Approved requests: ${approved.length}');
        for (final r in approved) {
          debugPrint(
              '     - ${r.employeeName}: ${r.correctionType} ${r.requestedTime}');
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading correction requests: $e');
      // Xóa dữ liệu lỗi
      platform_storage.storageRemove(_pendingRequestsKey);
      platform_storage.storageRemove(_processedRequestsKey);
      _pendingCorrectionRequests = [];
      _processedCorrectionRequests = [];
    }
  }

  /// Save correction requests to localStorage
  // ignore: unused_element
  void _saveCorrectionRequestsToStorage() {
    try {
      final pendingJson = jsonEncode(_pendingCorrectionRequests
          .map((e) => _correctionRequestToJson(e))
          .toList());
      final processedJson = jsonEncode(_processedCorrectionRequests
          .map((e) => _correctionRequestToJson(e))
          .toList());

      platform_storage.storageSet(_pendingRequestsKey, pendingJson);
      platform_storage.storageSet(_processedRequestsKey, processedJson);

      debugPrint('💾 Saved corrections to localStorage:');
      debugPrint(
          '   Pending: ${_pendingCorrectionRequests.length} items (${pendingJson.length} chars)');
      debugPrint(
          '   Processed: ${_processedCorrectionRequests.length} items (${processedJson.length} chars)');
    } catch (e) {
      debugPrint('❌ Error saving correction requests: $e');
    }
  }

  Map<String, dynamic> _correctionRequestToJson(CorrectionRequestInternal r) {
    return {
      'id': r.id,
      'employeeName': r.employeeName,
      'employeeCode': r.employeeCode,
      'pin': r.pin,
      'attendanceId': r.attendanceId,
      'requestDate': r.requestDate.toIso8601String(),
      'correctionDate': r.correctionDate.toIso8601String(),
      'reason': r.reason,
      'status': r.status.index,
      'correctionType': r.correctionType,
      'requestedTime': r.requestedTime,
      'originalTime': r.originalTime,
      'processedBy': r.processedBy,
      'processedDate': r.processedDate?.toIso8601String(),
      'rejectionReason': r.rejectionReason,
    };
  }

  CorrectionRequestInternal _correctionRequestFromJson(
      Map<String, dynamic> json) {
    return CorrectionRequestInternal(
      id: json['id'],
      employeeName: json['employeeName'],
      employeeCode: json['employeeCode'],
      pin: json['pin'],
      attendanceId: json['attendanceId'],
      requestDate: DateTime.parse(json['requestDate']),
      correctionDate: DateTime.parse(json['correctionDate']),
      reason: json['reason'],
      status: CorrectionStatus.values[json['status']],
      correctionType: json['correctionType'],
      requestedTime: json['requestedTime'],
      originalTime: json['originalTime'],
      processedBy: json['processedBy'],
      processedDate: json['processedDate'] != null
          ? DateTime.parse(json['processedDate'])
          : null,
      rejectionReason: json['rejectionReason'],
    );
  }

  /// Áp dụng yêu cầu chỉnh sửa đã được duyệt vào danh sách attendance
  @override
  void dispose() {
    _refreshTimer?.cancel();
    _attendanceSubscription?.cancel();
    _tableScrollController.dispose();
    ScreenRefreshNotifier.attendance.removeListener(_onExternalRefresh);
    super.dispose();
  }

  /// Connect to SignalR for real-time updates
  Future<void> _connectSignalR() async {
    try {
      // Cancel previous subscription before creating a new one to prevent leaks
      await _attendanceSubscription?.cancel();
      _attendanceSubscription = null;

      // SignalR connection is managed by MainLayout with auth token
      // Here we only subscribe to the stream
      if (!_signalRService.isConnected) {
        await _signalRService.connect();
      }

      // Listen for new attendances
      _attendanceSubscription =
          _signalRService.onNewAttendance.listen((attendance) {
        if (mounted) {
          _handleNewAttendance(attendance);
        }
      });

      if (mounted) {
        setState(() {
          _isRealtimeConnected = _signalRService.isConnected;
        });
      }
    } catch (e) {
      debugPrint('📡 SignalR connection error: $e');
    }
  }

  /// Handle new attendance from SignalR
  void _handleNewAttendance(Attendance attendance) {
    // Check if attendance is for a selected device
    if (_selectedDevices.isEmpty ||
        _selectedDevices.contains(attendance.deviceId)) {
      setState(() {
        // Add to beginning of list
        _attendances.insert(0, attendance);
      });

      // Không hiển thị popup ở đây vì main_layout.dart đã hiển thị popup global rồi
      // _showAttendanceNotification(attendance);
    }
  }

  // Queue for notifications to show them sequentially
  final List<OverlayEntry> _notificationQueue = [];
  bool _isShowingNotification = false;

  /// Show notification when new attendance received - Top Right Corner
  // ignore: unused_element
  void _showAttendanceNotification(Attendance attendance) {
    if (!mounted) return;

    final timeStr = DateFormat('HH:mm:ss').format(attendance.attendanceTime);
    final stateText = attendance.punchTypeText;
    final userName = attendance.employeeName ?? attendance.pin ?? 'Unknown';
    final isCheckIn = attendance.attendanceState == 0;

    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _AttendanceNotificationWidget(
        userName: userName,
        stateText: stateText,
        timeStr: timeStr,
        deviceName: attendance.deviceName ?? 'Device',
        isCheckIn: isCheckIn,
        verifyType: attendance.verifyTypeText,
        onDismiss: () {
          overlayEntry.remove();
          _notificationQueue.remove(overlayEntry);
          _isShowingNotification = false;
          _showNextNotification();
        },
      ),
    );

    _notificationQueue.add(overlayEntry);
    _showNextNotification();
  }

  void _showNextNotification() {
    if (_isShowingNotification || _notificationQueue.isEmpty) return;

    _isShowingNotification = true;
    final entry = _notificationQueue.first;
    Overlay.of(context).insert(entry);
  }

  // ignore: unused_element
  void _toggleAutoRefresh() {
    setState(() {
      _isAutoRefresh = !_isAutoRefresh;
    });

    if (_isAutoRefresh) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
        if (mounted && _isAutoRefresh) {
          _loadAttendances(showLoading: false);
        }
      });
      appNotification.showSuccess(
        title: _l10n.autoUpdate,
        message: _l10n.autoUpdateEnabled,
      );
    } else {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      appNotification.showInfo(
        title: _l10n.autoUpdate,
        message: _l10n.autoUpdateDisabled,
      );
    }
  }

  Future<void> _loadDevices() async {
    try {
      final data = await _apiService.getDevices(storeOnly: true);
      if (mounted) {
        setState(() {
          _devices = data.map((e) => Device.fromJson(e)).toList();
          _selectedDevices = _devices.map((d) => d.id).toList();
        });
        _loadAttendances();
      }
    } catch (e) {
      debugPrint('Error loading devices: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadAttendances({bool showLoading = true}) async {
    if (showLoading) {
      setState(() => _isLoading = true);
    }
    try {
      // Nếu preset là today, week, month thì cập nhật toDate đến hiện tại
      // Nếu là yesterday, lastWeek, lastMonth thì giữ nguyên toDate đã set
      if (_selectedDatePreset == 'today' ||
          _selectedDatePreset == 'week' ||
          _selectedDatePreset == 'month') {
        _toDate = DateTime.now();
      }

      if (_dayEndHour == 0 && _dayEndMinute == 0) {
        final dayEndResult = await _apiService
            .getAppSetting('day_end_time')
            .catchError((_) => <String, dynamic>{});
        if (dayEndResult['isSuccess'] == true && dayEndResult['data'] is Map) {
          final value =
              (dayEndResult['data'] as Map)['value']?.toString() ?? '00:00:00';
          final parts = value.split(':');
          if (parts.length >= 2) {
            _dayEndHour = int.tryParse(parts[0]) ?? 0;
            _dayEndMinute = int.tryParse(parts[1]) ?? 0;
          }
        }
      }

      final attLoad = await loadAttendancesForPeriodResult(
        _apiService,
        deviceIds: _selectedDevices,
        fromDate: _fromDate,
        toDate: _toDate,
        dayEndHour: _dayEndHour,
        dayEndMinute: _dayEndMinute,
        pageSize: 1000,
        parallelPages: 6,
      );
      var attendanceList = attLoad.items;

      if (mounted) {
        _attendanceLoadTruncated = attLoad.truncated;
        _attendanceServerTotalCount = attLoad.totalCount;
        // Sắp xếp theo thời gian mới nhất trước (hiển thị danh sách)
        attendanceList
            .sort((a, b) => b.attendanceTime.compareTo(a.attendanceTime));

        // Kiểm tra nếu có bản ghi mới (khi auto refresh)
        if (!showLoading &&
            _attendances.isNotEmpty &&
            attendanceList.isNotEmpty) {
          final latestNew = attendanceList.first;
          final latestOld = _attendances.first;
          if (latestNew.id != latestOld.id) {
            // Có dữ liệu mới
            appNotification.showInfo(
              title: 'Chấm công mới',
              message:
                  '${latestNew.employeeName ?? 'N/A'} - ${DateFormat('HH:mm:ss').format(latestNew.attendanceTime)}',
            );
          }
        }

        // Áp dụng lại các corrections đã được duyệt trước khi set state
        attendanceList = _applyAllApprovedCorrections(attendanceList);

        setState(() {
          _attendances = attendanceList;
        });
        if (_attendanceLoadTruncated) {
          final serverTotal = _attendanceServerTotalCount;
          final msg = serverTotal != null && serverTotal > attendanceList.length
              ? 'Đã tải ${attendanceList.length} / $serverTotal log.'
              : 'Đã tải ${attendanceList.length} log (giới hạn tải).';
          appNotification.showWarning(
            title: 'Dữ liệu có thể chưa đủ',
            message: tr('$msg Có thể thiếu ngày cuối tháng — thu hẹp thiết bị hoặc khoảng ngày.'),
          );
        }
      }
    } catch (e) {
      debugPrint('Error loading attendances: $e');
    } finally {
      if (mounted && showLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Áp dụng tất cả các corrections đã được duyệt vào danh sách attendance
  /// Trả về danh sách đã được sửa đổi
  List<Attendance> _applyAllApprovedCorrections(List<Attendance> attendances) {
    debugPrint(
        '🔍 _applyAllApprovedCorrections called with ${attendances.length} attendances');
    debugPrint(
        '   Total processed requests: ${_processedCorrectionRequests.length}');

    final approvedCorrections = _processedCorrectionRequests
        .where((r) => r.status == CorrectionStatus.approved)
        .toList();

    debugPrint(
        '   Approved corrections to apply: ${approvedCorrections.length}');

    if (approvedCorrections.isEmpty) return attendances;

    debugPrint(
        '🔄 Applying ${approvedCorrections.length} approved corrections');

    // Tạo bản copy để sửa đổi
    var result = List<Attendance>.from(attendances);

    for (final request in approvedCorrections) {
      result = _applyCorrectionToList(result, request);
    }

    // Sắp xếp lại
    result.sort((a, b) => b.attendanceTime.compareTo(a.attendanceTime));

    return result;
  }

  /// Áp dụng một correction vào danh sách attendance và trả về danh sách mới
  List<Attendance> _applyCorrectionToList(
      List<Attendance> attendances, CorrectionRequestInternal request) {
    try {
      debugPrint(
          '   Applying: ${request.correctionType} for ${request.employeeName}');

      final parts = request.correctionType.split(':');
      if (parts.length != 2) {
        debugPrint(
            '   ⚠️ Invalid correctionType format: ${request.correctionType}');
        return attendances;
      }

      final actionType = parts[0];
      final punchIndex = int.tryParse(parts[1]) ?? 1;

      final timeParts = request.requestedTime.split(':');
      if (timeParts.length < 2) {
        debugPrint(
            '   ⚠️ Invalid requestedTime format: ${request.requestedTime}');
        return attendances;
      }

      final hour = int.tryParse(timeParts[0]) ?? 0;
      final minute = int.tryParse(timeParts[1]) ?? 0;

      final newTime = DateTime(
        request.correctionDate.year,
        request.correctionDate.month,
        request.correctionDate.day,
        hour,
        minute,
      );

      var result = List<Attendance>.from(attendances);

      switch (actionType) {
        case 'add':
          // Kiểm tra xem đã tồn tại chưa (tránh duplicate)
          final exists = result.any((att) =>
              att.id.startsWith('manual_') &&
              att.employeeName == request.employeeName &&
              att.attendanceTime.year == newTime.year &&
              att.attendanceTime.month == newTime.month &&
              att.attendanceTime.day == newTime.day &&
              att.attendanceTime.hour == newTime.hour &&
              att.attendanceTime.minute == newTime.minute);

          if (!exists) {
            // Tìm một bản ghi khác của cùng nhân viên để lấy thông tin
            final existingRecord = result.firstWhere(
              (att) =>
                  att.employeeName == request.employeeName ||
                  att.pin == request.pin ||
                  att.employeeId == request.employeeCode,
              orElse: () => Attendance(
                id: '',
                attendanceTime: DateTime.now(),
              ),
            );

            final newAttendance = Attendance(
              id: 'manual_${request.id}',
              pin: request.pin ?? existingRecord.pin ?? request.employeeCode,
              employeeId: existingRecord.employeeId ?? request.employeeCode,
              employeeName: request.employeeName,
              deviceId: _devices.isNotEmpty
                  ? _devices.first.id
                  : existingRecord.deviceId,
              deviceName: _devices.isNotEmpty
                  ? _devices.first.deviceName
                  : existingRecord.deviceName ?? 'Manual',
              deviceUserName: existingRecord.deviceUserName,
              privilege: existingRecord.privilege,
              attendanceTime: newTime,
              attendanceState: punchIndex % 2 == 1 ? 0 : 1,
              verifyMode: 99, // Manual entry
              note: '[Thêm thủ công: ${request.reason}]',
              createdAt: DateTime.now(),
            );
            result.insert(0, newAttendance);
          }
          break;

        case 'edit':
          // Ưu tiên tìm theo attendanceId nếu có
          bool found = false;

          if (request.attendanceId != null &&
              request.attendanceId!.isNotEmpty) {
            // Tìm chính xác theo ID
            for (int i = 0; i < result.length; i++) {
              if (result[i].id == request.attendanceId) {
                final att = result[i];
                result[i] = Attendance(
                  id: att.id,
                  pin: att.pin,
                  employeeId: att.employeeId,
                  employeeName: att.employeeName,
                  deviceId: att.deviceId,
                  deviceName: att.deviceName,
                  deviceUserName: att.deviceUserName,
                  privilege: att.privilege,
                  attendanceTime: newTime, // Chỉ thay đổi thời gian
                  attendanceState: att.attendanceState,
                  verifyMode: att.verifyMode, // Giữ nguyên kiểu xác thực
                  workCode: att.workCode,
                  note: '${att.note ?? ''} [Sửa: ${request.reason}]'.trim(),
                  createdAt: att.createdAt,
                );
                found = true;
                break;
              }
            }
          }

          // Fallback: tìm theo name + date + time nếu không có ID hoặc không tìm thấy
          if (!found) {
            for (int i = 0; i < result.length; i++) {
              final att = result[i];
              final attTimeStr = DateFormat('HH:mm').format(att.attendanceTime);

              if (att.employeeName == request.employeeName &&
                  att.attendanceTime.year == request.correctionDate.year &&
                  att.attendanceTime.month == request.correctionDate.month &&
                  att.attendanceTime.day == request.correctionDate.day &&
                  (request.originalTime == null ||
                      attTimeStr == request.originalTime)) {
                result[i] = Attendance(
                  id: att.id,
                  pin: att.pin,
                  employeeId: att.employeeId,
                  employeeName: att.employeeName,
                  deviceId: att.deviceId,
                  deviceName: att.deviceName,
                  deviceUserName: att.deviceUserName,
                  privilege: att.privilege,
                  attendanceTime: newTime, // Chỉ thay đổi thời gian
                  attendanceState: att.attendanceState,
                  verifyMode: att.verifyMode, // Giữ nguyên kiểu xác thực
                  workCode: att.workCode,
                  note: '${att.note ?? ''} [Sửa: ${request.reason}]'.trim(),
                  createdAt: att.createdAt,
                );
                break;
              }
            }
          }
          break;

        case 'delete':
          // Ưu tiên xóa theo attendanceId nếu có
          if (request.attendanceId != null &&
              request.attendanceId!.isNotEmpty) {
            result.removeWhere((att) => att.id == request.attendanceId);
          } else {
            // Fallback: xóa theo name + date + time
            result.removeWhere((att) =>
                att.employeeName == request.employeeName &&
                att.attendanceTime.year == request.correctionDate.year &&
                att.attendanceTime.month == request.correctionDate.month &&
                att.attendanceTime.day == request.correctionDate.day &&
                request.originalTime != null &&
                DateFormat('HH:mm').format(att.attendanceTime) ==
                    request.originalTime);
          }
          break;
      }

      debugPrint('   ✅ Applied successfully');
      return result;
    } catch (e, stackTrace) {
      debugPrint('   ❌ Error applying correction: $e');
      debugPrint('   Stack: $stackTrace');
      return attendances; // Trả về danh sách gốc nếu có lỗi
    }
  }

  /// Áp dụng correction vào DATABASE thông qua API
  /// Trả về true nếu thành công
  // ignore: unused_element
  Future<bool> _applyCorrectionToDatabase(
      CorrectionRequestInternal request) async {
    try {
      final parts = request.correctionType.split(':');
      if (parts.length != 2) {
        debugPrint(
            '❌ Invalid correctionType format: ${request.correctionType}');
        return false;
      }

      final actionType = parts[0];
      debugPrint(
          '🔄 Applying correction to database: $actionType for ${request.employeeName}');

      final timeParts = request.requestedTime.split(':');
      if (timeParts.length < 2) {
        debugPrint('❌ Invalid requestedTime format: ${request.requestedTime}');
        return false;
      }

      final hour = int.tryParse(timeParts[0]) ?? 0;
      final minute = int.tryParse(timeParts[1]) ?? 0;

      final newTime = DateTime(
        request.correctionDate.year,
        request.correctionDate.month,
        request.correctionDate.day,
        hour,
        minute,
      );

      switch (actionType) {
        case 'add':
          // TODO: Implement add attendance API (createManualAttendance)
          // Hiện tại chưa có đủ thông tin employeeId để tạo mới
          debugPrint(
              '⚠️ Add attendance to DB not implemented yet - needs employeeId');
          return true; // Trả về true để không block flow

        case 'edit':
          if (request.attendanceId == null || request.attendanceId!.isEmpty) {
            debugPrint('❌ No attendanceId for edit operation');
            return false;
          }

          final success = await _apiService.updateAttendance(
            request.attendanceId!,
            attendanceTime: newTime,
          );

          if (success) {
            debugPrint(
                '✅ Successfully updated attendance ${request.attendanceId} in database');
          } else {
            debugPrint('❌ Failed to update attendance in database');
          }
          return success;

        case 'delete':
          if (request.attendanceId == null || request.attendanceId!.isEmpty) {
            debugPrint('❌ No attendanceId for delete operation');
            return false;
          }

          final success =
              await _apiService.deleteAttendance(request.attendanceId!);

          if (success) {
            debugPrint(
                '✅ Successfully deleted attendance ${request.attendanceId} from database');
          } else {
            debugPrint('❌ Failed to delete attendance from database');
          }
          return success;

        default:
          debugPrint('❌ Unknown action type: $actionType');
          return false;
      }
    } catch (e) {
      debugPrint('❌ Error applying correction to database: $e');
      return false;
    }
  }

  Future<void> _syncAttendancesFromDevice() async {
    if (_selectedDevices.isEmpty) {
      appNotification.showWarning(
        title: _l10n.missingInfo,
        message: _l10n.pleaseSelectDevice,
      );
      return;
    }

    final targets = <DeviceSyncTarget>[];
    for (final deviceId in _selectedDevices) {
      final dev = _devices.where((d) => d.id == deviceId).firstOrNull;
      targets.add(DeviceSyncTarget(
        deviceId: deviceId,
        deviceName: dev?.deviceName ?? deviceId,
      ));
    }

    unawaited(DeviceSyncProgressDialog.show(
      apiService: _apiService,
      kind: DeviceSyncKind.attendances,
      devices: targets,
      onDataReady: () {
        if (mounted) _loadAttendances(showLoading: false);
      },
    ));
  }

  /// Show manual attendance dialog
  Future<void> _showManualAttendanceDialog() async {
    final employeesData = await _apiService.getEmployees();
    // Parse employees từ JSON thành List<Employee>
    final employees = employeesData
        .map((e) => Employee.fromJson(e as Map<String, dynamic>))
        .toList();
    if (!mounted) return;

    Employee? selectedEmployee;
    Device? selectedDevice = _devices.isNotEmpty ? _devices.first : null;
    DateTime selectedDate = DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.now();
    String note = '';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => ScrollableAlertDialog(
          title: Row(
            children: [
              Icon(Icons.add_circle, color: Colors.orange[400]),
              const SizedBox(width: 8),
              Text(tr('Chấm công thủ công')),
            ],
          ),
          content: SizedBox(
            width: math
                .min(500, MediaQuery.of(context).size.width - 32)
                .toDouble(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Employee dropdown
                DropdownButtonFormField<Employee>(
                  initialValue: selectedEmployee,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tr('${_l10n.employee} *'),
                    prefixIcon: const Icon(Icons.person),
                    border: const OutlineInputBorder(),
                  ),
                  items: employees
                      .map<DropdownMenuItem<Employee>>(
                          (e) => DropdownMenuItem<Employee>(
                                value: e,
                                child: Text(
                                  tr('${e.employeeCode} - ${e.fullName}'),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                      .toList(),
                  selectedItemBuilder: (context) => employees
                      .map((e) => Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              tr('${e.employeeCode} - ${e.fullName}'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedEmployee = v),
                ),
                const SizedBox(height: 16),

                // Device dropdown
                DropdownButtonFormField<Device>(
                  initialValue: selectedDevice,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tr('${_l10n.device} *'),
                    prefixIcon: const Icon(Icons.devices),
                    border: const OutlineInputBorder(),
                  ),
                  items: _devices
                      .map<DropdownMenuItem<Device>>(
                          (d) => DropdownMenuItem<Device>(
                                value: d,
                                child: Text(
                                  tr(d.deviceName),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedDevice = v),
                ),
                const SizedBox(height: 16),

                // Date picker
                ListTile(
                  leading: const Icon(Icons.calendar_today),
                  title: Text(tr(_l10n.date)),
                  subtitle: Text(tr(DateFormat('dd/MM/yyyy').format(selectedDate))),
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (date != null) {
                      setDialogState(() => selectedDate = date);
                    }
                  },
                  tileColor: Theme.of(context).cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey[600]!),
                  ),
                ),
                const SizedBox(height: 8),

                // Time picker
                ListTile(
                  leading: const Icon(Icons.access_time),
                  title: Text(tr(_l10n.time)),
                  subtitle: Text(tr(selectedTime.format(context))),
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: selectedTime,
                    );
                    if (time != null) {
                      setDialogState(() => selectedTime = time);
                    }
                  },
                  tileColor: Theme.of(context).cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: Colors.grey[600]!),
                  ),
                ),
                const SizedBox(height: 16),

                // Note field
                TextField(
                  decoration: InputDecoration(
                    labelText: tr(_l10n.note),
                    prefixIcon: const Icon(Icons.note),
                    border: const OutlineInputBorder(),
                    hintText: tr('${_l10n.manualAttendance}...'),
                  ),
                  maxLines: 2,
                  onChanged: (v) => note = v,
                ),

                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.orange[700], size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr('${_l10n.authType}: ${_l10n.manual}'),
                          style: TextStyle(
                              color: Colors.orange[700], fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            AppDialogActions(
              onConfirm: selectedEmployee == null || selectedDevice == null
                  ? null
                  : () async {
                      final punchTime = DateTime(
                        selectedDate.year,
                        selectedDate.month,
                        selectedDate.day,
                        selectedTime.hour,
                        selectedTime.minute,
                      );

                      // Đóng dialog trước
                      Navigator.pop(context);

                      setState(() => _isLoading = true);

                      final result = await _apiService.createManualAttendance(
                        employeeId: selectedEmployee!.id,
                        punchTime: punchTime,
                        deviceId: selectedDevice!.id,
                        note: note.isEmpty ? 'Chấm công thủ công' : note,
                      );

                      if (mounted) {
                        setState(() => _isLoading = false);

                        if (result['isSuccess'] == true) {
                          appNotification.showSuccess(
                            title: 'Success',
                            message: _l10n.addManualAttendanceSuccess,
                          );
                          _loadAttendances();
                        } else {
                          appNotification.showError(
                            title: _l10n.error,
                            message: _l10n.cannotAddAttendance,
                          );
                        }
                      }
                    },
              confirmLabel: 'Xác nhận',
              confirmIcon: Icons.check,
            ),
          ],
        ),
      ),
    );
  }

  /// Import attendances from Excel (mẫu gọn NV×ngày×Lần 1–6 hoặc dạng cũ 1 dòng/lần chấm).
  Future<void> _importFromExcel() async {
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => ScrollableAlertDialog(
          title: Row(
            children: [
              Icon(Icons.upload_file, color: Colors.blue[400]),
              const SizedBox(width: 8),
              Text(tr('Import chấm công')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Cách làm:'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                tr('1) Bấm «Xuất mẫu» → tải file Excel\n'
                    '2) Chỉ sửa/điền cột Lần 1–6 (và Ghi chú nếu cần)\n'
                    '3) Lưu file → Import lại cùng file đó'),
                style: const TextStyle(fontSize: 13, height: 1.35),
              ),
              const SizedBox(height: 12),
              Text(tr('Cột bắt buộc giữ đúng (không đổi):'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('• Mã NV — khớp đúng mã trên hệ thống'),
                        style: const TextStyle(fontSize: 12)),
                    Text(tr('• Ngày — định dạng dd/MM/yyyy'),
                        style: const TextStyle(fontSize: 12)),
                    Text(tr('• Không xóa/đổi tên dòng tiêu đề cột'),
                        style: const TextStyle(fontSize: 12)),
                    Text(tr('• Import đọc sheet «MauChamCong» / «ChamCong»'),
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(tr('Được sửa / điền:'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('• Lần 1–6: giờ HH:mm (vd 08:00, 17:30) — để trống nếu không chấm'),
                        style: const TextStyle(fontSize: 12)),
                    Text(tr('• Ghi chú (tùy chọn)'),
                        style: const TextStyle(fontSize: 12)),
                    Text(tr('• Tên NV chỉ để đọc — hệ thống không dùng khi import'),
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tr('Giờ trùng đã có sẽ bỏ qua. File mẫu có thêm sheet «DanhSachNV» và «HuongDan» để tra cứu — không cần sửa 2 sheet đó.'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            AppDialogActions(
              onCancel: () => Navigator.pop(context, false),
              onConfirm: () => Navigator.pop(context, true),
              confirmLabel: 'Chọn file',
              confirmIcon: Icons.folder_open,
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final bytes = result.files.first.bytes;
      if (bytes == null) {
        if (mounted) {
          appNotification.showError(
            title: _l10n.error,
            message: tr('Không thể đọc file'),
          );
        }
        return;
      }

      setState(() => _isLoading = true);

      final excelData = excel_lib.Excel.decodeBytes(bytes);
      final records = <Map<String, dynamic>>[];

      // Ưu tiên sheet dữ liệu chấm công; bỏ qua HuongDan / DanhSachNV
      final preferredNames = [
        'mauchamcong',
        'chamcong',
        'attendance',
      ];
      final skipNames = {
        'huongdan',
        'danhsachnv',
        'nhanvien',
        'sheet1',
      };

      excel_lib.Sheet? pickSheet() {
        for (final name in preferredNames) {
          for (final key in excelData.tables.keys) {
            if (key.trim().toLowerCase() == name) {
              return excelData.tables[key];
            }
          }
        }
        for (final key in excelData.tables.keys) {
          final lower = key.trim().toLowerCase();
          if (skipNames.contains(lower)) continue;
          final sheet = excelData.tables[key];
          if (sheet == null || sheet.rows.isEmpty) continue;
          final headers = <String>[
            for (final c in sheet.rows.first)
              (_excelCellText(c) ?? '').trim().toLowerCase()
          ];
          if (headers.any((h) => h.contains('lần 1') || h == 'lan 1') ||
              headers.any((h) => h.contains('mã nv') || h == 'ma nv')) {
            return sheet;
          }
        }
        return null;
      }

      final sheet = pickSheet();
      if (sheet != null && sheet.rows.isNotEmpty) {
        final headers = <String>[
          for (final c in sheet.rows.first)
            (_excelCellText(c) ?? '').trim().toLowerCase()
        ];
        final isCompact =
            headers.any((h) => h.contains('lần 1') || h == 'lan 1');
        if (isCompact) {
          records.addAll(_parseCompactAttendanceSheet(sheet));
        } else {
          records.addAll(_parseLegacyAttendanceSheet(sheet));
        }
      }

      if (records.isEmpty) {
        setState(() => _isLoading = false);
        if (mounted) {
          appNotification.showWarning(
            title: 'Không có dữ liệu',
            message: tr('Không tìm thấy dữ liệu hợp lệ trong file'),
          );
        }
        return;
      }

      final importResult =
          await _apiService.importAttendancesFromExcel(records);

      setState(() => _isLoading = false);

      if (mounted) {
        if (importResult['success'] == true) {
          final skipped = importResult['skipped'] ?? 0;
          appNotification.showSuccess(
            title: 'Import thành công',
            message:
                'Đã thêm ${importResult['imported']} lần chấm'
                '${skipped > 0 ? ', bỏ qua $skipped trùng' : ''}'
                '${(importResult['failed'] ?? 0) > 0 ? ', ${importResult['failed']} lỗi' : ''}',
          );
          _loadAttendances();
        } else {
          appNotification.showError(
            title: 'Import thất bại',
            message: '${importResult['message']}',
          );
        }
      }
    } catch (e) {
      debugPrint('Error importing Excel: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        appNotification.showError(
          title: _l10n.error,
          message: '$e',
        );
      }
    }
  }

  String? _excelCellText(excel_lib.Data? cell) {
    final v = cell?.value;
    if (v == null) return null;
    if (v is excel_lib.TextCellValue) return v.value.toString();
    if (v is excel_lib.IntCellValue) return v.value.toString();
    if (v is excel_lib.DoubleCellValue) return v.value.toString();
    if (v is excel_lib.DateCellValue) {
      return DateFormat('dd/MM/yyyy')
          .format(DateTime(v.year, v.month, v.day));
    }
    if (v is excel_lib.DateTimeCellValue) {
      final dt = v.asDateTimeLocal();
      if (v.hour != 0 || v.minute != 0 || v.second != 0) {
        return DateFormat('dd/MM/yyyy HH:mm:ss').format(dt);
      }
      return DateFormat('dd/MM/yyyy').format(dt);
    }
    if (v is excel_lib.TimeCellValue) {
      return v.toString();
    }
    return v.toString().trim();
  }

  List<Map<String, dynamic>> _parseLegacyAttendanceSheet(
      excel_lib.Sheet sheet) {
    final records = <Map<String, dynamic>>[];
    for (int i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      if (row.isEmpty) continue;

      final employeeCode =
          row.isNotEmpty ? _excelCellText(row[0])?.trim() : null;
      final dateStr = row.length > 1 ? _excelCellText(row[1]) : null;
      final timeStr = row.length > 2 ? _excelCellText(row[2]) : null;
      final note = row.length > 3 ? _excelCellText(row[3]) : null;

      if (employeeCode == null ||
          employeeCode.isEmpty ||
          dateStr == null ||
          timeStr == null) {
        continue;
      }

      // Legacy: Ngày + Giờ tách cột; cũng chấp nhận ô Ngày đã có sẵn giờ
      DateTime? punchTime;
      if (timeStr.contains(':') || double.tryParse(timeStr) != null) {
        punchTime = _combineDateAndTime(dateStr, timeStr);
      } else {
        punchTime = _parseDateOnly(dateStr);
      }
      if (punchTime == null) continue;

      records.add({
        'employeeCode': employeeCode,
        'punchTime': punchTime.toIso8601String(),
        'note': note ?? 'Import từ Excel',
        'verifyType': 100,
        'isManual': true,
      });
    }
    return records;
  }

  List<Map<String, dynamic>> _parseCompactAttendanceSheet(
      excel_lib.Sheet sheet) {
    final records = <Map<String, dynamic>>[];
    // Cột: 0 Mã NV | 1 Tên | 2 Ngày | 3-8 Lần 1-6 | 9 Ghi chú
    for (int i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      if (row.isEmpty) continue;

      final employeeCode =
          row.isNotEmpty ? _excelCellText(row[0])?.trim() : null;
      final dateStr = row.length > 2 ? _excelCellText(row[2]) : null;
      final note = row.length > 9 ? _excelCellText(row[9]) : null;

      if (employeeCode == null ||
          employeeCode.isEmpty ||
          dateStr == null ||
          dateStr.trim().isEmpty) {
        continue;
      }

      final dateOnly = _parseDateOnly(dateStr.split(' ').first);
      if (dateOnly == null) continue;

      for (var punchIdx = 0; punchIdx < 6; punchIdx++) {
        final col = 3 + punchIdx;
        if (row.length <= col) break;
        final timeRaw = _excelCellText(row[col])?.trim();
        if (timeRaw == null || timeRaw.isEmpty) continue;

        // Ô Lần có thể là "HH:mm" hoặc full datetime từ Excel
        String timePart = timeRaw;
        if (timeRaw.contains(' ')) {
          final parts = timeRaw.split(RegExp(r'\s+'));
          timePart = parts.length > 1 ? parts.last : timeRaw;
        }

        final punchTime = _combineDateAndTime(
          DateFormat('dd/MM/yyyy').format(dateOnly),
          timePart,
        );
        if (punchTime == null) continue;

        records.add({
          'employeeCode': employeeCode,
          'punchTime': punchTime.toIso8601String(),
          'note': (note != null && note.trim().isNotEmpty)
              ? note.trim()
              : 'Import Excel Lần ${punchIdx + 1}',
          'verifyType': 100,
          'isManual': true,
        });
      }
    }
    return records;
  }

  DateTime? _parseDateOnly(String dateStr) {
    try {
      final cleaned = dateStr.trim();
      // ISO / DateTimeCellValue.toString()
      if (cleaned.contains('T') || RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(cleaned)) {
        final dt = DateTime.tryParse(cleaned);
        if (dt != null) {
          return DateTime(dt.year, dt.month, dt.day);
        }
      }
      // Excel serial number
      final asNum = double.tryParse(cleaned);
      if (asNum != null && asNum > 20000 && asNum < 80000) {
        final epoch = DateTime(1899, 12, 30);
        return epoch.add(Duration(days: asNum.floor()));
      }
      final dateParts = cleaned.split(RegExp(r'[/\-.]'));
      if (dateParts.length != 3) return null;
      var a = int.parse(dateParts[0]);
      var b = int.parse(dateParts[1]);
      var c = int.parse(dateParts[2].split(' ').first);
      // dd/MM/yyyy or yyyy/MM/dd
      if (a > 31) {
        return DateTime(a, b, c);
      }
      return DateTime(c, b, a);
    } catch (_) {
      return null;
    }
  }

  DateTime? _combineDateAndTime(String dateStr, String timeStr) {
    try {
      final dateOnly = _parseDateOnly(dateStr);
      if (dateOnly == null) return null;

      var cleaned = timeStr.trim();
      // Excel time fraction 0..1
      final asNum = double.tryParse(cleaned);
      if (asNum != null && asNum >= 0 && asNum < 1) {
        final totalSeconds = (asNum * 24 * 3600).round();
        final h = totalSeconds ~/ 3600;
        final m = (totalSeconds % 3600) ~/ 60;
        final s = totalSeconds % 60;
        return DateTime(dateOnly.year, dateOnly.month, dateOnly.day, h, m, s);
      }

      // "HH:mm:ss AM" etc.
      cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
      final timeParts = cleaned.split(RegExp(r'[:\s]'));
      if (timeParts.isEmpty) return null;
      var hour = int.parse(timeParts[0]);
      final minute = timeParts.length > 1 ? int.parse(timeParts[1]) : 0;
      final second = timeParts.length > 2
          ? int.tryParse(timeParts[2].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0
          : 0;
      if (cleaned.toUpperCase().contains('PM') && hour < 12) hour += 12;
      if (cleaned.toUpperCase().contains('AM') && hour == 12) hour = 0;

      return DateTime(
          dateOnly.year, dateOnly.month, dateOnly.day, hour, minute, second);
    } catch (e) {
      debugPrint('Error parsing date/time: $e');
      return null;
    }
  }

  /// Xuất mẫu / dữ liệu dạng bảng gọn: NV × ngày × Lần 1–6.
  Future<void> _exportCompactExcel({required bool templateOnly}) async {
    try {
      final from = DateTime(_fromDate.year, _fromDate.month, _fromDate.day);
      final to = DateTime(_toDate.year, _toDate.month, _toDate.day);
      if (to.isBefore(from)) {
        appNotification.showWarning(
          title: 'Khoảng ngày không hợp lệ',
          message: tr('Ngày kết thúc phải sau ngày bắt đầu'),
        );
        return;
      }

      // Giới hạn mẫu trống: tối đa ~90 ngày × NV
      final daySpan = to.difference(from).inDays + 1;
      if (templateOnly && daySpan > 62) {
        appNotification.showWarning(
          title: 'Khoảng ngày quá dài',
          message: tr('Xuất mẫu tối đa 62 ngày. Hãy thu hẹp bộ lọc ngày.'),
        );
        return;
      }

      var employees = List<Map<String, dynamic>>.from(_employeesList);
      if (_filterEmployeeCode != null && _filterEmployeeCode!.isNotEmpty) {
        employees = employees
            .where((e) => e['employeeCode']?.toString() == _filterEmployeeCode)
            .toList();
      }
      if (employees.isEmpty && !templateOnly) {
        // Fallback: lấy NV từ dữ liệu đang lọc
        final seen = <String>{};
        for (final att in _filteredAttendances) {
          final code = att.employeeId ?? '';
          if (code.isEmpty || !seen.add(code)) continue;
          employees.add({
            'employeeCode': code,
            'fullName': att.employeeName ?? '',
          });
        }
      }
      if (employees.isEmpty) {
        appNotification.showWarning(
          title: 'Không có nhân viên',
          message: tr('Không có nhân viên để xuất mẫu'),
        );
        return;
      }

      // Map mã NV → list giờ theo ngày (chỉ khi xuất dữ liệu)
      final punchesByKey = <String, List<DateTime>>{};
      if (!templateOnly) {
        for (final att in _filteredAttendances) {
          final code = att.employeeId ?? '';
          if (code.isEmpty) continue;
          final d = DateTime(
              att.punchTime.year, att.punchTime.month, att.punchTime.day);
          final key = '$code|${DateFormat('yyyy-MM-dd').format(d)}';
          punchesByKey.putIfAbsent(key, () => []).add(att.punchTime);
        }
        for (final list in punchesByKey.values) {
          list.sort();
        }
      }

      final excel = excel_lib.Excel.createExcel();
      final sheetName = templateOnly ? 'MauChamCong' : 'ChamCong';
      final sheet = excel[sheetName];
      try {
        excel.delete('Sheet1');
      } catch (_) {}

      _writeAttendanceGuideSheet(excel);
      _writeEmployeeInfoSheet(excel, employees);

      const headers = [
        'Mã NV',
        'Tên NV',
        'Ngày',
        'Lần 1',
        'Lần 2',
        'Lần 3',
        'Lần 4',
        'Lần 5',
        'Lần 6',
        'Ghi chú',
      ];
      for (var i = 0; i < headers.length; i++) {
        sheet
            .cell(excel_lib.CellIndex.indexByColumnRow(
                columnIndex: i, rowIndex: 0))
            .value = excel_lib.TextCellValue(headers[i]);
      }

      var row = 1;
      for (final emp in employees) {
        final code = emp['employeeCode']?.toString() ?? '';
        if (code.isEmpty) continue;
        final name = _employeeDisplayName(emp);

        for (var d = 0; d < daySpan; d++) {
          final day = from.add(Duration(days: d));
          final key = '$code|${DateFormat('yyyy-MM-dd').format(day)}';
          final punches = punchesByKey[key] ?? const <DateTime>[];

          // Khi xuất dữ liệu: bỏ ngày không có chấm để file gọn
          if (!templateOnly && punches.isEmpty) continue;

          sheet
              .cell(excel_lib.CellIndex.indexByColumnRow(
                  columnIndex: 0, rowIndex: row))
              .value = excel_lib.TextCellValue(code);
          sheet
              .cell(excel_lib.CellIndex.indexByColumnRow(
                  columnIndex: 1, rowIndex: row))
              .value = excel_lib.TextCellValue(name);
          sheet
              .cell(excel_lib.CellIndex.indexByColumnRow(
                  columnIndex: 2, rowIndex: row))
              .value =
              excel_lib.TextCellValue(DateFormat('dd/MM/yyyy').format(day));

          for (var p = 0; p < 6; p++) {
            final cell = sheet.cell(excel_lib.CellIndex.indexByColumnRow(
                columnIndex: 3 + p, rowIndex: row));
            if (p < punches.length) {
              cell.value = excel_lib.TextCellValue(
                  DateFormat('HH:mm').format(punches[p]));
            } else {
              cell.value = excel_lib.TextCellValue('');
            }
          }
          sheet
              .cell(excel_lib.CellIndex.indexByColumnRow(
                  columnIndex: 9, rowIndex: row))
              .value = excel_lib.TextCellValue('');
          row++;
        }
      }

      if (row == 1) {
        appNotification.showWarning(
          title: 'Không có dữ liệu',
          message: tr('Không có dòng nào để xuất trong khoảng đã chọn'),
        );
        return;
      }

      // Đưa sheet chấm công lên đầu để mở file thấy ngay
      try {
        excel.setDefaultSheet(sheetName);
      } catch (_) {}

      final bytes = excel.encode();
      if (bytes != null) {
        final prefix = templateOnly ? 'MauChamCong' : 'ChamCong';
        final fileName =
            '${prefix}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
        await file_saver.saveFileBytes(bytes, fileName,
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        appNotification.showSuccess(
          title: templateOnly ? 'Đã xuất mẫu' : 'Xuất file thành công',
          message: tr(
              'Đã xuất $fileName (${row - 1} dòng). Điền Lần 1–6 rồi Import lại cùng file.'),
        );
      }
    } catch (e) {
      debugPrint('Error exporting compact Excel: $e');
      appNotification.showError(
        title: 'Lỗi xuất Excel',
        message: '$e',
      );
    }
  }

  String _employeeDisplayName(Map<String, dynamic> emp) {
    final full = (emp['fullName'] ??
            emp['name'] ??
            '${emp['lastName'] ?? ''} ${emp['firstName'] ?? ''}')
        .toString()
        .trim();
    return full;
  }

  void _writeAttendanceGuideSheet(excel_lib.Excel excel) {
    final guide = excel['HuongDan'];
    final lines = <String>[
      'HƯỚNG DẪN IMPORT CHẤM CÔNG',
      '',
      'Cách làm:',
      '1. Mở sheet MauChamCong (hoặc ChamCong).',
      '2. Chỉ điền/sửa cột Lần 1 → Lần 6 bằng giờ HH:mm (vd: 08:00, 12:00, 13:00, 17:30).',
      '3. Để trống ô nếu ngày đó không chấm lần đó.',
      '4. Lưu file → vào app bấm Import Excel → chọn đúng file vừa sửa.',
      '',
      'Cột BẮT BUỘC giữ đúng (không sửa / không đổi định dạng):',
      '- Mã NV: phải khớp mã nhân viên trên hệ thống (xem sheet DanhSachNV).',
      '- Ngày: dd/MM/yyyy (vd 08/08/2026).',
      '- Dòng tiêu đề cột (hàng 1): không đổi tên cột, không xóa.',
      '',
      'Cột được phép sửa:',
      '- Lần 1, Lần 2, Lần 3, Lần 4, Lần 5, Lần 6',
      '- Ghi chú (tùy chọn)',
      '',
      'Cột chỉ để đọc (sửa cũng không ảnh hưởng import):',
      '- Tên NV',
      '',
      'Sheet khác trong file:',
      '- DanhSachNV: tra cứu mã / tên / phòng ban / chi nhánh khi điền.',
      '- HuongDan: sheet này — không cần sửa, app không import sheet này.',
      '',
      'Lưu ý:',
      '- Mỗi dòng = 1 nhân viên × 1 ngày, tối đa 6 lần chấm.',
      '- Giờ đã có trên hệ thống sẽ bị bỏ qua (không tạo trùng).',
      '- Có thể thêm dòng mới nếu giữ đúng Mã NV + Ngày + các cột Lần.',
    ];
    for (var i = 0; i < lines.length; i++) {
      guide
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 0, rowIndex: i))
          .value = excel_lib.TextCellValue(lines[i]);
    }
  }

  void _writeEmployeeInfoSheet(
    excel_lib.Excel excel,
    List<Map<String, dynamic>> employees,
  ) {
    final info = excel['DanhSachNV'];
    const headers = [
      'STT',
      'Mã NV',
      'Tên NV',
      'Phòng ban',
      'Chức vụ',
      'Chi nhánh',
      'Điện thoại',
      'Email',
    ];
    for (var i = 0; i < headers.length; i++) {
      info
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: i, rowIndex: 0))
          .value = excel_lib.TextCellValue(headers[i]);
    }

    // Sắp xếp theo mã NV để dễ tra
    final sorted = List<Map<String, dynamic>>.from(employees)
      ..sort((a, b) => (a['employeeCode']?.toString() ?? '')
          .compareTo(b['employeeCode']?.toString() ?? ''));

    var row = 1;
    for (final emp in sorted) {
      final code = emp['employeeCode']?.toString() ?? '';
      if (code.isEmpty) continue;
      final name = _employeeDisplayName(emp);
      final dept = emp['department']?.toString() ?? '';
      final position = emp['position']?.toString() ?? '';
      final branch = emp['branchName']?.toString() ?? '';
      final phone =
          (emp['phoneNumber'] ?? emp['phone'] ?? '').toString();
      final email =
          (emp['companyEmail'] ?? emp['email'] ?? '').toString();

      info
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 0, rowIndex: row))
          .value = excel_lib.IntCellValue(row);
      info
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 1, rowIndex: row))
          .value = excel_lib.TextCellValue(code);
      info
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 2, rowIndex: row))
          .value = excel_lib.TextCellValue(name);
      info
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 3, rowIndex: row))
          .value = excel_lib.TextCellValue(dept);
      info
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 4, rowIndex: row))
          .value = excel_lib.TextCellValue(position);
      info
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 5, rowIndex: row))
          .value = excel_lib.TextCellValue(branch);
      info
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 6, rowIndex: row))
          .value = excel_lib.TextCellValue(phone);
      info
          .cell(excel_lib.CellIndex.indexByColumnRow(
              columnIndex: 7, rowIndex: row))
          .value = excel_lib.TextCellValue(email);
      row++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final canSync = canSyncAttendanceFromDevice(
      role: auth.user?.role,
      permissions: perm,
    );
    final canCreate = perm.canCreate('Attendance');
    final canExport = perm.canExport('Attendance');

    final topActions = <Widget>[
      if (isMobile)
        HrmTopBarAction(
          icon: _showMobileSearch ? Icons.close : Icons.search,
          label: 'Tìm kiếm',
          onPressed: () => setState(() {
            if (_showMobileSearch) {
              _showMobileSearch = false;
              _searchPin = '';
              _currentPage = 1;
            } else {
              _showMobileSearch = true;
            }
          }),
        ),
      if (canSync)
        HrmTopBarAction(
          icon: Icons.sync,
          label: _l10n.syncData,
          onPressed: _syncAttendancesFromDevice,
        ),
      if (canCreate)
        HrmTopBarAction(
          icon: Icons.upload_file,
          label: _l10n.importExcel,
          onPressed: _importFromExcel,
        ),
      if (canExport) ...[
        HrmTopBarAction(
          icon: Icons.table_view_outlined,
          label: 'Xuất mẫu',
          onPressed: () => _exportCompactExcel(templateOnly: true),
        ),
        HrmTopBarAction(
          icon: Icons.file_download_outlined,
          label: _l10n.exportExcel,
          onPressed: () => _exportCompactExcel(templateOnly: false),
        ),
      ],
      if (canCreate)
        HrmTopBarAction(
          icon: Icons.add_circle_outline,
          label: _l10n.manualAttendance,
          primary: true,
          showLabel: true,
          onPressed: _showManualAttendanceDialog,
        ),
    ];

    return RegisterPageTopActions(
      actions: topActions,
      child: Scaffold(
        backgroundColor: HrmPageChrome.background,
        body: _buildDetailTab(),
      ),
    );
  }

  Widget _buildRealtimeIndicator({bool forLightBackground = false}) {
    final connectedBg = forLightBackground
        ? Colors.green.withValues(alpha: 0.12)
        : Colors.greenAccent.withValues(alpha: 0.2);
    final disconnectedBg = forLightBackground
        ? const Color(0xFFF4F4F5)
        : Colors.white.withValues(alpha: 0.15);
    final connectedBorder = forLightBackground
        ? Colors.green.withValues(alpha: 0.4)
        : Colors.greenAccent.withValues(alpha: 0.6);
    final disconnectedBorder = forLightBackground
        ? const Color(0xFFE4E4E7)
        : Colors.white.withValues(alpha: 0.3);
    final labelColor = forLightBackground
        ? (_isRealtimeConnected
            ? const Color(0xFF16A34A)
            : const Color(0xFF71717A))
        : (_isRealtimeConnected ? Colors.greenAccent : Colors.white70);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _isRealtimeConnected ? connectedBg : disconnectedBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isRealtimeConnected ? connectedBorder : disconnectedBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isRealtimeConnected
                  ? (forLightBackground
                      ? const Color(0xFF16A34A)
                      : Colors.greenAccent)
                  : (forLightBackground
                      ? const Color(0xFF9CA3AF)
                      : Colors.white54),
              boxShadow: _isRealtimeConnected
                  ? [
                      BoxShadow(
                          color: Colors.greenAccent.withValues(alpha: 0.6),
                          blurRadius: 6)
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            tr(_isRealtimeConnected ? 'LIVE' : 'OFFLINE'),
            style: TextStyle(
              color: labelColor,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderActionBtn(
      IconData icon, String tooltip, VoidCallback onPressed) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailTab() {
    final isMobile = Responsive.isMobile(context);
    return HrmResponsiveListLayout(
      padding: EdgeInsets.fromLTRB(
          isMobile ? 10 : 16, isMobile ? 10 : 16, isMobile ? 10 : 16, 8),
      headerSections: _detailTabHeaderSections(isMobile),
      desktopBody: _isLoading
          ? LoadingWidget(message: tr('Đang tải dữ liệu...'))
          : _attendances.isEmpty
              ? const EmptyState(
                  icon: Icons.access_time,
                  title: 'Không có dữ liệu',
                  description:
                      'Không có bản ghi chấm công trong khoảng thời gian này',
                )
              : Column(
                  children: [
                    Expanded(child: _buildAttendanceTable()),
                    _buildPagination(),
                  ],
                ),
      mobileSlivers: (_) => _detailTabMobileSlivers(),
    );
  }

  List<Widget> _detailTabHeaderSections(bool isMobile) => [
        if (isMobile && _showMobileSearch) ...[
          TextField(
            autofocus: true,
            decoration: InputDecoration(
              hintText: tr('Tìm ID/Tên...'),
              hintStyle: const TextStyle(fontSize: 13),
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      BorderSide(color: Theme.of(context).primaryColor)),
            ),
            style: const TextStyle(fontSize: 13),
            onChanged: (v) => setState(() {
              _searchPin = v;
              _currentPage = 1;
            }),
          ),
          const SizedBox(height: 12),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: _buildRealtimeIndicator(forLightBackground: true),
        ),
        const SizedBox(height: 12),
        _buildOverviewSection(isMobile),
        const SizedBox(height: 12),
      ];

  Widget _buildOverviewSection(bool isMobile) {
    return HrmCollapsibleOverview(
      expanded: _showOverviewPanel,
      onToggle: () =>
          setState(() => _showOverviewPanel = !_showOverviewPanel),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStatsRow(),
          const SizedBox(height: 10),
          _buildAttendanceFilterBar(),
        ],
      ),
    );
  }

  List<Widget> _detailTabMobileSlivers() {
    if (_isLoading) {
      return [
        HrmScrollSlivers.fillRemaining(
            child: LoadingWidget(message: tr('Đang tải dữ liệu...'))),
      ];
    }
    if (_attendances.isEmpty) {
      return [
        HrmScrollSlivers.fillRemaining(
          child: const EmptyState(
            icon: Icons.access_time,
            title: 'Không có dữ liệu',
            description:
                'Không có bản ghi chấm công trong khoảng thời gian này',
          ),
        ),
      ];
    }
    final allFiltered = _filteredAttendances;
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage).clamp(0, allFiltered.length);
    final pageItems = allFiltered.sublist(startIndex, endIndex);
    return [
      SliverToBoxAdapter(
        child: _buildAttendanceMobileList(pageItems, startIndex, shrinkWrap: true),
      ),
      if (allFiltered.length > _itemsPerPage)
        SliverToBoxAdapter(child: _buildPagination()),
    ];
  }

  Widget _buildStatsRow() {
    final total = _filteredAttendances.length;
    final fingerprint =
        _filteredAttendances.where((a) => a.verifyType == 1).length;
    final face = _filteredAttendances
        .where((a) => a.verifyType == 15 || a.verifyType == 9)
        .length;
    final manual =
        _filteredAttendances.where((a) => a.verifyType == 100).length;
    final card = _filteredAttendances.where((a) => a.verifyType == 2).length;

    final totalLabel = _attendanceLoadTruncated &&
            _attendanceServerTotalCount != null &&
            _attendanceServerTotalCount! > total
        ? '$total/${_attendanceServerTotalCount}'
        : '$total';
    final cards = [
      _buildStatCard('Tổng bản ghi', totalLabel, Icons.list_alt,
          _attendanceLoadTruncated ? HrmPageChrome.chipLight : HrmPageChrome.primaryNavy),
      _buildStatCard('Vân tay', '$fingerprint', Icons.fingerprint,
          HrmPageChrome.primaryNavy),
      _buildStatCard(
          'Khuôn mặt', '$face', Icons.face, HrmPageChrome.primaryNavy),
      _buildStatCard(
          'Thẻ từ', '$card', Icons.credit_card, HrmPageChrome.chipLight),
      _buildStatCard(
          'Thủ công', '$manual', Icons.edit_note, const Color(0xFFEF4444)),
    ];

    if (Responsive.isMobile(context)) {
      return HrmPageChrome.horizontalStatCards(
        cards: cards,
        minCardWidth: 100,
        gap: 8,
      );
    }

    return Row(
      children: cards
          .expand((c) => [Expanded(child: c), const SizedBox(width: 8)])
          .toList()
        ..removeLast(),
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color) {
    return HrmStatSummaryCard(
      icon: icon,
      value: value,
      label: label,
      color: color,
    );
  }

  // Pagination widget
  Widget _buildPagination() {
    final totalItems = _filteredAttendances.length;
    final totalPages = (totalItems / _itemsPerPage).ceil();
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage).clamp(0, totalItems);
    final isMobile = Responsive.isMobile(context);

    if (isMobile) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(12),
              bottomRight: Radius.circular(12)),
          border: Border(top: BorderSide(color: Color(0xFFE4E4E7))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(tr('${startIndex + 1}-$endIndex / $totalItems'),
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            Row(
              children: [
                _buildPageNavBtn(Icons.chevron_left, _currentPage > 1,
                    () => setState(() => _currentPage--)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(tr('$_currentPage/$totalPages'),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
                ),
                _buildPageNavBtn(Icons.chevron_right, _currentPage < totalPages,
                    () => setState(() => _currentPage++)),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
        border: Border(top: BorderSide(color: Color(0xFFE4E4E7))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Items info
          Text(tr('Hiển thị ${startIndex + 1}-$endIndex / $totalItems'),
            style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500),
          ),

          // Page size selector
          Row(
            children: [
              Text(tr('Hiển thị:'),
                  style: TextStyle(fontSize: 12, color: Colors.grey[500])),
              const SizedBox(width: 8),
              Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  border: Border.all(color: const Color(0xFFE4E4E7)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _itemsPerPage,
                    isDense: true,
                    style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                    items: _pageSizeOptions
                        .map((size) => DropdownMenuItem(
                              value: size,
                              child: Text(tr('$size')),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _itemsPerPage = v;
                          _currentPage = 1;
                        });
                      }
                    },
                  ),
                ),
              ),
            ],
          ),

          // Page navigation
          Row(
            children: [
              _buildPageNavBtn(Icons.first_page, _currentPage > 1,
                  () => setState(() => _currentPage = 1)),
              _buildPageNavBtn(Icons.chevron_left, _currentPage > 1,
                  () => setState(() => _currentPage--)),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  tr('$_currentPage / $totalPages'),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              _buildPageNavBtn(Icons.chevron_right, _currentPage < totalPages,
                  () => setState(() => _currentPage++)),
              _buildPageNavBtn(Icons.last_page, _currentPage < totalPages,
                  () => setState(() => _currentPage = totalPages)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPageNavBtn(IconData icon, bool enabled, VoidCallback onPressed) {
    return Material(
      color: enabled ? const Color(0xFFF1F5F9) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          child: Icon(icon,
              size: 20,
              color:
                  enabled ? Theme.of(context).primaryColor : Colors.grey[400]),
        ),
      ),
    );
  }

  void _applyDatePreset(String preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    setState(() {
      _selectedDatePreset = preset;
      _currentPage = 1; // Reset về trang 1 khi thay đổi filter
      switch (preset) {
        case 'today':
          _fromDate = today;
          _toDate = now;
          break;
        case 'yesterday':
          final yesterday = today.subtract(const Duration(days: 1));
          _fromDate = yesterday;
          // Set to end of yesterday (23:59:59)
          _toDate = DateTime(
              yesterday.year, yesterday.month, yesterday.day, 23, 59, 59);
          break;
        case 'week':
          // This week (Monday to now)
          final weekday = now.weekday;
          _fromDate = today.subtract(Duration(days: weekday - 1));
          _toDate = now;
          break;
        case 'lastWeek':
          // Last week (Monday to Sunday)
          final weekday = now.weekday;
          final thisMonday = today.subtract(Duration(days: weekday - 1));
          _fromDate = thisMonday.subtract(const Duration(days: 7));
          final lastSunday = thisMonday.subtract(const Duration(days: 1));
          _toDate = DateTime(
              lastSunday.year, lastSunday.month, lastSunday.day, 23, 59, 59);
          break;
        case 'month':
          // This month
          _fromDate = DateTime(now.year, now.month, 1);
          _toDate = now;
          break;
        case 'lastMonth':
          final firstThis = DateTime(today.year, today.month, 1);
          final lastDayPrev = firstThis.subtract(const Duration(days: 1));
          _fromDate = DateTime(lastDayPrev.year, lastDayPrev.month, 1);
          _toDate = DateTime(lastDayPrev.year, lastDayPrev.month,
              lastDayPrev.day, 23, 59, 59);
          break;
        case 'custom':
          // Keep current dates, show date pickers
          break;
      }
    });

    if (preset == 'custom') {
      _showCustomDateRangePicker();
    } else {
      _loadAttendances();
    }
  }

  Future<void> _showCustomDateRangePicker() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
    );
    if (picked != null && mounted) {
      setState(() {
        _fromDate = picked.start;
        _toDate = DateTime(
            picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
      _loadAttendances();
    }
  }

  List<Attendance> get _filteredAttendances {
    var result = _attendances;

    // Filter by branch
    if (_selectedBranchId != null) {
      final branchCodes = _employeesList
          .where((e) => e['branchId']?.toString() == _selectedBranchId)
          .map((e) => e['employeeCode']?.toString() ?? '')
          .where((c) => c.isNotEmpty)
          .toSet();
      result = result.where((a) => branchCodes.contains(a.employeeId)).toList();
    }

    // Filter by verify type
    if (_selectedVerifyType != null) {
      if (_selectedVerifyType == 15) {
        // Face recognition includes both mode 9 and 15
        result = result
            .where((a) => a.verifyType == 15 || a.verifyType == 9)
            .toList();
      } else {
        result =
            result.where((a) => a.verifyType == _selectedVerifyType).toList();
      }
    }

    // Filter by selected employee (mã chấm công)
    if (_filterEmployeeCode != null && _filterEmployeeCode!.isNotEmpty) {
      final code = _filterEmployeeCode!.toLowerCase();
      result = result
          .where((a) =>
              (a.employeeId?.toLowerCase() == code) ||
              (a.enrollNumber?.toLowerCase() == code))
          .toList();
    }

    // Filter by quick search (header)
    if (_searchPin.isNotEmpty) {
      final search = _searchPin.toLowerCase();
      result = result.where((a) {
        return (a.enrollNumber?.toLowerCase().contains(search) ?? false) ||
            (a.employeeName?.toLowerCase().contains(search) ?? false) ||
            (a.employeeId?.toLowerCase().contains(search) ?? false);
      }).toList();
    }

    // Sort
    result.sort((a, b) {
      int cmp;
      switch (_sortColumn) {
        case 'name':
          cmp = (a.employeeName ?? '').compareTo(b.employeeName ?? '');
          break;
        case 'time':
        default:
          cmp = a.punchTime.compareTo(b.punchTime);
      }
      return _sortAscending ? cmp : -cmp;
    });

    return result;
  }

  int? _getSortColumnIndex() {
    switch (_sortColumn) {
      case 'time':
        return 1;
      case 'name':
        return 6;
      default:
        return null;
    }
  }

  void _onSort(String column, bool ascending) {
    setState(() {
      _sortColumn = column;
      _sortAscending = ascending;
      _currentPage = 1;
    });
  }

  Widget _buildMobileHeaderIcon(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }

  bool _hasActiveFilters() {
    return _selectedVerifyType != null ||
        (_filterEmployeeCode != null && _filterEmployeeCode!.isNotEmpty) ||
        _searchPin.isNotEmpty ||
        (_selectedDevices.isNotEmpty &&
            _selectedDevices.length != _devices.length) ||
        _selectedDatePreset != 'week' ||
        _selectedBranchId != null;
  }

  void _clearAttFilters() {
    setState(() {
      _selectedVerifyType = null;
      _filterEmployeeCode = null;
      _searchPin = '';
      _selectedBranchId = null;
      _selectedDevices = _devices.map((d) => d.id).toList();
      _currentPage = 1;
    });
    _applyDatePreset('week');
  }

  String _filterDateLabel() {
    switch (_selectedDatePreset) {
      case 'today':
        return 'Hôm nay';
      case 'yesterday':
        return 'Hôm qua';
      case 'week':
        return 'Tuần này';
      case 'lastWeek':
        return 'Tuần trước';
      case 'month':
        return 'Tháng này';
      case 'lastMonth':
        return 'Tháng trước';
      case 'custom':
        final f = DateFormat('dd/MM/yyyy');
        return '${f.format(_fromDate)} → ${f.format(_toDate)}';
      default:
        return 'Tuần này';
    }
  }

  String _filterDeviceLabel() {
    if (_devices.isEmpty) return 'Chưa có TB';
    if (_selectedDevices.isEmpty ||
        _selectedDevices.length == _devices.length) {
      return 'Tất cả thiết bị';
    }
    final id = _selectedDevices.first;
    for (final d in _devices) {
      if (d.id == id) return d.deviceName;
    }
    return '1 thiết bị';
  }

  String _filterVerifyLabel() {
    if (_selectedVerifyType == null) return 'Tất cả kiểu';
    return _getVerifyTypeName(_selectedVerifyType!);
  }

  String _filterBranchLabel() {
    if (_selectedBranchId == null) return 'Tất cả CN';
    for (final b in _branches) {
      if (b['id']?.toString() == _selectedBranchId) {
        return b['name']?.toString() ?? 'Tất cả CN';
      }
    }
    return 'Tất cả CN';
  }

  String _filterEmployeeLabel() {
    if (_filterEmployeeCode == null || _filterEmployeeCode!.isEmpty) {
      return 'Tất cả NV';
    }
    for (final e in _employeesList) {
      if (e['employeeCode']?.toString() == _filterEmployeeCode) {
        final name =
            '${e['lastName'] ?? ''} ${e['firstName'] ?? ''}'.trim();
        if (name.isNotEmpty) {
          return name.length > 20 ? '${name.substring(0, 20)}…' : name;
        }
      }
    }
    return _filterEmployeeCode!;
  }

  Future<void> _showAttFilterSheet({
    required String title,
    required List<({String label, VoidCallback onPick})> options,
  }) async {
    await showAppSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(tr(title),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            ...options.map(
              (o) => ListTile(
                title: Text(tr(o.label), style: const TextStyle(fontSize: 15)),
                onTap: () {
                  Navigator.pop(ctx);
                  o.onPick();
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFilterEmployee() async {
    String? selectedEmpId;
    for (final e in _employeesList) {
      if (e['employeeCode']?.toString() == _filterEmployeeCode) {
        selectedEmpId = e['id']?.toString();
        break;
      }
    }
    final picked = await EmployeeSearchPicker.pickId(
      context,
      items: EmployeePickerItem.fromMaps(_employeesList),
      selectedId: selectedEmpId,
      title: 'Chọn nhân viên',
      allowClear: true,
    );
    if (!mounted) return;
    setState(() {
      if (picked == null) {
        _filterEmployeeCode = null;
      } else {
        for (final e in _employeesList) {
          if (e['id']?.toString() == picked) {
            _filterEmployeeCode = e['employeeCode']?.toString();
            break;
          }
        }
      }
      _currentPage = 1;
    });
  }

  Widget _buildAttFilterChipRow(List<Widget> chips) {
    return SafeEqualHeightRow(children: chips);
  }

  Widget _buildAttFilterChip({
    required String title,
    required String value,
    required IconData icon,
    required VoidCallback? onTap,
    bool active = false,
  }) {
    final accent = Theme.of(context).primaryColor;
    return Material(
      color: active ? accent.withValues(alpha: 0.08) : const Color(0xFFFAFAFA),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? accent.withValues(alpha: 0.45)
                  : const Color(0xFFE4E4E7),
              width: active ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15,
                      color: active ? accent : Colors.grey[500]),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(tr(title),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600]),
                        maxLines: 1),
                  ),
                  if (onTap != null)
                    Icon(Icons.expand_more,
                        size: 16, color: Colors.grey[500]),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                tr(value),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                  color: active ? accent : const Color(0xFF18181B),
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

  Widget _buildAttendanceFilterBar() {
    final hasFilters = _hasActiveFilters();
    final recordCount = _filteredAttendances.length;

    final chipTime = _buildAttFilterChip(
      title: 'Thời gian',
      value: _filterDateLabel(),
      icon: Icons.date_range_rounded,
      active: _selectedDatePreset != 'week',
      onTap: () => _showAttFilterSheet(
        title: 'Khoảng thời gian',
        options: [
          (label: 'Hôm nay', onPick: () => _applyDatePreset('today')),
          (label: 'Hôm qua', onPick: () => _applyDatePreset('yesterday')),
          (label: 'Tuần này', onPick: () => _applyDatePreset('week')),
          (label: 'Tuần trước', onPick: () => _applyDatePreset('lastWeek')),
          (label: 'Tháng này', onPick: () => _applyDatePreset('month')),
          (label: 'Tháng trước', onPick: () => _applyDatePreset('lastMonth')),
          (label: 'Tùy chọn ngày…', onPick: () => _applyDatePreset('custom')),
        ],
      ),
    );

    final chipDevice = _buildAttFilterChip(
      title: 'Thiết bị',
      value: _filterDeviceLabel(),
      icon: Icons.router_rounded,
      active: _selectedDevices.isNotEmpty &&
          _selectedDevices.length != _devices.length,
      onTap: _devices.isEmpty
          ? null
          : () => _showAttFilterSheet(
                title: 'Thiết bị chấm công',
                options: [
                  (
                    label: 'Tất cả thiết bị',
                    onPick: () {
                      setState(() {
                        _selectedDevices =
                            _devices.map((d) => d.id).toList();
                        _currentPage = 1;
                      });
                      _loadAttendances();
                    }
                  ),
                  ..._devices.map(
                    (d) => (
                      label: d.deviceName,
                      onPick: () {
                        setState(() {
                          _selectedDevices = [d.id];
                          _currentPage = 1;
                        });
                        _loadAttendances();
                      },
                    ),
                  ),
                ],
              ),
    );

    final chipVerify = _buildAttFilterChip(
      title: 'Kiểu xác thực',
      value: _filterVerifyLabel(),
      icon: Icons.fingerprint_rounded,
      active: _selectedVerifyType != null,
      onTap: () => _showAttFilterSheet(
        title: 'Kiểu xác thực',
        options: [
          (
            label: 'Tất cả kiểu',
            onPick: () => setState(() {
              _selectedVerifyType = null;
              _currentPage = 1;
            })
          ),
          (
            label: 'Vân tay',
            onPick: () => setState(() {
              _selectedVerifyType = 1;
              _currentPage = 1;
            })
          ),
          (
            label: 'Khuôn mặt',
            onPick: () => setState(() {
              _selectedVerifyType = 15;
              _currentPage = 1;
            })
          ),
          (
            label: 'Thẻ từ',
            onPick: () => setState(() {
              _selectedVerifyType = 2;
              _currentPage = 1;
            })
          ),
          (
            label: 'Mật khẩu',
            onPick: () => setState(() {
              _selectedVerifyType = 0;
              _currentPage = 1;
            })
          ),
          (
            label: 'Thủ công',
            onPick: () => setState(() {
              _selectedVerifyType = 100;
              _currentPage = 1;
            })
          ),
        ],
      ),
    );

    final chipBranch = BranchFilterHelper.showBranchFilter(_branches)
        ? _buildAttFilterChip(
            title: 'Chi nhánh',
            value: _filterBranchLabel(),
            icon: Icons.account_tree_outlined,
            active: _selectedBranchId != null,
            onTap: () => _showAttFilterSheet(
              title: 'Chi nhánh',
              options: [
                (
                  label: 'Tất cả chi nhánh',
                  onPick: () => setState(() {
                    _selectedBranchId = null;
                    _currentPage = 1;
                  })
                ),
                ..._branches.map(
                  (b) => (
                    label: b['name']?.toString() ?? '',
                    onPick: () => setState(() {
                      _selectedBranchId = b['id']?.toString();
                      _currentPage = 1;
                    }),
                  ),
                ),
              ],
            ),
          )
        : _buildAttFilterChip(
            title: 'Bản ghi',
            value: _attendanceLoadTruncated &&
                    _attendanceServerTotalCount != null &&
                    _attendanceServerTotalCount! > recordCount
                ? '$recordCount / ${_attendanceServerTotalCount} log'
                : '$recordCount bản ghi',
            icon: Icons.analytics_outlined,
            active: _attendanceLoadTruncated,
            onTap: null,
          );

    final chipEmployee = _buildAttFilterChip(
      title: 'Nhân viên',
      value: _filterEmployeeLabel(),
      icon: Icons.person_search_rounded,
      active:
          _filterEmployeeCode != null && _filterEmployeeCode!.isNotEmpty,
      onTap: _employeesList.isEmpty ? null : _pickFilterEmployee,
    );

    final chipClear = _buildAttFilterChip(
      title: 'Bộ lọc',
      value: hasFilters ? 'Xóa lọc' : 'Chưa lọc',
      icon: Icons.filter_alt_off,
      active: hasFilters,
      onTap: hasFilters ? _clearAttFilters : null,
    );

    return HrmFilterBar(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(10),
      children: [
        _buildAttFilterChipRow([chipTime, chipDevice]),
        const SizedBox(height: 8),
        _buildAttFilterChipRow([chipVerify, chipBranch]),
        const SizedBox(height: 8),
        _buildAttFilterChipRow([chipEmployee, chipClear]),
        if (!Responsive.isMobile(context) &&
            canSyncAttendanceFromDevice(
              role: Provider.of<AuthProvider>(context, listen: false)
                  .user
                  ?.role,
              permissions: Provider.of<PermissionProvider>(context,
                  listen: false),
            )) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _syncAttendancesFromDevice,
              icon: const Icon(Icons.sync, size: 18),
              label: Text(tr(_l10n.syncData)),
              style: OutlinedButton.styleFrom(
                foregroundColor: HrmPageChrome.primaryNavy,
                side: const BorderSide(color: HrmPageChrome.primaryNavy),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAttendanceTable() {
    final allFiltered = _filteredAttendances;
    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage).clamp(0, allFiltered.length);
    final displayedAttendances = allFiltered.sublist(startIndex, endIndex);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return _buildAttendanceMobileList(displayedAttendances, startIndex);
        }

        final verticalScrollController = _tableScrollController;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
              topRight: Radius.circular(12),
            ),
            child: Scrollbar(
              thumbVisibility: true,
              controller: verticalScrollController,
              child: SingleChildScrollView(
                controller: verticalScrollController,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        minWidth: MediaQuery.of(context).size.width - 250),
                    child: DataTable(
                      showCheckboxColumn: false,
                      headingRowColor: WidgetStateProperty.all(
                        const Color(0xFFFAFAFA),
                      ),
                      dataRowColor: WidgetStateProperty.resolveWith<Color?>(
                        (states) {
                          if (states.contains(WidgetState.hovered)) {
                            return Theme.of(context)
                                .primaryColor
                                .withValues(alpha: 0.04);
                          }
                          return null;
                        },
                      ),
                      columnSpacing: 16,
                      horizontalMargin: 16,
                      headingRowHeight: 44,
                      dataRowMinHeight: 40,
                      dataRowMaxHeight: 46,
                      dividerThickness: 0.5,
                      sortColumnIndex: _getSortColumnIndex(),
                      sortAscending: _sortAscending,
                      columns: [
                        DataColumn(
                            label: Expanded(
                                child: Text(tr('STT'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: Color(0xFF71717A))))),
                        DataColumn(
                            label: Expanded(
                                child: Text(tr('Ngày'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: Color(0xFF71717A)))),
                            onSort: (_, asc) => _onSort('time', asc)),
                        DataColumn(
                            label: Expanded(
                                child: Text(tr('Giờ'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: Color(0xFF71717A))))),
                        DataColumn(
                            label: Expanded(
                                child: Text(tr('Thứ'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: Color(0xFF71717A))))),
                        DataColumn(
                            label: Expanded(
                                child: Text(tr('UID'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: Color(0xFF71717A))))),
                        DataColumn(
                            label: Expanded(
                                child: Text(tr('Mã nhân viên'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: Color(0xFF71717A))))),
                        DataColumn(
                            label: Expanded(
                                child: Text(tr('Tên nhân viên'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: Color(0xFF71717A)))),
                            onSort: (_, asc) => _onSort('name', asc)),
                        DataColumn(
                            label: Expanded(
                                child: Text(tr('Tên trong máy'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: Color(0xFF71717A))))),
                        DataColumn(
                            label: Expanded(
                                child: Text(tr('Quyền hạn'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: Color(0xFF71717A))))),
                        DataColumn(
                            label: Expanded(
                                child: Text(tr('Thiết bị'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: Color(0xFF71717A))))),
                        DataColumn(
                            label: Expanded(
                                child: Text(tr('Kiểu xác thực'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: Color(0xFF71717A))))),
                        DataColumn(
                            label: Expanded(
                                child: Text(tr('Ghi chú'),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: Color(0xFF71717A))))),
                      ],
                      rows: displayedAttendances.asMap().entries.map((entry) {
                        final index = startIndex + entry.key;
                        final att = entry.value;
                        final dateStr =
                            DateFormat('dd/MM/yyyy').format(att.punchTime);
                        final timeStr =
                            DateFormat('HH:mm:ss').format(att.punchTime);
                        final dayOfWeek =
                            _getDayOfWeekVN(att.punchTime.weekday);

                        return DataRow(
                          onSelectChanged: (_) =>
                              _showAttendanceDetailDialog(att, index),
                          cells: [
                            // STT
                            DataCell(Center(
                              child: Text(
                                tr('${index + 1}'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey,
                                    fontSize: 12),
                              ),
                            )),
                            DataCell(Center(
                              child: Text(
                                tr(dateStr),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500, fontSize: 12),
                              ),
                            )),
                            DataCell(Center(
                              child: Text(
                                tr(timeStr),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).primaryColor,
                                  fontSize: 12,
                                ),
                              ),
                            )),
                            DataCell(Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _getDayColor(att.punchTime.weekday)
                                      .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  tr(dayOfWeek),
                                  style: TextStyle(
                                    color: _getDayColor(att.punchTime.weekday),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            )),
                            // UID - ID từ máy chấm công gửi lên
                            DataCell(Center(
                              child: Text(
                                tr(att.enrollNumber ?? '-'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.blue,
                                    fontSize: 12),
                              ),
                            )),
                            // Mã nhân viên - Liên kết từ bảng Nhân Sự
                            DataCell(Center(
                              child: Text(
                                tr(att.employeeId ?? '-'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500, fontSize: 12),
                              ),
                            )),
                            // Tên NV - Liên kết từ bảng Nhân Sự
                            DataCell(Center(
                              child: Text(
                                tr(att.employeeName ?? '-'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500, fontSize: 12),
                              ),
                            )),
                            // Tên trong máy - Tên không dấu hiển thị khi chấm công
                            DataCell(Center(
                              child: Text(
                                tr(att.deviceUserName ?? '-'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontStyle: FontStyle.italic,
                                    fontSize: 12),
                              ),
                            )),
                            // Quyền hạn
                            DataCell(Center(
                                child: _buildPrivilegeBadge(att.privilege))),
                            DataCell(Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.router,
                                      size: 12, color: Colors.grey),
                                  const SizedBox(width: 3),
                                  Text(tr(att.deviceName ?? '-'),
                                      style: const TextStyle(fontSize: 12)),
                                ],
                              ),
                            )),
                            DataCell(Center(
                                child: _buildVerifyTypeBadge(att.verifyType))),
                            // Ghi chú - hide correction ID marker
                            DataCell(Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_extractCorrectionRequestId(att.note) !=
                                      null)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 4),
                                      child: Icon(Icons.assignment,
                                          size: 14, color: Colors.orange[700]),
                                    ),
                                  Flexible(
                                    child: Text(
                                      tr(_getDisplayNote(att.note)),
                                      style: const TextStyle(fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            )),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Extract correction request ID from attendance note
  String? _extractCorrectionRequestId(String? note) {
    if (note == null) return null;
    final match = RegExp(r'\[YC:([a-f0-9\-]+)\]').firstMatch(note);
    return match?.group(1);
  }

  /// Get display note (without correction ID marker)
  String _getDisplayNote(String? note) {
    if (note == null) return '-';
    return note.replaceAll(RegExp(r'\s*\[YC:[a-f0-9\-]+\]'), '').trim();
  }

  /// Show correction request detail dialog
  void _showCorrectionRequestDetail(String correctionId) async {
    final loadingNav = SafeNavigator.capture(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result =
          await _apiService.getAttendanceCorrectionById(correctionId);
      SafeNavigator.dismissCaptured(loadingNav);
      if (!mounted) return;

      if (result['isSuccess'] == true && result['data'] != null) {
        final data = result['data'] as Map<String, dynamic>;
        final actionMap = {0: 'Thêm mới', 1: 'Sửa giờ', 2: 'Xóa'};
        final statusMap = {0: 'Chờ duyệt', 1: 'Đã duyệt', 2: 'Từ chối'};
        final isMobile = MediaQuery.of(context).size.width < 600;

        final titleRow = Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.assignment, color: Colors.orange),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(tr('Yêu cầu chấm công'),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        );

        final contentBody = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDetailRow(
                'Mã yêu cầu', correctionId.substring(0, 8), Icons.tag),
            _buildDetailRow(
                'Nhân viên', data['employeeName'] ?? '-', Icons.person),
            _buildDetailRow(
                'Mã NV', data['employeeCode'] ?? '-', Icons.numbers),
            _buildDetailRow(
                'Loại', actionMap[data['action']] ?? '-', Icons.category),
            _buildDetailRow(
                'Trạng thái', statusMap[data['status']] ?? '-', Icons.flag),
            if (data['newDate'] != null)
              _buildDetailRow(
                  'Ngày mới',
                  DateFormat('dd/MM/yyyy')
                      .format(DateTime.parse(data['newDate'])),
                  Icons.calendar_today),
            if (data['newTime'] != null)
              _buildDetailRow('Giờ mới',
                  data['newTime'].toString().substring(0, 8), Icons.schedule),
            if (data['oldDate'] != null)
              _buildDetailRow(
                  'Ngày cũ',
                  DateFormat('dd/MM/yyyy')
                      .format(DateTime.parse(data['oldDate'])),
                  Icons.history),
            if (data['oldTime'] != null)
              _buildDetailRow('Giờ cũ',
                  data['oldTime'].toString().substring(0, 8), Icons.history),
            _buildDetailRow('Lý do', data['reason'] ?? '-', Icons.comment),
            if (data['approvedByName'] != null)
              _buildDetailRow(
                  'Người duyệt', data['approvedByName'], Icons.verified),
            if (data['approvedDate'] != null)
              _buildDetailRow(
                  'Ngày duyệt',
                  DateFormat('dd/MM/yyyy HH:mm')
                      .format(DateTime.parse(data['approvedDate'])),
                  Icons.check_circle),
            if (data['approverNote'] != null &&
                data['approverNote'].toString().isNotEmpty)
              _buildDetailRow(
                  'Ghi chú duyệt', data['approverNote'], Icons.note),
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
                    title: Text(tr('Yêu cầu chấm công')),
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
                    .min(400, MediaQuery.of(context).size.width - 32)
                    .toDouble(),
                child: SingleChildScrollView(child: contentBody),
              ),
              actions: [
                FilledButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close, size: 18),
                  label: Text(tr('Đóng')),
                ),
              ],
            ),
          );
        }
      } else {
        appNotification.showError(
          title: _l10n.error,
          message: tr('Không tìm thấy yêu cầu chấm công'),
        );
      }
    } catch (e) {
      SafeNavigator.dismissCaptured(loadingNav);
      if (!mounted) return;
      appNotification.showError(
        title: _l10n.error,
        message: tr('Lỗi: $e'),
      );
    }
  }

  /// Mobile card list for attendance records - grouped by date
  Widget _buildAttendanceMobileList(List<Attendance> items, int startIndex,
      {bool shrinkWrap = false}) {
    // Group items by date
    final Map<String, List<MapEntry<int, Attendance>>> grouped = {};
    for (var i = 0; i < items.length; i++) {
      final att = items[i];
      final dateKey = DateFormat('yyyy-MM-dd').format(att.punchTime);
      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add(MapEntry(startIndex + i, att));
    }
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // newest first

    if (shrinkWrap) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var groupIdx = 0; groupIdx < sortedKeys.length; groupIdx++)
              _buildAttendanceDateGroup(
                groupIdx: groupIdx,
                sortedKeys: sortedKeys,
                grouped: grouped,
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      itemCount: sortedKeys.length,
      itemBuilder: (context, groupIdx) => _buildAttendanceDateGroup(
        groupIdx: groupIdx,
        sortedKeys: sortedKeys,
        grouped: grouped,
      ),
    );
  }

  Widget _buildAttendanceDateGroup({
    required int groupIdx,
    required List<String> sortedKeys,
    required Map<String, List<MapEntry<int, Attendance>>> grouped,
  }) {
    final dateKey = sortedKeys[groupIdx];
    final date = DateTime.parse(dateKey);
    final dateStr = DateFormat('dd/MM/yyyy').format(date);
    final dayOfWeek = _getDayOfWeekVN(date.weekday);
    final dayColor = _getDayColor(date.weekday);
    final entries = grouped[dateKey]!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Date header
        Padding(
          padding: EdgeInsets.fromLTRB(2, groupIdx == 0 ? 0 : 8, 0, 6),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: dayColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today, size: 13, color: dayColor),
                    const SizedBox(width: 5),
                    Text(tr('$dayOfWeek, $dateStr'),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: dayColor)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(tr('${entries.length}'),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade600)),
              ),
              const Spacer(),
            ],
          ),
        ),
        // Attendance rows - individual cards
        ...entries.map((e) {
          final globalIdx = e.key;
          final att = e.value;
          final timeStr = DateFormat('HH:mm:ss').format(att.punchTime);

          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE4E4E7)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _showAttendanceDetailDialog(att, globalIdx),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  child: _buildAttendanceMobileCardBody(att, timeStr),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildAttendanceMobileCardBody(Attendance att, String timeStr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row 1: Name + Time
        Row(
          children: [
            Expanded(
              child: Text(
                tr(att.employeeName ?? att.pin ?? '—'),
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              tr(timeStr),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).primaryColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Row 2: Verify type + Device
        Row(
          children: [
            _buildVerifyTypeIcon(att.verifyType),
            const SizedBox(width: 4),
            Text(tr(_getVerifyTypeName(att.verifyType)),
                style: const TextStyle(
                    fontSize: 12, color: Color(0xFF71717A))),
            if (att.deviceName != null && att.deviceName!.isNotEmpty) ...[
              const SizedBox(width: 8),
              const Icon(Icons.router, size: 12, color: Color(0xFFA1A1AA)),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  tr(att.deviceName!),
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF71717A)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ] else
              const Spacer(),
          ],
        ),
      ],
    );
  }

  /// Compact verify type icon only (no text)
  Widget _buildVerifyTypeIcon(int verifyType) {
    IconData icon;
    Color color;
    switch (verifyType) {
      case 0:
        icon = Icons.password;
        color = Colors.grey;
        break;
      case 1:
        icon = Icons.fingerprint;
        color = Colors.blue;
        break;
      case 2:
        icon = Icons.credit_card;
        color = Colors.orange;
        break;
      case 9:
      case 15:
        icon = Icons.face;
        color = Colors.green;
        break;
      case 100:
        icon = Icons.edit;
        color = Colors.purple;
        break;
      default:
        icon = Icons.help;
        color = Colors.grey;
    }
    return Icon(icon, size: 16, color: color);
  }

  /// Show attendance detail dialog when row is clicked
  Future<void> _showAttendanceDetailDialog(Attendance att, int index) async {
    var detailAtt = att;
    MobileAttendanceRecord? mobileDetail;
    final mobileId = att.mobileAttendanceRecordId?.trim();
    if (mobileId != null && mobileId.isNotEmpty) {
      try {
        final res = await _apiService.getMobileAttendanceRecord(mobileId);
        if (res['isSuccess'] == true && res['data'] is Map) {
          final data = Map<String, dynamic>.from(res['data'] as Map);
          mobileDetail = MobileAttendanceRecord.fromJson(data);
          if (mobileDetail.status == 'pending') {
            final url = mobileDetail.sitePhotoUrl?.trim();
            if (url != null && url.isNotEmpty) {
              detailAtt = att.copyWith(sitePhotoUrl: url);
            }
          }
        }
      } catch (e) {
        debugPrint('Load mobile detail for raw attendance: $e');
      }
    }
    if (!mounted) return;

    final dateStr = DateFormat('dd/MM/yyyy').format(detailAtt.punchTime);
    final timeStr = DateFormat('HH:mm:ss').format(att.punchTime);
    final dayOfWeek = _getDayOfWeekVN(att.punchTime.weekday);
    final isMobile = MediaQuery.of(context).size.width < 600;

    final titleRow = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.access_time,
            color: Theme.of(context).primaryColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Chi tiết chấm công'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                tr('STT: ${index + 1}'),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ],
    );

    final contentBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Icon(Icons.calendar_today,
                        color: Theme.of(context).primaryColor, size: 24),
                    const SizedBox(height: 8),
                    Text(tr(dateStr),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(tr(dayOfWeek),
                        style:
                            TextStyle(color: Colors.grey[600], fontSize: 12)),
                  ],
                ),
              ),
              Container(width: 1, height: 60, color: Colors.grey[300]),
              Expanded(
                child: Column(
                  children: [
                    Icon(Icons.schedule,
                        color: Theme.of(context).primaryColor, size: 24),
                    const SizedBox(height: 8),
                    Text(tr(timeStr),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(tr(detailAtt.punchTypeText),
                        style: TextStyle(
                          color: detailAtt.attendanceState == 0
                              ? Colors.green
                              : Colors.orange,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildDetailRow('ID chấm công', detailAtt.id, Icons.fingerprint),
        _buildDetailRow('UID (Mã máy)', detailAtt.enrollNumber ?? '-', Icons.badge),
        _buildDetailRow('Mã nhân viên', detailAtt.employeeId ?? '-', Icons.numbers),
        _buildDetailRow('Tên nhân viên', detailAtt.employeeName ?? '-', Icons.person),
        _buildDetailRow(
            'Tên trong máy', detailAtt.deviceUserName ?? '-', Icons.text_fields),
        _buildDetailRow(
            'Quyền hạn', detailAtt.privilegeText, Icons.admin_panel_settings),
        _buildDetailRow(
            'Thiết bị', detailAtt.deviceName ?? detailAtt.deviceId ?? '-', Icons.router),
        _buildDetailRow('Loại xác thực', _getVerifyTypeName(detailAtt.verifyType),
            Icons.verified_user),
        if (detailAtt.workCode != null && detailAtt.workCode!.isNotEmpty)
          _buildDetailRow('Mã công việc', detailAtt.workCode!, Icons.work),
        if (detailAtt.note != null &&
            _getDisplayNote(detailAtt.note).isNotEmpty &&
            _getDisplayNote(detailAtt.note) != '-')
          _buildDetailRow('Ghi chú', _getDisplayNote(detailAtt.note), Icons.note),
        ..._buildAttendanceLocationDetailWidgets(detailAtt,
            mobile: mobileDetail),
        if (detailAtt.createdAt != null)
          _buildDetailRow(
              'Thời gian tạo',
              DateFormat('dd/MM/yyyy HH:mm:ss').format(detailAtt.createdAt!),
              Icons.create),
        if (_extractCorrectionRequestId(detailAtt.note) != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.assignment, color: Colors.orange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(tr('Từ yêu cầu chấm công đã duyệt'),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.orange),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _showCorrectionRequestDetail(
                        _extractCorrectionRequestId(detailAtt.note)!);
                  },
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(tr('Xem'), style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final canEdit = canEditAttendanceRecord(role: auth.user?.role, permissions: perm);
    final canDelete =
        canDeleteAttendanceRecord(role: auth.user?.role, permissions: perm);

    final actionButtons = <Widget>[
      if (canDelete)
        TextButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            _confirmDeleteAttendance(detailAtt);
          },
          icon: const Icon(Icons.delete, color: Colors.red, size: 18),
          label: Text(tr('Xóa'), style: TextStyle(color: Colors.red)),
        ),
      if (canEdit)
        TextButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            _showEditAttendanceDialog(detailAtt);
          },
          icon:
              Icon(Icons.edit, color: Theme.of(context).primaryColor, size: 18),
          label: Text(tr('Sửa'),
              style: TextStyle(color: Theme.of(context).primaryColor)),
        ),
      FilledButton.icon(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.close, size: 18),
        label: Text(tr('Đóng')),
      ),
    ];

    if (isMobile) {
      showDialog(
        context: context,
        useSafeArea: false,
        builder: (context) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(tr('Chi tiết chấm công')),
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
            bottomNavigationBar: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: actionButtons,
              ),
            ),
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 800,
              maxHeight: MediaQuery.of(context).size.height * 0.9,
            ),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
                title: Text(tr('Chi tiết chấm công')),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleRow,
                    const SizedBox(height: 16),
                    contentBody,
                  ],
                ),
              ),
              bottomNavigationBar: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: actionButtons,
                ),
              ),
            ),
          ),
        ),
      );
    }
  }

  static String? _nonEmptyPhotoPath(String? path) {
    final s = path?.trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  List<Widget> _buildAttendanceLocationDetailWidgets(
    Attendance att, {
    MobileAttendanceRecord? mobile,
  }) {
    final widgets = <Widget>[];
    if (att.isFromMobile) {
      widgets.add(_buildDetailRow(
          'Nguồn', 'Chấm công mobile', Icons.phone_android_outlined));
    }
    if (att.locationName != null && att.locationName!.trim().isNotEmpty) {
      widgets.add(_buildDetailRow(
          'Điểm chấm', att.locationName!.trim(), Icons.place_outlined));
    }
    if (att.hasGpsLocation) {
      widgets.add(const SizedBox(height: 12));
      widgets.add(Text(tr('Vị trí GPS lúc chấm'),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF18181B),
        ),
      ));
      widgets.add(const SizedBox(height: 8));
      widgets.add(PunchLocationPreview(
        latitude: att.latitude!,
        longitude: att.longitude!,
        onTap: () => _openAttendanceGpsMap(att),
      ));
      widgets.add(const SizedBox(height: 8));
      widgets.add(Text(
        tr('${att.latitude!.toStringAsFixed(6)}, ${att.longitude!.toStringAsFixed(6)}'),
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      ));
      widgets.add(const SizedBox(height: 8));
      widgets.add(SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _openAttendanceGpsMap(att),
          icon: const Icon(Icons.map_outlined, size: 18),
          label: Text(tr('Xem trên bản đồ')),
        ),
      ));
    }
    final showPendingSitePhoto = mobile?.status == 'pending';
    if (showPendingSitePhoto) {
      widgets.add(const SizedBox(height: 12));
      widgets.add(Text(tr('Ảnh hiện trường (check-in CT)'),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF18181B),
        ),
      ));
      widgets.add(const SizedBox(height: 8));
      final sitePhotoPath = _nonEmptyPhotoPath(mobile?.sitePhotoUrl) ??
          _nonEmptyPhotoPath(att.sitePhotoUrl);
      widgets.add(PunchPhotoPreview(
        imagePath: sitePhotoPath,
        apiService: _apiService,
        emptyHint: sitePhotoPath == null
            ? 'Chưa có ảnh hiện trường — chụp khi chấm công (bản ghi chờ duyệt)'
            : null,
      ));
    }
    if (!att.hasGpsLocation &&
        !(mobile?.sitePhotoUrl?.trim().isNotEmpty == true || att.hasSitePhoto) &&
        att.isFromMobile &&
        att.mobileAttendanceRecordId != null &&
        att.mobileAttendanceRecordId!.isNotEmpty) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Vị trí GPS nằm trong bản ghi chấm công mobile.'),
              style: TextStyle(fontSize: 12, color: Color(0xFF1E40AF)),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: () => _openMobileDetailFromRaw(att),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(tr('Xem chi tiết mobile')),
            ),
          ],
        ),
      ));
    }
    return widgets;
  }

  Future<void> _openAttendanceGpsMap(Attendance att) async {
    if (!att.hasGpsLocation) return;
    final lat = att.latitude!;
    final lng = att.longitude!;
    final title = att.locationName?.trim().isNotEmpty == true
        ? att.locationName!.trim()
        : (att.employeeName ?? 'Vị trí chấm');

    if (MediaQuery.of(context).size.width < 600) {
      final uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => MapLocationPicker(
        initialLatitude: lat,
        initialLongitude: lng,
        initialZoom: 17,
        title: title,
        readOnly: true,
      ),
    );
  }

  Future<void> _openMobileDetailFromRaw(Attendance att) async {
    final id = att.mobileAttendanceRecordId?.trim();
    if (id == null || id.isEmpty) return;
    try {
      final res = await _apiService.getMobileAttendanceRecord(id);
      if (!mounted) return;
      if (res['isSuccess'] == true && res['data'] is Map) {
        final record = MobileAttendanceRecord.fromJson(
            Map<String, dynamic>.from(res['data'] as Map));
        await showMobileAttendanceRecordDetailSheet(
          context,
          record: record,
          apiService: _apiService,
        );
      } else {
        appNotification.showError(
          title: 'Lỗi',
          message: res['message']?.toString() ??
              'Không tải được chi tiết chấm công mobile',
        );
      }
    } catch (e) {
      if (!mounted) return;
      appNotification.showError(
        title: 'Lỗi',
        message: tr('Không tải được chi tiết: $e'),
      );
    }
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: Text(
              tr(label),
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              tr(value),
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Confirm delete attendance
  void _confirmDeleteAttendance(Attendance att) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    if (!canDeleteAttendanceRecord(role: auth.user?.role, permissions: perm)) {
      return;
    }
    showDialog(
      context: context,
      builder: (context) => ScrollableAlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text(tr('Xác nhận xóa')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Bạn có chắc muốn xóa bản ghi chấm công này?')),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Nhân viên: ${att.employeeName ?? att.enrollNumber ?? "N/A"}'),
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text(tr('${tr('Thời gian: ')}${DateFormat('dd/MM/yyyy HH:mm:ss').format(att.punchTime)}')),
                  Text(tr('Thiết bị: ${att.deviceName ?? "N/A"}')),
                ],
              ),
            ),
          ],
        ),
        actions: [
          AppDialogActions.delete(
            onConfirm: () {
              Navigator.of(context).pop();
              _deleteAttendance(att);
            },
          ),
        ],
      ),
    );
  }

  /// Delete attendance
  Future<void> _deleteAttendance(Attendance att) async {
    try {
      final success = await _apiService.deleteAttendance(att.id);

      if (success) {
        setState(() {
          _attendances.removeWhere((a) => a.id == att.id);
        });

        if (mounted) {
          appNotification.showSuccess(
            title: 'Thành công',
            message: tr('Đã xóa bản ghi chấm công'),
          );
        }
      } else {
        throw Exception('Failed to delete attendance');
      }
    } catch (e) {
      if (mounted) {
        appNotification.showError(
          title: 'Lỗi xóa',
          message: '$e',
        );
      }
    }
  }

  /// Show edit attendance dialog
  void _showEditAttendanceDialog(Attendance att) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    if (!canEditAttendanceRecord(role: auth.user?.role, permissions: perm)) {
      return;
    }
    final dateController = TextEditingController(
      text: tr(DateFormat('dd/MM/yyyy').format(att.punchTime)),
    );
    final timeController = TextEditingController(
      text: tr(DateFormat('HH:mm:ss').format(att.punchTime)),
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => ScrollableAlertDialog(
          title: Row(
            children: [
              Icon(Icons.edit, color: Colors.blue),
              SizedBox(width: 8),
              Text(tr('Sửa chấm công')),
            ],
          ),
          content: SizedBox(
            width: math
                .min(400, MediaQuery.of(context).size.width - 32)
                .toDouble(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Employee info (read-only)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person, color: Colors.grey),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr(att.employeeName ?? att.enrollNumber ?? 'N/A'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(tr('UID: ${att.enrollNumber ?? "-"} • Mã NV: ${att.employeeId ?? "-"}'),
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Date picker
                TextField(
                  controller: dateController,
                  decoration: InputDecoration(
                    labelText: tr('Ngày'),
                    prefixIcon: const Icon(Icons.calendar_today),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  readOnly: true,
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: att.punchTime,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 1)),
                    );
                    if (date != null) {
                      dateController.text =
                          DateFormat('dd/MM/yyyy').format(date);
                    }
                  },
                ),
                const SizedBox(height: 12),

                // Time picker
                TextField(
                  controller: timeController,
                  decoration: InputDecoration(
                    labelText: tr('Giờ'),
                    prefixIcon: const Icon(Icons.access_time),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  readOnly: true,
                  onTap: () async {
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(att.punchTime),
                    );
                    if (time != null) {
                      timeController.text =
                          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';
                    }
                  },
                ),
                const SizedBox(height: 12),

                // Attendance state info (read-only, auto-calculated)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.blue[700], size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('Loại chấm công: ${att.attendanceState == 0 ? "Chấm vào" : "Chấm ra"}'),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[700],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(tr('Tự động xác định dựa trên thứ tự chấm công trong ngày (lẻ = Vào, chẵn = Ra)'),
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.blue[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            AppDialogActions(
              onConfirm: () {
                Navigator.of(context).pop();
                _updateAttendance(
                    att, dateController.text, timeController.text);
              },
              confirmLabel: _l10n.save,
              confirmIcon: Icons.save,
            ),
          ],
        ),
      ),
    ).then((_) {
      dateController.dispose();
      timeController.dispose();
    });
  }

  /// Update attendance (only time, state is auto-calculated)
  Future<void> _updateAttendance(
      Attendance att, String dateStr, String timeStr) async {
    try {
      // Parse date and time
      final dateParts = dateStr.split('/');
      final timeParts = timeStr.split(':');
      final newDateTime = DateTime(
        int.parse(dateParts[2]), // year
        int.parse(dateParts[1]), // month
        int.parse(dateParts[0]), // day
        int.parse(timeParts[0]), // hour
        int.parse(timeParts[1]), // minute
        int.parse(timeParts[2]), // second
      );

      final success = await _apiService.updateAttendance(
        att.id,
        attendanceTime: newDateTime,
        // Don't pass attendanceState - it's auto-calculated on backend
      );

      if (success) {
        // Reload data
        _loadAttendances();

        if (mounted) {
          appNotification.showSuccess(
            title: 'Thành công',
            message: tr('Đã cập nhật bản ghi chấm công'),
          );
        }
      } else {
        throw Exception('Failed to update attendance');
      }
    } catch (e) {
      if (mounted) {
        appNotification.showError(
          title: 'Lỗi cập nhật',
          message: '$e',
        );
      }
    }
  }

  String _getVerifyTypeName(int verifyType) =>
      Attendance.verifyModeLabel(verifyType);

  Widget _buildPrivilegeBadge(int privilege) {
    final isAdmin = privilege == 14;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isAdmin
            ? Colors.orange.withValues(alpha: 0.1)
            : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAdmin ? Colors.orange : Colors.grey,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAdmin ? Icons.admin_panel_settings : Icons.person,
            size: 14,
            color: isAdmin ? Colors.orange : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(
            tr(isAdmin
                ? Attendance.privilegeLabel(14)
                : Attendance.privilegeLabel(0)),
            style: TextStyle(
              color: isAdmin ? Colors.orange : Colors.grey,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String _getDayOfWeekVN(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Thứ 2';
      case DateTime.tuesday:
        return 'Thứ 3';
      case DateTime.wednesday:
        return 'Thứ 4';
      case DateTime.thursday:
        return 'Thứ 5';
      case DateTime.friday:
        return 'Thứ 6';
      case DateTime.saturday:
        return 'Thứ 7';
      case DateTime.sunday:
        return 'CN';
      default:
        return '-';
    }
  }

  Color _getDayColor(int weekday) {
    switch (weekday) {
      case DateTime.saturday:
        return Colors.blue;
      case DateTime.sunday:
        return Colors.red;
      default:
        return const Color(0xFF71717A);
    }
  }

  // ignore: unused_element
  Widget _buildPunchTypeBadge(int punchType) {
    Color color;
    String text;

    switch (punchType) {
      case 0:
        color = Colors.green;
        text = 'Vào';
        break;
      case 1:
        color = Colors.orange;
        text = 'Ra';
        break;
      case 2:
        color = Colors.blue;
        text = 'Nghỉ ra';
        break;
      case 3:
        color = Colors.teal;
        text = 'Nghỉ vào';
        break;
      case 4:
        color = Colors.purple;
        text = 'OT vào';
        break;
      case 5:
        color = Colors.indigo;
        text = 'OT ra';
        break;
      default:
        color = Colors.grey;
        text = 'Khác';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        tr(text),
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildVerifyTypeBadge(int verifyType) {
    IconData icon;
    String text;
    Color color = Colors.grey;

    switch (verifyType) {
      case 0:
        icon = Icons.password;
        text = 'Mật khẩu';
        break;
      case 1:
        icon = Icons.fingerprint;
        text = 'Vân tay';
        color = Colors.blue;
        break;
      case 2:
        icon = Icons.credit_card;
        text = 'Thẻ';
        color = Colors.orange;
        break;
      case 9:
      case 15:
        icon = Icons.face;
        text = 'Khuôn mặt';
        color = Colors.green;
        break;
      case 100:
        icon = Icons.edit;
        text = 'Thủ công';
        color = Colors.purple;
        break;
      default:
        icon = Icons.help;
        text = 'Khác';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          tr(text),
          style: TextStyle(color: color, fontSize: 12),
        ),
      ],
    );
  }

  // ignore: unused_element
  Future<void> _selectDate(bool isFromDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isFromDate ? _fromDate : _toDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: Theme.of(context).primaryColor,
              onPrimary: Colors.white,
              surface: const Color(0xFF18181B),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isFromDate) {
          _fromDate = picked;
        } else {
          _toDate = picked;
        }
      });
    }
  }

}


/// Custom notification widget that appears at top-right corner
class _AttendanceNotificationWidget extends StatefulWidget {
  final String userName;
  final String stateText;
  final String timeStr;
  final String deviceName;
  final bool isCheckIn;
  final String verifyType;
  final VoidCallback onDismiss;

  const _AttendanceNotificationWidget({
    required this.userName,
    required this.stateText,
    required this.timeStr,
    required this.deviceName,
    required this.isCheckIn,
    required this.verifyType,
    required this.onDismiss,
  });

  @override
  State<_AttendanceNotificationWidget> createState() =>
      _AttendanceNotificationWidgetState();
}

class _AttendanceNotificationWidgetState
    extends State<_AttendanceNotificationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward();

    // Auto dismiss after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        _dismiss();
      }
    });
  }

  void _dismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 80,
      right: 16,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 320,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: widget.isCheckIn
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: widget.isCheckIn ? Colors.green : Colors.orange,
                  width: 2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:
                              widget.isCheckIn ? Colors.green : Colors.orange,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          widget.isCheckIn ? Icons.login : Icons.logout,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tr('Chấm công ${widget.isCheckIn ? "VÀO" : "RA"}'),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: widget.isCheckIn
                                    ? Colors.green.shade700
                                    : Colors.orange.shade700,
                              ),
                            ),
                            Text(
                              tr(widget.timeStr),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: _dismiss,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.person, size: 16, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr(widget.userName),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.router, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 8),
                      Text(
                        tr(widget.deviceName),
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF71717A)),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          tr(widget.verifyType),
                          style: const TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
