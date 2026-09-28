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
import 'package:zkteco_flutter_client/screens/overview/business_overview_screen.dart';
import 'package:zkteco_flutter_client/widgets/sbox/sbox_ui.dart';

/// Tổng quan HRM / POS / HRM+POS với dữ liệu giả, khổ máy tính và điện thoại.
/// Đặt SBOX_SHOT_DIR để lưu ảnh PNG duyệt giao diện.
Future<void> _loadFonts() async {
  final fl = FontLoader('BeVietnamPro');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    final bytes = File('assets/fonts/BeVietnamPro-$f.ttf').readAsBytesSync();
    fl.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await fl.load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final il = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)));
      await il.load();
    }
  }
}

http.Response _json(Object body) =>
    http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});

final _today = DateTime(2026, 9, 27);
String _d(int back) => _today.subtract(Duration(days: back)).toIso8601String();

Map<String, dynamic> _sales({double scale = 1}) => {
      'totalRevenue': 48250000 * scale,
      'totalProfit': 17900000 * scale,
      'totalPaid': 47100000 * scale,
      'orderCount': (186 * scale).round(),
      'byPayment': [
        {'paymentMethod': 'Tiền mặt', 'total': 21500000 * scale, 'count': 90},
        {'paymentMethod': 'Chuyển khoản', 'total': 17800000 * scale, 'count': 60},
        {'paymentMethod': 'Thẻ', 'total': 5200000 * scale, 'count': 20},
        {'paymentMethod': 'Ví điện tử', 'total': 2600000 * scale, 'count': 16},
      ],
      'profitByDay': [
        for (var i = 6; i >= 0; i--)
          {
            'date': _d(i),
            'revenue': (5200000 + (i * 917000) % 3100000) * scale,
            'profit': (1900000 + (i * 431000) % 1200000) * scale,
            'cogs': 0,
            'count': 20 + i,
          },
      ],
      'topProducts': [
        {'productName': 'Cà phê sữa đá', 'qty': 412, 'revenue': 11536000},
        {'productName': 'Trà đào cam sả', 'qty': 268, 'revenue': 9380000},
        {'productName': 'Bạc xỉu', 'qty': 190, 'revenue': 5890000},
        {'productName': 'Bánh mì thịt nướng', 'qty': 150, 'revenue': 4200000},
        {'productName': 'Nước ép cam', 'qty': 88, 'revenue': 3080000},
      ],
      'topEmployees': [
        {'soldBy': 'Nguyễn Thị Lan', 'revenue': 18400000, 'orderCount': 71},
        {'soldBy': 'Trần Văn Minh', 'revenue': 15250000, 'orderCount': 58},
        {'soldBy': 'Lê Hoàng Anh', 'revenue': 9800000, 'orderCount': 39},
        {'soldBy': 'Phạm Thu Hà', 'revenue': 4800000, 'orderCount': 18},
      ],
    };

final _manager = {
  'attendanceRate': {
    'totalEmployeesWithShift': 24,
    'presentEmployees': 19,
    'lateEmployees': 4,
    'absentEmployees': 3,
    'onLeaveEmployees': 2,
    'attendancePercentage': 79.2,
    'punctualityPercentage': 78.9,
  },
  'lateEmployees': [
    {'fullName': 'Trần Văn Minh', 'lateBy': '00:25:00', 'department': 'Pha chế'},
    {'fullName': 'Đỗ Mai Chi', 'lateBy': '00:12:00', 'department': 'Thu ngân'},
    {'fullName': 'Vũ Quốc Bảo', 'lateBy': '00:07:00', 'department': 'Phục vụ'},
  ],
  'todayEmployees': [
    {'fullName': 'Nguyễn Thị Lan', 'department': 'Thu ngân', 'status': 'Present', 'shiftStartTime': '2026-09-27T07:00:00', 'shiftEndTime': '2026-09-27T15:00:00', 'checkInTime': '2026-09-27T06:52:00', 'checkOutTime': null},
    {'fullName': 'Trần Văn Minh', 'department': 'Pha chế', 'status': 'Late', 'shiftStartTime': '2026-09-27T07:00:00', 'shiftEndTime': '2026-09-27T15:00:00', 'checkInTime': '2026-09-27T07:25:00'},
    {'fullName': 'Hoàng Gia Huy', 'department': 'Phục vụ', 'status': 'Absent', 'shiftStartTime': '2026-09-27T08:00:00', 'shiftEndTime': '2026-09-27T16:00:00'},
    {'fullName': 'Phạm Thu Hà', 'department': 'Thu ngân', 'status': 'On Leave', 'shiftStartTime': '2026-09-27T15:00:00', 'shiftEndTime': '2026-09-27T22:00:00'},
  ],
};

final _trends = [
  for (var i = 6; i >= 0; i--)
    {'date': _d(i), 'onTime': 16 + (i * 3) % 5, 'late': 2 + i % 3, 'absent': i % 2 + 1, 'present': 20, 'total': 24},
];

