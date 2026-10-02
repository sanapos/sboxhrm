import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_tr.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../widgets/sbox/sbox_ui.dart';
import 'accounts_v2/ac_common.dart' show agoText;

/// Thiết bị truy cập: mỗi điện thoại / trình duyệt / máy POS đăng nhập chiếm 1 chỗ theo gói.
/// Gỡ máy không dùng để máy mới vào được; máy bị gỡ phải đăng nhập lại.
class StoreAccessDevicesScreen extends StatefulWidget {
  const StoreAccessDevicesScreen({super.key, this.canEditOverride});

  /// Bỏ qua kiểm quyền (dùng cho test).
  final bool? canEditOverride;

  @override
  State<StoreAccessDevicesScreen> createState() => _StoreAccessDevicesScreenState();
}

/// Máy không thấy hoạt động quá số ngày này coi là «lâu không dùng».
const _staleDays = 30;

class _Device {
  _Device(this.m);
  final Map<String, dynamic> m;
  String get id => '${m['id'] ?? m['Id'] ?? ''}';
  String get platform => '${m['platform'] ?? m['Platform'] ?? ''}'.toLowerCase();
  String? get name => (m['deviceName'] ?? m['DeviceName'])?.toString();
  String? get user => (m['userName'] ?? m['UserName'])?.toString();
  String get key => '${m['deviceKey'] ?? m['DeviceKey'] ?? ''}';
  bool get isThis => m['isThisDevice'] == true || m['IsThisDevice'] == true;
  DateTime? get lastSeen => DateTime.tryParse('${m['lastSeenAt'] ?? m['LastSeenAt'] ?? ''}');
  bool get stale => lastSeen != null && DateTime.now().difference(lastSeen!.toLocal()).inDays >= _staleDays;

  String get platformLabel => switch (platform) {
        'web' || 'browser' || 'desktop' => 'Trình duyệt web',
        'pos' => 'Máy bán hàng POS',
        'android' => 'Điện thoại Android',
        'ios' => 'iPhone / iPad',
        '' => 'Khác',
        _ => platform,
      };

  IconData get icon => switch (platform) {
        'web' || 'browser' || 'desktop' => Icons.language_rounded,
        'pos' => Icons.point_of_sale_rounded,
        'ios' => Icons.phone_iphone_rounded,
        _ => Icons.smartphone_rounded,
      };
}

class _StoreAccessDevicesScreenState extends State<StoreAccessDevicesScreen> {
  final _api = ApiService();
  bool _loading = true;
  String? _error;
  int _used = 0;
  int _max = 0;
  bool _unlimited = true;
  List<_Device> _items = [];
  final Set<String> _busy = {};
  String _platform = 'all';

