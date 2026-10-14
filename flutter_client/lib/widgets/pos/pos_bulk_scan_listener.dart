import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/pos_sunmi_scanner.dart';

/// Nghe mã từ máy quét / máy kiểm kho khi quét hàng loạt (kiểm kho):
/// súng quét gõ phím (USB / Bluetooth, mỗi mã kết thúc bằng Enter) và máy cầm tay gửi broadcast
/// (Sunmi, Urovo, Newland, Zebra DataWedge, đầu đọc RFID…).
///
/// Khác [PosBarcodeKeyboardScope] (màn bán): không bỏ mã khi mã trước còn đang xử lý, không gộp mã
/// trùng — quét 3 lần cùng mã = 3 cái. Bên gọi tự gom / gửi theo lô.
class PosBulkScanListener extends StatefulWidget {
  const PosBulkScanListener({
    super.key,
    required this.child,
    required this.onCode,
    this.enabled = true,
  });

  final Widget child;
  final ValueChanged<String> onCode;
  final bool enabled;

  @override
  State<PosBulkScanListener> createState() => _PosBulkScanListenerState();
}

class _PosBulkScanListenerState extends State<PosBulkScanListener> {
  final _buffer = StringBuffer();
  DateTime? _lastKeyAt;
  StreamSubscription<String>? _sub;

  /// Súng quét gõ rất nhanh (< 50ms / phím); người gõ tay chậm hơn nhiều.
  static const _maxGap = Duration(milliseconds: 90);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    if (!kIsWeb) _sub = PosSunmiScanner.barcodes.listen(_emit);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _sub?.cancel();
    super.dispose();
  }

  void _emit(String code) {
    final c = code.trim();
    if (!widget.enabled || c.length < 2) return;
    widget.onCode(c);
  }

  /// Đang gõ vào ô chữ (ghi chú, SL…) thì để phím vào ô đó.
  bool _typingInField() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    return ctx != null && ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _onKey(KeyEvent event) {
    if (!widget.enabled || event is! KeyDownEvent || _typingInField()) return false;
    final now = DateTime.now();
    if (_lastKeyAt != null && now.difference(_lastKeyAt!) > _maxGap) _buffer.clear();
    _lastKeyAt = now;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab) {
      final code = _buffer.toString();
      _buffer.clear();
      _emit(code);
      return true;
    }
    final ch = event.character;
    if (ch == null || ch.isEmpty || ch.codeUnitAt(0) < 32) return false;
    _buffer.write(ch);
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
