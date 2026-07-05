class PosVoucher {
  final String id;
  final String code;
  final String? name;
  final String discountType;
  final double discountValue;
  final double minOrderAmount;
  final double? maxDiscountAmount;
  final DateTime? validFrom;
  final DateTime? validTo;
  final int? maxUses;
  final int usedCount;
  final String? customerId;
  final bool isActive;

  PosVoucher({
    required this.id,
    required this.code,
    this.name,
    required this.discountType,
    this.discountValue = 0,
    this.minOrderAmount = 0,
    this.maxDiscountAmount,
    this.validFrom,
    this.validTo,
    this.maxUses,
    this.usedCount = 0,
    this.customerId,
    this.isActive = true,
  });

  bool get isPercent =>
      discountType.toLowerCase() == 'percent' ||
      discountType == '1';

  factory PosVoucher.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    int i(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    DateTime? dt(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    return PosVoucher(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      code: (json['code'] ?? json['Code'] ?? '').toString(),
      name: json['name'] ?? json['Name'] as String?,
      discountType: (json['discountType'] ?? json['DiscountType'] ?? 'Fixed').toString(),
      discountValue: n(json['discountValue'] ?? json['DiscountValue']),
      minOrderAmount: n(json['minOrderAmount'] ?? json['MinOrderAmount']),
      maxDiscountAmount: json['maxDiscountAmount'] != null || json['MaxDiscountAmount'] != null
          ? n(json['maxDiscountAmount'] ?? json['MaxDiscountAmount'])
          : null,
      validFrom: dt(json['validFrom'] ?? json['ValidFrom']),
      validTo: dt(json['validTo'] ?? json['ValidTo']),
      maxUses: json['maxUses'] != null || json['MaxUses'] != null
          ? i(json['maxUses'] ?? json['MaxUses'])
          : null,
      usedCount: i(json['usedCount'] ?? json['UsedCount']),
      customerId: json['customerId']?.toString() ?? json['CustomerId']?.toString(),
      isActive: json['isActive'] == true || json['IsActive'] == true,
    );
  }

  Map<String, dynamic> toSaveBody() => {
        'code': code,
        'name': name,
        'discountType': isPercent ? 1 : 0,
        'discountValue': discountValue,
        'minOrderAmount': minOrderAmount,
        if (maxDiscountAmount != null) 'maxDiscountAmount': maxDiscountAmount,
        if (validFrom != null) 'validFrom': validFrom!.toIso8601String(),
        if (validTo != null) 'validTo': validTo!.toIso8601String(),
        if (maxUses != null) 'maxUses': maxUses,
        if (customerId != null && customerId!.isNotEmpty) 'customerId': customerId,
        'isActive': isActive,
      };
}
