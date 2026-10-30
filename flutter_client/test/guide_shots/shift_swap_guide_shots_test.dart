import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/shift_swap_screen.dart';

import 'guide_shot_kit.dart';

/// Ảnh cho bước hướng dẫn «Đổi ca làm việc» (id: shift_swap).

Map<String, Object?> _swap(int id, String from, String to, String fromShift, String toShift, String date, String status,
        {String? targetUserId}) =>
    {
      'id': id,
      'requesterName': from,
      'targetName': to,
      'requesterShiftName': fromShift,
      'targetShiftName': toShift,
      'requesterDate': date,
      'targetDate': date,
      'status': status,
      'reason': 'Việc gia đình',
      if (targetUserId != null) 'targetUserId': targetUserId,
    };

final _waitManager = _swap(1, 'Trần Thị Bình', 'Lê Văn Cường', 'Ca sáng', 'Ca chiều', '2026-11-03', 'TargetAccepted');
final _waitMe = _swap(2, 'Phạm Minh Dũng', 'Nguyễn Văn An', 'Ca chiều', 'Ca sáng', '2026-11-05', 'Pending', targetUserId: 'u1');
final _done = _swap(3, 'Hoàng Thu Hà', 'Trần Thị Bình', 'Ca đêm', 'Ca sáng', '2026-10-27', 'Approved');

final _api = guideApi({
  '/api/shiftswaps/pending-for-me': [_waitMe],
  '/api/shiftswaps/pending-approval': [_waitManager],
  '/api/shiftswaps/colleagues': [
    {'userId': 'u2', 'fullName': 'Lê Văn Cường', 'employeeCode': 'NV003'},
    {'userId': 'u3', 'fullName': 'Trần Thị Bình', 'employeeCode': 'NV002'},
    {'userId': 'u4', 'fullName': 'Phạm Minh Dũng', 'employeeCode': 'NV004'},
  ],
  '/api/shiftswaps': [_waitManager, _waitMe, _done],
  '/api/shifts/templates': [
    {'id': 's1', 'name': 'Ca sáng', 'startTime': '06:00:00', 'endTime': '14:00:00', 'isActive': true},
    {'id': 's2', 'name': 'Ca chiều', 'startTime': '14:00:00', 'endTime': '22:00:00', 'isActive': true},
    {'id': 's3', 'name': 'Ca đêm', 'startTime': '22:00:00', 'endTime': '06:00:00', 'isActive': true},
  ],
});

const _crumbs = ['Chấm công', 'Đổi ca làm việc'];

Finder _dropdown(String label) => GuideMark.within(find.text(label), 'DropdownButtonFormField<String>');
Finder _dateTile(String label) => GuideMark.within(find.text(label), 'ListTile');

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('shift-swap-1$suffix: tạo yêu cầu đổi ca', (t) async {
      await guideShot(
        t,
        name: 'shift-swap-1$suffix',
        screen: const ShiftSwapScreen(),
        api: _api,
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await t.tap(find.text('Yêu cầu đổi ca').first);
          await t.pump(const Duration(milliseconds: 400));
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
          await t.pump(const Duration(milliseconds: 400));
          await t.tap(find.text('Đồng nghiệp muốn đổi *'));
          await t.pump(const Duration(milliseconds: 400));
          await t.tap(find.text('Lê Văn Cường (NV003)').last);
          await t.pump(const Duration(milliseconds: 400));
          // «Ca muốn nhận»: chọn Ca chiều.
          await t.tap(_dropdown('Ca muốn nhận *'));
          await t.pump(const Duration(milliseconds: 400));
          await t.tap(find.text('Ca chiều').last);
          await t.pump(const Duration(milliseconds: 400));
        },
        marks: [
          GuideMark(1, [_dropdown('Ca của bạn *'), _dateTile('Ngày ca của bạn')]),
          GuideMark(2, [_dropdown('Đồng nghiệp muốn đổi *')]),
          GuideMark(3, [_dropdown('Ca muốn nhận *'), _dateTile('Ngày ca muốn nhận')]),
          GuideMark(4, [GuideMark.button(find.text('Gửi yêu cầu'))]),
        ],
      );
    });

    testWidgets('shift-swap-2$suffix: quản lý duyệt', (t) async {
      await guideShot(
        t,
        name: 'shift-swap-2$suffix',
        screen: const ShiftSwapScreen(),
        api: _api,
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await t.tap(find.textContaining('Chờ QL duyệt (').first);
          await t.pump(const Duration(milliseconds: 600));
        },
        marks: [
          GuideMark(1, [find.textContaining('Chờ QL duyệt (').first]),
          GuideMark(2, [GuideMark.button(find.text('Từ chối')), GuideMark.button(find.text('Duyệt'))]),
        ],
      );
    });
  }
}
