import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:zkteco_flutter_client/screens/attendance_approval_v2/aa_hub_screen.dart';

import 'guide_shot_kit.dart';
import 'hrm_extras_common.dart';

/// Ảnh «Duyệt chấm công» cho bước hướng dẫn «Chấm công thô & duyệt chấm công» (id: raw_attendance).

final _now = DateTime.now();
String _iso(DateTime t) => '${isoDay(t)}T${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';
DateTime _at(int daysAgo, int h, int m) => DateTime(_now.year, _now.month, _now.day - daysAgo, h, m);
String _ago(int hours) => _now.toUtc().subtract(Duration(hours: hours)).toIso8601String();

final _inbox = {
  'items': [
    {
      'kind': 'mobile', 'id': 'm1', 'employeeName': 'Võ Minh Tuấn', 'employeeCode': '5', 'department': 'Phục vụ',
      'time': _iso(_at(0, 13, 55)), 'createdAt': _ago(1), 'title': 'Vào ca 13:55', 'subtitle': 'Chi nhánh Quận 3 · cách 1,2 km',
      'reason': 'Quản lý điều sang chi nhánh Quận 3 hỗ trợ', 'riskLevel': 'review', 'riskScore': 38,
      'flags': ['Cách vị trí gần nhất 1,2 km'], 'distance': 1200, 'punchType': 0, 'isOutside': true, 'faceScore': 93,
    },
    {
      'kind': 'correction', 'id': 'c1', 'employeeName': 'Trần Thị Lan', 'employeeCode': '2', 'department': 'Phục vụ',
      'time': _iso(_at(2, 17, 0)), 'createdAt': _ago(20), 'title': 'Bổ sung chấm công 17:00', 'reason': 'Quên chấm ra, máy báo đầy bộ nhớ',
      'correctionAction': 0,
    },
    {
      'kind': 'mobile', 'id': 'm2', 'employeeName': 'Lê Văn Minh', 'employeeCode': '3', 'department': 'Bếp',
      'time': _iso(_at(0, 6, 1)), 'createdAt': _ago(8), 'title': 'Vào ca 06:01', 'subtitle': 'Cơm Gà Nam · cách 40 m',
      'riskLevel': 'trusted', 'riskScore': 5, 'distance': 40, 'punchType': 0, 'faceScore': 96,
    },
  ],
  'counts': {'all': 3, 'mobile': 2, 'correction': 1, 'outside': 1, 'trusted': 1, 'high': 0, 'overdue': 0},
  'stats30': [
    {'status': 'auto_approved', 'count': 54},
    {'status': 'approved', 'count': 12},
    {'status': 'rejected', 'count': 2},
  ],
};

final _mobileCtx = {
  'record': {
    'id': 'm1', 'employeeName': 'Võ Minh Tuấn', 'punchTime': _iso(_at(0, 13, 55)), 'punchType': 0, 'status': 'pending',
    'latitude': 10.7835, 'longitude': 106.6870, 'locationName': 'Chi nhánh Quận 3', 'distanceFromLocation': 1200,
    'gpsAccuracy': 25, 'faceMatchScore': 93, 'outsideReason': 'Quản lý điều sang chi nhánh Quận 3 hỗ trợ',
    'riskScore': 38, 'riskLevel': 'review', 'riskFlags': ['Cách vị trí gần nhất 1,2 km'],
  },
  'employee': {'id': 'e5', 'name': 'Võ Minh Tuấn', 'employeeCode': '5', 'department': 'Phục vụ'},
  'device': {'name': 'Điện thoại của Tuấn', 'model': 'Galaxy A54'},
  'shift': {'name': 'Ca chiều', 'start': '14:00', 'end': '22:00'},
  'sameDay': [
    {'id': 'm1', 'punchTime': _iso(_at(0, 13, 55)), 'punchType': 0, 'status': 'pending', 'locationName': 'Chi nhánh Quận 3', 'isOutside': true},
  ],
  'logs': [],
  'outsideThisMonth': 1,
  'history': [],
  'locations': [
    {'name': 'Cơm Gà Nam', 'latitude': 10.7769, 'longitude': 106.7009, 'radius': 150},
  ],
};

MockClient get _api => guideApi({
      '/records/m1/context': _mobileCtx,
      '/attendance-approvals/inbox': _inbox,
      '/approval-settings': {'autoApproveTrusted': true, 'trustedMaxDistanceMeters': 300, 'trustedMinFaceScore': 85},
    });

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = size.width < 600;
    testWidgets('raw-attendance-2$suffix: duyệt chấm công', (t) async {
      await guideShot(
        t,
        name: 'raw-attendance-2$suffix',
        screen: const AttendanceApprovalHubScreen(enableMapTiles: false),
        api: _api,
        crumbs: const ['Chấm công', 'Duyệt chấm công'],
        size: size,
        act: (t) async => extrasSettle(t),
        marks: [
          GuideMark(1, [find.textContaining('Tất cả (3)'), find.textContaining(mobile ? 'Sửa công (' : 'Sửa / bổ sung công (')], pad: 6),
          GuideMark(2, [cardOf(find.text('Trần Thị Lan').first)], pad: 2),
          if (!mobile) GuideMark(3, [GuideMark.button(find.text('Duyệt 1 bản tin cậy'))], pad: 2),
        ],
      );
    });
  }
}
