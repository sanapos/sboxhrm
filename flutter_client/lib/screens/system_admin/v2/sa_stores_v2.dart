import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_tr.dart';
import '../../../services/api_service.dart';
import '../../../widgets/sbox/sbox_ui.dart';
import 'sa_v2_common.dart';

const _statusLabels = {
  'all': 'Tất cả',
  'active': 'Hoạt động',
  'trial': 'Dùng thử',
  'expiring': 'Sắp hết hạn',
  'expired': 'Hết hạn',
  'locked': 'Bị khóa',
  'inactive': 'Ngừng',
};

SboxTone _statusTone(String s) => switch (s) {
      'active' => SboxTone.success,
      'trial' => SboxTone.brand,
      'expiring' => SboxTone.warning,
      'expired' || 'locked' => SboxTone.danger,
      _ => SboxTone.neutral,
    };

/// Cửa hàng v2: lọc theo trạng thái / gói, thao tác hàng loạt, chức năng riêng, lịch sử key.
/// Giữ màn cũ (chi tiết đầy đủ) ở tab «Chi tiết (cũ)».
class StoresHubV2 extends StatefulWidget {
  const StoresHubV2({super.key, required this.legacy, this.apiOverride});
  final Widget legacy;
  final ApiService? apiOverride;

  @override
  State<StoresHubV2> createState() => _StoresHubV2State();
}

class _StoresHubV2State extends State<StoresHubV2> {
  int _view = 0;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(
        color: SboxColors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: SaSegment<int>(
          value: _view,
          options: const {0: 'Quản lý cửa hàng', 1: 'Chi tiết (cũ)'},
          onChanged: (v) => setState(() => _view = v),
        ),
      ),
      Expanded(child: IndexedStack(index: _view, children: [StoresV2View(apiOverride: widget.apiOverride), widget.legacy])),
    ]);
  }
}

class StoresV2View extends StatefulWidget {
  const StoresV2View({super.key, this.apiOverride});
  final ApiService? apiOverride;

  @override
  State<StoresV2View> createState() => _StoresV2ViewState();
}

