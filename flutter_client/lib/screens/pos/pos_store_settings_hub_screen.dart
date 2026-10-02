import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../utils/pos_commercial_profile_local.dart';
import '../../utils/pos_sell_store_settings.dart';
import '../../widgets/pos/pos_commercial_company_fields.dart';
import '../../widgets/pos/pos_sell_fee_defaults_fields.dart';
import '../../widgets/sbox/sbox_ui.dart';
import '../../widgets/settings/settings_page.dart';

/// Thông tin cửa hàng: tên in hóa đơn, thông tin công ty (báo giá / hợp đồng), logo & con dấu,
/// cách tính VAT, phụ thu & phí giao hàng, điều khoản. Thuế / phụ thu lưu trên server (đồng bộ mọi máy).
class PosStoreSettingsHubScreen extends StatefulWidget {
  const PosStoreSettingsHubScreen({super.key, this.canEditOverride});

  final bool? canEditOverride;

  @override
  State<PosStoreSettingsHubScreen> createState() => _PosStoreSettingsHubScreenState();
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

  List<TextEditingController> get _ctrls => [
        _nameCtrl, _addressCtrl, _phoneCtrl, _companyCtrl, _taxCtrl, _companyAddressCtrl, _companyPhoneCtrl,
        _companyEmailCtrl, _bankNoCtrl, _bankNameCtrl, _bankHolderCtrl, _repCtrl, _titleCtrl, _termsCtrl,
        _warrantyCtrl, _surchargeNameCtrl, _surchargeDefaultCtrl, _deliveryDefaultCtrl,
      ];

  PosSellTaxMode _taxMode = PosSellTaxMode.includedInPrice;
  double _vatRate = 8;
  bool _enableSurcharge = false;
  bool _enableDeliveryFee = false;
  bool _surchargeIsPercent = false;
  bool _loading = true;
  bool _saving = false;
  String _stampB64 = '';
  Uint8List? _stampBytes;
  String _logoB64 = '';
  Uint8List? _logoBytes;
  String _savedSnapshot = '';

  bool get _canEdit {
    if (widget.canEditOverride != null) return widget.canEditOverride!;
    try {
      return Provider.of<PermissionProvider>(context, listen: false).canEditPosSetup();
    } catch (_) {
      return false;
    }
  }

  String get _snapshot => [
        ..._ctrls.map((c) => c.text),
        _taxMode.key,
        _vatRate,
        _enableSurcharge,
        _enableDeliveryFee,
        _surchargeIsPercent,
        _stampB64.length,
        _stampB64.hashCode,
        _logoB64.length,
        _logoB64.hashCode,
      ].join('|');

