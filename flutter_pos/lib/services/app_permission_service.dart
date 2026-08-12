import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

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
      ];
      final statuses = await need.request();
      debugPrint('AppPermissionService: $statuses');
    } catch (e) {
      debugPrint('AppPermissionService: $e');
    }
  }
}
