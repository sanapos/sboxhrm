import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zkteco_flutter_client/screens/penalty_report_screen.dart';
import 'package:zkteco_flutter_client/screens/penalty_settings_screen.dart';
import 'package:zkteco_flutter_client/widgets/page_top_actions.dart';

import '../fixtures/hr_reports_fixture.dart';
import 'guide_shot_kit.dart';
import 'hr_fin_guide_common.dart';

/// Ảnh cho bước hướng dẫn «Chính sách phạt» (id: penalty).

MockClient _reportApi() => MockClient((req) async {
      final body = hrReportsResponse(req.method, req.url.path, req.url.queryParameters) ?? {'isSuccess': true, 'data': []};
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });

/// Thẻ (khung có nền) gần nhất chứa [f].
Finder _box(Finder f) =>
    find.ancestor(of: f, matching: find.byWidgetPredicate((w) => w is DecoratedBox || w is Material || w is Card)).first;

Finder _tile(String label) => GuideMark.within(find.text(label), 'SettingsTile');

void _dump(String tag) {
  if (Platform.environment['GUIDE_DUMP'] != '1') return;
  // ignore: avoid_print
  print('DUMP $tag ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().take(140).toList()}');
}

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = size.width < 600;

    testWidgets('penalty-1$suffix: quên chấm, nghỉ không phép, cách thu', (t) async {
      await guideShot(
        t,
        name: 'penalty-1$suffix',
        screen: const PenaltySettingsScreen(),
        api: hrFinGuideApi(),
        crumbs: const ['Cài đặt', 'Phạt'],
        size: size,
        act: (t) async => guideScrollTo(t, find.text('Vi phạm khác & cách thu'), alignment: 0.05),
        marks: [
          GuideMark(1, [_tile('Quên chấm công'), _tile('Nghỉ không phép')], pad: 2),
          GuideMark(2, [_tile('Cách thu tiền phạt'), _tile('Tự duyệt phạt sau kết ca')], pad: 2),
        ],
      );
    });

    testWidgets('penalty-2$suffix: báo cáo phạt', (t) async {
      await guideShot(
        t,
        name: 'penalty-2$suffix',
        screen: const PenaltyReportScreen(),
        api: _reportApi(),
        crumbs: const ['Báo cáo nhân sự', 'Báo cáo phạt'],
        size: size,
        act: (t) async {
          _dump('penalty-report');
          await guideScrollTo(t, find.text('Tổng phiếu'), alignment: mobile ? 0.1 : 0.15);
        },
        marks: [
          GuideMark(1, [_box(find.text('Tổng tiền phạt')), _box(find.text('Tiền đã duyệt'))], pad: 2),
          GuideMark(2, [_box(find.text('Theo loại vi phạm'))], pad: 2),
          GuideMark(3, [if (mobile) find.byType(PageTopActionsFab) else GuideMark.button(find.text('Excel'))]),
        ],
      );
    });
  }
}
