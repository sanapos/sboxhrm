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
import 'package:zkteco_flutter_client/screens/accounts_v2/ac_common.dart';
import 'package:zkteco_flutter_client/screens/accounts_v2/ac_screen.dart';

/// Tài khoản (B4). Đặt SBOX_SHOT_DIR để lưu ảnh duyệt.
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

final _now = DateTime.now().toUtc();
Map<String, dynamic> _acc(String id, String last, String first, String role,
        {bool owner = false, bool active = true, bool resigned = false, int? loginHours, String? phone, String? empId}) =>
    {
      'id': id,
      'userName': '${first.toLowerCase()}.${id}',
      'email': '${first.toLowerCase()}@sbox.vn',
      'firstName': first,
      'lastName': last,
      'phoneNumber': phone,
      'roles': [role],
      'isOwner': owner,
      'isActive': active,
      'employeeId': empId,
      'isEmployeeResigned': resigned,
      'isEmployeeMissingOrResigned': resigned,
      'lastLoginAt': loginHours == null ? null : _now.subtract(Duration(hours: loginHours)).toIso8601String(),
    };

final _accounts = [
  _acc('u1', 'Nguyễn Văn', 'An', 'Admin', owner: true, loginHours: 2, phone: '0909 123 456'),
  _acc('u2', 'Trần Thị', 'Bình', 'Director', loginHours: 30),
  _acc('me', 'Lê Minh', 'Châu', 'Manager', loginHours: 0),
  _acc('u4', 'Phạm Thu', 'Dung', 'Cashier', loginHours: 5, empId: 'e4'),
  _acc('u5', 'Hoàng Văn', 'Em', 'Waiter', active: false, loginHours: 24 * 40),
  _acc('u6', 'Võ Thị', 'Giang', 'Employee', resigned: true, loginHours: 24 * 3, empId: 'e6'),
  _acc('u7', 'Đặng Quốc', 'Huy', 'Accountant', loginHours: 50),
];

http.Response _ok(Object? data) =>
    http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

final _client = MockClient((req) async {
  final p = req.url.path;
  if (p.endsWith('/api/accounts/role-policy')) {
    return _ok({
      'isOwner': false,
      'myRole': 'Manager',
      'assignableRoles': ['DepartmentHead', 'Accountant', 'Cashier', 'Employee', 'Waiter', 'User'],
    });
  }
  if (p.endsWith('/api/accounts')) return _ok(_accounts);
  if (p.endsWith('/api/employees')) {
    return _ok({
      'items': [
        {'id': 'e4', 'firstName': 'Dung', 'lastName': 'Phạm Thu', 'employeeCode': 'NV004'},
        {'id': 'e8', 'firstName': 'Khoa', 'lastName': 'Bùi Anh', 'employeeCode': 'NV008', 'companyEmail': 'khoa@sbox.vn', 'phoneNumber': '0912 000 888'},
        {'id': 'e9', 'firstName': 'Linh', 'lastName': 'Ngô Mỹ', 'employeeCode': 'NV009'},
      ],
    });
  }
  if (p.endsWith('/api/pos/service-areas')) {
    return _ok([
      {'id': 'a1', 'name': 'Tầng 1'},
      {'id': 'a2', 'name': 'Sân vườn'},
    ]);
  }
  return http.Response(jsonEncode({'isSuccess': false}), 200, headers: {'content-type': 'application/json'});
});

Future<void> _pump(WidgetTester tester, Size size, String name, {Future<void> Function()? before}) async {
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
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: const AccountsV2Screen(permOverride: {'view', 'create', 'edit', 'delete'}, myUserId: 'me'),
        ),
      ),
    ));
    for (var i = 0; i < 12; i++) {
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

  test('Quản lý chỉ quản lý được cấp thấp hơn, không đụng chủ cửa hàng', () {
    final p = RolePolicy.fromJson({'isOwner': false, 'myRole': 'Manager', 'assignableRoles': ['Cashier']}, myUserId: 'me');
    Account a(String role, {bool owner = false, String id = 'x'}) => Account({'id': id, 'roles': [role], 'isOwner': owner});
    expect(p.denyManage(a('Cashier')), isNull);
    expect(p.denyManage(a('Accountant')), isNull);
    expect(p.denyManage(a('Manager')), isNotNull);
    expect(p.denyManage(a('Director')), isNotNull);
    expect(p.denyManage(a('Admin', owner: true)), isNotNull);
    expect(p.denyManage(a('Cashier', id: 'me')), isNotNull);
    final owner = RolePolicy.fromJson({'isOwner': true, 'myRole': 'Admin'}, myUserId: 'o');
    expect(owner.denyManage(a('Admin')), isNull);
    expect(owner.denyManage(a('SuperAdmin')), isNotNull);
  });

  test('Mật khẩu ngẫu nhiên đủ dài, không ký tự dễ nhầm', () {
    final ps = {for (var i = 0; i < 30; i++) randomPassword()};
    expect(ps.length, 30);
    expect(ps.every((p) => p.length == 10 && !RegExp('[0O1lI]').hasMatch(p)), isTrue);
  });

  testWidgets('Danh sách tài khoản — máy tính', (t) async {
    await _pump(t, const Size(1200, 1000), 'b4_accounts');
    expect(find.text('Chủ cửa hàng'), findsOneWidget);
    expect(find.text('Bạn'), findsOneWidget);
    expect(find.text('Nhân viên đã nghỉ việc'), findsOneWidget);
    expect(find.text('Đã khóa'), findsWidgets);
  });

  testWidgets('Thêm tài khoản: chỉ vai trò thấp hơn mình', (t) async {
    await _pump(t, const Size(1200, 1000), 'b4_account_add', before: () async {
      await t.tap(find.text('Thêm tài khoản'));
    });
    expect(find.text('Liên kết hồ sơ nhân viên'), findsOneWidget);
    final dlg = find.byType(Dialog);
    expect(find.descendant(of: dlg, matching: find.text('Thu ngân')), findsOneWidget);
    expect(find.descendant(of: dlg, matching: find.text('Giám đốc')), findsNothing);
    expect(find.descendant(of: dlg, matching: find.text('Quản trị viên')), findsNothing);
    expect(find.text('Khu vực bán hàng được xem'), findsOneWidget);
  });

  testWidgets('Danh sách tài khoản — điện thoại', (t) async {
    await _pump(t, const Size(390, 1400), 'b4_accounts_mobile');
    expect(find.text('Thêm tài khoản'), findsOneWidget);
  });
}
