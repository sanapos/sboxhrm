import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/permission_provider.dart';
import '../screens/notifications_screen.dart';
import '../screens/pos/pos_quote_detail_screen.dart';
import '../screens/pos_reports_screen.dart';
import '../widgets/pos/pos_hub_scope.dart';
import 'permission_navigation.dart';

/// Màn mở trực tiếp khi bấm thông báo (không phải mục menu) — dùng chung [MainLayout] và app bán hàng riêng / Staff.

bool _allowed(BuildContext context, String moduleCode) {
  final perm = Provider.of<PermissionProvider>(context, listen: false);
  if (PermissionNavigation.canNavigate(perm, moduleCode)) return true;
  PermissionNavigation.showDenied(context, moduleCode);
  return false;
}

/// Thông báo nhắc hẹn chăm sóc → chi tiết báo giá + sheet chăm sóc khách.
Future<void> openPosQuoteCareFromNotification(BuildContext context, String quoteId) async {
  if (!_allowed(context, 'PosQuotes')) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => PosQuoteDetailScreen(quoteId: quoteId, openCare: true),
  ));
}

/// «Cảnh báo hạn sử dụng» → báo cáo Hàng sắp hết hạn (cùng màn mở từ Báo cáo POS).
Future<void> openPosExpiryReportFromNotification(BuildContext context) async {
  if (!_allowed(context, 'PosReportExpiry')) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => const PosHubScope(
      embeddedInHub: false,
      pushedSubPage: true,
      child: PosReportsScreen(initialTab: 2, lockTab: true),
    ),
  ));
}

/// App bán hàng riêng / Staff: chỉ báo giá và HSD có màn riêng, còn lại mở danh sách thông báo
/// (đang ở danh sách rồi thì thôi — tránh mở chồng khi bấm một dòng trong danh sách).
bool openNotificationInShell(BuildContext context, String? entityKey, String? relatedEntityId) {
  final hasId = relatedEntityId != null && relatedEntityId.isNotEmpty;
  if (entityKey == 'posquote' && hasId) {
    openPosQuoteCareFromNotification(context, relatedEntityId);
    return true;
  }
  if (entityKey == 'posreportexpiry') {
    openPosExpiryReportFromNotification(context);
    return true;
  }
  if (NotificationsScreen.openCount > 0) return false;
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()));
  return true;
}
