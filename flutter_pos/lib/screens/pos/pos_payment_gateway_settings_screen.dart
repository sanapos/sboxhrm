import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../providers/permission_provider.dart';
import '../../utils/pos_payment_gateway_listener.dart';
import '../../utils/pos_vietqr_helper.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../models/cash_transaction.dart';
import '../../models/hrm.dart';
import '../../widgets/notification_overlay.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Cấu hình Tingee + chế độ CK mặc định (VietQR / Tingee).
class PosPaymentGatewaySettingsScreen extends StatefulWidget {
  const PosPaymentGatewaySettingsScreen({super.key});

  @override
  State<PosPaymentGatewaySettingsScreen> createState() =>
      _PosPaymentGatewaySettingsScreenState();
}

class _PosPaymentGatewaySettingsScreenState
    extends State<PosPaymentGatewaySettingsScreen> {
  final _api = PosPaymentGatewayApi(ApiService());
  final _clientIdCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();
  final _webhookSecretCtrl = TextEditingController();
  final _vaCtrl = TextEditingController();
  final _merchantCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _tingeeEnabled = false;
  bool _hasSecret = false;
  bool _hasWebhookSecret = false;
  bool _platformTingeeConfigured = false;
  String _defaultProvider = 'VietQr';
  Map<String, dynamic>? _credits;
  List<Map<String, dynamic>> _packages = const [];
  List<Map<String, dynamic>> _purchases = const [];
  List<Map<String, dynamic>> _ledgers = const [];
  bool _creatingPurchase = false;
  List<BankAccount> _bankAccounts = const [];
  String _tingeeVaAccountNumber = '';
  Timer? _creditPurchasePollTimer;
  int _creditPurchasePollTry = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _creditPurchasePollTimer?.cancel();
    _clientIdCtrl.dispose();
    _secretCtrl.dispose();
    _webhookSecretCtrl.dispose();
    _vaCtrl.dispose();
    _merchantCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final settings = await _api.getSettings();
    final credits = await _api.getCredits();
    final packagesRes = await ApiService().listPosNotificationCreditPackages();
    final purchasesRes = await ApiService().listPosNotificationCreditPurchases();
    final ledgersRes = await ApiService().listPosNotificationCreditLedgers();
    var banksRes = await ApiService().getPosBankAccounts();
    if (banksRes['isSuccess'] != true) {
      banksRes = await ApiService().getBankAccounts();
    }
    final accounts = <BankAccount>[];
    if (banksRes['isSuccess'] == true && banksRes['data'] is List) {
      for (final raw in banksRes['data'] as List) {
        final account = BankAccount.fromJson(raw as Map<String, dynamic>);
        if (account.isActive) accounts.add(account);
      }
    }
    if (!mounted) return;
    setState(() {
      _credits = credits;
      _packages = (packagesRes['isSuccess'] == true && packagesRes['data'] is List)
          ? (packagesRes['data'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : const [];
      _purchases = (purchasesRes['isSuccess'] == true && purchasesRes['data'] is List)
          ? (purchasesRes['data'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : const [];
      _ledgers = (ledgersRes['isSuccess'] == true && ledgersRes['data'] is List)
          ? (ledgersRes['data'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : const [];
      _tingeeEnabled = settings?['tingeeEnabled'] == true;
      _defaultProvider =
          (settings?['defaultTransferProvider'] ?? 'VietQr').toString();
      _tingeeVaAccountNumber = (settings?['tingeeVaAccountNumber'] ?? '')
          .toString()
          .trim();
      _bankAccounts = accounts;
      _clientIdCtrl.text = (settings?['tingeeClientId'] ?? '').toString();
      _vaCtrl.text = (settings?['tingeeVaAccountNumber'] ?? '').toString();
      _merchantCtrl.text = (settings?['tingeeMerchantId'] ?? '').toString();
      _hasSecret = settings?['hasTingeeSecretKey'] == true;
      _hasWebhookSecret = settings?['hasTingeeWebhookSecret'] == true;
      _platformTingeeConfigured = settings?['platformTingeeConfigured'] == true;
      _secretCtrl.clear();
      _webhookSecretCtrl.clear();
      _loading = false;
    });
  }

  BankAccount? _resolveTingeeVaBankAccount() {
    final va = _tingeeVaAccountNumber.trim();
    if (va.isEmpty) return null;
    for (final a in _bankAccounts) {
      if (a.accountNumber.trim() == va) return a;
    }
    return null;
  }

  void _pollCreditPurchasePaid(String externalPaymentRef) {
    _creditPurchasePollTimer?.cancel();
    _creditPurchasePollTry = 0;
    _creditPurchasePollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (timer) {
        _creditPurchasePollTry++;
        if (!mounted || _creditPurchasePollTry >= 12) {
          timer.cancel();
          return;
        }
        unawaited(_checkCreditPurchasePaid(externalPaymentRef, timer));
      },
    );
  }

  Future<void> _checkCreditPurchasePaid(
    String externalPaymentRef,
    Timer timer,
  ) async {
    final res = await ApiService().listPosNotificationCreditPurchases(
      limit: 20,
    );
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! List) return;
    for (final raw in res['data']) {
      if (raw is! Map) continue;
      final ref = (raw['externalPaymentRef'] ??
              raw['ExternalPaymentRef'] ??
              '')
          .toString();
      if (ref != externalPaymentRef) continue;
      final status = (raw['status'] ?? raw['Status'] ?? '').toString();
      if (status.toLowerCase() == 'paid') {
        timer.cancel();
        NotificationOverlayManager().show(
          title: tr('Đã cộng credit'),
          message: tr('Webhook Tingee đã xác nhận thanh toán credit.'),
          type: NotificationType.success,
        );
        unawaited(_load());
        return;
      }
    }
  }

  Future<void> _createPurchase(Map<String, dynamic> pkg) async {
    final id = (pkg['id'] ?? '').toString();
    if (id.isEmpty) return;
    setState(() => _creatingPurchase = true);
    final res = await ApiService().createPosNotificationCreditPurchase(
      packageId: id,
      note: 'Tự mua từ POS',
    );
    if (!mounted) return;
    setState(() => _creatingPurchase = false);
    if (res['isSuccess'] == true && res['data'] is Map) {
      final row = Map<String, dynamic>.from(res['data'] as Map);
      final ref = (row['externalPaymentRef'] ??
              row['ExternalPaymentRef'] ??
              '')
          .toString()
          .trim();
      final amountPaid = (row['amountPaid'] as num?)?.toDouble() ??
          double.tryParse((row['amountPaid'] ?? '').toString()) ??
          0.0;

      if (ref.isEmpty || amountPaid <= 0) {
        NotificationOverlayManager().show(
          title: tr('Không tạo được QR'),
          message: tr('Dữ liệu tham chiếu không hợp lệ. Vui lòng thử lại.'),
          type: NotificationType.error,
        );
        return;
      }

      final vaAccount = _resolveTingeeVaBankAccount();
      if (vaAccount == null) {
        NotificationOverlayManager().show(
          title: tr('Thiếu VA để tạo QR'),
          message: tr(
              'Không tìm thấy Tingee VA trong danh sách bank accounts. '
              'Vui lòng cấu hình VA trong Bank account (PosBankAccounts) hoặc tích hợp Tingee checkout tạo QR trực tiếp.'),
          type: NotificationType.error,
        );
        return;
      }

      final qrUrl = PosVietQrHelper.qrImageUrl(
        account: vaAccount,
        amount: amountPaid,
        description: PosVietQrHelper.transferNote(
          orderNo: ref,
          prefix: 'POS',
        ),
      );

      if (qrUrl == null || qrUrl.isEmpty) {
        NotificationOverlayManager().show(
          title: tr('Không tạo được QR'),
          message: tr('Không tạo được QR từ VA hiện tại.'),
          type: NotificationType.error,
        );
        return;
      }

      NotificationOverlayManager().show(
        title: tr('Đã tạo đơn mua credit'),
        message: tr('Vui lòng quét mã QR để thanh toán. Tham chiếu: $ref'),
        type: NotificationType.success,
      );

      _pollCreditPurchasePaid(ref);
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return AlertDialog(
            title: Text(tr('Thanh toán credit')),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr('Tham chiếu: $ref'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  CachedNetworkImage(
                    imageUrl: qrUrl,
                    width: 220,
                    height: 220,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const SizedBox(
                      width: 220,
                      height: 220,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (_, __, ___) => const Icon(Icons.qr_code_2,
                        size: 80, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  Text(tr('Số tiền: ${amountPaid.toStringAsFixed(0)} đ')),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(tr('Đã thanh toán xong')),
              ),
            ],
          );
        },
      );
      unawaited(_load());
      return;
    }
    NotificationOverlayManager().show(
      title: tr('Không tạo được đơn'),
      message: (res['message'] ?? res['Message'] ?? 'Lỗi tạo đơn').toString(),
      type: NotificationType.error,
    );
  }

  Future<void> _save() async {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    if (!perm.canEditPosSetup()) {
      NotificationOverlayManager().show(
        title: tr('Không có quyền sửa'),
        message: tr('Chỉ quản lý được lưu cổng thanh toán.'),
        type: NotificationType.error,
      );
      return;
    }
    setState(() => _saving = true);
    final body = <String, dynamic>{
      'defaultTransferProvider': _defaultProvider,
      'tingeeEnabled': _tingeeEnabled,
      'tingeeVaAccountNumber': _vaCtrl.text.trim(),
      'tingeeMerchantId': _merchantCtrl.text.trim(),
    };
    final res = await ApiService().putPosPaymentGatewaySettings(body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().show(
        title: tr('Đã lưu'),
        message: tr('Cấu hình cổng thanh toán đã được cập nhật'),
        type: NotificationType.success,
      );
      unawaited(_load());
    } else {
      NotificationOverlayManager().show(
        title: tr('Lỗi'),
        message: (res['message'] ?? res['Message'] ?? 'Không lưu được')
            .toString(),
        type: NotificationType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final remain = (_credits?['remainingCount'] as num?)?.toInt() ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Cổng thanh toán CK')),
        backgroundColor: PosTheme.kiotBlue,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.notifications_active_outlined),
                    title: Text(tr('Lượt thông báo CK')),
                    subtitle: Text(tr('Mỗi webhook Tingee thành công trừ 1 lượt')),
                    trailing: Chip(
                      label: Text(tr('Còn $remain')),
                      backgroundColor: remain <= 10
                          ? Colors.orange.shade100
                          : Colors.green.shade100,
                    ),
                  ),
                ),
                if (_packages.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(tr('Mua thêm credit'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  ..._packages.map((pkg) {
                    final name = (pkg['name'] ?? 'Gói credit').toString();
                    final credits = (pkg['creditCount'] as num?)?.toInt() ?? 0;
                    final price = pkg['price']?.toString() ?? '0';
                    final desc = (pkg['description'] ?? '').toString();
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.shopping_cart_checkout_outlined),
                        title: Text(tr(name)),
                        subtitle: Text(tr([
                          '$credits lượt',
                          '$price đ',
                          if (desc.isNotEmpty) desc,
                        ].join(' · '))),
                        trailing: FilledButton(
                          onPressed: _creatingPurchase ? null : () => _createPurchase(pkg),
                          child: Text(tr('Tạo đơn')),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  Text(
                    tr('Sau khi tạo đơn, thanh toán QR theo mã tham chiếu của đơn. Webhook Tingee thành công sẽ tự cộng credit.'),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
                if (_purchases.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(tr('Lịch sử mua gần đây'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  ..._purchases.take(5).map((row) {
                    final status = (row['status'] ?? 'Pending').toString();
                    final isPaid = status.toLowerCase() == 'paid';
                    final ref = (row['externalPaymentRef'] ?? '').toString();
                    final title = (row['packageName'] ?? 'Gói credit').toString();
                    final subtitle = '${row['creditCount'] ?? 0} lượt · ${row['amountPaid'] ?? 0} đ · $ref';
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          isPaid ? Icons.check_circle : Icons.hourglass_top,
                          color: isPaid ? Colors.green : Colors.orange,
                        ),
                        title: Text(tr(title)),
                        subtitle: Text(tr(subtitle)),
                        trailing: Text(
                          tr(status),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: isPaid ? Colors.green : Colors.orange.shade800,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
                if (_ledgers.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(tr('Nhật ký credit (mua/trừ)'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  ..._ledgers.take(10).map((row) {
                    final delta = (row['delta'] as num?)?.toInt() ??
                        int.tryParse((row['Delta'] ?? '').toString()) ??
                        0;
                    final balanceAfter = (row['balanceAfter'] as num?)?.toInt() ??
                        int.tryParse((row['BalanceAfter'] ?? '').toString()) ??
                        0;
                    final source = (row['source'] ?? row['Source'] ?? '').toString();
                    final note = (row['note'] ?? row['Note'] ?? '').toString();
                    final isGrant = delta > 0;
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          isGrant ? Icons.add_circle : Icons.remove_circle_outline,
                          color: isGrant ? Colors.green : Colors.orange,
                        ),
                        title: Text(
                          source.isEmpty ? tr('Credit') : source,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${delta > 0 ? '+' : ''}$delta · '
                          'saldo: $balanceAfter'
                          '${note.isNotEmpty ? ' · $note' : ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 12),
                Text(tr('Ưu tiên hình thức chuyển khoản'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'VietQr',
                      label: Text(tr('VietQR')),
                      icon: const Icon(Icons.qr_code_2),
                    ),
                    ButtonSegment(
                      value: 'Tingee',
                      label: Text(tr('Tingee')),
                      icon: const Icon(Icons.account_balance),
                    ),
                  ],
                  selected: {_defaultProvider},
                  onSelectionChanged: (s) =>
                      setState(() => _defaultProvider = s.first),
                ),
                const SizedBox(height: 8),
                Text(
                  tr(
                    'Khi bấm «Chuyển khoản» trên POS sẽ ưu tiên loại đã chọn. '
                    'VietQR: thu ngân xác nhận tay. '
                    'Tingee: webhook tự xác nhận + loa + màn phụ (cần VA + TK nhận tiền trên Tingee).',
                  ),
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  title: Text(tr('Bật Tingee')),
                  subtitle: Text(tr('Hiện «Tingee QR» ở bước thanh toán')),
                  value: _tingeeEnabled,
                  onChanged: (v) => setState(() => _tingeeEnabled = v),
                ),
                const Divider(),
                if (!_platformTingeeConfigured)
                  Card(
                    color: Colors.orange.shade50,
                    child: ListTile(
                      leading: Icon(Icons.warning_amber, color: Colors.orange.shade800),
                      title: Text(tr('Sbox chưa cấu hình Tingee platform')),
                      subtitle: Text(tr(
                          'Liên hệ SuperAdmin bật credentials master trước khi dùng Tingee QR.')),
                    ),
                  )
                else
                  Card(
                    color: Colors.green.shade50,
                    child: ListTile(
                      leading: Icon(Icons.verified_outlined, color: Colors.green.shade800),
                      title: Text(tr('Tingee qua Sbox')),
                      subtitle: Text(tr(
                          'Token master do SuperAdmin quản lý. Cửa hàng chỉ cần số VA riêng.')),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _vaCtrl,
                  decoration: InputDecoration(
                    labelText: tr('Số VA Tingee (cửa hàng)'),
                    helperText: tr('Phải khớp tài khoản ngân hàng POS và VA trên Tingee'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _merchantCtrl,
                  decoration: InputDecoration(
                    labelText: tr('Merchant ID (tuỳ chọn)'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('Webhook Sbox: https://sboxhrm.com/api/webhooks/payment/tingee'),
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: (_saving ||
                          !context.watch<PermissionProvider>().canEditPosSetup())
                      ? null
                      : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(tr('Lưu cấu hình')),
                ),
              ],
            ),
    );
  }
}
