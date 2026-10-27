import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/cash_transaction.dart';
import '../../services/api_service.dart';
import '../../widgets/cash_party_picker.dart';
import '../../widgets/notification_overlay.dart';
import 'pos_form_keyboard.dart';
import 'pos_numeric_keypad.dart';
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
    hidePosSoftKeyboard();
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
    return wrapPosFormDialog(
      context,
      Dialog(
      insetPadding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 420 ? 12 : 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 420 ? 16 : 20),
          child: _loadingCats
              ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
              // Nút ghim dưới đáy hộp, chỉ phần nhập liệu cuộn (trước: nút bị mép hộp cắt nửa trên V2s).
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
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
                    CashPartyPicker(
                      nameController: _contactCtrl,
                      phoneController: _phoneCtrl,
                      dense: true,
                      initialKind: (widget.initialContactName ?? '')
                              .trim()
                              .isNotEmpty
                          ? CashPartyKind.other
                          : CashPartyKind.customer,
                      enableDebtCollect:
                          widget.type == CashTransactionType.income,
                      onDebtCollected: (_) {
                        if (mounted) Navigator.pop(context, true);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      // Máy cảm ứng: bàn phím số của app (bàn phím số hệ thống lẫn ( ) # * = và che nút).
                      readOnly: posUsesAppKeypad,
                      onTap: posUsesAppKeypad ? () => posPickAmountInto(context, _amountCtrl) : null,
                      decoration: InputDecoration(
                        labelText: tr('Số tiền'),
                        hintText: tr('0'),
                        border: OutlineInputBorder(),
                        isDense: true,
                        suffixText: tr('đ'),
                      ),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    // Trước chỉ là dòng chữ «Tiền mặt» cố định dưới ô số tiền — trông như gợi ý, không đổi được.
                    Row(
                      children: [
                        for (final m in const [PaymentMethodType.cash, PaymentMethodType.bankTransfer]) ...[
                          if (m != PaymentMethodType.cash) const SizedBox(width: 8),
                          ChoiceChip(
                            label: Text(tr(m.label)),
                            selected: _paymentMethod == m,
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            selectedColor: PosTheme.kiotBlueLight,
                            labelStyle: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _paymentMethod == m ? _kiotBlue : PosTheme.textSecondary,
                            ),
                            onSelected: (_) => setState(() => _paymentMethod = m),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(builder: (context, c) {
                      final timeField = InkWell(
                        onTap: _pickDateTime,
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: tr('Thời gian'),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          child: Text(tr(dtFmt.format(_when)), maxLines: 1, softWrap: false),
                        ),
                      );
                      final categoryField = DropdownButtonFormField<String>(
                        value: _categoryId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: tr('Danh mục'),
                          // Store chưa có danh mục loại này: báo ngay, khỏi đợi bấm tạo mới biết lỗi.
                          errorText: _categories.isEmpty ? tr('Chưa có danh mục thu chi') : null,
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: _categories
                            .map((c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(tr(c.name), maxLines: 1, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) => setState(() => _categoryId = v),
                      );
                      // Màn hẹp: chung hàng thì ngày giờ bẻ 2 dòng, cao lệch ô Danh mục.
                      if (c.maxWidth < 420) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [timeField, const SizedBox(height: 12), categoryField],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: timeField),
                          const SizedBox(width: 12),
                          Expanded(child: categoryField),
                        ],
                      );
                    }),
                    const SizedBox(height: 12),
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
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(builder: (context, c) {
                      final cancel = OutlinedButton(
                        onPressed: _loading ? null : () => Navigator.pop(context),
                        child: Text(tr('Bỏ qua')),
                      );
                      final create = FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: _kiotBlue),
                        onPressed: _loading ? null : () => _save(),
                        child: _loading
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : Text(tr(_isIncome ? 'Tạo phiếu thu' : 'Tạo phiếu chi')),
                      );
                      final createPrint = FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: _kiotBlue),
                        onPressed: _loading ? null : () => _save(andPrint: true),
                        child: Text(tr(_isIncome ? 'Tạo phiếu thu & In' : 'Tạo phiếu chi & In')),
                      );
                      // Màn hẹp: 3 nút một hàng tràn khỏi hộp — xếp 2 hàng, nút rộng đều.
                      if (c.maxWidth < 460) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            createPrint,
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(child: cancel),
                                const SizedBox(width: 8),
                                Expanded(child: create),
                              ],
                            ),
                          ],
                        );
                      }
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          cancel,
                          const SizedBox(width: 8),
                          create,
                          const SizedBox(width: 8),
                          createPrint,
                        ],
                      );
                    }),
                  ],
                ),
        ),
      ),
    ),
    );
  }
}
