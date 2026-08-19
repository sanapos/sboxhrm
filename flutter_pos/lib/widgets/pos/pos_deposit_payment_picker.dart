import 'package:flutter/material.dart';

import '../../models/cash_transaction.dart';
import '../../services/api_service.dart';
import 'pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Hình thức thu cọc — TM / CK / VietQR (+ TKNH).
class PosDepositPayChoice {
  const PosDepositPayChoice({
    this.methodLabel = 'Tiền mặt',
    this.bankAccountId,
  });

  final String methodLabel;
  final String? bankAccountId;

  bool get isCash => methodLabel == 'Tiền mặt';

  Map<String, dynamic> toCollectBody() => {
        'paymentMethod': methodLabel,
        if (bankAccountId != null) 'bankAccountId': bankAccountId,
      };

  Map<String, dynamic> toCreateBody() => {
        'depositPaymentMethod': methodLabel,
        if (bankAccountId != null) 'depositBankAccountId': bankAccountId,
      };
}

class PosDepositPaymentPicker extends StatefulWidget {
  const PosDepositPaymentPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.accounts,
    this.api,
    this.compact = false,
  });

  final PosDepositPayChoice value;
  final ValueChanged<PosDepositPayChoice> onChanged;
  final List<BankAccount>? accounts;
  final ApiService? api;
  final bool compact;

  @override
  State<PosDepositPaymentPicker> createState() => _PosDepositPaymentPickerState();
}

class _PosDepositPaymentPickerState extends State<PosDepositPaymentPicker> {
  List<BankAccount> _accounts = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _accounts = widget.accounts ?? const [];
    if (widget.accounts == null) {
      unawaitedLoad();
    }
  }

  @override
  void didUpdateWidget(covariant PosDepositPaymentPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.accounts != null) _accounts = widget.accounts!;
  }

  Future<void> unawaitedLoad() async {
    setState(() => _loading = true);
    final api = widget.api ?? ApiService();
    var res = await api.getPosBankAccounts();
    if (res['isSuccess'] != true) {
      res = await api.getBankAccounts();
    }
    if (!mounted) return;
    final next = <BankAccount>[];
    final raw = res['data'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          final a = BankAccount.fromJson(Map<String, dynamic>.from(e));
          if (a.isActive) next.add(a);
        }
      }
    }
    setState(() {
      _accounts = next;
      _loading = false;
    });
  }

  BankAccount? get _selected {
    final id = widget.value.bankAccountId;
    if (id == null || id.isEmpty) {
      for (final a in _accounts) {
        if (a.isDefault) return a;
      }
      return _accounts.isEmpty ? null : _accounts.first;
    }
    for (final a in _accounts) {
      if (a.id == id) return a;
    }
    return _accounts.isEmpty ? null : _accounts.first;
  }

  void _setMethod(String method) {
    String? bankId;
    if (method != 'Tiền mặt') {
      bankId = _selected?.id;
    }
    widget.onChanged(PosDepositPayChoice(
      methodLabel: method,
      bankAccountId: bankId,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    final methods = <String>['Tiền mặt'];
    if (_accounts.isNotEmpty) {
      methods.addAll(['Chuyển khoản', 'VietQR']);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr('Hình thức thu cọc'),
          style: TextStyle(
            fontSize: widget.compact ? 12 : 13,
            fontWeight: FontWeight.w600,
            color: PosTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in methods)
              ChoiceChip(
                label: Text(tr(m)),
                selected: v.methodLabel == m,
                onSelected: (_) => _setMethod(m),
              ),
            if (_loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        if (!v.isCash && _accounts.isNotEmpty) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _selected?.id,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: tr('Tài khoản nhận'),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              for (final a in _accounts)
                DropdownMenuItem(
                  value: a.id,
                  child: Text(
                    '${a.bankShortName ?? a.bankName} · ${a.accountNumber}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (id) {
              if (id == null) return;
              widget.onChanged(PosDepositPayChoice(
                methodLabel: v.methodLabel,
                bankAccountId: id,
              ));
            },
          ),
        ],
      ],
    );
  }
}

Future<({double amount, PosDepositPayChoice pay})?> showPosCollectDepositDialog({
  required BuildContext context,
  required String title,
  String? initialAmount,
}) async {
  final amountCtrl = TextEditingController(text: initialAmount ?? '');
  var pay = const PosDepositPayChoice();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(tr(title)),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: tr('Số tiền cọc'),
                  border: const OutlineInputBorder(),
                  suffixText: 'đ',
                ),
              ),
              const SizedBox(height: 12),
              PosDepositPaymentPicker(
                value: pay,
                onChanged: (v) => setLocal(() => pay = v),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Huỷ')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Thu cọc')),
          ),
        ],
      ),
    ),
  );
  final amount = double.tryParse(amountCtrl.text.trim().replaceAll(',', '')) ?? 0;
  amountCtrl.dispose();
  if (ok != true || amount <= 0) return null;
  return (amount: amount, pay: pay);
}
