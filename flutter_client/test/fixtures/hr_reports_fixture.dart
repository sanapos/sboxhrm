/// Dữ liệu mẫu cho các báo cáo nhân sự (tháng 10/2026, kỳ mặc định = đầu tháng → hôm nay).
/// Số mong đợi (tính tay) ghi cạnh dữ liệu — test so với chữ hiện trên màn.
/// Trả null = rỗng mặc định.
Map<String, dynamic>? hrReportsResponse(String method, String path, Map<String, String> q) {
  Map<String, dynamic> ok(Object data) => {'isSuccess': true, 'data': data};
  final p = path.toLowerCase();
  if (p == '/api/employees') return ok({'items': _employees, 'totalCount': _employees.length});
  if (p == '/api/employees/me') return ok(_employees.first);
  if (p == '/api/penaltytickets') return ok({'items': _penalties, 'totalCount': _penalties.length});
  if (p == '/api/reports/finance/penalty-summary') {
    return ok({
      'totalTickets': 3,
      'totalAmount': 180000,
      'approvedAmount': 150000,
      'byEmployee': [
        {'employeeCode': 'NV001', 'employeeName': 'Nguyễn Văn An', 'department': 'Bán hàng', 'ticketCount': 2, 'totalAmount': 80000},
        {'employeeCode': 'NV002', 'employeeName': 'Trần Thị Bình', 'department': 'Kho', 'ticketCount': 1, 'totalAmount': 100000},
      ],
    });
  }
  if (p == '/api/advancerequests') return ok({'items': _advances, 'totalCount': _advances.length});
  if (p == '/api/reports/finance/advance-debt') {
    return ok({
      'totalRequests': 3,
      'items': [
        {'employeeCode': 'NV002', 'employeeName': 'Trần Thị Bình', 'department': 'Kho', 'totalRequests': 1, 'totalApproved': 1500000, 'totalPaid': 0, 'outstandingDebt': 1500000},
        {'employeeCode': 'NV001', 'employeeName': 'Nguyễn Văn An', 'department': 'Bán hàng', 'totalRequests': 1, 'totalApproved': 1000000, 'totalPaid': 1000000, 'outstandingDebt': 0},
      ],
    });
  }
  if (p == '/api/reports/finance/business-trip') return ok(_trip);
  if (p == '/api/leaves') return ok({'items': _leaves, 'totalCount': _leaves.length});
  if (p == '/api/reports/leave-summary') {
    return ok({
      'items': [
        {'employeeName': 'Nguyễn Văn An', 'departmentName': 'Bán hàng', 'totalDays': 2.0, 'totalRequests': 1},
        {'employeeName': 'Trần Thị Bình', 'departmentName': 'Kho', 'totalDays': 0.5, 'totalRequests': 2},
      ],
    });
  }
  if (p == '/api/mobile-attendance/history') return ok(_travel);
  return null;
}

final _employees = [
  {'id': 'e1', 'employeeCode': 'NV001', 'fullName': 'Nguyễn Văn An', 'firstName': 'An', 'lastName': 'Nguyễn Văn', 'department': 'Bán hàng', 'applicationUserId': 'u1'},
  {'id': 'e2', 'employeeCode': 'NV002', 'fullName': 'Trần Thị Bình', 'firstName': 'Bình', 'lastName': 'Trần Thị', 'department': 'Kho', 'applicationUserId': 'u2'},
  {'id': 'e3', 'employeeCode': 'NV003', 'fullName': 'Lê Minh Châu', 'firstName': 'Châu', 'lastName': 'Lê Minh', 'department': 'Bán hàng', 'applicationUserId': 'u3'},
];

