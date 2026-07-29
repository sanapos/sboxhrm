import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../utils/permission_navigation.dart';
import '../utils/store_role_helper.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Chặn hiển thị màn hình khi user không có quyền xem module.
class ModuleRouteGuard extends StatelessWidget {
  const ModuleRouteGuard({
    super.key,
    required this.moduleCode,
    required this.child,
  });

  final String? moduleCode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (moduleCode == null || moduleCode!.isEmpty) return child;
    final perm = context.watch<PermissionProvider>();
    final authUser = context.watch<AuthProvider>().user;
    final bypassPackage =
        StoreRoleHelper.bypassesPackageFilter(authUser?.role);
    if (!PermissionNavigation.isAllowedByPackageOrRole(
      moduleCode,
      allowedModules: authUser?.allowedModules,
      perm: perm,
      bypassPackageFilter: bypassPackage,
    )) {
      return _AccessDeniedBody(moduleCode: moduleCode!);
    }
    if (PermissionNavigation.canNavigate(perm, moduleCode)) return child;
    return _AccessDeniedBody(moduleCode: moduleCode!);
  }
}

class _AccessDeniedBody extends StatelessWidget {
  const _AccessDeniedBody({required this.moduleCode});

  final String moduleCode;

  @override
  Widget build(BuildContext context) {
    final name = PermissionNavigation.label(moduleCode);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(tr('Bạn không có quyền truy cập'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              tr('Module: $name'),
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
