import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/allowance_calculator.dart';
import 'package:zkteco_flutter_client/utils/shift_records_calculator.dart';

/// Phụ cấp theo ngày / theo ca chỉ tính khi làm đủ thời gian trong ca.
void main() {
  // Ca chiều 13:00–18:00 (5 tiếng, không nghỉ giữa ca).
  final shift5h = <String, dynamic>{'id': 'S5', 'name': 'Ca chiều', 'startTime': '13:00:00', 'endTime': '18:00:00'};
  // Ca hành chính 08:00–17:00, nghỉ trưa 12:00–13:00 → 8 tiếng.
  final office = <String, dynamic>{
    'id': 'HC', 'name': 'Hành chính', 'startTime': '08:00:00', 'endTime': '17:00:00',
    'lunchBreakStartTime': '12:00:00', 'lunchBreakEndTime': '13:00:00',
  };

  DailyShiftPair pair(DateTime inAt, DateTime outAt, Map<String, dynamic> shift) => DailyShiftPair(
        employeeId: 'e1', employeeCode: 'NV1', employeeName: 'A', date: DateTime(inAt.year, inAt.month, inAt.day),
        shiftName: '${shift['name']}', checkIn: inAt, checkOut: outAt, lateMinutes: 0, earlyMinutes: 0,
        hasMatchedShift: true, shiftTemplateId: '${shift['id']}',
      );

  AllowanceWorkUnit unit(DailyShiftPair p, Map<String, dynamic> s) {
    final m = shiftWindowMinutes(p, s)!;
    return AllowanceWorkUnit(dayKey: AllowanceWorkUnit.keyOf(p.date), shiftId: p.shiftTemplateId, shiftName: p.shiftName,
        workedMinutes: m.worked, requiredMinutes: m.required);
  }

  group('Phút làm trong khung ca', () {
    test('Đến sớm / ở lại muộn không được cộng', () {
      final m = shiftWindowMinutes(pair(DateTime(2026, 9, 1, 12, 0), DateTime(2026, 9, 1, 19, 0), shift5h), shift5h)!;
      expect(m.worked, 300);
      expect(m.required, 300);
    });

    test('Đi muộn 20 phút, về sớm 15 phút → 265 phút', () {
      final m = shiftWindowMinutes(pair(DateTime(2026, 9, 1, 13, 20), DateTime(2026, 9, 1, 17, 45), shift5h), shift5h)!;
      expect(m.worked, 265);
    });

    test('Trừ nghỉ trưa; thời lượng ca hiệu lực 8 tiếng', () {
      final m = shiftWindowMinutes(pair(DateTime(2026, 9, 1, 8, 0), DateTime(2026, 9, 1, 17, 0), office), office)!;
      expect(m.worked, 480);
      expect(m.required, 480);
    });

    test('Ca qua đêm 22:00–06:00', () {
      final night = <String, dynamic>{'id': 'N', 'name': 'Ca đêm', 'startTime': '22:00:00', 'endTime': '06:00:00'};
      final m = shiftWindowMinutes(pair(DateTime(2026, 9, 1, 22, 10), DateTime(2026, 9, 2, 6, 0), night), night)!;
      expect(m.worked, 470);
      expect(m.required, 480);
    });
  });

  group('Điều kiện nhận', () {
    test('Ngưỡng 90% ca 5 tiếng = 270 phút; mô tả dễ hiểu', () {
      final a = {'minWorkPercent': 90};
      expect(AllowanceCalculator.thresholdMinutes(a, 300), 270);
      expect(AllowanceCalculator.describeRule(a), contains('4 giờ 30 phút'));
      expect(AllowanceCalculator.thresholdMinutes({'minWorkHours': 4.5}, 480), 270);
      expect(AllowanceCalculator.thresholdMinutes({}, 300), isNull);
      // Đặt cả hai → theo %.
      expect(AllowanceCalculator.thresholdMinutes({'minWorkPercent': 50, 'minWorkHours': 7}, 300), 150);
    });

    final perShift = {'id': 'a1', 'name': 'PC ca chiều', 'type': 'PerShift', 'amount': 30000, 'shiftIds': ['S5'], 'minWorkPercent': 90};
    final daily = {'id': 'a2', 'name': 'PC ăn', 'type': 'Daily', 'amount': 35000, 'minWorkHours': 4.5};

    final units = [
      unit(pair(DateTime(2026, 9, 1, 13, 0), DateTime(2026, 9, 1, 18, 0), shift5h), shift5h), // 5g — đạt
      unit(pair(DateTime(2026, 9, 2, 13, 25), DateTime(2026, 9, 2, 18, 0), shift5h), shift5h), // 4g35 — đạt
      unit(pair(DateTime(2026, 9, 3, 13, 40), DateTime(2026, 9, 3, 18, 0), shift5h), shift5h), // 4g20 — không
      unit(pair(DateTime(2026, 9, 4, 13, 0), DateTime(2026, 9, 4, 13, 10), shift5h), shift5h), // 10 phút — không
    ];
    final days = {for (final u in units) u.dayKey: 1.0};

    test('Theo ca: chỉ ca làm từ 90% (4g30) trở lên', () {
      final r = AllowanceCalculator.earnedWithRules(
          allowances: [perShift], employeeId: 'e1', units: units, eligibleDays: days, standardDayMinutes: 480);
      expect(r.shiftCount, 2);
      expect(r.shift, 60000);
      expect(r.misses.map((m) => m.dayKey), ['2026-09-03', '2026-09-04']);
      expect(r.misses.first.label, contains('làm 4 giờ 20 phút / cần 4 giờ 30 phút'));
    });

    test('Không điều kiện: ca có chấm ra đều tính (như cũ)', () {
      final r = AllowanceCalculator.earnedWithRules(
          allowances: [{...perShift}..remove('minWorkPercent')], employeeId: 'e1', units: units, eligibleDays: days, standardDayMinutes: 480);
      expect(r.shiftCount, 4);
    });

    test('Theo ngày có điều kiện: đếm ngày đạt, không nhân hệ số lễ', () {
      final r = AllowanceCalculator.earnedWithRules(
          allowances: [daily], employeeId: 'e1', units: units, eligibleDays: days, standardDayMinutes: 480);
      expect(r.dailyDays, 2);
      expect(r.daily, 70000);
    });

    test('Theo ngày không điều kiện: theo công gốc (nửa công = nửa phụ cấp)', () {
      final r = AllowanceCalculator.earnedWithRules(
          allowances: [{...daily}..remove('minWorkHours')], employeeId: 'e1', units: units,
          eligibleDays: {'2026-09-01': 1, '2026-09-02': 0.5}, standardDayMinutes: 480);
      expect(r.daily, 52500);
    });

    test('Ngày chỉ tăng ca (không có công) không được phụ cấp ngày', () {
      final r = AllowanceCalculator.earnedWithRules(
          allowances: [daily], employeeId: 'e1', units: units, eligibleDays: {'2026-09-01': 1}, standardDayMinutes: 480);
      expect(r.dailyDays, 1);
    });

    test('Ngày 2 ca: cộng thời gian các ca, so với tổng thời lượng', () {
      final morning = <String, dynamic>{'id': 'S1', 'name': 'Ca sáng', 'startTime': '07:00:00', 'endTime': '11:00:00'};
      final u2 = [
        unit(pair(DateTime(2026, 9, 5, 7, 0), DateTime(2026, 9, 5, 11, 0), morning), morning), // 4g / 4g
        unit(pair(DateTime(2026, 9, 5, 13, 30), DateTime(2026, 9, 5, 18, 0), shift5h), shift5h), // 4g30 / 5g
      ];
      final r = AllowanceCalculator.earnedWithRules(
          allowances: [{...daily, 'minWorkHours': null, 'minWorkPercent': 90}], employeeId: 'e1', units: u2,
          eligibleDays: {'2026-09-05': 1}, standardDayMinutes: 480);
      // 510 / 540 phút = 94% ≥ 90% → đạt.
      expect(r.dailyDays, 1);
    });
  });
}
