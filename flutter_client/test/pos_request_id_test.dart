import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zkteco_flutter_client/services/api_service.dart';
import 'package:zkteco_flutter_client/utils/pos_request_id.dart';

/// Chống trùng khi mạng lỗi: app tự gửi lại lệnh in / báo bếp với CÙNG mã, để server
/// trả lại kết quả lần trước thay vì tạo lệnh thứ hai.
void main() {
  test('Mã ngẫu nhiên 32 hex, không trùng', () {
    final ids = {for (var i = 0; i < 500; i++) PosRequestId.newId()};
    expect(ids.length, 500);
    expect(ids.every((s) => RegExp(r'^[0-9a-f]{32}$').hasMatch(s)), isTrue);
  });

  test('Nhận diện lỗi mạng (gửi lại an toàn) và lỗi khác (không gửi lại)', () {
    expect(PosRequestId.isNetworkError(TimeoutException('x')), isTrue);
    expect(PosRequestId.isNetworkError(http.ClientException('Connection reset by peer')), isTrue);
    expect(PosRequestId.isNetworkError(const FormatException('bad json')), isFalse);
  });

  test('Tạo lệnh in: mạng rớt lần 1 → gửi lại cùng clientRequestId', () async {
    final keys = <String>[];
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      keys.add((jsonDecode(req.body) as Map)['clientRequestId'] as String);
      if (calls == 1) throw http.ClientException('Connection reset by peer');
      return http.Response(
        jsonEncode({'isSuccess': true, 'data': {'jobId': 'j1', 'status': 'Completed'}}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final res = await http.runWithClient(
      () => ApiService().createPosPrintJob(
        documentType: 'KitchenSlip',
        payloadFormat: 'EscPosBase64',
        payload: 'AAAA',
      ),
      () => client,
    );
    expect(res['isSuccess'], isTrue);
    expect(calls, 2);
    expect(keys[0], keys[1]);
  });

  test('Tạo lệnh in: lỗi nghiệp vụ (HTTP 400) → không tự gửi lại', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return http.Response(jsonEncode({'isSuccess': false, 'message': 'Chưa cấu hình máy in'}), 400,
          headers: {'content-type': 'application/json'});
    });
    final res = await http.runWithClient(
      () => ApiService().createPosPrintJob(documentType: 'KitchenSlip', payloadFormat: 'EscPosBase64', payload: 'AAAA'),
      () => client,
    );
    expect(res['isSuccess'], isFalse);
    expect(calls, 1);
  });

  test('Báo bếp: mạng rớt 2 lần → lần 3 thành công, cả 3 lần cùng requestId', () async {
    final keys = <String>[];
    final client = MockClient((req) async {
      keys.add((jsonDecode(req.body) as Map)['requestId'] as String);
      if (keys.length < 3) throw TimeoutException('slow');
      return http.Response(
        jsonEncode({'isSuccess': true, 'data': {'sentLines': 1, 'replayed': true}}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final res = await http.runWithClient(
      () => ApiService().kitchenSendPosResourceSession('s1', requestId: 'ks0123456789abcdef'),
      () => client,
    );
    expect(res['isSuccess'], isTrue);
    expect(keys, ['ks0123456789abcdef', 'ks0123456789abcdef', 'ks0123456789abcdef']);
  });
}
