class PosQuoteLine {
  PosQuoteLine({
    this.id = '',
    this.productId,
    this.productCode,
    required this.productName,
    this.unitName,
    this.qty = 1,
    this.unitPrice = 0,
    this.discountAmount = 0,
    this.vatRate = 0,
    this.lineTotal = 0,
    this.lineNote,
    this.sortOrder = 0,
  });

  String id;
  String? productId;
  String? productCode;
  String productName;
  String? unitName;
  double qty;
  double unitPrice;
  double discountAmount;
  double vatRate;
  double lineTotal;
  String? lineNote;
  int sortOrder;

  double get net => (qty * unitPrice - discountAmount).clamp(0, double.infinity);

  factory PosQuoteLine.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return PosQuoteLine(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      productId: (json['productId'] ?? json['ProductId'])?.toString(),
      productCode: (json['productCode'] ?? json['ProductCode'])?.toString(),
      productName:
          (json['productName'] ?? json['ProductName'] ?? '').toString(),
      unitName: (json['unitName'] ?? json['UnitName'])?.toString(),
      qty: n(json['qty'] ?? json['Qty']),
      unitPrice: n(json['unitPrice'] ?? json['UnitPrice']),
      discountAmount: n(json['discountAmount'] ?? json['DiscountAmount']),
      vatRate: n(json['vatRate'] ?? json['VatRate']),
      lineTotal: n(json['lineTotal'] ?? json['LineTotal']),
      lineNote: (json['lineNote'] ?? json['LineNote'])?.toString(),
      sortOrder: (json['sortOrder'] ?? json['SortOrder'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toInputJson() => {
        if (productId != null && productId!.isNotEmpty) 'productId': productId,
        'productCode': productCode,
        'productName': productName,
        'unitName': unitName,
        'qty': qty,
        'unitPrice': unitPrice,
        'discountAmount': discountAmount,
        'vatRate': vatRate,
        'lineNote': lineNote,
      };
}

class PosQuoteDocument {
  PosQuoteDocument({
    required this.id,
    required this.kind,
    required this.docNo,
    required this.title,
    this.htmlContent = '',
    this.note,
    this.issuedAt,
    this.issuedBy,
    this.stockIssueId,
    this.stockIssueNo,
  });

  final String id;
  final String kind;
  final String docNo;
  final String title;
  final String htmlContent;
  final String? note;
  final DateTime? issuedAt;
  final String? issuedBy;
  final String? stockIssueId;
  final String? stockIssueNo;

  factory PosQuoteDocument.fromJson(Map<String, dynamic> json) {
    DateTime? d(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    return PosQuoteDocument(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      kind: (json['kind'] ?? json['Kind'] ?? '').toString(),
      docNo: (json['docNo'] ?? json['DocNo'] ?? '').toString(),
      title: (json['title'] ?? json['Title'] ?? '').toString(),
      htmlContent: (json['htmlContent'] ?? json['HtmlContent'] ?? '').toString(),
      note: (json['note'] ?? json['Note'])?.toString(),
      issuedAt: d(json['issuedAt'] ?? json['IssuedAt']),
      issuedBy: (json['issuedBy'] ?? json['IssuedBy'])?.toString(),
      stockIssueId: (json['stockIssueId'] ?? json['StockIssueId'])?.toString(),
      stockIssueNo: (json['stockIssueNo'] ?? json['StockIssueNo'])?.toString(),
    );
  }

  static String kindLabel(String k) => switch (k) {
        'Quote' => 'Báo giá',
        'Contract' => 'Hợp đồng',
        'Handover' => 'Bàn giao',
        'Acceptance' => 'Nghiệm thu',
        'StockIssue' => 'Xuất kho',
        _ => k,
      };
}

class PosQuote {
  PosQuote({
    required this.id,
    required this.quoteNo,
    required this.status,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.customerAddress,
    this.validUntil,
    this.issuedAt,
    this.issuedBy,
    this.subTotal = 0,
    this.discount = 0,
    this.vatAmount = 0,
    this.total = 0,
    this.note,
    this.terms,
    this.printTemplateId,
    this.revision = 1,
    this.quotedBy,
    this.commercialStage = 'None',
    this.createdAt,
    this.lines = const [],
    this.documents = const [],
  });

  final String id;
  final String quoteNo;
  final String status;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? customerAddress;
  final DateTime? validUntil;
  final DateTime? issuedAt;
  final String? issuedBy;
  final double subTotal;
  final double discount;
  final double vatAmount;
  final double total;
  final String? note;
  final String? terms;
  final String? printTemplateId;
  final int revision;
  final String? quotedBy;
  final String commercialStage;
  final DateTime? createdAt;
  final List<PosQuoteLine> lines;
  final List<PosQuoteDocument> documents;

  bool get isLocked =>
      status == 'Accepted' ||
      status == 'Rejected' ||
      status == 'Expired' ||
      status == 'Cancelled';

  bool get canSend => status == 'Draft' || status == 'Revised';
  bool get canDecide => status == 'Sent' || status == 'Revised';
  bool get canDelete => status == 'Draft';
  bool get canIssueDocs =>
      status == 'Accepted' && commercialStage != 'Closed';
  bool get canClose =>
      status == 'Accepted' && commercialStage == 'Inspected';

  static String statusLabel(String s) => switch (s) {
        'Draft' => 'Nháp',
        'Sent' => 'Đã gửi',
        'Revised' => 'Đã sửa',
        'Accepted' => 'Chấp nhận',
        'Rejected' => 'Từ chối',
        'Expired' => 'Hết hạn',
        'Cancelled' => 'Đã hủy',
        _ => s,
      };

  static String stageLabel(String s) => switch (s) {
        'None' => 'Chưa triển khai',
        'Accepted' => 'Đã nhận BG',
        'Contracted' => 'Đã lập HĐ',
        'Issued' => 'Đã xuất kho',
        'HandedOver' => 'Đã bàn giao',
        'Inspected' => 'Đã nghiệm thu',
        'Closed' => 'Đã đóng',
        _ => s,
      };

  factory PosQuote.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    DateTime? d(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    final rawLines = json['lines'] ?? json['Lines'];
    final rawDocs = json['documents'] ?? json['Documents'];
    return PosQuote(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      quoteNo: (json['quoteNo'] ?? json['QuoteNo'] ?? '').toString(),
      status: (json['status'] ?? json['Status'] ?? 'Draft').toString(),
      customerId: (json['customerId'] ?? json['CustomerId'])?.toString(),
      customerName: (json['customerName'] ?? json['CustomerName'])?.toString(),
      customerPhone:
          (json['customerPhone'] ?? json['CustomerPhone'])?.toString(),
      customerAddress:
          (json['customerAddress'] ?? json['CustomerAddress'])?.toString(),
      validUntil: d(json['validUntil'] ?? json['ValidUntil']),
      issuedAt: d(json['issuedAt'] ?? json['IssuedAt']),
      issuedBy: (json['issuedBy'] ?? json['IssuedBy'])?.toString(),
      subTotal: n(json['subTotal'] ?? json['SubTotal']),
      discount: n(json['discount'] ?? json['Discount']),
      vatAmount: n(json['vatAmount'] ?? json['VatAmount']),
      total: n(json['total'] ?? json['Total']),
      note: (json['note'] ?? json['Note'])?.toString(),
      terms: (json['terms'] ?? json['Terms'])?.toString(),
      printTemplateId:
          (json['printTemplateId'] ?? json['PrintTemplateId'])?.toString(),
      revision: (json['revision'] ?? json['Revision'] as num?)?.toInt() ?? 1,
      quotedBy: (json['quotedBy'] ?? json['QuotedBy'])?.toString(),
      commercialStage:
          (json['commercialStage'] ?? json['CommercialStage'] ?? 'None')
              .toString(),
      createdAt: d(json['createdAt'] ?? json['CreatedAt']),
      lines: rawLines is List
          ? rawLines
              .whereType<Map>()
              .map((e) => PosQuoteLine.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      documents: rawDocs is List
          ? rawDocs
              .whereType<Map>()
              .map((e) =>
                  PosQuoteDocument.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }
}
