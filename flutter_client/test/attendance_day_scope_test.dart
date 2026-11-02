import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/utils/attendance_day_scope.dart';
import 'package:zkteco_flutter_client/utils/attendance_leave_lookup.dart';
import 'package:zkteco_flutter_client/utils/report_screen_helpers.dart';

void main() {
  // Tháng 11/2026: T2 02 → CN 08.
  final dates = [for (var d = 2; d <= 8; d++) DateTime(2026, 11, d)];
  bool punched(DateTime d) => d.day == 2 || d.day == 3;

  AttendanceFillDayKind? classify(DateTime d) => switch (d.day) {
        4 => AttendanceFillDayKind.approvedLeave,
        5 => AttendanceFillDayKind.pendingLeave,
        6 => AttendanceFillDayKind.holiday,
        8 => AttendanceFillDayKind.weeklyOff,
        _ => AttendanceFillDayKind.absent,
      };

  group('attendanceFillDays', () {
    test('Đủ ngày: mọi ngày không chấm có dòng, đúng loại', () {
      final fills = attendanceFillDays(
        scope: AttendanceDayScope.allDays,
        dates: dates,
        hasRow: punched,
        classify: classify,
      );
      expect(fills.map((f) => f.day.day), [4, 5, 6, 7, 8]);
      expect(fills.map((f) => f.kind), [
        AttendanceFillDayKind.approvedLeave,
        AttendanceFillDayKind.pendingLeave,
        AttendanceFillDayKind.holiday,
        AttendanceFillDayKind.absent,
        AttendanceFillDayKind.weeklyOff,
      ]);
      // Cùng với 2 ngày có chấm = đủ 7 ngày trong kỳ.
      expect(fills.length + dates.where(punched).length, dates.length);
    });

    test('Chỉ ngày có chấm: không lấp dòng nào (kể cả Vắng)', () {
      final fills = attendanceFillDays(
        scope: AttendanceDayScope.punchedOnly,
        dates: dates,
        hasRow: punched,
        classify: classify,
      );
      expect(fills, isEmpty);
    });

    test('classify trả null thì bỏ ngày đó', () {
      final fills = attendanceFillDays(
        scope: AttendanceDayScope.allDays,
        dates: dates,
        hasRow: punched,
        classify: (d) => d.day == 7 ? null : classify(d),
      );
      expect(fills.map((f) => f.day.day), [4, 5, 6, 8]);
    });

    test('NV không chấm, chỉ toàn nghỉ tuần / lễ / không xếp lịch → bỏ cả người', () {
      final fills = attendanceFillDays(
        scope: AttendanceDayScope.allDays,
        dates: dates,
        hasRow: (_) => false,
        classify: (d) => d.day == 6
            ? AttendanceFillDayKind.holiday
            : (d.day == 8 ? AttendanceFillDayKind.weeklyOff : AttendanceFillDayKind.scheduleOff),
      );
      expect(fills, isEmpty);
    });

    test('NV không chấm nhưng vắng / có đơn nghỉ → vẫn đủ ngày', () {
      final fills = attendanceFillDays(
        scope: AttendanceDayScope.allDays,
        dates: dates,
        hasRow: (_) => false,
        classify: (d) => d.day == 4 ? AttendanceFillDayKind.approvedLeave : AttendanceFillDayKind.weeklyOff,
      );
      expect(fills.length, dates.length);
    });
  });

  test('Lọc «Thiếu chấm»: chỉ dòng vắng trong các dòng lấp thêm', () {
    expect(attendanceFillMatchesMissingFilter(null), isTrue);
    expect(attendanceFillMatchesMissingFilter(AttendanceFillDayKind.absent), isTrue);
    for (final k in AttendanceFillDayKind.values.where((k) => k != AttendanceFillDayKind.absent)) {
      expect(attendanceFillMatchesMissingFilter(k), isFalse, reason: k.name);
    }
  });

  test('Đổi loại ô vắng sang loại dòng lấp', () {
    expect(AttendanceFillDayKind.fromAbsence(AbsenceCellKind.unpaidAbsent), AttendanceFillDayKind.absent);
    expect(AttendanceFillDayKind.fromAbsence(AbsenceCellKind.approvedLeave).label, 'Nghỉ phép');
    expect(AttendanceFillDayKind.fromAbsence(AbsenceCellKind.holiday).label, 'Ngày lễ');
    expect(AttendanceFillDayKind.fromAbsence(AbsenceCellKind.weeklyOff).label, 'Nghỉ tuần');
    expect(AttendanceFillDayKind.absent.rowTint, isNull);
  });

  test('Nhớ lựa chọn theo máy; mặc định đủ ngày', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await AttendanceDayScope.load('k'), AttendanceDayScope.allDays);
    await AttendanceDayScope.save('k', AttendanceDayScope.punchedOnly);
    expect(await AttendanceDayScope.load('k'), AttendanceDayScope.punchedOnly);
    expect(await AttendanceDayScope.load('khac'), AttendanceDayScope.allDays);
  });

  test('Nhãn bộ lọc chi nhánh / phòng ban cho file xuất', () {
    final f = ReportBranchFilter()
      ..branches = [
        {'id': 'b1', 'name': 'Chi nhánh Quận 1'},
      ]
      ..departments = [
        {'id': 'd1', 'name': 'Bếp'},
        {'id': 'name:Phục vụ', 'name': 'Phục vụ'},
      ];
    expect(f.filterLabel(), isNull);
    expect(f.filterLabel(branchId: 'b1'), 'Chi nhánh: Chi nhánh Quận 1');
    expect(f.filterLabel(branchId: 'b1', departmentId: 'd1'), 'Chi nhánh: Chi nhánh Quận 1 · Phòng ban: Bếp');
    expect(f.filterLabel(departmentId: 'name:Phục vụ'), 'Phòng ban: Phục vụ');
  });
}
