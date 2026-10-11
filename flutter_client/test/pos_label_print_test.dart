import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_product.dart';
import 'package:zkteco_flutter_client/utils/pos_barcode_print.dart';
import 'package:zkteco_flutter_client/utils/pos_label_printer_service.dart';
import 'package:zkteco_flutter_client/utils/pos_label_printer_settings.dart';
import 'package:zkteco_flutter_client/utils/pos_label_renderer.dart';

PosProduct _product(String code, {Map<String, dynamic> extra = const {}}) => PosProduct.fromJson({
      'id': code,
      'productCode': code,
      'name': 'Hàng $code',
      'basePrice': 35000,
      'baseUnitName': 'Lon',
      ...extra,
    });

/// Số bản và khổ của từng lệnh TSPL (đọc «SIZE …» và «PRINT n,1»).
List<({String size, int copies})> _tsplJobs(List<List<int>> jobs) => [
      for (final j in jobs)
        (
          size: RegExp(r'SIZE ([^\r]+)').firstMatch(latin1.decode(j, allowInvalid: true))!.group(1)!,
          copies: int.parse(RegExp(r'PRINT (\d+),1').firstMatch(latin1.decode(j, allowInvalid: true))!.group(1)!),
        ),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const tspl = PosLabelPrinterSettings(protocol: PosLabelPrinterProtocol.tspl);

  group('Lệnh in tem mã vạch', () {
    test('mỗi tem vẽ 1 lần, số bản giao cho máy (PRINT n)', () async {
      final jobs = await PosLabelPrinterService.buildLabelByteJobs(
        [_product('A'), _product('B')],
        options: PosBarcodePrintOptions(template: defaultBarcodeLabelTemplate, copiesPerProduct: 7),
        settings: tspl,
      );
      expect(_tsplJobs(jobs).map((j) => j.copies), [7, 7]);
    });

    test('số tem riêng từng hàng (in theo phiếu nhập)', () async {
      final jobs = await PosLabelPrinterService.buildLabelByteJobs(
        [_product('A'), _product('B'), _product('C')],
        options: PosBarcodePrintOptions(template: defaultBarcodeLabelTemplate),
        settings: tspl,
        copiesPerItem: [48, 0, 3],
      );
      expect(_tsplJobs(jobs).map((j) => j.copies), [48, 3]);
    });

    test('cuộn 2 tem / hàng xếp kín ô — không bỏ trống nửa hàng', () async {
      final jobs = await PosLabelPrinterService.buildLabelByteJobs(
        [_product('A'), _product('B')],
        options: PosBarcodePrintOptions(template: posBarcodeLabelTemplateById('roll_2_72x22')!),
        settings: tspl,
        copiesPerItem: [5, 3],
      );
      // A×5, B×3 = 8 tem = 4 hàng: [A,A]×2, [A,B], [B,B].
      final parsed = _tsplJobs(jobs);
      expect(parsed.map((j) => j.copies).toList(), [2, 1, 1]);
      expect(parsed.fold<int>(0, (a, j) => a + j.copies), 4);
      expect(parsed.every((j) => j.size.startsWith('72.0 mm')), isTrue);
    });
  });

  test('vạch mã vạch khớp lưới điểm (module = số nguyên điểm)', () async {
    final r = await PosLabelRenderer.renderSingle(
      item: const PosLabelRenderItem(name: 'Đậu phộng da cá', code: 'SP001234'),
      template: defaultBarcodeLabelTemplate,
    );
    final bytesPerRow = (r.widthPx + 7) ~/ 8;
    bool black(int x, int y) => (r.raster[y * bytesPerRow + (x >> 3)] >> (7 - (x & 7))) & 1 == 1;
    // Hàng có nhiều chuyển đen/trắng nhất = giữa mã vạch.
    var bestY = 0, bestT = 0;
    for (var y = 0; y < r.heightPx; y++) {
      var t = 0;
      for (var x = 1; x < r.widthPx; x++) {
        if (black(x, y) != black(x - 1, y)) t++;
      }
      if (t > bestT) {
        bestT = t;
        bestY = y;
      }
    }
    final runs = <int>[];
    var len = 1;
    for (var x = 1; x < r.widthPx; x++) {
      if (black(x, bestY) == black(x - 1, bestY)) {
        len++;
      } else {
        runs.add(len);
        len = 1;
      }
    }
    final inner = runs.sublist(1, runs.length - 1); // bỏ lề trắng hai đầu
    final module = inner.reduce((a, b) => a < b ? a : b);
    expect(bestT, greaterThan(40));
    expect(module, greaterThanOrEqualTo(2));
    // Code128: mọi vạch / khoảng trắng là bội số nguyên của module (1–4 module).
    expect(inner.every((w) => w % module == 0 && w ~/ module <= 4), isTrue, reason: 'runs=$inner');
  });

  test('thông số hàng hóa trên tem', () {
    final p = _product('A', extra: {
      'brandName': 'Vinamilk',
      'weight': 180,
      'weightUnit': 'ml',
      'warrantyMonths': 0,
      'attributes': [
        {'attributeId': '1', 'attributeName': 'Vị', 'value': 'Dâu'},
      ],
    });
    expect(posProductSpecText(p), 'Vị: Dâu · TH: Vinamilk · KL: 180 ml');
    const off = PosBarcodePrintOptions(template: PosBarcodeLabelTemplate(
        id: 'x', name: 'x', sizeLabel: 'x', labelWidthMm: 50, labelHeightMm: 30));
    expect(posLabelDetailFor(p, off), isNull);
    final on = PosBarcodePrintOptions(template: defaultBarcodeLabelTemplate, specMode: PosBarcodeSpecMode.withSpecs);
    expect(posLabelDetailFor(p, on), contains('Vinamilk'));
    // Tem cân / lô HSD gắn sẵn được ưu tiên.
    posLabelDetail[p] = 'Lô L01 · HSD 01/12/2026';
    expect(posLabelDetailFor(p, on), 'Lô L01 · HSD 01/12/2026');
  });

  test('PDF tem cuộn 3 tem / hàng tạo được, không cần mạng tải font', () async {
    final bytes = await buildPosBarcodeLabelPdfBytes(
      [_product('A'), _product('B')],
      options: PosBarcodePrintOptions(template: posBarcodeLabelTemplateById('roll_3_104x22')!),
      copiesPerItem: [4, 2],
    );
    expect(bytes.length, greaterThan(1000));
    expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
  });
  Future<void> savePng(({Uint8List raster, int widthPx, int heightPx}) r, String name) async {
    final out = Platform.environment['SBOX_LABEL_SHOTS'];
    if (out == null) return;
    final bpr = (r.widthPx + 7) ~/ 8;
    final rgba = Uint8List(r.widthPx * r.heightPx * 4);
    for (var y = 0; y < r.heightPx; y++) {
      for (var x = 0; x < r.widthPx; x++) {
        final v = (r.raster[y * bpr + (x >> 3)] >> (7 - (x & 7))) & 1 == 1 ? 0 : 255;
        final i = (y * r.widthPx + x) * 4;
        rgba[i] = v;
        rgba[i + 1] = v;
        rgba[i + 2] = v;
        rgba[i + 3] = 255;
      }
    }
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, r.widthPx, r.heightPx, ui.PixelFormat.rgba8888, c.complete);
    final img = await c.future;
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  }

  test('tem vận đơn tự giao 100×150: đủ khổ, có mực', () async {
    final r = await PosLabelRenderer.renderShippingSelfLabel(
      orderNo: 'HD101020260012',
      receiverName: 'Nguyễn Thị Hồng Nhung',
      receiverPhone: '0905 123 456',
      receiverAddress: '191A Hà Huy Tập, Phường Thanh Khê Đông, Quận Thanh Khê, Đà Nẵng',
      codAmount: 460000,
      senderName: 'Quán Demo UI',
      senderPhone: '0935364556',
      carrierName: 'Giao nội bộ',
      note: 'Gọi trước khi giao',
      itemLines: const ['2 × Trà sữa trân châu (Ly L)', '1 × Bánh flan', '3 × Cà phê sữa đá'],
    );
    expect(r.widthPx, PosLabelRenderer.mmToDots(100, 203));
    expect(r.heightPx, PosLabelRenderer.mmToDots(150, 203));
    expect(PosLabelRenderer.hasEnoughInk(r.raster), isTrue);
    await savePng(r, 'ship_self');
  });

  test('ảnh nhãn ngang của hãng → xoay vừa tem dọc 100×150', () async {
    final rec = ui.PictureRecorder();
    final c = ui.Canvas(rec);
    c.drawRect(const ui.Rect.fromLTWH(0, 0, 600, 400), ui.Paint()..color = const ui.Color(0xFFFFFFFF));
    c.drawRect(const ui.Rect.fromLTWH(50, 50, 500, 60), ui.Paint()..color = const ui.Color(0xFF000000));
    c.drawRect(const ui.Rect.fromLTWH(50, 300, 120, 60), ui.Paint()..color = const ui.Color(0xFF000000));
    final img = await rec.endRecording().toImage(600, 400);
    final r = await PosLabelRenderer.rasterFromImage(img);
    expect((r.widthPx, r.heightPx), (PosLabelRenderer.mmToDots(100, 203), PosLabelRenderer.mmToDots(150, 203)));
    expect(PosLabelRenderer.hasEnoughInk(r.raster), isTrue);
    await savePng(r, 'ship_rotated');
  });
  test('độ đậm in: TSPL DENSITY, ZPL ~SD', () async {
    final opts = PosBarcodePrintOptions(template: defaultBarcodeLabelTemplate);
    final t = await PosLabelPrinterService.buildLabelByteJobs([_product('A')],
        options: opts, settings: const PosLabelPrinterSettings(protocol: PosLabelPrinterProtocol.tspl, density: 12));
    expect(latin1.decode(t.first.take(120).toList()), contains('DENSITY 12'));
    final z = await PosLabelPrinterService.buildLabelByteJobs([_product('A')],
        options: opts, settings: const PosLabelPrinterSettings(protocol: PosLabelPrinterProtocol.zpl, density: 12));
    expect(latin1.decode(z.first.take(12).toList()), startsWith('~SD24^XA'));
    final d = await PosLabelPrinterService.buildLabelByteJobs([_product('A')], options: opts, settings: tspl);
    expect(latin1.decode(d.first.take(120).toList()), isNot(contains('DENSITY')));
  });
}
