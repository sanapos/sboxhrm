import '../utils/api_datetime.dart';
import '../utils/pos_doc_status.dart';
import 'pos_product.dart' show parsePosStringList;

class PosSaleOrderLine {
  final String? id;
  final String productId;
  final String? variantId;
  final String productName;
  final String? unitName;
  final double qty;
  final double unitPrice;
  final double discountAmount;
  final double lineTotal;
  final String? lineNote;
  final double returnedQty;
  final List<String> serialNumbers;

  PosSaleOrderLine({
    this.id,
    required this.productId,
    this.variantId,
    required this.productName,
    this.unitName,
    this.qty = 1,
    this.unitPrice = 0,
    this.discountAmount = 0,
    this.lineTotal = 0,
    this.lineNote,
    this.returnedQty = 0,
    this.serialNumbers = const [],
  });

  factory PosSaleOrderLine.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return PosSaleOrderLine(
      id: (json['id'] ?? json['Id'])?.toString(),
      productId: (json['productId'] ?? json['ProductId']).toString(),
      variantId: (json['variantId'] ?? json['VariantId'])?.toString(),
      productName: (json['productName'] ?? json['ProductName'] ?? '').toString(),
      unitName: json['unitName'] ?? json['UnitName'] as String?,
      qty: n(json['qty'] ?? json['Qty']),
      unitPrice: n(json['unitPrice'] ?? json['UnitPrice']),
      discountAmount: n(json['discountAmount'] ?? json['DiscountAmount']),
      lineTotal: n(json['lineTotal'] ?? json['LineTotal']),
      lineNote: json['lineNote'] ?? json['LineNote'] as String?,
      returnedQty: n(json['returnedQty'] ?? json['ReturnedQty']),
      serialNumbers: json['serialNumbers'] != null || json['SerialNumbers'] != null
          ? parsePosStringList(json['serialNumbers'] ?? json['SerialNumbers'])
          : const [],
    );
  }
}

class PosSaleOrder {
  final String id;
  final String orderNo;
  final String status;
  /// `Partial` | `Full` when order has customer returns (status stays Completed).
  final String? returnStatus;
  final double subTotal;
  final double discount;
  final double total;
  final double paidAmount;
  final double balanceDue;
  final double returnedAmount;
  final String paymentMethod;
  final String? customerName;
  final String? customerId;
  final String? customerCode;
  final String? customerPhone;
  final bool isDelivery;
  final String? deliveryAddress;
  final String? deliveryPhone;
  final String? deliveryPartner;
  final String? deliveryStatus;
  final DateTime? deliveryDate;
  final String? note;
  final DateTime? saleDate;
  final String? soldBy;
  final String? soldByEmployeeId;
  final String? salesChannel;
  final String? priceListName;
  final String? voucherCode;
  final double voucherDiscount;
  final double pointsRedeemed;
  final double pointsDiscount;
  final double pointsEarned;
  final DateTime? createdAt;
  final String? createdBy;
  final int lineCount;
  final List<PosSaleOrderLine> lines;
  final int printCount;
  final int dailyOrderIndex;
  final double dailySalesTotal;

  PosSaleOrder({
    required this.id,
    required this.orderNo,
    this.status = 'Draft',
    this.returnStatus,
    this.subTotal = 0,
    this.discount = 0,
    this.total = 0,
    this.paidAmount = 0,
    this.balanceDue = 0,
    this.returnedAmount = 0,
    this.paymentMethod = 'Tiền mặt',
    this.customerName,
    this.customerId,
    this.customerCode,
    this.customerPhone,
    this.isDelivery = false,
    this.deliveryAddress,
    this.deliveryPhone,
    this.deliveryPartner,
    this.deliveryStatus,
    this.deliveryDate,
    this.note,
    this.saleDate,
    this.soldBy,
    this.soldByEmployeeId,
    this.salesChannel,
    this.priceListName,
    this.voucherCode,
    this.voucherDiscount = 0,
    this.pointsRedeemed = 0,
    this.pointsDiscount = 0,
    this.pointsEarned = 0,
    this.createdAt,
    this.createdBy,
    this.lineCount = 0,
    this.lines = const [],
    this.printCount = 0,
    this.dailyOrderIndex = 0,
    this.dailySalesTotal = 0,
  });

  PosSaleOrder copyWithPrintContext({
    int? printCount,
    int? dailyOrderIndex,
    double? dailySalesTotal,
  }) =>
      PosSaleOrder(
        id: id,
        orderNo: orderNo,
        status: status,
        returnStatus: returnStatus,
        subTotal: subTotal,
        discount: discount,
        total: total,
        paidAmount: paidAmount,
        balanceDue: balanceDue,
        returnedAmount: returnedAmount,
        paymentMethod: paymentMethod,
        customerName: customerName,
        customerId: customerId,
        customerCode: customerCode,
        customerPhone: customerPhone,
        isDelivery: isDelivery,
        deliveryAddress: deliveryAddress,
        deliveryPhone: deliveryPhone,
        deliveryPartner: deliveryPartner,
        deliveryStatus: deliveryStatus,
        deliveryDate: deliveryDate,
        note: note,
        saleDate: saleDate,
        soldBy: soldBy,
        soldByEmployeeId: soldByEmployeeId,
        salesChannel: salesChannel,
        priceListName: priceListName,
        voucherCode: voucherCode,
        voucherDiscount: voucherDiscount,
        pointsRedeemed: pointsRedeemed,
        pointsDiscount: pointsDiscount,
        pointsEarned: pointsEarned,
        createdAt: createdAt,
        createdBy: createdBy,
        lineCount: lineCount,
        lines: lines,
        printCount: printCount ?? this.printCount,
        dailyOrderIndex: dailyOrderIndex ?? this.dailyOrderIndex,
        dailySalesTotal: dailySalesTotal ?? this.dailySalesTotal,
      );

