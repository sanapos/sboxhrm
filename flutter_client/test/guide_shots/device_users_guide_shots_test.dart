import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:zkteco_flutter_client/screens/device_users_screen.dart';

import 'guide_shot_kit.dart';
import 'hrm_extras_common.dart';

/// Ảnh cho bước hướng dẫn «Đồng bộ NV & đăng ký vân tay / face» (id: device_users).

String _ago(Duration d) => DateTime.now().toUtc().subtract(d).toIso8601String();

List<Map<String, Object?>> _devices() => [
      {
        'id': 'd1', 'deviceName': 'Máy cửa chính', 'serialNumber': 'CQZ7232460512', 'location': 'Quầy lễ tân',
        'ipAddress': '192.168.1.201', 'deviceStatus': 'online', 'lastOnline': _ago(const Duration(seconds: 20)),
        'fingerprintCount': 9, 'faceTemplateCount': 3, 'isActive': true,
      },
    ];

Map<String, Object?> _du(String id, String pin, String name, String empId, String full, int fp, int face) => {
      'id': id, 'pin': pin, 'name': name, 'privilege': 0, 'isActive': true, 'deviceId': 'd1',
      'deviceName': 'Máy cửa chính', 'employee': {'id': empId, 'fullName': full},
      'fingerprintCount': fp, 'copyableFingerprintCount': fp, 'faceCount': face,
    };

final _deviceUsers = [
  _du('u1', '1', 'Nguyen Van Hung', 'e1', 'Nguyễn Văn Hùng', 2, 1),
  _du('u2', '2', 'Tran Thi Lan', 'e2', 'Trần Thị Lan', 2, 1),
  _du('u3', '3', 'Le Van Minh', 'e3', 'Lê Văn Minh', 1, 0),
  _du('u4', '4', 'Pham Thi Hoa', 'e4', 'Phạm Thị Hoa', 0, 0),
];

MockClient _api() => guideApi({
      '/api/devices': _devices(),
      '/api/employees': {'items': extrasEmployees, 'totalCount': extrasEmployees.length},
      '/api/deviceusers/devices': _deviceUsers,
      '/api/deviceusers/u2/fingerprints': [
        {'fingerIndex': 6, 'templateSize': 1200},
        {'fingerIndex': 5, 'templateSize': 1180},
      ],
      '/api/branches/select': [],
      '/api/Departments/select': [],
    });

const _crumbs = ['Chấm công', 'Nhân sự chấm công'];

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = size.width < 600;

    testWidgets('device-users-1$suffix: danh sách user trên máy', (t) async {
      await guideShot(
        t,
        name: 'device-users-1$suffix',
        screen: withExtrasPackage(const DeviceUsersScreen()),
        api: _api(),
        crumbs: _crumbs,
        size: size,
        marks: [
          GuideMark(1, [mobile ? find.byTooltip('Thao tác khác') : topActionBox('Tải hồ sơ NS', mobile: false)]),
          GuideMark(2, [GuideMark.button(find.text('NV chưa có trên máy'))]),
          if (!mobile) GuideMark(3, [find.text('Phạm Thị Hoa').first, find.text('0').last]),
        ],
      );
    });

    testWidgets('device-users-2$suffix: tải hồ sơ nhân sự xuống máy', (t) async {
      await guideShot(
        t,
        name: 'device-users-2$suffix',
        screen: withExtrasPackage(const DeviceUsersScreen()),
        api: _api(),
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          if (mobile) {
            await t.tap(find.byTooltip('Thao tác khác'));
            await extrasSettle(t, 3);
            await t.tap(find.text('Tải hồ sơ NS').last);
          } else {
            await t.tap(topAction('Tải hồ sơ NS'));
          }
          await extrasSettle(t);
          await t.tap(find.text('Chọn thiết bị *').last);
          await extrasSettle(t, 3);
          await t.tap(find.textContaining('Máy cửa chính (').last);
          await extrasSettle(t);
          await t.tap(inDialog(find.byType(Checkbox)).first);
          await extrasSettle(t, 3);
        },
        marks: [
          GuideMark(1, [decoratorLabeled('Chọn thiết bị *')]),
          GuideMark(2, [inDialog(find.byType(Checkbox)).first, inDialog(find.byType(Checkbox)).last]),
          GuideMark(3, [GuideMark.button(find.textContaining(RegExp(r'^Tải \d+ nhân viên')))]),
        ],
      );
    });

    testWidgets('device-users-3$suffix: quản lý vân tay', (t) async {
      await guideShot(
        t,
        name: 'device-users-3$suffix',
        screen: withExtrasPackage(const DeviceUsersScreen()),
        api: _api(),
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await t.tap(find.text('Tran Thi Lan').first);
          await extrasSettle(t, 3);
          await t.tap(find.text('Quản lý vân tay').last);
          await extrasSettle(t);
        },
        marks: [
          GuideMark(1, [find.textContaining('Đã đăng ký: 2/10').last]),
          GuideMark(2, [find.textContaining('Chọn ngón tay').last]),
          GuideMark(3, [find.text('TAY TRÁI'), find.text('TAY PHẢI'), find.text('Út').first, find.text('Út').last], pad: 14),
        ],
      );
    });
  }
}
