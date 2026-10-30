import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/feedback_screen.dart';

import 'guide_shot_kit.dart';
import 'hrm_extras_common.dart';

/// Ảnh cho bước hướng dẫn «Kiến nghị / Khiếu nại» (id: feedback).

String _at(Duration ago) => DateTime.now().toUtc().subtract(ago).toIso8601String();
String _due(Duration fromNow) => DateTime.now().toUtc().add(fromNow).toIso8601String();

Map<String, Object?> _fb(String id, String code, String category, String topic, String title, String status, int priority,
        {String? sender, String? dept, bool anon = false, Duration created = const Duration(hours: 5), Duration? due,
        String? assignee, int replies = 0}) =>
    {
      'id': id, 'code': code, 'category': category, 'topic': topic, 'title': title, 'status': status, 'priority': priority,
      'senderName': anon ? null : sender, 'senderDepartment': anon ? null : dept, 'isAnonymous': anon,
      'recipientName': 'Hòm thư chung', 'assigneeName': assignee, 'replyCount': replies,
      'createdAt': _at(created), 'updatedAt': _at(created ~/ 2),
      'dueAt': due == null ? null : (due.isNegative ? _at(-due) : _due(due)), 'overdue': due != null && due.isNegative,
      'content': title,
    };

final _inbox = [
  _fb('f1', 'PH-0031', 'Complaint', 'Ca làm / chấm công', 'Bị tính đi trễ dù đã chấm đúng giờ ngày 27/10', 'Pending', 2,
      sender: 'Trần Thị Lan', dept: 'Phục vụ', created: const Duration(hours: 52), due: const Duration(hours: -4)),
  _fb('f2', 'PH-0030', 'Suggestion', 'Cơ sở vật chất', 'Đề xuất lắp thêm quạt ở khu bếp', 'InProgress', 1,
      sender: 'Lê Văn Minh', dept: 'Bếp', created: const Duration(hours: 30), due: const Duration(hours: 42),
      assignee: 'Nguyễn Văn Hùng', replies: 2),
  _fb('f3', 'PH-0029', 'Complaint', 'Ứng xử / quan hệ', 'Khách hàng lớn tiếng với nhân viên ca tối', 'Pending', 3, anon: true,
      created: const Duration(hours: 3), due: const Duration(hours: 21)),
  _fb('f4', 'PH-0028', 'General', 'Chế độ phúc lợi', 'Hỏi về chế độ thưởng Tết 2027', 'InProgress', 0,
      sender: 'Phạm Thị Hoa', dept: 'Thu ngân', created: const Duration(days: 3), due: const Duration(days: 4),
      assignee: 'Hồ Ngọc Ánh', replies: 1),
];

final _api = guideApi({
  '/api/feedback/managers': [
    {'employeeId': 'e1', 'name': 'Nguyễn Văn Hùng', 'position': 'Chủ cửa hàng'},
    {'employeeId': 'e8', 'name': 'Hồ Ngọc Ánh', 'position': 'Kế toán viên'},
  ],
  '/api/feedback/my': [
    _fb('m1', 'PH-0027', 'Suggestion', 'Ca làm / chấm công', 'Đổi giờ ca chiều sang 14:30', 'Resolved', 1,
        sender: 'Nguyễn Văn Hùng', dept: 'Ban quản lý', created: const Duration(days: 6)),
  ],
  '/api/feedback/stats': {
    'totals': {
      'total': 28, 'complaints': 9, 'anonymous': 6, 'open': 4, 'pending': 2, 'overdue': 1, 'onTimePct': 89,
      'avgFirstResponseHours': 5.5, 'avgResolveHours': 31, 'avgRating': 4.4, 'rated': 17, 'reopened': 1,
    },
    'byTopic': [
      {'name': 'Ca làm / chấm công', 'count': 9, 'complaints': 4},
      {'name': 'Lương thưởng', 'count': 6, 'complaints': 3},
      {'name': 'Cơ sở vật chất', 'count': 5, 'complaints': 0},
      {'name': 'Môi trường làm việc', 'count': 4, 'complaints': 1},
      {'name': 'Ứng xử / quan hệ', 'count': 4, 'complaints': 1},
    ],
    'byDepartment': [
      {'name': 'Phục vụ', 'count': 11, 'complaints': 5},
      {'name': 'Bếp', 'count': 8, 'complaints': 2},
      {'name': 'Thu ngân', 'count': 6, 'complaints': 2},
      {'name': 'Kế toán', 'count': 3, 'complaints': 0},
    ],
    'byMonth': [
      {'month': 'T6', 'received': 3, 'resolved': 3, 'complaints': 1},
      {'month': 'T7', 'received': 5, 'resolved': 4, 'complaints': 2},
      {'month': 'T8', 'received': 4, 'resolved': 5, 'complaints': 1},
      {'month': 'T9', 'received': 7, 'resolved': 6, 'complaints': 2},
      {'month': 'T10', 'received': 9, 'resolved': 6, 'complaints': 3},
    ],
  },
  '/api/feedback': {
    'items': _inbox,
    'total': _inbox.length,
    'counts': {'open': 4, 'pending': 2, 'overdue': 1, 'assignedToMe': 1, 'resolved': 24, 'all': 28},
  },
});

const _crumbs = ['Truyền thông', 'Kiến nghị / Khiếu nại'];

/// Cả chip lọc / chọn có chữ [label].
Finder _chip(String label) => find
    .ancestor(of: find.textContaining(label).last, matching: find.byWidgetPredicate((w) => w is ChoiceChip || w is FilterChip))
    .first;

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('feedback-1$suffix: gửi kiến nghị / khiếu nại', (t) async {
      await guideShot(
        t,
        name: 'feedback-1$suffix',
        screen: const FeedbackScreen(),
        api: _api,
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await t.tap(find.text('Gửi kiến nghị').first);
          await extrasSettle(t);
        },
        marks: [
          GuideMark(1, [cardOf(find.text('Khiếu nại').last), cardOf(find.text('Góp ý chung').last)], pad: 4),
          GuideMark(2, [_chip('Lương thưởng'), _chip('Ca làm / chấm công'), _chip('An toàn lao động'), _chip('Khác')], pad: 4),
          GuideMark(3, [fieldLabeled('Tiêu đề *'), fieldLabeled('Nội dung *')], pad: 4),
        ],
      );
    });

    testWidgets('feedback-2$suffix: cần xử lý, hạn và quá hạn', (t) async {
      await guideShot(
        t,
        name: 'feedback-2$suffix',
        screen: const FeedbackScreen(),
        api: _api,
        crumbs: _crumbs,
        size: size,
        marks: [
          GuideMark(1, [_chip('Đang mở'), _chip('Giao cho tôi')], pad: 4),
          GuideMark(2, [cardOf(find.textContaining('Bị tính đi trễ'))]),
        ],
      );
    });

    testWidgets('feedback-3$suffix: báo cáo xử lý', (t) async {
      await guideShot(
        t,
        name: 'feedback-3$suffix',
        screen: const FeedbackScreen(),
        api: _api,
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await t.tap(find.text('Báo cáo'));
          await extrasSettle(t);
        },
        marks: [
          GuideMark(1, [cardOf(find.text('Đúng hạn').first), cardOf(find.text('Giải quyết TB').first)], pad: 4),
          GuideMark(2, [cardOf(find.text('Hài lòng').first)], pad: 4),
        ],
      );
    });
  }
}
