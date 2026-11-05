import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/attendance_punch_slots.dart';
import 'package:zkteco_flutter_client/widgets/attendance/shift_punch_slots_dialog.dart';

const PunchSlotShift _sang = (id: 'sang', name: 'Ca sáng', halves: [(start: 420, end: 660)]);
const PunchSlotShift _chieu = (id: 'chieu', name: 'Ca chiều', halves: [(start: 780, end: 1020)]);
const PunchSlotShift _hc = (
  id: 'hc',
  name: 'Hành chính',
  halves: [(start: 480, end: 720), (start: 780, end: 1020)],
);

void main() {
  group('AttendancePunchSlots', () {
    test('parse bỏ giá trị sai, giữ giá trị đúng', () {
      expect(AttendancePunchSlots.parse(null), isEmpty);
      expect(AttendancePunchSlots.parse('không phải json'), isEmpty);
      expect(
        AttendancePunchSlots.parse('{"a":[3,4],"b":[2,3],"c":[1],"d":[5,2],"e":"x","f":[1,2,3,4]}'),
        {'a': [3, 4], 'f': [1, 2, 3, 4]},
      );
    });

    test('encode rồi parse giữ nguyên', () {
      const v = {'a': [1, 4], 'b': [5, 6]};
      expect(AttendancePunchSlots.parse(AttendancePunchSlots.encode(v)), v);
    });

    test('mặc định: ca nối tiếp mỗi ca một cặp, ca trùng giờ dùng chung', () {
      expect(AttendancePunchSlots.withDefaults([_sang, _hc, _chieu], const {}), {
        'sang': [1, 2],
        'hc': [1, 2, 3, 4],
        'chieu': [3, 4],
      });
    });

    test('mặc định: sáng 1–2, chiều 3–4, đêm 5–6; hành chính vào 1, ra 4; ca trùng giờ không thêm cột', () {
      const PunchSlotShift s = (id: 's', name: 'Sáng', halves: [(start: 360, end: 840)]);
      const PunchSlotShift c = (id: 'c', name: 'Chiều', halves: [(start: 840, end: 1320)]);
      const PunchSlotShift d = (id: 'd', name: 'Đêm', halves: [(start: 1320, end: 1800)]);
      const PunchSlotShift hc = (id: 'hc', name: 'Hành chính', halves: [(start: 480, end: 1020)]);
      const PunchSlotShift lunch = (
        id: 'lunch',
        name: 'Có nghỉ trưa',
        halves: [(start: 480, end: 720), (start: 780, end: 1020)],
      );
      expect(AttendancePunchSlots.autoColumns([s, hc, lunch, c, d]), {
        's': [1, 2],
        'c': [3, 4],
        'd': [5, 6],
        'hc': [1, 4],
        'lunch': [1, 2, 3, 4],
      });
    });

    test('mặc định luôn hợp lệ', () {
      for (final v in AttendancePunchSlots.autoColumns([_sang, _hc, _chieu]).values) {
        expect(AttendancePunchSlots.isValid(v), isTrue);
      }
    });

    test('ca mới chưa thiết lập theo mặc định, ca đã thiết lập giữ nguyên', () {
      expect(AttendancePunchSlots.withDefaults([_sang, _chieu], const {'chieu': [5, 6]}), {
        'sang': [1, 2],
        'chieu': [5, 6],
      });
    });

    test('mẫu ca đổi nghỉ trưa sau khi thiết lập vẫn đủ số lần', () {
      expect(AttendancePunchSlots.withDefaults([_sang], const {'sang': [1, 2, 3, 4]})['sang'], [1, 4]);
      expect(AttendancePunchSlots.withDefaults([_hc], const {'hc': [3, 4]})['hc'], [3, 4, 5, 6]);
    });
  });

  group('ShiftPunchColumns.place', () {
    final a = DateTime(2026, 11, 2, 13), b = DateTime(2026, 11, 2, 17), c = DateTime(2026, 11, 2, 20);

    test('giờ nằm đúng cột, thiếu ra biết ô cặp', () {
      final r = ShiftPunchColumns.place(
        punches: [a],
        ins: [null, a],
        outs: [null, null],
        extra: const [],
        columns: const [(inCol: 0, outCol: 1), (inCol: 2, outCol: 3)],
      );
      expect(r.cols, [null, null, 0, null]);
      expect(r.pairOf, {2: 3, 3: 2});
    });

    test('giờ ngoài ca và giờ trùng ô nối ở cuối, không mất giờ', () {
      final r = ShiftPunchColumns.place(
        punches: [a, b, c],
        ins: [a, b],
        outs: [null, null],
        extra: [c],
        columns: const [(inCol: 0, outCol: 1), (inCol: 0, outCol: 1)],
      );
      expect(r.cols, [0, null, 1, 2]);
    });
  });

  testWidgets('Dialog: giá trị đã lưu, chọn sai bị chặn, Tự xếp theo giờ ca, Lưu trả kết quả', (tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, List<int>>? result;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              result = await showShiftPunchSlotsDialog(ctx, shifts: const [_sang, _chieu], saved: const {
                'sang': [1, 2],
                'chieu': [5, 6],
              });
            },
            child: const Text('mở'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('mở'));
    await tester.pumpAndSettle();
    expect(find.text('Lần 5'), findsOneWidget);
    expect(find.text('Lần 6'), findsOneWidget);

    // Ca sáng: chọn vào Lần 3 khi ra đang Lần 2 → sai, không lưu được.
    await tester.tap(find.text('Lần 1').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lần 3').last);
    await tester.pumpAndSettle();
    expect(find.text('Lần chấm sau phải lớn hơn lần chấm trước'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

    await tester.tap(find.text('Tự xếp theo giờ ca'));
    await tester.pumpAndSettle();
    expect(find.text('Lần chấm sau phải lớn hơn lần chấm trước'), findsNothing);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(result, {'sang': [1, 2], 'chieu': [3, 4]});
  });
}
