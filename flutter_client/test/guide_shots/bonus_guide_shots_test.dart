import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/hr_finance/hr_fin_common.dart';
import 'package:zkteco_flutter_client/screens/hr_finance/hr_finance_hub_screen.dart';

import 'guide_shot_kit.dart';
import 'hr_fin_guide_common.dart';

/// Ảnh cho bước hướng dẫn «Thưởng (chính sách)» (id: bonus) — tab Thưởng & phạt của
/// Tài chính nhân sự, dữ liệu mẫu trong hr_fin_guide_common.dart.

const _crumbs = ['Tài chính nhân sự', 'Thưởng & phạt'];

Finder _segment(String label) => find.descendant(
    of: find.byWidgetPredicate((w) => w.runtimeType.toString().startsWith('HrFinSegment')), matching: find.text(label));

/// Khung có nền / viền gần nhất chứa [f] (ô KPI, thẻ).
Finder _box(Finder f) => find
    .ancestor(of: f, matching: find.byWidgetPredicate((w) => w is DecoratedBox || w is Material || w is Card))
    .first;

Finder _tile(String title) => find.ancestor(of: find.text(title), matching: find.byType(HrFinItemTile)).first;

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = size.width < 600;

    testWidgets('bonus-1$suffix: lọc thưởng, lý do rõ ràng', (t) async {
      await guideShot(
        t,
        name: 'bonus-1$suffix',
        screen: hrFinHub(HrFinTab.rewards),
        api: hrFinGuideApi(),
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await guideScrollTo(t, _segment('Thưởng'), alignment: mobile ? 0.15 : 0.3);
          await t.tap(_segment('Thưởng'));
          await t.pump(const Duration(milliseconds: 300));
        },
        marks: [
          GuideMark(1, [GuideMark.button(_segment('Thưởng'))]),
          GuideMark(2, [_tile('Khách hàng khen trên fanpage'), _tile('Hoàn thành xuất sắc kiểm kê')], pad: 4),
        ],
      );
    });

    testWidgets('bonus-2$suffix: duyệt thưởng trước khi tính lương', (t) async {
      await guideShot(
        t,
        name: 'bonus-2$suffix',
        screen: hrFinHub(HrFinTab.rewards),
        api: hrFinGuideApi(),
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await guideScrollTo(t, find.text('Thưởng đã duyệt'), alignment: 0.05);
          await t.tap(_segment('Thưởng'));
          await t.pump(const Duration(milliseconds: 300));
        },
        marks: [
          GuideMark(1, [_box(find.text('Thưởng đã duyệt'))], pad: 4),
          GuideMark(2, [_tile('Doanh số vượt chỉ tiêu tháng')], pad: 4),
        ],
      );
    });
  }
}
