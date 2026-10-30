import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/hr_finance/hr_fin_common.dart';
import 'package:zkteco_flutter_client/screens/hr_finance/hr_finance_hub_screen.dart';

import 'guide_shot_kit.dart';
import 'hr_fin_guide_common.dart';

/// Ảnh cho bước hướng dẫn «Thưởng phạt» (id: bonus_ticket).

const _crumbs = ['Tài chính', 'Thưởng & phạt'];

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('bonus-ticket-1$suffix: nút tạo thưởng / phạt', (t) async {
      await guideShot(
        t,
        name: 'bonus-ticket-1$suffix',
        screen: hrFinHub(HrFinTab.rewards),
        api: hrFinGuideApi(),
        crumbs: _crumbs,
        size: size,
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Thưởng / phạt'))]),
          GuideMark(2, [GuideMark.button(find.text('Tất cả')), GuideMark.button(find.text('Phạt'))]),
        ],
      );
    });

    testWidgets('bonus-ticket-2$suffix: nhân viên, số tiền, nội dung', (t) async {
      await guideShot(
        t,
        name: 'bonus-ticket-2$suffix',
        screen: hrFinHub(HrFinTab.rewards),
        api: hrFinGuideApi(),
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await t.tap(find.text('Thưởng / phạt'));
          await t.pump(const Duration(milliseconds: 400));
          await hrFinPickEmployee(t, 'Trần Minh Khoa');
          await t.enterText(hrFinInputField('Số tiền'), '500000');
          await t.enterText(hrFinInputField('Nội dung'), 'Khách hàng khen trên fanpage');
          await t.pump(const Duration(milliseconds: 300));
        },
        marks: [
          GuideMark(1, [hrFinInputField('Nhân viên')]),
          GuideMark(2, [hrFinInputField('Số tiền')]),
          GuideMark(3, [hrFinInputField('Nội dung')]),
        ],
      );
    });

    testWidgets('bonus-ticket-3$suffix: duyệt thưởng', (t) async {
      await guideShot(
        t,
        name: 'bonus-ticket-3$suffix',
        screen: hrFinHub(HrFinTab.inbox),
        api: hrFinGuideApi(),
        crumbs: const ['Tài chính', 'Cần xử lý'],
        size: size,
        act: (t) async {
          final row = find.text('Doanh số vượt chỉ tiêu tháng');
          await guideScrollTo(t, row, alignment: 0.3);
          final tile = find.ancestor(of: row, matching: find.byType(HrFinItemTile)).first;
          final approve = find.descendant(of: tile, matching: find.text('Duyệt'));
          await t.tap(approve.evaluate().isNotEmpty ? approve.first : tile);
          await t.pump(const Duration(milliseconds: 400));
        },
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Cộng vào lương').last), GuideMark.button(find.text('Chi tiền mặt').last)]),
          GuideMark(2, [GuideMark.button(find.text('Duyệt').last)]),
        ],
      );
    });
  }
}
