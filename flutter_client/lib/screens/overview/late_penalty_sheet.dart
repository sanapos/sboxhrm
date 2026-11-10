import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../services/api_service.dart';
import '../../widgets/sbox/sbox_ui.dart';

/// Tổng quan → «Đi trễ hôm nay»: ai đi trễ, phiếu phạt tự động của từng người và nút duyệt
/// từng phiếu / duyệt nhanh tất cả phiếu đang chờ.
Future<void> showLatePenaltySheet(
  BuildContext context, {
  required List<Map<String, dynamic>> lateRows,
  required bool canApprove,
  VoidCallback? onOpenPenalties,
  ApiService? api,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => LatePenaltySheet(
      lateRows: lateRows,
      canApprove: canApprove,
      onOpenPenalties: onOpenPenalties,
      api: api ?? ApiService(),
    ),
  );
}

class LatePenaltySheet extends StatefulWidget {
  const LatePenaltySheet({
    super.key,
    required this.lateRows,
    required this.canApprove,
    required this.api,
    this.onOpenPenalties,
  });

  /// Dòng «Late» của chuyên cần hôm nay (employeeId, fullName, checkIn, lateMinutes, shift…).
  final List<Map<String, dynamic>> lateRows;
  final bool canApprove;
  final ApiService api;
  final VoidCallback? onOpenPenalties;

  @override
  State<LatePenaltySheet> createState() => _LatePenaltySheetState();
}

