import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'pos_web_ime.dart';

export 'pos_web_ime.dart';

/// Padding đáy khi IME mở — [maxFraction] trần theo chiều cao màn.
/// Web: 0 — viewport + OSK đã chiếm chỗ; pad thêm sẽ đẩy cả màn lên và che dữ liệu.
double posImeBottomPad(BuildContext context, {double maxFraction = 0.55}) {
  if (kIsWeb) return 0;
  final mq = MediaQuery.of(context);
  final raw = mq.viewInsets.bottom;
  if (raw <= 0) return 0;
  final cap = mq.size.height * maxFraction;
  return math.min(raw, cap);
}

/// Pad đáy theo IME (có animation) — giữ ô ghi chú/tìm kiếm phía trên bàn phím.
/// Web cảm ứng: không pad cả scaffold (OSK overlay + [PosImeAwareFocus]).
class PosImeAvoidingPadding extends StatelessWidget {
  const PosImeAvoidingPadding({
    super.key,
    required this.child,
    this.maxFraction = 0.55,
    this.extraGap = 8,
  });

  final Widget child;
  final double maxFraction;
  final double extraGap;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return child;
    final ime = posImeBottomPad(context, maxFraction: maxFraction);
    final pad = ime > 0 ? ime + extraGap : 0.0;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: pad),
      child: child,
    );
  }
}

/// Gỡ inset IME khỏi MediaQuery của dialog — tránh form co mất.
Widget wrapPosFormDialog(BuildContext context, Widget dialog) {
  return MediaQuery.removeViewInsets(
    context: context,
    removeBottom: true,
    child: dialog,
  );
}

/// Con trỏ vừa rồi là cảm ứng — dùng để mở IME trên Flutter web (Windows/tablet).
bool posLastPointerWasTouch = false;

void posShowSoftKeyboard() {
  SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  posFocusWebEditingElement();
}

/// Gọi từ [TextField.onTap] — web cảm ứng không tự mở bàn phím khi chỉ requestFocus.
void posShowSoftKeyboardOnFieldTap() {
  if (!posLastPointerWasTouch && !posWebHasTouchPoints()) return;
  posArmWebImeForGesture();
  posShowSoftKeyboard();
}

bool _boxContainsGlobal(RenderBox box, Offset global, {double inflate = 16}) {
  if (!box.hasSize || !box.attached) return false;
  final local = box.globalToLocal(global);
  return box.paintBounds.inflate(inflate).contains(local);
}

/// Ô chữ hoặc icon prefix/suffix cùng hàng (nút tìm kiếm).
bool posHitWantsSoftKeyboard(Offset global) {
  var found = false;
  void visit(RenderObject ro) {
    if (found) return;
    if (ro is RenderEditable && !ro.readOnly && ro.attached) {
      RenderObject? p = ro;
      for (var i = 0; i < 12 && p != null; i++) {
        if (p is RenderBox && _boxContainsGlobal(p, global)) {
          found = true;
          return;
        }
        p = p.parent;
      }
    }
    ro.visitChildren(visit);
  }

  for (final view in RendererBinding.instance.renderViews) {
    visit(view);
    if (found) break;
  }
  return found;
}

bool _posPointerLooksLikeTouch(PointerEvent e) {
  if (e.kind == PointerDeviceKind.touch ||
      e.kind == PointerDeviceKind.stylus ||
      e.kind == PointerDeviceKind.invertedStylus) {
    return true;
  }
  // Chrome/Windows tablet: cảm ứng đôi khi thành mouse — chỉ tin khi có radius/size.
  // Không dùng maxTouchPoints: laptop có màn cảm ứng sẽ coi mọi chuột là touch
  // và mở bàn phím liên tục khi bấm card / nút.
  if (e.kind == PointerDeviceKind.mouse &&
      (e.radiusMajor > 0 || e.size > 0)) {
    return true;
  }
  return false;
}

EditableText? _editableForFocus(FocusNode? node) {
  final ctx = node?.context;
  if (ctx == null) return null;
  final w = ctx.widget;
  if (w is EditableText) return w;
  return ctx.findAncestorStateOfType<EditableTextState>()?.widget;
}

bool posFocusWantsSoftKeyboard(FocusNode? node) {
  final w = _editableForFocus(node);
  if (w == null) return false;
  if (w.readOnly) return false;
  if (w.keyboardType == TextInputType.none) return false;
  return true;
}

