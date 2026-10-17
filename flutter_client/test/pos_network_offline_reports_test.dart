import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/l10n/app_localizations.dart';
import 'package:zkteco_flutter_client/providers/auth_provider.dart';
import 'package:zkteco_flutter_client/providers/permission_provider.dart';
import 'package:zkteco_flutter_client/providers/theme_provider.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_network_report_screen.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_offline_sales_screen.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_risk_report_screen.dart';

/// «Mạng cửa hàng» + «Bán offline & kiểm soát»: dựng với số liệu mẫu (đúng dạng JSON máy chủ trả), không lỗi
/// giao diện, có kết luận / việc nên làm / đồ thị. Đặt SBOX_SHOT_DIR để lưu ảnh duyệt giao diện.
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

String _vn(int h, {int day = 17}) => DateTime.utc(2026, 10, day, h).toIso8601String();

Map<String, dynamic> _hour(int h, String health, int orders, int print, int? p95, {double fail = 0, int off = 0, int disc = 0}) => {
      'hourVn': _vn(h), 'devices': 3, 'pingSent': 360, 'pingFailed': (360 * fail / 100).round(), 'failPct': fail,
      'latencyP95Ms': p95, 'maxDeviceOfflineSec': off, 'disconnects': disc, 'orders': orders, 'printJobs': print,
      'printP95Sec': print == 0 ? null : 3.5, 'health': health,
    };

final _network = {
  'verdict': 'yellow',
  'verdictText': 'Mạng chập chờn lúc cao điểm / có lúc rớt — dùng được nhưng nên khắc phục',
  'score': 72, 'sampleCount': 540, 'deviceCount': 3, 'failPct': 1.8, 'latencyP95Ms': 1150,
  'outageCount': 2, 'outageSeconds': 210, 'disconnects': 6, 'degradesAtPeak': true,
  'peakNote': 'Giờ đông: lỗi 4.2% · trễ 1900 ms — giờ khác: lỗi 0.3% · trễ 240 ms',
  'hours': [
    _hour(7, 'green', 4, 6, 210),
    _hour(8, 'green', 9, 12, 230),
    _hour(9, 'green', 6, 8, 250),
    _hour(10, 'green', 5, 7, 240),
    _hour(11, 'yellow', 22, 30, 1300, fail: 2.5, disc: 2),
    _hour(12, 'red', 31, 44, 2100, fail: 6.1, off: 150, disc: 3),
    _hour(13, 'yellow', 18, 25, 900, fail: 1.2, disc: 1),
    _hour(14, 'green', 3, 4, 220),
    _hour(15, 'none', 2, 1, null),
    _hour(16, 'green', 6, 9, 260),
    _hour(17, 'green', 12, 15, 300),
    _hour(18, 'yellow', 25, 33, 1100, fail: 1.5),
    _hour(19, 'yellow', 28, 39, 1250, fail: 2.0, off: 60),
    _hour(20, 'green', 14, 20, 320),
    _hour(21, 'green', 4, 5, 230),
  ],
  'devices': [
    {'deviceId': 'd1', 'deviceName': 'Máy thu ngân Sunmi T2', 'platform': 'android', 'isAgent': true, 'lastSeenVn': _vn(21),
      'samples': 180, 'pingSent': 1800, 'failPct': 2.4, 'latencyP95Ms': 1300, 'offlineSec': 150, 'outages': 1,
      'disconnects': 4, 'wifiRssi': -74, 'connType': 'wifi', 'printerChecks': 90, 'printerFailed': 12, 'health': 'red'},
    {'deviceId': 'd2', 'deviceName': 'Điện thoại order 1', 'platform': 'android', 'isAgent': false, 'lastSeenVn': _vn(21),
      'samples': 180, 'pingSent': 1800, 'failPct': 1.1, 'latencyP95Ms': 700, 'offlineSec': 60, 'outages': 1,
      'disconnects': 2, 'wifiRssi': -62, 'connType': 'wifi', 'printerChecks': 0, 'printerFailed': 0, 'health': 'yellow'},
    {'deviceId': 'd3', 'deviceName': 'Máy tính quầy bar', 'platform': 'windows', 'isAgent': false, 'lastSeenVn': _vn(21),
      'samples': 180, 'pingSent': 1800, 'failPct': 0, 'latencyP95Ms': 260, 'offlineSec': 0, 'outages': 0,
      'disconnects': 0, 'wifiRssi': null, 'connType': 'ethernet', 'printerChecks': 0, 'printerFailed': 0, 'health': 'green'},
  ],
  'outages': [
    {'deviceId': 'd2', 'deviceName': 'Điện thoại order 1', 'isAgent': false, 'startVn': _vn(19), 'seconds': 60, 'kind': 'Mất kết nối máy chủ'},
    {'deviceId': 'd1', 'deviceName': 'Máy thu ngân Sunmi T2', 'isAgent': true, 'startVn': _vn(12), 'seconds': 150, 'kind': 'Mất kết nối máy chủ'},
  ],
  'print': {'total': 258, 'completed': 246, 'failed': 3, 'cancelled': 9, 'staleQueued': 5, 'stuckNoRequeue': 1, 'p50Sec': 2.1, 'p95Sec': 9.4},
  'recommendations': [
    {'code': 'PEAK', 'level': 'high', 'title': 'Mạng tệ đúng giờ đông khách',
      'detail': 'Router quá tải khi khách dùng chung Wi‑Fi. Tách Wi‑Fi riêng cho máy POS / máy in, giới hạn băng thông Wi‑Fi khách.'},
    {'code': 'AGENT', 'level': 'high', 'title': 'Máy giữ máy in (Agent) «Máy thu ngân Sunmi T2» hay mất kết nối',
      'detail': 'Máy khác in qua máy này — nên cắm dây LAN, tắt tiết kiệm pin / tự tắt màn hình, không dùng 4G.'},
    {'code': 'WEAK_WIFI', 'level': 'medium', 'title': 'Sóng Wi‑Fi yếu ở «Máy thu ngân Sunmi T2» (-74 dBm)',
      'detail': 'Đặt máy gần router / thêm bộ phát, hoặc cắm dây LAN.'},
  ],
};

