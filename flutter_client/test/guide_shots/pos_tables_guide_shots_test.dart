import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_sell_industry.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_resource_floor_screen.dart';
import 'package:zkteco_flutter_client/utils/pos_sell_settings_helper.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';

/// Ảnh cho bước hướng dẫn «Bàn / phòng & đặt lịch» (id: pos_tables) — quán cà phê có sân vườn.

final _areas = [
  {'id': 'a1', 'name': 'Tầng 1', 'code': 'T1', 'sortOrder': 1, 'isActive': true},
  {'id': 'a2', 'name': 'Sân vườn', 'code': 'SV', 'sortOrder': 2, 'isActive': true},
];

Map<String, Object?> _table(String id, String name, String area, String areaName, int sort,
        {String status = 'Free', int cap = 4, int guests = 0, num subtotal = 0, int minutes = 0,
        int lines = 0, int kitchen = 0, String? order, String? resv, String? resvName}) =>
    {
      'id': id, 'name': name, 'code': name, 'areaId': area, 'areaName': areaName, 'sortOrder': sort,
      'capacity': cap, 'isActive': true, 'resourceKind': 'Table', 'occupancyStatus': status,
      'guestCount': guests, 'subtotal': subtotal, 'elapsedMinutes': minutes, 'lineCount': lines,
      'pendingKitchenCount': kitchen,
      if (order != null) ...{'openOrderId': 'o$id', 'openSessionId': 's$id', 'orderNo': order,
        'sessionStartedAt': DateTime.now().toUtc().subtract(Duration(minutes: minutes)).toIso8601String()},
      if (resv != null) ...{'reservationId': resv, 'reservationCustomerName': resvName, 'reservationGuestCount': 6,
        'reservationPhone': '0903 456 789'},
    };

final _tables = [
  _table('t1', 'Bàn 1', 'a1', 'Tầng 1', 1, status: 'Occupied', guests: 2, subtotal: 93000, minutes: 25, lines: 3, order: 'HD000431'),
  _table('t2', 'Bàn 2', 'a1', 'Tầng 1', 2),
  _table('t3', 'Bàn 3', 'a1', 'Tầng 1', 3, status: 'Occupied', guests: 4, subtotal: 212000, minutes: 48, lines: 6, kitchen: 2, order: 'HD000428'),
  _table('t4', 'Bàn 4', 'a1', 'Tầng 1', 4, cap: 2),
  _table('t5', 'Bàn 5', 'a1', 'Tầng 1', 5, status: 'Reserved', cap: 6, resv: 'rv1', resvName: 'Chị Mai'),
  _table('t6', 'Bàn 6', 'a1', 'Tầng 1', 6, cap: 2),
  _table('t7', 'SV 1', 'a2', 'Sân vườn', 7, status: 'Occupied', guests: 3, subtotal: 147000, minutes: 12, lines: 4, order: 'HD000433'),
  _table('t8', 'SV 2', 'a2', 'Sân vườn', 8),
  _table('t9', 'SV 3', 'a2', 'Sân vườn', 9, cap: 6),
  _table('t10', 'SV 4', 'a2', 'Sân vườn', 10, cap: 8),
];

final _api = posGuideApi((req) {
  final p = req.url.path;
  if (p.endsWith('/api/pos/sell-settings')) {
    return {'id': 'ss1', 'sellProfile': 'restaurant', 'enableResources': true, 'showFloorPlan': true, 'allowProvisionalBill': true};
  }
  if (p.endsWith('/api/pos/service-areas')) return _areas;
  if (p.endsWith('/api/pos/service-resources')) return _tables;
  return null;
});

void main() {
  setUp(() => PosSellSettingsHelper.lastProfile = PosSellProfile.restaurant);

  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('pos-tables-1$suffix: sơ đồ bàn', (t) async {
      await guideShot(
        t,
        name: 'pos-tables-1$suffix',
        screen: withPosPackage(const PosResourceFloorScreen(
          sellProfile: PosSellProfile.restaurant,
          autoRefreshSeconds: 0,
        )),
        api: _api,
        crumbs: const ['POS', 'Bán hàng', 'Sơ đồ bàn'],
        size: size,
        marks: [
          GuideMark(1, [
            GuideMark.button(find.byTooltip('Quản lý nhóm')),
            GuideMark.button(find.byTooltip('Thêm bàn')),
          ]),
          // Tên bàn ở góc trên + mã bàn ở góc dưới → khung bao cả ô bàn.
          GuideMark(2, [GuideMark.within(find.text('Bàn 3').first, 'Row'), find.text('Bàn 3').last, find.textContaining('212.000')], pad: 10),
        ],
      );
    });

    testWidgets('pos-tables-2$suffix: chạm giữ bàn', (t) async {
      await guideShot(
        t,
        name: 'pos-tables-2$suffix',
        screen: withPosPackage(const PosResourceFloorScreen(
          sellProfile: PosSellProfile.restaurant,
          autoRefreshSeconds: 0,
          manageMode: false,
        )),
        api: _api,
        crumbs: const ['POS', 'Bán hàng', 'Sơ đồ bàn'],
        size: size,
        act: (t) async {
          await t.longPress(find.text('Bàn 3').first);
          await t.pump(const Duration(milliseconds: 600));
        },
        marks: [
          GuideMark(1, [
            GuideMark.button(find.text('Chuyển bàn')),
            GuideMark.button(find.text('Tách bàn')),
            GuideMark.button(find.text('Gộp bàn vào đây')),
          ]),
        ],
      );
    });

    // «Gửi bếp» (pos_kitchen) — cùng sơ đồ bàn ở chế độ bán.
    testWidgets('pos-kitchen-1$suffix: báo chế biến', (t) async {
      await guideShot(
        t,
        name: 'pos-kitchen-1$suffix',
        screen: withPosPackage(const PosResourceFloorScreen(
          sellProfile: PosSellProfile.restaurant,
          autoRefreshSeconds: 0,
          manageMode: false,
        )),
        api: _api,
        crumbs: const ['POS', 'Bán hàng', 'Sơ đồ bàn'],
        size: size,
        act: (t) async {
          await t.longPress(find.text('Bàn 3').first);
          await t.pump(const Duration(milliseconds: 600));
        },
        marks: [
          GuideMark(1, [find.text('Tầng 1 · Bàn 3'), find.textContaining('6 món').first], pad: 8),
          GuideMark(2, [GuideMark.button(find.text('Báo chế biến (2 món)'))]),
        ],
      );
    });

    testWidgets('pos-kitchen-2$suffix: món chờ bếp trên sơ đồ', (t) async {
      await guideShot(
        t,
        name: 'pos-kitchen-2$suffix',
        screen: withPosPackage(const PosResourceFloorScreen(
          sellProfile: PosSellProfile.restaurant,
          autoRefreshSeconds: 0,
          manageMode: false,
        )),
        api: _api,
        crumbs: const ['POS', 'Bán hàng', 'Sơ đồ bàn'],
        size: size,
        marks: [
          GuideMark(1, [GuideMark.within(find.text('Bàn 3').first, 'Row'), find.text('Bàn 3').last, find.textContaining('2 bếp')], pad: 10),
        ],
      );
    });
  }
}
