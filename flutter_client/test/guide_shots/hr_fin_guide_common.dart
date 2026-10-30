import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zkteco_flutter_client/screens/hr_finance/hr_fin_common.dart';
import 'package:zkteco_flutter_client/screens/hr_finance/hr_finance_hub_screen.dart';

/// Dữ liệu mẫu chung cho ảnh hướng dẫn Tài chính nhân sự (phạt, ứng lương, thưởng, thu chi).
/// Theo test/hr_finance_hub_test.dart: các khoản trong tháng hiện tại của một quán cà phê.

final _now = DateTime.now();
String _day(int d) => DateTime(_now.year, _now.month, d.clamp(1, 28), 9).toIso8601String();

Map<String, dynamic> _item(String kind, String id, String emp, String code, String title, double amount,
        {String dir = 'in', String status = 'Pending', String? action, int day = 5, String? sub, String? settlement,
        int dispute = 0, String? reason, String? ticketCode}) =>
    {
      'kind': kind, 'id': id, 'employeeId': 'e-$code', 'employeeName': emp, 'employeeCode': code,
      'department': 'Quầy pha chế', 'title': title, 'subtitle': sub, 'amount': amount, 'direction': dir, 'status': status,
      'date': _day(day), 'action': action, 'settlement': settlement, 'evidence': const <String>[], 'disputeStatus': dispute,
      'disputeReason': reason, 'code': ticketCode,
    };

final _inbox = [
  _item('ticket', 't1', 'Phạm Thu Hà', 'NV004', 'Đi trễ 25 phút', 50000, dir: 'out', status: 'Pending', action: 'approve', day: 12,
      settlement: 'salary', ticketCode: 'PP-0012'),
  _item('advance', 'a1', 'Nguyễn Văn An', 'NV001', 'Ứng lương — Đóng học phí cho con', 3000000, action: 'approve', day: 14,
      sub: 'Trừ lương kỳ ${_now.month.toString().padLeft(2, '0')}/${_now.year}, góp 2 kỳ'),
  _item('bonus', 'b1', 'Trần Minh Khoa', 'NV002', 'Doanh số vượt chỉ tiêu tháng', 1500000, action: 'approve', day: 13, settlement: 'salary'),
  _item('penalty', 'p1', 'Lê Quốc Bảo', 'NV003', 'Làm vỡ ly thủy tinh', 120000, dir: 'out', action: 'approve', day: 11),
  _item('advance', 'a2', 'Đỗ Hải Nam', 'NV005', 'Ứng lương — Sửa xe', 2000000, status: 'Approved', action: 'pay', day: 9),
];

final _rewards = [
  _item('bonus', 'b2', 'Trần Minh Khoa', 'NV002', 'Khách hàng khen trên fanpage', 500000, status: 'Completed', day: 6, settlement: 'salary'),
  _item('bonus', 'b3', 'Nguyễn Văn An', 'NV001', 'Hoàn thành xuất sắc kiểm kê', 800000, status: 'Completed', day: 4, settlement: 'cash'),
  _item('penalty', 'p2', 'Lê Quốc Bảo', 'NV003', 'Không mặc đồng phục', 100000, dir: 'out', status: 'Completed', day: 7, settlement: 'salary'),
  _item('ticket', 't2', 'Phạm Thu Hà', 'NV004', 'Đi trễ 12 phút', 30000, dir: 'out', status: 'AutoApproved', day: 3, settlement: 'salary',
      ticketCode: 'PP-0003'),
  _item('ticket', 't3', 'Đỗ Hải Nam', 'NV005', 'Quên chấm công', 100000, dir: 'out', status: 'Approved', day: 2, settlement: 'salary',
      ticketCode: 'PP-0002'),
  ..._inbox.where((e) => e['kind'] == 'bonus' || e['kind'] == 'penalty' || e['kind'] == 'ticket'),
];

final _advances = [
  ..._inbox.where((e) => e['kind'] == 'advance'),
  _item('advance', 'a3', 'Võ Thị Mai', 'NV006', 'Ứng lương — Viện phí', 2500000, status: 'Paid', day: 3, sub: 'Trừ lương kỳ này'),
  _item('advance', 'a4', 'Lê Quốc Bảo', 'NV003', 'Ứng lương — Việc riêng', 1000000, status: 'Paid', day: 2, sub: 'Trừ lương kỳ này'),
];

