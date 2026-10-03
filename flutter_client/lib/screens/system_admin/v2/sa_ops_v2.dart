import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_tr.dart';
import '../../../services/api_service.dart';
import '../../../utils/file_saver.dart' as file_saver;
import '../../../widgets/sbox/sbox_ui.dart';
import 'sa_v2_common.dart';

/// Khung 2 chế độ xem: màn mới + màn cũ (giữ trạng thái cả hai).
class SaHubSwitch extends StatefulWidget {
  const SaHubSwitch({super.key, required this.views});
  final List<(String, Widget)> views;

  @override
  State<SaHubSwitch> createState() => _SaHubSwitchState();
}

class _SaHubSwitchState extends State<SaHubSwitch> {
  int _i = 0;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        width: double.infinity,
        color: SboxColors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: SaSegment<int>(
          value: _i,
          options: {for (var k = 0; k < widget.views.length; k++) k: widget.views[k].$1},
          onChanged: (v) => setState(() => _i = v),
        ),
      ),
      Expanded(child: IndexedStack(index: _i, children: [for (final v in widget.views) v.$2])),
    ]);
  }
}

// ─── Key kích hoạt ──────────────────────────────────────────────────

class KeysV2View extends StatefulWidget {
  const KeysV2View({super.key});

  @override
  State<KeysV2View> createState() => _KeysV2ViewState();
}

