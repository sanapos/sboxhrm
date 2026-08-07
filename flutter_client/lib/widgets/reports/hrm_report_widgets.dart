import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../utils/branch_filter_helper.dart';
import '../../utils/report_screen_helpers.dart';
import '../../utils/vietnamese_font.dart';
import '../hrm_collapsible_overview.dart';
import '../hrm_mini_stat_chip.dart';
import '../hrm_page_chrome.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Bọc KPI + bộ lọc báo cáo — thu gọn còn 1 hàng như Hồ sơ nhân sự.
class ReportCollapsibleChrome extends StatelessWidget {
  final bool expanded;
  final VoidCallback onToggle;
  final Widget? kpi;
  final Widget filter;
  final List<Widget> betweenKpiAndFilter;

  const ReportCollapsibleChrome({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.filter,
    this.kpi,
    this.betweenKpiAndFilter = const [],
  });

  @override
  Widget build(BuildContext context) {
    return HrmCollapsibleOverview(
      expanded: expanded,
      onToggle: onToggle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (kpi != null) kpi!,
          ...betweenKpiAndFilter,
          filter,
        ],
      ),
    );
  }
}

/// Một chỉ số KPI trên báo cáo.
class ReportKpiItem {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const ReportKpiItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });
}

/// Lưới KPI — nền trắng, viền xanh, chia đều, chiều cao thấp (dùng [HrmStatBar]).
class ReportKpiGrid extends StatelessWidget {
  final List<ReportKpiItem> items;

  const ReportKpiGrid({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return ColoredBox(
      color: Colors.white,
      child: HrmStatBar(
        items: [
          for (final k in items)
            HrmStatItem(
              icon: k.icon,
              label: k.label,
              value: k.value,
            ),
        ],
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        gap: 6,
        valueFontSize: 14,
      ),
    );
  }
}

/// Khung chung: AppBar + nội dung cuộn.
class ReportScreenShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color accentColor;
  final bool canExport;
  final VoidCallback onRefresh;
  final VoidCallback? onExport;
  final Widget child;

  const ReportScreenShell({
    super.key,
    required this.title,
    this.subtitle,
    required this.accentColor,
    this.canExport = false,
    required this.onRefresh,
    this.onExport,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(title),
                style: vietnameseTextStyle(const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold))),
            if (subtitle != null)
              Text(tr(subtitle!),
                  style: vietnameseTextStyle(const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.normal))),
          ],
        ),
        backgroundColor: accentColor,
        foregroundColor: Colors.white,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [accentColor, accentColor.withValues(alpha: 0.85)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          if (canExport && onExport != null)
            IconButton(
              icon: const Icon(Icons.file_download_outlined),
              tooltip: tr('Xuất Excel'),
              onPressed: onExport,
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: onRefresh),
        ],
      ),
      body: child,
    );
  }
}

/// Tab Chi tiết / Theo nhân viên (chỉ team view).
/// [tabs] tùy chọn: mỗi phần tử là (label, icon). Mặc định 2 tab.
class ReportViewModeTabs extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final List<({String label, IconData icon})>? tabs;

  const ReportViewModeTabs({
    super.key,
    required this.index,
    required this.onChanged,
    this.tabs,
  });

  @override
  Widget build(BuildContext context) {
    final items = tabs ??
        const [
          (label: 'Chi tiết', icon: Icons.list_alt),
          (label: 'Theo NV', icon: Icons.people_outline),
        ];
    const brand = HrmPageChrome.primaryNavy;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SegmentedButton<int>(
        segments: [
          for (var i = 0; i < items.length; i++)
            ButtonSegment(
              value: i,
              label: Text(tr(items[i].label),
                  style: vietnameseTextStyle(const TextStyle(fontSize: 12))),
              icon: Icon(items[i].icon, size: 16),
            ),
        ],
        selected: {index},
        onSelectionChanged: (s) => onChanged(s.first),
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return brand;
            }
            return Colors.white;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return const Color(0xFF586064);
          }),
          side: WidgetStateProperty.all(
            BorderSide(color: brand.withValues(alpha: 0.35)),
          ),
        ),
      ),
    );
  }
}

