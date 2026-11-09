import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../screens/attendance_screen.dart';
import '../../screens/staff/staff_nav.dart';
import '../../services/api_service.dart';
import '../../services/branch_session.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/branch_switcher.dart';
import '../../widgets/sbox/sbox_basics.dart';
import 'boss_load_error.dart';

/// Một nhân viên trong ngày: giờ chấm đầu / cuối (chưa chấm thì null), ca hôm nay theo lịch, đi trễ, nghỉ phép.
class _StaffDay {
  _StaffDay(Map m)
      : name = '${m['name'] ?? ''}',
        code = '${m['code'] ?? ''}',
        first = DateTime.tryParse('${m['firstPunch']}'),
        last = DateTime.tryParse('${m['lastPunch']}'),
        hasShift = m['hasShift'] == true,
        shiftName = m['shiftName']?.toString(),
        shiftStart = m['shiftStart']?.toString(),
        shiftEnd = m['shiftEnd']?.toString(),
        lateMinutes = (m['lateMinutes'] as num?)?.toInt() ?? 0,
        onLeave = m['onLeave'] == true,
        leaveHalf = m['leaveHalf'] == true;

  final String name;
  final String code;
  final DateTime? first;
  final DateTime? last;
  final bool hasShift;
  final String? shiftName;
  final String? shiftStart;
  final String? shiftEnd;
  final int lateMinutes;
  final bool onLeave;
  final bool leaveHalf;

  bool get punched => first != null;

  /// Phút trong ngày của giờ vào ca (null = không có ca).
  int? get startMinutes {
    final p = shiftStart?.split(':');
    if (p == null || p.length < 2) return null;
    final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
    return h == null || m == null ? null : h * 60 + m;
  }
}

/// SBOX BOSS — nhân viên hôm nay: ai đã chấm (đi trễ bao lâu), ai đã tới giờ ca mà chưa chấm, ai chưa tới ca,
/// ai nghỉ phép, ai không có ca. Bấm thẻ / chip → chỉ xem nhóm đó.
/// Máy chủ tính sẵn trong phạm vi người xem được và chi nhánh đang chọn.
class BossStaffTodayScreen extends StatefulWidget {
  const BossStaffTodayScreen({super.key, this.api});

  final ApiService? api;

  @override
  State<BossStaffTodayScreen> createState() => _BossStaffTodayScreenState();
}

class _BossStaffTodayScreenState extends State<BossStaffTodayScreen> {
  List<_StaffDay> _staff = const [];
  bool _hasSchedules = false;
  DateTime? _serverNow;
  bool _loading = true;
  String? _error;
  int _seq = 0;

  /// Bấm thẻ / chip → chỉ hiện nhóm đó; null = mọi nhóm.
  String? _only;

  @override
  void initState() {
    super.initState();
    BranchSession.instance.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    BranchSession.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await (widget.api ?? ApiService()).getBossStaffToday();
    if (!mounted || seq != _seq) return;
    final data = r['data'];
    setState(() {
      _loading = false;
      if (r['isSuccess'] == true && data is Map) {
        _staff = [for (final e in (data['staff'] as List? ?? const [])) if (e is Map) _StaffDay(e)];
        _hasSchedules = data['hasSchedules'] == true;
        _serverNow = DateTime.tryParse('${data['now']}');
      } else {
        _error = r['message']?.toString() ?? 'Không tải được chấm công';
      }
    });
  }

  static String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Nhóm của một NV (mỗi người một nhóm). Cửa hàng không xếp lịch: chỉ Đã chấm / Chưa chấm / Nghỉ phép.
  String _groupOf(_StaffDay s, int nowMinutes) {
    if (s.punched) return 'done';
    if (s.onLeave) return 'leave';
    if (!_hasSchedules) return 'waiting';
    if (!s.hasShift) return 'noShift';
    final start = s.startMinutes;
    if (start != null && start > nowMinutes) return 'upcoming';
    return 'waiting';
  }

