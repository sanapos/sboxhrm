import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kiểm tra camera (Samsung hay báo sai), giới hạn hộp thông báo. Mọi quyền hỏi đúng lúc dùng chức năng, không hỏi gộp lúc mở app.
class AppPermissionService {
  AppPermissionService._();

  static bool _cameraPermissionAllowed(PermissionStatus status) =>
      status.isGranted || status.isLimited;

  /// Kiểm tra/xin quyền camera — fallback thử mở danh sách camera khi
  /// permission_handler desync trên Samsung/One UI.
  static Future<PermissionStatus> ensureCameraPermission({
    bool requestIfNeeded = true,
  }) async {
    if (kIsWeb) return PermissionStatus.granted;

    var status = await Permission.camera.status;
    if (_cameraPermissionAllowed(status)) return status;

    if (requestIfNeeded &&
        !status.isPermanentlyDenied &&
        !status.isRestricted) {
      status = await Permission.camera.request();
      if (_cameraPermissionAllowed(status)) return status;
    }

    if (await _probeCameraAccess()) {
      return PermissionStatus.granted;
    }

    return status;
  }

  static Future<bool> _probeCameraAccess() async {
    if (kIsWeb) return false;
    try {
      final cameras = await availableCameras();
      return cameras.isNotEmpty;
    } catch (e) {
      debugPrint('📸 Camera probe: $e');
      return false;
    }
  }

  static Future<bool> hasCameraAccess() async {
    final status = await ensureCameraPermission(requestIfNeeded: false);
    return _cameraPermissionAllowed(status) || await _probeCameraAccess();
  }

  static const _prefNotificationAsked = 'sbox_notification_permission_asked_v1';
  static bool _notificationAskClaimed = false;

  /// Android: hộp thoại thông báo chỉ hiện một lần cho mỗi lần cài. FCM (cả lần thử lại sau 35 giây) và
  /// thông báo cục bộ đều tự xin, nên từ chối xong lại bị hỏi tiếp. Muốn bật lại: màn Thông báo / Cài đặt máy.
  static Future<bool> claimNotificationPrompt() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    if (_notificationAskClaimed) return false;
    _notificationAskClaimed = true;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_prefNotificationAsked) ?? false) return false;
    await prefs.setBool(_prefNotificationAsked, true);
    return true;
  }
}
