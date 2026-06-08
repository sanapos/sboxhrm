import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'utils/vietnamese_font.dart';
import 'utils/app_error_utils.dart';
import 'widgets/app_fatal_error_screen.dart';
import 'app/app.dart';
import 'providers/auth_provider.dart';
import 'providers/permission_provider.dart';
import 'providers/theme_provider.dart';
import 'services/fcm_service_stub.dart'
    if (dart.library.io) 'services/fcm_service.dart';

void main() async {
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
      debugPrint('⚠️ Overflow: ${details.summary}');
      return;
    }
    AppErrorUtils.logFlutterError(details);
    originalOnError?.call(details);
  };

  // Widget build lỗi → màn báo rõ (mạng / timeout / chi tiết kỹ thuật).
  ErrorWidget.builder = (FlutterErrorDetails details) {
    AppErrorUtils.logFlutterError(details);
    if (kDebugMode) {
      return ErrorWidget(details.exception);
    }
    return AppFatalErrorScreen(details: details);
  };

  await preloadVietnameseFonts();

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

  // FCM sau frame đầu — giảm tranh CPU với paint đầu tiên trên iOS cold start.
  // Face model: khởi tạo lazy khi vào chấm công khuôn mặt (mobile_attendance / camera).
  WidgetsBinding.instance.addPostFrameCallback((_) {
    // ignore: discarded_futures
    FcmService.instance.initialize();
  });
}

