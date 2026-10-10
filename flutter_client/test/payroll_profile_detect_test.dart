import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_engine/payroll/payroll_engine.dart';

/// Máy chủ trả hồ sơ rỗng cho NV chưa gán bảng lương → phải tính là «chưa có bảng lương».
void main() {
  test('Hồ sơ rỗng không tính là đã cài bảng lương', () {
    expect(PayrollEngine.isRealSalaryProfile(null), isFalse);
    expect(PayrollEngine.isRealSalaryProfile({'employeeId': 'e1', 'isActive': false, 'benefit': null}), isFalse);
    expect(PayrollEngine.isRealSalaryProfile({'employeeId': 'e1', 'benefit': <String, dynamic>{}}), isFalse);
    expect(
      PayrollEngine.isRealSalaryProfile({
        'employeeId': 'e1',
        'benefit': {'id': 'b1', 'rate': 8000000, 'rateType': 'Monthly'},
      }),
      isTrue,
    );
    expect(PayrollEngine.isRealSalaryProfile({'Benefit': {'Id': 'b1'}}), isTrue);
  });
}
