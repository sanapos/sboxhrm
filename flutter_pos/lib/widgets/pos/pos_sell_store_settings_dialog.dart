import 'package:flutter/material.dart';

import '../../utils/pos_sell_store_settings.dart';
import 'pos_sell_fee_defaults_fields.dart';
import 'pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

const _kiotBlue = PosTheme.kiotBlue;

/// Dialog thiết lập cửa hàng, thuế và phụ phí.
Future<PosSellStoreSettings?> showPosSellStoreSettingsDialog(
  BuildContext context, {
  required PosSellStoreSettings initial,
}) async {
  if (!context.mounted) return null;

  final nameCtrl = TextEditingController(text: tr(initial.storeName));
  final addressCtrl = TextEditingController(text: tr(initial.address));
  final phoneCtrl = TextEditingController(text: tr(initial.phone));
  final surchargeNameCtrl =
      TextEditingController(text: initial.surchargeLabel);
  final surchargeDefaultCtrl = TextEditingController(
    text: initial.surchargeDefault > 0
        ? PosSellStoreSettings.formatAmount(initial.surchargeDefault)
        : '',
  );
  final deliveryDefaultCtrl = TextEditingController(
    text: initial.deliveryFeeDefault > 0
        ? PosSellStoreSettings.formatAmount(initial.deliveryFeeDefault)
        : '',
  );
  var taxMode = initial.taxMode;
  var vatRate = initial.defaultVatRate;
  var enableSurcharge = initial.enableSurcharge;
  var enableDeliveryFee = initial.enableDeliveryFee;
  var surchargeIsPercent = initial.surchargeIsPercent;

  final result = await showDialog<PosSellStoreSettings>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) => AlertDialog(
        title: Text(tr('Thiết lập cửa hàng')),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: tr('Tên cửa hàng'),
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: addressCtrl,
                  decoration: InputDecoration(
                    labelText: tr('Địa chỉ'),
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: tr('Số điện thoại'),
                    border: OutlineInputBorder(),
                  ),
                ),
                const Divider(height: 20),
                Text(tr('Phụ phí khi thanh toán'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Bật phụ thu')),
                  subtitle: Text(tr('Đặt tên, mức cố định % hoặc tiền — tự nhảy khi tạo đơn'),
                    style: TextStyle(fontSize: 11),
                  ),
                  value: enableSurcharge,
                  onChanged: (v) => setDlg(() => enableSurcharge = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Bật phí giao hàng')),
                  subtitle: Text(tr('Có thể cài số tiền gợi ý mặc định tự nhảy'),
                    style: TextStyle(fontSize: 11),
                  ),
                  value: enableDeliveryFee,
                  onChanged: (v) => setDlg(() => enableDeliveryFee = v),
                ),
                PosSellFeeDefaultsFields(
                  compact: true,
                  enableSurcharge: enableSurcharge,
                  enableDeliveryFee: enableDeliveryFee,
                  surchargeNameCtrl: surchargeNameCtrl,
                  surchargeDefaultCtrl: surchargeDefaultCtrl,
                  deliveryDefaultCtrl: deliveryDefaultCtrl,
                  surchargeIsPercent: surchargeIsPercent,
                  onSurchargeMode: (v) =>
                      setDlg(() => surchargeIsPercent = v),
                ),
                const Divider(height: 20),
                Text(tr('Cách tính thuế VAT'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                ...PosSellTaxMode.values.map(
                  (m) => RadioListTile<PosSellTaxMode>(
                    value: m,
                    groupValue: taxMode,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr(m.label), style: const TextStyle(fontSize: 13)),
                    onChanged: (v) {
                      if (v != null) setDlg(() => taxMode = v);
                    },
                  ),
                ),
                if (taxMode != PosSellTaxMode.perItem) ...[
                  const SizedBox(height: 6),
                  DropdownButtonFormField<double>(
                    value: vatRate,
                    decoration: InputDecoration(
                      labelText: tr('Thuế suất VAT (%)'),
                      border: const OutlineInputBorder(),
                      helperText: tr(taxMode == PosSellTaxMode.includedInPrice
                          ? 'Giá bán đã gồm VAT — trên HĐ ghi VAT = 0đ'
                          : taxMode == PosSellTaxMode.perItem
                              ? 'Cộng thêm VAT theo % từng mặt hàng (thiết lập trên hàng hóa)'
                              : 'VAT cộng thêm trên tổng tiền hàng sau chiết khấu'),
                      helperMaxLines: 2,
                    ),
                    items: [
                      DropdownMenuItem(value: 0, child: Text(tr('0%'))),
                      DropdownMenuItem(value: 5, child: Text(tr('5%'))),
                      DropdownMenuItem(value: 8, child: Text(tr('8%'))),
                      DropdownMenuItem(value: 10, child: Text(tr('10%'))),
                    ],
                    onChanged: (v) {
                      if (v != null) setDlg(() => vatRate = v);
                    },
                  ),
                ] else ...[
                  const SizedBox(height: 6),
                  Text(tr('Thuế suất được thiết lập riêng trên từng hàng hóa (mục Giá bán).'),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  tr('Tài khoản ngân hàng / VietQR: Cổng thanh toán. In QR trên hóa đơn: Thiết lập máy in.'),
                  style: TextStyle(fontSize: 11, color: PosTheme.textSecondary),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Huỷ'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kiotBlue),
            onPressed: () {
              Navigator.pop(
                ctx,
                PosSellStoreSettings(
                  storeName: nameCtrl.text.trim(),
                  address: addressCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  taxMode: taxMode,
                  defaultVatRate: vatRate,
                  vietQrBankAccountId: initial.vietQrBankAccountId,
                  showVietQrAtPayment: initial.showVietQrAtPayment,
                  enableSurcharge: enableSurcharge,
                  enableDeliveryFee: enableDeliveryFee,
                  surchargeLabel: surchargeNameCtrl.text.trim(),
                  surchargeIsPercent: surchargeIsPercent,
                  surchargeDefault: PosSellStoreSettings.parseAmount(
                    surchargeDefaultCtrl.text,
                  ),
                  deliveryFeeDefault: PosSellStoreSettings.parseAmount(
                    deliveryDefaultCtrl.text,
                  ),
                ),
              );
            },
            child: Text(tr('Lưu')),
          ),
        ],
      ),
    ),
  );

  nameCtrl.dispose();
  addressCtrl.dispose();
  phoneCtrl.dispose();
  surchargeNameCtrl.dispose();
  surchargeDefaultCtrl.dispose();
  deliveryDefaultCtrl.dispose();
  return result;
}