class _LatePenaltySheetState extends State<LatePenaltySheet> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tickets = [];
  final Set<String> _busy = {};
  bool _bulkBusy = false;

  static double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    final r = await widget.api.getPenaltyTickets(pageSize: 200, type: 'Late', fromDate: day, toDate: day);
    if (!mounted) return;
    final data = r['data'];
    setState(() {
      _loading = false;
      if (r['isSuccess'] == true && data is Map && data['items'] is List) {
        _tickets = [for (final t in data['items'] as List) if (t is Map) Map<String, dynamic>.from(t)];
      } else {
        _error = '${r['message'] ?? 'Không tải được phiếu phạt'}';
      }
    });
  }

  List<Map<String, dynamic>> _ticketsOf(String empId) =>
      _tickets.where((t) => '${t['employeeId']}' == empId && '${t['status']}' != 'Cancelled').toList();

  List<Map<String, dynamic>> get _pending => _tickets.where((t) => '${t['status']}' == 'Pending').toList();

  Future<bool> _approveOne(Map<String, dynamic> t) async {
    final id = '${t['id']}';
    final r = await widget.api.approvePenaltyTicket(id);
    if (r['isSuccess'] == true) {
      t['status'] = 'Approved';
      return true;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('${r['message'] ?? 'Không duyệt được phiếu'}'))));
    }
    return false;
  }

  Future<void> _approve(Map<String, dynamic> t) async {
    setState(() => _busy.add('${t['id']}'));
    await _approveOne(t);
    if (mounted) setState(() => _busy.remove('${t['id']}'));
  }

  Future<void> _approveAll() async {
    final list = _pending;
    if (list.isEmpty) return;
    final total = list.fold<double>(0, (s, t) => s + _n(t['amount']));
    final ok = await SboxDialogs.confirm(
      context,
      title: 'Duyệt ${list.length} phiếu phạt đi trễ?',
      message: 'Tổng ${SboxFmt.money(total)}. Nhân viên sẽ nhận thông báo phiếu đã duyệt.',
      confirmLabel: 'Duyệt tất cả',
    );
    if (!ok || !mounted) return;
    setState(() => _bulkBusy = true);
    var done = 0;
    for (final t in list) {
      if (!mounted) return;
      setState(() => _busy.add('${t['id']}'));
      if (await _approveOne(t)) done++;
      if (mounted) setState(() => _busy.remove('${t['id']}'));
    }
    if (!mounted) return;
    setState(() => _bulkBusy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Đã duyệt $done/${list.length} phiếu phạt'))));
  }

  (String, SboxTone) _statusOf(String s) => switch (s) {
        'Pending' => ('Chờ duyệt', SboxTone.warning),
        'Approved' || 'AutoApproved' => ('Đã duyệt', SboxTone.success),
        'Paid' => ('Đã thu', SboxTone.success),
        _ => (s, SboxTone.neutral),
      };

  Widget _row(Map<String, dynamic> r) {
    final empId = '${r['employeeId'] ?? ''}';
    final tickets = _ticketsOf(empId);
    final shift = r['shiftStart'] == null
        ? ''
        : r['shiftEnd'] == null
            ? 'Ca ${r['shiftStart']}'
            : 'Ca ${r['shiftStart']}–${r['shiftEnd']}';
    final sub = [
      if ('${r['department'] ?? ''}'.isNotEmpty) '${r['department']}',
      if (shift.isNotEmpty) shift,
      if (r['checkIn'] != null) 'Vào ${r['checkIn']}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: SboxSpace.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${r['fullName'] ?? ''}', style: SboxType.titleSmStyle()),
              if (sub.isNotEmpty) Text(sub, style: SboxType.captionStyle()),
            ]),
          ),
          Text(tr('Trễ ${r['lateMinutes'] ?? 0}p'), style: SboxType.bodyStyle(SboxColors.warningText)),
        ]),
        const SizedBox(height: SboxSpace.xs),
        if (_loading)
          const SizedBox.shrink()
        else if (tickets.isEmpty)
          Text(tr('Chưa có phiếu phạt (dưới mức phạt hoặc chưa cấu hình phạt đi trễ)'),
              style: SboxType.captionStyle(SboxColors.textMuted))
        else
          for (final t in tickets)
            Row(children: [
              Expanded(
                child: Text(
                  '${t['ticketCode'] ?? ''} · ${SboxFmt.money(_n(t['amount']))}',
                  style: SboxType.bodyStyle(),
                ),
              ),
              Builder(builder: (_) {
                final (l, tone) = _statusOf('${t['status']}');
                return SboxStatusChip(label: l, tone: tone, dot: true);
              }),
              if (widget.canApprove && '${t['status']}' == 'Pending') ...[
                const SizedBox(width: SboxSpace.sm),
                SboxButton(
                  label: 'Duyệt',
                  size: SboxButtonSize.sm,
                  loading: _busy.contains('${t['id']}'),
                  onPressed: _bulkBusy || _busy.contains('${t['id']}') ? null : () => _approve(t),
                ),
              ],
            ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pending;
    final pendingTotal = pending.fold<double>(0, (s, t) => s + _n(t['amount']));
    final rows = [...widget.lateRows]..sort((a, b) => _n(b['lateMinutes']).compareTo(_n(a['lateMinutes'])));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(SboxSpace.lg, SboxSpace.lg, SboxSpace.sm, SboxSpace.sm),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Đi trễ hôm nay'), style: SboxType.titleStyle()),
                Text(
                  tr(_loading
                      ? '${rows.length} nhân viên · đang tải phiếu phạt…'
                      : '${rows.length} nhân viên · ${pending.length} phiếu chờ duyệt (${SboxFmt.money(pendingTotal)})'),
                  style: SboxType.captionStyle(),
                ),
              ]),
            ),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
          ]),
        ),
        if (widget.canApprove && pending.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SboxSpace.lg),
            child: SboxButton(
              label: 'Duyệt nhanh tất cả (${pending.length})',
              icon: Icons.done_all_rounded,
              expand: true,
              loading: _bulkBusy,
              onPressed: _bulkBusy ? null : _approveAll,
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(SboxSpace.lg),
            child: Text(tr(_error!), style: SboxType.bodyStyle(SboxColors.dangerText)),
          ),
        Expanded(
          child: rows.isEmpty
              ? Center(child: Text(tr('Hôm nay chưa có ai đi trễ'), style: SboxType.bodyStyle(SboxColors.textMuted)))
              : ListView.separated(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(SboxSpace.lg, SboxSpace.sm, SboxSpace.lg, SboxSpace.xl),
                  itemCount: rows.length + (widget.onOpenPenalties == null ? 0 : 1),
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    if (i == rows.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: SboxSpace.md),
                        child: SboxButton.ghost(
                          label: 'Mở danh sách phiếu phạt',
                          icon: Icons.open_in_new_rounded,
                          onPressed: () {
                            Navigator.pop(context);
                            widget.onOpenPenalties!();
                          },
                        ),
                      );
                    }
                    return _row(rows[i]);
                  },
                ),
        ),
      ]),
    );
  }
}
