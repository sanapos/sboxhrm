import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/providers/auth_provider.dart';
import 'package:zkteco_flutter_client/providers/theme_provider.dart';
import 'package:zkteco_flutter_client/screens/system_admin/v2/sa_ops_v2.dart';
import 'package:zkteco_flutter_client/screens/system_admin/v2/sa_packages_v2.dart';
import 'package:zkteco_flutter_client/screens/system_admin/v2/sa_stores_v2.dart';
import 'package:zkteco_flutter_client/screens/system_admin/v2/sa_user_security.dart';
import 'package:zkteco_flutter_client/screens/system_admin/v2/sa_v2_common.dart';
import 'package:zkteco_flutter_client/services/api_service.dart';

/// Quản trị Super Admin v2 với dữ liệu mẫu. Đặt SBOX_SHOT_DIR để lưu ảnh duyệt giao diện.
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

Map<String, dynamic> _m(String code, String name, String cat, String line, [List<String> req = const []]) =>
    {'code': code, 'name': name, 'description': 'Mô tả $name', 'category': cat, 'productLine': line, 'requires': req};

final _catalog = {
  'categories': [
    {'name': 'Tổng quan', 'productLine': 'common'},
    {'name': 'Chấm công', 'productLine': 'hrm'},
    {'name': 'Lương & báo cáo nhân sự', 'productLine': 'hrm'},
    {'name': 'Tài chính nhân sự', 'productLine': 'hrm'},
    {'name': 'Trí tuệ nhân tạo', 'productLine': 'common'},
    {'name': 'Bán hàng', 'productLine': 'pos'},
    {'name': 'Báo cáo bán hàng', 'productLine': 'pos'},
  ],
  'modules': [
    _m('Dashboard', 'Tổng quan doanh nghiệp', 'Tổng quan', 'common'),
    _m('Attendance', 'Chấm công thô', 'Chấm công', 'hrm'),
    _m('MobileAttendance', 'Chấm công Mobile', 'Chấm công', 'hrm'),
    _m('AttendanceApproval', 'Duyệt chấm công', 'Chấm công', 'hrm', ['Attendance']),
    _m('AttendanceSummary', 'Tổng hợp chấm công', 'Lương & báo cáo nhân sự', 'hrm', ['Attendance']),
    _m('Payroll', 'Bảng lương', 'Lương & báo cáo nhân sự', 'hrm', ['AttendanceSummary']),
    _m('PenaltyReport', 'Báo cáo phạt', 'Lương & báo cáo nhân sự', 'hrm', ['PenaltyTickets']),
    _m('PenaltyTickets', 'Phiếu phạt chấm công', 'Tài chính nhân sự', 'hrm'),
    _m('AdvanceRequests', 'Ứng lương', 'Tài chính nhân sự', 'hrm'),
    _m('AIAssistant', 'Trợ lý AI', 'Trí tuệ nhân tạo', 'common'),
    _m('PosSell', 'Bán hàng', 'Bán hàng', 'pos', ['PosProducts']),
    _m('PosProducts', 'Hàng hóa', 'Bán hàng', 'pos'),
    _m('PosKds', 'Màn hình bếp (KDS)', 'Bán hàng', 'pos', ['PosSell']),
    _m('PosSalesReport', 'Trung tâm báo cáo bán hàng', 'Báo cáo bán hàng', 'pos', ['PosSell']),
    _m('PosReportRevenue', 'Doanh thu', 'Báo cáo bán hàng', 'pos', ['PosSalesReport']),
  ],
  'presets': [
    {'key': 'pos_basic', 'name': 'POS bán hàng', 'description': 'Bán hàng cơ bản', 'productLine': 'pos', 'modules': ['PosSell', 'PosProducts', 'PosSalesReport', 'PosReportRevenue']},
    {'key': 'hrm_basic', 'name': 'HRM chấm công & lương', 'description': 'Chấm công, lương', 'productLine': 'hrm', 'modules': ['Attendance', 'MobileAttendance', 'AttendanceSummary', 'Payroll']},
    {'key': 'all', 'name': 'Trọn bộ POS + HRM', 'description': 'Tất cả', 'productLine': 'both', 'modules': ['Dashboard', 'Attendance', 'PosSell', 'PosProducts']},
  ],
  'fcmCategories': [
    {'code': 'attendance', 'name': 'Chấm công'}, {'code': 'payroll', 'name': 'Lương'}, {'code': 'pos', 'name': 'Bán hàng'}, {'code': 'feedback', 'name': 'Phản ánh'},
  ],
};

