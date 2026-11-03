import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../services/signalr_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/notification_display_utils.dart';
import '../../utils/store_role_helper.dart';
import '../../widgets/notification_overlay.dart';
import '../main_layout.dart' show ScreenRefreshNotifier;
import '../pos/pos_mobile_hub_screen.dart';
import '../settings_screen.dart';
import '../shift_hub/my_schedule_view.dart';
import 'staff_entries.dart';
import 'staff_home_tab.dart';
import 'staff_nav.dart';

enum _StaffTab { home, order, schedule, pay, me }

/// Khung app SBOX Staff (flavor `staff`): thanh dưới tối đa 5 tab cho nhân viên —
/// Trang chủ · Order · Lịch · Công & lương · Tôi. Không mở [MainLayout] quản trị;
/// mục nào vai trò / gói dịch vụ không có thì tự ẩn.
class StaffShell extends StatefulWidget {
  const StaffShell({super.key});

  @override
  State<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends State<StaffShell> with WidgetsBindingObserver {
  _StaffTab _tab = _StaffTab.home;

  /// Chỉ dựng tab đã mở — màn Order (bán hàng) rất nặng, không dựng sẵn.
  final Set<_StaffTab> _activated = {_StaffTab.home};
  bool _didLandOrder = false;

  final _signalR = SignalRService();
  StreamSubscription? _notificationSub;
  bool _connectingSignalR = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadPermissions());
      unawaited(_connectSignalR());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationSub?.cancel();
    unawaited(_signalR.disconnect());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    unawaited(_connectSignalR());
    ScreenRefreshNotifier.refreshDashboardScreen();
  }

  Future<void> _loadPermissions() async {
    final auth = context.read<AuthProvider>();
    final perm = context.read<PermissionProvider>();
    final user = auth.user;
    try {
      await perm
          .loadPermissions(
            role: user?.role,
            freshSession: true,
            cacheKey: user == null ? null : '${user.id}:${user.storeId ?? ''}',
          )
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('⚠️ StaffShell permissions: $e');
    }
    if (!mounted) return;
    // Phục vụ / thu ngân: mở thẳng màn gọi món (như MainLayout._maybeLandPosSell).
    if (!_didLandOrder &&
        StoreRoleHelper.isPosCashierRole(auth.userRole) &&
        _canOrder(listen: false)) {
      _didLandOrder = true;
      _select(_StaffTab.order);
    }
  }

  Future<void> _connectSignalR() async {
    if (_connectingSignalR || !mounted) return;
    _connectingSignalR = true;
    try {
      await _notificationSub?.cancel();
      if (!mounted) return;
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
      _notificationSub = _signalR.onNewNotification.listen(_handleNewNotification);
    } catch (e) {
      debugPrint('⚠️ StaffShell SignalR: $e');
    } finally {
      _connectingSignalR = false;
    }
  }

  void _handleNewNotification(Map<String, dynamic> data) {
    try {
      final display = resolveNotificationDisplay(data);
      final typeValue = data['type'] ?? 0;
      var type = NotificationType.info;
      if (typeValue is int &&
          typeValue >= 0 &&
          typeValue < NotificationType.values.length) {
        type = NotificationType.values[typeValue];
      }
      NotificationOverlayManager().show(
        title: display.title,
        message: display.body.isEmpty ? 'Có thông báo mới' : display.body,
        type: type,
        relatedEntityType: data['relatedEntityType']?.toString(),
      );
      ScreenRefreshNotifier.refreshNotificationCount();
      ScreenRefreshNotifier.refreshDashboardScreen();
    } catch (e) {
      debugPrint('⚠️ StaffShell notification: $e');
    }
  }

  bool _canOrder({bool listen = true}) {
    final perm = listen
        ? context.watch<PermissionProvider>()
        : context.read<PermissionProvider>();
    return staffCanOpen(context, 'PosSell', listen: listen) && perm.canPosOrder();
  }

  List<_StaffTab> _visibleTabs() => [
        _StaffTab.home,
        if (_canOrder()) _StaffTab.order,
        if (staffCanOpen(context, 'WorkSchedule')) _StaffTab.schedule,
        _StaffTab.pay,
        _StaffTab.me,
      ];

  void _select(_StaffTab t) {
    if (t == _tab) return;
    setState(() {
      _activated.add(t);
      _tab = t;
    });
  }

  Widget _buildTab(_StaffTab t) => switch (t) {
        _StaffTab.home => StaffHomeTab(
            onOpenSchedule: () => _select(_StaffTab.schedule),
          ),
        _StaffTab.order => PosMobileHubScreen(
            initialTab: 2,
            restoreLastTab: false,
            // Thanh dưới do khung Staff vẽ (cả khi hub đang Bán hàng toàn màn) — hub không vẽ ô POS riêng.
            bottomBarBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        _StaffTab.schedule => Scaffold(
            backgroundColor: SboxColors.page,
            appBar: AppBar(
              title: Text(tr('Lịch làm việc')),
              backgroundColor: SboxColors.white,
              surfaceTintColor: SboxColors.white,
            ),
            body: const MyScheduleView(onChanged: ScreenRefreshNotifier.refreshDashboardScreen),
          ),
        _StaffTab.pay => const _StaffPayTab(),
        _StaffTab.me => const _StaffMeTab(),
      };

  static ({String label, IconData icon, IconData active}) _meta(_StaffTab t) =>
      switch (t) {
        _StaffTab.home => (label: 'Trang chủ', icon: Icons.home_outlined, active: Icons.home),
        _StaffTab.order => (
            label: 'Order',
            icon: Icons.room_service_outlined,
            active: Icons.room_service
          ),
        _StaffTab.schedule => (
            label: 'Lịch',
            icon: Icons.calendar_month_outlined,
            active: Icons.calendar_month
          ),
        _StaffTab.pay => (
            label: 'Công & lương',
            icon: Icons.account_balance_wallet_outlined,
            active: Icons.account_balance_wallet
          ),
        _StaffTab.me => (label: 'Tôi', icon: Icons.person_outline, active: Icons.person),
      };

  Widget _bottomBar() {
    final tabs = _visibleTabs();
    final index = tabs.indexOf(_tab).clamp(0, tabs.length - 1);
    return NavigationBar(
      selectedIndex: index,
      height: 64,
      backgroundColor: SboxColors.white,
      surfaceTintColor: SboxColors.white,
      indicatorColor: SboxColors.primarySoft,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      onDestinationSelected: (i) => _select(tabs[i]),
      destinations: [
        for (final t in tabs)
          NavigationDestination(
            icon: Icon(_meta(t).icon),
            selectedIcon: Icon(_meta(t).active, color: SboxColors.primary),
            label: tr(_meta(t).label),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tabs = _visibleTabs();
    // Quyền đổi (tải xong / bị thu hồi) mà tab đang mở không còn → về Trang chủ.
    final current = tabs.contains(_tab) ? _tab : _StaffTab.home;
    return NotificationOverlay(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          final nav = Navigator.of(context);
          if (nav.canPop()) {
            nav.pop();
            return;
          }
          if (current != _StaffTab.home) {
            _select(_StaffTab.home);
            return;
          }
          SystemNavigator.pop();
        },
        child: Scaffold(
          body: IndexedStack(
            index: tabs.indexOf(current),
            children: [
              // Khóa theo tab: quyền tải xong chèn thêm tab Order thì các tab khác giữ nguyên trạng thái.
              for (final t in tabs)
                KeyedSubtree(
                  key: ValueKey(t),
                  child: _activated.contains(t) || t == current
                      ? _buildTab(t)
                      : const SizedBox.shrink(),
                ),
            ],
          ),
          bottomNavigationBar: _bottomBar(),
        ),
      ),
    );
  }
}

/// Tab «Công & lương»: chấm công, lịch sử, giải trình, phiếu lương, thưởng phạt, tạm ứng.
class _StaffPayTab extends StatelessWidget {
  const _StaffPayTab();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: AppBar(
        title: Text(tr('Công & lương')),
        backgroundColor: SboxColors.white,
        surfaceTintColor: SboxColors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StaffMenuSection(title: 'Chấm công', entries: StaffEntries.attendanceAndPay),
          StaffMenuSection(title: 'Lương & thu nhập', entries: StaffEntries.pay),
        ],
      ),
    );
  }
}

