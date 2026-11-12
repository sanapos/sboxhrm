// Ảnh App Store SBOX BOSS: dựng màn THẬT của app (BossShell, giao diện iOS) với dữ liệu
// chép từ cửa hàng demopos trên sboxpos.com.
//
// Một lệnh: scripts/boss-store-shots/render.ps1 (ghép fixtures → dựng PNG → ghép chú thích vào
// dist/app-store-assets/boss). Không đặt STORE_SHOT_FIXTURES thì test bỏ qua (CI không chạy).
// STORE_SHOT_FIXTURES=<thư mục>: đọc fixtures.json ({"GET /api/x?y": {"status":200,"body":"..."}}) + user.json,
//   ghi requests.txt (mọi yêu cầu app gửi — API mới chưa có dữ liệu thì chép thêm vào fixtures/resp).
// STORE_SHOT_OUT=<thư mục>: lưu PNG. STORE_SHOT_DEVICE=iphone69|ipad13: chỉ dựng một cỡ.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/features/boss/boss_shell.dart';
import 'package:zkteco_flutter_client/l10n/app_localizations.dart';
import 'package:zkteco_flutter_client/models/user.dart';
import 'package:zkteco_flutter_client/providers/auth_provider.dart';
import 'package:zkteco_flutter_client/providers/permission_provider.dart';
import 'package:zkteco_flutter_client/providers/theme_provider.dart';

import '../guide_shots/guide_shot_kit.dart' show loadGuideFonts;

final _env = Platform.environment;
final _fixDir = _env['STORE_SHOT_FIXTURES'];
final _outDir = _env['STORE_SHOT_OUT'];

Map<String, dynamic> _fixtures() {
  final f = File('$_fixDir/fixtures.json');
  return f.existsSync() ? (jsonDecode(f.readAsStringSync()) as Map<String, dynamic>) : {};
}

final _requests = <String>{};

MockClient _api(Map<String, dynamic> fx) => MockClient((req) async {
      final path = req.url.path;
      final q = req.url.query;
      final key = '${req.method} $path${q.isEmpty ? '' : '?$q'}';
      _requests.add(req.method == 'GET' ? key : '$key  BODY ${req.body}');
      final hit = fx[key] ?? fx['${req.method} $path'];
      if (hit is Map) {
        return http.Response.bytes(utf8.encode(hit['body'] as String), (hit['status'] as num).toInt(),
            headers: {'content-type': 'application/json; charset=utf-8'});
      }
      return http.Response(jsonEncode({'isSuccess': true, 'data': const []}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

class _Device {
  const _Device(this.name, this.size, this.ratio);
  final String name;
  final Size size;
  final double ratio;
}

// iPhone 6.9" (1320×2868) và iPad 13" (2064×2752).
const _devices = [
  _Device('iphone69', Size(440, 956), 3),
  _Device('ipad13', Size(1032, 1376), 2),
];

/// Một ảnh: [tab] (chỉ số tab dưới) rồi [act] (bấm mở màn con).
class _Shot {
  const _Shot(this.name, this.tabLabel, [this.open]);
  final String name;
  final String tabLabel;
  final String? open;
}

const _shots = [
  _Shot('1-tong-quan', 'Tổng quan'),
  _Shot('2-can-duyet', 'Cần duyệt'),
  _Shot('3-bao-cao', 'Báo cáo'),
  _Shot('4-kinh-doanh', 'Báo cáo', 'Kinh doanh'),
  _Shot('5-quan-ly', 'Quản lý'),
  _Shot('6-thu-chi', 'Quản lý', 'Phiếu thu chi'),
];

void main() {
  final userFile = File('$_fixDir/user.json');
  final user = (userFile.existsSync() ? jsonDecode(userFile.readAsStringSync()) : <String, dynamic>{})
      as Map<String, dynamic>;

  setUpAll(() async {
    await loadGuideFonts();
    PackageInfo.setMockInitialValues(
        appName: 'SBOX BOSS', packageName: 'boss.sboxpos.com', version: '1.0.0', buildNumber: '5', buildSignature: '');
  });

  final only = _env['STORE_SHOT_DEVICE'];
  for (final d in _devices.where((d) => only == null || d.name == only)) {
    for (final s in _shots) {
      testWidgets('${d.name} ${s.name}', skip: _fixDir == null, (t) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        // Máy cảm ứng: không vẽ viền focus bàn phím quanh nút.
        FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTouch;
        // flutter_test mặc định thay bóng đổ bằng viền đen — ảnh cửa hàng cần bóng thật.
        debugDisableShadows = false;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        SharedPreferences.setMockInitialValues({
          'saved_store_code': 'demopos',
          'refresh_token': 'shot-refresh',
        });
        await t.binding.setSurfaceSize(d.size);
        t.view.physicalSize = d.size * d.ratio;
        t.view.devicePixelRatio = d.ratio;
        // Khoảng tai thỏ / thanh Home của iOS để bố cục đúng như máy thật.
        t.view.padding = d.name.startsWith('iphone')
            ? FakeViewPadding(top: 62 * d.ratio, bottom: 34 * d.ratio)
            : FakeViewPadding(top: 24 * d.ratio, bottom: 20 * d.ratio);
        addTearDown(() {
          t.view.reset();
        });

        final auth = AuthProvider()
          ..debugSetUser(User(
            id: user['id'] as String? ?? 'u1',
            email: user['email'] as String? ?? 'demopos@gmail.com',
            fullName: user['fullName'] as String? ?? 'Demo POS Owner',
            role: 'Admin',
            storeId: user['storeId'] as String? ?? 's1',
            allowedModules: (user['allowedModules'] as List?)?.cast<String>(),
          ));
        final api = _api(_fixtures());
        final boundary = GlobalKey();

        Future<void> settle([int frames = 14]) async {
          for (var i = 0; i < frames; i++) {
            await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
            await t.pump(const Duration(milliseconds: 120));
          }
        }

        await http.runWithClient(() async {
          await t.pumpWidget(RepaintBoundary(
            key: boundary,
            child: MultiProvider(
              providers: [
                ChangeNotifierProvider<AuthProvider>.value(value: auth),
                ChangeNotifierProvider(create: (_) => PermissionProvider()),
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
                builder: (c, child) => MediaQuery(
                  data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
                  child: child!,
                ),
                home: const BossShell(),
              ),
            ),
          ));
          await settle();
          if (s.tabLabel != 'Tổng quan' && find.text(s.tabLabel).evaluate().isNotEmpty) {
            await t.tap(find.text(s.tabLabel).last);
            await settle();
          }
          if (s.open != null && find.text(s.open!).evaluate().isNotEmpty) {
            await t.tap(find.text(s.open!).first);
            await settle(18);
          }
        }, () => api);

        while (t.takeException() != null) {}

        if (_fixDir != null) {
          File('$_fixDir/requests.txt')
              .writeAsStringSync('${_requests.join('\n')}\n', mode: FileMode.append);
        }
        if (_outDir != null) {
          await t.runAsync(() async {
            final b = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
            final img = await b.toImage(pixelRatio: d.ratio);
            final data = await img.toByteData(format: ui.ImageByteFormat.png);
            Directory(_outDir!).createSync(recursive: true);
            File('$_outDir/${d.name}-${s.name}.png').writeAsBytesSync(data!.buffer.asUint8List());
          });
        }
        await http.runWithClient(() async {
          await t.pumpWidget(const SizedBox());
          for (var i = 0; i < 40; i++) {
            await t.pump(const Duration(seconds: 15));
          }
        }, () => api);
        debugDefaultTargetPlatformOverride = null;
        debugDisableShadows = true;
      });
    }
  }
}
