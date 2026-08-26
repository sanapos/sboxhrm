import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../models/hrm.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';

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

/// SuperAdmin — tạo merchant/shop Tingee cho cửa hàng và gắn STK.
class TingeeStoreSetupCard extends StatefulWidget {
  const TingeeStoreSetupCard({super.key, required this.stores});

  final List<Map<String, dynamic>> stores;

  @override
  State<TingeeStoreSetupCard> createState() => _TingeeStoreSetupCardState();
}

class _TingeeStoreSetupCardState extends State<TingeeStoreSetupCard> {
  final _api = ApiService();
  final _phoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _accNameCtrl = TextEditingController();
  final _accNumberCtrl = TextEditingController();
  final _identityCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();

  String? _storeId;
  String _bankBin = '970418';
  String _accountType = 'personal-account';
  bool _busy = false;
  String? _confirmId;
  String? _merchantId;
  String? _shopId;
  String? _va;
  String? _statusMsg;
  List<Map<String, dynamic>> _accounts = const [];

  @override
  void initState() {
    super.initState();
    if (widget.stores.isNotEmpty) {
      _storeId = _idOf(widget.stores.first);
      _fillFromStore(widget.stores.first);
    }
  }

  @override
  void didUpdateWidget(TingeeStoreSetupCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_storeId == null && widget.stores.isNotEmpty) {
      _storeId = _idOf(widget.stores.first);
      _fillFromStore(widget.stores.first);
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    _accNameCtrl.dispose();
    _accNumberCtrl.dispose();
    _identityCtrl.dispose();
    _mobileCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  String _idOf(Map<String, dynamic> s) =>
      (s['id'] ?? s['storeId'] ?? '').toString();

  String _nameOf(Map<String, dynamic> s) =>
      (s['name'] ?? s['storeName'] ?? _idOf(s)).toString();

  void _fillFromStore(Map<String, dynamic> s) {
    _nameCtrl.text = _nameOf(s);
    _phoneCtrl.text = (s['phone'] ?? s['Phone'] ?? '').toString();
    _mobileCtrl.text = _phoneCtrl.text;
  }

  Map<String, dynamic>? _data(Map<String, dynamic> res) {
    if (res['isSuccess'] == true && res['data'] is Map) {
      return Map<String, dynamic>.from(res['data'] as Map);
    }
    return null;
  }

  void _apply(Map<String, dynamic>? data, {String? fallback}) {
    if (data == null) return;
    setState(() {
      _merchantId = (data['tingeeMerchantId'] ?? '').toString();
      _shopId = (data['tingeeShopId'] ?? '').toString();
      _va = (data['tingeeVaAccountNumber'] ?? '').toString();
      _confirmId = (data['confirmId'] ?? '').toString();
      if (_confirmId!.isEmpty) _confirmId = null;
      _statusMsg = (data['message'] ?? fallback ?? '').toString();
      final acc = data['accounts'];
      _accounts = acc is List
          ? acc
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : const [];
    });
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() fn, String okTitle) async {
    final storeId = _storeId;
    if (storeId == null || storeId.isEmpty) return;
    setState(() => _busy = true);
    final res = await fn();
    if (!mounted) return;
    setState(() => _busy = false);
    final data = _data(res);
    if (data != null) {
      _apply(data);
      final url = (data['bankLinkUrl'] ?? data['authorizeLink'] ?? '').toString();
      if (url.startsWith('http')) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
      NotificationOverlayManager().show(
        title: tr(okTitle),
        message: (data['message'] ?? '').toString(),
        type: NotificationType.success,
      );
    } else {
      NotificationOverlayManager().show(
        title: tr('Lỗi Tingee'),
        message: (res['message'] ?? res['Message'] ?? '').toString(),
        type: NotificationType.error,
      );
    }
  }

  Future<void> _loadStatus() async {
    final storeId = _storeId;
    if (storeId == null) return;
    await _run(() => _api.adminTingeeStoreStatus(storeId), 'Trạng thái Tingee');
  }

  @override
  Widget build(BuildContext context) {
    final storeItems = widget.stores
        .map((s) {
          final id = _idOf(s);
          return DropdownMenuItem(value: id, child: Text(_nameOf(s)));
        })
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Tạo cửa hàng Tingee & gắn STK'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              tr('SBOX gọi API Tingee giúp SuperAdmin — không cần vào portal bấm Tạo mới.'),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _storeId,
              decoration: InputDecoration(
                labelText: tr('Cửa hàng SBOX'),
                border: const OutlineInputBorder(),
              ),
              items: storeItems,
              onChanged: (v) {
                setState(() {
                  _storeId = v;
                  final s = widget.stores.where((e) => _idOf(e) == v).toList();
                  if (s.isNotEmpty) _fillFromStore(s.first);
                });
                unawaited(_loadStatus());
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: tr('Tên merchant / shop Tingee'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: tr('SĐT đăng ký Tingee'),
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
                            () => _api.adminTingeeProvision(
                              storeId: _storeId!,
                              name: _nameCtrl.text.trim(),
                              phone: _phoneCtrl.text.trim(),
                            ),
                            'Đã tạo trên Tingee',
                          ),
                  icon: const Icon(Icons.storefront),
                  label: Text(tr('Tạo merchant + shop')),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _loadStatus,
                  icon: const Icon(Icons.refresh),
                  label: Text(tr('Tải trạng thái')),
                ),
              ],
            ),
            if ((_merchantId ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Merchant $_merchantId · Shop ${_shopId ?? '-'} · VA ${_va ?? '-'}',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            const Divider(height: 28),
            Text(tr('Gắn số tài khoản'),
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
              onChanged: (v) =>
                  setState(() => _accountType = v ?? _accountType),
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
                labelText: tr('SĐT đăng ký ngân hàng'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _identityCtrl,
              decoration: InputDecoration(
                labelText: tr('CCCD / MST (nếu ngân hàng yêu cầu)'),
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
                            () => _api.adminTingeeLinkBank(
                              storeId: _storeId!,
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
                  label: Text(tr('Gắn STK qua API')),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _run(
                            () => _api.adminTingeeBankLinkSession(_storeId!),
                            'Mở liên kết ngân hàng',
                          ),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(tr('Mở SDK chọn ngân hàng')),
                ),
              ],
            ),
            if (_confirmId != null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _otpCtrl,
                decoration: InputDecoration(
                  labelText: tr('OTP ngân hàng'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(
                          () => _api.adminTingeeConfirmVa(
                            storeId: _storeId!,
                            bankBin: _bankBin,
                            confirmId: _confirmId!,
                            otpNumber: _otpCtrl.text.trim(),
                          ),
                          'Đã xác nhận VA',
                        ),
                icon: const Icon(Icons.verified),
                label: Text(tr('Xác nhận OTP')),
              ),
            ],
            if ((_statusMsg ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_statusMsg!, style: const TextStyle(fontSize: 13)),
            ],
            if (_accounts.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(tr('Tài khoản trên Tingee'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              ..._accounts.map((a) {
                final va = (a['vaAccountNumber'] ?? a['accountNumber'] ?? '')
                    .toString();
                final name = (a['accountName'] ?? '').toString();
                final st = (a['status'] ?? '').toString();
                return ListTile(
                  dense: true,
                  title: Text(va),
                  subtitle: Text('$name · $st'),
                  trailing: TextButton(
                    onPressed: _busy || va.isEmpty
                        ? null
                        : () => _run(
                              () => _api.adminTingeeApplyVa(
                                storeId: _storeId!,
                                vaAccountNumber: va,
                              ),
                              'Đã gán VA',
                            ),
                    child: Text(tr('Dùng VA này')),
                  ),
                );
              }),
            ],
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}