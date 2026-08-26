import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/hrm.dart';
import '../../services/api_service.dart';
import '../notification_overlay.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

const _tingeeBanks = <(String, String)>[
  ('970436', 'Vietcombank'),
  ('970415', 'VietinBank'),
  ('970418', 'BIDV'),
  ('970422', 'MB Bank'),
  ('970416', 'ACB'),
  ('970432', 'VPBank'),
  ('970403', 'Sacombank'),
  ('970441', 'VIB'),
  ('970423', 'TPBank'),
  ('970426', 'MSB'),
];

/// Cửa hàng tự gắn STK / mở SDK sau khi SuperAdmin đã tạo merchant.
class TingeeBankAttachPanel extends StatefulWidget {
  const TingeeBankAttachPanel({
    super.key,
    required this.hasMerchant,
    this.onVaApplied,
  });

  final bool hasMerchant;
  final void Function(String va)? onVaApplied;

  @override
  State<TingeeBankAttachPanel> createState() => _TingeeBankAttachPanelState();
}

class _TingeeBankAttachPanelState extends State<TingeeBankAttachPanel> {
  final _api = ApiService();
  final _accNameCtrl = TextEditingController();
  final _accNumberCtrl = TextEditingController();
  final _identityCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  String _bankBin = '970418';
  String _accountType = 'personal-account';
  bool _busy = false;
  String? _confirmId;
  String? _msg;

  @override
  void dispose() {
    _accNameCtrl.dispose();
    _accNumberCtrl.dispose();
    _identityCtrl.dispose();
    _mobileCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() fn, String title) async {
    setState(() => _busy = true);
    final res = await fn();
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['isSuccess'] == true && res['data'] is Map) {
      final data = Map<String, dynamic>.from(res['data'] as Map);
      _confirmId = (data['confirmId'] ?? '').toString();
      if (_confirmId!.isEmpty) _confirmId = null;
      _msg = (data['message'] ?? '').toString();
      final va = (data['tingeeVaAccountNumber'] ?? '').toString();
      if (va.isNotEmpty) widget.onVaApplied?.call(va);
      final url = (data['bankLinkUrl'] ?? data['authorizeLink'] ?? '').toString();
      if (url.startsWith('http')) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      NotificationOverlayManager().show(
        title: tr(title),
        message: _msg ?? '',
        type: NotificationType.success,
      );
      setState(() {});
    } else {
      NotificationOverlayManager().show(
        title: tr('Lỗi Tingee'),
        message: (res['message'] ?? '').toString(),
        type: NotificationType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.hasMerchant) {
      return Card(
        color: Colors.orange.shade50,
        child: ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(tr('Chưa có cửa hàng Tingee')),
          subtitle: Text(tr(
              'SuperAdmin vào Lượt CK Tingee → Tạo merchant + shop cho cửa hàng này.')),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Gắn số tài khoản nhận CK'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _bankBin,
          decoration: InputDecoration(
            labelText: tr('Ngân hàng'),
            border: const OutlineInputBorder(),
          ),
          items: _tingeeBanks
              .map((b) => DropdownMenuItem(
                  value: b.$1, child: Text('${b.$2} (${b.$1})')))
              .toList(),
          onChanged: (v) => setState(() => _bankBin = v ?? _bankBin),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _accountType,
          decoration: InputDecoration(
            labelText: tr('Loại TK'),
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem(
                value: 'personal-account', child: Text(tr('Cá nhân'))),
            DropdownMenuItem(
                value: 'business-household-account',
                child: Text(tr('Hộ kinh doanh'))),
            DropdownMenuItem(
                value: 'business-account', child: Text(tr('Doanh nghiệp'))),
          ],
          onChanged: (v) => setState(() => _accountType = v ?? _accountType),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _accNameCtrl,
          decoration: InputDecoration(
            labelText: tr('Họ tên chủ tài khoản'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _accNumberCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: tr('Số tài khoản'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _mobileCtrl,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: tr('SĐT ngân hàng'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _identityCtrl,
          decoration: InputDecoration(
            labelText: tr('CCCD / MST'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(
                        () => _api.posTingeeLinkBank(
                          bankBin: _bankBin,
                          accountNumber: _accNumberCtrl.text.trim(),
                          accountName: _accNameCtrl.text.trim(),
                          identity: _identityCtrl.text.trim().isEmpty
                              ? null
                              : _identityCtrl.text.trim(),
                          mobile: _mobileCtrl.text.trim().isEmpty
                              ? null
                              : _mobileCtrl.text.trim(),
                          accountType: _accountType,
                        ),
                        'Đã gửi gắn STK',
                      ),
              icon: const Icon(Icons.account_balance),
              label: Text(tr('Gắn STK')),
            ),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(
                        () => _api.posTingeeBankLinkSession(),
                        'Mở liên kết ngân hàng',
                      ),
              icon: const Icon(Icons.open_in_new),
              label: Text(tr('Mở SDK ngân hàng')),
            ),
          ],
        ),
        if (_confirmId != null) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _otpCtrl,
            decoration: InputDecoration(
              labelText: tr('OTP'),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _run(
                      () => _api.posTingeeConfirmVa(
                        bankBin: _bankBin,
                        confirmId: _confirmId!,
                        otpNumber: _otpCtrl.text.trim(),
                      ),
                      'Đã xác nhận',
                    ),
            icon: const Icon(Icons.verified),
            label: Text(tr('Xác nhận OTP')),
          ),
        ],
        if ((_msg ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_msg!, style: const TextStyle(fontSize: 13)),
          ),
        if (_busy) const Padding(
          padding: EdgeInsets.only(top: 8),
          child: LinearProgressIndicator(),
        ),
      ],
    );
  }
}
