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

  /// Chuỗi VietQR chuẩn NAPAS (EMVCo) sinh tại máy — in bill không cần tải ảnh
  /// img.vietqr.io (mất mạng / mạng chậm là mất mã). Chỉ khi mã NH là BIN 6 số.
  static String? emvPayload({
    required String bankBin,
    required String accountNumber,
    double? amount,
    String? description,
  }) {
    final bin = bankBin.trim();
    final acc = accountNumber.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(bin) ||
        !RegExp(r'^[A-Za-z0-9]{1,19}$').hasMatch(acc)) {
      return null;
    }
    String f(String id, String v) =>
        '$id${v.length.toString().padLeft(2, '0')}$v';
    final amt = (amount ?? 0).round();
    var note = _asciiNote(description ?? '');
    if (note.length > 50) note = note.substring(0, 50).trim();
    final buf = StringBuffer()
      ..write(f('00', '01'))
      ..write(f('01', amt > 0 ? '12' : '11'))
      ..write(f(
          '38',
          f('00', 'A000000727') +
              f('01', f('00', bin) + f('01', acc)) +
              f('02', 'QRIBFTTA')))
      ..write(f('53', '704'));
    if (amt > 0) buf.write(f('54', '$amt'));
    buf.write(f('58', 'VN'));
    if (note.isNotEmpty) buf.write(f('62', f('08', note)));
    buf.write('6304');
    final body = buf.toString();
    return body + crc16(body).toRadixString(16).toUpperCase().padLeft(4, '0');
  }

  /// URL ảnh img.vietqr.io (do [BankAccount.generateVietQRUrl] tạo) → chuỗi VietQR tại máy.
  static String? emvPayloadFromImageUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host != 'img.vietqr.io' || uri.pathSegments.isEmpty) {
      return null;
    }
    var seg = uri.pathSegments.last;
    if (seg.toLowerCase().endsWith('.png')) seg = seg.substring(0, seg.length - 4);
    final parts = seg.split('-');
    if (parts.length < 3) return null;
    return emvPayload(
      bankBin: parts.first,
      accountNumber: parts.sublist(1, parts.length - 1).join('-'),
      amount: double.tryParse(uri.queryParameters['amount'] ?? ''),
      description: uri.queryParameters['addInfo'],
    );
  }

  /// CRC-16/CCITT-FALSE (đa thức 0x1021, khởi tạo 0xFFFF) — trường 63 của VietQR.
  static int crc16(String data) {
    var crc = 0xFFFF;
    for (final b in data.codeUnits) {
      crc ^= (b & 0xFF) << 8;
      for (var i = 0; i < 8; i++) {
        crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1);
        crc &= 0xFFFF;
      }
    }
    return crc;
  }

  static const _vnFrom =
      'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
  static const _vnTo =
      'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';

  /// Nội dung CK chỉ nhận chữ không dấu / số / khoảng trắng (app ngân hàng từ chối ký tự lạ).
  static String _asciiNote(String raw) {
    final out = StringBuffer();
    for (final ch in raw.split('')) {
      final lower = ch.toLowerCase();
      final i = _vnFrom.indexOf(lower);
      final c = i >= 0 ? _vnTo[i] : lower;
      final keep = RegExp(r'[a-z0-9 ]').hasMatch(c) ? c : ' ';
      out.write(ch == lower ? keep : keep.toUpperCase());
    }
    return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Số tiền QR hóa đơn đòi — dùng chung cho mã QR và dòng chữ in cạnh mã.
  static double qrAmountForOrder(PosSaleOrder order) {
    // Tổng phải trả gồm VAT + phụ thu + phí giao (order.total chỉ là tiền hàng);
    // đơn còn nợ → QR đòi đúng phần còn lại.
    final payable = order.total + order.vatAmount + order.surchargeAmount + order.deliveryFee;
    return order.balanceDue > 0.5
        ? order.balanceDue
        : (payable > 0 ? payable : order.paidAmount);
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
    return qrImageUrl(
      account: account,
      amount: qrAmountForOrder(order),
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
