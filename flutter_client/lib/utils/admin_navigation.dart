import 'package:flutter/foundation.dart';

/// Điều hướng tab trên màn /admin (SuperAdmin & Agent).
class AdminNavigationNotifier {
  AdminNavigationNotifier._();

  static final ValueNotifier<bool> systemAdminReady = ValueNotifier(false);

  /// Tab index trên [SystemAdminScreen] (0=Tổng quan, 1=Cửa hàng, …).
  static final ValueNotifier<int?> systemAdminTab = ValueNotifier<int?>(null);

  static final ValueNotifier<String?> highlightEntityId = ValueNotifier(null);

  /// Agent portal: 0 dash, 1 stores, 2 users, 3 devices, 4 licenses
  static const int agentLicenseTab = 4;

  /// SuperAdmin: licenses tab index
  static const int superAdminLicenseTab = 5;

  static int licenseTabIndex({required bool agentMode}) =>
      agentMode ? agentLicenseTab : superAdminLicenseTab;

  static int? tabIndexFromActionUrl(String? actionUrl, {required bool agentMode}) {
    if (actionUrl == null || actionUrl.isEmpty) return null;
    final segs = actionUrl.split('/').where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) return null;
    if (segs.first.toLowerCase() != 'admin') return null;
    if (segs.length < 2) return 0;
    switch (segs[1].toLowerCase()) {
      case 'stores':
        return 1;
      case 'users':
        return 2;
      case 'devices':
        return 3;
      case 'agents':
        return agentMode ? null : 4;
      case 'licenses':
        return licenseTabIndex(agentMode: agentMode);
      default:
        return 0;
    }
  }

  static int? tabIndexFromEntity(String? entity, {required bool agentMode}) {
    final key = entity?.trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
    switch (key) {
      case 'store':
        return 1;
      case 'device':
        return 3;
      case 'licensekey':
      case 'license':
        return licenseTabIndex(agentMode: agentMode);
      case 'agent':
        return agentMode ? null : 4;
      case 'user':
      case 'applicationuser':
        return 2;
      case 'renewal':
        return 1;
      default:
        return null;
    }
  }

  static void navigate({
    required bool agentMode,
    String? actionUrl,
    String? relatedEntityType,
    String? categoryCode,
    String? relatedEntityId,
  }) {
    var tab = tabIndexFromActionUrl(actionUrl, agentMode: agentMode);
    tab ??= tabIndexFromEntity(relatedEntityType, agentMode: agentMode);
    tab ??= tabIndexFromEntity(categoryCode, agentMode: agentMode);
    if (tab == null) return;
    if (relatedEntityId != null && relatedEntityId.isNotEmpty) {
      highlightEntityId.value = relatedEntityId;
    }
    systemAdminTab.value = tab;
    if (kDebugMode) {
      debugPrint('📍 Admin nav → tab $tab (agentMode=$agentMode url=$actionUrl)');
    }
  }
}
