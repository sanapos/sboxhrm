import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zkteco_flutter_client/services/auth_retry_client.dart';

void main() {
  tearDown(() {
    AuthRetryClient.refreshAccessToken = null;
    AuthRetryClient.currentAccessToken = null;
  });

  MockClient serverAccepting(String goodToken, List<String> seen) => MockClient((req) async {
        seen.add('${req.method} ${req.headers['Authorization']} ${req.body}');
        return req.headers['Authorization'] == 'Bearer $goodToken'
            ? http.Response('ok', 200)
            : http.Response('', 401);
      });

  test('401 → làm mới token rồi gửi lại cùng body', () async {
    final seen = <String>[];
    var refreshes = 0;
    AuthRetryClient.currentAccessToken = () => 'old';
    AuthRetryClient.refreshAccessToken = () async {
      refreshes++;
      return 'new';
    };
    final client = AuthRetryClient(serverAccepting('new', seen));
    final res = await client.post(Uri.parse('http://x/api/pos/quotes'),
        headers: {'Authorization': 'Bearer old'}, body: '{"a":1}');
    expect(res.statusCode, 200);
    expect(refreshes, 1);
    expect(seen, ['POST Bearer old {"a":1}', 'POST Bearer new {"a":1}']);
  });

  test('token đã được làm mới bởi request khác → gửi lại không làm mới lần 2', () async {
    final seen = <String>[];
    var refreshes = 0;
    AuthRetryClient.currentAccessToken = () => 'new';
    AuthRetryClient.refreshAccessToken = () async {
      refreshes++;
      return 'newer';
    };
    final client = AuthRetryClient(serverAccepting('new', seen));
    final res = await client.get(Uri.parse('http://x/api/pos/quotes'), headers: {'Authorization': 'Bearer old'});
    expect(res.statusCode, 200);
    expect(refreshes, 0);
  });

  test('làm mới hỏng → trả nguyên 401, không gửi lại', () async {
    final seen = <String>[];
    AuthRetryClient.currentAccessToken = () => 'old';
    AuthRetryClient.refreshAccessToken = () async => null;
    final client = AuthRetryClient(serverAccepting('new', seen));
    final res = await client.get(Uri.parse('http://x/api/pos/quotes'), headers: {'Authorization': 'Bearer old'});
    expect(res.statusCode, 401);
    expect(seen.length, 1);
  });

  test('không đụng request đăng nhập / làm mới', () async {
    final seen = <String>[];
    var refreshes = 0;
    AuthRetryClient.refreshAccessToken = () async {
      refreshes++;
      return 'new';
    };
    final client = AuthRetryClient(serverAccepting('new', seen));
    final res = await client.post(Uri.parse('http://x/api/auth/refresh'), headers: {'Authorization': 'Bearer old'});
    expect(res.statusCode, 401);
    expect(refreshes, 0);
  });
}
