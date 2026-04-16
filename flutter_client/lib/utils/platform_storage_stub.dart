import 'package:shared_preferences/shared_preferences.dart';

// In-memory cache from SharedPreferences (loaded on first access).
SharedPreferences? _prefs;

Future<SharedPreferences> _getPrefs() async {
  _prefs ??= await SharedPreferences.getInstance();
  return _prefs!;
}

/// Read a value (synchronous on web, but we keep sync API using cached prefs).
/// On first call the cache may not be ready — callers should await [initPlatformStorage].
String? storageGet(String key) => _prefs?.getString(key);

/// Write a value.
void storageSet(String key, String value) {
  _prefs?.setString(key, value);
}

/// Remove a value.
void storageRemove(String key) {
  _prefs?.remove(key);
}

/// Call once at app startup (or before first storageGet) to warm the cache.
Future<void> initPlatformStorage() async {
  await _getPrefs();
}
