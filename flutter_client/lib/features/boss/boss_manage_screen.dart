import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../screens/account_management_screen.dart';
import '../../screens/attendance_by_shift_screen.dart';
import '../../screens/attendance_summary_screen.dart';
import '../../screens/department_screen.dart';
import '../../screens/device_users_screen.dart';
import '../../screens/employees_screen.dart';
import '../../screens/feedback_screen.dart';
import '../../screens/payroll_screen.dart';
import '../../screens/salary_settings_screen.dart';
import '../../screens/schedule_approval_screen.dart';
import '../../screens/pos_products_screen.dart';
import '../../screens/pos_supplier_list_screen.dart';
import '../../screens/role_permissions_screen.dart';
import '../../screens/settings_hub_screen.dart';
import '../../screens/shift_hub/shift_hub_screen.dart';
import '../../screens/staff/staff_nav.dart';
import '../../screens/warehouse/wh_mobile_nav.dart';
import '../../screens/work/work_hub_screen.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/permission_navigation.dart';
import '../../utils/store_role_helper.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../../widgets/sbox/sbox_basics.dart';
import '../../widgets/warehouse/wh_doc_type.dart';
import 'boss_staff_today_screen.dart';
import 'boss_vouchers_screen.dart';

/// Một ô chức năng của tab «Quản lý». [moduleCode] quyết định ẩn / hiện theo gói dịch vụ và quyền.
class _BossTool {
  const _BossTool(this.moduleCode, this.title, this.icon, this.onOpen);

  final String moduleCode;
  final String title;
  final IconData icon;
  final void Function(BuildContext context) onOpen;
}

void _pushPos(BuildContext context, Widget child) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (_) => PosHubScope.pushed(child: child)));

final _sections = <(String, List<_BossTool>)>[
  (
    'Hàng hóa & kho',
    [
      _BossTool('PosProducts', 'Hàng hóa', Icons.inventory_2_rounded,
          (c) => _pushPos(c, const PosProductsScreen())),
      _BossTool('PosPurchaseReceipts', 'Nhập hàng', Icons.local_shipping_rounded,
          (c) => WhMobileNav.openList(c, WhDocType.purchaseReceipt)),
      _BossTool('PosStockCounts', 'Kiểm kho', Icons.fact_check_rounded,
          (c) => WhMobileNav.openList(c, WhDocType.stockCount)),
      _BossTool('PosPurchaseReceipts', 'Nhà cung cấp', Icons.storefront_rounded,
          (c) => _pushPos(c, const PosSupplierListScreen())),
      _BossTool('PosPurchaseReturns', 'Trả hàng nhập', Icons.assignment_return_rounded,
          (c) => WhMobileNav.openList(c, WhDocType.purchaseReturn)),
      _BossTool('PosDamageIssues', 'Xuất hủy', Icons.delete_forever_rounded,
          (c) => WhMobileNav.openList(c, WhDocType.damageIssue)),
      _BossTool('PosInternalUseIssues', 'Dùng nội bộ', Icons.build_rounded,
          (c) => WhMobileNav.openList(c, WhDocType.internalUseIssue)),
    ],
  ),
  (
    'Chấm công & lương',
    [
      _BossTool('Attendance', 'Hôm nay', Icons.how_to_reg_rounded,
          (c) => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => const BossStaffTodayScreen()))),
      _BossTool('DeviceUser', 'Nhân sự chấm công', Icons.fingerprint_rounded,
          (c) => openStaffPage(c, title: 'Nhân sự chấm công', child: const DeviceUsersScreen())),
      _BossTool('AttendanceSummary', 'Tổng hợp chấm công', Icons.table_chart_rounded,
          (c) => openStaffPage(c, title: 'Tổng hợp chấm công', child: const AttendanceSummaryScreen())),
      _BossTool('AttendanceByShift', 'Tổng hợp theo ca', Icons.view_timeline_rounded,
          (c) => openStaffPage(c, title: 'Tổng hợp chấm công theo ca', child: const AttendanceByShiftScreen())),
      _BossTool('Payroll', 'Bảng lương', Icons.payments_rounded,
          (c) => openStaffPage(c, title: 'Bảng lương', child: const PayrollScreen())),
    ],
  ),
  (
    'Nhân viên',
    [
      _BossTool('WorkSchedule', 'Xếp lịch', Icons.calendar_month_rounded,
          (c) => openStaffPage(c, title: 'Xếp lịch', child: const ShiftHubScreen(initialTab: 'board'))),
      _BossTool('Task', 'Công việc', Icons.task_alt_rounded,
          (c) => openStaffPage(c, title: 'Công việc', child: const WorkHubScreen())),
      _BossTool('Feedback', 'Ý kiến', Icons.forum_rounded,
          (c) => openStaffPage(c, title: 'Ý kiến nhân viên', child: const FeedbackScreen())),
      _BossTool('Employee', 'Hồ sơ', Icons.badge_rounded,
          (c) => openStaffPage(c, title: 'Hồ sơ nhân viên', child: const EmployeesScreen())),
    ],
  ),
  (
    'Cửa hàng',
    [
      _BossTool('UserManagement', 'Tài khoản', Icons.manage_accounts_rounded,
          (c) => openStaffPage(c, title: 'Tài khoản nhân viên', child: const AccountManagementScreen())),
      _BossTool('Role', 'Phân quyền', Icons.security_rounded,
          (c) => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => const RolePermissionsScreen()))),
      _BossTool('SettingsHub', 'Thiết lập', Icons.tune_rounded,
          (c) => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => const SettingsHubScreen()))),
    ],
  ),
  (
    'Tiền',
    [
      _BossTool('CashTransaction', 'Phiếu thu chi', Icons.receipt_long_rounded,
          (c) => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => const _BossVouchersPage()))),
    ],
  ),
];