class _StoresV2ViewState extends State<StoresV2View> {
  late final ApiService _api = widget.apiOverride ?? ApiService();
  final _search = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  String _status = 'all';
  String? _packageId;
  int _page = 1;
  int _total = 0;
  Map<String, int> _counts = {};
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _packages = [];
  SaCatalog? _catalog;
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
    final rs = await Future.wait([_api.saPackages(), _api.saCatalog()]);
    if (!mounted) return;
    setState(() {
      _packages = rs[0]['data'] is List ? (rs[0]['data'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
      if (rs[1]['data'] is Map) _catalog = SaCatalog.fromJson(Map<String, dynamic>.from(rs[1]['data'] as Map));
    });
    await _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => _loading = true);
    final r = await _api.saStores(status: _status, packageId: _packageId, search: _search.text, page: _page);
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      final d = r['data'];
      if (d is Map) {
        _items = (d['items'] as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
        _total = (d['total'] as num?)?.toInt() ?? 0;
        _counts = {for (final e in (d['counts'] as Map? ?? {}).entries) '${e.key}': (e.value as num).toInt()};
      }
      _selected.removeWhere((id) => !_items.any((s) => s['id'] == id));
    });
  }

  Future<void> _bulk(String action, {List<String>? ids}) async {
    final targets = ids ?? _selected.toList();
    if (targets.isEmpty) return;
    int? days;
    String? packageId;
    String? reason;
    switch (action) {
      case 'extend':
        days = await _askDays();
        if (days == null) return;
      case 'assign-package':
        packageId = await _askPackage();
        if (packageId == null) return;
      case 'lock':
        reason = await _askText('Khóa ${targets.length} cửa hàng', 'Lý do khóa');
        if (reason == null) return;
      case 'unlock':
        if (!await SboxDialogs.confirm(context, title: 'Mở khóa ${targets.length} cửa hàng?', confirmLabel: 'Mở khóa')) return;
    }
    final r = await _api.saBulkStores({'ids': targets, 'action': action, 'days': days ?? 0, 'packageId': packageId, 'reason': reason});
    if (!mounted) return;
    if (saOk(context, r, 'Đã cập nhật ${(r['data'] is Map ? r['data']['updated'] : targets.length)} cửa hàng')) {
      _selected.clear();
      _load();
    }
  }

  Future<int?> _askDays() async {
    final ctrl = TextEditingController(text: '30');
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Gia hạn cửa hàng')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 6, children: [
            for (final d in const [7, 30, 90, 180, 365])
              ActionChip(label: Text('$d ngày'), onPressed: () => ctrl.text = '$d'),
          ]),
          const SizedBox(height: 12),
          TextField(controller: ctrl, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: saInput('Số ngày cộng thêm', suffix: 'ngày', helper: 'Cộng vào hạn hiện tại (hoặc từ hôm nay nếu đã hết hạn)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text)), child: Text(tr('Gia hạn'))),
        ],
      ),
    );
  }

  Future<String?> _askPackage() => showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: Text(tr('Chọn gói dịch vụ')),
          children: [
            for (final p in _packages.where((p) => p['isActive'] == true))
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, '${p['id']}'),
                child: Text('${p['name']} · ${saProductLineLabel('${p['productLine']}')}'),
              ),
          ],
        ),
      );

  Future<String?> _askText(String title, String label) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(title)),
        content: TextField(controller: ctrl, autofocus: true, decoration: saInput(label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => ctrl.text.trim().isEmpty ? null : Navigator.pop(ctx, ctrl.text.trim()), child: Text(tr('Xác nhận'))),
        ],
      ),
    );
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
          const SboxPageHeader(title: 'Cửa hàng', subtitle: 'Hạn dùng, gói dịch vụ, chức năng riêng và key kích hoạt'),
          const SizedBox(height: SboxSpace.md),
          SaSegment<String>(
            value: _status,
            options: {for (final e in _statusLabels.entries) e.key: '${e.value} (${_counts[e.key] ?? 0})'},
            onChanged: (v) {
              setState(() {
                _status = v;
                _page = 1;
              });
              _load();
            },
          ),
          const SizedBox(height: SboxSpace.sm),
          Wrap(spacing: SboxSpace.sm, runSpacing: SboxSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(
              width: 280,
              child: TextField(
                controller: _search,
                decoration: saInput('Tìm tên, mã, SĐT, email chủ').copyWith(prefixIcon: const Icon(Icons.search_rounded, size: 18)),
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
              width: 240,
              child: DropdownButtonFormField<String?>(
                initialValue: _packageId,
                isExpanded: true,
                decoration: saInput('Gói dịch vụ'),
                items: [
                  DropdownMenuItem<String?>(value: null, child: Text(tr('Mọi gói'))),
                  for (final p in _packages) DropdownMenuItem<String?>(value: '${p['id']}', child: Text('${p['name']}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) {
                  setState(() {
                    _packageId = v;
                    _page = 1;
                  });
                  _load();
                },
              ),
            ),
            if (_loading) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          const SizedBox(height: SboxSpace.sm),
          if (_selected.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: SboxSpace.sm),
              padding: const EdgeInsets.symmetric(horizontal: SboxSpace.md, vertical: SboxSpace.sm),
              decoration: BoxDecoration(color: SboxColors.brand50, borderRadius: SboxRadius.mdAll, border: Border.all(color: SboxColors.brand100)),
              child: Wrap(spacing: SboxSpace.sm, runSpacing: SboxSpace.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('Đã chọn ${_selected.length}', style: SboxType.bodyStrong(SboxColors.brand800)),
                SboxButton(label: 'Gia hạn', icon: Icons.update, size: SboxButtonSize.sm, onPressed: () => _bulk('extend')),
                SboxButton.secondary(label: 'Đổi gói', icon: Icons.swap_horiz, size: SboxButtonSize.sm, onPressed: () => _bulk('assign-package')),
                SboxButton.secondary(label: 'Mở khóa', icon: Icons.lock_open, size: SboxButtonSize.sm, onPressed: () => _bulk('unlock')),
                SboxButton.danger(label: 'Khóa', icon: Icons.lock_outline, size: SboxButtonSize.sm, onPressed: () => _bulk('lock')),
                TextButton(onPressed: () => setState(_selected.clear), child: Text(tr('Bỏ chọn'))),
              ]),
            ),
          Container(
            decoration: BoxDecoration(color: SboxColors.white, borderRadius: SboxRadius.lgAll, border: Border.all(color: SboxColors.border)),
            clipBehavior: Clip.antiAlias,
            child: _items.isEmpty
                ? (_loading ? const SboxLoading() : const SboxEmptyState(icon: Icons.store_outlined, title: 'Không có cửa hàng phù hợp'))
                : Column(children: [
                    for (var i = 0; i < _items.length; i++) ...[
                      if (i > 0) const Divider(height: 1, color: SboxColors.divider),
                      _row(_items[i]),
                    ],
                  ]),
          ),
          const SizedBox(height: SboxSpace.sm),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text('$_total cửa hàng · trang $_page/$pages', style: SboxType.captionStyle()),
            IconButton(onPressed: _page > 1 ? () { setState(() => _page--); _load(); } : null, icon: const Icon(Icons.chevron_left)),
            IconButton(onPressed: _page < pages ? () { setState(() => _page++); _load(); } : null, icon: const Icon(Icons.chevron_right)),
          ]),
        ]),
      ),
    );
  }

  Widget _row(Map<String, dynamic> s) {
    final id = '${s['id']}';
    final st = '${s['status']}';
    final days = (s['daysLeft'] as num?)?.toInt();
    final mobile = SboxBreakpoints.isMobile(context);
    final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Flexible(child: Text('${s['name']}', style: SboxType.bodyStrong(), maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 6),
        Text('${s['code']}', style: SboxType.captionStyle()),
      ]),
      Text([s['ownerName'], s['ownerPhone'] ?? s['ownerEmail']].whereType<String>().where((e) => e.trim().isNotEmpty).join(' · '),
          style: SboxType.captionStyle(), maxLines: 1, overflow: TextOverflow.ellipsis),
      const SizedBox(height: 4),
      Wrap(spacing: 6, runSpacing: 4, children: [
        SboxStatusChip(label: _statusLabels[st] ?? st, tone: _statusTone(st), dot: true),
        if (s['packageName'] != null) SboxStatusChip(label: '${s['packageName']}', tone: saProductLineTone('${s['productLine']}')),
        SboxStatusChip(
          label: s['expiryDate'] == null ? 'Không thời hạn' : 'Hạn ${saDate(s['expiryDate'])}${days != null ? (days >= 0 ? ' · còn $days ngày' : ' · quá ${-days} ngày') : ''}',
          tone: SboxTone.neutral,
        ),
        SboxStatusChip(label: 'Gia hạn ${s['renewalCount'] ?? 0}/3', tone: ((s['renewalCount'] as num?) ?? 0) >= 3 ? SboxTone.warning : SboxTone.neutral),
        SboxStatusChip(label: (s['maxUsers'] as num?) == 0 ? '${s['users']} tài khoản' : '${s['users']}/${s['maxUsers']} tài khoản', tone: SboxTone.neutral),
        if (((s['extraCount'] as num?) ?? 0) + ((s['blockedCount'] as num?) ?? 0) > 0)
          SboxStatusChip(label: 'Chức năng riêng +${s['extraCount']}/−${s['blockedCount']}', tone: SboxTone.violet),
        if (s['agentName'] != null)
          SboxStatusChip(
              label: '${s['agentName']}'.toLowerCase().startsWith('đại lý') ? '${s['agentName']}' : 'Đại lý ${s['agentName']}',
              tone: SboxTone.neutral),
      ]),
      if (s['isLocked'] == true && s['lockReason'] != null)
        Padding(padding: const EdgeInsets.only(top: 4), child: Text('Khóa: ${s['lockReason']}', style: SboxType.captionStyle(SboxColors.dangerText))),
    ]);
    final actions = Wrap(spacing: 4, children: [
      IconButton(tooltip: tr('Chức năng riêng'), icon: const Icon(Icons.tune_rounded, size: 20), onPressed: () => _modules(s)),
      IconButton(tooltip: tr('Lịch sử key & gia hạn'), icon: const Icon(Icons.vpn_key_outlined, size: 20), onPressed: () => _history(s)),
      IconButton(tooltip: tr('Gia hạn'), icon: const Icon(Icons.update, size: 20), onPressed: () => _bulk('extend', ids: [id])),
      IconButton(
        tooltip: tr(s['isLocked'] == true ? 'Mở khóa' : 'Khóa'),
        icon: Icon(s['isLocked'] == true ? Icons.lock_open : Icons.lock_outline, size: 20, color: s['isLocked'] == true ? SboxColors.success : SboxColors.danger),
        onPressed: () => _bulk(s['isLocked'] == true ? 'unlock' : 'lock', ids: [id]),
      ),
    ]);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 8, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Checkbox(value: _selected.contains(id), onChanged: (v) => setState(() => v == true ? _selected.add(id) : _selected.remove(id))),
        Expanded(child: mobile ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [info, actions]) : info),
        if (!mobile) actions,
      ]),
    );
  }

  Future<void> _modules(Map<String, dynamic> s) async {
    final c = _catalog;
    if (c == null) return;
    final r = await _api.saStoreModules('${s['id']}');
    if (!mounted || r['data'] is! Map) return;
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => StoreModulesDialog(api: _api, catalog: c, store: s, data: Map<String, dynamic>.from(r['data'] as Map)),
    );
    if (changed == true) _load();
  }

  Future<void> _history(Map<String, dynamic> s) async {
    final r = await _api.saLicenseHistory('${s['id']}');
    if (!mounted || r['data'] is! Map) return;
    final d = Map<String, dynamic>.from(r['data'] as Map);
    final keys = (d['keys'] as List? ?? []).whereType<Map>().toList();
    final events = (d['events'] as List? ?? []).whereType<Map>().toList();
    final store = d['store'] is Map ? d['store'] as Map : const {};
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Key & gia hạn — ${s['name']}')),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('Đã gia hạn ${store['renewalCount'] ?? 0}/${d['maxRenewals'] ?? 3} lần · hạn ${saDate(store['expiryDate'])}', style: SboxType.bodyStrong()),
              const SizedBox(height: 12),
              Text(tr('Key đã kích hoạt'), style: SboxType.captionStyle()),
              if (keys.isEmpty) Text(tr('Chưa kích hoạt key nào'), style: SboxType.smallStyle()),
              for (final k in keys)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.vpn_key_outlined, size: 18),
                  title: Text('${k['key']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
                  subtitle: Text('${saDate(k['activatedAt'])} · +${k['durationDays']} ngày · ${k['packageName'] ?? k['licenseType']}'
                      '${k['agentName'] != null ? ' · đại lý ${k['agentName']}' : ''}'),
                ),
              const SizedBox(height: 8),
              Text(tr('Nhật ký'), style: SboxType.captionStyle()),
              for (final e in events)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('${saDate(e['timestamp'])} · ${e['details'] ?? e['action']} · ${e['userEmail'] ?? ''}', style: SboxType.smallStyle()),
                ),
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng')))],
      ),
    );
  }
}

