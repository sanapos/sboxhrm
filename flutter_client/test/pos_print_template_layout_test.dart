import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zkteco_flutter_client/models/pos_print_template.dart';
import 'package:zkteco_flutter_client/models/pos_print_template_v2.dart';
import 'package:zkteco_flutter_client/utils/pos_print_template_compiler.dart';
import 'package:zkteco_flutter_client/utils/pos_topping_format.dart';

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

  test('Món có giảm giá in thêm dòng «Giảm giá» (Đ.giá × SL ≠ T.T không còn khó hiểu)', () {
    final out = PosPrintTemplateCompiler.compile(
      template: _tpl([const PosPrintBlock(type: PosPrintBlockType.lineItems)]),
      data: const {},
      lineItems: const [
        {'Ten_Hang_Hoa': 'iPhone 15', 'So_Luong': '1', 'Don_Gia': '28.675.000', 'Thanh_Tien': '28.175.000', 'Chiet_Khau': '500.000'},
        {'Ten_Hang_Hoa': 'Trà sữa', 'So_Luong': '1', 'Don_Gia': '25.000', 'Thanh_Tien': '25.000', 'Chiet_Khau': '0'},
      ],
    );
    final texts = out.printImageLines.map((l) => l.text.trim()).toList();
    expect(texts.where((t) => t.startsWith('Giảm giá')), ['Giảm giá: 500.000']);
    expect(out.html, contains('Giảm giá: 500.000'));
  });

  test('Phiếu bếp combo: món con «- SL tên» in thụt, không gắn «*» như ghi chú', () {
    final note = posKitchenNoteWithComboParts(
      [(name: 'Cà phê sữa', qty: 2), (name: 'Bánh mì', qty: 4)],
      '+ Trân châu\nÍt đá',
    );
    expect(note, '- 2 Cà phê sữa\n- 4 Bánh mì\n+ Trân châu\nÍt đá');
    expect(posKitchenNoteWithComboParts(const [], null), isNull);

    final out = PosPrintTemplateCompiler.compile(
      template: PosPrintTemplateV2(
        paperSize: PosPrintPaperSizes.k80,
        printerProfile: 'generic_k80',
        documentType: PosPrintDocumentTypes.kitchenSlip,
        blocks: const [PosPrintBlock(type: PosPrintBlockType.lineItemsKitchen)],
      ),
      data: const {},
      lineItems: const [],
      kitchenLines: [
        {'Ten_Hang_Hoa': 'Combo sáng', 'So_Luong': '2', 'Ghi_Chu': note!},
      ],
    );
    final texts = out.printImageLines.map((l) => l.text).toList();
    expect(texts, containsAll(['  - 2 Cà phê sữa', '  - 4 Bánh mì', '  + Trân châu', '  * Ít đá']));
  });
}
