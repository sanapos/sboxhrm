import 'dart:math' as math;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;

/// Stable device identifier for mobile attendance registration / punch.
class MobileDeviceId {
  MobileDeviceId._();

  static const _prefsKey = 'sbox_persistent_device_id';

  static Future<String> resolve() async {
    String rawId = '';
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (kIsWeb) {
        final webInfo = await deviceInfo.webBrowserInfo;
        rawId =
            'web_${webInfo.userAgent?.hashCode ?? DateTime.now().millisecondsSinceEpoch}';
      } else if (Platform.isAndroid) {
        rawId = (await deviceInfo.androidInfo).id;
      } else if (Platform.isIOS) {
        rawId = (await deviceInfo.iosInfo).identifierForVendor ?? '';
      }
    } catch (e) {
      debugPrint('MobileDeviceId platform read error: $e');
    }
    return _persist(rawId);
  }

  static Future<String> _persist(String rawId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_prefsKey);
      if (cached != null && cached.isNotEmpty) return cached;
      final rand = math.Random.secure();
      final suffix = List<int>.generate(6, (_) => rand.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final generated =
          rawId.isNotEmpty ? '${rawId}_$suffix' : 'dev_$suffix';
      await prefs.setString(_prefsKey, generated);
      return generated;
    } catch (e) {
      debugPrint('MobileDeviceId persist error: $e');
      return rawId.isNotEmpty
          ? rawId
          : 'dev_${DateTime.now().millisecondsSinceEpoch}';
    }
  }
}