/// Thiết lập SBOX mở khi có quyền một trong các mục thiết lập, không chỉ quyền riêng của hub (như menu app chính).
bool _canOpen(BuildContext context, String moduleCode, {required bool listen}) {
  if (moduleCode != 'SettingsHub') return staffCanOpen(context, moduleCode, listen: listen);
  final user = (listen ? context.watch<AuthProvider>() : context.read<AuthProvider>()).user;
  return PermissionNavigation.canAccessModule(
    moduleCode,
    allowedModules: user?.allowedModules,
    perm: listen ? context.watch<PermissionProvider>() : context.read<PermissionProvider>(),
    role: user?.role,
  );
}

/// Màn không có ô riêng nhưng được nút trong màn khác mở tới (vd «Thiết lập lương» ở Bảng lương).
final _linkedTools = <_BossTool>[
  _BossTool('SalarySettings', 'Thiết lập lương', Icons.price_change_rounded,
      (c) => openStaffPage(c, title: 'Thiết lập lương', child: const SalarySettingsScreen())),
  _BossTool('Department', 'Phòng ban', Icons.business_rounded,
      (c) => openStaffPage(c, title: 'Phòng ban', child: const DepartmentScreen())),
  _BossTool('ScheduleApproval', 'Duyệt lịch làm việc', Icons.assignment_turned_in_rounded,
      (c) => openStaffPage(c, title: 'Duyệt lịch làm việc', child: const ScheduleApprovalScreen())),
];

/// Mở màn theo mã chức năng: các màn dùng chung nhờ khung app mở màn khác qua [NavigationNotifier],
/// app BOSS không có MainLayout nên [BossShell] chuyển yêu cầu về đây.
void openBossModule(BuildContext context, String moduleCode) {
  void toast(String m) => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(tr(m))));
  _BossTool? tool;
  for (final t in [for (final s in _sections) ...s.$2, ..._linkedTools]) {
    if (t.moduleCode == moduleCode) {
      tool = t;
      break;
    }
  }
  if (tool == null) return toast('Chức năng này chưa có trên SBOX BOSS.');
  if (!_canOpen(context, moduleCode, listen: false)) {
    return toast('Chưa có trong gói dịch vụ hoặc chưa được cấp quyền.');
  }
  tool.onOpen(context);
}

