import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'attendance_leave_lookup.dart';
import 'package:zkteco_flutter_client/theme/sbox_tokens.dart';

/// Phạm vi ngày trên bảng tổng hợp chấm công (theo ca / chi tiết) — áp dụng cả file Excel / PNG xuất ra.
enum AttendanceDayScope {
  /// Mọi ngày trong kỳ: ngày không chấm có dòng riêng (Vắng / Nghỉ phép / Nghỉ tuần / Ngày lễ…).
  allDays,

  /// Chỉ ngày có giờ chấm.
  punchedOnly;

  String get label => switch (this) {
        AttendanceDayScope.allDays => 'Đủ ngày trong kỳ',
        AttendanceDayScope.punchedOnly => 'Chỉ ngày có chấm',
      };

  static AttendanceDayScope parse(String? v) =>
      v == 'punchedOnly' ? AttendanceDayScope.punchedOnly : AttendanceDayScope.allDays;

  /// Nhớ lựa chọn theo máy, mỗi màn một khóa.
  static Future<AttendanceDayScope> load(String prefKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return parse(prefs.getString(prefKey));
    } catch (_) {
      return AttendanceDayScope.allDays;
    }
  }

  static Future<void> save(String prefKey, AttendanceDayScope scope) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefKey, scope.name);
    } catch (_) {}
  }
}

/// Cách xếp giờ chấm vào cột Lần 1, Lần 2… trên bảng theo ca — áp dụng cả file Excel / PNG xuất ra.
enum AttendancePunchLayout {
  /// Theo thứ tự lần chấm trong ngày (giờ đầu tiên ở Lần 1).
  ordered,

  /// Theo ca: Lần 1–2 là vào / ra ca (nửa ca) thứ nhất, Lần 3–4 ca thứ hai… — chỉ làm buổi chiều thì
  /// giờ nằm ở Lần 3–4, Lần 1–2 để trống.
  byShift;

  String get label => switch (this) {
        AttendancePunchLayout.ordered => 'Giờ chấm theo thứ tự',
        AttendancePunchLayout.byShift => 'Giờ chấm theo ca',
      };

  static AttendancePunchLayout parse(String? v) =>
      v == 'byShift' ? AttendancePunchLayout.byShift : AttendancePunchLayout.ordered;

  static Future<AttendancePunchLayout> load(String prefKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return parse(prefs.getString(prefKey));
    } catch (_) {
      return AttendancePunchLayout.ordered;
    }
  }

  static Future<void> save(String prefKey, AttendancePunchLayout layout) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefKey, layout.name);
    } catch (_) {}
  }
}

/// Loại ngày không có giờ chấm (dòng lấp thêm trên bảng).
enum AttendanceFillDayKind {
  absent,
  approvedLeave,
  pendingLeave,
  holiday,
  weeklyOff,

  /// Nhân viên tính công theo lịch: ngày không xếp ca làm.
  scheduleOff;

  static AttendanceFillDayKind fromAbsence(AbsenceCellKind k) => switch (k) {
        AbsenceCellKind.holiday => AttendanceFillDayKind.holiday,
        AbsenceCellKind.weeklyOff => AttendanceFillDayKind.weeklyOff,
        AbsenceCellKind.approvedLeave => AttendanceFillDayKind.approvedLeave,
        AbsenceCellKind.pendingLeave => AttendanceFillDayKind.pendingLeave,
        AbsenceCellKind.unpaidAbsent => AttendanceFillDayKind.absent,
      };

  /// Nhãn trạng thái (cột Trạng thái / Số công, Excel).
  String get label => switch (this) {
        AttendanceFillDayKind.absent => 'Vắng',
        AttendanceFillDayKind.approvedLeave => 'Nghỉ phép',
        AttendanceFillDayKind.pendingLeave => 'Phép chờ duyệt',
        AttendanceFillDayKind.holiday => 'Ngày lễ',
        AttendanceFillDayKind.weeklyOff => 'Nghỉ tuần',
        AttendanceFillDayKind.scheduleOff => 'Không xếp lịch',
      };

  Color get color => switch (this) {
        AttendanceFillDayKind.absent => const Color(0xFFDC2626),
        AttendanceFillDayKind.approvedLeave => (SboxColors.isBoss ? SboxColors.brand500 : const Color(0xFF1D4ED8)),
        AttendanceFillDayKind.pendingLeave => const Color(0xFFC2410C),
        AttendanceFillDayKind.holiday => const Color(0xFF7C3AED),
        AttendanceFillDayKind.weeklyOff => const Color(0xFF15803D),
        AttendanceFillDayKind.scheduleOff => const Color(0xFF64748B),
      };

  /// Màu nền dòng — cùng bảng màu mẫu Excel hằng ngày; Vắng giữ màu xen kẽ.
  Color? get rowTint => switch (this) {
        AttendanceFillDayKind.absent => null,
        AttendanceFillDayKind.approvedLeave => const Color(0xFFDBEAFE),
        AttendanceFillDayKind.pendingLeave => const Color(0xFFFFEDD5),
        AttendanceFillDayKind.holiday => const Color(0xFFEDE9FE),
        AttendanceFillDayKind.weeklyOff => const Color(0xFFDCFCE7),
        AttendanceFillDayKind.scheduleOff => const Color(0xFFF1F5F9),
      };

  /// Ngày làm việc mà không có mặt / có đơn nghỉ — nhân viên có ít nhất một ngày như vậy mới đáng hiện.
  bool get countsAsWorkDay =>
      this == AttendanceFillDayKind.absent ||
      this == AttendanceFillDayKind.approvedLeave ||
      this == AttendanceFillDayKind.pendingLeave;
}

/// Ngày cần lấp dòng cho một nhân viên theo [scope].
///
/// - [AttendanceDayScope.punchedOnly]: không lấp gì (bảng chỉ còn ngày có chấm).
/// - [AttendanceDayScope.allDays]: mọi ngày trong [dates] chưa có dòng ([hasRow]) được [classify];
///   `null` = bỏ qua ngày đó. Nhân viên chưa có dòng nào và mọi ngày chỉ là nghỉ tuần / lễ / không xếp lịch
///   (không vắng, không đơn nghỉ) → bỏ cả người, tránh khối dòng trống.
List<({DateTime day, AttendanceFillDayKind kind})> attendanceFillDays({
  required AttendanceDayScope scope,
  required List<DateTime> dates,
  required bool Function(DateTime day) hasRow,
  required AttendanceFillDayKind? Function(DateTime day) classify,
}) {
  if (scope == AttendanceDayScope.punchedOnly) return const [];
  final out = <({DateTime day, AttendanceFillDayKind kind})>[];
  var anyRow = false;
  for (final d in dates) {
    if (hasRow(d)) {
      anyRow = true;
      continue;
    }
    final kind = classify(d);
    if (kind != null) out.add((day: d, kind: kind));
  }
  if (!anyRow && !out.any((e) => e.kind.countsAsWorkDay)) return const [];
  return out;
}

/// Lọc trạng thái «Thiếu chấm»: dòng lấp thêm chỉ khớp khi là ngày vắng.
bool attendanceFillMatchesMissingFilter(AttendanceFillDayKind? kind) =>
    kind == null || kind == AttendanceFillDayKind.absent;