final _summary = {
  'year': _now.year, 'month': _now.month, 'advancePaid': 5500000, 'advanceToDeduct': 4500000, 'bonus': 2800000, 'penalty': 400000,
  'manualPenalty': 220000, 'ticketPenalty': 180000, 'tripAdvancePaid': 0, 'tripSettled': 0, 'cashIn': 41250000,
  'cashOut': 36800000, 'inboxCount': 5, 'disputeCount': 0, 'awaitingPayCount': 1, 'awaitingPayAmount': 2000000,
  'breakdown': [
    {'label': 'Ứng lương', 'amount': 5500000}, {'label': 'Thưởng', 'amount': 2800000},
  ],
  'daily': [
    for (var d = 1; d <= 28; d++)
      {'date': DateTime(_now.year, _now.month, d).toIso8601String(), 'cashIn': d % 3 == 0 ? 2400000 + d * 50000 : 900000 + d * 20000,
        'cashOut': d % 4 == 0 ? 3100000 : 700000 + d * 30000},
  ],
  'topEmployees': [
    {'employeeId': 'e1', 'name': 'Trần Minh Khoa', 'bonus': 2000000, 'penalty': 0},
    {'employeeId': 'e2', 'name': 'Nguyễn Văn An', 'bonus': 800000, 'penalty': 0},
    {'employeeId': 'e3', 'name': 'Lê Quốc Bảo', 'bonus': 0, 'penalty': 220000},
    {'employeeId': 'e4', 'name': 'Phạm Thu Hà', 'bonus': 0, 'penalty': 80000},
  ],
};

const _people = [
  ('NV001', 'Nguyễn Văn An'), ('NV002', 'Trần Minh Khoa'), ('NV003', 'Lê Quốc Bảo'),
  ('NV004', 'Phạm Thu Hà'), ('NV005', 'Đỗ Hải Nam'), ('NV006', 'Võ Thị Mai'),
];

// ─── Sổ quỹ ───────────────────────────────────────────────────────

final _categories = [
  {'id': 'c1', 'name': 'Doanh thu bán hàng', 'type': 1, 'icon': 'point_of_sale', 'color': '#16A34A'},
  {'id': 'c2', 'name': 'Thu tiền phạt', 'type': 1, 'icon': 'gavel', 'color': '#0EA5E9'},
  {'id': 'c3', 'name': 'Chi ứng lương', 'type': 2, 'icon': 'payments', 'color': '#F59E0B'},
  {'id': 'c4', 'name': 'Nhập nguyên liệu', 'type': 2, 'icon': 'inventory_2', 'color': '#EF4444'},
  {'id': 'c5', 'name': 'Tiền điện nước', 'type': 2, 'icon': 'bolt', 'color': '#8B5CF6'},
];

Map<String, dynamic> _tx(String id, int type, String cat, String catId, double amount, int day, String desc,
        {int method = 1, String? contact, String? source}) =>
    {
      'id': id, 'transactionCode': '${type == 1 ? 'PT' : 'PC'}-${_now.month.toString().padLeft(2, '0')}${day.toString().padLeft(2, '0')}-$id',
      'type': type, 'categoryId': catId, 'categoryName': cat, 'amount': amount, 'transactionDate': _day(day), 'description': desc,
      'paymentMethod': method, 'contactName': contact, 'isPaid': true, 'status': 2, 'createdByUserName': 'Nguyễn Văn An',
      'createdByUserId': 'u1', if (source != null) 'sourceLabel': source, if (source != null) 'isLinked': true,
    };

final _cashTx = [
  _tx('101', 1, 'Doanh thu bán hàng', 'c1', 8450000, 14, 'Doanh thu ca sáng + ca chiều'),
  _tx('102', 2, 'Chi ứng lương', 'c3', 2500000, 13, 'Chi ứng lương — Võ Thị Mai', contact: 'Võ Thị Mai', source: 'Phiếu ứng lương'),
  _tx('103', 2, 'Nhập nguyên liệu', 'c4', 3200000, 12, 'Nhập cà phê hạt, sữa tươi', method: 2, contact: 'Công ty Phúc Long'),
  _tx('104', 1, 'Thu tiền phạt', 'c2', 100000, 11, 'Thu phạt không mặc đồng phục — Lê Quốc Bảo', contact: 'Lê Quốc Bảo', source: 'Phiếu phạt'),
  _tx('105', 2, 'Tiền điện nước', 'c5', 1850000, 10, 'Tiền điện tháng trước', method: 2),
  _tx('106', 1, 'Doanh thu bán hàng', 'c1', 7920000, 9, 'Doanh thu ngày'),
];

