import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/notification_overlay.dart';
import 'shift_hub_sheets.dart';
import 'shift_hub_ui.dart';

/// Lịch của tôi theo tuần: ca đã xếp / nghỉ / đăng ký chờ duyệt / đơn nghỉ / đổi ca;
/// thao tác ngay trên từng ngày: đăng ký ca, xin nghỉ, đổi ca, huỷ đăng ký.
class MyScheduleView extends StatefulWidget {
  const MyScheduleView({super.key, this.onChanged});
  final VoidCallback? onChanged;

  @override
  State<MyScheduleView> createState() => _MyScheduleViewState();
}

class _MyScheduleViewState extends State<MyScheduleView> {
  final _api = ApiService();
  DateTime _monday = ShiftUi.monday(DateTime.now());
  Map<String, dynamic>? _d;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = _d == null);
    final r = await _api.getShiftHubMy(from: _monday, to: _monday.add(const Duration(days: 6)));
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (r['isSuccess'] == true) {
        _d = r['data'] as Map<String, dynamic>?;
        _error = null;
      } else {
        _error = r['message']?.toString() ?? 'Không tải được lịch';
      }
    });
  }

  void _changed() {
    _load();
    widget.onChanged?.call();
  }

  List<Map<String, dynamic>> _rows(dynamic v) => [
        for (final x in (v as List? ?? const []))
          if (x is Map) Map<String, dynamic>.from(x),
      ];

  List<Map<String, dynamic>> get _templates => _rows(_d?['templates']);

  Map<String, dynamic>? _tpl(dynamic id) =>
      id == null ? null : _templates.where((t) => t['id'].toString() == id.toString()).firstOrNull;

  @override
  Widget build(BuildContext context) {
    if (_loading && _d == null) return const Center(child: CircularProgressIndicator());
    if (_error != null && _d == null) return Center(child: Text(tr(_error!), style: const TextStyle(color: SboxColors.danger)));
    final sm = _d?['summary'] as Map<String, dynamic>? ?? const {};
    final days = _rows(_d?['days']);
    final incoming = _rows(_d?['incomingSwaps']);
    final today = days.where((d) => d['isToday'] == true).firstOrNull;
    return RefreshIndicator(
      onRefresh: _load,
      child: LayoutBuilder(builder: (context, c) {
        final pad = c.maxWidth < 600 ? 12.0 : 20.0;
        final cols = c.maxWidth >= 1200 ? 4 : c.maxWidth >= 860 ? 3 : c.maxWidth >= 560 ? 2 : 1;
        final w = (c.maxWidth - pad * 2 - (cols - 1) * 12) / cols;
        return ListView(
          padding: EdgeInsets.fromLTRB(pad, pad, pad, 96),
          children: [
            if (today != null) _todayHero(today),
            if (today != null) const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 8,
              children: [
                ShiftUi.weekNav(
                  monday: _monday,
                  onPrev: () {
                    _monday = _monday.subtract(const Duration(days: 7));
                    _load();
                  },
                  onNext: () {
                    _monday = _monday.add(const Duration(days: 7));
                    _load();
                  },
                  onToday: () {
                    _monday = ShiftUi.monday(DateTime.now());
                    _load();
                  },
                  onPick: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _monday,
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) {
                      _monday = ShiftUi.monday(d);
                      _load();
                    }
                  },
                ),
                Text(tr('${ShiftUi.n(sm['shifts'])} ca · ${ShiftUi.n(sm['hours'])} giờ · ${ShiftUi.n(sm['dayOff'])} ngày nghỉ'),
                    style: const TextStyle(color: SboxColors.slate600, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            if (incoming.isNotEmpty) ...[
              ShiftUi.sectionTitle('Đồng nghiệp muốn đổi ca với bạn (${incoming.length})', icon: Icons.swap_horiz_rounded),
              ...incoming.map(_incomingSwap),
              const SizedBox(height: 12),
            ],
            if (ShiftUi.n(sm['pendingRegistrations']) + ShiftUi.n(sm['pendingLeaves']) + ShiftUi.n(sm['pendingSwaps']) > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  if (ShiftUi.n(sm['pendingRegistrations']) > 0)
                    ShiftUi.pill('${ShiftUi.n(sm['pendingRegistrations'])} đăng ký ca chờ duyệt', SboxColors.warning, icon: Icons.hourglass_top_rounded),
                  if (ShiftUi.n(sm['pendingLeaves']) > 0)
                    ShiftUi.pill('${ShiftUi.n(sm['pendingLeaves'])} đơn nghỉ chờ duyệt', SboxColors.warning, icon: Icons.beach_access_rounded),
                  if (ShiftUi.n(sm['pendingSwaps']) > 0)
                    ShiftUi.pill('${ShiftUi.n(sm['pendingSwaps'])} đổi ca đang xử lý', SboxColors.violet, icon: Icons.swap_horiz_rounded),
                ]),
              ),
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final d in days) SizedBox(width: w, child: _dayCard(d)),
            ]),
          ],
        );
      }),
    );
  }

  Widget _todayHero(Map<String, dynamic> d) {
    final s = d['schedule'] as Map?;
    final tp = _tpl(s?['shiftId']);
    final leaveToday = _rows(d['leaves']).where((l) => l['status'] == 'Approved').isNotEmpty;
    final title = leaveToday
        ? 'Hôm nay bạn nghỉ phép'
        : s == null
            ? 'Hôm nay chưa có ca'
            : s['isDayOff'] == true
                ? 'Hôm nay là ngày nghỉ'
                : 'Hôm nay: ${tp?['name'] ?? 'Ca làm'} ${s['start']} – ${s['end']}';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [SboxColors.brand700, SboxColors.brand500]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr('${ShiftUi.weekdaysLong[DateTime.now().weekday - 1]}, ${ShiftUi.dmy(DateTime.now())}'),
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Text(tr(title), style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            if (s?['note'] != null && s!['note'].toString().isNotEmpty)
              Text('📝 ${s['note']}', style: const TextStyle(color: Colors.white70)),
          ]),
        ),
        Icon(leaveToday ? Icons.beach_access_rounded : Icons.work_history_rounded, color: Colors.white54, size: 40),
      ]),
    );
  }

  Widget _incomingSwap(Map<String, dynamic> s) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: SboxColors.violet.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SboxColors.violet.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('${s['otherName']} muốn đổi ca'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(tr('Bạn nhận: ${s['theirShift']} ngày ${_dm(s['theirDate'])}\nBạn nhường: ${s['myShift']} ngày ${_dm(s['myDate'])}'),
              style: const TextStyle(fontSize: 13, color: SboxColors.slate700)),
          if ((s['reason']?.toString() ?? '').isNotEmpty)
            Text(tr('Lý do: ${s['reason']}'), style: const TextStyle(fontSize: 12.5, color: SboxColors.slate500)),
          const SizedBox(height: 8),
          Row(children: [
            FilledButton.icon(
              onPressed: () async {
                final r = await _api.respondToShiftSwap(s['id'].toString(), accept: true);
                _result(r, 'Đã đồng ý — chờ quản lý duyệt');
              },
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(tr('Đồng ý')),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () async {
                final reason = await ShiftUi.askText(context, 'Từ chối đổi ca', hint: 'Lý do (không bắt buộc)');
                if (reason == null) return;
                final r = await _api.respondToShiftSwap(s['id'].toString(), accept: false, rejectionReason: reason);
                _result(r, 'Đã từ chối');
              },
              child: Text(tr('Từ chối')),
            ),
          ]),
        ]),
      );

  String _dm(dynamic v) {
    final d = ShiftUi.parse(v);
    return d == null ? '' : ShiftUi.dm(d);
  }

  void _result(Map<String, dynamic> r, String ok) {
    if (r['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(title: 'Ca làm việc', message: ok);
      _changed();
    } else {
      NotificationOverlayManager().showError(title: 'Ca làm việc', message: r['message']?.toString() ?? 'Thao tác thất bại');
    }
  }

  Widget _dayCard(Map<String, dynamic> d) {
    final date = ShiftUi.parse(d['date'])!;
    final past = d['isPast'] == true;
    final today = d['isToday'] == true;
    final s = d['schedule'] as Map?;
    final reg = d['registration'] as Map?;
    final leaves = _rows(d['leaves']);
    final swaps = _rows(d['swaps']);
    final tp = _tpl(s?['shiftId']);
    final color = tp == null ? SboxColors.slate300 : ShiftUi.shiftColor(ShiftUi.n(tp['colorIndex']).toInt());
    final approvedLeave = leaves.where((l) => l['status'] == 'Approved').firstOrNull;

    return Opacity(
      opacity: past ? 0.6 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: today ? SboxColors.brand500 : SboxColors.slate200, width: today ? 1.6 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
            child: Row(children: [
              Container(
                width: 42,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: today ? SboxColors.brand600 : SboxColors.slate100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(children: [
                  Text(ShiftUi.weekdays[date.weekday - 1],
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: today ? Colors.white70 : SboxColors.slate500)),
                  Text('${date.day}',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: today ? Colors.white : SboxColors.slate900)),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: approvedLeave != null
                    ? _line(Icons.beach_access_rounded, 'Nghỉ phép', ShiftUi.leaveTypes[approvedLeave['type']] ?? '', SboxColors.success)
                    : s == null
                        ? _line(Icons.event_busy_rounded, 'Chưa có ca', past ? '' : 'Bấm «Đăng ký» để chọn ca', SboxColors.slate400)
                        : s['isDayOff'] == true
                            ? _line(Icons.weekend_rounded, 'Ngày nghỉ', s['note']?.toString() ?? '', SboxColors.slate500)
                            : _line(Icons.schedule_rounded, tp?['name']?.toString() ?? 'Ca làm', '${s['start']} – ${s['end']}', color),
              ),
              if (!past) _menu(d, date, s, tp, reg),
            ]),
          ),
          if (reg != null || leaves.any((l) => l['status'] != 'Approved') || swaps.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                if (reg != null && reg['status'] != 'Approved')
                  ShiftUi.pill(
                    reg['status'] == 'Pending'
                        ? 'Đăng ký ${reg['isDayOff'] == true ? 'nghỉ' : _tpl(reg['shiftId'])?['name'] ?? 'ca'} · chờ duyệt'
                        : 'Đăng ký bị từ chối${(reg['rejectionReason']?.toString() ?? '').isNotEmpty ? ': ${reg['rejectionReason']}' : ''}',
                    ShiftUi.statusColor(reg['status']?.toString()),
                    icon: Icons.how_to_reg_rounded,
                  ),
                for (final l in leaves.where((l) => l['status'] != 'Approved'))
                  ShiftUi.pill('Đơn nghỉ ${ShiftUi.leaveTypes[l['type']] ?? ''} · ${ShiftUi.statusLabels[l['status']] ?? ''}',
                      ShiftUi.statusColor(l['status']?.toString()), icon: Icons.beach_access_rounded),
                for (final w in swaps)
                  ShiftUi.pill('Đổi ca với ${w['otherName']} · ${ShiftUi.statusLabels[w['status']] ?? w['status']}',
                      ShiftUi.statusColor(w['status']?.toString()), icon: Icons.swap_horiz_rounded),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _line(IconData icon, String title, String sub, Color color) => Row(children: [
        Container(width: 4, height: 34, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tr(title), maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, color: SboxColors.slate900)),
            if (sub.isNotEmpty)
              Text(tr(sub), maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: SboxColors.slate500)),
          ]),
        ),
      ]);

  Widget _menu(Map<String, dynamic> d, DateTime date, Map? s, Map<String, dynamic>? tp, Map? reg) {
    final hasShift = s != null && s['isDayOff'] != true && s['shiftId'] != null;
    return PopupMenuButton<String>(
      tooltip: tr('Thao tác'),
      icon: const Icon(Icons.more_vert_rounded, color: SboxColors.slate500),
      onSelected: (v) async {
        var changed = false;
        switch (v) {
          case 'register':
            changed = await showRegisterShiftSheet(context,
                date: date, templates: _templates, slots: _rows(d['slots']), currentShiftId: s?['shiftId']?.toString());
          case 'leave':
            changed = await showLeaveRequestSheet(context,
                date: date,
                templates: _templates,
                scheduledShiftId: hasShift ? s['shiftId'].toString() : null,
                employeeId: (_d?['employee'] as Map?)?['id']?.toString());
          case 'swap':
            changed = await showSwapRequestSheet(context,
                myDate: date,
                myShiftId: s!['shiftId'].toString(),
                myShiftLabel: '${tp?['name'] ?? ''} ${s['start']}–${s['end']}');
          case 'cancelReg':
            final r = await _api.deleteScheduleRegistration(reg!['id'].toString());
            _result(r, 'Đã huỷ đăng ký');
        }
        if (changed) _changed();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'register',
          child: ListTile(
            dense: true,
            leading: const Icon(Icons.how_to_reg_rounded),
            title: Text(tr(s == null ? 'Đăng ký ca' : 'Đăng ký đổi sang ca khác')),
          ),
        ),
        PopupMenuItem(
          value: 'leave',
          child: ListTile(dense: true, leading: const Icon(Icons.beach_access_rounded), title: Text(tr('Xin nghỉ phép'))),
        ),
        if (hasShift)
          PopupMenuItem(
            value: 'swap',
            child: ListTile(dense: true, leading: const Icon(Icons.swap_horiz_rounded), title: Text(tr('Đổi ca với đồng nghiệp'))),
          ),
        if (reg != null && reg['status'] == 'Pending')
          PopupMenuItem(
            value: 'cancelReg',
            child: ListTile(
                dense: true, leading: const Icon(Icons.undo_rounded, color: SboxColors.danger), title: Text(tr('Huỷ đăng ký đang chờ'))),
          ),
      ],
    );
  }
}
