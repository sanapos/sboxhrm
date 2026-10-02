import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/providers/theme_provider.dart';
import 'package:zkteco_flutter_client/screens/shift_templates_v2/st_common.dart';
import 'package:zkteco_flutter_client/screens/shift_templates_v2/st_editor.dart';
import 'package:zkteco_flutter_client/screens/shift_templates_v2/st_list_screen.dart';

/// Ca mẫu v2 với dữ liệu mẫu. Đặt SBOX_SHOT_DIR để lưu ảnh duyệt giao diện.
Future<void> _loadFonts() async {
  final fl = FontLoader('BeVietnamPro');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    fl.addFont(Future.value(ByteData.view(File('assets/fonts/BeVietnamPro-$f.ttf').readAsBytesSync().buffer)));
  }
  await fl.load();
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)))).load();
    }
  }
}

Map<String, dynamic> _shift(String id, String name, String code, String s, String e,
        {String type = 'Hành chính', String? ls, String? le, int brk = 0, bool active = true}) =>
    {
      'id': id, 'name': name, 'code': code, 'startTime': '$s:00', 'endTime': '$e:00', 'shiftType': type,
      'lunchBreakStartTime': ls == null ? null : '$ls:00', 'lunchBreakEndTime': le == null ? null : '$le:00',
      'breakTimeMinutes': brk, 'isActive': active, 'earlyCheckInMinutes': 45, 'lateGraceMinutes': 5,
      'maximumAllowedLateMinutes': 30, 'earlyLeaveGraceMinutes': 5, 'maximumAllowedEarlyLeaveMinutes': 30,
      'overtimeMinutesThreshold': 30, 'earlyOvertimeMinutesThreshold': 30, 'createdAt': '2026-01-01T00:00:00Z',
    };

final _shifts = [
  _shift('s1', 'Hành chính', 'HC', '08:00', '17:00', ls: '12:00', le: '13:00', brk: 60),
  _shift('s2', 'Ca sáng', 'CS', '06:00', '14:00', brk: 30),
  _shift('s3', 'Ca đêm', 'CD', '22:00', '06:00', type: 'Qua đêm', brk: 30),
  _shift('s4', 'Tăng ca tối', 'TC', '18:00', '21:00', type: 'Tăng ca'),
  _shift('s5', 'Ca gãy cũ', 'CG', '10:00', '21:00', ls: '14:00', le: '17:00', active: false),
];

Map<String, dynamic> _use(String id, {int sched = 0, int up = 0, int emps = 0, int lv = 0, int al = 0}) => {
      'shiftId': id, 'schedules': sched, 'upcomingSchedules': up, 'employees': emps, 'salaryLevels': lv,
      'allowances': al, 'staffingQuotas': 0, 'mealSessions': 0, 'hasData': sched > 0, 'canDelete': sched == 0,
      'lastUsedDate': sched > 0 ? '2026-09-30T00:00:00' : null,
      'dataSummary': sched > 0 ? '$sched lịch làm việc' : '',
    };

final _usage = [
  _use('s1', sched: 1240, up: 96, emps: 42, lv: 2),
  _use('s2', sched: 380, up: 24, emps: 12),
  _use('s3', sched: 150, up: 10, emps: 6, lv: 1),
  _use('s4', lv: 1, al: 1),
  _use('s5', sched: 60, emps: 4),
];

final _levels = [
  {'id': 'l1', 'shiftTemplateId': 's1', 'levelName': 'Thu ngân', 'rateType': 'fixed', 'fixedRate': 220000, 'isActive': true, 'employeeIds': ['e1', 'e2']},
  {'id': 'l2', 'shiftTemplateId': 's1', 'levelName': 'Quản lý ca', 'rateType': 'multiplier', 'multiplier': 1.5, 'isActive': true},
  {'id': 'l3', 'shiftTemplateId': 's3', 'levelName': 'Bảo vệ đêm', 'rateType': 'hourly', 'hourlyRate': 35000, 'isActive': true},
];

http.Response _ok(Object data) =>
    http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

final _client = MockClient((req) async {
  final p = req.url.path;
  if (p.endsWith('/shifts/templates/usage')) return _ok(_usage);
  if (p.endsWith('/shifts/templates')) return _ok(_shifts);
  if (p.endsWith('/shift-salary-levels')) return _ok({'items': _levels});
  if (p.endsWith('/employees')) return _ok({'items': []});
  return _ok({});
});

