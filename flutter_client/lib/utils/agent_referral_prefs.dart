import 'package:shared_preferences/shared_preferences.dart';

/// Giữ mã đại lý từ link giới thiệu cho đến khi đăng ký cửa hàng thành công.
class AgentReferralPrefs {
  AgentReferralPrefs._();

  static const _key = 'sbox_pending_agent_code';

  static Future<void> save(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, normalized);
  }

  static Future<String?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_key)?.trim();
    if (code == null || code.isEmpty) return null;
    return code.toUpperCase();
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
