import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/widgets/pos/pos_debt_statement.dart';

/// Sổ đối chiếu công nợ: KPI đầu kỳ / cuối kỳ, số dư từng dòng, cảnh báo lệch, không tràn chữ.
Future<void> _fonts() async {
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

final _calls = <(DateTime, DateTime)>[];

Future<Map<String, dynamic>> _loader(DateTime from, DateTime to, {double current = 300000}) async {
  _calls.add((from, to));
  return {
    'isSuccess': true,
    'data': {
      'opening': 1100000, 'increase': 300000, 'decrease': 1100000, 'closing': 300000, 'currentBalance': current,
      'items': [
        {'at': '2026-10-03T09:15:00.000', 'docType': 'Sale', 'docLabel': 'Bán hàng', 'docNo': 'HD000123',
          'increase': 300000, 'decrease': 0, 'balance': 1400000, 'note': 'Bán hàng — còn nợ 300.000đ'},
        {'at': '2026-10-05T16:40:00.000', 'docType': 'Payment', 'docLabel': 'Thanh toán', 'docNo': 'TT-20261005-0001',
          'increase': 0, 'decrease': 1100000, 'balance': 300000, 'note': 'Thu nợ (Chuyển khoản)'},
      ],
    },
  };
}

Future<void> _pump(WidgetTester t, Size size, String shot, {double current = 300000}) async {
  _calls.clear();
  await t.binding.setSurfaceSize(size);
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  final key = GlobalKey();
  await t.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SingleChildScrollView(
          child: PosDebtStatementView(
            loader: (f, to) => _loader(f, to, current: current),
            decreaseLabel: 'Đã thu / trả hàng',
          ),
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
  final errors = <Object>[];
  Object? e;
  while ((e = t.takeException()) != null) {
    errors.add(e!);
  }
  final dir = Platform.environment['SBOX_SHOT_DIR'];
  if (dir != null) {
    await t.runAsync(() async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: size.width < 600 ? 1.5 : 1);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/$shot.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }
  t.view.resetPhysicalSize();
  expect(errors, isEmpty, reason: errors.join('\n'));
}

void main() {
  setUpAll(_fonts);

  testWidgets('Máy tính: KPI, số dư từng dòng, giờ VN không đổi múi', (t) async {
    await _pump(t, const Size(1280, 800), 'pos_debt_statement_desk');
    final now = DateTime.now();
    expect(_calls.single.$1, DateTime(now.year, now.month, 1));
    expect(find.text('Đầu kỳ'), findsOneWidget);
    expect(find.text('Cuối kỳ'), findsOneWidget);
    expect(find.text('HD000123'), findsOneWidget);
    expect(find.text('03/10/2026 09:15'), findsOneWidget);
    expect(find.textContaining('khác công nợ hiện tại'), findsNothing);
  });

  testWidgets('Điện thoại: không tràn, báo lệch khi sổ khác công nợ hiện tại', (t) async {
    await _pump(t, const Size(390, 1200), 'pos_debt_statement_phone', current: 500000);
    expect(find.textContaining('khác công nợ hiện tại'), findsOneWidget);
  });
}
