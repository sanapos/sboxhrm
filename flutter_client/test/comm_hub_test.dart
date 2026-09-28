import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/models/comm_v2.dart';
import 'package:zkteco_flutter_client/providers/theme_provider.dart';
import 'package:zkteco_flutter_client/screens/comm/comm_common.dart';
import 'package:zkteco_flutter_client/screens/comm/comm_editor.dart';
import 'package:zkteco_flutter_client/screens/comm/comm_hub_screen.dart';
import 'package:zkteco_flutter_client/screens/comm/comm_post.dart';

/// Truyền thông v2 với dữ liệu mẫu. Đặt SBOX_SHOT_DIR để lưu ảnh duyệt giao diện.
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

final _now = DateTime.now().toUtc();
String _ago(int hours) => _now.subtract(Duration(hours: hours)).toIso8601String().replaceAll('Z', '');

final _channels = [
  {'id': 'c1', 'key': 'feed', 'name': 'Bảng tin', 'icon': 'home', 'color': '#158DC0', 'canPost': true, 'unread': 2, 'isSystem': true},
  {'id': 'c2', 'key': 'announcement', 'name': 'Thông báo', 'icon': 'campaign', 'color': '#DC2626', 'canPost': true, 'unread': 1, 'isSystem': true, 'postPolicy': 1},
  {'id': 'c3', 'key': 'policy', 'name': 'Nội quy & chính sách', 'icon': 'gavel', 'color': '#7C3AED', 'canPost': true, 'unread': 1, 'isSystem': true, 'postPolicy': 1},
  {'id': 'c4', 'key': 'hr', 'name': 'Nhân sự', 'icon': 'badge', 'color': '#0891B2', 'canPost': true, 'isSystem': true},
  {'id': 'c5', 'key': 'event', 'name': 'Sự kiện', 'icon': 'event', 'color': '#D97706', 'canPost': true, 'isSystem': true},
  {'id': 'c6', 'key': 'training', 'name': 'Đào tạo', 'icon': 'school', 'color': '#16A34A', 'canPost': true, 'isSystem': true},
  {'id': 'c7', 'key': 'culture', 'name': 'Văn hóa', 'icon': 'celebration', 'color': '#DB2777', 'canPost': true, 'isSystem': true},
  {'id': 'c8', 'key': 'docs', 'name': 'Tài liệu', 'icon': 'folder', 'color': '#475569', 'canPost': true, 'isSystem': true},
];

final _policy = {
  'id': 'p1', 'channelId': 'c3', 'channelName': 'Nội quy & chính sách', 'channelColor': '#7C3AED', 'type': 3,
  'title': 'Quy định chấm công và nghỉ phép 2026 (bản 3)',
  'summary': 'Đi trễ quá 15 phút tính nửa công; phép năm cộng dồn tối đa 5 ngày; xin nghỉ trước 48 giờ qua ứng dụng.',
  'contentHtml': '<h2>Phạm vi áp dụng</h2><p>Toàn bộ nhân viên chính thức và thử việc, hiệu lực từ <strong>01/10/2026</strong>.</p>'
      '<h2>Điểm chính</h2><ul><li>Đi trễ quá 15 phút tính <strong>nửa công</strong>.</li><li>Phép năm cộng dồn tối đa 5 ngày.</li><li>Xin nghỉ trước 48 giờ qua ứng dụng.</li></ul>'
      '<blockquote>Mọi thắc mắc liên hệ phòng Nhân sự – máy lẻ 102.</blockquote>',
  'contentFormat': 'html', 'priority': 2, 'status': 2, 'authorId': 'u1', 'authorName': 'Phòng Nhân sự', 'publishedAt': _ago(2),
  'createdAt': _ago(2), 'isPinned': true, 'requireAck': true, 'ackDeadline': _ago(-72), 'version': 3, 'allowComments': true,
  'attachments': [
    {'url': '/f/quy-dinh.pdf', 'name': 'Quy-dinh-cham-cong-2026.pdf', 'kind': 'pdf', 'size': 845000},
    {'url': '/f/bang-phat.xlsx', 'name': 'Bang-muc-phat.xlsx', 'kind': 'excel', 'size': 32000},
  ],
  'views': 31, 'reactionTotal': 12, 'reactions': {'0': 10, '4': 2}, 'comments': 3, 'ackCount': 18, 'audienceCount': 25,
  'myRead': true, 'myAcked': false, 'canEdit': true, 'isAiGenerated': true, 'tags': 'nội quy, chấm công',
};

