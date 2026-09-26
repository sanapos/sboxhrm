import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/models/pos_print_template.dart';
import 'package:zkteco_flutter_client/models/pos_print_template_v2.dart';
import 'package:zkteco_flutter_client/utils/pos_print_template_defaults.dart';
import 'package:zkteco_flutter_client/utils/pos_print_template_v2_codec.dart';
import 'package:zkteco_flutter_client/utils/pos_print_template_v2_presets.dart';
import 'package:zkteco_flutter_client/widgets/pos/pos_print_template_gallery.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Lưới mẫu in: thẻ K80, A4, Word và «Thêm mẫu» dựng không lỗi', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    final v2 = PosPrintTemplateV2Presets.build(
      documentType: PosPrintDocumentTypes.saleInvoice,
      paperSize: PosPrintPaperSizes.k80,
      printerProfile: PosPrintPrinterProfiles.sunmiK80,
      name: 'HĐ K80',
    );
    final templates = [
      PosPrintTemplate(id: '1', name: 'HĐ K80', documentType: PosPrintDocumentTypes.saleInvoice,
          paperSize: PosPrintPaperSizes.k80, htmlContent: PosPrintTemplateV2Codec.encode(v2), isDefault: true),
      PosPrintTemplate(id: '2', name: 'Báo giá A4', documentType: PosPrintDocumentTypes.quote,
          paperSize: PosPrintPaperSizes.a4,
          htmlContent: posPrintDefaultHtml(documentType: PosPrintDocumentTypes.quote, paperSize: PosPrintPaperSizes.a4)),
      const PosPrintTemplate(id: '3', name: 'Hợp đồng khách', documentType: PosPrintDocumentTypes.contract,
          paperSize: PosPrintPaperSizes.a4, htmlContent: '<!--DOCX_TEMPLATE--><p>x</p>', isDocx: true),
    ];
    var edited = '';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GridView.extent(
          padding: const EdgeInsets.all(16),
          maxCrossAxisExtent: 260,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: .62,
          children: [
            for (final t in templates)
              PosPrintTemplateCard(
                template: t,
                onEdit: () => edited = t.id,
                onUse: () {},
                onTestPrint: () {},
                onDuplicate: () {},
                onDelete: () {},
              ),
            PosPrintAddTemplateCard(onTap: () {}),
          ],
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Đang dùng'), findsOneWidget);
    expect(find.text('Dùng mẫu này'), findsNWidgets(2));
    expect(find.text('Word'), findsOneWidget);
    expect(find.text('Thêm mẫu'), findsOneWidget);
    if (const bool.fromEnvironment('SBOX_GOLDEN')) {
      await expectLater(find.byType(GridView), matchesGoldenFile('goldens/print_gallery.png'));
    }
    await tester.tap(find.text('Sửa').first);
    expect(edited, '1');
  });

  testWidgets('Danh sách loại phiếu theo nhóm', (tester) async {
    String? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 240, child: PosPrintDocTypeNav(current: 'SaleInvoice', onSelect: (t) => picked = t)),
      ),
    ));
    expect(find.text('BÁN HÀNG'), findsOneWidget);
    await tester.tap(find.text('Phiếu thu'));
    expect(picked, PosPrintDocumentTypes.cashReceipt);
  });
}
