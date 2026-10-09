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
import 'package:zkteco_flutter_client/screens/shift_hub/my_schedule_view.dart';
import 'package:zkteco_flutter_client/screens/shift_hub/schedule_board_view.dart';
import 'package:zkteco_flutter_client/screens/shift_hub/shift_hub_ui.dart';

/// Ca làm việc trên điện thoại / máy tính với dữ liệu mẫu. SBOX_SHOT_DIR = lưu ảnh duyệt giao diện.
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

final _mon = ShiftUi.monday(DateTime.now());
final _days = [for (var i = 0; i < 7; i++) ShiftUi.key(_mon.add(Duration(days: i)))];
final _today = ShiftUi.key(DateTime.now());

const _tpls = [
  {'id': 's1', 'name': 'Ca sáng', 'start': '07:00', 'end': '15:00', 'colorIndex': 0, 'active': true},
  {'id': 's2', 'name': 'Ca chiều', 'start': '15:00', 'end': '23:00', 'colorIndex': 1, 'active': true},
  {'id': 's3', 'name': 'Ca gãy trưa', 'start': '10:00', 'end': '14:00', 'colorIndex': 2, 'active': true},
];

const _names = [
  ('Trần Văn Quân', 'Bếp'), ('Lê Thị Thanh Tú', 'Phục vụ'), ('Phạm Hà', 'Phục vụ'), ('Nguyễn Minh', 'Thu ngân'),
  ('Đỗ Hoàng Long', 'Bếp'), ('Võ Ngọc Anh', 'Pha chế'), ('Bùi Khánh Linh', 'Phục vụ'), ('Hồ Đức Thịnh', 'Bảo vệ'),
  ('Lý Mỹ Duyên', 'Pha chế'), ('Trương Gia Bảo', 'Phục vụ'),
];

Map<String, dynamic> _board() {
  final emps = <Map<String, dynamic>>[];
  for (var i = 0; i < _names.length; i++) {
    final cells = <String, dynamic>{};
    for (var d = 0; d < 7; d++) {
      final k = (i + d) % 6;
      if (i == 9) continue; // chưa xếp cả tuần
      if (k == 5) {
        cells[_days[d]] = {'isDayOff': true, 'scheduleId': 'x$i$d'};
      } else if (k == 4 && d == 2) {
        cells[_days[d]] = {'registration': {'id': 'r$i', 'shiftId': 's2', 'isDayOff': false}};
      } else if (k == 3 && d == 4) {
        cells[_days[d]] = {
          'shiftId': 's1', 'start': '07:00', 'end': '15:00', 'scheduleId': 'x$i$d',
          'leave': {'status': 'Approved', 'type': 'AnnualLeave'},
        };
      } else {
        final sid = ['s1', 's2', 's1', 's2', 's3'][k];
        final t = _tpls.firstWhere((t) => t['id'] == sid);
        cells[_days[d]] = {
          'shiftId': sid, 'start': t['start'], 'end': t['end'], 'scheduleId': 'x$i$d',
          if (i == 2 && d == 1) 'moreShifts': 1,
        };
      }
    }
    emps.add({
      'id': 'e$i', 'name': _names[i].$1, 'code': 'NV${(i + 1).toString().padLeft(3, '0')}', 'department': _names[i].$2,
      'position': _names[i].$2, 'cells': cells, 'totals': {'hours': i == 9 ? 0 : 40 - i},
    });
  }
  final cov = <Map<String, dynamic>>[];
  for (final d in _days) {
    for (final t in _tpls) {
      final eff = emps.where((e) => ((e['cells'] as Map)[d] as Map?)?['shiftId'] == t['id']).length;
      final min = t['id'] == 's3' ? 1 : 3, max = t['id'] == 's3' ? 2 : 4;
      final st = eff < min ? 'short' : eff == min ? 'tight' : eff == max ? 'full' : eff > max ? 'over' : 'ok';
      cov.add({'date': d, 'shiftId': t['id'], 'effective': eff, 'scheduled': eff, 'min': min, 'max': max, 'hasQuota': true,
        'status': st, 'onLeave': 0, 'pending': d == _days[2] ? 1 : 0});
    }
  }
  return {
    'days': _days, 'today': _today, 'templates': _tpls, 'coverage': cov, 'employees': emps,
    'departments': ['Bếp', 'Phục vụ', 'Thu ngân', 'Pha chế', 'Bảo vệ'],
    'summary': {'employees': 10, 'unscheduled': 1, 'plannedHours': 356, 'shortSlots': 4, 'pendingRegistrations': 2, 'pendingLeaves': 1},
  };
}