/// Tab «Tôi»: hồ sơ, đơn từ, công việc, cài đặt cá nhân, đăng xuất.
class _StaffMeTab extends StatelessWidget {
  const _StaffMeTab();

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Đăng xuất')),
        content: Text(tr('Bạn muốn đăng xuất khỏi tài khoản này?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Hủy')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Đăng xuất')),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<AuthProvider>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final name = (user?.fullName ?? '').trim();
    final sub = [
      if ((user?.position ?? '').isNotEmpty) user!.position!,
      if ((user?.department ?? '').isNotEmpty) user!.department!,
    ].join(' · ');
    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: AppBar(
        title: Text(tr('Tôi')),
        backgroundColor: SboxColors.white,
        surfaceTintColor: SboxColors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: SboxColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: SboxColors.border),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: SboxColors.primarySoft,
                  child: Text(
                    name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: SboxColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? (user?.email ?? '') : name,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      if (sub.isNotEmpty)
                        Text(sub,
                            style: const TextStyle(
                                fontSize: 13, color: SboxColors.textMuted)),
                      if (name.isNotEmpty && (user?.email ?? '').isNotEmpty)
                        Text(user!.email,
                            style: const TextStyle(
                                fontSize: 12, color: SboxColors.textMuted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          StaffMenuSection(title: 'Đơn từ', entries: StaffEntries.requests),
          StaffMenuSection(title: 'Công việc & tiện ích', entries: StaffEntries.work),
          StaffMenuSection(
            title: 'Tài khoản',
            entries: [
              StaffEntry(
                moduleCode: 'Settings',
                title: 'Cài đặt',
                icon: Icons.settings_outlined,
                color: SboxColors.textSecondary,
                ownScaffold: true,
                builder: (_) => const SettingsScreen(showAppBar: true),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _logout(context),
            icon: const Icon(Icons.logout, color: SboxColors.danger),
            label: Text(tr('Đăng xuất'),
                style: const TextStyle(color: SboxColors.danger)),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              side: const BorderSide(color: SboxColors.border),
            ),
          ),
        ],
      ),
    );
  }
}
