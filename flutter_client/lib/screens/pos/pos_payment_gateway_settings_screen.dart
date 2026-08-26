import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/cash_transaction.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../utils/pos_payment_gateway_listener.dart';
import '../../utils/pos_sell_store_settings.dart';
import '../../utils/pos_vietqr_helper.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_bank_account_form_dialog.dart';
import '../../widgets/pos/pos_theme.dart';
import '../../widgets/pos/tingee_bank_attach_panel.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Hub cổng CK: VietQR (tài khoản NH) và Tingee (token + VA).
class PosPaymentGatewaySettingsScreen extends StatefulWidget {
  const PosPaymentGatewaySettingsScreen({super.key});

  @override
  State<PosPaymentGatewaySettingsScreen> createState() =>
      _PosPaymentGatewaySettingsScreenState();
}

class _PosPaymentGatewaySettingsScreenState
    extends State<PosPaymentGatewaySettingsScreen> {
  final _api = PosPaymentGatewayApi(ApiService());
  final _vaCtrl = TextEditingController();
  final _merchantCtrl = TextEditingController();
  final _shopCtrl = TextEditingController();

  bool _loading = true;
  bool _savingTingee = false;
  bool _savingVietQr = false;
  String? _expanded; // 'vietqr' | 'tingee'

  bool _vietQrEnabled = true;
  String? _vietQrBankId;
  List<BankAccount> _bankAccounts = const [];

  bool _tingeeEnabled = false;
  bool _platformTingeeConfigured = false;
  String _defaultProvider = 'VietQr';
  String _tingeeVaAccountNumber = '';
  Map<String, dynamic>? _credits;
  List<Map<String, dynamic>> _packages = const [];
  List<Map<String, dynamic>> _purchases = const [];
  List<Map<String, dynamic>> _ledgers = const [];
  bool _creatingPurchase = false;
  Timer? _creditPurchasePollTimer;
  int _creditPurchasePollTry = 0;

  bool get _canEdit =>
      Provider.of<PermissionProvider>(context, listen: false).canEditPosSetup();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _creditPurchasePollTimer?.cancel();
    _vaCtrl.dispose();
    _merchantCtrl.dispose();
    _shopCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final settings = await _api.getSettings();
    final store = await PosSellStoreSettings.load();
    final credits = await _api.getCredits();
    final packagesRes = await ApiService().listPosNotificationCreditPackages();
    final purchasesRes =
        await ApiService().listPosNotificationCreditPurchases();
    final ledgersRes = await ApiService().listPosNotificationCreditLedgers();
    await _reloadBanks(applyState: false);
    if (!mounted) return;
    setState(() {
      _credits = credits;
      _packages =
          (packagesRes['isSuccess'] == true && packagesRes['data'] is List)
              ? (packagesRes['data'] as List)
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
              : const [];
      _purchases =
          (purchasesRes['isSuccess'] == true && purchasesRes['data'] is List)
              ? (purchasesRes['data'] as List)
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
              : const [];
      _ledgers =
          (ledgersRes['isSuccess'] == true && ledgersRes['data'] is List)
              ? (ledgersRes['data'] as List)
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
              : const [];
      _vietQrEnabled = store.showVietQrAtPayment;
      _vietQrBankId = store.vietQrBankAccountId;
      _tingeeEnabled = settings?['tingeeEnabled'] == true;
      _defaultProvider =
          (settings?['defaultTransferProvider'] ?? 'VietQr').toString();
      _tingeeVaAccountNumber =
          (settings?['tingeeVaAccountNumber'] ?? '').toString().trim();
      _vaCtrl.text = (settings?['tingeeVaAccountNumber'] ?? '').toString();
      _merchantCtrl.text = (settings?['tingeeMerchantId'] ?? '').toString();
      _shopCtrl.text = (settings?['tingeeShopId'] ?? '').toString();
      _platformTingeeConfigured =
          settings?['platformTingeeConfigured'] == true;
      _loading = false;
    });
  }

  Future<void> _reloadBanks({bool applyState = true}) async {
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
    if (applyState) {
      setState(() {
        _bankAccounts = accounts;
        if (_vietQrBankId != null &&
            !_bankAccounts.any((a) => a.id == _vietQrBankId)) {
          _vietQrBankId = null;
        }
      });
    } else {
      _bankAccounts = accounts;
    }
  }

  BankAccount? _resolveTingeeVaBankAccount() {
    return PosVietQrHelper.resolveTingeeQrAccount(
      _bankAccounts,
      vaAccountNumber: _tingeeVaAccountNumber.trim(),
    );
  }

  Future<void> _saveVietQr({bool? enabled}) async {
    if (!_canEdit) return;
    final on = enabled ?? _vietQrEnabled;
    setState(() {
      _vietQrEnabled = on;
      _savingVietQr = true;
    });
    final current = await PosSellStoreSettings.load();
    await current
        .copyWith(
          vietQrBankAccountId: _vietQrBankId,
          showVietQrAtPayment: on,
        )
        .save();
    if (!mounted) return;
    setState(() => _savingVietQr = false);
    NotificationOverlayManager().showSuccess(
      title: tr('Đã lưu'),
      message: tr('Đã cập nhật cổng VietQR'),
    );
  }

  Future<void> _saveTingee({bool? enabled}) async {
    if (!_canEdit) return;
    final on = enabled ?? _tingeeEnabled;
    setState(() {
      _tingeeEnabled = on;
      _savingTingee = true;
    });
    var provider = _defaultProvider;
    if (on && !_vietQrEnabled) provider = 'Tingee';
    if (!on && _vietQrEnabled) provider = 'VietQr';
    _defaultProvider = provider;
    final res = await ApiService().putPosPaymentGatewaySettings({
      'defaultTransferProvider': provider,
      'tingeeEnabled': on,
      'tingeeVaAccountNumber': _vaCtrl.text.trim(),
      'tingeeMerchantId': _merchantCtrl.text.trim(),
      'tingeeShopId': _shopCtrl.text.trim(),
    });
    if (!mounted) return;
    setState(() => _savingTingee = false);
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: tr('Đã lưu'),
        message: tr('Đã cập nhật cổng Tingee'),
      );
      unawaited(_load());
    } else {
      NotificationOverlayManager().showError(
        title: tr('Lỗi'),
        message: (res['message'] ?? res['Message'] ?? 'Không lưu được')
            .toString(),
      );
    }
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
      final ref =
          (raw['externalPaymentRef'] ?? raw['ExternalPaymentRef'] ?? '')
              .toString();
      if (ref != externalPaymentRef) continue;
      final status = (raw['status'] ?? raw['Status'] ?? '').toString();
      if (status.toLowerCase() == 'paid') {
        timer.cancel();
        NotificationOverlayManager().showSuccess(
          title: tr('Đã cộng token'),
          message: tr('Webhook Tingee đã xác nhận thanh toán token.'),
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
      final ref = (row['externalPaymentRef'] ?? row['ExternalPaymentRef'] ?? '')
          .toString()
          .trim();
      final amountPaid = (row['amountPaid'] as num?)?.toDouble() ??
          double.tryParse((row['amountPaid'] ?? '').toString()) ??
          0.0;

      if (ref.isEmpty || amountPaid <= 0) {
        NotificationOverlayManager().showError(
          title: tr('Không tạo được QR'),
          message: tr('Dữ liệu tham chiếu không hợp lệ. Vui lòng thử lại.'),
        );
        return;
      }

      final vaAccount = _resolveTingeeVaBankAccount();
      if (vaAccount == null) {
        NotificationOverlayManager().showError(
          title: tr('Thiếu VA để tạo QR'),
          message: tr(
              'Cần số VA Tingee khớp tài khoản ngân hàng trước khi mua token.'),
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
        NotificationOverlayManager().showError(
          title: tr('Không tạo được QR'),
          message: tr('Không tạo được QR từ VA hiện tại.'),
        );
        return;
      }

      _pollCreditPurchasePaid(ref);
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          return AlertDialog(
            title: Text(tr('Thanh toán token Tingee')),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr('Tham chiếu: $ref'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
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
                child: Text(tr('Đóng')),
              ),
            ],
          );
        },
      );
      unawaited(_load());
      return;
    }
    NotificationOverlayManager().showError(
      title: tr('Không tạo được đơn'),
      message: (res['message'] ?? res['Message'] ?? 'Lỗi tạo đơn').toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Cổng thanh toán')),
        backgroundColor: PosTheme.kiotBlue,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  tr('Bật cổng để hiện khi thanh toán. Mở thẻ để thiết lập.'),
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                _gatewayCard(
                  code: 'vietqr',
                  title: 'VietQR',
                  subtitle: _vietQrEnabled
                      ? (_bankAccounts.isEmpty
                          ? 'Bật · chưa có tài khoản ngân hàng'
                          : 'Bật · ${_bankAccounts.length} tài khoản')
                      : 'Tắt',
                  icon: Icons.qr_code_2,
                  enabled: _vietQrEnabled,
                  busy: _savingVietQr,
                  onToggle: (v) => unawaited(_saveVietQr(enabled: v)),
                  body: _vietQrBody(),
                ),
                const SizedBox(height: 10),
                _gatewayCard(
                  code: 'tingee',
                  title: 'Tingee',
                  subtitle: _tingeeSubtitle(),
                  icon: Icons.account_balance,
                  enabled: _tingeeEnabled,
                  busy: _savingTingee,
                  onToggle: (v) => unawaited(_saveTingee(enabled: v)),
                  body: _tingeeBody(),
                ),
                if (_vietQrEnabled && _tingeeEnabled) ...[
                  const SizedBox(height: 16),
                  Text(tr('Ưu tiên khi bấm Chuyển khoản'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'VietQr',
                        label: Text(tr('VietQR')),
                        icon: const Icon(Icons.qr_code_2, size: 18),
                      ),
                      ButtonSegment(
                        value: 'Tingee',
                        label: Text(tr('Tingee')),
                        icon: const Icon(Icons.account_balance, size: 18),
                      ),
                    ],
                    selected: {_defaultProvider},
                    onSelectionChanged: _canEdit
                        ? (s) {
                            setState(() => _defaultProvider = s.first);
                            unawaited(_saveTingee());
                          }
                        : null,
                  ),
                ],
              ],
            ),
    );
  }

  String _tingeeSubtitle() {
    final remain = (_credits?['remainingCount'] as num?)?.toInt() ?? 0;
    if (!_tingeeEnabled) return 'Tắt';
    return 'Bật · còn $remain token thông báo CK';
  }

  Widget _gatewayCard({
    required String code,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool enabled,
    required bool busy,
    required ValueChanged<bool> onToggle,
    required Widget body,
  }) {
    final expanded = _expanded == code;
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = expanded ? null : code),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Icon(icon, color: enabled ? PosTheme.kiotBlue : Colors.grey),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr(title),
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                        Text(tr(subtitle),
                            style: TextStyle(
                                fontSize: 12,
                                color: enabled
                                    ? Colors.green.shade700
                                    : Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: enabled,
                    onChanged: _canEdit && !busy ? onToggle : null,
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.grey.shade700,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: body,
            ),
        ],
      ),
    );
  }

  Widget _vietQrBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr('Tài khoản ngân hàng dùng tạo mã VietQR khi khách chuyển khoản.'),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 10),
        if (_bankAccounts.isEmpty)
          Text(tr('Chưa có tài khoản. Thêm tài khoản để tạo mã QR.'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
        else
          DropdownButtonFormField<String?>(
            value: _vietQrBankId ??
                _bankAccounts
                    .where((a) => a.isDefault)
                    .map((a) => a.id)
                    .firstOrNull ??
                _bankAccounts.first.id,
            decoration: InputDecoration(
              labelText: tr('Tài khoản nhận tiền'),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: _bankAccounts
                .map(
                  (a) => DropdownMenuItem(
                    value: a.id,
                    child: Text(
                      tr('${a.bankShortName ?? a.bankName} · ${a.accountNumber}'
                          '${a.isDefault ? ' (Mặc định)' : ''}'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _canEdit
                ? (v) => setState(() => _vietQrBankId = v)
                : null,
          ),
        Row(
          children: [
            TextButton.icon(
              onPressed: _canEdit
                  ? () async {
                      final ok = await showPosBankAccountFormDialog(context);
                      if (ok) await _reloadBanks();
                    }
                  : null,
              icon: const Icon(Icons.add, size: 18),
              label: Text(tr('Thêm tài khoản')),
            ),
            if (_bankAccounts.isNotEmpty)
              TextButton(
                onPressed: _canEdit
                    ? () async {
                        final current = _bankAccounts.firstWhere(
                          (a) => a.id ==
                              (_vietQrBankId ?? _bankAccounts.first.id),
                          orElse: () => _bankAccounts.first,
                        );
                        final ok = await showPosBankAccountFormDialog(
                          context,
                          account: current,
                        );
                        if (ok) await _reloadBanks();
                      }
                    : null,
                child: Text(tr('Sửa')),
              ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed:
                (_savingVietQr || !_canEdit) ? null : () => _saveVietQr(),
            child: Text(tr('Lưu VietQR')),
          ),
        ),
      ],
    );
  }

  Widget _tingeeBody() {
    final remain = (_credits?['remainingCount'] as num?)?.toInt() ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.token_outlined),
            title: Text(tr('Token thông báo CK')),
            subtitle: Text(tr('Mỗi webhook Tingee thành công trừ 1 token')),
            trailing: Chip(
              label: Text(tr('Còn $remain')),
              backgroundColor: remain <= 10
                  ? Colors.orange.shade100
                  : Colors.green.shade100,
            ),
          ),
        ),
        if (_packages.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(tr('Mua token'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ..._packages.map((pkg) {
            final name = (pkg['name'] ?? 'Gói token').toString();
            final credits = (pkg['creditCount'] as num?)?.toInt() ?? 0;
            final price = pkg['price']?.toString() ?? '0';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                title: Text(tr(name)),
                subtitle: Text(tr('$credits token · $price đ')),
                trailing: FilledButton(
                  onPressed:
                      _creatingPurchase ? null : () => _createPurchase(pkg),
                  child: Text(tr('Mua')),
                ),
              ),
            );
          }),
        ],
        if (_purchases.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(tr('Lịch sử mua'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          ..._purchases.take(4).map((row) {
            final status = (row['status'] ?? 'Pending').toString();
            final isPaid = status.toLowerCase() == 'paid';
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                isPaid ? Icons.check_circle : Icons.hourglass_top,
                color: isPaid ? Colors.green : Colors.orange,
                size: 20,
              ),
              title: Text(tr((row['packageName'] ?? 'Gói token').toString())),
              subtitle: Text(
                tr('${row['creditCount'] ?? 0} token · ${row['amountPaid'] ?? 0} đ'),
              ),
              trailing: Text(tr(status),
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isPaid ? Colors.green : Colors.orange.shade800)),
            );
          }),
        ],
        if (_ledgers.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(tr('Nhật ký token'),
              style: const TextStyle(fontWeight: FontWeight.w700)),
          ..._ledgers.take(5).map((row) {
            final delta = (row['delta'] as num?)?.toInt() ?? 0;
            final source = (row['source'] ?? row['Source'] ?? '').toString();
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                delta > 0 ? Icons.add_circle : Icons.remove_circle_outline,
                color: delta > 0 ? Colors.green : Colors.orange,
                size: 20,
              ),
              title: Text(source.isEmpty ? tr('Token') : source,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${delta > 0 ? '+' : ''}$delta'),
            );
          }),
        ],
        const Divider(height: 24),
        if (!_platformTingeeConfigured)
          Card(
            color: Colors.orange.shade50,
            child: ListTile(
              dense: true,
              leading:
                  Icon(Icons.warning_amber, color: Colors.orange.shade800),
              title: Text(tr('Sbox chưa cấu hình Tingee platform')),
              subtitle: Text(tr(
                  'Liên hệ SuperAdmin bật credentials master trước khi dùng.')),
            ),
          )
        else
          Card(
            color: Colors.green.shade50,
            child: ListTile(
              dense: true,
              leading:
                  Icon(Icons.verified_outlined, color: Colors.green.shade800),
              title: Text(tr('Tingee qua Sbox')),
              subtitle: Text(tr('Cửa hàng chỉ cần số VA riêng.')),
            ),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _vaCtrl,
          decoration: InputDecoration(
            labelText: tr('Số VA Tingee'),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _merchantCtrl,
          decoration: InputDecoration(
            labelText: tr('Merchant ID (tuỳ chọn)'),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _shopCtrl,
          decoration: InputDecoration(
            labelText: tr('Shop ID Tingee'),
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TingeeBankAttachPanel(
          hasMerchant: _merchantCtrl.text.trim().isNotEmpty,
          onVaApplied: (va) => setState(() => _vaCtrl.text = va),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed:
                (_savingTingee || !_canEdit) ? null : () => _saveTingee(),
            child: Text(tr('Lưu Tingee')),
          ),
        ),
      ],
    );
  }
}
