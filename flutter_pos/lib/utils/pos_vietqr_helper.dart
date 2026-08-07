import '../models/cash_transaction.dart';

/// Tiện ích tạo VietQR cho màn bán hàng POS.
class PosVietQrHelper {
  static BankAccount? resolveAccount(
    List<BankAccount> accounts, {
    String? preferredId,
  }) {
    if (accounts.isEmpty) return null;
    if (preferredId != null && preferredId.isNotEmpty) {
      for (final a in accounts) {
        if (a.id == preferredId) return a;
      }
    }
    for (final a in accounts) {
      if (a.isDefault) return a;
    }
    return accounts.first;
  }

  static String transferNote({String? orderNo, String? prefix}) {
    final parts = <String>[];
    if (prefix != null && prefix.trim().isNotEmpty) parts.add(prefix.trim());
    if (orderNo != null && orderNo.trim().isNotEmpty) parts.add(orderNo.trim());
    return parts.isEmpty ? 'Thanh toan POS' : parts.join(' ');
  }

  static String? qrImageUrl({
    required BankAccount account,
    required double amount,
    String? description,
  }) {
    if (amount <= 0) return null;
    return account.generateVietQRUrl(
      amount: amount,
      description: description,
    );
  }
}
