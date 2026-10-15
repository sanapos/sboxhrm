import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_print_template.dart';
import 'package:zkteco_flutter_client/models/pos_print_template_v2.dart';
import 'package:zkteco_flutter_client/models/pos_product.dart';
import 'package:zkteco_flutter_client/utils/pos_barcode_print.dart';
import 'package:zkteco_flutter_client/utils/pos_print_template_compiler.dart';
import 'package:zkteco_flutter_client/utils/pos_print_template_v2_presets.dart';

/// Tem thông số / tự soạn: khổ tùy chỉnh, mã QR / mã vạch nội dung tự soạn, trường thông số hàng.
void main() {
  final product = PosProduct(
    id: 'p1',
    productCode: 'HH00321',
    barcode: '8934563123456',
    name: 'Nồi cơm điện',
    brandName: 'Panasonic',
    weight: 2.5,
    weightUnit: 'kg',
    lengthCm: 32,
    widthCm: 24,
    heightCm: 18,
    warrantyMonths: 12,
  );
  final opts = PosBarcodePrintOptions(template: defaultBarcodeLabelTemplate);

  test('Khổ tem tùy chỉnh: id, kích thước, khổ in', () {
    final id = PosPrintPaperSizes.customLabelId(70, 45.5);
    expect(id, 'roll_1_70x45.5');
    expect(PosPrintPaperSizes.isLabelSize(id), isTrue);
    expect((PosPrintPaperSizes.widthMm(id), PosPrintPaperSizes.heightMm(id)), (70.0, 45.5));
    expect(PosPrintPaperSizes.displayLabel(id), contains('tùy chỉnh'));
    final t = posBarcodeLabelTemplateById(id)!;
    expect((t.labelWidthMm, t.labelHeightMm, t.cols), (70.0, 45.5, 1));
    // Khổ cố định vẫn lấy đúng mẫu có sẵn; id vô lý → null.
    expect(posBarcodeLabelTemplateById('roll_1_50x30')!.name, 'Tem 50×30');
    expect(posBarcodeLabelTemplateById('roll_1_5x3'), isNull);
  });

  test('Trường thông số từng mục', () {
    final d = posBarcodeLabelData(product, opts);
    expect(d['Thuong_Hieu'], 'Panasonic');
    expect(d['Khoi_Luong_SP'], '2.5 kg');
    expect(d['Kich_Thuoc'], '32×24×18 cm');
    expect(d['Bao_Hanh'], '12 tháng');
    expect(d['Nha_Cung_Cap'], '');
  });

  test('Khối QR nội dung tự soạn chèn trường; lưu / đọc JSON', () {
    const block = PosPrintBlock(
      type: PosPrintBlockType.barcode,
      barcodeQr: true,
      codeContent: 'https://shop.vn/sp/{Ma_Hang}\n{Bao_Hanh}',
    );
    final back = PosPrintBlock.fromJson(block.toJson());
    expect((back.barcodeQr, back.codeContent), (true, block.codeContent));

    final out = compilePosBarcodeLayout(
      product,
      PosBarcodePrintOptions(
        template: defaultBarcodeLabelTemplate,
        layout: PosPrintTemplateV2(
          paperSize: 'roll_1_60x40',
          printerProfile: PosPrintPrinterProfiles.genericK58,
          documentType: PosPrintDocumentTypes.specLabel,
          blocks: const [block],
        ),
      ),
    );
    final qr = out.steps.whereType<PosPrintCompiledBarcode>().single;
    expect(qr.qr, isTrue);
    expect(qr.data, 'https://shop.vn/sp/HH00321\n12 tháng');
  });

  test('Mã vạch tự soạn: gộp một dòng', () {
    const block = PosPrintBlock(type: PosPrintBlockType.barcode, codeContent: '{Ma_Hang}\n-A');
    final out = compilePosBarcodeLayout(
      product,
      PosBarcodePrintOptions(
        template: defaultBarcodeLabelTemplate,
        layout: PosPrintTemplateV2(
          paperSize: 'roll_1_50x30',
          printerProfile: PosPrintPrinterProfiles.genericK58,
          documentType: PosPrintDocumentTypes.specLabel,
          blocks: const [block],
        ),
      ),
    );
    final bc = out.steps.whereType<PosPrintCompiledBarcode>().single;
    expect((bc.qr, bc.data), (false, 'HH00321 -A'));
  });

  test('Mẫu dựng sẵn tem thông số: bỏ dòng trống, có QR', () {
    final tpl = PosPrintTemplateV2Presets.build(
      documentType: PosPrintDocumentTypes.specLabel,
      paperSize: 'roll_1_60x40',
      printerProfile: PosPrintPrinterProfiles.genericK58,
    );
    expect(tpl.documentType, PosPrintDocumentTypes.specLabel);
    final out = compilePosBarcodeLayout(product, PosBarcodePrintOptions(template: defaultBarcodeLabelTemplate, layout: tpl));
    final lines = out.steps.whereType<PosPrintCompiledLine>().map((l) => l.text).join('\n');
    expect(lines, contains('Bảo hành: 12 tháng'));
    expect(lines, isNot(contains('Thuộc tính'))); // hàng không có thuộc tính → không in dòng trống
    expect(out.steps.whereType<PosPrintCompiledBarcode>().single.qr, isTrue);
    expect(PosPrintDocumentTypes.isProductLabel(PosPrintDocumentTypes.specLabel), isTrue);
  });
}
