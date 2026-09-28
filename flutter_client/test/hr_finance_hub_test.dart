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
import 'package:zkteco_flutter_client/models/hr_finance.dart';
import 'package:zkteco_flutter_client/providers/theme_provider.dart';
import 'package:zkteco_flutter_client/screens/hr_finance/hr_fin_common.dart';
import 'package:zkteco_flutter_client/screens/hr_finance/hr_finance_hub_screen.dart';

/// Tài chính nhân sự v2 với dữ liệu mẫu. Đặt SBOX_SHOT_DIR để lưu ảnh duyệt giao diện.
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
String _day(int d) => DateTime(_now.year, _now.month, d.clamp(1, 28), 9).toIso8601String();

Map<String, dynamic> _item(String kind, String id, String emp, String title, double amount,
        {String dir = 'in', String status = 'Pending', String? action, int day = 5, String? sub, String? settlement,
        int dispute = 0, String? reason, List<String> evidence = const [], String? code, String? caseId}) =>
    {
      'kind': kind, 'id': id, 'employeeId': 'e-$emp', 'employeeName': emp, 'employeeCode': 'NV${id.hashCode.abs() % 90 + 10}',
      'department': 'Cửa hàng Q1', 'title': title, 'subtitle': sub, 'amount': amount, 'direction': dir, 'status': status,
      'date': _day(day), 'action': action, 'settlement': settlement, 'evidence': evidence, 'disputeStatus': dispute,
      'disputeReason': reason, 'code': code, 'caseId': caseId,
    };

final _inbox = [
  _item('ticket', 't1', 'Phạm Thu Hà', 'Đi trễ 25 phút', 50000, dir: 'out', status: 'Approved', action: 'resolve', day: 12,
      dispute: 1, reason: 'Hôm đó em được quản lý cho đi giao hàng trước khi vào ca', code: 'PP-2410-0012', settlement: 'salary'),
  _item('advance', 'a1', 'Nguyễn Văn An', 'Ứng lương — Đóng học phí cho con', 3000000, action: 'approve', day: 14,
      sub: 'Trừ lương kỳ ${_now.month.toString().padLeft(2, '0')}/${_now.year}, góp 2 kỳ'),
  _item('bonus', 'b1', 'Trần Minh Khoa', 'Doanh số vượt chỉ tiêu tháng', 1500000, action: 'approve', day: 13, settlement: 'salary',
      evidence: ['/f/doanh-so.png']),
  _item('penalty', 'p1', 'Lê Quốc Bảo', 'Làm vỡ ly thủy tinh', 120000, dir: 'out', action: 'approve', day: 11, evidence: ['/f/vo-ly.jpg']),
  _item('trip_settlement', 's1', 'Võ Thị Mai', 'Quyết toán công tác — Khảo sát chi nhánh Đà Nẵng', 4250000, action: 'approve', day: 10,
      sub: 'Tổng chi 4.250.000đ, đã ứng 3.000.000đ', code: 'CT-0007', caseId: 'k1'),
  _item('advance', 'a2', 'Đỗ Hải Nam', 'Ứng lương — Sửa xe', 2000000, status: 'Approved', action: 'pay', day: 9),
  _item('cash', 'c1', 'Lê Quốc Bảo', 'Chi thưởng nóng ca tối - Lê Quốc Bảo', 300000, status: 'WaitingPayment', action: 'pay', day: 8,
      code: 'CH-20261008-0003'),
];

final _rewards = [
  _item('bonus', 'b2', 'Trần Minh Khoa', 'Khách hàng khen trên fanpage', 500000, status: 'Completed', day: 6, settlement: 'salary'),
  _item('bonus', 'b3', 'Nguyễn Văn An', 'Hoàn thành xuất sắc kiểm kê', 800000, status: 'Completed', day: 4, settlement: 'cash'),
  _item('penalty', 'p2', 'Lê Quốc Bảo', 'Không đồng phục', 100000, dir: 'out', status: 'Completed', day: 7, settlement: 'salary'),
  _item('ticket', 't2', 'Phạm Thu Hà', 'Đi trễ 12 phút', 30000, dir: 'out', status: 'AutoApproved', day: 3, settlement: 'salary', code: 'PP-2410-0003'),
  _item('ticket', 't3', 'Đỗ Hải Nam', 'Quên chấm công', 50000, dir: 'out', status: 'Cancelled', day: 2, dispute: 2, reason: 'Máy chấm công lỗi'),
  ..._inbox.where((e) => e['kind'] == 'bonus' || e['kind'] == 'penalty' || e['kind'] == 'ticket'),
];

