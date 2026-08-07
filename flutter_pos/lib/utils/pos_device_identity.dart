import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Định danh máy POS cho khóa đơn tạm đa thiết bị.
class PosDeviceIdentity {
  PosDeviceIdentity._();

  static const _idKey = 'pos_cashier_device_id';
  static const _nameKey = 'pos_cashier_device_name';

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
    if (id.isEmpty) {
      id = await _detectDeviceId();
      await prefs.setString(_idKey, id);
    }
    if (name.isEmpty || refreshName || _isGenericName(name)) {
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

  static Future<String> _detectDeviceId() async {
    try {
      if (Platform.isAndroid) {
        final a = await DeviceInfoPlugin().androidInfo;
        final hw = a.id.trim();
        if (hw.isNotEmpty &&
            hw.toLowerCase() != 'unknown' &&
            hw.replaceAll('0', '').isNotEmpty) {
          return hw;
        }
      }
    } catch (_) {}
    return _newUuid();
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
