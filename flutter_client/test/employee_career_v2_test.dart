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
import 'package:zkteco_flutter_client/screens/employee_career_v2/ec_forms.dart';
import 'package:zkteco_flutter_client/screens/employee_career_v2/ec_screen.dart';

/// Quá trình công tác v2 với dữ liệu mẫu. Đặt SBOX_SHOT_DIR để lưu ảnh duyệt giao diện.
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

Map<String, dynamic> _ev(String kind, String date, String title,
        {String? sub, String source = 'record', num? amount, String? decision, String? issuer, bool editable = false, List<String> att = const []}) =>
    {
      'key': '$kind$date', 'kind': kind, 'date': date, 'title': title, 'subtitle': sub, 'source': source, 'amount': amount,
      'decisionNumber': decision, 'issuedBy': issuer, 'editable': editable, 'attachments': att, 'recordId': 'r$date',
    };

final _career = {
  'employee': {
    'id': 'e1', 'name': 'Nguyễn Văn An', 'code': 'NV001', 'position': 'Trưởng kho', 'department': 'Kho vận',
    'departmentId': 'kho', 'branch': 'Chi nhánh Quận 7', 'joinDate': '2021-03-01T00:00:00',
    'contractEndDate': DateTime.now().add(const Duration(days: 20)).toIso8601String(),
  },
  'summary': {'moves': 2, 'awards': 2, 'disciplines': 1, 'bonusTotal': 3500000, 'penaltyTotal': 200000},
  'canEdit': true,
  'events': [
    _ev('promotion', '2026-09-01T00:00:00', 'Thăng chức Trưởng kho', sub: 'Thủ kho · Kho vận  ›  Trưởng kho · Kho vận', decision: 'QĐ-21/2026', issuer: 'Giám đốc', editable: true, att: ['/uploads/qd-21.pdf']),
    _ev('award', '2026-07-15T00:00:00', 'Hoàn thành xuất sắc kiểm kê quý 2', sub: 'Giấy khen', amount: 2000000, decision: 'QĐ-15/2026', editable: true),
    _ev('bonus', '2026-06-30T00:00:00', 'Thưởng doanh số tháng 6', source: 'finance', amount: 1500000),
    _ev('penalty', '2026-03-12T00:00:00', 'Đi trễ 3 lần', source: 'finance', amount: 200000),
    _ev('discipline', '2025-11-20T00:00:00', 'Vi phạm quy trình xuất kho', sub: 'Khiển trách', issuer: 'Trưởng phòng', editable: true),
    _ev('transfer', '2024-02-01T00:00:00', 'Điều chuyển sang Kho vận', sub: 'Nhân viên · Kinh doanh  ›  Thủ kho · Kho vận', decision: 'QĐ-03/2024', editable: true),
    _ev('contract', '2023-03-01T00:00:00', 'Hợp đồng lao động không thời hạn', source: 'document'),
    _ev('join', '2021-03-01T00:00:00', 'Vào làm', sub: 'Nhân viên · Kinh doanh', source: 'profile'),
  ],
};

http.Response _ok(Object data) =>
    http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

final _client = MockClient((req) async {
  final p = req.url.path;
  if (p.endsWith('/employee-career/e1')) return _ok(_career);
  if (p.endsWith('/departments/v2/overview')) {
    return _ok({
      'items': [
        {'id': 'kho', 'name': 'Kho vận', 'code': 'KV', 'positions': ['Thủ kho', 'Trưởng kho', 'Nhân viên kho']},
        {'id': 'kd', 'name': 'Kinh doanh', 'code': 'KD'},
      ],
    });
  }
  return http.Response('', 404);
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
        home: MediaQuery(data: MediaQueryData(size: size), child: home),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (before != null) {
      await before();
      for (var i = 0; i < 8; i++) {
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

  testWidgets('Quá trình công tác — máy tính', (t) async {
    await _pump(t, const EmployeeCareerV2Screen(employeeId: 'e1'), const Size(1440, 1500), 'career_desktop');
    expect(find.text('Thăng chức Trưởng kho'), findsOneWidget);
    expect(find.text('2024'), findsOneWidget);
    expect(find.textContaining('Thâm niên'), findsOneWidget);
  });

  testWidgets('Lọc khen thưởng — điện thoại', (t) async {
    await _pump(t, const EmployeeCareerV2Screen(employeeId: 'e1'), const Size(390, 1300), 'career_mobile_rewards', before: () async {
      await t.tap(find.textContaining('Khen thưởng (2)'));
    });
    expect(find.text('Thưởng doanh số tháng 6'), findsOneWidget);
    expect(find.text('Đi trễ 3 lần'), findsNothing);
  });

  testWidgets('Form kỷ luật', (t) async {
    await _pump(t, const CareerRecordForm(employeeId: 'e1', kind: 'discipline'), const Size(620, 900), 'career_form_discipline');
    expect(find.text('Khiển trách'), findsOneWidget);
    expect(find.text('Hiệu lực đến'), findsOneWidget);
  });

  testWidgets('Form điều chuyển', (t) async {
    await _pump(t, CareerMoveForm(employee: Map<String, dynamic>.from(_career['employee'] as Map)), const Size(620, 900),
        'career_form_move');
    expect(find.textContaining('Hiện tại: Trưởng kho'), findsOneWidget);
    expect(find.text('Nhân viên kho'), findsOneWidget); // gợi ý chức vụ của phòng
  });
}
