import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_gym_checkin_screen.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_sell_industry_settings_screen.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';

/// Ảnh tab «Ngành hàng»: check-in hội viên gym (ind_gym), cài đặt ngành — tiền phòng theo đêm
/// (ind_hotel), bật hoa hồng nhân viên (ind_commission).

String _today(int h, int m) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, h, m).toUtc().toIso8601String();
}

Map<String, Object?> _visit(String id, String name, String phone, int h, int m,
        {String pkg = 'Thẻ tập 1 tháng', bool unlimited = true, String status = 'Ok', int? outH, int? outM, String? note}) =>
    {
      'id': id, 'customerId': 'c$id', 'customerName': name, 'phone': phone, 'checkInAt': _today(h, m),
      if (outH != null) 'checkOutAt': _today(outH, outM ?? 0),
      if (outH != null) 'durationMinutes': (outH * 60 + (outM ?? 0)) - (h * 60 + m),
      'packageName': pkg, 'unlimited': unlimited, 'status': status, 'denied': status != 'Ok',
      'sessionDeducted': !unlimited && status == 'Ok', 'deviceName': 'Máy cửa chính', if (note != null) 'note': note,
    };

final _visits = {
  'inside': 3, 'total': 6, 'customers': 6, 'warnings': 1,
  // Mới nhất trước, như máy chủ trả.
  'items': [
    _visit('6', 'Võ Thanh Tùng', '0909 888 777', 17, 50, status: 'Expired', note: 'Thẻ hết hạn 28/10'),
    _visit('5', 'Đỗ Gia Huy', '0977 222 111', 17, 32, pkg: 'Gói PT 12 buổi', unlimited: false),
    _visit('4', 'Nguyễn Thảo Vy', '0934 567 890', 17, 15),
    _visit('3', 'Phạm Quốc Bảo', '0988 123 456', 7, 10, outH: 8, outM: 30),
    _visit('2', 'Lê Thu Hà', '0912 445 667', 6, 40, pkg: 'Gói PT 12 buổi', unlimited: false, outH: 7, outM: 45),
    _visit('1', 'Trần Minh Khoa', '0903 112 233', 6, 5, outH: 7, outM: 20),
  ],
};

String _inDays(int d) => DateTime.now().add(Duration(days: d)).toIso8601String();

Map<String, Object?> _member(String id, String name, String phone, String pin,
        {int fp = 1, int face = 0, String pkg = 'Thẻ tập 1 tháng', int days = 21, int? sessions}) => {
      'id': 'm$id', 'customerId': 'c$id', 'customerName': name, 'phone': phone, 'pin': pin,
      'packageName': pkg, 'expiresAt': _inDays(days), 'unlimited': sessions == null,
      if (sessions != null) 'remainingSessions': sessions,
      'deviceId': 'd1', 'deviceName': 'Máy cửa chính', 'deviceOnline': true, 'supportsEnroll': true,
      'fingerprintCount': fp, 'faceCount': face, 'lastVisitAt': _today(17, 15),
    };

final _members = [
  _member('1', 'Trần Minh Khoa', '0903 112 233', '903112233', fp: 2),
  _member('2', 'Lê Thu Hà', '0912 445 667', '912445667', fp: 0, face: 1, pkg: 'Gói PT 12 buổi', days: 60, sessions: 8),
  _member('3', 'Phạm Quốc Bảo', '0988 123 456', '988123456'),
  _member('4', 'Nguyễn Thảo Vy', '0934 567 890', '934567890', fp: 0, face: 1),
  _member('7', 'Bùi Hoàng Nam', '', '90000001', fp: 0, days: 3),
];

