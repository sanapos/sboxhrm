import '../utils/api_datetime.dart';
import '../utils/pos_doc_status.dart';

class PosStockIssueLine {
  final String id;
  final String productId;
  final String? variantId;
  final String productCode;
  final String productName;
  final String? unitName;
  final double qty;
  final double costPrice;
  final double lineTotal;
  final String? lineNote;

  PosStockIssueLine({
    required this.id,
    required this.productId,
    this.variantId,
    this.productCode = '',
    required this.productName,
    this.unitName,
    this.qty = 0,
    this.costPrice = 0,
    this.lineTotal = 0,
    this.lineNote,
  });

  factory PosStockIssueLine.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    final qty = n(json['qty'] ?? json['Qty']);
    final cost = n(json['costPrice'] ?? json['CostPrice']);
    return PosStockIssueLine(
      id: (json['id'] ?? json['Id']).toString(),
      productId: (json['productId'] ?? json['ProductId']).toString(),
      variantId: (json['variantId'] ?? json['VariantId'])?.toString(),
      productCode: (json['productCode'] ?? json['ProductCode'] ?? '').toString(),
      productName: (json['productName'] ?? json['ProductName'] ?? '').toString(),
      unitName: json['unitName'] ?? json['UnitName'] as String?,
      qty: qty,
      costPrice: cost,
      lineTotal: n(json['lineTotal'] ?? json['LineTotal'] ?? qty * cost),
      lineNote: json['lineNote'] ?? json['LineNote'] as String?,
    );
  }
}

class PosStockIssueDoc {
  final String id;
  final String issueNo;
  final String kind;
  final String status;
  final String? note;
  final String? categoryName;
  final String? recipientName;
  final DateTime? issuedAt;
  final String? issuedBy;
  final DateTime? completedAt;
  final double totalQty;
  final double totalValue;
  final DateTime? createdAt;
  final String? createdBy;
  final int lineCount;
  final List<PosStockIssueLine> lines;

  PosStockIssueDoc({
    required this.id,
    required this.issueNo,
    this.kind = '',
    this.status = 'Draft',
    this.note,
    this.categoryName,
    this.recipientName,
    this.issuedAt,
    this.issuedBy,
    this.completedAt,
    this.totalQty = 0,
    this.totalValue = 0,
    this.createdAt,
    this.createdBy,
    this.lineCount = 0,
    this.lines = const [],
  });

  factory PosStockIssueDoc.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    final lines = ((json['lines'] ?? json['Lines']) as List?)
            ?.map((e) => PosStockIssueLine.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    return PosStockIssueDoc(
      id: (json['id'] ?? json['Id']).toString(),
      issueNo: (json['issueNo'] ?? json['IssueNo'] ?? '').toString(),
      kind: (json['kind'] ?? json['Kind'] ?? '').toString(),
      status: normalizePosDocStatus(json['status'] ?? json['Status']),
      note: json['note'] ?? json['Note'] as String?,
      categoryName: json['categoryName'] ?? json['CategoryName'] as String?,
      recipientName: json['recipientName'] ?? json['RecipientName'] as String?,
      issuedAt: parseApiUtcDateTime(json['issuedAt'] ?? json['IssuedAt']),
      issuedBy: json['issuedBy'] ?? json['IssuedBy'] as String?,
      completedAt: parseApiUtcDateTime(json['completedAt'] ?? json['CompletedAt']),
      totalQty: n(json['totalQty'] ?? json['TotalQty']),
      totalValue: n(json['totalValue'] ?? json['TotalValue']),
      createdAt: parseApiUtcDateTime(json['createdAt'] ?? json['CreatedAt']),
      createdBy: json['createdBy'] ?? json['CreatedBy'] as String?,
      lineCount: (json['lineCount'] as num?)?.toInt() ?? lines.length,
      lines: lines,
    );
  }
}