class _KeysV2ViewState extends State<KeysV2View> {
  final _api = ApiService();
  final _search = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  String _status = 'unused';
  String? _packageId;
  String? _agentId;
  int _page = 1;
  int _total = 0;
  Map<String, int> _counts = {};
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _packages = [];
  List<Map<String, dynamic>> _agents = [];
  final Set<String> _selected = {};
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final rs = await Future.wait([_api.saPackages(), _api.saAgents()]);
    if (!mounted) return;
    setState(() {
      _packages = rs[0]['data'] is List ? (rs[0]['data'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
      _agents = rs[1]['data'] is List ? (rs[1]['data'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
    });
    await _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => _loading = true);
    final r = await _api.saLicenses(status: _status, packageId: _packageId, agentId: _agentId, search: _search.text, page: _page);
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      final d = r['data'];
      if (d is Map) {
        _items = (d['items'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _total = (d['total'] as num?)?.toInt() ?? 0;
        _counts = {for (final e in (d['counts'] as Map? ?? {}).entries) '${e.key}': (e.value as num).toInt()};
      }
      _selected.removeWhere((id) => !_items.any((k) => k['id'] == id));
    });
  }

  Future<void> _revoke() async {
    final ids = _items.where((k) => _selected.contains(k['id']) && k['isUsed'] != true).map((k) => '${k['id']}').toList();
    if (ids.isEmpty) return saToast(context, 'Chỉ thu hồi được key chưa dùng', error: true);
    final ok = await SboxDialogs.confirm(context,
        title: 'Thu hồi ${ids.length} key?', message: 'Key bị thu hồi không kích hoạt được nữa. Key đã dùng không bị ảnh hưởng.', confirmLabel: 'Thu hồi', danger: true);
    if (!ok) return;
    final r = await _api.batchRevokeLicenses(ids);
    if (!mounted) return;
    if (saOk(context, r, 'Đã thu hồi ${ids.length} key')) {
      _selected.clear();
      _load();
    }
  }

  Future<void> _export() async {
    final bytes = await _api.downloadLicenseExport(isUsed: _status == 'used' ? true : _status == 'unused' ? false : null, agentId: _agentId);
    if (!mounted) return;
    if (bytes == null) return saToast(context, 'Không xuất được file', error: true);
    final now = DateTime.now();
    await file_saver.saveFileBytes(bytes, 'sbox_keys_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.csv', 'text/csv');
    if (mounted) saToast(context, 'Đã xuất file CSV');
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = SboxSpace.pagePadding(w);
    final pages = (_total / 50).ceil().clamp(1, 9999);
    return ColoredBox(
      color: SboxColors.page,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: EdgeInsets.all(pad), children: [
          SboxPageHeader(
            title: 'Key kích hoạt',
            subtitle: 'Kho key, key đã giao đại lý, key đã kích hoạt cho cửa hàng',
            actions: [SboxButton.secondary(label: 'Xuất CSV', icon: Icons.download_outlined, onPressed: _export)],
          ),
          const SizedBox(height: SboxSpace.md),
          SboxKpiStrip(maxColumns: 4, items: [
            SboxKpi(label: 'Chưa dùng', value: '${_counts['unused'] ?? 0}', icon: Icons.vpn_key_outlined, tone: SboxTone.brand),
            SboxKpi(label: 'Đã kích hoạt', value: '${_counts['used'] ?? 0}', icon: Icons.verified_outlined, tone: SboxTone.success),
            SboxKpi(label: 'Đã thu hồi', value: '${_counts['revoked'] ?? 0}', icon: Icons.block, tone: SboxTone.neutral),
            SboxKpi(label: 'Tổng', value: '${_counts['all'] ?? 0}', icon: Icons.inventory_2_outlined),
          ]),
          const SizedBox(height: SboxSpace.md),
          SaSegment<String>(
            value: _status,
            options: const {'unused': 'Chưa dùng', 'used': 'Đã kích hoạt', 'revoked': 'Đã thu hồi', '': 'Tất cả'},
            onChanged: (v) {
              setState(() {
                _status = v;
                _page = 1;
              });
              _load();
            },
          ),
          const SizedBox(height: SboxSpace.sm),
          Wrap(spacing: SboxSpace.sm, runSpacing: SboxSpace.sm, children: [
            SizedBox(
              width: 260,
              child: TextField(
                controller: _search,
                decoration: saInput('Tìm key, cửa hàng, ghi chú').copyWith(prefixIcon: const Icon(Icons.search, size: 18)),
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 350), () {
                    _page = 1;
                    _load();
                  });
                },
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String?>(
                initialValue: _packageId,
                isExpanded: true,
                decoration: saInput('Gói'),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text(tr('Mọi gói'))),
                  for (final p in _packages) DropdownMenuItem<String?>(value: '${p['id']}', child: Text('${p['name']}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) {
                  setState(() => _packageId = v);
                  _load();
                },
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String?>(
                initialValue: _agentId,
                isExpanded: true,
                decoration: saInput('Đại lý'),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text(tr('Mọi đại lý'))),
                  for (final a in _agents) DropdownMenuItem<String?>(value: '${a['id']}', child: Text('${a['name']}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) {
                  setState(() => _agentId = v);
                  _load();
                },
              ),
            ),
          ]),
          const SizedBox(height: SboxSpace.sm),
          if (_selected.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: SboxSpace.sm),
              padding: const EdgeInsets.symmetric(horizontal: SboxSpace.md, vertical: SboxSpace.sm),
              decoration: BoxDecoration(color: SboxColors.brand50, borderRadius: SboxRadius.mdAll),
              child: Row(children: [
                Expanded(child: Text('Đã chọn ${_selected.length}', style: SboxType.bodyStrong(SboxColors.brand800))),
                SboxButton.secondary(
                  label: 'Sao chép',
                  icon: Icons.copy,
                  size: SboxButtonSize.sm,
                  onPressed: () {
                    final keys = _items.where((k) => _selected.contains(k['id'])).map((k) => '${k['key']}').join('\n');
                    Clipboard.setData(ClipboardData(text: keys));
                    saToast(context, 'Đã sao chép ${_selected.length} key');
                  },
                ),
                const SizedBox(width: SboxSpace.sm),
                SboxButton.danger(label: 'Thu hồi', icon: Icons.block, size: SboxButtonSize.sm, onPressed: _revoke),
              ]),
            ),
          Container(
            decoration: BoxDecoration(color: SboxColors.white, borderRadius: SboxRadius.lgAll, border: Border.all(color: SboxColors.border)),
            clipBehavior: Clip.antiAlias,
            child: _items.isEmpty
                ? (_loading ? const SboxLoading() : const SboxEmptyState(icon: Icons.vpn_key_outlined, title: 'Không có key phù hợp'))
                : Column(children: [
                    for (var i = 0; i < _items.length; i++) ...[
                      if (i > 0) const Divider(height: 1, color: SboxColors.divider),
                      _row(_items[i]),
                    ],
                  ]),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text('$_total key · trang $_page/$pages', style: SboxType.captionStyle()),
            IconButton(onPressed: _page > 1 ? () { setState(() => _page--); _load(); } : null, icon: const Icon(Icons.chevron_left)),
            IconButton(onPressed: _page < pages ? () { setState(() => _page++); _load(); } : null, icon: const Icon(Icons.chevron_right)),
          ]),
        ]),
      ),
    );
  }

  Widget _row(Map<String, dynamic> k) {
    final id = '${k['id']}';
    final used = k['isUsed'] == true;
    final revoked = !used && k['isActive'] != true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Checkbox(value: _selected.contains(id), onChanged: (v) => setState(() => v == true ? _selected.add(id) : _selected.remove(id))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              SelectableText('${k['key']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 14, fontWeight: FontWeight.w600)),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: tr('Sao chép'),
                icon: const Icon(Icons.copy, size: 16),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: '${k['key']}'));
                  saToast(context, 'Đã sao chép key');
                },
              ),
            ]),
            Wrap(spacing: 6, runSpacing: 4, children: [
              SboxStatusChip(
                label: used ? 'Đã kích hoạt' : revoked ? 'Đã thu hồi' : 'Chưa dùng',
                tone: used ? SboxTone.success : revoked ? SboxTone.neutral : SboxTone.brand,
                dot: true,
              ),
              SboxStatusChip(label: '${k['packageName'] ?? k['licenseType']} · ${k['durationDays']} ngày', tone: SboxTone.neutral),
              if (k['agentName'] != null) SboxStatusChip(label: '${k['agentName']}', tone: SboxTone.violet),
              if (k['storeName'] != null) SboxStatusChip(label: '${k['storeName']} (${k['storeCode']}) · ${saDate(k['activatedAt'])}', tone: SboxTone.success),
              Text('Tạo ${saDate(k['createdAt'])}', style: SboxType.captionStyle()),
            ]),
            if ((k['notes'] ?? '').toString().isNotEmpty) Text('${k['notes']}', style: SboxType.captionStyle()),
          ]),
        ),
      ]),
    );
  }
}