  bool get _canEdit {
    if (widget.canEditOverride != null) return widget.canEditOverride!;
    try {
      final p = Provider.of<PermissionProvider>(context, listen: false);
      return p.canEditPosSetup() || p.canEdit('SystemSettings') || p.canEdit('UserManagement');
    } catch (_) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getStoreAccessDevices();
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? 'Không tải được danh sách thiết bị';
      });
      return;
    }
    final data = Map<String, dynamic>.from(res['data'] as Map);
    final raw = data['items'] ?? data['Items'];
    int asInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    setState(() {
      _used = asInt(data['used'] ?? data['Used']);
      _max = asInt(data['max'] ?? data['Max']);
      _unlimited = data['unlimited'] == true || data['Unlimited'] == true || _max <= 0;
      _items = [for (final e in (raw is List ? raw : const [])) if (e is Map) _Device(Map<String, dynamic>.from(e))];
      _loading = false;
    });
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr(title)),
          content: SizedBox(width: 420, child: Text(tr(body))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr(action))),
          ],
        ),
      ) ==
      true;

  Future<bool> _releaseOne(_Device d) async {
    setState(() => _busy.add(d.id));
    final res = await _api.releaseStoreAccessDevice(d.id);
    if (!mounted) return false;
    setState(() => _busy.remove(d.id));
    return res['isSuccess'] == true;
  }

  Future<void> _release(_Device d) async {
    final label = d.name == null || d.name!.isEmpty ? d.platformLabel : '${d.name} (${d.platformLabel})';
    final ok = await _confirm(
      d.isThis ? 'Gỡ máy đang dùng?' : 'Gỡ $label?',
      d.isThis
          ? 'Đây là máy bạn đang dùng. Sau khi gỡ, bạn sẽ phải đăng nhập lại và máy chiếm lại 1 chỗ nếu gói còn chỗ.'
          : 'Máy này sẽ bị đăng xuất và phải đăng nhập lại mới dùng được. Chỗ trống được trả lại cho gói ngay.',
      'Gỡ thiết bị',
    );
    if (!ok) return;
    if (await _releaseOne(d)) {
      _toast('Đã gỡ thiết bị — chỗ trống đã được trả lại.');
      await _load();
    } else {
      _toast('Không gỡ được thiết bị. Thử lại.', error: true);
    }
  }

  Future<void> _releaseStale() async {
    final stale = _items.where((d) => d.stale && !d.isThis).toList();
    final ok = await _confirm(
      'Gỡ ${stale.length} máy lâu không dùng?',
      'Các máy không hoạt động từ $_staleDays ngày trở lên sẽ bị đăng xuất. Nếu vẫn cần dùng, chỉ việc đăng nhập lại.',
      'Gỡ ${stale.length} máy',
    );
    if (!ok) return;
    var done = 0;
    for (final d in stale) {
      if (await _releaseOne(d)) done++;
    }
    if (!mounted) return;
    _toast('Đã gỡ $done/${stale.length} máy.', error: done < stale.length);
    await _load();
  }

  void _toast(String m, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(m)),
        backgroundColor: error ? SboxColors.danger : null,
        behavior: SnackBarBehavior.floating,
      ));

  @override
  Widget build(BuildContext context) {
    if (_loading && _items.isEmpty) return const SboxLoading(message: 'Đang tải thiết bị…');
    if (_error != null && _items.isEmpty) {
      return SboxEmptyState(
        icon: Icons.cloud_off_rounded,
        title: _error!,
        action: SboxButton.secondary(label: 'Thử lại', icon: Icons.refresh_rounded, onPressed: _load),
      );
    }
    final narrow = MediaQuery.of(context).size.width < 700;
    final platforms = {for (final d in _items) d.platform}.toList()..sort();
    final shown = _platform == 'all' ? _items : _items.where((d) => d.platform == _platform).toList();
    final staleCount = _items.where((d) => d.stale && !d.isThis).length;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(narrow ? 12 : 24, 16, narrow ? 12 : 24, 40),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: SboxColors.dangerSoft, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.devices_other_rounded, color: SboxColors.dangerText),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr('Thiết bị truy cập'), style: SboxType.headlineStyle()),
                      Text(tr('Mỗi điện thoại, trình duyệt hoặc máy POS đã đăng nhập chiếm 1 chỗ theo gói dịch vụ.'),
                          style: SboxType.smallStyle()),
                    ]),
                  ),
                ]),
                const SizedBox(height: 16),
                _quota(),
                if (_canEdit && staleCount > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                    decoration: BoxDecoration(color: SboxColors.warningSoft, borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      const Icon(Icons.history_toggle_off_rounded, color: SboxColors.warningText),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(tr('$staleCount máy không hoạt động từ $_staleDays ngày trở lên.'),
                            style: SboxType.bodyStrong(SboxColors.warningText)),
                      ),
                      SboxButton.secondary(label: 'Gỡ tất cả', size: SboxButtonSize.sm, onPressed: _releaseStale),
                    ]),
                  ),
                ],
                const SizedBox(height: 16),
                if (platforms.length > 1)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      _chip('Tất cả (${_items.length})', 'all'),
                      for (final p in platforms)
                        _chip('${_items.firstWhere((d) => d.platform == p).platformLabel} (${_items.where((d) => d.platform == p).length})', p),
                    ]),
                  ),
                const SizedBox(height: 8),
                if (shown.isEmpty)
                  const SboxCard(child: SboxEmptyState(icon: Icons.devices_rounded, title: 'Chưa có thiết bị nào đăng nhập'))
                else
                  Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: SboxColors.border)),
                    child: Column(children: [
                      for (var i = 0; i < shown.length; i++) ...[
                        if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                        _row(shown[i]),
                      ],
                    ]),
                  ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, String value) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(label: Text(tr(label)), selected: _platform == value, showCheckmark: false, onSelected: (_) => setState(() => _platform = value)),
      );

  Widget _quota() {
    final full = !_unlimited && _used >= _max;
    final ratio = _unlimited ? 0.0 : (_used / _max).clamp(0.0, 1.0);
    final color = full ? SboxColors.danger : (ratio >= 0.8 ? SboxColors.warning : SboxColors.brand600);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: SboxColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$_used', style: SboxType.displayStyle(color)),
          const SizedBox(width: 6),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(tr(_unlimited ? 'máy · gói không giới hạn' : '/ $_max máy theo gói'), style: SboxType.bodyStyle(SboxColors.textSecondary)),
          ),
          const Spacer(),
          if (full) const SboxStatusChip(label: 'Đã đầy', tone: SboxTone.danger, icon: Icons.block_rounded),
        ]),
        if (!_unlimited) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(value: ratio, minHeight: 8, color: color, backgroundColor: SboxColors.slate100),
          ),
          const SizedBox(height: 8),
          Text(
            tr(full
                ? 'Máy mới sẽ không đăng nhập được. Gỡ máy không dùng hoặc nâng cấp gói.'
                : 'Còn ${_max - _used} chỗ cho máy mới.'),
            style: SboxType.smallStyle(full ? SboxColors.dangerText : SboxColors.textSecondary),
          ),
        ],
      ]),
    );
  }

  Widget _row(_Device d) {
    final busy = _busy.contains(d.id);
    final title = d.name == null || d.name!.isEmpty ? d.platformLabel : '${d.name} · ${d.platformLabel}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: d.stale ? SboxColors.slate100 : SboxColors.brand50, borderRadius: BorderRadius.circular(10)),
          child: Icon(d.icon, color: d.stale ? SboxColors.slate500 : SboxColors.brand700, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(tr(title), style: SboxType.bodyStrong()),
              if (d.isThis) const SboxStatusChip(label: 'Máy này', tone: SboxTone.success),
              if (d.stale) const SboxStatusChip(label: 'Lâu không dùng', tone: SboxTone.warning),
            ]),
            const SizedBox(height: 2),
            Text(
              [
                (d.user == null || d.user!.isEmpty) ? 'Chưa rõ tài khoản' : d.user!,
                agoText(d.lastSeen),
                if (d.key.isNotEmpty) 'Mã ${d.key}',
              ].join(' · '),
              style: SboxType.captionStyle(),
            ),
          ]),
        ),
        if (_canEdit)
          busy
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : SboxButton.ghost(label: 'Gỡ', icon: Icons.link_off_rounded, size: SboxButtonSize.sm, onPressed: () => _release(d)),
      ]),
    );
  }
}
