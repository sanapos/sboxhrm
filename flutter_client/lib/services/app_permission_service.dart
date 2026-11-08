import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Kiểm tra / xin quyền camera (Samsung hay báo sai).
///
/// Không xin quyền lúc mở app: mỗi quyền chỉ hỏi khi người dùng dùng đúng chức năng cần nó
/// (camera khi quét mã / chụp, vị trí khi chấm công / chọn bản đồ, micro khi bấm nút micro).
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
}
