import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sbox_pos/models/pos_quick_sell_note.dart';
import 'package:sbox_pos/services/api_service.dart';
import 'package:sbox_pos/widgets/pos/pos_quick_sell_notes_sheet.dart';

/// Sổ tay bán nhanh: thu ngân bấm một mục là cả danh sách món vào đơn.
/// Kiểm tra hộp trượt vẽ đúng danh sách và trả về đúng mục được bấm.
Future<Map<String, dynamic>> Function() _fakeLoader(
        List<Map<String, dynamic>> notes) =>
    () async => {'isSuccess': true, 'data': notes};

Map<String, dynamic> _note(String id, String name, List<List<Object>> items) => {
      'id': id,
      'name': name,
      'description': null,
      'sortOrder': 0,
      'items': [
        for (final it in items)
          {
            'id': 'i${it[0]}',
            'productId': it[0],
            'productName': it[1],
            'qty': it[2],
            'price': it[3],
            'sortOrder': 0,
          },
      ],
    };

Future<void> _openSheet(
  WidgetTester tester,
  List<Map<String, dynamic>> notes, {
  void Function(PosQuickSellNote?)? onPicked,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () async {
            final picked = await PosQuickSellNotesSheet.show(
              ctx,
              api: ApiService(),
              loadNotes: _fakeLoader(notes),
            );
            onPicked?.call(picked);
          },
          child: const Text('mở'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('mở'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Danh sách mục: hiện tên, món kèm số phần và tổng tạm tính', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _openSheet(tester, [
      _note('n1', 'Mâm 4 người', [
        ['p1', 'Bún chả', 2, 40000],
        ['p2', 'Trà đá', 4, 5000],
      ]),
    ]);

    expect(find.text('Mâm 4 người'), findsOneWidget);
    expect(find.textContaining('Bún chả ×2'), findsOneWidget);
    expect(find.textContaining('Trà đá ×4'), findsOneWidget);
    // 2 món, tổng 6 phần, tạm tính 2×40.000 + 4×5.000 = 100.000.
    expect(find.textContaining('2 món · 6 phần'), findsOneWidget);
    expect(find.textContaining('100.000'), findsOneWidget);
  });

  testWidgets('Bấm một mục: trả về đúng mục đó rồi đóng hộp', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    PosQuickSellNote? picked;
    await _openSheet(
      tester,
      [
        _note('n1', 'Mâm 4 người', [
          ['p1', 'Bún chả', 2, 40000]
        ]),
        _note('n2', 'Combo sáng', [
          ['p3', 'Phở', 1, 50000]
        ]),
      ],
      onPicked: (n) => picked = n,
    );

    await tester.tap(find.text('Combo sáng'));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.name, 'Combo sáng');
    expect(picked!.items.single.productId, 'p3');
    expect(find.text('Mâm 4 người'), findsNothing, reason: 'hộp phải đóng sau khi chọn');
  });

  testWidgets('Chưa có mục nào: hướng dẫn cách tạo', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _openSheet(tester, []);
    expect(find.text('Chưa có mục nào'), findsOneWidget);
    expect(find.textContaining('đặt tên chung'), findsOneWidget);
  });

  test('Mục sổ tay gửi lên API: giữ thứ tự món và số phần', () {
    const note = PosQuickSellNote(name: 'Mâm 4 người', items: [
      PosQuickSellNoteItem(productId: 'p1', productName: 'Bún chả', qty: 2),
      PosQuickSellNoteItem(productId: 'p2', productName: 'Trà đá', qty: 4),
    ]);
    final body = note.toUpsertJson();
    final items = body['items'] as List;
    expect(items, hasLength(2));
    expect(items[0], {'productId': 'p1', 'qty': 2.0, 'sortOrder': 0});
    expect(items[1], {'productId': 'p2', 'qty': 4.0, 'sortOrder': 1});
    expect(note.totalQty, 6);
  });
}
