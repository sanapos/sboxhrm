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
import '../../utils/pos_doc_numbering.dart';
import '../../utils/pos_sell_settings_helper.dart';
import '../../utils/pos_sell_store_settings.dart';
import '../../utils/settings_hub_catalog.dart';
import '../../widgets/pos/pos_commercial_company_fields.dart';
import '../../widgets/sbox/sbox_ui.dart';
import '../../widgets/settings/pos_sell_tax_fee_sections.dart';
import '../../widgets/settings/settings_page.dart';
import '../settings_hub_screen.dart';

/// Thông tin cửa hàng: tên in hóa đơn, thông tin công ty (báo giá / hợp đồng), logo & con dấu, điều khoản.
/// Thuế VAT khi bán nằm ở «Hóa đơn điện tử», phụ thu & phí giao hàng ở «Tham số hệ thống» — chỉ hiện lại ở
/// đây khi người dùng không thấy trang đó (gói / quyền), để luôn có chỗ chỉnh.
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
  final _fees = PosSellTaxFeeDraft();
  final _quotePatternCtrl = TextEditingController(text: PosDocNumbering.quoteDefault);
  final _contractPatternCtrl = TextEditingController(text: PosDocNumbering.contractDefault);
  PosDocNumbering _numbering = const PosDocNumbering();
  bool _quoteManual = false;
  bool _contractManual = false;

  List<TextEditingController> get _ctrls => [
        _nameCtrl, _addressCtrl, _phoneCtrl, _companyCtrl, _taxCtrl, _companyAddressCtrl, _companyPhoneCtrl,
        _companyEmailCtrl, _bankNoCtrl, _bankNameCtrl, _bankHolderCtrl, _repCtrl, _titleCtrl, _termsCtrl,
        _warrantyCtrl, _quotePatternCtrl, _contractPatternCtrl, ..._fees.controllers,
      ];

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

  /// Trang «Hóa đơn điện tử» / «Tham số hệ thống» có hiện với người dùng này không (gói + quyền).
  bool _hubShows(String code) {
    try {
      return SettingsHubScreen.visibleItems(context, SettingsHubCatalog.itemsForCurrentApp).any((i) => i.code == code);
    } catch (_) {
      return false;
    }
  }

  bool get _showVat => !_hubShows('einvoice');
  bool get _showFees => !_hubShows('system');

  String get _snapshot => [
        ..._ctrls.map((c) => c.text),
        _fees.taxSnapshot,
        _fees.feeSnapshot,
        _quoteManual,
        _contractManual,
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
    final sell = await PosSellSettingsHelper(ApiService()).load();
    if (!mounted) return;
    Map<String, dynamic> m = const {};
    if (profileRes['isSuccess'] == true && profileRes['data'] is Map) {
      m = mergeCommercialProfile(Map<String, dynamic>.from(profileRes['data'] as Map), local);
    } else if (local.isNotEmpty) {
      m = local;
    }
    String t(String a) => (m[a] ?? m[a[0].toUpperCase() + a.substring(1)] ?? '').toString();
    // Cửa hàng mới chưa lưu thông tin in → điền sẵn tên / địa chỉ / SĐT lúc đăng ký (chủ quán bấm Lưu để dùng).
    var regName = '', regAddress = '', regPhone = '';
    if (s.storeName.trim().isEmpty || s.address.trim().isEmpty || s.phone.trim().isEmpty) {
      final reg = await ApiService().getPosQrOrderTables();
      if (!mounted) return;
      if (reg['isSuccess'] == true && reg['data'] is Map) {
        final d = reg['data'] as Map;
        regName = '${d['storeName'] ?? ''}'.trim();
        regAddress = '${d['storeAddress'] ?? ''}'.trim();
        regPhone = '${d['storePhone'] ?? ''}'.trim();
      }
    }
    setState(() {
      _nameCtrl.text = s.storeName.trim().isNotEmpty ? s.storeName : regName;
      _addressCtrl.text = s.address.trim().isNotEmpty ? s.address : regAddress;
      _phoneCtrl.text = s.phone.trim().isNotEmpty ? s.phone : regPhone;
      _fees.loadFrom(s);
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
      _numbering = PosDocNumbering.parse(sell.settings?.extraJson);
      _quoteManual = _numbering.quote.manual;
      _contractManual = _numbering.contract.manual;
      _quotePatternCtrl.text = _numbering.quote.pattern;
      _contractPatternCtrl.text = _numbering.contract.pattern;
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
    final patternErr =
        PosDocNumbering.validate(_quotePatternCtrl.text) ?? PosDocNumbering.validate(_contractPatternCtrl.text);
    if (patternErr != null) {
      _toast('Mẫu đánh số: $patternErr', error: true);
      return;
    }
    setState(() => _saving = true);
    final existing = await PosSellStoreSettings.load();
    // Chỉ ghi phần thuế / phí đang hiện ở trang này — phần chỉnh ở «Hóa đơn điện tử» / «Tham số hệ thống» giữ nguyên.
    final next = _fees.applyTo(
      existing.copyWith(
        storeName: _nameCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
      ),
      tax: _showVat,
      fees: _showFees,
    );
    await next.save();
    final numbering = PosDocNumbering(
      quote: PosDocNumberRule(manual: _quoteManual, pattern: _quotePatternCtrl.text.trim()),
      contract: PosDocNumberRule(manual: _contractManual, pattern: _contractPatternCtrl.text.trim()),
    );
    if (numbering.mergeIntoExtraJson(null) != _numbering.mergeIntoExtraJson(null)) {
      final err = await PosDocNumbering.save(numbering);
      if (!mounted) return;
      if (err != null) {
        setState(() => _saving = false);
        _toast('Chưa lưu được cách đánh số: $err', error: true);
        return;
      }
      _numbering = numbering;
    }
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
      subtitle: 'Tên in hóa đơn, logo & con dấu, thông tin công ty, điều khoản — đồng bộ mọi máy bán hàng',
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
        if (_showVat) PosSellVatSection(draft: _fees, edit: edit, onChanged: _rebuild),
        if (_showFees) PosSellFeesSection(draft: _fees, edit: edit, onChanged: _rebuild),
        // Chỗ mới của 2 nhóm đã chuyển — người quen tìm ở đây bấm sang thẳng.
        if (!_showVat || !_showFees)
          SettingsSection(
            title: 'Thuế & phụ thu đã chuyển chỗ',
            icon: Icons.drive_file_move_outline,
            children: [
              if (!_showVat)
                SettingsLinkTile(
                  icon: Icons.request_quote_outlined,
                  label: 'Thuế VAT khi bán',
                  help: 'Ở «Hóa đơn điện tử», cạnh thuế khi xuất hóa đơn',
                  divider: false,
                  onTap: () => SettingsHubScreen.openCode('einvoice'),
                ),
              if (!_showFees)
                SettingsLinkTile(
                  icon: Icons.settings_suggest_outlined,
                  label: 'Phụ thu & phí giao hàng',
                  help: 'Ở «Tham số hệ thống»',
                  divider: !_showVat,
                  onTap: () => SettingsHubScreen.openCode('system'),
                ),
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
          title: 'Đánh số báo giá & hợp đồng',
          subtitle: 'Mỗi công ty một kiểu số: máy tự nhảy theo mẫu, hoặc người lập tự nhập số',
          icon: Icons.tag_outlined,
          children: [
            const SizedBox(height: 6),
            _numberingBlock('Báo giá', _quoteManual, (v) => setState(() => _quoteManual = v), _quotePatternCtrl,
                PosDocNumbering.quotePresets, edit),
            const SizedBox(height: 16),
            _numberingBlock('Hợp đồng', _contractManual, (v) => setState(() => _contractManual = v),
                _contractPatternCtrl, PosDocNumbering.contractPresets, edit),
            const SizedBox(height: 10),
            Text(
              // Một chuỗi liền — công cụ trích chuỗi dịch bỏ qua chuỗi ghép 'a' 'b'.
              tr('Ký hiệu trong mẫu: {YYYY} năm · {YY} 2 số cuối năm · {MM} tháng · {DD} ngày · {SEQ:4} số thứ tự 4 chữ số. Mẫu có {DD} thì mỗi ngày đếm lại từ 1, chỉ có năm thì mỗi năm đếm lại, không có ngày tháng thì đếm nối tiếp mãi.'),
              style: const TextStyle(fontSize: 12, height: 1.35, color: SboxColors.slate600),
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

  /// Một loại chứng từ: tự nhảy theo mẫu / tự nhập + ô mẫu (xem trước số) + mẫu hay dùng.
  Widget _numberingBlock(String label, bool manual, ValueChanged<bool> onManual, TextEditingController ctrl,
      List<String> presets, bool edit) {
    final err = PosDocNumbering.validate(ctrl.text);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(tr(label), style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<bool>(
          segments: [
            ButtonSegment(value: false, icon: const Icon(Icons.auto_mode_outlined), label: Text(tr('Tự nhảy theo mẫu'))),
            ButtonSegment(value: true, icon: const Icon(Icons.edit_outlined), label: Text(tr('Tự nhập'))),
          ],
          selected: {manual},
          onSelectionChanged: edit ? (v) => onManual(v.first) : null,
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: ctrl,
        enabled: edit,
        decoration: _dec(manual ? 'Mẫu gợi ý số kế tiếp' : 'Mẫu số').copyWith(
          errorText: err == null ? null : tr(err),
          helperText: err == null ? tr('Số đầu tiên hôm nay: ${PosDocNumbering.example(ctrl.text.trim())}') : null,
        ),
      ),
      if (edit) ...[
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final p in presets)
            ActionChip(
              label: Text(PosDocNumbering.example(p), style: const TextStyle(fontSize: 12)),
              tooltip: p,
              onPressed: () => ctrl.text = p,
            ),
        ]),
      ],
      if (manual)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            tr('Khi lập chứng từ, ô số điền sẵn số kế tiếp theo mẫu — sửa thành số của công ty, để trống thì máy tự nhảy. Số trùng sẽ bị báo.'),
            style: const TextStyle(fontSize: 12, height: 1.35, color: SboxColors.slate600),
          ),
        ),
    ]);
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
