import 'dart:io' show Platform;

/// `flutter test` đặt biến môi trường FLUTTER_TEST cho tiến trình test.
final bool isRunningFlutterTest = Platform.environment.containsKey('FLUTTER_TEST');
