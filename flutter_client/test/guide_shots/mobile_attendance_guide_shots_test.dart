import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/mobile_attendance_settings_screen.dart';

import 'guide_shot_kit.dart';

/// Ảnh cho bước hướng dẫn «Chấm công Mobile & duyệt» (id: mobile_attendance).

final _api = guideApi({
  '/api/mobile-attendance/settings': {
    'enableFaceId': true, 'enableGps': true, 'enableWifi': true, 'verificationMode': 'any',
    'gpsRadiusMeters': 100, 'minFaceMatchScore': 80.0, 'autoApproveInRange': true, 'allowManualApproval': true,
  },
  '/employees': [
    {'employeeId': 'e1', 'employeeName': 'Trần Thị Mai'},
    {'employeeId': 'e2', 'employeeName': 'Lê Văn Hùng'},
  ],
  '/api/mobile-attendance/locations': [
    {
      'id': 'l1', 'name': 'Cửa hàng Nguyễn Trãi', 'address': '125 Nguyễn Trãi, Q.1, TP.HCM',
      'latitude': 10.7681, 'longitude': 106.6907, 'radius': 100, 'isActive': true, 'autoApproveInRange': true,
      'wifiSsid': 'CHNguyenTrai',
    },
    {
      'id': 'l2', 'name': 'Kho Thủ Đức', 'address': '18 Đường số 7, TP. Thủ Đức',
      'latitude': 10.8495, 'longitude': 106.7537, 'radius': 200, 'isActive': true, 'autoApproveInRange': false,
    },
  ],
  '/api/mobile-attendance/devices': [
    {
      'id': 'a1', 'deviceId': 'and-7f2c', 'deviceName': 'Samsung Galaxy A35', 'deviceModel': 'SM-A356E',
      'osVersion': 'Android 14', 'employeeId': 'e1', 'employeeName': 'Trần Thị Mai', 'isAuthorized': true,
      'authorizedAt': '2026-10-02T08:10:00Z', 'lastUsedAt': '2026-10-29T07:58:00Z',
    },
    {
      'id': 'a2', 'deviceId': 'ios-91ab', 'deviceName': 'iPhone 13', 'deviceModel': 'iPhone14,5',
      'osVersion': 'iOS 18.1', 'employeeId': 'e2', 'employeeName': 'Lê Văn Hùng', 'isAuthorized': false,
    },
  ],
  '/api/mobile-attendance/device-change-requests': [],
});

const _crumbs = ['Cài đặt', 'Chấm công Mobile'];

/// Ô phương thức: máy tính là thẻ bấm được (InkWell), điện thoại là một hàng có công tắc.
Finder _method(String desc) {
  final tile = find.ancestor(of: find.text(desc), matching: find.byType(InkWell));
  return tile.evaluate().isNotEmpty ? tile.first : find.ancestor(of: find.text(desc), matching: find.byType(Row)).first;
}

Finder _segmented(String label) =>
    find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is SegmentedButton)).first;

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('mobile-attendance-1$suffix: bật phương thức xác thực', (t) async {
      await guideShot(
        t,
        name: 'mobile-attendance-1$suffix',
        screen: const MobileAttendanceSettingsScreen(),
        api: _api,
        crumbs: _crumbs,
        size: size,
        marks: [
          GuideMark(1, [
            _method('So khớp với ảnh đã đăng ký'),
            _method('Kết nối Wi-Fi đã khai báo ở điểm chấm'),
          ]),
          GuideMark(2, [_segmented('Chỉ cần đạt 1')]),
        ],
      );
    });

    testWidgets('mobile-attendance-2$suffix: vị trí chấm & Wi-Fi', (t) async {
      await guideShot(
        t,
        name: 'mobile-attendance-2$suffix',
        screen: const MobileAttendanceSettingsScreen(),
        api: _api,
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await t.tap(find.text('Vị trí'));
          await t.pump(const Duration(milliseconds: 500));
        },
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Thêm').first)]),
          GuideMark(2, [GuideMark.button(find.text('Cửa hàng Nguyễn Trãi'))], pad: 4),
        ],
      );
    });

    testWidgets('mobile-attendance-3$suffix: cấp quyền điện thoại nhân viên', (t) async {
      await guideShot(
        t,
        name: 'mobile-attendance-3$suffix',
        screen: const MobileAttendanceSettingsScreen(),
        api: _api,
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await t.tap(find.text('Thiết bị'));
          await t.pump(const Duration(milliseconds: 500));
        },
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Cấp quyền').first)]),
          GuideMark(2, [find.text('Lê Văn Hùng'), find.textContaining('iPhone 13'), find.text('Chờ duyệt')], pad: 10),
          GuideMark(3, [find.byTooltip('Duyệt'), find.byTooltip('Từ chối')], pad: 2),
        ],
      );
    });
  }
}
