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

/// Một nhân viên trong ngày: giờ chấm đầu / cuối, chưa chấm thì null.
class _StaffDay {
  _StaffDay(Map m)
      : name = '${m['name'] ?? ''}',
        code = '${m['code'] ?? ''}',
        first = DateTime.tryParse('${m['firstPunch']}'),
        last = DateTime.tryParse('${m['lastPunch']}');

  final String name;
  final String code;
  final DateTime? first;
  final DateTime? last;
}

/// SBOX BOSS — nhân viên hôm nay: ai đã chấm công (giờ vào, giờ chấm gần nhất), ai chưa.
/// Máy chủ tính sẵn trong phạm vi người xem được và chi nhánh đang chọn.
class BossStaffTodayScreen extends StatefulWidget {
  const BossStaffTodayScreen({super.key, this.api});

  final ApiService? api;

  @override
  State<BossStaffTodayScreen> createState() => _BossStaffTodayScreenState();
}

class _BossStaffTodayScreenState extends State<BossStaffTodayScreen> {
  List<_StaffDay> _staff = const [];
  bool _loading = true;
  String? _error;
  int _seq = 0;

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
      } else {
        _error = r['message']?.toString() ?? 'Không tải được chấm công';
      }
    });
  }

  static String _hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final done = _staff.where((s) => s.first != null).toList()..sort((a, b) => b.last!.compareTo(a.last!));
    final waiting = _staff.where((s) => s.first == null).toList();
    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: AppBar(
        backgroundColor: SboxColors.bar,
        foregroundColor: SboxColors.isBoss ? SboxColors.onBar : SboxColors.white,
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
                            label: 'Đã chấm công',
                            value: '${done.length}',
                            tone: SboxTone.success,
                          ),
                        ),
                        const SizedBox(width: SboxSpace.md),
                        Expanded(
                          child: SboxMetricCard(
                            label: 'Chưa chấm công',
                            value: '${waiting.length}',
                            tone: SboxTone.warning,
                          ),
                        ),
                      ]),
                      if (waiting.isNotEmpty) _section('Chưa chấm công', waiting),
                      if (done.isNotEmpty) _section('Đã chấm công', done),
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
                ListTile(
                  title: Text(staff[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(staff[i].code),
                  trailing: staff[i].first == null
                      ? null
                      : Text(
                          staff[i].first == staff[i].last
                              ? _hhmm(staff[i].first!)
                              : '${_hhmm(staff[i].first!)} – ${_hhmm(staff[i].last!)}',
                          style: SboxType.bodyStrong(),
                        ),
                ),
              ],
            ]),
          ),
        ]),
      );
}
