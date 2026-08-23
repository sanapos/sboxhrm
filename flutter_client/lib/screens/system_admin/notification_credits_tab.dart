import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../models/hrm.dart';
import '../../widgets/notification_overlay.dart';
import 'system_admin_helpers.dart';

/// SuperAdmin — kho lượt Tingee, credentials platform, bán gói cho cửa hàng.
class NotificationCreditsTab extends StatefulWidget {
  const NotificationCreditsTab({super.key});

  @override
  State<NotificationCreditsTab> createState() => NotificationCreditsTabState();
}

class NotificationCreditsTabState extends State<NotificationCreditsTab> {
  final _api = ApiService();
  bool _loading = true;

  Map<String, dynamic>? _pool;
  Map<String, dynamic>? _platformTingee;
  List<Map<String, dynamic>> _packages = const [];
  List<Map<String, dynamic>> _platformLedgers = const [];
  List<Map<String, dynamic>> _stores = const [];
  Map<String, dynamic>? _purchaseReport;

  final _topUpCountCtrl = TextEditingController(text: '10000');
  final _topUpCostCtrl = TextEditingController(text: '200');
  final _clientIdCtrl = TextEditingController();
  final _secretCtrl = TextEditingController();
  final _webhookSecretCtrl = TextEditingController();
  final _defaultVaCtrl = TextEditingController();
  String _apiEnv = 'Production';
  bool _tingeeEnabled = false;

