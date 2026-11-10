import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/notification_overlay.dart';
import 'shift_hub_ui.dart';

/// Một yêu cầu của tôi (đã chuẩn hoá từ 3 nguồn).
class _Req {
  _Req({
    required this.kind,
    required this.id,
    required this.title,
    required this.when,
    required this.status,
    this.detail,
    this.sortDate,
    this.mine = true,
    this.step,
  });
  final String kind; // reg | leave | swap
  final String id;
  final String title;
  final String when;
  final String? status;
  final String? detail;
  final DateTime? sortDate;
  /// Đổi ca: tôi là người gửi (huỷ được) hay người được nhờ.
  final bool mine;
  /// «Bước 2/3» khi duyệt nhiều cấp.
  final String? step;
}

/// «Yêu cầu của tôi»: đăng ký ca, đơn nghỉ, đổi ca trong một danh sách, cùng một kiểu trạng thái;
/// huỷ được khi còn chờ duyệt. Trả true nếu đã huỷ gì đó (để tải lại lịch).
Future<bool> showMyRequestsSheet(BuildContext context) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 680),
    builder: (_) => const _MyRequests(),
  );
  return r == true;
}

class _MyRequests extends StatefulWidget {
  const _MyRequests();

  @override
  State<_MyRequests> createState() => _MyRequestsState();
}

class _MyRequestsState extends State<_MyRequests> {
  final _api = ApiService();
  List<_Req> _items = [];
  bool _loading = true;
  bool _pendingOnly = true;
  bool _changed = false;
  final Set<String> _busy = {};

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

