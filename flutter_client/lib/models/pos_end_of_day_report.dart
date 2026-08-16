class PosEndOfDayProduct {
  final String productId;
  final String productName;
  final double qty;
  final double revenue;
  final double lineDiscount;

  const PosEndOfDayProduct({
    required this.productId,
    required this.productName,
    required this.qty,
    required this.revenue,
    this.lineDiscount = 0,
  });

  factory PosEndOfDayProduct.fromJson(Map<String, dynamic> json) => PosEndOfDayProduct(
        productId: json['productId']?.toString() ?? '',
        productName: json['productName']?.toString() ?? '',
        qty: _num(json['qty']),
        revenue: _num(json['revenue']),
        lineDiscount: _num(json['lineDiscount']),
      );
}

class PosEndOfDayPayment {
  final String paymentMethod;
  final double total;
  final int count;

  const PosEndOfDayPayment({
    required this.paymentMethod,
    required this.total,
    required this.count,
  });

  factory PosEndOfDayPayment.fromJson(Map<String, dynamic> json) => PosEndOfDayPayment(
        paymentMethod: json['paymentMethod']?.toString() ?? '',
        total: _num(json['total']),
        count: (json['count'] as num?)?.toInt() ?? 0,
      );
}

class PosEndOfDayOffDayOrder {
  final String orderNo;
  final DateTime? draftedOn;
  final DateTime? orderNoDate;
  final DateTime? saleDate;
  final double total;

  const PosEndOfDayOffDayOrder({
    required this.orderNo,
    this.draftedOn,
    this.orderNoDate,
    this.saleDate,
    this.total = 0,
  });

  factory PosEndOfDayOffDayOrder.fromJson(Map<String, dynamic> json) =>
      PosEndOfDayOffDayOrder(
        orderNo: json['orderNo']?.toString() ?? '',
        draftedOn: DateTime.tryParse(json['draftedOn']?.toString() ?? ''),
        orderNoDate: DateTime.tryParse(json['orderNoDate']?.toString() ?? ''),
        saleDate: DateTime.tryParse(json['saleDate']?.toString() ?? ''),
        total: _num(json['total']),
      );

  String get draftDayLabel {
    final d = orderNoDate ?? draftedOn;
    if (d == null) return '';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return 'nháp $dd/$mm';
  }
}

class PosEndOfDayTransaction {
  final String orderNo;
  final DateTime createdAt;
  final DateTime? draftedAt;
  final bool closedOffDay;
  final String? note;
  final double qty;
  final double revenue;
  final double otherIncome;
  final double vat;
  final double rounding;
  final double returnFee;
  final double actualReceived;
  final String paymentMethod;

  const PosEndOfDayTransaction({
    required this.orderNo,
    required this.createdAt,
    this.draftedAt,
    this.closedOffDay = false,
    this.note,
    required this.qty,
    required this.revenue,
    this.otherIncome = 0,
    this.vat = 0,
    this.rounding = 0,
    this.returnFee = 0,
    required this.actualReceived,
    this.paymentMethod = '',
  });

  factory PosEndOfDayTransaction.fromJson(Map<String, dynamic> json) => PosEndOfDayTransaction(
        orderNo: json['orderNo']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
        draftedAt: DateTime.tryParse(json['draftedAt']?.toString() ?? ''),
        closedOffDay: json['closedOffDay'] == true,
        note: json['note']?.toString(),
        qty: _num(json['qty']),
        revenue: _num(json['revenue']),
        otherIncome: _num(json['otherIncome']),
        vat: _num(json['vat']),
        rounding: _num(json['rounding']),
        returnFee: _num(json['returnFee']),
        actualReceived: _num(json['actualReceived']),
        paymentMethod: json['paymentMethod']?.toString() ?? '',
      );
}

