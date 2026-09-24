import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../utils/pos_commercial_profile_local.dart';
import '../../utils/pos_sell_store_settings.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_commercial_company_fields.dart';
import '../../widgets/pos/pos_sell_fee_defaults_fields.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Thiết lập cửa hàng / VAT / phụ phí — dùng trong Settings hub.
class PosStoreSettingsHubScreen extends StatefulWidget {
  const PosStoreSettingsHubScreen({super.key});

  @override
  State<PosStoreSettingsHubScreen> createState() =>
      _PosStoreSettingsHubScreenState();
}

class _PosStoreSettingsHubScreenState extends State<PosStoreSettingsHubScreen> {
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _companyAddressCtrl = TextEditingController();
  final _companyPhoneCtrl = TextEditingController();
  final _companyEmailCtrl = TextEditingController();
  final _bankNoCtrl = TextEditingController();
  final _bankNameCtrl = TextEditingController();
  final _bankHolderCtrl = TextEditingController();
  final _repCtrl = TextEditingController();
  final _titleCtrl = TextEditingController(text: 'Giám đốc');
  final _termsCtrl = TextEditingController();
  final _warrantyCtrl = TextEditingController();
  final _surchargeNameCtrl = TextEditingController();
  final _surchargeDefaultCtrl = TextEditingController();
  final _deliveryDefaultCtrl = TextEditingController();