// Phạt: đã duyệt 150.000 = trừ lương 50.000 + thu tiền mặt 100.000; chờ duyệt 30.000; hủy 50.000 (không tính).
final _penalties = [
  {'id': 'p1', 'ticketCode': 'PP001', 'employeeId': 'e1', 'employeeName': 'Nguyễn Văn An', 'employeeCode': 'NV001', 'type': 'Late', 'status': 'Approved', 'amount': 50000, 'violationDate': '2026-10-02T00:00:00', 'minutesLateOrEarly': 20, 'collectionMethod': 'Salary', 'createdAt': '2026-10-02T09:00:00'},
  {'id': 'p2', 'ticketCode': 'PP002', 'employeeId': 'e1', 'employeeName': 'Nguyễn Văn An', 'employeeCode': 'NV001', 'type': 'EarlyLeave', 'status': 'Pending', 'amount': 30000, 'violationDate': '2026-10-05T00:00:00', 'minutesLateOrEarly': 15, 'createdAt': '2026-10-05T18:00:00'},
  {'id': 'p3', 'ticketCode': 'PP003', 'employeeId': 'e2', 'employeeName': 'Trần Thị Bình', 'employeeCode': 'NV002', 'type': 'ForgotCheck', 'status': 'Approved', 'amount': 100000, 'violationDate': '2026-10-06T00:00:00', 'collectionMethod': 'Cash', 'createdAt': '2026-10-06T18:00:00'},
  {'id': 'p4', 'ticketCode': 'PP004', 'employeeId': 'e3', 'employeeName': 'Lê Minh Châu', 'employeeCode': 'NV003', 'type': 'Late', 'status': 'Cancelled', 'amount': 50000, 'violationDate': '2026-10-07T00:00:00', 'createdAt': '2026-10-07T09:00:00'},
];

// Ứng lương: duyệt 2.500.000 = đã chi 1.000.000 + duyệt chưa chi 1.500.000 (YC 2.000.000, duyệt 1.500.000); chờ 500.000; từ chối 300.000.
final _advances = [
  {'id': 'a1', 'employeeUserId': 'u1', 'employeeName': 'Nguyễn Văn An', 'employeeCode': 'NV001', 'amount': 1000000, 'reason': 'Đóng học phí', 'requestDate': '2026-10-02T08:00:00', 'status': 'Approved', 'approvedByName': 'Quản Lý', 'isPaid': true, 'paidDate': '2026-10-03T08:00:00', 'forMonth': 10, 'forYear': 2026, 'createdAt': '2026-10-02T08:00:00'},
  {'id': 'a2', 'employeeUserId': 'u2', 'employeeName': 'Trần Thị Bình', 'employeeCode': 'NV002', 'amount': 2000000, 'approvedAmount': 1500000, 'reason': 'Việc gia đình', 'requestDate': '2026-10-04T08:00:00', 'status': 'Approved', 'approvedByName': 'Quản Lý', 'isPaid': false, 'forMonth': 10, 'forYear': 2026, 'createdAt': '2026-10-04T08:00:00'},
  {'id': 'a3', 'employeeUserId': 'u3', 'employeeName': 'Lê Minh Châu', 'employeeCode': 'NV003', 'amount': 500000, 'requestDate': '2026-10-08T08:00:00', 'status': 'Pending', 'isPaid': false, 'createdAt': '2026-10-08T08:00:00'},
  {'id': 'a4', 'employeeUserId': 'u3', 'employeeName': 'Lê Minh Châu', 'employeeCode': 'NV003', 'amount': 300000, 'requestDate': '2026-10-01T08:00:00', 'status': 'Rejected', 'isPaid': false, 'createdAt': '2026-10-01T08:00:00'},
];

