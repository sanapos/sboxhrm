import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_purchase.dart';
import '../../services/api_service.dart';
import '../notification_overlay.dart';
import 'pos_theme.dart';
import 'pos_vnd_thousands_formatter.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

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

/// Trả nợ NCC một lần cho nhiều phiếu nhập — máy chủ chia vào phiếu còn nợ cũ trước (FIFO).
/// Trả về true khi đã trả.
Future<bool?> showPosSupplierPayAllDialog(
  BuildContext context, {
  required String supplierId,
  required String supplierName,
  required double currentDebt,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _PosSupplierPayAllDialog(
        supplierId: supplierId, supplierName: supplierName, currentDebt: currentDebt),
  );
}

class _PosSupplierPayAllDialog extends StatefulWidget {
  const _PosSupplierPayAllDialog(
      {required this.supplierId, required this.supplierName, required this.currentDebt});

  final String supplierId;
  final String supplierName;
  final double currentDebt;

  @override
  State<_PosSupplierPayAllDialog> createState() => _PosSupplierPayAllDialogState();
}

class _PosSupplierPayAllDialogState extends State<_PosSupplierPayAllDialog> {
  final _api = ApiService();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  String _method = 'Tiền mặt';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.currentDebt > 0) _amountCtrl.text = _moneyFmt.format(widget.currentDebt);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
    if (amount <= 0) {
      NotificationOverlayManager().showError(title: 'Lỗi', message: tr('Nhập số tiền thanh toán'));
      return;
    }
    setState(() => _saving = true);
    final res = await _api.payPosSupplierAll(widget.supplierId,
        amount: amount, paymentMethod: _method, note: _noteCtrl.text);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      final paid = (res['data'] is Map ? (res['data'] as Map)['paid'] as List? : null) ?? const [];
      NotificationOverlayManager().showSuccess(
        title: 'Đã trả nợ NCC',
        message: tr('${_moneyFmt.format(amount)} đ — ${paid.length} phiếu nhập'),
      );
      Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(
        title: 'Không trả được',
        message: res['message']?.toString() ?? '',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Trả nợ nhà cung cấp')),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.supplierName,
                style: const TextStyle(fontSize: 13, color: PosTheme.textSecondary)),
            const SizedBox(height: 4),
            Text(tr('Đang nợ: ${_moneyFmt.format(widget.currentDebt)} đ'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(tr('Số tiền được trừ vào các phiếu nhập còn nợ, phiếu cũ trước.'),
                style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [PosVndThousandsFormatter()],
              decoration: InputDecoration(
                  labelText: tr('Số tiền'), border: const OutlineInputBorder(), isDense: true, suffixText: 'đ'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: InputDecoration(
                  labelText: tr('Hình thức'), border: const OutlineInputBorder(), isDense: true),
              items: _PosSupplierDebtPayDialogState._methods
                  .map((m) => DropdownMenuItem(value: m, child: Text(tr(m))))
                  .toList(),
              onChanged: (v) => setState(() => _method = v ?? 'Tiền mặt'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteCtrl,
              decoration: InputDecoration(
                  labelText: tr('Ghi chú'), border: const OutlineInputBorder(), isDense: true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: Text(tr('Hủy'))),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(tr('Trả nợ')),
        ),
      ],
    );
  }
}
