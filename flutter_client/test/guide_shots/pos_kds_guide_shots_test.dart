import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_kds_screen.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';

/// Ảnh cho bước «Màn hình bếp (KDS)» (pos_kds) — quán ăn 3 bàn đang gọi món.

String _ago(int minutes) =>
    DateTime.now().toUtc().subtract(Duration(minutes: minutes)).toIso8601String();

Map<String, Object?> _item(String id, String name, num qty, String status, int min, {String? note}) => {
      'id': id, 'productId': 'p-$name', 'productName': name, 'qty': qty, 'sentQty': qty,
      'status': status, 'note': note, 'sentAt': _ago(min),
    };

List<Map<String, Object?>> _tickets() => [
      {
        'orderId': 'o1', 'orderNo': 'HD000231', 'tableName': 'Bàn 3', 'areaName': 'Tầng 1', 'sentAt': _ago(14),
        'status': 'cooking',
        'items': [
          _item('i1', 'Phở bò tái', 2, 'cooking', 14, note: 'Ít hành'),
          _item('i2', 'Cơm gà xối mỡ', 1, 'queued', 14),
          _item('i3', 'Trà đá', 2, 'ready', 14),
        ],
      },
      {
        'orderId': 'o2', 'orderNo': 'HD000232', 'tableName': 'Bàn 7', 'areaName': 'Tầng 1', 'sentAt': _ago(6),
        'status': 'queued',
        'items': [
          _item('i4', 'Phở bò tái', 1, 'queued', 6),
          _item('i5', 'Bún chả Hà Nội', 2, 'queued', 6, note: 'Thêm rau'),
        ],
      },
      {
        'orderId': 'o3', 'orderNo': 'HD000233', 'tableName': 'Bàn 2', 'areaName': 'Sân vườn', 'sentAt': _ago(2),
        'status': 'queued',
        'items': [
          _item('i6', 'Cơm gà xối mỡ', 2, 'queued', 2),
          _item('i7', 'Nem rán', 1, 'queued', 2),
        ],
      },
    ];

final _api = posGuideApi((req) {
  final p = req.url.path;
  if (p.endsWith('/api/pos/kds/tickets')) return {'tickets': _tickets()};
  return null;
});

void main() {
  setUpAll(() {
    // Giọng đọc món (flutter_tts) và giữ màn sáng không có trong môi trường test.
    for (final ch in ['flutter_tts', 'wakelock_plus', 'dev.fluttercommunity.plus/wakelock_plus']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(ch), (_) async => null);
    }
  });

  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    const crumbs = ['POS', 'Màn hình bếp (KDS)'];

    testWidgets('pos-kds-1$suffix: gộp món', (t) async {
      await guideShot(
        t,
        name: 'pos-kds-1$suffix',
        screen: withPosPackage(const PosKdsScreen()),
        api: _api,
        crumbs: crumbs,
        size: size,
        marks: [
          GuideMark(1, [find.text('Gộp món').first, find.text('Theo bàn').first], pad: 10),
          GuideMark(2, [find.text('Tất cả').first, find.text('Chờ làm').first]),
          GuideMark(3, [GuideMark.button(find.text('Ra món').first)]),
          GuideMark(4, [GuideMark.button(find.text('ĐÃ HOÀN THÀNH'))]),
        ],
      );
    });

    testWidgets('pos-kds-2$suffix: theo bàn', (t) async {
      await guideShot(
        t,
        name: 'pos-kds-2$suffix',
        screen: withPosPackage(const PosKdsScreen()),
        api: _api,
        crumbs: crumbs,
        size: size,
        act: (t) async {
          await t.tap(find.text('Theo bàn').first);
          await t.pump(const Duration(milliseconds: 400));
        },
        marks: [
          GuideMark(1, [find.text('Tầng 1 · Bàn 3'), find.text('5 món')]),
          GuideMark(2, [find.text('Phở bò tái').first, find.text('14p').at(2)], pad: 10),
          GuideMark(3, [GuideMark.button(find.text('Đang làm').at(1)), GuideMark.button(find.text('Ra món').first)]),
        ],
      );
    });
  }
}
