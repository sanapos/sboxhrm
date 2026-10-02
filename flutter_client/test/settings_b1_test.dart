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
import 'package:zkteco_flutter_client/screens/ai_settings_screen.dart';
import 'package:zkteco_flutter_client/screens/notification_settings_screen.dart';
import 'package:zkteco_flutter_client/screens/system_settings_screen.dart';
import 'package:zkteco_flutter_client/widgets/settings/settings_page.dart';

/// Thiết lập B1: Tham số hệ thống, Thông báo, Trợ lý AI. Đặt SBOX_SHOT_DIR để lưu ảnh duyệt.
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

final _app = {'day_end_time': '04:00:00', 'min_work_day_percent': '80', 'min_half_day_hours': '1', 'attendance_approval_levels': '2'};

final _prefs = [
  for (final (code, name, on) in [
    ('attendance', 'Chấm công', true),
    ('device', 'Thiết bị', true),
    ('leave', 'Nghỉ phép', true),
    ('approval', 'Phê duyệt', true),
    ('payroll', 'Lương & Phiếu lương', true),
    ('task', 'Công việc', false),
    ('internal_comm', 'Truyền thông nội bộ', false),
    ('pos', 'POS', true),
    ('system', 'Hệ thống', true),
  ])
    {'categoryCode': code, 'categoryDisplayName': name, 'categoryDescription': '', 'isEnabled': on, 'displayOrder': 0},
];

final _ai = {
  'enabled': true,
  'model': 'gemini-2.5-flash',
  'maxOutputTokens': 2048,
  'temperature': 0.7,
  'isConfigured': true,
  'apiKeys': ['AIza••••Q3k', 'AIza••••x9P'],
  'keyStatus': [
    {'key': 'AIza••••x9P', 'coolingUntil': DateTime.now().add(const Duration(hours: 2)).toUtc().toIso8601String()},
  ],
};

http.Response _ok(Object? data) =>
    http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

final _client = MockClient((req) async {
  final p = req.url.path;
  if (p.contains('/settings/app/')) {
    final k = p.split('/').last;
    return _app.containsKey(k) ? _ok({'key': k, 'value': _app[k]}) : http.Response(jsonEncode({'isSuccess': false, 'message': 'not found'}), 404);
  }
  if (p.endsWith('/notification-preferences')) return _ok(_prefs);
  if (p.endsWith('/ai/config')) return _ok(_ai);
  return http.Response(jsonEncode({'isSuccess': false}), 200, headers: {'content-type': 'application/json'});
});

Future<void> _pump(WidgetTester tester, Widget home, Size size, String name, {Future<void> Function()? before}) async {
  final key = GlobalKey();
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await http.runWithClient(() async {
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeProvider().lightTheme,
        home: MediaQuery(data: MediaQueryData(size: size), child: Scaffold(body: home)),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (before != null) {
      await before();
      await tester.pumpAndSettle();
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
  tearDown(() => SettingsLeaveGuard.set(null));

  test('Tham số hệ thống: đọc / ghi / kiểm tra', () {
    final p = SystemParams.fromSettings({'day_end_time': '05:30:00', 'min_hours_for_work_day': '6', 'leave_approval_levels': '9'});
    expect(p.dayEndText, '05:30');
    expect(p.minPercent, 75); // 6h / 8h — chuyển từ khóa cũ
    expect(p.leaveLevels, 3); // giới hạn 1–3
    final s = p.toSettings();
    expect(s['day_end_time'], '05:30:00');
    expect(s.containsKey('rounding_rule'), isFalse); // không ghi tham số chưa dùng
    expect(s.containsKey('payroll_cutoff_day'), isFalse);
    expect((p.copy()..minPercent = 120).validate(), isNotNull);
    expect(p == p.copy(), isTrue);
  });

  test('Nhóm thông báo: mã lạ vào Hệ thống', () {
    expect(NotifGroup.of('payroll').title, 'Lương & tài chính');
    expect(NotifGroup.of('xyz').title, 'Hệ thống');
  });

  testWidgets('Tham số hệ thống — có thay đổi chưa lưu', (t) async {
    await _pump(t, const SystemSettingsScreen(canEditOverride: true), const Size(1200, 1500), 'b1_system_desktop', before: () async {
      await t.tap(find.text('Thập phân (0,1 – 1)'));
    });
    expect(find.text('Có thay đổi chưa lưu'), findsOneWidget);
    expect(SettingsLeaveGuard.active, isTrue);
    expect(find.textContaining('Làm 6,5h'), findsOneWidget);
  });

  testWidgets('Tham số hệ thống — điện thoại', (t) async {
    await _pump(t, const SystemSettingsScreen(canEditOverride: true), const Size(390, 2000), 'b1_system_mobile');
    expect(find.textContaining('trước 04:00 tính cho ngày hôm trước'), findsOneWidget);
  });

  testWidgets('Thông báo', (t) async {
    await _pump(t, const NotificationSettingsScreen(showPushCard: false), const Size(1200, 1500), 'b1_notifications');
    expect(find.text('Đơn từ & phê duyệt'), findsOneWidget);
    expect(find.textContaining('Đang nhận 7/9'), findsOneWidget);
  });

  testWidgets('Trợ lý AI', (t) async {
    await _pump(t, const AiSettingsScreen(canEditOverride: true), const Size(1200, 1500), 'b1_ai');
    expect(find.textContaining('dùng 2 khóa riêng'), findsOneWidget);
    expect(find.textContaining('Hết lượt'), findsOneWidget);
  });
}
