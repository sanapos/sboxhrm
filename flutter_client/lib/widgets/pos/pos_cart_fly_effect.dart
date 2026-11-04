import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'pos_product_image.dart';
import 'pos_theme.dart';

/// Hiệu ứng «món bay vào giỏ» ở màn bán hàng: chip ảnh món bay theo đường vòng từ chỗ vừa chạm
/// tới [PosCartFlyTarget], tới nơi thì đích nảy nhẹ.
///
/// Chỉ để trang trí: giỏ đã nhận món trước khi bay, không chặn chạm (thu ngân bấm nhanh liên tiếp).
class PosCartFlyTarget extends StatefulWidget {
  const PosCartFlyTarget({super.key, required this.child});

  final Widget child;

  @override
  State<PosCartFlyTarget> createState() => PosCartFlyTargetState();
}

class PosCartFlyTargetState extends State<PosCartFlyTarget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1, end: 1.35), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 1.35, end: 1), weight: 60),
  ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

  void bump() => _ctrl.forward(from: 0);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: widget.child);
}

/// Chip ảnh món đang bay: dùng lại ảnh đang hiện trên ô món; chưa có ảnh (hàng không ảnh, ô chưa
/// tải xong) thì hiện icon.
class PosCartFlyChip extends StatelessWidget {
  const PosCartFlyChip({super.key, required this.productId});

  static const double size = 46;
  static const Widget _icon =
      Icon(Icons.shopping_bag_outlined, size: 24, color: PosTheme.kiotBlue);

  final String productId;

  @override
  Widget build(BuildContext context) {
    final shown = PosProductImage.shownImageOf(productId);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: PosTheme.kiotBlue, width: 2),
        boxShadow: const [
          BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      alignment: Alignment.center,
      child: shown == null
          ? _icon
          : ClipOval(
              child: Image(
                image: shown,
                width: size - 4,
                height: size - 4,
                fit: BoxFit.cover,
                frameBuilder: (_, child, frame, __) => frame == null ? _icon : child,
                errorBuilder: (_, __, ___) => _icon,
              ),
            ),
    );
  }
}

/// Số chip bay cùng lúc tối đa — bấm rất nhanh trên máy yếu thì bỏ bớt, không dồn khung hình.
const int _kMaxFlying = 4;
int _flying = 0;

/// Cho chip [chip] bay từ [from] (tọa độ toàn màn hình) tới [target]. Đích chưa vẽ, hệ thống tắt
/// hiệu ứng hoặc đang bay quá nhiều → bỏ qua, món vẫn đã vào giỏ.
void posFlyToCart({
  required BuildContext context,
  required Offset from,
  required GlobalKey<PosCartFlyTargetState> target,
  required Widget chip,
}) {
  if (_flying >= _kMaxFlying) return;
  if (WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations) {
    return;
  }
  final targetBox = target.currentContext?.findRenderObject();
  if (targetBox is! RenderBox || !targetBox.attached || !targetBox.hasSize) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final overlayBox = overlay?.context.findRenderObject();
  if (overlay == null || overlayBox is! RenderBox) return;

  final start = overlayBox.globalToLocal(from);
  final end = overlayBox.globalToLocal(
    targetBox.localToGlobal(targetBox.size.center(Offset.zero)),
  );

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _CartFlight(
      start: start,
      end: end,
      chip: chip,
      onDone: () {
        entry.remove();
        target.currentState?.bump();
      },
    ),
  );
  _flying++;
  overlay.insert(entry);
}

class _CartFlight extends StatefulWidget {
  const _CartFlight({
    required this.start,
    required this.end,
    required this.chip,
    required this.onDone,
  });

  final Offset start;
  final Offset end;
  final Widget chip;
  final VoidCallback onDone;

  @override
  State<_CartFlight> createState() => _CartFlightState();
}

class _CartFlightState extends State<_CartFlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );

  /// Điểm uốn: giữa đường, nhấc lên trên điểm cao hơn của hai đầu (không quá mép trên) — chip đi theo đường vòng.
  late final Offset _control = () {
    final lift = ((widget.end - widget.start).distance * 0.25).clamp(40.0, 140.0);
    return Offset(
      (widget.start.dx + widget.end.dx) / 2,
      math.max(0.0, math.min(widget.start.dy, widget.end.dy) - lift),
    );
  }();

  /// Bật lên nhanh ở đầu rồi thu nhỏ dần tới đích.
  static final _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 0.6, end: 1.1).chain(CurveTween(curve: Curves.easeOut)),
      weight: 18,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.1, end: 0.4).chain(CurveTween(curve: Curves.easeIn)),
      weight: 82,
    ),
  ]);

  @override
  void initState() {
    super.initState();
    _ctrl.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    // Đếm ở đây, không ở onDone: chip có thể bị gỡ giữa đường (đổi cây màn hình) — đếm sót thì
    // sau vài lần hiệu ứng tắt luôn.
    _flying--;
    _ctrl.dispose();
    super.dispose();
  }

  Offset _positionAt(double t) {
    final u = 1 - t;
    return widget.start * (u * u) + _control * (2 * u * t) + widget.end * (t * t);
  }

  @override
  Widget build(BuildContext context) {
    final chip = RepaintBoundary(child: widget.chip);
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topLeft,
        child: AnimatedBuilder(
          animation: _ctrl,
          child: chip,
          builder: (_, child) {
            final c = _ctrl.value;
            final p = _positionAt(Curves.easeInCubic.transform(c));
            const half = PosCartFlyChip.size / 2;
            return Transform.translate(
              offset: Offset(p.dx - half, p.dy - half),
              child: Transform.scale(
                scale: _scale.transform(c),
                child: Opacity(
                  opacity: c < 0.85 ? 1 : ((1 - c) / 0.15).clamp(0.0, 1.0),
                  child: child,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
