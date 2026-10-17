import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Định danh máy POS cho khóa đơn tạm đa thiết bị.
class PosDeviceIdentity {
  PosDeviceIdentity._();

  static const _idKey = 'pos_cashier_device_id';
  static const _nameKey = 'pos_cashier_device_name';
  static const _idSourceKey = 'pos_cashier_device_id_source';
  // Bump when the migration logic changes, to force one more re-detection
  // pass (id + name) on devices that already ran an older migration.
  static const _idSourceValue = 'uuid_v2';

  static String? _cachedId;
  static String? _cachedName;

  static Future<({String id, String name})> get({bool refreshName = false}) async {
    if (!refreshName &&
        _cachedId != null &&
        _cachedId!.isNotEmpty &&
        _cachedName != null &&
        _cachedName!.isNotEmpty &&
        !_isGenericName(_cachedName!)) {
      return (id: _cachedId!, name: _cachedName!);
    }
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_idKey)?.trim() ?? '';
    var name = prefs.getString(_nameKey)?.trim() ?? '';
    // Migration: any id previously derived from Build.ID (a non-unique OS
    // build tag, e.g. "S100") can collide across different physical devices
    // (seen between Sunmi and Landi terminals). Force-regenerate those.
    final idSource = prefs.getString(_idSourceKey)?.trim() ?? '';
    final migrating = id.isNotEmpty && idSource != _idSourceValue;
    if (migrating) {
      id = '';
    }
    if (id.isEmpty) {
      // Cài mới / cài lại app: lấy theo ANDROID_ID (giữ qua gỡ – cài lại) để máy chủ nhận ra
      // máy cũ — trước đây UUID ngẫu nhiên → cài lại là thành «máy mới», máy in nội bộ trên
      // máy chủ bị nhân bản mỗi lần cài lại.
      id = await _idFromHardware() ?? _newUuid();
      await prefs.setString(_idKey, id);
      await prefs.setString(_idSourceKey, _idSourceValue);
    }
    // Also force-refresh the name on migration: a stale/cloned id was often
    // paired with a stale/cloned name (e.g. a Landi device reporting itself
    // as "SUNMI T1-G"), so both must be re-detected together.
    if (name.isEmpty || refreshName || migrating || _isGenericName(name)) {
      name = await _detectDeviceName();
      await prefs.setString(_nameKey, name);
    }
    _cachedId = id;
    _cachedName = name;
    return (id: id, name: name);
  }

  static bool _isGenericName(String name) {
    final n = name.trim().toLowerCase();
    return n.isEmpty ||
        n == 'sbox pos' ||
        n == 'android pos' ||
        n == 'máy pos' ||
        n == 'may pos' ||
        n.startsWith('pos-') ||
        n == 'unknown';
  }

  static Future<Map<String, String>> lockBodyFields() async {
    final d = await get();
    return {'deviceId': d.id, 'deviceName': d.name};
  }

  /// UUID cố định suy ra từ ANDROID_ID (null nếu không đọc được).
  static Future<String?> _idFromHardware() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final k = (await const MethodChannel('sbox/offline_vault')
                  .invokeMethod<String>('deviceKey'))
              ?.trim() ??
          '';
      // Một số ROM trả ANDROID_ID mặc định giống nhau trên mọi máy — bỏ qua.
      if (k.length < 8 || k == '9774d56d682e549c') return null;
      // FNV-1a 32-bit × 4 hạt giống → 128 bit (không dùng hằng 64-bit: web không biên dịch được).
      String fnv(String s, int seed) {
        var h = 0x811c9dc5 ^ seed;
        for (final c in s.codeUnits) {
          h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
        }
        return h.toRadixString(16).padLeft(8, '0');
      }

      final h = [0x1f, 0x7a, 0x3c, 0x55].map((seed) => fnv('sbox-pos|$k', seed)).join();
      final b = h.split('');
      b[12] = '5'; // version
      b[16] = '89ab'[int.parse(b[16], radix: 16) & 3]; // variant
      final u = b.join();
      return '${u.substring(0, 8)}-${u.substring(8, 12)}-'
          '${u.substring(12, 16)}-${u.substring(16, 20)}-${u.substring(20, 32)}';
    } catch (_) {
      return null;
    }
  }

  static String _newUuid() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static Future<String> _detectDeviceName() async {
    try {
      final plugin = DeviceInfoPlugin();
      if (kIsWeb) {
        final web = await plugin.webBrowserInfo;
        return 'Web ${web.browserName.name}';
      }
      if (Platform.isAndroid) {
        final a = await plugin.androidInfo;
        final label = '${a.brand} ${a.model}'.trim();
        return label.isEmpty ? 'Android POS' : label;
      }
      if (Platform.isIOS) {
        final i = await plugin.iosInfo;
        return i.name.isNotEmpty ? i.name : 'iOS POS';
      }
      if (Platform.isWindows) return 'Windows POS';
    } catch (_) {}
    final r = Random().nextInt(9999).toString().padLeft(4, '0');
    return 'POS-$r';
  }
}
