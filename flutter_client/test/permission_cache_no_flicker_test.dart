import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/providers/permission_provider.dart';

/// Mở app: menu dựng từ quyền lần trước (không «bung» dần khi API trả về);
/// API trả cùng quyền → không vẽ lại; quyền đổi → vẽ lại một lần.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  List<Map<String, dynamic>> perms(bool payroll) => [
        {'module': 'Attendance', 'canView': true},
        {'module': 'Leave', 'canView': true, 'canCreate': true},
        {'module': 'Payroll', 'canView': payroll},
      ];

  Future<(PermissionProvider, List<bool>, Completer<void>)> start(bool apiPayroll) async {
    final gate = Completer<void>();
    final client = MockClient((req) async {
      await gate.future;
      return http.Response(jsonEncode({'isSuccess': true, 'data': perms(apiPayroll)}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });
    final p = PermissionProvider();
    final seen = <bool>[];
    p.addListener(() => seen.add(p.canView('Payroll')));
    unawaited(http.runWithClient(
        () => p.loadPermissions(role: 'Manager', freshSession: true, cacheKey: 'u1:s1'), () => client));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return (p, seen, gate);
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'perm_cache_v1:u1:s1': jsonEncode({'role': 'Manager', 'p': {'Attendance': 'V', 'Leave': 'VC', 'Payroll': ''}}),
    });
  });

  test('Có quyền ngay từ bản lưu, API trả giống → không vẽ lại', () async {
    final (p, seen, gate) = await start(false);
    expect(p.isLoaded, isTrue, reason: 'chưa chờ API đã có quyền');
    expect(p.canView('Leave'), isTrue);
    expect(seen, [false]); // một lần từ bản lưu
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(seen, [false], reason: 'quyền như cũ → không notify');
  });

  test('Quyền đổi → vẽ lại một lần và lưu bản mới', () async {
    final (p, seen, gate) = await start(true);
    gate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(seen, [false, true]);
    expect(p.canView('Payroll'), isTrue);
    final saved = jsonDecode((await SharedPreferences.getInstance()).getString('perm_cache_v1:u1:s1')!) as Map;
    expect((saved['p'] as Map)['Payroll'], 'V');
  });

  test('Bản lưu của vai trò khác → bỏ qua', () async {
    final gate = Completer<void>();
    final p = PermissionProvider();
    unawaited(http.runWithClient(
        () => p.loadPermissions(role: 'Employee', freshSession: true, cacheKey: 'u1:s1'),
        () => MockClient((_) async {
              await gate.future;
              return http.Response(jsonEncode({'isSuccess': true, 'data': []}), 200);
            })));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(p.isLoaded, isFalse);
    gate.complete();
  });
}
