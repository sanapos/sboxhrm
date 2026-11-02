import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zkteco_flutter_client/screens/gateway/zk_gateway_setup_screen.dart';

import 'guide_shot_kit.dart';
import 'hrm_extras_common.dart' show extrasSettle;

/// Ảnh cho bước hướng dẫn «Gateway WiFi cho máy chấm công đời cũ» (id: gateway_wifi).
/// Mạch ESP32 giả: trả JSON thô của firmware (không bọc isSuccess như API SBOX).

final _gateway = MockClient((req) async {
  final body = switch (req.url.path) {
    '/api/info' => {
        'product': 'sbox-zk-gateway', 'ip': '192.168.4.1', 'name': '', 'serial': 'A8N5202460031',
        'version': '1.6.2', 'apSsid': 'SBOX-Gateway-7F3A', 'provisioned': false, 'wifiConnected': false,
      },
    '/api/config' => {'gwName': '', 'wifiSsid': '', 'deviceIp': '', 'commKey': 0},
    '/api/scan' => [
        {'ssid': 'ComGaNam_2.4G', 'rssi': -48, 'secure': true},
        {'ssid': 'ComGaNam_Kho', 'rssi': -67, 'secure': true},
        {'ssid': 'FPT Telecom', 'rssi': -80, 'secure': true},
      ],
    _ => <String, Object?>{},
  };
  return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
});

/// Ô nhập của màn gateway: nhãn là dòng chữ riêng phía trên → lấy cả cột (nhãn + ô).
Finder _block(String label) => find.ancestor(of: find.text(label), matching: find.byType(Column)).first;
Finder _input(String label) => find.descendant(of: _block(label), matching: find.byType(TextField));

const _crumbs = ['Thiết lập SBOX', 'Gateway WiFi', 'Thêm gateway'];

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('gateway-wifi-1$suffix: chuẩn bị, cấu hình qua Bluetooth', (t) async {
      await guideShot(
        t,
        name: 'gateway-wifi-1$suffix',
        screen: const ZkGatewaySetupScreen(),
        api: _gateway,
        crumbs: _crumbs,
        size: size,
        act: (t) async => guideScrollTo(t, find.text('Cần chuẩn bị'), alignment: 0.05),
        marks: [
          GuideMark(1, [find.text('Cần chuẩn bị'), find.textContaining('Mật khẩu WiFi 2.4GHz')], pad: 8),
          GuideMark(2, [GuideMark.button(find.text('Bắt đầu bằng Bluetooth'))]),
        ],
      );
    });

    testWidgets('gateway-wifi-2$suffix: WiFi, IP máy chấm công, lưu', (t) async {
      await guideShot(
        t,
        name: 'gateway-wifi-2$suffix',
        screen: const ZkGatewaySetupScreen(),
        api: _gateway,
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await t.ensureVisible(find.text('Cách cũ: nối WiFi SoftAP (mất mạng tạm)'));
          await t.tap(find.text('Cách cũ: nối WiFi SoftAP (mất mạng tạm)'));
          await extrasSettle(t);
          await t.ensureVisible(find.text('Tôi đã kết nối, kiểm tra'));
          await t.tap(find.text('Tôi đã kết nối, kiểm tra'));
          await extrasSettle(t, 10);
          await t.enterText(_input('Mật khẩu WiFi'), 'comganam2024');
          await t.enterText(_input('Tên gợi nhớ cho gateway'), 'Cửa trước - tầng 1');
          await t.enterText(_input('IP máy chấm công trong LAN'), '192.168.1.201');
          await t.tap(find.text('ComGaNam_2.4G').first);
          await t.pump();
          await guideScrollTo(t, find.text('ComGaNam_2.4G').first, alignment: 0.02);
        },
        marks: [
          GuideMark(1, [find.ancestor(of: find.text('ComGaNam_2.4G').first, matching: find.byType(InkWell)).first], pad: 2),
          GuideMark(2, [_block('Mật khẩu WiFi')]),
          GuideMark(3, [_block('Tên gợi nhớ cho gateway'), _block('IP máy chấm công trong LAN')]),
        ],
      );
    });
  }
}
