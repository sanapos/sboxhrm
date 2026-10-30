import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zkteco_flutter_client/screens/leave_report_screen.dart';
import 'package:zkteco_flutter_client/widgets/page_top_actions.dart';

import '../fixtures/hr_reports_fixture.dart';
import 'guide_shot_kit.dart';

/// Ảnh cho bước hướng dẫn «Cách xem báo cáo HRM» (id: reports) — dùng báo cáo
/// nghỉ phép làm ví dụ, dữ liệu từ test/fixtures/hr_reports_fixture.dart.

MockClient _api() => MockClient((req) async {
      final body = hrReportsResponse(req.method, req.url.path, req.url.queryParameters) ?? {'isSuccess': true, 'data': []};
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });

const _crumbs = ['Báo cáo nhân sự', 'Báo cáo nghỉ phép'];

void _dump(String tag) {
  if (Platform.environment['GUIDE_DUMP'] != '1') return;
  // ignore: avoid_print
  print('DUMP $tag ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().take(120).toList()}');
}

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('reports-1$suffix: chọn kỳ, lọc', (t) async {
      await guideShot(
        t,
        name: 'reports-1$suffix',
        screen: const LeaveReportScreen(),
        api: _api(),
        crumbs: _crumbs,
        size: size,
        act: (t) async => _dump('report'),
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Hôm nay')), GuideMark.button(find.text(size.width < 600 ? 'Tuần trước' : 'Tùy chọn khác'))]),
          GuideMark(2, [GuideMark.within(find.text('Mọi trạng thái').first, 'DropdownButton<int?>'), find.text('Tìm nhân viên...')], pad: 8),
          GuideMark(3, [GuideMark.button(find.text('Áp dụng'))]),
        ],
      );
    });

    testWidgets('reports-2$suffix: xem chi tiết, xuất Excel', (t) async {
      final mobile = size.width < 600;
      await guideShot(
        t,
        name: 'reports-2$suffix',
        screen: const LeaveReportScreen(),
        api: _api(),
        crumbs: _crumbs,
        size: size,
        act: (t) async => guideScrollTo(t, find.text('Chi tiết'), alignment: mobile ? 0.15 : 0.35),
        marks: [
          // Máy tính: nút Excel trên thanh đầu trang; điện thoại: gom trong nút thao tác góc dưới.
          GuideMark(1, [if (mobile) find.byType(PageTopActionsFab) else GuideMark.button(find.text('Excel'))]),
          GuideMark(2, [GuideMark.button(find.text('Chi tiết')), GuideMark.button(find.text('Theo NV'))]),
          GuideMark(3, [find.text('Nguyễn Văn An').last, find.text('Phép năm · Về quê'), find.text('4.0 ngày')], pad: 10),
        ],
      );
    });
  }
}
