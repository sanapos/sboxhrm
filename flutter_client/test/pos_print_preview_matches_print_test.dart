import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zkteco_flutter_client/models/pos_print_template.dart';
import 'package:zkteco_flutter_client/models/pos_print_template_v2.dart';
import 'package:zkteco_flutter_client/utils/pos_print_code_lines.dart';
import 'package:zkteco_flutter_client/utils/pos_print_template_compiler.dart';
import 'package:zkteco_flutter_client/utils/pos_print_template_renderer.dart';
import 'package:zkteco_flutter_client/utils/pos_thermal_bitmap.dart';
import 'package:zkteco_flutter_client/utils/pos_thermal_printer_service.dart';
import 'package:zkteco_flutter_client/utils/pos_thermal_printer_settings.dart';

/// Ghép các ảnh GS v 0 trong dữ liệu ESC/POS thành lưới điểm (true = có mực).
List<List<bool>> _rasterRows(List<int> bytes) {
  final rows = <List<bool>>[];
  for (var i = 0; i + 7 < bytes.length; i++) {
    if (bytes[i] != 0x1D || bytes[i + 1] != 0x76 || bytes[i + 2] != 0x30) continue;
    final wb = bytes[i + 4] + bytes[i + 5] * 256;
    final h = bytes[i + 6] + bytes[i + 7] * 256;
    final body = bytes.sublist(i + 8, i + 8 + wb * h);
    for (var y = 0; y < h; y++) {
      rows.add([
        for (var x = 0; x < wb * 8; x++) (body[y * wb + (x >> 3)] & (0x80 >> (x & 7))) != 0,
      ]);
    }
    i += 7 + wb * h;
  }
  return rows;
}

PosPrintTemplateV2 _template(String paper) => PosPrintTemplateV2(
      paperSize: paper,
      printerProfile: 'generic',
      documentType: PosPrintDocumentTypes.saleInvoice,
      frameStyle: PosPrintFrameStyle.rounded,
      blocks: const [
        PosPrintBlock(type: PosPrintBlockType.field, field: 'Ten_Cua_Hang', style: PosPrintTextStyle(fontSize: 36, bold: true, align: PosPrintTextAlign.center)),
        PosPrintBlock(type: PosPrintBlockType.pair, leftField: 'Ma_Don_Hang', rightField: 'Ngay'),
        PosPrintBlock(type: PosPrintBlockType.divider),
        PosPrintBlock(type: PosPrintBlockType.lineItems, showColumnHeader: true),
        PosPrintBlock(type: PosPrintBlockType.totals, fields: ['Tong_Tien_Hang', 'Tong_Cong']),
        PosPrintBlock(type: PosPrintBlockType.vietQr, qrSize: 260),
        PosPrintBlock(type: PosPrintBlockType.barcode, field: 'Ma_Don_Hang', barcodeHeight: 60),
        PosPrintBlock(type: PosPrintBlockType.barcode, barcodeQr: true, codeContent: 'https://sbox.sana.vn', barcodeHeight: 80, barcodeShowText: false),
        PosPrintBlock(type: PosPrintBlockType.text, text: 'Cảm ơn quý khách!', style: PosPrintTextStyle(align: PosPrintTextAlign.center)),
      ],
    );

Future<void> _expectPreviewEqualsPrint(String paper, int paperMm) async {
  final tpl = _template(paper);
  final output = PosPrintTemplateCompiler.compile(
    template: tpl,
    data: posPrintSampleData(documentType: tpl.documentType),
    lineItems: posPrintSampleLines(),
    vietQrImageUrl: 'sample',
  );
  final dots = PosThermalBitmapEncoder.paperDots(paperMm);

  // Bản xem trước của trình soạn mẫu.
  final lines = await posPrintOutputImageLines(output, paperDots: dots);
  final preview = await PosThermalBitmapEncoder.receiptPreview(
    lines,
    paperDots: dots,
    frameStyle: output.frameStyle,
    frameInsetMm: output.frameInsetMm,
    frameMarginMm: output.frameMarginMm,
    sidePaddingMm: output.sidePaddingMm,
    monochrome: true,
  );
  expect(preview, isNotNull);
  final shown = img.decodePng(preview!.png)!;
  expect(shown.width, dots);

  // Bytes thật gửi máy in LAN / USB (chế độ ảnh).
  final bytes = await PosThermalPrinterService.buildCompiledEscPosBytes(
    output,
    settings: PosThermalPrinterSettings(enabled: true, textMode: PosThermalTextMode.image, paperSize: paper),
  );
  final printed = _rasterRows(bytes);
  expect(printed, isNotEmpty);
  expect(printed.first.length, dots);
  // Máy in cắt bớt phần trắng cuối; phần còn lại phải trùng từng điểm.
  expect(printed.length, lessThanOrEqualTo(shown.height));
  var diff = 0;
  for (var y = 0; y < shown.height; y++) {
    for (var x = 0; x < dots; x++) {
      final ink = shown.getPixel(x, y).r < 128;
      final inkPrinted = y < printed.length && printed[y][x];
      if (ink != inkPrinted) diff++;
    }
  }
  expect(diff, 0, reason: 'Khổ $paper: $diff điểm khác nhau giữa xem trước và bản in');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Xem trước K80 trùng từng điểm với bản in (chữ, khung, VietQR, mã vạch, QR)', () async {
    await _expectPreviewEqualsPrint(PosPrintPaperSizes.k80, 80);
  });

  test('Xem trước K58 trùng từng điểm với bản in', () async {
    await _expectPreviewEqualsPrint(PosPrintPaperSizes.k58, 58);
  });

  test('Mã vạch là ảnh vạch thật (không còn in mã thành dòng chữ)', () async {
    final lines = await posPrintCodeStepLines(
      const PosPrintCompiledBarcode(data: 'HD000123', height: 60),
      paperDots: 576,
    );
    expect(lines.first.imageBytes, isNotNull);
    expect(lines.first.imageWidthDots, greaterThan(100));
    expect(lines.last.text, 'HD000123');
  });
}
