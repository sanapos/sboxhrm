import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'app/app.dart';
import 'providers/auth_provider.dart';
import 'providers/permission_provider.dart';
import 'providers/theme_provider.dart';
import 'services/face_embedding_service_stub.dart'
    if (dart.library.io) 'services/face_embedding_service.dart';
import 'services/fcm_service_stub.dart'
    if (dart.library.io) 'services/fcm_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load Be Vietnam Pro vào CanvasKit font registry TRƯỚC runApp.
  // Đây là fix dứt điểm cho Vietnamese garbled text trong CanvasKit:
  // CanvasKit embedded fallback fonts có glyph mapping sai cho Vietnamese
  // Unicode range → phải đảm bảo Be Vietnam Pro được đăng ký trước
  // frame đầu tiên, không phụ thuộc vào pubspec.yaml font loading timing.
  await _loadBeVietnamProFonts();

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

  // Eagerly initialize the on-device face embedding model (MobileFaceNet via
  // TFLite). Without this the very first face-verification attempt uses the
  // weak HOG/LBP fallback which can false-positive — especially on iOS where
  // the model was historically assumed to be unavailable.
  // Fire-and-forget: any failure is logged; verification code will re-check.
  FaceEmbeddingService.initialize().then((_) {
    debugPrint(
        'FaceEmbeddingService init: ready=${FaceEmbeddingService.isReady}');
  }).catchError((e) {
    debugPrint('FaceEmbeddingService init failed: $e');
  });

  // Initialize Firebase Cloud Messaging (push notifications). Best-effort:
  // failures are swallowed so the app still launches without Firebase.
  // ignore: discarded_futures
  FcmService.instance.initialize();

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

/// Đăng ký Be Vietnam Pro vào CanvasKit font registry.
/// FontLoader.load() là cách duy nhất đảm bảo font có mặt trong
/// Skia/CanvasKit TRƯỚC khi paragraph builder chạy lần đầu.
Future<void> _loadBeVietnamProFonts() async {
  final loader = FontLoader('BeVietnamPro');
  loader.addFont(rootBundle.load('assets/fonts/BeVietnamPro-Regular.ttf'));
  loader.addFont(rootBundle.load('assets/fonts/BeVietnamPro-Medium.ttf'));
  loader.addFont(rootBundle.load('assets/fonts/BeVietnamPro-SemiBold.ttf'));
  loader.addFont(rootBundle.load('assets/fonts/BeVietnamPro-Bold.ttf'));
  loader.addFont(rootBundle.load('assets/fonts/BeVietnamPro-ExtraBold.ttf'));
  loader.addFont(rootBundle.load('assets/fonts/BeVietnamPro-Italic.ttf'));
  await loader.load();
}