// Công tác: tạm ứng 5.000.000 = đã chi 3.000.000 + chờ chi 2.000.000.
final _trip = {
  'totalCases': 2,
  'totalAdvanceAmount': 5000000,
  'totalSettledAmount': 3500000,
  'totalBalanceAmount': 500000,
  'totalWithInvoice': 3000000,
  'totalWithoutInvoice': 500000,
  'expenseLineCount': 3,
  'items': [
    {'id': 'c1', 'caseCode': 'CT001', 'title': 'Khảo sát chi nhánh Đà Nẵng', 'destination': 'Đà Nẵng', 'employeeUserId': 'u1', 'employeeCode': 'NV001', 'employeeName': 'Nguyễn Văn An', 'department': 'Bán hàng', 'status': 'Closed', 'statusLabel': 'Đã đóng', 'advanceAmount': 3000000, 'settledAmount': 3500000, 'balanceAmount': 500000, 'tripFromDate': '2026-10-02T00:00:00', 'tripToDate': '2026-10-04T00:00:00', 'createdAt': '2026-10-01T08:00:00', 'advanceIsPaid': true, 'expenseLineCount': 3, 'totalWithInvoice': 3000000, 'totalWithoutInvoice': 500000, 'categoryIds': [], 'hasUncategorizedExpense': true},
    {'id': 'c2', 'caseCode': 'CT002', 'title': 'Gặp nhà cung cấp', 'destination': 'Cần Thơ', 'employeeUserId': 'u2', 'employeeCode': 'NV002', 'employeeName': 'Trần Thị Bình', 'department': 'Kho', 'status': 'AdvancePending', 'statusLabel': 'Chờ duyệt tạm ứng', 'advanceAmount': 2000000, 'settledAmount': 0, 'balanceAmount': 0, 'tripFromDate': '2026-10-12T00:00:00', 'tripToDate': '2026-10-13T00:00:00', 'createdAt': '2026-10-08T08:00:00', 'advanceIsPaid': false, 'expenseLineCount': 0, 'totalWithInvoice': 0, 'totalWithoutInvoice': 0, 'categoryIds': [], 'hasUncategorizedExpense': false},
  ],
  'byEmployee': [
    {'employeeCode': 'NV001', 'employeeName': 'Nguyễn Văn An', 'department': 'Bán hàng', 'totalCases': 1, 'totalAdvance': 3000000, 'totalSettled': 3500000, 'totalBalance': 500000},
    {'employeeCode': 'NV002', 'employeeName': 'Trần Thị Bình', 'department': 'Kho', 'totalCases': 1, 'totalAdvance': 2000000, 'totalSettled': 0, 'totalBalance': 0},
  ],
  'byCategory': [
    {'categoryName': 'Chưa phân loại', 'lineCount': 3, 'caseCount': 1, 'totalAmount': 3500000, 'withInvoiceAmount': 3000000, 'withoutInvoiceAmount': 500000, 'percentage': 100},
  ],
};

// Nghỉ: An phép năm 29/9–2/10 (trong kỳ 2 ngày); Bình nửa ca 5/10 (0,5) + 1 đơn chờ → KPI 2,5 ngày.
final _leaves = [
  {'id': 'l1', 'employeeUserId': 'u1', 'employeeId': 'e1', 'employeeName': 'Nguyễn Văn An', 'type': 'AnnualLeave', 'startDate': '2026-09-29T00:00:00', 'endDate': '2026-10-02T00:00:00', 'isHalfShift': false, 'reason': 'Về quê', 'status': 'Approved', 'createdAt': '2026-09-20T08:00:00', 'countAsWork': false, 'paymentSource': 'EmployerPaid'},
  {'id': 'l2', 'employeeUserId': 'u2', 'employeeId': 'e2', 'employeeName': 'Trần Thị Bình', 'type': 'PersonalPaid', 'startDate': '2026-10-05T00:00:00', 'endDate': '2026-10-05T00:00:00', 'isHalfShift': true, 'reason': 'Khám bệnh', 'status': 'Approved', 'createdAt': '2026-10-01T08:00:00', 'countAsWork': false, 'paymentSource': 'EmployerPaid'},
  {'id': 'l3', 'employeeUserId': 'u2', 'employeeId': 'e2', 'employeeName': 'Trần Thị Bình', 'type': 'PersonalUnpaid', 'startDate': '2026-10-09T00:00:00', 'endDate': '2026-10-09T00:00:00', 'isHalfShift': false, 'reason': 'Việc riêng', 'status': 'Pending', 'createdAt': '2026-10-07T08:00:00', 'countAsWork': false, 'paymentSource': 'Unpaid'},
];

// Đi đường: chuyến 1 (đã duyệt) 1h30p; chuyến 2 đến điểm chờ duyệt 1h → tổng 2h30p, tính lương 1h30p.
final _travel = [
  {'id': 't1', 'odooEmployeeId': 'NV001', 'employeeName': 'Nguyễn Văn An', 'punchTime': '2026-10-02T08:00:00', 'punchType': 2, 'status': 'approved'},
  {'id': 't2', 'odooEmployeeId': 'NV001', 'employeeName': 'Nguyễn Văn An', 'punchTime': '2026-10-02T09:30:00', 'punchType': 3, 'status': 'approved'},
  {'id': 't3', 'odooEmployeeId': 'NV001', 'employeeName': 'Nguyễn Văn An', 'punchTime': '2026-10-06T14:00:00', 'punchType': 2, 'status': 'approved'},
  {'id': 't4', 'odooEmployeeId': 'NV001', 'employeeName': 'Nguyễn Văn An', 'punchTime': '2026-10-06T15:00:00', 'punchType': 3, 'status': 'pending'},
];
