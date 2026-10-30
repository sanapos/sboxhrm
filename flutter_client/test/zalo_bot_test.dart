import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/l10n/app_localizations.dart';
import 'package:zkteco_flutter_client/providers/auth_provider.dart';
import 'package:zkteco_flutter_client/providers/permission_provider.dart';
import 'package:zkteco_flutter_client/providers/theme_provider.dart';
import 'package:zkteco_flutter_client/screens/settings_screen.dart';
import 'package:zkteco_flutter_client/screens/zalo_bot_settings_screen.dart';
import 'package:zkteco_flutter_client/widgets/zalo_link_sheet.dart';

/// Zalo bot: thiết lập cửa hàng (token, nhóm thông báo, người đã liên kết), dòng «Liên kết Zalo» ở Cài đặt,
/// bảng lấy mã liên kết. Đặt SBOX_SHOT_DIR để lưu ảnh duyệt giao diện.
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

const _settings = {
  'enabled': true,
  'hasToken': true,
  'botName': 'Bot Cafe An',
  'botLink': 'https://zalo.me/s/botcafe',
  'webhookOk': true,
  'webhookUrl': 'https://sboxhrm.com/api/zalo-bot/webhook/x',
  'categories': ['payroll', 'penalty'],
  'hideMoney': false,
  'lastError': null,
  'linkedCount': 1,
  'allCategories': [
    {'code': 'payroll', 'label': 'Lương & phiếu lương'},
    {'code': 'penalty', 'label': 'Phiếu phạt'},
    {'code': 'leave', 'label': 'Nghỉ phép'},
  ],
};

const _links = [
  {'userId': 'u1', 'name': 'Nguyễn An', 'userName': 'an', 'role': 'Employee', 'linked': true, 'zaloName': 'An Zalo', 'linkedAt': '2026-10-30T03:00:00'},
  {'userId': 'u2', 'name': 'Trần Bình', 'userName': 'binh', 'role': 'Employee', 'linked': false, 'zaloName': null, 'linkedAt': null},
];

/// Máy chủ giả: ghi lại các yêu cầu gửi đi; [me] = trả lời /me.
class _Server {
  _Server({this.me = const {'available': true, 'linked': false, 'botName': 'Bot Cafe An', 'botLink': 'https://zalo.me/s/botcafe'}});

  final Map<String, dynamic> me;
  final List<http.Request> requests = [];

  http.Response _ok(Object? data) =>
      http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

  late final client = MockClient((req) async {
    requests.add(req);
    final p = req.url.path;
    if (p.endsWith('/api/zalo-bot/settings')) {
      if (req.method == 'PUT') return _ok({..._settings, ...jsonDecode(req.body) as Map<String, dynamic>, 'hasToken': true});
      return _ok(_settings);
    }
    if (p.endsWith('/api/zalo-bot/links')) return _ok(_links);
    if (p.endsWith('/api/zalo-bot/me/code')) {
      return _ok({'code': '123456', 'expiresAt': '2026-10-30T03:15:00', 'botName': 'Bot Cafe An', 'botLink': 'https://zalo.me/s/botcafe'});
    }
    if (p.endsWith('/api/zalo-bot/me')) return _ok(me);
    return _ok([]);
  });
}

Future<void> _pump(WidgetTester tester, _Server server, Widget home, Size size, String name,
    {Future<void> Function()? before}) async {
  final key = GlobalKey();
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await http.runWithClient(() async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => PermissionProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeProvider().lightTheme,
          localizationsDelegates: const [AppLocalizations.delegate, DefaultMaterialLocalizations.delegate, DefaultWidgetsLocalizations.delegate],
          home: MediaQuery(data: MediaQueryData(size: size), child: home),
        ),
      ),
    ));
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    if (before != null) {
      await before();
      await settle();
    }
    expect(tester.takeException(), isNull);
  }, () => server.client);
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

  testWidgets('Thiết lập Zalo bot: trạng thái, nhóm thông báo, người đã liên kết; lưu gửi đúng nhóm', (t) async {
    final server = _Server();
    await _pump(t, server, const Scaffold(body: ZaloBotSettingsScreen()), const Size(1000, 1500), 'zalo_settings_desktop',
        before: () async {
      await t.tap(find.widgetWithText(FilterChip, 'Nghỉ phép'));
      await t.pump();
    });
    expect(find.text('Bot Cafe An'), findsOneWidget);
    expect(find.text('Hoạt động'), findsOneWidget);
    expect(find.text('Nguyễn An'), findsOneWidget);
    expect(find.text('Trần Bình'), findsNothing); // chỉ liệt kê người đã liên kết
    expect(find.text('1/2 tài khoản'), findsOneWidget);

    await http.runWithClient(() async {
      final save = find.text('Lưu');
      expect(save, findsWidgets);
      await t.tap(save.last);
      for (var i = 0; i < 6; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump(const Duration(milliseconds: 100));
      }
    }, () => server.client);
    final put = server.requests.lastWhere((r) => r.method == 'PUT');
    final body = jsonDecode(put.body) as Map<String, dynamic>;
    expect(body['categories'], containsAll(['payroll', 'penalty', 'leave']));
    expect(body.containsKey('botToken'), isFalse); // ô token trống = giữ token cũ
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('Thiết lập Zalo bot — điện thoại', (t) async {
    await _pump(t, _Server(), const Scaffold(body: ZaloBotSettingsScreen()), const Size(390, 1700), 'zalo_settings_mobile');
    expect(find.text('Gửi tin thử cho tôi'), findsOneWidget);
  });

  testWidgets('Cài đặt: «Liên kết Zalo» chỉ hiện khi cửa hàng bật bot', (t) async {
    await _pump(t, _Server(), const SettingsScreen(), const Size(900, 900), 'zalo_settings_tile');
    expect(find.text('Liên kết Zalo'), findsOneWidget);

    await _pump(t, _Server(me: const {'available': false, 'linked': false}), const SettingsScreen(), const Size(900, 900), 'zalo_settings_tile_off');
    expect(find.text('Liên kết Zalo'), findsNothing);
  });

  testWidgets('Bảng liên kết: lấy mã 6 số, mở bot', (t) async {
    final server = _Server();
    await _pump(t, server, Scaffold(body: ZaloLinkSheet(initial: server.me)), const Size(390, 700), 'zalo_link_code',
        before: () async {
      await t.tap(find.text('Lấy mã liên kết'));
      await t.pump();
    });
    expect(find.text('123 456'), findsOneWidget);
    expect(find.text('Mở bot Zalo'), findsOneWidget);
    expect(server.requests.any((r) => r.method == 'POST' && r.url.path.endsWith('/me/code')), isTrue);
    // Dừng hẹn giờ tự cập nhật trạng thái liên kết.
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 3));
  });

  testWidgets('Bảng liên kết: đã liên kết → hiện tên Zalo + nút hủy', (t) async {
    final server = _Server(me: const {'available': true, 'linked': true, 'zaloName': 'An Zalo', 'botName': 'Bot Cafe An'});
    await _pump(t, server, Scaffold(body: ZaloLinkSheet(initial: server.me)), const Size(390, 500), 'zalo_link_linked');
    expect(find.textContaining('An Zalo'), findsOneWidget);
    expect(find.text('Hủy liên kết'), findsOneWidget);
  });
}
