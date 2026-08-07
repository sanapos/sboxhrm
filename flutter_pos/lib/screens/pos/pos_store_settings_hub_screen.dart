import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/cash_transaction.dart';
import '../../services/api_service.dart';
import '../../utils/pos_sell_store_settings.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_bank_account_form_dialog.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Thiết lập cửa hàng / VAT / VietQR — dùng trong Settings hub (HRM).
class PosStoreSettingsHubScreen extends StatefulWidget {
  const PosStoreSettingsHubScreen({super.key});

  @override
  State<PosStoreSettingsHubScreen> createState() =>
      _PosStoreSettingsHubScreenState();
}

class _PosStoreSettingsHubScreenState extends State<PosStoreSettingsHubScreen> {
  final _api = ApiService();
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  PosSellTaxMode _taxMode = PosSellTaxMode.includedInPrice;
  double _vatRate = 10;
  String? _vietQrBankId;
  bool _showVietQr = true;
  List<BankAccount> _accounts = [];
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
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = await PosSellStoreSettings.load();
    final banksRes = await _api.getPosBankAccounts();
    var accounts = <BankAccount>[];
    if (banksRes['isSuccess'] == true && banksRes['data'] is List) {
      accounts = (banksRes['data'] as List)
          .map((e) => BankAccount.fromJson(e as Map<String, dynamic>))
          .where((a) => a.isActive)
          .toList();
    }
    if (!mounted) return;
    setState(() {
      _nameCtrl.text = s.storeName;
      _addressCtrl.text = s.address;
      _phoneCtrl.text = s.phone;
      _taxMode = s.taxMode;
      _vatRate = s.defaultVatRate;
      _vietQrBankId = s.vietQrBankAccountId;
      _showVietQr = s.showVietQrAtPayment;
      _accounts = accounts;
      _loading = false;
    });
  }

  Future<void> _reloadAccounts() async {
    final res = await _api.getPosBankAccounts();
    if (res['isSuccess'] != true || res['data'] is! List || !mounted) return;
    setState(() {
      _accounts = (res['data'] as List)
          .map((e) => BankAccount.fromJson(e as Map<String, dynamic>))
          .where((a) => a.isActive)
          .toList();
      if (_vietQrBankId != null &&
          !_accounts.any((a) => a.id == _vietQrBankId)) {
        _vietQrBankId = null;
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final next = PosSellStoreSettings(
      storeName: _nameCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      taxMode: _taxMode,
      defaultVatRate: _vatRate,
      vietQrBankAccountId: _vietQrBankId,
      showVietQrAtPayment: _showVietQr,
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
          const SizedBox(height: 16),
          Text(tr('Tài khoản VietQR'),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (_accounts.isEmpty)
            Text(tr('Chưa có tài khoản ngân hàng. Thêm tài khoản để tạo mã QR.'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            )
          else
            DropdownButtonFormField<String?>(
              value: _vietQrBankId ??
                  _accounts
                      .where((a) => a.isDefault)
                      .map((a) => a.id)
                      .firstOrNull ??
                  _accounts.first.id,
              decoration: InputDecoration(
                labelText: tr('Tài khoản nhận tiền'),
                border: OutlineInputBorder(),
              ),
              items: _accounts
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
              onChanged: (v) => setState(() => _vietQrBankId = v),
            ),
          Row(
            children: [
              TextButton.icon(
                onPressed: () async {
                  final ok = await showPosBankAccountFormDialog(context);
                  if (ok) await _reloadAccounts();
                },
                icon: const Icon(Icons.add, size: 18),
                label: Text(tr('Thêm tài khoản')),
              ),
              if (_accounts.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    final current = _accounts.firstWhere(
                      (a) => a.id == (_vietQrBankId ?? _accounts.first.id),
                      orElse: () => _accounts.first,
                    );
                    final ok = await showPosBankAccountFormDialog(
                      context,
                      account: current,
                    );
                    if (ok) await _reloadAccounts();
                  },
                  child: Text(tr('Sửa')),
                ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Hiện mã VietQR khi thanh toán')),
            value: _showVietQr,
            onChanged: (v) => setState(() => _showVietQr = v),
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
            onPressed: _saving ? null : _save,
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
