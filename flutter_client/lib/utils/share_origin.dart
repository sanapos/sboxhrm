import 'dart:ui';

/// Điểm neo hộp chia sẻ (iPad / iPhone ném PlatformException nếu thiếu hoặc Rect rỗng).
Rect shareOriginRect() {
  final views = PlatformDispatcher.instance.views;
  if (views.isEmpty) return const Rect.fromLTWH(0, 0, 120, 48);
  final size = views.first.physicalSize / views.first.devicePixelRatio;
  final width = size.width > 8 ? size.width : 320.0;
  final height = size.height > 8 ? size.height : 640.0;
  return Rect.fromCenter(center: Offset(width / 2, height / 3), width: 48, height: 48);
}
