import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:zkteco_flutter_client/models/pos_sell_industry.dart';
import 'package:zkteco_flutter_client/widgets/pos/pos_ticking_text.dart';
import 'package:zkteco_flutter_client/widgets/pos/pos_timed_service_setup.dart';

/// Dịch vụ tính giờ (karaoke / bi-a): ĐVT khi bán, khung giờ đặc biệt (khớp máy chủ),
/// đồng hồ tự chạy, màn thiết lập kiểu POS365. Đặt SBOX_SHOT_DIR để lưu ảnh duyệt giao diện.
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

/// Giờ VN → UTC.
DateTime _vn(int h, int m) => DateTime.utc(2026, 10, 21, h, m).subtract(const Duration(hours: 7));

/// Khung giống màn «Thêm hàng hóa» — giữ mode / JSON như form thật.
class _Host extends StatefulWidget {
  const _Host({required this.initialMode, this.initialJson, this.onState});

  final PosServiceBillingMode initialMode;
  final String? initialJson;
  final void Function(_HostState s)? onState;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late PosServiceBillingMode mode = widget.initialMode;
  late String? json = widget.initialJson;
  final name = TextEditingController(text: 'Phòng hát VIP');
  final price = TextEditingController(text: '120.000');
  final block = TextEditingController(text: '15');
  final fee = TextEditingController(text: '100.000');
  final opening = TextEditingController(text: '60');
  final grace = TextEditingController();
  final minBill = TextEditingController();
  final roundAfter = TextEditingController();

  @override
  Widget build(BuildContext context) {
    widget.onState?.call(this);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(title: const Text('Thêm hàng hóa · Dịch vụ')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Tên hàng *', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                const Text('Tính tiền theo thời gian (phòng / bàn)',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                const SizedBox(height: 8),
                PosTimedServiceSetup(
                  mode: mode,
                  onModeChanged: (m) => setState(() => mode = m),
                  priceCtrl: price,
                  blockCtrl: block,
                  openingFeeCtrl: fee,
                  openingMinutesCtrl: opening,
                  graceCtrl: grace,
                  minBillCtrl: minBill,
                  roundAfterCtrl: roundAfter,
                  timeSurchargesJson: json,
                  onTimeSurchargesChanged: (v) => json = v,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _pump(WidgetTester tester, Widget home, Size size, String? shot) async {
  final key = GlobalKey();
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'BeVietnamPro', colorSchemeSeed: const Color(0xFF0F7BA8)),
      home: MediaQuery(data: MediaQueryData(size: size), child: home),
    ),
  ));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  final dir = Platform.environment['SBOX_SHOT_DIR'];
  if (dir != null && shot != null) {
    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: size.width < 600 ? 1.5 : 1);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/$shot.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }
}

const _rules =
    '[{"from":"18:00","to":"23:00","kind":"percent","value":20},{"from":"08:00","to":"12:00","kind":"amount","value":-10000}]';

