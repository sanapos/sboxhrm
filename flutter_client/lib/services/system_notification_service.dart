import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../screens/main_layout.dart' show NavigationNotifier, ScreenRefreshNotifier;
import '../services/api_service.dart';

/// Service để hiển thị thông báo trên thanh notification của Android
class SystemNotificationService {
  static final SystemNotificationService _instance =
      SystemNotificationService._internal();
  factory SystemNotificationService() => _instance;
  SystemNotificationService._internal();

  final ApiService _apiService = ApiService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _notificationId = 0;

  /// Khởi tạo plugin - gọi 1 lần khi app start
  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Request notification permission on Android 13+
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    _initialized = true;
    debugPrint('🔔 SystemNotificationService initialized');
  }

  /// Xử lý khi người dùng bấm vào thông báo hệ thống
  void _onNotificationTap(NotificationResponse response) async {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) {
      NavigationNotifier.goToNotifications();
      return;
    }

    debugPrint('🔔 System notification tapped, payload: $payload');

    // payload = "relatedEntityType|notificationId"
    String entityType;
    String? notificationId;
    final parts = payload.split('|');
    entityType = parts[0];
    if (parts.length > 1 && parts[1].isNotEmpty) {
      notificationId = parts[1];
    }

    // Đánh dấu đã đọc trước khi navigate
    if (notificationId != null) {
      try {
        // Đảm bảo token đã được load (trường hợp app khởi động từ notification)
        await _apiService.getStoredToken();
        final result = await _apiService.markNotificationAsRead(notificationId);
        debugPrint('🔔 Mark as read result: $result');
      } catch (e) {
        debugPrint('🔔 Error marking notification as read: $e');
      }
    }
    // Luôn refresh count sau khi tap
    ScreenRefreshNotifier.refreshNotificationCount();

    // payload = relatedEntityType
    switch (entityType) {
      case 'Device':
      case 'DeviceStatus':
        NavigationNotifier.goToDeviceSettings();
        break;
      case 'Attendance':
        NavigationNotifier.goToAttendance();
        break;
      case 'Leave':
        NavigationNotifier.goToLeaves();
        break;
      case 'WorkSchedule':
      case 'ScheduleRegistration':
        NavigationNotifier.goToWorkSchedule();
        break;
      case 'Employee':
        NavigationNotifier.goToEmployees();
        break;
      case 'Payroll':
      case 'Payslip':
        NavigationNotifier.goToPayroll();
        break;
      case 'WorkTask':
        NavigationNotifier.goToTaskManagement();
        break;
      case 'AdvanceRequest':
        NavigationNotifier.goToAdvanceRequests();
        break;
      case 'Communication':
        NavigationNotifier.goToCommunication();
        break;
      case 'BonusPenalty':
        NavigationNotifier.goToBonusPenalty();
        break;
      case 'CashTransaction':
        NavigationNotifier.goToCashTransaction();
        break;
      case 'PenaltyTicket':
        NavigationNotifier.goTo(NavigationNotifier.penaltyTickets);
        break;
      default:
        NavigationNotifier.goToNotifications();
        break;
    }
  }

  /// Hiển thị thông báo trên thanh notification Android
  Future<void> show({
    required String title,
    required String body,
    String? channelId,
    String? channelName,
    String? payload,
  }) async {
    if (!_initialized) await initialize();

    final androidDetails = AndroidNotificationDetails(
      channelId ?? 'sbox_hrm_default',
      channelName ?? 'Thông báo chung',
      channelDescription: 'Thông báo từ SBOX HRM',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(
        body,
        contentTitle: title,
        summaryText: 'SBOX HRM',
      ),
      autoCancel: true, // Chỉ dismiss khi user tap vào
    );

    final details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      _notificationId++,
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// Tạo payload chung: "entityType|notificationId"
  String _makePayload(String entityType, [String? notificationId]) {
    return notificationId != null ? '$entityType|$notificationId' : entityType;
  }

  /// Thông báo thiết bị kết nối/ngắt kết nối
  Future<void> showDeviceStatus({
    required String deviceName,
    required bool isOnline,
    String? notificationId,
  }) async {
    await show(
      title: isOnline ? 'Thiết bị kết nối' : 'Thiết bị ngắt kết nối',
      body: isOnline
          ? "Máy chấm công '$deviceName' đã kết nối"
          : "Máy chấm công '$deviceName' đã ngắt kết nối",
      channelId: 'sbox_hrm_device',
      channelName: 'Thiết bị',
      payload: _makePayload('Device', notificationId),
    );
  }

  /// Thông báo chấm công
  Future<void> showAttendance({
    required String employeeName,
    required String time,
    required String deviceName,
    String? notificationId,
  }) async {
    await show(
      title: 'Chấm công: $employeeName',
      body: '$time · $deviceName',
      channelId: 'sbox_hrm_attendance',
      channelName: 'Chấm công',
      payload: _makePayload('Attendance', notificationId),
    );
  }

  /// Thông báo chung
  Future<void> showGeneral({
    required String title,
    required String message,
    String? relatedEntityType,
    String? notificationId,
  }) async {
    await show(
      title: title,
      body: message,
      channelId: 'sbox_hrm_general',
      channelName: 'Thông báo chung',
      payload: _makePayload(relatedEntityType ?? 'Notification', notificationId),
    );
  }
}
