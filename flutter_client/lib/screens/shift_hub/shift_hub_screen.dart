import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../config/sbox_app_variant.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../utils/permission_navigation.dart';
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
import 'approval_inbox_view.dart';
import 'my_schedule_view.dart';
import 'schedule_board_view.dart';
import 'shift_hub_ui.dart';

/// Lối vào chung cho menu «Nghỉ phép», «Đổi ca làm việc», «Duyệt lịch làm việc»: mở Ca làm việc ở
/// [tab] (nhân viên không có tab Cần duyệt → về Lịch của tôi). Tài khoản không có quyền module
/// «WorkSchedule» (Ca làm việc) vẫn dùng màn cũ [fallback].
class ShiftHubEntry extends StatelessWidget {
  const ShiftHubEntry({super.key, required this.tab, required this.fallback, this.myAction});
  final String tab;
  final Widget fallback;
  final String? myAction;

  @override
  Widget build(BuildContext context) {
    final perm = context.watch<PermissionProvider>();
    if (!PermissionNavigation.canNavigate(perm, 'WorkSchedule')) return fallback;
    return ShiftHubScreen(initialTab: tab, myAction: myAction);
  }
}

/// App SBOX Nhân Viên: «Xin nghỉ phép» / «Đổi ca» mở Lịch của tôi và bật luôn bảng tương ứng.
class MyScheduleEntry extends StatelessWidget {
  const MyScheduleEntry({super.key, required this.action, required this.fallback});
  final String action;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final perm = context.watch<PermissionProvider>();
    if (!PermissionNavigation.canNavigate(perm, 'WorkSchedule')) return fallback;
    return MyScheduleView(startAction: action);
  }
}

/// Ca làm việc: một chỗ cho mọi việc về ca — Lịch của tôi (đăng ký ca, xin nghỉ, đổi ca),
/// Bảng xếp ca tuần kèm định mức nhân sự, Cần duyệt (đăng ký / nghỉ / đổi ca / ca giờ), Thiết lập.
class ShiftHubScreen extends StatefulWidget {
  const ShiftHubScreen({super.key, this.initialTab, this.myAction});

  /// my | board | inbox | setup
  final String? initialTab;

  /// Bảng tự mở ở «Lịch của tôi» sau khi tải ([MyScheduleView.startAction]).
  final String? myAction;

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
    _manager = const {'admin', 'storeowner', 'superadmin', 'director', 'manager', 'departmenthead', 'agent'}.contains(role);
    // App SBOX BOSS: chủ / quản lý xếp lịch cho người khác, không có «Lịch của tôi».
    _tabs = [
      if (!(SboxAppVariant.bossApp && _manager)) 'my',
      if (_manager) 'board',
      if (_manager) 'inbox',
      if (_manager) 'setup',
    ];
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
      actions: [],
      child: Scaffold(
        backgroundColor: HrmPageChrome.background,
        body: Column(children: [
          Material(
            color: SboxColors.bar,
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
                    'my' => MyScheduleView(
                        key: ValueKey('my$_version'),
                        onChanged: _loadCounts,
                        startAction: _version == 0 ? widget.myAction : null),
                    'board' => ScheduleBoardView(key: ValueKey('board$_version'), onChanged: _loadCounts),
                    'inbox' => ApprovalInboxView(key: ValueKey('inbox$_version'), onChanged: _changed, onOpenLeaves: _openLeaves),
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
              decoration: BoxDecoration(color: SboxColors.isBoss ? SboxColors.iconBox : color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: SboxColors.isBoss ? SboxColors.iconOnBox : color),
            ),
            title: Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(tr(sub)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(
                    builder: (_) => Scaffold(
                          // Trang con đăng ký nút (Thêm ca…) qua PageTopActions — route đẩy đè shell nên phải tự vẽ.
                          appBar: AppBar(title: Text(tr(title)), actions: [
                            ListenableBuilder(
                              listenable: PageTopActions.instance,
                              builder: (_, __) => PageTopActionsBar(actions: PageTopActions.instance.actions),
                            ),
                            const SizedBox(width: 8),
                          ]),
                          floatingActionButton: const PageTopActionsFab(),
                          body: page(),
                        )))
                .then((_) => _changed()),
          ),
        );
    // Chỉ còn cấu hình + báo cáo. Việc xếp lịch hằng ngày (theo ca, hàng loạt, sao chép ngày / tuần /
    // tháng, xuất Excel) đã ở tab «Bảng xếp ca»; quản lý đơn nghỉ ở tab «Cần duyệt».
    return ListView(padding: const EdgeInsets.all(16), children: [
      ShiftUi.sectionTitle('Cấu hình ca', icon: Icons.settings_rounded),
      tile(Icons.schedule_rounded, SboxColors.brand600, 'Ca mẫu', 'Giờ vào/ra, nghỉ giữa ca, cho phép đi muộn / về sớm, tăng ca',
          () => const ShiftSettingsScreen()),
      tile(Icons.groups_rounded, SboxColors.violet, 'Định mức nhân sự',
          'Số người tối thiểu / tối đa mỗi ca, theo bộ phận và theo thứ trong tuần', () => const StaffingQuotaSettingsScreen()),
      const SizedBox(height: 16),
      ShiftUi.sectionTitle('Quy trình duyệt', icon: Icons.approval_rounded),
      tile(Icons.account_tree_rounded, SboxColors.slate600, 'Duyệt lịch nhiều cấp', 'Xem chuỗi duyệt, hoàn tác duyệt đăng ký',
          () => const ScheduleApprovalScreen(chainOnly: true)),
      const SizedBox(height: 16),
      ShiftUi.sectionTitle('Báo cáo', icon: Icons.insert_chart_rounded),
      tile(Icons.rule_rounded, SboxColors.warning, 'Tuân thủ lịch', 'So lịch xếp với chấm công thực tế', () => const ScheduleComplianceScreen()),
      tile(Icons.summarize_rounded, SboxColors.brand500, 'Báo cáo nghỉ phép', 'Tổng hợp nghỉ theo nhân viên, loại nghỉ',
          () => const LeaveReportScreen()),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: SboxColors.brand50, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: SboxColors.brand700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              tr('Xếp lịch theo ca, sao chép ngày / tuần / tháng, xuất Excel: tab «Bảng xếp ca» → «Theo ca» / «Từng ngày» và «Thao tác nhanh». '
                  'Quản lý đơn nghỉ phép: tab «Cần duyệt».'),
              style: const TextStyle(fontSize: 12, color: SboxColors.brand900),
            ),
          ),
        ]),
      ),
    ]);
  }

  /// «Nghỉ phép (đầy đủ)»: tạo hộ, sửa / huỷ đơn, hoàn tác duyệt, phép năm — mở từ tab Cần duyệt.
  void _openLeaves() => Navigator.of(context)
      .push(MaterialPageRoute(
          builder: (_) => Scaffold(
                appBar: AppBar(title: Text(tr('Quản lý nghỉ phép')), actions: [
                  ListenableBuilder(
                    listenable: PageTopActions.instance,
                    builder: (_, __) => PageTopActionsBar(actions: PageTopActions.instance.actions),
                  ),
                  const SizedBox(width: 8),
                ]),
                floatingActionButton: const PageTopActionsFab(),
                body: const LeaveScreen(),
              )))
      .then((_) => _changed());
}
