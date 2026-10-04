import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Mã chức năng trong link `/#/m/<Mã>` (vd `#/m/PosProducts`) — null nếu không có.
String? currentModuleDeepLink() {
  final h = web.window.location.hash;
  final m = RegExp(r'^#/?m/([A-Za-z0-9_]+)').firstMatch(h);
  if (m != null) return m.group(1);
  // index.html lưu sẵn khi mở trang (hash bị bộ định tuyến xóa trước khi app chạy).
  final saved = web.window.sessionStorage.getItem('sbox_module');
  if (saved != null && saved.isNotEmpty) {
    web.window.sessionStorage.removeItem('sbox_module');
    return saved;
  }
  return null;
}

/// Gọi [onModule] mỗi khi người dùng đổi hash `#/m/<Mã>` trên thanh địa chỉ (không tải lại trang).
void listenModuleDeepLink(void Function(String module) onModule) {
  web.window.addEventListener(
    'hashchange',
    ((web.Event _) {
      final code = currentModuleDeepLink();
      if (code != null) onModule(code);
    }).toJS,
  );
}