final _todos = [
  {'key': 'leave', 'group': 'hrm', 'label': 'Đơn nghỉ phép chờ duyệt', 'count': 3, 'severity': 'warning'},
  {'key': 'mobileAttendance', 'group': 'hrm', 'label': 'Chấm công mobile chờ duyệt', 'count': 5, 'severity': 'warning'},
  {'key': 'correction', 'group': 'hrm', 'label': 'Yêu cầu sửa công chờ duyệt', 'count': 0, 'severity': 'warning'},
  {'key': 'advance', 'group': 'hrm', 'label': 'Ứng lương chờ duyệt', 'count': 1, 'severity': 'warning'},
  {'key': 'outOfStock', 'group': 'pos', 'label': 'Hàng đã hết', 'count': 2, 'severity': 'danger'},
  {'key': 'lowStock', 'group': 'pos', 'label': 'Hàng dưới tồn tối thiểu', 'count': 7, 'severity': 'warning'},
  {'key': 'onlinePending', 'group': 'pos', 'label': 'Đơn online chờ xác nhận', 'count': 2, 'severity': 'danger'},
  {'key': 'codPending', 'group': 'pos', 'label': 'Đơn COD chưa đối soát', 'count': 4, 'severity': 'info'},
];

final _client = MockClient((req) async {
  final p = req.url.path;
  if (p.endsWith('/api/overview/todos')) return _json({'isSuccess': true, 'data': _todos});
  if (p.endsWith('/sales/summary')) {
    final from = DateTime.tryParse(req.url.queryParameters['from'] ?? '');
    // Kỳ trước (from < hôm nay) nhỏ hơn một chút để thấy % tăng.
    final prev = from != null && from.isBefore(DateTime.now().subtract(const Duration(days: 1)));
    return _json({'isSuccess': true, 'data': _sales(scale: prev ? 0.86 : 1)});
  }
  if (p.endsWith('/stock/summary')) return _json({'isSuccess': true, 'data': {'outOfStockCount': 2}});
  if (p.toLowerCase().endsWith('/dashboard/manager')) return _json({'isSuccess': true, 'data': _manager});
  if (p.endsWith('/attendance-trends')) return _json({'isSuccess': true, 'data': _trends});
  return _json({'isSuccess': false, 'message': 'not mocked $p'});
});

Future<void> _pump(WidgetTester tester, OverviewMode mode, Size size, String name) async {
  final key = GlobalKey();
  Widget app(Size s) => RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeProvider().lightTheme,
          home: MediaQuery(
            data: MediaQueryData(size: s),
            child: Scaffold(body: BusinessOverviewScreen(mode: mode, showLegacyLink: false, canAccess: (_) => true)),
          ),
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
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
    final tall = Size(size.width, scrollable.position.maxScrollExtent + size.height);
    await setSize(tall);
    await tester.pumpWidget(app(tall));
    await tester.pump(const Duration(milliseconds: 600));
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

  test('Kỳ so sánh: tháng này ↔ cùng số ngày tháng trước', () {
    final now = DateTime(2026, 3, 30, 10);
    final (f, t) = SboxPeriod.thisMonth.previousRange(now);
    expect(f, DateTime(2026, 2, 1));
    expect(t.day, 28);
    final (yf, yt) = SboxPeriod.today.previousRange(now);
    expect(yf, DateTime(2026, 3, 29));
    expect(yt.day, 29);
    final (lf, lt) = SboxPeriod.last7.previousRange(now);
    expect(lf, DateTime(2026, 3, 17));
    expect(lt.day, 23);
  });

  test('KPI: % thay đổi và chiều tốt/xấu', () {
    final up = const SboxKpi(label: 'DT', value: '', current: 115, previous: 100).delta!;
    expect(up.text, '+15,0%');
    expect(up.good, true);
    final cost = const SboxKpi(label: 'Trễ', value: '', current: 5, previous: 4, higherIsBetter: false).delta!;
    expect(cost.good, false);
    expect(cost.up, true);
    expect(const SboxKpi(label: 'x', value: '', current: 0, previous: 0).delta!.good, isNull);
  });

  for (final (mode, tag) in [
    (OverviewMode.combined, 'combined'),
    (OverviewMode.pos, 'pos'),
    (OverviewMode.hrm, 'hrm'),
  ]) {
    testWidgets('Tổng quan $tag — máy tính 1440', (tester) async {
      await _pump(tester, mode, const Size(1440, 900), 'overview_${tag}_desktop');
      expect(find.text('Việc cần xử lý'), findsOneWidget);
    });
    testWidgets('Tổng quan $tag — điện thoại 390', (tester) async {
      await _pump(tester, mode, const Size(390, 844), 'overview_${tag}_mobile');
      expect(find.text('Việc cần xử lý'), findsOneWidget);
    });
  }
}
