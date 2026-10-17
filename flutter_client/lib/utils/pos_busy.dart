import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_tr.dart';

/// Chặn bấm lặp + phản hồi ngay cho thao tác chậm (mở / in / xuất / lập chứng từ):
/// - Đang chạy cùng [key] → lần bấm sau bị bỏ qua (không mở 2 lần, không tạo trùng).
/// - Sau 120ms chưa xong → phủ lớp mờ có vòng quay + chữ («Đang mở hợp đồng…») chặn mọi thao tác.
/// - Hộp xem / in mở ra thì gọi [hideLayer] để lớp chờ không nằm sau hộp thoại.
class PosBusy {
  PosBusy._();

  static final Set<String> _keys = {};
  static OverlayEntry? _entry;
  static final ValueNotifier<String> _label = ValueNotifier('');

  static bool isBusy([String key = _defaultKey]) => _keys.contains(key);

  static OverlayState? _overlay;
  static String _curLabel = '';
  static int _suspended = 0;
  // hideLayer() đã được gọi trong lần chạy này → không hiện lại lớp chờ (kể cả khi hẹn giờ 120ms chưa kịp bắn).
  static bool _hiddenByCaller = false;

  static void _showLayer() {
    final overlay = _overlay;
    if (_suspended > 0 || _hiddenByCaller || _keys.isEmpty || overlay == null || !overlay.mounted || _entry != null) return;
    _label.value = _curLabel;
    _entry = OverlayEntry(builder: (_) => const _BusyLayer());
    overlay.insert(_entry!);
  }

  /// Chạy [fn] (hộp thoại hỏi người dùng, bảng chia sẻ / in hệ thống…) mà KHÔNG có lớp chờ chặn phía trên.
  /// Trước đây lớp «Đang dựng…» hiện đè lên chính hộp hỏi («Có đóng dấu không?») → người dùng không bấm được,
  /// màn hình quay mãi. Xong thì lớp chờ hiện lại nếu thao tác ngoài vẫn đang chạy.
  static Future<T> suspend<T>(Future<T> Function() fn) async {
    _suspended++;
    hideLayer();
    try {
      return await fn();
    } finally {
      _suspended--;
      _showLayer();
    }
  }

  static const _defaultKey = 'pos-doc';

  static Future<T?> run<T>(
    BuildContext context,
    Future<T> Function() task, {
    String label = 'Đang mở…',
    String key = _defaultKey,
  }) async {
    if (_keys.contains(key)) return null;
    _keys.add(key);
    _overlay = Navigator.maybeOf(context, rootNavigator: true)?.overlay;
    _curLabel = label;
    final timer = Timer(const Duration(milliseconds: 120), _showLayer);
    try {
      return await task();
    } finally {
      timer.cancel();
      _keys.remove(key);
      if (_keys.isEmpty) {
        hideLayer();
        _hiddenByCaller = false;
      }
    }
  }

  /// Gỡ lớp chờ (hộp thoại kết quả đã mở) — thao tác vẫn tính là đang chạy tới khi xong.
  static void hideLayer() {
    _entry?.remove();
    _entry = null;
    if (_keys.isNotEmpty && _suspended == 0) _hiddenByCaller = true;
  }
}

class _BusyLayer extends StatelessWidget {
  const _BusyLayer();

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      const ModalBarrier(dismissible: false, color: Color(0x33000000)),
      Center(
        child: Material(
          color: Colors.white,
          elevation: 6,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(width: 14),
              ValueListenableBuilder<String>(
                valueListenable: PosBusy._label,
                builder: (_, v, __) => Text(tr(v), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}
