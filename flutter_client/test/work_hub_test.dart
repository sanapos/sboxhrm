import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/models/task.dart';
import 'package:zkteco_flutter_client/models/task_v2.dart';
import 'package:zkteco_flutter_client/providers/theme_provider.dart';
import 'package:zkteco_flutter_client/screens/work/work_hub_screen.dart';
import 'package:zkteco_flutter_client/screens/work/work_projects.dart';
import 'package:zkteco_flutter_client/screens/work/work_task_detail.dart';

/// Công việc v2 với dữ liệu mẫu (ngành nội thất). Đặt SBOX_SHOT_DIR để lưu ảnh duyệt giao diện.
Future<void> _loadFonts() async {
  final fl = FontLoader('BeVietnamPro');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    fl.addFont(Future.value(ByteData.view(File('assets/fonts/BeVietnamPro-$f.ttf').readAsBytesSync().buffer)));
  }
  await fl.load();
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)))).load();
    }
  }
}

final _now = DateTime.now();
String _at(int days, [int hour = 17]) => DateTime(_now.year, _now.month, _now.day + days, hour).toIso8601String();

const _stages = [
  {'key': 'survey', 'name': 'Khảo sát', 'color': '#64748B'},
  {'key': 'design', 'name': 'Thiết kế & báo giá', 'color': '#7C3AED'},
  {'key': 'production', 'name': 'Sản xuất / đặt hàng', 'color': '#0891B2'},
  {'key': 'construction', 'name': 'Thi công', 'color': '#158DC0'},
  {'key': 'handover', 'name': 'Nghiệm thu & bàn giao', 'color': '#16A34A', 'done': true},
];

final _project = {
  'id': 'p1', 'code': 'DA-0001', 'name': 'Thi công nhà chị Lan – Q7', 'industryKey': 'interior', 'color': '#B45309',
  'status': 0, 'customerName': 'Chị Lan', 'customerPhone': '0903xxx', 'address': '12 Nguyễn Lương Bằng, Q7',
  'ownerName': 'Trần Quân', 'dueDate': _at(20), 'stages': _stages, 'taskCount': 9, 'doneCount': 3, 'inProgressCount': 3,
  'overdueCount': 1, 'progress': 62, 'stageCounts': {'survey': 1, 'construction': 4},
};
final _project2 = {
  'id': 'p2', 'code': 'DA-0002', 'name': 'Sửa bếp anh Minh', 'industryKey': 'interior', 'color': '#0891B2', 'status': 0,
  'stages': _stages, 'taskCount': 4, 'doneCount': 1, 'overdueCount': 0, 'progress': 35,
};

Map<String, dynamic> _task(String id, String title, int status, String stage,
    {int progress = 0, int due = 3, String who = 'Trần Quân', String? checklist, int type = 8, int priority = 1}) => {
      'id': id, 'taskCode': 'TASK-20260927-00$id', 'title': title, 'status': status, 'progress': progress,
      'taskType': type, 'priority': priority, 'storeId': 's', 'assignedById': 'u', 'assigneeId': 'e1', 'assigneeName': who,
      'dueDate': _at(due), 'startDate': _at(due - 3, 8), 'createdAt': _at(-5), 'projectId': 'p1', 'projectName': _project['name'],
      'projectColor': '#B45309', 'stageKey': stage, 'progressMode': 1, 'commentCount': status == 1 ? 2 : 0,
      'checklist': checklist ??
          jsonEncode([
            {'id': 'c1', 'text': 'Kiểm hàng tủ', 'done': progress > 0, 'doneBy': 'Trần Quân', 'doneAt': _at(-1, 8)},
            {'id': 'c2', 'text': 'Lắp khung, thùng tủ', 'done': progress > 40, 'requirePhoto': true},
            {'id': 'c3', 'text': 'Lắp cánh, ray, bản lề', 'requirePhoto': true},
            {'id': 'c4', 'text': 'Vệ sinh, bàn giao'},
          ]),
      'assignees': [
        {'id': 'a', 'taskId': id, 'employeeId': 'e1', 'employeeName': who, 'assignedAt': _at(-5)},
        if (id == '3') {'id': 'b', 'taskId': id, 'employeeId': 'e2', 'employeeName': 'Lê Tú', 'assignedAt': _at(-5)},
      ],
    };

