import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/staff/staff_shell.dart';

import 'guide_shot_kit.dart';

// SBOX Nhân Viên: thanh dưới cùng cỡ SBOX HRM (trước biểu tượng 24, chữ 12, đệm 6 → thanh quá cao).
final _api = guideApi({
  '/api/dashboard/employee': {
    'todayShift': {'id': 's1', 'startTime': '2026-11-11T08:00:00', 'endTime': '2026-11-11T17:00:00', 'status': 1},
    'currentAttendance': {'status': 'checked-in', 'checkInTime': '2026-11-11T08:09:00', 'isLate': true, 'lateMinutes': 9},
    'attendanceStats': {'presentDays': 13, 'lateCheckIns': 1, 'earlyCheckOuts': 2},
  },
});

void main() {
  testWidgets('staff-shell-nav: thanh dưới gọn', (t) async {
    await guideShot(t, name: 'staff-shell-nav', screen: const StaffShell(), api: _api, size: mobileSize,
        act: (t) async {
      final label = find.text('Trang chủ').last;
      final bar = t.getSize(find.ancestor(of: label, matching: find.byType(Material)).first);
      expect(bar.height, lessThanOrEqualTo(56));
    });
    await t.pump(const Duration(minutes: 1));
  });
}
