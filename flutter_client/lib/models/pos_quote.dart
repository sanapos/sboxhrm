import 'package:flutter/material.dart';

import '../utils/pos_area_dims.dart';

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
    this.length,
    this.width,
    this.height,
    this.warrantyMonths,
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
  double? length;
  double? width;
  double? height;
  int? warrantyMonths;
  int sortOrder;

  double get net => (qty * unitPrice - discountAmount).clamp(0, double.infinity);

  factory PosQuoteLine.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    double? dim(dynamic v) {
      if (v == null) return null;
      final parsed = v is num ? v.toDouble() : double.tryParse('$v');
      if (parsed == null || parsed <= 0) return null;
      return parsed;
    }

    int? i(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse('$v');
    }

    final note = (json['lineNote'] ?? json['LineNote'])?.toString();
    final fromNote = parsePosAreaDims(note);
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
      lineNote: note,
      length: dim(json['length'] ?? json['Length']) ?? fromNote.length,
      width: dim(json['width'] ?? json['Width']) ?? fromNote.width,
      height: dim(json['height'] ?? json['Height']) ?? fromNote.height,
      warrantyMonths: i(json['warrantyMonths'] ?? json['WarrantyMonths']),
      sortOrder: i(json['sortOrder'] ?? json['SortOrder']) ?? 0,
    );
  }

  static bool _isGuid(String? s) {
    final v = (s ?? '').trim();
    if (v.isEmpty) return false;
    return RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')
        .hasMatch(v);
  }

  Map<String, dynamic> toInputJson() {
    final net = (qty * unitPrice - discountAmount).clamp(0, double.infinity);
    final total = lineTotal > 0 ? lineTotal : net * (1 + vatRate / 100);
    return {
      if (_isGuid(id)) 'id': id.trim(),
      if (_isGuid(productId)) 'productId': productId!.trim(),
      'productCode': productCode,
      'productName': productName,
      'unitName': unitName,
      'qty': qty,
      'unitPrice': unitPrice,
      'discountAmount': discountAmount,
      'vatRate': vatRate,
      'lineTotal': total,
      'lineNote': lineNote,
      'length': length,
      'width': width,
      'height': height,
      if (warrantyMonths != null) 'warrantyMonths': warrantyMonths,
    };
  }
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
        'PaymentRequest' => 'Đề nghị thanh toán',
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
    this.paymentMethod,
    this.depositAmount = 0,
    this.depositPercent,
    this.printTemplateId,
    this.revision = 1,
    this.quotedBy,
    this.quotedByEmployeeId,
    this.quotedByEmployeeName,
    this.commercialStage = 'None',
    this.potentialScore,
    this.includeImages = false,
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
  final String? paymentMethod;
  final double depositAmount;
  final double? depositPercent;
  final String? printTemplateId;
  final int revision;
  final String? quotedBy;
  final String? quotedByEmployeeId;
  final String? quotedByEmployeeName;
  final String commercialStage;

  /// Điểm tiềm năng khách gần nhất, thang 0–10.
  final int? potentialScore;

  /// Phiếu in của báo giá này chèn ảnh sản phẩm.
  final bool includeImages;
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

  static Color statusColor(String s) => switch (s) {
        'Draft' => const Color(0xFF64748B),
        'Sent' => const Color(0xFF2563EB),
        'Revised' => const Color(0xFFD97706),
        'Accepted' => const Color(0xFF15803D),
        'Rejected' => const Color(0xFFDC2626),
        'Expired' => const Color(0xFF9A3412),
        'Cancelled' => const Color(0xFF71717A),
        _ => const Color(0xFF334155),
      };

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
      paymentMethod:
          (json['paymentMethod'] ?? json['PaymentMethod'])?.toString(),
      depositAmount: n(json['depositAmount'] ?? json['DepositAmount']),
      depositPercent: () {
        final v = json['depositPercent'] ?? json['DepositPercent'];
        if (v == null) return null;
        return n(v);
      }(),
      printTemplateId:
          (json['printTemplateId'] ?? json['PrintTemplateId'])?.toString(),
      revision: (json['revision'] is num
              ? (json['revision'] as num).toInt()
              : (json['Revision'] is num
                  ? (json['Revision'] as num).toInt()
                  : int.tryParse('${json['revision'] ?? json['Revision']}'))) ??
          1,
      quotedBy: (json['quotedBy'] ?? json['QuotedBy'])?.toString(),
      quotedByEmployeeId:
          (json['quotedByEmployeeId'] ?? json['QuotedByEmployeeId'])?.toString(),
      quotedByEmployeeName: (json['quotedByEmployeeName'] ??
              json['QuotedByEmployeeName'])
          ?.toString(),
      commercialStage:
          (json['commercialStage'] ?? json['CommercialStage'] ?? 'None')
              .toString(),
      potentialScore: _score010(json['potentialScore'] ?? json['PotentialScore']),
      includeImages: json['includeImages'] == true ||
          json['IncludeImages'] == true,
      createdAt: d(json['createdAt'] ?? json['CreatedAt']),
      lines: parseLines(rawLines),
      documents: rawDocs is List
          ? [
              for (final e in rawDocs)
                if (e is Map)
                  PosQuoteDocument.fromJson(Map<String, dynamic>.from(e)),
            ]
          : const [],
    );
  }

  PosQuoteDocument? get quoteSlip {
    for (final d in documents) {
      if (d.kind == 'Quote' && d.htmlContent.trim().isNotEmpty) return d;
    }
    for (final d in documents) {
      if (d.htmlContent.trim().isNotEmpty) return d;
    }
    return null;
  }

  static List<PosQuoteLine> parseLines(dynamic raw) {
    if (raw is! List) return [];
    final out = <PosQuoteLine>[];
    for (final e in raw) {
      if (e is Map) {
        out.add(PosQuoteLine.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    return out;
  }

  String get staffLabel {
    final n = (quotedByEmployeeName ?? '').trim();
    if (n.isNotEmpty) return n;
    return (quotedBy ?? '').trim();
  }
}

int? _score010(dynamic v) {
  if (v == null) return null;
  final n = v is num ? v.toInt() : int.tryParse('$v');
  if (n == null || n < 0 || n > 10) return null;
  return n;
}

class PosQuoteActivity {
  PosQuoteActivity({
    required this.id,
    required this.kind,
    required this.content,
    this.nextFollowUpAt,
    this.employeeId,
    this.employeeName,
    this.createdBy,
    this.createdAt,
    this.potentialScore,
  });

  static final _scoreMark = RegExp(r'^\[\[TN:(\d{1,2})\]\]\s?');

  final String id;
  final String kind;
  final String content;
  final DateTime? nextFollowUpAt;
  final String? employeeId;
  final String? employeeName;
  final String? createdBy;
  final DateTime? createdAt;
  final int? potentialScore;

  int? get score {
    if (potentialScore != null) return potentialScore;
    final m = _scoreMark.firstMatch(content);
    if (m == null) return null;
    final n = int.tryParse(m.group(1)!);
    if (n == null || n < 0 || n > 10) return null;
    return n;
  }

  String get displayContent => content.replaceFirst(_scoreMark, '');

  static String encodeContent(String text, int score) =>
      '[[TN:$score]] ${text.trim()}';

  static Color scoreColor(int score) {
    if (score <= 3) return const Color(0xFFDC2626);
    if (score <= 6) return const Color(0xFFD97706);
    return const Color(0xFF15803D);
  }

  static String kindLabel(String k) => switch (k) {
        'Created' => 'Tạo báo giá',
        'Edit' => 'Sửa báo giá',
        'Call' => 'Gọi khách',
        'Note' => 'Ghi chú',
        'Meeting' => 'Gặp khách',
        'FollowUp' => 'Hẹn chăm sóc',
        'Status' => 'Trạng thái',
        _ => k,
      };

  factory PosQuoteActivity.fromJson(Map<String, dynamic> json) {
    DateTime? d(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    return PosQuoteActivity(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      kind: (json['kind'] ?? json['Kind'] ?? 'Note').toString(),
      content: (json['content'] ?? json['Content'] ?? '').toString(),
      nextFollowUpAt: d(json['nextFollowUpAt'] ?? json['NextFollowUpAt']),
      employeeId: (json['employeeId'] ?? json['EmployeeId'])?.toString(),
      employeeName: (json['employeeName'] ?? json['EmployeeName'])?.toString(),
      createdBy: (json['createdBy'] ?? json['CreatedBy'])?.toString(),
      createdAt: d(json['createdAt'] ?? json['CreatedAt']),
      potentialScore:
          _score010(json['potentialScore'] ?? json['PotentialScore']),
    );
  }
}
