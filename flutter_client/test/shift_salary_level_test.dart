import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_engine/payroll/payroll_policy.dart';
import 'package:payroll_engine/utils/shift_records_calculator.dart';

/// Lương ca (Thiết lập ca → mức lương ca) + phụ cấp làm đêm theo Chính sách tính lương.
DailyShiftPair _pair(DateTime inT, DateTime outT, {bool overnight = false}) => DailyShiftPair(
      employeeId: 'e1',
      employeeCode: 'NV001',
      employeeName: 'A',
      date: DateTime(inT.year, inT.month, inT.day),
      shiftName: 'Ca',
      checkIn: inT,
      checkOut: outT,
      lateMinutes: 0,
      earlyMinutes: 0,
      hasMatchedShift: true,
      isOvernight: overnight,
      shiftTemplateId: 's1',
    );

void main() {
  test('Giờ làm đêm chỉ tính phần trong 22:00–06:00', () {
    expect(nightWorkHours(_pair(DateTime(2026, 8, 1, 18), DateTime(2026, 8, 2, 2))), 4);
    expect(nightWorkHours(_pair(DateTime(2026, 8, 1, 21, 55), DateTime(2026, 8, 2, 6, 3))), 8);
    expect(nightWorkHours(_pair(DateTime(2026, 8, 1, 8), DateTime(2026, 8, 1, 17))), 0);
    expect(nightWorkHours(_pair(DateTime(2026, 8, 2, 4), DateTime(2026, 8, 2, 9))), 2);
  });

  test('Mức lương ca đánh dấu «Ca đêm» được cộng phụ cấp (trước đây bỏ qua)', () {
    final p = _pair(DateTime(2026, 8, 1, 18), DateTime(2026, 8, 2, 2));
    final level = {'rateType': 'fixed', 'fixedRate': 200000, 'isNightShift': true};
    final r = calcShiftPairPayroll(pair: p, level: level, fallbackFixedShiftRate: 0, standardDayHours: 8);
    expect(r.salary, 260000);
    // Chính sách tính theo giờ đêm → không cộng hệ số trong đơn giá ca.
    final r2 = calcShiftPairPayroll(pair: p, level: level, fallbackFixedShiftRate: 0, standardDayHours: 8, nightCoefficient: 1.0);
    expect(r2.salary, 200000);
  });

  test('Mức «hệ số» không nhân chồng hệ số ca đêm (trước đây 1,3 × 1,3 = 1,69)', () {
    final p = _pair(DateTime(2026, 8, 1, 22), DateTime(2026, 8, 2, 6), overnight: true);
    final r = calcShiftPairPayroll(
      pair: p,
      level: {'rateType': 'multiplier', 'multiplier': 1.3},
      fallbackFixedShiftRate: 200000,
      standardDayHours: 8,
    );
    expect(r.salary, closeTo(260000, 0.01));
  });

  test('Mức «theo giờ» trừ nghỉ trưa, phụ cấp đêm theo giờ thực làm', () {
    final shift = {'startTime': '08:00:00', 'endTime': '17:00:00', 'lunchBreakStartTime': '12:00:00', 'lunchBreakEndTime': '13:00:00'};
    final day = calcShiftPairPayroll(
      pair: _pair(DateTime(2026, 8, 1, 8), DateTime(2026, 8, 1, 17)),
      level: {'rateType': 'hourly', 'hourlyRate': 30000},
      fallbackFixedShiftRate: 0,
      standardDayHours: 8,
      shift: shift,
    );
    expect(day.salary, 8 * 30000);
    final night = calcShiftPairPayroll(
      pair: _pair(DateTime(2026, 8, 1, 22), DateTime(2026, 8, 2, 4), overnight: true),
      level: {'rateType': 'hourly', 'hourlyRate': 30000},
      fallbackFixedShiftRate: 0,
      standardDayHours: 8,
    );
    expect(night.salary, 6 * 30000 * 1.3);
  });

  test('Chính sách: mặc định = cách cũ, «Theo luật» = mức luật', () {
    final d = PayrollPolicy.fromSalarySettings({});
    expect(d.isLaw, isFalse);
    expect(d.holidayPayScope.covers(0), isFalse);
    expect(d.holidayPayScope.covers(1), isTrue);
    expect(d.nightAppliesTo(1), isFalse);
    expect(d.wholeShiftCoefficient, 1.3);
    final l = PayrollPolicy.fromSalarySettings({'payrollPolicyPreset': 'law'});
    expect(l.holidayPayScope.covers(0), isTrue);
    expect(l.nightAppliesTo(1), isTrue);
    expect(l.wholeShiftCoefficient, 1.0);
    expect(l.otWeekday(1.2), 1.5);
    expect(l.otWeekday(1.8), 1.8);
    final c = PayrollPolicy.fromSalarySettings({'holidayPayScope': 'none', 'nightPremiumEnabled': false});
    expect(c.holidayPayScope.covers(1), isFalse);
    expect(c.wholeShiftCoefficient, 1.0);
  });
}
