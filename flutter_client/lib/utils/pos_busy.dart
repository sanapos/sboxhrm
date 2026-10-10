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

  static const _defaultKey = 'pos-doc';

  static Future<T?> run<T>(
    BuildContext context,
    Future<T> Function() task, {
    String label = 'Đang mở…',
    String key = _defaultKey,
  }) async {
    if (_keys.contains(key)) return null;
    _keys.add(key);
    final overlay = Navigator.maybeOf(context, rootNavigator: true)?.overlay;
    final timer = Timer(const Duration(milliseconds: 120), () {
      if (overlay == null || !overlay.mounted || _entry != null) return;
      _label.value = label;
      _entry = OverlayEntry(builder: (_) => const _BusyLayer());
      overlay.insert(_entry!);
    });
    try {
      return await task();
    } finally {
      timer.cancel();
      _keys.remove(key);
      if (_keys.isEmpty) hideLayer();
    }
  }

  /// Gỡ lớp chờ (hộp thoại kết quả đã mở) — thao tác vẫn tính là đang chạy tới khi xong.
  static void hideLayer() {
    _entry?.remove();
    _entry = null;
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
