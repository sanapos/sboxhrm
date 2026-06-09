import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../utils/report_screen_helpers.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/vietnamese_font.dart';
import '../hrm_page_chrome.dart';

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

/// Lưới KPI — 2 cột mobile, 4 cột desktop.
class ReportKpiGrid extends StatelessWidget {
  final List<ReportKpiItem> items;

  const ReportKpiGrid({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final cross = Responsive.isMobile(context) ? 2 : items.length.clamp(2, 4);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cross,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: Responsive.isMobile(context) ? 2.4 : 2.8,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) {
          final k = items[i];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: k.color.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: k.color.withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(k.icon, color: k.color, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(k.label,
                          style: vietnameseTextStyle(TextStyle(
                              fontSize: 10, color: Colors.grey.shade700)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      Text(k.value,
                          style: vietnameseTextStyle(TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: k.color)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
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
            Text(title,
                style: vietnameseTextStyle(const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold))),
            if (subtitle != null)
              Text(subtitle!,
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
              tooltip: 'Xuất Excel',
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
class ReportViewModeTabs extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const ReportViewModeTabs({
    super.key,
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SegmentedButton<int>(
        segments: [
          ButtonSegment(
              value: 0,
              label: Text('Chi tiết',
                  style: vietnameseTextStyle(const TextStyle(fontSize: 12))),
              icon: const Icon(Icons.list_alt, size: 16)),
          ButtonSegment(
              value: 1,
              label: Text('Theo NV',
                  style: vietnameseTextStyle(const TextStyle(fontSize: 12))),
              icon: const Icon(Icons.people_outline, size: 16)),
        ],
        selected: {index},
        onSelectionChanged: (s) => onChanged(s.first),
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                        child: Text(title,
                            style: vietnameseTextStyle(const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (trailing != null)
                        Text(trailing!,
                            style: vietnameseTextStyle(TextStyle(
                                fontSize: 11, color: Colors.grey.shade600))),
                    ],
                  ),
                  if (amount != null) ...[
                    const SizedBox(height: 4),
                    Text(amount!,
                        style: vietnameseTextStyle(TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: accentColor))),
                  ],
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!,
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
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(label,
        style: vietnameseTextStyle(TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600, color: color))),
  );
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
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: vietnameseTextStyle(TextStyle(
                      color: accentColor, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: vietnameseTextStyle(const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    if (meta != null)
                      Text(meta!,
                          style: vietnameseTextStyle(TextStyle(
                              fontSize: 11, color: Colors.grey.shade600))),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(primaryValue,
                      style: vietnameseTextStyle(TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: accentColor))),
                  if (secondaryValue != null)
                    Text(secondaryValue!,
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

/// Bộ lọc chung: thu gọn mặc định, bấm mở ra để chỉnh.
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

  @override
  Widget build(BuildContext context) {
    final hasExtraFilters = widget.empSearch.isNotEmpty ||
        widget.selectedBranchId != null;

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
          title: const Text(
            'Bộ lọc',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            _filterSummary(),
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(
            _expanded ? Icons.expand_less : Icons.expand_more,
            color: Colors.grey[600],
            size: 22,
          ),
          children: [
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
                  widget.branchFilter!.branches.isNotEmpty) ...[
                const SizedBox(height: 8),
                _branchDropdown(),
              ],
              const SizedBox(height: 8),
              _empSearchField(),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (widget.onClearFilters != null && hasExtraFilters)
                  TextButton.icon(
                    onPressed: widget.onClearFilters,
                    icon: const Icon(Icons.filter_alt_off, size: 15),
                    label: Text('Xóa lọc',
                        style:
                            vietnameseTextStyle(const TextStyle(fontSize: 12))),
                  ),
                const Spacer(),
                FilledButton.icon(
                  icon: const Icon(Icons.search, size: 16),
                  label: Text('Áp dụng',
                      style: vietnameseTextStyle(const TextStyle(fontSize: 13))),
                  style: FilledButton.styleFrom(
                    backgroundColor: HrmPageChrome.primaryNavy,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                  onPressed: widget.onApply,
                ),
              ],
            ),
          ],
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
          hint: Text('Tất cả chi nhánh',
              style: vietnameseTextStyle(
                  const TextStyle(fontSize: 13, color: Color(0xFF6B7280)))),
          style: vietnameseTextStyle(
              const TextStyle(fontSize: 13, color: Color(0xFF111827))),
          items: [
            const DropdownMenuItem<String?>(
                value: null, child: Text('Tất cả chi nhánh')),
            ...widget.branchFilter!.branches.map((b) => DropdownMenuItem<String?>(
                  value: b['id']?.toString(),
                  child: Text(b['name']?.toString() ?? '',
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
              hintText: 'Tìm nhân viên...',
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
          Text(
            'Trang $page/$totalPages | $totalCount bản ghi',
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
            child: Text(message,
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
