import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;

/// Web: mở cửa sổ khách trên **màn hình thứ 2** (Multi-Screen Window Placement).
/// Không mở tab trên màn thu ngân.
class CustomerDisplayPlatformBridge {
  static web.Window? _popup;
  static web.BroadcastChannel? _channel;
  static final _controller = StreamController<String>.broadcast();
  static String lastOpenReason = '';
  static bool _helperReady = false;

  static const _helperJs = r'''
window.sboxHasSecondScreen = async function () {
  try {
    if (typeof window.getScreenDetails !== 'function') return false;
    if (navigator.permissions && navigator.permissions.query) {
      try {
        const st = await navigator.permissions.query({ name: 'window-management' });
        if (st.state === 'denied' || st.state === 'prompt') return false;
      } catch (e) {}
    }
    const details = await window.getScreenDetails();
    return !!(details && details.screens && details.screens.length > 1);
  } catch (e) { return false; }
};
window.sboxOpenCustomerDisplayOnSecondScreen = async function (url) {
  try {
    if (typeof window.getScreenDetails !== 'function') return 'no-api';
    const details = await window.getScreenDetails();
    const screens = details && details.screens ? Array.from(details.screens) : [];
    const cur = details.currentScreen;
    const other = screens.find(function (s) {
      if (!cur) return true;
      return s.left !== cur.left || s.top !== cur.top ||
        s.width !== cur.width || s.height !== cur.height;
    });
    if (!other) return 'no-second-screen';
    const left = other.availLeft ?? other.left ?? 0;
    const top = other.availTop ?? other.top ?? 0;
    const w = other.availWidth ?? other.width ?? 1280;
    const h = other.availHeight ?? other.height ?? 800;
    const feat = 'popup=yes,left=' + left + ',top=' + top +
      ',width=' + w + ',height=' + h;
    const win = window.open(url, 'sbox_customer_display', feat);
    if (!win) return 'popup-blocked';
    try {
      win.moveTo(left, top);
      win.resizeTo(w, h);
      win.focus();
    } catch (e) {}
    return 'ok';
  } catch (e) {
    const name = (e && e.name) ? String(e.name) : '';
    if (name === 'NotAllowedError') return 'permission-denied';
    return 'error';
  }
};
''';

  static void _ensureChannel() {
    if (_channel != null) return;
    try {
      _channel = web.BroadcastChannel('sbox-customer-display');
      _channel!.onmessage = ((web.MessageEvent event) {
        final data = event.data;
        if (data != null) {
          _controller.add(data.toString());
        }
      }).toJS;
    } catch (_) {}
  }

  static void _installHelper() {
    if (_helperReady) return;
    try {
      if (web.window.hasProperty('sboxOpenCustomerDisplayOnSecondScreen'.toJS).toDart) {
        _helperReady = true;
        return;
      }
    } catch (_) {}
    try {
      final script = web.HTMLScriptElement()
        ..type = 'text/javascript'
        ..text = _helperJs;
      web.document.head?.append(script);
      _helperReady = true;
    } catch (_) {}
  }

  static Future<Object?> _awaitJs(String name, [String? arg]) async {
    _installHelper();
    try {
      final promise = arg == null
          ? web.window.callMethod(name.toJS) as JSPromise
          : web.window.callMethod(name.toJS, arg.toJS) as JSPromise;
      final raw = await promise.toDart;
      return raw.dartify();
    } catch (_) {
      return null;
    }
  }

  static String _fallbackUrl(String route) {
    try {
      final origin = web.window.location.origin;
      final path = route.startsWith('/') ? route : '/$route';
      return '$origin$path';
    } catch (_) {
      return route;
    }
  }

  /// Chỉ true khi Chrome đã cấp quyền và máy có ≥2 màn (không prompt lúc bootstrap).
  static Future<bool> hasSecondaryDisplay() async {
    final v = await _awaitJs('sboxHasSecondScreen');
    return v == true;
  }

  static Future<bool> openSecondary({
    String route = '/customer-display',
    String? url,
  }) async {
    _ensureChannel();
    final target = (url != null && url.trim().isNotEmpty)
        ? url.trim()
        : _fallbackUrl(route);
    final reason =
        (await _awaitJs('sboxOpenCustomerDisplayOnSecondScreen', target))
            ?.toString() ??
        'no-api';
    lastOpenReason = reason;
    return reason == 'ok';
  }

  static Future<bool> closeSecondary() async {
    try {
      _popup?.close();
      _popup = null;
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> listDisplays() async => const [
        {'id': 0, 'name': 'Màn hình thứ 2 (trình duyệt)', 'isPrimary': false},
      ];

  static Future<void> publishNative(String json) async {
    _ensureChannel();
    try {
      _channel?.postMessage(json.toJS);
      web.window.localStorage.setItem('sbox_customer_display_state', json);
    } catch (_) {}
  }

  static Future<String?> readNative() async {
    try {
      return web.window.localStorage.getItem('sbox_customer_display_state');
    } catch (_) {
      return null;
    }
  }

  static Stream<String>? nativeStateStream() {
    _ensureChannel();
    return _controller.stream;
  }
}
