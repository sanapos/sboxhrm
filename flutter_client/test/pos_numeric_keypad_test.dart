import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/widgets/pos/pos_numeric_keypad.dart';

void main() {
  Future<String?> enter(WidgetTester tester, String initial, List<String> keys,
      {bool allowDecimal = false, bool cashNotes = false, List<int>? percents}) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    String? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async => result = await showPosNumericKeypad(
              context: ctx,
              title: 'Số tiền thanh toán',
              initial: initial,
              allowDecimal: allowDecimal,
              offerCashNotes: cashNotes,
              quickPercents: percents,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    for (final k in keys) {
      await tester.tap(find.text(k).last);
      await tester.pump();
    }
    await tester.tap(find.text('Xong'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('phím đầu tiên thay số điền sẵn (khách đưa 100.000 khi cần trả 65.000)', (tester) async {
    expect(await enter(tester, '65000', ['1', '0', '0', '0', '0', '0']), '100000');
  });

  testWidgets('không gõ gì → giữ nguyên số điền sẵn', (tester) async {
    expect(await enter(tester, '65000', []), '65000');
  });

  testWidgets('xóa lùi đầu tiên xóa hết số điền sẵn, sau đó gõ bình thường', (tester) async {
    expect(await enter(tester, '65000', ['⌫', '5', '0']), '50');
  });

  testWidgets('ô trống / 0 gõ nối như cũ', (tester) async {
    expect(await enter(tester, '', ['1', '2']), '12');
  });

  testWidgets('mệnh giá tiền mặt: bấm đầu thay số điền sẵn, bấm tiếp cộng dồn', (tester) async {
    expect(await enter(tester, '65000', ['+200k', '+50k', '+10k'], cashNotes: true), '260000');
  });

  testWidgets('mệnh giá cộng vào số vừa gõ tay', (tester) async {
    expect(await enter(tester, '65000', ['5', '+1k'], cashNotes: true), '1005');
  });

  testWidgets('không bật mệnh giá → không có nút', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => showPosNumericKeypad(context: ctx, title: 'Số lượng', allowDecimal: false),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('+500k'), findsNothing);
  });

  testWidgets('nút % chọn nhanh thay giá trị, bấm lại % khác thì đổi', (tester) async {
    expect(await enter(tester, '0', ['10%', '25%'], percents: const [5, 10, 15, 20, 25]), '25');
  });
}
