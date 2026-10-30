import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_sell_industry.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_resource_floor_screen.dart';
import 'package:zkteco_flutter_client/utils/pos_sell_settings_helper.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';

/// Ảnh tab «Ngành hàng» — sơ đồ bàn / phòng / ghế theo ngành: nhà hàng (ind_restaurant),
/// karaoke tính giờ (ind_room_hourly), salon (ind_salon), khách sạn (ind_hotel).

String _ago(int minutes) => DateTime.now().toUtc().subtract(Duration(minutes: minutes)).toIso8601String();

Map<String, Object?> _res(String id, String name, String area, String areaName, int sort, String kind,
        {String status = 'Free', int cap = 4, int guests = 0, num subtotal = 0, int minutes = 0, int lines = 0,
        Map<String, Object?> extra = const {}}) =>
    {
      'id': id, 'name': name, 'code': name, 'areaId': area, 'areaName': areaName, 'sortOrder': sort,
      'capacity': cap, 'isActive': true, 'resourceKind': kind, 'occupancyStatus': status,
      'guestCount': guests, 'subtotal': subtotal, 'elapsedMinutes': minutes, 'lineCount': lines,
      if (status != 'Free') ...{'openOrderId': 'o$id', 'openSessionId': 's$id', 'orderNo': 'HD${id.hashCode % 900 + 100}',
        'sessionStartedAt': _ago(minutes)},
      ...extra,
    };

/// Mỗi ngành một bộ khu + bàn/phòng/ghế + cài đặt bán hàng.
class _Floor {
  const _Floor(this.profile, this.settings, this.areas, this.resources, this.crumb);
  final PosSellProfile profile;
  final Map<String, Object?> settings;
  final List<Map<String, Object?>> areas;
  final List<Map<String, Object?>> resources;
  final String crumb;

  Object? api(String path) {
    if (path.endsWith('/api/pos/sell-settings')) return settings;
    if (path.endsWith('/api/pos/service-areas')) return areas;
    if (path.endsWith('/api/pos/service-resources')) return resources;
    return null;
  }
}

final _restaurant = _Floor(
  PosSellProfile.restaurant,
  {'id': 'ss1', 'sellProfile': 'restaurant', 'enableResources': true, 'showFloorPlan': true, 'allowProvisionalBill': true},
  [
    {'id': 'a1', 'name': 'Tầng 1', 'code': 'T1', 'sortOrder': 1, 'isActive': true},
    {'id': 'a2', 'name': 'Sân vườn', 'code': 'SV', 'sortOrder': 2, 'isActive': true},
  ],
  [
    _res('t1', 'Bàn 1', 'a1', 'Tầng 1', 1, 'Table', status: 'Occupied', guests: 2, subtotal: 118000, minutes: 32, lines: 3),
    _res('t2', 'Bàn 2', 'a1', 'Tầng 1', 2, 'Table'),
    _res('t3', 'Bàn 3', 'a1', 'Tầng 1', 3, 'Table', cap: 6),
    _res('t4', 'Bàn 4', 'a1', 'Tầng 1', 4, 'Table', status: 'Occupied', guests: 4, subtotal: 265000, minutes: 51, lines: 7),
    _res('t5', 'Bàn 5', 'a1', 'Tầng 1', 5, 'Table', cap: 2),
    _res('t6', 'Bàn 6', 'a1', 'Tầng 1', 6, 'Table', cap: 2),
    _res('t7', 'SV 1', 'a2', 'Sân vườn', 7, 'Table', status: 'Occupied', guests: 3, subtotal: 147000, minutes: 12, lines: 4),
    _res('t8', 'SV 2', 'a2', 'Sân vườn', 8, 'Table'),
  ],
  'Sơ đồ bàn',
);

