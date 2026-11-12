import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../config/sbox_app_variant.dart';

/// Bản Windows đổi tên sản phẩm «SBOX HRM» → «SBOX» nên thư mục dữ liệu chuyển từ
/// %APPDATA%\SBOX\SBOX HRM sang %APPDATA%\SBOX\SBOX. Lần đầu mở bản mới: chép dữ liệu cũ
/// (đăng nhập, máy chủ, đơn POS chờ đồng bộ…) sang để máy đang dùng không mất gì.
Future<void> migrateWindowsDataDir() async {
  if (kIsWeb || !Platform.isWindows || !SboxAppVariant.genericBrand) return;
  try {
    final current = await getApplicationSupportDirectory();
    final old = Directory('${current.parent.path}${Platform.pathSeparator}SBOX HRM');
    if (!await old.exists()) return;
    final marker = File('${current.path}${Platform.pathSeparator}shared_preferences.json');
    if (await marker.exists()) return;
    await _copyDir(old, current);
  } catch (e) {
    debugPrint('migrateWindowsDataDir: $e');
  }
}

Future<void> _copyDir(Directory from, Directory to) async {
  await to.create(recursive: true);
  await for (final entity in from.list(followLinks: false)) {
    final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    final target = '${to.path}${Platform.pathSeparator}$name';
    if (entity is Directory) {
      await _copyDir(entity, Directory(target));
    } else if (entity is File && !await File(target).exists()) {
      await entity.copy(target);
    }
  }
}