final _tasks = [
  _task('1', 'Khảo sát, đo đạc hiện trạng', 3, 'handover', progress: 100, due: -6),
  _task('2', 'Thiết kế 3D phòng khách', 1, 'design', progress: 60, due: 2, who: 'Phạm Hà', type: 0),
  _task('3', 'Lắp tủ bếp', 1, 'construction', progress: 50, due: -1, priority: 2),
  _task('4', 'Sơn tường phòng ngủ', 0, 'construction', due: 0, who: 'Lê Tú'),
  _task('5', 'Đặt ván, phụ kiện tủ áo', 6, 'production', due: 4, who: 'Nguyễn Minh', type: 13),
  _task('6', 'Nghiệm thu hệ thống điện', 2, 'construction', progress: 100, due: 1, type: 9),
  _task('7', 'Báo cáo công trường cuối ngày', 0, 'construction', due: 0, type: 6),
];

final _insights = {
  'total': 42, 'open': 18, 'inProgress': 7, 'pendingAcceptance': 3, 'inReview': 2, 'overdue': 3, 'dueToday': 4,
  'completedInRange': 24, 'completedOnTime': 21, 'onTimeRate': 87.5, 'avgCycleHours': 30.5, 'completedPrevRange': 19,
  'activeProjects': 2, 'byStatus': {'Todo': 6, 'InProgress': 7, 'Assigned': 3, 'InReview': 2},
  'byDay': [
    for (var i = 13; i >= 0; i--)
      {'date': _at(-i, 0), 'created': 2 + (i * 7) % 4, 'completed': 1 + (i * 5) % 4, 'completedLate': i % 5 == 0 ? 1 : 0},
  ],
};

final _workload = [
  {'employeeId': 'e1', 'employeeName': 'Trần Quân', 'open': 7, 'inProgress': 3, 'overdue': 2, 'dueSoon': 2, 'completedInRange': 11, 'completedOnTime': 9, 'onTimeRate': 81.8, 'openEstimatedHours': 32},
  {'employeeId': 'e2', 'employeeName': 'Lê Tú', 'open': 5, 'inProgress': 2, 'overdue': 1, 'dueSoon': 1, 'completedInRange': 8, 'completedOnTime': 8, 'onTimeRate': 100, 'openEstimatedHours': 20},
  {'employeeId': 'e3', 'employeeName': 'Phạm Hà', 'open': 4, 'inProgress': 1, 'overdue': 0, 'dueSoon': 1, 'completedInRange': 5, 'completedOnTime': 4, 'onTimeRate': 80, 'openEstimatedHours': 18},
  {'employeeId': 'e4', 'employeeName': 'Nguyễn Minh', 'open': 2, 'inProgress': 1, 'overdue': 0, 'dueSoon': 0, 'completedInRange': 3, 'completedOnTime': 3, 'onTimeRate': 100, 'openEstimatedHours': 6},
];

http.Response _ok(Object data) =>
    http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

