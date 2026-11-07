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
import '../../services/api_service.dart';
import '../../utils/notification_navigation.dart';
import '../../utils/navigation_notifier.dart';
import '../../utils/notification_open_screens.dart';
import '../../utils/pending_notification_launch.dart';
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

/// Khung app SBOX Nhân Viên (flavor `staff`): thanh dưới tối đa 5 tab cho nhân viên —
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
    notificationShellHandler = _openFromNotification;
    notificationShellCanOpen = _canOpenNotification;
    NavigationNotifier.staffLeavePosHub = _leaveOrderTab;
    PendingNotificationLaunch.scheduleConsume();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadPermissions());
      unawaited(_connectSignalR());
    });
  }

  @override
  void dispose() {
    if (notificationShellHandler == _openFromNotification) notificationShellHandler = null;
    if (notificationShellCanOpen == _canOpenNotification) notificationShellCanOpen = null;
    if (NavigationNotifier.staffLeavePosHub == _leaveOrderTab) {
      NavigationNotifier.staffLeavePosHub = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    _notificationSub?.cancel();
    unawaited(_signalR.disconnect());
    super.dispose();
  }

  /// Màn bán hàng xin «về trang chủ» (Back ở sơ đồ bàn) → tab Trang chủ của app nhân viên.
  void _leaveOrderTab() {
    if (mounted) _select(_StaffTab.home);
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
      debugPrint('⚠️ StaffShell SignalR: $e');
    } finally {
      _connectingSignalR = false;
    }
  }

  /// Bấm thông báo (popup, thanh thông báo, đẩy điện thoại): không có MainLayout nên shell tự mở màn.
  bool _openFromNotification(String? entityKey, String? relatedEntityId) {
    if (!mounted) return false;
    if (StaffEntries.isScheduleNotification(entityKey) && staffCanOpen(context, 'WorkSchedule', listen: false)) {
      Navigator.of(context).popUntil((r) => r.isFirst);
      _select(_StaffTab.schedule);
      return true;
    }
    final entry = StaffEntries.forNotification(entityKey);
    if (entry != null && staffCanOpen(context, entry.moduleCode, listen: false)) {
      if (relatedEntityId != null && relatedEntityId.isNotEmpty) {
        NavigationNotifier.notificationHighlightId.value = relatedEntityId;
      }
      unawaited(entry.open(context));
      return true;
    }
    return openNotificationInShell(context, entityKey, relatedEntityId);
  }

  bool _canOpenNotification(String? entityKey) {
    if (!mounted) return false;
    if (StaffEntries.isScheduleNotification(entityKey)) return staffCanOpen(context, 'WorkSchedule', listen: false);
    if (entityKey == 'posquote') return staffCanOpen(context, 'PosQuotes', listen: false);
    if (entityKey == 'posreportexpiry') return staffCanOpen(context, 'PosReportExpiry', listen: false);
    final entry = StaffEntries.forNotification(entityKey);
    return entry != null && staffCanOpen(context, entry.moduleCode, listen: false);
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
        onTap: () => _openTapped(data, display.title),
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
            onOpenMe: () => _select(_StaffTab.me),
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
              backgroundColor: SboxColors.chrome,
              surfaceTintColor: Colors.transparent,
            ),
            body: const MyScheduleView(onChanged: ScreenRefreshNotifier.refreshDashboardScreen),
          ),
        _StaffTab.pay => const _StaffPayTab(),
        _StaffTab.me => const _StaffMeTab(),
      };

  static ({String label, IconData icon}) _meta(_StaffTab t) => switch (t) {
        _StaffTab.home => (label: 'Trang chủ', icon: Icons.home_rounded),
        _StaffTab.order => (label: 'Order', icon: Icons.room_service_rounded),
        _StaffTab.schedule => (label: 'Lịch', icon: Icons.calendar_month_rounded),
        // Nhãn ngắn — «Công & lương» xuống 2 dòng khi đủ 5 tab (máy 360dp).
        _StaffTab.pay => (label: 'Công lương', icon: Icons.account_balance_wallet_rounded),
        _StaffTab.me => (label: 'Tôi', icon: Icons.person_rounded),
      };

  /// Thanh dưới kiểu SBOX POS: cùng màu nền trang, tab đang chọn có nền viên nhạt.
  Widget _bottomBar() {
    final tabs = _visibleTabs();
    final current = tabs.contains(_tab) ? _tab : _StaffTab.home;
    return Material(
      color: SboxColors.chrome,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: SboxSpace.xs, vertical: SboxSpace.xxs),
          child: Row(
            children: [
              for (final t in tabs)
                Expanded(child: _navItem(t, selected: t == current)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(_StaffTab t, {required bool selected}) {
    final meta = _meta(t);
    final color = selected ? SboxColors.brand600 : SboxColors.slate500;
    return Semantics(
      button: true,
      selected: selected,
      label: tr(meta.label),
      excludeSemantics: true,
      onTap: () => _select(t),
      child: GestureDetector(
        onTap: () => _select(t),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: SboxSpace.xs, vertical: 6),
          decoration: selected
              ? BoxDecoration(
                  color: SboxColors.brand600.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(SboxRadius.lg),
                )
              : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(meta.icon, size: 24, color: color),
              const SizedBox(height: 2),
              // Đủ 5 tab trên máy 360dp: thu chữ cho vừa, không cắt «Công lươ…».
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  tr(meta.label),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? SboxType.semibold : SboxType.regular,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final nav = Navigator.of(context);
          if (nav.canPop()) {
            nav.pop();
            return;
          }
          // Đang trong bàn / chọn món: màn bán hàng tự lùi (đóng chọn món, thoát bàn) như app POS.
          final posBack = NavigationNotifier.posHandleSystemBack;
          if (current == _StaffTab.order && posBack != null && await posBack()) return;
          if (!mounted) return;
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
        backgroundColor: SboxColors.chrome,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(SboxSpace.lg, SboxSpace.sm, SboxSpace.lg, SboxSpace.lg),
        children: [
          StaffMenuSection(
            title: 'Chấm công',
            icon: Icons.fingerprint_rounded,
            entries: StaffEntries.attendanceAndPay,
          ),
          StaffMenuSection(
            title: 'Lương & thu nhập',
            icon: Icons.payments_rounded,
            entries: StaffEntries.pay(staffCanOpen(context, 'BonusPenalty')),
          ),
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
        backgroundColor: SboxColors.chrome,
        surfaceTintColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(SboxSpace.lg, SboxSpace.xs, SboxSpace.lg, SboxSpace.lg),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: SboxSpace.lg),
            child: Row(
              children: [
                StaffAvatar(name: name.isEmpty ? (user?.email ?? '') : name, radius: 28),
                const SizedBox(width: SboxSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isEmpty ? (user?.email ?? '') : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SboxType.titleStyle(),
                      ),
                      if (sub.isNotEmpty) Text(sub, style: SboxType.smallStyle()),
                      if (name.isNotEmpty && (user?.email ?? '').isNotEmpty)
                        Text(
                          user!.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SboxType.smallStyle(SboxColors.textMuted),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: tr('Đăng xuất'),
                  onPressed: () => _logout(context),
                  icon: const Icon(Icons.logout_rounded, color: SboxColors.danger),
                ),
              ],
            ),
          ),
          StaffMenuSection(
            title: 'Đơn từ',
            icon: Icons.description_rounded,
            entries: StaffEntries.requests,
          ),
          StaffMenuSection(
            title: 'Công việc & tiện ích',
            icon: Icons.work_rounded,
            entries: StaffEntries.work,
          ),
          StaffMenuSection(
            title: 'Tài khoản',
            icon: Icons.person_rounded,
            entries: [
              StaffEntry(
                moduleCode: 'Settings',
                title: 'Cài đặt',
                icon: Icons.manage_accounts_rounded,
                ownScaffold: true,
                builder: (_) => const SettingsScreen(showAppBar: true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
