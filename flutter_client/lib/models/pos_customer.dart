class PosCustomer {
  final String id;
  final String customerCode;
  final String name;
  final String? phone;
  final String? email;
  final String? address;
  final String? province;
  final String? ward;
  final String? companyName;
  final String? taxCode;
  final String? legalRepresentative;
  final String? legalTitle;
  final String? note;
  final DateTime? birthday;
  final String? deliveryAddress;
  final double totalPurchase;
  final double currentDebt;
  final double pointBalance;
  final bool isActive;

  /// Lần mua gần nhất (UTC) và số đơn hoàn tất — chỉ có ở danh sách khách.
  final DateTime? lastPurchaseAt;
  final int orderCount;

  /// Sinh nhật rơi vào hôm nay / [days] ngày tới (theo ngày-tháng).
  bool birthdayWithin(int days, {DateTime? now}) {
    final b = birthday;
    if (b == null) return false;
    final t = now ?? DateTime.now();
    final today = DateTime(t.year, t.month, t.day);
    for (var i = 0; i < days; i++) {
      final d = today.add(Duration(days: i));
      if (d.month == b.month && d.day == b.day) return true;
    }
    return false;
  }

  PosCustomer({
    required this.id,
    required this.customerCode,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.province,
    this.ward,
    this.companyName,
    this.taxCode,
    this.legalRepresentative,
    this.legalTitle,
    this.note,
    this.birthday,
    this.deliveryAddress,
    this.totalPurchase = 0,
    this.currentDebt = 0,
    this.pointBalance = 0,
    this.isActive = true,
    this.lastPurchaseAt,
    this.orderCount = 0,
  });

  factory PosCustomer.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return PosCustomer(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      customerCode: (json['customerCode'] ?? json['CustomerCode'] ?? '').toString(),
      name: (json['name'] ?? json['Name'] ?? '').toString(),
      phone: json['phone'] ?? json['Phone'] as String?,
      email: json['email'] ?? json['Email'] as String?,
      address: json['address'] ?? json['Address'] as String?,
      province: json['province'] ?? json['Province'] as String?,
      ward: json['ward'] ?? json['Ward'] as String?,
      companyName: json['companyName'] ?? json['CompanyName'] as String?,
      taxCode: json['taxCode'] ?? json['TaxCode'] as String?,
      legalRepresentative:
          json['legalRepresentative'] ?? json['LegalRepresentative'] as String?,
      legalTitle: json['legalTitle'] ?? json['LegalTitle'] as String?,
      note: json['note'] ?? json['Note'] as String?,
      birthday: DateTime.tryParse(
          '${json['birthday'] ?? json['Birthday'] ?? ''}'),
      deliveryAddress: json['deliveryAddress'] ?? json['DeliveryAddress'] as String?,
      totalPurchase: n(json['totalPurchase'] ?? json['TotalPurchase']),
      currentDebt: n(json['currentDebt'] ?? json['CurrentDebt']),
      pointBalance: n(json['pointBalance'] ?? json['PointBalance']),
      isActive: (json['isActive'] ?? json['IsActive']) != false,
      lastPurchaseAt: DateTime.tryParse('${json['lastPurchaseAt'] ?? json['LastPurchaseAt'] ?? ''}'),
      orderCount: (json['orderCount'] ?? json['OrderCount'] ?? 0) is num
          ? ((json['orderCount'] ?? json['OrderCount'] ?? 0) as num).toInt()
          : 0,
    );
  }
}
