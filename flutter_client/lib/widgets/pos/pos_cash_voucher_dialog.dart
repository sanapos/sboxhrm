import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/cash_transaction.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import 'pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';
import 'package:zkteco_flutter_client/l10n/app_ui_locale.dart';

const _kiotBlue = PosTheme.kiotBlue;

/// Lập phiếu thu / phiếu chi kiểu KiotViet từ màn POS.
Future<bool> showPosCashVoucherDialog(
  BuildContext context, {
  required CashTransactionType type,
  String? contactName,
  String? contactPhone,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PosCashVoucherDialog(
      type: type,
      initialContactName: contactName,
      initialContactPhone: contactPhone,
    ),
  );
  return result == true;
}

class _PosCashVoucherDialog extends StatefulWidget {
  const _PosCashVoucherDialog({
    required this.type,
    this.initialContactName,
    this.initialContactPhone,
  });

  final CashTransactionType type;
  final String? initialContactName;
  final String? initialContactPhone;

  @override
  State<_PosCashVoucherDialog> createState() => _PosCashVoucherDialogState();
}

class _PosCashVoucherDialogState extends State<_PosCashVoucherDialog> {
  final _api = ApiService();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  List<TransactionCategory> _categories = [];
  String? _categoryId;
  PaymentMethodType _paymentMethod = PaymentMethodType.cash;
  DateTime _when = DateTime.now();
  bool _loading = false;
  bool _loadingCats = true;

  bool get _isIncome => widget.type == CashTransactionType.income;
  String get _title => _isIncome ? 'Lập phiếu thu' : 'Lập phiếu chi';

  @override
  void initState() {
    super.initState();
    _contactCtrl.text = widget.initialContactName ?? '';
    _phoneCtrl.text = widget.initialContactPhone ?? '';
    _descCtrl.text = _isIncome ? 'Thu từ khách' : 'Chi cho NCC / chi phí';
    _loadCategories();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _contactCtrl.dispose();
    _phoneCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final res = await _api.getTransactionCategories();
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is List) {
      final cats = (res['data'] as List)
          .map((e) => TransactionCategory.fromJson(e as Map<String, dynamic>))
          .where((c) => c.type == widget.type && c.isActive)
          .toList();
      setState(() {
        _categories = cats;
        _categoryId = cats.isNotEmpty ? cats.first.id : null;
        _loadingCats = false;
      });
    } else {
      setState(() => _loadingCats = false);
    }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: appUiLocale(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_when));
    if (time == null) return;
    setState(() => _when = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  Future<void> _save({bool andPrint = false}) async {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
    if (amount <= 0) {
      NotificationOverlayManager()
          .showWarning(title: _title, message: tr('Nhập số tiền hợp lệ'));
      return;
    }
    if (_categoryId == null) {
      NotificationOverlayManager()
          .showWarning(title: _title, message: tr('Chưa có danh mục thu chi'));
      return;
    }

    setState(() => _loading = true);
    final res = await _api.createCashTransaction({
      'type': widget.type.value,
      'categoryId': _categoryId,
      'amount': amount,
      'transactionDate': _when.toIso8601String(),
      'description': _descCtrl.text.trim().isEmpty ? _title : _descCtrl.text.trim(),
      'paymentMethod': _paymentMethod.value,
      if (_contactCtrl.text.trim().isNotEmpty) 'contactName': _contactCtrl.text.trim(),
      if (_phoneCtrl.text.trim().isNotEmpty) 'contactPhone': _phoneCtrl.text.trim(),
      if (_noteCtrl.text.trim().isNotEmpty) 'internalNote': _noteCtrl.text.trim(),
      'isPaid': true,
    });
    if (!mounted) return;
    setState(() => _loading = false);

    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: _title,
        message: andPrint ? 'Đã tạo phiếu (in sau khi mở Thu chi)' : 'Đã tạo phiếu',
      );
      Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không tạo được phiếu',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dtFmt = DateFormat('dd/MM/yyyy HH:mm', 'vi_VN');
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _loadingCats
              ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(tr(_title), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        ),
                        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _contactCtrl,
                      decoration: InputDecoration(
                        labelText: tr(_isIncome ? 'Thu từ khách' : 'Chi cho'),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: tr('Số tiền'),
                        hintText: tr('0'),
                        border: OutlineInputBorder(),
                        isDense: true,
                        suffixText: tr('đ'),
                      ),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr(_paymentMethod == PaymentMethodType.cash ? 'Tiền mặt' : 'Chuyển khoản'),
                      style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: _pickDateTime,
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: tr('Thời gian'),
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              child: Text(tr(dtFmt.format(_when))),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _categoryId,
                            decoration: InputDecoration(
                              labelText: tr('Danh mục'),
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: _categories
                                .map((c) => DropdownMenuItem(value: c.id, child: Text(tr(c.name))))
                                .toList(),
                            onChanged: (v) => setState(() => _categoryId = v),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _noteCtrl,
                      decoration: InputDecoration(
                        labelText: tr('Ghi chú'),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: _loading ? null : () => Navigator.pop(context),
                          child: Text(tr('Bỏ qua')),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: _kiotBlue),
                          onPressed: _loading ? null : () => _save(),
                          child: _loading
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                              : Text(tr(_isIncome ? 'Tạo phiếu thu' : 'Tạo phiếu chi')),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: _kiotBlue),
                          onPressed: _loading ? null : () => _save(andPrint: true),
                          child: Text(tr(_isIncome ? 'Tạo phiếu thu & In' : 'Tạo phiếu chi & In')),
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
