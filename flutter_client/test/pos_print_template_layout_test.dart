import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zkteco_flutter_client/models/pos_print_template.dart';
import 'package:zkteco_flutter_client/models/pos_print_template_v2.dart';
import 'package:zkteco_flutter_client/utils/pos_print_template_compiler.dart';

PosPrintTemplateV2 _tpl(List<PosPrintBlock> blocks, {double? side}) => PosPrintTemplateV2(
      paperSize: PosPrintPaperSizes.k80,
      printerProfile: 'generic_k80',
      documentType: PosPrintDocumentTypes.saleInvoice,
      blocks: blocks,
      sidePaddingMm: side,
    );

PosPrintCompiledOutput _compile(PosPrintTemplateV2 t) =>
    PosPrintTemplateCompiler.compile(template: t, data: const {'Ten_Cua_Hang': 'Cửa hàng'}, lineItems: const []);

void main() {
  test('Khoảng cách / thụt lề / chữ HOA của khối đi vào dòng in', () {
    final out = _compile(_tpl([
      const PosPrintBlock(
        type: PosPrintBlockType.field,
        field: 'Ten_Cua_Hang',
        style: PosPrintTextStyle(uppercase: true, spaceBefore: 10, spaceAfter: 14, indentLeft: 20, indentRight: 8),
      ),
    ]));
    final lines = out.printImageLines;
    expect(lines, hasLength(1));
    expect(lines.single.text, 'CỬA HÀNG');
    expect((lines.single.spaceBefore, lines.single.spaceAfter), (10.0, 14.0));
    expect((lines.single.indentLeft, lines.single.indentRight), (20.0, 8.0));
    expect(lines.single.sourceBlockIndex, 0);
  });

  test('Khối ảnh: giải mã base64, độ rộng %, căn giữa; HTML có thẻ img', () {
    final png = img.encodePng(img.Image(width: 40, height: 20));
    final out = _compile(_tpl([
      PosPrintBlock(
        type: PosPrintBlockType.image,
        imageData: base64Encode(png),
        imageWidthPct: 40,
        style: const PosPrintTextStyle(align: PosPrintTextAlign.center),
      ),
    ]));
    final step = out.steps.single as PosPrintCompiledImage;
    expect(step.widthFrac, 0.4);
    final line = out.printImageLines.single;
    expect(line.imageBytes, isNotNull);
    expect(line.center, isTrue);
    expect(out.html, contains('<img src="data:image/png;base64,'));
  });

  test('Khối cách dòng giữ chiều cao đặt trong mẫu', () {
    final out = _compile(_tpl([const PosPrintBlock(type: PosPrintBlockType.spacer, height: 40)]));
    expect(out.printImageLines.single.minHeight, 40);
  });

  test('HTML tính bằng mm theo khổ (khớp ảnh in nhiệt), lề nội dung', () {
    final out = _compile(_tpl([
      const PosPrintBlock(type: PosPrintBlockType.text, text: 'Xin chào', style: PosPrintTextStyle(fontSize: 36)),
    ], side: 3));
    // 36 điểm × 80 mm / 576 điểm = 5 mm
    expect(out.html, contains('font-size:5.00mm'));
    expect(out.html, isNot(contains('font-size:36px')));
    expect(out.html, contains('padding:0 3.0mm;'));
    expect(out.sidePaddingMm, 3);
  });

  test('JSON lưu / đọc đủ thuộc tính mới', () {
    final t = _tpl([
      const PosPrintBlock(
        type: PosPrintBlockType.image,
        imageData: 'AAAA',
        imageWidthPct: 70,
        style: PosPrintTextStyle(uppercase: true, spaceAfter: 6, indentLeft: 12),
      ),
    ], side: 2.5);
    final back = PosPrintTemplateV2.fromJson(jsonDecode(t.encode()) as Map<String, dynamic>);
    final b = back.blocks.single;
    expect((b.type, b.imageData, b.imageWidthPct), (PosPrintBlockType.image, 'AAAA', 70));
    expect((b.style.uppercase, b.style.spaceAfter, b.style.indentLeft), (true, 6.0, 12.0));
    expect(back.sidePaddingMm, 2.5);
  });
}
