/// Enum loại giao dịch thu chi
enum CashTransactionType {
  income(1, 'Thu'),
  expense(2, 'Chi');

  const CashTransactionType(this.value, this.label);
  final int value;
  final String label;

  static CashTransactionType fromValue(int value) {
    return CashTransactionType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => CashTransactionType.income,
    );
  }
}

/// Enum trạng thái giao dịch
enum CashTransactionStatus {
  pending(1, 'Chờ xử lý'),
  completed(2, 'Hoàn thành'),
  cancelled(3, 'Đã hủy'),
  waitingPayment(4, 'Chờ thanh toán');

  const CashTransactionStatus(this.value, this.label);
  final int value;
  final String label;

  static CashTransactionStatus fromValue(int value) {
    return CashTransactionStatus.values.firstWhere(
      (e) => e.value == value,
      orElse: () => CashTransactionStatus.pending,
    );
  }
}

/// Enum phương thức thanh toán
enum PaymentMethodType {
  cash(1, 'Tiền mặt', 'payments'),
  bankTransfer(2, 'Chuyển khoản', 'account_balance'),
  vietQR(3, 'VietQR', 'qr_code_2'),
  card(4, 'Thẻ', 'credit_card'),
  eWallet(5, 'Ví điện tử', 'account_balance_wallet'),
  other(99, 'Khác', 'more_horiz');

  const PaymentMethodType(this.value, this.label, this.icon);
  final int value;
  final String label;
  final String icon;

  static PaymentMethodType fromValue(int value) {
    return PaymentMethodType.values.firstWhere(
      (e) => e.value == value,
      orElse: () => PaymentMethodType.cash,
    );
  }
}

/// Model cho giao dịch thu chi
class CashTransaction {
  final String id;
  final String transactionCode;
  final CashTransactionType type;
  final String categoryId;
  final String categoryName;
  final String? categoryIcon;
  final String? categoryColor;
  final double amount;
  final DateTime transactionDate;
  final String description;
  final PaymentMethodType paymentMethod;
  final String? bankAccountId;
  final String? bankAccountName;
  final CashTransactionStatus status;
  final String? contactName;
  final String? contactPhone;
  final String? paymentReference;
  final String? receiptImageUrl;
  final String? vietQRUrl;
  final bool isPaid;
  final DateTime? paidDate;
  final String createdByUserId;
  final String createdByUserName;
  final String? internalNote;
  final String? tags;
  final DateTime? lastModified;

  CashTransaction({
    required this.id,
    required this.transactionCode,
    required this.type,
    required this.categoryId,
    required this.categoryName,
    this.categoryIcon,
    this.categoryColor,
    required this.amount,
    required this.transactionDate,
    required this.description,
    required this.paymentMethod,
    this.bankAccountId,
    this.bankAccountName,
    required this.status,
    this.contactName,
    this.contactPhone,
    this.paymentReference,
    this.receiptImageUrl,
    this.vietQRUrl,
    required this.isPaid,
    this.paidDate,
    required this.createdByUserId,
    required this.createdByUserName,
    this.internalNote,
    this.tags,
    this.lastModified,
  });

  factory CashTransaction.fromJson(Map<String, dynamic> json) {
    return CashTransaction(
      id: json['id'] ?? '',
      transactionCode: json['transactionCode'] ?? '',
      type: CashTransactionType.fromValue(json['type'] ?? 1),
      categoryId: json['categoryId'] ?? '',
      categoryName: json['categoryName'] ?? '',
      categoryIcon: json['categoryIcon'],
      categoryColor: json['categoryColor'],
      amount: (json['amount'] ?? 0).toDouble(),
      transactionDate: DateTime.parse(json['transactionDate'] ?? DateTime.now().toIso8601String()),
      description: json['description'] ?? '',
      paymentMethod: PaymentMethodType.fromValue(json['paymentMethod'] ?? 1),
      bankAccountId: json['bankAccountId'],
      bankAccountName: json['bankAccountName'],
      status: CashTransactionStatus.fromValue(json['status'] ?? 1),
      contactName: json['contactName'],
      contactPhone: json['contactPhone'],
      paymentReference: json['paymentReference'],
      receiptImageUrl: json['receiptImageUrl'],
      vietQRUrl: json['vietQRUrl'],
      isPaid: json['isPaid'] ?? false,
      paidDate: json['paidDate'] != null ? DateTime.parse(json['paidDate']) : null,
      createdByUserId: json['createdByUserId'] ?? '',
      createdByUserName: json['createdByUserName'] ?? '',
      internalNote: json['internalNote'],
      tags: json['tags'],
      lastModified: json['lastModified'] != null ? DateTime.parse(json['lastModified']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'transactionCode': transactionCode,
      'type': type.value,
      'categoryId': categoryId,
      'amount': amount,
      'transactionDate': transactionDate.toIso8601String(),
      'description': description,
      'paymentMethod': paymentMethod.value,
      'bankAccountId': bankAccountId,
      'contactName': contactName,
      'contactPhone': contactPhone,
      'paymentReference': paymentReference,
      'receiptImageUrl': receiptImageUrl,
      'isPaid': isPaid,
      'internalNote': internalNote,
      'tags': tags,
    };
  }
}

/// Model cho danh mục giao dịch
class TransactionCategory {
  final String id;
  final String name;
  final String? description;
  final CashTransactionType type;
  final String? icon;
  final String? color;
  final int sortOrder;
  final String? parentCategoryId;
  final String? parentCategoryName;
  final bool isSystem;
  final bool isActive;
  final int transactionCount;
  final List<TransactionCategory> subCategories;

