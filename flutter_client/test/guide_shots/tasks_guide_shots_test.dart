import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/task_management_screen.dart';

import 'guide_shot_kit.dart';
import 'hrm_extras_common.dart';

/// Ảnh cho bước hướng dẫn «Công việc (Tasks)» (id: tasks).

final _now = DateTime.now();
String _at(int days, [int hour = 17]) {
  final d = DateTime(_now.year, _now.month, _now.day + days, hour);
  return '${isoDay(d)}T${hour.toString().padLeft(2, '0')}:00:00';
}

Map<String, dynamic> _task(String id, String code, String title, String status, String priority,
        {required String assignee, required String assigneeId, required int due, int progress = 0, String type = 'Task'}) =>
    {
      'id': id, 'taskCode': code, 'title': title, 'taskType': type, 'priority': priority, 'status': status,
      'progress': progress, 'storeId': 's1', 'assignedById': 'e1', 'assignedByName': 'Nguyễn Văn Hùng',
      'assigneeId': assigneeId, 'assigneeName': assignee, 'startDate': _at(due - 2, 8), 'dueDate': _at(due),
      'commentCount': 0, 'createdAt': '${_at(-3, 8)}Z',
      'assignees': [
        {'employeeId': assigneeId, 'employeeName': assignee, 'status': status, 'progress': progress},
      ],
    };

final _tasks = [
  _task('t1', 'CV-0012', 'Vệ sinh máy lạnh khu sân vườn', 'InProgress', 'High',
      assignee: 'Võ Minh Tuấn', assigneeId: 'e5', due: 1, progress: 60, type: 'Maintenance'),
  _task('t2', 'CV-0013', 'Kiểm kê kho nguyên liệu cuối tuần', 'Todo', 'Medium',
      assignee: 'Lê Văn Minh', assigneeId: 'e3', due: 3),
  _task('t3', 'CV-0014', 'Đặt in menu mới mùa thu', 'InReview', 'Medium',
      assignee: 'Trần Thị Lan', assigneeId: 'e2', due: 2, progress: 90),
  _task('t4', 'CV-0015', 'Đối chiếu sổ quỹ tháng 10', 'Todo', 'Urgent',
      assignee: 'Hồ Ngọc Ánh', assigneeId: 'e8', due: 0),
  _task('t5', 'CV-0010', 'Thay bóng đèn bảng hiệu', 'Completed', 'Low',
      assignee: 'Võ Minh Tuấn', assigneeId: 'e5', due: -2, progress: 100),
  _task('t6', 'CV-0011', 'Huấn luyện nhân viên mới pha chế', 'InProgress', 'Medium',
      assignee: 'Trần Thị Lan', assigneeId: 'e2', due: 4, progress: 30, type: 'Meeting'),
];

List<Map<String, dynamic>> _col(String status) => [for (final t in _tasks) if (t['status'] == status) t];

final _api = guideApi({
  '/api/Tasks/statistics': {
    'totalTasks': 6, 'todoCount': 2, 'assignedCount': 0, 'inProgressCount': 2, 'inReviewCount': 1,
    'completedCount': 1, 'cancelledCount': 0, 'onHoldCount': 0, 'overdueCount': 0,
    'completionRate': 16.7, 'averageProgress': 47,
  },
  '/api/Tasks/kanban': {
    'columns': [
      for (final s in ['Todo', 'InProgress', 'InReview', 'Completed'])
        {'status': s, 'taskCount': _col(s).length, 'tasks': _col(s)},
    ],
  },
  '/api/Tasks/my': {'items': _tasks, 'totalCount': _tasks.length},
  '/api/Tasks': {'items': _tasks, 'totalCount': _tasks.length},
  '/api/employees/me': extrasEmployees.first,
  '/api/branches/select': [],
  '/api/employees': {'items': extrasEmployees, 'totalCount': extrasEmployees.length},
});

const _crumbs = ['Công việc'];

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('tasks-1$suffix: danh sách công việc', (t) async {
      await guideShot(
        t,
        name: 'tasks-1$suffix',
        screen: withExtrasPackage(const TaskManagementScreen()),
        api: _api,
        crumbs: _crumbs,
        size: size,
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Tạo công việc'))]),
          GuideMark(2, [find.text('Của tôi').first, find.text('Trạng thái').first, find.text('Ưu tiên').first]),
        ],
      );
    });

    testWidgets('tasks-2$suffix: tạo công việc', (t) async {
      await guideShot(
        t,
        name: 'tasks-2$suffix',
        screen: withExtrasPackage(const TaskManagementScreen()),
        api: _api,
        crumbs: [..._crumbs, 'Tạo công việc'],
        size: size,
        act: (t) async {
          await t.tap(find.text('Tạo công việc').first);
          await extrasSettle(t);
          await t.enterText(fieldLabeled('Tiêu đề *'), 'Lau kính mặt tiền trước giờ mở cửa');
          await t.enterText(fieldLabeled('Mô tả'), 'Lau cả kính cửa ra vào và bảng hiệu, xong chụp ảnh gửi quản lý.');
          await t.pump();
        },
        marks: [
          GuideMark(1, [fieldLabeled('Tiêu đề *')]),
          GuideMark(2, [dropdownLabeled('Loại'), dropdownLabeled('Ưu tiên')]),
          GuideMark(3, [decoratorLabeled('Giao cho (Chọn nhiều người)')]),
          GuideMark(4, [decoratorLabeled('Bắt đầu (ngày giờ)'), decoratorLabeled('Hết hạn (ngày giờ)')]),
        ],
      );
    });

    testWidgets('tasks-3$suffix: Kanban theo trạng thái', (t) async {
      await guideShot(
        t,
        name: 'tasks-3$suffix',
        screen: withExtrasPackage(const TaskManagementScreen()),
        api: _api,
        crumbs: [..._crumbs, 'Kanban'],
        size: size,
        act: (t) async {
          await t.tap(find.text('Kanban').first);
          await extrasSettle(t, 8);
        },
        marks: [
          GuideMark(1, [find.text('Đang làm').first], pad: 10),
          GuideMark(2, [GuideMark.button(find.text('Vệ sinh máy lạnh khu sân vườn').first)]),
        ],
      );
    });
  }
}
