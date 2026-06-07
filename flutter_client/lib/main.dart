import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import 'utils/vietnamese_font.dart';
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
      // Chỉ log, không hiển thị sọc vàng đen
      debugPrint('⚠️ Overflow: ${details.summary}');
      return;
    }
    originalOnError?.call(details);
  };

  // Tránh màn trắng trống khi một widget build lỗi (đặc biệt release iOS).
  ErrorWidget.builder = (FlutterErrorDetails details) {
    if (kDebugMode) {
      return ErrorWidget(details.exception);
    }
    return Material(
      color: ThemeProvider.primaryColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Đã xảy ra lỗi hiển thị.\nVui lòng đóng và mở lại ứng dụng.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 15,
              height: 1.45,
            ),
          ),
        ),
      ),
    );
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