  TransactionCategory({
    required this.id,
    required this.name,
    this.description,
    required this.type,
    this.icon,
    this.color,
    this.sortOrder = 0,
    this.parentCategoryId,
    this.parentCategoryName,
    this.isSystem = false,
    this.isActive = true,
    this.transactionCount = 0,
    this.subCategories = const [],
  });

  factory TransactionCategory.fromJson(Map<String, dynamic> json) {
    return TransactionCategory(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      type: CashTransactionType.fromValue(json['type'] ?? 1),
      icon: json['icon'],
      color: json['color'],
      sortOrder: json['sortOrder'] ?? 0,
      parentCategoryId: json['parentCategoryId'],
      parentCategoryName: json['parentCategoryName'],
      isSystem: json['isSystem'] ?? false,
      isActive: json['isActive'] ?? true,
      transactionCount: json['transactionCount'] ?? 0,
      subCategories: json['subCategories'] != null
          ? (json['subCategories'] as List).map((e) => TransactionCategory.fromJson(e)).toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'type': type.value,
      'icon': icon,
      'color': color,
      'sortOrder': sortOrder,
      'parentCategoryId': parentCategoryId,
    };
  }
}

/// Model cho tài khoản ngân hàng
class BankAccount {
  final String id;
  final String accountName;
  final String accountNumber;
  final String bankCode;
  final String bankName;
  final String? bankShortName;
  final String? branchName;
  final String? bankLogoUrl;
  final bool isDefault;
  final String? note;
  final String vietQRTemplate;
  final bool isActive;
  final int transactionCount;

  BankAccount({
    required this.id,
    required this.accountName,
    required this.accountNumber,
    required this.bankCode,
    required this.bankName,
    this.bankShortName,
    this.branchName,
    this.bankLogoUrl,
    this.isDefault = false,
    this.note,
    this.vietQRTemplate = 'compact2',
    this.isActive = true,
    this.transactionCount = 0,
  });

  factory BankAccount.fromJson(Map<String, dynamic> json) {
    return BankAccount(
      id: json['id'] ?? '',
      accountName: json['accountName'] ?? '',
      accountNumber: json['accountNumber'] ?? '',
      bankCode: json['bankCode'] ?? '',
      bankName: json['bankName'] ?? '',
      bankShortName: json['bankShortName'],
      branchName: json['branchName'],
      bankLogoUrl: json['bankLogoUrl'],
      isDefault: json['isDefault'] ?? false,
      note: json['note'],
      vietQRTemplate: json['vietQRTemplate'] ?? 'compact2',
      isActive: json['isActive'] ?? true,
      transactionCount: json['transactionCount'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accountName': accountName,
      'accountNumber': accountNumber,
      'bankCode': bankCode,
      'bankName': bankName,
      'bankShortName': bankShortName,
      'branchName': branchName,
      'bankLogoUrl': bankLogoUrl,
      'isDefault': isDefault,
      'note': note,
      'vietQRTemplate': vietQRTemplate,
    };
  }

  /// Tạo VietQR URL
  String generateVietQRUrl({double? amount, String? description}) {
    var url = 'https://img.vietqr.io/image/$bankCode-$accountNumber-$vietQRTemplate.png';
    final params = <String>[];
    if (amount != null && amount > 0) {
      params.add('amount=${amount.toInt()}');
    }
    if (description != null && description.isNotEmpty) {
      params.add('addInfo=${Uri.encodeComponent(description)}');
    }
    if (params.isNotEmpty) {
      url += '?${params.join('&')}';
    }
    return url;
  }
}

/// Model cho danh sách ngân hàng VietQR
class VietQRBank {
  final String code;
  final String bin;
  final String name;
  final String shortName;
  final String logoUrl;

  VietQRBank({
    required this.code,
    required this.bin,
    required this.name,
    required this.shortName,
    required this.logoUrl,
  });