  @override
  Widget build(BuildContext context) {
    final now = _serverNow ?? DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final groups = <String, List<_StaffDay>>{};
    for (final s in _staff) {
      (groups[_groupOf(s, nowMinutes)] ??= []).add(s);
    }
    final done = (groups['done'] ?? [])..sort((a, b) => b.last!.compareTo(a.last!));
    final late = done.where((s) => s.lateMinutes > 0).toList()
      ..sort((a, b) => b.lateMinutes.compareTo(a.lateMinutes));
    final waiting = groups['waiting'] ?? const <_StaffDay>[];
    final upcoming = (groups['upcoming'] ?? [])
      ..sort((a, b) => (a.startMinutes ?? 0).compareTo(b.startMinutes ?? 0));
    final leave = groups['leave'] ?? const <_StaffDay>[];
    final noShift = groups['noShift'] ?? const <_StaffDay>[];

    void toggle(String k) => setState(() => _only = _only == k ? null : k);
    bool show(String k) => _only == null || _only == k;

    final waitingLabel = _hasSchedules ? 'Tới ca, chưa chấm' : 'Chưa chấm công';
    final chips = <(String, String, int, bool)>[
      ('late', 'Đi trễ', late.length, true),
      ('upcoming', 'Chưa tới ca', upcoming.length, false),
      ('leave', 'Nghỉ phép', leave.length, false),
      ('noShift', 'Không có ca', noShift.length, false),
    ];

    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: AppBar(
        backgroundColor: SboxColors.brand700,
        foregroundColor: SboxColors.white,
        title: Text(tr('Nhân viên hôm nay')),
        actions: [
          IconButton(
            tooltip: tr('Nhật ký chấm công'),
            icon: const Icon(Icons.history_rounded),
            onPressed: () => openStaffPage(
              context,
              title: 'Nhật ký chấm công',
              child: const AttendanceScreen(initialDatePreset: 'today'),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(right: SboxSpace.sm),
            child: Center(child: BranchSwitcher(compact: true, onDark: true)),
          ),
        ],
      ),
      body: _error != null
          ? BossLoadError(title: 'Không tải được chấm công', message: _error, onRetry: _load)
          : _loading && _staff.isEmpty
              ? const SboxLoading()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.all(SboxSpace.lg), children: [
                    if (_staff.isEmpty)
                      const SboxEmptyState(icon: Icons.badge_rounded, title: 'Chưa có nhân viên')
                    else ...[
                      Row(children: [
                        Expanded(
                          child: SboxMetricCard(
                            label: _only == 'done' ? 'Đã chấm công ✓' : 'Đã chấm công',
                            value: '${done.length}',
                            tone: SboxTone.success,
                            onTap: () => toggle('done'),
                          ),
                        ),
                        const SizedBox(width: SboxSpace.md),
                        Expanded(
                          child: SboxMetricCard(
                            label: _only == 'waiting' ? '$waitingLabel ✓' : waitingLabel,
                            value: '${waiting.length}',
                            tone: SboxTone.warning,
                            onTap: () => toggle('waiting'),
                          ),
                        ),
                      ]),
                      if (chips.any((c) => c.$3 > 0))
                        Padding(
                          padding: const EdgeInsets.only(top: SboxSpace.sm),
                          child: Wrap(spacing: 6, runSpacing: 6, children: [
                            for (final c in chips)
                              if (c.$3 > 0)
                                ChoiceChip(
                                  label: Text(tr('${c.$2} ${c.$3}')),
                                  selected: _only == c.$1,
                                  showCheckmark: false,
                                  selectedColor: c.$4 ? SboxColors.danger : SboxColors.brand700,
                                  labelStyle: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _only == c.$1
                                        ? SboxColors.white
                                        : (c.$4 ? SboxColors.dangerText : SboxColors.slate700),
                                  ),
                                  onSelected: (_) => toggle(c.$1),
                                ),
                          ]),
                        ),
                      if (_only != null)
                        Padding(
                          padding: const EdgeInsets.only(top: SboxSpace.sm),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () => setState(() => _only = null),
                              icon: const Icon(Icons.close, size: 16),
                              label: Text(tr('Xem tất cả')),
                            ),
                          ),
                        ),
                      if (waiting.isNotEmpty && show('waiting')) _section(waitingLabel, waiting),
                      if (late.isNotEmpty && _only == 'late') _section('Đi trễ', late),
                      if (done.isNotEmpty && show('done')) _section('Đã chấm công', done),
                      if (upcoming.isNotEmpty && show('upcoming')) _section('Chưa tới ca', upcoming),
                      if (leave.isNotEmpty && show('leave')) _section('Nghỉ phép', leave),
                      if (noShift.isNotEmpty && show('noShift')) _section('Không có ca hôm nay', noShift),
                    ],
                  ]),
                ),
    );
  }

  Widget _section(String title, List<_StaffDay> staff) => Padding(
        padding: const EdgeInsets.only(top: SboxSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: SboxSpace.sm),
            child: Text('${tr(title)} (${staff.length})', style: SboxType.titleSmStyle()),
          ),
          SboxCard(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (var i = 0; i < staff.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _tile(staff[i]),
              ],
            ]),
          ),
        ]),
      );

  Widget _tile(_StaffDay s) {
    final name = s.shiftName != null && s.shiftName!.isNotEmpty ? '${s.shiftName} ' : '';
    final shift = s.hasShift && s.shiftStart != null
        ? '$name${s.shiftStart}${s.shiftEnd != null ? '–${s.shiftEnd}' : ''}'
        : null;
    final sub = [
      if (s.code.isNotEmpty) s.code,
      if (shift != null) '${tr('Ca')} $shift',
      if (s.onLeave) tr(s.leaveHalf ? 'Nghỉ phép nửa ca' : 'Nghỉ phép'),
    ].join(' · ');
    return ListTile(
      title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: sub.isEmpty ? null : Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: s.first == null
          ? null
          : Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(
                s.first == s.last ? _hhmm(s.first!) : '${_hhmm(s.first!)} – ${_hhmm(s.last!)}',
                style: SboxType.bodyStrong(),
              ),
              if (s.lateMinutes > 0)
                Text(tr('Trễ ${s.lateMinutes} phút'),
                    style: const TextStyle(fontSize: 12, color: SboxColors.dangerText, fontWeight: FontWeight.w600)),
            ]),
    );
  }
}
