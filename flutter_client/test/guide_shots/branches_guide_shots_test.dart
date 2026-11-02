import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:zkteco_flutter_client/screens/branch_management_screen.dart';

import 'guide_shot_kit.dart';
import 'hrm_extras_common.dart';

/// Ảnh cho bước hướng dẫn «Chi nhánh / nhiều điểm bán» (id: branches).

Map<String, Object?> _b(String id, String code, String name, int emp,
        {bool hq = false, String? parent, String? parentName, String? manager, String? address, String? phone}) =>
    {
      'id': id, 'code': code, 'name': name, 'employeeCount': emp, 'isHeadquarter': hq, 'isActive': true,
      'parentBranchId': parent, 'parentBranchName': parentName, 'managerName': manager, 'address': address,
      'city': 'TP. Hồ Chí Minh', 'phone': phone, 'openTime': '06:00', 'closeTime': '22:00', 'sortOrder': 0,
    };

final _branches = [
  _b('hq', 'HQ', 'Cơm Gà Nam — Trụ sở Quận 1', 12, hq: true, manager: 'Nguyễn Văn Hùng', address: '25 Lê Lợi, Bến Nghé', phone: '0283822 1234'),
  _b('q3', 'Q3', 'Chi nhánh Quận 3', 7, parent: 'hq', parentName: 'Cơm Gà Nam — Trụ sở Quận 1', manager: 'Trần Thị Lan', address: '118 Võ Văn Tần, Phường 6', phone: '0283930 5566'),
  _b('td', 'TD', 'Chi nhánh Thủ Đức', 5, parent: 'hq', parentName: 'Cơm Gà Nam — Trụ sở Quận 1', manager: 'Lê Văn Minh', address: '42 Võ Văn Ngân, Linh Chiểu', phone: '0283722 7788'),
];

final _tree = [
  {
    ..._branches[0],
    'children': [
      {..._branches[1], 'children': []},
      {..._branches[2], 'children': []},
    ],
  },
];

MockClient get _api => guideApi({
      '/api/branches/limits': {'maxBranches': 5, 'usedBranches': 3, 'canCreate': true},
      '/api/branches/tree': _tree,
      '/api/branches/stats': {
        'totalBranches': 3, 'activeBranches': 3, 'inactiveBranches': 0, 'headquarterCount': 1, 'totalEmployees': 24,
      },
      '/api/branches/select': [
        for (final b in _branches) {'id': b['id'], 'code': b['code'], 'name': b['name'], 'isHeadquarter': b['isHeadquarter']},
      ],
      '/api/branches': _branches,
      '/api/employees': {'items': extrasEmployees, 'totalCount': extrasEmployees.length},
    });

const _crumbs = ['Thiết lập SBOX', 'Chi nhánh'];

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('branches-1$suffix: danh sách chi nhánh', (t) async {
      await guideShot(
        t,
        name: 'branches-1$suffix',
        screen: withExtrasPackage(const BranchManagementScreen()),
        api: _api,
        crumbs: _crumbs,
        size: size,
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Thêm mới'))]),
          GuideMark(2, [find.text('Danh sách'), find.text('Thống kê')], pad: 10),
          GuideMark(3, [cardOf(find.text('Chi nhánh Quận 3'))], pad: 2),
        ],
      );
    });

    testWidgets('branches-2$suffix: thêm chi nhánh', (t) async {
      await guideShot(
        t,
        name: 'branches-2$suffix',
        screen: withExtrasPackage(const BranchManagementScreen()),
        api: _api,
        crumbs: [..._crumbs, 'Thêm mới'],
        size: size,
        act: (t) async {
          await t.tap(find.text('Thêm mới').first);
          await extrasSettle(t, 8);
          await t.enterText(fieldLabeled('Tên chi nhánh *'), 'Chi nhánh Bình Thạnh');
          await t.enterText(fieldLabeled('Mã chi nhánh *'), 'BT');
          await t.enterText(fieldLabeled('Số điện thoại'), '0283512 3344');
          await extrasSettle(t, 3);
        },
        marks: [
          GuideMark(1, [fieldLabeled('Mã chi nhánh *'), fieldLabeled('Tên chi nhánh *')], pad: 4),
          GuideMark(2, [dropdownLabeled('Chi nhánh cha'), dropdownLabeled('Quản lý chi nhánh')], pad: 4),
          GuideMark(3, [GuideMark.button(find.text('Tạo mới'))], pad: 4),
        ],
      );
    });

    testWidgets('branches-3$suffix: sơ đồ chi nhánh', (t) async {
      await guideShot(
        t,
        name: 'branches-3$suffix',
        screen: withExtrasPackage(const BranchManagementScreen()),
        api: _api,
        crumbs: [..._crumbs, 'Sơ đồ'],
        size: size,
        act: (t) async {
          await t.tap(find.text('Sơ đồ').first);
          await extrasSettle(t, 8);
        },
        marks: [
          GuideMark(1, [cardOf(find.text('Cơm Gà Nam — Trụ sở Quận 1').last)], pad: 2),
          GuideMark(2, [cardOf(find.text('Chi nhánh Quận 3').last), cardOf(find.text('Chi nhánh Thủ Đức').last)], pad: 2),
          GuideMark(3, [GuideMark.button(find.text('Mở tất cả')), GuideMark.button(find.text('Thu gọn'))], pad: 4),
        ],
      );
    });
  }
}
