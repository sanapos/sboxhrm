import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import '../utils/file_saver.dart' as file_saver;
import '../utils/platform_storage.dart' as platform_storage;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel_lib;
import '../models/attendance.dart';
import '../models/device.dart';
import '../models/employee.dart';
import '../services/api_service.dart';
import '../services/signalr_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/loading_widget.dart';
import '../widgets/empty_state.dart';
import '../widgets/notification_overlay.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../widgets/app_button.dart';
import 'attendance/attendance_correction_tab.dart'
    show CorrectionRequestInternal, CorrectionStatus;
import 'main_layout.dart' show ScreenRefreshNotifier;
import '../l10n/app_localizations.dart';

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

  // Danh sách yêu cầu chỉnh sửa chấm công (lưu ở state cha để chia sẻ giữa các tab)
  List<CorrectionRequestInternal> _pendingCorrectionRequests = [];
  List<CorrectionRequestInternal> _processedCorrectionRequests = [];

  // LocalStorage keys
  static const String _pendingRequestsKey = 'pending_correction_requests';
  static const String _processedRequestsKey = 'processed_correction_requests';

  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _toDate = DateTime.now();
  List<String> _selectedDevices = [];
  String _searchPin = ''; // Filter theo ID/PIN nhân viên
  String _selectedDatePreset =
      'week'; // Preset: today, yesterday, week, lastWeek, month, lastMonth, custom
  int?
      _selectedVerifyType; // null = all, 0 = password, 1 = fingerprint, 2 = card, 15 = face

  // Sorting
  String _sortColumn = 'time';
  bool _sortAscending = false;

  // Mobile UI state
  bool _showMobileFilters = false;
  bool _showMobileSearch = false;
  bool _showMobileSummary = false;

  // Pagination
  int _currentPage = 1;
  int _itemsPerPage = 50;
  final List<int> _pageSizeOptions = [25, 50, 100, 200];

  @override
  void initState() {
    super.initState();
    _loadCorrectionRequestsFromStorage();
    _loadDevices();
    _connectSignalR();
    
    // Listen for external refresh triggers
    ScreenRefreshNotifier.attendance.addListener(_onExternalRefresh);
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
      debugPrint('   Pending: ${_pendingCorrectionRequests.length} items (${pendingJson.length} chars)');
      debugPrint('   Processed: ${_processedCorrectionRequests.length} items (${processedJson.length} chars)');
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
    ScreenRefreshNotifier.attendance.removeListener(_onExternalRefresh);
    super.dispose();
  }

  /// Connect to SignalR for real-time updates
  Future<void> _connectSignalR() async {
    try {
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

      final result = await _apiService.getAttendances(
        deviceIds: _selectedDevices,
        fromDate: _fromDate,
        toDate: _toDate,
        pageSize: 500, // Tăng để lấy nhiều dữ liệu hơn
      );

      if (mounted) {
        var attendanceList = (result['items'] as List)
            .map((e) => Attendance.fromJson(e))
            .toList();

        // Sắp xếp theo thời gian mới nhất trước
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

    setState(() => _isLoading = true);

    try {
      int successCount = 0;
      int failCount = 0;
      final offlineDevices = <String>[];

      for (final deviceId in _selectedDevices) {
        // Kiểm tra online trước
        final isOnline = await _apiService.isDeviceOnline(deviceId);
        if (!isOnline) {
          failCount++;
          final dev = _devices.where((d) => d.id == deviceId).firstOrNull;
          offlineDevices.add(dev?.deviceName ?? deviceId);
          continue;
        }
        final success = await _apiService.sendSyncAttendancesCommand(deviceId);
        if (success) {
          successCount++;
        } else {
          failCount++;
        }
      }

      if (mounted) {
        if (offlineDevices.isNotEmpty) {
          appNotification.showError(
            title: 'Thiết bị offline',
            message: 'Các thiết bị đang offline: ${offlineDevices.join(", ")}. Vui lòng kiểm tra kết nối mạng của máy chấm công.',
          );
        } else if (successCount > 0) {
          appNotification.showSuccess(
            title: _l10n.syncData,
            message:
                'Đã gửi lệnh đồng bộ: $successCount thành công, $failCount thất bại. Chờ thiết bị phản hồi...',
          );
        } else {
          appNotification.showError(
            title: _l10n.syncData,
            message:
                'Đã gửi lệnh đồng bộ: $successCount thành công, $failCount thất bại',
          );
        }

        // Chờ 15 giây để thiết bị gửi dữ liệu rồi load lại
        await Future.delayed(const Duration(seconds: 15));
        await _loadAttendances();
      }
    } catch (e) {
      debugPrint('Error syncing attendances: $e');
      if (mounted) {
        appNotification.showError(
          title: _l10n.syncError,
          message: '$e',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.add_circle, color: Colors.orange[400]),
              const SizedBox(width: 8),
              const Text('Chấm công thủ công'),
            ],
          ),
          content: SizedBox(
            width: math.min(500, MediaQuery.of(context).size.width - 32).toDouble(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Employee dropdown
                DropdownButtonFormField<Employee>(
                  initialValue: selectedEmployee,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: '${_l10n.employee} *',
                    prefixIcon: const Icon(Icons.person),
                    border: const OutlineInputBorder(),
                  ),
                  items: employees
                      .map<DropdownMenuItem<Employee>>(
                          (e) => DropdownMenuItem<Employee>(
                                value: e,
                                child: Text(
                                  '${e.employeeCode} - ${e.fullName}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                      .toList(),
                  selectedItemBuilder: (context) => employees
                      .map((e) => Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${e.employeeCode} - ${e.fullName}',
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
                    labelText: '${_l10n.device} *',
                    prefixIcon: const Icon(Icons.devices),
                    border: const OutlineInputBorder(),
                  ),
                  items: _devices
                      .map<DropdownMenuItem<Device>>(
                          (d) => DropdownMenuItem<Device>(
                                value: d,
                                child: Text(
                                  d.deviceName,
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
                  title: Text(_l10n.date),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(selectedDate)),
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
                  title: Text(_l10n.time),
                  subtitle: Text(selectedTime.format(context)),
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
                    labelText: _l10n.note,
                    prefixIcon: const Icon(Icons.note),
                    border: const OutlineInputBorder(),
                    hintText: '${_l10n.manualAttendance}...',
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
                          '${_l10n.authType}: ${_l10n.manual}',
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

                      final success = await _apiService.createManualAttendance(
                        employeeId: selectedEmployee!.id,
                        punchTime: punchTime,
                        deviceId: selectedDevice!.id,
                        note: note.isEmpty ? 'Chấm công thủ công' : note,
                      );

                      if (mounted) {
                        setState(() => _isLoading = false);

                        if (success) {
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

  /// Import attendances from Excel file
  Future<void> _importFromExcel() async {
    try {
      // Show import instructions dialog first
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.upload_file, color: Colors.blue[400]),
              const SizedBox(width: 8),
              const Text('Import từ Excel'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('File Excel cần có các cột sau:'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[600]!),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• Mã NV (bắt buộc)',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('• Ngày (dd/MM/yyyy) (bắt buộc)'),
                    Text('• Giờ (HH:mm:ss) (bắt buộc)'),
                    Text('• Ghi chú (tùy chọn)'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
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
                    const Expanded(
                      child: Text(
                        'Tất cả bản ghi import sẽ có kiểu xác thực: Thủ công',
                        style: TextStyle(fontSize: 12),
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

      // Pick Excel file
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
            message: 'Không thể đọc file',
          );
        }
        return;
      }

      setState(() => _isLoading = true);

      // Parse Excel file
      final excelData = excel_lib.Excel.decodeBytes(bytes);
      final records = <Map<String, dynamic>>[];

      for (final table in excelData.tables.keys) {
        final sheet = excelData.tables[table];
        if (sheet == null) continue;

        // Skip header row
        for (int i = 1; i < sheet.rows.length; i++) {
          final row = sheet.rows[i];
          if (row.isEmpty) continue;

          // Get cell values
          final employeeCode =
              row.isNotEmpty ? row[0]?.value?.toString() : null;
          final dateStr = row.length > 1 ? row[1]?.value?.toString() : null;
          final timeStr = row.length > 2 ? row[2]?.value?.toString() : null;
          final note = row.length > 3 ? row[3]?.value?.toString() : null;

          if (employeeCode == null || dateStr == null || timeStr == null) {
            continue;
          }

          // Parse date and time
          DateTime? punchTime;
          try {
            // Try multiple date formats
            final dateParts = dateStr.split(RegExp(r'[/\-.]'));
            if (dateParts.length == 3) {
              final day = int.parse(dateParts[0]);
              final month = int.parse(dateParts[1]);
              final year = int.parse(dateParts[2]);

              final timeParts = timeStr.split(':');
              final hour = timeParts.isNotEmpty ? int.parse(timeParts[0]) : 0;
              final minute = timeParts.length > 1 ? int.parse(timeParts[1]) : 0;
              final second = timeParts.length > 2 ? int.parse(timeParts[2]) : 0;

              punchTime = DateTime(year, month, day, hour, minute, second);
            }
          } catch (e) {
            debugPrint('Error parsing date/time: $e');
          }

          if (punchTime == null) continue;

          records.add({
            'employeeCode': employeeCode,
            'punchTime': punchTime.toIso8601String(),
            'note': note ?? 'Import từ Excel',
            'verifyType': 100, // Manual
            'isManual': true,
          });
        }

        break; // Only process first sheet
      }

      if (records.isEmpty) {
        setState(() => _isLoading = false);
        if (mounted) {
          appNotification.showWarning(
            title: 'Không có dữ liệu',
            message: 'Không tìm thấy dữ liệu hợp lệ trong file',
          );
        }
        return;
      }

      // Send to API
      final importResult =
          await _apiService.importAttendancesFromExcel(records);

      setState(() => _isLoading = false);

      if (mounted) {
        if (importResult['success'] == true) {
          appNotification.showSuccess(
            title: 'Import thành công',
            message: 'Import thành công: ${importResult['imported']} bản ghi'
                '${importResult['failed'] > 0 ? ', ${importResult['failed']} thất bại' : ''}',
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

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;
    final isMobile = Responsive.isMobile(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          // Modern gradient header
          Container(
            padding: EdgeInsets.fromLTRB(isMobile ? 14 : 24, isMobile ? 12 : 18, isMobile ? 14 : 24, isMobile ? 10 : 14),
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
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title row with search + filter icons
                      if (!_showMobileSearch)
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.access_time_filled, size: 18, color: Colors.white),
                            ),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: Text(
                                'Chấm công',
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                            ),
                            _buildRealtimeIndicator(),
                            const SizedBox(width: 4),
                            // Search icon
                            _buildMobileHeaderIcon(Icons.search, () {
                              setState(() => _showMobileSearch = true);
                            }),
                            const SizedBox(width: 4),
                            // Filter icon with active indicator
                            Stack(
                              children: [
                                _buildMobileHeaderIcon(
                                  _showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
                                  () => setState(() => _showMobileFilters = !_showMobileFilters),
                                ),
                                if (_hasActiveFilters())
                                  Positioned(
                                    right: 4,
                                    top: 4,
                                    child: Container(
                                      width: 8, height: 8,
                                      decoration: const BoxDecoration(color: Colors.orangeAccent, shape: BoxShape.circle),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 4),
                            // Compact action menu
                            PopupMenuButton<String>(
                              icon: Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.more_vert, size: 18, color: Colors.white),
                              ),
                              onSelected: (v) {
                                if (v == 'sync') _syncAttendancesFromDevice();
                                if (v == 'manual') _showManualAttendanceDialog();
                                if (v == 'import') _importFromExcel();
                                if (v == 'export') _exportToExcel();
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(value: 'sync', child: Row(children: [const Icon(Icons.sync, size: 18, color: Colors.blue), const SizedBox(width: 10), Text(_l10n.syncData)])),
                                if (Provider.of<PermissionProvider>(context, listen: false).canCreate('Attendance'))
                                PopupMenuItem(value: 'manual', child: Row(children: [const Icon(Icons.add_circle_outline, size: 18), const SizedBox(width: 10), Text(_l10n.manualAttendance)])),
                                if (Provider.of<PermissionProvider>(context, listen: false).canCreate('Attendance'))
                                PopupMenuItem(value: 'import', child: Row(children: [const Icon(Icons.upload_file, size: 18), const SizedBox(width: 10), Text(_l10n.importExcel)])),
                                if (Provider.of<PermissionProvider>(context, listen: false).canExport('Attendance'))
                                PopupMenuItem(value: 'export', child: Row(children: [const Icon(Icons.file_download_outlined, size: 18), const SizedBox(width: 10), Text(_l10n.exportExcel)])),
                              ],
                            ),
                          ],
                        )
                      else
                        // Search mode: show search field in header
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 36,
                                child: TextField(
                                  autofocus: true,
                                  decoration: InputDecoration(
                                    hintText: 'Tìm ID/Tên...',
                                    hintStyle: const TextStyle(fontSize: 13, color: Colors.white70),
                                    prefixIcon: const Icon(Icons.search, size: 18, color: Colors.white70),
                                    isDense: true,
                                    filled: true,
                                    fillColor: Colors.white.withValues(alpha: 0.2),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white54, width: 1)),
                                  ),
                                  style: const TextStyle(fontSize: 13, color: Colors.white),
                                  onChanged: (v) => setState(() { _searchPin = v; _currentPage = 1; }),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => setState(() { _showMobileSearch = false; _searchPin = ''; _currentPage = 1; }),
                              child: Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.close, size: 18, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                    ],
                  )
                : Row(
                    children: [
                      // Icon + Title
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.access_time_filled, size: 22, color: Colors.white),
                      ),
                      const SizedBox(width: 14),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Chấm công',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          Text(
                            'Quản lý dữ liệu chấm công thời gian thực',
                            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8)),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Realtime indicator
                      _buildRealtimeIndicator(),
                      const SizedBox(width: 12),
                      // Action buttons
                      if (Provider.of<PermissionProvider>(context, listen: false).canCreate('Attendance'))
                      _buildHeaderActionBtn(Icons.add_circle_outline, 'Chấm công thủ công', _showManualAttendanceDialog),
                      if (Provider.of<PermissionProvider>(context, listen: false).canCreate('Attendance'))
                      const SizedBox(width: 8),
                      if (Provider.of<PermissionProvider>(context, listen: false).canCreate('Attendance'))
                      _buildHeaderActionBtn(Icons.upload_file, 'Import Excel', _importFromExcel),
                      if (Provider.of<PermissionProvider>(context, listen: false).canExport('Attendance'))
                      const SizedBox(width: 8),
                      if (Provider.of<PermissionProvider>(context, listen: false).canExport('Attendance'))
                      _buildHeaderActionBtn(Icons.file_download_outlined, 'Xuất Excel', () => _exportToExcel()),
                    ],
                  ),
          ),
          // Content
          Expanded(child: _buildDetailTab()),
        ],
      ),
    );
  }

  Widget _buildRealtimeIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _isRealtimeConnected
            ? Colors.greenAccent.withValues(alpha: 0.2)
            : Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isRealtimeConnected
              ? Colors.greenAccent.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isRealtimeConnected ? Colors.greenAccent : Colors.white54,
              boxShadow: _isRealtimeConnected
                  ? [BoxShadow(color: Colors.greenAccent.withValues(alpha: 0.6), blurRadius: 6)]
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _isRealtimeConnected ? 'LIVE' : 'OFFLINE',
            style: TextStyle(
              color: _isRealtimeConnected ? Colors.greenAccent : Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderActionBtn(IconData icon, String tooltip, VoidCallback onPressed) {
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
    return Padding(
      padding: EdgeInsets.fromLTRB(isMobile ? 10 : 16, isMobile ? 10 : 16, isMobile ? 10 : 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats cards
          if (isMobile) ...[
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
              _buildStatsRow(),
            ],
          ] else ...[
            _buildStatsRow(),
          ],
          const SizedBox(height: 12),
          // Filters: on mobile show only when toggled
          if (!isMobile) ...[
            _buildFilters(),
            const SizedBox(height: 12),
          ] else if (_showMobileFilters) ...[
            _buildMobileFilterPanel(),
            const SizedBox(height: 12),
          ],
          // Content
          Expanded(
            child: _isLoading
                ? const LoadingWidget(message: 'Đang tải dữ liệu...')
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
                          if (!Responsive.isMobile(context))
                            _buildPagination(),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    final total = _filteredAttendances.length;
    final fingerprint = _filteredAttendances.where((a) => a.verifyType == 1).length;
    final face = _filteredAttendances.where((a) => a.verifyType == 15 || a.verifyType == 9).length;
    final manual = _filteredAttendances.where((a) => a.verifyType == 100).length;
    final card = _filteredAttendances.where((a) => a.verifyType == 2).length;

    final stats = [
      ('Tổng bản ghi', '$total', Icons.list_alt, const Color(0xFF1E3A5F)),
      ('Vân tay', '$fingerprint', Icons.fingerprint, const Color(0xFF0F2340)),
      ('Khuôn mặt', '$face', Icons.face, const Color(0xFF1E3A5F)),
      ('Thẻ từ', '$card', Icons.credit_card, const Color(0xFFF59E0B)),
      ('Thủ công', '$manual', Icons.edit_note, const Color(0xFFEF4444)),
    ];

    return Row(
      children: stats.fold<List<Widget>>([], (acc, s) {
        if (acc.isNotEmpty) acc.add(const SizedBox(width: 8));
        acc.add(Expanded(child: _buildStatCard(s.$1, s.$2, s.$3, s.$4)));
        return acc;
      }),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFFA1A1AA)), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
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
          borderRadius: BorderRadius.only(bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
          border: Border(top: BorderSide(color: Color(0xFFE4E4E7))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${startIndex + 1}-$endIndex / $totalItems', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            Row(
              children: [
                _buildPageNavBtn(Icons.chevron_left, _currentPage > 1, () => setState(() => _currentPage--)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(color: Theme.of(context).primaryColor, borderRadius: BorderRadius.circular(8)),
                  child: Text('$_currentPage/$totalPages', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
                _buildPageNavBtn(Icons.chevron_right, _currentPage < totalPages, () => setState(() => _currentPage++)),
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
          Text(
            'Hiển thị ${startIndex + 1}-$endIndex / $totalItems',
            style: TextStyle(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w500),
          ),

          // Page size selector
          Row(
            children: [
              Text('Hiển thị:', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
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
                              child: Text('$size'),
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
              _buildPageNavBtn(Icons.first_page, _currentPage > 1, () => setState(() => _currentPage = 1)),
              _buildPageNavBtn(Icons.chevron_left, _currentPage > 1, () => setState(() => _currentPage--)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_currentPage / $totalPages',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              _buildPageNavBtn(Icons.chevron_right, _currentPage < totalPages, () => setState(() => _currentPage++)),
              _buildPageNavBtn(Icons.last_page, _currentPage < totalPages, () => setState(() => _currentPage = totalPages)),
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
          child: Icon(icon, size: 20, color: enabled ? Theme.of(context).primaryColor : Colors.grey[400]),
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
          // Last month
          final lastMonth = DateTime(now.year, now.month - 1, 1);
          _fromDate = lastMonth;
          final lastDayOfLastMonth = DateTime(now.year, now.month, 0);
          _toDate = DateTime(lastDayOfLastMonth.year, lastDayOfLastMonth.month,
              lastDayOfLastMonth.day, 23, 59, 59);
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
        _toDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
      _loadAttendances();
    }
  }

  List<Attendance> get _filteredAttendances {
    var result = _attendances;

    // Filter by verify type
    if (_selectedVerifyType != null) {
      if (_selectedVerifyType == 15) {
        // Face recognition includes both mode 9 and 15
        result = result.where((a) => a.verifyType == 15 || a.verifyType == 9).toList();
      } else {
        result = result.where((a) => a.verifyType == _selectedVerifyType).toList();
      }
    }

    // Filter by search
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
      case 'time': return 1;
      case 'name': return 6;
      default: return null;
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
        (_selectedDevices.isNotEmpty && _selectedDevices.length != _devices.length) ||
        _selectedDatePreset != 'week';
  }

  Widget _buildMobileFilterPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row header
          Row(
            children: [
              Icon(Icons.filter_alt, size: 16, color: Theme.of(context).primaryColor),
              const SizedBox(width: 6),
              Text('Bộ lọc', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Theme.of(context).primaryColor)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.analytics_outlined, size: 13, color: Theme.of(context).primaryColor),
                    const SizedBox(width: 4),
                    Text(
                      '${_filteredAttendances.length} bản ghi',
                      style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Date preset
          Row(
            children: [
              const Icon(Icons.calendar_today, size: 14, color: Color(0xFF71717A)),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDropdown<String>(
                  value: _selectedDatePreset,
                  icon: null,
                  items: const [
                    DropdownMenuItem(value: 'today', child: Text('Hôm nay')),
                    DropdownMenuItem(value: 'yesterday', child: Text('Hôm qua')),
                    DropdownMenuItem(value: 'week', child: Text('Tuần này')),
                    DropdownMenuItem(value: 'lastWeek', child: Text('Tuần trước')),
                    DropdownMenuItem(value: 'month', child: Text('Tháng này')),
                    DropdownMenuItem(value: 'lastMonth', child: Text('Tháng trước')),
                    DropdownMenuItem(value: 'custom', child: Text('Tùy chọn...')),
                  ],
                  onChanged: (v) { if (v != null) _applyDatePreset(v); },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _buildDateRangeSelector()),
            ],
          ),
          const SizedBox(height: 8),
          // Device + Verify type
          Row(
            children: [
              const Icon(Icons.router, size: 14, color: Color(0xFF71717A)),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDropdown<String>(
                  value: _selectedDevices.length == _devices.length || _selectedDevices.isEmpty ? 'all' : _selectedDevices.first,
                  icon: null,
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('Tất cả TB')),
                    ..._devices.map((d) => DropdownMenuItem(value: d.id, child: Text(d.deviceName, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (v) { setState(() { _selectedDevices = v == 'all' ? _devices.map((d) => d.id).toList() : [v!]; _currentPage = 1; }); _loadAttendances(); },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDropdown<int?>(
                  value: _selectedVerifyType,
                  icon: null,
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Tất cả loại')),
                    DropdownMenuItem(value: 1, child: Text('Vân tay')),
                    DropdownMenuItem(value: 15, child: Text('Khuôn mặt')),
                    DropdownMenuItem(value: 2, child: Text('Thẻ')),
                    DropdownMenuItem(value: 100, child: Text('Thủ công')),
                  ],
                  onChanged: (v) => setState(() { _selectedVerifyType = v; _currentPage = 1; }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final isMobile = Responsive.isMobile(context);
    final countChip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.analytics_outlined, size: 14, color: Theme.of(context).primaryColor),
          const SizedBox(width: 6),
          Text(
            '${_filteredAttendances.length} bản ghi',
            style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Row 1: Search + count
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'Tìm ID/Tên...',
                            hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                            prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
                            isDense: true,
                            filled: true,
                            fillColor: const Color(0xFFFAFAFA),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 1.5)),
                          ),
                          style: const TextStyle(fontSize: 13),
                          onChanged: (v) => setState(() { _searchPin = v; _currentPage = 1; }),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    countChip,
                  ],
                ),
                const SizedBox(height: 8),
                // Row 2: Date preset + date range
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildDropdown<String>(
                        value: _selectedDatePreset,
                        width: 110,
                        icon: Icons.calendar_today,
                        items: const [
                          DropdownMenuItem(value: 'today', child: Text('Hôm nay')),
                          DropdownMenuItem(value: 'yesterday', child: Text('Hôm qua')),
                          DropdownMenuItem(value: 'week', child: Text('Tuần này')),
                          DropdownMenuItem(value: 'lastWeek', child: Text('Tuần trước')),
                          DropdownMenuItem(value: 'month', child: Text('Tháng này')),
                          DropdownMenuItem(value: 'lastMonth', child: Text('Tháng trước')),
                          DropdownMenuItem(value: 'custom', child: Text('Tùy chọn...')),
                        ],
                        onChanged: (v) { if (v != null) _applyDatePreset(v); },
                      ),
                      const SizedBox(width: 8),
                      _buildDateRangeSelector(),
                      const SizedBox(width: 8),
                      _buildDropdown<String>(
                        value: _selectedDevices.length == _devices.length || _selectedDevices.isEmpty ? 'all' : _selectedDevices.first,
                        width: 110,
                        icon: Icons.router,
                        items: [
                          const DropdownMenuItem(value: 'all', child: Text('Tất cả TB')),
                          ..._devices.map((d) => DropdownMenuItem(value: d.id, child: Text(d.deviceName, overflow: TextOverflow.ellipsis))),
                        ],
                        onChanged: (v) { setState(() { _selectedDevices = v == 'all' ? _devices.map((d) => d.id).toList() : [v!]; _currentPage = 1; }); _loadAttendances(); },
                      ),
                      const SizedBox(width: 8),
                      _buildDropdown<int?>(
                        value: _selectedVerifyType,
                        width: 100,
                        icon: Icons.fingerprint,
                        items: const [
                          DropdownMenuItem(value: null, child: Text('Tất cả')),
                          DropdownMenuItem(value: 1, child: Text('Vân tay')),
                          DropdownMenuItem(value: 15, child: Text('Mặt')),
                          DropdownMenuItem(value: 2, child: Text('Thẻ')),
                          DropdownMenuItem(value: 100, child: Text('Thủ công')),
                        ],
                        onChanged: (v) => setState(() { _selectedVerifyType = v; _currentPage = 1; }),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildDropdown<String>(
                  value: _selectedDatePreset,
                  width: 120,
                  icon: Icons.calendar_today,
                  items: const [
                    DropdownMenuItem(value: 'today', child: Text('Hôm nay')),
                    DropdownMenuItem(value: 'yesterday', child: Text('Hôm qua')),
                    DropdownMenuItem(value: 'week', child: Text('Tuần này')),
                    DropdownMenuItem(value: 'lastWeek', child: Text('Tuần trước')),
                    DropdownMenuItem(value: 'month', child: Text('Tháng này')),
                    DropdownMenuItem(value: 'lastMonth', child: Text('Tháng trước')),
                    DropdownMenuItem(value: 'custom', child: Text('Tùy chọn...')),
                  ],
                  onChanged: (v) {
                    if (v != null) _applyDatePreset(v);
                  },
                ),
                _buildDateRangeSelector(),
                _buildDropdown<String>(
                  value: _selectedDevices.length == _devices.length ||
                          _selectedDevices.isEmpty
                      ? 'all'
                      : _selectedDevices.first,
                  width: 120,
                  icon: Icons.router,
                  items: [
                    const DropdownMenuItem(value: 'all', child: Text('Tất cả TB')),
                    ..._devices.map((d) => DropdownMenuItem(
                          value: d.id,
                          child: Text(d.deviceName, overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (v) {
                    setState(() {
                      _selectedDevices =
                          v == 'all' ? _devices.map((d) => d.id).toList() : [v!];
                      _currentPage = 1;
                    });
                    _loadAttendances();
                  },
                ),
                _buildDropdown<int?>(
                  value: _selectedVerifyType,
                  width: 110,
                  icon: Icons.fingerprint,
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Tất cả')),
                    DropdownMenuItem(value: 1, child: Text('Vân tay')),
                    DropdownMenuItem(value: 15, child: Text('Khuôn mặt')),
                    DropdownMenuItem(value: 2, child: Text('Thẻ')),
                    DropdownMenuItem(value: 0, child: Text('Mật khẩu')),
                    DropdownMenuItem(value: 100, child: Text('Thủ công')),
                  ],
                  onChanged: (v) => setState(() {
                    _selectedVerifyType = v;
                    _currentPage = 1;
                  }),
                ),
                SizedBox(
                  width: 200,
                  height: 36,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Tìm ID/Tên...',
                      hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                      prefixIcon:
                          Icon(Icons.search, size: 18, color: Colors.grey[400]),
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFFAFAFA),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 1.5),
                      ),
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (v) => setState(() {
                      _searchPin = v;
                      _currentPage = 1;
                    }),
                  ),
                ),
                countChip,
              ],
            ),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    double? width,
    IconData? icon,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      width: width,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.grey[500]),
          style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).textTheme.bodyMedium?.color),
          dropdownColor: Colors.white,
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item.value,
                    child: Row(
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 15, color: Theme.of(context).primaryColor.withValues(alpha: 0.7)),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                            child: DefaultTextStyle(
                          style: TextStyle(
                              fontSize: 13,
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
                      if (icon != null) ...[
                        Icon(icon,
                            size: 15, color: Theme.of(context).primaryColor),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                          child: DefaultTextStyle(
                        style: TextStyle(
                            fontSize: 13,
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

  Widget _buildDateRangeSelector() {
    return InkWell(
      onTap: () => _applyDatePreset('custom'),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE4E4E7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.date_range,
                size: 15, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            Text(
              '${DateFormat('dd/MM/yyyy').format(_fromDate)} - ${DateFormat('dd/MM/yyyy').format(_toDate)}',
              style: const TextStyle(fontSize: 13),
            ),
            if (_selectedDatePreset == 'custom') ...[
              const SizedBox(width: 4),
              Icon(Icons.edit, size: 12, color: Colors.grey[500]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceTable() {
    final allFiltered = _filteredAttendances;
    final isMobile = Responsive.isMobile(context);
    final startIndex = isMobile ? 0 : (_currentPage - 1) * _itemsPerPage;
    final endIndex = isMobile ? allFiltered.length : (startIndex + _itemsPerPage).clamp(0, allFiltered.length);
    final displayedAttendances = allFiltered.sublist(startIndex, endIndex);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return _buildAttendanceMobileList(displayedAttendances, startIndex);
        }

    final verticalScrollController = ScrollController();

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
                    return Theme.of(context).primaryColor.withValues(alpha: 0.04);
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
                const DataColumn(
                    label: Expanded(child: Text('STT', textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF71717A))))),
                DataColumn(
                    label: const Expanded(child: Text('Ngày', textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF71717A)))),
                    onSort: (_, asc) => _onSort('time', asc)),
                const DataColumn(
                    label: Expanded(child: Text('Giờ', textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF71717A))))),
                const DataColumn(
                    label: Expanded(child: Text('Thứ', textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF71717A))))),
                const DataColumn(
                    label: Expanded(child: Text('UID', textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF71717A))))),
                const DataColumn(
                    label: Expanded(child: Text('Mã nhân viên', textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF71717A))))),
                DataColumn(
                    label: const Expanded(child: Text('Tên nhân viên', textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF71717A)))),
                    onSort: (_, asc) => _onSort('name', asc)),
                const DataColumn(
                    label: Expanded(child: Text('Tên trong máy', textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF71717A))))),
                const DataColumn(
                    label: Expanded(child: Text('Quyền hạn', textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF71717A))))),
                const DataColumn(
                    label: Expanded(child: Text('Thiết bị', textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF71717A))))),
                const DataColumn(
                    label: Expanded(child: Text('Kiểu xác thực', textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF71717A))))),
                const DataColumn(
                    label: Expanded(child: Text('Ghi chú', textAlign: TextAlign.center,
                        style: TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF71717A))))),
              ],
              rows: displayedAttendances.asMap().entries.map((entry) {
                final index = startIndex + entry.key;
                final att = entry.value;
                final dateStr = DateFormat('dd/MM/yyyy').format(att.punchTime);
                final timeStr = DateFormat('HH:mm:ss').format(att.punchTime);
                final dayOfWeek = _getDayOfWeekVN(att.punchTime.weekday);

                return DataRow(
                  onSelectChanged: (_) =>
                      _showAttendanceDetailDialog(att, index),
                  cells: [
                    // STT
                    DataCell(Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            color: Colors.grey,
                            fontSize: 12),
                      ),
                    )),
                    DataCell(Center(
                      child: Text(
                        dateStr,
                        style: const TextStyle(
                            fontWeight: FontWeight.w500, fontSize: 12),
                      ),
                    )),
                    DataCell(Center(
                      child: Text(
                        timeStr,
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
                          dayOfWeek,
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
                        att.enrollNumber ?? '-',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.blue,
                            fontSize: 12),
                      ),
                    )),
                    // Mã nhân viên - Liên kết từ bảng Nhân Sự
                    DataCell(Center(
                      child: Text(
                        att.employeeId ?? '-',
                        style: const TextStyle(
                            fontWeight: FontWeight.w500, fontSize: 12),
                      ),
                    )),
                    // Tên NV - Liên kết từ bảng Nhân Sự
                    DataCell(Center(
                      child: Text(
                        att.employeeName ?? '-',
                        style: const TextStyle(
                            fontWeight: FontWeight.w500, fontSize: 12),
                      ),
                    )),
                    // Tên trong máy - Tên không dấu hiển thị khi chấm công
                    DataCell(Center(
                      child: Text(
                        att.deviceUserName ?? '-',
                        style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontStyle: FontStyle.italic,
                            fontSize: 12),
                      ),
                    )),
                    // Quyền hạn
                    DataCell(Center(child: _buildPrivilegeBadge(att.privilege))),
                    DataCell(Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.router,
                              size: 12, color: Colors.grey),
                          const SizedBox(width: 3),
                          Text(att.deviceName ?? '-',
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    )),
                    DataCell(Center(child: _buildVerifyTypeBadge(att.verifyType))),
                    // Ghi chú - hide correction ID marker
                    DataCell(Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_extractCorrectionRequestId(att.note) != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: Icon(Icons.assignment, size: 14, color: Colors.orange[700]),
                            ),
                          Flexible(
                            child: Text(
                              _getDisplayNote(att.note),
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await _apiService.getAttendanceCorrectionById(correctionId);
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loading

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
            const Expanded(
              child: Text('Yêu cầu chấm công', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        );

        final contentBody = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDetailRow('Mã yêu cầu', correctionId.substring(0, 8), Icons.tag),
            _buildDetailRow('Nhân viên', data['employeeName'] ?? '-', Icons.person),
            _buildDetailRow('Mã NV', data['employeeCode'] ?? '-', Icons.numbers),
            _buildDetailRow('Loại', actionMap[data['action']] ?? '-', Icons.category),
            _buildDetailRow('Trạng thái', statusMap[data['status']] ?? '-', Icons.flag),
            if (data['newDate'] != null)
              _buildDetailRow('Ngày mới', DateFormat('dd/MM/yyyy').format(DateTime.parse(data['newDate'])), Icons.calendar_today),
            if (data['newTime'] != null)
              _buildDetailRow('Giờ mới', data['newTime'].toString().substring(0, 8), Icons.schedule),
            if (data['oldDate'] != null)
              _buildDetailRow('Ngày cũ', DateFormat('dd/MM/yyyy').format(DateTime.parse(data['oldDate'])), Icons.history),
            if (data['oldTime'] != null)
              _buildDetailRow('Giờ cũ', data['oldTime'].toString().substring(0, 8), Icons.history),
            _buildDetailRow('Lý do', data['reason'] ?? '-', Icons.comment),
            if (data['approvedByName'] != null)
              _buildDetailRow('Người duyệt', data['approvedByName'], Icons.verified),
            if (data['approvedDate'] != null)
              _buildDetailRow('Ngày duyệt', DateFormat('dd/MM/yyyy HH:mm').format(DateTime.parse(data['approvedDate'])), Icons.check_circle),
            if (data['approverNote'] != null && data['approverNote'].toString().isNotEmpty)
              _buildDetailRow('Ghi chú duyệt', data['approverNote'], Icons.note),
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
                    title: const Text('Yêu cầu chấm công'),
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
                width: math.min(400, MediaQuery.of(context).size.width - 32).toDouble(),
                child: SingleChildScrollView(child: contentBody),
              ),
              actions: [
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(ctx).pop(),
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Đóng'),
                ),
              ],
            ),
          );
        }
      } else {
        appNotification.showError(
          title: _l10n.error,
          message: 'Không tìm thấy yêu cầu chấm công',
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      appNotification.showError(
        title: _l10n.error,
        message: 'Lỗi: $e',
      );
    }
  }

  /// Mobile card list for attendance records - grouped by date
  Widget _buildAttendanceMobileList(List<Attendance> items, int startIndex) {
    // Group items by date
    final Map<String, List<MapEntry<int, Attendance>>> grouped = {};
    for (var i = 0; i < items.length; i++) {
      final att = items[i];
      final dateKey = DateFormat('yyyy-MM-dd').format(att.punchTime);
      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add(MapEntry(startIndex + i, att));
    }
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a)); // newest first

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      itemCount: sortedKeys.length,
      itemBuilder: (context, groupIdx) {
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
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: dayColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.calendar_today, size: 13, color: dayColor),
                        const SizedBox(width: 5),
                        Text('$dayOfWeek, $dateStr',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: dayColor)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${entries.length}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Row 1: Name + Time
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  att.employeeName ?? att.pin ?? '—',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(timeStr,
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
                              Text(_getVerifyTypeName(att.verifyType),
                                style: const TextStyle(fontSize: 12, color: Color(0xFF71717A))),
                              if (att.deviceName != null && att.deviceName!.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                const Icon(Icons.router, size: 12, color: Color(0xFFA1A1AA)),
                                const SizedBox(width: 3),
                                Expanded(
                                  child: Text(att.deviceName!,
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF71717A)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ] else
                                const Spacer(),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
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
  void _showAttendanceDetailDialog(Attendance att, int index) {
    final dateStr = DateFormat('dd/MM/yyyy').format(att.punchTime);
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
              const Text(
                'Chi tiết chấm công',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                'STT: ${index + 1}',
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
                    Text(dateStr,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(dayOfWeek,
                        style: TextStyle(color: Colors.grey[600], fontSize: 12)),
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
                    Text(timeStr,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(att.punchTypeText,
                        style: TextStyle(
                          color: att.attendanceState == 0 ? Colors.green : Colors.orange,
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
        _buildDetailRow('ID chấm công', att.id, Icons.fingerprint),
        _buildDetailRow('UID (Mã máy)', att.enrollNumber ?? '-', Icons.badge),
        _buildDetailRow('Mã nhân viên', att.employeeId ?? '-', Icons.numbers),
        _buildDetailRow('Tên nhân viên', att.employeeName ?? '-', Icons.person),
        _buildDetailRow('Tên trong máy', att.deviceUserName ?? '-', Icons.text_fields),
        _buildDetailRow('Quyền hạn', att.privilegeText, Icons.admin_panel_settings),
        _buildDetailRow('Thiết bị', att.deviceName ?? att.deviceId ?? '-', Icons.router),
        _buildDetailRow('Loại xác thực', _getVerifyTypeName(att.verifyType), Icons.verified_user),
        if (att.workCode != null && att.workCode!.isNotEmpty)
          _buildDetailRow('Mã công việc', att.workCode!, Icons.work),
        if (att.note != null && _getDisplayNote(att.note).isNotEmpty && _getDisplayNote(att.note) != '-')
          _buildDetailRow('Ghi chú', _getDisplayNote(att.note), Icons.note),
        if (att.createdAt != null)
          _buildDetailRow('Thời gian tạo',
              DateFormat('dd/MM/yyyy HH:mm:ss').format(att.createdAt!), Icons.create),
        if (_extractCorrectionRequestId(att.note) != null) ...[
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
                const Expanded(
                  child: Text(
                    'Từ yêu cầu chấm công đã duyệt',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.orange),
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _showCorrectionRequestDetail(_extractCorrectionRequestId(att.note)!);
                  },
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Xem', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    final actionButtons = [
      TextButton.icon(
        onPressed: () {
          Navigator.of(context).pop();
          _confirmDeleteAttendance(att);
        },
        icon: const Icon(Icons.delete, color: Colors.red, size: 18),
        label: const Text('Xóa', style: TextStyle(color: Colors.red)),
      ),
      TextButton.icon(
        onPressed: () {
          Navigator.of(context).pop();
          _showEditAttendanceDialog(att);
        },
        icon: Icon(Icons.edit, color: Theme.of(context).primaryColor, size: 18),
        label: Text('Sửa', style: TextStyle(color: Theme.of(context).primaryColor)),
      ),
      ElevatedButton.icon(
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.close, size: 18),
        label: const Text('Đóng'),
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
              title: const Text('Chi tiết chấm công'),
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
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                title: const Text('Chi tiết chấm công'),
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actionButtons.map((btn) => Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: btn,
                  )).toList(),
                ),
              ),
            ),
          ),
        ),
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
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning, color: Colors.orange),
            SizedBox(width: 8),
            Text('Xác nhận xóa'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bạn có chắc muốn xóa bản ghi chấm công này?'),
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
                  Text(
                      'Nhân viên: ${att.employeeName ?? att.enrollNumber ?? "N/A"}',
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  Text(
                      'Thời gian: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(att.punchTime)}'),
                  Text('Thiết bị: ${att.deviceName ?? "N/A"}'),
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
            message: 'Đã xóa bản ghi chấm công',
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
    final dateController = TextEditingController(
      text: DateFormat('dd/MM/yyyy').format(att.punchTime),
    );
    final timeController = TextEditingController(
      text: DateFormat('HH:mm:ss').format(att.punchTime),
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.edit, color: Colors.blue),
              SizedBox(width: 8),
              Text('Sửa chấm công'),
            ],
          ),
          content: SizedBox(
            width: math.min(400, MediaQuery.of(context).size.width - 32).toDouble(),
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
                              att.employeeName ?? att.enrollNumber ?? 'N/A',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'UID: ${att.enrollNumber ?? "-"} • Mã NV: ${att.employeeId ?? "-"}',
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
                    labelText: 'Ngày',
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
                    labelText: 'Giờ',
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
                    border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
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
                            Text(
                              'Loại chấm công: ${att.attendanceState == 0 ? "Chấm vào" : "Chấm ra"}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue[700],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Tự động xác định dựa trên thứ tự chấm công trong ngày (lẻ = Vào, chẵn = Ra)',
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
    );
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
            message: 'Đã cập nhật bản ghi chấm công',
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

  String _getVerifyTypeName(int verifyType) {
    switch (verifyType) {
      case 0:
        return 'Mật khẩu';
      case 1:
        return 'Vân tay';
      case 2:
        return 'Thẻ từ';
      case 15:
        return 'Khuôn mặt';
      case 100:
        return 'Thủ công';
      default:
        return 'Khác ($verifyType)';
    }
  }

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
            isAdmin ? 'Quản trị viên' : 'Người dùng',
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
        text,
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
          text,
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

  void _exportToExcel() async {
    final dataToExport = _filteredAttendances;
    if (dataToExport.isEmpty) {
      appNotification.showWarning(
        title: 'Không có dữ liệu',
        message: 'Không có dữ liệu để xuất',
      );
      return;
    }

    try {
      // Tạo workbook mới
      final excel = excel_lib.Excel.createExcel();
      final sheet = excel['ChamCong'];
      excel.delete('Sheet1');

      // Header row
      final headers = [
        'STT',
        'Ngày',
        'Giờ',
        'Thứ',
        'UID',
        'Mã NV',
        'Tên nhân viên',
        'Tên trong máy',
        'Quyền hạn',
        'Thiết bị',
        'Kiểu xác thực'
      ];
      for (var i = 0; i < headers.length; i++) {
        sheet
            .cell(excel_lib.CellIndex.indexByColumnRow(
                columnIndex: i, rowIndex: 0))
            .value = excel_lib.TextCellValue(headers[i]);
      }

      // Data rows
      for (var i = 0; i < dataToExport.length; i++) {
        final att = dataToExport[i];
        final row = i + 1;
        final dayOfWeek = _getDayOfWeekVN(att.punchTime.weekday);
        final verifyTypeName = _getVerifyTypeName(att.verifyType);
        final privilege = att.privilege == 14 ? 'Admin' : 'Nhân viên';

        sheet
            .cell(excel_lib.CellIndex.indexByColumnRow(
                columnIndex: 0, rowIndex: row))
            .value = excel_lib.IntCellValue(i + 1);
        sheet
                .cell(excel_lib.CellIndex.indexByColumnRow(
                    columnIndex: 1, rowIndex: row))
                .value =
            excel_lib.TextCellValue(
                DateFormat('dd/MM/yyyy').format(att.punchTime));
        sheet
                .cell(excel_lib.CellIndex.indexByColumnRow(
                    columnIndex: 2, rowIndex: row))
                .value =
            excel_lib.TextCellValue(
                DateFormat('HH:mm:ss').format(att.punchTime));
        sheet
            .cell(excel_lib.CellIndex.indexByColumnRow(
                columnIndex: 3, rowIndex: row))
            .value = excel_lib.TextCellValue(dayOfWeek);
        sheet
            .cell(excel_lib.CellIndex.indexByColumnRow(
                columnIndex: 4, rowIndex: row))
            .value = excel_lib.TextCellValue(att.enrollNumber ?? '');
        sheet
                .cell(excel_lib.CellIndex.indexByColumnRow(
                    columnIndex: 5, rowIndex: row))
                .value =
            excel_lib.TextCellValue(att.employeeId ?? '');
        sheet
            .cell(excel_lib.CellIndex.indexByColumnRow(
                columnIndex: 6, rowIndex: row))
            .value = excel_lib.TextCellValue(att.employeeName ?? '');
        sheet
            .cell(excel_lib.CellIndex.indexByColumnRow(
                columnIndex: 7, rowIndex: row))
            .value = excel_lib.TextCellValue(att.deviceUserName ?? '');
        sheet
            .cell(excel_lib.CellIndex.indexByColumnRow(
                columnIndex: 8, rowIndex: row))
            .value = excel_lib.TextCellValue(privilege);
        sheet
                .cell(excel_lib.CellIndex.indexByColumnRow(
                    columnIndex: 9, rowIndex: row))
                .value =
            excel_lib.TextCellValue(att.deviceName ?? att.deviceId ?? '');
        sheet
            .cell(excel_lib.CellIndex.indexByColumnRow(
                columnIndex: 10, rowIndex: row))
            .value = excel_lib.TextCellValue(verifyTypeName);
      }

      // Encode và download
      final bytes = excel.encode();
      if (bytes != null) {
        final blob = bytes;
        final fileName =
            'ChamCong_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';

        await file_saver.saveFileBytes(blob, fileName, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');

        appNotification.showSuccess(
          title: 'Xuất file thành công',
          message: 'Đã xuất file $fileName (${dataToExport.length} bản ghi)',
        );
      }
    } catch (e) {
      debugPrint('Error exporting Excel: $e');
      appNotification.showError(
        title: 'Lỗi xuất Excel',
        message: '$e',
      );
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
                            Text(
                              'Chấm công ${widget.isCheckIn ? "VÀO" : "RA"}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: widget.isCheckIn
                                    ? Colors.green.shade700
                                    : Colors.orange.shade700,
                              ),
                            ),
                            Text(
                              widget.timeStr,
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
                          widget.userName,
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
                        widget.deviceName,
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
                          widget.verifyType,
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
