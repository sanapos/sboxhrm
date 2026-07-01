import 'package:flutter/material.dart';

import '../../screens/system_admin/system_admin_helpers.dart';
import '../../utils/responsive_helper.dart';

/// Super Admin dùng layout mobile (drawer + thẻ + filter sheet).
bool adminUseMobileLayout(BuildContext context) =>
    Responsive.isMobile(context);

EdgeInsets adminTabPadding(BuildContext context) =>
    Responsive.contentPadding(context);

/// Bottom sheet bộ lọc trên mobile.
Future<void> showAdminFilterSheet(
  BuildContext context, {
  required Widget child,
  String title = 'Bộ lọc',
  VoidCallback? onApply,
  VoidCallback? onClear,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (onClear != null)
                  TextButton(onPressed: onClear, child: const Text('Xóa lọc')),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              controller: scrollCtrl,
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
          if (onApply != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      onApply();
                      Navigator.pop(ctx);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AdminHelpers.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Áp dụng'),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// Thanh tìm kiếm + lọc gọn cho tab admin trên mobile.
class AdminMobileListToolbar extends StatelessWidget {
  const AdminMobileListToolbar({
    super.key,
    required this.searchController,
    required this.searchHint,
    required this.onSearchChanged,
    this.onOpenFilters,
    this.activeFilterCount = 0,
    this.onRefresh,
    this.onCreate,
    this.createLabel,
    this.stats,
    this.trailing,
  });

  final TextEditingController searchController;
  final String searchHint;
  final VoidCallback onSearchChanged;
  final VoidCallback? onOpenFilters;
  final int activeFilterCount;
  final VoidCallback? onRefresh;
  final VoidCallback? onCreate;
  final String? createLabel;
  final Widget? stats;
  final List<Widget>? trailing;

  @override
  Widget build(BuildContext context) {
    final pad = adminTabPadding(context);
    return Container(
      color: AdminHelpers.surfaceBg,
      padding: EdgeInsets.fromLTRB(pad.left, 10, pad.right, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: AdminHelpers.searchBar(
                  controller: searchController,
                  hint: searchHint,
                  onChanged: onSearchChanged,
                ),
              ),
              if (onOpenFilters != null) ...[
                const SizedBox(width: 8),
                _FilterButton(
                  count: activeFilterCount,
                  onTap: onOpenFilters!,
                ),
              ],
              if (onRefresh != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, size: 22),
                  tooltip: 'Tải lại',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
          if (onCreate != null || (trailing != null && trailing!.isNotEmpty))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onCreate != null)
                    FilledButton.icon(
                      onPressed: onCreate,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(createLabel ?? 'Tạo mới'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AdminHelpers.primary,
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ...?trailing,
                ],
              ),
            ),
          if (stats != null) ...[
            const SizedBox(height: 8),
            stats!,
          ],
        ],
      ),
    );
  }
}

class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: count > 0
                  ? AdminHelpers.primary
                  : Colors.grey.shade300,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tune,
                  size: 18,
                  color: count > 0 ? AdminHelpers.primary : Colors.grey[600]),
              if (count > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AdminHelpers.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$count',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Hàng badge thống kê cuộn ngang.
class AdminMobileStatRow extends StatelessWidget {
  const AdminMobileStatRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: children),
    );
  }
}

/// Dropdown full-width trong filter sheet mobile.
class AdminMobileFilterDropdown<T> extends StatelessWidget {
  const AdminMobileFilterDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700])),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                isExpanded: true,
                value: value,
                items: items,
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Định nghĩa tab trong drawer Super Admin.
class AdminNavItem {
  const AdminNavItem({
    required this.index,
    required this.icon,
    required this.label,
    required this.group,
    this.count,
  });

  final int index;
  final IconData icon;
  final String label;
  final String group;
  final int? count;
}

/// Drawer điều hướng Super Admin trên mobile.
class AdminMobileDrawer extends StatelessWidget {
  const AdminMobileDrawer({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelect,
    this.healthStatus,
    this.onLogout,
  });

  final List<AdminNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final String? healthStatus;
  final VoidCallback? onLogout;

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<AdminNavItem>>{};
    for (final item in items) {
      groups.putIfAbsent(item.group, () => []).add(item);
    }

    return Drawer(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
                20, MediaQuery.paddingOf(context).top + 16, 20, 16),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF334155)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.shield,
                          color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Quản trị hệ thống',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                          Text('SuperAdmin',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (healthStatus != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: healthStatus == 'Healthy'
                          ? Colors.green.withValues(alpha: 0.25)
                          : Colors.red.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          healthStatus == 'Healthy'
                              ? Icons.check_circle
                              : Icons.error,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(healthStatus!,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final group in groups.entries) ...[
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(group.key.toUpperCase(),
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.grey[500],
                            letterSpacing: 0.8)),
                  ),
                  ...group.value.map((item) {
                    final selected = item.index == currentIndex;
                    return ListTile(
                      dense: true,
                      selected: selected,
                      selectedTileColor:
                          AdminHelpers.primary.withValues(alpha: 0.08),
                      leading: Icon(item.icon,
                          size: 22,
                          color: selected
                              ? AdminHelpers.primary
                              : Colors.grey[700]),
                      title: Text(item.label,
                          style: TextStyle(
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: selected
                                  ? AdminHelpers.primary
                                  : Colors.grey[900])),
                      trailing: item.count != null && item.count! > 0
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AdminHelpers.primary
                                    : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text('${item.count}',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: selected
                                          ? Colors.white
                                          : Colors.grey[700])),
                            )
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        onSelect(item.index);
                      },
                    );
                  }),
                ],
              ],
            ),
          ),
          if (onLogout != null)
            SafeArea(
              top: false,
              child: ListTile(
                leading: const Icon(Icons.logout, color: AdminHelpers.danger),
                title: const Text('Đăng xuất',
                    style: TextStyle(color: AdminHelpers.danger)),
                onTap: onLogout,
              ),
            ),
        ],
      ),
    );
  }
}
