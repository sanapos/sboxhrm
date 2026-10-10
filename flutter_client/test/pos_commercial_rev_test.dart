import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_print_template.dart';
import 'package:zkteco_flutter_client/utils/pos_price_list_resolver.dart';
import 'package:zkteco_flutter_client/utils/pos_print_template_defaults.dart';

void main() {
  group('Phiên bản mẫu chuẩn A4', () {
    test('mẫu chuẩn mới mang số phiên bản hiện tại', () {
      final html = posPrintDefaultHtml(
        documentType: PosPrintDocumentTypes.quote,
        paperSize: PosPrintPaperSizes.a4,
      );
      expect(posCommercialBaseRev(html), kPosCommercialBaseRev);
    });

    test('mẫu cửa hàng lưu trước khi có đánh số = phiên bản 1 (được mời cập nhật)', () {
      const old = '<!--POS_A4_V9 paper="A4" mt="12" mr="12" mb="12" ml="12"--><div>{Ten_Hang_Hoa}</div>';
      expect(posCommercialBaseRev(old), 1);
      expect(posCommercialBaseRev(old) < kPosCommercialBaseRev, isTrue);
    });

    test('đổi lề / lưu lại không làm mất số phiên bản', () {
      final html = posPrintDefaultHtml(
        documentType: PosPrintDocumentTypes.contract,
        paperSize: PosPrintPaperSizes.a4,
      );
      final setup = PosCommercialPageSetup.parse(html).copyWith(leftMm: 20);
      final saved = setup.applyToHtml(html);
      expect(posCommercialBaseRev(saved), kPosCommercialBaseRev);
      expect(PosCommercialPageSetup.parse(saved).leftMm, 20);
    });
  });

  group('Giá theo bảng giá trên báo giá', () {
    final overrides = buildPosPriceOverrideMap([
      {'productId': 'p1', 'price': 80000},
      {'productId': 'p2', 'unitId': 'thung', 'price': 230000},
    ]);

    test('hàng có trong bảng giá lấy giá bảng', () {
      expect(resolvePosPriceListPrice(overrides, productId: 'p1'), 80000);
      expect(resolvePosPriceListPrice(overrides, productId: 'p2', unitId: 'thung'), 230000);
    });

    test('hàng / đơn vị không có trong bảng → null (dùng giá bán chung)', () {
      expect(resolvePosPriceListPrice(overrides, productId: 'p3'), isNull);
      expect(resolvePosPriceListPrice(overrides, productId: 'p2', unitId: 'lon'), isNull);
    });
  });
}
