import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_customer.dart';import '../../services/api_service.dart';
import '../notification_overlay.dart';
import 'pos_theme.dart';

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
  bool _saving = false;

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
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _provinceCtrl.dispose();
    _wardCtrl.dispose();
    _companyCtrl.dispose();
    _taxCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _body() => {
        'name': _nameCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'email': _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
        'address': _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        'province': _provinceCtrl.text.trim().isEmpty ? null : _provinceCtrl.text.trim(),
        'ward': _wardCtrl.text.trim().isEmpty ? null : _wardCtrl.text.trim(),
        'companyName': _companyCtrl.text.trim().isEmpty ? null : _companyCtrl.text.trim(),
        'taxCode': _taxCtrl.text.trim().isEmpty ? null : _taxCtrl.text.trim(),
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
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
                  Text(_isEdit ? 'Sửa khách hàng' : 'Thêm khách hàng',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Công nợ',
                                        style: TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
                                    Text(
                                      NumberFormat('#,##0', 'vi_VN')
                                          .format(widget.customer!.currentDebt),
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
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Điểm tích luỹ',
                                        style: TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
                                    Text(
                                      NumberFormat('#,##0', 'vi_VN')
                                          .format(widget.customer!.pointBalance),
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: PosTheme.inputDecoration(label: 'Tên khách hàng *'),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Nhập tên khách hàng' : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _phoneCtrl,
                              decoration: PosTheme.inputDecoration(label: 'Điện thoại'),
                              keyboardType: TextInputType.phone,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _emailCtrl,
                              decoration: PosTheme.inputDecoration(label: 'Email'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _addressCtrl,
                        decoration: PosTheme.inputDecoration(label: 'Địa chỉ'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _provinceCtrl,
                              decoration: PosTheme.inputDecoration(label: 'Tỉnh/TP'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _wardCtrl,
                              decoration: PosTheme.inputDecoration(label: 'Phường/Xã'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _companyCtrl,
                        decoration: PosTheme.inputDecoration(label: 'Công ty'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _taxCtrl,
                        decoration: PosTheme.inputDecoration(label: 'Mã số thuế'),
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
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(backgroundColor: _blue),
                    child: _saving
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(_isEdit ? 'Lưu' : 'Tạo mới'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
