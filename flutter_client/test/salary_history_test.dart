import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/salary_v2/sl_history.dart';

Map<String, dynamic> _b(num rate, {num completion = 0}) =>
    {'rateType': 1, 'rate': rate, 'completionSalary': completion, 'standardHoursPerDay': 8, 'paidLeaveDays': 12};

void main() {
  test('Gộp phiên bản + đính chính / bản bị thay / hủy, mới nhất trước', () {
    final entries = parseSalaryLog({
      'versions': [
        {'id': 'v2', 'from': '2026-10-08T00:00:00', 'to': '9998-12-31T00:00:00', 'effectiveDate': '2026-10-08T00:00:00', 'benefit': _b(9500000)},
        {'id': 'v1', 'from': '0002-01-01T00:00:00', 'to': '2026-10-07T00:00:00', 'effectiveDate': '2026-09-01T00:00:00', 'benefit': _b(8500000)},
      ],
      'changes': [
        {'kind': 'replaced', 'at': '2026-10-08T03:00:00', 'by': 'a@b.vn', 'before': _b(9000000), 'after': _b(9500000), 'effectiveDate': '2026-10-08T00:00:00'},
        {'kind': 'correction', 'at': '2026-09-05T03:00:00', 'by': 'a@b.vn', 'before': _b(8000000), 'after': _b(8500000)},
      ],
    });
    expect(entries.map((e) => e.kind).toList(), ['replaced', 'version', 'correction', 'version']);
    expect(entries.where((e) => e.kind == 'version').length, 2);
  });

  test('So sánh hồ sơ ghi rõ mức cũ → mới', () {
    final d = salaryDiff(_b(8000000, completion: 1000000), _b(8500000, completion: 1000000));
    expect(d.length, 1);
    expect(d.first, contains('Lương cơ bản'));
    expect(d.first, contains('→'));
    expect(salaryDiff(_b(8000000), _b(8000000)), isEmpty);
  });
}
