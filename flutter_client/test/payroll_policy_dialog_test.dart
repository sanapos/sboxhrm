import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_engine/payroll/payroll_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/providers/theme_provider.dart';
import 'package:zkteco_flutter_client/screens/salary_v2/sl_policy.dart';

/// Chính sách tính lương: «Theo luật» / «Tùy chỉnh» — lưu đúng khóa thiết lập lương.
Future<void> _fonts() async {
  final fl = FontLoader('BeVietnamPro');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    fl.addFont(Future.value(ByteData.view(File('assets/fonts/BeVietnamPro-$f.ttf').readAsBytesSync().buffer)));
  }
  await fl.load();
}

Future<Map<String, dynamic>?> _open(WidgetTester t, Map<String, dynamic> store, Future<void> Function() act, {String? shot}) async {
  await t.binding.setSurfaceSize(const Size(420, 1400));
  t.view.physicalSize = const Size(420, 1400);
  t.view.devicePixelRatio = 1;
  Map<String, dynamic>? result;
  final key = GlobalKey();
  await t.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      theme: ThemeProvider().lightTheme,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => result = await showPayrollPolicyDialog(ctx, store),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pumpAndSettle();
  final dir = Platform.environment['SBOX_SHOT_DIR'];
  if (dir != null && shot != null) {
    await t.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 1.5);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/$shot.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }
  await act();
  await t.tap(find.text('Lưu chính sách'));
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
  t.view.resetPhysicalSize();
  return result;
}

void main() {
  setUpAll(_fonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Chọn «Theo luật» → lưu preset law', (t) async {
    final r = await _open(t, {'overtimeRate': 1.5, 'weekendRate': 2, 'holidayRate': 3}, () async {
      await t.tap(find.text('Theo luật'));
      await t.pumpAndSettle();
    }, shot: 'payroll_policy_dialog');
    expect(r, isNotNull);
    expect(r!['payrollPolicyPreset'], 'law');
    expect(PayrollPolicy.fromSalarySettings(r).isLaw, isTrue);
  });

  testWidgets('Tùy chỉnh: mặc định giữ cách tính cũ', (t) async {
    final r = await _open(t, {'overtimeRate': 1.5, 'weekendRate': 2, 'holidayRate': 3}, () async {});
    expect(r!['payrollPolicyPreset'], 'custom');
    expect(r['holidayPayScope'], 'monthly_daily');
    expect(r['nightPremiumScope'], 'shift');
    expect(r['nightPremiumBasis'], 'whole_shift');
  });

  testWidgets('Theo luật: hệ số tăng ca thấp hơn luật bị chặn', (t) async {
    final r = await _open(t, {'overtimeRate': 1.2, 'weekendRate': 2, 'holidayRate': 3, 'payrollPolicyPreset': 'law'}, () async {});
    expect(r, isNull, reason: 'không đóng hộp thoại khi hệ số < 1,5');
    expect(find.textContaining('tối thiểu ×1,5'), findsOneWidget);
  });
}
