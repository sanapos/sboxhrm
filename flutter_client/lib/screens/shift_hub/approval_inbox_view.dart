import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/notification_overlay.dart';
import 'shift_hub_ui.dart';

/// Một việc chờ duyệt (đã chuẩn hoá từ 4 nguồn).
class _Item {
  _Item({
    required this.kind,
    required this.id,
    required this.name,
    required this.title,
    required this.when,
    this.detail,
    this.createdAt,
    this.sortDate,
  });
  final String kind; // reg | leave | swap | shift
  final String id;
  final String name;
  final String title;
  final String when;
  final String? detail;
  final DateTime? createdAt;
  final DateTime? sortDate;
  String get key => '$kind:$id';
}

/// Hộp «Cần duyệt» chung: đăng ký ca, đơn nghỉ, đổi ca (đồng nghiệp đã đồng ý), ca theo giờ.
/// Lọc theo loại, chọn nhiều để duyệt / từ chối hàng loạt. Dùng các endpoint duyệt sẵn có (giữ chuỗi duyệt).
class ApprovalInboxView extends StatefulWidget {
  const ApprovalInboxView({super.key, this.onChanged});
  final VoidCallback? onChanged;

  @override
  State<ApprovalInboxView> createState() => _ApprovalInboxViewState();
}

class _ApprovalInboxViewState extends State<ApprovalInboxView> {
  final _api = ApiService();
  List<_Item> _items = [];
  bool _loading = true;
  bool _busy = false;
  String _kind = 'all';
  final Set<String> _selected = {};

