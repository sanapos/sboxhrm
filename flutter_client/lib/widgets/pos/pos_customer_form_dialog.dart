import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/pos_customer.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../notification_overlay.dart';
import 'pos_form_keyboard.dart';
import 'pos_theme.dart';
import 'vn_admin_address_fields.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';
const _blue = SboxColors.brand600;

/// Chức vụ người đại diện hay gặp trên hóa đơn / hợp đồng (mặc định Giám đốc).
const kPosLegalTitles = [
  'Giám đốc',
  'Tổng giám đốc',
  'Phó giám đốc',
  'Chủ tịch HĐQT',
  'Chủ tịch HĐTV',
  'Chủ tịch công ty',
  'Chủ doanh nghiệp',
  'Chủ hộ kinh doanh',
  'Giám đốc chi nhánh',
  'Trưởng văn phòng đại diện',
  'Kế toán trưởng',
];

class PosCustomerFormDialog extends StatefulWidget {
  const PosCustomerFormDialog({super.key, this.customer, this.initialQuery});

  final PosCustomer? customer;
  /// Chữ đang gõ ở ô tìm khách (không thấy khách): số → điền SĐT, chữ → điền tên.
  final String? initialQuery;

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
  /// Mở phần hóa đơn điện tử: khách đã có MST / công ty thì mở sẵn.
  late bool _showInvoice = (widget.customer?.taxCode ?? '').trim().isNotEmpty ||
      (widget.customer?.companyName ?? '').trim().isNotEmpty;
  late final TextEditingController _legalRepCtrl;
  late final TextEditingController _legalTitleCtrl;
  late final TextEditingController _noteCtrl;
  late final TextEditingController _deliveryCtrl;
  late final TextEditingController _limitCtrl;
  late final TextEditingController _termCtrl;
  DateTime? _birthday;
  bool _saving = false;
  bool _lookingTax = false;
  String? _taxLookupHint;
  bool _taxLookupOk = false;
  Timer? _taxDebounce;
  Timer? _dupDebounce;
  /// Khách đã có cùng SĐT (chặn tạo) / cùng MST (chỉ nhắc).
  Map<String, dynamic>? _dupPhone;
  List<Map<String, dynamic>> _dupTax = const [];
  /// Lỗi lưu hiện ngay trong hộp (thông báo nổi dễ bị bàn phím / hộp thoại che trên máy POS).
  String? _saveError;

  bool get _isEdit => widget.customer != null;

