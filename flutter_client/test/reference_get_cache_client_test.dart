import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zkteco_flutter_client/services/reference_get_cache_client.dart';

void main() {
  late int calls;
  late DateTime now;
  late ReferenceGetCacheClient client;

  setUp(() {
    calls = 0;
    now = DateTime(2026, 1, 1, 8);
    client = ReferenceGetCacheClient(
      MockClient((req) async {
        calls++;
        return http.Response('{"n":$calls}', 200);
      }),
      clock: () => now,
    );
  });

  final branches = Uri.parse('https://api.test/api/branches');
  final employees = Uri.parse('https://api.test/api/employees');

  test('GET danh mục lần 2 trong TTL lấy từ cache', () async {
    final a = await client.get(branches, headers: {'Authorization': 'Bearer x'});
    final b = await client.get(branches, headers: {'Authorization': 'Bearer x'});
    expect(calls, 1);
    expect(b.body, a.body);
  });

  test('hết TTL thì tải lại', () async {
    await client.get(branches);
    now = now.add(const Duration(seconds: 46));
    await client.get(branches);
    expect(calls, 2);
  });

  test('khác token không dùng chung cache', () async {
    await client.get(branches, headers: {'Authorization': 'Bearer a'});
    await client.get(branches, headers: {'Authorization': 'Bearer b'});
    expect(calls, 2);
  });

  test('lệnh ghi xoá cache', () async {
    await client.get(branches);
    await client.post(branches, body: '{}');
    await client.get(branches);
    expect(calls, 3);
  });

  test('đường dẫn không nằm trong danh sách thì không cache', () async {
    await client.get(employees);
    await client.get(employees);
    expect(calls, 2);
  });

  test('GET trùng đang bay chỉ gọi mạng một lần', () async {
    final r = await Future.wait([client.get(branches), client.get(branches)]);
    expect(calls, 1);
    expect(r[0].body, r[1].body);
  });

  test('lỗi (khác 200) không được cache', () async {
    final c = ReferenceGetCacheClient(MockClient((req) async {
      calls++;
      return http.Response('err', 500);
    }));
    await c.get(branches);
    await c.get(branches);
    expect(calls, 2);
  });
}
