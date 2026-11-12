import '../widgets/reports/hrm_report_widgets.dart';
import '../widgets/sbox/sbox_charts.dart';

/// Nhóm các dòng gốc theo người, dùng cho sheet «số này từ đâu ra» của chip đếm người.
class HrADrillGroup<T> {
  HrADrillGroup(this.name);
  final String name;
  final List<T> items = [];
  double sum = 0;
}

/// Gom [rows] theo [key] (bỏ khóa rỗng nếu [skipEmpty]); [value] cộng dồn vào [HrADrillGroup.sum].
/// Xếp theo tổng giảm dần, rồi số dòng giảm dần, rồi tên.
List<HrADrillGroup<T>> hrADrillGroupBy<T>(
  Iterable<T> rows,
  String Function(T) key, {
  double Function(T)? value,
  bool skipEmpty = false,
}) {
  final map = <String, HrADrillGroup<T>>{};
  for (final r in rows) {
    final k = key(r);
    if (skipEmpty && k.isEmpty) continue;
    final g = map.putIfAbsent(k, () => HrADrillGroup<T>(k));
    g.items.add(r);
    if (value != null) g.sum += value(r);
  }
  final list = map.values.toList()
    ..sort((a, b) {
      final c = b.sum.compareTo(a.sum);
      if (c != 0) return c;
      final n = b.items.length.compareTo(a.items.length);
      if (n != 0) return n;
      return a.name.compareTo(b.name);
    });
  return list;
}

/// «150.000 đ».
String hrADrillMoney(num v) => '${reportMoneyFmt.format(v)} đ';

/// «2,5 ngày».
String hrADrillDays(num v) => '${SboxFmt.decimal(v)} ngày';
