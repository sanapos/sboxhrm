import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/widgets/pos/pos_cart_fly_effect.dart';
import 'package:zkteco_flutter_client/widgets/pos/pos_product_image.dart';

void main() {
  const chip = PosCartFlyChip(productId: 'p1');

  Future<BuildContext> pumpHost(
    WidgetTester tester, {
    required GlobalKey<PosCartFlyTargetState> target,
    bool withTarget = true,
    VoidCallback? onUnderTap,
  }) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (c) {
        ctx = c;
        return Scaffold(
          body: Stack(children: [
            Positioned.fill(
              child: GestureDetector(
                key: const Key('under'),
                behavior: HitTestBehavior.opaque,
                onTap: onUnderTap,
              ),
            ),
            if (withTarget)
              Positioned(
                right: 10,
                bottom: 10,
                child: PosCartFlyTarget(key: target, child: const Icon(Icons.shopping_cart)),
              ),
          ]),
        );
      }),
    ));
    return ctx;
  }

  testWidgets('chip bay về đích, đi đúng hướng rồi tự gỡ khỏi màn hình', (tester) async {
    final target = GlobalKey<PosCartFlyTargetState>();
    final ctx = await pumpHost(tester, target: target);
    final end = tester.getCenter(find.byIcon(Icons.shopping_cart));
    const from = Offset(100, 100);

    posFlyToCart(context: ctx, from: from, target: target, chip: chip);
    await tester.pump();
    expect(find.byType(PosCartFlyChip), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 470));
    final near = tester.getCenter(find.byType(PosCartFlyChip));
    expect((near - end).distance, lessThan((from - end).distance / 4));

    await tester.pumpAndSettle();
    expect(find.byType(PosCartFlyChip), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('không có đích (giỏ chưa vẽ) thì bỏ qua, không lỗi', (tester) async {
    final target = GlobalKey<PosCartFlyTargetState>();
    final ctx = await pumpHost(tester, target: target, withTarget: false);

    posFlyToCart(context: ctx, from: const Offset(100, 100), target: target, chip: chip);
    await tester.pump();

    expect(find.byType(PosCartFlyChip), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('đang bay không chặn chạm — thu ngân vẫn bấm được món khác', (tester) async {
    final target = GlobalKey<PosCartFlyTargetState>();
    var taps = 0;
    final ctx = await pumpHost(tester, target: target, onUnderTap: () => taps++);
    const from = Offset(100, 100);

    posFlyToCart(context: ctx, from: from, target: target, chip: chip);
    await tester.pump();
    await tester.tapAt(from);
    await tester.pump();

    expect(taps, 1);
    await tester.pumpAndSettle();
  });

  testWidgets('bấm dồn dập chỉ bay tối đa 4 chip, xong không kẹt lượt sau', (tester) async {
    final target = GlobalKey<PosCartFlyTargetState>();
    final ctx = await pumpHost(tester, target: target);

    for (var i = 0; i < 7; i++) {
      posFlyToCart(context: ctx, from: const Offset(100, 100), target: target, chip: chip);
    }
    await tester.pump();
    expect(find.byType(PosCartFlyChip), findsNWidgets(4));

    await tester.pumpAndSettle();
    expect(find.byType(PosCartFlyChip), findsNothing);

    posFlyToCart(context: ctx, from: const Offset(100, 100), target: target, chip: chip);
    await tester.pump();
    expect(find.byType(PosCartFlyChip), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('chip bị gỡ giữa đường không làm hiệu ứng tắt luôn', (tester) async {
    final target = GlobalKey<PosCartFlyTargetState>();
    final ctx = await pumpHost(tester, target: target);
    for (var i = 0; i < 4; i++) {
      posFlyToCart(context: ctx, from: const Offset(100, 100), target: target, chip: chip);
    }
    await tester.pump();
    await tester.pumpWidget(const SizedBox());

    final ctx2 = await pumpHost(tester, target: target);
    posFlyToCart(context: ctx2, from: const Offset(100, 100), target: target, chip: chip);
    await tester.pump();
    expect(find.byType(PosCartFlyChip), findsOneWidget);
    await tester.pumpAndSettle();
  });

  group('ảnh của chip', () {
    // PNG 1×1.
    final png = Uint8List.fromList(const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
      0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
      0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
      0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ]);

    testWidgets('chưa hiện ảnh trên ô món thì dùng icon', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: PosCartFlyChip(productId: 'chua-co-anh')));
      expect(find.byIcon(Icons.shopping_bag_outlined), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('dùng lại đúng ảnh ô món đã giải mã, hiện ngay khung đầu', (tester) async {
      final shown = MemoryImage(png);
      PosProductImage.rememberShown('co-anh', shown);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.runAsync(() => precacheImage(shown, tester.element(find.byType(SizedBox))));

      await tester.pumpWidget(const MaterialApp(home: PosCartFlyChip(productId: 'co-anh')));

      final image = tester.widget<Image>(find.byType(Image));
      expect(identical(image.image, shown), isTrue);
      expect(find.byIcon(Icons.shopping_bag_outlined), findsNothing);
    });

    test('nhớ có giới hạn: mục cũ nhất bị bỏ, mục vừa dùng được giữ', () {
      final img = MemoryImage(png);
      PosProductImage.rememberShown('vua-dung', img);
      PosProductImage.rememberShown('bi-bo', img);
      for (var i = 0; i < PosProductImage.shownMax - 2; i++) {
        PosProductImage.rememberShown('m$i', img);
      }
      PosProductImage.rememberShown('vua-dung', img);
      PosProductImage.rememberShown('moi', img);

      expect(PosProductImage.shownImageOf('bi-bo'), isNull);
      expect(PosProductImage.shownImageOf('vua-dung'), isNotNull);
      expect(PosProductImage.shownImageOf('moi'), isNotNull);
    });
  });
}