final _event = {
  'id': 'p2', 'channelId': 'c5', 'channelName': 'Sự kiện', 'channelColor': '#D97706', 'type': 2,
  'title': 'Team building Vũng Tàu 2 ngày 1 đêm', 'summary': 'Cả công ty đi Vũng Tàu cuối tháng 10. Bình chọn hoạt động bạn thích nhất nhé!',
  'contentHtml': '<p>Cả công ty đi Vũng Tàu cuối tháng 10.</p>', 'contentFormat': 'html', 'priority': 1, 'status': 2,
  'authorId': 'u2', 'authorName': 'Nguyễn Lan', 'publishedAt': _ago(20), 'createdAt': _ago(20), 'allowComments': true,
  'eventAt': _ago(-24 * 30), 'eventLocation': 'Resort Lan Rừng, Vũng Tàu', 'version': 1,
  'poll': {
    'question': 'Hoạt động bạn thích nhất?', 'multiple': false, 'totalVoters': 17, 'myVotes': ['o1'],
    'options': [{'id': 'o1', 'text': 'Team games trên biển', 'votes': 9}, {'id': 'o2', 'text': 'Gala dinner', 'votes': 6}, {'id': 'o3', 'text': 'Tự do tắm biển', 'votes': 2}],
  },
  'views': 40, 'reactionTotal': 24, 'reactions': {'0': 14, '1': 6, '2': 4}, 'comments': 8, 'myReaction': 2, 'canEdit': false,
};

final _culture = {
  'id': 'p3', 'channelId': 'c7', 'channelName': 'Văn hóa', 'channelColor': '#DB2777', 'type': 5,
  'title': '', 'summary': 'Chúc mừng sinh nhật 3 bạn tháng 9! Cảm ơn cả team đã cùng về đích doanh số quý 3.',
  'contentHtml': '<p>Chúc mừng sinh nhật 3 bạn tháng 9! Cảm ơn cả team đã cùng về đích doanh số quý 3.</p>', 'contentFormat': 'html',
  'priority': 1, 'status': 2, 'authorId': 'u3', 'authorName': 'Trần Minh', 'publishedAt': _ago(30), 'createdAt': _ago(30),
  'images': ['/img/1.jpg', '/img/2.jpg', '/img/3.jpg', '/img/4.jpg'], 'allowComments': true, 'version': 1,
  'views': 28, 'reactionTotal': 31, 'reactions': {'1': 20, '2': 11}, 'comments': 12, 'canEdit': false,
};

http.Response _ok(Object data) =>
    http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

final _client = MockClient((req) async {
  final p = req.url.path;
  if (p.endsWith('/v2/channels')) return _ok(_channels);
  if (p.endsWith('/v2/feed')) return _ok({'items': [_policy, _event, _culture], 'totalCount': 3});
  if (p.endsWith('/v2/sidebar')) {
    return _ok({
      'requiredPending': 2,
      'required': [{'id': 'p1', 'title': 'Quy định chấm công và nghỉ phép 2026'}, {'id': 'p9', 'title': 'Chính sách bảo mật thông tin khách hàng'}],
      'openPolls': 1,
      'events': [{'id': 'p2', 'title': 'Team building Vũng Tàu', 'at': _ago(-24 * 30)}, {'id': 'p8', 'title': 'Đào tạo an toàn thực phẩm', 'at': _ago(-24 * 8)}],
      'birthdays': [{'name': 'Lê Hà', 'date': _ago(-24)}, {'name': 'Phạm Tú', 'date': _ago(-72)}],
      'pendingApproval': 1,
    });
  }
  if (p.endsWith('/posts/p1/comments')) {
    return _ok([
      {'id': 'k1', 'userId': 'u5', 'userName': 'Lê Tú', 'content': 'Cho em hỏi ca đêm có áp dụng không ạ? @Phòng Nhân sự', 'createdAt': _ago(1)},
      {'id': 'k2', 'userId': 'u1', 'userName': 'Phòng Nhân sự', 'content': 'Có em nhé, áp dụng mọi ca.', 'parentCommentId': 'k1', 'createdAt': _ago(0)},
    ]);
  }
  if (p.endsWith('/posts/p1')) return _ok(_policy);
  if (p.contains('/api/Employees')) return _ok([]);
  return http.Response(jsonEncode({'isSuccess': false, 'message': 'not mocked $p'}), 200);
});

