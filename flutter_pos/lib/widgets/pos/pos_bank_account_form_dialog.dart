import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/cash_transaction.dart';
import '../../services/api_service.dart';
import '../../utils/responsive_helper.dart';
import '../notification_overlay.dart';
import 'pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

const _kiotBlue = PosTheme.kiotBlue;

/// Form thêm/sửa tài khoản ngân hàng (dùng trong POS).
Future<bool> showPosBankAccountFormDialog(
  BuildContext context, {
  BankAccount? account,
}) async {
  final api = ApiService();
  final banksRes = await api.getVietQRBanks();
  if (!context.mounted) return false;
  if (banksRes['isSuccess'] != true || banksRes['data'] is! List) {
    NotificationOverlayManager().showError(
      title: 'Lỗi',
      message: banksRes['message']?.toString() ?? 'Không tải được danh sách ngân hàng',
    );
    return false;
  }
  final banks = (banksRes['data'] as List)
      .map((e) => VietQRBank.fromJson(e as Map<String, dynamic>))
      .toList();

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => _PosBankAccountFormDialog(account: account, vietQRBanks: banks),
  );
  return ok == true;
}

class _PosBankAccountFormDialog extends StatefulWidget {
  const _PosBankAccountFormDialog({
    this.account,
    required this.vietQRBanks,
  });

  final BankAccount? account;
  final List<VietQRBank> vietQRBanks;

  @override
  State<_PosBankAccountFormDialog> createState() =>
      _PosBankAccountFormDialogState();
}

class _PosBankAccountFormDialogState extends State<_PosBankAccountFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _api = ApiService();
  final _accountNameCtrl = TextEditingController();
  final _accountNumberCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String? _selectedBankCode;
  bool _isDefault = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    if (a != null) {
      _accountNameCtrl.text = a.accountName;
      _accountNumberCtrl.text = a.accountNumber;
      _selectedBankCode = a.bankCode;
      _noteCtrl.text = a.note ?? '';
      _isDefault = a.isDefault;
    } else if (widget.vietQRBanks.isNotEmpty) {
      _selectedBankCode = widget.vietQRBanks.first.bin;
    }
  }

  @override
  void dispose() {
    _accountNameCtrl.dispose();
    _accountNumberCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  VietQRBank get _bank => widget.vietQRBanks.firstWhere(
        (b) => b.bin == _selectedBankCode,
        orElse: () => widget.vietQRBanks.first,
      );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _selectedBankCode == null) return;
    setState(() => _saving = true);
    final bank = _bank;
    final data = {
      'accountName': _accountNameCtrl.text.trim(),
      'accountNumber': _accountNumberCtrl.text.trim(),
      'bankCode': bank.bin,
      'bankName': bank.name,
      'bankShortName': bank.shortName,
      'bankLogoUrl': bank.logoUrl,
      'isDefault': _isDefault,
      if (_noteCtrl.text.trim().isNotEmpty) 'note': _noteCtrl.text.trim(),
    };

    final res = widget.account == null
        ? await _api.createBankAccount(data)
        : await _api.updateBankAccount(widget.account!.id, data);

    if (!mounted) return;
    setState(() => _saving = false);

    if (res['isSuccess'] == true) {
      Navigator.pop(context, true);
      NotificationOverlayManager().showSuccess(
        title: 'Thành công',
        message: widget.account == null ? 'Đã thêm tài khoản' : 'Đã cập nhật tài khoản',
      );
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không lưu được tài khoản',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);
    final title = widget.account == null ? 'Thêm tài khoản NH' : 'Sửa tài khoản NH';

    final form = Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            value: _selectedBankCode,
            decoration: InputDecoration(
              labelText: tr('Ngân hàng *'),
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.account_balance),
            ),
            items: widget.vietQRBanks
                .map(
                  (b) => DropdownMenuItem(
                    value: b.bin,
                    child: Row(
                      children: [
                        if (b.logoUrl.isNotEmpty)
                          CachedNetworkImage(
                            imageUrl: b.logoUrl,
                            width: 22,
                            height: 22,
                            errorWidget: (_, __, ___) =>
                                const Icon(Icons.account_balance, size: 18),
                          ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(tr(b.shortName), style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _selectedBankCode = v),
            validator: (v) => v == null ? 'Chọn ngân hàng' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _accountNameCtrl,
            decoration: InputDecoration(
              labelText: tr('Tên chủ tài khoản *'),
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.characters,
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'Nhập tên chủ tài khoản' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _accountNumberCtrl,
            decoration: InputDecoration(
              labelText: tr('Số tài khoản *'),
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Nhập số tài khoản';
              if (v.trim().length < 6) return 'Số tài khoản không hợp lệ';
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _noteCtrl,
            decoration: InputDecoration(
              labelText: tr('Ghi chú'),
              border: OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Tài khoản mặc định VietQR')),
            value: _isDefault,
            onChanged: (v) => setState(() => _isDefault = v),
          ),
        ],
      ),
    );

    if (isMobile) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(tr(title)),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context, false),
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: form,
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _kiotBlue),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(tr(widget.account == null ? 'Tạo tài khoản' : 'Lưu')),
              ),
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(tr(title)),
      content: SizedBox(width: 400, child: form),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Huỷ'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _kiotBlue),
          onPressed: _saving ? null : _save,
          child: Text(tr(widget.account == null ? 'Tạo' : 'Lưu')),
        ),
      ],
    );
  }
}
