import '../models/cash_transaction.dart';
import 'api_datetime.dart';

/// Tổng hợp sổ quỹ từ danh sách giao dịch báo cáo thu chi.
class CashReportSummary {
  final double paidIncome;
  final double paidExpense;
  final int paidIncomeCount;
  final int paidExpenseCount;
  final double pendingIncome;
  final double pendingExpense;
  final int pendingIncomeCount;
  final int pendingExpenseCount;
  final int cancelledCount;

  const CashReportSummary({
    this.paidIncome = 0,
    this.paidExpense = 0,
    this.paidIncomeCount = 0,
    this.paidExpenseCount = 0,
    this.pendingIncome = 0,
    this.pendingExpense = 0,
    this.pendingIncomeCount = 0,
    this.pendingExpenseCount = 0,
    this.cancelledCount = 0,
  });

  double get fundBalance => paidIncome - paidExpense;

  factory CashReportSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const CashReportSummary();
    double d(dynamic v) {
      if (v is double) return v;
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '') ?? 0;
    }
    int i(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    }
    final paidInc = d(json['paidIncome'] ?? json['totalIncome']);
    final paidExp = d(json['paidExpense'] ?? json['totalExpense']);
    return CashReportSummary(
      paidIncome: paidInc,
      paidExpense: paidExp,
      paidIncomeCount: i(json['paidIncomeCount'] ?? json['incomeTransactions']),
      paidExpenseCount: i(json['paidExpenseCount'] ?? json['expenseTransactions']),
      pendingIncome: d(json['pendingIncome'] ?? json['pendingIncomeAmount']),
      pendingExpense: d(json['pendingExpense'] ?? json['pendingExpenseAmount']),
      pendingIncomeCount: i(json['pendingIncomeCount']),
      pendingExpenseCount: i(json['pendingExpenseCount']),
      cancelledCount: i(json['cancelledCount']),
    );
  }

  factory CashReportSummary.fromRows(Iterable<Map<String, dynamic>> rows) {
    var paidInc = 0.0;
    var paidExp = 0.0;
    var pendInc = 0.0;
    var pendExp = 0.0;
    var paidIncN = 0;
    var paidExpN = 0;
    var pendIncN = 0;
    var pendExpN = 0;
    var cancelledN = 0;

    for (final row in rows) {
      final type = cashReportRowType(row);
      final amt = cashReportRowAmount(row);
      if (cashReportRowIsCancelled(row)) {
        cancelledN++;
        continue;
      }
      if (cashReportRowIsCompleted(row)) {
        if (type == CashTransactionType.income) {
          paidInc += amt;
          paidIncN++;
        } else {
          paidExp += amt;
          paidExpN++;
        }
      } else if (cashReportRowIsPending(row)) {
        if (type == CashTransactionType.income) {
          pendInc += amt;
          pendIncN++;
        } else {
          pendExp += amt;
          pendExpN++;
        }
      }
    }

    return CashReportSummary(
      paidIncome: paidInc,
      paidExpense: paidExp,
      paidIncomeCount: paidIncN,
      paidExpenseCount: paidExpN,
      pendingIncome: pendInc,
      pendingExpense: pendExp,
      pendingIncomeCount: pendIncN,
      pendingExpenseCount: pendExpN,
      cancelledCount: cancelledN,
    );
  }
}

DateTime? cashReportRowDate(Map<String, dynamic> row) {
  return parseApiCalendarDate(
      row['transactionDate'] ?? row['TransactionDate']);
}

/// Phiếu thuộc kỳ [from..to] theo ngày lịch VN.
bool cashReportInDateRange(
  Map<String, dynamic> row,
  DateTime from,
  DateTime to,
) {
  final d = cashReportRowDate(row);
  if (d == null) return false;
  final start = DateTime(from.year, from.month, from.day);
  final end = DateTime(to.year, to.month, to.day);
  return !d.isBefore(start) && !d.isAfter(end);
}

