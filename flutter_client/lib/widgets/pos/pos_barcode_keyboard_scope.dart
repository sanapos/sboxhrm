import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/pos_sunmi_scanner.dart';

/// Bắt input từ máy quét mã vạch (keyboard wedge + Sunmi broadcast).
///
/// Máy quét gõ nhanh chuỗi ký tự và kết thúc bằng Enter — widget này gom buffer
/// và gọi [onBarcode] mà không cần focus vào ô tìm kiếm trước.
/// Trên Sunmi V2s cũng nhận broadcast `ACTION_DATA_CODE_RECEIVED` (nhanh hơn camera).
class PosBarcodeKeyboardScope extends StatefulWidget {
  const PosBarcodeKeyboardScope({
    super.key,
    required this.child,
    required this.onBarcode,
    this.enabled = true,
    this.ignoreFocusNodes = const [],
  });

  final Widget child;
  final Future<void> Function(String code) onBarcode;
  final bool enabled;
  final List<FocusNode> ignoreFocusNodes;

  @override
  State<PosBarcodeKeyboardScope> createState() =>
      _PosBarcodeKeyboardScopeState();
}

class _PosBarcodeKeyboardScopeState extends State<PosBarcodeKeyboardScope> {
  final StringBuffer _buffer = StringBuffer();
  DateTime? _lastKeyAt;
  bool _handling = false;
  StreamSubscription<String>? _sunmiSub;
  String? _lastSunmiCode;
  DateTime? _lastSunmiAt;

  static const _maxGap = Duration(milliseconds: 90);
  static const _minCodeLength = 2;
  static const _sunmiDedupe = Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    if (!kIsWeb) {
      _sunmiSub = PosSunmiScanner.barcodes.listen(_onSunmiCode);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _sunmiSub?.cancel();
    super.dispose();
  }

  void _onSunmiCode(String code) {
    if (!widget.enabled || _handling) return;
    final now = DateTime.now();
    if (_lastSunmiCode == code &&
        _lastSunmiAt != null &&
        now.difference(_lastSunmiAt!) < _sunmiDedupe) {
      return;
    }
    _lastSunmiCode = code;
    _lastSunmiAt = now;
    _emit(code);
  }

  void _emit(String code) {
    final trimmed = code.trim();
    if (trimmed.length < _minCodeLength) return;
    _handling = true;
    HapticFeedback.lightImpact();
    widget.onBarcode(trimmed).whenComplete(() {
      if (mounted) _handling = false;
    });
  }

  bool _shouldCapture() {
    if (!widget.enabled || _handling) return false;
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return true;
    if (widget.ignoreFocusNodes.any((n) => n.hasFocus)) return false;
    final ctx = focus.context;
    if (ctx == null) return true;
    return ctx.findAncestorWidgetOfExactType<EditableText>() == null;
  }

  bool _onKey(KeyEvent event) {
    if (!_shouldCapture()) return false;
    if (event is! KeyDownEvent) return false;

    final now = DateTime.now();
    if (_lastKeyAt != null && now.difference(_lastKeyAt!) > _maxGap) {
      _buffer.clear();
    }
    _lastKeyAt = now;

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final code = _buffer.toString().trim();
      _buffer.clear();
      if (code.length >= _minCodeLength) {
        _emit(code);
      }
      return true;
    }

    final label = event.character;
    if (label == null || label.isEmpty) return false;
    if (label.codeUnitAt(0) < 32) return false;
    _buffer.write(label);
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
