import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const _payloadPrefix = 'pos_sell_catalog_payload_';
const _maxPayloadBytes = 1572864; // ~1.5 MB

Future<String?> readCatalogJson(String storeId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('$_payloadPrefix$storeId');
  } catch (_) {
    return null;
  }
}

Future<void> writeCatalogJson(String storeId, String payload) async {
  if (utf8.encode(payload).length > _maxPayloadBytes) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_payloadPrefix$storeId', payload);
  } catch (_) {}
}

Future<void> deleteCatalogJson(String storeId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_payloadPrefix$storeId');
  } catch (_) {}
}
