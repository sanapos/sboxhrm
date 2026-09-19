import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/hrm.dart';
import '../../services/api_service.dart';
import '../../utils/tingee_supported_banks.dart';
import '../notification_overlay.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Cửa hàng tự gắn STK / mở SDK sau khi SuperAdmin đã tạo merchant.
class TingeeBankAttachPanel extends StatefulWidget {
  const TingeeBankAttachPanel({
    super.key,
    required this.hasMerchant,
    this.onVaApplied,
    this.onStatusChanged,
    this.initialBankBin,
    this.initialAccountNumber,
    this.initialAccountName,
    this.initialMobile,
    this.initialIdentity,
    this.linkedAccounts = const [],
  });

  final bool hasMerchant;
  final void Function(String va)? onVaApplied;
  final VoidCallback? onStatusChanged;
  final String? initialBankBin;
  final String? initialAccountNumber;
  final String? initialAccountName;
  final String? initialMobile;
  final String? initialIdentity;

  /// Danh sách STK đã gắn Tingee (từ get-va-paging server-side).
  final List<Map<String, dynamic>> linkedAccounts;

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
  String? _pendingLink;
  bool _isDeepLink = false;
  List<TingeeSupportedBank> _banks = kTingeeFallbackBanks;

  @override
  void initState() {
    super.initState();
    _applyInitial();
    loadTingeeSupportedBanks().then((banks) {
      if (!mounted || banks.isEmpty) return;
      setState(() {
        _banks = banks;
        if (!_banks.any((b) => b.bin == _bankBin)) {
          _bankBin = _banks.first.bin;
        }
      });
    });
  }

  @override
  void didUpdateWidget(covariant TingeeBankAttachPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialAccountNumber != widget.initialAccountNumber ||
        oldWidget.initialAccountName != widget.initialAccountName ||
        oldWidget.initialBankBin != widget.initialBankBin ||
        oldWidget.initialMobile != widget.initialMobile ||
        oldWidget.initialIdentity != widget.initialIdentity) {
      _applyInitial();
    }
  }

  void _applyInitial() {
    if ((widget.initialAccountName ?? '').isNotEmpty && _accNameCtrl.text.isEmpty) {
      _accNameCtrl.text = widget.initialAccountName!;
    }
    if ((widget.initialAccountNumber ?? '').isNotEmpty && _accNumberCtrl.text.isEmpty) {
      _accNumberCtrl.text = widget.initialAccountNumber!;
    }
    if ((widget.initialMobile ?? '').isNotEmpty && _mobileCtrl.text.isEmpty) {
      _mobileCtrl.text = widget.initialMobile!;
    }
    if ((widget.initialIdentity ?? '').isNotEmpty && _identityCtrl.text.isEmpty) {
      _identityCtrl.text = widget.initialIdentity!;
    }
    final bin = (widget.initialBankBin ?? '').trim();
    if (bin.isNotEmpty) _bankBin = bin;
  }

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
      final bankLinkUrl = (data['bankLinkUrl'] ?? '').toString();
      final deepLink = (data['deepLink'] ?? '').toString();
      final authorizeLink = (data['authorizeLink'] ?? '').toString();
      final link = bankLinkUrl.isNotEmpty
          ? bankLinkUrl
          : deepLink.isNotEmpty
              ? deepLink
              : authorizeLink;
      _pendingLink = link.isNotEmpty ? link : null;
      _isDeepLink = deepLink.isNotEmpty && bankLinkUrl.isEmpty;
      if (_pendingLink != null) {
        await launchUrl(Uri.parse(_pendingLink!), mode: LaunchMode.externalApplication);
      }
      NotificationOverlayManager().show(
        title: tr(title),
        message: _msg ?? '',
        type: NotificationType.success,
      );
      setState(() {});
      widget.onStatusChanged?.call();
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
        _linkedAccountsCard(),
        Text(tr('Gắn số tài khoản nhận CK'),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(
          tr('Chọn đúng ngân hàng và STK cửa hàng đang dùng. QR thanh toán báo về đúng tài khoản này.'),
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _banks.any((b) => b.bin == _bankBin) ? _bankBin : _banks.first.bin,
          decoration: InputDecoration(
            labelText: tr('Ngân hàng'),
            border: const OutlineInputBorder(),
          ),
          items: _banks
              .map((b) => DropdownMenuItem(
                  value: b.bin, child: Text(b.label)))
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
        if (_pendingLink != null) _pendingLinkCard(),
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

  Widget _linkedAccountsCard() {
    final list = widget.linkedAccounts;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: list.isEmpty ? Colors.orange.shade50 : Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(list.isEmpty ? Icons.warning_amber : Icons.verified,
                    size: 18,
                    color: list.isEmpty ? Colors.orange.shade800 : Colors.green.shade800),
                const SizedBox(width: 6),
                Text(
                  tr(list.isEmpty
                      ? 'Chưa có STK nào được Tingee xác nhận'
                      : 'STK đã gắn Tingee (${list.length})'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  tr('Nhập STK bên dưới rồi bấm "Gắn STK" → duyệt trong app ngân hàng để active.'),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              )
            else
              ...list.map((a) {
                final bank = (a['bankBin'] ?? '').toString();
                final num = (a['accountNumber'] ?? '').toString();
                final va = (a['vaAccountNumber'] ?? '').toString();
                final name = (a['accountName'] ?? '').toString();
                final status = (a['status'] ?? '').toString();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '• $bank · ${num.isEmpty ? va : num} · $name  [$status]',
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _pendingLinkCard() {
    final link = _pendingLink!;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_isDeepLink ? Icons.smartphone : Icons.open_in_new,
                    size: 18, color: Colors.blue.shade800),
                const SizedBox(width: 6),
                Text(
                  tr(_isDeepLink
                      ? 'Mở app ngân hàng để duyệt (deep link hết hạn ~5 phút)'
                      : 'Mở link liên kết ngân hàng'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SelectableText(link, style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse(link),
                      mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(tr('Mở link')),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: link));
                    NotificationOverlayManager().show(
                      title: tr('Đã copy'),
                      message: tr('Dán vào app hoặc gửi qua Zalo'),
                      type: NotificationType.info,
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: Text(tr('Copy')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
