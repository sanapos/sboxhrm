import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const _key = 'pos_commercial_profile_json';

Future<Map<String, dynamic>> loadLocalCommercialProfile() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_key);
  if (raw == null || raw.isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } catch (_) {}
  return {};
}

Future<void> saveLocalCommercialProfile(Map<String, dynamic> profile) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_key, jsonEncode(profile));
}

/// API trống (chưa lưu được trên server) thì giữ bản vừa lưu trên máy.
Map<String, dynamic> mergeCommercialProfile(
  Map<String, dynamic> remote,
  Map<String, dynamic> local,
) {
  String pick(String a, String b) =>
      (remote[a] ?? remote[b] ?? '').toString().trim();
  if (pick('companyName', 'CompanyName').isNotEmpty) return remote;
  if ((local['companyName'] ?? '').toString().trim().isEmpty &&
      (local['logoPngBase64'] ?? '').toString().trim().isEmpty) {
    return remote;
  }
  return {...remote, ...local};
}
