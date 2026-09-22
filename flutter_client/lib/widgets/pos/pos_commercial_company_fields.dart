import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';

/// Khối thông tin pháp lý công ty — in trên báo giá / hợp đồng A4.
class PosCommercialCompanyFields extends StatefulWidget {
  const PosCommercialCompanyFields({
    super.key,
    required this.company,
    required this.tax,
    required this.address,
    required this.phone,
    required this.email,
    required this.bankNo,
    required this.bankName,
    required this.bankHolder,
    required this.rep,
    required this.title,
    this.enabled = true,
  });

  final TextEditingController company;
  final TextEditingController tax;
  final TextEditingController address;
  final TextEditingController phone;
  final TextEditingController email;
  final TextEditingController bankNo;
  final TextEditingController bankName;
  final TextEditingController bankHolder;
  final TextEditingController rep;
  final TextEditingController title;
  final bool enabled;

  @override
  State<PosCommercialCompanyFields> createState() =>
      _PosCommercialCompanyFieldsState();
}

class _PosCommercialCompanyFieldsState
    extends State<PosCommercialCompanyFields> {
  final _api = ApiService();
  Timer? _taxDebounce;
  bool _lookingTax = false;
  String? _taxLookupHint;
  bool _taxLookupOk = false;

  @override
  void dispose() {
    _taxDebounce?.cancel();
    super.dispose();
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: tr(label),
        border: const OutlineInputBorder(),
      );

  bool _looksLikeTaxCode(String s) {
    final t = s.replaceAll(RegExp(r'[\s.]'), '');
    return RegExp(r'^\d{10}(-\d{3})?$').hasMatch(t) ||
        RegExp(r'^\d{13}$').hasMatch(t);
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

  Future<void> _lookupTax() async {
    final code = widget.tax.text.trim();
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
    var res = await _api.lookupPosCommercialTax(code);
    if (res['isSuccess'] != true) {
      res = await _api.lookupPosCustomerTax(code);
    }
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
      if (foundCode.isNotEmpty) widget.tax.text = foundCode;
      if (name.isNotEmpty) {
        widget.company.text = name;
        if (widget.bankHolder.text.trim().isEmpty) {
          widget.bankHolder.text = name;
        }
      }
      if (address.isNotEmpty) widget.address.text = address;
      _taxLookupOk = true;
      _taxLookupHint = name.isEmpty
          ? 'MST hợp lệ — điền TK ngân hàng và người đại diện'
          : 'Đã điền tên và địa chỉ. TK ngân hàng / người đại diện nhập tay.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr('Thông tin công ty (báo giá / hợp đồng)'),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          tr('Tên cửa hàng phía trên dùng hóa đơn bán. Các trường này in trên báo giá, hợp đồng — tra cứu MST để điền tên và địa chỉ.'),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: widget.tax,
                enabled: enabled,
                keyboardType: TextInputType.number,
                decoration: _dec('Mã số thuế (MST)'),
                onChanged: enabled ? _onTaxChanged : null,
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: FilledButton.tonal(
                onPressed: (!enabled || _lookingTax) ? null : _lookupTax,
                child: _lookingTax
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
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
        TextField(
          controller: widget.company,
          enabled: enabled,
          textCapitalization: TextCapitalization.characters,
          decoration: _dec('Tên công ty'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.address,
          enabled: enabled,
          maxLines: 2,
          decoration: _dec('Địa chỉ công ty'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.rep,
          enabled: enabled,
          textCapitalization: TextCapitalization.words,
          decoration: _dec('Người đại diện'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.title,
          enabled: enabled,
          decoration: _dec('Chức vụ'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.bankNo,
          enabled: enabled,
          keyboardType: TextInputType.number,
          decoration: _dec('Số tài khoản ngân hàng'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.bankName,
          enabled: enabled,
          decoration: _dec('Ngân hàng'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.bankHolder,
          enabled: enabled,
          decoration: _dec('Chủ tài khoản'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.phone,
          enabled: enabled,
          keyboardType: TextInputType.phone,
          decoration: _dec('Điện thoại công ty'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: widget.email,
          enabled: enabled,
          keyboardType: TextInputType.emailAddress,
          decoration: _dec('Email công ty'),
        ),
      ],
    );
  }
}
