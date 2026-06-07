import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../utils/permission_navigation.dart';

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
            Text(
              'Bạn không có quyền truy cập',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Module: $name',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
