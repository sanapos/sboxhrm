import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import '../screens/main_layout.dart' show ScreenRefreshNotifier;
import '../utils/notification_display_utils.dart';
import '../utils/notification_navigation.dart';
import '../utils/pending_notification_launch.dart';
import 'api_service.dart';

/// Background message handler. Must be a top-level function.
/// On iOS, this handler is only called for DATA-ONLY messages (no `notification` field).
/// Notification messages (with title+body) are shown by the OS automatically — no
/// action needed here. On Android both types invoke this handler.
@pragma('vm:entry-point')
Future<void> _firebaseBgHandler(RemoteMessage message) async {
  // Guard: Firebase may already be initialized in this isolate.
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  if (kDebugMode) debugPrint('FCM bg: ${message.messageId} ${message.notification?.title}');
}

class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  static const String _channelId = 'attendance_default';
  static const String _channelName = 'Thông báo chung';
  static const String _channelDesc = 'Chấm công và thông báo từ hệ thống';
  static const String _tokenStorageKey = 'fcm_token_registered';

  final FlutterLocalNotificationsPlugin _localPlugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Call ONCE at app startup (before runApp). Safe to await; failures are swallowed
  /// so the app still launches when Firebase is misconfigured.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      // Guard against duplicate init: on iOS, FirebaseApp.configure() is called
      // natively in AppDelegate.swift before Dart runs, so Firebase.apps is already
      // populated. On Android (or if not yet initialized), initialize now.
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      }
      FirebaseMessaging.onBackgroundMessage(_firebaseBgHandler);

      // Local notification channel for foreground messages on Android.
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _localPlugin.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
      );
      final androidImpl = _localPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
      ));
      // Server chọn kênh theo mức độ: khẩn (cần duyệt / cảnh báo) và yên lặng (giờ nghỉ — không chuông).
      await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
        'attendance_urgent',
        'Thông báo khẩn',
        description: 'Cần duyệt, cảnh báo — luôn đổ chuông',
        importance: Importance.max,
      ));
      await androidImpl?.createNotificationChannel(const AndroidNotificationChannel(
        'attendance_quiet',
        'Thông báo yên lặng',
        description: 'Nhận trong giờ yên lặng — không chuông, không rung',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ));

      // Foreground iOS presentation: tắt vì SignalR đã hiển thị in-app khi
      // app đang mở; nếu để alert=true sẽ trùng 2 thông báo trên iOS.
      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: false, badge: true, sound: false,
      );

      // Listeners
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);
      // Cold start: queue navigation until MainLayout + auth are ready.
      FirebaseMessaging.instance.getInitialMessage().then((msg) {
        if (msg != null) _queueNotificationLaunch(msg);
      });
      FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        if (kDebugMode) debugPrint('FCM token refreshed');
        _registerToken(t).catchError((e) =>
            debugPrint('FCM token refresh registration failed: $e'));
      });

      _initialized = true;
    } catch (e, st) {
      debugPrint('FcmService.initialize failed: $e\n$st');
    }
  }

  /// Call after successful login. Requests permission, gets token, posts to backend.
  /// Safe to call multiple times (backend upserts). Tolerant to Firebase being uninitialized.
  Future<void> registerForCurrentUser() async {
    if (!_initialized) await initialize();
    if (!_initialized) return;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      // iOS: APNs token must exist before getToken() on cold start.
      // registerForRemoteNotifications() is called natively in AppDelegate, but
      // the OS may still take a few seconds to deliver the token.
      if (Platform.isIOS) {
        String? apnsToken;
        for (int i = 0; i < 30; i++) {
          apnsToken = await FirebaseMessaging.instance.getAPNSToken();
          if (apnsToken != null && apnsToken.isNotEmpty) break;
          await Future.delayed(const Duration(seconds: 1));
        }
        if (apnsToken == null || apnsToken.isEmpty) {
          // Check if iOS reported a native APNs registration error
          String? nativeError;
          try {
            const ch = MethodChannel('flutter/shared_preferences');
            final map = await ch.invokeMethod<Map>('getAll');
            nativeError = map?['flutter.apns_registration_error'] as String?;
          } catch (_) {}
          if (nativeError != null) {
            debugPrint('FCM: APNs registration error: $nativeError');
            return;
          }
          // Try getToken() directly — Firebase may have captured APNs internally
          try {
            final fallbackToken = await FirebaseMessaging.instance
                .getToken()
                .timeout(const Duration(seconds: 10));
            if (fallbackToken != null && fallbackToken.isNotEmpty) {
              await _registerToken(fallbackToken);
            }
          } catch (_) {}
          return;
        }
      }

      try {
        final token = await FirebaseMessaging.instance
            .getToken()
            .timeout(const Duration(seconds: 15));
        if (token != null && token.isNotEmpty) await _registerToken(token);
      } catch (e) {
        debugPrint('FCM getToken threw: $e');
      }
    } catch (e) {
      debugPrint('FcmService.registerForCurrentUser failed: $e');
    }
  }

  /// Gọi khi đăng xuất (kể cả phiên hết hạn) và trước khi đăng nhập tài khoản khác:
  /// gỡ token trên server (không cần access token) rồi hủy token ở Firebase,
  /// để thông báo của người cũ không còn đổ về máy này.
  Future<void> unregisterForLogout() async {
    if (!_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    try {
      final current = await FirebaseMessaging.instance.getToken().timeout(const Duration(seconds: 5));
      final tokens = {
        if (current != null && current.isNotEmpty) current,
        if ((prefs.getString(_tokenStorageKey) ?? '').isNotEmpty) prefs.getString(_tokenStorageKey)!,
      };
      final accessToken = prefs.getString('access_token');
      for (final token in tokens) {
        final url = Uri.parse(
          '${ApiService.baseUrl}/api/notifications/device-token?token=${Uri.encodeQueryComponent(token)}',
        );
        await http.delete(url, headers: {
          if (accessToken != null && accessToken.isNotEmpty) 'Authorization': 'Bearer $accessToken',
        }).timeout(const Duration(seconds: 5)).catchError((e) {
          debugPrint('FCM unregister request failed: $e');
          return http.Response('', 0);
        });
      }
    } catch (e) {
      debugPrint('FcmService.unregisterForLogout failed: $e');
    }
    try {
      // Hủy hẳn token: nếu server còn sót bản ghi, lần gửi sau Firebase báo Unregistered và tự tắt.
      // Lần đăng nhập sau máy nhận token mới.
      await FirebaseMessaging.instance.deleteToken().timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('FCM deleteToken failed: $e');
    }
    await prefs.remove(_tokenStorageKey);
  }

  Future<void> _registerToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token');
    if (accessToken == null || accessToken.isEmpty) {
      debugPrint('FCM register skipped: not logged in');
      return;
    }
    final platform = Platform.isIOS ? 'ios' : 'android';
    final deviceKey = prefs.getString('sbox_access_device_key');
    final body = jsonEncode({
      'token': token,
      'platform': platform,
      if (deviceKey != null && deviceKey.isNotEmpty) 'deviceKey': deviceKey,
    });
    final url = Uri.parse('${ApiService.baseUrl}/api/notifications/device-token');
    final res = await http.post(url, headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
    }, body: body).timeout(const Duration(seconds: 8));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      await prefs.setString(_tokenStorageKey, token);
      if (kDebugMode) debugPrint('FCM token registered ✓');
    } else {
      debugPrint('FCM register failed: ${res.statusCode} ${res.body}');
    }
  }

  void _onForegroundMessage(RemoteMessage msg) {
    // Khi app đang foreground, SignalR (`AttendanceHub` / `_handleNewNotification`
    // trong main_layout.dart) đã đảm nhận hiển thị notification qua
    // SystemNotificationService. Nếu hiện thêm local notif từ FCM ở đây sẽ
    // gây trùng 2 thông báo. Khi app vào background/terminated, FCM SDK tự
    // hiển thị system notification từ payload `notification` nên cũng không
    // cần xử lý ở đây. Chỉ log debug.
    if (kDebugMode) {
      debugPrint('FCM fg (suppressed, handled by SignalR): ${msg.notification?.title}');
    }
  }

  /// User tapped FCM system notification while app was in background or
  /// terminated. Route to the right screen + refresh notification badge so
  /// the target screen does not show stale/empty data.
  void _onMessageOpenedApp(RemoteMessage msg) {
    _queueNotificationLaunch(msg);
  }

  void _queueNotificationLaunch(RemoteMessage msg) {
    try {
      final raw = msg.data;
      final data = raw.map((k, v) => MapEntry(k, v.toString()));
      final entityType = resolveEntityTypeForNotification(
        relatedEntityType: data['relatedEntityType'],
        categoryCode: data['categoryCode'],
        actionUrl: data['actionUrl'],
        title: msg.notification?.title ?? data['title'],
      );
      final notificationRowId = data['notificationId'];
      final highlightId =
          data['relatedEntityId']?.isNotEmpty == true
              ? data['relatedEntityId']
              : notificationRowId;
      final display = resolveNotificationDisplay({
        ...data,
        if (msg.notification?.title != null) 'title': msg.notification!.title,
        if (msg.notification?.body != null) 'message': msg.notification!.body,
      });
      final title = display.title;
      final actionUrl = data['actionUrl'] ?? '';
      final adminPortalMode = actionUrl.startsWith('/admin') ||
          _isAdminPortalEntity(entityType);
      if (kDebugMode) {
        debugPrint(
            'FCM tap → entity=$entityType row=$notificationRowId highlight=$highlightId admin=$adminPortalMode');
      }

      PendingNotificationLaunch.store(
        relatedEntityType: entityType,
        notificationRowId: notificationRowId,
        highlightEntityId: highlightId,
        title: title,
        categoryCode: data['categoryCode'],
        actionUrl: data['actionUrl'],
      );
      if (!PendingNotificationLaunch.tryConsume(adminPortalMode: adminPortalMode)) {
        PendingNotificationLaunch.scheduleConsume(adminPortalMode: adminPortalMode);
      }
      ScreenRefreshNotifier.refreshNotificationCount();
    } catch (e) {
      debugPrint('FcmService._queueNotificationLaunch failed: $e');
    }
  }

  static bool _isAdminPortalEntity(String? entityType) {
    switch (entityType?.trim().toLowerCase()) {
      case 'store':
      case 'renewal':
      case 'licensekey':
      case 'license':
      case 'agent':
        return true;
      default:
        return false;
    }
  }

}
