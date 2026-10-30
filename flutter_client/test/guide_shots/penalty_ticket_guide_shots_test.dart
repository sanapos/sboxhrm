import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/hr_finance/hr_fin_common.dart';
import 'package:zkteco_flutter_client/screens/hr_finance/hr_finance_hub_screen.dart';
import 'package:zkteco_flutter_client/screens/penalty_settings_screen.dart';

import 'guide_shot_kit.dart';
import 'hr_fin_guide_common.dart';

/// Ảnh cho bước hướng dẫn «Phiếu phạt đi trễ / về sớm» (id: penalty_ticket).

Finder _section(String title) => GuideMark.within(find.text(title), 'SettingsSection');

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('penalty-ticket-1$suffix: mức phạt theo bậc phút', (t) async {
      await guideShot(
        t,
        name: 'penalty-ticket-1$suffix',
        screen: const PenaltySettingsScreen(),
        api: hrFinGuideApi(),
        crumbs: const ['Cài đặt', 'Phạt'],
        size: size,
        act: (t) async {
          await guideScrollTo(t, find.text('Đi trễ'), alignment: 0.05);
        },
        marks: [
          GuideMark(1, [_section('Đi trễ')]),
          GuideMark(2, [_section('Về sớm')]),
        ],
      );
    });

    testWidgets('penalty-ticket-2$suffix: phiếu phạt tự động từ chấm công', (t) async {
      await guideShot(
        t,
        name: 'penalty-ticket-2$suffix',
        screen: hrFinHub(HrFinTab.rewards),
        api: hrFinGuideApi(),
        crumbs: const ['Tài chính', 'Thưởng & phạt'],
        size: size,
        act: (t) async {
          await guideScrollTo(t, find.text('Phiếu phạt tự động'), alignment: 0.15);
          await t.tap(find.text('Phiếu phạt tự động'));
          await t.pump(const Duration(milliseconds: 300));
        },
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Phiếu phạt tự động'))]),
          GuideMark(2, [find.ancestor(of: find.text('Đi trễ 25 phút'), matching: find.byType(HrFinItemTile)).first]),
        ],
      );
    });

    testWidgets('penalty-ticket-3$suffix: duyệt / hủy phiếu phạt', (t) async {
      await guideShot(
        t,
        name: 'penalty-ticket-3$suffix',
        screen: hrFinHub(HrFinTab.inbox),
        api: hrFinGuideApi(),
        crumbs: const ['Tài chính', 'Cần xử lý'],
        size: size,
        act: (t) async {
          final tile = find.ancestor(of: find.text('Đi trễ 25 phút'), matching: find.byType(HrFinItemTile)).first;
          final approve = find.descendant(of: tile, matching: find.text('Duyệt'));
          await t.tap(approve.evaluate().isNotEmpty ? approve.first : tile);
          await t.pump(const Duration(milliseconds: 400));
        },
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Hủy phiếu').last)]),
          GuideMark(2, [GuideMark.button(find.text('Duyệt').last)]),
        ],
      );
    });
  }
}
