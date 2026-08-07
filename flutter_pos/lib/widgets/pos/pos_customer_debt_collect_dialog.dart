import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_customer.dart';
import '../../services/api_service.dart';
import '../notification_overlay.dart';
import 'pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Thu nợ công nợ khách hàng POS.
Future<bool?> showPosCustomerDebtCollectDialog(
  BuildContext context, {
  required PosCustomer customer,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => PosCustomerDebtCollectDialog(customer: customer),
  );
}

class PosCustomerDebtCollectDialog extends StatefulWidget {
  const PosCustomerDebtCollectDialog({super.key, required this.customer});

  final PosCustomer customer;

  @override
  State<PosCustomerDebtCollectDialog> createState() =>
      _PosCustomerDebtCollectDialogState();
}

class _PosCustomerDebtCollectDialogState extends State<PosCustomerDebtCollectDialog> {
  final _api = ApiService();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  String _method = 'Tiền mặt';
  bool _saving = false;

  static const _methods = ['Tiền mặt', 'Chuyển khoản', 'Thẻ', 'Khác'];

  @override
  void initState() {
    super.initState();
    if (widget.customer.currentDebt > 0) {
      _amountCtrl.text = _moneyFmt.format(widget.customer.currentDebt);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  double _parseAmount() {
    final cleaned = _amountCtrl.text.replaceAll(RegExp(r'[^\d]'), '');
    if (cleaned.isEmpty) return 0;
    return double.tryParse(cleaned) ?? 0;
  }

  Future<void> _submit() async {
    final amount = _parseAmount();
    if (amount <= 0) {
      NotificationOverlayManager()
          .showError(title: 'Lỗi', message: tr('Nhập số tiền thu nợ'));
      return;
    }
    setState(() => _saving = true);
    final res = await _api.createPosCustomerPayment(widget.customer.id, {
      'amount': amount,
      'paymentMethod': _method,
      'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      'paidAt': DateTime.now().toUtc().toIso8601String(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: 'Thu nợ thành công',
        message: tr('${_moneyFmt.format(amount)} đ — ${widget.customer.name}'),
      );
      Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Thu nợ thất bại',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.customer;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr('Thu nợ — ${c.name}'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(tr('Nợ hiện tại: ${_moneyFmt.format(c.currentDebt)} đ'),
                style: const TextStyle(color: PosTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: PosTheme.inputDecoration(label: 'Số tiền thu *'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _method,
                decoration: PosTheme.inputDecoration(label: 'Hình thức'),
                items: _methods
                    .map((m) => DropdownMenuItem(value: m, child: Text(tr(m))))
                    .toList(),
                onChanged: _saving ? null : (v) => setState(() => _method = v ?? _method),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                decoration: PosTheme.inputDecoration(label: 'Ghi chú'),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Huỷ'))),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(tr('Xác nhận thu')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
