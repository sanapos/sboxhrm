import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../widgets/sbox/sbox_ui.dart';
import '../attendance_approval_screen.dart';
import 'aa_common.dart';
import 'aa_detail.dart';

/// Duyệt chấm công v2 — một hộp duyệt cho chấm công Mobile ngoài vị trí và yêu cầu sửa/bổ sung công.
class AttendanceApprovalHubScreen extends StatefulWidget {
  const AttendanceApprovalHubScreen({super.key, this.enableMapTiles = true, this.initialSettings = false, this.autoOpenFirst = true});

  /// Tắt tải ô bản đồ (dùng khi chạy thử).
  final bool enableMapTiles;
  final bool initialSettings;

  /// Máy tính: tự mở yêu cầu đầu tiên ở khung bên phải.
  final bool autoOpenFirst;

  @override
  State<AttendanceApprovalHubScreen> createState() => _AttendanceApprovalHubScreenState();
}

class _AttendanceApprovalHubScreenState extends State<AttendanceApprovalHubScreen> {
  final _api = ApiService();
  final _search = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  bool _settingsTab = false;
  List<AaItem> _items = [];
  AaCounts _counts = AaCounts(const {});
  Map<String, int> _stats = {};
  String _kind = '';
  String _risk = '';
  final Set<String> _selected = {};
  AaItem? _active;
  bool _bulkBusy = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _settingsTab = widget.initialSettings;
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() => _loading = true);
    final r = await _api.getAttendanceApprovalInbox(kind: _kind, risk: _risk, search: _search.text);
    if (!mounted || seq != _seq) return;
    setState(() {
      _loading = false;
      final d = r['data'];
      if (r['isSuccess'] == true && d is Map) {
        _items = (d['items'] as List? ?? []).whereType<Map>().map((e) => AaItem.fromJson(Map<String, dynamic>.from(e))).toList();
        _counts = AaCounts(d['counts'] is Map ? Map<String, dynamic>.from(d['counts'] as Map) : {});
        _stats = {
          for (final s in (d['stats30'] as List? ?? []).whereType<Map>()) '${s['status']}': (s['count'] as num?)?.toInt() ?? 0,
        };
      } else {
        _items = [];
      }
      _selected.removeWhere((id) => !_items.any((i) => i.id == id));
      if (_active != null && !_items.any((i) => i.id == _active!.id)) _active = null;
    });
  }

  bool get _wide => MediaQuery.sizeOf(context).width >= 1100;

  void _open(AaItem it) {
    if (_wide) {
      setState(() => _active = it);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (ctx) => Scaffold(
        backgroundColor: SboxColors.white,
        appBar: AppBar(title: Text(tr('Chi tiết duyệt')), backgroundColor: SboxColors.white, surfaceTintColor: SboxColors.white),
        body: AaDetailPane(
          item: it,
          api: _api,
          compact: true,
          enableMapTiles: widget.enableMapTiles,
          onDecided: () {
            Navigator.of(ctx).pop();
            _load();
          },
        ),
      ),
    ));
  }

  Future<void> _approveTrusted() async {
    final n = _counts.c('trusted');
    final ok = await SboxDialogs.confirm(context,
        title: 'Duyệt $n bản chấm tin cậy?',
        message: 'Chỉ duyệt các bản gần vị trí khai báo, khuôn mặt khớp, GPS tốt. Bản cần xem / rủi ro cao và chấm đi đường vẫn để lại.',
        confirmLabel: 'Duyệt tất cả tin cậy',
        icon: Icons.verified_outlined);
    if (!ok || !mounted) return;
    setState(() => _bulkBusy = true);
    final r = await _api.mobileApproveTrusted();
    if (!mounted) return;
    setState(() => _bulkBusy = false);
    _toastBulk(r, 'Đã duyệt');
    _load();
  }

  void _toastBulk(Map<String, dynamic> r, String verb) {
    final d = r['data'];
    if (r['isSuccess'] == true && d is Map) {
      final errs = (d['errors'] as List? ?? []);
      aaToast(context, '$verb ${d['success']} bản${errs.isNotEmpty ? ' · ${errs.length} lỗi: ${errs.first}' : ''}', error: errs.isNotEmpty);
    } else {
      aaToast(context, '${r['message'] ?? 'Không thực hiện được'}', error: true);
    }
  }

  Future<void> _bulk(bool approve) async {
    final items = _items.where((i) => _selected.contains(i.id)).toList();
    String? reason;
    if (!approve) {
      reason = await aaAskRejectReason(context, title: 'Từ chối ${items.length} yêu cầu');
      if (reason == null) return;
    } else {
      final ok = await SboxDialogs.confirm(context, title: 'Duyệt ${items.length} yêu cầu đã chọn?', confirmLabel: 'Duyệt');
      if (!ok) return;
    }
    if (!mounted) return;
    setState(() => _bulkBusy = true);
    final mobileIds = items.where((i) => i.isMobile).map((i) => i.id).toList();
    var okCount = 0;
    final errors = <String>[];
    if (mobileIds.isNotEmpty) {
      final r = await _api.mobileApproveBulk(mobileIds, approved: approve, reason: reason);
      final d = r['data'];
      if (r['isSuccess'] == true && d is Map) {
        okCount += (d['success'] as num?)?.toInt() ?? 0;
        errors.addAll((d['errors'] as List? ?? []).map((e) => '$e'));
      } else {
        errors.add('${r['message'] ?? 'Lỗi duyệt chấm công mobile'}');
      }
    }
    for (final c in items.where((i) => !i.isMobile)) {
      final r = await _api.approveAttendanceCorrection(requestId: c.id, isApproved: approve, approverNote: reason);
      if (r['isSuccess'] == true) {
        okCount++;
      } else {
        errors.add('${c.employeeName}: ${r['message'] ?? 'lỗi'}');
      }
    }
    if (!mounted) return;
    setState(() {
      _bulkBusy = false;
      _selected.clear();
    });
    aaToast(context, '${approve ? 'Đã duyệt' : 'Đã từ chối'} $okCount/${items.length}${errors.isEmpty ? '' : ' · ${errors.first}'}',
        error: errors.isNotEmpty);
    _load();
  }

  void _openLegacy() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text(tr('Duyệt chấm công (giao diện cũ)'))),
        body: const AttendanceApprovalScreen(),
      ),
    ));
  }

  // ─── Khung ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = SboxSpace.pagePadding(w);
    final wide = _wide;
    if (wide && widget.autoOpenFirst && _active == null && _items.isNotEmpty && !_settingsTab) {
      _active = _items.first;
    }

    final header = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SboxPageHeader(
        title: 'Duyệt chấm công',
        subtitle: 'Chấm công Mobile ngoài vị trí · yêu cầu sửa / bổ sung công',
        actions: [
          if (_counts.c('trusted') > 0 && !_settingsTab)
            SboxButton(
              label: 'Duyệt ${_counts.c('trusted')} bản tin cậy',
              icon: Icons.verified_outlined,
              loading: _bulkBusy,
              onPressed: _bulkBusy ? null : _approveTrusted,
            ),
          SboxButton.ghost(label: 'Giao diện cũ', icon: Icons.history_rounded, onPressed: _openLegacy),
        ],
      ),
      const SizedBox(height: SboxSpace.md),
      Row(children: [
        _Pill(label: 'Cần duyệt', icon: Icons.fact_check_outlined, selected: !_settingsTab, badge: _counts.c('all'), onTap: () {
          setState(() => _settingsTab = false);
          _load();
        }),
        const SizedBox(width: SboxSpace.xs),
        _Pill(label: 'Cài đặt duyệt', icon: Icons.tune_rounded, selected: _settingsTab, onTap: () => setState(() => _settingsTab = true)),
      ]),
      const SizedBox(height: SboxSpace.md),
    ]);

    if (_settingsTab) {
      return ColoredBox(
        color: SboxColors.page,
        child: ListView(padding: EdgeInsets.all(pad), children: [header, _AaSettingsView(api: _api)]),
      );
    }

    final decided = (_stats['approved'] ?? 0) + (_stats['auto_approved'] ?? 0) + (_stats['rejected'] ?? 0);
    final autoPct = decided == 0 ? null : ((_stats['auto_approved'] ?? 0) * 100 / decided).round();
    final kpis = SboxKpiStrip(maxColumns: 5, items: [
      SboxKpi(label: 'Chờ duyệt', value: '${_counts.c('all')}', icon: Icons.inbox_outlined, note: '${_counts.c('correction')} yêu cầu sửa công'),
      SboxKpi(label: 'Chấm ngoài vị trí', value: '${_counts.c('outside')}', icon: Icons.wrong_location_outlined, tone: SboxTone.brand),
      SboxKpi(label: 'Tin cậy', value: '${_counts.c('trusted')}', icon: Icons.verified_outlined, tone: SboxTone.success, note: 'Có thể duyệt nhanh'),
      SboxKpi(label: 'Rủi ro cao', value: '${_counts.c('high')}', icon: Icons.gpp_maybe_outlined, tone: SboxTone.danger),
      SboxKpi(
          label: 'Quá 24 giờ',
          value: '${_counts.c('overdue')}',
          icon: Icons.schedule,
          tone: SboxTone.warning,
          note: autoPct == null ? null : 'Tự duyệt $autoPct% (30 ngày)'),
    ]);

    final filters = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Segment(
        value: _kind,
        options: {
          '': 'Tất cả (${_counts.c('all')})',
          'mobile': 'Chấm Mobile (${_counts.c('mobile')})',
          'correction': 'Sửa / bổ sung công (${_counts.c('correction')})',
        },
        onChanged: (v) {
          setState(() => _kind = v);
          _load();
        },
      ),
      const SizedBox(height: SboxSpace.sm),
      Row(children: [
        Expanded(
          child: _Segment(
            value: _risk,
            options: const {'': 'Mọi mức', 'trusted': 'Tin cậy', 'review': 'Cần xem', 'high': 'Rủi ro cao'},
            onChanged: (v) {
              setState(() => _risk = v);
              _load();
            },
          ),
        ),
      ]),
      const SizedBox(height: SboxSpace.sm),
      TextField(
        controller: _search,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search_rounded, size: 18),
          hintText: tr('Tìm nhân viên'),
          filled: true,
          fillColor: SboxColors.white,
          border: OutlineInputBorder(borderRadius: SboxRadius.mdAll, borderSide: const BorderSide(color: SboxColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: SboxRadius.mdAll, borderSide: const BorderSide(color: SboxColors.border)),
        ),
        onChanged: (_) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(milliseconds: 350), _load);
        },
      ),
    ]);

    final bulkBar = _selected.isEmpty
        ? null
        : Container(
            margin: const EdgeInsets.only(bottom: SboxSpace.sm),
            padding: const EdgeInsets.symmetric(horizontal: SboxSpace.md, vertical: SboxSpace.sm),
            decoration: BoxDecoration(color: SboxColors.brand50, borderRadius: SboxRadius.mdAll, border: Border.all(color: SboxColors.brand100)),
            child: Row(children: [
              Expanded(child: Text('Đã chọn ${_selected.length}', style: SboxType.bodyStrong(SboxColors.brand800))),
              SboxButton.danger(label: 'Từ chối', size: SboxButtonSize.sm, onPressed: _bulkBusy ? null : () => _bulk(false)),
              const SizedBox(width: SboxSpace.sm),
              SboxButton(label: 'Duyệt', size: SboxButtonSize.sm, loading: _bulkBusy, onPressed: _bulkBusy ? null : () => _bulk(true)),
            ]),
          );

    final list = Container(
      decoration: BoxDecoration(color: SboxColors.white, borderRadius: SboxRadius.lgAll, border: Border.all(color: SboxColors.border)),
      clipBehavior: Clip.antiAlias,
      child: _loading && _items.isEmpty
          ? const SboxLoading()
          : _items.isEmpty
              ? const SboxEmptyState(
                  icon: Icons.task_alt_rounded,
                  title: 'Không còn yêu cầu chờ duyệt',
                  message: 'Chấm công ngoài vị trí và yêu cầu sửa công mới sẽ hiện ở đây')
              : Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
                    child: Row(children: [
                      Checkbox(
                        value: _selected.isEmpty ? false : (_selected.length == _items.length ? true : null),
                        tristate: true,
                        visualDensity: VisualDensity.compact,
                        onChanged: (_) => setState(() {
                          if (_selected.length == _items.length) {
                            _selected.clear();
                          } else {
                            _selected
                              ..clear()
                              ..addAll(_items.map((e) => e.id));
                          }
                        }),
                      ),
                      Text(tr('Chọn tất cả'), style: SboxType.smallStyle()),
                      const Spacer(),
                      Text('${_items.length} yêu cầu', style: SboxType.captionStyle()),
                    ]),
                  ),
                  const Divider(height: 1),
                  for (var i = 0; i < _items.length; i++) ...[
                    if (i > 0) const Divider(height: 1, color: SboxColors.divider),
                    AaListTile(
                      item: _items[i],
                      selected: _selected.contains(_items[i].id),
                      active: wide && _active?.id == _items[i].id,
                      onTap: () => _open(_items[i]),
                      onSelect: (v) => setState(() => v ? _selected.add(_items[i].id) : _selected.remove(_items[i].id)),
                    ),
                  ],
                ]),
    );

    if (wide) {
      return ColoredBox(
        color: SboxColors.page,
        child: ListView(padding: EdgeInsets.all(pad), children: [
          header,
          kpis,
          const SizedBox(height: SboxSpace.md),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 440,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                filters,
                const SizedBox(height: SboxSpace.md),
                if (bulkBar != null) bulkBar,
                list,
              ]),
            ),
            const SizedBox(width: SboxSpace.lg),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(SboxSpace.lg),
                decoration: BoxDecoration(color: SboxColors.white, borderRadius: SboxRadius.lgAll, border: Border.all(color: SboxColors.border)),
                child: _active == null
                    ? const SboxEmptyState(icon: Icons.touch_app_outlined, title: 'Chọn một yêu cầu để xem chi tiết')
                    : AaDetailPane(
                        key: ValueKey(_active!.id),
                        item: _active!,
                        api: _api,
                        enableMapTiles: widget.enableMapTiles,
                        onDecided: () {
                          final idx = _items.indexWhere((e) => e.id == _active!.id);
                          setState(() => _active = idx >= 0 && idx + 1 < _items.length ? _items[idx + 1] : null);
                          _load();
                        },
                      ),
              ),
            ),
          ]),
        ]),
      );
    }

    return ColoredBox(
      color: SboxColors.page,
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: EdgeInsets.all(pad), children: [
          header,
          kpis,
          const SizedBox(height: SboxSpace.md),
          filters,
          const SizedBox(height: SboxSpace.md),
          if (bulkBar != null) bulkBar,
          list,
        ]),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.icon, required this.selected, required this.onTap, this.badge});
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? SboxColors.brand600 : SboxColors.white,
      shape: StadiumBorder(side: BorderSide(color: selected ? SboxColors.brand600 : SboxColors.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: selected ? SboxColors.white : SboxColors.slate500),
            const SizedBox(width: 6),
            Text(tr(label), style: SboxType.smallStyle(selected ? SboxColors.white : SboxColors.text).copyWith(fontWeight: FontWeight.w600)),
            if (badge != null && badge! > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: selected ? SboxColors.white : SboxColors.danger, borderRadius: SboxRadius.pillAll),
                child: Text('$badge',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: selected ? SboxColors.brand700 : SboxColors.white)),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({required this.value, required this.options, required this.onChanged});
  final String value;
  final Map<String, String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final e in options.entries)
          Padding(
            padding: const EdgeInsets.only(right: SboxSpace.xs),
            child: ChoiceChip(
              label: Text(tr(e.value)),
              selected: e.key == value,
              showCheckmark: false,
              onSelected: (_) => onChanged(e.key),
              labelStyle: SboxType.smallStyle(e.key == value ? SboxColors.brand700 : SboxColors.textSecondary)
                  .copyWith(fontWeight: e.key == value ? FontWeight.w600 : FontWeight.w500),
              selectedColor: SboxColors.brand50,
              backgroundColor: SboxColors.white,
              side: BorderSide(color: e.key == value ? SboxColors.brand300 : SboxColors.border),
              shape: const StadiumBorder(),
            ),
          ),
      ]),
    );
  }
}

