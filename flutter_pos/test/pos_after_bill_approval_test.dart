import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sbox_pos/models/pos_after_bill_approval_config.dart';
import 'package:sbox_pos/models/pos_sell_industry.dart';
import 'package:sbox_pos/services/api_service.dart';

/// «Sau tạm tính cần quản lý duyệt»: cấu hình trong ExtraJson + ApiService tự hỏi duyệt rồi gửi lại kèm mã.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    ApiService.onPosManagerApproval = null;
    ApiService.setPosApprovalToken(null);
  });

  test('cấu hình chỉ có tác dụng khi bật tạm tính, giữ khóa khác trong ExtraJson', () {
    final merged = PosAfterBillApprovalConfig.merge('{"cancelReturnReason":{"enabled":true}}', true);
    expect(PosAfterBillApprovalConfig.enabledIn(merged), isTrue);
    expect((jsonDecode(merged) as Map)['cancelReturnReason'], {'enabled': true});
    expect(PosAfterBillApprovalConfig.enabledIn(PosAfterBillApprovalConfig.merge(merged, false)), isFalse);
    expect(PosAfterBillApprovalConfig.enabledIn('hỏng{'), isFalse);
    final on = PosStoreSellSettingsDto(id: 's', sellProfile: PosSellProfile.restaurant, allowProvisionalBill: true, extraJson: '{"afterBillApproval":{"enabled":true}}');
    final offBill = PosStoreSellSettingsDto(id: 's', sellProfile: PosSellProfile.restaurant, allowProvisionalBill: false, extraJson: '{"afterBillApproval":{"enabled":true}}');
    expect(PosAfterBillApprovalConfig.isActive(on), isTrue);
    expect(PosAfterBillApprovalConfig.isActive(offBill), isFalse);
    expect(PosAfterBillApprovalConfig.isManagerRole('StoreOwner'), isTrue);
    expect(PosAfterBillApprovalConfig.isManagerRole('Cashier'), isFalse);
  });

  test('bị chặn → quản lý duyệt → gửi lại kèm X-Pos-Approval', () async {
    final seen = <String?>[];
    final client = MockClient((req) async {
      seen.add(req.headers['X-Pos-Approval']);
      final ok = req.headers['X-Pos-Approval'] == 'tok-1';
      return http.Response(
        jsonEncode(ok
            ? {'isSuccess': true, 'data': {'deleted': true}}
            : {'isSuccess': false, 'errors': ['Cần quản lý duyệt: xóa đơn sau khi đã in tạm tính cho khách.']}),
        ok ? 200 : 400,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    String? asked;
    ApiService.onPosManagerApproval = (msg) async {
      asked = msg;
      ApiService.setPosApprovalToken('tok-1');
      return true;
    };
    final res = await http.runWithClient(() => ApiService().deletePosSale('o1'), () => client);
    expect(res['isSuccess'], isTrue);
    expect(asked, startsWith('Cần quản lý duyệt'));
    expect(seen, [null, 'tok-1']);
    expect(ApiService.hasPosApprovalToken, isTrue);
  });

  test('quản lý không duyệt → không gửi lại, trả lỗi để màn giữ nguyên', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return http.Response(
        jsonEncode({'isSuccess': false, 'errors': ['Cần quản lý duyệt: hủy món sau khi đã in tạm tính cho khách.']}),
        400,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    ApiService.onPosManagerApproval = (_) async => false;
    final res = await http.runWithClient(() => ApiService().createPosKitchenVoids({'lines': []}), () => client);
    expect(ApiService.isPosApprovalDenied(res), isTrue);
    expect(calls, 1);
  });
}