final _karaoke = _Floor(
  PosSellProfile.roomHourly,
  {'id': 'ss1', 'sellProfile': 'roomHourly', 'enableResources': true, 'showFloorPlan': true, 'allowProvisionalBill': true},
  [
    {'id': 'k1', 'name': 'Tầng 2', 'code': 'T2', 'sortOrder': 1, 'isActive': true},
  ],
  [
    _res('r1', 'P.201', 'k1', 'Tầng 2', 1, 'Room', status: 'Occupied', guests: 6, subtotal: 385000, minutes: 74, lines: 4),
    _res('r2', 'P.202', 'k1', 'Tầng 2', 2, 'Room', status: 'Occupied', guests: 4, subtotal: 180000, minutes: 52, lines: 2,
        ),
    _res('r3', 'P.203', 'k1', 'Tầng 2', 3, 'Room'),
    _res('r4', 'P.204', 'k1', 'Tầng 2', 4, 'Room', status: 'Occupied', guests: 8, subtotal: 640000, minutes: 128, lines: 6,
        extra: {'billingLockedAt': _ago(3)}),
    _res('r5', 'P.205 VIP', 'k1', 'Tầng 2', 5, 'Room', cap: 15),
    _res('r6', 'P.206', 'k1', 'Tầng 2', 6, 'Room', status: 'Paused', guests: 5, subtotal: 245000, minutes: 61, lines: 3,
        extra: {'pausedAt': _ago(9), 'accumulatedPauseMinutes': 0}),
  ],
  'Sơ đồ phòng',
);

final _salon = _Floor(
  PosSellProfile.salon,
  {'id': 'ss1', 'sellProfile': 'salon', 'enableResources': true, 'showFloorPlan': true},
  [
    {'id': 'c1', 'name': 'Khu tóc', 'code': 'TOC', 'sortOrder': 1, 'isActive': true},
    {'id': 'c2', 'name': 'Khu spa', 'code': 'SPA', 'sortOrder': 2, 'isActive': true},
  ],
  [
    _res('g1', 'Ghế 1', 'c1', 'Khu tóc', 1, 'Chair', cap: 1, status: 'Occupied', guests: 1, subtotal: 150000, minutes: 25, lines: 2),
    _res('g2', 'Ghế 2', 'c1', 'Khu tóc', 2, 'Chair', cap: 1),
    _res('g3', 'Ghế 3', 'c1', 'Khu tóc', 3, 'Chair', cap: 1, status: 'Occupied', guests: 1, subtotal: 320000, minutes: 48, lines: 3),
    _res('g4', 'Ghế 4', 'c1', 'Khu tóc', 4, 'Chair', cap: 1),
    _res('g5', 'Giường 1', 'c2', 'Khu spa', 5, 'Chair', cap: 1, status: 'Occupied', guests: 1, subtotal: 450000, minutes: 40, lines: 1),
    _res('g6', 'Giường 2', 'c2', 'Khu spa', 6, 'Chair', cap: 1),
  ],
  'Sơ đồ ghế',
);

final _hotel = _Floor(
  PosSellProfile.hotel,
  {'id': 'ss1', 'sellProfile': 'hotel', 'enableResources': true, 'showFloorPlan': true, 'allowProvisionalBill': true},
  [
    {'id': 'h1', 'name': 'Tầng 3', 'code': 'T3', 'sortOrder': 1, 'isActive': true},
  ],
  [
    _res('h301', '301', 'h1', 'Tầng 3', 1, 'Room', cap: 2, status: 'Occupied', guests: 2, subtotal: 650000, minutes: 1140, lines: 2),
    _res('h302', '302', 'h1', 'Tầng 3', 2, 'Room', cap: 2),
    _res('h303', '303', 'h1', 'Tầng 3', 3, 'Room', cap: 3, status: 'Occupied', guests: 3, subtotal: 1350000, minutes: 1500, lines: 4),
    _res('h304', '304 VIP', 'h1', 'Tầng 3', 4, 'Room', cap: 2),
    _res('h305', '305', 'h1', 'Tầng 3', 5, 'Room', cap: 2, status: 'Occupied', guests: 1, subtotal: 240000, minutes: 95, lines: 1),
    _res('h306', '306', 'h1', 'Tầng 3', 6, 'Room', cap: 4),
  ],
  'Sơ đồ phòng',
);

Widget _screen(_Floor f, {bool manage = true, bool askGuests = false}) => withPosPackage(PosResourceFloorScreen(
      sellProfile: f.profile,
      autoRefreshSeconds: 0,
      manageMode: manage,
      promptGuestCountOnOpen: askGuests,
    ));

