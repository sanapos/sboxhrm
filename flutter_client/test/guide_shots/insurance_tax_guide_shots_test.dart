import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/insurance_settings_screen.dart';
import 'package:zkteco_flutter_client/screens/tax_settings_screen.dart';

import 'guide_shot_kit.dart';

/// Ảnh cho bước hướng dẫn «Bảo hiểm & thuế TNCN» (id: insurance_tax).

const _insurance = {
  'baseSalary': 2340000, 'maxInsuranceSalary': 46800000, 'defaultRegion': 1,
  'minSalaryRegion1': 5310000, 'minSalaryRegion2': 4730000, 'minSalaryRegion3': 4140000, 'minSalaryRegion4': 3700000,
  'bhxhEmployeeRate': 8, 'bhxhEmployerRate': 17.5, 'bhytEmployeeRate': 1.5, 'bhytEmployerRate': 3,
  'bhtnEmployeeRate': 1, 'bhtnEmployerRate': 1, 'unionFeeEmployeeRate': 1, 'unionFeeEmployerRate': 2,
};

final _deps = [
  {'employeeId': 'e1', 'employeeName': 'Nguyễn Văn An', 'employeeCode': 'NV001', 'numberOfDependents': 2},
  {'employeeId': 'e2', 'employeeName': 'Trần Minh Khoa', 'employeeCode': 'NV002', 'numberOfDependents': 1},
  {'employeeId': 'e3', 'employeeName': 'Lê Quốc Bảo', 'employeeCode': 'NV003', 'numberOfDependents': 0},
  {'employeeId': 'e4', 'employeeName': 'Phạm Thu Hà', 'employeeCode': 'NV004', 'numberOfDependents': 1},
  {'employeeId': 'e5', 'employeeName': 'Đỗ Hải Nam', 'employeeCode': 'NV005', 'numberOfDependents': 0},
];

final _api = guideApi({
  '/api/settings/insurance': _insurance,
  '/api/settings/tax/employee-deductions': _deps,
  // Để trống → màn dùng biểu thuế mặc định hiện hành.
  '/api/settings/tax': <String, dynamic>{},
});

Finder _tile(String label) => GuideMark.within(find.text(label), 'SettingsTile');
Finder _section(String title) => GuideMark.within(find.text(title), 'SettingsSection');

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = size.width < 600;

    testWidgets('insurance-tax-1$suffix: tỷ lệ đóng bảo hiểm', (t) async {
      await guideShot(
        t,
        name: 'insurance-tax-1$suffix',
        screen: const InsuranceSettingsScreen(canEditOverride: true),
        api: _api,
        crumbs: const ['Cài đặt', 'Bảo hiểm'],
        size: size,
        act: (t) async => guideScrollTo(t, find.text('Tỷ lệ đóng'), alignment: 0.05),
        marks: [
          GuideMark(1, [_tile('BHXH'), _tile('BHTN')], pad: 2),
          GuideMark(2, [find.textContaining('Tổng bắt buộc')], pad: 8),
        ],
      );
    });

    testWidgets('insurance-tax-2$suffix: giảm trừ gia cảnh, biểu thuế', (t) async {
      await guideShot(
        t,
        name: 'insurance-tax-2$suffix',
        screen: const TaxSettingsScreen(canEditOverride: true),
        api: _api,
        crumbs: const ['Cài đặt', 'Thuế TNCN'],
        size: size,
        act: (t) async => guideScrollTo(t, find.text('Giảm trừ gia cảnh (mỗi tháng)'), alignment: 0.05),
        marks: [
          GuideMark(1, [_tile('Bản thân người nộp thuế'), _tile('Mỗi người phụ thuộc')], pad: 2),
          GuideMark(2, [find.text('Biểu thuế lũy tiến')], pad: 8),
        ],
      );
    });

    testWidgets('insurance-tax-3$suffix: người phụ thuộc của nhân viên', (t) async {
      await guideShot(
        t,
        name: 'insurance-tax-3$suffix',
        screen: const TaxSettingsScreen(canEditOverride: true),
        api: _api,
        crumbs: const ['Cài đặt', 'Thuế TNCN'],
        size: size,
        act: (t) async => guideScrollTo(t, find.text('Người phụ thuộc của nhân viên'), alignment: mobile ? 0.08 : 0.2),
        marks: [
          GuideMark(1, [find.text('Người phụ thuộc của nhân viên')], pad: 8),
          GuideMark(2, [GuideMark.within(find.text('Nguyễn Văn An'), 'ListTile')], pad: 4),
        ],
      );
    });
  }
}
