import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/staff_map/staff_map_screen.dart';

import 'guide_shot_kit.dart';
import 'hrm_extras_common.dart';

/// Ảnh cho bước hướng dẫn «Bản đồ nhân sự / chấm ngoài hiện trường» (id: field_checkin).
/// Nền bản đồ (ô ảnh tải từ mạng) không có trong test — ảnh tập trung vào danh sách và lộ trình.

final _now = DateTime.now().toUtc();
String _ago(int minutes) => _now.subtract(Duration(minutes: minutes)).toIso8601String();

Map<String, dynamic> _emp(String id, String code, String name, String dept, String status,
        {double? lat, double? lng, int minutes = 1, bool onShift = true, bool lost = false, String? at, String? checkin,
        double km = 0, int? battery}) =>
    {
      'employeeId': id, 'employeeCode': code, 'employeeName': name, 'department': dept, 'position': '',
      'status': status, 'latitude': lat, 'longitude': lng, 'lat': lat, 'lng': lng, 'minutesAgo': minutes,
      'time': _ago(minutes), 'onShift': onShift, 'signalLostOnShift': lost, 'atWorkLocation': at,
      'activeCheckin': checkin, 'distanceTodayKm': km, 'battery': battery, 'hasAccount': true,
      'shiftStart': '08:00', 'shiftEnd': '17:00',
    };

final _live = {
  'summary': {'total': 6, 'online': 3, 'onShift': 4, 'signalLostOnShift': 1, 'offline': 1, 'stale': 1, 'noLocation': 1},
  'departments': ['Giao hàng', 'Kinh doanh', 'Kỹ thuật'],
  'workLocations': [
    {'id': 'w1', 'name': 'Cửa hàng Quận 3', 'latitude': 10.7799, 'longitude': 106.6872, 'radius': 100},
  ],
  'employees': [
    _emp('e11', '11', 'Ngô Thanh Tâm', 'Kinh doanh', 'online', lat: 10.7764, lng: 106.7009, km: 12.4, battery: 78, checkin: 'Siêu thị Co.op Q1'),
    _emp('e12', '12', 'Đỗ Văn Phúc', 'Giao hàng', 'online', lat: 10.7885, lng: 106.6713, minutes: 2, km: 28.1, battery: 54),
    _emp('e13', '13', 'Lý Thị Mai', 'Kỹ thuật', 'online', lat: 10.7799, lng: 106.6872, at: 'Cửa hàng Quận 3', km: 3.2, battery: 91),
    _emp('e14', '14', 'Trịnh Quốc Huy', 'Giao hàng', 'stale', lat: 10.8010, lng: 106.6650, minutes: 18, lost: true, km: 9.7, battery: 12),
    _emp('e15', '15', 'Phan Ngọc Yến', 'Kinh doanh', 'offline', lat: 10.7600, lng: 106.6600, minutes: 140, onShift: false, km: 4.0),
    _emp('e16', '16', 'Võ Thành Đạt', 'Kỹ thuật', 'none', onShift: true),
  ],
};

String _at(int h, int m) => DateTime.now().copyWith(hour: h, minute: m, second: 0).toUtc().toIso8601String();

