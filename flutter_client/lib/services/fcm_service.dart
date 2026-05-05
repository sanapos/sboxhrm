import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import '../screens/main_layout.dart' show NavigationNotifier, ScreenRefreshNotifier;
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
      // Cold start: app launched from a notification tap. Defer routing
      // until after first frame so MainLayout đã attach navigateTo listener.
      FirebaseMessaging.instance.getInitialMessage().then((msg) {
        if (msg != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // Delay thêm để đảm bảo auth state đã load và MainLayout mounted.
            Future.delayed(const Duration(milliseconds: 800), () {
              _onMessageOpenedApp(msg);
            });
          });
        }
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
    debugPrint('FCM registerForCurrentUser: start, initialized=$_initialized');
    if (!_initialized) await initialize();
    if (!_initialized) {
      debugPrint('FCM registerForCurrentUser: not initialized, abort');
      if (Platform.isIOS) _postDebugLog('registerForCurrentUser: initialize() failed to init Firebase');
      return;
    }
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true,
      );
      debugPrint('FCM permission status: ${settings.authorizationStatus}');
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('FCM permission denied');
        return;
      }
      // iOS: APNs token must exist before getToken on cold start.
      // On first launch / fresh install it can take up to 30s — retry up to 30 times.
      if (Platform.isIOS) {
        String? apnsToken;
        for (int i = 0; i < 30; i++) {
          apnsToken = await FirebaseMessaging.instance.getAPNSToken();
          debugPrint('FCM APNs attempt ${i + 1}/30: ${apnsToken != null ? "GOT TOKEN" : "null"}');
          if (apnsToken != null && apnsToken.isNotEmpty) break;
          if (kDebugMode) debugPrint('FCM: APNs token null, attempt ${i + 1}/30...');
          await Future.delayed(const Duration(seconds: 1));
        }
        if (apnsToken == null || apnsToken.isEmpty) {
          debugPrint('FCM: APNs token still null after 30s — checking native error, then trying getToken() fallback');

          // Check if iOS reported a registration error via AppDelegate → UserDefaults
          String? nativeError;
          try {
            const ch = MethodChannel('flutter/shared_preferences');
            final map = await ch.invokeMethod<Map>('getAll');
            nativeError = map?['flutter.apns_registration_error'] as String?;
          } catch (_) {}

          // Post debug info to server (error or generic null message)
          final debugMsg = nativeError != null
              ? 'APNs registration failed: $nativeError. Permission=${settings.authorizationStatus}'
              : 'APNs token null after 30s retries. Permission=${settings.authorizationStatus}. Trying getToken() fallback.';
          _postDebugLog(debugMsg);

          if (nativeError != null) {
            // APNs registration itself failed — provisioning or entitlement issue
            debugPrint('FCM: APNs native error: $nativeError');
            return;
          }

          // AppDelegate may have set apnsToken in Firebase even though getAPNSToken() returned
          // null (timing issue). Try getToken() directly — Firebase SDK handles APNs internally.
          try {
            final fallbackToken = await FirebaseMessaging.instance
                .getToken()
                .timeout(const Duration(seconds: 10));
            if (fallbackToken != null && fallbackToken.isNotEmpty) {
              debugPrint('FCM: getToken() fallback succeeded');
              _postDebugLog('getToken() fallback succeeded after APNs null. Token=${fallbackToken.substring(0, 20)}...');
              await _registerToken(fallbackToken);
              return;
            }
          } catch (e) {
            debugPrint('FCM: getToken() fallback failed: $e');
            _postDebugLog('getToken() fallback failed: $e');
          }
          return;
        }
        if (kDebugMode) debugPrint('FCM APNs token ready ✓');
        _postDebugLog('APNs token received OK (len=${apnsToken!.length}). Calling getToken()...');
      }
      try {
        final token = await FirebaseMessaging.instance
            .getToken()
            .timeout(const Duration(seconds: 15));
        debugPrint('FCM getToken result: ${token != null ? "OK (${token.substring(0, 20)}...)" : "NULL"}');
        if (token == null || token.isEmpty) {
          debugPrint('FCM getToken returned null');
          _postDebugLog('getToken() returned null after APNs token was set');
          return;
        }
        await _registerToken(token);
      } catch (e) {
        debugPrint('FCM getToken threw: $e');
        _postDebugLog('getToken() threw after APNs was set: $e');
      }
    } catch (e) {
      debugPrint('FcmService.registerForCurrentUser failed: $e');
      if (Platform.isIOS) _postDebugLog('registerForCurrentUser top-level catch: $e');
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

  /// Posts a debug log message to the server so remote diagnosis is possible.
  Future<void> _postDebugLog(String message) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null) return;
      final url = Uri.parse('${getApiBaseUrl()}/api/notifications/device-token/debug');
      await http.post(url, headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      }, body: jsonEncode({'message': message, 'platform': Platform.isIOS ? 'ios' : 'android'}))
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
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
    try {
      final data = msg.data;
      final entityType = (data['type'] ??
              data['relatedEntityType'] ??
              _entityFromActionUrl(data['actionUrl']?.toString()) ??
              '')
          .toString()
          .toLowerCase();
      final notificationId = data['notificationId']?.toString();
      if (kDebugMode) {
        debugPrint('FCM tap → entityType=$entityType notifId=$notificationId data=$data');
      }
      _routeToEntity(entityType);
      // Always bump notification count so badge refreshes.
      ScreenRefreshNotifier.refreshNotificationCount();
    } catch (e) {
      debugPrint('FcmService._onMessageOpenedApp failed: $e');
    }
  }

  String? _entityFromActionUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    // e.g. "/attendance" → "attendance"
    final segs = url.split('/').where((s) => s.isNotEmpty).toList();
    return segs.isNotEmpty ? segs.first : null;
  }

  void _routeToEntity(String entityType) {
    // Mirror of SystemNotificationService._onNotificationTap mapping.
    // If you change this list, also update system_notification_service.dart.
    switch (entityType) {
      case 'device':
      case 'devicestatus':
      case 'admsdevice':
        NavigationNotifier.goToDeviceSettings();
        break;
      case 'attendance':
      case 'newattendance':
      case 'overtime':
      case 'attendancecorrection':
      case 'correction':
        NavigationNotifier.goToAttendance();
        break;
      case 'leave':
      case 'leaverequest':
        NavigationNotifier.goToLeaves();
        break;
      case 'workschedule':
      case 'scheduleregistration':
      case 'shift':
      case 'shiftswap':
      case 'schedule':
        NavigationNotifier.goToWorkSchedule();
        break;
      case 'payroll':
      case 'payslip':
        NavigationNotifier.goToPayroll();
        break;
      case 'advance':
      case 'advancerequest':
        NavigationNotifier.goToAdvanceRequests();
        break;
      default:
        NavigationNotifier.goToNotifications();
        break;
    }
  }
}