final _packages = [
  {
    'id': 'p1', 'name': 'POS Cơ bản', 'description': 'Cho cửa hàng nhỏ', 'isActive': true, 'isPublic': true, 'productLine': 'pos',
    'monthlyPrice': 199000, 'yearlyPrice': 1990000, 'trialDays': 14, 'isFeatured': false, 'maxUsers': 5, 'maxBranches': 1, 'maxDevices': 0,
    'modules': ['PosSell', 'PosProducts', 'PosSalesReport', 'PosReportRevenue', 'AIAssistant'], 'missing': [], 'unknown': [],
    'stores': 36, 'activeStores': 31, 'expiringStores': 4, 'unusedKeys': 12, 'fcmCategories': ['pos'],
  },
  {
    'id': 'p2', 'name': 'POS + Nhân sự', 'description': 'Bán hàng kèm chấm công, lương', 'isActive': true, 'isPublic': true, 'productLine': 'both',
    'monthlyPrice': 399000, 'yearlyPrice': 3990000, 'trialDays': 14, 'isFeatured': true, 'badge': 'Phổ biến', 'maxUsers': 20, 'maxBranches': 3, 'maxDevices': 2,
    'modules': ['PosSell', 'PosProducts', 'Attendance', 'MobileAttendance', 'Payroll', 'PenaltyReport', 'AIAssistant'],
    'missing': [{'code': 'Payroll', 'missing': 'AttendanceSummary'}, {'code': 'PenaltyReport', 'missing': 'PenaltyTickets'}], 'unknown': [],
    'stores': 18, 'activeStores': 17, 'expiringStores': 2, 'unusedKeys': 6,
  },
  {
    'id': 'p3', 'name': 'HRM Doanh nghiệp', 'description': 'Gói gán tay cho khách lớn', 'isActive': true, 'isPublic': false, 'productLine': 'hrm',
    'maxUsers': 0, 'maxBranches': 0, 'maxDevices': 10, 'modules': ['Attendance', 'AttendanceSummary', 'Payroll', 'AdvanceRequests'],
    'missing': [], 'unknown': ['FieldCheckInOld'], 'stores': 3, 'activeStores': 3, 'expiringStores': 0, 'unusedKeys': 0,
  },
];

final _stores = {
  'items': [
    {
      'id': 's1', 'name': 'Cà phê Sana Q1', 'code': 'sanaq1', 'ownerName': 'Nguyễn Văn An', 'ownerPhone': '0901234567', 'status': 'expiring',
      'expiryDate': DateTime.now().add(const Duration(days: 4)).toIso8601String(), 'daysLeft': 4, 'packageName': 'POS + Nhân sự', 'productLine': 'both',
      'renewalCount': 2, 'users': 8, 'maxUsers': 20, 'extraCount': 1, 'blockedCount': 0, 'agentName': 'Đại lý Miền Nam',
    },
    {
      'id': 's2', 'name': 'Shop Thời trang Hà', 'code': 'shopha', 'ownerName': 'Phạm Thu Hà', 'ownerEmail': 'ha@shop.vn', 'status': 'active',
      'expiryDate': DateTime.now().add(const Duration(days: 210)).toIso8601String(), 'daysLeft': 210, 'packageName': 'POS Cơ bản', 'productLine': 'pos',
      'renewalCount': 3, 'users': 4, 'maxUsers': 5, 'extraCount': 0, 'blockedCount': 0,
    },
    {
      'id': 's3', 'name': 'Xưởng may Bảo Long', 'code': 'baolong', 'ownerName': 'Lê Quốc Bảo', 'status': 'locked', 'isLocked': true, 'lockReason': 'Chưa thanh toán gia hạn',
      'expiryDate': DateTime.now().subtract(const Duration(days: 12)).toIso8601String(), 'daysLeft': -12, 'packageName': 'HRM Doanh nghiệp', 'productLine': 'hrm',
      'renewalCount': 1, 'users': 64, 'maxUsers': 0, 'extraCount': 0, 'blockedCount': 2,
    },
  ],
  'total': 3, 'page': 1, 'pageSize': 50,
  'counts': {'all': 57, 'active': 41, 'trial': 6, 'expiring': 5, 'expired': 3, 'locked': 2},
};

final _security = {
  'id': 'u1', 'email': 'an@sana.vn', 'name': 'Nguyễn Văn An', 'role': 'Admin', 'isActive': true, 'lastLoginAt': DateTime.now().toIso8601String(),
  'storeName': 'Cà phê Sana Q1', 'storeCode': 'sanaq1', 'lockedUntil': DateTime.now().add(const Duration(minutes: 10)).toIso8601String(),
  'failedAttempts': 5, 'hasSession': true,
  'devices': [{'platform': 'android', 'deviceName': 'Samsung A54', 'createdAt': DateTime.now().toIso8601String()}],
  'logins': [
    {'action': 'LoginFailed', 'timestamp': DateTime.now().toIso8601String(), 'ipAddress': '14.161.2.10'},
    {'action': 'Login', 'timestamp': DateTime.now().subtract(const Duration(days: 1)).toIso8601String(), 'ipAddress': '14.161.2.10'},
  ],
};

