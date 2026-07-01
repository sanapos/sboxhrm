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
import '../screens/agent_portal_screen.dart';
import '../screens/agent_register_screen.dart';
import '../screens/admin_login_screen.dart';
import '../screens/landing_screen.dart';
import '../screens/landing_guide_screen.dart';
import '../utils/web_route_parser.dart';
import '../widgets/app_boot_screen.dart';

class ZKTecoApp extends StatelessWidget {
  const ZKTecoApp({super.key});

  @override
  Widget build(BuildContext context) {
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
            // Web/desktop: giữ cỡ thiết kế (14px body). Chỉ điện thoại hẹp thu nhỏ nhẹ.
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
            '/register': (context) => const RegisterScreen(),
            '/agent-register': (context) {
              final token = parseAgentRegistrationToken() ?? '';
              return AgentRegisterScreen(token: token);
            },
            '/forgot-password': (context) => const ForgotPasswordScreen(),
            '/admin': (context) => const _AdminRouteGuard(),
            '/login-app': (context) => const LoginScreen(),
            '/landing': (context) {
              final args = ModalRoute.of(context)?.settings.arguments;
              final section = args is Map
                  ? args['scrollSection']?.toString()
                  : null;
              return LandingScreen(initialScrollSection: section);
            },
            '/guide': (context) => const LandingGuideScreen(),
          },
          onGenerateRoute: (settings) {
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
          home: Selector<AuthProvider, ({bool isInit, bool isAuth})>(
            selector: (_, auth) =>
                (isInit: auth.isInitializing, isAuth: auth.isAuthenticated),
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
                  return const RegisterScreen();
                }
                return kIsWeb ? const LandingScreen() : const LoginScreen();
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

        if (state.role == 'SuperAdmin') {
          return const SystemAdminScreen();
        }

        if (state.role == 'Agent') {
          return const AgentPortalScreen();
        }

        return const AdminLoginScreen();
      },
    );
  }
}