// ─── Cài đặt duyệt ─────────────────────────────────────────────────

class _AaSettingsView extends StatefulWidget {
  const _AaSettingsView({required this.api});
  final ApiService api;

  @override
  State<_AaSettingsView> createState() => _AaSettingsViewState();
}

class _AaSettingsViewState extends State<_AaSettingsView> {
  bool _loading = true;
  bool _saving = false;
  bool _auto = true;
  final _dist = TextEditingController(text: '300');
  final _face = TextEditingController(text: '85');
  final _days = TextEditingController(text: '30');
  List<Map<String, dynamic>> _devices = [];
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rs = await Future.wait([widget.api.getMobileApprovalSettings(), widget.api.getOutsideReasonDevices()]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      final s = rs[0]['data'];
      if (s is Map) {
        _auto = s['autoApproveTrusted'] != false;
        _dist.text = '${(s['trustedMaxDistanceMeters'] as num?)?.toInt() ?? 300}';
        _face.text = '${(s['trustedMinFaceScore'] as num?)?.round() ?? 85}';
        _days.text = '${(s['evidenceRetentionDays'] as num?)?.toInt() ?? 30}';
      }
      final d = rs[1]['data'];
      _devices = d is List ? d.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : [];
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final r = await widget.api.saveMobileApprovalSettings({
      'autoApproveTrusted': _auto,
      'trustedMaxDistanceMeters': int.tryParse(_dist.text.trim()) ?? 300,
      'trustedMinFaceScore': double.tryParse(_face.text.trim()) ?? 85,
      'evidenceRetentionDays': int.tryParse(_days.text.trim()) ?? 30,
    });
    if (!mounted) return;
    setState(() => _saving = false);
    aaToast(context, r['isSuccess'] == true ? 'Đã lưu cài đặt' : '${r['message'] ?? 'Không lưu được'}', error: r['isSuccess'] != true);
  }

