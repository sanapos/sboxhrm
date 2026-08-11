import '../utils/api_datetime.dart';
import '../utils/pos_doc_status.dart';

class PosSupplierGroup {
  final String id;
  final String name;
  PosSupplierGroup({required this.id, required this.name});
  factory PosSupplierGroup.fromJson(Map<String, dynamic> json) => PosSupplierGroup(
        id: (json['id'] ?? json['Id']).toString(),
        name: (json['name'] ?? json['Name'] ?? '').toString(),
      );
}

class PosSupplierFull {
  final String id;
  final String supplierCode;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? province;
  final String? ward;
  final String? groupId;
  final String? groupName;
  final String? companyName;
  final String? taxCode;
  final String? identityNo;
  final String? note;
  final double totalPurchase;
  final double currentDebt;
  final bool isActive;

  PosSupplierFull({
    required this.id,
    required this.supplierCode,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.province,
    this.ward,
    this.groupId,
    this.groupName,
    this.companyName,
    this.taxCode,
    this.identityNo,
    this.note,
    this.totalPurchase = 0,
    this.currentDebt = 0,
    this.isActive = true,
  });

  factory PosSupplierFull.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return PosSupplierFull(
      id: (json['id'] ?? json['Id']).toString(),
      supplierCode: (json['supplierCode'] ?? json['SupplierCode'] ?? '').toString(),
      name: (json['name'] ?? json['Name'] ?? '').toString(),
      phone: json['phone'] ?? json['Phone'] as String?,
      email: json['email'] ?? json['Email'] as String?,
      address: json['address'] ?? json['Address'] as String?,
      province: json['province'] ?? json['Province'] as String?,
      ward: json['ward'] ?? json['Ward'] as String?,
      groupId: (json['groupId'] ?? json['GroupId'])?.toString(),
      groupName: json['groupName'] ?? json['GroupName'] as String?,
      companyName: json['companyName'] ?? json['CompanyName'] as String?,
      taxCode: json['taxCode'] ?? json['TaxCode'] as String?,
      identityNo: json['identityNo'] ?? json['IdentityNo'] as String?,
      note: json['note'] ?? json['Note'] as String?,
      totalPurchase: n(json['totalPurchase'] ?? json['TotalPurchase']),
      currentDebt: n(json['currentDebt'] ?? json['CurrentDebt']),
      isActive: json['isActive'] != false && json['IsActive'] != false,
    );
  }

  Map<String, dynamic> toSaveJson() => {
        'name': name,
        'phone': phone,
        'email': email,
        'address': address,
        'province': province,
        'ward': ward,
        'groupId': groupId,
        'companyName': companyName,
        'taxCode': taxCode,
        'identityNo': identityNo,
        'note': note,
      };
}

class PosPurchaseLine {
  final String? id;
  final String productId;
  final String? variantId;
  final String productCode;
  final String productName;
  final String? unitName;
  final double qty;
  final double costPrice;
  final double discountAmount;
  final double vatRate;
  final double vatAmount;
  final bool vatIncluded;
  final bool vatExempt;
  final double lineTotal;
  final String? lineNote;
  final String? lotNo;
  final DateTime? manufactureDate;
  final DateTime? expiryDate;
  final bool trackExpiry;
  final bool allowDecimalQty;

  PosPurchaseLine({
    this.id,
    required this.productId,
    this.variantId,
    this.productCode = '',
    required this.productName,
    this.unitName,
    this.qty = 1,
    this.costPrice = 0,
    this.discountAmount = 0,
    this.vatRate = 0,
    this.vatAmount = 0,
    this.vatIncluded = false,
    this.vatExempt = false,
    this.lineTotal = 0,
    this.lineNote,
    this.lotNo,
    this.manufactureDate,
    this.expiryDate,
    this.trackExpiry = false,
    this.allowDecimalQty = false,
  });

