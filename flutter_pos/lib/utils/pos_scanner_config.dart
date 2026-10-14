import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Cài máy quét / máy kiểm kho cầm tay gửi mã qua broadcast (Intent).
///
/// App tự nghe sẵn Sunmi, Urovo, Newland, iData, Chainway, Seuic và action chuẩn
/// `vn.sana.sbox.SCAN` (extra `data`) — Zebra DataWedge, Honeywell, app đọc RFID… cài theo action
/// này, hoặc nhập action / extra riêng của máy ở đây.
class PosScannerConfig {
  PosScannerConfig._();

  static const standardAction = 'vn.sana.sbox.SCAN';
  static const standardExtra = 'data';

  static const _channel = MethodChannel('com.sboxhrm/scanner_config');
  static const _kAction = 'pos_scanner_custom_action';
  static const _kExtra = 'pos_scanner_custom_extra';

  /// Hãng / dòng máy đã nghe sẵn (hiện trong màn cài đặt).
  static const supportedDevices = <String>[
    'Sunmi (V2s, L2, T2s…)',
    'Urovo (DT40, i6310…)',
    'Newland (MT90, N7…)',
    'iData (K1, 70…)',
    'Chainway (C72, C66 — mã vạch)',
    'Seuic / Autoid',
    'Zebra / Honeywell / đầu đọc RFID: cài Intent action «$standardAction», extra «$standardExtra»',
    'Súng quét USB / Bluetooth (gõ phím + Enter): dùng ngay, không cần cài',
  ];

  static Future<({String action, String extra})> load() async {
    final p = await SharedPreferences.getInstance();
    return (action: p.getString(_kAction) ?? '', extra: p.getString(_kExtra) ?? '');
  }

  static Future<void> save({required String action, required String extra}) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kAction, action.trim());
    await p.setString(_kExtra, extra.trim());
    await apply();
  }

  /// Gửi action / extra riêng xuống bộ nghe broadcast (gọi lúc mở app và sau khi lưu).
  static Future<void> apply() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final c = await load();
    try {
      await _channel.invokeMethod('setCustom', {'action': c.action, 'extra': c.extra});
    } catch (_) {
      // Bản app cũ / nền tảng khác — bỏ qua.
    }
  }
}
