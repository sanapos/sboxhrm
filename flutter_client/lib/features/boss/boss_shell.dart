import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../config/sbox_app_variant.dart';
import '../../l10n/app_tr.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../screens/main_layout.dart' show ScreenRefreshNotifier;
import '../../screens/notifications_screen.dart';
import '../../screens/staff/staff_nav.dart';
import '../../services/api_service.dart';
import '../../services/branch_session.dart';
import '../../services/signalr_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/navigation_notifier.dart';
import '../../utils/notification_display_utils.dart';
import '../../utils/notification_navigation.dart';
import '../../utils/notification_open_screens.dart';
import '../../utils/pending_notification_launch.dart';
import '../../utils/store_role_helper.dart';
import '../../widgets/branch_switcher.dart';
import '../../widgets/companion_account_links.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/sbox/sbox_basics.dart';
import 'boss_dashboard_screen.dart';
import 'boss_inbox_screen.dart';
import 'boss_manage_screen.dart';
import 'boss_reports_screen.dart';
import 'boss_vouchers_screen.dart';

/// Shell app SBOX BOSS (flavor `boss`): chỉ chủ / quản lý — tab Tổng quan · Cần duyệt · Báo cáo · Quản lý · Thêm,
/// chuông thông báo, nút ＋ tạo phiếu nhanh.
/// Tài khoản khác thấy [BossRoleBlockedScreen].
class BossShell extends StatefulWidget {
  const BossShell({super.key});

  @override
  State<BossShell> createState() => _BossShellState();
}

class _BossShellState extends State<BossShell> with WidgetsBindingObserver {
  int _tab = 0;
  int _unread = 0;

  final _signalR = SignalRService();
  StreamSubscription? _notificationSub;
  bool _connectingSignalR = false;

  static const _titles = ['Tổng quan hôm nay', 'Cần duyệt', 'Báo cáo', 'Quản lý', 'Thêm'];

