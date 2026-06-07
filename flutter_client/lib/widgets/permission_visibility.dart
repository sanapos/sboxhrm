import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';

/// Loại quyền thao tác trên module.
enum ModuleAction { view, create, edit, delete, export, approve }

/// Chỉ hiển thị [child] khi user có quyền tương ứng — ẩn hoàn toàn khỏi UI.
class PermissionVisibility extends StatelessWidget {
  const PermissionVisibility({
    super.key,
    required this.module,
    required this.action,
    required this.child,
    this.replacement,
  });

  final String module;
  final ModuleAction action;
  final Widget child;
  final Widget? replacement;

  static bool allows(PermissionProvider perm, String module, ModuleAction action) {
    switch (action) {
      case ModuleAction.view:
        return perm.canView(module);
      case ModuleAction.create:
        return perm.canCreate(module);
      case ModuleAction.edit:
        return perm.canEdit(module);
      case ModuleAction.delete:
        return perm.canDelete(module);
      case ModuleAction.export:
        return perm.canExport(module);
      case ModuleAction.approve:
        return perm.canApprove(module);
    }
  }

  @override
  Widget build(BuildContext context) {
    final perm = context.watch<PermissionProvider>();
    if (allows(perm, module, action)) return child;
    return replacement ?? const SizedBox.shrink();
  }
}

extension PermissionBuildContext on BuildContext {
  PermissionProvider get perm => read<PermissionProvider>();

  bool moduleCan(String module, ModuleAction action) =>
      PermissionVisibility.allows(perm, module, action);
}
