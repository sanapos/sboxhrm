import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/page_top_actions.dart';
import '../leave_report_screen.dart';
import '../leave_screen.dart';
import '../schedule_approval_screen.dart';
import '../schedule_compliance_screen.dart';
import '../shift_settings_screen.dart';
import '../staffing_quota_settings_screen.dart';
import '../work_schedule_screen.dart';
import 'approval_inbox_view.dart';
import 'my_schedule_view.dart';
import 'schedule_board_view.dart';
import 'shift_hub_ui.dart';

/// Ca làm việc: một chỗ cho mọi việc về ca — Lịch của tôi (đăng ký ca, xin nghỉ, đổi ca),
/// Bảng xếp ca tuần kèm định mức nhân sự, Cần duyệt (đăng ký / nghỉ / đổi ca / ca giờ), Thiết lập.
class ShiftHubScreen extends StatefulWidget {
  const ShiftHubScreen({super.key, this.initialTab});

  /// my | board | inbox | setup
  final String? initialTab;

  @override
  State<ShiftHubScreen> createState() => _ShiftHubScreenState();
}

class _ShiftHubScreenState extends State<ShiftHubScreen> with SingleTickerProviderStateMixin {
  final _api = ApiService();
  late final bool _manager;
  late final List<String> _tabs;
  late final TabController _tabCtl;
  Map<String, dynamic> _counts = {};
  int _version = 0;

  @override
  void initState() {
    super.initState();
    final role = Provider.of<AuthProvider>(context, listen: false).userRole.toLowerCase();
    _manager = const {'admin', 'superadmin', 'director', 'manager', 'departmenthead', 'agent'}.contains(role);
    _tabs = ['my', if (_manager) 'board', if (_manager) 'inbox', if (_manager) 'setup'];
    final initial = _tabs.indexOf(widget.initialTab ?? (_manager ? 'board' : 'my'));
    _tabCtl = TabController(length: _tabs.length, vsync: this, initialIndex: initial < 0 ? 0 : initial);
    _loadCounts();
  }

  @override
  void dispose() {
    _tabCtl.dispose();
    super.dispose();
  }

  Future<void> _loadCounts() async {
    final r = await _api.getShiftHubCounts();
    if (mounted && r['isSuccess'] == true) setState(() => _counts = Map<String, dynamic>.from(r['data'] as Map));
  }

  void _changed() {
    _loadCounts();
    setState(() => _version++);
  }

  int _badge(String tab) => switch (tab) {
        'my' => ShiftUi.n(_counts['swapsForMe']).toInt(),
        'inbox' => (ShiftUi.n(_counts['total']) - ShiftUi.n(_counts['swapsForMe'])).toInt(),
        _ => 0,
      };

  @override
  Widget build(BuildContext context) {
    return RegisterPageTopActions(
      actions: [HrmTopBarAction(icon: Icons.refresh_rounded, label: 'Làm mới', onPressed: _changed)],
      child: Scaffold(
        backgroundColor: HrmPageChrome.background,
        body: Column(children: [
          Material(
            color: Colors.white,
            child: TabBar(
              controller: _tabCtl,
              isScrollable: MediaQuery.of(context).size.width < 700,
              tabAlignment: MediaQuery.of(context).size.width < 700 ? TabAlignment.start : null,
              labelColor: SboxColors.brand700,
              unselectedLabelColor: SboxColors.slate500,
              indicatorColor: SboxColors.brand600,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.w700),
              tabs: [
                for (final t in _tabs)
                  Tab(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                          switch (t) {
                            'my' => Icons.event_note_rounded,
                            'board' => Icons.grid_view_rounded,
                            'inbox' => Icons.fact_check_rounded,
                            _ => Icons.tune_rounded,
                          },
                          size: 18),
                      const SizedBox(width: 6),
                      Text(tr(switch (t) {
                        'my' => 'Lịch của tôi',
                        'board' => 'Bảng xếp ca',
                        'inbox' => 'Cần duyệt',
                        _ => 'Thiết lập',
                      })),
                      if (_badge(t) > 0) ...[
                        const SizedBox(width: 6),
                        ShiftUi.pill('${_badge(t)}', SboxColors.danger, solid: true),
                      ],
                    ]),
                  ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtl,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final t in _tabs)
                  switch (t) {
                    'my' => MyScheduleView(key: ValueKey('my$_version'), onChanged: _loadCounts),
                    'board' => ScheduleBoardView(key: ValueKey('board$_version'), onChanged: _loadCounts),
                    'inbox' => ApprovalInboxView(key: ValueKey('inbox$_version'), onChanged: _changed),
                    _ => _setup(),
                  },
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _setup() {
    Widget tile(IconData icon, Color color, String title, String sub, Widget Function() page) => Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: SboxColors.slate200)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color),
            ),
            title: Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(tr(sub)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => Scaffold(appBar: AppBar(title: Text(tr(title))), body: page())))
                .then((_) => _changed()),
          ),
        );
    return ListView(padding: const EdgeInsets.all(16), children: [
      ShiftUi.sectionTitle('Cấu hình', icon: Icons.settings_rounded),
      tile(Icons.schedule_rounded, SboxColors.brand600, 'Ca mẫu', 'Giờ vào/ra, nghỉ giữa ca, cho phép đi muộn / về sớm, tăng ca',
          () => const ShiftSettingsScreen()),
      tile(Icons.groups_rounded, SboxColors.violet, 'Định mức nhân sự',
          'Số người tối thiểu / tối đa mỗi ca, theo bộ phận và theo thứ trong tuần', () => const StaffingQuotaSettingsScreen()),
      const SizedBox(height: 16),
      ShiftUi.sectionTitle('Nâng cao', icon: Icons.open_in_new_rounded),
      tile(Icons.calendar_view_month_rounded, SboxColors.slate600, 'Lịch làm việc (đầy đủ)',
          'Xếp ca hàng loạt, xuất Excel, lịch theo tháng', () => const WorkScheduleScreen()),
      tile(Icons.approval_rounded, SboxColors.slate600, 'Duyệt lịch nhiều cấp', 'Xem chuỗi duyệt, hoàn tác duyệt đăng ký',
          () => const ScheduleApprovalScreen()),
      tile(Icons.beach_access_rounded, SboxColors.success, 'Nghỉ phép (đầy đủ)', 'Tạo hộ, sửa / huỷ đơn, hoàn tác duyệt, phép năm',
          () => const LeaveScreen()),
      const SizedBox(height: 16),
      ShiftUi.sectionTitle('Báo cáo', icon: Icons.insert_chart_rounded),
      tile(Icons.rule_rounded, SboxColors.warning, 'Tuân thủ lịch', 'So lịch xếp với chấm công thực tế', () => const ScheduleComplianceScreen()),
      tile(Icons.summarize_rounded, SboxColors.brand500, 'Báo cáo nghỉ phép', 'Tổng hợp nghỉ theo nhân viên, loại nghỉ',
          () => const LeaveReportScreen()),
    ]);
  }
}
