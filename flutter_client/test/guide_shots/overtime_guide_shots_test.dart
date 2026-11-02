import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/overtime_screen.dart';

import 'guide_shot_kit.dart';
import 'hrm_extras_common.dart';

/// Ảnh cho bước hướng dẫn «Tăng ca: đăng ký, duyệt và cách tính tiền» (id: overtime).

String _day(int offset) => isoDay(DateTime.now().add(Duration(days: offset)));

final _overtimes = [
  {
    'id': 'o1', 'employeeName': 'Trần Thị Lan', 'date': _day(1), 'startTime': '17:00:00', 'endTime': '20:00:00',
    'totalHours': 3, 'status': 'Pending', 'reason': 'Tiệc đặt bàn 40 khách',
  },
  {
    'id': 'o2', 'employeeName': 'Lê Văn Minh', 'date': _day(1), 'startTime': '17:00:00', 'endTime': '21:00:00',
    'totalHours': 4, 'status': 'Pending', 'reason': 'Chuẩn bị nguyên liệu tiệc',
  },
  {
    'id': 'o3', 'employeeName': 'Phạm Thị Hoa', 'date': _day(-2), 'startTime': '18:00:00', 'endTime': '20:00:00',
    'totalHours': 2, 'status': 'Approved', 'reason': 'Kiểm kê cuối tháng',
  },
  {
    'id': 'o4', 'employeeName': 'Võ Minh Tuấn', 'date': _day(-5), 'startTime': '17:30:00', 'endTime': '19:30:00',
    'totalHours': 2, 'status': 'Rejected', 'reason': 'Dọn kho',
  },
];

final _api = guideApi({
  '/api/overtimes/pending': _overtimes.where((o) => o['status'] == 'Pending').toList(),
  '/api/overtimes/my-overtimes': [_overtimes[2]],
  '/api/overtimes/statistics': {'total': 4, 'approved': 1, 'rejected': 1, 'pending': 2, 'totalHours': 11},
  '/api/overtimes': _overtimes,
});

const _crumbs = ['Trang chủ', 'Tăng ca'];

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('overtime-1$suffix: đăng ký tăng ca', (t) async {
      await guideShot(
        t,
        name: 'overtime-1$suffix',
        screen: const OvertimeScreen(),
        api: _api,
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await t.tap(find.text('Đăng ký tăng ca').last);
          await extrasSettle(t);
          await t.enterText(fieldLabeled('Giờ bắt đầu (HH:mm) *'), '17:00');
          await t.enterText(fieldLabeled('Giờ kết thúc (HH:mm) *'), '20:00');
          await t.enterText(fieldLabeled('Lý do *'), 'Tiệc đặt bàn 40 khách');
        },
        marks: [
          GuideMark(1, [find.text('Chọn ngày')]),
          GuideMark(2, [fieldLabeled('Giờ bắt đầu (HH:mm) *'), fieldLabeled('Giờ kết thúc (HH:mm) *')]),
          GuideMark(3, [fieldLabeled('Lý do *')]),
          GuideMark(4, [GuideMark.button(find.text('Gửi yêu cầu'))]),
        ],
      );
    });

    testWidgets('overtime-2$suffix: quản lý duyệt / từ chối', (t) async {
      await guideShot(
        t,
        name: 'overtime-2$suffix',
        screen: const OvertimeScreen(),
        api: _api,
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await t.tap(find.widgetWithText(Tab, 'Chờ duyệt'));
          await extrasSettle(t);
        },
        marks: [
          GuideMark(1, [find.widgetWithText(Tab, 'Chờ duyệt')]),
          GuideMark(2, [find.byIcon(Icons.check_circle).first, find.byIcon(Icons.cancel).first], pad: 8),
        ],
      );
    });
  }
}
