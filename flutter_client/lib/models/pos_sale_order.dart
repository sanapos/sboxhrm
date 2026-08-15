import 'dart:convert';

import '../utils/api_datetime.dart';
import '../utils/pos_doc_status.dart';
import 'pos_product.dart' show parsePosStringList;

class PosSaleLineTopping {
  final String id;
  final String name;
  final double price;

  const PosSaleLineTopping({
    required this.id,
    required this.name,
    required this.price,
  });

  factory PosSaleLineTopping.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? json['Id'] ?? '').toString();
    final name = (json['name'] ?? json['Name'] ?? '').toString();
    final priceRaw = json['price'] ?? json['Price'];
    final price = priceRaw is num
        ? priceRaw.toDouble()
        : double.tryParse('$priceRaw') ?? 0;
    return PosSaleLineTopping(
      id: id.isEmpty ? name : id,
      name: name.isEmpty ? id : name,
      price: price,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
      };
}

List<PosSaleLineTopping> parsePosSaleLineToppings(dynamic raw) {
  if (raw == null) return const [];
  dynamic decoded = raw;
  if (raw is String) {
    if (raw.trim().isEmpty) return const [];
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const [];
    }
  }
  if (decoded is! List) return const [];
  final out = <PosSaleLineTopping>[];
  for (final e in decoded) {
    if (e is! Map) continue;
    final t = PosSaleLineTopping.fromJson(Map<String, dynamic>.from(e));
    if (t.id.isEmpty && t.name.isEmpty) continue;
    out.add(t);
  }
  return out;
}

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
  final int? durationMinutes;
  final int? billableMinutes;
  final DateTime? serviceStartedAt;
  final DateTime? serviceEndedAt;
  final double kitchenSentQty;
  final DateTime? kitchenSentAt;
  final List<PosSaleLineTopping> toppings;

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
    this.durationMinutes,
    this.billableMinutes,
    this.serviceStartedAt,
    this.serviceEndedAt,
    this.kitchenSentQty = 0,
    this.kitchenSentAt,
    this.toppings = const [],
  });

  factory PosSaleOrderLine.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    int? i(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
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
      durationMinutes: i(json['durationMinutes'] ?? json['DurationMinutes']),
      billableMinutes: i(json['billableMinutes'] ?? json['BillableMinutes']),
      serviceStartedAt:
          parseApiDateTime(json['serviceStartedAt'] ?? json['ServiceStartedAt']),
      serviceEndedAt:
          parseApiDateTime(json['serviceEndedAt'] ?? json['ServiceEndedAt']),
      kitchenSentQty: n(json['kitchenSentQty'] ?? json['KitchenSentQty']),
      kitchenSentAt:
          parseApiDateTime(json['kitchenSentAt'] ?? json['KitchenSentAt']),
      toppings: parsePosSaleLineToppings(
          json['toppingsJson'] ?? json['ToppingsJson']),
    );
  }

  /// Payload gọn cho Print Agent (Sunmi native) — tránh Agent phải gọi lại API.
  Map<String, dynamic> toPrintAgentJson() => {
        'id': id,
        'productId': productId,
        'variantId': variantId,
        'productName': productName,
        'unitName': unitName,
        'qty': qty,
        'unitPrice': unitPrice,
        'discountAmount': discountAmount,
        'lineTotal': lineTotal,
        'lineNote': lineNote,
        'returnedQty': returnedQty,
        'serialNumbers': serialNumbers,
        'toppingsJson': toppings.map((t) => t.toJson()).toList(),
      };
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
  final double vatAmount;
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
  final String? priceListId;
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
  final String? serviceResourceId;
  final String? resourceSessionId;
  final DateTime? serviceStartedAt;
  final DateTime? serviceEndedAt;
  final String? serviceResourceCode;
  final String? serviceResourceName;
  final String? serviceAreaName;
  final String? splitFromOrderId;
  final int lockVersion;
  final bool isLocked;
  final bool isLockedByMe;
  final String? lockedByDisplayName;
  final String? lockedByDeviceId;
  final String? lockedByDeviceName;
  final DateTime? lockExpiresAt;
  final String? eInvoiceStatus;
  final String? eInvoiceProvider;
  final String? eInvoiceNo;
  final String? eInvoiceSeries;
  final String? eInvoiceReservationCode;
  final String? eInvoiceCode;
  final DateTime? eInvoiceIssuedAt;
  final String? eInvoiceError;
  final String? eInvoiceBuyerName;
  final String? eInvoiceBuyerTaxCode;

  PosSaleOrder({
    required this.id,
    required this.orderNo,
    this.status = 'Draft',
    this.returnStatus,
    this.subTotal = 0,
    this.discount = 0,
    this.total = 0,
    this.vatAmount = 0,
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
    this.priceListId,
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
    this.serviceResourceId,
    this.resourceSessionId,
    this.serviceStartedAt,
    this.serviceEndedAt,
    this.serviceResourceCode,
    this.serviceResourceName,
    this.serviceAreaName,
    this.splitFromOrderId,
    this.lockVersion = 0,
    this.isLocked = false,
    this.isLockedByMe = false,
    this.lockedByDisplayName,
    this.lockedByDeviceId,
    this.lockedByDeviceName,
    this.lockExpiresAt,
    this.eInvoiceStatus,
    this.eInvoiceProvider,
    this.eInvoiceNo,
    this.eInvoiceSeries,
    this.eInvoiceReservationCode,
    this.eInvoiceCode,
    this.eInvoiceIssuedAt,
    this.eInvoiceError,
    this.eInvoiceBuyerName,
    this.eInvoiceBuyerTaxCode,
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
        vatAmount: vatAmount,
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
        priceListId: priceListId,
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
        serviceResourceId: serviceResourceId,
        resourceSessionId: resourceSessionId,
        serviceStartedAt: serviceStartedAt,
        serviceEndedAt: serviceEndedAt,
        serviceResourceCode: serviceResourceCode,
        serviceResourceName: serviceResourceName,
        serviceAreaName: serviceAreaName,
        lockVersion: lockVersion,
        isLocked: isLocked,
        isLockedByMe: isLockedByMe,
        lockedByDisplayName: lockedByDisplayName,
        lockedByDeviceId: lockedByDeviceId,
        lockedByDeviceName: lockedByDeviceName,
        lockExpiresAt: lockExpiresAt,
        eInvoiceStatus: eInvoiceStatus,
        eInvoiceProvider: eInvoiceProvider,
        eInvoiceNo: eInvoiceNo,
        eInvoiceSeries: eInvoiceSeries,
        eInvoiceReservationCode: eInvoiceReservationCode,
        eInvoiceCode: eInvoiceCode,
        eInvoiceIssuedAt: eInvoiceIssuedAt,
        eInvoiceError: eInvoiceError,
        eInvoiceBuyerName: eInvoiceBuyerName,
        eInvoiceBuyerTaxCode: eInvoiceBuyerTaxCode,
        splitFromOrderId: splitFromOrderId,
      );

  String? get lockBadgeLabel {
    if (!isLocked) return null;
    if (isLockedByMe) return 'Bạn đang giữ';
    final who = (lockedByDisplayName ?? '').trim();
    final device = (lockedByDeviceName ?? '').trim();
    if (who.isEmpty && device.isEmpty) return 'Đang mở trên máy khác';
    if (who.isEmpty) return 'Đang mở · $device';
    if (device.isEmpty) return 'Đang mở bởi $who';
    return 'Đang mở bởi $who · $device';
  }

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
    int i(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final linesRaw = json['lines'] ?? json['Lines'];
    final lines = linesRaw is List
        ? linesRaw
            .map((e) => PosSaleOrderLine.fromJson(e as Map<String, dynamic>))
            .toList()
        : <PosSaleOrderLine>[];
    final total = n(json['total'] ?? json['Total']);
    final vat = n(json['vatAmount'] ?? json['VatAmount']);
    final paid = n(json['paidAmount'] ?? json['PaidAmount']);
    final hasBalance =
        json.containsKey('balanceDue') || json.containsKey('BalanceDue');
    final balance = n(json['balanceDue'] ?? json['BalanceDue']);
    final payable = total + vat;
    return PosSaleOrder(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      orderNo: (json['orderNo'] ?? json['OrderNo'] ?? '').toString(),
      status: normalizePosDocStatus(json['status'] ?? json['Status']),
      returnStatus: (json['returnStatus'] ?? json['ReturnStatus'])?.toString(),
      subTotal: n(json['subTotal'] ?? json['SubTotal']),
      discount: n(json['discount'] ?? json['Discount']),
      total: total,
      vatAmount: vat,
      paidAmount: paid,
      balanceDue: hasBalance ? balance : payable - paid,
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
      priceListId: (json['priceListId'] ?? json['PriceListId'])?.toString(),
      priceListName: json['priceListName'] ?? json['PriceListName'] as String?,
      voucherCode: json['voucherCode'] ?? json['VoucherCode'] as String?,
      voucherDiscount: n(json['voucherDiscount'] ?? json['VoucherDiscount']),
      pointsRedeemed: n(json['pointsRedeemed'] ?? json['PointsRedeemed']),
      pointsDiscount: n(json['pointsDiscount'] ?? json['PointsDiscount']),
      pointsEarned: n(json['pointsEarned'] ?? json['PointsEarned']),
      createdAt: parseApiDateTime(json['createdAt'] ?? json['CreatedAt']),
      createdBy: json['createdBy'] ?? json['CreatedBy'] as String?,
      lineCount: i(json['lineCount'] ?? json['LineCount']) > 0
          ? i(json['lineCount'] ?? json['LineCount'])
          : lines.length,
      lines: lines,
      printCount: i(json['printCount'] ?? json['PrintCount']),
      dailyOrderIndex: i(json['dailyOrderIndex'] ?? json['DailyOrderIndex']),
      dailySalesTotal: n(json['dailySalesTotal'] ?? json['DailySalesTotal']),
      serviceResourceId:
          (json['serviceResourceId'] ?? json['ServiceResourceId'])?.toString(),
      resourceSessionId:
          (json['resourceSessionId'] ?? json['ResourceSessionId'])?.toString(),
      serviceStartedAt:
          parseApiDateTime(json['serviceStartedAt'] ?? json['ServiceStartedAt']),
      serviceEndedAt:
          parseApiDateTime(json['serviceEndedAt'] ?? json['ServiceEndedAt']),
      serviceResourceCode:
          (json['serviceResourceCode'] ?? json['ServiceResourceCode'])
              ?.toString(),
      serviceResourceName:
          (json['serviceResourceName'] ?? json['ServiceResourceName'])
              ?.toString(),
      serviceAreaName:
          (json['serviceAreaName'] ?? json['ServiceAreaName'])?.toString(),
      splitFromOrderId:
          (json['splitFromOrderId'] ?? json['SplitFromOrderId'])?.toString(),
      lockVersion: i(json['lockVersion'] ?? json['LockVersion']),
      isLocked: json['isLocked'] == true || json['IsLocked'] == true,
      isLockedByMe:
          json['isLockedByMe'] == true || json['IsLockedByMe'] == true,
      lockedByDisplayName:
          (json['lockedByDisplayName'] ?? json['LockedByDisplayName'])
              ?.toString(),
      lockedByDeviceId:
          (json['lockedByDeviceId'] ?? json['LockedByDeviceId'])?.toString(),
      lockedByDeviceName:
          (json['lockedByDeviceName'] ?? json['LockedByDeviceName'])
              ?.toString(),
      lockExpiresAt:
          parseApiDateTime(json['lockExpiresAt'] ?? json['LockExpiresAt']),
      eInvoiceStatus:
          (json['eInvoiceStatus'] ?? json['EInvoiceStatus'])?.toString(),
      eInvoiceProvider:
          (json['eInvoiceProvider'] ?? json['EInvoiceProvider'])?.toString(),
      eInvoiceNo: (json['eInvoiceNo'] ?? json['EInvoiceNo'])?.toString(),
      eInvoiceSeries:
          (json['eInvoiceSeries'] ?? json['EInvoiceSeries'])?.toString(),
      eInvoiceReservationCode: (json['eInvoiceReservationCode'] ??
              json['EInvoiceReservationCode'])
          ?.toString(),
      eInvoiceCode: (json['eInvoiceCode'] ?? json['EInvoiceCode'])?.toString(),
      eInvoiceIssuedAt:
          parseApiDateTime(json['eInvoiceIssuedAt'] ?? json['EInvoiceIssuedAt']),
      eInvoiceError:
          (json['eInvoiceError'] ?? json['EInvoiceError'])?.toString(),
      eInvoiceBuyerName:
          (json['eInvoiceBuyerName'] ?? json['EInvoiceBuyerName'])?.toString(),
      eInvoiceBuyerTaxCode: (json['eInvoiceBuyerTaxCode'] ??
              json['EInvoiceBuyerTaxCode'])
          ?.toString(),
    );
  }

  /// Payload gọn cho Print Agent — cùng dữ liệu Oppo đang xem, không phụ thuộc getPosSale.
  Map<String, dynamic> toPrintAgentJson() => {
        'id': id,
        'orderNo': orderNo,
        'status': status,
        'subTotal': subTotal,
        'discount': discount,
        'total': total,
        'vatAmount': vatAmount,
        'paidAmount': paidAmount,
        'balanceDue': balanceDue,
        'paymentMethod': paymentMethod,
        'customerName': customerName,
        'customerPhone': customerPhone,
        'isDelivery': isDelivery,
        'deliveryAddress': deliveryAddress,
        'note': note,
        'saleDate': saleDate?.toIso8601String(),
        'soldBy': soldBy,
        'createdAt': createdAt?.toIso8601String(),
        'printCount': printCount,
        'dailyOrderIndex': dailyOrderIndex,
        'serviceResourceName': serviceResourceName,
        'serviceAreaName': serviceAreaName,
        'lines': lines.map((l) => l.toPrintAgentJson()).toList(),
      };
}
