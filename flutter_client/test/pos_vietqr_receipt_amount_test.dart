import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:zkteco_flutter_client/models/cash_transaction.dart';
import 'package:zkteco_flutter_client/models/pos_sale_order.dart';
import 'package:zkteco_flutter_client/utils/pos_thermal_printer_service.dart';
import 'package:zkteco_flutter_client/utils/pos_thermal_printer_settings.dart';
import 'package:zkteco_flutter_client/utils/pos_vietqr_helper.dart';

const _caption = 'Quét VietQR thanh toán';

final _account = BankAccount(
  id: 'b1',
  accountName: 'CUA HANG QA',
  accountNumber: '0071000123456',
  bankCode: '970436',
  bankName: 'Vietcombank',
);

PosSaleOrder _order({
  double total = 1000000,
  double vat = 100000,
  double surcharge = 50000,
  double ship = 30000,
  double paid = 0,
  double balanceDue = 0,
}) =>
    PosSaleOrder(
      id: 'o1',
      orderNo: 'HD020112260001',
      subTotal: total,
      total: total,
      vatAmount: vat,
      surchargeAmount: surcharge,
      deliveryFee: ship,
      paidAmount: paid,
      balanceDue: balanceDue,
    );

/// Dòng ngay sau chú thích QR trong dữ liệu ESC/POS thật của lối in không theo mẫu.
Future<String> _printedAmountLine(PosSaleOrder order, String qrUrl) async {
  final bytes = await PosThermalPrinterService.buildSaleOrderEscPosBytes(
    order,
    settings: const PosThermalPrinterSettings(
      enabled: true,
      textMode: PosThermalTextMode.utf8,
    ),
    vietQrImageUrl: qrUrl,
  );
  final text = utf8.decode(bytes, allowMalformed: true);
  final at = text.indexOf('$_caption\n');
  expect(at, greaterThanOrEqualTo(0), reason: 'Không thấy dòng chú thích QR');
  return text.substring(at + _caption.length + 1).split('\n').first;
}

/// Số tiền mã QR thật sự đòi, viết theo định dạng của bản in.
String _amountDemandedByQr(String qrUrl) {
  final amount = int.parse(Uri.parse(qrUrl).queryParameters['amount']!);
  return '${NumberFormat('#,##0', 'vi_VN').format(amount)} đ';
}

Future<void> _expectLineMatchesQr(PosSaleOrder order, String expected) async {
  final url = PosVietQrHelper.qrImageUrlForOrder(order, accounts: [_account])!;
  expect(_amountDemandedByQr(url), expected);
  expect(await _printedAmountLine(order, url), expected);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('dòng tiền cạnh «$_caption» khớp số tiền QR đòi', () {
    test('đã trả đủ → tổng gồm VAT + phụ thu + phí giao, không phải tiền hàng', () async {
      await _expectLineMatchesQr(_order(paid: 1180000), '1.180.000 đ');
    });

    test('còn nợ → đúng phần còn lại', () async {
      await _expectLineMatchesQr(_order(paid: 500000, balanceDue: 680000), '680.000 đ');
    });

    test('nợ lẻ dưới 0,5đ coi như hết nợ → tổng phải trả', () async {
      await _expectLineMatchesQr(_order(paid: 1179999.6, balanceDue: 0.4), '1.180.000 đ');
    });

    test('tiền lẻ làm tròn giống mã QR', () async {
      await _expectLineMatchesQr(
        _order(total: 32399.7, vat: 0, surcharge: 0, ship: 0),
        '32.400 đ',
      );
    });
  });

  test('tổng bằng 0 → QR đòi số đã trả', () {
    final order = _order(total: 0, vat: 0, surcharge: 0, ship: 0, paid: 25000);
    expect(PosVietQrHelper.qrAmountForOrder(order), 25000);
  });
}
