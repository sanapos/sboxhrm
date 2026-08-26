import '../models/cash_transaction.dart';
import '../models/pos_sale_order.dart';
import '../services/api_service.dart';
import 'pos_sell_print_settings.dart';
import 'pos_sell_store_settings.dart';

/// Tiện ích tạo VietQR cho màn bán hàng POS.
class PosVietQrHelper {
  /// QR Tingee: VA chữ (vd. `96499085BOX`) là TK thu hộ BIDV — quét VietQR thường
  /// báo lỗi 025 «không có hóa đơn». Dùng STK số (settlement) để sinh QR.
  static BankAccount? resolveTingeeQrAccount(
    List<BankAccount> accounts, {
    required String vaAccountNumber,
  }) {
    final va = vaAccountNumber.trim();
    if (va.isEmpty || accounts.isEmpty) return null;
    BankAccount? exact;
    BankAccount? bidvDigits;
    final vaIsDigits = RegExp(r'^[0-9]+$').hasMatch(va);
    for (final a in accounts) {
      final n = a.accountNumber.trim();
      if (n == va) exact = a;
      final digits = RegExp(r'^[0-9]{6,}$').hasMatch(n);
      final blob =
          '${a.bankCode} ${a.bankShortName ?? ''} ${a.bankName}'.toUpperCase();
      final bidv = a.bankCode.trim() == '970418' || blob.contains('BIDV');
      if (digits && bidv) bidvDigits ??= a;
    }
    if (vaIsDigits) return exact ?? bidvDigits;
    return bidvDigits ?? exact;
  }

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
    final code = account.bankCode.trim();
    final number = account.accountNumber.trim();
    if (code.isEmpty || number.isEmpty) return null;
    return account.generateVietQRUrl(
      amount: amount,
      description: description,
    );
  }

  /// URL VietQR theo tổng đơn — dùng khi in hóa đơn (cờ «In mã VietQR»).
  static String? qrImageUrlForOrder(
    PosSaleOrder order, {
    required List<BankAccount> accounts,
    String? preferredAccountId,
  }) {
    if (accounts.isEmpty) return null;
    final account = resolveAccount(
      accounts,
      preferredId: preferredAccountId,
    );
    if (account == null) return null;
    final amount = order.total > 0 ? order.total : order.paidAmount;
    return qrImageUrl(
      account: account,
      amount: amount,
      description: transferNote(orderNo: order.orderNo, prefix: 'POS'),
    );
  }

  /// Tải TKNH + prefs in → URL VietQR (null nếu tắt / thiếu TK).
  static Future<String?> resolvePrintImageUrlForOrder(
    PosSaleOrder order, {
    bool? printEnabled,
    String? preferredAccountId,
  }) async {
    final enabled =
        printEnabled ?? (await PosSellPrintSettings.load()).printVietQrOnReceipt;
    if (!enabled) return null;

    final preferred = preferredAccountId ??
        (await PosSellStoreSettings.load()).vietQrBankAccountId;

    final api = ApiService();
    var res = await api.getPosBankAccounts();
    if (res['isSuccess'] != true || res['data'] is! List) {
      res = await api.getBankAccounts();
    }
    if (res['isSuccess'] != true || res['data'] is! List) return null;

    final accounts = <BankAccount>[];
    for (final raw in res['data'] as List) {
      if (raw is! Map) continue;
      try {
        accounts.add(BankAccount.fromJson(Map<String, dynamic>.from(raw)));
      } catch (_) {}
    }
    return qrImageUrlForOrder(
      order,
      accounts: accounts,
      preferredAccountId: preferred,
    );
  }
}
