import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/permission_navigation.dart';
import '../../utils/store_role_helper.dart';
import '../../widgets/hrm_page_chrome.dart';
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
              backgroundColor: SboxColors.chrome,
              surfaceTintColor: Colors.transparent,
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
            // Trang này đã có thanh tiêu đề: báo cho màn con để không vẽ thêm thanh «← tiêu đề» thứ hai.
            body: HrmShellChrome(visible: true, child: child),
          ),
  ));
}

/// Một mục chức năng trong app nhân viên (ô thao tác nhanh / dòng menu).
class StaffEntry {
  const StaffEntry({
    required this.moduleCode,
    required this.title,
    required this.icon,
    required this.builder,
    this.subtitle,
    this.ownScaffold = false,
  });

  final String moduleCode;
  final String title;
  final String? subtitle;
  final IconData icon;
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

/// Ô icon nền gradient màu logo (giống ô chức năng Trang chủ SBOX POS).
class StaffIconBox extends StatelessWidget {
  const StaffIconBox({super.key, required this.icon, this.size = 44, this.iconSize = 24});

  final IconData icon;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [SboxColors.brand400, SboxColors.brand600],
        ),
        borderRadius: BorderRadius.circular(size * 0.27),
      ),
      child: Icon(icon, size: iconSize, color: SboxColors.white),
    );
  }
}

/// Vòng tròn chữ cái đầu của người dùng.
class StaffAvatar extends StatelessWidget {
  const StaffAvatar({super.key, required this.name, this.radius = 24});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final t = name.trim();
    return CircleAvatar(
      radius: radius,
      backgroundColor: SboxColors.brand50,
      child: Text(
        t.isEmpty ? '?' : t.characters.first.toUpperCase(),
        style: TextStyle(
          fontSize: radius * 0.8,
          fontWeight: SboxType.bold,
          color: SboxColors.brand700,
        ),
      ),
    );
  }
}

/// Thẻ trắng viền mảnh: khối nền chung của các tab.
class StaffCard extends StatelessWidget {
  const StaffCard({super.key, required this.child, this.padding = const EdgeInsets.all(SboxSpace.lg)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: SboxColors.surface,
        borderRadius: SboxRadius.lgAll,
        border: Border.all(color: SboxColors.border),
      ),
      child: child,
    );
  }
}

/// Thẻ «Truy cập nhanh»: tiêu đề + lưới ô icon 4 cột (ẩn mục không có quyền).
class StaffQuickGrid extends StatelessWidget {
  const StaffQuickGrid({super.key, required this.title, required this.icon, required this.entries});

  final String title;
  final IconData icon;
  final List<StaffEntry> entries;

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final e in entries)
        if (staffCanOpen(context, e.moduleCode)) e,
    ];
    if (visible.isEmpty) return const SizedBox.shrink();
    return StaffCard(
      padding: const EdgeInsets.fromLTRB(SboxSpace.md, SboxSpace.md, SboxSpace.md, SboxSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              StaffIconBox(icon: icon, size: 28, iconSize: 16),
              const SizedBox(width: SboxSpace.sm),
              Expanded(child: Text(tr(title), style: SboxType.titleSmStyle())),
            ],
          ),
          const SizedBox(height: SboxSpace.sm),
          LayoutBuilder(builder: (context, c) {
            final tileWidth = c.maxWidth / (c.maxWidth >= 480 ? 6 : 4);
            return Wrap(
              children: [
                for (final e in visible)
                  SizedBox(
                    width: tileWidth,
                    child: InkWell(
                      onTap: () => e.open(context),
                      borderRadius: SboxRadius.mdAll,
                      child: SizedBox(
                        height: 96,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: SboxSpace.xxs, vertical: SboxSpace.sm),
                          child: Column(
                            children: [
                              StaffIconBox(icon: e.icon),
                              const SizedBox(height: 6),
                              Text(
                                tr(e.title),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: SboxType.captionStyle(SboxColors.text).copyWith(height: 1.25),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

/// Nhóm dòng menu kiểu Thiết lập SBOX: tiêu đề in hoa, thẻ trắng, ô icon nền nhạt (ẩn mục không có quyền).
class StaffMenuSection extends StatelessWidget {
  const StaffMenuSection({
    super.key,
    required this.title,
    required this.entries,
    this.icon,
  });

  final String title;
  final List<StaffEntry> entries;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final e in entries)
        if (staffCanOpen(context, e.moduleCode)) e,
    ];
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: SboxSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(SboxSpace.xs, 0, SboxSpace.xs, SboxSpace.sm),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: SboxColors.brand600),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    tr(title).toUpperCase(),
                    style: const TextStyle(
                      fontSize: SboxType.small,
                      fontWeight: SboxType.bold,
                      letterSpacing: 0.3,
                      color: SboxColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: SboxColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: SboxRadius.lgAll,
              side: const BorderSide(color: SboxColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < visible.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 68, color: SboxColors.divider),
                  StaffMenuTile(
                    icon: visible[i].icon,
                    title: visible[i].title,
                    subtitle: visible[i].subtitle,
                    onTap: () => visible[i].open(context),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Một dòng menu: ô icon nền nhạt, tiêu đề, mũi tên.
class StaffMenuTile extends StatelessWidget {
  const StaffMenuTile({super.key, required this.icon, required this.title, this.subtitle, this.onTap});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: SboxSpace.md, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: SboxColors.brand50,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, color: SboxColors.brand600, size: 22),
      ),
      title: Text(tr(title), style: SboxType.bodyStrong()),
      subtitle: subtitle == null ? null : Text(tr(subtitle!), style: SboxType.captionStyle()),
      trailing: const Icon(Icons.chevron_right_rounded, color: SboxColors.slate400),
      onTap: onTap,
    );
  }
}
