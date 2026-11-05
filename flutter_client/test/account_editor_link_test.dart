import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/accounts_v2/ac_common.dart';
import 'package:zkteco_flutter_client/screens/accounts_v2/ac_editor.dart';
import 'package:zkteco_flutter_client/services/api_service.dart';

/// API giả: ghi lại dữ liệu gửi khi sửa tài khoản.
class _Api implements ApiService {
  Map<String, dynamic>? sent;

  @override
  Future<Map<String, dynamic>> getPosServiceAreas() async => {'isSuccess': true, 'data': const []};

  @override
  Future<Map<String, dynamic>> updateAccount(String id, Map<String, dynamic> data) async {
    sent = data;
    return {'isSuccess': true, 'data': true};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Account _account({String? employeeId}) => Account({
      'id': 'u1',
      'email': 'an@test.local',
      'userName': 'an',
      'firstName': 'An',
      'lastName': 'Nguyễn',
      'fullName': 'Nguyễn An',
      'roles': ['Employee'],
      'employeeId': employeeId,
      'isEmployeeMissing': employeeId == null,
    });

final _employee = AcEmployee({
  'id': 'e1',
  'employeeCode': 'QA01',
  'fullName': 'Hồ Sơ Khác',
  'companyEmail': 'hoso@test.local',
});

Future<void> _pump(WidgetTester tester, _Api api, Account account) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: AcEditor(
        account: account,
        policy: RolePolicy.fallback('Admin'),
        roleOptions: const [],
        employees: [_employee],
        api: api,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tài khoản đã có hồ sơ không hiện ô gắn hồ sơ', (tester) async {
    await _pump(tester, _Api(), _account(employeeId: 'e9'));
    expect(find.text('Liên kết hồ sơ nhân viên'), findsNothing);
  });

  testWidgets('gắn hồ sơ khi sửa: gửi employeeId, giữ nguyên thông tin đăng nhập', (tester) async {
    final api = _Api();
    await _pump(tester, api, _account());
    expect(find.text('Liên kết hồ sơ nhân viên'), findsOneWidget);

    await tester.tap(find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == 'Tìm theo tên hoặc mã nhân viên'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hồ Sơ Khác · QA01').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Lưu'));
    await tester.pump();

    expect(api.sent?['employeeId'], 'e1');
    expect(api.sent?['email'], 'an@test.local');
    expect(api.sent?['firstName'], 'An');
  });

  testWidgets('sửa mà không chọn hồ sơ thì không gửi employeeId', (tester) async {
    final api = _Api();
    await _pump(tester, api, _account());
    await tester.tap(find.text('Lưu'));
    await tester.pump();
    expect(api.sent, isNotNull);
    expect(api.sent!.containsKey('employeeId'), isFalse);
  });

  test('tài khoản chưa có hồ sơ ghi đúng là chưa gắn', () {
    expect(_account().hrIssueLabel, 'Chưa gắn hồ sơ nhân viên');
  });
}
