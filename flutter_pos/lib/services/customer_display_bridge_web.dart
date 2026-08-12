import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Web: mở cửa sổ/tab phụ + BroadcastChannel đồng bộ.
class CustomerDisplayPlatformBridge {
  static web.Window? _popup;
  static web.BroadcastChannel? _channel;
  static final _controller = StreamController<String>.broadcast();

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

  /// Web: coi là có “màn phụ” nếu mở được popup/cửa sổ.
  static Future<bool> hasSecondaryDisplay() async => true;

  static Future<bool> openSecondary({
    String route = '/customer-display',
    String mode = 't1Native',
  }) async {
    // Window / web: luôn dùng popup trình duyệt.
    _ensureChannel();
    final base = web.window.location.href.split('#').first;
    final url = '$base#${route.startsWith('/') ? route : '/$route'}';
    try {
      _popup = web.window.open(
        url,
        'sbox_customer_display',
        'popup=yes,width=1280,height=800',
      );
      return _popup != null;
    } catch (_) {
      return false;
    }
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
        {'id': 0, 'name': 'Cửa sổ trình duyệt phụ', 'isPrimary': false},
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
