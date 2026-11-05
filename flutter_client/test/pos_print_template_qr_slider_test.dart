import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_print_template.dart';
import 'package:zkteco_flutter_client/models/pos_print_template_v2.dart';
import 'package:zkteco_flutter_client/utils/pos_print_template_compiler.dart';
import 'package:zkteco_flutter_client/widgets/pos/pos_print_template_v2_editor.dart';

PosPrintTemplateV2 _template(int qrSize) => PosPrintTemplateV2(
      paperSize: PosPrintPaperSizes.k80,
      printerProfile: PosPrintPrinterProfiles.sunmiK80,
      documentType: PosPrintDocumentTypes.saleInvoice,
      frameStyle: PosPrintFrameStyle.none,
      blocks: [PosPrintBlock(type: PosPrintBlockType.vietQr, qrSize: qrSize)],
    );

int _compiledQrSize(PosPrintTemplateV2 template) => PosPrintTemplateCompiler.compile(
      template: template,
      data: const {'Tong_Cong': '150.000'},
      lineItems: const [],
      vietQrImageUrl: 'https://img.vietqr.io/image/970436-0071000123456-compact2.png',
    ).steps.whereType<PosPrintCompiledQr>().single.size;

void main() {
  testWidgets('mẫu cũ lưu cỡ 160: thanh trượt hiện đúng cỡ in, kéo là đổi cỡ in thật', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final old = _template(160);
    PosPrintTemplateV2? edited;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PosPrintTemplateV2Editor(
          template: old,
          compact: false,
          onChanged: (t) => edited = t,
        ),
      ),
    ));
    await tester.pump();

    final sliderFinder = find.byWidgetPredicate(
      (w) => w is Slider && w.max > 220 && w.label != null && w.label!.endsWith('px'),
    );
    await tester.ensureVisible(sliderFinder);
    await tester.pump();

    final slider = tester.widget<Slider>(sliderFinder);
    expect(slider.value.round(), _compiledQrSize(old));
    expect(slider.min, 300);
    expect(slider.max, 400);
    expect(slider.label, '300px');
    expect(find.text('Kích thước QR: 300px'), findsOneWidget);

    await tester.drag(sliderFinder, const Offset(2000, 0));
    await tester.pump();
    expect(edited, isNotNull);
    expect(edited!.blocks.single.qrSize, 400);
    expect(_compiledQrSize(edited!), 400);
  });
}
