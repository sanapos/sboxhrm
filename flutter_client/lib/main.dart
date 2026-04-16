import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'app/app.dart';
import 'providers/auth_provider.dart';
import 'providers/permission_provider.dart';
import 'providers/theme_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Tắt Widget Inspector overlay trong debug mode
  WidgetsApp.debugAllowBannerOverride = false;

  // Ẩn sọc vàng đen overflow trong debug mode
  debugDisableClipLayers = false;
  debugDisablePhysicalShapeLayers = false;
  debugRepaintRainbowEnabled = false;

  // Suppress overflow error indicators visually
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final exception = details.exception;
    if (exception is FlutterError &&
        exception.toString().contains('overflowed by')) {
      // Chỉ log, không hiển thị sọc vàng đen
      debugPrint('⚠️ Overflow: ${details.summary}');
      return;
    }
    originalOnError?.call(details);
  };

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PermissionProvider()),
      ],
      child: const ZKTecoApp(),
    ),
  );
}
