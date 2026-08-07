import 'package:flutter/material.dart';

import '../../models/pos_purchase.dart';
import '../../services/api_service.dart';
import '../notification_overlay.dart';
import 'pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

const _blue = Color(0xFF2563EB);

/// Form thêm/sửa NCC kiểu KiotViet.
class PosSupplierFormDialog extends StatefulWidget {
  const PosSupplierFormDialog({
    super.key,
    this.supplier,
    this.groups = const [],
  });

  final PosSupplierFull? supplier;
  final List<PosSupplierGroup> groups;

  /// Mở dialog (tự load nhóm) — trả [PosSupplierFull] khi tạo/sửa thành công.
  static Future<PosSupplierFull?> open(
    BuildContext context, {
    PosSupplierFull? supplier,
  }) async {
    final api = ApiService();
    var groups = <PosSupplierGroup>[];
    final gRes = await api.getPosPurchaseSupplierGroups();
    if (gRes['isSuccess'] == true && gRes['data'] is List) {
      groups = (gRes['data'] as List)
          .map((e) => PosSupplierGroup.fromJson(
                Map<String, dynamic>.from(e as Map),
              ))
          .toList();
    }
    if (!context.mounted) return null;
    final raw = await showDialog<dynamic>(
      context: context,
      builder: (_) => PosSupplierFormDialog(
        supplier: supplier,
        groups: groups,
      ),
    );
    if (raw is! Map) return null;
    try {
      return PosSupplierFull.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      final id = (raw['id'] ?? raw['Id'])?.toString();
      final name = (raw['name'] ?? raw['Name'] ?? '').toString();
      if (id == null || id.isEmpty) return null;
      return PosSupplierFull(
        id: id,
        supplierCode: (raw['supplierCode'] ?? raw['SupplierCode'] ?? '').toString(),
        name: name,
      );
    }
  }

  @override
  State<PosSupplierFormDialog> createState() => _PosSupplierFormDialogState();
}

class _PosSupplierFormDialogState extends State<PosSupplierFormDialog> {
  final _api = ApiService();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _codeCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _provinceCtrl;
  late final TextEditingController _wardCtrl;
  late final TextEditingController _companyCtrl;
  late final TextEditingController _taxCtrl;
  late final TextEditingController _identityCtrl;
  late final TextEditingController _noteCtrl;
  String? _groupId;
  bool _saving = false;

  bool get _isEdit => widget.supplier != null;

  @override
  void initState() {
    super.initState();
    final s = widget.supplier;
    _nameCtrl = TextEditingController(text: tr(s?.name ?? ''));
    _codeCtrl = TextEditingController(text: tr(s?.supplierCode ?? ''));
    _phoneCtrl = TextEditingController(text: tr(s?.phone ?? ''));
    _emailCtrl = TextEditingController(text: tr(s?.email ?? ''));
    _addressCtrl = TextEditingController(text: tr(s?.address ?? ''));
    _provinceCtrl = TextEditingController(text: tr(s?.province ?? ''));
    _wardCtrl = TextEditingController(text: tr(s?.ward ?? ''));
    _companyCtrl = TextEditingController(text: tr(s?.companyName ?? ''));
    _taxCtrl = TextEditingController(text: tr(s?.taxCode ?? ''));
    _identityCtrl = TextEditingController(text: tr(s?.identityNo ?? ''));
    _noteCtrl = TextEditingController(text: tr(s?.note ?? ''));
    _groupId = s?.groupId;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _provinceCtrl.dispose();
    _wardCtrl.dispose();
    _companyCtrl.dispose();
    _taxCtrl.dispose();
    _identityCtrl.dispose();
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
        'groupId': _groupId,
        'companyName': _companyCtrl.text.trim().isEmpty ? null : _companyCtrl.text.trim(),
        'taxCode': _taxCtrl.text.trim().isEmpty ? null : _taxCtrl.text.trim(),
        'identityNo': _identityCtrl.text.trim().isEmpty ? null : _identityCtrl.text.trim(),
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      };

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final res = _isEdit
        ? await _api.updatePosPurchaseSupplier(widget.supplier!.id, _body())
        : await _api.createPosPurchaseSupplier(_body());
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: _isEdit ? 'Đã cập nhật' : 'Đã tạo NCC',
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
                  Text(tr(_isEdit ? 'Sửa nhà cung cấp' : 'Thêm nhà cung cấp'),
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
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: PosTheme.inputDecoration(label: 'Tên NCC *'),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Nhập tên NCC' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _codeCtrl,
                        readOnly: _isEdit,
                        decoration: PosTheme.inputDecoration(
                          label: 'Mã NCC',
                          hint: _isEdit ? null : 'Tự sinh khi lưu',
                        ),
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
                              keyboardType: TextInputType.emailAddress,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(tr('Địa chỉ'),
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 8),
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
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _groupId,
                        decoration: PosTheme.inputDecoration(label: 'Nhóm NCC'),
                        items: [
                          DropdownMenuItem(value: null, child: Text(tr('— Không chọn —'))),
                          ...widget.groups.map((g) =>
                              DropdownMenuItem(value: g.id, child: Text(tr(g.name)))),
                        ],
                        onChanged: (v) => setState(() => _groupId = v),
                      ),
                      const SizedBox(height: 16),
                      Text(tr('Thông tin thuế'),
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _companyCtrl,
                        decoration: PosTheme.inputDecoration(label: 'Tên công ty'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _taxCtrl,
                              decoration: PosTheme.inputDecoration(label: 'Mã số thuế'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _identityCtrl,
                              decoration: PosTheme.inputDecoration(label: 'CMND/CCCD'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _noteCtrl,
                        maxLines: 2,
                        decoration: PosTheme.inputDecoration(label: 'Ghi chú'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: PosTheme.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy'))),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(backgroundColor: _blue),
                    child: Text(tr(_saving ? 'Đang lưu…' : 'Lưu')),
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
