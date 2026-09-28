/// Tài chính nhân sự v2 — dữ liệu từ api/hr-finance.
library;

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
double? _dn(dynamic v) => v == null ? null : _d(v);
int _i(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
DateTime _dt(dynamic v) => DateTime.tryParse('${v ?? ''}')?.toLocal() ?? DateTime.now();

/// Một khoản tiền thống nhất: ứng lương, thưởng, phạt, phiếu phạt, công tác, phiếu quỹ.
class HrFinItem {
  HrFinItem({
    required this.kind,
    required this.id,
    this.code,
    this.employeeId,
    this.employeeName = '',
    this.employeeCode,
    this.photoUrl,
    this.department,
    this.title = '',
    this.subtitle,
    this.amount = 0,
    this.direction = 'in',
    this.status = '',
    required this.date,
    this.action,
    this.settlement,
    this.evidence = const [],
    this.disputeStatus = 0,
    this.disputeReason,
    this.disputeResponse,
    this.caseId,
    this.forMonth,
    this.forYear,
    this.installmentCount,
  });

  /// advance / bonus / penalty / ticket / trip_advance / trip_settlement / cash
  final String kind;
  final String id;
  final String? code;
  final String? employeeId;
  final String employeeName;
  final String? employeeCode;
  final String? photoUrl;
  final String? department;
  final String title;
  final String? subtitle;
  final double amount;

  /// in = công ty chi cho nhân viên; out = nhân viên nộp / bị trừ
  final String direction;
  final String status;
  final DateTime date;

  /// approve / pay / resolve / null
  final String? action;
  final String? settlement;
  final List<String> evidence;
  final int disputeStatus;
  final String? disputeReason;
  final String? disputeResponse;
  final String? caseId;
  final int? forMonth;
  final int? forYear;
  final int? installmentCount;

  bool get isIn => direction == 'in';
  bool get isPenalty => kind == 'penalty' || kind == 'ticket';
  bool get isTrip => kind.startsWith('trip_');
  bool get isApproved => const {'Completed', 'Approved', 'AutoApproved', 'Paid'}.contains(status);
  bool get isCancelled => const {'Cancelled', 'Rejected'}.contains(status);
  bool get isDisputeOpen => disputeStatus == 1;

  factory HrFinItem.fromJson(Map<String, dynamic> j) => HrFinItem(
        kind: '${j['kind'] ?? ''}',
        id: '${j['id'] ?? ''}',
        code: j['code']?.toString(),
        employeeId: j['employeeId']?.toString(),
        employeeName: '${j['employeeName'] ?? ''}',
        employeeCode: j['employeeCode']?.toString(),
        photoUrl: j['photoUrl']?.toString(),
        department: j['department']?.toString(),
        title: '${j['title'] ?? ''}',
        subtitle: j['subtitle']?.toString(),
        amount: _d(j['amount']),
        direction: '${j['direction'] ?? 'in'}',
        status: '${j['status'] ?? ''}',
        date: _dt(j['date']),
        action: j['action']?.toString(),
        settlement: j['settlement']?.toString(),
        evidence: (j['evidence'] as List?)?.map((e) => '$e').toList() ?? const [],
        disputeStatus: _i(j['disputeStatus']),
        disputeReason: j['disputeReason']?.toString(),
        disputeResponse: j['disputeResponse']?.toString(),
        caseId: j['caseId']?.toString(),
        forMonth: j['forMonth'] == null ? null : _i(j['forMonth']),
        forYear: j['forYear'] == null ? null : _i(j['forYear']),
        installmentCount: j['installmentCount'] == null ? null : _i(j['installmentCount']),
      );

  static List<HrFinItem> listFrom(dynamic data) => data is List
      ? data.whereType<Map>().map((e) => HrFinItem.fromJson(Map<String, dynamic>.from(e))).toList()
      : <HrFinItem>[];
}

class HrFinSettings {
  HrFinSettings({
    this.advanceLimitPercent = 50,
    this.advanceLimitAmount,
    this.advanceMaxRequestsPerPeriod,
    this.advanceMaxInstallments = 3,
    this.bonusDefaultSettlement = 'salary',
    this.penaltyDefaultSettlement = 'salary',
    this.disputeWindowDays = 7,
  });

  double? advanceLimitPercent;
  double? advanceLimitAmount;
  int? advanceMaxRequestsPerPeriod;
  int advanceMaxInstallments;
  String bonusDefaultSettlement;
  String penaltyDefaultSettlement;
  int disputeWindowDays;

  factory HrFinSettings.fromJson(Map<String, dynamic> j) => HrFinSettings(
        advanceLimitPercent: _dn(j['advanceLimitPercent']),
        advanceLimitAmount: _dn(j['advanceLimitAmount']),
        advanceMaxRequestsPerPeriod: j['advanceMaxRequestsPerPeriod'] == null ? null : _i(j['advanceMaxRequestsPerPeriod']),
        advanceMaxInstallments: j['advanceMaxInstallments'] == null ? 3 : _i(j['advanceMaxInstallments']),
        bonusDefaultSettlement: '${j['bonusDefaultSettlement'] ?? 'salary'}',
        penaltyDefaultSettlement: '${j['penaltyDefaultSettlement'] ?? 'salary'}',
        disputeWindowDays: j['disputeWindowDays'] == null ? 7 : _i(j['disputeWindowDays']),
      );

  Map<String, dynamic> toJson() => {
        'advanceLimitPercent': advanceLimitPercent,
        'advanceLimitAmount': advanceLimitAmount,
        'advanceMaxRequestsPerPeriod': advanceMaxRequestsPerPeriod,
        'advanceMaxInstallments': advanceMaxInstallments,
        'bonusDefaultSettlement': bonusDefaultSettlement,
        'penaltyDefaultSettlement': penaltyDefaultSettlement,
        'disputeWindowDays': disputeWindowDays,
      };
}

class HrFinAdvanceLimit {
  HrFinAdvanceLimit({this.monthlySalary, this.limit, this.used = 0, this.remaining, this.maxInstallments = 3, this.limitPercent});
  final double? monthlySalary;
  final double? limit;
  final double used;
  final double? remaining;
  final int maxInstallments;
  final double? limitPercent;

  factory HrFinAdvanceLimit.fromJson(Map<String, dynamic> j) => HrFinAdvanceLimit(
        monthlySalary: _dn(j['monthlySalary']),
        limit: _dn(j['limit']),
        used: _d(j['used']),
        remaining: _dn(j['remaining']),
        maxInstallments: j['maxInstallments'] == null ? 3 : _i(j['maxInstallments']),
        limitPercent: _dn(j['limitPercent']),
      );
}

class HrFinLedger {
  HrFinLedger({
    required this.employeeId,
    required this.employeeName,
    this.employeeCode,
    this.department,
    this.photoUrl,
    this.received = 0,
    this.deducted = 0,
    this.bonus = 0,
    this.penalty = 0,
    this.advance = 0,
    this.advanceOutstanding = 0,
    this.items = const [],
  });

  final String employeeId;
  final String employeeName;
  final String? employeeCode;
  final String? department;
  final String? photoUrl;
  final double received;
  final double deducted;
  final double bonus;
  final double penalty;
  final double advance;
  final double advanceOutstanding;
  final List<HrFinItem> items;

  factory HrFinLedger.fromJson(Map<String, dynamic> j) {
    final e = j['employee'] is Map ? Map<String, dynamic>.from(j['employee'] as Map) : const <String, dynamic>{};
    return HrFinLedger(
      employeeId: '${e['id'] ?? ''}',
      employeeName: '${e['name'] ?? ''}',
      employeeCode: e['code']?.toString(),
      department: e['department']?.toString(),
      photoUrl: e['photoUrl']?.toString(),
      received: _d(j['received']),
      deducted: _d(j['deducted']),
      bonus: _d(j['bonus']),
      penalty: _d(j['penalty']),
      advance: _d(j['advance']),
      advanceOutstanding: _d(j['advanceOutstanding']),
      items: HrFinItem.listFrom(j['items']),
    );
  }
}

class HrFinSummary {
  HrFinSummary(this.raw);
  final Map<String, dynamic> raw;

  double n(String k) => _d(raw[k]);
  int c(String k) => _i(raw[k]);

  List<({String label, double amount})> get breakdown => (raw['breakdown'] as List?)
          ?.whereType<Map>()
          .map((e) => (label: '${e['label']}', amount: _d(e['amount'])))
          .toList() ??
      const [];

  List<({DateTime date, double cashIn, double cashOut})> get daily => (raw['daily'] as List?)
          ?.whereType<Map>()
          .map((e) => (date: _dt(e['date']), cashIn: _d(e['cashIn']), cashOut: _d(e['cashOut'])))
          .toList() ??
      const [];

  List<({String id, String name, double bonus, double penalty})> get topEmployees => (raw['topEmployees'] as List?)
          ?.whereType<Map>()
          .map((e) => (id: '${e['employeeId']}', name: '${e['name']}', bonus: _d(e['bonus']), penalty: _d(e['penalty'])))
          .toList() ??
      const [];
}

/// Khoản cộng/trừ lương của một nhân viên trong kỳ (nguồn dùng chung cho bảng lương).
class HrFinPayrollAdj {
  HrFinPayrollAdj({
    required this.employeeId,
    this.employeeUserId,
    this.bonus = 0,
    this.penalty = 0,
    this.ticketPenalty = 0,
    this.advance = 0,
  });

  final String employeeId;
  final String? employeeUserId;
  final double bonus;
  final double penalty;
  final double ticketPenalty;
  final double advance;

  factory HrFinPayrollAdj.fromJson(Map<String, dynamic> j) => HrFinPayrollAdj(
        employeeId: '${j['employeeId'] ?? ''}',
        employeeUserId: j['employeeUserId']?.toString(),
        bonus: _d(j['bonus']),
        penalty: _d(j['penalty']),
        ticketPenalty: _d(j['ticketPenalty']),
        advance: _d(j['advance']),
      );
}
