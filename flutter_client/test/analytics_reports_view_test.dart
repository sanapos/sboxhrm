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
import 'package:zkteco_flutter_client/providers/permission_provider.dart';
import 'package:zkteco_flutter_client/providers/theme_provider.dart';
import 'package:zkteco_flutter_client/screens/analytics_reports_screen.dart';
import 'package:zkteco_flutter_client/l10n/app_localizations.dart';

/// Báo cáo phân tích: nhãn biểu đồ / bảng là tên nhân viên (mã ở dòng phụ). Đặt SBOX_SHOT_DIR để lưu ảnh duyệt giao diện.
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

final _compliance = {
  'year': 2026, 'month': 10, 'standardDays': 26, 'totalEmployees': 8, 'avgComplianceRate': 79.3,
  'items': [
    {'employeeId': 'g0', 'employeeCode': 'NV001', 'employeeName': 'Nguyễn Văn An', 'department': 'Bán hàng', 'standardDays': 26, 'presentDays': 26, 'lateDays': 0, 'leaveDays': 0, 'absentDays': 0, 'complianceRate': 100},
    {'employeeId': 'g1', 'employeeCode': 'NV002', 'employeeName': 'Trần Thị Bình', 'department': 'Kho', 'standardDays': 26, 'presentDays': 25, 'lateDays': 1, 'leaveDays': 1, 'absentDays': 0, 'complianceRate': 96.2},
    {'employeeId': 'g2', 'employeeCode': 'NV003', 'employeeName': 'Lê Hoàng Cường', 'department': 'Bán hàng', 'standardDays': 26, 'presentDays': 24, 'lateDays': 2, 'leaveDays': 0, 'absentDays': 2, 'complianceRate': 92.3},
    {'employeeId': 'g3', 'employeeCode': 'NV004', 'employeeName': 'Phạm Thu Dung', 'department': 'Kế toán', 'standardDays': 26, 'presentDays': 23, 'lateDays': 0, 'leaveDays': 1, 'absentDays': 2, 'complianceRate': 88.5},
    {'employeeId': 'g4', 'employeeCode': 'NV005', 'employeeName': 'Hoàng Minh Đức', 'department': 'Kho', 'standardDays': 26, 'presentDays': 21, 'lateDays': 1, 'leaveDays': 0, 'absentDays': 5, 'complianceRate': 80.8},
    {'employeeId': 'g5', 'employeeCode': 'NV006', 'employeeName': 'Võ Thị Hà', 'department': 'Bán hàng', 'standardDays': 26, 'presentDays': 19, 'lateDays': 2, 'leaveDays': 1, 'absentDays': 6, 'complianceRate': 73.1},
    {'employeeId': 'g6', 'employeeCode': 'NV007', 'employeeName': 'Đặng Quốc Huy', 'department': 'Giao hàng', 'standardDays': 26, 'presentDays': 16, 'lateDays': 0, 'leaveDays': 0, 'absentDays': 10, 'complianceRate': 61.5},
    {'employeeId': 'g7', 'employeeCode': 'NV008', 'employeeName': 'Bùi Thanh Lan', 'department': 'Kế toán', 'standardDays': 26, 'presentDays': 11, 'lateDays': 1, 'leaveDays': 1, 'absentDays': 14, 'complianceRate': 42.3}
  ],
};

final _expiring = {
  'expiringCount': 1, 'expiredCount': 1, 'usedUpCount': 1, 'lowSessionsCount': 0, 'renewedCount': 0,
  'items': [
    {'customerName': 'Nguyễn Văn An', 'phone': '0901000001', 'packageName': 'Thẻ 1 tháng', 'kind': 'Thẻ thời gian', 'usedSessions': 18,
     'remainingSessions': 'Không giới hạn', 'expiresAt': '20/10/2026', 'daysLeft': 3, 'lastUsedAt': '16/10/2026', 'status': 'Sắp hết hạn', 'renewed': false},
    {'customerName': 'Trần Thị Bình', 'phone': '0901000002', 'packageName': 'Gói 10 buổi', 'kind': 'Gói buổi', 'usedSessions': 10,
     'remainingSessions': '0', 'expiresAt': '', 'daysLeft': null, 'lastUsedAt': '12/10/2026', 'status': 'Đã hết buổi', 'renewed': false},
    {'customerName': 'Lê Hoàng Cường', 'phone': '0901000003', 'packageName': 'Thẻ 3 tháng', 'kind': 'Thẻ thời gian', 'usedSessions': 40,
     'remainingSessions': 'Không giới hạn', 'expiresAt': '10/10/2026', 'daysLeft': -7, 'lastUsedAt': '09/10/2026', 'status': 'Đã hết hạn', 'renewed': false},
  ],
};