/// Chức năng riêng của cửa hàng: cấp thêm ngoài gói / chặn dù gói có.
class StoreModulesDialog extends StatefulWidget {
  const StoreModulesDialog({super.key, required this.api, required this.catalog, required this.store, required this.data});
  final ApiService api;
  final SaCatalog catalog;
  final Map<String, dynamic> store;
  final Map<String, dynamic> data;

  @override
  State<StoreModulesDialog> createState() => _StoreModulesDialogState();
}

class _StoreModulesDialogState extends State<StoreModulesDialog> {
  late final Set<String> pkg = {...(widget.data['package'] as List? ?? []).map((e) => '$e'.toLowerCase())};
  late final Set<String> extra = {...(widget.data['extra'] as List? ?? []).map((e) => '$e')};
  late final Set<String> blocked = {...(widget.data['blocked'] as List? ?? []).map((e) => '$e')};
  late final _note = TextEditingController(text: '${widget.data['adminNote'] ?? ''}');
  String _q = '';
  bool _saving = false;

  bool _inPkg(String c) => pkg.contains(c.toLowerCase());
  bool _on(String c) => (_inPkg(c) || extra.contains(c)) && !blocked.contains(c);

  void _set(String code, bool on) => setState(() {
        if (_inPkg(code)) {
          on ? blocked.remove(code) : blocked.add(code);
        } else {
          on ? extra.add(code) : extra.remove(code);
        }
      });