  factory PosPurchaseLine.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return PosPurchaseLine(
      id: (json['id'] ?? json['Id'])?.toString(),
      productId: (json['productId'] ?? json['ProductId']).toString(),
      variantId: (json['variantId'] ?? json['VariantId'])?.toString(),
      productCode: (json['productCode'] ?? json['ProductCode'] ?? '').toString(),
      productName: (json['productName'] ?? json['ProductName'] ?? '').toString(),
      unitName: json['unitName'] ?? json['UnitName'] as String?,
      qty: n(json['qty'] ?? json['Qty']),
      costPrice: n(json['costPrice'] ?? json['CostPrice']),
      discountAmount: n(json['discountAmount'] ?? json['DiscountAmount']),
      vatRate: n(json['vatRate'] ?? json['VatRate']),
      vatAmount: n(json['vatAmount'] ?? json['VatAmount']),
      vatIncluded: json['vatIncluded'] == true || json['VatIncluded'] == true,
      vatExempt: json['vatExempt'] == true || json['VatExempt'] == true,
      lineTotal: n(json['lineTotal'] ?? json['LineTotal']),
      lineNote: json['lineNote'] ?? json['LineNote'] as String?,
      lotNo: json['lotNo'] ?? json['LotNo'] as String?,
      manufactureDate: parseApiUtcDateTime(json['manufactureDate'] ?? json['ManufactureDate']),
      expiryDate: parseApiUtcDateTime(json['expiryDate'] ?? json['ExpiryDate']),
      trackExpiry: json['trackExpiry'] == true || json['TrackExpiry'] == true,
      allowDecimalQty:
          json['allowDecimalQty'] == true || json['AllowDecimalQty'] == true,
    );
  }

  Map<String, dynamic> toInputJson() => {
        'productId': productId,
        if (variantId != null) 'variantId': variantId,
        'qty': qty,
        'costPrice': costPrice,
        'discountAmount': discountAmount,
        'vatRate': vatRate,
        'vatIncluded': vatIncluded,
        'vatExempt': vatExempt,
        if (unitName != null) 'unitName': unitName,
        if (lineNote != null) 'lineNote': lineNote,
        if (lotNo != null && lotNo!.isNotEmpty) 'lotNo': lotNo,
        if (manufactureDate != null) 'manufactureDate': manufactureDate!.toUtc().toIso8601String(),
        if (expiryDate != null) 'expiryDate': expiryDate!.toUtc().toIso8601String(),
      };
}

class PosPurchaseReceipt {
  final String id;
  final String receiptNo;
  final String? supplierId;
  final String? supplierCode;
  final String? supplierName;
  final String status;
  final String? note;
  final String? inputInvoiceNo;
  final String? purchaseOrderNo;
  final double totalQty;
  final double totalCost;
  final double totalVat;
  final double discountAmount;
  final bool discountIsPercent;
  final double discountInput;
  final double paidAmount;
  final double grandTotal;
  final double balanceDue;
  final DateTime? importDate;
  final String? importedBy;
  final DateTime? createdAt;
  final String? createdBy;
  final List<PosPurchaseLine> lines;

  PosPurchaseReceipt({
    required this.id,
    required this.receiptNo,
    this.supplierId,
    this.supplierCode,
    this.supplierName,
    this.status = 'Draft',
    this.note,
    this.inputInvoiceNo,
    this.purchaseOrderNo,
    this.totalQty = 0,
    this.totalCost = 0,
    this.totalVat = 0,
    this.discountAmount = 0,
    this.discountIsPercent = false,
    this.discountInput = 0,
    this.paidAmount = 0,
    this.grandTotal = 0,
    this.balanceDue = 0,
    this.importDate,
    this.importedBy,
    this.createdAt,
    this.createdBy,
    this.lines = const [],
  });

