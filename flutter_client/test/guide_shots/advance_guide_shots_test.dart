import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/hr_finance/hr_fin_common.dart';
import 'package:zkteco_flutter_client/screens/hr_finance/hr_finance_hub_screen.dart';

import 'guide_shot_kit.dart';
import 'hr_fin_guide_common.dart';

/// Ảnh cho bước hướng dẫn «Ứng lương» (id: advance).

const _crumbs = ['Tài chính', 'Ứng lương'];

/// Nút hành động (Duyệt / Chi / thu) trên dòng phiếu có tiêu đề [title].
Finder _rowAction(String title, String action) => find.descendant(
    of: find.ancestor(of: find.text(title), matching: find.byType(HrFinItemTile)).first, matching: find.text(action));

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('advance-1$suffix: tạo phiếu ứng lương', (t) async {
      await guideShot(
        t,
        name: 'advance-1$suffix',
        screen: hrFinHub(HrFinTab.advances),
        api: hrFinGuideApi(),
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await t.tap(find.text('Ứng lương').first);
          await t.pump(const Duration(milliseconds: 400));
          await hrFinPickEmployee(t, 'Phạm Thu Hà');
          await t.enterText(hrFinInputField('Số tiền xin ứng'), '2000000');
          await t.enterText(hrFinInputField('Lý do'), 'Đóng tiền nhà tháng này');
          await t.pump(const Duration(milliseconds: 300));
        },
        marks: [
          GuideMark(1, [hrFinInputField('Nhân viên')]),
          GuideMark(2, [hrFinInputField('Số tiền xin ứng')]),
          GuideMark(3, [find.byWidgetPredicate((w) => w is InputDecorator && w.decoration.labelText == 'Trả góp')]),
        ],
      );
    });

    testWidgets('advance-2$suffix: duyệt và chi ứng', (t) async {
      await guideShot(
        t,
        name: 'advance-2$suffix',
        screen: hrFinHub(HrFinTab.inbox),
        api: hrFinGuideApi(),
        crumbs: const ['Tài chính', 'Cần xử lý'],
        size: size,
        act: (t) async {
          await guideScrollTo(t, find.text('Ứng lương — Đóng học phí cho con'), alignment: 0.15);
        },
        marks: [
          GuideMark(1, [GuideMark.button(_rowAction('Ứng lương — Đóng học phí cho con', 'Duyệt'))]),
          GuideMark(2, [GuideMark.button(_rowAction('Ứng lương — Sửa xe', 'Chi / thu'))]),
        ],
      );
    });

    testWidgets('advance-3$suffix: theo dõi đã ứng / trừ lương', (t) async {
      await guideShot(
        t,
        name: 'advance-3$suffix',
        screen: hrFinHub(HrFinTab.advances),
        api: hrFinGuideApi(),
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await guideScrollTo(t, find.text('Đã chi trong tháng'), alignment: 0.1);
        },
        marks: [
          GuideMark(1, [find.text('Đã chi trong tháng'), find.text('Theo kỳ trừ + trả góp')], pad: 22),
          GuideMark(2, [GuideMark.button(find.text('Tất cả')), GuideMark.button(find.text('Từ chối / hủy'))]),
        ],
      );
    });
  }
}
