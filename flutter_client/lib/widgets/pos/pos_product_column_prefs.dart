import 'package:shared_preferences/shared_preferences.dart';

import 'pos_product_table_columns.dart';

const _prefKey = 'pos_product_visible_columns_v1';

/// Đọc cấu hình cột đã lưu (SharedPreferences).
Future<Set<PosProductTableColumn>> loadPosProductVisibleColumns() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefKey);
    if (raw == null || raw.isEmpty) {
      return defaultPosProductVisibleColumns();
    }
    final cols = <PosProductTableColumn>{};
    for (final name in raw) {
      try {
        cols.add(PosProductTableColumn.values.byName(name));
      } catch (_) {}
    }
    cols.addAll({
      PosProductTableColumn.select,
      PosProductTableColumn.actions,
    });
    return cols.isEmpty ? defaultPosProductVisibleColumns() : cols;
  } catch (_) {
    return defaultPosProductVisibleColumns();
  }
}

/// Lưu cấu hình cột hiển thị.
Future<void> savePosProductVisibleColumns(
    Set<PosProductTableColumn> columns) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final toSave = columns
        .where((c) => c.canToggle)
        .map((c) => c.name)
        .toList()
      ..sort();
    await prefs.setStringList(_prefKey, toSave);
  } catch (_) {}
}