  @override
  Widget build(BuildContext context) {
    final c = widget.catalog;
    final q = _q.toLowerCase();
    final mods = c.modules.where((m) => q.isEmpty || '${m.name} ${m.category}'.toLowerCase().contains(q)).toList();
    return AlertDialog(
      title: Text(tr('Chức năng riêng — ${widget.store['name']}')),
      content: SizedBox(
        width: 620,
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Gói: ${widget.data['packageName'] ?? '—'} · cấp thêm ${extra.length} · chặn ${blocked.length}', style: SboxType.smallStyle()),
          const SizedBox(height: 8),
          TextField(decoration: saInput('Tìm chức năng').copyWith(prefixIcon: const Icon(Icons.search, size: 18)), onChanged: (v) => setState(() => _q = v)),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(children: [
              for (final m in mods)
                CheckboxListTile(
                  dense: true,
                  value: _on(m.code),
                  onChanged: (v) => _set(m.code, v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(tr(m.name)),
                  subtitle: Text(m.category, style: SboxType.captionStyle()),
                  secondary: extra.contains(m.code)
                      ? const SboxStatusChip(label: 'Cấp thêm', tone: SboxTone.success)
                      : blocked.contains(m.code)
                          ? const SboxStatusChip(label: 'Chặn', tone: SboxTone.danger)
                          : _inPkg(m.code)
                              ? const SboxStatusChip(label: 'Theo gói', tone: SboxTone.neutral)
                              : null,
                ),
            ]),
          ),
          TextField(controller: _note, maxLines: 2, decoration: saInput('Ghi chú nội bộ (lý do cấp riêng…)')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Hủy'))),
        FilledButton(
          onPressed: _saving
              ? null
              : () async {
                  setState(() => _saving = true);
                  final r = await widget.api.saSaveStoreModules('${widget.store['id']}', {
                    'extra': extra.toList(),
                    'blocked': blocked.toList(),
                    'adminNote': _note.text.trim(),
                  });
                  if (!context.mounted) return;
                  setState(() => _saving = false);
                  if (saOk(context, r, 'Đã lưu chức năng riêng')) Navigator.pop(context, true);
                },
          child: Text(tr('Lưu')),
        ),
      ],
    );
  }
}
