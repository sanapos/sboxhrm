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
  final String? note;
  final double totalPurchase;
  final double currentDebt;

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
    this.note,
    this.totalPurchase = 0,
    this.currentDebt = 0,
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
      note: json['note'] ?? json['Note'] as String?,
      totalPurchase: n(json['totalPurchase'] ?? json['TotalPurchase']),
      currentDebt: n(json['currentDebt'] ?? json['CurrentDebt']),
    );
  }
}