void main() {
  setUpAll(() async {
    await _loadFonts();
    await initializeDateFormatting('vi_VN');
  });

  group('ĐVT khi bán (lỗi «cái»)', () {
    test('dịch vụ tính giờ không còn hiện «Cái»', () {
      expect(PosServiceBillingCalc.timedUnitName(PosServiceBillingMode.perHour, 'Cái'), 'Giờ');
      expect(PosServiceBillingCalc.timedUnitName(PosServiceBillingMode.perBlock, 'Cái'), 'Block');
      expect(PosServiceBillingCalc.timedUnitName(PosServiceBillingMode.perBlock, 'Giờ'), 'Block');
      expect(PosServiceBillingCalc.timedUnitName(PosServiceBillingMode.perMinute, ''), 'Phút');
      expect(PosServiceBillingCalc.timedUnitName(PosServiceBillingMode.perDay, 'Đêm'), 'Đêm');
      expect(PosServiceBillingCalc.timedUnitName(PosServiceBillingMode.flat, 'Lần'), 'Lần');
    });
  });

  group('Khung giờ đặc biệt — khớp PosServiceBillingMathTests (.NET)', () {
    double s(PosServiceBillingMode mode, DateTime start, int billable, double price, String json,
            {int? opening, int? block = 15}) =>
        PosServiceBillingCalc.timeSurchargeAmount(
          mode: mode,
          startedAt: start,
          billableMinutes: billable,
          unitPrice: price,
          openingMinutes: opening,
          billRoundMinutes: block,
          rulesJson: json,
        );

    test('tăng 50% chỉ phần trong khung', () {
      expect(
          s(PosServiceBillingMode.perHour, _vn(17, 30), 120, 60000,
              '[{"from":"18:00","to":"23:00","kind":"percent","value":50}]'),
          45000);
    });
    test('giảm theo số tiền / block', () {
      expect(
          s(PosServiceBillingMode.perBlock, _vn(9, 0), 30, 20000,
              '[{"from":"08:00","to":"12:00","kind":"amount","value":-4000}]'),
          -8000);
    });
    test('khung qua đêm, bỏ phần đã gồm giờ đầu', () {
      expect(
          s(PosServiceBillingMode.perHour, _vn(21, 0), 180, 60000,
              '[{"from":"22:00","to":"02:00","kind":"percent","value":20}]',
              opening: 60),
          24000);
    });
    test('JSON hỏng / trống = 0, encode bỏ dòng sai', () {
      expect(s(PosServiceBillingMode.perHour, _vn(19, 0), 60, 60000, 'not json'), 0);
      expect(PosServiceBillingCalc.parseTimeSurcharges(_rules).length, 2);
      expect(
          PosServiceBillingCalc.encodeTimeSurcharges(const [
            PosTimeSurchargeRule(fromMinute: 600, toMinute: 600, isPercent: true, value: 10),
          ]),
          isNull);
    });
  });

  testWidgets('Đồng hồ tự chạy từng giây, không cần màn cha vẽ lại (lỗi «lúc chạy lúc không»)', (t) async {
    var calls = 0;
    await t.pumpWidget(MaterialApp(
      home: PosTickingText(running: true, text: () => 'tick ${calls++}'),
    ));
    expect(find.text('tick 0'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    expect(find.text('tick 1'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    expect(calls, greaterThanOrEqualTo(3));
    // Tạm dừng → đứng yên.
    await t.pumpWidget(MaterialApp(
      home: PosTickingText(running: false, text: () => 'paused ${calls++}'),
    ));
    final frozen = calls;
    await t.pump(const Duration(seconds: 5));
    expect(calls, frozen);
  });

  testWidgets('Tích «giá từng block» quy đổi giá, số block giờ đầu → phút, thêm khung giờ', (t) async {
    late _HostState host;
    await _pump(t, _Host(initialMode: PosServiceBillingMode.perHour, onState: (s) => host = s),
        const Size(1100, 1700), null);
    expect(find.text('Số lượng tính theo thời gian sử dụng?'), findsOneWidget);
    expect(find.text('Giá bán được thiết lập cho từng block?'), findsOneWidget);
    expect(find.text('Block tính thời gian sử dụng dịch vụ (phút)'), findsOneWidget);
    expect(find.text('Giá cho 4 block giờ đầu tiên'), findsOneWidget); // 60 phút / block 15
    expect(find.text('Thiết lập khung giờ đặc biệt'), findsOneWidget);

    // 120.000đ/giờ → tích «từng block» 15 phút = 30.000đ/block.
    await t.tap(find.text('Giá bán được thiết lập cho từng block?'));
    await t.pumpAndSettle();
    expect(host.mode, PosServiceBillingMode.perBlock);
    expect(host.price.text, '30.000');

    // 2 block giờ đầu → 30 phút.
    await t.enterText(find.widgetWithText(TextField, 'Số block giờ đầu tiên'), '2');
    await t.pumpAndSettle();
    expect(host.opening.text, '30');
    expect(find.text('Giá cho 2 block giờ đầu tiên'), findsOneWidget);

    // Thêm khung 18:00–23:00 tăng 20%.
    await t.tap(find.text('Thêm khung giờ'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Từ'), '18:00');
    await t.enterText(find.widgetWithText(TextField, 'Đến'), '23:00');
    await t.enterText(find.widgetWithText(TextField, 'Mức (%)'), '20');
    await t.pumpAndSettle();
    final saved = jsonDecode(host.json!) as List;
    expect(saved.single, {'from': '18:00', 'to': '23:00', 'kind': 'percent', 'value': 20});

    // Bỏ tích «tính theo thời gian» → về giá cố định.
    await t.tap(find.text('Số lượng tính theo thời gian sử dụng?'));
    await t.pumpAndSettle();
    expect(host.mode, PosServiceBillingMode.flat);
  });

  for (final size in const [Size(390, 2300), Size(1100, 1500)]) {
    testWidgets('Ảnh màn thiết lập ${size.width.toInt()}', (t) async {
      await _pump(t, const _Host(initialMode: PosServiceBillingMode.perHour, initialJson: _rules), size,
          'timed_setup_${size.width.toInt()}');
      expect(find.text('Xem trước: khách dùng bao lâu thì trả bao nhiêu'), findsOneWidget);
      expect(find.textContaining('1 giờ = 120.000đ'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Từ'), findsNWidgets(2));
    });
  }
}
