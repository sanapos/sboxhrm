import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../utils/dashboard_ui_capabilities.dart';
import '../../widgets/sbox/sbox_ui.dart';
import '../dashboard_screen.dart';
import 'business_overview_screen.dart';

/// Trang «Tổng quan» của SBOX HRM: nhân viên thấy màn cá nhân cũ, quản lý thấy tổng quan theo gói.
/// Để riêng tệp này vì nó nạp [DashboardScreen] (kéo theo 11 màn HRM) — bản SBOX Bán Hàng không được chạm tới.
/// Trang «Tổng quan»: nhân viên → màn cá nhân cũ; quản lý → tổng quan mới theo gói.
class OverviewRouterScreen extends StatelessWidget {
  const OverviewRouterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final perm = context.watch<PermissionProvider>();
    final auth = context.watch<AuthProvider>();
    if (!perm.isLoaded) return const SboxLoading();
    final caps = DashboardUiCapabilities.from(perm, role: auth.userRole, allowedModules: auth.user?.allowedModules);
    if (caps.useEmployeeLayout) return const DashboardScreen();
    final mode = BusinessOverviewScreen.resolveMode(perm, auth);
    if (mode == null) return const DashboardScreen();
    return BusinessOverviewScreen(mode: mode);
  }
}
