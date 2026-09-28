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
import 'package:zkteco_flutter_client/screens/attendance_approval_v2/aa_common.dart';
import 'package:zkteco_flutter_client/screens/attendance_approval_v2/aa_detail.dart';
import 'package:zkteco_flutter_client/screens/attendance_approval_v2/aa_hub_screen.dart';
import 'package:zkteco_flutter_client/screens/attendance_approval_v2/outside_reason_dialog.dart';
import 'package:zkteco_flutter_client/services/api_service.dart';

/// Duyệt chấm công v2 với dữ liệu mẫu. Đặt SBOX_SHOT_DIR để lưu ảnh duyệt giao diện.
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

final _now = DateTime.now();
String _at(int h, int m, {int daysAgo = 0}) => DateTime(_now.year, _now.month, _now.day - daysAgo, h, m).toIso8601String();
String _ago(int hours) => _now.toUtc().subtract(Duration(hours: hours)).toIso8601String();

final _items = [
  {
    'kind': 'mobile', 'id': 'm1', 'employeeName': 'Nguyễn Văn An', 'employeeCode': 'NV012', 'department': 'Thi công',
    'time': _at(7, 52), 'createdAt': _ago(1), 'title': 'Vào ca 07:52', 'subtitle': 'Công trình Thảo Điền · cách 1,8 km',
    'reason': 'Em đi mua vật tư theo yêu cầu anh Tuấn', 'riskLevel': 'high', 'riskScore': 62,
    'flags': ['Cách vị trí gần nhất 1,8 km', 'GPS kém chính xác (±180 m)'], 'distance': 1830, 'punchType': 0, 'isOutside': true,
    'sitePhotoUrl': '/site/1.jpg', 'faceScore': 92,
  },
  {
    'kind': 'mobile', 'id': 'm2', 'employeeName': 'Trần Minh Khoa', 'employeeCode': 'NV004', 'department': 'Kinh doanh',
    'time': _at(17, 31), 'createdAt': _ago(3), 'title': 'Ra ca 17:31', 'subtitle': 'Nhà khách hàng Q7 · cách 180 m',
    'reason': 'Gặp khách hàng', 'riskLevel': 'trusted', 'riskScore': 8, 'distance': 180, 'punchType': 1, 'isOutside': true, 'faceScore': 94,
  },
  {
    'kind': 'correction', 'id': 'c1', 'employeeName': 'Phạm Thu Hà', 'employeeCode': 'NV021', 'department': 'Cửa hàng Q1',
    'time': _at(17, 30, daysAgo: 1), 'createdAt': _ago(30), 'title': 'Bổ sung chấm công 17:30', 'reason': 'Quên chấm ra do máy hết pin',
    'correctionAction': 0, 'overdue': true,
  },
  {
    'kind': 'mobile', 'id': 'm3', 'employeeName': 'Lê Quốc Bảo', 'employeeCode': 'NV017', 'department': 'Kho',
    'time': _at(8, 1), 'createdAt': _ago(2), 'title': 'Bắt đầu đi 08:01', 'subtitle': 'Kho Bình Dương · cách 4,2 km',
    'riskLevel': 'review', 'riskScore': 38, 'distance': 4200, 'punchType': 2, 'isOutside': true, 'isTravel': true,
  },
];

