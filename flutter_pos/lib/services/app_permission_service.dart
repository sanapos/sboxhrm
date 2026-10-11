import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../utils/pos_lite_mode.dart';

/// Xin quyền cần thiết trên máy POS (camera quét mã, lưu trữ…).
class AppPermissionService {
  static Future<bool> ensure(String p) async => true;

  static Future<void> promptEssentialPermissionsIfNeeded(
    BuildContext context,
  ) async {
    try {
      final need = <Permission>[
        Permission.camera,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        // Sunmi T1 (Android 6): màn hình phụ ghi ảnh trình chiếu / hoá đơn vào /sdcard/sbox_cd
        // để dịch vụ màn phụ đọc — thiếu quyền là EACCES, màn phụ chỉ hiện chữ.
        if (PosLiteMode.enabled) Permission.storage,
      ];
      final statuses = await need.request();
      debugPrint('AppPermissionService: $statuses');
    } catch (e) {
      debugPrint('AppPermissionService: $e');
    }
  }
}
