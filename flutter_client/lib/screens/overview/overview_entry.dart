import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'business_overview_screen.dart';

/// Trang «Tổng quan» của SBOX HRM — `lib/main.dart` gắn [OverviewRouterScreen] vào đây.
///
/// Bản SBOX Bán Hàng không gắn, nên `dashboard_screen.dart` (11.800 dòng, kéo theo 11 màn chấm công / lương)
/// không nằm trong gói. Apple từ chối bản POS theo điều 2.5.19 vì quét thấy nhóm mã đó.
Widget Function()? hrmOverviewScreen;

/// Mục «Tổng quan» trong khung màn chính.
class OverviewEntry extends StatelessWidget {
  const OverviewEntry({super.key});

  @override
  Widget build(BuildContext context) {
    final hrm = hrmOverviewScreen?.call();
    if (hrm != null) return hrm;
    final perm = context.watch<PermissionProvider>();
    final auth = context.watch<AuthProvider>();
    if (!perm.isLoaded) return const SboxLoading();
    // Bản bán hàng: luôn là tổng quan bán hàng, không có màn cá nhân của nhân viên HRM.
    final mode = BusinessOverviewScreen.resolveMode(perm, auth) ?? OverviewMode.pos;
    return BusinessOverviewScreen(mode: mode);
  }
}