  @override
  void initState() {
    super.initState();
    if (!BranchSession.instance.loaded) BranchSession.instance.load();
    WidgetsBinding.instance.addObserver(this);
    notificationShellHandler = _openFromNotification;
    PendingNotificationLaunch.scheduleConsume();
    ScreenRefreshNotifier.notifications.addListener(_refreshUnread);
    NavigationNotifier.navigateToModule.addListener(_onModuleRequested);
    NavigationNotifier.navigateTo.addListener(_onIndexRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadPermissions());
      unawaited(_refreshUnread());
      unawaited(_connectSignalR());
    });
  }

  @override
  void dispose() {
    if (notificationShellHandler == _openFromNotification) notificationShellHandler = null;
    ScreenRefreshNotifier.notifications.removeListener(_refreshUnread);
    NavigationNotifier.navigateToModule.removeListener(_onModuleRequested);
    NavigationNotifier.navigateTo.removeListener(_onIndexRequested);
    WidgetsBinding.instance.removeObserver(this);
    _notificationSub?.cancel();
    unawaited(_signalR.disconnect());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    unawaited(_refreshUnread());
    unawaited(_connectSignalR());
    if (context.read<PermissionProvider>().loadFailed) unawaited(_loadPermissions());
  }

  /// Kết nối realtime bằng token: màn Chấm công, Thông báo dùng chung kết nối này (không tự có token).
  Future<void> _connectSignalR() async {
    if (_connectingSignalR || !mounted) return;
    _connectingSignalR = true;
    try {
      await _notificationSub?.cancel();
      if (!mounted) return;
      // Nghe trước khi kết nối: lần đầu mất mạng thì kết nối tự nối lại sau vẫn có người nhận tin.
      _notificationSub = _signalR.onNewNotification.listen(_handleNewNotification);
      final auth = context.read<AuthProvider>();
      final token = await auth.getValidToken();
      if (!mounted) return;
      if (!_signalR.isConnected) {
        await _signalR.connect(null, token, () => auth.getValidToken());
      }
      final storeId = auth.user?.storeId;
      if (storeId != null && storeId.isNotEmpty) {
        await _signalR.joinStoreGroup(storeId);
      }
      final userId = auth.user?.id;
      if (userId != null && userId.isNotEmpty) {
        await _signalR.joinUserGroup(userId);
      }
    } catch (e) {
      debugPrint('⚠️ BossShell SignalR: $e');
    } finally {
      _connectingSignalR = false;
    }
  }

  void _openTapped(Map<String, dynamic> data, String title) {
    final rowId = (data['notificationId'] ?? data['id'])?.toString();
    if (rowId != null && rowId.isNotEmpty) {
      unawaited(ApiService().markNotificationAsRead(rowId).then((_) {
        ScreenRefreshNotifier.refreshNotificationCount();
      }));
    }
    navigateFromNotification(
      relatedEntityType: data['relatedEntityType']?.toString(),
      relatedEntityId: data['relatedEntityId']?.toString(),
      title: title,
      categoryCode: data['categoryCode']?.toString(),
      actionUrl: (data['actionUrl'] ?? data['relatedUrl'])?.toString(),
    );
  }

  void _handleNewNotification(Map<String, dynamic> data) {
    try {
      final display = resolveNotificationDisplay(data);
      final typeValue = data['type'] ?? 0;
      var type = NotificationType.info;
      if (typeValue is int && typeValue >= 0 && typeValue < NotificationType.values.length) {
        type = NotificationType.values[typeValue];
      }
      NotificationOverlayManager().show(
        title: display.title,
        message: display.body.isEmpty ? 'Có thông báo mới' : display.body,
        type: type,
        relatedEntityType: data['relatedEntityType']?.toString(),
        onTap: () => _openTapped(data, display.title),
      );
      ScreenRefreshNotifier.refreshNotificationCount();
    } catch (e) {
      debugPrint('⚠️ BossShell notification: $e');
    }
  }

  /// Màn dùng chung xin mở màn khác (vd «Thiết lập lương», «Phòng ban»): không có MainLayout nên shell tự mở.
  void _onModuleRequested() {
    final code = NavigationNotifier.navigateToModule.value;
    if (code == null || !mounted) return;
    NavigationNotifier.navigateToModule.value = null;
    openBossModule(context, code);
  }

  void _onIndexRequested() {
    final index = NavigationNotifier.navigateTo.value;
    if (index == null || !mounted) return;
    NavigationNotifier.navigateTo.value = null;
    openBossModule(context, switch (index) {
      NavigationNotifier.departments => 'Department',
      NavigationNotifier.employees => 'Employee',
      NavigationNotifier.deviceUsers => 'DeviceUser',
      NavigationNotifier.attendance => 'Attendance',
      NavigationNotifier.attendanceSummary => 'AttendanceSummary',
      NavigationNotifier.attendanceByShift => 'AttendanceByShift',
      NavigationNotifier.payroll => 'Payroll',
      NavigationNotifier.workSchedule => 'WorkSchedule',
      _ => '',
    });
  }

  /// Các màn kho, công việc… kiểm quyền qua [PermissionProvider] — shell phải tải trước khi mở.
  Future<void> _loadPermissions() async {
    final user = context.read<AuthProvider>().user;
    try {
      await context
          .read<PermissionProvider>()
          .loadPermissions(
            role: user?.role,
            freshSession: true,
            cacheKey: user == null ? null : '${user.id}:${user.storeId ?? ''}',
          )
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('⚠️ BossShell permissions: $e');
    }
  }

  Future<void> _refreshUnread() async {
    try {
      final n = (await ApiService().getNotificationSummary())['unreadCount'];
      if (mounted) setState(() => _unread = n is int ? n : int.tryParse('$n') ?? 0);
    } catch (_) {}
  }

  /// Bấm thông báo (thanh thông báo, đẩy điện thoại): không có MainLayout nên shell tự mở màn.
  bool _openFromNotification(String? entityKey, String? relatedEntityId) =>
      mounted && openNotificationInShell(context, entityKey, relatedEntityId);

  Future<void> _openNotifications() async {
    await openStaffPage(context, title: 'Thông báo', child: const NotificationsScreen());
    if (mounted) unawaited(_refreshUnread());
  }

  @override
  Widget build(BuildContext context) {
    final role = context.select<AuthProvider, String>((a) => a.userRole);
    if (!StoreRoleHelper.isBossRole(role)) return const BossRoleBlockedScreen();
    // Nút Back của máy: tab khác về Tổng quan trước, ở Tổng quan mới thoát app.
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _tab = 0);
      },
      child: _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: AppBar(
        backgroundColor: SboxColors.brand700,
        foregroundColor: SboxColors.white,
        title: Text(tr(_titles[_tab])),
        actions: [
          IconButton(
            tooltip: tr('Thông báo'),
            onPressed: _openNotifications,
            icon: Badge(
              isLabelVisible: _unread > 0,
              label: Text(_unread > 99 ? '99+' : '$_unread'),
              child: const Icon(Icons.notifications_outlined),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(right: SboxSpace.sm),
            child: Center(child: BranchSwitcher(compact: true, onDark: true)),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          BossDashboardScreen(onOpenInbox: () => setState(() => _tab = 1)),
          const BossInboxScreen(),
          const BossReportsScreen(),
          const BossManageScreen(),
          const _BossMoreScreen(),
        ],
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton(
              tooltip: tr('Tạo phiếu'),
              backgroundColor: SboxColors.brand600,
              foregroundColor: SboxColors.white,
              onPressed: () => showBossCreateSheet(context),
              child: const Icon(Icons.add_rounded),
            )
          : null,
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: bossInboxCount,
        builder: (context, pending, _) => NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.dashboard_outlined),
              selectedIcon: const Icon(Icons.dashboard_rounded),
              label: tr('Tổng quan'),
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: pending > 0,
                label: Text(pending > 99 ? '99+' : '$pending'),
                child: const Icon(Icons.fact_check_outlined),
              ),
              selectedIcon: Badge(
                isLabelVisible: pending > 0,
                label: Text(pending > 99 ? '99+' : '$pending'),
                child: const Icon(Icons.fact_check_rounded),
              ),
              label: tr('Cần duyệt'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.bar_chart_outlined),
              selectedIcon: const Icon(Icons.bar_chart_rounded),
              label: tr('Báo cáo'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.apps_outlined),
              selectedIcon: const Icon(Icons.apps_rounded),
              label: tr('Quản lý'),
            ),
            NavigationDestination(
              icon: const Icon(Icons.more_horiz_rounded),
              selectedIcon: const Icon(Icons.more_horiz_rounded),
              label: tr('Thêm'),
            ),
          ],
        ),
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
        const SizedBox(height: SboxSpace.md),
        const SboxCard(padding: EdgeInsets.zero, child: CompanionAccountLinks()),
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
              'Nhân viên dùng app SBOX POS hoặc SBOX Nhân Viên.',
          action: SboxButton(label: 'Đăng xuất', onPressed: () => context.read<AuthProvider>().logout()),
        ),
      ),
    );
  }
}
