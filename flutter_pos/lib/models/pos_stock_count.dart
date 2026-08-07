import '../utils/api_datetime.dart';
import '../utils/pos_doc_status.dart';

class PosStockCountLine {
  final String id;
  final String productId;
  final String? variantId;
  final String productCode;
  final String productName;
  final String? unitName;
  final double systemQty;
  final double? countedQty;
  final bool isChecked;
  final double diffQty;
  final double diffValue;
  final double costPrice;

  PosStockCountLine({
    required this.id,
    required this.productId,
    this.variantId,
    this.productCode = '',
    required this.productName,
    this.unitName,
    this.systemQty = 0,
    this.countedQty,
    this.isChecked = false,
    this.diffQty = 0,
    this.diffValue = 0,
    this.costPrice = 0,
  });

  factory PosStockCountLine.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return PosStockCountLine(
      id: (json['id'] ?? json['Id']).toString(),
      productId: (json['productId'] ?? json['ProductId']).toString(),
      variantId: (json['variantId'] ?? json['VariantId'])?.toString(),
      productCode: (json['productCode'] ?? json['ProductCode'] ?? '').toString(),
      productName: (json['productName'] ?? json['ProductName'] ?? '').toString(),
      unitName: json['unitName'] ?? json['UnitName'] as String?,
      systemQty: n(json['systemQty'] ?? json['SystemQty']),
      countedQty: json['countedQty'] != null || json['CountedQty'] != null
          ? n(json['countedQty'] ?? json['CountedQty'])
          : null,
      isChecked: json['isChecked'] == true || json['IsChecked'] == true,
      diffQty: n(json['diffQty'] ?? json['DiffQty'] ?? json['diff'] ?? json['Diff']),
      diffValue: n(json['diffValue'] ?? json['DiffValue']),
      costPrice: n(json['costPrice'] ?? json['CostPrice']),
    );
  }

  bool get isMatched => countedQty != null && diffQty == 0;
  bool get hasDiff => countedQty != null && diffQty != 0;
  bool get isUnchecked => countedQty == null && !isChecked;
}

class PosStockCount {
  final String id;
  final String countNo;
  final String name;
  final String? note;
  final String status;
  final DateTime? completedAt;
  final DateTime? createdAt;
  final String? createdBy;
  final String? balancedBy;
  final double totalActualQty;
  final double totalActualValue;
  final double totalDiffQty;
  final double totalDiffValue;
  final double qtyIncrease;
  final double qtyDecrease;
  final List<PosStockCountLine> lines;

  PosStockCount({
    required this.id,
    required this.countNo,
    required this.name,
    this.note,
    this.status = 'InProgress',
    this.completedAt,
    this.createdAt,
    this.createdBy,
    this.balancedBy,
    this.totalActualQty = 0,
    this.totalActualValue = 0,
    this.totalDiffQty = 0,
    this.totalDiffValue = 0,
    this.qtyIncrease = 0,
    this.qtyDecrease = 0,
    this.lines = const [],
  });

  factory PosStockCount.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return PosStockCount(
      id: (json['id'] ?? json['Id']).toString(),
      countNo: (json['countNo'] ?? json['CountNo'] ?? '').toString(),
      name: (json['name'] ?? json['Name'] ?? '').toString(),
      note: json['note'] ?? json['Note'] as String?,
      status: normalizePosDocStatus(
        json['status'] ?? json['Status'],
        fallback: 'InProgress',
      ),
      completedAt: parseApiUtcDateTime(json['completedAt'] ?? json['CompletedAt']),
      createdAt: parseApiUtcDateTime(json['createdAt'] ?? json['CreatedAt']),
      createdBy: json['createdBy'] ?? json['CreatedBy'] as String?,
      balancedBy: json['balancedBy'] ?? json['BalancedBy'] as String?,
      totalActualQty: n(json['totalActualQty'] ?? json['TotalActualQty']),
      totalActualValue: n(json['totalActualValue'] ?? json['TotalActualValue']),
      totalDiffQty: n(json['totalDiffQty'] ?? json['TotalDiffQty']),
      totalDiffValue: n(json['totalDiffValue'] ?? json['TotalDiffValue']),
      qtyIncrease: n(json['qtyIncrease'] ?? json['QtyIncrease']),
      qtyDecrease: n(json['qtyDecrease'] ?? json['QtyDecrease']),
      lines: ((json['lines'] ?? json['Lines']) as List?)
              ?.map((e) => PosStockCountLine.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  String get statusLabel => switch (status) {
        'Completed' => 'Đã cân bằng kho',
        'Cancelled' => 'Đã hủy',
        _ => 'Phiếu tạm',
      };

  int get lineCount => lines.length;
  int get checkedCount => lines.where((l) => l.isChecked || l.countedQty != null).length;
}

String stockCountStatusColor(String status) => switch (status) {
      'Completed' => '#22c55e',
      'Cancelled' => '#94a3b8',
      _ => '#f59e0b',
    };