  PosSellTaxMode _taxMode = PosSellTaxMode.includedInPrice;
  double _vatRate = 10;
  bool _enableSurcharge = false;
  bool _enableDeliveryFee = false;
  bool _surchargeIsPercent = false;
  bool _loading = true;
  bool _saving = false;
  String _stampB64 = '';
  Uint8List? _stampBytes;
  String _logoB64 = '';
  Uint8List? _logoBytes;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _companyCtrl.dispose();
    _taxCtrl.dispose();
    _companyAddressCtrl.dispose();
    _companyPhoneCtrl.dispose();
    _companyEmailCtrl.dispose();
    _bankNoCtrl.dispose();
    _bankNameCtrl.dispose();
    _bankHolderCtrl.dispose();
    _repCtrl.dispose();
    _titleCtrl.dispose();
    _termsCtrl.dispose();
    _warrantyCtrl.dispose();
    _surchargeNameCtrl.dispose();
    _surchargeDefaultCtrl.dispose();
    _deliveryDefaultCtrl.dispose();
    super.dispose();
  }

  Uint8List? _decodeB64(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    final comma = s.indexOf(',');
    if (s.startsWith('data:') && comma > 0) s = s.substring(comma + 1).trim();
    try {
      return base64Decode(s);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickImage({bool logo = false}) async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 640,
      maxHeight: 640,
      imageQuality: 92,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.length > 700 * 1024) {
      NotificationOverlayManager().showWarning(
        title: 'Ảnh quá lớn',
        message: tr('Ảnh cần dưới 700 KB.'),
      );
      return;
    }
    final b64 = base64Encode(bytes);
    setState(() {
      if (logo) {
        _logoBytes = bytes;
        _logoB64 = b64;
      } else {
        _stampBytes = bytes;
        _stampB64 = b64;
      }
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = await PosSellStoreSettings.load();
    final profileRes = await ApiService().getPosCommercialProfile();
    final local = await loadLocalCommercialProfile();
    if (!mounted) return;
    setState(() {
      _nameCtrl.text = s.storeName;
      _addressCtrl.text = s.address;
      _phoneCtrl.text = s.phone;
      _taxMode = s.taxMode;
      _vatRate = s.defaultVatRate;
      _enableSurcharge = s.enableSurcharge;
      _enableDeliveryFee = s.enableDeliveryFee;
      _surchargeIsPercent = s.surchargeIsPercent;
      _surchargeNameCtrl.text = s.surchargeLabel;
      _surchargeDefaultCtrl.text = s.surchargeDefault > 0
          ? PosSellStoreSettings.formatAmount(s.surchargeDefault)
          : '';
      _deliveryDefaultCtrl.text = s.deliveryFeeDefault > 0
          ? PosSellStoreSettings.formatAmount(s.deliveryFeeDefault)
          : '';
      if (profileRes['isSuccess'] == true && profileRes['data'] is Map) {
        final remote = Map<String, dynamic>.from(profileRes['data'] as Map);
        final m = mergeCommercialProfile(remote, local);
        String t(String a, String b) => (m[a] ?? m[b] ?? '').toString();
        _companyCtrl.text = t('companyName', 'CompanyName');
        _taxCtrl.text = t('taxCode', 'TaxCode');
        _companyAddressCtrl.text = t('address', 'Address');
        _companyPhoneCtrl.text = t('phone', 'Phone');
        _companyEmailCtrl.text = t('email', 'Email');
        _bankNoCtrl.text = t('bankAccountNumber', 'BankAccountNumber');
        _bankNameCtrl.text = t('bankName', 'BankName');
        _bankHolderCtrl.text = t('bankAccountHolder', 'BankAccountHolder');
        _repCtrl.text = t('legalRepresentative', 'LegalRepresentative');
        _titleCtrl.text = t('legalTitle', 'LegalTitle');
        if (_titleCtrl.text.trim().isEmpty) _titleCtrl.text = 'Giám đốc';
        _stampB64 = t('stampPngBase64', 'StampPngBase64').trim();
        _stampBytes = _decodeB64(_stampB64);
        _logoB64 = t('logoPngBase64', 'LogoPngBase64').trim();
        _logoBytes = _decodeB64(_logoB64);
        _termsCtrl.text = t('defaultTerms', 'DefaultTerms');
        _warrantyCtrl.text = t('warrantyPolicy', 'WarrantyPolicy');
      } else if (local.isNotEmpty) {
        String t(String a) => (local[a] ?? '').toString();
        _companyCtrl.text = t('companyName');
        _taxCtrl.text = t('taxCode');
        _companyAddressCtrl.text = t('address');
        _companyPhoneCtrl.text = t('phone');
        _companyEmailCtrl.text = t('email');
        _bankNoCtrl.text = t('bankAccountNumber');
        _bankNameCtrl.text = t('bankName');
        _bankHolderCtrl.text = t('bankAccountHolder');
        _repCtrl.text = t('legalRepresentative');
        _titleCtrl.text = t('legalTitle');
        if (_titleCtrl.text.trim().isEmpty) _titleCtrl.text = 'Giám đốc';
        _stampB64 = t('stampPngBase64');
        _stampBytes = _decodeB64(_stampB64);
        _logoB64 = t('logoPngBase64');
        _logoBytes = _decodeB64(_logoB64);
        _termsCtrl.text = t('defaultTerms');
        _warrantyCtrl.text = t('warrantyPolicy');
      }
      _loading = false;
    });
  }

  Future<void> _save() async {
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    if (!perm.canEditPosSetup()) {
      NotificationOverlayManager().showWarning(
        title: 'Không có quyền sửa',
        message: tr('Chỉ quản lý được lưu thiết lập cửa hàng.'),
      );
      return;
    }
    setState(() => _saving = true);
    final existing = await PosSellStoreSettings.load();
    final next = PosSellStoreSettings(
      storeName: _nameCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      taxMode: _taxMode,
      defaultVatRate: _vatRate,
      vietQrBankAccountId: existing.vietQrBankAccountId,
      showVietQrAtPayment: existing.showVietQrAtPayment,
      enableSurcharge: _enableSurcharge,
      enableDeliveryFee: _enableDeliveryFee,
      surchargeLabel: _surchargeNameCtrl.text.trim(),
      surchargeIsPercent: _surchargeIsPercent,
      surchargeDefault: PosSellStoreSettings.parseAmount(
        _surchargeDefaultCtrl.text,
      ),
      deliveryFeeDefault: PosSellStoreSettings.parseAmount(
        _deliveryDefaultCtrl.text,
      ),
    );
    await next.save();
    final profileBody = <String, dynamic>{
      'clientSavedAt': DateTime.now().toUtc().toIso8601String(),
      'companyName': _companyCtrl.text.trim(),
      'taxCode': _taxCtrl.text.trim(),
      'address': _companyAddressCtrl.text.trim(),
      'phone': _companyPhoneCtrl.text.trim(),
      'email': _companyEmailCtrl.text.trim(),
      'bankAccountNumber': _bankNoCtrl.text.trim(),
      'bankName': _bankNameCtrl.text.trim(),
      'bankAccountHolder': _bankHolderCtrl.text.trim(),
      'legalRepresentative': _repCtrl.text.trim(),
      'legalTitle': _titleCtrl.text.trim(),
      'stampPngBase64': _stampB64,
      'logoPngBase64': _logoB64,
      'defaultTerms': _termsCtrl.text.trim(),
      'warrantyPolicy': _warrantyCtrl.text.trim(),
    };
    await saveLocalCommercialProfile(profileBody);
    final profileRes = await ApiService().updatePosCommercialProfile(profileBody);
    if (!mounted) return;
    setState(() => _saving = false);
    if (profileRes['isSuccess'] == true && profileRes['data'] is Map) {
      final saved = Map<String, dynamic>.from(profileRes['data'] as Map);
      saved['clientSavedAt'] =
          saved['updatedAt'] ?? saved['UpdatedAt'] ?? profileBody['clientSavedAt'];
      await saveLocalCommercialProfile(saved);
    }
    if (profileRes['isSuccess'] != true) {
      NotificationOverlayManager().showWarning(
        title: 'Đã lưu cửa hàng',
        message: profileRes['message']?.toString() ??
            tr('Thông tin công ty chưa lưu được — kiểm tra quyền.'),
      );
      return;
    }
    NotificationOverlayManager().showSuccess(
      title: 'Đã lưu',
      message: tr('Thiết lập cửa hàng và thông tin công ty đã cập nhật'),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      const spinner = Center(child: CircularProgressIndicator());
      if (HrmPageChrome.hideOuterChrome(context)) return spinner;
      return Scaffold(
        backgroundColor: HrmPageChrome.background,
        appBar: HrmPageChrome.appBar(
          context: context,
          title: 'Thiết lập cửa hàng',
        ),
        body: spinner,
      );
    }
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      appBar: HrmPageChrome.appBar(
        context: context,
        title: 'Thiết lập cửa hàng',
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: InputDecoration(
              labelText: tr('Tên cửa hàng'),
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressCtrl,
            decoration: InputDecoration(
              labelText: tr('Địa chỉ'),
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: tr('Số điện thoại'),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr('QR thanh toán tại quầy nằm ở Cổng thanh toán. TK in trên báo giá / hợp đồng điền ở khối công ty bên dưới.'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const Divider(height: 28),
          PosCommercialCompanyFields(
            company: _companyCtrl,
            tax: _taxCtrl,
            address: _companyAddressCtrl,
            phone: _companyPhoneCtrl,
            email: _companyEmailCtrl,
            bankNo: _bankNoCtrl,
            bankName: _bankNameCtrl,
            bankHolder: _bankHolderCtrl,
            rep: _repCtrl,
            title: _titleCtrl,
            enabled:
                context.watch<PermissionProvider>().canEditPosSetup(),
          ),
          const SizedBox(height: 14),
          Text(
            tr('Logo công ty'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            tr('Ảnh này in ở góc đầu báo giá. JPG hoặc PNG, dưới 700 KB.'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade400),
                ),
                child: _logoBytes == null
                    ? Icon(Icons.image_outlined,
                        color: Colors.grey.shade400, size: 36)
                    : Padding(
                        padding: const EdgeInsets.all(6),
                        child: Image.memory(_logoBytes!, fit: BoxFit.contain),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: context
                              .watch<PermissionProvider>()
                              .canEditPosSetup()
                          ? () => _pickImage(logo: true)
                          : null,
                      icon: const Icon(Icons.upload_file),
                      label: Text(tr('Tải logo')),
                    ),
                    if (_logoBytes != null)
                      TextButton(
                        onPressed: context
                                .watch<PermissionProvider>()
                                .canEditPosSetup()
                            ? () => setState(() {
                                  _logoBytes = null;
                                  _logoB64 = '';
                                })
                            : null,
                        child: Text(tr('Gỡ logo')),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            tr('Con dấu công ty'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            tr('Ảnh PNG nền trong suốt. Khi in báo giá, dấu tự treo lên chữ ký đại diện công ty.'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade400),
                ),
                child: _stampBytes == null
                    ? Icon(Icons.verified_outlined,
                        color: Colors.grey.shade400, size: 36)
                    : Padding(
                        padding: const EdgeInsets.all(6),
                        child: Image.memory(_stampBytes!, fit: BoxFit.contain),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      onPressed: context
                              .watch<PermissionProvider>()
                              .canEditPosSetup()
                          ? () => _pickImage()
                          : null,
                      icon: const Icon(Icons.upload_file),
                      label: Text(tr('Chọn ảnh con dấu')),
                    ),
                    if (_stampBytes != null)
                      TextButton(
                        onPressed: context
                                .watch<PermissionProvider>()
                                .canEditPosSetup()
                            ? () => setState(() {
                                  _stampBytes = null;
                                  _stampB64 = '';
                                })
                            : null,
                        child: Text(tr('Gỡ con dấu')),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(tr('Điều khoản báo giá'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            tr('In khi báo giá không có điều khoản riêng. Ghi chú trên phiếu vẫn là ghi chú của báo giá đó.'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _termsCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Hiệu lực, thanh toán, giao hàng…',
            ),
          ),
          const SizedBox(height: 14),
          Text(tr('Chính sách bảo hành'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _warrantyCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'Thời gian và điều kiện bảo hành…',
            ),
          ),
          const SizedBox(height: 16),
          Text(tr('Phụ phí khi thanh toán'),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            tr('Bật để thu ngân nhập trên màn thanh toán. Tắt thì không hiện.'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Bật phụ thu')),
            subtitle: Text(tr('Đặt tên, mức cố định % hoặc tiền — tự nhảy khi tạo đơn'),
              style: TextStyle(fontSize: 12),
            ),
            value: _enableSurcharge,
            onChanged: (v) => setState(() => _enableSurcharge = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Bật phí giao hàng')),
            subtitle: Text(tr('Có thể cài số tiền gợi ý mặc định tự nhảy'),
              style: TextStyle(fontSize: 12),
            ),
            value: _enableDeliveryFee,
            onChanged: (v) => setState(() => _enableDeliveryFee = v),
          ),
          PosSellFeeDefaultsFields(
            enableSurcharge: _enableSurcharge,
            enableDeliveryFee: _enableDeliveryFee,
            surchargeNameCtrl: _surchargeNameCtrl,
            surchargeDefaultCtrl: _surchargeDefaultCtrl,
            deliveryDefaultCtrl: _deliveryDefaultCtrl,
            surchargeIsPercent: _surchargeIsPercent,
            onSurchargeMode: (v) => setState(() => _surchargeIsPercent = v),
          ),
          const Divider(height: 28),
          Text(tr('Cách tính thuế VAT'),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          ...PosSellTaxMode.values.map(
            (m) => RadioListTile<PosSellTaxMode>(
              value: m,
              groupValue: _taxMode,
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(tr(m.label), style: const TextStyle(fontSize: 13)),
              onChanged: (v) {
                if (v != null) setState(() => _taxMode = v);
              },
            ),
          ),
          if (_taxMode != PosSellTaxMode.perItem) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<double>(
              value: _vatRate,
              decoration: InputDecoration(
                labelText: tr('Thuế suất VAT (%)'),
                border: OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(value: 0, child: Text(tr('0%'))),
                DropdownMenuItem(value: 5, child: Text(tr('5%'))),
                DropdownMenuItem(value: 8, child: Text(tr('8%'))),
                DropdownMenuItem(value: 10, child: Text(tr('10%'))),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _vatRate = v);
              },
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: PosTheme.kiotBlue,
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: (_saving ||
                    !context.watch<PermissionProvider>().canEditPosSetup())
                ? null
                : _save,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(tr('Lưu thiết lập')),
          ),
        ],
      ),
    );
  }
}
