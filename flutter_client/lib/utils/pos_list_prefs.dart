import 'package:shared_preferences/shared_preferences.dart';

/// Nhớ lựa chọn sắp xếp của từng màn danh sách trên máy (mở lại không phải chọn lại).
abstract final class PosListPrefs {
  static String _key(String screen) => 'pos_list_sort_$screen';

  static Future<String?> loadSort(String screen) async {
    try {
      return (await SharedPreferences.getInstance()).getString(_key(screen));
    } catch (_) {
      return null;
    }
  }

  static void saveSort(String screen, String value) {
    SharedPreferences.getInstance()
        .then((p) => p.setString(_key(screen), value))
        .catchError((_) => false);
  }
}
