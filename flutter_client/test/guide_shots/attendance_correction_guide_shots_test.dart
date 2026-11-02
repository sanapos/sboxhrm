import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/attendance_approval_v2/aa_hub_screen.dart';
import 'package:zkteco_flutter_client/screens/system_settings_screen.dart';

import 'guide_shot_kit.dart';
import 'hrm_extras_common.dart';

/// Ảnh cho bước hướng dẫn «Sửa công / bổ sung công & quên chấm công» (id: attendance_correction).

final _now = DateTime.now();
String _at(int h, int m, {int daysAgo = 0}) => DateTime(_now.year, _now.month, _now.day - daysAgo, h, m).toIso8601String();
String _ago(int hours) => _now.toUtc().subtract(Duration(hours: hours)).toIso8601String();

final _items = [
  {
    'kind': 'correction', 'id': 'c1', 'employeeName': 'Trần Thị Lan', 'employeeCode': '2', 'department': 'Phục vụ',
    'time': _at(17, 30, daysAgo: 1), 'createdAt': _ago(20), 'title': 'Bổ sung chấm ra 17:30',
    'reason': 'Quên chấm ra do máy báo lỗi lúc tan ca', 'correctionAction': 0,
  },
  {
    'kind': 'correction', 'id': 'c2', 'employeeName': 'Lê Văn Minh', 'employeeCode': '3', 'department': 'Bếp',
    'time': _at(6, 55, daysAgo: 2), 'createdAt': _ago(30), 'title': 'Bổ sung chấm vào 06:55',
    'reason': 'Vào sớm nhận hàng, quên chấm', 'correctionAction': 0, 'overdue': true,
  },
  {
    'kind': 'correction', 'id': 'c3', 'employeeName': 'Phạm Thị Hoa', 'employeeCode': '4', 'department': 'Thu ngân',
    'time': _at(14, 2, daysAgo: 3), 'createdAt': _ago(50), 'title': 'Sửa giờ chấm 14:02 → 13:58',
    'reason': 'Máy chấm chậm, xếp hàng chờ chấm', 'correctionAction': 1,
  },
];

final _ctx = {
  'request': {
    'id': 'c1', 'employeeName': 'Trần Thị Lan', 'action': 0, 'newDate': _at(0, 0, daysAgo: 1), 'newTime': '17:30',
    'reason': 'Quên chấm ra do máy báo lỗi lúc tan ca', 'status': 0, 'totalApprovalLevels': 2, 'currentApprovalStep': 1,
    'approvals': [
      {'stepOrder': 1, 'stepName': 'Quản lý trực tiếp', 'assignedUserName': 'Nguyễn Văn Hùng', 'status': 'Pending'},
      {'stepOrder': 2, 'stepName': 'Quản lý cấp cao', 'assignedUserName': 'Hồ Ngọc Ánh', 'status': 'Pending'},
    ],
  },
  'employee': {'id': 'e2', 'name': 'Trần Thị Lan', 'employeeCode': '2'},
  'shift': {'name': 'Ca chiều', 'start': '14:00', 'end': '17:30', 'dayOff': false},
  'logs': [
    {'attendanceTime': _at(13, 56, daysAgo: 1), 'note': 'Máy cửa chính', 'fromMobile': false},
  ],
  'requestsThisMonth': 2,
  'forgotCheckPenalty': 100000,
};

final _api = guideApi({
  '/attendance-approvals/inbox': {
    'items': _items,
    'counts': {'all': 3, 'mobile': 0, 'correction': 3, 'outside': 0, 'trusted': 0, 'high': 0, 'overdue': 1},
    'stats30': [
      {'status': 'approved', 'count': 14},
      {'status': 'rejected', 'count': 2},
    ],
  },
  '/corrections/c1/context': _ctx,
  '/api/settings/app/allow_manual_correction': {'value': 'true'},
  '/api/settings/app/attendance_approval_levels': {'value': '2'},
});

Finder _tile(String label) => GuideMark.within(find.text(label), 'SettingsTile');

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = size.width < 600;

    testWidgets('attendance-correction-1$suffix: bật xin sửa công, số cấp duyệt', (t) async {
      await guideShot(
        t,
        name: 'attendance-correction-1$suffix',
        screen: const SystemSettingsScreen(canEditOverride: true),
        api: _api,
        crumbs: const ['Thiết lập SBOX', 'Cửa hàng', 'Tham số hệ thống'],
        size: size,
        act: (t) async => guideScrollTo(t, find.text('Chấm công bù & quy trình duyệt'), alignment: 0.1),
        marks: [
          GuideMark(1, [_tile('Cho phép xin sửa / bổ sung công')], pad: 2),
          GuideMark(2, [_tile('Duyệt yêu cầu sửa công')], pad: 2),
        ],
      );
    });

    testWidgets('attendance-correction-2$suffix: danh sách cần duyệt', (t) async {
      await guideShot(
        t,
        name: 'attendance-correction-2$suffix',
        screen: const AttendanceApprovalHubScreen(enableMapTiles: false, autoOpenFirst: false),
        api: _api,
        crumbs: const ['Chấm công', 'Duyệt chấm công'],
        size: size,
        act: (t) async {
          await t.tap(find.textContaining(mobile ? 'Sửa công' : 'Sửa / bổ sung công (').first);
          await t.pump(const Duration(milliseconds: 300));
        },
        marks: [
          GuideMark(1, [find.textContaining(mobile ? 'Sửa công' : 'Sửa / bổ sung công (').first]),
          GuideMark(2, [find.text('Chọn tất cả')]),
          GuideMark(3, [GuideMark.within(find.text('Trần Thị Lan'), 'AaListTile'), GuideMark.within(find.text('Phạm Thị Hoa'), 'AaListTile')], pad: 2),
        ],
      );
    });

    testWidgets('attendance-correction-3$suffix: chi tiết, duyệt hoặc duyệt + phạt', (t) async {
      await guideShot(
        t,
        name: 'attendance-correction-3$suffix',
        screen: const AttendanceApprovalHubScreen(enableMapTiles: false),
        api: _api,
        crumbs: const ['Chấm công', 'Duyệt chấm công'],
        size: size,
        act: (t) async {
          if (mobile) await t.tap(find.text('Trần Thị Lan'));
          await extrasSettle(t);
          await guideScrollTo(t, find.text('Mức phạt quên chấm'), alignment: mobile ? 0.35 : 0.5);
        },
        marks: [
          GuideMark(1, [GuideMark.within(find.text('Trước'), '_BeforeAfter'), GuideMark.within(find.text('Sau khi duyệt'), '_BeforeAfter')], pad: 4),
          GuideMark(2, [GuideMark.within(find.text('Mức phạt quên chấm'), 'AaFact')], pad: 4),
          GuideMark(3, [
            GuideMark.button(find.text('Từ chối').last),
            GuideMark.button(find.text('Duyệt + phạt')),
            GuideMark.button(find.text('Duyệt').last),
          ]),
        ],
      );
    });
  }
}
