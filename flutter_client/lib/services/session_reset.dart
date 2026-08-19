import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/permission_provider.dart';
import '../services/mobile_bottom_nav_prefs.dart';
import '../services/mobile_quick_actions_prefs.dart';
import '../utils/navigation_notifier.dart';

/// Xóa cache in-memory khi đổi tài khoản / cửa hàng (logout → login).
class SessionReset {
  SessionReset._();

  static PermissionProvider? _permissionProvider;

  static void bindPermissionProvider(PermissionProvider provider) {
    _permissionProvider = provider;
  }

  /// Gọi trước login mới và khi logout — không xóa mã cửa hàng / email đã lưu.
  static Future<void> clearForAccountSwitch() async {
    _permissionProvider?.clear();
    MobileBottomNavPrefs.clearCache();
    MobileQuickActionsPrefs.clearCache();
    NavigationNotifier.resetForNewSession();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('main_layout_last_nav_index');
    } catch (e) {
      debugPrint('SessionReset: clear prefs failed: $e');
    }
  }
}