/// Bọc app: chạm ô chữ trên cảm ứng / web → mở bàn phím hệ thống.
class PosTouchImeHost extends StatefulWidget {
  const PosTouchImeHost({super.key, required this.child});

  final Widget child;

  @override
  State<PosTouchImeHost> createState() => _PosTouchImeHostState();
}

class _PosTouchImeHostState extends State<PosTouchImeHost> {
  FocusNode? _last;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocus);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    final node = FocusManager.instance.primaryFocus;
    if (identical(node, _last)) return;
    _last = node;
    if (!posLastPointerWasTouch) return;
    if (!posFocusWantsSoftKeyboard(node)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!posLastPointerWasTouch) return;
      if (!posFocusWantsSoftKeyboard(FocusManager.instance.primaryFocus)) {
        return;
      }
      posShowSoftKeyboard();
    });
  }

  void _onPointerDown(PointerDownEvent e) {
    posLastPointerWasTouch = _posPointerLooksLikeTouch(e);
    final onField = posHitWantsSoftKeyboard(e.position);
    if (!onField) {
      if (posLastPointerWasTouch) {
        hidePosSoftKeyboard(alsoAfterMs: 0);
      } else {
        FocusManager.instance.primaryFocus?.unfocus();
      }
      return;
    }
    if (!posLastPointerWasTouch) return;
    // Phải focus input HTML ngay trong cử chỉ — post-frame thì Chrome không mở OSK.
    posArmWebImeForGesture();
    posShowSoftKeyboard();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!posLastPointerWasTouch) return;
      _showIfFocusedEditable(hit: e.position, requireHit: true);
    });
  }

  void _showIfFocusedEditable({
    required Offset hit,
    required bool requireHit,
  }) {
    final node = FocusManager.instance.primaryFocus;
    if (!posFocusWantsSoftKeyboard(node)) return;
    if (requireHit) {
      final state =
          node!.context?.findAncestorStateOfType<EditableTextState>();
      final box = (state?.context ?? node.context)?.findRenderObject()
          as RenderBox?;
      if (box != null && box.hasSize && box.attached) {
        final local = box.globalToLocal(hit);
        if (!box.paintBounds.inflate(24).contains(local)) return;
      }
    }
    posShowSoftKeyboard();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerUp: (e) {
        if (!posLastPointerWasTouch) return;
        _showIfFocusedEditable(hit: e.position, requireHit: true);
      },
      child: widget.child,
    );
  }
}

/// Bọc ô nhập có danh sách gợi ý thả xuống (tìm hàng, tìm khách…): khi bàn phím bật,
/// [PosKeyboardLift] chừa thêm [below] px dưới ô để danh sách hiện đủ phía trên bàn phím.
class PosImeReserve extends InheritedWidget {
  const PosImeReserve({super.key, required this.below, required super.child});

  final double below;

  @override
  bool updateShouldNotify(PosImeReserve oldWidget) => oldWidget.below != below;
}

/// Đẩy cả app lên khi bàn phím ảo che ô đang gõ (giống adjustPan nhưng tự tính trong Flutter).
///
/// Màn bán hàng cố ý không co theo bàn phím (`resizeToAvoidBottomInset: false`), app còn giới hạn
/// inset ~⅓ màn, dialog dùng [wrapPosFormDialog] bỏ inset → ô ghi chú / tiền khách đưa ở đáy bị
/// bàn phím Sunmi (~45% màn) che, gõ không thấy chữ. Lớp này đo vị trí ô đang focus SAU khi
/// layout; còn bị che thì dịch toàn bộ giao diện lên vừa đủ. Màn đã tự co / tự cuộn → không dịch.
class PosKeyboardLift extends StatefulWidget {
  const PosKeyboardLift({super.key, required this.child, this.gap = 12});

  final Widget child;
  /// Khoảng hở giữa đáy ô nhập và mép bàn phím.
  final double gap;

  @override
  State<PosKeyboardLift> createState() => _PosKeyboardLiftState();
}