// ─── Đại lý ─────────────────────────────────────────────────────────

class AgentsV2View extends StatefulWidget {
  const AgentsV2View({super.key});

  @override
  State<AgentsV2View> createState() => _AgentsV2ViewState();
}

class _AgentsV2ViewState extends State<AgentsV2View> {
  final _api = ApiService();
  bool _loading = true;
  List<Map<String, dynamic>> _agents = [];
  String _sort = 'activations';
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await _api.saAgents();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _agents = r['data'] is List ? (r['data'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
    });
  }

  int _n(Map a, String k) => (a[k] as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = SboxSpace.pagePadding(w);
    if (_loading && _agents.isEmpty) return const SboxLoading();
    final list = _agents.where((a) => _q.isEmpty || '${a['name']} ${a['code']} ${a['phone']}'.toLowerCase().contains(_q.toLowerCase())).toList()
      ..sort((a, b) => switch (_sort) {
            'stores' => _n(b, 'stores').compareTo(_n(a, 'stores')),
            'expiring' => _n(b, 'expiringStores').compareTo(_n(a, 'expiringStores')),
            'keys' => _n(a, 'unusedKeys').compareTo(_n(b, 'unusedKeys')),
            _ => _n(b, 'activations30').compareTo(_n(a, 'activations30')),
          });
    int sum(String k) => _agents.fold(0, (s, a) => s + _n(a, k));
    final top = [...list]..sort((a, b) => _n(b, 'activations30').compareTo(_n(a, 'activations30')));
    final cols = w >= 1300 ? 3 : w >= 820 ? 2 : 1;
    return ColoredBox(
      color: SboxColors.page,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: EdgeInsets.all(pad), children: [
          const SboxPageHeader(title: 'Hiệu quả đại lý', subtitle: 'Cửa hàng, kích hoạt key, tồn kho key và khách sắp hết hạn của từng đại lý'),
          const SizedBox(height: SboxSpace.md),
          SboxKpiStrip(maxColumns: 5, items: [
            SboxKpi(label: 'Đại lý hoạt động', value: '${_agents.where((a) => a['isActive'] == true).length}/${_agents.length}', icon: Icons.support_agent),
            SboxKpi(label: 'Cửa hàng qua đại lý', value: '${sum('stores')}', icon: Icons.store_outlined, tone: SboxTone.success),
            SboxKpi(label: 'Kích hoạt 30 ngày', value: '${sum('activations30')}', icon: Icons.trending_up, tone: SboxTone.brand),
            SboxKpi(label: 'Sắp hết hạn (7 ngày)', value: '${sum('expiringStores')}', icon: Icons.schedule, tone: SboxTone.warning),
            SboxKpi(label: 'Key đại lý chưa dùng', value: '${sum('unusedKeys')}', icon: Icons.vpn_key_outlined, tone: SboxTone.violet),
          ]),
          const SizedBox(height: SboxSpace.md),
          if (top.isNotEmpty && _n(top.first, 'activations30') > 0)
            SboxChartCard(
              title: 'Kích hoạt key 30 ngày theo đại lý',
              child: SboxRankList(
                items: [for (final a in top.take(8)) SboxSlice('${a['name']}', _n(a, 'activations30').toDouble(), caption: '${a['newStores30']} cửa hàng mới')],
                valueFormat: (v) => '${(v ?? 0).round()} key',
              ),
            ),
          const SizedBox(height: SboxSpace.md),
          Row(children: [
            Expanded(
              child: SaSegment<String>(
                value: _sort,
                options: const {'activations': 'Kích hoạt nhiều', 'stores': 'Nhiều cửa hàng', 'expiring': 'Nhiều khách sắp hết hạn', 'keys': 'Sắp hết key'},
                onChanged: (v) => setState(() => _sort = v),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(decoration: saInput('Tìm đại lý').copyWith(prefixIcon: const Icon(Icons.search, size: 18)), onChanged: (v) => setState(() => _q = v)),
            ),
          ]),
          const SizedBox(height: SboxSpace.md),
          if (list.isEmpty)
            const SboxEmptyState(icon: Icons.support_agent, title: 'Chưa có đại lý')
          else
            SboxGrid(columns: cols, children: [for (final a in list) _card(a)]),
        ]),
      ),
    );
  }

  Widget _card(Map<String, dynamic> a) {
    final maxStores = _n(a, 'maxStores');
    final stores = _n(a, 'stores');
    return Container(
      padding: const EdgeInsets.all(SboxSpace.lg),
      decoration: BoxDecoration(color: SboxColors.white, borderRadius: SboxRadius.lgAll, border: Border.all(color: SboxColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${a['name']}', style: SboxType.titleSmStyle(), maxLines: 1, overflow: TextOverflow.ellipsis)),
          SboxStatusChip(label: a['isActive'] == true ? 'Hoạt động' : 'Tạm khóa', tone: a['isActive'] == true ? SboxTone.success : SboxTone.neutral, dot: true),
        ]),
        Text('${a['code']} · ${a['phone'] ?? a['email'] ?? ''}', style: SboxType.captionStyle()),
        if (a['isRegistrationCompleted'] != true)
          const Padding(padding: EdgeInsets.only(top: 4), child: SboxStatusChip(label: 'Chưa hoàn tất đăng ký tài khoản', tone: SboxTone.warning)),
        const SizedBox(height: SboxSpace.sm),
        if (maxStores > 0) ...[
          Text('Cửa hàng $stores/$maxStores', style: SboxType.smallStyle(SboxColors.text)),
          const SizedBox(height: 4),
          SboxRatioBar(parts: [
            SboxSlice('Đã dùng', stores.toDouble(), color: stores >= maxStores ? SboxColors.danger : SboxColors.brand500),
            SboxSlice('Còn', (maxStores - stores).clamp(0, maxStores).toDouble(), color: SboxColors.slate200),
          ], height: 6),
        ] else
          Text('Cửa hàng $stores (không giới hạn)', style: SboxType.smallStyle(SboxColors.text)),
        const SizedBox(height: SboxSpace.sm),
        Wrap(spacing: 6, runSpacing: 4, children: [
          SboxStatusChip(label: '${a['activeStores']} hoạt động', tone: SboxTone.success),
          if (_n(a, 'expiringStores') > 0) SboxStatusChip(label: '${a['expiringStores']} sắp hết hạn', tone: SboxTone.warning),
          if (_n(a, 'expiredStores') > 0) SboxStatusChip(label: '${a['expiredStores']} đã hết hạn', tone: SboxTone.danger),
          SboxStatusChip(label: '${a['unusedKeys']} key tồn', tone: _n(a, 'unusedKeys') < 3 ? SboxTone.warning : SboxTone.neutral),
          SboxStatusChip(label: '${a['activations30']} kích hoạt / 30 ngày', tone: SboxTone.brand),
          if (_n(a, 'renewalDayBalance') > 0) SboxStatusChip(label: 'Quỹ ngày gia hạn ${a['renewalDayBalance']}', tone: SboxTone.violet),
        ]),
      ]),
    );
  }
}