  bool get _dirty => !_loading && _snapshot != _savedSnapshot;

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    for (final c in _ctrls) {
      c.addListener(_rebuild);
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
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

  void _toast(String m, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(m)),
        backgroundColor: error ? SboxColors.danger : null,
        behavior: SnackBarBehavior.floating,
      ));

  Future<void> _pickImage({bool logo = false}) async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 640, maxHeight: 640, imageQuality: 92);
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    if (bytes.length > 700 * 1024) {
      _toast('Ảnh cần dưới 700 KB', error: true);
      return;
    }
    setState(() {
      if (logo) {
        _logoBytes = bytes;
        _logoB64 = base64Encode(bytes);
      } else {
        _stampBytes = bytes;
        _stampB64 = base64Encode(bytes);
      }
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = await PosSellStoreSettings.load();
    final profileRes = await ApiService().getPosCommercialProfile();
    final local = await loadLocalCommercialProfile();
    if (!mounted) return;
    Map<String, dynamic> m = const {};
    if (profileRes['isSuccess'] == true && profileRes['data'] is Map) {
      m = mergeCommercialProfile(Map<String, dynamic>.from(profileRes['data'] as Map), local);
    } else if (local.isNotEmpty) {
      m = local;
    }
    String t(String a) => (m[a] ?? m[a[0].toUpperCase() + a.substring(1)] ?? '').toString();
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
      _surchargeDefaultCtrl.text = s.surchargeDefault > 0 ? PosSellStoreSettings.formatAmount(s.surchargeDefault) : '';
      _deliveryDefaultCtrl.text = s.deliveryFeeDefault > 0 ? PosSellStoreSettings.formatAmount(s.deliveryFeeDefault) : '';
      _companyCtrl.text = t('companyName');
      _taxCtrl.text = t('taxCode');
      _companyAddressCtrl.text = t('address');
      _companyPhoneCtrl.text = t('phone');
      _companyEmailCtrl.text = t('email');
      _bankNoCtrl.text = t('bankAccountNumber');
      _bankNameCtrl.text = t('bankName');
      _bankHolderCtrl.text = t('bankAccountHolder');
      _repCtrl.text = t('legalRepresentative');
      _titleCtrl.text = t('legalTitle').trim().isEmpty ? 'Giám đốc' : t('legalTitle');
      _stampB64 = t('stampPngBase64').trim();
      _stampBytes = _decodeB64(_stampB64);
      _logoB64 = t('logoPngBase64').trim();
      _logoBytes = _decodeB64(_logoB64);
      _termsCtrl.text = t('defaultTerms');
      _warrantyCtrl.text = t('warrantyPolicy');
      _loading = false;
      _savedSnapshot = _snapshot;
    });
  }

  Future<void> _save() async {
    if (!_canEdit) {
      _toast('Chỉ quản lý được lưu thiết lập cửa hàng', error: true);
      return;
    }
    if (_nameCtrl.text.trim().isEmpty) {
      _toast('Nhập tên cửa hàng (in trên hóa đơn)', error: true);
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
      surchargeDefault: PosSellStoreSettings.parseAmount(_surchargeDefaultCtrl.text),
      deliveryFeeDefault: PosSellStoreSettings.parseAmount(_deliveryDefaultCtrl.text),
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
      saved['clientSavedAt'] = saved['updatedAt'] ?? saved['UpdatedAt'] ?? profileBody['clientSavedAt'];
      await saveLocalCommercialProfile(saved);
    }
    if (!mounted) return;
    if (profileRes['isSuccess'] != true) {
      _toast(profileRes['message']?.toString() ?? 'Đã lưu cửa hàng, nhưng thông tin công ty chưa lưu được — kiểm tra quyền', error: true);
      return;
    }
    setState(() => _savedSnapshot = _snapshot);
    _toast('Đã lưu thông tin cửa hàng');
  }

  InputDecoration _dec(String label, {String? hint}) => InputDecoration(
        labelText: tr(label),
        hintText: hint == null ? null : tr(hint),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  @override
  Widget build(BuildContext context) {
    final edit = _canEdit;
    return SettingsPage(
      title: 'Thông tin cửa hàng',
      subtitle: 'Tên in hóa đơn, thông tin công ty, logo, thuế VAT, phụ thu — đồng bộ mọi máy bán hàng',
      icon: Icons.store_outlined,
      loading: _loading,
      dirty: _dirty,
      saving: _saving,
      onSave: _save,
      onDiscard: _load,
      children: [
        if (!edit) const SettingsNote('Bạn chỉ có quyền xem. Cần quyền sửa «Trung tâm thiết lập».', icon: Icons.lock_outline_rounded, tone: SboxTone.neutral),
        SettingsSection(
          title: 'In trên hóa đơn bán hàng',
          icon: Icons.receipt_long_outlined,
          children: [
            const SizedBox(height: 6),
            TextField(controller: _nameCtrl, enabled: edit, decoration: _dec('Tên cửa hàng *', hint: 'VD: SBOX Coffee Quận 1')),
            const SizedBox(height: 10),
            TextField(controller: _addressCtrl, enabled: edit, decoration: _dec('Địa chỉ')),
            const SizedBox(height: 10),
            TextField(controller: _phoneCtrl, enabled: edit, keyboardType: TextInputType.phone, decoration: _dec('Số điện thoại')),
            const SizedBox(height: 12),
          ],
        ),
        SettingsSection(
          title: 'Logo & con dấu',
          subtitle: 'Logo in trên hóa đơn / báo giá; con dấu chèn vào báo giá, hợp đồng. Ảnh dưới 700 KB',
          icon: Icons.image_outlined,
          children: [
            const SizedBox(height: 6),
            Wrap(spacing: 16, runSpacing: 12, children: [
              _imageBox('Logo', _logoBytes, edit, () => _pickImage(logo: true), () => setState(() {
                    _logoB64 = '';
                    _logoBytes = null;
                  })),
              _imageBox('Con dấu', _stampBytes, edit, () => _pickImage(), () => setState(() {
                    _stampB64 = '';
                    _stampBytes = null;
                  })),
            ]),
            const SizedBox(height: 12),
          ],
        ),
        SettingsSection(
          title: 'Thuế VAT khi bán',
          subtitle: 'Áp dụng cho mọi máy bán hàng và mã QR trên hóa đơn',
          icon: Icons.percent_rounded,
          children: [
            for (final m in PosSellTaxMode.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: edit,
                onTap: () => setState(() => _taxMode = m),
                leading: Icon(_taxMode == m ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                    color: _taxMode == m ? SboxColors.brand600 : SboxColors.slate400),
                title: Text(tr(m.label), style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            SettingsTile(
              label: 'Thuế suất mặc định',
              help: _taxMode == PosSellTaxMode.includedInPrice ? 'Giá bán đã gồm thuế — dùng để tách thuế trên hóa đơn' : 'Cộng thêm vào giá khi bán',
              control: SettingsSegment<double>(
                value: [0.0, 5.0, 8.0, 10.0].contains(_vatRate) ? _vatRate : 8.0,
                options: const [(0.0, '0%'), (5.0, '5%'), (8.0, '8%'), (10.0, '10%')],
                onChanged: edit ? (v) => setState(() => _vatRate = v) : (_) {},
              ),
            ),
          ],
        ),
        SettingsSection(
          title: 'Phụ thu & phí giao hàng',
          subtitle: 'Bật thì ô nhập hiện trên màn thanh toán, có số gợi ý tự điền',
          icon: Icons.add_card_outlined,
          children: [
            SettingsTile(
              divider: false,
              label: 'Phụ thu',
              help: 'VD: phụ thu ngày lễ, phí dịch vụ — theo % hoặc số tiền',
              control: Switch(value: _enableSurcharge, onChanged: edit ? (v) => setState(() => _enableSurcharge = v) : null),
            ),
            SettingsTile(
              label: 'Phí giao hàng',
              control: Switch(value: _enableDeliveryFee, onChanged: edit ? (v) => setState(() => _enableDeliveryFee = v) : null),
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
            const SizedBox(height: 8),
          ],
        ),
        SettingsSection(
          title: 'Thông tin công ty',
          subtitle: 'In trên báo giá, hợp đồng, hóa đơn điện tử. Tài khoản nhận tiền tại quầy (QR) đặt ở «Tài khoản nhận tiền»',
          icon: Icons.business_outlined,
          children: [
            const SizedBox(height: 6),
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
              enabled: edit,
            ),
            const SizedBox(height: 12),
          ],
        ),
        SettingsSection(
          title: 'Điều khoản mặc định',
          icon: Icons.description_outlined,
          children: [
            const SizedBox(height: 6),
            TextField(controller: _termsCtrl, enabled: edit, maxLines: 4, decoration: _dec('Điều khoản báo giá')),
            const SizedBox(height: 10),
            TextField(controller: _warrantyCtrl, enabled: edit, maxLines: 4, decoration: _dec('Chính sách bảo hành')),
            const SizedBox(height: 12),
          ],
        ),
      ],
    );
  }

  Widget _imageBox(String label, Uint8List? bytes, bool edit, VoidCallback onPick, VoidCallback onRemove) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(tr(label), style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Container(
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          color: SboxColors.slate50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SboxColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: bytes == null
            ? const Icon(Icons.add_photo_alternate_outlined, size: 36, color: SboxColors.slate400)
            : Image.memory(bytes, fit: BoxFit.contain),
      ),
      if (edit)
        Row(mainAxisSize: MainAxisSize.min, children: [
          TextButton(onPressed: onPick, child: Text(tr(bytes == null ? 'Tải ảnh' : 'Đổi ảnh'))),
          if (bytes != null) TextButton(onPressed: onRemove, child: Text(tr('Gỡ'), style: const TextStyle(color: SboxColors.danger))),
        ]),
    ]);
  }
}