final _client = MockClient((req) async {
  final p = req.url.path;
  if (p.endsWith('/api/task-projects/industry-packs')) {
    return _ok([
      {'key': 'interior', 'name': 'Nội thất / Thi công', 'description': 'Khảo sát → thiết kế → thi công → nghiệm thu.', 'projectLabel': 'Công trình', 'color': '#B45309', 'stages': _stages, 'installedTemplates': 7,
        'templates': [{'name': 'Thi công lắp đặt', 'taskType': 8, 'stageKey': 'construction', 'checklist': ['Che chắn', 'Lắp khung'], 'photoItems': 1}]},
      {'key': 'spa', 'name': 'Spa / Salon / Thẩm mỹ', 'description': 'Mở/đóng ca, tiệt trùng, chăm sóc khách.', 'projectLabel': 'Liệu trình', 'color': '#DB2777', 'stages': _stages.take(3).toList(), 'installedTemplates': 0,
        'templates': [{'name': 'Mở ca', 'taskType': 6, 'checklist': ['Bật đèn'], 'recurrenceType': 1, 'recurrenceTime': '08:00'}]},
      {'key': 'fnb', 'name': 'Nhà hàng / Cafe', 'description': 'Checklist mở/đóng cửa, nhận hàng, ATTP.', 'projectLabel': 'Sự kiện', 'color': '#EA580C', 'stages': _stages.take(4).toList(), 'installedTemplates': 0, 'templates': []},
    ]);
  }
  if (RegExp(r'/api/task-projects/p\d$').hasMatch(p)) return _ok(p.endsWith('p1') ? _project : _project2);
  if (p.endsWith('/api/task-projects')) return _ok([_project, _project2]);
  if (p.endsWith('/api/Tasks/insights')) return _ok(_insights);
  if (p.endsWith('/api/Tasks/workload')) return _ok(_workload);
  if (p.endsWith('/api/Tasks/templates')) return _ok([]);
  if (p.endsWith('/api/Tasks/timeline')) {
    return _ok([
      for (final t in _tasks)
        {...t, 'startDate': t['startDate'], 'dueDate': t['dueDate'], 'blockedBy': t['id'] == '4' ? ['3'] : []},
    ]);
  }
  final one = RegExp(r'/api/Tasks/(\d+)$').firstMatch(p);
  if (one != null) {
    final t = _tasks.firstWhere((x) => x['id'] == one.group(1));
    return _ok({
      ...t,
      'description': 'Lắp tủ bếp gỗ An Cường theo bản vẽ đã duyệt. Kiểm tra cao độ trước khi khoan.',
      'location': '12 Nguyễn Lương Bằng, Q7',
      'estimatedHours': 16,
      'comments': [
        {'id': 'm1', 'taskId': t['id'], 'userId': 'u', 'userName': 'Trần Quân', 'content': 'Thiếu 2 bản lề giảm chấn, chiều bổ sung.', 'createdAt': _at(0, 10), 'commentType': 0},
      ],
    });
  }
  if (RegExp(r'/api/Tasks/\d+/history$').hasMatch(p)) return _ok([]);
  if (p.endsWith('/api/Tasks')) return _ok({'items': _tasks, 'totalCount': _tasks.length});
  if (p.contains('/api/Employees')) return _ok([]);
  return http.Response(jsonEncode({'isSuccess': false, 'message': 'not mocked $p'}), 200);
});

