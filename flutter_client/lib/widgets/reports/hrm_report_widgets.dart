import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../utils/branch_filter_helper.dart';
import '../../utils/department_filter_helper.dart';
import '../../utils/report_screen_helpers.dart';
import '../../utils/vietnamese_font.dart';
import '../hrm_collapsible_overview.dart';
import '../hrm_page_chrome.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';
import '../sbox/sbox_basics.dart';
import '../sbox/sbox_report.dart';
import '../sbox/sbox_table.dart';

export '../sbox/sbox_basics.dart' show SboxTone;
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

  /// Dòng phụ dưới số (vd «trên 12 nhân viên»).
  final String? note;

  /// Màu thẻ; bỏ trống → suy từ [color].
  final SboxTone? tone;

  /// Số kỳ này / kỳ trước → hiện «+12% so với kỳ trước».
  final num? current;
  final num? previous;
  final bool higherIsBetter;

  /// Bấm thẻ (vd lọc danh sách theo chỉ số này).
  final VoidCallback? onTap;

  const ReportKpiItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.note,
    this.tone,
    this.current,
    this.previous,
    this.higherIsBetter = true,
    this.onTap,
  });

  SboxTone get resolvedTone {
    if (tone != null) return tone!;
    final c = color.toARGB32();
    bool near(Color x) => x.toARGB32() == c;
    if (near(SboxColors.success) || near(Colors.green)) return SboxTone.success;
    if (near(SboxColors.danger) || near(Colors.red)) return SboxTone.danger;
    if (near(SboxColors.warning) || near(Colors.orange) || near(Colors.amber)) return SboxTone.warning;
    if (near(SboxColors.violet) || near(Colors.purple)) return SboxTone.violet;
    if (near(Colors.blueGrey) || near(SboxColors.slate500) || near(SboxColors.slate600)) return SboxTone.neutral;
    return SboxTone.brand;
  }

  SboxKpi toSbox() => SboxKpi(
        label: label,
        value: value,
        icon: icon,
        tone: resolvedTone,
        note: note,
        current: current,
        previous: previous,
        higherIsBetter: higherIsBetter,
        compareLabel: current != null && previous != null ? 'kỳ trước' : null,
        onTap: onTap,
      );
}

/// Lưới KPI dạng thẻ (icon màu + số lớn + dòng phụ) — điện thoại 2 cột, máy tính 4–6 cột.
class ReportKpiGrid extends StatelessWidget {
  final List<ReportKpiItem> items;

  const ReportKpiGrid({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: SboxKpiStrip(items: [for (final k in items) k.toSbox()]),
      ),
    );
  }
}

/// Dashboard đầu báo cáo: thẻ KPI + biểu đồ (ẩn/hiện biểu đồ, nhớ trạng thái trong phiên).
class ReportDashboard extends StatefulWidget {
  const ReportDashboard({
    super.key,
    required this.kpis,
    this.charts = const [],
    this.title = 'Tổng quan',
    this.subtitle,
    this.storageKey,
  });

  final List<ReportKpiItem> kpis;
  final List<Widget> charts;
  final String title;
  final String? subtitle;

  /// Khóa nhớ trạng thái ẩn/hiện biểu đồ (vd 'penalty').
  final String? storageKey;

  static final Map<String, bool> _chartsOpen = {};

  @override
  State<ReportDashboard> createState() => _ReportDashboardState();
}

class _ReportDashboardState extends State<ReportDashboard> {
  late bool _open = ReportDashboard._chartsOpen[widget.storageKey ?? ''] ?? true;

  void _toggle() {
    setState(() => _open = !_open);
    if (widget.storageKey != null) ReportDashboard._chartsOpen[widget.storageKey!] = _open;
  }

  @override
  Widget build(BuildContext context) {
    final charts = widget.charts;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.insights_rounded, size: 18, color: SboxColors.brand600),
          const SizedBox(width: 6),
          Text(tr(widget.title),
              style: vietnameseTextStyle(const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: SboxColors.slate900))),
          const SizedBox(width: 8),
          Expanded(
            child: widget.subtitle == null
                ? const SizedBox.shrink()
                : Text(tr(widget.subtitle!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: vietnameseTextStyle(const TextStyle(fontSize: 12, color: SboxColors.slate500))),
          ),
          if (charts.isNotEmpty)
            TextButton.icon(
              onPressed: _toggle,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: Icon(_open ? Icons.expand_less_rounded : Icons.bar_chart_rounded, size: 18),
              label: Text(tr(_open ? 'Ẩn biểu đồ' : 'Xem biểu đồ'), style: const TextStyle(fontSize: 12)),
            ),
        ]),
        const SizedBox(height: 6),
        SboxInsightPanel(
          bottomGap: 0,
          kpis: [for (final k in widget.kpis) k.toSbox()],
          charts: _open ? charts : const [],
        ),
      ]),
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
                    fontSize: 18, fontWeight: FontWeight.bold))),
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
            return SboxColors.slate600;
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
    // Thẻ gọn: 1 hàng tiêu đề + ngày, 1 hàng số tiền + trạng thái, ghi chú tối đa 2 dòng.
    final sc = statusColor ?? accentColor;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SboxColors.slate200),
      ),
      padding: const EdgeInsets.fromLTRB(10, 9, 12, 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, color: accentColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(tr(title),
                          style: vietnameseTextStyle(const TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700, color: SboxColors.slate900)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (trailing != null)
                      Text(tr(trailing!),
                          style: vietnameseTextStyle(const TextStyle(
                              fontSize: 11.5, color: SboxColors.slate500))),
                  ],
                ),
                if (amount != null || statusLabel != null) ...[
                  const SizedBox(height: 3),
                  Row(children: [
                    if (amount != null)
                      Expanded(
                        child: Text(tr(amount!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: vietnameseTextStyle(TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w800, color: accentColor))),
                      )
                    else
                      const Spacer(),
                    if (statusLabel != null) _statusChip(statusLabel!, sc),
                  ]),
                ],
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(tr(subtitle!),
                      style: vietnameseTextStyle(const TextStyle(
                          fontSize: 12, color: SboxColors.slate600)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _statusChip(String label, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Text(tr(label),
        style: vietnameseTextStyle(TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color))),
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
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: SboxColors.slate200),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
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
                              fontSize: 11, color: SboxColors.slate600))),
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
                            fontSize: 11, color: SboxColors.slate600))),
                ],
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, color: SboxColors.slate400, size: 20),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Chi nhánh + phòng ban cạnh nhau (ẩn từng dropdown khi chỉ có 1 lựa chọn).
class ReportOrgFilterRow extends StatelessWidget {
  final ReportBranchFilter orgFilter;
  final String? selectedBranchId;
  final ValueChanged<String?>? onBranchChanged;
  final String? selectedDepartmentId;
  final ValueChanged<String?>? onDepartmentChanged;
  final bool dense;

