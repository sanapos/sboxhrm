import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_customer.dart';
import '../../services/api_service.dart';
import '../notification_overlay.dart';
import 'pos_form_keyboard.dart';
import 'pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

const _blue = Color(0xFF2563EB);

class PosCustomerFormDialog extends StatefulWidget {
  const PosCustomerFormDialog({super.key, this.customer});

  final PosCustomer? customer;

  @override
  State<PosCustomerFormDialog> createState() => _PosCustomerFormDialogState();
}

class _PosCustomerFormDialogState extends State<PosCustomerFormDialog> {
  final _api = ApiService();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _provinceCtrl;
  late final TextEditingController _wardCtrl;
  late final TextEditingController _companyCtrl;
  late final TextEditingController _taxCtrl;
  late final TextEditingController _noteCtrl;
  late final TextEditingController _deliveryCtrl;
  DateTime? _birthday;
  bool _saving = false;
  bool _lookingTax = false;
  String? _taxLookupHint;
  bool _taxLookupOk = false;
  Timer? _taxDebounce;

  bool get _isEdit => widget.customer != null;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _nameCtrl = TextEditingController(text: c?.name ?? '');
    _phoneCtrl = TextEditingController(text: c?.phone ?? '');
    _emailCtrl = TextEditingController(text: c?.email ?? '');
    _addressCtrl = TextEditingController(text: c?.address ?? '');
    _provinceCtrl = TextEditingController(text: c?.province ?? '');
    _wardCtrl = TextEditingController(text: c?.ward ?? '');
    _companyCtrl = TextEditingController(text: c?.companyName ?? '');
    _taxCtrl = TextEditingController(text: c?.taxCode ?? '');
    _noteCtrl = TextEditingController(text: c?.note ?? '');
    _deliveryCtrl = TextEditingController(text: c?.deliveryAddress ?? '');
    _birthday = c?.birthday;
    hidePosSoftKeyboard();
  }

  @override
  void dispose() {
    _taxDebounce?.cancel();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _provinceCtrl.dispose();
    _wardCtrl.dispose();
    _companyCtrl.dispose();
    _taxCtrl.dispose();
    _noteCtrl.dispose();
    _deliveryCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _body() => {
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'address':
            _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        'province':
            _provinceCtrl.text.trim().isEmpty ? null : _provinceCtrl.text.trim(),
        'ward': _wardCtrl.text.trim().isEmpty ? null : _wardCtrl.text.trim(),
        'companyName':
            _companyCtrl.text.trim().isEmpty ? null : _companyCtrl.text.trim(),
        'taxCode': _taxCtrl.text.trim().isEmpty ? null : _taxCtrl.text.trim(),
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        if (_birthday != null)
          'birthday': DateFormat('yyyy-MM-dd').format(_birthday!),
        'deliveryAddress':
            _deliveryCtrl.text.trim().isEmpty ? null : _deliveryCtrl.text.trim(),
      };

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final res = _isEdit
        ? await _api.updatePosCustomer(widget.customer!.id, _body())
        : await _api.createPosCustomer(_body());
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: _isEdit ? 'Đã cập nhật' : 'Đã tạo khách hàng',
        message: _nameCtrl.text.trim(),
      );
      Navigator.pop(context, res['data']);
    } else {
      NotificationOverlayManager()
          .showError(title: 'Lỗi', message: res['message']?.toString() ?? '');
    }
  }

  void _onTaxChanged(String raw) {
    _taxDebounce?.cancel();
    final code = raw.trim();
    if (!_looksLikeTaxCode(code)) {
      if (_taxLookupHint != null) {
        setState(() {
          _taxLookupHint = null;
          _taxLookupOk = false;
        });
      }
      return;
    }
    _taxDebounce = Timer(const Duration(milliseconds: 650), () {
      unawaited(_lookupTax());
    });
  }

  bool _looksLikeTaxCode(String s) {
    final t = s.replaceAll(RegExp(r'[\s.]'), '');
    return RegExp(r'^\d{10}(-\d{3})?$').hasMatch(t) ||
        RegExp(r'^\d{13}$').hasMatch(t);
  }

  Future<void> _lookupTax() async {
    final code = _taxCtrl.text.trim();
    if (!_looksLikeTaxCode(code)) {
      setState(() {
        _taxLookupHint = 'MST gồm 10 số, hoặc 10-3 nếu chi nhánh';
        _taxLookupOk = false;
      });
      return;
    }
    setState(() {
      _lookingTax = true;
      _taxLookupHint = 'Đang tra cứu MST…';
      _taxLookupOk = false;
    });
    final res = await _api.lookupPosCustomerTax(code);
    if (!mounted) return;
    setState(() => _lookingTax = false);
    if (res['isSuccess'] != true || res['data'] is! Map) {
      setState(() {
        _taxLookupHint =
            res['message']?.toString() ?? 'Không tìm thấy mã số thuế';
        _taxLookupOk = false;
      });
      return;
    }
    final data = Map<String, dynamic>.from(res['data'] as Map);
    final name = (data['name'] ?? '').toString().trim();
    final address = (data['address'] ?? '').toString().trim();
    final foundCode = (data['taxCode'] ?? code).toString().trim();
    setState(() {
      if (foundCode.isNotEmpty) _taxCtrl.text = foundCode;
      if (name.isNotEmpty) {
        _companyCtrl.text = name;
        if (_nameCtrl.text.trim().isEmpty) _nameCtrl.text = name;
      }
      if (address.isNotEmpty) _addressCtrl.text = address;
      _taxLookupOk = true;
      _taxLookupHint = name.isEmpty
          ? 'MST hợp lệ'
          : 'Đã điền: $name';
    });
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final initial = _birthday ?? DateTime(now.year - 25, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1920),
      lastDate: now,
      locale: const Locale('vi', 'VN'),
    );
    if (picked == null || !mounted) return;
    setState(() => _birthday = picked);
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          tr(text),
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _blue,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return wrapPosFormDialog(
      context,
      Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: PosTheme.border)),
                ),
                child: Row(
                  children: [
                    Text(
                      tr(_isEdit ? 'Sửa khách hàng' : 'Thêm khách hàng'),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_isEdit && widget.customer != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: PosTheme.kiotBlueLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(tr('Công nợ'),
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: PosTheme.textSecondary)),
                                      Text(
                                        tr(NumberFormat('#,##0', 'vi_VN')
                                            .format(
                                                widget.customer!.currentDebt)),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(tr('Điểm tích luỹ'),
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: PosTheme.textSecondary)),
                                      Text(
                                        tr(NumberFormat('#,##0', 'vi_VN')
                                            .format(
                                                widget.customer!.pointBalance)),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        _sectionTitle('Hóa đơn điện tử'),
                        Text(
                          tr('Điền MST để xuất HĐ đúng tên đơn vị / địa chỉ trên hóa đơn.'),
                          style: const TextStyle(
                              fontSize: 11, color: PosTheme.textSecondary),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _taxCtrl,
                                decoration: PosTheme.inputDecoration(
                                    label: 'Mã số thuế'),
                                keyboardType: TextInputType.number,
                                onChanged: _onTaxChanged,
                                validator: (v) {
                                  final t = (v ?? '').trim();
                                  if (t.isEmpty) return null;
                                  if (!_looksLikeTaxCode(t)) {
                                    return 'MST gồm 10 số, hoặc 10-3 chi nhánh';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: FilledButton.tonal(
                                onPressed: _lookingTax ? null : _lookupTax,
                                child: _lookingTax
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : Text(tr('Tra cứu')),
                              ),
                            ),
                          ],
                        ),
                        if (_taxLookupHint != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            tr(_taxLookupHint!),
                            style: TextStyle(
                              fontSize: 12,
                              color: _taxLookupOk
                                  ? const Color(0xFF059669)
                                  : Colors.orange.shade800,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _companyCtrl,
                          decoration: PosTheme.inputDecoration(
                              label: 'Tên đơn vị / công ty'),
                          validator: (v) {
                            if (_taxCtrl.text.trim().isEmpty) return null;
                            if ((v ?? '').trim().isEmpty) {
                              return 'Nhập tên đơn vị trên hóa đơn';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _nameCtrl,
                          decoration: PosTheme.inputDecoration(
                              label: 'Tên người mua *'),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Nhập tên người mua'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _addressCtrl,
                          decoration: PosTheme.inputDecoration(
                              label: 'Địa chỉ xuất hóa đơn'),
                          maxLines: 2,
                          validator: (v) {
                            if (_taxCtrl.text.trim().isEmpty) return null;
                            if ((v ?? '').trim().isEmpty) {
                              return 'Nhập địa chỉ xuất hóa đơn';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _phoneCtrl,
                                decoration: PosTheme.inputDecoration(
                                    label: 'Số điện thoại'),
                                keyboardType: TextInputType.phone,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _emailCtrl,
                                decoration:
                                    PosTheme.inputDecoration(label: 'Email HĐĐT'),
                                keyboardType: TextInputType.emailAddress,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        _sectionTitle('Thông tin thêm'),
                        InkWell(
                          onTap: _pickBirthday,
                          borderRadius: BorderRadius.circular(8),
                          child: InputDecorator(
                            decoration: PosTheme.inputDecoration(
                                label: 'Sinh nhật'),
                            child: Text(
                              tr(_birthday == null
                                  ? 'Chọn ngày'
                                  : DateFormat('dd/MM/yyyy').format(_birthday!)),
                              style: TextStyle(
                                color: _birthday == null
                                    ? PosTheme.textSecondary
                                    : PosTheme.textPrimary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _deliveryCtrl,
                          decoration: PosTheme.inputDecoration(
                              label: 'Địa chỉ nhận hàng'),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _provinceCtrl,
                                decoration: PosTheme.inputDecoration(
                                    label: 'Tỉnh/TP'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _wardCtrl,
                                decoration: PosTheme.inputDecoration(
                                    label: 'Phường/Xã'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _noteCtrl,
                          decoration: PosTheme.inputDecoration(label: 'Ghi chú'),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(tr('Hủy'))),
                    const Spacer(),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(backgroundColor: _blue),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(tr(_isEdit ? 'Lưu' : 'Tạo mới')),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