  String? _grantStoreId;
  final _grantCountCtrl = TextEditingController(text: '1000');

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void dispose() {
    _topUpCountCtrl.dispose();
    _topUpCostCtrl.dispose();
    _clientIdCtrl.dispose();
    _secretCtrl.dispose();
    _webhookSecretCtrl.dispose();
    _defaultVaCtrl.dispose();
    _grantCountCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _api.adminPlatformCredits(),
        _api.adminPlatformTingeeSettings(),
        _api.adminListCreditPackages(),
        _api.adminPlatformCreditLedgers(limit: 30),
        _api.getSystemAdminStores(page: 1, pageSize: 200),
        _api.adminCreditPurchasesReport(limit: 15),
      ]);
      if (!mounted) return;
      setState(() {
        if (results[0]['isSuccess'] == true) {
          _pool = Map<String, dynamic>.from(results[0]['data'] as Map);
        }
        if (results[1]['isSuccess'] == true) {
          _platformTingee = Map<String, dynamic>.from(results[1]['data'] as Map);
          _clientIdCtrl.text =
              (_platformTingee?['tingeeClientId'] ?? '').toString();
          _defaultVaCtrl.text =
              (_platformTingee?['defaultVaAccountNumber'] ?? '').toString();
          _apiEnv =
              (_platformTingee?['apiEnvironment'] ?? 'Production').toString();
          _tingeeEnabled = _platformTingee?['tingeeEnabled'] == true;
        }
        if (results[2]['isSuccess'] == true && results[2]['data'] is List) {
          _packages = (results[2]['data'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        if (results[3]['isSuccess'] == true && results[3]['data'] is List) {
          _platformLedgers = (results[3]['data'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
        if (results[4]['isSuccess'] == true) {
          final data = results[4]['data'];
          final items = data is Map ? data['items'] : data;
          if (items is List) {
            _stores = items
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
            _grantStoreId ??= _stores.isNotEmpty
                ? (_stores.first['id'] ?? _stores.first['storeId'])?.toString()
                : null;
          }
        }
        if (results[5]['isSuccess'] == true) {
          _purchaseReport = Map<String, dynamic>.from(results[5]['data'] as Map);
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _topUp() async {
    final count = int.tryParse(_topUpCountCtrl.text.trim()) ?? 0;
    final cost = double.tryParse(_topUpCostCtrl.text.trim()) ?? 200;
    if (count <= 0) return;
    final res = await _api.adminPlatformTopUp(
      creditCount: count,
      costPerCredit: cost,
      note: 'Nạp kho Tingee',
    );
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().show(
        title: tr('Đã nạp kho'),
        message: tr('+$count lượt'),
        type: NotificationType.success,
      );
      unawaited(_reload());
    } else {
      NotificationOverlayManager().show(
        title: tr('Lỗi'),
        message: (res['message'] ?? '').toString(),
        type: NotificationType.error,
      );
    }
  }

  Future<void> _savePlatformTingee() async {
    final res = await _api.adminUpsertPlatformTingeeSettings(
      tingeeEnabled: _tingeeEnabled,
      tingeeClientId: _clientIdCtrl.text.trim(),
      tingeeSecretKey:
          _secretCtrl.text.trim().isEmpty ? null : _secretCtrl.text.trim(),
      tingeeWebhookSecret: _webhookSecretCtrl.text.trim().isEmpty
          ? null
          : _webhookSecretCtrl.text.trim(),
      apiEnvironment: _apiEnv,
      defaultVaAccountNumber: _defaultVaCtrl.text.trim(),
    );
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      _secretCtrl.clear();
      _webhookSecretCtrl.clear();
      NotificationOverlayManager().show(
        title: tr('Đã lưu Tingee platform'),
        message: tr('Credentials master Sbox'),
        type: NotificationType.success,
      );
      unawaited(_reload());
    } else {
      NotificationOverlayManager().show(
        title: tr('Lỗi'),
        message: (res['message'] ?? '').toString(),
        type: NotificationType.error,
      );
    }
  }

  Future<void> _grantStore() async {
    final storeId = _grantStoreId;
    final count = int.tryParse(_grantCountCtrl.text.trim()) ?? 0;
    if (storeId == null || storeId.isEmpty || count <= 0) return;
    final res = await _api.adminGrantCredits(
      storeId: storeId,
      creditCount: count,
      note: 'SuperAdmin bán gói lượt',
    );
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().show(
        title: tr('Đã cấp credit'),
        message: tr('$count lượt → cửa hàng'),
        type: NotificationType.success,
      );
      unawaited(_reload());
    } else {
      NotificationOverlayManager().show(
        title: tr('Lỗi'),
        message: (res['message'] ?? '').toString(),
        type: NotificationType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final remain = (_pool?['remainingCount'] as num?)?.toInt() ?? 0;
    final purchased = (_pool?['totalPurchased'] as num?)?.toInt() ?? 0;
    final allocated = (_pool?['totalAllocated'] as num?)?.toInt() ?? 0;
    final costPer = (_pool?['lastCostPerCredit'] as num?)?.toDouble() ?? 200;
    final webhookUrl =
        (_platformTingee?['webhookUrl'] ?? '').toString();

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(tr('Kho lượt thông báo CK (Sbox)'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _statCard(tr('Còn trong kho'), '$remain', Colors.green),
              _statCard(tr('Đã mua Tingee'), '$purchased', Colors.blue),
              _statCard(tr('Đã bán CH'), '$allocated', Colors.orange),
              _statCard(tr('Giá vốn/lượt'), '${costPer.toStringAsFixed(0)} đ',
                  Colors.grey),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Nạp kho (mua gói Tingee)'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _topUpCountCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: tr('Số lượt'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _topUpCostCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: tr('Giá vốn/ lượt (đ)'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _topUp,
                    icon: const Icon(Icons.add_circle_outline),
                    label: Text(tr('Nạp vào kho')),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Tingee master (SuperAdmin)'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    tr('Webhook: $webhookUrl'),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    tr('UAT API: https://uat-open-api.tingee.vn/v1'),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('Bật Tingee platform')),
                    value: _tingeeEnabled,
                    onChanged: (v) => setState(() => _tingeeEnabled = v),
                  ),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'Production', label: Text(tr('Prod'))),
                      ButtonSegment(value: 'UAT', label: Text(tr('UAT'))),
                    ],
                    selected: {_apiEnv},
                    onSelectionChanged: (s) =>
                        setState(() => _apiEnv = s.first),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _clientIdCtrl,
                    decoration: InputDecoration(
                      labelText: tr('Client ID'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _secretCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: tr('Secret Token'),
                      hintText: _platformTingee?['hasTingeeSecretKey'] == true
                          ? tr('Đã lưu — để trống nếu không đổi')
                          : null,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _webhookSecretCtrl,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: tr('Webhook Secret'),
                      hintText:
                          _platformTingee?['hasTingeeWebhookSecret'] == true
                              ? tr('Đã lưu — để trống nếu không đổi')
                              : null,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _defaultVaCtrl,
                    decoration: InputDecoration(
                      labelText: tr('VA mặc định (mua gói credit)'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _savePlatformTingee,
                    icon: const Icon(Icons.save),
                    label: Text(tr('Lưu Tingee platform')),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('Bán lượt cho cửa hàng'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _grantStoreId,
                    decoration: InputDecoration(
                      labelText: tr('Cửa hàng'),
                      border: const OutlineInputBorder(),
                    ),
                    items: _stores
                        .map((s) {
                          final id =
                              (s['id'] ?? s['storeId'] ?? '').toString();
                          final name = (s['name'] ?? s['storeName'] ?? id)
                              .toString();
                          return DropdownMenuItem(value: id, child: Text(name));
                        })
                        .toList(),
                    onChanged: (v) => setState(() => _grantStoreId = v),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _grantCountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: tr('Số lượt cấp (trừ kho Sbox)'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _grantStore,
                    icon: const Icon(Icons.store),
                    label: Text(tr('Cấp cho cửa hàng')),
                  ),
                ],
              ),
            ),
          ),
          if (_packages.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(tr('Gói bán cho cửa hàng (tự mua trong app)'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            ..._packages.map((p) {
              final credits = (p['creditCount'] as num?)?.toInt() ?? 0;
              final price = (p['price'] as num?)?.toDouble() ?? 0;
              final per = credits > 0 ? (price / credits).round() : 0;
              return ListTile(
                title: Text((p['name'] ?? '').toString()),
                subtitle: Text('$credits lượt · ${price.toStringAsFixed(0)} đ · ~$per đ/lượt'),
              );
            }),
          ],
          if (_platformLedgers.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(tr('Nhật ký kho Sbox'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            ..._platformLedgers.take(15).map((row) {
              final delta = (row['delta'] as num?)?.toInt() ?? 0;
              final bal = (row['balanceAfter'] as num?)?.toInt() ?? 0;
              final store = (row['storeName'] ?? '').toString();
              return ListTile(
                dense: true,
                title: Text(
                  '${delta > 0 ? '+' : ''}$delta · còn $bal · ${row['source'] ?? ''}',
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: store.isNotEmpty ? Text(store) : null,
              );
            }),
          ],
          if (_purchaseReport != null) ...[
            const SizedBox(height: 16),
            Text(tr('Đơn mua credit cửa hàng'),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(
              tr('Paid: ${_purchaseReport!['totalCreditsPaid'] ?? 0} lượt · '
                  'Pending: ${_purchaseReport!['totalCreditsPending'] ?? 0} lượt'),
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: AdminHelpers.cardDecoration(borderColor: color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