  const ReportOrgFilterRow({
    super.key,
    required this.orgFilter,
    this.selectedBranchId,
    this.onBranchChanged,
    this.selectedDepartmentId,
    this.onDepartmentChanged,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    final showBranch =
        BranchFilterHelper.showBranchFilter(orgFilter.branches);
    final showDept =
        DepartmentFilterHelper.showDepartmentFilter(orgFilter.departments);
    if (!showBranch && !showDept) return const SizedBox.shrink();

    final branch = showBranch
        ? _dropdown(
            icon: Icons.account_tree_outlined,
            value: _validId(selectedBranchId, orgFilter.branches),
            allLabel: 'Tất cả chi nhánh',
            items: orgFilter.branches,
            onChanged: onBranchChanged,
          )
        : null;
    final dept = showDept
        ? _dropdown(
            icon: Icons.business_outlined,
            value: _validId(selectedDepartmentId, orgFilter.departments),
            allLabel: 'Tất cả phòng ban',
            items: orgFilter.departments,
            onChanged: onDepartmentChanged,
          )
        : null;

    if (branch != null && dept != null) {
      return Row(
        children: [
          Expanded(child: branch),
          const SizedBox(width: 8),
          Expanded(child: dept),
        ],
      );
    }
    return branch ?? dept!;
  }

  String? _validId(String? id, List<Map<String, dynamic>> items) {
    if (id == null) return null;
    final ok = items.any((e) => e['id']?.toString() == id);
    return ok ? id : null;
  }

  Widget _dropdown({
    required IconData icon,
    required String? value,
    required String allLabel,
    required List<Map<String, dynamic>> items,
    required ValueChanged<String?>? onChanged,
  }) {
    return Container(
      height: dense ? 36 : 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: SboxColors.slate50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SboxColors.slate200),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: SboxColors.slate500),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: value,
                isExpanded: true,
                isDense: true,
                hint: Text(tr(allLabel),
                    style: vietnameseTextStyle(const TextStyle(
                        fontSize: 13, color: SboxColors.slate500))),
                style: vietnameseTextStyle(
                    const TextStyle(fontSize: 13, color: SboxColors.slate900)),
                items: [
                  DropdownMenuItem<String?>(
                      value: null, child: Text(tr(allLabel))),
                  ...items.map((e) => DropdownMenuItem<String?>(
                        value: e['id']?.toString(),
                        child: Text(tr(e['name']?.toString() ?? ''),
                            overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
        ],
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
  final String? selectedDepartmentId;
  final ValueChanged<String?>? onDepartmentChanged;
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
    this.selectedDepartmentId,
    this.onDepartmentChanged,
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
    if (widget.selectedDepartmentId != null && widget.branchFilter != null) {
      final match = widget.branchFilter!.departments.where(
        (d) => d['id']?.toString() == widget.selectedDepartmentId,
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
            (BranchFilterHelper.showBranchFilter(
                    widget.branchFilter!.branches) ||
                DepartmentFilterHelper.showDepartmentFilter(
                    widget.branchFilter!.departments))) ...[
          const SizedBox(height: 8),
          ReportOrgFilterRow(
            orgFilter: widget.branchFilter!,
            selectedBranchId: widget.selectedBranchId,
            onBranchChanged: widget.onBranchChanged,
            selectedDepartmentId: widget.selectedDepartmentId,
            onDepartmentChanged: widget.onDepartmentChanged,
          ),
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
        widget.selectedBranchId != null ||
        widget.selectedDepartmentId != null;
    final body = _filterBody(hasExtraFilters);

    if (widget.embedded) {
      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: SboxColors.slate200)),
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
        border: Border(bottom: BorderSide(color: SboxColors.slate200)),
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
            style: TextStyle(fontSize: 12, color: SboxColors.slate600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(
            _expanded ? Icons.expand_less : Icons.expand_more,
            color: SboxColors.slate600,
            size: 22,
          ),
          children: body,
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
            border: Border.all(color: SboxColors.slate300),
            borderRadius: BorderRadius.circular(10),
          ),
          child: TextField(
            controller: ctrl,
            focusNode: node,
            style: vietnameseTextStyle(const TextStyle(fontSize: 13)),
            decoration: InputDecoration(
              hintText: tr('Tìm nhân viên...'),
              hintStyle: vietnameseTextStyle(
                  const TextStyle(fontSize: 12, color: SboxColors.slate400)),
              prefixIcon: const Icon(Icons.person_search_outlined,
                  size: 18, color: SboxColors.slate400),
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
    return SboxPager(page: page, pageSize: pageSize, total: totalCount, onPage: onPageChanged);
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
