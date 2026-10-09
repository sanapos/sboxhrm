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
import 'package:zkteco_flutter_client/models/task_v2.dart';
import 'package:zkteco_flutter_client/providers/theme_provider.dart';
import 'package:zkteco_flutter_client/screens/work/work_assign_sheet.dart';
import 'package:zkteco_flutter_client/screens/work/work_task_editor.dart' show WorkPerson;

/// Giao việc theo mẫu ngành (F&B): chọn mẫu → người → hạn → tạo việc đúng mẫu, nhân viên phải bấm Nhận việc.
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

final _templates = [
  TaskTemplateV2.fromJson({
    'id': 't1', 'name': 'Checklist mở ca', 'title': 'Checklist mở ca', 'taskType': 6, 'priority': 2,
    'recurrenceType': 1, 'recurrenceTime': '06:30', 'dueAfterHours': 2,
    'checklist': jsonEncode([
      {'id': 'a', 'text': 'Bật đèn, điều hoà, nhạc'},
      {'id': 'b', 'text': 'Quầy bar / khu bán gọn sạch', 'requirePhoto': true},
      {'id': 'c', 'text': 'Kiểm tra máy pha, máy POS, máy in bill'},
    ]),
    'formSchema': jsonEncode([
      {'key': 'temp', 'label': 'Nhiệt độ tủ mát', 'type': 'number', 'required': true},
      {'key': 'cash', 'label': 'Tiền đầu ca trong két', 'type': 'money', 'required': true},
    ]),
  }),
  TaskTemplateV2.fromJson({'id': 't2', 'name': 'Nhận hàng nhà cung cấp', 'title': 'Nhận hàng nhà cung cấp', 'taskType': 13,
    'checklist': jsonEncode([{'id': 'x', 'text': 'Đối chiếu số lượng'}])}),
  TaskTemplateV2.fromJson({'id': 't3', 'name': 'Xử lý phản ánh khách', 'title': 'Xử lý phản ánh khách', 'taskType': 10, 'dueAfterHours': 4}),
];

const _people = [WorkPerson('e1', 'Trần Quân'), WorkPerson('e2', 'Lê Tú'), WorkPerson('e3', 'Phạm Hà')];

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  final dir = Platform.environment['SBOX_SHOT_DIR'];
  if (dir == null) return;
  await tester.runAsync(() async {
    final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 2);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({'work_assign_recent_people': ['e2']}));

  testWidgets('Giao việc theo mẫu F&B — điện thoại', (tester) async {
    final posted = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      if (req.method == 'POST' && req.url.path.endsWith('/api/Tasks')) {
        posted.add(jsonDecode(req.body) as Map<String, dynamic>);
        return http.Response(jsonEncode({'isSuccess': true, 'data': {'id': 'n${posted.length}'}}), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response(jsonEncode({'isSuccess': false}), 200);
    });
    const size = Size(390, 844);
    await tester.binding.setSurfaceSize(size);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    final key = GlobalKey();
    var created = false;
    await http.runWithClient(() async {
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeProvider().lightTheme,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () async {
                    created = await showWorkAssignSheet(ctx,
                        templates: _templates,
                        people: _people,
                        taskLabel: 'Công việc',
                        industryName: 'F&B — Nhà hàng / Cafe',
                        onMore: (_) {},
                        onInstallPacks: () {});
                  },
                  child: const Text('Giao việc'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Giao việc'));
      await tester.pumpAndSettle();
      expect(find.text('Chọn mẫu việc'), findsOneWidget);
      expect(find.text('Checklist mở ca'), findsOneWidget);
      expect(find.textContaining('3 mục kiểm · biểu mẫu 2 ô · Hằng ngày'), findsOneWidget); // mẫu lặp lại vẫn hiện
      await _shot(tester, key, 'assign_step1_mobile');

      await tester.tap(find.text('Checklist mở ca'));
      await tester.pumpAndSettle();
      expect(find.text('Giao việc'), findsWidgets);
      expect(find.text('Trong 2 giờ'), findsOneWidget); // hạn theo mẫu
      expect(find.text('Quầy bar / khu bán gọn sạch'), findsOneWidget);
      await tester.tap(find.widgetWithText(ActionChip, 'Lê Tú')); // người giao gần đây
      await tester.pumpAndSettle();
      await _shot(tester, key, 'assign_step2_mobile');

      await tester.tap(find.byIcon(Icons.send_rounded));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
    }, () => client);

    expect(created, isTrue);
    expect(posted, hasLength(1));
    expect(posted.single['templateId'], 't1');
    expect(posted.single['assigneeId'], 'e2');
    expect(posted.single['requireAcceptance'], isTrue);
    expect(posted.single['title'], 'Checklist mở ca');
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
