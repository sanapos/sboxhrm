import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/providers/theme_provider.dart';
import 'package:zkteco_flutter_client/screens/shift_hub/my_schedule_view.dart';
import 'package:zkteco_flutter_client/screens/shift_hub/shift_hub_ui.dart';

/// Nạp phông thật: phông mặc định của test rộng hơn nên chữ tràn ngang không giống máy thật.
Future<void> _loadFonts() async {
  final fl = FontLoader('BeVietnamPro');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    fl.addFont(Future.value(ByteData.view(File('assets/fonts/BeVietnamPro-$f.ttf').readAsBytesSync().buffer)));
  }
  await fl.load();
  final root = Platform.environment['FLUTTER_ROOT'];
  final icons = root == null ? null : File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons != null && icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)))).load();
  }
}

/// «Lịch của tôi»: ngày đang chờ duyệt phải hiện ĐỦ các phiếu và không bảo nhân viên đăng ký lại.
void main() {
  setUpAll(_loadFonts);
  final today = ShiftUi.key(DateTime.now());
  final d1 = ShiftUi.key(DateTime.now().add(const Duration(days: 1)));
  final d2 = ShiftUi.key(DateTime.now().add(const Duration(days: 2)));

  const tpls = [
    {'id': 's1', 'name': 'Ca sáng', 'start': '07:00', 'end': '15:00', 'colorIndex': 0, 'active': true},
    {'id': 's2', 'name': 'Ca chiều', 'start': '15:00', 'end': '23:00', 'colorIndex': 1, 'active': true},
  ];

  Map<String, dynamic> payload() => {
        'templates': tpls,
        'employee': {'id': 'e0'},
        'today': today,
        'summary': {'shifts': 1, 'hours': 8, 'dayOff': 0, 'pendingRegistrations': 3, 'pendingLeaves': 0, 'pendingSwaps': 0},
        'incomingSwaps': const [],
        'days': [
          {
            'date': today,
            'isToday': true,
            'isPast': false,
            'schedule': {'shiftId': 's1', 'start': '07:00', 'end': '15:00'},
            'schedules': [
              {'shiftId': 's1', 'start': '07:00', 'end': '15:00'},
            ],
            // Hai phiếu cùng ngày: thêm Ca chiều và xin bỏ Ca sáng.
            'registrations': [
              {'id': 'r1', 'status': 'Pending', 'shiftId': 's2'},
              {'id': 'r2', 'status': 'Pending', 'shiftId': null, 'replaceShiftId': 's1'},
            ],
            'leaves': const [],
            'swaps': const [],
          },
          {
            // Ngày chưa có ca nhưng đã gửi đăng ký: không được nhắc «Bấm nút ⋯».
            'date': d1,
            'isToday': false,
            'isPast': false,
            'registrations': [
              {'id': 'r3', 'status': 'Pending', 'shiftId': 's1'},
            ],
            'leaves': const [],
            'swaps': const [],
          },
          {
            // Ngày trống thật sự: vẫn nhắc cách đăng ký.
            'date': d2,
            'isToday': false,
            'isPast': false,
            'registrations': const [],
            'leaves': const [],
            'swaps': const [],
          },
        ],
      };

  final client = MockClient((req) async {
    final body = req.url.path.endsWith('/api/shift-hub/my')
        ? {'isSuccess': true, 'data': payload()}
        : {'isSuccess': true, 'data': const <String, dynamic>{}};
    return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
  });

  Future<void> pump(WidgetTester tester, {Size size = const Size(420, 1800)}) async {
    await tester.binding.setSurfaceSize(size);
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeProvider().lightTheme,
        home: const Scaffold(body: MyScheduleView()),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }, () => client);
  }

  setUp(() => SharedPreferences.setMockInitialValues({'access_token': 'x'}));

  testWidgets('một ngày hai phiếu chờ duyệt thì hiện đủ cả hai', (tester) async {
    await pump(tester);
    expect(find.textContaining('Đăng ký Ca chiều'), findsOneWidget);
    expect(find.textContaining('Xin bỏ Ca sáng'), findsOneWidget);
  });

  testWidgets('ngày đã gửi đăng ký không nhắc «Bấm nút ⋯» nữa', (tester) async {
    await pump(tester);
    // Chỉ còn đúng một ngày trống thật sự được nhắc cách đăng ký.
    expect(find.textContaining('Bấm nút'), findsOneWidget);
  });

  testWidgets('hộp thao tác hiện đủ mọi dòng trong màn hình điện thoại', (tester) async {
    // Màn Sunmi V2s: 360×720 dp. Ngày hôm nay có 1 ca + 2 phiếu chờ ⇒ 6 dòng thao tác.
    await pump(tester, size: const Size(360, 720));
    await tester.tap(find.byTooltip('Thao tác').first);
    await tester.pumpAndSettle();

    const labels = [
      'Đăng ký thêm ca / đổi ca',
      'Xin nghỉ phép',
      'Đổi ca với đồng nghiệp',
      'Xin bỏ Ca sáng',
      'Huỷ «Xin bỏ Ca sáng»',
      'Huỷ «Đăng ký Ca chiều»',
    ];
    for (final l in labels) {
      final f = find.text(l);
      expect(f, findsOneWidget, reason: 'thiếu dòng «$l»');
      final r = tester.getRect(f);
      expect(r.bottom <= 720, isTrue, reason: 'dòng «$l» bị cắt dưới đáy màn hình (${r.bottom})');
      expect(r.top >= 0, isTrue, reason: 'dòng «$l» bị cắt trên đỉnh màn hình (${r.top})');
    }
  });
}
