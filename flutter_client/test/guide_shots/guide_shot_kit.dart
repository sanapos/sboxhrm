import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/l10n/app_localizations.dart';
import 'package:zkteco_flutter_client/models/user.dart';
import 'package:zkteco_flutter_client/providers/auth_provider.dart';
import 'package:zkteco_flutter_client/providers/permission_provider.dart';
import 'package:zkteco_flutter_client/providers/theme_provider.dart';
import 'package:zkteco_flutter_client/widgets/page_top_actions.dart';

/// Ảnh minh họa cho trang Hướng dẫn: dựng màn hình THẬT của app với dữ liệu mẫu (API giả),
/// vẽ khung + số thứ tự lên chỗ cần bấm, rồi lưu PNG.
///
/// Chạy thường (CI): chỉ kiểm mọi điểm đánh dấu còn tìm thấy — đổi giao diện mà quên
/// cập nhật hướng dẫn thì test báo đỏ.
/// Xuất ảnh: GUIDE_SHOT_DIR=../flutter_client/web/images/guide flutter test test/guide_shots

const desktopSize = Size(1280, 800);
const mobileSize = Size(390, 844);

const _markColor = Color(0xFFE53935);

bool _fontsLoaded = false;

Future<void> loadGuideFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  final fl = FontLoader('BeVietnamPro');
  for (final f in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    fl.addFont(Future.value(ByteData.view(File('assets/fonts/BeVietnamPro-$f.ttf').readAsBytesSync().buffer)));
  }
  await fl.load();
  final sym = FontLoader('SboxSymbols');
  for (final f in ['Regular', 'Bold']) {
    sym.addFont(Future.value(ByteData.view(File('assets/fonts/SboxSymbols-$f.ttf').readAsBytesSync().buffer)));
  }
  await sym.load();
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final icons = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)))).load();
    }
  }
}

/// API giả: [routes] khớp theo đuôi đường dẫn, giá trị là phần `data` của phản hồi.
/// Đường dẫn không khai báo trả danh sách rỗng.
MockClient guideApi(Map<String, Object?> routes) => MockClient((req) async {
      final p = req.url.path;
      Object? data = const [];
      for (final e in routes.entries) {
        if (p.endsWith(e.key)) {
          data = e.value;
          break;
        }
      }
      return http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

/// Một điểm đánh dấu: khung bao quanh (gộp) các phần tử [targets], số [n] ở góc.
class GuideMark {
  const GuideMark(this.n, this.targets, {this.pad = 6});

  final int n;
  final List<Finder> targets;
  final double pad;

  /// Cả nút chứa [f] (khung bao trọn nút thay vì chỉ chữ trên nút).
  static Finder button(Finder f) => find
      .ancestor(of: f, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton || w is InkResponse))
      .first;

  /// Widget gần nhất tên [type] chứa [f] — dùng cho widget riêng (_MinuteStepper…) không import được.
  static Finder within(Finder f, String type) =>
      find.ancestor(of: f, matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == type)).first;
}

/// Cuộn tới [f] và đặt nó ở [alignment] chiều cao khung (0 = sát trên, dễ bị thanh dính che).
Future<void> guideScrollTo(WidgetTester t, Finder f, {double alignment = 0.25}) async {
  final vertical = find.byWidgetPredicate((w) => w is Scrollable && axisDirectionToAxis(w.axisDirection) == Axis.vertical);
  // Danh sách dựng dần: nhảy từng đoạn tới khi phần tử xuất hiện (kéo giả lập hay rơi vào ô nhập số).
  final pos = t.state<ScrollableState>(vertical.first).position;
  for (var i = 0; i < 60 && f.evaluate().isEmpty && pos.pixels < pos.maxScrollExtent; i++) {
    pos.jumpTo((pos.pixels + 300).clamp(0, pos.maxScrollExtent));
    await t.pump();
  }
  await Scrollable.ensureVisible(t.element(f.first), alignment: alignment);
  await t.pump();
}

class _MarkBox {
  const _MarkBox(this.n, this.rect);
  final int n;
  final Rect rect;
}

class _MarksPainter extends CustomPainter {
  _MarksPainter(this.marks);
  final List<_MarkBox> marks;