final _stay = {
  'from': '2026-10-01T00:00:00.000', 'to': '2026-10-17T00:00:00.000', 'total': 2, 'missingIdCount': 1,
  'items': [
    {'id': 'a', 'roomCode': 'P101', 'roomName': 'Phòng 101', 'checkInAt': '2026-10-10T21:30:00.000', 'checkOutAt': null,
     'fullName': 'Nguyễn Văn An', 'idType': 'CCCD', 'idNumber': '001090000001', 'dateOfBirth': '1990-05-01T00:00:00.000',
     'gender': 'Nam', 'nationality': 'Việt Nam', 'isPrimary': true},
    {'id': 'b', 'roomCode': 'P101', 'roomName': 'Phòng 101', 'checkInAt': '2026-10-11T08:05:00.000', 'checkOutAt': null,
     'fullName': 'Trần Thị Bình', 'idType': 'CCCD', 'idNumber': null, 'dateOfBirth': null, 'isPrimary': false},
  ],
};

final _client = MockClient((req) async => http.Response(
    jsonEncode({
      'isSuccess': true,
      'data': req.url.path.contains('compliance')
          ? _compliance
          : req.url.path.contains('session-balances')
              ? _expiring
              : req.url.path.contains('stay-guests')
                  ? _stay
                  : {},
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'}));

final errors = <String>[];
Future<void> _pump(WidgetTester tester, Widget home, Size size, String name, {Future<void> Function()? before}) async {
  final key = GlobalKey();
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await http.runWithClient(() async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PermissionProvider()..loadPermissions(role: 'Admin')),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeProvider().lightTheme,
          localizationsDelegates: const [AppLocalizations.delegate, DefaultMaterialLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
          home: MediaQuery(data: MediaQueryData(size: size), child: home),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (before != null) {
      await before();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    final ex = tester.takeException();
    if (ex != null) errors.add('$name: $ex');
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
  for (final size in const [Size(360, 1700), Size(1200, 1300)]) {
    testWidgets('chuyên cần ${size.width}', (t) async {
      await _pump(t, const AnalyticsReportsScreen(), size, 'an_compliance_${size.width.toInt()}', before: () async {
        await t.tap(find.text('Tỷ lệ chuyên cần'));
        for (var i = 0; i < 10; i++) {
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
          await t.pump(const Duration(milliseconds: 100));
        }
      });
      expect(find.text('NV001'), findsNothing, reason: 'mã không làm nhãn chính');
      expect(find.text('Nguyễn Văn An'), findsWidgets);
    });
    testWidgets('thẻ tập sắp hết hạn ${size.width}', (t) async {
      await _pump(t, const AnalyticsReportViewer(spec: AnalyticsReportSpec.sessionExpiry), size,
          'an_session_expiry_${size.width.toInt()}');
      // Xếp hạng «số buổi đã dùng» không giúp gọi nhắc gia hạn → không vẽ.
      expect(find.textContaining('Xếp hạng'), findsNothing);
      expect(find.text('Đã hết buổi'), findsWidgets);
      expect(find.text('Trần Thị Bình'), findsWidgets);
    });
    testWidgets('sổ khách lưu trú ${size.width}', (t) async {
      await _pump(t, const AnalyticsReportViewer(spec: AnalyticsReportSpec.stayGuests), size,
          'an_stay_guests_${size.width.toInt()}');
      expect(find.text('Thiếu giấy tờ / ngày sinh'), findsOneWidget);
      if (size.width > 600) {
        expect(find.text('10/10/2026 21:30'), findsOneWidget, reason: 'giờ nhận phòng là giờ VN từ máy chủ');
        expect(find.text('Ngày sinh'), findsOneWidget);
      }
      expect(find.textContaining('birth'), findsNothing);
    });
  }
}
