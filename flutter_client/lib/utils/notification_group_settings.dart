import 'package:shared_preferences/shared_preferences.dart';

import 'notification_category_utils.dart';

/// Local cache của 2 nhóm thông báo (chấm công / công việc).
/// Đồng bộ từ server sau login và khi lưu thiết lập — dùng lọc popup in-app.
class NotificationGroupSettings {
  NotificationGroupSettings._();

  static const _keyAttendance = 'notif_group_attendance';
  static const _keyWork = 'notif_group_work';

  static Future<bool> isAttendanceEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAttendance) ?? true;
  }

  static Future<bool> isWorkEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyWork) ?? true;
  }

  static Future<void> setAttendanceEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAttendance, value);
  }

  static Future<void> setWorkEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyWork, value);
  }

  /// Đồng bộ nhóm local từ map category → isEnabled (server / cache).
  static Future<void> syncFromCategoryMap(Map<String, bool> byCode) async {
    if (byCode.isEmpty) {
      await setAttendanceEnabled(true);
      await setWorkEnabled(true);
      return;
    }

    var attOn = false;
    var workOn = false;

    for (final entry in byCode.entries) {
      if (NotificationCategoryUtils.attendanceGroupCodes.contains(entry.key)) {
        if (entry.value) attOn = true;
      } else if (entry.value) {
        workOn = true;
      }
    }

    await setAttendanceEnabled(attOn);
    await setWorkEnabled(workOn);
  }

  /// Đồng bộ từ danh sách preference API `[{categoryCode, isEnabled}, …]`.
  static Future<void> syncFromPreferenceList(Iterable<Map<String, dynamic>> prefs) {
    final map = <String, bool>{};
    for (final p in prefs) {
      final code = NotificationCategoryUtils.normalizeCategory(
        p['categoryCode']?.toString(),
      );
      if (code == null || code.isEmpty) continue;
      map[code] = p['isEnabled'] as bool? ?? true;
    }
    return syncFromCategoryMap(map);
  }

  /// Nhóm chấm công = category `attendance` + `device` (khớp UI & server seed).
  static bool isAttendanceType(
    String? relatedEntityType, {
    String? categoryCode,
  }) {
    final resolved = NotificationCategoryUtils.resolveCategory(
      categoryCode: categoryCode,
      relatedEntityType: relatedEntityType,
    );
    return NotificationCategoryUtils.isAttendanceCategory(resolved);
  }

  static bool isWorkType(
    String? relatedEntityType, {
    String? categoryCode,
  }) {
    return !isAttendanceType(
      relatedEntityType,
      categoryCode: categoryCode,
    );
  }
}
