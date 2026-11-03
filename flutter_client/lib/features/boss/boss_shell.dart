import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../config/sbox_app_variant.dart';
import '../../l10n/app_tr.dart';
import '../../providers/auth_provider.dart';
import '../../services/branch_session.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/store_role_helper.dart';
import '../../widgets/branch_switcher.dart';
import '../../widgets/sbox/sbox_basics.dart';
import 'boss_dashboard_screen.dart';
import 'boss_end_of_day_screen.dart';

/// Shell app SBOX BOSS (flavor `boss`): chỉ chủ / quản lý — tab Tổng quan · Cuối ngày · Thêm.
/// Tài khoản khác thấy [BossRoleBlockedScreen].
class BossShell extends StatefulWidget {
  const BossShell({super.key});

  @override
  State<BossShell> createState() => _BossShellState();
}

class _BossShellState extends State<BossShell> {
  int _tab = 0;

  static const _titles = ['Tổng quan hôm nay', 'Cuối ngày', 'Thêm'];

  @override
  void initState() {
    super.initState();
    if (!BranchSession.instance.loaded) BranchSession.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    final role = context.select<AuthProvider, String>((a) => a.userRole);
    if (!StoreRoleHelper.isBossRole(role)) return const BossRoleBlockedScreen();
    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: AppBar(
        backgroundColor: SboxColors.brand700,
        foregroundColor: SboxColors.white,
        title: Text(tr(_titles[_tab])),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: SboxSpace.sm),
            child: Center(child: BranchSwitcher(compact: true, onDark: true)),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: const [
          BossDashboardScreen(),
          BossEndOfDayScreen(),
          _BossMoreScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: const Icon(Icons.dashboard_rounded),
            label: tr('Tổng quan'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long_rounded),
            label: tr('Cuối ngày'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.more_horiz_rounded),
            selectedIcon: const Icon(Icons.more_horiz_rounded),
            label: tr('Thêm'),
          ),
        ],
      ),
    );
  }
}

Future<void> _confirmLogout(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(tr('Đăng xuất')),
      content: Text(tr('Đăng xuất khỏi ${SboxAppVariant.productLine} trên máy này?')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Đăng xuất'))),
      ],
    ),
  );
  if (ok == true && context.mounted) await context.read<AuthProvider>().logout();
}

class _BossMoreScreen extends StatefulWidget {
  const _BossMoreScreen();

  @override
  State<_BossMoreScreen> createState() => _BossMoreScreenState();
}

class _BossMoreScreenState extends State<_BossMoreScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = 'v${info.version} (${info.buildNumber})');
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final user = context.select<AuthProvider, ({String name, String email, String role})>((a) => (
          name: a.user?.fullName ?? '',
          email: a.user?.email ?? '',
          role: a.userRole,
        ));
    return ListView(
      padding: const EdgeInsets.all(SboxSpace.lg),
      children: [
        SboxCard(
          child: Row(children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: SboxColors.brand100,
              child: Text(
                user.name.trim().isEmpty ? '?' : user.name.trim()[0].toUpperCase(),
                style: SboxType.titleStyle(SboxColors.brand800),
              ),
            ),
            const SizedBox(width: SboxSpace.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(user.name, style: SboxType.titleSmStyle(), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(user.email, style: SboxType.smallStyle(SboxColors.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
            SboxStatusChip(label: _roleLabel(user.role), tone: SboxTone.brand),
          ]),
        ),
        const SizedBox(height: SboxSpace.md),
        SboxCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            ListenableBuilder(
              listenable: BranchSession.instance,
              builder: (context, _) {
                final s = BranchSession.instance;
                if (!s.showSwitcher) return const SizedBox.shrink();
                return ListTile(
                  leading: const Icon(Icons.storefront_rounded, color: SboxColors.brand600),
                  title: Text(tr('Chi nhánh đang xem')),
                  subtitle: Text(tr(s.currentLabel)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => BranchViewStrip.pick(context),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: SboxColors.danger),
              title: Text(tr('Đăng xuất'), style: const TextStyle(color: SboxColors.dangerText)),
              onTap: () => _confirmLogout(context),
            ),
          ]),
        ),
        const SizedBox(height: SboxSpace.lg),
        Center(
          child: Text('${SboxAppVariant.productLine} $_version'.trim(), style: SboxType.captionStyle()),
        ),
      ],
    );
  }
}

String _roleLabel(String role) => switch (role.trim().toLowerCase()) {
      'admin' || 'storeowner' => 'Chủ cửa hàng',
      'director' => 'Giám đốc',
      'manager' => 'Quản lý',
      _ => role,
    };

/// Tài khoản nhân viên / thu ngân đăng nhập nhầm vào SBOX BOSS.
class BossRoleBlockedScreen extends StatelessWidget {
  const BossRoleBlockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SboxEmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'SBOX BOSS dành cho chủ cửa hàng',
          message: 'Tài khoản này không phải chủ / quản lý cửa hàng. '
              'Nhân viên dùng app SBOX POS hoặc SBOX HRM.',
          action: SboxButton(label: 'Đăng xuất', onPressed: () => context.read<AuthProvider>().logout()),
        ),
      ),
    );
  }
}
