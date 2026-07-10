import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../services/api_service.dart';
import '../screens/main_layout.dart' show ScreenRefreshNotifier;
import 'navigation_notifier.dart';
import 'notification_navigation.dart';
import 'admin_navigation.dart';

/// Hàng đợi điều hướng từ FCM khi cold start — chỉ áp dụng sau khi [MainLayout] sẵn sàng.
class PendingNotificationLaunch {
  PendingNotificationLaunch._();

  static String? _entityType;
  static String? _notificationRowId;
  static String? _highlightEntityId;
  static String? _title;
  static String? _categoryCode;
  static String? _actionUrl;

  static void store({
    String? relatedEntityType,
    String? notificationRowId,
    String? highlightEntityId,
    String? title,
    String? categoryCode,
    String? actionUrl,
  }) {
    _entityType = relatedEntityType;
    _notificationRowId = notificationRowId;
    _highlightEntityId = highlightEntityId ?? notificationRowId;
    _title = title;
    _categoryCode = categoryCode;
    _actionUrl = actionUrl;
    if (kDebugMode) {
      debugPrint(
          '[BOOT] Pending notification nav: type=$_entityType row=$_notificationRowId highlight=$_highlightEntityId');
    }
  }

  static void clear() {
    _entityType = null;
    _notificationRowId = null;
    _highlightEntityId = null;
    _title = null;
    _categoryCode = null;
    _actionUrl = null;
  }

  static bool get hasPending =>
      (_entityType != null && _entityType!.isNotEmpty) ||
      (_title != null && _title!.isNotEmpty);

  /// Trả về true nếu đã điều hướng.
  static bool tryConsume({bool adminPortalMode = false, bool agentMode = false}) {
    if (!hasPending) return false;
    if (!adminPortalMode && !NavigationNotifier.mainLayoutReady.value) {
      return false;
    }
    if (adminPortalMode && !AdminNavigationNotifier.systemAdminReady.value) {
      return false;
    }
    final type = _entityType;
    final rowId = _notificationRowId;
    final highlightId = _highlightEntityId;
    final title = _title;
    final category = _categoryCode;
    final actionUrl = _actionUrl;
    clear();
    // ignore: discarded_futures
    _consumeAsync(type, rowId, highlightId, title, category, actionUrl,
        adminPortalMode: adminPortalMode, agentMode: agentMode);
    return true;
  }

  static Future<void> _consumeAsync(
    String? type,
    String? rowId,
    String? highlightId,
    String? title,
    String? categoryCode,
    String? actionUrl, {
    bool adminPortalMode = false,
    bool agentMode = false,
  }) async {
    if (rowId != null && rowId.isNotEmpty) {
      try {
        final api = ApiService();
        await api.getStoredToken();
        await api.markNotificationAsRead(rowId);
        ScreenRefreshNotifier.refreshNotificationCount();
      } catch (e) {
        if (kDebugMode) debugPrint('[BOOT] mark read failed: $e');
      }
    }
    navigateFromNotification(
      relatedEntityType: type,
      relatedEntityId: highlightId,
      title: title,
      categoryCode: categoryCode,
      actionUrl: actionUrl,
      adminPortalMode: adminPortalMode,
      agentMode: agentMode,
    );
  }

  /// Thử lại cho đến khi MainLayout hoặc SystemAdminScreen mount.
  static void scheduleConsume({
    int maxAttempts = 80,
    bool adminPortalMode = false,
    bool agentMode = false,
  }) {
    void attempt(int n) {
      if (tryConsume(adminPortalMode: adminPortalMode, agentMode: agentMode)) {
        return;
      }
      if (n >= maxAttempts) {
        if (kDebugMode && hasPending) {
          debugPrint(
              '[BOOT] Pending notification nav waiting for MainLayout (attempts=$n)');
        }
        return;
      }
      Future.delayed(const Duration(milliseconds: 250), () => attempt(n + 1));
    }

    SchedulerBinding.instance.addPostFrameCallback((_) => attempt(0));
  }
}