final _mobileCtx = {
  'record': {
    'id': 'm1', 'employeeName': 'Nguyễn Văn An', 'punchTime': _at(7, 52), 'punchType': 0, 'status': 'pending',
    'latitude': 10.8031, 'longitude': 106.7390, 'locationName': 'Công trình Thảo Điền', 'distanceFromLocation': 1830,
    'gpsAccuracy': 180, 'faceMatchScore': 92, 'sitePhotoUrl': '/site/1.jpg', 'outsideReason': 'Em đi mua vật tư theo yêu cầu anh Tuấn',
    'riskScore': 62, 'riskLevel': 'high', 'riskFlags': ['Cách vị trí gần nhất 1,8 km', 'GPS kém chính xác (±180 m)'],
  },
  'employee': {'id': 'e1', 'name': 'Nguyễn Văn An', 'employeeCode': 'NV012', 'department': 'Thi công'},
  'device': {'name': 'iPhone của An', 'model': 'iPhone 13'},
  'shift': {'name': 'Ca sáng', 'start': '08:00', 'end': '17:00'},
  'sameDay': [
    {'id': 'm1', 'punchTime': _at(7, 52), 'punchType': 0, 'status': 'pending', 'locationName': 'Công trình Thảo Điền', 'isOutside': true},
  ],
  'logs': [],
  'outsideThisMonth': 6,
  'history': [
    {'punchTime': _at(8, 5, daysAgo: 3), 'status': 'approved', 'locationName': 'Công trình Thảo Điền', 'distanceFromLocation': 420},
    {'punchTime': _at(7, 40, daysAgo: 9), 'status': 'rejected', 'locationName': 'Công trình Thảo Điền', 'distanceFromLocation': 6100, 'rejectReason': 'Không có lịch làm việc ngoài'},
  ],
  'locations': [
    {'name': 'Công trình Thảo Điền', 'latitude': 10.8040, 'longitude': 106.7555, 'radius': 150},
  ],
};

final _correctionCtx = {
  'request': {
    'id': 'c1', 'employeeName': 'Phạm Thu Hà', 'action': 0, 'newDate': _at(0, 0, daysAgo: 1), 'newTime': '17:30',
    'reason': 'Quên chấm ra do máy hết pin', 'status': 0, 'totalApprovalLevels': 1, 'currentApprovalStep': 0,
    'approvals': [],
  },
  'employee': {'id': 'e2', 'name': 'Phạm Thu Hà', 'employeeCode': 'NV021'},
  'shift': {'name': 'Ca hành chính', 'start': '08:00', 'end': '17:30', 'dayOff': false},
  'logs': [
    {'attendanceTime': _at(7, 58, daysAgo: 1), 'note': 'Máy cửa hàng Q1', 'fromMobile': false},
  ],
  'requestsThisMonth': 2,
  'forgotCheckPenalty': 50000,
};

http.Response _ok(Object data) =>
    http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

final _client = MockClient((req) async {
  final p = req.url.path;
  if (p.endsWith('/attendance-approvals/inbox')) {
    return _ok({
      'items': _items,
      'counts': {'all': 4, 'mobile': 3, 'correction': 1, 'outside': 3, 'trusted': 1, 'high': 1, 'overdue': 1},
      'stats30': [
        {'status': 'auto_approved', 'count': 42},
        {'status': 'approved', 'count': 18},
        {'status': 'rejected', 'count': 3},
      ],
    });
  }
  if (p.contains('/records/m1/context')) return _ok(_mobileCtx);
  if (p.contains('/corrections/c1/context')) return _ok(_correctionCtx);
  if (p.endsWith('/approval-settings')) {
    return _ok({'autoApproveTrusted': true, 'trustedMaxDistanceMeters': 300, 'trustedMinFaceScore': 85, 'evidenceRetentionDays': 30});
  }
  if (p.endsWith('/outside-reason-devices')) {
    return _ok([
      {'id': 'd1', 'employeeName': 'Nguyễn Văn An', 'deviceName': 'iPhone 13', 'allowOutsideCheckIn': true, 'requirePhotoProof': true, 'requireOutsideReason': true},
      {'id': 'd2', 'employeeName': 'Trần Minh Khoa', 'deviceName': 'Galaxy A54', 'allowOutsideCheckIn': true, 'requireOutsideReason': false},
      {'id': 'd3', 'employeeName': 'Lê Quốc Bảo', 'deviceName': 'Redmi Note 12', 'allowOutsideCheckIn': false, 'requireOutsideReason': false},
    ]);
  }
  return http.Response(jsonEncode({'isSuccess': false, 'message': 'not mocked $p'}), 200);
});