/// Thẻ timeline cho nhân viên (chế độ cá nhân).
class ReportTimelineCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? trailing;
  final String? amount;
  final Color accentColor;
  final Color? statusColor;
  final String? statusLabel;
  final IconData icon;

  const ReportTimelineCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.amount,
    required this.accentColor,
    this.statusColor,
    this.statusLabel,
    this.icon = Icons.description_outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE4E4E7)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: accentColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(tr(title),
                            style: vietnameseTextStyle(const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (trailing != null)
                        Text(tr(trailing!),
                            style: vietnameseTextStyle(TextStyle(
                                fontSize: 11, color: Colors.grey.shade600))),
                    ],
                  ),
                  if (amount != null) ...[
                    const SizedBox(height: 4),
                    Text(tr(amount!),
                        style: vietnameseTextStyle(TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: accentColor))),
                  ],
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(tr(subtitle!),
                        style: vietnameseTextStyle(TextStyle(
                            fontSize: 12, color: Colors.grey.shade700)),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis),
                  ],
                  if (statusLabel != null) ...[
                    const SizedBox(height: 8),
                    _statusChip(statusLabel!, statusColor ?? accentColor),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _statusChip(String label, Color color) {
  return HrmBrandChip(label: label);
}

/// Thẻ nhóm theo nhân viên (tab Theo NV).
class ReportEmployeeSummaryCard extends StatelessWidget {
  final String name;
  final String? meta;
  final String primaryValue;
  final String? secondaryValue;
  final Color accentColor;
  final VoidCallback? onTap;

  const ReportEmployeeSummaryCard({
    super.key,
    required this.name,
    this.meta,
    required this.primaryValue,
    this.secondaryValue,
    required this.accentColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE4E4E7)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: accentColor.withValues(alpha: 0.12),
                child: Text(
                  tr(name.isNotEmpty ? name[0].toUpperCase() : '?'),
                  style: vietnameseTextStyle(TextStyle(
                      color: accentColor, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(name),
                        style: vietnameseTextStyle(const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (meta != null)
                      Text(tr(meta!),
                          style: vietnameseTextStyle(TextStyle(
                              fontSize: 11, color: Colors.grey.shade600))),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(tr(primaryValue),
                      style: vietnameseTextStyle(TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: accentColor))),
                  if (secondaryValue != null)
                    Text(tr(secondaryValue!),
                        style: vietnameseTextStyle(TextStyle(
                            fontSize: 11, color: Colors.grey.shade600))),
                ],
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Bộ lọc chung. [embedded]=true khi nằm trong [ReportCollapsibleChrome]
/// (không còn ExpansionTile lồng — tránh thu gọn kép).
class ReportFilterSection extends StatefulWidget {
  final DateTime from;
  final DateTime to;
  final String datePreset;
  final void Function(DateTime from, DateTime to, String preset) onDateChanged;
  final Widget statusFilter;
  final String? statusSummary;
  final bool showTeamFilters;
  final ReportBranchFilter? branchFilter;
  final String? selectedBranchId;
  final ValueChanged<String?>? onBranchChanged;
  final String empSearch;
  final ValueChanged<String> onEmpSearchChanged;
  final List<String> empSuggestions;
  final VoidCallback onApply;
  final VoidCallback? onClearFilters;
  final bool embedded;
  /// Khi false: không hiện nút Áp dụng (lọc tức thì / auto-load).
  final bool showApplyButton;

  const ReportFilterSection({
    super.key,
    required this.from,
    required this.to,
    required this.datePreset,
    required this.onDateChanged,
    required this.statusFilter,
    this.statusSummary,
    this.showTeamFilters = true,
    this.branchFilter,
    this.selectedBranchId,
    this.onBranchChanged,
    this.empSearch = '',
    required this.onEmpSearchChanged,
    this.empSuggestions = const [],
    required this.onApply,
    this.onClearFilters,
    this.embedded = false,
    this.showApplyButton = true,
  });

  @override
  State<ReportFilterSection> createState() => _ReportFilterSectionState();
}

class _ReportFilterSectionState extends State<ReportFilterSection> {
  bool _expanded = false;

  String _filterSummary() {
    final fmt = DateFormat('dd/MM/yy');
    final parts = <String>[
      ReportDateRangePresets.presetLabel(widget.datePreset),
      '${fmt.format(widget.from)} — ${fmt.format(widget.to)}',
    ];
    if (widget.statusSummary != null && widget.statusSummary!.isNotEmpty) {
      parts.add(widget.statusSummary!);
    }
    if (widget.selectedBranchId != null && widget.branchFilter != null) {
      final match = widget.branchFilter!.branches.where(
        (b) => b['id']?.toString() == widget.selectedBranchId,
      );
      if (match.isNotEmpty) {
        final name = match.first['name']?.toString() ?? '';
        if (name.isNotEmpty) parts.add(name);
      }
    }
    if (widget.empSearch.isNotEmpty) {
      parts.add('NV: ${widget.empSearch}');
    }
    return parts.join(' · ');
  }

  List<Widget> _filterBody(bool hasExtraFilters) {
    return [
      ReportDateRangeFilterBar(
        from: widget.from,
        to: widget.to,
        preset: widget.datePreset,
        compact: true,
        onChanged: widget.onDateChanged,
      ),
      const SizedBox(height: 10),
      widget.statusFilter,
      if (widget.showTeamFilters) ...[
        if (widget.branchFilter != null &&
            BranchFilterHelper.showBranchFilter(
                widget.branchFilter!.branches)) ...[
          const SizedBox(height: 8),
          _branchDropdown(),
        ],
        const SizedBox(height: 8),
        _empSearchField(),
      ],
      const SizedBox(height: 10),
      if (widget.showApplyButton ||
          (widget.onClearFilters != null && hasExtraFilters))
        Row(
          children: [
            if (widget.onClearFilters != null && hasExtraFilters)
              TextButton.icon(
                onPressed: widget.onClearFilters,
                icon: const Icon(Icons.filter_alt_off, size: 15),
                label: Text(tr('Xóa lọc'),
                    style: vietnameseTextStyle(const TextStyle(fontSize: 12))),
              ),
            const Spacer(),
            if (widget.showApplyButton)
              FilledButton.icon(
                icon: const Icon(Icons.search, size: 16),
                label: Text(tr('Áp dụng'),
                    style: vietnameseTextStyle(const TextStyle(fontSize: 13))),
                style: FilledButton.styleFrom(
                  backgroundColor: HrmPageChrome.primaryNavy,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onPressed: widget.onApply,
              ),
          ],
        )
      else if (widget.onClearFilters != null && hasExtraFilters)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: widget.onClearFilters,
            icon: const Icon(Icons.filter_alt_off, size: 15),
            label: Text(tr('Xóa lọc'),
                style: vietnameseTextStyle(const TextStyle(fontSize: 12))),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final hasExtraFilters = widget.empSearch.isNotEmpty ||
        widget.selectedBranchId != null;
    final body = _filterBody(hasExtraFilters);

    if (widget.embedded) {
      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: body,
        ),
      );
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE4E4E7))),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _expanded,
          onExpansionChanged: (v) => setState(() => _expanded = v),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Text(tr('Bộ lọc'),
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            tr(_filterSummary()),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(
            _expanded ? Icons.expand_less : Icons.expand_more,
            color: Colors.grey[600],
            size: 22,
          ),
          children: body,
        ),
      ),
    );
  }

  Widget _branchDropdown() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: widget.selectedBranchId,
          isExpanded: true,
          isDense: true,
          hint: Text(tr('Tất cả chi nhánh'),
              style: vietnameseTextStyle(
                  const TextStyle(fontSize: 13, color: Color(0xFF6B7280)))),
          style: vietnameseTextStyle(
              const TextStyle(fontSize: 13, color: Color(0xFF111827))),
          items: [
            DropdownMenuItem<String?>(
                value: null, child: Text(tr('Tất cả chi nhánh'))),
            ...widget.branchFilter!.branches.map((b) => DropdownMenuItem<String?>(
                  value: b['id']?.toString(),
                  child: Text(tr(b['name']?.toString() ?? ''),
                      overflow: TextOverflow.ellipsis),
                )),
          ],
          onChanged: widget.onBranchChanged,
        ),
      ),
    );
  }

  Widget _empSearchField() {
    return Autocomplete<String>(
      optionsBuilder: (v) {
        if (widget.empSuggestions.isEmpty) return const Iterable<String>.empty();
        if (v.text.isEmpty) return widget.empSuggestions;
        final q = v.text.toLowerCase();
        return widget.empSuggestions.where((s) => s.toLowerCase().contains(q));
      },
      onSelected: widget.onEmpSearchChanged,
      fieldViewBuilder: (context, ctrl, node, _) {
        if (widget.empSearch.isEmpty && ctrl.text.isNotEmpty) ctrl.clear();
        return Container(
          height: 40,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFD1D5DB)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: ctrl,
            focusNode: node,
            style: vietnameseTextStyle(const TextStyle(fontSize: 13)),
            decoration: InputDecoration(
              hintText: tr('Tìm nhân viên...'),
              hintStyle: vietnameseTextStyle(
                  const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
              prefixIcon: const Icon(Icons.person_search_outlined,
                  size: 18, color: Color(0xFF9CA3AF)),
              suffixIcon: widget.empSearch.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        ctrl.clear();
                        widget.onEmpSearchChanged('');
                      })
                  : null,
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 0, horizontal: 4),
              isDense: true,
            ),
            onChanged: widget.onEmpSearchChanged,
          ),
        );
      },
    );
  }
}

