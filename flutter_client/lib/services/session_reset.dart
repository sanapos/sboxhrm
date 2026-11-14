import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/permission_provider.dart';
import '../services/mobile_bottom_nav_prefs.dart';
import '../services/mobile_quick_actions_prefs.dart';
import 'shared_http_client.dart';
import '../utils/navigation_notifier.dart';
import '../utils/pos_commercial_profile_local.dart';
import '../utils/pos_print_config_session.dart';
import '../utils/pos_print_template_loader.dart';
import '../utils/pos_sell_store_settings.dart';
import 'api_service.dart';
import '../widgets/ai_assistant_sheet.dart';

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
    clearSharedHttpCache();
    NavigationNotifier.resetForNewSession();
    // Bộ đệm theo cửa hàng trong RAM + quyền «quản lý duyệt» còn hạn của người vừa đăng xuất.
    PosSellStoreSettings.invalidateServerCache();
    PosPrintConfigSession.instance.invalidate();
    ApiService.setPosApprovalToken(null);
    // Cuộc trò chuyện với trợ lý (có số liệu của tài khoản cũ) không mang sang tài khoản / cửa hàng mới.
    AiAssistantSheet.resetSession();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('main_layout_last_nav_index');
    } catch (e) {
      debugPrint('SessionReset: clear prefs failed: $e');
    }
  }

  static const _deviceStoreKey = 'sbox_device_store_id_v1';

  /// Máy vừa vào một cửa hàng KHÁC lần trước (đổi tài khoản, đăng nhập thay) → bỏ các bản lưu trên máy không
  /// gắn mã cửa hàng: thiết lập bán hàng, hồ sơ thương mại, mẫu in. Cùng cửa hàng (đổi ca) thì giữ nguyên để
  /// mất mạng vẫn in đúng mẫu. Tài khoản không gắn cửa hàng (quản trị hệ thống / đại lý) không đổi gì.
  static Future<void> ensureDeviceStore(String? storeId) async {
    final sid = (storeId ?? '').trim();
    if (sid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final prev = prefs.getString(_deviceStoreKey);
      if (prev == sid) return;
      if (prev != null && prev.isNotEmpty) {
        await PosSellStoreSettings.clearDeviceCopy();
        await clearLocalCommercialProfile();
        await clearPosPrintTemplateDiskCache();
        PosPrintConfigSession.instance.invalidate();
      }
      await prefs.setString(_deviceStoreKey, sid);
    } catch (e) {
      debugPrint('SessionReset: ensureDeviceStore failed: $e');
    }
  }
}
