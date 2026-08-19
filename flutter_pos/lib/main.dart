import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'l10n/app_locale.dart';
import 'l10n/app_localizations.dart';
import 'l10n/app_tr.dart';
import 'providers/auth_provider.dart';
import 'providers/permission_provider.dart';
import 'screens/login_screen.dart';
import 'screens/pos/pos_customer_display_screen.dart';
import 'screens/pos/pos_mobile_hub_screen.dart';
import 'models/hrm.dart';
import 'screens/main_layout.dart';
import 'services/api_service.dart';
import 'services/mobile_bottom_nav_prefs.dart';
import 'services/pos_print_agent_service.dart';
import 'services/session_reset.dart';
import 'services/signalr_service.dart';
import 'utils/notification_display_utils.dart';
import 'utils/navigation_notifier.dart';
import 'utils/pos_print_agent_settings.dart';
import 'utils/pos_print_orchestrator.dart';
import 'utils/pos_qr_order_voice.dart';
import 'utils/pos_payment_gateway_listener.dart';
import 'utils/ssl_trust.dart';
import 'utils/vietnamese_font.dart';
import 'widgets/app_boot_screen.dart';
import 'widgets/notification_overlay.dart';
import 'widgets/pos_app_update_dialog.dart';
import 'widgets/pos/pos_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('FlutterError: ${details.exceptionAsString()}');
  };
  ErrorWidget.builder = (details) {
    return Material(
      color: const Color(0xFFF3F4F6),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Text(
              'Lỗi giao diện:\n${details.exceptionAsString()}',
              style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13),
            ),
          ),
        ),
      ),
    );
  };

  try {
    await initializeDateFormatting('vi_VN', null);
  } catch (e) {
    debugPrint('initializeDateFormatting: $e');
  }

  // HTTPS trên Android cũ (Sunmi T1…): bổ sung ISRG Root trước mọi gọi API.
  await installPosSslTrust();
  await preloadVietnameseFonts();
  await AppLocale.loadSaved();
  trResetCache();

  // Engine màn phụ: giữ orientation theo display khách, không ép POS.
  if (!_isCustomerDisplayRoute) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
  }

  runApp(const SboxPosApp());
}

bool get _isCustomerDisplayRoute {
  final name = ui.PlatformDispatcher.instance.defaultRouteName;
  return name.contains('customer-display');
}

class SboxPosApp extends StatelessWidget {
  const SboxPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Engine phụ (Sunmi T1 7"…): chỉ UI khách, không login.
    if (_isCustomerDisplayRoute) {
      return MaterialApp(
        title: 'SBOX Display',
        debugShowCheckedModeBanner: false,
        theme: applyVietnameseFonts(ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          fontFamily: kVietnameseFontFamily,
          fontFamilyFallback: kVietnameseFontFallback,
        )),
        home: const PosCustomerDisplayScreen(),
        routes: {
          '/customer-display': (_) => const PosCustomerDisplayScreen(),
        },
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PermissionProvider()),
        Provider(create: (_) => ApiService()),
      ],
      child: ListenableBuilder(
        listenable: AppLocale.listenable,
        builder: (context, _) {
          SessionReset.bindPermissionProvider(
            context.read<PermissionProvider>(),
          );
          return MaterialApp(
        title: 'SBOX POS',
        debugShowCheckedModeBanner: false,
        locale: AppLocale.locale,
        supportedLocales: const [
          Locale('vi'),
          Locale('en'),
        ],
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: applyVietnameseFonts(ThemeData(
          useMaterial3: true,
          fontFamily: kVietnameseFontFamily,
          fontFamilyFallback: kVietnameseFontFallback,
          colorScheme: ColorScheme.fromSeed(
            seedColor: PosTheme.kiotBlue,
            primary: PosTheme.kiotBlue,
          ),
          scaffoldBackgroundColor: PosTheme.background,
          appBarTheme: const AppBarTheme(
            backgroundColor: PosTheme.kiotBlue,
            foregroundColor: Colors.white,
          ),
        )),
        routes: {
          '/customer-display': (_) => const PosCustomerDisplayScreen(),
        },
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          final maxIme = mq.size.height / 3;
          Widget body = child ?? const SizedBox.shrink();
          // A6: IME Sunmi thường >½ màn — clamp inset để UI giữ ~⅔ phía trên.
          if (mq.viewInsets.bottom > maxIme) {
            body = MediaQuery(
              data: mq.copyWith(
                viewInsets: mq.viewInsets.copyWith(bottom: maxIme),
              ),
              child: body,
            );
          }
          return NotificationOverlay(child: body);
        },
        home: Consumer<AuthProvider>(
          builder: (context, auth, _) {
            if (auth.isInitializing) {
              return const AppBootScreen();
            }
            if (!auth.isAuthenticated) return const LoginScreen();
            return const _PosAuthShell();
          },
        ),
          );
        },
      ),
    );
  }
}

/// Sau login: tải quyền (có fallback POS), rồi vào [PosMobileHubScreen]
/// (cùng bố cục 5 tab với flutter_client / SDK cao).
class _PosAuthShell extends StatefulWidget {
  const _PosAuthShell();

  @override
  State<_PosAuthShell> createState() => _PosAuthShellState();
}

class _PosAuthShellState extends State<_PosAuthShell>
    with WidgetsBindingObserver {
  bool _ready = false;
  String? _status;
  String? _error;
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
    // Mở lại app: SignalR có thể còn «connected» nhưng group/agent đã mất.
    unawaited(_connectSignalR(forceAgent: true));
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthProvider>();
    final perm = context.read<PermissionProvider>();
    // Fail-open ngay: vào bán hàng không chờ API quyền (tới 12s).
    perm.ensurePosSellDefaults();
    auth.ensurePosPackageDefaults();
    if (mounted) {
      setState(() {
        _ready = true;
        _status = null;
        _error = null;
      });
    }
    unawaited(
      MobileBottomNavPrefs.loadAll().timeout(const Duration(seconds: 4)),
    );
    unawaited(_loadPermissionsInBackground(auth, perm));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(maybePromptPosAppUpdate(context));
    });
    unawaited(_connectSignalR());
  }

  Future<void> _loadPermissionsInBackground(
    AuthProvider auth,
    PermissionProvider perm,
  ) async {
    try {
      // Luôn gọi ACL thật — ensurePosSellDefaults() đã set isLoaded=true (fail-open UI)
      // nên không được skip; nếu skip thì Admin không lên superUser → nút TT xám mãi.
      await perm
          .loadPermissions(role: auth.user?.role, freshSession: true)
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('⚠️ PosAuthShell permissions: $e');
    } finally {
      // Giữ defaults nếu ACL rỗng; không ghi đè Approve đã load / superUser.
      perm.ensurePosSellDefaults();
      auth.ensurePosPackageDefaults();
      debugPrint(
        '✅ PosAuthShell perms role=${auth.user?.role} '
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
      debugPrint('⚠️ PosAuthShell SignalR: $e');
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
      debugPrint('⚠️ PosAuthShell notification: $e');
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
                _status ?? 'Đang mở bán hàng…',
                style: const TextStyle(
                  fontSize: 13,
                  color: PosTheme.textSecondary,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, color: Colors.orange),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // Tab Bán hàng (2) — hub lazy-load các tab khác khi mở lần đầu.
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
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
      child: const PosMobileHubScreen(initialTab: 2),
    );
  }
}