class _PosKeyboardLiftState extends State<PosKeyboardLift> with WidgetsBindingObserver {
  /// Khoảng dịch đích.
  double _dy = 0;
  /// Khoảng đang dịch thật trên màn (đang chạy hiệu ứng thì khác [_dy]).
  double _applied = 0;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_schedule);
    // Web: bàn phím ảo của trình duyệt đè lên trang, không có viewInsets → theo dõi riêng.
    posStartWebKeyboardWatch();
    posWebKeyboardInset.addListener(_schedule);
  }

  @override
  void dispose() {
    posWebKeyboardInset.removeListener(_schedule);
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_schedule);
    super.dispose();
  }

  @override
  void didChangeMetrics() => _schedule();

  /// Đo lại sau frame hiện tại và sau khi bàn phím / cuộn tự động chạy xong.
  void _schedule() {
    final seq = ++_seq;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (seq == _seq) _measure();
    });
    for (final ms in const [180, 420]) {
      Future<void>.delayed(Duration(milliseconds: ms), () {
        if (seq == _seq) _measure();
      });
    }
  }

  void _measure() {
    if (!mounted) return;
    final view = View.maybeOf(context);
    if (view == null) return;
    final raw = MediaQueryData.fromView(view);
    final inset = kIsWeb ? posWebKeyboardInset.value : raw.viewInsets.bottom;
    var next = 0.0;
    final node = FocusManager.instance.primaryFocus;
    if (inset > 0 && posFocusWantsSoftKeyboard(node) && node!.context != null) {
      final state = node.context!.findAncestorStateOfType<EditableTextState>();
      final box = (state?.context ?? node.context)!.findRenderObject();
      if (box is RenderBox && box.attached && box.hasSize) {
        // Toạ độ đã gồm phần đang dịch thật → cộng lại để có vị trí gốc (không dùng [_dy]:
        // giữa hiệu ứng, cộng đích sẽ tưởng ô thấp hơn thật rồi đẩy tới kịch trần).
        final top = box.localToGlobal(Offset.zero).dy + _applied;
        final reserve =
            node.context!.getInheritedWidgetOfExactType<PosImeReserve>()?.below ?? 0;
        final bottom = top + box.size.height + reserve;
        final visibleBottom = raw.size.height - inset - widget.gap;
        if (bottom > visibleBottom) {
          next = math.min(bottom - visibleBottom, inset);
          // Không đẩy mép trên ô ra khỏi màn (ô nhiều dòng cao).
          next = math.min(next, math.max(0.0, top - raw.padding.top - 8));
        }
      }
    }
    if ((next - _dy).abs() > 1) setState(() => _dy = next);
  }

  @override
  Widget build(BuildContext context) {
    // Màn tự cuộn ô vào tầm nhìn (ensureVisible) sau khi bàn phím bật — đo lại khi cuộn xong,
    // không thì vừa cuộn vừa dịch cộng dồn, ô trượt khỏi đỉnh màn.
    return NotificationListener<ScrollEndNotification>(
      onNotification: (_) {
        if (_dy > 0 || (kIsWeb ? posWebKeyboardInset.value : MediaQuery.viewInsetsOf(context).bottom) > 0) _schedule();
        return false;
      },
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: _dy),
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        builder: (_, v, child) {
          _applied = v.abs() < 0.5 ? 0 : v;
          return _applied == 0 ? child! : Transform.translate(offset: Offset(0, -v), child: child);
        },
        child: widget.child,
      ),
    );
  }
}

void hidePosSoftKeyboard({int alsoAfterMs = 320}) {
  void run() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
  }

  run();
  WidgetsBinding.instance.addPostFrameCallback((_) => run());
  if (alsoAfterMs > 0) {
    Future<void>.delayed(Duration(milliseconds: alsoAfterMs), run);
  }
}

/// Cuộn [context] vào vùng nhìn thấy phía trên IME (gọi khi focus TextField).
void posScrollIntoViewAboveIme(
  BuildContext context, {
  double alignment = 0.12,
  Duration duration = const Duration(milliseconds: 200),
}) {
  void run() {
    if (!context.mounted) return;
    Scrollable.ensureVisible(
      context,
      alignment: alignment,
      duration: duration,
      curve: Curves.easeOut,
    );
  }

  WidgetsBinding.instance.addPostFrameCallback((_) => run());
  // IME animate ~250ms — cuộn lại lần 2 khi chiều cao bàn phím ổn định.
  Future<void>.delayed(const Duration(milliseconds: 280), run);
}

/// Bọc field chữ: focus → cuộn lên trên IME.
class PosImeAwareFocus extends StatelessWidget {
  const PosImeAwareFocus({
    super.key,
    required this.child,
    this.alignment = 0.12,
  });

  final Widget child;
  final double alignment;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      onFocusChange: (has) {
        if (has) {
          posScrollIntoViewAboveIme(context, alignment: alignment);
          if (posLastPointerWasTouch) posShowSoftKeyboard();
        }
      },
      child: child,
    );
  }
}
