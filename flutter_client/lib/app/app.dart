import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../screens/main_layout.dart';
import '../screens/login_screen.dart';
import '../screens/register_screen.dart';
import '../screens/forgot_password_screen.dart';
import '../screens/reset_password_screen.dart';
import '../screens/system_admin_screen.dart';
import '../screens/admin_login_screen.dart';

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
          themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
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
            final screenWidth = mediaQuery.size.width;
            // Base design width: 375 (iPhone SE/small phone)
            // Scale factor: clamp between 0.8 and 1.3
            // On small screens (<375): scale down
            // On medium phones (375-414): ~1.0x
            // On large phones/tablets: scale up slightly
            final scaleFactor = (screenWidth / 375).clamp(0.82, 1.3);
            // Combine with user's accessibility text scale
            final userScale = mediaQuery.textScaler.scale(1.0);
            final combinedScale = min(scaleFactor * userScale, 1.5);
            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: TextScaler.linear(combinedScale),
              ),
              child: child!,
            );
          },
          routes: {
            '/register': (context) => const RegisterScreen(),
            '/forgot-password': (context) => const ForgotPasswordScreen(),
            '/admin': (context) => const _AdminRouteGuard(),
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
            return null;
          },
          home: Selector<AuthProvider, ({bool isInit, bool isAuth})>(
            selector: (_, auth) => (isInit: auth.isInitializing, isAuth: auth.isAuthenticated),
            builder: (context, state, child) {
              if (state.isInit) {
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              return state.isAuth
                  ? const MainLayout()
                  : const LoginScreen();
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

        if (state.role == 'SuperAdmin' || state.role == 'Agent') {
          return const SystemAdminScreen();
        }

        return const AdminLoginScreen();
      },
    );
  }
}
