import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../utils/pos_sell_store_settings.dart';
import '../pos/pos_sell_fee_defaults_fields.dart';
import '../sbox/sbox_ui.dart';
import 'settings_page.dart';

/// Bản nháp «Thuế VAT khi bán» + «Phụ thu & phí giao hàng» (lưu trong [PosSellStoreSettings], đồng bộ mọi
/// máy bán hàng). Dùng ở «Hóa đơn điện tử» (VAT), «Tham số hệ thống» (phụ thu, phí giao hàng) và —
/// khi người dùng không thấy 2 trang đó — «Thông tin cửa hàng».
class PosSellTaxFeeDraft {
  PosSellTaxMode taxMode = PosSellTaxMode.includedInPrice;
  double vatRate = 8;
  bool enableSurcharge = false;
  bool enableDeliveryFee = false;
  bool surchargeIsPercent = false;
  final surchargeNameCtrl = TextEditingController();
  final surchargeDefaultCtrl = TextEditingController();
  final deliveryDefaultCtrl = TextEditingController();

  List<TextEditingController> get controllers => [surchargeNameCtrl, surchargeDefaultCtrl, deliveryDefaultCtrl];

  void loadFrom(PosSellStoreSettings s) {
    taxMode = s.taxMode;
    vatRate = s.defaultVatRate;
    enableSurcharge = s.enableSurcharge;
    enableDeliveryFee = s.enableDeliveryFee;
    surchargeIsPercent = s.surchargeIsPercent;
    surchargeNameCtrl.text = s.surchargeLabel;
    surchargeDefaultCtrl.text = s.surchargeDefault > 0 ? PosSellStoreSettings.formatAmount(s.surchargeDefault) : '';
    deliveryDefaultCtrl.text = s.deliveryFeeDefault > 0 ? PosSellStoreSettings.formatAmount(s.deliveryFeeDefault) : '';
  }

  String get taxSnapshot => '${taxMode.key}|$vatRate';

  String get feeSnapshot => [
        enableSurcharge,
        enableDeliveryFee,
        surchargeIsPercent,
        for (final c in controllers) c.text,
      ].join('|');

  /// Ghi phần thuế / phí của bản nháp lên cấu hình mới nhất — các trường khác (tên, địa chỉ, VietQR…) giữ nguyên.
  PosSellStoreSettings applyTo(PosSellStoreSettings s, {bool tax = false, bool fees = false}) => s.copyWith(
        taxMode: tax ? taxMode : null,
        defaultVatRate: tax ? vatRate : null,
        enableSurcharge: fees ? enableSurcharge : null,
        enableDeliveryFee: fees ? enableDeliveryFee : null,
        surchargeLabel: fees ? surchargeNameCtrl.text.trim() : null,
        surchargeIsPercent: fees ? surchargeIsPercent : null,
        surchargeDefault: fees ? PosSellStoreSettings.parseAmount(surchargeDefaultCtrl.text) : null,
        deliveryFeeDefault: fees ? PosSellStoreSettings.parseAmount(deliveryDefaultCtrl.text) : null,
      );

  void dispose() {
    for (final c in controllers) {
      c.dispose();
    }
  }
}

/// «Thuế VAT khi bán»: giá đã gồm / chưa gồm thuế + thuế suất mặc định.
class PosSellVatSection extends StatelessWidget {
  const PosSellVatSection({super.key, required this.draft, required this.edit, required this.onChanged, this.subtitle});

  final PosSellTaxFeeDraft draft;
  final bool edit;
  final VoidCallback onChanged;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: 'Thuế VAT khi bán',
      subtitle: subtitle ?? 'Áp dụng cho mọi máy bán hàng và mã QR trên hóa đơn',
      icon: Icons.percent_rounded,
      children: [
        for (final m in PosSellTaxMode.values)
          ListTile(
            contentPadding: EdgeInsets.zero,
            enabled: edit,
            onTap: () {
              draft.taxMode = m;
              onChanged();
            },
            leading: Icon(draft.taxMode == m ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                color: draft.taxMode == m ? SboxColors.brand600 : SboxColors.slate400),
            title: Text(tr(m.label), style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        SettingsTile(
          label: 'Thuế suất mặc định',
          help: draft.taxMode == PosSellTaxMode.includedInPrice
              ? 'Giá bán đã gồm thuế — dùng để tách thuế trên hóa đơn'
              : 'Cộng thêm vào giá khi bán',
          control: SettingsSegment<double>(
            value: [0.0, 5.0, 8.0, 10.0].contains(draft.vatRate) ? draft.vatRate : 8.0,
            options: const [(0.0, '0%'), (5.0, '5%'), (8.0, '8%'), (10.0, '10%')],
            onChanged: edit
                ? (v) {
                    draft.vatRate = v;
                    onChanged();
                  }
                : (_) {},
          ),
        ),
      ],
    );
  }
}

/// «Phụ thu & phí giao hàng»: bật ô nhập trên màn thanh toán + số gợi ý tự điền.
class PosSellFeesSection extends StatelessWidget {
  const PosSellFeesSection({super.key, required this.draft, required this.edit, required this.onChanged});

  final PosSellTaxFeeDraft draft;
  final bool edit;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: 'Phụ thu & phí giao hàng',
      subtitle: 'Bật thì ô nhập hiện trên màn thanh toán, có số gợi ý tự điền',
      icon: Icons.add_card_outlined,
      children: [
        SettingsTile(
          divider: false,
          label: 'Phụ thu',
          help: 'VD: phụ thu ngày lễ, phí dịch vụ — theo % hoặc số tiền',
          control: Switch(
            value: draft.enableSurcharge,
            onChanged: edit
                ? (v) {
                    draft.enableSurcharge = v;
                    onChanged();
                  }
                : null,
          ),
        ),
        SettingsTile(
          label: 'Phí giao hàng',
          control: Switch(
            value: draft.enableDeliveryFee,
            onChanged: edit
                ? (v) {
                    draft.enableDeliveryFee = v;
                    onChanged();
                  }
                : null,
          ),
        ),
        PosSellFeeDefaultsFields(
          enableSurcharge: draft.enableSurcharge,
          enableDeliveryFee: draft.enableDeliveryFee,
          surchargeNameCtrl: draft.surchargeNameCtrl,
          surchargeDefaultCtrl: draft.surchargeDefaultCtrl,
          deliveryDefaultCtrl: draft.deliveryDefaultCtrl,
          surchargeIsPercent: draft.surchargeIsPercent,
          onSurchargeMode: (v) {
            draft.surchargeIsPercent = v;
            onChanged();
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
