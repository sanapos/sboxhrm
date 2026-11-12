import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../models/hrm.dart';
import '../../utils/api_datetime.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/reports/report_drill_sheet.dart';
import 'system_admin_helpers.dart';
import 'tingee_store_setup_card.dart';

import '../../theme/sbox_tokens.dart';
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
              _statCard(tr('Còn trong kho'), '$remain', SboxColors.okSwatch,
                  onTap: () => _ledgerDrill('Nhật ký kho lượt', null, remain,
                      'Còn trong kho = đã mua Tingee ($purchased) − đã bán / cấp cửa hàng ($allocated). '
                          'Danh sách: mọi lần nạp (+) và cấp cho cửa hàng (−).')),
              _statCard(tr('Đã mua Tingee'), '$purchased', SboxColors.brand500,
                  onTap: () => _ledgerDrill('Lần nạp kho (mua Tingee)', 'TingeePurchase', purchased, null)),
              _statCard(tr('Đã bán CH'), '$allocated', Colors.orange,
                  onTap: () => _ledgerDrill('Lượt đã bán / cấp cửa hàng', 'StoreAllocation', allocated,
                      'Gồm cấp tay từ màn này và cửa hàng tự mua gói lượt (đã thanh toán).')),
              _statCard(tr('Giá vốn/lượt'), '${costPer.toStringAsFixed(0)} đ',
                  SboxColors.slate500),
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
                    style: const TextStyle(fontSize: 12, color: SboxColors.slate500),
                  ),
                  Text(
                    tr('UAT API: https://uat-open-api.tingee.vn/v1'),
                    style: const TextStyle(fontSize: 12, color: SboxColors.slate500),
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
          TingeeStoreSetupCard(stores: _stores),
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
                subtitle: Text(tr('$credits lượt · ${price.toStringAsFixed(0)} đ · ~$per đ/lượt')),
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
            Wrap(spacing: 4, children: [
              InkWell(
                onTap: () => _purchaseDrill('Paid', 'Đơn mua lượt đã thanh toán'),
                child: Text(tr('Paid: ${_purchaseReport!['totalCreditsPaid'] ?? 0} lượt'),
                    style: const TextStyle(color: SboxColors.slate500, decoration: TextDecoration.underline)),
              ),
              const Text('·', style: TextStyle(color: SboxColors.slate500)),
              InkWell(
                onTap: () => _purchaseDrill('Pending', 'Đơn mua lượt chờ thanh toán'),
                child: Text(tr('Pending: ${_purchaseReport!['totalCreditsPending'] ?? 0} lượt'),
                    style: const TextStyle(color: SboxColors.slate500, decoration: TextDecoration.underline)),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _statCard(String label, String value, Color color, {VoidCallback? onTap}) {
    final card = Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: AdminHelpers.cardDecoration(borderColor: color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: SboxColors.slate600)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
    if (onTap == null) return card;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: card);
  }

  // ── Chi tiết số liệu («số này từ đâu ra») ──

  Future<Map<String, dynamic>?> _drillFetch(String path, Map<String, String> query) async {
    final nav = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final r = await _api.getReportJson(path, query: query);
    nav.pop();
    if (r['isSuccess'] == true && r['data'] is Map) return Map<String, dynamic>.from(r['data'] as Map);
    messenger?.showSnackBar(SnackBar(content: Text(tr(r['message']?.toString() ?? 'Không tải được dữ liệu'))));
    return null;
  }

  static String _when(Object? raw) {
    final d = parseApiUtcDateTime(raw);
    if (d == null) return '';
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  /// Nhật ký kho lượt theo nguồn (null = tất cả). [shown]: số trên ô để đối chiếu với tổng nhật ký.
  Future<void> _ledgerDrill(String title, String? source, int shown, String? note) async {
    final d = await _drillFetch('/api/system-admin/v2/drill/credit-ledgers', {if (source != null) 'source': source});
    if (d == null || !mounted) return;
    final items = [for (final e in (d['items'] as List? ?? const [])) if (e is Map) Map<String, dynamic>.from(e)];
    final ledgerTotal = source == null ? (d['sumDelta'] as num?)?.toInt() ?? 0 : (d['total'] as num?)?.toInt() ?? 0;
    final notes = [
      if (note != null) note,
      if (ledgerTotal != shown)
        'Tổng nhật ký ($ledgerTotal) lệch số trên ô ($shown) — số trên ô là bộ đếm của kho, có thể gồm điều chỉnh không ghi nhật ký.',
    ];
    await showReportDrillSheet(
      context,
      title: title,
      note: notes.isEmpty ? null : notes.join(' '),
      countLabel: '${d['count'] ?? items.length}',
      total: 'Tổng $ledgerTotal lượt',
      footer: d['truncated'] == true ? 'Hiện ${items.length} / ${d['count']} dòng mới nhất; tổng tính trên tất cả.' : null,
      emptyText: 'Chưa có nhật ký',
      rows: [
        for (final x in items)
          ReportDrillRow(
            title: (x['storeName'] ?? '').toString().isNotEmpty
                ? '${x['storeName']}'
                : switch ('${x['source']}') {
                    'TingeePurchase' => 'Nạp kho (mua Tingee)',
                    'StoreAllocation' => 'Cấp cho cửa hàng',
                    'AdminAdjust' => 'Điều chỉnh',
                    final s => s,
                  },
            icon: ((x['delta'] as num?) ?? 0) >= 0 ? Icons.add_circle_outline : Icons.remove_circle_outline,
            subtitle: [
              _when(x['createdAt']),
              if ((x['note'] ?? '').toString().isNotEmpty) '${x['note']}',
              if ((x['createdBy'] ?? '').toString().isNotEmpty) '${x['createdBy']}',
              'còn ${x['balanceAfter'] ?? 0}',
            ].join(' · '),
            trailing: '${((x['delta'] as num?) ?? 0) > 0 ? '+' : ''}${x['delta'] ?? 0}',
            trailingColor: ((x['delta'] as num?) ?? 0) >= 0 ? SboxColors.successText : SboxColors.dangerText,
          ),
      ],
    );
  }

  Future<void> _purchaseDrill(String status, String title) async {
    final d = await _drillFetch('/api/system-admin/v2/drill/credit-purchases', {'status': status});
    if (d == null || !mounted) return;
    final items = [for (final e in (d['items'] as List? ?? const [])) if (e is Map) Map<String, dynamic>.from(e)];
    await showReportDrillSheet(
      context,
      title: title,
      countLabel: '${d['count'] ?? items.length}',
      total: 'Tổng ${d['credits'] ?? 0} lượt · ${(d['amount'] as num? ?? 0).toStringAsFixed(0)} đ',
      footer: d['truncated'] == true ? 'Hiện ${items.length} / ${d['count']} đơn mới nhất.' : null,
      emptyText: 'Không có đơn',
      rows: [
        for (final x in items)
          ReportDrillRow(
            title: '${x['storeName'] ?? ''}',
            subtitle: [
              '${x['packageName'] ?? ''}',
              '${(x['amountPaid'] as num? ?? 0).toStringAsFixed(0)} đ',
              _when(x['paidAt'] ?? x['createdAt']),
              if ((x['externalPaymentRef'] ?? '').toString().isNotEmpty) '${x['externalPaymentRef']}',
            ].join(' · '),
            trailing: '${x['creditCount'] ?? 0} lượt',
          ),
      ],
    );
  }
}
