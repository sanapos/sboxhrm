import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:zkteco_flutter_client/screens/attendance_screen.dart';
import 'package:zkteco_flutter_client/services/signalr_service.dart';

import 'guide_shot_kit.dart';
import 'hrm_extras_common.dart';

/// Ảnh «Chấm công thô» cho bước hướng dẫn «Chấm công thô & duyệt chấm công» (id: raw_attendance).
/// Ảnh duyệt chấm công ở raw_attendance_approval_guide_shots_test.dart — chạy chung file thì SignalR của màn
/// chấm công thô còn sót làm màn duyệt treo.

final _now = DateTime.now();
String _iso(DateTime t) => '${isoDay(t)}T${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';
DateTime _at(int daysAgo, int h, int m) => DateTime(_now.year, _now.month, _now.day - daysAgo, h, m);

final _devices = [
  {'id': 'd1', 'deviceName': 'Máy cửa chính', 'serialNumber': 'CQZ7232460512', 'deviceStatus': 'online', 'isActive': true},
  {'id': 'd2', 'deviceName': 'Máy kho', 'serialNumber': 'CQZ7232460877', 'deviceStatus': 'online', 'isActive': true},
];

const _names = {'1': 'Nguyễn Văn Hùng', '2': 'Trần Thị Lan', '3': 'Lê Văn Minh', '4': 'Phạm Thị Hoa', '5': 'Võ Minh Tuấn'};
const _deviceNames = {'1': 'HUNG', '2': 'LAN', '3': 'MINH BEP', '4': 'HOA TN', '5': 'TUAN'};

/// Log chấm công: (mã NV, ngày trước, giờ, phút, vào/ra, máy, kiểu xác thực 1=vân tay 15=khuôn mặt).
const _punches = [
  ('1', 0, 7, 52, 0, 'd1', 15), ('2', 0, 7, 58, 0, 'd1', 1), ('3', 0, 6, 1, 0, 'd2', 1), ('4', 0, 8, 3, 0, 'd1', 15),
  ('5', 0, 13, 55, 0, 'd1', 1), ('3', 0, 14, 2, 1, 'd2', 1),
  ('1', 1, 7, 49, 0, 'd1', 15), ('1', 1, 17, 6, 1, 'd1', 15), ('2', 1, 8, 12, 0, 'd1', 1), ('2', 1, 17, 1, 1, 'd1', 1),
  ('4', 1, 7, 57, 0, 'd1', 15), ('4', 1, 17, 30, 1, 'd1', 15), ('5', 1, 13, 58, 0, 'd1', 1), ('5', 1, 22, 4, 1, 'd1', 1),
];

List<Map<String, Object?>> get _attendances => [
      for (final (pin, d, h, m, st, dev, vm) in _punches)
        {
          'id': 'a-$pin-$d-$h$m', 'pin': pin, 'employeeCode': pin, 'employeeName': _names[pin],
          'deviceUserName': _deviceNames[pin], 'deviceId': dev,
          'deviceName': dev == 'd1' ? 'Máy cửa chính' : 'Máy kho', 'attendanceTime': _iso(_at(d, h, m)),
          'attendanceState': st, 'verifyMode': vm,
        },
    ];

MockClient get _api => guideApi({
      '/api/devices': _devices,
      '/api/attendances/devices': {'items': _attendances, 'totalCount': _attendances.length},
      '/api/employees': {'items': extrasEmployees, 'totalCount': extrasEmployees.length},
    });

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = size.width < 600;
    testWidgets('raw-attendance-1$suffix: chấm công thô', (t) async {
      await guideShot(
        t,
        name: 'raw-attendance-1$suffix',
        screen: withExtrasPackage(const AttendanceScreen()),
        api: _api,
        crumbs: const ['Chấm công', 'Chấm công thô'],
        size: size,
        marks: [
          GuideMark(1, [find.text('Thời gian'), find.text('Chưa lọc')], pad: 18),
          if (!mobile) ...[
            GuideMark(2, [find.text('Kiểu xác thực').last, find.text('Khuôn mặt').at(1)], pad: 6),
            GuideMark(3, [GuideMark.button(find.text('Chấm công thủ công'))], pad: 2),
          ] else
            GuideMark(2, [GuideMark.button(find.text('Chấm công thủ công'))], pad: 2),
        ],
      );
      // Màn mở SignalR; không có máy chủ → hẹn giờ kết nối lại. Dừng và cho hẹn giờ chạy hết.
      await SignalRService().disconnect();
      await t.pump(const Duration(seconds: 70));
    });
  }
}
