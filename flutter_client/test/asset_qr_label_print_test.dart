import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/models/asset.dart';
import 'package:zkteco_flutter_client/utils/asset_qr_label_print.dart';
import 'package:zkteco_flutter_client/utils/pos_label_printer_service.dart';
import 'package:zkteco_flutter_client/utils/pos_label_printer_settings.dart';
import 'package:zkteco_flutter_client/utils/pos_label_renderer.dart';

/// Tem QR tài sản: nội dung QR khớp API tra cứu, tem nhiệt 40×30 / 50×30 ra lệnh TSPL đúng khổ,
/// PDF A4 24 tem / trang, hộp thoại «In tem QR» dựng không lỗi. Đặt SBOX_SHOT_DIR để lưu ảnh tem / hộp thoại.
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

Asset _asset(String code, {String? qr, String name = 'Laptop Dell Latitude 5440', String? location, String? holder}) =>
    Asset.fromJson({
      'id': code,
      'assetCode': code,
      'qrCode': qr,
      'name': name,
      'assetType': 1,
      'status': 1,
      'purchasePrice': 18500000,
      'location': location,
      'currentAssigneeId': holder == null ? null : 'u-$code',
      'currentAssigneeName': holder,
      'createdAt': '2026-10-01T00:00:00Z',
    });

final _shotDir = Platform.environment['SBOX_SHOT_DIR'];

