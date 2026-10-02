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
import 'package:zkteco_flutter_client/screens/departments_v2/dp_common.dart';
import 'package:zkteco_flutter_client/screens/departments_v2/dp_editor.dart';
import 'package:zkteco_flutter_client/screens/departments_v2/dp_screen.dart';

/// Phòng ban v2 với dữ liệu mẫu. Đặt SBOX_SHOT_DIR để lưu ảnh duyệt giao diện.
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

Map<String, dynamic> _d(String id, String name, String code, String? parent, int direct, int total, int kids,
        {String? manager, int order = 0, List<String> positions = const []}) =>
    {
      'id': id, 'name': name, 'code': code, 'parentId': parent, 'directCount': direct, 'totalCount': total,
      'childCount': kids, 'managerId': manager == null ? null : 'm$id', 'managerName': manager,
      'managerPosition': manager == null ? null : 'Trưởng phòng', 'sortOrder': order, 'isActive': true,
      'positions': positions, 'description': id == 'kd' ? 'Bán hàng và chăm sóc khách hàng' : null,
    };

final _overview = {
  'items': [
    _d('bgd', 'Ban giám đốc', 'BGD', null, 2, 2, 0, manager: 'Nguyễn Văn Hùng', order: 0),
    _d('kd', 'Khối Kinh doanh', 'KD', null, 3, 14, 2, manager: 'Trần Thị Lan', order: 1, positions: ['Trưởng nhóm', 'Nhân viên kinh doanh']),
    _d('bl', 'Phòng Bán lẻ', 'BL', 'kd', 7, 7, 0, manager: 'Lê Văn Minh', order: 0),
    _d('ol', 'Phòng Online', 'OL', 'kd', 4, 4, 0, order: 1),
    _d('kho', 'Kho vận', 'KV', null, 6, 6, 0, manager: 'Phạm Quốc Dũng', order: 2),
  ],
  'totalEmployees': 25,
  'unassigned': 3,
};

final _members = [
  {'id': 'e1', 'name': 'Trần Thị Lan', 'employeeCode': 'NV002', 'position': 'Giám đốc kinh doanh', 'branchName': 'Trụ sở Quận 1'},
  {'id': 'e2', 'name': 'Võ Minh Tuấn', 'employeeCode': 'NV011', 'position': 'Trưởng nhóm', 'branchName': 'Trụ sở Quận 1', 'probation': false},
  {'id': 'e3', 'name': 'Đặng Thu Hà', 'employeeCode': 'NV015', 'position': 'Nhân viên kinh doanh', 'branchName': 'Chi nhánh Quận 7', 'probation': true},
];

http.Response _ok(Object data) =>
    http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

final _client = MockClient((req) async {
  final p = req.url.path;
  if (p.endsWith('/departments/v2/overview')) return _ok(_overview);
  if (p.endsWith('/members')) return _ok(_members);
  if (p.endsWith('/employee-search')) return _ok(_members);
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

  test('Cây phòng ban: thứ tự, phòng con, đường dẫn, mã gợi ý', () {
    final tree = DeptTree([for (final x in _overview['items'] as List) Dept(Map<String, dynamic>.from(x as Map))]);
    expect(tree.roots.map((d) => d.code), ['BGD', 'KD', 'KV']);
    expect(tree.flatten().map((r) => r.$1.code), ['BGD', 'KD', 'BL', 'OL', 'KV']);
    expect(tree.flatten(collapsed: {'kd'}).length, 3);
    expect(tree.descendantsOf('kd'), {'kd', 'bl', 'ol'});
    expect(tree.pathOf('ol'), 'Khối Kinh doanh › Phòng Online');
    expect(suggestDeptCode('Phòng Kế toán', ['KD']), 'PKT');
    expect(suggestDeptCode('Kho', ['KHO']), 'KHO2');
  });

  testWidgets('Phòng ban — máy tính', (t) async {
    await _pump(t, const DepartmentsV2Screen(), const Size(1440, 1000), 'dept_desktop', before: () async {
      await t.tap(find.text('Khối Kinh doanh').first);
    });
    expect(find.text('Đặng Thu Hà'), findsOneWidget);
    expect(find.text('Chưa có phòng ban'), findsWidgets);
  });

  testWidgets('Sơ đồ tổ chức', (t) async {
    await _pump(t, const DepartmentsV2Screen(), const Size(1440, 800), 'dept_orgchart', before: () async {
      await t.tap(find.text('Sơ đồ'));
    });
    expect(find.text('Phòng Online'), findsOneWidget);
  });

  testWidgets('Phòng ban — điện thoại', (t) async {
    await _pump(t, const DepartmentsV2Screen(), const Size(390, 900), 'dept_mobile');
    expect(find.text('Phòng Bán lẻ'), findsOneWidget);
  });

  testWidgets('Sửa phòng ban', (t) async {
    final tree = DeptTree([for (final x in _overview['items'] as List) Dept(Map<String, dynamic>.from(x as Map))]);
    await _pump(t, DeptEditor(tree: tree, dept: tree.byId['bl']), const Size(620, 760), 'dept_editor');
    expect(find.text('Khối Kinh doanh'), findsOneWidget);
    expect(find.text('Lê Văn Minh'), findsOneWidget);
  });
}
