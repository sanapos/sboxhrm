import '../models/cash_transaction.dart';
import '../models/pos_sale_order.dart';
import '../services/api_service.dart';
import 'pos_sell_print_settings.dart';
import 'pos_sell_store_settings.dart';

/// Tiện ích tạo VietQR cho màn bán hàng POS.
class PosVietQrHelper {
  static bool isVirtualAccount(String? number) {
    final n = (number ?? '').trim();
    return n.isNotEmpty && RegExp(r'[A-Za-z]').hasMatch(n);
  }

  /// QR Tingee: ưu tiên số VA (TGE…) — đúng tài khoản Tingee nhận webhook.
  static BankAccount? resolveTingeeQrAccount(
    List<BankAccount> accounts, {
    required String vaAccountNumber,
    String? preferredId,
  }) {
    if (accounts.isEmpty) return null;
    final va = vaAccountNumber.trim();
    if (va.isNotEmpty) {
      for (final a in accounts) {
        if (a.accountNumber.trim().toLowerCase() == va.toLowerCase()) {
          return a;
        }
      }
      final template = resolveAccount(accounts, preferredId: preferredId);
      if (template != null) {
        return BankAccount(
          id: 'tingee-va:$va',
          accountName: template.accountName,
          accountNumber: va,
          bankCode: template.bankCode,
          bankName: template.bankName,
          bankShortName: template.bankShortName,
          branchName: template.branchName,
          bankLogoUrl: template.bankLogoUrl,
          isDefault: false,
          note: 'Tingee VA',
          vietQRTemplate: template.vietQRTemplate,
        );
      }
    }
    return resolveAccount(accounts, preferredId: preferredId);
  }

  /// Đưa VA vào list để panel VietQR resolve đúng (không rơi về STK mặc định).
  static List<BankAccount> withTingeeVaAccount(
    List<BankAccount> accounts, {
    required String vaAccountNumber,
    String? preferredId,
  }) {
    final acc = resolveTingeeQrAccount(
      accounts,
      vaAccountNumber: vaAccountNumber,
      preferredId: preferredId,
    );
    if (acc == null) return accounts;
    if (accounts.any((a) =>
        a.accountNumber.trim().toLowerCase() ==
        acc.accountNumber.trim().toLowerCase())) {
      return accounts;
    }
    return [acc, ...accounts];
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