  @override
  void paint(Canvas canvas, Size size) {
    if (marks.isEmpty) return;
    // Làm tối nhẹ phần còn lại để mắt dồn vào chỗ cần bấm.
    final dim = Path()..addRect(Offset.zero & size);
    for (final m in marks) {
      dim.addRRect(RRect.fromRectAndRadius(m.rect, const Radius.circular(10)));
    }
    dim.fillType = PathFillType.evenOdd;
    canvas.drawPath(dim, Paint()..color = const Color(0x2E0F172A));

    final stroke = Paint()
      ..color = _markColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (final m in marks) {
      canvas.drawRRect(RRect.fromRectAndRadius(m.rect, const Radius.circular(10)), stroke);
    }
    for (final m in marks) {
      const r = 14.0;
      var c = m.rect.topLeft + const Offset(-8, -8);
      c = Offset(c.dx.clamp(r + 2, size.width - r - 2), c.dy.clamp(r + 2, size.height - r - 2));
      canvas.drawCircle(c, r + 2.5, Paint()..color = Colors.white);
      canvas.drawCircle(c, r, Paint()..color = _markColor);
      final tp = TextPainter(
        text: TextSpan(
          text: '${m.n}',
          style: const TextStyle(fontFamily: 'BeVietnamPro', fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_MarksPainter old) => old.marks != marks;
}

/// Khung giống app: thanh trên có đường dẫn menu (vd «Cài đặt › Thiết lập ca») và
/// các nút trang đăng ký qua [RegisterPageTopActions]; điện thoại dùng FAB như app.
class _GuideFrame extends StatelessWidget {
  const _GuideFrame({required this.crumbs, required this.child});
  final List<String> crumbs;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    final crumbText = Text.rich(
      TextSpan(children: [
        for (var i = 0; i < crumbs.length; i++) ...[
          if (i > 0) const TextSpan(text: '  ›  ', style: TextStyle(color: Color(0xFF94A3B8))),
          TextSpan(
            text: crumbs[i],
            style: TextStyle(
              fontWeight: i == crumbs.length - 1 ? FontWeight.w700 : FontWeight.w500,
              color: i == crumbs.length - 1 ? const Color(0xFF0F172A) : const Color(0xFF64748B),
            ),
          ),
        ],
      ]),
      style: TextStyle(fontSize: mobile ? 15 : 16),
      overflow: TextOverflow.ellipsis,
    );
    return Scaffold(
      floatingActionButton: mobile ? const PageTopActionsFab() : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(children: [
              Expanded(child: crumbText),
              if (!mobile)
                ListenableBuilder(
                  listenable: PageTopActions.instance,
                  builder: (_, __) => PageTopActionsBar(actions: PageTopActions.instance.actions),
                ),
            ]),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Finder .first ném StateError khi rỗng — coi như không thấy.
bool _found(Finder f) {
  try {
    return f.evaluate().isNotEmpty;
  } on StateError {
    return false;
  }
}

/// Dựng [screen] trong khung app, chờ tải xong, chạy [act] (gõ chữ, bấm nút…),
/// đánh dấu [marks] rồi lưu `<GUIDE_SHOT_DIR>/<name>.png` (nếu có biến môi trường).
Future<void> guideShot(
  WidgetTester t, {
  required String name,
  required Widget screen,
  required MockClient api,
  List<String> crumbs = const [],
  Size size = desktopSize,
  List<GuideMark> marks = const [],
  Future<void> Function(WidgetTester t)? act,
}) async {
  await loadGuideFonts();
  SharedPreferences.setMockInitialValues({});
  await t.binding.setSurfaceSize(size);
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(() {
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });

  final auth = AuthProvider()
    ..debugSetUser(User(id: 'u1', employeeId: 'e1', email: 'admin@comganam.vn', fullName: 'Nguyễn Văn An', role: 'Admin', storeId: 's1'));
  final boundary = GlobalKey();
  final painted = ValueNotifier<List<_MarkBox>>(const []);

  Future<void> settle([int frames = 12]) async {
    for (var i = 0; i < frames; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  await http.runWithClient(() async {
    await t.pumpWidget(RepaintBoundary(
      key: boundary,
      child: Stack(textDirection: TextDirection.ltr, children: [
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: auth),
            ChangeNotifierProvider(create: (_) => PermissionProvider()..loadPermissions(role: 'Admin')),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeProvider().lightTheme,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('vi')],
            locale: const Locale('vi'),
            home: _GuideFrame(crumbs: crumbs, child: screen),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: ValueListenableBuilder<List<_MarkBox>>(
              valueListenable: painted,
              builder: (_, m, __) => CustomPaint(painter: _MarksPainter(m)),
            ),
          ),
        ),
      ]),
    ));
    await settle();
    if (act != null) {
      await act(t);
      await settle(6);
    }
  }, () => api);

  final errors = <Object>[];
  Object? e;
  while ((e = t.takeException()) != null) {
    errors.add(e!);
  }
  expect(errors, isEmpty, reason: '$name: lỗi vẽ giao diện');

  final origin = t.getTopLeft(find.byKey(boundary));
  final boxes = <_MarkBox>[];
  for (final m in marks) {
    Rect? r;
    for (final (i, f) in m.targets.indexed) {
      // Không in "$f": finder dạng .first/.ancestor ném lỗi khi mô tả lúc rỗng, che mất lỗi thật.
      expect(_found(f), isTrue, reason: '$name: không thấy điểm đánh dấu ${m.n} (phần tử thứ ${i + 1})');
      final rect = t.getRect(f.first).shift(-origin);
      r = r == null ? rect : r.expandToInclude(rect);
    }
    final box = r!.inflate(m.pad).intersect((Offset.zero & size).deflate(4));
    expect(box.width > 0 && box.height > 0, isTrue, reason: '$name: điểm đánh dấu ${m.n} nằm ngoài khung ảnh');
    boxes.add(_MarkBox(m.n, box));
  }
  painted.value = boxes;
  await t.pump();

  final dir = Platform.environment['GUIDE_SHOT_DIR'];
  if (dir != null) {
    await t.runAsync(() async {
      final b = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final img = await b.toImage(pixelRatio: size.width < 600 ? 2 : 1.5);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(dir).createSync(recursive: true);
      File('$dir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }
  // Hẹn giờ nền của AuthProvider (kiểm tra vị trí, thử lại 2 giây) — chạy hết trước khi gỡ cây.
  await http.runWithClient(() async {
    await t.pumpWidget(const SizedBox());
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(seconds: 3));
    }
  }, () => api);
}
