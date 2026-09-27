import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/widgets/sbox/sbox_command_palette.dart';

void main() {
  test('Bỏ dấu tiếng Việt để so khớp', () {
    expect(SboxCommandPalette.fold('Nhập hàng NCC'), 'nhap hang ncc');
    expect(SboxCommandPalette.fold('Đi trễ / Về sớm'), 'di tre / ve som');
    expect(SboxCommandPalette.fold('Tổng hợp lương'), 'tong hop luong');
  });

  testWidgets('Gõ không dấu → lọc đúng, Enter mở mục đang chọn', (tester) async {
    String? opened;
    final items = [
      SboxCommandItem(label: 'Bán hàng', group: 'POS', onSelect: () => opened = 'ban'),
      SboxCommandItem(label: 'Nhập hàng NCC', group: 'Kho', onSelect: () => opened = 'nhap'),
      SboxCommandItem(label: 'Tổng hợp lương', group: 'Báo cáo nhân sự', onSelect: () => opened = 'luong'),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => TextButton(onPressed: () => SboxCommandPalette.show(ctx, items), child: const Text('open')),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('3 chức năng'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'nhap hang');
    await tester.pump();
    expect(find.text('Nhập hàng NCC'), findsOneWidget);
    expect(find.text('Bán hàng'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, 'nhap');
  });
}
