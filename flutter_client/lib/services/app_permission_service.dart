import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Xin quyền thiết yếu lần đầu mở app + kiểm tra camera (Samsung hay báo sai).
class AppPermissionService {
  AppPermissionService._();

  static const _prefPrompted = 'sbox_essential_permissions_prompted_v1';

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

  static Future<bool> wasEssentialPermissionsPrompted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefPrompted) ?? false;
  }

  static Future<void> _markEssentialPermissionsPrompted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefPrompted, true);
  }

  /// Hiển thị dialog và xin quyền lần đầu (mobile). Gọi từ Login / MainLayout.
  static Future<void> promptEssentialPermissionsIfNeeded(
    BuildContext context,
  ) async {
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;
    if (await wasEssentialPermissionsPrompted()) return;
    if (!context.mounted) return;

    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Cấp quyền cho SBOX HRM')),
        content: Text(
          tr('Ứng dụng cần các quyền sau để hoạt động đúng:\n\n'
          '• Camera — đăng ký khuôn mặt, chấm công\n'
          '• Vị trí — xác nhận địa điểm chấm công\n'
          '• Thông báo — nhận duyệt đăng ký, chấm công\n\n'
          'Nhấn «Cấp quyền» để hệ thống hiện hộp thoại quyền.'),
          style: TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Để sau')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Cấp quyền')),
          ),
        ],
      ),
    );

    await _markEssentialPermissionsPrompted();

    if (proceed != true) return;

    await _requestEssentialPermissions();
  }

  static Future<void> _requestEssentialPermissions() async {
    if (Platform.isAndroid) {
      await Permission.notification.request();
    }
    await Permission.camera.request();
    await Permission.locationWhenInUse.request();
    if (Platform.isAndroid) {
      await Permission.nearbyWifiDevices.request();
    }
    // Làm mới trạng thái camera sau chuỗi xin quyền.
    await ensureCameraPermission(requestIfNeeded: false);
  }
}