final _keys = {
  'items': [
    {'id': 'k1', 'key': 'SBOX-7KQ2-M9XA-4TPL', 'durationDays': 365, 'isUsed': false, 'isActive': true, 'createdAt': DateTime.now().toIso8601String(),
      'licenseType': 'Pro', 'packageName': 'POS + Nhân sự', 'agentName': 'Đại lý Miền Nam'},
    {'id': 'k2', 'key': 'SBOX-3HD8-ZP2Q-91LC', 'durationDays': 180, 'isUsed': true, 'isActive': true, 'activatedAt': DateTime.now().toIso8601String(),
      'createdAt': DateTime.now().toIso8601String(), 'licenseType': 'Basic', 'packageName': 'POS Cơ bản', 'storeName': 'Shop Thời trang Hà', 'storeCode': 'shopha'},
    {'id': 'k3', 'key': 'SBOX-9MM1-QW7E-2RTY', 'durationDays': 30, 'isUsed': false, 'isActive': false, 'createdAt': DateTime.now().toIso8601String(),
      'licenseType': 'Basic', 'packageName': 'POS Cơ bản', 'notes': 'Thu hồi do cấp nhầm'},
  ],
  'total': 3, 'page': 1, 'pageSize': 50, 'counts': {'unused': 128, 'used': 342, 'revoked': 9, 'all': 479},
};

final _agents = [
  {'id': 'a1', 'name': 'Đại lý Miền Nam', 'code': 'DLMN', 'phone': '0909111222', 'isActive': true, 'maxStores': 50, 'stores': 38, 'activeStores': 33,
    'expiringStores': 4, 'expiredStores': 1, 'unusedKeys': 12, 'usedKeys': 40, 'activations30': 9, 'newStores30': 5, 'renewalDayBalance': 120, 'isRegistrationCompleted': true},
  {'id': 'a2', 'name': 'Sana Hà Nội', 'code': 'SNHN', 'email': 'hn@sana.vn', 'isActive': true, 'maxStores': 0, 'stores': 21, 'activeStores': 20,
    'expiringStores': 0, 'expiredStores': 0, 'unusedKeys': 2, 'usedKeys': 25, 'activations30': 4, 'newStores30': 2, 'renewalDayBalance': 0, 'isRegistrationCompleted': false},
];

final _status = {
  'database': {'ok': true, 'latencyMs': 12},
  'backups': {'count': 14, 'totalMb': 820.5, 'last': DateTime.now().subtract(const Duration(days: 3)).toIso8601String()},
  'disk': {'freeGb': 41.2, 'totalGb': 200.0},
  'maintenance': [{'title': 'Nâng cấp máy chủ', 'startAt': DateTime.now().add(const Duration(days: 2)).toIso8601String(), 'endAt': DateTime.now().add(const Duration(days: 2, hours: 2)).toIso8601String(), 'running': false, 'blockAccess': true}],
  'security': {'failedLogins': 23, 'impersonations': 1, 'deletes': 4},
  'stores': {'expiring': 5, 'expiredToday': 1},
  'keys': {'unusedUnassigned': 3},
  'server': {'version': '1.0.713', 'uptimeHours': 52.4, 'machine': 'sbox-api-1'},
  'warnings': [
    {'level': 'warning', 'text': 'Bản sao lưu gần nhất đã 3 ngày', 'tab': 'database'},
    {'level': 'info', 'text': '5 cửa hàng hết hạn trong 7 ngày tới', 'tab': 'stores'},
    {'level': 'info', 'text': 'Kho key chưa giao chỉ còn 3', 'tab': 'licenses'},
  ],
};

http.Response _ok(Object data) =>
    http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

final _client = MockClient((req) async {
  final p = req.url.path;
  if (p.endsWith('/v2/catalog')) return _ok(_catalog);
  if (p.endsWith('/v2/packages')) return _ok(_packages);
  if (p.endsWith('/v2/stores')) return _ok(_stores);
  if (p.endsWith('/security')) return _ok(_security);
  if (p.endsWith('/v2/licenses')) return _ok(_keys);
  if (p.endsWith('/v2/agents')) return _ok(_agents);
  if (p.endsWith('/v2/system-status')) return _ok(_status);
  return http.Response(jsonEncode({'isSuccess': false, 'message': 'not mocked $p'}), 200);
});