Future<void> _pump(WidgetTester tester, Widget home, Size size, String name, {bool tall = true, Future<void> Function()? before}) async {
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

  Future<void> settle([int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  await http.runWithClient(() async {
    await setSize(size);
    await tester.pumpWidget(app(size));
    await settle();
    expect(tester.takeException(), isNull);
    if (tall) {
      var extent = 0.0;
      for (final e in find.byType(Scrollable).evaluate()) {
        final st = (e as StatefulElement).state as ScrollableState;
        if (st.position.axis == Axis.vertical && st.position.maxScrollExtent > extent) extent = st.position.maxScrollExtent;
      }
      if (extent > 0) {
        final t = Size(size.width, size.height + extent);
        await setSize(t);
        await tester.pumpWidget(app(t));
        await settle(4);
      }
    }
    if (before != null) {
      await before();
      await settle(6);
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

  test('Đọc mục duyệt + nhãn rủi ro', () {
    final hi = AaItem.fromJson(_items[0]);
    expect(aaRisk(hi).$1, 'Rủi ro cao');
    expect(hi.flags.length, 2);
    final ok = AaItem.fromJson(_items[1]);
    expect(ok.isTrusted, isTrue);
    final travel = AaItem.fromJson(_items[3]);
    expect(travel.isTrusted, isFalse);
    expect(aaRisk(travel).$1, 'Đi đường');
    expect(aaRisk(AaItem.fromJson(_items[2])).$1, 'Sửa / bổ sung công');
    expect(aaDistance(1830), '1,8 km');
    expect(aaDistance(180), '180 m');
  });

  testWidgets('Hộp duyệt — máy tính (danh sách + chi tiết có bản đồ)', (t) async {
    await _pump(t, const AttendanceApprovalHubScreen(enableMapTiles: false), const Size(1440, 900), 'aa_hub_desktop');
    expect(find.text('Duyệt 1 bản tin cậy'), findsOneWidget);
    expect(find.text('Dấu hiệu cần chú ý'), findsOneWidget);
    expect(find.text('Lần chấm ngoài vị trí trước đây'), findsOneWidget);
  });

  testWidgets('Hộp duyệt — điện thoại', (t) async {
    await _pump(t, const AttendanceApprovalHubScreen(enableMapTiles: false), const Size(390, 844), 'aa_hub_mobile');
    expect(find.text('Rủi ro cao'), findsWidgets);
    expect(find.text('Quá 24 giờ'), findsWidgets);
  });

  testWidgets('Chi tiết chấm ngoài vị trí — điện thoại', (t) async {
    await _pump(
        t,
        AaDetailPane(item: AaItem.fromJson(_items[0]), api: ApiService(), onDecided: () {}, enableMapTiles: false, compact: true),
        const Size(390, 844),
        'aa_detail_mobile',
        tall: false);
    expect(find.text('Từ chối'), findsOneWidget);
    expect(find.text('Duyệt'), findsOneWidget);
  });

  testWidgets('Chi tiết yêu cầu bổ sung công — máy tính', (t) async {
    await _pump(
        t,
        SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: SizedBox(
            width: 760,
            child: AaDetailPane(item: AaItem.fromJson(_items[2]), api: ApiService(), onDecided: () {}, enableMapTiles: false),
          ),
        ),
        const Size(820, 900),
        'aa_correction_detail');
    expect(find.text('Duyệt + phạt'), findsOneWidget);
    expect(find.text('Sau khi duyệt'), findsOneWidget);
  });

  testWidgets('Cài đặt duyệt — máy tính', (t) async {
    await _pump(t, const AttendanceApprovalHubScreen(enableMapTiles: false, initialSettings: true), const Size(1440, 900), 'aa_settings_desktop');
    expect(find.text('Tự duyệt chấm công tin cậy'), findsOneWidget);
    expect(find.textContaining('1/3 đang bật'), findsOneWidget);
  });

  testWidgets('Nhân viên nhập lý do chấm ngoài vị trí', (t) async {
    await _pump(
        t,
        Builder(builder: (ctx) => Center(child: ElevatedButton(onPressed: () => showOutsideReasonDialog(ctx), child: const Text('open')))),
        const Size(390, 844),
        'aa_outside_reason_mobile',
        tall: false, before: () async {
      await t.tap(find.text('open'));
    });
    expect(find.text('Chấm công ngoài vị trí'), findsOneWidget);
    expect(find.text('Gặp khách hàng'), findsOneWidget);
  });
}