final _cashSummary = {
  'totalIncome': 41250000, 'totalExpense': 36800000, 'balance': 4450000, 'totalTransactions': 48, 'incomeTransactions': 30,
  'expenseTransactions': 18, 'pendingTransactions': 0,
};

http.Response _ok(Object? data) =>
    http.Response(jsonEncode({'isSuccess': true, 'data': data}), 200, headers: {'content-type': 'application/json; charset=utf-8'});

/// API giả cho cả hub Tài chính nhân sự, sổ quỹ và cài đặt phạt.
MockClient hrFinGuideApi() => MockClient((req) async {
      final p = req.url.path;
      if (p.endsWith('/hr-finance/settings')) {
        return _ok({'advanceLimitPercent': 50, 'advanceMaxInstallments': 3, 'bonusDefaultSettlement': 'salary',
          'penaltyDefaultSettlement': 'salary', 'disputeWindowDays': 7});
      }
      if (p.endsWith('/hr-finance/summary')) return _ok(_summary);
      if (p.endsWith('/hr-finance/inbox')) return _ok(_inbox);
      if (p.endsWith('/hr-finance/rewards')) return _ok(_rewards);
      if (p.endsWith('/hr-finance/advances')) return _ok(_advances);
      if (p.endsWith('/AdvanceRequests/limit')) {
        return _ok({'monthlySalary': 9000000, 'limit': 4500000, 'used': 0, 'remaining': 4500000, 'maxInstallments': 3, 'limitPercent': 50});
      }
      if (p.endsWith('/api/settings/penalty')) {
        return _ok({
          'lateMinutes1': 10, 'latePenalty1': 20000, 'lateMinutes2': 30, 'latePenalty2': 50000, 'lateMinutes3': 60, 'latePenalty3': 100000,
          'earlyMinutes1': 10, 'earlyPenalty1': 20000, 'earlyMinutes2': 30, 'earlyPenalty2': 50000, 'earlyMinutes3': 60, 'earlyPenalty3': 100000,
          'repeatCount1': 3, 'repeatPenalty1': 50000, 'repeatCount2': 5, 'repeatPenalty2': 100000, 'repeatCount3': 10, 'repeatPenalty3': 200000,
          'forgotCheckPenalty': 50000, 'unauthorizedLeavePenalty': 300000, 'violationPenalty': 100000,
          'collectionMethod': 'Salary', 'autoApproveHoursAfterShift': 2,
        });
      }
      if (p.endsWith('/api/TransactionCategories')) return _ok(_categories);
      if (p.endsWith('/api/CashTransactions/summary')) return _ok(_cashSummary);
      if (p.endsWith('/api/CashTransactions/fund-balances')) {
        return _ok([
          {'label': 'Tiền mặt', 'isCash': true, 'balance': 3250000},
          {'bankAccountId': 'b1', 'label': 'Vietcombank · 0071000123456', 'bankShortName': 'VCB', 'balance': 1200000},
        ]);
      }
      if (p.endsWith('/api/CashTransactions/fund-transfers')) return _ok({'items': [], 'totalCount': 0});
      if (p.endsWith('/api/CashTransactions')) return _ok({'items': _cashTx, 'totalCount': _cashTx.length});
      if (p.endsWith('/api/BankAccounts')) return _ok([]);
      if (p.contains('/api/employees')) {
        return _ok([for (final (c, n) in _people) {'id': 'e-$c', 'fullName': n, 'employeeCode': c}]);
      }
      return _ok([]);
    });

const hrFinManager = HrFinViewer(isManager: true, employeeId: 'e0');

Widget hrFinHub([HrFinTab? tab]) => HrFinanceHubScreen(debugViewer: hrFinManager, initialTab: tab);

/// Chọn nhân viên trong ô gợi ý «Nhân viên» của hộp thoại.
Future<void> hrFinPickEmployee(WidgetTester t, String name) async {
  final field = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == 'Nhân viên');
  await t.enterText(field.first, name.split(' ').last);
  await t.pump(const Duration(milliseconds: 300));
  // Gợi ý hiện «Tên · mã» hoặc tên — chạm dòng gợi ý để chọn đúng người.
  final opt = find.textContaining(name);
  if (opt.evaluate().isNotEmpty) {
    await t.tap(opt.last);
    await t.pump(const Duration(milliseconds: 300));
  } else {
    await t.enterText(field.first, name);
    await t.pump(const Duration(milliseconds: 300));
  }
}

Finder hrFinInputField(String label) =>
    find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label);