final _audit = {
  'verdict': 'red',
  'verdictText': 'Có 1 dấu hiệu bất thường — cần kiểm tra ngay',
  'verdictDetail': 'Có số hóa đơn offline đã dùng (đã in cho khách) mà chưa thấy đơn trên máy chủ. '
      'Làm theo «Cách xử lý» ở từng cảnh báo bên dưới.',
  'settings': {'enabled': true, 'maxHours': 8},
  'summary': {'offlineSales': 37, 'offlineTotal': 8450000, 'devices': 2, 'reinstalls': 1, 'alerts': 1, 'mediumAlerts': 0,
    'pendingOnDevices': 2, 'serialsIssued': 100, 'serialsUsed': 38, 'gaps': 1, 'avgDelayMinutes': 42, 'maxDelayMinutes': 1500},
  'alerts': [
    {'level': 'high', 'kind': 'GAP', 'device': 'Máy thu ngân Sunmi T2', 'text': '1 số nhảy cóc (đã in cho khách nhưng không về máy chủ)',
      'range': 'OFF-000001 – OFF-000050',
      'action': 'Mở app trên máy «Máy thu ngân Sunmi T2» khi có mạng → «Bán offline & kiểm soát» → «Gửi ngay». '
          'Nếu máy không còn đơn: hỏi thu ngân (người dùng gần nhất: thungan@quan.vn) về các số OFF-000017, đối chiếu tiền mặt két ca.'},
    {'level': 'info', 'kind': 'REINSTALL', 'device': 'Điện thoại order 1', 'text': 'Cài lại app 1 lần (gần nhất 12/10 09:15)',
      'range': null, 'action': 'Bình thường nếu đổi máy / sửa lỗi app. Nếu không ai báo — hỏi quản lý ca.'},
  ],
  'devices': [
    {'deviceKey': 'a:1', 'deviceName': 'Máy thu ngân Sunmi T2', 'reinstalls': 0, 'pendingOfflineSales': 2, 'lastSeenAt': '2026-10-17T03:00:00Z',
      'installs': [
        {'installId': 'i1abcdefghijk', 'platform': 'android', 'appVersion': '2.8.1', 'firstSeenAt': '2026-09-01T02:00:00Z',
          'lastSeenAt': '2026-10-17T03:00:00Z', 'osFirstInstallAt': null, 'lastUserName': 'thungan@quan.vn', 'pendingOfflineSales': 2, 'lastOfflineSeq': 'OFF-000038'},
      ]},
    {'deviceKey': 'a:2', 'deviceName': 'Điện thoại order 1', 'reinstalls': 1, 'pendingOfflineSales': 0, 'lastSeenAt': '2026-10-17T03:00:00Z',
      'installs': [
        {'installId': 'i2abcdefghijk', 'platform': 'android', 'appVersion': '2.7.0', 'firstSeenAt': '2026-09-10T02:00:00Z',
          'lastSeenAt': '2026-10-12T02:00:00Z', 'osFirstInstallAt': null, 'lastUserName': 'phucvu@quan.vn', 'pendingOfflineSales': 0, 'lastOfflineSeq': null},
        {'installId': 'i3abcdefghijk', 'platform': 'android', 'appVersion': '2.8.1', 'firstSeenAt': '2026-10-12T02:15:00Z',
          'lastSeenAt': '2026-10-17T03:00:00Z', 'osFirstInstallAt': null, 'lastUserName': 'phucvu@quan.vn', 'pendingOfflineSales': 0, 'lastOfflineSeq': null},
      ]},
  ],
  'blocks': [
    {'deviceKey': 'a:1', 'deviceName': 'Máy thu ngân Sunmi T2', 'installId': 'i1', 'reservedAt': '2026-09-01T02:01:00Z',
      'reservedBy': 'chuquan@quan.vn', 'from': 'OFF-000001', 'to': 'OFF-000050', 'size': 50, 'used': 37, 'lastUsed': 'OFF-000038',
      'gaps': ['OFF-000017'], 'gapCount': 1, 'missingReported': [], 'installReplaced': false,
      'suspicious': ['1 số nhảy cóc (đã in cho khách nhưng không về máy chủ)']},
    {'deviceKey': 'a:2', 'deviceName': 'Điện thoại order 1', 'installId': 'i3', 'reservedAt': '2026-10-12T02:16:00Z',
      'reservedBy': 'chuquan@quan.vn', 'from': 'OFF-000051', 'to': 'OFF-000100', 'size': 50, 'used': 1, 'lastUsed': 'OFF-000051',
      'gaps': [], 'gapCount': 0, 'missingReported': [], 'installReplaced': false, 'suspicious': []},
  ],
  'sales': [
    for (var i = 0; i < 6; i++)
      {'id': 'o$i', 'orderNo': 'HD00${120 + i}', 'offlineNo': 'OFF-0000${30 + i}', 'offlineAt': '2026-10-16T05:${10 + i}:00Z',
        'syncedAt': '2026-10-16T05:${40 + i}:00Z', 'total': 185000 + i * 20000, 'createdBy': 'thungan@quan.vn',
        'device': 'Máy thu ngân Sunmi T2', 'delayMinutes': 30, 'status': 'Completed'},
  ],
  'daily': [
    for (var d = 0; d < 31; d++)
      {'dateVn': DateTime.utc(2026, 9, 17).add(Duration(days: d)).toIso8601String(),
        'count': const {3: 5, 9: 2, 16: 12, 22: 3, 29: 15}[d] ?? 0,
        'total': (const {3: 5, 9: 2, 16: 12, 22: 3, 29: 15}[d] ?? 0) * 228000},
  ],
  'delayBuckets': [
    {'label': 'Dưới 5 phút', 'count': 21},
    {'label': '5 – 60 phút', 'count': 9},
    {'label': '1 – 24 giờ', 'count': 6},
    {'label': 'Trên 1 ngày', 'count': 1},
  ],
};