final _route = {
  'windowLabel': 'Ca hành chính 08:00–17:00',
  'shifts': [
    {'id': 's1', 'name': 'Ca hành chính', 'start': '08:00', 'end': '17:00'},
  ],
  'summary': {
    'distanceKm': 12.4, 'movingMinutes': 96, 'stoppedMinutes': 205, 'stops': 3, 'checkins': 2, 'punches': 1,
    'gaps': 0, 'gapMinutes': 0, 'first': _at(8, 2), 'last': _at(13, 5),
  },
  'workLocations': _live['workLocations'],
  'points': [
    for (final (i, p) in [
      (10.7799, 106.6872), (10.7790, 106.6905), (10.7781, 106.6950), (10.7770, 106.6990), (10.7764, 106.7009),
      (10.7740, 106.7030), (10.7712, 106.7046), (10.7690, 106.7020), (10.7700, 106.6980),
    ].indexed)
      {'lat': p.$1, 'lng': p.$2, 't': _at(8 + i ~/ 2, (i % 2) * 30 + 2)},
  ],
  'stops': [
    {'index': 1, 'lat': 10.7799, 'lng': 106.6872, 'minutes': 35, 'place': 'Cửa hàng Quận 3'},
    {'index': 2, 'lat': 10.7764, 'lng': 106.7009, 'minutes': 95, 'place': 'Siêu thị Co.op Q1'},
    {'index': 3, 'lat': 10.7712, 'lng': 106.7046, 'minutes': 75, 'place': 'Nhà hàng Bến Thành'},
  ],
  'timeline': [
    {'type': 'punch', 'time': _at(8, 2), 'title': 'Chấm công vào', 'detail': 'Cửa hàng Quận 3', 'lat': 10.7799, 'lng': 106.6872},
    {'type': 'stop', 'index': 1, 'time': _at(8, 2), 'end': _at(8, 37), 'title': 'Dừng 35 phút', 'detail': 'Cửa hàng Quận 3', 'lat': 10.7799, 'lng': 106.6872},
    {'type': 'checkin', 'time': _at(9, 5), 'title': 'Check-in khách hàng', 'detail': 'Siêu thị Co.op Q1', 'lat': 10.7764, 'lng': 106.7009},
    {'type': 'stop', 'index': 2, 'time': _at(9, 5), 'end': _at(10, 40), 'title': 'Dừng 95 phút', 'detail': 'Siêu thị Co.op Q1', 'lat': 10.7764, 'lng': 106.7009},
    {'type': 'checkin', 'time': _at(11, 20), 'title': 'Check-in khách hàng', 'detail': 'Nhà hàng Bến Thành', 'lat': 10.7712, 'lng': 106.7046},
    {'type': 'stop', 'index': 3, 'time': _at(11, 20), 'end': _at(12, 35), 'title': 'Dừng 75 phút', 'detail': 'Nhà hàng Bến Thành', 'lat': 10.7712, 'lng': 106.7046},
  ],
};

final _api = guideApi({
  '/api/staff-map/live': _live,
  '/api/staff-map/route': _route,
});

const _crumbs = ['Bản đồ nhân sự'];

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('field-checkin-1$suffix: vị trí nhân viên', (t) async {
      await guideShot(
        t,
        name: 'field-checkin-1$suffix',
        screen: withExtrasPackage(const StaffMapScreen()),
        api: _api,
        crumbs: _crumbs,
        size: size,
        marks: [
          GuideMark(1, [cardOf(find.text('Tổng NV')), cardOf(find.text('Chưa có vị trí'))], pad: 6),
          GuideMark(2, [
            find.ancestor(of: find.text('Tìm tên, mã NV, bộ phận'), matching: find.byType(TextField)).first,
            GuideMark.button(find.text('Tất cả bộ phận')),
          ]),
          if (size.width >= 600) GuideMark(3, [find.byTooltip('Xem lộ trình').first], pad: 4),
        ],
      );
    });

    testWidgets('field-checkin-2$suffix: lộ trình trong ca', (t) async {
      await guideShot(
        t,
        name: 'field-checkin-2$suffix',
        screen: withExtrasPackage(const StaffMapScreen()),
        api: _api,
        crumbs: [..._crumbs, 'Lộ trình'],
        size: size,
        act: (t) async {
          if (size.width < 600) {
            // Điện thoại: danh sách nằm trong khung kéo lên từ dưới bản đồ.
            await t.drag(find.text('Bản đồ nhân sự').last, const Offset(0, -700));
            await extrasSettle(t, 4);
          }
          await t.tap(find.byTooltip('Xem lộ trình').first);
          await extrasSettle(t, 8);
        },
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Trong ca')), GuideMark.button(find.text('Cả ngày'))]),
          GuideMark(2, [cardOf(find.text('Quãng đường')), cardOf(find.textContaining('Chấm công').first)], pad: 6),
          GuideMark(3, [find.text('Dòng thời gian'), find.text('Check-in khách hàng').first], pad: 12),
        ],
      );
    });
  }
}
