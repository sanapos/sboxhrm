import 'shift_hub_ui.dart';

/// Đọc dữ liệu `GET /api/shift-hub/board` cho các bảng xếp ca (ngày / tuần theo ca / sao chép / Excel).
///
/// Mỗi ô nhân viên × ngày có `items` = mọi dòng lịch trong ngày (nhiều ca + ngày nghỉ),
/// `registration` (đăng ký chờ duyệt), `leave` (đơn nghỉ chờ / đã duyệt), `swapPending`.
class BoardData {
  BoardData(this.raw);
  final Map<String, dynamic> raw;

  static List<Map<String, dynamic>> rows(dynamic v) => [
        for (final x in (v as List? ?? const []))
          if (x is Map) Map<String, dynamic>.from(x),
      ];

  List<Map<String, dynamic>> get allTemplates => rows(raw['templates']);
  List<Map<String, dynamic>> get templates => allTemplates.where((t) => t['active'] != false).toList();
  List<String> get days => [for (final d in (raw['days'] as List? ?? const [])) d.toString()];
  List<Map<String, dynamic>> get employees => rows(raw['employees']);
  List<String> get departments => [for (final d in (raw['departments'] as List? ?? const [])) d.toString()];
  String? get today => raw['today']?.toString();

  Map<String, dynamic>? tpl(dynamic id) =>
      id == null ? null : allTemplates.where((t) => t['id'].toString() == id.toString()).firstOrNull;

  Map<String, dynamic>? cov(String day, String shiftId) => rows(raw['coverage'])
      .where((c) => c['date'] == day && c['shiftId'].toString() == shiftId)
      .firstOrNull;

  static Map<String, dynamic>? cell(Map<String, dynamic> e, String day) {
    final c = (e['cells'] as Map?)?[day];
    return c is Map ? Map<String, dynamic>.from(c) : null;
  }

  /// Dòng lịch trong ngày. Bản API cũ chưa có `items`: dựng từ ô.
  static List<Map<String, dynamic>> items(Map<String, dynamic>? c) {
    if (c == null) return const [];
    final it = rows(c['items']);
    if (it.isNotEmpty || c['scheduleId'] == null) return it;
    return [
      {'scheduleId': c['scheduleId'], 'shiftId': c['shiftId'], 'isDayOff': c['isDayOff'] == true},
    ];
  }

  /// Dòng lịch của ca [shiftId] trong ô (null nếu chưa xếp).
  static Map<String, dynamic>? shiftItem(Map<String, dynamic>? c, String shiftId) =>
      items(c).where((x) => x['isDayOff'] != true && x['shiftId']?.toString() == shiftId).firstOrNull;

  static List<Map<String, dynamic>> shiftItems(Map<String, dynamic>? c) =>
      items(c).where((x) => x['isDayOff'] != true && x['shiftId'] != null).toList();

  static Map<String, dynamic>? dayOffItem(Map<String, dynamic>? c) => items(c).where((x) => x['isDayOff'] == true).firstOrNull;

  static bool hasSchedule(Map<String, dynamic>? c) => items(c).isNotEmpty;

  static Map<String, dynamic>? registration(Map<String, dynamic>? c) =>
      c?['registration'] is Map ? Map<String, dynamic>.from(c!['registration'] as Map) : null;

  static Map<String, dynamic>? leave(Map<String, dynamic>? c) =>
      c?['leave'] is Map ? Map<String, dynamic>.from(c!['leave'] as Map) : null;

  static bool leaveApproved(Map<String, dynamic>? c) => leave(c)?['status'] == 'Approved';

  /// Phút trong ngày của «HH:mm».
  static int? minutes(dynamic hhmm) {
    final p = hhmm?.toString().split(':');
    if (p == null || p.length < 2) return null;
    final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
    return h == null || m == null ? null : h * 60 + m;
  }

  /// Hai ca mẫu trùng giờ (ca qua đêm tính sang hôm sau).
  bool overlaps(Map<String, dynamic> a, Map<String, dynamic> b) {
    int? s1 = minutes(a['start']), e1 = minutes(a['end']), s2 = minutes(b['start']), e2 = minutes(b['end']);
    if (s1 == null || e1 == null || s2 == null || e2 == null) return false;
    if (e1 <= s1) e1 += 1440;
    if (e2 <= s2) e2 += 1440;
    return s1 < e2 && s2 < e1;
  }

  /// Tên các ca đã xếp trong ô, theo thứ tự giờ.
  String shiftNames(Map<String, dynamic>? c) =>
      shiftItems(c).map((x) => tpl(x['shiftId'])?['name']?.toString() ?? 'Ca').join(', ');

  /// Nhân viên đang có ca [shiftId] ngày [day].
  List<Map<String, dynamic>> employeesIn(String day, String shiftId) =>
      employees.where((e) => shiftItem(cell(e, day), shiftId) != null).toList();

  static DateTime date(String day) => ShiftUi.parse(day)!;
}