Map<String, dynamic> _flag(String code, String level, String title, String detail, num amount) =>
    {'code': code, 'level': level, 'title': title, 'detail': detail, 'amount': amount};

final _risk = {
  'verdict': 'red',
  'verdictText': '3 đơn có dấu hiệu nghiêm trọng — cần kiểm tra',
  'verdictDetail': 'Tổng tiền cần soát 1.235.000đ. Phần lớn là giảm / hủy sau khi đã đưa khách phiếu tạm tính hoặc hủy '
      'hóa đơn đã thu tiền. Đây là dấu hiệu, chưa chắc là gian lận — xem «Cách kiểm tra».',
  'summary': {'ordersChecked': 412, 'riskOrders': 7, 'highOrders': 3, 'amountAtRisk': 1235000, 'reducedAfterBillAmount': 320000,
    'voidsAfterBill': 2, 'droppedBills': 2, 'paidCancels': 1, 'noReceipt': 38, 'noReceiptPct': 14.2, 'provisionalBills': 96},
  'byCode': [
    {'code': 'REDUCED_AFTER_BILL', 'label': 'Tiền thu ít hơn tạm tính', 'level': 'high', 'count': 2, 'amount': 320000},
    {'code': 'VOID_AFTER_BILL', 'label': 'Hủy món / hủy đơn sau tạm tính', 'level': 'high', 'count': 2, 'amount': 245000},
    {'code': 'CANCEL_PAID', 'label': 'Hủy đơn đã thanh toán', 'level': 'medium', 'count': 1, 'amount': 410000},
    {'code': 'DROPPED_BILL', 'label': 'Xóa / hủy đơn đang có món (đá bill)', 'level': 'medium', 'count': 2, 'amount': 260000},
    {'code': 'REPRINT', 'label': 'In lại hóa đơn nhiều lần', 'level': 'medium', 'count': 3, 'amount': 0},
  ],
  'orders': [
    {'key': 'o:1', 'orderId': 'o1', 'orderNo': 'HD001245', 'atUtc': '2026-10-16T12:40:00Z', 'resourceName': 'Bàn 12',
      'staff': 'Trần Bình, Nguyễn An', 'paymentMethod': 'Tiền mặt', 'total': 680000, 'provisionalTotal': 880000,
      'amountAtRisk': 200000, 'level': 'high',
      'flags': [_flag('REDUCED_AFTER_BILL', 'high', 'Tiền thu ít hơn tạm tính',
          'Phiếu tạm tính in 880.000đ (in 1 lần) nhưng chỉ thu 680.000đ — thiếu 200.000đ', 200000),
        _flag('VOID_AFTER_BILL', 'high', 'Hủy món / hủy đơn sau tạm tính',
          'Khách đã được đưa phiếu tạm tính, sau đó hủy 2 món (Bia Tiger, Mực nướng) — 200.000đ. Lý do ghi: «Khách đổi ý»', 200000)],
      'howToCheck': 'Xem camera quầy / bàn đúng giờ này: khách có trả theo phiếu tạm tính không → Hỏi nhân viên lý do, ghi lại kết quả'},
    {'key': 'o:2', 'orderId': 'o2', 'orderNo': 'HD001198', 'atUtc': '2026-10-15T14:05:00Z', 'resourceName': null,
      'staff': 'Trần Bình', 'paymentMethod': 'Tiền mặt', 'total': 410000, 'provisionalTotal': null,
      'amountAtRisk': 410000, 'level': 'high',
      'flags': [_flag('CANCEL_PAID', 'high', 'Hủy đơn đã thanh toán', 'Hủy hóa đơn đã thanh toán 410.000đ (Tiền mặt), 95 phút sau khi bán', 410000)],
      'howToCheck': 'Hỏi khách / kiểm tra tiền đã hoàn thật chưa, đối chiếu két cuối ca → Hỏi nhân viên lý do, ghi lại kết quả'},
    {'key': 's:3', 'orderId': null, 'orderNo': null, 'atUtc': '2026-10-14T13:00:00Z', 'resourceName': 'Bàn 3',
      'staff': 'Lê Cường', 'paymentMethod': null, 'total': 0, 'provisionalTotal': null,
      'amountAtRisk': 260000, 'level': 'medium',
      'flags': [_flag('DROPPED_BILL', 'medium', 'Xóa / hủy đơn đang có món (đá bill)', 'Đơn đang có món (Lẩu thái +2 món) bị hủy — 260.000đ, không ghi lý do', 260000)],
      'howToCheck': 'Hỏi bếp / bar món đã làm chưa, đối chiếu phiếu bếp → Hỏi nhân viên lý do, ghi lại kết quả'},
  ],
  'staff': [
    {'key': 'binh', 'name': 'Trần Bình', 'orders': 120, 'highSignals': 3, 'mediumSignals': 1, 'lowSignals': 20, 'amountAtRisk': 810000,
      'voidsAfterBill': 1, 'reducedAfterBill': 1, 'droppedBills': 0, 'paidCancels': 1, 'kitchenVoids': 6, 'noReceipt': 20,
      'cashOrders': 60, 'noReceiptPct': 33.3, 'level': 'red',
      'notes': ['2 lần giảm / hủy sau tạm tính', '1 hóa đơn đã thu bị hủy', '6 món bị hủy', 'Không in hóa đơn 33% đơn tiền mặt (cả quán 14%)']},
    {'key': 'cuong', 'name': 'Lê Cường', 'orders': 80, 'highSignals': 0, 'mediumSignals': 2, 'lowSignals': 3, 'amountAtRisk': 260000,
      'voidsAfterBill': 0, 'reducedAfterBill': 0, 'droppedBills': 1, 'paidCancels': 0, 'kitchenVoids': 2, 'noReceipt': 5,
      'cashOrders': 40, 'noReceiptPct': 12.5, 'level': 'yellow', 'notes': ['1 đơn có món bị xóa / hủy']},
    {'key': 'an', 'name': 'Nguyễn An', 'orders': 212, 'highSignals': 0, 'mediumSignals': 0, 'lowSignals': 13, 'amountAtRisk': 0,
      'voidsAfterBill': 0, 'reducedAfterBill': 0, 'droppedBills': 0, 'paidCancels': 0, 'kitchenVoids': 1, 'noReceipt': 13,
      'cashOrders': 130, 'noReceiptPct': 10, 'level': 'green', 'notes': []},
  ],
  'daily': [
    for (var d = 0; d < 7; d++)
      {'dateVn': DateTime.utc(2026, 10, 11 + d).toIso8601String(), 'count': const [0, 0, 0, 1, 1, 2, 0][d],
        'amount': const [0, 0, 0, 260000, 410000, 565000, 0][d]},
  ],
  'recommendations': [
    {'level': 'high', 'title': 'Siết hủy món / sửa đơn sau tạm tính',
      'detail': 'Chỉ quản lý được hủy món, giảm giá hoặc hủy đơn sau khi đã in tạm tính (Phân quyền).'},
    {'level': 'high', 'title': 'Không cho nhân viên tự hủy hóa đơn đã thu tiền',
      'detail': 'Chỉ chủ / quản lý được hủy hóa đơn đã thanh toán; cuối ca đếm két và so với «Tổng kết cuối ngày».'},
    {'level': 'medium', 'title': 'Luôn in hóa đơn cho khách',
      'detail': 'Bật tự in hóa đơn khi thanh toán; dán bảng «Không nhận hóa đơn — báo quản lý».'},
  ],
};