  factory VietQRBank.fromJson(Map<String, dynamic> json) {
    return VietQRBank(
      code: json['code'] ?? '',
      bin: json['bin'] ?? json['bIN'] ?? '',
      name: json['name'] ?? '',
      shortName: json['shortName'] ?? '',
      logoUrl: json['logoUrl'] ?? '',
    );
  }
}

/// Model cho tổng hợp thu chi
class CashTransactionSummary {
  final double totalIncome;
  final double totalExpense;
  final double balance;
  final int totalTransactions;
  final int incomeTransactions;
  final int expenseTransactions;
  final int pendingTransactions;
  final DateTime? fromDate;
  final DateTime? toDate;
  final List<CategorySummary> incomeByCategory;
  final List<CategorySummary> expenseByCategory;
  final List<DailySummary> dailySummary;

  CashTransactionSummary({
    required this.totalIncome,
    required this.totalExpense,
    required this.balance,
    required this.totalTransactions,
    required this.incomeTransactions,
    required this.expenseTransactions,
    required this.pendingTransactions,
    this.fromDate,
    this.toDate,
    this.incomeByCategory = const [],
    this.expenseByCategory = const [],
    this.dailySummary = const [],
  });

  factory CashTransactionSummary.fromJson(Map<String, dynamic> json) {
    return CashTransactionSummary(
      totalIncome: (json['totalIncome'] ?? 0).toDouble(),
      totalExpense: (json['totalExpense'] ?? 0).toDouble(),
      balance: (json['balance'] ?? 0).toDouble(),
      totalTransactions: json['totalTransactions'] ?? 0,
      incomeTransactions: json['incomeTransactions'] ?? 0,
      expenseTransactions: json['expenseTransactions'] ?? 0,
      pendingTransactions: json['pendingTransactions'] ?? 0,
      fromDate: json['fromDate'] != null ? DateTime.parse(json['fromDate']) : null,
      toDate: json['toDate'] != null ? DateTime.parse(json['toDate']) : null,
      incomeByCategory: json['incomeByCategory'] != null
          ? (json['incomeByCategory'] as List).map((e) => CategorySummary.fromJson(e)).toList()
          : [],
      expenseByCategory: json['expenseByCategory'] != null
          ? (json['expenseByCategory'] as List).map((e) => CategorySummary.fromJson(e)).toList()
          : [],
      dailySummary: json['dailySummary'] != null
          ? (json['dailySummary'] as List).map((e) => DailySummary.fromJson(e)).toList()
          : [],
    );
  }
}

class CategorySummary {
  final String categoryId;
  final String categoryName;
  final String? icon;
  final String? color;
  final double amount;
  final int count;
  final double percentage;

  CategorySummary({
    required this.categoryId,
    required this.categoryName,
    this.icon,
    this.color,
    required this.amount,
    required this.count,
    required this.percentage,
  });

  factory CategorySummary.fromJson(Map<String, dynamic> json) {
    return CategorySummary(
      categoryId: json['categoryId'] ?? '',
      categoryName: json['categoryName'] ?? '',
      icon: json['icon'],
      color: json['color'],
      amount: (json['amount'] ?? 0).toDouble(),
      count: json['count'] ?? 0,
      percentage: (json['percentage'] ?? 0).toDouble(),
    );
  }
}

class DailySummary {
  final DateTime date;
  final double income;
  final double expense;
  final double balance;

  DailySummary({
    required this.date,
    required this.income,
    required this.expense,
    required this.balance,
  });

  factory DailySummary.fromJson(Map<String, dynamic> json) {
    return DailySummary(
      date: DateTime.parse(json['date']),
      income: (json['income'] ?? 0).toDouble(),
      expense: (json['expense'] ?? 0).toDouble(),
      balance: (json['balance'] ?? 0).toDouble(),
    );
  }
}

/// VietQR Response DTO
class VietQRResponse {
  final String qrUrl;
  final String qrDataUrl;
  final String bankName;
  final String bankLogo;
  final String accountNumber;
  final String accountName;
  final double? amount;
  final String? description;

  VietQRResponse({
    required this.qrUrl,
    required this.qrDataUrl,
    required this.bankName,
    required this.bankLogo,
    required this.accountNumber,
    required this.accountName,
    this.amount,
    this.description,
  });

  factory VietQRResponse.fromJson(Map<String, dynamic> json) {
    return VietQRResponse(
      qrUrl: json['qrUrl'] ?? json['qRUrl'] ?? '',
      qrDataUrl: json['qrDataUrl'] ?? json['qRDataUrl'] ?? '',
      bankName: json['bankName'] ?? '',
      bankLogo: json['bankLogo'] ?? '',
      accountNumber: json['accountNumber'] ?? '',
      accountName: json['accountName'] ?? '',
      amount: json['amount']?.toDouble(),
      description: json['description'],
    );
  }
}