  factory PosPurchaseReceipt.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return PosPurchaseReceipt(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      receiptNo: (json['receiptNo'] ?? json['ReceiptNo'] ?? '').toString(),
      supplierId: (json['supplierId'] ?? json['SupplierId'])?.toString(),
      supplierCode: json['supplierCode'] ?? json['SupplierCode'] as String?,
      supplierName: json['supplierName'] ?? json['SupplierName'] as String?,
      status: normalizePosDocStatus(json['status'] ?? json['Status']),
      note: json['note'] ?? json['Note'] as String?,
      inputInvoiceNo: json['inputInvoiceNo'] ?? json['InputInvoiceNo'] as String?,
      purchaseOrderNo: json['purchaseOrderNo'] ?? json['PurchaseOrderNo'] as String?,
      totalQty: n(json['totalQty'] ?? json['TotalQty']),
      totalCost: n(json['totalCost'] ?? json['TotalCost']),
      totalVat: n(json['totalVat'] ?? json['TotalVat']),
      discountAmount: n(json['discountAmount'] ?? json['DiscountAmount']),
      discountIsPercent: json['discountIsPercent'] == true || json['DiscountIsPercent'] == true,
      discountInput: n(json['discountInput'] ?? json['DiscountInput']),
      paidAmount: n(json['paidAmount'] ?? json['PaidAmount']),
      grandTotal: n(json['grandTotal'] ?? json['GrandTotal']),
      balanceDue: n(json['balanceDue'] ?? json['BalanceDue']),
      importDate: parseApiUtcDateTime(json['importDate'] ?? json['ImportDate']),
      importedBy: json['importedBy'] ?? json['ImportedBy'] as String?,
      createdAt: parseApiUtcDateTime(json['createdAt'] ?? json['CreatedAt']),
      createdBy: json['createdBy'] ?? json['CreatedBy'] as String?,
      lines: ((json['lines'] ?? json['Lines']) as List?)
              ?.map((e) => PosPurchaseLine.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  String get statusLabel => switch (status) {
        'Completed' => 'Đã nhập hàng',
        'Cancelled' => 'Đã hủy',
        _ => 'Phiếu tạm',
      };
}

class PosPurchaseReturn {
  final String id;
  final String returnNo;
  final String? supplierId;
  final String? supplierName;
  final String? sourceReceiptId;
  final String? sourceReceiptNo;
  final String status;
  final String? note;
  final double totalAmount;
  final double discountAmount;
  final double refundDue;
  final double refundReceived;
  final DateTime? returnDate;
  final String? createdBy;
  final String? returnedBy;
  final List<PosPurchaseLine> lines;

  PosPurchaseReturn({
    required this.id,
    required this.returnNo,
    this.supplierId,
    this.supplierName,
    this.sourceReceiptId,
    this.sourceReceiptNo,
    this.status = 'Draft',
    this.note,
    this.totalAmount = 0,
    this.discountAmount = 0,
    this.refundDue = 0,
    this.refundReceived = 0,
    this.returnDate,
    this.createdBy,
    this.returnedBy,
    this.lines = const [],
  });

  factory PosPurchaseReturn.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return PosPurchaseReturn(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      returnNo: (json['returnNo'] ?? json['ReturnNo'] ?? '').toString(),
      supplierId: (json['supplierId'] ?? json['SupplierId'])?.toString(),
      supplierName: json['supplierName'] ?? json['SupplierName'] as String?,
      sourceReceiptId: (json['sourceReceiptId'] ?? json['SourceReceiptId'])?.toString(),
      sourceReceiptNo: json['sourceReceiptNo'] ?? json['SourceReceiptNo'] as String?,
      status: normalizePosDocStatus(json['status'] ?? json['Status']),
      note: json['note'] ?? json['Note'] as String?,
      totalAmount: n(json['totalAmount'] ?? json['TotalAmount']),
      discountAmount: n(json['discountAmount'] ?? json['DiscountAmount']),
      refundDue: n(json['refundDue'] ?? json['RefundDue']),
      refundReceived: n(json['refundReceived'] ?? json['RefundReceived']),
      returnDate: parseApiUtcDateTime(json['returnDate'] ?? json['ReturnDate']),
      createdBy: json['createdBy'] ?? json['CreatedBy'] as String?,
      returnedBy: json['returnedBy'] ?? json['ReturnedBy'] as String?,
      lines: ((json['lines'] ?? json['Lines']) as List?)
              ?.map((e) => PosPurchaseLine.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  double get supplierRefundAmount => totalAmount - discountAmount;

  String get statusLabel => switch (status) {
        'Completed' => 'Đã trả hàng',
        'Cancelled' => 'Đã hủy',
        _ => 'Phiếu tạm',
      };
}

String purchaseStatusColor(String status) => switch (status) {
      'Completed' => '#22c55e',
      'Cancelled' => '#94a3b8',
      _ => '#f59e0b',
    };
