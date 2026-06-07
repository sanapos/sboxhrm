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
import '../utils/notification_navigation.dart';
import '../utils/pending_notification_launch.dart';
import 'api_config.dart';

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
      await _localPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.high,
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

  /// Call before logout to remove token binding for current user on the server.
  Future<void> unregisterForLogout() async {
    if (!_initialized) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (token != null && accessToken != null) {
        final url = Uri.parse(
          '${getApiBaseUrl()}/api/notifications/device-token?token=${Uri.encodeQueryComponent(token)}',
        );
        await http.delete(url, headers: {
          'Authorization': 'Bearer $accessToken',
        }).timeout(const Duration(seconds: 5)).catchError((e) {
          debugPrint('FCM unregister request failed: $e');
          return http.Response('', 0);
        });
      }
      await prefs.remove(_tokenStorageKey);
    } catch (e) {
      debugPrint('FcmService.unregisterForLogout failed: $e');
    }
  }

  Future<void> _registerToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token');
    if (accessToken == null || accessToken.isEmpty) {
      debugPrint('FCM register skipped: not logged in');
      return;
    }
    final platform = Platform.isIOS ? 'ios' : 'android';
    final body = jsonEncode({
      'token': token,
      'platform': platform,
    });
    final url = Uri.parse('${getApiBaseUrl()}/api/notifications/device-token');
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
      final title = msg.notification?.title ?? data['title'];
      if (kDebugMode) {
        debugPrint(
            'FCM tap → entity=$entityType row=$notificationRowId highlight=$highlightId');
      }

      PendingNotificationLaunch.store(
        relatedEntityType: entityType,
        notificationRowId: notificationRowId,
        highlightEntityId: highlightId,
        title: title,
        categoryCode: data['categoryCode'],
        actionUrl: data['actionUrl'],
      );
      if (!PendingNotificationLaunch.tryConsume()) {
        PendingNotificationLaunch.scheduleConsume();
      }
      ScreenRefreshNotifier.refreshNotificationCount();
    } catch (e) {
      debugPrint('FcmService._queueNotificationLaunch failed: $e');
    }
  }

}