  Future<void> _setReason(List<Map<String, dynamic>> devices, bool v) async {
    final ids = devices.map((d) => '${d['id']}').toList();
    setState(() {
      for (final d in devices) {
        d['requireOutsideReason'] = v;
      }
    });
    final r = await widget.api.setOutsideReasonDevices(ids, v);
    if (!mounted) return;
    if (r['isSuccess'] != true) {
      aaToast(context, '${r['message'] ?? 'Không lưu được'}', error: true);
      _load();
    }
  }

  InputDecoration _dec(String label, String suffix, String helper) => InputDecoration(
        labelText: tr(label),
        suffixText: suffix,
        helperText: tr(helper),
        helperMaxLines: 2,
        isDense: true,
        border: OutlineInputBorder(borderRadius: SboxRadius.mdAll),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SboxLoading();
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final list = _devices
        .where((d) => _q.isEmpty || '${d['employeeName']} ${d['deviceName']}'.toLowerCase().contains(_q.toLowerCase()))
        .toList();
    final onCount = _devices.where((d) => d['requireOutsideReason'] == true).length;

    final auto = SboxCard(
      title: 'Tự duyệt chấm công tin cậy',
      subtitle: 'Bản chấm ngoài vị trí đạt đủ điều kiện được duyệt ngay, không cần chờ quản lý',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SwitchListTile(
          value: _auto,
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Bật tự duyệt'), style: SboxType.bodyStrong()),
          subtitle: Text(tr('Chấm đi đường luôn cần duyệt tay'), style: SboxType.captionStyle()),
          onChanged: (v) => setState(() => _auto = v),
        ),
        const SizedBox(height: SboxSpace.sm),
        Row(children: [
          Expanded(child: TextField(controller: _dist, keyboardType: TextInputType.number, decoration: _dec('Cách vị trí tối đa', 'm', 'Tính tới vị trí khai báo gần nhất'))),
          const SizedBox(width: SboxSpace.sm),
          Expanded(child: TextField(controller: _face, keyboardType: TextInputType.number, decoration: _dec('Khớp mặt tối thiểu', '%', 'Dưới mức này cần duyệt tay'))),
        ]),
        const SizedBox(height: SboxSpace.md),
        TextField(controller: _days, keyboardType: TextInputType.number, decoration: _dec('Giữ ảnh bằng chứng', 'ngày', 'Sau khi duyệt/từ chối, ảnh hiện trường tự xóa khi hết hạn')),
        const SizedBox(height: SboxSpace.md),
        Container(
          padding: const EdgeInsets.all(SboxSpace.md),
          decoration: BoxDecoration(color: SboxColors.slate50, borderRadius: SboxRadius.mdAll),
          child: Text(
            tr('«Tin cậy» = gần vị trí khai báo + khớp khuôn mặt + GPS tốt + có ảnh hiện trường, không lệch ca nhiều. '
                'Bản «cần xem» và «rủi ro cao» vẫn gửi quản lý trực tiếp duyệt.'),
            style: SboxType.captionStyle(),
          ),
        ),
        const SizedBox(height: SboxSpace.md),
        Align(alignment: Alignment.centerRight, child: SboxButton(label: 'Lưu cài đặt', icon: Icons.save_outlined, loading: _saving, onPressed: _save)),
      ]),
    );

    final reason = SboxCard(
      title: 'Bắt buộc nhập lý do khi chấm ngoài vị trí',
      subtitle: 'Chọn nhân viên nào phải ghi lý do ($onCount/${_devices.length} đang bật)',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                hintText: tr('Tìm nhân viên'),
                border: OutlineInputBorder(borderRadius: SboxRadius.mdAll),
              ),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          const SizedBox(width: SboxSpace.sm),
          SboxButton.ghost(label: 'Bật tất cả', size: SboxButtonSize.sm, onPressed: list.isEmpty ? null : () => _setReason(list, true)),
          SboxButton.ghost(label: 'Tắt tất cả', size: SboxButtonSize.sm, onPressed: list.isEmpty ? null : () => _setReason(list, false)),
        ]),
        const SizedBox(height: SboxSpace.sm),
        if (list.isEmpty)
          const SboxEmptyState(icon: Icons.smartphone, title: 'Chưa có máy chấm công mobile được duyệt')
        else
          for (final d in list)
            Container(
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: SboxColors.divider))),
              child: SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: d['requireOutsideReason'] == true,
                onChanged: (v) => _setReason([d], v),
                secondary: AaAvatar(name: '${d['employeeName'] ?? ''}', size: 34),
                title: Text('${d['employeeName'] ?? ''}', style: SboxType.bodyStrong()),
                subtitle: Wrap(spacing: 6, children: [
                  Text('${d['deviceName'] ?? ''}', style: SboxType.captionStyle()),
                  if (d['allowOutsideCheckIn'] == true) Text('· ${tr('được chấm ngoài')}', style: SboxType.captionStyle(SboxColors.brand700)),
                  if (d['requirePhotoProof'] == true) Text('· ${tr('bắt buộc ảnh')}', style: SboxType.captionStyle()),
                ]),
              ),
            ),
      ]),
    );

    if (wide) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: auto),
        const SizedBox(width: SboxSpace.md),
        Expanded(child: reason),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [auto, const SizedBox(height: SboxSpace.md), reason]);
  }
}