// ─── Tình trạng hệ thống ────────────────────────────────────────────

String _dt(dynamic v) {
  final d = DateTime.tryParse('${v ?? ''}')?.toLocal();
  if (d == null) return '—';
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')} ${saDate(v)}';
}

class SystemStatusView extends StatefulWidget {
  const SystemStatusView({super.key, this.onNavigate});

  /// database / server / maintenance / audit / stores / licenses
  final ValueChanged<String>? onNavigate;

  @override
  State<SystemStatusView> createState() => _SystemStatusViewState();
}

class _SystemStatusViewState extends State<SystemStatusView> {
  final _api = ApiService();
  Map<String, dynamic>? _d;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _api.saSystemStatus();
    if (!mounted) return;
    setState(() => _d = r['data'] is Map ? Map<String, dynamic>.from(r['data'] as Map) : {});
  }

  Map<String, dynamic> _m(String k) => _d?[k] is Map ? Map<String, dynamic>.from(_d![k] as Map) : {};

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = SboxSpace.pagePadding(w);
    final d = _d;
    if (d == null) return const SboxLoading();
    final db = _m('database'), bk = _m('backups'), disk = _m('disk'), sec = _m('security'), st = _m('stores'), keys = _m('keys'), srv = _m('server');
    final warnings = (d['warnings'] as List? ?? []).whereType<Map>().toList();
    final maint = (d['maintenance'] as List? ?? []).whereType<Map>().toList();
    void go(String? tab) {
      if (tab != null) widget.onNavigate?.call(tab);
    }

    return ColoredBox(
      color: SboxColors.page,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: EdgeInsets.all(pad), children: [
          SboxPageHeader(
            title: 'Tình trạng hệ thống',
            subtitle: 'Phiên bản ${srv['version'] ?? '—'} · chạy ${srv['uptimeHours'] ?? 0} giờ · ${srv['machine'] ?? ''}',
            actions: [],
          ),
          const SizedBox(height: SboxSpace.md),
          if (warnings.isEmpty)
            Container(
              padding: const EdgeInsets.all(SboxSpace.md),
              decoration: BoxDecoration(color: SboxColors.successSoft, borderRadius: SboxRadius.mdAll),
              child: Row(children: [
                const Icon(Icons.check_circle, color: SboxColors.success),
                const SizedBox(width: 8),
                Text(tr('Mọi thứ đang hoạt động bình thường'), style: SboxType.bodyStrong(SboxColors.successText)),
              ]),
            )
          else
            for (final wn in warnings)
              Container(
                margin: const EdgeInsets.only(bottom: SboxSpace.sm),
                decoration: BoxDecoration(
                  color: wn['level'] == 'danger' ? SboxColors.dangerSoft : wn['level'] == 'warning' ? SboxColors.warningSoft : SboxColors.brand50,
                  borderRadius: SboxRadius.mdAll,
                ),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    wn['level'] == 'danger' ? Icons.error_outline : wn['level'] == 'warning' ? Icons.warning_amber_rounded : Icons.info_outline,
                    color: wn['level'] == 'danger' ? SboxColors.danger : wn['level'] == 'warning' ? SboxColors.warning : SboxColors.brand600,
                  ),
                  title: Text(tr('${wn['text']}'), style: SboxType.bodyStrong()),
                  trailing: wn['tab'] == null || widget.onNavigate == null ? null : TextButton(onPressed: () => go('${wn['tab']}'), child: Text(tr('Xem'))),
                ),
              ),
          const SizedBox(height: SboxSpace.md),
          SboxKpiStrip(maxColumns: 4, items: [
            SboxKpi(
                label: 'Database',
                value: db['ok'] == true ? '${db['latencyMs']} ms' : 'Lỗi',
                icon: Icons.storage,
                tone: db['ok'] == true ? SboxTone.success : SboxTone.danger,
                onTap: () => go('database')),
            SboxKpi(
                label: 'Sao lưu gần nhất',
                value: bk['last'] == null ? 'Chưa có' : saDate(bk['last']),
                icon: Icons.backup_outlined,
                note: '${bk['count'] ?? 0} bản · ${bk['totalMb'] ?? 0} MB',
                onTap: () => go('database')),
            SboxKpi(
                label: 'Ổ đĩa trống',
                value: disk['freeGb'] == null ? '—' : '${disk['freeGb']} GB',
                icon: Icons.sd_storage_outlined,
                note: disk['totalGb'] == null ? null : 'trên ${disk['totalGb']} GB',
                onTap: () => go('server')),
            SboxKpi(
                label: 'Bảo trì',
                value: maint.any((m) => m['running'] == true) ? 'Đang bảo trì' : maint.isEmpty ? 'Không có' : '${maint.length} lịch sắp tới',
                icon: Icons.build_circle_outlined,
                tone: maint.any((m) => m['running'] == true) ? SboxTone.warning : SboxTone.neutral,
                onTap: () => go('maintenance')),
          ]),
          const SizedBox(height: SboxSpace.md),
          SboxKpiStrip(maxColumns: 4, items: [
            SboxKpi(label: 'Đăng nhập sai 24h', value: '${sec['failedLogins'] ?? 0}', icon: Icons.gpp_maybe_outlined, tone: SboxTone.warning, onTap: () => go('audit')),
            SboxKpi(label: 'Đăng nhập thay', value: '${sec['impersonations'] ?? 0}', icon: Icons.support_agent, onTap: () => go('audit')),
            SboxKpi(label: 'Sắp hết hạn', value: '${st['expiring'] ?? 0}', icon: Icons.schedule, tone: SboxTone.warning, onTap: () => go('stores')),
            SboxKpi(label: 'Key chưa giao', value: '${keys['unusedUnassigned'] ?? 0}', icon: Icons.vpn_key_outlined, onTap: () => go('licenses')),
          ]),
          if (maint.isNotEmpty) ...[
            const SizedBox(height: SboxSpace.md),
            SboxCard(
              title: 'Lịch bảo trì',
              child: Column(children: [
                for (final m in maint)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(m['running'] == true ? Icons.build_circle : Icons.event, color: m['running'] == true ? SboxColors.warning : SboxColors.slate500),
                    title: Text('${m['title']}'),
                    subtitle: Text('${_dt(m['startAt'])} – ${_dt(m['endAt'])}${m['blockAccess'] == true ? ' · chặn truy cập' : ''}'),
                  ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}
