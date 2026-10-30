import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/cash_transaction_screen.dart';

import 'guide_shot_kit.dart';
import 'hr_fin_guide_common.dart';

/// Ảnh cho bước hướng dẫn «Thu chi quỹ» (id: cash).

const _crumbs = ['Tài chính', 'Sổ quỹ thu chi'];

Finder _input(String label) =>
    find.byWidgetPredicate((w) => w is InputDecorator && w.decoration.labelText == label);

/// Nút «Thu/Chi»: máy tính ở thanh trên, điện thoại là nút nổi.
Finder get _addButton => GuideMark.button(find.byIcon(Icons.add_circle_outline));

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('cash-1$suffix: danh sách thu chi', (t) async {
      await guideShot(
        t,
        name: 'cash-1$suffix',
        screen: const CashTransactionScreen(),
        api: hrFinGuideApi(),
        crumbs: _crumbs,
        size: size,
        marks: [
          GuideMark(1, [_addButton]),
          GuideMark(2, [find.text('Chi ứng lương — Võ Thị Mai')], pad: 10),
        ],
      );
    });

    testWidgets('cash-2$suffix: ghi phiếu thu / chi', (t) async {
      await guideShot(
        t,
        name: 'cash-2$suffix',
        screen: const CashTransactionScreen(),
        api: hrFinGuideApi(),
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await t.tap(_addButton);
          await t.pump(const Duration(milliseconds: 400));
          await t.tap(find.text('Chi').last);
          await t.pump(const Duration(milliseconds: 200));
          await t.tap(_input('Danh mục *'));
          await t.pump(const Duration(milliseconds: 400));
          await t.tap(find.text('Tiền điện nước').last);
          await t.pump(const Duration(milliseconds: 400));
          final amount = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Số tiền *');
          await t.enterText(amount, '1850000');
          final desc = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Mô tả *');
          await t.enterText(desc, 'Tiền điện tháng 9');
          await t.pump(const Duration(milliseconds: 300));
        },
        marks: [
          GuideMark(1, [find.ancestor(of: find.text('Thu'), matching: find.byWidgetPredicate((w) => w is SegmentedButton)).first]),
          GuideMark(2, [_input('Danh mục *')]),
          GuideMark(3, [_input('Số tiền *'), _input('Mô tả *')]),
        ],
      );
    });
  }
}