  bool get _canCredit {
    try {
      return Provider.of<PermissionProvider>(context, listen: false).canEdit('PosDebtAdjust');
    } catch (_) {
      return false;
    }
  }

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
    _legalRepCtrl = TextEditingController(text: c?.legalRepresentative ?? '');
    // Chức vụ mặc định «Giám đốc» (đa số hóa đơn / hợp đồng doanh nghiệp).
    _legalTitleCtrl = TextEditingController(text: (c?.legalTitle ?? '').trim().isEmpty ? 'Giám đốc' : c!.legalTitle);
    _noteCtrl = TextEditingController(text: c?.note ?? '');
    _deliveryCtrl = TextEditingController(text: c?.deliveryAddress ?? '');
    _limitCtrl = TextEditingController(
        text: (c?.debtLimit ?? 0) > 0 ? NumberFormat('#,##0', 'vi_VN').format(c!.debtLimit) : '');
    _termCtrl = TextEditingController(text: (c?.paymentTermDays ?? 0) > 0 ? '${c!.paymentTermDays}' : '');
    _birthday = c?.birthday;
    final q = (widget.initialQuery ?? '').trim();
    if (c == null && q.isNotEmpty) {
      final digits = q.replaceAll(RegExp(r'[\s.\-+]'), '');
      if (RegExp(r'^\d{8,12}$').hasMatch(digits)) {
        _phoneCtrl.text = q;
        WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleDupCheck());
      } else {
        _nameCtrl.text = q;
      }
    }
    hidePosSoftKeyboard();
  }

  @override
  void dispose() {
    _taxDebounce?.cancel();
    _dupDebounce?.cancel();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _provinceCtrl.dispose();
    _wardCtrl.dispose();
    _companyCtrl.dispose();
    _taxCtrl.dispose();
    _legalRepCtrl.dispose();
    _legalTitleCtrl.dispose();
    _noteCtrl.dispose();
    _deliveryCtrl.dispose();
    _limitCtrl.dispose();
    _termCtrl.dispose();
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
        'legalRepresentative': _legalRepCtrl.text.trim().isEmpty
            ? null
            : _legalRepCtrl.text.trim(),
        // Chức vụ chỉ có nghĩa khi có người đại diện / tên đơn vị (khách lẻ không lưu «Giám đốc» mặc định).
        'legalTitle': _legalTitleCtrl.text.trim().isEmpty ||
                (_legalRepCtrl.text.trim().isEmpty && _companyCtrl.text.trim().isEmpty)
            ? null
            : _legalTitleCtrl.text.trim(),
        'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        if (_birthday != null)
          'birthday': DateFormat('yyyy-MM-dd').format(_birthday!),
        'deliveryAddress':
            _deliveryCtrl.text.trim().isEmpty ? null : _deliveryCtrl.text.trim(),
        // Hạn mức / hạn thanh toán riêng (trống = theo thiết lập cửa hàng) — chỉ người có quyền điều chỉnh nợ.
        'setCredit': _canCredit,
        'debtLimit': double.tryParse(_limitCtrl.text.replaceAll('.', '').replaceAll(',', '').trim()),
        'paymentTermDays': int.tryParse(_termCtrl.text.trim()),
      };

  /// Ô còn thiếu / sai — hiện thành danh sách ngay trên nút Lưu (ô báo đỏ có thể nằm khuất dưới bàn phím).
  List<String> _missing() {
    final tax = _taxCtrl.text.trim();
    return [
      if (_nameCtrl.text.trim().isEmpty) 'Tên người mua',
      if (tax.isNotEmpty && !_looksLikeTaxCode(tax)) 'Mã số thuế (10 số, hoặc 10-3 chi nhánh)',
      if (tax.isNotEmpty && _companyCtrl.text.trim().isEmpty) 'Tên đơn vị (có MST)',
      if (tax.isNotEmpty && _addressCtrl.text.trim().isEmpty) 'Địa chỉ xuất hóa đơn (có MST)',
    ];
  }

  Future<void> _save() async {
    // Đóng bàn phím trước: trên máy POS bàn phím che nút Lưu / dòng báo lỗi.
    hidePosSoftKeyboard(alsoAfterMs: 0);
    final valid = _formKey.currentState!.validate();
    final missing = _missing();
    if (!valid || missing.isNotEmpty) {
      setState(() => _saveError = missing.isEmpty ? 'Kiểm tra lại các ô báo đỏ' : 'Cần nhập: ${missing.join(', ')}');
      return;
    }
    if (_dupPhone != null) {
      setState(() => _saveError =
          'Số điện thoại đã có ở khách «${_dupPhone!['name']}» — bấm «Chọn khách này» hoặc đổi số');
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final res = _isEdit
        ? await _api.updatePosCustomer(widget.customer!.id, _body())
        : await _api.createPosCustomer(_body());
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true && res['data'] is Map) {
      NotificationOverlayManager().showSuccess(
        title: _isEdit ? 'Đã cập nhật' : 'Đã tạo khách hàng',
        message: _nameCtrl.text.trim(),
      );
      Navigator.pop(context, Map<String, dynamic>.from(res['data'] as Map));
    } else {
      final msg = (res['message']?.toString() ?? '').trim();
      setState(() => _saveError = msg.isEmpty ? 'Không lưu được khách hàng (lỗi ${res['statusCode'] ?? 'mạng'})' : msg);
      NotificationOverlayManager().showError(title: 'Không lưu được', message: _saveError!);
    }
  }

  /// Kiểm tra trùng SĐT / MST khi đang nhập (chờ 0,5 giây sau lần gõ cuối).
  void _scheduleDupCheck() {
    _dupDebounce?.cancel();
    _dupDebounce = Timer(const Duration(milliseconds: 500), () => unawaited(_checkDuplicates()));
  }

  Future<void> _checkDuplicates() async {
    final phone = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    final tax = _taxCtrl.text.trim();
    if (phone.length < 8 && tax.length < 10) {
      if (_dupPhone != null || _dupTax.isNotEmpty) {
        setState(() {
          _dupPhone = null;
          _dupTax = const [];
        });
      }
      return;
    }
    final res = await _api.getPosCustomerDuplicates(
      phone: phone.length >= 8 ? phone : null,
      taxCode: tax.length >= 10 ? tax : null,
      exceptId: widget.customer?.id,
    );
    if (!mounted || res['isSuccess'] != true || res['data'] is! Map) return;
    final d = res['data'] as Map;
    setState(() {
      _dupPhone = d['phone'] is Map ? Map<String, dynamic>.from(d['phone'] as Map) : null;
      _dupTax = [
        for (final e in (d['taxCode'] as List? ?? const []))
          if (e is Map) Map<String, dynamic>.from(e),
      ];
      if (_dupPhone == null && _saveError != null && _saveError!.startsWith('Số điện thoại đã có')) _saveError = null;
    });
  }

  /// Hộp nhắc khách đã có (thêm mới: cho chọn luôn khách đó vào đơn).
  Widget _dupBox(Map<String, dynamic> c, String reason, {required bool blocking}) {
    final info = [c['customerCode'], c['phone'], c['companyName']]
        .where((e) => e != null && '$e'.trim().isNotEmpty)
        .join(' · ');
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
      decoration: BoxDecoration(
        color: blocking ? SboxColors.dangerSoft : SboxColors.warningSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(Icons.person_search_outlined,
            size: 18, color: blocking ? SboxColors.dangerText : SboxColors.warningText),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            tr('$reason «${c['name']}»${info.isEmpty ? '' : ' ($info)'}'),
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: blocking ? SboxColors.dangerText : SboxColors.warningText),
          ),
        ),
        if (!_isEdit)
          TextButton(
            onPressed: () => Navigator.pop(context, c),
            child: Text(tr('Chọn khách này')),
          ),
      ]),
    );
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
    _scheduleDupCheck();
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
    final rep = (data['representative'] ?? '').toString().trim();
    final foundCode = (data['taxCode'] ?? code).toString().trim();
    setState(() {
      if (foundCode.isNotEmpty) _taxCtrl.text = foundCode;
      if (name.isNotEmpty) {
        _companyCtrl.text = name;
        if (_nameCtrl.text.trim().isEmpty) _nameCtrl.text = name;
      }
      if (address.isNotEmpty) _addressCtrl.text = address;
      // Người đại diện (nguồn công khai, có thể chưa cập nhật) — chỉ điền khi ô đang trống.
      if (rep.isNotEmpty && _legalRepCtrl.text.trim().isEmpty) _legalRepCtrl.text = rep;
      if (_legalTitleCtrl.text.trim().isEmpty) _legalTitleCtrl.text = 'Giám đốc';
      _taxLookupOk = true;
      _taxLookupHint = name.isEmpty
          ? 'MST hợp lệ'
          : 'Đã điền: $name${rep.isEmpty ? '' : ' · đại diện: $rep (kiểm tra lại nếu đã đổi người)'}';
    });
    _scheduleDupCheck();
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
                              borderRadius: BorderRadius.circular(10),
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
                        // Khách lẻ (gym, quán…) không cần MST — thu gọn, bấm mới mở (trước mở ra là MST / công ty).
                        if (_showInvoice) ...[
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
                        for (final c in _dupTax)
                          _dupBox(c, 'MST đã có ở khách', blocking: false),
                        if (_taxLookupHint != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            tr(_taxLookupHint!),
                            style: TextStyle(
                              fontSize: 12,
                              color: _taxLookupOk
                                  ? SboxColors.success
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
                        ] else
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => setState(() => _showInvoice = true),
                              icon: const Icon(Icons.receipt_long_outlined, size: 18),
                              label: Text(tr('Thêm thông tin xuất hóa đơn (MST, công ty)')),
                            ),
                          ),
                        // Người đại diện / chức vụ chỉ dùng cho hóa đơn công ty.
                        if (_showInvoice) ...[
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: _legalRepCtrl,
                                decoration: PosTheme.inputDecoration(
                                    label: 'Người đại diện pháp luật'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: TextFormField(
                                controller: _legalTitleCtrl,
                                decoration: PosTheme.inputDecoration(label: 'Chức vụ').copyWith(
                                  suffixIcon: PopupMenuButton<String>(
                                    tooltip: tr('Chọn chức vụ'),
                                    icon: const Icon(Icons.arrow_drop_down),
                                    onSelected: (v) => setState(() => _legalTitleCtrl.text = v),
                                    itemBuilder: (_) => [
                                      for (final t in kPosLegalTitles)
                                        PopupMenuItem(value: t, child: Text(tr(t))),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ],
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
                              label: _showInvoice ? 'Địa chỉ xuất hóa đơn' : 'Địa chỉ'),
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
                                onChanged: (_) => _scheduleDupCheck(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _emailCtrl,
                                decoration:
                                    PosTheme.inputDecoration(label: _showInvoice ? 'Email HĐĐT' : 'Email'),
                                keyboardType: TextInputType.emailAddress,
                              ),
                            ),
                          ],
                        ),
                        if (_dupPhone != null)
                          _dupBox(_dupPhone!, 'Số điện thoại đã có ở khách', blocking: true),
                        const SizedBox(height: 20),
                        _sectionTitle('Thông tin thêm'),
                        InkWell(
                          onTap: _pickBirthday,
                          borderRadius: BorderRadius.circular(10),
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
                        VnAdminAddressFields(
                          provinceCtrl: _provinceCtrl,
                          wardCtrl: _wardCtrl,
                        ),
                        if (_canCredit) ...[
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                            child: TextFormField(
                              controller: _limitCtrl,
                              keyboardType: TextInputType.number,
                              decoration: PosTheme.inputDecoration(
                                  label: 'Hạn mức nợ (đ)', hint: 'Trống = theo cửa hàng'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _termCtrl,
                              keyboardType: TextInputType.number,
                              decoration: PosTheme.inputDecoration(
                                  label: 'Hạn thanh toán (ngày)', hint: 'Trống = theo cửa hàng'),
                            ),
                          ),
                        ]),
                        ],
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
              if (_saveError != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: SboxColors.dangerSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(tr(_saveError!),
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w600, color: SboxColors.dangerText)),
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