  bool get isReprint => printCount > 1;

  /// Tổng gốc trước khi trả (net + đã trả).
  double get grossTotal => total + returnedAmount;

  bool get hasReturns => returnedAmount > 0;

  bool get isFullyReturned => returnStatus == 'Full';

  bool get isPartiallyReturned => returnStatus == 'Partial';

  /// Ẩn khỏi danh sách: đơn nháp, đã hủy, hoặc đã trả hết 100%.
  bool get canDeleteFromList =>
      status == 'Cancelled' ||
      status == 'Draft' ||
      (status == 'Completed' && isFullyReturned);

  /// Hủy đơn (hoàn kho) — chỉ khi chưa có trả hàng khách.
  bool get canCancelWithStock => status == 'Completed' && !hasReturns;

  factory PosSaleOrder.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    final linesRaw = json['lines'] ?? json['Lines'];
    final lines = linesRaw is List
        ? linesRaw
            .map((e) => PosSaleOrderLine.fromJson(e as Map<String, dynamic>))
            .toList()
        : <PosSaleOrderLine>[];
    final total = n(json['total'] ?? json['Total']);
    final paid = n(json['paidAmount'] ?? json['PaidAmount']);
    final balance = n(json['balanceDue'] ?? json['BalanceDue']);
    return PosSaleOrder(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      orderNo: (json['orderNo'] ?? json['OrderNo'] ?? '').toString(),
      status: normalizePosDocStatus(json['status'] ?? json['Status']),
      returnStatus: (json['returnStatus'] ?? json['ReturnStatus'])?.toString(),
      subTotal: n(json['subTotal'] ?? json['SubTotal']),
      discount: n(json['discount'] ?? json['Discount']),
      total: total,
      paidAmount: paid,
      balanceDue: balance != 0 ? balance : total - paid,
      returnedAmount: n(json['returnedAmount'] ?? json['ReturnedAmount']),
      paymentMethod:
          (json['paymentMethod'] ?? json['PaymentMethod'] ?? 'Tiền mặt').toString(),
      customerName: json['customerName'] ?? json['CustomerName'] as String?,
      customerId: (json['customerId'] ?? json['CustomerId'])?.toString(),
      customerCode: json['customerCode'] ?? json['CustomerCode'] as String?,
      customerPhone: json['customerPhone'] ?? json['CustomerPhone'] as String?,
      isDelivery: json['isDelivery'] == true || json['IsDelivery'] == true,
      deliveryAddress: json['deliveryAddress'] ?? json['DeliveryAddress'] as String?,
      deliveryPhone: json['deliveryPhone'] ?? json['DeliveryPhone'] as String?,
      deliveryPartner: json['deliveryPartner'] ?? json['DeliveryPartner'] as String?,
      deliveryStatus: json['deliveryStatus'] ?? json['DeliveryStatus'] as String?,
      deliveryDate: parseApiDateTime(json['deliveryDate'] ?? json['DeliveryDate']),
      note: json['note'] ?? json['Note'] as String?,
      saleDate: parseApiDateTime(json['saleDate'] ?? json['SaleDate']),
      soldBy: json['soldBy'] ?? json['SoldBy'] as String?,
      soldByEmployeeId:
          (json['soldByEmployeeId'] ?? json['SoldByEmployeeId'])?.toString(),
      salesChannel: json['salesChannel'] ?? json['SalesChannel'] as String?,
      priceListName: json['priceListName'] ?? json['PriceListName'] as String?,
      voucherCode: json['voucherCode'] ?? json['VoucherCode'] as String?,
      voucherDiscount: n(json['voucherDiscount'] ?? json['VoucherDiscount']),
      pointsRedeemed: n(json['pointsRedeemed'] ?? json['PointsRedeemed']),
      pointsDiscount: n(json['pointsDiscount'] ?? json['PointsDiscount']),
      pointsEarned: n(json['pointsEarned'] ?? json['PointsEarned']),
      createdAt: parseApiDateTime(json['createdAt'] ?? json['CreatedAt']),
      createdBy: json['createdBy'] ?? json['CreatedBy'] as String?,
      lineCount: (json['lineCount'] ?? json['LineCount'] as num?)?.toInt() ??
          lines.length,
      lines: lines,
      printCount: (json['printCount'] ?? json['PrintCount'] as num?)?.toInt() ?? 0,
      dailyOrderIndex:
          (json['dailyOrderIndex'] ?? json['DailyOrderIndex'] as num?)?.toInt() ?? 0,
      dailySalesTotal: n(json['dailySalesTotal'] ?? json['DailySalesTotal']),
    );
  }
}