Future<void> _saveImage(ui.Image img, String name) async {
  if (_shotDir == null) return;
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  File('$_shotDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Nội dung tem', () {
    test('QR = mã QR của tài sản, trống thì mã tài sản (đúng cái API tra cứu so khớp)', () {
      expect(assetQrPayload(_asset('TS-0001', qr: 'TS-0001')), 'TS-0001');
      expect(assetQrPayload(_asset('TS-0002', qr: 'QR-PHONG-KE-TOAN-7')), 'QR-PHONG-KE-TOAN-7');
      expect(assetQrPayload(_asset('TS-0003')), 'TS-0003');
      expect(assetQrPayload(_asset('TS-0004', qr: '  ')), 'TS-0004');
      expect(assetQrPayload(_asset(' TS-0005 ', qr: ' QR5 ')), 'QR5');
    });

    test('dòng vị trí · người giữ, bỏ phần trống', () {
      expect(assetQrHolderLine(_asset('A', location: 'Phòng Kế toán', holder: 'Nguyễn Văn An')),
          'Phòng Kế toán · Nguyễn Văn An');
      expect(assetQrHolderLine(_asset('A', holder: 'Nguyễn Văn An')), 'Nguyễn Văn An');
      expect(assetQrHolderLine(_asset('A')), '');
    });

    test('số tem mỗi tài sản, bỏ tài sản không có mã', () {
      final items = assetQrLabelItems([_asset('A'), _asset(''), _asset('B')], copies: 3);
      expect(items.map((e) => e.assetCode), ['A', 'A', 'A', 'B', 'B', 'B']);
    });
  });

  group('Tem nhiệt (máy in tem POS)', () {
    for (final size in [AssetQrLabelSize.thermal40x30, AssetQrLabelSize.thermal50x30]) {
      test('${size.label}: ảnh đúng khổ, có mực, lệnh TSPL đúng SIZE', () async {
        final item = AssetQrLabelItem.fromAsset(_asset('TS-2026-0042',
            name: 'Máy tính xách tay Dell Latitude 5440 i7/16GB',
            location: 'Phòng Kế toán',
            holder: 'Nguyễn Thị Hồng Nhung'));
        final rasters = await renderAssetQrLabelRasters([item], size: size, companyName: 'Công ty TNHH SBOX Việt Nam');
        final r = rasters.single;
        expect((r.widthPx, r.heightPx),
            (PosLabelRenderer.mmToDots(size.widthMm, 203), PosLabelRenderer.mmToDots(size.heightMm, 203)));
        expect(PosLabelRenderer.hasEnoughInk(r.raster), isTrue);

        final jobs = PosLabelPrinterService.buildCupRasterByteJobs(
          rasters,
          settings: const PosLabelPrinterSettings(protocol: PosLabelPrinterProtocol.tspl),
          widthMm: size.widthMm,
          heightMm: size.heightMm,
        );
        final head = latin1.decode(jobs.single.take(160).toList(), allowInvalid: true);
        expect(head, contains('SIZE ${size.widthMm.toStringAsFixed(1)} mm, ${size.heightMm.toStringAsFixed(1)} mm'));

        final img = await renderAssetQrLabelImage(item,
            size: size, companyName: 'Công ty TNHH SBOX Việt Nam', dpi: 300);
        await _saveImage(img, 'asset_qr_${size.name}');
      });
    }

    test('tên / mã dài không làm lỗi tem 40×30', () async {
      final item = AssetQrLabelItem.fromAsset(_asset('TS-PHONG-HOP-TANG-3-0000000123',
          name: 'Bàn họp gỗ óc chó 12 chỗ kèm hộc điện âm bàn và ổ cắm đa năng nhập khẩu Ý loại cao cấp',
          location: 'Tầng 3 — Phòng họp lớn tòa nhà văn phòng chính',
          holder: 'Trần Nguyễn Hoàng Bảo Ngọc'));
      final r = (await renderAssetQrLabelRasters([item], size: AssetQrLabelSize.thermal40x30)).single;
      expect(PosLabelRenderer.hasEnoughInk(r.raster), isTrue);
      await _saveImage(await renderAssetQrLabelImage(item, size: AssetQrLabelSize.thermal40x30, dpi: 300),
          'asset_qr_long_40x30');
    });
  });

  group('PDF', () {
    String pdfText(List<int> b) => latin1.decode(b, allowInvalid: true);
    int pages(List<int> b) => RegExp(r'/Type\s*/Page[^s]').allMatches(pdfText(b)).length;

    test('A4: 24 tem / trang', () async {
      final items = assetQrLabelItems([for (var i = 1; i <= 10; i++) _asset('TS-$i')], copies: 3);
      final bytes = await buildAssetQrLabelPdfBytes(items, size: AssetQrLabelSize.a4, companyName: 'SBOX');
      expect(pdfText(bytes.take(5).toList()), '%PDF-');
      expect(pages(bytes), 2); // 30 tem → 2 trang
      if (_shotDir != null) File('$_shotDir/asset_qr_a4.pdf').writeAsBytesSync(bytes);
    });

    test('tem nhiệt: mỗi trang 1 tem đúng khổ', () async {
      final items = assetQrLabelItems([_asset('A'), _asset('B')], copies: 2);
      final bytes = await buildAssetQrLabelPdfBytes(items, size: AssetQrLabelSize.thermal50x30);
      expect(pages(bytes), 4);
      // 50 mm = 141,73 pt
      expect(pdfText(bytes), contains('141.73'));
    });
  });

  group('Hộp thoại In tem QR', () {
    Future<void> pumpDialog(WidgetTester tester, List<Asset> assets, Size size, String shot) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'BeVietnamPro', useMaterial3: true),
          home: Scaffold(
            body: Column(children: [
              // Ô QR ở chi tiết tài sản (cùng bộ vẽ với tem).
              Padding(
                padding: const EdgeInsets.all(8),
                child: AssetQrCodeView(data: assetQrPayload(assets.first), size: 100),
              ),
              Expanded(child: AssetQrLabelPrintDialog(assets: assets, companyName: 'Công ty TNHH SBOX Việt Nam')),
            ]),
          ),
        ),
      ));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(tester.takeException(), isNull);
      if (_shotDir != null) {
        await tester.runAsync(() async {
          final b = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          await _saveImage(await b.toImage(pixelRatio: 1.5), shot);
        });
      }
    }

    tearDown(() {
      final v = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
      v.resetPhysicalSize();
      v.resetDevicePixelRatio();
    });

    testWidgets('1 tài sản: chọn khổ, xem trước, nút in máy tem', (tester) async {
      await pumpDialog(
          tester,
          [_asset('TS-2026-0042', name: 'Máy chiếu Epson EB-X51', location: 'Phòng họp 2', holder: 'Lê Minh Tuấn')],
          const Size(520, 900),
          'asset_qr_dialog_single');
      expect(find.text('In tem QR tài sản'), findsOneWidget);
      expect(find.text('Tem nhiệt 40×30'), findsOneWidget);
      expect(find.text('Tem nhiệt 50×30'), findsOneWidget);
      expect(find.text('Giấy A4 (24 tem / trang)'), findsOneWidget);
      expect(find.text('In ra máy tem'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget); // ảnh xem trước tem
      expect(find.text('Tổng 1 tem'), findsOneWidget);
    });

    testWidgets('nhiều tài sản → A4: đếm tem / trang, nút In', (tester) async {
      await pumpDialog(tester, [for (var i = 1; i <= 30; i++) _asset('TS-$i', name: 'Ghế xoay văn phòng #$i')],
          const Size(520, 900), 'asset_qr_dialog_a4_before');
      await tester.tap(find.byKey(const ValueKey('asset-qr-size-a4')));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('30 tài sản đã chọn'), findsOneWidget);
      expect(find.text('Tổng 30 tem · 2 trang A4'), findsOneWidget);
      expect(find.text('In'), findsOneWidget);
      expect(find.text('In ra máy tem'), findsNothing);
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pump();
      expect(find.text('Tổng 60 tem · 3 trang A4'), findsOneWidget);
      if (_shotDir != null) {
        await tester.runAsync(() async {
          final b = tester.firstRenderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
          await _saveImage(await b.toImage(pixelRatio: 1.5), 'asset_qr_dialog_a4');
        });
      }
    });
  });
}