final _summary = {
  'year': _now.year, 'month': _now.month, 'advancePaid': 12500000, 'advanceToDeduct': 9800000, 'bonus': 6300000, 'penalty': 1480000,
  'manualPenalty': 620000, 'ticketPenalty': 860000, 'tripAdvancePaid': 3000000, 'tripSettled': 7650000, 'cashIn': 41250000,
  'cashOut': 36800000, 'inboxCount': 7, 'disputeCount': 1, 'awaitingPayCount': 2, 'awaitingPayAmount': 2300000,
  'breakdown': [
    {'label': 'Ứng lương', 'amount': 12500000}, {'label': 'Thưởng', 'amount': 6300000},
    {'label': 'Ứng công tác', 'amount': 3000000}, {'label': 'Quyết toán công tác', 'amount': 7650000},
  ],
  'daily': [
    for (var d = 1; d <= 28; d++)
      {'date': DateTime(_now.year, _now.month, d).toIso8601String(), 'cashIn': d % 3 == 0 ? 2400000 + d * 50000 : 900000 + d * 20000, 'cashOut': d % 4 == 0 ? 3100000 : 700000 + d * 30000},
  ],
  'topEmployees': [
    {'employeeId': 'e1', 'name': 'Trần Minh Khoa', 'bonus': 2000000, 'penalty': 0},
    {'employeeId': 'e2', 'name': 'Nguyễn Văn An', 'bonus': 1800000, 'penalty': 80000},
    {'employeeId': 'e3', 'name': 'Lê Quốc Bảo', 'bonus': 300000, 'penalty': 220000},
    {'employeeId': 'e4', 'name': 'Phạm Thu Hà', 'bonus': 500000, 'penalty': 130000},
    {'employeeId': 'e5', 'name': 'Võ Thị Mai', 'bonus': 1200000, 'penalty': 0},
  ],
};

final _me = {
  'year': _now.year, 'month': _now.month, 'disputeWindowDays': 60,
  'advanceLimit': {'monthlySalary': 9000000, 'limit': 4500000, 'used': 1500000, 'remaining': 3000000, 'maxInstallments': 3, 'limitPercent': 50},
  'ledger': {
    'employee': {'id': 'e4', 'name': 'Phạm Thu Hà', 'code': 'NV04', 'department': 'Cửa hàng Q1'},
    'received': 2000000, 'deducted': 80000, 'bonus': 500000, 'penalty': 80000, 'advance': 1500000, 'advanceOutstanding': 750000,
    'items': [
      _item('bonus', 'b9', 'Phạm Thu Hà', 'Khách hàng khen trên fanpage', 500000, status: 'Completed', day: 12, settlement: 'salary'),
      _item('ticket', 't2', 'Phạm Thu Hà', 'Đi trễ 12 phút', 30000, dir: 'out', status: 'AutoApproved', day: 10, settlement: 'salary', code: 'PP-2410-0003'),
      _item('ticket', 't1', 'Phạm Thu Hà', 'Đi trễ 25 phút', 50000, dir: 'out', status: 'Approved', day: 8, settlement: 'salary',
          dispute: 1, reason: 'Hôm đó em được quản lý cho đi giao hàng trước khi vào ca'),
      _item('advance', 'a9', 'Phạm Thu Hà', 'Ứng lương — Tiền nhà', 1500000, status: 'Paid', day: 3, sub: 'Trừ lương kỳ này, góp 2 kỳ'),
    ],
  },
};

http.Response _ok(Object data) =>
    http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