/// Phân trang đơn giản.
class ReportPaginationBar extends StatelessWidget {
  final int page;
  final int pageSize;
  final int totalCount;
  final ValueChanged<int> onPageChanged;

  const ReportPaginationBar({
    super.key,
    required this.page,
    required this.pageSize,
    required this.totalCount,
    required this.onPageChanged,
  });

  int get totalPages =>
      totalCount <= 0 ? 1 : ((totalCount - 1) ~/ pageSize) + 1;

  @override
  Widget build(BuildContext context) {
    if (totalCount <= pageSize) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Text(tr('Trang $page/$totalPages | $totalCount bản ghi'),
            style: vietnameseTextStyle(
                TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: page > 1 ? () => onPageChanged(page - 1) : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed:
                page < totalPages ? () => onPageChanged(page + 1) : null,
          ),
        ],
      ),
    );
  }
}

/// Banner phụ cá nhân (ví dụ: phép năm còn lại).
class ReportPersonalInsightBanner extends StatelessWidget {
  final String message;
  final Color color;
  final IconData icon;

  const ReportPersonalInsightBanner({
    super.key,
    required this.message,
    required this.color,
    this.icon = Icons.info_outline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(tr(message),
                style: vietnameseTextStyle(TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: color))),
          ),
        ],
      ),
    );
  }
}

String reportPeriodSubtitle(DateTime from, DateTime to, {bool team = true}) {
  final fmt = DateFormat('dd/MM/yyyy');
  final range = '${fmt.format(from)} - ${fmt.format(to)}';
  return team ? 'Kỳ $range' : 'Lịch sử của bạn | $range';
}

int reportSafeInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? -1;
}

double reportSafeDouble(dynamic v) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v?.toString() ?? '') ?? 0.0;
}

final reportMoneyFmt = NumberFormat('#,##0', 'vi_VN');
final reportDateFmt = DateFormat('dd/MM/yyyy');
