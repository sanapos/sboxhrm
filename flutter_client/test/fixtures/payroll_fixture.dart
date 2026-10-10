/// Dữ liệu mẫu bảng lương tháng 8/2026 — phủ các loại lương và khoản cộng / trừ.
/// Dùng chung cho test app (bảng lương trên máy) và bộ tính lương máy chủ: hai bên phải ra cùng kết quả.
library;

Map<String, dynamic> _benefit(
  String id, {
  required String rateType,
  required num rate,
  String paidLeaveType = 'sunday',
  String weeklyOffDays = 'Sunday',
  String shifts = 'Ca HC',
  Map<String, dynamic> extra = const {},
}) =>
    {
      'id': id,
      'name': 'Bảng lương $id',
      'rateType': rateType,
      'rate': rate,
      'completionSalary': 0,
      'socialInsuranceType': 0,
      'attendanceMode': 'both',
      'paidLeaveType': paidLeaveType,
      'weeklyOffDays': weeklyOffDays,
      'hourlyOvertimeType': 1,
      'holidayOvertimeType': 1,
      'standardHoursPerDay': 8,
      'description': 'attendanceType:both|shifts:$shifts|shiftsPerDay:1|hoursPerWorkDay:8',
      ...extra,
    };

final Map<String, Map<String, dynamic>> payrollFixtureBenefits = {
  // Lương tháng, có lương hoàn thành, BHXH theo lương cơ bản, tăng ca ngày thường.
  'e1': _benefit('b1', rateType: 'Monthly', rate: 15000000, extra: {
    'completionSalary': 2000000,
    'socialInsuranceType': 1,
    'hasHealthInsurance': false,
  }),
  // Lương giờ, làm cả Chủ nhật (tăng ca ngày nghỉ).
  'e2': _benefit('b2', rateType: 'Hourly', rate: 30000),
  // Lương ngày.
  'e3': _benefit('b3', rateType: 'Daily', rate: 400000, extra: {'socialInsuranceType': 3}),
  // Lương ca cố định, có ca qua đêm.
  'e4': _benefit('b4', rateType: 'Shift', rate: 0, shifts: 'Ca đêm', extra: {
    'shiftSalaryType': 0,
    'fixedShiftRate': 250000,
  }),
  // e5: chưa có bảng lương.
  // NV mới vào 20/8, lương tháng có BHXH → tháng 8 không làm ≥14 ngày → không đóng BHXH.
  'e7': _benefit('b7', rateType: 'Monthly', rate: 10000000, extra: {'socialInsuranceType': 1}),
  // Lương tháng, nghỉ T7 + CN, BHXH mức tự chọn.
  'e6': _benefit('b6', rateType: 'Monthly', rate: 9000000, paidLeaveType: 'sat-sun', weeklyOffDays: 'Saturday,Sunday', extra: {
    'socialInsuranceType': 4,
    'insuranceSalary': 6000000,
  }),
};

const payrollFixtureEmployees = [
  {'id': 'e1', 'employeeCode': 'NV001', 'pin': '1', 'firstName': 'An', 'lastName': 'Nguyễn Văn', 'workStatus': 'Active', 'department': 'Bếp', 'position': 'Bếp chính'},
  {'id': 'e2', 'employeeCode': 'NV002', 'pin': '2', 'firstName': 'Bình', 'lastName': 'Trần Thị', 'workStatus': 'Active', 'department': 'Phục vụ'},
  {'id': 'e3', 'employeeCode': 'NV003', 'pin': '3', 'firstName': 'Cường', 'lastName': 'Lê', 'workStatus': 'Active', 'department': 'Phục vụ'},
  {'id': 'e4', 'employeeCode': 'NV004', 'pin': '4', 'firstName': 'Dũng', 'lastName': 'Phạm', 'workStatus': 'Active', 'department': 'Bảo vệ'},
  {'id': 'e5', 'employeeCode': 'NV005', 'pin': '5', 'firstName': 'Em', 'lastName': 'Hồ', 'workStatus': 'Active', 'department': 'Thu ngân'},
  {'id': 'e6', 'employeeCode': 'NV006', 'pin': '6', 'firstName': 'Giang', 'lastName': 'Vũ', 'workStatus': 'Active', 'department': 'Văn phòng'},
  {'id': 'e7', 'employeeCode': 'NV007', 'pin': '7', 'firstName': 'Hải', 'lastName': 'Đặng', 'workStatus': 'Active', 'department': 'Bếp', 'joinDate': '2026-08-20T00:00:00', 'applicationUserId': 'u7'},
];

