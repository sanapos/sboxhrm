import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../utils/responsive_helper.dart';

import 'account_management_screen.dart';
import 'ai_settings_screen.dart';
import 'allowance_settings_screen.dart';

import 'holiday_settings_screen.dart';
import 'insurance_settings_screen.dart';
import 'mobile_attendance_settings_screen.dart';

import 'penalty_settings_screen.dart';
import 'role_permissions_screen.dart';
import 'shift_settings_screen.dart';
import 'system_settings_screen.dart';
import 'tax_settings_screen.dart';
import 'device_management_settings_screen.dart';
import 'google_drive_settings_screen.dart';
import 'product_salary_settings_screen.dart';

class SettingsHubScreen extends StatefulWidget {
  const SettingsHubScreen({super.key});

  /// Static callback for main_layout to handle internal back navigation.
  /// When a sub-screen is active on mobile, this is set to a callback
  /// that resets to the hub menu instead of leaving the hub entirely.
  static VoidCallback? internalBackCallback;

  /// Pending sub-screen index to open when navigating to settings hub.
  /// Set value to trigger navigation, even if already on settings hub.
  static final ValueNotifier<int?> pendingSubIndex = ValueNotifier<int?>(null);

  /// Navigate back from a settings sub-screen.
  /// Uses internalBackCallback if available, otherwise Navigator.maybePop.
  static void goBack(BuildContext context) {
    final cb = internalBackCallback;
    if (cb != null) {
      cb();
    } else {
      Navigator.maybePop(context);
    }
  }

  @override
  State<SettingsHubScreen> createState() => _SettingsHubScreenState();
}

