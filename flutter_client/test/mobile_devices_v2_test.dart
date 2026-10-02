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
import 'package:zkteco_flutter_client/screens/mobile_devices_v2/md_hub_screen.dart';

/// Thiết bị chấm công Mobile (quản lý) với dữ liệu mẫu. Đặt SBOX_SHOT_DIR để lưu ảnh duyệt giao diện.
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

Map<String, dynamic> _emp(String name, String code, String dept, String branch) =>
    {'employeeId': code, 'employeeName': name, 'employeeCode': code, 'department': dept, 'branchName': branch};

final _now = DateTime.now().toUtc();

final _inbox = {
  'items': [
    {
      'id': 'r1', 'kind': 'register', 'requestedAt': _now.subtract(const Duration(minutes: 25)).toIso8601String(),
      'employee': _emp('Nguyễn Văn An', 'NV001', 'Kho', 'Chi nhánh Quận 7'),
      'deviceName': 'iPhone 15', 'deviceModel': 'iPhone15,4', 'osVersion': 'iOS 18.6', 'wifiBssid': 'a4:2b:b0:11:22:33',
      'faceImages': ['/uploads/f1.jpg', '/uploads/f2.jpg', '/uploads/f3.jpg', '/uploads/f4.jpg', '/uploads/f5.jpg'],
      'locations': ['Kho Quận 7', 'Văn phòng Quận 1'],
    },
    {
      'id': 'c1', 'kind': 'change', 'requestedAt': _now.subtract(const Duration(hours: 3)).toIso8601String(),
      'employee': _emp('Trần Thị Bình', 'NV014', 'Bán hàng', 'Trụ sở Quận 1'),
      'deviceName': 'Galaxy S24', 'deviceModel': 'SM-S921B', 'osVersion': 'Android 15', 'oldDeviceName': 'Galaxy A52',
      'reason': 'Máy cũ bị vỡ màn hình', 'faceImages': ['/uploads/g1.jpg', '/uploads/g2.jpg'], 'locations': ['Văn phòng Quận 1'],
    },
  ],
  'counts': {'total': 2, 'register': 1, 'change': 1},
};

final _devices = [
  {
    'id': 'd1', 'employee': _emp('Lê Minh Châu', 'NV003', 'Kế toán', 'Trụ sở Quận 1'), 'deviceName': 'iPhone 13',
    'lastUsedAt': _now.subtract(const Duration(hours: 2)).toIso8601String(), 'canUseFaceId': true, 'canUseGps': true,
    'allowOutsideCheckIn': true, 'requireOutsideReason': true, 'allowTravelCheckIn': false, 'requirePhotoProof': false,
  },
  {
    'id': 'd2', 'employee': _emp('Phạm Quốc Dũng', 'NV007', 'Giao hàng', 'Chi nhánh Quận 7'), 'deviceName': 'Redmi Note 13',
    'lastUsedAt': _now.subtract(const Duration(days: 1)).toIso8601String(), 'canUseFaceId': true, 'canUseGps': true,
    'allowOutsideCheckIn': true, 'requireOutsideReason': false, 'allowTravelCheckIn': true, 'requirePhotoProof': true,
  },
];

final _unregistered = [
  {..._emp('Võ Thị Em', 'NV021', 'Bán hàng', 'Chi nhánh Thủ Đức'), 'hasAccount': true, 'pending': false},
  {..._emp('Đặng Văn Phúc', 'NV022', 'Kho', 'Chi nhánh Quận 7'), 'hasAccount': false, 'pending': false},
  {..._emp('Nguyễn Văn An', 'NV001', 'Kho', 'Chi nhánh Quận 7'), 'hasAccount': true, 'pending': true},
];

http.Response _ok(Object data) =>
    http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

final List<String> _posted = [];

final _client = MockClient((req) async {
  final p = req.url.path;
  if (req.method == 'POST') _posted.add('$p ${req.body}');
  if (p.endsWith('/mobile-devices/inbox')) return _ok(_inbox);
  if (p.endsWith('/mobile-devices/devices')) return _ok(_devices);
  if (p.endsWith('/mobile-devices/unregistered')) return _ok(_unregistered);
  if (p.endsWith('/mobile-devices/remind')) return _ok({'sent': 1, 'skipped': 0});
  if (p.contains('/approve-device')) return _ok({'id': 'x'});
  // Ảnh khuôn mặt mẫu: trả lỗi để hiện ô thay thế
  return http.Response('', 404);
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
          child: const MobileDevicesHubScreen(managerOverride: true, myPhone: Center(child: Text('Điện thoại của tôi'))),
        ),
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _posted.clear();
  });

  testWidgets('Cần duyệt — máy tính', (t) async {
    await _pump(t, const Size(1440, 900), 'devices_inbox_desktop');
    expect(find.text('Đăng ký mới'), findsOneWidget);
    expect(find.text('Đổi máy'), findsOneWidget);
    expect(find.textContaining('Galaxy A52'), findsOneWidget);
  });

  testWidgets('Cần duyệt — điện thoại', (t) async {
    await _pump(t, const Size(390, 1400), 'devices_inbox_mobile');
  });

  testWidgets('Từ chối có lý do', (t) async {
    await _pump(t, const Size(1440, 900), 'devices_reject_dialog', before: () async {
      await t.tap(find.text('Từ chối').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Ảnh khuôn mặt mờ / thiếu sáng'));
      await t.pump();
    });
    expect(find.textContaining('Từ chối đăng ký của Nguyễn Văn An'), findsOneWidget);
  });

  testWidgets('Đã cấp quyền + chỉnh hàng loạt', (t) async {
    await _pump(t, const Size(1440, 900), 'devices_authorized_desktop', before: () async {
      await t.tap(find.text('Đã cấp quyền'));
      for (var i = 0; i < 6; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump(const Duration(milliseconds: 100));
      }
      await t.tap(find.textContaining('Chỉnh tất cả'));
      await t.pumpAndSettle();
    });
    expect(find.text('Bắt nhập lý do'), findsWidgets);
    expect(find.textContaining('Chỉnh quyền 2 điện thoại'), findsOneWidget);
  });

  testWidgets('Chưa đăng ký — điện thoại', (t) async {
    await _pump(t, const Size(390, 900), 'devices_unregistered_mobile', before: () async {
      await t.ensureVisible(find.text('Chưa đăng ký').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Chưa đăng ký').first);
    });
    expect(find.text('Chưa có tài khoản'), findsOneWidget);
    expect(find.text('Đang chờ duyệt'), findsOneWidget);
    expect(find.textContaining('Nhắc tất cả (1)'), findsOneWidget);
  });
}
