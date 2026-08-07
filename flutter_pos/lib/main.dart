import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'providers/permission_provider.dart';
import 'screens/login_screen.dart';
import 'screens/pos/pos_mobile_hub_screen.dart';
import 'screens/pos_sell_screen.dart';
import 'services/api_service.dart';
import 'services/mobile_bottom_nav_prefs.dart';
import 'widgets/pos/pos_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
    DeviceOrientation.portraitUp,
  ]);

  runApp(const SboxPosApp());
}

class SboxPosApp extends StatelessWidget {
  const SboxPosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PermissionProvider()),
        Provider(create: (_) => ApiService()),
      ],
      child: MaterialApp(
        title: 'SBOX POS',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: PosTheme.kiotBlue,
            primary: PosTheme.kiotBlue,
          ),
          scaffoldBackgroundColor: PosTheme.background,
          appBarTheme: const AppBarTheme(
            backgroundColor: PosTheme.kiotBlue,
            foregroundColor: Colors.white,
          ),
        ),
        home: Consumer<AuthProvider>(
          builder: (context, auth, _) {
            if (auth.isInitializing) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (!auth.isAuthenticated) return const LoginScreen();
            // Phải load quyền trước khi mở POS — giống MainLayout flutter_client.
            return const _PosAuthShell();
          },
        ),
      ),
    );
  }
}

/// Sau login: tải PermissionProvider + nav prefs, rồi mới vào bán hàng.
/// Thiếu bước này → canView('PosSell') = false → màn xám trống.
class _PosAuthShell extends StatefulWidget {
  const _PosAuthShell();

  @override
  State<_PosAuthShell> createState() => _PosAuthShellState();
}

class _PosAuthShellState extends State<_PosAuthShell> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final auth = context.read<AuthProvider>();
    final perm = context.read<PermissionProvider>();
    try {
      final navFut = MobileBottomNavPrefs.loadAll();
      if (!perm.isLoaded) {
        await perm.loadPermissions(role: auth.user?.role);
      }
      await navFut;
    } catch (e) {
      debugPrint('⚠️ PosAuthShell bootstrap: $e');
      if (mounted) setState(() => _error = e.toString());
    }
    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        backgroundColor: PosTheme.background,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: PosTheme.kiotBlue),
              SizedBox(height: 12),
              Text(
                'Đang tải quyền truy cập…',
                style: TextStyle(fontSize: 13, color: PosTheme.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: PosTheme.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Không tải được quyền truy cập',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(_error!, textAlign: TextAlign.center,
                    style: const TextStyle(color: PosTheme.textSecondary)),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _ready = false;
                      _error = null;
                    });
                    _bootstrap();
                  },
                  child: const Text('Thử lại'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (wide) return const PosSellScreen();
    return const PosMobileHubScreen();
  }
}