class PosEndOfDayReport {
  final DateTime from;
  final DateTime to;
  final String filterBy;
  final String? staffEmail;
  final String? staffName;
  final String? storeName;
  final DateTime generatedAt;
  final int orderCount;
  final double orderDiscount;
  final double totalSales;
  final double vat;
  final double netSales;
  final double refundTotal;
  final double totalAfterRefund;
  final int canceledCount;
  final double canceledTotal;
  final double cashTotal;
  final double debtTotal;
  final double actualReceived;
  final double lineDiscountTotal;
  final int closedOffDayCount;
  final List<PosEndOfDayOffDayOrder> closedOffDayOrders;
  final List<PosEndOfDayPayment> payments;
  final List<PosEndOfDayProduct> products;
  final List<PosEndOfDayTransaction> transactions;

  const PosEndOfDayReport({
    required this.from,
    required this.to,
    required this.filterBy,
    this.staffEmail,
    this.staffName,
    this.storeName,
    required this.generatedAt,
    required this.orderCount,
    required this.orderDiscount,
    required this.totalSales,
    required this.vat,
    required this.netSales,
    required this.refundTotal,
    required this.totalAfterRefund,
    required this.canceledCount,
    required this.canceledTotal,
    required this.cashTotal,
    required this.debtTotal,
    required this.actualReceived,
    required this.lineDiscountTotal,
    this.closedOffDayCount = 0,
    this.closedOffDayOrders = const [],
    this.payments = const [],
    this.products = const [],
    this.transactions = const [],
  });

  factory PosEndOfDayReport.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(dynamic raw, T Function(Map<String, dynamic>) map) {
      if (raw is! List) return [];
      return raw.whereType<Map>().map((e) => map(Map<String, dynamic>.from(e))).toList();
    }

    return PosEndOfDayReport(
      from: DateTime.tryParse(json['from']?.toString() ?? '') ?? DateTime.now(),
      to: DateTime.tryParse(json['to']?.toString() ?? '') ?? DateTime.now(),
      filterBy: json['filterBy']?.toString() ?? 'soldBy',
      staffEmail: json['staffEmail']?.toString(),
      staffName: json['staffName']?.toString(),
      storeName: json['storeName']?.toString(),
      generatedAt: DateTime.tryParse(json['generatedAt']?.toString() ?? '') ?? DateTime.now(),
      orderCount: (json['orderCount'] as num?)?.toInt() ?? 0,
      orderDiscount: _num(json['orderDiscount']),
      totalSales: _num(json['totalSales']),
      vat: _num(json['vat']),
      netSales: _num(json['netSales']),
      refundTotal: _num(json['refundTotal']),
      totalAfterRefund: _num(json['totalAfterRefund']),
      canceledCount: (json['canceledCount'] as num?)?.toInt() ?? 0,
      canceledTotal: _num(json['canceledTotal']),
      cashTotal: _num(json['cashTotal']),
      debtTotal: _num(json['debtTotal']),
      actualReceived: _num(json['actualReceived']),
      lineDiscountTotal: _num(json['lineDiscountTotal']),
      closedOffDayCount: (json['closedOffDayCount'] as num?)?.toInt() ?? 0,
      closedOffDayOrders:
          list(json['closedOffDayOrders'], PosEndOfDayOffDayOrder.fromJson),
      payments: list(json['payments'], PosEndOfDayPayment.fromJson),
      products: list(json['products'], PosEndOfDayProduct.fromJson),
      transactions: list(json['transactions'], PosEndOfDayTransaction.fromJson),
    );
  }
}

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0;
}

class PosEndOfDayStaff {
  final String email;
  final String? employeeId;
  final String displayName;
  final bool isSelf;

  const PosEndOfDayStaff({
    required this.email,
    this.employeeId,
    required this.displayName,
    this.isSelf = false,
  });

  factory PosEndOfDayStaff.fromJson(Map<String, dynamic> json) => PosEndOfDayStaff(
        email: json['email']?.toString() ?? '',
        employeeId: (json['employeeId'] ?? json['EmployeeId'])?.toString(),
        displayName: json['displayName']?.toString() ?? json['email']?.toString() ?? '',
        isSelf: json['isSelf'] == true,
      );
}