Map<String, Object?> _settings(String profile, {bool commission = false}) => {
      'id': 'ss1', 'sellProfile': profile, 'defaultSellMode': 'normal', 'enableResources': true,
      'showFloorPlan': true, 'enableStaffCommission': commission,
    };

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('ind-gym-2$suffix: lượt tập hôm nay', (t) async {
      await guideShot(
        t,
        name: 'ind-gym-2$suffix',
        screen: withPosPackage(const PosGymCheckInScreen()),
        api: posGuideApi((req) {
          final p = req.url.path;
          if (p.endsWith('/api/pos/gym/visits')) return _visits;
          if (p.endsWith('/api/pos/gym/members')) return _members;
          return null;
        }),
        crumbs: const ['POS', 'Check-in hội viên'],
        size: size,
        marks: [
          GuideMark(1, [GuideMark.within(find.text('Đang tập').first, '_StatGrid')], pad: 4),
          GuideMark(2, [find.text('Võ Thanh Tùng'), find.textContaining('Thẻ hết hạn 28/10')], pad: 12),
          GuideMark(3, [GuideMark.button(find.text('Check-in tại quầy'))]),
        ],
      );
    });

    testWidgets('ind-gym-3$suffix: hội viên trên máy', (t) async {
      await guideShot(
        t,
        name: 'ind-gym-3$suffix',
        screen: withPosPackage(const PosGymCheckInScreen()),
        api: posGuideApi((req) {
          final p = req.url.path;
          if (p.endsWith('/api/pos/gym/visits')) return _visits;
          if (p.endsWith('/api/pos/gym/members')) return _members;
          if (p.endsWith('/api/pos/gym/expiring')) return [_members.last];
          return null;
        }),
        crumbs: const ['POS', 'Check-in hội viên'],
        size: size,
        act: (t) async {
          await t.tap(find.text('Hội viên trên máy'));
          await t.pump(const Duration(milliseconds: 600));
          for (var i = 0; i < 4; i++) {
            await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
            await t.pump(const Duration(milliseconds: 100));
          }
        },
        marks: [
          GuideMark(1, [
            find.text('Trần Minh Khoa'), find.textContaining('HSD').first, find.text('Lấy vân tay').first,
            find.text('Lấy khuôn mặt').first, find.text('Gỡ khỏi máy').first,
          ], pad: 10),
          GuideMark(2, [GuideMark.button(find.textContaining('Cần nhắc gia hạn'))]),
          GuideMark(3, [GuideMark.button(find.text('Thêm hội viên lên máy'))]),
        ],
      );
    });

    testWidgets('ind-hotel-4$suffix: tính tiền phòng theo đêm', (t) async {
      await guideShot(
        t,
        name: 'ind-hotel-4$suffix',
        screen: withPosPackage(const PosSellIndustrySettingsScreen()),
        api: posGuideApi((req) => req.url.path.endsWith('/api/pos/sell-settings') ? _settings('hotel') : null),
        crumbs: const ['Thiết lập SBOX', 'Ngành hàng & cách bán'],
        size: size,
        act: (t) => guideScrollTo(t, find.text('Tính tiền phòng theo đêm'), alignment: 0.2),
        marks: [
          GuideMark(1, [GuideMark.within(find.text('Tính tiền phòng theo đêm'), 'SwitchListTile')]),
          GuideMark(2, [
            GuideMark.within(find.text('Giờ nhận phòng'), 'ListTile'),
            GuideMark.within(find.text('Ân hạn (phút)'), 'ListTile'),
          ]),
        ],
      );
    });

    testWidgets('ind-commission-2$suffix: bật hoa hồng nhân viên', (t) async {
      await guideShot(
        t,
        name: 'ind-commission-2$suffix',
        screen: withPosPackage(const PosSellIndustrySettingsScreen()),
        api: posGuideApi((req) =>
            req.url.path.endsWith('/api/pos/sell-settings') ? _settings('salon', commission: true) : null),
        crumbs: const ['Thiết lập SBOX', 'Ngành hàng & cách bán'],
        size: size,
        act: (t) => guideScrollTo(t, find.text('Hoa hồng nhân viên'), alignment: 0.3),
        marks: [
          GuideMark(1, [GuideMark.within(find.text('Hoa hồng nhân viên'), 'SwitchListTile')]),
        ],
      );
    });
  }
}
