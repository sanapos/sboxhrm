class FundTransfer {
  final String id;
  final String transferCode;
  final String? fromBankAccountId;
  final String fromFundLabel;
  final String? toBankAccountId;
  final String toFundLabel;
  final double amount;
  final DateTime transferDate;
  final String description;
  final String? internalNote;
  final String createdByUserName;

  FundTransfer({
    required this.id,
    required this.transferCode,
    this.fromBankAccountId,
    required this.fromFundLabel,
    this.toBankAccountId,
    required this.toFundLabel,
    required this.amount,
    required this.transferDate,
    required this.description,
    this.internalNote,
    required this.createdByUserName,
  });

  factory FundTransfer.fromJson(Map<String, dynamic> json) {
    return FundTransfer(
      id: json['id']?.toString() ?? '',
      transferCode: json['transferCode']?.toString() ?? '',
      fromBankAccountId: json['fromBankAccountId']?.toString(),
      fromFundLabel: json['fromFundLabel']?.toString() ?? 'Tiền mặt',
      toBankAccountId: json['toBankAccountId']?.toString(),
      toFundLabel: json['toFundLabel']?.toString() ?? 'Tiền mặt',
      amount: (json['amount'] ?? 0).toDouble(),
      transferDate: json['transferDate'] != null
          ? DateTime.parse(json['transferDate'].toString())
          : DateTime.now(),
      description: json['description']?.toString() ?? '',
      internalNote: json['internalNote']?.toString(),
      createdByUserName: json['createdByUserName']?.toString() ?? '',
    );
  }
}

class FundBalance {
  final String? bankAccountId;
  final String label;
  final String? bankShortName;
  final double balance;
  final bool isCash;

  FundBalance({
    this.bankAccountId,
    required this.label,
    this.bankShortName,
    required this.balance,
    this.isCash = false,
  });

  factory FundBalance.fromJson(Map<String, dynamic> json) {
    return FundBalance(
      bankAccountId: json['bankAccountId']?.toString(),
      label: json['label']?.toString() ?? '',
      bankShortName: json['bankShortName']?.toString(),
      balance: (json['balance'] ?? 0).toDouble(),
      isCash: json['isCash'] == true,
    );
  }
}
