import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/device_management_settings_screen.dart';

import 'guide_shot_kit.dart';

/// Ảnh cho bước hướng dẫn «Kết nối máy chấm công ZKTeco» (id: device_connect).

String _ago(Duration d) => DateTime.now().toUtc().subtract(d).toIso8601String();

List<Map<String, Object?>> _devices() => [
      {
        'id': 'd1', 'deviceName': 'Máy cửa chính', 'serialNumber': 'CQZ7232460512', 'location': 'Quầy lễ tân',
        'ipAddress': '192.168.1.201', 'deviceStatus': 'online', 'lastOnline': _ago(const Duration(seconds: 20)),
        'fingerprintCount': 42, 'faceTemplateCount': 18, 'isActive': true,
      },
      {
        'id': 'd2', 'deviceName': 'Máy kho', 'serialNumber': 'CQZ7232460877', 'location': 'Kho sau',
        'ipAddress': '192.168.1.202', 'deviceStatus': 'offline', 'lastOnline': _ago(const Duration(hours: 3)),
        'fingerprintCount': 11, 'isActive': true,
      },
    ];

const _crumbs = ['Cài đặt', 'Máy chấm công'];

Finder _field(String label) => find.widgetWithText(TextField, label);

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('device-connect-1$suffix: hướng dẫn trỏ máy về máy chủ', (t) async {
      await guideShot(
        t,
        name: 'device-connect-1$suffix',
        screen: const DeviceManagementSettingsScreen(),
        api: guideApi({'/api/devices': _devices()}),
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await t.tap(find.text('Cách kết nối máy chấm công'));
        },
        marks: [
          GuideMark(1, [find.textContaining('Trên máy ZKTeco vào'), find.textContaining('Nhập Địa chỉ máy chủ')]),
        ],
      );
    });

    testWidgets('device-connect-2$suffix: thêm máy bằng số serial', (t) async {
      await guideShot(
        t,
        name: 'device-connect-2$suffix',
        screen: const DeviceManagementSettingsScreen(),
        api: guideApi({'/api/devices': _devices()}),
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          final add = find.text('Thêm thiết bị');
          await t.tap(add.evaluate().isNotEmpty ? add.first : find.byIcon(Icons.add_circle).first);
          await t.pump(const Duration(milliseconds: 400));
          await t.enterText(_field('Serial Number *'), 'CQZ7232461033');
          await t.enterText(_field('Tên thiết bị *'), 'Máy chi nhánh 2');
          await t.enterText(_field('Vị trí lắp đặt'), 'Cửa nhân viên');
        },
        marks: [
          GuideMark(1, [_field('Serial Number *')]),
          GuideMark(2, [_field('Tên thiết bị *')]),
          GuideMark(3, [GuideMark.button(find.text('Thêm').last)]),
        ],
      );
    });

    testWidgets('device-connect-3$suffix: trạng thái Online / Offline', (t) async {
      await guideShot(
        t,
        name: 'device-connect-3$suffix',
        screen: const DeviceManagementSettingsScreen(),
        api: guideApi({'/api/devices': _devices()}),
        crumbs: _crumbs,
        size: size,
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Máy cửa chính'))], pad: 4),
          GuideMark(2, [GuideMark.button(find.text('Máy kho'))], pad: 4),
        ],
      );
    });
  }
}
