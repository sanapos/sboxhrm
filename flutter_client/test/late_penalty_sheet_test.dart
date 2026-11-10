import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/overview/late_penalty_sheet.dart';
import 'package:zkteco_flutter_client/services/api_service.dart';

/// Tổng quan → «Đi trễ hôm nay»: phiếu phạt từng người, duyệt từng phiếu và duyệt nhanh tất cả.
class _FakePenaltyApi implements ApiService {
  final approved = <String>[];
  final tickets = [
    {'id': 't1', 'employeeId': 'e1', 'ticketCode': 'PP-001', 'amount': 50000, 'status': 'Pending', 'type': 'Late'},
    {'id': 't2', 'employeeId': 'e2', 'ticketCode': 'PP-002', 'amount': 100000, 'status': 'Pending', 'type': 'Late'},
    {'id': 't3', 'employeeId': 'e3', 'ticketCode': 'PP-003', 'amount': 50000, 'status': 'Approved', 'type': 'Late'},
  ];

  @override
  Future<Map<String, dynamic>> getPenaltyTickets({
    int page = 1,
    int pageSize = 20,
    String? employeeId,
    String? status,
    String? type,
    DateTime? fromDate,
    DateTime? toDate,
    bool includeManual = false,
  }) async =>
      {
        'isSuccess': true,
        'data': {'items': [for (final t in tickets) Map<String, dynamic>.from(t)]},
      };

  @override
  Future<Map<String, dynamic>> approvePenaltyTicket(String id, {String? note}) async {
    approved.add(id);
    return {'isSuccess': true, 'data': {'id': id}};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget _host(_FakePenaltyApi api, {bool canApprove = true}) => MaterialApp(
      home: Scaffold(
        body: LatePenaltySheet(
          api: api,
          canApprove: canApprove,
          lateRows: const [
            {'employeeId': 'e1', 'fullName': 'Nguyễn An', 'checkIn': '08:20', 'lateMinutes': 15, 'shiftStart': '08:00', 'shiftEnd': '17:00'},
            {'employeeId': 'e2', 'fullName': 'Trần Bình', 'checkIn': '08:40', 'lateMinutes': 35},
            {'employeeId': 'e3', 'fullName': 'Lê Chi', 'checkIn': '08:16', 'lateMinutes': 11},
            {'employeeId': 'e4', 'fullName': 'Phạm Dũng', 'checkIn': '08:09', 'lateMinutes': 4},
          ],
        ),
      ),
    );

void main() {
  testWidgets('hiện phiếu từng người, duyệt một phiếu', (t) async {
    final api = _FakePenaltyApi();
    await t.pumpWidget(_host(api));
    await t.pumpAndSettle();
    expect(find.text('Nguyễn An'), findsOneWidget);
    expect(find.textContaining('PP-001'), findsOneWidget);
    expect(find.text('Đã duyệt'), findsOneWidget);
    expect(find.textContaining('Chưa có phiếu phạt'), findsOneWidget); // Phạm Dũng
    expect(find.text('Duyệt nhanh tất cả (2)'), findsOneWidget);
    // Người trễ nhiều nhất lên đầu: Trần Bình (PP-002) → nút «Duyệt» đầu tiên.
    await t.tap(find.text('Duyệt').first);
    await t.pumpAndSettle();
    expect(api.approved, ['t2']);
    expect(find.text('Duyệt nhanh tất cả (1)'), findsOneWidget);
  });

  testWidgets('duyệt nhanh tất cả phiếu chờ', (t) async {
    final api = _FakePenaltyApi();
    await t.pumpWidget(_host(api));
    await t.pumpAndSettle();
    await t.tap(find.text('Duyệt nhanh tất cả (2)'));
    await t.pumpAndSettle();
    await t.tap(find.text('Duyệt tất cả'));
    await t.pumpAndSettle();
    expect(api.approved.toSet(), {'t1', 't2'});
    expect(find.text('Chờ duyệt'), findsNothing);
    expect(find.textContaining('Duyệt nhanh tất cả'), findsNothing);
  });

  testWidgets('không có quyền duyệt → không có nút', (t) async {
    final api = _FakePenaltyApi();
    await t.pumpWidget(_host(api, canApprove: false));
    await t.pumpAndSettle();
    expect(find.text('Duyệt'), findsNothing);
    expect(find.textContaining('Duyệt nhanh'), findsNothing);
    expect(find.text('Chờ duyệt'), findsNWidgets(2));
  });
}
