import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zkteco_flutter_client/screens/attendance_corrections_screen.dart';
import 'package:zkteco_flutter_client/widgets/attendance_correction_reason_field.dart';

import 'guide_shots/guide_shot_kit.dart';
import 'guide_shots/hrm_extras_common.dart' show extrasSettle;

/// Form «Yêu cầu sửa chấm công» của nhân viên: mỗi lần chấm là một phiếu,
/// sửa/xóa phải gửi giờ đã chấm (oldDate + oldTime) để backend tìm bản ghi gốc.
/// Bộ chọn giờ là kiểu 24 giờ: gõ 08 luôn ra 08:00 kể cả khi mở lúc buổi tối, gõ được 17.

List<Map<String, dynamic>> _sent = [];

final _api = MockClient((req) async {
  if (req.method == 'POST' && req.url.path.endsWith('/api/AttendanceCorrections')) {
    _sent.add(jsonDecode(req.body) as Map<String, dynamic>);
    return http.Response(jsonEncode({'isSuccess': true, 'data': {'id': 'c${_sent.length}', 'status': 0}}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});
  }
  final data = req.url.path.contains('/settings/app/') ? {'value': 'true'} : {'items': []};
  return http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200,
      headers: {'content-type': 'application/json; charset=utf-8'});
});

Future<void> _pickTime(WidgetTester t, String label, String hh, String mm) async {
  await t.tap(find.text(label));
  await t.pumpAndSettle();
  await t.tap(find.byIcon(Icons.keyboard_outlined));
  await t.pumpAndSettle();
  final fields = find.descendant(of: find.byType(TimePickerDialog), matching: find.byType(TextField));
  await t.enterText(fields.at(0), hh);
  await t.enterText(fields.at(1), mm);
  await t.tap(find.descendant(of: find.byType(TimePickerDialog), matching: find.byType(TextButton)).last);
  await t.pumpAndSettle();
}

Future<void> _openForm(WidgetTester t, String actionLabel) async {
  await t.tap(find.text('Yêu cầu mới'));
  await extrasSettle(t);
  if (actionLabel != 'Thêm mới') {
    await t.tap(find.text('Thêm mới').last);
    await t.pumpAndSettle();
    await t.tap(find.text(actionLabel).last);
    await t.pumpAndSettle();
  }
}

Future<void> _submit(WidgetTester t, String reason) async {
  await t.enterText(find.descendant(of: find.byType(AttendanceCorrectionReasonField), matching: find.byType(TextField)).first, reason);
  await t.tap(find.text('Gửi yêu cầu'));
  await extrasSettle(t, 8);
}

void main() {
  setUp(() => _sent = []);

  testWidgets('thêm cả giờ vào lẫn giờ ra → 2 phiếu CheckIn + CheckOut', (t) async {
    await guideShot(t, name: 'form-add', screen: const AttendanceCorrectionsScreen(), api: _api, size: mobileSize, act: (t) async {
      await _openForm(t, 'Thêm mới');
      await _pickTime(t, 'Giờ vào', '08', '05');
      await _pickTime(t, 'Giờ ra', '17', '30');
      await _submit(t, 'Quên chấm công');
    });
    expect(_sent.map((e) => (e['action'], e['newTime'], e['newType'])).toList(), [
      (0, '08:05:00', 'CheckIn'),
      (0, '17:30:00', 'CheckOut'),
    ]);
  });

  testWidgets('sửa → gửi giờ cũ, giờ đúng và loại chấm', (t) async {
    await guideShot(t, name: 'form-edit', screen: const AttendanceCorrectionsScreen(), api: _api, size: mobileSize, act: (t) async {
      await _openForm(t, 'Chỉnh sửa');
      await _pickTime(t, 'Giờ đã chấm cần sửa *', '07', '48');
      await _pickTime(t, 'Giờ đúng *', '09', '02');
      await t.tap(find.text('Vào').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Ra').last);
      await t.pumpAndSettle();
      await _submit(t, 'Máy nhận nhầm loại chấm');
    });
    expect(_sent, hasLength(1));
    expect(_sent.single, containsPair('action', 1));
    expect(_sent.single, containsPair('oldTime', '07:48:00'));
    expect(_sent.single, containsPair('newTime', '09:02:00'));
    expect(_sent.single, containsPair('newType', 'CheckOut'));
    expect(_sent.single['oldDate'], _sent.single['newDate']);
  });

  testWidgets('xóa → chỉ gửi giờ đã chấm cần xóa', (t) async {
    await guideShot(t, name: 'form-delete', screen: const AttendanceCorrectionsScreen(), api: _api, size: mobileSize, act: (t) async {
      await _openForm(t, 'Xóa');
      await _pickTime(t, 'Giờ đã chấm cần xóa *', '11', '01');
      await _submit(t, 'Chấm nhầm');
    });
    expect(_sent, hasLength(1));
    expect(_sent.single, containsPair('action', 2));
    expect(_sent.single, containsPair('oldTime', '11:01:00'));
    expect(_sent.single.containsKey('newTime'), isFalse);
  });

  testWidgets('thiếu giờ → không gửi phiếu', (t) async {
    await guideShot(t, name: 'form-missing', screen: const AttendanceCorrectionsScreen(), api: _api, size: mobileSize, act: (t) async {
      await _openForm(t, 'Thêm mới');
      await _submit(t, 'Quên chấm công');
    });
    expect(_sent, isEmpty);
  });
}
