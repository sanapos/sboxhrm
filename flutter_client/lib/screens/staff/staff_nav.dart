import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/permission_navigation.dart';
import '../../utils/store_role_helper.dart';
import '../../widgets/page_top_actions.dart';

/// Quyền mở một module trong app SBOX Nhân Viên: có trong gói dịch vụ của cửa hàng
/// và vai trò được Xem hoặc Gửi đơn (bộ quyền nhân viên phần lớn là «Gửi đơn»).
bool staffCanOpen(BuildContext context, String moduleCode, {bool listen = true}) {
  final auth = listen ? context.watch<AuthProvider>() : context.read<AuthProvider>();
  final perm = listen
      ? context.watch<PermissionProvider>()
      : context.read<PermissionProvider>();
  final user = auth.user;
  final inPackage = PermissionNavigation.isAllowedByPackageOrRole(
    moduleCode,
    allowedModules: user?.allowedModules,
    perm: perm,
    bypassPackageFilter: StoreRoleHelper.bypassesPackageFilter(user?.role),
  );
  return inPackage && (perm.canView(moduleCode) || perm.canCreate(moduleCode));
}

/// Mở màn HRM có sẵn thành trang riêng. Màn cũ đẩy nút (Tạo đơn…) lên thanh trên
/// của khung chính qua [PageTopActions] — trang mở riêng phải tự vẽ, không thì mất nút.
Future<void> openStaffPage(
  BuildContext context, {
  required String title,
  required Widget child,
  bool ownScaffold = false,
}) {
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ownScaffold
        ? child
        : Scaffold(
            backgroundColor: SboxColors.page,
            appBar: AppBar(
              title: Text(tr(title)),
              backgroundColor: SboxColors.appBarBg(SboxColors.white),
              surfaceTintColor: SboxColors.white,
              actions: [
                ListenableBuilder(
                  listenable: PageTopActions.instance,
                  builder: (_, __) =>
                      PageTopActionsBar(actions: PageTopActions.instance.actions),
                ),
                const SizedBox(width: 8),
              ],
            ),
            floatingActionButton: const PageTopActionsFab(),
            body: child,
          ),
  ));
}

/// Một mục chức năng trong app nhân viên (ô thao tác nhanh / dòng menu).
class StaffEntry {
  const StaffEntry({
    required this.moduleCode,
    required this.title,
    required this.icon,
    required this.color,
    required this.builder,
    this.subtitle,
    this.ownScaffold = false,
  });

  final String moduleCode;
  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final WidgetBuilder builder;

  /// Màn tự vẽ Scaffold + thanh tiêu đề — đẩy thẳng, không bọc thêm.
  final bool ownScaffold;

  Future<void> open(BuildContext context) => openStaffPage(
        context,
        title: title,
        child: builder(context),
        ownScaffold: ownScaffold,
      );
}

/// Nhóm dòng menu dạng thẻ trắng, mỗi dòng một chức năng (ẩn mục không có quyền).
class StaffMenuSection extends StatelessWidget {
  const StaffMenuSection({super.key, required this.title, required this.entries});

  final String title;
  final List<StaffEntry> entries;

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final e in entries)
        if (staffCanOpen(context, e.moduleCode)) e,
    ];
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              tr(title),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: SboxColors.textSecondary,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: SboxColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SboxColors.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 56, color: SboxColors.divider),
                  _StaffMenuTile(entry: visible[i]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StaffMenuTile extends StatelessWidget {
  const _StaffMenuTile({required this.entry});

  final StaffEntry entry;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: entry.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(entry.icon, color: entry.color, size: 20),
      ),
      title: Text(
        tr(entry.title),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      subtitle: entry.subtitle == null
          ? null
          : Text(
              tr(entry.subtitle!),
              style: const TextStyle(fontSize: 12, color: SboxColors.textMuted),
            ),
      trailing: const Icon(Icons.chevron_right, color: SboxColors.slate400),
      onTap: () => entry.open(context),
    );
  }
}