final _client = MockClient((req) async {
  final path = req.url.path;
  final data = path.contains('/network/report')
      ? _network
      : path.contains('/offline/audit')
          ? _audit
          : path.contains('/risk-report')
              ? _risk
              : <String, dynamic>{};
  return http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200,
      headers: {'content-type': 'application/json; charset=utf-8'});
});

Future<void> _pump(WidgetTester tester, Widget home, Size size, String name) async {
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
          localizationsDelegates: const [
            AppLocalizations.delegate,
            DefaultMaterialLocalizations.delegate,
            DefaultWidgetsLocalizations.delegate,
          ],
          home: MediaQuery(data: MediaQueryData(size: size), child: home),
        ),
      ),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }, () => _client);
  expect(tester.takeException(), isNull, reason: name);
  final dir = Platform.environment['SBOX_SHOT_DIR'];
  if (dir != null) {
    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: size.width < 600 ? 1.5 : 1);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    await initializeDateFormatting('vi_VN');
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final size in const [Size(390, 3300), Size(1100, 2300)]) {
    testWidgets('Mạng cửa hàng ${size.width.toInt()}', (t) async {
      await _pump(t, const PosNetworkReportScreen(), size, 'net_${size.width.toInt()}');
      expect(find.textContaining('Mạng chập chờn lúc cao điểm'), findsOneWidget);
      expect(find.text('Việc nên làm'), findsOneWidget);
      expect(find.text('Mạng theo từng giờ'), findsOneWidget);
      expect(find.text('Tốc độ phản hồi theo giờ'), findsOneWidget);
      expect(find.textContaining('Máy thu ngân Sunmi T2'), findsWidgets);
      // Mặc định chọn giờ tệ nhất (12h, đỏ) để xem chi tiết.
      expect(find.text('12:00 – 13:00'), findsOneWidget);
    });

    testWidgets('Bán offline & kiểm soát ${size.width.toInt()}', (t) async {
      await _pump(t, const PosOfflineSalesScreen(), size, 'offline_${size.width.toInt()}');
      expect(find.text('Có 1 dấu hiệu bất thường — cần kiểm tra ngay'), findsOneWidget);
      expect(find.text('Việc cần xử lý'), findsOneWidget);
      expect(find.textContaining('Cách xử lý'), findsWidgets);
      expect(find.text('Tiền bán offline theo ngày'), findsOneWidget);
      expect(find.text('Số nhảy cóc: OFF-000017'), findsOneWidget);
      expect(find.text('Máy này'), findsOneWidget);
    });
    testWidgets('Nguy cơ gian lận ${size.width.toInt()}', (t) async {
      await _pump(t, const PosRiskReportScreen(), size, 'risk_${size.width.toInt()}');
      expect(find.text('3 đơn có dấu hiệu nghiêm trọng — cần kiểm tra'), findsOneWidget);
      expect(find.text('Các loại dấu hiệu'), findsOneWidget);
      expect(find.text('Tiền cần soát theo ngày'), findsOneWidget);
      expect(find.textContaining('HD001245'), findsWidgets);
      expect(find.textContaining('Cách kiểm tra'), findsWidgets);
      expect(find.text('Cần kiểm tra'), findsWidgets); // nhân viên đỏ
    });
  }
}
