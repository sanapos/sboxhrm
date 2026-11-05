import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zkteco_flutter_client/models/user.dart';
import 'package:zkteco_flutter_client/providers/auth_provider.dart';
import 'package:zkteco_flutter_client/widgets/sign_out_route_reset.dart';

/// Hết phiên khi đang ở trang con phải về màn gốc, không được để người dùng kẹt ở trang đó.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('đăng xuất ở trang con thì gỡ hết trang đã mở', (t) async {
    final api = MockClient((_) async => http.Response(jsonEncode({'isSuccess': true, 'data': {}}), 200));
    await http.runWithClient(() async {
      final auth = AuthProvider()
        ..debugSetUser(User(id: 'u1', employeeId: 'e1', email: 'a@b.vn', fullName: 'A', role: 'Manager', storeId: 's1'));
      expect(auth.isAuthenticated, isTrue);
      await t.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: const MaterialApp(home: SignOutRouteReset(child: Text('goc'))),
      ));
      Navigator.of(t.element(find.text('goc'))).push(MaterialPageRoute<void>(builder: (_) => const Text('con')));
      await t.pumpAndSettle();
      expect(find.text('con'), findsOneWidget);

      await t.runAsync(auth.logout);
      await t.pump();
      await t.pumpAndSettle();
      expect(auth.isAuthenticated, isFalse);
      expect(find.text('con'), findsNothing);
      expect(find.text('goc'), findsOneWidget);
    }, () => api);
  });
}