/// SBOX BOSS — tab «Quản lý»: lối vào các màn điều hành có sẵn (hàng hóa, kho, nhân viên, cửa hàng, tiền).
/// Mục nào gói dịch vụ / quyền không có thì tự ẩn.
class BossManageScreen extends StatelessWidget {
  const BossManageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final perm = context.watch<PermissionProvider>();
    final auth = context.watch<AuthProvider>();
    // Danh sách gói rỗng = chưa tải được (mất mạng lúc đăng nhập), không phải gói không có gì.
    final modulesMissing = auth.user?.allowedModules?.isEmpty ?? true;
    if (perm.loadFailed || (modulesMissing && !StoreRoleHelper.bypassesPackageFilter(auth.user?.role))) {
      return SboxEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Không tải được quyền',
        message: 'Kiểm tra kết nối rồi thử lại.',
        action: SboxButton(
          label: 'Thử lại',
          onPressed: () {
            auth.refreshAllowedModules();
            perm.loadPermissions(role: auth.user?.role);
          },
        ),
      );
    }
    if (!perm.isLoaded) return const SboxLoading();
    final visible = [
      for (final s in _sections)
        (s.$1, [for (final t in s.$2) if (_canOpen(context, t.moduleCode, listen: true)) t]),
    ].where((s) => s.$2.isNotEmpty).toList();
    if (visible.isEmpty) {
      return const SboxEmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Chưa có trong gói dịch vụ',
        message: 'Gói dịch vụ của cửa hàng chưa có chức năng này. Liên hệ đại lý để nâng cấp gói.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(SboxSpace.lg, SboxSpace.lg, SboxSpace.lg, 96),
      children: [
        for (final s in visible) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: SboxSpace.sm),
            child: Text(tr(s.$1), style: SboxType.titleSmStyle()),
          ),
          GridView.extent(
            maxCrossAxisExtent: 130,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: SboxSpace.sm,
            crossAxisSpacing: SboxSpace.sm,
            childAspectRatio: 0.95,
            children: [for (final t in s.$2) _ToolTile(tool: t)],
          ),
          const SizedBox(height: SboxSpace.lg),
        ],
      ],
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.tool});

  final _BossTool tool;

  @override
  Widget build(BuildContext context) => SboxCard(
        onTap: () => tool.onOpen(context),
        padding: const EdgeInsets.all(SboxSpace.sm),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: SboxTone.brand.bg, borderRadius: SboxRadius.mdAll),
            child: Icon(tool.icon, color: SboxTone.brand.fg),
          ),
          const SizedBox(height: SboxSpace.sm),
          Text(
            tr(tool.title),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SboxType.bodyStrong(),
          ),
        ]),
      );
}

/// Phiếu thu chi mở từ tab «Quản lý», nút ＋ tạo phiếu rồi tải lại danh sách.
class _BossVouchersPage extends StatefulWidget {
  const _BossVouchersPage();

  @override
  State<_BossVouchersPage> createState() => _BossVouchersPageState();
}

class _BossVouchersPageState extends State<_BossVouchersPage> {
  int _tick = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: SboxColors.page,
        appBar: AppBar(
          backgroundColor: SboxColors.brand700,
          foregroundColor: SboxColors.white,
          title: Text(tr('Phiếu thu chi')),
        ),
        body: BossVouchersScreen(refreshTick: _tick),
        floatingActionButton: FloatingActionButton(
          tooltip: tr('Tạo phiếu'),
          backgroundColor: SboxColors.brand600,
          foregroundColor: SboxColors.white,
          onPressed: () async {
            if (await showBossCreateSheet(context) && mounted) setState(() => _tick++);
          },
          child: const Icon(Icons.add_rounded),
        ),
      );
}
