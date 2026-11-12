// Ảnh App Store SBOX KDS: dựng màn bếp THẬT (PosKdsScreen) với dữ liệu mẫu, đúng cỡ Apple.
// Chạy: STORE_SHOT_OUT=<thư mục> flutter test --dart-define=SBOX_APP=kds test/store_shots/kds_store_shots_test.dart
// Không đặt STORE_SHOT_OUT thì test bỏ qua.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/l10n/app_localizations.dart';
import 'package:zkteco_flutter_client/providers/theme_provider.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_kds_screen.dart';

import '../guide_shots/guide_shot_kit.dart' show loadGuideFonts;
import '../guide_shots/pos_guide_common.dart';

final _outDir = Platform.environment['STORE_SHOT_OUT'];

String _ago(int minutes) => DateTime.now().toUtc().subtract(Duration(minutes: minutes)).toIso8601String();

Map<String, Object?> _item(String id, String name, num qty, String status, int min, {String? note}) => {
      'id': id, 'productId': 'p-$name', 'productName': name, 'qty': qty, 'sentQty': qty,
      'status': status, 'note': note, 'sentAt': _ago(min),
    };

Map<String, Object?> _ticket(String id, String no, String table, String area, int min, String status,
        List<Map<String, Object?>> items) =>
    {'orderId': id, 'orderNo': no, 'tableName': table, 'areaName': area, 'sentAt': _ago(min), 'status': status, 'items': items};

List<Map<String, Object?>> _tickets() => [
      _ticket('o1', 'HD000231', 'Bàn 3', 'Tầng 1', 16, 'cooking', [
        _item('i1', 'Phở bò tái', 2, 'cooking', 16, note: 'Ít hành'),
        _item('i2', 'Cơm gà xối mỡ', 1, 'queued', 16),
        _item('i3', 'Trà đá', 2, 'ready', 16),
      ]),
      _ticket('o2', 'HD000232', 'Bàn 7', 'Tầng 1', 9, 'queued', [
        _item('i4', 'Phở bò tái', 1, 'queued', 9),
        _item('i5', 'Bún chả Hà Nội', 2, 'queued', 9, note: 'Thêm rau'),
        _item('i6', 'Nước cam ép', 2, 'cooking', 9),
      ]),
      _ticket('o3', 'HD000233', 'Bàn 2', 'Sân vườn', 5, 'queued', [
        _item('i7', 'Cơm gà xối mỡ', 2, 'queued', 5),
        _item('i8', 'Nem rán', 1, 'queued', 5),
        _item('i9', 'Gỏi cuốn tôm thịt', 2, 'queued', 5, note: 'Không rau mùi'),
      ]),
      _ticket('o4', 'HD000234', 'Bàn 5', 'Sân vườn', 3, 'queued', [
        _item('i10', 'Bún bò Huế', 2, 'queued', 3),
        _item('i11', 'Trà đá', 3, 'queued', 3),
      ]),
      _ticket('o5', 'HD000235', 'Mang về', '', 1, 'queued', [
        _item('i12', 'Bánh mì thịt nướng', 3, 'queued', 1),
        _item('i13', 'Cà phê sữa đá', 2, 'queued', 1),
      ]),
      _ticket('o6', 'HD000236', 'Bàn 9', 'Tầng 2', 12, 'cooking', [
        _item('i14', 'Lẩu thái hải sản', 1, 'cooking', 12, note: 'Ít cay'),
        _item('i15', 'Rau muống xào tỏi', 1, 'queued', 12),
        _item('i16', 'Mực chiên giòn', 1, 'ready', 12),
      ]),
      _ticket('o7', 'HD000237', 'Bàn 11', 'Tầng 2', 7, 'queued', [
        _item('i17', 'Cá kho tộ', 1, 'queued', 7),
        _item('i18', 'Canh chua cá lóc', 1, 'queued', 7),
        _item('i19', 'Sinh tố bơ', 2, 'queued', 7),
      ]),
    ];

final _api = posGuideApi((req) {
  if (req.url.path.endsWith('/api/pos/kds/tickets')) return {'tickets': _tickets()};
  return null;
});

class _Device {
  const _Device(this.name, this.size, this.ratio);
  final String name;
  final Size size;
  final double ratio;
}

// Ngang: iPad 13" 2752×2064, iPhone 6.9" 2868×1320.
const _devices = [
  _Device('ipad13', Size(1376, 1032), 2),
  _Device('iphone69', Size(956, 440), 3),
];

const _shots = [
  ('1-gop-mon', <String, Object>{}),
  ('2-theo-ban', <String, Object>{'pos_kds_view': 'table'}),
  ('3-giao-dien-toi', <String, Object>{'pos_kds_dark': true}),
  ('4-theo-ban-toi', <String, Object>{'pos_kds_dark': true, 'pos_kds_view': 'table'}),
];

void main() {
  setUpAll(() {
    for (final ch in ['flutter_tts', 'wakelock_plus', 'dev.fluttercommunity.plus/wakelock_plus']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(ch), (_) async => null);
    }
  });

  for (final d in _devices) {
    for (final (name, prefs) in _shots) {
      testWidgets('kds ${d.name} $name', skip: _outDir == null, (t) async {
        await loadGuideFonts();
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        t.view.physicalSize = d.size * d.ratio;
        t.view.devicePixelRatio = d.ratio;
        addTearDown(() {
          t.view.resetPhysicalSize();
          t.view.resetDevicePixelRatio();
        });
        final screen = withPosPackage(const PosKdsScreen());
        SharedPreferences.setMockInitialValues(prefs);
        final boundary = GlobalKey();

        Future<void> settle([int frames = 14]) async {
          for (var i = 0; i < frames; i++) {
            await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
            await t.pump(const Duration(milliseconds: 100));
          }
        }

        await http.runWithClient(() async {
          await t.pumpWidget(RepaintBoundary(
            key: boundary,
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
              home: screen,
            ),
          ));
          await settle();
        }, () => _api);

        await t.runAsync(() async {
          final b = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final img = await b.toImage(pixelRatio: d.ratio);
          final data = await img.toByteData(format: ui.ImageByteFormat.png);
          Directory(_outDir!).createSync(recursive: true);
          File('$_outDir/${d.name}-$name.png').writeAsBytesSync(data!.buffer.asUint8List());
        });

        await http.runWithClient(() async {
          await t.pumpWidget(const SizedBox());
          for (var i = 0; i < 4; i++) {
            await t.pump(const Duration(seconds: 3));
          }
        }, () => _api);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
