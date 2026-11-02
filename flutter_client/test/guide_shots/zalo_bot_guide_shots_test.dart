import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/zalo_bot_settings_screen.dart';
import 'package:zkteco_flutter_client/widgets/zalo_link_sheet.dart';

import 'guide_shot_kit.dart';

/// Ảnh cho bước hướng dẫn «Zalo bot thông báo nhân viên» (id: zalo_bot).

const _categories = [
  {'code': 'payroll', 'label': 'Lương & phiếu lương'},
  {'code': 'penalty', 'label': 'Phiếu phạt'},
  {'code': 'attendance', 'label': 'Chấm công & bổ sung công'},
  {'code': 'leave', 'label': 'Nghỉ phép'},
  {'code': 'overtime', 'label': 'Tăng ca'},
  {'code': 'shift', 'label': 'Ca làm / lịch làm'},
  {'code': 'approval', 'label': 'Phê duyệt'},
  {'code': 'task', 'label': 'Công việc'},
  {'code': 'kpi', 'label': 'KPI'},
  {'code': 'system', 'label': 'Hệ thống'},
];

Map<String, Object?> _settings({required bool connected}) => {
      'enabled': connected,
      'hasToken': connected,
      'botName': connected ? 'Cơm Gà Nam Bot' : null,
      'botLink': connected ? 'https://zalo.me/s/botcomganam' : '',
      'webhookOk': connected,
      'categories': connected ? ['payroll', 'penalty', 'attendance', 'leave', 'overtime', 'shift', 'approval'] : <String>[],
      'hideMoney': false,
      'linkedCount': connected ? 3 : 0,
      'allCategories': _categories,
    };

final _links = [
  {'userId': 'u2', 'name': 'Trần Thị Lan', 'linked': true, 'zaloName': 'Lan Trần'},
  {'userId': 'u3', 'name': 'Lê Văn Minh', 'linked': true, 'zaloName': 'Minh Lê'},
  {'userId': 'u4', 'name': 'Phạm Thị Hoa', 'linked': true, 'zaloName': 'Hoa Phạm'},
  {'userId': 'u5', 'name': 'Võ Minh Tuấn', 'linked': false},
  {'userId': 'u6', 'name': 'Hồ Ngọc Ánh', 'linked': false},
];

const _crumbs = ['Thiết lập SBOX', 'Tích hợp & thông báo', 'Zalo bot'];

Finder _tile(String label) => GuideMark.within(find.text(label), 'SettingsTile');

/// Bảng «Liên kết Zalo» của nhân viên đặt giữa trang Cài đặt mờ (giống bottom sheet trên app).
Widget _linkSheetPage() => ColoredBox(
      color: const Color(0x66000000),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: const Material(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            child: ZaloLinkSheet(initial: {
              'available': true,
              'linked': false,
              'botName': 'Cơm Gà Nam Bot',
              'botLink': 'https://zalo.me/s/botcomganam',
            }),
          ),
        ),
      ),
    );

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('zalo-bot-1$suffix: token bot và link mở bot', (t) async {
      await guideShot(
        t,
        name: 'zalo-bot-1$suffix',
        screen: const ZaloBotSettingsScreen(),
        api: guideApi({'/api/zalo-bot/settings': _settings(connected: false), '/api/zalo-bot/links': _links}),
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await t.enterText(find.byType(TextField).at(0), '123456789:AAFkq-guide');
          await t.enterText(find.byType(TextField).at(1), 'https://zalo.me/s/botcomganam');
        },
        marks: [
          GuideMark(1, [find.textContaining('1. Vào bot.zapps.me')]),
          GuideMark(2, [_tile('Token bot'), _tile('Link mở bot')], pad: 2),
        ],
      );
    });

    testWidgets('zalo-bot-2$suffix: webhook, bật gửi, nhóm thông báo', (t) async {
      await guideShot(
        t,
        name: 'zalo-bot-2$suffix',
        screen: const ZaloBotSettingsScreen(),
        api: guideApi({'/api/zalo-bot/settings': _settings(connected: true), '/api/zalo-bot/links': _links}),
        crumbs: _crumbs,
        size: size,
        act: (t) async => guideScrollTo(t, find.text('Nhận tin từ Zalo (webhook)'), alignment: 0.05),
        marks: [
          GuideMark(1, [_tile('Nhận tin từ Zalo (webhook)')], pad: 2),
          GuideMark(2, [_tile('Bật gửi qua Zalo'), GuideMark.within(find.text('Nhóm thông báo'), 'Column')], pad: 2),
        ],
      );
    });

    testWidgets('zalo-bot-3$suffix: nhân viên lấy mã liên kết', (t) async {
      await guideShot(
        t,
        name: 'zalo-bot-3$suffix',
        screen: _linkSheetPage(),
        api: guideApi({
          '/api/zalo-bot/me/code': {
            'code': '482915',
            'expiresAt': DateTime.now().toUtc().add(const Duration(minutes: 15)).toIso8601String(),
            'botName': 'Cơm Gà Nam Bot',
            'botLink': 'https://zalo.me/s/botcomganam',
          },
          '/api/zalo-bot/me': {'available': true, 'linked': false, 'botName': 'Cơm Gà Nam Bot'},
        }),
        crumbs: const ['Cài đặt', 'Liên kết Zalo'],
        size: size,
        act: (t) async => t.tap(find.text('Lấy mã liên kết')),
        marks: [
          GuideMark(1, [find.ancestor(of: find.text('482 915'), matching: find.byType(Container)).first], pad: 2),
          GuideMark(2, [GuideMark.button(find.text('Mở bot Zalo'))]),
        ],
      );
    });
  }
}
