import 'package:flutter/material.dart';

import '../../models/cash_transaction.dart';
import '../../services/api_service.dart';
import '../../utils/pos_sell_store_settings.dart';
import 'pos_bank_account_form_dialog.dart';
import 'pos_sell_fee_defaults_fields.dart';
import 'pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

const _kiotBlue = PosTheme.kiotBlue;

/// Dialog thiết lập cửa hàng, thuế và VietQR.
Future<PosSellStoreSettings?> showPosSellStoreSettingsDialog(
  BuildContext context, {
  required PosSellStoreSettings initial,
}) async {
  final api = ApiService();
  final banksRes = await api.getPosBankAccounts();
  var bankAccounts = <BankAccount>[];
  if (banksRes['isSuccess'] == true && banksRes['data'] is List) {
    bankAccounts = (banksRes['data'] as List)
        .map((e) => BankAccount.fromJson(e as Map<String, dynamic>))
        .where((a) => a.isActive)
        .toList();
  }

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
  var vietQrBankId = initial.vietQrBankAccountId;
  var showVietQr = initial.showVietQrAtPayment;
  var enableSurcharge = initial.enableSurcharge;
  var enableDeliveryFee = initial.enableDeliveryFee;
  var surchargeIsPercent = initial.surchargeIsPercent;
  var accounts = List<BankAccount>.from(bankAccounts);

  Future<void> reloadAccounts(StateSetter setDlg) async {
    final res = await api.getPosBankAccounts();
    if (res['isSuccess'] == true && res['data'] is List) {
      setDlg(() {
        accounts = (res['data'] as List)
            .map((e) => BankAccount.fromJson(e as Map<String, dynamic>))
            .where((a) => a.isActive)
            .toList();
        if (vietQrBankId != null &&
            !accounts.any((a) => a.id == vietQrBankId)) {
          vietQrBankId = null;
        }
      });
    }
  }

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
                const SizedBox(height: 14),
                Text(tr('Tài khoản VietQR'),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                if (accounts.isEmpty)
                  Text(tr('Chưa có tài khoản ngân hàng. Thêm tài khoản để tạo mã QR thanh toán.'),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  )
                else
                  DropdownButtonFormField<String?>(
                    value: vietQrBankId ??
                        accounts
                            .where((a) => a.isDefault)
                            .map((a) => a.id)
                            .firstOrNull ??
                        accounts.first.id,
                    decoration: InputDecoration(
                      labelText: tr('Tài khoản nhận tiền'),
                      border: OutlineInputBorder(),
                    ),
                    items: accounts
                        .map(
                          (a) => DropdownMenuItem(
                            value: a.id,
                            child: Text(
                              tr('${a.bankShortName ?? a.bankName} · ${a.accountNumber}'
                              '${a.isDefault ? ' (Mặc định)' : ''}'),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setDlg(() => vietQrBankId = v),
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        final ok = await showPosBankAccountFormDialog(ctx);
                        if (ok) await reloadAccounts(setDlg);
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(tr('Thêm tài khoản')),
                    ),
                    if (accounts.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      TextButton(
                        onPressed: () async {
                          final current = accounts.firstWhere(
                            (a) => a.id == (vietQrBankId ?? accounts.first.id),
                            orElse: () => accounts.first,
                          );
                          final ok = await showPosBankAccountFormDialog(
                            ctx,
                            account: current,
                          );
                          if (ok) await reloadAccounts(setDlg);
                        },
                        child: Text(tr('Sửa')),
                      ),
                    ],
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr('Hiện mã VietQR khi thanh toán')),
                  subtitle: Text(tr('Tạo QR động theo tổng tiền trên điện thoại'),
                    style: TextStyle(fontSize: 11),
                  ),
                  value: showVietQr,
                  onChanged: (v) => setDlg(() => showVietQr = v),
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
                Text(tr('In mã VietQR trên hóa đơn: bật trong Thiết lập máy in.'),
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
                  vietQrBankAccountId: vietQrBankId,
                  showVietQrAtPayment: showVietQr,
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