Future<void> _pump(WidgetTester tester, Widget home, Size size, String name, {bool tall = true, Future<void> Function()? before}) async {
  final key = GlobalKey();
  Widget app(Size s) => ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeProvider().lightTheme,
            home: MediaQuery(data: MediaQueryData(size: s), child: Scaffold(body: home)),
          ),
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
      await settle(8);
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

  test('Phụ thuộc chức năng: phát hiện thiếu và tự thêm đệ quy', () {
    final c = SaCatalog.fromJson(_catalog);
    final miss = c.missing({'Payroll', 'PenaltyReport'});
    expect(miss, contains(('Payroll', 'AttendanceSummary')));
    final fixed = c.withDependencies({'Payroll'});
    expect(fixed, containsAll(['Payroll', 'AttendanceSummary', 'Attendance']));
    expect(c.missing(fixed), isEmpty);
    expect(c.nameOf('PosKds'), 'Màn hình bếp (KDS)');
  });

  testWidgets('Gói dịch vụ — máy tính', (t) async {
    await _pump(t, const PackagesV2Tab(), const Size(1440, 900), 'sa_packages_desktop');
    expect(find.text('POS + Nhân sự'), findsOneWidget);
    expect(find.textContaining('chức năng thiếu phụ thuộc'), findsOneWidget);
  });

  testWidgets('Gói dịch vụ — điện thoại', (t) async {
    await _pump(t, const PackagesV2Tab(), const Size(390, 844), 'sa_packages_mobile');
    expect(find.text('Tạo gói'), findsOneWidget);
  });

  testWidgets('Trình sửa gói — máy tính', (t) async {
    await _pump(
        t,
        PackageEditorPage(api: ApiService(), catalog: SaCatalog.fromJson(_catalog), package: _packages[1]),
        const Size(1440, 1000),
        'sa_package_editor_desktop',
        tall: false);
    expect(find.textContaining('cần «Tổng hợp chấm công»'), findsOneWidget);
    expect(find.text('Tự thêm'), findsOneWidget);
    expect(find.textContaining('Trọn bộ POS + HRM'), findsOneWidget);
  });

  testWidgets('Cửa hàng — máy tính', (t) async {
    await _pump(t, const StoresV2View(), const Size(1440, 900), 'sa_stores_desktop', before: () async {
      await t.tap(find.byType(Checkbox).first);
    });
    expect(find.textContaining('Sắp hết hạn (5)'), findsOneWidget);
    expect(find.text('Gia hạn 3/3'), findsOneWidget);
    expect(find.text('Đã chọn 1'), findsOneWidget);
  });

  testWidgets('Cửa hàng — điện thoại', (t) async {
    await _pump(t, const StoresV2View(), const Size(390, 844), 'sa_stores_mobile');
    expect(find.text('Cà phê Sana Q1'), findsOneWidget);
  });

  testWidgets('Bảo mật & hỗ trợ tài khoản', (t) async {
    await _pump(
        t,
        Builder(builder: (ctx) => Center(child: ElevatedButton(onPressed: () => showSaUserSecurityDialog(ctx, {'id': 'u1', 'fullName': 'Nguyễn Văn An'}), child: const Text('open')))),
        const Size(1280, 860),
        'sa_user_security_dialog',
        tall: false, before: () async {
      await t.tap(find.text('open'));
    });
    expect(find.text('Đăng nhập thay'), findsOneWidget);
    expect(find.textContaining('Bị khóa đến'), findsOneWidget);
  });

  testWidgets('Kho key — máy tính', (t) async {
    await _pump(t, const KeysV2View(), const Size(1440, 900), 'sa_keys_desktop');
    expect(find.text('SBOX-7KQ2-M9XA-4TPL'), findsOneWidget);
    expect(find.text('Xuất CSV'), findsOneWidget);
  });

  testWidgets('Hiệu quả đại lý — máy tính', (t) async {
    await _pump(t, const AgentsV2View(), const Size(1440, 900), 'sa_agents_desktop');
    expect(find.text('Kích hoạt key 30 ngày theo đại lý'), findsOneWidget);
    expect(find.text('Chưa hoàn tất đăng ký tài khoản'), findsOneWidget);
  });

  testWidgets('Tình trạng hệ thống — điện thoại', (t) async {
    await _pump(t, const SystemStatusView(), const Size(390, 844), 'sa_system_status_mobile');
    expect(find.text('Bản sao lưu gần nhất đã 3 ngày'), findsOneWidget);
  });
}
