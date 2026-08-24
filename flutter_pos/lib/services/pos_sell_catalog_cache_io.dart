import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<String> _pathFor(String storeId) async {
  final dir = await getApplicationSupportDirectory();
  final safe = storeId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  return '${dir.path}/pos_sell_catalog_$safe.json';
}

Future<String?> readCatalogJson(String storeId) async {
  final file = File(await _pathFor(storeId));
  if (!await file.exists()) return null;
  return file.readAsString();
}

Future<void> writeCatalogJson(String storeId, String payload) async {
  final file = File(await _pathFor(storeId));
  await file.parent.create(recursive: true);
  await file.writeAsString(payload);
}

Future<void> deleteCatalogJson(String storeId) async {
  final file = File(await _pathFor(storeId));
  if (await file.exists()) {
    await file.delete();
  }
}
