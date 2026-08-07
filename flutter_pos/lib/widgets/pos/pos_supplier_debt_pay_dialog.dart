import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_purchase.dart';
import '../../services/api_service.dart';
import '../notification_overlay.dart';
import 'pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Thu công nợ NCC trên phiếu nhập đã hoàn tất.
Future<bool?> showPosSupplierDebtPayDialog(
  BuildContext context, {
  required PosPurchaseReceipt receipt,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => PosSupplierDebtPayDialog(receipt: receipt),
  );
}

class PosSupplierDebtPayDialog extends StatefulWidget {
  const PosSupplierDebtPayDialog({super.key, required this.receipt});

  final PosPurchaseReceipt receipt;

  @override
  State<PosSupplierDebtPayDialog> createState() =>
      _PosSupplierDebtPayDialogState();
}

class _PosSupplierDebtPayDialogState extends State<PosSupplierDebtPayDialog> {
  final _api = ApiService();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  String _method = 'Tiền mặt';
  bool _saving = false;

  static const _methods = ['Tiền mặt', 'Chuyển khoản', 'Thẻ', 'Khác'];

  double get _balanceDue {
    if (widget.receipt.balanceDue > 0) return widget.receipt.balanceDue;
    final gt = widget.receipt.grandTotal != 0
        ? widget.receipt.grandTotal
        : widget.receipt.totalCost +
            widget.receipt.totalVat -
            widget.receipt.discountAmount;
    return (gt - widget.receipt.paidAmount).clamp(0, double.infinity);
  }

  @override
  void initState() {
    super.initState();
    if (_balanceDue > 0) {
      _amountCtrl.text = _moneyFmt.format(_balanceDue);
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
          .showError(title: 'Lỗi', message: tr('Nhập số tiền thanh toán'));
      return;
    }
    if (amount > _balanceDue + 0.001) {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: tr('Vượt công nợ phiếu (${_moneyFmt.format(_balanceDue)} đ)'),
      );
      return;
    }
    setState(() => _saving = true);
    final res = await _api.createPosPurchaseReceiptPayment(widget.receipt.id, {
      'amount': amount,
      'paymentMethod': _method,
      'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      'paidAt': DateTime.now().toUtc().toIso8601String(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: 'Đã thanh toán NCC',
        message: tr('${_moneyFmt.format(amount)} đ — ${widget.receipt.receiptNo}'),
      );
      Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không thanh toán được',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Thanh toán công nợ NCC')),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(tr('${tr('Phiếu ')}${widget.receipt.receiptNo}'
              '${widget.receipt.supplierName != null ? ' · ${widget.receipt.supplierName}' : ''}'),
              style: const TextStyle(fontSize: 13, color: PosTheme.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(tr('Còn nợ: ${_moneyFmt.format(_balanceDue)} đ'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr('Số tiền'),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _method,
              decoration: InputDecoration(
                labelText: tr('Hình thức'),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _methods
                  .map((m) => DropdownMenuItem(value: m, child: Text(tr(m))))
                  .toList(),
              onChanged: (v) => setState(() => _method = v ?? 'Tiền mặt'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteCtrl,
              decoration: InputDecoration(
                labelText: tr('Ghi chú'),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(tr('Hủy')),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(tr('Thanh toán')),
        ),
      ],
    );
  }
}