Map<String, dynamic> _my() => {
      'templates': _tpls,
      'employee': {'id': 'e0'},
      'summary': {'shifts': 5, 'hours': 40, 'dayOff': 1, 'pendingRegistrations': 1, 'pendingLeaves': 0, 'pendingSwaps': 1},
      'incomingSwaps': [
        {'id': 'w1', 'otherName': 'Lê Thị Thanh Tú', 'theirShift': 'Ca chiều', 'theirDate': _days[3], 'myShift': 'Ca sáng', 'myDate': _days[3], 'reason': 'Bận việc gia đình'},
      ],
      'days': [
        for (var d = 0; d < 7; d++)
          {
            'date': _days[d],
            'isToday': _days[d] == _today,
            'isPast': _days[d].compareTo(_today) < 0,
            if (d != 5 && d != 6) 'schedule': {'shiftId': d.isEven ? 's1' : 's2', 'start': d.isEven ? '07:00' : '15:00', 'end': d.isEven ? '15:00' : '23:00'},
            if (d == 5) 'schedule': {'isDayOff': true},
            if (d == 6) 'registration': {'id': 'r9', 'status': 'Pending', 'shiftId': 's3'},
            'leaves': [],
            'swaps': d == 3 ? [{'otherName': 'Phạm Hà', 'status': 'Pending'}] : [],
          },
      ],
    };

http.Response _ok(Object data) =>
    http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

final _client = MockClient((req) async {
  final p = req.url.path;
  if (p.endsWith('/api/shift-hub/board')) return _ok(_board());
  if (p.endsWith('/api/shift-hub/my')) return _ok(_my());
  if (p.endsWith('/api/shift-hub/counts')) return _ok({'total': 3});
  return http.Response(jsonEncode({'isSuccess': false, 'message': 'not mocked $p'}), 200);
});

Future<void> _pump(WidgetTester tester, Widget home, Size size, String name, {Future<void> Function(WidgetTester)? after}) async {
  final key = GlobalKey();
  Widget app(Size s) => RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeProvider().lightTheme,
          home: MediaQuery(data: MediaQueryData(size: s), child: Scaffold(body: home)),
        ),
      );
  Future<void> setSize(Size s) async {
    await tester.binding.setSurfaceSize(s);
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1;
  }

  await http.runWithClient(() async {
    await setSize(size);
    await tester.pumpWidget(app(size));
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (after != null) await after(tester);
    expect(tester.takeException(), isNull);
    var extent = 0.0;
    for (final e in find.byType(Scrollable).evaluate()) {
      final st = (e as StatefulElement).state as ScrollableState;
      if (st.position.axis == Axis.vertical && st.position.maxScrollExtent > extent) extent = st.position.maxScrollExtent;
    }
    if (extent > 0) {
      final t = Size(size.width, size.height + extent);
      await setSize(t);
      await tester.pumpWidget(app(t));
      if (after != null) await after(tester);
      for (var i = 0; i < 4; i++) {
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

const _phone = Size(390, 844);
const _desk = Size(1440, 900);

void main() {
  setUpAll(_loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Bảng xếp ca — điện thoại', (t) async {
    await _pump(t, const ScheduleBoardView(), _phone, 'shift_board_mobile');
  });

  testWidgets('Bảng xếp ca — máy tính', (t) async {
    await _pump(t, const ScheduleBoardView(), _desk, 'shift_board_desktop');
  });

  testWidgets('Lịch của tôi — điện thoại', (t) async {
    await _pump(t, const MyScheduleView(), _phone, 'shift_my_mobile');
  });

  testWidgets('Bảng xếp ca — điện thoại, xem từng ngày', (t) async {
    await _pump(t, const ScheduleBoardView(), _phone, 'shift_board_day_mobile', after: (tester) async {
      await tester.tap(find.text('Từng ngày'));
      await tester.pumpAndSettle();
    });
    expect(find.textContaining('người · cần'), findsWidgets);
  });

  testWidgets('Bảng xếp ca — máy tính bảng', (t) async {
    await _pump(t, const ScheduleBoardView(), const Size(820, 1180), 'shift_board_tablet');
  });

  testWidgets('Bảng xếp ca — máy tính bảng ngang', (t) async {
    await _pump(t, const ScheduleBoardView(), const Size(1180, 820), 'shift_board_tablet_landscape');
  });
}