Future<void> _shot(WidgetTester t, String name, _Floor f, Size size,
    {bool manage = true, bool askGuests = false, Future<void> Function(WidgetTester t)? act, required List<GuideMark> marks}) async {
  PosSellSettingsHelper.lastProfile = f.profile;
  await guideShot(
    t,
    name: name,
    screen: _screen(f, manage: manage, askGuests: askGuests),
    api: posGuideApi((req) => f.api(req.url.path)),
    crumbs: ['POS', 'Bán hàng', f.crumb],
    size: size,
    act: act,
    marks: marks,
  );
}

/// Khung bao cả ô bàn / phòng: tên góc trên + mã góc dưới (+ dòng tiền nếu có).
List<Finder> _tile(String name, [String? money]) => [
      GuideMark.within(find.text(name).first, 'Row'),
      find.text(name).last,
      if (money != null) find.textContaining(money),
    ];

Finder _menu(String label) => GuideMark.within(find.text(label), 'ListTile');

Finder _inDialog(Type type) => find.descendant(of: find.byType(Dialog), matching: find.byType(type));

Future<void> _longPress(WidgetTester t, String name) async {
  await t.longPress(find.text(name).first);
  await t.pump(const Duration(milliseconds: 600));
}

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('ind-restaurant-1$suffix: tạo bàn nhanh', (t) async {
      await _shot(t, 'ind-restaurant-1$suffix', _restaurant, size,
          act: (t) async {
            await t.tap(find.byTooltip('Tạo bàn nhanh'));
            await t.pump(const Duration(milliseconds: 600));
            await t.enterText(_inDialog(TextField).first, 'Tầng 2');
            await t.pump(const Duration(milliseconds: 300));
          },
          marks: [
            GuideMark(1, [_inDialog(TextField).first]),
            GuideMark(2, [find.text('Số bàn trong nhóm'), _inDialog(TextField).at(2)]),
            GuideMark(3, [GuideMark.button(find.text('Tạo'))]),
          ]);
    });

    testWidgets('ind-restaurant-2$suffix: mở bàn, nhập số khách', (t) async {
      await _shot(t, 'ind-restaurant-2$suffix', _restaurant, size, manage: false, askGuests: true,
          act: (t) async {
            await t.tap(find.text('Bàn 3').first);
            await t.pump(const Duration(milliseconds: 600));
          },
          marks: [
            GuideMark(1, [find.text('Số khách (tối đa 6)'), _inDialog(TextField).first]),
            GuideMark(2, [GuideMark.button(find.text('Mở bàn'))]),
          ]);
    });

    testWidgets('ind-room-hourly-1$suffix: sơ đồ phòng tính giờ', (t) async {
      await _shot(t, 'ind-room-hourly-1$suffix', _karaoke, size, manage: false, marks: [
        GuideMark(1, _tile('P.201', '385.000'), pad: 8),
        GuideMark(2, _tile('P.204', '640.000'), pad: 8),
        GuideMark(3, _tile('P.206', '245.000'), pad: 8),
      ]);
    });

    testWidgets('ind-room-hourly-2$suffix: tạm dừng / chốt giờ', (t) async {
      await _shot(t, 'ind-room-hourly-2$suffix', _karaoke, size, manage: false,
          act: (t) => _longPress(t, 'P.201'),
          marks: [
            GuideMark(1, [_menu('Tạm dừng tính giờ')], pad: 2),
            GuideMark(2, [_menu('Chốt tiền giờ')], pad: 2),
          ]);
    });

    testWidgets('ind-salon-1$suffix: sơ đồ ghế', (t) async {
      await _shot(t, 'ind-salon-1$suffix', _salon, size, marks: [
        GuideMark(1, [GuideMark.button(find.byTooltip('Tạo ghế nhanh'))]),
        GuideMark(2, _tile('Ghế 3', '320.000'), pad: 8),
      ]);
    });

    testWidgets('ind-hotel-1$suffix: sơ đồ phòng khách sạn', (t) async {
      await _shot(t, 'ind-hotel-1$suffix', _hotel, size, manage: false, marks: [
        GuideMark(1, _tile('302'), pad: 8),
        GuideMark(2, _tile('303', '1.350.000'), pad: 8),
      ]);
    });

    testWidgets('ind-hotel-2$suffix: khách lưu trú', (t) async {
      await _shot(t, 'ind-hotel-2$suffix', _hotel, size, manage: false,
          act: (t) => _longPress(t, '303'),
          marks: [
            GuideMark(1, [_menu('Khách lưu trú (tạm trú)')], pad: 2),
          ]);
    });
  }
}