/// Log chấm công: (pin, ngày, giờ vào, giờ ra). Giờ ra < giờ vào = ra hôm sau.
List<(String, int, int, int, int, int)> payrollFixturePunches() {
  final out = <(String, int, int, int, int, int)>[];
  for (var d = 1; d <= 31; d++) {
    final wd = DateTime(2026, 8, d).weekday;
    // NV001: T2–T7 08:00–17:00; thứ Tư ở lại tới 19:30 (tăng ca).
    if (wd != DateTime.sunday) out.add(('1', d, 8, 0, wd == DateTime.wednesday ? 19 : 17, wd == DateTime.wednesday ? 30 : 0));
    // NV002: làm cả tuần, CN 09:00–15:00.
    if (wd == DateTime.sunday) {
      out.add(('2', d, 9, 0, 15, 0));
    } else if (d % 3 != 0) {
      out.add(('2', d, 8, 0, 17, 0));
    }
    // NV003: T2–T6, nghỉ ngày 10, 11.
    if (wd <= DateTime.friday && d != 10 && d != 11) out.add(('3', d, 8, 5, 17, 2));
    // NV004: ca đêm 22:00–06:00, cách ngày.
    if (d.isEven && d < 31) out.add(('4', d, 21, 55, 6, 3));
    // NV007: vào làm 20/8, T2–T7.
    if (d >= 20 && wd != DateTime.sunday) out.add(('7', d, 8, 0, 17, 0));
    // NV006: T2–T6, đi trễ thứ Hai.
    if (wd <= DateTime.friday) out.add(('6', d, wd == DateTime.monday ? 8 : 7, wd == DateTime.monday ? 25 : 58, 17, 1));
  }
  return out;
}


/// Log chấm công dạng API (/api/attendances).
List<Map<String, dynamic>> payrollFixtureAttendanceJson() {
  final out = <Map<String, dynamic>>[];
  String two(int v) => v.toString().padLeft(2, '0');
  for (final (pin, d, ih, im, oh, om) in payrollFixturePunches()) {
    final inT = DateTime(2026, 8, d, ih, im);
    var outT = DateTime(2026, 8, d, oh, om);
    if (!outT.isAfter(inT)) outT = outT.add(const Duration(days: 1));
    String iso(DateTime t) => '${t.year}-${two(t.month)}-${two(t.day)}T${two(t.hour)}:${two(t.minute)}:00';
    for (final (t, st) in [(inT, 0), (outT, 1)]) {
      out.add({
        'id': 'a-$pin-$d-$st',
        'pin': pin,
        // Như API thật (AttendanceDto): mã NV, không phải GUID.
        'employeeCode': 'NV00$pin',
        'deviceId': 'dev1',
        'deviceName': 'Máy cửa',
        'attendanceTime': iso(t),
        'attendanceState': st,
        'verifyMode': 1,
      });
    }
  }
  return out;
}