  static const _kinds = <String, (String, IconData, Color)>{
    'reg': ('Đăng ký ca', Icons.how_to_reg_rounded, SboxColors.brand600),
    'leave': ('Đơn nghỉ', Icons.beach_access_rounded, SboxColors.success),
    'swap': ('Đổi ca', Icons.swap_horiz_rounded, SboxColors.violet),
    'shift': ('Ca theo giờ', Icons.more_time_rounded, SboxColors.warning),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _list(Map<String, dynamic> r) {
    if (r['isSuccess'] != true) return [];
    final d = r['data'];
    final raw = d is List ? d : d is Map ? (d['items'] ?? d['Items'] ?? const []) : const [];
    return [
      for (final x in raw as List)
        if (x is Map) Map<String, dynamic>.from(x),
    ];
  }

  DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
  String _d(dynamic v) {
    final d = _dt(v);
    return d == null ? '' : '${ShiftUi.weekdays[d.weekday - 1]} ${ShiftUi.dmy(d)}';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await Future.wait([
      _api.getScheduleRegistrations(status: 0, pageSize: 300),
      _api.getPendingLeaves(pageSize: 300),
      _api.getShiftSwapsPendingApproval(),
      _api.getPendingShifts(),
    ]);
    if (!mounted) return;
    final items = <_Item>[];
    for (final r in _list(res[0])) {
      if (r['status']?.toString() != 'Pending' && r['status'] != 0) continue;
      items.add(_Item(
        kind: 'reg',
        id: r['id'].toString(),
        name: r['employeeName']?.toString() ?? '',
        title: r['isDayOff'] == true ? 'Xin nghỉ ngày này' : 'Đăng ký ${r['shiftName'] ?? 'ca'}',
        when: _d(r['date']),
        detail: r['note']?.toString(),
        createdAt: _dt(r['createdAt']),
        sortDate: _dt(r['date']),
      ));
    }
    for (final l in _list(res[1])) {
      final from = _dt(l['startDate']), to = _dt(l['endDate']);
      final days = from != null && to != null ? to.difference(from).inDays + 1 : 1;
      items.add(_Item(
        kind: 'leave',
        id: l['id'].toString(),
        name: l['employeeName']?.toString() ?? '',
        title: '${ShiftUi.leaveTypes[l['type']?.toString()] ?? 'Nghỉ phép'}${l['isHalfShift'] == true ? ' (nửa ca)' : ''}',
        when: days <= 1 ? _d(l['startDate']) : '${_d(l['startDate'])} → ${_d(l['endDate'])} ($days ngày)',
        detail: [
          if ((l['reason']?.toString() ?? '').isNotEmpty) 'Lý do: ${l['reason']}',
          if ((l['shiftNames'] as List?)?.isNotEmpty == true) 'Ca: ${(l['shiftNames'] as List).join(', ')}',
          if (l['remainingAnnualLeaveDays'] != null) 'Phép năm còn ${l['remainingAnnualLeaveDays']} ngày',
          if ((ShiftUi.n(l['totalApprovalLevels'])) > 1) 'Bước ${ShiftUi.n(l['currentApprovalStep']) + 1}/${l['totalApprovalLevels']}',
        ].join(' · '),
        createdAt: _dt(l['createdAt']),
        sortDate: from,
      ));
    }
    for (final s in _list(res[2])) {
      items.add(_Item(
        kind: 'swap',
        id: s['id'].toString(),
        name: '${s['requesterName']} ⇄ ${s['targetName']}',
        title: 'Đổi ca',
        when: '${s['requesterShiftName']} ${_d(s['requesterDate'])} ⇄ ${s['targetShiftName']} ${_d(s['targetDate'])}',
        detail: (s['reason']?.toString() ?? '').isEmpty ? 'Đồng nghiệp đã đồng ý' : 'Lý do: ${s['reason']} · đồng nghiệp đã đồng ý',
        createdAt: _dt(s['createdAt']),
        sortDate: _dt(s['requesterDate']),
      ));
    }
    for (final s in _list(res[3])) {
      final st = _dt(s['startTime']), en = _dt(s['endTime']);
      items.add(_Item(
        kind: 'shift',
        id: s['id'].toString(),
        name: s['employeeName']?.toString() ?? '',
        title: 'Ca theo giờ',
        when: st == null ? '' : '${_d(s['startTime'])} ${DateFormat('HH:mm').format(st)}–${en == null ? '' : DateFormat('HH:mm').format(en)}',
        detail: s['description']?.toString(),
        createdAt: _dt(s['createdAt']),
        sortDate: st,
      ));
    }
    items.sort((a, b) => (a.sortDate ?? DateTime(2100)).compareTo(b.sortDate ?? DateTime(2100)));
    setState(() {
      _items = items;
      _loading = false;
      _selected.removeWhere((k) => !items.any((i) => i.key == k));
    });
  }

  List<_Item> get _shown => _kind == 'all' ? _items : _items.where((i) => i.kind == _kind).toList();

  Future<Map<String, dynamic>> _act(_Item i, bool approve, String? reason) => switch (i.kind) {
        'reg' => _api.approveScheduleRegistration(i.id, {'isApproved': approve, if (!approve) 'rejectionReason': reason}),
        'leave' => approve ? _api.approveLeave(i.id) : _api.rejectLeave(i.id, reason),
        'swap' => _api.approveShiftSwap(i.id, approve: approve, rejectionReason: reason),
        _ => approve ? _api.approveShift(i.id) : _api.rejectShift(i.id, reason: reason),
      };

  Future<void> _process(List<_Item> items, bool approve) async {
    if (items.isEmpty) return;
    String? reason;
    if (!approve) {
      reason = await ShiftUi.askText(context, 'Từ chối ${items.length} yêu cầu', hint: 'Lý do từ chối', required: true);
      if (reason == null) return;
    }
    setState(() => _busy = true);
    var ok = 0;
    final errors = <String>[];
    for (final i in items) {
      final r = await _act(i, approve, reason);
      if (r['isSuccess'] == true) {
        ok++;
      } else {
        errors.add('${i.name}: ${r['message'] ?? 'lỗi'}');
      }
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _selected.clear();
    });
    if (errors.isEmpty) {
      NotificationOverlayManager().showSuccess(title: 'Duyệt', message: '${approve ? 'Đã duyệt' : 'Đã từ chối'} $ok yêu cầu');
    } else {
      NotificationOverlayManager().showWarning(
          title: 'Duyệt', message: 'Thành công $ok, lỗi ${errors.length}: ${errors.take(3).join('; ')}');
    }
    await _load();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _items.isEmpty) return const Center(child: CircularProgressIndicator());
    final shown = _shown;
    final allSelected = shown.isNotEmpty && shown.every((i) => _selected.contains(i.key));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            ChoiceChip(
              label: Text(tr('Tất cả (${_items.length})')),
              selected: _kind == 'all',
              onSelected: (_) => setState(() => _kind = 'all'),
            ),
            for (final e in _kinds.entries)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ChoiceChip(
                  avatar: Icon(e.value.$2, size: 16, color: e.value.$3),
                  label: Text(tr('${e.value.$1} (${_items.where((i) => i.kind == e.key).length})')),
                  selected: _kind == e.key,
                  onSelected: (_) => setState(() => _kind = e.key),
                ),
              ),
          ]),
        ),
      ),
      if (shown.isNotEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: [
            Checkbox(
              value: allSelected,
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selected.addAll(shown.map((i) => i.key));
                } else {
                  _selected.removeAll(shown.map((i) => i.key));
                }
              }),
            ),
            Text(tr(_selected.isEmpty ? 'Chọn tất cả' : 'Đã chọn ${_selected.length}')),
            const Spacer(),
            if (_selected.isNotEmpty) ...[
              TextButton(
                onPressed: _busy ? null : () => _process(_items.where((i) => _selected.contains(i.key)).toList(), false),
                style: TextButton.styleFrom(foregroundColor: SboxColors.danger),
                child: Text(tr('Từ chối')),
              ),
              const SizedBox(width: 6),
              FilledButton.icon(
                onPressed: _busy ? null : () => _process(_items.where((i) => _selected.contains(i.key)).toList(), true),
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: Text(tr('Duyệt ${_selected.length}')),
              ),
              const SizedBox(width: 8),
            ],
          ]),
        ),
      if (_busy) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: shown.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 80),
                  const Icon(Icons.task_alt_rounded, size: 64, color: SboxColors.success),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(tr('Không còn yêu cầu nào chờ duyệt'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: SboxColors.slate600)),
                  ),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                  itemCount: shown.length,
                  itemBuilder: (_, i) => _card(shown[i]),
                ),
        ),
      ),
    ]);
  }

  Widget _card(_Item i) {
    final (label, icon, color) = _kinds[i.kind]!;
    final sel = _selected.contains(i.key);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: sel ? color.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: sel ? color : SboxColors.slate200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => sel ? _selected.remove(i.key) : _selected.add(i.key)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 10, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Checkbox(value: sel, onChanged: (_) => setState(() => sel ? _selected.remove(i.key) : _selected.add(i.key))),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  ShiftUi.pill(label, color, icon: icon),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(i.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, color: SboxColors.slate900)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(tr('${i.title} · ${i.when}'), style: const TextStyle(fontWeight: FontWeight.w600, color: SboxColors.slate700)),
                if ((i.detail ?? '').isNotEmpty)
                  Text(tr(i.detail!), style: const TextStyle(fontSize: 12.5, color: SboxColors.slate500)),
                if (i.createdAt != null)
                  Text(tr('Gửi lúc ${DateFormat('HH:mm dd/MM').format(i.createdAt!.toLocal())}'),
                      style: const TextStyle(fontSize: 11, color: SboxColors.slate400)),
              ]),
            ),
            Column(children: [
              IconButton.filledTonal(
                tooltip: tr('Duyệt'),
                onPressed: _busy ? null : () => _process([i], true),
                icon: const Icon(Icons.check_rounded, color: SboxColors.success),
              ),
              IconButton(
                tooltip: tr('Từ chối'),
                onPressed: _busy ? null : () => _process([i], false),
                icon: const Icon(Icons.close_rounded, color: SboxColors.danger),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
