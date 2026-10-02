/// Hợp đồng từ báo giá: mốc tiến độ, đợt thanh toán, các lần thu (API /api/pos/quotes/{id}/contract).
library;

double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

double? _nn(dynamic v) {
  if (v == null) return null;
  final d = v is num ? v.toDouble() : double.tryParse('$v');
  return d;
}

DateTime? _d(dynamic v) {
  final s = v?.toString().trim() ?? '';
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

String? _s(dynamic v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

dynamic _k(Map<String, dynamic> j, String camel) =>
    j[camel] ?? j[camel[0].toUpperCase() + camel.substring(1)];

class PosContractStage {
  PosContractStage({
    this.id,
    required this.title,
    this.percent,
    this.amount = 0,
    this.dueDate,
    this.note,
    this.paid = 0,
    this.remaining = 0,
    this.status = 'pending',
  });

  String? id;
  String title;
  double? percent;
  double amount;
  DateTime? dueDate;
  String? note;
  double paid;
  double remaining;

  /// paid · partial · overdue · pending
  String status;

  factory PosContractStage.fromJson(Map<String, dynamic> j) => PosContractStage(
        id: _s(_k(j, 'id')),
        title: _s(_k(j, 'title')) ?? '',
        percent: _nn(_k(j, 'percent')),
        amount: _n(_k(j, 'amount')),
        dueDate: _d(_k(j, 'dueDate')),
        note: _s(_k(j, 'note')),
        paid: _n(_k(j, 'paid')),
        remaining: _n(_k(j, 'remaining')),
        status: _s(_k(j, 'status')) ?? 'pending',
      );

  Map<String, dynamic> toInputJson() => {
        if (id != null) 'id': id,
        'title': title,
        'percent': percent,
        'amount': amount,
        'dueDate': dueDate == null ? null : dateOnly(dueDate!),
        'note': note,
      };

  static String statusLabel(String s) => switch (s) {
        'paid' => 'Đã thu đủ',
        'partial' => 'Thu một phần',
        'overdue' => 'Quá hạn',
        _ => 'Chưa thu',
      };
}

class PosContractPayment {
  PosContractPayment({
    required this.id,
    this.stageId,
    this.stageTitle,
    required this.amount,
    required this.paidAt,
    this.paymentMethod,
    this.note,
    this.collectedBy,
    this.cashCode,
  });

  final String id;
  final String? stageId;
  final String? stageTitle;
  final double amount;
  final DateTime paidAt;
  final String? paymentMethod;
  final String? note;
  final String? collectedBy;
  final String? cashCode;

  factory PosContractPayment.fromJson(Map<String, dynamic> j) => PosContractPayment(
        id: _s(_k(j, 'id')) ?? '',
        stageId: _s(_k(j, 'stageId')),
        stageTitle: _s(_k(j, 'stageTitle')),
        amount: _n(_k(j, 'amount')),
        paidAt: _d(_k(j, 'paidAt')) ?? DateTime.now(),
        paymentMethod: _s(_k(j, 'paymentMethod')),
        note: _s(_k(j, 'note')),
        collectedBy: _s(_k(j, 'collectedBy')),
        cashCode: _s(_k(j, 'cashCode')),
      );
}

class PosQuoteContract {
  PosQuoteContract({
    required this.quoteId,
    required this.quoteNo,
    this.customerName,
    this.total = 0,
    this.depositAmount = 0,
    this.contractNo,
    this.contractSignedAt,
    this.productionDueAt,
    this.installDueAt,
    this.handoverDueAt,
    this.contractNote,
    this.collected = 0,
    this.remaining = 0,
    this.overdueAmount = 0,
    this.nextDueDate,
    this.nextDueTitle,
    this.stages = const [],
    this.payments = const [],
  });

  final String quoteId;
  final String quoteNo;
  final String? customerName;
  final double total;
  final double depositAmount;
  final String? contractNo;
  final DateTime? contractSignedAt;
  final DateTime? productionDueAt;
  final DateTime? installDueAt;
  final DateTime? handoverDueAt;
  final String? contractNote;
  final double collected;
  final double remaining;
  final double overdueAmount;
  final DateTime? nextDueDate;
  final String? nextDueTitle;
  final List<PosContractStage> stages;
  final List<PosContractPayment> payments;

  factory PosQuoteContract.fromJson(Map<String, dynamic> j) => PosQuoteContract(
        quoteId: _s(_k(j, 'quoteId')) ?? '',
        quoteNo: _s(_k(j, 'quoteNo')) ?? '',
        customerName: _s(_k(j, 'customerName')),
        total: _n(_k(j, 'total')),
        depositAmount: _n(_k(j, 'depositAmount')),
        contractNo: _s(_k(j, 'contractNo')),
        contractSignedAt: _d(_k(j, 'contractSignedAt')),
        productionDueAt: _d(_k(j, 'productionDueAt')),
        installDueAt: _d(_k(j, 'installDueAt')),
        handoverDueAt: _d(_k(j, 'handoverDueAt')),
        contractNote: _s(_k(j, 'contractNote')),
        collected: _n(_k(j, 'collected')),
        remaining: _n(_k(j, 'remaining')),
        overdueAmount: _n(_k(j, 'overdueAmount')),
        nextDueDate: _d(_k(j, 'nextDueDate')),
        nextDueTitle: _s(_k(j, 'nextDueTitle')),
        stages: ((_k(j, 'stages') as List?) ?? const [])
            .whereType<Map>()
            .map((e) => PosContractStage.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        payments: ((_k(j, 'payments') as List?) ?? const [])
            .whereType<Map>()
            .map((e) => PosContractPayment.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );
}

/// Một dòng công nợ hợp đồng (API /api/pos/quotes/receivables).
class PosContractReceivable {
  PosContractReceivable({
    required this.quoteId,
    required this.quoteNo,
    this.contractNo,
    this.customerName,
    this.customerPhone,
    this.total = 0,
    this.collected = 0,
    this.remaining = 0,
    this.overdueAmount = 0,
    this.nextDueDate,
    this.nextDueTitle,
    this.installDueAt,
    this.handoverDueAt,
  });

  final String quoteId;
  final String quoteNo;
  final String? contractNo;
  final String? customerName;
  final String? customerPhone;
  final double total;
  final double collected;
  final double remaining;
  final double overdueAmount;
  final DateTime? nextDueDate;
  final String? nextDueTitle;
  final DateTime? installDueAt;
  final DateTime? handoverDueAt;

  factory PosContractReceivable.fromJson(Map<String, dynamic> j) => PosContractReceivable(
        quoteId: _s(_k(j, 'quoteId')) ?? '',
        quoteNo: _s(_k(j, 'quoteNo')) ?? '',
        contractNo: _s(_k(j, 'contractNo')),
        customerName: _s(_k(j, 'customerName')),
        customerPhone: _s(_k(j, 'customerPhone')),
        total: _n(_k(j, 'total')),
        collected: _n(_k(j, 'collected')),
        remaining: _n(_k(j, 'remaining')),
        overdueAmount: _n(_k(j, 'overdueAmount')),
        nextDueDate: _d(_k(j, 'nextDueDate')),
        nextDueTitle: _s(_k(j, 'nextDueTitle')),
        installDueAt: _d(_k(j, 'installDueAt')),
        handoverDueAt: _d(_k(j, 'handoverDueAt')),
      );
}

/// `yyyy-MM-dd` — hạn / mốc hợp đồng là ngày, không giờ.
String dateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