class _SettingsHubScreenState extends State<SettingsHubScreen> {
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    // Consume pending sub-index if set before navigation
    if (SettingsHubScreen.pendingSubIndex.value != null) {
      _selectedIndex = SettingsHubScreen.pendingSubIndex.value;
      SettingsHubScreen.pendingSubIndex.value = null;
    }
    // Listen for future external navigation requests
    SettingsHubScreen.pendingSubIndex.addListener(_onPendingSubIndex);
  }

  void _onPendingSubIndex() {
    final idx = SettingsHubScreen.pendingSubIndex.value;
    if (idx != null && mounted) {
      setState(() => _selectedIndex = idx);
      SettingsHubScreen.pendingSubIndex.value = null;
    }
  }

  @override
  void dispose() {
    SettingsHubScreen.pendingSubIndex.removeListener(_onPendingSubIndex);
    SettingsHubScreen.internalBackCallback = null;
    super.dispose();
  }

  static const _bgColor = Color(0xFFFAFAFA);
  static const _textDark = Color(0xFF0F172A);
  static const _textMuted = Color(0xFF71717A);
  static const _borderColor = Color(0xFFE4E4E7);

  static const List<_SidebarGroup> _groups = [
    _SidebarGroup(
      title: 'Chấm công & Ca',
      icon: Icons.schedule,
      accent: Color(0xFF0F2340),
      items: [
        _SidebarItem(index: 0, icon: Icons.schedule_send, label: 'Thiết lập ca', desc: 'Ca làm việc, vào sớm, đi trễ, về sớm, tăng ca', accent: Color(0xFF0F2340), moduleCode: 'ShiftSetup'),
        _SidebarItem(index: 1, icon: Icons.phone_android, label: 'Chấm công mobile', desc: 'Face ID, GPS, cấp quyền thiết bị, vùng chấm công', accent: Color(0xFF1E3A5F), moduleCode: 'MobileAttendance'),
        _SidebarItem(index: 2, icon: Icons.celebration, label: 'Ngày lễ', desc: 'Ngày nghỉ lễ, hệ số công, cấu hình lịch nghỉ', accent: Color(0xFFEF4444), moduleCode: 'Holiday'),
        _SidebarItem(index: 12, icon: Icons.router, label: 'Máy chấm công', desc: 'Kết nối, quản lý, điều khiển máy chấm công', accent: Color(0xFF1E3A5F), moduleCode: 'Device'),
      ],
    ),
    _SidebarGroup(
      title: 'Chính sách lương',
      icon: Icons.payments,
      accent: Color(0xFF1E3A5F),
      items: [
        _SidebarItem(index: 3, icon: Icons.card_giftcard, label: 'Phụ cấp', desc: 'Phụ cấp cố định, phụ cấp ngày công', accent: Color(0xFFEC4899), moduleCode: 'Allowance'),
        _SidebarItem(index: 4, icon: Icons.gavel, label: 'Phạt', desc: 'Đi trễ, về sớm, tái phạm, kỷ luật', accent: Color(0xFFF97316), moduleCode: 'PenaltySetup'),
        _SidebarItem(index: 5, icon: Icons.health_and_safety, label: 'Bảo hiểm', desc: 'BHXH, BHYT, BHTN, lương cơ sở', accent: Color(0xFF2D5F8B), moduleCode: 'Insurance'),
        _SidebarItem(index: 6, icon: Icons.receipt_long, label: 'Thuế TNCN', desc: 'Bậc thuế, giảm trừ gia cảnh', accent: Color(0xFF0F2340), moduleCode: 'Tax'),
        _SidebarItem(index: 10, icon: Icons.precision_manufacturing, label: 'Lương sản phẩm', desc: 'Nhóm SP, sản phẩm, đơn giá theo bậc', accent: Color(0xFF059669), moduleCode: 'ProductSalary'),
      ],
    ),
    _SidebarGroup(
      title: 'Quản trị hệ thống',
      icon: Icons.admin_panel_settings,
      accent: Color(0xFF1E3A5F),
      items: [
        _SidebarItem(index: 7, icon: Icons.manage_accounts, label: 'Tài khoản', desc: 'Người dùng, kích hoạt, vai trò', accent: Color(0xFF0F2340), moduleCode: 'UserManagement'),
        _SidebarItem(index: 8, icon: Icons.security, label: 'Phân quyền', desc: 'Ma trận quyền, vai trò, module', accent: Color(0xFFEF4444), moduleCode: 'Role'),
        _SidebarItem(index: 9, icon: Icons.settings_suggest, label: 'Hệ thống', desc: 'Giờ kết thúc ngày, tham số vận hành', accent: Color(0xFF334155), moduleCode: 'SystemSettings'),
      ],
    ),
    _SidebarGroup(
      title: 'Tích hợp',
      icon: Icons.hub,
      accent: Color(0xFF1E3A5F),
      items: [
        _SidebarItem(index: 11, icon: Icons.auto_awesome, label: 'Thiết lập AI', desc: 'Gemini, DeepSeek, bật/tắt AI', accent: Color(0xFF0F2340), moduleCode: 'AIGemini'),
        _SidebarItem(index: 15, icon: Icons.cloud_upload, label: 'Google Drive', desc: 'Lưu trữ ảnh, sao lưu dữ liệu lên Drive', accent: Color(0xFF2D5F8B), moduleCode: 'GoogleDrive'),
      ],
    ),
  ];

  Widget _getScreen(int index) {
    switch (index) {
      case 0: return const ShiftSettingsScreen();
      case 1: return const MobileAttendanceSettingsScreen();
      case 2: return const HolidaySettingsScreen();
      case 3: return const AllowanceSettingsScreen();
      case 4: return const PenaltySettingsScreen();
      case 5: return const InsuranceSettingsScreen();
      case 6: return const TaxSettingsScreen();
      case 7: return const AccountManagementScreen();
      case 8: return const RolePermissionsScreen();
      case 9: return const SystemSettingsScreen();
      case 10: return const ProductSalarySettingsScreen();
      case 11: return const AiSettingsScreen();
      case 12: return const DeviceManagementSettingsScreen();
      case 15: return const GoogleDriveSettingsScreen();
      default: return const SizedBox();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Responsive.isMobile(context);

    if (isMobile) {
      // Mobile: show sidebar as full-width list, tapping item navigates to content
      if (_selectedIndex != null) {
        // Set callback so main_layout back button goes to hub menu first
        SettingsHubScreen.internalBackCallback = () {
          setState(() => _selectedIndex = null);
        };
        return _getScreen(_selectedIndex!);
      }
      // No sub-screen active, clear callback
      SettingsHubScreen.internalBackCallback = null;
      return Scaffold(
        backgroundColor: _bgColor,
        body: _buildMobileHome(),
      );
    }

    // Desktop/Tablet: show selected screen directly (same as mobile)
    // Avoid nested Navigator which causes _dependents.isEmpty assertion errors
    if (_selectedIndex != null) {
      SettingsHubScreen.internalBackCallback = () {
        setState(() => _selectedIndex = null);
      };
      return _getScreen(_selectedIndex!);
    }
    SettingsHubScreen.internalBackCallback = null;
    return Scaffold(
      backgroundColor: _bgColor,
      body: _buildOverview(),
    );
  }

  // ===== MOBILE HOME =====
  Widget _buildMobileHome() {
    return CustomScrollView(
      slivers: [
        // Header
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1D4ED8), Color(0xFF0F2340)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.tune, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 10),
                      const Text('Thiết lập HRM', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Quản lý toàn bộ cấu hình hệ thống',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Groups
        ..._groups.expand((g) {
          final filteredItems = _filterItems(g.items);
          if (filteredItems.isEmpty) return <Widget>[];
          return [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                child: Row(
                  children: [
                    Icon(g.icon, size: 14, color: g.accent),
                    const SizedBox(width: 6),
                    Text(g.title.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: g.accent, letterSpacing: 0.5)),
                  ],
                ),
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _buildMobileMenuItem(filteredItems[i]),
                childCount: filteredItems.length,
              ),
            ),
          ];
        }),
        const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
      ],
    );
  }

  Widget _buildMobileMenuItem(_SidebarItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => setState(() => _selectedIndex = item.index),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderColor),
            ),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: item.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.icon, size: 18, color: item.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _textDark)),
                      const SizedBox(height: 2),
                      Text(item.desc, style: const TextStyle(fontSize: 11, color: _textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: item.accent.withValues(alpha: 0.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<_SidebarItem> _filterItems(List<_SidebarItem> items) {
    final authUser = Provider.of<AuthProvider>(context, listen: false).user;
    final isSuperAdmin = authUser?.role == 'SuperAdmin';
    if (isSuperAdmin) return items;
    final permProvider = Provider.of<PermissionProvider>(context, listen: false);
    final allowedModules = authUser?.allowedModules;
    return items.where((item) {
      // Lọc theo gói dịch vụ
      if (allowedModules != null && allowedModules.isNotEmpty && !allowedModules.contains(item.moduleCode)) {
        return false;
      }
      // Lọc theo quyền canView
      if (!permProvider.canView(item.moduleCode)) return false;
      return true;
    }).toList();
  }

  // ===== OVERVIEW CONTENT =====
  Widget _buildOverview() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          _buildOverviewHeader(),
          const SizedBox(height: 24),
          // Quick stats
          _buildQuickStats(),
          const SizedBox(height: 28),
          // Group cards
          ..._groups.map((g) => Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: _buildGroupSection(g),
          )),
        ],
      ),
    );
  }

  Widget _buildOverviewHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1D4ED8), Color(0xFF0F2340)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Color(0x180F172A), blurRadius: 20, offset: Offset(0, 10))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                  child: const Text('HRM Settings Center', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Trung tâm thiết lập hệ thống HRM',
                  style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700, height: 1.2),
                ),
                const SizedBox(height: 8),
                Text(
                  'Quản lý toàn bộ cấu hình ca làm việc, chính sách lương, quản trị hệ thống và tích hợp.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _buildStatBadge(Icons.schedule, '${_groups[0].items.length}', 'Chấm công'),
              _buildStatBadge(Icons.payments, '${_groups[1].items.length}', 'Lương'),
              _buildStatBadge(Icons.admin_panel_settings, '${_groups[2].items.length}', 'Quản trị'),
              _buildStatBadge(Icons.hub, '${_groups[3].items.length}', 'Tích hợp'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatBadge(IconData icon, String count, String label) {
    return Container(
      width: 110,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(height: 8),
          Text(count, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildQuickStats() {
    final totalItems = _groups.fold<int>(0, (sum, g) => sum + g.items.length);
    return Row(
      children: [
        _buildInfoChip(Icons.apps, '$totalItems cấu hình', const Color(0xFF1E3A5F)),
        const SizedBox(width: 12),
        _buildInfoChip(Icons.category, '${_groups.length} nhóm', const Color(0xFF1E3A5F)),
        const SizedBox(width: 12),
        _buildInfoChip(Icons.check_circle_outline, 'Sẵn sàng', const Color(0xFF1E3A5F)),
      ],
    );
  }

  Widget _buildInfoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  Widget _buildGroupSection(_SidebarGroup group) {
    final filteredItems = _filterItems(group.items);
    if (filteredItems.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: group.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(group.icon, color: group.accent, size: 18),
            ),
            const SizedBox(width: 12),
            Text(group.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _textDark)),
            const Spacer(),
            Text('${filteredItems.length} mục', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: group.accent)),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: filteredItems.map((item) => _buildShortcutCard(item)).toList(),
        ),
      ],
    );
  }

  Widget _buildShortcutCard(_SidebarItem item) {
    return SizedBox(
      width: 280,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => setState(() => _selectedIndex = item.index),
          borderRadius: BorderRadius.circular(16),
          hoverColor: item.accent.withValues(alpha: 0.04),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _borderColor),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [item.accent, item.accent.withValues(alpha: 0.7)]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(item.icon, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _textDark)),
                      const SizedBox(height: 3),
                      Text(item.desc, style: const TextStyle(fontSize: 11, color: _textMuted, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, size: 18, color: item.accent.withValues(alpha: 0.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===== DATA CLASSES =====
class _SidebarGroup {
  final String title;
  final IconData icon;
  final Color accent;
  final List<_SidebarItem> items;
  const _SidebarGroup({required this.title, required this.icon, required this.accent, required this.items});
}

class _SidebarItem {
  final int index;
  final IconData icon;
  final String label;
  final String desc;
  final Color accent;
  final String moduleCode;
  const _SidebarItem({required this.index, required this.icon, required this.label, required this.desc, required this.accent, required this.moduleCode});
}
