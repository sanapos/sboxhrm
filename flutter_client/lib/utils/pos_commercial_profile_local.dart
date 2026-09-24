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

/// Bản trên máy vừa lưu mà server còn dữ liệu cũ thì giữ bản máy.
Map<String, dynamic> mergeCommercialProfile(
  Map<String, dynamic> remote,
  Map<String, dynamic> local,
) {
  String pick(String a, String b) =>
      (remote[a] ?? remote[b] ?? '').toString().trim();
  final localAt = DateTime.tryParse('${local['clientSavedAt'] ?? ''}');
  final remoteAt = DateTime.tryParse(
    '${remote['updatedAt'] ?? remote['UpdatedAt'] ?? ''}',
  );
  final localWins = localAt != null &&
      (remoteAt == null || !remoteAt.isAfter(localAt));
  if (!localWins) {
    if (pick('companyName', 'CompanyName').isNotEmpty) return remote;
    if ((local['companyName'] ?? '').toString().trim().isEmpty &&
        (local['logoPngBase64'] ?? '').toString().trim().isEmpty) {
      return remote;
    }
  }
  final out = <String, dynamic>{...remote};
  for (final e in local.entries) {
    if (e.key == 'clientSavedAt') continue;
    final v = e.value?.toString().trim() ?? '';
    if (v.isNotEmpty) out[e.key] = e.value;
  }
  if (localAt != null) out['clientSavedAt'] = local['clientSavedAt'];
  return out;
}
