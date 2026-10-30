import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/business_trip_case_detail_screen.dart';
import 'package:zkteco_flutter_client/screens/business_trip_expense_screen.dart';

import 'guide_shot_kit.dart';
import 'hrm_extras_common.dart';

/// Ảnh cho bước hướng dẫn «Công tác & tạm ứng công tác phí» (id: business_trip).

final _categories = [
  for (final (i, name) in ['Tiền ăn', 'Đi lại (xe, vé máy bay)', 'Nhà nghỉ / khách sạn', 'Chi phí khác'].indexed)
    {'id': 'cat$i', 'name': name, 'sortOrder': i, 'requiresInvoice': i == 2, 'isActive': true},
];

Map<String, dynamic> _case(String id, String code, String title, int status, String emp, String empCode,
        {required String dest, required String from, required String to, int advance = 0, int settled = 0}) =>
    {
      'id': id, 'caseCode': code, 'title': title, 'status': status, 'employeeName': emp, 'employeeCode': empCode,
      'destination': dest, 'tripFromDate': '${from}T00:00:00', 'tripToDate': '${to}T00:00:00',
      'advanceAmount': advance, 'settledAmount': settled, 'balanceAmount': settled == 0 ? 0 : settled - advance,
      'createdAt': '2026-10-20T02:00:00Z',
    };

final _cases = [
  _case('bt1', 'CT-0007', 'Đi Đà Lạt chọn nhà cung cấp rau', 1, 'Lê Văn Minh', '3',
      dest: 'Đà Lạt', from: '2026-11-04', to: '2026-11-06', advance: 3000000),
  _case('bt2', 'CT-0006', 'Tập huấn pha chế tại Hà Nội', 3, 'Trần Thị Lan', '2',
      dest: 'Hà Nội', from: '2026-10-21', to: '2026-10-23', advance: 5000000),
  _case('bt3', 'CT-0005', 'Khảo sát mặt bằng chi nhánh Thủ Đức', 7, 'Nguyễn Văn Hùng', '1',
      dest: 'TP. Thủ Đức', from: '2026-10-08', to: '2026-10-08', advance: 500000, settled: 620000),
  _case('bt4', 'CT-0004', 'Nhận hàng thiết bị bếp ở Bình Dương', 8, 'Võ Minh Tuấn', '5',
      dest: 'Bình Dương', from: '2026-09-25', to: '2026-09-25', settled: 350000),
];

final _detail = {
  ..._cases.first,
  'note': 'Gặp 3 nhà vườn, chốt giá rau tháng 11–12.',
  'advance': {'id': 'ad1', 'status': 0, 'amount': 3000000, 'isPaid': false, 'reason': 'Vé xe + nhà nghỉ 2 đêm'},
};

final _api = guideApi({
  '/api/BusinessTripCases/categories/seed': {},
  '/api/BusinessTripCases/categories': _categories,
  '/api/BusinessTripCases/bt1': _detail,
  '/api/BusinessTripCases': {'items': _cases, 'totalCount': _cases.length},
  '/api/employees': {'items': extrasEmployees, 'totalCount': extrasEmployees.length},
});

const _crumbs = ['Công tác phí'];

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('business-trip-1$suffix: danh sách hồ sơ', (t) async {
      await guideShot(
        t,
        name: 'business-trip-1$suffix',
        screen: withExtrasPackage(const BusinessTripExpenseScreen()),
        api: _api,
        crumbs: _crumbs,
        size: size,
        marks: [
          GuideMark(1, [topActionBox('Hồ sơ mới', mobile: size.width < 600)]),
          GuideMark(2, [cardOf(find.text('Đi Đà Lạt chọn nhà cung cấp rau').first)], pad: 4),
        ],
      );
    });

    testWidgets('business-trip-2$suffix: hồ sơ mới', (t) async {
      await guideShot(
        t,
        name: 'business-trip-2$suffix',
        screen: withExtrasPackage(const BusinessTripExpenseScreen()),
        api: _api,
        crumbs: [..._crumbs, 'Hồ sơ mới'],
        size: size,
        act: (t) async {
          await t.tap(topAction('Hồ sơ mới'));
          await extrasSettle(t);
          await t.enterText(fieldLabeled('Tiêu đề *'), 'Đi Đà Lạt chọn nhà cung cấp rau');
          await t.enterText(fieldLabeled('Điểm đến'), 'Đà Lạt');
          await t.enterText(fieldLabeled('Ghi chú'), 'Gặp 3 nhà vườn, chốt giá rau tháng 11–12.');
          await t.pump();
        },
        marks: [
          GuideMark(1, [fieldLabeled('Tiêu đề *'), fieldLabeled('Điểm đến')]),
          GuideMark(2, [GuideMark.button(find.text('Từ ngày')), GuideMark.button(find.text('Đến ngày'))]),
          GuideMark(3, [GuideMark.button(find.text('Tạo & nhập chi phí'))]),
        ],
      );
    });

    testWidgets('business-trip-3$suffix: duyệt và chi tạm ứng', (t) async {
      await guideShot(
        t,
        name: 'business-trip-3$suffix',
        screen: withExtrasPackage(const BusinessTripCaseDetailScreen(caseId: 'bt1')),
        api: _api,
        crumbs: [..._crumbs, 'CT-0007'],
        size: size,
        act: (t) async {
          await guideScrollTo(t, find.text('Duyệt ứng'), alignment: 0.85);
        },
        marks: [
          GuideMark(1, [find.text('Ứng công tác').first, find.textContaining('Đề nghị ứng:').first, find.textContaining('Đã chi:').first], pad: 10),
          GuideMark(2, [GuideMark.button(find.text('Từ chối ứng')), GuideMark.button(find.text('Duyệt ứng'))]),
        ],
      );
    });
  }
}
