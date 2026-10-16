import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_label_design.dart';
import 'package:zkteco_flutter_client/models/pos_print_template.dart';
import 'package:zkteco_flutter_client/models/pos_print_template_v2.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_label_templates_screen.dart';
import 'package:zkteco_flutter_client/utils/pos_label_design_painter.dart';
import 'package:zkteco_flutter_client/utils/pos_label_design_presets.dart';
import 'package:zkteco_flutter_client/utils/pos_print_template_v2_codec.dart';

void main() {
  test('Mẫu tem lưu / đọc lại giữ nguyên; bộ đọc mẫu khối cũ bỏ qua', () {
    final d = PosLabelDesignPresets.forType(PosPrintDocumentTypes.scaleLabel).first.build(50, 30);
    final enc = d.encode();
    expect(PosLabelDesign.isDesign(enc), isTrue);
    expect(PosPrintTemplateV2Codec.tryParse(enc), isNull);
    expect(PosPrintTemplateV2Codec.isV2Content(enc), isFalse);
    final back = PosLabelDesign.tryParse(enc)!;
    expect(back.widthMm, 50);
    expect(back.heightMm, 30);
    expect(back.documentType, PosPrintDocumentTypes.scaleLabel);
    expect(back.elements.length, d.elements.length);
    expect(back.elements.first.text, d.elements.first.text);
    expect(back.toJson(), d.toJson());
  });

  test('Thay trường dữ liệu; dòng có trường trống thì ẩn', () {
    final data = {'Ten_Hang_Hoa': 'Nồi cơm', 'Bao_Hanh': ''};
    expect(PosLabelDesignPainter.resolve('Tên: {Ten_Hang_Hoa}', data), 'Tên: Nồi cơm');
    expect(PosLabelDesignPainter.hasContent('Bảo hành: {Bao_Hanh}', data), isFalse);
    expect(PosLabelDesignPainter.hasContent('{Ten_Hang_Hoa} {Bao_Hanh}', data), isTrue);
    expect(PosLabelDesignPainter.hasContent('Chữ cố định', data), isTrue);
  });

  test('Mẫu dựng sẵn nằm gọn trong khổ tem (mọi loại, mọi khổ)', () {
    for (final type in [
      PosPrintDocumentTypes.barcodeLabel,
      PosPrintDocumentTypes.scaleLabel,
      PosPrintDocumentTypes.specLabel,
    ]) {
      for (final p in PosLabelDesignPresets.forType(type)) {
        for (final (w, h) in PosLabelDesignPresets.sizes) {
          final d = p.build(w, h);
          expect(d.documentType, type);
          for (final e in d.elements) {
            expect(e.x >= -0.01 && e.y >= -0.01, isTrue, reason: '${p.key} $w×$h ${e.text}');
            expect(e.x + e.w <= w + 0.01, isTrue, reason: '${p.key} $w×$h ${e.text} tràn phải');
            expect(e.y + e.h <= h + 0.01, isTrue, reason: '${p.key} $w×$h ${e.text} tràn dưới');
          }
        }
      }
    }
  });

  test('Mẫu khối cũ chuyển sang trình soạn: giữ trường, nằm trong tem', () {
    final v2 = PosPrintTemplateV2(
      paperSize: 'roll_1_50x30',
      printerProfile: 'generic_k58',
      documentType: PosPrintDocumentTypes.barcodeLabel,
      blocks: const [
        PosPrintBlock(type: PosPrintBlockType.field, field: 'Ten_Hang_Hoa', style: PosPrintTextStyle(fontSize: 26, bold: true)),
        PosPrintBlock(type: PosPrintBlockType.barcode, field: 'Ma_Vach', barcodeHeight: 48),
        PosPrintBlock(type: PosPrintBlockType.text, text: '{Don_Gia} đ', style: PosPrintTextStyle(fontSize: 24)),
      ],
    );
    final d = posLabelDesignFromBlocks(v2, PosPrintDocumentTypes.barcodeLabel, 50, 30);
    expect(d.elements.map((e) => e.type), [
      PosLabelElementType.text,
      PosLabelElementType.barcode,
      PosLabelElementType.text,
    ]);
    expect(d.elements.first.text, '{Ten_Hang_Hoa}');
    expect(d.elements.first.bold, isTrue);
    for (final e in d.elements) {
      expect(e.y + e.h <= 30.01, isTrue);
    }
  });

  testWidgets('Vẽ ảnh in nhiệt đúng kích thước 203 dpi, có mực', (tester) async {
    final d = PosLabelDesignPresets.forType(PosPrintDocumentTypes.barcodeLabel).first.build(50, 30);
    final data = {'Ten_Hang_Hoa': 'Bánh mì que', 'Ma_Vach': '8934567890123', 'Don_Gia': '12.000'};
    final r = await tester.runAsync(() => PosLabelDesignPainter.renderRowRaster(d, [data]));
    expect(r, isNotNull);
    expect(r!.widthPx, (50 * 203 / 25.4).round());
    expect(r.heightPx, (30 * 203 / 25.4).round());
    var black = 0;
    for (final b in r.raster) {
      black += b.bitCount;
    }
    expect(black, greaterThan(500));
  });
}

extension on int {
  int get bitCount {
    var v = this, c = 0;
    while (v != 0) {
      c += v & 1;
      v >>= 1;
    }
    return c;
  }
}