  /// Enum có thể về dạng số (bản cũ) hoặc tên.
  String? _status(dynamic v, List<String> names) {
    if (v is num && v.toInt() >= 0 && v.toInt() < names.length) return names[v.toInt()];
    return v?.toString();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = Provider.of<AuthProvider>(context, listen: false).user?.id.toString();
    final from = DateTime.now().subtract(const Duration(days: 45));
    final res = await Future.wait([
      _api.getMyScheduleRegistrations(pageSize: 200, fromDate: from),
      _api.getMyLeaves(pageSize: 100),
      _api.getShiftSwaps(pageSize: 100),
    ]);
    if (!mounted) return;
    final items = <_Req>[];
    for (final r in _list(res[0])) {
      items.add(_Req(
        kind: 'reg',
        id: r['id'].toString(),
        title: r['isDayOff'] == true ? 'Đăng ký nghỉ ngày' : 'Đăng ký ${r['shiftName'] ?? 'ca'}',
        when: _d(r['date']),
        status: _status(r['status'], const ['Pending', 'Approved', 'Rejected', 'Cancelled']),
        detail: (r['rejectionReason'] ?? r['note'])?.toString(),
        sortDate: _dt(r['date']),
        step: ShiftUi.n(r['totalApprovalLevels']) > 1 && r['status'] == 'Pending'
            ? 'Bước ${ShiftUi.n(r['currentApprovalStep']) + 1}/${r['totalApprovalLevels']}'
            : null,
      ));
    }
    for (final l in _list(res[1])) {
      final s = _status(l['status'], const ['Pending', 'Approved', 'Rejected', 'Cancelled']);
      if (s == 'Cancelled') continue;
      final from = _dt(l['startDate']), to = _dt(l['endDate']);
      items.add(_Req(
        kind: 'leave',
        id: l['id'].toString(),
        title: '${ShiftUi.leaveTypes[l['type']?.toString()] ?? 'Nghỉ'}${l['isHalfShift'] == true ? ' (nửa ca)' : ''}',
        when: from != null && to != null && ShiftUi.key(from) != ShiftUi.key(to) ? '${ShiftUi.dmy(from)} → ${ShiftUi.dmy(to)}' : _d(l['startDate']),
        status: s,
        detail: (s == 'Rejected' ? l['rejectionReason'] : l['reason'])?.toString(),
        sortDate: from,
        step: ShiftUi.n(l['totalApprovalLevels']) > 1 && s == 'Pending'
            ? 'Bước ${ShiftUi.n(l['currentApprovalStep']) + 1}/${l['totalApprovalLevels']}'
            : null,
      ));
    }
    for (final w in _list(res[2])) {
      final mine = w['requesterUserId']?.toString() == uid;
      if (!mine && w['targetUserId']?.toString() != uid) continue;
      final s = _status(w['status'],
          const ['Pending', 'TargetAccepted', 'Approved', 'RejectedByTarget', 'RejectedByManager', 'Cancelled']);
      if (s == 'Cancelled') continue;
      items.add(_Req(
        kind: 'swap',
        id: w['id'].toString(),
        title: mine ? 'Đổi ca với ${w['targetName']}' : '${w['requesterName']} nhờ đổi ca',
        when: '${w['requesterShiftName']} ${_d(w['requesterDate'])} ⇄ ${w['targetShiftName']} ${_d(w['targetDate'])}',
        status: s,
        detail: (w['rejectionReason'] ?? w['reason'])?.toString(),
        sortDate: _dt(w['requesterDate']),
        mine: mine,
      ));
    }
    items.sort((a, b) => (b.sortDate ?? DateTime(2000)).compareTo(a.sortDate ?? DateTime(2000)));
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _cancel(_Req i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Huỷ yêu cầu?')),
        content: Text(tr('${ShiftUi.requestKinds[i.kind]!.$1}: ${i.title} · ${i.when}')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Không'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Huỷ yêu cầu'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy.add(i.id));
    final r = await switch (i.kind) {
      'reg' => _api.deleteScheduleRegistration(i.id),
      'leave' => _api.cancelLeave(i.id),
      _ => _api.cancelShiftSwap(i.id),
    };
    if (!mounted) return;
    setState(() => _busy.remove(i.id));
    if (r['isSuccess'] == true) {
      _changed = true;
      NotificationOverlayManager().showSuccess(title: 'Yêu cầu của tôi', message: 'Đã huỷ');
      _load();
    } else {
      NotificationOverlayManager().showError(title: 'Yêu cầu của tôi', message: r['message']?.toString() ?? 'Không huỷ được');
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = _items
        .where((i) => !_pendingOnly || i.status == 'Pending' || i.status == 'TargetAccepted')
        .toList();
    final pending = _items.where((i) => i.status == 'Pending' || i.status == 'TargetAccepted').length;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr('Yêu cầu của tôi'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(tr('Đăng ký ca, đơn nghỉ, đổi ca — huỷ được khi còn chờ duyệt'), style: const TextStyle(color: SboxColors.slate500)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, children: [
              ChoiceChip(label: Text(tr('Đang chờ ($pending)')), selected: _pendingOnly, onSelected: (_) => setState(() => _pendingOnly = true)),
              ChoiceChip(label: Text(tr('Tất cả (${_items.length})')), selected: !_pendingOnly, onSelected: (_) => setState(() => _pendingOnly = false)),
            ]),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : shown.isEmpty
                    ? Center(
                        child: Text(tr(_pendingOnly ? 'Không có yêu cầu nào đang chờ' : 'Chưa có yêu cầu nào'),
                            style: const TextStyle(color: SboxColors.slate500)),
                      )
                    : ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 16), children: [for (final i in shown) _tile(i)]),
          ),
        ]),
      ),
    );
  }

  Widget _tile(_Req i) {
    final (label, icon) = ShiftUi.requestKinds[i.kind]!;
    final canCancel = i.mine && ShiftUi.requestCancellable(i.kind, i.status);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: SboxColors.slate200)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 20, color: ShiftUi.statusColor(i.status)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(i.title), style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(i.when, style: const TextStyle(fontSize: 12.5, color: SboxColors.slate600)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                ShiftUi.pill(label, SboxColors.slate500),
                ShiftUi.requestStatusPill(i.kind, i.status),
                if (i.step != null) ShiftUi.pill(i.step!, SboxColors.violet),
              ]),
              if ((i.detail ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(i.detail!.trim(), maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                ),
            ]),
          ),
          if (canCancel)
            _busy.contains(i.id)
                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : TextButton(onPressed: () => _cancel(i), child: Text(tr('Huỷ'), style: const TextStyle(color: SboxColors.danger))),
        ]),
      ),
    );
  }
}
