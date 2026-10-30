import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zkteco_flutter_client/features/leave/leave_catalog.dart';
import 'package:zkteco_flutter_client/screens/leave_screen.dart';

import 'guide_shot_kit.dart';

/// Ảnh cho bước hướng dẫn «Nghỉ phép» (id: leave).

final _employees = [
  {'id': 'e1', 'applicationUserId': 'u1', 'employeeCode': 'NV001', 'firstName': 'An', 'lastName': 'Nguyễn Văn', 'fullName': 'Nguyễn Văn An', 'departmentName': 'Bếp'},
  {'id': 'e2', 'applicationUserId': 'u2', 'employeeCode': 'NV002', 'firstName': 'Bình', 'lastName': 'Trần Thị', 'fullName': 'Trần Thị Bình', 'departmentName': 'Thu ngân'},
  {'id': 'e3', 'applicationUserId': 'u3', 'employeeCode': 'NV003', 'firstName': 'Cường', 'lastName': 'Lê Văn', 'fullName': 'Lê Văn Cường', 'departmentName': 'Phục vụ'},
  {'id': 'e4', 'applicationUserId': 'u4', 'employeeCode': 'NV004', 'firstName': 'Dũng', 'lastName': 'Phạm Minh', 'fullName': 'Phạm Minh Dũng', 'departmentName': 'Phục vụ'},
];

Map<String, Object?> _leave(String id, String emp, String empId, int type, String from, String to, int status,
        {String reason = '', String? rejection}) =>
    {
      'id': id,
      'employeeName': emp,
      'employeeId': empId,
      'type': type,
      'startDate': '${from}T00:00:00',
      'endDate': '${to}T00:00:00',
      'status': status,
      'reason': reason,
      'createdAt': '2026-10-28T08:15:00',
      'shiftNames': ['Ca sáng'],
      'totalApprovalLevels': 1,
      'currentApprovalStep': status == 0 ? 1 : 0,
      if (rejection != null) 'rejectionReason': rejection,
    };

final _pending = [
  _leave('7c1e2a01-5b3d-4e8f-9a21-0d6c4b8e1f31', 'Trần Thị Bình', 'e2', 0, '2026-11-03', '2026-11-04', 0, reason: 'Về quê dự đám cưới em gái'),
  _leave('7c1e2a02-5b3d-4e8f-9a21-0d6c4b8e1f32', 'Lê Văn Cường', 'e3', 4, '2026-11-02', '2026-11-02', 0, reason: 'Sốt, có giấy khám bệnh'),
];
final _all = [
  ..._pending,
  _leave('7c1e2a03-5b3d-4e8f-9a21-0d6c4b8e1f33', 'Phạm Minh Dũng', 'e4', 0, '2026-10-20', '2026-10-20', 1, reason: 'Việc gia đình'),
  _leave('7c1e2a04-5b3d-4e8f-9a21-0d6c4b8e1f34', 'Nguyễn Văn An', 'e1', 2, '2026-10-12', '2026-10-12', 2, reason: 'Việc riêng', rejection: 'Trùng lịch kiểm kho'),
];

http.Response _ok(Object? data) => http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

MockClient _api() => MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/api/Leaves/pending')) return _ok({'items': req.url.queryParameters['page'] == '1' || !req.url.queryParameters.containsKey('page') ? _pending : []});
      if (p.endsWith('/api/Leaves/my-leaves')) return _ok([_all.last]);
      if (p.endsWith('/api/Leaves')) return _ok({'items': req.url.queryParameters['page'] == '1' || !req.url.queryParameters.containsKey('page') ? _all : []});
      if (p.contains('annual-balance')) return _ok({'remainingDays': 9, 'totalDays': 12, 'usedDays': 3, 'eligible': true});
      if (p.contains('count-days')) return _ok({'days': 1});
      if (p.endsWith('/api/employees')) return _ok({'items': _employees, 'totalCount': _employees.length});
      if (p.endsWith('/api/shifts/templates')) {
        return _ok([
          {'id': 's1', 'name': 'Ca sáng', 'startTime': '06:00:00', 'endTime': '14:00:00', 'isActive': true},
          {'id': 's2', 'name': 'Ca chiều', 'startTime': '14:00:00', 'endTime': '22:00:00', 'isActive': true},
        ]);
      }
      return _ok([]);
    });

const _crumbs = ['Chấm công', 'Nghỉ phép'];

