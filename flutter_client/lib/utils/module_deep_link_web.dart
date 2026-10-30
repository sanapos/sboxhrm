import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Đổi hash `#/m/<Mã>` → engine báo route mới, MaterialApp gọi pushNamed('/m/…') không có
/// route → ném lỗi (Null check trong _onUnknownRoute). Đăng ký trước runApp để chặn trước
/// WidgetsApp; [listenModuleDeepLink] lo việc mở chức năng.
void installModuleDeepLinkRouteGuard() {
  WidgetsBinding.instance.addObserver(_ModuleDeepLinkRouteGuard());
}

class _ModuleDeepLinkRouteGuard with WidgetsBindingObserver {
  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async =>
      routeInformation.uri.path.startsWith('/m/');
}

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
