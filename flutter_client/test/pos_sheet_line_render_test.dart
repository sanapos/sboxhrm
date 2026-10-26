import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_sale_order.dart';
import 'package:zkteco_flutter_client/utils/pos_print_template_renderer.dart';

PosSaleOrderLine _line({String? code}) => PosSaleOrderLine(
      productId: '3abcef60-1111-2222-3333-444455556666',
      productName: 'Hàng QA A',
      productCode: code,
      unitName: 'Cái',
      qty: 1,
      unitPrice: 50000,
      lineTotal: 50000,
    );

String _render(String row, List<PosSaleOrderLine> lines) =>
    renderPosPrintTemplateHtml(
      '<table><!--BEGIN_ITEMS-->$row<!--END_ITEMS--></table>',
      data: const {},
      lineItems: buildSaleOrderPrintLines(lines),
      wrapDocument: false,
    );

void main() {
  test('Mã hàng lấy productCode, thiếu thì lùi về 8 ký tự id', () {
    expect(buildSaleOrderPrintLines([_line(code: 'SP0001')]).single['Ma_Hang'],
        'SP0001');
    expect(buildSaleOrderPrintLines([_line()]).single['Ma_Hang'], '3abcef60');
  });

  test('productCode đọc từ JSON chi tiết đơn', () {
    final l = PosSaleOrderLine.fromJson({
      'productId': 'p1',
      'productName': 'A',
      'productCode': 'SP0009',
    });
    expect(l.productCode, 'SP0009');
  });

  test('Mẫu có cột ĐVT → tên không kèm (ĐVT); mẫu nhiệt giữ nguyên', () {
    final sheet = _render(
        '<tr><td>{Ten_Hang_Hoa}</td><td>{Don_Vi_Tinh}</td></tr>', [_line()]);
    expect(sheet, contains('<td>Hàng QA A</td><td>Cái</td>'));
    final thermal = _render('<tr><td>{Ten_Hang_Hoa}</td></tr>', [_line()]);
    expect(thermal, contains('Hàng QA A (Cái)'));
  });
}