void _dump(String tag) {
  if (Platform.environment['GUIDE_DUMP'] != '1') return;
  // ignore: avoid_print
  print('DUMP $tag ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().take(90).toList()}');
}

Future<void> _openForm(WidgetTester t) async {
  await t.tap(find.text('Tạo đơn').first);
  await t.pump(const Duration(milliseconds: 500));
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
  await t.pump(const Duration(milliseconds: 500));
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 100));

  }
}

/// Chữ [label] trên thanh tab (bỏ qua thẻ thống kê cùng chữ ở khung Tổng quan).
Finder _tab(String label) => find.byElementPredicate((e) {
      final w = e.widget;
      if (w is! Text || w.data != label) return false;
      var inStat = false;
      e.visitAncestorElements((a) {
        if (a.widget.runtimeType.toString() == 'HrmStatSummaryCard') inStat = true;
        return !inStat;
      });
      return !inStat;
    });

Finder _card(String text) => GuideMark.button(find.text(text));

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('leave-1$suffix: chọn nhóm chế độ nghỉ', (t) async {
      await guideShot(
        t,
        name: 'leave-1$suffix',
        screen: const LeaveScreen(),
        api: _api(),
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          _dump('list');
          await _openForm(t);
          _dump('form');
        },
        marks: [
          GuideMark(1, [
            _card(LeaveCatalog.categoryTitle(LeaveLegalCategory.employerPaid)),
            _card(LeaveCatalog.categoryTitle(LeaveLegalCategory.socialInsurance)),
          ]),
        ],
      );
    });

    testWidgets('leave-2$suffix: thời gian, lý do, gửi đơn', (t) async {
      await guideShot(
        t,
        name: 'leave-2$suffix',
        screen: const LeaveScreen(),
        api: _api(),
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await _openForm(t);
          await t.tap(find.text(LeaveCatalog.categoryTitle(LeaveLegalCategory.employerPaid)));
          await _settle(t);
          // Thẻ «Phép năm» ở bước 2 (chữ này cũng có ở thẻ thống kê phía sau hộp thoại).
          await t.tap(find.ancestor(of: find.text('100% lương HĐLĐ · trừ quỹ phép'), matching: find.byType(InkWell)).first);
          await _settle(t);
          _dump('details');
        },
        marks: [
          GuideMark(1, [find.textContaining('Phép năm còn'), find.textContaining('Đơn này cần')]),
          GuideMark(2, [find.text('Từ ngày'), find.text('Đến ngày'), find.text('30/10/2026').last], pad: 10),
          GuideMark(3, [GuideMark.button(find.text('Ca sáng').last), GuideMark.button(find.text('Ca chiều').last)]),
          GuideMark(4, [GuideMark.button(find.text('Gửi đơn'))]),
        ],
      );
    });

    testWidgets('leave-3$suffix: quản lý duyệt đơn', (t) async {
      await guideShot(
        t,
        name: 'leave-3$suffix',
        screen: const LeaveScreen(),
        api: _api(),
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await t.tap(_tab('Chờ duyệt').first);
          await _settle(t);
          _dump('pending');
        },
        marks: [
          GuideMark(1, [_tab('Chờ duyệt').first]),
          // Điện thoại: thẻ đơn không có nút — chạm thẻ mở chi tiết rồi mới Duyệt / Từ chối.
          if (size.width < 600)
            GuideMark(2, [GuideMark.button(find.text('Trần Thị Bình').last)])
          else
            GuideMark(2, [GuideMark.button(_tab('Duyệt').first), GuideMark.button(_tab('Từ chối').first)]),
        ],
      );
    });
    testWidgets('leave-3$suffix: quản lý duyệt đơn', (t) async {
      await guideShot(
        t,
        name: 'leave-3$suffix',
        screen: const LeaveScreen(),
        api: _api(),
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await t.tap(_tab('Chờ duyệt').first);
          await _settle(t);
          _dump('pending');
        },
        marks: [
          GuideMark(1, [_tab('Chờ duyệt').first]),
          // Điện thoại: thẻ đơn không có nút — chạm thẻ mở chi tiết rồi mới Duyệt / Từ chối.
          if (size.width < 600)
            GuideMark(2, [GuideMark.button(find.text('Trần Thị Bình').last)])
          else
            GuideMark(2, [GuideMark.button(_tab('Duyệt').first), GuideMark.button(_tab('Từ chối').first)]),
        ],
      );
    });

  }
}