final _client = MockClient((req) async {
  final p = req.url.path;
  if (p.endsWith('/hr-finance/settings')) return _ok({'advanceLimitPercent': 50, 'advanceMaxInstallments': 3, 'bonusDefaultSettlement': 'salary', 'penaltyDefaultSettlement': 'salary', 'disputeWindowDays': 7});
  if (p.endsWith('/hr-finance/summary')) return _ok(_summary);
  if (p.endsWith('/hr-finance/inbox')) return _ok(_inbox);
  if (p.endsWith('/hr-finance/rewards')) return _ok(_rewards);
  if (p.endsWith('/hr-finance/advances')) {
    return _ok([
      ..._inbox.where((e) => e['kind'] == 'advance'),
      _item('advance', 'a3', 'Võ Thị Mai', 'Ứng lương — Viện phí', 2500000, status: 'Paid', day: 3, sub: 'Trừ lương kỳ này'),
      _item('advance', 'a4', 'Lê Quốc Bảo', 'Ứng lương — Việc riêng', 1000000, status: 'Rejected', day: 2),
    ]);
  }
  if (p.endsWith('/hr-finance/me')) return _ok(_me);
  if (p.endsWith('/AdvanceRequests/limit')) return _ok(_me['advanceLimit']!);
  if (p.contains('/api/CashTransactions')) return _ok({'items': [], 'totalCount': 0});
  if (p.contains('/api/employees')) {
    return _ok([
      for (final n in ['Nguyễn Văn An', 'Trần Minh Khoa', 'Lê Quốc Bảo', 'Phạm Thu Hà', 'Võ Thị Mai'])
        {'id': 'e-$n', 'fullName': n, 'employeeCode': 'NV0${n.length % 9}'},
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

const _manager = HrFinViewer(isManager: true, employeeId: 'e0');
const _staff = HrFinViewer(isManager: false, employeeId: 'e4');

void main() {
  setUpAll(_loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Khoản tiền: đọc JSON, trạng thái, chiều tiền', () {
    final it = HrFinItem.fromJson(_inbox.first);
    expect(it.kind, 'ticket');
    expect(it.isPenalty, isTrue);
    expect(it.isIn, isFalse);
    expect(it.isDisputeOpen, isTrue);
    expect(hrFinStatus(it).$1, 'Đang khiếu nại');
    final adv = HrFinItem.fromJson(_inbox[5]);
    expect(hrFinStatus(adv).$1, 'Đã duyệt · chờ chi');
    final s = HrFinSettings.fromJson({'advanceLimitPercent': 40, 'penaltyDefaultSettlement': 'cash'});
    expect(s.advanceLimitPercent, 40);
    expect(s.penaltyDefaultSettlement, 'cash');
    expect(s.toJson()['advanceMaxInstallments'], 3);
    final adj = HrFinPayrollAdj.fromJson({'employeeId': 'e1', 'bonus': 200000, 'advance': 1000000});
    expect(adj.bonus, 200000);
    expect(adj.ticketPenalty, 0);
  });

  testWidgets('Tổng quan — máy tính', (t) async {
    await _pump(t, const HrFinanceHubScreen(debugViewer: _manager), const Size(1440, 900), 'hrfin_overview_desktop');
    expect(find.text('Tài chính nhân sự'), findsOneWidget);
    expect(find.text('Việc cần làm'), findsOneWidget);
    expect(find.text('Ứng lương đã chi'), findsOneWidget);
  });

  testWidgets('Tổng quan — điện thoại', (t) async {
    await _pump(t, const HrFinanceHubScreen(debugViewer: _manager), const Size(390, 844), 'hrfin_overview_mobile');
    expect(find.text('Việc cần làm'), findsOneWidget);
  });

  testWidgets('Hộp duyệt — máy tính', (t) async {
    await _pump(t, const HrFinanceHubScreen(debugViewer: _manager, initialTab: HrFinTab.inbox), const Size(1440, 900), 'hrfin_inbox_desktop');
    expect(find.text('Xử lý khiếu nại'), findsOneWidget);
    expect(find.textContaining('Khiếu nại: Hôm đó'), findsOneWidget);
  });

  testWidgets('Hộp duyệt — điện thoại', (t) async {
    await _pump(t, const HrFinanceHubScreen(debugViewer: _manager, initialTab: HrFinTab.inbox), const Size(390, 844), 'hrfin_inbox_mobile');
    expect(find.text('Chi / thu'), findsWidgets);
  });

  testWidgets('Duyệt thưởng — hộp thoại chọn cộng lương / tiền mặt', (t) async {
    await _pump(t, const HrFinanceHubScreen(debugViewer: _manager, initialTab: HrFinTab.inbox), const Size(1280, 900), 'hrfin_approve_bonus_dialog',
        tall: false, before: () async {
      await t.tap(find.text('Duyệt').at(1));
    });
    expect(find.text('Duyệt phiếu thưởng'), findsOneWidget);
    expect(find.text('Cộng vào lương'), findsOneWidget);
    expect(find.text('Chi tiền mặt'), findsOneWidget);
  });

  testWidgets('Thưởng & phạt — máy tính', (t) async {
    await _pump(t, const HrFinanceHubScreen(debugViewer: _manager, initialTab: HrFinTab.rewards), const Size(1440, 900), 'hrfin_rewards_desktop');
    expect(find.text('Phạt theo lý do'), findsOneWidget);
  });

  testWidgets('Ứng lương — điện thoại', (t) async {
    await _pump(t, const HrFinanceHubScreen(debugViewer: _manager, initialTab: HrFinTab.advances), const Size(390, 844), 'hrfin_advances_mobile');
    expect(find.text('Trừ lương kỳ này'), findsWidgets);
  });

  testWidgets('Tiền của tôi — điện thoại', (t) async {
    await _pump(t, const HrFinanceHubScreen(debugViewer: _staff), const Size(390, 844), 'hrfin_me_mobile');
    expect(find.text('còn được ứng'), findsOneWidget);
    expect(find.text('Khiếu nại'), findsWidgets);
    expect(find.text('Cài đặt'), findsNothing);
  });

  testWidgets('Xin ứng lương — hạn mức + trả góp', (t) async {
    await _pump(t, const HrFinanceHubScreen(debugViewer: _staff), const Size(390, 844), 'hrfin_request_advance_mobile', tall: false,
        before: () async {
      await t.tap(find.text('Xin ứng'));
    });
    expect(find.text('Gửi yêu cầu'), findsOneWidget);
    expect(find.text('Trả góp'), findsOneWidget);
  });

  testWidgets('Cài đặt — máy tính', (t) async {
    await _pump(t, const HrFinanceHubScreen(debugViewer: _manager, initialTab: HrFinTab.settings), const Size(1440, 900), 'hrfin_settings_desktop');
    expect(find.text('Hạn mức ứng lương'), findsOneWidget);
  });
}
