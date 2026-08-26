import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../models/hrm.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../services/mobile_bottom_nav_prefs.dart';
import '../../services/pos_print_agent_service.dart';
import '../../services/signalr_service.dart';
import '../../utils/navigation_notifier.dart';
import '../../utils/notification_display_utils.dart';
import '../../utils/pos_payment_gateway_listener.dart';
import '../../utils/pos_print_agent_settings.dart';
import '../../utils/pos_print_orchestrator.dart';
import '../../utils/pos_qr_order_voice.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import '../main_layout.dart' show ScreenRefreshNotifier;
import 'pos_mobile_hub_screen.dart';

/// Shell POS độc lập (Play / flavor `pos`): quyền fail-open, SignalR + in,
/// hub 5 tab — cùng luồng A6, không mở [MainLayout] HRM.
class PosStandaloneShell extends StatefulWidget {
  const PosStandaloneShell({super.key});

  @override
  State<PosStandaloneShell> createState() => _PosStandaloneShellState();
}

class _PosStandaloneShellState extends State<PosStandaloneShell>
    with WidgetsBindingObserver {
  bool _ready = false;
  final _signalR = SignalRService();
  StreamSubscription? _notificationSub;
  bool _connectingSignalR = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
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
    unawaited(_connectSignalR(forceAgent: true));
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthProvider>();
    final perm = context.read<PermissionProvider>();
    perm.ensurePosSellDefaults();
    auth.ensurePosPackageDefaults();
    if (mounted) setState(() => _ready = true);

    unawaited(
      MobileBottomNavPrefs.loadAll().timeout(const Duration(seconds: 4)),
    );
    unawaited(_loadPermissionsInBackground(auth, perm));
    unawaited(_connectSignalR());
  }

  Future<void> _loadPermissionsInBackground(
    AuthProvider auth,
    PermissionProvider perm,
  ) async {
    try {
      await perm
          .loadPermissions(role: auth.user?.role, freshSession: true)
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('⚠️ PosStandaloneShell permissions: $e');
    } finally {
      perm.ensurePosSellDefaults();
      auth.ensurePosPackageDefaults();
      debugPrint(
        '✅ PosStandaloneShell perms role=${auth.user?.role} '
        'loaded=${perm.isLoaded} canPay=${perm.canPosPay()}',
      );
    }
  }

  Future<void> _connectSignalR({bool forceAgent = false}) async {
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
        await PosPrintOrchestrator.instance.ensureListening();
        final agentSettings = await PosPrintAgentSettings.load();
        if (agentSettings.enabled) {
          final u = auth.user;
          final label = [
            if ((u?.fullName ?? '').trim().isNotEmpty) u!.fullName.trim(),
            if ((u?.email ?? '').trim().isNotEmpty) u!.email.trim(),
          ].join(' · ');
          if (label.isNotEmpty && agentSettings.accountLabel != label) {
            await agentSettings.copyWith(accountLabel: label).save();
          }
        }
        await PosPrintAgentService.instance.ensureRunning(
          storeId,
          forceReregister: forceAgent,
        );
        unawaited(PosQrOrderVoiceAlert.instance.start());
        PosPaymentGatewayListener.instance.start();
      }
      final userId = auth.user?.id;
      if (userId != null && userId.isNotEmpty) {
        await _signalR.joinUserGroup(userId);
      }

      _notificationSub =
          _signalR.onNewNotification.listen(_handleNewNotification);
    } catch (e) {
      debugPrint('⚠️ PosStandaloneShell SignalR: $e');
    } finally {
      _connectingSignalR = false;
    }
  }

  void _handleNewNotification(Map<String, dynamic> data) {
    try {
      final display = resolveNotificationDisplay(data);
      final typeValue = data['type'] ?? 0;
      NotificationType type = NotificationType.info;
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
    } catch (e) {
      debugPrint('⚠️ PosStandaloneShell notification: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Scaffold(
        backgroundColor: PosTheme.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: PosTheme.kiotBlue),
              const SizedBox(height: 12),
              Text(
                tr('Đang mở bán hàng…'),
                style: const TextStyle(
                  fontSize: 13,
                  color: PosTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

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
          final handler = NavigationNotifier.posHandleSystemBack;
          if (handler != null && await handler()) return;
          SystemNavigator.pop();
        },
        child: const PosMobileHubScreen(
          initialTab: 2,
          restoreLastTab: false,
        ),
      ),
    );
  }
}