Future<void> _shot(WidgetTester tester, GlobalKey key, String name, double ratio) async {
  final dir = Platform.environment['SBOX_SHOT_DIR'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: ratio);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<void> _pump(WidgetTester tester, Widget home, Size size, String name, {bool tall = true}) async {
  final key = GlobalKey();
  Widget app(Size s) => RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeProvider().lightTheme,
          home: MediaQuery(data: MediaQueryData(size: s), child: Scaffold(body: home)),
        ),
      );
  Future<void> setSize(Size s) async {
    await tester.binding.setSurfaceSize(s);
    tester.view.physicalSize = s;
    tester.view.devicePixelRatio = 1;
  }

  await http.runWithClient(() async {
    await setSize(size);
    await tester.pumpWidget(app(size));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    if (tall) {
      var extent = 0.0;
      for (final e in find.byType(Scrollable).evaluate()) {
        final st = (e as StatefulElement).state as ScrollableState;
        if (st.position.axis == Axis.vertical && st.position.maxScrollExtent > extent) extent = st.position.maxScrollExtent;
      }
      if (extent > 0) {
        final t = Size(size.width, size.height + extent);
        await setSize(t);
        await tester.pumpWidget(app(t));
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
    }
    expect(tester.takeException(), isNull);
  }, () => _client);
  await _shot(tester, key, name, size.width < 600 ? 2 : 1.25);
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

const _manager = WorkViewer(isManager: true, employeeId: 'e1');
const _staff = WorkViewer(isManager: false, employeeId: 'e1');
const _desk = Size(1440, 900);
const _phone = Size(390, 844);

void main() {
  setUpAll(_loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Checklist: đọc mảng chuỗi cũ và định dạng mới', () {
    final old = TaskChecklistItemV2.parse('["A","B"]');
    expect(old.map((e) => e.text), ['A', 'B']);
    final v2 = TaskChecklistItemV2.parse(jsonEncode([
      {'id': 'x', 'text': 'Chụp ảnh', 'done': true, 'requirePhoto': true, 'photoUrl': '/u/a.jpg'},
    ]));
    expect(v2.single.requirePhoto, isTrue);
    expect(v2.single.done, isTrue);
    expect(recurrenceLabel(2, '1,3,5', '08:00'), 'Hằng tuần (T2, T4, T6) lúc 08:00');
    expect(parseTaskType(13), TaskType.procurement);
  });

  testWidgets('Tổng quan quản lý — máy tính', (t) async {
    await _pump(t, const WorkHubScreen(debugViewer: _manager, initialView: WorkView.overview), _desk, 'work_overview_desktop');
    expect(find.text('Việc mới và việc hoàn thành'), findsOneWidget);
  });

  testWidgets('Tổng quan quản lý — điện thoại', (t) async {
    await _pump(t, const WorkHubScreen(debugViewer: _manager, initialView: WorkView.overview), _phone, 'work_overview_mobile');
    expect(find.text('Cần chú ý'), findsOneWidget);
  });

  testWidgets('Bảng theo giai đoạn dự án — máy tính', (t) async {
    // Chọn dự án → cột = giai đoạn ngành.
    await _pump(t, const WorkHubScreen(debugViewer: _manager, initialView: WorkView.board, initialProjectId: 'p1'), _desk,
        'work_board_desktop', tall: false);
    expect(find.text('Thiết kế & báo giá'), findsWidgets);
    expect(find.text('Lắp tủ bếp'), findsWidgets);
  });

  testWidgets('Danh sách — điện thoại', (t) async {
    await _pump(t, const WorkHubScreen(debugViewer: _manager, initialView: WorkView.list), _phone, 'work_list_mobile');
    expect(find.text('Lắp tủ bếp'), findsWidgets);
  });

  testWidgets('Tiến độ Gantt — máy tính', (t) async {
    await _pump(t, const WorkHubScreen(debugViewer: _manager, initialView: WorkView.timeline), _desk, 'work_gantt_desktop', tall: false);
    expect(find.text('Hôm nay'), findsWidgets);
  });

  testWidgets('Nhân sự — máy tính', (t) async {
    await _pump(t, const WorkHubScreen(debugViewer: _manager, initialView: WorkView.people), _desk, 'work_people_desktop');
    expect(find.text('Việc đang mở theo người'), findsOneWidget);
  });

  testWidgets('Hôm nay của nhân viên — điện thoại', (t) async {
    await _pump(t, const WorkHubScreen(debugViewer: _staff), _phone, 'work_today_mobile');
    expect(find.text('Quá hạn'), findsWidgets);
    expect(find.text('Tổng quan'), findsNothing);
  });

  testWidgets('Chi tiết việc — điện thoại', (t) async {
    await _pump(t, const WorkTaskDetailPage(taskId: '3', viewer: _staff), _phone, 'work_detail_mobile');
    expect(find.text('Báo hoàn thành'), findsOneWidget);
    expect(find.text('Cần chụp ảnh khi hoàn thành'), findsOneWidget);
  });

  testWidgets('Gói ngành — máy tính', (t) async {
    await _pump(t, const WorkPacksPage(people: []), _desk, 'work_packs_desktop');
    expect(find.text('Nội thất / Thi công'), findsOneWidget);
  });
}