/// Phản hồi API theo đường dẫn (không gồm /api/employees, /api/attendances — xử lý riêng).
Map<String, Object?> payrollFixtureResponses({bool serverAdjustments = false, bool lawPolicy = false}) => {
      '/api/benefits/employees': [
        for (final e in payrollFixtureEmployees)
          if (payrollFixtureBenefits.containsKey(e['id']))
            {'employeeId': e['id'], 'benefitId': payrollFixtureBenefits[e['id']]!['id'], 'isActive': true, 'benefit': payrollFixtureBenefits[e['id']]}
          else
            {'employeeId': e['id'], 'isActive': false, 'benefit': null},
      ],
      '/api/benefits/timeline': [
        {
          'employeeId': 'e6',
          'segments': [
            {'id': 'v1', 'benefitId': 'b6old', 'benefit': {...payrollFixtureBenefits['e6']!, 'id': 'b6old', 'rate': 8000000}, 'from': '2026-08-01T00:00:00', 'to': '2026-08-14T00:00:00'},
            {'id': 'v2', 'benefitId': 'b6', 'benefit': payrollFixtureBenefits['e6'], 'from': '2026-08-15T00:00:00', 'to': '2026-08-31T00:00:00'},
          ],
        },
      ],
      '/api/shifts/templates': [
        {'id': 's1', 'name': 'Ca HC', 'startTime': '08:00:00', 'endTime': '17:00:00', 'breakTimeMinutes': 60, 'isActive': true, 'shiftType': 'Hành chính'},
        {'id': 's2', 'name': 'Ca đêm', 'startTime': '22:00:00', 'endTime': '06:00:00', 'breakTimeMinutes': 0, 'isActive': true, 'shiftType': 'Qua đêm'},
      ],
      '/api/settings/insurance': {
        'bhxhEmployeeRate': 8, 'bhytEmployeeRate': 1.5, 'bhtnEmployeeRate': 1, 'unionFeeEmployeeRate': 0,
        'defaultRegion': 1, 'minSalaryRegion1': 4960000, 'maxInsuranceSalary': 46800000,
      },
      '/api/settings/salary': {
        'standardWorkDays': 26, 'standardWorkHours': 8, 'overtimeRate': 1.5, 'weekendRate': 2, 'holidayRate': 3,
        if (lawPolicy) 'payrollPolicyPreset': 'law',
      },
      '/api/settings/tax': {'personalDeduction': 11000000, 'dependentDeduction': 4400000},
      '/api/settings/tax/employee-deductions': [
        {'employeeId': 'e1', 'numberOfDependents': 1},
      ],
      '/api/settings/holidays': [
        {'id': 'h1', 'name': 'Nghỉ bù', 'date': '2026-08-20T00:00:00', 'isRecurring': false},
      ],
      '/api/allowances': {
        'items': [
          {'id': 'al1', 'name': 'Ăn trưa', 'amount': 30000, 'type': 1, 'isActive': true, 'employeeIds': ['e1', 'e3', 'e6']},
          {'id': 'al2', 'name': 'Xăng xe', 'amount': 500000, 'type': 0, 'isActive': true, 'employeeIds': ['e1']},
        ],
      },
      '/api/Transactions': {
        'items': [
          {'id': 't1', 'employeeId': 'e1', 'type': 'Bonus', 'amount': 1000000, 'status': 'Approved', 'paymentMethod': 'Salary', 'transactionDate': '2026-08-10T00:00:00'},
          {'id': 't2', 'employeeId': 'e2', 'type': 'Penalty', 'amount': 200000, 'status': 'Approved', 'transactionDate': '2026-08-12T00:00:00'},
          {'id': 't3', 'employeeId': 'e3', 'type': 'Bonus', 'amount': 300000, 'status': 'Pending', 'transactionDate': '2026-08-12T00:00:00'},
        ],
      },
      '/api/AdvanceRequests': {
        'items': [
          {'id': 'ad1', 'employeeId': 'e1', 'amount': 3000000, 'approvedAmount': 2500000, 'status': 'Approved', 'isPaid': true, 'paidDate': '2026-08-15T10:00:00'},
          {'id': 'ad2', 'employeeId': 'e3', 'amount': 1000000, 'status': 'Approved', 'isPaid': false},
        ],
      },
      '/api/PenaltyTickets': {
        'items': [
          {'id': 'p1', 'employeeId': 'e6', 'amount': 50000, 'status': 'Approved', 'type': 'Late'},
          {'id': 'p2', 'employeeId': 'e6', 'amount': 50000, 'status': 'Pending', 'type': 'Late'},
          {'id': 'p3', 'employeeId': 'e2', 'amount': 100000, 'status': 'AutoApproved', 'collectionMethod': 'Cash'},
        ],
      },
      '/api/hr-finance/payroll-adjustments': serverAdjustments
          ? [
              {'employeeId': 'e1', 'bonus': 1200000, 'penalty': 0, 'ticketPenalty': 0, 'advance': 2000000},
              {'employeeId': 'e6', 'bonus': 0, 'penalty': 0, 'ticketPenalty': 50000, 'advance': 0},
            ]
          : null,
      '/api/shift-salary-levels': {'items': []},
      '/api/kpi/periods': [
        {'id': 'k1', 'periodStart': '2026-08-01T00:00:00', 'periodEnd': '2026-08-31T00:00:00'},
      ],
      '/api/kpi/employee-targets': [
        {'employeeId': 'e2', 'criteriaType': 0, 'targetValue': 50000000, 'actualValue': 60000000, 'completionSalary': 0},
      ],
      '/api/kpi/salary/for-payroll': {
        'items': [
          {'employeeId': 'e1', 'amount': 800000},
        ],
      },
      '/api/production/summary': [
        {'employeeId': 'e3', 'employeeCode': 'NV003', 'totalAmount': 450000},
      ],
      '/api/annual-leave/payouts': [
        {'employeeId': 'e6', 'amount': 350000},
      ],
      '/api/settings/app/commission_settings': {'key': 'commission_settings', 'value': '{"commissionType":"flat","flatRate":2}'},
      '/api/settings/app/day_end_time': {'key': 'day_end_time', 'value': '04:00'},
      '/api/Leaves': {
        'items': [
          // Phép năm DN trả lương — NV003 vắng 10, 11/8 → được trả 2 ngày.
          {'id': 'l1', 'employeeId': 'e3', 'employeeUserId': 'u3', 'type': 'AnnualLeave', 'status': 'Approved',
            'startDate': '2026-08-10T00:00:00', 'endDate': '2026-08-11T00:00:00', 'isHalfShift': false,
            'countAsWork': false, 'paymentSource': 'EmployerPaid'},
          // Ốm hưởng BHXH — không trả lương (NV002 nghỉ 3/8).
          {'id': 'l2', 'employeeId': 'e2', 'employeeUserId': 'u2', 'type': 'SickLeave', 'status': 'Approved',
            'startDate': '2026-08-03T00:00:00', 'endDate': '2026-08-03T00:00:00', 'isHalfShift': false,
            'countAsWork': false, 'paymentSource': 'SocialInsurance'},
        ],
        'totalCount': 2,
      },
    };