final _ctx = CommContext(
  isManager: true,
  channels: _channels.map(CommChannel.fromJson).toList(),
  myName: 'Trần Quân',
  people: const [CommPerson(employeeId: 'e1', userId: 'u5', name: 'Lê Tú', position: 'Thu ngân')],
);

Future<void> _pump(WidgetTester tester, Widget home, Size size, String name, {bool tall = true}) async {
  final key = GlobalKey();
  Widget app(Size s) => RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeProvider().lightTheme,
          localizationsDelegates: const [quill.FlutterQuillLocalizations.delegate, DefaultMaterialLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
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
  final dir = Platform.environment['SBOX_SHOT_DIR'];
  if (dir != null) {
    await tester.runAsync(() async {
      final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: size.width < 600 ? 2 : 1.25);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
}

void main() {
  setUpAll(_loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Khối AI → Quill: tiêu đề, danh sách, chữ đậm, FAQ', () {
    final ops = commBlocksToOps([
      CommAiBlock('h2', 'Điểm chính'),
      CommAiBlock('bullet', 'Đi trễ quá **15 phút** tính nửa công'),
      CommAiBlock('p', 'Hiệu lực từ 01/10'),
    ], faq: const [(q: 'Ca đêm có áp dụng?', a: 'Có.')]);
    expect(ops.first, {'insert': 'Điểm chính'});
    expect(ops[1], {'insert': '\n', 'attributes': {'header': 2}});
    expect(ops.any((o) => o['insert'] == '15 phút' && (o['attributes'] as Map?)?['bold'] == true), isTrue);
    expect(ops.any((o) => (o['attributes'] as Map?)?['list'] == 'bullet'), isTrue);
    expect(ops.any((o) => o['insert'] == 'Câu hỏi thường gặp'), isTrue);
    final doc = quill.Document.fromJson(ops);
    final html = commDeltaToHtml(doc);
    expect(html, contains('<h2>Điểm chính</h2>'));
    expect(html, contains('<strong>15 phút</strong>'));
    expect(html, contains('<li>'));
  });

  test('Đối tượng nhận: rỗng = toàn công ty', () {
    expect(CommAudience(all: false).isEveryone, isTrue);
    expect(CommAudience(all: false, positions: ['Thu ngân']).isEveryone, isFalse);
  });

  testWidgets('Bảng tin — máy tính 3 cột', (t) async {
    await _pump(t, CommHubScreen(debugContext: _ctx), const Size(1440, 900), 'comm_feed_desktop');
    expect(find.text('Quy định chấm công và nghỉ phép 2026 (bản 3)'), findsOneWidget);
    expect(find.text('Tôi đã đọc và cam kết'), findsOneWidget);
    expect(find.text('Cần bạn xử lý'), findsOneWidget);
  });

  testWidgets('Bảng tin — điện thoại', (t) async {
    await _pump(t, CommHubScreen(debugContext: _ctx), const Size(390, 844), 'comm_feed_mobile');
    expect(find.textContaining('văn bản cần đọc và xác nhận'), findsOneWidget);
  });

  testWidgets('Chi tiết bài + bình luận — điện thoại', (t) async {
    await _pump(t, CommPostDetailPage(postId: 'p1', ctx: _ctx), const Size(390, 844), 'comm_detail_mobile');
    expect(find.text('Phạm vi áp dụng'), findsWidgets);
    expect(find.text('Trả lời'), findsWidgets);
  });

  testWidgets('Trình soạn thảo + Trợ lý AI — máy tính', (t) async {
    await _pump(t, CommEditorPage(ctx: _ctx, startWithAi: true), const Size(1440, 1000), 'comm_editor_desktop', tall: false);
    expect(find.text('Trợ lý viết bài AI'), findsOneWidget);
    expect(find.text('Bắt buộc đọc và xác nhận'), findsOneWidget);
  });

  testWidgets('Trình soạn thảo — điện thoại', (t) async {
    await _pump(t, CommEditorPage(ctx: _ctx), const Size(390, 844), 'comm_editor_mobile');
    expect(find.text('Word / PDF / Excel'), findsOneWidget);
  });
}