Future<void> _pump(WidgetTester tester, Widget home, Size size, String name, {Future<void> Function()? before}) async {
  final key = GlobalKey();
  Widget app() => RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeProvider().lightTheme,
          home: MediaQuery(data: MediaQueryData(size: size), child: home),
        ),
      );
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await http.runWithClient(() async {
    await tester.pumpWidget(app());
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (before != null) {
      await before();
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    expect(tester.takeException(), isNull);
  }, () => _client);
  final dir = Platform.environment['SBOX_SHOT_DIR'];
  if (dir != null) {
    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: size.width < 600 ? 2 : 1.25);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

void main() {
  setUpAll(_loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Tính giờ ca: qua đêm, nghỉ giữa ca, giờ làm thực', () {
    final hc = ShiftTpl.fromJson(_shifts[0]);
    expect(hc.workMinutes, 8 * 60);
    expect(hc.overnight, isFalse);
    final night = ShiftTpl.fromJson(_shifts[2]);
    expect(night.overnight, isTrue);
    expect(night.spanMinutes, 8 * 60);
    expect(night.workMinutes, 7 * 60 + 30);
    expect(night.type, ShiftKind.overnight);
    expect(StTime.insideShift(22 * 60, 6 * 60, 1 * 60, 2 * 60), isTrue);
    expect(StTime.insideShift(8 * 60, 17 * 60, 18 * 60, 19 * 60), isFalse);
  });

  test('Kiểm tra trước khi lưu', () {
    final s = ShiftTpl.fromJson(_shifts[0]);
    expect(s.validate(), isNull);
    s.end = s.start;
    expect(s.validate(), contains('trùng giờ ra'));
    s.end = 17 * 60;
    s.otBefore = 45;
    s.earlyCheckIn = 45;
    expect(s.validate(), contains('Nhận chấm sớm'));
    s.earlyCheckIn = 46;
    s.lunchStart = 18 * 60;
    s.lunchEnd = 19 * 60;
    expect(s.validate(), isNotNull);
    // Dữ liệu gửi API giữ đúng định dạng cũ
    final j = ShiftTpl.fromJson(_shifts[1]).toJson();
    expect(j['startTime'], '06:00:00');
    expect(j['lunchBreakStartTime'], isNull);
    expect(j['breakTimeMinutes'], 30);
    expect(j['shiftType'], 'Hành chính');
  });

  test('Mẫu nhanh ca đêm', () {
    final t = ShiftTpl(id: '', name: '', start: 0, end: 0);
    ShiftPreset.all.firstWhere((p) => p.code == 'CD').applyTo(t);
    expect(t.name, 'Ca đêm');
    expect(t.overnight, isTrue);
    expect(t.type, ShiftKind.overnight);
    expect(t.validate(), isNull);
  });

  testWidgets('Danh sách ca — máy tính', (t) async {
    await _pump(t, const ShiftTemplatesV2Screen(), const Size(1440, 1000), 'shift_list_desktop');
    expect(find.text('Ca đêm'), findsWidgets);
    expect(find.textContaining('Chưa phát sinh dữ liệu'), findsWidgets);
  });

  testWidgets('Danh sách ca — điện thoại', (t) async {
    await _pump(t, const ShiftTemplatesV2Screen(), const Size(390, 1500), 'shift_list_mobile');
  });

  testWidgets('Không xóa được ca đã có dữ liệu', (t) async {
    await _pump(t, const ShiftTemplatesV2Screen(), const Size(1440, 1000), 'shift_delete_blocked', before: () async {
      await t.tap(find.byIcon(Icons.more_vert_rounded).first);
      await t.pumpAndSettle();
      await t.tap(find.text('Xóa (đã có dữ liệu)'));
      await t.pumpAndSettle();
    });
    expect(find.textContaining('Không xóa được ca'), findsOneWidget);
  });

  testWidgets('Xóa ca chưa dùng: báo gỡ khỏi thiết lập lương', (t) async {
    await _pump(t, const ShiftTemplatesV2Screen(), const Size(1440, 1000), 'shift_delete_unused', before: () async {
      // Ca «Tăng ca tối» (thứ 3 sau sắp xếp theo giờ vào: 06h, 08h, 18h, 22h)
      final menus = find.byIcon(Icons.more_vert_rounded);
      await t.tap(menus.at(2));
      await t.pumpAndSettle();
      await t.tap(find.text('Xóa ca').last);
      await t.pumpAndSettle();
    });
    expect(find.textContaining('mức lương ca'), findsWidgets);
    expect(find.textContaining('phụ cấp theo ca'), findsOneWidget);
  });

  testWidgets('Sửa ca — máy tính', (t) async {
    final s = ShiftTpl.fromJson(_shifts[0]);
    await _pump(t, ShiftTemplateEditorPage(shift: s, usage: ShiftUsage(_usage[0])), const Size(1440, 1700), 'shift_editor_desktop');
    expect(find.text('Minh họa chấm công'), findsOneWidget);
    expect(find.text('Thu ngân'), findsOneWidget);
  });

  testWidgets('Thêm ca — điện thoại', (t) async {
    await _pump(t, const ShiftTemplateEditorPage(), const Size(390, 2300), 'shift_editor_mobile_new', before: () async {
      await t.ensureVisible(find.textContaining('Ca đêm'));
      await t.pump();
      await t.tap(find.textContaining('Ca đêm'));
      await t.pump();
      await t.tap(find.text('Xem'));
      await t.pump();
    });
    expect(find.text('Giờ ra ca (hôm sau)'), findsOneWidget);
  });
}
