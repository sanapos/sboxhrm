import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../utils/app_text_scaler.dart';
import '../utils/vietnamese_font.dart';
import '../screens/main_layout.dart';
import '../screens/login_screen.dart';
import '../screens/register_screen.dart';
import '../screens/forgot_password_screen.dart';
import '../screens/reset_password_screen.dart';
import '../screens/system_admin_screen.dart';
import '../screens/agent_register_screen.dart';
import '../screens/admin_login_screen.dart';
import '../screens/landing_guide_screen.dart';
import '../screens/pos/pos_customer_display_screen.dart';
import '../utils/web_route_parser.dart';
import '../utils/store_role_helper.dart';
import '../widgets/app_boot_screen.dart';
import '../widgets/web_static_home_redirect.dart';

class ZKTecoApp extends StatelessWidget {
  const ZKTecoApp({super.key});

  static bool get _isCustomerDisplayRoute {
    final name = ui.PlatformDispatcher.instance.defaultRouteName;
    if (name.contains('customer-display')) return true;
    if (kIsWeb) {
      final segs = parseWebHashPathSegments();
      if (segs.isNotEmpty && segs.first == 'customer-display') return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    // Màn hình phụ — không cần đăng nhập; chỉ nhận state sync local.
    if (_isCustomerDisplayRoute) {
      return MaterialApp(
        title: 'SBOX Display',
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const PosCustomerDisplayScreen(),
        routes: {
          '/customer-display': (_) => const PosCustomerDisplayScreen(),
        },
      );
    }

    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: 'SBOX HRM',
          debugShowCheckedModeBanner: false,
          theme: themeProvider.lightTheme,
          darkTheme: themeProvider.darkTheme,
          themeMode:
              themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('vi'),
            Locale('en'),
          ],
          locale: themeProvider.locale,
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: AppTextScaler.resolve(context),
              ),
              child: DefaultTextStyle(
                style: kDefaultVietnameseTextStyle,
                child: child!,
              ),
            );
          },
          routes: {
            '/customer-display': (_) => const PosCustomerDisplayScreen(),
            '/register': (context) {
              final args = ModalRoute.of(context)?.settings.arguments;
              String? agentCode;
              String? packageName;
              if (args is Map) {
                agentCode = args['agentCode']?.toString();
                packageName = args['packageName']?.toString();
              }
              agentCode ??= InitialWebRoute.agentCode;
              return RegisterScreen(
                initialAgentCode: agentCode,
                initialPackageName: packageName,
              );
            },
            '/agent-register': (context) {
              final token = parseAgentRegistrationToken() ?? '';
              return AgentRegisterScreen(token: token);
            },
            '/forgot-password': (context) {
              final args = ModalRoute.of(context)?.settings.arguments;
              if (args is Map) {
                return ForgotPasswordScreen(
                  initialStoreCode: args['storeCode']?.toString(),
                  initialEmail: args['email']?.toString(),
                );
              }
              return const ForgotPasswordScreen();
            },
            '/admin': (context) => const _AdminRouteGuard(),
            '/login-app': (context) => const LoginScreen(),
            '/landing': (context) => const WebStaticHomeRedirect(),
            '/guide': (context) => const LandingGuideScreen(),
          },
          onGenerateRoute: (settings) {
            if (settings.name == '/customer-display') {
              return MaterialPageRoute(
                builder: (_) => const PosCustomerDisplayScreen(),
              );
            }
            if (settings.name == '/reset-password') {
              final args = settings.arguments as Map<String, String>?;
              final uri = Uri.parse(settings.name ?? '');
              final email =
                  args?['email'] ?? uri.queryParameters['email'] ?? '';
              final token =
                  args?['token'] ?? uri.queryParameters['token'] ?? '';
              return MaterialPageRoute(
                builder: (context) =>
                    ResetPasswordScreen(email: email, token: token),
              );
            }
            final name = settings.name ?? '';
            if (name.startsWith('/agent-register/')) {
              final token = name.replaceFirst('/agent-register/', '').trim();
              return MaterialPageRoute(
                builder: (context) => AgentRegisterScreen(token: token),
              );
            }
            if (name == '/agent-register') {
              final token = parseAgentRegistrationToken() ?? '';
              return MaterialPageRoute(
                builder: (context) => AgentRegisterScreen(token: token),
              );
            }
            return null;
          },
          home: Selector<AuthProvider, ({bool isInit, bool isAuth, String role})>(
            selector: (_, auth) => (
              isInit: auth.isInitializing,
              isAuth: auth.isAuthenticated,
              role: auth.userRole,
            ),
            builder: (context, state, child) {
              if (state.isInit) {
                return const AppBootScreen();
              }
              if (!state.isAuth) {
                if (kIsWeb && InitialWebRoute.showAgentRegister) {
                  final token = InitialWebRoute.agentRegisterToken ?? '';
                  return AgentRegisterScreen(token: token);
                }
                if (kIsWeb && InitialWebRoute.showRegister) {
                  return RegisterScreen(initialAgentCode: InitialWebRoute.agentCode);
                }
                if (kIsWeb && InitialWebRoute.showForgotPassword) {
                  return const ForgotPasswordScreen();
                }
                if (kIsWeb && InitialWebRoute.showLogin) {
                  return const LoginScreen();
                }
                if (kIsWeb && InitialWebRoute.showGuide) {
                  return const LandingGuideScreen();
                }
                return kIsWeb
                    ? const WebStaticHomeRedirect()
                    : const LoginScreen();
              }
              if (StoreRoleHelper.isSystemPortalRole(state.role)) {
                return SystemAdminScreen(
                  agentMode: state.role.toLowerCase() == 'agent',
                );
              }
              return const MainLayout();
            },
          ),
        );
      },
    );
  }
}

class _AdminRouteGuard extends StatelessWidget {
  const _AdminRouteGuard();

  @override
  Widget build(BuildContext context) {
    return Selector<AuthProvider, ({bool isAuthenticated, String? role})>(
      selector: (_, auth) => (
        isAuthenticated: auth.isAuthenticated,
        role: auth.userRole,
      ),
      builder: (context, state, child) {
        if (!state.isAuthenticated) {
          return const AdminLoginScreen();
        }

        if (StoreRoleHelper.isSystemPortalRole(state.role)) {
          return SystemAdminScreen(
            agentMode: state.role!.toLowerCase() == 'agent',
          );
        }

        return const AdminLoginScreen();
      },
    );
  }
}
