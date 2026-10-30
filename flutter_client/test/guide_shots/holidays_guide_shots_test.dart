import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:zkteco_flutter_client/screens/holiday_settings_screen.dart';

import 'guide_shot_kit.dart';

/// Ảnh cho bước hướng dẫn «Ngày lễ & ngày nghỉ đặc biệt» (id: holidays).
/// Danh sách năm nay có sẵn các ngày lễ dương lịch, còn thiếu Tết âm lịch + Giỗ Tổ →
/// màn hiện nút «Thêm … ngày lễ chuẩn» (tính năng chính cần hướng dẫn).

String _iso(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}T00:00:00';

List<Map<String, Object?>> _holidays() {
  final year = DateTime.now().year;
  var id = 0;
  return [
    for (final p in HolidayPreset.all)
      if (!p.lunar)
        {
          'id': 'h${++id}',
          'name': p.name,
          'date': _iso(p.dateIn(year)),
          'category': p.category,
          'salaryRate': p.rate,
          'isRecurring': true,
        },
    {
      'id': 'h${++id}',
      'name': 'Kỷ niệm thành lập cửa hàng',
      'date': _iso(DateTime(year, 8, 15)),
      'category': 'Ngày nghỉ công ty',
      'salaryRate': 2.0,
      'isRecurring': true,
    },
  ];
}

MockClient _api() => guideApi({
      '/api/settings/holidays': _holidays(),
    });

const _crumbs = ['Cài đặt', 'Ngày lễ'];

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('holidays-1$suffix: danh sách, thêm ngày lễ chuẩn', (t) async {
      await guideShot(
        t,
        name: 'holidays-1$suffix',
        screen: const HolidaySettingsScreen(),
        api: _api(),
        crumbs: _crumbs,
        size: size,
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Thêm ngày lễ'))]),
          GuideMark(2, [GuideMark.button(find.textContaining('ngày lễ chuẩn'))]),
        ],
      );
    });

    testWidgets('holidays-2$suffix: tên, ngày, hệ số lương', (t) async {
      await guideShot(
        t,
        name: 'holidays-2$suffix',
        screen: const HolidaySettingsScreen(),
        api: _api(),
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await t.tap(find.text('Thêm ngày lễ'));
          await t.pump(const Duration(milliseconds: 500));
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
          await t.pump(const Duration(milliseconds: 300));
          await t.enterText(find.widgetWithText(TextField, 'Tên ngày lễ *'), 'Liên hoan cuối năm');
          await t.tap(find.text('x2'));
          await t.pump(const Duration(milliseconds: 300));
        },
        marks: [
          GuideMark(1, [find.widgetWithText(TextField, 'Tên ngày lễ *'), GuideMark.within(find.text('Ngày'), 'InputDecorator')]),
          GuideMark(2, [GuideMark.within(find.text('Lặp lại hằng năm'), 'SwitchListTile')]),
          GuideMark(3, [find.text('Hệ số lương khi đi làm ngày này'), find.text('x4')]),
        ],
      );
    });
  }
}
