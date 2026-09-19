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
import '../../widgets/hrm_page_chrome.dart';
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

  bool _vietQrEnabled = true;
  String? _vietQrBankId;
  List<BankAccount> _bankAccounts = const [];

  bool _tingeeEnabled = false;
  bool _platformTingeeConfigured = false;
  String _defaultProvider = 'VietQr';
  String _tingeeVaAccountNumber = '';
  List<Map<String, dynamic>> _tingeeLinkedAccounts = const [];
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
    final tingeeStatus = await ApiService().posTingeeStatus();
    _tingeeLinkedAccounts = _extractLinkedAccounts(tingeeStatus);
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
      final shop = _shopBankAccounts;
      if (_vietQrBankId == null || !shop.any((a) => a.id == _vietQrBankId)) {
        _vietQrBankId = shop
                .where((a) => a.isDefault)
                .map((a) => a.id)
                .firstOrNull ??
            (shop.isEmpty ? null : shop.first.id);
      }
      _loading = false;
    });
  }

  List<BankAccount> get _shopBankAccounts => _bankAccounts
      .where((a) => !PosVietQrHelper.isVirtualAccount(a.accountNumber))
      .toList();

  BankAccount? get _receiveAccount => PosVietQrHelper.resolveAccount(
        _shopBankAccounts.isEmpty ? _bankAccounts : _shopBankAccounts,
        preferredId: _vietQrBankId,
      );

  List<Map<String, dynamic>> _extractLinkedAccounts(
      Map<String, dynamic>? tingeeStatus) {
    if (tingeeStatus == null || tingeeStatus['data'] is! Map) return const [];
    final data = Map<String, dynamic>.from(tingeeStatus['data'] as Map);
    final raw = data['accounts'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _reloadTingeeStatus() async {
    final res = await ApiService().posTingeeStatus();
    if (!mounted) return;
    setState(() {
      _tingeeLinkedAccounts = _extractLinkedAccounts(res);
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
      preferredId: _vietQrBankId,
    );
  }

  String _tingeeVaNumberForSave({String? shopAccountNumber}) {
    final current = _tingeeVaAccountNumber.trim();
    if (PosVietQrHelper.isVirtualAccount(current)) return current;
    final shop = (shopAccountNumber ?? '').trim();
    if (shop.isNotEmpty) return shop;
    return _vaCtrl.text.trim();
  }

  Future<void> _saveReceiveBank() async {
    if (!_canEdit) return;
    final acc = _receiveAccount;
    setState(() => _savingVietQr = true);
    final current = await PosSellStoreSettings.load();
    await current
        .copyWith(
          vietQrBankAccountId: acc?.id ?? _vietQrBankId,
          showVietQrAtPayment: _vietQrEnabled,
        )
        .save();
    if (acc != null && acc.id.isNotEmpty) {
      await ApiService().setDefaultBankAccount(acc.id);
    }
    final vaNumber = _tingeeVaNumberForSave(shopAccountNumber: acc?.accountNumber);
    await ApiService().putPosPaymentGatewaySettings({
      'defaultTransferProvider': _defaultProvider,
      'tingeeEnabled': _tingeeEnabled,
      'tingeeVaAccountNumber': vaNumber,
      'tingeeMerchantId': _merchantCtrl.text.trim(),
      'tingeeShopId': _shopCtrl.text.trim(),
    });
    if (!mounted) return;
    if (acc != null) {
      if (!PosVietQrHelper.isVirtualAccount(_tingeeVaAccountNumber)) {
        _vaCtrl.text = acc.accountNumber;
        _tingeeVaAccountNumber = acc.accountNumber;
      }
      _vietQrBankId = acc.id;
    }
    setState(() => _savingVietQr = false);
    NotificationOverlayManager().showSuccess(
      title: tr('Đã lưu'),
      message: acc == null
          ? tr('Đã cập nhật cổng chuyển khoản')
          : tr(
              'QR và báo CK theo ${acc.bankShortName ?? acc.bankName} · ${acc.accountNumber}'),
    );
  }

  Future<void> _saveVietQr({bool? enabled}) async {
    if (!_canEdit) return;
    if (enabled != null) _vietQrEnabled = enabled;
    await _saveReceiveBank();
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
      'tingeeVaAccountNumber': _tingeeVaNumberForSave(
          shopAccountNumber: _receiveAccount?.accountNumber),
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

      final vaAccount = _receiveAccount ?? _resolveTingeeVaBankAccount();
      if (vaAccount == null) {
        NotificationOverlayManager().showError(
          title: tr('Thiếu tài khoản nhận tiền'),
          message: tr('Chọn tài khoản ngân hàng của cửa hàng trước khi mua token.'),
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
      appBar: HrmPageChrome.hideOuterChrome(context)
          ? null
          : AppBar(
              title: Text(tr('Cổng thanh toán')),
              backgroundColor: PosTheme.kiotBlue,
              foregroundColor: Colors.white,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: tr('Quay lại'),
                onPressed: () => Navigator.maybePop(context),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _noteCard(
                  icon: Icons.info_outline,
                  color: Colors.blue,
                  title: 'Cách hoạt động',
                  body:
                      '1. Tài khoản ngân hàng cửa hàng: tiền về STK này.\n'
                      '2. Tingee: khách quét QR số VA (bán hàng, QR bàn, đơn online). CK xong Sbox tự xác nhận đơn, báo đã thanh toán, tắt QR.\n'
                      '3. Nút VietQR thường (không Tingee) không tự báo có tiền — thu ngân bấm Thanh toán.',
                ),
                const SizedBox(height: 16),
                Text(tr('1. Tài khoản ngân hàng cửa hàng'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  tr('STK thật nhận tiền. Dùng khi bấm VietQR (không tự báo có tiền).'),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 8),
                _bankCard(),
                const SizedBox(height: 20),
                Text(tr('2. Tự báo có tiền (Tingee)'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  tr('Bật để màn bán hiện QR VA. Khách CK đúng số VA → đơn tự xong, QR tự tắt.'),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 8),
                _tingeeCard(),
              ],
            ),
    );
  }

  Widget _noteCard({
    required IconData icon,
    required MaterialColor color,
    required String title,
    required String body,
  }) {
    return Card(
      color: color.shade50,
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color.shade800, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(title),
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: color.shade900)),
                  const SizedBox(height: 4),
                  Text(tr(body),
                      style: TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: color.shade900)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bankCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: _vietQrBody(),
      ),
    );
  }

  Widget _tingeeCard() {
    final remain = (_credits?['remainingCount'] as num?)?.toInt() ?? 0;
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(tr('Bật tự báo CK'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                tr(_tingeeEnabled
                    ? 'QR bán hàng dùng số VA Tingee'
                    : 'Tắt — thu ngân tự bấm Thanh toán'),
                style: const TextStyle(fontSize: 12),
              ),
              value: _tingeeEnabled,
              onChanged: _canEdit && !_savingTingee
                  ? (v) => unawaited(_saveTingee(enabled: v))
                  : null,
            ),
            if (_tingeeEnabled) ...[
              _tingeeStatusBanner(),
              const SizedBox(height: 8),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.notifications_active_outlined),
                title: Text(tr('Lượt thông báo còn $remain')),
                subtitle: Text(
                  tr('Mỗi lần CK thành công trừ 1 lượt. Hết lượt thì vẫn nhận webhook nhưng không đọc thông báo.'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (_packages.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _packages.map((pkg) {
                    final name = (pkg['name'] ?? 'Gói').toString();
                    final credits = (pkg['creditCount'] as num?)?.toInt() ?? 0;
                    final price = pkg['price']?.toString() ?? '0';
                    return OutlinedButton(
                      onPressed: _creatingPurchase
                          ? null
                          : () => _createPurchase(pkg),
                      child: Text(tr('Mua $name · $credits lượt · $price đ')),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 8),
              Text(tr('Gắn / đổi ngân hàng với Tingee'),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                tr('Điền STK cửa hàng rồi bấm Gắn STK. Mở app ngân hàng duyệt. QR bán hàng sẽ dùng số VA Tingee trả về (vd. TGE…VCB), không phải STK thật.'),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 8),
              TingeeBankAttachPanel(
                hasMerchant: _merchantCtrl.text.trim().isNotEmpty ||
                    _platformTingeeConfigured,
                initialBankBin: _receiveAccount?.bankCode,
                initialAccountNumber: _receiveAccount?.accountNumber,
                initialAccountName: _receiveAccount?.accountName,
                linkedAccounts: _tingeeLinkedAccounts,
                onStatusChanged: () async {
                  await _reloadBanks();
                  await _reloadTingeeStatus();
                  final settings = await _api.getSettings();
                  if (!mounted) return;
                  setState(() {
                    _tingeeVaAccountNumber =
                        (settings?['tingeeVaAccountNumber'] ?? '')
                            .toString()
                            .trim();
                    _vaCtrl.text = _tingeeVaAccountNumber;
                  });
                },
                onVaApplied: (va) {
                  unawaited(_reloadBanks());
                  unawaited(_reloadTingeeStatus());
                },
              ),
              if (_vietQrEnabled)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Nút Chuyển khoản mặc định dùng Tingee')),
                    subtitle: Text(
                      tr('Tắt thì nút CK hiện VietQR STK cửa hàng (không tự hoàn tất đơn).'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: _defaultProvider.toLowerCase().contains('tingee'),
                    onChanged: _canEdit
                        ? (v) {
                            setState(() =>
                                _defaultProvider = v ? 'Tingee' : 'VietQr');
                            unawaited(_saveTingee());
                          }
                        : null,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tingeeStatusBanner() {
    if (!_platformTingeeConfigured) {
      return _noteCard(
        icon: Icons.warning_amber,
        color: Colors.orange,
        title: 'Sbox chưa cấu hình Tingee',
        body: 'Liên hệ SuperAdmin nhập Client ID / Secret trên cổng platform trước.',
      );
    }
    final link = () {
      for (final a in _tingeeLinkedAccounts) {
        if ((a['status'] ?? '').toString().toLowerCase() == 'active') {
          return a;
        }
      }
      return _tingeeLinkedAccounts.isEmpty ? null : _tingeeLinkedAccounts.first;
    }();
    final va = (link?['vaAccountNumber'] ?? _tingeeVaAccountNumber)
        .toString()
        .trim();
    final stk = (link?['accountNumber'] ?? _receiveAccount?.accountNumber ?? '')
        .toString()
        .trim();
    final bank = (link?['bankBin'] ?? _receiveAccount?.bankShortName ?? 'VCB')
        .toString();
    if (va.isEmpty) {
      return _noteCard(
        icon: Icons.link_off,
        color: Colors.orange,
        title: 'Chưa gắn ngân hàng',
        body: 'Gắn STK bên dưới rồi duyệt trên app ngân hàng. Sau đó QR bán hàng mới có số VA.',
      );
    }
    return _noteCard(
      icon: Icons.verified_outlined,
      color: Colors.green,
      title: 'Đã sẵn sàng nhận CK',
      body: 'QR khách quét: $va ($bank)\n'
          'Tiền về STK cửa hàng: ${stk.isEmpty ? '—' : stk}\n'
          'Nội dung CK phải giữ mã đơn trên QR để tự khớp.',
    );
  }

  Widget _vietQrBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_shopBankAccounts.isEmpty)
          Text(tr('Chưa có tài khoản. Thêm STK Vietcombank / ngân hàng của cửa hàng.'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
        else
          DropdownButtonFormField<String?>(
            value: _shopBankAccounts.any((a) => a.id == _vietQrBankId)
                ? _vietQrBankId
                : (_shopBankAccounts
                        .where((a) => a.isDefault)
                        .map((a) => a.id)
                        .firstOrNull ??
                    _shopBankAccounts.first.id),
            decoration: InputDecoration(
              labelText: tr('STK nhận tiền'),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: _shopBankAccounts
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
                ? (v) {
                    setState(() => _vietQrBankId = v);
                    unawaited(_saveReceiveBank());
                  }
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
              label: Text(tr('Thêm STK')),
            ),
            if (_shopBankAccounts.isNotEmpty)
              TextButton(
                onPressed: _canEdit
                    ? () async {
                        final shop = _shopBankAccounts;
                        final current = shop.firstWhere(
                          (a) => a.id ==
                              (_vietQrBankId ?? shop.first.id),
                          orElse: () => shop.first,
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
      ],
    );
  }
}