double cashReportRowAmount(Map<String, dynamic> row) {
  final v = row['amount'];
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

CashTransactionType cashReportRowType(Map<String, dynamic> row) {
  return CashTransactionType.parse(row['type']);
}

CashTransactionStatus cashReportRowStatus(Map<String, dynamic> row) {
  return resolveCashTransactionStatus(row);
}

bool cashReportRowIsPaid(dynamic raw) {
  if (raw == true) return true;
  if (raw is num) return raw != 0;
  final s = raw?.toString().trim().toLowerCase() ?? '';
  return s == 'true' || s == '1';
}

bool cashReportRowIsCompleted(Map<String, dynamic> row) {
  final st = cashReportRowStatus(row);
  return cashReportRowIsPaid(row['isPaid'] ?? row['IsPaid']) ||
      st == CashTransactionStatus.completed;
}

bool cashReportRowIsCancelled(Map<String, dynamic> row) {
  return cashReportRowStatus(row) == CashTransactionStatus.cancelled;
}

bool cashReportRowIsPending(Map<String, dynamic> row) {
  if (cashReportRowIsCancelled(row)) return false;
  if (cashReportRowIsCompleted(row)) return false;
  final st = cashReportRowStatus(row);
  return st == CashTransactionStatus.pending ||
      st == CashTransactionStatus.waitingPayment;
}

/// Số dư quỹ lũy kế sau từng dòng (theo thứ tự thời gian tăng dần).
Map<String, double> cashReportRunningBalances(
  List<Map<String, dynamic>> rows,
) {
  final sorted = List<Map<String, dynamic>>.from(rows);
  sorted.sort((a, b) {
    final da = cashReportRowDate(a) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final db = cashReportRowDate(b) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final c = da.compareTo(db);
    if (c != 0) return c;
    return (a['id']?.toString() ?? '').compareTo(b['id']?.toString() ?? '');
  });

  var balance = 0.0;
  final out = <String, double>{};
  for (final row in sorted) {
    if (!cashReportRowIsCompleted(row)) continue;
    final id = row['id']?.toString() ?? '';
    final amt = cashReportRowAmount(row);
    balance += cashReportRowType(row) == CashTransactionType.income ? amt : -amt;
    if (id.isNotEmpty) out[id] = balance;
  }
  return out;
}

/// Lọc theo chip / dropdown trạng thái.
bool cashReportMatchesStatusFilter(
  Map<String, dynamic> row,
  String? filter,
) {
  if (filter == null || filter.isEmpty || filter == 'all') return true;
  switch (filter) {
    case 'paid_income':
      return cashReportRowIsCompleted(row) &&
          cashReportRowType(row) == CashTransactionType.income;
    case 'paid_expense':
      return cashReportRowIsCompleted(row) &&
          cashReportRowType(row) == CashTransactionType.expense;
    case 'pending_income':
      return cashReportRowIsPending(row) &&
          cashReportRowType(row) == CashTransactionType.income;
    case 'pending_expense':
      return cashReportRowIsPending(row) &&
          cashReportRowType(row) == CashTransactionType.expense;
    case 'pending':
      return cashReportRowIsPending(row);
    case 'completed':
      return cashReportRowIsCompleted(row);
    case 'cancelled':
      return cashReportRowIsCancelled(row);
    default:
      return true;
  }
}

/// Ngưỡng lọc giá trị cao (VND).
abstract final class CashReportAmountThresholds {
  static const int oneMillion = 1000000;
  static const int fiveMillion = 5000000;
  static const int tenMillion = 10000000;
  static const int fiftyMillion = 50000000;
}

bool cashReportMatchesAmountFilter(Map<String, dynamic> row, int? minAmount) {
  if (minAmount == null || minAmount <= 0) return true;
  return cashReportRowAmount(row) >= minAmount;
}

bool cashReportMatchesCategoryFilter(
  Map<String, dynamic> row,
  String? categoryKey,
) {
  if (categoryKey == null || categoryKey.isEmpty) return true;
  final id = row['categoryId']?.toString() ?? row['CategoryId']?.toString();
  if (id != null && id.isNotEmpty && id == categoryKey) return true;
  final name = row['categoryName']?.toString() ?? row['CategoryName']?.toString() ?? '';
  return name == categoryKey;
}

String cashReportStatusFilterLabel(String filter) {
  switch (filter) {
    case 'paid_income':
      return 'Đã thu';
    case 'paid_expense':
      return 'Đã chi';
    case 'completed':
      return 'Đã vào/ra quỹ';
    case 'pending_income':
      return 'Chờ thu';
    case 'pending_expense':
      return 'Chờ chi';
    case 'pending':
      return 'Chờ thanh toán';
    case 'cancelled':
      return 'Đã hủy';
    default:
      return filter;
  }
}

String cashReportAmountFilterLabel(int? minAmount) {
  if (minAmount == null || minAmount <= 0) return 'Tất cả';
  if (minAmount >= CashReportAmountThresholds.fiftyMillion) return '≥ 50 triệu';
  if (minAmount >= CashReportAmountThresholds.tenMillion) return '≥ 10 triệu';
  if (minAmount >= CashReportAmountThresholds.fiveMillion) return '≥ 5 triệu';
  if (minAmount >= CashReportAmountThresholds.oneMillion) return '≥ 1 triệu';
  return '≥ ${_fmtShort(minAmount)}';
}

String _fmtShort(int v) {
  if (v >= 1000000) return '${v ~/ 1000000} triệu';
  if (v >= 1000) return '${v ~/ 1000} nghìn';
  return '$v';
}
