import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/permission_provider.dart';
import '../../utils/pos_sell_store_settings.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_sell_fee_defaults_fields.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

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
    _surchargeNameCtrl.dispose();
    _surchargeDefaultCtrl.dispose();
    _deliveryDefaultCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = await PosSellStoreSettings.load();
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
    if (!mounted) return;
    setState(() => _saving = false);
    NotificationOverlayManager().showSuccess(
      title: 'Đã lưu',
      message: tr('Thiết lập cửa hàng đã cập nhật'),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Scaffold(
          backgroundColor: HrmPageChrome.background,
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
            tr('Tài khoản ngân hàng và VietQR nằm ở Cổng thanh toán.'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
